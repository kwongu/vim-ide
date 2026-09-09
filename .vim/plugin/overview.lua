-- overview.lua - Source Insight / VSCode 의 Overview 막대.
--
-- 편집 창 오른쪽 끝에 파일 전체를 나타내는 얇은 막대를 띄운다. 지금 보고
-- 있는 구간이 밝게, 커서 줄이 진하게, 변경된 줄과 진단이 색으로 찍힌다.
-- 막대를 클릭하거나 끌면 편집 창이 그 위치로 움직인다.
--
--   <Leader>b        막대 켜기/끄기
--   :OverviewToggle  같은 것
--   막대에서 클릭/드래그  그 위치로 이동
--   막대에서 휠         편집 창 스크롤
--
-- 옵션
--   g:overview          0 이면 아무 것도 하지 않는다 (기본 1)
--   g:overview_width    막대 너비, 칸 수 (기본 2)
--   g:overview_min      이 줄 수 아래인 파일에는 띄우지 않는다 (기본 40)
--
-- 색은 지금 쓰는 colorscheme 에서 가져온다(CursorLine / Visual / Cursor /
-- Diff* / Diagnostic*), 그래서 si / light / dark 어디서나 어울린다.
-- 직접 정하려면 OverviewBg / OverviewView / OverviewCursor / OverviewAdd /
-- OverviewChange / OverviewDelete / OverviewError / OverviewWarn 을 덮어쓴다.
--
-- nvim 전용(부동 창과 extmark 를 쓴다). vim 에서는 조용히 빠진다.

if vim.fn.has('nvim') == 0 then
  return
end
if vim.g.loaded_overview == 1 then
  return
end
vim.g.loaded_overview = 1

local api = vim.api
local uv = vim.uv or vim.loop

local function cfg(name, default)
  local v = vim.g['overview' .. (name == '' and '' or '_' .. name)]
  if v == nil or v == '' then
    return default
  end
  return v
end

local map_bar    -- 아래에서 정의; 막대 버퍼를 만들 때 매핑을 붙인다
local goto_row   -- 아래에서 정의
local mouse_row  -- 아래에서 정의

-- g:overview_debug = '<파일>' 이면 마우스 이벤트를 그 파일에 적는다.
-- 부동 창의 getmousepos() 값을 눈으로 확인해야 할 때가 있다.
local function dbg(msg)
  local f = vim.g.overview_debug
  if f == nil or f == '' then
    return
  end
  local fh = io.open(tostring(f), 'a')
  if fh then
    fh:write(msg .. '\n')
    fh:close()
  end
end

local NS = api.nvim_create_namespace('Overview')
local s = {
  buf = nil,     -- 막대 버퍼
  win = nil,     -- 막대 창
  target = nil,  -- 이 막대가 붙어 있는 편집 창
  timer = nil,
  on = cfg('', 1) ~= 0,
  dragging = false,
}

-- ---------------------------------------------------------------------------
-- 색
-- ---------------------------------------------------------------------------
-- colorscheme 에서 배경색을 빌려 온다. 없으면 그 다음 후보로.
local function bg_of(names, field)
  for _, n in ipairs(names) do
    local ok, h = pcall(api.nvim_get_hl, 0, { name = n, link = false })
    if ok and h then
      local c = h[field or 'bg'] or (field == nil and h.fg or nil)
      if c then
        return c
      end
    end
  end
  return nil
end

