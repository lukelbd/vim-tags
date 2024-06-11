"------------------------------------------------------------------------------
" General tag processing utiltiies {{{1
"------------------------------------------------------------------------------
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
endfunc
function! s:sort_by_name(tag1, tag2) abort
  let str1 = a:tag1[0]
  let str2 = a:tag2[0]
  return str1 <# str2 ? -1 : str1 ==# str2 ? 0 : 1  " equality, lesser, and greater
endfunction
function! s:filter_buffer(...) abort
  let bnr = a:0 > 0 ? a:1 : bufnr()
  let ftype = a:0 > 1 ? a:2 : ''
  let btype = getbufvar(bnr, '&filetype')
  if empty(btype) || !empty(ftype) && ftype !=# btype  " type required
    return 0
  endif
  if !filereadable(expand('#' . bnr . ':p'))  " file required
    return 0
  endif
  if index(g:tags_skip_filetypes, btype) != -1  " additional skips
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
  let name = call('tags#lang_name', a:000)
  let opts = get(get(g:, name, {}), name, a:default)
  let kind1 = get(a:tag, 2, '')  " translate to or from character
  let kinds = len(kind1) > 1 ? g:tags_kind_chars : g:tags_kind_names
  let kind2 = get(get(kinds, name, {}), kind1, kind1)
  if type(opts) > 1
    return index(opts, kind1) >= 0 || index(opts, kind2) >= 0
  else  " faster than splitting (important for statusline)
    return kind1 =~# '[' . opts . ']' || kind2 =~# '[' . opts . ']'
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
  if !empty(ftype) && index(g:tags_skip_filetypes, ftype) < 0
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
  let regex = '^' . escape(a:name, s:regex_magic) . '$'
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
    let paths = [expand('%:p')]
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
        redraw | echohl WarningMsg
        echom 'Warning: Path ' . string(path) . ' not open or not readable.'
        echohl None
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
    redraw | echohl ErrorMsg
    echom 'Error: Tags not found or not available.'
    echohl None | return ''
  endif
  return 'Tags for ' . label . ":\n" . join(tables, "\n")
endfunction

" Show the current file kinds
" Note: Ctags cannot show specific filetype kinds so instead filter '--list-kinds=all'
" Note: See https://stackoverflow.com/a/71334/4970632 for difference between \r and \n
function! tags#table_kinds(...) abort
  let [umajor, uminor] = [copy(g:tags_major_kinds), copy(g:tags_minor_kinds)]
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
  return title . ":\n" . major . "\n" . minor . "\n" . trim(table)
endfunction

"-----------------------------------------------------------------------------
" Tag selection utiltiies {{{1
"-----------------------------------------------------------------------------
" Return or set the tag stack index
" Note: This is used to manually update the tag stack index, allowing us to emulate
" native vim :tag with tags#iter_tags(1, ...) and :pop with tags#iter_tags(-1, ...).
function! s:get_index(name, ...) abort  " stack index
  let stack = gettagstack(winnr())
  let items = get(stack, 'items', [])
  let idxs = []  " exact tag matches
  for idx in range(len(items))
    let item = items[idx]  " search tag stack
    if item.tagname ==# a:name && item.bufnr == bufnr()
      call add(idxs, idx)
    endif
  endfor
  return empty(idxs) ? -1 : a:0 && a:1 < 0 ? idxs[0] : idxs[-1]
endfunction
function! s:set_index(name, lnum, from, ...) abort
  let scroll = a:0 ? a:1 : 0
  if a:name ==# '<top>' | return | endif
  if !scroll && !g:tags_keep_stack  " perform :tag <name>
    let item = {'bufnr': bufnr(), 'from': a:from, 'matchnr': 1, 'tagname': a:name}
    if item.bufnr != a:from[0] || a:lnum != a:from[1]  " push from curidx to top
      call settagstack(winnr(), {'items': [item]}, 't')
    endif
  else  " perform :tag or :pop
    let idx = s:get_index(a:name, scroll)
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
    let items = getbufvar(bufnr(path), 'tags_by_name', [])
    if a:0 && type(a:1)  " user-input [path, line, name, other]
      let items = deepcopy(a:1)
    else  " [name, line, other] -> [path, line, name, other]
      let items = map(deepcopy(items), '[path, v:val[1], v:val[0]] + v:val[2:]')
    endif
    if a:0 > 0  " line:name (other) or file:line:name (other)
      let size = max(map(copy(items), 'len(string(str2nr(v:val[1])))'))
      let format = string('%s: %s: %' . size . 'd: %s (%s)')
      call map(items, 'v:val[:2] + [tags#kind_char(v:val[3])] + v:val[4:]')
      call map(items, 'add(v:val[:2], join(v:val[3:], ", "))')  " combine parts
      call map(items, '[v:val[0], s:get_name(v:val[0], cache)] + v:val[1:]')
      call map(items, 'call("printf", [' . format  . '] + v:val)')
    endif
    call extend(result, uniq(items))  " ignore duplicates
  endfor | return result
