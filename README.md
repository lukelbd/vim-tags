Vim tags
========

A set of basic tools for integrating vim with
[exuberant ctags](http://ctags.sourceforge.net/) and [universal-ctags](https://docs.ctags.io/en/latest/index.html)
that help with refactoring and navigation in arbitrary file types for vim
sessions with many open windows.

Includes the following `ctags`-powered navigation features:

* Jumping to the tag under the cursor across open tabs and windows with the default
  mapping `<Leader><CR>`. Tags are generated whenever a buffer is read or written,
  then stored in buffer variables `b:tags_by_line` and `b:tags_by_name`. Any
  buffers that belong to filetypes in `g:tags_skip_filetypes` are skipped.
* Selecting and jumping to tags in the current window or across all open windows from
  an [fzf.vim](https://github.com/junegunn/fzf.vim) fuzzy-search window with the default mappings `<Leader><Leader>` and
  `<Leader><Tab>` (respectively). For jumping to arbitrary tags across a project,
  see `:help 'tags'`, [vim-gutentags](https://github.com/ludovicchabant/vim-gutentags), and the [fzf.vim](https://github.com/junegunn/fzf.vim) `:Tags` command.
* Moving between adjacent buffer tags with default bracket mappings `[t`, `]t`, `[T`,
  and `]T`. The lowercase mappings ignore "minor" tags in `g:tags_minor_kinds` (e.g.
  variables; see `:ShowKinds` for options), and the uppercase mappings only include
  "major" tags in `g:tags_major_kinds` (default is `f` for functions).
* Moving between adjacent keywords with default bracket mappings `[w`, `]w`, `[W`,
  and `]W`. The lowercase mappings restrict the search to the local variable scope
  (estimated from the positions of "major" tags and fold boundaries; see below for
  details). These mappings skip instances in `Comment` syntax blocks.

Also includes the following related search-and-replace features:

* Selecting characters, words, or WORDS under the cursor without jumping to the
  next occurrence with the default mappings `!`, `*`, and `&`; selecting words or
  WORDS within the current local variable scope with the default mappings `#` and
  `@`; or searching the local scope manually with `g/` or `g?` (analogous to `/` and
  `?`). As with the `[w` and `]w` mappings, local scope is estimated from "major" tags
  and fold boundaries (see below). These highlight the matches with `:hlsearch` and
  call the [vim-indexed-search](https://github.com/henrik/vim-indexed-search) command `:ShowSearchIndex` if it is available.
* Deleting characters, words, or WORDS under the cursor with the default mappings
  `d!`, `d*`, `d&` (respectively); deleting words or WORDS in the current local variable
  scope with `d#` and `d@`; or deleting previous searches with `d/` or `d?`. These
  automatically jump to the next match after deletion (or previous for `d?`).
  If [vim-repeat](https://github.com/tpope/vim-repeat) is installed, hitting `.` will repeat the previous deletion and repeat
  the jump. This is similar to `:s` but keeps you from having to leave normal mode.
  Use `da!`, `da*`, `da&`, `da#`, `da@`, `da/`, or `da?` to delete *all* matches.
* Changing characters, words, or WORDS under the cursor with the default mappings
  `c!`, `c*`, `c&` (respectively); changing words or WORDS in the current local
  variable scope with `c#` and `c@`; or changing previous searches with `c/` or `c?`.
  These enter insert mode, allowing you to type something, then automatically jump to
  the next match after leaving insert mode (or previous for `c?`). As with the `d`
  maps, hitting `.` will repeat the previous replacement and repeat the jump.
  Use `ca!`, `ca*`, `ca&`, `ca#`, `ca@`, `ca/`, or `ca?` to change *all* matches.

The `[w` and `]w` local-scope jumping feature and `#` and `@` local-scope searching
features are motivated by the idea that `expr` and `syntax` style folds typically
include regions that comprise the variable scopes associated with functions,
classes, and modules, and the "kind" property of any tag that starts on the same
line as a fold can be used to distinguish these scope-defining folds from other folds.
This approach is not always perfect but works with arbitrary filetypes. Note the
`#`, `d#`, `c#`, `@`, `d@`, and `c@` mappings print the line range selected by
the algorithm, or you can use `g/` or `g?` to highlight the entire range.

Documentation
=============

Commands
--------

| Command | Description |
| ---- | ---- |
| `:Search` | Set the current search pattern to the input and print a count. Accepts an optional manually-passed or visually-selected line range. |
| `:ShowTags` | Update file tags and print them in a table. This ignores `g:tags_skip_kinds`. Use `:ShowTags!` to display tags for all open buffers or `:ShowTags path1 [path2...]` for specific files. |
| `:ShowKinds` | Print file tag kinds in a table. This ignores `g:tags_skip_kinds`. Use `:ShowKinds!` to display kinds for all open buffers or `:ShowKinds path1 [path2...]` for specific files. |
| `:UpdateTags` | Manually refresh the buffer-scope variables used by this plugin. This is called whenever a file is read or written. Use `:UpdateTags!` to update tags for all open buffers. |
| `:SelectTag` | Show a fuzzy-completion menu of tags and jump to the selected location. Use `:SelectTag!` to choose from tags across all open buffers instead of just the current buffer. |
| `:CursorTag` | Jump to the tag under the cursor or passed to the command. Use `:CursorTag!` to search tags across buffers of any filetype instead of just the current filetype. |

Jumping maps
------------

| Mapping | Description |
| ---- | ---- |
| `<Leader><Leader>` | Show a fuzzy-completion menu of the tags and jump to the selected location. This is only defined if the [fzf](https://github.com/junegunn/fzf) plugin is installed. The map can be changed with `g:tags_bselect_map`. |
| `<Leader><Tab>` | Show a fuzzy-completion menu of the tags across all open tab page buffers and jump to the location with `:tab drop <file> \| exe <line>`. The map can be changed with `g:tags_select_map`. |
| `<Leader><CR>` | Jump to the tag under the cursor. Similar to `<C-]>`, but works both with and without tag files and jumps to existing windows/opens buffers in new tabs. The map can be changed with `g:tags_cursor_map`. |
| `[t`, `]t` | Jump to previous and next tag locations. The cursor is positioned at the start of the tag name. The maps can be changed with `g:tags_backward_map` and `g:tags_forward_map`. |
| `[T`, `]T` | Jump to previous and next "major" tags from `g:tags_major_kinds`. These are function definitions by default (i.e. tag kind `f`). The maps can be changed with `g:tags_backward_top_map` and `g:tags_forward_top_map`. |
| `[w`, `]w` | Jump to previous and next instances of the keyword under the cursor for the current local scope. The maps can be changed with `g:tags_prev_local_map` and `g:tags_next_local_map`. |
| `[W`, `]W` | Jump to previous and next instances of the keyword under the cursor under global scope. The maps can be changed with `g:tags_prev_global_map` and `g:tags_next_global_map`. |

Searching maps
--------------

| Mapping | Description |
| ---- | ---- |
| `!`, `*`, `&` | Select the character, word or WORD under the cursor. The maps can be changed with `g:tags_char_global_map` (default `!`), `g:tags_word_global_map` (default `*`), and `g:tags_WORD_global_map` (default `@`), respectively. |
| `#`, `@` | As for `*` and `&`, but select only the "local" scope defined syntax or expr-style folds that begin on the same line as tag kind in `g:tags_major_kinds` (default is functions i.e. `f`). The maps can be changed with `g:tags_word_local_map` (default `#`) and `g:tags_WORD_local_map` (default `@`). |
| `g/`, `g?` | As for `/` and `?`, but again select only the approximate local scope instead of the entire file. Typing only `g/` and `g?` will highlight the entire scope. These maps cannot be changed from the default. |
| `d/`, `d*`, `d&`, `d#`, `d@` | Delete the corresponding selection under the cursor and move to the next occurrence (`d/` uses the most recent search pattern). Use `.` to delete additional occurrences (whether or not they are under the cursor) and then jump to following matches. This is similar to `:substitute` but permits staying in normal mode. The mapping suffixes can be changed with `g:tags_word_global_map`, `g:tags_WORD_global_map`, `g:tags_word_local_map`, and `g:tags_WORD_local_map` (see above). |
| `da/`, `da*`, `da&`, `da#`, `da@` | As with `d/`, `d*`, `d&`, `d#`, `d@`, but delete *all* occurrences. |
| `c/`, `c*`, `c&`, `c#`, `c@` | Replace the corresponding selection under the cursor in insert mode and jump to the next occurrence after leaving insert mode (`c/` uses the most recent search pattern). Use `.` to replace additional occurrences with what you typed on the first replacement and then jump to following matches. The mapping suffixes can be changed with `g:tags_word_global_map`, `g:tags_WORD_global_map`, `g:tags_word_local_map`, and `g:tags_WORD_local_map` (see above). |
| `ca/`, `ca*`, `ca&`, `ca#`, `ca@` | As with `c/`, `c*`, `c&`, `c#`, `c@`, but change *all* occurrences. |

Options
-------

| Setting | Description |
| ---- | ---- |
| `g:tags_nomap` | Whether to disable the default maps. Default is `0`. If `1` you must add all maps manually (see `plugin/tags.vim`). |
| `g:tags_nomap_jumps` | Whether to disable the maps that jump between ctag locations and keywords (e.g. `<Leader><CR>`, `]t`, `]w`, etc.). Default is `g:tags_nomap`. |
| `g:tags_nomap_searches` | Whether to disable the maps used for searching and relacing words under the cursor (e.g. `*`, `d*`, `c*`, etc.). Default is `g:tags_nomap`. |
| `g:tags_skip_filetypes` | List of filetypes for which we do not want to try to generate tags. Setting this variable could speed things up a bit. Default is `['diff', 'help', 'man', 'qf']`. |
| `g:tags_skip_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds to ignore. Default behavior is to include all tags. |
| `g:tags_major_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds defining search scope boundaries. Default is `'f'` i.e. function definition tags. |
| `g:tags_minor_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds to ignore during bracket navigation. Default is `'v'` i.e. variable definition tags. |
| `g:tags_keep_jumps` | Whether to preserve the jumplist when navigating tags with bracket maps. Default is ``0``. Note jumping to tags under the cursor or with fzf always changes the jumplist. |
| `g:tags_keep_stack` | Whether to preserve the tag stack when jumping to tags under the cursor or with fzf. Default is ``0``. Note jumping to tags with bracket maps never changes the tag stack. |

Installation
============

Install with your favorite [plugin manager](https://vi.stackexchange.com/q/388/8084).
I highly recommend the [vim-plug](https://github.com/junegunn/vim-plug) manager.
To install with vim-plug, add
```
Plug 'lukelbd/vim-tags'
```
to your `~/.vimrc`.
