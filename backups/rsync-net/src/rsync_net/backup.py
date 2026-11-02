"""Finish declarative backup setup only after signed recovery escrow is published."""

import hashlib
import json
import re
from pathlib import Path


class BackupError(ValueError):
    """Incomplete or mismatched per-backup setup."""


def require(condition, message):
    if not condition:
        raise BackupError(message)


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def setup(
    args,
    manifest,
    *,
    load_helper,
    remote_call,
    validate,
    plan,
    transport,
    restic="restic",
    gpg="gpg",
):
    require(args.apply or args.review is None, "--review is only used with --apply")
    require(
        not args.apply or args.review is not None,
        "backup setup --apply requires a saved --review",
    )
    content = args.config.read_bytes()
    job = json.loads(content)
    require(
        isinstance(job, dict)
        and set(job)
        == {
            "schemaVersion",
            "manifest",
            "principal",
            "repository",
            "resticOptions",
            "passwordFile",
            "passwordCommand",
            "paths",
            "recoveryBundle",
        },
        "invalid declarative backup descriptor",
    )
    require(
        job["schemaVersion"] == 1 and validate(job["manifest"]) == manifest,
        "backup descriptor and authoritative server policy differ",
    )
    principal = next(
        (p for p in manifest["principals"] if p["name"] == job["principal"]), None
    )
    require(
        principal is not None and principal["backend"] == "restic",
        "backup needs a declared Restic principal",
    )
    policy = principal["recovery"]
    require(
        policy["enable"] and policy["recipients"] and manifest["control"]["enable"],
        "backup setup requires recovery recipients and control storage",
    )
    signer = args.signing_key or policy["recipients"][0]
    require(
        signer in policy["recipients"],
        "backup signer must be a declared recovery recipient",
    )
    require(
        isinstance(job["repository"], str) and job["repository"] == "rclone:ignored",
        "backup descriptor needs the declared SSH-backed repository",
    )
    require(
        isinstance(job["resticOptions"], list)
        and all(isinstance(o, str) for o in job["resticOptions"]),
        "invalid native Restic backend options",
    )
    require(
        (job["passwordFile"] is None) != (job["passwordCommand"] is None),
        "backup needs exactly one password source",
    )
    for name in ("passwordFile", "passwordCommand"):
        require(
            job[name] is None or isinstance(job[name], str) and bool(job[name].strip()),
            "invalid backup password source",
        )
    enrollment = load_helper("enrollment")
    require(
        isinstance(job["recoveryBundle"], str)
        and Path(job["recoveryBundle"]).is_absolute(),
        "recovery bundle must have an absolute runtime path",
    )
    bundle_path = enrollment.private_location(Path(job["recoveryBundle"]))
    recovery = load_helper("recovery")
    administrative = {
        "admin_identity": args.admin_identity,
        "admin_agent_public_key": args.admin_agent_public_key,
        "known_hosts": args.known_hosts,
    }

    def remote(operation, **options):
        return remote_call(manifest, operation, **administrative, **options)

    # Provisioning and account authorization remain explicit earlier CLI phases;
    # setup cannot silently publish a recovery key to unverified storage.
    for control in (False, True):
        reviewed = remote(
            "_storage-review",
            payload={
                "principal": None if control else principal["name"],
                "control": control,
                "transport": transport,
            },
        )
        require(
            not reviewed.get("blockers") and not reviewed["actions"],
            "provision declared backup/control storage with storage init before backup setup",
        )
    state = remote("_inspect")
    accounts = plan(manifest, state)
    require(
        not accounts["blockers"] and not accounts["actions"],
        "complete reviewed account bootstrap before backup setup",
    )
    entries = state.get("repositoryEntries", {}).get(principal["name"])
    require(isinstance(entries, list), "repository root was not inspected")
    password_args = (
        ["--password-file", job["passwordFile"]]
        if job["passwordFile"] is not None
        else ["--password-command", job["passwordCommand"]]
    )
    if job["passwordFile"] is not None:
        enrollment.private_location(Path(job["passwordFile"]))
    options = tuple(item for option in job["resticOptions"] for item in ("-o", option))
    base = [
        restic,
        "--no-cache",
        "--json",
        "--repo",
        job["repository"],
        *password_args,
        *options,
    ]

    def repository_id():
        config = json.loads(
            recovery.run(
                [*base, "cat", "config"], operation="Backup repository inspection"
            )
        )
        value = config.get("id")
        require(
            isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value),
            "invalid repository identity",
        )
        return value

    observed_id = repository_id() if entries else None
    reviewed = {
        "operation": "declarative-backup-setup-review",
        "schemaVersion": 1,
        "principal": principal["name"],
        "paths": job["paths"],
        "repositoryId": observed_id,
        "configSha256": hashlib.sha256(content).hexdigest(),
        "manifestSha256": digest(manifest),
        "stateSha256": digest(state),
        "transport": transport,
        "signingKey": signer,
        "recoveryBundle": str(bundle_path),
        "phases": [
            "verify declared storage and account access",
            "initialize an empty repository or verify its identity",
            "prepare or verify the hardware-signed encrypted recovery bundle",
            "publish and read back immutable recovery escrow and public catalog",
        ],
        "blockers": [],
    }
    reviewed["reviewDigest"] = digest(reviewed)
    if not args.apply:
        return reviewed
    saved = json.loads(args.review.read_text())
    require(
        isinstance(saved, dict)
        and saved.get("reviewDigest") == reviewed["reviewDigest"],
        "backup setup review is stale or belongs to a different config, signer or SSH trust",
    )
    initialized = False
    try:
        if observed_id is None:
            recovery.run([*base, "init"], operation="Backup repository initialization")
            initialized = True
            observed_id = repository_id()
        enrollment.private_parent(bundle_path)
        prepared = recovery.prepare(
            principal,
            repository=job["repository"],
            password_file=job["passwordFile"],
            password_command=job["passwordCommand"],
            output=bundle_path,
            signing_key=signer,
            restic=restic,
            gpg=gpg,
            restic_options=options,
        )
        bundle = recovery.read_bundle(principal, bundle_path)
        require(
            bundle["metadata"]["repositoryId"] == observed_id,
            "recovery bundle belongs to a different repository",
        )
        payload = {
            key: bundle["metadata"][key]
            for key in ("principal", "repositoryId", "keyId", "recipients")
        }
        payload["encryptedPassword"] = bundle["encryptedPassword"]
        publication = remote("_control-review", payload=payload)
        remote(
            "_control-publish",
            payload=payload,
            review_digest=publication["reviewDigest"],
        )
        fetched = remote("_control-fetch", payload={"principal": principal["name"]})
        require(
            fetched["metadata"] == bundle["metadata"]
            and fetched["encryptedPassword"] == bundle["encryptedPassword"],
            "published recovery escrow did not match the local bundle",
        )
    except (ValueError, OSError) as error:
        raise BackupError(
            f"backup setup incomplete; repository/recovery artifacts retained for retry; {error}"
        ) from error
    return {
        "operation": "declarative-backup-setup",
        "schemaVersion": 1,
        "setupComplete": True,
        "principal": principal["name"],
        "repositoryId": observed_id,
        "repositoryInitialized": initialized,
        "recoveryChanged": prepared["changed"],
        "recoveryPublished": True,
        "recoveryBundle": str(bundle_path),
        "signingKey": signer,
        "restoreVerified": False,
    }
