"""Prepare a private Firefox profile and read chrome geometry and input."""

import json
import socket
import sys
from pathlib import Path


class Marionette:
    def __init__(self):
        endpoint = ("127.0.0.1", 2828)
        self.connection = socket.create_connection(endpoint, timeout=5)
        self.read()
        self.identifier = 0

    def read(self):
        size = b""
        while not size.endswith(b":"):
            value = self.connection.recv(1)
            if not value:
                raise EOFError("Marionette connection closed")
            size += value
        payload = b""
        length = int(size[:-1])
        while len(payload) < length:
            value = self.connection.recv(length - len(payload))
            if not value:
                raise EOFError("Incomplete Marionette packet")
            payload += value
        return json.loads(payload)

    def call(self, method, parameters):
        self.identifier += 1
        payload = json.dumps([0, self.identifier, method, parameters]).encode()
        self.connection.sendall(str(len(payload)).encode() + b":" + payload)
        result = self.read()
        if result[2]:
            raise RuntimeError(result[2])
        return result[3]


def main():
    if sys.argv[1] == "prepare":
        profile, preferences, stylesheet = map(Path, sys.argv[2:])
        (profile / "chrome").mkdir(parents=True, exist_ok=True)
        (profile / "chrome/userChrome.css").write_text(stylesheet.read_text())
        settings = {
            "marionette.port": 2828,
            "browser.shell.checkDefaultBrowser": False,
            "browser.startup.page": 0,
            "browser.startup.homepage": "about:blank",
            "browser.startup.homepage_override.mstone": "ignore",
            "browser.aboutwelcome.enabled": False,
            "browser.tabs.warnOnClose": False,
            "browser.newtabpage.enabled": False,
            "toolkit.telemetry.reportingpolicy.firstRun": False,
        }
        text = preferences.read_text() + "\n"
        text += "".join(
            f"user_pref({json.dumps(key)}, {json.dumps(value)});\n"
            for key, value in settings.items()
        )
        (profile / "user.js").write_text(text)
        return

    client = Marionette()
    try:
        client.call("WebDriver:NewSession", {"capabilities": {}})
        client.call("Marionette:SetContext", {"value": "chrome"})
        if sys.argv[1] == "geometry":
            script = """
                let input = document.getElementById("urlbar-input");
                let r = input.getBoundingClientRect();
                return {x:r.x,y:r.y,width:r.width,height:r.height,
                        innerWidth,innerHeight,ratio:devicePixelRatio};
            """
        else:
            script = 'return document.getElementById("urlbar-input").value;'
        response = client.call(
            "WebDriver:ExecuteScript",
            {"script": script, "args": [], "newSandbox": True},
        )
        print(json.dumps(response["value"]))
    finally:
        client.connection.close()


if __name__ == "__main__":
    main()
