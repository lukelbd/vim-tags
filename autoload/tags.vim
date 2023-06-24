"------------------------------------------------------------------------------
" General tag processing utiltiies
" Warning: Encountered strange error where naming .vim/autoload file same as
" vim-tags/autoload file or naming the latter to tags.vim at all caused an autocmd
" BufRead error on startup. Was impossible to diagnose so just use alternate names.
"------------------------------------------------------------------------------
" Tags command
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
" Results should be in number mode (i.e. shows line number instead of line)
function! s:get_tags(path, ...) abort
  let flags = join(a:000, ' ')
  let path = shellescape(expand(fnamemodify(a:path, ':p')))
  return s:tags_command . ' ' . flags . ' ' . path . " 2>/dev/null | cut -d'\t' -f1,3-5"
endfunction

" List open window paths
" Todo: Also use this to jump to tags in arbitrary files? Similar to :Tags but no file.
function! s:get_paths() abort
  let paths = []
  for tnr in range(tabpagenr('$'))  " iterate through each tab
    let tabnr = tnr + 1 " the tab number
    let tbufs = tabpagebuflist(tabnr)
    for bnr in tbufs
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

" Helper tag utility
" Used to put both results in same message
function! tags#show_both(...) abort
  call call('tags#show_kinds', a:000)
  call call('tags#show_tags', a:000)
endfunction

" Show the current file kinds
" Note: See https://stackoverflow.com/a/71334/4970632 for difference between \r and \n
function! tags#show_kinds(...) abort
  let global = a:0 ? a:1 : 0
  let kind = global ? 'all' : &filetype
  let cmd = s:get_tags('', '--list-kinds=' . string(kind))
  let cmd = substitute(cmd, '|.*$', '', 'g')
  let table = system(cmd)
  if global
    let l:subs = []
    let types = uniq(map(s:get_paths(), "getbufvar(v:val, '&filetype')"))
    let regex = '\c\(\%(\n\|^\)\@<=\%(' . join(types, '\|') . '\)\n'
    let regex = regex . '\%(\s\+[^\n]*\%(\n\|$\)\)*\)\S\@!'
    let repl = '\=add(l:subs, submatch(0))'  " see: https://vi.stackexchange.com/a/16491/8084
    call substitute(table, regex, repl, 'gn')
    let table = join(l:subs, '')
  endif
  let head = global ? 'Tag kinds for open filetypes' : "Tag kinds for filetype '" . &filetype . "'"
  echo head . ":\n" . table
endfunction

" Show the current file tags
" Note: This also calls UpdateTags so that printed tags match buffer variables.
function! tags#show_tags(...) abort
  call call('tags#update_tags', a:000)
  let global = a:0 ? a:1 : 0
  let paths = global ? s:get_paths() : [expand('%:p')]
  let table = []
  for path in paths  " always absolutes
    let cmd = s:get_tags(path) . " | tr -s '\t' | column -t -s '\t'"
    let tags = system(cmd)  " call ctags command
    let tags = substitute(tags, '^\_s*\(.\{-}\)\_s*$', '\1', '')  " strip whitespace
    if !empty(tags)
      let tags = substitute(tags, escape(path, s:regex_magic), '', 'g')
      if len(paths) > 1
        let tags = substitute(tags, '\(^\|\n\)', '\1    ', 'g')
        let tags = fnamemodify(path, ':~:.') . "\n" . tags
      endif
      call add(table, tags)
    endif
  endfor
  if empty(table)
    echohl WarningMsg
    echom 'Warning: Tags not found or not available.'
    echohl None
    return
  endif
  let head = global ? 'Tags for open files' : "Tags for file '" . expand('%:~:.') . "'"
  echo head . ":\n" . join(table, "\n")
endfunction

" Generate tags and parse them into list of lists
" Note: Files open in multiple windows use the same buffer number and same variables.
function! tags#update_tags(...) abort
  let global = a:0 ? a:1 : 0
  let paths = global ? s:get_paths() : [expand('%:p')]
  for path in paths
    " Possibly skip
    let bnr = bufnr(path)  " buffer unique to path
    let type = getbufvar(bnr, '&filetype')
    let time = getbufvar(bnr, 'tags_update_time', 0)
    if getftime(path) < time | continue | endif
    if index(g:tags_skip_filetypes, type) != -1 | continue | endif
    " Retrieve tags
    let flags = getline(1) =~# '#!.*python[23]' ? '--language-force=python' : ''
    let tags = system(s:get_tags(path, flags) . " | sed 's/;\"\t/\t/g'")
    let tags = map(split(tags, '\n'), "split(v:val, '\t')")
    let filt = "v:val[2] !~# '[" . get(g:tags_skip_kinds, type, '@') . "]'"
    let tags = filter(tags, filt)
    " Get helper variables
    let by_name = sort(deepcopy(tags), 's:sort_by_name')  " sort alphabetically by name
    let by_line = sort(deepcopy(tags), 's:sort_by_line')  " sort numerically by line
    let scope_filt = "v:val[2] =~# '[" . get(g:tags_scope_kinds, type, 'f') . "]'"
    let top_filt = 'len(v:val) == 3'  " does not belong to larger tag
    let scope_by_line = filter(deepcopy(by_line), scope_filt)
    let top_by_line = filter(deepcopy(by_line), top_filt . ' && ' . scope_filt)
    " Set helper variables
    call setbufvar(bnr, 'tags_by_name', by_name)
    call setbufvar(bnr, 'tags_by_line', by_line)
    call setbufvar(bnr, 'tags_scope_by_line', scope_by_line)
    call setbufvar(bnr, 'tags_top_by_line', top_by_line)
    call setbufvar(bnr, 'tags_update_time', localtime())
  endfor
