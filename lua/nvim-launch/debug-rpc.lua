-- nvim-launch/debug-rpc.lua
-- Exposes debugger state and control functions via nvim's RPC API.
-- Designed to be called from external tools (e.g., OpenCode skill) via:
--   nvim --server $SOCK --remote-expr "luaeval('require(\"nvim-launch.debug-rpc\").get_state()')"
--
-- Cross-platform: uses nvim's built-in RPC (Unix sockets on Linux/macOS,
-- named pipes on Windows). No platform-specific code needed.

local M = {}

-- Internal state, updated by DAP event listeners
M._state = {
  session_active = false,
  stopped = false,
  file = "",
  line = 0,
  reason = "",
  thread_id = 0,
  frames = {},      -- top stack frames when stopped
  variables = {},   -- local variables at stop point (top frame)
}

-- Track whether listeners have been registered
M._listeners_registered = false

--- Register DAP event listeners to track debugger state.
--- Called automatically on first use, or can be called explicitly.
function M.register_listeners()
  if M._listeners_registered then
    return
  end

  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end

  -- Session started
  dap.listeners.after.event_initialized["debug-rpc"] = function()
    M._state.session_active = true
    M._state.stopped = false
    M._state.reason = ""
    -- Auto-open dap-ui when debug session starts
    local dapui_ok, dapui = pcall(require, "dapui")
    if dapui_ok then
      dapui.open()
    end
  end

  -- Execution stopped (breakpoint hit, step completed, etc.).
  -- We delay setting M._state.stopped = true until after stackTrace lands,
  -- so callers polling get_state() never observe stopped=true with empty
  -- file/line/frames. (Pre-fix race: event_stopped flipped stopped first
  -- and fired an async stackTrace request; pollers won the race.)
  dap.listeners.after.event_stopped["debug-rpc"] = function(session, body)
    M._state.reason = body and body.reason or "unknown"
    M._state.thread_id = body and body.threadId or 0
    -- Reset frame data; will be repopulated below.
    M._state.frames = {}
    M._state.file = ""
    M._state.line = 0

    if not session then
      -- No session means we can't request stackTrace; surface the stop
      -- anyway so callers don't hang forever.
      M._state.stopped = true
      return
    end

    local thread_id = M._state.thread_id
    if thread_id == 0 and body and body.allThreadsStopped then
      thread_id = 1
    end
    -- Request stack trace, then mark stopped only when we have frames.
    session:request("stackTrace", { threadId = thread_id, startFrame = 0, levels = 5 }, function(err, response)
      if not err and response and response.stackFrames then
        for i, frame in ipairs(response.stackFrames) do
          M._state.frames[i] = {
            name = frame.name,
            file = frame.source and frame.source.path or "",
            line = frame.line,
          }
        end
        if #M._state.frames > 0 then
          M._state.file = M._state.frames[1].file
          M._state.line = M._state.frames[1].line
        end
      end
      -- Always flip stopped last, even on stackTrace error, so pollers
      -- don't hang on adapter glitches.
      M._state.stopped = true
    end)
  end

  -- Session terminated
  dap.listeners.after.event_terminated["debug-rpc"] = function()
    M._state.session_active = false
    M._state.stopped = false
    M._state.reason = "terminated"
    -- Auto-close dap-ui when session ends
    local dapui_ok, dapui = pcall(require, "dapui")
    if dapui_ok then
      dapui.close()
    end
  end

  -- Session exited
  dap.listeners.after.event_exited["debug-rpc"] = function()
    M._state.session_active = false
    M._state.stopped = false
    M._state.reason = "exited"
  end

  -- Continued (resumed from stop)
  dap.listeners.after.event_continued["debug-rpc"] = function()
    M._state.stopped = false
    M._state.reason = ""
  end

  M._listeners_registered = true
end

--- Get current debugger state as a JSON-encoded string.
--- This is the primary function called via RPC to check state.
---@return string JSON representation of the current debug state
function M.get_state()
  M.register_listeners()
  return vim.fn.json_encode(M._state)
end

--- Set a breakpoint at the given file and line.
---@param file string Absolute path to the file
---@param line number Line number (1-based)
---@param condition string|nil Optional condition expression
---@return string JSON result: {success: bool, error: string?}
function M.set_breakpoint(file, line, condition)
  M.register_listeners()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.fn.json_encode({ success = false, error = "nvim-dap not available" })
  end

  -- Normalize msgpack/RPC nils: callers over the Neovim RPC bridge get
  -- vim.NIL for absent args, but dap.set_breakpoint asserts type(cond)
  -- == "string" when non-nil, so vim.NIL crashes it. Translate to lua nil.
  if condition == vim.NIL then condition = nil end

  -- Open the file in a buffer without discarding current buffer changes
  local bufnr = vim.fn.bufadd(file)
  vim.fn.bufload(bufnr)
  -- Switch to that buffer in current window
  vim.api.nvim_set_current_buf(bufnr)
  -- Move cursor to the target line
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  -- Use dap.set_breakpoint which handles signs correctly
  dap.set_breakpoint(condition, nil, nil)

  return vim.fn.json_encode({ success = true })
