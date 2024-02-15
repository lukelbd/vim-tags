Vim tags
========

A set of basic tools for integrating vim with
[exuberant ctags](http://ctags.sourceforge.net/) and [universal-ctags](https://docs.ctags.io/en/latest/index.html)
that help with refactoring and navigation in arbitrary file types.
Includes the following features:

* Jumping between tags or jumping to particular tags using a fuzzy-search algorithm
  (via the [fzf](https://github.com/junegunn/fzf) plugin).
* Quickly changing or deleting words, WORDS, and regular expressions one-by-one
  or all at once using insert mode rather than the `:s` command.
* Changing or deleting words, WORDS, and regular expressions delimited by adjacent
  tags -- for example, successive function definitions.

The last feature is motivated by the idea that certain tags approximately delimit the
variable scope boundaries. For example, given a consecutive series of function
declarations in a python module, the lines between each declaration approximately denote
the scope for variables declared inside the function. This approach is primitive and not
always perfect, but works with arbitrary file types.

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

Mappings
--------

| Mapping | Description |
| ---- | ---- |
| `<Leader><Leader>` | Show a fuzzy-completion menu of the tags and jump to the selected location. This is only defined if the [fzf](https://github.com/junegunn/fzf) plugin is installed. The map can be changed with `g:tags_jump_map`. |
| `<Leader><Tab>` | Show a fuzzy-completion menu of the tags across all open tab page buffers and jump to the location with `:tab drop <file> | exe <line>`. The map can be changed with `g:tags_drop_map`. |
| `[t`, `]t` | Jump to subsequent and preceding tags. The maps can be changed with `g:tags_backward_map` and `g:tags_forward_map`. |
| `[T`, `]T` | Jump to subsequent and preceding top-level "significant" tags -- that is, omitting variable definitions, import statements, etc. Generally these are just function and class definitions. The maps can be changed with `g:tags_backward_top_map` and `g:tags_forward_top_map`. |
| `!`, `*`, `&` | Select the character, word or WORD under the cursor. Unlike the vim `*` map, these do not move the cursor. |
| `#`, `@` | As for `*` and `&`, but select only the approximate local scope instead of the entire file, using "significant ctag locations" as scope boundaries (typically functions).
| `g/`, `g?` | As for `/` and `?`, but again select only the approximate local scope instead of the entire file.
| `d/`, `d*`, `d&`, `d#`, `d@` | Delete the corresponding selection under the cursor and move to the next occurrence.  Hitting `.` deletes this occurrence and jumps to the next one. `d/` uses the last search pattern.
| `c/`, `c*`, `c&`, `c#`, `c@` | Replace the corresponding selection under the cursor with user input text by (1) deleting the selection and (2) entering insert mode and allowing the user to type something. `c/` uses the last search pattern. When you exit insert mode we jump to the next occurrence. Hitting `.` replaces this with the text you previously typed. This is like `:s/pattern/replacement/g` but cleaner.
| `da/`, `da*`, `da&`, `da#`, `da@` | As with `d/`, `d*`, `d&`, `d#`, `d@`, but delete *all* occurrences.
| `ca/`, `ca*`, `ca&`, `ca#`, `ca@` | As with `c/`, `c*`, `c&`, `c#`, `c@`, but change *all* occurrences.

Options
-------

| Option | Description |
| ---- | ---- |
| `g:tags_skip_filetypes` | List of filetypes for which we do not want to try to generate tags. Setting this variable could speed things up a bit. Default is `['diff', 'help', 'man', 'qf']`. |
| `g:tags_skip_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds to ignore. Default behavior is to include all tags. |
| `g:tags_major_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds defining search scope boundaries. Default is `'f'` i.e. function definition tags. |
| `g:tags_minor_kinds` | Dictionary whose keys are filetypes and whose values are strings indicating the tag kinds to ignore during bracket navigation. Default is `'v'` i.e. variable definition tags. |

Installation
============

Install with your favorite [plugin manager](https://vi.stackexchange.com/q/388/8084).
I highly recommend the [vim-plug](https://github.com/junegunn/vim-plug) manager.
To install with vim-plug, add
```
Plug 'lukelbd/vim-tags'
```
to your `~/.vimrc`.
