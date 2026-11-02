"""Client-side enrollment records and administrative recovery review.

Device private keys are created only on the invoking machine and never enter
enrollment artifacts. Reviewed privileged reconstruction uses the explicitly
selected administrative SSH identity; ordinary device credentials never inherit it.
"""

import base64
import copy
import json
import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path


class EnrollmentError(ValueError):
    """Unsafe or incomplete enrollment request."""


def require(condition, message):
    if not condition:
        raise EnrollmentError(message)


def plain_path(path):
    path = Path(os.path.abspath(path.expanduser()))
    require(
        not path.is_relative_to("/nix/store"),
        "runtime keys must stay outside the Nix store",
    )
    for ancestor in (*reversed(path.parents), path):
        require(
            not ancestor.is_symlink(), f"symlinked path is not accepted: {ancestor}"
        )
    return path


def private_location(path):
    path = plain_path(path)
    for ancestor in path.parents:
        marker = ancestor / ".git"
        repository = (marker.is_dir() and (marker / "HEAD").is_file()) or (
            marker.is_file() and marker.read_text().startswith("gitdir:")
        )
        require(
            not repository,
            "private device keys must stay outside Git worktrees",
        )
    return path


def private_parent(path):
    """Create only client-owned private directories; never relax existing modes."""
    parent = path.parent
    if not parent.exists():
        private_parent(parent)
        parent.mkdir(mode=0o700)
    info = parent.stat()
    require(
        info.st_uid == os.getuid(),
        f"key directory must belong to the current user: {parent}",
    )
    require(
        stat.S_IMODE(info.st_mode) & 0o077 == 0,
        f"key directory must have private permissions: {parent}",
    )


