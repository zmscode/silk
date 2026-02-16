#!/usr/bin/env node

import { mkdir, writeFile, access } from "node:fs/promises";
import { join } from "node:path";
import { createInterface } from "node:readline/promises";
import { execSync } from "node:child_process";

// ─── Argument Parsing ───────────────────────────────────────────────────

const args = process.argv.slice(2);
const zigFlag = args.includes("--zig");
const templateFlag =
	args.find((a) => a.startsWith("--template="))?.split("=")[1] || (args.includes("--template") ? args[args.indexOf("--template") + 1] : null);
const positional = args.filter((a) => !a.startsWith("--") && a !== templateFlag);
const cliName = positional[0] || null;

const TEMPLATES = ["vanilla", "react"];

// ─── Package Manager Detection ──────────────────────────────────────────

function detectPackageManager() {
	// Check if invoked via a specific package manager
	const ua = process.env.npm_config_user_agent || "";
	if (ua.startsWith("bun")) return "bun";
	if (ua.startsWith("pnpm")) return "pnpm";
	if (ua.startsWith("yarn")) return "yarn";
	if (ua.startsWith("npm")) return "npm";

	// Fallback: check which are available
	for (const pm of ["bun", "pnpm", "yarn", "npm"]) {
		try {
			execSync(`${pm} --version`, { stdio: "ignore" });
			return pm;
		} catch {
			continue;
		}
	}
	return "npm";
}

function installCmd(pm) {
	return pm === "yarn" ? "yarn" : `${pm} install`;
}

function runCmd(pm, script) {
	if (pm === "npm") return `npx ${script}`;
	if (pm === "yarn") return `yarn ${script}`;
	if (pm === "pnpm") return `pnpm ${script}`;
	if (pm === "bun") return `bun run ${script}`;
	return `npx ${script}`;
}

// ─── Interactive Prompts ────────────────────────────────────────────────

async function prompt() {
	const isTTY = process.stdin.isTTY;

	if (!isTTY) {
		return {
			name: cliName || "my-silk-app",
			template: templateFlag || "vanilla",
			withZig: zigFlag,
		};
	}

	const rl = createInterface({ input: process.stdin, output: process.stdout });

	const defaultName = cliName || "my-silk-app";
	const nameInput = await rl.question(`Project name (${defaultName}): `);
	const name = nameInput.trim() || defaultName;

	let template = templateFlag;
	if (!template) {
		const tmplInput = await rl.question(`Template — ${TEMPLATES.join(", ")} (vanilla): `);
		template = tmplInput.trim().toLowerCase() || "vanilla";
	}

	let withZig = zigFlag;
	if (!zigFlag) {
		const zigInput = await rl.question("Include Zig backend? (y/N): ");
		withZig = zigInput.trim().toLowerCase() === "y";
	}

	rl.close();
	return { name, template, withZig };
}

// ─── Validation ─────────────────────────────────────────────────────────

function validateName(name) {
	if (!/^[a-z][a-z0-9-]*$/.test(name)) {
		console.error(`Error: Invalid project name "${name}". Use lowercase letters, numbers, and hyphens (e.g. "my-app").`);
		process.exit(1);
	}
}

