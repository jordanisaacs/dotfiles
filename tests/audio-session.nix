{ pkgs, nixosConfiguration }:
pkgs.runCommand "pipewire-independent-of-x11"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.pipewire
      pkgs.xvfb
    ];
    AUDIO_CONFIG_SOURCE = nixosConfiguration.config.environment.etc.pipewire.source;
    AUDIO_STOCK_CONFIG = "${pkgs.pipewire}/share/pipewire/pipewire.conf";
  }
  ''
    python -B ${./test_audio_session.py} --output-dir "$out"
  ''
