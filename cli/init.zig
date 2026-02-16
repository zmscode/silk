//! Silk CLI — `silk init <name>`
//!
//! Scaffolds a new Silk project. By default generates a TypeScript-only
//! vanilla project. Pass `--template react` for a React template.
//! Pass `--zig` to include a `src-silk/` directory with a custom Zig
//! command template.

const std = @import("std");

const Template = enum { vanilla, react };

const PackageManager = enum {
    npm,
    bun,
    pnpm,

    fn installCmd(self: PackageManager) []const u8 {
        return switch (self) {
            .npm => "npm install",
            .bun => "bun install",
            .pnpm => "pnpm install",
        };
    }

    fn runCmd(self: PackageManager) []const u8 {
        return switch (self) {
            .npm => "npx silk dev",
            .bun => "bun run silk dev",
            .pnpm => "pnpm silk dev",
        };
    }

    fn devServerCmd(self: PackageManager) []const u8 {
        return switch (self) {
            .npm => "npm run dev",
            .bun => "bun run dev",
            .pnpm => "pnpm dev",
        };
    }
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    var project_name: ?[]const u8 = null;
    var with_zig = false;
    var template: Template = .vanilla;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const s = args[i];
        if (std.mem.eql(u8, s, "--zig")) {
            with_zig = true;
        } else if (std.mem.eql(u8, s, "--template")) {
            i += 1;
            if (i < args.len) {
                if (std.mem.eql(u8, args[i], "react")) {
                    template = .react;
                } else if (std.mem.eql(u8, args[i], "vanilla")) {
                    template = .vanilla;
                } else {
                    printErr(io, "Error: unknown template '");
                    printErr(io, args[i]);
                    printErr(io, "'. Available: vanilla, react\n");
                    return;
                }
            }
        } else if (s.len > 0 and s[0] != '-') {
            project_name = s;
        }
    }

    const name = project_name orelse {
        printErr(io, "Usage: silk init <project-name> [--template vanilla|react] [--zig]\n");
        return;
    };

    const title = try toTitleCase(allocator, name);
    defer allocator.free(title);

    const pm = detectPackageManager(io);

    printOut(io, "Creating Silk project: ");
    printOut(io, name);
    printOut(io, switch (template) {
        .vanilla => " (vanilla)\n",
        .react => " (react)\n",
    });

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

    // Write shared config files
    const silk_cfg = try silkConfig(allocator, name, title, pm);
    defer allocator.free(silk_cfg);
    try dir.writeFile(io, .{ .sub_path = "silk.config.json", .data = silk_cfg });
    try dir.writeFile(io, .{ .sub_path = ".gitignore", .data = gitignore });

    // Write template-specific files
    switch (template) {
        .vanilla => try scaffoldVanilla(allocator, io, dir, name, title),
        .react => try scaffoldReact(allocator, io, dir, name, title),
    }

    // Optionally create Zig backend
    if (with_zig) {
        try dir.createDir(io, "src-silk", .default_dir);
        try dir.writeFile(io, .{ .sub_path = "src-silk/main.zig", .data = zigMain });
        printOut(io, "  + src-silk/main.zig (custom Zig commands)\n");
    }

    printOut(io, "\nDone! Next steps:\n");
    printOut(io, "  cd ");
    printOut(io, name);
    printOut(io, "\n  ");
    printOut(io, pm.installCmd());
    printOut(io, "\n  ");
    printOut(io, pm.runCmd());
    printOut(io, "\n");
}

// ─── Package Manager Detection ──────────────────────────────────────────

fn detectPackageManager(io: std.Io) PackageManager {
    // Try bun first (fastest), then pnpm, then fallback to npm
    if (checkCommand(io, "bun")) return .bun;
    if (checkCommand(io, "pnpm")) return .pnpm;
    return .npm;
}

