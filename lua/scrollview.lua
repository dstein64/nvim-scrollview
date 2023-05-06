local api = vim.api
local fn = vim.fn

-- TODO: documentation for all new functionality (including User autocmd).
-- TODO: perhaps you should support repeated lines. For example, for searching
-- there could be multiple matches on the same line.

-- WARN: Sometimes 1-indexing is used (primarily for mutual Vim/Neovim API
-- calls) and sometimes 0-indexing (primarily for Neovim-specific API calls).
-- WARN: Functionality that temporarily moves the cursor and restores it should
-- use a window workspace to prevent unwanted side effects. More details are in
-- the documentation for with_win_workspace.
-- XXX: Some of the functionality is applicable to bars and signs, but is
-- named as if it were only applicable to bars (since it was implemented prior
-- to sign support).

-- *************************************************
-- * Memoization
-- *************************************************

local cache = {}
local memoize = false

local start_memoize = function()
  memoize = true
end

local stop_memoize = function()
  memoize = false
end

local reset_memoize = function()
  cache = {}
end

-- *************************************************
-- * Globals
-- *************************************************

-- Internal flag for tracking scrollview state.
local scrollview_enabled = false

-- Since there is no text displayed in the buffers, the same buffers are used
-- for multiple windows. This also prevents the buffer list from getting high
-- from usage of the plugin.

-- bar_bufnr has the bufnr of the buffer created for a position bar.
local bar_bufnr = -1

-- sign_bufnr has the bufnr of the buffer created for signs.
local sign_bufnr = -1

-- Keep count of pending async refreshes.
local pending_async_refresh_count = 0

-- A window variable is set on each scrollview window, as a way to check for
-- scrollview windows, in addition to matching the scrollview buffer number
-- saved in bar_bufnr. This was preferable versus maintaining a list of window
-- IDs.
local win_var = 'scrollview_key'
local win_val = 'scrollview_val'

-- For win workspaces, a window variable is used to store the base window ID.
local win_workspace_base_winid_var = 'scrollview_win_workspace_base_winid'

-- A type field is used to indicate the type of scrollview windows.
local bar_type = 0
local sign_type = 1

-- A key for saving scrollbar properties using a window variable.
local props_var = 'scrollview_props'

-- A key for flagging windows that are pending async removal.
local pending_async_removal_var = 'scrollview_pending_async_removal'

-- Stores registered sign specifications, mapping names to specs.
local sign_specs = {}

-- A highlight namespace that is used for buffer highlighting and as part of a
-- workaround for Neovim #22906.
local hl_namespace = api.nvim_create_namespace('')
api.nvim_set_hl(hl_namespace, 'Normal', {})

-- *************************************************
-- * Utils
-- *************************************************

-- Round to the nearest integer.
-- WARN: .5 rounds to the right on the number line, including for negatives
-- (which would not result in rounding up in magnitude).
-- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
local round = function(x)
  return math.floor(x + 0.5)
end

local reltime_to_microseconds = function(reltime)
  local reltimestr = fn.reltimestr(reltime)
  return tonumber(table.concat(vim.split(reltimestr, '%.'), ''))
end

-- Replace termcodes.
local t = function(str)
  return api.nvim_replace_termcodes(str, true, true, true)
end

-- Get value from a map-like table, using the specified default.
local tbl_get = function(table, key, default)
  local result = table[key]
  if result == nil then
    result = default
  end
  return result
end

-- Returns true for boolean true and any non-zero number, otherwise returns
-- false.
local to_bool = function(x)
  if type(x) == 'boolean' then
    return x
  elseif type(x) == 'number' then
    return x ~= 0
  end
  return false
end

-- Create a shallow copy of a map-like table.
local copy = function(table)
  local result = {}
  for key, val in pairs(table) do
    result[key] = val
  end
  return result
end

-- Concatenate two array-like tables.
local concat = function(a, b)
  local result = {}
  for _, x in ipairs(a) do
    table.insert(result, x)
  end
  for _, x in ipairs(b) do
    table.insert(result, x)
  end
  return result
end

-- A non-destructive sort function.
local sorted = function(l)
  local result = copy(l)
  table.sort(result)
  return result
end

-- Returns the index of x in l if present, or the index for insertion
-- otherwise.
local binary_search = function(l, x)
  local lo = 1
  local hi = #l
  while lo <= hi do
    local mid = math.floor((hi - lo) / 2 + lo)
    if l[mid] == x then
      return mid
    elseif l[mid] < x then
      lo = lo + 1
    else
      hi = hi - 1
    end
  end
  return lo
end

-- Slice an array-like table.
local slice = function(tbl, first, last, step)
  local result = {}
  for idx = first, last, step do
    if idx > #tbl or idx < 1 then
      break
    end
    table.insert(result, tbl[idx])
  end
  return result
end

-- TODO Move the follwing functions to where they should go
local register_sign_spec = function(name, specification)
  specification = copy(specification)
  -- priority, symbol and highlight can be arrays
  for _, key in ipairs({'priority', 'symbol', 'highlight'}) do
    if type(specification[key]) ~= 'table' then
      specification[key] = {specification[key]}
    else
      specification[key] = copy(specification[key])
    end
  end
  sign_specs[name] = specification
end

local unregister_sign_spec = function(name)
  sign_specs[name] = nil
end

-- TODO: Move diagnostic handling out of here.
-- TODO: Make highlight groups for the plugin (e.g., ScrollViewDiagnosticError)
-- TODO: Update highlight colors and signs. Some match search highlights.

local spec_data = {
  [vim.diagnostic.severity.ERROR] =
    {'scrollview_diagnostic_signs_error', 60, 'Error'},
  [vim.diagnostic.severity.WARN] =
    {'scrollview_diagnostic_signs_warn', 50, 'Todo'},
  [vim.diagnostic.severity.INFO] =
    {'scrollview_diagnostic_signs_info', 40, 'Title'},
  [vim.diagnostic.severity.HINT] =
    {'scrollview_diagnostic_signs_hint', 30, 'Question'},
}
for _, item in pairs(spec_data) do
  local name, priority, highlight = unpack(item)
  -- TODO: Use a different symbol.
  register_sign_spec(name, {
    priority = priority,
    symbol = {'1', '2', '3', '4', '5', '6', '7', '8', '9', '+'},
    highlight = highlight,
  })
end

if to_bool(fn.exists('*nvim_create_autocmd')) then
  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    callback = function(args)
      local names = {
        [vim.diagnostic.severity.ERROR] = 'scrollview_diagnostic_signs_error',
        [vim.diagnostic.severity.WARN] = 'scrollview_diagnostic_signs_warn',
        [vim.diagnostic.severity.INFO] = 'scrollview_diagnostic_signs_info',
        [vim.diagnostic.severity.HINT] = 'scrollview_diagnostic_signs_hint',
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
      if vim.fn.mode() ~= 'i' or vim.diagnostic.config().update_in_insert then
        -- Refresh scrollbars immediately when update_in_insert is set or the
        -- current mode is not insert mode.
        require('scrollview').scrollview_refresh()
      else
        -- Refresh scrollbars once leaving insert mode. Overwrite an existing
        -- autocmd configured to already do this.
        local group = vim.api.nvim_create_augroup('scrollview_diagnostic_signs', {
          clear = true
        })
        vim.api.nvim_create_autocmd('InsertLeave', {
          group = group,
          callback = function(args)
            require('scrollview').scrollview_refresh()
          end,
          once = true,
        })
      end
    end,
  })
end

-- TODO: Move search handling out of here.

local signs_name = 'scrollview_search_signs'

register_sign_spec(signs_name, {
  priority = 50,
  symbol = {'1', '2', '3', '4', '5', '6', '7', '8', '9', '+'},
  highlight = 'Search',
})

