const std = @import("std");
const ipc = @import("../ipc/router.zig");
const builtin = @import("builtin");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:dialog/open", open);
    try router.register("silk:dialog/save", save);
    try router.register("silk:dialog/message", message);
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

    return runPathDialog(ctx, script, multiple);
}

fn save(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    if (builtin.os.tag != .macos) return error.UnsupportedPlatform;
    const default_name = getStringArg(args, "default_name") orelse "untitled.txt";

    const script = try std.fmt.allocPrint(
        ctx.allocator,
        "POSIX path of (choose file name default name \"{s}\")",
        .{escapeAppleScript(default_name)},
    );
    defer ctx.allocator.free(script);

    return runPathDialog(ctx, script, false);
}

fn message(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    if (builtin.os.tag != .macos) return error.UnsupportedPlatform;

    const text = getStringArg(args, "text") orelse return error.MissingMessageText;
    const title = getStringArg(args, "title") orelse "Silk";
    const level = getStringArg(args, "level") orelse "info";

    const icon = if (std.mem.eql(u8, level, "error"))
        "stop"
    else if (std.mem.eql(u8, level, "warning"))
        "caution"
    else
        "note";

    const script = try std.fmt.allocPrint(
        ctx.allocator,
        "set r to display dialog \"{s}\" with title \"{s}\" buttons {{\"Cancel\", \"OK\"}} default button \"OK\" with icon {s}\nreturn button returned of r",
        .{ escapeAppleScript(text), escapeAppleScript(title), icon },
    );
    defer ctx.allocator.free(script);

    const result = try runAppleScript(ctx, script);
    defer {
        ctx.allocator.free(result.stdout);
        ctx.allocator.free(result.stderr);
    }

    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                if (std.mem.indexOf(u8, result.stderr, "(-128)")) |_| {
                    return .{ .string = "Cancel" };
                }
                return error.DialogCommandFailed;
            }
        },
        else => return error.DialogCommandFailed,
    }

    const button = std.mem.trim(u8, result.stdout, " \r\n\t");
    return .{ .string = try ctx.allocator.dupe(u8, button) };
}

fn runPathDialog(ctx: *ipc.Context, script: []const u8, multiple: bool) !std.json.Value {
    const result = try runAppleScript(ctx, script);
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

fn runAppleScript(ctx: *ipc.Context, script: []const u8) !std.process.RunResult {
    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    return std.process.run(ctx.allocator, io, .{
        .argv = &.{ "osascript", "-e", script },
        .max_output_bytes = 1024 * 1024,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.OsascriptNotFound,
        else => return err,
    };
}

fn escapeAppleScript(input: []const u8) []const u8 {
    // Keeps parser simple for now: reject quotes/backslashes that would alter script structure.
    if (std.mem.indexOfAny(u8, input, "\\\"") != null) return "";
    return input;
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

fn getBoolArg(v: std.json.Value, key: []const u8) ?bool {
    const obj = getObject(v) orelse return null;
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .bool => |b| b,
        else => null,
    };
}
