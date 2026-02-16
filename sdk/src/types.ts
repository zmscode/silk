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

export function defineConfig(config: SilkConfig): SilkConfig {
	return config;
}
