-- goose.nvim/lua/goose/job.lua
-- Contains goose job execution logic

local context = require("goose.context")
local state = require("goose.state")
local template = require("goose.template")
local Job = require('plenary.job')
local util = require("goose.util")

local M = {}

-- Store temporary recipe files to clean up later
M.temp_recipe_files = {}

function M.build_args(input_prompt)
  if not input_prompt then return nil end

  -- Build arguments for goose run
  local args = { "run" }

  -- Create the recipe file
  local instructions = context.format_instructions()
  local prompt = context.format_prompt(input_prompt)
  local recipe_file = template.create_recipe_file(instructions, prompt)

  -- Keep track of the temp file for cleanup
  if recipe_file then
    table.insert(M.temp_recipe_files, recipe_file)
  end

  table.insert(args, "--recipe")
  table.insert(args, recipe_file)

  -- Session management args
  if state.active_session then
    table.insert(args, "--name")
    table.insert(args, state.active_session.name)
    table.insert(args, "--resume")
  else
    local session_name = util.uid()
    state.new_session_name = session_name
    table.insert(args, "--name")
    table.insert(args, session_name)
  end

  return args
end

function M.execute(prompt, handlers)
  if not prompt then
    return nil
  end

  local args = M.build_args(prompt)

  state.goose_run_job = Job:new({
    command = 'goose',
    args = args,
    on_start = function()
      vim.schedule(function()
        handlers.on_start()
      end)
    end,
    on_stdout = function(_, out)
      if out then
        vim.schedule(function()
          handlers.on_output(out)
        end)
      end
    end,
    on_stderr = function(_, err)
      if err then
        vim.schedule(function()
          handlers.on_error(err)
        end)
      end
    end,
    on_exit = function()
      vim.schedule(function()
        -- Clean up temporary recipe files
        M.cleanup_temp_files()

        handlers.on_exit()
      end)
    end
  })

  state.goose_run_job:start()
end

function M.cleanup_temp_files()
  for _, file_path in ipairs(M.temp_recipe_files) do
    if file_path and vim.fn.filereadable(file_path) == 1 then
      -- Use pcall to prevent errors from stopping execution
      pcall(function() os.remove(file_path) end)
    end
  end
  -- Reset the temp files table
  M.temp_recipe_files = {}
end

function M.stop(job)
  if job then
    pcall(function()
      vim.uv.process_kill(job.handle)
      job:shutdown()
    end)
  end

  -- Clean up temp files when stopping a job
  M.cleanup_temp_files()
end

return M
