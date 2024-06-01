"------------------------------------------------------------------------------
" Tools for working with tags in vim. {{{1
"------------------------------------------------------------------------------
" Initial stuff {{{2
" Author: Luke Davis (lukelbd@gmail.com)
" This plugin works as a companion to project-wide tag navigation utilities.
" Supports jumping across open buffers and search and replace within buffers.
exe exists('g:loaded_tags') ? 'finish' : ''
let g:loaded_tags = 1
call system('type ctags &>/dev/null')
if v:shell_error | echoerr 'Error: ''ctags'' executable not found.' | finish | endif
silent! exe 'au! tags'
augroup vim_tags
  au!
  au InsertLeave * silent call tags#change_setup()  " finish change operation and set repeat
  au BufReadPost,BufWritePost * silent call tags#update_tags(expand('<afile>'))
augroup END

" Disable mappings {{{2
if !exists('g:tags_nomap')
  let g:tags_nomap = 0
endif
if !exists('g:tags_nomap_jumps')
  let g:tags_nomap_jumps = g:tags_nomap
endif
if !exists('g:tags_nomap_searches')
  let g:tags_nomap_searches = g:tags_nomap
endif

" Filetype settings {{{2
if !exists('g:tags_skip_filetypes')  " filetypes to fully skip
  let g:tags_skip_filetypes = ['diff', 'help', 'man', 'qf']
endif
if !exists('g:tags_skip_kinds')  " filetype kinds to fully skip
  let g:tags_skip_kinds = {}
endif
if !exists('g:tags_major_kinds')  " filetype kinds for search scope and [T navigation
  let g:tags_major_kinds = {}
endif
if !exists('g:tags_minor_kinds')  " filetype kinds skipped by [T and [t navigation
  let g:tags_minor_kinds = {}
endif

" Jump and tag stack options {{{2
if !exists('g:tags_keep_jumps')
  let g:tags_keep_jumps = 0
endif
if !exists('g:tags_keep_stack')
  let g:tags_keep_stack = 0
endif

" Tag jump map settings {{{2
if !exists('g:tags_cursor_map')
  let g:tags_cursor_map = '<Leader><CR>'
endif
if !exists('g:tags_bselect_map')
  let g:tags_bselect_map = '<Leader><Leader>'
endif
if !exists('g:tags_select_map')
  let g:tags_select_map = '<Leader><Tab>'
endif

" Tag navigation map settings {{{2
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

" Keyword navigation map settings {{{2
if !exists('g:tags_prev_local_map')
  let g:tags_prev_local_map = '[w'
endif
if !exists('g:tags_next_local_map')
  let g:tags_next_local_map = ']w'
endif
if !exists('g:tags_prev_global_map')
  let g:tags_prev_global_map = '[W'
endif
if !exists('g:tags_next_global_map')
  let g:tags_next_global_map = ']W'
endif

" Selection map settings {{{2
if !exists('g:tags_char_global_map')
  let g:tags_char_global_map = '!'
endif
if !exists('g:tags_word_global_map')
  let g:tags_word_global_map = '*'
endif
if !exists('g:tags_WORD_global_map')
  let g:tags_WORD_global_map = '&'
endif
if !exists('g:tags_word_local_map')
  let g:tags_word_local_map = '#'
endif
if !exists('g:tags_WORD_local_map')
  let g:tags_WORD_local_map = '@'
endif

"-----------------------------------------------------------------------------
" Commands and mappings {{{1
"-----------------------------------------------------------------------------
" Public commands {{{2
" Note: The tags#current_tag() function can also be used for statuslines
command! -bang -nargs=? -complete=tag Goto
  \ call tags#goto_name(<bang>0 + 1, <f-args>)
command! -bang -count=0 -nargs=* -complete=buffer Select
  \ call tags#select_tag(!empty(<q-args>) ? [<f-args>] : <bang>0 ? 2 : <count>)
