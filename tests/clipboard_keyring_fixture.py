#!/usr/bin/env python3
"""Exercise the real private VM keyring and vault without logging its keys."""

import argparse
import base64
import os
import socket
import struct
import subprocess
import time
from pathlib import Path

import gi

gi.require_version("Secret", "1")
from gi.repository import GLib, Secret

SCHEMA = Secret.Schema.new(
    "dev.snowytrees.ClipboardHistory",
    Secret.SchemaFlags.NONE,
    {"application": Secret.SchemaAttributeType.STRING},
)
ATTRIBUTES = {"application": "dev.snowytrees.clipboard-history"}


def collection():
    deadline = time.monotonic() + 5
    last_error = None
    while True:
        try:
            service = Secret.Service.get_sync(
                Secret.ServiceFlags.LOAD_COLLECTIONS, None
            )
            value = Secret.Collection.for_alias_sync(
                service, "default", Secret.CollectionFlags.NONE, None
            )
            if value is not None:
                return service, value
        except GLib.Error as error:
            last_error = error
        if time.monotonic() > deadline:
            raise AssertionError(
                f"The fixture login keyring was not created: {last_error}"
            )
        time.sleep(0.05)


def control(*arguments, check=True):
    return subprocess.run(
        ["systemctl", "--user", *arguments], check=check, capture_output=True
    )


