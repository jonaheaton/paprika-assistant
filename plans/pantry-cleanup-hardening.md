# Pantry Cleanup Automation Hardening

## Context

The pantry cleanup runs weekly on Wednesdays at 3 AM via `com.jonaheaton.pantry-cleanup` LaunchAgent.
It uses `claude -p` with the `pantry-cleanup-autonomous` agent to delete expired and duplicate items.

It has been **silently failing since April 23, 2026**, when the local Paprika MCP server was removed
from Claude Code's config in favor of the cloud integration. The tool name used throughout the
cleanup system (`mcp__paprika__pantry`) no longer exists.

Discovered April 30, 2026 while auditing the walmart grocery sync automation.

Affected files:
- `scripts/pantry-cleanup-scheduled.sh` — orchestrator script
- `.claude/agents/pantry-cleanup-autonomous.md` — agent definition
- `scripts/com.jonaheaton.pantry-cleanup.plist` — launchd schedule

## Problem / Goal

Three distinct issues:

**1. Broken tool name (blocking)**
The agent and script both reference `mcp__paprika__pantry` (the old local MCP server, now removed).
The correct tool is `mcp__claude_ai_Paprika__pantry` (the cloud integration via claude.ai connector).
Every run since April 23 has failed with claude exiting non-zero, which `set -e` then silently
propagates — leaving only a 3-line log header.

**2. `WorkingDirectory` in plist (reliability)**
The plist sets `WorkingDirectory` to `~/Documents/paprika-assistant`. On macOS, this causes
`getcwd: cannot access parent directories: Operation not permitted` in some launchd contexts.
The script already does `cd "$PROJECT_DIR"` itself, so the key is redundant.
This is the same bug fixed in `com.jonaheaton.walmart-grocery-sync.plist` on April 26.

**3. No failure alerting (observability)**
When the script fails, nothing happens — no Things 3 task, no notification. The only evidence
is a truncated log file. The walmart sync has `notify_failure` which creates an actionable
Things 3 task with log context. The cleanup needs the same.

## Implementation Steps

### Step 1 — Fix tool name in agent definition

In `.claude/agents/pantry-cleanup-autonomous.md`, change:
```
tools: mcp__paprika__pantry
```
to:
```
tools: mcp__claude_ai_Paprika__pantry
```

Also check `.claude/agents/pantry-cleanup-agent.md` and `.claude/agents/pantry-cleanup.md`
for the same stale tool name.

### Step 2 — Fix tool name in orchestrator script

In `scripts/pantry-cleanup-scheduled.sh`, change:
```bash
--allowedTools "mcp__paprika__pantry" \
```
to:
```bash
--allowedTools "mcp__claude_ai_Paprika__pantry" \
```

### Step 3 — Remove WorkingDirectory from plist

In `scripts/com.jonaheaton.pantry-cleanup.plist`, remove:
```xml
<key>WorkingDirectory</key>
<string>/Users/jonaheaton/Documents/paprika-assistant</string>
```

### Step 4 — Add failure alerting to the script

Refactor `pantry-cleanup-scheduled.sh` to match the walmart sync pattern:
- Replace bare `"$CLAUDE_BIN" -p ...` (killed silently by `set -e`) with `|| { notify_failure; exit 1 }`
- Add JSON output validation after the claude call (catches silent exit-0 failures)
- Add `notify_failure` function that calls `claude -p` to create a Things 3 task
  (use `--allowedTools "mcp__claude_ai_Things3__things_create_task"`)
- Make `CLAUDE_BIN` overridable via env var (enables stub-based testing)

### Step 5 — Reload launchd and verify

```bash
launchctl unload ~/Library/LaunchAgents/com.jonaheaton.pantry-cleanup.plist
cp scripts/com.jonaheaton.pantry-cleanup.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.jonaheaton.pantry-cleanup.plist
```

Verify with a manual run:
```bash
./scripts/install-scheduled-cleanup.sh run-now
```
Confirm the run log has content beyond the 3-line header and the exit code is 0.

### Step 6 — (Optional) Add tests

Consider adding a `test` subcommand to `install-scheduled-cleanup.sh` and a
`tests/test-cleanup-orchestrator.sh` mirroring the walmart sync test suite.
Lower priority than steps 1-5.

## Verification

- Manual `run-now` produces a full log (not just the 3-line header)
- `launchctl list | grep pantry-cleanup` shows exit code 0 after the run
- Intentionally breaking the tool name should produce a Things 3 task in inbox
- Next Wednesday (May 6) 3 AM run should succeed

## References

- `scripts/pantry-cleanup-scheduled.sh` — script to harden
- `.claude/agents/pantry-cleanup-autonomous.md` — agent with stale tool name
- `scripts/com.jonaheaton.walmart-grocery-sync.sh` — reference for notify_failure pattern
- `CLAUDE.md` → Testing & Troubleshooting — known failure modes
- Discovered during: April 30, 2026 audit of walmart grocery sync automation
