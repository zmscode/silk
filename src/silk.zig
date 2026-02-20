const std = @import("std");
const sriracha = @import("sriracha");
const silk_api = @import("silk");
const user_commands = @import("user_commands");

const protocol = @import("ipc/message.zig");
const ipc = @import("ipc/router.zig");
const config_mod = @import("config.zig");
const permissions_mod = @import("permissions.zig");
const plugins = @import("plugins/register.zig");
const ts_bridge = @import("ts_bridge.zig");

const bridge_js = @embedFile("ipc/bridge.js");

var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

var window: sriracha.Window = .{};
var webview: sriracha.WebView = .{};

var router: ipc.Router = undefined;
var permissions: permissions_mod.Permissions = undefined;
var ctx: ipc.Context = undefined;
var mode_a_bridge: ?ts_bridge.Bridge = null;
var mode_a_worker_thread: ?std.Thread = null;
var mode_a_queue: std.ArrayList(ModeAJob) = .empty;
var mode_a_mutex: std.Thread.Mutex = .{};
var mode_a_cond: std.Thread.Condition = .{};
var mode_a_shutdown = false;

var eval_queue: std.ArrayList([]u8) = .empty;
var eval_flush_scheduled = false;
var eval_mutex: std.Thread.Mutex = .{};

const ModeAJob = struct {
    req: protocol.InvokeRequest,
};

