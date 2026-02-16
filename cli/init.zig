//! Silk CLI — `silk init <name>`
//!
//! Scaffolds a new Silk project. By default generates a TypeScript-only
//! project. Pass `--zig` to include a `src-silk/` directory with a
//! custom Zig command template.

const std = @import("std");

pub fn run(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    _ = allocator;

    var project_name: ?[]const u8 = null;
    var with_zig = false;

    for (args) |s| {
        if (std.mem.eql(u8, s, "--zig")) {
            with_zig = true;
        } else if (s.len > 0 and s[0] != '-') {
            project_name = s;
        }
    }

    const name = project_name orelse {
        printErr(io, "Usage: silk init <project-name> [--zig]\n");
        return;
    };

    printOut(io, "Creating Silk project: ");
    printOut(io, name);
    printOut(io, "\n");

    // Create project directory
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, name, .default_dir) catch |e| {
        if (e == error.PathAlreadyExists) {
            printErr(io, "Error: directory '");
            printErr(io, name);
            printErr(io, "' already exists.\n");
            return;
        }
        return e;
    };

    var dir = try cwd.openDir(io, name, .{});
    defer dir.close(io);

    // Create src/ directory
    try dir.createDir(io, "src", .default_dir);

    // Write all template files
    try dir.writeFile(io, .{ .sub_path = "silk.config.json", .data = silkConfig(name) });
    try dir.writeFile(io, .{ .sub_path = "package.json", .data = packageJson(name) });
    try dir.writeFile(io, .{ .sub_path = "tsconfig.json", .data = tsconfig });
    try dir.writeFile(io, .{ .sub_path = "vite.config.ts", .data = viteConfig });
    try dir.writeFile(io, .{ .sub_path = "src/index.html", .data = indexHtml(name) });
    try dir.writeFile(io, .{ .sub_path = "src/main.ts", .data = mainTs });
    try dir.writeFile(io, .{ .sub_path = "src/style.css", .data = styleCss });
    try dir.writeFile(io, .{ .sub_path = ".gitignore", .data = gitignore });

    // Optionally create Zig backend
    if (with_zig) {
        try dir.createDir(io, "src-silk", .default_dir);
        try dir.writeFile(io, .{ .sub_path = "src-silk/main.zig", .data = zigMain });
        printOut(io, "  + src-silk/main.zig (custom Zig commands)\n");
    }

    printOut(io, "\nDone! Next steps:\n");
    printOut(io, "  cd ");
    printOut(io, name);
    printOut(io, "\n  npm install\n  silk dev\n");
}

fn printOut(io: std.Io, msg: []const u8) void {
    const stdout = std.Io.File.stdout();
    stdout.writeStreamingAll(io, msg) catch {};
}

fn printErr(io: std.Io, msg: []const u8) void {
    const stderr = std.Io.File.stderr();
    stderr.writeStreamingAll(io, msg) catch {};
}

// ─── Template Data ──────────────────────────────────────────────────────

fn silkConfig(name: []const u8) []const u8 {
    _ = name;
    return 
    \\{
    \\  "name": "my-silk-app",
    \\  "window": {
    \\    "title": "My Silk App",
    \\    "width": 1024,
    \\    "height": 768
    \\  },
    \\  "permissions": {
    \\    "fs": true,
    \\    "clipboard": true,
    \\    "shell": false,
    \\    "dialog": true,
    \\    "window": true
    \\  },
    \\  "devServer": {
    \\    "command": "npm run dev",
    \\    "url": "http://localhost:5173"
    \\  }
    \\}
    ;
}

fn packageJson(name: []const u8) []const u8 {
    _ = name;
    return 
    \\{
    \\  "name": "my-silk-app",
    \\  "private": true,
    \\  "version": "0.1.0",
    \\  "type": "module",
    \\  "scripts": {
    \\    "dev": "vite",
    \\    "build": "tsc && vite build",
    \\    "preview": "vite preview"
    \\  },
    \\  "dependencies": {
    \\    "@silk/api": "^0.1.0"
    \\  },
    \\  "devDependencies": {
    \\    "typescript": "^5.7.0",
    \\    "vite": "^6.0.0"
    \\  }
    \\}
    ;
}

