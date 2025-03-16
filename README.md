[![build][badge_thumbnail]][badge_link]

# nvim-scrollview

`nvim-scrollview` is a Neovim plugin that displays interactive vertical
scrollbars and signs. The plugin is customizable (see `:help
scrollview-configuration`).

<img src="https://github.com/dstein64/media/blob/main/nvim-scrollview/screenshot.svg?raw=true" width="600" />

<sub>(a scrollbar and signs can be seen near the right edge of the preceding image)</sub>

## Features

* Handling for folds
* Signs (e.g., `diagnostics` and `search` enabled by default, and `marks` too
  for `nvim>=0.10`)
* Scrollbars can be dragged with the mouse, and signs can be clicked for
  navigation or right-clicked for information

## Requirements

* `nvim>=0.6`
* Mouse functionality requires mouse support (see `:help 'mouse'`)
* Signs require `nvim>=0.9`

## Installation

A package manager can be used to install `nvim-scrollview`.
<details><summary>Examples</summary><br>

* [Vim8 packages][vim8pack]:
  - `git clone https://github.com/dstein64/nvim-scrollview ~/.local/share/nvim/site/pack/plugins/start/nvim-scrollview`
* [Vundle][vundle]:
  - Add `Plugin 'dstein64/nvim-scrollview'` to `~/.config/nvim/init.vim`
  - `:PluginInstall` or `$ nvim +PluginInstall +qall`
* [Pathogen][pathogen]:
  - `git clone --depth=1 https://github.com/dstein64/nvim-scrollview ~/.local/share/nvim/site/bundle/nvim-scrollview`
* [vim-plug][vimplug]:
  - Add `Plug 'dstein64/nvim-scrollview', { 'branch': 'main' }` to `~/.config/nvim/init.vim`
  - `:PlugInstall` or `$ nvim +PlugInstall +qall`
* [dein.vim][dein]:
  - Add `call dein#add('dstein64/nvim-scrollview')` to `~/.config/nvim/init.vim`
  - `:call dein#install()`
* [NeoBundle][neobundle]:
  - Add `NeoBundle 'dstein64/nvim-scrollview'` to `~/.config/nvim/init.vim`
  - Re-open Neovim or execute `:source ~/.config/nvim/init.vim`
* [packer.nvim][packer]:
  - Add `use 'dstein64/nvim-scrollview'` to the packer startup function
  - `:PackerInstall`

</details>

## Usage

* `nvim-scrollview` works automatically, displaying interactive scrollbars.
* `:ScrollViewDisable` disables the plugin. When arguments are given,
  the specified sign groups are disabled.
* `:ScrollViewEnable` enables the plugin. This is only necessary if
  nvim-scrollview has previously been disabled. When arguments are given,
  the specified sign groups are enabled.
* `:ScrollViewToggle` toggles the plugin. When arguments are given, the
  specified sign groups are toggled.
* `:ScrollViewRefresh` refreshes the scrollbars and signs. This is relevant
  when the scrollbars or signs are out-of-sync, which can occur as a result of
  some window arrangement actions.
* `:ScrollViewNext`, `:ScrollViewPrev`, `:ScrollViewFirst`, and
  `:ScrollViewLast` move the cursor to lines with signs. Arguments can specify
  which sign groups are considered.
* `:ScrollViewLegend` shows a legend for the plugin. This can be helpful if
  you're unsure what a sign represents. With the `!` variant of the command,
  the legend will include the scrollbar and all registered signs (even those
  from disabled groups), regardless of their display status.
* The scrollbars are draggable with a mouse. Signs can be clicked for
  navigation or right-clicked for information. If `mousemoveevent` is set,
  scrollbars and signs are highlighted when the mouse pointer hovers.

## Signs

