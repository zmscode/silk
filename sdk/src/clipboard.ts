import { invoke } from "./ipc";

export async function readText(): Promise<string | null> {
	const result = await invoke<{ text: string | null }>("clipboard:readText");
	return result.text;
}

export async function writeText(text: string): Promise<void> {
	await invoke("clipboard:writeText", { text });
}