pub fn main(_: std.process.Init) !void {
    allocator = gpa_state.allocator();

    var loaded_cfg = try config_mod.loadFromFile(allocator, "silk.config.json");
    defer loaded_cfg.deinit(allocator);

    permissions = try permissions_mod.Permissions.initDefault(allocator);
    defer permissions.deinit();
    if (loaded_cfg.cfg.permissions.allow_commands.len > 0) {
        try permissions.replaceAllowlist(loaded_cfg.cfg.permissions.allow_commands);
    }
    try permissions.replaceDenylist(loaded_cfg.cfg.permissions.deny_commands);
    permissions.setFsRoots(
        loaded_cfg.cfg.permissions.fs_read_roots,
        loaded_cfg.cfg.permissions.fs_write_roots,
    );
    try permissions.setShellAllowPrograms(loaded_cfg.cfg.permissions.shell_allow_programs);

    if (loaded_cfg.cfg.mode_a.enabled) {
        mode_a_bridge = try ts_bridge.Bridge.init(allocator, .{
            .enabled = loaded_cfg.cfg.mode_a.enabled,
            .argv = loaded_cfg.cfg.mode_a.argv,
        });
        mode_a_queue = .empty;
        mode_a_shutdown = false;
        mode_a_worker_thread = try std.Thread.spawn(.{}, modeAWorkerMain, .{});
    } else {
        mode_a_bridge = null;
    }

    router = ipc.Router.init(allocator);
    defer router.deinit();

    try plugins.registerAll(&router);
    try registerUserCommands(&router);

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
    defer {
        stopModeAWorker();
        for (mode_a_queue.items) |job| deinitInvokeRequest(job.req);
        mode_a_queue.deinit(allocator);
    }

    sriracha.app.init(.{ .on_ready = onReady });

    window.create(.{
        .title = loaded_cfg.cfg.window.title,
        .width = loaded_cfg.cfg.window.width,
        .height = loaded_cfg.cfg.window.height,
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
    stopModeAWorker();
    if (mode_a_bridge) |*bridge| {
        bridge.deinit();
    }
    sriracha.app.terminate();
}

fn onScriptMessage(_: *sriracha.WebView, message: []const u8) void {
    const parsed_invoke = protocol.parseInvoke(allocator, message) catch |err| {
        std.debug.print("[silk] invoke parse error: {s}\n", .{@errorName(err)});
        return;
    };
    defer parsed_invoke.parsed.deinit();

    if (router.hasHandler(parsed_invoke.req.cmd)) {
        const js = dispatchRequest(parsed_invoke.req) catch |err| {
            std.debug.print("[silk] invoke dispatch error: {s}\n", .{@errorName(err)});
            return;
        };

        enqueueEval(js) catch |err| {
            allocator.free(js);
            std.debug.print("[silk] schedule eval error: {s}\n", .{@errorName(err)});
        };
        return;
    }

    if (mode_a_bridge == null) {
        const js = router.buildErrorScript(parsed_invoke.req.callback, "Command not found") catch |err| {
            std.debug.print("[silk] invoke dispatch error: {s}\n", .{@errorName(err)});
            return;
        };
        enqueueEval(js) catch |err| {
            allocator.free(js);
            std.debug.print("[silk] schedule eval error: {s}\n", .{@errorName(err)});
        };
        return;
    }

    if (!ctx.permissions.allows(parsed_invoke.req.cmd)) {
        const js = router.buildErrorScript(parsed_invoke.req.callback, "Command denied by permissions") catch |err| {
            std.debug.print("[silk] invoke dispatch error: {s}\n", .{@errorName(err)});
            return;
        };
        enqueueEval(js) catch |err| {
            allocator.free(js);
            std.debug.print("[silk] schedule eval error: {s}\n", .{@errorName(err)});
        };
        return;
    }

    const cloned_req = cloneInvokeRequest(parsed_invoke.req) catch |err| {
        std.debug.print("[silk] mode-a clone error: {s}\n", .{@errorName(err)});
        return;
    };
    queueModeAJob(.{ .req = cloned_req }) catch |err| {
        deinitInvokeRequest(cloned_req);
        std.debug.print("[silk] mode-a queue error: {s}\n", .{@errorName(err)});
    };
}

fn dispatchRequest(req: protocol.InvokeRequest) ![]u8 {
    return router.dispatch(&ctx, req);
}

fn registerUserCommands(target_router: *ipc.Router) !void {
    var host = silk_api.Host.init(@ptrCast(target_router), registerUserCommand);
    try silk_api.registerUserModule(&host, user_commands);
}

fn registerUserCommand(raw_ctx: *anyopaque, cmd: []const u8, user_handler: silk_api.UserHandler) !void {
    const target_router: *ipc.Router = @ptrCast(@alignCast(raw_ctx));
    const handler: ipc.HandlerFn = @ptrCast(user_handler);
    try target_router.register(cmd, handler);
}

fn queueModeAJob(job: ModeAJob) !void {
    mode_a_mutex.lock();
    defer mode_a_mutex.unlock();
    try mode_a_queue.append(allocator, job);
    mode_a_cond.signal();
}

fn stopModeAWorker() void {
    mode_a_mutex.lock();
    mode_a_shutdown = true;
    mode_a_cond.broadcast();
    mode_a_mutex.unlock();

    if (mode_a_worker_thread) |thread| {
        thread.join();
        mode_a_worker_thread = null;
    }
}

fn modeAWorkerMain() void {
    while (true) {
        mode_a_mutex.lock();
        while (mode_a_queue.items.len == 0 and !mode_a_shutdown) {
            mode_a_cond.wait(&mode_a_mutex);
        }
        if (mode_a_shutdown) {
            mode_a_mutex.unlock();
            return;
        }
        const job = mode_a_queue.orderedRemove(0);
        mode_a_mutex.unlock();

        const js = dispatchModeAJob(job.req) catch |err| blk: {
            break :blk router.buildErrorScript(job.req.callback, @errorName(err)) catch continue;
        };
        deinitInvokeRequest(job.req);

        enqueueEval(js) catch |err| {
            allocator.free(js);
            std.debug.print("[silk] mode-a eval enqueue error: {s}\n", .{@errorName(err)});
        };
    }
}

fn dispatchModeAJob(req: protocol.InvokeRequest) ![]u8 {
    const bridge = &(mode_a_bridge orelse return error.TsBridgeMissing);
    const result = bridge.invoke(req) catch |err| {
        if (err == error.TsHostClosedStream or err == error.TsHostUnavailable) {
            bridge.deinit();
        }
        return router.buildErrorScript(req.callback, @errorName(err));
    };
    return router.buildSuccessScript(req.callback, result);
}

fn cloneInvokeRequest(req: protocol.InvokeRequest) !protocol.InvokeRequest {
    return .{
        .callback = req.callback,
        .cmd = try allocator.dupe(u8, req.cmd),
        .args = try deepCopyJsonValue(req.args),
    };
}

fn deinitInvokeRequest(req: protocol.InvokeRequest) void {
    allocator.free(req.cmd);
    deinitJsonValue(req.args);
}

fn deepCopyJsonValue(value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .{ .null = {} },
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .number_string => |s| .{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| blk: {
            var out = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try out.append(try deepCopyJsonValue(item));
            }
            break :blk .{ .array = out };
        },
        .object => |obj| blk: {
            var out = std.json.ObjectMap.init(allocator);
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                try out.put(key, try deepCopyJsonValue(entry.value_ptr.*));
            }
            break :blk .{ .object = out };
        },
    };
}

fn deinitJsonValue(value: std.json.Value) void {
    switch (value) {
        .null, .bool, .integer, .float => {},
        .number_string => |s| allocator.free(s),
        .string => |s| allocator.free(s),
        .array => |arr| {
            for (arr.items) |item| deinitJsonValue(item);
            var a = arr;
            a.deinit();
        },
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                deinitJsonValue(entry.value_ptr.*);
            }
            var o = obj;
            o.deinit();
        },
    }
}

fn enqueueEval(js: []u8) !void {
    eval_mutex.lock();
    defer eval_mutex.unlock();

    try eval_queue.append(allocator, js);
    if (eval_flush_scheduled) return;

    eval_flush_scheduled = true;
    sriracha.scheduleCallback(0, flushEvalQueue);
}

fn flushEvalQueue(_: ?*anyopaque) callconv(.c) void {
    eval_mutex.lock();
    defer eval_mutex.unlock();

    eval_flush_scheduled = false;

    for (eval_queue.items) |script| {
        webview.evaluateJavaScript(script);
        allocator.free(script);
    }
    eval_queue.clearRetainingCapacity();
}
