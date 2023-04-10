" Test the consistency of linewise and simple computations. These should only
" match without folds.

" Load a file with many lines.
help eval.txt

let s:lua_module = luaeval('require("scrollview")')

let s:line_count = nvim_buf_line_count(0)

let s:vtopline_lookup_simple =
      \ s:lua_module.simple_topline_lookup(win_getid(winnr()))
let s:vtopline_lookup_linewise =
      \ s:lua_module.virtual_topline_lookup_linewise()
call assert_equal(s:vtopline_lookup_simple, s:vtopline_lookup_linewise)

" Create folds.
set foldmethod=indent
normal! zM

let s:vtopline_lookup_simple =
      \ s:lua_module.simple_topline_lookup(win_getid(winnr()))
call assert_equal(s:vtopline_lookup_simple, s:vtopline_lookup_linewise)
let s:vtopline_lookup_linewise =
      \ s:lua_module.virtual_topline_lookup_linewise()
call assert_notequal(s:vtopline_lookup_simple, s:vtopline_lookup_linewise)
