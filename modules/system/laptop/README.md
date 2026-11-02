# Laptop power and performance

`jd.laptop.enable` enables native TLP/tlp-pd automatic AC/battery policy, UPower
battery thresholds and logind suspend/hibernate handling. TLP owns CPU/platform
policy; competing auto-cpufreq, tuned and power-profiles-daemon services are
disabled. Profile consumers use the power-profiles interface provided by tlp-pd.

Tune the upstream service options for hardware-specific requirements. CPU policy
validation and sleep ordering belong beside the module implementation. Avoid
applying all powertop recommendations as permanent policy without measuring their
latency, wakeup and device effects.

Inspect `tlp-stat`, `powerprofilesctl`, `upower -d` and the TLP/logind journal.
Compare repeated battery energy measurements under a controlled workload; device
activity percentages or a single short sample do not establish whole-system
power consumption. Temporary audit captures do not belong in declarative policy.
