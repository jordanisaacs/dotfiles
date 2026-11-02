{
  pkgs,
  modules ? [ ],
}:
let
  evaluated = pkgs.lib.evalModules {
    modules = [ ./module.nix ] ++ modules;
  };
  manifest = pkgs.writeText "rsync-net-manifest.json" (
    builtins.toJSON evaluated.config.rsyncNet.manifest
  );
  settings = {
    manifest = toString manifest;
    ssh = "${pkgs.openssh}/bin/ssh";
    sshFail = "${pkgs.coreutils}/bin/false";
    sshKeygen = "${pkgs.openssh}/bin/ssh-keygen";
    restic = "${pkgs.restic}/bin/restic";
    gpg = "${pkgs.gnupg}/bin/gpg";

  };
  project = builtins.fromTOML (builtins.readFile ./pyproject.toml);
  nativeTools = [
    pkgs.openssh
    pkgs.nix
    pkgs.restic
    pkgs.gnupg
  ];
  source = pkgs.lib.fileset.toSource {
    root = ./.;
    fileset = pkgs.lib.fileset.difference (pkgs.lib.fileset.unions [
      ./pyproject.toml
      ./MANIFEST.in
      ./src
      ./module.nix
      ./framework.nix
      ./example-identifiers.nix
      ./tests/framework-policy.nix
      (pkgs.lib.fileset.fileFilter (
        file: file.name == "conftest.py" || (pkgs.lib.hasPrefix "test_" file.name && file.hasExt "py")
      ) ./tests)
      ./network
    ]) (pkgs.lib.fileset.fileFilter (file: file.hasExt "pyc") ./.);
  };
  cli = pkgs.python3Packages.buildPythonApplication {
    pname = project.project.name;
    version = project.project.version;
    pyproject = true;
    src = source;
    build-system = [ pkgs.python3Packages.setuptools ];
    postPatch = ''
      cp ${pkgs.writeText "rsync-net-settings.json" (builtins.toJSON settings)} src/rsync_net/data/settings.json
    '';
    nativeCheckInputs = [ pkgs.python3Packages.pytestCheckHook ] ++ nativeTools;
    env.RSYNC_NET_NIX_LIB = "${pkgs.path}/lib";
    preCheck = ''
      export PATH="$out/bin:$PATH"
      # Native restore correctly rejects writable ancestors. The disposable
      # build root is builder-owned but stdenv may initially leave it shared.
      python - <<'PY'
      import os
      import stat
      from pathlib import Path
      root = Path(os.environ["NIX_BUILD_TOP"]).resolve(strict=True)
      if root == Path("/") or root.stat().st_uid != os.getuid():
          raise RuntimeError("expected a private builder-owned sandbox root")
      root.chmod(stat.S_IMODE(root.stat().st_mode) & ~0o077)
      PY
    '';
    doCheck = true;
    pythonImportsCheck = [
      "rsync_net"
      "rsync_net.cli"
      "rsync_net.apply"
      "rsync_net.control"
      "rsync_net.enrollment"
      "rsync_net.recovery"
      "rsync_net.ssh"
      "rsync_net.setup"
      "rsync_net.storage"
      "rsync_net.backup"
      "rsync_net.snapshots"
      "rsync_net.git"
      "rsync_net.data"
    ];
    meta.mainProgram = "rsync-net";
  };
  devShell = pkgs.mkShell {
    packages = nativeTools ++ [
      pkgs.python3
      pkgs.uv
      pkgs.ruff
    ];
    env = {
      RSYNC_NET_NIX_LIB = "${pkgs.path}/lib";
      UV_PYTHON = "${pkgs.python3}/bin/python3";
      UV_PYTHON_DOWNLOADS = "never";
    };
  };
in
{
  inherit manifest cli devShell;
  inherit (evaluated) config options;
}
