"""Native machine GPG isolation, keyring setup, retries and gcrypt pipe semantics."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from test_planner import policy

from rsync_net import cli
from rsync_net import git as local_git


@pytest.fixture
def machine(tmp_path, monkeypatch):
    recovery = tmp_path / "recovery"
    recovery.mkdir(mode=0o700)
    monkeypatch.setenv("GNUPGHOME", str(recovery))
    executable = shutil.which("gpg")
    local_git.native(
        executable,
        recovery,
        [
            "--pinentry-mode",
            "loopback",
            "--passphrase",
            "",
            "--quick-generate-key",
            "Test recovery",
            "ed25519",
            "sign",
            "0",
        ],
    )
    recovery_id = local_git.primary_fingerprint(
        local_git.native(executable, recovery, ["--with-colons", "--list-secret-keys"])
    )
    local_git.native(
        executable,
        recovery,
        [
            "--pinentry-mode",
            "loopback",
            "--passphrase",
            "",
            "--quick-add-key",
            recovery_id,
            "cv25519",
            "encrypt",
            "0",
        ],
    )
    keyring = tmp_path / "test-keyring"
    provider = tmp_path / "provider.py"
    provider.write_text(
        "import sys\nfrom pathlib import Path\np=Path(sys.argv[2])\nif sys.argv[1]=='store':\n p.write_bytes(sys.stdin.buffer.read())\nelif p.exists():\n sys.stdout.buffer.write(p.read_bytes())\nelse:\n sys.exit(1)\n"
    )
    manifest = cli.validate(policy())
    principal = manifest["principals"][1]
    principal.update(
        backend="git",
        gcryptParticipants=[recovery_id],
        recovery={"enable": True, "recipients": [recovery_id]},
    )
    manifest["datasets"][1]["purpose"] = "git"
    spec = {
        "schemaVersion": 1,
        "device": "test",
        "home": str(tmp_path / "machine"),
        "userId": "rsync-net machine test",
        "lookupCommand": [sys.executable, str(provider), "lookup", str(keyring)],
        "storeCommand": [sys.executable, str(provider), "store", str(keyring)],
        "bindings": {"git": {"principal": "backup-source", "device": "test"}},
        "manifest": manifest,
    }
    descriptor = tmp_path / "identity.json"
    descriptor.write_text(json.dumps(spec))
    yield descriptor, spec, manifest, recovery_id, keyring, executable
    gpgconf = shutil.which("gpgconf")
    for home in (recovery, Path(spec["home"])):
        subprocess.run(
            [gpgconf, "--homedir", str(home), "--kill", "all"],
            capture_output=True,
            check=False,
        )


def test_setup_is_local_encrypted_idempotent_and_recovery_has_no_machine_private_key(
    machine,
):
    descriptor, spec, manifest, recovery_id, keyring, executable = machine
    result = local_git.setup(descriptor, manifest, gpg=executable)
    assert result["localKeyCreated"] and not result["serverMutationPerformed"]
    assert result["fingerprint"] != recovery_id
    assert (
        local_git.primary_fingerprint(
            local_git.native(
                executable, spec["home"], ["--with-colons", "--list-secret-keys"]
            )
        )
        == result["fingerprint"]
    )
    assert (
        local_git.primary_fingerprint(
            local_git.native(
                executable,
                os.environ["GNUPGHOME"],
                ["--with-colons", "--list-secret-keys"],
            )
        )
        == recovery_id
    )
    assert all(
        b"protected-private-key" in key.read_bytes()
        for key in (Path(spec["home"]) / "private-keys-v1.d").glob("*.key")
    )
    assert result["fingerprint"] in Path(result["publicModule"]).read_text()
    assert keyring.read_text().strip() not in Path(result["publicModule"]).read_text()
    assert not local_git.setup(descriptor, manifest, gpg=executable)["localKeyCreated"]
    keyring.unlink()
    with pytest.raises(local_git.GitError, match="will not be regenerated"):
        local_git.setup(descriptor, manifest, gpg=executable)


def test_wrapper_keeps_gcrypt_pack_password_fd_and_machine_keyring_separate(machine):
    descriptor, spec, manifest, _recovery_id, keyring, executable = machine
    result = local_git.setup(descriptor, manifest, gpg=executable)
    wrapper = shutil.which("rsync-net-gpg")
    assert wrapper
    signed = subprocess.run(
        [
            wrapper,
            "--config",
            str(descriptor),
            "--batch",
            "--local-user",
            result["fingerprint"],
            "--sign",
        ],
        input=b"machine signature\n",
        capture_output=True,
        check=True,
    ).stdout
    assert (
        local_git.native(
            executable,
            spec["home"],
            ["--decrypt"],
            password=keyring.read_bytes().strip(),
            input=signed,
        )
        == b"machine signature\n"
    )
    encrypted = subprocess.run(
        [
            wrapper,
            "--config",
            str(descriptor),
            "--batch",
            "--trust-model",
            "always",
            "--local-user",
            result["fingerprint"],
            "--recipient",
            result["fingerprint"],
            "--recipient",
            _recovery_id,
            "--sign",
            "--encrypt",
        ],
        input=b"independent recovery\n",
        capture_output=True,
        check=True,
    ).stdout
    assert (
        subprocess.run(
            [wrapper, "--config", str(descriptor), "--batch", "--decrypt"],
            input=encrypted,
            capture_output=True,
            check=True,
        ).stdout
        == b"independent recovery\n"
    )
    local_git.native(
        executable,
        os.environ["GNUPGHOME"],
        ["--import"],
        input=Path(result["publicCertificate"]).read_bytes(),
    )
    assert (
        local_git.native(
            executable, os.environ["GNUPGHOME"], ["--decrypt"], input=encrypted
        )
        == b"independent recovery\n"
    )
    keyring.unlink()  # Symmetric packs must not even request this password.

    def pack(arguments, content):
        read_fd, write_fd = os.pipe()
        try:
            os.write(write_fd, b"independent-pack-password\n")
            os.close(write_fd)
            return subprocess.run(
                [
                    wrapper,
                    "--config",
                    str(descriptor),
                    "--batch",
                    "--passphrase-fd",
                    str(read_fd),
                    *arguments,
                ],
                input=content,
                capture_output=True,
                pass_fds=(read_fd,),
                check=True,
            ).stdout
        finally:
            os.close(read_fd)

    ciphertext = pack(["-c"], b"encrypted pack\n")
    assert pack(["-d"], ciphertext) == b"encrypted pack\n"


def test_stale_policy_and_symlinked_identity_home_do_not_generate_keys(
    machine, tmp_path
):
    descriptor, spec, manifest, _recovery_id, keyring, executable = machine
    with pytest.raises(local_git.GitError, match="differs"):
        local_git.setup(descriptor, {**manifest, "mode": "private"}, gpg=executable)
    assert not keyring.exists() and not Path(spec["home"]).exists()
    Path(spec["home"]).symlink_to(tmp_path / "recovery", target_is_directory=True)
    with pytest.raises(ValueError, match="symlink"):
        local_git.setup(descriptor, manifest, gpg=executable)
    assert not keyring.exists()
