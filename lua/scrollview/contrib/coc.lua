-- Requirements:
--  - coc.nvim (https://github.com/neoclide/coc.nvim)
-- Usage:
--   require('scrollview.contrib.coc').setup([{config}])
--     {config} is an optional table with the following attributes:
--       - enabled (boolean): Whether signs are enabled immediately. If false,
--         use ':ScrollViewEnable coc' to enable later. Defaults to true.
--       - error_highlight (string): Defaults to 'CocErrorSign'.
--       - error_priority (number): Defaults to 60.
--       - error_symbol (string): Defaults to 'E'.
--       - hint_highlight (string): Defaults to 'CocHintSign'.
--       - hint_priority (number): Defaults to 30.
--       - hint_symbol (string): Defaults to 'H'.
--       - info_highlight (string): Defaults to 'CocInfoSign'.
--       - info_priority (number): Defaults to 40.
--       - info_symbol (string): Defaults to 'I'.
--       - warn_highlight (string): Defaults to 'CocWarningSign'.
--       - warn_priority (number): Defaults to 50.
--       - warn_symbol (string): Defaults to 'W'.
--       - severities (string[]): A list of severities for which diagnostic
--         signs will be shown. Defaults to {'error', 'hint', 'info', 'warn'}.

local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')
local copy = utils.copy
local to_bool = utils.to_bool

local M = {}

function M.setup(config)
  if api.nvim_create_autocmd == nil then
    return
  end

  config = config or {}
  config = copy(config)  -- create a copy, since this is modified

  local defaults = {
    enabled = true,
    error_highlight = 'CocErrorSign',
    error_priority = 60,
    error_symbol = 'E',
    hint_highlight = 'CocHintSign',
    hint_priority = 30,
    hint_symbol = 'H',
    info_highlight = 'CocInfoSign',
    info_priority = 40,
    info_symbol = 'I',
    warn_highlight = 'CocWarningSign',
    warn_priority = 50,
    warn_symbol = 'W',
    severities = {'error', 'hint', 'info', 'warn'},
  }

  for key, val in pairs(defaults) do
    if config[key] == nil then
      config[key] = val
    end
  end

  local group = 'coc'
  scrollview.register_sign_group(group)

  local spec_data = {}
  for _, severity in ipairs(config.severities) do
    local value
    if severity == 'error' then
      value = {
        'error',
        config.error_priority,
        config.error_symbol,
        config.error_highlight
      }
    elseif severity == 'hint' then
      value = {
        'hint',
        config.hint_priority,
        config.hint_symbol,
        config.hint_highlight
      }
    elseif severity == 'info' then
      value = {
        'info',
        config.info_priority,
        config.info_symbol,
        config.info_highlight
      }
    elseif severity == 'warn' then
      value = {
        'warn',
        config.warn_priority,
        config.warn_symbol,
        config.warn_highlight
      }
    end
    if value ~= nil then
      local key = ({error = 'E', hint = 'H', info = 'I', warn = 'W'})[severity]
      spec_data[key] = value
    end
  end
  if vim.tbl_isempty(spec_data) then return end
  local names = {}  -- maps severity to registration name
  for severity, item in pairs(spec_data) do
    local variant, priority, symbol, highlight = unpack(item)
    local registration = scrollview.register_sign_spec({
      group = group,
      highlight = highlight,
      priority = priority,
      symbol = symbol,
      variant = variant,
    })
    names[severity] = registration.name
  end
  scrollview.set_sign_group_state(group, config.enabled)

  scrollview.set_sign_group_callback(group, function()
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      for _, name in pairs(names) do
        -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
        -- Check if coc_diagnostic_info is set for the buffer. This will not
        -- be set if e.g., diagnosticToggle or diagnosticToggleBuffer were
        -- used to disable diagnostics. However, we can't use that variable's
        -- contents to get diagnostic info. It only has the number of
        -- diagnostics of each severity, and the minimum line number that
        -- there is a diagnostic for each severity.
        if vim.b[bufnr].coc_diagnostic_info == nil then
          vim.b[bufnr][name] = {}
        end
      end
    end
  end)

  -- The last updated buffers, reset on each CocDiagnosticChange. This is a
  -- dictionary used as a set.
  local active_bufnrs = {}

  api.nvim_create_autocmd('User', {
    pattern = 'CocDiagnosticChange',
    callback = function()
      -- CocActionAsync('diagnosticList') is used intentionally instead of
      -- CocAction('diagnosticList'). Using the latter results in an error when
      -- CocAction('diagnosticRefresh') is called. Although that is not used by
      -- nvim-scrollview, as CocActionAsync('diagnosticRefresh') is used
      -- instead, the possibility of the error elsewhere (e.g., other plugins,
      -- user configs) is avoided by using the asynchronous approach for
      -- getting the diagnostic list. coc.nvim #4806
      if to_bool(vim.fn.exists('*CocActionAsync')) then
        fn.CocActionAsync('diagnosticList', function(err, diagnostic_list)
          -- Clear diagnostic info for existing buffers.
          for bufnr, _ in pairs(active_bufnrs) do
            for _, name in pairs(names) do
              if to_bool(vim.fn.bufexists(bufnr)) then
                -- luacheck: ignore 122 (setting read-only field b.?.? of
                -- global vim)
                vim.b[bufnr][name] = {}
              end
            end
          end
          active_bufnrs = {}
          if err ~= vim.NIL then return end
          -- See Coc's src/diagnostic/util.ts::getSeverityName for severity
          -- names.
          local lookup = {
            Hint = 'H',
            Error = 'E',
            Information = 'I',
            Warning = 'W',
          }
          -- 'diagnostics' maps buffer numbers to a mapping of severity ('H',
          -- 'E', 'I', 'W') to line numbers.
          local diagnostics = {}
          for _, item in ipairs(diagnostic_list) do
            local uri = item.location.uri
            local bufnr = vim.uri_to_bufnr(uri)
            active_bufnrs[bufnr] = true
            if diagnostics[bufnr] == nil then
              diagnostics[bufnr] = {H = {}, E = {}, I = {}, W = {}}
            end
            for lnum = item.lnum, item.end_lnum do
              local key = lookup[item.severity]
              if key ~= nil then
                table.insert(diagnostics[bufnr][key], lnum)
              end
            end
          end
          for bufnr, lines_lookup in pairs(diagnostics) do
            for severity, lines in pairs(lines_lookup) do
              local name = names[severity]
              if name ~= nil then
                vim.b[bufnr][name] = lines
              end
            end
          end
          -- Checking whether the sign group is active is deferred to here so
          -- that the proper coc diagnostics state is maintained even when the
          -- sign group is inactive. This way, signs will be properly set when
          -- the sign group is enabled.
          if scrollview.is_sign_group_active(group) then
            scrollview.refresh()
          end
        end)
      end
    end
  })

  -- Refresh diagnostics to trigger CocDiagnosticChange (otherwise existing
  -- diagnostics wouldn't be reflected on the scrollbar until the next
  -- CocDiagnosticChange).
  pcall(function()
    vim.fn.CocActionAsync('diagnosticRefresh')
  end)
end

return M
