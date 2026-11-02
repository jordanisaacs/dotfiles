"""Exercise Firefox's native sidebar with a disposable profile and pointer input."""

import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path


def wait_for(check, description):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for {description}")


with tempfile.TemporaryDirectory(prefix="firefox-sidebar-test-") as temporary:
    root = Path(temporary)
    profile = root / "profile"
    profile.mkdir()
    # Register this disposable profile so the selectable-profile UI really
    # would be enabled without the enterprise policy being tested.
    profiles_root = root / ".mozilla/firefox"
    profiles_root.mkdir(parents=True)
    (profiles_root / "profiles.ini").write_text(
        "[General]\nVersion=2\nStartWithLastProfile=1\n\n"
        f"[Profile0]\nName=fixture\nIsRelative=0\nPath={profile}\nDefault=1\n"
    )
    shutil.copyfile(os.environ["FIREFOX_USER_JS"], profile / "user.js")
    if os.environ.get("INSTALL_COMPACT_STYLE") == "1":
        (profile / "chrome").mkdir()
        shutil.copyfile(
            os.environ["FIREFOX_USER_CHROME"], profile / "chrome/userChrome.css"
        )
    # Reproduce a profile whose old vertical sidebar was saved fully expanded.
    # Only synthetic UI state is used; the real profile is never opened.
    saved_state = {
        "command": "",
        "panelOpen": False,
        "launcherWidth": 240,
        "launcherExpanded": True,
        "launcherVisible": True,
    }
    with (profile / "user.js").open("a") as output:
        output.write(
            'user_pref("sidebar.backupState", '
            + json.dumps(json.dumps(saved_state))
            + ");\n"
        )
        # A negative control proves the test detects an ordinary expanded rail.
        if os.environ.get("EXPECT_HOVER") == "0":
            output.write('user_pref("sidebar.visibility", "always-show");\n')

    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]

    environment = os.environ | {
        "HOME": str(root),
        "XDG_CONFIG_HOME": str(root / "config"),
        "XDG_CACHE_HOME": str(root / "cache"),
        "MOZ_HEADLESS": "1",
        # Nix's build sandbox already isolates the disposable browser process.
        "MOZ_DISABLE_CONTENT_SANDBOX": "1",
    }
    with (root / "geckodriver.log").open("w+") as log:
        driver = subprocess.Popen(
            [
                os.environ["GECKODRIVER"],
                "--port",
                str(port),
                # Privileged automation is confined to this test process.
                "--allow-system-access",
            ],
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        session = None

        def request(method, path, data=None):
            request_data = json.dumps(data).encode() if data is not None else None
            request_object = urllib.request.Request(
                f"http://127.0.0.1:{port}" + path,
                data=request_data,
                method=method,
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(request_object, timeout=40) as response:
                return json.load(response)["value"]

        try:

            def ready():
                try:
                    return request("GET", "/status")["ready"]
                except OSError:
                    return False

            wait_for(ready, "GeckoDriver startup")
            result = request(
                "POST",
                "/session",
                {
                    "capabilities": {
                        "alwaysMatch": {
                            "browserName": "firefox",
                            "moz:firefoxOptions": {
                                "binary": os.environ["FIREFOX_BINARY"],
                                "args": [
                                    "-headless",
                                    "-no-remote",
                                    "-profile",
                                    str(profile),
                                ],
                            },
                        }
                    }
                },
            )
            session = result["sessionId"]
            prefix = "/session/" + session
            request("POST", prefix + "/moz/context", {"context": "chrome"})

            def chrome(script):
                return request(
                    "POST", prefix + "/execute/sync", {"script": script, "args": []}
                )

            def state():
                return chrome("""
                    const controller = window.SidebarController;
                    return {
                        ready: !!controller?.initialized,
                        expanded: controller?.getUIState()?.launcherExpanded,
                        visible: controller?.getUIState()?.launcherVisible,
                        vertical: controller?.sidebarVerticalTabsEnabled,
                        hover: document.documentElement.hasAttribute("sidebar-expand-on-hover"),
                        width: controller?.sidebarContainer?.getBoundingClientRect().width,
                    };
                """)

            def move(x, y):
                request(
                    "POST",
                    prefix + "/actions",
                    {
                        "actions": [
                            {
                                "type": "pointer",
                                "id": "mouse",
                                "parameters": {"pointerType": "mouse"},
                                "actions": [
                                    {
                                        "type": "pointerMove",
                                        "duration": 100,
                                        "origin": "viewport",
                                        "x": x,
                                        "y": y,
                                    }
                                ],
                            }
                        ]
                    },
                )

            wait_for(lambda: state()["ready"], "sidebar initialization")
            move(500, 300)
            initial = state()
            assert initial["vertical"] and initial["visible"], initial
            assert initial["hover"], initial
            wait_for(lambda: not state()["expanded"], "initial icon rail")
            collapsed_width = state()["width"]
            assert 20 < collapsed_width < 100, state()
            rectangle = chrome("return SidebarController.getMouseTargetRect()")
            move(
                int((rectangle["left"] + rectangle["right"]) / 2),
                int((rectangle["top"] + rectangle["bottom"]) / 2),
            )
            wait_for(lambda: state()["expanded"], "hover expansion")
            wait_for(
                lambda: state()["width"] > collapsed_width + 100,
                "rendered tab labels",
            )
            expanded_width = state()["width"]
            move(500, 300)
            wait_for(lambda: not state()["expanded"], "collapse after pointer leaves")
            wait_for(
                lambda: abs(state()["width"] - collapsed_width) < 2,
                "rendered icon rail",
            )
            # Firefox intentionally allows its toolbar/keyboard command to pin
            # labels open without changing the configured hover preference.
            chrome("SidebarController.handleToolbarButtonClick(); return true;")
            wait_for(
                lambda: state()["expanded"] and not state()["hover"],
                "explicitly pinned tab labels",
            )
            assert (
                chrome('return Services.prefs.getStringPref("sidebar.visibility")')
                == "expand-on-hover"
            )
            chrome("SidebarController.handleToolbarButtonClick(); return true;")
            wait_for(
                lambda: state()["hover"] and not state()["expanded"],
                "hover mode after unpinning",
            )
            # Measure rendered rows in both density modes, not just the pref.
            assert (
                chrome("return document.documentElement.getAttribute('uidensity')")
                == "compact"
            )
            compact_height = chrome(
                "return gBrowser.selectedTab.getBoundingClientRect().height"
            )
            chrome("Services.prefs.setIntPref('browser.uidensity', 0); return true;")
            wait_for(
                lambda: (
                    chrome("return document.documentElement.getAttribute('uidensity')")
                    != "compact"
                ),
                "normal-density comparison",
            )
            normal_height = chrome(
                "return gBrowser.selectedTab.getBoundingClientRect().height"
            )
            assert normal_height > compact_height + 3, (compact_height, normal_height)
            chrome("Services.prefs.setIntPref('browser.uidensity', 1); return true;")
            wait_for(
                lambda: (
                    abs(
                        chrome(
                            "return gBrowser.selectedTab.getBoundingClientRect().height"
                        )
                        - compact_height
                    )
                    < 1
                ),
                "compact tab rows",
            )
            # Open the real app menu and inspect its profile controls. The
            # registered profile ensures this is not a false pass from -profile.
            assert (
                chrome("return Services.policies.isAllowed('profileManagement')")
                is False
            )
            chrome("PanelUI.show(); return true;")
            wait_for(lambda: chrome("return PanelUI.panel.state == 'open'"), "app menu")
            for identifier in [
                "appMenu-profiles-button",
                "appMenu-create-profile-button",
                "profiles-menu",
            ]:
                assert chrome(
                    f"return document.getElementById({json.dumps(identifier)}).hidden"
                ), identifier
            chrome("PanelUI.hide(); return true;")
            # Add the account widget through Firefox's supported customization
            # API, as an existing profile might already have placed it there.
            chrome("""
                const { CustomizableUI } = ChromeUtils.importESModule(
                    "moz-src:///browser/components/customizableui/CustomizableUI.sys.mjs"
                );
                CustomizableUI.addWidgetToArea("fxa-toolbar-menu-button", CustomizableUI.AREA_NAVBAR);
                return true;
            """)
            assert chrome("""
                const avatar = document.getElementById("fxa-toolbar-menu-button");
                return !avatar || avatar.hidden || getComputedStyle(avatar).display === "none";
            """), "Firefox account avatar is still visible"
            print(
                "Native vertical tabs: "
                f"{collapsed_width}px rail -> {expanded_width}px hover -> icon rail; "
                "pin/unpin preserves the preference; "
                f"compact rows {compact_height}px vs {normal_height}px; profile UI hidden"
            )
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read()[-5000:])
            raise
        finally:
            if session:
                request("DELETE", "/session/" + session)
            driver.terminate()
            driver.wait(timeout=10)
