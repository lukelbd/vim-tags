"-----------------------------------------------------------------------------"
" General tag processing utiltiies {{{1
"-----------------------------------------------------------------------------"
" Todo: Add tag file-reading utilities here including file sorting
" Note: Encountered strange error where naming .vim/autoload file same as
" vim-tags/autoload file or naming the latter to tags.vim at all caused an autocmd
" BufRead error on startup. Was impossible to diagnose so just use alternate names.
scriptencoding utf-8
let s:regex_magic = '[]\/.*$~'
let s:keyword_mods = {'vim': ':', 'tex': ':-'}
function! s:sort_by_line(tag1, tag2) abort
  let num1 = a:tag1[1]
  let num2 = a:tag2[1]
  return num1 - num2  " >0 if greater, 0 if equal, <0 if lesser
endfunction
function! s:sort_by_name(tag1, tag2) abort
  let str1 = a:tag1[0]
  let str2 = a:tag2[0]
  return str1 <# str2 ? -1 : str1 ==# str2 ? 0 : 1  " equality, lesser, and greater
endfunction
function! s:filter_buffer(...) abort
  let bnr = a:0 > 0 ? a:1 : bufnr()
  let ftype = a:0 > 1 ? a:2 : ''
  let btype = getbufvar(bnr, '&filetype')
  let info = get(getwininfo(bufwinid(bnr)), 0, {})
  if !empty(win_gettype()) || get(info, 'terminal', 0) || get(info, 'quickfix', 0)
    return 0
  endif
  if empty(btype) || !empty(ftype) && ftype !=# btype  " type required
    return 0
  endif
  if !filereadable(expand('#' . bnr . ':p'))  " file required
    return 0
  endif
  if index(get(g:, 'tags_skip_filetypes', []), btype) != -1  " additional skips
    return 0
  endif | return 1
endfunction

" Return whether tag is the given kind
function! tags#is_major(tag, ...) abort
  return call('s:tag_is_kind', [a:tag, 'major', 'f'] + a:000)
endfunction
function! tags#is_minor(tag, ...) abort
  return call('s:tag_is_kind', [a:tag, 'minor', 'v'] + a:000)
endfunction
function! tags#is_skipped(tag, ...) abort
  return call('s:tag_is_kind', [a:tag, 'skip', '@'] + a:000)
endfunction
function! s:tag_is_kind(tag, name, default, ...) abort
  let name = 'tags_' . a:name . '_kinds'  " setting name
  let lang = call('tags#lang_name', a:000)
  let opts = get(get(g:, name, {}), lang, a:default)
  let kind0 = get(a:tag, 2, '')  " translate to or from character
  let kinds = len(kind0) > 1 ? g:tags_kind_chars : g:tags_kind_names
  let kind1 = get(get(kinds, lang, {}), kind0, kind0)
  if type(opts) > 1
    return index(opts, kind0) >= 0 || index(opts, kind1) >= 0
  elseif len(kind0) > 1  " faster than splitting (important for statusline)
    return kind0 ==# opts || kind1 =~# '^[' . opts . ']$'
  else  " full name or string of chatacters
    return kind1 ==# opts || kind0 =~# '^[' . opts . ']$'
  endif
endfunction

" Return ctags kind or language
let g:tags_kind_chars = {}
let g:tags_kind_names = {}
let g:tags_kind_langs = {}
function! tags#kind_char(kind, ...) abort
  let name = call('tags#lang_name', a:000)
  let opts = len(a:kind) <= 1 ? {} : get(g:tags_kind_chars, name, {})
  return get(opts, a:kind, a:kind)
endfunction
function! tags#kind_name(kind, ...) abort
  let name = call('tags#lang_name', a:000)
  let opts = len(a:kind) > 1 ? {} : get(g:tags_kind_names, name, {})
  return get(opts, a:kind, a:kind)
endfunction
function! tags#lang_name(...) abort
  let bnr = call('bufnr', a:000)
  let name = getbufvar(bnr, 'tags_lang_name', '')
  if !empty(name) | return name | endif  " speedup for statusline
  let type = tolower(getbufvar(bnr, '&filetype', ''))
  let type = substitute(type, '\..*$', '', 'g')
  let name = get(g:tags_kind_langs, type, type)
  call setbufvar(bnr, 'tags_lang_name', name)
  return name
endfunction

"-----------------------------------------------------------------------------"
" Buffer listing utilities {{{1
"-----------------------------------------------------------------------------"
" Return buffers sorted by access time
" Note: This optionally filters out tabs accessed after 'startup time' determined
" from files with smallest access times and within 10 seconds of each other.
function! tags#get_recents(...) abort
  let nostartup = a:0 > 0 ? a:1 : 0
  let filter = a:0 > 1 ? a:2 : 0
  let ftype = a:0 > 2 ? a:3 : ''
  let mintime = 0  " default minimum time
  let bufs = map(getbufinfo(), {idx, val -> [val.bufnr, get(val, 'lastused', 0)]})
  if nostartup  " auto-detect threshold for sorting
    for btime in sort(map(copy(bufs), 'v:val[1]'))  " approximate loading time
      if mintime && btime - mintime > 10 | break | endif | let mintime = btime
    endfor
  endif
  let recent = []  " buffers used after mintime
  for [bnr, btime] in bufs
    if filter && !s:filter_buffer(bnr, ftype)
      continue
    endif
    if btime > mintime
      call add(recent, [bnr, btime])
    endif
  endfor
  let recent = sort(recent, {val1, val2 -> val2[1] - val1[1]})
  return map(recent, 'v:val[0]')
endfunction

" Return buffers sorted by proximity to current tab
" Note: This optionally filters out buffers not belonging to the active
" filetype used for :tag-style definition jumping across multiple windows.
function! tags#get_neighbors(...) abort
  let tnr = tabpagenr()  " active tab
  let tleft = tnr
  let tright = tnr - 1  " initial value
  let filter = a:0 > 0 ? a:1 : 0
  let ftype = a:0 > 1 ? a:2 : ''
  let bufs = []  " buffer numbers
  while v:true
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
      if filter && !s:filter_buffer(bnr, ftype)
        continue
      endif
      if index(bufs, bnr) == -1
        call add(bufs, bnr)  " one entry per buffer
      endif
    endfor
  endwhile
  return bufs
endfunction

