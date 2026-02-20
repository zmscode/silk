const std = @import("std");

pub const WindowConfig = struct {
    title: []const u8 = "Silk",
    width: i32 = 1200,
    height: i32 = 800,
};

pub const PermissionsConfig = struct {
    allow_commands: []const []const u8 = &.{},
    deny_commands: []const []const u8 = &.{},
    fs_read_roots: []const []const u8 = &.{},
    fs_write_roots: []const []const u8 = &.{},
    shell_allow_programs: []const []const u8 = &.{},
};

pub const AppConfig = struct {
    window: WindowConfig = .{},
    permissions: PermissionsConfig = .{},
};

pub const LoadedConfig = struct {
    parsed: ?std.json.Parsed(std.json.Value) = null,
    cfg: AppConfig = .{},

    owned_allow_commands: []const []const u8 = &.{},
    owned_deny_commands: []const []const u8 = &.{},
    owned_fs_read_roots: []const []const u8 = &.{},
    owned_fs_write_roots: []const []const u8 = &.{},
    owned_shell_allow_programs: []const []const u8 = &.{},

    pub fn deinit(self: *LoadedConfig, allocator: std.mem.Allocator) void {
        if (self.owned_allow_commands.len > 0) allocator.free(self.owned_allow_commands);
        if (self.owned_deny_commands.len > 0) allocator.free(self.owned_deny_commands);
        if (self.owned_fs_read_roots.len > 0) allocator.free(self.owned_fs_read_roots);
        if (self.owned_fs_write_roots.len > 0) allocator.free(self.owned_fs_write_roots);
        if (self.owned_shell_allow_programs.len > 0) allocator.free(self.owned_shell_allow_programs);
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
            loaded.cfg.window.title = switch (title_val) {
                .string => |s| s,
                else => return error.InvalidWindowTitle,
            };
        }
        if (win_obj.get("width")) |w_val| {
            loaded.cfg.window.width = try parseI32(w_val);
        }
        if (win_obj.get("height")) |h_val| {
            loaded.cfg.window.height = try parseI32(h_val);
        }
    }

    if (obj.get("permissions")) |perms_val| {
        if (perms_val != .object) return error.InvalidPermissionsConfig;
        const perms_obj = perms_val.object;

        if (perms_obj.get("allow_commands")) |allow_val| {
            const commands = try parseStringArray(allocator, allow_val);
            loaded.owned_allow_commands = commands;
            loaded.cfg.permissions.allow_commands = commands;
        }

        if (perms_obj.get("deny_commands")) |deny_val| {
            const commands = try parseStringArray(allocator, deny_val);
            loaded.owned_deny_commands = commands;
            loaded.cfg.permissions.deny_commands = commands;
        }

        if (perms_obj.get("fs")) |fs_val| {
            if (fs_val != .object) return error.InvalidFsPermissions;
            const fs_obj = fs_val.object;

            if (fs_obj.get("read_roots")) |roots_val| {
                const roots = try parseStringArray(allocator, roots_val);
                loaded.owned_fs_read_roots = roots;
                loaded.cfg.permissions.fs_read_roots = roots;
            }

            if (fs_obj.get("write_roots")) |roots_val| {
                const roots = try parseStringArray(allocator, roots_val);
                loaded.owned_fs_write_roots = roots;
                loaded.cfg.permissions.fs_write_roots = roots;
            }
        }

        if (perms_obj.get("shell")) |shell_val| {
            if (shell_val != .object) return error.InvalidShellPermissions;
            const shell_obj = shell_val.object;

            if (shell_obj.get("allow_programs")) |programs_val| {
                const programs = try parseStringArray(allocator, programs_val);
                loaded.owned_shell_allow_programs = programs;
                loaded.cfg.permissions.shell_allow_programs = programs;
            }
        }
    }

    return loaded;
}

fn parseStringArray(allocator: std.mem.Allocator, v: std.json.Value) ![]const []const u8 {
    if (v != .array) return error.InvalidStringArray;
    const arr = v.array.items;
    const out = try allocator.alloc([]const u8, arr.len);
    for (arr, 0..) |item, i| {
        out[i] = switch (item) {
            .string => |s| s,
            else => return error.InvalidStringArrayItem,
        };
    }
    return out;
}

fn parseI32(v: std.json.Value) !i32 {
    const n: i64 = switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return error.InvalidInteger,
    };
    return std.math.cast(i32, n) orelse error.IntegerOutOfRange;
}
