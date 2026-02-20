const std = @import("std");
const ipc = @import("../ipc/router.zig");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:fs/readText", readText);
    try router.register("silk:fs/writeText", writeText);
    try router.register("silk:fs/listDir", listDir);
    try router.register("silk:fs/stat", stat);
}

fn readText(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    const path = getStringArg(args, "path") orelse return error.MissingPath;
    if (!ctx.permissions.canReadPath(path)) return error.ReadPathDenied;

    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, ctx.allocator, .limited(16 * 1024 * 1024));
    return .{ .string = contents };
}

fn writeText(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    const path = getStringArg(args, "path") orelse return error.MissingPath;
    const content = getStringArg(args, "content") orelse return error.MissingContent;
    if (!ctx.permissions.canWritePath(path)) return error.WritePathDenied;

    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = content,
        .flags = .{},
    });

    return .{ .null = {} };
}

fn listDir(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    const path = getStringArg(args, "path") orelse ".";
    if (!ctx.permissions.canReadPath(path)) return error.ReadPathDenied;
    const io = std.Io.Threaded.global_single_threaded.ioBasic();

    var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true, .access_sub_paths = false });
    defer dir.close(io);

    var it = dir.iterate();
    var arr = std.json.Array.init(ctx.allocator);

    while (try it.next(io)) |entry| {
        var item = std.json.ObjectMap.init(ctx.allocator);
        const name = try ctx.allocator.dupe(u8, entry.name);
        try item.put("name", .{ .string = name });
        try item.put("kind", .{ .string = @tagName(entry.kind) });
        try arr.append(.{ .object = item });
    }
    return .{ .array = arr };
}

fn stat(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    const path = getStringArg(args, "path") orelse return error.MissingPath;
    if (!ctx.permissions.canReadPath(path)) return error.ReadPathDenied;

    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    const meta = try std.Io.Dir.cwd().statFile(io, path, .{});

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("size", .{ .integer = @intCast(meta.size) });
    try obj.put("kind", .{ .string = @tagName(meta.kind) });
    try obj.put("nlink", .{ .integer = @intCast(meta.nlink) });
    try obj.put("mtime_ns", .{ .integer = @intCast(meta.mtime.nanoseconds) });
    try obj.put("ctime_ns", .{ .integer = @intCast(meta.ctime.nanoseconds) });
    if (meta.atime) |atime| {
        try obj.put("atime_ns", .{ .integer = @intCast(atime.nanoseconds) });
    } else {
        try obj.put("atime_ns", .{ .null = {} });
    }

    return .{ .object = obj };
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