" Return [tab, buffer] pairs sorted by recent use
" Note: This sorts buffers using three methods: first by recent use among the
" author's vimrc 'tab stack' utility, second by recent use among all other tabs,
" and third by physical proximity to the current tab. Useful for fzf selection.
function! tags#get_paths(...) abort
  let ftype = a:0 ? a:1 : ''  " ensure filtering
  let stack = get(g:, 'tab_stack', [])  " stack of absolute paths
  let stack = map(copy(stack), 'bufnr(v:val)')
  let brecent = tags#get_recents(1, 1, ftype)  " sorted after startup, filtered
  let bnearby = tags#get_neighbors(1, ftype)  " sorted by proximity, filtered
  let idxs = []  " recorded nearby buffers
  let stacked = []  " sorted by access time
  let temporal = []  " sorted by access time
  let physical = []  " ordered by adjacency
  for bnr in brecent  " after startup
    let idx = index(bnearby, bnr)
    if idx == -1 | continue | endif  " i.e. not displayed
    let path = expand('#' . bnr . ':p')
    let items = index(stack, bnr) == -1 ? temporal : stacked
    call add(idxs, idx)
    call add(items, path)
  endfor
  for idx in range(len(bnearby))
    let jdx = index(idxs, idx)
    if jdx != -1 | continue | endif
    let bnr = bnearby[idx]
    let path = expand('#' . bnr . ':p')
    call add(physical, path)
  endfor
  let pairs = stacked + temporal + physical
  return pairs  " prefer most recently visited then closest
endfunction

" Filter paths matching the current or requested filetype
" Note: This lets us restrict tag sources to specific filetypes before searching
" for matches. Helps reduce false positives when tag jumping in large sessions.
" Todo: Remove this and use ctags --machinable --list-maps instead or possibly
" use -F with a given file then print the name.
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
  let path = fnamemodify(a:path, ':p')
  let name = fnamemodify(path, ':t')
  let regex = tags#type_regex(ftype)
  let btype = getbufvar(bufnr(path), '&filetype', '')
  if empty(ftype) || btype ==# ftype
    let imatch = 1
  elseif empty(regex)
    let imatch = 0
  elseif &fileignorecase
    let imatch = name =~? regex
  else
    let imatch = name =~# regex
  endif
  if !imatch && name !~# '\.' && filereadable(path)
    let head = readfile(path, '', 1)
    let head = empty(head) ? '' : get(head, 0, '')
    if head !~# '^#!'
      let imatch = 0
    else  " check shebang
      let cmd = substitute(head, '^#!.*/', '', 'g')
      let cmd = split(cmd, '', 1)[-1]
      let imatch = cmd =~# '^' . ftype . '\d*$'
      let imatch = imatch || 'file.' . cmd =~# regex
    endif
  endif
  let itype = imatch ? ftype : !empty(btype) ? btype : ''
  return imatch
endfunction

"-----------------------------------------------------------------------------"
" Tag generation utiliities {{{1
"-----------------------------------------------------------------------------"
" Generate tag string or lists
" Note: This is used for buffer variables and unopened :ShowTags path(s)
" Note: Output should be in number mode (i.e. shows line number instead of full line)
function! s:execute_tags(path, ...) abort
  let path = empty(a:path) ? '' : fnamemodify(expand(a:path), ':p')
  let flag = empty(a:path) ? '' : tags#lang_name(path)
  let flag = empty(flag) || fnamemodify(path, ':t') =~# '\.' ? '' : '--language-force=' . flag
  let cmd = 'ctags -f - --excmd=number ' . join(a:000, ' ') . ' ' . flag
  let cmd .= ' ' . shellescape(path) . ' 2>/dev/null'
  let cmd .= empty(path) ? '' : " | cut -d'\t' -f1,3-5 | sed 's/;\"\t/\t/g'"
  return system(cmd)
endfunction
function! s:generate_tags(path) abort
  let ftype = getbufvar(bufnr(a:path), '&filetype')  " possibly empty string
  if !empty(ftype) && index(get(g:, 'tags_skip_filetypes', []), ftype) < 0
    let items = split(s:execute_tags(a:path), '\n')
  else  " skip generating tags
    let items = []
  endif
  let expr = 'len(v:val) >= 2 && !tags#is_skipped(v:val)'
  let expr .= ftype ==# 'json' ? ' && v:val[0] !~# ''^\d\+$''' : ''
  let items = filter(map(items, "split(v:val, '\t')"), expr)
  let lines = sort(items, 's:sort_by_line')
  let names = sort(deepcopy(items), 's:sort_by_name')
  return [lines, names]
endfunction
function! tags#execute(...) abort
  return call('s:execute_tags', a:0 ? a:000 : [expand('%')])
endfunction
function! tags#generate(...) abort
  return call('s:generate_tags', a:000)
endfunction

" Return tag files and tags from tag files prioritized by project
" Note: Here tagfiles() function returns buffer-local variables so use &g:tags instead,
" and note that literal commas/spaces preced by backslash (see :help option-backslash).
" Note: Here taglist() uses path only to prioritize tags (i.e. does not filter) and
" name is treated as a regex as with :tags /<name> (see :help taglist()).
function! tags#tag_list(name, ...) abort
  let regex = escape(a:name, s:regex_magic)
  let regex = '^' . regex . '$'
  let path = expand(a:0 ? a:1 : '%')
  let tags = call('tags#tag_files', a:000)
  call map(tags, {_, val -> substitute(val, '\(,\| \)', '\\\1', 'g')})
  let [itags, jtags] = [&l:tags, join(tags, ',')]
  try  " restrict to current project
    let &l:tags = jtags
    return taglist(regex, path)
  finally
    let &l:tags = itags
  endtry
endfunction
function! tags#tag_files(...) abort
  let strict = a:0 > 1 ? a:2 : 0
  let source = a:0 > 0 ? a:1 : ''
  let source = expand(empty(source) ? '%' : source)
  let head = fnamemodify(source, ':p')  " initial value
  let tags = split(&g:tags, '\\\@<!,')  " see above
  call map(tags, {_, val -> substitute(val, '\\\(,\| \)', '\1', 'g')})
  call map(tags, {_, val -> fnamemodify(val, ':p')})
  let heads = map(copy(tags), {_, val -> fnamemodify(val, ':h')})
  let result = []  " filtered tag files
  while v:true
    let ihead = fnamemodify(head, ':h')
    if empty(ihead) || ihead ==# head | break | endif
    let idx = index(heads, ihead)
    if idx >= 0 | call add(result, tags[idx]) | endif
    let head = ihead  " tag file candidate
  endwhile
  if !strict  " other paths lower priority
    call extend(result, filter(tags, 'index(result, v:val) < 0'))
  endif
  return result
endfunction

" Update tag buffer variables and kind global variables
" Todo: Make this asyncronous to speed up startup in huge sessions.
" Note: This will only update when tag generation time more recent than last file
" save time. Also note files open in multiple windows have the same buffer number
" Note: Ctags has both language 'aliases' for translating internal options like
" --language-force and 'mappings' that convert file names to languages. Seems alias
" definitions were developed with vim in mind so no need to use their extensions.
function! tags#update_tags(...) abort
  let global = a:0 ? a:1 : 0
  if empty(g:tags_kind_names) || empty(g:tags_kind_chars)
    call tags#update_kinds()
  endif
  if global  " global paths
    let paths = tags#get_paths()
  else  " local path
    let paths = s:filter_buffer() ? [expand('%:p')] : []
  endif
  for path in paths
    let bnr = bufnr(path)  " buffer unique to path
    let time = getbufvar(bnr, 'tags_update_time', 0)
    let items = getbufvar(bnr, 'tags_by_line', [])
    if !empty(items) && getftime(path) < time | continue | endif
    let items = s:generate_tags(path)  " items by line and name
    call setbufvar(bnr, 'tags_by_line', items[0])
    call setbufvar(bnr, 'tags_by_name', items[1])
    call setbufvar(bnr, 'tags_update_time', localtime())
  endfor
