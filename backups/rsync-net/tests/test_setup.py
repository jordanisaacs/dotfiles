"""Regress the configured native setup phases; VM tests exercise FreeBSD itself."""

import copy
import json
import subprocess
import sys
import syslog
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from test_planner import policy

from rsync_net import apply as rsync_apply
from rsync_net import cli as rsync_net
from rsync_net import setup

BASE_SERVICES = "# provider comments must be preserved\nssh\t22/tcp\t# secure shell\n"


@pytest.fixture(autouse=True)
def native_services_fixture(tmp_path, monkeypatch):
    services = tmp_path / "services"
    services.write_text(BASE_SERVICES)
    monkeypatch.setattr(setup, "SERVICES", services)


def configured():
    manifest = policy()
    manifest["setup"] = {
        "enable": True,
        "expectedRelease": "14.4-RELEASE",
        "backends": ["restic", "nix-cache"],
    }
    return rsync_net.validate(manifest)


def observed(*, prerequisites=True, managed=False):
    return {
        "system": "FreeBSD",
        "release": "14.4-RELEASE",
        "uid": "0",
        "pkgInstalled": prerequisites,
        "pythonInstalled": prerequisites,
        "providerInetd": "# provider has no configured inetd services\n",
        "services": setup.service_registration(
            BASE_SERVICES + (setup.SERVICE_ENTRY if managed else "")
        ),
        "inetdRc": setup.INETD_RC_CONTENT if managed else "",
        "localInetdRc": "",
        "inetdConfig": setup.INETD_CONTENT if managed else "",
        "inetdRunning": managed,
        "inetdProcesses": [
            {"uid": 0, "pid": 42, "arguments": "/usr/sbin/inetd " + setup.INETD_FLAGS}
        ]
        if managed
        else [],
        "providerRc": "",
        "providerRcLocal": "",
    }


def test_module_setup_defaults_and_exact_release_validation():
    manifest = rsync_net.validate(policy())
    assert manifest["setup"] == {
        "enable": False,
        "expectedRelease": None,
        "backends": ["restic"],
        "snapshotting": False,
    }
    assert setup.review(manifest, observed())["blockers"]
    manifest["setup"] = {"enable": True, "expectedRelease": "14.4-RELEASE;reboot"}
    with pytest.raises(rsync_net.PolicyError, match="release"):
        rsync_net.validate(manifest)


def test_review_binds_host_release_packages_and_manifest():
    manifest = configured()
    review = setup.review(manifest, observed(prerequisites=False))
    assert not review["blockers"]
    assert review["prePythonActions"] == [
        ["/usr/sbin/pkg", "bootstrap", "-y"],
        ["/usr/sbin/pkg", "install", "-y", "python311"],
    ]
    assert review["requiredPackages"] == ["nix", "rclone"]
    assert not review["atomic"]
    changed = copy.deepcopy(manifest)
    changed["connection"]["host"] = "different.invalid"
    assert (
        setup.review(changed, observed(prerequisites=False))["reviewDigest"]
        != review["reviewDigest"]
    )
    wrong = observed()
    wrong["release"] = "14.3-RELEASE"
    assert any("release" in x for x in setup.review(manifest, wrong)["blockers"])


@pytest.mark.parametrize(
    "field,value",
    [
        ("providerInetd", "ftp stream tcp nowait root /usr/libexec/ftpd ftpd -l\n"),
        ("inetdRc", 'inetd_enable="YES"\n'),
        ("localInetdRc", 'inetd_flags="/provider/inetd.conf"\n'),
        ("inetdRunning", True),
        ("providerRc", 'inetd_enable="YES"\n'),
        ("inetdConfig", "provider-owned config\n"),
    ],
)
def test_refuse_provider_inetd_takeover(field, value):
    state = observed()
    state[field] = value
    assert setup.service_conflicts(state)
    assert not setup.service_conflicts(observed(managed=True))


def args(tmp_path):
    known_hosts = tmp_path / "known-hosts"
    known_hosts.write_text("fixture-host ssh-ed25519 fixture-public-key\n")
    return SimpleNamespace(
        apply=True,
        review=tmp_path / "review.json",
        admin_identity=Path("/admin-key"),
        admin_agent_public_key=None,
        known_hosts=known_hosts,
    )


