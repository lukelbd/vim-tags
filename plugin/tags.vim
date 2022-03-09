"------------------------------------------------------------------------------"
" Author: Luke Davis (lukelbd@gmail.com)
" Date:   2018-09-09
" A collection of IDE-like tools for vim. See README.md for details.
"------------------------------------------------------------------------------"
" * Each element of the b:tags_by_line list (and similar lists) is as follows:
"     Index 0: Tag name.
"     Index 1: Tag line number.
"     Index 2: Tag type.
" * Made my own implementation instead of using easytags or gutentags, because
"   (1) find that :tag and :pop are not that useful outside of help menus --
"   generally only want to edit one file at a time, and the <C-]> is about as
"   reliable as gd or gD, and (2) now I can filter the most important tags
"   and make them searchable, without losing the completion popup you'd get
"   from :tagjump /<Tab>.
" * General searching/replacing utilities, useful for refactoring. A convervative
"   approach is taken for the most part -- global searches are not automatic. But
"   could expand functionality by adding s*, s# maps to go along with c*, c# maps,
"   which replace every choice without user confirmation. Or C*, C# would work.
" * Re-define a few of the shift-number row keys to make them a bit more useful:
"     '*' is the current word, global
"     '&' is the current WORD, global
"     '#' is the current word, local
"     '@' is the current WORD, local
"   This made sense for my workflow because I never really want the backward
"   search from '#', access my macros with the comma key instead of @, and the
"   & key goes pretty much untouched.
" * For c* and c# map origin, see:
"   https://www.reddit.com/r/vim/comments/8k4p6v/what_are_your_best_mappings/
"   https://www.reddit.com/r/vim/comments/2p6jqr/quick_replace_useful_refactoring_and_editing_tool/
" * For repeat.vim usage see:
"   http://vimcasts.org/episodes/creating-repeatable-mappings-with-repeat-vim/
call system('type ctags &>/dev/null')
if v:shell_error " exit code
  echohl WarningMsg
  echom 'Error: vim-tags requires the command-line tool ctags, not found.'
  echohl None
  finish
endif
set cpoptions+=d
augroup tags
  au!
  au InsertLeave * call tags#change_repeat()  " magical c* searching function
  au BufReadPost,BufWritePost * call tags#update_tags()
augroup END

" Files that we wish to ignore
if !exists('g:tags_skip_filetypes')
  let g:tags_skip_filetypes = ['diff', 'help', 'man', 'qf']
endif

" List of per-file/per-filetype tag categories that we define as 'scope-delimiters',
" i.e. tags approximately denoting boundaries for variable scope of code block underneath cursor
if !exists('g:tags_scope_filetypes')
  let g:tags_scope_filetypes = {}
endif

" List of files for which we only want not just the 'top level' tags (i.e. tags
" that do not belong to another block, e.g. a program or subroutine)
if !exists('g:tags_nofilter_filetypes')
  let g:tags_nofilter_filetypes = []
endif

" Default mapping settings
if !exists('g:tags_jump_map')
  let g:tags_jump_map = '<Leader><Leader>'
endif
if !exists('g:tags_backward_map')
  let g:tags_backward_map = '[t'
endif
if !exists('g:tags_forward_map')
  let g:tags_forward_map = ']t'
endif
if !exists('g:tags_backward_top_map')
  let g:tags_backward_top_map = '[T'
endif
if !exists('g:tags_forward_top_map')
  let g:tags_forward_top_map = ']T'
endif

"-----------------------------------------------------------------------------"
" Tag commands and maps
"-----------------------------------------------------------------------------"
" Replace driver function
" Warning: *Must* be in here because cannot issue normal! in autoload folder evidently
function! s:replace_occurence() abort
  let [l0, c0] = getpos('.')[1:2]
  let reg = getreg('"')
  let regmode = getregtype('"')
  let winview = winsaveview()
  normal! ygn
  let [l1, c1] = getpos("'[")[1:2]  " first char of yanked text
  let [l2, c2] = getpos("']")[1:2]  " last char of yanked text
  call setreg('"', reg, regmode)
  call winrestview(winview)
  if l0 >= l1 && l0 <= l2 && c0 >= c1 && c0 <= c2  " replace next occurence with previously inserted text
    exe "silent! normal! cgn\<C-a>\<Esc>"
  endif
  silent! normal! n
  call repeat#set("\<Plug>replace_occurence")
endfunction

" Public commands
command! ShowTag echom 'Current tag: ' . tags#print_tag()
command! ShowTags call tags#print_tags()
command! UpdateTags call tags#update_tags()

