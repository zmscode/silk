//! Clipboard Plugin
//!
//! Provides IPC commands for system clipboard access:
//! clipboard:readText, clipboard:writeText
//!
//! Uses NSPasteboard via ObjC runtime.

const std = @import("std");
const objc = @import("objc");
const Router = @import("../ipc/router.zig").Router;
const Context = @import("../core/context.zig").Context;

pub fn register(router: *Router) void {
    router.register("clipboard:readText", &readText, "clipboard");
    router.register("clipboard:writeText", &writeText, "clipboard");
}

fn readText(ctx: *Context, _: std.json.Value) anyerror!std.json.Value {
    // [NSPasteboard generalPasteboard]
    const pasteboard = objc.msgSend(objc.getClass("NSPasteboard"), objc.sel("generalPasteboard"));

    // [pasteboard stringForType:NSPasteboardTypeString]
    const ns_type = objc.nsStringZ("public.utf8-plain-text");
    const ns_str = objc.msgSend_id(pasteboard, objc.sel("stringForType:"), ns_type);

    if (ns_str == null) {
        var obj = std.json.ObjectMap.init(ctx.allocator);
        try obj.put("text", .null);
        return .{ .object = obj };
    }

    const utf8_fn: *const fn (objc.id, objc.SEL) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    const c_str = utf8_fn(ns_str, objc.sel("UTF8String")) orelse {
        var obj = std.json.ObjectMap.init(ctx.allocator);
        try obj.put("text", .null);
        return .{ .object = obj };
    };

    const text = try ctx.allocator.dupe(u8, std.mem.span(c_str));
    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("text", .{ .string = text });
    return .{ .object = obj };
}

fn writeText(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    if (params != .object) return error.InvalidParams;
    const val = params.object.get("text") orelse return error.InvalidParams;
    if (val != .string) return error.InvalidParams;
    const text = val.string;

    // [NSPasteboard generalPasteboard]
    const pasteboard = objc.msgSend(objc.getClass("NSPasteboard"), objc.sel("generalPasteboard"));

    // [pasteboard clearContents]
    objc.msgSend_void(pasteboard, objc.sel("clearContents"));

    // [pasteboard setString:forType:]
    const ns_str = objc.nsString(text);
    const ns_type = objc.nsStringZ("public.utf8-plain-text");
    const set_fn: *const fn (objc.id, objc.SEL, objc.id, objc.id) callconv(.c) objc.BOOL = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    _ = set_fn(pasteboard, objc.sel("setString:forType:"), ns_str, ns_type);

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("success", .{ .bool = true });
    return .{ .object = obj };
}
