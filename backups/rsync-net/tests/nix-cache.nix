{ pkgs }:
let
  cache = import ../default.nix {
    inherit pkgs;
    modules = [
      {
        rsyncNet = {
          connection.host = "fixture.invalid";
          principals.cache = {
            backend = "nix-cache";
            dataset = "data1/cache";
            devices = {
              writer.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4";
              reader = {
                publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5";
                readOnly = true;
              };
            };
          };
          datasets.cache = {
            name = "data1/cache";
            mountpoint = "/mnt/data1/cache";
            principal = "cache";
            purpose = "cache";
            quotaBytes = 1048576;
          };
        };
      }
    ];
  };
in
pkgs.runCommand "signed-ssh-nix-cache"
  {
    nativeBuildInputs = [
      pkgs.nix
      pkgs.python3
    ];
  }
  ''
    PYTHONPATH=${../src} python -B ${./nix_cache_probe.py} --manifest ${cache.manifest}
    touch "$out"
  ''