fn checkCommand(io: std.Io, cmd: []const u8) bool {
    var proc = std.process.spawn(io, .{
        .argv = &.{ cmd, "--version" },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;

    const term = proc.wait(io) catch return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

// ─── Template Scaffolding ───────────────────────────────────────────────

fn scaffoldVanilla(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, name: []const u8, title: []const u8) !void {
    const pkg_json = try vanillaPackageJson(allocator, name);
    defer allocator.free(pkg_json);
    try dir.writeFile(io, .{ .sub_path = "package.json", .data = pkg_json });

    try dir.writeFile(io, .{ .sub_path = "tsconfig.json", .data = vanilla_tsconfig });
    try dir.writeFile(io, .{ .sub_path = "vite.config.ts", .data = vanilla_vite_config });

    const idx_html = try vanillaIndexHtml(allocator, title);
    defer allocator.free(idx_html);
    try dir.writeFile(io, .{ .sub_path = "src/index.html", .data = idx_html });

    try dir.writeFile(io, .{ .sub_path = "src/main.ts", .data = vanilla_main_ts });
    try dir.writeFile(io, .{ .sub_path = "src/style.css", .data = shared_style_css });
}

fn scaffoldReact(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, name: []const u8, title: []const u8) !void {
    const pkg_json = try reactPackageJson(allocator, name);
    defer allocator.free(pkg_json);
    try dir.writeFile(io, .{ .sub_path = "package.json", .data = pkg_json });

    try dir.writeFile(io, .{ .sub_path = "tsconfig.json", .data = react_tsconfig });
    try dir.writeFile(io, .{ .sub_path = "vite.config.ts", .data = react_vite_config });

    const idx_html = try reactIndexHtml(allocator, title);
    defer allocator.free(idx_html);
    try dir.writeFile(io, .{ .sub_path = "index.html", .data = idx_html });

    const app_tsx = try reactAppTsx(allocator, title);
    defer allocator.free(app_tsx);
    try dir.writeFile(io, .{ .sub_path = "src/App.tsx", .data = app_tsx });

    try dir.writeFile(io, .{ .sub_path = "src/main.tsx", .data = react_main_tsx });
    try dir.writeFile(io, .{ .sub_path = "src/App.css", .data = shared_style_css });
    try dir.writeFile(io, .{ .sub_path = "src/vite-env.d.ts", .data = react_vite_env_dts });
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

fn toTitleCase(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .{};
    var capitalize_next = true;
    for (name) |c| {
        if (c == '-') {
            try buf.append(allocator, ' ');
            capitalize_next = true;
        } else if (capitalize_next) {
            try buf.append(allocator, std.ascii.toUpper(c));
            capitalize_next = false;
        } else {
            try buf.append(allocator, c);
        }
    }
    return try buf.toOwnedSlice(allocator);
}

// ─── Shared Templates ───────────────────────────────────────────────────

fn silkConfig(allocator: std.mem.Allocator, name: []const u8, title: []const u8, pm: PackageManager) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\{{
        \\  "name": "{s}",
        \\  "window": {{
        \\    "title": "{s}",
        \\    "width": 1024,
        \\    "height": 768
        \\  }},
        \\  "permissions": {{
        \\    "fs": true,
        \\    "clipboard": true,
        \\    "shell": false,
        \\    "dialog": true,
        \\    "window": true
        \\  }},
        \\  "devServer": {{
        \\    "command": "{s}",
        \\    "url": "http://localhost:5173"
        \\  }}
        \\}}
        \\
    , .{ name, title, pm.devServerCmd() });
}

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

const shared_style_css =
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

// ─── Vanilla Templates ──────────────────────────────────────────────────

fn vanillaPackageJson(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\{{
        \\  "name": "{s}",
        \\  "private": true,
        \\  "version": "0.1.0",
        \\  "type": "module",
        \\  "scripts": {{
        \\    "dev": "vite",
        \\    "build": "tsc && vite build",
        \\    "preview": "vite preview"
        \\  }},
        \\  "dependencies": {{
        \\    "@silkapp/api": "^0.2.0"
        \\  }},
        \\  "devDependencies": {{
        \\    "@silkapp/cli": "^0.1.0",
        \\    "typescript": "^5.7.0",
        \\    "vite": "^6.0.0"
        \\  }}
        \\}}
        \\
    , .{name});
}

const vanilla_tsconfig =
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

const vanilla_vite_config =
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

fn vanillaIndexHtml(allocator: std.mem.Allocator, title: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="UTF-8">
        \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\  <title>{s}</title>
        \\  <link rel="stylesheet" href="./style.css">
        \\</head>
        \\<body>
        \\  <div id="app">
        \\    <h1>{s}</h1>
        \\    <p>Edit <code>src/main.ts</code> to get started.</p>
        \\    <button id="ping-btn">Test IPC</button>
        \\    <pre id="output"></pre>
        \\  </div>
        \\  <script type="module" src="./main.ts"></script>
        \\</body>
        \\</html>
        \\
    , .{ title, title });
}

