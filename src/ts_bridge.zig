const std = @import("std");
const message = @import("ipc/message.zig");

pub const ModeAConfig = struct {
    enabled: bool = false,
    argv: []const []const u8 = &.{},
};

pub const Bridge = struct {
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    child: ?std.process.Child = null,

    pub fn init(allocator: std.mem.Allocator, cfg: ModeAConfig) !Bridge {
        if (!cfg.enabled) return error.ModeADisabled;
        if (cfg.argv.len == 0) return error.MissingHostCommand;
        return .{
            .allocator = allocator,
            .argv = cfg.argv,
            .child = null,
        };
    }

    pub fn deinit(self: *Bridge) void {
        const io = std.Io.Threaded.global_single_threaded.ioBasic();
        if (self.child) |*child| {
            child.kill(io);
            self.child = null;
        }
    }

    pub fn invoke(self: *Bridge, req: message.InvokeRequest) !std.json.Value {
        try self.ensureStarted();

        const payload = try std.json.Stringify.valueAlloc(
            self.allocator,
            std.json.Value{ .object = try buildRequest(self.allocator, req) },
            .{},
        );
        defer self.allocator.free(payload);

        const io = std.Io.Threaded.global_single_threaded.ioBasic();
        const child = &(self.child orelse return error.TsHostUnavailable);

        try child.stdin.?.writeStreamingAll(io, payload);
        try child.stdin.?.writeStreamingAll(io, "\n");

        const read_buf = try self.allocator.alloc(u8, 2 * 1024 * 1024);
        defer self.allocator.free(read_buf);

        var reader = child.stdout.?.reader(io, read_buf);
        const line = reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                self.child = null;
                return error.TsHostClosedStream;
            },
            else => return err,
        };

        return self.parseResponse(line);
    }

    fn ensureStarted(self: *Bridge) !void {
        if (self.child != null) return;

        const io = std.Io.Threaded.global_single_threaded.ioBasic();
        self.child = try std.process.spawn(io, .{
            .argv = self.argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        });
    }

    fn parseResponse(self: *Bridge, raw: []const u8) !std.json.Value {
        const trimmed = std.mem.trim(u8, raw, " \r\n\t");
        if (trimmed.len == 0) return error.EmptyHostResponse;

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, trimmed, .{});
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidHostResponse;
        const obj = parsed.value.object;

        const ok_val = obj.get("ok") orelse return error.InvalidHostResponse;
        const ok = switch (ok_val) {
            .bool => |b| b,
            else => return error.InvalidHostResponse,
        };

        if (ok) {
            const result = obj.get("result") orelse std.json.Value{ .null = {} };
            return try deepCopyJsonValue(self.allocator, result);
        }

        const err_val = obj.get("error") orelse return error.InvalidHostResponse;
        const err_msg = switch (err_val) {
            .string => |s| s,
            else => return error.InvalidHostResponse,
        };
        _ = err_msg;
        return error.HostCommandError;
    }
};

fn buildRequest(allocator: std.mem.Allocator, req: message.InvokeRequest) !std.json.ObjectMap {
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("kind", .{ .string = "invoke" });
    try obj.put("callback", .{ .integer = req.callback });
    try obj.put("cmd", .{ .string = req.cmd });
    try obj.put("args", try deepCopyJsonValue(allocator, req.args));
    return obj;
}

fn deepCopyJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
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
                try out.append(try deepCopyJsonValue(allocator, item));
            }
            break :blk .{ .array = out };
        },
        .object => |obj| blk: {
            var out = std.json.ObjectMap.init(allocator);
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                try out.put(key, try deepCopyJsonValue(allocator, entry.value_ptr.*));
            }
            break :blk .{ .object = out };
        },
    };
}
