"""Public package resources and immutable Nix-generated defaults."""

import json
from importlib.resources import files

CONFIG = json.loads(files(__package__).joinpath("settings.json").read_text())