endfunction
function! tags#update_kinds() abort
  let g:tags_kind_names = {}  " mapping from e.g. 'f' to 'function'
  let g:tags_kind_chars = {}  " mapping from e.g. 'function' to 'f'
  let g:tags_kind_langs = {'python2': 'python', 'python3': 'python'}
  let head = '--machinable --with-list-header=no '
  let items = split(s:execute_tags('', head . '--list-aliases'), '\n')
  for line in items
    let parts = split(line, '\t')
    if len(parts) != 2 | continue | endif
    let [name, alias] = map(parts, 'tolower(v:val)')
    if alias =~# '\*' | continue | endif  " currently only python[23]*
    let g:tags_kind_langs[alias] = name
  endfor
  let items = split(s:execute_tags('', head . '--list-kinds-full'), '\n')
  for line in items
    let parts = split(line, '\t')
    if len(parts) < 5 | continue | endif
    let [type, char, name; rest] = parts
    let key = tolower(type)
    let opts = get(g:tags_kind_names, key, {})
    let opts[char] = name
    let g:tags_kind_names[key] = opts
    let opts = get(g:tags_kind_chars, key, {})
    let opts[name] = char
    let g:tags_kind_chars[key] = opts
  endfor
endfunction

" Show the current file tags
" Note: This tries to read existing buffer variables to improve speed
function! tags#table_tags(...) abort
  if index(a:000, 'all') >= 0  " all open paths
    let paths = tags#get_paths()
    let label = 'all open paths'
  elseif a:0  " input path(s)
    let paths = copy(a:000)
    let label = 'input path(s) ' . join(map(copy(paths), 'string(v:val)'), ', ')
  else  " current path
    let paths = [expand('%:p')]
    let label = 'current path ' . string(paths[0])
  endif
  let tables = []
  for path in paths  " relative paths
    if !filereadable(path)
      let types = getcompletion(path, 'filetype')  " https://vi.stackexchange.com/a/14990/8084
      if index(types, path) < 0
        let msg = 'Warning: Path ' . string(path) . ' not open or not readable'
        redraw | echohl WarningMsg | echom msg | echohl None
      endif | continue
    endif
    let table = ''  " intialize table
    let items = getbufvar(bufnr(path), 'tags_by_name', [])  " prefer from buffer
    let items = empty(items) ? s:generate_tags(path)[1] : items  " generate tags
    if !empty(items) && len(paths) > 1
      let table .= exists('*RelativePath') ? RelativePath(path) : fnamemodify(path, ':~:.')
      let table .= "\n"
    endif
    for [name, line, kind; context] in items
      let kind = len(paths) == 1 ? kind : '    ' . kind
      let name = empty(context) ? name : name . ' (' . join(context, ' ') . ')'
      let table .= kind . ' ' . repeat(' ', 4 - len(line)) . line . ': ' . name . "\n"
    endfor
    if !empty(trim(table)) | call add(tables, trim(table)) | endif
  endfor
  if empty(tables)
    let msg = 'Error: Tags not found or not available'
    redraw | echohl ErrorMsg | echom msg | echohl None | return ''
  endif
  return 'Tags for ' . label . ":\n" . join(tables, "\n")
endfunction

