{
  config,
  lib,
  ...
}:
with lib;
with builtins;
let
  cfg = config.jd.core;
  persist = config.jd.impermanence;
in
{
  options.jd = {
    inputStyle = mkOption {
      type = types.enum [
        "mac"
        "win"
      ];
      default = config.machineData.inputStyle or "win";
      description = "Desktop shortcut convention; defaults to the system preference independently of editing keybindings.";
    };

    keybindings = mkOption {
      type = types.enum [
        "vim"
        "emacs"
      ];
      default = config.machineData.keybindings or "emacs";
      description = "Editing and navigation keybinding profile; defaults to the system preference.";
    };

    core = {
      enable = mkOption {
        description = "Enable some core configurations";
        type = types.bool;
        default = true;
      };
    };

  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf persist.enable {
      home.persistence.${persist.backupPool} = [
        "${config.xdg.userDirs.documents}/dev"
        config.xdg.configHome
      ];

      home.persistence.${persist.persistPool} = [
        config.xdg.cacheHome
        ".thunderbird"
      ];
    })
    {
      home.sessionVariables.JD_KEYBINDINGS = config.jd.keybindings;
      xdg = {
        enable = true;

        userDirs.enable = true;

        userDirs.setSessionVariables = true;

        mime.enable = true;

        mimeApps.enable = true;
      };

      programs.home-manager.enable = true;

      # System GC does not expire profiles in the user's XDG state directory.
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
        randomizedDelaySec = "30min";
      };
    }
  ]);
}
