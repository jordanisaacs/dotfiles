# YubiKey button output

`ykman` is provided with the user GnuPG tools. To disable touch-generated USB OTP
text without deleting credential slots or changing NFC configuration, use:

```console
ykman config usb --disable OTP
```

This device setting persists across computers. Inspect `ykman info` and restore
it with `ykman config usb --enable OTP` when needed. FIDO/CCID settings are
separate; consult `ykman config usb --help` before changing interfaces.
