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

" NERDTree 가 아직 없으면(지연 로딩) 나중에 다시 시도한다
if !exists('g:NERDTreePathNotifier') && !exists('*NERDTreeAddKeyMap')
    augroup ProjectFilesTreeLate
        autocmd!
        autocmd VimEnter,SourcePost * ++once
                    \ if exists('*NERDTreeAddKeyMap')
                    \ |   unlet! g:loaded_projectfiles_tree
                    \ |   runtime plugin/projectfiles_tree.vim
                    \ | endif
    augroup END
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

" 범위를 커맨드로도 쓸 수 있게 (:'<,'>ProjectFilesIndexAdd)
command! -range -bar ProjectFilesIndexAdd
            \ call ProjectFilesTreeAddRange(<line1>, <line2>)
command! -range -bar ProjectFilesIndexRemove
            \ call ProjectFilesTreeRemoveRange(<line1>, <line2>)

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
    " 이벤트의 대상은 a:event.subject 다 (a:event.path 가 아니다 -
    " nerdtree/lib/nerdtree/event.vim 의 Event.New 가 subject 로 담는다)
    function! s:OnPathEvent(event) abort
        let l:path = a:event.subject
        call l:path.flagSet.clearFlags('projectfiles')
        let l:m = luaeval('_G.projectfiles_tree_flag(_A)', l:path.str())
        if type(l:m) == v:t_string && !empty(l:m)
            call l:path.flagSet.addFlag('projectfiles', l:m)
        endif
    endfunction
    call g:NERDTreePathNotifier.AddListener('init', function('s:OnPathEvent'))
    call g:NERDTreePathNotifier.AddListener('refresh', function('s:OnPathEvent'))
    call g:NERDTreePathNotifier.AddListener('refreshFlags', function('s:OnPathEvent'))
endif