const tsconfig =
    \\{
    \\  "compilerOptions": {
    \\    "target": "ES2022",
    \\    "module": "ESNext",
    \\    "moduleResolution": "bundler",
    \\    "strict": true,
    \\    "esModuleInterop": true,
    \\    "skipLibCheck": true,
    \\    "forceConsistentCasingInFileNames": true,
    \\    "resolveJsonModule": true,
    \\    "isolatedModules": true,
    \\    "noEmit": true
    \\  },
    \\  "include": ["src"]
    \\}
;

const viteConfig =
    \\import { defineConfig } from "vite";
    \\
    \\export default defineConfig({
    \\  server: {
    \\    port: 5173,
    \\    strictPort: true,
    \\  },
    \\  build: {
    \\    outDir: "dist",
    \\  },
    \\});
;

fn indexHtml(name: []const u8) []const u8 {
    _ = name;
    return 
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\  <meta charset="UTF-8">
    \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \\  <title>My Silk App</title>
    \\  <link rel="stylesheet" href="./style.css">
    \\</head>
    \\<body>
    \\  <div id="app">
    \\    <h1>My Silk App</h1>
    \\    <p>Edit <code>src/main.ts</code> to get started.</p>
    \\    <button id="ping-btn">Test IPC</button>
    \\    <pre id="output"></pre>
    \\  </div>
    \\  <script type="module" src="./main.ts"></script>
    \\</body>
    \\</html>
    ;
}

const mainTs =
    \\import { invoke } from "@silk/api";
    \\import "./style.css";
    \\
    \\const btn = document.getElementById("ping-btn")!;
    \\const output = document.getElementById("output")!;
    \\
    \\btn.addEventListener("click", async () => {
    \\  try {
    \\    const result = await invoke("silk:ping");
    \\    output.textContent = JSON.stringify(result, null, 2);
    \\  } catch (e: any) {
    \\    output.textContent = `Error: ${e.message}`;
    \\  }
    \\});
;

const styleCss =
    \\* {
    \\  margin: 0;
    \\  padding: 0;
    \\  box-sizing: border-box;
    \\}
    \\
    \\body {
    \\  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    \\  background: #0f0f1a;
    \\  color: #e0e0e0;
    \\  display: flex;
    \\  align-items: center;
    \\  justify-content: center;
    \\  min-height: 100vh;
    \\}
    \\
    \\#app {
    \\  text-align: center;
    \\}
    \\
    \\h1 {
    \\  font-size: 36px;
    \\  color: #fff;
    \\  margin-bottom: 8px;
    \\}
    \\
    \\p {
    \\  color: #888;
    \\  margin-bottom: 24px;
    \\}
    \\
    \\code {
    \\  background: #1a1a2e;
    \\  padding: 2px 8px;
    \\  border-radius: 4px;
    \\  font-family: "SF Mono", "Fira Code", monospace;
    \\  color: #7fdbca;
    \\}
    \\
    \\button {
    \\  padding: 10px 24px;
    \\  background: #e94560;
    \\  color: white;
    \\  border: none;
    \\  border-radius: 8px;
    \\  font-size: 15px;
    \\  cursor: pointer;
    \\}
    \\
    \\button:hover {
    \\  background: #c73650;
    \\}
    \\
    \\pre {
    \\  margin-top: 16px;
    \\  padding: 12px 20px;
    \\  background: #1a1a2e;
    \\  border-radius: 8px;
    \\  font-family: "SF Mono", "Fira Code", monospace;
    \\  font-size: 14px;
    \\  color: #7fdbca;
    \\  text-align: left;
    \\  min-height: 40px;
    \\}
;

const gitignore =
    \\node_modules/
    \\dist/
    \\.DS_Store
    \\*.log
;

const zigMain =
    \\//! Custom Silk Commands
    \\//!
    \\//! Register your own Zig-powered IPC commands here.
    \\//! These are called from TypeScript via invoke("myapp:command", params).
    \\
    \\const std = @import("std");
    \\const silk = @import("silk");
    \\
    \\pub fn setup(router: *silk.Router) void {
    \\    router.register("myapp:hello", &hello, null);
    \\}
    \\
    \\fn hello(ctx: *silk.Context, params: std.json.Value) !std.json.Value {
    \\    _ = params;
    \\    var obj = std.json.ObjectMap.init(ctx.allocator);
    \\    try obj.put("message", .{ .string = "Hello from Zig!" });
    \\    return .{ .object = obj };
    \\}
;
