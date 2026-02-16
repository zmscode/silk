//! IPC Router
//!
//! Maps method names to handler functions and dispatches incoming
//! commands with permission checks. Returns IPC responses.

const std = @import("std");
const ipc = @import("ipc.zig");
const silk = @import("silk");
const Context = silk.Context;
const Permissions = @import("../core/permissions.zig").Permissions;

/// Handler function signature — re-exported from the shared silk module.
pub const HandlerFn = silk.HandlerFn;

/// A registered route: handler + optional permission key.
const Route = struct {
    handler: HandlerFn,
    /// Permission key to check (e.g. "fs" or "fs:read").
    /// If null, the method is always allowed (e.g. silk:ping).
    permission: ?[]const u8,
};

pub const Router = struct {
    routes: std.StringHashMap(Route),
    permissions: Permissions,
    on_before: ?*const fn (method: []const u8) void = null,
    on_after: ?*const fn (method: []const u8, success: bool) void = null,

    pub fn init(allocator: std.mem.Allocator) Router {
        var r = Router{
            .routes = std.StringHashMap(Route).init(allocator),
            .permissions = Permissions.init(allocator),
        };

        // Register built-in handlers
        r.routes.put("silk:ping", .{ .handler = &pingHandler, .permission = null }) catch {};

        return r;
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit();
        self.permissions.deinit();
    }

    /// Register an IPC method handler.
    /// `permission` is the key checked against the permission system (e.g. "fs").
    /// Pass null for methods that should always be allowed.
    pub fn register(self: *Router, method: []const u8, handler: HandlerFn, permission: ?[]const u8) void {
        self.routes.put(method, .{ .handler = handler, .permission = permission }) catch {};
    }

    /// Dispatch an IPC command. Looks up the route, checks permissions,
    /// calls the handler, and returns a serialized JSON response.
    pub fn dispatch(self: *Router, allocator: std.mem.Allocator, io: std.Io, cmd: ipc.Command) ?[]const u8 {
        if (self.on_before) |hook| hook(cmd.method);

        // Look up the route
        const route = self.routes.get(cmd.method) orelse {
            if (self.on_after) |hook| hook(cmd.method, false);
            return ipc.serializeResponse(allocator, .{ .err = .{
                .id = cmd.id,
                .@"error" = .{ .code = "METHOD_NOT_FOUND", .message = "Unknown method" },
            } }) catch null;
        };

        // Check permissions
        if (route.permission) |perm_key| {
            if (!self.permissions.check(perm_key)) {
                if (self.on_after) |hook| hook(cmd.method, false);
                return ipc.serializeResponse(allocator, .{ .err = .{
                    .id = cmd.id,
                    .@"error" = .{ .code = "PERMISSION_DENIED", .message = "Permission denied" },
                } }) catch null;
            }
        }

        // Build context
        var ctx = Context{
            .allocator = allocator,
            .io = io,
            .window_label = "main",
            .webview_label = "main",
        };

        // Call the handler
        const result = route.handler(&ctx, cmd.params) catch |err| {
            if (self.on_after) |hook| hook(cmd.method, false);
            return ipc.serializeResponse(allocator, .{ .err = .{
                .id = cmd.id,
                .@"error" = .{ .code = "INTERNAL_ERROR", .message = @errorName(err) },
            } }) catch null;
        };

        if (self.on_after) |hook| hook(cmd.method, true);
        return ipc.serializeResponse(allocator, .{ .ok = .{
            .id = cmd.id,
            .result = result,
        } }) catch null;
    }
};

// ─── Built-in Handlers ──────────────────────────────────────────────────

fn pingHandler(_: *Context, _: std.json.Value) anyerror!std.json.Value {
    return .{ .string = "pong" };
}
