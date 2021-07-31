"------------------------------------------------------------------------------"
" Ctag functions
"------------------------------------------------------------------------------"
" Strip leading and trailing whitespace
function! s:strip_whitespace(text) abort
  return substitute(a:text, '^\_s*\(.\{-}\)\_s*$', '\1', '')
endfunction

" Default sorting is always alphabetical, with type coercion
function! s:sort_line(tag1, tag2) abort
  let num1 = a:tag1[1]
  let num2 = a:tag2[1]
  return num1 - num2 " fits requirements
endfunc

" From this page: https://vi.stackexchange.com/a/11237/8084
function! s:sort_alph(tag1, tag2) abort
  let str1 = a:tag1[0]
  let str2 = a:tag2[0]
  return (str1 < str2 ? -1 : str1 == str2 ? 0 : 1) " equality, lesser, and greater
endfunction

" Generate command-line exe that prints taglist to stdout
" We call ctags in number mode (i.e. return line number)
function! s:ctags_cmd(...) abort
  let path = shellescape(expand('%:p'))
  let flags = (a:0 ? a:1 : '')  " extra flags
  return
    \ 'ctags -f - --excmd=number ' . flags . ' ' . path
    \ . " 2>/dev/null | cut -d'\t' -f1,3-5 "
endfunction

" Tool that provides a nice display of tags
function! tagtools#ctags_show() abort
  let cmd = s:ctags_cmd() . " | tr -s '\t' | column -t -s '\t'"
  let ctags = s:strip_whitespace(system(cmd))
  if len(ctags) == 0
    echohl WarningMsg
    echom "Warning: No ctags found for file '" . expand('%:p') . "'."
    echohl None
  else
    echo "Ctags for file '" . expand('%:p') . "':\n" . ctags
  endif
endfunction

" Parse user menu selection/get the line number
" We split by whitespace, get the line num (comes before the colon)
function! tagtools#ctags_select(ctag) abort
  exe split(a:ctag, '\s\+')[0][:-2]
endfunction

" Generate list of strings for fzf menu, looks like:
" <line number>: name (type)
" <line number>: name (type, scope)
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
function! tagtools#ctags_menu() abort
  let ctags = get(b:, 'ctags_alph', [])
  if empty(ctags)
    echohl WarningMsg
    echom 'Warning: Ctags unavailable.'
    echohl None
    return []
  endif
  return map(
    \ deepcopy(ctags),
    \ "printf('%4d', v:val[1]) . ': ' . v:val[0] . ' (' . join(v:val[2:], ', ') . ')'"
    \ )
endfunction

" Generate ctags and parses them into list of lists
" Note multiple tags on same line is *very* common, try the below in a model
" src folder: for f in <pattern>; do echo $f:; ctags -f - -n $f | cut -d $'\t' -f3 | cut -d\; -f1 | sort -n | uniq -c | cut -d' ' -f4 | uniq; done
function! tagtools#ctags_update() abort
  " First get simple list of lists. Tag properties sorted alphabetically by
  " identifier, and numerically by line number.
  " Warning: To test if ctags worked, want exit status of *first* command in pipeline (i.e. ctags)
  " but instead we get cut/sed statuses. If ctags returns error
  if index(g:tagtools_filetypes_skip, &filetype) != -1
    return
  endif
  let flags = getline(1) =~# '#!.*python[23]' ? '--language-force=python' : ''
  let ctags = map(
    \ split(system(s:ctags_cmd(flags) . " | sed 's/;\"\t/\t/g'"), '\n'),
    \ "split(v:val,'\t')"
    \ )
  if len(ctags) == 0 || len(ctags[0]) == 0  " don't want warning message for files without tags!
    return
  endif
  let b:ctags_alph = sort(deepcopy(ctags), 's:sort_alph')  " sort numerically by *position 1* in the sub-arrays
  let b:ctags_line = sort(deepcopy(ctags), 's:sort_line')  " sort alphabetically by *position 0* in the sub-arrays

  " Next filter the tags sorted by line to include only a few limited categories
  " Will also filter to pick only ***top-level*** items (i.e. tags with global scope)
  let cats = get(g:tagtools_filetypes_top_tags, &filetype, 'f')
  let b:ctags_line_top = filter(
    \ deepcopy(b:ctags_line),
    \ 'v:val[2] =~ "[' . cats . ']" && ('
    \ . index(g:tagtools_filetypes_all_tags, &filetype)
    \ . ' != -1 || len(v:val) == 3'
    \ . ')'
    \ )
endfunction

" Jump between top level ctags
" Warning: Ctag lines are stored as strings and only get implicitly converted
" to numbers on comparison with other numbers, so need to make sure in loop
" that 'lnum' is always a number!
function! tagtools#ctag_jump(forward, repeat, top) abort
  let ctags_name = a:top ? 'b:ctags_line_top' : 'b:ctags_line'
  if !exists(ctags_name) || len(eval(ctags_name)) == 0
    echohl WarningMsg
    echom 'Warning: Ctags unavailable.'
    echohl None
    return line('.')  " stay on current line if failed
  endif
  let lnum = line('.')
  let repeat = a:repeat == 0 ? 1 : a:repeat
  let ctags_list = eval(ctags_name)

  " Loop through repitition
  for j in range(repeat)
    " Edge cases; at bottom or top of document
    if lnum < ctags_list[0][1] || lnum > ctags_list[-1][1]
      let idx = (a:forward ? 0 : -1)
    " Extra case not handled in main loop
    elseif lnum == ctags_list[-1][1]
      let idx = (a:forward ? 0 : -2)
    " Main loop
    else
      for i in range(len(ctags_list) - 1)
        if lnum == ctags_list[i][1]
          let idx = (a:forward ? i + 1 : i - 1)
          break
        elseif lnum > ctags_list[i][1] && lnum < ctags_list[i + 1][1]
          let idx = (a:forward ? i + 1 : i)
          break
        endif
        if i == len(ctags_list) - 1
          echohl WarningMsg
          echom 'Error: Bracket jump failed.'
          echohl None
          return line('.')
        endif
      endfor
    endif
    let ltag = ctags_list[idx][0]
    let lnum = str2nr(ctags_list[idx][1])
  endfor

  " Cannot move cursor inside autoload function (???)
  " Instead return command for jumping to line
  echom 'Tag: ' . ltag
  return lnum . 'G'
