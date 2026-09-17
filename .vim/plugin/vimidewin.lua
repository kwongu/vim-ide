-- vimidewin.lua - 창의 역할을 지킨다
--
-- 두 가지를 한다.
--
--   1. 곁창(플러그인 창)에서는 그 플러그인 일만 하게 한다.
--      파일이 곁창에 실리면 그 파일을 '직전에 보던 EDIT 창'으로 옮기고,
--      곁창은 원래 내용으로 되돌린다.
--
--   2. EDIT 창은 최소 하나를 지킨다.
--      곁창만 남고 EDIT 창이 0개가 되면 vim 을 끝낸다.
--
-- 왜 한 파일에 같이 두나: 둘 다 '이 창이 EDIT 창인가'라는 같은 질문에
-- 매달려 있기 때문이다. 이 설정에는 그 판정기가 서로 다른 기준으로 넷이나
-- 흩어져 있었다(overview.lua:120, relationview.lua 의 is_edit_win,
-- projectfiles.lua, vimide#qf#Usable). 여기서 하나를 정본으로 세우고
-- _G.vimide_is_edit_win 으로 내놓는다.
--
-- 끄는 법:
--   let g:vimide_win_guard    = 0   " 1번(곁창 보호) 끄기
--   let g:vimide_min_edit_win = 0   " 2번(EDIT 최소 1개) 끄기
--
-- nvim 전용이다. 개발서버의 진짜 vim 8.1 은 .vim/plugin/*.lua 를 읽지 않으니
-- 거기서는 이 규칙이 통째로 없다 - 그쪽은 예전 그대로 동작한다.

if vim.fn.has('nvim') ~= 1 then
  return
end

local api = vim.api

local function cfg(name, default)
  local v = vim.g['vimide_' .. name]
  if v == nil then
    return default
  end
  -- false / v:false 로 끄는 사람이 있다. tonumber(false) 는 nil 이라
  -- 그대로 두면 default 로 되돌아가 '껐는데 켜진 채'가 된다.
  if v == false or v == 0 then
    return 0
  end
  if v == true then
    return 1
  end
  return tonumber(v) or default
end

-- ---------------------------------------------------------------------------
-- 이 창이 EDIT 창인가
-- ---------------------------------------------------------------------------
-- 흩어져 있던 넷을 합쳤다. 가장 촘촘하던 overview.lua 의 판정을 뼈대로,
-- relationview 의 '자기 창 제외'와 qf.vim 의 &previewwindow 를 더했다.

-- 곁창임이 확실한 filetype
local PLUGIN_FT = {
  ['neo-tree'] = true, ['neo-tree-popup'] = true,
  ['nerdtree'] = true, ['tagbar'] = true, ['aerial'] = true,
  ['qf'] = true, ['relationview'] = true, ['overview'] = true,
  ['NvimTree'] = true, ['netrw'] = true, ['bufexplorer'] = true,
  ['help'] = true, ['man'] = true, ['fugitive'] = true,
  ['DiffviewFiles'] = true, ['DiffviewFileHistory'] = true,
}

-- 곁창임이 확실한 버퍼 '파일 이름'(경로 말고 마지막 조각) 패턴.
--
-- 경로 전체에 대고 찾으면 진짜 소스 파일을 곁창으로 오해한다. 실제로
-- 이 저장소 안에 .vim/plugged/nerdtree/plugin/NERD_tree.vim 이 있다 -
-- 그 파일을 열어 고치는 동안 그 창이 EDIT 창이 아니게 되면, 곁창 하나만
-- 닫아도 'EDIT 0개' 로 계산되어 nvim 이 꺼진다.
local PLUGIN_NAME = {
  '^RelationView$',          -- 패널
  '^RelationView%-',         -- 미리보기(작은/큰 둘 다)
  '^NERD_tree_',             -- NERD_tree_1 / NERD_tree_tab_1
  '^%[BufExplorer%]$',
  '^neo%-tree filesystem',
}

local function is_plugin_buf(buf)
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return true -- 알 수 없으면 편집 창으로 치지 않는다
  end
  if vim.bo[buf].buftype ~= '' then
    return true -- nofile / quickfix / terminal / prompt / help ...
  end
  local ft = vim.bo[buf].filetype or ''
  if PLUGIN_FT[ft] or ft:match('^Telescope') or ft:match('^Neogit') then
    return true
  end
  local base = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ':t')
  for _, pat in ipairs(PLUGIN_NAME) do
    if base:match(pat) then
      return true
    end
  end
  return false
end

--- 이 창을 '파일을 열어도 되는 EDIT 창'으로 볼 수 있는가.
--- @param win integer|nil 창 id (없으면 지금 창)
function _G.vimide_is_edit_win(win)
  win = win or api.nvim_get_current_win()
  if not (win and api.nvim_win_is_valid(win)) then
    return false
  end
  if api.nvim_win_get_tabpage(win) ~= api.nvim_get_current_tabpage() then
    return false
  end
  -- 부동 창(telescope, overview 막대, 각종 popup)은 EDIT 창이 아니다.
  -- relationview 쪽 판정이 이것을 빠뜨리고 있었다.
  local ok, conf = pcall(api.nvim_win_get_config, win)
  if ok and conf and conf.relative and conf.relative ~= '' then
    return false
  end
  -- quickr-preview 의 pedit 창은 buftype 도 filetype 도 평범한 파일과 같다.
  -- &previewwindow 로만 갈린다.
  if vim.wo[win].previewwindow then
    return false
  end
  return not is_plugin_buf(api.nvim_win_get_buf(win))
end

--- 지금 탭의 EDIT 창 목록. '파일을 어디에 열까'는 지금 탭 안에서 고른다.
--- @param skip integer|nil 세지 않을 창 (닫히는 중인 창을 빼는 데 쓴다)
function _G.vimide_edit_wins(skip)
  local out = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if w ~= skip and _G.vimide_is_edit_win(w) then
      out[#out + 1] = w
    end
  end
  return out
end

-- '편집 자리를 잠시 빌려 쓰는' 플러그인들.
--
-- aerial / neo-tree / NERDTree / tagbar / quickfix 같은 것은 자기 창을 새로
-- 만드는 '곁창' 이다. 반면 BufExplorer 와 netrw 는 지금 창을 그 자리에서
-- 차지한다 - 그 창은 원래 EDIT 창이었고, 고르고 나면 돌려준다.
local BORROWED_FT = {
  bufexplorer = true,
  netrw = true,
  NvimTree = true, -- hijack_netrw 로 netrw 자리를 대신 차지한다
}

--- 파일을 열 '편집 자리' 를 고른다.
---
--- 1) 진짜 EDIT 창이 있으면 직전에 보던 것
--- 2) 없으면, 편집 자리를 빌려 쓰는 중인 창(BufExplorer / netrw)
--- 3) 그것도 없으면 0
---
--- 2)가 필요한 이유: F6 으로 BufExplorer 를 띄워 두면 그 창이 유일한 편집
--- 자리를 차지한다. 그 상태에서 곁창에서 :Ex 를 누르면 '진짜 EDIT 창' 은
--- 하나도 없어서 아무 일도 못 했다.
function _G.vimide_edit_slot()
  if type(_G.vimide_last_edit_win) == 'function' then
    local ok, w = pcall(_G.vimide_last_edit_win)
    if ok and w and w ~= 0 and _G.vimide_is_edit_win(w) then
      return w
    end
  end
  local wins = _G.vimide_edit_wins()
  if wins[1] then
    return wins[1]
  end
  return _G.vimide_borrowed_win()
end

--- 지금 '편집 자리를 빌려 쓰는 중'인 창. 없으면 0.
---
--- 따로 내놓는 이유는 되돌이 때문이다. vimide_edit_slot() 은 첫 수로
--- _G.vimide_last_edit_win()(= relationview 의 pick_src_win) 을 부른다.
--- 그래서 pick_src_win 이 마지막 수로 edit_slot 을 부르면 서로 물고 돈다.
--- 이 함수는 아무도 되부르지 않으니 양쪽이 같이 쓸 수 있다.
function _G.vimide_borrowed_win()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local ok, conf = pcall(api.nvim_win_get_config, w)
    local floating = ok and conf and conf.relative and conf.relative ~= ''
    if not floating and BORROWED_FT[vim.bo[api.nvim_win_get_buf(w)].filetype] then
      return w
    end
  end
  return 0
end

--- 모든 탭을 통틀어 EDIT 창이 몇 개인가.
---
--- '끝낼까'는 반드시 이쪽으로 센다. 지금 탭만 보면 다른 탭에 편집 창이
--- 멀쩡히 있어도 nvim 이 통째로 꺼진다 - neogit 은 kind='tab' 이라 늘 새
--- 탭에 뜨고, 그 탭에는 곁창밖에 없어서 거기서 창 하나만 닫아도 발동한다.
--- @param skip integer|nil 세지 않을 창
function _G.vimide_edit_win_count_all(skip)
  local n = 0
  local cur = api.nvim_get_current_tabpage()
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    for _, w in ipairs(api.nvim_tabpage_list_wins(tab)) do
      -- is_edit_win 은 '지금 탭' 조건을 달고 있어 남의 탭을 못 센다.
      -- 여기서는 그 조건만 빼고 같은 잣대를 쓴다.
      if w ~= skip and api.nvim_win_is_valid(w) then
        local ok, conf = pcall(api.nvim_win_get_config, w)
        local floating = ok and conf and conf.relative and conf.relative ~= ''
        if not floating and not vim.wo[w].previewwindow
            and not is_plugin_buf(api.nvim_win_get_buf(w)) then
          n = n + 1
        end
      end
    end
  end
  local _ = cur
  return n
end

--- 살아 있는 터미널 작업이 붙은 창이 있는가.
--- 빌드나 ssh 를 돌려 두고 편집 창을 닫았을 뿐인데 20분짜리 작업이
--- 말없이 죽으면 안 된다.
function _G.vimide_has_live_terminal()
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    for _, w in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if api.nvim_win_is_valid(w) then
        local b = api.nvim_win_get_buf(w)
        if api.nvim_buf_is_valid(b) and vim.bo[b].buftype == 'terminal' then
          return true
        end
      end
    end
  end
  return false
end

-- 나가는 중이거나 세션을 되살리는 중인가. 둘 다일 때는 아무 규칙도 돌면 안 된다.
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

-- ---------------------------------------------------------------------------
-- 1. 곁창에 실린 파일을 EDIT 창으로 돌려보낸다
-- ---------------------------------------------------------------------------
-- 마우스 매핑과 같은 사정이다. 파일이 곁창에 실리는 길은 한둘이 아니다 -
-- gf, <C-^>, :edit/:find/:buffer 를 직접 치기, 전역 버퍼 순환 매핑(,r ,e ,w
-- ,1~,0), 남의 플러그인이 고른 창... 길마다 가드를 다는 대신, 실리고 난
-- '뒤'를 한 곳에서 되돌린다.
--
-- RelationView 패널/미리보기 세 창에는 winfixbuf 가 걸려 있어 애초에 거부되고
-- (E1513), 여기 오는 것은 그것이 없는 나머지 곁창들이다.

local guarded = {} -- winid -> { buf = 곁창 버퍼, ft = 곁창 filetype, kind = ... }
local sweeping = false

-- '지금 창을 그 자리에서 차지하는' 플러그인들.
--
-- EDIT 창에 들어앉는 것은 정상이다 - 자리를 잠시 빌렸다가 고르고 나면
-- 돌려준다. 곁창에 들어앉으면 그 곁창이 통째로 없어진다.
--
-- 이 표는 BORROWED_FT 와 목적이 다르다. 저쪽은 '이 창을 편집 자리로 쳐도
-- 되나'를 묻고, 이쪽은 '이 버퍼가 곁창에 들어온 침입자인가'를 묻는다.
-- nerdtree 가 이쪽에만 있는 이유: NERDTree 는 제 창을 따로 만들지만
-- (그래서 편집 자리가 아니다) NERDTreeHijackNetrw 로 디렉터리를 가로챌
-- 때는 지금 창을 차지한다.
local TAKEOVER_FT = {
  netrw = true,
  bufexplorer = true,
  nerdtree = true,
  NvimTree = true,
}

local function kind_of(buf)
  if vim.bo[buf].buftype == 'quickfix' then
    -- quickfix 와 location list 는 buftype 도 filetype 도 같다
    local ok, info = pcall(vim.fn.getwininfo, vim.fn.bufwinid(buf))
    if ok and info and info[1] and info[1].loclist == 1 then
      return 'loclist'
    end
    return 'quickfix'
  end
  return 'other'
end

-- 이 곁창을 어떻게 다시 세우나. 버퍼가 함께 사라지는 종류가 있어서,
-- 되돌릴 버퍼가 없을 때는 이 명령으로 새로 연다.
local REOPEN = {
  quickfix = 'botright copen',
  aerial = 'AerialOpen',
  tagbar = 'TagbarOpen',
  nerdtree = 'NERDTree',
}

local function remember(win)
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  -- is_plugin_buf(버퍼 기준)만 보면 모자란다. 부동 창과 미리보기 창
  -- (&previewwindow)은 버퍼가 평범한 파일이라 곁창인 줄 모른다 - 판정이
  -- 두 갈래로 갈리면 '지키는 목록'과 'EDIT 창 목록'이 어긋난다.
  if _G.vimide_is_edit_win(win) then
    return
  end
  -- 부동 창(overview 막대, telescope, 각종 popup)은 지키지 않는다.
  --
  -- 이것들은 제 버퍼를 수시로 새로 만들고 창째로 사라졌다 나타난다.
  -- 그 오르내림을 '침입' 으로 읽으면 멀쩡한 버퍼를 EDIT 창으로 밀어 넣는다
  -- (실측: 이 줄이 없을 때 시작하자마자 편집 창이 overview 버퍼로 바뀌고
  -- 배치가 통째로 무너졌다). 어차피 파일이 부동 창에 실려도 잠깐이다.
  local okc, conf = pcall(api.nvim_win_get_config, win)
  if okc and conf and conf.relative and conf.relative ~= '' then
    guarded[win] = nil
    return
  end
  local buf = api.nvim_win_get_buf(win)
  -- 이미 적어 둔 곁창이 있고, 지금 들어와 있는 것이 그것과 다른 남의
  -- 곁창 버퍼면 덮어쓰지 않는다.
  --
  -- 안 그러면 되살릴 대상이 침입자로 바뀐다. 실제로 그렇게 된다:
  -- aerial 창에서 :term 을 치면 BufEnter 가 먼저 떠서 여기가 돌고,
  -- 그 자리에서 덮어쓰면 뒤이어 도는 rescue 가 '되돌릴 것은 터미널'
  -- 이라고 믿는다. 곁창의 정체는 한 번 잡으면 유지한다.
  local g = guarded[win]
  if g and g.buf and g.buf ~= buf and api.nvim_buf_is_valid(g.buf)
      and is_plugin_buf(buf) and vim.bo[buf].filetype ~= g.ft then
    return
  end
  -- '편집 자리를 잠시 빌려 쓰는' 플러그인이 든 창은 아예 지키지 않는다.
  --
  -- :Ex 를 EDIT 창에서 치면 그 창이 netrw 버퍼를 든다. buftype 이 nofile
  -- 이라 곁창처럼 보이지만, 그 창은 원래 EDIT 창이고 고르고 나면 바로
  -- 그 자리에 파일을 연다. 그것을 '곁창에 파일이 실렸다' 고 보면 안 된다.
  --
  -- 실측(이 줄이 없을 때): EDIT 창에서 :Ex -> 파일 선택 -> 지킴이가 netrw
  -- 버퍼를 도로 집어넣고 파일을 딴 창으로 빼냈다. 게다가 되돌려 넣은 netrw
  -- 버퍼는 이름이 디렉터리라, divert_dir 이 그것을 다시 편집 자리로 넘겨
  -- NERDTree 가 가로챘다 - 편집 창이 통째로 사라졌다.
  --
  -- 이미 적어 둔 곁창(aerial 등)에 netrw 가 들어앉은 경우는 바로 위
  -- 검사가 그 기록을 지켜 주므로, 그때는 여전히 되돌린다.
  if not g and BORROWED_FT[vim.bo[buf].filetype] then
    guarded[win] = nil
    return
  end
  -- 폭도 같이 적는다. 찌그러진 값은 적지 않고 전에 적어 둔 것을 지킨다 -
  -- 되돌릴 기준이 1칸이 되어 버리면 되돌릴 방법이 없어진다.
  local floor = cfg('side_min_width', 8)
  local keep = g and g.width or nil
  local wid = nil
  if floor > 0 then
    local okw, fixed = pcall(function() return vim.wo[win].winfixwidth end)
    if okw and fixed then
      local now = api.nvim_win_get_width(win)
      wid = now > floor and now or keep
    end
  end
  guarded[win] = {
    buf = buf,
    ft = vim.bo[buf].filetype,
    kind = kind_of(buf),
    width = wid,
    reopen = REOPEN[vim.bo[buf].filetype] or REOPEN[kind_of(buf)],
  }
end

-- 곁창이 한두 칸으로 뭉개졌으면 원래 폭으로 되돌린다.
--
-- winfixwidth 는 '균등 분할이 이 폭을 건드리지 말라' 는 뜻이지, 이미 줄어든
-- 것을 되돌려 주지는 않는다. 그래서 새 창이 억지로 자리를 빼앗아 가면
-- (NERDTree 가 :e . 로 디렉터리를 가로챌 때가 그렇다 - 실측: aerial 이
-- 35칸에서 1칸이 된다) 그 곁창은 :wincmd = 로도 영영 안 돌아왔다.
-- F9/F10 으로 껐다 켜는 수밖에 없었다.
--
-- '조금 줄어든 것' 은 건드리지 않는다. RelationView 의 w(wide) 토글이
-- 일부러 줄이는 폭이 그 자리다(실측: 같은 aerial 이 35 -> 43 -> 31 -> 20
-- 으로 오간다). 여기서 되돌리는 것은 쓸 수 없게 뭉개진 경우뿐이다.
--
--   let g:vimide_side_min_width = 0    " 이 되돌리기를 끈다
--   let g:vimide_side_min_width = 12   " 더 일찍 되돌린다
local function unsquash(win)
  local g = guarded[win]
  if not (g and g.width) or not api.nvim_win_is_valid(win) then
    return
  end
  local floor = cfg('side_min_width', 8)
  if floor <= 0 or g.width <= floor then
    return
  end
  local ok, fixed = pcall(function() return vim.wo[win].winfixwidth end)
  if not ok or not fixed then
    return
  end
  if api.nvim_win_get_width(win) > floor then
    return
  end
  pcall(api.nvim_win_set_width, win, g.width)
end

-- 곁창에 실린 파일을 EDIT 창으로 옮기고 곁창을 되돌린다
local function rescue(win)
  local g = guarded[win]
  if not g then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  if buf == g.buf then
    return -- 아직 제자리다
  end
  if is_plugin_buf(buf) then
    -- 곁창 자리에 들어온 것이 또 곁창 버퍼다. 두 경우가 있다.
    --
    --   같은 플러그인이 제 버퍼를 갈아 끼운 것 - NERDTree 새로 고침,
    --   quickfix 다시 열기, neo-tree 가 source 를 바꾼 것. 그냥 둔다.
    --
    --   낯선 특수 버퍼가 들어앉은 것 - aerial 창에서 :e . 를 쳐서
    --   NERDTree 가 그 자리를 먹거나, :term 으로 터미널이 들어앉은 경우.
    --   이것은 되돌려야 한다.
    --
    -- '아는 것만 잡는' 목록으로 간다. 한때 이것을 뒤집어 '같은 filetype 일
    -- 때만 놓아주고 나머지는 전부 잡는' 쪽으로 해 봤는데, 배치를 세우는
    -- 동안 한 창이 여러 역할을 거치는 것까지 침입으로 읽혀 F12 배치가
    -- 통째로 무너졌다(실측: 편집 창이 사라지고 트리와 패널이 두 개씩).
    -- 곁창을 세우는 플러그인은 제 창을 그렇게 돌려 쓴다.
    local ft = vim.bo[buf].filetype
    local bt = vim.bo[buf].buftype
    local intruder = TAKEOVER_FT[ft] or bt == 'terminal'
        or ft == 'help' or ft == 'man'
    if not intruder or ft == g.ft then
      return
    end
  end

  -- 되돌리기 전에 커서를 기억해 둔다. 사용자가 보려던 자리다.
  local pos = api.nvim_win_get_cursor(win)
  -- 곁창 버퍼가 이미 지워져 '되돌리기' 대신 '다시 세우기' 를 해야 하는가
  local reopen_after = false

  -- 곁창을 원래대로.
  --
  -- quickfix 버퍼는 창이 빼앗기는 순간 함께 사라진다(실측: 되돌릴 버퍼가
  -- 이미 무효). 그때는 되살릴 것이 없으니 그 창을 닫는다 - 같은 파일이
  -- 두 창에 뜬 채 남는 것보다 낫다.
  if g.buf and api.nvim_buf_is_valid(g.buf) then
    -- winfixbuf 는 침입을 못 막는다. netrw 는 :enew! 로 새 버퍼를 만들어
    -- 그냥 뚫고 들어온다(netrw.vim 의 s:NetrwEditFile). 그런데 되돌릴
    -- 때는 그 winfixbuf 가 우리를 막아, '침입은 되고 복구는 안 되는'
    -- 순손해가 된다. 되돌리는 동안만 끄고 원래대로 돌려 놓는다.
    local fixed = false
    pcall(function() fixed = vim.wo[win].winfixbuf end)
    if fixed then
      pcall(function() vim.wo[win].winfixbuf = false end)
    end
    local ok = pcall(api.nvim_win_set_buf, win, g.buf)
    if fixed and api.nvim_win_is_valid(win) then
      pcall(function() vim.wo[win].winfixbuf = true end)
    end
    if not ok or api.nvim_win_get_buf(win) ~= g.buf then
      -- 되돌리지 못했다(winfixbuf 가 걸린 창에 :b!N 을 직접 친 경우 등).
      -- 여기서 포기하지 않으면 창을 옮길 때마다 rescue 가 다시 깨어나
      -- 매번 포커스를 빼앗는다. 한 번만 알리고 그 창은 놓아준다.
      guarded[win] = nil
      vim.notify('이 창은 원래대로 되돌리지 못했습니다 (g:vimide_win_guard)',
        vim.log.levels.WARN)
      return
    end
  elseif BORROWED_FT[g.ft or ''] or not g.reopen then
    -- 곁창 버퍼가 사라졌는데, 그것이 '편집 자리를 빌려 쓰던' 플러그인이다
    -- = 이 창을 돌려준 것이다.
    --
    -- F6 의 BufExplorer 가 그렇다. 편집 창을 잠시 빌려 목록을 띄우고,
    -- 고른 파일을 바로 그 자리에 연 뒤 자기 버퍼는 지운다. 그러면 여기서
    -- 되돌릴 것이 없다.
    --
    -- 예전에는 그 창을 닫고 파일을 딴 창에 다시 열었는데, 그 바람에
    -- aerial 과 EDIT 창이 자리를 맞바꿨다(실측: 고른 뒤 tcc_mem.c 가 열0,
    -- aerial 이 열64 로 튀었다). 돌려준 창은 그냥 놓아준다.
    --
    -- 다시 세울 명령(g.reopen)이 없는 곁창도 여기로 온다. 되살릴 길이
    -- 없으니 건드리지 않는 편이 낫다.
    guarded[win] = nil
    return
  else
    -- 진짜 곁창인데 제 버퍼가 함께 지워졌다. aerial 창에서 :cnext 를
    -- 치면 그렇다 - 아웃라인이 사라지고 그 16칸짜리 좁은 자리에 소스가
    -- 실린 채 남으며, 그 창은 이제 EDIT 창 취급이라 다시는 보호받지
    -- 못했다. 파일은 편집 자리로 옮기고, 이 창은 닫은 뒤 곁창을 다시
    -- 세운다(아래 g.reopen).
    reopen_after = true
  end

  -- 그 파일은 '직전에 보던 EDIT 창'에 연다.
  --
  -- 이 창(win) 자신은 빼야 한다. reopen_after 일 때 win 은 이미 파일을
  -- 들고 있어서 EDIT 창처럼 보이고, 그대로 고르면 '제자리에 그대로 두는'
  -- 것이 되어 곁창이 영영 안 돌아온다.
  local target
  if type(_G.vimide_last_edit_win) == 'function' then
    local ok, w = pcall(_G.vimide_last_edit_win)
    if ok and w and w ~= 0 and w ~= win and _G.vimide_is_edit_win(w) then
      target = w
    end
  end
  if not target then
    target = _G.vimide_edit_wins(win)[1]
  end
  if not target then
    -- EDIT 창이 하나도 없다: 하나 만든다. 여기서 포기하면 사용자가 연
    -- 파일이 아무 데도 안 뜬 채 사라진다.
    local ok = pcall(function()
      vim.cmd('noautocmd topleft vertical split')
      target = api.nvim_get_current_win()
    end)
    if not ok or not target then
      return
    end
    -- :split 은 지금 창의 창 옵션을 물려준다. 곁창에서 갈랐으면 winfixbuf
    -- 까지 따라와, 정작 그 창에 파일을 못 넣는다.
    for _, o in ipairs({ 'winfixbuf', 'winfixwidth', 'winfixheight',
      'previewwindow' }) do
      pcall(function() vim.wo[target][o] = false end)
    end
  end
  -- 세 번의 pcall 을 따로 두면 안 된다. 버퍼를 못 넣었는데 커서와 포커스만
  -- 옮기면, 사용자는 열려던 파일 대신 엉뚱한 창에 끌려가 있게 된다.
  if not pcall(api.nvim_win_set_buf, target, buf) then
    vim.notify('파일을 EDIT 창으로 옮기지 못했습니다 (g:vimide_win_guard)',
      vim.log.levels.WARN)
    return
  end
  pcall(api.nvim_win_set_cursor, target, pos)
  pcall(api.nvim_set_current_win, target)

  -- 곁창 버퍼가 이미 지워져 되돌리지 못했으면, 그 창을 닫고 곁창을 새로
  -- 세운다. 파일은 바로 위에서 편집 자리로 옮겨 놓았으니 여기서 닫아도
  -- 잃는 것이 없다. EDIT 창은 target 이 지키고 있어 '최소 1개' 규칙도
  -- 걸리지 않는다.
  if reopen_after then
    guarded[win] = nil
    -- 창을 닫는 것은 되돌릴 수 없다. 확실할 때만 한다 - 나가는 중도
    -- 복구 중도 아니고, 닫아도 창이 둘은 남을 때.
    if not busy() and api.nvim_win_is_valid(win)
        and #api.nvim_tabpage_list_wins(0) > 2 then
      pcall(api.nvim_win_close, win, false)
    end
  end

  -- 닫아 버린 곁창은 다시 세워 준다. 보던 중이었을 테니까.
  if g.reopen and not api.nvim_win_is_valid(win) then
    pcall(vim.cmd, 'silent! ' .. g.reopen)
    pcall(api.nvim_set_current_win, target)
  end
end

-- 탭의 모든 창을 한 번 훑는다.
--
-- 지금 창만 보면 모자란다 - 포커스를 준 적 없는 곁창은 기록조차 안 되고,
-- 파일이 실려도 아무도 모른다.
-- '적기' 와 '되돌리기' 를 갈라 둔다.
--
-- 예전에는 busy()(세션 복구 중 / 나가는 중) 면 둘 다 건너뛰었다. 그러면
-- 복구 직후 수백 ms 동안(사이드카가 깨졌으면 15초) 곁창이 장부에 한 줄도
-- 안 적히고, 그 사이에 곁창에 파일이 실리면 되돌릴 근거가 없어 영영 그대로
-- 남았다. 창을 옮기는 것만 미루고, 장부는 그때도 적는다.
local function sweep(note_only)
  if sweeping then
    return
  end
  sweeping = true
  if not (note_only or busy()) then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if guarded[w] then
        pcall(rescue, w)
      end
    end
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    pcall(remember, w)
  end
  if not (note_only or busy()) then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      pcall(unsquash, w)
    end
  end
  sweeping = false
end

-- 디렉터리 버퍼가 곁창에 들어오려 한다: 가로채는 쪽이 손대기 전에 넘긴다.
--
-- :e . / :edit <디렉터리> 는 특히 나쁘다. nvim 0.12 에는 netrw 대신
-- NERDTree 가 디렉터리를 가로채는데(NERDTreeHijackNetrw), 그것이 곁창의
-- 버퍼를 바꾸는 데 그치지 않고 그 창을 아예 없앤다. 없어진 창은 사후
-- 복구가 되돌릴 수 없다.
--
-- .vimrc 의 명령줄 약어가 사람이 곧게 친 :e . 는 이미 EDIT 창으로 돌린다.
-- 여기는 그 그물을 빠져나가는 나머지다 - ':' <Up> 으로 되부른 것,
-- 남의 플러그인이 :execute 'edit '.dir 로 부르는 것, :0Ex 처럼 카운트가
-- 붙어 약어가 아예 안 터지는 것.
--
-- 이 augroup 은 NERDTreeHijackNetrw / FileExplorer 보다 먼저 돈다
-- (실측: :autocmd BufEnter 에서 VimIdeWinGuard 가 그 둘보다 위).
local function divert_dir()
  local win = api.nvim_get_current_win()
  local g = guarded[win]
  if not g then
    return -- 원래 곁창이 아니었다
  end
  local buf = api.nvim_get_current_buf()
  if buf == g.buf then
    return -- 제자리다
  end
  local name = api.nvim_buf_get_name(buf)
  if name == '' or vim.fn.isdirectory(name) ~= 1 then
    return -- 디렉터리가 아니면 사후 복구(rescue)가 맡는다
  end
  local target = _G.vimide_edit_slot()
  if target == 0 or target == win or not api.nvim_win_is_valid(target) then
    return
  end
  -- 곁창을 제자리로. 여기는 BufEnter 안이라 자동명령을 꺼야 한다 -
  -- 안 그러면 이 함수가 제 손으로 다시 불린다.
  local ei = vim.o.eventignore
  vim.o.eventignore = 'all'
  if g.buf and api.nvim_buf_is_valid(g.buf) then
    local fixed = false
    pcall(function() fixed = vim.wo[win].winfixbuf end)
    if fixed then
      pcall(function() vim.wo[win].winfixbuf = false end)
    end
    pcall(api.nvim_win_set_buf, win, g.buf)
    if fixed and api.nvim_win_is_valid(win) then
      pcall(function() vim.wo[win].winfixbuf = true end)
    end
  end
  pcall(api.nvim_set_current_win, target)
  vim.o.eventignore = ei
  -- 편집 자리에서 원래 하려던 것을 한다
  vim.schedule(function()
    if api.nvim_win_is_valid(target) then
      pcall(api.nvim_set_current_win, target)
      pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(name))
    end
  end)
end

-- 지금 무엇을 지키고 있는지. 시험과 문제 추적용이다.
function _G.vimide_win_guard_state()
  local out = {}
  for w, g in pairs(guarded) do
    out[#out + 1] = string.format('%d=%s(%s)', w,
      (g.buf and api.nvim_buf_is_valid(g.buf)) and tostring(g.buf) or 'dead', g.kind)
  end
  table.sort(out)
  return table.concat(out, ' ')
end

api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'WinEnter', 'WinNew' }, {
  group = api.nvim_create_augroup('VimIdeWinGuard', { clear = true }),
  callback = function()
    if cfg('win_guard', 1) == 0 then
      return
    end
    -- 디렉터리 가로채기는 여기서 막는다. 뒤로 미루면 늦는다.
    if not sweeping then
      sweeping = true
      pcall(divert_dir)
      sweeping = false
    end
    -- 장부는 지금 당장 적는다.
    --
    -- 한 줄/한 매핑으로 곁창을 열고 곧바로 파일을 여는 경우가 있다
    -- (:copen | e tcc_mem.c). 적는 것까지 vim.schedule 로 미루면 그
    -- 사이에 파일이 실려, 곁창이 장부에 오르기도 전에 사라진다.
    if not sweeping then
      sweeping = true
      pcall(remember, api.nvim_get_current_win())
      sweeping = false
    end
    -- 되돌리는 것은 한 틱 미룬다. 곁창을 세우는 플러그인은 먼저 보통
    -- 버퍼를 :edit 로 띄우고 그 다음에 buftype 을 박는다(NERDTree 가
    -- 그렇다). 그 찰나에 판정하면 멀쩡한 곁창을 '파일이 실렸다'고
    -- 오해한다.
    vim.schedule(function()
      if cfg('win_guard', 1) == 0 then
        return
      end
      sweep()
    end)
  end,
  desc = '곁창에 실린 파일을 직전 EDIT 창으로 되돌린다',
})

api.nvim_create_autocmd('WinClosed', {
  group = 'VimIdeWinGuard',
  callback = function(a)
    guarded[tonumber(a.match) or -1] = nil
  end,
  desc = '닫힌 창의 기록을 지운다',
})

-- ---------------------------------------------------------------------------
-- 곁들이: 마우스가 nvim 까지 오는지 본다  (:VimIdeMouseCheck)
-- ---------------------------------------------------------------------------
-- '클릭해도 커서가 안 움직인다' 는 원인이 여럿이라 말로는 안 갈린다.
-- nvim 은 터미널 종류와 상관없이 마우스 보고를 켜고(실측: TERM 이 무엇이든
-- ^[[?1002h ^[[?1006h 를 쓴다), tmux 도 자기 mouse 옵션과 무관하게 앱이
-- 요청했으면 그대로 넘겨 준다(실측: 중첩 tmux 로 확인). 그러니 남는 고리는
-- 터미널 프로그램 자신이다 - 그것을 여기서 직접 확인한다.
-- 지금 누가 마우스 키를 잡고 있나. 전역 매핑만 본다(버퍼 지역은 그 창에서만 산다).
local MOUSE_KEYS = { '<LeftMouse>', '<LeftDrag>', '<LeftRelease>',
  '<2-LeftMouse>', '<3-LeftMouse>', '<4-LeftMouse>',
  '<ScrollWheelUp>', '<ScrollWheelDown>' }

local function who(key, mode)
  local d = vim.fn.maparg(key, mode, false, true)
  if type(d) ~= 'table' or not d.lhs then
    return nil
  end
  if d.desc and d.desc ~= '' then
    return d.desc
  end
  if d.rhs and d.rhs ~= '' then
    return d.rhs
  end
  if d.callback then
    -- 누구 것인지 파일 이름으로라도 알려 준다
    local info = debug.getinfo(d.callback, 'S')
    return 'lua ' .. tostring(info and info.short_src or '?')
        .. ':' .. tostring(info and info.linedefined or '?')
  end
  return '(?)'
end

local function mouse_maps()
  local out = {}
  for _, k in ipairs(MOUSE_KEYS) do
    local w = who(k, 'n')
    if w then
      out[#out + 1] = '  ' .. k .. '  ->  ' .. w
    end
  end
  if #out == 0 then
    return '  (전역 마우스 매핑 없음)'
  end
  return table.concat(out, '\n')
end

-- 매핑 층이 범인인지 한 세션 안에서 가른다. 다시 띄울 필요 없이 지금 끈다.
api.nvim_create_user_command('VimIdeMouseOff', function()
  local n = 0
  for _, k in ipairs(MOUSE_KEYS) do
    for _, m in ipairs({ 'n', 'i', 'v' }) do
      if pcall(vim.keymap.del, m, k) then
        n = n + 1
      end
    end
  end
  print(('전역 마우스 매핑 %d개를 지웠습니다. 이제 클릭과 드래그를 해 보세요.'):format(n))
  print('되살리려면 nvim 을 다시 띄우면 됩니다.')
  print('이걸로 정상이 되면 범인은 매핑입니다:')
  print('  let g:overview_mouse = 0            " 막대 쪽')
  print('  let g:relationview_global_mouse = 0  " [+] 한 번 클릭 쪽')
end, { desc = '전역 마우스 매핑을 지금 전부 끈다 (원인 가리기)' })

api.nvim_create_user_command('VimIdeMouseCheck', function()
  local v = vim.version()
  print('── 마우스 진단 ──')
  print('TERM   = ' .. tostring(vim.env.TERM))
  print('TMUX   = ' .. (vim.env.TMUX and '있음' or '없음'))
  print('mouse  = ' .. vim.o.mouse .. '   (a 여야 정상)')
  print('nvim   = ' .. string.format('%d.%d.%d', v.major, v.minor, v.patch))
  print('')
  print('이제 이 창 아무 데나 왼쪽 버튼으로 한 번 클릭하세요.')
  print('(아무 일도 안 일어난 채 멈춘 것처럼 보이면, 아무 키나 눌러 빠져나오세요)')
  vim.cmd('redraw')
  local ok, ch = pcall(vim.fn.getcharstr)
  if not ok then
    print('입력을 못 받았습니다: ' .. tostring(ch))
    return
  end
  local shown = (vim.fn.exists('*keytrans') == 1) and vim.fn.keytrans(ch)
      or vim.inspect(ch)
  print('')
  print('받은 것 = ' .. shown)
  print('')
  print('── 지금 마우스 키를 잡고 있는 매핑 ──')
  print(mouse_maps())
  if shown:match('Mouse') then
    print(string.format('창=%d 줄=%d 칸=%d', vim.v.mouse_win, vim.v.mouse_lnum,
      vim.v.mouse_col))
    print('=> 마우스가 nvim 까지 옵니다. 터미널은 정상입니다.')
  else
    print('=> 클릭이 아니라 키가 들어왔습니다.')
    print('   터미널이 마우스 이벤트를 안 보내고 있습니다:')
    print('   * 테라텀: 설정 > 기타 설정 > 마우스 - 마우스 이벤트 추적을 켠다')
    print('             (SGR 확장은 4.87 이상이어야 합니다)')
    print('   * iTerm2: Settings > Profiles > Terminal - Enable mouse reporting')
  end
end, { desc = '마우스가 nvim 까지 오는지 본다' })

-- ---------------------------------------------------------------------------
-- 2. EDIT 창이 0개가 되면 끝낸다
-- ---------------------------------------------------------------------------
-- 지금은 편집 창을 전부 닫아도 nvim 이 안 죽는다. neo-tree 와 RelationView
-- 만 남은 채로 살아 있고, 그 상태에서는 파일을 열 자리도 없다.
--
-- 함정이 여럿이라 하나씩 막는다(전부 실측으로 확인한 것들이다):
--
--   * WinClosed 콜백 '안'에서 :qa 를 부르면 QuitPre/ExitPre/VimLeavePre/
--     VimLeave 가 통째로 건너뛰어진다. 세션이 저장되지 않고 gtags 자식과
--     autoindex 락이 고아로 남는데 종료 코드는 0 이라 겉보기엔 멀쩡하다.
--     그래서 반드시 한 틱 이상 미뤄서 부른다.
--   * 미룬 뒤에는 다시 센다. 그 사이에 relationview 의 트리 재생성이나
--     세션 복원이 창을 도로 열 수 있다.
--   * 세션 복원 중에는 정상적으로 'EDIT 0개'인 순간이 생긴다(세션 파일 첫
--     줄의 `silent only` 가 하필 편집 창부터 닫는다. 실측 3회).
--   * 미저장 버퍼가 숨어 있으면 :qa 가 E37 로 실패한다. 그때 그냥 두면
--     'EDIT 창도 없고 나갈 수도 없는' 상태가 된다 - 그 버퍼를 띄워 준다.
--
-- :qa / :wqa / :xa 와는 겹치지 않는다. 그 명령들은 창을 하나씩 닫지 않아
-- WinClosed 를 한 번도 쏘지 않는다(실측).

local pending = false

local function dirty_bufs()
  local out = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    -- acwrite 도 센다. fugitive 의 커밋 버퍼, 원격 편집(scp://), diffview 가
    -- 그것을 쓰는데 vim 은 이것도 '저장 안 함' 으로 치고 :qa 를 E37 로 막는다.
    -- 안 세면 pcall 이 그 오류를 삼켜, 나갈 수도 없고 보여 줄 창도 없는
    -- 상태로 남는다.
    local bt = vim.bo[b].buftype
    if api.nvim_buf_is_loaded(b) and vim.bo[b].modified
        and (bt == '' or bt == 'acwrite') then
      out[#out + 1] = b
    end
  end
  return out
end

api.nvim_create_autocmd('WinClosed', {
  group = api.nvim_create_augroup('VimIdeMinEdit', { clear = true }),
  callback = function(a)
    if cfg('min_edit_win', 1) == 0 or pending or busy() then
      return
    end
    -- 닫히는 그 창이 EDIT 창이었을 때만 따진다.
    --
    -- 이것이 없으면 'EDIT 창은 이미 0인데 곁창 하나가 닫히는' 아무 순간에도
    -- 규칙이 깨어난다. 실제로 F6 을 누르면 BufExplorer 가 하나뿐인 편집 창을
    -- 제자리에서 차지해 EDIT 이 0이 되고, 그 직후 overview 막대(부동 창)가
    -- 닫히면서 vim 이 통째로 꺼졌다.
    --
    -- WinClosed 는 창이 아직 목록에 있을 때 뜨므로 여기서 물어볼 수 있다.
    local dying = tonumber(a.match)
    if not (dying and _G.vimide_is_edit_win(dying)) then
      return
    end
    -- 세는 것은 반드시 탭 전체다(지금 탭만 보면 남의 탭까지 끄게 된다).
    if _G.vimide_edit_win_count_all(dying) > 0 then
      return
    end
    pending = true
    -- 120ms: vim.schedule 한 틱으로는 relationview 의 '트리 닫고 다시 열기'
    -- 와 같은 큐에 들어가 순서가 안 정해진다. 조금 더 미뤄 두고 다시 센다.
    vim.defer_fn(function()
      pending = false
      if cfg('min_edit_win', 1) == 0 or busy() then
        return
      end
      if _G.vimide_edit_win_count_all() > 0 then
        return -- 누가 도로 열어 주었다
      end
      -- 돌아가는 터미널이 있으면 끝내지 않는다. 사용자는 편집 창 하나를
      -- 닫았을 뿐인데 빌드나 ssh 가 말없이 죽으면 안 된다.
      if _G.vimide_has_live_terminal() then
        vim.notify('EDIT 창이 없지만 터미널 창이 있어 끝내지 않았습니다',
          vim.log.levels.WARN)
        return
      end
      local dirty = dirty_bufs()
      if #dirty > 0 then
        -- 저장 안 한 것이 있으면 끝내지 않는다. :qa 는 어차피 E37 로
        -- 막히고, 그 상태로 두면 보여 줄 창조차 없다.
        pcall(function()
          vim.cmd('noautocmd topleft split')
          api.nvim_win_set_buf(api.nvim_get_current_win(), dirty[1])
        end)
        vim.notify(
          ('EDIT 창이 없지만 저장하지 않은 버퍼가 %d개 있어 끝내지 않았습니다')
          :format(#dirty), vim.log.levels.WARN)
        return
      end
      -- 여기서의 :qa 는 WinClosed 밖이라 VimLeavePre 가 정상으로 돈다
      -- (세션 저장, gtags 자식 정리, autoindex 락 해제).
      pcall(vim.cmd, 'qa')
    end, 120)
  end,
  desc = 'EDIT 창이 0개가 되면 vim 을 끝낸다',
})

-- ---------------------------------------------------------------------------
-- 초점이 어디로, 누가 옮겼는지 적어 둔다 (기본 꺼짐)
-- ---------------------------------------------------------------------------
-- '커서가 다른 창으로 갔다가 돌아온다' 같은 것은 가끔 일어나서 그 순간을
-- 붙잡기 어렵다. 켜 두고 평소처럼 쓰다가 그 일이 나면 :VimIdeFocusLog 로
-- 보면 된다. 창이 바뀔 때마다 '어디서 어디로' 와 그것을 부른 lua 스택을
-- 적는다 - 스택이 비어 있으면 사람이 옮긴 것이고, 파일 이름과 줄 번호가
-- 찍혀 있으면 그 코드가 옮긴 것이다.
--
-- 적는 것은 메모리 안이고 마지막 g:vimide_focus_log_max 개만 남는다.
-- 파일에 쓰지 않으므로 켜 둔 채로 두어도 디스크를 건드리지 않는다.
--
--   let g:vimide_focus_log = 1        " 켜기 (기본 0)
--   let g:vimide_focus_log_max = 400  " 남길 줄 수
--   :VimIdeFocusLog                   " 적힌 것을 새 창에 펼친다
--   :VimIdeFocusLog!                  " 지우고 다시 시작한다
local focus_log = {}
local focus_prev = nil

local function win_tag(w)
  if not (w and api.nvim_win_is_valid(w)) then
    return tostring(w) .. '(없음)'
  end
  local b = api.nvim_win_get_buf(w)
  local ft = vim.bo[b].filetype
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ':t')
  return ('%d[%s%s]'):format(w, ft ~= '' and ft or (vim.bo[b].buftype ~= ''
    and vim.bo[b].buftype or 'edit'), name ~= '' and (' ' .. name) or '')
end

api.nvim_create_autocmd('WinEnter', {
  group = api.nvim_create_augroup('VimIdeFocusLog', { clear = true }),
  callback = function()
    if cfg('focus_log', 0) == 0 then
      return
    end
    local now = api.nvim_get_current_win()
    if now == focus_prev then
      return
    end
    -- 스택에서 이 콜백 자신과 nvim 다리는 빼고, 한 줄로 눕힌다
    local tb = debug.traceback('', 2) or ''
    tb = tb:gsub('^%s*stack traceback:%s*', ''):gsub('%s*\n%s*', ' < ')
    tb = tb:gsub('%[C%]: in function ', ''):gsub('/home/[^/]+/', '~/')
    if tb:find('^%s*$') then
      tb = '(사람이 옮김)'
    end
    focus_log[#focus_log + 1] = ('%8.2f  %s -> %s   %s'):format(
      (vim.uv or vim.loop).now() / 1000, win_tag(focus_prev), win_tag(now),
      tb:sub(1, 400))
    focus_prev = now
    local max = tonumber(cfg('focus_log_max', 400)) or 400
    while #focus_log > max do
      table.remove(focus_log, 1)
    end
  end,
  desc = '초점이 옮겨간 자취 (g:vimide_focus_log)',
})

api.nvim_create_user_command('VimIdeFocusLog', function(a)
  if a.bang then
    focus_log = {}
    vim.notify('초점 기록을 지웠습니다')
    return
  end
  if cfg('focus_log', 0) == 0 then
    vim.notify("꺼져 있습니다: let g:vimide_focus_log = 1 로 켜세요",
      vim.log.levels.WARN)
  end
  if #focus_log == 0 then
    vim.notify('적힌 것이 없습니다')
    return
  end
  local lines = { '초점이 옮겨간 자취 (최근 ' .. #focus_log .. '줄)', '' }
  for _, l in ipairs(focus_log) do
    lines[#lines + 1] = l
  end
  -- EDIT 창을 빼앗지 않도록 아래에 가로로 연다
  vim.cmd('botright new')
  local b = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].buftype = 'nofile'
  vim.bo[b].bufhidden = 'wipe'
  vim.bo[b].swapfile = false
  vim.bo[b].modifiable = false
  pcall(api.nvim_buf_set_name, b, 'VimIde-FocusLog')
end, { bang = true, desc = '초점이 옮겨간 자취를 보여준다' })
