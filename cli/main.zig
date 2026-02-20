const builtin = @import("builtin");
const std = @import("std");

const TemplateFile = struct {
    rel_path: []const u8,
    body: []const u8,
    render_placeholders: bool = true,
};

const template_files = [_]TemplateFile{
    .{ .rel_path = "package.json", .body = @embedFile("templates/package.json.tmpl") },
    .{ .rel_path = "index.html", .body = @embedFile("templates/index.html") },
    .{ .rel_path = "src/main.ts", .body = @embedFile("templates/src_main.ts") },
    .{ .rel_path = "src/styles.css", .body = @embedFile("templates/src_styles.css"), .render_placeholders = false },
    .{ .rel_path = "src/silk.d.ts", .body = @embedFile("templates/src_silk.d.ts"), .render_placeholders = false },
    .{ .rel_path = "tsconfig.json", .body = @embedFile("templates/tsconfig.json"), .render_placeholders = false },
    .{ .rel_path = "vite.config.ts", .body = @embedFile("templates/vite.config.ts"), .render_placeholders = false },
    .{ .rel_path = "silk.config.json", .body = @embedFile("templates/silk.config.json") },
    .{ .rel_path = ".gitignore", .body = @embedFile("templates/gitignore"), .render_placeholders = false },
};

const template_user_commands = TemplateFile{
    .rel_path = "user_commands.zig",
    .body = @embedFile("templates/user_commands.zig"),
    .render_placeholders = false,
};

const PackageManager = enum {
    npm,
    pnpm,
    yarn,
    bun,
};

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.next(); // binary name

    const subcmd = args.next() orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, subcmd, "init")) {
        try runInit(init.io, init.gpa, &args);
        return;
    }

    if (std.mem.eql(u8, subcmd, "dev")) {
        try runDev(init, &args);
        return;
    }

    if (std.mem.eql(u8, subcmd, "build")) {
        try runBuild(init, &args);
        return;
    }

    std.debug.print("unknown command: {s}\n\n", .{subcmd});
    printUsage();
}

fn runInit(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    var project_dir: ?[]const u8 = null;
    var with_zig = false;
    var force = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--zig")) {
            with_zig = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--force")) {
            force = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("unknown flag for init: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        if (project_dir != null) {
            std.debug.print("unexpected extra positional argument: {s}\n", .{arg});
            return error.InvalidArgs;
        }
        project_dir = arg;
    }

    const target_dir = project_dir orelse ".";
    const app_name = try inferAppName(allocator, target_dir);
    defer allocator.free(app_name);
    const app_title = app_name;

    if (!force and !std.mem.eql(u8, target_dir, ".") and pathExists(target_dir)) {
        std.debug.print("init target already exists: {s} (use --force to overwrite files)\n", .{target_dir});
        return error.PathAlreadyExists;
    }
    try std.Io.Dir.cwd().createDirPath(io, target_dir);

    for (template_files) |tpl| {
        try writeTemplateFile(io, allocator, target_dir, app_name, app_title, tpl, force);
    }
    if (with_zig) {
        try writeTemplateFile(io, allocator, target_dir, app_name, app_title, template_user_commands, force);
    }

    std.debug.print("initialized Silk project at {s}\n", .{target_dir});
    std.debug.print("next steps:\n", .{});
    if (!std.mem.eql(u8, target_dir, ".")) {
        std.debug.print("  cd {s}\n", .{target_dir});
    }
    std.debug.print("  npm install\n", .{});
    std.debug.print("  silk dev\n", .{});
}

