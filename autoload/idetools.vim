"------------------------------------------------------------------------------"
" Ctag functions
"------------------------------------------------------------------------------"
" Generate command-line exe that prints taglist to stdout
" We call ctags in number mode (i.e. return line number)
function! s:ctagcmd(...) abort
  let flags = (a:0 ? a:1 : '') " extra flags
  return 'ctags ' . flags . ' ' . shellescape(expand('%:p')) . ' 2>/dev/null '
   \ . " | cut -d '\t' -f1,3-5 "
endfunction
" Default sorting is always alphabetical, with type coercion
function! s:linesort(tag1, tag2) abort
  let num1 = a:tag1[1]
  let num2 = a:tag2[1]
  return num1 - num2 " fits requirements
endfunc
" From this page: https://vi.stackexchange.com/a/11237/8084
function! s:alphsort(tag1, tag2) abort
  let str1 = a:tag1[0]
  let str2 = a:tag2[0]
  return (str1 < str2 ? -1 : str1 == str2 ? 0 : 1) " equality, lesser, and greater
endfunction

" Tool that provides a nice display of tags
" Used to show the regexes instead of -n mode; the below sed was used to parse them nicely
" | tr -s ' ' | sed '".'s$/\(.\{0,60\}\).*/;"$/\1.../$'."' "
function! idetools#ctags_display() abort
  exe '!clear; ' . s:ctagcmd()
   \ . ' | tr -s ''\t'' | column -t -s ''\t'' | less'
endfunction

" Generate list of strings for fzf menu, looks like:
" <line number>: name (type)
" <line number>: name (type, scope)
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
function! idetools#ctagmenu(ctaglist) abort " returns nicely formatted string
  return map(deepcopy(a:ctaglist),
    \ 'printf("%4d", v:val[1]) . ": " . v:val[0] . " (" . join(v:val[2:],", ") . ")"')
endfunction
" Parse user menu selection/get the line number
" We split by whitespace, get the line num (comes before the colon)
function! idetools#ctagselect(ctag) abort
  exe split(a:ctag, '\s\+')[0][:-2]
endfunction

