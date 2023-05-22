local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local registration = scrollview.register_sign_spec({
    current_only = true,
    group = 'cursor',
    highlight = 'ScrollViewCursor',
    priority = vim.g.scrollview_cursor_priority,
    symbol = vim.g.scrollview_cursor_symbol,
  })
  local name = registration.name
  if enable then
    scrollview.set_sign_group_state('cursor', enable)
  end

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = scrollview.signs_autocmd_callback(function(args)
      for _, winid in ipairs(scrollview.get_ordinary_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        vim.b[bufnr][name] = {fn.line('.')}
      end
    end)
  })

  api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
    callback = scrollview.signs_autocmd_callback(function(args)
      local lines = vim.b[name]
      if lines == nil or lines[1] ~= fn.line('.') then
        scrollview.refresh()
      end
    end)
  })
end

return M
