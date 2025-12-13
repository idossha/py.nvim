-- Main module for pyenv_manager
local M = {}

-- Module imports
local config = require("pyenv_manager.config")
local environments = require("pyenv_manager.environments")
local telescope_integration = require("pyenv_manager.telescope")

-- State variables
M.current_env = nil
M.current_env_type = nil
M.previous_path = nil

-- Setup function
function M.setup(opts)
  -- Load and merge configuration
  config.setup(opts)
  
  -- Create default mappings if enabled
  if config.options.create_mappings then
    local map_opts = { noremap = true, silent = true }
    vim.keymap.set("n", config.options.keymap_select, "<cmd>PyenvSelect<CR>", map_opts)
    
    -- Set the run script keymap with direct function call instead of command
    vim.keymap.set("n", config.options.keymap_run_script, function()
      M.run_script()
    end, map_opts)
  end
  
  -- Set up autocommands
  if config.options.auto_detect_on_start then
    vim.api.nvim_create_autocmd("VimEnter", {
      callback = function()
        vim.defer_fn(function()
          M.detect_active_env()
        end, 500)
      end,
    })
  end
  
  -- Return the module for chaining
  return M
end

-- Detect active environment
function M.detect_active_env()
  local env = environments.detect_active()
  if env then
    M.activate_env(env) -- activate the environment
  end
end

-- Prompt user to create a new venv
function M.create_new_venv()
  vim.ui.input({
    prompt = "Enter virtual environment name: ",
    default = "venv"
  }, function(name)
    if not name or name == "" then
      vim.notify("Venv creation cancelled", vim.log.levels.INFO)
      return
    end

    -- Create the venv in the current working directory
    local new_env = environments.create_venv(name, vim.fn.getcwd())

    if new_env then
      -- Automatically activate the newly created venv
      M.activate_env(new_env)
    end
  end)
end

-- Select environment using Telescope
function M.select_env()
  telescope_integration.show_picker(function(env)
    if env.type == "deactivate" then
      M.deactivate_env()
    elseif env.type == "create_new" then
      M.create_new_venv()
    else
      M.activate_env(env)
    end
  end)
end

-- Activate an environment
function M.activate_env(env)
  if env == nil then
    return false
  end

  -- Validate the environment path exists
  if env.path and env.path ~= "" and vim.fn.isdirectory(env.path) == 0 then
    vim.notify("Environment path no longer exists: " .. env.path, vim.log.levels.ERROR)
    vim.notify("The directory may have been moved or renamed", vim.log.levels.WARN)
    return false
  end

  -- Save the previous PATH to restore later
  M.previous_path = vim.env.PATH
  M.current_env = env
  M.current_env_type = env.type

  -- Perform activation
  local success = environments.activate(env)
  if not success then
    vim.notify("Failed to activate environment: " .. env.name, vim.log.levels.ERROR)
    return false
  end
  
  -- Update global variable for status line
  M.set_env_info(env)
  
  -- Run hooks
  for _, hook in ipairs(config.options.changed_env_hooks) do
    hook(env)
  end
  
  vim.notify("Activated Python environment: " .. env.name, vim.log.levels.INFO)
  vim.cmd("redrawstatus")
  return true
end

-- Deactivate the current environment
function M.deactivate_env()
  if M.current_env == nil then
    vim.notify("No environment is currently active", vim.log.levels.INFO)
    return false
  end
  
  -- Perform deactivation
  environments.deactivate(M.current_env, M.previous_path)
  
  -- Clear global variable for status line
  M.set_env_info(nil)
  
  -- Run hooks
  for _, hook in ipairs(config.options.changed_env_hooks) do
    hook(nil)
  end
  
  vim.notify("Deactivated Python environment: " .. M.current_env.name, vim.log.levels.INFO)
  M.current_env = nil
  M.current_env_type = nil
  M.previous_path = nil
  vim.cmd("redrawstatus")
  return true
end

