-- Requirements:
--  - gitsigns.nvim (https://github.com/lewis6991/gitsigns.nvim)
-- Usage:
--   require('scrollview.contrib.gitsigns').setup([{config}])
--     {config} is an optional table with the following attributes:
--       - add_highlight (string): Defaults to a value from gitsigns config
--         when available, otherwise 'DiffAdd'.
--       - add_priority (number): Defaults to 90.
--       - add_symbol (string): Defaults to a value from gitsigns config when
--         available, otherwise box drawing heavy vertical.
--       - change_highlight (string): Defaults to a value from gitsigns config
--         when available, otherwise 'DiffChange'.
--       - change_priority (number): Defaults to 90.
--       - change_symbol (string): Defaults to a value from gitsigns config
--         when available, otherwise box drawing heavy vertical.
--       - delete_highlight (string): Defaults to a value from gitsigns config
--         when available, otherwise 'DiffDelete'.
--       - delete_priority (number): Defaults to 90.
--       - delete_symbol (string): Defaults to a value from gitsigns config
--         when available, otherwise lower one-eigth block.
--       - enabled (boolean): Whether signs are enabled immediately. If false,
--         use ':ScrollViewEnable gitsigns' to enable later. Defaults to true.
--       - hide_full_add (boolean): Whether to hide signs for a hunk if the
--         hunk lines cover the entire buffer. Defaults to true.
--       - only_first_line: Whether a sign is shown only for the first line of
--         each hunk. Defaults to false.
--     The setup() function should be called after gitsigns.setup().

local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')
local copy = utils.copy
local to_bool = utils.to_bool

local M = {}

function M.setup(config)
  config = config or {}
  config = copy(config)  -- create a copy, since this is modified

  local defaults = {
    enabled = true,
    hide_full_add = true,
    only_first_line = false,
    add_priority = 90,
    change_priority = 90,
    delete_priority = 90,
  }

  -- Try setting highlight and symbol defaults from gitsigns config.
  pcall(function()
    local signs = require('gitsigns.config').config.signs
    defaults.add_highlight = signs.add.hl
    defaults.change_highlight = signs.change.hl
    defaults.delete_highlight = signs.delete.hl
    defaults.add_symbol = signs.add.text
    defaults.change_symbol = signs.change.text
    defaults.delete_symbol = signs.delete.text
  end)

  -- Try setting highlight and symbol defaults from gitsigns defaults.
  pcall(function()
    local default = require('gitsigns.config').schema.signs.default
    defaults.add_highlight = defaults.add_highlight or default.add.hl
    defaults.change_highlight = defaults.change_highlight or default.change.hl
    defaults.delete_highlight = defaults.delete_highlight or default.delete.hl
    defaults.add_symbol = defaults.add_symbol or default.add.text
    defaults.change_symbol = defaults.change_symbol or default.change.text
    defaults.delete_symbol = defaults.delete_symbol or default.delete.text
  end)

  -- Try setting highlight and symbol defaults from fixed values.
  defaults.add_highlight = defaults.add_highlight or 'DiffAdd'
  defaults.change_highlight = defaults.change_highlight or 'DiffChange'
  defaults.delete_highlight = defaults.delete_highlight or 'DiffDelete'
  defaults.add_symbol = defaults.add_symbol or fn.nr2char(0x2503)
  defaults.change_symbol = defaults.change_symbol or fn.nr2char(0x2503)
  defaults.delete_symbol = defaults.delete_symbol or fn.nr2char(0x2581)

  -- Set missing config values with defaults.
  for key, val in pairs(defaults) do
    if config[key] == nil then
      config[key] = val
    end
  end

  local group = 'gitsigns'
  scrollview.register_sign_group(group)

  local add = scrollview.register_sign_spec({
    extend = true,
    group = group,
    highlight = config.add_highlight,
    priority = config.add_priority,
    symbol = config.add_symbol,
    variant = 'add',
  }).name

  local change = scrollview.register_sign_spec({
    extend = true,
    group = group,
    highlight = config.change_highlight,
    priority = config.change_priority,
    symbol = config.change_symbol,
    variant = 'change',
  }).name

  local delete = scrollview.register_sign_spec({
    extend = true,
    group = group,
    highlight = config.delete_highlight,
    priority = config.delete_priority,
    symbol = config.delete_symbol,
    variant = 'delete',
  }).name

  scrollview.set_sign_group_state(group, config.enabled)

  -- The last updated buffers, reset on each GitSignsUpdate. This is a
  -- dictionary used as a set.
  local active_bufnrs = {}

  api.nvim_create_autocmd('User', {
    pattern = 'GitSignsUpdate',
    callback = function()
      -- WARN: Ordinarily, the code that follows would be handled in a
      -- ScrollViewRefresh User autocommand callback, and code here would just
      -- be a call to ScrollViewRefresh. That approach is avoided for better
      -- handling of the 'hide_full_add' scenario that avoids an entire column
      -- being covered (the ScrollViewRefresh User autocommand approach could
      -- result in brief occurrences of full coverage when hide_full_add=true).
      local gitsigns = require('gitsigns')
      -- Clear gitsigns info for existing buffers.
      for bufnr, _ in pairs(active_bufnrs) do
        if to_bool(vim.fn.bufexists(bufnr)) then
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          vim.b[bufnr][add] = {}
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          vim.b[bufnr][change] = {}
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          vim.b[bufnr][delete] = {}
        end
      end
      for _, tabpage in ipairs(api.nvim_list_tabpages()) do
        local tabwins = api.nvim_tabpage_list_wins(tabpage)
        for _, winid in ipairs(tabwins) do
          local bufnr = api.nvim_win_get_buf(winid)
          local hunks = gitsigns.get_hunks(bufnr) or {}
          if not vim.tbl_isempty(hunks) then
            active_bufnrs[bufnr] = true
          end
          local lines_add = {}
          local lines_change = {}
          local lines_delete = {}
          for _, hunk in ipairs(hunks) do
            if hunk.type == 'add' then
              local full = hunk.added.count >= api.nvim_buf_line_count(bufnr)
              if not config.hide_full_add or not full then
                local first = hunk.added.start
                local last = hunk.added.start
                if not config.only_first_line then
                  last = last + hunk.added.count - 1
                end
                for line = first, last do
                  table.insert(lines_add, line)
                end
              end
            elseif hunk.type == 'change' then
              -- WARN: A change hunk can be comprised of a change (the removed
              -- lines) and an add (lines added after the removed lines). #129
              local first = hunk.added.start
              local last = first
              if not config.only_first_line then
                last = last + hunk.added.count - 1
                if hunk.added.count > hunk.removed.count then
                  last = last - (hunk.added.count - hunk.removed.count)
                end
              end
              for line = first, last do
                table.insert(lines_change, line)
              end
              if hunk.added.count > hunk.removed.count then
                first = hunk.added.start + hunk.removed.count
                last = first
                if not config.only_first_line then
                  last = last + hunk.added.count - hunk.removed.count - 1
                end
                for line = first, last do
                  table.insert(lines_add, line)
                end
              end
            elseif hunk.type == 'delete' then
              table.insert(lines_delete, hunk.added.start)
            end
          end
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          vim.b[bufnr][add] = lines_add
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          vim.b[bufnr][change] = lines_change
          -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
          vim.b[bufnr][delete] = lines_delete
        end
      end
      -- Checking whether the sign group is active is deferred to here so that
      -- the proper gitsigns state is maintained even when the sign group is
      -- inactive. This way, signs will be properly set when the sign group is
      -- enabled.
      if not scrollview.is_sign_group_active(group) then return end
      vim.cmd('silent! ScrollViewRefresh')
    end
  })

  -- Refresh gitsigns to trigger GitSignsUpdate (otherwise existing signs
  -- from gitsigns wouldn't be reflected on the scrollbar until the next
  -- GitSignsUpdate).
  pcall(function()
    require('gitsigns').refresh()
  end)
end

return M
