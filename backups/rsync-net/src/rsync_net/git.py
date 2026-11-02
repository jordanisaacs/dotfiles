"""Source-local machine GPG setup and a pipe-only keyring-backed GPG adapter."""

import argparse
import fcntl
import json
import os
import re
import secrets
import stat
import subprocess
import sys
from pathlib import Path

from rsync_net import enrollment
from rsync_net.data import CONFIG


class GitError(ValueError):
    """Incomplete or unsafe local Git identity setup."""


def require(condition, message):
    if not condition:
        raise GitError(message)


def descriptor(path):
    value = json.loads(Path(path).read_text())
    require(
        isinstance(value, dict)
        and set(value)
        == {
            "schemaVersion",
            "device",
            "home",
            "userId",
            "lookupCommand",
            "storeCommand",
            "bindings",
            "manifest",
        }
        and value["schemaVersion"] == 1,
        "invalid Git identity descriptor",
    )
    require(
        re.fullmatch(r"[a-z][a-z0-9_-]{0,30}", value["device"]),
        "invalid machine identity name",
    )
    require(
        isinstance(value["userId"], str)
        and value["userId"]
        and not any(c in value["userId"] for c in "\n\r\x00"),
        "invalid machine GPG user ID",
    )
    for field in ("lookupCommand", "storeCommand"):
        command = value[field]
        require(
            isinstance(command, list)
            and command
            and all(isinstance(a, str) and "\x00" not in a for a in command)
            and Path(command[0]).is_absolute(),
            "keyring commands must be explicit native argv",
        )
    require(
        isinstance(value["bindings"], dict) and value["bindings"],
        "machine Git identity needs an enrolled Git binding",
    )
    for binding in value["bindings"].values():
        require(
            set(binding) == {"principal", "device"}
            and binding["device"] == value["device"],
            "Git bindings must use this machine identity",
        )
        principal = next(
            (
                p
                for p in value["manifest"]["principals"]
                if p["name"] == binding["principal"]
            ),
            None,
        )
        require(
            principal is not None and principal["backend"] == "git",
            "Git identity binding is not an enrolled Git principal",
        )
    value["home"] = str(enrollment.private_location(Path(value["home"])))
    return value


def private_home(spec, *, create=False):
    home = enrollment.private_location(Path(spec["home"]))
    if create:
        enrollment.private_parent(home / ".setup.lock")
    require(
        home.is_dir()
        and home.stat().st_uid == os.getuid()
        and stat.S_IMODE(home.stat().st_mode) & 0o077 == 0,
        "machine GPG home must be user-owned and private",
    )
    return home


def lookup(spec):
    result = subprocess.run(
        spec["lookupCommand"], input=b"", capture_output=True, timeout=60, check=False
    )
    require(result.returncode in (0, 1), "machine GPG keyring lookup failed")
    password = result.stdout.rstrip(b"\r\n")
    require(
        not password
        or (
            result.returncode == 0
            and 16 <= len(password) <= 512
            and b"\n" not in password
            and b"\r" not in password
            and b"\x00" not in password
        ),
        "invalid machine GPG keyring item",
    )
    return password


def native(gpg, home, arguments, *, password=None, input=b""):
    command = [gpg, "--homedir", str(home), "--batch", "--yes"]
    descriptors = []
    try:
        if password is not None:
            read_fd, write_fd = os.pipe()
            descriptors.append(read_fd)
            try:
                os.write(write_fd, password + b"\n")
            finally:
                os.close(write_fd)
            command += ["--pinentry-mode", "loopback", "--passphrase-fd", str(read_fd)]
        result = subprocess.run(
            [*command, *arguments],
            input=input,
            capture_output=True,
            pass_fds=tuple(descriptors),
            timeout=60,
            check=False,
        )
        require(
            result.returncode == 0,
            "native machine GPG operation failed; existing keys and keyring state were retained",
        )
        return result.stdout
    finally:
        for descriptor in descriptors:
            os.close(descriptor)


def primary_fingerprint(listing):
    keys, primary = [], False
    for line in listing.decode().splitlines():
        fields = line.split(":")
        if fields[0] == "sec":
            require(
                fields[14] in ("", "+"),
                "machine identity must have local private key material",
            )
            primary = True
        elif fields[0] == "ssb":
            primary = False
        elif fields[0] == "fpr" and primary:
            keys.append(fields[9])
            primary = False
    require(len(keys) <= 1, "machine GPG home contains multiple private identities")
    return keys[0] if keys else None


