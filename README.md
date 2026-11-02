# Dotfiles

My NixOS dotfile flake for both systems and users. Each system/user is built upon custom modules abstracting NixOS/home-manager. The modules are meant to be easily shareable and should *just work* by taking into account the systemwide configuration. There are modules tailored towards server, desktop, and laptop use.

Note: One of my flake inputs points towards a private git repository of secrets. Thus you will not be able to clone and run this repo without some changes. See the notes on my secrets config below.

## Laptop updates

The active laptop is `framework`. Its desktop uses River with the
`river-window-management-v1` protocol and Oxbow 0.1.1. The old DWM/X11
session, rivercarro layout generator, and classic River configuration are removed.
XWayland remains available for applications.

Home Manager has standard, pure flake targets; it does not read
`/etc/hmsystemdata.json` during evaluation:

```sh
nix run ~/.dotfiles#home-manager -- build --flake ~/.dotfiles#jd@framework
home-manager build --flake ~/.dotfiles#jd@framework
home-manager switch --flake ~/.dotfiles#jd@framework
```

`framework` is the only active NixOS target. `jd` and `jd@framework` select its
Home Manager profile. Unused desktop, laptop, server, deployment and installer
definitions are preserved in [retired/outputs.nix](retired/outputs.nix) for
reference and are not exported by the flake. The old
`homeManagerConfigurations` alias is removed. `sys apply-user` delegates to the
Home Manager CLI using the current username and hostname.

The same Home Manager profile includes Oxbow and Reka. After installing the
updated system and user configurations, log out and back in once to load the
patched River and managed window-manager services. Press F3 in the system
login greeter to choose **River (Reka)** or **River (Oxbow)**. For a recovery
terminal, press F2 and enter `desktop-login --terminal`, or use a normal getty
on another virtual terminal. Tuigreet's desktop-session menu only supports
graphical session types; the F2 route records a correct TTY login session.

The system setting `jd.greetd.defaultWindowManager = "oxbow"` selects the default
login choice; set it to `"reka"` to change that default. The greeter, session
menu, authentication, and shared default remain NixOS configuration. Home
Manager owns each user's window-manager configuration. Direct user session
starts inherit the system default, with an optional user override under
`jd.graphical.wayland.river.windowManager`.

Switch the running session without restarting River or applications:

```console
river-wm reka
river-wm oxbow
river-wm toggle
river-wm status
```

The launcher entry **Switch Window Manager (Reka / Oxbow)** toggles the active
manager, using the same managed switcher as `river-wm toggle`.

Runtime selection lasts for the current login; layouts may be rearranged. A
failed start restores the previous manager. Reka uses a minimal Emacs
window-manager configuration; the custom Emacs editor environment remains
disabled. Super+Shift+q ends the desktop session.

Reka preserves Super+Shift+Return for Ghostty, Super+x for Fuzzel in the Emacs
binding profile, Super+Space for floating, Super+f for fullscreen, and
Super+Shift+c for closing an application. Super+left/right mouse drag moves or
resizes floating windows. Super+1–9 selects Emacs tab workspaces, creating them
when needed; these are not Oxbow's overlapping tags. C-x and M-x operate the
window-manager Emacs. Super+Shift+q ends the session; C-x C-c does not.

Shared keyboard configuration lives under `jd.graphical.wayland.keyboard`.
Caps Lock is an additional Alt key; set `capsLockAsAlt = false` to restore it.
One native XKB definition supplies Oxbow, Sway, and Reka's input daemon. Reka
uses the upstream River channel daemon while its manager service is active for
device hotplug and touchpad preferences, and Kanshi for output scaling. Its
readiness hook acknowledges the manager service after River processes a usable
frame. River's startup process then finalizes UWSM from the compositor service.

The fork is pinned in `flake.lock`. Its native keyboard/floating tests and the
dotfiles' `reka-session`, `desktop-keyboard`, and `river-input` checks cover the
protocol features, complete UWSM login/logout, keymap, and input rules.

```sh
cd ~/.dotfiles
nix build --no-link .#checks.x86_64-linux.framework .#checks.x86_64-linux.home-framework
sudo -A nixos-rebuild boot --flake .#framework
```

For this migration, reboot after preparing the boot generation, open the
recovery terminal from greetd with F2, and activate Home Manager before opening the new
desktop:

