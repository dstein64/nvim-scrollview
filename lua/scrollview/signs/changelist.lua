local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

local PREVIOUS = 0
local CURRENT = 1
local NEXT = 2

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'changelist'
  scrollview.register_sign_group(group)

  local spec_data = {
    [PREVIOUS] = {
      'previous',
      vim.g.scrollview_changelist_previous_priority,
      vim.g.scrollview_changelist_previous_symbol,
      'ScrollViewChangeListPrevious'
    },
    [CURRENT] = {
      'current',
      vim.g.scrollview_changelist_current_priority,
      vim.g.scrollview_changelist_current_symbol,
      'ScrollViewChangeListCurrent'
    },
    [NEXT] = {
      'next',
      vim.g.scrollview_changelist_next_priority,
      vim.g.scrollview_changelist_next_symbol,
      'ScrollViewChangeListNext'
    },
  }
  local names = {}  -- maps direction to registration name
  for direction, item in pairs(spec_data) do
    local variant, priority, symbol, highlight = unpack(item)
    local registration = scrollview.register_sign_spec({
      group = group,
      highlight = highlight,
      priority = priority,
      symbol = symbol,
      variant = variant,
    })
    names[direction] = registration.name
  end
  scrollview.set_sign_group_state(group, enable)

  -- Refresh scrollbars after jumping through the change list.
  scrollview.register_key_sequence_callback('g;', 'nv', scrollview.refresh)
  scrollview.register_key_sequence_callback('g,', 'nv', scrollview.refresh)

  scrollview.set_sign_group_callback(group, function()
    -- Track visited buffers, to prevent duplicate computation when multiple
    -- windows are showing the same buffer.
    local visited = {}
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      if not visited[bufnr] then
        local bufvars = vim.b[bufnr]
        for direction, name in pairs(names) do
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars[name] = {}
          local locations, position = unpack(fn.getchangelist(bufnr))
          position = position + 1
          if direction == PREVIOUS
              and #locations > 0
              and position - 1 > 0
              and position - 1 <= #locations then
            bufvars[name] = {locations[position - 1].lnum}
          end
          if direction == CURRENT
              and #locations > 0
              and position > 0
              and position <= #locations then
            bufvars[name] = {locations[position].lnum}
          end
          if direction == NEXT
              and #locations > 0
              and position + 1 > 0
              and position + 1 <= #locations then
            bufvars[name] = {locations[position + 1].lnum}
          end
        end
        visited[bufnr] = true
      end
    end
  end)

  api.nvim_create_autocmd('InsertLeave', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })

  api.nvim_create_autocmd('InsertEnter', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      api.nvim_create_autocmd('TextChangedI', {
        callback = function()
          if not scrollview.is_sign_group_active(group) then return end
          scrollview.refresh()
        end,
        once = true
      })
    end
  })
end

return M
