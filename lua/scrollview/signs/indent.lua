local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')

local M = {}

local SPACES = 0
local TABS = 1

local should_show = function(option, expandtab)
  if option == 'always' then
    return true
  elseif option == 'never' then
    return false
  elseif option == 'expandtab' then
    return expandtab
  elseif option == 'noexpandtab' then
    return not expandtab
  else
    -- Unknown option. Don't show.
    return false
  end
end

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'indent'
  scrollview.register_sign_group(group)
  local names = {
    [SPACES] = scrollview.register_sign_spec({
      group = group,
      highlight = 'ScrollViewIndentSpaces',
      priority = vim.g.scrollview_indent_spaces_priority,
      symbol = vim.g.scrollview_indent_spaces_symbol,
      variant = 'spaces',
    }).name,
    [TABS] = scrollview.register_sign_spec({
      group = group,
      highlight = 'ScrollViewIndentTabs',
      priority = vim.g.scrollview_indent_tabs_priority,
      symbol = vim.g.scrollview_indent_tabs_symbol,
      variant = 'tabs',
    }).name,
  }

  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    -- Track visited buffers, to prevent duplicate computation when multiple
    -- windows are showing the same buffer.
    local visited = {}
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      local expandtab = api.nvim_buf_get_option(bufnr, 'expandtab')
      if not visited[bufnr] then
        local bufvars = vim.b[bufnr]
        local lines = {
          [SPACES] = {},
          [TABS] = {},
        }
        local changedtick = bufvars.changedtick
        local changedtick_cached = bufvars.scrollview_indent_changedtick_cached
        local spaces_condition_cached =
          bufvars.scrollview_indent_spaces_condition_cached
        local tabs_condition_cached =
          bufvars.scrollview_indent_tabs_condition_cached
        local expandtab_cached =
          bufvars.scrollview_indent_expandtab_option_cached
        local cache_hit = changedtick_cached == changedtick
          and expandtab_cached == expandtab
          and spaces_condition_cached == vim.g.scrollview_indent_spaces_condition
          and tabs_condition_cached == vim.g.scrollview_indent_tabs_condition
        if cache_hit then
          lines[SPACES] = bufvars.scrollview_indent_spaces_cached
          lines[TABS] = bufvars.scrollview_indent_tabs_cached
        else
          local line_count = api.nvim_buf_line_count(bufnr)
          local show_spaces_signs =
            should_show(vim.g.scrollview_indent_spaces_condition, expandtab)
          local show_tabs_signs =
            should_show(vim.g.scrollview_indent_tabs_condition, expandtab)
          for line = 1, line_count do
            local str = fn.getbufline(bufnr, line)[1]
            local sub = string.sub(str, 1, 1)
            if sub == ' ' then
              if show_spaces_signs then
                table.insert(lines[SPACES], line)
              end
            elseif sub == '\t' then
              if show_tabs_signs then
                table.insert(lines[TABS], line)
              end
            end
          end
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars.scrollview_indent_expandtab_option_cached = expandtab
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars.scrollview_indent_spaces_condition_cached =
            vim.g.scrollview_indent_spaces_condition
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          bufvars.scrollview_indent_tabs_condition_cached =
            vim.g.scrollview_indent_tabs_condition
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars.scrollview_indent_changedtick_cached = changedtick
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars.scrollview_indent_spaces_cached = lines[SPACES]
          -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
          bufvars.scrollview_indent_tabs_cached = lines[TABS]
        end
        -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
        bufvars[names[SPACES]] = lines[SPACES]
        bufvars[names[TABS]] = lines[TABS]
        visited[bufnr] = true
      end
    end
  end)

  api.nvim_create_autocmd('TextChangedI', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      local bufnr = api.nvim_get_current_buf()
      local expandtab = api.nvim_buf_get_option(bufnr, 'expandtab')
      local line = fn.line('.')
      local str = fn.getbufline(bufnr, line)[1]
      local sub = string.sub(str, 1, 1)
      for _, mode in ipairs({SPACES, TABS}) do
        local expect_sign = false
        if mode == SPACES then
          local show_signs =
            should_show(vim.g.scrollview_indent_spaces_condition, expandtab)
          expect_sign = sub == ' ' and show_signs
        elseif mode == TABS then
          local show_tabs =
            should_show(vim.g.scrollview_indent_tabs_condition, expandtab)
          expect_sign = sub == '\t' and show_tabs
        else
          error('Unknown mode: ' .. mode)
        end
        local lines = vim.b[bufnr][names[mode]]
        local idx = -1
        if lines ~= nil then
          idx = utils.binary_search(lines, line)
          if lines[idx] ~= line then
            idx = -1
          end
        end
        local has_sign = idx ~= -1
        if expect_sign ~= has_sign then
          scrollview.refresh()
          break
        end
      end
    end
  })

  api.nvim_create_autocmd('OptionSet', {
    pattern = 'expandtab',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      if vim.g.scrollview_indent_spaces_condition == 'expandtab'
          or vim.g.scrollview_indent_spaces_condition == 'noexpandtab'
          or vim.g.scrollview_indent_tabs_condition == 'expandtab'
          or vim.g.scrollview_indent_tabs_condition == 'noexpandtab' then
        scrollview.refresh()
      end
    end
  })
end

return M
