" projectfiles_tree.vim - NERDTree 에서 색인 목록을 편집한다.
"
" projectfiles.lua 가 '어떤 파일을 색인할지'를 결정하고, 그 목록은 preset 에
" 담긴다. 지금까지 목록을 고치는 방법은 ':ProjectFilesAdd' 커맨드와 telescope
" 피커의 ^a / ^d 뿐이었다. 파일 트리를 보면서 담고 빼는 게 더 자연스럽다.
"
" 트리에서
"   +   커서의 파일/디렉터리를 색인에 넣는다 (넣고 바로 재색인)
"   -   색인에서 뺀다
"   =   이 경로가 색인에 들어 있는지 알려 준다
"   m   메뉴 -> '(i)ndex …' 안에 같은 항목 + 모드 고르기 / 재색인
"
" v / V / <C-v> 로 여러 줄을 고른 뒤 + 또는 - 를 누르면 그 범위를 한 번에
" 처리한다. 항목마다 목록을 다시 펼치고 재색인하지 않고 끝에 한 번만 하므로,
" 수십 줄을 골라도 한 번의 재색인으로 끝난다.
"
" 노드 옆의 표시 (preset 모드에서만; auto 모드는 전부 대상이라 표시하지 않는다)
"   [●]  이 파일이 색인에 있다
"   [·]  이 디렉터리 아래에 색인된 파일이 있다
"
" 옵션
"   g:projectfiles_tree        0 이면 이 파일이 아무 것도 하지 않는다
"   g:projectfiles_tree_marks  0 이면 노드 옆 표시를 달지 않는다
"   g:projectfiles_tree_add_key / _remove_key / _info_key
"                              기본 '+' / '-' / '='
"
" projectfiles.lua 는 nvim 전용이므로 여기도 nvim 에서만 동작한다.

if exists('g:loaded_projectfiles_tree') || !has('nvim')
    finish
endif
let g:loaded_projectfiles_tree = 1

if get(g:, 'projectfiles_tree', 1) == 0
    finish
endif


" ---------------------------------------------------------------------------
" 노드 -> 경로
" ---------------------------------------------------------------------------
function! s:NodePath(...) abort
    if a:0 > 0 && type(a:1) == v:t_dict && has_key(a:1, 'path')
        return a:1.path.str()
    endif
    let l:node = g:NERDTreeFileNode.GetSelected()
    return empty(l:node) ? '' : l:node.path.str()
endfunction

" 목록이 바뀌었으니 표시를 다시 계산하고 트리를 다시 그린다.
"
" NERDTreeRender() 는 버퍼를 통째로 다시 쓴다. 그러면 커서와 시각 선택
" 마크('<, '>)가 날아가서, 범위로 작업한 직후에 gv 로 다시 고르거나
" :'<,'>ProjectFilesIndexRemove 를 이어서 쓰는 것이 조용히 아무 것도 하지
" 않게 된다. 그리는 것은 목록이 바뀌었을 때뿐이니, 둘 다 되돌려 준다.
function! s:Rerender() abort
    if !exists('b:NERDTree')
        return
    endif
    let l:pos = getcurpos()
    let l:vs = [line("'<"), col("'<")]
    let l:ve = [line("'>"), col("'>")]
    call luaeval('_G.projectfiles_tree_invalidate()')
    call b:NERDTree.root.refreshFlags()
    call NERDTreeRender()
    call setpos('.', l:pos)
    if l:vs[0] > 0 && l:ve[0] > 0
        call setpos("'<", [0, l:vs[0], l:vs[1], 0])
        call setpos("'>", [0, l:ve[0], l:ve[1], 0])
    endif
endfunction

function! ProjectFilesTreeAdd(...) abort
    let l:p = call('s:NodePath', a:000)
    if empty(l:p)
        return
    endif
    call luaeval('_G.projectfiles_add(_A)', l:p)
    call s:Rerender()
endfunction

function! ProjectFilesTreeRemove(...) abort
    let l:p = call('s:NodePath', a:000)
    if empty(l:p)
        return
    endif
    call luaeval('_G.projectfiles_remove(_A)', l:p)
    call s:Rerender()
endfunction

" ---------------------------------------------------------------------------
" 범위 (visual / :'<,'>)
" ---------------------------------------------------------------------------
" NERDTree 는 줄마다 노드가 하나다. b:NERDTree.ui.getPath(줄번호) 가 그 줄의
" 경로를 주고, 헤더나 빈 줄에서는 빈 값을 준다 - 커서를 옮겨 다니지 않아도
" 범위를 그대로 경로 목록으로 바꿀 수 있다.
function! s:RangePaths(first, last) abort
    let l:paths = []
    if !exists('b:NERDTree')
        return l:paths
    endif
    for l:ln in range(a:first, a:last)
        let l:p = {}
        try
            let l:p = b:NERDTree.ui.getPath(l:ln)
        catch
            continue
        endtry
        if !empty(l:p)
            call add(l:paths, l:p.str())
        endif
    endfor
    return l:paths
