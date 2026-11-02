# Clipboard history

The native Home Manager wl-paste watchers record text/images with Cliphist. The
shared Fuzzel picker supports selection, Shift+Delete for one entry and
Control+Shift+Delete for confirmed clearing; launcher actions expose the same
operations. Desktop shortcut conventions follow the selected input profile.

`jd.graphical.wayland.clipboard.persistent` retains encrypted history using the
login keyring. History is available only while that keyring and the graphical
session are active; a locked or missing key never creates a plaintext fallback.
The option description documents storage and recovery requirements.

A password-protected default keyring must already exist. Fingerprint auth alone
does not supply its password. Back up the encrypted vault and encrypted keyring
together; do not reset the vault's keyring item while retaining its ciphertext.
Same-user applications can read history while unlocked. Sensitive clipboard hints
are honored only when the source app supplies them; remove unintended secrets.

Disabling persistence uses session-owned runtime history without deleting an old
vault. `clipboard-history` verifies the actual Home Manager service with native
GNOME keyring, FUSE/gocryptfs and synthetic text/image data in a disposable VM.
