{
  style,
  wmModifier ? "Super+Alt",
}:
let
  isMac = style == "mac";
  modifier = if isMac then wmModifier else "Super";
in
{
  inherit isMac;
  # Preserve Command for app shortcuts and selected desktop actions.
  wmModifier = modifier;
  auxiliaryModifier = if builtins.match ".*Control.*" modifier != null then "Alt" else "Control";
  emacsWmModifier =
    builtins.replaceStrings [ "Super" "Alt" "Control" "+" ] [ "s-" "M-" "C-" "" ]
      modifier;
  launcher = if isMac then "Super+space" else null;
  emacsLauncher = if isMac then "s-SPC" else null;
  nextWindow = if isMac then "Super+Tab" else null;
  previousWindow = if isMac then "Super+Shift+Tab" else null;
  emacsNextWindow = if isMac then "s-<tab>" else null;
  emacsPreviousWindow = if isMac then "s-S-<tab>" else null;
  fullscreen = if isMac then "Super+Control+f" else "Super+f";
  emacsFullscreen = if isMac then "s-C-f" else "s-f";
}
