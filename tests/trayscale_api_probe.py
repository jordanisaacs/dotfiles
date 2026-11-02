"""Exercise actual Trayscale subscription flags against an isolated tailscaled."""

import http.client
import re
import socket
from pathlib import Path


class LocalAPI(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(10)
        self.sock.connect("/run/tailscale/tailscaled.sock")


def watch_mask(poller: Path, sdk: Path) -> int:
    # Read the shipped source and its exact vendored SDK: no copied wire bits.
    declaration = re.search(
        r"const watcherOpts\s*=\s*(.*?)\n\s*watch:", poller.read_text(), re.DOTALL
    )
    assert declaration is not None, "Trayscale watch-mask declaration changed"
    names = re.findall(r"ipn\.(Notify\w+)", declaration.group(1))
    assert names, "No subscription flags found"
    constants = {
        name: 1 << int(shift)
        for name, shift in re.findall(
            r"(Notify\w+)\s+NotifyWatchOpt\s*=\s*1\s*<<\s*(\d+)",
            sdk.read_text(),
        )
    }
    mask = 0
    for name in names:
        mask |= constants[name]
    return mask


def subscribe(mask: int) -> tuple[int, str]:
    connection = LocalAPI("local-tailscaled.sock", timeout=10)
    try:
        connection.request("GET", f"/localapi/v0/watch-ipn-bus?mask={mask}")
        response = connection.getresponse()
        # A successful watch is a stream: checking headers is enough. Never
        # consume its body, even though this VM has no real tailnet profile.
        error = response.read(4096).decode() if response.status != 200 else ""
        return response.status, error
    finally:
        connection.close()


sdk_source = Path("/etc/trayscale-sdk-backend.go")
stock_mask = watch_mask(Path("/etc/trayscale-stock-poller.go"), sdk_source)
fixed_mask = watch_mask(Path("/etc/trayscale-fixed-poller.go"), sdk_source)

status, error = subscribe(stock_mask)
assert status == 400, (status, error)
assert "NotifyInitialNetMap" in error, error
assert "no longer supported" in error, error
print("Unpatched Trayscale reproduces HTTP 400 from the actual daemon")

status, error = subscribe(fixed_mask)
assert status == 200, (status, error)
print("Patched Trayscale subscription is accepted (HTTP 200)")
