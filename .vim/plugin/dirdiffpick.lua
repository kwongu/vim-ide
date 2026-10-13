-- dirdiffpick.lua - neo-tree 에서 두 곳을 골라 비교한다 (Space 두 번, Tab·\d 도 같다)
--
-- 트리에서 비교할 첫 번째 디렉터리(또는 파일) 위에서 Space 를 누르면 그 줄 끝에 [A] 가
-- 붙고, 두 번째 위에서 Space 를 누르면 [B] 로 삼아 곧바로 비교 창을 띄운다: 디렉터리
-- 둘이면 DirDiff(나란한 트리, dirdiffview.lua), 파일 둘이면 DirDiff 의 비교 탭(보통 짝과 같은
-- 창 - 색·창 머리·개요 막대·\d·복사 키·Ctrl+Z·q 모두. 이름·디렉터리가 달라도 된다 -
-- dirdiffview.lua 의 cmp.open_files). [A] 를 고른 뒤 같은 줄에서 다시 Space 는 취소. 트리가 달라도
-- 된다(F9 트리에서 고르고 RelationView 트리에서 비교).
-- 파일 둘의 비교 탭이 어디에 붙나는 [B] 를 누른 곳이 정한다: DirDiff 의 비교 트리면 그 세션의 탭으로
-- (q 는 그 트리의 줄로), neo-tree 면 혼자 선 비교 탭 (q 는 [B] 를 누른 창으로).
-- 예전의 맨 vimdiff(새 탭에서 diffsplit)는 g:vimide_dirdiff_pick_vimdiff = 1 이면 (g:vimide_dirdiff_view = 0 -
-- 디렉터리 둘도 DirDiff.vim 의 목록일 때, dirdiffview.lua 가 없을 때도 그것).
--
-- Space 는 neo-tree 기본의 toggle_node(폴더 펼치기/접기)였다 - 폴더는 Enter·o·더블클릭으로 펼치고
-- 접는다 (C 는 접기, O / X 는 아래 모두). Tab 은 select(여러 줄 골라 두기)였다 - vim-ide 는 그것을
-- 쓰지 않고, 여러 줄은 V 로 골라도 된다. Tab 도 그대로 고른다 (예전 손버릇). '=' 가 아닌 것은 트리의 =
-- 가 이미 색인 목록 정보(projectfiles_neotree.lua)라서다. neo-tree 매핑은 .vimrc 의 neo-tree
-- window.mappings ['<space>'] / ['<Tab>'] / ['<leader>d'] 에 있다.
--
-- DirDiff 의 비교 트리(dirdiffview.lua)의 Space 도 같은 [A] 를 쓴다 (_G.vimide_dirdiff_pick_path - 거기서 Tab 은
-- A 쪽 / B 쪽 바꾸기라 Space 만):
-- 비교 트리에서 [A], 다른 비교 탭이나 neo-tree 에서 [B] 도 된다. [A] 는 하나다. 비교 트리는 고른
-- 곳(세션·줄·쪽 - ctx)도 넘긴다: [A] 의 것은 여기 들고 있다가 [B] 때 같이 돌려준다.

if vim.g.loaded_vimide_dirdiffpick then
  return
end
vim.g.loaded_vimide_dirdiffpick = 1

local levels = vim.log.levels
local api = vim.api
local first = nil -- { path = ..., kind = 'dir' | 'file', real = 링크를 푼 경로, ctx = 고른 곳(비교 트리) }
local ns = api.nvim_create_namespace('vimide_dirdiff_pick')

api.nvim_set_hl(0, 'VimIdeDirDiffPickA', { link = 'Search', default = true })
api.nvim_create_autocmd('ColorScheme', {
  group = api.nvim_create_augroup('VimIdeDirDiffPick', { clear = true }),
  callback = function()
    api.nvim_set_hl(0, 'VimIdeDirDiffPickA', { link = 'Search', default = true })
  end,
})

