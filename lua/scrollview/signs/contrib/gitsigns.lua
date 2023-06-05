-- Requirements:
--  - gitsigns.nvim (https://github.com/lewis6991/gitsigns.nvim)
-- Usage:
--   require('scrollview.signs.contrib.gitsigns').setup([{config}])
--     {config} is an optional table with the following attributes:
--       - enabled (boolean): Whether signs are enabled immediately. If false,
--         use ':ScrollViewEnable gitsigns' to enable later. Defaults to true.
--       - hide_full_add (boolean): Whether to hide signs for a hunk if the
--         hunk lines cover the entire buffer. Defaults to true.
--       - highlight_add (string): Defaults to a value from gitsigns config
--         when available, otherwise 'DiffAdd'.
--       - highlight_change (string): Defaults to a value from gitsigns config
--         when available, otherwise 'DiffChange'.
--       - highlight_delete (string): Defaults to a value from gitsigns config
--         when available, otherwise 'DiffDelete'.
--       - only_first_line: Whether a sign is shown only for the first line of
--         each hunk. Defaults to false.
--       - symbol_add (string): Defaults to a value from gitsigns config when
--         available, otherwise box drawing heavy vertical.
--       - symbol_change (string): Defaults to a value from gitsigns config
--         when available, otherwise box drawing heavy vertical.
--       - symbol_delete (string): Defaults to a value from gitsigns config
--         when available, otherwise lower one-eigth block.
--     The setup() function should be called after gitsigns.setup().

local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

-- Create a shallow copy of a map-like table.
local copy = function(table)
  local result = {}
  for key, val in pairs(table) do
    result[key] = val
  end
  return result
end

function M.setup(config)
  config = config or {}
  config = copy(config)  -- create a copy, since this is modified

  local defaults = {
    enabled = true,
    hide_full_add = true,
    only_first_line = false,
  }

  -- Try setting highlight and symbol defaults from gitsigns config.
  pcall(function()
    local signs = require('gitsigns.config').config.signs
    defaults.highlight_add = signs.add.hl
    defaults.highlight_change = signs.change.hl
    defaults.highlight_delete = signs.delete.hl
    defaults.symbol_add = signs.add.text
    defaults.symbol_change = signs.change.text
    defaults.symbol_delete = signs.delete.text
  end)

  -- Try setting highlight and symbol defaults from gitsigns defaults.
  pcall(function()
    local default = require('gitsigns.config').schema.signs.default
    defaults.highlight_add = defaults.highlight_add or default.add.hl
    defaults.highlight_change = defaults.highlight_change or default.change.hl
    defaults.highlight_delete = defaults.highlight_delete or default.delete.hl
    defaults.symbol_add = defaults.symbol_add or default.add.text
    defaults.symbol_change = defaults.symbol_change or default.change.text
    defaults.symbol_delete = defaults.symbol_delete or default.delete.text
  end)

  -- Try setting highlight and symbol defaults from fixed values.
  defaults.highlight_add = defaults.highlight_add or 'DiffAdd'
  defaults.highlight_change = defaults.highlight_change or 'DiffChange'
  defaults.highlight_delete = defaults.highlight_delete or 'DiffDelete'
  defaults.symbol_add = defaults.symbol_add or fn.nr2char(0x2503)
  defaults.symbol_change = defaults.symbol_change or fn.nr2char(0x2503)
  defaults.symbol_delete = defaults.symbol_delete or fn.nr2char(0x2581)

  -- Set missing config values with defaults.
  if config.enabled == nil then
    config.enabled = defaults.enabled
  end
  if config.hide_full_add == nil then
    config.hide_full_add = defaults.hide_full_add
  end
  config.highlight_add = config.highlight_add or defaults.highlight_add
  config.highlight_change = config.highlight_change or defaults.highlight_change
  config.highlight_delete = config.highlight_delete or defaults.highlight_delete
  if config.only_first_line == nil then
    config.only_first_line = defaults.only_first_line
  end
  config.symbol_add = config.symbol_add or defaults.symbol_add
  config.symbol_change = config.symbol_change or defaults.symbol_change
  config.symbol_delete = config.symbol_delete or defaults.symbol_delete

  local group = 'gitsigns'

  local add = scrollview.register_sign_spec({
    group = group,
    highlight = config.highlight_add,
    symbol = config.symbol_add,
  }).name

  local change = scrollview.register_sign_spec({
    group = group,
    highlight = config.highlight_change,
    symbol = config.symbol_change,
  }).name

  local delete = scrollview.register_sign_spec({
    group = group,
    highlight = config.highlight_delete,
    symbol = config.symbol_delete,
  }).name

  scrollview.set_sign_group_state(group, config.enabled)

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
      for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        local hunks = gitsigns.get_hunks(bufnr) or {}
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
            local first = hunk.added.start
            local last = hunk.added.start
            if not config.only_first_line then
              last = last + hunk.added.count - 1
            end
            for line = first, last do
              table.insert(lines_change, line)
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
      -- Checking whether the sign group is active is deferred to here so that
      -- the proper gitsigns state is maintained even when the sign group is
      -- inactive. This way, signs will be properly set when the sign group is
      -- enabled.
      if not scrollview.is_sign_group_active(group) then return end
      vim.cmd('silent! ScrollViewRefresh')
    end
  })
end

return M
