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
local function sign_rows(buf, per)
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
  local blank = string.rep(' ', width)
  local rows = {}
  for i = 1, height do
    rows[i] = blank
  end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, rows)
  vim.bo[s.buf].modifiable = false

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
    pcall(api.nvim_win_set_config, s.win, wcfg)
  else
    local ok, w = pcall(api.nvim_open_win, s.buf, false, wcfg)
    if not ok then
      return
    end
    s.win = w
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

local function schedule()
  if s.timer then
    s.timer:stop()
    s.timer:close()
    s.timer = nil
  end
  s.timer = uv.new_timer()
  s.timer:start(30, 0, function()
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
  api.nvim_win_call(s.target, function()
    api.nvim_win_set_cursor(s.target, { line, 0 })
    vim.cmd(center and 'normal! zz' or 'normal! zt')
  end)
  -- 누르고 있는 동안에는 초점을 막대에 둔다.
  --
  -- 부동 창이 클릭을 받으려면 focusable 이어야 하고, 클릭은 그 창으로
  -- 초점을 옮긴다. 여기서 바로 편집 창으로 되돌리면 그 다음 <LeftDrag> 이
  -- 편집 창으로 가 버려서 막대의 매핑이 불리지 않는다 - 드래그가 통째로
  -- 죽는다(실측: 아래에서 위로 끌어도 첫 클릭 자리에 머물렀다).
  -- 그래서 <LeftRelease> 에서만 되돌린다.
  if not s.dragging then
    api.nvim_set_current_win(s.target)
  end
  schedule()
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
          if s.target and api.nvim_win_is_valid(s.target) then
            api.nvim_set_current_win(s.target)
          end
        end
        return key -- 막대가 아니면 원래 동작
      end
      if key == '<ScrollWheelUp>' or key == '<ScrollWheelDown>' then
        -- 막대 위에서 휠: 편집 창을 굴린다
        if s.target and api.nvim_win_is_valid(s.target) then
          api.nvim_win_call(s.target, function()
            vim.cmd('normal! ' .. (key == '<ScrollWheelUp>' and '3\22y' or '3\22e'))
          end)
          schedule()
        end
      elseif key == '<LeftRelease>' then
        s.dragging = false
      else
        s.dragging = true
        vim.schedule(function()
          local ok, err = pcall(goto_row, r, key == '<LeftMouse>')
          if not ok then
            dbg('goto 실패: ' .. tostring(err))
          end
        end)
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
  callback = function() schedule() end,
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
