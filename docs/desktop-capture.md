# Desktop capture

The multimedia configuration installs Kooha with its native desktop entry and
application-local experimental features. It starts on demand through UWSM.
Flameshot uses Home Manager's native service for annotated screenshots.

Kooha's **Capture a Monitor or Window** mode opens the portal chooser after
Record. Select a `Window: …` row for isolated window capture; region mode selects
a screen rectangle. Refresh a remembered source to reopen selection. Window
availability depends on the active portal/compositor, not a separate Kooha button.

`xdg-desktop-portal-wlr` handles screencasting; portal configuration belongs in
the desktop module. Package patches and their compatibility constraints live
beside the source overlays rather than in this guide.

The `kooha-window-capture` check uses production feature flags, actual portal
selection/cancellation and a moving private VM window, then decodes the recording
to verify dimensions and progress. It does not capture host windows, microphones
or the user's recordings.
