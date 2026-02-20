const std = @import("std");
const ipc = @import("../ipc/router.zig");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:clipboard/readText", readText);
}

fn readText(_: *ipc.Context, _: std.json.Value) !std.json.Value {
    return error.NotImplemented;
}
