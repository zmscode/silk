//! Silk Public API
//!
//! Shared types used by both the Silk runtime and custom user commands.
//! Available as @import("silk") in user Zig code.

const std = @import("std");

/// Request context passed to every IPC handler.
pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    window_label: []const u8 = "main",
    webview_label: []const u8 = "main",
};

/// Handler function type for IPC commands.
pub const HandlerFn = *const fn (ctx: *Context, params: std.json.Value) anyerror!std.json.Value;

/// Opaque handle to the Silk router, passed to user setup functions.
/// Provides a typed `register()` method for adding custom commands.
pub const Router = struct {
    /// Opaque pointer to the internal router.
    ptr: *anyopaque,
    /// Function pointer provided by the runtime to register commands.
    register_fn: *const fn (ptr: *anyopaque, method: []const u8, handler: HandlerFn, permission: ?[]const u8) void,

    /// Register a custom IPC command.
    pub fn register(self: Router, method: []const u8, handler: HandlerFn, permission: ?[]const u8) void {
        self.register_fn(self.ptr, method, handler, permission);
    }
};
