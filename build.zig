const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    // ─── Shared Modules ─────────────────────────────────────────────────

    const objc_mod = b.addModule("objc", .{
        .root_source_file = b.path("src/backend/macos/objc.zig"),
        .target = target,
    });

    // Shared "silk" module — defines Context, HandlerFn.
    // Both the app and user commands import this so types match.
    const silk_mod = b.addModule("silk", .{
        .root_source_file = b.path("lib/silk.zig"),
        .target = target,
    });

    // ─── User Commands (opt-in) ─────────────────────────────────────────

    const user_zig_path = b.option([]const u8, "user-zig", "Path to custom Zig commands (e.g. src-silk/main.zig)");

    const user_commands_mod = b.addModule("user_commands", .{
        .root_source_file = if (user_zig_path) |p| .{ .cwd_relative = p } else b.path("stubs/user_stub.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "silk", .module = silk_mod },
        },
    });

    // ─── App Target ─────────────────────────────────────────────────────

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/silk.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "objc", .module = objc_mod },
            .{ .name = "silk", .module = silk_mod },
            .{ .name = "user_commands", .module = user_commands_mod },
        },
    });

    root_module.linkFramework("AppKit", .{});
    root_module.linkFramework("WebKit", .{});
    root_module.linkSystemLibrary("objc", .{});

    const exe = b.addExecutable(.{
        .name = "silk",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ─── CLI Target (no AppKit/WebKit) ────────────────────────────────────

    const cli_module = b.createModule(.{
        .root_source_file = b.path("cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cli_exe = b.addExecutable(.{
        .name = "silk-cli",
        .root_module = cli_module,
    });

    b.installArtifact(cli_exe);

    const cli_run_step = b.step("cli", "Run the CLI");

    const cli_run_cmd = b.addRunArtifact(cli_exe);
    cli_run_step.dependOn(&cli_run_cmd.step);

    cli_run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        cli_run_cmd.addArgs(args);
    }

    // ─── Tests ──────────────────────────────────────────────────────────────

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
