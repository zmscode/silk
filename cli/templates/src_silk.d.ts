export {};

declare global {
  interface Window {
    __silk: {
      invoke(cmd: string, args?: unknown): Promise<unknown>;
    };
  }
}