endfunction

" Navigate to input tag list or fzf selection
" Note: This supports reading base path from trailing tab-delimited character. For
" now not implemented in dotfiles since slow for huge libraries (even though needed
" for large tags libraries). Also note this positions cursor on exact tag column.
function! tags#goto_tag(...) abort  " :tag <name> analogue
  return call('s:goto_tag', [0] + a:000)
endfunction
function! tags#_goto_tag(count, ...) abort  " 1:naked tag/pop, 2:bracket jump
  return call('s:goto_tag', [a:count] + a:000)
endfunction
function! s:goto_tag(count, ...) abort
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
    redraw | echohl ErrorMsg
    echom 'Error: Path ' . string(ibuf) . ' does not exist.'
    echohl None | return
  endif
  if ipath !=# path  " record mark
    if exists('*file#goto_file')  " dotfiles utility
      silent call file#goto_file(ipath)
    else  " built-in utility
      silent exe 'tab drop ' . fnameescape(ipath)
    endif
  endif
  " Jump to tag position
  if !a:count || !g:tags_keep_jumps  " add jump
    exe getpos('.') == getpos("''") ? '' : "normal! m'"
  endif
  let g:tag_name = [ipath, ipos, name]  " dotfiles stacks
  let [lnum, cnum] = type(ipos) > 1 ? ipos : [ipos, 0]
  call cursor(lnum, 1)
  if cnum <= 0
    let regex = substitute(escape(name, s:regex_magic), '·*$', '', '')
    silent call search(regex, 'cW', lnum)
  elseif cnum > 1
    let motion = (cnum - 1) . 'l'
    exe 'normal! ' . motion
  endif
  if abs(a:count) < 2 && name !=# '<top>'  " i.e. not block jump
    call s:set_index(name, lnum, from, a:count)
  endif
  if &l:foldopen =~# (a:count ? '\<block\>' : '\<tag\>')
    let keys = 'zvzz'  " open fold
  else  " center tag
    let keys = a:count ? '' : 'zz'
  endif
  if !a:count || !g:tags_keep_jumps  " add jump
    let keys .= getpos('.') == getpos("''") ? '' : "m'"
  endif
  exe empty(keys) ? '' : 'normal! ' . keys
  let [kind; rest] = extra  " see above
  let long = tags#kind_name(kind)
  let kind = empty(long) ? kind : long
  let info = join(empty(kind) ? rest : [kind] + rest, ', ')
  let info = empty(info) ? '' : ' (' . info . ')'
  redraw | echom 'Tag: ' . name . info
endfunction

" Select a specific tag using fzf
" See: https://github.com/ludovicchabant/vim-gutentags/issues/349
" Note: Usage is tags#select_tag(paths_or_level, options_or_iter) where second
" argument indicates whether stacks should be updated (tags#goto_tag) or not
" (tags#_goto_tag) and first argument indicates the paths to search and whether to
" display the path in the fzf prompt. The second argument can also be a list of tags
" in the format [line, name, other] (or [path, line, name, other] if level > 0)
function! tags#_select_tag(count, item) abort
  let args = type(a:item) > 1 ? [a:count] + a:item : [a:count, a:item]
  if exists('*stack#push_stack')
    call stack#push_stack('tag', 'tags#_goto_tag', args, 0)
  else
    call call('tags#_goto_tag', args)
  endif
