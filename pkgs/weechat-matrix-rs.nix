{ pkgs, ... }:
with pkgs;

rustPlatform.buildRustPackage rec {
  pname = "weechat-matrix-rs";
  version = "master";
  src = fetchFromGitHub {
    owner = "poljar";
    repo = pname;
    rev = "2b093a7ff1c75650467d61335b90e4a6ce1fa210";
    sha256 = "P9SLZ2EefZ+ITYV3BRvtVsdbZaGeLZI0k67TdtGQMgs=";
  };

  nativeBuildInputs = [ pkg-config cmake ];
  buildInputs = [ openssl weechat libclang glibc libcxx ];
  cargoSha256 = "gwUBpSBCLDYiXtkFdeDBQDqfInY/ZVK3tP5V3CZEzD0=";
  PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
  # https://github.com/NixOS/nixpkgs/issues/52447#issuecomment-853429315
  LIBCLANG_PATH = "${lib.getLib libclang}/lib";
  BINDGEN_EXTRA_CLANG_ARGS = "-isystem ${llvmPackages.libclang.lib}/lib/clang/${lib.getVersion clang}/include";
  WEECHAT_BUNDLED = true;
}
