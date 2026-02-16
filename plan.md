# Silk Implementation Plan

## Philosophy: TypeScript-First, Zig-Optional

Silk occupies the middle ground between Electron and Tauri v2:

| | Electron | **Silk** | Tauri v2 |
|---|---|---|---|
| Frontend | JS/TS | JS/TS | JS/TS |
| Backend | JS/TS (Node.js) | **TS by default, Zig opt-in** | Rust (required) |
| Native access | All via JS | All via TS SDK, extend in Zig | Must write Rust for custom commands |
| Binary size | ~150MB+ (ships Chromium) | Small (OS webview) | Small (OS webview) |

**The key insight:**
- **Electron** lets you do everything in JavaScript — file system, dialogs, shell commands, window management — all from the renderer or main process. No compiled language needed. This is great DX but ships a 150MB+ Chromium binary.
- **Tauri v2** uses the OS webview (small binary) but forces developers to write Rust for any custom backend logic. Built-in plugins cover common cases (fs, dialog, clipboard), but anything beyond that requires `#[tauri::command]` in Rust.
- **Silk** should combine the best of both: OS webview for small binaries (like Tauri), but **TypeScript-only by default** (like Electron). The `@silk/api` SDK should provide everything a developer needs out of the box — fs, dialogs, clipboard, shell, window management, HTTP, etc. — without ever touching Zig. But if a developer *wants* native performance or low-level access, they can write custom Zig commands and call them from TypeScript.

### How This Works in Practice

**TypeScript-only developer** (the default, like Electron):
```typescript
import { fs, dialog, clipboard, shell, window } from "@silk/api";

const file = await dialog.open({ filters: [{ name: "Text", extensions: ["txt"] }] });
const contents = await fs.readFile(file);
await clipboard.writeText(contents);
await shell.open("https://example.com");
```

No `src-silk/` directory needed. No Zig compilation. Just TypeScript.

**TypeScript + Zig developer** (opt-in, like Tauri):
```typescript
import { invoke } from "@silk/api";
const result = await invoke<{ hash: string }>("myapp:hash_file", { path: "/tmp/large.bin" });
```

```zig
// src-silk/main.zig — only created if the developer opts in
const silk = @import("silk");

pub fn setup(router: *silk.Router) void {
    router.register("myapp:hash_file", hashFile);
}

fn hashFile(ctx: *silk.Context, params: std.json.Value) !std.json.Value {
    // Custom Zig logic — raw performance, system APIs, etc.
}
```

---

## Implementation Phases

### Phase 1: Core App Bootstrap
- [x] Create `src/core/app.zig` — AppState struct (allocator, window, webview) with global `g_app` pointer
- [x] Rewrite `src/silk.zig` — NSApplication bootstrap, SilkAppDelegate, appDidFinishLaunching
- [x] Wire `MessageCallback` from webview.zig → `app.handleMessage` for IPC routing
- [x] Create window (1024x768, titled "Silk") + embed WKWebView as content view
- [x] Load built-in welcome HTML with IPC test button
- [x] Export window delegate callbacks (`windowShouldClose` terminates app, etc.)
- [x] Fix build.zig typos (`bakcend` → `backend`, `obcj` → `objc`)
- [x] Fix window.zig import path (`../silk.zig` → `../../silk.zig`)
- [x] Fix `dispatch_get_main_queue()` macro — use `@extern` for `_dispatch_main_q` + `@ptrCast`

**Lessons learned:**
- `dispatch_get_main_queue()` is a C macro that Zig's cImport can't translate. Must use `@extern(*anyopaque, .{ .name = "_dispatch_main_q" })` and `@ptrCast` to the expected `dispatch_queue_t` type.
- Relative `@import` paths in Zig are relative to the file's own directory, not the project root. Files in `src/backend/macos/` need `../../silk.zig` to reach `src/silk.zig`.
- The webview's `handleScriptMessage` callback runs inside WKScriptMessageHandler context — `evaluateJavaScript` silently fails if called directly. The existing `dispatchAsync` pattern (defer to next run loop tick via GCD) is correct and working.

**Ideas for improvement:**
- The `handleMessage` function in `app.zig` currently hardcodes `silk:ping` — Phase 2 will replace this with a proper router.
- Welcome HTML has inline JS that manually calls `webkit.messageHandlers.silk_ipc.postMessage()` — Phase 3 (bridge.js) will wrap this in a clean `invoke()` API.
- AppState doesn't hold `io: std.Io` yet — will need it when plugins do file I/O (Phase 4).

---

