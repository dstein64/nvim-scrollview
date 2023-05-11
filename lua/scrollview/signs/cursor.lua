local api = vim.api
local fn = vim.fn

local M = {}

function M.init()
  if api.nvim_create_autocmd == nil then
    return
  end

  require('scrollview').register_sign_spec('scrollview_signs_cursor', {
    priority = 100,
    symbol = fn.nr2char(0x2bc8),  -- a triangle pointing rightward
    highlight = 'ScrollViewSignsCursor',
    current_only = true,
  })

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = function(args)
      for _, winid in ipairs(require('scrollview').get_ordinary_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        vim.b[bufnr].scrollview_signs_cursor = {fn.line('.')}
      end
    end
  })

  api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
    callback = function(args)
      local lines = vim.b.scrollview_signs_cursor
      if lines == nil or lines[1] ~= fn.line('.') then
        require('scrollview').scrollview_refresh()
      end
    end
  })
end

return M
