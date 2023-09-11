{ config, pkgs, lib, ... }:
with lib;
let
  src = pkgs.fetchFromGitHub {
    owner = "drduh";
    repo = "YubiKey-Guide";
    rev = "4a641dffd002e8132bcbbcd46089acfa2040c749";
    hash = "sha256-yRFlKslsMNF1QcWCJqSjUrDbORXLd+jU5YFfrREoBjE=";
  };

  guide = "${src}/README.md";
  contrib = "${src}/contrib";
  drduhConfig = pkgs.fetchFromGitHub {
    owner = "drduh";
    repo = "config";
    rev = "6bea1fdaa8732ec8625f4bac7022b25e14b15ffe";
    hash = "sha256-Fto8FCVYeKviMz0VmCiXHrgMT1pVopJGGDHF0s3K4ts=";
  };
  gpg-conf = "${drduhConfig}/gpg.conf";

  xserverCfg = config.services.xserver;

  pinentryFlavour =
    if xserverCfg.desktopManager.lxqt.enable || xserverCfg.desktopManager.plasma5.enable then
      "qt"
    else if xserverCfg.desktopManager.xfce.enable then
      "gtk2"
    else if xserverCfg.enable || config.programs.sway.enable then
      "gnome3"
    else
      "curses";

  # Instead of hard-coding the pinentry program, chose the appropriate one
  # based on the environment of the image the user has chosen to build.
  gpg-agent-conf = pkgs.runCommand "gpg-agent.conf" { } ''
    sed '/pinentry-program/d' ${drduhConfig}/gpg-agent.conf > $out
    echo "pinentry-program ${pkgs.pinentry.${pinentryFlavour}}/bin/pinentry" >> $out
  '';

  view-yubikey-guide = pkgs.writeShellScriptBin "view-yubikey-guide" ''
    viewer="$(type -P xdg-open || true)"
    if [ -z "$viewer" ]; then
      viewer="${pkgs.glow}/bin/glow -p"
    fi
    exec $viewer "${guide}"
  '';

  shortcut = pkgs.makeDesktopItem {
    name = "yubikey-guide";
    icon = "${pkgs.yubikey-manager-qt}/share/ykman-gui/icons/ykman.png";
    desktopName = "drduh's YubiKey Guide";
    genericName = "Guide to using YubiKey for GPG and SSH";
    comment = "Open the guide in a reader program";
    categories = [ "Documentation" ];
    exec = "${view-yubikey-guide}/bin/view-yubikey-guide";
  };

  yubikey-guide = pkgs.symlinkJoin {
    name = "yubikey-guide";
    paths = [ view-yubikey-guide shortcut ];
  };

in
{
  options.jd = {
    yubikey = mkEnableOption "yubikey tools";
  };

  config = mkIf config.jd.yubikey {
    services.pcscd.enable = true;
    services.udev.packages = [ pkgs.yubikey-personalization ];

    programs = {
      ssh.startAgent = false;
      gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
      };
    };

    environment.systemPackages = with pkgs; [
      # Tools for backing up keys
      paperkey
      pgpdump
      parted
      cryptsetup

      # Yubico's official tools
      yubikey-manager
      yubikey-manager-qt
      yubikey-personalization
      yubikey-personalization-gui
      yubico-piv-tool
      yubioath-flutter

      # Testing
      ent
      # (haskell.lib.justStaticExecutables haskellPackages.hopenpgp-tools)

      # Password generation tools
      diceware
      pwgen

      # Miscellaneous tools that might be useful beyond the scope of the guide
      cfssl
      pcsctools

      # This guide itself (run `view-yubikey-guide` on the terminal to open it
      # in a non-graphical environment).
      yubikey-guide
    ];

    # Unset history so it's never stored
    # Set GNUPGHOME to an ephemeral location and configure GPG with the
    # guide's recommended settings.
    environment.interactiveShellInit = ''
      unset HISTFILE
      export GNUPGHOME="/run/user/$(id -u)/gnupg"
      if [ ! -d "$GNUPGHOME" ]; then
        echo "Creating \$GNUPGHOME…"
        install --verbose -m=0700 --directory="$GNUPGHOME"
      fi
      [ ! -f "$GNUPGHOME/gpg.conf" ] && cp --verbose ${gpg-conf} "$GNUPGHOME/gpg.conf"
      [ ! -f "$GNUPGHOME/gpg-agent.conf" ] && cp --verbose ${gpg-agent-conf} "$GNUPGHOME/gpg-agent.conf"
      echo "\$GNUPGHOME is \"$GNUPGHOME\""
    '';

    # Copy the contents of contrib to the home directory, add a shortcut to
    # the guide on the desktop, and link to the whole repo in the documents
    # folder.
    system.activationScripts.yubikeyGuide =
      let
        homeDir = "/home/nixos/";
        desktopDir = homeDir + "Desktop/";
        documentsDir = homeDir + "Documents/";
      in
      ''
        mkdir -p ${desktopDir} ${documentsDir}
        chown nixos ${homeDir} ${desktopDir} ${documentsDir}

        cp -R ${contrib}/* ${homeDir}
        ln -sf ${yubikey-guide}/share/applications/yubikey-guide.desktop ${desktopDir}
        ln -sfT ${src} ${documentsDir}/YubiKey-Guide
      '';
  };
}
