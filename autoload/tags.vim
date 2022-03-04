"------------------------------------------------------------------------------"
" General tag processing utiltiies
"------------------------------------------------------------------------------"
" Strip leading and trailing whitespace
function! s:strip_whitespace(text) abort
  return substitute(a:text, '^\_s*\(.\{-}\)\_s*$', '\1', '')
endfunction

" Numerical sorting of tag lines
function! s:sort_by_line(tag1, tag2) abort
  let num1 = a:tag1[1]
  let num2 = a:tag2[1]
  return num1 - num2  " fits requirements
endfunc

" Alphabetical sorting of tag names
" From this page: https://vi.stackexchange.com/a/11237/8084
function! s:sort_by_name(tag1, tag2) abort
  let str1 = a:tag1[0]
  let str2 = a:tag2[0]
  return (str1 < str2 ? -1 : str1 == str2 ? 0 : 1)  " equality, lesser, and greater
endfunction

" Generate command-line exe that prints taglist to stdout
" We use ctags in number mode (i.e. return line number)
function! s:tag_command(...) abort
  let path = shellescape(expand('%:p'))
  let flags = a:0 ? a:1 : ''  " extra flags
  return
    \ 'ctags -f - --excmd=number ' . flags . ' ' . path
    \ . " 2>/dev/null | cut -d'\t' -f1,3-5 "
endfunction

" Tool that prints the result of the tag command
" Note: Just prints the output of the command
function! tags#print_tags() abort
  let cmd = s:tag_command() . " | tr -s '\t' | column -t -s '\t'"
  let tags = s:strip_whitespace(system(cmd))
  if len(tags) == 0
    echohl WarningMsg
    echom 'Warning: Tags not found or not available.'
    echohl None
  else
    echo "Tags for file '" . expand('%:p') . "':\n" . tags
  endif
endfunction

" Generate tags and parse them into list of lists
" Note: Multiple tags on same line is *very* common, try the below in a model
" src folder: for f in <pattern>; do echo $f:; ctags -f - -n $f | cut -d $'\t' -f3 | cut -d\; -f1 | sort -n | uniq -c | cut -d' ' -f4 | uniq; done
function! tags#update_tags() abort
  if index(g:tags_skip_filetypes, &filetype) != -1
    return
  endif
  let flags = getline(1) =~# '#!.*python[23]' ? '--language-force=python' : ''
  let tags = map(
    \ split(system(s:tag_command(flags) . " | sed 's/;\"\t/\t/g'"), '\n'),
    \ "split(v:val,'\t')"
    \ )
  if len(tags) == 0 || len(tags[0]) == 0  " no warning message for files without tags
    return
  endif
  let b:tags_by_name = sort(deepcopy(tags), 's:sort_by_name')  " sort alphabetically by *position 0* in the sub-arrays
  let b:tags_by_line = sort(deepcopy(tags), 's:sort_by_line')  " sort numerically by *position 1* in the sub-arrays
  let idx_nofilter = index(g:tags_nofilter_filetypes, &filetype)
  let kinds_scope = get(g:tags_scope_filetypes, &filetype, 'f')
  let b:scope_tags_by_line = filter(
    \ deepcopy(b:tags_by_line),
    \ 'v:val[2] =~# "[' . kinds_scope . ']" && '
    \ . '(' . idx_nofilter . ' != -1 || len(v:val) == 3)'
    \ )  " filter to top-level tags belonging to a certain category
endfunction

"-----------------------------------------------------------------------------"
" Tag navigation utiltiies
"-----------------------------------------------------------------------------"
" Get the current tag from a list of tags
" Note: This function searches exclusively (i.e. does not match the current line).
" So only start at current line when jumping, otherwise start one line down.
function! tags#close_tag(line, level, forward, circular) abort
  let bufvar = a:level ? 'b:scope_tags_by_line' : 'b:tags_by_line'
  if !exists(bufvar) || len(eval(bufvar)) == 0
    return []  " silent failure
  endif
  let lnum = a:line
  let tags = eval(bufvar)
  if a:circular && a:forward && lnum >= tags[-1][1]
    let idx = 0
  elseif a:circular && !a:forward && lnum <= tags[0][1]
    let idx = -1
  else
    for i in range(1, len(tags) - 1)  " in-between tags (endpoint inclusive)
      if a:forward && lnum >= tags[-i - 1][1]
        let idx = -i
        break
      endif
      if !a:forward && lnum <= tags[i][1]
        let idx = i - 1
        break
      endif
    endfor
    if !exists('idx')  " single tag or first or last tag
      let idx = a:forward ? 0 : -1
    endif
  endif
  return tags[idx]
endfunction

" Get the 'current' tag defined as the tag under the cursor or preceding
" Note: This is used with statusline
function! tags#print_tag(...) abort
  let tag = tags#close_tag(line('.') + 1, 0, 0, 0)
  let full = a:0 ? a:1 : 1  " print full tag
  if empty(tag)
    return ''
  elseif full && len(tag) == 4  " indicates extra information
    return tag[2] . ':' . substitute(tag[3], '^.*:', '', '')
  else
    return tag[2] . ':' . tag[0]
  endif
endfunction

