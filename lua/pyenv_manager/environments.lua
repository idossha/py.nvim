-- Environment detection and management module for pyenv_manager
local M = {}

local config = require("pyenv_manager.config")

-- Helper: Get bin directory name based on OS
local function get_bin_dir()
  return vim.fn.has("win32") == 1 and "Scripts" or "bin"
end

-- Helper: Get python executable name based on OS
local function get_python_exe()
  return vim.fn.has("win32") == 1 and "python.exe" or "python"
end

-- Helper: Get python path from environment path
local function get_python_from_env_path(env_path)
  return env_path .. "/" .. get_bin_dir() .. "/" .. get_python_exe()
end

-- Helper: Create environment identifier structure
local function create_env_identifier(env_path, env_name, env_type, discovery_type)
  local project_name = vim.fn.fnamemodify(vim.fn.fnamemodify(env_path, ":h"), ":t")
  local identifier_prefix = env_type == "conda" and "conda/" or (project_name .. "/")

  return {
    venv_name = env_name,
    project_name = env_type == "conda" and env_name or project_name,
    discovery_type = discovery_type,
    identifier = identifier_prefix .. env_name,
    cached_path = env_path,
    name = env_type == "conda" and ("conda: " .. env_name) or env_name,
    type = env_type
  }
end

-- Dynamically resolve the current path for a venv based on its identifier
function M.resolve_path(env)
  if not env then return nil end

  -- Check if cached path is still valid
  local is_valid = env.type == "conda" and M.is_conda_env or M.is_venv
  if env.cached_path and vim.fn.isdirectory(env.cached_path) == 1 and is_valid(env.cached_path) then
    return env.cached_path
  end

  -- Search function that checks a path and updates cache if found
  local function check_and_cache(path)
    if vim.fn.isdirectory(path) == 1 and is_valid(path) then
      env.cached_path = path
      return path
    end
  end

  local venv_name = env.venv_name
  local project_name = env.project_name
  local search_paths = env.type == "conda" and config.options.conda_paths or config.options.venv_paths

  -- Search in configured paths
  for _, base_path in ipairs(search_paths) do
    if vim.fn.isdirectory(base_path) == 1 then
      -- Check if base path itself is the environment
      local result = check_and_cache(base_path)
      if result then return result end

      -- Search subdirectories
      for _, entry in ipairs(vim.fn.glob(base_path .. "/*", false, true)) do
        if vim.fn.isdirectory(entry) == 1 then
          local entry_name = vim.fn.fnamemodify(entry, ":t")

          -- Direct match or project/venv match
          result = check_and_cache(entry)
          if result and entry_name == venv_name then return result end

          result = check_and_cache(entry .. "/" .. venv_name)
          if result and (entry_name == project_name or env.type == "conda") then return result end
        end
      end
    end
  end

  -- For venvs, also search parent directories
  if env.type == "venv" then
    local parent_dir = vim.fn.getcwd()
    for i = 1, config.options.parents do
      local result = check_and_cache(parent_dir .. "/" .. venv_name)
      if result then return result end

      parent_dir = vim.fn.fnamemodify(parent_dir, ":h")
      if parent_dir == "/" or parent_dir:match("^%a:[\\/]$") then break end
    end
  end

  return nil
end

