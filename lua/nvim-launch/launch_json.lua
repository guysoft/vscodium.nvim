-- nvim-launch/launch_json.lua
-- Parse .vscode/launch.json (JSONC) and resolve VSCode-style variables

local M = {}

local config = require("nvim-launch.config")

--- Resolve VSCode-style variables in a string
---@param str string
---@param cfg table|nil Optional launch config for context
---@return string
function M.resolve_variables(str, cfg)
  if type(str) ~= "string" then
    return str
  end

  local workspace_folder = vim.fn.getcwd()
  local file = vim.fn.expand("%:p")
  local file_dir = vim.fn.expand("%:p:h")
  local file_basename = vim.fn.expand("%:t")
  local file_ext = vim.fn.expand("%:e")
  local file_basename_no_ext = vim.fn.expand("%:t:r")
  local relative_file = vim.fn.expand("%:.")
  local relative_file_dir = vim.fn.fnamemodify(vim.fn.expand("%:."), ":h")
  local workspace_folder_basename = vim.fn.fnamemodify(workspace_folder, ":t")
  local cwd = cfg and cfg.cwd or workspace_folder

  local vars = {
    ["${file}"] = file,
    ["${fileBasename}"] = file_basename,
    ["${fileBasenameNoExtension}"] = file_basename_no_ext,
    ["${fileDirname}"] = file_dir,
    ["${fileExtname}"] = file_ext ~= "" and ("." .. file_ext) or "",
    ["${relativeFile}"] = relative_file,
    ["${relativeFileDirname}"] = relative_file_dir,
    ["${workspaceFolder}"] = workspace_folder,
    ["${workspaceFolderBasename}"] = workspace_folder_basename,
    ["${cwd}"] = cwd,
    ["${lineNumber}"] = tostring(vim.fn.line(".")),
    ["${selectedText}"] = "",
    ["${pathSeparator}"] = "/",
  }

  local result = str

  -- Resolve standard variables
  for var, val in pairs(vars) do
    result = result:gsub(vim.pesc(var), (val:gsub("%%", "%%%%")))
  end

  -- Resolve ${workspaceFolder:name} (multi-root workspace syntax)
  -- Falls back to the current workspace folder
  result = result:gsub("%${workspaceFolder:[^}]+}", workspace_folder)

  -- Resolve ${env:NAME} variables
  result = result:gsub("%${env:([^}]+)}", function(name)
    return os.getenv(name) or ""
  end)

  return result
end

--- Resolve all string values in a table recursively
---@param tbl table
---@param cfg table|nil
---@return table
function M.resolve_variables_in_table(tbl, cfg)
  local result = {}
  for k, v in pairs(tbl) do
    if type(v) == "string" then
      result[k] = M.resolve_variables(v, cfg)
    elseif type(v) == "table" then
      result[k] = M.resolve_variables_in_table(v, cfg)
    else
      result[k] = v
    end
  end
  return result
end

--- Strip JSONC comments (// and /* */) properly
--- Handles comments inside arrays, after values, etc.
---@param text string
---@return string
local function strip_jsonc_comments(text)
  local result = {}
  local i = 1
  local len = #text
  local in_string = false
  local string_char = nil

  while i <= len do
    local c = text:sub(i, i)
    local next_c = text:sub(i + 1, i + 1)

    if in_string then
      table.insert(result, c)
      if c == "\\" then
        -- Skip escaped character
        i = i + 1
        if i <= len then
          table.insert(result, text:sub(i, i))
        end
      elseif c == string_char then
        in_string = false
        string_char = nil
      end
    elseif c == '"' then
      in_string = true
      string_char = c
      table.insert(result, c)
    elseif c == "/" and next_c == "/" then
      -- Single-line comment: skip to end of line
      i = i + 2
      while i <= len and text:sub(i, i) ~= "\n" do
        i = i + 1
      end
      -- Don't skip the newline itself, let the loop handle it
      goto continue
    elseif c == "/" and next_c == "*" then
      -- Block comment: skip to */
      i = i + 2
      while i <= len do
        if text:sub(i, i) == "*" and text:sub(i + 1, i + 1) == "/" then
          i = i + 2
          break
        end
        -- Preserve newlines for line counting
        if text:sub(i, i) == "\n" then
          table.insert(result, "\n")
        end
        i = i + 1
      end
      goto continue
    else
      table.insert(result, c)
    end

    i = i + 1
    ::continue::
  end

  return table.concat(result)
end

--- Remove trailing commas from JSON (common in JSONC)
---@param text string
---@return string
local function strip_trailing_commas(text)
  -- Remove commas followed by optional whitespace/newlines then } or ]
  text = text:gsub(",%s*}", "}")
  text = text:gsub(",%s*%]", "]")
  return text
