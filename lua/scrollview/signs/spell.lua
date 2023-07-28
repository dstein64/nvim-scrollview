local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')
local to_bool = utils.to_bool

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil or vim.keymap == nil then
    return
  end

  local group = 'spell'
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewSpell',
    priority = vim.g.scrollview_spell_priority,
    symbol = vim.g.scrollview_spell_symbol,
    type = 'w',
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  local invalidate_cache = function()
    for _, winid in ipairs(api.nvim_list_wins()) do
      -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
      vim.w[winid].scrollview_spell_changedtick_cached = nil
    end
  end

  -- Invalidate cache and refresh scrollbars after certain spell key sequences.
  local seqs = {'zg', 'zG', 'zq', 'zW', 'zuw', 'zug', 'zuW', 'zuG'}
  for _, seq in ipairs(seqs) do
    scrollview.register_key_sequence_callback(seq, 'nv', function()
      invalidate_cache()
      scrollview.refresh()  -- asynchronous
    end)
  end

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        local spell = api.nvim_win_get_option(winid, 'spell')
        local winvars = vim.w[winid]
        local lines = {}
        if spell then
          local changedtick = vim.b[bufnr].changedtick
          local changedtick_cached = winvars.scrollview_spell_changedtick_cached
          local bufnr_cached = winvars.scrollview_spell_bufnr_cached
          local cache_hit = changedtick_cached == changedtick
            and bufnr_cached == bufnr
          if cache_hit then
            lines = winvars.scrollview_spell_cached
          else
            local line_count = api.nvim_buf_line_count(bufnr)
            scrollview.with_win_workspace(winid, function()
              for line = 1, line_count do
                fn.cursor(line, 1)
                local spellbadword = fn.spellbadword()
                if spellbadword[1] ~= '' then table.insert(lines, line) end
              end
            end)
            -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
            winvars.scrollview_spell_changedtick_cached = changedtick
            -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
            winvars.scrollview_spell_bufnr_cached = bufnr
            -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
            winvars.scrollview_spell_cached = lines
          end
        end
        -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
        winvars[name] = lines
      end
    end
  })

  api.nvim_create_autocmd('OptionSet', {
    pattern = {'dictionary', 'spell'},
    callback = function(args)
      if not scrollview.is_sign_group_active(group) then return end
      if args.match == 'dictionary' then
        invalidate_cache()
      end
      scrollview.refresh()
    end
  })

  api.nvim_create_autocmd('CmdlineLeave', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      if to_bool(vim.v.event.abort) then
        return
      end
      if fn.expand('<afile>') ~= ':' then
        return
      end
      -- Invalidate cache and refresh scrollbars after certain spell commands.
      --   :[count]spe[llgood]
      --   :spe[llgood]!
      --   :[count]spellw[rong]
      --   :spellw[rong]!
      --   :[count]spellra[re]
      --   :spellr[are]!
      --   :[count]spellu[ndo]
      --   :spellu[ndo]!
      -- WARN: Only text at the beginning of the command is considered.
      -- WARN: CmdlineLeave is not executed for command mappings (<cmd>).
      -- WARN: CmdlineLeave is not executed for commands executed from Lua
      -- (e.g., vim.cmd('help')).
      local cmdline = fn.getcmdline()
      if string.match(cmdline, '^%d*spe') ~= nil then
        invalidate_cache()
        scrollview.refresh()
      end
    end
  })
end

return M
