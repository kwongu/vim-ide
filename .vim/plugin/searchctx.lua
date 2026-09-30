-- searchctx.lua - 곁창에서 찾을 때 '이 창이 가리키는 파일'
--
-- <C-g>(grep)와 <C-/>(룩업 레퍼런스)는 지금 파일을 기준으로 찾는다: grep 은 그
-- 파일이 있는 디렉터리 이하에서, 룩업은 그 파일이 든 색인에서. 편집 창이면 지금
-- 버퍼가 그 파일이지만, quickfix·RelationView 목록·context view·aerial 같은 곁창의
-- 버퍼는 파일이 아니다. 예전에는 <C-g> 가 곁창을 아예 거절했고(목록의 글자이지
-- 소스의 심볼이 아니라서), <C-/> 는 현재 디렉터리의 색인으로 떨어졌다 - 다른
-- 디렉터리에서 연 파일이면 엉뚱한 색인을 뒤졌다.
--
-- 곁창마다 가리키는 파일을 이렇게 찾는다:
--   quickfix / location list   커서 줄 항목의 파일
--   RelationView 목록           커서 줄 항목의 파일 (relationview_path_at)
--   context view (미리보기)     보여 주는 진짜 파일 (relationview_ctx_path)
--   aerial                      심볼 목록의 원본 버퍼
--   neo-tree                    커서 줄 노드 (디렉터리면 그 디렉터리)
--   DirDiff 트리                커서 줄의 A 쪽(없으면 B 쪽) 경로
--   그 밖 / 못 찾으면           편집 창(EDIT) 자리의 파일
--
--   _G.vimide_search_file()    그 파일의 절대 경로 (없으면 nil)
--   _G.vimide_search_origin()  찾은 뒤 '돌아갈 편집 창' - 편집 창이면 그 창,
--                              곁창이면 EDIT 자리 (없으면 0). relationview_grep 의
--                              origin 으로 넘긴다: 곁창을 주면 미리보기의 <C-t>
--                              스택에 그 곁창 버퍼 이름이 파일처럼 적힌다

if vim.g.loaded_vimide_searchctx then
  return
end
vim.g.loaded_vimide_searchctx = 1

local api = vim.api

local function real_file(buf)
  if not (buf and api.nvim_buf_is_valid(buf)) or vim.bo[buf].buftype ~= '' then
    return nil
  end
  local n = api.nvim_buf_get_name(buf)
  return n ~= '' and n or nil
end

local function edit_slot()
  local ok, w = pcall(function()
    return _G.vimide_edit_slot and _G.vimide_edit_slot()
  end)
  if ok and w and w ~= 0 and api.nvim_win_is_valid(w) then
    return w
  end
  return nil
end

local function qf_file(win)
  local info = vim.fn.getwininfo(win)[1] or {}
  local lnum = api.nvim_win_get_cursor(win)[1]
  local what = { idx = lnum, items = 0 }
  local list = info.loclist == 1 and vim.fn.getloclist(win, what) or vim.fn.getqflist(what)
  local it = list and list.items and list.items[1]
  if it and it.bufnr and it.bufnr > 0 then
    local n = api.nvim_buf_get_name(it.bufnr)
    return n ~= '' and n or nil
  end
end

-- neo-tree 창의 state. position=current(RelationView 트리)에서는 get_state_for_window 가
-- nil 을 주는 일이 있어 전체 목록에서 버퍼로 찾는다
local function neotree_state(win, buf)
  local ok, m = pcall(require, 'neo-tree.sources.manager')
  if not ok then
    return nil
  end
  local ok1, st = pcall(m.get_state_for_window, win)
  if ok1 and st and st.tree and st.bufnr == buf then
    return st
  end
  local ok2, all = pcall(m._get_all_states)
  for _, x in ipairs(ok2 and all or {}) do
    if x.bufnr == buf and x.tree then
      return x
    end
  end
end

local function neotree_node(win, buf)
  local st = neotree_state(win, buf)
  local node
  pcall(function()
    node = st.tree:get_node(api.nvim_win_get_cursor(win)[1])
  end)
  local p = node and node.path
  -- 진짜 파일·디렉터리만 (안내 줄, buffers 소스의 터미널·[No Name] 줄은 빼고 - treesearch.lua)
  if type(p) ~= 'string' or p:sub(1, 1) ~= '/'
      or (node.type ~= 'file' and node.type ~= 'directory' and node.type ~= 'link') then
    return nil
  end
  -- 디렉터리면 끝에 '/' - 찾을 곳(':h')이 그 디렉터리가 되게
  return node.type == 'directory' and (p:gsub('/+$', '') .. '/') or p