" Get the line of the next or previous tag excluding under the cursor
" Note: This is used with bracket maps
function! tags#jump_tag(repeat, ...) abort
  let repeat = a:repeat == 0 ? 1 : a:repeat
  let args = copy(a:000)
  call add(args, 1)  " enable circular searching
  call insert(args, line('.'))  " start on current line
  for j in range(repeat)  " loop through repitition count
    let tag = call('tags#close_tag', args)
    if empty(tag)
      echohl WarningMsg
      echom 'Error: Tag jump failed.'
      echohl None
      return ''
    endif
    let args[0] = str2nr(tag[1])  " adjust line number
  endfor
  echom 'Tag: ' . tag[0]
  return tag[1] . 'G'  " return cmd since cannot move cursor inside autoload function
endfunction

" Return a list of strings for the an menu in the format:
" <line number>: name (type)
" <line number>: name (type, scope)
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
function! tags#list_tags() abort
  let tags = get(b:, 'tags_by_name', [])
  if empty(tags)
    echohl WarningMsg
    echom 'Warning: Tags not found or not available.'
    echohl None
    return []
  endif
  return map(
    \ deepcopy(tags),
    \ "printf('%4d', v:val[1]) . ': ' . v:val[0] . ' (' . join(v:val[2:], ', ') . ')'"
    \ )
endfunction

" Parse tags#list_tags user selection/get the line number
" We split by whitespace, get the line num (comes before the colon)
function! tags#select_tags(ctag) abort
  exe split(a:ctag, '\s\+')[0][:-2]
endfunction

"-----------------------------------------------------------------------------"
" Refactoring-related utilities
"-----------------------------------------------------------------------------"
" Count occurrences inside file
" See: https://vi.stackexchange.com/a/20661/8084
function! tags#count_occurence(pattern) range abort
  let range = a:firstline == a:lastline ? '%' : a:firstline . ',' . a:lastline
  let winview = winsaveview()
  redir => text
    silent exe range . 's/' . a:pattern . '//n'
  redir END
  call winrestview(winview)
  let num = matchstr(text, '\d\+')
  echom "Number of '" . a:pattern . "' occurences: " . num
endfunction

" Special function that jumps to next occurence automatically
" This is called when InsertLeave is triggered
" Warning: The @. register may contain keystrokes like <80>kb (i.e. backspace)
function! tags#change_repeat() abort
  if exists('g:iterate_occurences') && g:iterate_occurences
    call feedkeys(
      \ ':silent undo | let winview = winsaveview() '
      \ . '| keepjumps %s@' . getreg('/') . '@' . getreg('.') . '@ge '
      \ . "| call winrestview(winview)\<CR>"
      \ , 't'
      \ )
  elseif exists('g:inject_replace_occurences') && g:inject_replace_occurences
    silent! normal! n
    call repeat#set("\<Plug>replace_occurence")
  endif
  let g:iterate_occurences = 0
  let g:inject_replace_occurences = 0
endfunction

" Search within top level tags belonging to 'scope' kinds
" * Search func idea came from: http://vim.wikia.com/wiki/Search_in_current_function
" * Below is copied from: https://stackoverflow.com/a/597932/4970632
" * Note jedi-vim 'variable rename' is sketchy and fails; should do my own
"   renaming, and do it by confirming every single instance
function! tags#get_scope(...) abort
  let cline = a:0 ? a:1 : line('.')
  let ntext = 10  " text length
  if !exists('b:scope_tags_by_line') || len(b:scope_tags_by_line) == 0
    echohl WarningMsg
    echom 'Warning: Tags unavailable so cannot limit search scope.'
    echohl None
    return ''
  endif
  let ctaglines = map(deepcopy(b:scope_tags_by_line), 'v:val[1]')  " just pick out the line number
  let ctaglines = ctaglines + [line('$')]
  for i in range(0, len(ctaglines) - 2)
    if ctaglines[i] > cline || ctaglines[i + 1] <= cline  " must be line above start of next function
      continue
    endif
    let text = b:scope_tags_by_line[i][0]
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

" Set the last search register to some 'current pattern' under cursor, and
" return normal mode commands for highlighting that match
" Warning: For some reason set hlsearch does not work inside function so
" we must return command
function! tags#set_search(map) abort
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
    let @/ = tags#get_scope() . '\<' . expand('<cword>') . '\>\C'
    let motion = 'lb'
  elseif a:map =~# '@'
    let @/ = '\_s\@<=' . tags#get_scope() . expand('<cWORD>') . '\ze\_s\C'
    let motion = 'lB'
  elseif a:map =~# '/'
    " No-op
    exe
  else
    echohl WarningMsg
    echom 'Error: Unknown mapping "' . a:map . '" for vim-tags refactoring shortcut.'
    echohl None
    return motion
  endif
  return motion . ":setlocal hlsearch\<CR>"
endfunction

" Function that sets things up for maps that change text
function! tags#change_next(map) abort
  let action = tags#set_search(a:map)
  if action ==# ''
    return
  endif
  let g:inject_replace_occurences = 1
  return ":setlocal hlsearch\<CR>cgn"
endfunction

" Delete next match
function! tags#delete_next(map) abort
  let action = tags#set_search(a:map)
  if action ==# ''
    return
  endif
  return
    \ ":setlocal hlsearch\<CR>dgnn"
    \ . ':call repeat#set("\<Plug>' . a:map . '", ' . v:count . ")\<CR>"
endfunction

" Delete all of next matches
function! tags#delete_all(map) abort
  let action = tags#set_search(a:map)
  if action ==# ''
    return
  endif
  let winview = winsaveview()
  exe 'silent! keepjumps %s/' . @/ . '//ge'
  call winrestview(winview)
  echom 'Deleted all occurences.'
endfunction
