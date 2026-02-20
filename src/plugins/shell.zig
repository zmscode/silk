const std = @import("std");
const ipc = @import("../ipc/router.zig");

pub fn register(router: *ipc.Router) !void {
    try router.register("silk:shell/exec", exec);
}

fn exec(ctx: *ipc.Context, args: std.json.Value) !std.json.Value {
    const cmd = getStringArg(args, "cmd") orelse return error.MissingCommand;
    if (!ctx.permissions.canExecProgram(cmd)) return error.ProgramDenied;

    const cwd = getStringArg(args, "cwd");
    if (cwd) |path| {
        if (!ctx.permissions.canReadPath(path)) return error.CwdDenied;
    }

    const stdin_text = getStringArg(args, "stdin");
    const max_output_i64 = getIntegerArg(args, "max_output_bytes") orelse 1024 * 1024;
    if (max_output_i64 < 0) return error.InvalidMaxOutput;
    const max_output: usize = @intCast(max_output_i64);

    const argv = try parseArgv(ctx.allocator, cmd, args);
    defer ctx.allocator.free(argv);

    var environ_map = try parseEnvMap(ctx.allocator, args);
    defer if (environ_map) |*env| env.deinit();

    if (stdin_text) |stdin_val| {
        return runWithStdin(ctx, argv, cwd, environ_map, stdin_val, max_output);
    }

    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    const result = try std.process.run(ctx.allocator, io, .{
        .argv = argv,
        .cwd = cwd,
        .environ_map = if (environ_map) |*env| env else null,
        .max_output_bytes = max_output,
    });
    defer {
        ctx.allocator.free(result.stdout);
        ctx.allocator.free(result.stderr);
    }

    return buildResult(ctx.allocator, result.term, result.stdout, result.stderr);
}

fn runWithStdin(
    ctx: *ipc.Context,
    argv: []const []const u8,
    cwd: ?[]const u8,
    environ_map: ?std.process.Environ.Map,
    stdin_text: []const u8,
    max_output: usize,
) !std.json.Value {
    const io = std.Io.Threaded.global_single_threaded.ioBasic();

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = cwd,
        .environ_map = if (environ_map) |*env| env else null,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(io);

    try child.stdin.?.writeStreamingAll(io, stdin_text);
    child.stdin.?.close(io);
    child.stdin = null;

    var stdout: std.ArrayList(u8) = .empty;
    defer stdout.deinit(ctx.allocator);
    var stderr: std.ArrayList(u8) = .empty;
    defer stderr.deinit(ctx.allocator);

    try child.collectOutput(ctx.allocator, &stdout, &stderr, max_output);
    const term = try child.wait(io);

    return buildResult(ctx.allocator, term, stdout.items, stderr.items);
}

fn buildResult(allocator: std.mem.Allocator, term: std.process.Child.Term, stdout: []const u8, stderr: []const u8) !std.json.Value {
    var out = std.json.ObjectMap.init(allocator);
    try out.put("stdout", .{ .string = try allocator.dupe(u8, stdout) });
    try out.put("stderr", .{ .string = try allocator.dupe(u8, stderr) });

    switch (term) {
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

fn parseEnvMap(allocator: std.mem.Allocator, args: std.json.Value) !?std.process.Environ.Map {
    const obj = getObject(args) orelse return null;
    const env_val = obj.get("env") orelse return null;
    if (env_val != .object) return error.InvalidEnv;

    var env = std.process.Environ.Map.init(allocator);
    errdefer env.deinit();

    var it = env_val.object.iterator();
    while (it.next()) |entry| {
        const val = switch (entry.value_ptr.*) {
            .string => |s| s,
            else => return error.InvalidEnvValue,
        };
        try env.put(entry.key_ptr.*, val);
    }

    return env;
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
