" *************************************************
" * Preamble
" *************************************************

if get(g:, 'loaded_scrollview', 0)
  finish
endif
let g:loaded_scrollview = 1

let s:save_cpo = &cpo
set cpo&vim

" The additional check for ##WinScrolled may be redundant, but was added in
" case early versions of nvim 0.5 didn't have that event.
if !has('nvim-0.5') || !exists('##WinScrolled')
  " Logging error with echomsg or echoerr interrupts Neovim's startup by
  " blocking. Fail silently.
  finish
endif

" *************************************************
" * User Configuration
" *************************************************

" === General ===

let g:scrollview_auto_mouse = get(g:, 'scrollview_auto_mouse', 1)
let g:scrollview_auto_workarounds = get(g:, 'scrollview_auto_workarounds', 1)
let g:scrollview_base = get(g:, 'scrollview_base', 'right')
" The plugin enters a restricted state when the number of buffer bytes exceeds
" the limit. Use -1 for no limit.
let g:scrollview_byte_limit = get(g:, 'scrollview_byte_limit', 1000000)
let g:scrollview_character = get(g:, 'scrollview_character', '')
let g:scrollview_column = get(g:, 'scrollview_column', 2)
let g:scrollview_current_only = get(g:, 'scrollview_current_only', 0)
let g:scrollview_excluded_filetypes = 
      \ get(g:, 'scrollview_excluded_filetypes', [])
let g:scrollview_hide_on_intersect =
      \ get(g:, 'scrollview_hide_on_intersect', 0)
" The plugin enters a restricted state when the number of buffer lines exceeds
" the limit. Use -1 for no limit.
let g:scrollview_line_limit = get(g:, 'scrollview_line_limit', 20000)
let g:scrollview_mode = get(g:, 'scrollview_mode', 'virtual')
let g:scrollview_on_startup = get(g:, 'scrollview_on_startup', 1)
" Whether bars and signs beyond the window boundary (out-of-bounds) are
" adjusted to be within the window.
let g:scrollview_out_of_bounds_adjust =
      \ get(g:, 'scrollview_out_of_bounds_adjust', 1)
" Using a winblend of 100 results in the bar becoming invisible on nvim-qt.
let g:scrollview_winblend = get(g:, 'scrollview_winblend', 50)
" The default zindex for floating windows is 50. A smaller value is used here
" by default so that scrollbars don't cover floating windows.
let g:scrollview_zindex = get(g:, 'scrollview_zindex', 40)

" === Signs ===

" Internal list of all builtin sign groups, populated automatically.
let s:available_signs = readdir(expand('<sfile>:p:h') .. '/../lua/scrollview/signs')
let s:available_signs = filter(s:available_signs, 'v:val =~# "\\.lua$"')
call map(s:available_signs, {_, val -> fnamemodify(val, ':r')})
" Internal list of sign groups that are enabled on startup by default.
let s:default_signs = ['all']

" *** General sign settings ***
" Sign column is relative to the scrollbar. It specifies the initial column
" for showing signs.
let g:scrollview_signs_column = get(g:, 'scrollview_signs_column', -1)
" Whether signs in folds should be shown or hidden.
let g:scrollview_signs_show_in_folds =
      \ get(g:, 'scrollview_signs_show_in_folds', 0)
" The maximum number of signs shown per row. Set to -1 to have no limit.
" Set to 0 to disable signs.
let g:scrollview_signs_max_per_row =
      \ get(g:, 'scrollview_signs_max_per_row', -1)
" Sign groups to enable on startup. If 'all' is included, it effectively
" expands to all builtin plugins. If 'defaults' is included, it effectively
" expands to builtin plugins that would ordinarily be enabled by default.
let g:scrollview_signs_on_startup =
      \ get(g:, 'scrollview_signs_on_startup', s:default_signs)
" Specifies the sign overflow direction ('left' or 'right').
let g:scrollview_signs_overflow = get(g:, 'scrollview_signs_overflow', 'left')
let g:scrollview_signs_zindex = get(g:, 'scrollview_signs_zindex', 45)

" *** Conflict signs ***
let g:scrollview_conflicts_top_priority =
      \ get(g:, 'scrollview_conflicts_top_priority', 70)
let g:scrollview_conflicts_top_symbol =
      \ get(g:, 'scrollview_conflicts_top_symbol', '<')
let g:scrollview_conflicts_middle_priority =
      \ get(g:, 'scrollview_conflicts_middle_priority', 70)
