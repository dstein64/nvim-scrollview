local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'trail'
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewTrail',
    priority = vim.g.scrollview_trail_priority,
    symbol = vim.g.scrollview_trail_symbol,
    type = 'w',
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
        local winvars = vim.w[winid]
        -- Don't update when in insert mode. This way, pressing 'o' to start a
        -- new line won't trigger a new sign when there is indentation.
        local mode = api.nvim_win_call(winid, fn.mode)
        if mode ~= 'i' then
          local lines = {}
          local bufnr = api.nvim_win_get_buf(winid)
          local changedtick = vim.b[bufnr].changedtick
          local list = api.nvim_win_get_option(winid, 'list')
          if list then
            -- Use getwinvar instead of nvim_win_get_option, since that will return
            -- the relevant window-local value (window value if set, global value
            -- otherwise).
            local listchars = vim.split(fn.getwinvar(winid, '&listchars'), ',')
            local trail = false
            for _, x in ipairs(listchars) do
              if vim.startswith(x, 'trail:') then
                trail = true
                break
              end
            end
            if trail then
              local changedtick_cached
                = winvars.scrollview_trail_changedtick_cached
              local bufnr_cached
                = winvars.scrollview_trail_bufnr_cached
              local cache_hit = changedtick_cached == changedtick
                and bufnr_cached == bufnr
              if cache_hit then
                lines = winvars.scrollview_trail_cached
              else
                local line_count = api.nvim_buf_line_count(bufnr)
                for line = 1, line_count do
                  local string = fn.getbufline(bufnr, line)[1]
                  if string.match(string, "%s$") then
                    table.insert(lines, line)
                  end
                end
                -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
                winvars.scrollview_trail_changedtick_cached = changedtick
                -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
                winvars.scrollview_trail_bufnr_cached = bufnr
                -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
                winvars.scrollview_trail_cached = lines
              end
            end
          end
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          winvars[name] = lines
        end
      end
    end
  })

  api.nvim_create_autocmd('InsertLeave', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })

  api.nvim_create_autocmd('OptionSet', {
    pattern = 'list',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })

  api.nvim_create_autocmd('OptionSet', {
    pattern = 'listchars',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })
end

return M
