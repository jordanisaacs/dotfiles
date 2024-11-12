{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "1220687c8c47a48ba285d26a05600f8700d37fc637e223ced3aa8324f3650bf52242";
    path = fetchzip {
      url = "https://codeberg.org/ifreund/zig-wayland/archive/v0.2.0.tar.gz";
      hash = "sha256-dvit+yvc0MnipqWjxJdfIsA6fJaJZOaIpx4w4woCxbE=";
    };
  }
]
