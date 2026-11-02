# rsync.net controller

Typed Nix policy describes accounts, device public keys, ZFS datasets and SSH
service access. The Python controller inspects an existing provider and
reconstructs a bounded subset through administrative SSH. It is not a FreeBSD
NixOS module or a complete backup deployment tool.

## Configuration

`default.nix` evaluates `module.nix` and returns `config`, `options`, `manifest`
and `cli`. The flake exports `lib.rsyncNet`, `lib.rsyncNetModule`, the `rsync-net`
app/package and `rsync-net-manifest`. Option descriptions are the field reference.

`framework.nix` is a policy constructor: import it with
`{ identifiers = secrets.dotfiles.rsyncNet; }` and pass its result in `modules`.
The public policy keeps service capabilities, quotas and retention schedules.
Account names, endpoint trust, pool identifiers and device enrollments come from
the private flake input. `example-identifiers.nix` supplies synthetic values for
the isolated regression checks; it is not a live deployment configuration.

- `connection`: administrative SSH endpoint and trusted host identity.
- `mode`: `public` uses the provider's existing SSH service. `private` is retained
  as an incomplete option and refuses activation.
- `pool` / `datasets`: expected pool GUID, dataset mountpoints, owners and quotas.
- `principals`: numerical identities, backend settings and named device membership.
- `principals.<name>.cache`: signed Nix cache settings for a cache backend.
- `control`: private durable catalog and encrypted recovery-envelope storage.
- `network`: a retained future private-transport candidate; not activated.

Do not place private SSH/GPG keys, repository passwords, Tailscale state or cache
signing secrets in Nix. Keep recovery credentials off the source machine as well.
Missing numerical allocations, storage or trust produce blockers; they are not
inferred from a preferred account name.

## Enroll a device

```console
nix run .#rsync-net -- validate
nix run .#rsync-net -- enroll --principal PRINCIPAL --device DEVICE --key-file /private/local/device-key --output ./enrollment
```

Use `--public-key /path/to/device.pub` when the private key belongs to another
machine. New accounts additionally need `--new-account`, `--backend`, `--uid`,
`--gid`, `--dataset` and `--quota-bytes`; Restic backends select `--purpose user`
or `service`, and Git enrollment requires `--gpg-fingerprint`.

Enrollment declarations contain public keys and identifying metadata. Import
the generated `enrollment.nix` through private policy inputs. Enrollment never
contacts the provider. Generated private keys stay source-local;
repeated enrollment verifies rather than replaces them. A later failure can
leave a new private key available for retry; use a fresh review directory when
changing policy.

## Local clients

Import the flake's `homeManagerModules.rsync-net-client` for user configuration.
The `jd.rsyncNetClient` options consume public server policy modules, pinned host
trust and named device bindings. Public SSH host/port inherit from server policy
unless explicitly overridden. They generate
upstream SSH settings, public key references, selected Restic user backups and
Git host identity/recipient policy. Repositories add their own remotes on demand.
Option descriptions are in
[`client/home-manager.nix`](client/home-manager.nix) and
[`client/options.nix`](client/options.nix).

A Documents backup can select GNOME Keyring through `passwordCommand`.
Its item has public lookup attributes `application=rsync-net`,
`host=storage.example.invalid`, and `backup=documents`. Restic reads the password from
`secret-tool lookup` over a pipe; no plaintext password file is created. The
login keyring must be available and unlocked in the user's D-Bus session. A
locked keyring can prompt for unlocking; a missing item fails the backup.
Software running as the logged-in user can still request the unlocked secret.
A client can enable `backups.documents`, selecting only `~/Documents`.
An hourly persistent timer catches up missed runs when the user session is
available. Enabling
`createWrapper` installs upstream `restic-rsync-net-documents` for explicit repository
initialization, inspection and restore using the same transport and keyring.

To import an existing repository password, run this interactively; the password
prompt does not echo and the password is not a command argument:

```console
secret-tool store --collection=default --label='Restic: rsync.net Documents' application rsync-net host storage.example.invalid backup documents
```

For a new repository, generate its password directly into the keyring once,
without writing a file or printing it. Preserve the same item on retries; never
replace an initialized repository's password with a new random value. The
keyring uses encrypted local storage; keep the independent recovery envelope
and recovery private key available after loss of this machine.

Private identity and password files are runtime paths, never Nix inputs.
Provision keys with enrollment, import its public declaration into server policy,
and persist local credentials separately. Public key references may use files
managed by Nix/Home Manager. Client jobs never initialize or prune repositories;
timers are explicit. Importing the module alone enables no jobs.