let g:scrollview_conflicts_middle_symbol =
      \ get(g:, 'scrollview_conflicts_middle_symbol', '=')
let g:scrollview_conflicts_bottom_priority =
      \ get(g:, 'scrollview_conflicts_bottom_priority', 70)
let g:scrollview_conflicts_bottom_symbol =
      \ get(g:, 'scrollview_conflicts_bottom_symbol', '>')

" *** Cursor signs ***
let g:scrollview_cursor_priority = get(g:, 'scrollview_cursor_priority', 100)
" Use a small square, resembling a block cursor, for the default symbol.
let g:scrollview_cursor_symbol =
      \ get(g:, 'scrollview_cursor_symbol', nr2char(0x25aa))

" *** Diagnostics signs ***
let g:scrollview_diagnostics_error_priority =
      \ get(g:, 'scrollview_diagnostics_error_priority', 60)
let g:scrollview_diagnostics_error_symbol =
      \ get(g:, 'scrollview_diagnostics_error_symbol', 'E')
let g:scrollview_diagnostics_hint_priority =
      \ get(g:, 'scrollview_diagnostics_hint_priority', 30)
let g:scrollview_diagnostics_hint_symbol =
      \ get(g:, 'scrollview_diagnostics_hint_symbol', 'H')
let g:scrollview_diagnostics_info_priority =
      \ get(g:, 'scrollview_diagnostics_info_priority', 40)
let g:scrollview_diagnostics_info_symbol =
      \ get(g:, 'scrollview_diagnostics_info_symbol', 'I')
let g:scrollview_diagnostics_warn_priority =
      \ get(g:, 'scrollview_diagnostics_warn_priority', 50)
let g:scrollview_diagnostics_warn_symbol =
      \ get(g:, 'scrollview_diagnostics_warn_symbol', 'W')

" *** Fold signs ***
let g:scrollview_folds_priority = get(g:, 'scrollview_folds_priority', 30)
" Default symbol: a right pointing triangle, similar to what's shown in the
" browser for a hidden <details>/<summary>.
let g:scrollview_folds_symbol =
      \ get(g:, 'scrollview_folds_symbol', nr2char(0x25b6))

" *** Location list signs ***
let g:scrollview_loclist_priority = get(g:, 'scrollview_loclist_priority', 45)
" Default symbol: a small circle
let g:scrollview_loclist_symbol =
      \ get(g:, 'scrollview_loclist_symbol', nr2char(0x2981))

" *** Mark signs ***
" Characters for which mark signs will be shown.
if !has_key(g:, 'scrollview_marks_characters')
  " Default to a-z ("lowercase marks, valid within one file") and A-Z
  " ("uppercase marks, also called file marks, valid between files").
  " Don't include numbered marks. These are set automatically ("They
  " are only present when using a shada file").
  let g:scrollview_marks_characters = []
  let s:codes = range(char2nr('a'), char2nr('z'))
  call extend(s:codes, range(char2nr('A'), char2nr('Z')))
  for s:code in s:codes
    call add(g:scrollview_marks_characters, nr2char(s:code))
  endfor
endif
let g:scrollview_marks_priority = get(g:, 'scrollview_marks_priority', 50)

" *** Quickfix signs ***
let g:scrollview_quickfix_priority = get(g:, 'scrollview_quickfix_priority', 45)
" Default symbol: a small circle
let g:scrollview_quickfix_symbol =
      \ get(g:, 'scrollview_quickfix_symbol', nr2char(0x2981))

" *** Search signs ***
let g:scrollview_search_priority = get(g:, 'scrollview_search_priority', 70)
" Default symbols: (1,2) equals, (>=3) triple bar
let g:scrollview_search_symbol =
      \ get(g:, 'scrollview_search_symbol', ['=', '=', nr2char(0x2261)])

" *** Spell signs ***
let g:scrollview_spell_priority = get(g:, 'scrollview_spell_priority', 20)
let g:scrollview_spell_symbol = get(g:, 'scrollview_spell_symbol', '~')

" *** Textwidth signs ***
let g:scrollview_textwidth_priority =
      \ get(g:, 'scrollview_textwidth_priority', 20)
" Default symbol: two adjacent small '>' symbols.
let g:scrollview_textwidth_symbol =
      \ get(g:, 'scrollview_textwidth_symbol', nr2char(0xbb))

" === Highlights ===

