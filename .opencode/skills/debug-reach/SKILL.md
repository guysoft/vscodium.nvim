# Skill: debug-reach

Reach a specific line in the debugger. The user tells you a file and line they want to hit,
and you orchestrate nvim-dap (via RPC) to set a breakpoint, launch the program, and confirm
the breakpoint was reached.

## Quick Reference (proven working commands)

```bash
# Discover socket
NVIM_IDE_SOCK=$(tmux show-environment NVIM_IDE_SOCK 2>/dev/null | sed 's/^NVIM_IDE_SOCK=//')

# Ensure debug-rpc module is loaded
RESULT=$(nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('pcall(require, \"nvim-launch.debug-rpc\")')" 2>&1)
if [ "$RESULT" != "true" ]; then
  nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua vim.opt.runtimepath:append("/path/to/vscodium.nvim")<CR>'
fi

# Set breakpoint (opens file, moves cursor, places sign)
nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"nvim-launch.debug-rpc\").set_breakpoint(\"FILE\", LINE)')"

# Start debug session (dap-ui auto-opens)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").run({ type = "debugpy", request = "launch", name = "NAME", program = "FILE", cwd = "DIR" })<CR>'

# Poll state until breakpoint hit
nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"nvim-launch.debug-rpc\").get_state()')"
# Returns: {"stopped": true, "reason": "breakpoint", "line": N, "file": "...", "frames": [...], "session_active": true}

# Verify visually (capture nvim screen)
tmux capture-pane -t 0 -p | grep "^→"   # execution arrow at stopped line
tmux capture-pane -t 0 -p | grep "^B "  # breakpoint sign

# Step / continue / stop
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").step_over()<CR>'
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").step_into()<CR>'
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").continue()<CR>'
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").terminate()<CR>'
```

## Behavior

- When a debug session starts, **dap-ui auto-opens** (scopes, watches, REPL, stack panels).
- When a debug session ends, **dap-ui auto-closes**.
- The `set_breakpoint` function opens the file in nvim, moves the cursor to the line,
  and places the breakpoint with a visible `B` sign in the gutter.
- When stopped, nvim shows a `→` arrow at the current execution line.

## Important: Working Directory

nvim's `cwd` determines how `${workspaceFolder}` resolves in launch.json configs.
Before starting a debug session, ensure nvim's cwd is set to the project root:

```bash
# Check current cwd
nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('vim.fn.getcwd()')"

# Change cwd to project root if needed
nvim --server "$NVIM_IDE_SOCK" --remote-send ':cd /path/to/project<CR>'
```

If the cwd is wrong, launch configs using `${workspaceFolder}` will resolve to the wrong
path and the program won't be found (or breakpoints won't match).

## Key Learnings

- `--remote-expr` with `luaeval()` is for expressions that RETURN values. Cannot do assignments.
- `--remote-send ':lua ...<CR>'` is for statements (assignments, mutations, calling functions with side effects).
- `set_breakpoint` uses `bufadd` + `set_current_buf` (not `:edit`) to avoid E37 errors when
  the current buffer has unsaved changes.
- When dap-ui flickers (opens then closes), it's because a previous terminated event triggered
  the close listener. This is normal and resolves on the next stable session.
- The breakpoint persists across debug sessions. Once set, the user can re-run from the
  quickui "Run" menu → "Start Debugging" or "Debug Last" and hit the same breakpoint.

## Prerequisites

- The tmux-ide layout must be running (or you launch it)
- nvim must have the `nvim-launch` plugin with `debug-rpc` module loaded
- A `.vscode/launch.json` should exist (or you create one)
- For Python: `debugpy` adapter must be installed (mason: `debugpy`)
- For Go: `delve` adapter must be installed (mason: `delve`)

## Configuring nvim from the outside

You can send commands to nvim via RPC. Use `--remote-send` for statements (assignments,
commands) and `--remote-expr` for expressions that return values:

