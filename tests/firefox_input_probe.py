"""WebDriver inspection only; physical keystrokes come from the marked VM."""

import json
import sys
import urllib.request
from pathlib import Path
from urllib.error import HTTPError

assert Path("/etc/mac-input-vm").exists(), "Refusing non-VM browser control"
SESSION = Path("/run/mac-input/firefox-session")


def request(method, path, value=None):
    payload = None if value is None else json.dumps(value).encode()
    query = urllib.request.Request(
        "http://127.0.0.1:4444" + path,
        data=payload,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(query, timeout=45) as response:
            result = json.load(response)["value"]
    except HTTPError as error:
        raise AssertionError(error.read().decode()) from error
    assert not (isinstance(result, dict) and "error" in result), result
    return result


def execute(script):
    return request(
        "POST",
        "/session/" + SESSION.read_text() + "/execute/sync",
        {"script": script, "args": []},
    )


def main():
    action = sys.argv[1]
    if action == "start":
        preferences = json.loads(Path(sys.argv[3]).read_text())
        preferences |= {
            "browser.startup.homepage_override.mstone": "ignore",
            "browser.shell.checkDefaultBrowser": False,
            "browser.startup.page": 0,
        }
        session = request(
            "POST",
            "/session",
            {
                "capabilities": {
                    "alwaysMatch": {
                        "browserName": "firefox",
                        "moz:firefoxOptions": {
                            "binary": sys.argv[2],
                            "args": ["--no-remote"],
                            "prefs": preferences,
                        },
                    }
                }
            },
        )
        SESSION.write_text(session["sessionId"])
        request(
            "POST",
            "/session/" + session["sessionId"] + "/moz/context",
            {"context": "chrome"},
        )
    elif action == "prepare":
        execute(
            "gURLBar.focus(); gURLBar.value = 'alpha beta';"
            "gURLBar.inputField.setSelectionRange(10, 10);"
        )
    elif action == "state":
        print(
            json.dumps(
                execute(
                    "return {value: gURLBar.value, "
                    "start: gURLBar.inputField.selectionStart, "
                    "end: gURLBar.inputField.selectionEnd, "
                    "tabs: gBrowser.tabs.length};"
                )
            )
        )
    elif action == "close":
        request("DELETE", "/session/" + SESSION.read_text())
    else:
        raise ValueError(action)


if __name__ == "__main__":
    main()
