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

-- Read the Jinja template file
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

  -- Only clean up indentation for the prompt template
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
-- This ensures all lines have consistent indentation to maintain YAML validity
function M.indent_for_yaml(text, indent_level)
  indent_level = indent_level or 2 -- Default indent of 2 spaces
  local indent = string.rep(" ", indent_level)

  -- If text is nil or empty, return an empty string with proper indentation
  if not text or text == "" then
    return indent
  end

  -- Replace any escaped newlines with actual newlines
  text = text:gsub("\\n", "\n")

  -- Split text into lines
  local lines = vim.split(text, "\n")

  -- Indent each line
  for i, line in ipairs(lines) do
    -- Empty lines still need indentation to maintain YAML block structure
    lines[i] = indent .. line
  end

  -- Join lines back together
  return vim.trim(table.concat(lines, "\n"))
end

-- Create a temporary YAML recipe file from the rendered template
function M.create_recipe_file(instructions, prompt)
  -- Create directly formatted YAML without using the template engine for the multi-line parts
  local yaml_content = M.render_template('template/recipe.yaml', {
    instructions = M.indent_for_yaml(instructions),
    prompt = M.indent_for_yaml(prompt)
  })

  -- Create a temporary file
  local temp_dir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
  local temp_file = temp_dir .. "/goose_recipe_" .. os.time() .. ".yaml"

  -- Write the directly formatted YAML to the temporary file
  local file = io.open(temp_file, "w")
  if not file then
    error("Failed to create temporary recipe file")
    return nil
  end

  file:write(yaml_content)
  file:close()

  local handle = io.popen('cat ' .. temp_file)
  if not handle then return nil end
  local result = handle:read("*a")
  print(result)
  handle:close()

  return temp_file
end

function M.extract_tag(tag, text)
  local start_tag = "<" .. tag .. ">"
  local end_tag = "</" .. tag .. ">"

  -- Use pattern matching to find the content between the tags
  -- Make search start_tag and end_tag more robust with pattern escaping
  local pattern = vim.pesc(start_tag) .. "(.-)" .. vim.pesc(end_tag)
  local content = text:match(pattern)

  if content then
    return vim.trim(content)
  end

  -- Fallback to the original method if pattern matching fails
  local query_start = text:find(start_tag)
  local query_end = text:find(end_tag)

  if query_start and query_end then
    -- Extract and trim the content between the tags
    local query_content = text:sub(query_start + #start_tag, query_end - 1)
    return vim.trim(query_content)
  end

  return nil
end

return M
