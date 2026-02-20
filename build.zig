const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const os = target.result.os.tag;

    // ── Dependencies ──

    const sriracha_dep = b.dependency("sriracha", .{ .target = target });
    const sriracha_mod = sriracha_dep.module("sriracha");

    // ── silk runtime binary ──

    const silk_mod = b.createModule(.{
        .root_source_file = b.path("src/silk.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sriracha", .module = sriracha_mod },
        },
    });

    if (os == .macos) {
        if (sriracha_mod.import_table.get("objc")) |objc_mod| {
            silk_mod.addImport("objc", objc_mod);
        }
    }

    const silk_exe = b.addExecutable(.{
        .name = "silk",
        .root_module = silk_mod,
    });

    if (os == .windows) {
        silk_exe.subsystem = .windows;
    }

    b.installArtifact(silk_exe);

    // ── run step (macOS: .app bundle; others: direct) ──

    const run_step = b.step("run", "Run silk");

    if (os == .macos) {
        const wf = b.addWriteFiles();
        const plist = wf.add("Info.plist",
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            \\<plist version="1.0">
            \\<dict>
            \\    <key>CFBundleName</key>
            \\    <string>Silk</string>
            \\    <key>CFBundleIdentifier</key>
            \\    <string>com.silk.app</string>
            \\    <key>CFBundleExecutable</key>
            \\    <string>silk</string>
            \\    <key>CFBundlePackageType</key>
            \\    <string>APPL</string>
            \\    <key>CFBundleVersion</key>
            \\    <string>0.1.0</string>
            \\    <key>NSHighResolutionCapable</key>
            \\    <true/>
            \\</dict>
            \\</plist>
            \\
        );
        const install_plist = b.addInstallFile(plist, "Silk.app/Contents/Info.plist");
        const install_bin = b.addInstallFile(silk_exe.getEmittedBin(), "Silk.app/Contents/MacOS/silk");

        // Ensure plain `zig build` also materializes Silk.app.
        const install_step = b.getInstallStep();
        install_step.dependOn(&install_plist.step);
        install_step.dependOn(&install_bin.step);

        const bundle_step = b.step("bundle", "Create Silk.app bundle");
        bundle_step.dependOn(&install_plist.step);
        bundle_step.dependOn(&install_bin.step);

        const bundle_path = b.getInstallPath(.prefix, "Silk.app");
        const run_cmd = b.addSystemCommand(&.{ "open", "-W", bundle_path, "--args" });
        if (b.args) |args| run_cmd.addArgs(args);
        run_cmd.step.dependOn(&install_plist.step);
        run_cmd.step.dependOn(&install_bin.step);
        run_step.dependOn(&run_cmd.step);
    } else {
        const run_cmd = b.addRunArtifact(silk_exe);
        if (b.args) |args| run_cmd.addArgs(args);
        run_step.dependOn(&run_cmd.step);
    }

    // ── silk-cli binary ──

    const cli_exe = b.addExecutable(.{
        .name = "silk-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cli/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(cli_exe);
}
