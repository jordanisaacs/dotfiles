"""Exercise the production FreeBSD kernel/userspace through administrative SSH."""

import json
import shlex
import tempfile
from datetime import timedelta
from pathlib import Path
from time import monotonic, sleep

admin = globals()["admin"]
provider = globals()["provider"]


def remote(*arguments, user="root", key="/root/admin-key", source=None):
    return shlex.join(
        [
            "ssh",
            "-T",
            "-F",
            "/dev/null",
            "-i",
            key,
            *(["-b", source] if source is not None else []),
            "-o",
            "BatchMode=yes",
            "-o",
            "IdentityAgent=none",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "ConnectTimeout=3",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "UserKnownHostsFile=/root/known_hosts",
            user + "@192.168.10.1",
            shlex.join(arguments),
        ]
    )


def command(*arguments):
    return admin.succeed(shlex.join(["timeout", "180", *map(str, arguments)])).strip()


def put(path, content, mode=0o600):
    with tempfile.TemporaryDirectory(prefix="rsync-net-fixture-") as temporary:
        source = Path(temporary) / "content"
        source.write_text(content)
        source.chmod(mode)
        admin.copy_from_host(str(source), path)


def provider_python(code):
    return admin.succeed(remote("/usr/local/bin/python3.11", "-c", code)).strip()


def provider_put(path, content, mode=0o644):
    provider_python(
        "from pathlib import Path; "
        + f"p=Path({str(path)!r});p.parent.mkdir(parents=True,exist_ok=True);"
        + f"p.write_text({content!r});p.chmod({mode})"
    )


def provider_hashes(paths):
    return {path: admin.succeed(remote("sha256", "-q", path)).strip() for path in paths}


def observer(*arguments):
    # This fixture-only master observes native sshd logs without introducing an
    # authentication into the operation being measured. Missing masters fail.
    return shlex.join(
        [
            "ssh",
            "-T",
            "-F",
            "/dev/null",
            "-S",
            "/root/auth-observer",
            "-o",
            "ProxyCommand=/bin/false",
            "root@192.168.10.1",
            shlex.join(arguments),
        ]
    )


def start_observer():
    # Mirror native authentication messages to a fixture-only log without a
    # newsyslog rule, so a wall-clock rotation cannot reset measured counts.
    admin.succeed(remote("service", "syslogd", "reload"))
    arguments = shlex.split(remote("true"))[:-1]
    arguments[1:1] = ["-M", "-S", "/root/auth-observer", "-fN"]
    admin.succeed(shlex.join(arguments))


def controller_authentications():
    lines = admin.succeed(observer("cat", "/var/log/rsync-test-auth.log")).splitlines()
    return sum(
        "Accepted publickey for root " in line and controller_fingerprint in line
        for line in lines
    )


def setup(*extra, success=True, authentications=1, json_output=False):
    arguments = [
        "rsync-net",
        "--manifest",
        "/root/policy.json",
        "setup",
        "--admin-identity",
        "/root/controller-key",
        "--known-hosts",
        "/root/known_hosts",
        *extra,
    ]
    before = controller_authentications()
    python_absent = (
        admin.execute(observer("test", "-x", "/usr/local/bin/python3.11"))[0] != 0
    )
    completed = json.loads(
        command(
            "python3",
            "-c",
            "import json,subprocess,sys;"
            "r=subprocess.run(sys.argv[1:],capture_output=True,text=True,timeout=170);"
            "print(json.dumps({'status':r.returncode,'stdout':r.stdout,'stderr':r.stderr}))",
            *arguments,
        )
    )
    deadline = monotonic() + 5
    after = controller_authentications()
    while after < before + authentications and monotonic() < deadline:
        sleep(0.05)
        after = controller_authentications()
    if after - before != authentications:
        for log in ("/var/log/rsync-test-auth.log", "/var/log/auth.log"):
            print(
                "Native authentication diagnostic:",
                log,
                admin.succeed(observer("tail", "-n", "30", log)),
                flush=True,
            )
    assert after - before == authentications, (extra, before, after, completed)
    progress = [
        line.removeprefix("rsync-net: phase ")
        for line in completed["stderr"].splitlines()
        if line.startswith("rsync-net: phase ")
    ]
    assert set(progress) <= {
        "review",
        "prerequisites",
        "packages",
        "inetd",
        "complete",
    }, completed
    if authentications:
        assert progress, completed
        if "--apply" in extra and python_absent:
            assert "prerequisites" in progress, completed
    assert (completed["status"] == 0) == success, completed
    if success:
        assert progress[0] == "review" and progress[-1] == "complete", completed
        if "--apply" in extra:
            assert {"packages", "inetd"} <= set(progress), completed
    print("Setup authentications:", after - before, "phases:", progress, flush=True)
    if success or json_output:
        result = json.loads(completed["stdout"])
        if success and "--apply" in extra:
            assert result["accountReconstructionPerformed"] is False, result
            assert result["storageMutationPerformed"] is False, result
        return result
    return completed["stdout"] + completed["stderr"]


def bootstrap(*extra, success=True):
    arguments = [
        "rsync-net",
        "--manifest",
        "/root/policy.json",
        "bootstrap",
        "--admin-identity",
        "/root/admin-key",
        "--known-hosts",
        "/root/known_hosts",
        *extra,
    ]
    if success:
        return json.loads(command(*arguments))
    return admin.fail(shlex.join(arguments) + " 2>&1")