def test_stale_review_cannot_run_package_actions(tmp_path, monkeypatch):
    manifest = configured()
    options = args(tmp_path)
    options.review.write_text(
        json.dumps(
            setup.review(
                manifest,
                observed(prerequisites=False),
                transport=setup.transport_policy(options),
            )
        )
    )
    monkeypatch.setattr(setup, "probe", lambda *_: observed())
    invoke = Mock(return_value=subprocess.CompletedProcess([], 1, "", ""))
    remote = Mock()
    with pytest.raises(setup.SetupError, match="stale"):
        setup.setup(options, manifest, remote_run=invoke, remote_call=remote)
    assert invoke.call_count == 1
    assert invoke.call_args.args[1].startswith("/bin/test -x ")
    remote.assert_not_called()


def test_partial_prerequisite_failure_reports_completed_phase(tmp_path, monkeypatch):
    manifest = configured()
    options = args(tmp_path)
    state = observed(prerequisites=False)
    options.review.write_text(
        json.dumps(
            setup.review(manifest, state, transport=setup.transport_policy(options))
        )
    )
    monkeypatch.setattr(setup, "probe", lambda *_: state)
    invoke = Mock(
        side_effect=[
            subprocess.CompletedProcess([], 1, "", ""),
            subprocess.CompletedProcess([], 0, "", ""),
            subprocess.CompletedProcess([], 1, "", ""),
        ]
    )
    remote = Mock()
    with pytest.raises(setup.SetupError, match="pkg bootstrap.*partial changes"):
        setup.setup(options, manifest, remote_run=invoke, remote_call=remote)
    assert invoke.call_args.kwargs["timeout"] == 600
    assert invoke.call_args_list[1].args[1] == "/usr/sbin/pkg bootstrap -y"
    assert invoke.call_args_list[2].args[1] == "/usr/sbin/pkg install -y python311"
    remote.assert_not_called()


def remote_context(
    monkeypatch, *, managed=False, version="2.35.3", install_missing=False
):
    manifest = configured()
    setup.SERVICES.write_text(BASE_SERVICES + (setup.SERVICE_ENTRY if managed else ""))
    state = observed(managed=managed)
    reviewed = setup.review(manifest, state)
    monkeypatch.setattr(setup, "probe", lambda *_: state)
    backend = SimpleNamespace(check=Mock(), check_acl=Mock())
    engine = SimpleNamespace(
        FreeBSD=lambda: backend,
        supported_nix=rsync_apply.supported_nix,
        protected=Mock(),
        atomic_file=Mock(return_value=not managed),
        _reconstruct_locked=Mock(return_value={"changes": []}),
    )

    @contextmanager
    def host_lock():
        engine.lock_held = True
        try:
            yield
        finally:
            engine.lock_held = False

    engine.reconstruction_lock = host_lock
    engine.lock_held = False
    inspected = Mock(return_value={"postPackageUsers": True})
    calls = []

    def invoke(arguments, **kwargs):
        assert engine.lock_held, "native setup escaped the shared host lock"
        calls.append(arguments)
        assert kwargs["timeout"] == 600
        result = ""
        if arguments[:3] == ["/usr/local/sbin/pkg", "query", "%n"]:
            result = "" if install_missing else "nix\nrclone\ntailscale\n"
        elif arguments[:3] == ["/usr/local/sbin/pkg", "query", "%v"]:
            result = version + "\n"
        elif arguments[:2] == ["/usr/bin/sockstat", "-46l"]:
            result = "USER COMMAND PID FD PROTO LOCAL FOREIGN\nroot inetd 1 5 tcp4 127.0.0.1:2222 *:*\n"
        return subprocess.CompletedProcess(arguments, 0, result, "")

    monkeypatch.setattr(setup.subprocess, "run", invoke)
    context = {
        "load_helper": lambda _: engine,
        "config_path": Path("/private-config"),
        "reviewed": reviewed,
        "expected_digest": reviewed["reviewDigest"],
    }
    return manifest, context, engine, inspected, calls


def test_server_setup_installs_capabilities_without_backup_accounts(monkeypatch):
    manifest, context, engine, inspected, calls = remote_context(
        monkeypatch, install_missing=True
    )
    setup.configure_remote(manifest, **context)
    assert [
        "/usr/local/sbin/pkg",
        "install",
        "-y",
        "nix",
        "rclone",
    ] in calls
    inspected.assert_not_called()
    engine._reconstruct_locked.assert_not_called()
    engine.atomic_file.assert_not_called()