local function set_hl()
  local function def(name, opts)
    if next(opts) == nil then
      return
    end
    opts.default = true
    pcall(api.nvim_set_hl, 0, name, opts)
  end
  def('OverviewBg', { bg = bg_of({ 'CursorLine', 'ColorColumn', 'Pmenu' }) })
  def('OverviewView', { bg = bg_of({ 'Visual', 'PmenuSel', 'IncSearch' }) })
  def('OverviewCursor', { bg = bg_of({ 'Cursor', 'CursorLineNr', 'Search' })
      or bg_of({ 'Cursor' }, 'fg') })
  def('OverviewAdd', { bg = bg_of({ 'DiffAdd', 'DiagnosticOk' })
      or bg_of({ 'SignifySignAdd', 'GitSignsAdd' }, 'fg') })
  def('OverviewChange', { bg = bg_of({ 'DiffChange', 'DiagnosticWarn' })
      or bg_of({ 'SignifySignChange', 'GitSignsChange' }, 'fg') })
  def('OverviewDelete', { bg = bg_of({ 'DiffDelete', 'DiagnosticError' })
      or bg_of({ 'SignifySignDelete', 'GitSignsDelete' }, 'fg') })
  def('OverviewError', { bg = bg_of({ 'DiagnosticError', 'ErrorMsg' })
      or bg_of({ 'DiagnosticError' }, 'fg') })
  def('OverviewWarn', { bg = bg_of({ 'DiagnosticWarn', 'WarningMsg' })
      or bg_of({ 'DiagnosticWarn' }, 'fg') })
end

-- ---------------------------------------------------------------------------
-- 어떤 창에 붙일까
-- ---------------------------------------------------------------------------
-- 특수 창(트리, 패널, telescope, quickfix, 도움말, 터미널, 부동 창)에는
-- 붙이지 않는다. 편집 중인 파일 창만 대상이다.
local function is_edit_win(win)
  if not (win and api.nvim_win_is_valid(win)) then
    return false
  end
  local c = api.nvim_win_get_config(win)
  if c and c.relative and c.relative ~= '' then
    return false -- 부동 창
  end
  local buf = api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' then
    return false
  end
  local name = api.nvim_buf_get_name(buf)
  if name:match('RelationView') or name:match('NERD_tree') then
    return false
  end
  local ft = vim.bo[buf].filetype
  if ft == 'neo-tree' or ft == 'tagbar' or ft == 'aerial'
      or ft:match('^Telescope') then
    return false
  end
  return true
end

local function pick_target()
  local cur = api.nvim_get_current_win()
  if is_edit_win(cur) then
    return cur
  end
  if is_edit_win(s.target) then
    return s.target -- 패널에 들어가 있는 동안에도 막대는 남는다
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if is_edit_win(w) then
      return w
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- 그리기
-- ---------------------------------------------------------------------------
local function close()
  if s.win and api.nvim_win_is_valid(s.win) then
    pcall(api.nvim_win_close, s.win, true)
  end
  s.win = nil
end

-- 버퍼에 놓인 sign 을 줄 -> 색으로 바꾼다. signify / gitsigns / 진단 모두
-- sign 을 쓰므로, 이름만 보고 한 곳에서 처리한다.
-- sign 은 저장·진단·편집에서만 바뀐다. 그런데 렌더마다
-- sign_getplaced(buf, {group='*'}) 로 버퍼의 sign 을 통째로 다시 긁고
-- 있었다 - 막대를 끄는 동안에도 매번. 세대 번호로 캐시한다(아래
-- autocmd 가 바뀔 만한 사건에서 번호를 올린다).
local sign_gen = 0
local sign_cache = { key = nil, rows = {} }

local function sign_rows_uncached(buf, per)
  local out = {}
  local ok, placed = pcall(vim.fn.sign_getplaced, buf, { group = '*' })
  if not ok or not placed or not placed[1] then
    return out
  end
  for _, sn in ipairs(placed[1].signs or {}) do
    local n = tostring(sn.name or '')
    local hl
    if n:match('[Aa]dd') then
      hl = 'OverviewAdd'
    elseif n:match('[Dd]elete') or n:match('[Rr]emove') then
      hl = 'OverviewDelete'
    elseif n:match('[Cc]hange') then
      hl = 'OverviewChange'
    elseif n:match('Error') then
      hl = 'OverviewError'
    elseif n:match('Warn') then
      hl = 'OverviewWarn'
    end
    if hl then
      local row = math.floor((sn.lnum - 1) / per)
      -- 진단이 변경 표시를 덮지 않게: 우선순위는 오류 > 경고 > 변경
      local rank = { OverviewChange = 1, OverviewAdd = 1, OverviewDelete = 1,
        OverviewWarn = 2, OverviewError = 3 }
      local cur = out[row]
      if not cur or (rank[hl] or 0) > (rank[cur] or 0) then
        out[row] = hl
      end
    end
  end
  return out
