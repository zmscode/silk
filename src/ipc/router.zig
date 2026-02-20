const std = @import("std");
const protocol = @import("message.zig");
const perms = @import("../permissions.zig");

pub const InvokeRequest = protocol.InvokeRequest;

pub const Context = struct {
    allocator: std.mem.Allocator,
    webview: *anyopaque,
    window: *anyopaque,
    permissions: *const perms.Permissions,
};

pub const HandlerFn = *const fn (ctx: *Context, args: std.json.Value) anyerror!std.json.Value;

pub const Router = struct {
    allocator: std.mem.Allocator,
    handlers: std.StringHashMap(HandlerFn),

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{
            .allocator = allocator,
            .handlers = std.StringHashMap(HandlerFn).init(allocator),
        };
    }

    pub fn deinit(self: *Router) void {
        self.handlers.deinit();
    }

    pub fn register(self: *Router, cmd: []const u8, handler: HandlerFn) !void {
        try self.handlers.put(cmd, handler);
    }

    pub fn hasHandler(self: *Router, cmd: []const u8) bool {
        return self.handlers.contains(cmd);
    }

    /// Returns a heap-allocated JS eval string:
    /// window.__silk.__dispatch({...})
    pub fn dispatch(self: *Router, ctx: *Context, req: InvokeRequest) ![]u8 {
        if (!ctx.permissions.allows(req.cmd)) {
            return self.buildDispatch(req.callback, false, std.json.Value{ .null = {} }, "Command denied by permissions");
        }

        const handler = self.handlers.get(req.cmd) orelse {
            return self.buildDispatch(req.callback, false, std.json.Value{ .null = {} }, "Command not found");
        };

        const result = handler(ctx, req.args) catch |err| {
            return self.buildDispatch(req.callback, false, std.json.Value{ .null = {} }, @errorName(err));
        };

        return self.buildDispatch(req.callback, true, result, null);
    }

    pub fn buildSuccessScript(self: *Router, callback: i64, result: std.json.Value) ![]u8 {
        return self.buildDispatch(callback, true, result, null);
    }

    pub fn buildErrorScript(self: *Router, callback: i64, err_msg: []const u8) ![]u8 {
        return self.buildDispatch(callback, false, .{ .null = {} }, err_msg);
    }

    fn buildDispatch(self: *Router, callback: i64, ok: bool, result: std.json.Value, err_msg: ?[]const u8) ![]u8 {
        var payload_obj = std.json.ObjectMap.init(self.allocator);
        defer payload_obj.deinit();

        try payload_obj.put("kind", std.json.Value{ .string = "response" });
        try payload_obj.put("callback", std.json.Value{ .integer = callback });
        try payload_obj.put("ok", std.json.Value{ .bool = ok });

        if (ok) {
            try payload_obj.put("result", result);
        } else {
            try payload_obj.put("error", std.json.Value{ .string = err_msg orelse "Silk command failed" });
        }

        const payload_json = try std.json.Stringify.valueAlloc(
            self.allocator,
            std.json.Value{ .object = payload_obj },
            .{},
        );
        defer self.allocator.free(payload_json);

        return std.fmt.allocPrint(
            self.allocator,
            "window.__silk && window.__silk.__dispatch({s});",
            .{payload_json},
        );
    }
};
