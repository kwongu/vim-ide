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

function! vimide#qf#Jump() abort
    let l:info = getwininfo(win_getid())
    let l:isloc = !empty(l:info) && get(l:info[0], 'loclist', 0)
    let l:idx = line('.')
    let l:list = l:isloc ? getloclist(0) : getqflist()
    if l:idx < 1 || l:idx > len(l:list) || !get(l:list[l:idx - 1], 'valid', 0)
        return
    endif
    " 미리보기 창은 원래 동작대로 먼저 닫는다 (quickr-preview 와 같다)
    silent! pclose
    let l:win = vimide#qf#Win()
    let l:sb = &switchbuf
    try
        if l:win > 0
            call win_gotoid(l:win)
            " 이미 원하는 창에 서 있으므로 switchbuf 가 다시 창을 고르지
            " 않게 비운다. 비어 있으면 :cc 는 '지금 창'에 연다.
            set switchbuf=
        endif
        execute (l:isloc ? 'll ' : 'cc ') . l:idx
    finally
        let &switchbuf = l:sb
    endtry
    silent! foldopen!
    if get(g:, 'quickr_preview_exit_on_enter', 0)
        cclose
    endif
endfunction