" Tag search maps
" Note: Must use :n instead of <expr> ngg so we can use <C-u> to discard count!
exe 'map <silent> ' . g:tags_forward_map . ' <Plug>TagsForwardAll'
exe 'map <silent> ' . g:tags_backward_map . ' <Plug>TagsBackwardAll'
exe 'map <silent> ' . g:tags_forward_top_map . ' <Plug>TagsForwardTop'
exe 'map <silent> ' . g:tags_backward_top_map . ' <Plug>TagsBackwardTop'
noremap <expr> <silent> <Plug>TagsForwardAll tags#jump_tag(v:count, 0, 1)
noremap <expr> <silent> <Plug>TagsBackwardAll tags#jump_tag(v:count, 0, 0)
noremap <expr> <silent> <Plug>TagsForwardTop tags#jump_tag(v:count, 1, 1)
noremap <expr> <silent> <Plug>TagsBackwardTop tags#jump_tag(v:count, 1, 0)

" Tag jump map
" Note: If statement must be embedded in mapping to avoid race condition issues
exe 'nmap ' . g:tags_jump_map . ' <Plug>TagsJump'
nnoremap <silent> <Plug>TagsJump
  \ :if exists('*fzf#run') \| call fzf#run(fzf#wrap({
  \ 'source': tags#list_tags(),
  \ 'sink': function('tags#select_tags'),
  \ 'options': "--no-sort --prompt='Tag> '",
  \ })) \| endif<CR>

"------------------------------------------------------------------------------"
" Refactoring commands and maps
"------------------------------------------------------------------------------"
" Public commands
command! -nargs=1 -range Count <line1>,<line2>call tags#count_occurence(<f-args>)

" Global and local <cword> and global and local <cWORD> searches, current
" character search, and forward and backward local scope search.
nnoremap <silent> <Plug>replace_occurence <Cmd>call <sid>replace_occurence()<CR>
nnoremap <silent> <expr> * tags#set_search('*')
nnoremap <silent> <expr> & tags#set_search('&')
nnoremap <silent> <expr> # tags#set_search('#')
nnoremap <silent> <expr> @ tags#set_search('@')
nnoremap <silent> <expr> ! tags#set_search('!')
nnoremap <silent> <expr> g/ '/' . tags#get_scope()
nnoremap <silent> <expr> g? '?' . tags#get_scope()

" Count number of occurrences for match under cursor
" Note: current character copied from https://stackoverflow.com/a/23323958/4970632
noremap <Leader>*
  \ <Cmd>call tags#count_occurence('\<' . escape(expand('<cword>'), '[]\/.*$~') . '\>')<CR>
noremap <Leader>&
  \ <Cmd>call tags#count_occurence('\_s' . escape(expand('<cWORD>'), '[]\/.*$~') . '\_s')<CR>
noremap <Leader>!
  \ <Cmd>call tags#count_occurence(escape(matchstr(getline('.'), '\%' . col('.') . 'c.'), '[]\/.*$~'))<CR>
noremap <Leader>/
  \ <Cmd>call tags#count_occurence(@/)<CR>

" Maps that replicate :d/regex/ behavior and can be repeated with '.'
nmap d/ <Plug>d/
nmap d* <Plug>d*
nmap d& <Plug>d&
nmap d# <Plug>d#
nmap d@ <Plug>d@
nnoremap <expr> <Plug>d/ tags#delete_next('d/')
nnoremap <expr> <Plug>d* tags#delete_next('d*')
nnoremap <expr> <Plug>d& tags#delete_next('d&')
nnoremap <expr> <Plug>d# tags#delete_next('d#')
nnoremap <expr> <Plug>d@ tags#delete_next('d@')

" Similar to the above, but replicates :s/regex/sub/ behavior -- the substitute
" value is determined by what user enters in insert mode, and the cursor jumps
" to the next map after leaving insert mode
nnoremap <expr> c/ tags#change_next('c/')
nnoremap <expr> c* tags#change_next('c*')
nnoremap <expr> c& tags#change_next('c&')
nnoremap <expr> c# tags#change_next('c#')
nnoremap <expr> c@ tags#change_next('c@')

" Maps as above, but this time delete or replace *all* occurrences
" Added a block to next_occurence function
nmap da/ <Cmd>tags#delete_all('d/')<CR>
nmap da* <Cmd>tags#delete_all('d*')<CR>
nmap da& <Cmd>tags#delete_all('d&')<CR>
nmap da# <Cmd>tags#delete_all('d#')<CR>
nmap da@ <Cmd>tags#delete_all('d@')<CR>
nmap ca/ <Cmd>let g:iterate_occurences = 1<CR>c/
nmap ca* <Cmd>let g:iterate_occurences = 1<CR>c*
nmap ca& <Cmd>let g:iterate_occurences = 1<CR>c&
nmap ca# <Cmd>let g:iterate_occurences = 1<CR>c#
nmap ca@ <Cmd>let g:iterate_occurences = 1<CR>c@