end

local function sign_rows(buf, per)
  local key = ('%d\0%d\0%d\0%d'):format(buf, per, sign_gen,
    vim.b[buf] and vim.b[buf].changedtick or 0)
  if sign_cache.key == key then
    return sign_cache.rows
  end
  local rows = sign_rows_uncached(buf, per)
  sign_cache = { key = key, rows = rows }
  return rows
end

local function render()
  if not s.on then
    close()
    return
  end
  local target = pick_target()
  if not target then
    close()
    return
  end
  s.target = target
  local buf = api.nvim_win_get_buf(target)
  local total = api.nvim_buf_line_count(buf)
  local width = math.max(1, tonumber(cfg('width', 2)) or 2)
  local height = api.nvim_win_get_height(target)
  if total < (tonumber(cfg('min', 40)) or 40) or height < 3 then
    close() -- 짧은 파일에는 막대가 의미 없다
    return
  end

  -- 막대 버퍼
  if not (s.buf and api.nvim_buf_is_valid(s.buf)) then
    s.buf = api.nvim_create_buf(false, true)
    vim.bo[s.buf].bufhidden = 'hide'
    vim.bo[s.buf].filetype = 'overview'
    -- 매핑은 버퍼를 만드는 이 자리에서 붙인다. 예전에는 VimEnter 에서
    -- 한 번만 붙였는데, 그때는 창 배치가 아직 안 잡혀 막대가 없는 일이
    -- 흔해서(버퍼도 없다) 매핑이 통째로 빠졌다 - 클릭이 아무 일도 하지
    -- 않았던 이유다.
    if map_bar then
      pcall(map_bar)
    end
  end
  -- 빈 줄은 높이가 바뀔 때만 다시 쓴다. 예전에는 렌더마다 height 줄을
  -- 통째로 갈아 끼웠는데, 내용이 같아도 버퍼 쓰기는 공짜가 아니다.
  if s.lines_h ~= height or s.lines_w ~= width then
    local blank = string.rep(' ', width)
    local rows = {}
    for i = 1, height do
      rows[i] = blank
    end
    vim.bo[s.buf].modifiable = true
    api.nvim_buf_set_lines(s.buf, 0, -1, false, rows)
    vim.bo[s.buf].modifiable = false
    s.lines_h, s.lines_w = height, width
  end

  -- 창
  local tw = api.nvim_win_get_width(target)
  if tw <= width + 4 then
    close() -- 창이 막대를 두기엔 너무 좁다
    return
  end
  local wcfg = {
    relative = 'win',
    win = target,
    anchor = 'NE',
    row = 0,
    col = tw,
    width = width,
    height = height,
    focusable = true,
    style = 'minimal',
    zindex = 40,
  }
  if s.win and api.nvim_win_is_valid(s.win) then
    -- 배치가 그대로면 건드리지 않는다 (win_set_config 는 매번 창을 다시
    -- 잡는다 - 끄는 동안 이것이 눈에 띄게 쌓인다)
    local key = ('%d\0%d\0%d\0%d'):format(target, tw, width, height)
    if s.wcfg_key ~= key then
      s.wcfg_key = key
      pcall(api.nvim_win_set_config, s.win, wcfg)
    end
  else
    local ok, w = pcall(api.nvim_open_win, s.buf, false, wcfg)
    if not ok then
      return
    end
    s.win = w
    s.wcfg_key = ('%d\0%d\0%d\0%d'):format(target, tw, width, height)
    vim.wo[s.win].winhighlight = 'Normal:OverviewBg,NormalFloat:OverviewBg'
    vim.wo[s.win].winblend = 0
  end

  -- 칠하기
  local per = math.max(1, math.ceil(total / height))
  api.nvim_buf_clear_namespace(s.buf, NS, 0, -1)
  local function paint(row, hl, prio)
    if row >= 0 and row < height then
      pcall(api.nvim_buf_set_extmark, s.buf, NS, row, 0,
        { end_col = width, hl_group = hl, priority = prio or 100,
          hl_eol = true })
    end
  end
  -- 변경/진단
  for row, hl in pairs(sign_rows(buf, per)) do
    paint(row, hl, 110)
  end
  -- 보이는 구간
  local info = vim.fn.getwininfo(target)[1]
  if info then
    local from = math.floor((info.topline - 1) / per)
    local to = math.floor((info.botline - 1) / per)
    -- 파일이 창보다 훨씬 길면 보이는 구간이 한 행으로 눌린다. 한 칸은
    -- 눈에 잘 안 띄므로 최소 두 행은 차지하게 한다(막대 안에서만 넓힌다).
    if height >= 8 and to - from < 1 then
      if to + 1 < height then
        to = to + 1
      elseif from > 0 then
        from = from - 1
      end
    end
    for r = from, to do
      paint(r, 'OverviewView', 120)
    end
  end
  -- 커서 줄
  local ok, pos = pcall(api.nvim_win_get_cursor, target)
  if ok and pos then
    paint(math.floor((pos[1] - 1) / per), 'OverviewCursor', 130)
  end
