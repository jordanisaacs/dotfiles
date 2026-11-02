# Activity monitoring

Mission Center is configured through the user applications module and launched
through UWSM. Its packaged cgroup discovery supports nested systemd app slices,
escaped desktop IDs and multiple instances; process visibility remains subject
to normal kernel permissions. btop remains useful for terminal process views.

`jd.graphical.activityMonitor` grants optional network/CPU metrics to explicitly
allowed users. Its options describe the capabilities and fresh-session requirement.
Home Manager recognizes declarative setup for those users; use system policy
rather than the application's imperative root setup script.

`mission-center-apps` tests actual cgroup discovery. `activity-monitor-metrics`
uses native helpers, real synthetic VM traffic and a test-only kernel powercap
device to verify the production permission rules without exposing host metrics.
