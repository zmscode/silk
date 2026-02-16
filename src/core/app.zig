//! Application State
//!
//! Central struct holding all runtime state for a Silk application.
//! A global pointer (`g_app`) is used so ObjC callbacks can access it.

const std = @import("std");
const silk = @import("silk");
const ipc = @import("../ipc/ipc.zig");
const Router = @import("../ipc/router.zig").Router;
const Scope = @import("permissions.zig").Scope;
const macos_window = @import("../backend/macos/window.zig");
const macos_webview = @import("../backend/macos/webview.zig");

// Plugins
const fs_plugin = @import("../plugins/fs.zig");
const clipboard_plugin = @import("../plugins/clipboard.zig");
const shell_plugin = @import("../plugins/shell.zig");
const dialog_plugin = @import("../plugins/dialog.zig");
const window_plugin = @import("../plugins/window_plugin.zig");
const user_commands = @import("user_commands");

pub const AppState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    router: Router,
    window: ?macos_window.Window = null,
    webview: ?macos_webview.WebView = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) AppState {
        return .{
            .allocator = allocator,
            .io = io,
            .router = Router.init(allocator),
        };
    }

    /// Register all built-in plugins and grant default permissions.
    pub fn setup(self: *AppState) void {
        // Register built-in plugin commands
        fs_plugin.register(&self.router);
        clipboard_plugin.register(&self.router);
        shell_plugin.register(&self.router);
        dialog_plugin.register(&self.router);
        window_plugin.register(&self.router);

        // Register custom user commands (no-op if no user module provided)
        var user_router = silk.Router{
            .ptr = @ptrCast(&self.router),
            .register_fn = &routerRegisterBridge,
        };
        user_commands.setup(&user_router);

        // Grant default permissions (all access for development)
        self.router.permissions.grant("fs", Scope.all) catch {};
        self.router.permissions.grant("clipboard", Scope.all) catch {};
        self.router.permissions.grant("shell", Scope.all) catch {};
        self.router.permissions.grant("dialog", Scope.all) catch {};
        self.router.permissions.grant("window", Scope.all) catch {};
    }

    pub fn deinit(self: *AppState) void {
        if (self.webview) |*wv| wv.deinit();
        self.router.deinit();
        self.webview = null;
        self.window = null;
    }
};

/// Bridge function: adapts silk.Router.register() calls to the internal Router.
fn routerRegisterBridge(ptr: *anyopaque, method: []const u8, handler: silk.HandlerFn, permission: ?[]const u8) void {
    const router: *Router = @ptrCast(@alignCast(ptr));
    router.register(method, handler, permission);
}

/// Global app state pointer — accessible from ObjC callbacks.
pub var g_app: ?*AppState = null;

/// Handle an IPC message from the webview. Wired as the `MessageCallback`.
pub fn handleMessage(raw_json: []const u8) ?[]const u8 {
    const app = g_app orelse return null;
    const allocator = app.allocator;

    const result = ipc.parseMessage(allocator, raw_json) catch |err| {
        std.log.err("IPC parse error: {}", .{err});
        return ipc.serializeResponse(allocator, .{ .err = .{
            .id = 0,
            .@"error" = .{ .code = "PARSE_ERROR", .message = "Failed to parse IPC message" },
        } }) catch null;
    };
    defer result.parsed.deinit();

    switch (result.message) {
        .command => |cmd| return app.router.dispatch(allocator, app.io, cmd),
        .event => return null,
    }
}