fn runDev(init: std.process.Init, args: *std.process.Args.Iterator) !void {
    var skip_frontend = false;
    var runtime_args = std.ArrayList([]const u8).empty;
    defer runtime_args.deinit(init.gpa);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-frontend")) {
            skip_frontend = true;
            continue;
        }
        try runtime_args.append(init.gpa, arg);
    }

    var frontend_child: ?std.process.Child = null;
    defer {
        if (frontend_child) |*child| child.kill(init.io);
    }

    if (!skip_frontend and pathExists("package.json")) {
        try ensureFrontendDependencies(init.io, init.gpa);
        const pm = detectPackageManager();
        const frontend_argv = packageManagerRunArgv(pm, "dev");
        std.debug.print("starting frontend dev server: ", .{});
        printCommand(frontend_argv);
        frontend_child = try std.process.spawn(init.io, .{
            .argv = frontend_argv,
            .cwd = ".",
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
    }

    var runtime_argv = std.ArrayList([]const u8).empty;
    defer runtime_argv.deinit(init.gpa);

    const runtime_bin = resolveRuntimeBinary(init.environ_map);
    try runtime_argv.append(init.gpa, runtime_bin);
    for (runtime_args.items) |arg| {
        try runtime_argv.append(init.gpa, arg);
    }

    std.debug.print("starting runtime: ", .{});
    printCommand(runtime_argv.items);

    var runtime_child = try std.process.spawn(init.io, .{
        .argv = runtime_argv.items,
        .cwd = ".",
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try runtime_child.wait(init.io);
    try ensureSuccess(term, "runtime");
}

fn runBuild(init: std.process.Init, args: *std.process.Args.Iterator) !void {
    if (args.next()) |arg| {
        std.debug.print("unexpected argument for build: {s}\n", .{arg});
        return error.InvalidArgs;
    }

    if (pathExists("package.json")) {
        try ensureFrontendDependencies(init.io, init.gpa);
        const pm = detectPackageManager();
        const frontend_build_argv = packageManagerRunArgv(pm, "build");
        std.debug.print("building frontend: ", .{});
        printCommand(frontend_build_argv);
        try runCommandBlocking(init.io, frontend_build_argv, ".");
    }

    if (pathExists("build.zig")) {
        const runtime_build_argv: []const []const u8 = &.{ "zig", "build", "--release=small" };
        std.debug.print("building runtime: ", .{});
        printCommand(runtime_build_argv);
        try runCommandBlocking(init.io, runtime_build_argv, ".");
        std.debug.print("build complete: zig-out/ contains runtime artifacts.\n", .{});
    } else {
        std.debug.print("frontend build complete. No build.zig found, skipping runtime build.\n", .{});
    }
}

fn ensureFrontendDependencies(io: std.Io, allocator: std.mem.Allocator) !void {
    if (!pathExists("package.json")) return;
    if (pathExists("node_modules")) return;

    const pm = detectPackageManager();
    const install_argv = packageManagerInstallArgv(pm);
    std.debug.print("installing frontend dependencies: ", .{});
    printCommand(install_argv);
    _ = allocator;
    try runCommandBlocking(io, install_argv, ".");
}

fn packageManagerInstallArgv(pm: PackageManager) []const []const u8 {
    return switch (pm) {
        .npm => &.{ "npm", "install" },
        .pnpm => &.{ "pnpm", "install" },
        .yarn => &.{ "yarn", "install" },
        .bun => &.{ "bun", "install" },
    };
}

fn packageManagerRunArgv(pm: PackageManager, script: []const u8) []const []const u8 {
    if (std.mem.eql(u8, script, "dev")) {
        return switch (pm) {
            .npm => &.{ "npm", "run", "dev" },
            .pnpm => &.{ "pnpm", "run", "dev" },
            .yarn => &.{ "yarn", "dev" },
            .bun => &.{ "bun", "run", "dev" },
        };
    }

    return switch (pm) {
        .npm => &.{ "npm", "run", "build" },
        .pnpm => &.{ "pnpm", "run", "build" },
        .yarn => &.{ "yarn", "build" },
        .bun => &.{ "bun", "run", "build" },
    };
}

fn detectPackageManager() PackageManager {
    if (pathExists("pnpm-lock.yaml")) return .pnpm;
    if (pathExists("yarn.lock")) return .yarn;
    if (pathExists("bun.lock") or pathExists("bun.lockb")) return .bun;
    return .npm;
}

fn resolveRuntimeBinary(environ: *const std.process.Environ.Map) []const u8 {
    if (environ.get("SILK_RUNTIME_BIN")) |from_env| {
        return from_env;
    }

    if (builtin.os.tag == .windows and pathExists("zig-out/bin/silk.exe")) {
        return "zig-out/bin/silk.exe";
    }
    if (pathExists("zig-out/bin/silk")) {
        return "zig-out/bin/silk";
    }
    if (builtin.os.tag == .windows) {
        return "silk.exe";
    }
    return "silk";
}

fn runCommandBlocking(io: std.Io, argv: []const []const u8, cwd: []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = cwd,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(io);
    try ensureSuccess(term, argv[0]);
}

fn ensureSuccess(term: std.process.Child.Term, name: []const u8) !void {
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("command failed ({s}), exit code {}\n", .{ name, code });
                return error.CommandFailed;
            }
        },
        .signal => |sig| {
            std.debug.print("command terminated by signal ({s}): {}\n", .{ name, @intFromEnum(sig) });
            return error.CommandFailed;
        },
        else => {
            std.debug.print("command ended unexpectedly ({s})\n", .{name});
            return error.CommandFailed;
        },
    }
}

