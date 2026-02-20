const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    _ = args.next(); // skip binary name

    const subcmd = args.next() orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, subcmd, "init")) {
        std.debug.print("silk init — coming in Phase 7\n", .{});
    } else if (std.mem.eql(u8, subcmd, "dev")) {
        std.debug.print("silk dev — coming in Phase 7\n", .{});
    } else if (std.mem.eql(u8, subcmd, "build")) {
        std.debug.print("silk build — coming in Phase 7\n", .{});
    } else {
        std.debug.print("unknown command: {s}\n\n", .{subcmd});
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\silk-cli
        \\
        \\Usage:
        \\  silk init [name] [--zig]   Scaffold a new Silk project
        \\  silk dev                   Start dev server
        \\  silk build                 Build for distribution
        \\
    , .{});
}