def setup(path, manifest, *, gpg="gpg"):
    spec = descriptor(path)
    require(
        spec["manifest"] == manifest,
        "Git identity descriptor differs from authoritative public policy; activate Home Manager first",
    )
    home = private_home(spec, create=True)
    lock = home / ".setup.lock"
    with open(
        lock, "a", opener=lambda p, flags: os.open(p, flags | os.O_NOFOLLOW, 0o600)
    ) as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        listing = native(gpg, home, ["--with-colons", "--list-secret-keys"])
        fingerprint = primary_fingerprint(listing)
        password = lookup(spec)
        if not password:
            require(
                fingerprint is None,
                "machine GPG key exists but its keyring password is missing; it will not be regenerated",
            )
            password = secrets.token_urlsafe(48).encode()
            stored = subprocess.run(
                spec["storeCommand"],
                input=password + b"\n",
                capture_output=True,
                timeout=60,
                check=False,
            )
            require(
                stored.returncode == 0 and lookup(spec) == password,
                "machine GPG password was not verified in the keyring; no key was generated",
            )
        created = fingerprint is None
        if created:
            native(
                gpg,
                home,
                ["--quick-generate-key", spec["userId"], "ed25519", "sign", "0"],
                password=password,
            )
            listing = native(gpg, home, ["--with-colons", "--list-secret-keys"])
            fingerprint = primary_fingerprint(listing)
        require(fingerprint is not None, "machine GPG identity was not generated")
        require(
            any(
                line.split(":")[0] == "uid" and line.split(":")[9] == spec["userId"]
                for line in listing.decode().splitlines()
            ),
            "existing machine GPG user ID differs; no key was replaced",
        )
        if not any(
            line.startswith("ssb:") and "e" in line.split(":")[11]
            for line in listing.decode().splitlines()
        ):
            native(
                gpg,
                home,
                ["--quick-add-key", fingerprint, "cv25519", "encrypt", "0"],
                password=password,
            )
        members = {b["principal"] for b in spec["bindings"].values()}
        recipients = sorted(
            {
                r
                for p in manifest["principals"]
                if p["name"] in members
                for r in p["recovery"]["recipients"]
            }
        )
        for recipient in recipients:
            require(
                recipient != fingerprint,
                "hardware recovery must be independent of the machine identity",
            )
            exported = subprocess.run(
                [gpg, "--batch", "--export", recipient],
                capture_output=True,
                timeout=30,
                check=False,
            )
            require(
                exported.returncode == 0 and exported.stdout,
                "recovery public certificate is unavailable in the default public keyring",
            )
            native(gpg, home, ["--import"], input=exported.stdout)
        # Exercise the protected secret key without any hardware identity in
        # this GNUPGHOME. A wrong/lost keyring item must not appear successful.
        signature = native(
            gpg,
            home,
            ["--local-user", fingerprint, "--detach-sign"],
            password=password,
            input=b"rsync-net machine identity setup\n",
        )
        require(bool(signature), "machine GPG signing verification failed")
        certificate = native(gpg, home, ["--armor", "--export", fingerprint]).decode()
        lines = [
            "{",
            "  # Public machine GPG enrollment generated by rsync-net git setup.",
        ]
        for principal in sorted(members):
            lines.append(
                "  rsyncNet.principals."
                + enrollment.nix_string(principal)
                + ".devices."
                + enrollment.nix_string(spec["device"])
                + ".gpgFingerprint = "
                + enrollment.nix_string(fingerprint)
                + ";"
            )
        lines += ["}", ""]
        for filename, content in (
            ("public-key.asc", certificate),
            ("enrollment.nix", "\n".join(lines)),
        ):
            target = home / filename
            require(not target.is_symlink(), "machine public artifact is a symlink")
            if not target.exists() or target.read_text() != content:
                target.write_text(content)
                target.chmod(0o600)
        return {
            "schemaVersion": 1,
            "operation": "machine-git-identity-setup",
            "device": spec["device"],
            "fingerprint": fingerprint,
            "localKeyCreated": created,
            "gpgHome": str(home),
            "publicModule": str(home / "enrollment.nix"),
            "publicCertificate": str(home / "public-key.asc"),
            "recoveryRecipients": recipients,
            "serverMutationPerformed": False,
        }


def gpg_main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    known, arguments = parser.parse_known_args()
    try:
        spec = descriptor(known.config)
        home = private_home(spec)
        gpg = CONFIG.get("gpg", "gpg")
        command = [gpg, "--homedir", str(home), "--pinentry-mode", "loopback"]
        # gcrypt supplies its *pack encryption password* through fd 3. Keep
        # that fd and every status/output fd intact; never replace that secret
        # with the machine private-key password.
        if not any(
            a == "--passphrase-fd" or a.startswith("--passphrase-fd=")
            for a in arguments
        ):
            password = lookup(spec)
            require(
                bool(password), "machine GPG password is unavailable in the keyring"
            )
            read_fd, write_fd = os.pipe()
            try:
                os.write(write_fd, password + b"\n")
            finally:
                os.close(write_fd)
            os.set_inheritable(read_fd, True)
            command += ["--passphrase-fd", str(read_fd)]
        os.execvp(gpg, [*command, *arguments])
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print("rsync-net-gpg: " + str(error), file=sys.stderr)
        return 2