```sh
nix run ~/.dotfiles#home-manager -- switch -b before-modernization --flake ~/.dotfiles#jd@framework
~/.nix-profile/bin/codex --version
```

Home Manager backs up the manually edited `.bashrc` and restores its managed
version. Once the Nix profile's Codex works, remove the temporary
`~/.local/bin/codex` symlink, then exit the terminal session and select Wayland.
The current pinned Codex package is 0.165.0; the temporary installer supplied
0.166.0. Account settings and credentials remain outside Nix management.

Keep `system.stateVersion` and `home.stateVersion` unchanged when updating
inputs; these are data compatibility settings. Future updates use
`nix flake update nixpkgs home-manager` followed by the checks. Nix itself follows `nixVersions.latest` from the locked nixpkgs input.
Legacy channels are disabled and `nixpkgs` in the registry and `NIX_PATH` refers
to this same locked input. Signed binary caches are configured for cache.nixos.org,
nix-community, nixpkgs-wayland, and the existing eigenvalue cache; build sandboxing and signature
verification stay enabled, and only root is a trusted Nix daemon user.

The user and system share `jd.keybindings`, which defaults to `"emacs"`.
Selecting `"vim"` retains the alternative bindings. Emacs mode uses
Super+n/p for next/previous window, Super+x for the application launcher,
and, in Oxbow, Super+Ctrl+b/f for the master ratio. Vim mode uses Super+j/k,
Super+p, and Super+h/l respectively. Oxbow uses Super+Shift+Return for Ghostty,
Super+1–9 for tags, Super+Shift+1–9 to move windows, Super+m for monocle,
Super+t for tiling, and Super+Shift+q to log out. Add Shift to the focus
bindings to reorder windows. The preference also configures Readline, Zsh,
tmux, and GTK3 editing; applications with their own shortcuts retain those.

Oxbow's screen-edge padding is controlled by
`jd.graphical.wayland.river.gaps.outer`; this laptop sets it to zero while
preserving the upstream gap between tiles. Oxbow still reserves half that
inner gap at the edges, giving a small inset rather than the large stock margin.

UWSM owns the Wayland session through upstream systemd user units and D-Bus
broker. The Python `.winitrc` entry passes Home Manager's environment to
`uwsm start`; Oxbow signals readiness using `uwsm finalize` after configuration.
Desktop services follow `graphical-session.target`. Fuzzel launches applications
and the terminal shortcut launches Ghostty through `uwsm app -t service`, giving
applications their own cgroups and journal logs. Waybar uses the session slice;
the wallpaper uses the background slice. Logout uses `uwsm stop`, which stops
session applications and cleans up the activation environment. Useful tools:

```sh
systemctl --user status
systemd-cgls --user-unit app-graphical.slice
journalctl --user -b
uwsm app -t service -- firefox.desktop
uwsm stop
```

Laptop power and performance use TLP with its `tlp-pd` profile API, UPower,
and thermald. AC selects performance, battery selects balanced, and power-saver
is available through `powerprofilesctl` or Waybar. Turbo remains available;
there are no fixed CPU/GPU frequency caps. Auto-cpufreq and competing profile
daemons are disabled. UPower hibernates at 5% battery; logind handles the lid
and suspend-then-hibernate. Idle detection starts after ten minutes and logind
waits another fifteen minutes before its idle action. wluma discovers supported
ambient-light sensors and backlights automatically and learns from manual
brightness changes; it cleanly exits when supported hardware is absent.

Ordinary CLI tools remain system packages. Home Manager uses upstream program
modules for Ghostty, gh, Codex, Claude Code, Chromium, Thunderbird, and uv.
Custom Emacs configuration is disabled for now in favor of stock pgtk Emacs.

GUI typography is controlled by Home Manager's `gtk.font` setting. Qt derives
its KDE fonts from it, and Waybar converts points to CSS pixels. GTK has no
additional text-scaling multiplier. Ghostty keeps its preferred terminal font
size, while Fuzzel uses physical-DPI font sizing explicitly so connecting a
scaled monitor does not change its font-sizing mode. Qt uses native KDE platform
integration with matching dark colors and opaque Kvantum windows.
Normal controls use Noto Sans. Fontconfig's separate monospace role selects
Berkeley Mono for terminals, the launcher, and KDE's fixed-width font; those
applications reference the role instead of inheriting the GUI family.