endfunction

"-----------------------------------------------------------------------------"
" Refactoring tools
"-----------------------------------------------------------------------------"
" Search within top level ctags boundaries
" * Search func idea came from: http://vim.wikia.com/wiki/Search_in_current_function
" * Below is copied from: https://stackoverflow.com/a/597932/4970632
" * Note jedi-vim 'variable rename' is sketchy and fails; should do my own
"   renaming, and do it by confirming every single instance
function! tagtools#get_scope() abort
  let ntext = 10 " text length
  if !exists('b:ctags_line_top') || len(b:ctags_line_top) == 0
    echohl WarningMsg
    echom 'Warning: Tags unavailable so cannot limit search scope.'
    echohl None
    return ''
  endif
  let init = line('.')
  let ctaglines = map(deepcopy(b:ctags_line_top), 'v:val[1]') " just pick out the line number
  let ctaglines = ctaglines + [line('$')]
  for i in range(0, len(ctaglines) - 2)
    if ctaglines[i] > init || ctaglines[i + 1] <= init " must be line above start of next function
      continue
    endif
    let text = b:ctags_line_top[i][0]
    if len(text) >= ntext
      let text = text[:ntext - 1] . '...'
    endif
    echom 'Scopesearch selected line ' . ctaglines[i] . ' (' . text . ') to ' . (ctaglines[i + 1] - 1) . '.'
    return printf('\%%>%dl\%%<%dl', ctaglines[i] - 1, ctaglines[i + 1])
  endfor
  echohl WarningMsg
  echom 'Warning: Failed to limit search scope.'
  echohl None
  return ''
endfunction

" Special function that jumps to next occurence automatically
" This is called when InsertLeave is triggered
function! tagtools#change_repeat() abort
  if exists('g:iterate_occurences') && g:iterate_occurences
    let winview = winsaveview()
    exe 'silent! keepjumps %s@' . @/ . '@' . escape(@., '\') . '@g'
    call winrestview(winview)
    echom 'Replaced all occurences.'
  elseif exists('g:inject_replace_occurences') && g:inject_replace_occurences
    silent! normal! n
    call repeat#set("\<Plug>replace_occurence")
  endif
  let g:iterate_occurences = 0
  let g:inject_replace_occurences = 0
endfunction

" Set the last search register to some 'current pattern' under cursor, and
" return normal mode commands for highlighting that match
" Warning: For some reason set hlsearch does not work inside function so
" we must return command
function! tagtools#set_search(map) abort
  let motion = ''
  if a:map =~# '!'
    let string = getline('.')
    if len(string) == 0
      let @/ = "\n"
    else
      let @/ = escape(string[col('.') - 1], '/\')
    endif
  elseif a:map =~# '\*'
    let @/ = '\<' . expand('<cword>') . '\>\C'
    let motion = 'lb'
  elseif a:map =~# '&'
    let @/ = '\_s\@<=' . expand('<cWORD>') . '\ze\_s\C'
    let motion = 'lB'
  elseif a:map =~# '#'
    let @/ = tagtools#get_scope() . '\<' . expand('<cword>') . '\>\C'
    let motion = 'lb'
  elseif a:map =~# '@'
    let @/ = '\_s\@<=' . tagtools#get_scope() . expand('<cWORD>') . '\ze\_s\C'
    let motion = 'lB'
  elseif a:map =~# '/'
    " No-op
    exe
  else
    echohl WarningMsg
    echom 'Error: Unknown mapping "' . a:map . '" for vim-tagtools refactoring shortcut.'
    echohl None
    return motion
  endif
  return motion . ":setlocal hlsearch\<CR>"
endfunction

" Function that sets things up for maps that change text
function! tagtools#change_next(map) abort
  let action = tagtools#set_search(a:map)
  if action ==# ''
    return
  endif
  let g:inject_replace_occurences = 1
  return ":setlocal hlsearch\<CR>cgn"
endfunction

" Delete next match
function! tagtools#delete_next(map) abort
  let action = tagtools#set_search(a:map)
  if action ==# ''
    return
  endif
  return
    \ ":setlocal hlsearch\<CR>dgnn"
    \ . ':call repeat#set("\<Plug>' . a:map . '", ' . v:count . ")\<CR>"
endfunction

" Delete all of next matches
function! tagtools#delete_all(map) abort
  let action = tagtools#set_search(a:map)
  if action ==# ''
    return
  endif
  let winview = winsaveview()
  exe 'silent! keepjumps %s/' . @/ . '//ge'
  call winrestview(winview)
  echom 'Deleted all occurences.'
endfunction

