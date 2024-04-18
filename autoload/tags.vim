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
  let key = call('tags#kind_lang', a:000)
  let name = 'tags_' . a:name . '_kinds'  " setting name
  let opts = get(get(g:, name, {}), key, a:default)
  if type(opts) <= 1 | let opts = split(opts, '\zs') | endif
  let kind1 = get(a:tag, 2, '')  " translate to or from character
  let cache = len(kind1) > 1 ? g:tags_kind_chars : g:tags_kind_names
  let kind2 = get(get(cache, key, {}), kind1, kind1)
  return index(opts, kind1) >= 0 || index(opts, kind2) >= 0
endfunction

" Return ctags filetype or
let g:tags_kind_chars = {}
let g:tags_kind_names = {}
let g:tags_kind_langs = {}
function! tags#kind_char(kind, ...) abort
  let key = call('tags#kind_lang', a:000)
  let opts = len(a:kind) <= 1 ? {} : get(g:tags_kind_chars, key, {})
  return get(opts, a:kind, a:kind)
endfunction
function! tags#kind_name(kind, ...) abort
  let key = call('tags#kind_lang', a:000)
  let opts = len(a:kind) > 1 ? {} : get(g:tags_kind_names, key, {})
  return get(opts, a:kind, a:kind)
endfunction
function! tags#kind_lang(...) abort
  let name = getbufvar(call('bufnr', a:000), '&filetype')
  let name = substitute(tolower(name), '\..*$', '', 'g')
  return get(g:tags_kind_langs, name, name)
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
  let ftype = a:0 ? tags#kind_lang(a:1) : ''  " restricted type
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
      if !empty(ftype) && ftype !=# tags#kind_lang(bnr)
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
  let cache = a:0 > 2 ? a:3 : {}  " cached matches
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
  let regex = a:0 > 1 ? a:2 : tags#type_regex(ftype)
  let cache = a:0 > 2 ? a:3 : {}  " entries {'path': 'type', 'path': ''}
  let fast = a:0 > 3 ? a:4 : 0  " already checked this filetype
  let path = fnamemodify(a:path, ':p')
  if has_key(cache, path)
    let ctype = cache[path]
    if !empty(ctype) || fast
      return ctype ==# ftype
    endif
  endif
  let name = fnamemodify(path, ':t')
  let btype = tags#kind_lang(path)
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
  let name = empty(a:path) ? '' : tags#kind_lang(expand(a:path))
  let path = empty(a:path) ? '' : fnamemodify(expand(a:path), ':p')
  let flag = empty(name) || fnamemodify(path, ':t') =~# '\.' ? '' : '--language-force=' . name
  let cmd = 'ctags -f - --excmd=number ' . join(a:000, ' ') . ' ' . flag
  let cmd .= ' ' . shellescape(path) . ' 2>/dev/null'
  let cmd .= empty(path) ? '' : " | cut -d'\t' -f1,3-5 | sed 's/;\"\t/\t/g'"
  return system(cmd)
endfunction
function! s:generate_tags(path) abort
  let ftype = tags#kind_lang(a:path)  " possibly empty string
  if index(g:tags_skip_filetypes, ftype) >= 0
    let items = []
  else  " generate tags
    let items = split(s:execute_tags(a:path), '\n')
  endif
  call map(items, "split(v:val, '\t')")
  call filter(items, '!tags#is_skipped(v:val)')
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