```bash
# Evaluate an expression (returns a value)
nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"nvim-launch.debug-rpc\").get_state()')"

# Execute a statement (assignments, side effects)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").adapters.debugpy = { type = "executable", command = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python", args = { "-m", "debugpy.adapter" } }<CR>'

# Install a mason package
nvim --server "$NVIM_IDE_SOCK" --remote-send ":MasonInstall debugpy<CR>"

# Run Lazy sync to install plugins
nvim --server "$NVIM_IDE_SOCK" --remote-send ":Lazy sync<CR>"

# Close floating windows (Lazy UI, Mason UI)
nvim --server "$NVIM_IDE_SOCK" --remote-send "<Esc>:q<CR>"
```

**Important:** `--remote-expr` with `luaeval()` cannot handle assignment statements.
Use `--remote-send ':lua ...<CR>'` for anything that assigns or mutates state.

### Ensuring debugpy adapter is configured

If the debugpy adapter isn't registered, configure it:
```bash
# Check if adapter exists
RESULT=$(nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"dap\").adapters.debugpy ~= nil')")
if [ "$RESULT" != "true" ]; then
  # Check if debugpy is installed via mason
  if [ ! -d "$HOME/.local/share/nvim/mason/packages/debugpy" ]; then
    nvim --server "$NVIM_IDE_SOCK" --remote-send ":MasonInstall debugpy<CR>"
    # Wait for install (poll for the directory, ~15s)
    for i in $(seq 1 30); do
      [ -d "$HOME/.local/share/nvim/mason/packages/debugpy" ] && break
      sleep 1
    done
    # Close mason UI
    nvim --server "$NVIM_IDE_SOCK" --remote-send "<Esc>:q<CR>"
  fi
  # Register the adapter
  nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").adapters.debugpy = { type = "executable", command = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python", args = { "-m", "debugpy.adapter" } }<CR>'
fi
```

### Ensuring delve adapter is configured (Go)

```bash
RESULT=$(nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"dap\").adapters.delve ~= nil')")
if [ "$RESULT" != "true" ]; then
  if [ ! -d "$HOME/.local/share/nvim/mason/packages/delve" ]; then
    nvim --server "$NVIM_IDE_SOCK" --remote-send ":MasonInstall delve<CR>"
    for i in $(seq 1 30); do
      [ -d "$HOME/.local/share/nvim/mason/packages/delve" ] && break
      sleep 1
    done
    nvim --server "$NVIM_IDE_SOCK" --remote-send "<Esc>:q<CR>"
  fi
  nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").adapters.delve = { type = "server", port = "${port}", executable = { command = vim.fn.stdpath("data") .. "/mason/packages/delve/dlv", args = { "dap", "-l", "127.0.0.1:${port}" } } }<CR>'
fi
```

## Layout Awareness

You are running in pane 2 (right side) of the tmux-ide layout. You can inspect the layout:

```bash
# See all panes and what's running in them
tmux list-panes -F '#{pane_index} #{pane_current_command} #{pane_pid}'
```

Expected layout:
- Pane 0: nvim (editor) - top-left
- Pane 1: terminal (shell) - bottom-left
- Pane 2: opencode (you) - right