def run_keygen(executable, arguments):
    result = subprocess.run(
        [executable, *arguments],
        input="",
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    require(
        result.returncode == 0,
        "ssh-keygen failed; existing keys were not overwritten (encrypted keys require explicit public-key enrollment)",
    )
    return result.stdout.strip()


def canonical_public(value):
    lines = value.strip().splitlines()
    require(len(lines) == 1, "exactly one public key is required")
    fields = lines[0].split()
    require(
        len(fields) >= 2 and fields[0] == "ssh-ed25519",
        "enrollment currently accepts bare Ed25519 device public keys",
    )
    try:
        wire = base64.b64decode(fields[1], validate=True)
    except ValueError as error:
        raise EnrollmentError("invalid Ed25519 public key encoding") from error
    prefix = b"\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20"
    require(
        wire.startswith(prefix) and len(wire) == len(prefix) + 32,
        "invalid Ed25519 public key encoding",
    )
    return " ".join(fields[:2])


def public_location(path):
    # Public certificates may be supplied declaratively by Nix/Home Manager.
    # Resolve only for reading; private keys and writable outputs retain their
    # separate no-symlink, outside-store/worktree guards.
    path = Path(os.path.abspath(path.expanduser())).resolve()
    require(path.is_file(), "public key file does not exist or is not regular")
    return path


def public_file(path):
    path = public_location(path)
    return canonical_public(path.read_text())


def write_exclusive(path, content, mode=0o644):
    """Never silently replace operator-owned files or follow symlinks."""
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    except FileExistsError:
        require(
            not path.is_symlink() and path.is_file(),
            f"existing output is not a regular file: {path}",
        )
        require(
            path.read_text() == content,
            f"existing output differs; use a new review directory: {path}",
        )
        return False
    with os.fdopen(fd, "w") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    return True


def device_key(path, principal, device, executable):
    """Create a source-local key or validate its existing private/public pair."""
    path = private_location(path)
    private_parent(path)
    public_path = Path(str(path) + ".pub")
    require(not public_path.is_symlink(), "public key path is a symlink")
    if path.exists():
        info = path.stat()
        require(
            stat.S_ISREG(info.st_mode)
            and info.st_uid == os.getuid()
            and stat.S_IMODE(info.st_mode) & 0o077 == 0,
            "existing private key must be a current-user-owned private regular file",
        )
        public = canonical_public(
            run_keygen(executable, ["-y", "-P", "", "-f", str(path)])
        )
        if public_path.exists():
            require(
                public_file(public_path) == public,
                "existing public key does not match the private key",
            )
        else:
            write_exclusive(public_path, public + "\n")
        return public, False
    require(
        not public_path.exists(),
        "public key exists without a private key; use --public-key or choose a new path",
    )
    # Generation is staged in a private directory. Hard links publish without
    # replacing an existing key, including a key created by another process.
    with tempfile.TemporaryDirectory(
        prefix=".rsync-enroll-", dir=path.parent
    ) as folder:
        candidate = Path(folder) / "identity"
        run_keygen(
            executable,
            [
                "-q",
                "-t",
                "ed25519",
                "-N",
                "",
                "-C",
                f"rsync-net:{principal}:{device}",
                "-f",
                str(candidate),
            ],
        )
        public = canonical_public(
            run_keygen(executable, ["-y", "-P", "", "-f", str(candidate)])
        )
        try:
            os.link(candidate, path, follow_symlinks=False)
        except FileExistsError as error:
            raise EnrollmentError(
                "device private key appeared during generation; it was not overwritten"
            ) from error
        # A failure after publishing a private key leaves it recoverable in
        # place. The next run derives its public key, never generates over it.
        write_exclusive(public_path, public + "\n")
    return public, True


def nix_string(value):
    # JSON string escaping is almost Nix double-string escaping; interpolation
    # must additionally be disabled for untrusted public comments/hostnames.
    return json.dumps(value).replace("${", "\\${")


def render_module(record):
    principal = record["principal"]
    name = nix_string(principal["name"])
    device = nix_string(record["device"])
    lines = ["{", f"  rsyncNet.principals.{name} = {{"]
    for field in ("uid", "gid"):
        lines.append(f"    {field} = {principal[field]};")
    for field in ("home", "backend"):
        lines.append(f"    {field} = {nix_string(principal[field])};")
    dataset = principal["dataset"]
    lines.append(f"    dataset = {nix_string(dataset) if dataset else 'null'};")
    lines += [
        f"    devices.{device} = {{",
        f"      publicKey = {nix_string(record['publicKey'])};",
    ]
    if record["readOnly"]:
        lines.append("      readOnly = true;")
    if record["gpgFingerprint"]:
        lines.append(f"      gpgFingerprint = {nix_string(record['gpgFingerprint'])};")
    lines += ["    };", "  };"]
    if record["datasetDeclaration"]:
        declaration = record["datasetDeclaration"]
        lines.append(f"  rsyncNet.datasets.{nix_string(record['datasetLabel'])} = {{")
        for field in ("name", "mountpoint", "principal", "purpose"):
            lines.append(f"    {field} = {nix_string(declaration[field])};")
        lines += [f"    quotaBytes = {declaration['quotaBytes']};", "  };"]
    lines += ["}", ""]
    return "\n".join(lines)


def enroll(args, manifest, *, validate, keygen):
    require(
        re.fullmatch(r"[a-z][a-z0-9_-]{0,30}", args.principal)
        and args.principal != "root",
        "invalid enrollment principal",
    )
    require(re.fullmatch(r"[a-z][a-z0-9_-]{0,30}", args.device), "invalid device name")
    principal = next(
        (p for p in manifest["principals"] if p["name"] == args.principal), None
    )
    dataset_declaration = None
    new_account = principal is None
    if new_account:
        require(
            args.new_account,
            "undeclared principal requires --new-account and explicit allocations",
        )
        require(
            args.backend and args.uid is not None and args.gid is not None,
            "new accounts require explicit --backend, --uid and --gid",
        )
        require(
            args.dataset and args.quota_bytes,
            "new repository accounts require --dataset and --quota-bytes; no dataset is created",
        )
        principal = {
            "name": args.principal,
            "uid": args.uid,
            "gid": args.gid,
            "home": f"/home/{args.principal}",
            "backend": args.backend,
            "dataset": args.dataset,
            "publicKeys": [],
            "readOnlyKeys": [],
            "gcryptParticipants": [],
            "cache": {
                "signingPublicKeys": [],
            }
            if args.backend == "nix-cache"
            else None,
            "recovery": {
                "enable": manifest["recovery"]["enable"]
                and args.backend != "nix-cache",
                "recipients": list(manifest["recovery"]["recipients"]),
            },
        }
        if args.backend == "git" and principal["recovery"]["enable"]:
            principal["gcryptParticipants"] = sorted(
                set(principal["recovery"]["recipients"])
            )
        if args.dataset:
            purpose = args.purpose or {"git": "git", "nix-cache": "cache"}.get(
                args.backend
            )
            require(
                purpose is not None,
                "Restic accounts require explicit --purpose user or service",
            )
            dataset_declaration = {
                "name": args.dataset,
                "mountpoint": "/mnt/" + args.dataset,
                "principal": args.principal,
                "purpose": purpose,
                "quotaBytes": args.quota_bytes,
            }
    else:
        require(
            not args.new_account
            and all(
                getattr(args, field) is None
                for field in (
                    "backend",
                    "uid",
                    "gid",
                    "dataset",
                    "quota_bytes",
                    "purpose",
                )
            ),
            "existing principals use their declared allocations; do not override them during enrollment",
        )
        principal = copy.deepcopy(principal)
    require(
        principal["uid"] is not None and principal["gid"] is not None,
        "principal UID/GID allocations must be declared before enrollment",
    )
    require(
        not args.read_only or principal["backend"] in {"git", "nix-cache"},
        "read-only enrollment is only supported for Git and Nix cache principals",
    )
    if principal["backend"] == "git":
        require(
            args.gpg_fingerprint
            and re.fullmatch(r"[a-fA-F0-9]{40}|[a-fA-F0-9]{64}", args.gpg_fingerprint),
            "Git device membership requires a full public --gpg-fingerprint",
        )
    else:
        require(
            args.gpg_fingerprint is None,
            "GPG membership is only valid for Git principals",
        )
    fingerprint = args.gpg_fingerprint.upper() if args.gpg_fingerprint else None
    # Validate all proposed allocations before producing any private key.
    candidate = copy.deepcopy(manifest)
    if new_account:
        candidate["principals"].append(copy.deepcopy(principal))
    if dataset_declaration:
        candidate["datasets"].append(dataset_declaration)
    validate(candidate)
    if args.key_file:
        public, created = device_key(args.key_file, args.principal, args.device, keygen)
    else:
        public, created = public_file(args.public_key), False
    enrolled = next(p for p in candidate["principals"] if p["name"] == args.principal)
    if public in enrolled["publicKeys"]:
        require(
            (public in enrolled["readOnlyKeys"]) == args.read_only,
            "existing key permission differs; permission changes require an explicit policy review",
        )
    else:
        enrolled["publicKeys"].append(public)
    enrolled["publicKeys"].sort()
    if args.read_only and public not in enrolled["readOnlyKeys"]:
        enrolled["readOnlyKeys"].append(public)
    enrolled["readOnlyKeys"].sort()
    if fingerprint and fingerprint not in enrolled["gcryptParticipants"]:
        enrolled["gcryptParticipants"].append(fingerprint)
    enrolled["gcryptParticipants"].sort()
    validate(candidate)
    record = {
        "schemaVersion": 1,
        "principal": principal,
        "device": args.device,
        "publicKey": public,
        "readOnly": args.read_only,
        "gpgFingerprint": fingerprint,
        "datasetDeclaration": dataset_declaration,
        "datasetLabel": args.dataset_label or args.principal,
    }
    # The Nix record intentionally carries only the named device, not a copied
    # mutable key database or any path to a private/admin identity.
    module = render_module(record)
    output = plain_path(args.output)
    if not output.exists():
        output.mkdir(mode=0o700, parents=True)
    require(
        output.is_dir() and output.stat().st_uid == os.getuid(),
        "review output must be a current-user-owned directory",
    )
    artifacts = {
        "enrollment.nix": module,
        "manifest.json": json.dumps(candidate, indent=2, sort_keys=True) + "\n",
        "enrollment.json": json.dumps(record, indent=2, sort_keys=True) + "\n",
    }
    # Check all existing public artifacts first, so a retry cannot replace or
    # partially update an earlier review with a different device/policy.
    for filename, content in artifacts.items():
        path = output / filename
        if path.exists() or path.is_symlink():
            require(
                not path.is_symlink()
                and path.is_file()
                and path.read_text() == content,
                "existing review artifact differs; use a new output directory",
            )
    for filename, content in artifacts.items():
        write_exclusive(output / filename, content)
    return {
        "schemaVersion": 1,
        "localDeviceKeyCreated": created,
        "publicModule": str(output / "enrollment.nix"),
        "reviewManifest": str(output / "manifest.json"),
        "applySupported": False,
        "note": "Import the public Nix module into the authoritative configuration and review bootstrap. No remote account/storage was changed. Git public-key import and coordinated participant rollout remain separate.",
    }


def check_admin_file(path, *, private):
    path = plain_path(path) if private else public_location(path)
    require(path.is_file(), "explicit administrative identity file does not exist")
    info = path.stat()
    if private:
        require(
            info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) & 0o077 == 0,
            "administrative private identity must be current-user-owned and private",
        )
    else:
        public_file(path)
    return path