endfunction
function! tags#select_tag(level, ...) abort
  let cnt = a:0 > 1 ? a:2 : 0
  let input = a:0 > 0 && !empty(a:1)
  let result = s:tag_source(a:level, input ? a:1 : 1)
  if empty(result)
    redraw | echohl ErrorMsg
    echom 'Error: Tags not found or not available.'
    echohl None | return
  endif
  if !exists('*fzf#run')
    redraw | echohl ErrorMsg
    echom 'Error: fzf.vim plugin not available.'
    echohl None | return
  endif
  let show = empty(a:level) ? '--with-nth=3..' : '--with-nth=2..'
  let opts = fzf#vim#with_preview({'placeholder': '{1}:{3..}'})
  let opts = join(map(get(opts, 'options', []), 'fzf#shellescape(v:val)'), ' ')
  let opts = "-d': ' " . show . " --preview-window '+{3}-/2' " . opts
  let char = input || type(a:level) ? 'S' : a:level < 1 ? 'B' : a:level < 2 ? 'F' : ''
  let options = {
    \ 'source': result,
    \ 'sink': function('tags#_select_tag', [cnt]),
    \ 'options': opts . ' --no-sort --prompt=' . string(char . 'Tag> ')
  \ }
  call fzf#run(fzf#wrap(options))
endfunction

"-----------------------------------------------------------------------------"
" Tag navigation utilities {{{1
"-----------------------------------------------------------------------------"
" Return the tags and nearest index for the given buffer and line number
" Note: This is analogous to builtin functions getloclist(), getjumplist(), etc.
function! tags#get_tags(...)
  let pos = a:0 > 0 ? a:1 : line('.')
  let bnr = type(pos) > 1 && !empty(pos[0]) ? bufnr(pos[0]) : bufnr()
  let lnum = type(pos) > 1 ? pos[1] : type(pos) ? str2nr(pos) : pos
  let items = getbufvar(bnr, 'tags_by_line', [])
  let forward = a:0 > 1 ? a:2 : 0
  let max = len(items) - 1  " maximum valid index
  let idxs = forward ? range(max, 0, -1) : range(0, max)
  let index = -1  " returned index
  for idx in idxs
    if forward && lnum > items[idx][1]
      let index = min([idx + 1, max]) | break
    endif
    if !forward && lnum < items[idx][1]
      let index = max([idx - 1, 0]) | break
    endif
    if idx == idxs[-1]
      let index = idx | break
    endif
  endfor
  return [items, index]
endfunction

" Return the nearest tag matching input criteria
" Note: This translates kind to single-character for use e.g. in statusline
function! tags#get_tag(...) abort
  let [items, idx] = call('tags#get_tags', a:000[:1])
  let forward = a:0 > 1 ? a:2 : 0
  let circular = a:0 > 2 ? a:3 : 0
  let major = a:0 > 3 ? a:4 : 0
  let max = len(items) - 1
  if forward
    let idxs = range(idx, max)
    let jdxs = range(0, idx - 1)
  else
    let idxs = range(idx, 0, -1)
    let jdxs = range(max, idx + 1, -1)
  endif
  let jdxs = circular ? jdxs : reverse(jdxs)
  let index = -1  " returned index
  for idx in extend(idxs, jdxs)  " search valid tags
    let item = items[idx]
    if major && len(item) == 3 && tags#is_major(item)
      let index = idx | break
    elseif !major && len(item) > 2 && !tags#is_minor(item)
      let index = idx | break
    endif
  endfor
  let item = copy(index >= 0 ? items[index] : [])
  if len(item) > 2
    let item[2] = tags#kind_char(item[2])
  endif | return item
endfunction

" Go to the tag keyword under the cursor
" Note: Vim does not natively support jumping separate windows so implement here
function! tags#goto_name(...) abort
  let level = a:0 ? a:1 : 0
  let names = a:000[1:]
  let iskey = &l:iskeyword
  let ftype = &l:filetype
  let path = expand('%:p')
  if empty(names)  " tag names
    let mods = get(s:keyword_mods, &l:filetype, '')
    let mods = split(mods, '\zs')
    try
      let &l:iskeyword = join([iskey] + mods, ',')
      let names = [expand('<cword>'), expand('<cWORD>')]
    finally
      let &l:iskeyword = iskey
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
      return tags#_select_tag(0, item)
    endfor
    let itags = s:tag_source(level)  " search buffer tag variables
    for [ipath, iline, iname; irest] in itags
      if name !=# iname | continue | endif
      let item = [ipath, iline, iname] + irest
      return tags#_select_tag(0, item)
    endfor
  endfor
  redraw | echohl ErrorMsg
  echom 'Error: Tag ' . string(names[0]) . ' not found'
  echohl None | return 1
