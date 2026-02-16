//! Dialog Plugin
//!
//! Provides IPC commands for native macOS dialogs:
//! dialog:open — File open dialog (NSOpenPanel)
//! dialog:save — File save dialog (NSSavePanel)
//! dialog:message — Alert/confirm dialog (NSAlert)

const std = @import("std");
const objc = @import("objc");
const Router = @import("../ipc/router.zig").Router;
const Context = @import("../core/context.zig").Context;

pub fn register(router: *Router) void {
    router.register("dialog:open", &openDialog, "dialog");
    router.register("dialog:save", &saveDialog, "dialog");
    router.register("dialog:message", &messageDialog, "dialog");
}

/// Show a file open dialog.
/// Params: { "directory": false, "multiple": false, "title": "Open File" }
/// Returns: { "paths": ["/path/to/file"] } or { "paths": null } if cancelled
fn openDialog(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    // [NSOpenPanel openPanel]
    const panel = objc.msgSend(objc.getClass("NSOpenPanel"), objc.sel("openPanel"));

    // Configure options
    if (params == .object) {
        if (params.object.get("directory")) |v| {
            if (v == .bool) {
                objc.msgSend_bool(panel, objc.sel("setCanChooseDirectories:"), v.bool);
                if (v.bool) {
                    objc.msgSend_bool(panel, objc.sel("setCanChooseFiles:"), false);
                }
            }
        }
        if (params.object.get("multiple")) |v| {
            if (v == .bool) {
                objc.msgSend_bool(panel, objc.sel("setAllowsMultipleSelection:"), v.bool);
            }
        }
        if (params.object.get("title")) |v| {
            if (v == .string) {
                objc.msgSend_id_void(panel, objc.sel("setTitle:"), objc.nsString(v.string));
            }
        }
    }

    // [panel runModal] — NSModalResponseOK = 1
    const run_fn: *const fn (objc.id, objc.SEL) callconv(.c) objc.NSInteger = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    const response = run_fn(panel, objc.sel("runModal"));

    var obj = std.json.ObjectMap.init(ctx.allocator);

    if (response != 1) {
        // User cancelled
        try obj.put("paths", .null);
        return .{ .object = obj };
    }

    // Extract selected URLs
    const urls = objc.msgSend(panel, objc.sel("URLs"));
    const count_fn: *const fn (objc.id, objc.SEL) callconv(.c) objc.NSUInteger = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    const count = count_fn(urls, objc.sel("count"));

    var paths = std.json.Array.init(ctx.allocator);
    const get_fn: *const fn (objc.id, objc.SEL, objc.NSUInteger) callconv(.c) objc.id = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    const utf8_fn: *const fn (objc.id, objc.SEL) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(objc.objc_msgSend_ptr));

    for (0..count) |i| {
        const url = get_fn(urls, objc.sel("objectAtIndex:"), @intCast(i));
        const path_ns = objc.msgSend(url, objc.sel("path"));
        const c_str = utf8_fn(path_ns, objc.sel("UTF8String")) orelse continue;
        const path = try ctx.allocator.dupe(u8, std.mem.span(c_str));
        try paths.append(.{ .string = path });
    }

    try obj.put("paths", .{ .array = paths });
    return .{ .object = obj };
}

/// Show a file save dialog.
/// Params: { "title": "Save File", "defaultName": "untitled.txt" }
/// Returns: { "path": "/path/to/file" } or { "path": null } if cancelled
fn saveDialog(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    // [NSSavePanel savePanel]
    const panel = objc.msgSend(objc.getClass("NSSavePanel"), objc.sel("savePanel"));

    if (params == .object) {
        if (params.object.get("title")) |v| {
            if (v == .string) {
                objc.msgSend_id_void(panel, objc.sel("setTitle:"), objc.nsString(v.string));
            }
        }
        if (params.object.get("defaultName")) |v| {
            if (v == .string) {
                objc.msgSend_id_void(panel, objc.sel("setNameFieldStringValue:"), objc.nsString(v.string));
            }
        }
    }

    const run_fn: *const fn (objc.id, objc.SEL) callconv(.c) objc.NSInteger = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    const response = run_fn(panel, objc.sel("runModal"));

    var obj = std.json.ObjectMap.init(ctx.allocator);

    if (response != 1) {
        try obj.put("path", .null);
        return .{ .object = obj };
    }

    // [panel URL] → [url path]
    const url = objc.msgSend(panel, objc.sel("URL"));
    const path_ns = objc.msgSend(url, objc.sel("path"));
    const utf8_fn: *const fn (objc.id, objc.SEL) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    const c_str = utf8_fn(path_ns, objc.sel("UTF8String")) orelse {
        try obj.put("path", .null);
        return .{ .object = obj };
    };

    const path = try ctx.allocator.dupe(u8, std.mem.span(c_str));
    try obj.put("path", .{ .string = path });
    return .{ .object = obj };
}

/// Show an alert/confirm dialog.
/// Params: { "title": "Confirm", "message": "Are you sure?", "style": "informational" }
/// style: "warning", "critical", "informational" (default)
/// Returns: { "confirmed": true } — true if OK/first button clicked
fn messageDialog(ctx: *Context, params: std.json.Value) anyerror!std.json.Value {
    // [[NSAlert alloc] init]
    const alert = objc.msgSend(
        objc.msgSend(objc.getClass("NSAlert"), objc.sel("alloc")),
        objc.sel("init"),
    );

    if (params == .object) {
        if (params.object.get("title")) |v| {
            if (v == .string) {
                objc.msgSend_id_void(alert, objc.sel("setMessageText:"), objc.nsString(v.string));
            }
        }
        if (params.object.get("message")) |v| {
            if (v == .string) {
                objc.msgSend_id_void(alert, objc.sel("setInformativeText:"), objc.nsString(v.string));
            }
        }
        if (params.object.get("style")) |v| {
            if (v == .string) {
                // NSAlertStyleWarning = 0, NSAlertStyleInformational = 1, NSAlertStyleCritical = 2
                const style: objc.NSUInteger = if (std.mem.eql(u8, v.string, "warning"))
                    0
                else if (std.mem.eql(u8, v.string, "critical"))
                    2
                else
                    1;
                objc.msgSend_uint(alert, objc.sel("setAlertStyle:"), style);
            }
        }
    }

    // Add OK and Cancel buttons
    objc.msgSend_id_void(alert, objc.sel("addButtonWithTitle:"), objc.nsStringZ("OK"));
    objc.msgSend_id_void(alert, objc.sel("addButtonWithTitle:"), objc.nsStringZ("Cancel"));

    // [alert runModal] — NSAlertFirstButtonReturn = 1000
    const run_fn: *const fn (objc.id, objc.SEL) callconv(.c) objc.NSInteger = @ptrCast(@alignCast(objc.objc_msgSend_ptr));
    const response = run_fn(alert, objc.sel("runModal"));

    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("confirmed", .{ .bool = response == 1000 });
    return .{ .object = obj };
}
