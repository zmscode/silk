import { invoke } from "./ipc";

/**
 * Read the current clipboard text.
 *
 * @returns The clipboard text, or `null` if empty
 *
 * @example
 * ```ts
 * const text = await clipboard.readText();
 * if (text) console.log("Clipboard:", text);
 * ```
 */
export async function readText(): Promise<string | null> {
	const result = await invoke<{ text: string | null }>("clipboard:readText");
	return result.text;
}

/**
 * Write text to the clipboard.
 *
 * @param text - The string to copy
 *
 * @example
 * ```ts
 * await clipboard.writeText("Hello from Silk!");
 * ```
 */
export async function writeText(text: string): Promise<void> {
	if (typeof text !== "string") throw new TypeError("writeText: text must be a string");
	await invoke("clipboard:writeText", { text });
}