endfunction

" Return the tag name under or preceding the cursor
" Note: This is used with statusline and :CurrentTag
function! tags#current_tag(...) abort
  let lnum = line('.')
  let info = tags#get_tag(lnum)
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
  let args = [a:count >= 0, 1, a:0 ? a:1 : 0]
  for idx in range(abs(a:count))  " count times
    let lnum = idx == 0 ? line('.') : str2nr(itag[1])
    let lnum += idx == 0 ? 0 : a:count >= 0 ? 1 : -1
    let itag = call('tags#get_tag', [lnum] + args)
    if empty(itag)  " algorithm failed
      redraw | echohl WarningMsg
      echom 'Error: Next tag not found'
      echohl None | return
    endif  " assign line number
  endfor
  call tags#_goto_tag(2, itag[1], itag[0])  " jump to line then name
  exe &l:foldopen =~# '\<block\>' ? 'normal! zv' : ''
endfunction

" Jump to the next or previous word under the cursor
" Note: This is used with bracket w/W mappings
function! tags#next_word(count, ...) abort
  let winview = winsaveview()  " tags#set_search() moves to start of match
  let local = a:0 ? 1 - a:1 : 1
  silent call tags#set_search(1, 0, local, 1)  " suppress scope message for now
  let [regex, flags] = [@/, a:count < 0 ? 'bw' : 'w']
  for _ in range(abs(a:count))
    let pos = getpos('.')
    call search(regex, flags, 0, 0, "!tags#get_skip(0, 'Constant', 'Comment')")
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
  exe &l:foldopen =~# '\<block\>' ? 'normal! zv' : ''
endfunction

"-----------------------------------------------------------------------------"
" Keyword searching utilities {{{1
"-----------------------------------------------------------------------------"
" Return match under cursor and whether inside requested syntax group
" Note: Here level -1 is previous search, level 0 is current character, level 1 is
" current word, and level 2 is current WORD. Second arg denotes scope boundary.
" Note: This uses the search() 'skip' parameter to skip matches inside comments and
" constants (i.e. strings). Similar method is used in succinct.vim for python docstrings
function! tags#get_skip(arg, ...) abort
  let lnum = line('.')  " check against input column offset or given position
  let cnum = type(a:arg) ? col(a:arg) : col('.') + a:arg
  let cnum = max([cnum, 1])  " one-based indexing
  let cnum = min([cnum, col('$') - 1])  " end-of-line or end-of-file plus 1
  let stack = synstack(lnum, cnum)
  let sids = map(stack, 'synIDtrans(v:val)')
  for name in a:000  " group names
    let sid = synIDtrans(hlID(name))
    if sid && index(sids, sid) != -1 | return 0 | endif
  endfor | return 1
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
" See: https://stackoverflow.com/a/597932/4970632
" See: http://vim.wikia.com/wiki/Search_in_current_function
function! tags#get_scope(...) abort
  " Find closing line and tag
  let s:scope_bounds = []  " reset message cache
  let tags = get(b:, 'tags_by_line', [])
  let itags = filter(copy(tags), 'tags#is_major(v:val)')
  let lines = map(deepcopy(itags), 'str2nr(v:val[1])')
  if empty(itags)
    let msg = empty(tags) ? 'tags unavailable' : 'no major tags found'
    redraw | echohl WarningMsg
    echom 'Error: Failed to restrict the search scope (' . msg . ').'
    echohl None | return ''
  endif
  let winview = winsaveview()
  exe a:0 ? a:1 : '' | let lnum = line('.')
  let [iline, line1, level1] = [-1, lnum, foldlevel('.')]
  while iline != line1 && index(lines, line1) == -1
    let [iline, ifold] = [line('.'), foldclosed('.')]
    exe ifold > 0 && iline != ifold ? ifold : 'keepjumps normal! [z'
    let [line1, level1] = [line('.'), foldlevel('.')]
    let line1 = get(get(b:, 'fold_heads', {}), line1, line1)  " python decorators
  endwhile
  let ifold = foldclosedend('.')
  exe ifold > 0 ? ifold : 'keepjumps normal! ]z'
  let [line2, level2] = [line('.'), foldlevel('.')]
  call winrestview(winview)
  " Return scope if within fold
  let iscursor = lnum >= line1 && lnum <= line2
  let isfold = level1 > 0 && line1 != line2
  let idx = index(lines, line1)  " fold aligns with tags
  if idx < 0 || !isfold || !iscursor
    let msg = !iscursor ? 'current scope is global' : 'major tag fold not found'
    redraw | echohl WarningMsg
    echom 'Error: Failed to restrict the search scope (' . msg . ').'
    echohl None | return ''
  endif
  let label1 = itags[idx][0]
  let label2 = trim(getline(line2))
  let nmax = 20  " maximum label length
  let label1 = len(label1) > nmax ? label1[:nmax - 3] . '···' : label1
  let label2 = len(label2) > nmax ? label2[:nmax - 3] . '···' : label2
  let s:scope_bounds = [line1, line2, label1, label2]  " see tags#show_search
  return printf('\%%>%dl\%%<%dl', line1 - 1, line2 + 1)
