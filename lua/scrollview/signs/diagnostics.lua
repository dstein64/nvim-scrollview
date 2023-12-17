local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')
local to_bool = utils.to_bool

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil or vim.diagnostic == nil then
    return
  end

  local group = 'diagnostics'
  local spec_data = {}
  for _, severity in ipairs(vim.g.scrollview_diagnostics_severities) do
    local value
    if severity == vim.diagnostic.severity.ERROR then
      value = {
        vim.g.scrollview_diagnostics_error_priority,
        vim.g.scrollview_diagnostics_error_symbol,
        'ScrollViewDiagnosticsError'
      }
    elseif severity == vim.diagnostic.severity.HINT then
      value = {
        vim.g.scrollview_diagnostics_hint_priority,
        vim.g.scrollview_diagnostics_hint_symbol,
        'ScrollViewDiagnosticsHint'
      }
    elseif severity == vim.diagnostic.severity.INFO then
      value = {
        vim.g.scrollview_diagnostics_info_priority,
        vim.g.scrollview_diagnostics_info_symbol,
        'ScrollViewDiagnosticsInfo'
      }
    elseif severity == vim.diagnostic.severity.WARN then
      value = {
        vim.g.scrollview_diagnostics_warn_priority,
        vim.g.scrollview_diagnostics_warn_symbol,
        'ScrollViewDiagnosticsWarn'
      }
    end
    if value ~= nil then
      spec_data[severity] = value
    end
  end
  if vim.tbl_isempty(spec_data) then return end
  local names = {}  -- maps severity to registration name
  for severity, item in pairs(spec_data) do
    local priority, symbol, highlight = unpack(item)
    local registration = scrollview.register_sign_spec({
      group = group,
      highlight = highlight,
      priority = priority,
      symbol = symbol,
    })
    names[severity] = registration.name
  end
  scrollview.set_sign_group_state(group, enable)

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        if vim.diagnostic.is_disabled(bufnr) then
          for _, name in pairs(names) do
            -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
            vim.b[bufnr][name] = {}
          end
        else
          local lookup = {}  -- maps diagnostic type to a list of line numbers
          for severity, _ in pairs(names) do
            lookup[severity] = {}
          end
          local diagnostics = vim.diagnostic.get(bufnr)
          local line_count = vim.api.nvim_buf_line_count(bufnr)
          for _, x in ipairs(diagnostics) do
            if lookup[x.severity] ~= nil then
              -- Diagnostics can be reported for lines beyond the last line in
              -- the buffer. Treat these as if they were reported for the last
              -- line, matching what Neovim does for displaying diagnostic
              -- signs in the sign column.
              local lnum = math.min(x.lnum + 1, line_count)
              table.insert(lookup[x.severity], lnum)
            end
          end
          for severity, lines in pairs(lookup) do
            local name = names[severity]
            -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
            vim.b[bufnr][name] = lines
          end
        end
      end
    end
  })

  api.nvim_create_autocmd('DiagnosticChanged', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      if fn.mode() ~= 'i' or vim.diagnostic.config().update_in_insert then
        -- Refresh scrollbars immediately when update_in_insert is set or the
        -- current mode is not insert mode.
        scrollview.refresh()
      else
        -- Refresh scrollbars once leaving insert mode. Overwrite an existing
        -- autocmd configured to already do this.
        local augroup = api.nvim_create_augroup('scrollview_diagnostics', {
          clear = true
        })
        api.nvim_create_autocmd('InsertLeave', {
          group = augroup,
          callback = function()
            scrollview.refresh()
          end,
          once = true,
        })
      end
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
      -- Refresh scrollbars after the following commands.
      --   vim.diagnostic.enable()
      --   vim.diagnostic.disable()
      -- WARN: CmdlineLeave is not executed for command mappings (<cmd>).
      -- WARN: CmdlineLeave is not executed for commands executed from Lua
      -- (e.g., vim.cmd('help')).
      local cmdline = fn.getcmdline()
      if string.match(cmdline, 'vim%.diagnostic%.enable') ~= nil
          or string.match(cmdline, 'vim%.diagnostic%.disable') ~= nil then
        scrollview.refresh()
      end
    end
  })
end

return M
