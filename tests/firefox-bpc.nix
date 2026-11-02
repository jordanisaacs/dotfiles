{ pkgs, home }:
let
  addon = import ../modules/users/graphical/applications/firefox-bpc.nix { inherit pkgs; };
in
pkgs.runCommand "firefox-bpc-signature-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    FIREFOX_BINARY = "${home.programs.firefox.finalPackage}/bin/firefox";
    GECKODRIVER = "${pkgs.geckodriver}/bin/geckodriver";
    BPC_XPI = "${addon}/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${addon.addonId}.xpi";
  }
  ''
    python -B ${./test_firefox_bpc.py}
    touch "$out"
  ''