" The default highlight groups are specified below.
" Change the defaults by defining or linking an alternative highlight group.
" E.g., the following will use the Pmenu highlight.
"   :highlight link ScrollView Pmenu
" E.g., the following will use custom highlight colors.
"   :highlight ScrollView ctermbg=159 guibg=LightCyan
highlight default link ScrollView Visual
highlight default link ScrollViewConflictsTop DiffAdd
highlight default link ScrollViewConflictsMiddle DiffAdd
highlight default link ScrollViewConflictsBottom DiffAdd
highlight default link ScrollViewCursor Identifier
highlight default link ScrollViewDiagnosticsError WarningMsg
highlight default link ScrollViewDiagnosticsHint Question
highlight default link ScrollViewDiagnosticsInfo Identifier
highlight default link ScrollViewDiagnosticsWarn LineNr
highlight default link ScrollViewFolds Directory
highlight default link ScrollViewLocList LineNr
highlight default link ScrollViewMarks ColorColumn
highlight default link ScrollViewQuickFix Constant
highlight default link ScrollViewRestricted SpellLocal
highlight default link ScrollViewSearch NonText
highlight default link ScrollViewSpell Statement
highlight default link ScrollViewTextWidth Question

" *************************************************
" * Versioning
" *************************************************

" An integer to be incremented when the interface for using signs changes.
" For example, this would correspond to the register_sign_spec function
" interface and the format for saving sign information in buffers.
let g:scrollview_signs_version = 1

" *************************************************
" * Commands
" *************************************************

" Returns a list of groups for command completion. A 'custom' function is used
" instead of a 'customlist' function, for the automatic filtering that is
" conducted for the former, but not the latter.
" XXX: This currently returns the full list of groups, including entries that
" may not be relevant for the current command (for example, a disabled group
" would not be relevant for :ScrollViewFirst).
function! s:Complete(...) abort
  let l:groups = luaeval('require("scrollview").get_sign_groups()')
  call sort(l:groups)
  return join(l:groups, "\n")
endfunction

" CompleteWithAll is similar to Complete, but also includes 'all'.
function! s:CompleteWithAll(...) abort
  let l:groups = luaeval('require("scrollview").get_sign_groups()')
  call add(l:groups, 'all')
  call sort(l:groups)
  return join(l:groups, "\n")
endfunction

" A helper for :ScrollViewEnable, :ScrollViewDisable, and :ScrollViewToggle to
" call the underlying functions. Set state to v:true to enable, v:false to
" disable, and v:null to toggle. Additional arguments specify sign groups.
function! s:DispatchStateCommand(state, ...)
  let s:module = luaeval('require("scrollview")')
  if empty(a:000)
    " The command had no arguments, so is for the plugin.
    call s:module.set_state(a:state)
  else
    " The command had arguments, so is for signs.
    let l:groups = []
    for l:group in a:000
      if l:group ==# 'all'
        call extend(l:groups, luaeval('require("scrollview").get_sign_groups()'))
      else
        call add(l:groups, l:group)
      endif
    endfor
    for l:group in l:groups
      call s:module.set_sign_group_state(l:group, a:state)
    endfor
  endif
endfunction

if !exists(':ScrollViewDisable')
  command -bar -nargs=* -complete=custom,s:CompleteWithAll ScrollViewDisable
        \ call s:DispatchStateCommand(v:false, <f-args>)
endif

if !exists(':ScrollViewEnable')
  command -bar -nargs=* -complete=custom,s:CompleteWithAll ScrollViewEnable
        \ call s:DispatchStateCommand(v:true, <f-args>)
endif

