import { invoke } from "./ipc";

/**
 * Represents a Silk application window.
 *
 * @example
 * ```ts
 * const win = SilkWindow.getCurrent();
 * await win.setTitle("My App");
 * await win.center();
 * ```
 */
export class SilkWindow {
	constructor(private label: string) {}

	/** Get the current (main) window. */
	static getCurrent(): SilkWindow {
		return new SilkWindow("main");
	}

	/**
	 * Set the window title.
	 * @param title - New title text
	 */
	async setTitle(title: string): Promise<void> {
		await invoke("window:setTitle", { label: this.label, title });
	}

	/**
	 * Resize the window.
	 * @param width - Width in pixels
	 * @param height - Height in pixels
	 */
	async setSize(width: number, height: number): Promise<void> {
		await invoke("window:setSize", { label: this.label, width, height });
	}

	/** Center the window on screen. */
	async center(): Promise<void> {
		await invoke("window:center", { label: this.label });
	}

	/** Close the window. */
	async close(): Promise<void> {
		await invoke("window:close", { label: this.label });
	}

	/** Show the window if hidden. */
	async show(): Promise<void> {
		await invoke("window:show", { label: this.label });
	}

	/** Hide the window. */
	async hide(): Promise<void> {
		await invoke("window:hide", { label: this.label });
	}

	/** Check whether the window is currently visible. */
	async isVisible(): Promise<boolean> {
		const result = await invoke<{ visible: boolean }>("window:isVisible", {
			label: this.label,
		});
		return result.visible;
	}

	/** Toggle fullscreen mode. */
	async setFullscreen(): Promise<void> {
		await invoke("window:setFullscreen", { label: this.label });
	}
}
