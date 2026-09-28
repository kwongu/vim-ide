" dirdifftab.vim - :DirDiff 를 새 탭에서, 원래 자리는 그대로 (will133/vim-dirdiff 감싸기)
"
" vim-dirdiff 의 :DirDiff 는 'diff -r --brief' 결과 목록을 지금 창에 열고, 목록에서
" 고른 파일 둘을 그 창 위로 쪼개 붙여 비교한다. vim-ide 배치(트리 / aerial /
" RelationView)에서 그러면 편집 창이 목록으로 바뀌고 곁창 사이로 창이 늘어난다.
" 그래서 새 탭을 하나 열고 거기서 한다. 목록에서 q(와 확인)로 끝내면 - 또는 그
" 탭을 :tabclose 로 닫아도 - 그 탭을 닫고, 비교하느라 연 버퍼를 치우고(고친 것은
" 남긴다), 시작한 탭으로 돌아간다.
"
"   :DirDiff <A> <B>                두 디렉터리 비교 (새 탭)
"   neo-tree 에서 \d                첫 번째를 고르고, 두 번째에서 \d (dirdiffpick.lua)
"   let g:vimide_dirdiff_tab = 0    " 새 탭 없이 지금 창에서 (아래 고침은 그대로)
"
" 목록 창: <CR>/o 열기, s 맞추기(sync), u 다시 비교, x 제외 목록, q 끝내기
" 비교 창: ]c [c 다음/앞 차이, do dp 가져오기/보내기, :DirDiffNext :DirDiffPrev
"
" 플러그인을 그대로 쓰면 생기는 일과 여기서 한 것 (반대 심문에서 나온 것 포함):
"   * 경로를 expand() 로 푸는데 expand() 는 'wildignore' 에 걸리는 경로를 빈 글자로
"     돌려준다 - .vimrc 의 '*/tmp/*' 때문에 Yocto 트리(build/tmp/work/...)가 통째로
"     '지금 디렉터리'로 바뀌어 엉뚱한 곳을 비교했다. 'wildignore' 를 비우고 부른다.
"   * 목록에서 다음 항목을 열 때 앞 파일을 ':bd' 한다. 비교 전부터 열려 있던 파일이면
"     원래 탭의 편집 창까지 닫혔다. 열기(<CR>/o, :DirDiffNext/Prev)는 여기서 한다 -
"     비교 창을 닫고 새로 쪼갤 뿐 버퍼는 지우지 않는다.
"   * 상태를 스크립트 전역에 하나만 둔다. 그래서 비교는 한 번에 하나 - 이미 열린 비교
"     탭이 있으면 그리로 간다. q 가 아닌 길로 끝났으면 다음 비교 전에 그 상태를 비운다.
"   * 한쪽에만 있는 디렉터리를 열면 nvim-tree 가 그 창을 가져간다 - 열지 않고 알린다.
"   * 경로의 $ % # ! " ` \ 는 플러그인이 한 번 더 풀거나(:! 명령) 깨뜨린다 - 거절한다.

if exists('g:loaded_vimide_dirdifftab')
  finish
endif
let g:loaded_vimide_dirdifftab = 1

let s:seq = 0
let s:sessions = {}   " id -> { before, opened, lists, quit, done, updating }

" vim-dirdiff 의 스크립트 번호 - 그 안의 s: 함수를 부른다
function! s:plugin_sid() abort
  for l:line in split(execute('scriptnames'), "\n")
    let l:m = matchlist(l:line, '^\s*\(\d\+\):\s*\(.\{-}\)\s*$')
    if !empty(l:m) && l:m[2] =~# '[/\\]plugin[/\\]dirdiff\.vim$'
      return l:m[1]
    endif
  endfor
  return ''
endfunction

function! s:fn(name) abort
  let l:sid = s:plugin_sid()
  if empty(l:sid)
    throw 'vim-dirdiff 가 없습니다 (:PlugInstall 로 설치)'
  endif
  return function('<SNR>' . l:sid . '_' . a:name)
endfunction

" 플러그인의 s: 함수를 'wildignore' 를 비운 채로 부른다
function! s:call(name, args) abort
  let l:F = s:fn(a:name)
  let l:wi = &wildignore
  set wildignore=
  try
    return call(l:F, a:args)
  finally
    let &wildignore = l:wi
  endtry
endfunction

function! s:warn(msg) abort
  echohl WarningMsg
  echomsg 'DirDiff: ' . a:msg
  echohl None
endfunction

" 플러그인의 전역 상태(마지막 모드, 비교 중인 파일)를 비운다. 그것을 비우는 곳은
" DirDiffQuit 하나뿐이고, 그 함수는 '정말 끝낼까' 를 묻고 대답과 상관없이 상태를
" 비운다 - 아니오(n)를 미리 넣어 두고 부른다. 버퍼는 지우지 않는다.
" nvim 의 confirm() 은 feedkeys() 로 넣은 글자를 읽지만 vim 8.1 은 읽지 않고
" 보이지 않는 프롬프트에서 기다렸다(실측: 첫 :DirDiff 가 그대로 멈췄다). vim 은
" test_feedinput() 이 낮은 층에 넣어 준 글자를 읽는다.
" 비울 것이 있을 때만 부른다: 플러그인이 항목을 연 뒤 q 로 끝나지 않은 경우.
let s:plugin_dirty = 0
function! s:reset_plugin() abort
  if !s:plugin_dirty
    return
  endif
  try
    let l:F = s:fn('DirDiffQuit')
  catch
    return
  endtry
  if has('nvim')
    call feedkeys('n', 'n')
  elseif exists('*test_feedinput')
    call test_feedinput('n')
  else
    return
  endif
  try
    silent! call l:F()
  finally
    " 쓰이지 않고 남은 n 이 있으면 치운다
    while getchar(1)
      call getchar(0)
    endwhile
  endtry
  let s:plugin_dirty = 0
endfunction

function! s:listed() abort
  let l:d = {}
  for l:b in range(1, bufnr('$'))
    if buflisted(l:b)
      let l:d[l:b] = 1
    endif
  endfor
  return l:d
endfunction

function! s:tab_of(id) abort
  for l:t in range(1, tabpagenr('$'))
    let l:v = gettabvar(l:t, 'vimide_dirdiff', {})
    if type(l:v) == type({}) && get(l:v, 'id', -1) == a:id
      return l:t
    endif
  endfor
  return 0
endfunction

function! s:origin_of(id) abort
  for l:t in range(1, tabpagenr('$'))
    if gettabvar(l:t, 'vimide_dirdiff_origin', -1) == a:id
      return l:t
    endif
  endfor
  return 0
endfunction

function! s:list_win() abort
  for l:w in range(1, winnr('$'))
    if getbufvar(winbufnr(l:w), '&filetype') ==# 'dirdiff'
      return l:w
    endif
  endfor
  return 0
endfunction

" 곁창(트리 등)에 선 채로 :tabnew 하면 새 탭의 창이 그 곁창의 창 옵션을 물려받는다.
" neo-tree 는 그런 창을 제 창으로 알고 도로 가져가, 비교 창 하나가 트리로 바뀌고
" 다른 하나를 덮었다 (실측). 먼저 EDIT 창으로 옮기고, 새 창의 창 옵션은 전역값으로.
function! s:leave_side() abort
  if has('nvim') && exists('*luaeval')
    let l:w = luaeval('(_G.vimide_is_edit_win and not _G.vimide_is_edit_win()'
          \ . ' and _G.vimide_edit_slot) and _G.vimide_edit_slot() or 0')
    if l:w > 0
      call win_gotoid(l:w)
    endif
  elseif &buftype !=# ''
    wincmd p
  endif
endfunction

function! s:plain_window() abort
  for l:o in ['winhighlight', 'winfixwidth', 'winfixheight', 'number', 'relativenumber',
        \ 'signcolumn', 'foldcolumn', 'cursorline', 'list', 'wrap', 'statuscolumn', 'winbar']
    if exists('+' . l:o)
      execute 'silent! setlocal ' . l:o . '<'
    endif
  endfor
endfunction

" 비교를 끝낸다: 탭을 닫고, 시작한 탭으로 가고, 그 비교에서 연 버퍼를 치운다
function! s:finish(id, ...) abort
  let l:s = get(s:sessions, a:id, {})
  if empty(l:s) || get(l:s, 'done', 0)
    return
  endif
  let l:s.done = 1
  let l:tab = s:tab_of(a:id)
  if l:tab > 0
    execute 'tabnext ' . l:tab
    silent! diffoff!
    unlet! t:vimide_dirdiff
    if tabpagenr('$') > 1
      tabclose
    else
      silent! only
      enew
    endif
  endif
  let l:org = s:origin_of(a:id)
  if l:org > 0
    execute 'tabnext ' . l:org
    unlet! t:vimide_dirdiff_origin
  endif
  " q 로 끝나지 않았으면 플러그인이 아직 이 비교를 들고 있다
  if !get(l:s, 'quit', 0)
    call s:reset_plugin()
  endif
  let l:kept = []
  for l:b in keys(l:s.lists) + keys(l:s.opened)
    let l:b = str2nr(l:b)
    if !bufexists(l:b) || has_key(l:s.before, l:b) || !empty(win_findbuf(l:b))
      continue
    endif
    if getbufvar(l:b, '&modified')
      call add(l:kept, fnamemodify(bufname(l:b), ':~:.'))
    else
      execute 'silent! bwipeout ' . l:b
    endif
  endfor
  if has_key(s:sessions, a:id)
    call remove(s:sessions, a:id)
  endif
  if !empty(l:kept)
    call s:warn('고친 채 남겨 둔 버퍼: ' . join(l:kept, ', '))
  endif
endfunction

function! s:session_here() abort
  if !exists('t:vimide_dirdiff') || type(t:vimide_dirdiff) != type({})
    return {}
  endif
  return get(s:sessions, t:vimide_dirdiff.id, {})
endfunction

" 비교 탭에서 새로 창에 들어온 버퍼를 적어 둔다 (끝낼 때 치운다)
function! s:note_buf(buf) abort
  let l:s = s:session_here()
  if empty(l:s) || has_key(l:s.before, a:buf) || a:buf <= 0
    return
  endif
  if getbufvar(a:buf, '&filetype') ==# 'dirdiff'
    let l:s.lists[a:buf] = 1
  else
    let l:s.opened[a:buf] = 1
  endif
endfunction

function! s:on_delete(buf) abort
  if getbufvar(a:buf, '&filetype') !=# 'dirdiff'
    return
  endif
  for [l:id, l:s] in items(s:sessions)
    if has_key(l:s.lists, a:buf) && !get(l:s, 'done', 0) && !get(l:s, 'updating', 0)
      " q -> 확인 -> bd! 로 목록이 지워지는 중이다 (플러그인은 상태를 비웠다).
      " 목록이 탭의 마지막 창이었으면 탭은 이미 닫혔다 - 그래도 치운다.
      let l:s.quit = 1
      let s:plugin_dirty = 0
      call timer_start(0, function('s:finish', [str2nr(l:id)]))
    endif
  endfor
endfunction

" 탭이 q 가 아닌 길로 닫혔으면(:tabclose, 창을 다 :q) 그 비교를 끝낸다
function! s:on_tabclosed() abort
  for l:id in keys(s:sessions)
    if s:tab_of(str2nr(l:id)) == 0 && !get(s:sessions[l:id], 'done', 0)
      call timer_start(0, function('s:finish', [str2nr(l:id)]))
    endif
  endfor
endfunction

" 목록 창 말고는 모두 비교 창이다 - 닫는다 (버퍼는 그대로). 고친 것은 물어본다.
function! s:close_diff_windows() abort
  let l:lw = win_getid(s:list_win())
  for l:w in reverse(range(1, winnr('$')))
    let l:id = win_getid(l:w)
    if l:id == l:lw
      continue
    endif
    let l:b = winbufnr(l:w)
    if getbufvar(l:b, '&modified')
      let l:ans = confirm('DirDiff: ' . fnamemodify(bufname(l:b), ':~:.') . ' 을(를) 고쳤습니다.',
            \ "&Save\nCa&ncel", 1)
      if l:ans != 1
        return 0
      endif
      call win_execute(l:id, 'write')
    endif
    call win_execute(l:id, 'silent! diffoff')
    call win_execute(l:id, 'close')
  endfor
  return 1
endfunction

" 목록의 한 줄을 연다 - 비교 창을 닫고 목록 위로 새로 쪼갠다. 버퍼는 지우지 않는다.
function! s:open_line(lnum) abort
  let l:lw = s:list_win()
  if l:lw == 0
    return
  endif
  execute l:lw . 'wincmd w'
  let l:line = getline(a:lnum)
  let l:only = s:call('IsOnly', [l:line])
  let l:differ = s:call('IsDiffer', [l:line])
  if !l:only && !l:differ
    return s:warn('이 줄에는 비교할 것이 없습니다')
  endif
  let l:fa = s:call('GetFileNameFromLine', ['A', l:line])
  let l:fb = s:call('GetFileNameFromLine', ['B', l:line])
  let l:file = ''
  if l:only
    let l:file = s:call('ParseOnlySrc', [l:line]) ==# 'A' ? l:fa : l:fb
    if isdirectory(l:file)
      return s:warn('한쪽에만 있는 디렉터리입니다: ' . fnamemodify(l:file, ':~:.'))
    endif
  endif
  if !s:close_diff_windows()
    return
  endif
  execute s:list_win() . 'wincmd w'
  if exists('b:currentDiff')
    call s:call('DeHighlightLine', [])
  endif
  let b:currentDiff = a:lnum
  call s:call('HighlightLine', [])
  let l:wi = &wildignore
  set wildignore=
  try
    if l:only
      execute 'silent aboveleft split ' . fnameescape(l:file)
      diffthis
    else
      execute 'silent aboveleft split ' . fnameescape(l:fb)
      " A 가 왼쪽, B 가 오른쪽
      execute 'silent leftabove vertical diffsplit ' . fnameescape(l:fa)
    endif
  finally
    let &wildignore = l:wi
  endtry
  execute s:list_win() . 'wincmd w'
  execute 'resize ' . get(g:, 'DirDiffWindowSize', 14)
  execute a:lnum
  normal! z.
endfunction

function! s:entry_lines() abort
  let l:out = []
  for l:n in range(1, line('$'))
    let l:t = getline(l:n)
    if s:call('IsOnly', [l:t]) || s:call('IsDiffer', [l:t])
      call add(l:out, l:n)
    endif
  endfor
  return l:out
endfunction

function! VimIdeDirDiffOpen() abort
  if s:list_win() == 0
    return s:warn('비교 목록이 없습니다')
  endif
  execute s:list_win() . 'wincmd w'
  call s:open_line(line('.'))
endfunction

function! VimIdeDirDiffStep(dir) abort
  if s:list_win() == 0
    return s:warn('비교 목록이 없습니다')
  endif
  execute s:list_win() . 'wincmd w'
  let l:lines = s:entry_lines()
  if empty(l:lines)
    return
  endif
  let l:cur = get(b:, 'currentDiff', 0)
  let l:next = 0
  for l:n in (a:dir > 0 ? l:lines : reverse(copy(l:lines)))
    if (a:dir > 0 && l:n > l:cur) || (a:dir < 0 && l:n < l:cur)
      let l:next = l:n
      break
    endif
  endfor
  if l:next == 0
    return s:warn(a:dir > 0 ? '마지막 항목입니다' : '첫 항목입니다')
  endif
  call s:open_line(l:next)
endfunction

" 목록 버퍼에 열기·다시 비교를 여기 것으로 건다 (플러그인이 목록을 만들 때마다).
" 끝나면 원래 창으로 - 'wincmd p' 로 돌아가면 목록이 아니라 A 파일 창에 섰다
" (반대 심문: 그 뒤 x s o u 가 파일을 고쳤다).
function! s:remap_list() abort
  let l:keep = win_getid()
  let l:lw = s:list_win()
  if l:lw > 0
    call win_gotoid(win_getid(l:lw))
    nnoremap <buffer> <silent> <CR> :<C-u>call VimIdeDirDiffOpen()<CR>
    nnoremap <buffer> <silent> o :<C-u>call VimIdeDirDiffOpen()<CR>
    nnoremap <buffer> <silent> <2-LeftMouse> :<C-u>call VimIdeDirDiffOpen()<CR>
    nnoremap <buffer> <silent> u :<C-u>call VimIdeDirDiffUpdate()<CR>
  endif
  call win_gotoid(l:keep)
endfunction

function! VimIdeDirDiffUpdate() abort
  if s:list_win() == 0
    return s:warn('비교 목록이 없습니다')
  endif
  let l:s = s:session_here()
  if !empty(l:s)
    let l:s.updating = 1
  endif
  try
    if !s:close_diff_windows()
      return
    endif
    " 플러그인이 다시 만들며 '앞 파일' 을 :bd 하지 않게 상태를 먼저 비운다
    let s:plugin_dirty = 1
    call s:reset_plugin()
    execute s:list_win() . 'wincmd w'
    call s:call('DirDiffUpdate', [])
    let s:plugin_dirty = 1
  catch
    return s:warn(v:exception)
  finally
    if !empty(l:s)
      let l:s.updating = 0
    endif
  endtry
  call s:remap_list()
  if s:list_win() > 0
    execute s:list_win() . 'wincmd w'
  endif
endfunction

" 플러그인의 경로 처리(한 번 더 expand, :! 명령)를 깨는 글자
let s:bad_chars = '[$%#!"`\\]'

