{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.jd.greetd;
  loginRules = config.security.pam.services.login.rules.auth;
  enabledRules = lib.filterAttrs (_: rule: rule.enable) loginRules;
  supportedRules = [
    "deny"
    "fprintd"
    "gnome_keyring"
    "unix"
    "unix-early"
  ];
  tailOrder = loginRules.deny.order + 10;
  fingerprintSkip = builtins.length (
    builtins.filter (rule: rule.order > loginRules.fprintd.order && rule.order < tailOrder) (
      builtins.attrValues enabledRules
    )
  );
  inheritedRules = lib.mapAttrs (name: rule: {
    inherit (rule)
      order
      modulePath
      args
      ;
    # The native rule's final args already contain its rendered settings.
    control =
      if name == "fprintd" then
        "[success=${toString fingerprintSkip} default=ignore]"
      else if name == "deny" then
        "requisite"
      else
        rule.control;
  }) enabledRules;
in
{
  options.jd.greetd.bootKeyringUsers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Users whose encrypted GNOME login keyring may be unlocked with the
      systemd-cryptsetup cached boot passphrase after successful fingerprint
      authentication. Their keyring and disk passphrases must match.
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.bootKeyringUsers != [ ]) {
    assertions = [
      {
        assertion = builtins.elem config.systemd.services.greetd.serviceConfig.KeyringMode [
          "inherit"
          "shared"
        ];
        message = "Boot keyring unlocking requires greetd to inherit or share root's user keyring.";
      }
      {
        assertion = config.services.gnome.gnome-keyring.enable;
        message = "Boot keyring unlocking requires GNOME Keyring's native PAM integration.";
      }
      {
        assertion = builtins.attrNames enabledRules == supportedRules;
        message = ''
          Boot keyring unlocking currently supports the native Unix-password and
          fingerprint login policy. Additional login authentication rules require
          a policy review before enabling this feature.
        '';
      }
      {
        assertion =
          loginRules.fprintd.control == "sufficient"
          && loginRules.unix.control == "sufficient"
          && loginRules."unix-early".control == "optional"
          && loginRules.gnome_keyring.control == "optional"
          && loginRules.deny.control == "required"
          && loginRules.fprintd.order < loginRules."unix-early".order
          && loginRules."unix-early".order < loginRules.gnome_keyring.order
          && loginRules.gnome_keyring.order < loginRules.unix.order
          && loginRules.unix.order < loginRules.deny.order;
        message = "The native login PAM controls/order changed; review the boot-keyring fingerprint branch.";
      }
      {
        assertion = builtins.all (
          user:
          builtins.hasAttr user config.users.users
          && config.users.users.${user}.isNormalUser
          && builtins.match "[A-Za-z_][A-Za-z0-9_.-]*[$]?" user != null
        ) cfg.bootKeyringUsers;
        message = "bootKeyringUsers must name declared normal user accounts.";
      }
    ];

    # greetd's native KeyringMode=shared already links root's user keyring.
    # Keep that upstream default and the boot cache's native short expiry.

    # A successful native password path exits before this tail. Only a matched
    # fingerprint jumps here; failed password authentication stops at pam_deny.
    # Loading before authentication would let try_first_pass use the cached disk
    # password to authenticate a login, rather than only unlocking the keyring.
    security.pam.services.greetd.rules.auth = inheritedRules // {
      login.enable = false;
      boot-keyring-user = {
        order = tailOrder;
        # pam_succeed_if returns PAM_IGNORE from setcred. Unlike an auth jump,
        # a credential jump contributes its return code to the stack result;
        # treat IGNORE explicitly so greetd's unauthenticated greeter can start.
        control = "[success=ignore ignore=ignore default=1]";
        modulePath = "${pkgs.pam}/lib/security/pam_succeed_if.so";
        settings.quiet = true;
        args = [
          "user"
          "in"
          (lib.concatStringsSep ":" cfg.bootKeyringUsers)
        ];
      };
      boot-keyring-load = {
        order = tailOrder + 10;
        control = "optional";
        modulePath = "${config.systemd.package}/lib/security/pam_systemd_loadkey.so";
      };
      boot-keyring-unlock = {
        order = tailOrder + 20;
        control = "optional";
        modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
        # Capture the token here; the native session rule starts/unlocks the
        # daemon after pam_systemd has established the user's runtime directory.
        args = loginRules.gnome_keyring.args;
      };
      boot-keyring-authenticated = {
        order = tailOrder + 30;
        control = "sufficient";
        modulePath = "${pkgs.pam}/lib/security/pam_permit.so";
      };
    };
  };
}