" Update tag buffer variables and kind global variables
" Note: This will only update when tag generation time more recent than last file
" save time. Also note files open in multiple windows have the same buffer number
" Note: Ctags has both language 'aliases' for translating internal options like
" --language-force and 'mappings' that convert file names to languages. Seems alias
" defitions were developed with vim in mind so no need to use their extensions.
function! tags#update_tags(...) abort
  let global = a:0 ? a:1 : 0
  if empty(g:tags_kind_names) || empty(g:tags_kind_chars)
    call tags#update_kinds()
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
    let types = uniq(map(tags#buffer_paths(), 'tags#kind_lang(v:val[1])'))
    let label = 'all buffer filetypes'
  elseif a:0  " input filetype(s)
    let types = uniq(sort(map(copy(a:000), 'tags#kind_lang(v:val)')))
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

"-----------------------------------------------------------------------------
" Tag selection utiltiies
"-----------------------------------------------------------------------------
" Return index of input tag in the stack
" Note: This is used to manually update the tag stack index, allowing us to emulate
" native vim :tag with tags#iter_tags(1, ...) and :pop with tags#iter_tags(-1, ...).
function! s:get_index(name, ...) abort  " stack index
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

" Return truncated paths
" Todo: Use gutentags internal root finder and fix issues with duplicate names.
" Note: This truncates tag paths as if they were generated by gutentags and written
" to tags files. If root finder unavailable also try relative to git repository.
function! s:path_base(path) abort
  let base = get(b:, 'gutentags_root', '')  " see also statusline.vim
  if empty(base) && exists('*FugitiveExtractGitDir')
    let base = FugitiveExtractGitDir(a:path)
    let base = empty(base) ? base : fnamemodify(base, ':h')
  endif | return base
endfunction
function! s:path_name(path, ...) abort
  let names = a:0 > 0 ? a:1 : {}  " cached names
  let heads = a:0 > 1 ? a:2 : {}  " cached heads
  let path = fnamemodify(a:path, ':p')
  let name = get(names, path, '')
  if !empty(name) | return name | endif
  let base = s:path_base(path)  " remove '.git' heading
  let head = fnamemodify(fnamemodify(base, ':h'), ':p')  " root with trailing slash
  let icwd = !empty(base) && strpart(getcwd(), 0, len(base)) ==# base
  let ipath = !empty(base) && strpart(path, 0, len(base)) ==# base
  if ipath && !icwd
    let name = strpart(path, len(head)) | let heads[name] = head
  elseif exists('*RelativePath')
    let name = RelativePath(path)
  else  " default display
    let name = fnamemodify(path, ':~:.')
  endif
  let names[path] = name | return name
endfunction

" Return tags in the format '[<file>: ]<line>: name (type[, scope])'
" for selection by fzf. File name included only if 'global' was passed.
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
function! s:tag_source(level, ...) abort
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
  let [result, names, heads] = [[], {}, {}]  " path name caches
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
      call map(opts, show ? '[s:path_name(v:val[0], names, heads)] + v:val[1:]' : 'v:val')
      call map(opts, 'add(v:val[:idx], join(v:val[jdx:], ", "))')
      call map(opts, 'call("printf", [' . string(fmt . '%4d: %s (%s)') . '] + v:val)')
    endif
    call extend(result, uniq(opts))  " ignore duplicates
  endfor
  return [result, names, heads]
endfunction

" Navigate to input tag list or fzf selection
" Note: This supports reading base path from trailing tab-delimited character. For
" now not implemented in dotfiles since slow for huge libraries (even though needed
" for large tags libraries). Also note this positions cursor on exact tag column.
function! tags#goto_tag(...) abort  " :tag <name> analogue
  return call('s:goto_tag', [0] + a:000)
endfunction
function! tags#jump_tag(mode, ...) abort  " 1:naked tag/pop, 2:bracket jump
  return call('s:goto_tag', [a:mode] + a:000)
endfunction
function! s:goto_tag(mode, ...) abort
  " Parse tag input
  let from = getpos('.')  " from position
  let from[0] = bufnr()  " ensure correct buffer
  let path = expand('%:p')  " current path
  let iloc = ''  " source vimtags file
  let native = '^\s*\(.\{-}\) *\t\(.\{-}\) *\t\(\d\+\)\%(;"\s*\(.*\)\)\?$'
  let custom = '^\%(\(.\{-}\):\)\?\s*\(\d\+\):\s\+\(.\{-}\)\s\+(\(.*\))$'
  if a:0 > 1  " non-fzf input
    let [ibuf, ipos, name; extra] = a:0 > 2 ? a:000 : [path] + a:000
  elseif a:0 && a:1 =~# custom  " format '[<file>: ]<line>: name (kind[, scope])'
    let [ibuf, ipos, name; extra] = matchlist(a:1, custom)[1:4]
  elseif a:0 && a:1 =~# native  " native format 'name<Tab>file<Tab>line;\"kind<Tab>scope'
    let [name, ibuf, ipos; extra] = matchlist(a:1, native)[1:4]
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
  let heads = get(s:, 'path_heads', {})  " optional cache
  if empty(ibuf)
    let ipath = path
  elseif !type(ibuf)
    let ipath = expand('#' . ibuf . ':p')
  elseif filereadable(ibuf)
    let ipath = fnamemodify(ibuf, ':p')
  elseif !empty(base)
    let ipath = fnamemodify(base, ':p') . ibuf
  elseif has_key(heads, ibuf)  " relative to repo
    let ipath = s:path_heads[ibuf] . ibuf
  else  " absolute path
    redraw | echohl ErrorMsg
    echom 'Error: Path ' . string(ibuf) . ' does not exist.'
    echohl None | return
  endif
  let g:tag_name = [ipath, ipos, name]  " dotfiles stacks
  if ipath ==# path  " record mark
    exe a:mode && g:tags_keep_jumps || getpos("''") == getpos('.') ? '' : "normal! m'"
  elseif exists('*file#open_drop')  " dotfiles utility
    silent call file#open_drop(ipath)
  else  " built-in utility
    silent exe 'tab drop ' . fnameescape(ipath)
  endif
  " Jump to tag position
  let [lnum, cnum] = type(ipos) == type([]) ? ipos : [ipos, 0]
  call cursor(lnum, 1)
  if cnum <= 0
    let regex = substitute(escape(name, s:regex_magic), '·*$', '', '')
    silent call search(regex, 'cW', lnum)
  elseif cnum > 1
    let motion = (cnum - 1) . 'l'
    exe 'normal! ' . motion
  endif
  if !a:mode && !g:tags_keep_stack && name !=# '<top>'  " perform :tag <name>
    let item = {'bufnr': bufnr(), 'from': from, 'matchnr': 1, 'tagname': name}
    if item.bufnr != from[0] || lnum != from[1]  " push from curidx to top
      call settagstack(winnr(), {'items': [item]}, 't')
    endif
  elseif abs(a:mode) == 1  " perform :tag or :pop
    let idx = s:get_index(name, a:mode)
    if idx > 0  " assign new stack index
      call settagstack(winnr(), {'curidx': idx})
    endif
  endif
  let word = a:mode ? '\<block\>' : '\<tag\>'
  let keys = a:0 == 1 ? 'zz' : ''
  let keys .= &l:foldopen =~# word ? 'zv' : ''
  let keys .= a:mode && g:tags_keep_jumps || getpos("''") == getpos('.') ? '' : "m'"
  exe empty(keys) ? '' : 'normal! ' . keys
  let [kind; rest] = extra  " see above
  let name = tags#kind_name(kind)
  let kind = empty(name) ? kind : name
  let info = join(empty(kind) ? rest : [kind] + rest, ', ')
  let info = empty(info) ? '' : ' (' . info . ')'
  redraw | echom 'Tag: ' . name . info
endfunction

" Select a specific tag using fzf
" See: https://github.com/ludovicchabant/vim-gutentags/issues/349
" Note: Usage is tags#select_tag(paths_or_level, options_or_iter) where second
" argument indicates whether stacks should be updated (tags#goto_tag) or not
" (tags#jump_tag) and first argument indicates the paths to search and whether to
" display the path in the fzf prompt. The second argument can also be a list of tags
" in the format [line, name, other] (or [path, line, name, other] if level > 0)
function! tags#_select_tag(heads, mode, item) abort
  let s:path_heads = a:heads
  let name = a:mode ? 'tags#jump_tag' : 'tags#goto_tag'
  if exists('*stack#push_stack')
    let arg = a:mode ? type(a:item) > 1 ? [a:mode] + a:item : [a:mode, a:item] : a:item
    call stack#push_stack('tag', name, arg, 0)
  else
    let arg = a:mode ? [a:mode, a:item] : [a:item]
    call call(name, arg)
  endif
  let s:path_heads = {} | return
endfunction
function! tags#select_tag(level, ...) abort
  let input = a:0 && !empty(a:1)
  let mode = a:0 > 1 ? a:2 : 0
  let char = input || type(a:level) > 1 ? 'S' : a:level < 1 ? 'B' : a:level < 2 ? 'F' : ''
  let [result, names, heads] = s:tag_source(a:level, input ? a:1 : 1)
  if empty(result)
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
    \ 'source': result,
    \ 'sink': function('tags#_select_tag', [heads, mode]),
    \ 'options': '--no-sort --prompt=' . string(char . 'Tag> ')
  \ }
  call fzf#run(fzf#wrap(options))
endfunction

"-----------------------------------------------------------------------------"
" Tag navigation utilities
"-----------------------------------------------------------------------------"
" Get tags and tag files using &g:tags setting
" Note: Here tagfiles() function returns buffer-local variables so use &g:tags instead,
" and note that literal commas/spaces preced by backslash (see :help option-backslash).
" Note: Here modify &l:tags temporarily to optionally exclude unrelated projects, since
" taglist() uses tagfiles() which may include unrelated projects if &l:tags unset. Also
" note function expects regex i.e. behaves like :tags /<name> (see :help taglist()).
function! tags#get_tags(name, ...) abort
  let regex = '^' . escape(a:name, s:regex_magic) . '$'
  let path = expand(a:0 ? a:1 : '%')
  let tags = call('tags#get_files', a:000)
  call map(tags, {_, val -> substitute(val, '\(,\| \)', '\\\1', 'g')})
  let [itags, jtags] = [&l:tags, join(tags, ',')]
  try
    let &l:tags = jtags
    return taglist(regex, path)
  finally
    let &l:tags = itags
  endtry
endfunction
function! tags#get_files(...) abort
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

" Go to the tag keyword under the cursor
" Note: Vim does not natively support jumping separate windows so implement here
let s:keyword_mods = {'vim': ':', 'tex': ':-'}
function! tags#goto_name(...) abort
  let cache = {}
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
  for name in names
    let name = substitute(name, '\(^\s*\|\s*$\)', '', 'g')
    if empty(name) | return | endif
    let itags = tags#get_tags(name, path)
    for itag in itags  " search 'tags' files
      let ipath = fnamemodify(itag.filename, ':p')
      if level < 1 && ipath !=# path | continue | endif
      let itype = tags#type_paths([ipath], &l:filetype, cache)
      if level < 2 && empty(itype) | continue | endif
      let item = [ipath, itag.cmd, itag.name, itag.kind]
      return tags#_select_tag({}, 0, item)
    endfor
    let [itags; rest] = s:tag_source(level, 0)  " search buffer tag variables
    for [ipath, iline, iname; irest] in itags
      if name !=# iname | continue | endif
      let item = [ipath, iline, iname] + irest
      return tags#_select_tag({}, 0, item)
    endfor
  endfor
  redraw | echohl ErrorMsg
  echom 'Error: Tag ' . string(names[0]) . ' not found'
  echohl None | return 1
endfunction

" Find the tag closest to the input position
" Note: This translates tag to single-character for use e.g. in statusline
function! tags#find_tag(...) abort
  let pos = a:0 > 0 ? a:1 : line('.')
  let bnum = type(pos) > 1 && !empty(pos[0]) ? bufnr(pos[0]) : bufnr()
  let lnum = type(pos) > 1 ? pos[1] : type(pos) ? str2nr(pos) : pos
  let major = a:0 > 1 ? a:2 : 0
  let forward = a:0 > 2 ? a:3 : 0
  let circular = a:0 > 3 ? a:4 : 0
  if major  " major tags only
    let filt = 'len(v:val) == 3 && tags#is_major(v:val)'
  else  " all except minor
    let filt = 'len(v:val) > 2 && !tags#is_minor(v:val)'
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
      if !forward && lnum <= items[jdx][1]
        let idx = jdx - 1 | break
      endif
    endfor
  endif
  let [name, lnum, kind; rest] = items[idx]
  let kind = tags#kind_char(kind)
  return [name, lnum, kind] + rest
endfunction

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
  redraw | echom 'Keyword: ' . prefix . suffix
  exe &l:foldopen =~# '\<block\>' ? 'normal! zv' : ''
endfunction

"-----------------------------------------------------------------------------"
" Keyword searching utilities
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
  let items = get(b:, 'tags_by_line', [])
  let items = filter(copy(items), 'tags#is_major(v:val)')
  let lines = map(deepcopy(items), 'str2nr(v:val[1])')
  if empty(items)
    redraw | echohl WarningMsg
    echom 'Error: Failed to restrict the search scope (tags unavailable).'
    echohl None | return ''
  endif
  let winview = winsaveview()
  exe a:0 ? a:1 : '' | let lnum = line('.')
  let [iline, line1, level1] = [-1, lnum, foldlevel('.')]
  while iline != line1 && index(lines, line1) == -1
    let [iline, ifold] = [line('.'), foldclosed('.')]
    exe ifold > 0 && iline != ifold ? ifold : 'keepjumps normal! [z'
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
    let label1 = items[idx][0]
    let label2 = trim(getline(line2))
  elseif !a:force  " fallback to global search
    let [line1, line2] = [1, line('$')]
    let [label1, label2] = ['START', 'END']
  else
    let msg = isfold ? 'current scope is global' : 'major tag fold not found'
    redraw | echohl WarningMsg
    echom 'Error: Failed to restrict the search scope (' . msg . ').'
    echohl None | return ''
  endif
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
function! tags#change_next(level, force, ...) abort
  if a:level < 0  " e.g. c/
    let motion = a:0 && a:1 ? 'N' : 'n'
    let names = ['Match', motion ==# 'N' ? 'Prev' : 'Next']
  else  " e.g. c*
    let motion = 'n'
    let names = call('tags#set_search', [a:level] + a:000)
  endif
  if empty(names) | return | endif  " scope not found
  let s:change_motion = motion
  call feedkeys('cg' . motion, 'n')
  if !a:force  " change single match
    let s:change_setup = ''
    call s:feed_repeat('TagsChangeRepeat')
  else  " change all matches
    let plural = a:level < 0 ? 'es' : 's'
    let plug = 'TagsChange' . names[0] . plural . names[1]
    let s:change_setup = plug
    call s:feed_repeat(plug)
  endif
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
