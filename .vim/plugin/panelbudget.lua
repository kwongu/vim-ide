-- panelbudget.lua - 곁창 폭 예산: 좁은 터미널에서도 EDIT 창이 일할 자리를 남긴다
--
-- 곁창(F9 트리 32, aerial 40, RelationView 열 80, 큰 미리보기 T)은 저마다 정한 폭으로 열리고
-- winfixwidth 라, 터미널이 좁으면 줄어드는 몫을 EDIT 창이 다 떠안았다. 실측 (QA-10):
--   120x27 에서 F12 다음 F9                              EDIT 6칸
--   220 에서 F10, F12 -> 다른 탭에서 120 으로 줄이고 gT   EDIT 1칸 (aerial 40, 열 77)
--   aerial 을 닫으면 그 칸을 옆 트리가 떠안아 32 -> 65 로 부푼 채 남았다
--
-- 그래서 창 구조가 바뀔 때(창이 열리고 닫힐 때, 터미널 크기, 탭 옮김)마다 지금 탭을 한 번 본다.
--   * EDIT 영역이 g:vimide_edit_min_width 칸(기본 40, 나란한 EDIT 창이 여럿이면 창마다 20칸)
--     아래면, 옆에 선 곁창들을 '원래 폭' 비율대로 줄인다. 곁창은 g:vimide_panel_min_width
--     칸(기본 20) 아래로는 줄이지 않는다 - 그래도 모자라면 EDIT 이 그만큼 덜 받는다.
--   * 자리가 다시 나면(터미널을 넓히거나 곁창 하나를 닫으면) 원래 폭으로 되돌린다.
--   * 다른 곁창이 닫히며 빈자리를 떠안아 부푼 곁창도 원래 폭으로 돌린다.
-- '원래 폭' 은 곁창을 처음 본 폭이다 (창이 w:vimide_pref_width 를 달고 있으면 그 값 -
-- RelationView 는 g:relationview_width 를 단다. 좁을 때 열리면 처음 폭이 이미 깎여 있어서다).
-- 사람이 손으로 바꾼 폭(:vertical resize, 경계 끌기, RelationView/트리의 w)은 그 자리에서
-- 거스르지 않고 새 '원래 폭' 으로 적는다 - EDIT 영역이 모자라면 나머지 곁창이 비켜 준다.
-- 그런 곁창은 터미널 크기가 바뀔 때만 줄인다.
-- 줄 수도 본다: 터미널 줄 수가 줄어 1-2줄로 눌린 quickfix 와 쌓인 EDIT 창을 편다 (rows()).
--
-- 남의 배치는 건드리지 않는다: Diffview/Neogit/DirDiff 탭(vimidewin.lua 의 foreign_tab)과
-- 세션 복구 중에는 쉰다. vimidewin.lua 의 unsquash(8칸 이하로 뭉개진 곁창 되살리기)와는
-- 겹치지 않는다 - 여기 바닥(20칸)이 그 위다. RelationView 의 restore_geom(창이 열리고 닫힐 때
-- 열 폭 되돌리기)은 되돌린 뒤 여기를 다시 부른다(_G.vimide_panel_budget).
--
-- 일은 가볍다(창 열댓 개의 위치/폭 읽기, 0.1ms 안팎). 이벤트에서는 vim.schedule 로 한 번만
-- 모아서 돈다 - 키 처리 길에 아무것도 더하지 않는다.
--
--   let g:vimide_panel_budget = 0       " 끈다
--   let g:vimide_edit_min_width = 40    " EDIT 영역이 지킬 칸수
--   let g:vimide_panel_min_width = 20   " 곁창을 줄여도 이 칸수까지만

if vim.g.loaded_vimide_panelbudget then
  return
end
vim.g.loaded_vimide_panelbudget = 1

if vim.fn.has('nvim-0.10') == 0 then
  return
end

local api = vim.api

