const std = @import("std");
const ipc = @import("../ipc/router.zig");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:ping", ping);
    try router.register("silk:appInfo", appInfo);
}

fn ping(_: *ipc.Context, _: std.json.Value) !std.json.Value {
    return std.json.Value{ .string = "pong" };
}

fn appInfo(ctx: *ipc.Context, _: std.json.Value) !std.json.Value {
    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("name", std.json.Value{ .string = "Silk" });
    try obj.put("version", std.json.Value{ .string = "0.1.0" });
    try obj.put("platform", std.json.Value{ .string = @tagName(@import("builtin").os.tag) });
    try obj.put("arch", std.json.Value{ .string = @tagName(@import("builtin").cpu.arch) });
    return std.json.Value{ .object = obj };
}