-- 고른 [A] 를 트리 줄 끝에 보인다. 그릴 때마다(decoration provider) 그 창의 트리에서
-- [A] 노드의 줄을 찾아 단다 - 버퍼에 표시를 박아 두면, neo-tree 가 접기·펼치기·git 표시
-- 갱신 때 줄을 통째로 갈아 끼우면서 (그린 뒤 알림 AFTER_RENDER 도 없이) 표시가 다른 줄로
-- 밀렸다. 그 노드가 펼쳐져 보일 때만 (get_node(id) 가 줄 번호를 준다). neo-tree 모듈은
-- 부르지 않고 이미 불린 것만 본다
local function state_of(buf)
  local mgr = package.loaded['neo-tree.sources.manager']
  if not mgr then
    return nil
  end
  for _, st in ipairs(mgr._get_all_states()) do
    if st.bufnr == buf and st.tree then
      return st
    end
  end
end

-- 표시를 어디에 다나. 줄이 창 끝까지 차는 일이 흔하다 - neo-tree 는 오른쪽에 붙이는 것
-- (크기·날짜 열, git 표시)이 있으면 줄을 창 너비까지 채우고, 긴 이름은 창 끝에서 자른다.
-- 그런 줄에 줄 끝(eol) 표시를 달면 창 밖이라 보이지 않았다 (RelationView 트리, 깊은
-- 커널 경로, 루트 줄)
--   이름 바로 뒤가 빈칸이면       이름 뒤에 겹쳐 쓴다
--   줄 끝 뒤에 자리가 있으면      줄 끝에 (nvim 이 한 칸 띄워 단다)
--   아니면                        창 오른쪽 끝에 겹쳐 쓴다 (잘린 이름의 꼬리를 덮는다)
local function place(win, line, name)
  local _, e = line:find(name or '\0', 1, true)
  if e and line:sub(e + 1, e + 5) == '     ' then
    return e, { virt_text_pos = 'overlay' }, ' [A]'
  end
  local info = vim.fn.getwininfo(win)[1] or {}
  local width = api.nvim_win_get_width(win) - (info.textoff or 0)
  if vim.fn.strdisplaywidth(line) + 4 <= width then
    return 0, { virt_text_pos = 'eol' }, '[A]'
  end
  return 0, { virt_text_pos = 'overlay', virt_text_win_col = math.max(0, width - 4) }, ' [A]'
end

api.nvim_set_decoration_provider(ns, {
  on_win = function(_, win, buf, top, bot)
    if not first or vim.bo[buf].filetype ~= 'neo-tree' then
      return false
    end
    pcall(function()
      local node, lnum = state_of(buf).tree:get_node(first.path)
      if not (lnum and lnum - 1 >= top and lnum - 1 <= bot) then
        return
      end
      local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
      local col, opts, text = place(win, line, node.name)
      opts.virt_text = { { text, 'VimIdeDirDiffPickA' } }
      opts.hl_mode = 'combine'
      opts.ephemeral = true
      api.nvim_buf_set_extmark(buf, ns, lnum - 1, col, opts)
    end)
    return false
  end,
})

-- 고른 것이 바뀌면 트리 창들을 다시 그리게 한다 (바뀌지 않은 창은 다시 그리지 않으므로).
-- DirDiff 의 비교 트리도 - 거기서는 dirdiffview.lua 가 [A] 를 단다
local TREE_FT = { ['neo-tree'] = true, vimidedirdiff = true }
local function mark_all()
  for _, w in ipairs(api.nvim_list_wins()) do
    local b = api.nvim_win_get_buf(w)
    if TREE_FT[vim.bo[b].filetype] then
      if not pcall(api.nvim__redraw, { win = w, valid = false }) then
        vim.cmd('redraw!')
        return
      end
    end
  end
end

local function say(msg, level)
  (_G.vimide_notify or vim.notify)('비교: ' .. msg, level or levels.INFO)
