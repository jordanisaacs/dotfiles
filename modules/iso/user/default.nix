{ pkgs
, config
, lib
, ...
}: {
  users.users.nixos = {
    name = "nixos";
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    uid = 1000;
    initialPassword = "helloworld!";
    shell = pkgs.zsh;
  };
}