fn printCommand(argv: []const []const u8) void {
    for (argv, 0..) |part, idx| {
        if (idx != 0) std.debug.print(" ", .{});
        std.debug.print("{s}", .{part});
    }
    std.debug.print("\n", .{});
}

fn writeTemplateFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    target_dir: []const u8,
    app_name: []const u8,
    app_title: []const u8,
    template_file: TemplateFile,
    force: bool,
) !void {
    const rendered = if (template_file.render_placeholders)
        try renderTemplate(allocator, template_file.body, app_name, app_title)
    else
        try allocator.dupe(u8, template_file.body);
    defer allocator.free(rendered);

    const full_path = try std.fs.path.join(allocator, &.{ target_dir, template_file.rel_path });
    defer allocator.free(full_path);

    if (std.fs.path.dirname(full_path)) |dir_name| {
        try std.Io.Dir.cwd().createDirPath(io, dir_name);
    }

    var file = std.Io.Dir.cwd().createFile(io, full_path, .{
        .truncate = true,
        .exclusive = !force,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            std.debug.print("file exists, skipping: {s}\n", .{full_path});
            return;
        },
        else => return err,
    };
    defer file.close(io);
    try file.writeStreamingAll(io, rendered);
}

fn renderTemplate(
    allocator: std.mem.Allocator,
    template_body: []const u8,
    app_name: []const u8,
    app_title: []const u8,
) ![]u8 {
    const with_name = try std.mem.replaceOwned(u8, allocator, template_body, "__APP_NAME__", app_name);
    defer allocator.free(with_name);
    return std.mem.replaceOwned(u8, allocator, with_name, "__APP_TITLE__", app_title);
}

fn inferAppName(allocator: std.mem.Allocator, target_dir: []const u8) ![]u8 {
    if (!std.mem.eql(u8, target_dir, ".")) {
        return allocator.dupe(u8, std.fs.path.basename(target_dir));
    }
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    return allocator.dupe(u8, std.fs.path.basename(cwd));
}

fn pathExists(path: []const u8) bool {
    const io = std.Io.Threaded.global_single_threaded.ioBasic();
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn printUsage() void {
    std.debug.print(
        \\silk
        \\
        \\Usage:
        \\  silk init [name] [--zig] [--force]  Scaffold a new Silk project
        \\  silk dev [--no-frontend] [args...]  Run frontend dev server + Silk runtime
        \\  silk build                           Build frontend assets + runtime release binary
        \\
        \\Notes:
        \\  - `silk dev` looks for runtime at SILK_RUNTIME_BIN, then zig-out/bin/silk, then PATH.
        \\  - `silk build` runs `zig build --release=small` when build.zig is present.
        \\
    , .{});
}
