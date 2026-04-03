-- nvim-launch/picker.lua
-- Configuration picker using vim.ui.select

local M = {}

local launch_json = require("nvim-launch.launch_json")
local runner = require("nvim-launch.runner")

-- Store last debug config name for menu display
M._last_debug_name = nil

--- Pick a launch configuration and run it (without debugging)
function M.pick_and_run()
  local configs, err = launch_json.get_raw_configurations()
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if #configs == 0 then
    vim.notify("No configurations found in launch.json", vim.log.levels.WARN)
    return
  end

  local names = {}
  for _, cfg in ipairs(configs) do
    table.insert(names, cfg.name or "(unnamed)")
  end

  vim.ui.select(names, {
    prompt = "Run (no debug):",
  }, function(choice, idx)
    if choice and idx then
      runner.run(configs[idx])
    end
  end)
end

--- Pick a launch configuration and debug it
function M.pick_and_debug()
  local dap_ok, dap = pcall(require, "dap")
  if not dap_ok then
    vim.notify("nvim-dap is not installed", vim.log.levels.ERROR)
    return
  end

  -- Register a one-shot listener to capture the config name when session starts
  dap.listeners.after.event_initialized["nvim-launch"] = function(session)
    if session and session.config and session.config.name then
      M._last_debug_name = session.config.name
      -- Update quickui menu to show the debug name
      local ok, init = pcall(require, "nvim-launch")
      if ok and init.update_quickui_menu then
        init.update_quickui_menu()
      end
    end
  end

  -- Let nvim-dap handle everything — it already loads launch.json automatically
  -- DapNew shows a picker of all configs (both dap.configurations and launch.json)
  local has_dap_new = vim.fn.exists(":DapNew") == 2
  if has_dap_new then
    vim.cmd("DapNew")
  else
    -- Fallback for older nvim-dap: use dap.continue() which also shows picker
    dap.continue()
  end
end

--- Debug the last configuration
function M.debug_last()
  local dap_ok, dap = pcall(require, "dap")
  if not dap_ok then
    vim.notify("nvim-dap is not installed", vim.log.levels.ERROR)
    return
  end
  dap.run_last()
end

return M