def authorization_hashes():
    return {
        name: admin.succeed(
            remote("sha256", "-q", "/home/" + name + "/.ssh/authorized_keys")
        ).strip()
        for name in ("backup-a", "backup-b", "git-host")
    }


def reviewed_setup():
    review = setup()
    assert not review["blockers"], review
    put("/root/setup-review.json", json.dumps(review))
    try:
        result = setup("--apply", "--review", "/root/setup-review.json")
        assert not result["accountReconstructionPerformed"]
        # Host initialization and per-backup authorization are separate CLI runs.
        account_review = bootstrap()
        assert not account_review["blockers"], account_review
        put("/root/bootstrap-review.json", json.dumps(account_review))
        result["accountReconstruction"] = bootstrap(
            "--apply", "--review", "/root/bootstrap-review.json"
        )
        return result
    except Exception:
        # Keep unexpected native lifecycle failures diagnosable before the
        # test driver tears the disposable provider down.
        for arguments in (
            (
                "ps",
                "-axww",
                "-o",
                "uid=",
                "-o",
                "pid=",
                "-o",
                "ppid=",
                "-o",
                "state=",
                "-o",
                "comm=",
                "-o",
                "args=",
            ),
            ("sockstat", "-46l", "-P", "tcp", "-p", "2222"),
            ("cat", "/var/run/inetd.pid"),
            ("cat", "/etc/rc.conf.d/inetd"),
        ):
            status, output = admin.execute(remote(*arguments))
            print("Native setup diagnostic:", arguments, status, output, flush=True)
        raise


def routine_ssh(principal):
    return shlex.join(
        [
            "ssh",
            "-T",
            "-F",
            "/dev/null",
            "-i",
            "/root/" + principal + "-key",
            "-p",
            "22",
            "-b",
            "192.168.10.3",
            "-o",
            "BatchMode=yes",
            "-o",
            "IdentityAgent=none",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "UserKnownHostsFile=/root/known_hosts",
            principal + "@192.168.10.1",
        ]
    )


def restic(principal, *arguments, success=True):
    args = [
        "restic",
        "--repo",
        "rclone:ignored",
        "--password-file",
        "/root/restic-password",
        "-o",
        "rclone.program=" + routine_ssh(principal),
        "-o",
        "rclone.args=ignored",
        *arguments,
    ]
    if success:
        return command(*args)
    return admin.fail(shlex.join(["timeout", "30", *args]) + " 2>&1")


admin.start()
provider.start(allow_reboot=True)
admin.wait_for_unit("multi-user.target")
admin.succeed("install -m 0600 /etc/freebsd-test-admin-key /root/admin-key")
admin.succeed("install -m 0600 /etc/freebsd-test-controller-key /root/controller-key")
controller_fingerprint = command(
    "ssh-keygen", "-lf", "/root/controller-key", "-E", "sha256"
).split()[1]
admin.succeed(
    "python3 -c "
    + shlex.quote(
        "from pathlib import Path; "
        "key=Path('/etc/freebsd-test-host-key').read_text(); "
        "Path('/root/known_hosts').write_text('192.168.10.1 ' + key)"
    )
)
admin.wait_until_succeeds(remote("true"), timeout=timedelta(minutes=4))
start_observer()
assert admin.succeed(remote("uname", "-s")).strip() == "FreeBSD"
assert admin.succeed(remote("freebsd-version", "-u")).strip() == "14.4-RELEASE"
retained_authority = {
    path: admin.succeed(remote("sha256", "-q", path)).strip()
    for path in (
        "/root/.ssh/authorized_keys",
        "/etc/ssh/ssh_host_ed25519_key.pub",
        "/etc/ssh/sshd_config",
        "/etc/services",
    )
}

admin.succeed(remote("test", "-x", "/usr/sbin/pkg"))
admin.succeed(remote("test", "-x", "/usr/sbin/pw"))
admin.fail(remote("test", "-x", "/usr/local/bin/python3.11"))
admin.succeed(remote("mkdir", "/packages"))
admin.succeed(remote("mount", "-t", "cd9660", "-o", "ro", "/dev/vtbd2", "/packages"))
admin.succeed(remote("zpool", "create", "data1", "/dev/vtbd1"))
admin.succeed(
    remote("zfs", "create", "-o", "mountpoint=/mnt/data1/control", "data1/control")
)
admin.succeed(remote("chmod", "0700", "/mnt/data1/control"))
admin.succeed(remote("zpool", "export", "data1"))
admin.succeed(remote("zpool", "import", "data1"))
assert any(
    line.split()[:3] == ["data1/control", "/mnt/data1/control", "zfs"]
    for line in admin.succeed(remote("mount", "-p")).splitlines()
)

