# River desktop

`jd.graphical.wayland` owns the user desktop; system modules own the greeter,
authentication, device permissions and multi-user capabilities. River runs under
UWSM, with session services tied to `graphical-session.target`. Launch applications
through the provided launcher/UWSM path so systemd tracks their lifecycle.

Set `river.windowManager` to choose the default manager. The greeter's session
selection and the default are separate from runtime switching:

```console
river-wm status
river-wm oxbow
river-wm reka
river-wm toggle
```

The Switch Window Manager desktop entry uses the same selector. Mutually
conflicting user units perform the handoff without closing applications. ReKa
uses a dedicated clean Emacs process; enabling a custom Emacs environment is a
separate choice. Read the manager modules for their generated bindings.

Shared font, scale, surface colors and spacing feed the launcher and Waybar;
use those configuration options instead of per-application pixel overrides.
Waybar provides tray menus, notification/clipboard entry points and audio/network
controls. The idle inhibitor's active state remains visible outside details.

For session faults inspect `journalctl --user -b`, the two `river-wm-*.service`
units and the UWSM compositor unit. Regression checks exercise actual manager
handoff, click focus, keyboard delivery and VT/logind lifecycle; health-protocol
experiments are opt-in rather than evidence that every app is unresponsive.
See [graceful logout](graceful-logout.md) for close/save handling.
