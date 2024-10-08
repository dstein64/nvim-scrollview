local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'cursor'
  scrollview.register_sign_group(group)
  local registration = scrollview.register_sign_spec({
    current_only = true,
    group = group,
    highlight = 'ScrollViewCursor',
    priority = vim.g.scrollview_cursor_priority,
    show_in_folds = true,
    symbol = vim.g.scrollview_cursor_symbol,
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
      vim.b[bufnr][name] = {fn.line('.')}
    end
  end)

  api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      local lines = vim.b[name]
      if lines == nil or lines[1] ~= fn.line('.') then
        scrollview.refresh()
      end
    end
  })
end

return M
