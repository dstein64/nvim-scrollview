local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'quickfix'
  scrollview.register_sign_group(group)
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewQuickFix',
    priority = vim.g.scrollview_quickfix_priority,
    symbol = vim.g.scrollview_quickfix_symbol,
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
      vim.b[bufnr][name] = nil
    end
    local buflines = {}  -- maps buffers to a list of quickfix lines
    for _, item in ipairs(fn.getqflist()) do
      if buflines[item.bufnr] == nil then
        buflines[item.bufnr] = {}
      end
      table.insert(buflines[item.bufnr], item.lnum)
    end
    for bufnr, lines in pairs(buflines) do
      -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
      vim.b[bufnr][name] = lines
    end
  end)

  -- WARN: QuickFixCmdPost won't fire for some cases where the quickfix list
  -- can be updated (e.g., setqflist).
  api.nvim_create_autocmd('QuickFixCmdPost', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })
end

return M
