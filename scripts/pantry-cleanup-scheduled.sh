#!/bin/bash
# Scheduled Pantry Cleanup Script
# Runs Claude Code in non-interactive mode to clean up expired pantry items
# Intended to be called by launchd every Tuesday at 3 AM

set -euo pipefail

# Ensure claude is in PATH (launchd doesn't inherit shell profile)
export PATH="/Users/jonaheaton/.local/bin:$PATH"

# Configuration
PROJECT_DIR="/Users/jonaheaton/Documents/paprika-assistant"
LOG_DIR="$PROJECT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JSON_LOG="$LOG_DIR/pantry-cleanup-$TIMESTAMP.json"
TEXT_LOG="$LOG_DIR/pantry-cleanup-$TIMESTAMP.log"
SUMMARY_LOG="$LOG_DIR/cleanup-history.log"
CLAUDE_BIN="/Users/jonaheaton/.local/bin/claude"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log start
{
    echo "========================================"
    echo "PANTRY CLEANUP - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo ""
} | tee "$TEXT_LOG"

# Change to project directory (required for Claude to find .claude/ config)
cd "$PROJECT_DIR"

# Run Claude Code in non-interactive mode with minimal permissions
# --model haiku: Use cheaper/faster model for routine automation
# --allowedTools: Only allow the specific MCP tool needed for pantry operations
# -p: Print mode (non-interactive)
# --output-format json: Structured output for logging
# --max-turns: Limit to prevent runaway execution
"$CLAUDE_BIN" -p "Run the autonomous pantry cleanup. Use the pantry-cleanup-autonomous agent to delete all duplicate and expired items. Execute the full workflow and provide a complete report of all items deleted." \
    --model haiku \
    --allowedTools "mcp__paprika__pantry" \
    --output-format json \
    --max-turns 20 \
    > "$JSON_LOG" 2>&1

EXIT_CODE=$?

# Extract the result text from JSON and append to text log
if command -v jq &> /dev/null && [ -f "$JSON_LOG" ]; then
    # Extract result field from JSON
    RESULT=$(jq -r '.result // "No result field found"' "$JSON_LOG" 2>/dev/null || echo "Failed to parse JSON")

    echo "CLAUDE OUTPUT:" >> "$TEXT_LOG"
    echo "----------------------------------------" >> "$TEXT_LOG"
    echo "$RESULT" >> "$TEXT_LOG"
    echo "----------------------------------------" >> "$TEXT_LOG"

    # Extract key metrics for summary log (append to running history)
    {
        echo ""
        echo "[$TIMESTAMP] Exit: $EXIT_CODE"
        # Try to extract deletion counts from the result
        echo "$RESULT" | grep -E "(removed|deleted|Total|Duplicates|Expired)" | head -10 || echo "  No metrics extracted"
    } >> "$SUMMARY_LOG"
else
    # Fallback if jq not available
    echo "RAW OUTPUT (jq not available):" >> "$TEXT_LOG"
    cat "$JSON_LOG" >> "$TEXT_LOG" 2>/dev/null || echo "No output captured" >> "$TEXT_LOG"

    echo "[$TIMESTAMP] Exit: $EXIT_CODE (no jq for parsing)" >> "$SUMMARY_LOG"
fi

# Log completion
{
    echo ""
    echo "========================================"
    echo "COMPLETED: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Exit code: $EXIT_CODE"
    echo "JSON log: $JSON_LOG"
    echo "========================================"
} >> "$TEXT_LOG"

# Cleanup old logs (keep last 90 days)
find "$LOG_DIR" -name "pantry-cleanup-*.json" -mtime +90 -delete 2>/dev/null || true
find "$LOG_DIR" -name "pantry-cleanup-*.log" -mtime +90 -delete 2>/dev/null || true

exit $EXIT_CODE