Use `nixosModules.rsync-net-client` for service backups and Nix-daemon caches.
It uses upstream `services.restic` with independent service credentials, and
requires a separately enrolled read-only cache device with public signing trust.
The daemon reads its own root-accessible runtime key; it cannot use desktop SSH
aliases or a user's agent for authentication. Both modules are imported by this
repository's normal system/user module sets and remain disabled by default.

## Inspect and reconstruct

```console
nix run .#rsync-net -- inspect --admin-identity /private/admin-key > state.json
nix run .#rsync-net -- plan --state state.json
nix run .#rsync-net -- bootstrap --admin-identity /private/admin-key > review.json
nix run .#rsync-net -- bootstrap --admin-identity /private/admin-key --review review.json --apply
```

`--admin-agent-public-key` explicitly selects an agent-backed administrative
identity instead. Existing host trust is required. A saved review must still
match fresh local and remote state before writes. An alternate JSON manifest
uses `--manifest FILE` before the subcommand. Exit codes: 0 valid, 1 blockers,
2 invalid input or failed operation; `deploymentReady=false` remains explicit.

Bootstrap can create missing declared users/groups with disabled passwords,
root-owned homes and restricted account `authorized_keys` files.
Use `bootstrap --principal NAME` to review/apply just one declared account and
its dataset boundary. Unrelated active clients are outside that scope; active
sessions for the selected principal still block account changes. Omitting the
option retains the full-policy scope. Review and apply must use the same scope.
It checks native sshd syntax and refuses identity collisions, unsafe public SSH
policy, missing packages/storage, ownership/quota drift and delegated ZFS rights.
Public mode accepts the provider's keyboard-interactive/PAM authentication setting.
Key-level forced commands apply to SSH-key authentication; managed account
passwords must remain disabled.
Existing managed keys cannot disappear through enrollment-only reconstruction.
Restic accounts receive a root-owned `.rclone.conf` declaring the local
`repository` backend. Their fixed command selects that file explicitly and binds
the same append-only dataset path. Bootstrap can migrate only the exact former
command with the same enrolled keys and dataset; other key/command changes are
still refused. Unmanaged existing backend configuration is never overwritten.
It preserves administrative/provider keys, public sshd, host keys, boot files,
storage and retention. Failed operations may leave safe partial reconstruction;
inspect and review again. An unchanged second run should perform no writes.

Initial server setup is separate from adding backup configurations. For an
explicitly approved FreeBSD release, enable `setup` and select `setup.backends`
to install server capabilities independently of enrolled principals:

```console
nix run .#rsync-net -- setup --admin-identity /private/admin-key --known-hosts /private/known-hosts > setup-review.json
nix run .#rsync-net -- setup --admin-identity /private/admin-key --known-hosts /private/known-hosts --review setup-review.json --apply
```

Setup works before Python is installed and uses the provider's existing trusted
package repositories. It never creates backup accounts or publishes device keys.
Later `bootstrap` independently inspects the resulting identities before
publishing any account authorization.
Each command that contacts the provider uses one short-lived authenticated
administrative SSH connection, reused for its remote operations and closed when
the command exits.
Review and apply authenticate separately. With Python available, setup runs a
server-side Python script; a fresh server uses native prerequisite probes over
the same connection. Progress phases go to stderr and native server syslog,
leaving stdout available for JSON reviews.
Public mode adds no listener or persistent service. It stops/disables only an
exactly recognized legacy managed inetd setup, retaining its files; unrelated
provider services are untouched. Partial progress remains after failure; inspect
and create a fresh review before retrying. Nix cache activation requires Nix
2.35.3 or newer. OS upgrades remain separate operations.

## Provision storage through the CLI

After host setup, provision shared control storage once. Set `control.dataset`,
`control.path`, and `control.quotaBytes` explicitly in public policy:

```console
nix run .#rsync-net -- storage init --control --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts > control-storage-review.json
nix run .#rsync-net -- storage init --control --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts --review control-storage-review.json --apply
```

For each new backup, enroll its device, import the public declaration, then
provision only that principal's dataset and bootstrap its restricted account:

```console
nix run .#rsync-net -- storage init --principal PRINCIPAL --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts > backup-storage-review.json
nix run .#rsync-net -- storage init --principal PRINCIPAL --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts --review backup-storage-review.json --apply
nix run .#rsync-net -- bootstrap --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts > bootstrap-review.json
nix run .#rsync-net -- bootstrap --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts --review bootstrap-review.json --apply
```

