//! Silk CLI — Entry Point
//!
//! Subcommand dispatch for `silk init`, `silk dev`, `silk help`.

const std = @import("std");
const init_cmd = @import("init.zig");
const dev_cmd = @import("dev.zig");

pub fn main(proc: std.process.Init) !void {
    const io = proc.io;
    const allocator = proc.gpa;

    // Collect args from iterator into a slice
    var args_list: std.ArrayList([]const u8) = .{};
    defer args_list.deinit(allocator);
    var iter = std.process.Args.Iterator.init(proc.minimal.args);
    while (iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }
    const args = args_list.items;

    // Skip argv[0] (the executable name)
    if (args.len < 2) {
        printUsage(io);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "init")) {
        try init_cmd.run(allocator, io, args[2..]);
    } else if (std.mem.eql(u8, command, "dev")) {
        try dev_cmd.run(allocator, io);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage(io);
    } else if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        printOut(io, "silk 0.1.0\n");
    } else {
        printErr(io, "Unknown command: ");
        printErr(io, command);
        printErr(io, "\n\n");
        printUsage(io);
    }
}

fn printUsage(io: std.Io) void {
    const usage =
        \\Usage: silk <command> [options]
        \\
        \\Commands:
        \\  init <name>       Create a new Silk project
        \\  dev               Start development server
        \\  help              Show this help message
        \\
        \\Options:
        \\  --version, -v     Show version
        \\  --help, -h        Show help
        \\
    ;
    printOut(io, usage);
}

fn printOut(io: std.Io, msg: []const u8) void {
    const stdout = std.Io.File.stdout();
    stdout.writeStreamingAll(io, msg) catch {};
}

fn printErr(io: std.Io, msg: []const u8) void {
    const stderr = std.Io.File.stderr();
    stderr.writeStreamingAll(io, msg) catch {};
}
