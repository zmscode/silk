//! Window Plugin
//!
//! Provides IPC commands for window management:
//! window:setTitle, window:setSize, window:center, window:close,
//! window:show, window:hide, window:isVisible, window:setFullscreen
//!
//! Accesses the main window via g_app global.

const std = @import("std");
const objc = @import("objc");
const Router = @import("../ipc/router.zig").Router;
const Context = @import("../core/context.zig").Context;
const app_mod = @import("../core/app.zig");

pub fn register(router: *Router) void {
    router.register("window:setTitle", &setTitle, "window");
    router.register("window:setSize", &setSize, "window");
    router.register("window:center", &center, "window");
    router.register("window:close", &close, "window");
    router.register("window:show", &show, "window");
    router.register("window:hide", &hide, "window");
    router.register("window:isVisible", &isVisible, "window");
    router.register("window:setFullscreen", &setFullscreen, "window");
}

fn getWindow() ?objc.id {
    const app = app_mod.g_app orelse return null;
    const win = app.window orelse return null;
    return win.ns_window;
}

fn setTitle(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const ns_window = getWindow() orelse return error.WindowNotFound;

    if (params != .object) return error.InvalidParams;
    const val = params.object.get("title") orelse return error.InvalidParams;
    if (val != .string) return error.InvalidParams;

    objc.msgSend_id_void(ns_window, objc.sel("setTitle:"), objc.nsString(val.string));

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

fn setSize(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const ns_window = getWindow() orelse return error.WindowNotFound;

    if (params != .object) return error.InvalidParams;
    const w_val = params.object.get("width") orelse return error.InvalidParams;
    const h_val = params.object.get("height") orelse return error.InvalidParams;

    const width: f64 = switch (w_val) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => return error.InvalidParams,
    };
    const height: f64 = switch (h_val) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => return error.InvalidParams,
    };

    // Get current frame, update size, setFrame:display:
    const frame = objc.msgSend_stret_rect(ns_window, objc.sel("frame"));
    const new_frame = objc.makeRect(frame.origin.x, frame.origin.y, width, height);
    const set_fn: *const fn (objc.id, objc.SEL, objc.NSRect, bool) callconv(.c) void = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    set_fn(ns_window, objc.sel("setFrame:display:"), new_frame, true);

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

fn center(ctx: *Context, _: std.json.Value) anyerror!std.json.Value {
    const ns_window = getWindow() orelse return error.WindowNotFound;
    objc.msgSend_void(ns_window, objc.sel("center"));

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

fn close(ctx: *Context, _: std.json.Value) anyerror!std.json.Value {
    const ns_window = getWindow() orelse return error.WindowNotFound;
    objc.msgSend_void(ns_window, objc.sel("performClose:"));

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

fn show(ctx: *Context, _: std.json.Value) anyerror!std.json.Value {
    const ns_window = getWindow() orelse return error.WindowNotFound;
    objc.msgSend_bool(ns_window, objc.sel("makeKeyAndOrderFront:"), false);

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

fn hide(ctx: *Context, _: std.json.Value) anyerror!std.json.Value {
    const ns_window = getWindow() orelse return error.WindowNotFound;
    objc.msgSend_id_void(ns_window, objc.sel("orderOut:"), null);

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}

fn isVisible(ctx: *Context, _: std.json.Value) anyerror!std.json.Value {
    const ns_window = getWindow() orelse return error.WindowNotFound;
    const vis_fn: *const fn (objc.id, objc.SEL) callconv(.c) objc.BOOL = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    const visible = vis_fn(ns_window, objc.sel("isVisible"));

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("visible", .{ .bool = visible != 0 });
    return .{ .object = obj };
}

fn setFullscreen(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    const ns_window = getWindow() orelse return error.WindowNotFound;

    // toggleFullScreen: toggles — we just call it. If the caller passes
    // { "fullscreen": true/false } we could check current state, but
    // toggling is the standard NSWindow API.
    _ = params;
    objc.msgSend_id_void(ns_window, objc.sel("toggleFullScreen:"), null);

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}
