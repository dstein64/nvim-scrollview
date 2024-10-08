local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'latestchange'
  scrollview.register_sign_group(group)
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewLatestChange',
    priority = vim.g.scrollview_latestchange_priority,
    symbol = vim.g.scrollview_latestchange_symbol,
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    -- Track visited buffers, to prevent duplicate computation when multiple
    -- windows are showing the same buffer.
    local visited = {}
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      if not visited[bufnr] then
        local bufvars = vim.b[bufnr]
        -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
        bufvars[name] = {}
        local latestchange = api.nvim_win_call(winid, function()
          return fn.line("'.")
        end)
        if latestchange > 0 then
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars[name] = {latestchange}
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