local pref = {}     -- winid -> 원래 폭
local held = {}     -- winid -> true: 사람이(또는 플러그인이 스스로) 정한 폭
local seen = {}     -- winid -> 마지막으로 보거나 맞춘 폭. 그 뒤에 따로 바뀌면 사람 손이다
local born = {}     -- winid -> 처음 본 때 (vim.uv.now). 갓 생긴 곁창의 폭 바꾸기는 자리 잡기다
local tab_cols = {} -- tabpage -> 그 탭을 마지막으로 맞출 때의 &columns
local tab_lines = {} -- tabpage -> 그 탭을 마지막으로 볼 때의 &lines (rows())
local lines_now = vim.o.lines -- VimResized 직전의 &lines
local cols_now = vim.o.columns -- VimResized 직전의 &columns
local hgt = {}        -- winid -> 크기가 바뀌기 전에 본 높이 (rows(): 누가 줄였나)
local wdt = {}        -- winid -> 크기가 바뀌기 전에 본 폭 (apply(): 누가 줄였나)
local relaid = false  -- 크기가 바뀌어 다시 배치됐고 run() 이 아직 안 봤다: 그동안의 크기는 적지 않는다
local dirty = false -- 창 구조가 바뀌었고 아직 맞추지 않았다
local queued = false
local resized = false -- 터미널 크기가 바뀌었다: 손으로 정한 폭도 줄인다
local moved = false   -- 곁창 폭을 사람이 바꿨다: 뭉개진 EDIT 창이 있으면 고르게 편다
local last = {}       -- 마지막으로 나눈 내역 (진단용: _G.vimide_panel_budget_state())

local function num(name, default)
  local v = tonumber(vim.g[name])
  if v == nil then
    return default
  end
  return v
end

local function floating(w)
  local ok, c = pcall(api.nvim_win_get_config, w)
  return ok and c and c.relative ~= nil and c.relative ~= ''
end

-- 곁창: 폭을 고정한(winfixwidth) 파일 아닌 창 (neo-tree, aerial, tagbar, RelationView 열)
local function is_panel(w)
  if floating(w) then
    return false
  end
  local ok, fixed = pcall(function() return vim.wo[w].winfixwidth end)
  if not (ok and fixed) then
    return false
  end
  return vim.bo[api.nvim_win_get_buf(w)].buftype ~= ''
end

-- EDIT 영역을 이루는 창: 곁창도, 아래에 깔리는 quickfix/미리보기도 아닌 창
local function is_body(w)
  if floating(w) or vim.wo[w].previewwindow then
    return false
  end
  if vim.bo[api.nvim_win_get_buf(w)].buftype == 'quickfix' then
    return false
  end
  return not is_panel(w)
end

local function skip_tab()
  if num('vimide_panel_budget', 1) == 0 then
    return true
  end
  local f = _G.vimide_foreign_tab
  if type(f) == 'function' then
    local ok, r = pcall(f)
    if ok and r then
      return true
    end
  end
  return false
end

local function busy()
  if vim.v.exiting ~= vim.NIL then
    return true
  end
  local sess = _G.vimide_session
  if type(sess) == 'table' and type(sess.is_restoring) == 'function' then
    local ok, r = pcall(sess.is_restoring)
    if ok and r then
      return true
    end
  end
  return false
end

