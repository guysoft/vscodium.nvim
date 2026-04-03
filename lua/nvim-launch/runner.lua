-- nvim-launch/runner.lua
-- "Run Without Debugging" - build shell command from launch config and send to tmux pane

local M = {}

local config = require("nvim-launch.config")
local launch_json = require("nvim-launch.launch_json")

-- Store last run config for "Run Last"
M._last_config = nil

--- Build a shell command from a launch.json configuration
---@param cfg table Resolved launch configuration
---@return string command Shell command to execute
function M.build_command(cfg)
  local conf = config.get()
  local type_map = conf.type_to_command
  local cfg_type = cfg.type or ""

  -- Determine the command prefix based on type
  local cmd_prefix = type_map[cfg_type]

  -- Determine the program/file to run
  local program = cfg.program or ""

  -- Handle custom python interpreter
  if (cfg_type == "debugpy" or cfg_type == "python") and cfg.python then
    cmd_prefix = cfg.python
  end

  -- Build args string
  local args_str = ""
  if cfg.args and type(cfg.args) == "table" then
    local escaped_args = {}
    for _, arg in ipairs(cfg.args) do
      -- Quote args that contain spaces or special characters
      if arg:match("[%s\"'$`\\|&;()<>]") then
        -- Use single quotes, escaping any single quotes in the arg
        arg = "'" .. arg:gsub("'", "'\\''") .. "'"
      end
      table.insert(escaped_args, arg)
    end
    args_str = table.concat(escaped_args, " ")
  end

  -- Build environment prefix
  local env_str = ""
  if cfg.env and type(cfg.env) == "table" then
    local env_parts = {}
    for k, v in pairs(cfg.env) do
      table.insert(env_parts, k .. "=" .. vim.fn.shellescape(v))
    end
    if #env_parts > 0 then
      env_str = table.concat(env_parts, " ") .. " "
    end
  end

  -- Build cwd prefix
  local cwd_str = ""
  if cfg.cwd then
    cwd_str = "cd " .. vim.fn.shellescape(cfg.cwd) .. " && "
  end

  -- Assemble the full command
  local parts = {}
  if cwd_str ~= "" then
    table.insert(parts, cwd_str)
  end
  if env_str ~= "" then
    table.insert(parts, env_str)
  end

  if cmd_prefix and cmd_prefix ~= "" then
    table.insert(parts, cmd_prefix .. " " .. program)
  else
    -- If no prefix mapping, just run the program directly
    table.insert(parts, program)
  end

  if args_str ~= "" then
    table.insert(parts, " " .. args_str)
  end

  return table.concat(parts)
end

--- Check if we're inside a tmux session
---@return boolean
local function in_tmux()
  return os.getenv("TMUX") ~= nil and os.getenv("TMUX") ~= ""
end

--- Send a command to a tmux pane
---@param command string Command to send
---@param pane_index number|nil Pane index (default from config)
function M.send_to_tmux(command, pane_index)
  local conf = config.get()
  pane_index = pane_index or conf.tmux_pane

  if not in_tmux() then
    vim.notify("Not in a tmux session. Cannot send command to pane.", vim.log.levels.ERROR)
    return false
  end

  -- Optionally clear the pane first
  if conf.tmux_clear then
    vim.fn.system({ "tmux", "send-keys", "-t", tostring(pane_index), "C-c", "" })
    vim.fn.system({ "tmux", "send-keys", "-t", tostring(pane_index), "C-l", "" })
    -- Small delay to let clear take effect
    vim.defer_fn(function()
      vim.fn.system({ "tmux", "send-keys", "-t", tostring(pane_index), command, "Enter" })
    end, 50)
  else
    vim.fn.system({ "tmux", "send-keys", "-t", tostring(pane_index), command, "Enter" })
  end

  return true
end

--- Run a launch configuration without debugging
---@param cfg table Raw launch configuration (variables will be resolved)
function M.run(cfg)
  -- Resolve variables
  local resolved = launch_json.resolve_variables_in_table(cfg, cfg)

  -- Store for "run last"
  M._last_config = cfg

  -- Build command
  local command = M.build_command(resolved)

  -- Notify user
  vim.notify("Running: " .. resolved.name, vim.log.levels.INFO)

  -- Send to tmux pane
  if not M.send_to_tmux(command) then
    -- Fallback: run in nvim terminal if not in tmux
    vim.cmd("botright split | terminal " .. command)
  end
end

--- Re-run the last configuration
function M.run_last()
  if M._last_config then
    M.run(M._last_config)
  else
    vim.notify("No previous run configuration", vim.log.levels.WARN)
  end
end

return M
