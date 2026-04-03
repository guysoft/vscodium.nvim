-- nvim-launch/init.lua
-- Main entry point for nvim-launch plugin
--
-- A neovim plugin that provides VSCode-like Run/Debug functionality:
-- - Reads .vscode/launch.json configurations
-- - "Run Without Debugging" sends commands to tmux terminal pane
-- - "Start Debugging" delegates to nvim-dap
-- - Integrates with vim-quickui for a Run menu

local M = {}

local config = require("nvim-launch.config")

--- Setup the plugin
---@param opts table|nil User configuration overrides
function M.setup(opts)
  config.setup(opts)

  local conf = config.get()

  -- Register keymaps
  if conf.keymaps then
    M._setup_keymaps(conf.keys)
  end

  -- Register quickui menu after quickui loads
  if conf.quickui_menu then
    -- Defer to ensure quickui is loaded first
    vim.defer_fn(function()
      require("nvim-launch.quickui").setup_menu()
    end, 200)
  end

  -- Register user commands
  M._setup_commands()
end

--- Setup keybindings
---@param keys table Key definitions
function M._setup_keymaps(keys)
  local map = vim.keymap.set

  -- Run without debugging
  map("n", keys.run, function() M.run() end, { desc = "Run Without Debugging" })
  map("n", keys.run_last, function() M.run_last() end, { desc = "Run Last (no debug)" })

  -- Debug
  map("n", keys.debug, function() M.debug() end, { desc = "Start Debugging" })
  map("n", keys.debug_last, function() M.debug_last() end, { desc = "Debug Last" })
  map("n", keys.stop, function()
    local ok, dap = pcall(require, "dap")
    if ok then dap.terminate() end
  end, { desc = "Stop Debugging" })

  -- Breakpoints
  map("n", keys.toggle_breakpoint, function()
    local ok, dap = pcall(require, "dap")
    if ok then dap.toggle_breakpoint() end
  end, { desc = "Toggle Breakpoint" })

  -- Stepping
  map("n", keys.step_over, function()
    local ok, dap = pcall(require, "dap")
    if ok then dap.step_over() end
  end, { desc = "Step Over" })

  map("n", keys.step_into, function()
    local ok, dap = pcall(require, "dap")
    if ok then dap.step_into() end
  end, { desc = "Step Into" })

  map("n", keys.step_out, function()
    local ok, dap = pcall(require, "dap")
    if ok then dap.step_out() end
  end, { desc = "Step Out" })

  -- UI
  map("n", keys.toggle_ui, function()
    local ok, dapui = pcall(require, "dapui")
    if ok then dapui.toggle() end
  end, { desc = "Toggle Debug UI" })

  -- Open launch.json
  map("n", keys.open_launch_json, function()
    require("nvim-launch.launch_json").open_launch_json()
  end, { desc = "Open launch.json" })
end

--- Setup user commands
function M._setup_commands()
  vim.api.nvim_create_user_command("LaunchRun", function()
    M.run()
  end, { desc = "Pick a launch config and run without debugging" })

  vim.api.nvim_create_user_command("LaunchDebug", function()
    M.debug()
  end, { desc = "Pick a launch config and start debugging" })

  vim.api.nvim_create_user_command("LaunchRunLast", function()
    M.run_last()
  end, { desc = "Re-run last config without debugging" })

  vim.api.nvim_create_user_command("LaunchDebugLast", function()
    M.debug_last()
  end, { desc = "Re-run last debug session" })

  vim.api.nvim_create_user_command("LaunchOpen", function()
    require("nvim-launch.launch_json").open_launch_json()
  end, { desc = "Open or create launch.json" })
end

-- Public API (delegated to picker/runner)

--- Pick a configuration and run without debugging
function M.run()
  require("nvim-launch.picker").pick_and_run()
end

--- Pick a configuration and debug
function M.debug()
  require("nvim-launch.picker").pick_and_debug()
end

--- Re-run last configuration without debugging
function M.run_last()
  require("nvim-launch.runner").run_last()
end

--- Re-run last debug session
function M.debug_last()
  require("nvim-launch.picker").debug_last()
end

--- Set a conditional breakpoint (prompts for condition)
function M.conditional_breakpoint()
  local ok, dap = pcall(require, "dap")
  if ok then
    vim.ui.input({ prompt = "Breakpoint condition: " }, function(condition)
      if condition then
        dap.set_breakpoint(condition)
      end
    end)
  end
end

return M
