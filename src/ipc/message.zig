const std = @import("std");

/// Incoming command invocation from the JS bridge.
pub const InvokeRequest = struct {
    callback: i64,
    cmd: []const u8,
    args: std.json.Value,
};

/// Parse raw JSON from webview postMessage.
/// Supports only the Silk command envelope:
/// {"kind":"invoke","callback":1,"cmd":"silk:ping","args":{...}}
pub fn parseInvoke(allocator: std.mem.Allocator, raw: []const u8) !struct {
    parsed: std.json.Parsed(std.json.Value),
    req: InvokeRequest,
} {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{});
    errdefer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidEnvelope;
    const obj = root.object;

    const kind_val = obj.get("kind") orelse return error.MissingKind;
    const kind: []const u8 = switch (kind_val) {
        .string => |s| s,
        else => return error.InvalidKind,
    };
    if (!std.mem.eql(u8, kind, "invoke")) return error.UnsupportedKind;

    const cb_val = obj.get("callback") orelse return error.MissingCallback;
    const callback: i64 = switch (cb_val) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return error.InvalidCallback,
    };

    const cmd_val = obj.get("cmd") orelse return error.MissingCommand;
    const cmd: []const u8 = switch (cmd_val) {
        .string => |s| s,
        else => return error.InvalidCommand,
    };

    const args = obj.get("args") orelse std.json.Value{ .null = {} };

    return .{
        .parsed = parsed,
        .req = .{
            .callback = callback,
            .cmd = cmd,
            .args = args,
        },
    };
}
