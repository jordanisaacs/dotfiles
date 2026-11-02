# Keep Xwayland's compiler compatible with current XKB data without rebuilding
# the desktop's shared X11 libraries or changing native Wayland keymaps.
final: prev:
let
  keysyms = {
    XF86ElectronicPrivacyScreenOn = "10081252";
    XF86ElectronicPrivacyScreenOff = "10081253";
    XF86ActionOnSelection = "10081254";
    XF86ContextualInsert = "10081255";
    XF86ContextualQuery = "10081256";
  };
  keysymDB = final.runCommand "xwayland-keysyms" { } ''
    ${final.python3}/bin/python - "$out" <<'PY'
    import json
    from pathlib import Path
    import sys

    # XStringToKeysym checks its compiled table before this native fallback.
    # Retain the package's existing fallback database when one is installed.
    base = Path(${builtins.toJSON "${prev.libx11}/share/X11/XKeysymDB"})
    existing = base.read_text() if base.is_file() else ""
    additions = json.loads(${builtins.toJSON (builtins.toJSON keysyms)})
    Path(sys.argv[1]).write_text(
        existing + "\n" + "\n".join(f"{key}: {value}" for key, value in additions.items()) + "\n"
    )
    PY
  '';
  keyboardData = final.runCommand "xwayland-keyboard-data" { } ''
    ${final.python3}/bin/python - "$out" <<'PY'
    from pathlib import Path
    import re
    import shutil
    import sys

    output = Path(sys.argv[1])
    shutil.copytree(${builtins.toJSON "${prev.xkeyboard-config}"}, output, symlinks=True)
    path = output / "share/X11/xkb/symbols/inet"
    keycodes = (output / "share/X11/xkb/keycodes/evdev").read_text()
    original = path.read_text()
    result = original
    # I201/I202 alias FK23/FK24. Consolidate the duplicate definitions while
    # preserving their actual merged symbols and modifier-sensitive types.
    for name, alias, before, after in [
        ("FK23", "I201", "XF86TouchpadOff, XF86Assistant", "F23, XF86Assistant"),
        ("FK24", "I202", "F24, XF86TouchpadToggle", "F24, XF86TouchpadToggle"),
    ]:
        direct = re.findall(rf"^\s*key <{name}>[^\n]+", result, re.MULTILINE)
        aliased = re.findall(rf"^\s*key <{alias}>[^\n]+\n", result, re.MULTILINE)
        # Already consolidated upstream data needs no compatibility change.
        is_alias = re.search(rf"alias\s+<{alias}>\s*=\s*<{name}>;", keycodes)
        if not direct or not aliased or not is_alias:
            continue
        assert len(direct) == len(aliased) == 1, "Unexpected XKB key definitions"
        assert before in direct[0], "Unexpected XKB function-key symbols"
        function = "F23" if name == "FK23" else "F24"
        assert re.fullmatch(rf"\s*key <{alias}>\s*\{{\s*\[\s*{function}\s*\]\s*\}};[^\n]*\n", aliased[0]), "Unexpected XKB alias symbols"
        result = result.replace(direct[0], direct[0].replace(before, after), 1)
        result = result.replace(aliased[0], "", 1)
    if result != original:
        path.chmod(0o644)
        path.write_text(result)
    PY
  '';
  compiler = final.symlinkJoin {
    name = "xwayland-xkbcomp";
    paths = [ prev.xkbcomp ];
    nativeBuildInputs = [ final.makeBinaryWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/xkbcomp" --set-default XKEYSYMDB ${keysymDB}
    '';
  };
in
{
  xwayland =
    (prev.xwayland.override {
      xkbcomp = compiler;
      xkeyboard_config = keyboardData;
    }).overrideAttrs
      (old: {
        # Use Meson's native -Wall setting and correct its minimum version;
        # keep compiler checks enabled and handle short writes in test tools.
        patches = (old.patches or [ ]) ++ [ ./xwayland-build.patch ];
        mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dwarning_level=1" ];
        passthru = (old.passthru or { }) // {
          jdKeymap = {
            inherit
              compiler
              keyboardData
              keysymDB
              keysyms
              ;
            originalCompiler = prev.xkbcomp;
            originalData = prev.xkeyboard-config;
          };
        };
      });
}
