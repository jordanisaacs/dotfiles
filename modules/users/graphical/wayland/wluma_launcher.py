"""Discover the local ALS/backlights for the pinned wluma configuration format."""

import json
import os
import sys
from pathlib import Path

SENSOR_NAMES = {"als", "acpi-als", "apds9960", "cros-ec-light", "aop-sensors-als"}
THRESHOLDS = {
    0: "night",
    20: "dark",
    80: "dim",
    250: "normal",
    500: "bright",
    800: "outdoors",
}


def discover_config(sysfs: Path = Path("/sys")) -> str | None:
    sensors = sysfs / "bus/iio/devices"
    supported_sensor = False
    for path in sorted(sensors.glob("iio:device*")):
        try:
            if (path / "name").read_text().strip() in SENSOR_NAMES:
                supported_sensor = True
                break
        except FileNotFoundError:
            continue
    backlights = [
        path
        for path in sorted((sysfs / "class/backlight").glob("*"))
        if (path / "brightness").exists() and (path / "max_brightness").exists()
    ]
    if not supported_sensor or not backlights:
        return None
    thresholds = ", ".join(
        f"{key} = {json.dumps(value)}" for key, value in THRESHOLDS.items()
    )
    config = [
        "[als.iio]",
        f"path = {json.dumps(str(sensors))}",
        f"thresholds = {{ {thresholds} }}",
    ]
    for path in backlights:
        config.extend(
            [
                "",
                "[[output.backlight]]",
                f"name = {json.dumps(path.name)}",
                f"path = {json.dumps(str(path))}",
                'capturer = "none"',
            ]
        )
    return "\n".join(config) + "\n"


def main() -> None:
    config = discover_config()
    if config is None:
        print(
            "No supported ambient-light sensor and backlight; adaptive brightness is inactive."
        )
        return
    runtime = Path(os.environ["XDG_RUNTIME_DIR"]) / "wluma-autoconfig"
    directory = runtime / "wluma"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    (directory / "config.toml").write_text(config)
    # The daemon uses its normal XDG data directory for learned preferences.
    os.environ["XDG_CONFIG_HOME"] = str(runtime)
    os.execv(sys.argv[1], [sys.argv[1]])


if __name__ == "__main__":
    main()