command! -bang -nargs=* -complete=buffer ShowTags
  \ echo call('tags#table_tags', <bang>0 ? ['all'] : [<f-args>])
command! -bang -nargs=* -complete=buffer ShowKinds
  \ echo call('tags#table_kinds', <bang>0 ? ['all'] : [<f-args>])
command! -bang -nargs=* -complete=buffer UpdateTags
  \ call call('tags#update_tags', <bang>0 ? ['all'] : [<f-args>])
command! -nargs=? -complete=buffer UpdateKinds
  \ call call('tags#update_kinds', [])
command! -bang -nargs=* -range Search
  \ <line1>,<line2>call tags#set_search(<q-args>, <bang>0)

" Tag select maps {{{2
" Note: Must use :n instead of <expr> ngg so we can use <C-u> to discard count!
if !g:tags_nomap_jumps
  exe 'nmap ' . g:tags_bselect_map . ' <Plug>TagsBSelect'
  exe 'nmap ' . g:tags_select_map . ' <Plug>TagsGSelect'
  exe 'nmap ' . g:tags_cursor_map . ' <Plug>TagsCursor'
  exe 'map ' . g:tags_forward_map . ' <Plug>TagsForwardAll'
  exe 'map ' . g:tags_forward_top_map . ' <Plug>TagsForwardTop'
  exe 'map ' . g:tags_backward_map . ' <Plug>TagsBackwardAll'
  exe 'map ' . g:tags_backward_top_map . ' <Plug>TagsBackwardTop'
  exe 'map ' . g:tags_next_local_map . ' <Plug>TagsNextLocal'
  exe 'map ' . g:tags_next_global_map . ' <Plug>TagsNextGlobal'
  exe 'map ' . g:tags_prev_local_map . ' <Plug>TagsPrevLocal'
  exe 'map ' . g:tags_prev_global_map . ' <Plug>TagsPrevGlobal'
endif
nnoremap <Plug>TagsCursor <Cmd>call tags#goto_name(1)<CR>
nnoremap <Plug>TagsBSelect <Cmd>call tags#select_tag(0)<CR>
nnoremap <Plug>TagsGSelect <Cmd>call tags#select_tag(2)<CR>
noremap <Plug>TagsForwardAll <Cmd>call tags#next_tag(v:count1, 0)<CR>
noremap <Plug>TagsForwardTop <Cmd>call tags#next_tag(v:count1, 1)<CR>
noremap <Plug>TagsBackwardAll <Cmd>call tags#next_tag(-v:count1, 0)<CR>
noremap <Plug>TagsBackwardTop <Cmd>call tags#next_tag(-v:count1, 1)<CR>
noremap <Plug>TagsNextLocal <Cmd>call tags#next_word(v:count1, 0)<CR>
noremap <Plug>TagsNextGlobal <Cmd>call tags#next_word(v:count1, 1)<CR>
noremap <Plug>TagsPrevLocal <Cmd>call tags#next_word(-v:count1, 0)<CR>
noremap <Plug>TagsNextGlobal <Cmd>call tags#next_word(v:count1, 1)<CR>

