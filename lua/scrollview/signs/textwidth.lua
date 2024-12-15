local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'textwidth'
  scrollview.register_sign_group(group)
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewTextWidth',
    priority = vim.g.scrollview_textwidth_priority,
    symbol = vim.g.scrollview_textwidth_symbol,
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    -- Track visited buffers, to prevent duplicate computation when multiple
    -- windows are showing the same buffer.
    local visited = {}
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      local textwidth = api.nvim_buf_get_option(bufnr, 'textwidth')
      if not visited[bufnr] then
        local bufvars = vim.b[bufnr]
        local lines = {}
        local cache_hit = false
        local changedtick = bufvars.changedtick
        if bufvars.scrollview_textwidth_option_cached == textwidth then
          local changedtick_cached =
            bufvars.scrollview_textwidth_changedtick_cached
          cache_hit = changedtick_cached == changedtick
        end
        if cache_hit then
          lines = bufvars.scrollview_textwidth_cached
        else
          local line_count = api.nvim_buf_line_count(bufnr)
          if textwidth > 0 then
            api.nvim_win_call(winid, function()
              for line = 1, line_count do
                local str = fn.getbufline(bufnr, line)[1]
                local line_length = fn.strchars(str, 1)
                if line_length > textwidth then
                  table.insert(lines, line)
                end
              end
            end)
          end
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars.scrollview_textwidth_option_cached = textwidth
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars.scrollview_textwidth_changedtick_cached = changedtick
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars.scrollview_textwidth_cached = lines
        end
        -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
        bufvars[name] = lines
        visited[bufnr] = true
      end
    end
  end)

  api.nvim_create_autocmd('OptionSet', {
    pattern = 'textwidth',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })

  api.nvim_create_autocmd('TextChangedI', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      local bufnr = api.nvim_get_current_buf()
      local textwidth = api.nvim_buf_get_option(bufnr, 'textwidth')
      local line = fn.line('.')
      local str = fn.getbufline(bufnr, line)[1]
      local line_length = fn.strchars(str, 1)
      local expect_sign = textwidth > 0 and line_length > textwidth
      local idx = -1
      local lines = vim.b[bufnr][name]
      if lines ~= nil then
        idx = utils.binary_search(lines, line)
        if lines[idx] ~= line then
          idx = -1
        end
      end
      local has_sign = idx ~= -1
      if expect_sign ~= has_sign then
        scrollview.refresh()
      end
    end
  })
end

return M
