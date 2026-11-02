# Fingerprint login and encrypted keyrings

`jd.greetd.bootKeyringUsers` opts named users into loading a cached boot-unlock
passphrase through native `pam_systemd_loadkey` and `pam_gnome_keyring`. The
login-keyring password must match a passphrase typed during encrypted boot.
Fingerprint authentication authenticates the user; it does not supply that secret.

The default empty list leaves this integration disabled. Native password login
remains available when no suitable cached passphrase exists. Token-only unlock,
an expired cache or differing passwords cannot automatically unlock the keyring.
The integration also works with systemd-cryptsetup when password caching is
available; it does not change disk credentials or enroll encryption tokens.

The module keeps account/session checks and restricts cache loading to listed
normal users. PAM ordering and greetd keyring visibility are asserted beside the
configuration. Avoid introducing a plaintext password file or a parallel daemon.

`boot-keyring-unlock` tests actual PAM/keyring behavior with fixture credentials;
`login-greeter-keyring` exercises greeter initialization. Encrypted-initrd checks cover
the independent storage-unlock path. All run in disposable NixOS VMs.
See [encrypted storage](encrypted-storage-migration.md) before changing disks.
