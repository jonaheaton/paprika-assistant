#!/bin/bash
# Scheduled Pantry Cleanup Script
# Runs Claude Code in non-interactive mode to clean up expired pantry items.
# Called by launchd every Wednesday at 3 AM.

set -euo pipefail

export PATH="/Users/jonaheaton/.local/bin:$PATH"

PROJECT_DIR="/Users/jonaheaton/Documents/paprika-assistant"
LOG_DIR="$PROJECT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JSON_LOG="$LOG_DIR/pantry-cleanup-$TIMESTAMP.json"
TEXT_LOG="$LOG_DIR/pantry-cleanup-$TIMESTAMP.log"
SUMMARY_LOG="$LOG_DIR/cleanup-history.log"
CLAUDE_BIN="${CLAUDE_BIN:-/Users/jonaheaton/.local/bin/claude}"

mkdir -p "$LOG_DIR"

{
    echo "========================================"
    echo "PANTRY CLEANUP - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo ""
} | tee "$TEXT_LOG"

notify_failure() {
  local reason="$1"
  echo "ERROR: $reason" | tee -a "$TEXT_LOG"
  local last_lines
  last_lines=$(tail -20 "$TEXT_LOG" 2>/dev/null | tr "'" '"' || echo "No log available")
  "$CLAUDE_BIN" -p "Create a Things 3 task titled 'Pantry Cleanup Failed ($TIMESTAMP)' with notes: '$reason

Last log lines:
$last_lines

Full log: $TEXT_LOG'" \
    --allowedTools "mcp__claude_ai_Things3__things_create_task" \
    --max-turns 3 \
    >> "$TEXT_LOG" 2>&1 || true
}

cd "$PROJECT_DIR"

"$CLAUDE_BIN" -p "Run the autonomous pantry cleanup. Use the pantry-cleanup-autonomous agent to delete all duplicate and expired items. Execute the full workflow and provide a complete report of all items deleted." \
    --model haiku \
    --allowedTools "mcp__claude_ai_Paprika__pantry" \
    --output-format json \
    --max-turns 20 \
    > "$JSON_LOG" 2>&1 || {
  notify_failure "Pantry cleanup claude call failed. See $JSON_LOG"
  exit 1
}

# Catch silent failures: claude exits 0 but writes empty or non-JSON output
if ! python3 -m json.tool "$JSON_LOG" > /dev/null 2>&1; then
  notify_failure "Pantry cleanup produced empty/invalid JSON — silent crash or Paprika MCP init failure"
  exit 1
fi

# Extract result and append to text log
RESULT=$(python3 -c "import json; d=json.load(open('$JSON_LOG')); print(d.get('result','(no result field)'))" 2>/dev/null || echo "Failed to parse JSON")

{
    echo "CLAUDE OUTPUT:"
    echo "----------------------------------------"
    echo "$RESULT"
    echo "----------------------------------------"
} >> "$TEXT_LOG"

# Append metrics line to running history
{
    echo ""
    echo "[$TIMESTAMP] Completed"
    echo "$RESULT" | grep -E "(removed|deleted|Total|Duplicates|Expired)" | head -10 || echo "  No metrics extracted"
} >> "$SUMMARY_LOG"

{
    echo ""
    echo "========================================"
    echo "COMPLETED: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "JSON log: $JSON_LOG"
    echo "========================================"
} >> "$TEXT_LOG"

# Rotate logs older than 90 days
find "$LOG_DIR" -name "pantry-cleanup-*.json" -mtime +90 -delete 2>/dev/null || true
find "$LOG_DIR" -name "pantry-cleanup-*.log" -mtime +90 -delete 2>/dev/null || true
