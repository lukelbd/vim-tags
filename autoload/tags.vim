"------------------------------------------------------------------------------
" General tag processing utiltiies
" Warning: Encountered strange error where naming .vim/autoload file same as
" vim-tags/autoload file or naming the latter to tags.vim at all caused an autocmd
" BufRead error on startup. Was impossible to diagnose so just use alternate names.
"------------------------------------------------------------------------------
" Global tags command
" Note: Keep in sync with g:fzf_tags_command
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
  let flags = join(a:000, ' ')
  let path = shellescape(expand(fnamemodify(a:path, ':p')))
  let cmd = s:tags_command . ' ' . flags . ' ' . path . ' 2>/dev/null'
  return cmd . " | cut -d'\t' -f1,3-5"
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

" List open window paths
" Todo: Also use this to jump to tags in arbitrary files? Similar to :Tags but no file.
function! tags#buffer_paths() abort
  let paths = []
  for tnr in range(tabpagenr('$'))  " iterate through each tab
    let tabnr = tnr + 1 " the tab number
    let bnrs = tabpagebuflist(tabnr)
    for bnr in bnrs
      let path = expand('#' . bnr . ':p')
      let type = getbufvar(bnr, '&filetype')
      if !filereadable(path) || index(g:tags_skip_filetypes, type) != -1
        continue
      endif
      call add(paths, path)
    endfor
  endfor
  return paths
endfunction

" Generate tags and parse them into list of lists
" Note: Files open in multiple windows use the same buffer number and same variables.
function! tags#update_tags(...) abort
  let global = a:0 ? a:1 : 0
  let paths = global ? tags#buffer_paths() : [expand('%:p')]
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
    let types = uniq(map(tags#buffer_paths(), "getbufvar(v:val, '&filetype')"))
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
    let paths = tags#buffer_paths()
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
  let paths = global ? tags#buffer_paths() : [expand('%:p')]
  let source = []
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
  let cmd = tags#set_match(a:key)
  let b:winview = winsaveview()  " store window as buffer variable
  return cmd . "\<Cmd>%s@" . @/ . "@@gne | call winrestview(b:winview)\<CR>"
endfunction

" Repeat previous change
" Note: The 'cgn' command silently fails to trigger insert mode if no matches found
" so we check for that. Putting <Esc> in feedkeys() cancels operation so must come
" afterward (may be no-op) and the 'i' is necessary to insert <C-a> before <Esc>.
function! tags#change_again() abort
  let cmd = "\<Cmd>call feedkeys(mode() =~# 'i' ? '\<C-a>' : '', 'ni')\<CR>"
  call feedkeys('cgn' . cmd . "\<Esc>n")  " add previously inserted if cgn succeeds
  if exists('*repeat#set')
    call repeat#set("\<Plug>change_again")  " re-apply this function for next repeat
  endif
endfunction

" Function that sets things up for maps that change text
" Note: Unlike tags#delete_next we wait until
function! tags#change_next(key) abort
  let cmd = tags#set_match(a:key)
  let g:change_next = 1
  if exists('*repeat#set')
    call repeat#set("\<Plug>change_again")
  endif
  return cmd . 'cgn'
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
  let cmd = tags#set_match(a:key)
  if exists('*repeat#set')
    call repeat#set("\<Plug>" . a:key, v:count)
  endif
  return cmd . 'dgnn'
endfunction

" Delete all of next matches
" Note: Unlike 'change all' this can simply call :substitute
function! tags#delete_all(key) abort
  call tags#set_match(a:key)
  let winview = winsaveview()
  exe 'keepjumps %s@' . @/ . '@@ge'
  call winrestview(winview)
endfunction

" Search within top level tags belonging to 'major' kinds
" Search func idea came from: http://vim.wikia.com/wiki/Search_in_current_function
" The below is copied from: https://stackoverflow.com/a/597932/4970632
" Note: jedi-vim 'variable rename' utility is sketchy and fails; gives us
" motivation for custom renaming, and should confirm every single instance.
function! tags#get_scope(...) abort
  let kinds = get(g:tags_major_kinds, &filetype, 'f')
  let filt = "v:val[2] =~# '[" . kinds . "]'"
  let lnum = a:0 ? a:1 : line('.')
  let items = get(b:, 'tags_by_line', [])
  let items = filter(copy(items), filt)
  if empty(items)
    echohl WarningMsg
    echom 'Warning: Failed to restrict the search scope (tags unavailable).'
    echohl None
    return ''
  endif
  let lines = map(deepcopy(items), 'v:val[1]')
  if lnum < lines[0]
    let line1 = 1
    let line2 = lines[0]
    let tag1 = 'START'
    let tag2 = items[0][0]
  elseif lnum >= lines[len(lines) - 1]
    let line1 = lines[len(lines) - 1]
    let line2 = line('$') + 1  " match below this
    let tag1 = items[len(lines) - 1][0]
    let tag2 = 'END'
  else
    for idx in range(0, len(lines) - 2)
      if lnum >= lines[idx] && lnum < lines[idx + 1]
        let line1 = lines[idx]
        let line2 = lines[idx + 1]
        let tag1 = items[idx][0]
        let tag2 = items[idx + 1][0]
        break
      endif
    endfor
  endif
  let maxlen = 20
  let regex = printf('\%%>%dl\%%<%dl', line1 - 1, line2)
  let info1 = line1 . ' (' . tag1[:maxlen] . ')'
  let info2 = line2 . ' (' . tag2[:maxlen] . ')'
  echom 'Selected line ' . info1 . ' to line ' . info2 . '.'
  return regex
endfunction

" Set the last search register to some 'current pattern' under cursor, and
" return normal mode commands for highlighting that match (must return the
" command because for some reason set hlsearch does not work inside function).
" Note: Here '!' handles multi-byte characters using example in :help byteidx. Also
" the native vim-indexed-search maps invoke <Plug>(indexed-search-after), which just
" calls <Plug>(indexed-search-index) --> :ShowSearchIndex... but causes change
" mappings to silently abort for some weird reason... so instead call this manually.
function! tags#set_match(key, ...) abort
  let scope = ''
  let motion = ''
  let inplace = a:0 && a:1 ? 1 : 0
  if a:key =~# '\*'
    let motion = 'lb'
    let @/ = '\<' . escape(expand('<cword>'), s:regex_magic) . '\>\C'
  elseif a:key =~# '&'
    let motion = 'lB'
    let @/ = '\_s\@<=' . escape(expand('<cWORD>'), s:regex_magic) . '\ze\_s\C'
  elseif a:key =~# '#'
    let motion = 'lb'
    let scope = tags#get_scope()
    let @/ = scope . '\<' . escape(expand('<cword>'), s:regex_magic) . '\>\C'
  elseif a:key =~# '@'
    let motion = 'lB'
    let scope = tags#get_scope()
    let @/ = '\_s\@<=' . scope . escape(expand('<cWORD>'), s:regex_magic) . '\ze\_s\C'
  elseif a:key =~# '!'
    let text = getline('.')
    let @/ = empty(text) ? "\n" : escape(matchstr(text, '.', byteidx(text, col('.') - 1)), s:regex_magic)
  endif  " otherwise keep current selection
  let cmds = inplace ? motion : ''
  let cmds .= "\<Cmd>setlocal hlsearch\<CR>"
  let cmds .= empty(scope) && exists(':ShowSearchIndex') ? "\<Cmd>ShowSearchIndex\<CR>" : ''
  return cmds  " see top for notes about <Plug>(indexed-search-after)
endfunction
