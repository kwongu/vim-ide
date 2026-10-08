-- gitviewkeys.lua - Diffview 패널의 'w' (폭 넓히기) 와, Neogit 커밋 창·diff 창의
-- <C-n>/<C-p> (다음/이전 헝크)
--
-- 'w' 는 .vimrc 의 diffview 설정(keymaps 의 file_panel / file_history_panel)이
-- 이 파일의 함수에 건다. <C-n>/<C-p> 는 이 파일이 FileType 으로 직접 건다 -
-- Neogit 의 mappings 설정은 commit_view 에 정해진 이름 둘(OpenFileInWorktree,
-- OpenCommitLinkInBrowser)만 받고, diff 창(NeogitDiffView)에는 설정 자리가
-- 아예 없어서 함수를 걸 데가 없다.
--
-- 전역 함수
--   _G.vimide_diffview_wide()     Diffview 패널에서 'w'
--   _G.vimide_neogit_hunk(dir)    Neogit 창에서 <C-n> (dir=1) / <C-p> (dir=-1)
--
-- nvim 전용이다. 진짜 vim 8.1 에는 diffview·Neogit 이 없다.

if vim.fn.has('nvim') ~= 1 or vim.g.loaded_vimide_gitviewkeys then
  return
end
vim.g.loaded_vimide_gitviewkeys = 1

local api = vim.api

