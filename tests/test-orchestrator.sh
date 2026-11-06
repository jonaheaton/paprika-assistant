#!/bin/bash
# Offline regression tests for the ARCHIVED walmart-grocery-sync.sh source.
# Run: bash tests/test-orchestrator.sh
# Uses tests/stub-claude.sh as the claude binary to exercise error paths
# without hitting real APIs. Tests run against a temporary log directory.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_DIR/archive/walmart-sync/scripts/walmart-grocery-sync.sh"
STUB="$REPO_DIR/tests/stub-claude.sh"
chmod +x "$STUB"

# Temporary log dir isolated per test run
TEST_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_LOG_DIR"' EXIT

PASS=0
FAIL=0

# ── helpers ──────────────────────────────────────────────────────────────────

run() {
  # Runs the sync script with the stub claude and a temp log dir.
  # STUB_MODE / STUB_MODE_STEP3 are inherited from the calling environment.
  local exit_code=0
  env CLAUDE_BIN="$STUB" \
      TODAY="test" \
      HOME="$HOME" \
      LOG_DIR="$TEST_LOG_DIR" \
      bash "$SCRIPT" >> "$TEST_LOG_DIR/test-output.log" 2>&1 || exit_code=$?
  echo $exit_code
}

assert() {
  local name="$1" ok="$2"
  if [ "$ok" = "1" ]; then
    echo "  PASS  $name"
    ((PASS++)) || true
  else
    echo "  FAIL  $name"
    ((FAIL++)) || true
  fi
}

log_contains() {
  grep -q "$1" "$TEST_LOG_DIR/walmart-sync-test.log" 2>/dev/null
}

setup() {
  # Clean per-test state in the temp dir. Override LOG_DIR via env in run().
  rm -f "$TEST_LOG_DIR"/walmart-sync-test*.{log,json}
  rm -f "$TEST_LOG_DIR/.walmart-sync.pid"
  rm -f "$TEST_LOG_DIR/walmart-sync-pending.json"
}

# ── tests ─────────────────────────────────────────────────────────────────────

echo "Running walmart-grocery-sync orchestrator tests..."
echo ""

# Test 1: Step 1 silent failure (exit 0, empty output) → JSON validation catches it
echo "1. Step 1 silent failure → JSON validation fires"
setup
actual=$(STUB_MODE=step1-empty run)
assert "exits non-zero" "$([ "$actual" != "0" ] && echo 1 || echo 0)"
assert "ERROR in log"   "$(log_contains 'ERROR' && echo 1 || echo 0)"
assert "mentions JSON"  "$(log_contains 'JSON' && echo 1 || echo 0)"
echo ""

# Test 2: Step 1 non-zero exit → generic failure handler fires
echo "2. Step 1 non-zero exit → error handler fires"
setup
actual=$(STUB_MODE=step1-fail run)
assert "exits non-zero" "$([ "$actual" != "0" ] && echo 1 || echo 0)"
assert "ERROR in log"   "$(log_contains 'ERROR' && echo 1 || echo 0)"
echo ""

# Test 3: Step 1 MCP token expired → specific error message
echo "3. Step 1 MCP token expired → specific notify_failure message"
setup
actual=$(STUB_MODE=step1-mcp-expired run)
assert "exits non-zero"       "$([ "$actual" != "0" ] && echo 1 || echo 0)"
assert "token error in log"   "$(log_contains 'token' && echo 1 || echo 0)"
echo ""

# Test 4: No new deliveries (pending file is []) → clean exit 0
echo "4. No new deliveries → clean exit"
setup
echo "[]" > "$TEST_LOG_DIR/walmart-sync-pending.json"
actual=$(STUB_MODE=step1-ok run)
assert "exits 0"               "$([ "$actual" = "0" ] && echo 1 || echo 0)"
assert "no ERROR in log"       "$(log_contains 'ERROR' && echo 0 || echo 1)"
assert "no deliveries message" "$(log_contains 'No new grocery' && echo 1 || echo 0)"
echo ""

# Test 5: Stale PID file with non-existent PID → guard bypassed
echo "5. Stale PID (non-existent process) → guard bypassed, sync proceeds"
setup
echo "[]" > "$TEST_LOG_DIR/walmart-sync-pending.json"
echo "99999" > "$TEST_LOG_DIR/.walmart-sync.pid"
actual=$(STUB_MODE=step1-ok run)
assert "exits 0"           "$([ "$actual" = "0" ] && echo 1 || echo 0)"
assert "not blocked"       "$(log_contains 'Another sync' && echo 0 || echo 1)"
assert "sync ran"          "$(log_contains 'Walmart Grocery Sync starting' && echo 1 || echo 0)"
echo ""

# Test 6: Stale PID file with recycled PID (real process, not the sync) → guard bypassed
echo "6. Stale PID (recycled to unrelated process) → guard bypassed"
setup
echo "[]" > "$TEST_LOG_DIR/walmart-sync-pending.json"
echo $$ > "$TEST_LOG_DIR/.walmart-sync.pid"   # current shell PID — alive but not the sync
actual=$(STUB_MODE=step1-ok run)
assert "exits 0"      "$([ "$actual" = "0" ] && echo 1 || echo 0)"
assert "not blocked"  "$(log_contains 'Another sync' && echo 0 || echo 1)"
assert "sync ran"     "$(log_contains 'Walmart Grocery Sync starting' && echo 1 || echo 0)"
echo ""

# Test 7: Step 3 silent failure → JSON validation catches it
echo "7. Step 3 silent failure → JSON validation fires"
setup
# Write a pending entry so Step 2 gate passes
echo '[{"email_id":"test123","delivered_date":"2026-01-01"}]' \
  > "$TEST_LOG_DIR/walmart-sync-pending.json"
actual=$(STUB_MODE=step1-ok STUB_MODE_STEP3=step3-empty run)
assert "exits non-zero" "$([ "$actual" != "0" ] && echo 1 || echo 0)"
assert "ERROR in log"   "$(log_contains 'ERROR' && echo 1 || echo 0)"
echo ""

# ── summary ───────────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
