const std = @import("std");

pub const AppConfig = struct {
    title: []const u8 = "Silk",
    width: i32 = 1200,
    height: i32 = 800,
    allowed_commands: []const []const u8 = &.{},
};

pub const LoadedConfig = struct {
    parsed: ?std.json.Parsed(std.json.Value) = null,
    cfg: AppConfig = .{},
    owned_allowed_commands: []const []const u8 = &.{},

    pub fn deinit(self: *LoadedConfig, allocator: std.mem.Allocator) void {
        if (self.owned_allowed_commands.len > 0) {
            allocator.free(self.owned_allowed_commands);
        }
        if (self.parsed) |*p| p.deinit();
    }
};

pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !LoadedConfig {
    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer allocator.free(raw);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{});
    errdefer parsed.deinit();

    var loaded: LoadedConfig = .{ .parsed = parsed };
    errdefer loaded.deinit(allocator);

    const root = parsed.value;
    if (root != .object) return error.InvalidConfig;
    const obj = root.object;

    if (obj.get("window")) |win_val| {
        if (win_val != .object) return error.InvalidWindowConfig;
        const win_obj = win_val.object;

        if (win_obj.get("title")) |title_val| {
            loaded.cfg.title = switch (title_val) {
                .string => |s| s,
                else => return error.InvalidWindowTitle,
            };
        }
        if (win_obj.get("width")) |w_val| {
            loaded.cfg.width = try parseI32(w_val);
        }
        if (win_obj.get("height")) |h_val| {
            loaded.cfg.height = try parseI32(h_val);
        }
    }

    if (obj.get("permissions")) |perms_val| {
        if (perms_val != .object) return error.InvalidPermissionsConfig;
        const perms_obj = perms_val.object;

        if (perms_obj.get("allow_commands")) |allow_val| {
            if (allow_val != .array) return error.InvalidAllowCommands;
            const arr = allow_val.array.items;
            const commands = try allocator.alloc([]const u8, arr.len);
            loaded.owned_allowed_commands = commands;
            for (arr, 0..) |item, i| {
                commands[i] = switch (item) {
                    .string => |s| s,
                    else => return error.InvalidAllowCommandEntry,
                };
            }
            loaded.cfg.allowed_commands = commands;
        }
    }

    return loaded;
}

fn parseI32(v: std.json.Value) !i32 {
    const n: i64 = switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return error.InvalidInteger,
    };
    return std.math.cast(i32, n) orelse error.IntegerOutOfRange;
}
