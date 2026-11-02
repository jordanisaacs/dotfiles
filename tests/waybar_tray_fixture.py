#!/usr/bin/env python3
"""A real AppIndicator item, isolated inside the desktop regression VM."""

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AppIndicator3", "0.1")
from gi.repository import AppIndicator3, Gtk

indicator = AppIndicator3.Indicator.new(
    "status-bar-regression",
    "dialog-information",
    AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
)
indicator.set_title("Status bar regression fixture")
menu = Gtk.Menu()
item = Gtk.MenuItem(label="Regression action")
menu.append(item)
menu.show_all()
indicator.set_menu(menu)
indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
Gtk.main()
