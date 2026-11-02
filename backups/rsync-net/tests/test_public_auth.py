"""Public SSH sources remain bounded to root-managed forced-command key files."""

from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from test_planner import observed, policy

from rsync_net import apply as engine
from rsync_net import cli as core

SETTINGS = """pubkeyauthentication yes
strictmodes yes
usepam yes
permituserenvironment no
passwordauthentication no
kbdinteractiveauthentication no
hostbasedauthentication no
authorizedkeyscommand none
trustedusercakeys none
authorizedprincipalsfile none
authorizedprincipalscommand none
authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2
"""


def test_restic_configuration_is_explicit_and_keeps_append_only_path_binding():
    manifest = core.validate(policy())
    principal = manifest["principals"][1]
    path, content = core.backend_config(principal)
    assert path == Path(principal["home"]) / ".rclone.conf"
    assert "[repository]\ntype = local\n" in content
    command = core.authorization(manifest, principal)
    assert (
        f"--config {path} serve restic --stdio --append-only repository:/mnt/data1/user"
        in command
    )
    assert engine.preserves_authorization(
        core.legacy_authorization(manifest, principal),
        command,
        core.legacy_authorization(manifest, principal),
    )


@pytest.mark.parametrize(
    "replacement",
    [
        ("--append-only", ""),
        ("/mnt/data1/user", "/mnt/data1/other"),
        ("restrict,", ""),
        ("ssh-ed25519 ", "ssh-ed25519 unapproved"),
    ],
)
def test_backend_migration_never_accepts_different_keys_or_commands(replacement):
    manifest = core.validate(policy())
    principal = manifest["principals"][1]
    legacy = core.legacy_authorization(manifest, principal)
    assert not engine.preserves_authorization(
        legacy.replace(*replacement),
        core.authorization(manifest, principal),
        legacy,
    )


def test_backend_config_is_reviewed_before_bootstrap_and_untrusted_ownership_blocks():
    manifest = core.validate(policy())
    state = observed(manifest)
    principal = manifest["principals"][1]
    path, _ = core.backend_config(principal)
    state["files"][str(path)] = {"exists": False}
    actions = core.plan(manifest, state)["actions"]
    assert any(a["kind"] == "restore-backend-config" for a in actions)
    state["files"][str(path)] = {"exists": True, "uid": principal["uid"], "mode": 0o644}
    assert any(
        "backend configuration" in b for b in core.plan(manifest, state)["blockers"]
    )


def provider(tmp_path, monkeypatch):
    manifest = core.validate(policy())
    for principal in manifest["principals"]:
        principal["home"] = str(tmp_path / principal["name"])
        home = Path(principal["home"])
        (home / ".ssh").mkdir(parents=True)
        (home / ".ssh/authorized_keys").write_text(
            core.authorization(manifest, principal)
        )
    config = tmp_path / "sshd_config"
    config.write_text("# provider configuration remains unchanged\n")
    native = Mock(return_value=SETTINGS)
    monkeypatch.setattr(
        engine,
        "Path",
        lambda path: config if str(path) == "/etc/ssh/sshd_config" else Path(path),
    )
    monkeypatch.setattr(engine, "protected", Mock())
    monkeypatch.setattr(engine, "native", native)
    backend = SimpleNamespace(sshd="/usr/sbin/sshd", check_acl=Mock())
    return manifest, backend, native, config


def test_existing_managed_public_keys_are_accepted_without_a_fallback_database(
    tmp_path, monkeypatch
):
    manifest, backend, _, config = provider(tmp_path, monkeypatch)
    engine.public_policy(backend, manifest)
    assert config.read_text() == "# provider configuration remains unchanged\n"
    for principal in manifest["principals"]:
        assert (
            core.authorization_path(principal)
            == Path(principal["home"]) / ".ssh/authorized_keys"
        )


def test_secondary_undeclared_authorized_keys_is_refused(tmp_path, monkeypatch):
    manifest, backend, _, _ = provider(tmp_path, monkeypatch)
    (Path(manifest["principals"][0]["home"]) / ".ssh/authorized_keys2").write_text(
        "unmanaged public key\n"
    )
    with pytest.raises(engine.ApplyError, match="undeclared"):
        engine.public_policy(backend, manifest)