def interactions(mount):
    def run(*arguments, data=None):
        result = subprocess.run(
            arguments,
            input=data,
            check=True,
            stdout=subprocess.DEVNULL if arguments[0] == "wl-copy" else subprocess.PIPE,
            stderr=subprocess.DEVNULL if arguments[0] == "wl-copy" else subprocess.PIPE,
            timeout=10,
        )
        return result.stdout

    def history():
        return run(os.environ["CLIPHIST"], "-db-path", str(mount / "db"), "list")

    def until(predicate):
        deadline = time.monotonic() + 5
        while not predicate():
            if time.monotonic() > deadline:
                raise AssertionError("Private clipboard interaction timed out")
            time.sleep(0.05)

    # Native sensitive-hint state must bypass persistence.
    subprocess.run(
        [os.environ["CLIPHIST"], "-db-path", str(mount / "db"), "store"],
        env={**os.environ, "CLIPBOARD_STATE": "sensitive"},
        input=b"private-synthetic-sensitive-exclusion",
        check=True,
        capture_output=True,
    )
    assert b"private-synthetic-sensitive-exclusion" not in history()
    before_sensitive = history()
    sensitive = b"private-synthetic-sensitive-mime-hint"
    run("wl-copy", "--sensitive", "--type", "text/plain", data=sensitive)
    assert run("wl-paste", "--no-newline", "--type", "text/plain") == sensitive
    time.sleep(0.2)
    assert history() == before_sensitive
    text = "private multiline clipboard\nsecond line\tUnicode λ".encode()
    run("wl-copy", "--type", "text/plain;charset=utf-8", data=text)
    until(lambda: b"private multiline" in history())
    image = base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6wWQAAAAASUVORK5CYII="
    )
    run("wl-copy", "--type", "image/png", data=image)
    until(lambda: b"png 1x1" in history())
    assert sensitive not in history(), "Native sensitive MIME hint was persisted"
    image_entry = next(line for line in history().splitlines() if b"png 1x1" in line)
    assert (
        run(
            os.environ["CLIPHIST"],
            "-db-path",
            str(mount / "db"),
            "decode",
            data=image_entry,
        )
        == image
    )

    def pick(keys, query=None, action="pick"):
        with subprocess.Popen(
            [os.environ["PICKER"], action], stdout=subprocess.DEVNULL
        ) as process:
            until(
                lambda: (
                    subprocess.run(
                        ["pgrep", "-u", str(os.getuid()), "-x", "fuzzel"],
                        capture_output=True,
                        check=False,
                    ).returncode
                    == 0
                )
            )
            time.sleep(0.3)
            if query:
                run("wtype", query)
            run("wtype", "-k", keys)
            assert process.wait(timeout=5) == 0

    # Cancellation leaves the actual clipboard and saved entries unchanged.
    before = history()
    pick("Escape")
    assert run("wl-paste", "--no-newline", "--type", "image/png") == image
    assert history() == before
    pick("Return", "private multiline")
    assert run("wl-paste", "--no-newline", "--type", "text/plain;charset=utf-8") == text
    pick("Return", "png 1x1")
    assert run("wl-paste", "--no-newline", "--type", "image/png") == image
    pick("Return", "private multiline", "delete")
    assert b"private multiline" not in history()
    pick("Return", action="clear")  # Cancel is the default confirmation row.
    assert history()
    pick("Return", "Clear saved", "clear")
    until(lambda: history() == b"")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=("prepare", "lock", "unlock", "wrong-key", "inspect", "interactions"),
    )
    args = parser.parse_args()
    mount = Path(os.environ["XDG_RUNTIME_DIR"]) / "clipboard-history/plain"
    cipher = Path.home() / ".local/state/clipboard-history/vault"
    if args.action in ("prepare", "unlock"):
        # Exercise GNOME Keyring's native PAM control unlock protocol against
        # this VM's real daemon. --unlock starts a new daemon rather than
        # unlocking an existing Secret Service provider.
        def unlock_login():
            password = b"private-vm-password-not-a-user-credential"
            packet = (
                struct.pack("!III", 12 + len(password), 1, len(password)) + password
            )
            deadline = time.monotonic() + 5
            while True:
                try:
                    with socket.socket(
                        socket.AF_UNIX, socket.SOCK_STREAM
                    ) as connection:
                        connection.connect(
                            str(Path(os.environ["XDG_RUNTIME_DIR"]) / "keyring/control")
                        )
                        connection.sendall(b"\0" + packet)
                        response = connection.recv(8, socket.MSG_WAITALL)
                        assert struct.unpack("!II", response) == (8, 0), (
                            "Native keyring unlock failed"
                        )
                        return
                except FileNotFoundError, ConnectionRefusedError:
                    if time.monotonic() > deadline:
                        raise
                    time.sleep(0.05)

        unlock_login()
        if args.action == "prepare":
            # Load the freshly created encrypted login file through the usual
            # daemon startup path before exercising the clipboard service.
            control("restart", "gnome-keyring.service")
            unlock_login()
        _, value = collection()
        assert not value.get_locked()
    elif args.action == "lock":
        service, value = collection()
        Secret.Service.lock_sync(service, [value], None)
    elif args.action == "wrong-key":
        original = Secret.password_lookup_sync(SCHEMA, ATTRIBUTES, None)
        assert original, "The real vault did not create its keyring item"
        before = (cipher / "gocryptfs.conf").read_bytes()
        control("stop", "clipboard-vault.service")
        try:
            assert not mount.is_mount()
            Secret.password_store_sync(
                SCHEMA,
                ATTRIBUTES,
                Secret.COLLECTION_DEFAULT,
                "Clipboard history vault",
                "deliberately-wrong-private-vm-key",
                None,
            )
            result = control("start", "clipboard-vault.service", check=False)
            assert result.returncode != 0, "A wrong vault key was accepted"
            assert not mount.is_mount()
            assert not (mount / "db").exists(), "Plaintext fallback DB appeared"
            assert (cipher / "gocryptfs.conf").read_bytes() == before
        finally:
            Secret.password_store_sync(
                SCHEMA,
                ATTRIBUTES,
                Secret.COLLECTION_DEFAULT,
                "Clipboard history vault",
                original,
                None,
            )
        control("reset-failed", "clipboard-vault.service")
        control("start", "cliphist.service", "cliphist-images.service")
        assert mount.is_mount()
    elif args.action == "interactions":
        interactions(mount)
    elif args.action == "inspect":
        value = Secret.password_lookup_sync(SCHEMA, ATTRIBUTES, None)
        assert value, "The keyring item is missing"
        encoded_key = value.encode()
        for p in Path("/proc").iterdir():
            if not p.name.isdecimal():
                continue
            try:
                if (
                    "gocryptfs" not in (p / "comm").read_text()
                    and "clipboard-vault" not in (p / "cmdline").read_text()
                ):
                    continue
                assert encoded_key not in (p / "cmdline").read_bytes(), (
                    "Vault key leaked into process arguments"
                )
                assert encoded_key not in (p / "environ").read_bytes(), (
                    "Vault key leaked into the environment"
                )
            except FileNotFoundError, PermissionError, ProcessLookupError:
                pass
        marker = b"encrypted-clipboard-private-native-fixture-marker"
        assert marker in (mount / "db").read_bytes()
        for p in cipher.rglob("*"):
            if p.is_file():
                data = p.read_bytes()
                assert marker not in data, (
                    "Clipboard plaintext was stored outside the encrypted view"
                )
                assert encoded_key not in data, (
                    "A plaintext vault password file was created"
                )
        print(
            "Native keyring item, process secret handling and ciphertext contents verified"
        )


if __name__ == "__main__":
    main()