end

local function schedule(fast)
  if s.timer then
    s.timer:stop()
    s.timer:close()
    s.timer = nil
  end
  s.timer = uv.new_timer()
  -- 끄는 동안에는 더 자주 그린다. 30ms 는 가만히 있을 때는 넉넉하지만
  -- 마우스를 따라갈 때는 눈에 띄게 뒤처진다.
  --   let g:overview_drag_debounce = 8
  local ms = fast and (tonumber(cfg('drag_debounce', 10)) or 10)
      or (tonumber(cfg('debounce', 30)) or 30)
  s.timer:start(ms, 0, function()
    if s.timer then
      s.timer:stop()
      s.timer:close()
      s.timer = nil
    end
    vim.schedule(function() pcall(render) end)
  end)
end

-- ---------------------------------------------------------------------------
-- 마우스
-- ---------------------------------------------------------------------------
-- 막대에서 클릭한 줄로 편집 창을 옮긴다. 부동 창이 클릭을 받으려면
-- focusable 이어야 하므로, 처리한 뒤 초점을 편집 창으로 되돌린다.
goto_row = function(row, center)
  if not (s.target and api.nvim_win_is_valid(s.target)) then
    dbg('goto: target 없음 (' .. tostring(s.target) .. ')')
    return
  end
  local buf = api.nvim_win_get_buf(s.target)
  local total = api.nvim_buf_line_count(buf)
  local height = api.nvim_win_get_height(s.target)
  local per = math.max(1, math.ceil(total / height))
  local line = math.min(total, math.max(1, (row - 1) * per + 1))
  dbg(('goto row=%d total=%d height=%d per=%d -> line=%d target=%s')
    :format(row, total, height, per, line, tostring(s.target)))
  -- 'normal! zz' 대신 winrestview: 명령 한 번이 아니라 값 한 번이고,
  -- normal 이 일으키는 부수 효과가 없다. topline 을 직접 정하므로 화면이
  -- 어디에 놓일지도 분명하다.
  local top
  if center then
    top = math.max(1, line - math.floor(height / 2))
  else
    top = line
  end
  top = math.min(top, math.max(1, total - height + 1))
  s.self_move = true
  api.nvim_win_call(s.target, function()
    pcall(vim.fn.winrestview, { lnum = line, topline = top, col = 0 })
  end)
  s.self_move = false
  -- 누르고 있는 동안에는 초점을 막대에 둔다.
  --
  -- 부동 창이 클릭을 받으려면 focusable 이어야 하고, 클릭은 그 창으로
  -- 초점을 옮긴다. 여기서 바로 편집 창으로 되돌리면 그 다음 <LeftDrag> 이
  -- 편집 창으로 가 버려서 막대의 매핑이 불리지 않는다 - 드래그가 통째로
  -- 죽는다(실측: 아래에서 위로 끌어도 첫 클릭 자리에 머물렀다).
  -- 그래서 <LeftRelease> 에서만 되돌린다.
  if not s.dragging and api.nvim_get_current_win() ~= s.target then
    pcall(api.nvim_set_current_win, s.target)
  end
  schedule(s.dragging)