end

-- 알림에 쓸 이름: 줄바꿈 같은 제어 문자는 ^@ 로 (그대로 두면 알림이 두 줄이 되어 Press ENTER 가
-- 떴다)
local function short(p)
  return vim.fn.strtrans(vim.fn.fnamemodify(p, ':~'))
end

local function key()
  return 'Space'
end

local function kind_name(kind)
  return kind == 'dir' and '디렉터리' or '파일'
end

-- 조사가 붙은 이름 ('파일' 은 받침이 있다)
local JOSA = {
  dir = { topic = '디렉터리는', with = '디렉터리와', subj = '디렉터리가' },
  file = { topic = '파일은', with = '파일과', subj = '파일이' },
}

-- 트리 창에서 :tabnew 하면 새 창이 트리의 창 옵션을 물려받고, neo-tree 가 그 창을
-- 제 것으로 알고 도로 가져간다 (dirdifftab.vim 과 같은 사정). EDIT 창으로 옮겨서
-- 열고, 그런 창이 없으면 새 창의 창 옵션을 전역값으로 되돌린다.
local PLAIN = { 'winhighlight', 'winfixwidth', 'winfixheight', 'number', 'relativenumber',
  'signcolumn', 'foldcolumn', 'cursorline', 'list', 'wrap', 'statuscolumn', 'winbar' }

-- cmd: Ex 줄, 또는 이름을 인자로 넘길 nvim_cmd 표 (vim.cmd 는 둘 다 받는다)
local function tab_from_edit(cmd)
  local w = _G.vimide_edit_slot and _G.vimide_edit_slot()
  local moved = false
  if w and w ~= 0 and vim.api.nvim_win_is_valid(w) then
    vim.api.nvim_set_current_win(w)
    moved = true
  end
  vim.cmd(cmd)
  if not moved then
    for _, o in ipairs(PLAIN) do
      pcall(vim.cmd, 'setlocal ' .. o .. '<')
    end
  end
end

local function exists(kind, path)
  if kind == 'dir' then
    return vim.fn.isdirectory(path) == 1
  end
  return vim.fn.filereadable(path) == 1
end

-- 같은 것인가: 경로 그대로, 아니면 링크를 푼 것으로. DirDiff 의 비교 트리는 뿌리의 링크를
-- 풀어 둔다 (macOS 의 /tmp -> /private/tmp) - neo-tree 에서 고른 [A] 를 비교 트리의 같은 줄에서
-- 취소하려면 푼 경로로 견주어야 한다
local function same_path(p)
  if first.path == p then
    return true
  end
  local r = (vim.uv or vim.loop).fs_realpath(p)
  return r ~= nil and r == first.real
end

-- 지금 [A] (없으면 nil). dirdiffview.lua 가 비교 트리에 [A] 를 달 때 본다
function _G.vimide_dirdiff_picked()
  return first
end

-- [A] 를 고른 비교 트리의 뿌리가 바뀌었다 (dirdiffview.lua 의 경로 바꾸기): 고른 곳(ctx - 옛 트리의 줄)만 버린다 -
-- 경로는 디스크에 그대로라 [B] 와 견줄 수 있다
function _G.vimide_dirdiff_pick_forget(tab)
  if first and first.ctx and first.ctx.tab == tab then
    first.ctx = nil
  end
end

-- [A] 를 고른 비교 트리가 양측을 바꾸었다 (dirdiffview.lua 의 양측 교환 - A·B 뿌리를 바꾼다): 경로와 줄은 그대로고
-- 그 파일이 이제 다른 쪽에 있다 - 고른 쪽만 뒤집는다 ([B] 의 비교 탭이 q 로 돌아갈 [A] 줄의 쪽)
function _G.vimide_dirdiff_pick_swapped(tab)
  local c = first and first.ctx
  if c and c.tab == tab and (c.side == 'a' or c.side == 'b') then
    c.side = c.side == 'a' and 'b' or 'a'
  end