" Generate ctags and parses them into list of lists
" Note multiple tags on same line is *very* common, try the below in a model
" src folder: for f in <pattern>; do echo $f:; ctags -f - -n $f | cut -d $'\t' -f3 | cut -d\; -f1 | sort -n | uniq -c | cut -d' ' -f4 | uniq; done
function! idetools#ctags_read() abort
  " First get simple list of lists; tag properties sorted alphabetically by
  " identifier, and numerically by line number
  " * To filter by category, use: filter(b:ctags, 'v:val[2]=="<category>"')
  " * First bail out if filetype is bad
  if index(g:idetools_filetypes_skip, &ft) != -1
    return
  endif
  let flags = (getline(1) =~# '#!.*python[23]' ? '--language-force=python' : '')
  " Call system command
  " Warning: In MacVim, instead what gets called is:
  " /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ctags"
  " and then for some reason ctags can't accept -n flag or --excmd=number flag.
  " Warning: To test if ctags worked, want exit status of *first* command in pipeline (i.e. ctags)
  " but instead we get cut/sed statuses. If ctags returns error
  let ctags = map(split(system(s:ctagcmd(flags) . " | sed 's/;\"\t/\t/g'"), '\n'), "split(v:val,'\t')")
  if len(ctags) == 0 || len(ctags[0]) == 0 " don't want warning message for files without tags!
    return
  endif
  let b:ctags_alph = sort(deepcopy(ctags), 's:alphsort') " sort numerically by *position 1* in the sub-arrays
  let b:ctags_line = sort(deepcopy(ctags), 's:linesort') " sort alphabetically by *position 0* in the sub-arrays
  " Next filter the tags sorted by line to include only a few limited categories
  " Will also filter to pick only ***top-level*** items (i.e. tags with global scope)
  if has_key(g:idetools_filetypes_top_tags, &ft)
    let cats = g:idetools_filetypes_top_tags[&ft]
  else
    let cats = g:idetools_filetypes_top_tags['default']
  endif
  let b:ctags_line_top = filter(deepcopy(b:ctags_line),
    \ 'v:val[2] =~ "[' . cats . ']" && ('
    \ . index(g:idetools_filetypes_all_tags, &ft) . ' != -1 || len(v:val) == 3)')
endfunction

" Jump between top level ctags
" Warning: Ctag lines are stored as strings and only get implicitly converted
" to numbers on comparison with other numbers, so need to make sure in loop
" that 'lnum' is always a number!
function! idetools#ctagjump(forward, repeat, top) abort
  let ctags_name = a:top ? 'b:ctags_line_top' : 'b:ctags_line'
  if !exists(ctags_name) || len(eval(ctags_name)) == 0
    echohl WarningMsg
    echom 'Warning: Bracket jump impossible because ctags unavailable.'
    echohl None
    return line('.') " stay on current line if failed
  endif
  let lnum = line('.')
  let repeat = (a:repeat == 0 ? 1 : a:repeat)
  let ctags_list = eval(ctags_name)
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
  echom 'Tag: ' . ltag
  return lnum
endfunction

"-----------------------------------------------------------------------------"
" Refactoring tools
"-----------------------------------------------------------------------------"
" Search within top level ctags boundaries
" * Search func idea came from: http://vim.wikia.com/wiki/Search_in_current_function
" * Below is copied from: https://stackoverflow.com/a/597932/4970632
" * Note jedi-vim 'variable rename' is sketchy and fails; should do my own
"   renaming, and do it by confirming every single instance
function! idetools#get_scope() abort
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
function! idetools#change_repeat() abort
  if exists('g:iterate_occurences') && g:iterate_occurences
    let winview = winsaveview()
    exe 'silent! keepjumps %s/' . @/ . '/' . @. . '/g'
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
function! idetools#set_search(map) abort
  let motion = ''
  if a:map =~# '!'
    let string = getline('.')
    if len(string) == 0
      let @/ = "\n"
    else
      let @/ = escape(string[col('.') - 1], '/\')
    endif
  elseif a:map =~# '\*'
    let @/ = '\<'.expand('<cword>').'\>\C'
    let motion = 'lb'
  elseif a:map =~# '&'
    let @/ = '\_s\@<='.expand('<cWORD>').'\ze\_s\C'
    let motion = 'lB'
  elseif a:map =~# '#'
    let @/ = idetools#get_scope().'\<'.expand('<cword>').'\>\C'
    let motion = 'lb'
  elseif a:map =~# '@'
    let @/ = '\_s\@<='.idetools#get_scope().expand('<cWORD>').'\ze\_s\C'
    let motion = 'lB'
  elseif a:map !~# '/'
    echohl WarningMsg
    echom 'Error: Unknown mapping "' . a:map . '" for vim-idetools refactoring shortcut.'
    echohl None
    return motion
  endif
  return motion . ":setlocal hlsearch\<CR>"
endfunction

" Function that sets things up for maps that change text
function! idetools#change_next(map) abort
  let action = idetools#set_search(a:map)
  if action ==# ''
    return
  endif
  let g:inject_replace_occurences = 1
  return ":setlocal hlsearch\<CR>cgn"
endfunction

" Delete next match
function! idetools#delete_next(map) abort
  let action = idetools#set_search(a:map)
  if action ==# ''
    return
  endif
  return ":setlocal hlsearch\<CR>dgnn"
    \ . ':call repeat#set("\<Plug>' . a:map . '", ' . v:count . ")\<CR>"
endfunction

" Delete all of next matches
function! idetools#delete_all(map) abort
  let action = idetools#set_search(a:map)
  if action ==# ''
    return
  endif
  let winview = winsaveview()
  exe 'silent! keepjumps %s/' . @/ . '//ge'
  call winrestview(winview)
  echom 'Deleted all occurences.'
endfunction

