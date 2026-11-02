#!/usr/bin/env python3
"""Inspect and drive only Kooha in the disposable capture-test session."""

import json
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, GLib

Atspi.set_timeout(500, 500)


def walk(node, depth=0):
    if depth > 18:
        return []
    result = [node]
    for index in range(min(node.get_child_count(), 100)):
        try:
            child = node.get_child_at_index(index)
            if child is not None:
                result.extend(walk(child, depth + 1))
        except GLib.Error:
            continue
    return result


desktop = Atspi.get_desktop(0)
apps = [desktop.get_child_at_index(i) for i in range(desktop.get_child_count())]
rows = []
for app in apps:
    if "kooha" not in app.get_name().lower():
        continue
    for node in walk(app):
        name = node.get_name()
        role = node.get_role_name()
        rows.append(
            {
                "name": name,
                "role": role,
                "sensitive": node.get_state_set().contains(Atspi.StateType.SENSITIVE),
            }
        )
        if len(sys.argv) > 1 and name == sys.argv[1]:
            action = node.get_action_iface()
            if action is not None and action.get_n_actions() > 0:
                assert action.do_action(0)
                print("Activated", name)
                raise SystemExit(0)
if len(sys.argv) > 1:
    raise SystemExit("No action: " + repr(rows))
print(json.dumps(rows))
