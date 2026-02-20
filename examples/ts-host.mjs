#!/usr/bin/env node

process.stdin.setEncoding('utf8');
let buf = '';

process.stdin.on('data', (chunk) => {
  buf += chunk;
});

process.stdin.on('end', () => {
  const line = buf.trim();
  if (!line) {
    process.stdout.write(JSON.stringify({ ok: false, error: 'empty request' }));
    return;
  }

  let req;
  try {
    req = JSON.parse(line);
  } catch {
    process.stdout.write(JSON.stringify({ ok: false, error: 'invalid json' }));
    return;
  }

  if (req.kind !== 'invoke') {
    process.stdout.write(JSON.stringify({ ok: false, error: 'unsupported kind' }));
    return;
  }

  // Example handler set for Mode A
  if (req.cmd === 'ts:echo') {
    process.stdout.write(JSON.stringify({ ok: true, result: req.args ?? null }));
    return;
  }

  if (req.cmd === 'ts:time') {
    process.stdout.write(JSON.stringify({ ok: true, result: { now: new Date().toISOString() } }));
    return;
  }

  process.stdout.write(JSON.stringify({ ok: false, error: `unknown command: ${req.cmd}` }));
});
