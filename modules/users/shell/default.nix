{
  pkgs,
  config,
  lib,
  ...
}:
with lib; {
  imports = [./zsh.nix ./bash.nix];

  options.jd.shell = mkOption {
    description = "Type of shell to use";
    type = types.enum ["zsh" "bash"];
    default = "zsh";
  };
}
