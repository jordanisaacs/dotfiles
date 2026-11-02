{
  lib,
  pkgs,
  cfg,
}:
let
  public =
    (lib.evalModules {
      modules = [ ../module.nix ] ++ cfg.policyModules;
    }).config.rsyncNet;
  inherit (public) manifest;
  host = if cfg.endpoint.host != null then cfg.endpoint.host else public.connection.host;
  port = if cfg.endpoint.port != null then cfg.endpoint.port else public.connection.port;
  trustedName =
    if cfg.endpoint.hostKeyAlias != null then cfg.endpoint.hostKeyAlias else public.connection.host;
  knownHosts =
    assert lib.assertMsg (
      (cfg.endpoint.knownHostsFile == null) != (cfg.endpoint.publicHostKey == null)
    ) "rsyncNetClient requires exactly one explicit knownHostsFile/publicHostKey";
    if cfg.endpoint.publicHostKey != null then
      toString (pkgs.writeText "rsync-net-known-hosts" "${trustedName} ${cfg.endpoint.publicHostKey}\n")
    else
      cfg.endpoint.knownHostsFile;
  runtimeIdentity =
    path:
    path != null
    && lib.hasPrefix "/" path
    && !lib.hasInfix "\n" path
    && !lib.hasInfix "\r" path
    && !lib.hasPrefix "/nix/store/" path
    && path != "/nix/store";
  quoteSsh = value: "\"${lib.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] value}\"";
  resticArgumentOptions = binding: [
    (
      "\""
      +
        lib.replaceStrings [ "\"" ] [ "\"\"" ]
          "rclone.program=${lib.escapeShellArgs binding.sshArguments}"
      + "\""
    )
    "rclone.args=ignored"
  ];
  bindings = lib.mapAttrs (
    name: binding:
    assert lib.assertMsg (
      builtins.match "[a-z][a-z0-9_-]{0,40}" name != null
    ) "Invalid rsyncNetClient binding name";
    assert lib.assertMsg (builtins.hasAttr binding.principal public.principals)
      "Unknown rsyncNetClient principal ${binding.principal}";
    let
      principal = public.principals.${binding.principal};
      effective = lib.findFirst (p: p.name == principal.name) null manifest.principals;
      storage = lib.findFirst (d: d.name == principal.dataset) null manifest.datasets;
    in
    assert lib.assertMsg (
      principal.uid != null && principal.gid != null && principal.dataset != null
    ) "rsyncNetClient principal ${binding.principal} needs approved UID/GID/dataset allocation";
    assert lib.assertMsg (
      storage != null && storage.principal == principal.name && storage.quotaBytes != null
    ) "rsyncNetClient principal ${binding.principal} needs a declared dataset/quota";
    assert lib.assertMsg (builtins.hasAttr binding.device principal.devices)
      "rsyncNetClient device ${binding.device} is not enrolled in ${binding.principal}";
    assert lib.assertMsg (runtimeIdentity binding.identityFile)
      "rsyncNetClient ${name} needs a runtime private identity outside the Nix store";
    {
      inherit principal effective;
      inherit (binding) identityFile;
      device = principal.devices.${binding.device};
      alias = "rsync-net-${name}";
      sshSettings = {
        HostName = host;
        Port = port;
        User = principal.name;
        IdentityFile = quoteSsh binding.identityFile;
        IdentityAgent = "none";
        IdentitiesOnly = true;
        AddKeysToAgent = "no";
        ForwardAgent = false;
        BatchMode = true;
        RequestTTY = "no";
        PreferredAuthentications = "publickey";
        ClearAllForwardings = true;
        StrictHostKeyChecking = "yes";
        HostKeyAlias = trustedName;
        UserKnownHostsFile = quoteSsh knownHosts;
        GlobalKnownHostsFile = "none";
        ControlMaster = "no";
        ControlPath = "none";
        ControlPersist = "no";
      };
      # Scheduled jobs bypass unrelated user/system SSH blocks. Aliases remain
      # available through upstream SSH settings for interactive tools.
      sshArguments = [
        "${pkgs.openssh}/bin/ssh"
        "-T"
        "-F"
        "/dev/null"
        "-i"
        binding.identityFile
        "-p"
        (toString port)
        "-o"
        "IdentityAgent=none"
        "-o"
        "IdentitiesOnly=yes"
        "-o"
        "AddKeysToAgent=no"
        "-o"
        "ForwardAgent=no"
        "-o"
        "BatchMode=yes"
        "-o"
        "ClearAllForwardings=yes"
        "-o"
        "StrictHostKeyChecking=yes"
        "-o"
        "HostKeyAlias=${trustedName}"
        "-o"
        "UserKnownHostsFile=${quoteSsh knownHosts}"
        "-o"
        "GlobalKnownHostsFile=none"
        "-o"
        "ControlMaster=no"
        "${principal.name}@${host}"
      ];
    }
  ) cfg.bindings;
in
assert lib.assertMsg (
  public.mode == "public"
) "rsyncNetClient private mode is incomplete; client activation is refused";
assert lib.assertMsg (
  builtins.match "[A-Za-z0-9:][A-Za-z0-9.:%_-]*" host != null
) "rsyncNetClient requires a valid public service hostname/address";
{
  inherit
    bindings
    knownHosts
    public
    manifest
    runtimeIdentity
    resticArgumentOptions
    ;
  # Restic parses -o as CSV; upstream service scripts additionally need shell
  # escaping, while the declarative setup descriptor supplies native argv.
  resticOptions = binding: map lib.escapeShellArg (resticArgumentOptions binding);
}