def test_server_packages_do_not_depend_on_backup_enrollment():
    manifest = configured()
    manifest["principals"] = []
    manifest["datasets"] = []
    assert setup.packages(manifest) == ["nix", "rclone"]


@pytest.mark.parametrize("version", ["2.32.4_6", "2.35.2", "unknown"])
def test_unsupported_nix_refused_before_authorization_or_service(monkeypatch, version):
    manifest, context, engine, inspected, calls = remote_context(
        monkeypatch, version=version
    )
    with pytest.raises(setup.SetupError, match="Nix >= 2.35.3"):
        setup.configure_remote(manifest, **context)
    inspected.assert_not_called()
    engine._reconstruct_locked.assert_not_called()
    engine.atomic_file.assert_not_called()
    assert not any("nix-store" in str(call) for call in calls)
    assert not any(call[:2] == ["/usr/sbin/service", "inetd"] for call in calls)


def test_identity_guard_failure_cannot_publish_or_start_service(monkeypatch):
    manifest, context, engine, _, calls = remote_context(monkeypatch)
    engine._reconstruct_locked.side_effect = ValueError(
        "reserved UID belongs to another account"
    )
    result = setup.configure_remote(manifest, **context)
    assert not result["accountReconstructionPerformed"]
    engine._reconstruct_locked.assert_not_called()
    engine.atomic_file.assert_not_called()
    assert not any(call[:2] == ["/usr/sbin/service", "inetd"] for call in calls)


def test_public_setup_does_not_create_or_restart_any_listener(monkeypatch):
    manifest, context, _, _, calls = remote_context(monkeypatch)
    result = setup.configure_remote(manifest, **context)
    assert not result["installedPackages"]
    assert not result["serviceConfigurationChanged"]
    assert not any(
        call[0] == "/usr/local/sbin/pkg" and "install" in call for call in calls
    )
    assert not any(
        call[:2] == ["/usr/sbin/service", "inetd"] and call[-1] != "onestatus"
        for call in calls
    )


def test_pre_python_probe_never_sources_rc_configuration():
    calls = []

    def invoke(arguments):
        calls.append(arguments)
        assert arguments[0] not in {
            "/usr/sbin/service",
            "/usr/sbin/sysrc",
            "/bin/sh",
            "/bin/csh",
        }
        output = {
            "/usr/bin/uname": "FreeBSD\n",
            "/bin/freebsd-version": "14.4-RELEASE\n",
            "/usr/bin/id": "0\n",
        }.get(arguments[0], "")
        if arguments[0] == "/bin/cat":
            output = "# literally read; never sourced\n"
        return subprocess.CompletedProcess(
            arguments, 1 if arguments[0] == "/bin/pgrep" else 0, output, ""
        )

    result = setup.probe(configured(), invoke)
    assert not result["inetdRunning"]
    assert [
        "/bin/ps",
        "-axww",
        "-o",
        "uid=",
        "-o",
        "pid=",
        "-o",
        "state=",
        "-o",
        "comm=",
        "-o",
        "args=",
    ] in calls


@pytest.mark.parametrize(
    "value", ["yes", "YES", "on", "true", "1", "${custom}", "$(do_something)"]
)
def test_unknown_or_enabled_rc_values_are_not_assumed_disabled(value):
    state = observed()
    state["providerRc"] = f'inetd_enable="{value}"\n'
    assert setup.service_conflicts(state)


@pytest.mark.parametrize("value", ["NO", "no", "off", "false", "0"])
def test_literal_disabled_rc_values_can_be_reserved(value):
    state = observed()
    state["providerRc"] = f'inetd_enable="{value}"\n'
    assert not setup.service_conflicts(state)


@pytest.mark.parametrize("variable", ["rc_conf_files", "local_startup"])
def test_custom_rc_source_paths_require_separate_review(variable):
    state = observed()
    state["providerRc"] = f'{variable}="/provider/custom"\n'
    assert setup.service_conflicts(state)


