local scrollview = require('scrollview')

local group = 'cursor'
local registration = scrollview.register_sign_spec({
  current_only = true,
  group = group,
  highlight = 'SpellCap',
  show_in_folds = true,
})
local name = registration.name
scrollview.set_sign_group_state(group, true)

vim.api.nvim_create_autocmd('User', {
  pattern = 'ScrollViewRefresh',
  callback = function()
    if not scrollview.is_sign_group_active(group) then return end
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = vim.api.nvim_win_get_buf(winid)
      vim.b[bufnr][name] = {vim.fn.line('.')}
    end
  end
})

vim.api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
  callback = function()
    if not scrollview.is_sign_group_active(group) then return end
    local lines = vim.b[name]
    if lines == nil or lines[1] ~= vim.fn.line('.') then
      vim.cmd('ScrollViewRefresh')
    end
  end
})


local M = {}
function M.init(enable)
end

return M
