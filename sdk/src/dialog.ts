import { invoke } from "./ipc";

/** Options for {@link open}. */
export interface OpenDialogOptions {
	/** Dialog window title */
	title?: string;
	/** Allow selecting directories instead of files */
	directory?: boolean;
	/** Allow selecting multiple items */
	multiple?: boolean;
}

/** Options for {@link save}. */
export interface SaveDialogOptions {
	/** Dialog window title */
	title?: string;
	/** Suggested file name */
	defaultName?: string;
}

/** Options for {@link message}. */
export interface MessageDialogOptions {
	/** Dialog window title */
	title?: string;
	/** Message body text */
	message?: string;
	/** Alert style */
	style?: "informational" | "warning" | "critical";
}

/**
 * Show a native open-file dialog.
 *
 * @param options - Dialog configuration
 * @returns Selected file paths, or `null` if cancelled
 *
 * @example
 * ```ts
 * const files = await dialog.open({ title: "Pick a file", multiple: true });
 * if (files) console.log("Selected:", files);
 * ```
 */
export async function open(options?: OpenDialogOptions): Promise<string[] | null> {
	const result = await invoke<{ paths: string[] | null }>("dialog:open", options as Record<string, unknown>);
	return result.paths;
}

/**
 * Show a native save-file dialog.
 *
 * @param options - Dialog configuration
 * @returns The chosen save path, or `null` if cancelled
 *
 * @example
 * ```ts
 * const path = await dialog.save({ defaultName: "report.csv" });
 * if (path) await fs.writeFile(path, csvData);
 * ```
 */
export async function save(options?: SaveDialogOptions): Promise<string | null> {
	const result = await invoke<{ path: string | null }>("dialog:save", options as Record<string, unknown>);
	return result.path;
}

/**
 * Show a native message/alert dialog.
 *
 * @param text - The message body
 * @param options - Title and style overrides
 * @returns `true` if the user clicked OK
 *
 * @example
 * ```ts
 * await dialog.message("Operation complete!", { title: "Success" });
 * ```
 */
export async function message(text: string, options?: Omit<MessageDialogOptions, "message">): Promise<boolean> {
	if (typeof text !== "string") throw new TypeError("message: text must be a string");
	const result = await invoke<{ confirmed: boolean }>("dialog:message", {
		message: text,
		...options,
	});
	return result.confirmed;
}

/**
 * Show a confirmation dialog (convenience wrapper around {@link message}).
 *
 * @param text - The question to ask
 * @param title - Optional dialog title (defaults to "Confirm")
 * @returns `true` if confirmed
 *
 * @example
 * ```ts
 * if (await dialog.confirm("Delete this file?")) { ... }
 * ```
 */
export async function confirm(text: string, title?: string): Promise<boolean> {
	return message(text, { title: title ?? "Confirm", style: "informational" });
}
