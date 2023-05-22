local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'spell'
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewSpell',
    priority = 20,
    symbol = '~',
    type = 'w',
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

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
          local seq_cur = fn.undotree().seq_cur
          local cache_seq_cur = winvars.scrollview_spell_seq_cur_cached
          local cache_hit = cache_seq_cur == seq_cur
          -- XXX: Commands like zG invalidate the cache, but that's not
          -- currently handled.
          -- TODO: Add handling.
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
            winvars.scrollview_spell_seq_cur_cached = seq_cur
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
      scrollview.refresh()
    end
  })
end

return M