policy = json.loads(command("cat", "/etc/rsync-base.json"))
policy["pool"]["guid"] = admin.succeed(
    remote("zpool", "get", "-Hp", "-o", "value", "guid", "data1")
).strip()
gpg_home = "/root/recovery-gpg"
command("mkdir", "-m", "0700", gpg_home)
gpg = ["gpg", "--no-options", "--homedir", gpg_home, "--batch", "--no-tty"]
command(
    *gpg,
    "--pinentry-mode",
    "loopback",
    "--passphrase",
    "",
    "--quick-generate-key",
    "Recovery fixture <recovery@example.invalid>",
    "ed25519",
    "cert,sign",
    "0",
)
fingerprint = next(
    line.split(":")[9]
    for line in command(*gpg, "--with-colons", "--list-keys").splitlines()
    if line.startswith("fpr:")
)
command(
    *gpg,
    "--pinentry-mode",
    "loopback",
    "--passphrase",
    "",
    "--quick-add-key",
    fingerprint,
    "cv25519",
    "encr",
    "0",
)
policy["recovery"] = {"enable": True, "recipients": [fingerprint]}
for principal in policy["principals"]:
    principal["recovery"] = {"enable": True, "recipients": [fingerprint]}
    if principal["backend"] == "git":
        principal["gcryptParticipants"] = [fingerprint]
for principal in policy["principals"]:
    name = principal["name"]
    admin.succeed(
        remote(
            "zfs",
            "create",
            "-o",
            "mountpoint=/mnt/data1/" + name,
            "-o",
            "quota=268435456",
            "data1/" + name,
        )
    )
    admin.succeed(
        remote(
            "chown",
            str(principal["uid"]) + ":" + str(principal["gid"]),
            "/mnt/data1/" + name,
        )
    )
    admin.succeed(remote("chmod", "0700", "/mnt/data1/" + name))
admin.succeed(remote("chmod", "0711", "/mnt/data1"))
put("/root/policy.json", json.dumps(policy))
for name in ("backup-a", "backup-b", "git-host"):
    command(
        "rsync-net",
        "--manifest",
        "/root/policy.json",
        "enroll",
        "--principal",
        name,
        "--device",
        name,
        "--key-file",
        "/root/" + name + "-key",
        "--output",
        "/root/enroll-" + name,
        *(["--gpg-fingerprint", fingerprint] if name == "git-host" else []),
    )
    put("/root/policy.json", command("cat", "/root/enroll-" + name + "/manifest.json"))

# Incomplete private mode can be inspected, but cannot install even Python or
# publish authorization. Public mode stays the unchanged provider default.
public_policy = json.loads(command("cat", "/root/policy.json"))
private_policy = json.loads(json.dumps(public_policy))
private_policy["mode"] = "private"
put("/root/policy.json", json.dumps(private_policy))
private_review = setup(success=False, json_output=True)
assert any(
    "private mode is incomplete" in blocker for blocker in private_review["blockers"]
)
put("/root/setup-review.json", json.dumps(private_review))
denial = setup(
    "--apply", "--review", "/root/setup-review.json", success=False, authentications=0
)
assert "private mode is incomplete" in denial, denial
admin.fail(remote("test", "-x", "/usr/local/bin/python3.11"))
assert provider_hashes(retained_authority) == retained_authority
put("/root/policy.json", json.dumps(public_policy))

# Host initialization installs packages without publishing backup authorization.
first_review = setup()
assert first_review["prePythonActions"] == [
    ["/usr/sbin/pkg", "install", "-y", "python311"]
]
put("/root/setup-review.json", json.dumps(first_review))
admin.succeed(
    remote("setfacl", "-m", "user:62002:read_data::deny", "/mnt/data1/backup-a")
)
initial_host = setup("--apply", "--review", "/root/setup-review.json")
assert not initial_host["accountReconstructionPerformed"]
for principal in policy["principals"]:
    admin.fail(remote("id", principal["name"]))
    admin.fail(remote("test", "-e", principal["home"] + "/.ssh/authorized_keys"))
put("/root/bootstrap-review.json", json.dumps(bootstrap()))
denial = bootstrap("--apply", "--review", "/root/bootstrap-review.json", success=False)
assert "nontrivial filesystem ACL" in denial, denial
admin.fail(remote("test", "-e", "/home/backup-a/.ssh/authorized_keys"))
admin.fail(remote("id", "backup-a"))
admin.succeed(remote("test", "-x", "/usr/local/bin/python3.11"))
admin.succeed(remote("setfacl", "-b", "/mnt/data1/backup-a"))
# A provider configuration that accepts a runtime-control environment variable
# must be refused before any principal exists. A later harmless AcceptEnv row
# cannot conceal the first one from native sshd -T validation.
provider_sshd = admin.succeed(remote("cat", "/etc/ssh/sshd_config"))
provider_put(
    "/etc/ssh/sshd_config", provider_sshd + "AcceptEnv LD_PRELOAD\nAcceptEnv LANG\n"
)
unsafe_provider = provider_hashes(["/etc/ssh/sshd_config"])
put("/root/bootstrap-review.json", json.dumps(bootstrap()))
denial = bootstrap("--apply", "--review", "/root/bootstrap-review.json", success=False)
assert "environment" in denial.lower(), denial
admin.fail(remote("id", "backup-a"))
admin.fail(remote("test", "-e", "/home/backup-a/.ssh/authorized_keys"))
assert provider_hashes(unsafe_provider) == unsafe_provider
provider_put("/etc/ssh/sshd_config", provider_sshd)
result = reviewed_setup()
assert result["storageMutationPerformed"] is False
assert result["accountReconstruction"]["adapter"] == "FreeBSD"
assert result["tailscaleEnrollment"].startswith("not performed")
native_phases = {
    line.split(": phase ", 1)[1]
    for line in admin.succeed(observer("cat", "/var/log/messages")).splitlines()
    if "rsync-net[" in line and ": phase " in line
}
assert {"review", "packages", "inetd", "complete"} <= native_phases, native_phases
assert setup()["prePythonActions"] == []
again = reviewed_setup()
assert again["installedPackages"] == []
assert again["accountReconstruction"]["changes"] == []
assert again["serviceConfigurationChanged"] is False
admin.fail(remote("pgrep", "-x", "inetd"))
admin.fail(remote("test", "-e", "/root/backup-a-key"))
admin.fail(remote("pkg", "info", "-e", "tailscale"))
admin.fail(remote("test", "-e", "/usr/local/etc/rsync-net/sshd-private.conf"))
assert provider_hashes(retained_authority) == retained_authority