There is built-in support for various types of signs (referred to as "sign
groups"), listed below. The functionality is similar to the sign column, but
with the same positioning logic as the scrollbar.

* `changelist`: change list items (previous, current, and next)
* `conflicts`: git merge conflicts
* `cursor`: cursor position
* `diagnostics`: errors, warnings, info, and hints
* `folds`: closed folds
* `indent`: unexpected indentation characters (e.g., tabs when `expandtab` is
  set)
* `keywords`: FIX, FIXME, HACK, TODO, WARN, WARNING, and XXX (see `:help
  scrollview-signs-keywords` for customization info)
* `latestchange`: latest change
* `loclist`: items on the location list
* `marks`
* `quickfix`: items on the quickfix list
* `search`
* `spell`: spell check items when the `spell` option is enabled
* `textwidth`: line lengths exceeding the value of the `textwidth` option, when
  non-zero
* `trail`: trailing whitespace

`search` and `diagnostics` groups are enabled by default (`marks` too for
`nvim>=0.10`). To modify which sign groups are enabled, set
`scrollview_signs_on_startup` accordingly in your Neovim configuation (see
`:help scrollview_signs_on_startup`), or use `:ScrollViewEnable {group1}
{group2} ...` to enable sign groups in the current Neovim session.

Clicking on a sign will navigate to its associated line. If a sign is linked to
multiple lines, successive clicks will cycle through these lines. Right-clicking
a sign reveals additional information, including its sign group and the
corresponding lines, which can be selected for navigation. Identifying the sign
group can be helpful if you are unsure what a sign represents.

The plugin was written so that it's possible to extend the sign functionality
in a Neovim configuration file or with a plugin. See the documentation for
details.

The [contrib](lua/scrollview/contrib) directory contains sign group
implementations that are not built-in (e.g., `coc`, `gitsigns`), but may be
useful to some users. The code there does not receive the same level of support
as the main source code, and may be less stable. Use at your own risk. For
installation instructions and other documentation, see the source code files.

## Configuration

There are various settings that can be configured. Please see the documentation
for details. The code below only shows a few of the possible settings.

#### Vimscript Example

```vim
let g:scrollview_excluded_filetypes = ['nerdtree']
let g:scrollview_current_only = v:true
" Position the scrollbar at the 80th character of the buffer
let g:scrollview_base = 'buffer'
let g:scrollview_column = 80
" Enable all sign groups (defaults to ['diagnostics', 'search']).
" Set to the empty list to disable all sign groups.
let g:scrollview_signs_on_startup = ['all']
" Show diagnostic signs only for errors.
let g:scrollview_diagnostics_severities =
      \ [luaeval('vim.diagnostic.severity.ERROR')]
```

#### Lua Example

A Lua `setup()` function is provided for convenience, to set globally scoped
options (the 'scrollview_' prefix is omitted).

```lua
require('scrollview').setup({
  excluded_filetypes = {'nerdtree'},
  current_only = true,
  base = 'buffer',
  column = 80,
  signs_on_startup = {'all'},
  diagnostics_severities = {vim.diagnostic.severity.ERROR}
})
```

Alternatively, configuration variables can be set without calling `setup()`.

```lua
vim.g.scrollview_excluded_filetypes = {'nerdtree'},
vim.g.scrollview_current_only = true,
vim.g.scrollview_base = 'buffer',
vim.g.scrollview_column = 80,
vim.g.scrollview_signs_on_startup = {'all'},
vim.g.scrollview_diagnostics_severities = {vim.diagnostic.severity.ERROR}
```
## Documentation

Documentation can be accessed with:

```nvim
:help nvim-scrollview
```

The underlying markup is in [scrollview.txt](doc/scrollview.txt).

#### Issues

Documentation for issues, along with some workarounds, can be accessed with:

```nvim
:help scrollview-issues
```

Some of the known issues are regarding scrollbar synchronization, error messages, session
restoration, and scrollbar floating windows being included in the window count returned by
`winnr('$')`.

## License

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).

See [LICENSE](LICENSE).

[badge_link]: https://github.com/dstein64/nvim-scrollview/actions/workflows/build.yml
[badge_thumbnail]: https://github.com/dstein64/nvim-scrollview/actions/workflows/build.yml/badge.svg
[dein]: https://github.com/Shougo/dein.vim
[gitsigns.nvim]: https://github.com/lewis6991/gitsigns.nvim
[gitsigns_example]: https://gist.github.com/dstein64/b5d9431ebeacae1fb963efc3f2c94cf4
[neobundle]: https://github.com/Shougo/neobundle.vim
[packer]: https://github.com/wbthomason/packer.nvim
[pathogen]: https://github.com/tpope/vim-pathogen
[vim8pack]: http://vimhelp.appspot.com/repeat.txt.html#packages
[vimplug]: https://github.com/junegunn/vim-plug
[vundle]: https://github.com/gmarik/vundle
