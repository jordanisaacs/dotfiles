"""Verify actual native key translation and modifier state, without input devices."""

import ctypes
import json
import os
import unittest
from contextlib import contextmanager
from pathlib import Path


class RulesNames(ctypes.Structure):
    _fields_ = [
        (name, ctypes.c_char_p)
        for name in ("rules", "model", "layout", "variant", "options")
    ]


xkb = ctypes.CDLL(os.environ["LIBXKB"])


def function(name, arguments, result):
    fn = getattr(xkb, name)
    fn.argtypes = arguments
    fn.restype = result
    return fn


pointer = ctypes.c_void_p
integer = ctypes.c_uint32
context_new = function("xkb_context_new", [integer], pointer)
context_unref = function("xkb_context_unref", [pointer], None)
include_path_append = function(
    "xkb_context_include_path_append", [pointer, ctypes.c_char_p], ctypes.c_int
)
keymap_new = function(
    "xkb_keymap_new_from_names", [pointer, ctypes.POINTER(RulesNames), integer], pointer
)
keymap_parse = function(
    "xkb_keymap_new_from_string", [pointer, ctypes.c_char_p, integer, integer], pointer
)
keymap_unref = function("xkb_keymap_unref", [pointer], None)
key_by_name = function("xkb_keymap_key_by_name", [pointer, ctypes.c_char_p], integer)
state_new = function("xkb_state_new", [pointer], pointer)
state_unref = function("xkb_state_unref", [pointer], None)
state_update_key = function(
    "xkb_state_update_key", [pointer, integer, integer], integer
)
state_symbol = function("xkb_state_key_get_one_sym", [pointer, integer], integer)
state_mod_active = function(
    "xkb_state_mod_name_is_active", [pointer, ctypes.c_char_p, integer], ctypes.c_int
)


@contextmanager
def keyboard(*, serialized=None, layout=None, options=None):
    context = context_new(0)
    assert context
    assert include_path_append(context, os.fsencode(os.environ["XKB_EXTENSION"]))
    keymap = None
    state = None
    try:
        if serialized is not None:
            keymap = keymap_parse(context, serialized.encode(), 1, 0)
        else:
            names = RulesNames(
                rules=b"jd",
                model=b"pc105",
                layout=(layout or os.environ["LAYOUT"]).encode(),
                variant=os.environ["VARIANT"].encode(),
                options=",".join(options or []).encode(),
            )
            keymap = keymap_new(context, ctypes.byref(names), 0)
        assert keymap, "Native XKB keymap compilation failed"
        state = state_new(keymap)
        assert state
        yield keymap, state
    finally:
        if state:
            state_unref(state)
        if keymap:
            keymap_unref(keymap)
        context_unref(context)


class KeyboardTests(unittest.TestCase):
    def check_alt_caps(self, keymap, state):
        caps = key_by_name(keymap, b"CAPS")
        letter = key_by_name(keymap, b"AC01")
        unmodified = state_symbol(state, letter)
        self.assertEqual(state_symbol(state, caps), 0xFFE9, "Caps must emit Alt_L")
        state_update_key(state, caps, 1)
        self.assertEqual(state_mod_active(state, b"Mod1", 1 << 3), 1)
        self.assertEqual(state_mod_active(state, b"Lock", 1 << 3), 0)
        state_update_key(state, caps, 0)
        self.assertEqual(state_mod_active(state, b"Mod1", 1 << 3), 0)
        self.assertEqual(state_mod_active(state, b"Lock", 1 << 3), 0)
        self.assertEqual(state_symbol(state, letter), unmodified)

    def test_generated_keymap_matches_native_channel_rules(self):
        options = json.loads(os.environ["OPTIONS"])
        if json.loads(os.environ["CAPS_ALT"]):
            options.append("jd:caps_alt")
        with (
            keyboard(serialized=Path(os.environ["KEYMAP"]).read_text()) as compiled,
            keyboard(options=options) as channel,
        ):
            for name in (b"CAPS", b"LALT", b"LCTL", b"LFSH", b"AD01", b"AC01"):
                self.assertEqual(
                    state_symbol(compiled[1], key_by_name(compiled[0], name)),
                    state_symbol(channel[1], key_by_name(channel[0], name)),
                )
            if json.loads(os.environ["CAPS_ALT"]):
                # Check held/released modifiers as well as the displayed keysym.
                self.check_alt_caps(*compiled)
                self.check_alt_caps(*channel)

    def test_baseline_keymap_reproduces_the_old_behavior(self):
        with keyboard(layout="us") as (keymap, state):
            caps = key_by_name(keymap, b"CAPS")
            self.assertEqual(state_symbol(state, caps), 0xFFE5)
            state_update_key(state, caps, 1)
            state_update_key(state, caps, 0)
            self.assertEqual(state_mod_active(state, b"Lock", 1 << 3), 1)
            with self.assertRaises(AssertionError):
                self.check_alt_caps(keymap, state)

    def test_remap_keeps_other_modifiers_and_layouts(self):
        for layout in ("us", "fr"):
            with (
                keyboard(layout=layout) as before,
                keyboard(layout=layout, options=["jd:caps_alt"]) as after,
            ):
                for name in (b"LALT", b"RALT", b"LCTL", b"RCTL", b"LFSH", b"AD01"):
                    self.assertEqual(
                        state_symbol(before[1], key_by_name(before[0], name)),
                        state_symbol(after[1], key_by_name(after[0], name)),
                    )
                alt = key_by_name(after[0], b"LALT")
                state_update_key(after[1], alt, 1)
                self.assertEqual(state_mod_active(after[1], b"Mod1", 1 << 3), 1)
                state_update_key(after[1], alt, 0)
                self.assertEqual(state_mod_active(after[1], b"Mod1", 1 << 3), 0)


if __name__ == "__main__":
    unittest.main()
