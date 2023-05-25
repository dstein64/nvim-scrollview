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
      vim.w[winid].scrollview_spell_changedtick_cached = nil
    end
  end

  -- Create mappings to invalidate cache and refresh scrollbars after certain
  -- spell key sequences.
  local seqs = {'zg', 'zG', 'zq', 'zW', 'zuw', 'zug', 'zuW', 'zuG'}
  for _, seq in ipairs(seqs) do
    if fn.maparg(seq) == '' then
      vim.keymap.set({'n', 'x'}, seq, function()
        invalidate_cache()
        vim.cmd('ScrollViewRefresh')  -- asynchronous
        return seq
      end, {
        noremap = true,
        unique = true,
        expr = true,
      })
    end
  end

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = function(args)
      if not scrollview.is_sign_group_active(group) then return end
      for _, winid in ipairs(scrollview.get_ordinary_windows()) do
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
            winvars.scrollview_spell_changedtick_cached = changedtick
            winvars.scrollview_spell_bufnr_cached = bufnr
            winvars.scrollview_spell_cached = lines
          end
        end
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
    callback = function(args)
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
      --   :[count]spellr[are]
      --   :spellr[are]!
      --   :[count]spellu[ndo]
      --   :spellu[ndo]!
      -- WARN: [count] is not handled.
      -- WARN: Only text at the beginning of the command is considered.
      -- WARN: CmdlineLeave is not executed for command mappings (<cmd>).
      local cmdline = fn.getcmdline()
      if vim.startswith(cmdline, 'spe') then
        invalidate_cache()
        scrollview.refresh()
      end
    end
  })
end

return M
