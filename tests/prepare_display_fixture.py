"""Adapt the actual generated Kanshi policy to a headless output name only."""

import json
import os
import shlex
from pathlib import Path


def expand(path: Path) -> list[str]:
    lines = []
    for line in path.read_text().splitlines():
        words = shlex.split(line)
        if words and words[0] == "include":
            assert len(words) == 2, line
            included = Path(words[1])
            assert included.is_absolute(), included
            lines.extend(expand(included))
        else:
            lines.append(line)
    return lines


source = "\n".join(expand(Path(os.environ["KANSHI_SOURCE"])))
criteria = json.dumps(os.environ["INTERNAL_OUTPUT"])
assert source.count(criteria) == 2, source
fixture = source.replace(criteria, json.dumps("HEADLESS-1"))
Path(os.environ["out"]).write_text(fixture + "\n")
