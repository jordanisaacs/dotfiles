{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.jd.graphical.applications;
  isGraphical =
    let
      cfg = config.jd.graphical;
    in
    cfg.wayland.enable;
  noRemoteGrammar = pkgs.writeText "libreoffice-no-remote-grammar.xcu" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <oor:items xmlns:oor="http://openoffice.org/2001/registry">
      <item oor:path="/org.openoffice.Office.Linguistic/GrammarChecking/LanguageTool">
        <prop oor:name="IsEnabled" oor:op="fuse" oor:finalized="true">
          <value>false</value>
        </prop>
      </item>
    </oor:items>
  '';
  # Keep LibreOffice's normal configuration layers and writable profile. The
  # read-only policy changes one property, including when the saved value is
  # true. Removing the policy restores the user's existing server preferences.
  configurationLayers = concatStringsSep " " [
    "xcsxcu:\${BRAND_BASE_DIR}/share/registry"
    "res:\${BRAND_BASE_DIR}/share/registry"
    "bundledext:\${\${BRAND_BASE_DIR}/program/lounorc:BUNDLED_EXTENSIONS_USER}/registry/com.sun.star.comp.deployment.configuration.PackageRegistryBackend/configmgr.ini"
    "sharedext:\${\${BRAND_BASE_DIR}/program/lounorc:SHARED_EXTENSIONS_USER}/registry/com.sun.star.comp.deployment.configuration.PackageRegistryBackend/configmgr.ini"
    "userext:\${\${BRAND_BASE_DIR}/program/lounorc:UNO_USER_PACKAGES_CACHE}/registry/com.sun.star.comp.deployment.configuration.PackageRegistryBackend/configmgr.ini"
    "user:*file://${noRemoteGrammar}"
    "user:!\${$BRAND_BASE_DIR/program/bootstraprc:UserInstallation}/user/registrymodifications.xcu"
  ];
in
{
  options.jd.graphical.applications.libreoffice = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable libreoffice with config [libreoffice]";
    };
    remoteGrammar.enable = mkEnableOption "the saved remote LanguageTool server integration";
  };

  config = mkIf (isGraphical && cfg.enable && cfg.libreoffice.enable) {
    programs.libreoffice = {
      enable = true;
      package =
        if cfg.libreoffice.remoteGrammar.enable then
          pkgs.libreoffice
        else
          pkgs.libreoffice.override {
            extraMakeWrapperArgs = [
              "--set"
              "CONFIGURATION_LAYERS"
              (escapeShellArg configurationLayers)
            ];
          };
      # Do not use settings: it replaces the user's entire existing registry.
    };

    xdg.mimeApps.defaultApplications = {
      "application/vnd.ms-word.document.macroenabled.12" = "writer.desktop";
      "application/vnd.oasis.opendocument.text" = "writer.desktop";
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "writer.desktop";
    };
  };
}
