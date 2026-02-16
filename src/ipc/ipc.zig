const std = @import("std");
const json = std.json;

// ─── Message Types ──────────────────────────────────────────────────────

/// A command message from the webview (request/response pattern).
pub const Command = struct {
    id: u64,
    method: []const u8,
    params: json.Value,
};

/// An event message (fire-and-forget pattern).
pub const Event = struct {
    event: []const u8,
    payload: json.Value,
};

/// Parsed IPC message — either a command or an event.
pub const Message = union(enum) {
    command: Command,
    event: Event,
};

// ─── Response Types ─────────────────────────────────────────────────────

pub const ErrorInfo = struct {
    code: []const u8,
    message: []const u8,
};

/// IPC response sent back to the webview.
pub const Response = union(enum) {
    ok: struct {
        id: u64,
        result: json.Value,
    },
    err: struct {
        id: u64,
        @"error": ErrorInfo,
    },
};

// ─── Flexible raw message for parsing ───────────────────────────────────

/// Internal struct — parses any incoming JSON message. Fields are optional
/// because the same struct handles both commands and events.
const RawMessage = struct {
    id: ?u64 = null,
    method: ?[]const u8 = null,
    params: ?json.Value = null,
    event: ?[]const u8 = null,
    payload: ?json.Value = null,
};

// ─── Serialization structs ──────────────────────────────────────────────

const OkEnvelope = struct {
    id: u64,
    result: json.Value,
};

const ErrEnvelope = struct {
    id: u64,
    @"error": ErrorInfo,
};

const EventEnvelope = struct {
    event: []const u8,
    payload: json.Value,
};

// ─── Public API ─────────────────────────────────────────────────────────

pub const ParseError = error{
    InvalidMessage,
    MissingCommandId,
    MissingMethod,
    MissingEventName,
};

/// Parse a raw JSON string into an IPC `Message`.
///
/// The returned `Message` contains slices that point into the `Parsed`
/// arena, so the caller must keep the returned `Parsed` alive while
/// using the message.
pub fn parseMessage(
    allocator: std.mem.Allocator,
    raw: []const u8,
) (ParseError || json.ParseFromValueError || std.mem.Allocator.Error)!struct {
    parsed: json.Parsed(RawMessage),
    message: Message,
} {
    const parsed = json.parseFromSlice(
        RawMessage,
        allocator,
        raw,
        .{ .allocate = .alloc_always },
    ) catch return error.InvalidMessage;
    errdefer parsed.deinit();

    const raw_msg = parsed.value;

    // Detect message type by which fields are present
    if (raw_msg.method != null) {
        // It's a command — id and method are required
        const id = raw_msg.id orelse return error.MissingCommandId;
        const method = raw_msg.method orelse return error.MissingMethod;
        return .{
            .parsed = parsed,
            .message = .{
                .command = .{
                    .id = id,
                    .method = method,
                    .params = raw_msg.params orelse .null,
                },
            },
        };
    }

    if (raw_msg.event != null) {
        // It's an event
        const event_name = raw_msg.event orelse return error.MissingEventName;
        return .{
            .parsed = parsed,
            .message = .{ .event = .{
                .event = event_name,
                .payload = raw_msg.payload orelse .null,
            } },
        };
    }

    return error.InvalidMessage;
}

/// Serialize an `Response` into a JSON string.
pub fn serializeResponse(allocator: std.mem.Allocator, response: Response) ![]const u8 {
    return switch (response) {
        .ok => |ok| json.Stringify.valueAlloc(allocator, OkEnvelope{
            .id = ok.id,
            .result = ok.result,
        }, .{}),
        .err => |e| json.Stringify.valueAlloc(allocator, ErrEnvelope{
            .id = e.id,
            .@"error" = e.@"error",
        }, .{}),
    };
}

/// Serialize an outgoing event into a JSON string.
pub fn serializeEvent(allocator: std.mem.Allocator, event_name: []const u8, payload: json.Value) ![]const u8 {
    return json.Stringify.valueAlloc(allocator, EventEnvelope{
        .event = event_name,
        .payload = payload,
    }, .{});
}