-- 묶음들에게 줄 폭을 정한다. 손으로 정한 것은 그 폭 그대로, 나머지는 남은 자리를
-- 원래 폭 비율로 나눈다 (바닥에 걸린 것은 바닥에 두고 나머지끼리 다시 나눈다).
local function share(groups, space)
  local free, rest = space, {}
  for _, g in ipairs(groups) do
    if g.held then
      g.target = g.pref
      free = free - g.pref
    else
      rest[#rest + 1] = g
    end
  end
  local want = 0
  for _, g in ipairs(rest) do
    want = want + g.pref
  end
  if want <= free then
    for _, g in ipairs(rest) do
      g.target = g.pref
    end
    return
  end
  local left, avail = rest, free
  for _ = 1, #rest + 1 do
    local sum = 0
    for _, g in ipairs(left) do
      sum = sum + g.pref
    end
    local keep, clamped = {}, false
    for _, g in ipairs(left) do
      local t = math.floor(g.pref * math.max(avail, 0) / math.max(sum, 1))
      if t < g.floor then
        g.target = g.floor
        avail = avail - g.floor
        clamped = true
      else
        g.target = t
        keep[#keep + 1] = g
      end
    end
    if not clamped or #keep == 0 then
      return
    end
    left = keep
  end
end

-- 지금 탭을 맞춘다. all = 손으로 정한 폭도 줄인다 (터미널 크기가 바뀌었다)
local function apply(all, balance)
  if skip_tab() then
    return
  end
  local tab = api.nvim_get_current_tabpage()
  if tab_cols[tab] and tab_cols[tab] ~= vim.o.columns then
    all = true -- 다른 탭에 있는 동안 터미널 크기가 바뀌었다
  end
  tab_cols[tab] = vim.o.columns
  -- 터미널 크기가 바뀌면 vim 이 EDIT 창들에 칸을 제멋대로 나눈다(한 창이 1칸으로 남기도 한다):
  -- 그때도 뭉개진 EDIT 창은 고르게 편다
  balance = balance or all
  local wins = api.nvim_tabpage_list_wins(tab)
  local emin, emax, body = math.huge, -1, {}
  for _, w in ipairs(wins) do
    if is_body(w) then
      local pos = api.nvim_win_get_position(w)
      emin = math.min(emin, pos[2])
      emax = math.max(emax, pos[2] + api.nvim_win_get_width(w))
      body[#body + 1] = { pos[1], pos[1] + api.nvim_win_get_height(w) }
    end
  end
  if #body == 0 then
    return -- EDIT 창이 없다 (곁창만 남은 탭): 나눌 것이 없다
  end
  -- 한 줄에 나란히 선 EDIT 창의 최대 수 (창마다 윗줄에서 그 줄을 덮는 창을 센다)
  local k = 1
  for _, a in ipairs(body) do
    local n = 0
    for _, b in ipairs(body) do
      if b[1] <= a[1] and a[1] < b[2] then
        n = n + 1
      end
    end
    k = math.max(k, n)
  end
  -- 옆에 선 곁창을 칸(시작 열, 폭)으로 묶는다. 오른쪽 열의 트리/목록/미리보기는 한 묶음이다.
  -- EDIT 영역 위나 아래에 깔린 곁창(아래쪽 RelationView 목록 등)은 폭과 상관이 없어 뺀다.
  local groups, by = {}, {}
  for _, w in ipairs(wins) do
    if is_panel(w) then
      local c = api.nvim_win_get_position(w)[2]
      local wd = api.nvim_win_get_width(w)
      if c + wd <= emin or c >= emax then
        local key = c .. ':' .. wd
        local g = by[key]
        if not g then
          g = { wins = {}, width = wd }
          by[key] = g
          groups[#groups + 1] = g
        end
        g.wins[#g.wins + 1] = w
      end
    end
  end
  if #groups == 0 then
    -- 곁창이 없어도 터미널 폭이 줄면 vim 은 오른쪽 EDIT 창부터 칸을 뺀다 (220 -> 120 에서
    -- 나란한 둘이 110/9, QA): 그 바람에 10칸 아래로 눌린 창이 있을 때만 아래처럼 고르게
    -- 편다 - 그 전부터 좁던 창(<C-w>| 로 다른 창을 키운 것)은 그대로 둔다
    if balance then
      for _, w in ipairs(wins) do
        if api.nvim_win_is_valid(w) and is_body(w) and api.nvim_win_get_width(w) < 10
            and (wdt[w] or 10) >= 10 then
          pcall(vim.cmd, 'wincmd =')
          break
        end
      end
    end
    return
  end
  local floor0 = num('vimide_panel_min_width', 20)
  local total = emax - emin
  for _, g in ipairs(groups) do
    total = total + g.width
    local p, h = 0, false
    for _, w in ipairs(g.wins) do
      if not pref[w] then
        local okv, v = pcall(function() return vim.w[w].vimide_pref_width end)
        pref[w] = (okv and tonumber(v)) or g.width
        born[w] = born[w] or vim.uv.now()
      end
      p = math.max(p, pref[w])
      h = h or held[w] == true
    end
    g.pref = p
    g.held = h and not all
    g.floor = math.min(p, floor0)
  end
  local need = math.max(num('vimide_edit_min_width', 40), k * 20)
  share(groups, total - need)
  last = { tab = tab, edit = { emin, emax, k }, need = need, all = all, groups = {} }
  for _, g in ipairs(groups) do
    last.groups[#last.groups + 1] = { wins = g.wins, width = g.width, pref = g.pref,
      held = g.held, target = g.target }
  end
  -- 줄일 것부터 줄이고 늘린다: 늘릴 자리는 줄인 데서 나온다. 한 묶음을 맞추면 옆 묶음이
  -- 그 칸을 떠안기도 해서(열 프레임은 winfixwidth 로 안 쳐진다) 다 맞을 때까지 몇 번 돈다.
  local touched = false
  for _ = 1, 3 do
    local off = false
    for pass = 1, 2 do
      for _, g in ipairs(groups) do
        local w = g.wins[1]
        if g.target and api.nvim_win_is_valid(w) then
          local cur = api.nvim_win_get_width(w)
          if cur ~= g.target and ((pass == 1) == (g.target < cur)) then
            pcall(api.nvim_win_set_width, w, g.target)
            off = true
            touched = true
          end
        end
      end
    end
    if not off then
      break
    end
  end
  -- 돌려준 칸은 vim 이 EDIT 영역의 한쪽 끝 창에 몰아 준다. 나란한 EDIT 창 하나가 그래도
  -- 10칸 아래로 남았으면 고르게 편다 ('wincmd =' 는 winfixwidth 곁창의 폭을 건드리지 않는다).
  -- 곁창 폭이 바뀐 때(여기서 맞췄거나, 트리의 w 처럼 곁창을 넓혔을 때)만 한다 - <C-w>| 로
  -- 일부러 한 창을 키운 것까지 되돌리면 안 된다.
  if touched or balance then
    for _, w in ipairs(wins) do
      if api.nvim_win_is_valid(w) and is_body(w) and api.nvim_win_get_width(w) < 10 then
        pcall(vim.cmd, 'wincmd =')
        break
      end
    end
  end
  for _, g in ipairs(groups) do
    for _, w in ipairs(g.wins) do
      if api.nvim_win_is_valid(w) then
        seen[w] = api.nvim_win_get_width(w)
      end
    end
  end
end

-- 줄 수가 줄어 뭉개진 창을 편다. 터미널 줄 수가 줄면 vim 은 아래 창부터 줄을 뺀다:
-- F12 열은 창마다 winfixheight 라 그 몫을 맨 아래 quickfix 가 다 떠안아 1줄로 남았고
-- (220x60 -> 40, 다른 탭은 들어갈 때 같은 일), 쌓인 EDIT 창의 맨 아래 것도 1줄이 됐다.
-- 그 탭의 줄 수가 바뀐 뒤 처음 볼 때, 그 바람에 3줄 아래로 눌린 창만 편다 - 그 전부터
-- 작던 창(<C-w>_ 로 다른 창을 키웠거나 :resize 1 한 것)은 그대로 둔다. quickfix 는
-- 10줄(화면의 1/4 까지)로, EDIT 더미는 .vimrc 의 vimide_edit_stack_fix 가 고르게 편다
-- (남의 탭에서는 quickfix 만).
local function note_sizes()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if not floating(w) then
      hgt[w] = api.nvim_win_get_height(w)
      wdt[w] = api.nvim_win_get_width(w)
    end
  end
end

local function rows(all)
  if num('vimide_panel_budget', 1) == 0 then
    return
  end
  local tab = api.nvim_get_current_tabpage()
  local was = tab_lines[tab]
  tab_lines[tab] = vim.o.lines
  if not (all or (was and was ~= vim.o.lines)) then
    return
  end
  local want = math.min(10, math.max(3, math.floor((vim.o.lines - vim.o.cmdheight) / 4)))
  local stack = false
  for _, w in ipairs(api.nvim_tabpage_list_wins(tab)) do
    local h = api.nvim_win_get_height(w)
    if not floating(w) and h < 3 and (hgt[w] or 3) >= 3 then
      if vim.bo[api.nvim_win_get_buf(w)].buftype == 'quickfix' then
        pcall(api.nvim_win_set_height, w, want)
      elseif is_body(w) then
        stack = true
      end
    end
  end
  if stack and not skip_tab() and type(_G.vimide_edit_stack_fix) == 'function' then
    pcall(_G.vimide_edit_stack_fix)
  end
end

local function run()
  queued = false
  if not dirty then
    return
  end
  if busy() then
    -- 세션 복구 중: 다 세운 뒤에 한 번
    vim.defer_fn(function()
      if not queued then
        queued = true
        vim.schedule(run)
      end
    end, 300)
    return
  end
  local all, balance = resized, moved
  dirty, resized, moved = false, false, false
  pcall(rows, all)
  pcall(apply, all, balance)
  -- 다 맞춘 뒤의 크기를 '바뀌기 전' 으로 적는다 (다음 크기 바뀜에서 누가 줄였나를 가린다)
  pcall(note_sizes)
  relaid = false
end

local function soon(is_resize)
  dirty = true
  if is_resize then
    resized = true
  end
  if queued then
    return
  end
  queued = true
  vim.schedule(run)
end

-- RelationView 처럼 autocmd 없이(noautocmd) 창을 세우는 쪽이 다 세운 뒤에 부른다.
-- 동기로 바로 맞춘다 - 첫 그림부터 EDIT 창이 제 폭으로 나온다.
function _G.vimide_panel_budget(all)
  if busy() then
    soon(all)
    return
  end
  pcall(apply, all)
end

-- 진단용: :lua print(vim.inspect(_G.vimide_panel_budget_state()))
function _G.vimide_panel_budget_state()
  return { pref = pref, held = held, seen = seen, dirty = dirty, last = last }
end

local grp = api.nvim_create_augroup('VimIdePanelBudget', { clear = true })

api.nvim_create_autocmd('WinNew', {
  group = grp,
  callback = function()
    if not floating(api.nvim_get_current_win()) then
      soon(false)
    end
  end,
})

-- 곁창을 noautocmd 로 가르는 플러그인이 있다 (aerial: 'noau vertical topleft 1split' 뒤에 제
-- 버퍼를 싣는다). WinNew 는 없지만 버퍼를 싣는 BufWinEnter 는 온다. 파일 버퍼 바꾸기는 흔하고
-- 곁창과 상관없어 뺀다.
api.nvim_create_autocmd('BufWinEnter', {
  group = grp,
  callback = function(a)
    if vim.bo[a.buf].buftype ~= '' and not floating(api.nvim_get_current_win()) then
      soon(false)
    end
  end,
})

api.nvim_create_autocmd('WinClosed', {
  group = grp,
  callback = function(a)
    local w = tonumber(a.match)
    if not w then
      return
    end
    local float = api.nvim_win_is_valid(w) and floating(w)
    pref[w], held[w], seen[w], born[w], hgt[w], wdt[w] = nil, nil, nil, nil, nil, nil
    if not float then
      soon(false)
    end
  end,
})

api.nvim_create_autocmd('TabEnter', {
  group = grp,
  callback = function()
    -- 다른 탭에 있는 동안 터미널 크기가 바뀌었으면 vim 이 들어오며 다시 배치했다
    local cur = api.nvim_get_current_tabpage()
    local t, c = tab_lines[cur], tab_cols[cur]
    if (t and t ~= vim.o.lines) or (c and c ~= vim.o.columns) then
      relaid = true
    end
    soon(false)
  end,
})

api.nvim_create_autocmd('TabClosed', {
  group = grp,
  callback = function()
    -- 닫힌 탭의 기록은 탭 핸들로 찾을 수 없다: 남은 탭만 남긴다
    local live, live_l = {}, {}
    for _, t in ipairs(api.nvim_list_tabpages()) do
      live[t] = tab_cols[t]
      live_l[t] = tab_lines[t]
    end
    tab_cols, tab_lines = live, live_l
  end,
})

api.nvim_create_autocmd('VimResized', {
  group = grp,
  callback = function()
    -- 아직 본 적 없는 탭은 크기가 바뀌기 전 줄·칸 수로 적어 둔다 - 그 탭에 들어갈 때 rows()
    -- 와 apply() 가 '크기가 바뀌었다' 로 알아보게
    for _, t in ipairs(api.nvim_list_tabpages()) do
      tab_lines[t] = tab_lines[t] or lines_now
      tab_cols[t] = tab_cols[t] or cols_now
    end
    lines_now, cols_now = vim.o.lines, vim.o.columns
    relaid = true
    soon(true)
  end,
})

-- 구조가 그대로인데 곁창 폭이 바뀌었다 = 사람이(또는 그 플러그인이 스스로) 정한 폭이다.
-- 그것을 새 '원래 폭' 으로 적는다. 구조가 바뀌는 중(dirty)에 일어난 변화는 곧 도는 맞추기의
-- 몫이라 적지 않는다.
--   * 갓 생긴 곁창(1초 안)이 폭을 바꾼 것은 그 플러그인이 자리를 잡는 것이다 - aerial 은
--     1칸으로 갈라 두었다가 심볼을 읽은 뒤 내용 폭으로 넓힌다. 원래 폭으로만 적는다.
--   * 그 뒤의 변화는 사람 손이다(:vertical resize, 경계 끌기, w). 그 폭은 지키고(held),
--     EDIT 영역이 모자라면 나머지 곁창이 비켜 준다 - 그래서 한 번 맞춘다.
api.nvim_create_autocmd('WinResized', {
  group = grp,
  callback = function()
    local ev = vim.v.event
    local now = vim.uv.now()
    local changed = false
    for _, w in ipairs(ev and ev.windows or {}) do
      -- 높이는 사람이(또는 창이 열리고 닫히며) 바꾼 것만 적는다 - 터미널 크기가 바뀐 뒤 rows()
      -- 가 보기 전의 것은 vim 이 줄인 것이다
      if not relaid and api.nvim_win_is_valid(w) and not floating(w) then
        hgt[w] = api.nvim_win_get_height(w)
        wdt[w] = api.nvim_win_get_width(w)
      end
      if api.nvim_win_is_valid(w) and is_panel(w) then
        local wd = api.nvim_win_get_width(w)
        born[w] = born[w] or now
        if not dirty and seen[w] ~= nil and wd ~= seen[w] then
          pref[w] = wd
          held[w] = (now - born[w] > 1000) or nil
          changed = true
        end
        seen[w] = wd
      end
    end
    if changed then
      moved = true
      soon(false)
    end
  end,
})
