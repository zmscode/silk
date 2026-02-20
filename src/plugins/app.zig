const std = @import("std");
const sriracha = @import("sriracha");
const ipc = @import("../ipc/router.zig");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:app/version", version);
    try router.register("silk:app/platform", platform);
    try router.register("silk:app/quit", quit);
}

fn version(_: *ipc.Context, _: std.json.Value) !std.json.Value {
    return .{ .string = "0.1.0" };
}

fn platform(_: *ipc.Context, _: std.json.Value) !std.json.Value {
    return .{ .string = @tagName(@import("builtin").os.tag) };
}

fn quit(_: *ipc.Context, _: std.json.Value) !std.json.Value {
    sriracha.app.terminate();
    return .{ .null = {} };
}
