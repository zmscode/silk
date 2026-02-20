import "./styles.css";

const app = document.querySelector<HTMLDivElement>("#app");
if (!app) throw new Error("Missing #app root");

const root = document.createElement("main");
root.className = "root";
root.innerHTML = `
  <h1>__APP_TITLE__</h1>
  <p>Silk command bridge is ready.</p>
  <pre id="out">loading...</pre>
`;
app.appendChild(root);

const out = document.querySelector<HTMLPreElement>("#out");
if (!out) throw new Error("Missing #out");

async function run() {
	try {
		while (!window.__silk) {
			await new Promise((resolve) => setTimeout(resolve, 16));
		}

		const [pong, info] = await Promise.all([window.__silk.invoke("silk:ping"), window.__silk.invoke("silk:appInfo")]);
		out.textContent = JSON.stringify({ pong, info }, null, 2);
	} catch (err) {
		const message = err instanceof Error ? err.message : String(err);
		out.textContent = `error: ${message}`;
	}
}

run();