-- Show environment info
function M.show_info()
  if M.current_env == nil then
    vim.notify("No Python environment is active", vim.log.levels.INFO)
    return
  end
  
  local info = "Active Python Environment:\n"
  info = info .. "  Name: " .. M.current_env.name .. "\n"
  info = info .. "  Type: " .. M.current_env_type .. "\n"
  info = info .. "  Path: " .. M.current_env.path .. "\n"
  
  local python_path = environments.get_python_path(M.current_env)
  if python_path then
    info = info .. "  Python: " .. python_path .. "\n"
  end
  
  vim.notify(info, vim.log.levels.INFO)
end

-- Set environment info for status line
function M.set_env_info(env)
  if env then
    vim.g.pyenv_manager_env_name = env.name
    vim.g.pyenv_manager_env_type = env.type
    vim.g.pyenv_manager_env_path = env.path
  else
    vim.g.pyenv_manager_env_name = nil
    vim.g.pyenv_manager_env_type = nil
    vim.g.pyenv_manager_env_path = nil
  end
end

-- Get current environment
function M.get_current_env()
  return M.current_env
end

function M.run_script()
  -- Check if an environment is active
  if M.current_env == nil then
    vim.notify("No Python environment is active. Please select one first.", vim.log.levels.ERROR)
    return
  end
  
  -- Get the current buffer's file path
  local file_path = vim.fn.expand("%:p")
  
  -- Check if the current file is a Python file
  if not file_path:match("%.py$") then
    vim.notify("Current file is not a Python script.", vim.log.levels.ERROR)
    return
  end
  
  -- Get the Python executable path
  local python_path = environments.get_python_path(M.current_env)
  if not python_path then
    vim.notify("Could not determine Python executable path.", vim.log.levels.ERROR)
    return
  end
  
  -- Save the file before running
  vim.cmd("write")
  
  -- Create the command to run the script
  local cmd = python_path .. " " .. vim.fn.shellescape(file_path)
  
  -- Determine how to run the command based on configuration
  if config.options.run_in_terminal then
    -- Close any existing terminal buffers (optional)
    vim.cmd("silent! bdelete! term:")
    
    -- Run in a terminal buffer
    vim.cmd("botright " .. config.options.terminal_height .. "split")
    
    -- Display environment info at the top of the terminal
    local env_info = file_path .. " Running with Python environment: " .. M.current_env.name .. " (" .. python_path .. ")"
    
    -- Create the terminal with clear command
    vim.cmd("terminal clear && echo '" .. env_info .. "' && echo '-- Press q to close this window --' && " .. cmd)
    
    -- Set up the terminal buffer options and mappings for this buffer
    local buf = vim.api.nvim_get_current_buf()
    
    -- Set buffer-local options for better navigation
    vim.opt_local.number = true
    vim.opt_local.relativenumber = true
    
    -- Start in normal mode instead of insert mode
    vim.cmd("stopinsert")
    
    -- Map 'q' to close the terminal buffer - use buf explicitly
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":bdelete!<CR>", {
      noremap = true,
      silent = true,
      desc = "Close terminal"
    })
    
    -- No need to add the message at the bottom - we'll show it at the top instead
  else
    -- Run using system() and display output
    vim.notify("Running with environment: " .. M.current_env.name, vim.log.levels.INFO)
    vim.notify("Python path: " .. python_path, vim.log.levels.INFO)
    vim.notify("Command: " .. cmd, vim.log.levels.INFO)
    
    -- Create a callback to handle the command output
    local on_exit = function(job_id, exit_code, _)
      if exit_code == 0 then
        vim.notify("Script executed successfully.", vim.log.levels.INFO)
      else
        vim.notify("Script execution failed with exit code: " .. exit_code, vim.log.levels.ERROR)
      end
    end
    
    -- Run the command asynchronously
    vim.fn.jobstart(cmd, {
      on_exit = on_exit,
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data)
        if data and #data > 1 then
          vim.notify(table.concat(data, "\n"), vim.log.levels.INFO)
        end
      end,
      on_stderr = function(_, data)
        if data and #data > 1 then
          vim.notify(table.concat(data, "\n"), vim.log.levels.ERROR)
        end
      end,
    })
  end
end
return M
