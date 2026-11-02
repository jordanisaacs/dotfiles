"""Drive the configured native UPower daemon on an isolated bus and fake battery."""

import importlib.util
import os
import sys
import unittest
from pathlib import Path

import gi

gi.require_version("UPowerGlib", "1.0")
gi.require_version("UMockdev", "1.0")
from gi.repository import Gio, GLib, UMockdev, UPowerGlib

source = Path(os.environ["UPOWER_TEST_SOURCE"])
sys.path.insert(0, str(source))
spec = importlib.util.spec_from_file_location(
    "upower_native_tests", source / "integration-test.py"
)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
native.Gio, native.GLib = Gio, GLib
native.UMockdev, native.UPowerGlib = UMockdev, UPowerGlib


class CriticalPower(native.Tests):
    def exercise(self, response):
        # Retain upstream bus/device/daemon setup; only the logind capability
        # response is controlled. No request can reach the host's system bus.
        capability = (
            "raise dbus.exceptions.DBusException('fixture capability unavailable', "
            "name='org.freedesktop.login1.Error.NotSupported')"
            if response is None
            else f"ret = {response!r}"
        )
        self.logind_obj.AddMethod(
            "org.freedesktop.login1.Manager", "CanHibernate", "", "s", capability
        )
        battery = self.testbed.add_device(
            "power_supply",
            "BAT0",
            None,
            [
                "type",
                "Battery",
                "present",
                "1",
                "status",
                "Discharging",
                "energy_full",
                "60000000",
                "energy_full_design",
                "60000000",
                "energy_now",
                "30000000",
                "voltage_now",
                "12000000",
            ],
            [],
        )
        self.start_daemon(cfgfile=os.environ["UPOWER_TEST_CONFIG"], warns=True)
        selected = "Hibernate" if response == "yes" else "PowerOff"
        self.assertEqual(self.proxy.GetCriticalAction(), selected)
        self.daemon_log.check_no_line("Critical battery action fallback", wait=0.1)
        self.testbed.set_attribute(battery, "energy_now", "600000")
        self.testbed.uevent(battery, "change")
        self.assertEventually(
            lambda: self.get_dbus_display_property("WarningLevel"),
            value=native.UP_DEVICE_LEVEL_ACTION,
        )
        if response is None:
            self.daemon_log.check_line_re(
                r"Critical battery action fallback: CanHibernate=.*fixture capability unavailable; selected PowerOff",
                timeout=native.UP_DAEMON_ACTION_DELAY + 2,
            )
        elif response != "yes":
            self.daemon_log.check_line(
                f"Critical battery action fallback: CanHibernate={response}; selected PowerOff",
                timeout=native.UP_DAEMON_ACTION_DELAY + 2,
            )
        self.daemon_log.check_line(
            f"About to call logind method {selected}",
            timeout=native.UP_DAEMON_ACTION_DELAY + 2,
        )
        self.assertEventually(
            lambda: any(
                str(call[1]) in (selected, selected + "WithFlags")
                for call in self.logind_obj.GetCalls()
            ),
            value=True,
        )
        if response == "yes":
            self.daemon_log.check_no_line("Critical battery action fallback", wait=0.1)
        forbidden = "PowerOff" if response == "yes" else "Hibernate"
        self.assertFalse(
            any(
                str(call[1]).startswith(forbidden)
                for call in self.logind_obj.GetCalls()
            )
        )

    def test_supported_hibernates(self):
        self.exercise("yes")

    def test_unavailable_reports_fallback(self):
        self.exercise("na")

    def test_denied_reports_fallback(self):
        self.exercise("no")

    def test_capability_error_reports_fallback(self):
        self.exercise(None)


suite = unittest.TestSuite(
    CriticalPower(name)
    for name in (
        "test_supported_hibernates",
        "test_unavailable_reports_fallback",
        "test_denied_reports_fallback",
        "test_capability_error_reports_fallback",
    )
)
if not unittest.TextTestRunner(verbosity=2, failfast=True).run(suite).wasSuccessful():
    raise SystemExit(1)
