final: prev:
let
  upstream = prev.tlaplus-toolbox;
  pythonScript = import ../lib/python-script.nix { pkgs = final; };
  launcher = pythonScript "tla-toolbox" ../scripts/tla-toolbox.py { };
in
{
  tlaplus-toolbox = final.stdenvNoCC.mkDerivation {
    name = "${upstream.name}-desktop-compatible";
    inherit (upstream) pname version meta;
    dontUnpack = true;
    nativeBuildInputs = [
      final.lndir
      final.python3
      (final.wrapGAppsHook3.override { makeWrapper = final.makeBinaryWrapper; })
    ];
    buildInputs = [ final.gtk3 ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      lndir -silent ${upstream} "$out"
      rm "$out/bin/tla-toolbox"
      install -m755 ${launcher}/bin/tla-toolbox "$out/bin/tla-toolbox"
      # Eclipse resolves its installation from the native launcher's location.
      # Copy that small binary so it resolves this patched installation.
      rm "$out/libexec/toolbox/toolbox"
      cp ${upstream}/libexec/toolbox/toolbox "$out/libexec/toolbox/toolbox"
      jar=$(echo "$out"/libexec/toolbox/plugins/org.eclipse.swt.gtk.linux.x86_64_*.jar)
      cp --remove-destination "$jar" "$jar.copy"
      rm "$jar"
      mv "$jar.copy" "$jar"
      python ${../lib/patch-swt-mime.py} "$out/libexec/toolbox/plugins" \
        ${final.shared-mime-info}/share/mime/globs
      runHook postInstall
    '';
    preFixup = ''
      gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "${
        final.lib.makeLibraryPath [
          final.gtk3
          final.glib
          final.libxtst
          final.zlib
          final.cairo
        ]
      }")
    '';
    passthru = {
      unwrapped = upstream;
    };
  };
}
