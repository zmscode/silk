declare global {
	interface Window {
		__silk: {
			invoke(method: string, params?: Record<string, unknown>): Promise<unknown>;
			listen(event: string, callback: (data: unknown) => void): () => void;
		};
	}
}

function getBridge() {
	if (typeof window === "undefined" || !window.__silk) {
		throw new Error("Silk bridge not available. Are you running inside a Silk app?");
	}
	return window.__silk;
}

/**
 * Invoke a Silk IPC command.
 *
 * @param method - The command to invoke (e.g. `"fs:read"`)
 * @param params - Optional key-value parameters for the command
 * @param options - Optional settings like timeout
 * @returns The result from the native side
 *
 * @example
 * ```ts
 * const result = await invoke<{ contents: string }>("fs:read", { path: "/tmp/file.txt" });
 * ```
 */
export async function invoke<T = unknown>(method: string, params?: Record<string, unknown>, options?: { timeout?: number }): Promise<T> {
	if (typeof method !== "string") {
		throw new TypeError("invoke: method must be a string");
	}
	const promise = getBridge().invoke(method, params) as Promise<T>;
	if (options?.timeout != null && options.timeout > 0) {
		return Promise.race([
			promise,
			new Promise<never>((_, reject) => setTimeout(() => reject(new Error(`invoke("${method}") timed out after ${options.timeout}ms`)), options.timeout)),
		]);
	}
	return promise;
}

/**
 * Listen for events from the native side.
 *
 * @param event - The event name to listen for
 * @param callback - Called each time the event fires
 * @returns An unsubscribe function
 *
 * @example
 * ```ts
 * const unlisten = listen<{ count: number }>("counter:updated", (data) => {
 *   console.log("Counter:", data.count);
 * });
 * // Later: unlisten();
 * ```
 */
export function listen<T = unknown>(event: string, callback: (data: T) => void): () => void {
	if (typeof event !== "string") {
		throw new TypeError("listen: event must be a string");
	}
	if (typeof callback !== "function") {
		throw new TypeError("listen: callback must be a function");
	}
	return getBridge().listen(event, callback as (data: unknown) => void);
}
