const std = @import("std");

pub const Permissions = struct {
    allocator: std.mem.Allocator,
    allowed_commands: std.StringHashMap(void),

    pub fn initDefault(allocator: std.mem.Allocator) !Permissions {
        var p = Permissions{
            .allocator = allocator,
            .allowed_commands = std.StringHashMap(void).init(allocator),
        };
        try p.allow("silk:ping");
        try p.allow("silk:appInfo");
        try p.allow("silk:app/version");
        try p.allow("silk:app/platform");
        try p.allow("silk:app/quit");
        try p.allow("silk:window/getFrame");
        try p.allow("silk:window/setTitle");
        try p.allow("silk:window/setSize");
        try p.allow("silk:window/show");
        try p.allow("silk:window/hide");
        try p.allow("silk:window/center");
        try p.allow("silk:fs/readText");
        try p.allow("silk:fs/writeText");
        try p.allow("silk:fs/listDir");
        try p.allow("silk:shell/exec");
        try p.allow("silk:dialog/open");
        try p.allow("silk:clipboard/readText");
        try p.allow("silk:clipboard/writeText");
        return p;
    }

    pub fn deinit(self: *Permissions) void {
        self.allowed_commands.deinit();
    }

    pub fn allow(self: *Permissions, cmd: []const u8) !void {
        try self.allowed_commands.put(cmd, {});
    }

    pub fn replaceAllowlist(self: *Permissions, commands: []const []const u8) !void {
        self.allowed_commands.clearRetainingCapacity();
        for (commands) |cmd| {
            try self.allow(cmd);
        }
    }

    pub fn allows(self: *const Permissions, cmd: []const u8) bool {
        return self.allowed_commands.contains(cmd);
    }
};
