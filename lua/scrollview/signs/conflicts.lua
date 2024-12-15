local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')

local M = {}

local TOP = 0
local MIDDLE = 1
local BOTTOM = 2

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'conflicts'
  scrollview.register_sign_group(group)
  local spec_data = {
    [TOP] = {
      'top',
      vim.g.scrollview_conflicts_top_priority,
      vim.g.scrollview_conflicts_top_symbol,
      'ScrollViewConflictsTop'
    },
    [MIDDLE] = {
      'middle',
      vim.g.scrollview_conflicts_middle_priority,
      vim.g.scrollview_conflicts_middle_symbol,
      'ScrollViewConflictsMiddle'
    },
    [BOTTOM] = {
      'bottom',
      vim.g.scrollview_conflicts_bottom_priority,
      vim.g.scrollview_conflicts_bottom_symbol,
      'ScrollViewConflictsBottom'
    },
  }
  local names = {}  -- maps position to registration name
  for position, item in pairs(spec_data) do
    local variant, priority, symbol, highlight = unpack(item)
    local registration = scrollview.register_sign_spec({
      group = group,
      highlight = highlight,
      priority = priority,
      symbol = symbol,
      variant = variant,
    })
    names[position] = registration.name
  end
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
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
              local str = fn.getbufline(bufnr, line)[1]
              if position == TOP then
                match = vim.startswith(str, '<<<<<<< ')
              elseif position == MIDDLE then
                match = str == '======='
              elseif position == BOTTOM then
                match = vim.startswith(str, '>>>>>>> ')
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
  end)

  api.nvim_create_autocmd('TextChangedI', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      local bufnr = api.nvim_get_current_buf()
      local line = fn.line('.')
      local str = fn.getbufline(bufnr, line)[1]
      for position, name in pairs(names) do
        local expect_sign = nil
        if position == TOP then
          expect_sign = vim.startswith(str, '<<<<<<< ')
        elseif position == MIDDLE then
          expect_sign = str == '======='
        elseif position == BOTTOM then
          expect_sign = vim.startswith(str, '>>>>>>> ')
        else
          error('Unknown position: ' .. position)
        end
        local idx = -1
        local lines = vim.b[bufnr][name]
        if lines ~= nil then
          idx = utils.binary_search(lines, line)
          if lines[idx] ~= line then
            idx = -1
          end
        end
        local has_sign = idx ~= -1
        if expect_sign ~= has_sign then
          scrollview.refresh()
          break
        end
      end
    end
  })
end

return M
