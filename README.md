# Claude Expression Viewer

A self-contained macOS floating window that displays agent expressions and speech bubbles for Claude Code. Agents are auto-detected from the `agents/` directory — no hardcoded names or paths. The viewer starts automatically on session begin and stops on session end.

The agent handles everything automatically — starting/stopping the viewer, changing expressions, and displaying speech bubbles. All you need to do is **initial setup**.

![Example](example.png)

## Requirements

- macOS
- Swift runtime (included with Xcode Command Line Tools)
  ```bash
  xcode-select --install
  ```

## Installation

```bash
git clone https://github.com/beyond1969/claude-expression.git
cd claude-expression
chmod +x expr start.sh stop.sh
```

## Setup

### 1. Add Agent Images

Create a directory under `agents/` with your agent's name and place expression images inside.

```bash
mkdir agents/myagent
```

Expression images should be named `{expression}.png` (240x240 recommended):
```
agents/myagent/normal.png
agents/myagent/angry.png
agents/myagent/thinking.png
...
```

Supported expressions: `normal`, `angry`, `confused`, `proud`, `shy`, `surprise`, `thinking`

If no images are provided, a placeholder with the agent's initial letter is shown.

### 2. Add Integration to CLAUDE.md

Add the following to your project's `CLAUDE.md`, replacing the placeholders:

```markdown
# Emotion Expression Module

See `/path/to/claude-expression/EXPRESSION.md` for full instructions.

- **EXPRESSION_DIR**: `/path/to/claude-expression`
- **AGENT_NAME**: `myagent`
```

The agent will read `EXPRESSION.md` and handle the viewer and expressions automatically.

## Multi-Agent Support

Multiple agents can be displayed simultaneously. Each agent needs:
- A directory in `agents/` (for images)
- An expression state file in `state/` (created automatically by `expr`)

The viewer auto-detects agents from `agents/` and shows/hides them based on whether `state/{name}_expression` exists.

## Directory Structure

```
claude-expression/
├── README.md           # This file (English)
├── README.ko.md        # Korean guide
├── EXPRESSION.md       # Agent-facing expression instructions
├── viewer.swift        # macOS viewer (relative-path based)
├── expr                # Expression/speech helper script
├── start.sh            # Start viewer
├── stop.sh             # Stop viewer
├── state/              # Runtime state files (auto-managed)
└── agents/             # Agent image directories
    └── sample/         # Example agent (placeholder demo)
```

## How It Works

- `start.sh` compiles and runs `viewer.swift`, passing the package directory as an argument. It also registers a `SessionEnd` hook in `~/.claude/settings.json` so the viewer stops automatically when a session ends
- The viewer scans `agents/` for subdirectories to build the agent list
- Every 0.3s, it checks `state/{name}_expression` files to show/hide agents
- Expression images are loaded from `agents/{name}/{expression}.png`
- Speech bubbles are read from `state/{name}_speech`
- The viewer window floats at the top-left corner, preferring portrait monitors

## License

MIT