end


-- 지금 보이는 구간이 막대의 몇 행인가 (render 와 같은 셈)
local function view_rows()
  if not (s.target and api.nvim_win_is_valid(s.target)) then
    return nil
  end
  local buf = api.nvim_win_get_buf(s.target)
  local total = api.nvim_buf_line_count(buf)
  local height = api.nvim_win_get_height(s.target)
  local per = math.max(1, math.ceil(total / height))
  local info = vim.fn.getwininfo(s.target)[1]
  if not info then
    return nil
  end
  return math.floor((info.topline - 1) / per),
      math.floor((info.botline - 1) / per), per, total, height
end

-- 막대의 '보이는 구간' 표시를 끌어서 화면을 옮긴다.
--
-- 예전에는 드래그 중에도 매 이벤트가 절대 점프였다: '이 행이 가리키는 줄을
-- 화면 가운데로'. 그러면 표시를 잡는 순간 그 표시가 손가락 밑에서 튀고,
-- 한 행이 파일의 여러 화면치(3000줄/47행이면 64줄, 창 높이 47줄보다 크다)
-- 라서 끌 때마다 내용이 건너뛴다. 진짜 스크롤바처럼 '잡은 자리를 유지한 채'
-- 표시를 옮긴다.
local function drag_to(row)
  local from, _, per, total, height = view_rows()
  if not from then
    return
  end
  -- mouse_row() 는 1-기반 막대 줄이고 render 의 행은 0-기반이다.
  -- 그 변환을 빼먹으면 잡는 순간 한 행(= per 줄)만큼 튄다.
  local want_top_row = (row - (s.grab_off or 0)) - 1
  local top = math.max(1, want_top_row * per + 1)
  top = math.min(top, math.max(1, total - height + 1))
  s.self_move = true
  api.nvim_win_call(s.target, function()
    local view = vim.fn.winsaveview()
    local lnum = math.min(total, math.max(top, view.lnum))
    lnum = math.min(lnum, top + height - 1)
    pcall(vim.fn.winrestview, { topline = top, lnum = lnum, col = view.col })
  end)
  s.self_move = false
  schedule(true)
end

mouse_row = function()
  local ok, m = pcall(vim.fn.getmousepos)
  if not ok or not m then
    dbg('getmousepos 실패')
    return nil
  end
  dbg(('mouse winid=%s (bar=%s) line=%s col=%s screenrow=%s screencol=%s wrow=%s wcol=%s')
    :format(tostring(m.winid), tostring(s.win), tostring(m.line),
      tostring(m.column), tostring(m.screenrow), tostring(m.screencol),
      tostring(m.winrow), tostring(m.wincol)))
  if s.win and m.winid == s.win then
    return m.line
  end
  return nil
end

local function on_click(center)
  local r = mouse_row()
  if r then
    goto_row(r, center)
  end
end

-- 마우스는 전역 매핑으로 받는다.
--
-- 부동 창을 클릭해도 초점이 그리로 옮겨지지 않고, 게다가 마우스 매핑은
-- '클릭하기 전에 현재였던 버퍼'에서 찾는다. 그래서 막대 버퍼에 걸어 둔
-- 버퍼 지역 매핑은 아무리 제대로 붙어 있어도 절대 불리지 않는다
-- (실측: 매핑 목록에는 <LeftMouse> 가 있는데 핸들러가 한 번도 안 불렸다).
--
-- 그러니 전역에 걸고, 클릭 지점이 막대가 아니면 원래 동작으로 통과시킨다.
-- noremap 으로 걸었으므로 '<LeftMouse>' 를 돌려주면 기본 동작이 실행되고
-- 이 매핑이 다시 불리지는 않는다. 버퍼 지역 매핑(예: RelationView 의
-- 더블클릭)은 전역보다 우선하므로 그대로 살아 있다.
local MOUSE_KEYS = { '<LeftMouse>', '<LeftDrag>', '<LeftRelease>',
  '<ScrollWheelUp>', '<ScrollWheelDown>' }
