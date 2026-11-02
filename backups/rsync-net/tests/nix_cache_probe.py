"""Exercise the generated per-device Nix SSH commands with isolated native stores.

Nix's special localhost transport runs the real serve protocol directly. The
provider VM separately proves OpenSSH authentication, UID and filesystem scope.
All signing keys and store data here are disposable.
"""

import argparse
import json
import os
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlencode

from rsync_net import cli as rsync_net


def build_request(command, derivation, environment, *, read_only):
    """Send an actual BuildPaths request; CLI errors do not test the server."""

    def number(value):
        return struct.pack("<Q", value)

    value = derivation.encode()
    string = number(len(value)) + value + b"\0" * (-len(value) % 8)
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
    )
    try:
        process.stdin.write(number(0x390C9DEB) + number(0x207))
        process.stdin.flush()
        greeting = process.stdout.read(16)
        assert len(greeting) == 16, process.stderr.read().decode()
        magic, version = struct.unpack("<QQ", greeting)
        assert magic == 0x5452EECB and version >> 8 == 2 and version >= 0x207, greeting
        process.stdin.write(number(6) + number(1) + string + number(0) * 6)
        process.stdin.flush()
        if not read_only:
            status = struct.unpack("<Q", process.stdout.read(8))[0]
            size = struct.unpack("<Q", process.stdout.read(8))[0]
            message = process.stdout.read(size).decode()
            process.stdout.read(-size % 8)
            assert status != 0 and "isn't a local store" in message, message
        process.stdin.close()
        process.wait(timeout=10)
        error = process.stderr.read().decode()
        if read_only:
            assert (
                process.returncode != 0 and "building paths is not allowed" in error
            ), error
        else:
            assert process.returncode == 0, error
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    manifest = rsync_net.validate(json.loads(args.manifest.read_text()))
    principal = next(p for p in manifest["principals"] if p["backend"] == "nix-cache")
    commands = rsync_net.authorization(manifest, principal).splitlines()
    with tempfile.TemporaryDirectory(prefix="nix-ssh-cache-") as temporary:
        root = Path(temporary)
        cache = root / "cache"
        environment = os.environ | {
            "NIX_CACHE_HOME": str(root / "client-cache"),
            "NIX_STATE_HOME": str(root / "client-state"),
            "NIX_CONFIG": "experimental-features = nix-command\n",
        }

        def nix(*arguments, data=None, success=True):
            result = subprocess.run(
                ["nix", *arguments],
                input=data,
                capture_output=True,
                text=True,
                env=environment,
                timeout=60,
                check=False,
            )
            assert (result.returncode == 0) == success, result.stderr
            return result

        endpoints = {}
        for line in commands:
            key = line.split('" ', 1)[1]
            command = shlex.split(line.split('command="', 1)[1].split('" ', 1)[0])
            command[0] = shutil.which("nix-store")
            command[command.index("--store") + 1] = cache.as_uri()
            mode = "reader" if key in principal["readOnlyKeys"] else "writer"
            wrapper = root / mode
            wrapper.write_text(
                "#!"
                + sys.executable
                + "\nimport os\nos.execv("
                + repr(command[0])
                + ", "
                + repr(command)
                + ")\n"
            )
            wrapper.chmod(0o700)
            endpoints[mode] = (
                "ssh://localhost?" + urlencode({"remote-program": str(wrapper)}),
                command,
            )
        assert set(endpoints) == {"reader", "writer"}
        writer, writer_command = endpoints["writer"]
        reader, reader_command = endpoints["reader"]
        source = "local?root=" + str(root / "source")
        payload = root / "payload"
        payload.write_text("synthetic private build output\n")
        path = nix("store", "add", "--store", source, str(payload)).stdout.strip()
        secret = root / "signing.key"
        secret.write_text(
            nix("key", "generate-secret", "--key-name", "cache-test").stdout
        )
        secret.chmod(0o600)
        public = nix(
            "key", "convert-secret-to-public", data=secret.read_text()
        ).stdout.strip()
        staging = root / "staging"
        nix(
            "copy",
            "--from",
            source,
            "--to",
            staging.as_uri() + "?" + urlencode({"secret-key": str(secret)}),
            path,
        )
        narinfo = next(staging.glob("*.narinfo"))
        # CA content is self-authenticating; remove that optional assertion so
        # positive/negative signature checks exercise ordinary cache trust.
        narinfo.write_text(
            "\n".join(
                line
                for line in narinfo.read_text().splitlines()
                if not line.startswith("CA:")
            )
            + "\n"
        )
        assert "Sig: cache-test:" in narinfo.read_text()
        nix("copy", "--from", staging.as_uri(), "--to", writer, path)
        assert "CA:" not in (cache / narinfo.name).read_text()
        assert "Sig: cache-test:" in (cache / narinfo.name).read_text()
        denied_payload = root / "reader-must-not-publish"
        denied_payload.write_text("reader upload must fail\n")
        denied_path = nix(
            "store", "add", "--store", source, str(denied_payload)
        ).stdout.strip()
        denied = nix(
            "copy", "--from", source, "--to", reader, denied_path, success=False
        )
        assert "importing paths is not allowed" in denied.stderr, denied.stderr
        wrong_secret = nix(
            "key", "generate-secret", "--key-name", "wrong-cache-test"
        ).stdout
        wrong_public = nix(
            "key", "convert-secret-to-public", data=wrong_secret
        ).stdout.strip()
        for trusted in (False, True):
            destination = "local?root=" + str(
                root / ("trusted" if trusted else "untrusted")
            )
            result = subprocess.run(
                [
                    "nix-store",
                    "--realise",
                    path,
                    "--store",
                    destination,
                    "--option",
                    "substituters",
                    reader,
                    "--option",
                    "trusted-public-keys",
                    public if trusted else wrong_public,
                    "--option",
                    "require-sigs",
                    "true",
                    "--option",
                    "builders",
                    "",
                    "--option",
                    "max-jobs",
                    "0",
                ],
                capture_output=True,
                text=True,
                env=environment,
                timeout=60,
                check=False,
            )
            assert (result.returncode == 0) == trusted, result.stderr
            if trusted:
                assert (
                    root / "trusted" / path.lstrip("/")
                ).read_bytes() == payload.read_bytes()
            else:
                assert "not signed" in result.stderr, result.stderr
        metadata = dict(
            line.split(": ", 1)
            for line in (cache / narinfo.name).read_text().splitlines()
            if ": " in line
        )
        nar = cache / metadata["URL"]
        valid_nar = nar.read_bytes()
        try:
            nar.write_bytes(b"damaged static cache object")
            nix(
                "copy",
                "--from",
                reader,
                "--to",
                "local?root=" + str(root / "corrupt-target"),
                "--option",
                "require-sigs",
                "true",
                "--option",
                "trusted-public-keys",
                public,
                path,
                success=False,
            )
        finally:
            nar.write_bytes(valid_nar)
        derivation = subprocess.run(
            [
                "nix-instantiate",
                "--store",
                source,
                "--expr",
                'derivation { name = "never-build"; system = "x86_64-linux"; builder = "/nonexistent-builder"; }',
            ],
            capture_output=True,
            text=True,
            env=environment,
            timeout=30,
            check=True,
        ).stdout.strip()
        nix("copy", "--from", source, "--to", writer, derivation)
        build_request(writer_command, derivation, environment, read_only=False)
        build_request(reader_command, derivation, environment, read_only=True)
        assert not list(cache.rglob("*.sqlite*"))
        assert not list(cache.rglob("db.sqlite"))
        assert not (cache / "nix/store").exists()
        assert not (root / "client-state").exists()
        print(
            "native generated SSH cache: signed substitution, reader upload/build denial, writer static-store build denial; no server daemon/database"
        )


if __name__ == "__main__":
    main()
