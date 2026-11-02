#!/usr/bin/env python3
"""Read the native logout dialog through the standard accessibility bus."""

import json
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, GLib


def walk(node, depth=0):
    if depth > 16:
        return []
    result = [{"name": node.get_name(), "role": node.get_role_name()}]
    for index in range(min(node.get_child_count(), 100)):
        try:
            child = node.get_child_at_index(index)
            if child is not None:
                result.extend(walk(child, depth + 1))
        except GLib.Error:
            continue
    return result


# A deliberately stopped private app must not block inspection of the live
# logout dialog. This timeout is a test reader bound, not a hang diagnosis.
Atspi.set_timeout(500, 500)
result = []
names = []
desktop = Atspi.get_desktop(0)
for index in range(desktop.get_child_count()):
    try:
        app = desktop.get_child_at_index(index)
        names.append(app.get_name())
        if app.get_name() in ("Log Out", "dev.snowytrees.DesktopLogout"):
            result.extend(walk(app))
    except GLib.Error:
        continue
if not result:
    print("AT-SPI applications: " + repr(names), file=sys.stderr)
print(json.dumps(result))