Laptop output scaling is declared once in
`jd.graphical.wayland.display.internalScale` (default `1.25`), with panel
selection in `display.internalOutput` (default `eDP-1`). Native Kanshi follows
the graphical systemd session and applies that policy with any number of
external displays; their mode, position, scale and enabled state are retained.
This scales entire application interfaces, including browser controls, rather
than adding a toolkit text multiplier. The GTK/Qt base remains 15 points:
`15 × 96/72 × 1.25 = 25` physical pixels. Waybar uses equivalent CSS pixels.
`jd.graphical.wayland.terminal.preferredFontSize` expresses the terminal's
preferred points at 100% scale (default 20); Ghostty's configured points divide
by the internal scale, preserving about 27 physical pixels on that panel.
Fuzzel retains its independent 12-point physical-DPI policy. Terminal sizing is
calibrated for the internal panel; its physical size on another display follows
that display's scale. Native per-output scaling also depends on application
support; older Xwayland applications may have different rendering behavior.

Laptop touchpad scrolling defaults to half distance through
`jd.graphical.wayland.touchpad.scrollFactor`; mouse wheels retain their defaults.

Firefox uses native vertical tabs with an icon rail that expands on hover,
the built-in dark theme, and Mozilla's supported policies to block
built-in AI, telemetry, studies, sponsored suggestions and experiments. HTTPS-only,
Global Privacy Control and standard tracking protection are enabled. The locked
NUR catalog supplies extension versions; Nix updates those extensions, while
manually installed extensions retain their ordinary update mechanism. Existing
profile/account/bookmark data is preserved, including Cookie AutoDelete storage.

Wi-Fi authentication uses wpa_supplicant with the Qt6 `wpa_gui` interface;
`systemd-networkd` owns DHCP/routes and `systemd-resolved` owns DNS.
`networkctl`, `resolvectl`, `wpa_cli`, and `wpa_gui` are the management tools.
The built-in adapter has a systemd `.link` matching its permanent MAC and naming
it `wifi0`; supplicant, networkd, Waybar, and the Wi-Fi Settings launcher share
that name. The laptop disables network-online waiting so login works offline.
A root oneshot imports supported saved iwd personal/open networks before the
first supplicant start. It preserves `/var/lib/iwd` and any existing supplicant
configuration, and keeps credentials outside the Nix store in a private file.
Enterprise, encrypted, or unsupported profiles need explicit configuration in
`wpa_gui`; inspect counts with `journalctl -u wifi-profile-migration`.
Wi-Fi is not required for the laptop to reach its boot target.

`nix flake check` builds the laptop system and home, runs Python fixture tests
for Wi-Fi migration, boots a NixOS VM to test the real River/Oxbow session and
application cgroup/logout lifecycle, and rejects NixOS/Home Manager evaluation warnings.
The development shell provides pinned nixfmt, Ruff, Statix and deadnix.
`nix fmt` uses upstream treefmt-nix to format both Nix and Python files. The same
checks run over every Nix/Python source file, including retired references:

```sh
nix fmt
nix develop -c statix check .
nix develop -c deadnix --fail .
nix develop -c ruff check .
nix develop -c ruff format --check .
nix flake check --print-build-logs
```

The fixture, desktop and encrypted-boot tests can also be run independently:

```sh
nix build .#checks.x86_64-linux.wifi-migration
nix build .#checks.x86_64-linux.wifi-boot
nix build .#checks.x86_64-linux.desktop-session
nix build .#checks.x86_64-linux.desktop-theme
nix build .#checks.x86_64-linux.desktop-fonts
nix build .#checks.x86_64-linux.firefox-sidebar
nix build .#checks.x86_64-linux.encrypted-boot
```

Encrypted-boot coverage performs a real UEFI reboot with the laptop's raw
1 MiB `cryptkey` layout unlocking root and swap. Disabling only the readiness
module reproduces the pre-fix hang; the normal check requires a complete boot,
active swap, and stable device readiness after a udev re-probe. The targeted
rule must sort after systemd's unformatted-device rule and is installed in both
initrd and the running system. It changes no LUKS headers or key material.

