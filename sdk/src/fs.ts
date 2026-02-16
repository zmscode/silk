import { invoke } from "./ipc";

/** Result from {@link stat}. */
export interface StatResult {
	size: number;
	isDir: boolean;
	isFile: boolean;
}

/** A single directory entry from {@link readDir}. */
export interface DirEntry {
	name: string;
	isDir: boolean;
}

/**
 * Read the contents of a file as a UTF-8 string.
 *
 * @param path - Absolute path to the file
 * @returns The file contents
 *
 * @example
 * ```ts
 * const text = await fs.readFile("/tmp/hello.txt");
 * ```
 */
export async function readFile(path: string): Promise<string> {
	if (typeof path !== "string") throw new TypeError("readFile: path must be a string");
	const result = await invoke<{ contents: string }>("fs:read", { path });
	return result.contents;
}

/**
 * Write a string to a file, creating or overwriting it.
 *
 * @param path - Absolute path to the file
 * @param contents - The string to write
 *
 * @example
 * ```ts
 * await fs.writeFile("/tmp/hello.txt", "Hello, world!");
 * ```
 */
export async function writeFile(path: string, contents: string): Promise<void> {
	if (typeof path !== "string") throw new TypeError("writeFile: path must be a string");
	if (typeof contents !== "string") throw new TypeError("writeFile: contents must be a string");
	await invoke("fs:write", { path, contents });
}

/**
 * Check whether a file or directory exists.
 *
 * @param path - Absolute path to check
 * @returns `true` if the path exists
 */
export async function exists(path: string): Promise<boolean> {
	if (typeof path !== "string") throw new TypeError("exists: path must be a string");
	const result = await invoke<{ exists: boolean }>("fs:exists", { path });
	return result.exists;
}

/**
 * List entries in a directory.
 *
 * @param path - Absolute path to the directory
 * @returns Array of directory entries
 *
 * @example
 * ```ts
 * const entries = await fs.readDir("/tmp");
 * entries.forEach(e => console.log(e.name, e.isDir ? "(dir)" : "(file)"));
 * ```
 */
export async function readDir(path: string): Promise<DirEntry[]> {
	if (typeof path !== "string") throw new TypeError("readDir: path must be a string");
	const result = await invoke<{ entries: DirEntry[] }>("fs:readDir", { path });
	return result.entries;
}

/**
 * Create a directory.
 *
 * @param path - Absolute path for the new directory
 * @param options - Set `recursive: true` to create parent directories
 */
export async function mkdir(path: string, options?: { recursive?: boolean }): Promise<void> {
	if (typeof path !== "string") throw new TypeError("mkdir: path must be a string");
	await invoke("fs:mkdir", { path, ...options });
}

/**
 * Remove a file or directory.
 *
 * @param path - Absolute path to remove
 * @param options - Set `recursive: true` to remove directories recursively
 */
export async function remove(path: string, options?: { recursive?: boolean }): Promise<void> {
	if (typeof path !== "string") throw new TypeError("remove: path must be a string");
	await invoke("fs:remove", { path, ...options });
}

/**
 * Get file or directory metadata.
 *
 * @param path - Absolute path to stat
 * @returns Size, isDir, and isFile flags
 */
export async function stat(path: string): Promise<StatResult> {
	if (typeof path !== "string") throw new TypeError("stat: path must be a string");
	return invoke<StatResult>("fs:stat", { path });
}

/**
 * Read a JSON file and parse its contents.
 *
 * @param path - Absolute path to the JSON file
 * @returns The parsed value
 *
 * @example
 * ```ts
 * const config = await fs.readJSON<{ port: number }>("/tmp/config.json");
 * ```
 */
export async function readJSON<T = unknown>(path: string): Promise<T> {
	const text = await readFile(path);
	return JSON.parse(text) as T;
}

/**
 * Stringify a value as JSON and write it to a file.
 *
 * @param path - Absolute path to the file
 * @param data - The value to serialize
 *
 * @example
 * ```ts
 * await fs.writeJSON("/tmp/config.json", { port: 3000 });
 * ```
 */
export async function writeJSON(path: string, data: unknown): Promise<void> {
	await writeFile(path, JSON.stringify(data, null, 2));
}
