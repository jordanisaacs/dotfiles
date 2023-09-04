{ config
, lib
, pkgs
, ...
}:
with lib; let
  cfg = config.jd.monitoring;
in
{
  options = {
    jd.monitoring = {
      enable = mkOption {
        description = "Whether to enable monitoring";
        type = types.bool;
        default = false;
      };
    };

    vectorCfg = mkOption {
      inherit ((pkgs.formats.json { })) type;
      default = { };
      description = ''
        Specify the configuration for Vector in Nix.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      # Nested to get around merges/conditionals showing up in generated toml
      vectorCfg =
        let
          buildCfg = opt: config:
            if opt
            then config
            else { };
        in
        {
          sources =
            { }
            // (buildCfg config.jd.unbound.enable {
              generate_unbound = {
                type = "dnstap";
                max_frame_length = 102400;
                socket_file_mode = 511; # TODO: Update permissions
                socket_path = "/run/vector/dnstap.sock";
                raw_data_only = false;
              };
            });
          sinks = {
            out_unbound = {
              inputs = [ "generate_unbound" ];
              type = "file";
              encoding = {
                codec = "json";
              };
              path = "/var/lib/vector/out";
            };
          };
        };

      vectorPkg = pkgs.vector.override {
        enableKafka = false;
        features = [ "vrl-cli" "sources-dnstap" "sinks-file" "unix" ];
      };
    in
    {
      inherit vectorCfg;
      users.groups.vector = { };
      users.users.vector = {
        description = "Vector service user";
        group = "vector";
        isSystemUser = true;
      };
      systemd.services.vector = {
        description = "Vector event and log aggregator";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        requires = [ "network-online.target" ];
        serviceConfig =
          let
            format = pkgs.formats.toml { };
            conf = format.generate "vector.toml" vectorCfg;
            validateConfig = file:
              pkgs.runCommand "validate-vector-conf" { } ''
                ${vectorPkg}/bin/vector validate --no-environment "${file}"
                ln -s "${file}" "$out"
              '';
          in
          {
            ExecStart = "${vectorPkg}/bin/vector --config ${validateConfig conf}";
            User = "vector";
            Group = "vector";
            Restart = "no";
            StateDirectory = "vector";
            ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
            AmbientCapabilities = "CAP_NET_BIND_SERVICE";
            RuntimeDirectory = "vector";
            # This group is required for accessing journald.
            # SupplementaryGroups = mkIf cfg.journaldAccess "systemd-journal";
          };
      };
    }
  );
}
