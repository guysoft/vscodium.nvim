-- nvim-launch/config.lua
-- Default configuration and user config management

local M = {}

local defaults = {
  -- Tmux pane index to send "run without debugging" commands to
  -- In the IDE layout: 0=editor, 1=bottom-left terminal, 2=right agent
  tmux_pane = 1,

  -- Whether to clear the tmux pane before running
  tmux_clear = true,

  -- Path to launch.json relative to workspace root
  launch_json_path = ".vscode/launch.json",

  -- Type-to-command mapping for "run without debugging"
  -- Maps launch.json "type" field to the command prefix
  type_to_command = {
    debugpy = "python3",
    python = "python3",
    go = "go run",
    node = "node",
    ["pwa-node"] = "node",
    lldb = "",
    codelldb = "",
    cppdbg = "",
  },

  -- Register vim-quickui menu
  quickui_menu = true,

  -- Register keybindings
  keymaps = true,

  -- Keymap definitions
  keys = {
    run = "<F5>",            -- Run without debugging (picks config)
    debug = "<F6>",          -- Start debugging (picks config)
    run_last = "<C-F5>",     -- Run last config without debugging
    debug_last = "<C-F6>",   -- Debug last config
    stop = "<S-F5>",         -- Stop debug session
    toggle_breakpoint = "<F9>",
    step_over = "<leader>do",
    step_into = "<F11>",
    step_out = "<S-F11>",
    toggle_ui = "<leader>du",
    open_launch_json = "<leader>dl",
  },
}

M._config = vim.deepcopy(defaults)

function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.get()
  return M._config
end

return M
