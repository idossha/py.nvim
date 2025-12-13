-- Environment detection and management module for pyenv_manager
local M = {}

local config = require("pyenv_manager.config")

-- Helper function to create a unique identifier for a venv
local function create_venv_identifier(venv_path, venv_name, discovery_type)
  local project_name = vim.fn.fnamemodify(vim.fn.fnamemodify(venv_path, ":h"), ":t")
  return {
    venv_name = venv_name,
    project_name = project_name,
    discovery_type = discovery_type,  -- "configured_path", "parent_dir", etc.
    identifier = project_name .. "/" .. venv_name,
    -- Store path only for initial display, but it will be resolved dynamically when used
    cached_path = venv_path
  }
end

-- Dynamically resolve the current path for a venv based on its identifier
function M.resolve_path(env)
  if not env then return nil end

  -- Handle conda environments differently
  if env.type == "conda" then
    -- First check if cached path still exists and is valid
    if env.cached_path and
       vim.fn.isdirectory(env.cached_path) == 1 and
       M.is_conda_env(env.cached_path) then
      return env.cached_path
    end

    -- Search in conda paths
    for _, path in ipairs(config.options.conda_paths) do
      if vim.fn.isdirectory(path) == 1 then
        local entries = vim.fn.glob(path .. "/*", false, true)
        for _, entry in ipairs(entries) do
          if vim.fn.isdirectory(entry) == 1 then
            local entry_name = vim.fn.fnamemodify(entry, ":t")
            if entry_name == env.venv_name and M.is_conda_env(entry) then
              env.cached_path = entry
              return entry
            end
          end
        end
      end
    end

    return nil
  end

  -- Handle venv environments
  -- First check if cached path still exists and is valid
  if env.cached_path and
     vim.fn.isdirectory(env.cached_path) == 1 and
     M.is_venv(env.cached_path) then
    return env.cached_path
  end

  -- Cached path is invalid, search for the venv again
  local venv_name = env.venv_name
  local project_name = env.project_name

  -- Search in configured paths
  for _, path in ipairs(config.options.venv_paths) do
    if vim.fn.isdirectory(path) == 1 then
      -- Check if path itself matches
      if vim.fn.fnamemodify(path, ":t") == venv_name and M.is_venv(path) then
        env.cached_path = path
        return path
      end

      -- Search in subdirectories
      local entries = vim.fn.glob(path .. "/*", false, true)
      for _, entry in ipairs(entries) do
        if vim.fn.isdirectory(entry) == 1 then
          local entry_name = vim.fn.fnamemodify(entry, ":t")

          -- Direct match
          if entry_name == venv_name and M.is_venv(entry) then
            env.cached_path = entry
            return entry
          end

          -- Check for project/venv combination
          if entry_name == project_name then
            local venv_path = entry .. "/" .. venv_name
            if vim.fn.isdirectory(venv_path) == 1 and M.is_venv(venv_path) then
              env.cached_path = venv_path
              return venv_path
            end
          end

          -- Also try any venv inside this directory with matching name
          local potential_path = entry .. "/" .. venv_name
          if vim.fn.isdirectory(potential_path) == 1 and M.is_venv(potential_path) then
            -- Check if the parent matches our project name
            if vim.fn.fnamemodify(entry, ":t") == project_name then
              env.cached_path = potential_path
              return potential_path
            end
          end
        end
      end
    end
  end

  -- Search in parent directories
  local current_dir = vim.fn.getcwd()
  local parent_dir = current_dir
  for i = 1, config.options.parents do
    local parent_name = vim.fn.fnamemodify(parent_dir, ":t")
    local venv_path = parent_dir .. "/" .. venv_name

    if vim.fn.isdirectory(venv_path) == 1 and M.is_venv(venv_path) then
      -- Check if this matches our identifier
      if parent_name == project_name or project_name == venv_name then
        env.cached_path = venv_path
        return venv_path
      end
    end

    parent_dir = vim.fn.fnamemodify(parent_dir, ":h")
    if parent_dir == "/" or parent_dir:match("^%a:[\\/]$") then
      break
    end
  end

  -- Could not find the venv
  return nil
end

