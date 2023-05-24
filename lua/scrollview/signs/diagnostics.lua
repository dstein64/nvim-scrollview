local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil or vim.diagnostic == nil then
    return
  end

  local group = 'diagnostics'
  local spec_data = {
    [vim.diagnostic.severity.ERROR] = {
      vim.g.scrollview_diagnostics_error_priority,
      vim.g.scrollview_diagnostics_error_symbol,
      'ScrollViewDiagnosticsError'
    },
    [vim.diagnostic.severity.HINT] = {
      vim.g.scrollview_diagnostics_hint_priority,
      vim.g.scrollview_diagnostics_hint_symbol,
      'ScrollViewDiagnosticsHint'
    },
    [vim.diagnostic.severity.INFO] = {
      vim.g.scrollview_diagnostics_info_priority,
      vim.g.scrollview_diagnostics_info_symbol,
      'ScrollViewDiagnosticsInfo'
    },
    [vim.diagnostic.severity.WARN] = {
      vim.g.scrollview_diagnostics_warn_priority,
      vim.g.scrollview_diagnostics_warn_symbol,
      'ScrollViewDiagnosticsWarn'
    },
  }
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
    callback = function(args)
      if not scrollview.is_sign_group_active(group) then return end
      for _, winid in ipairs(scrollview.get_ordinary_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        local lookup = {}  -- maps diagnostic type to a list of line numbers
        for severity, _ in pairs(names) do
          lookup[severity] = {}
        end
        local diagnostics = vim.diagnostic.get(bufnr)
        for _, x in ipairs(diagnostics) do
          if lookup[x.severity] ~= nil then
            table.insert(lookup[x.severity], x.lnum + 1)
          end
        end
        for severity, lines in pairs(lookup) do
          local name = names[severity]
          vim.b[args.buf][name] = lines
        end
      end
    end
  })

  api.nvim_create_autocmd('DiagnosticChanged', {
    callback = function(args)
      if not scrollview.is_sign_group_active(group) then return end
      if fn.mode() ~= 'i' or vim.diagnostic.config().update_in_insert then
        -- Refresh scrollbars immediately when update_in_insert is set or the
        -- current mode is not insert mode.
        scrollview.refresh()
      else
        -- Refresh scrollbars once leaving insert mode. Overwrite an existing
        -- autocmd configured to already do this.
        local group = api.nvim_create_augroup('scrollview_diagnostics', {
          clear = true
        })
        api.nvim_create_autocmd('InsertLeave', {
          group = group,
          callback = function(args)
            scrollview.refresh()
          end,
          once = true,
        })
      end
    end
  })
end

return M