local mouse_installed = false

-- 드래그는 이벤트가 쏟아진다. 하나마다 vim.schedule 을 걸면 콜백이 쌓여
-- 마지막 위치까지 가는 데 그만큼 밀리고, 지나간 위치를 전부 그리느라
-- 끊겨 보인다. 마지막 요청만 남기고 한 틱에 한 번 처리한다.
local pending_row
local goto_queued = false

local function request_goto(row)
  pending_row = row
  if goto_queued then
    return
  end
  goto_queued = true
  vim.schedule(function()
    goto_queued = false
    local r = pending_row
    pending_row = nil
    if not r then
      return
    end
    -- 클릭과 드래그가 같은 방식이어야 한다. 예전에는 클릭만 가운데(zz)로
    -- 맞추고 드래그는 맨 위(zt)로 붙여서, 누른 뒤 처음 움직이는 순간
    -- 화면이 반 페이지 튀었다.
    local ok, err = pcall(goto_row, r, true)
    if not ok then
      dbg('goto 실패: ' .. tostring(err))
    end
  end)
end

local pending_drag
local drag_queued = false

local function request_drag(row)
  pending_drag = row
  if drag_queued then
    return
  end
  drag_queued = true
  vim.schedule(function()
    drag_queued = false
    local r = pending_drag
    pending_drag = nil
    if r then
      pcall(drag_to, r)
    end
  end)
end

-- 초점을 편집 창으로 되돌린다. expr 매핑 안에서는 금지되므로 미룬다.
local function restore_focus()
  vim.schedule(function()
    if s.dragging then
      return -- 그 사이 다시 끌기 시작했다
    end
    if s.target and api.nvim_win_is_valid(s.target)
        and api.nvim_get_current_win() ~= s.target then
      pcall(api.nvim_set_current_win, s.target)
    end
  end)
end

local function install_mouse()
  if mouse_installed then
    return
  end
  mouse_installed = true
  for _, lhs in ipairs(MOUSE_KEYS) do
    local key = lhs
    vim.keymap.set({ 'n', 'i', 'v' }, key, function()
      local r = mouse_row()
      if not r then
        if key == '<LeftRelease>' and s.dragging then
          s.dragging = false
          -- expr 매핑 안에서는 창을 바꿀 수 없다(textlock). 여기서 바로
          -- 부르면 빠르게 끌 때 이 에러가 난다:
          --   E565: Not allowed to change text or change window
          -- 그래서 잠금이 풀린 뒤로 미룬다.
          restore_focus()
        end
        return key -- 막대가 아니면 원래 동작
      end
      if key == '<ScrollWheelUp>' or key == '<ScrollWheelDown>' then
        -- 막대 위에서 휠: 편집 창을 굴린다
        if s.target and api.nvim_win_is_valid(s.target) then
          api.nvim_win_call(s.target, function()
            -- Ctrl-Y(위로) = \25, Ctrl-E(아래로) = \5.
            -- 예전에는 '3\22y' / '3\22e' 였는데 \22 는 Ctrl-V 다:
            -- 'normal! 3<C-v>y' 가 되어 화면은 그대로 두고 블록을 잡아
            -- yank 해 버렸다. 휠이 아무 일도 안 하는 것처럼 보인 이유다.
            vim.cmd('normal! ' .. (key == '<ScrollWheelUp>' and '3\25' or '3\5'))
          end)
          schedule()
        end
      elseif key == '<LeftRelease>' then
        s.dragging = false
        restore_focus()
      elseif key == '<LeftMouse>' then
        -- 누른 자리가 '보이는 구간' 안이면 그 자리를 잡은 것으로 보고
        -- 옮기지 않는다(스크롤바를 집는 동작). 바깥이면 거기로 간다.
        local from, to = view_rows()
        if from and r >= from + 1 and r <= to + 1 then
          s.grab_off = r - (from + 1)
        else
          s.grab_off = 0
          request_goto(r)
        end
        s.dragging = true
      else
        s.dragging = true
        request_drag(r)
      end
      return '<Ignore>'
    end, { expr = true, replace_keycodes = true, remap = false, silent = true })
  end
