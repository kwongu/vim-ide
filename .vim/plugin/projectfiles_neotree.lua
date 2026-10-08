-- projectfiles_neotree.lua - neo-tree 에서도 색인 목록을 고친다.
--
-- NERDTree 쪽(projectfiles_tree.vim)과 같은 키, 같은 동작이다:
--
--   +   커서 밑(또는 고른 범위)을 색인 목록에 담는다
--   -   뺀다
--   =   지금 담겨 있는지, 어느 .tags 에 담기는지 말한다
--
-- v / V / <C-v> 로 여러 줄을 고른 뒤 + 나 - 를 누르면 그 범위 전체에
-- 적용된다. 범위는 한 번의 커밋으로 처리된다(목록을 여러 번 다시 쓰지
-- 않는다) - projectfiles.lua 의 배치 경로(_G.projectfiles_add_many /
-- _remove_many, 없으면 예전의 _G.projectfiles_add / _remove)를 그대로 쓴다.
--
-- 표시([●]/[·])는 neo-tree 가 그리는 것이 아니라 이 파일의 decoration
-- provider 가 '보이는 줄'에만 덧그린다 - 아래 '색인 표시' 참고.
--
-- 옵션은 NERDTree 쪽과 공유한다(키를 한 곳에서 바꾸면 둘 다 바뀐다):
--   g:projectfiles_tree_add_key      기본 '+'
--   g:projectfiles_tree_remove_key   기본 '-'
--   g:projectfiles_tree_info_key     기본 '='
--   g:projectfiles_neotree = 0       neo-tree 쪽만 끄기

if vim.g.loaded_projectfiles_neotree then
  return
end
vim.g.loaded_projectfiles_neotree = 1

if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local uv = vim.uv or vim.loop

local function enabled()
  return vim.g.projectfiles_neotree == nil or vim.g.projectfiles_neotree ~= 0
end

local function key(name, default)
  local v = vim.g['projectfiles_tree_' .. name .. '_key']
  return (v == nil or v == '') and default or tostring(v)
end

-- 이 창의 neo-tree 상태. 창으로 먼저 묻고, 안 되면 버퍼가 알려 주는
-- source 이름으로 묻는다(neo-tree 가 버퍼에 neo_tree_source 를 심는다).
local function tree_state()
  local ok, manager = pcall(require, 'neo-tree.sources.manager')
  if not ok then
    return nil
  end
  local ok2, st = pcall(manager.get_state_for_window, api.nvim_get_current_win())
  if ok2 and st and st.tree then
    return st
  end
  local src = vim.b.neo_tree_source
  if src then
    local ok3, st2 = pcall(manager.get_state, src)
    if ok3 and st2 and st2.tree then
      return st2
    end
  end
  return nil
end

local function path_at(state, lnum)
  local ok, node = pcall(function()
    return state.tree:get_node(lnum)
  end)
  if not ok or not node then
    return nil
  end
  -- 'message' 같은 안내 노드에는 경로가 없다
  local p = node.path
  if type(p) ~= 'string' or p == '' then
    return nil
  end
  return p
end

-- 검색 결과 목록에서 범위를 잡을 때, 디렉터리 줄은 '결과'가 아니다.
--
-- F 로 찾으면 트리는 맞은 파일들과 '그 파일이 들어 있는 디렉터리'를 함께
-- 보여 준다. 디렉터리는 어디에 있는지 알려 주는 뼈대일 뿐 찾은 것이 아닌데,
-- V 로 목록을 통째로 훑으면 그것들까지 들어온다 - 맨 윗줄은 프로젝트
-- 루트라서, 색인에 담는 순간 트리 전체가 들어간다.
--
-- 그래서 검색 중에 '범위'로 고를 때는 파일만 담는다. 한 줄에서 누르는 것은
-- 그대로 둔다 - 그건 그 디렉터리를 담겠다고 콕 집은 것이다.
local function searching(st)
  local sp = st and st.search_pattern
  return type(sp) == 'string' and sp ~= ''
end

local function is_dir(st, lnum)
  local ok, node = pcall(function()
    return st.tree:get_node(lnum)
  end)
  return ok and node and node.type == 'directory' or false
