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
    const config = parseConfig(config_json) orelse {
        printErr(io, "Error: failed to parse silk.config.json.\n");
        return;
    };

    const dev_command = config.command orelse {
        printErr(io, "Error: silk.config.json is missing devServer.command.\n");
        return;
    };
    const dev_url = config.url orelse {
        printErr(io, "Error: silk.config.json is missing devServer.url.\n");
        return;
    };
    const title = config.title orelse "Silk";

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

    const ready = pollUrl(io, dev_url, 30);

    if (!ready) {
        printErr(io, "Error: dev server did not become ready within 30 seconds.\n");
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

// ─── Config Parsing ─────────────────────────────────────────────────────

const Config = struct {
    command: ?[]const u8,
    url: ?[]const u8,
    title: ?[]const u8,
};

fn parseConfig(json: []const u8) ?Config {
    var config = Config{ .command = null, .url = null, .title = null };
    config.command = extractStringField(json, "\"command\"");
    config.url = extractStringField(json, "\"url\"");
    config.title = extractStringField(json, "\"title\"");
    return config;
}

fn extractStringField(json: []const u8, key: []const u8) ?[]const u8 {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return null;
    const after_key = json[key_pos + key.len ..];

    var i: usize = 0;
    while (i < after_key.len and (after_key[i] == ' ' or after_key[i] == ':' or after_key[i] == '\t' or after_key[i] == '\n' or after_key[i] == '\r')) : (i += 1) {}

    if (i >= after_key.len or after_key[i] != '"') return null;
    i += 1;

    const start = i;
    while (i < after_key.len and after_key[i] != '"') : (i += 1) {}
    if (i >= after_key.len) return null;

    return after_key[start..i];
}

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
