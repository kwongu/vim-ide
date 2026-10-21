" quickfix 에서 <CR> 은 '직전에 포커스가 있던 EDIT 창'에 연다.
"
" quickr-preview 가 <CR> 을 HandleEnterQuickfix 로 잡고 있는데 그 안은
" 결국 'normal! <CR>' 이라 switchbuf 규칙을 그대로 탄다. 이 파일은
" ~/.vim/after 에 있어 그 플러그인의 after/ftplugin(rtp 60)보다 나중에
" (rtp 61) 읽히므로 여기서 덮는다.
"
"   let g:vimide_qf_last_edit = 0   " 끄면 예전 동작 그대로
if get(g:, 'vimide_qf_last_edit', 1) && has('nvim')
    nnoremap <silent> <buffer> <CR> :call vimide#qf#Jump()<CR>
    nnoremap <silent> <buffer> <2-LeftMouse> :call vimide#qf#Jump()<CR>
endif

" quickfix / 위치 목록 버퍼는 버퍼 목록에서 뺀다 (QA-05).
"
" nvim 0.12 는 quickfix 버퍼를 목록에 넣는다. 그래서 :bn / :bp / ,r / ,e 가 그것을
" 밟아 편집 창에 목록이 실렸고(편집 창 0개, quickfix 창 둘), 그 자리에서는 ,e 가
" 'buftype 이 있는 창' 이라며 돌아오지도 못했다. 목록은 ,o / :copen 으로 연다.
setlocal nobuflisted

" q : 이 목록을 닫는다 - quickr 미리보기(\p)도 같이 (QA-30, .vimrc 의 VimIdeQfClose).
"
" 예전에는 q 에 매핑이 없어 매크로 녹화가 시작됐다. 다음 키가 녹화 이름으로 먹히고,
" 목록은 고칠 수 없는 버퍼라 그 뒤의 키들이 E21 만 냈다. 매크로는 다른 창에서 쓴다.
if exists('*VimIdeQfClose')
    nnoremap <silent> <buffer> <nowait> q
                \ :<C-u>call VimIdeQfClose(get(getwininfo(win_getid())[0], 'loclist', 0) ? 'l' : 'c')<CR>
endif
