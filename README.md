# IDE tools
This repo stores several IDE tools for refactoring code cleanly and easily, and for jumping between syntactically-meaningful parts of your code.  It relies on [vim-repeat](https://github.com/tpope/vim-repeat) and the [exuberant ctags](http://ctags.sourceforge.net/) command-line tool. It also optionally provides a tool for jumping between tag locations, powered by the [FZF](https://github.com/junegunn/fzf) plugin.

Some features in this plugin are based on the idea that `ctags` locations can be used to approximately delimit variable scope boundaries.  For example, for a series of function declarations in a python module with no top-level code between the declarations, the lines between each declaration approximately denote the scope for variables declared inside the function.  This approach is primitive and not always perfect, but very flexible and works for all file types.

# Documentation

## Commands

| Command | Description |
| ---- | ---- |
| `:ReadTags` | Manually refreshes the `b:ctags_top`, `b:ctags_alph`, and `b:ctags_line` variables used by this plugin. This is called automatically whenever a file is read or written to disk. |
| `:DisplayTags` |  Displays a nicely condensed table of tags for the current file. |

## Mappings

| Mapping | Description |
| ---- | ---- |
| `<Leader><Leader>` | Brings up a fuzzy-completion menu of the ctags list, and jumps to the selected location. This is only defined if the [FZF](https://github.com/junegunn/fzf) plugin is installed. The map can be changed with `g:idetools_ctags_jump_map`. |
| `[t`, `]t` | Jumps to subsequent and preceding top-level "significant ctag locations" -- that is, omitting variable definitions, import statements, etc. Generally these are just function and class definition locations. The maps can be changed with `g:idetools_ctags_backward_map` and `g:idetools_ctags_forward_map`. |
| `!`, `*`, `&` | Selects the character, word or WORD under the cursor. Unlike the vim `*` map, these do not move the cursor. |
| `#`, `@` | As for `*` and `&`, but selects only the approximate local scope instead of the entire file, using "significant ctag locations" as approximate scope boundaries.
| `g/`, `g?` | As for `/` and `?`, but again selects only the approximate local scope instead of the entire file.
| `d/`, `d*`, `d&`, `d#`, `d@` | Deletes the corresponding selection under the cursor, and moves to the next occurrence.  Hitting `.` deletes this occurrence and jumps to the next one. `d/` uses the last search pattern.
| `c/`, `c*`, `c&`, `c#`, `c@` | Replaces the corresponding selection under the cursor with user input text by (1) deleting the selection and (2) entering insert mode and allowing the user to type something. `c/` uses the last search pattern. When you leave insert mode, it jumps to the next occurrence, and hitting `.` replaces this with the text you previously typed. This is like `:s/pattern/replacement/g` but cleaner.
| `da/`, `da*`, `da&`, `da#`, `da@` | As with `d/`, `d*`, `d&`, `d#`, `d@`, but deletes all occurrences.
| `ca/`, `ca*`, `ca&`, `ca#`, `ca@` | As with `c/`, `c*`, `c&`, `c#`, `c@`, but changes all occurrences.
| `<Leader>.`, `<Leader>*`, `<Leader>&` | Counts the number of search patterns, words, or WORDs under the cursor in the file. |

## Options

| Option | Description |
| ---- | ---- |
| `g:idetools_filetypes_skip` | List of filetypes for which we do not want to try to generate ctags. Fill this to prevent annoying error messages. |
| `g:idetools_filetypes_all_tags` | List of filetypes for which we want to use **not only** "top level" tags as scope delimiters, but also "child" tags -- for example, functions declared inside of other functions. By default, this list is equal to just `['fortran']`, since all Fortran subroutines and functions must be declared inside of a "`program`" or "`module`", which have their own tags. |
| `g:idetools_filetypes_top_tags` | Dictionary whose keys are filetypes or file names and whose values are lists of characters, corresponding to the ctags categories used to approximate the local scope refactoring tools.  If the current filetype is not in the dictionary, the `'default'` entry is used. By default, this is `f`, indicating function definition locations. To generate a list of all possible ctags categories for a given language, call e.g. `ctags --list-kinds=pyghon` on the command line. |

# Installation
Install with your favorite [plugin manager](https://vi.stackexchange.com/questions/388/what-is-the-difference-between-the-vim-plugin-managers).
I highly recommend the [`vim-plug`](https://github.com/junegunn/vim-plug) manager,
in which case you can install this plugin by adding
```
Plug 'lukelbd/vim-idetools'
```
to your `~/.vimrc`.