endfunction

function! ProjectFilesTreeAddRange(first, last) abort
    let l:paths = s:RangePaths(a:first, a:last)
    if empty(l:paths)
        echo 'projectfiles: 고른 범위에 트리 노드가 없습니다'
        return
    endif
    call luaeval('_G.projectfiles_add(_A)', l:paths)
    call s:Rerender()
endfunction

function! ProjectFilesTreeRemoveRange(first, last) abort
    let l:paths = s:RangePaths(a:first, a:last)
    if empty(l:paths)
        echo 'projectfiles: 고른 범위에 트리 노드가 없습니다'
        return
    endif
    call luaeval('_G.projectfiles_remove(_A)', l:paths)
    call s:Rerender()
endfunction

function! ProjectFilesTreeInfo(...) abort
    let l:p = call('s:NodePath', a:000)
    if empty(l:p)
        return
    endif
    echo luaeval('_G.projectfiles_status(_A)', l:p)
endfunction

function! ProjectFilesTreeMode(...) abort
    ProjectFilesMode
endfunction

function! ProjectFilesTreeReindex(...) abort
    ProjectFilesReindex
    call s:Rerender()
endfunction

function! s:MapVisual() abort
    let l:add = get(g:, 'projectfiles_tree_add_key', '+')
    let l:rem = get(g:, 'projectfiles_tree_remove_key', '-')
    execute printf('xnoremap <buffer> <silent> %s '
                \ . ':<C-u>call ProjectFilesTreeAddRange(line("''<"), line("''>"))<CR>',
                \ l:add)
    execute printf('xnoremap <buffer> <silent> %s '
                \ . ':<C-u>call ProjectFilesTreeRemoveRange(line("''<"), line("''>"))<CR>',
                \ l:rem)
endfunction

augroup ProjectFilesTreeVisual
    autocmd!
    autocmd FileType nerdtree call s:MapVisual()
augroup END

" 표시가 어느 프로젝트 기준인지는 현재 디렉터리에 달려 있다. cd 하면
" 기억해 둔 '경로 -> 루트'를 버려서 다음 렌더가 새 기준으로 다시 판단한다.
augroup ProjectFilesTreeRoot
    autocmd!
    autocmd DirChanged * call luaeval('_G.projectfiles_tree_invalidate()')
augroup END

" 범위를 커맨드로도 쓸 수 있게 (:'<,'>ProjectFilesIndexAdd)
command! -range -bar ProjectFilesIndexAdd
            \ call ProjectFilesTreeAddRange(<line1>, <line2>)
command! -range -bar ProjectFilesIndexRemove
            \ call ProjectFilesTreeRemoveRange(<line1>, <line2>)


" 이벤트의 대상은 a:event.subject 다 (a:event.path 가 아니다 -
" nerdtree/lib/nerdtree/event.vim 의 Event.New 가 subject 로 담는다)
function! s:OnPathEvent(event) abort
    let l:path = a:event.subject
    call l:path.flagSet.clearFlags('projectfiles')
    " 트리가 열고 있는 루트를 같이 넘긴다: 표시는 '지금 보고 있는
    " 프로젝트'의 목록이어야 하고, 하위 프로젝트의 목록이 섞이면 안 된다.
    "
    " luaeval 은 vim 리스트를 1-기반 Lua 테이블로 넘긴다. _A[0] 은 nil 이다 -
    " 그렇게 써서 경로가 nil 로 들어가 표시가 통째로 사라져 있었다.
    "
    " b:NERDTree 는 이 콜백이 트리 버퍼 문맥에서 불릴 때만 있다. 없을 때를
    " 위해 마지막으로 본 루트를 기억해 둔다.
    if exists('b:NERDTree')
        let s:last_tree_root = b:NERDTree.root.path.str()
    endif
    let l:root = get(s:, 'last_tree_root', '')
    let l:m = luaeval('_G.projectfiles_tree_flag(_A[1], _A[2])',
                \ [l:path.str(), l:root])
    if type(l:m) == v:t_string && !empty(l:m)
        call l:path.flagSet.addFlag('projectfiles', l:m)
    endif
endfunction

