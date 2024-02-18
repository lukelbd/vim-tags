"------------------------------------------------------------------------------
" General tag processing utiltiies
" Warning: Encountered strange error where naming .vim/autoload file same as
" vim-tags/autoload file or naming the latter to tags.vim at all caused an autocmd
" BufRead error on startup. Was impossible to diagnose so just use alternate names.
"------------------------------------------------------------------------------
" Global tags command
" Note: Keep in sync with g:fzf_tags_command
scriptencoding utf-8
let s:tags_command = 'ctags -f - --excmd=number'
let s:regex_magic = '[]\/.*$~'

" Numerical sorting of tag lines
function! s:sort_by_line(tag1, tag2) abort
  let num1 = a:tag1[1]
  let num2 = a:tag2[1]
  return num1 - num2  " >0 if greater, 0 if equal, <0 if lesser
endfunc

" Alphabetical sorting of tag names
function! s:sort_by_name(tag1, tag2) abort
  let str1 = a:tag1[0]
  let str2 = a:tag2[0]
  return str1 <# str2 ? -1 : str1 ==# str2 ? 0 : 1  " equality, lesser, and greater
endfunction

" Return command-line executable that prints tags to stdout
" Note: Output should be in number mode (i.e. shows line number instead of full line)
function! s:tags_command(path, ...) abort
  let path = shellescape(expand(fnamemodify(a:path, ':p')))
  let cmd = join(a:000, ' ') . ' ' . path
  return s:tags_command . ' ' . cmd . ' 2>/dev/null' . " | cut -d'\t' -f1,3-5"
endfunction

" Return tags parsed and sorted by name and line
" Note: This is used for buffer variables and unopened :ShowTags path(s)
function! s:tags_parsed(path) abort
  let type = getbufvar(bufnr(a:path), '&filetype')  " possibly empty string
  let skip = get(g:tags_skip_kinds, type, '@')  " default dummy character
  if index(g:tags_skip_filetypes, type) >= 0 | return [[], []] | endif
  let flags = getline(1) =~# '#!.*python[23]' ? '--language-force=python' : ''
  let items = system(s:tags_command(a:path, flags) . " | sed 's/;\"\t/\t/g'")
  let items = map(split(items, '\n'), "split(v:val, '\t')")
  let items = filter(items, "v:val[2] !~# '[" . skip . "]'")
  let items = [sort(items, 's:sort_by_line'), sort(deepcopy(items), 's:sort_by_name')]
  return items
endfunction

" Return buffers by most recent
" Note: Here try to detect tabs that were either accessed within session or were only
" loaded on startup by finding the minimum access time that differs from neighbors.
function! tags#buffers_recent(...) abort
  let bufs = map(getbufinfo(), {idx, val -> [val['bufnr'], val['lastused']]})
  let mintime = a:0 ? a:1 : 0
  if a:0 == 0  " auto-detect threshold for sorting
    for btime in sort(map(copy(bufs), 'v:val[1]'))  " approximate loading time
      if mintime && btime - mintime > 10 | break | endif | let mintime = btime
    endfor
  endif
  let recent = []  " buffers used after mintime
  for [bnr, btime] in bufs
    if btime > mintime
      call add(recent, [bnr, btime])
    endif
  endfor
  let recent = sort(recent, {val1, val2 -> val2[1] - val1[1]})
  let recent = map(recent, 'v:val[0]')
  return recent
endfunction

" Return [tab, buffer] number pairs in helpful order
" Note: This is used to sort tag files by recent use or else tab adjacency
" when displaying tags in window or running multi-file fzf selection.
function! tags#buffer_paths() abort
  let tnr = tabpagenr()  " active tab
  let tleft = tnr
  let tright = tnr - 1  " initial value
  let pairs = []  " [tnr, bnr] pairs
  while 1
    if tnr == tleft
      let tright += 1 | let tnr = tright
    else
      let tleft -= 1 | let tnr = tleft
    endif
    if tleft < 1 && tright > tabpagenr('$')
      break
    elseif tnr == tright && tright > tabpagenr('$')
      continue  " possibly more tabs to the left
    elseif tnr == tleft && tleft < 1
      continue  " possibly more tabs to the right
    endif
    for bnr in tabpagebuflist(tnr)
      let path = expand('#' . bnr . ':p')
      let type = getbufvar(bnr, '&filetype')
      if filereadable(path) && index(g:tags_skip_filetypes, type) == -1
        call add(pairs, [tnr, bnr]) | break  " one entry per tab
      endif
    endfor
  endwhile
  let idxs = []
  let temporal = []  " sorted by access time
  let physical = []  " ordered by adjacency
  for bnr in tags#buffers_recent()
    for idx in range(len(pairs))
      let [tnr, inr] = pairs[idx]
      if inr == bnr
        let path = expand('#' . bnr . ':p')
        call add(idxs, idx)
        call add(temporal, [tnr, path])
      endif
    endfor
  endfor
  for idx in range(len(pairs))
    if index(idxs, idx) == -1
      let [tnr, bnr] = pairs[idx]
      let path = expand('#' . bnr . ':p')
      call add(physical, [tnr, path])
    endif
  endfor
  let pairs = temporal + physical
  return pairs  " prefer most recently visited then closest