" Current word searches {{{2
" Includes current character, global and local <cword>, global and local <cWORD>
" Note: Current character copied from https://stackoverflow.com/a/23323958/4970632
" Todo: Add scope-local matches? No because use those for other mappings.
if !g:tags_nomap_searches
  if !hasmapto('tags#set_search('''', 1)')  " avoid overwriting
    noremap g/ <Cmd>call tags#set_search('', 1)<CR><Cmd>call feedkeys(empty(@/) ? '' : '/' . @/, 'n')<CR>
    noremap g? <Cmd>call tags#set_search('', 1)<CR><Cmd>call feedkeys(empty(@/) ? '' : '?' . @/, 'n')<CR>
  endif
  exe 'noremap ' . g:tags_char_global_map . ' <Cmd>call tags#set_search(0, 0, 1)<CR>'
  exe 'noremap ' . g:tags_word_global_map . ' <Cmd>call tags#set_search(1, 0, 1)<CR>'
  exe 'noremap ' . g:tags_WORD_global_map . ' <Cmd>call tags#set_search(2, 0, 1)<CR>'
  exe 'noremap ' . g:tags_word_local_map . ' <Cmd>call tags#set_search(1, 1, 1)<CR>'
  exe 'noremap ' . g:tags_WORD_local_map . ' <Cmd>call tags#set_search(2, 1, 1)<CR>'
endif

" Current word search-and-replace {{{2
" These replicate :s/regex/sub/ behavior and can be repeated with '.'. The replacement
" text is determined from the text typed by the user until the next InsertLeave event
" and the cursor jumps to the next match automatically. The 'a' maps change all matches
if !g:tags_nomap_searches
  if !hasmapto('TagsChangeMatch')  " avoid overwriting
    nmap c/ <Plug>TagsChangeMatchNext
    nmap c? <Plug>TagsChangeMatchPrev
    nmap ca/ <Plug>TagsChangeMatchesNext
    nmap ca? <Plug>TagsChangeMatchesPrev
  endif
  exe 'nmap c' . g:tags_char_global_map . ' <Plug>TagsChangeCharGlobal'
  exe 'nmap c' . g:tags_word_global_map . ' <Plug>TagsChangeWordGlobal'
  exe 'nmap c' . g:tags_WORD_global_map . ' <Plug>TagsChangeWORDGlobal'
  exe 'nmap c' . g:tags_word_local_map . ' <Plug>TagsChangeWordLocal'
  exe 'nmap c' . g:tags_WORD_local_map . ' <Plug>TagsChangeWORDLocal'
  exe 'nmap ca' . g:tags_char_global_map . ' <Plug>TagsChangeCharsGlobal'
  exe 'nmap ca' . g:tags_word_global_map . ' <Plug>TagsChangeWordsGlobal'
  exe 'nmap ca' . g:tags_WORD_global_map . ' <Plug>TagsChangeWORDSGlobal'
  exe 'nmap ca' . g:tags_word_local_map . ' <Plug>TagsChangeWordsLocal'
  exe 'nmap ca' . g:tags_WORD_local_map . ' <Plug>TagsChangeWORDSLocal'
endif
nnoremap <Plug>TagsChangeAll <Cmd>call tags#change_all()<CR>
nnoremap <Plug>TagsChangeAgain <Cmd>call tags#change_again()<CR>
nnoremap <Plug>TagsChangeMatchNext <Cmd>call tags#change_next(@/, 0, 0)<CR>
nnoremap <Plug>TagsChangeMatchPrev <Cmd>call tags#change_next(@/, 0, 1)<CR>
nnoremap <Plug>TagsChangeMatchesNext <Cmd>call tags#change_next(@/, 1, 0)<CR>
nnoremap <Plug>TagsChangeMatchesPrev <Cmd>call tags#change_next(@/, 1, 1)<CR>
nnoremap <Plug>TagsChangeCharGlobal <Cmd>call tags#change_next(0, 0, 0)<CR>
nnoremap <Plug>TagsChangeWordGlobal <Cmd>call tags#change_next(1, 0, 0)<CR>
nnoremap <Plug>TagsChangeWORDGlobal <Cmd>call tags#change_next(2, 0, 0)<CR>
nnoremap <Plug>TagsChangeWordLocal <Cmd>call tags#change_next(1, 0, 1)<CR>
nnoremap <Plug>TagsChangeWORDLocal <Cmd>call tags#change_next(2, 0, 1)<CR>
nnoremap <Plug>TagsChangeCharsGlobal <Cmd>call tags#change_next(0, 1, 0)<CR>
nnoremap <Plug>TagsChangeWordsGlobal <Cmd>call tags#change_next(1, 1, 0)<CR>
nnoremap <Plug>TagsChangeWORDSGlobal <Cmd>call tags#change_next(2, 1, 0)<CR>
nnoremap <Plug>TagsChangeWordsLocal <Cmd>call tags#change_next(1, 1, 1)<CR>
nnoremap <Plug>TagsChangeWORDSLocal <Cmd>call tags#change_next(2, 1, 1)<CR>

" Current word deltion {{{2
" Normal mode mappings that replicate :d/regex/ behavior and can be repeated with '.'.
" Cursor automatically jumps to the next match. The 'a' mappings delete all matches.
if !g:tags_nomap_searches
  if !hasmapto('TagsDeleteMatch')
    nmap d/ <Plug>TagsDeleteMatchNext
    nmap d? <Plug>TagsDeleteMatchPrev
    nmap da/ <Plug>TagsDeleteMatchesNext
    nmap da? <Plug>TagsDeleteMatchesPrev
  endif
  exe 'nmap d' . g:tags_char_global_map . ' <Plug>TagsDeleteCharGlobal'
  exe 'nmap d' . g:tags_word_global_map . ' <Plug>TagsDeleteWordGlobal'
  exe 'nmap d' . g:tags_WORD_global_map . ' <Plug>TagsDeleteWORDGlobal'
  exe 'nmap d' . g:tags_word_local_map . ' <Plug>TagsDeleteWordLocal'
  exe 'nmap d' . g:tags_WORD_local_map . ' <Plug>TagsDeleteWORDLocal'
  exe 'nmap da' . g:tags_char_global_map . ' <Plug>TagsDeleteCharsGlobal'
  exe 'nmap da' . g:tags_word_global_map . ' <Plug>TagsDeleteWordsGlobal'
  exe 'nmap da' . g:tags_WORD_global_map . ' <Plug>TagsDeleteWORDSGlobal'
  exe 'nmap da' . g:tags_word_local_map . ' <Plug>TagsDeleteWordsLocal'
  exe 'nmap da' . g:tags_WORD_local_map . ' <Plug>TagsDeleteWORDSLocal'
endif
nnoremap <Plug>TagsDeleteMatchNext <Cmd>call tags#delete_next(@/, 0, 0)<CR>
nnoremap <Plug>TagsDeleteMatchPrev <Cmd>call tags#delete_next(@/, 0, 1)<CR>
nnoremap <Plug>TagsDeleteMatchesNext <Cmd>call tags#delete_next(@/, 1, 0)<CR>
nnoremap <Plug>TagsDeleteMatchesPrev <Cmd>call tags#delete_next(@/, 1, 1)<CR>
nnoremap <Plug>TagsDeleteCharGlobal <Cmd>call tags#delete_next(0, 0, 0)<CR>
nnoremap <Plug>TagsDeleteWordGlobal <Cmd>call tags#delete_next(1, 0, 0)<CR>
nnoremap <Plug>TagsDeleteWORDGlobal <Cmd>call tags#delete_next(1, 0, 0)<CR>
nnoremap <Plug>TagsDeleteWordLocal <Cmd>call tags#delete_next(1, 0, 1)<CR>
nnoremap <Plug>TagsDeleteWORDLocal <Cmd>call tags#delete_next(2, 0, 1)<CR>
nnoremap <Plug>TagsDeleteCharsGlobal <Cmd>call tags#delete_next(0, 1, 0)<CR>
nnoremap <Plug>TagsDeleteWordsGlobal <Cmd>call tags#delete_next(1, 1, 0)<CR>
nnoremap <Plug>TagsDeleteWORDSGlobal <Cmd>call tags#delete_next(2, 1, 0)<CR>
nnoremap <Plug>TagsDeleteWordsLocal <Cmd>call tags#delete_next(1, 1, 1)<CR>
nnoremap <Plug>TagsDeleteWORDSLocal <Cmd>call tags#delete_next(2, 1, 1)<CR>
