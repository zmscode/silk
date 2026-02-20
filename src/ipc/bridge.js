(function () {
  if (window.__silk) return;

  const pending = new Map();
  const listeners = new Map();
  let nextCallback = 1;

  function getTransport() {
    if (window.webkit?.messageHandlers?.silk?.postMessage) {
      return (payload) => window.webkit.messageHandlers.silk.postMessage(payload);
    }

    if (window.chrome?.webview?.postMessage) {
      return (payload) => window.chrome.webview.postMessage(payload);
    }

    if (typeof window.__silkPostMessage === "function") {
      return (payload) => window.__silkPostMessage(payload);
    }

    return null;
  }

  function post(payload) {
    const transport = getTransport();
    if (!transport) {
      throw new Error("Silk transport unavailable");
    }
    transport(JSON.stringify(payload));
  }

  window.__silk = {
    invoke(cmd, args) {
      return new Promise((resolve, reject) => {
        const callback = nextCallback++;
        pending.set(callback, { resolve, reject });

        try {
          post({
            kind: "invoke",
            callback,
            cmd,
            args: args ?? null,
          });
        } catch (err) {
          pending.delete(callback);
          reject(err instanceof Error ? err : new Error(String(err)));
        }
      });
    },

    listen(event, handler) {
      if (!listeners.has(event)) listeners.set(event, new Set());
      listeners.get(event).add(handler);
      return () => listeners.get(event)?.delete(handler);
    },

    __dispatch(msg) {
      if (!msg || typeof msg !== "object") return;

      if (msg.kind === "event") {
        const set = listeners.get(msg.event);
        if (set) set.forEach((handler) => handler(msg.payload));
        return;
      }

      if (msg.kind !== "response") return;

      const p = pending.get(msg.callback);
      if (!p) return;

      pending.delete(msg.callback);
      if (msg.ok) {
        p.resolve(msg.result);
      } else {
        const message = typeof msg.error === "string" ? msg.error : (msg.error?.message ?? "Silk command failed");
        p.reject(new Error(message));
      }
    },
  };
})();
