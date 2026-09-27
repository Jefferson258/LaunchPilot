#!/usr/bin/env node
// One-shot Cursor agent coding step for LaunchPilot.
//
// Reads (env, set by scripts/code.sh):
//   PILOT_REPO_DIR  absolute path to the product repo (the agent's cwd)
//   PILOT_PROMPT    the change request
//   PILOT_JOB_DIR   where to write the transcript + result
//   PILOT_MODEL     model id (default "auto")
//   CURSOR_API_KEY  Cursor API key
//
// Exit codes follow the SDK skill: 1 = startup failure (never ran),
// 2 = run executed but failed, 0 = finished.
import { appendFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const repoDir = process.env.PILOT_REPO_DIR;
const prompt = process.env.PILOT_PROMPT;
const jobDir = process.env.PILOT_JOB_DIR || process.cwd();
const model = process.env.PILOT_MODEL || "auto";
const apiKey = process.env.CURSOR_API_KEY;

if (!repoDir || !prompt) {
  console.error("PILOT_REPO_DIR and PILOT_PROMPT are required");
  process.exit(1);
}
if (!apiKey) {
  console.error("CURSOR_API_KEY is required");
  process.exit(1);
}

const transcriptPath = path.join(jobDir, "transcript.txt");
const log = (s) => {
  process.stdout.write(s);
  appendFileSync(transcriptPath, s);
};

let Agent, CursorAgentError;
try {
  ({ Agent, CursorAgentError } = await import("@cursor/sdk"));
} catch {
  console.error("@cursor/sdk not installed — run: npm install (in agent/)");
  process.exit(1);
}

// Guardrails appended to every coding prompt.
const guarded = [
  prompt,
  "",
  "Constraints:",
  "- Make only the change requested; keep edits minimal and focused.",
  "- Do not commit, push, or run git history-altering commands.",
  "- Do not deploy, upload builds, run destructive SQL, or rotate/change secrets.",
  "- Do not add paid dependencies or take actions that spend money.",
  "- If the request is ambiguous or unsafe, stop and explain instead of guessing.",
].join("\n");

try {
  const result = await Agent.prompt(guarded, {
    apiKey,
    model: { id: model },
    local: { cwd: repoDir },
  });

  log(`\n--- agent result ---\nstatus: ${result.status}\n`);
  if (result.result) log(`${result.result}\n`);

  writeFileSync(
    path.join(jobDir, "result.json"),
    JSON.stringify({ status: result.status, id: result.id ?? null }, null, 2),
  );

  if (result.status === "error") {
    console.error(`run failed: ${result.id ?? "(no id)"}`);
    process.exit(2);
  }
  process.exit(0);
} catch (err) {
  if (CursorAgentError && err instanceof CursorAgentError) {
    console.error(
      `startup failed: ${err.message} (retryable=${err.isRetryable})`,
    );
    process.exit(1);
  }
  throw err;
}