# Private bootstrap is equally unavailable after public accounts exist, without
# removing their working authorization or changing any provider configuration.
public_policy = json.loads(command("cat", "/root/policy.json"))
private_policy = json.loads(json.dumps(public_policy))
private_policy["mode"] = "private"
keys_before = authorization_hashes()
put("/root/policy.json", json.dumps(private_policy))
private_review = json.loads(bootstrap(success=False))
assert private_review["applySupported"] is False
put("/root/bootstrap-review.json", json.dumps(private_review))
denial = bootstrap("--apply", "--review", "/root/bootstrap-review.json", success=False)
assert "private mode is incomplete" in denial, denial
assert authorization_hashes() == keys_before
assert provider_hashes(retained_authority) == retained_authority
put("/root/policy.json", json.dumps(public_policy))

# A provider's unrelated inetd keeps running: public mode neither claims nor
# disables it. These service files are created only in this disposable fixture.
admin.fail(remote("test", "-e", "/etc/rc.conf.d/inetd"))
original_inetd = admin.succeed(remote("cat", "/etc/inetd.conf"))
provider_put("/etc/inetd.conf", "echo stream tcp nowait root internal\n")
provider_put(
    "/etc/rc.conf.d/inetd", 'inetd_enable="YES"\ninetd_flags="-wW -a 127.0.0.1"\n'
)
admin.succeed(remote("service", "inetd", "start"))
provider_pid = admin.succeed(remote("cat", "/var/run/inetd.pid")).strip()
provider_files = provider_hashes(
    ["/etc/inetd.conf", "/etc/rc.conf.d/inetd", "/etc/services"]
)
untouched = reviewed_setup()
assert untouched["inetd"] == {
    "state": "provider",
    "changed": False,
    "filesRetained": True,
}
assert admin.succeed(remote("cat", "/var/run/inetd.pid")).strip() == provider_pid
admin.succeed(remote("kill", "-0", provider_pid))
assert provider_hashes(provider_files) == provider_files
admin.succeed(remote("service", "inetd", "stop"))
provider_put("/etc/inetd.conf", original_inetd)
provider_python("from pathlib import Path;Path('/etc/rc.conf.d/inetd').unlink()")

# Seed the exact retained legacy configuration from the production package's
# constants. The server has only Python, never the controller package installed.
legacy = json.loads(
    command(
        "python3",
        "-c",
        "import sys,json;from pathlib import Path;"
        "sys.path.insert(0,Path('/etc/rsync-test-module-path').read_text());"
        "from rsync_net import setup as old,cli as policy;"
        "manifest=json.loads(Path('/root/policy.json').read_text());"
        "print(json.dumps({'inetdConfig':str(old.INETD_CONFIG),'inetdContent':old.INETD_CONTENT,"
        "'rc':str(old.INETD_RC),'activeRc':old.INETD_RC_CONTENT,'disabledRc':old.INETD_DISABLED_RC_CONTENT,"
        "'serviceEntry':old.SERVICE_ENTRY,'sshdConfig':str(policy.PRIVATE_SSHD_CONFIG),"
        "'sshdContent':policy.private_sshd_config(manifest)}))",
    )
)
provider_put(legacy["inetdConfig"], legacy["inetdContent"])
provider_put(legacy["rc"], legacy["activeRc"])
provider_put(legacy["sshdConfig"], legacy["sshdContent"], 0o600)
central_key = "/usr/local/etc/rsync-net/authorized_keys/backup-a"
provider_put(central_key, "# retained legacy public authorization fixture\n")
provider_python(
    "from pathlib import Path;p=Path('/etc/services');p.write_text(p.read_text()+"
    + repr(legacy["serviceEntry"])
    + ")"
)
admin.succeed(remote("services_mkdb", "/etc/services"))
admin.succeed(remote("service", "inetd", "start"))
legacy_files = provider_hashes(
    [legacy["inetdConfig"], legacy["sshdConfig"], central_key, "/etc/services"]
)
assert setup()["inetd"]["state"] == "managed-active"
retired = reviewed_setup()
assert retired["inetd"] == {
    "state": "managed-disabled",
    "changed": True,
    "filesRetained": True,
}
# A stopped process may briefly remain a zombie awaiting init. It must no
# longer own a listening socket; the controller verifies that native boundary.
listeners = admin.succeed(remote("sockstat", "-46l", "-P", "tcp", "-p", "2222"))
assert not listeners.splitlines()[1:], listeners
assert (
    provider_python(
        "from pathlib import Path;print(Path("
        + repr(legacy["rc"])
        + ").read_text(),end='')"
    )
    == legacy["disabledRc"].strip()
)
assert provider_hashes(legacy_files) == legacy_files
assert authorization_hashes() == keys_before
assert reviewed_setup()["inetd"] == {
    "state": "managed-disabled",
    "changed": False,
    "filesRetained": True,
}
# Retrying a prior partial failure must also stop the exact managed process
# when its RC override was already disabled. Only this disposable fixture uses
# native onestart to recreate that retained-but-running state.
admin.succeed(remote("service", "inetd", "onestart"))
assert setup()["inetd"]["state"] == "managed-active"
retried = reviewed_setup()
assert retried["inetd"] == {
    "state": "managed-disabled",
    "changed": True,
    "filesRetained": True,
}
assert provider_hashes(legacy_files) == legacy_files
listeners = admin.succeed(remote("sockstat", "-46l", "-P", "tcp", "-p", "2222"))
assert not listeners.splitlines()[1:], listeners

