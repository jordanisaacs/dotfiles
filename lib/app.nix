{pkgs, ...}: {
  mkFlakeApp = {
    app,
    name,
  }:
    pkgs.writeBashBin name ''
      nix run ${app} $@
    '';
}
