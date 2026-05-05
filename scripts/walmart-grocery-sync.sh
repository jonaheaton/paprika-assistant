#!/bin/bash
# Walmart Grocery Sync — Orchestrator
# Runs daily at 5 AM via launchd. Detects new Walmart grocery deliveries in Gmail
# and imports items into Paprika pantry.
#
# Architecture:
#   Step 1 (claude -p, RESTRICTED): Gmail detection → walmart-sync-pending.json
#   Step 2 (bash): gate — exit if no new deliveries
#   Step 3 (claude -p, BROADER): Playwright + Paprika import → walmart-sync-history.json
#   Step 4 (bash): cleanup, log rotation

set -euo pipefail

# Ensure claude is in PATH (launchd doesn't inherit shell profile)
export PATH="/Users/jonaheaton/.local/bin:/opt/homebrew/bin:$PATH"

REPO_DIR="${REPO_DIR:-$HOME/Documents/paprika-assistant}"
LOG_DIR="${LOG_DIR:-$REPO_DIR/logs}"
TODAY="${TODAY:-$(date +%Y-%m-%d)}"
PENDING_FILE="$LOG_DIR/walmart-sync-pending.json"
HISTORY_LOG="$LOG_DIR/walmart-sync-history.json"
STEP1_JSON="$LOG_DIR/walmart-sync-$TODAY-step1.json"
STEP2_JSON="$LOG_DIR/walmart-sync-$TODAY-step2.json"
RUN_LOG="$LOG_DIR/walmart-sync-$TODAY.log"
PID_FILE="$LOG_DIR/.walmart-sync.pid"
CLAUDE_BIN="${CLAUDE_BIN:-/Users/jonaheaton/.local/bin/claude}"

# Change to project directory — required for Claude to find .claude/skills/
cd "$REPO_DIR"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$RUN_LOG"; }

notify_failure() {
  local reason="$1"
  log "ERROR: $reason"
  # Capture last 20 log lines for the Things task note (sanitize single quotes)
  local last_lines
  last_lines=$(tail -20 "$RUN_LOG" 2>/dev/null | tr "'" '"' || echo "No log available")
  "$CLAUDE_BIN" -p "Create a Things 3 task titled 'Walmart Grocery Sync Failed ($TODAY)' with notes: '$reason

Last log lines:
$last_lines

Full log: $RUN_LOG'" \
    --allowedTools "mcp__claude_ai_Things3__things_create_task" \
    --max-turns 3 \
    >> "$RUN_LOG" 2>&1 || true
}

# PID file guard — exit silently if another instance is already running.
# Verify the PID actually belongs to this script (guards against recycled PIDs).
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null \
      && ps -p "$OLD_PID" -o args= 2>/dev/null | grep -q "walmart-grocery-sync"; then
    log "Another sync is already running (PID $OLD_PID). Exiting."
    exit 0
  fi
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

# Test mode: verify environment and exit early (used by install-walmart-sync.sh test)
if [ "${WALMART_SYNC_TEST:-}" = "1" ]; then
  log "TEST MODE: environment OK"
  exit 0
fi

log "=== Walmart Grocery Sync starting ==="

# ---------------------------------------------------------------------------
# Step 1: Gmail detection (restricted — Gmail + Read/Write only, no Playwright)
# ---------------------------------------------------------------------------
log "Step 1: Gmail grocery detection..."

gtimeout 300 "$CLAUDE_BIN" -p "Use the gmail-walmart-detector skill." \
    --allowedTools "mcp__claude_ai_Gmail__search_threads,mcp__claude_ai_Gmail__get_thread,Read,Write" \
    --debug-file "$LOG_DIR/walmart-sync-$TODAY-debug.log" \
    --output-format json \
    --max-turns 20 \
    > "$STEP1_JSON" 2>&1 || {
  # Extract result text for the Things task note if available
  local_result=$(python3 -c "import json,sys; d=json.load(open('$STEP1_JSON')); print(d.get('result',''))" 2>/dev/null || echo "")
  # Check for MCP auth errors specifically
  if echo "$local_result" | grep -qi "token.*expired\|re-authoriz\|auth.*error\|MCP.*token"; then
    notify_failure "Gmail MCP token expired — re-authorize via Claude.ai Integrations settings (Settings → Integrations → Gmail)"
  else
    notify_failure "Gmail detection step failed on $TODAY. See step1 JSON: $STEP1_JSON"
  fi
  exit 1
}

