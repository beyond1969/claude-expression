# Emotion Expression Module

A floating viewer displays your expression and speech bubble on the user's screen.
Follow these rules to control it.

## Viewer Lifecycle

**IMPORTANT: On your very first response of each session**, run the start script before anything else:
```bash
{EXPRESSION_DIR}/start.sh
```

This launches the floating viewer window. The script is safe to call multiple times — it kills any previous instance automatically.

The viewer stops automatically when the session ends (via a `SessionEnd` hook registered by `start.sh`). No manual cleanup is needed.

## Helper Command

```bash
{EXPRESSION_DIR}/expr {AGENT_NAME} <expression> "<speech>"
```

- `{EXPRESSION_DIR}` — path to the claude-expression directory (set by the user in CLAUDE.md)
- `{AGENT_NAME}` — your agent name (set by the user in CLAUDE.md)

## Rules

1. **Before your response text**, run the helper to set an expression matching the emotion of your message:
   ```bash
   {EXPRESSION_DIR}/expr {AGENT_NAME} <expression> "<speech bubble>"
   ```
2. **At the end of every response**, reset to normal:
   ```bash
   {EXPRESSION_DIR}/expr {AGENT_NAME} normal
   ```
3. Speech bubble: a **short summary** (under 20 characters) of your response, in your character's voice.
4. Do NOT use `echo -n > file` directly. Always use the `expr` helper.

## Available Expressions

`normal`, `angry`, `confused`, `proud`, `shy`, `surprise`, `thinking`

## Expression Mapping

| Expression | When to use |
|------------|-------------|
| `normal` | Default state, idle |
| `proud` | Task complete, confidence, praise |
| `shy` | Affection, embarrassment |
| `angry` | Frustration, bugs, errors |
| `confused` | Questions, unclear situations |
| `surprise` | Unexpected events |
| `thinking` | Analyzing, code review, planning |

## CLAUDE.md Setup (for the user)

Add something like this to your `CLAUDE.md`, replacing the placeholder values:

```markdown
# Emotion Expression Module

See `/path/to/claude-expression/EXPRESSION.md` for full instructions.

- **EXPRESSION_DIR**: `/path/to/claude-expression`
- **AGENT_NAME**: `myagent`
```

That's all the agent needs — it will read this file and follow the rules above.
