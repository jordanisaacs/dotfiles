"""Reviewed native FreeBSD server prerequisites and legacy listener retirement.

Package installation is deliberately separate from guarded account restoration.
Later per-backup bootstrap independently reinspects package-created identities.
No package repository, OS upgrade, public SSH, storage or Tailscale enrollment
is changed. Interrupted runs require a new review and retain completed phases.
"""

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

PYTHON = "/usr/local/bin/python3.11"
SERVICE_NAME = "rsync-net-ssh"
SERVICES = Path("/etc/services")
SERVICES_DB = Path("/var/db/services.db")
SERVICE_ENTRY = f"{SERVICE_NAME}\t2222/tcp\t# rsync-net private SSH\n"
INETD_CONFIG = Path("/usr/local/etc/rsync-net/inetd.conf")
INETD_RC = Path("/etc/rc.conf.d/inetd")
LOCAL_INETD_RC = Path("/usr/local/etc/rc.conf.d/inetd")
INETD_FLAGS = f"-wW -a 127.0.0.1 {INETD_CONFIG}"
INETD_RC_CONTENT = f'inetd_enable="YES"\ninetd_flags="{INETD_FLAGS}"\n'
INETD_DISABLED_RC_CONTENT = INETD_RC_CONTENT.replace(
    'inetd_enable="YES"', 'inetd_enable="NO"'
)
INETD_PID = Path("/var/run/inetd.pid")
INETD_CONTENT = (
    f"{SERVICE_NAME} stream tcp nowait root /usr/sbin/sshd "
    "sshd -i -f /usr/local/etc/rsync-net/sshd-private.conf\n"
)


class SetupError(ValueError):
    """A refused or incomplete native setup phase."""


def require(condition, message):
    if not condition:
        raise SetupError(message)


def progress(phase):
    require(
        phase
        in {"review", "prerequisites", "packages", "accounts", "inetd", "complete"},
        "invalid progress phase",
    )
    if os.uname().sysname == "FreeBSD":
        import syslog

        syslog.openlog("rsync-net", syslog.LOG_PID, syslog.LOG_DAEMON)
        syslog.syslog(syslog.LOG_NOTICE, "phase " + phase)
    try:
        print("rsync-net: phase " + phase, file=sys.stderr, flush=True)
    except BrokenPipeError:
        pass  # Native phase notice remains available after a client disconnect.


def review_remote(manifest, *, transport):
    require(os.uname().sysname == "FreeBSD", "setup review requires FreeBSD")
    progress("review")

    def invoke(arguments):
        return subprocess.run(
            arguments, input="", capture_output=True, text=True, timeout=60, check=False
        )

    result = review(manifest, probe(manifest, invoke), transport=transport)
    progress("complete")
    return result


def packages(manifest):
    return sorted(
        ({"tailscale"} if manifest["mode"] == "private" else set())
        | ({"zfsnap2"} if manifest["setup"]["snapshotting"] else set())
        | {
            {"restic": "rclone", "git": "rsync", "nix-cache": "nix"}[backend]
            for backend in manifest["setup"]["backends"]
        }
    )


