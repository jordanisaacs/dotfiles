{ pkgs, nixosConfiguration }:
let
  pipewire = nixosConfiguration.config.services.pipewire.package;
in
pkgs.runCommand "pipewire-independent-of-x11"
  {
    nativeBuildInputs = [
      pkgs.python3
      pipewire
      pkgs.xvfb
    ];
    AUDIO_CONFIG_SOURCE = nixosConfiguration.config.environment.etc.pipewire.source;
    AUDIO_STOCK_CONFIG = "${pipewire}/share/pipewire/pipewire.conf";
  }
  ''
    python -B ${./test_audio_session.py} --output-dir "$out"
  ''
