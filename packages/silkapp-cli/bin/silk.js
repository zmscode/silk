#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { arch, platform } from "node:os";
import { join } from "node:path";

const require = createRequire(import.meta.url);

const PLATFORMS = {
	"darwin-arm64": "@silkapp/cli-darwin-arm64",
	"darwin-x64": "@silkapp/cli-darwin-x64",
};

const key = `${platform()}-${arch()}`;
const pkg = PLATFORMS[key];

if (!pkg) {
	console.error(`Unsupported platform: ${key}`);
	console.error(`Silk currently supports: ${Object.keys(PLATFORMS).join(", ")}`);
	process.exit(1);
}

let pkgDir;
try {
	pkgDir = join(require.resolve(`${pkg}/package.json`), "..");
} catch {
	console.error(`Platform package ${pkg} is not installed.`);
	console.error("Try running: npm install");
	process.exit(1);
}

// Determine which binary to run.
// "silk dev" and other CLI commands use silk-cli.
// The silk-cli binary handles subcommand dispatch.
const binary = join(pkgDir, "bin", "silk-cli");
const args = process.argv.slice(2);

try {
	execFileSync(binary, args, { stdio: "inherit" });
} catch (err) {
	// execFileSync throws on non-zero exit — just pass through the code
	process.exit(err.status ?? 1);
}