`--admin-agent-public-key` explicitly selects the GPG card's SSH authentication
subkey through the agent; its private key stays on the hardware. Provisioning
creates only the selected missing filesystem and required missing parents on an
existing pool with the pinned GUID. Mountpoints must follow the mounted pool's
hierarchy. New parent filesystems are root-owned 0755; backup/control roots are
0700 with their declared numeric ownership and snapshot-inclusive quotas.
Quotas reserve no space. Sharing and ZFS delegation are not enabled.

Apply rechecks the saved review, host trust, mount sources, path control, ACLs,
identity allocations and delegation. Existing directories are never mounted over;
existing filesystems are never adopted, recursively chowned, resized or deleted.
A failed run retains any created filesystems for inspection and a fresh review.
Pool creation, one-time legacy cleanup and OS upgrades remain outside this CLI.

After activating the local Home Manager configuration, finish each backup using
its generated descriptor. Repository initialization and signed recovery escrow
are one reviewed setup operation; routine backup jobs never perform either:

```console
nix run .#rsync-net -- backup setup --config ~/.config/rsync-net/backups/documents.json --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts > backup-setup-review.json
nix run .#rsync-net -- backup setup --config ~/.config/rsync-net/backups/documents.json --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts --review backup-setup-review.json --apply
systemctl --user start restic-backups-rsync-net-documents.service
```

The descriptor contains public policy, native backend arguments, selected source
directories and runtime credential references. It contains no password or private
key. Setup refuses mismatched server policy, stale configuration/trust, unfinished
storage or account bootstrap. It never initializes a nonempty unrecognized
repository. Recovery is required: setup reports completion only after preparing
or verifying the hardware-signed encrypted bundle, publishing it to control, and
reading back matching ciphertext and metadata. Interrupted operations retain the
repository and recovery artifacts for a fresh review; retries reuse a complete
bundle. Each review/apply invocation shares one hardware-authenticated SSH
connection across its administrative phases. Restore verification remains a
separate explicit check, never inferred from successful escrow publication.

The local backup configuration accepts multiple absolute `paths` and multiple
`xdgDirectories` in one job. Select the intended directories explicitly and
verify restoration independently of backup creation.

## Storage and access boundaries

Use separate datasets and identities for each user/service backup principal.
Routine Restic credentials force append-only repository access; maintenance and
retention require separate administrative authority. ZFS quotas and snapshots
are server-side boundaries, distinct from client-side repository encryption.
Provider refreshes require reconstructing OS accounts/configuration against the
preserved pool; stable numeric IDs and durable secret state matter.

An illustrative storage hierarchy is:

```text
POOL/
  backups/user/<machine-user>
  backups/service/<workload>
  git/<principal>
  cache/<principal>
  control/backups/catalog.json
  control/backups/recovery/<principal>.asc
```

Each backup leaf is an independent repository and isolation boundary. A Git
principal owns a shared encrypted namespace containing repository directories;
devices join that principal using their own SSH/GPG identities. The control
catalog and encrypted recovery envelopes are administered separately and must
be inaccessible to routine storage users. This hierarchy is an example, not an
allocation or a provisioning operation.

Git backends use git-remote-gcrypt with source-held GPG keys and device-specific
SSH authentication. Devices can have read/write or read-only access within a
principal; GPG fingerprints declare decryption membership separately from SSH
write permissions. **Serialize writers**: gcrypt pack-list updates do not provide
concurrent hosting. Cache upload keys are separate from backup
and Git credentials; clients verify Nix signatures independently of transport.
Named cache principals use the same ownership/device-enrollment model. A fixed
`nix-store --serve` command exposes a static file cache over SSH; writer keys can
upload and read, while reader keys cannot upload. The server needs Nix commands,
but no persistent Nix daemon. Clients must trust the configured signing keys.
Uploader keys retain `--write` for native `nix copy --to ssh://…` imports. The
fixed file-cache store cannot build, and remote builders are explicitly disabled.

Public mode shares the existing SSH listener while separating administrative and
routine keys/accounts. Every routine key has a restricted fixed backend command.
Private mode, including future Tailnet transport, remains incomplete; its retained
inetd configuration is inactive. Account-only `bootstrap` never installs packages
or manages services; reviewed `setup` handles host prerequisites and legacy-service
disablement. Reviewed `storage init` creates declared missing filesystems. No
controller operation destroys pools or datasets. Snapshot expiry is scoped to
the explicitly declared dataset and schedule prefixes below.

