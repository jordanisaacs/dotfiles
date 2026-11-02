"""Restricted account/config reconstruction; never replay arbitrary plan commands.

This restores declared identities and root-managed home forced-command keys.
It leaves provider SSH configuration, retained private-mode assets and storage
unchanged. Private mode remains incomplete and cannot be activated.
"""

import ctypes
import errno
import fcntl
import glob
import grp
import os
import platform
import pwd
import re
import shlex
import stat
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path


class ApplyError(ValueError):
    """A fail-closed privileged reconstruction guard."""


def require(condition, message):
    if not condition:
        raise ApplyError(message)


def supported_nix(version):
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:[_+,-].*)?", version.strip())
    # Conservative floor for the October 2026 upstream security fixes.
    # The FreeBSD repository's 2.32 branch is unsupported upstream.
    require(
        match is not None and tuple(map(int, match.groups())) >= (2, 35, 3),
        "Nix cache requires Nix >= 2.35.3; native repository package is "
        "unsupported or unrecognized; no cache authorization was published",
    )


def native(arguments):
    process = subprocess.run(
        arguments, input="", capture_output=True, text=True, timeout=30, check=False
    )
    require(
        process.returncode == 0,
        f"native operation failed: {arguments[0]} (exit {process.returncode})",
    )
    return process.stdout


def protected(path, *, directory=False):
    """Validate the complete authority path, not just its final mode."""
    path = Path(path)
    for candidate in (*reversed(path.parents), path):
        if not candidate.exists():
            require(
                not candidate.is_symlink(), f"dangling authority symlink: {candidate}"
            )
            continue
        info = candidate.lstat()
        require(
            not stat.S_ISLNK(info.st_mode), f"authority path is a symlink: {candidate}"
        )
        store_parent = str(candidate) == "/nix/store" and bool(
            info.st_mode & stat.S_ISVTX
        )
        require(
            info.st_uid == 0
            and (stat.S_IMODE(info.st_mode) & 0o022 == 0 or store_parent),
            f"authority path is not root-controlled: {candidate}",
        )
    if path.exists():
        require(
            path.is_dir() if directory else path.is_file(),
            f"wrong authority file type: {path}",
        )


def directory(path):
    path = Path(path)
    protected(path, directory=True)
    if not path.exists():
        directory(path.parent)
        path.mkdir(mode=0o755)


def atomic_file(path, content, *, mode=0o644):
    path = Path(path)
    protected(path)
    directory(path.parent)
    if (
        path.exists()
        and path.read_text() == content
        and stat.S_IMODE(path.stat().st_mode) == mode
    ):
        return False
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, prefix=".rsync-net-", delete=False
    ) as stream:
        staging = Path(stream.name)
        try:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
            os.fchmod(stream.fileno(), mode)
            os.replace(staging, path)
        finally:
            staging.unlink(missing_ok=True)
    return True


class FreeBSD:
    label = "FreeBSD"
    sshd = "/usr/sbin/sshd"

    def check(self):
        require(
            platform.system() == "FreeBSD", "production reconstruction requires FreeBSD"
        )
        require(
            os.geteuid() == 0,
            "reconstruction requires the administrative root identity",
        )
        for path in ("/usr/sbin/pw", self.sshd):
            protected(path)

    def check_backend(self, principal):
        if principal["backend"] != "nix-cache":
            return
        package_manager = Path("/usr/local/sbin/pkg")
        protected(package_manager)
        supported_nix(native([str(package_manager), "query", "%v", "nix"]))

    def check_acl(self, path):
        """Accept only mode-equivalent ACLs, including NFSv4 on FreeBSD ZFS.

        Native acl_get_fd selects NFSv4 versus POSIX access ACLs. POSIX default
        ACLs must be empty so newly created control files cannot inherit grants.
        FreeBSD sys/acl.h defines ACL_TYPE_DEFAULT as 3. Unsupported ACLs mean
        the filesystem implements mode permissions alone; other errors stop.
        """
        # https://github.com/freebsd/freebsd-src/blob/releng/14.1/lib/libc/posix1e/acl_get.c#L99-L104
        libc = ctypes.CDLL(None, use_errno=True)
        libc.acl_get_fd.argtypes = [ctypes.c_int]
        libc.acl_get_fd.restype = ctypes.c_void_p
        libc.acl_get_fd_np.argtypes = [ctypes.c_int, ctypes.c_int]
        libc.acl_get_fd_np.restype = ctypes.c_void_p
        libc.acl_is_trivial_np.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_int),
        ]
        libc.acl_get_entry.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_void_p),
        ]
        libc.acl_free.argtypes = [ctypes.c_void_p]
        unsupported = {errno.EOPNOTSUPP}
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            for default in (False, True):
                acl = libc.acl_get_fd_np(fd, 3) if default else libc.acl_get_fd(fd)
                if not acl:
                    require(
                        ctypes.get_errno()
                        in (unsupported | {errno.EINVAL} if default else unsupported),
                        f"cannot inspect filesystem ACL: {path}",
                    )
                    continue
                try:
                    if default:
                        entry = ctypes.c_void_p()
                        require(
                            libc.acl_get_entry(acl, 0, ctypes.byref(entry)) == 0,
                            f"inherited/default filesystem ACL is unsupported: {path}",
                        )
                    else:
                        trivial = ctypes.c_int()
                        require(
                            libc.acl_is_trivial_np(acl, ctypes.byref(trivial)) == 0
                            and trivial.value == 1,
                            f"nontrivial filesystem ACL is unsupported: {path}",
                        )
                finally:
                    libc.acl_free(acl)
        finally:
            os.close(fd)

    def create_group(self, principal):
        native(
            ["/usr/sbin/pw", "groupadd", principal["name"], "-g", str(principal["gid"])]
        )

    def create_user(self, principal):
        native(
            [
                "/usr/sbin/pw",
                "useradd",
                principal["name"],
                "-u",
                str(principal["uid"]),
                "-g",
                str(principal["gid"]),
                "-d",
                principal["home"],
                "-s",
                "/bin/sh",
                "-w",
                "no",
            ]
        )


