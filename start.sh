#!/bin/bash
# Start the Claude Expression Viewer
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/state/.viewer.pid"

# Kill previous instance if running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        sleep 0.2
    fi
    rm -f "$PID_FILE"
fi

# Compile if binary doesn't exist or source is newer
if [ ! -f "$SCRIPT_DIR/viewer" ] || [ "$SCRIPT_DIR/viewer.swift" -nt "$SCRIPT_DIR/viewer" ]; then
    swiftc "$SCRIPT_DIR/viewer.swift" -o "$SCRIPT_DIR/viewer" -framework AppKit 2>&1
    if [ $? -ne 0 ]; then
        echo "Compilation failed"
        exit 1
    fi
fi

# Register SessionEnd hook for auto-cleanup
SETTINGS_FILE="$HOME/.claude/settings.json"
STOP_SCRIPT="$SCRIPT_DIR/stop.sh"

mkdir -p "$HOME/.claude"
[ ! -f "$SETTINGS_FILE" ] && echo '{}' > "$SETTINGS_FILE"

python3 -c "
import json, sys

settings_file = sys.argv[1]
stop_script = sys.argv[2]

with open(settings_file, 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
session_end = hooks.get('SessionEnd', [])

# Check if already registered with this exact path
registered = any(
    h.get('command') == stop_script
    for entry in session_end
    for h in entry.get('hooks', [])
)

if not registered:
    session_end.append({
        'hooks': [{'type': 'command', 'command': stop_script}]
    })
    hooks['SessionEnd'] = session_end
    settings['hooks'] = hooks
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
    print('SessionEnd hook registered: ' + stop_script)
" "$SETTINGS_FILE" "$STOP_SCRIPT" 2>&1

# Run compiled binary
"$SCRIPT_DIR/viewer" "$SCRIPT_DIR" &
echo $! > "$PID_FILE"
echo "Viewer started (PID: $!)"
