"""Prepare a durable GPG envelope before adding a native Restic recovery key.

Only ciphertext and public metadata are persisted. A pending bundle is retained
after any ambiguous failure and must be inspected explicitly, never regenerated
over. The caller separately publishes completed bundles through admin access.
"""

import fcntl
import hashlib
import json
import os
import re
import secrets
import stat
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path


class RecoveryError(ValueError):
    """Invalid policy or an operation requiring explicit recovery review."""


def require(condition, message):
    if not condition:
        raise RecoveryError(message)


def private_file(fd):
    info = os.fstat(fd)
    require(
        stat.S_ISREG(info.st_mode)
        and info.st_uid == os.getuid()
        and stat.S_IMODE(info.st_mode) & 0o077 == 0,
        "recovery files must be current-user-owned private regular files",
    )


def fsync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_new(path, content):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as output:
        output.write(content)
        output.flush()
        os.fsync(output.fileno())
    fsync_directory(path.parent)


def write_metadata(path, value):
    fd, temporary = tempfile.mkstemp(prefix=".recovery-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(value, output, sort_keys=True, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        Path(temporary).unlink(missing_ok=True)


def read_private(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as source:
        private_file(source.fileno())
        data = source.read(limit + 1)
    require(len(data) <= limit, "recovery artifact exceeds its size limit")
    return data


@contextmanager
def bundle_directory(output, *, create=True):
    path = Path(output).expanduser().absolute()
    require(
        not path.is_relative_to("/nix/store"),
        "recovery output cannot be in the Nix store",
    )
    require(not path.is_symlink(), "recovery output cannot be a symlink")
    if not path.exists():
        require(create, "recovery bundle does not exist")
        path.mkdir(mode=0o700)
        fsync_directory(path.parent)
    info = path.stat()
    require(
        stat.S_ISDIR(info.st_mode)
        and info.st_uid == os.getuid()
        and stat.S_IMODE(info.st_mode) == 0o700,
        "recovery output must be a current-user-owned 0700 directory",
    )
    fd = os.open(path / ".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        private_file(fd)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RecoveryError(
                "another recovery preparation is using this bundle"
            ) from error
        require(
            {p.name for p in path.iterdir()}
            <= {".lock", "recovery-password.asc", "recovery.json"},
            "recovery output contains unrelated files; use a dedicated bundle directory",
        )
        yield path
    finally:
        os.close(fd)


def run(arguments, *, operation, input_data=None, pass_fds=(), timeout=120):
    # Command output is intentionally never included in exceptions: native tools
    # may repeat backend URLs, decrypted data or authentication details.
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith("RESTIC_PASSWORD")
        and k not in {"RESTIC_REPOSITORY", "RESTIC_REPOSITORY_FILE", "RESTIC_KEY_HINT"}
    }
    try:
        result = subprocess.run(
            [str(a) for a in arguments],
            input=input_data,
            capture_output=True,
            pass_fds=pass_fds,
            env=env,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RecoveryError(
            f"{operation} failed; command output was withheld"
        ) from error
    require(result.returncode == 0, f"{operation} failed; command output was withheld")
    return result.stdout


def recovery_policy(principal):
    require(
        principal.get("backend") == "restic",
        "recovery preparation requires a Restic principal",
    )
    name = principal.get("name")
    require(
        isinstance(name, str) and re.fullmatch(r"[a-z][a-z0-9_-]{0,30}", name),
        "invalid recovery principal",
    )
    require(
        isinstance(principal.get("dataset"), str)
        and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_./:-]*", principal["dataset"])
        and not any(
            part in {"", ".", ".."} for part in principal["dataset"].split("/")
        ),
        "recovery requires a declared dataset binding",
    )
    policy = principal.get("recovery", {})
    recipients = policy.get("recipients")
    require(policy.get("enable") is True, "recovery is not enabled for this principal")
    require(
        isinstance(recipients, list)
        and bool(recipients)
        and all(
            isinstance(f, str) and re.fullmatch(r"[A-F0-9]{40}|[A-F0-9]{64}", f)
            for f in recipients
        ),
        "recovery requires full uppercase public recipient fingerprints",
    )
    return name, sorted(set(recipients))


def check_bundle(principal, metadata, ciphertext, *, complete=True):
    name, recipients = recovery_policy(principal)
    require(
        isinstance(metadata, dict)
        and set(metadata)
        == {
            "schemaVersion",
            "state",
            "principal",
            "repositoryId",
            "recipients",
            "keyId",
            "ciphertextSha256",
            "restoreVerified",
        }
        and metadata.get("schemaVersion") == 1,
        "unsupported recovery bundle metadata",
    )
    require(
        len(json.dumps(metadata).encode()) <= 65536,
        "recovery metadata exceeds its size limit",
    )
    require(
        metadata.get("principal") == name and metadata.get("recipients") == recipients,
        "existing recovery bundle belongs to a different principal or recipient policy",
    )
    require(
        isinstance(metadata.get("repositoryId"), str)
        and re.fullmatch(r"[a-f0-9]{64}", metadata["repositoryId"]),
        "invalid recovery repository identity",
    )
    require(
        metadata.get("restoreVerified") is False,
        "bundle cannot assert an independently verified restore",
    )
    require(
        metadata.get("state") in {"pending", "complete"},
        "invalid recovery bundle state",
    )
    if complete:
        require(
            metadata["state"] == "complete",
            "pending recovery bundle retained; the key addition may have succeeded, so inspect before retrying",
        )
    require(
        (metadata["state"] == "pending" and metadata.get("keyId") is None)
        or (
            isinstance(metadata.get("keyId"), str)
            and re.fullmatch(r"[a-f0-9]{64}", metadata["keyId"])
        ),
        "invalid recovery key identity",
    )
    require(
        isinstance(ciphertext, bytes)
        and 0 < len(ciphertext) <= 1048576
        and ciphertext.startswith(b"-----BEGIN PGP MESSAGE-----")
        and ciphertext.rstrip().endswith(b"-----END PGP MESSAGE-----"),
        "invalid encrypted recovery envelope",
    )
    require(
        metadata.get("ciphertextSha256") == hashlib.sha256(ciphertext).hexdigest(),
        "existing recovery ciphertext differs from its recorded hash",
    )


def read_contents(principal, folder):
    metadata_path = folder / "recovery.json"
    ciphertext_path = folder / "recovery-password.asc"
    require(
        metadata_path.exists() and ciphertext_path.exists(),
        "incomplete recovery bundle retained; inspect it explicitly before retrying",
    )
    metadata = json.loads(read_private(metadata_path, 65536))
    ciphertext = read_private(ciphertext_path, 1048576)
    check_bundle(principal, metadata, ciphertext)
    return metadata, ciphertext


def public_result(metadata, folder, changed):
    return {
        **metadata,
        "changed": changed,
        "ciphertextPath": str(folder / "recovery-password.asc"),
        "metadataPath": str(folder / "recovery.json"),
    }


def read_bundle(principal, output):
    """Read only ciphertext/public metadata; never invoke private GPG operations."""
    with bundle_directory(output, create=False) as folder:
        metadata, ciphertext = read_contents(principal, folder)
        return {"metadata": metadata, "encryptedPassword": ciphertext.decode("ascii")}


def save_bundle(principal, *, output, metadata, encrypted_password):
    """Save an administratively fetched bundle without replacing local records."""
    require(
        isinstance(encrypted_password, str), "encrypted password must be ASCII armor"
    )
    try:
        ciphertext = encrypted_password.encode("ascii")
    except UnicodeEncodeError as error:
        raise RecoveryError("encrypted password must be ASCII armor") from error
    check_bundle(principal, metadata, ciphertext)
    with bundle_directory(output) as folder:
        if any(
            (folder / name).exists() or (folder / name).is_symlink()
            for name in ("recovery.json", "recovery-password.asc")
        ):
            old_metadata, old_ciphertext = read_contents(principal, folder)
            require(
                old_metadata == metadata and old_ciphertext == ciphertext,
                "existing recovery bundle differs; it was not replaced",
            )
            return public_result(metadata, folder, False)
        write_new(folder / "recovery-password.asc", ciphertext)
        write_metadata(folder / "recovery.json", metadata)
        return public_result(metadata, folder, True)


def prepare(
    principal,
    *,
    repository,
    password_file=None,
    password_command=None,
    output,
    restic="restic",
    gpg="gpg",
    gnupghome=None,
    restic_options=(),
    signing_key=None,
):
    """Add a recovery password while retaining durable, ciphertext-only escrow.

    ``restic_options`` accepts only native ``-o KEY=VALUE`` backend options.
    Existing completed bundles verify public identity/policy and key presence;
    they cannot independently test decryption without a recovery private key.
    New bundles require a one-time signing operation by a configured recovery
    identity. Routine backups do not need that key. ``state=complete`` refers to
    local provisioning, not a tested server restore.
    """
    name, recipients = recovery_policy(principal)
    signer = signing_key or recipients[0]
    require(
        signer in recipients, "recovery signer must be a configured recovery recipient"
    )
    require(
        len(restic_options) % 2 == 0
        and all(
            restic_options[i] in {"-o", "--option"} and "=" in restic_options[i + 1]
            for i in range(0, len(restic_options), 2)
        ),
        "only explicit Restic backend -o KEY=VALUE options are accepted",
    )
    require(
        (password_file is None) != (password_command is None),
        "select exactly one operational password file or command",
    )
    password_fd = None
    if password_command is not None:
        require(
            isinstance(password_command, str) and bool(password_command.strip()),
            "operational password command must not be empty",
        )
    else:
        password_path = Path(password_file).expanduser().absolute()
        require(
            not password_path.is_relative_to("/nix/store"),
            "operational password cannot be in the Nix store",
        )
        for parent in password_path.parents:
            require(
                not (parent / ".git").exists(),
                "operational password must stay outside Git worktrees",
            )
        password_fd = os.open(
            password_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
        )
    try:
        if password_fd is not None:
            private_file(password_fd)
        descriptor_root = (
            "/proc/self/fd" if Path("/proc/self/fd").exists() else "/dev/fd"
        )
        password_arguments = (
            ["--password-command", password_command]
            if password_command is not None
            else ["--password-file", f"{descriptor_root}/{password_fd}"]
        )
        password_fds = (password_fd,) if password_fd is not None else ()
        base = [
            restic,
            "--no-cache",
            "--json",
            "--repo",
            repository,
            *password_arguments,
            *restic_options,
        ]

        def native(*arguments, new_password=None):
            if password_fd is not None:
                os.lseek(password_fd, 0, os.SEEK_SET)
            if new_password is None:
                return run(
                    [*base, *arguments],
                    operation="Restic metadata inspection",
                    pass_fds=password_fds,
                )
            reader, writer = os.pipe()
            try:
                os.write(writer, new_password + b"\n")
                os.close(writer)
                writer = None
                return run(
                    [
                        *base,
                        *arguments,
                        "--new-password-file",
                        f"{descriptor_root}/{reader}",
                    ],
                    operation="Restic recovery-key addition; durable bundle retained for review",
                    pass_fds=(*password_fds, reader),
                )
            finally:
                os.close(reader)
                if writer is not None:
                    os.close(writer)

        config = json.loads(native("cat", "config"))
        repository_id = config.get("id")
        require(
            isinstance(repository_id, str)
            and re.fullmatch(r"[a-f0-9]{64}", repository_id),
            "Restic returned an invalid repository identity",
        )

        def key_ids():
            keys = json.loads(native("key", "list"))
            require(
                isinstance(keys, list)
                and all(
                    isinstance(k.get("id"), str)
                    and re.fullmatch(r"[a-f0-9]{64}", k["id"])
                    for k in keys
                ),
                "Restic returned invalid key identities",
            )
            return {key["id"] for key in keys}

        with bundle_directory(output) as folder:
            ciphertext_path = folder / "recovery-password.asc"
            metadata_path = folder / "recovery.json"
            existing = (
                ciphertext_path.exists()
                or ciphertext_path.is_symlink()
                or metadata_path.exists()
                or metadata_path.is_symlink()
            )
            if existing:
                metadata, _ = read_contents(principal, folder)
                require(
                    metadata["repositoryId"] == repository_id,
                    "existing recovery bundle belongs to a different repository",
                )
                require(
                    metadata.get("keyId") in key_ids(),
                    "recorded recovery key is absent; existing bundle was not replaced",
                )
                return public_result(metadata, folder, False)
            before = key_ids()
            password = secrets.token_urlsafe(32).encode("ascii")
            payload = json.dumps(
                {
                    "schemaVersion": 1,
                    "principal": name,
                    "dataset": principal["dataset"],
                    "repositoryId": repository_id,
                    "password": password.decode("ascii"),
                },
                sort_keys=True,
            ).encode()
            gpg_arguments = [gpg, "--no-options"]
            if gnupghome is not None:
                gpg_arguments += ["--homedir", gnupghome]
            gpg_arguments += [
                "--batch",
                "--no-tty",
                "--no-auto-key-retrieve",
                "--auto-key-locate",
                "clear",
                "--trust-model",
                "always",
                "--armor",
                "--local-user",
                signer,
                "--sign",
                "--encrypt",
            ]
            for recipient in recipients:
                gpg_arguments += ["--recipient", recipient]
            ciphertext = run(
                gpg_arguments,
                operation="GPG recovery signing/encryption",
                input_data=payload,
            )
            require(
                ciphertext.startswith(b"-----BEGIN PGP MESSAGE-----")
                and ciphertext.rstrip().endswith(b"-----END PGP MESSAGE-----"),
                "GPG returned an invalid encrypted envelope",
            )
            metadata = {
                "schemaVersion": 1,
                "state": "pending",
                "principal": name,
                "repositoryId": repository_id,
                "recipients": recipients,
                "keyId": None,
                "ciphertextSha256": hashlib.sha256(ciphertext).hexdigest(),
                "restoreVerified": False,
            }
            check_bundle(principal, metadata, ciphertext, complete=False)
            write_new(ciphertext_path, ciphertext)
            write_metadata(metadata_path, metadata)
            # Both durable artifacts exist before the repository can be changed.
            native("key", "add", new_password=password)
            added = key_ids() - before
            require(
                len(added) == 1,
                "recovery-key result is ambiguous; encrypted pending bundle retained for explicit review",
            )
            metadata.update(state="complete", keyId=added.pop())
            write_metadata(metadata_path, metadata)
            return public_result(metadata, folder, True)
    finally:
        if password_fd is not None:
            os.close(password_fd)


def decrypt_password(principal, output, *, gpg="gpg", gnupghome=None):
    """Return the secret only after verifying its pinned signer and bindings.

    Encryption alone cannot authenticate a recovery bundle: an untrusted server
    also knows the public encryption keys. Certificate expiry after signing does
    not invalidate a historical signature; revoked/bad/expired signatures do.
    GPG status contains only public verification metadata, never the plaintext.
    """
    _, recipients = recovery_policy(principal)
    bundle = read_bundle(principal, output)
    arguments = [gpg, "--no-options"]
    if gnupghome is not None:
        arguments += ["--homedir", gnupghome]
    with tempfile.TemporaryFile() as status:
        arguments += [
            "--batch",
            "--no-tty",
            "--no-auto-key-retrieve",
            "--auto-key-locate",
            "clear",
            "--status-fd",
            str(status.fileno()),
            "--decrypt",
        ]
        plaintext = run(
            arguments,
            operation="GPG recovery decryption/signature verification",
            input_data=bundle["encryptedPassword"].encode("ascii"),
            pass_fds=(status.fileno(),),
        )
        status.seek(0)
        verification = status.read(65537)
    require(
        len(verification) <= 65536, "GPG verification metadata exceeds its size limit"
    )
    records = [
        line.split()[1:]
        for line in verification.decode("ascii", errors="replace").splitlines()
        if line.startswith("[GNUPG:] ")
    ]
    require(
        any(record[0] == "DECRYPTION_OKAY" for record in records),
        "recovery envelope was not successfully decrypted",
    )
    require(
        not any(
            record[0] in {"BADSIG", "ERRSIG", "REVKEYSIG", "EXPSIG", "SIGEXPIRED"}
            for record in records
        ),
        "GPG recovery signature is invalid or revoked",
    )
    valid = [record for record in records if record[0] == "VALIDSIG"]
    require(
        len(valid) == 1
        and (valid[0][10] if len(valid[0]) >= 11 else valid[0][1]) in recipients,
        "recovery envelope is unsigned or signed by an untrusted key",
    )
    try:
        payload = json.loads(plaintext)
    except ValueError:
        raise RecoveryError("invalid signed recovery payload") from None
    require(
        isinstance(payload, dict)
        and set(payload)
        == {"schemaVersion", "principal", "dataset", "repositoryId", "password"}
        and payload.get("schemaVersion") == 1
        and payload.get("principal") == principal["name"]
        and payload.get("dataset") == principal["dataset"]
        and payload.get("repositoryId") == bundle["metadata"]["repositoryId"],
        "signed recovery payload does not match the principal, dataset or repository",
    )
    password = payload.get("password")
    require(
        isinstance(password, str) and re.fullmatch(r"[A-Za-z0-9_-]{43,256}", password),
        "signed recovery password has an invalid format",
    )
    return password.encode("ascii")


def restore(
    principal,
    *,
    repository,
    bundle,
    target,
    snapshot="latest",
    restic="restic",
    gpg="gpg",
    gnupghome=None,
    restic_options=(),
):
    """Restore using a verified envelope and native Restic verification.

    The target must be a new or empty private directory. The decrypted password
    only travels through private inherited pipes, never argv, env or a file.
    """
    require(
        len(restic_options) % 2 == 0
        and all(
            restic_options[i] in {"-o", "--option"} and "=" in restic_options[i + 1]
            for i in range(0, len(restic_options), 2)
        ),
        "only explicit Restic backend -o KEY=VALUE options are accepted",
    )
    requested = Path(target).expanduser().absolute()
    destination = requested.parent.resolve(strict=True) / requested.name

    def check_target():
        require(not destination.is_symlink(), "restore target cannot be a symlink")
        if destination.exists():
            info = destination.stat()
            require(
                stat.S_ISDIR(info.st_mode)
                and info.st_uid == os.getuid()
                and stat.S_IMODE(info.st_mode) == 0o700
                and not any(destination.iterdir()),
                "restore target must be a new or empty current-user-owned 0700 directory",
            )
        require(
            not destination.is_relative_to("/nix/store"),
            "restore target cannot be in the Nix store",
        )
        for parent in destination.parents:
            info = parent.stat()
            require(
                info.st_uid in {0, os.getuid()}
                and (not (info.st_mode & 0o022) or bool(info.st_mode & stat.S_ISVTX)),
                f"restore target ancestors cannot be writable by other users: {parent}",
            )

    check_target()
    metadata = read_bundle(principal, bundle)["metadata"]
    password = decrypt_password(principal, bundle, gpg=gpg, gnupghome=gnupghome)
    descriptor_root = "/proc/self/fd" if Path("/proc/self/fd").exists() else "/dev/fd"

    def native(*arguments):
        reader, writer = os.pipe()
        try:
            os.write(writer, password + b"\n")
            os.close(writer)
            writer = None
            return run(
                [
                    restic,
                    "--no-cache",
                    "--json",
                    "--repo",
                    repository,
                    "--password-file",
                    f"{descriptor_root}/{reader}",
                    *restic_options,
                    *arguments,
                ],
                operation="Restic recovery restore",
                pass_fds=(reader,),
                timeout=None if arguments[0] == "restore" else 120,
            )
        finally:
            os.close(reader)
            if writer is not None:
                os.close(writer)

    config = json.loads(native("cat", "config"))
    require(
        config.get("id") == metadata["repositoryId"],
        "actual Restic repository differs from the signed recovery binding",
    )
    keys = json.loads(native("key", "list"))
    require(
        any(
            key.get("id") == metadata["keyId"] and key.get("current") is True
            for key in keys
        ),
        "actual recovery key differs from the recorded key identity",
    )
    check_target()
    if not destination.exists():
        destination.mkdir(mode=0o700)
    native(
        "restore",
        snapshot,
        "--verify",
        "--overwrite",
        "never",
        "--target",
        str(destination),
    )
    return {
        "principal": principal["name"],
        "repositoryId": metadata["repositoryId"],
        "keyId": metadata["keyId"],
        "snapshot": snapshot,
        "target": str(destination),
        "restoreVerified": True,
    }
