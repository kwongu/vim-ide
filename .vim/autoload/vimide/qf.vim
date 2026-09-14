" quickfix / location list 에서 '직전에 포커스가 있던 EDIT 창'으로 뛴다.
"
" vim 은 'switchbuf' 의 uselast 규칙으로 winnr('#') 에 연다. 그런데 그
" '직전 창'이 aerial 이나 트리 같은 옆 창이면 거기에 파일을 열어 버린다.
" 실측: EDIT 3번째 창 -> aerial 창으로 이동 -> :copen -> <CR> 하니
" aerial 창이 파일로 갈려(ft=vim) 아웃라인이 사라졌다.
"
" 편집 창은 relationview.lua 가 골라 기억해 둔 것을 쓴다
" (_G.vimide_last_edit_win). 없으면 아무것도 하지 않고 vim 기본에 맡긴다.
function! vimide#qf#Win() abort
    if !has('nvim') || !exists('*luaeval')
        return 0
    endif
    let l:w = luaeval('(_G.vimide_last_edit_win and _G.vimide_last_edit_win()) or 0')
    if type(l:w) != type(0) || l:w <= 0
        return 0
    endif
    return win_id2win(l:w) > 0 ? l:w : 0
endfunction

" 이 창에 파일을 열어도 되는가.
" 'hidden' 이 꺼진 vim 에서 고친 버퍼를 밀어내면 E37 이 난다. 판정은
" NERDTree 의 _isWindowUsable() 과 같게 맞춘다 (opener.vim:102-125).
function! vimide#qf#Usable(win) abort
    if a:win <= 0
        return 0
    endif
    let l:nr = win_id2win(a:win)
    if l:nr <= 0 || getwinvar(l:nr, '&previewwindow')
        return 0
    endif
    let l:buf = winbufnr(l:nr)
    if l:buf <= 0 || getbufvar(l:buf, '&buftype') !=# ''
        return 0
    endif
    return &hidden || !getbufvar(l:buf, '&modified')
endfunction

" 옆 창(패널/트리/아웃라인)에 서서 :cnext 를 누르면 vim 은 '지금 창'에
" 파일을 연다 - 'switchbuf' 는 qf 창 '안'에서 뛸 때만 본다. 실측: 패널이
" buftype=nofile 에서 보통 버퍼로 갈려 아웃라인이 사라졌다.
" 그래서 세기 전에 EDIT 창으로 옮겨 놓는다.
function! vimide#qf#Step(dir, ...) abort
    let l:loc = a:0 > 0 ? a:1 : 0
    if &buftype !=# '' && get(g:, 'vimide_qf_last_edit', 1)
        let l:win = vimide#qf#Win()
        if vimide#qf#Usable(l:win)
            call win_gotoid(l:win)
        endif
    endif
    try
        if a:dir > 0
            execute l:loc ? 'lnext' : 'cnext'
        else
            execute l:loc ? 'lprevious' : 'cprevious'
        endif
    catch /^Vim\%((\a\+)\)\=:E/
        echo substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', '')
    endtry
endfunction

function! vimide#qf#Jump() abort
    let l:src = win_getid()
    let l:info = getwininfo(l:src)
    let l:isloc = !empty(l:info) && get(l:info[0], 'loclist', 0)
    let l:idx = line('.')
    let l:list = l:isloc ? getloclist(l:src) : getqflist()
    if l:idx < 1 || l:idx > len(l:list) || !get(l:list[l:idx - 1], 'valid', 0)
        " 항목이 아닌 줄이면 키를 삼키지 말고 vim 기본 <CR> 에 맡긴다
        execute "normal! \<CR>"
        return
    endif
    " 미리보기 창은 원래 동작대로 먼저 닫는다 (quickr-preview 와 같다)
    silent! pclose
    let l:win = vimide#qf#Win()
    if !vimide#qf#Usable(l:win)
        let l:win = 0
    endif
    let l:sb = &switchbuf
    try
        if l:win > 0
            call win_gotoid(l:win)
            if l:isloc && l:win != l:src
                " loclist 는 창마다 다르다. 옮겨 간 창이 이 리스트의 주인이
                " 아니면 :ll 이 E776 을 낸다. 같은 리스트를 그 창에 깔고
                " 나서 뛴다 - 그래야 :lnext 도 이어진다.
                call setloclist(l:win, [], ' ',
                            \ {'title': get(getloclist(l:src, {'title': 0}), 'title', ''),
                            \  'items': l:list})
            endif
            " 이미 원하는 창에 서 있으므로 switchbuf 가 다시 창을 고르지
            " 않게 비운다. 비어 있으면 :cc 는 '지금 창'에 연다.
            set switchbuf=
        endif
        execute (l:isloc ? 'll ' : 'cc ') . l:idx
    catch /^Vim\%((\a\+)\)\=:E/
        echohl WarningMsg
        echomsg substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', '')
        echohl None
    finally
        let &switchbuf = l:sb
    endtry
    silent! foldopen!
    if get(g:, 'quickr_preview_exit_on_enter', 0)
        cclose
    endif
endfunction
