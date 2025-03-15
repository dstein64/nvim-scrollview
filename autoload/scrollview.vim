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
let g:scrollview_consider_border =
      \ get(g:, 'scrollview_consider_border', v:false)
let g:scrollview_current_only = get(g:, 'scrollview_current_only', v:false)
let g:scrollview_excluded_filetypes =
      \ get(g:, 'scrollview_excluded_filetypes', [])
let g:scrollview_floating_windows =
      \ get(g:, 'scrollview_floating_windows', v:false)
let g:scrollview_signs_hidden_for_insert =
      \ get(g:, 'scrollview_signs_hidden_for_insert', [])
let g:scrollview_hide_bar_for_insert =
      \ get(g:, 'scrollview_hide_bar_for_insert', v:false)
let g:scrollview_hide_on_cursor_intersect =
      \ get(g:, 'scrollview_hide_on_cursor_intersect', v:false)
" Use the old option, scrollview_hide_on_intersect, if it's set.
if has_key(g:, 'scrollview_hide_on_intersect')
  let g:scrollview_hide_on_float_intersect = g:scrollview_hide_on_intersect
endif
let g:scrollview_hide_on_float_intersect =
      \ get(g:, 'scrollview_hide_on_float_intersect', v:false)
let g:scrollview_hide_on_text_intersect =
      \ get(g:, 'scrollview_hide_on_text_intersect', v:false)
let g:scrollview_hover = get(g:, 'scrollview_hover', v:true)
let g:scrollview_include_end_region =
      \ get(g:, 'scrollview_include_end_region', v:false)
" The plugin enters a restricted state when the number of buffer lines exceeds
" the limit. Use -1 for no limit.
let g:scrollview_line_limit = get(g:, 'scrollview_line_limit', 20000)
let g:scrollview_mode = get(g:, 'scrollview_mode', 'auto')
" If the old option, scrollview_auto_mouse, is set to false, disable the mouse
" functionality.
if !get(g:, 'scrollview_auto_mouse', v:true)
  if !has_key(g:, 'scrollview_mouse_primary')
    let g:scrollview_mouse_primary = v:null
  endif
  if !has_key(g:, 'scrollview_mouse_secondary')
    let g:scrollview_mouse_secondary = v:null
  endif
endif
let g:scrollview_mouse_primary = get(g:, 'scrollview_mouse_primary', 'left')
let g:scrollview_mouse_secondary =
      \ get(g:, 'scrollview_mouse_secondary', 'right')
let g:scrollview_on_startup = get(g:, 'scrollview_on_startup', v:true)
let g:scrollview_winblend = get(g:, 'scrollview_winblend', 50)
let g:scrollview_winblend_gui = get(g:, 'scrollview_winblend_gui', 0)
" The default zindex for floating windows is 50. A smaller value is used here
" by default so that scrollbars don't cover floating windows.
let g:scrollview_zindex = get(g:, 'scrollview_zindex', 40)

" === Signs ===

" Internal list of all built-in sign groups, populated automatically.
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
" expands to all built-in plugins. If 'defaults' is included, it effectively
" expands to built-in plugins that would ordinarily be enabled by default.
let g:scrollview_signs_on_startup =
      \ get(g:, 'scrollview_signs_on_startup', s:default_signs)
" Specifies the sign overflow direction ('left' or 'right').
let g:scrollview_signs_overflow = get(g:, 'scrollview_signs_overflow', 'left')
" Whether signs in folds should be shown or hidden.
let g:scrollview_signs_show_in_folds =
      \ get(g:, 'scrollview_signs_show_in_folds', v:false)

" *** Change list signs ***
let g:scrollview_changelist_previous_priority =
      \ get(g:, 'scrollview_changelist_previous_priority', 15)
let g:scrollview_changelist_previous_symbol =
      \ get(g:, 'scrollview_changelist_previous_symbol', nr2char(0x21b0))
let g:scrollview_changelist_current_priority =
      \ get(g:, 'scrollview_changelist_current_priority', 10)
let g:scrollview_changelist_current_symbol =
      \ get(g:, 'scrollview_changelist_current_symbol', '@')
let g:scrollview_changelist_next_priority =
      \ get(g:, 'scrollview_changelist_next_priority', 5)
