const std = @import("std");
const sriracha = @import("sriracha");
const ipc = @import("../ipc/router.zig");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:window/getFrame", getFrame);
    try router.register("silk:window/setTitle", setTitle);
    try router.register("silk:window/setSize", setSize);
    try router.register("silk:window/show", show);
    try router.register("silk:window/hide", hide);
    try router.register("silk:window/center", center);
}

fn getWindow(ctx: *ipc.Context) *sriracha.Window {
    return @ptrCast(@alignCast(ctx.window));
}

fn getFrame(ctx: *ipc.Context, _: std.json.Value) !std.json.Value {
    const frame = getWindow(ctx).getFrame();

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("x", .{ .float = frame.origin.x });
    try obj.put("y", .{ .float = frame.origin.y });
    try obj.put("width", .{ .float = frame.size.width });
    try obj.put("height", .{ .float = frame.size.height });
    return .{ .object = obj };
}

fn setTitle(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    const title = getStringArg(args, "title") orelse return error.MissingTitle;
    getWindow(ctx).setTitle(title);
    return .{ .null = {} };
}

fn setSize(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    const width = getNumberArg(args, "width") orelse return error.MissingWidth;
    const height = getNumberArg(args, "height") orelse return error.MissingHeight;
    const animate = getBoolArg(args, "animate") orelse false;

    const w = getWindow(ctx);
    const frame = w.getFrame();
    w.setFrame(frame.origin.x, frame.origin.y, width, height, animate);
    return .{ .null = {} };
}

fn show(ctx: *ipc.Context, _: std.json.Value) !std.json.Value {
    getWindow(ctx).show();
    return .{ .null = {} };
}

fn hide(ctx: *ipc.Context, _: std.json.Value) !std.json.Value {
    getWindow(ctx).hide();
    return .{ .null = {} };
}

fn center(ctx: *ipc.Context, _: std.json.Value) !std.json.Value {
    getWindow(ctx).center();
    return .{ .null = {} };
}

fn getObject(v: std.json.Value) ?std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
        else => null,
    };
}

fn getStringArg(v: std.json.Value, key: []const u8) ?[]const u8 {
    const obj = getObject(v) orelse return null;
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn getNumberArg(v: std.json.Value, key: []const u8) ?f64 {
    const obj = getObject(v) orelse return null;
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => null,
    };
}

fn getBoolArg(v: std.json.Value, key: []const u8) ?bool {
    const obj = getObject(v) orelse return null;
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .bool => |b| b,
        else => null,
    };
}