-- Find all virtual environments
function M.find_venvs()
  local venvs = {}
  local seen = {}

  local function add_if_new(env)
    if not seen[env.identifier] then
      seen[env.identifier] = true
      table.insert(venvs, env)
    end
  end

  -- Search in predefined paths
  for _, path in ipairs(config.options.venv_paths) do
    if vim.fn.isdirectory(path) == 1 then
      -- Check if path itself is a venv
      if M.is_venv(path) then
        add_if_new(create_env_identifier(path, vim.fn.fnamemodify(path, ":t"), "venv", "configured"))
      end

      -- Check subdirectories
      for _, entry in ipairs(vim.fn.glob(path .. "/*", false, true)) do
        if vim.fn.isdirectory(entry) == 1 then
          if M.is_venv(entry) then
            add_if_new(create_env_identifier(entry, vim.fn.fnamemodify(entry, ":t"), "venv", "configured"))
          else
            -- Check for standard venv names within projects
            for _, venv_name in ipairs(config.options.venv_names) do
              local venv_path = entry .. "/" .. venv_name
              if M.is_venv(venv_path) then
                local env = create_env_identifier(venv_path, venv_name, "venv", "configured")
                env.name = vim.fn.fnamemodify(entry, ":t") .. " (" .. venv_name .. ")"
                add_if_new(env)
              end
            end
          end
        end
      end
    end
  end

  -- Check parent directories
  local parent_dir = vim.fn.getcwd()
  for i = 1, config.options.parents do
    for _, venv_name in ipairs(config.options.venv_names) do
      local venv_path = parent_dir .. "/" .. venv_name
      if M.is_venv(venv_path) then
        local env = create_env_identifier(venv_path, venv_name, "venv", "parent")
        env.name = vim.fn.fnamemodify(parent_dir, ":t") .. "/" .. venv_name
        add_if_new(env)
      end
    end
    parent_dir = vim.fn.fnamemodify(parent_dir, ":h")
    if parent_dir == "/" or parent_dir:match("^%a:[\\/]$") then break end
  end

  return venvs
end

-- Check if a directory is a valid venv
function M.is_venv(path)
  return vim.fn.filereadable(path .. "/bin/activate") == 1 or 
         vim.fn.filereadable(path .. "/Scripts/activate.bat") == 1
end

-- Find conda environments
function M.find_conda_envs()
  if not config.options.show_conda then return {} end

  local envs = {}
  local seen = {}

  for _, path in ipairs(config.options.conda_paths) do
    if vim.fn.isdirectory(path) == 1 then
      for _, entry in ipairs(vim.fn.glob(path .. "/*", false, true)) do
        if M.is_conda_env(entry) then
          local env = create_env_identifier(entry, vim.fn.fnamemodify(entry, ":t"), "conda", "conda_path")
          if not seen[env.identifier] then
            seen[env.identifier] = true
            table.insert(envs, env)
          end
        end
      end
    end
  end

  return envs
end

-- Check if a directory is a valid conda env
function M.is_conda_env(path)
  return vim.fn.isdirectory(path .. "/bin") == 1 or 
         vim.fn.isdirectory(path .. "/Scripts") == 1
end

-- Check if conda is available
function M.is_conda_available()
  return vim.fn.executable("conda") == 1
end

-- Create a new virtual environment
function M.create_venv(name, path)
  -- Default to current working directory if path not provided
  local venv_path = path or vim.fn.getcwd()
  local full_path = venv_path .. "/" .. name

  -- Check if directory already exists
  if vim.fn.isdirectory(full_path) == 1 then
    vim.notify("Directory already exists: " .. full_path, vim.log.levels.ERROR)
    return nil
  end

  -- Find Python executable
  local python_cmd = vim.fn.exepath("python3") or vim.fn.exepath("python")
  if not python_cmd or python_cmd == "" then
    vim.notify("Python executable not found", vim.log.levels.ERROR)
    return nil
  end

  -- Create the venv
  vim.notify("Creating virtual environment: " .. name, vim.log.levels.INFO)
  local cmd = python_cmd .. " -m venv " .. vim.fn.shellescape(full_path)
  local result = vim.fn.system(cmd)

  -- Check if creation was successful
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to create virtual environment:\n" .. result, vim.log.levels.ERROR)
    return nil
  end

  -- Verify the venv was created correctly
  if not M.is_venv(full_path) then
    vim.notify("Virtual environment created but validation failed", vim.log.levels.ERROR)
    return nil
  end

  vim.notify("Successfully created virtual environment: " .. name, vim.log.levels.INFO)

  -- Upgrade pip
  vim.notify("Upgrading pip...", vim.log.levels.INFO)
  local python_path = get_python_from_env_path(full_path)
  vim.fn.system(python_path .. " -m pip install --upgrade pip")

  if vim.v.shell_error ~= 0 then
    vim.notify("Warning: Failed to upgrade pip", vim.log.levels.WARN)
  else
    vim.notify("pip upgraded successfully", vim.log.levels.INFO)
  end

  return create_env_identifier(full_path, name, "venv", "created")