def bootstrap(
    args, manifest, *, inspect_remote, plan, digest=None, reconstruct_remote=None
):
    if args.apply:
        require(
            manifest["mode"] == "public",
            "private mode is incomplete; activation is disabled",
        )
        require(
            getattr(args, "review", None) is not None
            and reconstruct_remote is not None,
            "privileged apply requires an available tested adapter and a saved --review; no writes were requested",
        )
    require(
        args.admin_identity is not None or args.admin_agent_public_key is not None,
        "bootstrap requires an explicit administrative identity selector",
    )
    private = (
        check_admin_file(args.admin_identity, private=True)
        if args.admin_identity
        else None
    )
    agent_public = (
        check_admin_file(args.admin_agent_public_key, private=False)
        if args.admin_agent_public_key
        else None
    )
    state = inspect_remote(
        manifest,
        admin_identity=private,
        admin_agent_public_key=agent_public,
        known_hosts=args.known_hosts,
    )
    result = plan(manifest, state)
    review_digest = digest(manifest, result) if digest is not None else None
    if args.apply:
        require(
            result["applySupported"],
            "privileged apply is gated pending native FreeBSD acceptance; no writes were requested",
        )
        reviewed = json.loads(args.review.read_text())
        require(
            reviewed.get("reviewDigest") == review_digest,
            "saved review is stale or for a different policy; inspect and review again",
        )
        require(not result["blockers"], "cannot reconstruct while review has blockers")
        return reconstruct_remote(
            manifest,
            admin_identity=private,
            admin_agent_public_key=agent_public,
            known_hosts=args.known_hosts,
            review_digest=review_digest,
        )
    result["operation"] = "administrative-bootstrap-review"
    result["reviewDigest"] = review_digest
    return result