let g:scrollview_changelist_next_symbol =
      \ get(g:, 'scrollview_changelist_next_symbol', nr2char(0x21b3))

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
        " WARN: Neovim diagnostic signs can be configured with a function
        " (that takes namespace and bufnr). That's not supported here.
        " The value can also be a boolean.
        if luaeval('type(vim.diagnostic.config().signs)') ==# 'table'
              \ && luaeval('vim.diagnostic.config().signs.text') isnot# v:null
          let g:[s:key] =
                \ luaeval('vim.diagnostic.config().signs.text[_A]', s:severity)
          if g:[s:key] is# v:null
            let g:[s:key] =
                  \ luaeval('vim.diagnostic.config().signs.text[_A]', s:name)
          endif
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

" *** Indent signs ***
let g:scrollview_indent_spaces_condition =
      \ get(g:, 'scrollview_indent_spaces_condition', 'noexpandtab')
let g:scrollview_indent_spaces_priority =
      \ get(g:, 'scrollview_indent_spaces_priority', 25)
let g:scrollview_indent_spaces_symbol =
      \ get(g:, 'scrollview_indent_spaces_symbol', '-')
let g:scrollview_indent_tabs_condition =
      \ get(g:, 'scrollview_indent_tabs_condition', 'expandtab')
let g:scrollview_indent_tabs_priority =
      \ get(g:, 'scrollview_indent_tabs_priority', 25)
let g:scrollview_indent_tabs_symbol =
      \ get(g:, 'scrollview_indent_tabs_symbol', '>')

" *** Keyword signs ***
let g:scrollview_keywords_fix_priority =
      \ get(g:, 'scrollview_keywords_fix_priority', 20)
let g:scrollview_keywords_fix_symbol =
      \ get(g:, 'scrollview_keywords_fix_symbol', 'F')
let g:scrollview_keywords_hack_priority =
      \ get(g:, 'scrollview_keywords_hack_priority', 20)
let g:scrollview_keywords_hack_symbol =
      \ get(g:, 'scrollview_keywords_hack_symbol', 'H')
let g:scrollview_keywords_todo_priority =
      \ get(g:, 'scrollview_keywords_todo_priority', 20)
let g:scrollview_keywords_todo_symbol =
      \ get(g:, 'scrollview_keywords_todo_symbol', 'T')
let g:scrollview_keywords_warn_priority =
      \ get(g:, 'scrollview_keywords_warn_priority', 20)
let g:scrollview_keywords_warn_symbol =
      \ get(g:, 'scrollview_keywords_warn_symbol', 'W')
let g:scrollview_keywords_xxx_priority =
      \ get(g:, 'scrollview_keywords_xxx_priority', 20)
let g:scrollview_keywords_xxx_symbol =
      \ get(g:, 'scrollview_keywords_xxx_symbol', 'X')

let s:scrollview_keywords_fix_patterns =
      \ ['%f[%w_]FIX%f[^%w_]', '%f[%w_]FIXME%f[^%w_]']
let s:scrollview_keywords_hack_patterns = ['%f[%w_]HACK%f[^%w_]']
let s:scrollview_keywords_todo_patterns = ['%f[%w_]TODO%f[^%w_]']
let s:scrollview_keywords_warn_patterns =
      \ ['%f[%w_]WARN%f[^%w_]', '%f[%w_]WARNING%f[^%w_]']
let s:scrollview_keywords_xxx_patterns = ['%f[%w_]XXX%f[^%w_]']

let s:default_built_ins = ['fix', 'hack', 'todo', 'warn', 'xxx']
let g:scrollview_keywords_built_ins =
      \ get(g:, 'scrollview_keywords_built_ins', s:default_built_ins)

for s:built_in in g:scrollview_keywords_built_ins
  let s:capitalized= substitute(s:built_in, '\v^.', '\u&', '')
  let s:spec = {
        \   'highlight': 'ScrollViewKeywords' .. s:capitalized,
        \   'patterns': s:['scrollview_keywords_' .. s:built_in .. '_patterns'],
        \   'priority': g:['scrollview_keywords_' .. s:built_in .. '_priority'],
        \   'symbol': g:['scrollview_keywords_' .. s:built_in .. '_symbol'],
        \ }
  let s:key = 'scrollview_keywords_' .. s:built_in .. '_spec'
  let g:[s:key] = get(g:, s:key, s:spec)
endfor

" *** Latest change signs ***
let g:scrollview_latestchange_priority =
      \ get(g:, 'scrollview_latestchange_priority', 10)
