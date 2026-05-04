-- nvim-launch/navigation-history-buttons.lua
-- VS Code-style navigation history (back/forward) with mouse button support
-- and optional bufferline.nvim GUI buttons.
--
-- Uses a custom position stack that records on:
--   1. Buffer switches
--   2. Large cursor jumps (> N lines)
--   3. Cursor idle (CursorHold)
-- This gives VS Code-like "where I was working" history.

local M = {}

-- Internal state
local history = {}       -- list of {bufnr, lnum, col}
local history_pos = 0    -- current position in history (1-indexed, 0 = empty)
local max_history = 100  -- max entries
local navigating = false -- flag to prevent recording while navigating
local min_jump_lines = 10 -- minimum line delta to auto-record

--- Record current position into history stack
--- Truncates any forward history when recording from a non-end position
---@param force boolean|nil Force recording even if position hasn't changed much
function M._record(force)
  if navigating then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  -- Skip non-file buffers (terminals, prompts, etc.)
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return
  end

  local pos = vim.api.nvim_win_get_cursor(0)
  local lnum, col = pos[1], pos[2]

  -- Deduplicate: don't record if same buf+line as current position
  if history_pos > 0 and history_pos <= #history then
    local last = history[history_pos]
    if last.bufnr == bufnr and last.lnum == lnum then
      -- Update col silently
      last.col = col
      return
    end
    -- If not forced, check minimum jump distance (within same buffer)
    if not force and last.bufnr == bufnr then
      if math.abs(lnum - last.lnum) < min_jump_lines then
        return
      end
    end
  end

  -- Truncate forward history
  if history_pos < #history then
    for i = #history, history_pos + 1, -1 do
      table.remove(history, i)
    end
  end

  -- Add new entry
  table.insert(history, { bufnr = bufnr, lnum = lnum, col = col })

  -- Trim if over max
  if #history > max_history then
    table.remove(history, 1)
  end

  history_pos = #history
end

--- Check if we can navigate backward
---@return boolean
function M.can_go_back()
  return history_pos > 1
end

--- Check if we can navigate forward
---@return boolean
function M.can_go_forward()
  return history_pos < #history
end

--- Navigate backward in history
function M.go_back()
  if not M.can_go_back() then
    return
  end

  navigating = true
  history_pos = history_pos - 1
  local entry = history[history_pos]

  -- Jump to the buffer and position
  if vim.api.nvim_buf_is_valid(entry.bufnr) then
    if vim.api.nvim_get_current_buf() ~= entry.bufnr then
      vim.api.nvim_set_current_buf(entry.bufnr)
    end
    local line_count = vim.api.nvim_buf_line_count(entry.bufnr)
    local lnum = math.min(entry.lnum, line_count)
    local line = vim.api.nvim_buf_get_lines(entry.bufnr, lnum - 1, lnum, false)[1] or ""
    local col = math.min(entry.col, math.max(0, #line - 1))
    vim.api.nvim_win_set_cursor(0, { lnum, col })
  else
    -- Buffer no longer valid, skip this entry and try again
    table.remove(history, history_pos)
    if history_pos > #history then
      history_pos = #history
    end
    navigating = false
    M.go_back()
    return
  end

  navigating = false
end

--- Navigate forward in history
function M.go_forward()
  if not M.can_go_forward() then
    return
  end

  navigating = true
  history_pos = history_pos + 1
  local entry = history[history_pos]

  if vim.api.nvim_buf_is_valid(entry.bufnr) then
    if vim.api.nvim_get_current_buf() ~= entry.bufnr then
      vim.api.nvim_set_current_buf(entry.bufnr)
    end
    local line_count = vim.api.nvim_buf_line_count(entry.bufnr)
    local lnum = math.min(entry.lnum, line_count)
    local line = vim.api.nvim_buf_get_lines(entry.bufnr, lnum - 1, lnum, false)[1] or ""
    local col = math.min(entry.col, math.max(0, #line - 1))
    vim.api.nvim_win_set_cursor(0, { lnum, col })
  else
    -- Buffer no longer valid, skip
    table.remove(history, history_pos)
    if history_pos > #history then
      history_pos = #history
    end
    navigating = false
    M.go_forward()
    return
  end

  navigating = false
end

--- Setup autocmds to record position history
local function setup_recording(opts)
  local augroup = vim.api.nvim_create_augroup("NavHistoryRecording", { clear = true })

  -- Record on buffer switch (always significant)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      -- Small delay to let cursor settle after buffer switch
      vim.defer_fn(function()
        M._record(true)
      end, 10)
    end,
  })

  -- Record on large jumps (CursorMoved with line delta check)
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    callback = function()
      M._record(false)
    end,
  })

  -- Record on idle (CursorHold) — captures where you've been reading/working
  vim.api.nvim_create_autocmd("CursorHold", {
    group = augroup,
    callback = function()
      M._record(true)
    end,
  })
