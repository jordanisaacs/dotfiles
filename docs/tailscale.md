# Tailscale integration

The system module owns tailscaled; the user tray uses the local daemon API.
Granting user access must be explicit and does not turn a graphical tray into an
administrative identity. Ordinary application access should follow Tailnet ACLs.

Tailnet IPv6 connectivity and public Internet IPv6 are different paths. Inspect
`tailscale status`, `tailscale netcheck`, routes and router prefix delegation
before attributing an unreachable public IPv6 host to Tailnet policy. Public
IPv6-only services need a usable upstream IPv6 route or a deliberately chosen
proxy; enabling IPv6 locally does not create one.

Tailnet Lock signing keys and device node keys have different roles. Review
`tailscale lock status` and CLI help before signing or removing a key. Match the
actual device identity; hostnames alone can be ambiguous. Keep recovery/signing
authority distinct from routine service credentials.

The rsync.net [controller guide](../backups/rsync-net/README.md) documents its
separate userspace-networking plan and native Headscale/Tailscale ACL regressions.
