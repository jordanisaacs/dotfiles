"""Verify BPC's Mozilla signature without installing or executing the add-on."""

import hashlib
import json
import os
import socket
import subprocess
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

xpi = Path(os.environ["BPC_XPI"])
assert hashlib.sha256(xpi.read_bytes()).hexdigest() == (
    "63ed54bb1c6c60fb4d9d8ee9476aaef4b23f0efa0a52ef7377473c87d236d38c"
)
with zipfile.ZipFile(xpi) as archive:
    manifest = json.loads(archive.read("manifest.json"))
assert manifest["version"] == "4.4.8.3"
assert manifest["browser_specific_settings"]["gecko"]["id"] == "magnolia@12.34"
assert manifest["optional_permissions"] == ["*://*/*"]
assert "*://*/*" not in manifest["permissions"]

with tempfile.TemporaryDirectory(prefix="bpc-signature-") as temporary:
    root = Path(temporary)
    profile = root / "profile"
    profile.mkdir()
    # Signature enforcement stays enabled. No extension is installed in this
    # disposable profile, and the Nix sandbox has no external network access.
    (profile / "user.js").write_text(
        'user_pref("xpinstall.signatures.required", true);\n'
    )
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]

    def request(method, path, data=None):
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}{path}",
            data=json.dumps(data).encode() if data is not None else None,
            method=method,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=40) as response:
            return json.load(response)["value"]

    with (root / "geckodriver.log").open("w+") as log:
        driver = subprocess.Popen(
            [os.environ["GECKODRIVER"], "--port", str(port), "--allow-system-access"],
            env=os.environ
            | {
                "HOME": str(root),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_CACHE_HOME": str(root / "cache"),
                "MOZ_HEADLESS": "1",
                "MOZ_DISABLE_CONTENT_SANDBOX": "1",
            },
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        prefix = None
        try:
            for _ in range(150):
                try:
                    if request("GET", "/status")["ready"]:
                        break
                except OSError:
                    pass
                time.sleep(0.1)
            else:
                raise AssertionError("GeckoDriver did not become ready")
            session = request(
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
            prefix = "/session/" + session["sessionId"]
            request("POST", prefix + "/moz/context", {"context": "chrome"})
            result = request(
                "POST",
                prefix + "/execute/async",
                {
                    "args": [str(xpi)],
                    "script": """
                        const done = arguments[arguments.length - 1];
                        const {AddonManager} = ChromeUtils.importESModule(
                            "resource://gre/modules/AddonManager.sys.mjs");
                        const file = Cc["@mozilla.org/file/local;1"]
                            .createInstance(Ci.nsIFile);
                        file.initWithPath(arguments[0]);
                        // Inspect only: do not call install.install().
                        AddonManager.getInstallForFile(file).then(async install => {
                            const existing = await AddonManager.getAddonByID("magnolia@12.34");
                            done({error: install.error, id: install.addon?.id,
                                signedState: install.addon?.signedState,
                                expected: AddonManager.SIGNEDSTATE_SIGNED,
                                installed: !!existing});
                            install.cancel();
                        }).catch(error => done({failure: String(error)}));
                    """,
                },
            )
            assert result.get("id") == "magnolia@12.34", result
            assert result["error"] == 0, result
            assert result["signedState"] == result["expected"], result
            assert not result["installed"], result
            print("Mozilla signature verified; BPC was not installed or executed.")
        except Exception:
            log.flush()
            print((root / "geckodriver.log").read_text())
            raise
        finally:
            if prefix:
                try:
                    request("DELETE", prefix)
                except OSError:
                    pass
            driver.terminate()
            try:
                driver.wait(timeout=10)
            except subprocess.TimeoutExpired:
                driver.kill()
                driver.wait()
