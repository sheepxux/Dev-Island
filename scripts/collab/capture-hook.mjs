#!/usr/bin/env node
// Records what an Agent CLI actually sends to a Hook, without Dev Island.
//
//   node capture-hook.mjs <agent> <Event>   (reads the Hook payload from stdin)
//
// Raw payloads stay in ~/devisland-capture/<agent>/raw/ and must never be
// committed. timeline.jsonl keeps only the payload's shape: field names,
// types, string lengths, allowlisted enum values and an 8-character hash for
// identifiers, so the same session can be recognized without revealing it.
// The command prints nothing and always exits 0, so the CLI keeps its native
// behavior (approval prompts included).

import { createHash } from "node:crypto";
import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const enumKeys = new Set([
  "hook_event_name", "hookEventName", "event", "type", "kind", "status",
  "notification_type", "notificationType", "reason", "behavior", "decision",
  "permission_mode", "permissionMode", "source", "matcher", "phase", "category",
]);

function shape(value, key = "") {
  if (Array.isArray(value)) return value.slice(0, 3).map((item) => shape(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, shape(v, k)]));
  }
  if (typeof value !== "string") return value;
  if (enumKeys.has(key) && value.length <= 64) return value;
  if (/(^|_)id$|Id$|ID$/.test(key)) {
    return `<id ${createHash("sha256").update(value).digest("hex").slice(0, 8)}>`;
  }
  return `<string ${value.length}>`;
}

export function record(agent, event, payload) {
  try {
    const root = join(homedir(), "devisland-capture", agent);
    const at = new Date().toISOString();
    const raw = typeof payload === "string" ? payload : JSON.stringify(payload);
    mkdirSync(join(root, "raw"), { recursive: true });
    writeFileSync(join(root, "raw", `${at.replace(/[:.]/g, "-")}-${event}.json`), raw);
    let parsed;
    try { parsed = typeof payload === "string" ? JSON.parse(payload) : payload; }
    catch { parsed = { unparsable: raw.length }; }
    appendFileSync(join(root, "timeline.jsonl"),
      JSON.stringify({ at, event, bytes: Buffer.byteLength(raw), shape: shape(parsed) }) + "\n");
  } catch {
    // Capturing must never break the Agent's turn.
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [agent = "unknown", event = "unknown"] = process.argv.slice(2);
  let input = "";
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    record(agent, event, input);
    process.exit(0);
  };
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => { input += chunk; });
  process.stdin.on("end", finish);
  process.stdin.on("error", finish);
  setTimeout(finish, 2000).unref?.();
}
