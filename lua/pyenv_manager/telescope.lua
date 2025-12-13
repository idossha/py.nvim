-- Telescope integration for pyenv_manager
local M = {}

local has_telescope, telescope = pcall(require, "telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local environments = require("pyenv_manager.environments")
local config = require("pyenv_manager.config")

-- Show environment picker with Telescope
function M.show_picker(callback)
  if not has_telescope then
    vim.notify("Telescope is required for environment selection", vim.log.levels.ERROR)
    return
  end
  
  local venvs = environments.find_venvs()
  local conda_envs = environments.find_conda_envs()
  local all_envs = {}
  
  -- Add an option to create new venv (at the top)
  table.insert(all_envs, { path = "", name = "++ Create new venv ++", type = "create_new" })

  -- Combine venvs and conda envs
  for _, env in ipairs(venvs) do
    table.insert(all_envs, env)
  end
  for _, env in ipairs(conda_envs) do
    table.insert(all_envs, env)
  end

  -- Add an option to deactivate
  table.insert(all_envs, { path = "", name = "-- Deactivate --", type = "deactivate" })
  
  -- Create a custom previewer for showing packages
  local package_previewer = previewers.new_buffer_previewer({
    title = "Installed Packages",
    define_preview = function(self, entry, status)
      local env = entry.value

      -- Don't preview for special entries
      if env.type == "create_new" or env.type == "deactivate" then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
          "No preview available for this option"
        })
        return
      end

      -- Get packages
      local packages = environments.get_packages(env)

      if not packages or #packages == 0 then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
          "No packages found"
        })
        return
      end

      -- Ensure all lines are clean (no embedded newlines)
      local clean_packages = {}
      for _, line in ipairs(packages) do
        -- Remove any newline characters that might have slipped through
        local clean_line = tostring(line):gsub("[\r\n]", "")
        table.insert(clean_packages, clean_line)
      end

      -- Display packages in preview buffer
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, clean_packages)

      -- Set filetype for syntax highlighting
      vim.api.nvim_set_option_value("filetype", "text", { buf = self.state.bufnr })
    end,
  })

  -- Show Telescope picker
  pickers.new({}, {
    prompt_title = "Select Python Environment",
    finder = finders.new_table({
      results = all_envs,
      entry_maker = function(entry)
        -- Format display with name and path
        local display_text
        if entry.type == "create_new" or entry.type == "deactivate" then
          -- Special entries don't have paths
          display_text = entry.name
        else
          -- Show name and absolute path
          display_text = entry.name .. "  →  " .. entry.path
        end

        return {
          value = entry,
          display = display_text,
          ordinal = entry.name .. " " .. (entry.path or ""),
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = package_previewer,
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local env = selection.value

        if callback then
          callback(env)
        end
      end)
      return true
    end,
  }):find()
end

return M
