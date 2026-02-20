const std = @import("std");
const ipc = @import("../ipc/router.zig");
const builtin = @import("builtin");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:dialog/open", open);
}

fn open(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    if (builtin.os.tag != .macos) return error.UnsupportedPlatform;

    const pick_folder = getBoolArg(args, "directory") orelse false;
    const multiple = getBoolArg(args, "multiple") orelse false;

    const script = if (pick_folder)
        if (multiple)
            "set items to choose folder with multiple selections allowed\nset out to \"\"\nrepeat with f in items\nset out to out & POSIX path of f & linefeed\nend repeat\nreturn out"
        else
            "POSIX path of (choose folder)"
    else if (multiple)
        "set items to choose file with multiple selections allowed\nset out to \"\"\nrepeat with f in items\nset out to out & POSIX path of f & linefeed\nend repeat\nreturn out"
    else
        "POSIX path of (choose file)";

    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    const result = std.process.run(ctx.allocator, io, .{
        .argv = &.{ "osascript", "-e", script },
        .max_output_bytes = 1024 * 1024,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.OsascriptNotFound,
        else => return err,
    };
    defer {
        ctx.allocator.free(result.stdout);
        ctx.allocator.free(result.stderr);
    }

    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                if (std.mem.indexOf(u8, result.stderr, "(-128)")) |_| {
                    return .{ .null = {} };
                }
                return error.DialogCommandFailed;
            }
        },
        else => return error.DialogCommandFailed,
    }

    if (multiple) {
        var arr = std.json.Array.init(ctx.allocator);
        var it = std.mem.splitScalar(u8, result.stdout, '\n');
        while (it.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \r\n\t");
            if (line.len == 0) continue;
            const owned = try ctx.allocator.dupe(u8, line);
            try arr.append(.{ .string = owned });
        }
        return .{ .array = arr };
    }

    const path = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (path.len == 0) return .{ .null = {} };
    return .{ .string = try ctx.allocator.dupe(u8, path) };
}

fn getObject(v: std.json.Value) ?std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
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
