{ pkgs }:
pkgs.nur.repos.rycee.firefox-addons.buildFirefoxXpiAddon {
  pname = "bypass-paywalls-clean";
  version = "4.4.8.3";
  addonId = "magnolia@12.34";
  # Keep the signed artifact intact. Updates require another source audit.
  url = "https://gitflic.ru/project/magnolia1234/bpc_uploads/blob/raw?file=bypass_paywalls_clean-4.4.8.3.xpi";
  sha256 = "63ed54bb1c6c60fb4d9d8ee9476aaef4b23f0efa0a52ef7377473c87d236d38c";
  meta = {
    description = "Bypass Paywalls Clean, pinned to the reviewed signed Firefox release";
    homepage = "https://gitflic.ru/project/magnolia1234/bypass-paywalls-firefox-clean";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.all;
  };
}
