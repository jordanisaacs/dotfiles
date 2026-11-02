{ pkgs }:
name: source: settings:
pkgs.writers.writePython3Bin name
  {
    flakeIgnore = [
      "E402"
      "E501"
    ];
  }
  (
    ''
      import json
      CONFIG = json.loads(${builtins.toJSON (builtins.toJSON settings)})

    ''
    + builtins.readFile source
  )
