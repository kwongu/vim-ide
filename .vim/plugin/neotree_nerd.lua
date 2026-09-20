-- neotree_nerd.lua - neo-tree 에서 NERDTree 의 K/J (형제 중 처음/마지막).
--
-- neo-tree 에는 이에 해당하는 명령이 없어서 직접 만든다. 나머지 NERDTree
-- 키(o O X I)는 neo-tree 의 명령에 그대로 붙일 수 있어 .vimrc 에서 맵으로만
-- 얹었다. 파일 조작 키(a A d r c m y x p u)는 neo-tree 것을 건드리지 않는다.

if vim.g.loaded_neotree_nerd then
  return
end
vim.g.loaded_neotree_nerd = 1

-- state.tree 에서 커서 노드의 형제 목록을 얻는다. 최상위 노드는 부모가
-- 없으므로 트리의 루트 자식들을 쓴다.
function _G.neotree_sibling(state, which)
  local ok, renderer = pcall(require, 'neo-tree.ui.renderer')
  if not ok or not state or not state.tree then
    return
  end
  local node = state.tree:get_node()
  if not node then
    return
  end
  local ids
  local pid = node:get_parent_id()
  if pid then
    local parent = state.tree:get_node(pid)
    ids = parent and parent:get_child_ids() or nil
  end
  if not ids then
    ids = state.tree:get_nodes()
    local out = {}
    for _, n in ipairs(ids) do
      out[#out + 1] = n:get_id()
    end
    ids = out
  end
  if not ids or #ids == 0 then
    return
  end
  local target = which == 'first' and ids[1] or ids[#ids]
  pcall(renderer.focus_node, state, target)
end

-- 'w' 로 트리 폭을 넓혔다 줄인다 (RelationView 패널의 'w' 와 같은 손버릇).
--
-- 단계는 화면 폭의 %다. 마지막 단계에서 한 번 더 누르면 처음 폭으로
-- 돌아온다. 처음 폭은 '이 창에서 처음 w 를 누른 그때의 폭'이라,
-- g:neo_tree_window_width 를 바꿔도 따로 맞출 것이 없다.
--
--   let g:neotree_wide_steps = [25, 40]   " 기본
--   let g:neotree_wide_steps = [30]       " 한 단계만
--   let g:neotree_wide_steps = [20, 35, 50]
--   let g:neotree_wide_steps = []         " 이 기능을 쓰지 않는다
--
-- 다른 곁창(aerial, RelationView 패널, 개요 막대 ...)은 건드리지 않는다:
-- 넓히기 전에 폭을 적어 두었다가 그대로 되돌려 놓는다. 늘어난 만큼은
-- EDIT 창이 낸다. RelationView 의 'w' 가 지키는 규칙과 같다.
--
-- neo-tree 기본에서 'w' 는 open_with_window_picker 다. 이 설정에는 창
-- 고르개를 쓰지 않으므로(파일은 늘 직전 EDIT 창에 연다) 그 자리를 넘겨받는다.

local wide = {}   -- winid -> { base = 처음 폭, step = 지금 몇 번째 }

local function wide_steps()
  local v = vim.g.neotree_wide_steps
  if v == nil then
    return { 25, 40 }
  end
  if type(v) == 'number' then
    v = { v }
  end
  if type(v) ~= 'table' then
    return {}
  end
  local out = {}
  for _, p in ipairs(v) do
    local n = tonumber(p)
    -- 100% 를 받으면 EDIT 창이 0칸이 된다. 화면을 다 덮는 것은 막는다.
    if n and n > 0 and n < 100 then
      out[#out + 1] = n
    end
  end
  return out
end

-- 폭이 고정된 세로 곁창들(자기 자신과 부동 창은 뺀다)의 지금 폭
local function other_sides(me)
  local out = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= me and vim.api.nvim_win_get_config(w).relative == ''
        and vim.wo[w].winfixwidth then
      out[#out + 1] = { win = w, width = vim.api.nvim_win_get_width(w) }
    end
  end
  return out
end

function _G.neotree_toggle_wide()
  local api = vim.api
  local win = api.nvim_get_current_win()
  local steps = wide_steps()
  if #steps == 0 then
    return
  end
  local st = wide[win]
  if not st then
    st = { base = api.nvim_win_get_width(win), step = 0 }
    wide[win] = st
  end
  st.step = st.step + 1
  if st.step > #steps then
    st.step = 0 -- 한 바퀴 돌았다: 처음 폭으로
  end
  local want = st.step == 0 and st.base
      or math.floor(vim.o.columns * steps[st.step] / 100)
  if want < 1 then
    want = 1
  end
  local others = other_sides(win)
  pcall(api.nvim_win_set_width, win, want)
  -- 내 폭을 바꾸면 nvim 이 이웃에서 칸을 가져온다. 곁창이 같이 줄었으면
  -- 되돌린다 - 그 몫은 EDIT 창이 낸다.
  for _, o in ipairs(others) do
    if api.nvim_win_is_valid(o.win)
        and api.nvim_win_get_width(o.win) ~= o.width then
      pcall(api.nvim_win_set_width, o.win, o.width)
    end
  end
end

-- 창이 닫히면 기억도 버린다 (winid 는 돌려 쓰인다)
vim.api.nvim_create_autocmd('WinClosed', {
  group = vim.api.nvim_create_augroup('NeoTreeWide', { clear = true }),
  callback = function(a)
    wide[tonumber(a.match)] = nil
  end,
})
