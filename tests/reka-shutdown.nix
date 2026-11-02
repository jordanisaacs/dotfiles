{
  pkgs,
  home,
  withGracefulStop ? true,
}:
pkgs.runCommand "reka-orderly-shutdown-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    EMACS = "${home.programs.emacs.finalPackage}/bin/emacs";
    EMACSCLIENT = "${home.programs.emacs.finalPackage}/bin/emacsclient";
    STOP_COMMAND =
      if withGracefulStop then home.systemd.user.services.river-wm-reka.Service.ExecStop else "";
  }
  ''
    python -B ${./test_reka_shutdown.py}
    touch "$out"
  ''