# Catch silent failures: claude exits 0 but writes empty or non-JSON output
if ! python3 -m json.tool "$STEP1_JSON" > /dev/null 2>&1; then
  notify_failure "Step 1 produced empty/invalid JSON — silent crash or MCP init failure at boot. Run: ./install-walmart-sync.sh test"
  exit 1
fi

# Append step output to run log
python3 -c "
import json, sys
try:
    d = json.load(open('$STEP1_JSON'))
    print(d.get('result', '(no result field)'))
except Exception as e:
    print(f'(could not parse step1 JSON: {e})')
" >> "$RUN_LOG" 2>&1 || true

# ---------------------------------------------------------------------------
# Step 2: Gate — check if any new deliveries were detected
# ---------------------------------------------------------------------------
if [ ! -f "$PENDING_FILE" ]; then
  log "No pending file written — no new deliveries found. Done."
  exit 0
fi

PENDING_CONTENT=$(cat "$PENDING_FILE" 2>/dev/null || echo "[]")
if [ "$PENDING_CONTENT" = "[]" ] || [ -z "$PENDING_CONTENT" ]; then
  log "No new grocery deliveries found. Done."
  exit 0
fi

DELIVERY_COUNT=$(python3 -c "import json; print(len(json.loads(open('$PENDING_FILE').read())))" 2>/dev/null || echo "?")
log "Found $DELIVERY_COUNT new delivery/deliveries. Starting pantry import..."

# ---------------------------------------------------------------------------
# Step 3: Pantry import (broader — Playwright + Paprika, no Gmail)
# ---------------------------------------------------------------------------
# Note: walmart-to-pantry skill detects headless mode by checking for pending file.
# Enumerate specific Playwright tools; update if wildcard syntax is verified.
gtimeout 1800 "$CLAUDE_BIN" -p "A new Walmart grocery delivery was detected. Read $PENDING_FILE for the delivery details, then use the walmart-to-pantry skill to import the items into Paprika. This is a headless automated run — do not ask for user input at any point. If you cannot proceed without user interaction, output a HEADLESS_ERROR message and exit." \
    --allowedTools "mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_snapshot,mcp__plugin_playwright_playwright__browser_evaluate,mcp__plugin_playwright_playwright__browser_click,mcp__plugin_playwright_playwright__browser_wait_for,mcp__plugin_playwright_playwright__browser_type,mcp__claude_ai_Paprika__pantry,Read,Write" \
    --output-format json \
    --max-turns 60 \
    > "$STEP2_JSON" 2>&1 || {
  local_result=$(python3 -c "import json,sys; d=json.load(open('$STEP2_JSON')); print(d.get('result',''))" 2>/dev/null || echo "")
  # Surface specific headless errors as actionable Things tasks
  if echo "$local_result" | grep -q "HEADLESS_ERROR:"; then
    headless_msg=$(echo "$local_result" | grep "HEADLESS_ERROR:" | head -1)
    notify_failure "$headless_msg"
  elif echo "$local_result" | grep -qi "session.*expired\|sign.*in.*create"; then
    notify_failure "Walmart session expired — re-login required (see CLAUDE.md → Playwright Setup)"
  else
    notify_failure "Pantry import step failed on $TODAY. See step2 JSON: $STEP2_JSON"
  fi
  exit 1
}

# Catch silent failures: claude exits 0 but writes empty or non-JSON output
if ! python3 -m json.tool "$STEP2_JSON" > /dev/null 2>&1; then
  notify_failure "Step 3 produced empty/invalid JSON — silent crash or Playwright/Paprika init failure"
  exit 1
fi

# Append step output to run log
python3 -c "
import json, sys
try:
    d = json.load(open('$STEP2_JSON'))
    print(d.get('result', '(no result field)'))
except Exception as e:
    print(f'(could not parse step2 JSON: {e})')
" >> "$RUN_LOG" 2>&1 || true

# ---------------------------------------------------------------------------
# Step 4: Cleanup
# ---------------------------------------------------------------------------
# Delete pending file — only reached on success
rm -f "$PENDING_FILE"

# Rotate logs older than 30 days
find "$LOG_DIR" -name "walmart-sync-*.log" -mtime +30 -delete 2>/dev/null || true
find "$LOG_DIR" -name "walmart-sync-*-step*.json" -mtime +30 -delete 2>/dev/null || true
find "$LOG_DIR" -name "walmart-sync-*-debug.log" -mtime +30 -delete 2>/dev/null || true

log "=== Walmart grocery sync completed successfully ==="
