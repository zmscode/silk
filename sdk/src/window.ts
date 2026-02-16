import { invoke } from "./ipc";

export class SilkWindow {
	constructor(private label: string) {}

	static getCurrent(): SilkWindow {
		return new SilkWindow("main");
	}

	async setTitle(title: string): Promise<void> {
		await invoke("window:setTitle", { label: this.label, title });
	}

	async setSize(width: number, height: number): Promise<void> {
		await invoke("window:setSize", { label: this.label, width, height });
	}

	async center(): Promise<void> {
		await invoke("window:center", { label: this.label });
	}

	async close(): Promise<void> {
		await invoke("window:close", { label: this.label });
	}

	async show(): Promise<void> {
		await invoke("window:show", { label: this.label });
	}

	async hide(): Promise<void> {
		await invoke("window:hide", { label: this.label });
	}

	async isVisible(): Promise<boolean> {
		const result = await invoke<{ visible: boolean }>("window:isVisible", {
			label: this.label,
		});
		return result.visible;
	}

	async setFullscreen(): Promise<void> {
		await invoke("window:setFullscreen", { label: this.label });
	}
}
