-- Template rendering functionality

local M = {}

local Renderer = {}

function Renderer.escape(data)
  return tostring(data or ''):gsub("[\">/<'&]", {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
    ["/"] = "&#47;"
  })
end

function Renderer.render(tpl, args)
  tpl = tpl:gsub("\n", "\\n")

  local compiled = load(Renderer.parse(tpl))()

  local buffer = {}
  local function exec(data)
    if type(data) == "function" then
      local args = args or {}
      setmetatable(args, { __index = _G })
      load(string.dump(data), nil, nil, args)(exec)
    else
      table.insert(buffer, tostring(data or ''))
    end
  end
  exec(compiled)

  -- First replace all escaped newlines with actual newlines
  local result = table.concat(buffer, ''):gsub("\\n", "\n")
  -- Then reduce multiple consecutive newlines to a single newline
  result = result:gsub("\n\n+", "\n")
  return vim.trim(result)
end

function Renderer.parse(tpl)
  local str =
      "return function(_)" ..
      "function __(...)" ..
      "_(require('template').escape(...))" ..
      "end " ..
      "_[=[" ..
      tpl:
      gsub("[][]=[][]", ']=]_"%1"_[=['):
      gsub("<%%=", "]=]_("):
      gsub("<%%", "]=]__("):
      gsub("%%>", ")_[=["):
      gsub("<%?", "]=] "):
      gsub("%?>", " _[=[") ..
      "]=] " ..
      "end"

  return str
end

-- Find the plugin root directory
local function get_plugin_root()
  local path = debug.getinfo(1, "S").source:sub(2)
  local lua_dir = vim.fn.fnamemodify(path, ":h:h")
  return vim.fn.fnamemodify(lua_dir, ":h") -- Go up one more level
end

local function read_template(template_path)
  local file = io.open(template_path, "r")
  if not file then
    error("Failed to read template file: " .. template_path)
    return nil
  end

  local content = file:read("*all")
  file:close()
  return content
end

function M.cleanup_indentation(template)
  local res = vim.split(template, "\n")
  for i, line in ipairs(res) do
    res[i] = line:gsub("^%s+", "")
  end
  return table.concat(res, "\n")
end

function M.render_template(template_path, template_vars)
  local plugin_root = get_plugin_root()
  local full_template_path = plugin_root .. "/" .. template_path

  local template = read_template(full_template_path)
  if not template then return nil end

  -- Apply indentation cleanup only to the prompt template
  if template_path == "template/prompt.tpl" then
    template = M.cleanup_indentation(template)
  end

  return Renderer.render(template, template_vars)
end

function M.render_prompt(context_vars)
  return M.render_template("template/prompt.tpl", context_vars)
end

function M.render_instructions(context_vars)
  return M.render_template("template/instructions.tpl", context_vars)
end

-- Properly indent a multi-line string for YAML block scalar inclusion
function M.indent_for_yaml(text, indent_level)
  if not text or text == "" then
    return string.rep(" ", indent_level or 2)
  end

  -- Process text: normalize newlines and add indentation
  local indent = string.rep(" ", indent_level or 2)
  local lines = vim.split(text:gsub("\\n", "\n"), "\n")

  -- Apply indentation to each line
  for i, line in ipairs(lines) do
    lines[i] = indent .. line
  end

  return vim.trim(table.concat(lines, "\n"))
end

-- Create a temporary YAML recipe file
function M.create_recipe_file(instructions, prompt)
  local yaml_content = M.render_template('template/recipe.yaml', {
    instructions = M.indent_for_yaml(instructions),
    prompt = M.indent_for_yaml(prompt)
  })

  -- Create a unique temporary file
  local temp_file = string.format(
    "%s/goose_recipe_%d.yaml",
    vim.fn.fnamemodify(vim.fn.tempname(), ":h"),
    os.time()
  )

  -- Write to the file
  local file, err = io.open(temp_file, "w")
  if not file then
    error(string.format("Failed to create temporary recipe file: %s", err or ""))
    return nil
  end

  file:write(yaml_content)
  file:close()

  return temp_file
end

function M.extract_tag(tag, text)
  if not text or not tag then return nil end

  local start_tag = "<" .. tag .. ">"
  local end_tag = "</" .. tag .. ">"

  -- Use pattern matching to find the content between the tags
  local pattern = vim.pesc(start_tag) .. "(.-)" .. vim.pesc(end_tag)
  local content = text:match(pattern)

  return content and vim.trim(content) or nil
end

return M
