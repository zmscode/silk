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

export async function invoke<T = unknown>(method: string, params?: Record<string, unknown>): Promise<T> {
	return getBridge().invoke(method, params) as Promise<T>;
}

export function listen<T = unknown>(event: string, callback: (data: T) => void): () => void {
	return getBridge().listen(event, callback as (data: unknown) => void);
}
