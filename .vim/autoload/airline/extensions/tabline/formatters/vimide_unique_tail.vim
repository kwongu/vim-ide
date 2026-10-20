" vim-ide: airline 버퍼 줄(tabline)의 이름 - unique_tail 과 같은 이름을 담아 두고 꺼낸다
"
" airline 의 tabline 은 보이는 버퍼마다 %{airline#extensions#tabline#get_buffer_name(N)}
" 를 넣는다. unique_tail 은 그 한 번 한 번마다 열린 버퍼 전체를 다시 훑어(bufname,
" fnamemodify, 겹치는 이름은 ':p:.' 와 정규식) 이름표를 새로 만든다. 그래서 tabline
" 한 번 그리기가 (보이는 수) x (열린 수) 이고, 버퍼가 쌓일수록 커진다 - 버퍼 55개에서
" 한 번에 65-100ms (개발서버 실측, 닷새 띄운 nvim). 버퍼를 옮기면 airline 이 줄을
" 다시 짜며(이름 폭을 재느라) 한 번, 그리느라 두 번 더 - :bn 한 번이 0.2초를 넘었다.
"
" 여기서는 이름표를 한 번 만들어 담아 두고 꺼내기만 한다. 이름표는 (airline 목록의
" 버퍼들, 그 버퍼들의 이름, 현재 디렉터리, fnamemod/fnamecollapse) 로 정해진다.
" 다시 만드는 때:
"   - airline 목록의 '내용'이 달라졌다. airline 은 버퍼를 옮길 때마다(BufLeave) 같은
"     내용으로 새 리스트를 짠다 - is 로만 보면 옮길 때마다 다시 만들었다 (버퍼 150개
"     에서 7ms). 새 리스트가 오면 내용(==#, C 에서 비교), getcwd(), 버퍼 이름들
"     (bufname - 150개에서 0.07ms)을 한 번 보고, 같으면 그 리스트를 받아 두기만 한다
"   - 이름표에 있는 버퍼의 이름이 바뀌었거나 지워졌다 (BufFilePost/BufDelete/
"     BufWipeout. 목록 밖 버퍼 - 플로트·피커·트리 - 가 생기고 지워지는 것은 상관없다)
"   - 현재 디렉터리가 바뀌었다 (DirChanged - 겹치는 이름은 ':p:.' 라 cwd 기준이다.
"     nvim 은 :lcd/:tcd 가 다른 창·탭으로 옮길 때도 DirChanged 를 낸다)
"   - 지금 창에 :lcd 가 있으면 그 디렉터리가 이름표의 것과 다르다 (vim 은 창을
"     옮길 때 DirChanged 를 내지 않는다). getcwd() 는 맥에서 한 번 15us 라 지역
"     디렉터리가 있는 창에서만 부른다
"   - airline 의 fnamemod / fnamecollapse 가 달라졌다
" 고친 표시(+)와 번호 표시는 부를 때마다 airline 의 wrap_name 이 붙인다.
" airline 의 목록이 아닌 리스트(tabs 모드의 탭 제목 - 그 탭의 창들)는 작으므로
" unique_tail 을 그대로 부른다. 이름은 unique_tail 과 글자 하나까지 같다.
" 하나 늦는 때: 자동명령 없이 바꾼 디렉터리·이름(noautocmd cd, noautocmd file,
" eventignore=all 안의 :cd)은 다음에 버퍼를 옮길 때(airline 이 목록을 새로 짤 때)
" 따라잡는다. 그 전까지는 옛 이름(겹치는 이름은 옛 디렉터리 기준의 앞부분)이다.
"
" 되돌리기 (.vimrc): let g:vimide_tabline_cache = 0
" (vim 8.1 에서도 읽는다 - vim9script, ->, #{} 를 쓰지 않는다)

scriptencoding utf-8

let s:list = []     " 이름표를 만든(받아 둔) airline 목록 - 같은 리스트면 is 로 바로 맞다
let s:copy = []     " 그 목록의 내용 (airline 이 같은 내용으로 새로 짠 리스트를 알아본다)
let s:cwd = ''      " 이름표를 만든 때의 getcwd()
let s:bnames = []   " 그때 목록 버퍼들의 bufname() (자동명령 없이 바꾼 이름을 알아본다)
let s:gen = 0       " 이름표에 있는 버퍼의 이름이 바뀌거나 디렉터리가 바뀔 때마다 올린다
let s:built = -1    " 이름표를 만든 때의 s:gen
let s:lcd = ''      " 이름표를 만든 창의 지역 디렉터리 ('' = 없었다)
let s:fmod = ''
let s:collapse = -1
let s:names = {}    " bufnr -> 이름 (wrap_name 전)
" DirChanged 가 없는 vim 이면 늘 getcwd() 로 본다
let s:has_dc = exists('##DirChanged')

