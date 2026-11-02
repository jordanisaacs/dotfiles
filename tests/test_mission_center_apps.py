"""Run upstream Rust app detection against synthetic UWSM cgroup hierarchies."""

import argparse
import os
import shutil
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--stock", action="store_true")
    args = parser.parse_args()
    source = Path(os.environ["MISSION_CENTER_SOURCE"])
    relative = Path("subprojects/magpie/platform-linux/crates/app-rummage")
    work = Path.cwd() / "source"
    crate = work / relative
    shutil.copytree(source / relative, crate)
    for path in work.rglob("*"):
        path.chmod(path.stat().st_mode | 0o200)
    original = (crate / "src/cgroup.rs").read_text()
    subprocess.run(
        ["patch", "-p1", "-i", os.environ["MISSION_CENTER_PATCH"]],
        cwd=work,
        check=True,
    )
    if args.stock:
        # Extract a root-path seam for the fixture, retaining upstream's exact
        # old traversal. The new tests must fail semantically, not at compile.
        path = crate / "src/cgroup.rs"
        patched = path.read_text()
        old_body = original.split("    let app_slice_dir = match ", 1)[1]
        old_body = old_body.split("\n#[cfg(test)]", 1)[0]
        old_body = old_body.replace(
            "Path::new(&app_slice_dir).read_dir()", "slice.read_dir()", 1
        ).replace(
            "                app_slice_dir,", "                slice.display(),", 1
        )
        signature = patched.split("fn running_apps_in_slice", 1)[1]
        signature = signature.split("    let mut result =", 1)[0]
        prefix = patched.split("fn running_apps_in_slice", 1)[0]
        tests = patched.split("\n#[cfg(test)]", 1)[1]
        path.write_text(
            prefix
            + "fn running_apps_in_slice"
            + signature
            + "    let app_slice_dir = match "
            + old_body
            + "\n#[cfg(test)]"
            + tests
        )

    # Isolate this small upstream library from Magpie's hardware/UI workspace.
    with (crate / "Cargo.toml").open("a") as handle:
        handle.write("\n[workspace]\n")
    shutil.copyfile(source / "subprojects/magpie/Cargo.lock", crate / "Cargo.lock")
    vendor = Path(os.environ["MISSION_CENTER_VENDOR"])
    config = (
        (vendor / ".cargo/config.toml").read_text().replace("@vendor@", str(vendor))
    )
    (crate / ".cargo").mkdir(exist_ok=True)
    (crate / ".cargo/config.toml").write_text(config)
    subprocess.run(["cargo", "test", "--offline", "--lib"], cwd=crate, check=True)
    (crate / "examples").mkdir(exist_ok=True)
    shutil.copyfile(
        os.environ["MISSION_CENTER_INVENTORY"], crate / "examples/uwsm-inventory.rs"
    )
    subprocess.run(
        ["cargo", "build", "--offline", "--example", "uwsm-inventory"],
        cwd=crate,
        check=True,
    )
    (args.output / "bin").mkdir(parents=True)
    shutil.copyfile(
        crate / "target/debug/examples/uwsm-inventory",
        args.output / "bin/mission-center-app-inventory",
    )
    (args.output / "bin/mission-center-app-inventory").chmod(0o755)


if __name__ == "__main__":
    main()
