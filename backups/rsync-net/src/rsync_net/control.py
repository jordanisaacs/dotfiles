"""Administrative catalog and immutable encrypted recovery-envelope storage.

The caller supplies the same validated public manifest, native provider adapter
and authority guards used by account reconstruction. This helper never creates
storage, decrypts an envelope, or accepts an operator-selected output filename.
"""

import base64
import binascii
import hashlib
import json
import os
import re
import stat
import subprocess
from pathlib import Path, PurePosixPath

MAX_ENVELOPE_BYTES = 131072
HEX_ID = re.compile(r"[a-f0-9]{64}")


class ControlError(ValueError):
    """Control storage or recovery publication is unsafe or inconsistent."""


def require(condition, message):
    if not condition:
        raise ControlError(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, indent=2) + "\n"


def sha256(content):
    return hashlib.sha256(content.encode()).hexdigest()


def encrypted_message(armor):
    """Recognize a bounded public-key-encrypted OpenPGP message, without decrypting.

    Packet parsing checks the envelope only. GnuPG on the producing client owns
    encryption, recipient selection and verification; server root is not a
    cryptographic verifier of the message's plaintext or intended recipients.
    """
    require(isinstance(armor, str), "encrypted password must be ASCII armor")
    try:
        encoded = armor.encode("ascii")
    except UnicodeEncodeError as error:
        raise ControlError("encrypted password must be ASCII armor") from error
    require(0 < len(encoded) <= MAX_ENVELOPE_BYTES, "encrypted envelope is too large")
    lines = armor.splitlines()
    require(
        len(lines) >= 4
        and lines[0] == "-----BEGIN PGP MESSAGE-----"
        and lines[-1] == "-----END PGP MESSAGE-----",
        "only an encrypted PGP MESSAGE envelope can be stored",
    )
    try:
        divider = lines.index("")
    except ValueError as error:
        raise ControlError("invalid encrypted armor headers") from error
    require(
        all(line.startswith(("Version: ", "Comment: ")) for line in lines[1:divider]),
        "invalid encrypted armor headers",
    )
    body = lines[divider + 1 : -1]
    if body and body[-1].startswith("="):
        require(len(body[-1]) == 5, "invalid encrypted armor checksum")
        body = body[:-1]
    try:
        binary = base64.b64decode("".join(body), validate=True)
    except (ValueError, binascii.Error) as error:
        raise ControlError("invalid encrypted armor body") from error

    def length(position):
        require(position < len(binary), "truncated OpenPGP packet")
        first = binary[position]
        position += 1
        if first < 192:
            return first, position, False
        if first < 224:
            require(position < len(binary), "truncated OpenPGP packet")
            return ((first - 192) << 8) + binary[position] + 192, position + 1, False
        if first < 255:
            return 1 << (first & 31), position, True
        require(position + 4 <= len(binary), "truncated OpenPGP packet")
        return (
            int.from_bytes(binary[position : position + 4], "big"),
            position + 4,
            False,
        )

    tags, position = [], 0
    while position < len(binary):
        header = binary[position]
        position += 1
        require(header & 128, "invalid OpenPGP packet")
        if header & 64:
            tag = header & 63
            partial = True
            size = 0
            while partial:
                chunk, position, partial = length(position)
                require(position + chunk <= len(binary), "truncated OpenPGP packet")
                position += chunk
                size += chunk
        else:
            tag = (header >> 2) & 15
            width = (1, 2, 4, 0)[header & 3]
            require(
                width != 0 and position + width <= len(binary),
                "unsupported OpenPGP packet",
            )
            size = int.from_bytes(binary[position : position + width], "big")
            position += width
            require(position + size <= len(binary), "truncated OpenPGP packet")
            position += size
        require(size > 0, "empty OpenPGP packet")
        tags.append(tag)
    require(
        len(tags) >= 2 and all(tag == 1 for tag in tags[:-1]) and tags[-1] in (18, 20),
        "envelope must contain public-key session packets and integrity-protected ciphertext",
    )
    return armor


def _principal(manifest, name, *, require_recovery=True):
    require(
        isinstance(name, str) and re.fullmatch(r"[a-z][a-z0-9_-]{0,30}", name),
        "invalid recovery principal",
    )
    principal = next((p for p in manifest["principals"] if p["name"] == name), None)
    require(principal is not None, "recovery principal is not declared")
    require(principal["backend"] == "restic", "principal does not use Restic")
    require(
        not require_recovery or principal["recovery"]["enable"],
        "principal has no enabled recovery policy",
    )
    return principal


