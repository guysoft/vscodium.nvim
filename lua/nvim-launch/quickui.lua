-- nvim-launch/quickui.lua
-- Vim-quickui menu integration for Run/Debug

local M = {}

--- Register the Run menu in vim-quickui
--- Called after quickui is loaded
function M.setup_menu()
  -- Check if quickui is available
  if vim.fn.exists("*quickui#menu#install") ~= 1 then
    return
  end

  vim.fn["quickui#menu#install"]("&Run", {
    { "&Run                   Ctrl+F5",  "lua require('nvim-launch').run()",          "Pick a config and run without debugger (in tmux pane)" },
    { "Start &Debugging          F6",    "lua require('nvim-launch').debug()",        "Pick a config and start debugging" },
    { "--" },
    { "R&un Last              Ctrl+F6",  "lua require('nvim-launch').run_last()",     "Re-run last config without debugger" },
    { "De&bug Last                  ",   "lua require('nvim-launch').debug_last()",   "Re-run last debug session" },
    { "--" },
    { "&Toggle Breakpoint        F9",    "lua require('dap').toggle_breakpoint()",    "Toggle breakpoint on current line" },
    { "&Conditional Breakpoint      ",   "lua require('nvim-launch').conditional_breakpoint()", "Set breakpoint with condition" },
    { "Clear &All Breakpoints      ",    "lua require('dap').clear_breakpoints()",    "Remove all breakpoints" },
    { "--" },
    { "&Continue                 F5",    "lua require('dap').continue()",             "Resume paused debug session" },
    { "Step &Over            leader+do", "lua require('dap').step_over()",            "Step over current line" },
    { "Step &Into               F11",    "lua require('dap').step_into()",            "Step into function" },
    { "Ste&p Out             Shift+F11", "lua require('dap').step_out()",             "Step out of function" },
    { "&Stop                 Shift+F5",  "lua require('dap').terminate()",            "Stop debug session" },
    { "--" },
    { "Toggle Debug &UI     leader+du",  "lua require('dapui').toggle()",             "Toggle debug UI panels" },
    { "Open &launch.json   leader+dl",   "lua require('nvim-launch.launch_json').open_launch_json()", "Open or create launch.json" },
  }, 10000)
end

return M
