local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init()
  if api.nvim_create_autocmd == nil or vim.diagnostic == nil then
    return
  end

  local spec_data = {
    [vim.diagnostic.severity.ERROR] =
    {'scrollview_signs_diagnostics_error', 60, 'E', 'ScrollViewSignsDiagnosticsError'},
    [vim.diagnostic.severity.HINT] =
    {'scrollview_sigsn_diagnostics_hint', 30, 'H', 'ScrollViewSignsDiagnosticsHint'},
    [vim.diagnostic.severity.INFO] =
    {'scrollview_signs_diagnostics_info', 40, 'I', 'ScrollViewSignsDiagnosticsInfo'},
    [vim.diagnostic.severity.WARN] =
    {'scrollview_signs_diagnostics_warn', 50, 'W', 'ScrollViewSignsDiagnosticsWarn'},
  }
  for _, item in pairs(spec_data) do
    local name, priority, symbol, highlight = unpack(item)
    scrollview.register_sign_spec(name, {
      priority = priority,
      symbol = symbol,
      highlight = highlight,
    })
  end

  api.nvim_create_autocmd('DiagnosticChanged', {
    callback = function(args)
      local names = {
        [vim.diagnostic.severity.ERROR] = 'scrollview_signs_diagnostics_error',
        [vim.diagnostic.severity.HINT] = 'scrollview_sigsn_diagnostics_hint',
        [vim.diagnostic.severity.INFO] = 'scrollview_signs_diagnostics_info',
        [vim.diagnostic.severity.WARN] = 'scrollview_signs_diagnostics_warn',
      }
      local bufs = {[args.buf] = true}
      for _, x in ipairs(args.data.diagnostics) do
        bufs[x.bufnr] = true
      end
      local lookup = {}  -- maps diagnostic type to a list of line numbers
      for severity, _ in pairs(names) do
        lookup[severity] = {}
      end
      for bufnr, _ in pairs(bufs) do
        local diagnostics = vim.diagnostic.get(bufnr)
        for _, x in ipairs(diagnostics) do
          if lookup[x.severity] ~= nil then
            table.insert(lookup[x.severity], x.lnum + 1)
          end
        end
      end
      for severity, lines in pairs(lookup) do
        local name = names[severity]
        vim.b[args.buf][name] = lines
      end
      if fn.mode() ~= 'i' or vim.diagnostic.config().update_in_insert then
        -- Refresh scrollbars immediately when update_in_insert is set or the
        -- current mode is not insert mode.
        scrollview.refresh()
      else
        -- Refresh scrollbars once leaving insert mode. Overwrite an existing
        -- autocmd configured to already do this.
        local group = api.nvim_create_augroup('scrollview_diagnostic_signs', {
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
    end,
  })
end

return M
