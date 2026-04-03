-- nvim-launch/picker.lua
-- Configuration picker using vim.ui.select

local M = {}

local launch_json = require("nvim-launch.launch_json")
local runner = require("nvim-launch.runner")

-- Store last debug config for "Debug Last"
M._last_debug_config = nil
M._last_debug_name = nil

--- Normalize a resolved launch config for nvim-dap.
--- VSCode implicitly sets cwd to the workspace folder and resolves relative
--- program paths against it. debugpy without an explicit cwd falls back to
--- os.path.dirname(program), which breaks when program is a relative path.
--- This function matches VSCode's behavior.
---@param cfg table Resolved launch configuration
---@return table cfg The same table, modified in-place
local function normalize_for_dap(cfg)
  local cwd = vim.fn.getcwd()

  -- If cwd is not set, default to the workspace folder (matches VSCode)
  if not cfg.cwd or cfg.cwd == "" then
    cfg.cwd = cwd
  end

  -- If program is a relative path, make it absolute relative to cwd
  if cfg.program and not vim.startswith(cfg.program, "/") then
    cfg.program = cfg.cwd .. "/" .. cfg.program
  end

  return cfg
end

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

--- Pick a launch configuration and debug it via nvim-dap.
--- Uses our own JSONC parser (handles comments, trailing commas, etc.)
--- and presents all configs in a picker, then calls dap.run() directly.
function M.pick_and_debug()
  local dap_ok, dap = pcall(require, "dap")
  if not dap_ok then
    vim.notify("nvim-dap is not installed", vim.log.levels.ERROR)
    return
  end

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
    prompt = "Debug:",
  }, function(choice, idx)
    if choice and idx then
      local cfg = configs[idx]

      -- Store for "debug last"
      M._last_debug_config = cfg
      M._last_debug_name = cfg.name

      -- Update quickui menu label
      local ok, init = pcall(require, "nvim-launch")
      if ok and init.update_quickui_menu then
        init.update_quickui_menu()
      end

      -- Resolve VSCode-style variables (our parser handles ${workspaceFolder:name} etc.)
      local resolved = launch_json.resolve_variables_in_table(cfg, cfg)

      -- Normalize for nvim-dap (set cwd, make relative program paths absolute)
      normalize_for_dap(resolved)

      vim.notify("Debugging: " .. (resolved.name or choice), vim.log.levels.INFO)

      -- Launch directly via nvim-dap
      dap.run(resolved)
    end
  end)
end

--- Debug the last configuration
function M.debug_last()
  local dap_ok, dap = pcall(require, "dap")
  if not dap_ok then
    vim.notify("nvim-dap is not installed", vim.log.levels.ERROR)
    return
  end

  if not M._last_debug_config then
    vim.notify("No previous debug configuration", vim.log.levels.WARN)
    return
  end

  -- Update quickui menu label
  local ok, init = pcall(require, "nvim-launch")
  if ok and init.update_quickui_menu then
    init.update_quickui_menu()
  end

  -- Resolve and run
  local resolved = launch_json.resolve_variables_in_table(M._last_debug_config, M._last_debug_config)
  normalize_for_dap(resolved)
  vim.notify("Debugging: " .. (resolved.name or "last"), vim.log.levels.INFO)
  dap.run(resolved)
end

return M
