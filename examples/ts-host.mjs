#!/usr/bin/env node

import { createInterface } from 'node:readline';

const rl = createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

for await (const line of rl) {
  const trimmed = line.trim();
  if (!trimmed) {
    process.stdout.write(`${JSON.stringify({ ok: false, error: 'empty request' })}\n`);
    continue;
  }

  let req;
  try {
    req = JSON.parse(trimmed);
  } catch {
    process.stdout.write(`${JSON.stringify({ ok: false, error: 'invalid json' })}\n`);
    continue;
  }

  if (req.kind !== 'invoke') {
    process.stdout.write(`${JSON.stringify({ ok: false, error: 'unsupported kind' })}\n`);
    continue;
  }

  if (req.cmd === 'ts:echo') {
    process.stdout.write(`${JSON.stringify({ ok: true, result: req.args ?? null })}\n`);
    continue;
  }

  if (req.cmd === 'ts:time') {
    process.stdout.write(`${JSON.stringify({ ok: true, result: { now: new Date().toISOString() } })}\n`);
    continue;
  }

  process.stdout.write(`${JSON.stringify({ ok: false, error: `unknown command: ${req.cmd}` })}\n`);
}