The Wi-Fi VM imports a public fixture profile, associates with a simulated access
point and acquires a DHCP lease. Omitting the stable link policy reproduces the
missing-interface failure. The desktop VM launches a real application through
Fuzzel and UWSM, checking search paths, runtime socket paths and logout cleanup.
The theme check shows real Wayland widgets after KDE's color-manager startup,
checking text contrast, font size and opacity. The font check uses Ghostty's
effective configuration. Firefox's browser UI test moves the pointer to verify
the icon rail expands and collapses and checks its native pin/unpin behavior.

Wayland SSH and sudo password dialogs use native KDE `ksshaskpass`. Home Manager
exports both `SSH_ASKPASS` and `SUDO_ASKPASS` before UWSM starts; sudo also has an
`/etc/sudo.conf` fallback. Use `sudo -A command` to request the graphical helper.
Sudo's PAM stack tries a fingerprint once for up to five seconds before password
fallback. PAM authenticates these methods sequentially rather than concurrently.

The unused local Firefly III service is disabled on framework. Its data at
`/var/lib/firefly-iii` is intentionally removed by a boot-only tmpfiles rule
while the service stays disabled, as requested. The boot menu uses
systemd-boot’s built-in Shift+O (power off) and Shift+B (reboot) actions.

## Follow Along

