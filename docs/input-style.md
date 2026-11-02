# Input profiles

`jd.inputStyle = "win" | "mac"` chooses shortcut conventions independently of
`jd.keybindings = "emacs" | "vim"`. System preferences are inherited by Home
Manager and can be overridden per user. Natural scrolling applies to both.
Touchpad behavior is configured through `jd.graphical.wayland.touchpad`; native
`clickfinger` supports two-finger physical right-click and tap-to-click.

Mac uses Super as Command and Alt as Option. Terminal Control editing remains
available. `keyboard.macWmModifier` selects the separate window-management
modifier, defaulting to Super+Alt; its option documents collision constraints.
The compositor's `river.controlClick` supplies native Control-click right-click.

| Mac shortcut | Action |
| --- | --- |
| Command+Space | Launcher |
| Command+Tab / Shift+Tab | Next / previous window |
| Command+Control+F | Fullscreen |
| Command+Shift+Q | Confirmed graceful logout |
| Command+Shift+3 / 4 | Capture display / region |
| WM+Space | Floating toggle |
| WM+Shift+Return | Terminal |
| WM+V / Shift+V | Clipboard / notifications |

Firefox and Ghostty use native accelerators. GTK3 editing bindings and positively
identified GUI apps receive scoped policies inspired by Toshy; unknown apps pass
through. Window cycling follows the active manager's window order.
Reload affected apps after changing profiles;
startup-only compositor settings require a new graphical session.

The system capability `jd.graphical.inputRemapping.enable` and its `users` list
must authorize Mac remapping before a user enables it. A dedicated nonroot
backend owns input/uinput access; the user only reaches its bridge socket.
Policies and session guards live in the system module and patched package.
Home Manager cannot grant those device permissions.

Regression checks exercise the actual generated GTK/Ghostty settings, native
River/Oxbow/Reka bindings, logind/lock transitions and scoped remapper behavior:
`input-style-gtk`, `input-style-session`, `input-style-reka`, `xremap-session`,
`uinput-acl` and `input-style-control-click`. Hardware layout preferences remain separate
from automated VM coverage.
