" *************************************************
" * Utils
" *************************************************

" Converts 1 and 0 to v:true and v:false.
function! s:ToBool(x) abort
  if a:x
    return v:true
  else
    return v:false
  endif
endfunction

" *************************************************
" * User Configuration
" *************************************************

" === General ===

let g:scrollview_always_show = get(g:, 'scrollview_always_show', v:false)
let g:scrollview_auto_mouse = get(g:, 'scrollview_auto_mouse', v:true)
let g:scrollview_base = get(g:, 'scrollview_base', 'right')
" The plugin enters a restricted state when the number of buffer bytes exceeds
" the limit. Use -1 for no limit.
let g:scrollview_byte_limit = get(g:, 'scrollview_byte_limit', 1000000)
let g:scrollview_character = get(g:, 'scrollview_character', '')
let g:scrollview_column = get(g:, 'scrollview_column', 1)
let g:scrollview_current_only = get(g:, 'scrollview_current_only', v:false)
let g:scrollview_excluded_filetypes =
      \ get(g:, 'scrollview_excluded_filetypes', [])
let g:scrollview_floating_windows =
      \ get(g:, 'scrollview_floating_windows', v:false)
let g:scrollview_hide_on_intersect =
      \ get(g:, 'scrollview_hide_on_intersect', v:false)
let g:scrollview_hover = get(g:, 'scrollview_hover', v:true)
let g:scrollview_include_end_region =
      \ get(g:, 'scrollview_include_end_region', v:false)
" The plugin enters a restricted state when the number of buffer lines exceeds
" the limit. Use -1 for no limit.
let g:scrollview_line_limit = get(g:, 'scrollview_line_limit', 20000)
let g:scrollview_mode = get(g:, 'scrollview_mode', 'auto')
let g:scrollview_on_startup = get(g:, 'scrollview_on_startup', v:true)
let g:scrollview_winblend = get(g:, 'scrollview_winblend', 50)
let g:scrollview_winblend_gui = get(g:, 'scrollview_winblend_gui', 0)
" The default zindex for floating windows is 50. A smaller value is used here
" by default so that scrollbars don't cover floating windows.
let g:scrollview_zindex = get(g:, 'scrollview_zindex', 40)

" === Signs ===

" Internal list of all builtin sign groups, populated automatically.
let s:available_signs = readdir(expand('<sfile>:p:h') .. '/../lua/scrollview/signs')
let s:available_signs = filter(s:available_signs, 'v:val =~# "\\.lua$"')
call map(s:available_signs, {_, val -> fnamemodify(val, ':r')})
" Internal list of sign groups that are enabled on startup by default.
let s:default_signs = ['diagnostics', 'search']
" Enable mark signs by default, but only with nvim>=0.10, since :delmarks
" doesn't persist on earlier versions (Neovim #4288, #4925, #24963).
if has('nvim-0.10')
  call add(s:default_signs, 'marks')
endif

" *** General sign settings ***
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
" Whether signs in folds should be shown or hidden.
let g:scrollview_signs_show_in_folds =
      \ get(g:, 'scrollview_signs_show_in_folds', v:false)

" *** Conflict signs ***
let g:scrollview_conflicts_bottom_priority =
      \ get(g:, 'scrollview_conflicts_bottom_priority', 80)
let g:scrollview_conflicts_bottom_symbol =
      \ get(g:, 'scrollview_conflicts_bottom_symbol', '>')
let g:scrollview_conflicts_middle_priority =
      \ get(g:, 'scrollview_conflicts_middle_priority', 75)
let g:scrollview_conflicts_middle_symbol =
      \ get(g:, 'scrollview_conflicts_middle_symbol', '=')
let g:scrollview_conflicts_top_priority =
      \ get(g:, 'scrollview_conflicts_top_priority', 70)
let g:scrollview_conflicts_top_symbol =
      \ get(g:, 'scrollview_conflicts_top_symbol', '<')

" *** Cursor signs ***
let g:scrollview_cursor_priority = get(g:, 'scrollview_cursor_priority', 0)
" Use a small square, resembling a block cursor, for the default symbol.
let g:scrollview_cursor_symbol =
      \ get(g:, 'scrollview_cursor_symbol', nr2char(0x25aa))

" *** Diagnostics signs ***
let g:scrollview_diagnostics_error_priority =
      \ get(g:, 'scrollview_diagnostics_error_priority', 60)
let g:scrollview_diagnostics_hint_priority =
      \ get(g:, 'scrollview_diagnostics_hint_priority', 30)
let g:scrollview_diagnostics_info_priority =
      \ get(g:, 'scrollview_diagnostics_info_priority', 40)