end

--- Clear all breakpoints in a file (or all files if file is nil).
---@param file string|nil File path, or nil for all files
---@return string JSON result
function M.clear_breakpoints(file)
  M.register_listeners()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.fn.json_encode({ success = false, error = "nvim-dap not available" })
  end

  local breakpoints = require("dap.breakpoints")
  if file then
    local bufnr = vim.fn.bufnr(file)
    if bufnr ~= -1 then
      breakpoints.clear(bufnr)
    end
  else
    -- Clear all
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      breakpoints.clear(buf)
    end
  end

  return vim.fn.json_encode({ success = true })
end

--- Start a debug session with the given config name from launch.json.
--- If config_name is nil, uses the first available config.
---@param config_name string|nil Name of the launch configuration
---@return string JSON result
function M.start_debug(config_name)
  M.register_listeners()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.fn.json_encode({ success = false, error = "nvim-dap not available" })
  end

  -- Load launch.json configs
  local launch_json = require("nvim-launch.launch_json")
  local configs, lj_err = launch_json.get_configurations()
  if lj_err then
    return vim.fn.json_encode({ success = false, error = lj_err })
  end

  if config_name then
    -- Find the named config
    for _, cfg in ipairs(configs) do
      if cfg.name == config_name then
        dap.run(cfg)
        return vim.fn.json_encode({ success = true, config = config_name })
      end
    end
    -- Not found in launch.json, try dap.configurations
    local ft = vim.bo.filetype
    local dap_configs = dap.configurations[ft] or {}
    for _, cfg in ipairs(dap_configs) do
      if cfg.name == config_name then
        dap.run(cfg)
        return vim.fn.json_encode({ success = true, config = config_name })
      end
    end
    return vim.fn.json_encode({ success = false, error = "Config not found: " .. config_name })
  else
    -- Use first available
    if #configs > 0 then
      dap.run(configs[1])
      return vim.fn.json_encode({ success = true, config = configs[1].name })
    end
    return vim.fn.json_encode({ success = false, error = "No launch configurations found" })
  end
end

--- Continue execution (resume from breakpoint).
---@return string JSON result
function M.continue()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.fn.json_encode({ success = false, error = "nvim-dap not available" })
  end
  if not dap.session() then
    return vim.fn.json_encode({ success = false, error = "no active debug session" })
  end
  dap.continue()
  return vim.fn.json_encode({ success = true })
end

--- Stop the current debug session.
---@return string JSON result
function M.stop()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.fn.json_encode({ success = false, error = "nvim-dap not available" })
  end
  if not dap.session() then
    return vim.fn.json_encode({ success = false, error = "no active debug session" })
  end
  dap.terminate()
  return vim.fn.json_encode({ success = true })
end

--- Step over.
---@return string JSON result
function M.step_over()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.fn.json_encode({ success = false, error = "nvim-dap not available" })
  end
  if not dap.session() then
    return vim.fn.json_encode({ success = false, error = "no active debug session" })
  end
  dap.step_over()
  return vim.fn.json_encode({ success = true })
end

--- Step into.
---@return string JSON result
function M.step_into()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.fn.json_encode({ success = false, error = "nvim-dap not available" })
  end
  if not dap.session() then
    return vim.fn.json_encode({ success = false, error = "no active debug session" })
  end
  dap.step_into()
  return vim.fn.json_encode({ success = true })
end

--- Step out.
---@return string JSON result
function M.step_out()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.fn.json_encode({ success = false, error = "nvim-dap not available" })
  end
  if not dap.session() then
    return vim.fn.json_encode({ success = false, error = "no active debug session" })
  end
  dap.step_out()
  return vim.fn.json_encode({ success = true })
end

--- List all available launch configurations.
---@return string JSON {success, configs?: array, error?}
function M.list_configs()
  local launch_json = require("nvim-launch.launch_json")
  local configs, lj_err = launch_json.get_configurations()
  if lj_err then
    return vim.fn.json_encode({ success = false, error = lj_err })
  end
  local names = {}
  for _, cfg in ipairs(configs) do
    table.insert(names, { name = cfg.name, type = cfg.type, request = cfg.request })
  end
  return vim.fn.json_encode({ success = true, configs = names })
end

return M
