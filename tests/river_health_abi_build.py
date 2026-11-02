"""Add a small ABI executable to the actual pinned River module graph."""

import shutil
import sys
from pathlib import Path

shutil.copyfile(sys.argv[1], "health-abi.zig")
shutil.copyfile(sys.argv[2], "health-abi.c")
build = Path("build.zig")
source = build.read_text()
anchor = '    const flags = b.createModule(.{ .root_source_file = b.path("common/flags.zig") });'
assert source.count(anchor) == 1
source = source.replace(
    anchor,
    """    if (b.option(bool, "health-abi-probe", "Compare pinned C and Zig health layouts") orelse false) {
        const probe = b.addExecutable(.{
            .name = "river-health-abi",
            .root_module = b.createModule(.{
                .root_source_file = b.path("health-abi.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        probe.root_module.addImport("wlroots", wlroots);
        probe.root_module.linkSystemLibrary(wlroots_pkgconf, .{});
        probe.root_module.linkSystemLibrary("wayland-server", .{});
        probe.root_module.addCSourceFile(.{ .file = b.path("health-abi.c"), .flags = &.{"-std=c11"} });
        b.installArtifact(probe);
        return;
    }

"""
    + anchor,
)
build.write_text(source)