function! VimIdeDirDiff(...) abort
  if a:0 != 2
    return s:warn('디렉터리 두 개를 주세요 - :DirDiff <A> <B>')
  endif
  " expand(,1): 'wildignore' 를 쓰지 않는다
  let l:a = fnamemodify(expand(a:1, 1), ':p')
  let l:b = fnamemodify(expand(a:2, 1), ':p')
  for [l:d, l:arg] in [[l:a, a:1], [l:b, a:2]]
    if !isdirectory(l:d)
      return s:warn('디렉터리가 아닙니다: ' . l:arg)
    endif
    if l:d =~# s:bad_chars
      return s:warn('경로에 DirDiff 가 다루지 못하는 글자($ % # ! " ` \)가 있습니다: ' . l:d)
    endif
  endfor
  if resolve(substitute(l:a, '/\+$', '', '')) ==# resolve(substitute(l:b, '/\+$', '', ''))
    return s:warn('같은 디렉터리입니다: ' . fnamemodify(l:a, ':~'))
  endif
  if empty(s:plugin_sid())
    return s:warn('vim-dirdiff 가 없습니다 (:PlugInstall 로 설치)')
  endif
  " 비교는 한 번에 하나 (플러그인 상태가 전역 하나다). 탭이 사라진 것은 여기서 치운다.
  for l:id in keys(s:sessions)
    let l:t = s:tab_of(str2nr(l:id))
    if l:t > 0
      execute 'tabnext ' . l:t
      return s:warn('이미 비교 중입니다 - 목록에서 q 로 끝낸 뒤 다시 하세요')
    endif
    call s:finish(str2nr(l:id))
  endfor
  let s:seq += 1
  let l:id = s:seq
  let s:sessions[l:id] = { 'before': s:listed(), 'opened': {}, 'lists': {} }
  " 지난 비교가 q 가 아닌 길로 끝났으면 플러그인이 그 상태를 아직 들고 있다
  call s:reset_plugin()
  let l:tab = get(g:, 'vimide_dirdiff_tab', 1)
  if l:tab
    call s:leave_side()
    let t:vimide_dirdiff_origin = l:id
    tabnew
    call s:plain_window()
  endif
  let t:vimide_dirdiff = { 'id': l:id }
  try
    call s:call('DirDiff', [l:a, l:b])
  catch
    call s:warn(v:exception)
  endtry
  if s:list_win() == 0
    " 차이가 없으면 목록 없이 돌아온다 - 빈 탭을 닫고 알린다
    let s:sessions[l:id].quit = 1
    if l:tab
      call s:finish(l:id)
    else
      unlet! t:vimide_dirdiff
      call remove(s:sessions, l:id)
    endif
    redraw
    echomsg 'DirDiff: 차이가 없습니다 - ' . fnamemodify(l:a, ':~') . '  =  ' . fnamemodify(l:b, ':~')
    return
  endif
  " 플러그인이 첫 항목을 열었다 - 이제 그 상태를 들고 있다
  let s:plugin_dirty = 1
  call s:remap_list()
  execute s:list_win() . 'wincmd w'
