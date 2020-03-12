"------------------------------------------------------------------------------"
" Author: Luke Davis (lukelbd@gmail.com)
" Date:   2018-09-09
" Tries to wrap a few related features into one plugin file,
" including super cool and useful ***refactoring*** tools based on ctags:
" * Ctags integration -- jumping between successive tags, jumping to a particular
"   tag based on its regex, searching/replacing text blocks delimited by the
"   lines on which tags appear (roughly results in function-local search).
"   Each element of the b:ctags list (and similar lists) is as follows:
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
" * For repeat.vim usage see: http://vimcasts.org/episodes/creating-repeatable-mappings-with-repeat-vim/
" Todo: Make sure python2 and python3 shebangs work
" Maybe re-implement: if getline(1)=~"#!.*python[23]" | let force = "--language=python"
"------------------------------------------------------------------------------"
" Initial stuff
call system('type ctags &>/dev/null')
if v:shell_error " exit code
  echohl WarningMsg
  echom 'Error: vim-idetools requires the command-line tool ctags, not found.'
  echohl None
  finish
endif
set cpoptions+=d
augroup idetools
  au!
  au InsertLeave * call idetools#change_repeat() " magical c* searching function
  au BufRead,BufWritePost * call idetools#ctags_update()
augroup END

" Files that we wish to ignore
if !exists('g:idetools_filetypes_skip')
  let g:idetools_filetypes_skip = ['qf', 'rst', 'man', 'help', 'diff', 'nerdtree', 'tagbar']
endif

" List of per-file/per-filetype tag categories that we define as 'scope-delimiters',
" i.e. tags approximately denoting boundaries for variable scope of code block underneath cursor
if !exists('g:idetools_filetypes_top_tags')
  let g:idetools_filetypes_top_tags = {
    \ 'vim'     : 'afc',
    \ 'tex'     : 'bs',
    \ 'python'  : 'fcm',
    \ 'fortran' : 'smfp',
    \ 'default' : 'f',
    \ }
endif

" List of files for which we only want not just the 'top level' tags (i.e. tags
" that do not belong to another block, e.g. a program or subroutine)
if !exists('g:idetools_filetypes_all_tags')
  let g:idetools_filetypes_all_tags = ['fortran']
endif

" Default map variables
if !exists('g:idetools_ctags_jump_map')
  let g:idetools_ctags_jump_map = '<Leader><Leader>'
endif
if !exists('g:idetools_ctags_backward_map')
  let g:idetools_ctags_backward_map = '[t'
endif
if !exists('g:idetools_ctags_forward_map')
  let g:idetools_ctags_forward_map = ']t'
endif
if !exists('g:idetools_ctags_backward_top_map')
  let g:idetools_ctags_backward_top_map = '[T'
endif
if !exists('g:idetools_ctags_forward_top_map')
  let g:idetools_ctags_forward_top_map = ']T'
endif

"-----------------------------------------------------------------------------"
" Ctags commands and maps
"-----------------------------------------------------------------------------"
" Comamnds
command! CTagsUpdate call idetools#ctags_update()
command! CTagsDisplay call idetools#ctags_display()

" Jump and bracket maps
" Note: Must use :n instead of <expr> ngg so we can use <C-u> to discard count!
exe 'noremap <expr> <silent> ' . g:idetools_ctags_forward_top_map
  \ . ' idetools#ctagjump(1, v:count, 1)'
exe 'noremap <expr> <silent> ' . g:idetools_ctags_backward_top_map
  \ . ' idetools#ctagjump(0, v:count, 1)'
exe 'noremap <expr> <silent> ' . g:idetools_ctags_forward_map
  \ . ' idetools#ctagjump(1, v:count, 0)'
exe 'noremap <expr> <silent> ' . g:idetools_ctags_backward_map
  \ . ' idetools#ctagjump(0, v:count, 0)'
if exists('*fzf#run')
  exe 'nnoremap <silent> ' . g:idetools_ctags_jump_map
    \ . ' :call fzf#run({'
    \ . '"source": idetools#ctags_menu(b:ctags_alph), '
    \ . '"sink": function("idetools#ctags_select"), '
    \ . '"down": "~20%"})<CR>'
endif

