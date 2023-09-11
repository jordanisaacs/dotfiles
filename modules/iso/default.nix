{ pkgs
, config
, lib
, ...
}: {
  imports = [
    ./core
    ./user
    ./desktop
    ./yubikey
  ];
}