def test_changed_trusted_host_key_requires_fresh_review(tmp_path, monkeypatch):
    manifest = configured()
    options = args(tmp_path)
    state = observed(prerequisites=False)
    options.review.write_text(
        json.dumps(
            setup.review(manifest, state, transport=setup.transport_policy(options))
        )
    )
    options.known_hosts.write_text("fixture-host ssh-ed25519 changed-public-key\n")
    monkeypatch.setattr(setup, "probe", lambda *_: state)
    native = Mock()
    monkeypatch.setattr(setup.subprocess, "run", native)
    with pytest.raises(setup.SetupError, match="trusted transport"):
        setup.setup(options, manifest, remote_run=native, remote_call=Mock())
    native.assert_not_called()


def test_package_script_inetd_changes_block_publication(monkeypatch):
    manifest, context, engine, inspected, calls = remote_context(
        monkeypatch, install_missing=True
    )
    changed = observed()
    changed["providerInetd"] = "ftp stream tcp nowait root /usr/libexec/ftpd ftpd\n"
    monkeypatch.setattr(setup, "probe", Mock(side_effect=[observed(), changed]))
    with pytest.raises(setup.SetupError, match="inetd state changed after package"):
        setup.configure_remote(manifest, **context)
    assert any("install" in call for call in calls)
    inspected.assert_not_called()
    engine._reconstruct_locked.assert_not_called()
    engine.atomic_file.assert_not_called()
    assert not engine.lock_held


def test_rc_file_acl_is_checked_before_packages_or_service(tmp_path, monkeypatch):
    manifest, context, engine, _, calls = remote_context(monkeypatch, managed=True)
    rc_file = tmp_path / "inetd-rc"
    rc_file.write_text(setup.INETD_RC_CONTENT)
    monkeypatch.setattr(setup, "INETD_RC", rc_file)

    def acl(path):
        if path == rc_file:
            raise ValueError("nontrivial native RC ACL")

    engine.FreeBSD().check_acl.side_effect = acl
    with pytest.raises(setup.SetupError, match="native RC ACL"):
        setup.configure_remote(manifest, **context)
    assert calls == []
    engine.atomic_file.assert_not_called()
    assert not engine.lock_held


def test_shared_host_lock_contention_prevents_native_setup(monkeypatch):
    manifest, context, engine, _, calls = remote_context(monkeypatch)

    @contextmanager
    def busy():
        raise ValueError("another bootstrap is running")
        yield

    engine.reconstruction_lock = busy
    with pytest.raises(ValueError, match="another bootstrap"):
        setup.configure_remote(manifest, **context)
    assert calls == []
    engine._reconstruct_locked.assert_not_called()
    engine.atomic_file.assert_not_called()


@pytest.mark.parametrize(
    "entry",
    [
        "other-service 2222/tcp\n",
        "other-service 02222/tcp\n",
        "rsync-net-ssh 9999/tcp\n",
        "other-service 9999/tcp rsync-net-ssh\n",
        "rsync-net-ssh 2222/udp\n",
        setup.SERVICE_ENTRY * 2,
        "+\n",
    ],
)
def test_service_registration_refuses_provider_name_port_and_nis_collisions(entry):
    state = observed()
    state["services"] = setup.service_registration(BASE_SERVICES + entry)
    assert state["services"]["blockers"]


def test_private_activation_is_blocked_before_native_or_package_actions(
    tmp_path, monkeypatch
):
    manifest = configured()
    manifest["mode"] = "private"
    native = Mock()
    monkeypatch.setattr(setup.subprocess, "run", native)
    helper = Mock()
    with pytest.raises(setup.SetupError, match="private mode is incomplete"):
        setup.configure_remote(manifest, load_helper=helper)
    with pytest.raises(setup.SetupError, match="private mode is incomplete"):
        setup.setup(args(tmp_path), manifest, remote_run=Mock(), remote_call=Mock())
    helper.assert_not_called()
    native.assert_not_called()
    backend = Mock()
    with pytest.raises(rsync_apply.ApplyError, match="private mode is incomplete"):
        rsync_apply.reconstruct(manifest, backend=backend)
    backend.check.assert_not_called()


def test_unrelated_provider_inetd_is_inventoried_without_service_or_file_changes():
    state = observed()
    state.update(
        inetdRc='inetd_enable="YES"\n',
        inetdConfig="provider-owned config\n",
        inetdRunning=True,
    )
    assert setup.inetd_status(state) == "provider"
    assert not setup.public_service_conflicts(state)
    engine = SimpleNamespace(atomic_file=Mock())
    invoke = Mock()
    result = setup.retire_inetd(state, engine=engine, backend=Mock(), invoke=invoke)
    assert result == {"state": "provider", "changed": False, "filesRetained": True}
    engine.atomic_file.assert_not_called()
    invoke.assert_not_called()