@contextmanager
def reconstruction_lock():
    parent = Path("/var/run").resolve(strict=True)
    protected(parent, directory=True)
    path = parent / "rsync-net-bootstrap.lock"
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        info = os.fstat(fd)
        require(
            stat.S_ISREG(info.st_mode)
            and info.st_uid == 0
            and stat.S_IMODE(info.st_mode) == 0o600
            and info.st_nlink == 1,
            "bootstrap lock is not a root-owned private regular file",
        )
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ApplyError(
                "another bootstrap is running; no account/config mutations performed"
            ) from error
        yield
    finally:
        os.close(fd)


def public_policy(backend, manifest):
    """A conservative public-daemon policy guard; unsupported Match fails.

    Public Match rules can change authentication by address/time/group and are
    intentionally not accepted. Private authorization and backend-specific
    forced commands are generated separately.
    """
    require(
        manifest["mode"] == "public",
        "private mode is incomplete; activation is disabled",
    )
    visited = set()

    def inspect(path):
        path = Path(path)
        protected(path)
        resolved = path.resolve(strict=True)
        if resolved in visited:
            return
        visited.add(resolved)
        protected(resolved)
        for candidate in (*resolved.parents, resolved):
            backend.check_acl(candidate)
        for line in resolved.read_text().splitlines():
            fields = shlex.split(line, comments=True)
            if not fields:
                continue
            require(
                fields[0].lower() != "match",
                "public sshd Match rules need separate verification; refusing account reconstruction",
            )
            if fields[0].lower() == "include":
                for pattern in fields[1:]:
                    require(
                        "%" not in pattern and "$" not in pattern,
                        "unsupported dynamic public sshd Include",
                    )
                    absolute = (
                        pattern
                        if pattern.startswith("/")
                        else str(Path("/etc/ssh") / pattern)
                    )
                    for included in sorted(glob.glob(absolute)):
                        inspect(included)

    inspect("/etc/ssh/sshd_config")
    output = native([backend.sshd, "-T"])
    settings = {
        parts[0].lower(): parts[1]
        for line in output.splitlines()
        if len(parts := line.split(None, 1)) == 2
    }
    expected = {
        "pubkeyauthentication": "yes",
        "strictmodes": "yes",
        "usepam": "yes",
        "permituserenvironment": "no",
        "passwordauthentication": "no",
        # Keyboard-interactive/PAM authentication follows provider policy.
        "hostbasedauthentication": "no",
        "authorizedkeyscommand": "none",
        "trustedusercakeys": "none",
        "authorizedprincipalsfile": "none",
        "authorizedprincipalscommand": "none",
    }
    accepted_environment = [
        pattern
        for line in output.splitlines()
        if (fields := line.split()) and fields[0].lower() == "acceptenv"
        for pattern in fields[1:]
    ]
    require(
        all(pattern in {"LANG", "LC_*"} for pattern in accepted_environment),
        "public SSH accepts unsafe client environment variables; forced commands could be bypassed",
    )
    mismatches = {
        key: settings.get(key, "<absent>")
        for key, value in expected.items()
        if settings.get(key) != value
    }
    require(
        not mismatches,
        "public sshd authentication policy differs: "
        + repr(mismatches)
        + "; observed keywords="
        + repr(list(settings)[:8]),
    )
    require(
        settings.get("gssapiauthentication", "no") == "no",
        "public SSH GSSAPI authentication must be disabled",
    )
    key_sources = shlex.split(settings.get("authorizedkeysfile", ""))
    require(bool(key_sources), "public SSH has no approved home authorization source")
    for principal in manifest["principals"]:
        home = Path(principal["home"])
        managed = home / ".ssh/authorized_keys"
        paths = []
        for key_path in key_sources:
            require(
                key_path
                in {
                    ".ssh/authorized_keys",
                    ".ssh/authorized_keys2",
                    "%h/.ssh/authorized_keys",
                    "%h/.ssh/authorized_keys2",
                },
                "public SSH authorized-key source is not an approved home-only policy",
            )
            expanded = key_path.replace("%h", str(home))
            path = Path(expanded) if expanded.startswith("/") else home / expanded
            paths.append(path)
            protected(path)
            if path != managed:
                require(
                    not path.exists() and not path.is_symlink(),
                    "undeclared public SSH authorization source is present",
                )
        require(
            paths.count(managed) == 1,
            "public SSH must read the single managed home authorized_keys file",
        )
        secondary = home / ".ssh/authorized_keys2"
        require(
            not secondary.exists() and not secondary.is_symlink(),
            "undeclared authorized_keys2 is present",
        )