If the layout is wrong (e.g., nvim is not in pane 0, or the layout doesn't exist),
you can fix it yourself:
```bash
# Kill existing panes and recreate the IDE layout
~/.tmux/plugins/tmux-ide/scripts/ide.sh --force "$(pwd)"
```

After the layout is created, you'll be in pane 2. nvim is in pane 0 with the RPC socket.

## Step 0: Discover nvim RPC socket

Find the nvim socket for the current tmux IDE session:

```bash
# Get the socket path from tmux environment
NVIM_IDE_SOCK=$(tmux show-environment NVIM_IDE_SOCK 2>/dev/null | sed 's/^NVIM_IDE_SOCK=//')
```

If `NVIM_IDE_SOCK` is set but the socket is dead (connection refused), nvim may have
restarted. The vscodium.nvim plugin auto-heals this on startup (calls `serverstart()`
if `NVIM_IDE_SOCK` env var is set). Try:
1. Send a restart trigger: `nvim --server "$NVIM_IDE_SOCK" ...` — if it times out
2. Use `tmux send-keys -t 0` to tell nvim to start the server:
   ```bash
   tmux send-keys -t 0 Escape Escape
   tmux send-keys -t 0 ":call serverstart('$NVIM_IDE_SOCK')" Enter
   sleep 1
   ```

If `NVIM_IDE_SOCK` is empty or the socket file doesn't exist, nvim is not running in this
tmux window. In that case:

1. Launch the IDE layout:
   ```bash
   # Get current directory
   DIR=$(pwd)
   # Run the IDE layout script
   ~/.tmux/plugins/tmux-ide/scripts/ide.sh --force "$DIR"
   ```
2. Wait for nvim to start (poll for socket, max 10 seconds):
   ```bash
   for i in $(seq 1 20); do
     NVIM_IDE_SOCK=$(tmux show-environment NVIM_IDE_SOCK 2>/dev/null | sed 's/^NVIM_IDE_SOCK=//')
     [ -S "$NVIM_IDE_SOCK" ] && break
     sleep 0.5
   done
   ```
3. If socket still not available after 10s, report failure and stop.

## Step 1: Parse the user's request

Extract:
- **file**: The file path (relative or absolute)
- **line**: The line number to reach
- **condition** (optional): A condition expression for a conditional breakpoint

The user might say things like:
- "reach line 42 in server.py"
- "hit the breakpoint at handlers/auth.py:87"
- "I want to land on line 15 of main.go when x > 5"
- "debug into the process_request function" (you need to find the line)

If the user specifies a function name instead of a line number, use grep/search to find
the function definition line in the file.

## Step 2: Open the file in nvim and set breakpoint

First, ensure the debug-rpc module is loadable. If nvim-launch isn't in the runtime path
(e.g., plugin installed via local dev path), add it:
```bash
# Test if module is available
RESULT=$(nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('pcall(require, \"nvim-launch.debug-rpc\")')" 2>&1)
if [ "$RESULT" != "true" ]; then
  # Add the plugin path (adjust to where vscodium.nvim is cloned)
  nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('vim.opt.runtimepath:append(\"$PLUGIN_PATH\")')"
fi
```

Then open the file and set the breakpoint:

```bash
# Open the file in nvim
nvim --server "$NVIM_IDE_SOCK" --remote-send ":e $FILE<CR>"

# Wait a moment for buffer to load
sleep 0.5

# Set breakpoint at the target line
nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"nvim-launch.debug-rpc\").set_breakpoint(\"$FILE\", $LINE)')"
```

If setting a conditional breakpoint:
```bash
nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"nvim-launch.debug-rpc\").set_breakpoint(\"$FILE\", $LINE, \"$CONDITION\")')"
```

Verify the result is `{"success": true}`.

## Step 3: Ensure launch.json exists with the right config

The debug config should be in `.vscode/launch.json` so the user can re-run from the
"Run" menu in nvim (quickui → Run → Start Debugging).

```bash
# Determine project root (git root or cwd)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LAUNCH_JSON="$PROJECT_ROOT/.vscode/launch.json"
```

**If `launch.json` already exists:**
- Read it and check if a suitable config already exists for the target file.
- If yes, use it.
- If no, **ask the user for permission** before modifying: "I'd like to add a debug
  config to your existing launch.json. OK?" Show them what you'd add.
- NEVER overwrite or reformat an existing launch.json without explicit approval.

**If `launch.json` doesn't exist:**
- Ask the user: "No launch.json found. I'll create one with a debug config for $FILE. OK?"
- On approval, create it.

**For Python:**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Python: <descriptive name>",
      "type": "debugpy",
      "request": "launch",
      "program": "${workspaceFolder}/path/to/script.py",
      "cwd": "${workspaceFolder}",
      "console": "integratedTerminal"
    }
  ]
}
```

**For Go:**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Go: <descriptive name>",
      "type": "go",
      "request": "launch",
      "mode": "debug",
      "program": "${workspaceFolder}/path/to/main.go",
      "cwd": "${workspaceFolder}"
    }
  ]
}
```