Follow along with my NixOS evolution and things I learn along the way: [NixOS Desktop Series](https://jdisaacs.com/series/nixos-desktop/)

## Custom Flakes

I use a variety of custom flakes, but these are the ones I have written myself!

[jdpkgs](https://github.com/jordanisaacs/jdpkgs): A variety of programs that I have packaged and/or created useful wrappers for.

[neovim-flake](https://github.com/jordanisaacs/neovim-flake): A configurable flake for noevim.

[homeage]()

## Dotfile Gems

Some cool excerpts of my dotfiles

### Stateless Encrypted ZFS Server

* Erase your darlings inspired stateless machine utilizing `impermanence` and ZFS snapshots
* Encrypted ZFS pool (and encrypted swap) with initrd SSH support for decryption.
* See *./modules/system/ssh*, *./modules/system/boot*, and *./modules/system/impermanence*

[Erase your darlings - Graham Christensen](https://grahamc.com/blog/erase-your-darlings)

### Desktop Config

* Working GTK/QT theming, icons, and cursors on wayland. See *./modules/users/graphical/shared.nix*.
* Reproducible firefox with plugins. See *./modules/users/graphical/applications/firefox.nix*.
* Greetd login that starts River and Oxbow. See *./modules/users/graphical/wayland/compositor.nix*
* Mounted on login onedrive filesystem using [onedriver](https://github.com/jstaf/onedriver) and a systemd-unit. See *./modules/users/office365/default.nix*

### Automagic Wireguard

Automagic wireguard setup with tagging and DNS. Each peer provides a list of tags (and an optional endpoint address associated with the peer list).

An example configuration that would be passed into every system (no changes necessary between systems):

```nix
{
 wireguardConf = {
   enable = true;
   interface = "thevoid";
   peers = {
     "server" = {
       wgAddrV4 = "10.55.1.1";
       publicKey = secrets.wireguard.phone.publicKey;

       tags = [{ name = "net"; }];
     };

     "framework" = {
       wgAddrV4 = "10.55.1.2";
       interfaceMask = 16;
       listenPort = 51820;

       privateKeyPath = "/etc/wireguard/private_key";
       privateKeyAge = secrets.wireguard.framework.secret.file;
       publicKey = secrets.wireguard.framework.publicKey;

       tags = [{ name = "net"; } { name = "home"; ipAddr = "172.26.40.247"; }];
     };

     "desktop" = {
       wgAddrV4 = "10.55.0.1";
       interfaceMask = 16;
       listenPort = 51820;

       firewall.allowedTCPPorts = [ 8080 ];

       privateKeyPath = "/etc/wireguard/private_key";
       privateKeyAge = secrets.wireguard.desktop.secret.file;
       publicKey = secrets.wireguard.desktop.publicKey;

       tags = [{ name = "home"; ipAddr = "172.26.26.90"; } { name = "net"; }];
     };

     "vps" = {
        # config
        # ...

        tags = [{ name = "net"; ipAddr = "123.45.67.89"; }];
     };
   };
 };
}
```

The name of the peer must match the hostname of the machine. Firewall ports for wireguard are automatically opened up using the configured network interfaces from another module (*./modules/system/networking*). Age encrypted secrets wireguard keys are automatically setup with `agenix` (see notes on secrets management below). Peer lists are automatically set up using the tags list.

How peer tags work:

* Each tag for a peer signifies it belongs to that tag and will connect to all machines with corresponding tags.
* Tags are read from first to last according to the host's tag list. So `framework` would use the `net` config from `desktop`, while `desktop` would use the `home` config from `framework`. Both `framework` and `desktop` would have `vps` and `phone` in their peer conig as they all belong to `net`.

See *./modules/system/wireguard*.

Inspired by [xe's post](https://christine.website/blog/my-wireguard-setup-2021-02-06).

### Secrets Management

System secrets are managed using `agenix` and user secrets using `homeage`. They are set up in an external (private) repository called `secrets` and pulled in as a flake input. All secrets are age encrypted files. The encrypted files get put into the nix store and they are decrypted at runtime and are tracked by the git repository so they can be pulled in by the flake. The `secrets` repository has two `.nix` files, `config.nix` and `secrets.nix`. `config.nix` contains the configurations. All secrets are stored following attribute (must be named secret):

```nix
secret = {
    publicKeys = [ key1 key2 ... ];
    file = ./example/secret;
};
```

It must be named `secret` so the `secrets.nix` file can extract and transform them to be agenix cli [compatible](https://github.com/ryantm/agenix#tutorial). The follow `secrets.nix` file does the conversion (can be copy/pasted):

```nix
with builtins; let
  config = import ./config.nix;

  nameValuePair = name: value: {inherit name value;};

  filterAttrs = pred: set:
    listToAttrs (concatMap (name: let
      v = set.${name};
    in
      if pred name v
      then [(nameValuePair name v)]
      else []) (attrNames set));

  collect = pred: attrs:
    if pred attrs
    then [attrs]
    else if builtins.isAttrs attrs
    then builtins.concatMap (collect pred) (builtins.attrValues attrs)
    else [];

  relPath = path: replaceStrings [(toString ./.)] ["."] (toString path);

  secretToOutput = attr:
    nameValuePair
    (relPath attr.secret.file)
    {
      publicKeys = attr.secret.publicKeys;
    };

  collectSecrets =
    builtins.listToAttrs
    (builtins.map
      secretToOutput
      (collect
        (x: x ? "secret")
        config));
in
  collectSecrets
```

A more complete example `config.nix`:

```nix
let
  age = {
    system = {
      # The desktop public key used for decryption (manually installed)
      desktop = {
        publicKey = "....";
        privateKeyPath = "....."; # for identity path config
      };

      # The server public key used for decryption (manually installed)
      server = {
        publicKey = "....";
        privateKeyPath = ".....";
      };
    };
  };
in
{
  inherit age;

  ssh = {
    jd = {
      publicKey = "";
      secret = {
        publicKeys = with (age.system); [ desktop.publicKey ];
        file = ./ssh/jd_private_key;
      };
    };
  };

  wireguard = {
    desktop = {
      publicKey = "";
      secret = {
        publicKeys = with (age.system); [ desktop.publicKey ];
        file = ./wireguard/desktop_private_key;
      };
    };

    server = {
      publicKey = "";
      secret = {
        # Be able to edit it on desktop
        publicKeys = with (age.system); [ desktop.publicKey server.publicKey ];
        file = ./wireguard/chairlift_private_key;
      };
    };
  };
}
```

## Credit

A heavily evolved version of Wil Taylor's [dotfiles](https://github.com/wiltaylor/dotfiles). Would not have the setup I have today without his [youtube series](https://www.youtube.com/watch?v=QKoQ1gKJY5A&list=PL-saUBvIJzOkjAw_vOac75v-x6EzNzZq-) and repo as a guide when I was first starting out.

Account endpoints, hardware identifiers, host keys and live enrollment metadata
come from the private `secrets.dotfiles` flake output in `~/.secrets`. The public
repository keeps service policy and synthetic examples; identifier values are
resolved into local generated configuration when building. Commit the private
input before updating its public lock pin, and make that private revision
available to other machines before they use the pin.
