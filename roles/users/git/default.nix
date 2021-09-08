{ pkgs, config, lib, ...}:
{
  home.packages = with pkgs; [
    libsecret
  ];

  programs.git = {
    enable = true;
    userName = "Jordan Isaacs";
    userEmail = "github@jdisaacs.com";
    extraConfig = { # https://nixos.wiki/wiki/Git (use libsecret for credential management)
      credential.helper = "${pkgs.libsecret}/bin/lib-credential-manger:";
    };
  };
}