endfunction

" Generate tags and parse them into list of lists
" Note: Files open in multiple windows use the same buffer number and same variables.
function! tags#update_tags(...) abort
  let global = a:0 ? a:1 : 0
  if global  " global paths
    let paths = map(tags#buffer_paths(), 'v:val[1]')
  else  " local path
    let paths = [expand('%:p')]
  endif
  for path in paths
    let bnr = bufnr(path)  " buffer unique to path
    let time = getbufvar(bnr, 'tags_update_time', 0)
    let ftype = getbufvar(bnr, '&filetype')
    if getftime(path) < time | continue | endif
    let items = s:tags_parsed(path)  " items by line and name
    call setbufvar(bnr, 'tags_by_line', items[0])
    call setbufvar(bnr, 'tags_by_name', items[1])
    call setbufvar(bnr, 'tags_update_time', localtime())
  endfor
endfunction

"-----------------------------------------------------------------------------
" Tag display utiltiies
"-----------------------------------------------------------------------------
" Show the current file kinds
" Note: Ctags cannot show specific filetype kinds so instead filter '--list-kinds=all'
" Note: See https://stackoverflow.com/a/71334/4970632 for difference between \r and \n
function! tags#table_kinds(...) abort
  if index(a:000, 'all') >= 0  " all open filetypes
    let flag = 'all'
    let types = uniq(map(tags#buffer_paths(), "getbufvar(v:val[1], '&filetype')"))
    let label = 'all buffer filetypes'
  elseif a:0  " input filetype(s)
    let flag = a:0 == 1 ? a:1 : 'all'
    let types = copy(a:000)
    let label = 'input filetype(s) ' . join(map(copy(types), 'string(v:val)'), ', ')
  else  " current filetype
    let flag = &filetype
    let types = [&filetype]
    let label = 'current filetype ' . string(&filetype)
  endif
  let cmd = s:tags_command('', '--list-kinds=' . string(flag))
  let cmd = substitute(cmd, '|.*$', '', 'g')
  let table = system(cmd)
  if flag ==# 'all'  " filter particular filetypes
    let l:subs = []
    let regex = '\c\(\%(\n\|^\)\@<=\%(' . join(types, '\|') . '\)\n'
    let regex = regex . '\%(\s\+[^\n]*\%(\n\|$\)\)*\)\S\@!'
    let append = '\=add(l:subs, submatch(0))'  " see: https://vi.stackexchange.com/a/16491/8084
    call substitute(table, regex, append, 'gn')
    let table = join(l:subs, '')
  endif
  return 'Tag kinds for ' . label . ":\n" . trim(table)
endfunction

" Show the current file tags
" Note: This tries to read existing buffer variable to increase speed in huge sessions
" let table = system(s:tags_command(path) . ' | tr -s $''\t'' | column -t -s $''\t''')
" let table = substitute(table, escape(path, s:regex_magic), '', 'g')
function! tags#table_tags(...) abort
  if index(a:000, 'all') >= 0  " all open paths
    let paths = map(tags#buffer_paths(), 'v:val[1]')
    let label = 'all open paths'
  elseif a:0  " input path(s)
    let paths = copy(a:000)
    let label = 'input path(s) ' . join(map(copy(paths), 'string(v:val)'), ', ')
  else  " current path
    let paths = [exists('*RelativePath') ? RelativePath(@%) : expand('%:~:.')]
    let label = 'current path ' . string(paths[0])
  endif
  let tables = []
  for path in paths  " relative paths
    if !filereadable(path)
      let types = getcompletion(path, 'filetype')  " https://vi.stackexchange.com/a/14990/8084
      if index(types, path) < 0
        echohl WarningMsg
        echom 'Warning: Path ' . string(path) . ' not open or not readable.'
        echohl None
      endif
      continue
    endif
    let path = exists('*RelativePath') ? RelativePath(path) : fnamemodify(path, ':~:.')
    let items = getbufvar(bufnr(path), 'tags_by_name', [])  " use buffer by default
    let items = empty(items) ? s:tags_parsed(path)[1] : items  " try to generate
    let table = empty(items) || len(paths) == 1 ? '' : path . "\n"
    for [name, line, kind; context] in empty(items) ? [] : items
      let kind = len(paths) == 1 ? kind : '    ' . kind
      let name = empty(context) ? name : name . ' (' . join(context, ' ') . ')'
      let table .= kind . ' ' . repeat(' ', 4 - len(line)) . line . ': ' . name . "\n"
    endfor
    if !empty(trim(table)) | call add(tables, trim(table)) | endif
  endfor
  if empty(tables)
    echohl WarningMsg
    echom 'Warning: Tags not found or not available.'
    echohl None
    return ''
  endif
  return 'Tags for ' . label . ":\n" . join(tables, "\n")
endfunction

"-----------------------------------------------------------------------------
" Tag navigation utiltiies
"-----------------------------------------------------------------------------
" Get the current tag from a list of tags
" Note: This function searches exclusively (i.e. does not match the current line).
" So only start at current line when jumping, otherwise start one line down.
function! tags#close_tag(line, major, forward, circular) abort
  if a:major
    let kinds = get(g:tags_major_kinds, &filetype, 'f')
    let filt = "len(v:val) == 3 && v:val[2] =~# '[" . kinds . "]'"
  else
    let kinds = get(g:tags_minor_kinds, &filetype, 'v')
    let filt = "v:val[2] !~# '[" . kinds . "]'"
  endif
  silent! unlet! b:tags_scope_by_line  " outdated
  silent! unlet! b:tags_top_by_line  " outdated
  let tags = get(b:, 'tags_by_line', [])
  let tags = filter(copy(tags), filt)
  if empty(tags)
    return []  " silent failure
  endif
  let lnum = a:line
  if a:circular && a:forward && lnum >= tags[-1][1]
    let idx = 0
  elseif a:circular && !a:forward && lnum <= tags[0][1]
    let idx = -1
  else
    for jdx in range(1, len(tags) - 1)  " in-between tags (endpoint inclusive)
      if a:forward && lnum >= tags[-jdx - 1][1]
        let idx = -jdx
        break
      endif
      if !a:forward && lnum <= tags[jdx][1]
        let idx = jdx - 1
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
function! tags#current_tag(...) abort
  let lnum = line('.') + 1
  let info = tags#close_tag(lnum, 0, 0, 0)
  let full = a:0 ? a:1 : 1  " print full tag
  if empty(info)
    let parts = []
  elseif !full || len(info) == 3
    let parts = [info[2], info[0]]
  els  " include extra information
    let extra = substitute(info[3], '^.*:', '', '')
    let parts = [info[2], extra, info[0]]
  endif
  let string = join(parts, ':')
  return string
endfunction

" Get the line of the next or previous tag excluding under the cursor
" Note: This is used with bracket maps
function! tags#jump_tag(repeat, ...) abort
  let repeat = a:repeat == 0 ? 1 : a:repeat
  let args = copy(a:000)
  call add(args, 1)  " enable circular searching
  call insert(args, line('.'))  " start on current line
  for idx in range(repeat)  " loop through repitition count
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

" Select a specific tag using fzf
" Note: This matches construction of fzf mappings in vim-succinct.
function! tags#select_tag(...) abort
  let global = a:0 ? a:1 : 0
  let prompt = global ? 'Tag> ' : 'BTag> '
  let source = call('s:tag_source', a:000)
  if empty(source)
    echohl WarningMsg
    echom 'Warning: Tags not found or not available.'
    echohl None
    return
  endif
  if !exists('*fzf#run')
    echohl WarningMsg
    echom 'Warning: FZF plugin not found.'
    echohl None
    return
  endif
  call fzf#run(fzf#wrap({
    \ 'source': source,
    \ 'sink': function('s:tag_sink'),
    \ 'options': '--no-sort --prompt=' . string(prompt),
    \ }))
endfunction

" Return strings in the format: '[<file name>: ]<line number>: name (type, [scope])'
" for selection by fzf. File name included only if 'global' was passed.
" Note: Tried gutentags, but too complicated, would need access to script variables
" See: https://github.com/ludovicchabant/vim-gutentags/issues/349
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
function! s:tag_sink(tag) abort
  let parts = split(a:tag, ':')
  if parts[0] =~# '^\s*\d\+'
    exe parts[0]
  elseif exists('*file#open_drop')
    call file#open_drop(parts[0])
    exe parts[1]
  else
    exe 'tab drop ' . parts[0]
    exe parts[1]
  endif
  normal! zv
endfunction
function! s:tag_source(...) abort
  let global = a:0 ? a:1 : 0
  let source = []
  if global  " global paths
    let paths = map(tags#buffer_paths(), 'v:val[1]')
  else  " local path
    let paths = [expand('%:p')]
  endif
  for path in paths
    let bnr = bufnr(path)  " buffer unique to path
    let src = deepcopy(getbufvar(bnr, 'tags_by_name', []))
    let head = "printf('%4d', v:val[1]) . ': '"
    let tail = "v:val[0] . ' (' . join(v:val[2:], ', ') . ')'"
    if global
      if exists('*RelativePath')
        let path = RelativePath(path)  " vim-statusline function
      else
        let path = fnamemodify(path, ':~:.')
      endif
      let head = string(path) . " . ': ' . " . head
    endif
    let src = map(src, head . ' . ' . tail)
    call extend(source, src)
  endfor
  return source
endfunction

"-----------------------------------------------------------------------------
" Refactoring-related utilities
"-----------------------------------------------------------------------------
" Count occurrences inside file
" See: https://vi.stackexchange.com/a/20661/8084
function! tags#count_match(key) abort
  call tags#set_match(a:key)
  let winview = winsaveview()  " store window as buffer variable
  let search = @/
  exe '%s@' . search . '@@gne'
  call winrestview(b:winview)
endfunction

" Repeat previous change
" Note: The 'cgn' command silently fails to trigger insert mode if no matches found
" so we check for that. Putting <Esc> in feedkeys() cancels operation so must come
" afterward (may be no-op) and the 'i' is necessary to insert <C-a> before <Esc>.
function! tags#change_again() abort
  let cmd = "mode() =~# 'i' ? '\<C-a>' : ''"
  let cmd = 'feedkeys(' . cmd . ', "ni")'
  let cmd = "cgn\<Cmd>call " . cmd . "\<CR>\<Esc>n"
  call feedkeys(cmd, 'n')  " add previous insert if cgn succeeds
  if exists('*repeat#set')
    call repeat#set("\<Plug>change_again")  " re-apply this function for next repeat
  endif
endfunction

" Function that sets things up for maps that change text
" Note: Unlike tags#delete_next we wait until
function! tags#change_next(key) abort
  call tags#set_match(a:key)
  call feedkeys('cgn')
  let g:change_next = 1
  if exists('*repeat#set')
    call repeat#set("\<Plug>change_again")
  endif
endfunction

" Finish change after InsertLeave and automatically jump to next occurence
" Note: Register may have keystrokes e.g. <80>kb (backspace) so must feed as 'typed'
function! tags#change_finish() abort
  if exists('g:change_all') && g:change_all
    silent undo  " undo first change so subsequent undo reverts all changes
    let b:winview = winsaveview()  " store window view as buffer variable
    call feedkeys(':keepjumps %s@' . @/ . '@' . @. . "@ge | call winrestview(b:winview)\<CR>", 'nt')
  elseif exists('g:change_next') && g:change_next
    call feedkeys('n', 'nt')
    if exists('*repeat#set')
      call repeat#set("\<Plug>change_again")
    endif
  endif
  let g:change_all = 0
  let g:change_next = 0
endfunction

" Delete next match
" Note: hlsearch inside function fails: https://stackoverflow.com/q/1803539/4970632
function! tags#delete_next(key) abort
  call tags#set_match(a:key)
  call feedkeys('dgnn')
  if exists('*repeat#set')
    call repeat#set("\<Plug>" . a:key, v:count)
  endif
endfunction

" Delete all of next matches
" Note: Unlike 'change all' this can simply call :substitute
function! tags#delete_all(key) abort
  call tags#set_match(a:key)
  let winview = winsaveview()
  exe 'keepjumps %s@' . @/ . '@@ge'
  call winrestview(winview)
endfunction

" Return major tag folding scope
" See: https://stackoverflow.com/a/597932/4970632
" See: http://vim.wikia.com/wiki/Search_in_current_function
function! tags#get_scope(...) abort
  " Initial stuff
  let kinds = get(g:tags_major_kinds, &filetype, 'f')
  let filt = "v:val[2] =~# '[" . kinds . "]'"
  let lnum = a:0 ? a:1 : line('.')
  let items = get(b:, 'tags_by_line', [])
  let items = filter(copy(items), filt)
  let lines = map(deepcopy(items), 'v:val[1]')
  if empty(items)
    echohl WarningMsg
    echom 'Warning: Failed to restrict the search scope (tags unavailable).'
    echohl None
    return ''
  endif
  " Find closing line and tag
  keepjumps normal! zv
  let winview = winsaveview()
  exe index(lines, lnum) >= 0 ? lnum + 1 : ''
  let [kline, klevel] = [-1, -1]
  while kline != line('.') && foldlevel('.') > klevel
    let [kline, klevel] = [line('.'), foldlevel('.')]
    keepjumps normal! [z
  endwhile
  let [iline, ilevel] = [line('.'), foldlevel('.')]
  keepjumps normal! ]z
  let [jline, jlevel] = [line('.'), foldlevel('.')]
  call winrestview(winview)
  " Return scope if within fold
  let maxlen = 20  " truncate long labels
  let idx = index(lines, string(iline))  " type matters for index()
  if idx >= 0 && lnum >= iline && lnum <= jline && iline != jline && ilevel == jlevel
    let [line1, line2] = [iline, jline]
    let [label1, label2] = [items[idx][0], trim(getline(jline))]
  else  " fallback to global search
    let [line1, line2] = [1, line('$')]
    let [label1, label2] = ['START', 'END']
  endif
  let label1 = len(label1) <= maxlen ? label1 : label1[:maxlen - 3] . '···'
  let label2 = len(label2) <= maxlen ? label2 : label2[:maxlen - 3] . '···'
  let regex = printf('\%%>%dl\%%<%dl', line1 - 1, line2 + 1)
  echom 'Selected lines ' . line1 . ' (' . label1 . ') to ' . line2 . ' (' . label2 . ').'
  return regex
endfunction

" Set the last search register to some 'current pattern' under cursor
" Note: Here '!' handles multi-byte characters using example in :help byteidx. Also
" the native vim-indexed-search maps invoke <Plug>(indexed-search-after), which just
" calls <Plug>(indexed-search-index) --> :ShowSearchIndex... but causes change maps
" to silently abort for some weird reason... so instead call this manually.
function! s:get_item(key, ...) abort
  let search = a:0 ? a:1 : 0
  if a:key =~# '[*#]'
    let item = escape(expand('<cword>'), s:regex_magic)
    let item = item =~# '^\k\+$' ? search ? '\<' . item . '\>\C' : item : ''
  elseif a:key =~# '[&@]'
    let item = escape(expand('<cWORD>'), s:regex_magic)
    let item = search ? '\(^\|\s\)\zs' . item . '\ze\($\|\s\)\C' : item
  else  " ··· note col('.') and string[:idx] uses byte index
    let item = strcharpart(strpart(getline('.'), col('.') - 1), 0, 1)
    let item = escape(empty(item) ? "\n" : item, s:regex_magic)
  endif
  return item
endfunction
function! tags#set_match(key, ...) abort
  let item = s:get_item(a:key, 0)
  if a:0 && a:1 && empty(item) && foldclosed('.') == -1
    exe getline('.') =~# '^\s*$' ? '' : 'normal! B'
  endif
  let item = s:get_item(a:key, 1)
  if !strwidth(item)
    return
  endif
  let char = strcharpart(strpart(getline('.'), col('.') - 1), 0, 1)
  let flags = char =~# '\s' || a:key =~# '[*#]' && char !~# '\k' ? 'cW' : 'cbW'
  if a:0 && a:1 && strwidth(item) > 1
    call search(item, flags, line('.'))
  endif
  let scope = a:key =~# '[#@]' ? tags#get_scope() : ''
  let @/ = scope . item
  if empty(scope) && exists(':ShowSearchIndex')
    ShowSearchIndex
  endif
endfunction