-- Find all virtual environments
function M.find_venvs()
  local venvs = {}
  local seen_identifiers = {}  -- Track identifiers we've already added to avoid duplicates

  -- Helper function to add venv if not duplicate
  local function add_venv(venv_entry)
    if not seen_identifiers[venv_entry.identifier] then
      seen_identifiers[venv_entry.identifier] = true
      table.insert(venvs, venv_entry)
    end
  end

  -- Search in predefined paths
  for _, path in ipairs(config.options.venv_paths) do
    if vim.fn.isdirectory(path) == 1 then
      -- Check if the path itself is a venv
      if M.is_venv(path) then
        local venv_name = vim.fn.fnamemodify(path, ":t")
        local env = create_venv_identifier(path, venv_name, "configured_path")
        env.name = venv_name
        env.type = "venv"
        add_venv(env)
      end

      -- Check for venvs in subdirectories
      local entries = vim.fn.glob(path .. "/*", false, true)
      for _, entry in ipairs(entries) do
        if vim.fn.isdirectory(entry) == 1 then
          -- Check if entry is a venv
          if M.is_venv(entry) then
            local venv_name = vim.fn.fnamemodify(entry, ":t")
            local env = create_venv_identifier(entry, venv_name, "configured_path")
            env.name = venv_name
            env.type = "venv"
            add_venv(env)
          else
            -- Check for venv names in subdirectories
            for _, venv_name in ipairs(config.options.venv_names) do
              local venv_path = entry .. "/" .. venv_name
              if vim.fn.isdirectory(venv_path) == 1 and M.is_venv(venv_path) then
                local proj_name = vim.fn.fnamemodify(entry, ":t")
                local env = create_venv_identifier(venv_path, venv_name, "configured_path")
                env.name = proj_name .. " (" .. venv_name .. ")"
                env.type = "venv"
                add_venv(env)
              end
            end
          end
        end
      end
    end
  end

  -- Check parent directories for venvs
  local current_dir = vim.fn.getcwd()
  local parent_dir = current_dir
  for i = 1, config.options.parents do
    for _, venv_name in ipairs(config.options.venv_names) do
      local venv_path = parent_dir .. "/" .. venv_name
      if vim.fn.isdirectory(venv_path) == 1 and M.is_venv(venv_path) then
        -- Use parent directory name + venv name for clarity
        local parent_name = vim.fn.fnamemodify(parent_dir, ":t")
        local env = create_venv_identifier(venv_path, venv_name, "parent_dir")
        env.name = parent_name .. "/" .. venv_name
        env.type = "venv"
        add_venv(env)
      end
    end
    parent_dir = vim.fn.fnamemodify(parent_dir, ":h")
    if parent_dir == "/" or parent_dir:match("^%a:[\\/]$") then
      break
    end
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
  if not config.options.show_conda then
    return {}
  end

  local conda_envs = {}
  local seen_identifiers = {}  -- Track identifiers we've already added to avoid duplicates

  -- Helper function to add conda env if not duplicate
  local function add_conda_env(conda_entry)
    if not seen_identifiers[conda_entry.identifier] then
      seen_identifiers[conda_entry.identifier] = true
      table.insert(conda_envs, conda_entry)
    end
  end

  for _, path in ipairs(config.options.conda_paths) do
    if vim.fn.isdirectory(path) == 1 then
      local entries = vim.fn.glob(path .. "/*", false, true)
      for _, entry in ipairs(entries) do
        if vim.fn.isdirectory(entry) == 1 and M.is_conda_env(entry) then
          local env_name = vim.fn.fnamemodify(entry, ":t")
          local env = {
            venv_name = env_name,
            project_name = env_name,  -- For conda, project name is the env name
            discovery_type = "conda_path",
            identifier = "conda/" .. env_name,
            cached_path = entry,
            name = "conda: " .. env_name,
            type = "conda"
          }
          add_conda_env(env)
        end
      end
    end
  end

  return conda_envs
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
  local bin_dir = vim.fn.has("win32") == 1 and "Scripts" or "bin"
  local pip_path = full_path .. "/" .. bin_dir .. "/pip"
  local upgrade_cmd = pip_path .. " install --upgrade pip"
  local upgrade_result = vim.fn.system(upgrade_cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify("Warning: Failed to upgrade pip", vim.log.levels.WARN)
  else
    vim.notify("pip upgraded successfully", vim.log.levels.INFO)
  end

  -- Return the environment object
  return {
    path = full_path,
    name = name,
    type = "venv"
  }
end

-- Get the path to the Python executable
function M.get_python_path(env)
  if not env then return nil end

  -- Dynamically resolve the current path
  local env_path = M.resolve_path(env)
  if not env_path then return nil end

  local bin_dir = vim.fn.has("win32") == 1 and "Scripts" or "bin"
  local python_exe = vim.fn.has("win32") == 1 and "python.exe" or "python"

  return env_path .. "/" .. bin_dir .. "/" .. python_exe
end

-- Get list of installed packages in a venv
function M.get_packages(env)
  if not env then
    return {"No preview available"}
  end

  -- Dynamically resolve the current path
  local env_path = M.resolve_path(env)
  if not env_path then
    return {
      "ERROR: Virtual environment not found",
      "",
      "Identifier: " .. (env.identifier or "unknown"),
      "Expected venv: " .. (env.venv_name or "unknown"),
      "In project: " .. (env.project_name or "unknown"),
      "",
      "This may happen if:",
      "- A parent directory was renamed or moved",
      "- The virtual environment was deleted",
      "",
      "Please refresh the environment list to rediscover available venvs."
    }
  end

  -- Get pip path
  local bin_dir = vim.fn.has("win32") == 1 and "Scripts" or "bin"
  local pip_path = env_path .. "/" .. bin_dir .. "/pip"

  -- Run pip list
  local cmd = pip_path .. " list --format=columns 2>&1"
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return {
      "ERROR: pip list command failed",
      "",
      "Command: " .. cmd,
      "Path: " .. env_path,
      "",
      "Output:",
      result
    }
  end

  -- Split result into lines and clean each line
  local lines = {}
  for line in result:gmatch("[^\r\n]+") do
    -- Remove any remaining newline characters and trim whitespace
    local cleaned_line = line:gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned_line ~= "" then
      table.insert(lines, cleaned_line)
    end
  end

  if #lines == 0 then
    return {"No packages installed"}
  end

  return lines
end

-- Detect currently active environment
function M.detect_active()
  -- Check for venv
  local venv = vim.env.VIRTUAL_ENV
  if venv and venv ~= "" then
    return {
      path = venv,
      name = vim.fn.fnamemodify(venv, ":t"),
      type = "venv"
    }
  end
  
  -- Check for conda
  local conda = vim.env.CONDA_PREFIX
  if conda and conda ~= "" then
    return {
      path = conda,
      name = "conda: " .. vim.fn.fnamemodify(conda, ":t"),
      type = "conda"
    }
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
  if env.type == "venv" then
    -- For virtual environments
    -- Dynamically resolve the current path
    local resolved_path = M.resolve_path(env)
    if not resolved_path then
      vim.notify("Failed to locate virtual environment: " .. env.name, vim.log.levels.ERROR)
      return false
    end

    local bin_dir = vim.fn.has("win32") == 1 and "Scripts" or "bin"
    local env_path = resolved_path .. "/" .. bin_dir

    -- Update PATH
    vim.env.PATH = env_path .. (vim.fn.has("win32") == 1 and ";" or ":") .. vim.env.PATH
    vim.env.VIRTUAL_ENV = resolved_path

    -- Update Python path for LSP
    local python_path = M.get_python_path(env)
    if not python_path then
      vim.notify("Failed to locate Python executable in: " .. resolved_path, vim.log.levels.ERROR)
      return false
    end
    vim.g.python3_host_prog = python_path

    -- Restart Python LSP servers
    M.restart_python_lsp(python_path)

    -- Apply sys.path changes by setting PYTHONPATH
    -- This helps with import resolution
    local site_packages_path = vim.fn.fnamemodify(python_path, ":h:h") .. "/lib/site-packages"
    -- Get any existing PYTHONPATH
    local existing_pythonpath = vim.env.PYTHONPATH or ""
    -- Set the PYTHONPATH to include the site-packages directory
    vim.env.PYTHONPATH = site_packages_path .. (existing_pythonpath ~= "" and (":" .. existing_pythonpath) or "")

    return true
  elseif env.type == "conda" and M.is_conda_available() then
    -- For conda environments
    -- Dynamically resolve the current path
    local conda_prefix = M.resolve_path(env)
    if not conda_prefix then
      vim.notify("Failed to locate conda environment: " .. env.name, vim.log.levels.ERROR)
      return false
    end
    local bin_dir = vim.fn.has("win32") == 1 and "Scripts" or "bin"
    local env_path = conda_prefix .. "/" .. bin_dir
    
    -- Update PATH
    vim.env.PATH = env_path .. (vim.fn.has("win32") == 1 and ";" or ":") .. vim.env.PATH
    vim.env.CONDA_PREFIX = conda_prefix
    vim.env.CONDA_DEFAULT_ENV = vim.fn.fnamemodify(conda_prefix, ":t") -- Environment name
    
    -- Update Python path for LSP
    local python_path = M.get_python_path(env)
    vim.g.python3_host_prog = python_path
    
    -- Check for conda activation scripts
    local activate_d_path = conda_prefix .. "/etc/conda/activate.d"
    if vim.fn.isdirectory(activate_d_path) == 1 then
      local scripts = vim.fn.glob(activate_d_path .. "/*.sh", false, true)
      for _, script_path in ipairs(scripts) do
        -- Read script content to look for PYTHONPATH modifications
        local file = io.open(script_path, "r")
        if file then
          local content = file:read("*all")
          file:close()
          
          -- Look for SimNIBS specific path (or any PYTHONPATH export)
          local simnibs_path = content:match("export PYTHONPATH=([^:]+)")
          if simnibs_path then
            -- Add this path to PYTHONPATH
            local existing_pythonpath = vim.env.PYTHONPATH or ""
            if existing_pythonpath ~= "" then
              vim.env.PYTHONPATH = simnibs_path .. ":" .. existing_pythonpath
            else
              vim.env.PYTHONPATH = simnibs_path
            end
            vim.notify("Added custom path from activation script: " .. simnibs_path, vim.log.levels.INFO)
          end
        end
      end
    end
    
    -- Special case for SimNIBS environment
    if env.name:match("simnibs") then
      local simnibs_path = "/Users/idohaber/Applications/SimNIBS-4.5"
      if vim.fn.isdirectory(simnibs_path) == 1 then
        local existing_pythonpath = vim.env.PYTHONPATH or ""
        if existing_pythonpath ~= "" then
          vim.env.PYTHONPATH = simnibs_path .. ":" .. existing_pythonpath
        else
          vim.env.PYTHONPATH = simnibs_path
        end
        vim.notify("Added SimNIBS path: " .. simnibs_path, vim.log.levels.INFO)
      end
    end
    
    -- Restart Python LSP servers
    M.restart_python_lsp(python_path)
    
    -- Apply sys.path changes by setting PYTHONPATH for site-packages too
    -- This helps with import resolution
    local site_packages_path
    if vim.fn.has("win32") == 1 then
      site_packages_path = conda_prefix .. "/Lib/site-packages"
    else
      site_packages_path = conda_prefix .. "/lib/python3.*/site-packages"
      -- Expand the wildcard to get the actual path
      local cmd = "ls -d " .. site_packages_path .. " 2>/dev/null || echo ''"
      local handle = io.popen(cmd)
      if handle then
        site_packages_path = handle:read("*a"):gsub("%s+$", "")
        handle:close()
      end
    end
    
    -- Only set PYTHONPATH if we found a valid site-packages path
    if site_packages_path ~= "" then
      -- Get any existing PYTHONPATH
      local existing_pythonpath = vim.env.PYTHONPATH or ""
      -- Set the PYTHONPATH to include the site-packages directory
      vim.env.PYTHONPATH = existing_pythonpath .. (existing_pythonpath ~= "" and (":" .. site_packages_path) or site_packages_path)
    end
    
    return true
  else
    return false
  end
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
