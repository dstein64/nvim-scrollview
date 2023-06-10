" The additional check for ##WinScrolled may be redundant, but was added in
" case early versions of nvim 0.5 didn't have that event.
if !has('nvim-0.5') || !exists('##WinScrolled')
  " Logging error with echomsg or echoerr interrupts Neovim's startup by
  " blocking. Fail silently.
  finish
endif

" Initialize scrollview asynchronously. Asynchronous initialization is used to
" prevent issues when setting configuration variables is deferred (#99). This
" was originally used to avoid an issue that prevents diff mode from
" functioning properly when it's launched at startup (i.e., with nvim
" -d). The issue was reported on Jan 8, 2021, in Neovim Issue #13720. As of
"  Neovim 0.9.0, the issue is resolved (Neovim PR #21829, Jan 16, 2023).
" WARN: scrollview events are omitted from the output of --startuptime.
call timer_start(0, {-> execute('call scrollview#Initialize()', '')})
