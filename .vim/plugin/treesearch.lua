-- treesearch.lua - neo-tree 에서 커서 자리 이하를 찾는다 (<C-g> grep, <C-f> find)
--
-- F9 왼쪽 트리, F11 뜬 트리, RelationView 의 트리는 셋 다 neo-tree 라서
-- .vimrc 의 neo-tree window.mappings 에 건 두 키가 세 곳 모두에서 먹는다.
--
--   <C-g>  찾기 (grep)   찾을 말 / 찾을 곳     그 아래 파일들의 내용에서
--   <C-f>  찾기 (find)   찾을 파일 / 찾을 곳   그 아래 파일들의 이름에서
--
-- 찾을 곳은 커서 밑 항목으로 정한다
--   디렉터리 줄   그 디렉터리
--   파일 줄       그 파일이 든 디렉터리
--   빈 줄         트리의 루트 (경로가 없는 안내 줄도 같다)
-- 찾을 파일(<C-f>)에는 커서 밑 항목의 이름을 넣는다. 빈 줄이면 비워 둔다.
-- 찾을 말(<C-g>)은 비워 둔다 - 트리의 글자는 파일 이름이지 소스의 낱말이
-- 아니다.
--
-- 결과는 편집 창의 <C-g> 와 같은 자리로 간다: RelationView 패널이 떠
-- 있으면 패널 목록에, 아니면 quickfix 창에.
--
-- 편집 창의 <C-g> 는 이 파일을 거치지 않는다 (.vimrc 의 s:GrepPrompt 그대로).

if vim.g.loaded_vimide_treesearch then
  return
end
vim.g.loaded_vimide_treesearch = 1

local api = vim.api
local WARN = vim.log.levels.WARN

-- 커서 밑 항목에서 찾을 곳과 이름을 읽는다. 키를 누른 그 순간에 읽는다.
-- 찾기 창이 닫히고 나면 지금 창도 커서도 트리라는 보장이 없고, F11 의 뜬
-- 트리는 결과(quickfix, 패널)가 초점을 가져가는 순간 닫힌다.
--
-- neo-tree 의 mapping 함수로 불리므로 지금 창이 키를 누른 그 트리다.
-- get_node 에는 줄 번호를 꼭 준다: 인자가 없으면 nui 가 지금 창이 아니라
-- '그 버퍼를 보여주는 창'(bufwinid, 여럿이면 첫 창)의 커서를 읽는다.
local function target(state)
  local root = state and state.path
  local node
  pcall(function()
    node = state.tree:get_node(api.nvim_win_get_cursor(0)[1])
  end)
  local p = node and node.path
  -- 안내 줄('(3 hidden items)')과 트리 끝 너머에는 경로가 없다
  if type(p) ~= 'string' or p == '' then
    return root, ''
  end
  -- 진짜 파일과 디렉터리만 받는다. < > 로 buffers 소스로 바꾸면 경로를 단
  -- 가짜 줄이 섞인다: 터미널 줄은 path 가 그 터미널의 cwd('/proj/')이고
  -- type 이 'terminal' 이라, 아래 ':h' 를 타면 루트의 부모('/')가 찾을 곳이
  -- 된다. '[No Name]' 줄은 type 이 'file' 인데 path 가 상대 경로다.
  -- (type 'link' 는 링크를 못 읽었을 때만 남는다. 읽히면 가리키는 쪽 type.)
  local t = node.type
  if (t ~= 'file' and t ~= 'directory' and t ~= 'link') or p:sub(1, 1) ~= '/' then
    return root, ''
  end
  if p ~= '/' then
    p = (p:gsub('/+$', ''))
  end
  local dir = t == 'directory' and p or vim.fn.fnamemodify(p, ':h')
  if vim.fn.isdirectory(dir) ~= 1 then
    return root, ''
  end
  -- 세 번째 값은 항목 자체의 경로 (reposearch.lua 가 링크를 풀 때 쓴다 -
  -- 링크 파일의 '든 디렉터리'는 링크 쪽이지 가리키는 쪽이 아니다)
  return dir, vim.fn.fnamemodify(p, ':t'), p
