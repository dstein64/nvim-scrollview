" The plugin should not be reloaded. #110
if get(g:, 'loaded_scrollview', v:false)
  finish
endif
let g:loaded_scrollview = v:true

if !has('nvim-0.6')
  " Logging error with echomsg or echoerr interrupts Neovim's startup by
  " blocking. Fail silently.
  finish
endif

" === Highlights ===

" Highlights are specified here instead of in autoload/scrollview.vim. Since
" that file is loaded asynchronously, calling ':highlight ...' would clear the
" intro screen. #102

" The default highlight groups are specified below.
" Change the defaults by defining or linking an alternative highlight group.
" E.g., the following will use the Pmenu highlight.
"   :highlight link ScrollView Pmenu
" E.g., the following will use custom highlight colors.
"   :highlight ScrollView ctermbg=159 guibg=LightCyan
highlight default link ScrollView Visual
highlight default link ScrollViewChangeListPrevious SpecialKey
highlight default link ScrollViewChangeListCurrent SpecialKey
highlight default link ScrollViewChangeListNext SpecialKey
highlight default link ScrollViewConflictsMiddle DiffAdd
highlight default link ScrollViewConflictsTop DiffAdd
highlight default link ScrollViewConflictsMiddle DiffAdd
highlight default link ScrollViewConflictsBottom DiffAdd
highlight default link ScrollViewCursor WarningMsg
" Set the diagnostic highlights to the corresponding Neovim sign text
" highlight if defined, or the default otherwise.
let s:diagnostics_highlight_data = [
  \   ['ScrollViewDiagnosticsError', 'DiagnosticError', 'DiagnosticSignError'],
  \   ['ScrollViewDiagnosticsHint', 'DiagnosticHint', 'DiagnosticSignHint'],
  \   ['ScrollViewDiagnosticsInfo', 'DiagnosticInfo', 'DiagnosticSignInfo'],
  \   ['ScrollViewDiagnosticsWarn', 'DiagnosticWarn', 'DiagnosticSignWarn'],
  \ ]
for [s:key, s:fallback, s:sign] in s:diagnostics_highlight_data
  if has('nvim-0.10')
    let s:highlight = s:sign
  else
    try
      let s:highlight = sign_getdefined(s:sign)[0].texthl
    catch
      let s:highlight = s:fallback
    endtry
  endif
  execute 'highlight default link ' .. s:key .. ' ' .. s:highlight
endfor
highlight default link ScrollViewFolds Directory
if has('nvim-0.9.2')
  highlight default link ScrollViewHover CurSearch
else
  highlight default link ScrollViewHover WildMenu
endif
highlight default link ScrollViewIndentSpaces LineNr
highlight default link ScrollViewIndentTabs LineNr
highlight default link ScrollViewKeywordsFix ColorColumn
highlight default link ScrollViewKeywordsHack ColorColumn
highlight default link ScrollViewKeywordsTodo ColorColumn
highlight default link ScrollViewKeywordsWarn ColorColumn
highlight default link ScrollViewKeywordsXxx ColorColumn
highlight default link ScrollViewLatestChange SpecialKey
highlight default link ScrollViewLocList LineNr
highlight default link ScrollViewMarks Identifier
highlight default link ScrollViewQuickFix Constant
if has('nvim-0.9.2')
  highlight default link ScrollViewRestricted CurSearch
else
  highlight default link ScrollViewRestricted MatchParen
endif
highlight default link ScrollViewSearch NonText
highlight default link ScrollViewSpell Statement
highlight default link ScrollViewTextWidth Question

" === Initialization ===

" Initialize scrollview asynchronously. Asynchronous initialization is used to
" prevent issues when setting configuration variables is deferred (#99). This
" was originally used to avoid an issue that prevents diff mode from
" functioning properly when it's launched at startup (i.e., with nvim
" -d). The issue was reported on Jan 8, 2021, in Neovim Issue #13720. As of
"  Neovim 0.9.0, the issue is resolved (Neovim PR #21829, Jan 16, 2023).
" WARN: scrollview events are omitted from the output of --startuptime.
call timer_start(0, {-> execute('call scrollview#Initialize()', '')})
