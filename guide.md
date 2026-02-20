# Silk Quick Guide

This guide shows the fastest path to scaffold, run, and build a Silk app with the current toolchain.

## 1. Build Silk

From the Silk repo root:

```bash
zig build
```

Outputs:
- `zig-out/bin/silk` (runtime)
- `zig-out/bin/silk-cli` (CLI)

## 2. Scaffold a New App

Create a new frontend project:

```bash
./zig-out/bin/silk-cli init my-app
```

Create a project with a compile-in Zig command module scaffold:

```bash
./zig-out/bin/silk-cli init my-app --zig
```

Useful flag:
- `--force` overwrites existing files where possible.

## 3. Install Frontend Dependencies

Inside the generated app folder:

```bash
npm install
```

`silk-cli dev` auto-detects package manager (`pnpm`, `yarn`, `bun`, then `npm`) and will install deps if `node_modules` is missing.

## 4. Run in Dev Mode

Run frontend dev server + Silk runtime together:

```bash
SILK_RUNTIME_BIN=/absolute/path/to/silk/zig-out/bin/silk \
/absolute/path/to/silk/zig-out/bin/silk-cli dev
```

Notes:
- `silk-cli dev` runtime lookup order:
  1. `SILK_RUNTIME_BIN`
  2. `zig-out/bin/silk` (or `zig-out/bin/silk.exe` on Windows)
  3. `silk` from `PATH`
- Pass extra runtime args after `dev`:

```bash
silk-cli dev -- --my-arg value
```

Optional:
- `silk-cli dev --no-frontend` runs only runtime.

## 5. Build

From your app project:

```bash
silk-cli build
```

Behavior:
- If `package.json` exists, runs frontend build script.
- If `build.zig` exists, runs runtime release build:

```bash
zig build --release=small
```

## 6. Frontend Config (`silk.config.json`)

The runtime reads:

- `frontend.dev_url`: URL to load in dev (example: `http://127.0.0.1:5173`)
- `frontend.dist_entry`: built HTML entry file (example: `./dist/index.html`)

If neither is set, Silk falls back to embedded demo HTML.

## 7. Mode B Compile-In Zig Commands

Compile runtime with a user Zig command module:

```bash
zig build -Duser-zig=examples/user_commands.zig
```

Required user module signature:

```zig
pub fn register(host: *silk.Host) !void
```

Register commands through `host.register("name", handler)`.

## 8. Basic Troubleshooting

- `command not found: silk`: use full path to `zig-out/bin/silk` or add it to `PATH`.
- Frontend does not load: check `frontend.dev_url` and dev server port.
- `silk-cli build` fails on frontend: run install (`npm install` / `pnpm install`) first.
- Runtime build issues with custom user module: verify the `register` signature exactly matches `*silk.Host`.
