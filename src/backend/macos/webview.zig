//! macOS WebView (Weave)
//!
//! Embeds WKWebView into an NSWindow and provides:
//! - JS evaluation (Zig → JS)
//! - IPC message handler via WKScriptMessageHandler (JS → Zig)
//! - Custom `silk://` protocol via WKURLSchemeHandler
//! - User script injection (bridge.js)

const std = @import("std");
const objc = @import("objc");

const id = objc.id;
const SEL = objc.SEL;
const msg_ptr = objc.objc_msgSend_ptr;

// ─── IPC Callback Type ──────────────────────────────────────────────────

/// Called when the webview sends a message via `window.webkit.messageHandlers.silk_ipc.postMessage(...)`.
/// The callback receives the raw JSON string and must return a JSON response string.
pub const MessageCallback = *const fn (raw_json: []const u8) ?[]const u8;

// ─── Asset Provider ─────────────────────────────────────────────────────

/// Called by the silk:// protocol handler to resolve asset paths.
/// Returns the file contents and MIME type, or null if not found.
pub const AssetProvider = *const fn (path: []const u8) ?Asset;

pub const Asset = struct {
    data: []const u8,
    mime_type: []const u8,
};

// ─── WebView ────────────────────────────────────────────────────────────

/// Stores the global state for the ObjC callback to access.
/// Only one webview is supported per process for now (Phase 1).
var g_state: ?*WebViewState = null;

const WebViewState = struct {
    message_callback: MessageCallback,
    asset_provider: ?AssetProvider,
    wk_webview: id,
    allocator: std.mem.Allocator,
};

pub const WebViewConfig = struct {
    debug: bool = false,
    /// JavaScript source to inject at document start (the bridge script).
    bridge_script: ?[]const u8 = null,
    /// Callback for IPC messages from JS.
    message_callback: MessageCallback,
    /// Provider for silk:// protocol assets.
    asset_provider: ?AssetProvider = null,
    /// Content Security Policy to inject as a meta tag.
    csp: ?[]const u8 = null,
};

pub const WebView = struct {
    state: *WebViewState,

    /// Create a WKWebView with IPC message handling and optional silk:// protocol.
    pub fn init(allocator: std.mem.Allocator, config: WebViewConfig) !WebView {
        const state = try allocator.create(WebViewState);
        state.* = .{
            .message_callback = config.message_callback,
            .asset_provider = config.asset_provider,
            .wk_webview = null,
            .allocator = allocator,
        };
        g_state = state;

        // Register the ObjC classes for our handlers (idempotent)
        registerObjcClasses();

        // WKWebViewConfiguration
        const wk_config = objc.msgSend(
            objc.msgSend(objc.getClass("WKWebViewConfiguration"), objc.sel("alloc")),
            objc.sel("init"),
        );

        // Get the user content controller
        const content_controller = objc.msgSend(wk_config, objc.sel("userContentController"));

        // Register silk_ipc message handler
        const handler = objc.msgSend(
            objc.msgSend(objc.getClass("SilkMessageHandler"), objc.sel("alloc")),
            objc.sel("init"),
        );
        objc.msgSend_id_id_void(
            content_controller,
            objc.sel("addScriptMessageHandler:name:"),
            handler,
            objc.nsStringZ("silk_ipc"),
        );

        // Inject bridge.js as a user script (runs at document start)
        if (config.bridge_script) |script| {
            const user_script = createUserScript(script);
            objc.msgSend_id_void(content_controller, objc.sel("addUserScript:"), user_script);
        }

        // Inject CSP meta tag via user script (runs at document start)
        if (config.csp) |csp| {
            var buf: std.ArrayList(u8) = .{};
            buf.appendSlice(allocator, "(function(){var m=document.createElement('meta');m.httpEquiv='Content-Security-Policy';m.content='") catch {};
            buf.appendSlice(allocator, csp) catch {};
            buf.appendSlice(allocator, "';document.head.appendChild(m);})();") catch {};
            const csp_script = createUserScript(buf.items);
            objc.msgSend_id_void(content_controller, objc.sel("addUserScript:"), csp_script);
            buf.deinit(allocator);
        }

        // Register silk:// URL scheme handler
        if (config.asset_provider != null) {
            const scheme_handler = objc.msgSend(
                objc.msgSend(objc.getClass("SilkSchemeHandler"), objc.sel("alloc")),
                objc.sel("init"),
            );
            objc.msgSend_id_id_void(
                wk_config,
                objc.sel("setURLSchemeHandler:forURLScheme:"),
                scheme_handler,
                objc.nsStringZ("silk"),
            );
        }

        // Enable developer extras (Web Inspector) in debug mode
        if (config.debug) {
            const prefs = objc.msgSend(wk_config, objc.sel("preferences"));
            const key = objc.nsStringZ("developerExtrasEnabled");
            const yes_val = objc.msgSend_bool_ret(objc.getClass("NSNumber"), objc.sel("numberWithBool:"), true);
            objc.msgSend_id_id_void(prefs, objc.sel("setValue:forKey:"), yes_val, key);
        }

        // Create the WKWebView (frame will be set when added to window)
        const rect = objc.makeRect(0, 0, 0, 0);
        const wk_webview = objc.msgSend_rect_id(
            objc.msgSend(objc.getClass("WKWebView"), objc.sel("alloc")),
            objc.sel("initWithFrame:configuration:"),
            rect,
            wk_config,
        );

        // Enable autoresizing so the webview fills its parent
        // NSViewWidthSizable | NSViewHeightSizable = 2 | 16 = 18
        objc.msgSend_uint(wk_webview, objc.sel("setAutoresizingMask:"), 18);

        state.wk_webview = wk_webview;
        return .{ .state = state };
    }

    /// Get the underlying WKWebView as an ObjC id (for setContentView).
    pub fn view(self: *const WebView) id {
        return self.state.wk_webview;
    }

    /// Load a URL in the webview.
    pub fn loadURL(self: *const WebView, url: []const u8) void {
        const ns_url = objc.nsURL(url);
        const request = objc.msgSend_id(
            objc.getClass("NSURLRequest"),
            objc.sel("requestWithURL:"),
            ns_url,
        );
        _ = objc.msgSend_id(self.state.wk_webview, objc.sel("loadRequest:"), request);
    }

    /// Load an HTML string directly.
    pub fn loadHTML(self: *const WebView, html: []const u8) void {
        _ = objc.msgSend_id_id(
            self.state.wk_webview,
            objc.sel("loadHTMLString:baseURL:"),
            objc.nsString(html),
            null,
        );
    }

    /// Evaluate JavaScript in the webview. Fire-and-forget (no completion handler).
    pub fn evaluateJS(self: *const WebView, js: []const u8) void {
        _ = objc.msgSend_id_id(
            self.state.wk_webview,
            objc.sel("evaluateJavaScript:completionHandler:"),
            objc.nsString(js),
            null,
        );
    }

    /// Clean up.
    pub fn deinit(self: *WebView) void {
        g_state = null;
        self.state.allocator.destroy(self.state);
    }
};

