"""Select a workload-aware kernel governor before TLP applies energy preferences."""

from pathlib import Path


def governor_for(driver: str, available: set[str]) -> str | None:
    if driver in {"intel_pstate", "amd-pstate-epp"}:
        return "powersave" if "powersave" in available else None
    if driver in {"intel_cpufreq", "amd-pstate", "acpi-cpufreq"}:
        return next(
            (name for name in ("schedutil", "ondemand") if name in available), None
        )
    return None


def apply_policy(root: Path = Path("/sys/devices/system/cpu/cpufreq")) -> None:
    for policy in sorted(root.glob("policy[0-9]*")):
        try:
            driver = (policy / "scaling_driver").read_text().strip()
            available = set(
                (policy / "scaling_available_governors").read_text().split()
            )
        except FileNotFoundError:
            # A policy may disappear if a CPU is offlined during startup.
            continue
        governor = governor_for(driver, available)
        if governor is not None:
            current = (policy / "scaling_governor").read_text().strip()
            if current != governor:
                (policy / "scaling_governor").write_text(governor)
                print(f"{policy.name}: {driver}: {current} -> {governor}")


if __name__ == "__main__":
    apply_policy()
