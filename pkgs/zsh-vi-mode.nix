{ pkgs, ... }:
with pkgs;
stdenvNoCC.mkDerivation rec {
  pname = "zsh-vi-mode";
  version = "master";

  src = fetchFromGitHub {
    owner = "jeffreytse";
    repo = "zsh-vi-mode";
    rev = "258eff7b16f9232bb99323aad019969cf94601c5";
    sha256 = "U/UtCNQW+WL8xSjdf90DckxxjcjW+0XlINFAURRA6Eg=";
  };
  
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/share/zsh-vi-mode
    cp zsh-vi-mode.zsh $out/share/zsh-vi-mode
  '';

  installFlags = [ "PREFIX=$(out)" ];
}

