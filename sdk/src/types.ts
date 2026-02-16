/** Configuration for a window. */
export interface WindowConfig {
	label?: string;
	title?: string;
	width?: number;
	height?: number;
	resizable?: boolean;
	closable?: boolean;
	minimizable?: boolean;
	fullscreen?: boolean;
	center?: boolean;
}

/** Top-level Silk application configuration (silk.config.json). */
export interface SilkConfig {
	appName: string;
	window?: WindowConfig;
	devServer?: {
		command: string;
		url: string;
	};
	permissions?: Record<string, boolean | { paths?: string[]; commands?: string[] }>;
	csp?: string;
}

/**
 * Type-safe helper for defining silk.config.json.
 *
 * @param config - Your application config
 * @returns The same config (identity function for type checking)
 *
 * @example
 * ```ts
 * export default defineConfig({ appName: "My App" });
 * ```
 */
export function defineConfig(config: SilkConfig): SilkConfig {
	return config;
}