end

-- 찾을 곳 칸의 값을 디렉터리로 푼다. 비우면 처음 넣어 준 곳.
--
-- 손대지 않은 값은 expand() 하지 않는다. 트리에서 온 진짜 경로라서, 이름에
-- $ 나 { } 가 든 디렉터리가 환경 변수나 중괄호 전개로 바뀌면 안 된다.
-- 고쳐 쳤을 때만 ~ 와 $HOME 을 풀어 준다.
local function resolve(v, fallback)
  local raw = (v == '' or v == fallback) and fallback or vim.fn.expand(v)
  local d = vim.fn.fnamemodify(raw, ':p')
  if d ~= '/' then
    d = (d:gsub('/+$', ''))
  end
  if vim.fn.isdirectory(d) ~= 1 then
    vim.notify('그런 디렉터리가 없습니다 - ' .. d, WARN)
    return nil
  end
  return d
end

local function ask_grep(dir, origin)
  _G.vimide_ask({
    title = ' 찾기 (grep) ',
    fields = {
      { label = '찾을 말', value = '' },
      { label = '찾을 곳', value = dir, file = true },
    },
    footer = ' Tab 칸 이동 · Enter 찾기 · Esc 취소 · <C-x><C-f> 경로 완성 ',
  }, function(v)
    -- 찾을 말은 늘 빈칸으로 시작하니, 곧장 찾을 곳으로 가서 Enter 를 치면
    -- 여기로 온다. 아무 말 없이 닫히면 키가 죽은 것처럼 보인다.
    if v[1] == '' then
      vim.notify('찾을 말이 비어 있어 찾지 않았습니다', WARN)
      return
    end
    local d = resolve(v[2], dir)
    if d then
      _G.relationview_grep(v[1], d, origin)
    end
  end)
end

local function ask_find(dir, name)
  _G.vimide_ask({
    title = ' 찾기 (find) ',
    fields = {
      { label = '찾을 파일', value = name },
      { label = '찾을 곳', value = dir, file = true },
    },
    footer = ' Tab 칸 이동 · Enter 찾기 · Esc 취소 · * ? 는 와일드카드 ',
  }, function(v)
    -- 찾을 파일 칸은 expand() 하지 않는다. *.dts 가 vim 의 와일드카드로
    -- 풀려 지금 디렉터리의 파일 이름으로 바뀐다.
    if v[1] == '' then
      vim.notify('찾을 파일이 비어 있어 찾지 않았습니다', WARN)
      return
    end
    local d = resolve(v[2], dir)
    if d then
      _G.relationview_find(v[1], d)
    end
  end)
end

-- reposearch.lua(\ff \fg \fi)도 같은 규칙으로 커서 밑 항목을 읽는다
_G.vimide_tree_target = target

--- .vimrc 의 neo-tree window.mappings 가 부른다. kind = 'grep' | 'find'
function _G.vimide_tree_search(state, kind)
  if type(_G.vimide_ask) ~= 'function' then
    vim.notify('찾기 창(askform.lua)이 없습니다', WARN)
    return
  end
  local fn = kind == 'find' and _G.relationview_find or _G.relationview_grep
  if type(fn) ~= 'function' then
    vim.notify('RelationView(relationview.lua)가 올라와 있지 않습니다', WARN)
    return
  end
  local dir, name = target(state)
  if type(dir) ~= 'string' or dir == '' then
    vim.notify('찾을 곳을 정하지 못했습니다 - 트리의 루트를 모릅니다', WARN)
    return
  end
  if kind == 'find' then
    ask_find(dir, name)
    return
  end
  -- 돌아갈 편집 창은 지금 잡아 둔다. 찾기 창이 닫히면 초점은 트리로
  -- 돌아오므로, 그때 '지금 창'을 쓰면 트리가 돌아갈 자리가 된다
  -- (relationview.lua 의 _G.relationview_grep 주석). 편집 창이 없으면 0.
  local origin = type(_G.vimide_last_edit_win) == 'function'
      and _G.vimide_last_edit_win() or 0
  ask_grep(dir, origin)
end
