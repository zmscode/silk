const std = @import("std");

pub const Permissions = struct {
    allocator: std.mem.Allocator,
    allowed_commands: std.StringHashMap(void),
    denied_commands: std.StringHashMap(void),

    fs_read_roots: []const []const u8,
    fs_write_roots: []const []const u8,
    shell_allow_programs: std.StringHashMap(void),

    pub fn initDefault(allocator: std.mem.Allocator) !Permissions {
        var p = Permissions{
            .allocator = allocator,
            .allowed_commands = std.StringHashMap(void).init(allocator),
            .denied_commands = std.StringHashMap(void).init(allocator),
            .fs_read_roots = &.{},
            .fs_write_roots = &.{},
            .shell_allow_programs = std.StringHashMap(void).init(allocator),
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
        try p.allow("silk:fs/stat");
        try p.allow("silk:shell/exec");
        try p.allow("silk:dialog/open");
        try p.allow("silk:dialog/save");
        try p.allow("silk:dialog/message");
        try p.allow("silk:clipboard/readText");
        try p.allow("silk:clipboard/writeText");
        return p;
    }

    pub fn deinit(self: *Permissions) void {
        self.allowed_commands.deinit();
        self.denied_commands.deinit();
        self.shell_allow_programs.deinit();
    }

    pub fn allow(self: *Permissions, cmd: []const u8) !void {
        try self.allowed_commands.put(cmd, {});
    }

    pub fn deny(self: *Permissions, cmd: []const u8) !void {
        try self.denied_commands.put(cmd, {});
    }

    pub fn replaceAllowlist(self: *Permissions, commands: []const []const u8) !void {
        self.allowed_commands.clearRetainingCapacity();
        for (commands) |cmd| try self.allow(cmd);
    }

    pub fn replaceDenylist(self: *Permissions, commands: []const []const u8) !void {
        self.denied_commands.clearRetainingCapacity();
        for (commands) |cmd| try self.deny(cmd);
    }

    pub fn setFsRoots(self: *Permissions, read_roots: []const []const u8, write_roots: []const []const u8) void {
        self.fs_read_roots = read_roots;
        self.fs_write_roots = write_roots;
    }

    pub fn setShellAllowPrograms(self: *Permissions, programs: []const []const u8) !void {
        self.shell_allow_programs.clearRetainingCapacity();
        for (programs) |prog| {
            try self.shell_allow_programs.put(prog, {});
        }
    }

    pub fn allows(self: *const Permissions, cmd: []const u8) bool {
        if (self.denied_commands.contains(cmd)) return false;
        return self.allowed_commands.contains(cmd);
    }

    pub fn canReadPath(self: *const Permissions, path: []const u8) bool {
        return self.pathAllowed(path, self.fs_read_roots);
    }

    pub fn canWritePath(self: *const Permissions, path: []const u8) bool {
        return self.pathAllowed(path, self.fs_write_roots);
    }

    pub fn canExecProgram(self: *const Permissions, program: []const u8) bool {
        if (self.shell_allow_programs.count() == 0) return true;
        return self.shell_allow_programs.contains(program);
    }

    fn pathAllowed(self: *const Permissions, path: []const u8, roots: []const []const u8) bool {
        if (roots.len == 0) return true;

        const target = self.resolvePath(path) catch return false;
        defer self.allocator.free(target);

        for (roots) |root| {
            const resolved_root = self.resolvePath(root) catch continue;
            defer self.allocator.free(resolved_root);
            if (isPathInside(resolved_root, target)) return true;
        }
        return false;
    }

    fn resolvePath(self: *const Permissions, path: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(path)) {
            return std.fs.path.resolve(self.allocator, &.{path});
        }

        const cwd = try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(cwd);
        return std.fs.path.resolve(self.allocator, &.{ cwd, path });
    }
};

fn isPathInside(root: []const u8, target: []const u8) bool {
    const sep = std.fs.path.sep;
    var root_end = root.len;
    while (root_end > 1 and root[root_end - 1] == sep) : (root_end -= 1) {}
    const root_trimmed = root[0..root_end];
    if (std.mem.eql(u8, root_trimmed, "")) return true;
    if (std.mem.eql(u8, target, root_trimmed)) return true;
    if (!std.mem.startsWith(u8, target, root_trimmed)) return false;
    if (target.len <= root_trimmed.len) return false;
    return target[root_trimmed.len] == sep;
}
