{ lib, ... }:
let
  inherit (lib) mkOption types;
  name = types.strMatching "[a-z][a-z0-9_-]{0,40}";
  runtimeFile = types.nullOr (types.strMatching "/[^\n\r]+");
in
{
  options.jd.rsyncNetClient = {
    enable = lib.mkEnableOption "scoped rsync.net client configuration";
    policyModules = mkOption {
      type = types.listOf types.deferredModule;
      default = [ ];
      description = "Public rsyncNet policy modules, evaluated with the server's typed module. Never put private keys or passwords in these modules.";
    };
    endpoint = {
      host = mkOption {
        type = types.nullOr (types.strMatching "[A-Za-z0-9:][A-Za-z0-9.:%_-]*");
        default = null;
        description = "Optional public-mode service hostname/address override; null uses the public policy connection.host. Private mode remains incomplete and cannot activate clients.";
      };
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Optional public-mode service port override; null uses the public policy connection.port.";
      };
      hostKeyAlias = mkOption {
        type = types.nullOr (types.strMatching "[A-Za-z0-9][A-Za-z0-9.-]*");
        default = null;
        description = "Known-host identity; defaults to the public administrative hostname so its existing verified host key authenticates the service endpoint.";
      };
      knownHostsFile = mkOption {
        type = runtimeFile;
        default = null;
        description = "Explicit public known_hosts file, readable by the local backup user. Select exactly one of this and publicHostKey.";
      };
      publicHostKey = mkOption {
        type = types.nullOr (types.strMatching "ssh-ed25519 [A-Za-z0-9+/]+={0,2}( [^\n\r]*)?");
        default = null;
        description = "Verified public Ed25519 host key to pin declaratively. This is public data; private identities are runtime file references only.";
      };
    };
    bindings = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            principal = mkOption {
              type = name;
              description = "Existing allocated principal in the public server policy.";
            };
            device = mkOption {
              type = name;
              description = "Named enrolled device belonging to the principal.";
            };
            identityFile = mkOption {
              type = runtimeFile;
              default = null;
              description = "Absolute runtime path to this device's matching SSH private key, outside Git/Nix store. Provision and persist it separately; no key generation or secret reads happen during Nix evaluation.";
            };
          };
        }
      );
      description = "Local device/principal memberships. SSH aliases are rsync-net-<binding>; every binding needs an explicit private identity path.";
    };
  };
}
