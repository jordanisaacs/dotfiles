"""Build a native probe of the actual Trayscale monitor initialization."""

import os
import re
import subprocess
import sys
from pathlib import Path

source, vendor, compiler, output = map(Path, sys.argv[1:])
workspace = Path("probe").absolute()
workspace.mkdir()
os.chdir(workspace)
initializer = re.search(
    r"func initMonitor\(\) \*netmon\.Monitor \{.*?\n\}",
    (source / "internal/tsutil/client.go").read_text(),
    re.DOTALL,
)
assert initializer, "Trayscale monitor initialization changed"

Path("go.mod").write_text((source / "go.mod").read_text())
Path("go.sum").write_text((source / "go.sum").read_text())
Path("vendor").symlink_to(vendor)
Path("main.go").write_text(
    """package main
import (
    "fmt"
    "log/slog"
    "os"
    "time"
    "tailscale.com/net/netmon"
    "tailscale.com/types/logger"
    "tailscale.com/util/eventbus"
)
var bus = eventbus.New()
"""
    + initializer.group(0)
    + """
func main() {
    monitor := initMonitor()
    if monitor == nil { panic("monitor initialization failed") }
    defer monitor.Close()
    if monitor.InterfaceState().HaveV6 { panic("fixture already has public IPv6") }
    if err := os.WriteFile("/run/trayscale-monitor-ready", nil, 0600); err != nil { panic(err) }
    deadline := time.Now().Add(15 * time.Second)
    for time.Now().Before(deadline) {
        if monitor.InterfaceState().HaveV6 {
            fmt.Println("monitor observed the new native IPv6 address")
            return
        }
        time.Sleep(50 * time.Millisecond)
    }
    panic("Trayscale monitor retained its startup snapshot after IPv6 appeared")
}
"""
)
output.parent.mkdir(parents=True, exist_ok=True)
environment = os.environ | {
    "GOCACHE": str(Path.cwd() / ".go-cache"),
    "GOPATH": str(Path.cwd() / ".go-path"),
    "GOPROXY": "off",
    "GOSUMDB": "off",
    "GOTOOLCHAIN": "local",
    "CGO_ENABLED": "0",
}
subprocess.run(
    [str(compiler), "build", "-mod=vendor", "-trimpath", "-o", str(output), "."],
    env=environment,
    check=True,
)
