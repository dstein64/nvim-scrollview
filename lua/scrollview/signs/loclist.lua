local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'loclist'
  scrollview.register_sign_group(group)
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewLocList',
    priority = vim.g.scrollview_loclist_priority,
    symbol = vim.g.scrollview_loclist_symbol,
    type = 'w',
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    local winlines = {}  -- maps winids to a list of loclist lines
    local sign_winids = scrollview.get_sign_eligible_windows()
    for _, winid in ipairs(sign_winids) do
      -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
      vim.w[winid][name] = nil
    end
    for _, winid in ipairs(sign_winids) do
      local bufnr = api.nvim_win_get_buf(winid)
      for _, item in ipairs(fn.getloclist(winid)) do
        if item.bufnr == bufnr then
          if winlines[winid] == nil then
            winlines[winid] = {}
          end
          table.insert(winlines[winid], item.lnum)
        end
      end
    end
    for winid, lines in pairs(winlines) do
      -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
      vim.w[winid][name] = lines
    end
  end)

  -- WARN: QuickFixCmdPost won't fire for some cases where loclist can be
  -- updated (e.g., setloclist).
  api.nvim_create_autocmd('QuickFixCmdPost', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })
end

return M
