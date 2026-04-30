#!/bin/bash
# Fake claude binary for orchestrator tests.
# Routes calls by inspecting the -p prompt argument.
# Step 1 behavior is controlled by STUB_MODE:
#   step1-ok     (default) exit 0, valid JSON — no new deliveries
#   step1-empty            exit 0, no output  — simulates silent crash
#   step1-fail             exit 1, no output  — simulates non-zero exit
#   step1-mcp-expired      exit 1, JSON with "token expired" in result

PROMPT=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-p" && $# -gt 1 ]]; then
    PROMPT="$2"; shift 2
  else
    shift
  fi
done

if echo "$PROMPT" | grep -q "gmail-walmart-detector"; then
  case "${STUB_MODE:-step1-ok}" in
    step1-empty)
      exit 0
      ;;
    step1-fail)
      exit 1
      ;;
    step1-mcp-expired)
      echo '{"type":"result","is_error":true,"result":"Gmail MCP token has expired — re-authorize via Claude.ai Integrations settings","stop_reason":"end_turn"}'
      exit 1
      ;;
    step1-ok|*)
      echo '{"type":"result","is_error":false,"result":"Gmail detection complete.\n  Threads searched: 2\n  DFS matches: 0\n  Already processed: 0\n  New entries written: 0","stop_reason":"end_turn"}'
      ;;
  esac

elif echo "$PROMPT" | grep -q "Things 3 task"; then
  echo '{"type":"result","is_error":false,"result":"Things task created.","stop_reason":"end_turn"}'

elif echo "$PROMPT" | grep -q "walmart-to-pantry"; then
  case "${STUB_MODE_STEP3:-step3-ok}" in
    step3-empty)
      exit 0
      ;;
    step3-fail)
      exit 1
      ;;
    step3-ok|*)
      echo '{"type":"result","is_error":false,"result":"Import complete. 3 items added to Paprika pantry.","stop_reason":"end_turn"}'
      ;;
  esac

else
  echo '{"type":"result","is_error":false,"result":"ok","stop_reason":"end_turn"}'
fi
