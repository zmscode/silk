//! Silk CLI — `silk dev`
//!
//! Reads silk.config.json from the current directory, spawns the dev
//! server, waits for the URL to become ready, then launches the Silk
//! app window pointing at the dev URL.

const std = @import("std");

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    // Read silk.config.json
    const cwd = std.Io.Dir.cwd();
    const config_file = cwd.openFile(io, "silk.config.json", .{}) catch {
        printErr(io, "Error: silk.config.json not found in current directory.\n");
        printErr(io, "Run 'silk init <name>' to create a new project first.\n");
        return;
    };
    defer config_file.close(io);

    const meta = try config_file.stat(io);
    const size: usize = @intCast(meta.size);
    if (size > 1024 * 1024) {
        printErr(io, "Error: silk.config.json is too large.\n");
        return;
    }

    const config_buf = try allocator.alloc(u8, size);
    defer allocator.free(config_buf);
    const bytes_read = try config_file.readPositionalAll(io, config_buf, 0);
    const config_json = config_buf[0..bytes_read];

    // Parse config
    const parsed = std.json.parseFromSlice(SilkConfig, allocator, config_json, .{
        .ignore_unknown_fields = true,
    }) catch {
        printErr(io, "Error: failed to parse silk.config.json.\n");
        return;
    };
    defer parsed.deinit();
    const config = parsed.value;

    const dev_command = config.devServer.command;
    const dev_url = config.devServer.url;
    const timeout = config.devServer.timeout;
    const title = config.window.title;

    // Check for user Zig commands and rebuild if needed
    const has_user_zig = hasUserZig(io);
    if (has_user_zig) {
        printOut(io, "Detected src-silk/main.zig — rebuilding with custom commands...\n");
        if (!rebuildWithUserZig(allocator, io)) {
            printErr(io, "Error: failed to rebuild silk with user Zig commands.\n");
            return;
        }
    }

    // Resolve the silk app binary path (next to silk-cli)
    const silk_bin = findSilkBinary(allocator) orelse {
        printErr(io, "Error: could not find 'silk' binary next to silk-cli.\n");
        printErr(io, "Make sure 'silk' is built: mise exec -- zig build\n");
        return;
    };

    printOut(io, "Starting dev server: ");
    printOut(io, dev_command);
    printOut(io, "\n");

    // Use /bin/sh -c "command" to handle npm scripts, pipes, etc.
    var dev_proc = try std.process.spawn(io, .{
        .argv = &.{ "/bin/sh", "-c", dev_command },
        .stdout = .inherit,
        .stderr = .inherit,
    });

    // Poll the dev URL until it's ready
    printOut(io, "Waiting for ");
    printOut(io, dev_url);
    printOut(io, " ...\n");

    const ready = pollUrl(io, dev_url, timeout);

    if (!ready) {
        printErr(io, "Error: dev server did not become ready in time.\n");
        printErr(io, "Check that '");
        printErr(io, dev_command);
        printErr(io, "' starts a server at ");
        printErr(io, dev_url);
        printErr(io, "\n");
        dev_proc.kill(io);
        _ = dev_proc.wait(io) catch {};
        return;
    }

    printOut(io, "Dev server ready. Launching Silk...\n");

    // Launch the silk app binary with --url and --title
    var app_proc = std.process.spawn(io, .{
        .argv = &.{ silk_bin, "--url", dev_url, "--title", title },
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch {
        printErr(io, "Error: could not launch silk binary at: ");
        printErr(io, silk_bin);
        printErr(io, "\n");
        dev_proc.kill(io);
        _ = dev_proc.wait(io) catch {};
        return;
    };

    // Wait for the app to exit
    _ = app_proc.wait(io) catch {};

    // Kill dev server after app closes
    printOut(io, "\nSilk closed. Stopping dev server...\n");
    dev_proc.kill(io);
    _ = dev_proc.wait(io) catch {};
}

// ─── Config ─────────────────────────────────────────────────────────────

const SilkConfig = struct {
    name: []const u8 = "silk-app",
    window: struct {
        title: []const u8 = "Silk",
        width: u32 = 1024,
        height: u32 = 768,
    } = .{},
    devServer: struct {
        command: []const u8 = "npm run dev",
        url: []const u8 = "http://localhost:5173",
        timeout: u32 = 30,
    } = .{},
};

// ─── URL Polling ────────────────────────────────────────────────────────

fn pollUrl(io: std.Io, url: []const u8, max_seconds: u32) bool {
    var elapsed: u32 = 0;
    while (elapsed < max_seconds) {
        var probe = std.process.spawn(io, .{
            .argv = &.{ "curl", "-sf", "--max-time", "1", "-o", "/dev/null", url },
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch {
            sleep(io);
            elapsed += 1;
            continue;
        };

        const term = probe.wait(io) catch {
            sleep(io);
            elapsed += 1;
            continue;
        };

        switch (term) {
            .exited => |code| {
                if (code == 0) return true;
            },
            else => {},
        }

        sleep(io);
        elapsed += 1;
    }
    return false;
}

fn sleep(io: std.Io) void {
    var proc = std.process.spawn(io, .{
        .argv = &.{ "sleep", "1" },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return;
    _ = proc.wait(io) catch {};
}

// ─── User Zig Detection ─────────────────────────────────────────────────

fn hasUserZig(io: std.Io) bool {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, "src-silk/main.zig", .{}) catch return false;
    return true;
}

/// Rebuild the silk binary with -Duser-zig pointing at the project's src-silk/main.zig.
/// The silk project root is two levels up from the silk-cli binary (zig-out/bin/silk-cli → project root).
fn rebuildWithUserZig(allocator: std.mem.Allocator, io: std.Io) bool {
    // Find the silk project root (where build.zig lives) — parent of zig-out/bin/
    var root_buf: [4096]u8 = undefined;
    const silk_root = findSilkRoot(&root_buf) orelse return false;

    // Get absolute path to CWD's src-silk/main.zig via realpath
    var realpath_buf: std.ArrayList(u8) = .{};
    defer realpath_buf.deinit(allocator);
    var realpath_err: std.ArrayList(u8) = .{};
    defer realpath_err.deinit(allocator);

    var realpath_proc = std.process.spawn(io, .{
        .argv = &.{ "/usr/bin/realpath", "src-silk/main.zig" },
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch return false;

    realpath_proc.collectOutput(allocator, &realpath_buf, &realpath_err, 4096) catch return false;
    const realpath_term = realpath_proc.wait(io) catch return false;
    switch (realpath_term) {
        .exited => |code| if (code != 0) return false,
        else => return false,
    }

    const abs_user_zig = std.mem.trimEnd(u8, realpath_buf.items, "\n\r");
    if (abs_user_zig.len == 0) return false;

    // Build the -Duser-zig argument
    const user_zig_arg = std.fmt.allocPrint(allocator, "-Duser-zig={s}", .{abs_user_zig}) catch return false;
    defer allocator.free(user_zig_arg);

    // Run zig build from the silk project root
    var build_proc = std.process.spawn(io, .{
        .argv = &.{ "zig", "build", user_zig_arg },
        .cwd = silk_root,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return false;

    const build_term = build_proc.wait(io) catch return false;
    switch (build_term) {
        .exited => |code| return code == 0,
        else => return false,
    }
}

fn findSilkRoot(buf: *[4096]u8) ?[]const u8 {
    // silk-cli lives at <silk-root>/zig-out/bin/silk-cli
    // So silk root is two directories up from the binary.
    var buf_size: u32 = buf.len;
    const rc = std.c._NSGetExecutablePath(buf, &buf_size);
    if (rc != 0) return null;

    const exe_path = buf[0..buf_size];

    // Strip /silk-cli filename
    const last_slash = std.mem.lastIndexOfScalar(u8, exe_path, '/') orelse return null;
    const bin_dir = exe_path[0..last_slash];

    // Strip /bin
    const second_slash = std.mem.lastIndexOfScalar(u8, bin_dir, '/') orelse return null;
    const zig_out_dir = bin_dir[0..second_slash];

    // Strip /zig-out
    const third_slash = std.mem.lastIndexOfScalar(u8, zig_out_dir, '/') orelse return null;

    // Verify this looks right by checking the last component was "zig-out"
    const zig_out_name = zig_out_dir[third_slash + 1 ..];
    if (!std.mem.eql(u8, zig_out_name, "zig-out")) return null;

    return buf[0..third_slash];
}

// ─── Binary Location ────────────────────────────────────────────────────

fn findSilkBinary(allocator: std.mem.Allocator) ?[]const u8 {
    // Use _NSGetExecutablePath to find our own path, then replace
    // the filename with "silk" to find the app binary next to us.
    var path_buf: [4096]u8 = undefined;
    var buf_size: u32 = @intCast(path_buf.len);
    const rc = std.c._NSGetExecutablePath(&path_buf, &buf_size);
    if (rc != 0) return null;

    const exe_path = path_buf[0..buf_size];

    // Find last '/' to get the directory
    const last_slash = std.mem.lastIndexOfScalar(u8, exe_path, '/') orelse return null;
    const dir = exe_path[0 .. last_slash + 1]; // include trailing slash

    // Build "dir/silk"
    const silk_path = allocator.alloc(u8, dir.len + 4) catch return null;
    @memcpy(silk_path[0..dir.len], dir);
    @memcpy(silk_path[dir.len..][0..4], "silk");

    return silk_path;
}

// ─── Helpers ────────────────────────────────────────────────────────────

fn printOut(io: std.Io, msg: []const u8) void {
    const stdout = std.Io.File.stdout();
    stdout.writeStreamingAll(io, msg) catch {};
}

fn printErr(io: std.Io, msg: []const u8) void {
    const stderr = std.Io.File.stderr();
    stderr.writeStreamingAll(io, msg) catch {};
}
