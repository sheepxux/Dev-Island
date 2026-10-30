#!/usr/bin/env node
// Records what an Agent CLI actually sends to a Hook, without Dev Island.
//
//   node capture-hook.mjs <agent> <Event>   (reads the Hook payload from stdin)
//
// Raw payloads stay in ~/devisland-capture/<agent>/raw/ and must never be
// committed. timeline.jsonl keeps only the payload's shape: reviewed field names,
// types, string lengths, allowlisted enum values and an 8-character hash for
// identifiers, so the same session can be recognized without revealing it.
// The command prints nothing and always exits 0, so the CLI keeps its native
// behavior (approval prompts included).
// Windows files inherit directory ACLs; mode 0600 is not a Windows ACL guarantee.

import { createHash, randomUUID } from "node:crypto";
import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const enumKeys = new Set([
  "hook_event_name", "hookEventName", "event", "type", "kind", "status",
  "notification_type", "notificationType", "reason", "behavior", "decision",
  "permission_mode", "permissionMode", "source", "matcher", "phase", "category",
]);

// Unknown values are redacted even under an enum-like key (reason/source can
// contain user text). Extend only after reviewing real vendor evidence.
const enumValues = new Set([
  "SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "Notification",
  "UserPromptSubmit", "PermissionRequest", "permissionRequest", "PermissionResult",
  "Stop", "StopFailure", "ErrorOccurred", "TurnStarted", "Interrupt",
  "ToolPermission", "permission_prompt", "idle_prompt",
  "session.created", "session.updated", "session.deleted", "session.status",
  "session.idle", "session.error", "permission.asked", "permission.updated", "permission.replied",
  "permission.ask", "busy", "idle", "retry", "allow", "deny", "ask",
  "approved", "denied", "cancelled", "canceled", "success", "error",
]);

const maxInputBytes = 8 * 1024 * 1024;
const fieldNames = new Set([
  ...enumKeys, "id", "session_id", "sessionId", "sessionID", "projectID",
  "requestID", "messageID", "callID", "partID", "parentID", "tool_use_id",
  "permission_id", "request_id", "turn_id", "agent_id", "tool_call_id",
  "timestamp", "cwd", "transcript_path", "initial_prompt", "prompt",
  "prompt_response", "stop_hook_active", "stop_reason", "hookName",
  "toolName", "tool_name", "toolInput", "tool_input", "permissionSuggestions",
  "input", "output", "properties", "info", "details", "metadata", "error",
  "message", "name", "stack", "error_context", "recoverable", "isRetryable",
  "data", "title", "permission", "permissions", "patterns", "always", "tool",
  "reply", "file_path", "filePath", "filepath", "fileName", "fileDiff", "diff",
  "originalContent", "newContent", "content", "command", "args", "result",
  "attempt", "next", "time", "created", "updated", "completed", "start", "end",
  "version", "directory", "path", "slug", "cost", "tokens", "cache", "read",
  "write", "reasoning", "url", "code", "exit_code", "token", "unparsable",
  "capture_truncated", "observed_bytes", "limit_bytes",
]);

function label(value) {
  return typeof value === "string" && enumValues.has(value)
    ? value : `<string ${String(value).length}>`;
}

function shape(value, key = "", depth = 0) {
  if (depth >= 32) return "<depth limit>";
  if (Array.isArray(value)) return value.slice(0, 3).map((item) => shape(item, "", depth + 1));
  if (value && typeof value === "object") {
    const entries = [];
    for (const k in value) {
      if (!Object.hasOwn(value, k)) continue;
      if (entries.length >= 128) break;
      const known = fieldNames.has(k);
      entries.push([known ? k : `<key ${entries.length} length ${k.length}>`,
        shape(value[k], known ? k : "", depth + 1)]);
    }
    return Object.fromEntries(entries);
  }
  if (typeof value === "number") return "<number>";
  if (typeof value !== "string") return value;
  if (enumKeys.has(key) && enumValues.has(value)) return value;
  if (/(^|_)id$|Id$|ID$/.test(key)) {
    return `<id ${createHash("sha256").update(value).digest("hex").slice(0, 8)}>`;
  }
  return `<string ${value.length}>`;
}

export function record(agent, event, payload) {
  try {
    if (!["gemini", "qwen", "copilot", "kimi", "opencode", "unknown"].includes(agent)) return;
    const root = join(process.env.DEVISLAND_CAPTURE_ROOT || join(homedir(), "devisland-capture"), agent);
    const at = new Date().toISOString();
    const raw = typeof payload === "string" ? payload : JSON.stringify(payload);
    mkdirSync(join(root, "raw"), { recursive: true });
    writeFileSync(join(root, "raw", `${at.replace(/[:.]/g, "-")}-${randomUUID()}.json`), raw, { flag: "wx", mode: 0o600 });
    let parsed;
    try { parsed = typeof payload === "string" ? JSON.parse(payload) : payload; }
    catch { parsed = { unparsable: raw.length }; }
    appendFileSync(join(root, "timeline.jsonl"),
      JSON.stringify({ at, event: label(event), bytes: Buffer.byteLength(raw), shape: shape(parsed) }) + "\n", { mode: 0o600 });
  } catch {
    // Capturing must never break the Agent's turn.
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [agent = "unknown", event = "unknown"] = process.argv.slice(2);
  let input = "";
  let inputBytes = 0;
  let oversized = false;
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    record(agent, event, oversized
      ? { capture_truncated: true, observed_bytes: inputBytes, limit_bytes: maxInputBytes }
      : input);
    process.exit(0);
  };
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => {
    inputBytes += Buffer.byteLength(chunk);
    if (inputBytes > maxInputBytes) { oversized = true; input = ""; }
    else if (!oversized) input += chunk;
  });
  process.stdin.on("end", finish);
  process.stdin.on("error", finish);
  setTimeout(finish, 2000).unref?.();
}