# Root-owned public key directories cannot be replaced by routine identities.
admin.fail(
    remote("su", "-m", "backup-a", "-c", "/usr/bin/touch /home/backup-a/.ssh/injected")
)
forward = routine_ssh("backup-a").rsplit(" ", 1)
denial = admin.fail(
    "timeout 10 " + forward[0] + " -W 127.0.0.1:22 " + forward[1] + " 2>&1"
)
assert "administratively prohibited" in denial or "stdio forwarding failed" in denial, (
    denial
)

# A real process under a managed UID must be observed and prevent changing its
# authorization. The historical Linux-style ps format silently missed this on
# FreeBSD; this exercises the production inspector and mutation guard together.
original_policy = json.loads(command("cat", "/root/policy.json"))
keys_before = authorization_hashes()
command(
    "rsync-net",
    "--manifest",
    "/root/policy.json",
    "enroll",
    "--principal",
    "backup-a",
    "--device",
    "busy-device",
    "--key-file",
    "/root/busy-device-key",
    "--output",
    "/root/busy-enrollment",
)
put("/root/policy.json", command("cat", "/root/busy-enrollment/manifest.json"))
admin.succeed(
    remote(
        "install",
        "-d",
        "-o",
        "backup-a",
        "-g",
        "backup-a",
        "-m",
        "0700",
        "/tmp/native-busy",
    )
)
busy = "import time;from pathlib import Path;Path('/tmp/native-busy/ready').write_text('ready');time.sleep(60)"
admin.succeed(
    remote(
        "daemon",
        "-f",
        "-u",
        "backup-a",
        "-p",
        "/root/native-busy.pid",
        "-o",
        "/root/native-busy.log",
        "/usr/local/bin/python3.11",
        "-I",
        "-S",
        "-c",
        busy,
    )
)
admin.wait_until_succeeds(
    remote("test", "-f", "/tmp/native-busy/ready"), timeout=timedelta(seconds=10)
)
busy_pid = admin.succeed(remote("cat", "/root/native-busy.pid")).strip()
observed = json.loads(
    command(
        "rsync-net",
        "--manifest",
        "/root/policy.json",
        "inspect",
        "--admin-identity",
        "/root/admin-key",
        "--known-hosts",
        "/root/known_hosts",
    )
)
assert any(
    process["uid"] == 62001 and process["pid"] == int(busy_pid)
    for process in observed["activeProcesses"]
), observed["activeProcesses"]
review = bootstrap()
assert review["actions"], review
put("/root/bootstrap-review.json", json.dumps(review))
denial = bootstrap("--apply", "--review", "/root/bootstrap-review.json", success=False)
assert "active" in denial.lower(), denial
assert authorization_hashes() == keys_before
admin.succeed(remote("kill", busy_pid))
admin.wait_until_fails(remote("kill", "-0", busy_pid), timeout=timedelta(seconds=10))
# This negative enrollment was never published; restoring the original local
# candidate does not revoke any server authorization.
put("/root/policy.json", json.dumps(original_policy))

# A fresh native supplementary-group change invalidates a saved review before
# any key/config publication. The test never asks reconstruction to repair it.
keys_before = authorization_hashes()
put("/root/bootstrap-review.json", json.dumps(bootstrap()))
admin.succeed(remote("pw", "groupadd", "review-change", "-g", "62000"))
admin.succeed(remote("pw", "groupmod", "review-change", "-m", "backup-a"))
denial = bootstrap("--apply", "--review", "/root/bootstrap-review.json", success=False)
assert "review is stale" in denial, denial
assert authorization_hashes() == keys_before
admin.succeed(remote("pw", "groupmod", "review-change", "-d", "backup-a"))
admin.succeed(remote("pw", "groupdel", "review-change"))
assert not bootstrap()["blockers"]