" Default symbol: the Greek uppercase letter delta, which denotes change.
let g:scrollview_latestchange_symbol =
      \ get(g:, 'scrollview_latestchange_symbol', nr2char(0x0394))

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

let g:scrollview_enabled = v:false

" A flag that gets set to true while scrollbars are being refreshed. #88
let g:scrollview_refreshing = v:false

" Tracks buffer line count in insert mode, so scrollbars can be refreshed when
" the line count changes.
let g:scrollview_ins_mode_buf_lines = 0

" A string for the echo() function, to avoid having to handle character
" escaping.
let g:scrollview_echo_string = v:null

" Keep track of the initial mouse settings. These are only used for nvim<0.11.
let g:scrollview_init_mouse_primary = g:scrollview_mouse_primary
let g:scrollview_init_mouse_secondary = g:scrollview_mouse_secondary

" Stores the sign group that should be disabled (from right-clicking a sign,
" clicking the group name, then selecting 'disable').
let g:scrollview_disable_sign_group = v:null

" *************************************************
" * Versioning
" *************************************************

" An integer to be incremented when the interface for using signs changes.
" For example, this would correspond to the register_sign_spec function
" interface and the format for saving sign information in buffers.
let g:scrollview_signs_version = 2

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

if !exists(':ScrollViewLegend')
  command -bang -bar -nargs=* -complete=custom,s:Complete ScrollViewLegend
        \ lua require('scrollview').legend(
        \   #{<f-args>} > 0 and {<f-args>} or nil, '<bang>' == '!')
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

function! scrollview#HandleMouseFromMapping(button, is_primary) abort
  let l:button_repr = nvim_replace_termcodes(
        \ printf('<%smouse>', a:button), v:true, v:true, v:true)
  let l:packed = luaeval(
        \ '{require("scrollview").should_handle_mouse(_A)}', l:button_repr)
  let l:should_handle = l:packed[0]
  if l:should_handle
    let l:data = l:packed[1]
    call luaeval(
          \ 'require("scrollview").handle_mouse('
          \ .. '_A.button, _A.is_primary, _A.props, _A.mousepos)', l:data)
  else
    " Process the click as it would ordinarily be processed.
    call feedkeys(l:button_repr, 'ni')
  endif
endfunction

function! s:SetUpMouseMappings(button, primary) abort
  if a:button isnot# v:null
    " Create a mouse mapping only if mappings don't already exist and "!" is
    " not used at the end of the button. For example, a mapping may already
    " exist if the user uses swapped buttons from $VIMRUNTIME/pack/dist/opt
    " /swapmouse/plugin/swapmouse.vim. Handling for that scenario would
    " require modifications (e.g., possibly by updating the non-initial
    " feedkeys calls in handle_mouse() to remap keys).
    let l:force = v:false
    let l:button = a:button
    if strcharpart(l:button, strchars(l:button, 1) - 1, 1) ==# '!'
      let l:force = v:true
      let l:button =
            \ strcharpart(l:button, 0, strchars(l:button, 1) - 1)
    endif
    for l:mapmode in ['n', 'v', 'i']
      execute printf(
            \   'silent! %snoremap %s <silent> <%smouse>'
            \   .. ' <cmd>call scrollview#HandleMouseFromMapping("%s", %s)<cr>',
            \   l:mapmode,
            \   l:force ? '' : '<unique>',
            \   l:button,
            \   l:button,
            \   a:primary,
            \ )
    endfor
  endif
endfunction

" With Neovim 0.11, mouse functionality is handled with vim.on_key, not
" mappings.
if !has('nvim-0.11')
  call s:SetUpMouseMappings(g:scrollview_mouse_primary, v:true)
  " :popup doesn't work for nvim<0.8.
  if has('nvim-0.8')
    call s:SetUpMouseMappings(g:scrollview_mouse_secondary, v:false)
  endif
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
noremap  <silent> <plug>(ScrollViewLegend)  <cmd>ScrollViewLegend<cr>
inoremap <silent> <plug>(ScrollViewLegend)  <cmd>ScrollViewLegend<cr>
noremap  <silent> <plug>(ScrollViewLegend!) <cmd>ScrollViewLegend!<cr>
inoremap <silent> <plug>(ScrollViewLegend!) <cmd>ScrollViewLegend!<cr>
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
