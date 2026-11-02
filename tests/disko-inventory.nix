{
  pkgs,
  nixpkgs,
  disko,
}:
let
  # Public fixture identities, deliberately unrelated to the laptop's UUIDs.
  partitionUUIDs = {
    ESP = "11111111-1111-4111-8111-111111111111";
    key = "22222222-2222-4222-8222-222222222222";
    swap = "33333333-3333-4333-8333-333333333333";
    root = "44444444-4444-4444-8444-444444444444";
  };
  evaluated = nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      disko.nixosModules.disko
      (import ../storage/experiments/disko-existing-layout.nix {
        device = "/dev/does-not-exist-inventory-only";
        inherit partitionUUIDs;
      })
      {
        # Evaluate generated NixOS settings without executing any Disko script.
        disko.enableConfig = pkgs.lib.mkForce true;
        system.stateVersion = "26.11";
      }
    ];
  };
  inherit (evaluated) config;
  data = pkgs.writeText "disko-inventory.json" (
    builtins.toJSON {
      inherit partitionUUIDs;
      filesystems = pkgs.lib.mapAttrs (_: fs: {
        inherit (fs) device fsType options;
      }) config.fileSystems;
      luks = pkgs.lib.mapAttrs (_: volume: {
        inherit (volume) device keyFile;
      }) config.boot.initrd.luks.devices;
      inherit (config.boot) resumeDevice;
      swaps = map (swap: {
        inherit (swap) device;
        randomEncryption = swap.randomEncryption.enable;
      }) config.swapDevices;
      destroy = config.disko.devices.disk.framework.destroy;
    }
  );
in
pkgs.runCommand "disko-existing-layout-inventory"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    INVENTORY = data;
  }
  ''
    python -B ${./test_disko_inventory.py}
    touch "$out"
  ''