# Exercise the actual FreeBSD kernel flock, held by a short disposable Python
# process supervised by the base daemon utility, rather than a mocked lock.
put("/root/bootstrap-review.json", json.dumps(bootstrap()))
holder = (
    "import fcntl,time;from pathlib import Path;"
    "f=open('/var/run/rsync-net-bootstrap.lock','r+');"
    "fcntl.flock(f,fcntl.LOCK_EX);"
    "Path('/root/native-lock-ready').write_text('ready');time.sleep(60)"
)
admin.succeed(
    remote(
        "daemon",
        "-f",
        "-p",
        "/root/native-lock.pid",
        "-o",
        "/root/native-lock.log",
        "/usr/local/bin/python3.11",
        "-c",
        holder,
    )
)
admin.wait_until_succeeds(
    remote("test", "-f", "/root/native-lock-ready"), timeout=timedelta(seconds=10)
)
denial = bootstrap("--apply", "--review", "/root/bootstrap-review.json", success=False)
assert "another bootstrap is running" in denial, denial
assert authorization_hashes() == keys_before
holder_pid = admin.succeed(remote("cat", "/root/native-lock.pid")).strip()
admin.succeed(remote("kill", holder_pid))
assert not bootstrap()["blockers"]

# A provider-allocated identity cannot take over a new declared principal's
# numeric UID. Enrollment remains local; no account/key is published remotely.
original_policy = json.loads(command("cat", "/root/policy.json"))
collision_policy = json.loads(json.dumps(original_policy))
principal = dict(collision_policy["principals"][0])
principal.update(
    {
        "name": "collision-target",
        "uid": 61005,
        "gid": 61005,
        "home": "/home/collision-target",
        "dataset": "data1/collision-target",
        "publicKeys": [],
        "readOnlyKeys": [],
    }
)
collision_policy["principals"].append(principal)
dataset = dict(collision_policy["datasets"][0])
dataset.update(
    {
        "name": "data1/collision-target",
        "mountpoint": "/mnt/data1/collision-target",
        "principal": "collision-target",
    }
)
collision_policy["datasets"].append(dataset)
admin.succeed(
    remote(
        "zfs",
        "create",
        "-o",
        "mountpoint=" + dataset["mountpoint"],
        "-o",
        "quota=" + str(dataset["quotaBytes"]),
        dataset["name"],
    )
)
admin.succeed(remote("chown", "61005:61005", dataset["mountpoint"]))
admin.succeed(remote("chmod", "0700", dataset["mountpoint"]))
put("/root/policy.json", json.dumps(collision_policy))
command(
    "rsync-net",
    "--manifest",
    "/root/policy.json",
    "enroll",
    "--principal",
    "collision-target",
    "--device",
    "collision-device",
    "--key-file",
    "/root/collision-key",
    "--output",
    "/root/collision-enrollment",
)
put("/root/policy.json", command("cat", "/root/collision-enrollment/manifest.json"))
admin.succeed(remote("pw", "groupadd", "collision-group", "-g", "62999"))
admin.succeed(
    remote(
        "pw",
        "useradd",
        "collision-owner",
        "-u",
        "61005",
        "-g",
        "62999",
        "-d",
        "/nonexistent",
        "-s",
        "/bin/sh",
        "-w",
        "no",
    )
)
collision_review = json.loads(bootstrap(success=False))
assert any(
    "reserved UID belongs" in blocker for blocker in collision_review["blockers"]
), collision_review
put("/root/bootstrap-review.json", json.dumps(collision_review))
bootstrap("--apply", "--review", "/root/bootstrap-review.json", success=False)
admin.fail(remote("id", "collision-target"))
admin.fail(remote("test", "-e", "/home/collision-target/.ssh/authorized_keys"))
assert admin.succeed(remote("id", "-u", "collision-owner")).strip() == "61005"
assert authorization_hashes() == keys_before
put("/root/policy.json", json.dumps(original_policy))
admin.succeed(remote("pw", "userdel", "collision-owner"))
admin.succeed(remote("pw", "groupdel", "collision-group"))

# A valid routine identity cannot authenticate as a different principal. Keep
# this deliberate authentication failure away from administration/routine jobs
# in OpenSSH's per-source penalty accounting.
wrong_identity = (
    routine_ssh("backup-b")
    .replace("/root/backup-b-key", "/root/backup-a-key")
    .replace("192.168.10.3", "192.168.10.4")
)
admin.fail("timeout 10 " + wrong_identity + " true")
put("/root/restic-password", "disposable-restic-password\n")
put("/root/data/document.txt", "recover from native FreeBSD\n")
restic("backup-a", "init")
restic("backup-a", "backup", "/root/data")
snapshots = json.loads(restic("backup-a", "snapshots", "--json"))
assert len(snapshots) == 1
snapshot_id = snapshots[0]["id"]
denial = restic("backup-a", "forget", snapshot_id, success=False)
assert "403" in denial or "Forbidden" in denial, denial
assert json.loads(restic("backup-a", "snapshots", "--json"))[0]["id"] == snapshot_id
restic("backup-a", "restore", "latest", "--target", "/root/restored")
assert (
    command("cat", "/root/restored/root/data/document.txt")
    == "recover from native FreeBSD"
)
restic("backup-b", "snapshots", success=False)
admin.fail(remote("su", "-m", "backup-b", "-c", "/bin/cat /mnt/data1/backup-a/config"))