### Phase 2: IPC Router & Permissions
- [x] Create `src/core/context.zig` — Request context (allocator, window label, webview label)
- [x] Create `src/core/permissions.zig` — Permission system with 3-level hierarchy
- [x] Create `src/ipc/router.zig` — Method → handler dispatch with permission checks
- [x] Wire router into `AppState` — replace hardcoded `handleMessage` with `router.dispatch()`
- [x] Register built-in `silk:ping` handler via the router
- [x] Test: ping still works end-to-end through the new router
- [x] Add `io: std.Io` to Context/AppState for file I/O readiness (completed in Phase 4)

**Lessons learned:**
- Keeping the `handleMessage` callback thin (parse → dispatch → return) makes the code much cleaner. The 50-line hardcoded handler collapsed to 5 lines once the router existed.
- `HandlerFn` returning `anyerror!std.json.Value` lets handlers use normal Zig error handling — the router catches all errors and serializes them into IPC error responses automatically.
- Permission keys are separate from method names — a handler registered as `"fs:read"` can have permission key `"fs"`, meaning granting the `fs` namespace grants all fs commands. This decoupling is important for the TypeScript-first model where developers configure permissions at the namespace level in `silk.config.json`.
- `Context` doesn't need `io: std.Io` yet — deferring it to Phase 4 avoids threading it through code that doesn't use it.

**Ideas for improvement:**
- Router currently uses `StringHashMap` which copies nothing — method name strings must outlive the registration. Fine for static strings but worth noting for dynamic plugin registration later.
- Could add middleware/hooks (before/after handler) for logging, metrics, etc. — not needed now, but the `dispatch()` path is the right place.
- `getScope()` on Permissions returns the raw Scope — handlers will need this in Phase 4 to enforce path restrictions on fs operations.

---

### Phase 3: JS Bridge
- [x] Create `src/bridge/bridge.js` — JS IPC client (IIFE, strict mode)
- [x] Implement `window.__silk.invoke(method, params)` — Promise-based RPC with auto-incrementing IDs
- [x] Implement `window.__silk.listen(event, callback)` — event subscription returning unsubscribe function
- [x] Implement `window.__silk_dispatch(response)` — resolve/reject pending promises, attach error `.code`
- [x] Implement `window.__silk_event(data)` — dispatch to registered event listeners
- [x] Embed bridge.js via `@embedFile("bridge/bridge.js")` in silk.zig, passed as `bridge_script` to WebView
- [x] Update welcome HTML to use `await __silk.invoke('silk:ping')` instead of raw postMessage
- [x] Add "Test Unknown Method" button to verify error path (rejects with `METHOD_NOT_FOUND`)
- [x] Test: invoke returns a proper Promise that resolves (ping) and rejects (unknown method)

**Lessons learned:**
- `@embedFile` path is relative to the file containing it — `@embedFile("bridge/bridge.js")` in `src/silk.zig` resolves to `src/bridge/bridge.js`. No need to touch build.zig.
- The bridge injects at document start (WKUserScriptInjectionTimeAtDocumentStart), so `window.__silk` is available before any page scripts run. No race condition.
- The IIFE pattern `(function() { ... })()` keeps bridge internals (`pending`, `nextId`, `listeners`) private. Only `window.__silk`, `window.__silk_dispatch`, and `window.__silk_event` are exposed.
- Error objects from rejected promises carry a `.code` property (e.g. `"METHOD_NOT_FOUND"`, `"PERMISSION_DENIED"`) — this is important for the TypeScript SDK to provide typed error handling.

**Ideas for improvement:**
- Consider adding a `timeout` option to `invoke()` so hung commands don't leave dangling promises forever.
- The bridge currently has no max pending map size — a runaway caller could leak memory. Not a concern for normal use but worth noting.
- `__silk_dispatch` and `__silk_event` are globals on `window` — could namespace them under `__silk` too, but changing this would require updating the Zig-side `handleScriptMessage` which references `__silk_dispatch`. Leave as-is for now.

---

### Phase 4: Built-in Plugins (TypeScript-First Core)
This is the critical phase that makes Silk TypeScript-first. Every plugin listed here means one less reason for a developer to touch Zig.

- [x] Add `io: std.Io` to Context and AppState, thread from `main()` through router dispatch
- [x] Create `AppState.setup()` — registers all plugins, grants default permissions

#### 4a. FS Plugin — `src/plugins/fs.zig`
- [x] `fs:read` — Read file contents (text, max 10MB)
- [x] `fs:write` — Write/overwrite file
- [x] `fs:exists` — Check if path exists
- [x] `fs:readDir` — List directory entries with `name` + `isDir`
- [x] `fs:mkdir` — Create directory (optional `recursive`)
- [x] `fs:remove` — Remove file/directory (optional `recursive`)
- [x] `fs:stat` — Return `size`, `isDir`, `isFile`
- [x] Register all commands via `fs.register(&router)`