def test_managed_inetd_is_stopped_disabled_and_all_data_retained(tmp_path, monkeypatch):
    state = observed(managed=True)
    pid = tmp_path / "inetd.pid"
    pid.write_text("42\n")
    monkeypatch.setattr(setup, "INETD_PID", pid)
    engine = SimpleNamespace(protected=Mock(), atomic_file=Mock(return_value=True))
    calls = []

    def invoke(arguments, **_options):
        calls.append(arguments)
        return subprocess.CompletedProcess(
            arguments, 1 if arguments[0] == "/bin/pgrep" else 0, "", ""
        )

    result = setup.retire_inetd(state, engine=engine, backend=Mock(), invoke=invoke)
    assert calls == [
        ["/usr/sbin/service", "inetd", "onestop"],
        [
            "/bin/ps",
            "-axww",
            "-o",
            "uid=",
            "-o",
            "pid=",
            "-o",
            "state=",
            "-o",
            "comm=",
            "-o",
            "args=",
        ],
        ["/usr/bin/sockstat", "-46l", "-P", "tcp", "-p", "2222"],
    ]
    engine.atomic_file.assert_called_once_with(
        setup.INETD_RC, setup.INETD_DISABLED_RC_CONTENT
    )
    assert result["state"] == "managed-disabled" and result["filesRetained"]
    assert pid.read_text() == "42\n"


@pytest.mark.parametrize(
    "mutation",
    [
        {"inetdConfig": "provider-owned config\n"},
        {"localInetdRc": 'inetd_flags="different"\n'},
        {
            "inetdProcesses": [
                {"uid": 0, "pid": 42, "arguments": "/usr/sbin/inetd /etc/inetd.conf"}
            ]
        },
        {
            "inetdProcesses": [
                {
                    "uid": 1000,
                    "pid": 42,
                    "arguments": "/usr/sbin/inetd " + setup.INETD_FLAGS,
                }
            ]
        },
    ],
)
def test_ambiguous_inetd_is_never_stopped_or_reconfigured(mutation):
    state = observed(managed=True)
    state.update(mutation)
    assert setup.public_service_conflicts(state)
    engine = SimpleNamespace(atomic_file=Mock())
    invoke = Mock()
    with pytest.raises(setup.SetupError, match="ambiguous"):
        setup.retire_inetd(state, engine=engine, backend=Mock(), invoke=invoke)
    engine.atomic_file.assert_not_called()
    invoke.assert_not_called()


def test_managed_pid_mismatch_cannot_stop_a_provider_service(tmp_path, monkeypatch):
    state = observed(managed=True)
    pid = tmp_path / "inetd.pid"
    pid.write_text("99\n")
    monkeypatch.setattr(setup, "INETD_PID", pid)
    engine = SimpleNamespace(protected=Mock(), atomic_file=Mock())
    invoke = Mock()
    with pytest.raises(setup.SetupError, match="PID does not match"):
        setup.retire_inetd(state, engine=engine, backend=Mock(), invoke=invoke)
    engine.atomic_file.assert_not_called()
    invoke.assert_not_called()


def retirement_probe(states, *, listeners=None):
    rows = iter(states)
    current = None
    calls = []

    def invoke(arguments, **options):
        assert 0 < options["timeout"] <= 5.0
        nonlocal current
        calls.append(arguments)
        if arguments[0] == "/bin/ps":
            current = next(rows)
            output = current
        else:
            output = "USER COMMAND PID FD PROTO LOCAL FOREIGN\n" + (
                listeners(current) if listeners else ""
            )
        return subprocess.CompletedProcess(arguments, 0, output, "")

    return invoke, calls


def test_retirement_waits_for_asynchronous_verified_daemon_exit(monkeypatch):
    state = observed(managed=True)
    live = "0 42 S inetd " + state["inetdProcesses"][0]["arguments"] + "\n"
    invoke, calls = retirement_probe([live, ""])
    sleep = Mock()
    monkeypatch.setattr(setup.time, "sleep", sleep)
    setup.wait_for_inetd_retirement(state, invoke=invoke)
    assert sleep.call_count == 1
    assert len(calls) == 4
    assert not any(call[0] in {"/bin/kill", "/usr/bin/killall"} for call in calls)