## Dataset snapshot schedules

Server prerequisites and dataset policy are separate: `rsyncNet.setup.snapshotting = true`
adds the native FreeBSD `zfsnap2` package to reviewed `rsync-net setup`.
`rsyncNet.snapshotSchedules` supplies shared defaults for all backup, Git, and
binary cache datasets. `rsyncNet.datasets.<name>.snapshots` can replace those
defaults for a specific dataset, or explicitly use `{}` to opt out. Both use
the same typed schedules and CLI; retention is independent of storage backend:

```nix
snapshotSchedules = {
  hourly = { schedule = "15 * * * *"; retention = "48h"; };
  daily = { schedule = "20 0 * * *"; retention = "30d"; };
  weekly = { schedule = "25 0 * * 0"; retention = "12w"; };
  monthly = { schedule = "30 0 1 * *"; retention = "1y"; };
  yearly = { schedule = "35 0 1 1 *"; retention = "forever"; };
};
```

Schedules use five numeric cron fields in the server's local time. Retention
uses native zfsnap2 TTLs; `forever` never expires. The shared policy applies
these tiers to user-backup and Git datasets within their snapshot-inclusive
quotas (1 TiB and 256 GiB respectively). Future binary cache
datasets inherit the same defaults without enabling or creating a cache host.
Restic's client timer is configured separately in `backups.documents.timerConfig`.

After reviewed server setup, apply the declared schedules through the CLI:

```console
rsync-net snapshots configure --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts > snapshots-review.json
rsync-net snapshots configure --admin-agent-public-key ~/.ssh/id_ed25519.pub --known-hosts ~/.ssh/known_hosts --review snapshots-review.json --apply
```

Review binds the policy, pool, mounted dataset, ownership, quota, native tool,
existing managed file and SSH trust. Apply repeats native dry-runs, installs a
root-owned `/etc/cron.d/rsync-net-snapshots`, verifies its contents, and updates
the control catalog and its verified control-dataset snapshot. Cron reloads it
automatically. Configuration creates or deletes no repository snapshots;
scheduled jobs invoke native zfsnap2 non-recursively
on each explicit dataset. Expiry runs at minute 55 of each hour, filtering each
exact declared `rsync-net-<name>-` prefix and respecting the embedded TTL.
Unrelated snapshots are outside that scope. An empty `snapshots = { };` stops
that dataset's scheduling and expiry without deleting existing snapshots.
Removing a tier also stops its expiry; retention edits affect newly created
snapshots, while existing snapshots keep their embedded TTLs.

## Shared encrypted Git hosts

Private enrollment modules declare each Git account, dataset and device's public
SSH/GPG identities. Keep those modules and public certificates in the private
configuration repository. Private SSH keys remain at their declared runtime
paths. Home Manager provides a host-scoped SSH alias and native Git
encryption/rsync tools; it does not select repository directories or create
remotes. Native Git `includeIf hasconfig:remote.*.url` selects recipient/signing
policy only when a repository has a matching remote URL. Add remotes on demand,
substituting the private principal and generated binding alias:

```console
git remote add backup gcrypt::rsync://GIT_PRINCIPAL@rsync-net-GIT_BINDING/REPOSITORY
```
Routine transport is forced through dataset-scoped `rrsync`; Git contents are
encrypted by git-remote-gcrypt before upload. Hardware GPG membership and the
global recovery recipient are carried in public policy, independently of the
device SSH key and the hardware key used for administration.

Each machine uses its own software GPG signing/encryption identity; the hardware
key is a separate recovery recipient. Enable Home Manager `gitIdentity` with a
device name, private runtime GPG home, and native keyring lookup/store argv.
Home Manager emits `~/.config/rsync-net/git-identity.json`. Run:

```console
rsync-net git setup --config ~/.config/rsync-net/git-identity.json
```

Setup generates a random passphrase directly into the keyring, creates an
encrypted Ed25519/CV25519 machine identity, imports only recovery **public**
certificates, tests local signing and emits a public `enrollment.nix`. Import
that module into the private enrollment configuration and activate Home Manager
again. Retrying reuses the same key; an existing key with a missing password fails without
regenerating either. Private key material stays in the runtime machine GPG home.
Only matching Git host URLs select the machine GPG adapter; the user's
normal hardware GPG configuration remains separate. The adapter reads the
keyring passphrase through a pipe and preserves gcrypt's independent pack
password/status file descriptors. Never copy a machine private key into a
recovery test: use the hardware identity and public member certificates only.
The default named-recipient mode (`gitIdentity.publishParticipants = true`)
exposes recipient key IDs, while keeping content encrypted. This avoids the
GnuPG 2.4 failure observed with independent hidden ECDH machine/recovery keys.