#### 4b. Dialog Plugin — `src/plugins/dialog.zig`
- [x] `dialog:open` — NSOpenPanel (directory mode, multiple selection, title)
- [x] `dialog:save` — NSSavePanel (title, default filename)
- [x] `dialog:message` — NSAlert (title, message, style: warning/critical/informational, OK+Cancel)

#### 4c. Clipboard Plugin — `src/plugins/clipboard.zig`
- [x] `clipboard:readText` — NSPasteboard generalPasteboard, stringForType:public.utf8-plain-text
- [x] `clipboard:writeText` — clearContents + setString:forType:

#### 4d. Shell Plugin — `src/plugins/shell.zig`
- [x] `shell:open` — NSWorkspace openURL: (handles both URLs and file paths)
- [x] `shell:exec` — `std.process.spawn()` with pipe stdout/stderr, collectOutput, return exitCode

#### 4e. Window Plugin — `src/plugins/window_plugin.zig`
- [x] `window:setTitle` — Set window title via NSWindow setTitle:
- [x] `window:setSize` — Get current frame, update size, setFrame:display:
- [x] `window:center` — NSWindow center
- [x] `window:close` — NSWindow performClose:
- [x] `window:show` — makeKeyAndOrderFront:
- [x] `window:hide` — orderOut:
- [x] `window:isVisible` — NSWindow isVisible
- [x] `window:setFullscreen` — toggleFullScreen:

