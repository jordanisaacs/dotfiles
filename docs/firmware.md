# Firmware updates

The system enables native fwupd. Inspect supported devices and release metadata
with `fwupdmgr get-devices`, `fwupdmgr refresh` and `fwupdmgr get-updates`.
Review the device's upgrade prerequisites before `fwupdmgr update`; firmware
changes are separate from switching a NixOS generation and may require reboot.

Keep reliable power and a recovery path appropriate to the device. A NixOS
rollback does not roll back firmware. Version-specific vendor restrictions belong
in a separately reviewed update operation, not permanent module defaults.