" Show the current file kinds
" Note: Ctags cannot show specific filetype kinds so instead filter '--list-kinds=all'
" Note: See https://stackoverflow.com/a/71334/4970632 for difference between \r and \n
function! tags#table_kinds(...) abort
  let umajor = copy(get(g:, 'tags_major_kinds', []))
  let uminor = copy(get(g:, 'tags_minor_kinds', []))
  if index(a:000, 'all') >= 0  " all open filetypes
    let [flag, langs] = ['all', uniq(sort(keys(umajor) + keys(uminor)))]
    let major = map(copy(langs), {idx, val -> val . ' ' . string(get(umajor, val, 'f'))})
    let minor = map(copy(langs), {idx, val -> val . ' ' . string(get(uminor, val, 'v'))})
    let major = ['default ' . string('f')] + major
    let minor = ['default ' . string('v')] + minor
    let langs = uniq(map(tags#get_paths(), 'tags#lang_name(v:val)'))
    let label = 'all buffer filetypes'
  elseif a:0  " input filetype(s)
    let langs = uniq(sort(map(copy(a:000), 'tags#lang_name(v:val)')))
    let flag = len(langs) == 1 ? langs[0] : 'all'
    let major = map(copy(langs), {idx, val -> val . ' ' . string(get(umajor, val, 'f'))})
    let minor = map(copy(langs), {idx, val -> val . ' ' . string(get(uminor, val, 'v'))})
    let label = 'input filetype(s) ' . join(map(copy(langs), 'string(v:val)'), ', ')
  else  " current filetype
    let flag = &l:filetype
    let langs = [&l:filetype]
    let major = [string(get(umajor, flag, 'f'))]
    let minor = [string(get(uminor, flag, 'v'))]
    let label = 'current filetype ' . string(&filetype)
  endif
  let table = s:execute_tags('', '--list-kinds=' . shellescape(flag))
  if flag ==# 'all'  " filter particular filetypes
    let regex = '\c\(\%(\n\|^\)\@<=\%(' . join(langs, '\|') . '\)\n'
    let regex = regex . '\%(\s\+[^\n]*\%(\n\|$\)\)*\)\S\@!'
    let [l:subs, append] = [[], '\=add(l:subs, submatch(0))']
    call substitute(table, regex, append, 'gn') | let table = join(l:subs, '')
  endif
  let title = 'Tag kinds for ' . label
  let major = 'Major tag kinds: ' . join(major, ' ')
  let minor = 'Minor tag kinds: ' . join(minor, ' ')
  let table = empty(trim(table)) ? '' : "\n" . trim(table)
  return title . ":\n" . major . "\n" . minor . table
endfunction

"-----------------------------------------------------------------------------"
" Tag selection utiltiies {{{1
"-----------------------------------------------------------------------------"
" Return or set the tag stack index
" Note: This is used to manually update the tag stack index, allowing us to emulate
" native vim :tag with tags#iter_tags(1, ...) and :pop with tags#iter_tags(-1, ...).
function! s:get_index(mode, name) abort  " stack index
  let stack = gettagstack(winnr())
  let items = get(stack, 'items', [])
  let idxs = []  " exact tag matches
  for idx in range(len(items))
    let item = items[idx]  " search tag stack
    if item.tagname ==# a:name && item.bufnr == bufnr()
      call add(idxs, idx)
    endif
  endfor
  return empty(idxs) ? -1 : a:mode < 0 ? idxs[0] : idxs[-1]
endfunction
function! s:set_index(mode, name, lnum, from) abort
  if a:mode > 1 && empty(get(g:, 'tags_keep_stack', 0))  " perform :tag <name>
    let item = {'bufnr': bufnr(), 'from': a:from, 'matchnr': 1, 'tagname': a:name}
    if item.bufnr != a:from[0] || a:lnum != a:from[1]  " push from curidx to top
      call settagstack(winnr(), {'items': [item]}, 't')
    endif
  else  " perform :tag or :pop
    let idx = s:get_index(a:mode, a:name)
    if idx > 0  " assign new stack index
      call settagstack(winnr(), {'curidx': idx})
    endif
  endif
endfunction

" Return truncated paths
" Note: This truncates tag paths as if they were generated by gutentags and written
" to tags files. If root finder unavailable also try relative to git repository.
function! s:get_name(path, ...) abort
  let cache = a:0 > 0 ? a:1 : {}  " cached names
  let path = fnamemodify(a:path, ':p')
  if has_key(cache, path)
    return cache[path]
  endif
  let root = getbufvar(bufnr(path), 'gutentags_root', '')  " see also statusline.vim
  if empty(root) && exists('*gutentags#get_project_root')
    let root = gutentags#get_project_root(a:path)  " standard gutentags algorithm
  endif
  let path_in_cwd = strpart(getcwd(), 0, len(root)) ==# root
  let path_in_root = strpart(path, 0, len(root)) ==# root
  let root = path_in_root && !path_in_cwd ? fnamemodify(root, ':p') : ''
  if empty(root)  " truncated path
    let name = exists('*RelativePath') ? RelativePath(path) : fnamemodify(path, ':~:.')
  else  " relative to root
    let name = strpart(path, len(root))
  endif
  let cache[path] = name | return name
endfunction

" Return tags in the format '[<file>: ]<line>: name (type[, scope])'
" for selection by fzf. File name included only if 'global' was passed.
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
function! s:tag_source(level, ...) abort
  if a:0 && type(a:1)  " user input tags
    let paths = ['']
  elseif type(a:level)  " user input paths
    let paths = deepcopy(a:level)
  elseif a:level > 1  " global paths
    let paths = tags#get_paths()
  elseif a:level > 0  " filetype paths
    let paths = tags#get_paths(&l:filetype)
  else  " local path
    let paths = [expand('%:p')]
  endif
  let [result, cache] = [[], {}]  " path name caches
  for path in paths
    let bnr = bufnr(expand(path))  " e.g. expand tilde
    let items = getbufvar(bnr, 'tags_by_name', [])
    if a:0 && type(a:1)  " user-input [path, line, name, other]
      let items = deepcopy(a:1)
    else  " [name, line, other] -> [path, line, name, other]
      let items = map(deepcopy(items), '[path, v:val[1], v:val[0]] + v:val[2:]')
    endif
    if a:0 > 0  " line:name (other) or file:line:name (other)
      let size = max(map(copy(items), 'len(string(str2nr(v:val[1])))'))
      let fmt = string('%s: %s: %' . size . 'd: %s (%s)')
      call map(items, 'v:val[:2] + [tags#kind_char(v:val[3])] + v:val[4:]')
      call map(items, 'add(v:val[:2], join(v:val[3:], ", "))')  " combine parts
      call map(items, '[v:val[0], s:get_name(v:val[0], cache)] + v:val[1:]')
      call map(items, 'call("printf", [' . fmt  . '] + v:val)')
    endif
    call extend(result, uniq(items))  " ignore duplicates
  endfor | return result
endfunction

" Navigate to input tag list or fzf selection
" Note: This supports reading base path from trailing tab-delimited character. For
" now not implemented in dotfiles since slow for huge libraries (even though needed
" for large tags libraries). Also note this positions cursor on exact tag column.
function! tags#_goto_tag(mode, ...) abort  " 0:bracket jump, 1:tag/pop jump, 2:fzf jump
  return call('s:goto_tag', [a:mode] + a:000)
endfunction
function! s:goto_tag(mode, ...) abort
  " Parse tag input
  let path = expand('%:p')  " current path
  let from = getpos('.')  " current position
  let from[0] = bufnr()  " ensure correct buffer
  let native = '^\s*\(.\{-}\) *\t\(.\{-}\) *\t\(\d\+\)\%(;"\s*\(.*\)\)\?$'
  let custom = '^\%(\(.\{-}\): .\{-}: \)\?\s*\(\d\+\): \(.\{-}\) (\(.*\))$'
  if a:0 > 1  " non-fzf input
    let [ibuf, ipos, name; extra] = a:0 > 2 ? a:000 : [path] + a:000
  elseif a:0 && a:1 =~# native  " native format 'name<Tab>file<Tab>line;\"kind<Tab>scope'
    let [name, ibuf, ipos; extra] = matchlist(a:1, native)[1:4]
  elseif a:0 && a:1 =~# custom  " format '[<path>: <file>: ]<line>: name (kind[, scope])'
    let [ibuf, ipos, name; extra] = matchlist(a:1, custom)[1:4]
  else  " e.g. cancelled selection
    return
  endif
  let base = ''  " default base
  let extra = split(get(extra, 0, ''), ' *\t', 1)
  if a:1 =~# native && extra[-1] =~# 'tags$'
    let base = fnamemodify(extra[-1], ':h')
    let extra = slice(extra, 0, len(extra) - 1)
  endif
  " Jump to tag buffer
  if empty(ibuf)
    let ipath = path
  elseif !type(ibuf)
    let ipath = expand('#' . ibuf . ':p')
  elseif filereadable(ibuf)
    let ipath = fnamemodify(ibuf, ':p')
  elseif !empty(base)
    let ipath = fnamemodify(base, ':p') . ibuf
  else  " absolute path
    let msg = 'Error: Path ' . string(ibuf) . ' does not exist'
    redraw | echohl ErrorMsg | echom msg | echohl None | return
  endif
  if ipath !=# path  " record mark
    if exists('*file#goto_file')  " dotfiles utility
      silent call file#goto_file(ipath)
    else  " built-in utility
      silent exe 'tab drop ' . fnameescape(ipath)
    endif
  endif
  let [lnum, cnum] = type(ipos) > 1 ? ipos : [ipos, 0]
  let g:tag_name = [ipath, ipos, name]  " dotfiles stacks
  " Jump to tag position
  if a:mode > 1 || empty(get(g:, 'tags_keep_jumps', 0))  " update jumplist
    exe getpos('.') == getpos("''") ? '' : "normal! m'"
  endif
  let regex = substitute(escape(name, s:regex_magic), '·*$', '', '')
  call cursor(lnum, 1)
  if cnum <= 0
    silent call search(regex, 'cW', lnum)
  elseif cnum > 1
    exe 'normal! ' . (cnum - 1) . 'l'
  endif
  let regex = a:mode ? 'tag\|all' : 'block\|all'
  exe &l:foldopen =~# regex ? 'normal! zvzz' : a:mode ? 'normal! zz' : ''
  if a:mode != 0 && name !=# '<top>'  " i.e. not block jump
    call s:set_index(a:mode, name, lnum, from)
  endif
  if a:mode > 1 || empty(get(g:, 'tags_keep_jumps', 0))  " add jump
    exe getpos('.') == getpos("''") ? '' : "normal! m'"
  endif
  let [kind; rest] = extra  " see above
  let long = tags#kind_name(kind)
  let kind = empty(long) ? kind : long
  let info = join(empty(kind) ? rest : [kind] + rest, ', ')
  let info = empty(info) ? '' : ' (' . info . ')'
  let msg = 'Tag: ' . name . info
  redraw | if a:mode | echom msg | else | echo msg | endif
endfunction

" Select a specific tag using fzf
" See: https://github.com/ludovicchabant/vim-gutentags/issues/349
" Note: Usage is tags#select_tag(paths_or_level, options_or_iter) where first argument
" indicates the paths from which to get tags (or a level indicating the path range)
" and the optional second argument indicates manually provided tag source in the either
" format [line, name, other] if level == 0 or [path, line, name, other] if level > 0.
function! tags#_select_tag(mode, arg) abort
  let args = type(a:arg) > 1 ? [a:mode] + a:arg : [a:mode, a:arg]
  if exists('*stack#push_stack')
    call stack#push_stack('tag', 'tags#_goto_tag', args, 0)
  else
    call call('tags#_goto_tag', args)
  endif
endfunction
function! tags#select_tag(level, ...) abort
  let mode = a:0 > 1 ? a:2 : 2  " echom and show name
  let user = a:0 > 0 && !empty(a:1)
  let result = s:tag_source(a:level, user ? a:1 : 1)
  if empty(result)
    let msg = 'Error: Tags not found or not available'
    redraw | echohl ErrorMsg | echom msg | echohl None | return
  endif
  if !exists('*fzf#run')
    let msg = 'Error: fzf.vim plugin not available'
    redraw | echohl ErrorMsg | echom msg | echohl None | return
  endif
  let char = user || type(a:level) ? 'S' : a:level < 1 ? 'B' : a:level < 2 ? 'F' : ''
  let name = user || type(a:level) || a:level < 1 ? 'chunk,index' : 'index'
  let show = empty(a:level) ? '--with-nth 3..' : '--with-nth 2..'
  let opts = fzf#vim#with_preview({'placeholder': '{1}:{3..}'})
  let opts = join(map(get(opts, 'options', []), 'fzf#shellescape(v:val)'), ' ')
  let opts .= " -d': ' --tiebreak " . name . " --preview-window '+{3}-/2' " . show
  let options = {
    \ 'source': result,
    \ 'sink': function('tags#_select_tag', [mode]),
    \ 'options': opts . ' --tiebreak=index --prompt=' . string(char . 'Tag> ')
  \ }
  call fzf#run(fzf#wrap(options))
endfunction

"-----------------------------------------------------------------------------"
" Tag navigation utilities {{{1
"-----------------------------------------------------------------------------"
" Return tags and nearest index the given buffer and line
" Note: This translates kind to single-character for use e.g. in statusline
" Note: This is analogous to builtin functions getloclist(), getjumplist(), etc.
function! tags#get_tags(...) abort
  let forward = a:0 > 1 ? a:2 : 0
  let pos = a:0 > 0 ? a:1 : line('.')
  let bnr = type(pos) > 1 && !empty(pos[0]) ? bufnr(pos[0]) : bufnr()
  let lnum = type(pos) > 1 ? pos[1] : type(pos) ? str2nr(pos) : pos
  let items = getbufvar(bnr, 'tags_by_line', [])
  for idx in forward ? range(len(items)) : reverse(range(len(items)))
    if forward ? lnum <= items[idx][1] : lnum >= items[idx][1]
      return [items, idx]
    endif
  endfor
  let index = forward ? len(items) : -1
  return [items, index]
endfunction
function! tags#get_tag(...) abort
  let [items, idx] = call('tags#get_tags', a:000[:1])
  let forward = a:0 > 1 ? a:2 : 0
  let block = a:0 > 2 ? a:3 : 0
  let level = a:0 > 3 ? a:4 : 0
  let imax = len(items) - 1
  if forward
    let idxs = range(max([idx, 0]), imax)
    let jdxs = reverse(range(0, max([idx, 0]) - 1))  " start + 1 == stop allowed
  else
    let idxs = reverse(range(0, min([idx, imax])))
    let jdxs = range(min([idx, imax]) + 1, imax)  " start + 1 == stop allowed
  endif
  let itag = []  " closest tag
  for idx in block ? idxs : idxs + jdxs
    let item = items[idx]
    if level > 1  " top-level
      let bool = len(item) == 3 && tags#is_major(item)
    elseif level > 0  " major
      let bool = tags#is_major(item)
    elseif level == 0  " non-minor
      let bool = !tags#is_minor(item)
    else  " any tag
      let bool = v:true
    endif
    if bool  " meets requirements
      let itag = copy(item) | break
    endif
  endfor
  if len(itag) > 2
    let itag[2] = tags#kind_char(itag[2])
  endif
  return itag
endfunction

" Go to the tag keyword under the cursor
" NOTE: Here search both tag files using builtin functions and buffer-local method
" Note: Vim does not natively support jumping separate windows so implement here
function! tags#goto_name(...) abort
  let level = a:0 ? a:1 : 0
  let names = a:000[1:]
  let ftype = &l:filetype
  let keys = &l:iskeyword
  let path = expand('%:p')
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
  for name in names
    let name = substitute(name, '\(^\s*\|\s*$\)', '', 'g')
    if empty(name) | return | endif
    let itags = tags#tag_list(name, path)
    for itag in itags  " search 'tags' files
      let ipath = fnamemodify(itag.filename, ':p')
      if level < 1 && ipath !=# path | continue | endif
      let itype = tags#type_match(ipath)
      if level < 2 && empty(itype) | continue | endif
      let item = [ipath, itag.cmd, itag.name, itag.kind]
      return tags#_select_tag(2, item)
    endfor
    let itags = s:tag_source(level)  " search buffer tag variables
    for [ipath, iline, iname; irest] in itags
      if name !=# iname | continue | endif
      let item = [ipath, iline, iname] + irest
      return tags#_select_tag(2, item)
    endfor
  endfor
  let msg = 'Error: Tag ' . string(names[0]) . ' not found'
  redraw | echohl ErrorMsg | echom msg | echohl None | return 1
endfunction

" Jump to the next or previous tag under the cursor and get current tag
" Note: This is used with bracket t/T mappings and statusline
" Note: Native vim jumping maps e.g. n/N ignore content under cursor closed fold
" even if foldopen is enabled. Here stay consistent with this behavior
function! tags#current_tag(...) abort
  let scope = a:0 ? a:1 : 0
  let itag = tags#get_tag(line('.'))
  let itag = type(itag) > 1 ? itag : []
  if scope && len(itag) > 3  " show tag kind:scope:name
    let info = itag[2] . ':' . substitute(itag[3], '^\a:.\@=', '', '') . ':' . itag[0]
  elseif len(itag) > 2  " show tag kind:name
    let info = itag[2] . ':' . substitute(itag[0], '^\a:.\@=', '', '')
  else  " unknown tag
    return ''
  endif
  let stack = reverse(copy(get(g:, 'tag_stack', [])))
  let name = [expand('%:p'), itag[1], itag[0]]  " tag stack name
  let idx = index(stack, name) + 1
  let info .= idx > 0 ? ':' . idx : ''
  let jdx = len(stack) - get(g:, 'tag_loc', len(stack))
  let info .= jdx > 0 ? ':' . jdx : ''
  return info
endfunction
function! tags#next_tag(count, ...) abort
  let forward = a:count >= 0
  for idx in range(abs(a:count))  " count times
    let lnum = idx == 0 ? line('.') : str2nr(itag[1])
    let fnum = forward ? foldclosedend(lnum) : foldclosed(lnum)
    let inum = (fnum > 0 ? fnum : lnum) + (forward ? 1 : -1)
    let itag = call('tags#get_tag', [inum, forward, 1] + a:000)
    if empty(itag)  " algorithm failed
      let msg = 'Warning: ' . (type(itag) ? 'No more tags' : 'Tags not available')
      redraw | echohl WarningMsg | echom msg | echohl None | return
    endif  " assign line number
  endfor
  call tags#_goto_tag(0, itag[1], itag[0])  " jump to line then name
  exe &l:foldopen =~# 'block\|all' ? 'normal! zv' : ''
endfunction

" Jump to the next or previous word under the cursor
" Note: This is used with bracket w/W mappings
" Note: Native vim jumping maps e.g. n/N ignore content under cursor closed fold
" even if foldopen is enabled. Here stay consistent with this behavior
function! tags#next_word(count, ...) abort
  let winview = winsaveview()  " tags#search() moves to start of match
  let search = @/  " record previous search
  let result = tags#search(1, a:0 ? 1 - a:1 : 1, 0, 2)
  let [regex, flags] = [@/, a:count < 0 ? 'bw' : 'w']
  let @/ = search  " restore previous search
  if empty(regex)
    if empty(result) | return | endif  " scope error message
    let msg = 'Error: No keyword under cursor'
    redraw | echohl WarningMsg | echom msg | echohl None | return
  endif
  for idx in range(abs(a:count))
    let inum = foldclosed('.')
    let skip = "tags#get_inside(0, 'Constant', 'Comment')"
    let skip .= inum > 0 ? " || foldclosed('.') == " . inum : ''
    let pos = getpos('.')
    call search(regex, flags, 0, 0, skip)
  endfor
  let parts = matchlist(regex, '^\(\\%>\(\d\+\)l\)\?\(\\%<\(\d\+\)l\)\?\(.*\)$')
  let [line1, line2, name] = [parts[2], parts[4], parts[5]]  " get scope from regex
  let bnds = get(s:, 'scope_bounds', [line1, line2])  " get named scope
  let info = len(bnds) > 2 ? bnds[2] : !empty(bnds) ? line1 . ' ' . line2 : ''
  let msg = 'Keyword: ' . substitute(name, '\\[<>cC]', '', 'g')
  let msg .= empty(info) ? '' : ' (' . info . ')'
  exe &l:foldopen =~# 'block\|all' ? 'normal! zv' : ''
  redraw | echo msg | return 0
endfunction

"-----------------------------------------------------------------------------"
" Scope searching utilities {{{1
"-----------------------------------------------------------------------------"
" Helper function for printing scope
" Note: This is used to show search statistics for pattern-selection mappings. Use
" vim-indexed-search plugin if available or else use :substitute no-op flag to
" print 'N matches on M lines' message (take care to avoid suppressing message).
function! tags#_show(...) abort
  let bounds = get(s:, 'scope_bounds', [])
  unlet! s:scope_bounds
  if empty(bounds)  " usually only when ShowSearchIndex unavailable
    let regex = a:0 && !empty(a:1) ? a:1 : @/
    let regex = escape(regex, '@')
    exe '%s@' . regex . '@@gne'
  else  " show information on scope boundaries
    let [line1, line2; rest] = bounds
    let part1 = empty(rest) ? line1 : line1 . ' (' . rest[0] . ')'
    let part2 = empty(rest) ? line2 : line2 . ' (' . rest[1] . ')'
    redraw | echo 'Selected lines ' . part1 . ' to ' . part2
  endif
  call feedkeys("\<Cmd>setlocal hlsearch\<CR>", 'n')
endfunction

" Return regex for object under cursor
" Note: Here level -1 is previous search, level 0 is current character, level 1 is
" current word, and level 2 is current WORD. Second arg denotes scope boundary.
" Note: This uses the search() 'skip' parameter to skip matches inside comments and
" constants (i.e. strings). Similar method is used in succinct.vim for python docstrings
function! tags#get_inside(arg, ...) abort
  if type(a:arg) > 1  " explicit position
    let [lnum, cnum] = a:arg
  elseif type(a:arg) > 0  " column string
    let [lnum, cnum] = [line('.'), col(a:arg)]
  else  " column offset
    let [lnum, cnum] = [line('.'), col('.') + a:arg]
  endif
  let cnum = max([cnum, 1])  " one-based indexing
  let cnum = min([cnum, col([lnum, '$']) - 1])  " end-of-line or end-of-file plus 1
  let stack = synstack(lnum, cnum)
  let sids = map(stack, 'synIDtrans(v:val)')
  for name in a:000  " group names
    let sid = synIDtrans(hlID(name))
    if sid && index(sids, sid) != -1 | return 1 | endif
  endfor | return 0
endfunction
function! tags#get_search(level, ...) abort
  let search = a:0 ? a:1 : 0
  if type(a:level) | return a:level | endif
  if a:level > 1
    let regex = escape(expand('<cWORD>'), s:regex_magic)
    let regex = search ? '\(^\|\s\)\zs' . regex . '\ze\($\|\s\)\C' : regex
  elseif a:level > 0
    let regex = escape(expand('<cword>'), s:regex_magic)
    let regex = regex =~# '^\k\+$' ? search ? '\<' . regex . '\>\C' : regex : ''
  else  " ··· note col('.') and string[:idx] uses byte index
    let regex = strcharpart(strpart(getline('.'), col('.') - 1), 0, 1)
    let regex = escape(empty(regex) ? "\n" : regex, s:regex_magic)
  endif
  return regex
endfunction

" Return major tag folding scope
" NOTE: Here also do extra check to ensure tag scope is not outdated. Otherwise allow
" scope search on unsaved files since e.g. editing text below major tags is very common
" See: https://stackoverflow.com/a/597932/4970632
" See: http://vim.wikia.com/wiki/Search_in_current_function
function! s:set_scope(...) abort
  if exists('*fold#update_folds')
    silent! call fold#update_folds(0)
  elseif exists(':FastFoldUpdate')
    silent! FastFoldUpdate
  endif
endfunction
function! s:get_scope(...) abort
  let level = a:0 > 1 ? a:2 : 1
  let lnum = a:0 > 0 ? a:1 : line('.')
  let itag = tags#get_tag(lnum, 0, 1, level)
  let name0 = empty(itag) ? '' : itag[0]
  let line0 = empty(itag) ? 0 : str2nr(itag[1])
  let winview = winsaveview()
  let closed = foldclosed(line0)  " WARNING: critical (needed for foldtextresult())
  silent! exe closed > 0 ? '': line0 . 'foldclose'
  let line1 = foldclosed(line0)
  let line2 = foldclosedend(line0)
  call foldtextresult(line1)  " WARNING: critical (updates foldtext cache)
  silent! exe closed > 0 ? '' : line0 . 'foldopen'
  call winrestview(winview)
  let deltas = get(b:, 'foldtext_delta', {})
  let delta = get(deltas, string(line1), 0)
  return [name0, line0, line1 + delta, line2]
endfunction
function! tags#get_scope(...) abort
  let lnum = a:0 > 0 ? a:1 : line('.')
  let keep = a:0 > 1 ? a:2 : get(g:, 'tags_keep_folds', 0)
  if empty(keep) | call s:set_scope() | endif
  let s:scope_bounds = []  " reset message cache
  for level in [1, 2]  " attempt cursor then parent
    let [name0, line0, line1, line2] = s:get_scope(lnum, level)
    let regex = substitute(escape(name0, s:regex_magic), '·*$', '', '')
    let isavail = !empty(get(b:, 'tags_by_line', []))  " check if tags available
    let istag = matchend(getline(line0), regex) >= 0  " check if tag is valid
    let isfold = line2 > line1 && foldlevel(lnum)  " fails for invalid folds
    let ismatch = line0 == line1 && line0 < line2  " fails for invalid tags
    let isinside = lnum >= line1 && lnum <= line2  " fails for invalid tags
    if isinside && ismatch && istag  " success
      break
    elseif isfold && level == 1  " try again
      continue
    elseif !empty(keep)  " try again
      return tags#get_scope(lnum, 0)
    endif
    let icol = matchend(getline(line1), '^\s*\S')
    let iscomment = icol > 0 ? tags#get_inside([line1, icol], 'Comment') : 0
    if istag && isavail && !ismatch && !empty(name0)  " e.g. missing folds
      let msg = string(name0) . ' fold not found'
    elseif istag && isavail && !isinside  " e.g. global scope
      let msg = 'search scope appears to be global'
    elseif &l:modified  " e.g. oudated changes
      let msg = 'tags appear to be outdated; try :write'
    elseif !isavail  " inactive tags
      let msg = 'tags appear to be unavailable'
    else  " invalid tag name
      let msg = string(name0) . ' tag not found'
    endif
    let msg = 'Error: Failed to restrict the search scope (' . msg . ')'
    redraw | echohl ErrorMsg | echom msg | echohl None | return []
  endfor
  let [name1, name2, nmax] = [name0, trim(getline(line2)), 20]
  let name1 = len(name1) > nmax ? name1[:nmax - 3] . '···' : name1
  let name2 = len(name2) > nmax ? name2[:nmax - 3] . '···' : name2
  let s:scope_bounds = [line1, line2, name1, name2]  " see tags#_show
  return [line1, line2]
endfunction

"-----------------------------------------------------------------------------"
" Search and replace commands {{{1
"-----------------------------------------------------------------------------"
" Replace the current search
" Note: Here tags#rescope() is also used in forked version of vim-repeat
" Note: Replacing search-scope text with newlines will make subsequent scope
" restrictions out-of-date. Fix this by offsetting scope regex by number of
" newlines in replacement string minus number of newlines in search string.
function! tags#rescope(...) abort
  let search = a:0 > 0 ? a:1 : @/
  let scale = a:0 > 1 ? a:2 : 1
  let parts = matchlist(search, '\\%<\(\d\+\)l')
  let lnum = str2nr(get(parts, 1, ''))
  if empty(lnum) | return search | endif
  let sub = get(g:, 'tags_change_sub', '')
  let cnt1 = count(substitute(search, '\\n', "\r", 'g'), "\r")
  let cnt2 = count(substitute(sub, '\\r', "\r", 'g'), "\r")
  let lnum += scale * (cnt2 - cnt1)
  return substitute(search, '\\%<\d\+l', '\\%<' . lnum . 'l', '')
endfunction
function! tags#replace(text, ...) range abort
  let winview = get(b:, 'tags_change_winview', winsaveview())
  let local = a:0 ? a:1 : 0
  let lines = []
  if local > 1  " manual scope
    let lines = [a:firstline, a:lastline]
  elseif local > 0  " local scope
    let lines = tags#get_scope() | let lines = type(lines) ? lines : []
  endif  " global scope
  let range = empty(lines) ? '%' : lines[0] . ',' . lines[1]
  let regex = escape(@/, '@')
  let text = escape(a:text, '@')
  exe range . 's@' . regex . '@' . text . '@ge'
  call winrestview(winview)
  let g:tags_repeat_tick = b:changedtick  " see repeat.vim
endfunction

" Search for object under cursor
" Note: Native vim * mappings update search history so do this explicitly below
" Note: Default vim-indexed-search maps invoke <Plug>(indexed-search-after), which just
" calls <Plug>(indexed-search-index) --> :ShowSearchIndex... but causes change maps
" to silently abort for some weird reason... so instead call the command manually.
function! tags#search(level, local, ...) range abort
  let focus = a:0 > 0 ? a:1 : 0
  let quiet = a:0 > 1 ? a:2 : 0
  let match = tags#get_search(a:level, 0)
  if focus && empty(match) && foldclosed('.') == -1
    exe getline('.') =~# '^\s*$' ? '' : 'normal! B'
  endif
  let regex = tags#get_search(a:level, 1)
  let char = strcharpart(strpart(getline('.'), col('.') - 1), 0, 1)
  let flag = char =~# '\s' || a:level == 1 && char !~# '\k' ? 'cW' : 'cbW'
  if focus && strwidth(match) > 1
    call search(regex, flag, line('.'))
  endif
  let bnds = []
  let feed = ''
  let scope = ''
  if a:local > 1  " manual scope
    let bnds = [a:firstline, a:lastline] | let s:scope_bounds = bnds
  elseif a:local > 0  " local scope
    let bnds = tags#get_scope() | let bnds = type(bnds) ? bnds : []
  endif  " global scope
  if type(bnds) && !empty(bnds)
    let scope = printf('\%%>%dl\%%<%dl', bnds[0] - 1, bnds[1] + 1)
  endif
  if a:local && empty(scope)  " reset pattern
    let @/ = '' | return []
  else  " update pattern
    let @/ = scope . regex
  endif
  if focus  " add e.g. '*' to search history
    call histadd('search', @/)
  endif
  if quiet  " do not show message
    let feed = quiet > 1 ? '' : "\<Cmd>setlocal hlsearch\<CR>"
  elseif !a:local && exists(':ShowSearchIndex')  " show vim-indexed-search
    let feed = "\<Cmd>ShowSearchIndex\<CR>\<Cmd>setlocal hlsearch\<CR>"
  else  " show scope or @/ summary (if scope empty)
    let feed = "\<Cmd>call tags#_show(" . string(scope) . ")\<CR>"
  endif
  let name1 = a:level > 1 ? 'WORD' : a:level > 0 ? 'Word' : 'Char'
  let name2 = a:local ? 'Local' : 'Global'
  exe focus && &l:foldopen =~# 'block\|all' ? 'normal! zv' : ''
  call feedkeys(feed, 'n')
  return [name1, name2]
endfunction

"-----------------------------------------------------------------------------"
" Search and replace mappings {{{1
"-----------------------------------------------------------------------------"
" Change and delete next match
" Note: See :help sub-replace-special for special characters tht have to be escaped
" Note: Register @. may have keystrokes e.g. <80>kb (backspace) so must feed 'typed'
" keys, and vim automatically suppresses standard :substitute message 'changed N
" matches on M lines' if mapping includes multiple text-changing commands so must
" :undo the initial 'cgn' or 'dgn' operation before changing the other matches.
function! s:feed_repeat(name, ...) abort
  if !exists('*repeat#set') | return | endif
  let cnt = v:count ? v:count : get(g:, 'tags_change_count', 0)
  let key = '"\<Plug>Tags' . a:name . join(a:000, '') . '"'
  let feed = 'call repeat#set(' . key . ', ' . cnt . ')'
  call feedkeys("\<Cmd>" . feed . "\<CR>", 'n')
endfunction
function! tags#change_init(...) abort
  let force = get(g:, 'tags_change_force', -1)
  let sub = a:0 ? a:1 : @.
  if force < 0 | return | endif
  let cnt = get(g:, 'tags_change_count', 0)
  let key = get(g:, 'tags_change_key', 'n')
  let post = &l:foldopen =~# 'quickfix\|all' ? 'zv' : ''  " treat as 'quickfix'
  if cnt > 1  " trigger additional changes
    let post .= exists(':ShowSearchIndex') ? "\<Cmd>ShowSearchIndex\<CR>" : ''
    let post .= (cnt - 1) . "\<Cmd>call tags#change_again(1)\<CR>"
  endif
  if g:tags_change_force  " change all items
    let sub = substitute(sub, "\n", '\\r', 'g')
    let feed = "\<Cmd>call tags#change_force(1)\<CR>"
    call feedkeys(feed, 'n')
  else  " change one item
    let sub = substitute(sub, "\n", "\<CR>", 'g')
    call feedkeys(key . post, 'n')
    call s:feed_repeat('Change', 'Again')
  endif
  let @/ = tags#rescope(@/, 1)
  let g:tags_change_sub = sub
  let g:tags_change_force = -1
endfunction

" Repeat initial changes
" Note: Here global variables are required to avoid issues with nested feedkeys().
" Note: Here implement global and repeated deletions by calling tags#change_again()
" and tags#change_force() commands with empty replacement strings.
function! tags#_change_input(...) abort
  let text = input('Replace: ', '')  " see below; used to convert literals
  return call('tags#replace', [text] + a:000)
endfunction
function! tags#change_force(...) abort
  let tick = get(b:, 'tags_change_tick', 0)  " before initial change
  exe a:0 && a:1 && tick && tick != b:changedtick ? 'silent undo' : ''
  let b:tags_change_tick = 0  " possible edge case
  let b:tags_change_winview = winsaveview()  " see repeat.vim
  let g:tags_change_sub = get(g:, 'tags_change_sub', '')
  let g:tags_change_count = 0  " overwrite unused count
  let feed = 'mode() =~# "^c" ? escape(g:tags_change_sub . "\<CR>", "~&\\") : ""'
  let feed = "\<Cmd>call feedkeys(" . feed . ", 'tni')\<CR>"
  let cmd = "\<Cmd>call tags#_change_input()\<CR>"
  call s:feed_repeat('Change', 'Force')  " critial or else fails
  call feedkeys(cmd . feed, 'n')
endfunction
function! tags#change_again(...) abort
  let g:tags_change_sub = get(g:, 'tags_change_sub', '')
  let b:tags_change_tick = 0  " possible edge case
  let cnt = v:count ? v:count : get(g:, 'tags_change_count', 0)
  let key = get(g:, 'tags_change_key', 'n')
  let post = &l:foldopen =~# 'quickfix\|all' ? 'zv' : ''
  let post .= exists(':ShowSearchIndex') ? "\<Cmd>ShowSearchIndex\<CR>" : ''
  let feed = "mode() ==# 'i' ? g:tags_change_sub : ''"
  let feed = "\<Cmd>call feedkeys(" . feed . ", 'tni')\<CR>\<Esc>"
  let feed = 'cg' . key . feed . key . post  " change next match
  for idx in range(max([cnt, 1]))
    let @/ = tags#rescope(@/, 1) | call feedkeys(feed, 'ni')
  endfor
  if !a:0 || !a:1  " i.e. not initial call
    call s:feed_repeat('Change', 'Again')
  endif
endfunction

" Setup and repeat changes
" Note: The 'cgn' command silently fails to trigger insert mode if no matches found
" so we check for that. Putting <Esc> in feedkeys() cancels operation so must come
" afterward (may be no-op) and the 'i's are necessary to insert previously-inserted
" text before <Esc> and to complete initial v:count1 repeats before s:feed_repeat().
function! tags#change_next(...) abort
  return call('s:change_next', [0] + a:000)
endfunction
function! tags#delete_next(...) abort
  return call('s:change_next', [1] + a:000)
endfunction
function! s:change_next(delete, level, local, ...) abort
  let cnt = v:count  " WARNING: this must come first
  let force = a:0 ? a:1 : 0
  if a:level < 0  " delete match e.g. d/
    let key = a:local ? 'N' : 'n'  " shorthand
    let names = ['Match', key ==# 'N' ? 'Prev' : 'Next']
  else  " delete word e.g. d*
    let key = 'n'
    let names = tags#search(a:level, a:local)
  endif
  if empty(names) | return | endif  " scope not found
  let feed = a:delete ? "\<Esc>\<Cmd>call tags#change_init('')\<CR>" : ''
  let b:tags_change_tick = b:changedtick
  let g:tags_change_key = key
  let g:tags_change_count = cnt
  let g:tags_change_force = force
  call feedkeys('cg' . key . feed, 'n')
endfunction
