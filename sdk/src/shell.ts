import { invoke } from "./ipc";

/** Result from {@link exec}. */
export class ExecResult {
	readonly stdout: string;
	readonly stderr: string;
	readonly exitCode: number;

	constructor(stdout: string, stderr: string, exitCode: number) {
		this.stdout = stdout;
		this.stderr = stderr;
		this.exitCode = exitCode;
	}

	/** `true` if the process exited with code 0. */
	get ok(): boolean {
		return this.exitCode === 0;
	}
}

/**
 * Open a URL or file with the system default application.
 *
 * @param target - URL or file path to open
 *
 * @example
 * ```ts
 * await shell.open("https://example.com");
 * await shell.open("/Users/me/photo.png");
 * ```
 */
export async function open(target: string): Promise<void> {
	if (typeof target !== "string") throw new TypeError("open: target must be a string");
	await invoke("shell:open", { target });
}

/**
 * Execute a command and capture its output.
 *
 * @param command - The executable to run
 * @param args - Optional arguments
 * @returns An {@link ExecResult} with stdout, stderr, and exitCode
 *
 * @example
 * ```ts
 * const result = await shell.exec("ls", ["-la", "/tmp"]);
 * if (result.ok) console.log(result.stdout);
 * ```
 */
export async function exec(command: string, args?: string[]): Promise<ExecResult> {
	if (typeof command !== "string") throw new TypeError("exec: command must be a string");
	const raw = await invoke<{ stdout: string; stderr: string; exitCode: number }>("shell:exec", { command, args });
	return new ExecResult(raw.stdout, raw.stderr, raw.exitCode);
}
