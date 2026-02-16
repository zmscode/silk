//! Shell Plugin
//!
//! Provides IPC commands for shell operations:
//! shell:open — Open URL/file with default app (NSWorkspace)
//! shell:exec — Execute shell command, return stdout/stderr/exitCode

const std = @import("std");
const objc = @import("objc");
const Router = @import("../ipc/router.zig").Router;
const Context = @import("../core/context.zig").Context;

pub fn register(router: *Router) void {
    router.register("shell:open", &open, "shell");
    router.register("shell:exec", &exec, "shell");
}

/// Open a URL or file path with the default application.
/// Params: { "target": "https://example.com" } or { "target": "/path/to/file" }
fn open(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    if (params != .object) return error.InvalidParams;
    const val = params.object.get("target") orelse return error.InvalidParams;
    if (val != .string) return error.InvalidParams;
    const target = val.string;

    // [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:target]]
    const workspace = objc.msgSend(objc.getClass("NSWorkspace"), objc.sel("sharedWorkspace"));
    const ns_url = objc.nsURL(target);

    // Try as URL first; if it fails, try as file path
    if (ns_url != null) {
        const open_fn: *const fn (objc.id, objc.SEL, objc.id) callconv(.c) objc.BOOL = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
        _ = open_fn(workspace, objc.sel("openURL:"), ns_url);
    }

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

/// Execute a shell command synchronously.
/// Params: { "command": "ls", "args": ["-la", "/tmp"] }
/// Returns: { "stdout": "...", "stderr": "...", "exitCode": 0 }
fn exec(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    if (params != .object) return error.InvalidParams;
    const cmd_val = params.object.get("command") orelse return error.InvalidParams;
    if (cmd_val != .string) return error.InvalidParams;
    const command = cmd_val.string;

    // Build argv: [command] ++ args
    var argv: std.ArrayList([]const u8) = .{};
    defer argv.deinit(ctx.allocator);

    try argv.append(ctx.allocator, command);

    // Parse args array if present
    if (params.object.get("args")) |args_val| {
        if (args_val == .array) {
            for (args_val.array.items) |arg| {
                if (arg == .string) {
                    try argv.append(ctx.allocator, arg.string);
                }
            }
        }
    }

    // 0.16-dev: std.process.spawn(io, options)
    var child = try std.process.spawn(ctx.io, .{
        .argv = argv.items,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Collect stdout and stderr
    var stdout_buf: std.ArrayList(u8) = .{};
    var stderr_buf: std.ArrayList(u8) = .{};
    try child.collectOutput(ctx.allocator, &stdout_buf, &stderr_buf, 1024 * 1024);
    const term = try child.wait(ctx.io);

    const exit_code: i64 = switch (term) {
        .exited => |code| @intCast(code),
        else => -1,
    };

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("stdout", .{ .string = stdout_buf.items });
    try obj.put("stderr", .{ .string = stderr_buf.items });
    try obj.put("exitCode", .{ .integer = exit_code });
    return .{ .object = obj };
}