**Lessons learned:**
- `std.process.Child` has no `.init()` in 0.16-dev. Use `std.process.spawn(io, .{ .argv = ..., .stdout = .pipe, .stderr = .pipe })` instead. The spawn returns a `Child` directly.
- `collectOutput` on `Child` takes `ArrayList(u8)` pointers for stdout/stderr — no `readToEndAlloc` on `Io.File`.
- `std.Io` must be threaded all the way from `main(init)` → `AppState` → `router.dispatch()` → `Context`. Every file and process operation in 0.16-dev requires the io parameter.
- NSPasteboard uses `public.utf8-plain-text` (UTI string), not `NSPasteboardTypeString` (which is an ObjC constant we can't easily access from Zig).
- NSAlert button return codes: `NSAlertFirstButtonReturn = 1000`, not 0 or 1.
- `NSOpenPanel runModal` returns `NSModalResponseOK = 1`.
- Window plugin accesses the main window through `g_app` global — works for single-window, but will need a window registry for multi-window (Phase 12).
- Named the file `window_plugin.zig` to avoid collision with `backend/macos/window.zig` in the module system.

**Ideas for improvement:**
- Dialog commands run on the main thread and block the event loop — fine for modal dialogs (which block by design), but worth noting.
- `shell:exec` is powerful and dangerous — currently gated behind `"shell"` permission namespace. In production, should support `Scope.commands` to whitelist specific executables.
- FS plugin uses `Dir.cwd()` for relative paths — should consider sandboxing to project directory.
- `dialog:open` doesn't support file type filters yet — would need NSOpenPanel's `allowedContentTypes` or `allowedFileTypes`.
- Clipboard plugin only handles text — binary/image clipboard support would be a future enhancement.

---

### Phase 5: TypeScript SDK (`@silk/api`)
- [x] Create `sdk/package.json` — `@silk/api` v0.1.0
- [x] Create `sdk/tsconfig.json` — ES2022, ESNext modules, declaration files
- [x] Create `sdk/src/index.ts` — re-exports all modules
- [x] Create `sdk/src/ipc.ts` — `invoke<T>()`, `listen<T>()` with bridge detection
- [x] Create `sdk/src/fs.ts` — `readFile`, `writeFile`, `exists`, `readDir`, `mkdir`, `remove`, `stat`
- [x] Create `sdk/src/dialog.ts` — `open`, `save`, `message`, `confirm` (convenience wrapper)
- [x] Create `sdk/src/clipboard.ts` — `readText`, `writeText`
- [x] Create `sdk/src/shell.ts` — `open`, `exec` with `ExecResult` type
- [x] Create `sdk/src/window.ts` — `SilkWindow` class with `getCurrent()` static factory
- [x] Create `sdk/src/types.ts` — `SilkConfig`, `WindowConfig`, IPC types, `defineConfig`
- [x] `npm run build` produces `dist/` with 8 `.js` + 8 `.d.ts` files

**Lessons learned:**
- The SDK mirrors the IPC method names exactly (e.g. `fs:read` → `fs.readFile(path)`) — this makes it easy for developers to reason about what's happening under the hood.
- `invoke<T>()` generic type parameter gives full type inference on return values without runtime overhead.
- Bridge detection (`typeof window.__silk`) lets the SDK throw clear errors when used outside a Silk webview — better DX than silent failures or cryptic "webkit is undefined" errors.
- `SilkWindow` uses a class with static `getCurrent()` factory — feels natural for JS developers and avoids global state in the module.
- `confirm()` is a convenience wrapper around `dialog:message` that returns a plain boolean — this is the kind of DX shortcut that makes the TypeScript-first experience feel polished.

**Ideas for improvement:**
- Add runtime validation in the SDK so TypeScript developers get clear errors if they pass wrong param types (rather than cryptic Zig-side parse failures).
- Consider shipping an `@silk/api/vite` plugin that auto-configures the dev server integration.
- Could add `fs.readJSON()` / `fs.writeJSON()` convenience methods that handle parse/stringify.
- `ExecResult` could include a `.ok` boolean (exitCode === 0) for ergonomic checks.
- Consider adding JSDoc comments to all exported functions for IDE hover documentation.

---

### Phase 6: Demo Frontend
- [x] Create `src/frontend/index.html` — comprehensive demo page
- [x] Sections for each plugin: IPC, Clipboard, Window, Dialog, Shell, Filesystem
- [x] Interactive controls per section (buttons, text inputs, per-section output areas)
- [x] Dark themed UI matching Silk branding (2-column grid, monospace code output)
- [x] Embedded via `@embedFile("frontend/index.html")`, replaced inline `welcome_html` multiline string
- [x] Build succeeds, app launches with full demo UI

**Lessons learned:**
- `@embedFile` is much cleaner than Zig multiline strings for HTML — editing a real `.html` file gives syntax highlighting, formatting, and no `\\` prefix noise.
- Keeping the demo HTML self-contained (no external CSS/JS imports) means it works immediately with `loadHTML()` — no asset server needed.
- Per-section output areas (instead of one shared output div) make it easy to see results from multiple plugins simultaneously without them overwriting each other.
- The Shell plugin's `exec` command is the most dangerous from a demo perspective — providing editable command/args inputs makes it testable but also shows why permissions matter.

**Ideas for improvement:**
- Could add a "log" panel that captures all IPC traffic (requests + responses) for debugging.
- Event listener demo section would be useful once backend → frontend events are implemented (Phase 13).
- Consider adding a "permissions" section that lets users test denied commands.
- The demo could display the `@silk/api` TypeScript code alongside each button to show the SDK equivalent.

---

### Phase 7: CLI — `silk init`
- [x] Create `cli/main.zig` — subcommand dispatch (`init`, `dev`, `help`, `--version`)
- [x] Create `cli/init.zig` — project scaffolding
- [x] Default scaffold: TypeScript-only (8 files: silk.config.json, package.json, tsconfig.json, vite.config.ts, src/index.html, src/main.ts, src/style.css, .gitignore)
- [x] Optional scaffold: `--zig` flag adds `src-silk/main.zig` with custom command template
- [x] Generate all template files via Zig multiline string constants (no external template files)
- [x] Add `silk-cli` target to `build.zig` (no AppKit/WebKit linking — pure Zig, no frameworks)
- [x] Error handling: "directory already exists" message instead of crash
- [x] No memory leaks (ArrayList deferred deinit)

**Lessons learned:**
- `std.process.Init.minimal.args` in 0.16-dev is a `std.process.Args` struct, not a slice. Must use `Args.Iterator.init(args)` and `iter.next()` to consume arguments, then collect into an ArrayList for slice-based access.
- The CLI target links zero frameworks — `silk-cli` binary is tiny compared to the `silk` app binary that links AppKit+WebKit+objc. This separation is important for fast CLI operations like `silk init`.
- Zig multiline strings (`\\` prefix) work well for small templates but don't support interpolation — functions like `silkConfig(name)` accept the project name but currently return static content. Dynamic template content would need `std.fmt` or manual string concatenation.
- `dir.writeFile(io, .{ .sub_path = "src/index.html", .data = ... })` creates files inside subdirectories that already exist — the `src/` directory must be created first with `createDir`.

**Ideas for improvement:**
- Templates currently hardcode `"my-silk-app"` — should interpolate the actual project name into package.json, silk.config.json, and index.html title. Would need `std.fmt.allocPrint` or arena-based string building.
- Consider adding `--template react` / `--template vue` flags for framework-specific scaffolds.
- Could auto-detect if `npm` / `bun` / `pnpm` is available and adjust the "Next steps" output accordingly.
- The scaffolded `src/main.ts` imports from `@silk/api` which isn't published to npm yet — need to handle this (local path dependency, or npm publish, or Vite alias).

---

### Phase 8: CLI — `silk dev`
- [x] Create `cli/dev.zig` — dev server management
- [x] Read `silk.config.json` from current directory (manual JSON field extraction)
- [x] Parse `devServer.command`, `devServer.url`, and `window.title` from config
- [x] Spawn dev server child process via `/bin/sh -c "command"` (handles npm scripts, pipes)
- [x] Poll dev URL until ready using `curl -sf --max-time 1` (up to 30s timeout)
- [x] Launch Silk app binary with `--url` and `--title` flags
- [x] Add `--url` and `--title` CLI arg parsing to `silk.zig` (loadURL vs loadHTML)
- [x] Resolve silk binary path via `_NSGetExecutablePath` — finds `silk` next to `silk-cli`
- [x] Clean shutdown: wait for app to exit, then kill dev server process
- [x] Error handling: missing config, missing fields, server timeout, binary not found

**Lessons learned:**
- `Child.kill(io)` returns `void` in 0.16-dev, not an error union — no `catch` needed.
- `collectOutput` requires `.stdout = .pipe` / `.stderr = .pipe` — using `.ignore` pipes then calling `collectOutput` panics on null. For fire-and-forget processes, just call `.wait(io)` directly.
- The silk app binary and silk-cli binary are separate targets — `silk dev` needs to find and spawn the app binary. Using `_NSGetExecutablePath` to resolve our own path, then replacing the filename with `silk`, is robust across working directories.
- `std.c._NSGetExecutablePath` is available in Zig's std and works on macOS without linking additional libraries.
- Spawning dev servers with `/bin/sh -c "command"` is essential — `npm run dev` needs shell expansion.

**Ideas for improvement:**
- HMR (hot module replacement) works out of the box since we point the webview at the Vite URL.
- Consider watching `src-silk/main.zig` for changes and auto-recompiling the Zig backend.
- The 30-second timeout is hardcoded — could be configurable in `silk.config.json`.
- Config parsing uses simple string search — could miss fields in edge cases (e.g. comments, duplicate keys). A proper JSON parser would be more robust.
- Should forward SIGINT to gracefully shut down both the app and dev server when the user presses Ctrl+C in the terminal.

---

### Phase 9: Custom Zig Command Loading (Opt-in Backend)
- [x] Create `lib/silk.zig` — shared type module (Context, HandlerFn, Router wrapper)
- [x] Extract Context and HandlerFn to `lib/silk.zig` so types are shared across modules
- [x] `src/core/context.zig` re-exports `silk.Context`; `src/ipc/router.zig` uses `silk.HandlerFn`
- [x] Create `stubs/user_stub.zig` — no-op stub used when `-Duser-zig` is not provided
- [x] Update `build.zig` — `silk` module (lib/silk.zig), `user_commands` module (stub or user file)
- [x] Both root and user_commands depend on `silk` module — shared types, no file overlap
- [x] `silk.Router` wrapper: opaque ptr + register function pointer — clean API boundary
- [x] `app.zig` bridge function: `routerRegisterBridge` adapts `silk.Router.register()` → internal `Router.register()`
- [x] `silk init --zig` template already matches the new API (`@import("silk")`, `*silk.Router`)
- [x] Build flag: `mise exec -- zig build -Duser-zig=src-silk/main.zig`
- [x] Test: custom commands `myapp:hello` and `myapp:add` registered and app launches clean

**Lessons learned:**
- Zig 0.16-dev enforces strict "one file, one module" — a file cannot belong to two modules. This means shared types MUST live in a dedicated module outside `src/`, not alongside the app code.
- The `silk` module (`lib/silk.zig`) defines Context, HandlerFn, and a Router wrapper. Both `root` (the app) and `user_commands` (the user's code) import `silk`, so the types are identical at compile time.
- The Router wrapper uses an opaque pointer + function pointer pattern to avoid exposing internal Router internals (StringHashMap, Permissions) to user code. This is a clean API boundary.
- `context.zig` becomes a thin re-export (`pub const Context = @import("silk").Context`), and `router.zig` imports HandlerFn from `silk`. No duplication.
- The stub module (`stubs/user_stub.zig`) imports `silk` and exports `setup(*silk.Router)` that does nothing — zero overhead when no user module is provided.

**Ideas for improvement:**
- `silk dev` should auto-detect `src-silk/main.zig` and pass `-Duser-zig` when building.
- Could add more types to the `silk` module: Permissions, Scope, AppState for advanced users.
- Consider a `silk.log()` helper in the public API for user commands to write to stderr.
- The register function pointer adds one level of indirection — negligible at registration time but worth noting.

---

## Future Phases (Post-MVP)

### Phase 10: CLI & DX Polish
Improve the developer experience across the CLI and dev workflow.
- [ ] Interpolate project name into scaffolded templates (package.json, silk.config.json, index.html title)
- [ ] Add `--template react` / `--template vue` / `--template svelte` flags to `silk init`
- [ ] Auto-detect `npm` / `bun` / `pnpm` and adjust CLI output + scaffold accordingly
- [ ] `silk dev` should auto-detect `src-silk/main.zig` and pass `-Duser-zig` automatically
- [ ] `silk dev` timeout should be configurable in `silk.config.json`
- [ ] Replace manual JSON field extraction in `silk dev` with proper `std.json` parsing
- [ ] Forward SIGINT in `silk dev` to gracefully shut down app + dev server
- [ ] Watch `src-silk/main.zig` for changes and auto-recompile Zig backend during dev

### Phase 11: SDK Polish & Publishing
Make the TypeScript SDK production-ready and publish to npm.
- [ ] Publish `@silk/api` to npm so scaffolded projects can `npm install` immediately
- [ ] Ship `@silk/api/vite` plugin for auto-configured dev server integration
- [ ] Add JSDoc comments to all exported SDK functions for IDE hover documentation
- [ ] Add runtime validation in SDK so wrong param types give clear errors (not cryptic Zig parse failures)
- [ ] `fs.readJSON()` / `fs.writeJSON()` — convenience methods with parse/stringify
- [ ] `ExecResult.ok` boolean (exitCode === 0) for ergonomic checks
- [ ] `invoke()` timeout option — prevent hung commands from leaving dangling promises
- [ ] `dialog:open` file type filters — `allowedContentTypes` / `allowedFileTypes` on NSOpenPanel
- [ ] Clipboard binary/image support (read/write images, rich text)

### Phase 12: Runtime Hardening
Security, sandboxing, and internal improvements.
- [ ] Router middleware/hooks (before/after handler) for logging, metrics, debugging
- [ ] FS sandboxing — restrict file access to project directory by default
- [ ] `shell:exec` command whitelisting via `Scope.commands` in permissions
- [ ] Bridge pending map size limit to prevent memory leaks from runaway callers
- [ ] Expose more types in `silk` module (Permissions, Scope) for advanced user commands
- [ ] IPC traffic logging / debug panel in demo UI

### Phase 13: npm Distribution
Distribute Silk as npm packages so users never need to clone the repo or install Zig.
- [ ] Create `create-silk-app` npm package — interactive scaffolder (`npm create silk-app@latest`)
  - Prompt for project name, template (vanilla/react/vue/svelte), TypeScript/JavaScript
  - Scaffold project files (same output as `silk init` but from npm)
  - Add `@silk/cli` + `@silk/api` as devDependencies in the generated project
- [ ] Create `@silk/cli` npm package — thin JS wrapper that runs the prebuilt Zig binary
  - Platform-specific packages: `@silk/cli-darwin-arm64`, `@silk/cli-darwin-x64` (Linux/Windows later)
  - Main `@silk/cli` package uses `optionalDependencies` — npm auto-downloads the right one
  - Each platform package contains the prebuilt `silk` + `silk-cli` binaries
  - JS entry script detects platform, finds the binary, and execs it with args
  - `npx silk dev`, `npx silk init`, etc. all work
- [ ] GitHub Actions release pipeline
  - On tagged release: cross-compile binaries for each target via `zig build -Dtarget=...`
  - Package each into the corresponding `@silk/cli-<platform>` npm package
  - Publish all packages to npm
- [ ] Update `@silk/api` — publish to npm so `npm install` works in scaffolded projects
- [ ] End-to-end test: `npm create silk-app@latest my-app && cd my-app && npm install && npx silk dev`

### Phase 14: Event System (Backend → Frontend)
Enable the Zig backend to push events to the frontend without a request.
- [ ] `app.emit(event, payload)` — serialize event JSON, call `evaluateJavaScript` with `__silk_event()`
- [ ] Bridge `listen()` already works — just needs backend emission support
- [ ] SDK `listen<T>(event, callback)` already typed — verify end-to-end
- [ ] Use cases: progress updates, file watchers, system notifications, real-time data

### Phase 15: HTTP Plugin
Native HTTP client that bypasses CORS — a killer feature for desktop apps.
- [ ] `http:request` — GET/POST/PUT/DELETE with headers, body, timeout
- [ ] `http:download` — stream large files to disk with progress events
- [ ] Use `std.http.Client` or NSURLSession via ObjC interop
- [ ] SDK: `http.get()`, `http.post()`, `http.request()` typed wrappers
- [ ] Pairs with event system for download progress

### Phase 16: Notification Plugin
System notifications for desktop apps.
- [ ] `notification:show` — title, body, icon, actions
- [ ] UNUserNotificationCenter on macOS (modern API)
- [ ] Handle notification click → emit event to frontend
- [ ] SDK: `notification.show()` with typed options

### Phase 17: Multi-Window Support
Enable multiple windows addressed by label.
- [ ] Window registry in AppState — `HashMap([]const u8, Window)`
- [ ] `window:create` — create new window with label, size, title, URL
- [ ] `window:focus` — bring window to front by label
- [ ] Update all window plugin commands to accept optional `label` param
- [ ] Each window gets its own webview with shared IPC router
- [ ] SDK: `new SilkWindow(label)`, `SilkWindow.create()`

### Phase 18: Tray / Menu Bar
System tray icon and native menus.
- [ ] `tray:create` — NSStatusItem with icon, tooltip
- [ ] `tray:setMenu` — define menu items with click handlers
- [ ] `menu:setApplicationMenu` — native menu bar customization
- [ ] SDK: `tray.create()`, `menu.setAppMenu()`

### Phase 19: State Management
Shared state between windows and persistent storage.
- [ ] `store:get` / `store:set` / `store:delete` — in-memory key-value store
- [ ] `store:persist` / `store:load` — save/restore to disk (JSON)
- [ ] Emit events to all windows on state change
- [ ] SDK: `store.get()`, `store.set()`, `store.subscribe()`

### Phase 20: TypeScript Config
Replace `silk.config.json` with `silk.config.ts` for type-safe config.
- [ ] `defineConfig()` in `@silk/api` already exists — make the CLI read `.ts` configs
- [ ] Evaluate via `tsx` or `ts-node` at CLI time, output JSON for the runtime
- [ ] Support conditional config (dev vs production builds)

### Phase 21: Linux Backend
Cross-platform: GTK + WebKitGTK.
- [ ] `src/backend/linux/window.zig` — GTK window management
- [ ] `src/backend/linux/webview.zig` — WebKitGTK webview embedding
- [ ] `src/backend/linux/bridge.zig` — webkit message handler equivalent
- [ ] Platform abstraction layer — compile-time backend selection via `@import("builtin")`
- [ ] Dialog, clipboard, shell plugins use Linux-native APIs
- [ ] CI: build + test on Linux

### Phase 22: Windows Backend
Cross-platform: Win32 + WebView2.
- [ ] `src/backend/windows/window.zig` — Win32 window management
- [ ] `src/backend/windows/webview.zig` — WebView2 embedding (Edge runtime)
- [ ] `src/backend/windows/bridge.zig` — WebView2 message handler
- [ ] Dialog plugin: Win32 file dialogs (IFileDialog)
- [ ] Clipboard plugin: Win32 clipboard API
- [ ] Shell plugin: ShellExecute / CreateProcess
- [ ] CI: build + test on Windows

### Phase 23: App Bundling
Package apps for distribution.
- [ ] macOS: `.app` bundle with Info.plist, icon, entitlements
- [ ] Linux: `.AppImage` or `.deb` packaging
- [ ] Windows: `.exe` installer or MSIX
- [ ] `silk build` CLI command — compile frontend (Vite build) + compile Zig + bundle
- [ ] Include `@silk/api` SDK in the bundle's webview assets

### Phase 24: Code Signing & Notarization
Required for macOS distribution.
- [ ] macOS: `codesign` integration, notarization via `notarytool`
- [ ] Windows: Authenticode signing
- [ ] `silk sign` CLI command
- [ ] CI pipeline integration docs

### Phase 25: Homebrew Distribution
Distribute Silk CLI via Homebrew so users can `brew install silk`.
- [ ] Create `homebrew-tap` GitHub repo (e.g. `silkframework/homebrew-tap`)
- [ ] Set up GitHub Actions release pipeline: cross-compile `silk` + `silk-cli` for darwin-arm64 and darwin-x86_64
- [ ] Upload tarballs as GitHub Release assets on tagged versions
- [ ] Write `Formula/silk.rb` with `on_macos` / `on_arm` / `on_intel` blocks, SHA256 hashes, `bin.install`
- [ ] Users install via `brew install silkframework/tap/silk`
- [ ] Add Linux bottles once Phase 21 (Linux Backend) is complete
- [ ] Eventually submit to homebrew-core once Silk has traction (requires building from source in CI)

### Phase 26: Auto-Updater
Keep deployed apps up to date.
- [ ] `updater:check` — poll update server for new version
- [ ] `updater:install` — download and replace binary
- [ ] Configurable update URL in `silk.config`
- [ ] SDK: `updater.check()`, `updater.install()`
- [ ] Delta updates for minimal download size

### Phase 27: Plugin Ecosystem
Allow third-party Zig plugins to be distributed and installed.
- [ ] Plugin manifest format (name, version, IPC methods, permissions)
- [ ] `silk plugin add <name>` — download and link into build
- [ ] Plugin registry / repository (GitHub-based or dedicated)
- [ ] Sandboxed permissions per plugin

---

## Build Commands

```bash
# Build & run the app (built-in demo)
mise exec -- zig build run

# Build with custom Zig commands
mise exec -- zig build -Duser-zig=src-silk/main.zig run

# Build & run CLI
mise exec -- zig build cli -- init my-app
mise exec -- zig build cli -- init my-app --zig
mise exec -- zig build cli -- dev
mise exec -- zig build cli -- help
mise exec -- zig build cli -- --version

# Run tests
mise exec -- zig build test

# Build TypeScript SDK
cd sdk && npm run build
```

---

## Directory Structure (Target)

```
silk/
├── build.zig                  # Build config (silk + silk-cli + silk module)
├── build.zig.zon              # Zig dependencies
├── mise.toml                  # Zig version pinning
├── plan.md                    # This file
├── lib/
│   └── silk.zig               # Shared types (Context, HandlerFn, Router wrapper)
├── stubs/
│   └── user_stub.zig          # No-op user commands (when -Duser-zig not set)
├── src/
│   ├── silk.zig               # App entry: NSApplication bootstrap, --url/--title args
│   ├── core/
│   │   ├── app.zig            # AppState, plugin registration, user command bridge
│   │   ├── context.zig        # Re-exports silk.Context
│   │   └── permissions.zig    # Permission system (broad + granular)
│   ├── ipc/
│   │   ├── ipc.zig            # Message protocol (Command, Event, Response)
│   │   └── router.zig         # Method → handler dispatch
│   ├── backend/
│   │   ├── macos/
│   │   │   ├── objc.zig       # ObjC runtime helpers
│   │   │   ├── window.zig     # NSWindow management
│   │   │   └── webview.zig    # WKWebView + message handler + scheme handler
│   │   ├── linux/             # (future)
│   │   └── windows/           # (future)
│   ├── plugins/
│   │   ├── fs.zig             # Filesystem plugin (7 commands)
│   │   ├── dialog.zig         # Native file/message dialogs
│   │   ├── clipboard.zig      # System clipboard
│   │   ├── shell.zig          # Open URLs, execute commands
│   │   └── window_plugin.zig  # Window management commands
│   ├── bridge/
│   │   └── bridge.js          # JS IPC bridge (injected into webview)
│   └── frontend/
│       └── index.html         # Built-in demo UI
├── cli/
│   ├── main.zig               # CLI subcommand dispatch
│   ├── init.zig               # Project scaffolding (TS-only default, --zig opt-in)
│   └── dev.zig                # Dev server management
└── sdk/
    ├── package.json           # @silk/api npm package
    ├── tsconfig.json
    └── src/
        ├── index.ts           # Re-exports
        ├── ipc.ts             # invoke(), listen()
        ├── window.ts          # SilkWindow class
        ├── fs.ts              # Typed filesystem API
        ├── dialog.ts          # Typed dialog API
        ├── clipboard.ts       # Typed clipboard API
        ├── shell.ts           # Typed shell API
        └── types.ts           # Config & IPC types
```

---

## Developer Experience Summary

```
┌─────────────────────────────────────────────────────────────┐
│                      Silk Framework                         │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              TypeScript Layer (default)                │  │
│  │                                                       │  │
│  │  @silk/api SDK                                        │  │
│  │  ├── fs.readFile(), fs.writeFile()                    │  │
│  │  ├── dialog.open(), dialog.save(), dialog.confirm()   │  │
│  │  ├── clipboard.readText(), clipboard.writeText()      │  │
│  │  ├── shell.open(), shell.exec()                       │  │
│  │  ├── SilkWindow.setTitle(), .center(), .close()       │  │
│  │  └── invoke("custom:cmd", params)  ← escape hatch    │  │
│  └──────────────────────┬────────────────────────────────┘  │
│                         │ IPC (Command/Event protocol)      │
│  ┌──────────────────────▼────────────────────────────────┐  │
│  │               Zig Runtime (built-in)                  │  │
│  │                                                       │  │
│  │  Built-in plugins: fs, dialog, clipboard, shell, win  │  │
│  │  Router + Permissions + Bridge                        │  │
│  │  OS WebView (WKWebView / WebKitGTK / WebView2)       │  │
│  └──────────────────────┬────────────────────────────────┘  │
│                         │ optional                          │
│  ┌──────────────────────▼────────────────────────────────┐  │
│  │            Custom Zig Commands (opt-in)               │  │
│  │                                                       │  │
│  │  src-silk/main.zig                                    │  │
│  │  └── router.register("myapp:heavy_compute", fn)      │  │
│  │                                                       │  │
│  │  For developers who need:                             │  │
│  │  • Raw performance (crypto, image processing)         │  │
│  │  • Direct system API access                           │  │
│  │  • Custom native integrations                         │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```