-- ---------------------------------------------------------------------------
-- Diffview 패널의 'w'
-- ---------------------------------------------------------------------------
-- F9 neo-tree 와 RelationView 패널의 'w' 와 같은 손버릇이다. 누를 때마다 한
-- 단계씩 넓히고, 마지막 단계에서 한 번 더 누르면 처음 크기로 돌아온다. 단계는
-- 화면의 %.
--
--   파일 패널 (왼쪽, \v / :DiffviewOpen)       폭    g:diffview_wide_steps         [25, 40]
--   파일 이력 패널 (아래, :DiffviewFileHistory) 높이  g:diffview_wide_height_steps  [50, 75]
--
-- 이력 패널은 diff 창 밑에 가로로 눕는다(diffview 기본). 거기서 늘릴 것은 높이다 -
-- RelationView 를 아래 배치로 쓸 때 'w' 가 높이를 다루는 것과 같다. 단계도 그쪽과
-- 같게 둔다: 기본 16줄은 50줄 화면의 32% 라 25% 단계는 오히려 줄이기가 된다.
--
-- 지금 크기보다 크지 않은 단계는 건너뛴다. 'w' 는 넓히기만 한다 - 좁은 화면
-- (120칸)에서는 25% 가 30칸이라 기본 35칸보다 좁다. 손으로(:vertical resize)
-- 넓혀 둔 패널도 지금 실제 크기와 견준다 - 앞 단계의 크기와만 견주면 120칸으로
-- 늘려 둔 패널을 다음 단계 80칸으로 줄였다(실측). 넓힐 단계가 하나도 없으면
-- 아무 일도 없고, 넓혀 둔 뒤라면 처음 크기로 돌아온다.
--
-- diff 창마다 최소 20칸(높이는 5줄)은 남긴다 (RelationView 의 'w' 가 편집 영역에
-- 남기는 값과 같다). 미리 계산하지 않고 넓혀 본 뒤 diff 창을 직접 재서, 모자라면
-- 그만큼 패널을 물린다 - RelationView 의 'w' 와 같은 방법이다. 예전에는 화면
-- 크기에서 20칸(5줄)을 뺀 값을 한도로 삼았는데, 그러면 탭줄·상태줄·명령줄과 같은
-- 탭의 다른 곁창을 셈하지 못한다 (실측: 200칸에 neo-tree 32칸과 RelationView 80칸이
-- 같이 있으면 둘째 'w' 에 diff 창이 2칸/2칸, 24줄 화면의 이력 패널은 첫 'w' 에
-- diff 창이 2줄). 창마다 재는 것은 diff 창이 둘셋 나란히 서기 때문이다 - 충돌
-- 파일(3-way)의 세 창이 저마다 7칸이면 합이 20칸이어도 못 읽는다. 물려서도
-- 넓어지지 않는 단계는 건너뛴 것으로 친다.
--
-- 늘고 준 만큼은 diff 창들만 똑같이 나눠 낸다 (diff 창마다 같은 칸 수 - 200칸
-- 화면에서 81/82 칸이 74/74 칸). 탭의 다른 창은 크기를 그대로 둔다 - 사용자가 나눈
-- 창(:vertical help, :vsplit, 터미널)이나 neo-tree·RelationView 기둥의 폭은 'w' 를
-- 몇 번 눌러도, 처음 크기로 돌아와도 그대로다. 돌아올 때 diff 창들은 처음 'w'
-- 앞의 폭으로 돌아간다 (그 사이에 창이 새로 생겼으면 - 충돌 파일로 옮겨 배치를
-- 새로 짰으면 - 돌려받는 칸을 똑같이 나눈다). 20칸이 안 되는 diff 창은 내지 않고
-- 돌려받는 칸을 먼저 받는다.
--   창 배치 나무(winlayout)에서 패널과 같은 줄에 선 형제들을 가른다: 패널, diff
--   창이 든 것, 그 밖의 것. 형제마다 바랄 크기를 정해 앞에서부터 차례로 맞추기를
--   다 맞을 때까지 되풀이한다 (winrestcmd 와 같은 방법). 한 번으로는 안 된다 - vim
--   은 크기를 바꾼 창의 뒤쪽에서 먼저 가져오고 돌려주는데, winfixheight 인 패널은
--   건너뛰어서 패널이 아래 끝에 있으면 다른 창이 내놓은 줄이 diff 창으로 되돌아갔다
--   (실측: 이력 패널을 \b 로 껐다 켜면 사용자가 연 창 밑으로 간다).
--   그냥 두면 nvim 은 패널 바로 옆 창 하나에서만 가져가 두 diff 창이 36/82 칸으로
--   어긋난다(실측 200칸). wincmd = 는 높이까지 펴서 diff 창 위에 10줄로 띄운
--   :help 가 23줄로 뭉개졌고, horizontal wincmd = 는 폭만 펴지만 탭의 모든 창을
--   펴서 30칸으로 둔 :vertical help 가 49칸, 돌아와서는 54칸이 되었다(둘 다 실측).
--   패널과 neo-tree·RelationView 기둥은 winfixwidth 라 비켜 갔을 뿐이다.
--   RelationView 의 'w' 가 wincmd = 를 쓰지 않는 것과 같은 까닭이다.
-- 이력 패널(높이)도 같은 방법이다. diff 창들은 패널 위 한 줄에 나란히 서 있어
-- 높이가 같이 줄고 늘고, 그 줄 밖의 창(아래 quickfix 같은 것)은 그대로다. 그 줄
-- 안에서 diff 창 위아래로 나눈 창도 높이를 지킨다 - 그 diff 창이 낸다. 그래서 그런
-- 창이 있으면 diff 창이 5줄에 먼저 닿아 덜 넓어진다. 예전에는 패널 높이만 바꿔서 vim
-- 이 패널 밑 창부터 가져갔다 - 아래에 둔 6줄 창이 'w' 마다 1줄, 22줄, 13줄로 오갔고
-- diff 창 위에 나눈 8줄 창은 5줄이 되었다 (실측). 고르게 펴는 일은 없다 - vertical
-- wincmd = 는 사용자가 나눈 창의 높이를 뭉갠다 (실측 8/21 줄이 10/10).
--
-- 넓힌 크기는 'w' 로 되돌리거나 view 가 닫힐 때까지 간다.
--   파일을 옮겨 다니거나(Tab, <C-n>), R 로 새로 고치거나, 탭을 오가거나, 화면
--   크기가 바뀌어도 diffview 는 패널을 건드리지 않는다(실측). winfixwidth 라
--   wincmd = 도 비켜 간다.
--   패널을 닫았다 다시 열 때는 다르다 - \b(toggle_files)로 껐다 켤 때, 2-way
--   파일과 충돌 파일(3-way) 사이를 옮겨 배치를 새로 짤 때. diffview 는 열 때마다
--   설정의 크기(win_config.width = 35)로 되돌려 놓는다(Panel:resize, 실측: 80칸이
--   충돌 파일로 옮기자 35칸). 그 크기는 패널이 그때그때 설정에서 읽어 온다
--   (Panel:get_config 가 config_producer 를 부른다). 그래서 넓혀 둔 동안은 그
--   패널 하나의 config_producer 만 '넓힌 크기를 돌려주는 함수'로 바꿔 끼운다.
--   다른 view(탭)의 패널과 diffview 의 전역 설정은 그대로다.
--   그 크기는 다시 열 때마다 지금 화면에 맞춘다. 200칸에서 넓힌 80칸을 110칸으로
--   줄어든 화면에 그대로 다시 열면 diff 창이 8/20칸으로 눌렸다(실측) - 화면에서
--   20칸을 뺀 값으로 깎고, diffview 가 배치를 다 짠 뒤에 위의 '재서 물리기'를 한
--   번 더 한다. 기억해 둔 크기 자체는 그대로라 화면이 다시 넓어지면 돌아온다.
--
-- view(탭)마다 따로 기억한다 - 탭 둘에 다른 폭을 두어도 된다. 기억은 패널
-- 객체에 매달아 두므로 view 가 닫히면 같이 사라지고, 다시 열면 기본 크기다.
-- 떠 있는(float) 패널 설정이면 손대지 않는다. diff 창 안의 'w' 는 vim 의 낱말
-- 이동 그대로다 (이 키는 패널 버퍼에만 걸린다).

