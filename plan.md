# Silk — Detailed Implementation Plan

An Electron/Tauri alternative with TypeScript developer experience and Zig runtime performance.
Core runtime is built on [sriracha](https://github.com/zmscode/sriracha) for native window + webview.
IPC model is Tauri-style command invocation (`invoke(cmd, args)`), not JSON-RPC.

---

## Current State (as of 2026-02-20)

- Runtime window + webview boot path works.
- Command IPC is wired end-to-end:
  - JS bridge (`window.__silk.invoke`)
  - Zig parser/dispatcher
  - deferred JS callback dispatch via `sriracha.scheduleCallback`
- Config-driven command + scope permissions are active.
- Built-in bootstrap commands exist: `silk:ping`, `silk:appInfo`.
- Mode A (external TS host) and Mode B (compile-in user Zig module) are both implemented.
- macOS app bundle generation is connected to `zig build`.
- CLI Phase 7 baseline is implemented (`init`, `dev`, `build`).

---

## Architecture Overview

### Command Envelope

Request (JS -> Zig):

```json
{
  "kind": "invoke",
  "callback": 1,
  "cmd": "silk:ping",
  "args": null
}
```

Response (Zig -> JS):

```json
{
  "kind": "response",
  "callback": 1,
  "ok": true,
  "result": "pong"
}
```

Error response:

```json
{
  "kind": "response",
  "callback": 1,
  "ok": false,
  "error": "Command denied by permissions"
}
```

---

## Developer Modes

| | Mode A: TypeScript Only | Mode B: TypeScript + Zig |
|---|---|---|
| **Like** | Electron | Tauri |
| **Backend handlers** | External TS process (stdio bridge) | In-process Zig command handlers |
| **IPC surface** | `invoke(cmd, args)` | `invoke(cmd, args)` |
| **Primary use case** | Fast app iteration, no Zig app code required | Max performance / native integrations |

---

## Phase Roadmap

| # | Phase | Status |
|---|---|---|
| 1 | Runtime foundation (window/webview/build) | ✅ Complete |
| 2 | Command IPC foundation | ✅ Complete |
| 3 | Built-in plugin commands | ✅ Complete |
| 4 | Config + capability permissions | ✅ Complete |
| 5 | Mode A TS command host | ✅ Complete |
| 6 | Mode B user Zig compile-in | ✅ Complete |
| 7 | CLI productization | ✅ Complete |
| 8 | TypeScript SDK | ⬜ Pending |
| 9 | Cross-platform hardening | ⬜ Pending |
| 10 | Packaging + distribution | ⬜ Pending |

---

## Phase 1 — Runtime Foundation

**Goal**
- Boot a native desktop app with webview content and stable build/run flow.

**Delivered**
- `silk` runtime executable and `silk-cli` executable built from `build.zig`.
- macOS app bundle output (`Silk.app`) generated from `zig build`.
- Window + webview creation and app lifecycle wired.

**Remaining in this phase**
- None (done).

**Acceptance criteria**
- `zig build` succeeds and produces runnable output.
- macOS run path launches bundled app via `open -W`.

---

## Phase 2 — Command IPC Foundation

**Goal**
- Provide stable Tauri-style command API between frontend and Zig runtime.

**Delivered**
- JS bridge:
  - `window.__silk.invoke(cmd, args)` Promise-based API.
  - transport detection (`webkit`, `chrome.webview`, custom hook).
  - pending callback tracking and response routing.
- Zig parser and router:
  - command envelope parsing.
  - command registration and dispatch.
  - response marshalling back to JS.
- Runtime integration:
  - bridge injection on app ready.
  - incoming script message -> parse -> dispatch -> deferred `evaluateJavaScript`.
- Command bootstrap:
  - `silk:ping`
  - `silk:appInfo`

**Technical notes**
- Deferred dispatch via `sriracha.scheduleCallback(0, ...)` avoids webview re-entrancy issues.

**Acceptance criteria**
- Frontend can invoke bootstrap commands and receive responses.
- Command-not-found and permission-denied return structured errors.

---

## Phase 3 — Built-in Plugin Commands

**Goal**
- Ship practical native capabilities through first-party command plugins.

**Current progress**
- Implemented:
  - `silk:app/version`
  - `silk:app/platform`
  - `silk:app/quit`
  - `silk:window/getFrame`
  - `silk:window/setTitle`
  - `silk:window/setSize`
  - `silk:window/show`
  - `silk:window/hide`
  - `silk:window/center`
  - `silk:fs/readText`
  - `silk:fs/writeText`
  - `silk:fs/listDir`
  - `silk:fs/stat`
  - `silk:shell/exec`
  - `silk:dialog/open`
  - `silk:dialog/save`
  - `silk:dialog/message`
  - `silk:clipboard/readText`
  - `silk:clipboard/writeText`
- Notes:
  - Shell supports argv, cwd, env overrides, stdin, and output size limits.
  - Dialog/clipboard are macOS-first implementations; cross-platform parity remains in Phase 9.

**Scope (initial plugin set)**
- `silk:fs` (read/write/list/stat)
- `silk:shell` (spawn/exec with controlled policy)
- `silk:dialog` (open/save/message)
- `silk:clipboard` (read/write text)
- `silk:window` (size/title/focus)
- `silk:app` (app metadata/lifecycle)

**Deliverables**
- Per-plugin module with `register(router)` entry.
- Consistent error taxonomy and command naming conventions.
- Unit tests for validation, argument parsing, and permission checks.

**Dependencies**
- Phase 4 capability model must define plugin command scopes.

**Acceptance criteria**
- Plugins register cleanly and respect permission gates.
- Core command paths have tests and negative-path coverage.

---

## Phase 4 — Config + Capability Permissions

**Goal**
- Move from hardcoded allowlist to config-driven, explicit capability security model.

**Status**
- Complete for current milestone: config-driven command and scoped permission policy is active.

**Deliverables**
- `silk.config.json` schema and parser.
- Capability model:
  - allow/deny by command
  - scoped controls for filesystem roots and shell program allowlist
- Validation diagnostics with actionable startup errors.
- Profile presets are deferred to post-phase improvements (config schema is ready for extension).

**Acceptance criteria**
- App start fails fast on invalid config shape.
- Commands denied unless explicitly granted by capability rules.
- FS/shell commands are additionally constrained by configured scopes.

---

## Phase 5 — Mode A (TS Command Host)

**Goal**
- Support external TypeScript command handlers with same command envelope.

**Deliverables**
- `ts_bridge.zig` process manager (spawn/restart/shutdown).
- stdio protocol bridge between webview commands and TS host.
- Non-blocking reader with main-thread handoff.
- Error and lifecycle handling for host crashes/timeouts.

**Current progress**
- Implemented:
  - Config-driven Mode A section (`mode_a.enabled`, `mode_a.argv`).
  - `src/ts_bridge.zig` stdio bridge with persistent TS host process over stdio.
  - Runtime fallback: unknown commands can be forwarded to Mode A host when enabled.
  - Worker-thread dispatch queue to keep webview callback path non-blocking.
  - App lifecycle cleanup for Mode A host process.
  - Example TS host: `examples/ts-host.mjs`.
- Post-phase improvements:
  - Host restart backoff and request timeout policy.
  - Advanced multiplexing/concurrency protocol for high-throughput Mode A traffic.

**Acceptance criteria**
- TS host handles commands with same API as in-process handlers.
- Graceful fallback/error propagation when host unavailable.

---

## Phase 6 — Mode B (User Zig Compile-In)

**Goal**
- Let user Zig modules compile directly into silk binary.

**Deliverables**
- `-Duser-zig=...` build option.
- Public host API (`lib/silk.zig`) for registration and utilities.
- Default fallback stub (`stubs/user_stub.zig`).

**Implemented**
- Build wiring:
  - `zig build -Duser-zig=path/to/user_commands.zig` now swaps the compile-in command module.
  - Default module path is `stubs/user_stub.zig` when no option is passed.
- Public API:
  - `lib/silk.zig` exports `silk.Host` registration interface for user modules.
  - Utility helpers for JSON arg parsing:
    - `expectObject(args)`
    - `getString(obj, key)`
    - `getOptionalString(obj, key)`
- Runtime integration:
  - Core runtime always calls user module registration during startup.
  - Compile-time signature checks ensure user module exports:
    - `pub fn register(host: *silk.Host) !void`
  - Invalid signatures fail at compile-time with explicit diagnostics.

**Acceptance criteria**
- User command module can be registered without editing core runtime source.
- Build fails with clear diagnostics for invalid user module signatures.

---

## Phase 7 — CLI Productization

**Goal**
- Provide complete dev/build workflow tooling.

**Commands**
- `silk init [--zig]`
- `silk dev`
- `silk build`

**Deliverables**
- Project templates via `@embedFile`.
- Dev orchestration (frontend dev server + runtime).
- Build orchestration (assets, bundles, outputs).
- Consistent user-facing binary naming (`silk` command UX).

**Implemented**
- `silk init [name] [--zig] [--force]`
  - Scaffolds a TypeScript + Vite frontend, `silk.config.json`, and bridge typings.
  - Template assets are embedded in CLI via `@embedFile` (`cli/templates/*`).
  - Optional `--zig` emits `user_commands.zig` scaffold.
- `silk dev [--no-frontend] [args...]`
  - Detects package manager (`pnpm`/`yarn`/`bun`/`npm`), auto-installs dependencies when needed.
  - Starts frontend dev server and Silk runtime together.
  - Runtime resolution order: `SILK_RUNTIME_BIN` -> `zig-out/bin/silk` -> `PATH`.
- `silk build`
  - Runs frontend build script when `package.json` exists.
  - Runs runtime release build (`zig build --release=small`) when `build.zig` exists.
- Runtime/frontend integration update:
  - New config block:
    - `frontend.dev_url`
    - `frontend.dist_entry`
  - Runtime now loads `dev_url` in dev mode or `dist_entry` file URL for built assets.

**Acceptance criteria**
- New project can be initialized and run with one command.
- Build command produces runnable release output.

---

## Phase 8 — TypeScript SDK

**Goal**
- Make command API strongly typed and easy to consume from TS apps.

**Deliverables**
- `@silk/api` package with typed wrappers and docs.
- Shared command type definitions aligned with runtime commands.
- Optional codegen pipeline from command schema.

**Acceptance criteria**
- TS compile-time checks catch invalid command names/arguments.
- SDK examples work with both Mode A and Mode B backends.

---

## Phase 9 — Cross-Platform Hardening

**Goal**
- Stabilize behavior across macOS, Windows, and Linux.

**Deliverables**
- Platform parity matrix for all core commands/plugins.
- Windows-specific and Linux-specific plugin implementations.
- CI matrix build + smoke tests across targets.

**Acceptance criteria**
- Baseline app boot and command invocations succeed on all platforms.
- Platform differences are documented and tested.

---

## Phase 10 — Packaging + Distribution

**Goal**
- Produce distributable, signed artifacts.

**Deliverables**
- macOS signing/notarization pipeline.
- Windows installer output path.
- Linux AppImage (or distro package baseline).
- Release automation and checksums.

**Acceptance criteria**
- Release artifacts install and launch cleanly on target OSes.
- Reproducible build metadata and release notes pipeline.

---

## Improvements Backlog

### P0 (Do next)

- Add origin-aware IPC sender validation and per-window/webview command policy checks.
- Add IPC timeout + cancellation for pending command callbacks.
- Introduce structured error objects (`code`, `message`, `details`) instead of string-only errors.
- Add integration tests for invoke success/error/permission-denied and malformed-payload flows.
- Add strict payload limits (request/response bytes) and rate limiting per webview.

### P1 (High-value)

- Add event channel contract (`kind: "event"`) with typed payloads and listener lifecycle APIs.
- Add streaming IPC primitive (channel/port model) for high-throughput or incremental responses.
- Add command schema and TS/Zig type/codegen pipeline, including shared error/code definitions.
- Add request correlation IDs and structured tracing logs for all command hops.
- Add crash-safe Mode A supervision (healthcheck, restart backoff, max-retry policy).

### P2 (Quality/scale)

- Add binary payload fast path for large transfers (side channel instead of JSON body).
- Command metrics (latency, failure rate, payload size histograms).
- Hot-reload developer workflow for command handlers in Mode A.
- Add plugin permission manifests (default-deny) with granular command scopes.
- Add sidecar packaging model for Mode A host (Tauri-style external binary with explicit allow rules).
- Add CSP + custom app protocol support and disable direct `file://` loading by default.

### P3 (Polish)

- Improve default app HTML demo into diagnostics dashboard.
- Add docs site with architecture + plugin authoring + security hardening guides.
- Publish compatibility matrix vs Electron/Tauri APIs and migration notes.

---

## Electron/Tauri-Informed Recommendations

The following items are direct adaptations of patterns proven in Electron and Tauri:

- Security defaults first:
  - Keep renderer/webview isolated and minimize exposed bridge surface.
  - Validate IPC sender/origin before command dispatch.
  - Enforce explicit permission grants per command scope and window.
- Capability model maturation:
  - Add capability documents keyed by window/webview IDs.
  - Document and test permission-merge behavior when multiple capabilities apply.
  - Ship default-deny plugin permission sets with narrow `allow-*` entries.
- IPC ergonomics + reliability:
  - Keep `invoke` for request/response.
  - Add typed events for fire-and-forget state changes.
  - Add stream/channel transport for large or progressive results.
  - Standardize error serialization to preserve machine-readable codes.
- Sidecar and host process model:
  - Treat external TS hosts as first-class sidecars with explicit allow rules for executable + args.
  - Add managed lifecycle policies (spawn strategy, restart backoff, graceful shutdown).
  - Add handshake/version negotiation between runtime and host.
- Performance discipline:
  - Prevent sync/blocking work on UI-critical threads.
  - Add startup and invoke latency budgets with regression checks.
  - Measure before optimizing and keep automated performance smoke checks.
- Productization parity:
  - Add updater + release signature pipeline and CLI distribution workflows.
  - Provide strict template defaults for CSP, permissions, and bridge exposure.

---

## Execution Order Recommendation

1. Phase 8: ship typed SDK + command/error schema.
2. Implement P0 security/reliability hardening backlog.
3. Complete Phase 9 cross-platform behavior parity.
4. Complete Phase 10 packaging/distribution and updater workflow.
