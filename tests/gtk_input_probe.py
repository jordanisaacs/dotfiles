"""Exercise the native GTK binding engine with the actual generated stylesheet."""

import argparse
import json

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk


def drain():
    while Gtk.events_pending():
        Gtk.main_iteration_do(False)


def text_state(widget):
    if isinstance(widget, Gtk.Entry):
        return widget.get_position(), tuple(widget.get_selection_bounds())
    buffer = widget.get_buffer()
    cursor = buffer.get_iter_at_mark(buffer.get_insert()).get_offset()
    return cursor, tuple(it.get_offset() for it in buffer.get_selection_bounds())


def prepare(widget):
    if isinstance(widget, Gtk.Entry):
        widget.set_text("alpha beta")
        widget.set_position(-1)
    else:
        buffer = widget.get_buffer()
        buffer.set_text("alpha beta")
        buffer.place_cursor(buffer.get_end_iter())
    drain()


def activate(widget, key, modifiers):
    handled = Gtk.bindings_activate(widget, key, modifiers)
    drain()
    return handled


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--editing", choices=("emacs", "vim"), required=True)
    parser.add_argument("--css", required=True)
    parser.add_argument("--stock", action="store_true")
    args = parser.parse_args()
    Gtk.init([])
    settings = Gtk.Settings.get_default()
    settings.set_property(
        "gtk-key-theme-name", "Emacs" if args.editing == "emacs" else "Default"
    )
    provider = Gtk.CssProvider()
    errors = []
    provider.connect(
        "parsing-error", lambda _provider, _section, error: errors.append(str(error))
    )
    provider.load_from_path(args.css)
    assert not errors, errors
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
    )
    window = Gtk.Window()
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    window.add(box)
    widgets = [Gtk.Entry(), Gtk.TextView()]
    for widget in widgets:
        box.pack_start(widget, True, True, 0)
    window.show_all()
    drain()
    for widget in widgets:
        widget.grab_focus()
        prepare(widget)
        activate(widget, Gdk.KEY_a, Gdk.ModifierType.CONTROL_MASK)
        _cursor, selection = text_state(widget)
        if args.editing == "emacs":
            assert text_state(widget) == (0, ()), text_state(widget)
        else:
            assert selection == (0, 10), text_state(widget)
        prepare(widget)
        activate(widget, Gdk.KEY_a, Gdk.ModifierType.SUPER_MASK)
        if args.stock:
            assert text_state(widget)[1] != (0, 10), text_state(widget)
            continue
        assert text_state(widget)[1] == (0, 10), text_state(widget)
        prepare(widget)
        activate(widget, Gdk.KEY_Left, Gdk.ModifierType.MOD1_MASK)
        assert text_state(widget) == (6, ()), text_state(widget)
        prepare(widget)
        activate(
            widget,
            Gdk.KEY_Left,
            Gdk.ModifierType.MOD1_MASK | Gdk.ModifierType.SHIFT_MASK,
        )
        assert text_state(widget)[1] == (6, 10), text_state(widget)
        prepare(widget)
        activate(widget, Gdk.KEY_Up, Gdk.ModifierType.SUPER_MASK)
        assert text_state(widget) == (0, ()), text_state(widget)
        activate(widget, Gdk.KEY_Down, Gdk.ModifierType.SUPER_MASK)
        assert text_state(widget) == (10, ()), text_state(widget)
        activate(widget, Gdk.KEY_BackSpace, Gdk.ModifierType.MOD1_MASK)
        if isinstance(widget, Gtk.Entry):
            assert widget.get_text() == "alpha ", widget.get_text()
        else:
            buffer = widget.get_buffer()
            assert (
                buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), True)
                == "alpha "
            )
        prepare(widget)
        activate(widget, Gdk.KEY_a, Gdk.ModifierType.SUPER_MASK)
        invoked = []

        def action(target, name, invoked=invoked):
            invoked.append(name)
            # Verify action dispatch without depending on selection serials in
            # this widget-level probe. The VM separately checks Firefox's
            # native clipboard payload through the Wayland clipboard protocol.
            target.stop_emission_by_name(name)

        for key, name in (
            (Gdk.KEY_c, "copy-clipboard"),
            (Gdk.KEY_x, "cut-clipboard"),
            (Gdk.KEY_v, "paste-clipboard"),
        ):
            widget.connect(name, action, name)
            assert activate(widget, key, Gdk.ModifierType.SUPER_MASK), name
        assert invoked == ["copy-clipboard", "cut-clipboard", "paste-clipboard"], (
            invoked
        )
        if isinstance(widget, Gtk.TextView):
            buffer = widget.get_buffer()
            buffer.set_text("alpha\nbeta")
            buffer.place_cursor(buffer.get_end_iter())
            drain()
            activate(widget, Gdk.KEY_a, Gdk.ModifierType.CONTROL_MASK)
            if args.editing == "emacs":
                assert text_state(widget) == (6, ()), text_state(widget)
            else:
                assert text_state(widget)[1] == (0, 10), text_state(widget)
            activate(widget, Gdk.KEY_a, Gdk.ModifierType.SUPER_MASK)
            assert text_state(widget)[1] == (0, 10), text_state(widget)
    window.destroy()
    print(
        json.dumps(
            {
                "editing": args.editing,
                "stock": args.stock,
                "widgets": ["entry", "textview"],
                "passed": True,
            }
        )
    )


if __name__ == "__main__":
    main()
