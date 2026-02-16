# Silk Guide

Silk is a desktop application framework that lets you build native apps with TypeScript. It uses the OS webview (no bundled Chromium), so binaries are small. Everything works from TypeScript out of the box — filesystem, dialogs, clipboard, shell, window management. If you need raw performance, you can optionally write custom commands in Zig.

## Prerequisites

- **Zig 0.16-dev** — installed via [mise](https://mise.jdx.dev/):
  ```bash
  # Install mise if you don't have it
  curl https://mise.run | sh

  # The project's mise.toml pins zig = "master"
  # mise will install the right version automatically
  mise install
  ```
- **Node.js** (for the TypeScript SDK and Vite dev server)
- **macOS** (the only supported platform currently — Linux and Windows are planned)

## Building Silk

Clone the repo and build both targets:

```bash
git clone <repo-url> silk
cd silk

# Build the app runtime + CLI
mise exec -- zig build

# The binaries are at:
#   zig-out/bin/silk       — the app runtime (links AppKit + WebKit)
#   zig-out/bin/silk-cli   — the CLI tool (no framework dependencies)
```

To build the TypeScript SDK:

```bash
cd sdk
npm install
npm run build
cd ..
```

## Quick Start: Create a New Project

```bash
# Scaffold a new TypeScript-only project
mise exec -- zig build cli -- init my-app

# Or include a Zig backend for custom commands
mise exec -- zig build cli -- init my-app --zig
```

This creates:

```
my-app/
├── silk.config.json       # App config (window size, permissions, dev server)
├── package.json           # Node dependencies
├── tsconfig.json
├── vite.config.ts
├── .gitignore
└── src/
    ├── index.html         # Your app's HTML
    ├── main.ts            # Entry point — imports from @silk/api
    └── style.css
```

With `--zig`, you also get:

```
└── src-silk/
    └── main.zig           # Custom Zig commands (opt-in)
```

## Project Configuration

`silk.config.json` controls your app:

```json
{
  "name": "my-silk-app",
  "window": {
    "title": "My Silk App",
    "width": 1024,
    "height": 768
  },
  "permissions": {
    "fs": true,
    "clipboard": true,
    "shell": false,
    "dialog": true,
    "window": true
  },
  "devServer": {
    "command": "npm run dev",
    "url": "http://localhost:5173"
  }
}
```

Permissions control which APIs your frontend can access. Set `"shell": false` to prevent `shell.exec()` from being called, for example.

## Development Workflow

```bash
cd my-app
npm install

# Start the dev server + open the app window
silk dev
```

`silk dev` does the following:
1. Reads `silk.config.json`
2. Spawns your dev server (`npm run dev` by default)
3. Waits for the dev URL to become ready
4. Launches the Silk app window pointing at that URL
5. When you close the window, it stops the dev server

Hot module replacement (HMR) works out of the box since the webview points at your Vite dev server.

> **Note:** Currently `silk dev` expects the `silk` and `silk-cli` binaries to be in the same directory. When running from the build output, this is `zig-out/bin/`. You can add it to your PATH or symlink:
> ```bash
> ln -s $(pwd)/zig-out/bin/silk-cli /usr/local/bin/silk
> ln -s $(pwd)/zig-out/bin/silk /usr/local/bin/silk-runtime
> ```

## Running the Built-in Demo

If you just want to see Silk in action without creating a project:

```bash
mise exec -- zig build run
```

This launches the app with a built-in demo page that lets you test every plugin interactively — IPC, clipboard, window management, dialogs, shell commands, and filesystem operations.

## TypeScript SDK (`@silk/api`)

The SDK gives you typed access to all native functionality. No Zig required.

### IPC

The foundation — call any registered command or listen for events:

```typescript
import { invoke, listen } from "@silk/api";

// Call a command
const result = await invoke<{ message: string }>("silk:ping");

// Listen for events (returns an unsubscribe function)
const unlisten = listen<{ count: number }>("my-event", (data) => {
  console.log(data.count);
});
unlisten(); // stop listening
```

### Filesystem

Read, write, and manage files and directories:

```typescript
import { fs } from "@silk/api";

// Read and write files
const contents = await fs.readFile("/path/to/file.txt");
await fs.writeFile("/path/to/output.txt", "Hello from Silk!");

// Check existence
if (await fs.exists("/path/to/file.txt")) {
  // ...
}

// List directory contents
const entries = await fs.readDir("/path/to/dir");
// entries: [{ name: "file.txt", isDir: false }, { name: "subdir", isDir: true }]

// Create directories
await fs.mkdir("/path/to/new/dir", { recursive: true });

// Remove files or directories
await fs.remove("/path/to/file.txt");
await fs.remove("/path/to/dir", { recursive: true });

// Get file info
const info = await fs.stat("/path/to/file.txt");
// info: { size: 1234, isDir: false, isFile: true }
```

### Dialogs

Native file pickers and message boxes:

```typescript
import { dialog } from "@silk/api";

// Open file picker
const files = await dialog.open();
// files: ["/Users/you/picked-file.txt"] or null if cancelled

// Open with options
const dirs = await dialog.open({ directory: true, multiple: true, title: "Pick folders" });

// Save file picker
const savePath = await dialog.save({ title: "Save as...", defaultName: "output.txt" });

// Message dialog (returns true if confirmed)
const ok = await dialog.message("Are you sure?", { title: "Confirm", style: "warning" });

// Convenience confirm shorthand
if (await dialog.confirm("Delete this file?", "Confirm Delete")) {
  // user clicked OK
}
```

### Clipboard

Read and write the system clipboard:

```typescript
import { clipboard } from "@silk/api";

// Read clipboard text
const text = await clipboard.readText();

// Write to clipboard
await clipboard.writeText("Copied from Silk!");
```

### Shell

Open URLs/files and execute commands:

```typescript
import { shell } from "@silk/api";

// Open a URL in the default browser
await shell.open("https://example.com");

// Open a file with its default app
await shell.open("/path/to/document.pdf");

// Execute a command
const result = await shell.exec("ls", ["-la", "/tmp"]);
// result: { stdout: "...", stderr: "...", exitCode: 0 }
```

> **Note:** `shell.exec` requires the `shell` permission to be enabled in `silk.config.json`.

### Window

Control the app window:

```typescript
import { SilkWindow } from "@silk/api";

const win = SilkWindow.getCurrent();

await win.setTitle("New Title");
await win.setSize(800, 600);
await win.center();
await win.setFullscreen();

// Visibility
await win.hide();
await win.show();
const visible = await win.isVisible();

// Close the window (terminates the app)
await win.close();
```

## Custom Zig Commands (Optional)

If you need native performance or system-level access beyond what the SDK provides, you can write custom commands in Zig.

### Setup

Scaffold with the `--zig` flag:

```bash
mise exec -- zig build cli -- init my-app --zig
```

Or add `src-silk/main.zig` manually to an existing project:

```zig
// src-silk/main.zig
const std = @import("std");
const silk = @import("silk");

pub fn setup(router: *silk.Router) void {
    router.register("myapp:hello", &hello, null);
    router.register("myapp:add", &add, null);
}

fn hello(ctx: *silk.Context, params: std.json.Value) !std.json.Value {
    _ = params;
    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("message", .{ .string = "Hello from Zig!" });
    return .{ .object = obj };
}

fn add(ctx: *silk.Context, params: std.json.Value) !std.json.Value {
    const obj = params.object;
    const a = obj.get("a").?.integer;
    const b = obj.get("b").?.integer;
    var result = std.json.ObjectMap.init(ctx.allocator);
    try result.put("sum", .{ .integer = a + b });
    return .{ .object = result };
}
```

### Building with Custom Commands

Pass the `-Duser-zig` flag to include your Zig commands:

```bash
mise exec -- zig build -Duser-zig=src-silk/main.zig run
```

Without this flag, the app builds with a no-op stub — zero overhead.

### Calling from TypeScript

```typescript
import { invoke } from "@silk/api";

const greeting = await invoke<{ message: string }>("myapp:hello");
console.log(greeting.message); // "Hello from Zig!"

const math = await invoke<{ sum: number }>("myapp:add", { a: 10, b: 20 });
console.log(math.sum); // 30
```

### What You Get in Zig

Your handler receives:

- **`ctx.allocator`** — arena allocator, freed after the response is sent
- **`ctx.io`** — `std.Io` for file/process operations
- **`params`** — `std.json.Value` with whatever the TypeScript side sent
- Return a `std.json.Value` object — it gets serialized back to TypeScript automatically
- Errors are caught by the router and sent back as IPC error responses

## CLI Reference

```
silk <command> [options]

Commands:
  init <name>       Create a new Silk project
  init <name> --zig Create a project with Zig backend template
  dev               Start dev server + open app window
  help              Show help
  --version, -v     Show version
```

## Build Commands Reference

```bash
# Build everything (app + CLI)
mise exec -- zig build

# Build and run the app (built-in demo)
mise exec -- zig build run

# Build and run with custom Zig commands
mise exec -- zig build -Duser-zig=src-silk/main.zig run

# Run the CLI
mise exec -- zig build cli -- <command>

# Run tests
mise exec -- zig build test

# Build the TypeScript SDK
cd sdk && npm run build
```

## Architecture Overview

```
Your TypeScript App
        |
        | @silk/api SDK (fs, dialog, clipboard, shell, window)
        |
   JS Bridge (invoke / listen)
        |
        | IPC (Command/Event protocol over WKScriptMessageHandler)
        |
   Zig Runtime
   ├── Router (method dispatch + permission checks)
   ├── Built-in plugins (fs, dialog, clipboard, shell, window)
   └── Your custom Zig commands (optional, via src-silk/main.zig)
        |
   OS Webview (WKWebView on macOS)
```

## Current Limitations

- **macOS only** — Linux (GTK + WebKitGTK) and Windows (WebView2) backends are planned
- **Single window** — multi-window support is planned
- **No app bundling yet** — no `.app` bundle, code signing, or notarization
- **`@silk/api` is not on npm** — scaffolded projects reference it but you'll need to link it locally for now
- **No event push from backend** — `listen()` is wired up on the JS side but the Zig runtime doesn't emit events yet
