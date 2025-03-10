local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'trail'
  scrollview.register_sign_group(group)
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewTrail',
    priority = vim.g.scrollview_trail_priority,
    symbol = vim.g.scrollview_trail_symbol,
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    -- Track visited buffers, to prevent duplicate computation when multiple
    -- windows are showing the same buffer.
    local visited = {}
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      -- Don't update when in insert mode. This way, pressing 'o' to start a
      -- new line won't trigger a new sign when there is indentation.
      local mode = api.nvim_win_call(winid, fn.mode)
      if not visited[bufnr] and mode ~= 'i' then
        local bufvars = vim.b[bufnr]
        local lines = {}
        local changedtick = bufvars.changedtick
        local changedtick_cached = bufvars.scrollview_trail_changedtick_cached
        local cache_hit = changedtick_cached == changedtick
        if cache_hit then
          lines = bufvars.scrollview_trail_cached
        else
          local line_count = api.nvim_buf_line_count(bufnr)
          for line = 1, line_count do
            local str = fn.getbufline(bufnr, line)[1]
            if string.match(str, "%s$") then
              table.insert(lines, line)
            end
          end
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars.scrollview_trail_changedtick_cached = changedtick
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars.scrollview_trail_cached = lines
        end
        -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
        bufvars[name] = lines
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
end

return M
