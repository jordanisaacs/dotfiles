{ pkgs, home }:
pkgs.runCommand "libreoffice-remote-grammar-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    PYTHONPATH = "${pkgs.libreoffice.unwrapped}/lib/libreoffice/program";
    URE_BOOTSTRAP = "vnd.sun.star.pathname:${pkgs.libreoffice.unwrapped}/lib/libreoffice/program/fundamentalrc";
    BASE_LIBREOFFICE = "${pkgs.libreoffice}/bin/soffice";
    CONFIGURED_LIBREOFFICE = "${home.programs.libreoffice.package}/bin/soffice";
  }
  ''
    python -B ${./test_libreoffice_grammar.py}
    touch "$out"
  ''
