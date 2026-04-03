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

--- Get the name of the last run configuration (or nil)
---@return string|nil
function M.last_run_name()
  local cfg = require("nvim-launch.runner")._last_config
  return cfg and cfg.name or nil
end

--- Get the name of the last debug configuration (or nil)
---@return string|nil
function M.last_debug_name()
  local ok, dap = pcall(require, "dap")
  if ok and dap.session() then
    local cfg = dap.session().config
    return cfg and cfg.name or nil
  end
  return nil
end

--- Update the quickui Run menu with current last-run names.
--- Call this after running/debugging to refresh menu labels.
function M.update_quickui_menu()
  -- Only update if quickui is available
  if vim.fn.exists("*quickui#menu#install") ~= 1 then
    return
  end

  local run_label = "R&un Last"
  local run_name = M.last_run_name()
  if run_name then
    run_label = "R&un Last (" .. run_name .. ")"
  end

  local debug_label = "De&bug Last"
  -- For debug, check runner's stored dap config name
  local debug_name = require("nvim-launch.picker")._last_debug_name
  if debug_name then
    debug_label = "De&bug Last (" .. debug_name .. ")"
  end

  -- Pad labels to align (min 35 chars to keep consistent width)
  local function pad(s, width)
    if #s < width then
      return s .. string.rep(" ", width - #s)
    end
    return s
  end

  local menu_items = {
    { pad("&Run", 35), 'lua require("nvim-launch").run()', "Pick a config and run without debugger (in tmux pane)" },
    { pad("Start &Debugging", 35), 'lua require("nvim-launch").debug()', "Pick a config and start debugging" },
    { "--" },
    { pad(run_label, 35), 'lua require("nvim-launch").run_last()', "Re-run last config without debugger" },
    { pad(debug_label, 35), 'lua require("nvim-launch").debug_last()', "Re-run last debug session" },
    { "--" },
    { pad("&Toggle Breakpoint", 35), 'lua require("dap").toggle_breakpoint()', "Toggle breakpoint on current line" },
    { pad("&Conditional Breakpoint", 35), 'lua require("nvim-launch").conditional_breakpoint()', "Set breakpoint with condition" },
    { pad("Clear &All Breakpoints", 35), 'lua require("dap").clear_breakpoints()', "Remove all breakpoints" },
    { "--" },
    { pad("&Continue", 35), 'lua require("dap").continue()', "Resume paused debug session" },
    { pad("Step &Over", 35), 'lua require("dap").step_over()', "Step over current line" },
    { pad("Step &Into", 35), 'lua require("dap").step_into()', "Step into function" },
    { pad("Ste&p Out", 35), 'lua require("dap").step_out()', "Step out of function" },
    { pad("&Stop", 35), 'lua require("dap").terminate()', "Stop debug session" },
    { "--" },
    { pad("Toggle Debug &UI", 35), 'lua require("dapui").toggle()', "Toggle debug UI panels" },
    { pad("Open &launch.json", 35), 'lua require("nvim-launch.launch_json").open_launch_json()', "Open or create .vscode/launch.json" },
  }

  vim.fn["quickui#menu#clear"]("&Run")
  vim.fn["quickui#menu#install"]("&Run", menu_items)
end

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
