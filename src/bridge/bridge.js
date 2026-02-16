// Silk IPC Bridge
// Injected into every webview at document start.
// Provides window.__silk with invoke() and listen() APIs.

(function () {
	"use strict";

	const MAX_PENDING = 1000;
	let nextId = 1;
	const pending = new Map();
	const listeners = new Map();

	/**
	 * Call a Zig-side IPC command and return a Promise.
	 * @param {string} method - The command name (e.g. "fs:read")
	 * @param {object} [params] - Optional parameters
	 * @returns {Promise<any>}
	 */
	function invoke(method, params) {
		return new Promise((resolve, reject) => {
			if (pending.size >= MAX_PENDING) {
				reject(new Error("Too many pending requests"));
				return;
			}
			const id = nextId++;
			pending.set(id, { resolve, reject });

			const msg = JSON.stringify({ id, method, params: params || {} });
			window.webkit.messageHandlers.silk_ipc.postMessage(msg);
		});
	}

	/**
	 * Subscribe to a named event from the Zig backend.
	 * @param {string} event - The event name
	 * @param {function} callback - Called with the event payload
	 * @returns {function} Unsubscribe function
	 */
	function listen(event, callback) {
		if (!listeners.has(event)) {
			listeners.set(event, new Set());
		}
		listeners.get(event).add(callback);

		return function unsubscribe() {
			const cbs = listeners.get(event);
			if (cbs) {
				cbs.delete(callback);
				if (cbs.size === 0) listeners.delete(event);
			}
		};
	}

	// Called by Zig via evaluateJavaScript when a command response arrives.
	window.__silk_dispatch = function (response) {
		if (response == null) return;

		const id = response.id;
		const entry = pending.get(id);
		if (!entry) return;
		pending.delete(id);

		if (response.error) {
			const err = new Error(response.error.message);
			err.code = response.error.code;
			entry.reject(err);
		} else {
			entry.resolve(response.result);
		}
	};

	// Called by Zig via evaluateJavaScript when a backend event fires.
	window.__silk_event = function (data) {
		if (data == null || !data.event) return;

		const cbs = listeners.get(data.event);
		if (cbs) {
			cbs.forEach(function (cb) {
				try {
					cb(data.payload);
				} catch (_) {}
			});
		}
	};

	window.__silk = { invoke, listen };
})();
