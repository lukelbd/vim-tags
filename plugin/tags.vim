"------------------------------------------------------------------------------
" Name: tags.vim
" Author: Luke Davis (lukelbd@gmail.com)
" Date:   2018-09-09
" Tools for working with ctags in vim.
" For c* and c# map origin, see:
" https://www.reddit.com/r/vim/comments/8k4p6v/what_are_your_best_mappings/
" For repeat.vim usage see:
" http://vimcasts.org/episodes/creating-repeatable-mappings-with-repeat-vim/
" * Each element of the b:tags_* variables is as follows:
"   Index 0: Tag name.
"   Index 1: Tag line number.
"   Index 2: Tag type.
"   Index 3: Tag parent (optional).
" * Re-define a few of the shift-number row keys to make them a bit more useful:
"   '*' is the current word, global
"   '&' is the current WORD, global
"   '#' is the current word, local
"   '@' is the current WORD, local
"------------------------------------------------------------------------------
call system('type ctags &>/dev/null')
if v:shell_error " exit code
  echohl WarningMsg
  echom 'Error: vim-tags requires the command-line tool ctags, not found.'
  echohl None
  finish
endif

" Initial stuff
set cpoptions+=d
augroup tags
  au!
  au InsertLeave * silent call tags#change_finish()  " finish change operation and set repeat
  au BufReadPost,BufWritePost * silent call tags#update_tags(expand('<afile>'))
augroup END

" List of per-file/per-filetype tag categories that we define as 'scope-delimiters',
" i.e. tags approximately denoting variable scope for code blocks. Default is 'f'
if !exists('g:tags_scope_kinds')
  let g:tags_scope_kinds = {}
endif

" List of per-file/per-filetype kind categories to skip. Useful to trim options (e.g.
" vim remappings) or to skip secondary or verbose options (e.g. tex frame subtitles).
if !exists('g:tags_skip_kinds')
  let g:tags_skip_kinds = {}
endif

" Files that we wish to ignore
if !exists('g:tags_skip_filetypes')
  let g:tags_skip_filetypes = ['diff', 'help', 'man', 'qf']
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

"-----------------------------------------------------------------------------
" Tag commands and maps
"-----------------------------------------------------------------------------
" Public commands
" Note: The tags#current_tag() is also used in vim-statusline plugin.
command! -bang -nargs=* ShowTags call tags#show_tags(<bang>0)
command! -bang -nargs=* ShowKinds call tags#show_kinds(<bang>0)
command! -bang -nargs=* UpdateTags call tags#update_tags(<bang>0)
command! CurrentTag echom 'Current tag: ' . tags#current_tag()

" Tag select maps
" Note: Must use :n instead of <expr> ngg so we can use <C-u> to discard count!
exe 'map ' . g:tags_jump_map . ' <Plug>TagsJump'
exe 'map <silent> ' . g:tags_forward_map . ' <Plug>TagsForwardAll'
exe 'map <silent> ' . g:tags_backward_map . ' <Plug>TagsBackwardAll'
exe 'map <silent> ' . g:tags_forward_top_map . ' <Plug>TagsForwardTop'
exe 'map <silent> ' . g:tags_backward_top_map . ' <Plug>TagsBackwardTop'
noremap <Plug>TagsJump <Cmd>call tags#select_tag()<CR>
noremap <expr> <silent> <Plug>TagsForwardAll tags#jump_tag(v:count, 0, 1)
noremap <expr> <silent> <Plug>TagsBackwardAll tags#jump_tag(v:count, 0, 0)
noremap <expr> <silent> <Plug>TagsForwardTop tags#jump_tag(v:count, 1, 1)
noremap <expr> <silent> <Plug>TagsBackwardTop tags#jump_tag(v:count, 1, 0)

"------------------------------------------------------------------------------
" Refactoring commands and maps
"------------------------------------------------------------------------------
" Public commands
command! -nargs=1 -range Match
  \ let @/ = <line1> == <line2> ? <q-args> :
  \ printf('\%%>%dl\%%<%dl', <line1> - 1, <line2> + 1) . <q-args>
  \ | call feedkeys(tags#count_match('/'))

" Global and local <cword>, global and local <cWORD>, local forward and backward,
" and current character searches. Also include match counts.
" character search, and forward and backward local scope search.
" Note: current character copied from https://stackoverflow.com/a/23323958/4970632
" Todo: Add scope-local matches? No because use those for other mappings.
noremap <expr> * tags#set_match('*', 1)
noremap <expr> & tags#set_match('&', 1)
noremap <expr> # tags#set_match('#', 1)
noremap <expr> @ tags#set_match('@', 1)
noremap <expr> ! tags#set_match('!', 1)
noremap <expr> g/ '/' . tags#set_scope()
noremap <expr> g? '?' . tags#set_scope()

" Normal mode mappings that replicate :s/regex/sub/ behavior and can be repeated
" with '.'. The substitution is determined from the text inserted by the user and
" the cursor automatically jumps to the next match. The 'a' mappings change all matches.
nmap c* <Plug>c*
nmap c& <Plug>c&
nmap c# <Plug>c#
nmap c@ <Plug>c@
nmap c/ <Plug>c/
nmap c? <Plug>c?
nmap ca* <Cmd>let g:change_all = 1<CR><Plug>c*
nmap ca& <Cmd>let g:change_all = 1<CR><Plug>c&
nmap ca# <Cmd>let g:change_all = 1<CR><Plug>c#
nmap ca@ <Cmd>let g:change_all = 1<CR><Plug>c@
nmap ca/ <Cmd>let g:change_all = 1<CR><Plug>c/
nmap ca? <Cmd>let g:change_all = 1<CR><Plug>c?
nnoremap <expr> <Plug>c* tags#change_next('c*')
nnoremap <expr> <Plug>c& tags#change_next('c&')
nnoremap <expr> <Plug>c# tags#change_next('c#')
nnoremap <expr> <Plug>c@ tags#change_next('c@')
nnoremap <expr> <Plug>c/ tags#change_next('c/')
nnoremap <expr> <Plug>c? tags#change_next('c?')
nnoremap <Plug>change_again <Cmd>call tags#change_again()<CR>

" Normal mode mappings that replicate :d/regex/ behavior and can be repeated
" with '.'. The cursuro automatically jumps to the next match. The 'a' mappings
" delete all matches.
nmap d* <Plug>d*
nmap d& <Plug>d&
nmap d# <Plug>d#
nmap d@ <Plug>d@
nmap d/ <Plug>d/
nmap d? <Plug>d?
nmap da* <Cmd>call tags#delete_all('d*')<CR>
nmap da& <Cmd>call tags#delete_all('d&')<CR>
nmap da# <Cmd>call tags#delete_all('d#')<CR>
nmap da@ <Cmd>call tags#delete_all('d@')<CR>
nmap da/ <Cmd>call tags#delete_all('d/')<CR>
nmap da? <Cmd>call tags#delete_all('d?')<CR>
nnoremap <expr> <Plug>d* tags#delete_next('d*')
nnoremap <expr> <Plug>d& tags#delete_next('d&')
nnoremap <expr> <Plug>d# tags#delete_next('d#')
nnoremap <expr> <Plug>d@ tags#delete_next('d@')
nnoremap <expr> <Plug>d/ tags#delete_next('d/')
nnoremap <expr> <Plug>d? tags#delete_next('d?')
