//! Filesystem Plugin
//!
//! Provides 7 IPC commands for file system access:
//! fs:read, fs:write, fs:exists, fs:readDir, fs:mkdir, fs:remove, fs:stat

const std = @import("std");
const Router = @import("../ipc/router.zig").Router;
const Context = @import("../core/context.zig").Context;
const Scope = @import("../core/permissions.zig").Scope;

const Dir = std.Io.Dir;

/// Register all fs commands on the router.
pub fn register(router: *Router) void {
    router.register("fs:read", &readFile, "fs");
    router.register("fs:write", &writeFile, "fs");
    router.register("fs:exists", &exists, "fs");
    router.register("fs:readDir", &readDir, "fs");
    router.register("fs:mkdir", &mkdir, "fs");
    router.register("fs:remove", &remove, "fs");
    router.register("fs:stat", &fileStat, "fs");
}

// ─── Helpers ────────────────────────────────────────────────────────────

/// Validate a path: reject directory traversal (`..`) and enforce allowed-paths scope.
fn validatePath(path: []const u8) !void {
    // Reject paths containing ".." segments
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return error.PermissionDenied;
    }

    // Check path scope from permissions (if configured)
    const app_mod = @import("../core/app.zig");
    const app = app_mod.g_app orelse return;
    const scope = app.router.permissions.getScope("fs") orelse return;
    switch (scope) {
        .paths => |allowed| {
            for (allowed) |prefix| {
                if (std.mem.startsWith(u8, path, prefix)) return;
            }
            return error.PermissionDenied;
        },
        else => {},
    }
}

fn getStringParam(params: std.json.Value, key: []const u8) ![]const u8 {
    if (params != .object) return error.InvalidParams;
    const val = params.object.get(key) orelse return error.InvalidParams;
    if (val != .string) return error.InvalidParams;
    return val.string;
}

fn getBoolParam(params: std.json.Value, key: []const u8, default: bool) bool {
    if (params != .object) return default;
    const val = params.object.get(key) orelse return default;
    if (val != .bool) return default;
    return val.bool;
}

fn jsonObject(allocator: std.mem.Allocator) std.json.ObjectMap {
    return std.json.ObjectMap.init(allocator);
}

// ─── Command Handlers ───────────────────────────────────────────────────

fn readFile(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const path = try getStringParam(params, "path");
    try validatePath(path);

    const file = try Dir.openFileAbsolute(ctx.io, path, .{});
    defer file.close(ctx.io);

    const metadata = try file.stat(ctx.io);
    const size: usize = @intCast(metadata.size);
    if (size > 10 * 1024 * 1024) return error.FileTooLarge;

    const contents = try ctx.allocator.alloc(u8, size);
    const bytes_read = try file.readPositionalAll(ctx.io, contents, 0);

    var obj = jsonObject(ctx.allocator);
    try obj.put("contents", .{ .string = contents[0..bytes_read] });
    return .{ .object = obj };
}

fn writeFile(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const path = try getStringParam(params, "path");
    try validatePath(path);
    const contents = try getStringParam(params, "contents");

    Dir.cwd().writeFile(ctx.io, .{
        .sub_path = path,
        .data = contents,
    }) catch |e| return e;

    var obj = jsonObject(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    try obj.put("bytesWritten", .{ .integer = @intCast(contents.len) });
    return .{ .object = obj };
}

fn exists(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const path = try getStringParam(params, "path");
    try validatePath(path);

    const result = blk: {
        Dir.cwd().access(ctx.io, path, .{}) catch break :blk false;
        break :blk true;
    };

    var obj = jsonObject(ctx.allocator);
    try obj.put("exists", .{ .bool = result });
    return .{ .object = obj };
}

fn readDir(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const path = try getStringParam(params, "path");
    try validatePath(path);

    var dir = try Dir.cwd().openDir(ctx.io, path, .{ .iterate = true });
    defer dir.close(ctx.io);

    var entries = std.json.Array.init(ctx.allocator);
    var iter = dir.iterate();
    while (try iter.next(ctx.io)) |entry| {
        var entry_obj = jsonObject(ctx.allocator);
        const name = try ctx.allocator.dupe(u8, entry.name);
        try entry_obj.put("name", .{ .string = name });
        try entry_obj.put("isDir", .{ .bool = entry.kind == .directory });
        try entries.append(.{ .object = entry_obj });
    }

    var obj = jsonObject(ctx.allocator);
    try obj.put("entries", .{ .array = entries });
    return .{ .object = obj };
}

fn mkdir(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const path = try getStringParam(params, "path");
    try validatePath(path);
    const recursive = getBoolParam(params, "recursive", false);

    if (recursive) {
        try Dir.cwd().createDirPath(ctx.io, path);
    } else {
        try Dir.cwd().createDir(ctx.io, path, .default_dir);
    }

    var obj = jsonObject(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

fn remove(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const path = try getStringParam(params, "path");
    try validatePath(path);
    const recursive = getBoolParam(params, "recursive", false);

    if (recursive) {
        try Dir.cwd().deleteTree(ctx.io, path);
    } else {
        Dir.cwd().deleteFile(ctx.io, path) catch |e| {
            if (e == error.IsDir) {
                try Dir.cwd().deleteDir(ctx.io, path);
            } else {
                return e;
            }
        };
    }

    var obj = jsonObject(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

fn fileStat(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const path = try getStringParam(params, "path");
    try validatePath(path);

    const file = try Dir.openFileAbsolute(ctx.io, path, .{});
    defer file.close(ctx.io);
    const metadata = try file.stat(ctx.io);

    var obj = jsonObject(ctx.allocator);
    try obj.put("size", .{ .integer = @intCast(metadata.size) });
    try obj.put("isDir", .{ .bool = metadata.kind == .directory });
    try obj.put("isFile", .{ .bool = metadata.kind == .file });
    return .{ .object = obj };
}