if !has_key(g:, 'scrollview_diagnostics_severities')
  let g:scrollview_diagnostics_severities = [
        \   luaeval('vim.diagnostic.severity.ERROR'),
        \   luaeval('vim.diagnostic.severity.HINT'),
        \   luaeval('vim.diagnostic.severity.INFO'),
        \   luaeval('vim.diagnostic.severity.WARN'),
        \ ]
endif
let g:scrollview_diagnostics_warn_priority =
      \ get(g:, 'scrollview_diagnostics_warn_priority', 50)
" Set the diagnostic symbol to the corresponding Neovim sign text if defined,
" or the default otherwise.
let s:diagnostics_symbol_data = [
      \   [
      \     'scrollview_diagnostics_error_symbol',
      \     'E',
      \     'DiagnosticSignError',
      \     luaeval('vim.diagnostic.severity.ERROR'),
      \     'ERROR',
      \   ],
      \   [
      \     'scrollview_diagnostics_hint_symbol',
      \     'H',
      \     'DiagnosticSignHint',
      \     luaeval('vim.diagnostic.severity.HINT'),
      \     'HINT',
      \   ],
      \   [
      \     'scrollview_diagnostics_info_symbol',
      \     'I',
      \     'DiagnosticSignInfo',
      \     luaeval('vim.diagnostic.severity.INFO'),
      \     'INFO',
      \   ],
      \   [
      \     'scrollview_diagnostics_warn_symbol',
      \     'W',
      \     'DiagnosticSignWarn',
      \     luaeval('vim.diagnostic.severity.WARN'),
      \     'WARN',
      \   ],
      \ ]
for [s:key, s:fallback, s:sign, s:severity, s:name] in s:diagnostics_symbol_data
  if !has_key(g:, s:key)
    try
      if has('nvim-0.10')
        " The key for configuring text can be a severity code (e.g.,
        " vim.diagnostic.severity.ERROR) or a severity name (e.g., 'ERROR').
        " Code and name keys can both be used in the same table, so we can't
        " use luaeval() directly on the table ("E5100: Cannot convert given
        " lua table: table should either have a sequence of positive integer
        " keys or contain only string key"). When the same type of diagnostic
        " has both a code and name key, the code key takes precedence.
        " https://github.com/neovim/neovim/pull/26193#issue-2009346914
        let g:[s:key] = luaeval(
              \ printf('vim.diagnostic.config().signs.text[%d]', s:severity))
        if g:[s:key] is# v:null
          let g:[s:key] = luaeval(
                \ printf('vim.diagnostic.config().signs.text["%s"]', s:name))
        endif
        if g:[s:key] is# v:null
          let g:[s:key] = s:fallback
        endif
      else
        let g:[s:key] = trim(sign_getdefined(s:sign)[0].text)
      endif
    catch
      let g:[s:key] = s:fallback
    endtry
  endif
endfor

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
      \ get(g:, 'scrollview_loclist_symbol', nr2char(0x2022))

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
      \ get(g:, 'scrollview_quickfix_symbol', nr2char(0x2022))

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

" *** Trail signs ***
let g:scrollview_trail_priority = get(g:, 'scrollview_trail_priority', 50)
" Default symbol: an outlined square
let g:scrollview_trail_symbol =
      \ get(g:, 'scrollview_trail_symbol', nr2char(0x25a1))

" *************************************************
" * Global State
" *************************************************

" External global state is specified here.
" Internal global state is primarily represented with local variables in
" lua/scrollview.lua, but specified here when more convenient.

" A flag that gets set to true while scrollbars are being refreshed. #88
let g:scrollview_refreshing = v:false

" Tracks buffer line count in insert mode, so scrollbars can be refreshed when
" the line count changes.
let g:scrollview_ins_mode_buf_lines = 0

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
function! s:DispatchStateCommand(state, ...) abort
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
  command -count=1 -bar -nargs=* -complete=custom,s:Complete ScrollViewNext
        \ lua require('scrollview').next(
        \   #{<f-args>} > 0 and {<f-args>} or nil, <count>)
endif

if !exists(':ScrollViewPrev')
  command -count=1 -bar -nargs=* -complete=custom,s:Complete ScrollViewPrev
        \ lua require('scrollview').prev(
        \   #{<f-args>} > 0 and {<f-args>} or nil, <count>)
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

" *************************************************
" * Sign Group Initialization
" *************************************************

" === Initialize built-in sign groups (for nvim>=0.9) ===

if has('nvim-0.9')
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
endif

" *************************************************
" * Enable/Disable scrollview
" *************************************************

" Enable nvim-scrollview if scrollview_on_startup is true.
if g:scrollview_on_startup
  lua require('scrollview').set_state(true)
endif

" *************************************************
" * Initialization
" *************************************************

function! scrollview#Initialize() abort
  " The first call to this function will result in executing this file's code.
endfunction