def active_lines(content):
    return [
        line
        for line in content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def service_registration(content):
    """Reserve one native service name/port without rewriting provider entries."""
    blockers, found = [], False
    if not content:
        blockers.append("provider /etc/services is missing or empty")
    for line in content.splitlines():
        fields = line.split("#", 1)[0].split()
        if not fields:
            continue
        if fields == ["+"]:
            blockers.append("NIS services expansion requires separate review")
        relevant = SERVICE_NAME in fields[:1] + fields[2:]
        if len(fields) >= 2:
            port, _, protocol = fields[1].partition("/")
            relevant |= (
                port.isdigit() and int(port) == 2222 and protocol.lower() == "tcp"
            )
        if relevant:
            if line != SERVICE_ENTRY.rstrip("\n") or found:
                blockers.append(
                    "private SSH service name/port conflicts with an existing provider entry"
                )
            found = True
    return {
        "sha256": hashlib.sha256(content.encode()).hexdigest(),
        "needed": not found,
        "blockers": blockers,
    }


def inetd_status(state):
    """Identify only the exact retained service this controller used to own."""
    expected_config = state["inetdConfig"] == INETD_CONTENT
    expected_rc = state["inetdRc"] in {INETD_RC_CONTENT, INETD_DISABLED_RC_CONTENT}
    hinted = expected_config or INETD_FLAGS in state["inetdRc"]
    if not hinted:
        return (
            "provider"
            if state["inetdRc"] or state["inetdConfig"] or state["inetdRunning"]
            else "absent"
        )
    if (
        not expected_config
        or not expected_rc
        or state["localInetdRc"]
        or active_lines(state["providerInetd"])
    ):
        return "ambiguous"
    for content in (state["providerRc"], state["providerRcLocal"]):
        for line in active_lines(content):
            if "rc_conf_files" in line or "local_startup" in line:
                return "ambiguous"
            if re.search(r"\binetd\w*", line) and not re.fullmatch(
                r"\s*inetd_enable=(?P<quote>[\"']?)(?:no|false|off|0)(?P=quote)\s*(?:#.*)?",
                line,
                re.IGNORECASE,
            ):
                return "ambiguous"
    if state["inetdRunning"]:
        processes = state.get("inetdProcesses", [])
        if len(processes) != 1 or processes[0]["uid"] != 0:
            return "ambiguous"
        try:
            arguments = shlex.split(processes[0]["arguments"])
        except ValueError:
            return "ambiguous"
        if (
            not arguments
            or Path(arguments[0]).name != "inetd"
            or arguments[1:] != shlex.split(INETD_FLAGS)
        ):
            return "ambiguous"
    return (
        "managed-disabled"
        if state["inetdRc"] == INETD_DISABLED_RC_CONTENT and not state["inetdRunning"]
        else "managed-active"
    )


def public_service_conflicts(state):
    return (
        ["managed inetd ownership is ambiguous; provider service was left untouched"]
        if inetd_status(state) == "ambiguous"
        else []
    )


def service_conflicts(state):
    problems = list(state["services"]["blockers"])
    if active_lines(state["providerInetd"]):
        problems.append(
            "provider /etc/inetd.conf contains services; cannot take over inetd"
        )
    if state["inetdRc"] and state["inetdRc"] != INETD_RC_CONTENT:
        problems.append("provider inetd rc configuration differs; cannot replace it")
    if state["inetdConfig"] and state["inetdConfig"] != INETD_CONTENT:
        problems.append("existing private inetd configuration differs")
    if state["localInetdRc"]:
        problems.append(
            "local provider inetd rc configuration requires separate review"
        )
    for content in (state["providerRc"], state["providerRcLocal"]):
        for line in active_lines(content):
            if "rc_conf_files" in line or "local_startup" in line:
                problems.append(
                    "custom rc_conf_files/local_startup requires separate source-path review"
                )
            # Only literal disabled values are safe to reserve. Shell expansion,
            # checkyesno aliases and unknown assignments never imply disabled.
            if re.search(r"\binetd\w*", line) and not re.fullmatch(
                r"\s*inetd_enable=(?P<quote>[\"']?)(?:no|false|off|0)(?P=quote)\s*(?:#.*)?",
                line,
                re.IGNORECASE,
            ):
                problems.append("provider RC contains custom/enabled inetd settings")
    managed = (
        state["inetdRc"] == INETD_RC_CONTENT and state["inetdConfig"] == INETD_CONTENT
    )
    if state["inetdRunning"] and not managed:
        problems.append(
            "provider inetd is enabled/running and is not this managed listener"
        )
    return problems


def probe(manifest, invoke):
    """Only fixed base-system argv; works before Python or pkg is installed."""

    def output(arguments, *, optional=False):
        result = invoke(arguments)
        require(
            optional or result.returncode == 0,
            f"native setup inspection failed: {arguments[0]}",
        )
        return result.stdout.strip() if result.returncode == 0 else ""

    def content(path):
        result = invoke(["/bin/cat", str(path)])
        if result.returncode == 0:
            return result.stdout
        # Missing is expected; distinguish it from an unreadable existing file.
        missing = invoke(["/bin/test", "-e", str(path)]).returncode == 1
        symlink = invoke(["/bin/test", "-L", str(path)]).returncode == 0
        require(missing and not symlink, f"cannot inspect setup configuration: {path}")
        return ""

    processes = []
    for line in output(
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
    ).splitlines():
        values = line.split(None, 4)
        if not line.strip():
            continue
        require(
            len(values) >= 4 and values[0].isdigit() and values[1].isdigit(),
            "native ps output is malformed; inetd inspection is incomplete",
        )
        if values[2].startswith("Z"):
            continue
        if Path(values[3].strip("()")).name == "inetd":
            require(
                len(values) == 5 and values[0].isdigit() and values[1].isdigit(),
                "cannot inspect native inetd process ownership",
            )
            processes.append(
                {"uid": int(values[0]), "pid": int(values[1]), "arguments": values[4]}
            )
    return {
        "system": output(["/usr/bin/uname", "-s"]),
        "release": output(["/bin/freebsd-version", "-u"]),
        "uid": output(["/usr/bin/id", "-u"]),
        "pkgInstalled": invoke(["/usr/sbin/pkg", "-N"]).returncode == 0,
        "pythonInstalled": invoke(
            ["/bin/test", "-x", manifest["connection"]["interpreter"]]
        ).returncode
        == 0,
        "services": service_registration(content(SERVICES)),
        "providerInetd": content("/etc/inetd.conf"),
        "providerRc": content("/etc/rc.conf"),
        "providerRcLocal": content("/etc/rc.conf.local"),
        "inetdRc": content(INETD_RC),
        "localInetdRc": content(LOCAL_INETD_RC),
        "inetdConfig": content(INETD_CONFIG),
        "inetdRunning": bool(processes),
        "inetdProcesses": processes,
    }


def review(manifest, state, *, transport=None):
    policy = manifest["setup"]
    blockers = (
        public_service_conflicts(state)
        if manifest["mode"] == "public"
        else service_conflicts(state)
    )
    if manifest["mode"] == "private":
        blockers.append("private mode is incomplete; activation is disabled")
    if not policy["enable"]:
        blockers.append("native setup is disabled")
    if policy["expectedRelease"] is None:
        blockers.append("exact provider FreeBSD release is not approved")
    elif state["release"] != policy["expectedRelease"]:
        blockers.append("provider release differs from the approved release")
    if state["system"] != "FreeBSD" or state["uid"] != "0":
        blockers.append("setup requires native FreeBSD and administrative root SSH")
    if manifest["connection"]["interpreter"] != PYTHON:
        blockers.append("native setup supports the declared python311 interpreter only")
    actions = []
    if not state["pkgInstalled"]:
        actions.append(["/usr/sbin/pkg", "bootstrap", "-y"])
    if not state["pythonInstalled"]:
        actions.append(["/usr/sbin/pkg", "install", "-y", "python311"])
    result = {
        "operation": "native-freebsd-setup-review",
        "schemaVersion": 1,
        "host": manifest["connection"],
        "transport": transport,
        "state": state,
        "blockers": blockers,
        "prePythonActions": actions,
        "requiredPackages": packages(manifest),
        "inetd": {
            "state": inetd_status(state),
            "action": "stop and disable only the recognized managed listener; retain all files"
            if inetd_status(state) == "managed-active"
            else "retain unchanged",
        },
        "serviceRegistration": None
        if manifest["mode"] == "public"
        else {
            "path": str(SERVICES),
            "entry": SERVICE_ENTRY.rstrip("\n"),
            "needed": state["services"]["needed"],
            "database": str(SERVICES_DB),
            "rebuildCommand": ["/usr/sbin/services_mkdb", str(SERVICES)],
        },
        "phases": [
            "native pkg/python311 prerequisites using current provider repositories and trust",
            "install missing backend packages with native pkg; package scripts may create users",
            "leave backup accounts, device authorization and repository storage to separate storage init and bootstrap operations",
            "disable only a recognized retained managed inetd instance",
        ],
        "atomic": False,
        "retry": "Inspect partial state and create a fresh setup review after any interrupted phase.",
        "tailscaleEnrollment": "not performed; private network enrollment/Serve remains a separate approved operation",
        "storageMutationPerformed": False,
    }
    result["reviewDigest"] = hashlib.sha256(
        json.dumps(
            {"manifest": manifest, "review": result},
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    return result


def transport_policy(args):
    require(
        args.known_hosts is not None, "setup requires an explicit --known-hosts file"
    )
    path = Path(args.known_hosts)
    require(path.is_file(), "setup trusted host-key file does not exist")
    return {
        "knownHostsSha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "administrativeIdentity": str(
            args.admin_identity or args.admin_agent_public_key
        ),
        "agentIdentity": args.admin_agent_public_key is not None,
    }


def setup(args, manifest, *, remote_run, remote_call):
    if args.apply:
        require(
            manifest["mode"] == "public",
            "private mode is incomplete; activation is disabled",
        )
        require(args.review is not None, "setup requires a saved --review")
    require(args.apply or args.review is None, "--review is only used with --apply")
    transport = transport_policy(args)
    administrative = {
        "admin_identity": args.admin_identity,
        "admin_agent_public_key": args.admin_agent_public_key,
        "known_hosts": args.known_hosts,
    }
    saved = json.loads(args.review.read_text()) if args.apply else None
    if args.apply:
        require(
            isinstance(saved, dict) and isinstance(saved.get("state"), dict),
            "invalid saved setup review",
        )
        require(
            review(manifest, saved["state"], transport=transport)["reviewDigest"]
            == saved.get("reviewDigest"),
            "setup review belongs to a different policy or trusted transport",
        )
        require(not saved.get("blockers"), "setup review contains blockers")

    def invoke(arguments, *, timeout=60):
        return remote_run(
            manifest, shlex.join(arguments), timeout=timeout, **administrative
        )

    interpreter = invoke(["/bin/test", "-x", manifest["connection"]["interpreter"]])
    require(
        interpreter.returncode in {0, 1},
        "cannot inspect provider Python availability; no fallback authentication attempted",
    )
    if interpreter.returncode == 0:
        if not args.apply:
            return remote_call(
                manifest,
                "_setup-review",
                payload={"transport": transport},
                **administrative,
            )
        # Warm apply refreshes and verifies the reviewed host state within the
        # single locked RPC, before installing packages or publishing accounts.
        return remote_call(
            manifest,
            "_setup",
            payload={
                "review": saved,
                "transport": transport,
                "prerequisitesPrepared": False,
            },
            review_digest=saved["reviewDigest"],
            **administrative,
        )

    progress("review")
    current = review(manifest, probe(manifest, invoke), transport=transport)
    if not args.apply:
        progress("complete")
        return current
    require(
        saved["reviewDigest"] == current["reviewDigest"],
        "setup review is stale or belongs to a different host/policy",
    )
    require(
        not current["blockers"],
        "setup review contains blockers: " + "; ".join(current["blockers"]),
    )
    completed = []
    try:
        if current["prePythonActions"]:
            progress("prerequisites")
        for arguments in current["prePythonActions"]:
            result = invoke(arguments, timeout=600)
            require(
                result.returncode == 0,
                f"native prerequisite failed: {arguments}; package changes may remain",
            )
            completed.append(" ".join(arguments))
        result = remote_call(
            manifest,
            "_setup",
            payload={
                "review": current,
                "transport": transport,
                "prerequisitesPrepared": True,
            },
            review_digest=current["reviewDigest"],
            **administrative,
        )
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        raise SetupError(
            f"setup incomplete after {completed!r}: {error}; partial changes may remain, inspect and create a fresh review before retry"
        ) from error
    result["completedPhases"] = completed + result["completedPhases"]
    return result


def configure_remote(manifest, *, load_helper, **parameters):
    require(
        manifest["mode"] == "public",
        "private mode is incomplete; activation is disabled",
    )
    engine = load_helper("apply")
    backend = engine.FreeBSD()
    backend.check()
    # Package scripts and service changes share the same
    # host-wide lock as ordinary bootstrap; no nested flock is acquired.
    with engine.reconstruction_lock():
        return _configure_locked(manifest, engine=engine, backend=backend, **parameters)


def _configure_locked(
    manifest,
    *,
    engine,
    backend,
    config_path,
    reviewed,
    expected_digest,
    transport=None,
    prerequisites_prepared=False,
):
    completed = []

    def invoke(arguments, *, timeout=600):
        return subprocess.run(
            arguments,
            input="",
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )

    try:
        progress("review")
        require(
            type(prerequisites_prepared) is bool,
            "invalid prerequisite preparation state",
        )
        require(
            isinstance(reviewed, dict) and isinstance(reviewed.get("state"), dict),
            "missing saved setup review",
        )
        require(
            review(
                manifest,
                reviewed["state"],
                transport=transport
                if transport is not None
                else reviewed.get("transport"),
            )["reviewDigest"]
            == expected_digest,
            "invalid saved setup review digest",
        )
        observed = probe(manifest, invoke)
        for key, value in reviewed["state"].items():
            if not prerequisites_prepared or key not in {
                "pkgInstalled",
                "pythonInstalled",
            }:
                require(
                    observed.get(key) == value,
                    "provider setup state changed after review: " + key,
                )
        require(
            observed["pkgInstalled"] and observed["pythonInstalled"],
            "native prerequisites are incomplete",
        )
        preflight = review(manifest, observed)
        require(
            not preflight["blockers"],
            "native setup preflight contains blockers: "
            + "; ".join(preflight["blockers"]),
        )

        def guard_service_authority():
            paths = [Path("/usr/local/sbin/pkg"), Path(PYTHON)]
            if inetd_status(observed).startswith("managed-"):
                paths += [INETD_PID, Path(config_path)]
            if manifest["mode"] == "private" or inetd_status(observed).startswith(
                "managed-"
            ):
                paths += [
                    SERVICES,
                    SERVICES_DB,
                    Path(str(SERVICES_DB) + ".tmp"),
                    Path("/usr/sbin/services_mkdb"),
                    Path("/etc/nsswitch.conf"),
                    INETD_RC,
                    LOCAL_INETD_RC,
                    INETD_CONFIG,
                    Path("/etc/inetd.conf"),
                    Path("/etc/rc.conf"),
                    Path("/etc/rc.conf.local"),
                    Path("/etc/defaults/rc.conf"),
                    Path("/etc/rc.subr"),
                    Path("/etc/rc.d/inetd"),
                    Path("/usr/sbin/service"),
                    Path("/usr/sbin/inetd"),
                    Path("/usr/local/sbin/pkg"),
                    Path(PYTHON),
                ]
            for path in paths:
                engine.protected(path)
                for candidate in (path, *path.parents):
                    if candidate.exists():
                        backend.check_acl(candidate)

        guard_service_authority()
        progress("packages")
        installed = invoke(["/usr/local/sbin/pkg", "query", "%n"])
        require(installed.returncode == 0, "cannot inspect installed native packages")
        missing = sorted(set(packages(manifest)) - set(installed.stdout.splitlines()))
        if missing:
            result = invoke(["/usr/local/sbin/pkg", "install", "-y", *missing])
            require(
                result.returncode == 0,
                "backend package installation failed; package changes may remain",
            )
        if "nix-cache" in manifest["setup"]["backends"]:
            version = invoke(["/usr/local/sbin/pkg", "query", "%v", "nix"])
            require(
                version.returncode == 0,
                "cannot inspect the native Nix package version",
            )
            engine.supported_nix(version.stdout)
        completed.append("backend packages verified")
        # Native package scripts run as root: they may create accounts or alter
        # service files. Recheck their results before publishing any access.
        post_package_state = probe(manifest, invoke)
        require(
            manifest["mode"] == "public"
            or post_package_state["services"] == observed["services"],
            "provider services registration changed after package installation; inspect and create a fresh review",
        )
        if manifest["mode"] == "public":
            for key in (
                "inetdRc",
                "localInetdRc",
                "inetdConfig",
                "inetdProcesses",
                "providerRc",
                "providerRcLocal",
                "providerInetd",
            ):
                require(
                    post_package_state.get(key) == observed.get(key),
                    "inetd state changed after package installation; inspect and create a fresh review",
                )
        post_packages = review(manifest, post_package_state)
        require(
            not post_packages["blockers"],
            "post-package setup preflight contains blockers: "
            + "; ".join(post_packages["blockers"]),
        )
        guard_service_authority()
        if manifest["mode"] == "public":
            progress("inetd")
            retirement = retire_inetd(
                post_package_state, engine=engine, backend=backend, invoke=invoke
            )
            progress("complete")
            return {
                "schemaVersion": 1,
                "operation": "native-freebsd-setup",
                "completedPhases": completed,
                "accountReconstructionPerformed": False,
                "installedPackages": missing,
                "serviceConfigurationChanged": retirement["changed"],
                "inetd": retirement,
                "atomic": False,
                "tailscaleEnrollment": "not performed; private mode is incomplete",
                "storageMutationPerformed": False,
            }
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        raise SetupError(
            f"setup incomplete after {completed!r}: {error}; partial package/service changes may remain; inspect before retry"
        ) from error


def retire_inetd(state, *, engine, backend, invoke):
    status = inetd_status(state)
    require(
        status != "ambiguous",
        "managed inetd ownership is ambiguous; provider service was left untouched",
    )
    if not status.startswith("managed-"):
        return {"state": status, "changed": False, "filesRetained": True}
    if state["inetdRunning"]:
        engine.protected(INETD_PID)
        backend.check_acl(INETD_PID)
        require(
            INETD_PID.read_text().strip() == str(state["inetdProcesses"][0]["pid"]),
            "managed inetd PID does not match the verified process; service left untouched",
        )
        stopped = invoke(["/usr/sbin/service", "inetd", "onestop"])
        require(stopped.returncode == 0, "could not stop the recognized managed inetd")
    changed = engine.atomic_file(INETD_RC, INETD_DISABLED_RC_CONTENT)
    wait_for_inetd_retirement(state, invoke=invoke)
    return {
        "state": "managed-disabled",
        "changed": changed or state["inetdRunning"],
        "filesRetained": True,
    }


def wait_for_inetd_retirement(state, *, invoke, timeout=15.0, interval=0.1):
    """Wait for the verified daemon only; never signal a replacement process."""
    previous = state["inetdProcesses"][0] if state["inetdRunning"] else None
    deadline = time.monotonic() + timeout

    def bounded_probe(arguments):
        remaining = deadline - time.monotonic()
        require(
            remaining > 0,
            "managed inetd did not terminate within the bounded wait; no further signals were sent",
        )
        return invoke(arguments, timeout=min(5.0, remaining))

    while True:
        processes = bounded_probe(
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
        )
        require(processes.returncode == 0, "cannot inspect inetd termination")
        live = False
        for line in processes.stdout.splitlines():
            fields = line.split(None, 4)
            if not line.strip():
                continue
            require(
                len(fields) >= 4 and fields[0].isdigit() and fields[1].isdigit(),
                "native ps output is malformed; inetd termination inspection is incomplete",
            )
            uid, pid = int(fields[0]), int(fields[1])
            relevant = Path(fields[3].strip("()")).name == "inetd" or (
                previous is not None and pid == previous["pid"]
            )
            if not relevant:
                continue
            require(
                previous is not None
                and pid == previous["pid"]
                and uid == previous["uid"],
                "unexpected inetd process appeared; replacement service was left untouched",
            )
            if fields[2].startswith("Z"):
                continue  # An unreaped zombie cannot own a listening socket.
            arguments = fields[4] if len(fields) == 5 else ""
            require(
                arguments == previous["arguments"],
                "verified inetd PID changed identity; replacement process was left untouched",
            )
            live = True
        sockets = bounded_probe(
            ["/usr/bin/sockstat", "-46l", "-P", "tcp", "-p", "2222"]
        )
        require(
            sockets.returncode == 0, "cannot inspect the retired private SSH listener"
        )
        listeners = [
            line.split() for line in sockets.stdout.splitlines()[1:] if line.strip()
        ]
        for listener in listeners:
            require(
                previous is not None
                and len(listener) >= 7
                and listener[:2] == ["root", "inetd"]
                and listener[2] == str(previous["pid"])
                and listener[5] == "127.0.0.1:2222",
                "unexpected listener remains on the private SSH port; service was left untouched",
            )
        if not live and not listeners:
            return
        remaining = deadline - time.monotonic()
        require(
            remaining > 0,
            "managed inetd did not terminate within the bounded wait; no further signals were sent",
        )
        time.sleep(min(interval, remaining))
