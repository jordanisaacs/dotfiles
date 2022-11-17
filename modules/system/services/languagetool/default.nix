{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.jd.languagetool;

  name = "langaugetool";
  user = name;
  group = name;
  id = 328;
in {
  options.jd.languagetool = {
    enable = mkOption {
      description = "Whether to enable languagetool";
      type = types.bool;
      default = false;
    };

    port = mkOption {
      type = types.int;
      description = "Languagetool port";
      default = 9002;
    };
  };

  config = mkIf cfg.enable {
    services.languagetool = let
      ngrams-en = pkgs.fetchzip {
        url = "https://languagetool.org/download/ngram-data/ngrams-en-20150817.zip";
        sha256 = "sha256-v3Ym6CBJftQCY5FuY6s5ziFvHKAyYD3fTHr99i6N8sE=";
      };

      ngram-env = pkgs.linkFarm "lt-ngram-env" [
        {
          name = "en";
          path = ngrams-en;
        }
      ];
    in {
      enable = true;
      port = cfg.port;
      settings = {
        languageModel = ngram-env;
      };
      # TODO: Enable advanced (2grams, etc)
    };
  };
}
