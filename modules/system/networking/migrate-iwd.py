"""Import supported iwd profiles without exposing credentials or removing originals."""

import hashlib
import os
import pwd
import re
import tempfile
from pathlib import Path


class UnsupportedProfile(ValueError):
    """A profile requires manual configuration rather than a guessed conversion."""


def read_settings(path: Path) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current: dict[str, str] | None = None
    escapes = {"s": " ", "t": "\t", "n": "\n", "r": "\r", "\\": "\\"}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", ";")):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            current = sections.setdefault(stripped[1:-1], {})
            continue
        key, separator, value = line.partition("=")
        if current is None or not separator:
            raise UnsupportedProfile
        value = value.lstrip(" \t")
        current[key.strip()] = re.sub(
            r"\\([stnr\\])", lambda match: escapes[match[1]], value
        )
    return sections


def convert_profile(path: Path) -> str:
    if path.is_symlink() or path.suffix not in {".psk", ".open"}:
        raise UnsupportedProfile
    name = path.stem
    ssid = bytes.fromhex(name[1:]) if name.startswith("=") else name.encode("utf-8")
    if not 1 <= len(ssid) <= 32:
        raise UnsupportedProfile
    settings = read_settings(path)
    security = settings.get("Security", {})
    # Do not silently drop SAE identifiers, encrypted data, MAC overrides or
    # learned transition restrictions. Their semantics need explicit setup.
    if set(security) - {"Passphrase", "PreSharedKey"}:
        raise UnsupportedProfile
    lines = ["network={", f"    ssid={ssid.hex()}"]
    general = settings.get("Settings", {})
    if set(general) - {"Hidden", "AutoConnect"}:
        raise UnsupportedProfile
    if set(settings) - {"Settings", "Security", "IPv4", "IPv6"}:
        raise UnsupportedProfile
    # networkd retains responsibility for addressing. Static iwd-only address
    # settings cannot be safely inferred as part of authentication migration.
    if settings.get("IPv4") or settings.get("IPv6"):
        raise UnsupportedProfile
    if general.get("Hidden", "false").lower() in {"true", "1"}:
        lines.append("    scan_ssid=1")
    if general.get("AutoConnect", "true").lower() in {"false", "0"}:
        lines.append("    disabled=1")
    if path.suffix == ".open":
        lines.append("    key_mgmt=NONE")
    elif "Passphrase" in security:
        passphrase = security["Passphrase"]
        if not 8 <= len(passphrase.encode("utf-8")) <= 63:
            raise UnsupportedProfile
        # psk's parser does not understand printf escapes. Derive its binary
        # WPA2 key, and use the generic hex-string parser for the SAE password.
        password = passphrase.encode("utf-8")
        psk = hashlib.pbkdf2_hmac("sha1", password, ssid, 4096, 32).hex()
        lines.extend(
            [
                "    key_mgmt=SAE WPA-PSK",
                f"    psk={psk}",
                f"    sae_password={password.hex()}",
            ]
        )
    elif re.fullmatch(r"[0-9a-fA-F]{64}", security.get("PreSharedKey", "")):
        lines.extend(["    key_mgmt=WPA-PSK", "    psk=" + security["PreSharedKey"]])
    else:
        raise UnsupportedProfile
    return "\n".join(lines + ["}", ""])


def migrate(
    source: Path, destination: Path, owner: tuple[int, int] | None = None
) -> dict[str, int]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.parent.chmod(0o750)
    if owner is not None:
        os.chown(destination.parent, *owner)
    if destination.is_symlink():
        raise OSError("Refusing a symbolic-link destination")
    if destination.exists() and destination.read_text(encoding="utf-8").strip():
        return {"existing_configuration_preserved": 1}
    converted = []
    skipped = 0
    if source.exists():
        for path in sorted(source.iterdir()):
            if path.suffix not in {".psk", ".open", ".8021x"}:
                continue
            try:
                converted.append(convert_profile(path))
            except OSError, UnicodeError, ValueError:
                skipped += 1
    descriptor, temporary = tempfile.mkstemp(
        dir=destination.parent, prefix=".iwd-import-"
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            if owner is not None:
                os.fchown(stream.fileno(), *owner)
            stream.write("# Imported from iwd; original profiles are preserved.\n")
            stream.write("\n".join(converted))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return {"imported": len(converted), "manual_configuration_required": skipped}


def main() -> None:
    try:
        account = pwd.getpwnam("wpa_supplicant")
        result = migrate(
            Path(CONFIG["source"]),
            Path(CONFIG["destination"]),
            (account.pw_uid, account.pw_gid),
        )
    except OSError, KeyError, UnicodeError:
        raise SystemExit(
            "Wi-Fi profile import failed; existing iwd files remain intact."
        ) from None
    counts = ", ".join(f"{key}={value}" for key, value in result.items())
    print(f"Wi-Fi profile migration: {counts}")
    if result.get("manual_configuration_required"):
        print(
            "Enterprise, encrypted or unsupported profiles require setup in wpa_gui; originals remain in /var/lib/iwd."
        )


if __name__ == "__main__":
    main()
