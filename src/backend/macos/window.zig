//! macOS Window Management (Loom)
//!
//! Creates and manages NSWindow instances via the ObjC runtime.
//! This is Silk's equivalent of Tauri's TAO layer on macOS.

const std = @import("std");
const objc = @import("objc");

const id = objc.id;
const SEL = objc.SEL;

// ─── NSWindow Style Masks ───────────────────────────────────────────────

pub const StyleMask = struct {
    pub const titled: objc.NSUInteger = 1 << 0;
    pub const closable: objc.NSUInteger = 1 << 1;
    pub const miniaturizable: objc.NSUInteger = 1 << 2;
    pub const resizable: objc.NSUInteger = 1 << 3;
    pub const fullscreen: objc.NSUInteger = 1 << 14;

    pub const default = titled | closable | miniaturizable | resizable;
};

// ─── Window Configuration ───────────────────────────────────────────────

pub const WindowConfig = struct {
    title: []const u8 = "Silk App",
    width: f64 = 1024,
    height: f64 = 768,
    x: f64 = 200,
    y: f64 = 200,
    style_mask: objc.NSUInteger = StyleMask.default,
    resizable: bool = true,
};

// ─── Window ─────────────────────────────────────────────────────────────

pub const Window = struct {
    ns_window: id,

    /// Create a new NSWindow with the given configuration.
    pub fn init(config: WindowConfig) Window {
        const rect = objc.makeRect(config.x, config.y, config.width, config.height);

        // [[NSWindow alloc] initWithContentRect:styleMask:backing:defer:]
        const alloc_obj = objc.msgSend(objc.getClass("NSWindow"), objc.sel("alloc"));
        const window = objc.msgSend_rect_uint_uint_bool(
            alloc_obj,
            objc.sel("initWithContentRect:styleMask:backing:defer:"),
            rect,
            config.style_mask,
            2, // NSBackingStoreBuffered
            false,
        );

        // [window setTitle:]
        objc.msgSend_id_void(window, objc.sel("setTitle:"), objc.nsString(config.title));

        // Center the window on screen
        objc.msgSend_void(window, objc.sel("center"));

        return .{ .ns_window = window };
    }

    /// Set the content view of the window.
    pub fn setContentView(self: *const Window, view: id) void {
        objc.msgSend_id_void(self.ns_window, objc.sel("setContentView:"), view);
    }

    /// Make the window visible and key.
    pub fn show(self: *const Window) void {
        objc.msgSend_bool(self.ns_window, objc.sel("makeKeyAndOrderFront:"), false);
    }

    /// Set the window title.
    pub fn setTitle(self: *const Window, title: []const u8) void {
        objc.msgSend_id_void(self.ns_window, objc.sel("setTitle:"), objc.nsString(title));
    }

    /// Get the content view's frame rect.
    pub fn contentRect(self: *const Window) objc.NSRect {
        const content_view = objc.msgSend(self.ns_window, objc.sel("contentView"));
        return objc.msgSend_stret_rect(content_view, objc.sel("frame"));
    }

    /// Release the NSWindow.
    pub fn deinit(self: *const Window) void {
        objc.msgSend_void(self.ns_window, objc.sel("close"));
    }
};

// ─── NSApplication Helpers ──────────────────────────────────────────────

/// Initialize the shared NSApplication and set activation policy to regular
/// (foreground app with dock icon and menu bar).
pub fn initApp() id {
    const ns_app = objc.msgSend(objc.getClass("NSApplication"), objc.sel("sharedApplication"));

    // [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]
    objc.msgSend_uint(ns_app, objc.sel("setActivationPolicy:"), 0);

    return ns_app;
}

/// Run the NSApplication main event loop. This blocks until the app terminates.
pub fn runApp(ns_app: id) void {
    objc.msgSend_void(ns_app, objc.sel("run"));
}

/// Activate the app (bring to front).
pub fn activateApp(ns_app: id) void {
    objc.msgSend_bool(ns_app, objc.sel("activateIgnoringOtherApps:"), true);
}

// ─── Window Delegate ────────────────────────────────────────────────────

const silk_main = @import("../../silk.zig");

var delegate_registered: bool = false;

/// Set a window delegate to receive lifecycle callbacks.
pub fn setWindowDelegate(ns_window: id) void {
    if (!delegate_registered) {
        registerDelegateClass();
        delegate_registered = true;
    }

    const delegate = objc.msgSend(
        objc.msgSend(objc.getClass("SilkWindowDelegate"), objc.sel("alloc")),
        objc.sel("init"),
    );
    objc.msgSend_id_void(ns_window, objc.sel("setDelegate:"), delegate);
}

fn registerDelegateClass() void {
    const cls = objc.allocateClassPair("NSObject", "SilkWindowDelegate") orelse return;

    _ = objc.addMethod(cls, objc.sel("windowShouldClose:"), @ptrCast(&delegateWindowShouldClose), "B@:@");
    _ = objc.addMethod(cls, objc.sel("windowDidBecomeKey:"), @ptrCast(&delegateWindowDidBecomeKey), "v@:@");
    _ = objc.addMethod(cls, objc.sel("windowDidResignKey:"), @ptrCast(&delegateWindowDidResignKey), "v@:@");
    _ = objc.addMethod(cls, objc.sel("windowDidResize:"), @ptrCast(&delegateWindowDidResize), "v@:@");

    _ = objc.addProtocol(cls, "NSWindowDelegate");
    objc.registerClassPair(cls);
}

fn delegateWindowShouldClose(_: id, _: SEL, _: id) callconv(.c) bool {
    return silk_main.windowShouldClose();
}

fn delegateWindowDidBecomeKey(_: id, _: SEL, _: id) callconv(.c) void {
    silk_main.windowDidBecomeKey();
}

fn delegateWindowDidResignKey(_: id, _: SEL, _: id) callconv(.c) void {
    silk_main.windowDidResignKey();
}

fn delegateWindowDidResize(_: id, _: SEL, _: id) callconv(.c) void {
    silk_main.windowDidResize();
}