if to_bool(fn.exists('*nvim_create_autocmd')) then
  vim.api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = function(args)
      for _, winid in ipairs(require('scrollview').get_ordinary_windows()) do
        local winnr = api.nvim_win_get_number(winid)
        local lines = {}
        if to_bool(vim.v.hlsearch) then
          lines = require('scrollview').with_win_workspace(winid, function()
            local result = {}
            local line_count = api.nvim_buf_line_count(0)
            -- Search signs are not shown when the number of buffer lines
            -- exceeds the limit, to prevent a slowdown.
            local line_count_limit = require('scrollview').get_variable(
              'scrollview_search_signs_buffer_lines_limit', winnr)
            local within_limit = line_count_limit == -1
              or line_count <= line_count_limit
            if within_limit and fn.searchcount().total > 0 then
              result = fn.split(fn.execute('global//echo line(".")'))
            end
            return result
          end)
          for idx, line in ipairs(lines) do
            lines[idx] = tonumber(line)
          end
        end
        local bufnr = api.nvim_win_get_buf(winid)
        vim.b[bufnr][signs_name] = lines
      end
    end,
  })

  vim.api.nvim_create_autocmd('OptionSet', {
    callback = function(args)
      local amatch = fn.expand('<amatch>')
      if amatch == 'hlsearch' then
        require('scrollview').scrollview_refresh()
      end
    end
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    callback = function(args)
      if to_bool(vim.v.event.abort) then
        return
      end
      local afile = fn.expand('<afile>')
      -- Handle the case where a search is executed.
      local refresh = afile == '/' or afile == '?'
      -- Handle the case where :nohls may have been executed (this won't work
      -- for e.g., <cmd>nohls<cr> in a mapping).
      if afile == ':' then
        -- TODO: Can this be limited to only :nohls? If not, can we check some
        -- other way if a refresh is necessary?
        refresh = true
      end
      if refresh then
        require('scrollview').scrollview_refresh()
      end
    end
  })

  -- Handle the case where the cursor moves. This handles pressing 'n' or 'N'
  -- to continue a search (except in the case where there's only one match and
  -- the cursor doesn't move). The InsertEnter case handles when insert mode is
  -- entered at the same time as v:hlsearch is turned off. The InsertLeave case
  -- updates search signs after leaving insert mode, when newly added text
  -- might correspond to new signs.
  vim.api.nvim_create_autocmd({'CursorMoved', 'InsertEnter', 'InsertLeave'}, {
    callback = function(args)
      -- TODO: Can we check if a refresh is necessary?
      require('scrollview').scrollview_refresh()
    end
  })
end

-- *************************************************
-- * Core
-- *************************************************

-- Return window height, subtracting 1 if there is a winbar.
local get_window_height = function(winid)
  if winid == 0 then
    winid = api.nvim_get_current_win()
  end
  local height = api.nvim_win_get_height(winid)
  if to_bool(tbl_get(fn.getwininfo(winid)[1], 'winbar', 0)) then
    height = height - 1
  end
  return height
end

-- Set window option.
local set_window_option = function(winid, key, value)
  -- Convert to Vim format (e.g., 1 instead of Lua true).
  if value == true then
    value = 1
  elseif value == false then
    value = 0
  end
  -- setwinvar(..., '&...', ...) is used in place of nvim_win_set_option
  -- to avoid Neovim Issues #15529 and #15531, where the global window option
  -- is set in addition to the window-local option, when using Neovim's API or
  -- Lua interface.
  fn.setwinvar(winid, '&' .. key, value)
end

-- Executes a function in a window with the specified options temporarily set.
local with_win_options = function(winid, opts, fun)
  api.nvim_win_call(winid, function()
    local restore = {}
    for key, val in pairs(opts) do
      local cur = api.nvim_win_get_option(winid, key)
      if cur ~= val then
        restore[key] = cur
        set_window_option(winid, key, val)
      end
    end
    fun()
    for key, val in pairs(restore) do
      set_window_option(winid, key, val)
    end
  end)
end

-- Return the base window ID for the specified window. Assumes that windows
-- have been properly marked with win_workspace_base_winid_var.
local get_base_winid = function(winid)
  local base_winid = winid
  pcall(function()
    -- Loop until reaching a window with no base winid specified.
    while true do
      base_winid = api.nvim_win_get_var(
        base_winid, win_workspace_base_winid_var)
    end
  end)
  return base_winid
end

-- Creates a temporary floating window that can be used for computations
-- ---corresponding to the specified window---that require temporary cursor
-- movements (e.g., counting virtual lines, where all lines in a closed fold
-- are counted as a single line). This can be used instead of working in the
-- actual window, to prevent unintended side-effects that arise from moving the
-- cursor in the actual window, even when autocmd's are disabled with
-- eventignore=all and the cursor is restored (e.g., Issue #18: window
-- flickering when resizing with the mouse, Issue #19: cursorbind/scrollbind
-- out-of-sync).
local with_win_workspace = function(winid, fun)
  -- Make the target window active, so that its folds are inherited by the
  -- created floating window (this is necessary when there are multiple windows
  -- that have the same buffer, each window having different folds).
  local workspace_winid = api.nvim_win_call(winid, function()
    local bufnr = api.nvim_win_get_buf(winid)
    return api.nvim_open_win(bufnr, false, {
      relative = 'editor',
      focusable = false,
      width = math.max(1, api.nvim_win_get_width(winid)),
      -- The floating window doesn't inherit a winbar. Use the winbar-omitted
      -- height where applicable.
      height = math.max(1, get_window_height(winid)),
      row = 0,
      col = 0
    })
  end)
  -- Disable scrollbind and cursorbind on the workspace window so that diff
  -- mode and other functionality that utilizes binding (e.g., :Gdiff, :Gblame)
  -- can function properly.
  set_window_option(workspace_winid, 'scrollbind', false)
  set_window_option(workspace_winid, 'cursorbind', false)
  api.nvim_win_set_var(workspace_winid, win_workspace_base_winid_var, winid)
  -- As a precautionary measure, make sure the floating window has no winbar,
  -- which is assumed above.
  if to_bool(fn.exists('+winbar')) then
    set_window_option(workspace_winid, 'winbar', '')
  end
  -- Don't include the workspace window in a diff session. If included, closing
  -- it could end the diff session (e.g., when there is one other window in the
  -- session). Issue #57.
  set_window_option(workspace_winid, 'diff', false)
  local result
  local success, err = pcall(function()
    result = api.nvim_win_call(workspace_winid, fun)
  end)
  api.nvim_win_close(workspace_winid, true)
  if not success then error(err) end
  return result
end

local is_visual_mode = function(mode)
  return vim.tbl_contains({'v', 'V', t'<c-v>'}, mode)
end

local is_select_mode = function(mode)
  return vim.tbl_contains({'s', 'S', t'<c-s>'}, mode)
end

-- Returns true for ordinary windows (not floating and not external), and false
-- otherwise.
local is_ordinary_window = function(winid)
  local config = api.nvim_win_get_config(winid)
  local not_external = not tbl_get(config, 'external', false)
  local not_floating = tbl_get(config, 'relative', '') == ''
  return not_external and not_floating
end

-- Returns a list of window IDs for the ordinary windows.
local get_ordinary_windows = function()
  local winids = {}
  for winnr = 1, fn.winnr('$') do
    local winid = fn.win_getid(winnr)
    if is_ordinary_window(winid) then
      table.insert(winids, winid)
    end
  end
  return winids
end

local in_command_line_window = function()
  if fn.win_gettype() == 'command' then return true end
  if fn.mode() == 'c' then return true end
  local bufnr = api.nvim_get_current_buf()
  local buftype = api.nvim_buf_get_option(bufnr, 'buftype')
  local bufname = fn.bufname(bufnr)
  return buftype == 'nofile' and bufname == '[Command Line]'
end

-- Returns the window column where the buffer's text begins. This may be
-- negative due to horizontal scrolling. This may be greater than one due to
-- the sign column and 'number' column.
local buf_text_begins_col = function()
  -- The calculation assumes lines don't wrap, so 'nowrap' is temporarily set.
  local wrap = api.nvim_win_get_option(0, 'wrap')
  set_window_option(0, 'wrap', false)
  local result = fn.wincol() - fn.virtcol('.') + 1
  set_window_option(0, 'wrap', wrap)
  return result
end

-- Returns the window column where the view of the buffer begins. This can be
-- greater than one due to the sign column and 'number' column.
local buf_view_begins_col = function()
  -- The calculation assumes lines don't wrap, so 'nowrap' is temporarily set.
  local wrap = api.nvim_win_get_option(0, 'wrap')
  set_window_option(0, 'wrap', false)
  local result = fn.wincol() - fn.virtcol('.') + fn.winsaveview().leftcol + 1
  set_window_option(0, 'wrap', wrap)
  return result
end

-- Returns the specified variable. There are two optional arguments, for
-- specifying precedence and a default value. Without specifying precedence,
-- highest precedence is given to window variables, then tab page variables,
-- then buffer variables, then global variables. Without specifying a default
-- value, 0 will be used.
local get_variable = function(name, winnr, precedence, default)
  if precedence == nil then precedence = 'wtbg' end
  if default == nil then default = 0 end
  for idx = 1, #precedence do
    local c = precedence:sub(idx, idx)
    if c == 'w' then
      local winvars = fn.getwinvar(winnr, '')
      if winvars[name] ~= nil then return winvars[name] end
    elseif c == 't' then
      local winid = fn.win_getid(winnr)
      local tabnr = fn.getwininfo(winid)[1].tabnr
      local tabvars = fn.gettabvar(tabnr, '')
      if tabvars[name] ~= nil then return tabvars[name] end
    elseif c == 'b' then
      local bufnr = fn.winbufnr(winnr)
      local bufvars = fn.getbufvar(bufnr, '')
      if bufvars[name] ~= nil then return bufvars[name] end
    elseif c == 'g' then
      if vim.g[name] ~= nil then return vim.g[name] end
    else
      error('Unknown variable type ' .. c)
    end
  end
  return default
end

-- Returns the scrollview mode. The function signature matches s:GetVariable,
-- without the 'name' argument.
local scrollview_mode = function(winnr, precedence, default)
  if to_bool(vim.g.scrollview_refresh_time_exceeded) then
    return 'simple'
  end
  return get_variable('scrollview_mode', winnr, precedence, default)
end

-- Return top line and bottom line in window. For folds, the top line
-- represents the start of the fold and the bottom line represents the end of
-- the fold.
local line_range = function(winid)
  -- WARN: getwininfo(winid)[1].botline is not properly updated for some
  -- movements (Neovim Issue #13510), so this is implemented as a workaround.
  -- This was originally handled by using an asynchronous context, but this was
  -- not possible for refreshing bars during mouse drags.
  -- Using scrolloff=0 combined with H and L breaks diff mode. Scrolling is not
  -- possible and/or the window scrolls when it shouldn't. Temporarily turning
  -- off scrollbind and cursorbind accommodates, but the following is simpler.
  return unpack(api.nvim_win_call(winid, function()
    local topline = fn.line('w0')
    local botline = fn.line('w$')
    -- line('w$') returns 0 in silent Ex mode, but line('w0') is always greater
    -- than or equal to 1.
    botline = math.max(botline, topline)
    return {topline, botline}
  end))
end

-- Advance the current window cursor to the start of the next virtual span,
-- returning the range of lines jumped over, and a boolean indicating whether
-- that range was in a closed fold. A virtual span is a contiguous range of
-- lines that are either 1) not in a closed fold or 2) in a closed fold. If
-- there is no next virtual span, the cursor is returned to the first line.
local advance_virtual_span = function()
  local start = fn.line('.')
  local foldclosedend = fn.foldclosedend(start)
  if foldclosedend ~= -1 then
    -- The cursor started on a closed fold.
    if foldclosedend == fn.line('$') then
      vim.cmd('keepjumps normal! gg')
    else
      vim.cmd('keepjumps normal! j')
    end
    return start, foldclosedend, true
  end
  local lnum = start
  while true do
    vim.cmd('keepjumps normal! zj')
    if lnum == fn.line('.') then
      -- There are no more folds after the cursor. This is the last span.
      vim.cmd('keepjumps normal! gg')
      return start, fn.line('$'), false
    end
    lnum = fn.line('.')
    local foldclosed = fn.foldclosed(lnum)
    if foldclosed ~= -1 then
      -- The cursor moved to a closed fold. The preceding line ends the prior
      -- virtual span.
      return start, lnum - 1, false
    end
  end
end

