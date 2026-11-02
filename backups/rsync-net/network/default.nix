{
  pkgs,
  modules ? [ ],
}:
let
  evaluated = pkgs.lib.evalModules {
    modules = [ ./module.nix ] ++ modules;
  };
  plan = evaluated.config.rsyncNet.network.plan;
in
{
  inherit plan;
  inherit (evaluated) config options;
  manifest = pkgs.writeText "rsync-net-private-network-plan.json" (builtins.toJSON plan);
  sshdConfig =
    let
      files = pkgs.lib.filter (file: file.path == plan.privateSshConfigPath) plan.desiredFiles;
    in
    if files == [ ] then
      null
    else
      pkgs.writeText "rsync-net-private-sshd_config" (builtins.head files).contents;
}
