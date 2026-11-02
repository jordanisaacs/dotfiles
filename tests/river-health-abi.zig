const std = @import("std");
const wlr = @import("wlroots");

extern fn river_health_c_abi(index: c_uint) u64;

pub fn main() void {
    const names = [_][]const u8{
        "XdgSurface.size",               "XdgSurface.events",             "XdgSurface.client",               "XdgSurface.role_resource",
        "XdgClient.size",                "XdgClient.ping_serial",         "XdgToplevel.size",                "XdgToplevel.base",
        "ExtForeignToplevelHandle.size", "ExtForeignToplevelHandle.data", "ExtForeignToplevelHandle.events",
    };
    const values = [_]u64{
        @sizeOf(wlr.XdgSurface),
        @offsetOf(wlr.XdgSurface, "events"),
        @offsetOf(wlr.XdgSurface, "client"),
        @offsetOf(wlr.XdgSurface, "role_resource"),
        @sizeOf(wlr.XdgClient),
        @offsetOf(wlr.XdgClient, "ping_serial"),
        @sizeOf(wlr.XdgToplevel),
        @offsetOf(wlr.XdgToplevel, "base"),
        @sizeOf(wlr.ExtForeignToplevelHandleV1),
        @offsetOf(wlr.ExtForeignToplevelHandleV1, "data"),
        @offsetOf(wlr.ExtForeignToplevelHandleV1, "events"),
    };
    var matches = true;
    for (names, values, 0..) |name, zig_value, index| {
        const c_value = river_health_c_abi(@intCast(index));
        std.debug.print("{s}: C={d} Zig={d}\n", .{ name, c_value, zig_value });
        matches = matches and c_value == zig_value;
    }
    if (!matches) std.process.exit(1);
}
