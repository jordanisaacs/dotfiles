{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.graphical.wayland;
  inherit (cfg) keyboard;
  xkbDirectory = pkgs.linkFarm "desktop-xkb-extension" [
    {
      name = "rules/jd";
      path = ./xkb/rules/jd;
    }
    {
      name = "symbols/jd";
      path = ./xkb/symbols/jd;
    }
  ];
  xkbOptions = keyboard.options ++ lib.optional keyboard.capsLockAsAlt "jd:caps_alt";
  keymap = pkgs.runCommand "desktop-keyboard.xkb" { nativeBuildInputs = [ pkgs.libxkbcommon ]; } ''
    xkbcli compile-keymap --include ${xkbDirectory} --include-defaults \
      --rules jd --layout ${lib.escapeShellArg keyboard.layout} \
      --variant ${lib.escapeShellArg keyboard.variant} \
      --options ${lib.escapeShellArg (lib.concatStringsSep "," xkbOptions)} \
      --output-format 1 > "$out"
  '';
  channelConfig = pkgs.writeText "river-input-config.rh" ''
    input {
      profiles {
        keyboard {
          keyboard {
            rules jd
            layout ${keyboard.layout}
            ${lib.optionalString (keyboard.variant != "") "variant ${keyboard.variant}"}
            ${lib.optionalString (xkbOptions != [ ]) "options ${lib.concatStringsSep "," xkbOptions}"}
            repeat {
              rate ${toString keyboard.repeatRate}
              delay ${toString keyboard.repeatDelay}
            }
          }
        }
        touchpad {
          pointer {
            scroll_factor ${toString cfg.touchpad.scrollFactor}
          }
          libinput {
            natural_scroll true
            tap_to_click true
            click_method ${cfg.touchpad.clickMethod}
            disable_while_typing true
          }
        }
      }
      rules [
        type, keyboard, keyboard
        ${lib.concatMapStringsSep "\n" (
          pattern: "name, ${pattern}, touchpad"
        ) cfg.touchpad.namePatterns}
      ]
    }
  '';
in
{
  options.jd.graphical.wayland = {
    keyboard = {
      layout = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_,+-]+";
        default = "us";
        description = "XKB keyboard layouts shared by the Wayland sessions.";
      };
      variant = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_,+-]*";
        default = "";
        description = "XKB variants corresponding to the keyboard layouts.";
      };
      options = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_:+-]+");
        default = [ ];
        description = "Additional XKB options shared by the Wayland sessions.";
      };
      capsLockAsAlt = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Make Caps Lock an additional left Alt modifier without locking capitalization.";
      };
      repeatRate = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 50;
        description = "Keyboard repeat rate in characters per second; zero disables repeat.";
      };
      repeatDelay = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 300;
        description = "Delay in milliseconds before keyboard repeat starts.";
      };
      keymap = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        internal = true;
        default = keymap;
        description = "Compiled native XKB keymap for compositors accepting a keymap file.";
      };
      xkbDirectory = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        internal = true;
        default = xkbDirectory;
        description = "Native XKB extension shared by keymap compilation and River channel.";
      };
    };
    touchpad = {
      clickMethod = lib.mkOption {
        type = lib.types.enum [
          "none"
          "button_areas"
          "clickfinger"
        ];
        default = "clickfinger";
        description = "Physical touchpad click method; clickfinger uses two fingers for a right-click.";
      };
      scrollFactor = lib.mkOption {
        type = lib.types.numbers.positive;
        default = if config.machineData.systemConfig.laptop.enable or false then 0.5 else 1.0;
        description = ''
          Multiplier for touchpad scroll distance. Laptop sessions use half the
          compositor's native scroll distance; mouse wheels retain their defaults.
        '';
      };
      namePatterns = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "[^,\n]+");
        default = [
          # Channel's '*' matches one or more characters, including at the end.
          "Touchpad"
          "touchpad"
          "*Touchpad"
          "*touchpad"
          "*Touchpad*"
          "*touchpad*"
        ];
        description = "River channel device-name patterns identifying touchpads, preserving mouse wheel defaults.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        xdg.configFile = {
          "xkb/rules/jd".source = ./xkb/rules/jd;
          "xkb/symbols/jd".source = ./xkb/symbols/jd;
        };
      }
      (lib.mkIf (cfg.type == "river") {
        home.packages = [ pkgs.river-channel ];
        xdg.configFile."river/config.rh".source = channelConfig;
        systemd.user.services.river-input = {
          Unit = {
            Description = "Native River input configuration";
            Documentation = "https://codeberg.org/Sivecano/channel";
            PartOf = [
              "graphical-session.target"
              "river-wm-reka.service"
            ];
            # Only Reka requests this unit. Stop it before Reka so its input
            # manager is gone before Oxbow applies its own input preferences.
            After = [
              "graphical-session.target"
              "river-wm-reka.service"
            ];
            X-Restart-Triggers = [ channelConfig ];
          };
          Service = {
            ExecStart = "${pkgs.river-channel}/bin/channel";
            Environment = [ "XKB_CONFIG_EXTRA_PATH=${xkbDirectory}" ];
            Restart = "on-failure";
            Slice = "session.slice";
          };
        };
      })
    ]
  );
}