// ─── WKUserScript Creation ──────────────────────────────────────────────

fn createUserScript(source: []const u8) id {
    // WKUserScriptInjectionTimeAtDocumentStart = 0
    // forMainFrameOnly = YES
    const ns_source = objc.nsString(source);

    const f: *const fn (id, SEL, id, objc.NSUInteger, bool) callconv(.c) id = @ptrCast(@alignCast(msg_ptr));
    return f(
        objc.msgSend(objc.getClass("WKUserScript"), objc.sel("alloc")),
        objc.sel("initWithSource:injectionTime:forMainFrameOnly:"),
        ns_source,
        0, // WKUserScriptInjectionTimeAtDocumentStart
        true,
    );
}

// ─── ObjC Class Registration ────────────────────────────────────────────
//
// We register two ObjC classes at runtime:
// 1. SilkMessageHandler — implements WKScriptMessageHandler
// 2. SilkSchemeHandler — implements WKURLSchemeHandler

var classes_registered: bool = false;

fn registerObjcClasses() void {
    if (classes_registered) return;
    classes_registered = true;

    registerMessageHandlerClass();
    registerSchemeHandlerClass();
}

// ─── SilkMessageHandler (WKScriptMessageHandler) ────────────────────────

fn registerMessageHandlerClass() void {
    const cls = objc.allocateClassPair("NSObject", "SilkMessageHandler") orelse return;

    _ = objc.addMethod(
        cls,
        objc.sel("userContentController:didReceiveScriptMessage:"),
        @ptrCast(&handleScriptMessage),
        "v@:@@",
    );

    _ = objc.addProtocol(cls, "WKScriptMessageHandler");
    objc.registerClassPair(cls);
}

/// Context passed through dispatch_async to evaluate JS on the next run loop tick.
const EvalContext = struct {
    ns_string: id,
    wk_webview: id,
};

/// ObjC callback: invoked when JS calls `window.webkit.messageHandlers.silk_ipc.postMessage(msg)`.
fn handleScriptMessage(_: id, _: SEL, _: id, wk_message: id) callconv(.c) void {
    const state = g_state orelse return;

    // [message body] → NSString
    const body = objc.msgSend(wk_message, objc.sel("body"));

    const utf8_fn: *const fn (id, SEL) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(msg_ptr));
    const c_str = utf8_fn(body, objc.sel("UTF8String")) orelse return;
    const raw_json = std.mem.span(c_str);

    // Call the Zig-side message handler
    const response_json = state.message_callback(raw_json) orelse return;

    // Build JS: window.__silk_dispatch({...});
    const alloc = state.allocator;
    var buf: std.ArrayList(u8) = .{};
    buf.appendSlice(alloc, "window.__silk_dispatch(") catch return;
    buf.appendSlice(alloc, response_json) catch return;
    buf.appendSlice(alloc, ");") catch return;
    alloc.free(response_json);

    // Create the NSString now (retaining it for the async callback)
    const ns_js = objc.nsString(buf.items);
    buf.deinit(alloc);

    // Retain the NSString so it survives until the async callback fires
    objc.msgSend_void(ns_js, objc.sel("retain"));

    // Allocate a context struct to pass through dispatch_async_f
    const ctx = alloc.create(EvalContext) catch return;
    ctx.* = .{ .ns_string = ns_js, .wk_webview = state.wk_webview };

    // Defer evaluateJavaScript to the next run loop tick via dispatch_async.
    // WKWebView doesn't allow evaluateJavaScript from within a
    // WKScriptMessageHandler callback (re-entrancy issue).
    objc.dispatchAsync(@ptrCast(ctx), &dispatchEvalJS);
}

