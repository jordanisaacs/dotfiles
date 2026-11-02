{ pkgs, homeConfiguration }:
let
  homeFor =
    editing:
    (homeConfiguration.extendModules {
      modules = [
        ({ lib, ... }: {
          jd.inputStyle = lib.mkForce "mac";
          jd.keybindings = lib.mkForce editing;
          machineData = lib.mkForce (
            homeConfiguration.config.machineData
            // {
              inputRemapping = {
                enable = true;
                users = [ homeConfiguration.config.home.username ];
              };
            }
          );
        })
      ];
    }).config;
  python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);
  probe = pkgs.stdenvNoCC.mkDerivation {
    name = "gtk-input-probe";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
    ];
    buildInputs = [
      pkgs.gtk3
      pkgs.gsettings-desktop-schemas
    ];
    installPhase = ''
      install -Dm755 ${
        pkgs.writeText "gtk-input-probe.py" (
          "#!${python}/bin/python3\n" + builtins.readFile ./gtk_input_probe.py
        )
      } "$out/bin/gtk-input-probe"
    '';
  };
  driver = pkgs.writeText "gtk-input-driver.py" ''
    import os
    from pathlib import Path
    import subprocess
    import tempfile
    import time

    with tempfile.TemporaryDirectory() as temporary:
        runtime = Path(temporary) / "runtime"
        runtime.mkdir(mode=0o700)
        init = Path(temporary) / "river" / "init"
        init.parent.mkdir()
        init.write_text("#!${pkgs.python3}/bin/python3\nimport os\nos.execv('${pkgs.oxbow}/bin/oxbow', ['${pkgs.oxbow}/bin/oxbow'])\n")
        init.chmod(0o700)
        environment = os.environ | {
            "HOME": temporary,
            "XDG_CONFIG_HOME": temporary,
            "XDG_CACHE_HOME": temporary,
            "XDG_RUNTIME_DIR": str(runtime),
            "WLR_BACKENDS": "headless",
            "WLR_RENDERER": "pixman",
            "WLR_HEADLESS_OUTPUTS": "1",
            "LIBSEAT_BACKEND": "noop",
            "GDK_BACKEND": "wayland",
            "GSETTINGS_BACKEND": "memory",
            "NO_AT_BRIDGE": "1",
        }
        with (Path(temporary) / "river.log").open("w+") as log:
            compositor = subprocess.Popen([
                "${pkgs.river}/bin/river", "-no-xwayland",
            ], env=environment, stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 10
                while True:
                    sockets = [path for path in runtime.glob("wayland-*") if path.is_socket()]
                    if sockets and (runtime / ("oxbow-" + sockets[0].name + ".sock")).is_socket():
                        assert len(sockets) == 1, sockets
                        environment["WAYLAND_DISPLAY"] = sockets[0].name
                        break
                    assert compositor.poll() is None, "Private compositor exited"
                    assert time.monotonic() < deadline, "Private compositor did not start"
                    time.sleep(0.05)
                for editing, css in [
                    ("emacs", "${(homeFor "emacs").xdg.configFile."gtk-3.0/gtk.css".source}"),
                    ("vim", "${(homeFor "vim").xdg.configFile."gtk-3.0/gtk.css".source}"),
                ]:
                    subprocess.run(["${probe}/bin/gtk-input-probe", "--editing", editing, "--css", css],
                                   env=environment, check=True, timeout=20)
                    subprocess.run(["${probe}/bin/gtk-input-probe", "--editing", editing,
                                    "--css", "${pkgs.writeText "empty-gtk.css" ""}", "--stock"],
                                   env=environment, check=True, timeout=20)
            except Exception:
                log.seek(0)
                print(log.read())
                raise
            finally:
                compositor.terminate()
                compositor.wait(timeout=10)
  '';
in
pkgs.runCommand "input-style-gtk-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
  }
  ''
    ${pkgs.ghostty}/bin/ghostty +validate-config --config-file=${
      (homeFor "emacs").xdg.configFile."ghostty/config".source
    }
    python -B ${driver}
    touch "$out"
  ''