" a:nr < 0 이면 무조건 (디렉터리), 아니면 이름표에 있는 버퍼일 때만
function! s:Dirty(nr) abort
  if a:nr < 0 || has_key(s:names, a:nr)
    let s:gen += 1
  endif
endfunction

augroup VimIdeUniqueTail
  autocmd!
  autocmd BufDelete,BufWipeout,BufFilePost * call <SID>Dirty(str2nr(expand('<abuf>')))
  if s:has_dc
    autocmd DirChanged * call <SID>Dirty(-1)
  endif
augroup END

function! s:Lcd() abort
  return (!s:has_dc || haslocaldir()) ? getcwd() : ''
endfunction

" airline 의 unique_tail#format 과 같은 계산 (wrap_name 만 빼고)
function! s:Build(buffers) abort
  let l:names = {}
  let l:tails = {}
  let l:dups = []
  for l:nr in a:buffers
    let l:name = bufname(l:nr)
    if empty(l:name)
      let l:names[l:nr] = '[No Name]'
      continue
    endif
    if l:name =~ 'term://'
      " Neovim Terminal
      let l:tail = substitute(l:name, '\(term:\)//.*:\(.*\)', '\1 \2', '')
    else
      let l:tail = fnamemodify(l:name, ':s?/\+$??:t')
    endif
    if has_key(l:tails, l:tail)
      call add(l:dups, l:nr)
    endif
    let l:tails[l:tail] = 1
    let l:names[l:nr] = l:tail
  endfor
  let l:fmod = get(g:, 'airline#extensions#tabline#fnamemod', ':p:.')
  let l:collapse = get(g:, 'airline#extensions#tabline#fnamecollapse', 1)
  for l:nr in l:dups
    let l:name = fnamemodify(bufname(l:nr), l:fmod)
    if l:collapse
      let l:name = substitute(l:name, '\v\w\zs.{-}\ze(\\|/)', '', 'g')
    endif
    let l:names[l:nr] = l:name
  endfor
  let s:names = l:names
  let s:list = a:buffers
  let s:copy = copy(a:buffers)
  let s:built = s:gen
  let s:cwd = getcwd()
  let s:bnames = map(copy(a:buffers), 'bufname(v:val)')
  let s:lcd = (!s:has_dc || haslocaldir()) ? s:cwd : ''
  let s:fmod = l:fmod
  let s:collapse = l:collapse
endfunction

function! airline#extensions#tabline#formatters#vimide_unique_tail#format(bufnr, buffers) abort
  if a:buffers isnot s:list
    if a:buffers isnot airline#extensions#tabline#buflist#list()
      " 탭 제목처럼 작은 목록 - 담지 않고 airline 것을 그대로
      return airline#extensions#tabline#formatters#unique_tail#format(a:bufnr, a:buffers)
    endif
    " airline 이 목록을 새로 짰다 (버퍼를 옮길 때마다). 내용·디렉터리·이름이 같으면
    " 이름표도 같다 - 받아 두기만 한다. getcwd()·bufname 은 여기서(옮길 때 한 번)만 본다
    if a:buffers ==# s:copy && getcwd() ==# s:cwd
          \ && map(copy(a:buffers), 'bufname(v:val)') ==# s:bnames
      let s:list = a:buffers
    else
      call s:Build(a:buffers)
    endif
  endif
  if s:built != s:gen || s:Lcd() !=# s:lcd
        \ || get(g:, 'airline#extensions#tabline#fnamemod', ':p:.') !=# s:fmod
        \ || get(g:, 'airline#extensions#tabline#fnamecollapse', 1) != s:collapse
    call s:Build(a:buffers)
  endif
  if has_key(s:names, a:bufnr)
    return airline#extensions#tabline#formatters#default#wrap_name(a:bufnr, s:names[a:bufnr])
  endif
  " 목록이 아직 지금 버퍼를 모른다 - unique_tail 처럼 default 로
  return airline#extensions#tabline#formatters#default#format(a:bufnr, a:buffers)
endfunction