@pytest.mark.parametrize("enabled", ["yes", "no"])
def test_provider_keyboard_interactive_policy_is_retained(
    tmp_path, monkeypatch, enabled
):
    manifest, backend, native, config = provider(tmp_path, monkeypatch)
    native.return_value = (
        SETTINGS.replace(
            "kbdinteractiveauthentication no", f"kbdinteractiveauthentication {enabled}"
        )
        + "authenticationmethods any\n"
    )
    before = config.read_bytes()
    engine.public_policy(backend, manifest)
    assert config.read_bytes() == before


@pytest.mark.parametrize(
    "replacement",
    [
        ("authorizedkeyscommand none", "authorizedkeyscommand /unapproved-helper"),
        ("trustedusercakeys none", "trustedusercakeys /unapproved-ca"),
        ("passwordauthentication no", "passwordauthentication yes"),
        ("pubkeyauthentication yes", "pubkeyauthentication no"),
        ("strictmodes yes", "strictmodes no"),
        ("usepam yes", "usepam no"),
        ("permituserenvironment no", "permituserenvironment yes"),
        (
            "authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2",
            "authorizedkeysfile /other/keys/%u",
        ),
        (
            "authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2",
            "authorizedkeysfile .ssh/authorized_keys2",
        ),
    ],
)
def test_provider_authentication_drift_cannot_publish_public_authorization(
    tmp_path, monkeypatch, replacement
):
    manifest, backend, native, _ = provider(tmp_path, monkeypatch)
    native.return_value = SETTINGS.replace(*replacement)
    with pytest.raises(engine.ApplyError):
        engine.public_policy(backend, manifest)


def test_public_plan_retains_private_assets_and_refuses_private_activation():
    manifest = core.validate(policy())
    state = observed(manifest)
    state["files"][str(core.AUTHORIZATION_ROOT)] = {"exists": True, "symlink": True}
    assert not core.plan(manifest, state)["blockers"]
    assert not core.plan(manifest, state)["actions"]
    manifest["mode"] = "private"
    assert any("incomplete" in item for item in core.plan(manifest, state)["blockers"])


@pytest.mark.parametrize(
    "environment",
    [
        "acceptenv LD_PRELOAD\nacceptenv LANG LC_*\n",
        "acceptenv NIX_CONFIG\nacceptenv LANG\n",
        "acceptenv PYTHONPATH\n",
        "acceptenv *\n",
        "acceptenv BASH_ENV\n",
    ],
)
def test_all_client_environment_patterns_are_checked_before_key_publication(
    tmp_path, monkeypatch, environment
):
    manifest, backend, native, _ = provider(tmp_path, monkeypatch)
    native.return_value = SETTINGS + environment
    with pytest.raises(engine.ApplyError, match="unsafe client environment"):
        engine.public_policy(backend, manifest)


def test_locale_environment_acceptance_does_not_enable_program_configuration(
    tmp_path, monkeypatch
):
    manifest, backend, native, _ = provider(tmp_path, monkeypatch)
    native.return_value = SETTINGS + "acceptenv LANG\nacceptenv LC_*\n"
    engine.public_policy(backend, manifest)


@pytest.mark.parametrize(
    "output", [",pid=,comm=\n0\n2000\n", "0\n2000\n", "2000 incomplete\n"]
)
def test_native_managed_process_inspection_never_treats_malformed_bsd_output_as_idle(
    monkeypatch, output
):
    monkeypatch.setattr(core, "run_readonly", Mock(return_value=output))
    with pytest.raises(core.PolicyError, match="process inspection is incomplete"):
        core.active_processes({2000})


def test_native_managed_process_inspection_uses_separate_bsd_columns(monkeypatch):
    native = Mock(return_value="0 1 init\n2000 42 rclone\n2001 43 rsync\n")
    monkeypatch.setattr(core, "run_readonly", native)
    assert core.active_processes({2000}) == [
        {"uid": 2000, "pid": 42, "command": "rclone"}
    ]
    native.assert_called_once_with(
        ["/bin/ps", "-axww", "-o", "uid=", "-o", "pid=", "-o", "comm="]
    )
