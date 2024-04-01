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

"-----------------------------------------------------------------------------"
" Buffer listing utilities
"-----------------------------------------------------------------------------"
" Return [tab, buffer] number pairs in order of proximity to current tab
" Note: This optionally filters out buffers not belonging to the active
" filetype used for :tag-style definition jumping across multiple windows.
function! s:bufs_close(...) abort
  let tnr = tabpagenr()  " active tab
  let tleft = tnr
  let tright = tnr - 1  " initial value
  let ftype = a:0 ? a:1 : ''  " restricted type
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
      let btype = getbufvar(bnr, '&filetype')
      if !empty(ftype) && btype !=# ftype
        continue
      elseif filereadable(path) && index(g:tags_skip_filetypes, btype) == -1
        call add(pairs, [tnr, bnr]) | break  " one entry per tab
      endif
    endfor
  endwhile
  return pairs
endfunction

" Return buffers accessed after given time
" Note: This defaults to returning tabs accessed after 'startup time' determined from
" files with smallast access times and within 10 seconds of each other.
function! tags#bufs_recent(...) abort
  let bufs = map(getbufinfo(), {idx, val -> [val.bufnr, get(val, 'lastused', 0)]})
  let mintime = a:0 ? a:1 : 0
  if !a:0  " auto-detect threshold for sorting
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

" Return [tab, buffer] pairs sorted by recent use
" Note: This sorts buffers using three methods: first by recent use among the
" author's vimrc 'tab stack' utility, second by recent use among all other tabs,
" and third by physical proximity to the current tab. Useful for fzf selection.
function! tags#buffer_paths(...) abort
  let pairs = call('s:bufs_close', a:000)
  let bnrs = map(copy(pairs), 'v:val[1]')
  let idxs = []
  let stacked = []  " sorted by access time
  let temporal = []  " sorted by access time
  let physical = []  " ordered by adjacency
  let stack = get(g:, 'tab_stack', [])  " stack of absolute paths
  let stack = map(copy(stack), 'bufnr(v:val)')
  for bnr in tags#bufs_recent()
    let idx = index(bnrs, bnr)
    if idx != -1  " move to the front
      let tnr = pairs[idx][0]
      let path = expand('#' . bnr . ':p')
      let items = index(stack, bnr) == -1 ? temporal : stacked
      call add(idxs, idx)
      call add(items, [tnr, path])
    endif
  endfor
  for idx in range(len(pairs))
    if index(idxs, idx) == -1
      let [tnr, bnr] = pairs[idx]
      let path = expand('#' . bnr . ':p')
      call add(physical, [tnr, path])
    endif
  endfor
  let pairs = stacked + temporal + physical
  return pairs  " prefer most recently visited then closest
endfunction

"-----------------------------------------------------------------------------"
" Tag generation utiliities
"-----------------------------------------------------------------------------"
" Return tags parsed and sorted by name and line
" Note: This is used for buffer variables and unopened :ShowTags path(s)
" Note: Output should be in number mode (i.e. shows line number instead of full line)
function! s:tags_command(path, ...) abort
  let path = shellescape(expand(fnamemodify(a:path, ':p')))
  let cmd = join(a:000, ' ') . ' ' . path
  return s:tags_command . ' ' . cmd . ' 2>/dev/null' . " | cut -d'\t' -f1,3-5"
endfunction
function! s:tags_parsed(path) abort
  let type = getbufvar(bufnr(a:path), '&filetype')  " possibly empty string
  let skip = get(g:tags_skip_kinds, type, '@')  " default dummy character
  if index(g:tags_skip_filetypes, type) >= 0 | return [[], []] | endif
  let flags = getline(1) =~# '#!.*python[23]' ? '--language-force=python' : ''
  let items = system(s:tags_command(a:path, flags) . " | sed 's/;\"\t/\t/g'")
  let items = map(split(items, '\n'), "split(v:val, '\t')")
  let items = filter(items, "v:val[2] !~# '[" . skip . "]'")
  return [sort(items, 's:sort_by_line'), sort(deepcopy(items), 's:sort_by_name')]
endfunction