# Run the packaged upstream helper with our declared isolated interpreter, even
# though its port-provided shebang points at a different Python version.
admin.fail(remote("test", "-x", "/usr/local/bin/python3.12"))
rsync_environment = "RSYNC_RSH=" + routine_ssh("git-host").rsplit(" ", 1)[0]
git_url = "gcrypt::rsync://git-host@192.168.10.1/repository"
git_environment = ["env", "GNUPGHOME=" + gpg_home, rsync_environment]
command("git", "init", "--initial-branch=main", "/root/git-source")
command("git", "-C", "/root/git-source", "remote", "add", "archive", git_url)
for key, value in {
    "user.name": "Regression fixture",
    "user.email": "regression@example.invalid",
    "commit.gpgsign": "false",
    "remote.archive.gcrypt-participants": fingerprint,
    "remote.archive.gcrypt-signingkey": fingerprint,
}.items():
    command("git", "-C", "/root/git-source", "config", key, value)
put("/root/git-source/secret.txt", "recover encrypted Git payload\n")
command("git", "-C", "/root/git-source", "add", "secret.txt")
command("git", "-C", "/root/git-source", "commit", "-m", "Initial encrypted archive")
command(*git_environment, "git", "-C", "/root/git-source", "push", "archive", "main")
put("/root/git-source/incremental.txt", "retain incremental encrypted Git history\n")
command("git", "-C", "/root/git-source", "add", "incremental.txt")
command(
    "git", "-C", "/root/git-source", "commit", "-m", "Incremental encrypted archive"
)
command(*git_environment, "git", "-C", "/root/git-source", "push", "archive", "main")
command(
    *git_environment,
    "git",
    "-c",
    "gcrypt.participants=" + fingerprint,
    "clone",
    "--branch=main",
    git_url,
    "/root/git-clone",
)
assert command("cat", "/root/git-clone/secret.txt") == "recover encrypted Git payload"
admin.fail(
    remote("su", "-m", "backup-a", "-c", "/bin/ls /mnt/data1/git-host/repository")
)


def control(action, *arguments):
    return json.loads(
        command(
            "rsync-net",
            "--manifest",
            "/root/policy.json",
            "control",
            action,
            "--admin-identity",
            "/root/admin-key",
            "--known-hosts",
            "/root/known_hosts",
            *arguments,
        )
    )


prepared = json.loads(
    command(
        "rsync-net",
        "--manifest",
        "/root/policy.json",
        "recovery",
        "prepare",
        "--principal",
        "backup-a",
        "--repository",
        "rclone:ignored",
        "--restic-option",
        "rclone.program=" + routine_ssh("backup-a"),
        "--restic-option",
        "rclone.args=ignored",
        "--password-file",
        "/root/restic-password",
        "--gnupghome",
        gpg_home,
        "--output",
        "/root/prepared-recovery",
    )
)
assert prepared["state"] == "complete"
publication = ("--principal", "backup-a", "--bundle", "/root/prepared-recovery")
review = control("backup", *publication)
put("/root/control-review.json", json.dumps(review))
published = control(
    "backup", *publication, "--apply", "--review", "/root/control-review.json"
)
assert published["changes"]
assert published["snapshot"]["created"] and published["snapshot"]["verified"]
snapshot_name = published["snapshot"]["name"]
assert snapshot_name.startswith("data1/control@rsync-net-control-")
assert (
    admin.succeed(
        remote("zfs", "list", "-H", "-o", "name", "-t", "snapshot", snapshot_name)
    ).strip()
    == snapshot_name
)
frozen_root = "/mnt/data1/control/.zfs/snapshot/" + snapshot_name.split("@", 1)[1]
assert admin.succeed(remote("cat", frozen_root + "/catalog.json")) == admin.succeed(
    remote("cat", "/mnt/data1/control/catalog.json")
)
catalog = control("fetch", "--catalog")["catalog"]
admin.fail(
    remote("su", "-m", "backup-a", "-c", "/bin/cat /mnt/data1/control/catalog.json")
)
admin.succeed(remote("zfs", "snapshot", "data1/backup-a@retained"))
admin.fail(
    remote("su", "-m", "backup-a", "-c", "/sbin/zfs destroy data1/backup-a@retained")
)

# Replace the OS disk, rather than selectively deleting simulated config. The
# provider's preserved pool remains a separate disk; public administrative keys
# and host keys are the same fixture identities on both fresh release images.
admin.succeed(remote("zpool", "export", "data1"))
command(
    "ssh",
    "-F",
    "/dev/null",
    "-S",
    "/root/auth-observer",
    "-O",
    "exit",
    "root@192.168.10.1",
)
admin.execute(remote("shutdown", "-p", "now"))
provider.wait_for_shutdown(timeout=timedelta(seconds=60))
os_disk = provider.state_dir / "freebsd-system.qcow2"
assert os_disk.parent == provider.state_dir and os_disk.is_file()
os_disk.unlink()
provider.start(allow_reboot=True)
admin.wait_until_succeeds(remote("true"), timeout=timedelta(minutes=4))
start_observer()
admin.fail(remote("id", "backup-a"))
admin.fail(remote("test", "-e", "/usr/local/etc/rsync-net/sshd-private.conf"))
admin.fail(remote("test", "-x", "/usr/local/bin/python3.11"))
admin.succeed(remote("mkdir", "/packages"))
admin.succeed(remote("mount", "-t", "cd9660", "-o", "ro", "/dev/vtbd2", "/packages"))
admin.succeed(remote("zpool", "import", "-d", "/dev", policy["pool"]["guid"]))
assert (
    admin.succeed(remote("zpool", "get", "-Hp", "-o", "value", "guid", "data1")).strip()
    == policy["pool"]["guid"]
)
restored_setup = reviewed_setup()
assert "created user backup-a" in restored_setup["accountReconstruction"]["changes"]
assert control("fetch", "--catalog")["catalog"] == catalog
# The encrypted Git host also survives a completely fresh provider OS.

