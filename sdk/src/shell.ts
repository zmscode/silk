import { invoke } from "./ipc";

export interface ExecResult {
	stdout: string;
	stderr: string;
	exitCode: number;
}

export async function open(target: string): Promise<void> {
	await invoke("shell:open", { target });
}

export async function exec(command: string, args?: string[]): Promise<ExecResult> {
	return invoke<ExecResult>("shell:exec", { command, args });
}
