# modified from: https://github.com/lucasew/nixcfg/blob/master/packages/wrapWine.nix
{ pkgs, ...}:
{
  executable,
  name,
  config_dir,
  wineFlags ? "",
  tricks ? [ ],
  setupScript ? "",
  firstRunScript ? "",
  is64bits ? false,
  wine ? pkgs.wineWowPackages.stable
}:
with builtins;
let
  wineBin = "${wine}/bin/wine${if is64bits then "64" else ""}";
  requiredPackages = with pkgs; [
    wine
    cabextract
  ];
  wineConfigDir = "${config_dir}/wine";
  PATH = pkgs.lib.makeBinPath requiredPackages;
  NAME = name;

  HOME =
    if home == "" then
      "${WINENIX_PROFILES}/${name}" 
    else
      home;

  WINEARCH =
    if is64bits then
      "win64" 
    else
      "win32";

  setupHook = "${wine}/bin/wineboot";

  tricksHook=
    if (length tricks) > 0 then
      let
        tricksStr = concatStringsSep " " tricks;
        tricksPkg = pkg.winetricks.override { inherit wine; };
      in
        "${tricksPkg}/bin/winetricks ${tricksStr}"
    else
      "";

  script = pkgs.writeShellScriptBin name ''
    export WINEARCH=${WINEARCH}
    export PATH=$PATH:${PATH}
    export WINEPREFIX="${wineConfigDir}/${name}"
    mkdir -p "${wineConfigDir}"
    export HOME="$WINEPREFIX"
    ${setupScript}
    if [ ! -d "$WINEPREFIX" ] # if the prefix does not exist
    then
      mkdir -p "$WINEPREFIX"
      ${setupHook}
      wineserver -w
      ${tricksHook}
      ${firstRunScript}
    fi
    if [ ! "$REPL" == "" ]; # if $REPL is setup then start a shell in the context
    then
      bash
      exit 0
    fi

    ${wineBin} start ${wineFlags} /unix "${executable}" "$@"
    wineserver -w
  '';
in script