if !exists(':ScrollViewFirst')
  command -bar -nargs=* -complete=custom,s:Complete ScrollViewFirst
        \ lua require('scrollview').first(
        \   #{<f-args>} > 0 and {<f-args>} or nil)
endif

if !exists(':ScrollViewLast')
  command -bar -nargs=* -complete=custom,s:Complete ScrollViewLast
        \ lua require('scrollview').last(
        \   #{<f-args>} > 0 and {<f-args>} or nil)
endif

if !exists(':ScrollViewNext')
  command -bar -nargs=* -complete=custom,s:Complete ScrollViewNext
        \ lua require('scrollview').next(
        \   #{<f-args>} > 0 and {<f-args>} or nil)
endif

if !exists(':ScrollViewPrev')
  command -bar -nargs=* -complete=custom,s:Complete ScrollViewPrev
        \ lua require('scrollview').prev(
        \   #{<f-args>} > 0 and {<f-args>} or nil)
endif

if !exists(':ScrollViewRefresh')
  command -bar ScrollViewRefresh lua require('scrollview').refresh()
endif

if !exists(':ScrollViewToggle')
  command -bar -nargs=* -complete=custom,s:CompleteWithAll ScrollViewToggle
        \ call s:DispatchStateCommand(v:null, <f-args>)
endif

" *************************************************
" * Mappings
" *************************************************

" <plug> mappings for mouse functionality.
" E.g., <plug>(ScrollViewLeftMouse)
let s:mouse_plug_pairs = [
      \   ['ScrollViewLeftMouse',   'left'  ],
      \   ['ScrollViewMiddleMouse', 'middle'],
      \   ['ScrollViewRightMouse',  'right' ],
      \   ['ScrollViewX1Mouse',     'x1'    ],
      \   ['ScrollViewX2Mouse',     'x2'    ],
      \ ]
for [s:plug_name, s:button] in s:mouse_plug_pairs
  let s:lhs = printf('<silent> <plug>(%s)', s:plug_name)
  let s:rhs = printf(
        \ '<cmd>lua require("scrollview").handle_mouse("%s")<cr>', s:button)
  execute 'noremap' s:lhs s:rhs
  execute 'inoremap' s:lhs s:rhs
endfor

if g:scrollview_auto_mouse
  " Create a <leftmouse> mapping only if one does not already exist.
  " For example, a mapping may already exist if the user uses swapped buttons
  " from $VIMRUNTIME/pack/dist/opt/swapmouse/plugin/swapmouse.vim. Handling
  " for that scenario would require modifications (e.g., possibly by updating
  " the non-initial feedkeys calls in scrollview#HandleMouse to remap keys).
  silent! nmap <unique> <silent> <leftmouse> <plug>(ScrollViewLeftMouse)
  silent! vmap <unique> <silent> <leftmouse> <plug>(ScrollViewLeftMouse)
  silent! imap <unique> <silent> <leftmouse> <plug>(ScrollViewLeftMouse)
endif

" Additional <plug> mappings are defined for convenience of creating
" user-defined mappings that call nvim-scrollview functionality. However,
" since the usage of <plug> mappings requires recursive map commands, this
" prevents mappings that both call <plug> functions and have the
" left-hand-side key sequences repeated not at the beginning of the
" right-hand-side (see :help recursive_mapping for details). Experimentation
" suggests <silent> is not necessary for <cmd> mappings, but it's added to
" make it explicit.
noremap  <silent> <plug>(ScrollViewDisable) <cmd>ScrollViewDisable<cr>
inoremap <silent> <plug>(ScrollViewDisable) <cmd>ScrollViewDisable<cr>
noremap  <silent> <plug>(ScrollViewEnable)  <cmd>ScrollViewEnable<cr>
inoremap <silent> <plug>(ScrollViewEnable)  <cmd>ScrollViewEnable<cr>
noremap  <silent> <plug>(ScrollViewFirst)   <cmd>ScrollViewFirst<cr>
inoremap <silent> <plug>(ScrollViewFirst)   <cmd>ScrollViewFirst<cr>
noremap  <silent> <plug>(ScrollViewLast)    <cmd>ScrollViewLast<cr>
inoremap <silent> <plug>(ScrollViewLast)    <cmd>ScrollViewLast<cr>
noremap  <silent> <plug>(ScrollViewNext)    <cmd>ScrollViewNext<cr>
inoremap <silent> <plug>(ScrollViewNext)    <cmd>ScrollViewNext<cr>
noremap  <silent> <plug>(ScrollViewPrev)    <cmd>ScrollViewPrev<cr>
inoremap <silent> <plug>(ScrollViewPrev)    <cmd>ScrollViewPrev<cr>
noremap  <silent> <plug>(ScrollViewRefresh) <cmd>ScrollViewRefresh<cr>
inoremap <silent> <plug>(ScrollViewRefresh) <cmd>ScrollViewRefresh<cr>
noremap  <silent> <plug>(ScrollViewToggle)  <cmd>ScrollViewToggle<cr>
inoremap <silent> <plug>(ScrollViewToggle)  <cmd>ScrollViewToggle<cr>

" Creates a mapping where the left-hand-side key sequence is repeated on the
" right-hand-side, followed by a scrollview refresh. 'modes' is a string with
" each character specifying a mode (e.g., 'nvi' for normal, visual, and insert
" modes). 'seq' is the key sequence that will be remapped. Existing mappings
" are not clobbered.
function s:CreateRefreshMapping(modes, seq) abort
  for l:idx in range(strchars(a:modes))
    let l:mode = strcharpart(a:modes, l:idx, 1)
    " A <plug> mapping is avoided since it doesn't work properly in
    " terminal-job mode.
    execute printf(
          \ 'silent! %snoremap <unique> %s %s<cmd>ScrollViewRefresh<cr>',
          \ l:mode, a:seq, a:seq)
  endfor
endfunction

" An 'operatorfunc' for g@ that executes zf and then refreshes scrollbars.
function! s:ZfOperator(type) abort
  " Handling for 'char' is needed since e.g., using linewise mark jumping
  " results in the cursor moving to the beginning of the line for zfl, which
  " should not move the cursor. Separate handling for 'line' is needed since
  " e.g., with 'char' handling, zfG won't include the last line in the fold if
  " the cursor gets positioned on the first character.
  if a:type ==# 'char'
    silent normal! `[zf`]
  elseif a:type ==# 'line'
    silent normal! '[zf']
  else
    " Unsupported
  endif
  ScrollViewRefresh
endfunction

if g:scrollview_auto_workarounds
  " === Window arrangement synchronization workarounds ===
  let s:win_seqs = [
        \   '<c-w>H', '<c-w>J', '<c-w>K', '<c-w>L',
        \   '<c-w>r', '<c-w><c-r>', '<c-w>R'
        \ ]
  for s:seq in s:win_seqs
    call s:CreateRefreshMapping('nv', s:seq)
  endfor
  " === Mouse wheel scrolling synchronization workarounds ===
  let s:wheel_seqs = ['<scrollwheelup>', '<scrollwheeldown>']
  for s:seq in s:wheel_seqs
    call s:CreateRefreshMapping('nvit', s:seq)
  endfor
  " === Fold command synchronization workarounds ===
  " zf takes a motion in normal mode, so it requires a g@ mapping.
  silent! nnoremap <unique> zf <cmd>set operatorfunc=<sid>ZfOperator<cr>g@
  call s:CreateRefreshMapping('x', 'zf')
  let s:fold_seqs = [
        \   'zF', 'zd', 'zD', 'zE', 'zo', 'zO', 'zc', 'zC', 'za', 'zA', 'zv',
        \   'zx', 'zX', 'zm', 'zM', 'zr', 'zR', 'zn', 'zN', 'zi'
        \ ]
  for s:seq in s:fold_seqs
    call s:CreateRefreshMapping('nx', s:seq)
  endfor
  " === <c-w>c for the tab last window workaround ===
  " A workaround is intentionally not currently applied. It would need careful
  " handling to 1) ensure that if scrollview had been disabled, it doesn't get
  " re-enabled, and 2) avoid flickering (possibly by only disabling/enabling
  " when there is a single ordinary window in the tab, as the workaround would
  " not be needed otherwise).
endif

" *************************************************
" * Sign Initialization
" *************************************************

function! s:InitializeSigns() abort
  let s:lookup = {}  " maps sign groups to state (enabled/disabled)
  for s:group in s:available_signs
    let s:lookup[s:group] = v:false
  endfor
  for s:group in g:scrollview_signs_on_startup
    if s:group ==# 'all'
      for s:group2 in s:available_signs
        let s:lookup[s:group2] = v:true
      endfor
      break
    elseif s:group ==# 'defaults'
      for s:group2 in s:default_signs
        let s:lookup[s:group2] = v:true
      endfor
    else
      let s:lookup[s:group] = v:true
    endif
  endfor
  for s:group in s:available_signs
    let s:module = luaeval('require("scrollview.signs.' .. s:group .. '")')
    call s:module.init(s:lookup[s:group])
  endfor
endfunction

call timer_start(0, {-> execute('call s:InitializeSigns()', '')})

" *************************************************
" * Core
" *************************************************

if g:scrollview_on_startup
  " Enable scrollview asynchronously. This avoids an issue that prevents diff
  " mode from functioning properly when it's launched at startup (i.e., with
  " nvim -d). The issue is reported in Neovim Issue #13720.
  lua vim.defer_fn(function() require('scrollview').set_state(true) end, 0)
endif

" *************************************************
" * Postamble
" *************************************************

let &cpo = s:save_cpo
unlet s:save_cpo
