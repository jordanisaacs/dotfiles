# Notification center

Home Manager's native SwayNotificationCenter service groups notifications and
retains history while running. Quiet mode suppresses popups while keeping center
entries; history is not persisted across logout.

The bar icon opens the center and right-click toggles quiet mode. Launcher and
keyboard actions use the same service; shortcuts follow the input profile.
The bar consumes native event subscriptions and shared typography/surface colors.

Only one service may own `org.freedesktop.Notifications`. The module masks the
replaced Mako unit as well as managing the new service; existing daemon history
cannot be transferred. `notification-center` tests generated styling, native
handoff, quiet-mode events, panel/history actions and session teardown with
synthetic notifications in a disposable VM.