end

--- Read and parse launch.json from the workspace
---@param path string|nil Optional path to launch.json
---@return table|nil configurations Array of launch configurations
---@return string|nil error Error message if parsing failed
function M.read_launch_json(path)
  local conf = config.get()
  path = path or (vim.fn.getcwd() .. "/" .. conf.launch_json_path)

  if vim.fn.filereadable(path) ~= 1 then
    return nil, "launch.json not found: " .. path
  end

  local content = table.concat(vim.fn.readfile(path), "\n")

  -- Strip JSONC comments and trailing commas
  content = strip_jsonc_comments(content)
  content = strip_trailing_commas(content)

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil, "Failed to parse launch.json: " .. tostring(data)
  end

  if not data.configurations or type(data.configurations) ~= "table" then
    return nil, "launch.json has no 'configurations' array"
  end

  -- Apply platform-specific overrides
  local platform = "linux"
  if vim.fn.has("mac") == 1 then
    platform = "osx"
  elseif vim.fn.has("win32") == 1 then
    platform = "windows"
  end

  local configs = {}
  for _, cfg in ipairs(data.configurations) do
    local resolved = vim.deepcopy(cfg)

    -- Apply platform-specific overrides
    if resolved[platform] and type(resolved[platform]) == "table" then
      resolved = vim.tbl_deep_extend("force", resolved, resolved[platform])
    end
    -- Remove platform keys
    resolved.linux = nil
    resolved.osx = nil
    resolved.windows = nil

    table.insert(configs, resolved)
  end

  return configs, nil
end

--- Get all launch configurations with variables resolved
---@return table configurations
---@return string|nil error
function M.get_configurations()
  local configs, err = M.read_launch_json()
  if err then
    return {}, err
  end

  local resolved = {}
  for _, cfg in ipairs(configs) do
    table.insert(resolved, M.resolve_variables_in_table(cfg, cfg))
  end

  return resolved, nil
end

--- Get raw configurations (variables NOT resolved yet)
--- Useful when passing to DAP which does its own resolution
---@return table configurations
---@return string|nil error
function M.get_raw_configurations()
  return M.read_launch_json()
end

--- Create a default launch.json template
---@return string content Pretty-printed JSON
function M.default_template()
  local template = {
    version = "0.2.0",
    configurations = {
      {
        type = "debugpy",
        request = "launch",
        name = "Python: Current File",
        program = "${file}",
        console = "integratedTerminal",
      },
      {
        type = "go",
        request = "launch",
        name = "Go: Run Package",
        mode = "auto",
        program = "${fileDirname}",
      },
    },
  }
  return M.pretty_json(template)
end

--- Pretty-print a Lua table as formatted JSON
---@param tbl table
---@return string
function M.pretty_json(tbl)
  local json = vim.json.encode(tbl)
  local indent = 0
  local result = {}
  local in_string = false
  local i = 1
  while i <= #json do
    local c = json:sub(i, i)
    if c == '"' and (i == 1 or json:sub(i - 1, i - 1) ~= "\\") then
      in_string = not in_string
      table.insert(result, c)
    elseif in_string then
      table.insert(result, c)
    elseif c == "{" or c == "[" then
      indent = indent + 1
      table.insert(result, c)
      table.insert(result, "\n" .. string.rep("    ", indent))
    elseif c == "}" or c == "]" then
      indent = indent - 1
      table.insert(result, "\n" .. string.rep("    ", indent) .. c)
    elseif c == "," then
      table.insert(result, c)
      table.insert(result, "\n" .. string.rep("    ", indent))
    elseif c == ":" then
      table.insert(result, ": ")
    else
      table.insert(result, c)
    end
    i = i + 1
  end
  return table.concat(result)
end

--- Open or create launch.json
function M.open_launch_json()
  local conf = config.get()
  local path = vim.fn.getcwd() .. "/" .. conf.launch_json_path
  local dir = vim.fn.fnamemodify(path, ":h")

  if vim.fn.filereadable(path) ~= 1 then
    -- Create .vscode directory and launch.json with template
    vim.fn.mkdir(dir, "p")
    local content = M.default_template()
    vim.fn.writefile(vim.split(content, "\n"), path)
    vim.notify("Created " .. conf.launch_json_path, vim.log.levels.INFO)
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

return M
