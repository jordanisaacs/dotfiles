# Keep incomplete frames out of the capture stream, and let capture consumers
# negotiate enough buffers for their native pipelines. No renderer overrides.
_final: prev: {
  xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./portal-wlr-incomplete-frame.patch ];
  });
  pipewire-capture = prev.pipewire.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./pipewire-capture-buffer-priority.patch ];
  });
}