endfunction

" Set the last search register to some 'current pattern' under cursor
" Note: Native vim-indexed-search maps invoke <Plug>(indexed-search-after), which just
" calls <Plug>(indexed-search-index) --> :ShowSearchIndex... but causes change maps
" to silently abort for some weird reason... so instead call this manually.
function! tags#show_search(...) abort
  let regex = a:0 ? a:1 : @/
  if !empty(get(s:, 'scope_bounds', []))
    let [line1, line2; rest] = s:scope_bounds
    let part1 = empty(rest) ? line1 : line1 . ' (' . rest[0] . ')'
    let part2 = empty(rest) ? line2 : line2 . ' (' . rest[1] . ')'
    echom 'Selected lines ' . part1 . ' to ' . part2 . '.'
  else  " n flag prints results without substitution
    let winview = winsaveview()  " store window as buffer variable
    let search = escape(regex, '@')
    call execute('%s@' . search . '@@gne')
    call winrestview(winview)
  endif
  let keys = "\<Cmd>setlocal hlsearch\<CR>"
  call feedkeys(keys, 'n') | let s:scope_bounds = []  " reset message cache
endfunction
function! tags#set_search(level, ...) range abort
  let adjust = a:0 > 1 ? a:2 : 0
  let local = a:0 > 0 ? a:1 : 0
  let bnds = [a:firstline, a:lastline]
  let match = tags#get_search(a:level, 0)
  if adjust && empty(match) && foldclosed('.') == -1
    exe getline('.') =~# '^\s*$' ? '' : 'normal! B'
  endif
  let regex = tags#get_search(a:level, 1)
  let char = strcharpart(strpart(getline('.'), col('.') - 1), 0, 1)
  let flag = char =~# '\s' || a:level == 1 && char !~# '\k' ? 'cW' : 'cbW'
  if adjust && strwidth(match) > 1
    call search(regex, flag, line('.'))
  endif
  if bnds[0] != bnds[1]  " user-input range
    let scope = printf('\%%>%dl\%%<%dl', bnds[0] - 1, bnds[1] + 1) | let s:scope_bounds = bnds
  elseif local  " local scope
    let scope = tags#get_scope()
  else  " global scope
    let scope = ''
  endif
  if local && empty(scope)  " reset pattern
    let @/ = '' | return []
  else  " update pattern
    let @/ = scope . regex
  endif
  let prefix = a:level > 1 ? 'WORD' : a:level > 0 ? 'Word' : 'Char'
  let suffix = local ? 'Local' : 'Global'
  if empty(scope) && exists(':ShowSearchIndex')
    let cmds = ['ShowSearchIndex', 'setlocal hlsearch']
    let s:scope_bounds = []
  else
    let cmds = ['call tags#show_search(' . string(scope) . ')']
  endif
  exe &l:foldopen =~# '\<block\>' && adjust ? 'normal! zv' : ''
  call map(cmds, {_, val -> "\<Cmd>" . val . "\<CR>"})
  call feedkeys(join(cmds, ''), 'n')
  return [prefix, suffix]
endfunction

