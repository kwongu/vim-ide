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
