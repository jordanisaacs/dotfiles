#!/usr/bin/env python3
"""Draw changing colours exclusively in the disposable capture-test desktop."""

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk

app = Gtk.Application(application_id="org.example.KoohaCaptureFixture")


def activate(application):
    window = Gtk.ApplicationWindow(application=application)
    window.set_title("Capture motion fixture")
    window.set_default_size(500, 400)
    drawing = Gtk.DrawingArea()
    ticks = [0]

    def draw(_area, context, _width, _height):
        context.set_source_rgb((ticks[0] % 7) / 6, (ticks[0] % 11) / 10, 0.4)
        context.paint()

    def advance():
        ticks[0] += 1
        drawing.queue_draw()
        return GLib.SOURCE_CONTINUE

    drawing.set_draw_func(draw)
    window.set_child(drawing)
    window.present()
    GLib.timeout_add(200, advance)


app.connect("activate", activate)
app.run([])