-- Returns a boolean indicating whether the count of folds (closed folds count
-- as a single fold) between the specified start and end lines exceeds 'n', in
-- the current window. The cursor may be moved.
local fold_count_exceeds = function(start, end_, n)
  vim.cmd('keepjumps normal! ' .. start .. 'G')
  if fn.foldclosed(start) ~= -1 then
    n = n - 1
  end
  if n < 0 then
    return true
  end
  -- Navigate down n folds.
  if n > 0 then
    vim.cmd('keepjumps normal! ' .. n .. 'zj')
  end
  local line1 = fn.line('.')
  -- The fold count exceeds n if there is another fold to navigate to on a line
  -- less than end_.
  vim.cmd('keepjumps normal! zj')
  local line2 = fn.line('.')
  return line2 > line1 and line2 <= end_
end

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the current window. A closed fold counts as one virtual
-- line. The computation loops over virtual spans. The cursor may be moved.
local virtual_line_count_spanwise = function(start, end_)
  start = math.max(1, start)
  end_ = math.min(fn.line('$'), end_)
  local count = 0
  if end_ >= start then
    vim.cmd('keepjumps normal! ' .. start .. 'G')
    while true do
      local range_start, range_end, fold = advance_virtual_span()
      range_end = math.min(range_end, end_)
      local delta = 1
      if not fold then
        delta = range_end - range_start + 1
      end
      count = count + delta
      if range_end == end_ or fn.line('.') == 1 then
        break
      end
    end
  end
  return count
end

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the current window. A closed fold counts as one virtual
-- line. The computation loops over lines. The cursor is not moved.
local virtual_line_count_linewise = function(start, end_)
  local count = 0
  local line = start
  while line <= end_ do
    count = count + 1
    local foldclosedend = fn.foldclosedend(line)
    if foldclosedend ~= -1 then
      line = foldclosedend
    end
    line = line + 1
  end
  return count
end

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the specified window. A closed fold counts as one
-- virtual line. The computation loops over either lines or virtual spans, so
-- the cursor may be moved.
local virtual_line_count = function(winid, start, end_)
  local last_line = api.nvim_buf_line_count(api.nvim_win_get_buf(winid))
  if type(end_) == 'string' and end_ == '$' then
    end_ = last_line
  end
  local base_winid = get_base_winid(winid)
  local memoize_key =
    table.concat({'virtual_line_count', base_winid, start, end_}, ':')
  if memoize and cache[memoize_key] then return cache[memoize_key] end
  local count = with_win_workspace(winid, function()
    -- On an AMD Ryzen 7 2700X, linewise computation takes about 3e-7 seconds
    -- per line (this is an overestimate, as it assumes all folds are open, but
    -- the time is reduced when there are closed folds, as lines would be
    -- skipped). Spanwise computation takes about 5e-5 seconds per fold (closed
    -- folds count as a single fold). Therefore the linewise computation is
    -- worthwhile when the number of folds is greater than (3e-7 / 5e-5) * L =
    -- .006L, where L is the number of lines.
    if fold_count_exceeds(start, end_, math.floor(last_line * .006)) then
      return virtual_line_count_linewise(start, end_)
    else
      return virtual_line_count_spanwise(start, end_)
    end
  end)
  if memoize then cache[memoize_key] = count end
  return count
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode, in the current window.
-- The computation loops over virtual spans. The cursor may be moved.
local virtual_topline_lookup_spanwise = function()
  local winheight = get_window_height(0)
  local result = {}  -- A list of line numbers
  local winid = api.nvim_get_current_win()
  local total_vlines = virtual_line_count(winid, 1, '$')
  if total_vlines > 1 and winheight > 1 then
    local line = 0
    local virtual_line = 0
    local prop = 0.0
    local row = 1
    local proportion = (row - 1) / winheight
    vim.cmd('keepjumps normal! gg')
    while #result < winheight do
      local range_start, range_end, fold = advance_virtual_span()
      local line_delta = range_end - range_start + 1
      local virtual_line_delta = 1
      if not fold then
        virtual_line_delta = line_delta
      end
      local prop_delta = virtual_line_delta / (total_vlines - 1)
      while prop + prop_delta >= proportion and #result < winheight do
        local ratio = (proportion - prop) / prop_delta
        local topline = line + 1
        if fold then
          -- If ratio >= 0.5, add all lines in the fold, otherwise don't add
          -- the fold.
          if ratio >= 0.5 then
            topline = topline + line_delta
          end
        else
          topline = topline + round(ratio * line_delta)
        end
        table.insert(result, topline)
        row = row + 1
        proportion = (row - 1) / winheight
      end
      -- A line number of 1 indicates that advance_virtual_span looped back to
      -- the beginning of the document.
      local looped = fn.line('.') == 1
      if looped or #result >= winheight then
        break
      end
      line = line + line_delta
      virtual_line = virtual_line + virtual_line_delta
      prop = virtual_line / (total_vlines - 1)
    end
  end
  while #result < winheight do
    table.insert(result, fn.line('$'))
  end
  for idx, line in ipairs(result) do
    line = math.max(1, line)
    line = math.min(fn.line('$'), line)
    local foldclosed = fn.foldclosed(line)
    if foldclosed ~= -1 then
      line = foldclosed
    end
    result[idx] = line
  end
  return result
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode, in the current window.
-- The computation primarily loops over lines, but may loop over virtual spans
-- as part of calling 'virtual_line_count', so the cursor may be moved.
local virtual_topline_lookup_linewise = function()
  local winheight = get_window_height(0)
  local last_line = fn.line('$')
  local result = {}  -- A list of line numbers
  local winid = api.nvim_get_current_win()
  local total_vlines = virtual_line_count(winid, 1, '$')
  if total_vlines > 1 and winheight > 1 then
    local count = 1  -- The count of virtual lines
    local line = 1
    local best = line
    local best_distance = math.huge
    local best_count = count
    for row = 1, winheight do
      local proportion = (row - 1) / winheight
      while line <= last_line do
        local current = (count - 1) / (total_vlines - 1)
        local distance = math.abs(current - proportion)
        if distance <= best_distance then
          best = line
          best_distance = distance
          best_count = count
        elseif distance > best_distance then
          -- Prepare variables so that the next row starts iterating at the
          -- current line and count, using an infinite best distance.
          line = best
          best_distance = math.huge
          count = best_count
          break
        end
        local foldclosedend = fn.foldclosedend(line)
        if foldclosedend ~= -1 then
          line = foldclosedend
        end
        line = line + 1
        count = count + 1
      end
      local value = best
      local foldclosed = fn.foldclosed(value)
      if foldclosed ~= -1 then
        value = foldclosed
      end
      table.insert(result, value)
    end
  end
  return result
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode. The computation loops
-- over either lines or virtual spans, so the cursor may be moved.
local virtual_topline_lookup = function(winid)
  local result = with_win_workspace(winid, function()
    local last_line = api.nvim_buf_line_count(api.nvim_win_get_buf(winid))
    -- On an AMD Ryzen 7 2700X, linewise computation takes about 1.6e-6 seconds
    -- per line (this is an overestimate, as it assumes all folds are open, but
    -- the time is reduced when there are closed folds, as lines would be
    -- skipped). Spanwise computation takes about 6.5e-5 seconds per fold
    -- (closed folds count as a single fold). Therefore the linewise
    -- computation is worthwhile when the number of folds is greater than
    -- (1.6e-6 / 6.5e-5) * L = .0246L, where L is the number of lines.
    if fold_count_exceeds(1, last_line, math.floor(last_line * .0246)) then
      return virtual_topline_lookup_linewise()
    else
      return virtual_topline_lookup_spanwise()
    end
  end)
  return result
end

