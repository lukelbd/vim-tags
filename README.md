Vim tags
========

A set of basic tools for integrating vim with
[exuberant ctags](http://ctags.sourceforge.net/) and [universal-ctags](https://docs.ctags.io/en/latest/index.html)
that help with refactoring and navigation in arbitrary file types.
Includes the following features:

* Quickly moving between tags and keywords, jumping to tags under the cursor, or
  jumping to particualr tags using a fuzzy-search algorithm (via the [fzf](https://github.com/junegunn/fzf) plugin).
* Changing or deleting words, WORDS, and regular expressions one-by-one
  or all at once using insert mode rather than the `:s` command.
* Changing or deleting words, WORDS, and regular expressions within the "local scope"
  approximated by certain tag kinds and folds that start on the same line.

The last feature is motivated by the idea that `expr` and `syntax` style folding
schemes typically fold variable scopes associated with functions, classes, and
modules, and any corresponding ctag kinds that start on the same line can be
used to identify those folds from other non-scope folds. This approach is not always
perfect but works with arbitrary filetypes. The "local scope" mappings always
print or highlight the line range selected by the algorithm.

Documentation
=============

Commands
--------

| Command | Description |
| ---- | ---- |
| `:Search` | Set the current search pattern to the input and print a count. Accepts an optional manually-passed or visually-selected line range. |
| `:ShowTags` | Update file tags and print them in a table. This ignores `g:tags_skip_kinds`. Use `:ShowTags!` to display tags for all open buffers or `:ShowTags path1 [path2...]` for specific files. |
| `:ShowKinds` | Print file tag kinds in a table. This ignores `g:tags_skip_kinds`. Use `:ShowKinds!` to display kinds for all open buffers or `:ShowKinds path1 [path2...]` for specific files. |
| `:CurrentTag` | Print the non-minor tag under or preceding the cursor. This can be shown in the status line by adding the associated function `tags#current_tag()` to `&statusline`. |
| `:UpdateTags` | Manually refresh the buffer-scope variables used by this plugin. This is called whenever a file is read or written. Use `:UpdateTags!` to update tags for all open buffers. |
| `:SelectTag` | Show a fuzzy-completion menu of tags and jump to the selected location. Use `:SelectTag!` to choose from tags across all open buffers instead of just the current buffer. |
| `:FindTag` | Find and jump to the input tag (default is the keyword under the cursor). Use `:FindTag!` to search tags across buffers of any filetype instead of just the current filetype. |

Jumping maps
------------

| Mapping | Description |
| ---- | ---- |
| `<Leader><Leader>` | Show a fuzzy-completion menu of the tags and jump to the selected location. This is only defined if the [fzf](https://github.com/junegunn/fzf) plugin is installed. The map can be changed with `g:tags_jump_map`. |
| `<Leader><Tab>` | Show a fuzzy-completion menu of the tags across all open tab page buffers and jump to the location with `:tab drop <file> \| exe <line>`. The map can be changed with `g:tags_drop_map`. |
| `<Leader><CR>` | Find the keyword under the cursor among the tag lists for all open tab page buffers and jump to the location if found. The map can be changed with `g:tags_find_map`. |
| `[t`, `]t` | Jump to subsequent and preceding tags. The maps can be changed with `g:tags_backward_map` and `g:tags_forward_map`. |
| `[T`, `]T` | Jump to subsequent and preceding top-level "significant" tags -- that is, omitting variable definitions, import statements, etc. Generally these are just function and class definitions. The maps can be changed with `g:tags_backward_top_map` and `g:tags_forward_top_map`. |
| `[w`, `]w` | Jump to subsequent and preceding instances of the keyword under the cursor for the current local scope. The maps can be changed with `g:tags_prev_local_map` and `g:tags_next_local_map`. |
| `[W`, `]W` | Jump to subsequent and preceding instances of the keyword under the cursor under global scope. The maps can be changed with `g:tags_prev_global_map` and `g:tags_next_global_map`. |

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
| `g:tags_skip_filetypes` | List of filetypes for which we do not want to try to generate tags. Setting this variable could speed things up a bit. Default is `['diff', 'help', 'man', 'qf']`. |
| `g:tags_skip_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds to ignore. Default behavior is to include all tags. |
| `g:tags_major_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds defining search scope boundaries. Default is `'f'` i.e. function definition tags. |
| `g:tags_minor_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds to ignore during bracket navigation. Default is `'v'` i.e. variable definition tags. |
| `g:tags_keep_jumps` | Whether to preserve the jumplist when navigating tags with bracket maps or jumping to tags under the cursor or selected from fzf. Default is ``0`` i.e. the jumplist is changed. |

Installation
============

Install with your favorite [plugin manager](https://vi.stackexchange.com/q/388/8084).
I highly recommend the [vim-plug](https://github.com/junegunn/vim-plug) manager.
To install with vim-plug, add
```
Plug 'lukelbd/vim-tags'
```
to your `~/.vimrc`.