admin.succeed(remote("zfs", "list", "data1/backup-a@retained"))
command(
    *git_environment,
    "git",
    "-c",
    "gcrypt.participants=" + fingerprint,
    "clone",
    "--branch=main",
    git_url,
    "/root/git-after-reset",
)
assert (
    command("cat", "/root/git-after-reset/secret.txt")
    == "recover encrypted Git payload"
)
assert (
    command("git", "-C", "/root/git-after-reset", "rev-list", "--count", "HEAD") == "2"
)
assert (
    command("cat", "/root/git-after-reset/incremental.txt")
    == "retain incremental encrypted Git history"
)


# Recover with a fresh device key and the separately encrypted/signed recovery
# envelope after discarding the original source's SSH key/password/local bundle.
command(
    "rsync-net",
    "--manifest",
    "/root/policy.json",
    "enroll",
    "--principal",
    "backup-a",
    "--device",
    "replacement",
    "--key-file",
    "/root/replacement-key",
    "--output",
    "/root/enroll-replacement",
)
put("/root/policy.json", command("cat", "/root/enroll-replacement/manifest.json"))
reviewed_setup()
command(
    "rm",
    "-rf",
    "/root/prepared-recovery",
    "/root/restic-password",
    "/root/backup-a-key",
)
control("fetch", "--principal", "backup-a", "--output", "/root/recovered-bundle")
recovery_ssh = routine_ssh("backup-a").replace(
    "/root/backup-a-key", "/root/replacement-key"
)
restoration = json.loads(
    command(
        "rsync-net",
        "--manifest",
        "/root/policy.json",
        "recovery",
        "restore",
        "--principal",
        "backup-a",
        "--bundle",
        "/root/recovered-bundle",
        "--repository",
        "rclone:ignored",
        "--restic-option",
        "rclone.program=" + recovery_ssh,
        "--restic-option",
        "rclone.args=ignored",
        "--gnupghome",
        gpg_home,
        "--target",
        "/root/recovered-after-reset",
    )
)
assert restoration["restoreVerified"]
assert (
    command("cat", "/root/recovered-after-reset/root/data/document.txt")
    == "recover from native FreeBSD"
)
assert reviewed_setup()["accountReconstruction"]["changes"] == []

# The provider repository's Nix branch is unsupported. Test this actual package
# fact as a deployment refusal, rather than substituting Linux's newer binary
# and declaring the native provider cache ready.
cache_policy = json.loads(command("cat", "/root/policy.json"))
cache_principal = dict(cache_policy["principals"][0])
cache_principal.update(
    {
        "name": "nix-cache",
        "uid": 61004,
        "gid": 61004,
        "home": "/home/nix-cache",
        "backend": "nix-cache",
        "dataset": "data1/nix-cache",
        "publicKeys": [],
        "gcryptParticipants": [],
        "recovery": {"enable": False, "recipients": []},
        "cache": {
            "signingPublicKeys": [
                "disposable-cache:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            ]
        },
    }
)
cache_policy["principals"].append(cache_principal)
cache_policy["datasets"].append(
    {
        "name": "data1/nix-cache",
        "mountpoint": "/mnt/data1/nix-cache",
        "principal": "nix-cache",
        "purpose": "cache",
        "quotaBytes": 268435456,
    }
)
admin.succeed(
    remote(
        "zfs",
        "create",
        "-o",
        "mountpoint=/mnt/data1/nix-cache",
        "-o",
        "quota=268435456",
        "data1/nix-cache",
    )
)
admin.succeed(remote("chown", "61004:61004", "/mnt/data1/nix-cache"))
admin.succeed(remote("chmod", "0700", "/mnt/data1/nix-cache"))
cache_policy["setup"]["backends"].append("nix-cache")
put("/root/policy.json", json.dumps(cache_policy))
command(
    "rsync-net",
    "--manifest",
    "/root/policy.json",
    "enroll",
    "--principal",
    "nix-cache",
    "--device",
    "unsupported-builder",
    "--key-file",
    "/root/cache-key",
    "--output",
    "/root/cache-enrollment",
)
put("/root/policy.json", command("cat", "/root/cache-enrollment/manifest.json"))
review = setup()
put("/root/setup-review.json", json.dumps(review))
denial = setup("--apply", "--review", "/root/setup-review.json", success=False)
assert "Nix" in denial and "unsupported" in denial, denial
admin.fail(remote("id", "nix-cache"))
admin.fail(remote("test", "-e", "/home/nix-cache/.ssh/authorized_keys"))
admin.fail(remote("pgrep", "-x", "nix-daemon"))

for path, digest in retained_authority.items():
    assert admin.succeed(remote("sha256", "-q", path)).strip() == digest
