" Plugin to highlight multiple words in different colors.
" Version 2008-11-19 from http://vim.wikia.com/wiki/VimTip1572
" File highlights.csv (in same directory as script) defines the highlights.
"
" Type ':HighlightMaps' to toggle mapping of keypad on/off (assuming \ leader).
" (vim-ide: \m belongs to vim-mark, see the note above s:MatchToggle.)
" Type '\f' to find the next match; '\F' to find backwards.
" Can also type '\n' or '\N' for search; then n or N will find next.
" On the numeric keypad, press:
"   1 to highlight visually selected text or current word
"     using highlight group hl1 (defined below)
"   2 for highlight hl2, 3 for highlight hl3, etc
"     (can press 1 to 9 on keypad for highlights hl1 to hl9)
"   0 to remove highlight from current word
"   - to remove all highlights in current window
"   + to restore highlights cleared with '-' in current window
"   * to restore highlights (possibly from another window)
" Can press 1 or 2 on main keyboard before keypad 1..9 for more highlights.
" Commands:
"   ':Highlight' list all highlights.
"   ':Highlight [n [pattern]]' set highlight.
"   ':Hsample' display all highlights in a scratch buffer.
"   ':Hclear [hlnum|pattern|*]' clear highlights.
"   ':Hsave x', ':Hrestore x' save/restore highlights (x any name).
" Saving current highlights requires '!' in 'viminfo' option.
if v:version < 702 || exists('loaded_highlightmultiple') || &cp
  finish
endif
let loaded_highlightmultiple = 1
 
" On first call, read file highlights.csv in same directory as script.
" For example, line "5,white,blue,black,green" executes:
" highlight hl5 ctermfg=white ctermbg=blue guifg=black guibg=green
let s:data_file = expand('<sfile>:p:r').'.csv'
let s:loaded_data = 0
function! LoadHighlights()
  if !s:loaded_data
    if filereadable(s:data_file)
      let names = ['hl', 'ctermfg=', 'ctermbg=', 'guifg=', 'guibg=']
      for line in readfile(s:data_file)
        let fields = split(line, ',', 1)
        if len(fields) == 5 && fields[0] =~ '^\d\+$'
          let cmd = range(5)
          call map(cmd, 'names[v:val].fields[v:val]')
          call filter(cmd, 'v:val!~''=$''')
          execute 'silent highlight '.join(cmd)
        endif
      endfor
      let s:loaded_data = 1
    endif
    if !s:loaded_data
      echo 'Error: Could not read highlight data from '.s:data_file
    endif
  endif
endfunction
 
