"""Keep clipboard history in a keyring-unlocked, session-mounted gocryptfs vault."""

import argparse
import fcntl
import os
import resource
import secrets
import signal
import subprocess
import sys
import time
from pathlib import Path

import gi

gi.require_version("Secret", "1")
gi.require_version("GLibUnix", "2.0")
from gi.repository import GLib, GLibUnix, Secret


class VaultError(RuntimeError):
    pass


SCHEMA = Secret.Schema.new(
    "dev.snowytrees.ClipboardHistory",
    Secret.SchemaFlags.NONE,
    {"application": Secret.SchemaAttributeType.STRING},
)
ATTRIBUTES = {"application": "dev.snowytrees.clipboard-history"}


def keyring():
    try:
        service = Secret.Service.get_sync(Secret.ServiceFlags.LOAD_COLLECTIONS, None)
        collection = Secret.Collection.for_alias_sync(
            service, "default", Secret.CollectionFlags.NONE, None
        )
    except GLib.Error as error:
        raise VaultError("The login keyring is unavailable") from error
    if collection is None:
        raise VaultError("Create and unlock a default password keyring first")
    return service, collection


def password(cipher: Path) -> bytes:
    try:
        value = Secret.password_lookup_sync(SCHEMA, ATTRIBUTES, None)
        if value is None:
            if (cipher / "gocryptfs.conf").exists():
                raise VaultError(
                    "The existing clipboard vault key is missing from the keyring"
                )
            if any(cipher.iterdir()):
                raise VaultError("Refusing to initialize a non-empty clipboard vault")
            value = secrets.token_urlsafe(48)
            if not Secret.password_store_sync(
                SCHEMA,
                ATTRIBUTES,
                Secret.COLLECTION_DEFAULT,
                "Clipboard history vault",
                value,
                None,
            ):
                raise VaultError(
                    "Could not save the clipboard vault key in the keyring"
                )
    except GLib.Error as error:
        raise VaultError("Could not access the clipboard vault key") from error
    if not value or "\n" in value:
        raise VaultError("The clipboard vault key has an invalid format")
    return value.encode()


def crypt_process(arguments: list[str], key: bytes) -> subprocess.Popen:
    read_descriptor, write_descriptor = os.pipe()
    try:
        os.write(write_descriptor, key + b"\n")
        os.close(write_descriptor)
        write_descriptor = -1
        return subprocess.Popen(
            [
                CONFIG["gocryptfs"],
                "-q",
                "-nosyslog",
                "-passfile",
                f"/dev/fd/{read_descriptor}",
                *arguments,
            ],
            pass_fds=(read_descriptor,),
            stdout=subprocess.DEVNULL,
            stderr=None,
        )
    finally:
        os.close(read_descriptor)
        if write_descriptor != -1:
            os.close(write_descriptor)


def systemctl(*arguments: str, timeout: int = 40) -> None:
    subprocess.run(
        [CONFIG["systemctl"], "--user", *arguments], check=True, timeout=timeout
    )


def unlock() -> None:
    service, collection = keyring()
    if collection.get_locked():
        try:
            Secret.Service.unlock_sync(service, [collection], None)
        except GLib.Error as error:
            raise VaultError("The password keyring was not unlocked") from error
    if collection.get_locked():
        raise VaultError("The password keyring is still locked")
    systemctl("restart", "clipboard-vault.service")
    systemctl("restart", "cliphist.service", "cliphist-images.service")


