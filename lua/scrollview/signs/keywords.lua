local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

local SCOPE_FULL = 0
local SCOPE_COMMENTS = 1
local SCOPE_AUTO = 2

-- Check if the text between idx1 and idx2 from the specified line is in a
-- comment, using Treesitter.
local check_in_comment_ts = function(bufnr, line, idx1, idx2)
  local got_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not got_parser or not parser then return nil end
  local trees = parser:trees()
  if #trees == 0 then return nil end
  for _, tree in ipairs(trees) do
    local root = tree:root()
    local node = root:named_descendant_for_range(
      line - 1, idx1 - 1, line - 1, idx2 - 1)
    while node ~= nil do
      if node:type() == 'comment' then
        return true
      end
      node = node:parent()
    end
  end
  return false
end

-- Escape the pattern characters in a string.
local escape = function(str)
  return str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

-- Check if the substring sub is in a commment in str, using 'commentstring'.
local check_in_comment_cs = function(commentstring, str, sub)
  if not string.find(commentstring, '%%s') then
    return nil
  end
  commentstring = commentstring:gsub('%s+', '')  -- remove whitespace
  commentstring = escape(commentstring)
  local pattern = commentstring:gsub('%%%%s', '.*' .. escape(sub) .. '.*', 1)
  return string.find(str, pattern) ~= nil
end

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'keywords'
  scrollview.register_sign_group(group)
  local keyword_groups = {}
  local registration_lookup = {}  -- maps keyword to registration
  local patterns_lookup = {}  -- maps keyword to patterns
  local scope_lookup = {}  -- maps keyword to scope
  for _, key in ipairs(vim.fn.eval('keys(g:)')) do
    local keyword_group = key:match('^scrollview_keywords_(.+)_spec$')
    if keyword_group ~= nil then
      local spec = vim.g['scrollview_keywords_' .. keyword_group .. '_spec']
      if type(spec) == 'table' then
        if not vim.tbl_isempty(spec.patterns) then
          local scope = SCOPE_AUTO
          if spec.scope ~= nil then
            scope = ({
              full = SCOPE_FULL,
              auto = SCOPE_AUTO,
              comments = SCOPE_COMMENTS,
            })[spec.scope]
          end
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
          scope_lookup[keyword_group] = scope
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
      local commentstring = api.nvim_buf_get_option(bufnr, 'commentstring')
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
        local commentstring_cached = bufvars.scrollview_keywords_commentstring_cached
        local cache_hit = changedtick_cached == changedtick
          and commentstring_cached == commentstring
        if cache_hit then
          for _, keyword_group in ipairs(keyword_groups) do
            lines_lookup[keyword_group] =
              bufvars['scrollview_keywords_group_' .. keyword_group .. '_cached']
          end
        else
          local line_count = api.nvim_buf_line_count(bufnr)
          for line = 1, line_count do
            local str = fn.getbufline(bufnr, line)[1]
            for _, keyword_group in ipairs(keyword_groups) do
              local scope = scope_lookup[keyword_group]
              local patterns = patterns_lookup[keyword_group]
              for _, pattern in ipairs(patterns) do
                local start = 1
                while true do
                  local idx1, idx2 = string.find(str, pattern, start)
                  if not idx1 then break end
                  local match = false
                  if scope == SCOPE_FULL then
                    match = true
                  else
                    local in_comment_ts = check_in_comment_ts(
                      bufnr, line, idx1, idx2)
                    if in_comment_ts then
                      match = true
                    else
                      local in_comment_cs = check_in_comment_cs(
                        commentstring, str, string.sub(str, idx1, idx2))
                      if in_comment_cs then
                        match = true
                      else
                        -- The string wasn't found in a comment using
                        -- Treesitter nor 'commentstring'.
                        if scope == SCOPE_AUTO then
                          match = in_comment_ts == nil and in_comment_cs == nil
                        elseif scope == SCOPE_COMMENTS then
                          match = false
                        else
                          error('Unknown scope: ' .. scope)
                        end
                      end
                    end
                  end
                  if match then
                    table.insert(lines_lookup[keyword_group], line)
                    break
                  end
                  start = idx2 + 1
                end
              end
            end
          end
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars.scrollview_keywords_changedtick_cached = changedtick
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars.scrollview_keywords_commentstring_cached = commentstring
          for _, keyword_group in ipairs(keyword_groups) do
            -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
            bufvars['scrollview_keywords_group_' .. keyword_group .. '_cached']
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

  api.nvim_create_autocmd('OptionSet', {
    pattern = 'commentstring',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })
end

return M
