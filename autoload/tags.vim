"------------------------------------------------------------------------------
" General tag processing utiltiies
" Todo: Add tag file-reading utilities here including file sorting
" Todo: Parse ctags abbreviated kinds into long names using --machinable
" Todo: Support either strings or lists for g:tag_major_kind setting
" Warning: Encountered strange error where naming .vim/autoload file same as
" vim-tags/autoload file or naming the latter to tags.vim at all caused an autocmd
" BufRead error on startup. Was impossible to diagnose so just use alternate names.
"------------------------------------------------------------------------------
" Helper functions and variables
scriptencoding utf-8
let s:regex_magic = '[]\/.*$~'
function! s:sort_by_line(tag1, tag2) abort
  let num1 = a:tag1[1]
  let num2 = a:tag2[1]
  return num1 - num2  " >0 if greater, 0 if equal, <0 if lesser
endfunc
function! s:sort_by_name(tag1, tag2) abort
  let str1 = a:tag1[0]
  let str2 = a:tag2[0]
  return str1 <# str2 ? -1 : str1 ==# str2 ? 0 : 1  " equality, lesser, and greater
endfunction

" Return whether tag is the given kind
function! s:tag_is_major(tag, ...) abort
  return call('s:tag_is_kind', [a:tag, 'major', 'f'] + a:000)
endfunction
function! s:tag_is_minor(tag, ...) abort
  return call('s:tag_is_kind', [a:tag, 'minor', 'v'] + a:000)
endfunction
function! s:tag_is_skipped(tag, ...) abort
  return call('s:tag_is_kind', [a:tag, 'skip', '@'] + a:000)