def serve() -> None:
    service, collection = keyring()
    if collection.get_locked():
        raise VaultError("Unlock the login keyring to use clipboard history")
    cipher = Path(CONFIG["cipherDirectory"])
    cipher.mkdir(mode=0o700, parents=True, exist_ok=True)
    cipher.chmod(0o700)
    mount = Path(os.environ["XDG_RUNTIME_DIR"]) / "clipboard-history/plain"
    mount.mkdir(mode=0o500, parents=True, exist_ok=True)
    if mount.is_mount():
        raise VaultError("The clipboard vault is already mounted")
    # The underlying directory cannot accept a DB after unexpected mount loss.
    mount.chmod(0o500)
    key = password(cipher)
    if not (cipher / "gocryptfs.conf").exists():
        process = crypt_process(["-init", str(cipher)], key)
        if process.wait(timeout=30) != 0:
            raise VaultError("Clipboard vault initialization failed")
    # FUSE requires a writable mountpoint during setup. Keep a descriptor to
    # its underlying directory, then seal that directory before READY: chmod
    # through the mounted path would instead change the decrypted vault root.
    mount_descriptor = os.open(mount, os.O_RDONLY | os.O_DIRECTORY)
    os.fchmod(mount_descriptor, 0o700)
    try:
        process = crypt_process(["-fg", str(cipher), str(mount)], key)
    except BaseException:
        os.fchmod(mount_descriptor, 0o500)
        os.close(mount_descriptor)
        raise
    del key
    loop = GLib.MainLoop()
    stopping = False
    ready = False
    exit_code = 0

    def stop(*_arguments):
        nonlocal stopping
        if not stopping:
            stopping = True
            # Stop native watchers before unmounting, including on a keyring
            # lock event that occurs while the graphical session stays alive.
            if ready:
                try:
                    systemctl(
                        "stop", "cliphist.service", "cliphist-images.service", timeout=5
                    )
                except OSError, subprocess.SubprocessError:
                    print(
                        "Could not stop clipboard watchers; closing their encrypted view",
                        file=sys.stderr,
                    )
            if process.returncode is None:
                # GLib exclusively reaps this child. Popen.send_signal() polls
                # first and can reap it, racing GLib's pidfd child watch.
                try:
                    os.kill(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        return GLib.SOURCE_REMOVE

    def child_exited(_pid, status):
        nonlocal exit_code
        process.returncode = os.waitstatus_to_exitcode(status) if status >= 0 else 1
        if not stopping:
            exit_code = process.returncode or 1
        loop.quit()

    def collection_changed(_collection, _property):
        if collection.get_locked():
            stop()

    def owner_changed(_service, _property):
        if service.get_name_owner() is None:
            stop()

    GLib.child_watch_add(GLib.PRIORITY_DEFAULT, process.pid, child_exited)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)
    collection.connect("notify::locked", collection_changed)
    service.connect("notify::g-name-owner", owner_changed)
    context = GLib.MainContext.default()
    deadline = time.monotonic() + 30
    while (
        not mount.is_mount()
        and process.returncode is None
        and time.monotonic() < deadline
    ):
        while context.pending():
            context.iteration(False)
        time.sleep(0.02)
    os.fchmod(mount_descriptor, 0o500)
    os.close(mount_descriptor)
    if not mount.is_mount():
        if process.returncode is None:
            stop()
            loop.run()
        raise VaultError("The clipboard vault could not be mounted")
    if collection.get_locked() or service.get_name_owner() is None:
        stop()
        loop.run()
        raise VaultError("The password keyring became unavailable during startup")
    ready = True
    subprocess.run(
        [CONFIG["notify"], "--ready", "--status=Encrypted clipboard history unlocked"],
        check=True,
    )
    try:
        loop.run()
    finally:
        if process.returncode is None:
            stop()
            loop.run()
        if mount.is_mount():
            subprocess.run([CONFIG["fusermount"], "-u", str(mount)], check=True)
        mount.chmod(0o500)
    if exit_code:
        raise VaultError("The clipboard vault process stopped unexpectedly")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "serve", "unlock"))
    arguments = parser.parse_args()
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    if arguments.action == "check":
        try:
            _, collection = keyring()
            return 1 if collection.get_locked() else 0
        except VaultError:
            return 1
    if arguments.action == "unlock":
        unlock()
        return 0
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    descriptor = os.open(
        runtime / "clipboard-vault.lock", os.O_CREAT | os.O_RDWR, 0o600
    )
    with os.fdopen(descriptor, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        serve()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (VaultError, OSError, subprocess.SubprocessError) as error:
        print(f"Clipboard history unavailable: {error}", file=sys.stderr)
        raise SystemExit(1) from error