" Return last visually selected text or '\<cword\>'.
" what = 1 (selection), or 2 (cword), or 0 (guess if 1 or 2 is wanted).
function! s:Pattern(what)
  if a:what == 2 || (a:what == 0 && histget(':', -1) =~# '^H')
    let result = expand("<cword>")
    if !empty(result)
      let result = '\<'.result.'\>'
    endif
  else
    let old_reg = getreg('"')
    let old_regtype = getregtype('"')
    normal! gvy
    let result = substitute(escape(@@, '\.*$^~['), '\_s\+', '\\_s\\+', 'g')
    normal! gV
    call setreg('"', old_reg, old_regtype)
  endif
  return result
endfunction
 
" Remove any highlighting for hlnum then highlight pattern (if not empty).
" If pat is numeric, use current word or visual selection and
" increase hlnum by count*10 (if count [1..9] is given).
function! s:DoHighlight(hlnum, pat, decade)
  call LoadHighlights()
  let hltotal = a:hlnum
  if 0 < a:decade && a:decade < 10
    let hltotal += a:decade * 10
  endif
  if type(a:pat) == type(0)
    let pattern = s:Pattern(a:pat)
  else
    let pattern = a:pat
  endif
  let id = hltotal + 100
  silent! call matchdelete(id)
  if !empty(pattern)
    try
      call matchadd('hl'.hltotal, pattern, -1, id)
    catch /E28:/
      echo 'Highlight hl'.hltotal.' is not defined'
    endtry
  endif
endfunction
 
" Remove all matches for pattern.
function! s:UndoHighlight(pat)
  if type(a:pat) == type(0)
    let pattern = s:Pattern(a:pat)
  else
    let pattern = a:pat
  endif
  for m in s:OwnMatches()
    if m.pattern ==# pattern
      call matchdelete(m.id)
    endif
  endfor
endfunction
 
" Return pattern to search for next match, and do search.
function! s:Search(backward)
  let patterns = []
  for m in s:OwnMatches()
    call add(patterns, m.pattern)
  endfor
  if empty(patterns)
    let pat = ''
  else
    let pat = join(patterns, '\|')
    call search(pat, a:backward ? 'b' : '')
  endif
  return pat
endfunction
 
" vim-ide: 켤 때 덮어쓰는 키의 원래 매핑을 적어 두었다가 끌 때 되돌린다.
" 예전에는 끌 때 unmap/nunmap 만 해서, 켜기 전에 있던 vim-ide 의 \f(:Gtags -P)와
" vim-mark 의 \n \* 가 그 세션 내내 사라졌다 (QA). 토글 키도 \m 에서
" :HighlightMaps 로 옮겼다 - \m 은 vim-mark 의 마크 키다 (.vimrc 의 F4 옆).
let s:saved_maps = []

function! s:SaveMaps()
  let s:saved_maps = []
  let keys = map(range(0, 9), 'string(v:val)') + ['-', '+', '*', 'f', 'F', 'n', 'N']
  for k in keys
    for mode in ['n', 'x']
      let d = maparg('<Leader>' . k, mode, 0, 1)
      " 버퍼 매핑은 우리가 덮은 것이 아니다 (전역만 건다)
      if !empty(d) && !get(d, 'buffer', 0)
        call add(s:saved_maps, [mode, d])
      endif
    endfor
  endfor
endfunction

function! s:RestoreMaps()
  for [mode, d] in s:saved_maps
    if exists('*mapset')
      call mapset(mode, 0, d)
    else
      " vim 8.1 에는 mapset() 이 없다
      let cmd = mode . (d.noremap ? 'noremap' : 'map')
      for o in ['nowait', 'silent', 'expr']
        if get(d, o, 0)
          let cmd .= ' <' . o . '>'
        endif
      endfor
      execute cmd d.lhs d.rhs
    endif
  endfor
  let s:saved_maps = []
endfunction

" Enable or disable mappings and any current matches.
function! s:MatchToggle()
  if exists('g:match_maps') && g:match_maps
    let g:match_maps = 0
    for i in range(0, 9)
      execute 'silent! unmap <Leader>'.i.''
    endfor
    silent! nunmap <Leader>-
    silent! nunmap <Leader>+
    silent! nunmap <Leader>*
    silent! nunmap <Leader>f
    silent! nunmap <Leader>F
    silent! nunmap <Leader>n
    silent! nunmap <Leader>N
    call s:RestoreMaps()
  else
    let g:match_maps = 1
    call s:SaveMaps()
    for i in range(1, 9)
      execute 'vnoremap <silent> <Leader>'.i.' :<C-U>call <SID>DoHighlight('.i.', 1, v:count)<CR>'
      execute 'nnoremap <silent> <Leader>'.i.' :<C-U>call <SID>DoHighlight('.i.', 2, v:count)<CR>'
    endfor
    vnoremap <silent> <Leader>0 :<C-U>call <SID>UndoHighlight(1)<CR>
    nnoremap <silent> <Leader>0 :<C-U>call <SID>UndoHighlight(2)<CR>
    nnoremap <silent> <Leader>- :call <SID>WindowMatches(0)<CR>
    nnoremap <silent> <Leader>+ :call <SID>WindowMatches(1)<CR>
    nnoremap <silent> <Leader>* :call <SID>WindowMatches(2)<CR>
    nnoremap <silent> <Leader>f :call <SID>Search(0)<CR>
    nnoremap <silent> <Leader>F :call <SID>Search(1)<CR>
    nnoremap <silent> <Leader>n :let @/=<SID>Search(0)<CR>
    nnoremap <silent> <Leader>N :let @/=<SID>Search(1)<CR>
  endif
  call s:WindowMatches(g:match_maps)
  echo 'Mappings for matching:' g:match_maps ? 'ON' : 'off'
endfunction
command! HighlightMaps call s:MatchToggle()

" vim-ide: 이 플러그인이 만든 매치(hl1..hl99)만 다룬다. 예전에는 getmatches()/
" clearmatches()/setmatches() 로 창의 매치를 통째로 다뤄서, 끌 때 vim-mark(F4)·
" 참조 강조·노란 표시까지 지웠고, 켤 때는 옛 사본으로 덮어 그 사이에 칠한 것을
" 날렸다 (QA).
function! s:OwnMatches()
  return filter(getmatches(), 'v:val.group =~# ''^hl\d\+$''')
endfunction

function! s:SetOwnMatches(list)
  for m in s:OwnMatches()
    call matchdelete(m.id)
  endfor
  for m in a:list
    if get(m, 'group', '') =~# '^hl\d\+$'
      try
        call matchadd(m.group, m.pattern, m.priority, m.id)
      catch /E801:/
        " 그 id 를 다른 것이 쓰고 있다: id 없이
        silent! call matchadd(m.group, m.pattern, m.priority)
      catch
      endtry
    endif
  endfor
endfunction
 
" Remove and save current matches, or restore them.
function! s:WindowMatches(action)
  call LoadHighlights()
  if a:action == 1
    if exists('w:last_matches')
      call s:SetOwnMatches(w:last_matches)
    endif
  elseif a:action == 2
    if exists('g:last_matches')
      call s:SetOwnMatches(g:last_matches)
    else
      call s:Hrestore('')
    endif
  else
    let m = s:OwnMatches()
    if !empty(m)
      let w:last_matches = m
      let g:last_matches = m
      call s:Hsave('')
      call s:SetOwnMatches([])
    endif
  endif
endfunction
 
" Return name of global variable to save value ('' if invalid).
function! s:NameForSave(name)
  if a:name =~# '^\w*$'
    return 'HI_SAVE_'.toupper(a:name)
  endif
  echo 'Error: Invalid name "'.a:name.'"'
  return ''
endfunction
 
" Return custom completion string (match patterns).
function! s:MatchPatterns(A, L, P)
  return join(sort(map(getmatches(), 'v:val.pattern')), "\n")
endfunction
 
" Return custom completion string (saved highlight names).
function! s:SavedNames(A, L, P)
  let l = filter(keys(g:), 'v:val =~# ''^HI_SAVE_\w''')
  return tolower(join(sort(map(l, 'strpart(v:val, 8)')), "\n"))
endfunction
 
" Save current highlighting in a global variable.
function! s:Hsave(name)
  let sname = s:NameForSave(a:name)
  if !empty(sname)
    let l = s:OwnMatches()
    call map(l, 'join([v:val.group, v:val.pattern, v:val.priority, v:val.id], "\t")')
    let g:{sname} = join(l, "\n")
  endif
endfunction
command! -nargs=? -complete=custom,s:SavedNames Hsave call s:Hsave('<args>')
 
" Restore current highlighting from a global variable.
function! s:Hrestore(name)
  call LoadHighlights()
  let sname = s:NameForSave(a:name)
  if !empty(sname)
    if exists('g:{sname}')
      let matches = []
      for l in split(g:{sname}, "\n")
        let f = split(l, "\t", 1)
        call add(matches, {'group':f[0], 'pattern':f[1], 'priority':f[2], 'id':f[3]})
      endfor
      call s:SetOwnMatches(matches)
    else
      echo 'No such global variable: '.sname
    endif
  endif
endfunction
command! -nargs=? -complete=custom,s:SavedNames Hrestore call s:Hrestore('<args>')
 
" Clear a match, or clear all current matches. Example args:
"   '14' = hl14, '*' = all, '' = visual selection or cword,
"   'pattern' = all matches for pattern
function! s:Hclear(pattern) range
  if empty(a:pattern)
    call s:UndoHighlight(0)
  elseif a:pattern == '*'
    call s:WindowMatches(0)
  elseif a:pattern =~ '^[1-9][0-9]\?$'
    call s:DoHighlight(str2nr(a:pattern), '', 0)
  else
    call s:UndoHighlight(a:pattern)
  endif
endfunction
command! -nargs=* -complete=custom,s:MatchPatterns -range Hclear call s:Hclear('<args>')
 
" Create a scratch buffer with sample text, and apply all highlighting.
function! s:Hsample()
  call LoadHighlights()
  new
  setlocal buftype=nofile bufhidden=hide noswapfile
  let lines = []
  let items = []
  for hl in filter(range(1, 99), 'v:val % 10 > 0')
    if hlexists('hl'.hl)
      let sample = printf('Sample%2d', hl)
      call s:DoHighlight(hl, sample, 0)
    else
      let sample = '        '
    endif
    call add(items, sample)
    if len(items) >= 3
      call insert(lines, substitute(join(items), '\s\+$', '', ''))
      let items = []
    endif
  endfor
  call append(0, filter(lines, 'len(v:val) > 0'))
  $d
  %s/\d3$/&\r/e
endfunction
command! Hsample call s:Hsample()
 
" Set a match, or display all current matches. Example args:
"   '14' = set hl14 for visual selection or cword,
"   '14 pattern' = set hl14 for pattern, '' = display all
function! s:Highlight(args) range
  if empty(a:args)
    echo 'Highlight groups and patterns:'
    for m in getmatches()
      echo m.group m.pattern
    endfor
    return
  endif
  let l = matchlist(a:args, '^\s*\([1-9][0-9]\?\)\%($\|\s\+\(.*\)\)')
  if len(l) >= 3
    let hlnum = str2nr(l[1])
    let pattern = l[2]
    if empty(pattern)
      let pattern = s:Pattern(0)
    endif
    call s:DoHighlight(hlnum, pattern, 0)
    return
  endif
  echo 'Error: First argument must be highlight number 1..99'
endfunction
command! -nargs=* -range Highlight call s:Highlight('<args>')