def test_retirement_accepts_unreaped_verified_zombie_only_without_listener(monkeypatch):
    state = observed(managed=True)
    invoke, _ = retirement_probe(["0 42 Z inetd <defunct>\n"])
    sleep = Mock()
    monkeypatch.setattr(setup.time, "sleep", sleep)
    setup.wait_for_inetd_retirement(state, invoke=invoke)
    sleep.assert_not_called()


def test_retirement_zombie_still_requires_private_socket_to_disappear(monkeypatch):
    state = observed(managed=True)
    invoke, _ = retirement_probe(
        ["0 42 Z inetd <defunct>\n", ""],
        listeners=lambda current: (
            "root inetd 42 5 tcp4 127.0.0.1:2222 *:*\n" if current else ""
        ),
    )
    sleep = Mock()
    monkeypatch.setattr(setup.time, "sleep", sleep)
    setup.wait_for_inetd_retirement(state, invoke=invoke)
    sleep.assert_called_once()


def test_retirement_timeout_never_sends_extra_signals(monkeypatch):
    state = observed(managed=True)
    invoke, calls = retirement_probe(
        ["0 42 S inetd " + state["inetdProcesses"][0]["arguments"] + "\n"]
    )
    monkeypatch.setattr(setup.time, "monotonic", Mock(side_effect=[0, 0, 0, 16]))
    with pytest.raises(setup.SetupError, match="bounded wait.*no further signals"):
        setup.wait_for_inetd_retirement(state, invoke=invoke)
    assert all(call[0] in {"/bin/ps", "/usr/bin/sockstat"} for call in calls)


@pytest.mark.parametrize(
    "row",
    [
        "0 99 S inetd /usr/sbin/inetd /etc/inetd.conf\n",
        "0 42 S different /usr/sbin/provider-daemon\n",
        "1000 42 Z inetd <defunct>\n",
    ],
)
def test_retirement_does_not_touch_unknown_or_reused_processes(row):
    state = observed(managed=True)
    invoke, calls = retirement_probe([row])
    with pytest.raises(setup.SetupError, match="replacement"):
        setup.wait_for_inetd_retirement(state, invoke=invoke)
    assert calls == [
        [
            "/bin/ps",
            "-axww",
            "-o",
            "uid=",
            "-o",
            "pid=",
            "-o",
            "state=",
            "-o",
            "comm=",
            "-o",
            "args=",
        ]
    ]


def test_preflight_ignores_unreaped_inetd_zombies_for_idempotent_reapply():
    def invoke(arguments):
        output = {
            "/usr/bin/uname": "FreeBSD\n",
            "/bin/freebsd-version": "14.4-RELEASE\n",
            "/usr/bin/id": "0\n",
        }.get(arguments[0], "")
        if arguments[0] == "/bin/ps":
            output = "0 42 Z inetd <defunct>\n"
        if arguments[0] == "/bin/cat":
            output = "# fixture\n"
        return subprocess.CompletedProcess(arguments, 0, output, "")

    state = setup.probe(configured(), invoke)
    assert not state["inetdRunning"]
    assert state["inetdProcesses"] == []


def test_retirement_malformed_bsd_ps_output_cannot_be_claimed_as_stopped():
    invoke, _ = retirement_probe([",pid=,state=,comm=,args=\n0\n"])
    with pytest.raises(setup.SetupError, match="termination inspection is incomplete"):
        setup.wait_for_inetd_retirement(observed(managed=True), invoke=invoke)


def test_managed_retirement_retry_stops_verified_daemon_even_when_rc_already_disabled(
    tmp_path, monkeypatch
):
    state = observed(managed=True)
    state["inetdRc"] = setup.INETD_DISABLED_RC_CONTENT
    assert setup.inetd_status(state) == "managed-active"
    pid = tmp_path / "inetd.pid"
    pid.write_text("42\n")
    monkeypatch.setattr(setup, "INETD_PID", pid)
    engine = SimpleNamespace(protected=Mock(), atomic_file=Mock(return_value=False))
    calls = []

    def invoke(arguments, **_options):
        calls.append(arguments)
        return subprocess.CompletedProcess(arguments, 0, "", "")

    result = setup.retire_inetd(state, engine=engine, backend=Mock(), invoke=invoke)
    assert calls[0] == ["/usr/sbin/service", "inetd", "onestop"]
    assert result["state"] == "managed-disabled"
    assert result["changed"] and result["filesRetained"]
    engine.atomic_file.assert_called_once_with(
        setup.INETD_RC, setup.INETD_DISABLED_RC_CONTENT
    )


