"""Keep a private PipeWire daemon alive when its private X server disappears."""

import argparse
import json
import os
import resource
import select
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


def wait_until(predicate, description, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {description}")


def copy_configuration(source, destination):
    """Copy store contents without retaining their read-only directory modes."""
    for parent, directories, files in os.walk(source, followlinks=True):
        target = destination / Path(parent).relative_to(source)
        target.mkdir(parents=True, exist_ok=True)
        for directory in directories:
            (target / directory).mkdir(exist_ok=True)
        for file in files:
            shutil.copyfile(Path(parent) / file, target / file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument(
        "--stock", action="store_true", help="Run the unfixed negative control"
    )
    arguments = parser.parse_args()
    # The negative control intentionally faults; keep it out of the host's
    # core-dump store and avoid retaining inherited process environment data.
    _, core_limit = resource.getrlimit(resource.RLIMIT_CORE)
    resource.setrlimit(resource.RLIMIT_CORE, (0, core_limit))
    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="audio-session-") as temporary:
        root = Path(temporary)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        configuration = root / "config"
        configuration.mkdir()
        copy_configuration(Path(os.environ["AUDIO_STOCK_CONFIG"]).parent, configuration)
        if not arguments.stock:
            copy_configuration(Path(os.environ["AUDIO_CONFIG_SOURCE"]), configuration)
        environment = {
            name: value
            for name, value in os.environ.items()
            if not name.startswith("PIPEWIRE_")
            and name
            not in {
                "DISPLAY",
                "WAYLAND_DISPLAY",
                "DBUS_SESSION_BUS_ADDRESS",
                "PULSE_SERVER",
                "XAUTHORITY",
                "SESSION_MANAGER",
            }
        }
        environment.update(
            HOME=str(root),
            XDG_RUNTIME_DIR=str(runtime),
            XDG_CONFIG_HOME=str(root / "home-config"),
            PIPEWIRE_CONFIG_DIR=str(configuration),
            PIPEWIRE_DEBUG="3",
        )
        children = []
        try:
            with (arguments.output_dir / "xserver.log").open("wb") as xlog:
                read_fd, write_fd = os.pipe()
                xserver = subprocess.Popen(
                    [
                        "Xvfb",
                        "-displayfd",
                        str(write_fd),
                        "-screen",
                        "0",
                        "800x600x24",
                        "-nolisten",
                        "tcp",
                        "-ac",
                    ],
                    env=environment,
                    stdout=xlog,
                    stderr=subprocess.STDOUT,
                    pass_fds=(write_fd,),
                )
                children.append(xserver)
                os.close(write_fd)
                with os.fdopen(read_fd) as display_pipe:
                    assert select.select([display_pipe], [], [], 10)[0], (
                        "Private X server did not publish a display"
                    )
                    display = display_pipe.readline().strip()
                assert display and xserver.poll() is None, (
                    "Private X server did not start"
                )
                environment["DISPLAY"] = f":{display}"
                with (arguments.output_dir / "pipewire.log").open("wb") as plog:
                    daemon = subprocess.Popen(
                        ["pipewire"],
                        env=environment,
                        stdout=plog,
                        stderr=subprocess.STDOUT,
                    )
                    children.append(daemon)

                    def snapshot():
                        try:
                            result = subprocess.run(
                                ["pw-dump", "--remote", "pipewire-0-manager"],
                                env=environment,
                                capture_output=True,
                                text=True,
                                timeout=2,
                                check=False,
                            )
                        except subprocess.TimeoutExpired:
                            return None
                        if result.returncode:
                            (arguments.output_dir / "client-error.log").write_text(
                                result.stderr
                            )
                        return (
                            json.loads(result.stdout)
                            if result.returncode == 0
                            else None
                        )

                    before = wait_until(snapshot, "private PipeWire")
                    modules = [
                        item.get("info", {}).get("props", {}).get("module.name", "")
                        for item in before
                        if item.get("type") == "PipeWire:Interface:Module"
                    ]
                    if arguments.stock:
                        assert "libpipewire-module-x11-bell" in modules, modules
                    else:
                        assert "libpipewire-module-x11-bell" not in modules, modules
                    xserver.terminate()
                    xserver.wait(timeout=3)
                    deadline = time.monotonic() + 1
                    while time.monotonic() < deadline and daemon.poll() is None:
                        time.sleep(0.05)
                    result = {
                        "pid": daemon.pid,
                        "bell_loaded": "libpipewire-module-x11-bell" in modules,
                        "returncode": daemon.poll(),
                        "survived": daemon.poll() is None,
                    }
                    (arguments.output_dir / "result.json").write_text(
                        json.dumps(result, indent=2)
                    )
                    assert daemon.poll() is None, (
                        f"PipeWire died with X server: {result}"
                    )
                    after = wait_until(snapshot, "PipeWire after X shutdown")
                    assert any(
                        item.get("info", {}).get("props", {}).get("node.name")
                        == "Dummy-Driver"
                        for item in after
                    ), "Audio graph stopped responding after X shutdown"
        finally:
            for child in reversed(children):
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()


if __name__ == "__main__":
    main()
