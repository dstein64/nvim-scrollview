local api = vim.api
local fn = vim.fn
-- vim.tbl_islist was deprecated in Neovim v0.10. #131
local islist = vim.islist or vim.tbl_islist

local utils = require('scrollview.utils')
local binary_search = utils.binary_search
local concat = utils.concat
local copy = utils.copy
local echo = utils.echo
local preceding = utils.preceding
local remove_duplicates = utils.remove_duplicates
local round = utils.round
local sorted = utils.sorted
local subsequent = utils.subsequent
local t = utils.t
local tbl_get = utils.tbl_get
local to_bool = utils.to_bool

-- WARN: Sometimes 1-indexing is used (primarily for mutual Vim/Neovim API
-- calls) and sometimes 0-indexing (primarily for Neovim-specific API calls).
-- WARN: Don't move the cursor or change the current window. It can have
-- unwanted side effects (e.g., #18, #23, #43, window sizes changing to satisfy
-- winheight/winwidth, etc.).
-- WARN: Functionality that temporarily moves the cursor, or changes the 'wrap'
-- setting should use a window workspace to prevent unwanted side effects. More
-- details are in the documentation for with_win_workspace.
-- XXX: Some of the functionality is applicable to bars and signs, but is
-- named as if it were only applicable to bars (since it was implemented prior
-- to sign support).

-- *************************************************
-- * Forward Declarations
-- *************************************************

-- Declared here since it's used by the earlier legend() function.
local get_sign_groups

-- Declared here since it's used by the earlier refresh_bars() function.
local is_sign_group_active

-- *************************************************
-- * Globals
-- *************************************************

-- Since there is no text displayed in the buffers, the same buffers are used
-- for multiple windows. This also prevents the buffer list from getting high
-- from usage of the plugin.

-- bar_bufnr has the bufnr of the buffer created for a position bar.
local bar_bufnr = -1

-- sign_bufnr has the bufnr of the buffer created for signs.
local sign_bufnr = -1

local popup_bufnr = -1

-- Keep count of pending async refreshes.
local pending_async_refresh_count = 0

-- Keep count of pending mousemove callbacks.
local pending_mousemove_callback_count = 0

-- Tracks whether the handle_mouse function is running.
local handling_mouse = false

-- A window variable is set on each scrollview window, as a way to check for
-- scrollview windows, in addition to matching the scrollview buffer number
-- saved in bar_bufnr. This was preferable versus maintaining a list of window
-- IDs.
local WIN_VAR = 'scrollview_key'
local WIN_VAL = 'scrollview_val'

-- For win workspaces, a window variable is used to store the base window ID.
local WIN_WORKSPACE_BASE_WINID_VAR = 'scrollview_win_workspace_base_winid'

-- Maps window IDs to a corresponding window workspace.
local win_workspace_lookup = {}

-- A type field is used to indicate the type of scrollview windows.
local BAR_TYPE = 0
local SIGN_TYPE = 1

-- A key for saving scrollbar properties using a window variable.
local PROPS_VAR = 'scrollview_props'

-- Maps sign groups to state (enabled or disabled).
local sign_group_state = {}

-- Maps sign groups to refresh callbacks.
local sign_group_callbacks = {}

-- Stores registered sign specifications.
-- WARN: This may seem array-like, but since items can be set to nil by
-- deregister_sign_spec(), it's dictionary-like (use pairs(), not ipairs()).
local sign_specs = {}
-- Keep track of how many sign specifications were registered. This is used for
-- ID assignment, and is not adjusted for deregistrations.
local sign_spec_counter = 0

-- Track whether there has been a <mousemove> occurrence. Hover highlights are
-- only used if this has been set to true. Without this, the bar would be
-- highlighted when being dragged even if the client doesn't support
-- <mousemove> (e.g., nvim-qt), and may retain the wrong highlight after
-- dragging completes if the mouse is still over the bar.
-- WARN: It's possible that Neovim is opened, with the mouse exactly where it
-- needs to be for a user to start dragging without first moving the mouse. In
-- that case, hover highlights should be used, but won't be. This scenario is
-- unlikely.
local mousemove_received = false

local CTRLS = t('<c-s>')
local CTRLV = t('<c-v>')
local MOUSEMOVE = t('<mousemove>')

local SIMPLE_MODE = 0   -- doesn't consider folds nor wrapped lines
local VIRTUAL_MODE = 1  -- considers folds, but not wrapped lines
local PROPER_MODE = 2   -- considers folds and wrapped lines

-- Memoization key prefixes.
local VIRTUAL_LINE_COUNT_KEY_PREFIX = 0
local PROPER_LINE_COUNT_KEY_PREFIX = 1
local TOPLINE_LOOKUP_KEY_PREFIX = 2
local GET_WINDOW_EDGES_KEY_PREFIX = 3
local ROW_LENGTH_LOOKUP_KEY_PREFIX = 4

-- Maps window ID and highlight group to a temporary highlight group with the
-- corresponding definition. This is reset on each refresh cycle.
local highlight_lookup = {}
-- Tracks the number of entries in the preceding table.
local highlight_lookup_size = 0

-- The indices for the array of border elements in the config returned by
-- nvim_win_get_config. The array specifies the eight characters that comprise
-- the border, in a clockwise order starting from the top-left corner.
local BORDER_TOP = 2
local BORDER_RIGHT = 4
local BORDER_BOTTOM = 6
local BORDER_LEFT = 8

-- Maps mouse buttons (e.g., 'left') to the Neovim key representation.
local MOUSE_LOOKUP = (function()
  local valid_buttons = {
    'left', 'middle', 'right', 'x1', 'x2',
    'c-left', 'c-middle', 'c-right', 'c-x1', 'c-x2',
    'm-left', 'm-middle', 'm-right', 'm-x1', 'm-x2',
  }
  local result = {}
  for _, button in ipairs(valid_buttons) do
    result[button] = t('<' .. button .. 'mouse>')
  end
  return result
end)()

-- Fake window IDs are used by read_input_stream for representing the command
-- line and tabline. These are negative so they can be distinguished from
-- valid IDs for actual windows.
local COMMAND_LINE_WINID = -1
local TABLINE_WINID = -2

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
-- * Key Sequence Callbacks
-- *************************************************

-- The max length of all key sequences that have been registered.
local max_key_sequence_length = 0

-- A buffer of recent key sequences, whose size does not exceed
-- max_key_sequence_length.
local active_key_sequence = ''

local last_raw_mode = nil

-- Maps a mode concatenated with a key sequence to a callback.
local key_sequence_callbacks = {}

-- WARN: The modes here do not exactly match mode(), where there is no 'o'
-- mode. Also, these modes do not exactly match the mapping modes (:h
-- map-overview), where 'v' would correspond to both visual and select modes,
-- and 'x' would be for visual mode only.
--   o: Operator-pending
--   n: Normal
--   v: Visual
--   s: Select
--   i: Insert
--   R: Replace
--   c: Command-line editing or Vim Ex mode
--   r: Prompt
--   !: Shell or external command
--   t: Terminal
local KNOWN_MODES = {'o', 'n', 'v', 's', 'i', 'R', 'c', 'r', '!', 't'}