def _metadata(name, repository_id, key_id, recipients, armor):
    require(
        isinstance(repository_id, str)
        and HEX_ID.fullmatch(repository_id)
        and isinstance(key_id, str)
        and HEX_ID.fullmatch(key_id),
        "recovery upload requires full repository and key IDs",
    )
    require(
        isinstance(recipients, list)
        and recipients
        and all(
            isinstance(value, str) and re.fullmatch(r"[A-F0-9]{40}|[A-F0-9]{64}", value)
            for value in recipients
        )
        and recipients == sorted(set(recipients)),
        "recovery recipients must be sorted unique public fingerprints",
    )
    encrypted_message(armor)
    return {
        "schemaVersion": 1,
        "state": "complete",
        "principal": name,
        "repositoryId": repository_id,
        "recipients": recipients,
        "keyId": key_id,
        "ciphertextSha256": sha256(armor),
        "restoreVerified": False,
    }


def _payload(manifest, payload):
    if payload is None:
        return None
    require(
        isinstance(payload, dict)
        and set(payload)
        == {"principal", "repositoryId", "recipients", "keyId", "encryptedPassword"},
        "invalid recovery upload fields",
    )
    principal = _principal(manifest, payload["principal"])
    require(
        payload["recipients"] == sorted(set(principal["recovery"]["recipients"])),
        "recovery recipients differ from declared policy",
    )
    armor = payload["encryptedPassword"]
    return {
        "metadata": _metadata(
            principal["name"],
            payload["repositoryId"],
            payload["keyId"],
            payload["recipients"],
            armor,
        ),
        "encryptedPassword": armor,
    }


def _mount(root, state, engine, backend):
    expected = next(
        (d for d in state["datasets"] if d["mountpoint"] == str(root) and d["mounted"]),
        None,
    )
    require(
        expected is not None,
        "control path must be an existing mounted ZFS dataset root",
    )
    require(
        expected["name"].startswith(state["pool"]["name"] + "/"),
        "control dataset is outside the expected pool",
    )
    require(
        backend.label == "FreeBSD", "control mount inspection requires native FreeBSD"
    )
    # mount -p reports fstab fields; decode octal escapes, never shell text.
    rows = []
    for line in engine.native(["/sbin/mount", "-p"]).splitlines():
        fields = line.split()
        if len(fields) >= 3:
            rows.append(
                [
                    re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), value)
                    for value in fields[:3]
                ]
            )
    matching = [row for row in rows if row[1] == str(root)]
    require(
        matching == [[expected["name"], str(root), "zfs"]],
        "actual control mount source/type differs from declared ZFS",
    )
    return expected["name"]


def _file(path, engine, backend, *, device):
    engine.protected(path)
    if not path.exists():
        return None
    require(
        stat.S_IMODE(path.stat().st_mode) == 0o600 and path.stat().st_nlink == 1,
        "control files must be private single-link regular files",
    )
    require(
        path.stat().st_dev == device,
        "control file is outside the verified control filesystem",
    )
    backend.check_acl(path)
    require(
        path.stat().st_size <= MAX_ENVELOPE_BYTES * 16,
        "control file exceeds its size bound",
    )
    return path.read_text()