endfunction

"-----------------------------------------------------------------------------
" Tag navigation utiltiies
"-----------------------------------------------------------------------------
" Get the current tag from a list of tags
" Note: This function searches exclusively (i.e. does not match the current line).
" So only start at current line when jumping, otherwise start one line down.
function! tags#close_tag(line, toplevel, forward, circular) abort
  let bufvar = a:toplevel ? 'b:tags_top_by_line' : 'b:tags_by_line'
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
function! tags#current_tag(...) abort
  let tag = tags#close_tag(line('.') + 1, 0, 0, 0)
  let full = a:0 ? a:1 : 1  " print full tag
  if empty(tag)
    return ''
  elseif full && len(tag) == 4  " indicates extra information
    return tag[2] . ':' . substitute(tag[3], '^.*:', '', '') . ':' . tag[0]
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

" Select a specific tag using fzf
" Note: This matches construction of fzf mappings in vim-succinct.
function! tags#select_tag() abort
  let tags = s:tag_source()
  if empty(tags)
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
    \ 'source': tags,
    \ 'sink': function('s:tag_sink'),
    \ 'options': "--no-sort --prompt='Tag> '",
    \ }))
endfunction

" Return a list of strings for the an menu in the format: '<line number>: name (type)'
" or the format '<line number>: name (type, scope)' if scope information is present.
" Then the sink function simply gets the line number before the colon.
" See: https://github.com/junegunn/fzf/wiki/Examples-(vim)
function! s:tag_sink(tag) abort
  exe split(a:tag, ':')[0]
endfunction
function! s:tag_source() abort
  let tags = get(b:, 'tags_by_name', [])
  let tags = deepcopy(tags)
  return map(tags, "printf('%4d', v:val[1]) . ': ' . v:val[0] . ' (' . join(v:val[2:], ', ') . ')'")
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

" Finish change after InsertLeave and automatically jump to next occurence.
" Warning: The @. register may contain keystrokes like <80>kb (i.e. backspace) so
" must feed keys as if typed rather than as if from mapping.
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

" Repeat previous change
" Warning: The 'cgn' command silently fails to trigger insert mode if no matches found
" so we check for that. Putting <Esc> in feedkeys() cancels operation so must come
" afterward (may be no-op) and the 'i' is necessary to insert <C-a> before <Esc>.
function! tags#change_again() abort
  let cmd = "\<Cmd>call feedkeys(mode() =~# 'i' ? '\<C-a>' : '', 'ni')\<CR>"
  call feedkeys('cgn' . cmd . "\<Esc>n")  " add previously inserted if cgn succeeds
  if exists('*repeat#set')
    call repeat#set("\<Plug>change_again")  " re-apply this function for next repeat
  endif
endfunction

" Delete next match
" Warning: hlsearch inside function fails: https://stackoverflow.com/q/1803539/4970632
function! tags#delete_next(key) abort
  let cmd = tags#set_match(a:key)
  if exists('*repeat#set')
    call repeat#set("\<Plug>" . a:key, v:count)
  endif
  return cmd . 'dgnn'
endfunction

" Delete all of next matches
function! tags#delete_all(key) abort
  call tags#set_match(a:key)
  let winview = winsaveview()
  exe 'keepjumps %s@' . @/ . '@@ge'
  call winrestview(winview)
endfunction

" Search within top level tags belonging to 'scope' kinds
" Search func idea came from: http://vim.wikia.com/wiki/Search_in_current_function
" The Below is copied from: https://stackoverflow.com/a/597932/4970632
" Note jedi-vim 'variable rename' utility is sketchy and fails; gives us
" motivation for custom renaming, and should confirm every single instance.
function! tags#set_scope(...) abort
  let lnum = a:0 ? a:1 : line('.')
  if !exists('b:tags_scope_by_line') || len(b:tags_scope_by_line) == 0
    echohl WarningMsg
    echom 'Warning: Failed to restrict the search scope (tags unavailable).'
    echohl None
    return ''
  endif
  let taglines = map(deepcopy(b:tags_scope_by_line), 'v:val[1]')
  if lnum < taglines[0]
    let line1 = 1
    let line2 = taglines[0]
    let scope1 = 'START'
    let scope2 = b:tags_scope_by_line[0][0]
  elseif lnum >= taglines[len(taglines) - 1]
    let line1 = taglines[len(taglines) - 1]
    let line2 = line('$') + 1  " match below this
    let scope1 = b:tags_scope_by_line[len(taglines) - 1][0]
    let scope2 = 'END'
  else
    for idx in range(0, len(taglines) - 2)
      if lnum >= taglines[idx] && lnum < taglines[idx + 1]
        let line1 = taglines[idx]
        let line2 = taglines[idx + 1]
        let scope1 = b:tags_scope_by_line[idx][0]
        let scope2 = b:tags_scope_by_line[idx + 1][0]
        break
      endif
    endfor
  endif
  let maxlen = 20
  let regex = printf('\%%>%dl\%%<%dl', line1 - 1, line2)
  let info1 = line1 . ' (' . scope1[:maxlen] . ')'
  let info2 = line2 . ' (' . scope2[:maxlen] . ')'
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
    let scope = tags#set_scope()
    let @/ = scope . '\<' . escape(expand('<cword>'), s:regex_magic) . '\>\C'
  elseif a:key =~# '@'
    let motion = 'lB'
    let scope = tags#set_scope()
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
