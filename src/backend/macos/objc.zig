//! ObjC Runtime Helpers
//!
//! Thin wrappers around the Objective-C runtime for calling macOS
//! framework APIs (AppKit, WebKit) from Zig via `objc_msgSend`.

const std = @import("std");
const c = @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
    @cInclude("dispatch/dispatch.h");
});

// ─── Core Types ─────────────────────────────────────────────────────────

pub const id = ?*anyopaque;
pub const SEL = ?*anyopaque;
pub const Class = ?*anyopaque;
pub const BOOL = i8;
pub const NSUInteger = u64;
pub const NSInteger = i64;

pub const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};

pub const NSPoint = extern struct {
    x: f64,
    y: f64,
};

pub const NSSize = extern struct {
    width: f64,
    height: f64,
};

/// Raw pointer to objc_msgSend — other modules cast this to call ObjC methods.
pub const objc_msgSend_ptr: *const anyopaque = @ptrCast(@alignCast(&c.objc_msgSend));

pub fn makeRect(x: f64, y: f64, w: f64, h: f64) NSRect {
    return .{
        .origin = .{ .x = x, .y = y },
        .size = .{ .width = w, .height = h },
    };
}

// ─── Selector & Class Lookup ────────────────────────────────────────────

pub inline fn sel(name: [*:0]const u8) SEL {
    return c.sel_registerName(name);
}

pub inline fn getClass(name: [*:0]const u8) id {
    return @as(id, @ptrCast(c.objc_getClass(name)));
}

// ─── objc_msgSend Wrappers ──────────────────────────────────────────────
//
// Each variant casts objc_msgSend to the correct function pointer type
// for the given argument/return signature. This is required because
// objc_msgSend is variadic in C but must be called with the exact ABI
// in Zig.

/// No extra arguments, returns id.
pub inline fn msgSend(obj: id, selector: SEL) id {
    const f: *const fn (id, SEL) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(obj, selector);
}

/// One id argument, returns id.
pub inline fn msgSend_id(obj: id, selector: SEL, a0: id) id {
    const f: *const fn (id, SEL, id) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(obj, selector, a0);
}

/// Two id arguments, returns id.
pub inline fn msgSend_id_id(obj: id, selector: SEL, a0: id, a1: id) id {
    const f: *const fn (id, SEL, id, id) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(obj, selector, a0, a1);
}

/// Three id arguments, returns id.
pub inline fn msgSend_id_id_id(obj: id, selector: SEL, a0: id, a1: id, a2: id) id {
    const f: *const fn (id, SEL, id, id, id) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(obj, selector, a0, a1, a2);
}

/// One bool argument, returns void.
pub inline fn msgSend_bool(obj: id, selector: SEL, val: bool) void {
    const f: *const fn (id, SEL, bool) callconv(.c) void = @ptrCast(@alignCast(&c.objc_msgSend));
    f(obj, selector, val);
}

/// One NSUInteger argument, returns void.
pub inline fn msgSend_uint(obj: id, selector: SEL, val: NSUInteger) void {
    const f: *const fn (id, SEL, NSUInteger) callconv(.c) void = @ptrCast(@alignCast(&c.objc_msgSend));
    f(obj, selector, val);
}

/// One id argument, returns void.
pub inline fn msgSend_id_void(obj: id, selector: SEL, a0: id) void {
    const f: *const fn (id, SEL, id) callconv(.c) void = @ptrCast(@alignCast(&c.objc_msgSend));
    f(obj, selector, a0);
}

/// Two id arguments, returns void.
pub inline fn msgSend_id_id_void(obj: id, selector: SEL, a0: id, a1: id) void {
    const f: *const fn (id, SEL, id, id) callconv(.c) void = @ptrCast(@alignCast(&c.objc_msgSend));
    f(obj, selector, a0, a1);
}

/// NSRect + NSUInteger + NSUInteger + bool → id (NSWindow initWithContentRect:styleMask:backing:defer:)
pub inline fn msgSend_rect_uint_uint_bool(obj: id, selector: SEL, rect: NSRect, style: NSUInteger, backing: NSUInteger, defer_: bool) id {
    const f: *const fn (id, SEL, NSRect, NSUInteger, NSUInteger, bool) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(obj, selector, rect, style, backing, defer_);
}

/// NSRect + id → id (WKWebView initWithFrame:configuration:)
pub inline fn msgSend_rect_id(obj: id, selector: SEL, rect: NSRect, a0: id) id {
    const f: *const fn (id, SEL, NSRect, id) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(obj, selector, rect, a0);
}

/// No extra arguments, returns void.
pub inline fn msgSend_void(obj: id, selector: SEL) void {
    const f: *const fn (id, SEL) callconv(.c) void = @ptrCast(@alignCast(&c.objc_msgSend));
    f(obj, selector);
}