end

-- p 의 위 디렉터리 쪽 링크만 푼다 (있는 데까지 - 이름을 바꾼 뒤라 옛 경로의 위가 없을 수 있다). 마지막 이름은 그대로:
-- [A] 가 링크면 그 링크 자신이다 (first.real 은 가리키는 것이라, 그것으로 견주었더니 링크가 가리키는 파일의 이름을
-- 바꾸면 [A] 가 링크에서 그 파일로 옮겨 갔다)
local function real_dir(p)
  local uv = vim.uv or vim.loop
  local rest, cur = {}, p
  while true do
    local dir, name = cur:match('^(.*)/([^/]+)$')
    if not dir then
      return p
    end
    table.insert(rest, 1, name)
    local r = uv.fs_realpath(dir == '' and '/' or dir)
    if r then
      return (r:gsub('/$', '')) .. '/' .. table.concat(rest, '/')
    end
    cur = dir
  end
end

-- [A] 나 그 위 디렉터리의 이름이 바뀌었다 (dirdiffview.lua 의 트리 r, old -> new 절대 경로): [A] 를 새 경로로. 고른
-- 곳(옛 줄)은 버린다. 그대로 두면 [B] 에서 '먼저 고른 것이 없어져 버렸습니다' 로 [A] 가 버려졌다.
-- new 가 nil 이면 지웠다 (트리의 d): [A] 를 버린다. old 는 뿌리를 푼 경로(/private/tmp)라 [A] 는 경로 그대로, 아니면
-- 위 디렉터리를 푼 것으로 견준다 (neo-tree 에서 /tmp 로 골랐다)
function _G.vimide_dirdiff_pick_moved(old, new)
  if not first then
    return
  end
  local function under(p)
    return p == old or p:sub(1, #old + 1) == old .. '/'
  end
  local p = first.path
  if not under(p) then
    p = real_dir(p)
  end
  if not under(p) then
    -- [A] 는 그대로지만 링크가 가리키던 것이 옮겨졌을 수 있다
    first.real = (vim.uv or vim.loop).fs_realpath(first.path)
    return
  end
  if new then
    first.path = new .. p:sub(#old + 1)
    first.real = (vim.uv or vim.loop).fs_realpath(first.path)
    first.ctx = nil
  else
    first = nil
  end
  mark_all()
end

-- path 를 [A] 로, 또는 [A] 와 비교 ([B]). neo-tree 의 Space·Tab 과 DirDiff 비교 트리의 Space 가 같이 쓴다.
-- ctx: 비교 트리에서 골랐으면 { tab = 세션의 탭, rel = 줄, side = 'a' | 'b' } (neo-tree 는 nil)
function _G.vimide_dirdiff_pick_path(path, kind, ctx)
  -- [A] 줄에서 다시 누르면 취소. 디스크에서 없어졌어도 - 파일 감시를 꺼 두어
  -- (use_libuv_file_watcher) 밖에서 지운 줄은 R 로 새로 고칠 때까지 트리에 남는다
  if first and same_path(path) then
    first = nil
    mark_all()
    return say('고른 것을 취소했습니다')
  end
  -- buffers 소스의 이름 없는 버퍼는 path 가 '[No Name]' 이다
  if not exists(kind, path) then
    return say('디스크에 없는 ' .. kind_name(kind) .. '입니다: ' .. short(path), levels.WARN)
  end
  -- 먼저 고른 것이 그 사이 없어졌으면 버리고 이것을 [A] 로
  if first and not exists(first.kind, first.path) then
    say('먼저 고른 ' .. JOSA[first.kind].subj .. ' 없어져 버렸습니다: ' .. short(first.path), levels.WARN)
    first = nil
    mark_all()
  end
  if not first then
    first = { path = path, kind = kind, real = (vim.uv or vim.loop).fs_realpath(path), ctx = ctx }
    mark_all()
    return say(('[A] %s: %s - 비교할 곳에서 %s ([B]). 같은 줄에서 다시 누르면 취소')
      :format(kind_name(kind), short(path), key()))
  end
  if first.kind ~= kind then
    return say(('%s %s 비교합니다 - [A]: %s (같은 줄에서 다시 누르면 취소)')
      :format(JOSA[first.kind].topic, JOSA[first.kind].with, short(first.path)), levels.WARN)
  end
  local a, actx = first.path, first.ctx
  first = nil
  mark_all()
  if kind == 'dir' then
    -- :DirDiff 를 거치지 않고 바로 부른다 (VimIdeDirDiff 가 EDIT 창에서 새 탭을 연다)
    if _G.vimide_dirdiff_open and (tonumber(vim.g.vimide_dirdiff_view) or 1) ~= 0 then
      _G.vimide_dirdiff_open(a, path)
    elseif vim.fn.exists('*VimIdeDirDiff') == 1 then
      vim.fn.VimIdeDirDiff(a, path)
    else
      say('dirdifftab.vim 이 없습니다', levels.WARN)
    end
  elseif _G.vimide_dirdiff_open_files and (tonumber(vim.g.vimide_dirdiff_pick_vimdiff) or 0) == 0
      and (tonumber(vim.g.vimide_dirdiff_view) or 1) ~= 0 then
    -- 파일 둘: DirDiff 의 비교 탭 (dirdiffview.lua). 맨 vimdiff 는 비교 탭이 아니라 bc 색·창 머리·\d·
    -- 복사 키·q·,r ,e 가 없었다 (사용자 보고). g:vimide_dirdiff_view = 0 (나란한 트리 대신 DirDiff.vim 의
    -- 목록)이면 위의 디렉터리 둘처럼 이것도 예전 것으로 - 디렉터리는 예전 목록인데 파일만 새 비교 탭이면 어긋난다
    _G.vimide_dirdiff_open_files(a, path, { a = actx, b = ctx })
  else
    -- 예전 그대로의 vimdiff (g:vimide_dirdiff_pick_vimdiff = 1, g:vimide_dirdiff_view = 0, dirdiffview.lua 가
    -- 없을 때).
    -- 이름은 Ex 줄로 만들지 않고 인자로 (dirdiffview.lua 의 show_file 과 같은 까닭): 이름에
    -- 줄바꿈이 있으면 fnameescape 로도 줄이 갈라져 없는 'x\' 를 열고 나머지를 명령으로 돌렸다
    tab_from_edit({ cmd = 'tabnew', args = { a }, magic = { file = false } })
    vim.cmd.diffsplit({ args = { path }, magic = { file = false }, mods = { split = 'belowright', vertical = true } })
    -- 창 머리(winbar)는 걷는다: nvim 은 버퍼를 새 창에 띄울 때 그 버퍼가 떠 있는(떠 있던) 창의 옵션을
    -- 입힌다 - DirDiff 의 비교 트리에서 Space/Space 로 연 vimdiff 는 DirDiff 편집 창의 머리(' B: …')를
    -- 받아 [A]/[B] 와 거꾸로 보였다. diffsplit 의 창도 따로 받으므로 새 탭의 창 모두에서
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      pcall(api.nvim_win_call, w, function()
        vim.cmd('setlocal winbar<')
      end)
    end
  end
end

function _G.vimide_dirdiff_pick(state)
  local ok, node = pcall(function()
    return state.tree:get_node()
  end)
  local path = ok and node and node.path
  local t = ok and node and node.type
  if not path or (t ~= 'directory' and t ~= 'file') then
    return say('디렉터리나 파일 줄에서 누르세요', levels.WARN)
  end
  _G.vimide_dirdiff_pick_path(path, t == 'directory' and 'dir' or 'file')
end