end

-- Get the path to the Python executable
function M.get_python_path(env)
  local env_path = M.resolve_path(env)
  return env_path and get_python_from_env_path(env_path) or nil
end

-- Get list of installed packages in a venv
function M.get_packages(env)
  if not env then return {"No preview available"} end

  local env_path = M.resolve_path(env)
  if not env_path then
    return {"ERROR: Environment not found - " .. (env.identifier or "unknown")}
  end

  local python_path = get_python_from_env_path(env_path)
  local result = vim.fn.system(python_path .. " -m pip list --format=columns 2>&1")

  if vim.v.shell_error ~= 0 then
    return {"ERROR: pip list failed", "", result}
  end

  local lines = {}
  for line in result:gmatch("[^\r\n]+") do
    local cleaned = line:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned ~= "" then table.insert(lines, cleaned) end
  end

  return #lines > 0 and lines or {"No packages installed"}
end

-- Detect currently active environment
function M.detect_active()
  local venv = vim.env.VIRTUAL_ENV
  if venv and venv ~= "" then
    return create_env_identifier(venv, vim.fn.fnamemodify(venv, ":t"), "venv", "active")
  end

  local conda = vim.env.CONDA_PREFIX
  if conda and conda ~= "" then
    return create_env_identifier(conda, vim.fn.fnamemodify(conda, ":t"), "conda", "active")
  end

  return nil
end

function M.restart_python_lsp(python_path)
  -- Check if nvim-lspconfig is available
  local has_lspconfig = pcall(require, "lspconfig")
  if not has_lspconfig then
    return
  end
  
  -- Get a list of running LSP clients
  local clients = vim.lsp.get_clients or vim.lsp.get_clients
  local python_servers = {"pyright", "pylsp", "jedi_language_server", "ruff_lsp"}
  
  -- Update LSP settings for each Python server
  for _, server_name in ipairs(python_servers) do
    -- Execute for each active client of this type
    for _, client in ipairs(clients({ name = server_name })) do
      if not client then
        goto continue
      end
      
      vim.notify("Updating " .. server_name .. " to use: " .. python_path, vim.log.levels.INFO)
      
      -- Update the client settings
      if client.settings then
        if server_name == "pyright" then
          client.settings = vim.tbl_deep_extend('force', client.settings, { 
            python = { 
              pythonPath = python_path,
              analysis = {
                autoSearchPaths = true,
                diagnosticMode = "workspace",
                useLibraryCodeForTypes = true,
                typeCheckingMode = "basic",
                reportMissingImports = true,
                reportMissingModuleSource = true,
              }
            } 
          })
        elseif server_name == "pylsp" then
          client.settings = vim.tbl_deep_extend('force', client.settings, {
            pylsp = {
              plugins = {
                jedi = {
                  environment = python_path,
                },
              },
            }
          })
        elseif server_name == "jedi_language_server" then
          client.settings = vim.tbl_deep_extend('force', client.settings, {
            jedi = {
              environment = python_path,
            }
          })
        end
      else
        -- Some clients store settings in config.settings instead
        if not client.config then client.config = {} end
        if not client.config.settings then client.config.settings = {} end
        
        if server_name == "pyright" then
          client.config.settings = vim.tbl_deep_extend('force', client.config.settings, { 
            python = { 
              pythonPath = python_path,
              analysis = {
                autoSearchPaths = true,
                diagnosticMode = "workspace",
                useLibraryCodeForTypes = true,
                typeCheckingMode = "basic",
                reportMissingImports = true,
                reportMissingModuleSource = true,
              }
            } 
          })
        elseif server_name == "pylsp" then
          client.config.settings = vim.tbl_deep_extend('force', client.config.settings, {
            pylsp = {
              plugins = {
                jedi = {
                  environment = python_path,
                },
              },
            }
          })
        elseif server_name == "jedi_language_server" then
          client.config.settings = vim.tbl_deep_extend('force', client.config.settings, {
            jedi = {
              environment = python_path,
            }
          })
        end
      end
      
      -- Notify the client of configuration changes
      client.notify('workspace/didChangeConfiguration', { settings = nil })
      
      ::continue::
    end
  end
  
  -- Force reload of all Python files
  vim.defer_fn(function()
    -- Get all buffer numbers
    local buffers = vim.api.nvim_list_bufs()
    for _, bufnr in ipairs(buffers) do
      -- Check if the buffer is loaded and is a Python file
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if bufname:match("%.py$") then
          -- Request diagnostics for this buffer
          vim.diagnostic.show()
        end
      end
    end
  end, 1000) -- Wait 1 second for LSP to process configuration changes