/// One bool argument, returns id (e.g. [NSNumber numberWithBool:]).
pub inline fn msgSend_bool_ret(obj: id, selector: SEL, val: bool) id {
    const f: *const fn (id, SEL, bool) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(obj, selector, val);
}

/// No extra arguments, returns NSRect.
pub inline fn msgSend_stret_rect(obj: id, selector: SEL) NSRect {
    // On arm64, structs up to 4 registers are returned in registers, so
    // regular objc_msgSend works (no _stret needed on Apple Silicon).
    const f: *const fn (id, SEL) callconv(.c) NSRect = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(obj, selector);
}

// ─── NSString Helpers ───────────────────────────────────────────────────

/// Create an autoreleased NSString from a Zig string slice.
/// Uses initWithBytes:length:encoding: (NSUTF8StringEncoding = 4).
pub fn nsString(str: []const u8) id {
    const alloc_obj = msgSend(getClass("NSString"), sel("alloc"));
    const f: *const fn (id, SEL, [*]const u8, NSUInteger, NSUInteger) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(
        alloc_obj,
        sel("initWithBytes:length:encoding:"),
        str.ptr,
        @intCast(str.len),
        4, // NSUTF8StringEncoding
    );
}

/// Create an autoreleased NSString from a null-terminated string.
pub fn nsStringZ(str: [*:0]const u8) id {
    const f: *const fn (id, SEL, [*:0]const u8) callconv(.c) id = @ptrCast(@alignCast(&c.objc_msgSend));
    return f(
        getClass("NSString"),
        sel("stringWithUTF8String:"),
        str,
    );
}

/// Create an autoreleased NSURL from a string.
pub fn nsURL(str: []const u8) id {
    return msgSend_id(
        getClass("NSURL"),
        sel("URLWithString:"),
        nsString(str),
    );
}

// ─── ObjC Class Registration ────────────────────────────────────────────

/// Register a new ObjC class with the runtime. Returns the new class.
pub fn allocateClassPair(superclass_name: [*:0]const u8, name: [*:0]const u8) ?*anyopaque {
    const super: ?*c.objc_class = @ptrCast(c.objc_getClass(superclass_name));
    return @ptrCast(c.objc_allocateClassPair(super, name, 0));
}

/// Add a method to a class being constructed.
pub fn addMethod(cls: ?*anyopaque, selector: SEL, imp: *const anyopaque, types: [*:0]const u8) bool {
    return c.class_addMethod(
        @ptrCast(cls),
        @ptrCast(selector),
        @ptrCast(@alignCast(imp)),
        types,
    );
}

/// Add an ivar (instance variable) to a class being constructed.
pub fn addIvar(cls: ?*anyopaque, name: [*:0]const u8, size: usize, alignment: u8, types: [*:0]const u8) bool {
    return c.class_addIvar(@ptrCast(cls), name, size, alignment, types);
}

/// Finish registering a class pair.
pub fn registerClassPair(cls: ?*anyopaque) void {
    c.objc_registerClassPair(@ptrCast(cls));
}

/// Set the value of an ivar.
pub fn setIvar(obj: id, name: [*:0]const u8, value: ?*anyopaque) void {
    const ivar = c.class_getInstanceVariable(c.object_getClass(@ptrCast(obj)), name);
    c.object_setIvar(@ptrCast(obj), ivar, @ptrCast(value));
}

/// Get the value of an ivar.
pub fn getIvar(obj: id, name: [*:0]const u8) ?*anyopaque {
    const ivar = c.class_getInstanceVariable(c.object_getClass(@ptrCast(obj)), name);
    return @ptrCast(c.object_getIvar(@ptrCast(obj), ivar));
}

/// Add a protocol conformance to a class.
pub fn addProtocol(cls: ?*anyopaque, protocol_name: [*:0]const u8) bool {
    const proto = c.objc_getProtocol(protocol_name) orelse return false;
    return c.class_addProtocol(@ptrCast(cls), proto);
}

// ─── GCD (Grand Central Dispatch) ───────────────────────────────────────

/// The main dispatch queue. `dispatch_get_main_queue()` is a C macro that
/// Zig can't translate, so we reference the underlying symbol directly.
const dispatch_main_q = @extern(*anyopaque, .{ .name = "_dispatch_main_q" });

/// Schedule a C function to run on the main queue (main thread).
/// Used to defer work out of ObjC callbacks that don't allow re-entrancy
/// (e.g. WKScriptMessageHandler → evaluateJavaScript).
pub fn dispatchAsync(context: ?*anyopaque, func: *const fn (?*anyopaque) callconv(.c) void) void {
    c.dispatch_async_f(@ptrCast(dispatch_main_q), context, func);
}
