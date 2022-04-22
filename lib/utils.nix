{ self, lib }:

with lib;

rec {
  # Removes attributes by path. Used to remove module options when disabled
  # Example:
  # removeAttrByPath [ "x" "y" ] { x = { y = { f = 4; }; z = 3; } -> { x = { z = 3; }; }
  removeAttrByPath = attrPath: set:
    let
      removeAttrRec = recPath: rem: set':
        if recPath == [ ] then
          let
            removed = removeAttrs set' [ rem ];

            result = updateManyAttrsByPath [
              {
                path = (init attrPath);
                update = old: removed;
              }
            ]
              set;
          in
          if isAttrs set' then
            result
          else
            set
        else
          if (hasAttr rem set') then
            removeAttrRec (drop 1 recPath) (head recPath) (getAttr rem set')
          else set;
    in
    if (length attrPath) == 0 then set
    else
      removeAttrRec (drop 1 attrPath) (head attrPath) set;

  # Enable a module if attribute exists and is true
  enableModule = config: module: path:
    if (attrByPath path false config) then
      [ module ]
    else
      [{ }];

  # Enable a module if attribute exists and is activated, along with importing the respective config
  enableModuleConfig = config: module: folder: { path, activate }:
    if (attrByPath (path ++ activate) false config) then
      [
        module
        (import (self + folder + (lib.concatStringsSep "/" path)))
      ]
    else
      [{ }];

  # Remove the module options from systemConfig if the module is not activated
  removeModuleOptions = { path, activate }: config:
    if (attrByPath (path ++ activate) false config) then
      config
    else
      removeAttrByPath path config;
}