const vanilla_main_ts =
    \\import { invoke } from "@silkapp/api";
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

// ─── React Templates ────────────────────────────────────────────────────

fn reactPackageJson(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\{{
        \\  "name": "{s}",
        \\  "private": true,
        \\  "version": "0.1.0",
        \\  "type": "module",
        \\  "scripts": {{
        \\    "dev": "vite",
        \\    "build": "tsc -b && vite build",
        \\    "preview": "vite preview"
        \\  }},
        \\  "dependencies": {{
        \\    "@silkapp/api": "^0.2.0",
        \\    "react": "^19.0.0",
        \\    "react-dom": "^19.0.0"
        \\  }},
        \\  "devDependencies": {{
        \\    "@silkapp/cli": "^0.1.0",
        \\    "@types/react": "^19.0.0",
        \\    "@types/react-dom": "^19.0.0",
        \\    "@vitejs/plugin-react": "^4.3.0",
        \\    "typescript": "^5.7.0",
        \\    "vite": "^6.0.0"
        \\  }}
        \\}}
        \\
    , .{name});
}

const react_tsconfig =
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
    \\    "noEmit": true,
    \\    "jsx": "react-jsx"
    \\  },
    \\  "include": ["src"]
    \\}
;

const react_vite_config =
    \\import { defineConfig } from "vite";
    \\import react from "@vitejs/plugin-react";
    \\
    \\export default defineConfig({
    \\  plugins: [react()],
    \\  server: {
    \\    port: 5173,
    \\    strictPort: true,
    \\  },
    \\  build: {
    \\    outDir: "dist",
    \\  },
    \\});
;

fn reactIndexHtml(allocator: std.mem.Allocator, title: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="UTF-8">
        \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\  <title>{s}</title>
        \\</head>
        \\<body>
        \\  <div id="root"></div>
        \\  <script type="module" src="/src/main.tsx"></script>
        \\</body>
        \\</html>
        \\
    , .{title});
}

const react_main_tsx =
    \\import { StrictMode } from "react";
    \\import { createRoot } from "react-dom/client";
    \\import App from "./App";
    \\
    \\createRoot(document.getElementById("root")!).render(
    \\  <StrictMode>
    \\    <App />
    \\  </StrictMode>,
    \\);
;

fn reactAppTsx(allocator: std.mem.Allocator, title: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\import {{ useState }} from "react";
        \\import {{ invoke }} from "@silkapp/api";
        \\import "./App.css";
        \\
        \\export default function App() {{
        \\  const [output, setOutput] = useState("");
        \\
        \\  async function handlePing() {{
        \\    try {{
        \\      const result = await invoke("silk:ping");
        \\      setOutput(JSON.stringify(result, null, 2));
        \\    }} catch (e: any) {{
        \\      setOutput(`Error: ${{e.message}}`);
        \\    }}
        \\  }}
        \\
        \\  return (
        \\    <div id="app">
        \\      <h1>{s}</h1>
        \\      <p>
        \\        Edit <code>src/App.tsx</code> to get started.
        \\      </p>
        \\      <button onClick={{handlePing}}>Test IPC</button>
        \\      <pre>{{output}}</pre>
        \\    </div>
        \\  );
        \\}}
        \\
    , .{title});
}

const react_vite_env_dts =
    \\/// <reference types="vite/client" />
;
