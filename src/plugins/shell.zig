const std = @import("std");
const ipc = @import("../ipc/router.zig");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:shell/exec", exec);
}

fn exec(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    const cmd = getStringArg(args, "cmd") orelse return error.MissingCommand;
    const cwd = getStringArg(args, "cwd");
    const max_output = getIntegerArg(args, "max_output_bytes") orelse 1024 * 1024;

    const argv = try parseArgv(ctx.allocator, cmd, args);
    defer ctx.allocator.free(argv);

    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    const result = try std.process.run(ctx.allocator, io, .{
        .argv = argv,
        .cwd = cwd,
        .max_output_bytes = @intCast(max_output),
    });
    defer {
        ctx.allocator.free(result.stdout);
        ctx.allocator.free(result.stderr);
    }

    var out = std.json.ObjectMap.init(ctx.allocator);
    try out.put("stdout", .{ .string = result.stdout });
    try out.put("stderr", .{ .string = result.stderr });
    switch (result.term) {
        .exited => |code| {
            try out.put("code", .{ .integer = code });
            try out.put("ok", .{ .bool = code == 0 });
        },
        .signal => |sig| {
            try out.put("ok", .{ .bool = false });
            try out.put("signal", .{ .string = @tagName(sig) });
        },
        .stopped => |code| {
            try out.put("ok", .{ .bool = false });
            try out.put("stopped", .{ .integer = @intCast(code) });
        },
        .unknown => |code| {
            try out.put("ok", .{ .bool = false });
            try out.put("unknown", .{ .integer = @intCast(code) });
        },
    }

    return .{ .object = out };
}

fn parseArgv(allocator: std.mem.Allocator, cmd: []const u8, args: std.json.Value) ![]const []const u8 {
    if (getArray(args, "args")) |arr| {
        const argv = try allocator.alloc([]const u8, arr.len + 1);
        argv[0] = cmd;
        for (arr, 0..) |item, i| {
            argv[i + 1] = switch (item) {
                .string => |s| s,
                else => return error.InvalidArgumentArray,
            };
        }
        return argv;
    }

    const argv = try allocator.alloc([]const u8, 1);
    argv[0] = cmd;
    return argv;
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

fn getIntegerArg(v: std.json.Value, key: []const u8) ?i64 {
    const obj = getObject(v) orelse return null;
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => null,
    };
}

fn getArray(v: std.json.Value, key: []const u8) ?[]const std.json.Value {
    const obj = getObject(v) orelse return null;
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .array => |a| a.items,
        else => null,
    };
}