" ---------------------------------------------------------------------------
" NERDTree API 가 필요한 부분
" ---------------------------------------------------------------------------
" 이 파일은 ~/.vim/plugin 에 있고 그 디렉터리는 rtp 에서 plugged 보다 앞이라,
" NERDTree 의 plugin/NERD_tree.vim 보다 먼저 읽힌다 (:scriptnames 실측으로
" #19 대 #42). 그래서 여기서는 NERDTreeAddKeyMap 같은 함수가 아직 없다.
"
" 예전에는 그때 파일 전체를 finish 하고 VimEnter 에서 다시 읽었는데, 그러면
" 시작 직후 한동안 ProjectFilesTreeAddRange 도 :ProjectFilesIndexAdd 도 없는
" 상태가 된다. 이제 순서에 의존하는 것만 이 함수에 모으고, 나머지는 언제나
" 정의된다.
function! s:RegisterNERDTree() abort
    if exists('g:loaded_projectfiles_tree_nt') || !exists('*NERDTreeAddKeyMap')
        return
    endif
    let g:loaded_projectfiles_tree_nt = 1
    " ---------------------------------------------------------------------------
    " 키
    " ---------------------------------------------------------------------------
    " NERDTree 의 기본 키를 피해서 고른 것들이다(+ - = 는 비어 있다).
    call NERDTreeAddKeyMap({
                \ 'key': get(g:, 'projectfiles_tree_add_key', '+'),
                \ 'scope': 'Node',
                \ 'callback': 'ProjectFilesTreeAdd',
                \ 'quickhelpText': '색인에 추가 (project index)' })
    call NERDTreeAddKeyMap({
                \ 'key': get(g:, 'projectfiles_tree_remove_key', '-'),
                \ 'scope': 'Node',
                \ 'callback': 'ProjectFilesTreeRemove',
                \ 'quickhelpText': '색인에서 제거' })
    call NERDTreeAddKeyMap({
                \ 'key': get(g:, 'projectfiles_tree_info_key', '='),
                \ 'scope': 'Node',
                \ 'callback': 'ProjectFilesTreeInfo',
                \ 'quickhelpText': '색인 상태 보기' })

    " NERDTreeAddKeyMap 은 normal 모드만 걸어 준다. 범위를 고르는 것은 visual
    " 모드이므로 트리 버퍼에 직접 건다. '<,'> 는 xnoremap 안에서 <C-u> 로 범위
    " 접두사를 지운 뒤 mark 로 읽는다(그래야 v / V / <C-v> 가 모두 같이 된다).
    " ---------------------------------------------------------------------------
    " m 메뉴
    " ---------------------------------------------------------------------------
    if exists('*NERDTreeAddSubmenu')
        let s:sub = NERDTreeAddSubmenu({ 'text': '(i)ndex - 프로젝트 색인',
                    \ 'shortcut': 'i' })
        call NERDTreeAddMenuItem({ 'text': '(a)dd - 색인에 추가',
                    \ 'shortcut': 'a', 'callback': 'ProjectFilesTreeAdd',
                    \ 'parent': s:sub })
        call NERDTreeAddMenuItem({ 'text': '(r)emove - 색인에서 제거',
                    \ 'shortcut': 'r', 'callback': 'ProjectFilesTreeRemove',
                    \ 'parent': s:sub })
        call NERDTreeAddMenuItem({ 'text': '(s)tatus - 색인 상태',
                    \ 'shortcut': 's', 'callback': 'ProjectFilesTreeInfo',
                    \ 'parent': s:sub })
        call NERDTreeAddMenuItem({ 'text': '(m)ode - 색인 모드 고르기',
                    \ 'shortcut': 'm', 'callback': 'ProjectFilesTreeMode',
                    \ 'parent': s:sub })
        call NERDTreeAddMenuItem({ 'text': '(i)ndex now - 지금 재색인',
                    \ 'shortcut': 'i', 'callback': 'ProjectFilesTreeReindex',
                    \ 'parent': s:sub })
    endif

    " ---------------------------------------------------------------------------
    " 노드 옆 표시
    " ---------------------------------------------------------------------------
    " nerdtree-git-plugin 과 같은 방식(PathNotifier + flagSet)이라 서로 간섭하지
    " 않는다. scope 이름만 다르면 각자의 표시가 나란히 붙는다.
    if get(g:, 'projectfiles_tree_marks', 1) != 0 && exists('g:NERDTreePathNotifier')
        call g:NERDTreePathNotifier.AddListener('init', function('s:OnPathEvent'))
        call g:NERDTreePathNotifier.AddListener('refresh', function('s:OnPathEvent'))
        call g:NERDTreePathNotifier.AddListener('refreshFlags', function('s:OnPathEvent'))
    endif

endfunction

call s:RegisterNERDTree()
if !exists('g:loaded_projectfiles_tree_nt')
    augroup ProjectFilesTreeLate
        autocmd!
        autocmd VimEnter * ++once call s:RegisterNERDTree()
    augroup END
endif
