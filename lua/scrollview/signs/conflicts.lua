local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

local TOP = 0
local MIDDLE = 1
local BOTTOM = 2

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'conflicts'
  local spec_data = {
    [TOP] = {
      vim.g.scrollview_conflicts_top_priority,
      vim.g.scrollview_conflicts_top_symbol,
      'ScrollViewConflictsTop'
    },
    [MIDDLE] = {
      vim.g.scrollview_conflicts_middle_priority,
      vim.g.scrollview_conflicts_middle_symbol,
      'ScrollViewConflictsMiddle'
    },
    [BOTTOM] = {
      vim.g.scrollview_conflicts_bottom_priority,
      vim.g.scrollview_conflicts_bottom_symbol,
      'ScrollViewConflictsBottom'
    },
  }
  local names = {}  -- maps position to registration name
  for position, item in pairs(spec_data) do
    local priority, symbol, highlight = unpack(item)
    local registration = scrollview.register_sign_spec({
      group = group,
      highlight = highlight,
      priority = priority,
      symbol = symbol,
    })
    names[position] = registration.name
  end
  scrollview.set_sign_group_state(group, enable)

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      -- Track visited buffers, to prevent duplicate computation when multiple
      -- windows are showing the same buffer.
      local visited = {}
      for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        if not visited[bufnr] then
          local bufvars = vim.b[bufnr]
          local changedtick = bufvars.changedtick
          local changedtick_cached =
            bufvars.scrollview_conflicts_changedtick_cached
          local cache_hit = changedtick_cached == changedtick
          for position, name in pairs(names) do
            local lines = {}
            if cache_hit then
              lines = bufvars[name]
            else
              local line_count = api.nvim_buf_line_count(bufnr)
              for line = 1, line_count do
                local match = false
                local string = fn.getbufline(bufnr, line)[1]
                if position == TOP then
                  match = vim.startswith(string, '<<<<<<< ')
                elseif position == MIDDLE then
                  match = string == '======='
                elseif position == BOTTOM then
                  match = vim.startswith(string, '>>>>>>> ')
                else
                  error('Unknown position: ' .. position)
                end
                if match then
                  table.insert(lines, line)
                end
              end
            end
            -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
            bufvars[name] = lines
          end
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars.scrollview_conflicts_changedtick_cached = changedtick
          visited[bufnr] = true
        end
      end
    end
  })
end

return M