" Generate tags and parse them into list of lists
" Note: This will only update when tag generation time more recent than last file
" save time. Also note files open in multiple windows have the same buffer number
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

" Show the current file kinds
" Note: Ctags cannot show specific filetype kinds so instead filter '--list-kinds=all'
" Note: See https://stackoverflow.com/a/71334/4970632 for difference between \r and \n
function! tags#table_kinds(...) abort
  let [umajor, uminor] = [copy(g:tags_major_kinds), copy(g:tags_minor_kinds)]
  if index(a:000, 'all') >= 0  " all open filetypes
    let flag = 'all'
    let types = uniq(sort(umajor + uminor))
    let major = map(copy(types), {idx, val -> val . ' ' . string(get(umajor, val, 'f'))})
    let minor = map(copy(types), {idx, val -> val . ' ' . string(get(uminor, val, 'v'))})
    let major = ['default ' . string('f')] + major
    let minor = ['default ' . string('v')] + minor
    let types = uniq(map(tags#buffer_paths(), "getbufvar(v:val[1], '&filetype')"))
    let label = 'all buffer filetypes'
  elseif a:0  " input filetype(s)
    let flag = a:0 == 1 ? a:1 : 'all'
    let types = sort(copy(a:000))
    let major = map(copy(types), {idx, val -> val . ' ' . string(get(umajor, val, 'f'))})
    let minor = map(copy(types), {idx, val -> val . ' ' . string(get(uminor, val, 'v'))})
    let label = 'input filetype(s) ' . join(map(copy(types), 'string(v:val)'), ', ')
  else  " current filetype
    let flag = &l:filetype
    let types = [&l:filetype]
    let major = [string(get(umajor, flag, 'f'))]
    let minor = [string(get(uminor, flag, 'v'))]
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
  let title = 'Tag kinds for ' . label
  let major = 'Major tag kinds: ' . join(major, ' ')
  let minor = 'Minor tag kinds: ' . join(minor, ' ')
  return title . ":\n" . major . "\n" . minor . "\n" . trim(table)
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
        redraw | echohl WarningMsg
        echom 'Warning: Path ' . string(path) . ' not open or not readable.'
        echohl None
      endif | continue
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
    redraw | echohl WarningMsg
    echom 'Warning: Tags not found or not available.'
    echohl None | return ''
  endif
  return 'Tags for ' . label . ":\n" . join(tables, "\n")
endfunction

"-----------------------------------------------------------------------------
" Tag searching utiltiies
"-----------------------------------------------------------------------------
" Return tags in the format '[<file>: ]<line>: name (type[, scope])'
" for selection by fzf. File name included only if 'global' was passed.
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
function! s:tag_source(level, ...) abort
  let source = []
  if a:level > 1  " global paths
    let paths = map(tags#buffer_paths(), 'v:val[1]')
  elseif a:level > 0  " filetype paths
    let paths = map(tags#buffer_paths(&filetype), 'v:val[1]')
  else  " local path
    let paths = [expand('%:p')]
  endif
  for path in paths
    if exists('*RelativePath')
      let path = RelativePath(path)  " vim-statusline function
    else
      let path = fnamemodify(path, ':~:.')
    endif
    let bnr = bufnr(path)  " buffer unique to path
    let src = deepcopy(getbufvar(bnr, 'tags_by_name', []))
    if a:0 && a:1
      let src = map(src, 'v:val[1:1] + v:val[0:0] + v:val[2:]')
      let src = a:level ? map(src, 'insert(v:val, path, 0)') : (src)
      call extend(source, src)
    else
      let head = a:level ? string(path) . " . ': ' . " : ''
      let head .= "printf('%4d', v:val[1]) . ': '"
      let tail = "v:val[0] . ' (' . join(v:val[2:], ', ') . ')'"
      let src = map(src, head . ' . ' . tail)
      call extend(source, src)
    endif
  endfor
  return source
endfunction

" Navigate to input tag list or fzf selection
" Note: Here optionally preserve jumps triggered by line change, and try
" to position cursor on exact match instead of start-of-line.
function! tags#goto_tag(...) abort
  return call('s:goto_tag', [0] + a:000)
endfunction
function! tags#goto_block(...) abort
  return call('s:goto_tag', [1] + a:000)
endfunction
function! s:goto_tag(block, ...) abort
  " Parse tag input
  let raw = '^\s*\(.\{-}\) *\t\(.\{-}\) *\t\(\d\+\)'
  let raw .= ';"\s*\(.\{-}\)\%( *\t\(.*\)\)\?$'
  let regex = '^\s*\%(\(.*\):\s\+\)\?'  " tag file
  let regex .= '\(\d\+\):\s\+'  " tag line
  let regex .= '\(.\{-}\)\s\+'  " tag name
  let regex .= '(\(\a\(,\s\+.\{-}\)\?\))$'  " tag kind and scope
  let path = expand('%:p')  " current path
  let isrc = ''  " reference ctags file
  if a:0 > 1  " non-fzf input
    let [ibuf, ipos, iname; irest] = a:0 < 3 ? [path] + a:000 : a:000
  elseif a:1 =~# regex  " format '[<file>: ]<line>: name (type[, scope])'
    let [ibuf, ipos, iname, irest] = matchlist(a:1, regex)[1:4]
  elseif a:1 =~# raw  " native format 'name<Tab>file<Tab>line;...'
    let [iname, ibuf, ipos, irest, isrc] = matchlist(a:1, raw)[1:5]
  else  " e.g. cancelled selection
    return
  endif
  " Jump to tag buffer
  if empty(ibuf)
    let ipath = path
  elseif !type(ibuf)
    let ipath = expand('#' . ibuf . ':p')
  elseif empty(isrc)
    let ipath = fnamemodify(ibuf, ':p')
  else  " relative to tags file
    let ipath = fnamemodify(isrc, ':p:h') . '/' . ibuf
  endif
  if ipath ==# path  " record mark
    exe a:block && g:tags_keep_jumps || getpos("''") == getpos('.') ? '' : "normal! m'"
  elseif exists('*file#open_drop')  " dotfiles utility
    silent call file#open_drop(ipath)
  else  " built-in utility
    silent exe 'tab drop ' . fnameescape(ipath)
  endif
  " Jump to tag position
  let [bnum, from] = [bufnr(), getpos('.')]  " from position
  let [lnum, cnum] = type(ipos) == type([]) ? ipos : [ipos, 0]
  call cursor(lnum, 1)
  let regex = escape(iname, s:regex_magic)
  if cnum == 0
    silent call search(regex, 'cW', lnum)
  elseif cnum > 1
    exe 'normal! ' . (cnum - 1) . 'l'
  endif
  if !a:block && !g:tags_keep_stack && iname !=# '<from>'
    let item = {'bufnr': bnum, 'from': from, 'matchnr': 1, 'tagname': iname}
    call settagstack(winnr(), {'items': [item]}, 'a')
  endif
  let type = a:block ? '\<block\>' : '\<tag\>'
  exe &l:foldopen !~# type ? 'normal! zz' : 'normal! zvzz'
  exe a:block && g:tags_keep_jumps ? '' : "normal! m'"
  let b:tag_name = [ipath, lnum, iname]  " used for stacks
  let suffix = type(irest) <= 1 ? irest : get(irest, 0, '')
  let suffix = empty(irest) ? '' : ' (' . suffix . ')'
  redraw | echom 'Tag: ' . iname . suffix
endfunction

" Get the current tag from a list of tags
" Note: This function searches exclusively (i.e. does not match the current line).
" So only start at current line when jumping, otherwise start one line down.
function! tags#close_tag(...) abort
  let lnum = a:0 > 0 ? a:1 : line('.')
  let major = a:0 > 1 ? a:2 : 0
  let forward = a:0 > 2 ? a:3 : 0
  let circular = a:0 > 3 ? a:4 : 0
  if major  " major tags only
    let kinds = get(g:tags_major_kinds, &filetype, 'f')
    let filt = "len(v:val) == 3 && v:val[2] =~# '[" . kinds . "]'"
  else  " all except minor
    let kinds = get(g:tags_minor_kinds, &filetype, 'v')
    let filt = "v:val[2] !~# '[" . kinds . "]'"
  endif
  silent! exe 'unlet! b:tags_scope_by_line'
  silent! exe 'unlet! b:tags_top_by_line'
  let tags = get(b:, 'tags_by_line', [])
  let tags = filter(copy(tags), filt)
  if empty(tags)
    return []  " silent failure
  endif
  if circular && forward && lnum >= tags[-1][1]
    let idx = 0
  elseif circular && !forward && lnum <= tags[0][1]
    let idx = -1
  else  " search in between (endpoint inclusive)
    for jdx in range(1, len(tags) - 1)
      if forward && lnum >= tags[-jdx - 1][1]
        let idx = -jdx
        break
      endif
      if !forward && lnum <= tags[jdx][1]
        let idx = jdx - 1
        break
      endif
    endfor
    if !exists('idx')  " single tag or first or last tag
      let idx = forward ? 0 : -1
    endif
  endif
  return tags[idx]
endfunction

" Select a specific tag using fzf
" Note: This matches construction of fzf mappings in vim-succinct.
" See: https://github.com/ludovicchabant/vim-gutentags/issues/349
function! tags#push_tag(...) abort
  if exists('*stack#push_stack')
    return stack#push_stack('tag', 'tags#goto_tag', a:000, 0)
  else
    return call('tags#goto_tag', a:000)
  endif
endfunction
function! tags#select_tag(...) abort
  let level = a:0 ? a:1 : 0
  let prompt = level > 1 ? 'Tag> ' : level > 0 ? 'FTag> ' : 'BTag> '
  let source = s:tag_source(level, 0)
  if empty(source)
    redraw | echohl WarningMsg
    echom 'Warning: Tags not found or not available.'
    echohl None | return
  endif
  if !exists('*fzf#run')
    redraw | echohl WarningMsg
    echom 'Warning: FZF plugin not found.'
    echohl None | return
  endif
  let flags = '--no-sort --prompt=' . string(prompt)
  let options = {'source': source, 'sink': function('tags#push_tag'), 'options': flags}
  call fzf#run(fzf#wrap(options))
endfunction

"-----------------------------------------------------------------------------"
" Tag navigation utilities
"-----------------------------------------------------------------------------"
" Get the 'current' tag definition under or preceding the cursor
" Note: This is used with statusline and :CurrentTag
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

" Jump to the next or previous tag under the cursor
" Note: This is used with bracket t/T mappings
function! tags#next_tag(count, ...) abort
  let forward = a:count >= 0
  let args = [line('.'), a:0 && a:1, forward, 1]  " circular searching
  for idx in range(abs(a:count))  " loop through repitition count
    let tag = call('tags#close_tag', args)
    if empty(tag)
      redraw | echohl WarningMsg
      echom 'Error: Next tag not found'
      echohl None | return
    endif
    let args[0] = str2nr(tag[1])  " adjust line number
  endfor
  call tags#goto_block(tag[1], tag[0])  " jump to line then name
  if &l:foldopen =~# '\<block\>' | exe 'normal! zv' | endif
endfunction

" Jump to the next or previous word under the cursor
" Note: This is used with bracket w/W mappings
function! tags#next_word(count, ...) abort
  let global = a:0 && a:1
  let winview = winsaveview()  " tags#set_match() moves to start of match
  silent call tags#set_match(1, !global, 1)  " suppress scope emssage for now
  let regex = @/ | let flags = a:count >= 0 ? 'w' : 'bw'
  for _ in range(abs(a:count))
    let pos = getpos('.')
    call search(regex, flags, 0, 0, "tags#get_inside('Constant', 'Comment')")
    if getpos('.') == pos
      redraw | echohl WarningMsg
      echom 'Error: Next keyword not found'
      echohl None | call winrestview(winview) | return
    endif
  endfor
  let parts = matchlist(regex, '^\(\\%>\(\d\+\)l\)\?\(\\%<\(\d\+\)l\)\?\(.*\)$')
  let [line1, line2, word] = [parts[2], parts[4], parts[5]]  " get scope from regex
  let [line1, line2] = [str2nr(line1), str2nr(line2)]  " note str2nr('') is zero
  let prefix = substitute(word, '\\[<>cC]', '', 'g')
  let suffix = line1 && line2 ? ' (lines ' . line1 . ' to ' . line2 . ')' : ''
  redraw | echom 'Keyword: ' . prefix . suffix
  if &l:foldopen =~# '\<block\>' | exe 'normal! zv' | endif
endfunction

" Go to the tag keyword under the cursor
" Note: Vim does not natively support jumping separate windows so implement here
let s:keyword_mods = {'vim': ':', 'tex': ':-'}
function! tags#goto_name(...) abort
  let level = a:0 ? a:1 : 1
  let path = expand('%:p')
  let keys = &l:iskeyword
  let names = a:000[1:]
  if empty(names)  " tag names
    let mods = get(s:keyword_mods, &l:filetype, '')
    let mods = split(mods, '\zs')
    let &l:iskeyword = join([keys]+ mods, ',')
    try
      let names = [expand('<cword>'), expand('<cWORD>')]
    finally
      let &l:iskeyword = keys
    endtry
  endif
  for name in names  " several attempts
    let name = substitute(name, '\(^\s*\|\s*$\)', '', 'g')
    if empty(name) | return | endif
    let itags = taglist(escape(name, s:regex_magic), path)
    for itag in itags  " search 'tags' files
      if itag.name !=# name | continue | endif
      let ipath = fnamemodify(itag.filename, ':p')
      if level < 1 && ipath !=# path | continue | endif
      let itype = getbufvar(bufnr(ipath), '&filetype')
      if level < 2 && itype !=# &l:filetype | continue | endif
      return tags#push_tag(ipath, itag.cmd, itag.name, itag.kind)
    endfor
    let itags = s:tag_source(level, 1)
    for [ipath, iline, iname; irest] in itags  " search all files
      if name !=# iname | continue | endif
      return call('tags#push_tag', [ipath, iline, iname] + irest)
    endfor
  endfor
  redraw | echohl ErrorMsg
  echom "Error: Tag '" . names[0] . "' not found"
  echohl None
endfunction

"-----------------------------------------------------------------------------"
" Keyword searching utilities
"-----------------------------------------------------------------------------"
" Return whether cursor is inside the requested syntax element(s)
" Note: This uses the searcy() 'skip' parameter to skip matches inside comments and
" constants (i.e. strings). Similar method is used in succinct.vim for python docstrings
function! tags#get_inside(arg, ...) abort
  if type(a:arg)  " i.e. not numeric
    let [offset; names] = [0, a:arg] + a:000
  else
    let [offset; names] = [a:arg] + a:000
  endif
  let [lnum, cnum] = [line('.'), col('.') + offset]
  let cnum = min([max([cnum, 1]), col('$') - 1])  " col('$') is newline/end-of-file
  let sids = map(synstack(lnum, cnum), 'synIDtrans(v:val)')
  for name in names  " iterate over options
    let sid = synIDtrans(hlID(name))
    if sid && index(sids, sid) != -1 | return 1 | endif
  endfor | return 0
endfunction

" Return major tag folding scope
" See: https://stackoverflow.com/a/597932/4970632
" See: http://vim.wikia.com/wiki/Search_in_current_function
function! tags#get_scope(...) abort
  " Initial stuff
  let trunc = 20  " truncate long labels
  let opts = get(g:tags_major_kinds, &filetype, 'f')
  let filt = "v:val[2] =~# '[" . opts . "]'"
  let items = get(b:, 'tags_by_line', [])
  let items = filter(copy(items), filt)
  let lines = map(deepcopy(items), 'str2nr(v:val[1])')
  if empty(items)
    redraw | echohl WarningMsg
    echom 'Warning: Failed to restrict the search scope (tags unavailable).'
    echohl None | return ''
  endif
  " Find closing line and tag
  let winview = winsaveview()
  exe a:0 ? a:1 : '' | let lnum = line('.')
  let [iline, line1, level1] = [-1, lnum, foldlevel('.')]
  while iline != line1 && index(lines, line1) == -1
    let [iline, ifold] = [line('.'), foldclosed('.')]
    exe ifold > 0 ? ifold : 'keepjumps normal! [z'
    let [line1, level1] = [line('.'), foldlevel('.')]
  endwhile
  let ifold = foldclosedend('.')
  exe ifold > 0 ? ifold : 'keepjumps normal! ]z'
  let [line2, level2] = [line('.'), foldlevel('.')]
  call winrestview(winview)
  " Return scope if within fold
  let idx = index(lines, line1)
  let isfold = level1 > 0 && line1 != line2
  let iscursor = lnum >= line1 && lnum <= line2
  if idx >= 0 && isfold && iscursor  " scope local search
    let [label1, label2] = [items[idx][0], trim(getline(line2))]
  else  " fallback to global search
    let [line1, line2, label1, label2] = [1, line('$'), 'START', 'END']
  endif
  let label1 = len(label1) <= trunc ? label1 : label1[:trunc - 3] . '···'
  let label2 = len(label2) <= trunc ? label2 : label2[:trunc - 3] . '···'
  let regex = printf('\%%>%dl\%%<%dl', line1 - 1, line2 + 1)
  let msg = 'Selected lines ' . line1 . ' (' . label1 . ') to ' . line2 . ' (' . label2 . ').'
  redraw | echom msg | return regex
endfunction

" Set the last search register to some 'current pattern' under cursor
" Note: Here level -1 is previous search, level 0 is current character, level 1 is
" current word, and level 2 is current WORD. Second arg denotes scope boundary.
" Note: Here '!' handles multi-byte characters using example in :help byteidx. Also
" the native vim-indexed-search maps invoke <Plug>(indexed-search-after), which just
" calls <Plug>(indexed-search-index) --> :ShowSearchIndex... but causes change maps
" to silently abort for some weird reason... so instead call this manually.
function! tags#get_match(level, ...) abort
  let search = a:0 ? a:1 : 0
  if a:level >= 2
    let item = escape(expand('<cWORD>'), s:regex_magic)
    let item = search ? '\(^\|\s\)\zs' . item . '\ze\($\|\s\)\C' : item
  elseif a:level >= 1
    let item = escape(expand('<cword>'), s:regex_magic)
    let item = item =~# '^\k\+$' ? search ? '\<' . item . '\>\C' : item : ''
  else  " ··· note col('.') and string[:idx] uses byte index
    let item = strcharpart(strpart(getline('.'), col('.') - 1), 0, 1)
    let item = escape(empty(item) ? "\n" : item, s:regex_magic)
  endif
  return item
endfunction
function! tags#set_match(level, option, ...) abort
  let adjust = a:0 && a:1
  let scope = ''
  if a:level < 0  " previous search
    let prefix = 'Match'
    let suffix = a:option ? 'Prev' : 'Next'
  else  " cursor search
    let prefix = a:level >= 2 ? 'WORD' : a:level >= 1 ? 'Word' : 'Char'
    let suffix = a:option ? 'Local' : 'Global'
    let item = tags#get_match(a:level, 0)
    if adjust && empty(item) && foldclosed('.') == -1
      exe getline('.') =~# '^\s*$' ? '' : 'normal! B'
    endif
    let item = tags#get_match(a:level, 1)
    let char = strcharpart(strpart(getline('.'), col('.') - 1), 0, 1)
    let flags = char =~# '\s' || a:level == 1 && char !~# '\k' ? 'cW' : 'cbW'
    if a:0 && a:1 && strwidth(item) > 1
      call search(item, flags, line('.'))
    endif
    let scope = a:option ? tags#get_scope() : ''
    let @/ = scope . item
  endif
  if a:0 && a:1 && foldclosed('.') != -1
    foldopen
  endif
  if empty(scope) && exists(':ShowSearchIndex')
    call feedkeys("\<Cmd>ShowSearchIndex\<CR>", 'n')
  endif
  return [prefix, suffix]
endfunction

"-----------------------------------------------------------------------------
" Keyword manipulation utilities
"-----------------------------------------------------------------------------
" Helper functions
" Note: Critical to feed repeat command and use : instead of <Cmd> or will
" not work properly. See: https://vi.stackexchange.com/a/20661/8084
function! s:feed_repeat(name, ...) abort
  if !exists('*repeat#set') | return | endif
  let plug = '\<Plug>' . a:name
  let cnt = a:0 ? a:1 : v:count
  let cmd = 'call repeat#set("' . plug . '", ' . cnt . ')'
  call feedkeys("\<Cmd>" . cmd . "\<CR>", 'n')
endfunction
function! tags#search_match(level, option) abort
  call tags#set_match(a:level, a:option)
  let winview = winsaveview()  " store window as buffer variable
  let result = execute('%s@' . escape(@/, '@') . '@@gne')
  call winrestview(winview)
  call feedkeys("\<Cmd>setlocal hlsearch\<CR>", 'n')
  return result
endfunction

" Set up repeat after finishing previous change on InsertLeave
" Note: The 'cgn' command silently fails to trigger insert mode if no matches found
" so we check for that. Putting <Esc> in feedkeys() cancels operation so must come
" afterward (may be no-op) and the 'i' is necessary to insert <C-a> before <Esc>.
function! tags#change_repeat() abort
  let motion = get(s:, 'change_motion', 'n')
  let cmd = "mode() =~# 'i' ? '\<C-a>' : ''"
  let cmd = 'feedkeys(' . cmd . ', "ni")'
  let cmd = 'zvcg' . motion . "\<Cmd>call " . cmd . "\<CR>\<Esc>" . motion
  call feedkeys(cmd, 'n')  " add previous insert if cgn succeeds
  call s:feed_repeat('TagsChangeRepeat')
endfunction
function! tags#change_setup() abort
  if !exists('s:change_setup')
    return
  endif
  if empty(s:change_setup)  " change single item
    let motion = get(s:, 'change_motion', 'n')
    call feedkeys(motion, 'nt')
    call s:feed_repeat('TagsChangeRepeat')
  else  " change all items
    let b:change_winview = winsaveview()
    let cmd = 'u:keepjumps %s@' . escape(@/, '@') . '@' . escape(@., '@') . '@ge'
    call feedkeys(cmd . " | call winrestview(b:change_winview)\<CR>", 'nt')
    call s:feed_repeat(s:change_setup)
  endif
  exe 'unlet s:change_setup'
endfunction

" Change and delete next match
" Note: Undo first change so subsequent undo reverts all changes. Also note
" register may have keystrokes e.g. <80>kb (backspace) so must feed as 'typed'
" Note: Unlike 'change all', 'delete all' can simply use :substitute. Also note
" :hlsearch inside functions fails: https://stackoverflow.com/q/1803539/4970632
function! tags#change_next(level, option, ...) abort
  let [prefix, suffix] = tags#set_match(a:level, a:option)
  let iterate = a:0 && a:1
  let motion = a:level < 0 && a:option ? 'N' : 'n'
  let s:change_motion = motion
  call feedkeys('cg' . motion, 'n')
  if !iterate  " change single match
    let s:change_setup = ''
    call s:feed_repeat('TagsChangeRepeat')
  else  " change all matches
    let plural = a:level < 0 ? 'es' : 's'
    let plug = 'TagsChange' . prefix . plural . suffix
    let s:change_setup = plug
    call s:feed_repeat(plug)
  endif
endfunction
function! tags#delete_next(level, option, ...) abort
  let [prefix, suffix] = tags#set_match(a:level, a:option)
  let iterate = a:0 && a:1
  let motion = a:level < 0 && a:option ? 'N' : 'n'
  if !iterate  " delete single item
    let plug = 'TagsDelete' . prefix . suffix
    call feedkeys('dg' . repeat(motion, 2), 'n')
    call s:feed_repeat(plug)
  else  " delete all matches
    let plural = a:level < 0 ? 'es' : 's'
    let plug = 'TagsDelete' . prefix . plural . suffix
    let winview = winsaveview()
    exe 'keepjumps %s@' . escape(@/, '@') . '@@ge'
    call winrestview(winview)
    call s:feed_repeat(plug)
  endif
endfunction
