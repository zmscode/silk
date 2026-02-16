import { invoke } from "./ipc";

export interface StatResult {
	size: number;
	isDir: boolean;
	isFile: boolean;
}

export interface DirEntry {
	name: string;
	isDir: boolean;
}

export async function readFile(path: string): Promise<string> {
	const result = await invoke<{ contents: string }>("fs:read", { path });
	return result.contents;
}

export async function writeFile(path: string, contents: string): Promise<void> {
	await invoke("fs:write", { path, contents });
}

export async function exists(path: string): Promise<boolean> {
	const result = await invoke<{ exists: boolean }>("fs:exists", { path });
	return result.exists;
}

export async function readDir(path: string): Promise<DirEntry[]> {
	const result = await invoke<{ entries: DirEntry[] }>("fs:readDir", { path });
	return result.entries;
}

export async function mkdir(path: string, options?: { recursive?: boolean }): Promise<void> {
	await invoke("fs:mkdir", { path, ...options });
}

export async function remove(path: string, options?: { recursive?: boolean }): Promise<void> {
	await invoke("fs:remove", { path, ...options });
}

export async function stat(path: string): Promise<StatResult> {
	return invoke<StatResult>("fs:stat", { path });
}