endfunction
function! s:tag_is_kind(tag, name, value, ...) abort
  let types = get(g:, 'tags_' . a:name . '_kinds', {})
  let opts = get(types, a:0 ? a:1 : tags#lang_name(), a:value)
  if type(opts) <= 1 | let opts = split(opts, '\zs') | endif
  let kind1 = get(a:tag, 2, '')  " translate to or from character
  let kind2 = get(len(kind1) > 1 ? s:kind_chars : s:kind_names, kind1, kind1)
  return index(opts, kind1) >= 0 || index(opts, kind2) >= 0
endfunction

" Return ctags filetype or
let s:kind_names = {}
let s:kind_chars = {}
function! tags#lang_name(...) abort
  let arg = a:0 ? a:1 : ''  " default current path
  let name = getbufvar(bufnr(arg), '&filetype')
  return substitute(tolower(name), '\..*$', '', 'g')
endfunction
function! tags#kind_name(kind, ...) abort
  let key = call('tags#lang_name', a:000)
  let opts = len(a:kind) > 1 ? {} : get(s:kind_names, key, {})
  return get(opts, a:kind, a:kind)
endfunction
function! tags#kind_char(kind, ...) abort
  let key = call('tags#lang_name', a:000)
  let opts = len(a:kind) <= 1 ? {} : get(s:kind_chars, key, {})
  return get(opts, a:kind, a:kind)
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
  let ftype = a:0 ? tags#lang_name(a:1) : ''  " restricted type
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
      if !empty(ftype) && ftype !=# tags#lang_name(bnr)
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

" Filter paths matching the current or requested filetype
" Note: This lets us restrict tag sources to specific filetypes before searching
" for matches. Helps reduce false positives when tag jumping in large sessions.
" Todo: Remove this and use ctags --machinable --list-maps instead or possibly
" use -F with a given file then print the name.
function! tags#type_paths(...) abort
  let cache = {}  " cached matches
  let ftype = a:0 > 1 ? a:2 : &l:filetype
  let regex = tags#type_regex(ftype)  " auto-construct filetype regex
  let paths = a:0 && type(a:1) > 1 ? copy(a:1) : map(tags#buffer_paths(), 'v:val[1]')
  let paths = filter(paths, {idx, val -> tags#type_match(val, ftype, regex, cache)})
  return paths
endfunction
function! tags#type_regex(...) abort
  let ftype = a:0 ? a:1 : &l:filetype
  let suffix = '\<' . ftype. '\>\s*$'  " commands should end with filetype
  let regex = 'setf\(iletype\)\?\s\+' . suffix  " 'setf type' 'setfiletype type'
  let regex .= '\|\%(ft\|filetype\)\s*=\s*' . suffix  " 'set ft=type' 'set filetype=type'
  let opts = autocmd_get({'event': 'BufNewFile'})
  let opts = filter(opts, 'v:val.cmd =~# ' . string(regex))
  let opts = map(opts, 'glob2regpat(v:val.pattern)')
  return join(uniq(sort(opts)), '\|')
endfunction
function! tags#type_match(path, ...) abort
  let ftype = a:0 > 0 ? a:1 : &l:filetype  " filetype to match
  let cache = a:0 > 2 ? a:3 : {}  " entries {'path': 'type', 'path': ''}
  let fast = a:0 > 3 ? a:4 : 0  " already checked this filetype
  let path = fnamemodify(a:path, ':p')
  if has_key(cache, path)
    let ctype = cache[path]
    if !empty(ctype) || fast
      return ctype ==# ftype
    endif
  endif
  let regex = a:0 > 1 ? a:2 : tags#type_regex(ftype)
  let name = fnamemodify(path, ':t')
  let btype = tags#lang_name(path)
  if !empty(btype) && btype ==# ftype
    let imatch = 1
  elseif empty(regex)
    let imatch = 0
  elseif &fileignorecase
    let imatch = name =~? regex
  else
    let imatch = name =~# regex
  endif
  if !imatch && name !~# '\.' && a:0 && !empty(a:1) && filereadable(path)
    let head = readfile(path, '', 1)
    let head = empty(head) ? '' : get(head, 0, '')
    if head !~# '^#!'
      let imatch = 0
    else  " check shebang
      let cmd = substitute(head, '^#!.*/', '', 'g')
      let cmd = split(cmd, '', 1)[-1]
      let imatch = cmd =~# '^' . ftype . '\d*$'
      let imatch = imatch || 'name.' . cmd =~# regex
    endif
  endif
  let ctype = imatch ? ftype : !empty(btype) ? btype : ''
  let cache[path] = ctype
  return imatch
endfunction

"-----------------------------------------------------------------------------"
" Tag generation utiliities
"-----------------------------------------------------------------------------"
" Generate tag string or lists
" Note: This is used for buffer variables and unopened :ShowTags path(s)
" Note: Output should be in number mode (i.e. shows line number instead of full line)
function! s:execute_tags(path, ...) abort
  let path = empty(a:path) ? '' : fnamemodify(expand(a:path), ':p')
  let name = empty(path) ? '' : fnamemodify(path, ':t')
  let type = empty(path) ? '' : tags#lang_name(path)
  let flag = empty(type) || name =~# '\.' ? '' : '--language-force=' . shellescape(type)
  let cmd = 'ctags -f - --excmd=number ' . join(a:000, ' ') . ' ' . flag
  let cmd .= ' ' . shellescape(path) . ' 2>/dev/null'
  let cmd .= empty(path) ? '' : " | cut -d'\t' -f1,3-5 | sed 's/;\"\t/\t/g'"
  return system(cmd)
endfunction
function! s:generate_tags(path) abort
  let ftype = tags#lang_name(a:path)  " possibly empty string
  if index(g:tags_skip_filetypes, ftype) >= 0
    let items = []
  else  " generate tags
    let items = split(s:execute_tags(a:path), '\n')
  endif
  let items = map(items, "split(v:val, '\t')")
  let items = filter(items, '!s:tag_is_skipped(v:val)')
  let lines = sort(items, 's:sort_by_line')
  let names = sort(deepcopy(items), 's:sort_by_name')
  return [lines, names]
endfunction

" Update tag buffer variables and kind cache
" Note: This will only update when tag generation time more recent than last file
" save time. Also note files open in multiple windows have the same buffer number
function! s:update_kinds() abort
  let s:kind_names = {}  " mapping from e.g. 'f' to 'function'
  let s:kind_chars = {}  " mapping from e.g. 'function' to 'f'
  let items = split(s:execute_tags('', '--machinable --list-kinds-full'), '\n')
  for line in items[1:]
    let parts = split(line, '\t')
    if len(parts) < 5 | continue | endif
    let [type, char, name; rest] = parts
    let key = tolower(type)
    let opts = get(s:kind_names, key, {})
    let opts[char] = name
    let s:kind_names[key] = opts
    let opts = get(s:kind_chars, key, {})
    let opts[name] = char
    let s:kind_chars[key] = opts
  endfor
endfunction
function! tags#update_tags(...) abort
  let global = a:0 ? a:1 : 0
  if empty(s:kind_names) || empty(s:kind_chars)
    call s:update_kinds()
  endif
  if global  " global paths
    let paths = map(tags#buffer_paths(), 'v:val[1]')
  else  " local path
    let paths = [expand('%:p')]
  endif
  for path in paths
    let bnr = bufnr(path)  " buffer unique to path
    let time = getbufvar(bnr, 'tags_update_time', 0)
    if getftime(path) < time | continue | endif
    let items = s:generate_tags(path)  " items by line and name
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
    let types = uniq(sort(keys(umajor) + keys(uminor)))
    let major = map(copy(types), {idx, val -> val . ' ' . string(get(umajor, val, 'f'))})
    let minor = map(copy(types), {idx, val -> val . ' ' . string(get(uminor, val, 'v'))})
    let major = ['default ' . string('f')] + major
    let minor = ['default ' . string('v')] + minor
    let types = uniq(map(tags#buffer_paths(), 'tags#lang_name(v:val[1])'))
    let label = 'all buffer filetypes'
  elseif a:0  " input filetype(s)
    let types = uniq(sort(map(copy(a:000), 'tags#lang_name(v:val)')))
    let flag = len(types) == 1 ? types[0] : 'all'
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
  let table = s:execute_tags('', '--list-kinds=' . shellescape(flag))
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
" let table = system(s:execute_tags(path) . ' | tr -s $''\t'' | column -t -s $''\t''')
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
    let items = empty(items) ? s:generate_tags(path)[1] : items  " try to generate
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
" Return index of input tag in the stack
" Note: This is used to manually update the tag stack index, allowing us to emulate
" native vim :tag with tags#iter_tags(1, ...) and :pop with tags#iter_tags(-1, ...).
function! s:tag_index(name, ...) abort  " stack index
  let direc = a:0 ? a:1 : 0
  let stack = gettagstack(winnr())
  let items = get(stack, 'items', [])
  let idxs = []  " exact tag matches
  for idx in range(len(items))  " search tag stack
    let item = items[idx]
    let name = get(item, 'tagname', '')
    let bnr = get(item, 'bufnr', 0)
    if name ==# a:name && bnr == bufnr()
      call add(idxs, idx)
    endif
  endfor
  return empty(idxs) ? -1 : direc < 0 ? idxs[0] : idxs[-1]
endfunction

" Return tags in the format '[<file>: ]<line>: name (type[, scope])'
" for selection by fzf. File name included only if 'global' was passed.
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
let s:path_names = {}
let s:path_roots = {}
function! s:path_name(path) abort
  let path = fnamemodify(a:path, ':p')
  let name = get(s:path_names, path, '')
  if !empty(name) | return name | endif
  let git = exists('*FugitiveExtractGitDir') ? FugitiveExtractGitDir(path) : ''
  let base = fnamemodify(git, ':h')  " remove '.git' heading
  let root = fnamemodify(fnamemodify(base, ':h'), ':p')  " root with trailing slash
  let igit = !empty(git) && strpart(path, 0, len(base)) ==# base
  let icwd = !empty(git) && strpart(getcwd(), 0, len(base)) ==# base
  if igit && !icwd
    let name = strpart(path, len(root)) | let s:path_roots[name] = root
  elseif exists('*RelativePath')
    let name = RelativePath(path)
  else  " default display
    let name = fnamemodify(path, ':~:.')
  endif
  let s:path_names[path] = name
  return name
endfunction
function! s:tag_source(level, ...) abort
  let s:path_roots = {}
  let s:path_names = {}
  let source = []
  let show = type(a:level) > 1 ? 1 : a:level  " whether to show path
  if a:0 && type(a:1) > 1  " user input tags
    let paths = ['']
  elseif type(a:level) > 1  " user input paths
    let paths = deepcopy(a:level)
  elseif a:level > 1  " global paths
    let paths = map(tags#buffer_paths(), 'v:val[1]')
  elseif a:level > 0  " filetype paths
    let paths = map(tags#buffer_paths(bufname()), 'v:val[1]')
  else  " local path
    let paths = [expand('%:p')]
  endif
  for path in paths
    if a:0 && type(a:1) > 1  " [line, name, other] or [path, line, name, other]
      let [opts, print] = [deepcopy(a:1), 1]
    else  " note buffer number is unique to path (i.e. windows show same buffer)
      let opts = deepcopy(getbufvar(bufnr(path), 'tags_by_name', []))
      call map(opts, '[v:val[1], v:val[0]] + v:val[2:]')
      call map(opts, show ? 'insert(v:val, path, 0)' : 'v:val')
    endif
    if a:0 && !empty(a:1)  " line:name (other) or file:line:name (other)
      " vint: -ProhibitUsingUndeclaredVariable
      let [idx, jdx, kdx, fmt] = show ? [2, 3, 4, '%s:'] : [1, 2, 3, '']
      call map(opts, 'v:val[:idx] + [tags#kind_char(v:val[jdx])] + v:val[kdx:]')
      call map(opts, show ? '[s:path_name(v:val[0])] + v:val[1:]' : 'v:val')
      call map(opts, 'add(v:val[:idx], join(v:val[jdx:], ", "))')
      call map(opts, 'call("printf", [' . string(fmt . '%4d: %s (%s)') . '] + v:val)')
    endif
    call extend(source, uniq(opts))  " ignore duplicates
  endfor
  return source
endfunction

" Navigate to input tag list or fzf selection
" Note: Here optionally preserve jumps triggered by line change, and try
" to position cursor on exact match instead of start-of-line.
function! tags#goto_tag(...) abort  " :tag <name> analogue
  return call('s:goto_tag', [0] + a:000)
endfunction
function! tags#jump_tag(iter, ...) abort  " 1:naked tag/pop, 2:bracket jump
  return call('s:goto_tag', [a:iter] + a:000)
endfunction
function! s:goto_tag(mode, ...) abort
  " Parse tag input
  let raw = '^\s*\(.\{-}\) *\t\(.\{-}\) *\t\(\d\+\)'
  let raw .= ';"\s*\(.\{-}\)\%( *\t\(.*\)\)\?$'
  let regex = '^\%(\(.\{-}\):\)\?'  " tag file
  let regex .= '\s*\(\d\+\):\s\+'  " tag line
  let regex .= '\(.\{-}\)\s\+'  " tag name
  let regex .= '(\(\w\+\%(,\s\+.\{-}\)\?\))$'  " tag kind and scope
  let from = getpos('.')  " from position
  let from[0] = bufnr()  " ensure correct buffer
  let path = expand('%:p')  " current path
  let isrc = ''  " reference file
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
  elseif !empty(isrc)  " relative to tags file
    let ipath = fnamemodify(fnamemodify(isrc, ':p:h'), ':p') . ibuf
  elseif has_key(s:path_roots, ibuf)  " relative to git repo
    let ipath = s:path_roots[ibuf] . ibuf
  else  " absolute path
    let ipath = fnamemodify(ibuf, ':p')
  endif
  if ipath ==# path  " record mark
    exe a:mode && g:tags_keep_jumps || getpos("''") == getpos('.') ? '' : "normal! m'"
  elseif exists('*file#open_drop')  " dotfiles utility
    silent call file#open_drop(ipath)
  else  " built-in utility
    silent exe 'tab drop ' . fnameescape(ipath)
  endif
  " Jump to tag position
  let [lnum, cnum] = type(ipos) == type([]) ? ipos : [ipos, 0]
  let g:tag_name = [ipath, ipos, iname]  " save for vim stacks
  call cursor(lnum, 1)
  if cnum <= 0
    let regex = escape(iname, s:regex_magic)
    silent call search(regex, 'cW', lnum)
  elseif cnum > 1
    let motion = (cnum - 1) . 'l'
    exe 'normal! ' . motion
  endif
  if !a:mode && !g:tags_keep_stack && iname !=# '<top>'  " perform :tag <name>
    let item = {'bufnr': bufnr(), 'from': from, 'matchnr': 1, 'tagname': iname}
    if item.bufnr != from[0] || lnum != from[1]  " push from curidx to top
      call settagstack(winnr(), {'items': [item]}, 't')
    endif
  elseif abs(a:mode) == 1  " perform :tag or :pop
    let idx = s:tag_index(iname, a:mode)
    if idx > 0  " assign new stack index
      call settagstack(winnr(), {'curidx': idx})
    endif
  endif
  let type = a:mode ? '\<block\>' : '\<tag\>'
  exe &l:foldopen !~# type ? 'normal! zz' : 'normal! zvzz'
  exe a:mode && g:tags_keep_jumps || getpos("''") == getpos('.') ? '' : "normal! m'"
  let suffix = type(irest) <= 1 ? irest : get(irest, 0, '')
  let suffix = empty(irest) ? '' : ' (' . suffix . ')'
  redraw | echom 'Tag: ' . iname . suffix
endfunction

" Find the tag closest to the input position
" Note: Here modify &tags temporarily since taglist() seems to search all tagfiles()
" even when input path is outside of tag file path (can be slow). Also note input
" argument interprets regex i.e. behaves like :tags /<name> (see :help taglist())
function! tags#get_tags(name, ...) abort
  let path = expand(a:0 ? a:1 : '%')
  let paths = call('tags#get_files', a:000)
  let regex = '^' . escape(a:name, s:regex_magic) . '$'
  let sorted = join(map(paths, {idx, val -> escape(val, ',')}), ',')
  let unsorted = &l:tags
  try
    let &l:tags = sorted
    return taglist(regex, path)
  finally
    let &l:tags = unsorted
  endtry
endfunction
function! tags#get_files(...) abort  " 
  let strict = a:0 > 1 ? a:2 : 0
  let source = a:0 > 0 ? a:1 : ''
  let source = expand(empty(source) ? '%' : source)
  let head = fnamemodify(source, ':p')  " initial value
  let paths = map(tagfiles(), {idx, val -> fnamemodify(val, ':p')})
  let heads = map(copy(paths), {idx, val -> fnamemodify(val, ':h')})
  let result = []  " filtered tag files
  while v:true
    let ihead = fnamemodify(head, ':h')
    if empty(ihead) || ihead ==# head | break | endif
    let head = ihead  " tag file candidate
    let idx = index(heads, head)
    if idx >= 0 | call add(result, paths[idx]) | endif
  endwhile
  if !strict  " other paths lower priority
    call extend(result, filter(paths, 'index(result, v:val) < 0'))
  endif
  return result
endfunction
function! tags#find_tag(...) abort
  let pos = a:0 > 0 ? a:1 : line('.')
  let bnum = type(pos) > 1 && !empty(pos[0]) ? bufnr(pos[0]) : bufnr()
  let lnum = type(pos) > 1 ? pos[1] : type(pos) ? str2nr(pos) : pos
  let major = a:0 > 1 ? a:2 : 0
  let forward = a:0 > 2 ? a:3 : 0
  let circular = a:0 > 3 ? a:4 : 0
  if major  " major tags only
    let filt = 'len(v:val) == 3 && s:tag_is_major(v:val)'
  else  " all except minor
    let filt = 'len(v:val) > 2 && !s:tag_is_minor(v:val)'
  endif
  let items = getbufvar(bnum, 'tags_by_line', [])
  let items = filter(copy(items), filt)
  if empty(items)
    return []  " silent failure
  endif
  if circular && forward && lnum >= items[-1][1]
    let idx = 0
  elseif circular && !forward && lnum <= items[0][1]
    let idx = -1
  else  " search in between (endpoint inclusive)
    let idx = forward ? 0 : -1
    for jdx in range(1, len(items) - 1)
      if forward && lnum >= items[-jdx - 1][1]
        let idx = -jdx | break
      endif
      if !forward && lnum < items[jdx][1]
        let idx = jdx - 1 | break
      endif
    endfor
  endif
  let [name, lnum, kind; rest] = items[idx]
  let kind = tags#kind_char(kind)
  return [name, lnum, kind] + rest
endfunction

" Select a specific tag using fzf
" See: https://github.com/ludovicchabant/vim-gutentags/issues/349
" Note: Usage is tags#select_tag(paths_or_level, options_or_iter) where second
" argument indicates whether stacks should be updated (tags#goto_tag) or not
" (tags#jump_tag) and first argument indicates the paths to search and whether to
" display the path in the fzf prompt. The second argument can also be a list of tags
" in the format [line, name, other] (or [path, line, name, other] if level > 0)
function! tags#push_tag(iter, item) abort
  let name = a:iter ? 'tags#jump_tag' : 'tags#goto_tag'
  if exists('*stack#push_stack')
    let arg = a:iter ? type(a:item) > 1 ? [a:iter] + a:item : [a:iter, a:item] : a:item
    return stack#push_stack('tag', name, arg, 0)
  else
    let arg = a:iter ? [a:iter, a:item] : [a:item]
    return call(name, arg)
  endif
endfunction
function! tags#select_tag(level, ...) abort
  let input = a:0 && !empty(a:1)
  let iter = a:0 > 1 ? a:2 : 0
  let char = input || type(a:level) > 1 ? 'S' : a:level < 1 ? 'B' : a:level < 2 ? 'F' : ''
  let source = s:tag_source(a:level, input ? a:1 : 1)
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
  let options = {
    \ 'source': source,
    \ 'sink': function('tags#push_tag', [iter]),
    \ 'options': '--no-sort --prompt=' . string(char . 'Tag> ')
  \ }
  call fzf#run(fzf#wrap(options))
endfunction

"-----------------------------------------------------------------------------"
" Tag navigation utilities
"-----------------------------------------------------------------------------"
" Get the 'current' tag definition under or preceding the cursor
" Note: This is used with statusline and :CurrentTag
function! tags#current_tag(...) abort
  let lnum = line('.')
  let info = tags#find_tag(lnum, 0, 0, 0)
  let full = a:0 ? a:1 : 1  " print full tag
  if empty(info)
    let parts = []
  elseif !full || len(info) == 3
    let parts = [info[2], info[0]]
  else  " include extra information
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
    let tag = call('tags#find_tag', args)
    if empty(tag)
      redraw | echohl WarningMsg
      echom 'Error: Next tag not found'
      echohl None | return
    endif
    let args[0] = str2nr(tag[1])  " adjust line number
  endfor
  call tags#jump_tag(2, tag[1], tag[0])  " jump to line then name
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
  let level = a:0 ? a:1 : 0
  let path = expand('%:p')
  let keys = &l:iskeyword
  let names = a:000[1:]
  if empty(names)  " tag names
    let mods = get(s:keyword_mods, &l:filetype, '')
    let mods = split(mods, '\zs')
    try
      let &l:iskeyword = join([keys] + mods, ',')
      let names = [expand('<cword>'), expand('<cWORD>')]
    finally
      let &l:iskeyword = keys
    endtry
  endif
  for name in names  " several attempts
    let name = substitute(name, '\(^\s*\|\s*$\)', '', 'g')
    if empty(name) | return | endif
    let itags = tags#get_tags(name, path)
    for itag in itags  " search 'tags' files
      let ipath = fnamemodify(itag.filename, ':p')
      if level < 1 && ipath !=# path | continue | endif
      let itype = tags#type_paths([ipath], &l:filetype)
      if level < 2 && empty(itype) | continue | endif
      return tags#push_tag(0, [ipath, itag.cmd, itag.name, itag.kind])
    endfor
    let itags = s:tag_source(level, 0)  " search all files
    for [ipath, iline, iname; irest] in itags
      if name !=# iname | continue | endif
      return tags#push_tag(0, [ipath, iline, iname] + irest)
    endfor
  endfor
  redraw | echohl ErrorMsg
  echom 'Error: Tag ' . string(names[0]) . ' not found'
  echohl None | return 1
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
  let items = get(b:, 'tags_by_line', [])
  let items = filter(copy(items), 's:tag_is_major(v:val)')
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
