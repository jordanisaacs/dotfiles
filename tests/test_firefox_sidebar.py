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
from urllib.parse import quote


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
    # Exercise migration away from a fixed DPI override without any real data.
    (profile / "prefs.js").write_text(
        'user_pref("layout.css.devPixelsPerPx", "2.0");\n'
    )
    if os.environ.get("INSTALL_COMPACT_STYLE") == "1":
        (profile / "chrome").mkdir()
        shutil.copyfile(
            os.environ["FIREFOX_USER_CHROME"], profile / "chrome/userChrome.css"
        )
        if os.environ.get("STABLE_COMPACT_ROWS") == "0":
            # Negative control: the former fixed floor lets larger labels grow
            # expanded rows and displace the tabs below the pointer.
            with (profile / "chrome/userChrome.css").open("a") as output:
                output.write(
                    '\n:root[uidensity="compact"] #tabbrowser-tabs[orient="vertical"]'
                    " { --tab-min-height: 28px !important; }\n"
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

        def request(method, path, data=None, timeout=40):
            request_data = json.dumps(data).encode() if data is not None else None
            request_object = urllib.request.Request(
                f"http://127.0.0.1:{port}" + path,
                data=request_data,
                method=method,
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(request_object, timeout=timeout) as response:
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

            def tab_rectangles():
                return chrome("""
                    return Array.from(gBrowser.visibleTabs).map(tab => {
                        const row = tab.getBoundingClientRect();
                        const icon = tab.querySelector(".tab-icon-stack").getBoundingClientRect();
                        return {id: tab.linkedBrowser.browsingContext.id, selected: tab.selected,
                                y: row.y, height: row.height,
                                iconY: icon.y, iconHeight: icon.height};
                    });
                """)

            def unchanged_rows(expected):
                actual = tab_rectangles()
                assert len(actual) == len(expected), (expected, actual)
                for before, after in zip(expected, actual, strict=True):
                    assert before["id"] == after["id"], (before, after)
                    assert before["selected"] == after["selected"], (before, after)
                    for key in ("y", "height", "iconY", "iconHeight"):
                        assert abs(before[key] - after[key]) <= 1, (key, before, after)

            def sample_stable_rows(expected):
                # Include the animation, rather than only its final dimensions.
                deadline = time.monotonic() + 0.8
                while time.monotonic() < deadline:
                    unchanged_rows(expected)
                    time.sleep(0.05)

            def hover_and_leave():
                move(500, 300)
                wait_for(lambda: not state()["expanded"], "collapsed tab rows")
                time.sleep(0.5)
                before = tab_rectangles()
                rectangle = chrome("return SidebarController.getMouseTargetRect()")
                move(
                    int((rectangle["left"] + rectangle["right"]) / 2),
                    int((rectangle["top"] + rectangle["bottom"]) / 2),
                )
                sample_stable_rows(before)
                wait_for(lambda: state()["expanded"], "hover expansion")
                unchanged_rows(before)
                move(500, 300)
                sample_stable_rows(before)
                wait_for(lambda: not state()["expanded"], "hover collapse")
                unchanged_rows(before)
                return before

            wait_for(lambda: state()["ready"], "sidebar initialization")
            move(500, 300)
            initial = state()
            assert initial["vertical"] and initial["visible"], initial
            assert initial["hover"], initial
            wait_for(lambda: not state()["expanded"], "initial icon rail")
            collapsed_width = state()["width"]
            assert 20 < collapsed_width < 100, state()
            chrome("""
                const principal = Services.scriptSecurityManager.getSystemPrincipal();
                for (let index = 0; index < 4; index++) {
                    const tab = gBrowser.addTab("about:blank", {
                        triggeringPrincipal: principal, skipAnimation: true,
                    });
                    tab.label = "Sidebar font fixture " + index;
                }
                return true;
            """)
            wait_for(lambda: len(tab_rectangles()) == 5, "five fixture tabs")
            time.sleep(0.5)
            configured_rows = hover_and_leave()

            # Native UI font roles apply to browser chrome, including fields.
            appearance = chrome("""
                const root = getComputedStyle(document.documentElement);
                const field = getComputedStyle(document.getElementById("urlbar-input"));
                const canvas = document.createElementNS("http://www.w3.org/1999/xhtml", "canvas");
                const context = canvas.getContext("2d");
                context.font = root.fontSize + " " + root.fontFamily;
                return {
                    family: root.fontFamily, size: parseFloat(root.fontSize),
                    fieldFamily: field.fontFamily, fieldSize: parseFloat(field.fontSize),
                    narrow: context.measureText("iiii").width,
                    wide: context.measureText("WWWW").width,
                    ratio: window.devicePixelRatio,
                    fixedDpi: Services.prefs.prefHasUserValue("layout.css.devPixelsPerPx"),
                };
            """)
            family = os.environ["FIREFOX_UI_FONT_FAMILY"]
            font_size = float(os.environ["FIREFOX_UI_FONT_SIZE_PX"])
            scale_percent = int(os.environ["FIREFOX_UI_SCALE_PERCENT"])
            assert family in appearance["family"], appearance
            assert family in appearance["fieldFamily"], appearance
            assert abs(appearance["size"] - font_size) < 0.2, appearance
            # Firefox intentionally gives the address field a small relative
            # size increase; retain that native hierarchy over the same family.
            assert font_size <= appearance["fieldSize"] <= font_size * 1.1, appearance
            assert appearance["wide"] > appearance["narrow"] * 1.5, appearance
            assert appearance["fixedDpi"] is False, appearance
            configured_ratio = appearance["ratio"]
            chrome('Services.prefs.setIntPref("ui.textScaleFactor", 100); return true;')
            wait_for(
                lambda: abs(chrome("return window.devicePixelRatio") - 1) < 0.03,
                "native scale baseline",
            )
            baseline_ratio = chrome("return window.devicePixelRatio")
            chrome(
                f'Services.prefs.setIntPref("ui.textScaleFactor", {scale_percent}); return true;'
            )
            wait_for(
                lambda: (
                    abs(
                        chrome("return window.devicePixelRatio") / baseline_ratio
                        - scale_percent / 100
                    )
                    < 0.03
                ),
                "Firefox-only relative pixel scale",
            )
            assert (
                abs(configured_ratio / baseline_ratio - scale_percent / 100) < 0.03
            ), appearance

            # The compact row policy must work with larger accessible fonts too,
            # not merely hide the jump by making this profile's font smaller.
            original_sizes = chrome("""
                return Object.fromEntries(Services.prefs.getChildList("ui.font.")
                    .filter(pref => pref.endsWith(".size"))
                    .map(pref => [pref, Services.prefs.getCharPref(pref)]));
            """)
            chrome("""
                for (const pref of Services.prefs.getChildList("ui.font.")) {
                    if (pref.endsWith(".size")) Services.prefs.setCharPref(pref, "20");
                }
                return true;
            """)
            wait_for(
                lambda: (
                    chrome(
                        "return parseFloat(getComputedStyle(document.documentElement).fontSize)"
                    )
                    > 19.5
                ),
                "larger native UI font",
            )
            hover_and_leave()
            chrome(
                """
                const sizes = """
                + json.dumps(original_sizes)
                + """;
                for (const [pref, value] of Object.entries(sizes)) Services.prefs.setCharPref(pref, value);
                return true;
            """
            )
            wait_for(
                lambda: (
                    abs(
                        chrome(
                            "return parseFloat(getComputedStyle(document.documentElement).fontSize)"
                        )
                        - font_size
                    )
                    < 0.2
                ),
                "configured native UI font",
            )

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
            request("POST", prefix + "/moz/context", {"context": "content"})
            page = (
                "<p id='body'><span>iiii</span><span>WWWW</span></p>"
                "<pre id='code'><span>iiii</span><span>WWWW</span></pre>"
            )
            request("POST", prefix + "/url", {"url": "data:text/html," + quote(page)})
            content_fonts = request(
                "POST",
                prefix + "/execute/sync",
                {
                    "script": """
                    function widths(id) {
                        const element = document.getElementById(id);
                        return Array.from(element.children).map(child => child.getBoundingClientRect().width);
                    }
                    return {body: widths("body"), code: widths("code"),
                            bodyFamily: getComputedStyle(document.getElementById("body")).fontFamily,
                            codeFamily: getComputedStyle(document.getElementById("code")).fontFamily};
                """,
                    "args": [],
                },
            )
            assert content_fonts["body"][1] > content_fonts["body"][0] * 1.5, (
                content_fonts
            )
            assert abs(content_fonts["code"][0] - content_fonts["code"][1]) < 0.1, (
                content_fonts
            )
            request("POST", prefix + "/moz/context", {"context": "chrome"})
            print(
                "Native vertical tabs: "
                f"{collapsed_width}px rail -> {expanded_width}px hover -> icon rail; "
                "pin/unpin preserves the preference; "
                f"compact rows {compact_height}px vs {normal_height}px; profile UI hidden; "
                f"{family} {font_size:.2f}px UI at {configured_ratio:.3f} DPR; "
                f"{len(configured_rows)} tab rows stay fixed across hover; page/code fonts preserved"
            )
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read()[-5000:])
            raise
        finally:
            try:
                if session:
                    request("DELETE", "/session/" + session, timeout=5)
            except OSError as error:
                print(f"Disposable browser shutdown: {type(error).__name__}")
            finally:
                driver.terminate()
                try:
                    driver.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    driver.kill()
                    driver.wait(timeout=5)
