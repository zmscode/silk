const std = @import("std");
const sriracha = @import("sriracha");

const protocol = @import("ipc/message.zig");
const ipc = @import("ipc/router.zig");
const config_mod = @import("config.zig");
const permissions_mod = @import("permissions.zig");
const plugins = @import("plugins/register.zig");

const bridge_js = @embedFile("ipc/bridge.js");

var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

var window: sriracha.Window = .{};
var webview: sriracha.WebView = .{};

var router: ipc.Router = undefined;
var permissions: permissions_mod.Permissions = undefined;
var ctx: ipc.Context = undefined;

var eval_queue: std.ArrayList([]u8) = .empty;
var eval_flush_scheduled = false;

pub fn main(_: std.process.Init) !void {
    allocator = gpa_state.allocator();

    var loaded_cfg = try config_mod.loadFromFile(allocator, "silk.config.json");
    defer loaded_cfg.deinit(allocator);

    permissions = try permissions_mod.Permissions.initDefault(allocator);
    defer permissions.deinit();
    if (loaded_cfg.cfg.allowed_commands.len > 0) {
        try permissions.replaceAllowlist(loaded_cfg.cfg.allowed_commands);
    }

    router = ipc.Router.init(allocator);
    defer router.deinit();

    try plugins.registerAll(&router);

    ctx = .{
        .allocator = allocator,
        .webview = @ptrCast(&webview),
        .window = @ptrCast(&window),
        .permissions = &permissions,
    };

    eval_queue = .empty;
    defer {
        for (eval_queue.items) |script| allocator.free(script);
        eval_queue.deinit(allocator);
    }

    sriracha.app.init(.{ .on_ready = onReady });

    window.create(.{
        .title = loaded_cfg.cfg.title,
        .width = loaded_cfg.cfg.width,
        .height = loaded_cfg.cfg.height,
        .callbacks = .{ .on_close = onClose },
    });
    window.center();
    window.show();

    webview.create(.{
        .handler_name = "silk",
        .on_script_message = onScriptMessage,
    });
    webview.attachToWindow(&window);
    webview.loadHTML(
        \\<!DOCTYPE html>
        \\<html>
        \\<head><meta charset="utf-8"><title>Silk</title></head>
        \\<body style="margin:0;padding:40px;font-family:-apple-system,sans-serif;background:#0f0f0f;color:#eee;">
        \\  <h1 style="color:#f97316;">Silk</h1>
        \\  <p>Command API scaffold is live.</p>
        \\  <pre id="out" style="padding:12px;background:#1a1a1a;border-radius:8px;color:#cbd5e1;">waiting...</pre>
        \\  <script>
        \\    const out = document.getElementById('out');
        \\    function waitForSilk() {
        \\      if (!window.__silk) {
        \\        setTimeout(waitForSilk, 16);
        \\        return;
        \\      }
        \\      Promise.all([
        \\        window.__silk.invoke('silk:ping'),
        \\        window.__silk.invoke('silk:appInfo')
        \\      ])
        \\        .then(([pong, info]) => {
        \\          out.textContent = JSON.stringify({ pong, info }, null, 2);
        \\        })
        \\        .catch((err) => {
        \\          out.textContent = `error: ${err.message}`;
        \\        });
        \\    }
        \\    waitForSilk();
        \\  </script>
        \\</body>
        \\</html>
    , null);

    sriracha.app.run();
}

fn onReady() void {
    webview.evaluateJavaScript(bridge_js);
}

fn onClose(_: *sriracha.Window) void {
    sriracha.app.terminate();
}

fn onScriptMessage(_: *sriracha.WebView, message: []const u8) void {
    const parsed_invoke = protocol.parseInvoke(allocator, message) catch |err| {
        std.debug.print("[silk] invoke parse error: {s}\n", .{@errorName(err)});
        return;
    };
    defer parsed_invoke.parsed.deinit();

    const js = router.dispatch(&ctx, parsed_invoke.req) catch |err| {
        std.debug.print("[silk] invoke dispatch error: {s}\n", .{@errorName(err)});
        return;
    };

    enqueueEval(js) catch |err| {
        allocator.free(js);
        std.debug.print("[silk] schedule eval error: {s}\n", .{@errorName(err)});
    };
}

fn enqueueEval(js: []u8) !void {
    try eval_queue.append(allocator, js);
    if (eval_flush_scheduled) return;

    eval_flush_scheduled = true;
    sriracha.scheduleCallback(0, flushEvalQueue);
}

fn flushEvalQueue(_: ?*anyopaque) callconv(.c) void {
    eval_flush_scheduled = false;

    for (eval_queue.items) |script| {
        webview.evaluateJavaScript(script);
        allocator.free(script);
    }
    eval_queue.clearRetainingCapacity();
}
