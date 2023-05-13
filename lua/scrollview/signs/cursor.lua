local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init()
  if api.nvim_create_autocmd == nil then
    return
  end

  scrollview.register_sign_spec('scrollview_signs_cursor', {
    priority = vim.g.scrollview_signs_cursor_priority,
    symbol = vim.g.scrollview_signs_cursor_symbol,
    highlight = 'ScrollViewSignsCursor',
    current_only = true,
  })

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = scrollview.signs_autocmd_callback(function(args)
      for _, winid in ipairs(scrollview.get_ordinary_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        vim.b[bufnr].scrollview_signs_cursor = {fn.line('.')}
      end
    end)
  })

  api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
    callback = scrollview.signs_autocmd_callback(function(args)
      local lines = vim.b.scrollview_signs_cursor
      if lines == nil or lines[1] ~= fn.line('.') then
        scrollview.refresh()
      end
    end)
  })
end

return M
