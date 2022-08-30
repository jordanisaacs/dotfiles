# Dotfiles

My NixOS dotfile flake for both systems and users. Each system/user is built upon custom modules abstracting NixOS/home-manager. The modules are meant to be easily shareable and should *just work* by taking into account the systemwide configuration. There are modules tailored towards server, desktop, and laptop use.

Note: One of my flake inputs points towards a private git repository of secrets. Thus you will not be able to clone and run this repo without some changes. See the notes on my secrets config below.

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
* Greetd login that starts up sway. See *./modules/users/graphical/wayland.nix*
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
