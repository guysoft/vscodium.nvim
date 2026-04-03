# vscodium.nvim

A Neovim plugin that brings VSCode-like Run/Debug functionality to your editor. Reads `.vscode/launch.json` files and provides a unified menu for running and debugging your code.

```
+-------------------------------+
| Run                           |
|-------------------------------|
| Run               Ctrl+F5    |
| Start Debugging      F6      |
|-------------------------------|
| Run Last          Ctrl+F6    |
| Debug Last                    |
|-------------------------------|
| Toggle Breakpoint    F9       |
| Conditional Breakpoint        |
| Clear All Breakpoints         |
|-------------------------------|
| Continue             F5       |
| Step Over                     |
| Step Into            F11      |
| Step Out          Shift+F11   |
| Stop              Shift+F5    |
|-------------------------------|
| Toggle Debug UI               |
| Open launch.json              |
+-------------------------------+
```

## Features

- **Reads `.vscode/launch.json`** with full JSONC support (comments, trailing commas)
- **Run Without Debugging** -- sends commands to a tmux terminal pane (ideal for the [tmux-ide](https://github.com/guysoft/tmux-ide) layout)
- **Start Debugging** -- delegates to [nvim-dap](https://github.com/mfussenegger/nvim-dap) for full DAP debugging
- **VSCode variable resolution** -- `${file}`, `${workspaceFolder}`, `${env:NAME}`, etc.
- **Platform-specific configs** -- respects `linux`, `osx`, `windows` overrides
- **Vim-quickui integration** -- adds a "Run" menu to the menu bar
- **Auto-creates launch.json** -- with sensible defaults for Python and Go

## Requirements

- Neovim >= 0.9
- [nvim-dap](https://github.com/mfussenegger/nvim-dap) (for debugging)
- [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) (optional, for debug panels)
- [tmux](https://github.com/tmux/tmux) (for "Run Without Debugging" to terminal pane)
- [vim-quickui](https://github.com/skywind3000/vim-quickui) (optional, for menu bar integration)

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "guysoft/vscodium.nvim",
  lazy = false,
  dependencies = {
    "mfussenegger/nvim-dap",
    "rcarriga/nvim-dap-ui",
  },
  config = function()
    require("nvim-launch").setup({
      -- tmux pane to send "run without debugging" commands to
      -- In tmux-ide layout: 0=editor, 1=terminal, 2=agent
      tmux_pane = 1,
      tmux_clear = true,
    })
  end,
}
```

### Debug Adapters

Install debug adapters via Mason:

```lua
{
  "jay-babu/mason-nvim-dap.nvim",
  dependencies = { "williamboman/mason.nvim", "mfussenegger/nvim-dap" },
  config = function()
    require("mason-nvim-dap").setup({
      ensure_installed = { "debugpy", "delve" },
    })
  end,
}
```

## Usage

### Run Menu (vim-quickui)

Press `F10` or `<leader>m` to open the menu bar, then select "Run".

### Commands

| Command | Description |
|---------|-------------|
| `:LaunchRun` | Pick a config and run without debugging |
| `:LaunchDebug` | Pick a config and start debugging |
| `:LaunchRunLast` | Re-run last config without debugging |
| `:LaunchDebugLast` | Re-run last debug session |
| `:LaunchOpen` | Open or create `.vscode/launch.json` |

### How "Run Without Debugging" Works

When you select "Run", the plugin:

1. Reads `.vscode/launch.json` from your project
2. Shows a picker with all configurations
3. Builds a shell command from the selected config:
   - Maps the `type` field to a command (e.g., `debugpy` -> `python3`)
   - Resolves VSCode variables (`${file}`, `${workspaceFolder}`, etc.)
   - Applies `args`, `env`, and `cwd` from the config
4. Sends the command to the tmux terminal pane (bottom-left in IDE layout)

### How Debugging Works

When you select "Start Debugging":

1. nvim-dap automatically loads `.vscode/launch.json`
2. Shows a picker with all configurations (from both launch.json and dap.configurations)
3. Starts a full DAP debug session with breakpoints, stepping, variable inspection, etc.
4. nvim-dap-ui auto-opens panels for scopes, watches, stacks, and console

## Configuration

```lua
require("nvim-launch").setup({
  -- Tmux pane index for "run without debugging" output
  tmux_pane = 1,

  -- Clear tmux pane before running
  tmux_clear = true,

  -- Path to launch.json relative to workspace root
  launch_json_path = ".vscode/launch.json",

  -- Type-to-command mapping for "run without debugging"
  type_to_command = {
    debugpy = "python3",
    python = "python3",
    go = "go run",
    node = "node",
    ["pwa-node"] = "node",
  },

  -- Register vim-quickui menu
  quickui_menu = false,  -- Set true if not using quickui_config.vim

  -- Register keybindings
  keymaps = true,

  -- Keymap definitions (only used if keymaps = true)
  keys = {
    run = "<F5>",
    debug = "<F6>",
    run_last = "<C-F5>",
    debug_last = "<C-F6>",
    stop = "<S-F5>",
    toggle_breakpoint = "<F9>",
    step_over = "<leader>do",
    step_into = "<F11>",
    step_out = "<S-F11>",
    toggle_ui = "<leader>du",
    open_launch_json = "<leader>dl",
  },
})
```

## Supported launch.json Features

| Feature | Status |
|---------|--------|
| `configurations` array | Supported |
| `type`, `request`, `name` | Supported |
| `program`, `args`, `cwd`, `env` | Supported |
| `python` (custom interpreter) | Supported |
| JSONC comments (`//`, `/* */`) | Supported |
| Trailing commas | Supported |
| `${file}`, `${workspaceFolder}`, etc. | Supported |
| `${env:NAME}` | Supported |
| `${workspaceFolder:name}` | Supported (falls back to cwd) |
| Platform-specific (`linux`/`osx`/`windows`) | Supported |
| `inputs` (promptString/pickString) | Via nvim-dap |
| `compounds` | Not yet |
| `preLaunchTask` / `postDebugTask` | Not yet (use overseer.nvim) |

## Integration with tmux-ide

This plugin is designed to work with [tmux-ide](https://github.com/guysoft/tmux-ide), which creates a 3-pane IDE layout:

```
+---------------------------+--------------+
|                           |              |
|   nvim (editor)           |   opencode   |
|                           |   (agent)    |
|                           |              |
|---------------------------|              |
|   terminal (pane 1) <--- |              |
|   run output goes here    |              |
+---------------------------+--------------+
```

When you "Run Without Debugging", the command is sent to pane 1 (the terminal), so you can see output without leaving your editor.

## Related

- [tmux-ide](https://github.com/guysoft/tmux-ide) -- 3-pane tmux IDE layout
- [tmux-resurrect-opencode-sessions](https://github.com/guysoft/tmux-resurrect-opencode-sessions) -- Preserve OpenCode sessions across tmux restarts
- [nvim-dap](https://github.com/mfussenegger/nvim-dap) -- Debug Adapter Protocol client
- [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) -- Debug UI panels

## License

[GPL-3.0](LICENSE)