def _prepare(manifest, payload, *, validate, inspect, engine, backend):
    backend.check()
    validate(manifest)
    require(manifest["control"]["enable"], "control storage is disabled")
    path = manifest["control"]["path"]
    require(
        isinstance(path, str)
        and path.startswith("/")
        and str(PurePosixPath(path)) == path
        and ".." not in PurePosixPath(path).parts,
        "control path is unselected or non-canonical",
    )
    root = Path(path)
    require(root.is_dir(), "control directory must already exist")
    engine.protected(root, directory=True)
    require(
        stat.S_IMODE(root.stat().st_mode) == 0o700,
        "control dataset root must have mode 0700",
    )
    for candidate in (*root.parents, root):
        backend.check_acl(candidate)
    for dataset in manifest["datasets"]:
        repository = Path(dataset["mountpoint"])
        require(
            root != repository
            and root not in repository.parents
            and repository not in root.parents,
            "control storage must be separate from every repository/cache",
        )
    state = inspect(manifest)
    require(
        state["system"] == backend.label
        and state["pool"] == manifest["pool"]
        and manifest["pool"]["guid"] is not None,
        "control pool identity differs from approved storage",
    )
    dataset_name = _mount(root, state, engine, backend)
    require(
        not any(text.strip() for text in state["delegations"].values()),
        "control publication refuses delegated ZFS access",
    )
    zfs = (
        "/sbin/zfs" if backend.label == "FreeBSD" else "/run/current-system/sw/bin/zfs"
    )
    parts = dataset_name.split("/")
    for count in range(1, len(parts) + 1):
        require(
            not engine.native([zfs, "allow", "/".join(parts[:count])]).strip(),
            "control dataset has delegated ZFS access",
        )
    incoming = _payload(manifest, payload)
    recovery = root / "recovery"
    if recovery.exists() or recovery.is_symlink():
        engine.protected(recovery, directory=True)
        require(
            stat.S_IMODE(recovery.stat().st_mode) == 0o700,
            "recovery directory must have mode 0700",
        )
        require(
            recovery.stat().st_dev == root.stat().st_dev,
            "recovery directory is outside the verified control filesystem",
        )
        backend.check_acl(recovery)
    snapshots = {}
    entries = {}
    for principal in manifest["principals"]:
        name = principal["name"]
        if principal["backend"] != "restic":
            continue
        metadata_path, envelope_path = (
            recovery / (name + ".json"),
            recovery / (name + ".asc"),
        )
        metadata_text = _file(metadata_path, engine, backend, device=root.stat().st_dev)
        armor = _file(envelope_path, engine, backend, device=root.stat().st_dev)
        snapshots[name] = {
            "metadata": sha256(metadata_text) if metadata_text is not None else None,
            "ciphertext": sha256(armor) if armor is not None else None,
        }
        expected = (
            incoming if incoming and incoming["metadata"]["principal"] == name else None
        )
        if metadata_text is None and armor is None:
            if expected:
                entries[name] = expected["metadata"]
            continue
        if expected:
            require(
                metadata_text is None
                or metadata_text == canonical(expected["metadata"]),
                "existing recovery metadata would be replaced; rotation requires separate review",
            )
            require(
                armor is None or armor == expected["encryptedPassword"],
                "existing recovery envelope would be replaced; rotation requires separate review",
            )
            entries[name] = expected["metadata"]
        else:
            require(
                metadata_text is not None and armor is not None,
                "incomplete recovery publication requires its original bundle to retry",
            )
            try:
                metadata = json.loads(metadata_text)
            except ValueError as error:
                raise ControlError("invalid existing recovery metadata") from error
            require(
                isinstance(metadata, dict) and metadata.get("principal") == name,
                "existing recovery principal is inconsistent",
            )
            expected = _metadata(
                name,
                metadata.get("repositoryId"),
                metadata.get("keyId"),
                metadata.get("recipients"),
                armor,
            )
            require(
                metadata == expected,
                "existing recovery metadata is inconsistent",
            )
            entries[name] = metadata
    catalog_path = root / "catalog.json"
    catalog_before = _file(catalog_path, engine, backend, device=root.stat().st_dev)
    catalog = {"schemaVersion": 1, "manifest": manifest, "repositories": entries}
    catalog_content = canonical(catalog)
    require(
        len(catalog_content.encode()) <= MAX_ENVELOPE_BYTES * 16,
        "public catalog exceeds its size bound",
    )
    actions = []
    if incoming:
        name = incoming["metadata"]["principal"]
        before = snapshots[name]
        if before["ciphertext"] is None:
            actions.append("publish encrypted recovery envelope " + name)
        if before["metadata"] is None:
            actions.append("publish recovery metadata " + name)
    if catalog_before != catalog_content:
        actions.append("publish public catalog")
    snapshot = dataset_name + "@rsync-net-control-" + sha256(catalog_content)
    engine.protected(Path(zfs))
    backend.check_acl(Path(zfs))
    existing_snapshots = engine.native(
        [zfs, "list", "-H", "-o", "name", "-t", "snapshot", "-d", "1", dataset_name]
    ).splitlines()
    snapshot_exists = snapshot in existing_snapshots
    if not snapshot_exists:
        actions.append("snapshot control dataset " + snapshot)
    review = {
        "schemaVersion": 1,
        "operation": "administrative-control-publication",
        "controlPath": str(root),
        "dataset": dataset_name,
        "actions": actions,
        "catalogSha256": sha256(catalog_content),
        "recovery": incoming["metadata"] if incoming else None,
        "snapshot": {
            "name": snapshot,
            "exists": snapshot_exists,
            "retention": "forever",
        },
        "before": {
            "catalog": sha256(catalog_before) if catalog_before is not None else None,
            "recovery": snapshots,
        },
        "storageCreationPerformed": False,
        "note": "Catalog and encrypted recovery-envelope publication only. No plaintext password or private GPG key is accepted; existing recovery material is immutable.",
    }
    review["reviewDigest"] = sha256(canonical(review))
    return root, incoming, catalog_content, review


def review(manifest, payload=None, **dependencies):
    """Return a fresh public review; never include ciphertext or plaintext."""
    return _prepare(manifest, payload, **dependencies)[3]


def _sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _verify_snapshot(root, snapshot, catalog_content, *, engine, backend):
    frozen = root / ".zfs/snapshot" / snapshot.split("@", 1)[1]
    engine.protected(frozen, directory=True)
    require(frozen.is_dir(), "control snapshot is not accessible for verification")
    expected = {"catalog.json": catalog_content}
    for name, metadata in json.loads(catalog_content)["repositories"].items():
        expected["recovery/" + name + ".json"] = canonical(metadata)
        armor = _file(
            root / "recovery" / (name + ".asc"),
            engine,
            backend,
            device=root.stat().st_dev,
        )
        require(armor is not None, "published recovery envelope disappeared")
        expected["recovery/" + name + ".asc"] = armor
    for relative, content in expected.items():
        require(
            _file(frozen / relative, engine, backend, device=frozen.stat().st_dev)
            == content,
            "control snapshot does not match the completed publication: " + relative,
        )