**Important:** Use `${workspaceFolder}` relative paths so configs are portable.
Give configs descriptive names (e.g., "Python: test_debug.py" not just "Python: Current File")
so the user can identify them in the Run menu.

**If the user declines** modifying launch.json, you can still run the debug session
directly via `dap.run({...})` without saving to launch.json. The user just won't be
able to re-run from the menu.

After creating/updating launch.json, tell nvim to reload it:
```bash
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap.ext.vscode").load_launchjs(nil, { debugpy = {"python"}, delve = {"go"} })<CR>'
```

## Step 4: Start the debug session

**Preferred: run with explicit config** (avoids the picker prompt):
```bash
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").run({ type = "debugpy", request = "launch", name = "Python: test_debug.py", program = "/absolute/path/to/script.py", cwd = "/project/root" })<CR>'
```

**Alternative: if launch.json is loaded and only has one config:**
```bash
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").run(require("dap").configurations.python[1])<CR>'
```

**`dap.run_last()` works** for re-running after the first `dap.run()` call in the session.
However, avoid it for the FIRST launch — it may show an interactive picker if multiple
configs are registered (from launch.json + manual), which blocks RPC.

**Troubleshooting run_last():**
- If it "terminates immediately", the breakpoint is likely on a wrong/stale line (file was edited)
- Always clear and re-set breakpoints after file edits
- Ensure `dap.session() == nil` before calling (wait 2-3s after terminate)

**Note:** If the picker prompt appears (nvim shows "Type number and <Enter>..."), select with:
```bash
nvim --server "$NVIM_IDE_SOCK" --remote-send "1<CR>"
```

## Step 5: Monitor progress

Poll the debugger state to determine if the breakpoint was hit:

```bash
nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"nvim-launch.debug-rpc\").get_state()')"
```

Returns JSON:
```json
{
  "session_active": true/false,
  "stopped": true/false,
  "file": "/path/to/file.py",
  "line": 42,
  "reason": "breakpoint" | "step" | "exception" | "terminated" | ...,
  "thread_id": 1,
  "frames": [{"name": "func", "file": "/path", "line": 42}, ...]
}
```

**Monitoring strategy (AI decides based on context):**

- Poll every 1-2 seconds.
- **If `stopped == true` and `line == target_line`**: SUCCESS. Report it.
- **If `stopped == true` but at a different line**: The program stopped elsewhere (different
  breakpoint, exception). Decide: continue execution or report the unexpected stop.
- **If `session_active == false`**: The program exited without hitting the breakpoint.
  Analyze why (wrong config? line unreachable in this code path? needs specific input?).
- **If the program needs user input** (e.g., a web server waiting for a request): Tell the
  user what action they need to take, OR if you know what to do (e.g., send a curl request),
  do it yourself from the terminal pane.
- **Timeout decision**: There's no fixed timeout. Use judgment:
  - Fast scripts: if not hit in 10s, likely won't be hit.
  - Servers/long-running: may need to wait for a trigger event. Tell the user.
  - Tests: usually fast, 30s is reasonable.
  - If unsure, ask the user.

## Step 6: Report results

On **SUCCESS**:
```
Breakpoint hit at $FILE:$LINE
Reason: breakpoint
Stack: $FRAMES

To reach this line again:
1. Open the "Run" menu (F10 → Run) in nvim
2. Select "Start Debugging" and pick "$CONFIG_NAME"
   (or use "Debug Last" to re-run the same config)
3. [Any trigger action needed, e.g., "send request to /api/auth"]

The launch config is saved in .vscode/launch.json so you can reuse it anytime.
```