def preserves_authorization(before, desired, legacy=""):
    allowed = set(desired.splitlines()) | set(legacy.splitlines())
    return set(before.splitlines()) <= allowed


def _reconstruct_locked(
    manifest,
    *,
    backend,
    inspect,
    plan,
    digest,
    expected_digest,
    authorization,
    authorization_path,
    config_path,
    config_content,
    legacy_authorization=None,
    backend_config=None,
):
    require(
        manifest["mode"] == "public",
        "private mode is incomplete; activation is disabled",
    )
    backend.check()
    state = inspect(manifest)
    require(state["system"] == backend.label, "provider adapter/state mismatch")
    reviewed = plan(manifest, state)
    require(
        digest(manifest, reviewed) == expected_digest,
        "review is stale or belongs to a different policy; inspect and review again",
    )
    require(
        not reviewed["blockers"],
        "review contains unresolved identity/storage/security blockers",
    )
    require("activeProcesses" in state, "managed process state was not inspected")
    require(
        not reviewed["actions"] or not state["activeProcesses"],
        "managed processes are still active; quiesce clients/sessions before changing account policy",
    )
    require(
        not any(action["kind"] == "install-package" for action in reviewed["actions"]),
        "required packages must be installed through the provider-supported path before reconstruction",
    )
    require(
        "delegations" in state
        and all(not text.strip() for text in state["delegations"].values()),
        "delegated ZFS permissions on managed storage require separate review; no client authorization was published",
    )
    acl_paths = set()
    for dataset in manifest["datasets"]:
        protected(Path(dataset["mountpoint"]).parent, directory=True)
        acl_paths.add(Path(dataset["mountpoint"]))
    public_policy(backend, manifest)
    # Preflight every controlled path and native protocol executable before any
    # identity is created. Storage ownership/quotas must already match exactly.
    for principal in manifest["principals"]:
        backend.check_backend(principal)
        protected(Path(principal["home"]), directory=True)
        path = authorization_path(principal)
        protected(path)
        acl_paths.update((Path(principal["home"]), path))
        content = authorization(manifest, principal)
        if path.exists():
            require(
                preserves_authorization(
                    path.read_text(),
                    content,
                    legacy_authorization(manifest, principal)
                    if legacy_authorization is not None
                    else "",
                ),
                "existing managed keys would be removed or changed; enrollment never silently revokes keys",
            )
        config = backend_config(principal) if backend_config is not None else None
        if config is not None:
            backend_path, backend_content = config
            protected(backend_path)
            acl_paths.add(backend_path)
            if backend_path.exists():
                require(
                    backend_path.read_text() == backend_content
                    or backend_path.read_text().startswith(
                        "# Managed by rsync-net; no credentials.\n"
                    ),
                    "existing backend config is unmanaged; no configuration was overwritten",
                )
        helpers = {
            "restic": ["/usr/local/bin/rclone"],
            # The FreeBSD package ships rrsync under sbin without a Python
            # dependency. Use the declared controller interpreter explicitly.
            "git": [
                manifest["connection"]["interpreter"],
                "/usr/local/sbin/rrsync",
            ],
            "nix-cache": ["/usr/local/bin/nix-store"],
        }[principal["backend"]]
        for helper in helpers:
            source = Path(helper)
            protected(source.parent, directory=True)
            acl_paths.add(source.parent)
            resolved = source.resolve(strict=True)
            protected(resolved)
            require(os.access(resolved, os.X_OK), f"helper is not executable: {helper}")
            acl_paths.add(resolved)
    if manifest["mode"] == "private":
        protected(config_path)
        acl_paths.add(Path(config_path))
    for path in sorted(
        {
            candidate
            for managed_path in acl_paths
            for candidate in (*managed_path.parents, managed_path)
            if candidate.exists()
        }
    ):
        backend.check_acl(path)
    if manifest["mode"] == "private":
        # Validate generated daemon configuration using the native parser before
        # publication. The temporary file is root-owned and is not an auth source.
        with tempfile.TemporaryDirectory(
            prefix="rsync-net-sshd-", dir="/root"
        ) as temporary:
            candidate = Path(temporary) / "sshd.conf"
            candidate.write_text(config_content)
            native([backend.sshd, "-t", "-f", str(candidate)])
    changes = []
    for principal in manifest["principals"]:
        # Refresh native identity lookups immediately before each operation;
        # never renumber, modify groups or delete a conflicting account.
        try:
            group = grp.getgrnam(principal["name"])
        except KeyError:
            try:
                grp.getgrgid(principal["gid"])
            except KeyError:
                backend.create_group(principal)
                changes.append("created group " + principal["name"])
            else:
                raise ApplyError("reserved GID became occupied") from None
        else:
            require(
                group.gr_gid == principal["gid"]
                and set(group.gr_mem) <= {principal["name"]},
                "group changed after review",
            )
        try:
            user = pwd.getpwnam(principal["name"])
        except KeyError:
            try:
                pwd.getpwuid(principal["uid"])
            except KeyError:
                backend.create_user(principal)
                changes.append("created user " + principal["name"])
            else:
                raise ApplyError("reserved UID became occupied") from None
        else:
            require(
                (user.pw_uid, user.pw_gid, user.pw_dir, user.pw_shell)
                == (principal["uid"], principal["gid"], principal["home"], "/bin/sh"),
                "identity changed after review",
            )
        home = Path(principal["home"])
        existed = home.exists()
        directory(home)
        for path in (home, home / ".ssh"):
            directory(path)
            if stat.S_IMODE(path.stat().st_mode) != 0o755:
                path.chmod(0o755)
                changes.append("restored public authorization directory " + str(path))
        if not existed:
            changes.append("created root-owned home " + principal["name"])
    # Reinspect all identity/storage guards after native account-tool side
    # effects. File publication is last; partial account restoration is safe to
    # review/retry, not automatically rolled back by deleting users.
    after_accounts = plan(manifest, inspect(manifest))
    require(
        not after_accounts["blockers"],
        "post-account inspection failed; no new device authorization was published",
    )
    for principal in manifest["principals"]:
        config = backend_config(principal) if backend_config is not None else None
        if config is not None and atomic_file(config[0], config[1]):
            changes.append("restored backend configuration " + principal["name"])
        if atomic_file(
            authorization_path(principal), authorization(manifest, principal)
        ):
            changes.append("restored public authorization " + principal["name"])
    if manifest["mode"] == "private" and atomic_file(
        config_path, config_content, mode=0o600
    ):
        changes.append("restored private daemon configuration")
    return {
        "schemaVersion": 1,
        "operation": "administrative-bootstrap-reconstruction",
        "adapter": backend.label,
        "changes": changes,
        "serviceActivationPerformed": False,
        "storageMutationPerformed": False,
        "note": "Declared accounts and root-owned home forced-command authorization were reconstructed. The existing provider SSH daemon/configuration, admin keys, storage and retention were unchanged.",
    }


def reconstruct(manifest, **parameters):
    require(
        manifest["mode"] == "public",
        "private mode is incomplete; activation is disabled",
    )
    # Reject the wrong host/privilege before even creating a runtime lock.
    parameters["backend"].check()
    with reconstruction_lock():
        return _reconstruct_locked(manifest, **parameters)
