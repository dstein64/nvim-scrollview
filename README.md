[![build][badge_thumbnail]][badge_link]

# nvim-scrollview

`nvim-scrollview` is a Neovim plugin that displays interactive vertical
scrollbars and signs. The plugin is customizable (see `:help
scrollview-configuration`).

<img src="https://github.com/dstein64/media/blob/main/nvim-scrollview/screenshot.svg?raw=true" width="600" />

## Features

* Handling for folds
* Scrollbars can be dragged with the mouse
* Partially transparent scrollbars so that text is not covered
* Signs (`diagnostics` and `search` enabled by default)

## Requirements

* `nvim>=0.5`
* Scrollbar mouse dragging requires mouse support (see `:help 'mouse'`) and
  `nvim>=0.6`
* Signs require `nvim>=0.7`

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
  `:ScrollViewToggle` toggles the plugin. When arguments are given, the
  specified sign groups are toggled.
* `:ScrollViewRefresh` refreshes the scrollbars. This is relevant when the
  scrollbars are out-of-sync, which can occur as a result of some window
  arrangement actions.
* `:ScrollViewNext`, `:ScrollViewPrev`, `:ScrollViewFirst`, and
  `ScrollViewLast` move the cursor to lines with signs. Arguments can specify
  which sign groups are considered.
* The scrollbars can be dragged and signs can be clicked. This requires a
  corresponding mapping, which is automatically configured when
  `scrollview_auto_mouse` is set (see `:help scrollview-mouse-customization`).

## Signs

There is built-in support for various types of signs (referred to as "sign
groups"), listed below. The functionality is similar to the sign column, but
with the same positioning logic as the scrollbar.

* `conflicts`: git merge conflicts
* `cursor`: cursor position
* `diagnostics`: errors, warnings, info, and hints
* `folds`: closed folds
* `loclist`: items on the location list
* `marks`
* `quickfix`: items on the quickfix list
* `search`
* `spell`: spell check items when the `spell` option is enabled
* `textwidth`: line lengths exceeding the value of the textwidth option, when
  non-zero
* `trail`: trailing whitespace, when the `list` option is enabled and the
  `listchars` option includes "trail"

`search` and `diagnostics` groups are enabled by default.

The plugin was written so that it's possible to extend the sign functionality
in a Neovim configuration file or with a plugin. See the documentation for
details. An [example][gitsigns_example] was created to show how support for
[gitsigns.nvim][gitsigns.nvim] could be implemented. Plugin authors can tag
their repos with `scrollview-signs` for [discoverability][scrollview-signs].

## Configuration

There are various settings that can be configured. Please see the documentation
for details.

#### VimScript Example

```vim
let g:scrollview_excluded_filetypes = ['nerdtree']
let g:scrollview_current_only = v:true
let g:scrollview_winblend = 75
" Position the scrollbar at the 80th character of the buffer
let g:scrollview_base = 'buffer'
let g:scrollview_column = 80
" Enable all sign groups (defaults to ['diagnostics', 'search'])
let g:scrollview_signs_on_startup = ['all']
```

#### Lua Setup Example

```lua
require('scrollview').setup({
  excluded_filetypes = {'nerdtree'},
  current_only = true,
  winblend = 75,
  base = 'buffer',
  column = 80,
  signs_on_startup = {'all'}
})
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
[scrollview-signs]: https://github.com/topics/scrollview-signs
[vim8pack]: http://vimhelp.appspot.com/repeat.txt.html#packages
[vimplug]: https://github.com/junegunn/vim-plug
[vundle]: https://github.com/gmarik/vundle