On **FAILURE** (session ended without hitting):
```
The debug session ended without hitting $FILE:$LINE.

Possible reasons:
- The code path doesn't reach this line with the current inputs
- The launch config "$CONFIG_NAME" doesn't exercise this code
- [specific analysis based on what you know about the code]

Suggestions:
- [Specific suggestions based on analysis]
```

## Step 7: Cleanup (optional)

After reporting, leave the debugger in its current state (stopped at breakpoint or terminated).
The user may want to inspect variables, step through, etc.

If the user asks to stop:
```bash
nvim --server "$NVIM_IDE_SOCK" --remote-expr "luaeval('require(\"nvim-launch.debug-rpc\").stop()')"
```

## Additional capabilities

### Determining current state

Poll `get_state()` and interpret the JSON:

| State | Meaning |
|-------|---------|
| `session_active: false` | No debug session running |
| `session_active: true, stopped: false` | Program is running (between breakpoints) |
| `session_active: true, stopped: true, reason: "breakpoint"` | Hit a breakpoint |
| `session_active: true, stopped: true, reason: "exception"` | Unhandled exception (traceback) |
| `session_active: true, stopped: true, reason: "step"` | Stopped after a step command |
| `session_active: true, stopped: true, reason: "pause"` | Manually paused |
| `reason: "terminated"` or `reason: "exited"` | Session ended |

When stopped at an **exception/traceback**, the `frames` array shows the full stack trace.
The top frame is where the exception occurred. You can inspect it, step out, or terminate.

### Starting, stopping, and re-running

```bash
# Start a new debug session (use absolute path or ensure cwd is correct)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").run({ type = "debugpy", request = "launch", name = "NAME", program = "/absolute/path/to/script.py", cwd = "/project/root" })<CR>'

# Start using a config from launch.json (after loading it)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap.ext.vscode").load_launchjs(nil, { debugpy = {"python"} })<CR>'
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").run(require("dap").configurations.python[1])<CR>'

# Stop/terminate current session
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").terminate()<CR>'

# Continue from breakpoint (resume execution)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").continue()<CR>'

# Re-run last debug session (same config)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").run_last()<CR>'
```

### Step through code
If the user asks to step after hitting a breakpoint:
```bash
# Step over (execute current line, stop at next)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").step_over()<CR>'
# Step into (enter function call)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").step_into()<CR>'
# Step out (finish current function, stop at caller)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").step_out()<CR>'
# Continue (run until next breakpoint or end)
nvim --server "$NVIM_IDE_SOCK" --remote-send ':lua require("dap").continue()<CR>'
```

After each step, poll `get_state()` to see where execution stopped.

### Trigger the code path yourself
If you know how to trigger the code path (e.g., run a test, send an HTTP request),
use the terminal pane (pane 1 in tmux-ide layout) to do it:
```bash
tmux send-keys -t 1 "curl http://localhost:8000/api/endpoint" C-m
```

### Multiple breakpoints
You can set multiple breakpoints before starting the session. The first one hit wins.

## Observing the nvim screen

You can capture what's visible in the nvim pane (pane 0) to verify state visually:

```bash
# Capture the full nvim pane content as text
tmux capture-pane -t 0 -p

# Check if breakpoint sign (B) is visible at a line
tmux capture-pane -t 0 -p | grep "^B "

# Check if execution arrow (→) is at the target line
tmux capture-pane -t 0 -p | grep "^→"

# Capture just a range of lines around the target
tmux capture-pane -t 0 -p | grep -A2 -B2 "target_pattern"
```

Use this to verify:
- Breakpoint was set (look for `B` in sign column)
- Debugger stopped at the right line (look for `→` in sign column)
- dap-ui opened (look for split panels, `dap>` prompt)

## Notes

- The nvim RPC socket path uses the tmux session name and window index, so it's unique per IDE window.
- On macOS and Linux, nvim uses Unix sockets. On Windows, it uses named pipes. The `--server` flag handles both transparently.
- If nvim crashes or is restarted, the socket becomes stale. The skill should detect connection failures and re-launch if needed.
