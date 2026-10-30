import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const script = fileURLToPath(new URL('./capture-hook.mjs', import.meta.url));
function run(root, input, args = ['copilot', 'PermissionRequest']) {
  const result = spawnSync(process.execPath, [script, ...args], {
    input, encoding: 'utf8', timeout: 5000,
    env: { ...process.env, DEVISLAND_CAPTURE_ROOT: root },
  });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
}
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'dev-island-capture-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}

test('JSON capture redacts free text, numeric values and stable identifiers', t => {
  const root = fixture(t);
  const input = JSON.stringify({ session_id: 'private-session', reason: 'secret reason',
    source: 'secret source', type: 'secret type', status: 'busy', prompt: 'secret prompt',
    token: 123456789, recoverable: false, nested: [{ tool_input: 'private command' }] });
  run(root, input);
  run(root, input);
  const lines = readFileSync(join(root, 'copilot/timeline.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(lines.length, 2);
  assert.equal(lines[0].bytes, Buffer.byteLength(input));
  assert.equal(lines[0].shape.status, 'busy');
  assert.equal(lines[0].shape.recoverable, false);
  assert.match(lines[0].shape.session_id, /^<id [a-f0-9]{8}>$/);
  assert.equal(lines[0].shape.session_id, lines[1].shape.session_id);
  assert.equal(lines[0].shape.token, '<number>');
  assert.doesNotMatch(JSON.stringify(lines), /secret|private|123456789/);
  const raw = readdirSync(join(root, 'copilot/raw'));
  assert.equal(raw.length, 2);
  assert.equal(readFileSync(join(root, 'copilot/raw', raw[0]), 'utf8'), input);
});

test('invalid JSON and unknown event names do not expose text', t => {
  const root = fixture(t);
  run(root, 'not JSON: private text', ['qwen', '../private-event']);
  const line = JSON.parse(readFileSync(join(root, 'qwen/timeline.jsonl'), 'utf8'));
  assert.doesNotMatch(JSON.stringify(line), /private|not JSON/);
  assert.equal(line.shape.unparsable, '<number>');
});

test('invalid agent and unwritable destination remain silent and exit zero', t => {
  const root = fixture(t);
  run(root, '{}', ['../escape', 'Stop']);
  assert.deepEqual(readdirSync(root), []);
  const file = join(root, 'file');
  writeFileSync(file, 'occupied');
  run(file, '{}');
});

test('dynamic map keys are hidden while known protocol fields remain readable', t => {
  const root = fixture(t);
  const input = JSON.stringify({ metadata: {
    'C:/private/customer-project': { prompt: 'private prose' },
    'private-key-two': { session_id: 'private-session' },
  }, properties: { sessionID: 'private-session' }, type: 'permission.asked' });
  run(root, input, ['opencode', 'permission.asked']);
  const line = JSON.parse(readFileSync(join(root, 'opencode/timeline.jsonl'), 'utf8'));
  assert.equal(line.event, 'permission.asked');
  assert.equal(line.shape.type, 'permission.asked');
  assert.equal(Object.keys(line.shape.metadata).length, 2);
  assert.match(line.shape.properties.sessionID, /^<id [a-f0-9]{8}>$/);
  assert.doesNotMatch(JSON.stringify(line), /private|customer-project/);
});

test('oversized stdin is drained without buffering or retaining the original payload', t => {
  const root = fixture(t);
  run(root, JSON.stringify({ prompt: 'sensitive'.repeat(1024 * 1024) }));
  const line = JSON.parse(readFileSync(join(root, 'copilot/timeline.jsonl'), 'utf8'));
  assert.equal(line.shape.capture_truncated, true);
  const files = readdirSync(join(root, 'copilot/raw'));
  const raw = readFileSync(join(root, 'copilot/raw', files[0]), 'utf8');
  assert.ok(raw.length < 200);
  assert.doesNotMatch(raw, /sensitive/);
  assert.ok(JSON.parse(raw).observed_bytes > 8 * 1024 * 1024);
});

test('ES module import has no side effects; same-millisecond records are unique and do not mutate payload', t => {
  const root = fixture(t);
  const code = `
    const { record } = await import(${JSON.stringify(new URL('./capture-hook.mjs', import.meta.url).href)});
    const { readdirSync } = await import('node:fs');
    if (readdirSync(process.env.DEVISLAND_CAPTURE_ROOT).length) throw Error('import side effect');
    Date.prototype.toISOString = () => '2026-10-28T00:00:00.000Z';
    const payload = { input: { id: 'private-id' }, output: { decision: 'ask' } };
    const before = JSON.stringify(payload);
    for (let i = 0; i < 20; i++) record('opencode', 'permission.ask', payload);
    if (JSON.stringify(payload) !== before) throw Error('mutated payload');
  `;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', code], {
    encoding: 'utf8', timeout: 5000, env: { ...process.env, DEVISLAND_CAPTURE_ROOT: root },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout + result.stderr, '');
  assert.equal(readdirSync(join(root, 'opencode/raw')).length, 20);
});