end

-- Activate an environment
function M.activate(env)
  local resolved_path = M.resolve_path(env)
  if not resolved_path then
    vim.notify("Failed to locate environment: " .. env.name, vim.log.levels.ERROR)
    return false
  end

  local python_path = M.get_python_path(env)
  if not python_path then
    vim.notify("Failed to locate Python in: " .. resolved_path, vim.log.levels.ERROR)
    return false
  end

  local path_sep = vim.fn.has("win32") == 1 and ";" or ":"

  -- Update PATH and Python host
  vim.env.PATH = resolved_path .. "/" .. get_bin_dir() .. path_sep .. vim.env.PATH
  vim.g.python3_host_prog = python_path

  -- Set environment-specific variables
  if env.type == "venv" then
    vim.env.VIRTUAL_ENV = resolved_path
    vim.env.PYTHONPATH = vim.fn.fnamemodify(python_path, ":h:h") .. "/lib/site-packages"
      .. (vim.env.PYTHONPATH and (path_sep .. vim.env.PYTHONPATH) or "")
  elseif env.type == "conda" then
    vim.env.CONDA_PREFIX = resolved_path
    vim.env.CONDA_DEFAULT_ENV = vim.fn.fnamemodify(resolved_path, ":t")

    -- Check conda activation scripts for PYTHONPATH
    local activate_d = resolved_path .. "/etc/conda/activate.d"
    if vim.fn.isdirectory(activate_d) == 1 then
      for _, script in ipairs(vim.fn.glob(activate_d .. "/*.sh", false, true)) do
        local file = io.open(script, "r")
        if file then
          local custom_path = file:read("*all"):match("export PYTHONPATH=([^:]+)")
          file:close()
          if custom_path then
            vim.env.PYTHONPATH = custom_path .. (vim.env.PYTHONPATH and (path_sep .. vim.env.PYTHONPATH) or "")
          end
        end
      end
    end

    -- Special case: SimNIBS
    if env.name:match("simnibs") then
      local simnibs = "/Users/idohaber/Applications/SimNIBS-4.5"
      if vim.fn.isdirectory(simnibs) == 1 then
        vim.env.PYTHONPATH = simnibs .. (vim.env.PYTHONPATH and (path_sep .. vim.env.PYTHONPATH) or "")
      end
    end
  end

  M.restart_python_lsp(python_path)
  return true
end
-- Deactivate an environment
function M.deactivate(env, previous_path)
  -- Restore previous PATH
  if previous_path then
    vim.env.PATH = previous_path
  end
  
  -- Clear environment variables
  if env.type == "venv" then
    vim.env.VIRTUAL_ENV = nil
  elseif env.type == "conda" then
    vim.env.CONDA_PREFIX = nil
  end
  
  -- Clear PYTHONPATH
  vim.env.PYTHONPATH = nil
  
  -- Reset Python path
  vim.g.python3_host_prog = vim.fn.exepath("python3") or vim.fn.exepath("python") or "python"
  
  -- Restart LSP servers with default Python
  M.restart_python_lsp(vim.g.python3_host_prog)
  
  return true
end

return M
