{
  config,
  lib,
  pkgs,
  ...
}:
let
  askpass = lib.getExe pkgs.kdePackages.ksshaskpass;
in
{
  config = lib.mkIf config.jd.graphical.enable {
    # The upstream SSH default follows xserver.enable, which excludes Wayland.
    programs.ssh = {
      enableAskPassword = true;
      askPassword = askpass;
    };
    environment = {
      systemPackages = [ pkgs.kdePackages.ksshaskpass ];
      sessionVariables.SUDO_ASKPASS = askpass;
      # Also let sudo find the helper when a launcher omits SUDO_ASKPASS.
      etc."sudo.conf".text = "Path askpass ${askpass}\n";
    };

    # PAM authenticates serially: try a fingerprint briefly, then ask for the
    # password. Other login/lock services retain their existing fingerprint policy.
    security.pam.services.sudo.rules.auth.fprintd.settings = lib.mkIf config.services.fprintd.enable {
      timeout = 5;
      max-tries = 1;
    };
  };
}
