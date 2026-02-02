#!/bin/bash
# Install/manage the scheduled pantry cleanup launchd job
# Usage: ./install-scheduled-cleanup.sh [install|uninstall|status|run-now]

set -euo pipefail

PLIST_NAME="com.jonaheaton.pantry-cleanup"
PLIST_SOURCE="$(dirname "$0")/$PLIST_NAME.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

case "${1:-install}" in
    install)
        echo "Installing pantry cleanup scheduled job..."

        # Create LaunchAgents directory if needed
        mkdir -p "$HOME/Library/LaunchAgents"

        # Copy plist to LaunchAgents
        cp "$PLIST_SOURCE" "$PLIST_DEST"
        echo "  Copied plist to $PLIST_DEST"

        # Load the job
        launchctl load "$PLIST_DEST"
        echo "  Loaded launchd job"

        echo ""
        echo "Scheduled cleanup installed."
        echo "  Schedule: Every Wednesday at 3:00 AM"
        echo "  Logs: $(dirname "$0")/../logs/"
        echo ""
        echo "Commands:"
        echo "  ./install-scheduled-cleanup.sh status   - Check job status"
        echo "  ./install-scheduled-cleanup.sh run-now  - Run immediately"
        echo "  ./install-scheduled-cleanup.sh uninstall - Remove scheduled job"
        ;;

    uninstall)
        echo "Uninstalling pantry cleanup scheduled job..."

        if [ -f "$PLIST_DEST" ]; then
            launchctl unload "$PLIST_DEST" 2>/dev/null || true
            rm "$PLIST_DEST"
            echo "  Removed launchd job"
        else
            echo "  Job not installed"
        fi
        ;;

    status)
        echo "Pantry cleanup job status:"
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

        # Show recent logs
        LOG_DIR="$(dirname "$0")/../logs"
        if [ -d "$LOG_DIR" ]; then
            echo ""
            echo "  Recent logs:"
            ls -lt "$LOG_DIR"/pantry-cleanup-*.log 2>/dev/null | head -3 | awk '{print "    " $NF}' || echo "    (none)"

            # Show last entry from history
            if [ -f "$LOG_DIR/cleanup-history.log" ]; then
                echo ""
                echo "  Last cleanup:"
                tail -5 "$LOG_DIR/cleanup-history.log" | sed 's/^/    /'
            fi
        fi
        ;;

    run-now)
        echo "Running pantry cleanup now..."
        echo ""
        "$(dirname "$0")/pantry-cleanup-scheduled.sh"
        ;;

    *)
        echo "Usage: $0 [install|uninstall|status|run-now]"
        exit 1
        ;;
esac