/// Called by dispatch_async on the main queue — evaluates JS in the webview.
fn dispatchEvalJS(raw_ctx: ?*anyopaque) callconv(.c) void {
    const ctx: *EvalContext = @ptrCast(@alignCast(raw_ctx orelse return));
    const state = g_state orelse return;

    _ = objc.msgSend_id_id(
        ctx.wk_webview,
        objc.sel("evaluateJavaScript:completionHandler:"),
        ctx.ns_string,
        @as(id, null),
    );

    // Release the retained NSString
    objc.msgSend_void(ctx.ns_string, objc.sel("release"));

    // Free the context
    state.allocator.destroy(ctx);
}

// ─── SilkSchemeHandler (WKURLSchemeHandler) ──────────────────────────────

fn registerSchemeHandlerClass() void {
    const cls = objc.allocateClassPair("NSObject", "SilkSchemeHandler") orelse return;

    _ = objc.addMethod(
        cls,
        objc.sel("webView:startURLSchemeTask:"),
        @ptrCast(&handleSchemeTask),
        "v@:@@",
    );

    _ = objc.addMethod(
        cls,
        objc.sel("webView:stopURLSchemeTask:"),
        @ptrCast(&handleSchemeStop),
        "v@:@@",
    );

    _ = objc.addProtocol(cls, "WKURLSchemeHandler");
    objc.registerClassPair(cls);
}

/// ObjC callback: invoked when the webview requests a `silk://` URL.
fn handleSchemeTask(_: id, _: SEL, _: id, task: id) callconv(.c) void {
    const state = g_state orelse return;
    const provider = state.asset_provider orelse return;

    // Get the request URL
    const request = objc.msgSend(task, objc.sel("request"));
    const url = objc.msgSend(request, objc.sel("URL"));

    // Get the path component: silk://localhost/index.html → /index.html
    const path_ns = objc.msgSend(url, objc.sel("path"));
    const utf8_fn: *const fn (id, SEL) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(msg_ptr));
    const c_str = utf8_fn(path_ns, objc.sel("UTF8String")) orelse return;
    var path = std.mem.span(c_str);

    // Strip leading slash
    if (path.len > 0 and path[0] == '/') {
        path = path[1..];
    }

    // Default to index.html
    if (path.len == 0) {
        path = "index.html";
    }

    // Look up the asset
    const asset = provider(path) orelse {
        sendResponse(task, "Not Found", "text/plain");
        return;
    };

    sendResponse(task, asset.data, asset.mime_type);
}

fn handleSchemeStop(_: id, _: SEL, _: id, _: id) callconv(.c) void {
    // Nothing to cancel for static assets
}

// ─── Scheme Handler Helpers ─────────────────────────────────────────────

fn sendResponse(task: id, data: []const u8, mime_type: []const u8) void {
    // Create NSData
    const data_fn: *const fn (id, SEL, [*]const u8, objc.NSUInteger) callconv(.c) id = @ptrCast(@alignCast(msg_ptr));
    const ns_data = data_fn(
        objc.getClass("NSData"),
        objc.sel("dataWithBytes:length:"),
        data.ptr,
        @intCast(data.len),
    );

    // Get URL from request for the response
    const request = objc.msgSend(task, objc.sel("request"));
    const url = objc.msgSend(request, objc.sel("URL"));

    // Create NSURLResponse
    const resp_fn: *const fn (id, SEL, id, id, objc.NSInteger, id) callconv(.c) id = @ptrCast(@alignCast(msg_ptr));
    const response = resp_fn(
        objc.msgSend(objc.getClass("NSURLResponse"), objc.sel("alloc")),
        objc.sel("initWithURL:MIMEType:expectedContentLength:textEncodingName:"),
        url,
        objc.nsString(mime_type),
        @intCast(data.len),
        null,
    );

    // Send to task
    objc.msgSend_id_void(task, objc.sel("didReceiveResponse:"), response);
    objc.msgSend_id_void(task, objc.sel("didReceiveData:"), ns_data);
    objc.msgSend_void(task, objc.sel("didFinish"));
}