endfunction

function! s:install() abort
  if exists(':DirDiff') == 2
    command! -nargs=* -complete=dir DirDiff call VimIdeDirDiff(<f-args>)
    command! -nargs=0 DirDiffUpdate call VimIdeDirDiffUpdate()
    command! -nargs=0 DirDiffOpen call VimIdeDirDiffOpen()
    command! -nargs=0 DirDiffNext call VimIdeDirDiffStep(1)
    command! -nargs=0 DirDiffPrev call VimIdeDirDiffStep(-1)
  endif
endfunction

augroup VimIdeDirDiffTab
  autocmd!
  " 플러그인이 명령을 정의한 바로 뒤에 덮는다 - 'nvim -c "DirDiff a b"' 는 VimEnter
  " 보다 먼저 돈다 (VimEnter 는 SourcePost 가 없는 vim 을 위한 뒤받침)
  if exists('##SourcePost')
    autocmd SourcePost */plugin/dirdiff.vim call s:install()
  endif
  autocmd VimEnter * call s:install()
  autocmd BufDelete * call s:on_delete(str2nr(expand('<abuf>')))
  autocmd BufWinEnter * call s:note_buf(str2nr(expand('<abuf>')))
  autocmd FileType dirdiff call s:note_buf(str2nr(expand('<abuf>')))
  if exists('##TabClosed')
    autocmd TabClosed * call s:on_tabclosed()
  endif
augroup END
if v:vim_did_enter
  call s:install()
endif