local simple_topline_lookup = function(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  local winheight = get_window_height(winid)
  local topline_lookup = {}
  for row = 1, winheight do
    local proportion = (row - 1) / winheight
    local topline = round(proportion * (line_count - 1)) + 1
    table.insert(topline_lookup, topline)
  end
  return topline_lookup
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row.
local topline_lookup = function(winid)
  local winnr = api.nvim_win_get_number(winid)
  local mode = scrollview_mode(winnr)
  local base_winid = get_base_winid(winid)
  local memoize_key =
    table.concat({'topline_lookup', base_winid, mode}, ':')
  if memoize and cache[memoize_key] then return cache[memoize_key] end
  local topline_lookup
  if mode ~= 'simple' then
    -- Handling for virtual mode or an unknown mode.
    topline_lookup = virtual_topline_lookup(winid)
  else
    topline_lookup = simple_topline_lookup(winid)
  end
  if memoize then cache[memoize_key] = topline_lookup end
  return topline_lookup
end

local calculate_scrollbar_column = function(winnr)
  local winid = fn.win_getid(winnr)
  local winwidth = fn.winwidth(winnr)
  -- left is the position for the left of the scrollbar, relative to the
  -- window, and 0-indexed.
  local left = 0
  local column = get_variable('scrollview_column', winnr)
  local base = get_variable('scrollview_base', winnr)
  if base == 'left' then
    left = left + column - 1
  elseif base == 'right' then
    left = left + winwidth - column
  elseif base == 'buffer' then
    local btbc = api.nvim_win_call(winid, buf_text_begins_col)
    left = left + column - 1 + btbc - 1
  else
    -- For an unknown base, use the default position (right edge of window).
    left = left + winwidth - 1
  end
  return left + 1
end

-- Calculates the bar position for the specified window. Returns a dictionary
-- with a height, row, and col.
local calculate_position = function(winnr)
  local winid = fn.win_getid(winnr)
  local bufnr = api.nvim_win_get_buf(winid)
  local topline, botline = line_range(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  local the_topline_lookup = topline_lookup(winid)
  -- top is the position for the top of the scrollbar, relative to the window.
  local top = binary_search(the_topline_lookup, topline)
  if top > #the_topline_lookup
      or (top > 1 and the_topline_lookup[top] ~= topline) then
    top = top - 1  -- use the preceding line from topline lookup.
  end
  top = top - 1  -- use 0-indexing (temporarily)
  local winheight = get_window_height(winid)
  local height = winheight
  local effective_line_count = line_count
  local mode = scrollview_mode(winnr)
  if mode ~= 'simple' then
    -- For virtual mode or an unknown mode, update effective_line_count to
    -- correspond to virtual lines, which account for closed folds.
    effective_line_count = virtual_line_count(winid, 1, '$')
  end
  if effective_line_count > height then
    height = winheight / effective_line_count
    height = math.ceil(height * winheight)
    height = math.max(1, height)
  end
  -- Make sure bar properly reflects bottom of document.
  if botline == line_count then
    top = winheight - height
  end
  -- Make sure bar never overlaps status line.
  if top + height > winheight then
    top = winheight - height
  end
  local result = {
    height = height,
    row = top + 1,
    col = calculate_scrollbar_column(winnr)
  }
  return result
end

local is_scrollview_window = function(winid)
  if is_ordinary_window(winid) then return false end
  local has_attr = false
  pcall(function()
    has_attr = api.nvim_win_get_var(winid, win_var) == win_val
  end)
  if not has_attr then return false end
  local bufnr = api.nvim_win_get_buf(winid)
  return bufnr == bar_bufnr or bufnr == sign_bufnr
end

-- Returns the position of window edges, with borders considered part of the
-- window.
local get_window_edges = function(winid)
  local top, left = unpack(fn.win_screenpos(winid))
  local bottom = top + get_window_height(winid) - 1
  local right = left + fn.winwidth(winid) - 1
  -- Only edges have to be checked to determine if a border is present (i.e.,
  -- corners don't have to be checked). Borders don't impact the top and left
  -- positions calculated above; only the bottom and right positions.
  local border = api.nvim_win_get_config(winid).border
  if border ~= nil and vim.tbl_islist(border) and #border == 8 then
    if border[2] ~= '' then
      -- There is a top border.
      bottom = bottom + 1
    end
    if border[4] ~= '' then
      -- There is a right border.
      right = right + 1
    end
    if border[6] ~= '' then
      -- There is a bottom border.
      bottom = bottom + 1
    end
    if border[8] ~= '' then
      -- There is a left border.
      right = right + 1
    end
  end
  return top, bottom, left, right
end

-- Return the floating windows that overlap the region corresponding to the
-- specified edges.
local get_float_overlaps = function(top, bottom, left, right)
  local result = {}
  for winnr = 1, fn.winnr('$') do
    local winid = fn.win_getid(winnr)
    local config = api.nvim_win_get_config(winid)
    local floating = tbl_get(config, 'relative', '') ~= ''
    if floating and not is_scrollview_window(winid) then
      local top2, bottom2, left2, right2 = get_window_edges(winid)
      if top <= bottom2
          and bottom >= top2
          and left <= right2
          and right >= left2 then
        table.insert(result, winid)
      end
    end
  end
  return result
end

-- Whether scrollbar and signs should be shown. This is the first check; it
-- only checks for conditions that apply to both the position bar and signs.
local should_show = function(winid)
  local winnr = api.nvim_win_get_number(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local buf_filetype = api.nvim_buf_get_option(bufnr, 'filetype')
  local winheight = get_window_height(winid)
  local winwidth = fn.winwidth(winnr)
  local wininfo = fn.getwininfo(winid)[1]
  -- Skip if the filetype is on the list of exclusions.
  local excluded_filetypes = get_variable('scrollview_excluded_filetypes', winnr)
  if vim.tbl_contains(excluded_filetypes, buf_filetype) then
    return false
  end
  -- Don't show in terminal mode, since the bar won't be properly updated for
  -- insertions.
  if to_bool(wininfo.terminal) then
    return false
  end
  if winheight == 0 or winwidth == 0 then
    return false
  end
  -- Don't show when all lines are on screen.
  local topline, botline = line_range(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  if botline - topline + 1 == line_count then
    return false
  end
  return true
end

-- Indicates whether the column is valid for showing a scrollbar or signs.
local is_valid_column = function(winid, col)
  local winnr = api.nvim_win_get_number(winid)
  local winwidth = fn.winwidth(winnr)
  local min_valid_col = 1
  local max_valid_col = winwidth
  local base = get_variable('scrollview_base', winnr)
  if base == 'buffer' then
    min_valid_col = api.nvim_win_call(winid, buf_view_begins_col)
  end
  if col < min_valid_col then
    return false
  end
  if col > max_valid_col then
    return false
  end
  return true
end

-- Show a scrollbar for the specified 'winid' window ID, using the specified
-- 'bar_winid' floating window ID (a new floating window will be created if
-- this is -1). Returns -1 if the bar is not shown, and the floating window ID
-- otherwise.
local show_scrollbar = function(winid, bar_winid)
  local winnr = api.nvim_win_get_number(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local wininfo = fn.getwininfo(winid)[1]
  local line_count = api.nvim_buf_line_count(bufnr)
  local bar_position = calculate_position(winnr)
  if not to_bool(get_variable('scrollview_out_of_bounds', winnr)) then
    local winwidth = fn.winwidth(winnr)
    bar_position.col = math.max(1, math.min(winwidth, bar_position.col))
  end
  if not is_valid_column(winid, bar_position.col) then
    return -1
  end
  -- Height has to be positive for the call to nvim_open_win. When opening a
  -- terminal, the topline and botline can be set such that height is negative
  -- when you're using scrollview document mode.
  if bar_position.height <= 0 then
    return -1
  end
  if to_bool(get_variable('scrollview_hide_on_intersect', winnr)) then
    local winrow0 = wininfo.winrow - 1
    local wincol0 = wininfo.wincol - 1
    local float_overlaps = get_float_overlaps(
      winrow0 + bar_position.row,
      winrow0 + bar_position.row + bar_position.height - 1,
      wincol0 + bar_position.col,
      wincol0 + bar_position.col
    )
    for _, float_winid in ipairs(float_overlaps) do
      if not is_scrollview_window(float_winid) then
        return -1
      end
    end
  end
  if bar_bufnr == -1 or not to_bool(fn.bufexists(bar_bufnr)) then
    bar_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(bar_bufnr, 'modifiable', false)
    api.nvim_buf_set_option(bar_bufnr, 'filetype', 'scrollview')
    api.nvim_buf_set_option(bar_bufnr, 'buftype', 'nofile')
    api.nvim_buf_set_option(bar_bufnr, 'swapfile', false)
    api.nvim_buf_set_option(bar_bufnr, 'bufhidden', 'hide')
    api.nvim_buf_set_option(bar_bufnr, 'buflisted', false)
  end
  -- Make sure that a custom character is up-to-date and is repeated enough to
  -- cover the full height of the scrollbar.
  local bar_line_count = api.nvim_buf_line_count(bar_bufnr)
  if api.nvim_buf_get_lines(bar_bufnr, 0, 1, false)[1] ~= vim.g.scrollview_character
      or bar_position.height > bar_line_count then
    api.nvim_buf_set_option(bar_bufnr, 'modifiable', true)
    api.nvim_buf_set_lines(
      bar_bufnr, 0, bar_line_count, false,
      fn['repeat']({vim.g.scrollview_character}, bar_position.height))
    api.nvim_buf_set_option(bar_bufnr, 'modifiable', false)
  end
  local zindex = get_variable('scrollview_zindex', winnr)
  -- When there is a winbar, nvim_open_win with relative=win considers row 0 to
  -- be the line below the winbar.
  local config = {
    win = winid,
    relative = 'win',
    focusable = false,
    style = 'minimal',
    height = bar_position.height,
    width = 1,
    row = bar_position.row - 1,
    col = bar_position.col - 1,
    zindex = zindex
  }
  if bar_winid == -1 then
    bar_winid = api.nvim_open_win(bar_bufnr, false, config)
  else
    api.nvim_win_set_config(bar_winid, config)
  end
  -- Scroll to top so that the custom character spans full scrollbar height.
  vim.cmd('keepjumps call nvim_win_set_cursor(' .. bar_winid .. ', [1, 0])')
  -- It's not sufficient to just specify Normal highlighting. With just that, a
  -- color scheme's specification of EndOfBuffer would be used to color the
  -- bottom of the scrollbar.
  local winhighlight = 'Normal:ScrollView,EndOfBuffer:ScrollView'
  set_window_option(bar_winid, 'winhighlight', winhighlight)
  local winblend = get_variable('scrollview_winblend', winnr)
  set_window_option(bar_winid, 'winblend', winblend)
  set_window_option(bar_winid, 'foldcolumn', '0')  -- foldcolumn takes a string
  set_window_option(bar_winid, 'foldenable', false)
  set_window_option(bar_winid, 'wrap', false)
  api.nvim_win_set_var(bar_winid, win_var, win_val)
  api.nvim_win_set_var(bar_winid, pending_async_removal_var, false)
  local props = {
    type = bar_type,
    parent_winid = winid,
    scrollview_winid = bar_winid,
    height = bar_position.height,
    row = bar_position.row,
    col = bar_position.col,
    zindex = zindex,
  }
  api.nvim_win_set_var(bar_winid, props_var, props)
  return bar_winid
end

-- Show signs for the specified 'winid' window ID. A list of existing sign
-- winids, 'sign_winids', is specified for possible reuse. Reused windows are
-- removed from the list.
local show_signs = function(winid, sign_winids)
  local winnr = api.nvim_win_get_number(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  local the_topline_lookup = nil  -- only set when needed
  local base_col = calculate_scrollbar_column(winnr)
  base_col = base_col + get_variable('scrollview_sign_column', winnr)
  -- lookup maps rows to a mapping of names to sign specifications (with lines).
  local lookup = {}
  for name, sign_spec in pairs(sign_specs) do
    local lines = {}
    local lines_as_given = fn.getbufvar(bufnr, name, {})
    -- Signs are not shown when the number of lines for each registered sign
    -- specification exceeds the limit, to prevent a slowdown.
    local lines_per_sign_spec_limit =
      get_variable('scrollview_lines_per_sign_spec_limit', winnr)
    local within_limit = lines_per_sign_spec_limit == -1
      or #lines_as_given <= lines_per_sign_spec_limit
    if within_limit then
      for _, line in ipairs(sorted(lines_as_given)) do
        if #lines == 0 or lines[#lines] ~= line then
          table.insert(lines, line)
        end
      end
    end
    if #lines > 0 and the_topline_lookup == nil then
      the_topline_lookup = topline_lookup(winid)
    end
    for _, line in ipairs(lines) do
      if line >= 1 and line <= line_count then
        local row = binary_search(the_topline_lookup, line)
        if row > #the_topline_lookup or
            (row > 1 and the_topline_lookup[row] ~= line) then
          row = row - 1  -- use the preceding line from topline lookup.
        end
        if lookup[row] == nil then
          lookup[row] = {}
        end
        if lookup[row][name] == nil then
          local properties = {
            symbol = sign_spec.symbol,
            highlight = sign_spec.highlight,
            priority = sign_spec.priority,
          }
          properties.name = name
          properties.lines = {line}
          lookup[row][name] = properties
        else
          table.insert(lookup[row][name].lines, line)
        end
      end
    end
  end
  for row, props_lookup in pairs(lookup) do
    local props_list = {}
    for _, properties in pairs(props_lookup) do
      for _, field in ipairs({'priority', 'symbol', 'highlight'}) do
        if #properties.lines > #properties[field] then
          properties[field] = properties[field][#properties[field]]
        else
          properties[field] = properties[field][#properties.lines]
        end
      end
      table.insert(props_list, properties)
    end
    -- Sort descending by priority.
    table.sort(props_list, function(a, b)
      return a.priority > b.priority
    end)
    local max_signs_per_row = get_variable('scrollview_max_signs_per_row', winnr)
    if max_signs_per_row >= 0 then
      props_list = slice(props_list, 1, max_signs_per_row, 1)
    end
    -- A set of 'row,col' pairs to prevent creating multiple signs in the same
    -- location.
    local shown = {}
    for idx, properties in ipairs(props_list) do
      local offset = idx - 1
      if get_variable('scrollview_sign_overflow', winnr) == 'left' then
        offset = -offset
      end
      local col = base_col + offset
      if to_bool(get_variable('scrollview_out_of_bounds_adjust', winnr)) then
        local winwidth = fn.winwidth(winnr)
        col = math.max(1, math.min(winwidth, col))
      end
      if is_valid_column(winid, col) and not shown[row .. ',' .. col] then
        shown[row .. ',' .. col] = true
        local zindex = get_variable('scrollview_sign_zindex', winnr)
        local config = {
          win = winid,
          relative = 'win',
          focusable = false,
          style = 'minimal',
          height = 1,
          width = 1,
          row = row - 1,
          col = col - 1,
          zindex = zindex,
        }
        if sign_bufnr == -1 or not to_bool(fn.bufexists(sign_bufnr)) then
          sign_bufnr = api.nvim_create_buf(false, true)
          api.nvim_buf_set_option(sign_bufnr, 'modifiable', false)
          api.nvim_buf_set_option(sign_bufnr, 'filetype', 'scrollview_sign')
          api.nvim_buf_set_option(sign_bufnr, 'buftype', 'nofile')
          api.nvim_buf_set_option(sign_bufnr, 'swapfile', false)
          api.nvim_buf_set_option(sign_bufnr, 'bufhidden', 'hide')
          api.nvim_buf_set_option(sign_bufnr, 'buflisted', false)
        end
        local sign_line_count = api.nvim_buf_line_count(sign_bufnr)
        api.nvim_buf_set_option(sign_bufnr, 'modifiable', true)
        local symbol = properties.symbol
        if symbol == nil then symbol = vim.g['scrollview_sign_symbol'] end
        symbol = symbol:gsub('\n', '')
        symbol = symbol:gsub('\r', '')
        if #symbol < 1 then symbol = ' ' end
        symbol = vim.fn.strcharpart(symbol, 0, 1)
        api.nvim_buf_set_lines(
          sign_bufnr,
          sign_line_count - 1,
          sign_line_count - 1,
          false,
          {symbol}
        )
        api.nvim_buf_set_option(sign_bufnr, 'modifiable', false)
        local highlight = properties.highlight
        if highlight ~= nil then
          api.nvim_buf_add_highlight(
            sign_bufnr, hl_namespace, highlight, sign_line_count - 1, 0, -1)
        end
        local sign_winid
        if vim.tbl_isempty(sign_winids) then
          sign_winid = api.nvim_open_win(sign_bufnr, false, config)
        else
          sign_winid = table.remove(sign_winids)
          api.nvim_win_set_config(sign_winid, config)
        end
        -- Scroll to the inserted line.
        local args = sign_winid .. ', [' .. sign_line_count .. ', 0]'
        vim.cmd('keepjumps call nvim_win_set_cursor(' .. args .. ')')
        local winhighlight = 'Normal:Normal'
        set_window_option(sign_winid, 'winhighlight', winhighlight)
        local winblend = get_variable('scrollview_winblend', winnr)
        set_window_option(sign_winid, 'winblend', winblend)
        -- Normal highlighting is ignored for floating windows in Neovim 0.8
        -- (Neovim #22906) and fixed for Neovim 0.9. There's a workaround.
        if to_bool(fn.has('nvim-0.8')) and not to_bool(fn.has('nvim-0.9')) then
          api.nvim_win_set_hl_ns(sign_winid, hl_namespace)
        end
        set_window_option(sign_winid, 'foldcolumn', '0')  -- foldcolumn takes a string
        set_window_option(sign_winid, 'foldenable', false)
        set_window_option(sign_winid, 'wrap', false)
        api.nvim_win_set_var(sign_winid, win_var, win_val)
        api.nvim_win_set_var(sign_winid, pending_async_removal_var, false)
        local props = {
          type = sign_type,
          parent_winid = winid,
          scrollview_winid = sign_winid,
          row = row,
          col = col,
          lines = properties.lines,
          zindex = zindex,
        }
        api.nvim_win_set_var(sign_winid, props_var, props)
      end
    end
  end
end

-- Given a scrollbar properties dictionary and a target window row, the
-- corresponding scrollbar is moved to that row. The row is adjusted (up in
-- value, down in visual position) such that the full height of the scrollbar
-- remains on screen. Returns the updated scrollbar properties.
local move_scrollbar = function(props, row)
  props = copy(props)
  local max_row = get_window_height(props.parent_winid) - props.height + 1
  row = math.min(row, max_row)
  local options = {
    win = props.parent_winid,
    relative = 'win',
    row = row - 1,
    col = props.col - 1
  }
  api.nvim_win_set_config(props.scrollview_winid, options)
  props.row = row
  api.nvim_win_set_var(props.scrollview_winid, props_var, props)
  return props
end

local get_scrollview_windows = function()
  local result = {}
  for winnr = 1, fn.winnr('$') do
    local winid = fn.win_getid(winnr)
    if is_scrollview_window(winid) then
      table.insert(result, winid)
    end
  end
  return result
end

local close_scrollview_window = function(winid)
  -- The floating window may have been closed (e.g., :only/<ctrl-w>o, or
  -- intentionally deleted prior to the removal callback in order to reduce
  -- motion blur).
  if not api.nvim_win_is_valid(winid) then
    return
  end
  if not is_scrollview_window(winid) then
    return
  end
  vim.cmd('silent! noautocmd call nvim_win_close(' .. winid .. ', 1)')
end

-- Returns a dictionary mapping winid to topline for the ordinary windows in
-- the current tab.
local get_toplines = function()
  local result = {}
  local tabnr = fn.tabpagenr()
  for _, info in ipairs(fn.getwininfo()) do
    local winid = info.winid
    if info.tabnr == tabnr and is_ordinary_window(winid) then
      result[winid] = info.topline
    end
  end
  return result
end

-- Like the built-in winrestcmd, but ignores floating/external windows.
local winrestcmd2 = function()
  local cmds = fn.split(fn.winrestcmd(), '|')
  local filtered = {}
  for _, cmd in ipairs(cmds) do
    local winnr = string.match(cmd, '%d+')
    if winnr ~= nil and is_ordinary_window(fn.win_getid(winnr)) then
      table.insert(filtered, cmd)
    end
  end
  return fn.join(filtered, '|')
end

-- Sets global state that is assumed by the core functionality and returns a
-- state that can be used for restoration.
local init = function()
  local eventignore = api.nvim_get_option('eventignore')
  api.nvim_set_option('eventignore', 'all')
  -- It's possible that window views can change as a result of moving the
  -- cursor across windows throughout nvim-scrollview processing (Issue #43).
  -- Toplines are saved so that the views can be restored in s:Restore.
  -- winsaveview/winrestview would be insufficient to restore views (vim Issue
  -- #8654).
  -- XXX: Because window views can change, scrollbars could be positioned
  -- slightly incorrectly when that happens since they would correspond to the
  -- (temporarily) shifted view. A possible workaround could be to 1)
  -- temporarily set scrolloff to 0 (both global and local scrolloff options)
  -- for the duration of processing, or 2) update nvim-scrollview so that it
  -- uses win_execute for all functionality and never has to change windows,
  -- preventing the shifted views from occurring.
  local state = {
    previous_winid = fn.win_getid(fn.winnr('#')),
    initial_winid = fn.win_getid(fn.winnr()),
    belloff = api.nvim_get_option('belloff'),
    eventignore = eventignore,
    winwidth = api.nvim_get_option('winwidth'),
    winheight = api.nvim_get_option('winheight'),
    winrestcmd = winrestcmd2(),
    mode = fn.mode(),
    toplines = get_toplines()
  }
  -- Disable the bell (e.g., for invalid cursor movements, trying to navigate
  -- to a next fold, when no fold exists).
  api.nvim_set_option('belloff', 'all')
  -- Minimize winwidth and winheight so that changing the current window
  -- doesn't unexpectedly cause window resizing.
  api.nvim_set_option(
    'winwidth', math.max(1, api.nvim_get_option('winminwidth')))
  api.nvim_set_option(
    'winheight', math.max(1, api.nvim_get_option('winminheight')))
  if is_select_mode(state.mode) then
    -- Temporarily switch from select-mode to visual-mode, so that 'normal!'
    -- commands can be executed properly.
    vim.cmd('normal! ' .. t'<c-g>')
  end
  return state
end

local restore = function(state, restore_toplines)
  -- Restore the previous window so that <c-w>p and winnr('#') function as
  -- expected, and so that plugins that utilize previous windows (e.g., CtrlP)
  -- function properly. If the current window is the same as the initial
  -- window, set the same previous window. If the current window differs from
  -- the initial window, use the initial window for setting the previous
  -- window.
  -- WARN: Since the current window is changed, 'eventignore' should not be
  -- restored until after.
  if restore_toplines == nil then restore_toplines = true end
  local current_winid = fn.win_getid(fn.winnr())
  pcall(function()
    local previous_winid = state.previous_winid
    if current_winid ~= state.initial_winid then
      previous_winid = state.initial_winid
    end
    local previous_winnr = api.nvim_win_get_number(previous_winid)
    if fn.winnr('#') ~= previous_winnr then
      api.nvim_set_current_win(previous_winid)
      api.nvim_set_current_win(current_winid)
    end
  end)
  -- Switch back to select mode where applicable.
  if current_winid == state.initial_winid then
    if is_select_mode(state.mode) then
      if is_visual_mode(fn.mode()) then
        vim.cmd('normal! ' .. t'<c-g>')
      else  -- luacheck: ignore 542 (an empty if branch)
        -- WARN: this scenario should not arise, and is not handled.
      end
    end
  end
  -- Restore options.
  api.nvim_set_option('winwidth', state.winwidth)
  api.nvim_set_option('winheight', state.winheight)
  -- After restoring winwidth and winheight, restore window sizes (#76). This
  -- is intentionally done before restoring toplines, else it's possible for a
  -- non-current window to scroll. To replicate such scrolling (which requires
  -- moving the following line later):
  --   :vert split
  --   :set winwidth=130
  --   :vert resize -30
  --   :execute "normal! \<c-d>"
  if winrestcmd2() ~= state.winrestcmd then
    -- Only restore if winrestcmd changed. #79
    api.nvim_command(state.winrestcmd)
  end
  if restore_toplines then
    -- Scroll windows back to their original positions.
    -- Temporarily disable cursorbind/scrollbind to prevent unintended
    -- scrolling (Issue #68).
    local opts = {
      cursorbind = false,
      scrollbind = false,
    }
    for winid, topline in pairs(state.toplines) do
      -- The number of scrolls is limited as a precaution against entering an
      -- infinite loop.
      local countdown = topline - fn.getwininfo(winid)[1].topline
      while countdown > 0 and fn.getwininfo(winid)[1].topline < topline do
        -- Can't use set_topline, since that function changes the current
        -- window, and would result in the same problem that is intended to be
        -- solved here.
        with_win_options(winid, opts, function()
          vim.cmd('keepjumps normal! ' .. t'<c-e>')
        end)
        countdown = countdown - 1
      end
    end
  end
  -- 'set title' when 'title' is on, so it's properly set. #84
  if api.nvim_get_option('title') then
    api.nvim_set_option('title', true)
  end
  api.nvim_set_option('eventignore', state.eventignore)
  api.nvim_set_option('belloff', state.belloff)
end

-- Get input characters---including mouse clicks and drags---from the input
-- stream. Characters are read until the input stream is empty. Returns a
-- 2-tuple with a string representation of the characters, along with a list of
-- dictionaries that include the following fields:
--   1) char
--   2) str_idx
--   3) charmod
--   4) mouse_winid
--   5) mouse_row
--   6) mouse_col
-- The mouse values are 0 when there was no mouse event or getmousepos is not
-- available. The mouse_winid is set to -1 when a mouse event was on the
-- command line. The mouse_winid is set to -2 when a mouse event was on the
-- tabline.
local read_input_stream = function()
  local chars = {}
  local chars_props = {}
  local str_idx = 1  -- in bytes, 1-indexed
  while true do
    local char
    if not pcall(function()
      char = fn.getchar()
    end) then
      -- E.g., <c-c>
      char = t'<esc>'
    end
    -- For Vim on Cygwin, pressing <c-c> during getchar() does not raise
    -- "Vim:Interrupt". Handling for such a scenario is added here as a
    -- precaution, by converting to <esc>.
    if char == t'<c-c>' then
      char = t'<esc>'
    end
    local charmod = fn.getcharmod()
    if type(char) == 'number' then
      char = tostring(char)
    end
    table.insert(chars, char)
    local mouse_winid = 0
    local mouse_row = 0
    local mouse_col = 0
    -- Check v:mouse_winid to see if there was a mouse event. Even for clicks
    -- on the command line, where getmousepos().winid could be zero,
    -- v:mousewinid is non-zero.
    if vim.v.mouse_winid ~= 0 and to_bool(fn.exists('*getmousepos')) then
      mouse_winid = vim.v.mouse_winid
      local mousepos = fn.getmousepos()
      mouse_row = mousepos.winrow
      mouse_col = mousepos.wincol
      -- Handle a mouse event on the command line.
      if mousepos.screenrow > vim.go.lines - vim.go.cmdheight then
        mouse_winid = -1
        mouse_row = mousepos.screenrow - vim.go.lines + vim.go.cmdheight
        mouse_col = mousepos.screencol
      end
      -- Handle a mouse event on the tabline. When the click is on a floating
      -- window covering the tabline, mousepos.winid will be set to that
      -- floating window's winid. Otherwise, mousepos.winid would correspond to
      -- an ordinary window ID (seemingly for the window below the tabline).
      if fn.win_screenpos(1) == {2, 1}  -- Checks for presence of a tabline.
          and mousepos.screenrow == 1
          and is_ordinary_window(mousepos.winid) then
        mouse_winid = -2
        mouse_row = mousepos.screenrow
        mouse_col = mousepos.screencol
      end
      -- Handle mouse events when there is a winbar.
      if mouse_winid > 0
          and to_bool(tbl_get(fn.getwininfo(mouse_winid)[1], 'winbar', 0)) then
        mouse_row = mouse_row - 1
      end
    end
    local char_props = {
      char = char,
      str_idx = str_idx,
      charmod = charmod,
      mouse_winid = mouse_winid,
      mouse_row = mouse_row,
      mouse_col = mouse_col
    }
    str_idx = str_idx + string.len(char)
    table.insert(chars_props, char_props)
    -- Break if there are no more items on the input stream.
    if fn.getchar(1) == 0 then
      break
    end
  end
  local string = table.concat(chars, '')
  local result = {string, chars_props}
  return unpack(result)
end

-- Scrolls the window so that the specified line number is at the top.
local set_topline = function(winid, linenr)
  -- WARN: Unlike other functions that move the cursor (e.g., VirtualLineCount,
  -- VirtualProportionLine), a window workspace should not be used, as the
  -- cursor and viewport changes here are intended to persist.
  api.nvim_win_call(winid, function()
    local init_line = fn.line('.')
    vim.cmd('keepjumps normal! ' .. linenr .. 'G')
    local topline, _ = line_range(winid)
    -- Use virtual lines to figure out how much to scroll up. winline() doesn't
    -- accommodate wrapped lines.
    local virtual_line = virtual_line_count(winid, topline, fn.line('.'))
    if virtual_line > 1 then
      vim.cmd('keepjumps normal! ' .. (virtual_line - 1) .. t'<c-e>')
    end
    -- Make sure 'topline' is correct, as a precaution.
    topline = nil  -- luacheck: no unused
    local _, botline = line_range(winid)
    if botline == fn.line('$') then
      -- If the last buffer line is on-screen, position that line at the bottom
      -- of the window.
      vim.cmd('keepjumps normal! Gzb')
    end
    -- Position the cursor as if all scrolling was conducted with <ctrl-e> and/or
    -- <ctrl-y>. H and L are used to get topline and botline instead of
    -- getwininfo, to prevent jumping to a line that could result in a scroll if
    -- scrolloff>0.
    vim.cmd('keepjumps normal! H')
    local effective_top = fn.line('.')
    vim.cmd('keepjumps normal! L')
    local effective_bottom = fn.line('.')
    if init_line < effective_top then
      -- User scrolled down.
      vim.cmd('keepjumps normal! H')
    elseif init_line > effective_bottom then
      -- User scrolled up.
      vim.cmd('keepjumps normal! L')
    else
      -- The initial line is still on-screen.
      vim.cmd('keepjumps normal! ' .. init_line .. 'G')
    end
  end)
end

-- Returns scrollview bar properties for the specified window. An empty
-- dictionary is returned if there is no corresponding scrollbar.
local get_scrollview_bar_props = function(winid)
  for _, scrollview_winid in ipairs(get_scrollview_windows()) do
    local props = api.nvim_win_get_var(scrollview_winid, props_var)
    if props.type == bar_type and props.parent_winid == winid then
      return props
    end
  end
  return {}
end

-- Returns a list of scrollview sign properties for the specified scrollbar
-- window. An empty list is returned if there are no signs.
local get_scrollview_sign_props = function(winid)
  local result = {}
  for _, scrollview_winid in ipairs(get_scrollview_windows()) do
    local props = api.nvim_win_get_var(scrollview_winid, props_var)
    if props.type == sign_type and props.parent_winid == winid then
      table.insert(result, props)
    end
  end
  return result
end

-- With no argument, remove all bars. Otherwise, remove the specified list of
-- bars. Global state is initialized and restored.
local remove_bars = function(target_wins)
  if target_wins == nil then target_wins = get_scrollview_windows() end
  if bar_bufnr == -1 and sign_bufnr == -1 then return end
  local state = init()
  pcall(function()
    for _, winid in ipairs(target_wins) do
      close_scrollview_window(winid)
    end
  end)
  restore(state)
end

-- Remove scrollbars if InCommandLineWindow is true. This fails when called
-- from the CmdwinEnter event (some functionality, like nvim_win_close, cannot
-- be used from the command line window), but works during the transition to
-- the command line window (from the WinEnter event).
local remove_if_command_line_window = function()
  if in_command_line_window() then
    pcall(remove_bars)
  end
end

-- Refreshes scrollbars. There is an optional argument that specifies whether
-- removing existing scrollbars is asynchronous (defaults to true). Global
-- state is initialized and restored.
local refresh_bars = function(async_removal)
  if async_removal == nil then async_removal = true end
  local state = init()
  -- Use a pcall block, so that unanticipated errors don't interfere. The
  -- worst case scenario is that bars won't be shown properly, which was
  -- deemed preferable to an obscure error message that can be interrupting.
  start_memoize()
  pcall(function()
    if in_command_line_window() then return end
    -- Don't refresh when the current window shows a scrollview buffer. This
    -- could cause a loop where TextChanged keeps firing.
    for _, scrollview_bufnr in ipairs({sign_bufnr, bar_bufnr}) do
      if scrollview_bufnr ~= -1 and to_bool(fn.bufexists(scrollview_bufnr)) then
        local windows = fn.getbufinfo(scrollview_bufnr)[1].windows
        if vim.tbl_contains(windows, fn.win_getid(fn.winnr())) then
          return
        end
      end
    end
    -- Remove any scrollbars that are pending asynchronous removal. This
    -- reduces the appearance of motion blur that results from the accumulation
    -- of windows for asynchronous removal (e.g., when CPU utilization is
    -- high).
    for _, winid in ipairs(get_scrollview_windows()) do
      if to_bool(api.nvim_win_get_var(winid, pending_async_removal_var)) then
        close_scrollview_window(winid)
      end
    end
    -- Existing windows are determined before adding new windows, but removed
    -- later (they have to be removed after adding to prevent flickering from
    -- the delay between removal and adding).
    local existing_barids = {}
    local existing_signids = {}
    for _, winid in ipairs(get_scrollview_windows()) do
      local props = api.nvim_win_get_var(winid, props_var)
      if props.type == bar_type then
        table.insert(existing_barids, winid)
      elseif props.type == sign_type then
        table.insert(existing_signids, winid)
      end
    end
    local target_wins = {}
    if to_bool(get_variable('scrollview_current_only', fn.winnr(), 'tg')) then
      table.insert(target_wins, api.nvim_get_current_win())
    else
      for _, winid in ipairs(get_ordinary_windows()) do
        table.insert(target_wins, winid)
      end
    end
    local eventignore = api.nvim_get_option('eventignore')
    api.nvim_set_option('eventignore', state.eventignore)
    vim.cmd('doautocmd User ScrollViewRefresh')
    api.nvim_set_option('eventignore', eventignore)
    local start_reltime = fn.reltime()
    -- Delete all signs and highlights in the sign buffer.
    if sign_bufnr ~= -1 and to_bool(fn.bufexists(sign_bufnr)) then
      -- Clear existing highlights to prevent memory leak.
      api.nvim_buf_clear_namespace(sign_bufnr, hl_namespace, 0, -1)
      api.nvim_buf_set_option(sign_bufnr, 'modifiable', true)
      fn.deletebufline(sign_bufnr, 1, '$')
      api.nvim_buf_set_option(sign_bufnr, 'modifiable', false)
    end
    for _, winid in ipairs(target_wins) do
      if should_show(winid) then
        local existing_winid = -1
        if not vim.tbl_isempty(existing_barids) then
          -- Reuse an existing scrollbar floating window when available. This
          -- prevents flickering when there are folds. This keeps the window IDs
          -- smaller than they would be otherwise. The benefits of small window
          -- IDs seems relatively less beneficial than small buffer numbers,
          -- since they would ordinarily be used less as inputs to commands
          -- (where smaller numbers are preferable for their fewer digits to
          -- type).
          existing_winid = existing_barids[#existing_barids]
        end
        local bar_winid = show_scrollbar(winid, existing_winid)
        -- If an existing window was successfully reused, remove it from the
        -- existing window list.
        if bar_winid ~= -1 and existing_winid ~= -1 then
          table.remove(existing_barids)
        end
        -- Repeat a similar process for signs.
        show_signs(winid, existing_signids)
      end
    end
    -- The elapsed microseconds for showing scrollbars.
    local elapsed_micro = reltime_to_microseconds(fn.reltime(start_reltime))
    if vim.g.scrollview_refresh_time > -1
        and elapsed_micro > vim.g.scrollview_refresh_time * 1000 then
      vim.g.scrollview_refresh_time_exceeded = 1
    end
    local existing_wins = concat(existing_barids, existing_signids)
    if vim.tbl_isempty(existing_wins) then  -- luacheck: ignore 542 (empty if)
      -- Do nothing. The following clauses are only applicable when there are
      -- existing windows. Skipping prevents the creation of an unnecessary
      -- timer.
    elseif async_removal then
      -- Remove bars asynchronously to prevent flickering (this may help when
      -- there are folds and mode='virtual' in some cases). Even when
      -- nvim_win_close is called synchronously after the code that adds the
      -- other windows, the window removal still happens earlier in time, as
      -- confirmed by using 'writedelay'. Even with asynchronous execution, the
      -- call to vim.defer_fn must still occur after the code for the window
      -- additions.
      -- - remove_bars is used instead of close_scrollview_window for global
      --   state initialization and restoration.
      for _, winid in ipairs(existing_wins) do
        api.nvim_win_set_var(winid, pending_async_removal_var, true)
      end
      vim.defer_fn(function()
        remove_bars(existing_wins)
      end, 0)
    else
      for _, winid in ipairs(existing_wins) do
        close_scrollview_window(winid)
      end
    end
  end)
  stop_memoize()
  reset_memoize()
  restore(state)
end

-- This function refreshes the bars asynchronously. This works better than
-- updating synchronously in various scenarios where updating occurs in an
-- intermediate state of the editor (e.g., when closing a command-line window),
-- which can result in bars being placed where they shouldn't be.
-- WARN: For debugging, it's helpful to use synchronous refreshing, so that
-- e.g., echom works as expected.
local refresh_bars_async = function()
  pending_async_refresh_count = pending_async_refresh_count + 1
  -- Use defer_fn twice so that refreshing happens after other processing. Issue #59.
  vim.defer_fn(function()
    vim.defer_fn(function()
      pending_async_refresh_count = math.max(0, pending_async_refresh_count - 1)
      if pending_async_refresh_count > 0 then
        -- If there are asynchronous refreshes that will occur subsequently,
        -- don't execute this one.
        return
      end
      -- ScrollView may have already been disabled by time this callback executes
      -- asynchronously.
      if scrollview_enabled then
        refresh_bars()
      end
    end, 0)
  end, 0)
end

-- *************************************************
-- * Main (entry points)
-- *************************************************

-- INFO: Asynchronous refreshing was originally used to work around issues
-- (e.g., getwininfo(winid)[1].botline not updated yet in a synchronous
-- context). However, it's now primarily utilized because it makes the UI more
-- responsive and it permits redundant refreshes to be dropped (e.g., for mouse
-- wheel scrolling).

local scrollview_enable = function()
  scrollview_enabled = true
  vim.cmd([[
    augroup scrollview
      autocmd!
      " === Scrollbar Removal ===

      " For the duration of command-line window usage, there should be no bars.
      " Without this, bars can possibly overlap the command line window. This
      " can be problematic particularly when there is a vertical split with the
      " left window's bar on the bottom of the screen, where it would overlap
      " with the center of the command line window. It was not possible to use
      " CmdwinEnter, since the removal has to occur prior to that event. Rather,
      " this is triggered by the WinEnter event, just prior to the relevant
      " funcionality becoming unavailable.
      autocmd WinEnter * :lua require('scrollview').remove_if_command_line_window()

      " The following error can arise when the last window in a tab is going to
      " be closed, but there are still open floating windows, and at least one
      " other tab.
      "   > "E5601: Cannot close window, only floating window would remain"
      " Neovim Issue #11440 is open to address this. As of 2020/12/12, this
      " issue is a 0.6 milestone.
      " The autocmd below removes bars subsequent to :quit, :wq, or :qall (and
      " also ZZ and ZQ), to avoid the error. However, the error will still arise
      " when <ctrl-w>c or :close are used. To avoid the error in those cases,
      " <ctrl-w>o can be used to first close the floating windows, or
      " alternatively :tabclose can be used (or one of the alternatives handled
      " with the autocmd, like ZQ).
      autocmd QuitPre * :lua require('scrollview').remove_bars()

      " === Scrollbar Refreshing ===

      " The following handles bar refreshing when changing the current window.
      autocmd WinEnter,TermEnter * :lua require('scrollview').refresh_bars_async()

      " The following restores bars after leaving the command-line window.
      " Refreshing must be asynchronous, since the command line window is still
      " in an intermediate state when the CmdwinLeave event is triggered.
      autocmd CmdwinLeave * :lua require('scrollview').refresh_bars_async()

      " The following handles scrolling events, which could arise from various
      " actions, including resizing windows, movements (e.g., j, k), or
      " scrolling (e.g., <ctrl-e>, zz).
      autocmd WinScrolled * :lua require('scrollview').refresh_bars_async()

      " The following handles window resizes that don't trigger WinScrolled
      " (e.g., leaving the command line window). This was added in Neovim 0.9,
      " so its presence needs to be tested.
      if exists('##WinResized')
        autocmd WinResized * :lua require('scrollview').refresh_bars_async()
      endif

      " The following handles the case where text is pasted. TextChangedI is not
      " necessary since WinScrolled will be triggered if there is corresponding
      " scrolling.
      autocmd TextChanged * :lua require('scrollview').refresh_bars_async()

      " The following handles when :e is used to load a file. The asynchronous
      " version handles a case where :e is used to reload an existing file, that
      " is already scrolled. This avoids a scenario where the scrollbar is
      " refreshed while the window is an intermediate state, resulting in the
      " scrollbar moving to the top of the window.
      autocmd BufWinEnter * :lua require('scrollview').refresh_bars_async()

      " The following is used so that bars are shown when cycling through tabs.
      autocmd TabEnter * :lua require('scrollview').refresh_bars_async()

      autocmd VimResized * :lua require('scrollview').refresh_bars_async()

      " Scrollbar positions can become stale after adding or removing winbars.
      autocmd OptionSet winbar :lua require('scrollview').refresh_bars_async()
    augroup END
  ]])
  -- The initial refresh is asynchronous, since :ScrollViewEnable can be used
  -- in a context where Neovim is in an intermediate state. For example, for
  -- ':bdelete | ScrollViewEnable', with synchronous processing, the 'topline'
  -- and 'botline' in getwininfo's results correspond to the existing buffer
  -- that :bdelete was called on.
  refresh_bars_async()
end

local scrollview_disable = function()
  local winid = api.nvim_get_current_win()
  local state = init()
  pcall(function()
    if in_command_line_window() then
      vim.cmd([[
        echohl ErrorMsg
        echo 'nvim-scrollview: Cannot disable from command-line window'
        echohl None
      ]])
      return
    end
    scrollview_enabled = false
    vim.cmd([[
      augroup scrollview
        autocmd!
      augroup END
    ]])
    -- Remove scrollbars from all tabs.
    for _, tabnr in ipairs(api.nvim_list_tabpages()) do
      api.nvim_set_current_tabpage(tabnr)
      pcall(remove_bars)
    end
  end)
  api.nvim_set_current_win(winid)
  restore(state)
end

local scrollview_refresh = function()
  if scrollview_enabled then
    -- This refresh is asynchronous to keep interactions responsive (e.g.,
    -- mouse wheel scrolling, as redundant async refreshes are dropped). If
    -- scenarios necessitate synchronous refreshes, the interface would have to
    -- be updated (e.g., :ScrollViewRefresh --sync) to accommodate (as there is
    -- currently only a single refresh command and a single refresh <plug>
    -- mapping, both utilizing whatever is implemented here).
    refresh_bars_async()
  end
end

-- 'button' can be 'left', 'middle', 'right', 'x1', or 'x2'.
local handle_mouse = function(button)
  if not vim.tbl_contains({'left', 'middle', 'right', 'x1', 'x2'}, button) then
    error('Unsupported button: ' .. button)
  end
  local mousedown = t('<' .. button .. 'mouse>')
  local mouseup = t('<' .. button .. 'release>')
  if not scrollview_enabled then
    -- nvim-scrollview is disabled. Process the click as it would ordinarily be
    -- processed, by re-sending the click and returning.
    fn.feedkeys(mousedown, 'ni')
    return
  end
  local state = init()
  local restore_toplines = true
  pcall(function()
    -- Re-send the click, so its position can be obtained through
    -- read_input_stream().
    fn.feedkeys(mousedown, 'ni')
    -- Mouse handling is not relevant in the command line window since
    -- scrollbars are not shown. Additionally, the overlay cannot be closed
    -- from that mode.
    if in_command_line_window() then
      return
    end
    local count = 0
    local winid  -- The target window ID for a mouse scroll.
    local bufnr  -- The target buffer number.
    local scrollbar_offset
    local previous_row
    local idx = 1
    local string, chars_props = '', {}
    local str_idx, char, mouse_winid, mouse_row, mouse_col
    local props
    -- Computing this prior to the first mouse event could distort the location
    -- since this could be an expensive operation (and the mouse could move).
    local the_topline_lookup = nil
    while true do
      while true do
        idx = idx + 1
        if idx > #chars_props then
          idx = 1
          string, chars_props = read_input_stream()
        end
        local char_props = chars_props[idx]
        str_idx = char_props.str_idx
        char = char_props.char
        mouse_winid = char_props.mouse_winid
        mouse_row = char_props.mouse_row
        mouse_col = char_props.mouse_col
        -- Break unless it's a mouse drag followed by another mouse drag, so
        -- that the first drag is skipped.
        if mouse_winid == 0
            or vim.tbl_contains({mousedown, mouseup}, char) then
          break
        end
        if idx >= #char_props then break end
        local next = chars_props[idx + 1]
        if next.mouse_winid == 0
            or vim.tbl_contains({mousedown, mouseup}, next.char) then
          break
        end
      end
      if char == t'<esc>' then
        fn.feedkeys(string.sub(string, str_idx + #char), 'ni')
        return
      end
      -- In select-mode, mouse usage results in the mode intermediately
      -- switching to visual mode, accompanied by a call to this function.
      -- After the initial mouse event, the next getchar() character is
      -- <80><f5>X. This is "Used for switching Select mode back on after a
      -- mapping or menu" (https://github.com/vim/vim/blob/
      -- c54f347d63bcca97ead673d01ac6b59914bb04e5/src/keymap.h#L84-L88,
      -- https://github.com/vim/vim/blob/
      -- c54f347d63bcca97ead673d01ac6b59914bb04e5/src/getchar.c#L2660-L2672)
      -- Ignore this character after scrolling has started.
      -- NOTE: "\x80\xf5X" (hex) ==# "\200\365X" (octal)
      if char ~= '\x80\xf5X' or count == 0 then
        if mouse_winid == 0 then
          -- There was no mouse event.
          fn.feedkeys(string.sub(string, str_idx), 'ni')
          return
        end
        if char == mouseup then
          if count == 0 then
            -- No initial mousedown was captured.
            fn.feedkeys(string.sub(string, str_idx), 'ni')
          elseif count == 1 then
            -- A scrollbar was clicked, but there was no corresponding drag.
            -- Allow the interaction to be processed as it would be with no
            -- scrollbar.
            fn.feedkeys(mousedown .. string.sub(string, str_idx), 'ni')
          else
            -- A scrollbar was clicked and there was a corresponding drag.
            -- 'feedkeys' is not called, since the full mouse interaction has
            -- already been processed. The current window (from prior to
            -- scrolling) is not changed.
            -- Refresh scrollbars to handle the scenario where
            -- scrollview_hide_on_intersect is enabled and dragging resulted in a
            -- scrollbar overlapping a floating window.
            refresh_bars(false)
          end
          return
        end
        if count == 0 then
          if mouse_winid < 0 then
            -- The mouse event was on the tabline or command line.
            fn.feedkeys(string.sub(string, str_idx), 'ni')
            return
          end
          props = get_scrollview_bar_props(mouse_winid)
          local clicked_bar = false
          if not vim.tbl_isempty(props) then
            clicked_bar = mouse_row >= props.row
              and mouse_row < props.row + props.height
              and mouse_col >= props.col
              and mouse_col <= props.col
          end
          -- First check for a click on a sign and handle accordingly.
          for _, sign_props in pairs(get_scrollview_sign_props(mouse_winid)) do
            if mouse_row == sign_props.row
              and mouse_col >= sign_props.col
              and mouse_col <= sign_props.col
              and (not clicked_bar or sign_props.zindex > props.zindex) then
              restore_toplines = false
              api.nvim_win_call(mouse_winid, function()
                -- Go to the next sign_props line after the cursor.
                local current = fn.line('.')
                local target_idx = binary_search(sign_props.lines, current)
                if target_idx <= #sign_props.lines
                    and sign_props.lines[target_idx] == current then
                  target_idx = target_idx + 1  -- use the next line
                end
                if target_idx > #sign_props.lines then
                  target_idx = 1
                end
                local target = sign_props.lines[target_idx]
                vim.cmd('normal!' .. target .. 'G')
                vim.cmd('normal! zz')
              end)
              refresh_bars(false)
              return
            end
          end
          if not clicked_bar then
            -- There was either no scrollbar in the window where a click
            -- occurred or the click was not on a scrollbar.
            fn.feedkeys(string.sub(string, str_idx), 'ni')
            return
          end
          -- The click was on a scrollbar.
          -- It's possible that the clicked scrollbar is out-of-sync. Refresh the
          -- scrollbars and check if the mouse is still over a scrollbar. If not,
          -- ignore all mouse events until a mouseup. This approach was deemed
          -- preferable to refreshing scrollbars initially, as that could result
          -- in unintended clicking/dragging where there is no scrollbar.
          refresh_bars(false)
          vim.cmd('redraw')
          -- Don't restore toplines whenever a scrollbar was clicked. This
          -- prevents the window where a scrollbar is dragged from having its
          -- topline restored to the pre-drag position. This also prevents
          -- restoring windows that may have had their windows shifted during the
          -- course of scrollbar clicking/dragging, to prevent jumpiness in the
          -- display.
          restore_toplines = false
          props = get_scrollview_bar_props(mouse_winid)
          if vim.tbl_isempty(props)
              or props.type ~= bar_type
              or mouse_row < props.row
              or mouse_row >= props.row + props.height then
            while fn.getchar() ~= mouseup do end
            return
          end
          -- By this point, the click on a scrollbar was successful.
          if is_visual_mode(fn.mode()) then
            -- Exit visual mode.
            vim.cmd('normal! ' .. t'<esc>')
          end
          winid = mouse_winid
          bufnr = api.nvim_win_get_buf(winid)
          scrollbar_offset = props.row - mouse_row
          previous_row = props.row
        end
        -- Only consider a scrollbar update for mouse events on windows (i.e.,
        -- not on the tabline or command line).
        if mouse_winid > 0 then
          local winheight = get_window_height(winid)
          local mouse_winrow = fn.getwininfo(mouse_winid)[1].winrow
          local winrow = fn.getwininfo(winid)[1].winrow
          local window_offset = mouse_winrow - winrow
          local row = mouse_row + window_offset + scrollbar_offset
          row = math.min(row, winheight - props.height + 1)
          row = math.max(1, row)
          -- Only update scrollbar if the row changed.
          if previous_row ~= row then
            if the_topline_lookup == nil then
              the_topline_lookup = topline_lookup(winid)
            end
            local topline = the_topline_lookup[row]
            topline = math.max(1, topline)
            if row == 1 then
              -- If the scrollbar was dragged to the top of the window, always show
              -- the first line.
              topline = 1
            elseif row + props.height - 1 >= winheight then
              -- If the scrollbar was dragged to the bottom of the window, always
              -- show the bottom line.
              topline = api.nvim_buf_line_count(bufnr)
            end
            set_topline(winid, topline)
            if api.nvim_win_get_option(winid, 'scrollbind')
                or api.nvim_win_get_option(winid, 'cursorbind') then
              refresh_bars(false)
              props = get_scrollview_bar_props(winid)
            end
            props = move_scrollbar(props, row)
            vim.cmd('redraw')
            previous_row = row
          end
        end
        count = count + 1
      end  -- end if
    end  -- end while
  end)  -- end pcall
  restore(state, restore_toplines)
end

-- A convenience function for setting global options with
-- require('scrollview').setup().
local setup = function(opts)
  opts = opts or {}
  for key, val in pairs(opts) do
    if type(val) == 'boolean' then
      val = val and 1 or 0
    end
    api.nvim_set_var('scrollview_' .. key, val)
  end
end

-- *************************************************
-- * API
-- *************************************************

return {
  -- Functions called internally (by autocmds).
  refresh_bars_async = refresh_bars_async,
  remove_bars = remove_bars,
  remove_if_command_line_window = remove_if_command_line_window,

  -- Functions called by commands and mappings defined in
  -- plugin/scrollview.vim, and sign handlers.
  scrollview_enable = scrollview_enable,
  scrollview_disable = scrollview_disable,
  scrollview_refresh = scrollview_refresh,
  get_ordinary_windows = get_ordinary_windows,
  get_variable = get_variable,
  handle_mouse = handle_mouse,
  with_win_workspace = with_win_workspace,

  -- Functions called by tests.
  virtual_line_count_spanwise = virtual_line_count_spanwise,
  virtual_line_count_linewise = virtual_line_count_linewise,
  virtual_topline_lookup_spanwise = virtual_topline_lookup_spanwise,
  virtual_topline_lookup_linewise = virtual_topline_lookup_linewise,
  simple_topline_lookup = simple_topline_lookup,

  -- require('scrollview').setup()
  setup = setup,
}