"------------------------------------------------------------------------------"
" Refactoring tool maps
"------------------------------------------------------------------------------"
" Driver function *must* be in here because cannot issue normal! in
" autoload folder evidently
function! s:replace_occurence() abort
  " Get lines and columns for next occurence without messing up window/register
  let [l0, c0] = getpos('.')[1:2]
  let reg = getreg('"')
  let regmode = getregtype('"')
  let winview = winsaveview()
  normal! ygn
  let [l1, c1] = getpos("'[")[1:2] " first char of yanked text
  let [l2, c2] = getpos("']")[1:2] " last char of yanked text
  call setreg('"', reg, regmode)
  call winrestview(winview)

  " Replace next occurence with previously inserted text
  if l0 >= l1 && l0 <= l2 && c0 >= c1 && c0 <= c2
    exe "silent! normal! cgn\<C-a>\<Esc>"
  endif
  silent! normal! n
  call repeat#set("\<Plug>replace_occurence")
endfunction

" Mapping for vim-repeat command
nnoremap <silent> <Plug>replace_occurence :call <sid>replace_occurence()<CR>

" Global and local <cword> and global and local <cWORD> searches, and current character
nnoremap <silent> <expr> * idetools#set_search('*')
nnoremap <silent> <expr> & idetools#set_search('&')
nnoremap <silent> <expr> # idetools#set_search('#')
nnoremap <silent> <expr> @ idetools#set_search('@')
nnoremap <silent> <expr> ! idetools#set_search('!')
" Search within function scope
nnoremap <silent> <expr> g/ '/'.idetools#get_scope()
nnoremap <silent> <expr> g? '?'.idetools#get_scope()
" Count number of occurrences for match under cursor
nnoremap <silent> <Leader>* :echom 'Number of "'.expand('<cword>').'" occurences: '.system('grep -c "\b"'.shellescape(expand('<cword>')).'"\b" '.expand('%'))<CR>
nnoremap <silent> <Leader>& :echom 'Number of "'.expand('<cWORD>').'" occurences: '.system('grep -c "[ \n\t]"'.shellescape(expand('<cWORD>')).'"[ \n\t]" '.expand('%'))<CR>
nnoremap <silent> <Leader>. :echom 'Number of "'.@/.'" occurences: '.system('grep -c '.shellescape(@/).' '.expand('%'))<CR>

" Maps that replicate :d/regex/ behavior and can be repeated with '.'
nmap d/ <Plug>d/
nmap d* <Plug>d*
nmap d& <Plug>d&
nmap d# <Plug>d#
nmap d@ <Plug>d@
nnoremap <silent> <expr> <Plug>d/ idetools#delete_next('d/')
nnoremap <silent> <expr> <Plug>d* idetools#delete_next('d*')
nnoremap <silent> <expr> <Plug>d& idetools#delete_next('d&')
nnoremap <silent> <expr> <Plug>d# idetools#delete_next('d#')
nnoremap <silent> <expr> <Plug>d@ idetools#delete_next('d@')

" Similar to the above, but replicates :s/regex/sub/ behavior -- the substitute
" value is determined by what user enters in insert mode, and the cursor jumps
" to the next map after leaving insert mode
nnoremap <silent> <expr> c/ idetools#change_next('c/')
nnoremap <silent> <expr> c* idetools#change_next('c*')
nnoremap <silent> <expr> c& idetools#change_next('c&')
nnoremap <silent> <expr> c# idetools#change_next('c#')
nnoremap <silent> <expr> c@ idetools#change_next('c@')

" Maps as above, but this time delete or replace *all* occurrences
" Added a block to next_occurence function
nmap <silent> da/ :call idetools#delete_all('d/')<CR>
nmap <silent> da* :call idetools#delete_all('d*')<CR>
nmap <silent> da& :call idetools#delete_all('d&')<CR>
nmap <silent> da# :call idetools#delete_all('d#')<CR>
nmap <silent> da@ :call idetools#delete_all('d@')<CR>
nmap <silent> ca/ :let g:iterate_occurences = 1<CR>c/
nmap <silent> ca* :let g:iterate_occurences = 1<CR>c*
nmap <silent> ca& :let g:iterate_occurences = 1<CR>c&
nmap <silent> ca# :let g:iterate_occurences = 1<CR>c#
nmap <silent> ca@ :let g:iterate_occurences = 1<CR>c@
