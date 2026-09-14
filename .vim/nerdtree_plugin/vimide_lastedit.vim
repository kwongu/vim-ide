" NERDTree 에서 파일을 여는 키만 '직전에 포커스가 있던 EDIT 창'으로 돌린다.
"
" 왜 여기(nerdtree_plugin/)인가: plugin/NERD_tree.vim:235 의
" nerdtree#postSourceActions() 가 createDefaultBindings() 를 먼저 부르고
" 그 다음에 'runtime! nerdtree_plugin/**/*.vim' 을 읽는다
" (autoload/nerdtree.vim:193-198, 서버의 예전 bundle 도 같은 순서다).
" 그래서 이 자리에서는 기본 키가 이미 있고 override 가 그대로 먹는다
" - VimEnter 로 미룰 필요도, :source ~/.vimrc 를 따로 챙길 필요도 없다.
"
" 쪼개기/탭(i s t T gi gs)과 디렉터리(DirNode)는 건드리지 않는다. 사용자가
" 일부러 고른 것이다. projectfiles_tree 의 + - = 와 nerdtree-git 의 ]c [c 는
" scope 'Node' 라, FileNode 를 먼저 보는 KeyMap.Invoke() 순서상 가려지지
" 않는다 (key_map.vim:102-121).
"
" 키 이름은 반드시 get() 으로 읽는다: 서버의 예전 bundle
" (.vim/bundle/The-NERD-tree) 에는 g:NERDTreeMapCustomOpen 이 아예 없어서
" 그냥 쓰면 E121 이 난다 (실측, vim 9.1). 그쪽은 <CR> 도
" invokeKeyMap(g:NERDTreeMapActivateNode) 로 들어오므로 'o' 하나만 덮으면
" <CR> 까지 함께 고쳐진다.
"
"   let g:vimide_nerdtree_last_edit = 0   " 끄면 예전(stock) 동작
if exists('g:loaded_vimide_nerdtree_lastedit')
    finish
endif
let g:loaded_vimide_nerdtree_lastedit = 1
if !get(g:, 'vimide_nerdtree_last_edit', 1)
            \ || !exists('*NERDTreeAddKeyMap') || !exists('*VimIdeNERDTreeOpen')
    finish
endif

let s:keys = ['<2-LeftMouse>']
for s:n in ['NERDTreeMapCustomOpen', 'NERDTreeMapActivateNode']
    let s:v = get(g:, s:n, '')
    if !empty(s:v) && index(s:keys, s:v) < 0
        call add(s:keys, s:v)
    endif
endfor
for s:k in s:keys
    call NERDTreeAddKeyMap({
                \ 'key': s:k,
                \ 'scope': 'FileNode',
                \ 'callback': 'VimIdeNERDTreeOpen',
                \ 'override': 1,
                \ 'quickhelpText': 'open in the last focused EDIT window' })
endfor
" 미리보기(go): 파일은 EDIT 창에 뜨고 포커스는 트리에 남는다
let s:p = get(g:, 'NERDTreeMapPreview', '')
if !empty(s:p)
    call NERDTreeAddKeyMap({
                \ 'key': s:p,
                \ 'scope': 'FileNode',
                \ 'callback': 'VimIdeNERDTreePreview',
                \ 'override': 1,
                \ 'quickhelpText': 'preview in the last focused EDIT window' })
endif
unlet! s:keys s:n s:v s:k s:p
