# Audio controls

Home Manager owns pasystray and passes its native `--volume-max=100`, with an XDG
autostart override preventing an additional uncapped instance. Hardware keys and
bar actions use `stools vol`, whose ordinary upward adjustments also stop at 100%.

Explicit commands such as `stools vol set 120` or `stools vol up 5 150` remain
intentional amplification overrides. These are control defaults, not a PipeWire
access boundary or a physical loudness guarantee. Downward adjustments preserve
channel balance and mute state; other applications can still request gain.

`audio-volume` tests the actual tray's StatusNotifierItem scroll interface, XDG
autostart behavior and CLI against a private PipeWire null sink. Its negative
control removes only the native maximum argument. No host audio device is used.
