# IDE tools
This repo stores several IDE tools for **refactoring code**
cleanly and easily, and for **jumping between syntactically-meaningful parts**
of your code.
It relies on [vim-repeat](https://github.com/tpope/vim-repeat), the [exuberant ctags](http://ctags.sourceforge.net/) command-line tool,
and, optionally, the [FZF](https://github.com/junegunn/fzf) vim plugin.

Adds the following ctags-related normal mode maps.

* `<Leader>c`: Displays a condensed table of the `ctags`.
* `<Leader>C`: Manually refreshes the `b:ctags` variable (done automatically
  on writing to file).
* `<Leader><Leader>`: Brings up a fuzzy-completion menu of the ctags list, and
  jumps to the selected location.
* `<CR>`: Goes to the definition of the word under the cursor with `gd`.
* `[[` and `]]`: Jumps to subsequent and preceding top-level "significant
  ctag locations" -- that is, omitting variable definitions, import statements, etc.
  Generally these are just function and class definition locations.

Also adds the following refactoring-related normal mode maps.

* `!`: Selects for the single character under the cursor.
* `*`, `&`: Selects the word or WORD under the cursor. Is case-sensitive, and does not
  jump to the next one.
* `<Leader>*`, `<Leader>&`: Counts the number of words or WORDs under the cursor
  in the file.
* `#`, `@`: As for `*` and `&`, but selecting only the approximate **local-scope**
  instead of the entire file, using "significant ctag locations" as
  approximate scope boundaries.
* `g/`, `g?`: As for `/` and `?`, but again selecting only the approximate local-scope
  instead of the entire file.
* `d/`, `d*`, `d&`, `d#`, `d@`: **Deletes** the corresponding selection under the cursor,
  and moves to the next occurrence (`d/` just uses the last search pattern).
* `c/`, `c*`, `c&`, `c#`, `c@`: **Replaces** the corresponding selection under the cursor
  with user input text by (1) deleting the selection and (2) entering insert mode
  and allowing the user to type something (`c/` just uses the last search pattern).
  When the user presses `<Esc>`, it jumps to the next
  occurrence. Hitting `.` replaces this occurrence with the text you previously
  typed, and jumps to the next one. This is like `:s/pattern/replacement/g`, but much cleaner, much faster, and very powerful!
* `da/`, `da*`, `da&`, `da#`, `da@`: As with `d/`, `d*`, `d&`, `d#`, `d@`, but
  deletes **all occurrences** in the file or approximate local scope.
* `ca/`, `ca*`, `ca&`, `ca#`, `ca@`: As with `c/`, `c*`, `c&`, `c#`, `c@`, but
  changes **all occurrences** in the file or approximate local scope.

See the source code for more details.
<!-- Detailed description is coming soon. -->