vim.on_key(function(str)
  -- Use pcall to avoid an error in some cases for nvim<0.8 (Neovim #17273).
  pcall(function()
    local raw_mode = fn.mode(1)
    if raw_mode == last_raw_mode then
      active_key_sequence = active_key_sequence .. str
    else
      -- Reset the active key sequence when the mode changes.
      active_key_sequence = str
    end
    last_raw_mode = raw_mode
    active_key_sequence = string.sub(
      active_key_sequence, -max_key_sequence_length, -1)
    local mode
    if vim.startswith(raw_mode, 'no') then
      mode = 'o'
    else
      mode = string.lower(string.sub(raw_mode, 1, 1))
      if mode == CTRLV then
        mode = 'v'
      elseif mode == CTRLS then
        mode = 's'
      end
    end
    local known_mode = false
    for _, x in ipairs(KNOWN_MODES) do
      if mode == x then
        known_mode = true
        break
      end
    end
    if not known_mode then
      mode = nil
    end
    if mode ~= nil then
      for start_idx = -1, -#active_key_sequence, -1 do
        local subseq = string.sub(active_key_sequence, start_idx, -1)
        local key = mode .. subseq
        local callback = key_sequence_callbacks[key]
        if callback ~= nil then
          callback()
        end
      end
    end
  end)
end)

-- Register a sequence of keys, for which the callback will be executed when
-- those keys are pressed under the specified modes. There is a comment above
-- on the supported modes.
local register_key_sequence_callback = function(seq, modes, callback)
  for idx = 1, #modes do
    local mode = string.sub(modes, idx, idx)
    local known_mode = false
    for _, x in ipairs(KNOWN_MODES) do
      if mode == x then
        known_mode = true
        break
      end
    end
    if not known_mode then
      error('Unknown mode: ' .. mode)
    end
    local key = mode .. seq
    key_sequence_callbacks[key] = callback
    max_key_sequence_length = math.max(max_key_sequence_length, #seq)
  end
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

-- Returns the position of window edges, with borders considered part of the
-- window.
local get_window_edges = function(winid)
  local memoize_key = table.concat({GET_WINDOW_EDGES_KEY_PREFIX, winid}, ':')
  if memoize and cache[memoize_key] then return cache[memoize_key] end
  local top, left = unpack(fn.win_screenpos(winid))
  local bottom = top + get_window_height(winid) - 1
  local right = left + fn.winwidth(winid) - 1
  -- Only edges have to be checked to determine if a border is present (i.e.,
  -- corners don't have to be checked). Borders don't impact the top and left
  -- positions calculated above; only the bottom and right positions.
  local border = api.nvim_win_get_config(winid).border
  if border ~= nil and islist(border) and #border == 8 then
    if border[BORDER_TOP] ~= '' then
      bottom = bottom + 1
    end
    if border[BORDER_RIGHT] ~= '' then
      right = right + 1
    end
    if border[BORDER_BOTTOM] ~= '' then
      bottom = bottom + 1
    end
    if border[BORDER_LEFT] ~= '' then
      right = right + 1
    end
  end
  local result = {top, bottom, left, right}
  if memoize then cache[memoize_key] = result end
  return result
end

-- Return the floating windows that overlap the region corresponding to the
-- specified edges. Scrollview windows are included, but workspace windows are
-- not.
local get_float_overlaps = function(top, bottom, left, right)
  local result = {}
  for winnr = 1, fn.winnr('$') do
    local winid = fn.win_getid(winnr)
    local config = api.nvim_win_get_config(winid)
    local floating = tbl_get(config, 'relative', '') ~= ''
    local workspace_win =
      fn.getwinvar(winid, WIN_WORKSPACE_BASE_WINID_VAR, -1) ~= -1
    if not workspace_win and floating then
      local top2, bottom2, left2, right2 = unpack(get_window_edges(winid))
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

local is_mouse_over_scrollview_win = function(winid)
  -- WARN: We use the positioning from the scrollview props. This is so that
  -- clicking when hovering retains the hover highlight for scrollview windows
  -- when their parent winnr > 1. Otherwise, it appeared getwininfo,
  -- nvim_win_get_posiiton, and win_screenpos were not returning accurate info
  -- (may relate to Neovim #24078). Perhaps it's because the windows were just
  -- created and not yet in the necessary state. #100
  local config = api.nvim_win_get_config(winid)
  local mousepos = fn.getmousepos()
  -- Return false if there are any floating windows with higher zindex.
  local float_overlaps = get_float_overlaps(
    mousepos.screenrow, mousepos.screenrow,
    mousepos.screencol, mousepos.screencol
  )
  for _, overlap_winid in ipairs(float_overlaps) do
    local overlap_config = api.nvim_win_get_config(overlap_winid)
    if overlap_winid ~= winid and overlap_config.zindex > config.zindex then
      return false
    end
  end
  local props = api.nvim_win_get_var(winid, PROPS_VAR)
  local parent_pos = fn.win_screenpos(props.parent_winid)
  local row = props.row + parent_pos[1] - 1
  local col = props.col + parent_pos[2] - 1
  -- Adjust for floating window borders.
  local parent_config = api.nvim_win_get_config(props.parent_winid)
  local parent_is_float = tbl_get(parent_config, 'relative', '') ~= ''
  if parent_is_float then
    local border = parent_config.border
    if border ~= nil and islist(border) and #border == 8 then
      if border[BORDER_TOP] ~= '' then
        row = row + 1
      end
      if border[BORDER_LEFT] ~= '' then
        col = col + 1
      end
    end
  end
  -- Adjust for winbar. #117
  if to_bool(tbl_get(fn.getwininfo(props.parent_winid)[1], 'winbar', 0)) then
    row = row + 1
  end
  return mousepos.screenrow >= row
    and mousepos.screenrow < row + props.height
    and mousepos.screencol >= col
    and mousepos.screencol < col + props.width
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

-- Return the base window ID for the specified window. Assumes that windows
-- have been properly marked with WIN_WORKSPACE_BASE_WINID_VAR.
local get_base_winid = function(winid)
  local base_winid = winid
  pcall(function()
    -- Loop until reaching a window with no base winid specified.
    while true do
      base_winid = api.nvim_win_get_var(
        base_winid, WIN_WORKSPACE_BASE_WINID_VAR)
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
-- out-of-sync). This can also be used to prevent unintended side effects when
-- changing the 'wrap' setting temporarily while lines are wrapped (Issue #103).
local with_win_workspace = function(winid, fun)
  local workspace_winid = win_workspace_lookup[winid]
  if workspace_winid == nil then
    -- If winid is already a window workspace, use that. Otherwise, create a
    -- new workspace window.
    if get_base_winid(winid) ~= winid then
      workspace_winid = winid
    else
      -- Make the target window active, so that its folds are inherited by the
      -- created floating window (this is necessary when there are multiple
      -- windows that have the same buffer, each window having different
      -- folds).
      workspace_winid = api.nvim_win_call(winid, function()
        local bufnr = api.nvim_win_get_buf(winid)
        return api.nvim_open_win(bufnr, false, {
          relative = 'editor',
          focusable = false,
          border = 'none',
          width = math.max(1, api.nvim_win_get_width(winid)),
          -- The floating window doesn't inherit a winbar. Use the
          -- winbar-omitted height where applicable.
          height = math.max(1, get_window_height(winid)),
          row = 0,
          col = 0,
        })
      end)
      win_workspace_lookup[winid] = workspace_winid
      -- Disable scrollbind and cursorbind on the workspace window so that diff
      -- mode and other functionality that utilizes binding (e.g., :Gdiff,
      -- :Gblame) can function properly.
      set_window_option(workspace_winid, 'scrollbind', false)
      set_window_option(workspace_winid, 'cursorbind', false)
      api.nvim_win_set_var(workspace_winid, WIN_WORKSPACE_BASE_WINID_VAR, winid)
      -- As a precautionary measure, make sure the floating window has no
      -- winbar, which is assumed above.
      if to_bool(fn.exists('+winbar')) then
        set_window_option(workspace_winid, 'winbar', '')
      end
      -- Don't include the workspace window in a diff session. If included,
      -- closing it could end the diff session (e.g., when there is one other
      -- window in the session). Issue #57.
      set_window_option(workspace_winid, 'diff', false)
    end
  end
  local success, result = pcall(function()
    return api.nvim_win_call(workspace_winid, fun)
  end)
  if not success then error(result) end
  return result
end

local reset_win_workspaces = function()
  for _, workspace_winid in pairs(win_workspace_lookup) do
    if api.nvim_win_is_valid(workspace_winid) then
      api.nvim_win_close(workspace_winid, true)
    end
  end
  win_workspace_lookup = {}
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
local buf_text_begins_col = function(winid)
  -- Use a window workspace to avoid Issue #103.
  return with_win_workspace(winid, function()
    -- The calculation assumes lines don't wrap, so 'nowrap' is temporarily set.
    local wrap = api.nvim_win_get_option(0, 'wrap')
    set_window_option(0, 'wrap', false)
    local result = fn.wincol() - fn.virtcol('.') + 1
    set_window_option(0, 'wrap', wrap)
    return result
  end)
end

-- Returns the window column where the view of the buffer begins. This can be
-- greater than one due to the sign column and 'number' column.
local buf_view_begins_col = function(winid)
  -- Use a window workspace to avoid Issue #103.
  return with_win_workspace(winid, function()
    -- The calculation assumes lines don't wrap, so 'nowrap' is temporarily set.
    local wrap = api.nvim_win_get_option(0, 'wrap')
    set_window_option(0, 'wrap', false)
    local result = fn.wincol() - fn.virtcol('.') + fn.winsaveview().leftcol + 1
    set_window_option(0, 'wrap', wrap)
    return result
  end)
end

local get_byte_count = function(winid)
  return api.nvim_win_call(winid, function()
    return fn.line2byte(fn.line('$') + 1) - 1
  end)
end

-- Returns a boolean indicating whether a restricted state should be used.
local is_restricted = function(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  local line_limit = vim.g.scrollview_line_limit
  if line_limit ~= -1 and line_count > line_limit then
    return true
  end
  local byte_count = get_byte_count(winid)
  local byte_limit = vim.g.scrollview_byte_limit
  if byte_limit ~= -1 and byte_count > byte_limit then
    return true
  end
  return false
end

-- Returns the scrollview mode.
local scrollview_mode = function(winid)
  if is_restricted(winid) then
    return SIMPLE_MODE
  end
  local specified_mode = vim.g.scrollview_mode
  if specified_mode == 'simple' then
    return SIMPLE_MODE
  elseif specified_mode == 'virtual' then
    return VIRTUAL_MODE
  elseif specified_mode == 'proper' then
    return PROPER_MODE
  elseif specified_mode == 'auto' then
    if jit == nil then
      -- Proper mode is slower. Only use it when luajit is available.
      return VIRTUAL_MODE
    end
    local bufnr = api.nvim_win_get_buf(winid)
    local line_count = api.nvim_buf_line_count(bufnr)
    if not api.nvim_win_get_option(winid, 'wrap')
        and not to_bool(fn.has('nvim-0.10')) then
      -- Proper mode is not necessary when there is no wrapping and nvim<0.10
      -- (on nvim>=0.10, diff filler and virtual text lines are also considered).
      return VIRTUAL_MODE
    end
    local winheight = get_window_height(winid)
    local threshold_multiple = 5
    if line_count <= winheight * threshold_multiple then
      return PROPER_MODE
    end
  end
  -- Fallback for when mode is unknown and for auto mode's case where there are
  -- relatively many lines.
  return VIRTUAL_MODE
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
    table.concat({VIRTUAL_LINE_COUNT_KEY_PREFIX, base_winid, start, end_}, ':')
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

-- Returns the proper line count between the two lines. 'store' is an optional
-- dictionary that can be used to save/retrieve values for reuse.
local proper_line_count = function(winid, start, end_, store)
  if store == nil then
    store = {}
  end
  local last_line = api.nvim_buf_line_count(api.nvim_win_get_buf(winid))
  if type(end_) == 'string' and end_ == '$' then
    end_ = last_line
  end
  start = math.max(1, start)
  local base_winid = get_base_winid(winid)
  local memoize_key = table.concat(
      {PROPER_LINE_COUNT_KEY_PREFIX, base_winid, start, end_}, ':')
  if memoize and cache[memoize_key] then return cache[memoize_key] end
  local count
  -- The two approaches that follow, which use nvim_win_text_height and
  -- virtcol, take about the same time to run. However, the nvim_win_text_height
  -- approach also accounts for diff filler and virtual text lines, in addition
  -- to folds and wrapped lines.
  if api.nvim_win_text_height ~= nil then
    count = api.nvim_win_text_height(
      winid, {start_row = start - 1, end_row = end_ - 1}).all
  else
    api.nvim_win_call(winid, function()
      if store.bufwidth == nil then
        local winwidth = fn.winwidth(winid)
        store.bufwidth = winwidth - buf_view_begins_col(winid) + 1
      end
      count = 0
      local line = start
      while line <= end_ do
        local count_diff = 1
        if api.nvim_win_get_option(winid, 'wrap') then
          local virtcol = fn.virtcol({line, '$'})
          count_diff = math.ceil((virtcol - 1) / store.bufwidth)
        end
        -- Avoid zero as a precaution (virtcol's result is one for empty
        -- lines).
        count_diff = math.max(1, count_diff)
        count = count + count_diff
        local foldclosedend = fn.foldclosedend(line)
        if foldclosedend ~= -1 then
          line = foldclosedend
        end
        line = line + 1
      end
    end)
  end
  if memoize then cache[memoize_key] = count end
  return count
end

local calculate_scrollbar_height = function(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local winheight = get_window_height(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  local mode = scrollview_mode(winid)
  local effective_line_count
  if mode == SIMPLE_MODE then
    effective_line_count = line_count
  elseif mode == VIRTUAL_MODE then
    effective_line_count = virtual_line_count(winid, 1, '$')
  elseif mode == PROPER_MODE then
    effective_line_count = proper_line_count(winid, 1, '$')
  else
    error('Unknown mode: ' .. mode)
  end
  if to_bool(vim.g.scrollview_include_end_region) then
    effective_line_count = effective_line_count + winheight - 1
  end
  local height = winheight / effective_line_count
  height = math.ceil(height * winheight)
  height = math.max(1, height)
  return height
end

-- Return the target number of items for a topline lookup table.
local get_target_topline_count = function(winid)
  local target_topline_count = get_window_height(winid)
  if to_bool(vim.g.scrollview_include_end_region) then
    local scrollbar_height = calculate_scrollbar_height(winid)
    target_topline_count = target_topline_count - scrollbar_height + 1
  end
  return target_topline_count
end

local sanitize_topline_lookup = function(
    winid, topline_lookup, target_topline_count)
  api.nvim_win_call(winid, function()
    while #topline_lookup < target_topline_count do
      table.insert(topline_lookup, fn.line('$'))
    end
    for idx, line in ipairs(topline_lookup) do
      line = math.max(1, line)
      line = math.min(fn.line('$'), line)
      local foldclosed = fn.foldclosed(line)
      if foldclosed ~= -1 then
        line = foldclosed
      end
      topline_lookup[idx] = line
    end
  end)
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode, in the current window.
-- The computation loops over virtual spans. The cursor may be moved.
local virtual_topline_lookup_spanwise = function()
  local winid = api.nvim_get_current_win()
  local target_topline_count = get_target_topline_count(winid)
  local result = {}  -- A list of line numbers
  local total_vlines = virtual_line_count(winid, 1, '$')
  if total_vlines > 1 and target_topline_count > 1 then
    local line = 0
    local virtual_line = 0
    local prop = 0.0
    local row = 1
    local proportion = (row - 1) / (target_topline_count - 1)
    vim.cmd('keepjumps normal! gg')
    while #result < target_topline_count do
      local range_start, range_end, fold = advance_virtual_span()
      local line_delta = range_end - range_start + 1
      local virtual_line_delta = 1
      if not fold then
        virtual_line_delta = line_delta
      end
      local prop_delta = virtual_line_delta / (total_vlines - 1)
      while prop + prop_delta >= proportion and #result < target_topline_count do
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
        proportion = (row - 1) / (target_topline_count - 1)
      end
      -- A line number of 1 indicates that advance_virtual_span looped back to
      -- the beginning of the document.
      local looped = fn.line('.') == 1
      if looped or #result >= target_topline_count then
        break
      end
      line = line + line_delta
      virtual_line = virtual_line + virtual_line_delta
      prop = virtual_line / (total_vlines - 1)
    end
  end
  while #result < target_topline_count do
    table.insert(result, fn.line('$'))
  end
  sanitize_topline_lookup(winid, result, target_topline_count)
  return result
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode, in the current window.
local virtual_topline_lookup_linewise = function()
  local winid = api.nvim_get_current_win()
  local target_topline_count = get_target_topline_count(winid)
  local last_line = fn.line('$')
  local result = {}  -- A list of line numbers
  local total_vlines = virtual_line_count(winid, 1, '$')
  if total_vlines > 1 and target_topline_count > 1 then
    local count = 1  -- The count of virtual lines
    local line = 1
    local best = line
    local best_distance = math.huge
    local best_count = count
    for row = 1, target_topline_count do
      local proportion = (row - 1) / (target_topline_count - 1)
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
  sanitize_topline_lookup(winid, result, target_topline_count)
  return result
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode.
local virtual_topline_lookup = function(winid)
  return with_win_workspace(winid, function()
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
end

-- Returns a topline lookup for the current window. The cursor is moved only if
-- api.nvim_win_text_height is not available.
local proper_virtual_topline_lookup = function(winid)
  local target_topline_count = get_target_topline_count(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  local result = {}  -- A list of line numbers
  local total_vlines = proper_line_count(winid, 1, '$')
  -- 'store' is used to speed up calls to proper_line_count. This ends up being
  -- faster than using the existing memoization approach for caching (since the
  -- call to get_base_winid would be relatively slow, and it's simpler to
  -- implement since memoization is turned off below).
  local store = {}
  if total_vlines > 1 and target_topline_count > 1 then
    local line = 1
    local vline = 1
    local prior_line = line
    local prior_vline = vline
    for row = 1, target_topline_count do
      local proportion = (row - 1) / (target_topline_count - 1)
      line = prior_line
      vline = prior_vline
      local best_distance = math.huge
      local best_line = line
      while line <= line_count do
        local current = (vline - 1) / (total_vlines - 1)
        local distance = math.abs(current - proportion)
        if distance < best_distance then
          best_distance = distance
          best_line = line
        elseif distance > best_distance then
          break
        end
        prior_line = line
        prior_vline = vline
        -- Disable caching. It's not useful here, so avoid the memory usage
        -- that would be incurred from caching each line's result.
        local resume_memoize = memoize
        stop_memoize()
        local vline_diff = proper_line_count(winid, line, line, store)
        if resume_memoize then
          start_memoize()
        end
        vline = vline + vline_diff
        local foldclosedend = api.nvim_win_call(winid, function()
          return fn.foldclosedend(line)
        end)
        if foldclosedend ~= -1 then
          line = foldclosedend
        end
        line = line + 1
      end
      table.insert(result, best_line)
    end
  end
  sanitize_topline_lookup(winid, result, target_topline_count)
  return result
end

local simple_topline_lookup = function(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  local target_topline_count = get_target_topline_count(winid)
  local topline_lookup = {}
  for row = 1, target_topline_count do
    local proportion = (row - 1) / (target_topline_count - 1)
    local topline = round(proportion * (line_count - 1)) + 1
    table.insert(topline_lookup, topline)
  end
  return topline_lookup
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row.
local get_topline_lookup = function(winid)
  local mode = scrollview_mode(winid)
  local base_winid = get_base_winid(winid)
  local memoize_key =
    table.concat({TOPLINE_LOOKUP_KEY_PREFIX, base_winid, mode}, ':')
  if memoize and cache[memoize_key] then return cache[memoize_key] end
  local topline_lookup
  if mode == SIMPLE_MODE then
    topline_lookup = simple_topline_lookup(winid)
  elseif mode == VIRTUAL_MODE then
    topline_lookup = virtual_topline_lookup(winid)
  elseif mode == PROPER_MODE then
    topline_lookup = proper_virtual_topline_lookup(winid)
  else
    error('Unknown mode: ' .. mode)
  end
  if memoize then cache[memoize_key] = topline_lookup end
  return topline_lookup
end

local consider_border = function(winid)
  if vim.g.scrollview_consider_border
      and vim.g.scrollview_floating_windows
      and vim.tbl_contains({'left', 'right'}, vim.g.scrollview_base) then
    local config = api.nvim_win_get_config(winid)
    local is_float = tbl_get(config, 'relative', '') ~= ''
    if is_float then
      local border = config.border
      return border ~= nil and islist(border) and #border == 8
    end
  end
  return false
end

local calculate_scrollbar_column = function(winid)
  local winwidth = fn.winwidth(winid)
  -- left is the position for the left of the scrollbar, relative to the
  -- window, and 0-indexed.
  local left = 0
  local column = vim.g.scrollview_column
  local base = vim.g.scrollview_base
  if base == 'left' then
    left = left + column - 1
  elseif base == 'right' then
    left = left + winwidth - column
  elseif base == 'buffer' then
    local btbc = buf_text_begins_col(winid)
    left = left + column - 1 + btbc - 1
  else
    -- For an unknown base, use the default position (right edge of window).
    left = left + winwidth - 1
  end
  if consider_border(winid) then
    local border = api.nvim_win_get_config(winid).border
    if base == 'right' then
      if border[BORDER_RIGHT] ~= '' then
        left = left + 1
      end
    elseif base == 'left' then
      if border[BORDER_LEFT] ~= '' then
        left = left - 1
      end
    end
  end
  return left + 1
end

-- Calculates the bar position for the specified window. Returns a dictionary
-- with a height, row, and col. Uses 1-indexing.
local calculate_position = function(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local topline, _ = line_range(winid)
  local topline_lookup = get_topline_lookup(winid)
  -- top is the position for the top of the scrollbar, relative to the window.
  local top = binary_search(topline_lookup, topline)
  top = math.min(top, #topline_lookup)
  if top > 1 and topline_lookup[top] > topline then
    top = top - 1  -- use the preceding line from topline lookup.
  end
  local winheight = get_window_height(winid)
  local height = calculate_scrollbar_height(winid)
  if not to_bool(vim.g.scrollview_include_end_region) then
    -- Make sure bar properly reflects bottom of document.
    local _, botline = line_range(winid)
    local line_count = api.nvim_buf_line_count(bufnr)
    if botline == line_count then
      top = math.max(top, winheight - height + 1)
    end
  end
  local result = {
    height = height,
    row = top,
    col = calculate_scrollbar_column(winid)
  }
  return result
end

local is_scrollview_window = function(winid)
  if is_ordinary_window(winid) then return false end
  local has_attr = fn.getwinvar(winid, WIN_VAR, '') == WIN_VAL
  if not has_attr then return false end
  local bufnr = api.nvim_win_get_buf(winid)
  return bufnr == bar_bufnr or bufnr == sign_bufnr
end

-- Whether scrollbar and signs should be shown. This is the first check; it
-- only checks for conditions that apply to both the position bar and signs.
local should_show = function(winid)
  if to_bool(vim.g.scrollview_current_only)
      and winid ~= api.nvim_get_current_win() then
    return false
  end
  if is_scrollview_window(winid) then
    return false
  end
  -- Exclude workspace windows.
  if fn.getwinvar(winid, WIN_WORKSPACE_BASE_WINID_VAR, -1) ~= -1 then
    return false
  end
  if vim.g.scrollview_zindex <= 0 then
    return false
  end
  local bufnr = api.nvim_win_get_buf(winid)
  local buf_filetype = api.nvim_buf_get_option(bufnr, 'filetype')
  local winheight = get_window_height(winid)
  local winwidth = fn.winwidth(winid)
  local wininfo = fn.getwininfo(winid)[1]
  local config = api.nvim_win_get_config(winid)
  local is_float = tbl_get(config, 'relative', '') ~= ''
  -- Skip if the window is a floating window and scrollview_floating_windows is
  -- false.
  if not to_bool(vim.g.scrollview_floating_windows)
      and is_float then
    return false
  end
  -- Skip if the filetype is on the list of exclusions.
  local excluded_filetypes = vim.g.scrollview_excluded_filetypes
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
  local always_show = to_bool(vim.g.scrollview_always_show)
  if not always_show then
    -- Don't show when all lines are on screen.
    local topline, botline = line_range(winid)
    local line_count = api.nvim_buf_line_count(bufnr)
    if botline - topline + 1 == line_count then
      return false
    end
  end
  return true
end

-- Returns the cursor screen position, accounting for concealed text
-- (screenpos, screencol, and screenrow don't account for concealed text).
local get_cursor_screen_pos = function()
  local winid = api.nvim_get_current_win()
  local wininfo = fn.getwininfo(winid)[1]
  local winrow0 = wininfo.winrow - 1
  local wincol0 = wininfo.wincol - 1
  local screenrow, screencol
  api.nvim_win_call(winid, function()
    screenrow = winrow0 + fn.winline()
    screencol = wincol0 + fn.wincol()
  end)
  return {row = screenrow, col = screencol}
end

local cursor_intersects_scrollview = function()
  local cursor_screen_pos = get_cursor_screen_pos()
  local float_overlaps = get_float_overlaps(
    cursor_screen_pos.row, cursor_screen_pos.row,
    cursor_screen_pos.col, cursor_screen_pos.col
  )
  float_overlaps = vim.tbl_filter(function(x)
    return is_scrollview_window(x)
  end, float_overlaps)
  return not vim.tbl_isempty(float_overlaps)
end

-- Indicates whether the column is valid for showing a scrollbar or signs.
local is_valid_column = function(winid, col, width)
  local winwidth = fn.winwidth(winid)
  local min_valid_col = 1
  local max_valid_col = winwidth - width + 1
  local base = vim.g.scrollview_base
  if consider_border(winid) then
    local border = api.nvim_win_get_config(winid).border
    if border[BORDER_RIGHT] ~= '' then
      max_valid_col = max_valid_col + 1
    end
    if border[BORDER_LEFT] ~= '' then
      min_valid_col = min_valid_col - 1
    end
  end
  if base == 'buffer' then
    min_valid_col = buf_view_begins_col(winid)
  end
  if col < min_valid_col then
    return false
  end
  if col > max_valid_col then
    return false
  end
  return true
end

-- Returns true if 'cterm' has a 'reverse' attribute for the specified
-- highlight group, or false otherwise. Checks 'gui' instead of 'cterm' if a
-- GUI is running or termguicolors is set.
local is_hl_reversed = function(group)
  local items
  while true do
    local highlight = fn.execute('highlight ' .. group)
    items = fn.split(highlight)
    table.remove(items, 1)  -- Remove the group name
    table.remove(items, 1)  -- Remove "xxx"
    if items[1] == 'links' and items[2] == 'to' then
      group = items[3]
    else
      break
    end
  end
  if items[1] ~= 'cleared' then
    for _, item in ipairs(items) do
      local key, val = unpack(vim.split(item, '='))
      local guicolors = to_bool(fn.has('gui_running'))
        or vim.o.termguicolors
      if (not guicolors and key == 'cterm')
          or (guicolors and key == 'gui') then
        local attrs = vim.split(val, ',')
        for _, attr in ipairs(attrs) do
          if attr == 'reverse' or attr == 'inverse' then
            return true
          end
        end
      end
    end
  end
  return false
end

-- Returns the mapped highlight for the specified window, creating a new group
-- if nvim_win_set_hl_ns was used.
-- WARN: 'nvim_win_set_hl_ns' "takes precedence over the 'winhighlight'
-- option".
local get_mapped_highlight = function(winid, from)
  local highlight = from
  local hl_ns = -1
  if api.nvim_get_hl_ns ~= nil then
    hl_ns = api.nvim_get_hl_ns({winid = winid})
  end
  if hl_ns ~= -1 then
    if highlight_lookup[winid .. '.' .. from] ~= nil then
      highlight = highlight_lookup[winid .. '.' .. from]
    else
      local hl_spec = api.nvim_get_hl(
        hl_ns, {name = from, create = false, link = true})
      -- NormalFloat takes precedence for floating windows, but if it's not
      -- specified, Normal will be used if present.
      if vim.tbl_isempty(hl_spec) and from == 'NormalFloat' then
        hl_spec = api.nvim_get_hl(
          hl_ns, {name = 'Normal', create = false, link = true})
      end
      -- Use the global namespace if the specification was not found.
      if vim.tbl_isempty(hl_spec) then
        hl_spec = api.nvim_get_hl(
          0, {name = from, create = false, link = true})
      end
      local visited = {}
      while not vim.tbl_isempty(hl_spec)
          and hl_spec.link ~= nil
          and not visited[hl_ns .. '_' .. hl_spec.link] do
        local link = hl_spec.link
        visited[hl_ns .. '_' .. link] = true
        hl_spec = api.nvim_get_hl(
          hl_ns, {name = link, create = false, link = true})
        -- If the link is to a highlight specification that doesn't exist in
        -- the current namespace, switch to the global namespace and try again.
        if hl_ns ~= 0 and vim.tbl_isempty(hl_spec) then
          hl_ns = 0
          visited[hl_ns .. '_' .. link] = true
          hl_spec = api.nvim_get_hl(
            hl_ns, {name = link, create = false, link = true})
        end
      end
      -- Create a group with a matching specification.
      highlight = 'ScrollViewHighlight' .. highlight_lookup_size
      api.nvim_set_hl(0, highlight, hl_spec)
      highlight_lookup[winid .. '.' .. from] = highlight
      highlight_lookup_size = highlight_lookup_size + 1
    end
  else
    local base_winhighlight = api.nvim_win_get_option(winid, 'winhighlight')
    if base_winhighlight ~= '' then
      pcall(function()
        for _, item in ipairs(fn.split(base_winhighlight, ',')) do
          local lhs, rhs = unpack(fn.split(item, ':'))
          if lhs == from then
            highlight = rhs
            break
          end
          -- NormalFloat takes precedence for floating windows, but if it's not
          -- specified, Normal will be used if present.
          if lhs == 'Normal' and from == 'NormalFloat' then
            highlight = rhs
          end
        end
      end)
    end
  end
  return highlight
end

local get_scrollbar_character = function()
  local character = vim.g.scrollview_character
  character = character:gsub('\n', '')
  character = character:gsub('\r', '')
  if #character < 1 then character = ' ' end
  character = fn.strcharpart(character, 0, 1)
  return character
end

-- Returns a table that maps window rows to the length of text on that row.
-- WARN: When a multi-cell character is the last character on a row, the length
-- returned by this function represents the first cell of that character.
local get_row_length_lookup = function(winid)
  local memoize_key =
    table.concat({ROW_LENGTH_LOOKUP_KEY_PREFIX, winid}, ':')
  if memoize and cache[memoize_key] then return cache[memoize_key] end
  local result = {}
  with_win_workspace(winid, function()
    local scrolloff = api.nvim_win_get_option(0, 'scrolloff')
    local virtualedit = api.nvim_win_get_option(0, 'virtualedit')
    set_window_option(0, 'scrolloff', 0)
    set_window_option(0, 'virtualedit', 'none')
    fn.winrestview(api.nvim_win_call(winid, fn.winsaveview))
    vim.cmd('keepjumps normal! Hg0')
    local prior
    -- Limit the number of steps as a precaution. The doubling of window height
    -- is to be safe.
    local max_steps = fn.winheight(0) * 2
    local steps = 0
    while fn.winline() > 1
        and prior ~= fn.winline()
        and steps < max_steps do
      steps = steps + 1
      prior = fn.winline()
      vim.cmd('keepjumps normal! g0gk')
    end
    prior = nil
    steps = 0
    local winheight = get_window_height(0)
    -- It may not be possible to get to every winline (e.g., virtual lines).
    while fn.winline() <= winheight
        and prior ~= fn.winline()
        and steps < max_steps do
      steps = steps + 1
      prior = fn.winline()
      vim.cmd('keepjumps normal! g$')
      result[fn.winline()] = fn.wincol()
      vim.cmd('keepjumps normal! g0gj')
    end
    set_window_option(0, 'scrolloff', scrolloff)
    set_window_option(0, 'virtualedit', virtualedit)
  end)
  if memoize then cache[memoize_key] = result end
  return result
end

-- Show a scrollbar for the specified 'winid' window ID, using the specified
-- 'bar_winid' floating window ID (a new floating window will be created if
-- this is -1). Returns -1 if the bar is not shown, and the floating window ID
-- otherwise.
local show_scrollbar = function(winid, bar_winid)
  local wininfo = fn.getwininfo(winid)[1]
  local config = api.nvim_win_get_config(winid)
  local is_float = tbl_get(config, 'relative', '') ~= ''
  local bar_position = calculate_position(winid)
  local bar_width = 1
  if not is_valid_column(winid, bar_position.col, bar_width) then
    return -1
  end
  local cur_winid = api.nvim_get_current_win()
  -- Height has to be positive for the call to nvim_open_win. When opening a
  -- terminal, the topline and botline can be set such that height is negative
  -- when you're using scrollview document mode.
  if bar_position.height <= 0 then
    return -1
  end
  if to_bool(vim.g.scrollview_hide_bar_for_insert)
      and string.find(fn.mode(), 'i')
      and winid == cur_winid then
    return -1
  end
  local winrow0 = wininfo.winrow - 1
  local wincol0 = wininfo.wincol - 1
  local top = winrow0 + bar_position.row
  local bottom = winrow0 + bar_position.row + bar_position.height - 1
  local left = wincol0 + bar_position.col
  local right = wincol0 + bar_position.col
  if to_bool(vim.g.scrollview_hide_on_float_intersect) then
    local float_overlaps = get_float_overlaps(top, bottom, left, right)
    float_overlaps = vim.tbl_filter(function(x)
      return not is_scrollview_window(x)
    end, float_overlaps)
    if not vim.tbl_isempty(float_overlaps) then
      if #float_overlaps > 1 or float_overlaps[1] ~= winid then
        return -1
      end
    end
  end
  if to_bool(vim.g.scrollview_hide_on_cursor_intersect)
      and to_bool(fn.has('nvim-0.7'))  -- for Neovim autocmd API
      and winid == cur_winid then
    local cursor_screen_pos = get_cursor_screen_pos()
    if top <= cursor_screen_pos.row
        and bottom >= cursor_screen_pos.row
        and left <= cursor_screen_pos.col
        and right >= cursor_screen_pos.col then
      -- Refresh scrollview for next cursor move, in case it moves away.
      -- Overwrite an existing autocmd configured to already do this.
      local augroup = api.nvim_create_augroup('scrollview_cursor_intersect', {
        clear = true
      })
      api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
        group = augroup,
        callback = function()
          require('scrollview').refresh()
        end,
        once = true,
      })
      return -1
    end
  end
  if to_bool(vim.g.scrollview_hide_on_text_intersect) then
    local row_length_lookup = get_row_length_lookup(winid)
    for row = bar_position.row, bar_position.row + bar_position.height - 1 do
      if row_length_lookup[row] ~= nil
          and row_length_lookup[row] >= bar_position.col then
        return -1
      end
    end
  end
  if bar_bufnr == -1 or not to_bool(fn.bufloaded(bar_bufnr)) then
    if bar_bufnr == -1 then
      bar_bufnr = api.nvim_create_buf(false, true)
    end
    -- Other plugins might have unloaded the buffer. #104
    fn.bufload(bar_bufnr)
    api.nvim_buf_set_option(bar_bufnr, 'modifiable', false)
    api.nvim_buf_set_option(bar_bufnr, 'filetype', 'scrollview')
    api.nvim_buf_set_option(bar_bufnr, 'buftype', 'nofile')
    api.nvim_buf_set_option(bar_bufnr, 'swapfile', false)
    api.nvim_buf_set_option(bar_bufnr, 'bufhidden', 'hide')
    api.nvim_buf_set_option(bar_bufnr, 'buflisted', false)
    -- Don't turn off undo for Neovim 0.9.0 and 0.9.1 since Neovim could crash,
    -- presumably from Neovim #24289. #111, #115
    if not to_bool(fn.has('nvim-0.9')) or to_bool(fn.has('nvim-0.9.2')) then
      api.nvim_buf_set_option(bar_bufnr, 'undolevels', -1)
    end
  end
  -- Make sure that a custom character is up-to-date and is repeated enough to
  -- cover the full height of the scrollbar.
  local bar_line_count = api.nvim_buf_line_count(bar_bufnr)
  local character = get_scrollbar_character()
  if api.nvim_buf_get_lines(bar_bufnr, 0, 1, false)[1] ~= character
      or bar_position.height > bar_line_count then
    api.nvim_buf_set_option(bar_bufnr, 'modifiable', true)
    api.nvim_buf_set_lines(
      bar_bufnr, 0, bar_line_count, false,
      fn['repeat']({character}, bar_position.height))
    api.nvim_buf_set_option(bar_bufnr, 'modifiable', false)
  end
  local zindex = vim.g.scrollview_zindex
  if is_float then
    zindex = zindex + config.zindex
  end
  -- When there is a winbar, nvim_open_win with relative=win considers row 0 to
  -- be the line below the winbar.
  local max_height = get_window_height(winid) - bar_position.row + 1
  local height = math.min(bar_position.height, max_height)
  local bar_config = {
    win = winid,
    relative = 'win',
    focusable = false,
    style = 'minimal',
    border = 'none',
    height = height,
    width = bar_width,
    row = bar_position.row - 1,
    col = bar_position.col - 1,
    zindex = zindex
  }
  -- Create a new window if one is not available for re-use. Also, create a new
  -- window if the base window is a floating window, to avoid Neovim Issue #18142,
  -- a z-index issue (#139) that was fixed in Neovim PR #30259.
  local issue_18142 = is_float and not to_bool(fn.has('nvim-0.11'))
  if bar_winid == -1 or issue_18142 then
    bar_winid = api.nvim_open_win(bar_bufnr, false, bar_config)
  else
    api.nvim_win_set_config(bar_winid, bar_config)
  end
  -- Scroll to top so that the custom character spans full scrollbar height.
  vim.cmd('keepjumps call nvim_win_set_cursor(' .. bar_winid .. ', [1, 0])')
  local highlight_fn = function(hover)
    hover = hover and vim.g.scrollview_hover
    local highlight
    if hover then
      highlight = 'ScrollViewHover'
    else
      highlight = 'ScrollView'
      if is_restricted(winid) then
        highlight = highlight .. 'Restricted'
      end
    end
    api.nvim_win_call(bar_winid, function()
      fn.clearmatches()
      -- Multiple matchaddpos calls are necessary since the maximum number of
      -- positions that matchaddpos can take is 8 (for nvim<=0.8).
      -- Use the full height (bar_position.height), not the actual height
      -- (fn.winheight(bar_winid)). #106
      for pos_start = 1, bar_position.height, 8 do
        local pos_end = math.min(pos_start + 7, bar_position.height)
        fn.matchaddpos(highlight, fn.range(pos_start, pos_end))
      end
    end)
    local winblend = vim.g.scrollview_winblend
    if to_bool(fn.has('gui_running')) or vim.o.termguicolors then
      winblend = vim.g.scrollview_winblend_gui
    end
    -- Add a workaround for Neovim #14624.
    if is_float then
      -- Disable winblend for base windows that are floating. The scrollbar would
      -- blend with an orinary window, not the base floating window.
      winblend = 0
    end
    -- Add a workaround for Neovim #24159.
    if is_hl_reversed(highlight) then
      winblend = 0
    end
    -- Add a workaround for Neovim #24584 (nvim-scrollview #112).
    if string.gsub(character, '%s', '') ~= '' then
      winblend = 0
    end
    set_window_option(bar_winid, 'winblend', winblend)
    -- Set the Normal highlight to match the base window. It's not sufficient to
    -- just specify Normal highlighting. With just that, a color scheme's
    -- specification of EndOfBuffer would be used to color the bottom of the
    -- scrollbar.
    local target = is_float and 'NormalFloat' or 'Normal'
    if consider_border(winid) then
      local border = api.nvim_win_get_config(winid).border
      local winwidth = fn.winwidth(winid)
      if border[BORDER_RIGHT] ~= ''
          and winwidth + 1 == bar_position.col then
        target = 'FloatBorder'
      end
      if border[BORDER_LEFT] ~= ''
          and 0 == bar_position.col then
        target = 'FloatBorder'
      end
    end
    target = get_mapped_highlight(winid, target)
    local winhighlight = string.format(
      'Normal:%s,EndOfBuffer:%s,NormalFloat:%s', target, target, target)
    set_window_option(bar_winid, 'winhighlight', winhighlight)
  end
  set_window_option(bar_winid, 'foldcolumn', '0')  -- foldcolumn takes a string
  set_window_option(bar_winid, 'foldenable', false)
  -- Don't inherit 'foldmethod'. It could slow down scrolling. #135
  set_window_option(bar_winid, 'foldmethod', 'manual')
  set_window_option(bar_winid, 'wrap', false)
  api.nvim_win_set_var(bar_winid, WIN_VAR, WIN_VAL)
  local props = {
    col = bar_position.col,
    -- Save bar_position.height in addition to the actual height, since the
    -- latter may be reduced for the bar to fit in the window.
    full_height = bar_position.height,
    height = height,
    parent_winid = winid,
    row = bar_position.row,
    scrollview_winid = bar_winid,
    type = BAR_TYPE,
    width = bar_width,
    zindex = zindex,
  }
  if to_bool(fn.has('nvim-0.7')) then
    -- Neovim 0.7 required to later avoid "Cannot convert given lua type".
    props.highlight_fn = highlight_fn
  end
  api.nvim_win_set_var(bar_winid, PROPS_VAR, props)
  local hover = mousemove_received
    and to_bool(fn.exists('&mousemoveevent'))
    and vim.o.mousemoveevent
    and is_mouse_over_scrollview_win(bar_winid)
  highlight_fn(hover)
  return bar_winid
end

-- Show signs for the specified 'winid' window ID. A list of existing sign
-- winids, 'sign_winids', is specified for possible reuse. Reused windows are
-- removed from the list. The bar_winid is necessary so that signs can be
-- properly highlighted when intersecting a scrollbar.
local show_signs = function(winid, sign_winids, bar_winid)
  -- Neovim 0.8 has an issue with matchaddpos highlighting (similar type of
  -- issue reported in Neovim #22906).
  if not to_bool(fn.has('nvim-0.9')) then return end
  local bar_props
  if bar_winid ~= -1 then
    bar_props = api.nvim_win_get_var(bar_winid, PROPS_VAR)
  end
  local cur_winid = api.nvim_get_current_win()
  local wininfo = fn.getwininfo(winid)[1]
  local config = api.nvim_win_get_config(winid)
  local is_float = tbl_get(config, 'relative', '') ~= ''
  if is_restricted(winid) then return end
  local bufnr = api.nvim_win_get_buf(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  local topline_lookup = nil  -- only set when needed
  local base_col = calculate_scrollbar_column(winid)
  -- lookup maps rows to a mapping of names to sign specifications (with lines).
  local lookup = {}
  for _, sign_spec in pairs(sign_specs) do
    local name = sign_spec.name
    local lines = {}
    local lines_as_given = {}
    pcall(function()
      if sign_spec.type == 'b' then
        lines_as_given = api.nvim_buf_get_var(bufnr, name)
      elseif sign_spec.type == 'w' then
        lines_as_given = api.nvim_win_get_var(winid, name)
      end
    end)
    local satisfied_current_only = true
    if sign_spec.current_only then
      satisfied_current_only = winid == cur_winid
    end
    local hide_for_insert =
      vim.tbl_contains(vim.g.scrollview_signs_hidden_for_insert, sign_spec.group)
        or vim.tbl_contains(vim.g.scrollview_signs_hidden_for_insert, 'all')
    hide_for_insert = hide_for_insert
      and string.find(fn.mode(), 'i')
      and winid == api.nvim_get_current_win()
    local show = sign_group_state[sign_spec.group]
      and satisfied_current_only
      and not hide_for_insert
    if show then
      local lines_to_show = sorted(lines_as_given)
      local show_in_folds = to_bool(vim.g.scrollview_signs_show_in_folds)
      if sign_spec.show_in_folds ~= nil then
        show_in_folds = sign_spec.show_in_folds
      end
      if not show_in_folds then
        lines_to_show = api.nvim_win_call(winid, function()
          local result = {}
          for _, line in ipairs(lines_to_show) do
            if fn.foldclosed(line) == -1 then
              table.insert(result, line)
            end
          end
          return result
        end)
      end
      for _, line in ipairs(lines_to_show) do
        if vim.tbl_isempty(lines) or lines[#lines] ~= line then
          table.insert(lines, line)
        end
      end
    end
    if not vim.tbl_isempty(lines) and topline_lookup == nil then
      topline_lookup = get_topline_lookup(winid)
    end
    for _, line in ipairs(lines) do
      if line >= 1 and line <= line_count then
        local row1 = binary_search(topline_lookup, line)
        row1 = math.min(row1, #topline_lookup)
        if row1 > 1 and topline_lookup[row1] > line then
          row1 = row1 - 1  -- use the preceding line from topline lookup.
        end
        local rows = {row1}  -- rows to draw the sign on
        -- When extend is set, draw the sign on subsequent rows with the same
        -- topline.
        if sign_spec.extend then
          while topline_lookup[row1] == topline_lookup[rows[#rows] + 1] do
            table.insert(rows, rows[#rows] + 1)
          end
        end
        for _, row in ipairs(rows) do
          if lookup[row] == nil then
            lookup[row] = {}
          end
          if lookup[row][name] == nil then
            local properties = {
              symbol = sign_spec.symbol,
              highlight = sign_spec.highlight,
              priority = sign_spec.priority,
              sign_spec_id = sign_spec.id,
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
      if a.priority ~= b.priority then
        return a.priority > b.priority
      else
        -- Resolve ties based on specification ID (earlier registrations are
        -- given higher priority).
        return a.sign_spec_id < b.sign_spec_id
      end
    end)
    local max_signs_per_row = vim.g.scrollview_signs_max_per_row
    if max_signs_per_row >= 0 then
      props_list = vim.list_slice(props_list, 1, max_signs_per_row)
    end
    -- A set of columns, to prevent creating multiple signs in the same
    -- location.
    local total_width = 0  -- running sum of sign widths
    -- Treat the bar as if it were a sign, and position subsequent signs
    -- accordingly. This only applies if a scrollbar is shown (e.g., not when
    -- it is hidden from hide_on_intersect or not shown because of an invalid
    -- column).
    if bar_props ~= nil
        and row >= bar_props.row
        and row <= bar_props.row + bar_props.height - 1 then
      total_width = total_width + 1
    end
    for _, properties in ipairs(props_list) do
      local symbol = properties.symbol
      local sign_width = fn.strdisplaywidth(symbol)
      local col = base_col
      if vim.g.scrollview_signs_overflow == 'left' then
        col = col - total_width
        col = col - sign_width + 1
      else
        col = col + total_width
      end
      total_width = total_width + sign_width
      local show = is_valid_column(winid, col, sign_width)
      local winrow0 = wininfo.winrow - 1
      local wincol0 = wininfo.wincol - 1
      local top = winrow0 + row
      local bottom = winrow0 + row
      local left = wincol0 + col
      local right = wincol0 + col + sign_width - 1
      if to_bool(vim.g.scrollview_hide_on_float_intersect)
          and show then
        local float_overlaps = get_float_overlaps(top, bottom, left, right)
        float_overlaps = vim.tbl_filter(function(x)
          return not is_scrollview_window(x)
        end, float_overlaps)
        if not vim.tbl_isempty(float_overlaps) then
          if #float_overlaps > 1 or float_overlaps[1] ~= winid then
            show = false
          end
        end
      end
      if to_bool(vim.g.scrollview_hide_on_cursor_intersect)
          and to_bool(fn.has('nvim-0.7'))  -- for Neovim autocmd API
          and winid == cur_winid
          and show then
        local cursor_screen_pos = get_cursor_screen_pos()
        if top <= cursor_screen_pos.row
            and bottom >= cursor_screen_pos.row
            and left <= cursor_screen_pos.col
            and right >= cursor_screen_pos.col then
          -- Refresh scrollview for next cursor move, in case it moves away.
          -- Overwrite an existing autocmd configured to already do this.
          local augroup = api.nvim_create_augroup('scrollview_cursor_intersect', {
            clear = true
          })
          api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
            group = augroup,
            callback = function()
              require('scrollview').refresh()
            end,
            once = true,
          })
          show = false
        end
      end
      if to_bool(vim.g.scrollview_hide_on_text_intersect) then
        local row_length_lookup = get_row_length_lookup(winid)
        if row_length_lookup[row] ~= nil
            and row_length_lookup[row] >= col then
          show = false
        end
      end
      if show then
        if sign_bufnr == -1 or not to_bool(fn.bufloaded(sign_bufnr)) then
          if sign_bufnr == -1 then
            sign_bufnr = api.nvim_create_buf(false, true)
          end
          -- Other plugins might have unloaded the buffer. #104
          fn.bufload(sign_bufnr)
          api.nvim_buf_set_option(sign_bufnr, 'modifiable', false)
          api.nvim_buf_set_option(sign_bufnr, 'filetype', 'scrollview_sign')
          api.nvim_buf_set_option(sign_bufnr, 'buftype', 'nofile')
          api.nvim_buf_set_option(sign_bufnr, 'swapfile', false)
          api.nvim_buf_set_option(sign_bufnr, 'bufhidden', 'hide')
          api.nvim_buf_set_option(sign_bufnr, 'buflisted', false)
          -- Don't turn off undo for Neovim 0.9.0 and 0.9.1 since Neovim could
          -- crash, presumably from Neovim #24289. #111, #115
          if not to_bool(fn.has('nvim-0.9'))
              or to_bool(fn.has('nvim-0.9.2')) then
            api.nvim_buf_set_option(sign_bufnr, 'undolevels', -1)
          end
        end
        local sign_line_count = api.nvim_buf_line_count(sign_bufnr)
        api.nvim_buf_set_option(sign_bufnr, 'modifiable', true)
        api.nvim_buf_set_lines(
          sign_bufnr,
          sign_line_count - 1,
          sign_line_count - 1,
          false,
          {symbol}
        )
        api.nvim_buf_set_option(sign_bufnr, 'modifiable', false)
        local sign_winid
        local zindex = vim.g.scrollview_zindex
        if is_float then
          zindex = zindex + config.zindex
        end
        local sign_config = {
          win = winid,
          relative = 'win',
          focusable = false,
          style = 'minimal',
          border = 'none',
          height = 1,
          width = sign_width,
          row = row - 1,
          col = col - 1,
          zindex = zindex,
        }
        -- Create a new window if none are available for re-use. Also, create a
        -- new window if the base window is a floating window, to avoid Neovim
        -- Issue #18142, a z-index issue (#139) that was fixed in Neovim PR #30259.
        local issue_18142 = is_float and not to_bool(fn.has('nvim-0.11'))
        if vim.tbl_isempty(sign_winids) or issue_18142 then
          sign_winid = api.nvim_open_win(sign_bufnr, false, sign_config)
        else
          sign_winid = table.remove(sign_winids)
          api.nvim_win_set_config(sign_winid, sign_config)
        end
        local over_scrollbar = bar_props ~= nil
          and bar_props.col >= col
          and bar_props.col <= col + sign_width - 1
          and row >= bar_props.row
          and row <= bar_props.row + bar_props.height - 1
          and zindex > bar_props.zindex
        local highlight_fn = function(hover)
          hover = hover and vim.g.scrollview_hover
          local highlight
          if hover then
            highlight = 'ScrollViewHover'
          else
            highlight = properties.highlight
          end
          if highlight ~= nil then
            api.nvim_win_call(sign_winid, function()
              fn.clearmatches()
              fn.matchaddpos(highlight, {sign_line_count})
            end)
            local winblend = vim.g.scrollview_winblend
            if to_bool(fn.has('gui_running')) or vim.o.termguicolors then
              winblend = vim.g.scrollview_winblend_gui
            end
            -- Add a workaround for Neovim #14624.
            if is_float then
              -- Disable winblend for base windows that are floating. The sign
              -- would blend with an orinary window, not the base floating
              -- window.
              winblend = 0
            end
            -- Add a workaround for Neovim #24159.
            if is_hl_reversed(highlight) then
              winblend = 0
            end
            -- Add a workaround for Neovim #24584 (nvim-scrollview #112).
            if not over_scrollbar then
              local bufline = fn.getbufline(sign_bufnr, sign_line_count)[1]
              if string.gsub(bufline, '%s', '') ~= '' then
                winblend = 0
              end
            end
            set_window_option(sign_winid, 'winblend', winblend)
            local target
            if over_scrollbar then
              target = 'ScrollView'
            else
              target = is_float and 'NormalFloat' or 'Normal'
              if consider_border(winid) then
                local border = api.nvim_win_get_config(winid).border
                local winwidth = fn.winwidth(winid)
                if border[BORDER_RIGHT] ~= ''
                    and winwidth + 1 >= col
                    and winwidth + 1 <= col + sign_width - 1 then
                  target = 'FloatBorder'
                end
                if border[BORDER_LEFT] ~= ''
                    and 0 >= col
                    and 0 <= col + sign_width - 1 then
                  target = 'FloatBorder'
                end
              end
            end
            target = get_mapped_highlight(winid, target)
            local winhighlight = string.format(
              'Normal:%s,EndOfBuffer:%s,NormalFloat:%s', target, target, target)
            set_window_option(sign_winid, 'winhighlight', winhighlight)
          end
        end
        -- Scroll to the inserted line.
        local args = sign_winid .. ', [' .. sign_line_count .. ', 0]'
        vim.cmd('keepjumps call nvim_win_set_cursor(' .. args .. ')')
        -- Set the window's highlight to that of the scrollbar if intersecting,
        -- or otherwise set the Normal highlight to match the base window.
        -- foldcolumn takes a string
        set_window_option(sign_winid, 'foldcolumn', '0')
        set_window_option(sign_winid, 'foldenable', false)
        -- Don't inherit 'foldmethod'. It could slow down scrolling. #135
        set_window_option(sign_winid, 'foldmethod', 'manual')
        set_window_option(sign_winid, 'wrap', false)
        api.nvim_win_set_var(sign_winid, WIN_VAR, WIN_VAL)
        local props = {
          col = col,
          height = 1,
          highlight = properties.highlight,
          lines = properties.lines,
          parent_winid = winid,
          row = row,
          scrollview_winid = sign_winid,
          sign_spec_id = properties.sign_spec_id,
          symbol = properties.symbol,
          type = SIGN_TYPE,
          width = sign_width,
          zindex = zindex,
        }
        if to_bool(fn.has('nvim-0.7')) then
          -- Neovim 0.7 required to later avoid "Cannot convert given lua type".
          props.highlight_fn = highlight_fn
        end
        api.nvim_win_set_var(sign_winid, PROPS_VAR, props)
        local hover = mousemove_received
          and to_bool(fn.exists('&mousemoveevent'))
          and vim.o.mousemoveevent
          and is_mouse_over_scrollview_win(sign_winid)
        highlight_fn(hover)
      end
    end
  end
end

-- Given a scrollbar properties dictionary and a target window row, the
-- corresponding scrollbar is moved to that row.
-- Where applicable, the height is adjusted if it would extend past the screen.
-- The row is adjusted (up in value, down in visual position) such that the
-- full height of the scrollbar remains on screen. Returns the updated
-- scrollbar properties.
local move_scrollbar = function(props, row)
  props = copy(props)
  local max_height = get_window_height(props.parent_winid) - row + 1
  local height = math.min(props.full_height, max_height)
  local options = {
    win = props.parent_winid,
    relative = 'win',
    row = row - 1,
    col = props.col - 1,
    height = height,
  }
  api.nvim_win_set_config(props.scrollview_winid, options)
  props.row = row
  props.height = height
  api.nvim_win_set_var(props.scrollview_winid, PROPS_VAR, props)
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

-- Sets global state that is assumed by the core functionality and returns a
-- state that can be used for restoration.
local init = function()
  local eventignore = api.nvim_get_option('eventignore')
  api.nvim_set_option('eventignore', 'all')
  local state = {
    initial_winid = api.nvim_get_current_win(),
    belloff = api.nvim_get_option('belloff'),
    eventignore = eventignore,
    mode = fn.mode(),
  }
  -- Disable the bell (e.g., for invalid cursor movements, trying to navigate
  -- to a next fold, when no fold exists).
  api.nvim_set_option('belloff', 'all')
  if is_select_mode(state.mode) then
    -- Temporarily switch from select-mode to visual-mode, so that 'normal!'
    -- commands can be executed properly.
    vim.cmd('normal! ' .. t'<c-g>')
  end
  return state
end

local restore = function(state)
  local current_winid = api.nvim_get_current_win()
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
  -- 'set title' when 'title' is on, so it's properly set. #84
  if api.nvim_get_option('title') then
    api.nvim_set_option('title', true)
  end
  -- Use a no-op normal! command so that events are processed before reverting
  -- 'eventignore'. The event being targeted is ModeChanged, which fires from
  -- switching from a window workspace floating window in normal mode back to
  -- the active window in visual mode. Here we switch back and forth from
  -- visual and select modes, which is effectively a no-op. Without doing this,
  -- the ModeChanged event will fire later, after eventignore is restored. Here
  -- it will fire but will be ignored, since eventignore=all. #136
  if is_visual_mode(fn.mode()) or is_select_mode(fn.mode()) then
    vim.cmd('normal! ' .. t'<c-g><c-g>')
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
--   5) mouse_row (1-indexed)
--   6) mouse_col (1-indexed)
-- The mouse values are 0 when there was no mouse event or getmousepos is not
-- available. The mouse_winid is set to COMMAND_LINE_WINID (negative) when a
-- mouse event was on the command line. The mouse_winid is set to TABLINE_WINID
-- (negative) when a mouse event was on the tabline. For floating windows with
-- borders, the left border is considered column 0 and the top border is
-- considered row 0.
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
        mouse_winid = COMMAND_LINE_WINID
        mouse_row = mousepos.screenrow - vim.go.lines + vim.go.cmdheight
        mouse_col = mousepos.screencol
      end
      -- Handle a mouse event on the tabline. When the click is on a floating
      -- window covering the tabline, mousepos.winid will be set to that
      -- floating window's winid. Otherwise, mousepos.winid would correspond to
      -- an ordinary window ID (seemingly for the window below the tabline).
      if vim.deep_equal(fn.win_screenpos(1), {2, 1})  -- Checks for presence of a tabline.
          and mousepos.screenrow == 1
          and is_ordinary_window(mousepos.winid) then
        mouse_winid = TABLINE_WINID
        mouse_row = mousepos.screenrow
        mouse_col = mousepos.screencol
      end
      -- Handle mouse events when there is a winbar.
      if mouse_winid > 0
          and to_bool(tbl_get(fn.getwininfo(mouse_winid)[1], 'winbar', 0)) then
        mouse_row = mouse_row - 1
      end
      -- Adjust for floating window borders.
      if mouse_winid > 0 then
        local config = api.nvim_win_get_config(mouse_winid)
        local is_float = tbl_get(config, 'relative', '') ~= ''
        if is_float then
          local border = config.border
          if border ~= nil and islist(border) and #border == 8 then
            if border[BORDER_TOP] ~= '' then
              mouse_row = mouse_row - 1
            end
            if border[BORDER_LEFT] ~= '' then
              mouse_col = mouse_col - 1
            end
          end
        end
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
  local str = table.concat(chars, '')
  local result = {str, chars_props}
  return unpack(result)
end

-- Scrolls the window so that the specified line number is at the top.
local set_topline = function(winid, linenr)
  -- WARN: Unlike other functions that move the cursor (e.g., VirtualLineCount,
  -- VirtualProportionLine), a window workspace should not be used, as the
  -- cursor and viewport changes here are intended to persist.
  api.nvim_win_call(winid, function()
    vim.cmd('keepjumps normal! ' .. linenr .. 'G0')
    local topline, _ = line_range(winid)
    -- Use virtual lines to figure out how much to scroll up. winline() doesn't
    -- accommodate wrapped lines for this action.
    local virtual_line = virtual_line_count(winid, topline, fn.line('.'))
    if virtual_line > 1 then
      vim.cmd('keepjumps normal! ' .. (virtual_line - 1) .. t'<c-e>')
    end
  end)
end

local set_cursor_position = function(winid, winline, wincol)
  api.nvim_win_call(winid, function()
    -- Make sure that h and l don't change lines.
    local whichwrap = api.nvim_get_option('whichwrap')
    vim.cmd('set whichwrap-=h')
    vim.cmd('set whichwrap-=l')

    vim.cmd('keepjumps normal! H0')

    -- Set the specified window line.
    local prior
    -- Limit the number of steps as a precaution. The doubling of window height
    -- is to be safe.
    local max_steps = fn.winheight(0) * 2
    local steps = 0
    while fn.winline() < winline
        and prior ~= fn.winline()
        and steps < max_steps do
      steps = steps + 1
      prior = fn.winline()
      vim.cmd('keepjumps normal! gj')
      if fn.winline() == prior then
        -- gj may not move to the next screen line (e.g., if a character that
        -- can't be displayed, like <99>, spans screen lines).
        vim.cmd('keepjumps normal! l')
      end
    end
    -- Update winline for the purpose of setting window column. It may not have
    -- been possible to properly set the window line, but we still want to try
    -- to set the window column. The procedure utilizes the winline value.
    winline = fn.winline()

    -- Set the specified window column.
    -- WARN: The calculations below don't properly account for concealed text.
    -- It appears that the application of 'concealcursor' occurs after this
    -- code runs.
    vim.cmd('keepjumps normal! g0')
    if fn.winline() < winline then
      -- g0 may move to the preceding line (e.g., if a character that can't be
      -- displayed, like <99>, spans screen lines).
      vim.cmd('keepjumps normal! l')
    end
    -- We use col() here for tracking movement in addition to wincol(), since
    -- the cursor sometimes doesn't move (e.g., when there is concealed text).
    -- Using wincol() accommodates virtual text, so we use that too.
    prior = nil
    -- Limit the number of steps as a precaution. The line length, in bytes,
    -- accounts for characters that are concealed with empty text (the cursor
    -- won't move for those characters), and the window width bounds the number
    -- of steps that can be taken over normal characters. We double to be safe.
    local line = fn.line('.')
    local line_bytes = fn.line2byte(line + 1) - fn.line2byte(line)
    max_steps = (fn.winwidth(0) + line_bytes) * 2
    steps = 0
    -- Redraw for proper handling of concealed text.
    -- https://github.com/dstein64/nvim-scrollview/issues/127#issuecomment-1939726646
    vim.cmd('redraw')
    while fn.wincol() < wincol
        and not vim.deep_equal(prior, {fn.col('.'), fn.wincol()})
        and steps < max_steps do
      steps = steps + 1
      prior = {fn.col('.'), fn.wincol()}
      vim.cmd('keepjumps normal! l')
      -- Redraw for proper handling of concealed text.
      -- https://github.com/dstein64/nvim-scrollview/issues/127#issuecomment-1939726646
      vim.cmd('redraw')
      -- If we moved to the next screen line (e.g., with 'wrap' set), move back
      -- and break.
      if fn.winline() > winline then
        vim.cmd('keepjumps normal! h')
        break
      end
    end

    api.nvim_set_option('whichwrap', whichwrap)
  end)
end

-- Returns scrollview bar properties for the specified window. An empty
-- dictionary is returned if there is no corresponding scrollbar.
local get_scrollview_bar_props = function(winid)
  for _, scrollview_winid in ipairs(get_scrollview_windows()) do
    local props = api.nvim_win_get_var(scrollview_winid, PROPS_VAR)
    if props.type == BAR_TYPE and props.parent_winid == winid then
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
    local props = api.nvim_win_get_var(scrollview_winid, PROPS_VAR)
    if props.type == SIGN_TYPE and props.parent_winid == winid then
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

-- Refreshes scrollbars. Global state is initialized and restored.
local refresh_bars = function()
  vim.g.scrollview_refreshing = true
  local state = init()
  local resume_memoize = memoize
  start_memoize()
  -- Use a pcall block, so that unanticipated errors don't interfere. The
  -- worst case scenario is that bars won't be shown properly, which was
  -- deemed preferable to an obscure error message that can be interrupting.
  pcall(function()
    if in_command_line_window() then return end
    -- Don't refresh when the current window shows a scrollview buffer. This
    -- could cause a loop where TextChanged keeps firing.
    for _, scrollview_bufnr in ipairs({sign_bufnr, bar_bufnr}) do
      if scrollview_bufnr ~= -1 and to_bool(fn.bufexists(scrollview_bufnr)) then
        local windows = fn.getbufinfo(scrollview_bufnr)[1].windows
        if vim.tbl_contains(windows, api.nvim_get_current_win()) then
          return
        end
      end
    end
    -- Existing windows are determined before adding new windows, but removed
    -- later (they have to be removed after adding to prevent flickering from
    -- the delay between removal and adding).
    local existing_barids = {}
    local existing_signids = {}
    for _, winid in ipairs(get_scrollview_windows()) do
      local props = api.nvim_win_get_var(winid, PROPS_VAR)
      if props.type == BAR_TYPE then
        table.insert(existing_barids, winid)
      elseif props.type == SIGN_TYPE then
        table.insert(existing_signids, winid)
      end
    end
    local target_wins = {}
    for winnr = 1, fn.winnr('$') do
      local winid = fn.win_getid(winnr)
      table.insert(target_wins, winid)
    end
    -- Execute sign group callbacks. We don't do this when handle_mouse is
    -- running, since it's not necessary and for the cursor sign, it can result
    -- in incorrect positioning (keeping the cursor at the same position also
    -- results in incorrect positioning, but this was deemed preferable).
    if not handling_mouse then
      for group, callback in pairs(sign_group_callbacks) do
        if is_sign_group_active(group) then
          callback()
        end
      end
    end
    -- Reset highlight group name mapping (and table size) for each refresh
    -- cycle.
    highlight_lookup = {}
    highlight_lookup_size = 0
    -- Delete all signs and highlights in the sign buffer.
    if sign_bufnr ~= -1 and to_bool(fn.bufexists(sign_bufnr)) then
      api.nvim_buf_set_option(sign_bufnr, 'modifiable', true)
      -- Don't use fn.deletebufline to avoid the "--No lines in buffer--"
      -- message that shows when the buffer is empty.
      api.nvim_buf_set_lines(
        sign_bufnr, 0, api.nvim_buf_line_count(sign_bufnr), true, {})
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
        if bar_winid ~= -1 and existing_winid == bar_winid then
          table.remove(existing_barids)
        end
        -- Repeat a similar process for signs.
        show_signs(winid, existing_signids, bar_winid)
      end
    end
    local existing_wins = concat(existing_barids, existing_signids)
    for _, winid in ipairs(existing_wins) do
      close_scrollview_window(winid)
    end
  end)
  reset_win_workspaces()
  if not resume_memoize then
    stop_memoize()
    reset_memoize()
  end
  restore(state)
  vim.g.scrollview_refreshing = false
end

-- This function refreshes the bars asynchronously. This works better than
-- updating synchronously in various scenarios where updating occurs in an
-- intermediate state of the editor (e.g., when closing a command-line window),
-- which can result in bars being placed where they shouldn't be.
-- WARN: For debugging, it's helpful to use synchronous refreshing, so that
-- e.g., echom works as expected.
local refresh_bars_async = function()
  pending_async_refresh_count = pending_async_refresh_count + 1
  -- Use defer_fn twice so that refreshing happens after other processing. #59.
  vim.defer_fn(function()
    vim.defer_fn(function()
      pending_async_refresh_count = math.max(0, pending_async_refresh_count - 1)
      if pending_async_refresh_count > 0 then
        -- If there are asynchronous refreshes that will occur subsequently,
        -- don't execute this one.
        return
      end
      -- ScrollView may have already been disabled by time this callback
      -- executes asynchronously.
      if vim.g.scrollview_enabled then
        refresh_bars()
      end
    end, 0)
  end, 0)
end

if to_bool(fn.exists('&mousemoveevent')) then
  -- pcall is not necessary here to avoid an error in some cases (Neovim
  -- #17273), since that would be necessary for nvim<0.8, where this code would
  -- not execute ('mousemoveevent' was introduced in nvim==0.8).
  vim.on_key(function(str)
    if vim.o.mousemoveevent and string.find(str, MOUSEMOVE) then
      mousemove_received = true
      pending_mousemove_callback_count = pending_mousemove_callback_count + 1
      vim.defer_fn(function()
        local resume_memoize = memoize
        start_memoize()
        pcall(function()
          pending_mousemove_callback_count =
          math.max(0, pending_mousemove_callback_count - 1)
          if pending_mousemove_callback_count > 0 then
            -- If there are mousemove callbacks that will occur subsequently,
            -- don't execute this one.
            return
          end
          for _, winid in ipairs(get_scrollview_windows()) do
            local props = api.nvim_win_get_var(winid, PROPS_VAR)
            if not vim.tbl_isempty(props) and props.highlight_fn ~= nil then
              props.highlight_fn(is_mouse_over_scrollview_win(winid))
            end
          end
        end)
        if not resume_memoize then
          stop_memoize()
          reset_memoize()
        end
      end, 0)
    end
  end)
end

-- *************************************************
-- * Main (entry points)
-- *************************************************

-- INFO: Asynchronous refreshing was originally used to work around issues
-- (e.g., getwininfo(winid)[1].botline not updated yet in a synchronous
-- context). However, it's now primarily utilized because it makes the UI more
-- responsive and it permits redundant refreshes to be dropped (e.g., for mouse
-- wheel scrolling).

local enable = function()
  vim.g.scrollview_enabled = true
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
      autocmd WinEnter * lua require('scrollview').remove_if_command_line_window()

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
      autocmd QuitPre * lua require('scrollview').remove_bars()

      " === Scrollbar Refreshing ===

      " The following handles bar refreshing when changing the current window.
      autocmd WinEnter,TermEnter * lua require('scrollview').refresh_bars_async()

      " The following restores bars after leaving the command-line window.
      " Refreshing must be asynchronous, since the command line window is still
      " in an intermediate state when the CmdwinLeave event is triggered.
      autocmd CmdwinLeave * lua require('scrollview').refresh_bars_async()

      " The following handles scrolling events, which could arise from various
      " actions, including resizing windows, movements (e.g., j, k), or
      " scrolling (e.g., <ctrl-e>, zz).
      autocmd WinScrolled * lua require('scrollview').refresh_bars_async()

      " The following handles window resizes that don't trigger WinScrolled
      " (e.g., leaving the command line window). This was added in Neovim 0.9,
      " so its presence needs to be tested.
      if exists('##WinResized')
        autocmd WinResized * lua require('scrollview').refresh_bars_async()
      endif

      " The following handles the case where text is pasted. Handling for
      " TextChangedI is not necessary since WinScrolled will be triggered if
      " there is corresponding scrolling when pasting.
      autocmd TextChanged * lua require('scrollview').refresh_bars_async()

      " Refresh in insert mode if the number of lines changes. This handles the
      " case where lines are deleted in insert mode. This is also used as a
      " precaution, as there may be other possible scenarios where WinScrolled
      " does not fire when the number of lines changes in insert mode.
      " WARN: This does not handle a change to the number of displayed lines
      " (unlike buffer lines, the number of displayed lines is affected by diff
      " filler, virtual text lines, folds, and/or line wrapping).
      " TODO: If you switch to using nvim_create_autocmd (requires nvim>=0.7),
      " you can avoid using the Vim variable g:scrollview_ins_mode_buf_lines,
      " instead using a Lua variable (defined under "Globals" above). The Vim
      " variable can also be deleted from autoload/scrollview.vim.
      autocmd InsertEnter *
            \ let g:scrollview_ins_mode_buf_lines = nvim_buf_line_count(0)
      autocmd TextChangedI,TextChangedP *
            \   if g:scrollview_ins_mode_buf_lines !=# nvim_buf_line_count(0)
            \ |   execute "lua require('scrollview').refresh_bars_async()"
            \ | endif
            \ | let g:scrollview_ins_mode_buf_lines = nvim_buf_line_count(0)

      " The following handles hiding the scrollbar and signs in insert mode,
      " and unhiding upon leaving insert mode, when such functionality is
      " enabled.
      " WARN: This does not handle the scenario where insert mode is left with
      " <ctrl-c>. We use a key sequence callback to handle that.
      autocmd InsertEnter,InsertLeave *
            \   if g:scrollview_hide_bar_for_insert
            \       || !empty(g:scrollview_signs_hidden_for_insert)
            \ |   execute "lua require('scrollview').refresh_bars_async()"
            \ | endif

      " Refresh bars if the cursor intersects a scrollview window (and the
      " corresponding option is set). We check for Neovim 0.7 since this
      " functionality utilizes the Neovim autocmd API.
      autocmd CursorMoved,CursorMovedI *
            \   if g:scrollview_hide_on_cursor_intersect
            \       && has('nvim-0.7')
            \       && luaeval('require("scrollview").cursor_intersects_scrollview()')
            \ |   execute "lua require('scrollview').refresh_bars_async()"
            \ | endif

      " Refresh scrollview when text is changed in insert mode (and
      " scrollview_hide_on_text_intersect is set). This way, scrollbars and
      " signs will appear/hide accordingly when modifying text.
      autocmd TextChangedI *
            \   if g:scrollview_hide_on_text_intersect
            \ |   execute "lua require('scrollview').refresh_bars_async()"
            \ | endif

      " The following handles when :e is used to load a file. The asynchronous
      " version handles a case where :e is used to reload an existing file, that
      " is already scrolled. This avoids a scenario where the scrollbar is
      " refreshed while the window is an intermediate state, resulting in the
      " scrollbar moving to the top of the window.
      autocmd BufWinEnter * lua require('scrollview').refresh_bars_async()

      " The following is used so that bars are shown when cycling through tabs.
      autocmd TabEnter * lua require('scrollview').refresh_bars_async()

      autocmd VimResized * lua require('scrollview').refresh_bars_async()

      " Scrollbar positions can become stale after adding or removing winbars.
      autocmd OptionSet winbar lua require('scrollview').refresh_bars_async()

      " Scrollbar positions can become stale when the number column or sign
      " column is added or removed (when scrollview_base=buffer).
      autocmd OptionSet number,relativenumber,signcolumn
            \ lua require('scrollview').refresh_bars_async()

      " The following handles scrollbar/sign generation for new floating
      " windows.
      autocmd WinNew * lua require('scrollview').refresh_bars_async()
    augroup END
  ]])
  -- The initial refresh is asynchronous, since :ScrollViewEnable can be used
  -- in a context where Neovim is in an intermediate state. For example, for
  -- ':bdelete | ScrollViewEnable', with synchronous processing, the 'topline'
  -- and 'botline' in getwininfo's results correspond to the existing buffer
  -- that :bdelete was called on.
  refresh_bars_async()
end

local disable = function()
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
    vim.g.scrollview_enabled = false
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

-- With no argument, toggles the current state. Otherwise, true enables and
-- false disables.
-- WARN: 'state' is enable/disable state. This differs from how "state" is used
-- in other parts of the code (for saving and restoring environment).
local set_state = function(state)
  if state == vim.NIL then
    state = nil
  end
  if state == nil then
    state = not vim.g.scrollview_enabled
  end
  if state then
    enable()
  else
    disable()
  end
end

local refresh = function()
  if vim.g.scrollview_enabled then
    -- This refresh is asynchronous to keep interactions responsive (e.g.,
    -- mouse wheel scrolling, as redundant async refreshes are dropped). If
    -- scenarios necessitate synchronous refreshes, the interface would have to
    -- be updated (e.g., :ScrollViewRefresh --sync) to accommodate (as there is
    -- currently only a single refresh command and a single refresh <plug>
    -- mapping, both utilizing whatever is implemented here).
    refresh_bars_async()
  end
end

-- Move the cursor to the specified line with a sign. Can take (1) an integer
-- value, (2) '$' for the last line, (3) 'next' for the next line, or (4)
-- 'prev' for the previous line. 'groups' specifies the sign groups that are
-- considered; use nil for all. 'args' is a dictionary with optional arguments.
local move_to_sign_line = function(location, groups, args)
  if groups ~= nil then
    groups = utils.sorted(groups)
  end
  if args == nil then
    args = {}
  end
  local lines = {}
  local winid = api.nvim_get_current_win()
  for _, sign_props in ipairs(get_scrollview_sign_props(winid)) do
    local eligible = groups == nil
    if not eligible then
      local group = sign_specs[sign_props.sign_spec_id].group
      local idx = utils.binary_search(groups, group)
      eligible = idx <= #groups and groups[idx] == group
    end
    if eligible then
      for _, line in ipairs(sign_props.lines) do
        table.insert(lines, line)
      end
    end
  end
  if vim.tbl_isempty(lines) then
    return
  end
  table.sort(lines)
  lines = remove_duplicates(lines)
  local current = fn.line('.')
  local target = nil
  if location == 'next' then
    local count = args.count or 1
    target = subsequent(lines, current, count, vim.o.wrapscan)
  elseif location == 'prev' then
    local count = args.count or 1
    target = preceding(lines, current, count, vim.o.wrapscan)
  elseif location == '$' then
    target = lines[#lines]
  elseif type(location) == 'number' then
    target = lines[location]
  end
  if target ~= nil then
    vim.cmd('normal!' .. target .. 'G')
  end
end

-- Move the cursor to the next line that has a sign.
local next = function(groups, count)  -- luacheck: ignore 431 (shadowing upvalue next)
  move_to_sign_line('next', groups, {count = count})
end

-- Move the cursor to the previous line that has a sign.
local prev = function(groups, count)
  move_to_sign_line('prev', groups, {count = count})
end

-- Move the cursor to the first line with a sign.
local first = function(groups)
  move_to_sign_line(1, groups)
end

-- Move the cursor to the last line with a sign.
local last = function(groups)
  move_to_sign_line('$', groups)
end

-- Echo a legend of scrollview symbols. 'groups' specifies the sign groups
-- that are considered; use nil for all. 'full' indicates whether all
-- registered signs (including those from disabled groups) should be included
-- in the legend, as opposed to just those that are currently visible.
local legend = function(groups, full)
  local included = {}  -- maps groups to their inclusion state
  for _, group in pairs(get_sign_groups()) do
    included[group] = groups == nil and true or false
  end
  if groups ~= nil then
    for _, group in ipairs(groups) do
      included[group] = true
    end
  end
  local items = {}
  local add_scrollbar_item = function()
    table.insert(items, {
      name = 'scrollbar',
      extra = nil,
      highlight = 'ScrollView',
      symbol = get_scrollbar_character(),
    })
  end
  if full then
    add_scrollbar_item()
    for _, sign_spec in pairs(sign_specs) do
      if included[sign_spec.group] then
        local count = math.max(#sign_spec.symbol, #sign_spec.highlight)
        for idx = 1, count do
          local symbol = sign_spec.symbol[math.min(idx, #sign_spec.symbol)]
          local highlight =
            sign_spec.highlight[math.min(idx, #sign_spec.highlight)]
          table.insert(items, {
            name = sign_spec.group,
            extra = sign_spec.variant,
            highlight = highlight,
            symbol = symbol,
          })
        end
      end
    end
  else
    for _, winid in ipairs(get_scrollview_windows()) do
      local props = api.nvim_win_get_var(winid, PROPS_VAR)
      if props.type == BAR_TYPE then
        add_scrollbar_item()
      elseif props.type == SIGN_TYPE then
        local sign_spec = sign_specs[props.sign_spec_id]
        if included[sign_spec.group] then
          table.insert(items, {
            name = sign_spec.group,
            extra = sign_spec.variant,
            highlight = props.highlight,
            symbol = props.symbol,
          })
        end
      else
        error('Unknown props type: ' .. props.type)
      end
    end
  end
  for _, item in ipairs(items) do
    -- Check for the expected fields, since other code changes would be
    -- necessary if the fields change (the sorting code later in this
    -- function).
    local keys = {}
    for key, _ in pairs(item) do
      if key ~= 'name'
          and key ~= 'extra'
          and key ~= 'symbol'
          and key ~= 'highlight' then
        error('Unknown key: ' .. key)
      end
      table.insert(keys, key)
    end
    -- 'extra' is not required.
    for _, key in ipairs({'name', 'symbol', 'highlight'}) do
      if item[key] == nil then
        error('Missing key: ' .. key)
      end
    end
  end
  table.sort(items, function(a, b)
    if a.name == 'scrollbar' and b.name ~= 'scrollbar' then
      return true
    end
    if a.name ~= 'scrollbar' and b.name == 'scrollbar' then
      return false
    end
    if a.name ~= b.name then
      return a.name < b.name
    elseif a.extra ~= b.extra then
      if a.extra ~= nil and b.extra ~= nil then
        return a.extra < b.extra
      elseif a.extra == nil then
        return true
      else
        -- b.extra == nil
        return false
      end
    elseif a.symbol ~= b.symbol then
      return a.symbol < b.symbol
    else
      return a.highlight < b.highlight
    end
  end)
  local echo_list = {}
  table.insert(echo_list, {'Title', 'nvim-scrollview'})
  for idx, item in ipairs(items) do
    -- Skip duplicates. Duplicates can arise since the same sign can be shown
    -- in different windows or multiple times in the same window.
    if idx == 1 or not vim.deep_equal(item, items[idx - 1]) then
      table.insert(echo_list, {'None', '\n'})
      table.insert(echo_list, {item.highlight, item.symbol})
      table.insert(echo_list, {'None', ' '})
      table.insert(echo_list, {'None', item.name})
      if item.extra ~= nil then
        table.insert(echo_list, {'None', ' '})
        table.insert(echo_list, {'NonText', item.extra})
      end
    end
  end
  echo(echo_list)
end

-- 'button' can be 'left', 'middle', 'right', 'x1', or 'x2'. 'c-' or 'm-' can be
-- prepended for the control-key and alt-key variants. If primary is true, the
-- handling is for navigation (dragging scrollbars and navigating to signs).
-- If primary is false, the handling is for context (showing popups with info).
local handle_mouse = function(button, is_primary, init_props, init_mousepos)
  local valid_buttons = {
    'left', 'middle', 'right', 'x1', 'x2',
    'c-left', 'c-middle', 'c-right', 'c-x1', 'c-x2',
    'm-left', 'm-middle', 'm-right', 'm-x1', 'm-x2',
  }
  if not vim.tbl_contains(valid_buttons, button) then
    error('Unsupported button: ' .. button)
  end
  if is_primary == nil then
    is_primary = true
  end
  local mousedown = t('<' .. button .. 'mouse>')
  local mouseup = t('<' .. button .. 'release>')
  -- We don't support mouse functionality in visual nor select mode.
  if is_visual_mode(fn.mode()) or is_select_mode(fn.mode()) then
    vim.cmd('normal! ' .. t'<esc>')
    vim.cmd('redraw')
  end
  local state = init()
  local resume_memoize = memoize
  start_memoize()
  pcall(function()
    handling_mouse = true
    -- Mouse handling is not relevant in the command line window since
    -- scrollbars are not shown. Additionally, the overlay cannot be closed
    -- from that mode.
    if in_command_line_window() then
      return
    end
    local count = 0
    local winid  -- The target window ID for a mouse scroll.
    local scrollbar_offset
    local previous_row
    local idx = 1
    local chars_props = {}
    local char, mouse_winid, mouse_row
    local props
    -- Computing this prior to the first mouse event could distort the location
    -- since this could be an expensive operation (and the mouse could move).
    local topline_lookup = nil
    -- For clicks on a scrollbar, we save the wincol and winline so they can be
    -- restored after dragging.
    local init_wincol
    local init_winline
    while true do
      while true do
        if count == 0 then
          chars_props = {{
            char = mousedown,
            str_idx = 1,
            charmod = 0,
            mouse_winid = init_mousepos.winid,
            mouse_row = init_mousepos.winrow,
            mouse_col = init_mousepos.wincol,
          }}
        else
          idx = idx + 1
          if idx > #chars_props then
            idx = 1
            chars_props = select(2, read_input_stream())
          end
        end
        local char_props = chars_props[idx]
        char = char_props.char
        mouse_winid = char_props.mouse_winid
        mouse_row = char_props.mouse_row
        -- Break unless it's a mouse drag followed by another mouse drag, so
        -- that the first drag is skipped.
        if mouse_winid == 0
            or vim.tbl_contains({mousedown, mouseup}, char) then
          break
        end
        if idx >= #char_props then break end
        local next_char_props = chars_props[idx + 1]
        if next_char_props.mouse_winid == 0
            or vim.tbl_contains({mousedown, mouseup}, next_char_props.char) then
          break
        end
      end
      if char == t'<esc>' then
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
      -- WARN: This handling may no longer be necessary after addressing Issue
      -- #140, but was kept as a precaution.
      if char ~= '\x80\xf5X' or count == 0 then
        if mouse_winid == 0 then
          -- There was no mouse event.
          return
        end
        if char == mouseup then
          if count == 0 then  -- luacheck: ignore 542 (an empty if branch)
            -- No initial mousedown was captured. This can't happen with the
            -- approach used to resolve Issue #140.
          elseif count == 1 then  -- luacheck: ignore 542 (an empty if branch)
            -- A scrollbar was clicked, but there was no corresponding drag.
          else
            -- A scrollbar was clicked and there was a corresponding drag.
            -- The current window (from prior to scrolling) is not changed.
            -- Refresh scrollbars to handle the scenario where
            -- scrollview_hide_on_float_intersect is enabled and dragging
            -- resulted in a scrollbar overlapping a floating window.
            refresh_bars()
            -- We only restore the cursor after dragging is finished. The
            -- cursor position can't be changed while dragging (but it stays in
            -- the same place when there aren't wrapped lines).
            set_cursor_position(winid, init_winline, init_wincol)
          end
          return
        end
        if count == 0 then
          props = init_props
          local clicked_bar = props.type == BAR_TYPE
          local clicked_sign = props.type == SIGN_TYPE
          if clicked_sign and is_primary then
            -- There was a primary click on a sign. Navigate to the next
            -- sign_props line after the cursor.
            api.nvim_win_call(mouse_winid, function()
              local current = fn.line('.')
              local target = subsequent(props.lines, current, 1, true)
              vim.cmd('normal!' .. target .. 'G')
            end)
            refresh_bars()
            return
          end
          if not is_primary then
            -- There was a secondary click on either a scrollbar or sign. Show
            -- a popup accordingly.
            -- Menus starting with ']' are excluded from the main menu bar
            -- (:help hidden-menus).
            local menu_name = ']ScrollViewPopUp'
            local lhs, rhs
            local mousepos = fn.getmousepos()
            if clicked_sign then
              local group = sign_specs[props.sign_spec_id].group
              lhs = menu_name .. '.' .. group
              rhs = '<cmd>let g:scrollview_disable_sign_group = "'
                .. group .. '"<cr>'
              vim.cmd('anoremenu ' .. lhs .. ' ' .. rhs)
              local variant = sign_specs[props.sign_spec_id].variant
              if variant ~= nil then
                lhs = menu_name .. '.' .. variant
                rhs = '<nop>'
                vim.cmd('anoremenu ' .. lhs .. ' ' .. rhs)
              end
              lhs = menu_name .. '.-sep-'
              rhs = '<nop>'
              vim.cmd('anoremenu ' .. lhs .. ' ' .. rhs)
              -- For nvim<0.11, we limit the number of items on the popup
              -- menu to prevent a scenario where the menu pops up and then
              -- disappears unless the mouse button is held. The issue is not
              -- present as of nvim commit 842725e.
              local menu_slots_available = nil
              if not to_bool(fn.has('nvim-0.11')) then
                menu_slots_available = vim.o.lines
                menu_slots_available = math.max(
                  menu_slots_available - mousepos.screenrow,
                  mousepos.screenrow - 1
                )
                -- WARN: menu_info can have issues if used with multiple modes
                -- (Vim Issue #15154).
                menu_slots_available = menu_slots_available
                  - #fn.menu_info(menu_name).submenus
              end
              for line_idx, line in ipairs(props.lines) do
                if menu_slots_available ~= nil
                    and line_idx > menu_slots_available then
                  break
                end
                lhs = menu_name .. '.' .. line
                rhs = string.format(
                  '<cmd>call win_execute(%d, "normal! %dG")<cr>',
                  props.parent_winid,
                  line
                )
                vim.cmd('anoremenu ' .. lhs .. ' ' .. rhs)
              end
            else
              local popup_title = clicked_bar and 'scrollbar' or 'scrollview'
              lhs = menu_name .. '.' .. popup_title
              rhs = '<nop>'
              vim.cmd('anoremenu ' .. lhs .. ' ' .. rhs)
            end
            -- We create a temporary floating window for positioning the cursor
            -- at the mouse pointer. This way, the popup opens where the click
            -- occurs.
            if popup_bufnr == -1
                or not to_bool(fn.bufloaded(popup_bufnr)) then
              if popup_bufnr == -1 then
                popup_bufnr = api.nvim_create_buf(false, true)
              end
              -- Other plugins might have unloaded the buffer. #104
              fn.bufload(popup_bufnr)
              api.nvim_buf_set_option(popup_bufnr, 'modifiable', false)
              api.nvim_buf_set_option(popup_bufnr, 'buftype', 'nofile')
              api.nvim_buf_set_option(popup_bufnr, 'swapfile', false)
              api.nvim_buf_set_option(popup_bufnr, 'bufhidden', 'hide')
              api.nvim_buf_set_option(popup_bufnr, 'buflisted', false)
              -- Don't turn off undo for Neovim 0.9.0 and 0.9.1 since Neovim
              -- could crash, presumably from Neovim #24289. #111, #115
              if not to_bool(fn.has('nvim-0.9'))
                  or to_bool(fn.has('nvim-0.9.2')) then
                api.nvim_buf_set_option(popup_bufnr, 'undolevels', -1)
              end
            end
            local popup_win = api.nvim_open_win(popup_bufnr, false, {
              relative = 'editor',
              focusable = false,
              border = 'none',
              width = 1,
              height = 1,
              row = mousepos.screenrow - 1,
              col = mousepos.screencol - 1,
              zindex = 1,
              style = 'minimal'
            })
            api.nvim_set_current_win(popup_win)
            vim.cmd('popup ' .. menu_name)
            if vim.g.scrollview_disable_sign_group ~= vim.NIL then
              local group = vim.g.scrollview_disable_sign_group
              vim.g.scrollview_disable_sign_group = vim.NIL
              vim.cmd('silent! aunmenu ' .. menu_name)
              lhs = menu_name .. '.disable'
              rhs = '<cmd>call timer_start('
                .. '0, {-> execute("ScrollViewDisable ' .. group .. '")})<cr>'
              vim.cmd('anoremenu ' .. lhs .. ' ' .. rhs)
              vim.cmd('popup ' .. menu_name)
            end
            vim.cmd('silent! aunmenu ' .. menu_name)
            api.nvim_win_close(popup_win, true)
            refresh_bars()
            return
          end
          -- There was a primary click on a scrollbar.
          -- It's possible that the clicked scrollbar is out-of-sync. Refresh
          -- the scrollbars and check if the mouse is still over a scrollbar. If
          -- not, ignore all mouse events until a mouseup. This approach was
          -- deemed preferable to refreshing scrollbars initially, as that could
          -- result in unintended clicking/dragging where there is no scrollbar.
          refresh_bars()
          vim.cmd('redraw')
          props = get_scrollview_bar_props(mouse_winid)
          if vim.tbl_isempty(props)
              or props.type ~= BAR_TYPE
              or mouse_row < props.row
              or mouse_row >= props.row + props.height then
            while fn.getchar() ~= mouseup do end
            return
          end
          -- By this point, the click on a scrollbar was successful.
          winid = mouse_winid
          api.nvim_win_call(winid, function()
            init_wincol = fn.wincol()
            init_winline = fn.winline()
          end)
          scrollbar_offset = props.row - mouse_row
          previous_row = props.row
        end
        local winheight = get_window_height(winid)
        local mouse_winrow
        if mouse_winid == COMMAND_LINE_WINID then
          mouse_winrow = vim.go.lines - vim.go.cmdheight + 1
        elseif mouse_winid == TABLINE_WINID then
          mouse_winrow = 1
        else
          mouse_winrow = fn.getwininfo(mouse_winid)[1].winrow
        end
        local winrow = fn.getwininfo(winid)[1].winrow
        local window_offset = mouse_winrow - winrow
        local row = mouse_row + window_offset + scrollbar_offset
        row = math.min(row, winheight)
        row = math.max(1, row)
        if vim.g.scrollview_include_end_region then
          -- Don't allow scrollbar to overflow.
          row = math.min(row, winheight - props.height + 1)
        end
        -- Only update scrollbar if the row changed.
        if previous_row ~= row then
          if topline_lookup == nil then
            topline_lookup = get_topline_lookup(winid)
          end
          local topline = topline_lookup[row]
          topline = math.max(1, topline)
          if row == 1 then
            -- If the scrollbar was dragged to the top of the window, always
            -- show the first line.
            topline = 1
          end
          set_topline(winid, topline)
          if api.nvim_win_get_option(winid, 'scrollbind')
              or api.nvim_win_get_option(winid, 'cursorbind') then
            refresh_bars()
            props = get_scrollview_bar_props(winid)
          end
          props = move_scrollbar(props, row)  -- luacheck: ignore
          -- Refresh since sign backgrounds might be stale, for signs that
          -- switched intersection state with scrollbar. This is fast, from
          -- caching.
          refresh_bars()
          props = get_scrollview_bar_props(winid)
          -- Apply appropriate highlighting where relevant.
          if mousemove_received
              and to_bool(fn.exists('&mousemoveevent'))
              and vim.o.mousemoveevent then
            -- But be sure to keep the scrollbar highlighted.
            if not vim.tbl_isempty(props) and props.highlight_fn ~= nil then
              props.highlight_fn(true)
            end
            -- Be sure that signs are not highlighted. Without this handling,
            -- signs could be higlighted if a sign is moved to the same
            -- position as the cursor while dragging a scrollbar.
            for _, winid2 in ipairs(get_scrollview_windows()) do
              local props2 = api.nvim_win_get_var(winid2, PROPS_VAR)
              if not vim.tbl_isempty(props2)
                  and props2.highlight_fn ~= nil
                  and props2.type == SIGN_TYPE then
                props2.highlight_fn(false)
              end
            end
          end
          -- Window workspaces may still be present as a result of the
          -- earlier commands. Remove prior to redrawing.
          reset_win_workspaces()
          vim.cmd('redraw')
          previous_row = row
        end
        count = count + 1
      end  -- end if
    end  -- end while
  end)  -- end pcall
  reset_win_workspaces()  -- as a precaution
  if not resume_memoize then
    stop_memoize()
    reset_memoize()
  end
  restore(state)
  handling_mouse = false
end

-- Checks if an input event is over a scrollview window and should be handled.
-- 'str' is the representation of a key press (as represented by the argument
-- to on_key, which e.g., would be "\<leftmouse>" or
-- nvim_replace_termcodes('<leftmouse>', 1, 1, 1)). Returns either a single
-- value, false, or multiple values, true along with a table containing
-- 'button', 'is_primary', 'props', and 'mousepos'.
local should_handle_mouse = function(str)
  if not vim.g.scrollview_enabled then
    return false
  end
  if handling_mouse then
    return false
  end
  local normalize = function(button)
    if button == vim.NIL then
      button = nil
    elseif button:sub(-1) == '!' then
      -- Remove a trailing "!", which was supported in older versions of the
      -- plugin for clobbering mappings.
      button = button:sub(1, -2)
    end
    return button
  end
  local primary = vim.g.scrollview_mouse_primary
  local secondary = vim.g.scrollview_mouse_secondary
  if not to_bool(fn.has('nvim-0.11')) then
    -- On nvim<0.11, mouse mappings are created when the plugin starts, so we
    -- don't support changes to the settings.
    primary = vim.g.scrollview_init_mouse_primary
    secondary = vim.g.scrollview_init_mouse_secondary
  end
  primary = normalize(primary)
  secondary = normalize(secondary)
  if primary == nil and secondary == nil then
    return false
  end
  if str ~= MOUSE_LOOKUP[primary] and str ~= MOUSE_LOOKUP[secondary] then
    return false
  end
  local mousepos = vim.deepcopy(fn.getmousepos())
  -- Ignore clicks on the command line.
  if mousepos.screenrow > vim.go.lines - vim.go.cmdheight then
    return false
  end
  -- Ignore clicks on the tabline. When the click is on a floating window
  -- covering the tabline, mousepos.winid will be set to that floating window's
  -- winid. Otherwise, mousepos.winid would correspond to an ordinary window ID
  -- (seemingly for the window below the tabline).
  if vim.deep_equal(fn.win_screenpos(1), {2, 1})  -- Checks for presence of a tabline.
      and mousepos.screenrow == 1
      and is_ordinary_window(mousepos.winid) then
    return false
  end
  -- Adjust for a winbar.
  if mousepos.winid > 0
      and to_bool(tbl_get(fn.getwininfo(mousepos.winid)[1], 'winbar', 0)) then
    mousepos.winrow = mousepos.winrow - 1
  end
  -- Adjust for floating window borders.
  local mouse_winid = mousepos.winid
  local config = api.nvim_win_get_config(mouse_winid)
  local is_float = tbl_get(config, 'relative', '') ~= ''
  if is_float then
    local border = config.border
    if border ~= nil and islist(border) and #border == 8 then
      if border[BORDER_TOP] ~= '' then
        mousepos.winrow = mousepos.winrow - 1
      end
      if border[BORDER_LEFT] ~= '' then
        mousepos.wincol = mousepos.wincol - 1
      end
    end
  end
  local mouse_row = mousepos.winrow
  local mouse_col = mousepos.wincol
  local props = get_scrollview_bar_props(mouse_winid)
  local clicked_bar = false
  local clicked_sign = false
  if not vim.tbl_isempty(props) then
    clicked_bar = mouse_row >= props.row
      and mouse_row < props.row + props.height
      and mouse_col >= props.col
      and mouse_col <= props.col
  end
  -- First check for a click on a sign and handle accordingly.
  for _, sign_props in ipairs(get_scrollview_sign_props(mouse_winid)) do
    if mouse_row == sign_props.row
        and mouse_col >= sign_props.col
        and mouse_col <= sign_props.col + sign_props.width - 1
        and (not clicked_bar or sign_props.zindex > props.zindex) then
      clicked_sign = true
      clicked_bar = false
      props = sign_props
      break
    end
  end
  if not clicked_bar and not clicked_sign then
    return false
  end
  local button, is_primary
  if str == MOUSE_LOOKUP[primary] then
    button, is_primary = primary, true
  elseif str == MOUSE_LOOKUP[secondary] then
    button, is_primary = secondary, false
  else
    -- This should not be reached, since there's a return earlier for this
    -- scenario.
    return false
  end
  local data = {
    button = button,
    is_primary = is_primary,
    props = props,
    mousepos = mousepos,
  }
  return true, data
end

-- With nvim<0.11, mouse functionality is handled with mappings, not
-- vim.on_key, since the on_key handling for the mouse requires nvim==0.11,
-- for the ability to ignore the key by returning the empty string.
if to_bool(fn.has('nvim-0.11')) then  -- Neovim 0.11 for ignoring keys
  -- pcall is not necessary here to avoid an error in some cases (Neovim
  -- #17273), since that would be necessary for nvim<0.8, where this code
  -- would not execute (this only runs on nvim>=0.11).
  vim.on_key(function(str)
    local should_handle, data = should_handle_mouse(str)
    if should_handle then
      handle_mouse(data.button, data.is_primary, data.props, data.mousepos)
      return ''  -- ignore the mouse event
    end
  end)
end

-- A convenience function for setting global options with
-- require('scrollview').setup().
local setup = function(opts)
  opts = opts or {}
  for key, val in pairs(opts) do
    api.nvim_set_var('scrollview_' .. key, val)
  end
end

local register_sign_group = function(group)
  if sign_group_state[group] ~= nil then
    error('group is already registered: ' .. group)
  end
  sign_group_state[group] = false
end

-- Deregister a sign group and corresponding (1) sign spec registrations and
-- (2) sign group refresh callbacks. 'refresh' is an optional argument that
-- specifies whether scrollview will refresh afterwards. It defaults to true.
local deregister_sign_group = function(group, refresh_)
  if refresh_ == nil then
    refresh_ = true
  end
  sign_group_state[group] = nil
  -- The linear runtime could be reduced by mapping groups to the set of
  -- corresponding sign specs.
  for id, sign_spec in pairs(sign_specs) do
    if sign_spec.group == group then
      sign_specs[id] = nil
    end
  end
  sign_group_callbacks[group] = nil
  if refresh_ and vim.g.scrollview_enabled then
    refresh_bars()
  end
end

-- Set the refresh callback for a sign group. Set callback to nil to unset.
local set_sign_group_callback = function(group, callback)
  sign_group_callbacks[group] = callback
end

local register_sign_spec = function(specification)
  local id = sign_spec_counter + 1
  specification = copy(specification)
  specification.id = id
  local defaults = {
    current_only = false,
    extend = false,
    group = nil,
    highlight = 'Pmenu',
    priority = 50,
    show_in_folds = nil,  -- when set, overrides 'scrollview_signs_show_in_folds'
    symbol = '',  -- effectively ' '
    type = 'b',
    variant = nil,
  }
  for key, val in pairs(defaults) do
    if specification[key] == nil then
      specification[key] = val
    end
  end
  if specification.group == nil then
    error('group is required')
  end
  for _, group in ipairs({'all', 'defaults', 'scrollbar'}) do
    if specification.group == group then
      error('Invalid group: ' .. group)
    end
  end
  if sign_group_state[specification.group] == nil then
    error('group was not registered: ' .. specification.group)
  end
  -- Group names can be made up of letters, digits, and underscores, but cannot
  -- start with a digit. This matches the rules for internal variables (:help
  -- internal-variables), but is more restrictive than what is possible with
  -- e.g., nvim_buf_set_var.
  local valid_pattern = '^[a-zA-Z_][a-zA-Z0-9_]*$'
  if string.match(specification.group, valid_pattern) == nil then
    error('Invalid group: ' .. specification.group)
  end
  -- Apply the same restrictions to variants.
  if specification.variant ~= nil
      and string.match(specification.variant, valid_pattern) == nil then
    error('Invalid variant: ' .. specification.variant)
  end
  local name = 'scrollview_signs_' .. id .. '_' .. specification.group
  specification.name = name
  -- priority, symbol, and highlight can be arrays
  for _, key in ipairs({'priority', 'highlight', 'symbol',}) do
    if type(specification[key]) ~= 'table' then
      specification[key] = {specification[key]}
    else
      specification[key] = copy(specification[key])
    end
  end
  for idx, symbol in ipairs(specification.symbol) do
    symbol = symbol:gsub('\n', '')
    symbol = symbol:gsub('\r', '')
    if #symbol < 1 then symbol = ' ' end
    specification.symbol[idx] = symbol
  end
  sign_specs[id] = specification
  sign_spec_counter = id
  local registration = {
    id = id,
    name = name,
  }
  return registration
end

-- Deregister a sign specification and remove corresponding signs. 'refresh' is
-- an optional argument that specifies whether scrollview will refresh
-- afterwards. It defaults to true.
local deregister_sign_spec = function(id, refresh_)
  if refresh_ == nil then
    refresh_ = true
  end
  sign_specs[id] = nil
  if refresh_ and vim.g.scrollview_enabled then
    refresh_bars()
  end
end

-- state can be true, false, or nil to toggle.
-- WARN: 'state' is enable/disable state. This differs from how "state" is used
-- in other parts of the code (for saving and restoring environment).
local set_sign_group_state = function(group, state)
  if sign_group_state[group] == nil then
    error('Unknown group: ' .. group)
  end
  if state == vim.NIL then
    state = nil
  end
  local prior_state = sign_group_state[group]
  if state == nil then
    sign_group_state[group] = not sign_group_state[group]
  else
    sign_group_state[group] = state
  end
  if prior_state ~= sign_group_state[group] then
    refresh_bars_async()
  end
end

local get_sign_group_state = function(group)
  local result = sign_group_state[group]
  if result == nil then
    error('Unknown group: ' .. group)
  end
  return result
end

-- Indicates whether scrollview is enabled and the specified sign group is
-- enabled. Using this is more convenient than having to call (1) a
-- (hypothetical) get_state function to check if scrollview is enabled and (2)
-- a get_sign_group_state function to check if the group is enabled.
is_sign_group_active = function(group)
  return vim.g.scrollview_enabled and get_sign_group_state(group)
end

get_sign_groups = function()
  local groups = {}
  for group, _ in pairs(sign_group_state) do
    table.insert(groups, group)
  end
  return groups
end

-- Returns a list of window IDs that could potentially have signs.
local get_sign_eligible_windows = function()
  local winids = {}
  for winnr = 1, fn.winnr('$') do
    local winid = fn.win_getid(winnr)
    if should_show(winid) then
      if not is_restricted(winid) then
        table.insert(winids, winid)
      end
    end
  end
  return winids
end

-- *************************************************
-- * Synchronization
-- *************************************************

-- === Window arrangement synchronization ===

local win_seqs = {
  t('<c-w>H'), t('<c-w>J'), t('<c-w>K'), t('<c-w>L'),
  t('<c-w>r'), t('<c-w><c-r>'), t('<c-w>R')
}
for _, seq in ipairs(win_seqs) do
  register_key_sequence_callback(seq, 'nvs', refresh_bars_async)
end

-- Refresh after :wincmd.
--   :[count]winc[md]
--   :winc[md]!
-- WARN: Only text at the beginning of the command is considered.
-- WARN: CmdlineLeave is not executed for command mappings (<cmd>).
-- WARN: CmdlineLeave is not executed for commands executed from Lua
-- (e.g., vim.cmd('help')).
if api.nvim_create_autocmd ~= nil then
  api.nvim_create_autocmd('CmdlineLeave', {
    callback = function()
      if to_bool(vim.v.event.abort) then
        return
      end
      if fn.expand('<afile>') ~= ':' then
        return
      end
      local cmdline = fn.getcmdline()
      if string.match(cmdline, '^%d*winc') ~= nil then
        refresh_bars_async()
      end
    end
  })
end

-- === Mouse wheel scrolling synchronization ===

-- For nvim<0.9, scrollbars become out-of-sync when the mouse wheel is used to
-- scroll a non-current window. This is because the WinScrolled event only
-- corresponds to the current window.
local wheel_seqs = {t('<scrollwheelup>'), t('<scrollwheeldown>')}
for _, seq in ipairs(wheel_seqs) do
  register_key_sequence_callback(seq, 'nvsit', refresh_bars_async)
end

-- === Fold command synchronization ===

local zf_operator = function(type_)
  -- Handling for 'char' is needed since e.g., using linewise mark jumping
  -- results in the cursor moving to the beginning of the line for zfl, which
  -- should not move the cursor. Separate handling for 'line' is needed since
  -- e.g., with 'char' handling, zfG won't include the last line in the fold if
  -- the cursor gets positioned on the first character.
  if type_ == 'char' then
    vim.cmd('silent normal! `[zf`]')
  elseif type_ == 'line' then
    vim.cmd("silent normal! '[zf']")
  else  -- luacheck: ignore 542 (an empty if branch)
    -- Unsupported
  end
  refresh_bars_async()
end

register_key_sequence_callback('zf', 'n', function()
  -- If you don't use defer_fn, the mode will be normal (not operator pending).
  -- Here we check for operator pending since it's possible that zf is part of
  -- some other mapping that doesn't enter operator pending mode.
  vim.defer_fn(function()
    if vim.startswith(fn.mode(1), 'no') and vim.v.operator == 'zf' then
      api.nvim_set_option(
        'operatorfunc', "v:lua.require'scrollview'.zf_operator")
      -- <esc> is used to cancel waiting for a motion (from having pressed zf).
      fn.feedkeys(t('<esc>' .. 'g@'), 'nt')
    end
  end, 0)
end)
register_key_sequence_callback('zf', 'v', refresh_bars_async)

local fold_seqs = {
  'zF', 'zd', 'zD', 'zE', 'zo', 'zO', 'zc', 'zC', 'za', 'zA', 'zv',
  'zx', 'zX', 'zm', 'zM', 'zr', 'zR', 'zn', 'zN', 'zi'
}
for _, seq in ipairs(fold_seqs) do
  register_key_sequence_callback(seq, 'nv', refresh_bars_async)
end

-- === InsertLeave synchronization ===

-- InsertLeave is not triggered when leaving insert mode with <ctrl-c>. We use
-- a key sequence callback to accommodate.
register_key_sequence_callback(t('<c-c>'), 'i', function()
  if vim.g.scrollview_hide_bar_for_insert
      or not vim.tbl_isempty(vim.g.scrollview_signs_hidden_for_insert) then
    refresh_bars_async()
  end
end)

-- *************************************************
-- * API
-- *************************************************

return {
  -- Functions called internally (by autocmds and operatorfunc).
  cursor_intersects_scrollview = cursor_intersects_scrollview,
  refresh_bars_async = refresh_bars_async,
  remove_bars = remove_bars,
  remove_if_command_line_window = remove_if_command_line_window,
  zf_operator = zf_operator,

  -- Functions called by commands and mappings defined in
  -- plugin/scrollview.vim, and sign handlers.
  first = first,
  fold_count_exceeds = fold_count_exceeds,
  get_sign_eligible_windows = get_sign_eligible_windows,
  handle_mouse = handle_mouse,
  last = last,
  legend = legend,
  next = next,
  prev = prev,
  refresh = refresh,
  set_state = set_state,
  should_handle_mouse = should_handle_mouse,
  with_win_workspace = with_win_workspace,

  -- Sign registration/configuration
  deregister_sign_spec = deregister_sign_spec,
  deregister_sign_group = deregister_sign_group,
  get_sign_groups = get_sign_groups,
  is_sign_group_active = is_sign_group_active,
  register_sign_group = register_sign_group,
  register_sign_spec = register_sign_spec,
  set_sign_group_callback = set_sign_group_callback,
  set_sign_group_state = set_sign_group_state,

  -- Key sequence callback registration
  register_key_sequence_callback = register_key_sequence_callback,

  -- Functions called by tests.
  virtual_line_count_spanwise = virtual_line_count_spanwise,
  virtual_line_count_linewise = virtual_line_count_linewise,
  virtual_topline_lookup_spanwise = virtual_topline_lookup_spanwise,
  virtual_topline_lookup_linewise = virtual_topline_lookup_linewise,
  simple_topline_lookup = simple_topline_lookup,

  -- require('scrollview').setup()
  setup = setup,
}
