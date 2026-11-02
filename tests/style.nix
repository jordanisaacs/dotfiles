{ pkgs }:
let
  inherit (pkgs) lib;
  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference (lib.fileset.fileFilter (
      file:
      file.type == "regular" && (file.hasExt "nix" || file.hasExt "py" || file.name == "pyproject.toml")
    ) ../.) (lib.fileset.maybeMissing (../. + "/.git"));
  };
  pythonScript = import ../lib/python-script.nix { inherit pkgs; };
  runner = pythonScript "config-style-check" ./style.py {
    nixfmt = lib.getExe pkgs.nixfmt;
    statix = lib.getExe pkgs.statix;
    deadnix = lib.getExe pkgs.deadnix;
    ruff = lib.getExe pkgs.ruff;
  };
in
{
  checks = lib.genAttrs [ "nixfmt" "statix" "deadnix" "ruff" ] (
    name:
    pkgs.runCommand "config-${name}"
      {
        src = source;
        preferLocalBuild = true;
      }
      ''
        ${runner}/bin/config-style-check ${name} "$src" "$out"
      ''
  );
  devShellPackages = with pkgs; [
    nixfmt
    statix
    deadnix
    ruff
    python3
  ];
}
