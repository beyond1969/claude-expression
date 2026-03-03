#!/bin/bash
# Stop the Claude Expression Viewer and clean up state
# Called automatically via SessionEnd hook, or manually.
# When invoked as a hook, JSON is piped to stdin — safely ignored.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/state/.viewer.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        echo "Viewer stopped (PID: $PID)"
    else
        echo "Viewer was not running (stale PID: $PID)"
    fi
    rm -f "$PID_FILE"
else
    echo "No PID file found. Viewer may not be running."
fi

# Clean up state files so next session starts fresh
rm -f "$SCRIPT_DIR"/state/*_expression "$SCRIPT_DIR"/state/*_speech 2>/dev/null
