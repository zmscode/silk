//! Silk — Application Entry Point
//!
//! Bootstraps NSApplication, registers an AppDelegate, and starts the
//! main event loop. The AppDelegate creates a window + webview on launch.

const std = @import("std");
const objc = @import("objc");
const macos_window = @import("backend/macos/window.zig");
const macos_webview = @import("backend/macos/webview.zig");
const app_mod = @import("core/app.zig");

const AppState = app_mod.AppState;

// Static app state — lives for the process lifetime.
var app_state: AppState = undefined;
var dev_url: ?[]const u8 = null;
var window_title: []const u8 = "Silk";

// ─── Main ───────────────────────────────────────────────────────────────

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Parse CLI args (e.g. --url http://localhost:5173 --title "My App")
    var iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = iter.next(); // skip argv[0]
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--url")) {
            dev_url = iter.next();
        } else if (std.mem.eql(u8, arg, "--title")) {
            window_title = iter.next() orelse "Silk";
        }
    }

    app_state = AppState.init(allocator, init.io);
    app_state.setup();
    app_mod.g_app = &app_state;

    // Initialise NSApplication and set activation policy to regular (dock icon + menu bar)
    const ns_app = macos_window.initApp();

    // Register and attach the AppDelegate
    const delegate = createAppDelegate();
    objc.msgSend_id_void(ns_app, objc.sel("setDelegate:"), delegate);

    // Activate the app (bring to front)
    macos_window.activateApp(ns_app);

    // Run the main event loop (blocks until termination)
    macos_window.runApp(ns_app);
}

// ─── AppDelegate ────────────────────────────────────────────────────────

var delegate_class_registered: bool = false;

fn createAppDelegate() objc.id {
    if (!delegate_class_registered) {
        const cls = objc.allocateClassPair("NSObject", "SilkAppDelegate") orelse
            @panic("Failed to create SilkAppDelegate class");

        _ = objc.addMethod(
            cls,
            objc.sel("applicationDidFinishLaunching:"),
            @ptrCast(&appDidFinishLaunching),
            "v@:@",
        );

        _ = objc.addProtocol(cls, "NSApplicationDelegate");
        objc.registerClassPair(cls);
        delegate_class_registered = true;
    }

    return objc.msgSend(
        objc.msgSend(objc.getClass("SilkAppDelegate"), objc.sel("alloc")),
        objc.sel("init"),
    );
}

fn appDidFinishLaunching(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    const allocator = app_state.allocator;

    // Create the main window
    app_state.window = macos_window.Window.init(.{
        .title = window_title,
        .width = 1024,
        .height = 768,
    });
    var win = &app_state.window.?;

    // Set window delegate for lifecycle callbacks
    macos_window.setWindowDelegate(win.ns_window);

    // Create the webview with IPC message handling and JS bridge
    app_state.webview = macos_webview.WebView.init(allocator, .{
        .debug = true,
        .message_callback = &app_mod.handleMessage,
        .bridge_script = @embedFile("bridge/bridge.js"),
    }) catch {
        std.log.err("Failed to create webview", .{});
        return;
    };
    const wv = &app_state.webview.?;

    // Embed the webview in the window
    win.setContentView(wv.view());

    // Load dev URL or built-in demo page
    if (dev_url) |url| {
        wv.loadURL(url);
    } else {
        wv.loadHTML(welcome_html);
    }

    // Show the window
    win.show();
}

// ─── Window Delegate Callbacks ──────────────────────────────────────────
//
// These are called by the SilkWindowDelegate registered in window.zig.

pub fn windowShouldClose() bool {
    // Terminate the app when the main window closes
    const ns_app = objc.msgSend(objc.getClass("NSApplication"), objc.sel("sharedApplication"));
    objc.msgSend_id_void(ns_app, objc.sel("terminate:"), null);
    return true;
}

pub fn windowDidBecomeKey() void {}

pub fn windowDidResignKey() void {}

pub fn windowDidResize() void {}

// ─── Built-in Demo HTML ─────────────────────────────────────────────────

const welcome_html = @embedFile("frontend/index.html");
