-- Telescope integration for pyenv_manager
local M = {}

local has_telescope, telescope = pcall(require, "telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

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
  
  -- Show Telescope picker
  pickers.new({}, {
    prompt_title = "Select Python Environment",
    finder = finders.new_table({
      results = all_envs,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.name,
          ordinal = entry.name,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
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