end

local function remove_mouse()
  if not mouse_installed then
    return
  end
  mouse_installed = false
  for _, lhs in ipairs(MOUSE_KEYS) do
    for _, m in ipairs({ 'n', 'i', 'v' }) do
      pcall(vim.keymap.del, m, lhs)
    end
  end
end

map_bar = function()
  install_mouse()
end


-- ---------------------------------------------------------------------------
-- 붙이기
-- ---------------------------------------------------------------------------
local group = api.nvim_create_augroup('Overview', { clear = true })

api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'WinScrolled',
  'WinResized', 'VimResized', 'BufWinEnter', 'WinEnter', 'TextChanged',
  'TextChangedI', 'BufWritePost', 'DiagnosticChanged' }, {
  group = group,
  callback = function()
    -- goto_row 가 방금 화면을 옮긴 것이라면 그 스스로 렌더를 예약한다.
    -- 여기서 또 걸면 끄는 동안 렌더가 두 배로 돈다.
    if s.self_move then
      return
    end
    schedule(s.dragging)
  end,
})

-- sign 은 텍스트가 안 바뀌어도 달라진다(비동기 진단, git 작업 뒤 gitsigns).
-- changedtick 만으로는 못 잡으므로 이 사건들에서 캐시를 버린다.
api.nvim_create_autocmd({ 'BufWritePost', 'DiagnosticChanged', 'TextChanged',
  'TextChangedI', 'BufWinEnter' }, {
  group = group,
  callback = function()
    sign_gen = sign_gen + 1
  end,
})

api.nvim_create_autocmd('ColorScheme', {
  group = group,
  callback = function()
    set_hl()
    schedule()
  end,
})

-- 어떤 이유로든 막대에 초점이 남았으면 편집 창으로 돌려보낸다
api.nvim_create_autocmd('CursorHold', {
  group = group,
  callback = function()
    if not s.dragging and s.win and api.nvim_get_current_win() == s.win
        and s.target and api.nvim_win_is_valid(s.target) then
      api.nvim_set_current_win(s.target)
    end
  end,
})

api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(a)
    if tonumber(a.match) == s.win then
      s.win = nil
    end
    schedule()
  end,
})

local function toggle(on)
  if on == nil then
    s.on = not s.on
  else
    s.on = on
  end
  vim.g.overview = s.on and 1 or 0
  if s.on then
    set_hl()
    render()
    map_bar()
    vim.notify('Overview 막대: 켜짐 (막대를 클릭/드래그하면 그 위치로 이동)')
  else
    close()
    remove_mouse()
    vim.notify('Overview 막대: 꺼짐')
  end
end

-- 시험/디버그용: 막대의 n번째 행을 클릭한 것과 같은 동작
function _G.overview_goto(row, center)
  return goto_row(row, center ~= false)
end

api.nvim_create_user_command('OverviewToggle', function() toggle() end,
  { desc = 'Toggle the overview bar on the right of the edit window' })
api.nvim_create_user_command('OverviewOpen', function() toggle(true) end,
  { desc = 'Show the overview bar' })
api.nvim_create_user_command('OverviewClose', function() toggle(false) end,
  { desc = 'Hide the overview bar' })

if vim.fn.maparg('<Leader>b', 'n') == '' then
  vim.keymap.set('n', '<Leader>b', '<Cmd>OverviewToggle<CR>',
    { silent = true, desc = 'overview bar' })
end

api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    vim.defer_fn(function()
      set_hl()
      if s.on then
        pcall(render)
        map_bar()
      end
    end, 400)
  end,
})
