#!/usr/bin/env node

import { mkdir, writeFile, access } from "node:fs/promises";
import { join } from "node:path";
import { createInterface } from "node:readline/promises";

// ─── Argument Parsing ───────────────────────────────────────────────────

const args = process.argv.slice(2);
const zigFlag = args.includes("--zig");
const positional = args.filter((a) => !a.startsWith("--"));
const cliName = positional[0] || null;

// ─── Interactive Prompts ────────────────────────────────────────────────

async function prompt() {
	const isTTY = process.stdin.isTTY;

	if (!isTTY) {
		return { name: cliName || "my-silk-app", withZig: zigFlag };
	}

	const rl = createInterface({ input: process.stdin, output: process.stdout });

	const defaultName = cliName || "my-silk-app";
	const nameInput = await rl.question(`Project name (${defaultName}): `);
	const name = nameInput.trim() || defaultName;

	let withZig = zigFlag;
	if (!zigFlag) {
		const zigInput = await rl.question("Include Zig backend? (y/N): ");
		withZig = zigInput.trim().toLowerCase() === "y";
	}

	rl.close();
	return { name, withZig };
}

// ─── Validation ─────────────────────────────────────────────────────────

function validateName(name) {
	if (!/^[a-z][a-z0-9-]*$/.test(name)) {
		console.error(`Error: Invalid project name "${name}". Use lowercase letters, numbers, and hyphens (e.g. "my-app").`);
		process.exit(1);
	}
}

function toTitleCase(str) {
	return str
		.split("-")
		.map((w) => w.charAt(0).toUpperCase() + w.slice(1))
		.join(" ");
}

// ─── Scaffolding ────────────────────────────────────────────────────────

async function scaffold(name, withZig) {
	const title = toTitleCase(name);
	const dir = join(process.cwd(), name);

	try {
		await access(dir);
		console.error(`Error: directory '${name}' already exists.`);
		process.exit(1);
	} catch {
		// Directory doesn't exist — good
	}

	console.log(`\nCreating Silk project: ${name}\n`);

	await mkdir(join(dir, "src"), { recursive: true });

	await writeFile(join(dir, "silk.config.json"), silkConfig(name, title));
	await writeFile(join(dir, "package.json"), packageJson(name));
	await writeFile(join(dir, "tsconfig.json"), tsconfig);
	await writeFile(join(dir, "vite.config.ts"), viteConfig);
	await writeFile(join(dir, "src", "index.html"), indexHtml(title));
	await writeFile(join(dir, "src", "main.ts"), mainTs);
	await writeFile(join(dir, "src", "style.css"), styleCss);
	await writeFile(join(dir, ".gitignore"), gitignore);

	if (withZig) {
		await mkdir(join(dir, "src-silk"), { recursive: true });
		await writeFile(join(dir, "src-silk", "main.zig"), zigMain);
		console.log("  + src-silk/main.zig (custom Zig commands)");
	}

	console.log(`\nDone! Next steps:\n`);
	console.log(`  cd ${name}`);
	console.log(`  npm install`);
	console.log(`  npx silk dev\n`);
}

// ─── Templates ──────────────────────────────────────────────────────────

function silkConfig(name, title) {
	return (
		JSON.stringify(
			{
				name,
				window: {
					title,
					width: 1024,
					height: 768,
				},
				permissions: {
					fs: true,
					clipboard: true,
					shell: false,
					dialog: true,
					window: true,
				},
				devServer: {
					command: "npm run dev",
					url: "http://localhost:5173",
				},
			},
			null,
			2,
		) + "\n"
	);
}

function packageJson(name) {
	return (
		JSON.stringify(
			{
				name,
				private: true,
				version: "0.1.0",
				type: "module",
				scripts: {
					dev: "vite",
					build: "tsc && vite build",
					preview: "vite preview",
				},
				dependencies: {
					"@silkapp/api": "^0.1.0",
				},
				devDependencies: {
					typescript: "^5.7.0",
					vite: "^6.0.0",
				},
			},
			null,
			2,
		) + "\n"
	);
}

const tsconfig = `{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true
  },
  "include": ["src"]
}
`;

const viteConfig = `import { defineConfig } from "vite";

export default defineConfig({
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: "dist",
  },
});
`;

function indexHtml(title) {
	return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <link rel="stylesheet" href="./style.css">
</head>
<body>
  <div id="app">
    <h1>${title}</h1>
    <p>Edit <code>src/main.ts</code> to get started.</p>
    <button id="ping-btn">Test IPC</button>
    <pre id="output"></pre>
  </div>
  <script type="module" src="./main.ts"></script>
</body>
</html>
`;
}

const mainTs = `import { invoke } from "@silkapp/api";
import "./style.css";

const btn = document.getElementById("ping-btn")!;
const output = document.getElementById("output")!;

btn.addEventListener("click", async () => {
  try {
    const result = await invoke("silk:ping");
    output.textContent = JSON.stringify(result, null, 2);
  } catch (e: any) {
    output.textContent = \`Error: \${e.message}\`;
  }
});
`;

const styleCss = `* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  background: #0f0f1a;
  color: #e0e0e0;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
}

#app {
  text-align: center;
}

h1 {
  font-size: 36px;
  color: #fff;
  margin-bottom: 8px;
}

p {
  color: #888;
  margin-bottom: 24px;
}

code {
  background: #1a1a2e;
  padding: 2px 8px;
  border-radius: 4px;
  font-family: "SF Mono", "Fira Code", monospace;
  color: #7fdbca;
}

button {
  padding: 10px 24px;
  background: #e94560;
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 15px;
  cursor: pointer;
}

button:hover {
  background: #c73650;
}

pre {
  margin-top: 16px;
  padding: 12px 20px;
  background: #1a1a2e;
  border-radius: 8px;
  font-family: "SF Mono", "Fira Code", monospace;
  font-size: 14px;
  color: #7fdbca;
  text-align: left;
  min-height: 40px;
}
`;

const gitignore = `node_modules/
dist/
.DS_Store
*.log
`;

const zigMain = `//! Custom Silk Commands
//!
//! Register your own Zig-powered IPC commands here.
//! These are called from TypeScript via invoke("myapp:command", params).

const std = @import("std");
const silk = @import("silk");

pub fn setup(router: *silk.Router) void {
    router.register("myapp:hello", &hello, null);
}

fn hello(ctx: *silk.Context, params: std.json.Value) !std.json.Value {
    _ = params;
    var obj = std.json.ObjectMap.init(ctx.allocator);
    try obj.put("message", .{ .string = "Hello from Zig!" });
    return .{ .object = obj };
}
`;

// ─── Main ───────────────────────────────────────────────────────────────

const { name, withZig } = await prompt();
validateName(name);
await scaffold(name, withZig);