def test_warm_review_batches_native_preflight_into_one_rpc(tmp_path, monkeypatch):
    manifest = configured()
    options = args(tmp_path)
    options.apply = False
    options.review = None
    native = Mock(return_value=subprocess.CompletedProcess([], 0, "", ""))
    rpc = Mock(return_value={"blockers": []})
    monkeypatch.setattr(
        setup,
        "probe",
        Mock(side_effect=AssertionError("warm review must probe on the server")),
    )
    assert setup.setup(options, manifest, remote_run=native, remote_call=rpc) == {
        "blockers": []
    }
    assert native.call_count == 1
    assert rpc.call_count == 1 and rpc.call_args.args[1] == "_setup-review"
    assert rpc.call_args.kwargs["payload"]["transport"] == setup.transport_policy(
        options
    )


def test_warm_apply_sends_saved_review_and_current_trust_in_one_rpc(
    tmp_path, monkeypatch
):
    manifest = configured()
    options = args(tmp_path)
    saved = setup.review(
        manifest, observed(), transport=setup.transport_policy(options)
    )
    options.review.write_text(json.dumps(saved))
    native = Mock(return_value=subprocess.CompletedProcess([], 0, "", ""))
    rpc = Mock(return_value={"completedPhases": ["accounts"]})
    monkeypatch.setattr(
        setup,
        "probe",
        Mock(
            side_effect=AssertionError(
                "warm apply freshness must be checked on the server"
            )
        ),
    )
    setup.setup(options, manifest, remote_run=native, remote_call=rpc)
    assert native.call_count == 1
    assert rpc.call_count == 1 and rpc.call_args.args[1] == "_setup"
    assert rpc.call_args.kwargs["payload"] == {
        "review": saved,
        "transport": setup.transport_policy(options),
        "prerequisitesPrepared": False,
    }
    assert rpc.call_args.kwargs["review_digest"] == saved["reviewDigest"]


def test_warm_rpc_rechecks_changed_prerequisite_state_before_any_package_action(
    monkeypatch,
):
    manifest, context, engine, _, calls = remote_context(monkeypatch)
    monkeypatch.setattr(setup, "probe", lambda *_: observed(prerequisites=False))
    with pytest.raises(setup.SetupError, match="changed after review"):
        setup.configure_remote(manifest, **context)
    assert calls == []
    engine._reconstruct_locked.assert_not_called()


def test_warm_rpc_binds_current_trust_descriptor_before_native_mutation(monkeypatch):
    manifest, context, engine, _, calls = remote_context(monkeypatch)
    context["transport"] = {"knownHostsSha256": "changed"}
    with pytest.raises(setup.SetupError, match="review digest"):
        setup.configure_remote(manifest, **context)
    assert calls == []
    engine._reconstruct_locked.assert_not_called()


def test_server_progress_is_static_stderr_and_stdout_stays_clean(monkeypatch, capsys):
    manifest, context, _, _, _ = remote_context(monkeypatch)
    setup.configure_remote(manifest, **context)
    output = capsys.readouterr()
    assert output.out == ""
    assert output.err.splitlines() == [
        "rsync-net: phase " + phase
        for phase in ("review", "packages", "inetd", "complete")
    ]


def test_server_logs_phase_before_disconnected_client_stderr(monkeypatch):
    events = []
    monkeypatch.setattr(
        setup, "os", SimpleNamespace(uname=lambda: SimpleNamespace(sysname="FreeBSD"))
    )
    monkeypatch.setattr(syslog, "openlog", Mock())
    monkeypatch.setattr(syslog, "syslog", lambda *_: events.append("syslog"))

    def disconnected(_text):
        events.append("stderr")
        raise BrokenPipeError

    with monkeypatch.context() as stream:
        stream.setattr(sys, "stderr", SimpleNamespace(write=disconnected, flush=Mock()))
        setup.progress("packages")
    assert events == ["syslog", "stderr"]
