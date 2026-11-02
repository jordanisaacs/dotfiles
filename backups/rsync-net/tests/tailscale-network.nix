{
  pkgs,
  allowDenied ? false,
}:
let
  inherit (pkgs) lib;
  cert = pkgs.runCommand "rsync-net-test-control-cert" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir "$out"
    openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
      -out "$out/cert.pem" -keyout "$out/key.pem" \
      -subj /CN=control -addext subjectAltName=DNS:control
  '';
  network = import ../network {
    inherit pkgs;
    modules = [
      {
        rsyncNet.network = {
          requested = true;
          nodeName = "provider";
          tailnetSuffix = "fixture.test.ts.net";
          stateDirectory = "/mnt/data1/control/tailscale";
          tags = [ "tag:storage" ];
          managedUsers = [ "backup" ];
        };
      }
    ];
  };
  policy = pkgs.writeText "rsync-net-test-tailnet-policy.json" (
    builtins.toJSON {
      tagOwners."tag:storage" = [ "storage@" ];
      acls = [
        {
          action = "accept";
          src = [ "allowed@" ];
          dst = [
            "tag:storage:22"
            "tag:storage:80"
          ];
        }
        {
          action = "accept";
          src = [ "denied@" ];
          dst = [ "allowed@:9999" ];
        }
      ]
      ++ lib.optional allowDenied {
        action = "accept";
        src = [ "denied@" ];
        dst = [ "tag:storage:22" ];
      };
    }
  );
  peer = {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      disableUpstreamLogging = true;
      disableTaildrop = true;
    };
    security.pki.certificateFiles = [ "${cert}/cert.pem" ];
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
    environment.systemPackages = [
      pkgs.python3
      pkgs.curl
      pkgs.openssh
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "rsync-net-private-tailnet";
  nodes = {
    control = {
      virtualisation.memorySize = 768;
      services = {
        headscale = {
          enable = true;
          settings = {
            server_url = "https://control";
            policy = {
              mode = "file";
              path = "/etc/headscale/test-policy.json";
            };
            derp = {
              urls = [ ];
              auto_update_enabled = false;
              server = {
                enabled = true;
                region_id = 999;
                stun_listen_addr = "0.0.0.0:3478";
              };
            };
            dns = {
              base_domain = "fixture.test";
              override_local_dns = false;
            };
          };
        };
        nginx = {
          enable = true;
          virtualHosts.control = {
            addSSL = true;
            sslCertificate = "${cert}/cert.pem";
            sslCertificateKey = "${cert}/key.pem";
            locations."/" = {
              proxyPass = "http://127.0.0.1:8080";
              proxyWebsockets = true;
            };
          };
        };
      };
      networking.firewall = {
        allowedTCPPorts = [ 443 ];
        allowedUDPPorts = [ 3478 ];
      };
      environment.etc."headscale/test-policy.json".source = policy;
      environment.systemPackages = [
        pkgs.headscale
        pkgs.python3
        pkgs.openssh
      ];
    };
    provider =
      { lib, ... }:
      {
        imports = [ peer ];
        virtualisation.memorySize = 768;
        # Use the exact production candidate's userspace-mode decision.
        services.tailscale.interfaceName = lib.mkForce network.plan.mode;
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
          };
          authorizedKeysFiles = [
            "%h/.ssh/authorized_keys"
            "%h/.ssh/authorized_keys2"
            "/etc/ssh/public-authorized/%u"
          ];
        };
        users.users.backup = {
          isNormalUser = true;
          uid = 2000;
          home = "/home/backup";
        };
        systemd.tmpfiles.rules = [
          "L+ ${network.plan.privateSshConfigPath} - - - - ${network.sshdConfig}"
        ];
        environment.systemPackages = [ pkgs.procps ];
      };
    allowed = {
      imports = [ peer ];
      virtualisation.memorySize = 512;
    };
    denied = {
      imports = [ peer ];
      virtualisation.memorySize = 512;
    };
  };
  testScript = builtins.readFile ./tailscale_network_probe.py + ''
    start_all()
    control.wait_for_unit("headscale.service")
    control.wait_for_open_port(443)
    for peer in [provider, allowed, denied]:
        peer.wait_for_unit("tailscaled.service")
    provider.wait_for_unit("sshd.service")
    run(control=control, provider=provider, allowed=allowed, denied=denied,
        private_config_path=${builtins.toJSON network.plan.privateSshConfigPath})
  '';
}
