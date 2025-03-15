local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'keywords'
  scrollview.register_sign_group(group)
  local keyword_groups = {}
  local registration_lookup = {}  -- maps keyword to registration
  local patterns_lookup = {}  -- maps keyword to patterns
  for _, key in ipairs(vim.fn.eval('keys(g:)')) do
    local keyword_group = key:match('^scrollview_keywords_(.+)_spec$')
    if keyword_group ~= nil then
      local spec = vim.g['scrollview_keywords_' .. keyword_group .. '_spec']
      if type(spec) == 'table' then
        if not vim.tbl_isempty(spec.patterns) then
          table.insert(keyword_groups, keyword_group)
          patterns_lookup[keyword_group] = spec.patterns
          local registration = scrollview.register_sign_spec({
            group = group,
            highlight = spec.highlight,
            priority = spec.priority,
            symbol = spec.symbol,
            variant = keyword_group,
          })
          registration_lookup[keyword_group] = registration
        end
      end
    end
  end
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
        local lines_lookup = {}
        for _, keyword_group in ipairs(keyword_groups) do
          lines_lookup[keyword_group] = {}
        end
        local changedtick = bufvars.changedtick
        local changedtick_cached = bufvars.scrollview_keywords_changedtick_cached
        local cache_hit = changedtick_cached == changedtick
        if cache_hit then
          for _, keyword_group in ipairs(keyword_groups) do
            lines_lookup[keyword_group] =
              bufvars['scrollview_keywords_' .. keyword_group .. '_cached']
          end
        else
          local line_count = api.nvim_buf_line_count(bufnr)
          for line = 1, line_count do
            local str = fn.getbufline(bufnr, line)[1]
            for _, keyword_group in ipairs(keyword_groups) do
              local patterns = patterns_lookup[keyword_group]
              for _, pattern in ipairs(patterns) do
                if string.match(str, pattern) then
                  table.insert(lines_lookup[keyword_group], line)
                  break
                end
              end
            end
          end
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars.scrollview_keywords_changedtick_cached = changedtick
          for _, keyword_group in ipairs(keyword_groups) do
            -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
            bufvars['scrollview_keywords_' .. keyword_group .. '_cached']
              = lines_lookup[keyword_group]
          end
        end
        for _, keyword_group in ipairs(keyword_groups) do
          local registration = registration_lookup[keyword_group]
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars[registration.name] = lines_lookup[keyword_group]
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
end

return M