end

--- Setup mouse button mappings
---@param opts table
local function setup_mouse(opts)
  if not opts.mouse_buttons then
    return
  end

  local modes = { "n", "i", "v" }

  vim.keymap.set(modes, "<X1Mouse>", function()
    M.go_back()
  end, { desc = "Navigate Back (mouse)", silent = true, nowait = true })

  vim.keymap.set(modes, "<X2Mouse>", function()
    M.go_forward()
  end, { desc = "Navigate Forward (mouse)", silent = true, nowait = true })

  -- Suppress release events
  vim.keymap.set(modes, "<X1Release>", "<Nop>", { silent = true })
  vim.keymap.set(modes, "<X2Release>", "<Nop>", { silent = true })
end

--- Setup keyboard shortcuts
---@param opts table
local function setup_keys(opts)
  if not opts.keys then
    return
  end

  if opts.keys.back then
    vim.keymap.set("n", opts.keys.back, function()
      M.go_back()
    end, { desc = "Navigate Back", silent = true })
  end

  if opts.keys.forward then
    vim.keymap.set("n", opts.keys.forward, function()
      M.go_forward()
    end, { desc = "Navigate Forward", silent = true })
  end
end

--- Setup bufferline.nvim custom_areas integration (optional)
---@param opts table
local function setup_bufferline(opts)
  if not opts.bufferline_buttons then
    return
  end

  local ok = pcall(require, "bufferline")
  if not ok then
    return
  end

  -- Define highlight groups
  vim.api.nvim_set_hl(0, "NavHistoryButtonActive", { fg = "#ffffff", bg = "#3c3c3c", bold = true })
  vim.api.nvim_set_hl(0, "NavHistoryButtonInactive", { fg = "#5c5c5c", bg = "#3c3c3c" })

  -- Refresh tabline on cursor movement to update button states
  local refresh_timer = vim.loop.new_timer()
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, {
    group = vim.api.nvim_create_augroup("NavHistoryButtons", { clear = true }),
    callback = function()
      refresh_timer:stop()
      refresh_timer:start(100, 0, vim.schedule_wrap(function()
        vim.cmd("redrawtabline")
      end))
    end,
  })
end

--- Get bufferline custom_areas components
--- Usage in bufferline setup:
---   custom_areas = {
---     left = function()
---       return require("nvim-launch.navigation-history-buttons").get_bufferline_components()
---     end
---   }
---@return table[]
function M.get_bufferline_components()
  local back_hl = M.can_go_back() and "NavHistoryButtonActive" or "NavHistoryButtonInactive"
  local fwd_hl = M.can_go_forward() and "NavHistoryButtonActive" or "NavHistoryButtonInactive"

  return {
    { text = " ◀ ", link = back_hl },
    { text = " ▶ ", link = fwd_hl },
  }
end

--- Get current history state (for debugging/testing)
---@return table
function M._get_state()
  return { history = history, pos = history_pos }
end

--- Reset history (for testing)
function M._reset()
  history = {}
  history_pos = 0
  navigating = false
end

--- Main setup function
---@param opts table Navigation history buttons configuration
function M.setup(opts)
  if not opts or not opts.enabled then
    return
  end

  -- Apply config
  if opts.min_jump_lines then
    min_jump_lines = opts.min_jump_lines
  end
  if opts.max_history then
    max_history = opts.max_history
  end

  setup_recording(opts)
  setup_mouse(opts)
  setup_keys(opts)
  setup_bufferline(opts)

  -- Register user commands
  vim.api.nvim_create_user_command("NavigateBack", function()
    M.go_back()
  end, { desc = "Navigate back in cursor history" })

  vim.api.nvim_create_user_command("NavigateForward", function()
    M.go_forward()
  end, { desc = "Navigate forward in cursor history" })
end

return M
