local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')
local to_bool = utils.to_bool

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'search'
  scrollview.register_sign_group(group)
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewSearch',
    priority = vim.g.scrollview_search_priority,
    symbol = vim.g.scrollview_search_symbol,
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    local pattern = fn.getreg('/')
    -- Track visited buffers, to prevent duplicate computation when multiple
    -- windows are showing the same buffer.
    local visited = {}
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      if not visited[bufnr] then
        local bufvars = vim.b[bufnr]
        local lines = {}
        if to_bool(vim.v.hlsearch) then
          local cache_hit = false
          local changedtick = bufvars.changedtick
          if bufvars.scrollview_search_pattern_cached == pattern then
            local changedtick_cached =
              bufvars.scrollview_search_changedtick_cached
            cache_hit = changedtick_cached == changedtick
          end
          if cache_hit then
            lines = bufvars.scrollview_search_cached
          else
            lines = scrollview.with_win_workspace(winid, function()
              local result = {}
              -- Use a pcall since searchcount() and :global throw an
              -- exception (E383, E866) when the pattern is invalid (e.g.,
              -- "\@a").
              pcall(function()
                -- searchcount() can return {} (e.g., when launching Neovim
                -- with -i NONE).
                local searchcount_total = fn.searchcount().total or 0
                if searchcount_total > 0 then
                  result = fn.split(
                    fn.execute('keepjumps global//echo line(".")'))
                end
              end)
              return result
            end)
            for idx, line in ipairs(lines) do
              lines[idx] = tonumber(line)
            end
            -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
            bufvars.scrollview_search_pattern_cached = pattern
            -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
            bufvars.scrollview_search_changedtick_cached = changedtick
            -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
            bufvars.scrollview_search_cached = lines
          end
        end
        -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
        bufvars[name] = lines
        -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
        bufvars.scrollview_search_pattern = pattern
        visited[bufnr] = true
      end
    end
  end)

  api.nvim_create_autocmd('OptionSet', {
    pattern = 'hlsearch',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })

  api.nvim_create_autocmd('CmdlineLeave', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      if to_bool(vim.v.event.abort) then
        return
      end
      local afile = fn.expand('<afile>')
      -- Handle the case where a search is executed.
      local refresh = afile == '/' or afile == '?'
      -- Handle the case where :nohls may have been executed (this won't work
      -- for e.g., <cmd>nohls<cr> in a mapping).
      -- WARN: CmdlineLeave is not executed for command mappings (<cmd>).
      -- WARN: CmdlineLeave is not executed for commands executed from Lua
      -- (e.g., vim.cmd('help')).
      if afile == ':' and string.find(fn.getcmdline(), 'nohls') then
        refresh = true
      end
      if refresh then
        scrollview.refresh()
      end
    end
  })

  -- It's possible that <cmd>nohlsearch<cr> was executed from a mapping, and
  -- wouldn't be handled by the CmdlineLeave callback above. Use a CursorMoved
  -- event to check if search signs are shown when they shouldn't be, and
  -- update accordingly. Also handle the case where 'n', 'N', '*', '#', 'g*',
  -- or 'g#' are pressed (although these won't be properly handled when there
  -- is only one search result and the cursor is already on it, since the
  -- cursor wouldn't move; creating scrollview refresh mappings for those keys
  -- could handle that scenario). NOTE: If there are scenarios where search
  -- signs become out of sync (i.e., shown when they shouldn't be), this same
  -- approach could be used with a timer.
  api.nvim_create_autocmd('CursorMoved', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      -- Use defer_fn since vim.v.hlsearch may not have been properly set yet.
      vim.defer_fn(function()
        local refresh = false
        if to_bool(vim.v.hlsearch) then
          -- Refresh bars if (1) v:hlsearch is on, (2) search signs aren't
          -- currently shown, and (3) searchcount().total > 0. Also refresh
          -- bars if v:hlsearch is on and the shown search signs correspond to
          -- a different pattern than the current one.
          -- Track visited buffers, to prevent duplicate computation when
          -- multiple windows are showing the same buffer.
          local pattern = fn.getreg('/')
          local visited = {}
          for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
            local bufnr = api.nvim_win_get_buf(winid)
            if not visited[bufnr] then
              visited[bufnr] = true
              refresh = api.nvim_win_call(winid, function()
                if pattern ~= vim.b.scrollview_search_pattern then
                  return true
                end
                local lines = vim.b[name]
                if lines == nil or vim.tbl_isempty(lines) then
                  -- Use a pcall since searchcount() throws an exception (E383,
                  -- E866) when the pattern is invalid (e.g., "\@a").
                  local searchcount_total = 0
                  pcall(function()
                    -- searchcount() can return {} (e.g., when launching Neovim
                    -- with -i NONE).
                    searchcount_total = fn.searchcount().total or 0
                  end)
                  if searchcount_total > 0 then
                    return true
                  end
                end
                return false
              end)
              if refresh then
                break
              end
            end
          end
        else
          -- Refresh bars if v:hlsearch is off and search signs are currently
          -- shown.
          for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
            local bufnr = api.nvim_win_get_buf(winid)
            local lines = vim.b[bufnr][name]
            if lines ~= nil and not vim.tbl_isempty(lines) then
              refresh = true
              break
            end
          end
        end
        if refresh then
          scrollview.refresh()
        end
      end, 0)
    end
  })

  -- The InsertEnter case handles when insert mode is entered at the same time
  -- as v:hlsearch is turned off. The InsertLeave case updates search signs
  -- after leaving insert mode, when newly added text might correspond to new
  -- signs.
  api.nvim_create_autocmd({'InsertEnter', 'InsertLeave'}, {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      scrollview.refresh()
    end
  })
end

return M
