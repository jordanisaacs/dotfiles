{ pkgs }:
pkgs.runCommand "wifi-profile-migration-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    src = pkgs.lib.fileset.toSource {
      root = ../.;
      fileset = pkgs.lib.fileset.unions [
        ./test_iwd_migration.py
        ../modules/system/networking/migrate-iwd.py
      ];
    };
  }
  ''
    python -B "$src/tests/test_iwd_migration.py"
    touch "$out"
  ''