end

-- 범위의 줄들이 가리키는 경로. 같은 경로가 여러 줄에 걸쳐도 한 번만.
local function paths_in(first, last)
  local st = tree_state()
  if not st then
    return {}
  end
  local lo, hi = math.min(first, last), math.max(first, last)
  local files_only = (hi > lo) and searching(st)
  local out, seen = {}, {}
  for l = lo, hi do
    if not (files_only and is_dir(st, l)) then
      local p = path_at(st, l)
      -- 범위에 트리의 머리줄(트리가 열고 있는 디렉터리)이 끼면 뺀다. 한 줄을
      -- 콕 집어 누른 것은 그대로 둔다. 트리를 하위 디렉터리에 열어 두면
      -- ('.' 로 루트를 옮기면) 머리줄이 프로젝트 루트가 아니라서
      -- projectfiles 의 루트 거르기에 걸리지 않고, 그 디렉터리 전체가 담겼다.
      if p and hi > lo and st.path and p == st.path then
        p = nil
      end
      if p and not seen[p] then
        seen[p] = true
        out[#out + 1] = p
      end
    end
  end
  return out
end

local function cursor_paths()
  local l = api.nvim_win_get_cursor(0)[1]
  return paths_in(l, l)
end

-- 비주얼 모드에서 고른 줄 범위. 'v' 마크는 아직 갱신되지 않았을 수 있어
-- line('v') 와 line('.') 을 쓴다.
local function visual_range()
  local a = vim.fn.line('v')
  local b = vim.fn.line('.')
  return math.min(a, b), math.max(a, b)
end

local function leave_visual()
  api.nvim_feedkeys(
    api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

local sync_trees  -- 아래에서 정의

local function act(paths, fn, what)
  if #paths == 0 then
    vim.notify('ProjectFiles: 경로가 있는 줄이 아닙니다', vim.log.levels.WARN)
    return
  end
  if type(fn) ~= 'function' then
    vim.notify('ProjectFiles: projectfiles.lua 가 올라오지 않았습니다', vim.log.levels.WARN)
    return
  end
  local ok, err = pcall(fn, paths)
  if not ok then
    vim.notify('ProjectFiles: ' .. what .. ' 실패 - ' .. tostring(err),
      vim.log.levels.ERROR)
    return
  end
  -- 표시는 바뀐 목록을 이 키 안에서 바로 따라간다. 목록 파일이 바뀐 트리 창만
  -- 다시 그리게 하고(neo-tree 를 다시 렌더하지 않는다), 뒤이어 오는
  -- ProjectFilesChanged 는 이미 그린 것과 같으니 아무것도 하지 않는다.
  -- 예전에는 여기서 refresh_trees 를 미루고 그 이벤트에서 또 그려서, +/- 한 번에
  -- 트리 전체를 두 번 다시 렌더했다(펼친 줄 2000개에서 120ms, stat 이 느린
  -- 서버를 흉내 내면 760ms). 색인(GTAGS)은 기다리지 않는다 - 뒤에서 따라온다.
  if sync_trees then
    sync_trees()
  end
end

-- 범위는 projectfiles.lua 의 배치 API 로 한 번에 넘긴다: preset 을 한 번 쓰고
-- 목록을 한 번 고치고, 프로젝트마다 재색인도 한 번이다. 그 API 가 없는 옛
-- projectfiles.lua 면 예전처럼 표 하나를 _G.projectfiles_add 에 넘긴다(그쪽도
-- 배치로 처리한다).
--
-- 한 줄은 일부러 단건 API 로 간다: 배치는 범위에 낀 프로젝트 루트 줄을
-- 걸러내는데, 루트 줄에서 + 를 한 번 누른 것은 '루트를 담아라'다(README).
local function pick(paths, many, one)
  local f = #paths > 1 and _G[many] or nil
  if type(f) == 'function' then
    return f
  end
  return _G[one]
end

local function do_add(paths)
  act(paths, pick(paths, 'projectfiles_add_many', 'projectfiles_add'), '추가')
end

local function do_remove(paths)
  act(paths, pick(paths, 'projectfiles_remove_many', 'projectfiles_remove'), '제거')
end

local function do_info()
  local p = cursor_paths()[1]
  if not p then
    vim.notify('ProjectFiles: 경로가 있는 줄이 아닙니다', vim.log.levels.WARN)
    return
  end
  vim.notify('ProjectFiles: ' .. tostring(_G.projectfiles_status(p)))
end

-- nowait: 키가 전역 매핑의 앞머리면 nvim 이 'timeoutlen' 동안 다음 글자를
-- 기다린다. '=' 가 그랬다 - vim-unimpaired 의 =p =P =s 때문에 누를 때마다
-- 0.8초 뒤에야 답했다. netrw/quickfix/bufexplorer/relationview 쪽은 이미 nowait.
local function map_buf(buf)
  local function nmap(lhs, fn, desc)
    if lhs == '' then
      return
    end
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  local function xmap(lhs, fn, desc)
    if lhs == '' then
      return
    end
    vim.keymap.set('x', lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  local ka, kr, ki = key('add', '+'), key('remove', '-'), key('info', '=')

  nmap(ka, function() do_add(cursor_paths()) end, 'ProjectFiles: 색인에 담기')
  nmap(kr, function() do_remove(cursor_paths()) end, 'ProjectFiles: 색인에서 빼기')
  nmap(ki, do_info, 'ProjectFiles: 이 경로의 색인 상태')

  -- 범위: 고른 줄 전체에 한 번의 커밋으로
  xmap(ka, function()
    local f, l = visual_range()
    leave_visual()
    vim.schedule(function() do_add(paths_in(f, l)) end)
  end, 'ProjectFiles: 고른 범위를 색인에 담기')
  xmap(kr, function()
    local f, l = visual_range()
    leave_visual()
    vim.schedule(function() do_remove(paths_in(f, l)) end)
  end, 'ProjectFiles: 고른 범위를 색인에서 빼기')
end

-- ---------------------------------------------------------------------------
-- 색인 표시
-- ---------------------------------------------------------------------------
-- NERDTree 쪽과 같은 표시를 neo-tree 에도 단다:
--   [O]  이 파일이 색인 목록에 있다
--   [.]  이 디렉터리 아래에 색인된 파일이 있다
-- (실제 글자는 g:projectfiles_tree_mark_file / _mark_dir 이고 기본은 ●/·)
--
-- 판정은 NERDTree 의 _G.projectfiles_tree_flag 와 같다: 트리가 열고 있는
-- 디렉터리의 프로젝트(_G.projectfiles_root_of, 현재 디렉터리 기준 고정 포함)의
-- '<root>/.tags/files' 에 있으면 파일 표시, 그 아래에 있는 것이 있으면 디렉터리
-- 표시, auto 모드(목록 파일이 없다)면 아무 표시도 없다. 심볼릭 링크는 풀어서
-- 판정한다.
--
-- 예전에는 neo-tree 컴포넌트가 줄마다 projectfiles_tree_flag 를 불러 표시를
-- 글자로 그렸다. 그게 +/- 한 번마다 이렇게 됐다(펼친 줄 2090개, 실측):
--   * 트리 전체를 두 번 다시 렌더했다 - 키 처리에서 미룬 redraw 하나,
--     ProjectFilesChanged 에서 또 하나.
--   * 줄마다 '.tags/files' 를 fs_stat 했다(목록이 바뀌었나 보려고) - 4195번.
--   * 목록이 바뀌면 경로->실제 경로 캐시까지 버려서 줄마다 fs_realpath - 2090번.
--   합쳐 120~140ms, stat 하나에 0.1ms 를 더해 서버를 흉내 내면 760ms 였다.
--   펼치고 접을 때마다 하는 렌더에서도 줄마다 stat 이 따라붙었다.
--
-- 이제 컴포넌트는 표시 자리만 비워 둔다(빈칸 + 아무 색도 없는 하이라이트
-- 'ProjectFilesIndexPad'). 표시는 decoration provider 가 화면에 그릴 때 '보이는
-- 줄'에만 덧그린다(ephemeral overlay) - 자리는 그 하이라이트가 남긴 extmark 로
-- 정확히 찾는다(이름을 문자열로 찾으면 잘린 이름, 루트 줄에서 틀린다). 그래서
--   * 목록이 바뀌면 neo-tree 를 다시 렌더하지 않고 그 창만 다시 그린다:
--     비용은 펼친 줄 수가 아니라 창 높이에 비례한다.
--   * 목록 파일 stat 은 한 번 그릴 때 한 번(같은 틱이면 다시 하지 않는다).
--   * 실제 경로는 디렉터리 단위로 기억하고, 목록이 바뀌어도 버리지 않는다
--     (실제 경로는 목록과 상관이 없다). 노드 자체가 링크이거나 종류를 모를
--     때만 그 경로를 따로 푼다 - 링크인 디렉터리 아래의 파일은 neo-tree 가
--     is_link 를 달지 않으므로 디렉터리 쪽을 푸는 것으로 맞게 나온다.
--   * 그릴 때마다 목록을 보므로 다른 nvim 이 목록을 고쳐도 다음에 그릴 때
--     따라간다.
--
-- 버퍼에 extmark 를 박아 두는 방식은 쓰지 않는다: neo-tree 는 펼치기·접기·git
-- 갱신 때 줄을 통째로 갈아 끼우고 그 뒤에 알림(AFTER_RENDER)도 주지 않아서,
-- 박아 둔 표시가 다른 줄로 밀린다(dirdiffpick.lua 의 [A] 와 같은 이유).
local MARK_HL = 'ProjectFilesIndexMark'
local PAD_HL = 'ProjectFilesIndexPad'
local ns = api.nvim_create_namespace('projectfiles_neotree_mark')

-- 표시는 눈에 띄어야 한다.
--
-- 처음에는 'Special' 에 link 해 뒀는데, 쓰고 있는 테마(sourceinsight,
-- 밝은 배경)에서 Special 은 검정(#000000)이라 파일 이름과 구분이 되지
-- 않았다. 이 테마의 빨강은 #cc0000 이다(ErrorMsg / Error / DiffDelete 가
-- 모두 그 색). termguicolors 가 꺼진 환경도 있어서 cterm 값도 함께 준다.
--
--   let g:projectfiles_mark_hl = 'ErrorMsg'   " 다른 그룹을 따라가게
--   let g:projectfiles_mark_color = '#ff0000' " 색만 바꾸기
local function set_mark_hl()
  -- 자리 표시용 그룹은 일부러 아무 속성도 없다(커서 줄 색 등을 가리지 않게)
  api.nvim_set_hl(0, PAD_HL, {})
  local link = vim.g.projectfiles_mark_hl
  if type(link) == 'string' and link ~= '' then
    api.nvim_set_hl(0, MARK_HL, { link = link })
    return
  end
  local fg = vim.g.projectfiles_mark_color
  api.nvim_set_hl(0, MARK_HL, {
    fg = (type(fg) == 'string' and fg ~= '') and fg or '#cc0000',
    ctermfg = 160,
    bold = true,
  })
end

set_mark_hl()
api.nvim_create_autocmd('ColorScheme', {
  group = api.nvim_create_augroup('ProjectFilesNeotreeHl', { clear = true }),
  callback = function()
    -- 컬러스킴이 바뀌면 그룹이 지워지므로 다시 건다
    vim.schedule(set_mark_hl)
  end,
})

-- 표시를 다는 기능이 살아 있나. projectfiles.lua 는 nvim 0.10 이상에서만
-- 올라오고, nvim__redraw 도 0.10 부터다.
local function marks_on()
  return enabled() and type(_G.projectfiles_root_of) == 'function'
    and api.nvim__redraw ~= nil
end

-- 표시 글자와 자리 폭. 컴포넌트가 줄마다 부르므로 vim.g 는 한 틱에 한 번만
-- 읽는다. 자리는 '[표시]' 에 한 칸을 더한 폭이다 - 예전 그림('[●] 이름',
-- neo-tree 가 ']' 뒤에 한 칸을 띄웠다)과 같게 보이면서, 표시가 없는 줄의
-- 이름도 같은 칸에서 시작한다(예전에는 표시가 있는 줄만 한 칸 밀렸다).
local glyph = { t = nil, mf = nil, md = nil, pad = '    ', w = nil }
local function glyphs()
  local t = uv.now()
  if glyph.t ~= t then
    glyph.t = t
    local mf, md = vim.g.projectfiles_tree_mark_file, vim.g.projectfiles_tree_mark_dir
    mf = (mf == nil or mf == '') and '●' or tostring(mf)
    md = (md == nil or md == '') and '·' or tostring(md)
    if mf ~= glyph.mf or md ~= glyph.md or not glyph.w then
      glyph.mf, glyph.md = mf, md
      glyph.w = math.max(vim.fn.strdisplaywidth('[' .. mf .. ']'),
        vim.fn.strdisplaywidth('[' .. md .. ']'))
      glyph.pad = string.rep(' ', glyph.w + 1)
    end
  end
  return glyph
end

-- neo-tree 컴포넌트. .vimrc 의 setup 에서 이 함수를 부른다.
-- 표시가 없을 때도 같은 폭을 차지해야 이름이 들쭉날쭉하지 않다. 여기서는
-- 자리만 잡고 계산은 하지 않는다 - 렌더(펼치기·접기·따라가기마다 한다)가
-- 노드 수만큼 stat 하지 않게.
function _G.projectfiles_neotree_mark(_, node, _)
  if not marks_on() then
    return { text = '' }
  end
  local path = node and node.path
  if type(path) ~= 'string' or path == '' then
    return { text = '' }
  end
  return { text = glyphs().pad, highlight = PAD_HL }
end

local tree_bufs = {}  -- neo-tree 버퍼들 (FileType 에서 모은다)
local roots = {}      -- 트리가 연 디렉터리 -> 프로젝트 루트 | false
local lists = {}      -- 루트 -> { key, preset, files, dirs }
local checked = {}    -- 루트 -> 목록 파일을 stat 한 틱(uv.now())
local real_dir = {}   -- 디렉터리 -> 실제 경로
local real_one = {}   -- 링크(또는 종류를 모르는) 노드 -> 실제 경로
local nreal = 0
local pad_cache = {}  -- 버퍼 -> { tick, lo, hi, cols = { [줄] = 바이트 열 } }
local drawn = {}      -- 창 -> 마지막으로 그릴 때 쓴 '루트 + 목록 키' (자리 없으면 false)

local function state_of(buf)
  local mgr = package.loaded['neo-tree.sources.manager']
  if not mgr then
    return nil
  end
  local ok, states = pcall(mgr._get_all_states)
  if not ok or type(states) ~= 'table' then
    return nil
  end
  for _, st in ipairs(states) do
    if st.bufnr == buf and st.tree and not st.disposed then
      return st
    end
  end
end

-- 트리가 연 디렉터리의 프로젝트. root_of 는 위로 올라가며 stat 을 하므로
-- 트리마다 한 번만 묻는다. projectfiles_tree_flag 처럼 자식 하나를 붙여서
-- 묻는다(root_of 는 인자의 dirname 에서 출발한다).
local function root_for(treeroot)
  treeroot = tostring(treeroot or ''):gsub('/+$', '')
  local r = roots[treeroot]
  if r == nil then
    local ok, got = pcall(_G.projectfiles_root_of,
      (treeroot ~= '' and treeroot or vim.fn.getcwd()) .. '/x')
    r = ok and type(got) == 'string' and got ~= '' and got or false
    roots[treeroot] = r
  end
  return r
end

-- projectfiles.lua 의 dbdir() 과 같은 규칙 (빈 값이면 '.tags')
local function list_file(root)
  local d = vim.g.autoindex_dbdir
  if d == nil or d == '' or d == '.' then
    d = '.tags'
  end
  return root .. '/' .. tostring(d):gsub('/+$', '') .. '/files'
end

-- 루트의 목록. 한 틱에 stat 한 번 - 렌더 하나, 화면 그리기 하나가 한 틱이다.
-- 키에 nsec 과 크기까지 넣는다(같은 초에 두 번 고쳐 써도 알아본다).
local function list_of(root)
  local c = lists[root]
  local t = uv.now()
  if c and checked[root] == t then
    return c
  end
  checked[root] = t
  local lf = list_file(root)
  local st = uv.fs_stat(lf)
  local key = st and ('%d:%d:%d'):format(st.mtime.sec, st.mtime.nsec or 0, st.size)
    or 'none'
  if c and c.key == key then
    return c
  end
  local files, dirs = {}, {}
  local f = st and io.open(lf, 'rb')
  if f then
    local text = f:read('*a') or ''
    f:close()
    for rel in text:gmatch('[^\n]+') do
      files[rel] = true
      -- 상위 디렉터리도 표시 대상으로. 이미 있는 디렉터리를 만나면 멈춘다 -
      -- 그 위는 그 디렉터리를 넣을 때 이미 다 넣었다(파일마다 끝까지 올라가지
      -- 않으니 커널 크기 목록에서도 줄 수에 비례한다).
      local up = rel
      while true do
        local parent = up:match('^(.*)/[^/]+$')
        if not parent or parent == '' or dirs[parent] then
          break
        end
        dirs[parent] = true
        up = parent
      end
    end
  end
  c = { key = key, preset = st ~= nil, files = files, dirs = dirs }
  lists[root] = c
  return c
end

local function forget_real()
  real_dir, real_one, nreal = {}, {}, 0
end

-- kind: 'dir' 이면 디렉터리 캐시, 아니면 노드 하나짜리 캐시
local function realpath(kind, p)
  local cache = kind == 'dir' and real_dir or real_one
  local rp = cache[p]
  if rp == nil then
    rp = uv.fs_realpath(p) or p
    if nreal >= 50000 then
      -- 커널 트리를 오래 돌아다녀도 끝없이 커지지 않게
      forget_real()
      cache = kind == 'dir' and real_dir or real_one
    end
    cache[p] = rp
    nreal = nreal + 1
  end
  return rp
end

-- 노드의 실제 경로. 추가/제거/상태(=)는 심볼릭 링크를 풀어 실제 경로로 다루므로
-- 표시도 같은 경로로 판정해야 링크 줄의 점이 = 과 어긋나지 않는다.
local function real_of(node, path)
  local t = node.type
  if node.is_link or (t ~= 'file' and t ~= 'directory') then
    return realpath('one', path)
  end
  local dir, name = path:match('^(.+)/([^/]+)$')
  if not dir then
    return path
  end
  local rd = realpath('dir', dir)
  if rd == dir then
    return path
  end
  return (rd == '/' and '' or rd) .. '/' .. name
end

local function mark_of(node, root, c, g)
  local path = node.path
  local rp = real_of(node, path)
  -- 풀린 경로가 이 프로젝트 안일 때만 쓴다 - 밖이면 담을 수 없으니 점도 없다
  if rp ~= path and rp:sub(1, #root + 1) == root .. '/' then
    path = rp
  end
  if path:sub(1, #root + 1) ~= root .. '/' then
    return nil
  end
  local rel = path:sub(#root + 2)
  if c.files[rel] then
    return g.mf
  end
  if c.dirs[rel] then
    return g.md
  end
end

-- 보이는 줄들에서 표시 자리(PAD_HL 하이라이트)가 있는 줄과 그 바이트 열.
-- neo-tree 가 버퍼를 다시 쓰지 않은 동안(changedtick 이 같은 동안)은 다시
-- 찾지 않는다 - 트리 안에서 커서만 움직일 때도 화면은 다시 그려진다.
local tree_ns = nil
local function pads_in(buf, top, bot)
  local tick = api.nvim_buf_get_changedtick(buf)
  local p = pad_cache[buf]
  if p and p.tick == tick and p.lo <= top and p.hi >= bot then
    return p.cols
  end
  -- neo-tree 가 하이라이트를 거는 이름공간만 본다(없으면 전부)
  tree_ns = tree_ns or api.nvim_get_namespaces()['neo-tree.nvim']
  local cols = {}
  local marks = api.nvim_buf_get_extmarks(buf, tree_ns or -1, { top, 0 }, { bot, -1 },
    { details = true, type = 'highlight' })
  for _, m in ipairs(marks) do
    local d = m[4]
    if d and d.hl_group == PAD_HL then
      cols[m[2]] = m[3]
    end
  end
  pad_cache[buf] = { tick = tick, lo = top, hi = bot, cols = cols }
  return cols
end

local function sig_of(root, c)
  return root and (root .. '\0' .. c.key) or '-'
end

-- 창 전체를 다시 그리게 한다 (바뀌지 않은 줄까지)
local function force(w)
  if not pcall(api.nvim__redraw, { win = w, valid = false }) then
    pcall(vim.cmd, 'redraw!')
  end
end

local function draw(win, buf, top, bot)
  local st = state_of(buf)
  if not st then
    return
  end
  -- botrow 는 어림값일 수 있다: 창 높이만큼은 본다
  bot = math.max(bot, top + api.nvim_win_get_height(win))
  local cols = pads_in(buf, top, bot)
  if next(cols) == nil then
    drawn[win] = false
    return
  end
  local root = root_for(st.path)
  local c = root and list_of(root)
  -- on_win 은 창의 몇 줄만 다시 그릴 때도 불린다(커서만 움직였을 때, 명령 중간의
  -- :redraw). 그런 때 목록이 바뀌어 있으면 다시 그린 줄만 새 표시가 되고 나머지
  -- 줄에는 지난 표시가 남는다 - auto 로 바꿨는데 [·] 가 남아 있었다. 그래서 그린
  -- 기준이 바뀐 것을 보면 창 전체를 한 번 더 그리게 한다.
  local sig = sig_of(root, c)
  local was = drawn[win]
  drawn[win] = sig
  if was and was ~= sig then
    vim.schedule(function()
      if api.nvim_win_is_valid(win) then
        force(win)
      end
    end)
  end
  if not root or not c.preset then
    return -- auto 모드: 전부 대상이라 표시할 게 없다
  end
  local g = glyphs()
  local tree = st.tree
  for row, col in pairs(cols) do
    if row >= top and row <= bot then
      local ok, node = pcall(tree.get_node, tree, row + 1)
      if ok and node and type(node.path) == 'string' and node.path ~= '' then
        local m = mark_of(node, root, c, g)
        if m then
          api.nvim_buf_set_extmark(buf, ns, row, col, {
            virt_text = { { '[' .. m .. ']', MARK_HL } },
            virt_text_pos = 'overlay',
            hl_mode = 'combine',
            ephemeral = true,
          })
        end
      end
    end
  end
end

api.nvim_set_decoration_provider(ns, {
  on_win = function(_, win, buf, top, bot)
    -- 모든 창의 모든 다시 그리기마다 불린다: 트리가 아니면 표 하나 보고 끝
    if not tree_bufs[buf] or not marks_on() then
      return false
    end
    pcall(draw, win, buf, top, bot)
    return false
  end,
})

-- 목록(또는 루트)이 바뀐 트리 창만 다시 그리게 한다. 떠 있는 트리만 - F9,
-- F11, RelationView 의 트리 모두. 이미 지금 목록으로 그린 창은 건드리지 않는다:
-- 트리에서 누른 +/- 는 키 안에서 여기를 부르고, 곧이어 오는
-- ProjectFilesChanged 에서는 같은 목록이라 아무것도 하지 않는다(다시 그리기는
-- 한 번). 다른 탭의 트리는 그 탭으로 갈 때 화면 전체가 다시 그려지며 따라간다.
sync_trees = function()
  if not marks_on() then
    return
  end
  checked = {} -- 목록 파일을 다시 본다 (같은 틱이어도)
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    if tree_bufs[b] and drawn[w] ~= false then
      local st = state_of(b)
      local sig = '-'
      if st then
        local root = root_for(st.path)
        sig = root and sig_of(root, list_of(root)) or '-'
      end
      if not st or sig ~= drawn[w] then
        drawn[w] = sig
        force(w)
      end
    end
  end
end

-- 색인 목록이 다른 곳에서 바뀌어도(quickfix 의 +, RelationView 의 i+,
-- :ProjectFilesAdd) 트리의 표시를 따라가게 한다. projectfiles.lua 가 쏜다.
-- 예전에는 트리에서 누른 +/- 뒤에만 다시 그려서, 다른 데서 바꾸면 표시가
-- 트리를 다시 열 때까지 낡아 있었다.
--
-- VimIdeIndexUpdated 는 autoindex.lua 가 GTAGS 를 고친 뒤에 쏜다. 두 가지를
-- 따라간다: 색인 갱신이 목록을 다시 펼치며 고쳐 쓴 것(git pull 로 디렉터리
-- 항목 아래에 생긴 파일 - 그 길은 ProjectFilesChanged 를 쏘지 않는다), 그리고
-- 처음 생긴 GTAGS 로 바뀐 루트. 목록 파일이 그대로면 다시 그리지 않는다.
--
-- :cd 는 루트 고정(anchor_cwd)을 바꾼다.
local function on_changed(a)
  if not enabled() then
    return
  end
  -- 파일 하나의 갱신(:w 마다 온다)은 데이터베이스를 새로 만들지 않으니 루트는 그대로
  local d = type(a) == 'table' and type(a.data) == 'table' and a.data or nil
  if not (a and a.match == 'VimIdeIndexUpdated' and d and d.kind == 'single') then
    roots = {}
  end
  sync_trees()
end

local changed_group = api.nvim_create_augroup('ProjectFilesNeotreeChanged', { clear = true })
api.nvim_create_autocmd('User', {
  group = changed_group,
  pattern = { 'ProjectFilesChanged', 'VimIdeIndexUpdated' },
  callback = on_changed,
})
api.nvim_create_autocmd('DirChanged', {
  group = changed_group,
  callback = on_changed,
})

-- 트리에서 이름을 바꾸거나 옮기면(r / m / x,p) 색인 목록이 따라간다
-- (projectfiles.lua 의 projectfiles_renamed). 예전에는 이 이벤트를 듣지 않아서
-- 바꾼 이름은 색인에서 빠지고, preset 에는 없는 경로가 남았다.
--
-- neo-tree 의 setup() 이 다시 불리면 이벤트 구독이 모두 지워진다
-- (events.clear_all_events). 그래서 트리 버퍼가 생길 때마다 같은 id 로 다시 건다.
local function on_moved(args)
  -- 옮긴 경로 아래로 기억해 둔 실제 경로는 더는 맞지 않을 수 있다
  forget_real()
  if enabled() and type(args) == 'table' and type(_G.projectfiles_renamed) == 'function' then
    _G.projectfiles_renamed(args.source, args.destination)
  end
end

local function subscribe_moves()
  local ok, events = pcall(require, 'neo-tree.events')
  if not (ok and type(events) == 'table' and events.subscribe) then
    return
  end
  for _, ev in ipairs({ events.FILE_RENAMED, events.FILE_MOVED }) do
    local h = { id = 'projectfiles_' .. ev, event = ev, handler = on_moved }
    pcall(events.unsubscribe, h)
    pcall(events.subscribe, h)
  end
end
subscribe_moves()

-- neo-tree 가 자기 매핑을 건 뒤에 걸어야 우리 것이 이긴다. FileType 이
-- neo-tree 의 매핑보다 먼저 올 수 있어서 한 틱 미룬다.
api.nvim_create_autocmd('FileType', {
  group = api.nvim_create_augroup('ProjectFilesNeotree', { clear = true }),
  pattern = 'neo-tree',
  callback = function(a)
    if not enabled() then
      return
    end
    -- 표시를 그릴 버퍼로 기억한다. 버퍼 번호는 다시 쓰일 수 있으니 없어질 때(wipe) 뺀다.
    if not tree_bufs[a.buf] then
      tree_bufs[a.buf] = true
      api.nvim_create_autocmd('BufWipeout', {
        group = api.nvim_create_augroup('ProjectFilesNeotree', { clear = false }),
        buffer = a.buf,
        once = true,
        callback = function(b)
          tree_bufs[b.buf] = nil
          pad_cache[b.buf] = nil
        end,
      })
    end
    vim.schedule(function()
      subscribe_moves()
      if api.nvim_buf_is_valid(a.buf) then
        pcall(map_buf, a.buf)
      end
    end)
  end,
})
