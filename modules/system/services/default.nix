{ pkgs
, config
, lib
, ...
}: {
  imports = [
    ./syncthing
    ./monitoring
    ./unbound
    ./acme
    ./mail-server
    ./nginx
    ./miniflux
    ./taskserver
    ./ankisyncd
    ./microbin
    ./languagetool
    ./calibre
    ./firefly-iii
  ];
}