-- 패널 -> { base = 처음 크기, size = 지금 단계의 크기 (물린 뒤의 실제 크기),
--           step = 몇 번째 단계, row = 높이를 다루는가,
--           producer = 원래 config_producer,
--           keep = 처음 'w' 앞의 diff 창 크기 { [그 묶음의 첫 diff 창] = 크기 } }
local wide = setmetatable({}, { __mode = 'k' })

local function pct_list(v, default)
  if v == nil then
    v = default
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
    -- 100% 면 diff 창이 0칸이 된다. 화면을 다 덮는 것은 막는다.
    if n and n > 0 and n < 100 then
      out[#out + 1] = n
    end
  end
  return out
end

local MIN_W, MIN_H = 20, 5 -- diff 창마다 남길 폭과 높이

local function panel_size(win, row)
  return row and api.nvim_win_get_height(win) or api.nvim_win_get_width(win)
end

local function win_set(win, row, n)
  if row then
    pcall(api.nvim_win_set_height, win, n)
  else
    pcall(api.nvim_win_set_width, win, n)
  end
end

-- 패널을 띄운 view 의 diff 창들 (지금 배치, 패널과 같은 탭)
local function diff_wins(panel, tab)
  local okl, lib = pcall(require, 'diffview.lib')
  for _, v in ipairs(okl and type(lib.views) == 'table' and lib.views or {}) do
    if v.panel == panel then
      local out = {}
      local ok, ws = pcall(function()
        return v.cur_layout.windows
      end)
      for _, w in ipairs(ok and type(ws) == 'table' and ws or {}) do
        local id = w.id
        if id and api.nvim_win_is_valid(id) and api.nvim_win_get_tabpage(id) == tab
            and api.nvim_win_get_config(id).relative == '' then
          out[#out + 1] = id
        end
      end
      return out
    end
  end
  return {}
end

-- ---- 창 배치 나무 (winlayout) ----
-- 패널과 같은 줄에 선 형제들. 폭이면 가로로 늘어선 줄(row), 높이면 세로로 쌓인
-- 줄(col)이다. 형제 하나는 창 하나이거나, 그 안에서 다시 나뉜 창 묶음이다
-- (diff 창 위에 :split 한 창은 그 diff 창과 한 묶음이라 폭을 같이 쓴다).

local function leaves(node, out)
  out = out or {}
  if node[1] == 'leaf' then
    out[#out + 1] = node[2]
  else
    for _, c in ipairs(node[2]) do
      leaves(c, out)
    end
  end
  return out
end

-- 묶음의 크기를 바꿀 때 잡을 창: 묶음을 끝에서 끝까지 덮는 창. 가로 줄의 형제는
-- 창이거나 세로로 쌓인 묶음이고, 그 묶음에 바로 든 창은 묶음과 폭이 같다 (높이는
-- 거꾸로). 그런 창이 없으면 nil - 그 형제는 남이 맞춰지면 저절로 맞는다.
local function handle(node)
  if node[1] == 'leaf' then
    return node[2]
  end
  for _, c in ipairs(node[2]) do
    if c[1] == 'leaf' then
      return c[2]
    end
  end
  return nil
end

local function extent(node, row)
  local h = handle(node)
  if h then
    return panel_size(h, row)
  end
  local lo, hi = math.huge, -math.huge
  for _, w in ipairs(leaves(node)) do
    local p = api.nvim_win_get_position(w)[row and 1 or 2]
    lo, hi = math.min(lo, p), math.max(hi, p + panel_size(w, row))
  end
  return hi - lo
end

-- 묶음 안에서 diff 창과 같은 방향으로 늘어선 다른 창 - 이력 패널이면 diff 창 위에
-- :split 한 창. 그 크기(높이)는 묶음의 크기에 매이지 않으므로 그대로 지킨다. 폭이면
-- diff 창 위아래로 쌓인 창은 diff 창과 폭을 같이 쓰므로(매여 있다) 여기 들지 않는다.
-- along: 위쪽 어디선가 재는 방향으로 늘어선 묶음을 지났나
local function kept_others(node, row, diff, along, out)
  out = out or {}
  if node[1] == 'leaf' then
    if along and not diff[node[2]] then
      out[#out + 1] = { win = node[2], size = panel_size(node[2], row) }
    end
    return out
  end
  local a = along or (node[1] == 'col') == row
  for _, c in ipairs(node[2]) do
    kept_others(c, row, diff, a, out)
  end
  return out
end

-- 묶음을 줄일 수 있는 가장 작은 크기. diff 창(과 거기 매인 창)은 winminwidth /
-- winminheight 까지, 지키는 다른 창(kept_others)은 지금 크기 그대로. 사이 경계 1칸.
local function min_size(node, row, diff, along)
  if node[1] == 'leaf' then
    if along and not diff[node[2]] then
      return panel_size(node[2], row)
    end
    return math.max(row and vim.o.winminheight or vim.o.winminwidth, 1)
  end
  local a = (node[1] == 'col') == row -- 안의 창들이 재는 방향으로 늘어섰나
  local sum, most = 0, 0
  for _, c in ipairs(node[2]) do
    local m = min_size(c, row, diff, along or a)
    sum, most = sum + m, math.max(most, m)
  end
  return a and sum + #node[2] - 1 or most
end

-- 패널과 같은 줄의 형제들: { node, kind = 'panel'|'diff'|'other', size, min,
-- key = 'diff' 면 그 묶음의 첫 diff 창 }. 패널이 그 줄에 바로 서 있지 않으면(패널을
-- 손으로 나눴다) nil.
local function siblings(panel, win, row)
  local tab = api.nvim_win_get_tabpage(win)
  local ok, tree = pcall(vim.fn.winlayout, api.nvim_tabpage_get_number(tab))
  if not ok or type(tree) ~= 'table' then
    return nil
  end
  local want = row and 'col' or 'row'
  local function find(node)
    if node[1] == 'leaf' then
      return nil
    end
    for _, c in ipairs(node[2]) do
      if c[1] == 'leaf' and c[2] == win then
        return node[1] == want and node or false
      end
      local r = find(c)
      if r ~= nil then
        return r
      end
    end
    return nil
  end
  local parent = find(tree)
  if not parent then
    return nil
  end
  local diff = {}
  for _, w in ipairs(diff_wins(panel, tab)) do
    diff[w] = true
  end
  local out = {}
  for _, c in ipairs(parent[2]) do
    local s = { node = c, size = extent(c, row), kind = 'other' }
    if c[1] == 'leaf' and c[2] == win then
      s.kind = 'panel'
    else
      for _, w in ipairs(leaves(c)) do
        if diff[w] and not s.key then
          s.kind, s.key = 'diff', w
        end
      end
    end
    if s.kind == 'diff' then
      s.min, s.inner = min_size(c, row, diff, false), kept_others(c, row, diff, false)
    end
    out[#out + 1] = s
  end
  return out
end

-- 지금 diff 묶음들의 크기 { [첫 diff 창] = 크기 } - 처음 'w' 앞에 적어 둔다
local function diff_sizes(panel, row)
  local win = panel.winid
  local out = {}
  api.nvim_win_call(win, function()
    for _, s in ipairs(siblings(panel, win, row) or {}) do
      if s.kind == 'diff' then
        out[s.key] = s.size
      end
    end
  end)
  return out
end

-- total 을 diff 묶음들에 나눈다. base 에서 시작해 남거나 모자라는 것을 똑같이
-- 더하고 빼되, 묶음마다 mins 밑으로는 내리지 않는다 - 이미 mins 보다 작은 묶음은
-- 내지 않고 mins 까지 먼저 받는다. 똑같이 나누고 남는 한 칸씩은 줄일 때는 큰
-- 묶음이, 늘릴 때는 작은 묶음이 맡는다 (81/82 칸에서 15칸을 내면 74/74).
local function spread(total, base, mins)
  local out, free = {}, {}
  for i = 1, #base do
    out[i], free[i] = math.max(base[i], mins[i]), base[i] > mins[i]
  end
  for _ = 1, #base + 1 do
    local sum = 0
    for i = 1, #out do
      sum = sum + out[i]
    end
    local diff = total - sum
    local idx = {}
    for i = 1, #out do
      if diff > 0 or free[i] then -- 늘리는 것은 어느 묶음이나 받는다
        idx[#idx + 1] = i
      end
    end
    if diff == 0 or #idx == 0 then
      break
    end
    local sign = diff < 0 and -1 or 1
    table.sort(idx, function(a, b)
      if out[a] ~= out[b] then
        return (out[a] - out[b]) * sign < 0
      end
      return a < b
    end)
    local q = math.floor(math.abs(diff) / #idx)
    local r = math.abs(diff) - q * #idx
    local low = false
    for j, i in ipairs(idx) do
      out[i] = out[i] + sign * (q + (j <= r and 1 or 0))
      if out[i] < mins[i] then
        out[i], free[i], low = mins[i], false, true
      end
    end
    if not low then
      break
    end
  end
  return out
end

-- 패널을 n 으로 하고, 늘고 준 만큼은 diff 묶음들만 똑같이 나눠 낸다. keep(처음
-- 'w' 앞의 크기)이 오면 diff 묶음들을 그 크기로 돌려놓는다 (그 사이 다른 창이
-- 바뀌어 남거나 모자라는 것만 똑같이). 다른 형제는 지금 크기 그대로다.
-- 폭은 diff 묶음마다 20칸(MIN_W)을 바닥으로 둔다 - 그만큼 줄 수 있을 때만, 그리고
-- 돌려놓을 때는 빼고 (처음부터 20칸이 안 되었으면 그대로 돌아간다). 패널은
-- diff 묶음들이 저마다 가장 작은 크기가 될 때까지만 는다 (더는 fit 이 물린다).
local function resize(panel, row, n, keep)
  local win = panel.winid
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  api.nvim_win_call(win, function()
    local sibs = siblings(panel, win, row)
    local p, lanes = nil, {}
    for _, s in ipairs(sibs or {}) do
      if s.kind == 'panel' then
        p = s
      elseif s.kind == 'diff' then
        lanes[#lanes + 1] = s
      end
    end
    if not p or #lanes == 0 then
      win_set(win, row, n) -- 알 수 없는 배치: 패널만 (vim 이 옆 창에서 가져온다)
      return
    end
    local pool, least = p.size, 0
    for _, s in ipairs(lanes) do
      pool, least = pool + s.size, least + s.min
    end
    n = math.max(1, math.min(n, pool - least))
    local base, mins, kept = {}, {}, 0
    for i, s in ipairs(lanes) do
      base[i], mins[i] = keep and keep[s.key], s.min
      kept = kept + (base[i] and 1 or 0)
    end
    local back = kept == #lanes and kept == vim.tbl_count(keep or {})
    if not back then
      for i, s in ipairs(lanes) do
        base[i] = s.size -- 돌려놓을 것이 없거나 창이 바뀌었다: 지금 크기에서
      end
    end
    if not row and not back then -- 돌려놓을 때는 처음 크기 그대로 (20칸이 안 되었어도)
      local floors, sum = {}, 0
      for i, s in ipairs(lanes) do
        floors[i] = math.max(s.min, MIN_W)
        sum = sum + floors[i]
      end
      if sum <= pool - n then
        mins = floors
      end
    end
    local sizes = spread(pool - n, base, mins)
    p.want = n
    for i, s in ipairs(lanes) do
      s.want = sizes[i]
    end
    -- 묶음 안의 다른 창은 묶음 크기가 맞은 뒤에 제 크기로 (같은 묶음 안의 diff
    -- 창과 주고받는다 - vim 은 아래 창부터 줄이고 늘리므로 diff 창 밑에 나눈 창이면
    -- 그것이 먼저 줄었다)
    local inner = {}
    for _, s in ipairs(lanes) do
      vim.list_extend(inner, s.inner)
    end
    for _ = 1, 4 do
      local off = false
      for _, s in ipairs(sibs) do
        local h = handle(s.node)
        local want = s.want or s.size
        if h and api.nvim_win_is_valid(h) and panel_size(h, row) ~= want then
          off = true
          win_set(h, row, want)
        end
      end
      for _, o in ipairs(inner) do
        if api.nvim_win_is_valid(o.win) and panel_size(o.win, row) ~= o.size then
          off = true
          win_set(o.win, row, o.size)
        end
      end
      if not off then
        break
      end
    end
  end)
end

-- diff 창이 쓸 수 없게 눌렸으면 그만큼 패널을 물린다 (처음 크기 밑으로는 안 간다).
-- 폭: 돌려받은 칸은 20칸이 안 되는 diff 창부터 채우므로(resize), 나란한 diff
-- 창들의 폭을 더해 '창 수 x 20칸'에 모자란 만큼 물린다. 가장 좁은 창 하나로
-- 셈하면 안 된다 - diff 창 하나만 1칸으로 눌려 있는 때가 있어서(27/1칸) 너무 많이
-- 물렸다.
-- 높이: diff 창들이 한 줄에 나란하므로 가장 작은 창에 모자란 줄만큼.
-- 한 번에 맞지 않을 때를 위해 세 번까지 잰다.
local function fit(panel, st)
  local win = panel.winid
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  local row = st.row
  api.nvim_win_call(win, function() -- 창 자리(position)는 지금 탭의 것이라야 맞다
    local wins = diff_wins(panel, api.nvim_win_get_tabpage(win))
    for _ = 1, 3 do
      local short = 0
      if row then
        local least = math.huge
        for _, w in ipairs(wins) do
          if api.nvim_win_is_valid(w) then
            least = math.min(least, api.nvim_win_get_height(w))
          end
        end
        short = least < math.huge and MIN_H - least or 0
      else
        -- 세로 줄(x 자리)마다 가장 좁은 창 - 위아래로 쌓인 창은 폭이 같다
        local lane = {}
        for _, w in ipairs(wins) do
          if api.nvim_win_is_valid(w) then
            local x = api.nvim_win_get_position(w)[2]
            lane[x] = math.min(lane[x] or math.huge, api.nvim_win_get_width(w))
          end
        end
        local n, sum = 0, 0
        for _, wd in pairs(lane) do
          n, sum = n + 1, sum + wd
        end
        short = MIN_W * n - sum
      end
      if short <= 0 then
        return
      end
      local cur = panel_size(win, row)
      local n = math.max(st.base, cur - short)
      if n >= cur then
        return
      end
      resize(panel, row, n)
    end
  end)
end

-- 넓혀 둔 동안 diffview 가 패널을 다시 열 때 읽을 설정. 원래 설정(전역 설정의
-- 표이거나 함수)을 그대로 두고 크기만 덮는다. 크기는 지금 화면에 맞춰 깎고,
-- diffview 가 배치를 다 짠 뒤에 diff 창을 재서 물린다 (fit).
local function producer_for(st, panel)
  local orig = st.producer
  return function()
    local c
    if vim.is_callable(orig) then
      c = orig()
    else
      c = vim.deepcopy(orig or {})
    end
    if type(c) ~= 'table' then
      c = {}
    end
    local total = st.row and vim.o.lines or vim.o.columns
    local n = math.min(st.size, math.max(st.base, total - (st.row and MIN_H or MIN_W)))
    if st.row then
      c.height = n
    else
      c.width = n
    end
    -- 한 번 열 때 두 번(open, resize) 불린다 - 재는 일은 한 번만 미뤄 둔다
    if not st.fitting then
      st.fitting = true
      vim.schedule(function()
        st.fitting = nil
        if wide[panel] == st then
          fit(panel, st)
        end
      end)
    end
    return c
  end
end

function _G.vimide_diffview_wide()
  local okl, lib = pcall(require, 'diffview.lib')
  local view = okl and lib.get_current_view() or nil
  local panel = view and view.panel
  local win = panel and panel.winid
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  local okc, conf = pcall(panel.get_config, panel)
  if not okc or type(conf) ~= 'table' or conf.type ~= 'split' then
    return
  end

  local st = wide[panel]
  local row
  if st then
    row = st.row
  else
    row = (panel.state and panel.state.form) == 'row'
  end
  local steps = row and pct_list(vim.g.diffview_wide_height_steps, { 50, 75 })
      or pct_list(vim.g.diffview_wide_steps, { 25, 40 })
  if #steps == 0 and not st then
    return
  end

  if not st then
    st = { base = panel_size(win, row), step = 0, row = row, producer = panel.config_producer,
           keep = diff_sizes(panel, row) }
    st.size = st.base
    wide[panel] = st
  end

  -- 다음 단계: 앞 단계의 크기와 지금 실제 크기보다 큰 것. 넓혀 본 뒤 diff 창을
  -- 재서 물리고(fit), 그래도 지금보다 넓어졌으면 그 단계로 정한다.
  local total = row and vim.o.lines or vim.o.columns
  local limit = math.max(st.base, total - (row and MIN_H or MIN_W))
  local prev = panel_size(win, row)
  local over = math.max(st.size, prev)
  local idx, tried
  for i = st.step + 1, #steps do
    local n = math.min(math.floor(total * steps[i] / 100), limit)
    if n > over then
      tried = true
      resize(panel, row, n)
      fit(panel, st)
      if panel_size(win, row) > prev then
        idx = i
        break
      end
    end
  end

  if not idx and not tried and st.step == 0 then
    wide[panel] = nil -- 넓힐 단계가 없고 넓혀 둔 적도 없다: 아무것도 건드리지 않는다
    return
  end
  if idx then
    st.step, st.size = idx, panel_size(win, row)
    panel.config_producer = producer_for(st, panel)
  else
    -- 한 바퀴 돌았다(또는 넓힐 단계가 없다): 처음 크기로. diff 창들도 처음 'w'
    -- 앞의 크기로 돌려놓는다 - 다른 창은 지금 크기 그대로다.
    panel.config_producer = st.producer
    wide[panel] = nil
    resize(panel, row, st.base, st.keep)
  end
end

-- ---------------------------------------------------------------------------
-- Neogit 커밋 창과 diff 창의 <C-n> / <C-p>
-- ---------------------------------------------------------------------------
-- 두 창 모두 git 의 통합(unified) diff 를 그대로 보여 준다.
--   NeogitCommitView  커밋 내용 - 로그(l l)나 상태 화면의 커밋 줄에서 Enter
--   NeogitDiffView    커밋할 때(c c) 메시지 창 옆에 뜨는 'Staged Changes'
-- (상태 화면의 d 팝업은 이 버퍼가 아니라 diffview 를 연다 - setup 의
--  integrations.diffview. 거기서는 diffview 의 <C-n>/<C-p> 가 ]c/[c 다)
--
-- <C-n> 은 다음 헝크, <C-p> 는 이전 헝크의 머리 줄(@@ -a,b +c,d @@ ...)로 간다.
-- 파일 경계를 넘어 이어진다 - 커밋 하나의 모든 헝크를 차례로 밟는다.
--   머리 줄에 서는 까닭: 통합 diff 에서 '어디가 바뀌었나'(줄 번호, 함수 이름)를
--   말하는 줄이 그것이고, 헝크는 거기서부터 아래로 읽힌다. Neogit 의 { } 도
--   거기 선다. 첫 바뀐 줄로 가면 위의 문맥 줄 세 줄과 머리 줄이 커서 위로
--   숨기 쉽다.
--   헝크가 창 아래로 넘치면 머리 줄을 창 맨 위로 올린다(zt). 다 보이면 화면은
--   그대로 둔다 - 누를 때마다 화면이 튀지 않게.
--   마지막(처음) 헝크에서 한 번 더 누르면 그 자리에 머문다. diffview 의 <C-n>
--   (]c) 과 같다 - 한 바퀴 돌면 '끝인 줄 알았는데 처음으로 튀는' 놀람이 생긴다.
--   알림도 띄우지 않는다 (Press ENTER 를 부를 여지를 남기지 않는다).
--   <C-p> 를 헝크 한가운데서 누르면 그 헝크의 머리 줄로 간다 ([c 와 Neogit 의
--   { 와 같다). 3<C-n> 처럼 횟수도 받는다.
--   Tab(za)으로 접어 둔 파일 안의 헝크는 건너뛴다 - 보이는 헝크만 밟는다
--   (Magit 의 n/p 가 접힌 절을 건너뛰는 것과 같다). 접힌 헝크는 머리 줄이
--   보이므로 거기 선다.
--
-- 헝크 머리 줄은 git 의 꼴 전체(@@ -a[,b] ... +c[,d] @@)로 알아본다. 커밋 메시지
-- 줄은 뺀다 - 커널 커밋 메시지에는 Coccinelle 규칙(@@ 줄)이나 인용한 diff 가
-- 들어 있곤 하다. Neogit 은 메시지 줄에 NeogitCommitViewDescription 색을 건다.
--
-- Neogit 의 { } (GoToPreviousHunkHeader / GoToNextHunkHeader)도 그대로 있다.
-- 그쪽은 파일 머리 줄(modified a.c)에도 서고, 마지막 헝크 다음에는 버퍼 끝
-- 줄로 가고, 누를 때마다 zt 한다.
-- 상태 화면(NeogitStatus)의 <C-n>/<C-p> 는 Neogit 의 다음/이전 절(NextSection /
-- PreviousSection)이다. 거기서는 헝크가 접힌 채 파일·절 단위로 다니는 것이
-- 맞아서 건드리지 않는다. 다른 창의 <C-n>/<C-p>(RelationView 목록 이동)도
-- 그대로다 - 이 키는 두 버퍼에만 걸린다.

local function is_hunk_header(s)
  return s:match('^@@+ %-%d+,?%d* .*%+%d+,?%d* @@') ~= nil
end

-- 이 줄이 커밋 메시지인가 (Neogit 의 색으로)
local function is_description(buf, ns, lnum)
  if not ns then
    return false
  end
  local ok, marks = pcall(api.nvim_buf_get_extmarks, buf, ns,
    { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true })
  if not ok then
    return false
  end
  for _, m in ipairs(marks) do
    if m[4] and m[4].hl_group == 'NeogitCommitViewDescription' then
      return true
    end
  end
  return false
end

-- from 줄부터 dir 쪽으로 ok(lnum, text) 를 만족하는 첫 줄. 큰 커밋(커널의
-- 머지 커밋은 수만 줄)에서도 버퍼 전체를 한 번에 읽지 않게 조금씩 읽는다.
local function scan(buf, from, dir, ok)
  local n = api.nvim_buf_line_count(buf)
  local l = from
  while l >= 1 and l <= n do
    local a, b
    if dir > 0 then
      a, b = l, math.min(n, l + 399)
    else
      a, b = math.max(1, l - 399), l
    end
    local lines = api.nvim_buf_get_lines(buf, a - 1, b, false)
    local first, last, inc = 1, #lines, 1
    if dir < 0 then
      first, last, inc = #lines, 1, -1
    end
    for i = first, last, inc do
      if ok(a + i - 1, lines[i]) then
        return a + i - 1
      end
    end
    l = dir > 0 and b + 1 or a - 1
  end
end

function _G.vimide_neogit_hunk(dir)
  local buf = api.nvim_get_current_buf()
  local win = api.nvim_get_current_win()
  local ns = api.nvim_get_namespaces()['neogit-buffer-' .. buf]
  local function ok(lnum, text)
    if not is_hunk_header(text) then
      return false
    end
    -- 접힌 파일 안이면 건너뛴다 (접힌 헝크 자신은 머리 줄이 보이므로 된다)
    local fc = vim.fn.foldclosed(lnum)
    if fc ~= -1 and fc ~= lnum then
      return false
    end
    return not is_description(buf, ns, lnum)
  end

  local cur = api.nvim_win_get_cursor(win)[1]
  local target
  for _ = 1, vim.v.count1 do
    -- 접힌 곳 안에 서 있으면 그 접힘을 통째로 넘어서 찾는다 (커서는 접힌
    -- 곳 안 어느 줄에나 있을 수 있고, 화면에는 접힘의 첫 줄로 보인다)
    local from
    if dir > 0 then
      local fe = vim.fn.foldclosedend(cur)
      from = (fe ~= -1 and fe or cur) + 1
    else
      local fs = vim.fn.foldclosed(cur)
      from = (fs ~= -1 and fs or cur) - 1
    end
    local l = scan(buf, from, dir, ok)
    if not l then
      break -- 끝: 거기 머문다
    end
    target, cur = l, l
  end
  if not target then
    return
  end

  api.nvim_win_set_cursor(win, { target, 0 })
  -- 헝크 끝이 창 아래로 넘치면 머리 줄을 맨 위로. 헝크는 머리 줄 뒤로 이어지는
  -- 문맥(' ')·더하기(+)·빼기(-)·'\ No newline' 줄이다. 창 높이만큼만 본다.
  local h = api.nvim_win_get_height(win)
  local body = api.nvim_buf_get_lines(buf, target, target + h, false)
  local last = target
  for i, s in ipairs(body) do
    if s:match('^[ +%-\\]') and not is_hunk_header(s) then
      last = target + i
    else
      break
    end
  end
  vim.fn.line('w0') -- 커서를 따라 화면 맨 위 줄을 먼저 맞춘다 (w$ 가 옛 값이 되지 않게)
  if last > vim.fn.line('w$') then
    vim.cmd('normal! zt')
  end
end

api.nvim_create_autocmd('FileType', {
  group = api.nvim_create_augroup('VimideNeogitHunk', { clear = true }),
  pattern = { 'NeogitCommitView', 'NeogitDiffView' },
  callback = function(a)
    local o = { buffer = a.buf, silent = true, nowait = true }
    vim.keymap.set('n', '<C-n>', function() _G.vimide_neogit_hunk(1) end,
      vim.tbl_extend('force', o, { desc = '다음 헝크 (diff 의 ]c 처럼, 끝에서는 머문다)' }))
    vim.keymap.set('n', '<C-p>', function() _G.vimide_neogit_hunk(-1) end,
      vim.tbl_extend('force', o, { desc = '이전 헝크 (diff 의 [c 처럼, 처음에서는 머문다)' }))
  end,
})
