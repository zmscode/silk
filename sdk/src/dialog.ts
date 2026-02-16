import { invoke } from "./ipc";

export interface OpenDialogOptions {
	title?: string;
	directory?: boolean;
	multiple?: boolean;
}

export interface SaveDialogOptions {
	title?: string;
	defaultName?: string;
}

export interface MessageDialogOptions {
	title?: string;
	message?: string;
	style?: "informational" | "warning" | "critical";
}

export async function open(options?: OpenDialogOptions): Promise<string[] | null> {
	const result = await invoke<{ paths: string[] | null }>("dialog:open", options as Record<string, unknown>);
	return result.paths;
}

export async function save(options?: SaveDialogOptions): Promise<string | null> {
	const result = await invoke<{ path: string | null }>("dialog:save", options as Record<string, unknown>);
	return result.path;
}

export async function message(text: string, options?: Omit<MessageDialogOptions, "message">): Promise<boolean> {
	const result = await invoke<{ confirmed: boolean }>("dialog:message", {
		message: text,
		...options,
	});
	return result.confirmed;
}

export async function confirm(text: string, title?: string): Promise<boolean> {
	return message(text, { title: title ?? "Confirm", style: "informational" });
}
