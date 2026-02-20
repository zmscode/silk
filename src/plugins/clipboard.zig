const std = @import("std");
const ipc = @import("../ipc/router.zig");
const builtin = @import("builtin");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:clipboard/readText", readText);
    try router.register("silk:clipboard/writeText", writeText);
}

fn readText(ctx: *ipc.Context, _: std.json.Value) !std.json.Value {
    if (builtin.os.tag != .macos) return error.UnsupportedPlatform;

    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    const result = try std.process.run(ctx.allocator, io, .{
        .argv = &.{"pbpaste"},
        .max_output_bytes = 1024 * 1024,
    });
    defer {
        ctx.allocator.free(result.stdout);
        ctx.allocator.free(result.stderr);
    }

    switch (result.term) {
        .exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }

    return .{ .string = result.stdout };
}

fn writeText(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    if (builtin.os.tag != .macos) return error.UnsupportedPlatform;
    const text = getStringArg(args, "text") orelse return error.MissingText;

    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    var child = try std.process.spawn(io, .{
        .argv = &.{"pbcopy"},
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(io);

    try child.stdin.?.writeStreamingAll(io, text);
    child.stdin.?.close(io);
    child.stdin = null;

    var stdout: std.ArrayList(u8) = .empty;
    defer stdout.deinit(ctx.allocator);
    var stderr: std.ArrayList(u8) = .empty;
    defer stderr.deinit(ctx.allocator);
    try child.collectOutput(ctx.allocator, &stdout, &stderr, 1024 * 1024);

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }
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