## Recovery

Recovery recipients are configurable globally and per encrypted principal. Git
writers include them in each repository's participant policy. Restic setup adds
an independent random recovery password and signs/encrypts its bound recovery
payload with native GPG. Initial setup needs a trusted signing key; routine
backups use their own machine password. Private keys and plaintext passwords
never go to control storage.

Normal per-backup setup provisions and publishes recovery through `backup setup`
as described above. The lower-level commands remain available for explicit
recovery administration of an initialized repository:

```console
rsync-net recovery prepare --principal PRINCIPAL --repository REPOSITORY --password-file /private/machine-password --output ./recovery-bundle
rsync-net control backup --principal PRINCIPAL --bundle ./recovery-bundle --admin-identity /private/admin-key > control-review.json
rsync-net control backup --principal PRINCIPAL --bundle ./recovery-bundle --admin-identity /private/admin-key --review control-review.json --apply
```

For a keyring-backed machine password, replace `--password-file` with
`--password-command 'secret-tool lookup application rsync-net host storage.example.invalid backup documents'`.
Select exactly one password source. The command contains only the lookup, never
the secret; Restic invokes it directly and recovery errors withhold tool output.

`control.path` must already be a dedicated mounted root-only ZFS dataset. The
catalog backs up public policy and observed repository IDs; recovery files are
ciphertext. Publication never overwrites an existing envelope. Interrupted setup
preserves a pending bundle and refuses silent regeneration. Key rotation needs
separate review.

Every control publication now ensures a non-recursive native ZFS snapshot of
the **control dataset** after durable catalog/envelope writes. Snapshot names
are `rsync-net-control-<catalog SHA-256>` and are retained indefinitely within
the control quota. The CLI verifies the frozen catalog and every referenced
recovery file before reporting success. Repeated publication of identical state
reuses its verified snapshot; a failed snapshot leaves published files intact
and a fresh review can finish it without rewriting credentials. The same path
covers explicit `control backup`, integrated backup setup and schedule changes
that update the catalog. These snapshots are separate from repository schedules.

After authorizing a replacement device, fetch and restore without the original
machine password:

```console
rsync-net control fetch --principal PRINCIPAL --admin-identity /private/admin-key --output ./recovery-bundle
rsync-net recovery restore --principal PRINCIPAL --repository REPOSITORY --bundle ./recovery-bundle --target ./restored
```

Restore verifies the GPG signer against independently trusted recipient policy,
the signed principal/dataset/repository binding, and the actual Restic repository.
It uses a new or empty private target. Keep public certificates, trusted policy
and independent recovery key material available without the source machine or
provider. Public declarations and successful preparation are not a tested restore.

## Regression checks

The Python package lives in `src/rsync_net`, including its packaged resources.
The `rsync-net` console command and `python -m rsync_net` use the same entrypoint.
For development:

```console
nix develop .#rsync-net
cd backups/rsync-net
uv sync --locked
uv run pytest
ruff check .
```

Nix packages the same project and runs pytest during the build. The Nix app
supplies an immutable public default manifest; uv accepts `--manifest FILE`.

All tests live in `tests/`. Run selected flake checks with
`nix build .#checks.x86_64-linux.NAME`:

- `rsync-net`: typed policy, key enrollment, review and controller unit regressions.
- `rsync-net-integration`: a pinned official FreeBSD server and Linux client,
  native package/account/service setup, encrypted Git, append-only Restic and
  recovery after replacing the OS disk while preserving a separate ZFS disk.
- `rsync-net-client-home`: generated Home Manager SSH, Git and Restic settings,
  native configuration parsing and public-key enrollment from the Nix store.
- `rsync-net-client-system`: native system SSH, service backup units and signed
  Nix-daemon cache configuration with independent runtime credentials.
- `rsync-net-network-module`: network plan constraints and rendering.
- `nix-cache`: production SSH commands, Nix signatures, corrupt archive rejection
  and read-only boundaries.

The FreeBSD check tests native platform behavior; simulated OS replacement
cannot prove a provider's upgrade contract. Tests never connect to the real
appliance or use host disks.