end

-- 곁창이 가리키는 파일. 알 수 없으면 nil
local function side_file(win, buf)
  local bt, ft = vim.bo[buf].buftype, vim.bo[buf].filetype
  if bt == 'quickfix' then
    return qf_file(win)
  end
  if _G.relationview_bufnr and _G.relationview_path_at then
    local ok, pb = pcall(_G.relationview_bufnr)
    if ok and pb == buf then
      local ok2, p = pcall(_G.relationview_path_at, api.nvim_win_get_cursor(win)[1])
      return ok2 and p or nil
    end
  end
  if api.nvim_buf_get_name(buf):match('RelationView%-Context$') and _G.relationview_ctx_path then
    local ok, p = pcall(_G.relationview_ctx_path)
    return ok and p or nil
  end
  if ft == 'aerial' then
    local ok, src = pcall(api.nvim_buf_get_var, buf, 'source_buffer')
    return ok and real_file(src) or nil
  end
  if ft == 'neo-tree' then
    return neotree_node(win, buf)
  end
  if ft == 'vimidedirdiff' and _G.vimide_dirdiff_path_at then
    local ok, p = pcall(_G.vimide_dirdiff_path_at)
    return ok and p or nil
  end
  return nil
end

function _G.vimide_search_file()
  local win = api.nvim_get_current_win()
  local buf = api.nvim_get_current_buf()
  local f = real_file(buf) or side_file(win, buf)
  if f then
    return vim.fn.fnamemodify(f, ':p')
  end
  local w = edit_slot()
  f = w and real_file(api.nvim_win_get_buf(w))
  return f and vim.fn.fnamemodify(f, ':p') or nil
end

-- 낱말 글자: 'iskeyword' 이면서 아이콘·기호가 아닌 것. 사용자 정의 영역(Nerd Font 아이콘
-- , 󰊕), 화살표, 선 긋기·도형(│ └ ◆)은 vim 에게는 낱말 글자(0xff 위는 다 그렇다)지만
-- 찾을 말이 아니다. 한글은 낱말이다
local WORDCH = [[\%(\k\&[^\ue000-\uf8ff\u2190-\u21ff\u2500-\u25ff\U000f0000-\U0010ffff]\)]]

-- 곁창 가운데 '목록' 인 곳에서 찾을 말의 처음 값 (quickfix, RelationView 목록, aerial,
-- neo-tree, DirDiff 트리). 진짜 코드를 보여 주는 곳(context view)과 편집 창은 nil -
-- 그때는 .vimrc 의 예전 규칙 그대로 (<C-/> 는 커서가 낱말 위일 때만, 빈칸이면 비움)
--   커서가 낱말 글자 위면 그 낱말, 아니면(아이콘·기호·빈칸) 커서 뒤 첫 낱말, 없으면 그
--   줄의 첫 낱말. quickfix 에서 커서가 '파일|줄|' 머리에 있으면 본문의 첫 낱말
function _G.vimide_search_word()
  local buf = api.nvim_get_current_buf()
  if vim.bo[buf].buftype == '' or api.nvim_buf_get_name(buf):match('RelationView%-Context$') then
    return nil
  end
  local line = api.nvim_get_current_line()
  local col = api.nvim_win_get_cursor(0)[2]
  if vim.bo[buf].buftype == 'quickfix' then
    local _, e = line:find('^[^|]*|[^|]*|')
    if e and col < e then
      local w = vim.fn.matchstr(line, WORDCH .. [[\+]], e)
      if w ~= '' then
        return w
      end
    end
  end
  local ch = vim.fn.matchstr(line, [[\%]] .. (col + 1) .. [[c.]])
  if ch ~= '' and vim.fn.match(ch, '^' .. WORDCH .. '$') >= 0 then
    return vim.fn.expand('<cword>')
  end
  local w = vim.fn.matchstr(line, WORDCH .. [[\+]], col)
  if w == '' then
    w = vim.fn.matchstr(line, WORDCH .. [[\+]])
  end
  return w
end

function _G.vimide_search_origin()
  local win = api.nvim_get_current_win()
  if _G.vimide_is_edit_win and _G.vimide_is_edit_win(win) then
    return win
  end
  return edit_slot() or 0
end