"-----------------------------------------------------------------------------
" Keyword manipulation utilities {{{1
"-----------------------------------------------------------------------------
" Helper functions
" Note: Critical to feed repeat command and use : instead of <Cmd> or will
" not work properly. See: https://vi.stackexchange.com/a/20661/8084
function! s:feed_repeat(name, ...) abort
  if !exists('*repeat#set') | return | endif
  let plug = '\<Plug>' . a:name
  let cnt = a:0 ? a:1 : v:count
  let cmd = 'call repeat#set("zv' . plug . '", ' . cnt . ')'
  call feedkeys("\<Cmd>" . cmd . "\<CR>", 'n')
endfunction

" Set up repeat after finishing previous change on InsertLeave
" Note: Critical to use global variables or else have issues with nested feed
" Note: The 'cgn' command silently fails to trigger insert mode if no matches found
" so we check for that. Putting <Esc> in feedkeys() cancels operation so must come
" afterward (may be no-op) and the 'i' is necessary to insert <C-a> before <Esc>.
function! tags#change_again() abort
  let motion = get(g:, 'tags_change_motion', 'n')
  let replace = "mode() ==# 'i' ? get(g:, 'tags_change_string', '') : ''"
  let replace = "\<Cmd>call feedkeys(" . replace . ", 'ti')\<CR>"
  call feedkeys('cg' . motion . replace . "\<Esc>" . motion, 'n')
  call s:feed_repeat('TagsChangeAgain')
endfunction
function! tags#change_all() abort
  let winview = winsaveview()
  let regex = escape(@/, '@')
  let string = get(g:, 'tags_change_string', '')
  let replace = escape(string, '@')
  exe 'keepjumps %s@' . regex . '@' . replace . '@ge'
  call winrestview(winview)
  call s:feed_repeat('TagsChangeAll')
endfunction
function! tags#change_setup() abort
  let setup = get(g:, 'tags_change_setup', 0)
  if !setup | return | endif
  let g:tags_change_setup = 0
  let g:tags_change_string = substitute(@., "\n", "\<CR>", 'g')
  if setup == 1  " change single item
    let motion = get(g:, 'tags_change_motion', 'n')
    call feedkeys(motion . 'zv', 'nt')
    call s:feed_repeat('TagsChangeAgain')
  else  " change all items
    call feedkeys('u', 'n')
    call feedkeys("\<Plug>TagsChangeAll", 'm')
    call s:feed_repeat('TagsChangeAll')
  endif
endfunction

" Change and delete next match
" Note: Undo first change so subsequent undo reverts all changes. Also note
" register may have keystrokes e.g. <80>kb (backspace) so must feed as 'typed'
" Note: Unlike 'change all', 'delete all' can simply use :substitute. Also note
" :hlsearch inside functions fails: https://stackoverflow.com/q/1803539/4970632
function! tags#change_next(level, force, ...) abort
  if a:level < 0  " e.g. c/
    let motion = a:0 && a:1 ? 'N' : 'n'
    let names = ['Match', motion ==# 'N' ? 'Prev' : 'Next']
  else  " e.g. c*
    let motion = 'n'
    let names = call('tags#set_search', [a:level] + a:000)
  endif
  if empty(names) | return | endif  " scope not found
  let g:tags_change_motion = motion
  call feedkeys('cg' . motion, 'n')
  let g:tags_change_setup = 1 + a:force
endfunction
function! tags#delete_next(level, force, ...) abort
  if a:level < 0
    let motion = a:0 && a:1 ? 'N' : 'n'
    let names = ['Match', motion ==# 'N' ? 'Prev' : 'Next']
  else
    let motion = 'n'
    let names = call('tags#set_search', [a:level] + a:000)
  endif
  if empty(names) | return | endif  " scope not found
  if !a:force  " delete single item
    let plug = 'TagsDelete' . names[0] . names[1]
    call feedkeys('dg' . repeat(motion, 2) . 'zv', 'n')
    call s:feed_repeat(plug)
  else  " delete all matches
    let plural = a:level < 0 ? 'es' : 's'
    let plug = 'TagsDelete' . names[0] . plural . names[1]
    let winview = winsaveview()
    exe 'keepjumps %s@' . escape(@/, '@') . '@@ge'
    call winrestview(winview)
    call s:feed_repeat(plug)
  endif
endfunction