function validateTemplate(template) {
	if (!TEMPLATES.includes(template)) {
		console.error(`Error: Unknown template "${template}". Available: ${TEMPLATES.join(", ")}`);
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

async function scaffold(name, template, withZig) {
	const title = toTitleCase(name);
	const dir = join(process.cwd(), name);
	const pm = detectPackageManager();

	try {
		await access(dir);
		console.error(`Error: directory '${name}' already exists.`);
		process.exit(1);
	} catch {
		// Directory doesn't exist — good
	}

	console.log(`\nCreating Silk project: ${name} (${template})\n`);

	await mkdir(join(dir, "src"), { recursive: true });

	// Shared files
	await writeFile(join(dir, "silk.config.json"), silkConfig(name, title, pm));
	await writeFile(join(dir, ".gitignore"), gitignore);

	if (template === "vanilla") {
		await scaffoldVanilla(dir, name, title);
	} else if (template === "react") {
		await scaffoldReact(dir, name, title);
	}

	if (withZig) {
		await mkdir(join(dir, "src-silk"), { recursive: true });
		await writeFile(join(dir, "src-silk", "main.zig"), zigMain);
		console.log("  + src-silk/main.zig (custom Zig commands)");
	}

	console.log(`\nDone! Next steps:\n`);
	console.log(`  cd ${name}`);
	console.log(`  ${installCmd(pm)}`);
	console.log(`  ${runCmd(pm, "silk dev")}\n`);
}

async function scaffoldVanilla(dir, name, title) {
	await writeFile(join(dir, "package.json"), vanillaPackageJson(name));
	await writeFile(join(dir, "tsconfig.json"), vanillaTsconfig);
	await writeFile(join(dir, "vite.config.ts"), vanillaViteConfig);
	await writeFile(join(dir, "src", "index.html"), vanillaIndexHtml(title));
	await writeFile(join(dir, "src", "main.ts"), vanillaMainTs);
	await writeFile(join(dir, "src", "style.css"), sharedStyleCss);
}

async function scaffoldReact(dir, name, title) {
	await writeFile(join(dir, "package.json"), reactPackageJson(name));
	await writeFile(join(dir, "tsconfig.json"), reactTsconfig);
	await writeFile(join(dir, "vite.config.ts"), reactViteConfig);
	await writeFile(join(dir, "index.html"), reactIndexHtml(title));
	await writeFile(join(dir, "src", "App.tsx"), reactAppTsx(title));
	await writeFile(join(dir, "src", "main.tsx"), reactMainTsx);
	await writeFile(join(dir, "src", "App.css"), sharedStyleCss);
	await writeFile(join(dir, "src", "vite-env.d.ts"), reactViteEnvDts);
}

// ─── Shared Templates ───────────────────────────────────────────────────

function silkConfig(name, title, pm) {
	const devCommand = pm === "bun" ? "bun run dev" : pm === "pnpm" ? "pnpm dev" : "npm run dev";
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
					command: devCommand,
					url: "http://localhost:5173",
				},
			},
			null,
			2,
		) + "\n"
	);
}

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

// ─── Vanilla Templates ──────────────────────────────────────────────────

function vanillaPackageJson(name) {
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
					"@silkapp/api": "^0.2.0",
				},
				devDependencies: {
					"@silkapp/cli": "^0.1.0",
					typescript: "^5.7.0",
					vite: "^6.0.0",
				},
			},
			null,
			2,
		) + "\n"
	);
}

const vanillaTsconfig = `{
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

const vanillaViteConfig = `import { defineConfig } from "vite";

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

function vanillaIndexHtml(title) {
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

const vanillaMainTs = `import { invoke } from "@silkapp/api";
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

// ─── React Templates ────────────────────────────────────────────────────

function reactPackageJson(name) {
	return (
		JSON.stringify(
			{
				name,
				private: true,
				version: "0.1.0",
				type: "module",
				scripts: {
					dev: "vite",
					build: "tsc -b && vite build",
					preview: "vite preview",
				},
				dependencies: {
					"@silkapp/api": "^0.2.0",
					react: "^19.0.0",
					"react-dom": "^19.0.0",
				},
				devDependencies: {
					"@silkapp/cli": "^0.1.0",
					"@types/react": "^19.0.0",
					"@types/react-dom": "^19.0.0",
					"@vitejs/plugin-react": "^4.3.0",
					typescript: "^5.7.0",
					vite: "^6.0.0",
				},
			},
			null,
			2,
		) + "\n"
	);
}

const reactTsconfig = `{
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
    "noEmit": true,
    "jsx": "react-jsx"
  },
  "include": ["src"]
}
`;

const reactViteConfig = `import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: "dist",
  },
});
`;

function reactIndexHtml(title) {
	return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.tsx"></script>
</body>
</html>
`;
}

const reactMainTsx = `import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
`;

function reactAppTsx(title) {
	return `import { useState } from "react";
import { invoke } from "@silkapp/api";
import "./App.css";

export default function App() {
  const [output, setOutput] = useState("");

  async function handlePing() {
    try {
      const result = await invoke("silk:ping");
      setOutput(JSON.stringify(result, null, 2));
    } catch (e: any) {
      setOutput(\`Error: \${e.message}\`);
    }
  }

  return (
    <div id="app">
      <h1>${title}</h1>
      <p>
        Edit <code>src/App.tsx</code> to get started.
      </p>
      <button onClick={handlePing}>Test IPC</button>
      <pre>{output}</pre>
    </div>
  );
}
`;
}

const reactViteEnvDts = `/// <reference types="vite/client" />
`;

// ─── Shared Styles ──────────────────────────────────────────────────────

const sharedStyleCss = `* {
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

// ─── Main ───────────────────────────────────────────────────────────────

const { name, template, withZig } = await prompt();
validateName(name);
validateTemplate(template);
await scaffold(name, template, withZig);
