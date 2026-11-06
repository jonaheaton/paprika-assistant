#!/bin/bash
# Install/manage the Walmart grocery sync launchd job
# Usage: ./install-walmart-sync.sh [install|uninstall|status|run-now]

set -euo pipefail

PLIST_NAME="com.jonaheaton.walmart-grocery-sync"
PLIST_SOURCE="$(dirname "$0")/$PLIST_NAME.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
SCRIPT="$(dirname "$0")/walmart-grocery-sync.sh"
LOG_DIR="$(dirname "$0")/../logs"

case "${1:-install}" in
    install)
        echo "Installing Walmart grocery sync job..."

        mkdir -p "$HOME/Library/LaunchAgents"
        cp "$PLIST_SOURCE" "$PLIST_DEST"
        echo "  Copied plist to $PLIST_DEST"

        launchctl load "$PLIST_DEST"
        echo "  Loaded launchd job"

        echo ""
        echo "Walmart grocery sync installed."
        echo "  Schedule: Every day at 5:00 AM"
        echo "  Logs: $LOG_DIR/"
        echo ""
        echo "Commands:"
        echo "  ./install-walmart-sync.sh status    - Check job status"
        echo "  ./install-walmart-sync.sh run-now   - Run immediately"
        echo "  ./install-walmart-sync.sh uninstall - Remove scheduled job"
        ;;

    uninstall)
        echo "Uninstalling Walmart grocery sync job..."

        if [ -f "$PLIST_DEST" ]; then
            launchctl unload "$PLIST_DEST" 2>/dev/null || true
            rm "$PLIST_DEST"
            echo "  Removed launchd job"
        else
            echo "  Job not installed"
        fi
        ;;

    status)
        echo "Walmart grocery sync job status:"
        echo ""

        if [ -f "$PLIST_DEST" ]; then
            echo "  Installed: Yes"
            echo "  Plist: $PLIST_DEST"
        else
            echo "  Installed: No"
            exit 0
        fi

        echo ""
        echo "  launchctl list output:"
        launchctl list | grep "$PLIST_NAME" || echo "    (not currently loaded)"

        if [ -d "$LOG_DIR" ]; then
            echo ""
            echo "  Recent run logs:"
            ls -lt "$LOG_DIR"/walmart-sync-*.log 2>/dev/null | head -3 | awk '{print "    " $NF}' || echo "    (none)"

            echo ""
            echo "  History (last 5 entries):"
            HISTORY="$LOG_DIR/walmart-sync-history.json"
            if [ -f "$HISTORY" ]; then
                python3 -c "
import json, sys
history = json.load(open('$HISTORY'))
for entry in history[-5:]:
    print(f\"    {entry.get('completed_at','?')} | {entry.get('delivered_date','?')} | email {entry.get('email_id','?')}\")
" 2>/dev/null || echo "    (could not parse history)"
            else
                echo "    (no history yet)"
            fi
        fi
        ;;

    run-now)
        echo "Running Walmart grocery sync now..."
        echo ""
        bash "$SCRIPT"
        ;;

    test)
        PASS=0; FAIL=0

        check() {
            local name="$1" ok="$2"
            if [ "$ok" = "0" ]; then
                echo "  PASS  $name"; ((PASS++)) || true
            else
                echo "  FAIL  $name (exit $ok)"; ((FAIL++)) || true
            fi
        }

        echo "Walmart sync environment checks..."
        echo ""

        # 1. env -i simulation: verify bash can read the script without terminal FDA
        echo "1. launchd environment simulation (env -i + WALMART_SYNC_TEST)"
        env -i \
            HOME="$HOME" \
            PATH="/Users/jonaheaton/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            WALMART_SYNC_TEST=1 \
            bash "$SCRIPT" > /dev/null 2>&1
        check "script readable in stripped env" $?
        echo ""

        # 2. claude -p reachability: verify the subprocess works outside a terminal
        echo "2. claude -p reachability"
        result=$("/Users/jonaheaton/.local/bin/claude" -p "Reply with the word OK." \
            --output-format json --max-turns 1 2>/dev/null \
            | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('result') else 1)" \
            2>/dev/null); rc=$?
        check "claude -p produces valid JSON output" $rc
        echo ""

        # 3. Stale PID guard: non-existent PID should not block
        echo "3. Stale PID guard (non-existent PID)"
        TMP_LOG=$(mktemp -d)
        echo "99999" > "$TMP_LOG/.walmart-sync.pid"
        WALMART_SYNC_TEST=1 LOG_DIR="$TMP_LOG" bash "$SCRIPT" > /dev/null 2>&1; rc=$?
        if [ $rc -eq 0 ] && ! grep -q "Another sync" "$TMP_LOG"/*.log 2>/dev/null; then
            check "guard bypassed for non-existent PID" 0
        else
            check "guard bypassed for non-existent PID" 1
        fi
        rm -rf "$TMP_LOG"
        echo ""

        echo "Results: $PASS passed, $FAIL failed"
        [ "$FAIL" -eq 0 ] || exit 1
        ;;

    *)
        echo "Usage: $0 [install|uninstall|status|run-now|test]"
        exit 1
        ;;
esac