def publish(manifest, payload=None, *, expected_digest, **dependencies):
    """Reinspect under the host-wide admin lock, then durably publish fixed files."""
    engine = dependencies["engine"]
    dependencies["backend"].check()
    with engine.reconstruction_lock():
        root, incoming, catalog_content, checked = _prepare(
            manifest, payload, **dependencies
        )
        require(
            checked["reviewDigest"] == expected_digest,
            "control review is stale or belongs to a different publication",
        )
        changes = []
        if incoming:
            recovery = root / "recovery"
            if not recovery.exists():
                recovery.mkdir(mode=0o700)
                _sync_directory(root)
            name = incoming["metadata"]["principal"]
            for suffix, content in (
                (".asc", incoming["encryptedPassword"]),
                (".json", canonical(incoming["metadata"])),
            ):
                if engine.atomic_file(recovery / (name + suffix), content, mode=0o600):
                    changes.append("published recovery " + name + suffix)
                _sync_directory(recovery)
        if engine.atomic_file(root / "catalog.json", catalog_content, mode=0o600):
            changes.append("published public catalog")
        _sync_directory(root)
        snapshot = checked["snapshot"]["name"]
        snapshot_created = not checked["snapshot"]["exists"]
        try:
            if snapshot_created:
                engine.native(["/sbin/zfs", "snapshot", snapshot])
            _verify_snapshot(
                root,
                snapshot,
                catalog_content,
                engine=engine,
                backend=dependencies["backend"],
            )
        except (ValueError, OSError, subprocess.TimeoutExpired) as error:
            raise ControlError(
                "control files were published, but their control-dataset snapshot is incomplete; "
                "files are retained, retry with a fresh review: " + str(error)
            ) from error
        return {
            "schemaVersion": 1,
            "operation": "administrative-control-publication",
            "changes": changes,
            "recovery": incoming["metadata"] if incoming else None,
            "snapshot": {
                "name": snapshot,
                "created": snapshot_created,
                "verified": True,
                "retention": "forever",
            },
            "storageCreationPerformed": False,
        }


def fetch(manifest, principal=None, **dependencies):
    """Fetch only a declared principal's encrypted bundle, or the public catalog."""
    engine = dependencies["engine"]
    dependencies["backend"].check()
    with engine.reconstruction_lock():
        root, _, _, _ = _prepare(manifest, None, **dependencies)
        if principal is None:
            content = _file(
                root / "catalog.json",
                engine,
                dependencies["backend"],
                device=root.stat().st_dev,
            )
            require(content is not None, "control catalog has not been published")
            try:
                catalog = json.loads(content)
            except ValueError as error:
                raise ControlError("invalid published catalog") from error
            require(
                isinstance(catalog, dict)
                and set(catalog) == {"schemaVersion", "manifest", "repositories"}
                and catalog["schemaVersion"] == 1,
                "invalid published catalog",
            )
            dependencies["validate"](catalog["manifest"])
            require(
                isinstance(catalog["repositories"], dict),
                "invalid published catalog repositories",
            )
            for name, metadata in catalog["repositories"].items():
                _principal(catalog["manifest"], name, require_recovery=False)
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
                    and metadata["schemaVersion"] == 1
                    and metadata["state"] == "complete"
                    and metadata["principal"] == name
                    and metadata["restoreVerified"] is False,
                    "invalid published catalog recovery metadata",
                )
                for field in ("repositoryId", "keyId", "ciphertextSha256"):
                    require(
                        isinstance(metadata[field], str)
                        and HEX_ID.fullmatch(metadata[field]),
                        "invalid published catalog recovery ID",
                    )
                recipients = metadata["recipients"]
                require(
                    isinstance(recipients, list)
                    and recipients
                    and all(
                        isinstance(value, str)
                        and re.fullmatch(r"[A-F0-9]{40}|[A-F0-9]{64}", value)
                        for value in recipients
                    )
                    and recipients == sorted(set(recipients)),
                    "invalid published catalog recovery recipients",
                )
            return {"catalog": catalog}
        _principal(manifest, principal, require_recovery=False)
        metadata = (
            json.loads((root / "recovery" / (principal + ".json")).read_text())
            if (root / "recovery" / (principal + ".json")).exists()
            else None
        )
        require(metadata is not None, "recovery bundle has not been published")
        armor = (root / "recovery" / (principal + ".asc")).read_text()
        return {"metadata": metadata, "encryptedPassword": armor}
