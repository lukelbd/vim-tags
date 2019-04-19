# IDE tools
This repo stores several IDE tools for **refactoring code**
cleanly and easily, and for **jumping between syntactically-meaningful parts**
of your code.
It relies on [vim-repeat](https://github.com/tpope/vim-repeat), the [exuberant ctags](http://ctags.sourceforge.net/) command-line tool, and, optionally, the [FZF](https://github.com/junegunn/fzf) vim plugin.

A fundamental feature of this plugin is the idea that `ctags` locations can
be used to approximately **delimit variable scope boundaries**.
For example, for a series of function declarations in a python module, with
no top-level code between the declarations, the lines between each
declaration approximately denote the scope for variables declared
inside the preceding function.
This approach is primitive and not always perfect, but
very flexible.
And it is on this basis that
this plugin provides some neat refactoring tools.

## Global plugin options

* `g:idetools_no_ctags`: Vim-list of strings specifying the
  filetypes for which we do not want to try to generate ctags.
* `g:idetools_all_ctags`: Vim-list of strings specifying the
  filetypes for which we want to use **not only** "top-level"
  tags as scope delimiters, but also "child" tags -- for example, functions
  declared inside of other functions. By default, this list is equal
  to just `['fortran']`, since all Fortran subroutines and functions
  must be declared inside of a "`program`" or "`module`", which have their own tags.
* `g:idetools_top_ctags_map`: Vim-dictionary whose keys are
  filetypes and whose values are lists of characters, corresponding to the ctags
  **categories** used to approximate the "local scope" refactoring tools.
  If the current filetype is not in the dictionary,
  the `'default'` entry is used (by default, this is `f`, indicating
  **function definition** locations).
  
  To generate a list of all possible ctags **categories** for all languages, run
  `ctags --list-kinds` on the command line. For a specific language, use
  e.g. `ctags --list-kinds=python`.

## Ctags maps

* `<Leader>c`: Displays a condensed table of the `ctags`.
* `<Leader>C`: Manually refreshes the `b:ctags` variable (done automatically
  on writing to file).
* `<Leader><Leader>`: Brings up a fuzzy-completion menu of the ctags list, and
  jumps to the selected location.
* `<CR>`: Goes to the definition of the word under the cursor with `gd`.
* `[[` and `]]`: Jumps to subsequent and preceding top-level "significant
  ctag locations" -- that is, omitting variable definitions, import statements, etc.
  Generally these are just function and class definition locations.

## Refactoring maps

* `!`, `*`, `&`: Selects the character, word or WORD under the cursor. Is case-sensitive. Does not move the cursor.
* `#`, `@`: As for `*` and `&`, but selects only the approximate **local-scope**
  instead of the entire file, using "significant ctag locations" as
  approximate scope boundaries.
* `g/`, `g?`: As for `/` and `?`, but again selects only the approximate local-scope
  instead of the entire file.
* `d/`, `d*`, `d&`, `d#`, `d@`: **Deletes** the corresponding selection under the cursor,
  and moves to the next occurrence (`d/` just uses the last search pattern).
  Hitting `.` deletes this occurrence and jumps to the next one.
* `c/`, `c*`, `c&`, `c#`, `c@`: **Replaces** the corresponding selection under the cursor
  with user input text by (1) deleting the selection (`c/` just uses the last search pattern) and (2) entering insert mode
  and allowing the user to type something.
  When the user presses `<Esc>`, it jumps to the next
  occurrence.
  Hitting `.` replaces this occurrence with the text you previously
  typed and jumps to the next one. This is like `:s/pattern/replacement/g`, but much cleaner.
* `da/`, `da*`, `da&`, `da#`, `da@`: As with `d/`, `d*`, `d&`, `d#`, `d@`, but
  deletes **all occurrences**.
* `ca/`, `ca*`, `ca&`, `ca#`, `ca@`: As with `c/`, `c*`, `c&`, `c#`, `c@`, but
  changes **all occurrences**.
* `<Leader>*`, `<Leader>&`: Counts the number of words or WORDs under the cursor

<!-- See the source code for more details. -->
<!-- Detailed description is coming soon. -->


# Installation
Install with your favorite [plugin manager](https://vi.stackexchange.com/questions/388/what-is-the-difference-between-the-vim-plugin-managers).
I highly recommend the [`vim-plug`](https://github.com/junegunn/vim-plug) manager,
in which case you can install this plugin by adding
```
Plug 'lukelbd/vim-idetools'
```
to your `~/.vimrc`.

