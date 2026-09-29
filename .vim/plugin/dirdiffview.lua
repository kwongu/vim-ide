-- dirdiffview.lua - Beyond Compare 처럼: 두 디렉터리를 나란한 트리로, 바로
--
--   :DirDiff <A> <B>        새 탭: 위는 편집 창 둘(A | B, diff), 아래는 비교 트리
--   neo-tree 에서 \d 두 번  같은 것 (dirdiffpick.lua)
--   :DirDiffClassic <A> <B> 예전 DirDiff.vim 목록 (dirdifftab.vim)
--
-- 아래 창(비교 트리)은 왼쪽이 A, 오른쪽이 B 의 트리다. 같은 줄에 같은 이름이
-- 오고, 한쪽에만 있으면 다른 쪽은 비어 있다. 가운데 칸이 판정이다:
--   =  같다      ≠(x) 다르다      ◀(<) A 에만     ▶(>) B 에만     ·(.) 확인 중
-- 다른 것은 빨강, 한쪽에만 있는 것은 파랑, 확인 중인 것은 흐리게.
--
-- 트리 창의 키
--   <CR>        파일: 위 두 창에 비교를 열고 커서를 편집 창(첫 차이)으로
--               디렉터리: 펼치기/접기
--   o           파일: 비교를 열되 커서는 트리에 그대로
--   <C-n>/<C-p> 다음/앞 '차이' 파일로 (접힌 디렉터리는 펼치며)
--   l / h       펼치기 / 접기(접혀 있으면 부모로)
--   O / X       차이 있는 디렉터리를 모두 펼치기 / 모두 접기 (트리 전체)
--   f           차이만 보기 켜기/끄기
--   <Tab>       A 쪽 / B 쪽 (커서가 그쪽 이름으로. 마우스로 눌러도 된다)
--   <Space>     지금 쪽의 항목 고르기/풀기 (다음 줄로)       U  고른 것 모두 풀기
--   <C-r>/<C-l> A → B / B → A 로 파일·디렉터리 복사: 원본 쪽(A→B 면 A 트리)에서 고른 것,
--               없으면 비주얼 줄, 그것도 없으면 커서 줄. 이름을 보이고 묻고 나서, 뒤쪽이
--               항목마다 안전하게 한다 (같은 이름은 덮어쓰고 디렉터리는 합친다 - 지우지
--               않는다, 제외 목록은 건드리지 않는다, 대상 쪽 링크를 따라가 쓰지 않는다).
--               복사한 곳만 다시 본다
--   R           다시 훑기        q  끝내기(탭을 닫는다)       ?  도움말
-- 편집 창(비교 중인 두 창)에서는 <C-n>/<C-p> 가 ]c/[c (다음/앞 차이), <C-r>/<C-l> 은
-- 커서 줄(비주얼이면 고른 줄)을 오른쪽(B)/왼쪽(A)으로 (diffput/diffget - 저장은 :w).
-- 비교 탭 밖의 <C-r>(되돌리기 취소)·<C-l>(창 옮기기)은 그대로다.
--
-- 빠른 이유는 뒤쪽 dirdiffscan.py 에 적었다: 찾는 대로 보여 주고(펼쳐 둔 디렉터리
-- 먼저), 크기가 다르면 바로 '다름', 크기·시각이 같으면 '같음', 나머지만 뒤에서
-- 내용을 읽는다. 편집기는 한 번도 기다리지 않는다.
--
--   let g:vimide_dirdiff_view = 0          " :DirDiff 를 예전 목록(DirDiff.vim)으로
--   let g:vimide_dirdiff_only_diff = 1     " 처음부터 차이만 보기
--   let g:vimide_dirdiff_trust_mtime = 0   " 크기·시각이 같아도 내용까지 읽기
--   let g:vimide_dirdiff_list_height = 16  " 트리 창 높이 (기본: 화면의 40%)
--   let g:vimide_dirdiff_max_mb = 20       " 이보다 큰 파일은 열지 않고 알림만
--   let g:vimide_dirdiff_confirm_copy = 0  " 트리의 <C-r>/<C-l> 복사를 묻지 않고
--   let g:vimide_dirdiff_copy_keys = 0     " <C-r>/<C-l> 을 가로채지 않기 (편집 창)
--   (제외 목록은 DirDiff.vim 과 같은 g:DirDiffExcludes)

if vim.g.loaded_vimide_dirdiffview then
  return
end
vim.g.loaded_vimide_dirdiffview = 1

local api = vim.api
local uv = vim.uv or vim.loop
local ns = api.nvim_create_namespace('vimide_dirdiffview')
local ns_open = api.nvim_create_namespace('vimide_dirdiffview_open')
local ns_side = api.nvim_create_namespace('vimide_dirdiffview_side')

local M = {}
local sessions = {} -- tabpage handle -> session

local BAD = { diff = true, onlyA = true, onlyB = true }

local function ascii()
  return (tonumber(vim.g.vimide_ascii_icons) or 0) ~= 0
end

local function sym(st)
  if ascii() then
    return ({ same = '=', diff = 'x', onlyA = '<', onlyB = '>', pend = '.' })[st] or ' '
  end
  return ({ same = '=', diff = '≠', onlyA = '◀', onlyB = '▶', pend = '·' })[st] or ' '
end

local function fold_icon(open)
  if ascii() then
    return open and '- ' or '+ '
  end
  return open and '▾ ' or '▸ '
end

local function say(msg, level)
  (_G.vimide_notify or vim.notify)('DirDiff: ' .. msg, level or vim.log.levels.INFO)
end

local function set_hl()
  local function def(name, spec)
    spec.default = true
    api.nvim_set_hl(0, name, spec)
  end
  def('VimIdeDirDiffChanged', { fg = '#e06c75', ctermfg = 167 })
  def('VimIdeDirDiffOrphan', { fg = '#61afef', ctermfg = 75 })
  def('VimIdeDirDiffPending', { link = 'Comment' })
  def('VimIdeDirDiffSame', { link = 'Normal' })
  def('VimIdeDirDiffDir', { link = 'Directory' })
  def('VimIdeDirDiffSize', { link = 'Number' })
  def('VimIdeDirDiffDate', { link = 'Comment' })
  def('VimIdeDirDiffOpened', { link = 'Visual' })
  def('VimIdeDirDiffMark', { link = 'Search' })        -- Space 로 고른 항목
  def('VimIdeDirDiffSide', { underline = true, bold = true })  -- 커서 줄의 지금 쪽(A/B)
end
set_hl()
api.nvim_create_autocmd('ColorScheme', {
  group = api.nvim_create_augroup('VimIdeDirDiffViewHl', { clear = true }),
  callback = set_hl,
})

local function script_path()
  local f = api.nvim_get_runtime_file('tools/dirdiffscan.py', false)[1]
  if f then
    return f
  end
  local here = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(here, ':h:h') .. '/tools/dirdiffscan.py'
end

local function commas(n)
  if type(n) ~= 'number' then
    return ''
  end
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

local function nz(v)
  if v == vim.NIL then
    return nil
  end
  return v
end

-- 이름을 폭 w 안에 (넘치면 …)
local function fit(s, w)
  if w <= 0 then
    return ''
  end
  if vim.fn.strdisplaywidth(s) <= w then
    return s .. string.rep(' ', w - vim.fn.strdisplaywidth(s))
  end
  local n = vim.fn.strchars(s)
  while n > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(s, 0, n)) > w - 1 do
    n = n - 1
  end
  local t = vim.fn.strcharpart(s, 0, n) .. '…'
  return t .. string.rep(' ', w - vim.fn.strdisplaywidth(t))
end

local function rjust(s, w)
  local d = vim.fn.strdisplaywidth(s)
  if d >= w then
    return s
  end
  return string.rep(' ', w - d) .. s
end

-- ---------------------------------------------------------------------------
-- 뒤쪽(dirdiffscan.py)과의 이야기
-- ---------------------------------------------------------------------------

local function send(s, obj)
  if s.job and s.job > 0 then
    pcall(vim.fn.chansend, s.job, vim.json.encode(obj) .. '\n')
  end
end

local render, render_rows, schedule_render, on_event, open_pair_fn, goto_row, mark_side, copied_fn, entry_of_fn

local function start_job(s)
  local excl = vim.g.DirDiffExcludes or ''
  local cmd = { 'python3', '-X', 'utf8', script_path(), s.a, s.b, '--exclude', excl,
    '--trust-mtime', (tonumber(vim.g.vimide_dirdiff_trust_mtime) or 1) ~= 0 and '1' or '0' }
  if (tonumber(vim.g.vimide_dirdiff_debug) or 0) ~= 0 then
    cmd[#cmd + 1] = '--debug'
  end
  local partial = ''
  local me
  me = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      -- R 로 멈춘 앞의 뒤쪽이 아직 내보내던 것은 버린다 (새 비교에 섞였다)
      if not data or me ~= s.job then
        return
      end
      data[1] = partial .. data[1]
      partial = data[#data]
      for i = 1, #data - 1 do
        local line = data[i]
        if line ~= '' then
          local ok, ev = pcall(vim.json.decode, line)
          if ok and type(ev) == 'table' then
            on_event(s, ev)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if me ~= s.job then
        return
      end
      local msg = table.concat(data or {}, '\n'):gsub('%s+$', '')
      if msg ~= '' then
        s.stderr = (s.stderr or '') .. msg .. '\n'
      end
    end,
    on_exit = function(_, code)
      if me == s.job and code ~= 0 and not s.closing then
        vim.schedule(function()
          say('비교가 멈췄습니다 (code ' .. code .. ') ' .. (s.stderr or ''), vim.log.levels.WARN)
        end)
      end
    end,
  })
  s.job = me
  if s.job <= 0 then
    say('python3 을 찾을 수 없습니다', vim.log.levels.WARN)
    return false
  end
  return true
end

local function request_list(s, rel)
  s.req = s.req + 1
  s.loading[rel] = true
  send(s, { cmd = 'list', id = s.req, dir = rel })
end

local function store_list(s, rel, entries)
  local d = { entries = {}, idx = {} }
  for _, e in ipairs(entries) do
    local x = { name = e[1], ka = nz(e[2]), kb = nz(e[3]), sa = nz(e[4]), sb = nz(e[5]),
      ma = nz(e[6]), mb = nz(e[7]), st = e[8], rerr = nz(e[9]) }
    d.entries[#d.entries + 1] = x
    d.idx[x.name] = x
  end
  s.dirs[rel] = d
  s.loading[rel] = nil
  s.need_full = true
end

local function join(dir, name)
  return dir == '' and name or (dir .. '/' .. name)
end

local function is_dir(e)
  return e.ka == 'd' or e.kb == 'd'
end

local function both_dirs(e)
  return e.ka == 'd' and e.kb == 'd'
end

local function is_item(e)
  return (BAD[e.st] and not both_dirs(e)) or e.rerr ~= nil
end

on_event = function(s, ev)
  local k = ev.ev
  if k == 'copied' then
    copied_fn(s, ev)
    return
  end
  if k == 'list' then
    store_list(s, ev.dir, ev.entries or {})
    if s.reopen and ev.dir == s.reopen.parent then
      s.reopen.ready = true   -- 복사한 뒤의 새 판정이 왔다 - 이제 그 짝을 다시 연다
    end
    -- R 뒤: 펼쳐 두었던 아래 디렉터리는 부모의 목록이 온 뒤에 청한다 (한꺼번에 청했더니
    -- 새 뒤쪽이 아직 부모를 훑지 않아 빈 목록을 돌려주었고, 펼친 폴더가 모두 비었다)
    for _, e in ipairs(s.dirs[ev.dir].entries) do
      local c = join(ev.dir, e.name)
      if is_dir(e) and s.expanded[c] and not s.dirs[c] and not s.loading[c] then
        request_list(s, c)
      end
    end
    schedule_render(s)
  elseif k == 'lists' or k == 'reveal' then
    for rel, entries in pairs(ev.lists or {}) do
      store_list(s, rel, entries)
      s.expanded[rel] = true
    end
    local path = nz(ev.path)   -- JSON null 은 vim.NIL (참) 이다
    if k == 'reveal' then
      s.reveal_path = path
      if not path then
        local done = s.prog and s.prog.done
        say(s.reveal_step > 0 and (done and '마지막 차이입니다' or '아래로는 아직 찾은 차이가 없습니다 (훑는 중)')
          or (done and '첫 차이입니다' or '위로는 아직 찾은 차이가 없습니다 (훑는 중)'))
      end
    end
    if next(ev.lists or {}) ~= nil or not (path and s.row_of[path]) then
      render(s)
    end
    if k == 'reveal' and path and s.row_of[path] and api.nvim_win_is_valid(s.win_l) then
      goto_row(s, s.row_of[path])
      mark_side(s)
    end
  elseif k == 'u' then
    local d = s.dirs[ev.d]
    local e = d and d.idx[ev.n]
    if e then
      e.st = ev.s
      local x = ev.e
      if type(x) == 'table' then
        e.sa, e.sb, e.ma, e.mb, e.rerr = nz(x[4]), nz(x[5]), nz(x[6]), nz(x[7]), nz(x[9])
      end
      s.dirty[join(ev.d, ev.n)] = true
      schedule_render(s)
    end
  elseif k == 'progress' then
    s.prog = ev
    s.prog_dirty = true
    schedule_render(s)
  elseif k == 'error' then
    say(ev.msg or '?', vim.log.levels.WARN)
  end
end

-- ---------------------------------------------------------------------------
-- 그리기
-- ---------------------------------------------------------------------------

local function visible(s, e)
  if not s.filter then
    return true
  end
  return e.st ~= 'same'
end

-- 펼친 디렉터리만 따라 내려가며 줄을 만든다
render_rows = function(s)
  local rows = {}
  local function walk(rel, depth)
    local d = s.dirs[rel]
    if not d then
      if s.loading[rel] then
        rows[#rows + 1] = { rel = rel .. '/', depth = depth, loading = true }
      end
      return
    end
    for _, e in ipairs(d.entries) do
      if visible(s, e) then
        local r = join(rel, e.name)
        rows[#rows + 1] = { rel = r, dir = rel, depth = depth, e = e }
        if is_dir(e) and s.expanded[r] then
          walk(r, depth + 1)
        end
      end
    end
  end
  walk('', 0)
  s.rows = rows
  s.row_of = {}
  for i, r in ipairs(rows) do
    if r.e then
      s.row_of[r.rel] = i
    end
  end
end

local function layout(s)
  local W = api.nvim_win_get_width(s.win_l)
  local half = math.floor((W - 3) / 2)
  local date = half >= 60
  local size = half >= 34
  return { W = W, half = half, date = date, size = size }
end

-- 한쪽(A 또는 B) 반 칸: 들여쓰기 + 접기 표시 + 이름 + 크기 + 날짜
-- 화면에 쓸 이름: 줄바꿈 같은 제어 문자는 ^J 로 (줄에 \n 이 들어가면 nvim_buf_set_lines 가
-- 트리 전체를 못 그렸다). 경로·주고받기에는 원래 이름을 쓴다
local function shown(name)
  return vim.fn.strtrans(name)
end

local function side_text(s, L, r, side)
  local e = r.e
  -- 'side == "a" and e.ka or e.kb' 로 썼더니 A 에 없는 것(e.ka == nil)이 B 의 것으로
  -- 떨어져 B 에만 있는 줄이 A 쪽에도 그려졌다
  local k, sz, mt
  if side == 'a' then
    k, sz, mt = e.ka, e.sa, e.ma
  else
    k, sz, mt = e.kb, e.sb, e.mb
  end
  if k == nil then
    return string.rep(' ', L.half), nil
  end
  local tail = ''
  if L.size then
    tail = tail .. ' ' .. rjust(k == 'd' and '' or commas(sz), 11)
  end
  if L.date then
    tail = tail .. ' ' .. (mt and os.date('%Y-%m-%d', mt) or '          ')
  end
  local indw = 2 * r.depth
  local icon = k == 'd' and fold_icon(s.expanded[r.rel]) or '  '
  local iconw = vim.fn.strdisplaywidth(icon)
  local namew = L.half - indw - iconw - vim.fn.strdisplaywidth(tail)
  -- 깊은 줄이 반 칸을 넘으면 판정 칸과 B 쪽이 밀린다: 들여쓰기부터, 그다음 크기·날짜를 줄인다
  if namew < 8 then
    indw = math.max(0, indw - (8 - namew))
    namew = L.half - indw - iconw - vim.fn.strdisplaywidth(tail)
  end
  if namew < 1 then
    tail = ''
    namew = L.half - indw - iconw
  end
  if namew < 1 then
    indw = 0
    namew = L.half - iconw
  end
  local ind = string.rep(' ', indw)
  local bad = e.rerr and e.rerr:find(side, 1, true) and ' (못 읽음)' or ''
  local name = fit(shown(e.name) .. (k == 'l' and ' @' or '') .. bad, namew)
  return ind .. icon .. name .. tail, { name_start = #ind + #icon, name_end = #ind + #icon + #name, tail = #tail }
end

local function line_of(s, L, r)
  if r.loading then
    local t = string.rep('  ', r.depth) .. '  (읽는 중…)'
    return t, {}, nil
  end
  local e = r.e
  local lt, lm = side_text(s, L, r, 'a')
  local g = ' ' .. sym(e.st) .. ' '
  local rt, rm = side_text(s, L, r, 'b')
  local text = lt .. g .. rt
  local hls = {}
  local st = e.st
  local group
  if st == 'diff' then
    group = 'VimIdeDirDiffChanged'
  elseif st == 'pend' then
    group = 'VimIdeDirDiffPending'
  elseif st == 'same' then
    group = is_dir(e) and 'VimIdeDirDiffDir' or nil
  end
  local ga = st == 'onlyA' and 'VimIdeDirDiffOrphan' or group
  local gb = st == 'onlyB' and 'VimIdeDirDiffOrphan' or group
  local off_g = #lt
  local off_b = #lt + #g
  if lm and ga then
    hls[#hls + 1] = { ga, lm.name_start, lm.name_end }
  end
  if lm and lm.tail > 0 then
    hls[#hls + 1] = { (st == 'diff' or st == 'onlyA') and ga or 'VimIdeDirDiffSize', off_g - lm.tail, off_g }
  end
  hls[#hls + 1] = { (st == 'same') and 'VimIdeDirDiffPending' or (ga or gb or 'VimIdeDirDiffPending'), off_g, off_b }
  if rm and gb then
    hls[#hls + 1] = { gb, off_b + rm.name_start, off_b + rm.name_end }
  end
  if rm and rm.tail > 0 then
    hls[#hls + 1] = { (st == 'diff' or st == 'onlyB') and gb or 'VimIdeDirDiffSize', #text - rm.tail, #text }
  end
  if lm and s.marks.a[r.rel] then
    hls[#hls + 1] = { 'VimIdeDirDiffMark', lm.name_start, lm.name_end }
  end
  if rm and s.marks.b[r.rel] then
    hls[#hls + 1] = { 'VimIdeDirDiffMark', off_b + rm.name_start, off_b + rm.name_end }
  end
  return text, hls, off_b, off_g
end

local function put_hls(s, lnum, hls)
  for _, h in ipairs(hls) do
    if h[1] then
      pcall(api.nvim_buf_set_extmark, s.buf_l, ns, lnum - 1, h[2], { end_col = h[3], hl_group = h[1] })
    end
  end
end

local function status_text(s)
  local p = s.prog or {}
  local parts = {}
  if p.done then
    parts[#parts + 1] = ('끝 %.1f초'):format(p.sec or 0)
  elseif p.again then
    parts[#parts + 1] = '복사한 곳을 다시 보는 중'
  else
    parts[#parts + 1] = ('훑는 중 %d초 · 디렉터리 %s'):format(math.floor(p.sec or 0), commas(p.dirs or 0))
  end
  parts[#parts + 1] = ('파일 %s'):format(commas(p.files or 0))
  parts[#parts + 1] = ('다름 %s'):format(commas(p.diff or 0))
  parts[#parts + 1] = ('A만 %s'):format(commas(p.onlyA or 0))
  parts[#parts + 1] = ('B만 %s'):format(commas(p.onlyB or 0))
  if (p.pend or 0) > 0 then
    parts[#parts + 1] = ('확인 중 %s'):format(commas(p.pend))
  end
  if (p.err or 0) > 0 then
    parts[#parts + 1] = ('읽기 실패 %s'):format(commas(p.err))
  end
  local na, nb = vim.tbl_count(s.marks.a), vim.tbl_count(s.marks.b)
  if na + nb > 0 then
    parts[#parts + 1] = ('고름 A %d / B %d'):format(na, nb)
  end
  return ' DirDiff  ' .. table.concat(parts, ' · ') .. (s.filter and '   [차이만]' or '')
    .. '   [' .. (s.side == 'b' and 'B' or 'A') .. ' 쪽]   (? 도움말)'
end

local function winbar_text(s, L)
  local function side(tag, path)
    return fit(' ' .. tag .. ': ' .. vim.fn.fnamemodify(path, ':~'), L.half)
  end
  return (side('A', s.a) .. '   ' .. side('B', s.b)):gsub('%%', '%%%%')
end

-- 줄 i 로, 지금 쪽(A/B)의 이름 자리에 커서를
goto_row = function(s, i)
  if not (i and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  local col = s.side == 'b' and (s.offb and s.offb[i]) or 0
  pcall(api.nvim_win_set_cursor, s.win_l, { i, col or 0 })
end

-- 커서 줄의 지금 쪽 반 칸에 밑줄
mark_side = function(s)
  if not (api.nvim_buf_is_valid(s.buf_l) and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  api.nvim_buf_clear_namespace(s.buf_l, ns_side, 0, -1)
  local i = api.nvim_win_get_cursor(s.win_l)[1]
  local ob = s.offb and s.offb[i]
  if not ob then
    return
  end
  local line = api.nvim_buf_get_lines(s.buf_l, i - 1, i, false)[1] or ''
  local a, b
  if s.side == 'b' then
    a, b = ob, #line
  else
    a, b = 0, (s.offg and s.offg[i]) or ob
  end
  pcall(api.nvim_buf_set_extmark, s.buf_l, ns_side, i - 1, a, { end_col = b, hl_group = 'VimIdeDirDiffSide', priority = 50 })
end

local function mark_open(s)
  api.nvim_buf_clear_namespace(s.buf_l, ns_open, 0, -1)
  local i = s.opened_rel and s.row_of[s.opened_rel]
  if i then
    pcall(api.nvim_buf_set_extmark, s.buf_l, ns_open, i - 1, 0, { line_hl_group = 'VimIdeDirDiffOpened' })
  end
end

render = function(s)
  s.render_pending = false
  if not (api.nvim_buf_is_valid(s.buf_l) and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  local keep = s.rows and s.rows[api.nvim_win_get_cursor(s.win_l)[1]]
  keep = keep and keep.rel
  render_rows(s)
  local L = layout(s)
  local lines, all = {}, {}
  s.offb, s.offg = {}, {}
  for i, r in ipairs(s.rows) do
    local t, h, ob, og = line_of(s, L, r)
    lines[i] = t
    all[i] = h
    s.offb[i], s.offg[i] = ob, og
  end
  if #lines == 0 then
    lines = { s.prog and s.prog.done and '  (차이가 없습니다)' or '  (훑는 중…)' }
  end
  vim.bo[s.buf_l].modifiable = true
  api.nvim_buf_set_lines(s.buf_l, 0, -1, false, lines)
  vim.bo[s.buf_l].modifiable = false
  api.nvim_buf_clear_namespace(s.buf_l, ns, 0, -1)
  for i, h in ipairs(all) do
    put_hls(s, i, h)
  end
  mark_open(s)
  s.dirty = {}
  pcall(function()
    vim.wo[s.win_l].winbar = winbar_text(s, L)
    vim.wo[s.win_l].statusline = status_text(s):gsub('%%', '%%%%')
  end)
  if s.want_rel and s.row_of[s.want_rel] then
    goto_row(s, s.row_of[s.want_rel])
    s.want_rel = nil
  elseif keep and s.row_of[keep] then
    goto_row(s, s.row_of[keep])
  end
  mark_side(s)
  -- 복사로 바뀐 파일을 보고 있었으면 그 짝을 다시 연다 (없던 쪽이 생겼다). 부모의 새 목록이
  -- 온 뒤에만 - 먼저 열었더니 옛 항목(없던 쪽 그대로)으로 열고 끝났다
  if s.reopen and s.reopen.ready then
    local rel = s.reopen.rel
    s.reopen = nil
    local e = entry_of_fn(s, rel)
    if e and not is_dir(e) then
      vim.schedule(function()
        if not s.done then
          open_pair_fn(s, { rel = rel, e = e, dir = rel:match('^(.*)/[^/]+$') or '' }, false)
        end
      end)
    end
  end
  if s.want_rel and s.prog and s.prog.done and next(s.loading) == nil then
    s.want_rel = nil   -- 다시 훑은 뒤에 없어진 줄
  end
  s.last_render = uv.now()
end

-- 바뀐 줄만 다시 그린다 (거르기가 켜져 있으면 줄이 생기거나 없어지므로 전부)
local function render_dirty(s)
  s.render_pending = false
  if not (api.nvim_buf_is_valid(s.buf_l) and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  if s.filter then
    return render(s)
  end
  local L = layout(s)
  vim.bo[s.buf_l].modifiable = true
  for rel in pairs(s.dirty) do
    local i = s.row_of[rel]
    if i and s.rows[i] then
      local t, h, ob, og = line_of(s, L, s.rows[i])
      s.offb[i], s.offg[i] = ob, og
      api.nvim_buf_set_lines(s.buf_l, i - 1, i, false, { t })
      api.nvim_buf_clear_namespace(s.buf_l, ns, i - 1, i)
      put_hls(s, i, h)
    end
  end
  vim.bo[s.buf_l].modifiable = false
  s.dirty = {}
  mark_open(s)
  if s.prog_dirty then
    s.prog_dirty = false
    pcall(function()
      vim.wo[s.win_l].statusline = status_text(s):gsub('%%', '%%%%')
    end)
  end
end

schedule_render = function(s)
  if s.render_pending then
    return
  end
  s.render_pending = true
  -- 목록이 새로 오면 전부, 상태만 바뀌면 바뀐 줄만 - 60ms 씩 모아서
  vim.defer_fn(function()
    -- 트리에서 비주얼로 고르는 중에는 줄을 다시 쓰지 않는다 - 목록이 오며 줄이 밀리면
    -- 비주얼 시작 줄은 그대로라 고르지 않은 줄까지 복사되었다
    if s.need_full and api.nvim_get_current_win() == s.win_l and api.nvim_get_mode().mode:match('^[vV\22]') then
      s.render_pending = false
      vim.defer_fn(function()
        schedule_render(s)
      end, 200)
      return
    end
    if s.need_full then
      s.need_full = false
      render(s)
    else
      render_dirty(s)
    end
  end, 60)
end

-- ---------------------------------------------------------------------------
-- 비교 열기 (위의 두 편집 창)
-- ---------------------------------------------------------------------------

-- 창 옵션을 전역 값으로 되돌린다 (곁창·트리 창에서 갈라 만든 창은 그 옵션을 물려받는다)
local function plain_window(win)
  for _, o in ipairs({ 'winhighlight', 'winfixwidth', 'winfixheight', 'number', 'relativenumber',
    'signcolumn', 'foldcolumn', 'cursorline', 'list', 'wrap', 'spell', 'statuscolumn', 'winbar',
    'statusline' }) do
    pcall(api.nvim_win_call, win, function()
      vim.cmd('setlocal ' .. o .. '<')
    end)
  end
end

-- 비교 창에 띄우는 빈 버퍼 / 안내 버퍼. 반드시 이름을 붙인다: 이름 없는 빈 버퍼가
-- 떠 있는 창에서 :edit 하면 vim 은 그 버퍼를 파일 버퍼로 '다시 쓴다' - 그 뒤 안내를
-- 써 넣으면 그 글이 진짜 파일 버퍼에 들어갔다 (실측: B 창의 hunks.c 버퍼에
-- '(B 에 없음)' 이 들어갔다. 저장했으면 파일이 덮였다).
--
-- 이름은 처음 한 번만 붙이고 바꾸지 않는다. 무엇을 보이는지는 창 머리(winbar)와 버퍼 글에
-- 쓴다 - 처음에는 볼 때마다 이름을 바꾸었더니, nvim 이 바꾸기 전 이름으로 버퍼를 하나씩
-- 새로 만들어 두어(rename_buffer) 끝낸 뒤에도 'DirDiff A (A 에 없음) …' 버퍼가 쌓였다.
local function scratch(s, side, text)
  local b = s['empty_' .. side]
  if not (b and api.nvim_buf_is_valid(b)) then
    b = api.nvim_create_buf(false, true)
    vim.bo[b].bufhidden = 'hide'
    vim.bo[b].swapfile = false
    pcall(api.nvim_buf_set_name, b, ('DirDiff %s #%d'):format(side:upper(), b))
    s['empty_' .. side] = b
  end
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, text)
  vim.bo[b].modifiable = false
  vim.bo[b].modified = false
  return b
end

local function is_binary(path)
  local f = io.open(path, 'rb')
  if not f then
    return false
  end
  local chunk = f:read(8000) or ''
  f:close()
  return chunk:find('\0', 1, true) ~= nil
end

-- 한쪽에만 있는 파일: 있는 쪽에 파일을, 없는 쪽에는 빈 버퍼를 diff 로 (Beyond Compare
-- 처럼 - 있는 쪽 줄이 모두 '더해진 줄'로 보인다). 무엇인지는 창 머리(winbar)에 쓴다.
-- 이름이 꼭 같은 버퍼 (bufnr() 는 이름을 무늬로 보아 [ ] ~ 가 든 이름에서 딴 버퍼를 준다)
local function buf_named(path)
  local full = vim.fn.fnamemodify(path, ':p')
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(b) == full then
      return b
    end
  end
end

local function show_file(s, win, path, side)
  if not path then
    api.nvim_win_set_buf(win, scratch(s, side, {}))
    return
  end
  -- 누구 버퍼인지는 열기 바로 앞에 본다 (비교를 시작할 때 한 번 찍어 둔 목록으로 보았더니,
  -- 그 뒤 사용자가 연 버퍼를 비교가 연 것으로 알고 지웠다)
  local pre = buf_named(path)
  local pre_listed = pre and vim.bo[pre].buflisted
  local pre_loaded = pre and api.nvim_buf_is_loaded(pre)
  local pre_ours = pre and vim.b[pre].vimide_dirdiff
  -- noautocmd: 비교하려고 연 파일에서 vim-ide 의 BufRead 훅이 돌지 않게 - 색인이 없는
  -- 트리면 autoindex 가 그 트리 전체의 GTAGS 를 만들기 시작하고(트리 안에 .tags/ 를
  -- 쓴다), gutentags 도 붙는다. 비교는 보기일 뿐이다. 구문 색은 filetype 을 따로 준다.
  local wi = vim.o.wildignore
  vim.o.wildignore = ''
  local ok, err = pcall(api.nvim_win_call, win, function()
    vim.cmd('silent keepalt noautocmd hide edit ' .. vim.fn.fnameescape(path))
  end)
  vim.o.wildignore = wi
  if not ok then
    say(tostring(err):gsub('^.-(E%d+:)', '%1'), vim.log.levels.WARN)
    return
  end
  local b = api.nvim_win_get_buf(win)
  if not pre or pre_ours or (not pre_listed and not pre_loaded) then
    -- 없던 것, 다른 비교가 연 것(함께 가진다), 지워져 있던 것: 이 비교의 것
    s.opened[b] = true
    vim.b[b].vimide_dirdiff = true
  elseif not pre_loaded then
    -- 목록에만 있고 읽지 않은 사용자 버퍼(세션의 badd): 끝나면 도로 내려 둔다 - 여기서
    -- noautocmd 로 읽었으니 그대로 두면 그 버퍼의 BufRead 훅이 끝내 돌지 않는다
    s.unload[b] = true
  end
  if vim.bo[b].filetype == '' then
    local okf, ft = pcall(vim.filetype.match, { buf = b, filename = path })
    if okf and ft then
      pcall(function()
        vim.bo[b].filetype = ft
      end)
    end
  end
end

local function set_head(win, text)
  pcall(function()
    vim.wo[win].winbar = (' ' .. text):gsub('%%', '%%%%')
  end)
end

-- 앞에서 열었던 파일 버퍼를 치운다 (이 비교에서 연 것, 고치지 않았고 어디에도 안 보이는 것)
local function unused(b)
  return api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 0 and not vim.bo[b].modified
end

local function sweep(s)
  for b in pairs(s.opened) do
    if unused(b) then
      pcall(api.nvim_buf_delete, b, { force = false })
      s.opened[b] = nil
    elseif not api.nvim_buf_is_valid(b) then
      s.opened[b] = nil
    end
  end
  for b in pairs(s.unload) do
    if unused(b) then
      pcall(api.nvim_buf_delete, b, { unload = true })
      s.unload[b] = nil
    elseif not api.nvim_buf_is_valid(b) then
      s.unload[b] = nil
    end
  end
end

-- 링크는 가리키는 것을 본다: 디렉터리를 가리키면 디렉터리처럼(열면 nvim-tree 가 창을
-- 가져갔다), 끊겼으면 안내, 파일이면 크기·바이너리 검사도 그 파일로
local function real_kind(k, p)
  if k ~= 'l' or not p then
    return k
  end
  if vim.fn.isdirectory(p) == 1 then
    return 'ld'
  end
  if vim.fn.filereadable(p) == 1 then
    return 'lf'
  end
  return 'lx'
end

local NOTE = { d = '디렉터리', o = '특수 파일', ld = '디렉터리를 가리키는 링크', lx = '끊긴 링크' }

local function open_pair(s, r, jump)
  local e = r.e
  local rel = shown(r.rel)
  local pa = e.ka and (s.a .. '/' .. r.rel) or nil
  local pb = e.kb and (s.b .. '/' .. r.rel) or nil
  local ka, kb = real_kind(e.ka, pa), real_kind(e.kb, pb)
  -- 디렉터리를 :edit 하면 nvim-tree 가 창을 가져간다 - 파일(과 파일 링크)만 연다
  local function note(k, side, p)
    if not NOTE[k] then
      return nil
    end
    local to = (k == 'ld' or k == 'lx') and uv.fs_readlink(p)
    return ('  (%s 쪽은 %s: %s%s)'):format(side, NOTE[k], rel, to and (' -> ' .. shown(to)) or '')
  end
  local na, nb = note(ka, 'A', pa), note(kb, 'B', pb)
  -- 비교 창을 닫아 버렸으면 트리 위에 다시 만든다. 트리 창에서 가르면 트리 옵션
  -- (번호 끔 등)을 물려받으므로 plain_window 로 되돌리고, 트리 높이도 되돌린다
  local made = {}
  if not api.nvim_win_is_valid(s.win_a) and not api.nvim_win_is_valid(s.win_b) then
    s.win_a = api.nvim_open_win(scratch(s, 'a', {}), false, { split = 'above', win = s.win_l })
    made[#made + 1] = s.win_a
  end
  if not api.nvim_win_is_valid(s.win_a) then
    s.win_a = api.nvim_open_win(scratch(s, 'a', {}), false, { split = 'left', win = s.win_b })
    made[#made + 1] = s.win_a
  elseif not api.nvim_win_is_valid(s.win_b) then
    s.win_b = api.nvim_open_win(scratch(s, 'b', {}), false, { split = 'right', win = s.win_a })
    made[#made + 1] = s.win_b
  end
  for _, w in ipairs(made) do
    plain_window(w)
  end
  if #made > 0 and s.list_h then
    pcall(api.nvim_win_set_height, s.win_l, s.list_h)
  end
  for _, w in ipairs({ s.win_a, s.win_b }) do
    pcall(api.nvim_win_call, w, function()
      vim.cmd('diffoff')
    end)
  end
  local max = (tonumber(vim.g.vimide_dirdiff_max_mb) or 20) * 1024 * 1024
  local function size_of(k, p, sz)
    if k == 'lf' then
      return math.max(0, vim.fn.getfsize(p))
    end
    return k == 'f' and sz or 0
  end
  local sa, sb = size_of(ka, pa, e.sa), size_of(kb, pb, e.sb)
  local big = (sa or 0) > max or (sb or 0) > max
  local function binary(k, p)
    return p and (k == 'f' or k == 'lf') and is_binary(p)
  end
  local bin = big or binary(ka, pa) or binary(kb, pb)
  if bin then
    local info = {
      '',
      (big and ('  큰 파일(%d MB 넘음 - g:vimide_dirdiff_max_mb): '):format(max / 1048576) or '  바이너리 파일: ') .. rel,
      '',
      '  A: ' .. (e.ka and (commas(sa) .. ' 바이트') or '없음'),
      '  B: ' .. (e.kb and (commas(sb) .. ' 바이트') or '없음'),
      '',
      '  판정: ' .. ({ same = '같다', diff = '다르다', onlyA = 'A 에만', onlyB = 'B 에만', pend = '확인 중' })[e.st],
    }
    api.nvim_win_set_buf(s.win_a, scratch(s, 'a', info))
    api.nvim_win_set_buf(s.win_b, scratch(s, 'b', info))
  else
    if na then
      api.nvim_win_set_buf(s.win_a, scratch(s, 'a', { '', na }))
    else
      show_file(s, s.win_a, pa, 'a')
    end
    if nb then
      api.nvim_win_set_buf(s.win_b, scratch(s, 'b', { '', nb }))
    else
      show_file(s, s.win_b, pb, 'b')
    end
    for _, w in ipairs({ s.win_a, s.win_b }) do
      pcall(api.nvim_win_call, w, function()
        vim.cmd('diffthis')
        vim.wo.foldlevel = 0
        -- 파일별 BufEnter 설정(.c 의 ts=8 등)을 양쪽 모두에 - noautocmd 로 열어서 커서가
        -- 들어가는 쪽만 받았고, 탭 들여쓰기가 A 와 B 에서 다르게 보였다. BufRead 는 여전히 없다
        if vim.bo.buftype == '' then
          vim.cmd('silent! doautocmd <nomodeline> BufEnter')
        end
      end)
    end
  end
  local function head(side, k, root)
    if k == nil then
      return side .. ': (없음) ' .. rel
    end
    return side .. ': ' .. shown(vim.fn.fnamemodify(root .. '/' .. r.rel, ':~'))
  end
  set_head(s.win_a, head('A', e.ka, s.a))
  set_head(s.win_b, head('B', e.kb, s.b))
  sweep(s)
  s.opened_rel = r.rel
  mark_open(s)
  if jump then
    local w = pa and s.win_a or s.win_b
    api.nvim_set_current_win(w)
    pcall(vim.cmd, 'normal! gg')
    if not bin then
      if vim.fn.diff_filler(1) > 0 then
        -- 첫 차이가 1줄 위에 끼인 줄(다른 쪽에만 있는 첫머리)이면 그대로 두고 보이게만.
        -- ]c 는 그것을 건너 두 번째 차이로 갔다
        pcall(vim.fn.winrestview, { topline = 1, topfill = vim.fn.diff_filler(1) })
      elseif vim.fn.diff_hlID(1, 1) == 0 then
        pcall(vim.cmd, 'normal! ]c')
      end
    end
  end
end

open_pair_fn = open_pair

-- ---------------------------------------------------------------------------
-- 트리 창의 동작
-- ---------------------------------------------------------------------------

local function cur_row(s)
  if not api.nvim_win_is_valid(s.win_l) then
    return nil
  end
  return s.rows[api.nvim_win_get_cursor(s.win_l)[1]]
end

local function toggle(s, r, want)
  local open = s.expanded[r.rel]
  if want ~= nil and want == (open and true or false) then
    return
  end
  if open then
    s.expanded[r.rel] = nil
    send(s, { cmd = 'unlist', dir = r.rel })
  else
    s.expanded[r.rel] = true
    request_list(s, r.rel)
  end
  render(s)
end

local function act_enter(s, jump)
  local r = cur_row(s)
  if not r or r.loading then
    return
  end
  if is_dir(r.e) then
    if jump == nil or jump == true then
      toggle(s, r)
    end
    return
  end
  open_pair(s, r, jump)
end

local function act_step(s, step)
  local r = cur_row(s)
  local from = r and (r.loading and r.rel:gsub('/$', '') or r.rel) or ''
  s.req = s.req + 1
  s.reveal_step = step
  send(s, { cmd = 'next', id = s.req, from = from, step = step })
end

local function act_h(s)
  local r = cur_row(s)
  if not r or r.loading then
    return
  end
  if is_dir(r.e) and s.expanded[r.rel] then
    return toggle(s, r, false)
  end
  local parent = r.dir
  if parent and parent ~= '' and s.row_of[parent] then
    goto_row(s, s.row_of[parent])
  end
end

-- O / X 는 트리 전체 (Beyond Compare 의 Expand All / Collapse All). 처음에는 커서의
-- 디렉터리 아래만 했더니 맨 윗줄(한쪽에만 있는 디렉터리)에서 O 가 아무것도 펼치지 않았다
local function act_expand_all(s)
  s.req = s.req + 1
  send(s, { cmd = 'expand', id = s.req, dir = '' })
end

local function act_collapse_all(s)
  local r = cur_row(s)
  local top = r and r.rel and r.rel:match('^[^/]+')
  for k in pairs(s.expanded) do
    if k ~= '' then
      s.expanded[k] = nil
      send(s, { cmd = 'unlist', dir = k })
    end
  end
  render(s)
  -- 커서는 있던 줄의 맨 위 조상에
  if top and s.row_of[top] then
    goto_row(s, s.row_of[top])
  end
end

-- ---------------------------------------------------------------------------
-- 고르기(A/B 쪽 따로)와 파일·디렉터리 복사 (Beyond Compare 의 Copy to Right / Left)
-- ---------------------------------------------------------------------------

local function cursor_side(s)
  -- 커서가 트리의 오른쪽 반(B)에 있는지 - 마우스로 눌렀거나 l/w 로 옮겼을 때
  local pos = api.nvim_win_get_cursor(s.win_l)
  local ob = s.offb and s.offb[pos[1]]
  if ob then
    s.side = pos[2] >= ob and 'b' or 'a'
  end
end

local function act_side(s)
  s.side = s.side == 'a' and 'b' or 'a'
  goto_row(s, api.nvim_win_get_cursor(s.win_l)[1])
  mark_side(s)
  s.prog_dirty = true
  schedule_render(s)
end

local function act_mark(s)
  local r = cur_row(s)
  if r and r.e then
    local side = s.side
    -- 'side == "a" and ka or kb' 로 썼더니 B 에만 있는 줄의 빈 A 쪽에서도 골라졌다
    local has
    if side == 'a' then
      has = r.e.ka
    else
      has = r.e.kb
    end
    if has then
      local m = s.marks[side]
      m[r.rel] = (not m[r.rel]) or nil
      s.dirty[r.rel] = true
      s.prog_dirty = true
      schedule_render(s)
    else
      say(('%s 쪽에 없는 항목입니다'):format(side:upper()))
    end
  end
  local i = api.nvim_win_get_cursor(s.win_l)[1]
  if i < api.nvim_buf_line_count(s.buf_l) then
    goto_row(s, i + 1)
    mark_side(s)
  end
end

local function clear_marks(s)
  if next(s.marks.a) or next(s.marks.b) then
    s.marks = { a = {}, b = {} }
    render(s)
  end
end

local function entry_of(s, rel)
  local dir, name = rel:match('^(.*)/([^/]+)$')
  dir, name = dir or '', name or rel
  local d = s.dirs[dir]
  return d and d.idx[name]
end
entry_of_fn = entry_of

-- 복사할 것: 원본 쪽(A→B 면 A)에서 Space 로 고른 것 > 비주얼 줄 > 커서 줄.
-- 반대쪽에서 고른 것은 쓰지 않는다 (B 에서 고른 것을 A→B 원본으로 써 B 쪽을 덮었다)
local function picked(s, from, l1, l2)
  local set, by_mark = {}, false
  if next(s.marks[from]) then
    by_mark = true
    for rel in pairs(s.marks[from]) do
      set[rel] = true
    end
  elseif l1 then
    for i = math.min(l1, l2), math.max(l1, l2) do
      local r = s.rows[i]
      if r and r.e then
        set[r.rel] = true
      end
    end
  else
    local r = cur_row(s)
    if r and r.e then
      set[r.rel] = true
    end
  end
  local list = vim.tbl_keys(set)
  table.sort(list)
  local out = {}
  for _, rel in ipairs(list) do
    local inside = false
    for _, o in ipairs(out) do
      if rel:sub(1, #o + 1) == o .. '/' then
        inside = true
        break
      end
    end
    if not inside then
      out[#out + 1] = rel
    end
  end
  return out, by_mark
end

-- 버퍼 이름은 nvim 이 디렉터리 쪽 링크를 풀어서 붙인다 - 뿌리를 M.open 에서 풀어 두었으니
-- 여기서도 버퍼 이름을 풀어서 견준다
local function real(p)
  return uv.fs_realpath(p) or vim.fn.resolve(p)
end

local function modified_under(path, is_dir_)
  for _, b in ipairs(api.nvim_list_bufs()) do
    local n = api.nvim_buf_get_name(b)
    if n ~= '' and api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
      local rn = real(n)
      if rn == path or (is_dir_ and rn:sub(1, #path + 1) == path .. '/') then
        return vim.fn.fnamemodify(n, ':~:.')
      end
    end
  end
end

local WHY = {
  ['source missing'] = '원본에 없음', kind = '종류가 다름 (디렉터리 / 파일)',
  special = '특수 파일 (FIFO 등)', ['bad path'] = '경로가 이상함',
}
local function why_text(to, w)
  local parent = w:match('^parent:(.*)$')
  if parent then
    return ('%s 쪽 %s 가 진짜 디렉터리가 아님 (링크 등) - 따라가 쓰지 않는다'):format(to:upper(), shown(parent))
  end
  return WHY[w] or w
end

-- dir: 1 = A -> B (<C-r>), -1 = B -> A (<C-l>). 실제 복사는 뒤쪽(dirdiffscan.py 의 copier)이
-- 항목마다 안전하게 한다 - 여기서는 고르고, 묻고, 끝난 뒤를 정리한다
local function act_copy(s, dir, l1, l2)
  local from, to = dir > 0 and 'a' or 'b', dir > 0 and 'b' or 'a'
  if s.copying then
    return say('앞의 복사가 아직 끝나지 않았습니다', vim.log.levels.WARN)
  end
  local list, by_mark = picked(s, from, l1, l2)
  local paths, skipped, names = {}, {}, {}
  local nfile, ndir = 0, 0
  for _, rel in ipairs(list) do
    local e = entry_of(s, rel)
    local ks = e and (from == 'a' and e.ka or nil)
    if e and from == 'b' then
      ks = e.kb
    end
    local kt
    if e then
      if to == 'a' then
        kt = e.ka
      else
        kt = e.kb
      end
    end
    local w
    if not e or ks == nil then
      w = from:upper() .. ' 에 없음'
    elseif (ks == 'd') ~= (kt == 'd') and kt ~= nil then
      w = '종류가 다름 (디렉터리 / 파일)'
    elseif ks == 'o' then
      w = '특수 파일'
    else
      local m = modified_under(s[to] .. '/' .. rel, ks == 'd')
      if m then
        w = '저장하지 않은 버퍼: ' .. m
      end
    end
    if w then
      skipped[#skipped + 1] = shown(rel) .. ' - ' .. w
    else
      paths[#paths + 1] = rel
      names[#names + 1] = shown(rel) .. (ks == 'd' and '/' or '')
      if ks == 'd' then
        ndir = ndir + 1
      else
        nfile = nfile + 1
      end
    end
  end
  if #paths == 0 then
    return say(#skipped > 0 and ('복사할 것이 없습니다: ' .. table.concat(skipped, ', ')) or '복사할 것이 없습니다',
      vim.log.levels.WARN)
  end
  if (tonumber(vim.g.vimide_dirdiff_confirm_copy) or 1) ~= 0 then
    local what = {}
    if nfile > 0 then
      what[#what + 1] = ('파일 %d'):format(nfile)
    end
    if ndir > 0 then
      what[#what + 1] = ('디렉터리 %d'):format(ndir)
    end
    -- 무엇을 덮는지 이름으로 보인다 (수만으로는 엉뚱한 줄이 섞여도 알 수 없었다)
    local shown_names = vim.list_slice(names, 1, 8)
    local more = #names > 8 and (' 외 %d개'):format(#names - 8) or ''
    local msg = ('%s → %s: %s  (%s%s)\n%s 쪽의 같은 이름은 덮어씁니다. 디렉터리는 합칩니다 (지우지 않음).%s')
      :format(from:upper(), to:upper(), table.concat(what, ', '), table.concat(shown_names, ', '), more,
        to:upper(), #skipped > 0 and ('\n건너뜀: ' .. table.concat(skipped, ', ')) or '')
    local yes = vim.fn.confirm(msg, '&Yes\n&No', 2) == 1
    -- 물음이 차지한 줄을 치운다 - 그대로 두면 다음 알림이 Press ENTER 를 띄우고, 그동안은
    -- vim.schedule 이 돌지 않아 복사가 키를 누를 때까지 멈춰 있었다
    vim.cmd('redraw')
    if not yes then
      return say('복사하지 않았습니다')
    end
  end
  s.req = s.req + 1
  s.copying = { id = s.req, from = from, to = to, by_mark = by_mark, skipped = skipped }
  send(s, { cmd = 'copy', id = s.req, from = from, paths = paths })
  say(('복사하는 중… (%d 개)'):format(#paths))
end

-- 뒤쪽의 'copied': 목록을 새로 받게 하고, 버퍼를 다시 읽고, 알린다
local function on_copied(s, ev)
  local c = s.copying
  s.copying = nil
  local to = c and c.to or 'b'
  local from = c and c.from or 'a'
  local roots = ev.roots or {}
  for _, rr in ipairs(roots) do
    for k in pairs(s.dirs) do
      if k == rr or k:sub(1, #rr + 1) == rr .. '/' then
        s.dirs[k] = nil
        s.loading[k] = nil
      end
    end
  end
  -- 대상 쪽 버퍼를 새로 읽는다 (비교가 연 것은 BufRead 훅 없이)
  local base = s[to]
  for _, b in ipairs(api.nvim_list_bufs()) do
    local n = api.nvim_buf_get_name(b)
    if n ~= '' and api.nvim_buf_is_loaded(b) and not vim.bo[b].modified then
      local rn = real(n)
      for _, rr in ipairs(roots) do
        local p = base .. '/' .. rr
        if rn == p or rn:sub(1, #p + 1) == p .. '/' then
          if vim.b[b].vimide_dirdiff then
            pcall(api.nvim_buf_call, b, function()
              vim.cmd('silent! noautocmd edit!')
            end)
          else
            pcall(vim.cmd, 'silent! checktime ' .. b)
          end
          break
        end
      end
    end
  end
  -- 보고 있던 짝이 복사한 곳 안이면, 그 부모의 새 목록이 온 뒤에 다시 연다
  if s.opened_rel then
    for _, rr in ipairs(roots) do
      if s.opened_rel == rr or s.opened_rel:sub(1, #rr + 1) == rr .. '/' then
        local parent = s.opened_rel:match('^(.*)/[^/]+$') or ''
        s.reopen = { rel = s.opened_rel, parent = parent }
        if parent ~= '' and not s.expanded[parent] then
          request_list(s, parent)   -- 접혀 있어도 새 판정을 받아 온다
        end
        break
      end
    end
  end
  if c and c.by_mark then
    s.marks[from] = {}
  end
  s.need_full = true
  schedule_render(s)
  local skipped = vim.list_extend(vim.deepcopy(c and c.skipped or {}), {})
  for _, x in ipairs(ev.skipped or {}) do
    skipped[#skipped + 1] = shown(x[1]) .. ' - ' .. why_text(to, x[2])
  end
  local failed = {}
  for _, x in ipairs(ev.failed or {}) do
    failed[#failed + 1] = shown(x[1]) .. ': ' .. tostring(x[2])
  end
  local msg = ('%s → %s 복사: 파일 %d, 디렉터리 %d'):format(from:upper(), to:upper(), ev.files or 0, ev.dirs or 0)
  if #failed > 0 then
    say(msg .. ' / 실패 ' .. table.concat(failed, '; ') .. (#skipped > 0 and (' / 건너뜀 ' .. table.concat(skipped, ', ')) or ''),
      vim.log.levels.WARN)
  elseif #skipped > 0 then
    say(msg .. ' / 건너뜀 ' .. table.concat(skipped, ', '), vim.log.levels.WARN)
  else
    say(msg)
  end
end
copied_fn = on_copied

-- 편집 창(비교 중인 두 창)에서 <C-r>/<C-l>: 커서 줄(또는 고른 줄)을 오른쪽/왼쪽으로.
-- 바뀐 줄이 아니면 바로 위·아래에 끼인 줄(다른 쪽에만 있는 줄)이 있을 때만 그 덩어리째
local function applies()
  local s = sessions[api.nvim_get_current_tabpage()]
  local w = api.nvim_get_current_win()
  return s and (w == s.win_a or w == s.win_b) and vim.wo[w].diff and s or nil
end

function _G.vimide_dirdiff_copy_lines(dir)
  local s = applies()
  if not s then
    return
  end
  local w = api.nvim_get_current_win()
  local mode = api.nvim_get_mode().mode
  local count = vim.v.count1
  local l1, l2 = vim.fn.line('.'), vim.fn.line('.') + count - 1
  local visual = mode:match('^[vV\22]') ~= nil
  if visual then
    l1, l2 = vim.fn.line('v'), vim.fn.line('.')
    if l1 > l2 then
      l1, l2 = l2, l1
    end
    -- 비주얼을 끝낸다. feedkeys('<Esc>', 'x') 는 뒤에 쌓인 키까지 비주얼 안에서 먼저 돌렸다
    vim.cmd('normal! \27')
  end
  local in_a = w == s.win_a
  local put = (dir > 0) == in_a          -- 내 창에서 저쪽으로 보내기 / 저쪽에서 가져오기
  local other = in_a and s.win_b or s.win_a
  if not api.nvim_win_is_valid(other) then
    return
  end
  local mine, theirs = api.nvim_get_current_buf(), api.nvim_win_get_buf(other)
  local tb = put and theirs or mine
  -- 양쪽 다 진짜 파일이어야 한다: 빈 쪽(한쪽에만 있는 파일)·안내 쪽에서 가져오면 안내 글이
  -- 파일에 들어가거나 줄이 지워졌다
  for _, b in ipairs({ mine, theirs }) do
    if vim.bo[b].buftype ~= '' then
      local side = (b == s.empty_a or api.nvim_win_get_buf(s.win_a) == b) and 'A' or 'B'
      return say(side .. ' 쪽은 파일이 아닙니다 - 파일째는 트리에서 <C-r>/<C-l> 로 복사하세요',
        vim.log.levels.WARN)
    end
  end
  local cmd = put and 'diffput' or 'diffget'
  local range
  if visual or vim.fn.diff_hlID(l1, 1) ~= 0 then
    range = ('%d,%d'):format(l1, l2)
  elseif vim.fn.diff_filler(l1) > 0 then
    range = ''                           -- 바로 위에 끼인 줄: 그 덩어리
  elseif vim.fn.diff_filler(l1 + 1) > 0 then
    range = ('%d,%d'):format(l1, l1 + 1) -- 바로 아래에 끼인 줄
  else
    return say('이 줄에는 차이가 없습니다')
  end
  local tick = vim.b[tb].changedtick
  local ok, err = pcall(vim.cmd, range .. cmd)
  if not ok then
    say(tostring(err):gsub('^.-(E%d+:)', '%1'), vim.log.levels.WARN)
  elseif vim.b[tb].changedtick ~= tick then
    -- 복사 하나를 되돌리기 한 번으로 (그대로 두면 이어진 복사들이 한 번에 되돌려졌다)
    pcall(api.nvim_buf_call, tb, function()
      vim.cmd('let &g:undolevels = &g:undolevels')
    end)
  end
  pcall(vim.cmd, 'diffupdate')
end

-- 전역 <C-r>/<C-l> 를 비교 창에서만 가로챈다. 그 밖에서는 원래대로 (<C-r> 되돌리기 취소,
-- <C-l> 은 .vimrc 의 창 옮기기): expr 매핑이라 원래 키가 그 자리(쌓인 키 앞)에서 돈다 -
-- feedkeys 로 넘겼더니 빠르게 친 뒤의 키가 먼저 돌았다
local TAKE = { ['<C-r>'] = 1, ['<C-l>'] = -1 }
local prev_maps = {}

function _G.vimide_dirdiff_prev_key(id)
  local p = prev_maps[id]
  if p and p.callback then
    return p.callback()
  end
end

local function take_over()
  for lhs, dir in pairs(TAKE) do
    for _, mode in ipairs({ 'n', 'x' }) do
      local prev = vim.fn.maparg(lhs, mode, false, true)
      if type(prev) == 'table' and prev.desc and prev.desc:match('^DirDiff 비교 창') then
        prev = prev_maps[mode .. lhs]   -- 벌써 가로챈 것 - 처음 것을 그대로
      end
      if type(prev) ~= 'table' or vim.tbl_isempty(prev) then
        prev = nil
      end
      prev_maps[mode .. lhs] = prev
      local id = mode .. lhs
      vim.keymap.set(mode, lhs, function()
        if applies() then
          return ('<Cmd>lua _G.vimide_dirdiff_copy_lines(%d)<CR>'):format(dir)
        end
        local p = prev_maps[id]
        if not p then
          return lhs
        end
        if p.callback then
          return ('<Cmd>lua _G.vimide_dirdiff_prev_key(%q)<CR>'):format(id)
        end
        return p.rhs
      end, { expr = true, silent = true, replace_keycodes = true,
        desc = 'DirDiff 비교 창: 줄을 ' .. (dir > 0 and '오른쪽(B)' or '왼쪽(A)') .. '으로' })
    end
  end
end
-- .vimrc 를 다시 읽으면(:source) 그 map <C-l> 이 이것을 덮는다 - .vimrc 가 이것을 다시 부른다
function _G.vimide_dirdiff_take_over()
  if (tonumber(vim.g.vimide_dirdiff_copy_keys) or 1) ~= 0 then
    take_over()
  end
end
_G.vimide_dirdiff_take_over()

local function help()
  vim.notify(table.concat({
    'DirDiff 트리',
    '  <CR>        파일: 비교를 열고 편집 창으로 / 디렉터리: 펼치기·접기',
    '  o           비교를 열되 트리에 그대로',
    '  <C-n> <C-p> 다음 / 앞 차이 파일',
    '  l h         펼치기 / 접기(부모로)',
    '  O X         차이 있는 디렉터리 모두 펼치기 / 모두 접기',
    '  f           차이만 보기',
    '  R           다시 훑기      q  끝내기',
    '  <Tab>       A 쪽 / B 쪽 오가기     <Space> 그쪽 항목 고르기    U 고른 것 모두 풀기',
    '  <C-r> <C-l> 고른 것(또는 비주얼 줄, 커서 줄)을 A→B / B→A 로 복사 (묻고 나서)',
    '편집 창: <C-n> <C-p> = ]c [c (다음 / 앞 차이)',
    '         <C-r> <C-l> 커서 줄·고른 줄을 오른쪽(B) / 왼쪽(A) 으로 (저장은 :w)',
  }, '\n'))
end

-- ---------------------------------------------------------------------------
-- 열기 / 끝내기
-- ---------------------------------------------------------------------------

-- stay: 다른 탭에서 이 비교 탭을 닫았다 - 사용자가 있던 탭에 그대로 둔다
local function finish(s, stay)
  if s.done then
    return
  end
  s.done = true
  s.closing = true
  if s.job and s.job > 0 then
    send(s, { cmd = 'quit' })
    pcall(vim.fn.jobstop, s.job)
  end
  sessions[s.tab] = nil
  local here = api.nvim_get_current_tabpage()
  if api.nvim_tabpage_is_valid(s.tab) then
    api.nvim_set_current_tabpage(s.tab)
    pcall(vim.cmd, 'diffoff!')
    if #api.nvim_list_tabpages() > 1 then
      pcall(vim.cmd, 'tabclose')
    else
      -- 마지막 탭: 창 하나를 새 빈 버퍼로. 트리 창을 물려 쓰게 되므로 그 옵션을 걷는다
      pcall(vim.cmd, 'silent! only | enew')
      plain_window(api.nvim_get_current_win())
    end
  end
  if stay and api.nvim_tabpage_is_valid(here) then
    api.nvim_set_current_tabpage(here)
  elseif s.origin and api.nvim_tabpage_is_valid(s.origin) then
    api.nvim_set_current_tabpage(s.origin)
  end
  local kept = {}
  for b in pairs(s.opened) do
    if api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 0 then
      if vim.bo[b].modified then
        kept[#kept + 1] = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ':~:.')
      else
        pcall(api.nvim_buf_delete, b, { force = false })
      end
    end
  end
  for b in pairs(s.unload) do
    if unused(b) then
      pcall(api.nvim_buf_delete, b, { unload = true })
    end
  end
  for _, b in ipairs({ s.buf_l, s.empty_a, s.empty_b }) do
    if b and api.nvim_buf_is_valid(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
  if #kept > 0 then
    say('고친 채 남겨 둔 버퍼: ' .. table.concat(kept, ', '), vim.log.levels.WARN)
  end
end

local function restart(s)
  if s.job and s.job > 0 then
    local old = s.job
    s.job = nil
    pcall(vim.fn.chansend, old, vim.json.encode({ cmd = 'quit' }) .. '\n')
    pcall(vim.fn.jobstop, old)
  end
  local r = cur_row(s)
  s.want_rel = r and r.e and r.rel or nil   -- 커서가 있던 줄로 돌아간다 (그 줄이 다시 생기면)
  s.dirs, s.loading, s.dirty, s.prog = {}, {}, {}, nil
  if not start_job(s) then
    return
  end
  -- 맨 위만 청한다. 펼쳐 두었던 아래 디렉터리는 부모의 목록이 오면 on_event 가 청한다
  request_list(s, '')
  render(s)
end

local function map_list(s)
  local b = s.buf_l
  local function m(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = b, nowait = true, silent = true, desc = desc })
  end
  m('<CR>', function() act_enter(s, true) end, '비교 열고 편집 창으로 / 펼치기')
  m('<2-LeftMouse>', function() act_enter(s, true) end, '비교 열기')
  m('o', function() act_enter(s, false) end, '비교 열기 (트리에 그대로)')
  m('<C-n>', function() act_step(s, 1) end, '다음 차이')
  m('<C-p>', function() act_step(s, -1) end, '앞 차이')
  m('l', function()
    local r = cur_row(s)
    if r and r.e and is_dir(r.e) then
      toggle(s, r, true)
    end
  end, '펼치기')
  m('h', function() act_h(s) end, '접기 / 부모로')
  m('O', function() act_expand_all(s) end, '차이 있는 디렉터리 모두 펼치기')
  m('X', function() act_collapse_all(s) end, '모두 접기')
  m('f', function()
    s.filter = not s.filter
    render(s)
  end, '차이만 보기')
  m('R', function() restart(s) end, '다시 훑기')
  m('<Tab>', function() act_side(s) end, 'A 쪽 / B 쪽')
  m('<Space>', function() act_mark(s) end, '고르기')
  -- <Esc> 로 두었더니 습관처럼 누르는 Esc 에 고른 것이 사라졌다
  m('U', function() clear_marks(s) end, '고른 것 모두 풀기')
  m('<C-r>', function() act_copy(s, 1) end, 'A → B 복사')
  m('<C-l>', function() act_copy(s, -1) end, 'B → A 복사')
  for _, spec in ipairs({ { '<C-r>', 1 }, { '<C-l>', -1 } }) do
    vim.keymap.set('x', spec[1], function()
      local l1, l2 = vim.fn.line('v'), vim.fn.line('.')
      vim.cmd('normal! \27')   -- feedkeys('<Esc>', 'x') 는 뒤에 쌓인 키를 비주얼 안에서 먼저 돌렸다
      act_copy(s, spec[2], l1, l2)
    end, { buffer = b, nowait = true, silent = true, desc = spec[2] > 0 and 'A → B 복사' or 'B → A 복사' })
  end
  api.nvim_create_autocmd('CursorMoved', {
    buffer = b,
    callback = function()
      local old = s.side
      cursor_side(s)
      mark_side(s)
      if old ~= s.side then
        s.prog_dirty = true
        schedule_render(s)
      end
    end,
  })
  m('q', function()
    if s.copying then
      return say('복사하는 중입니다 - 끝난 뒤에 q', vim.log.levels.WARN)
    end
    finish(s)
  end, '끝내기')
  m('?', help, '도움말')
end

local function full_dir(d)
  -- 있는 경로는 그대로 ('P$x' 의 $x 를 환경 변수로 풀지 않게), 없으면 ~ · $VAR 를 풀어 본다
  if vim.fn.isdirectory(d) == 0 then
    d = vim.fn.expand(d, 1)
  end
  return (vim.fn.fnamemodify(d, ':p'):gsub('(.)/+$', '%1'))
end

-- 트리 창 (탭 맨 아래, 전체 너비). 옵션은 창에만(local) - vim.wo 는 :set 처럼 그 창의
-- 전역 값까지 바꾸어, 그 창에서 갈라 만든 창과 끝낸 뒤 남은 창이 번호 없이 남았다
local function open_tree_win(s)
  s.win_l = api.nvim_open_win(s.buf_l, true, { split = 'below', win = -1, height = s.list_h })
  for k, v in pairs({ number = false, relativenumber = false, wrap = false, cursorline = true,
    winfixheight = true, signcolumn = 'no', foldcolumn = '0', list = false, spell = false }) do
    pcall(api.nvim_set_option_value, k, v, { scope = 'local', win = s.win_l })
  end
end

function M.open(a, b)
  a, b = full_dir(a), full_dir(b)
  -- 링크를 푼 진짜 경로로: nvim 은 버퍼 이름의 디렉터리 쪽 링크를 풀어서 붙이므로, 그대로
  -- 두면 사용자 버퍼를 못 알아보고(우리 것으로 알고 지웠다) 저장 안 한 버퍼 검사도 비껴갔다
  a, b = uv.fs_realpath(a) or a, uv.fs_realpath(b) or b
  for _, d in ipairs({ a, b }) do
    if vim.fn.isdirectory(d) == 0 then
      return say('디렉터리가 아닙니다: ' .. d, vim.log.levels.WARN)
    end
  end
  if vim.fn.resolve(a) == vim.fn.resolve(b) then
    return say('같은 디렉터리입니다: ' .. vim.fn.fnamemodify(a, ':~'), vim.log.levels.WARN)
  end
  -- 같은 두 디렉터리를 이미 비교하고 있으면 그 탭으로 (새로 훑지 않는다 - 다시 훑기는 R)
  for tab, o in pairs(sessions) do
    if o.a == a and o.b == b and api.nvim_tabpage_is_valid(tab) then
      api.nvim_set_current_tabpage(tab)
      if not api.nvim_win_is_valid(o.win_l) and api.nvim_buf_is_valid(o.buf_l) then
        open_tree_win(o)   -- 트리 창을 닫아 버렸으면 (키는 모두 트리에 있다) 다시 연다
        render(o)
      end
      if api.nvim_win_is_valid(o.win_l) then
        api.nvim_set_current_win(o.win_l)
      end
      return say('이미 비교 중입니다 - 이 탭입니다 (다시 훑기는 R, 끝내기는 q)')
    end
  end
  if vim.fn.executable('python3') ~= 1 then
    return say('python3 이 없습니다 - :DirDiffClassic 을 쓰세요', vim.log.levels.WARN)
  end
  local s = {
    a = a, b = b, req = 0, dirs = {}, loading = {}, dirty = {},
    expanded = { [''] = true }, rows = {}, row_of = {}, opened = {}, unload = {},
    side = 'a', marks = { a = {}, b = {} }, offb = {}, offg = {},
    filter = (tonumber(vim.g.vimide_dirdiff_only_diff) or 0) ~= 0, reveal_step = 1,
    origin = api.nvim_get_current_tabpage(),
  }
  -- 곁창에서 :tabnew 하면 그 창 옵션을 물려받고 neo-tree 가 가져간다 - EDIT 창에서
  local w = _G.vimide_edit_slot and _G.vimide_edit_slot()
  if w and w ~= 0 and api.nvim_win_is_valid(w) then
    api.nvim_set_current_win(w)
  end
  vim.cmd('tabnew')
  s.tab = api.nvim_get_current_tabpage()
  s.win_a = api.nvim_get_current_win()
  local nb = api.nvim_get_current_buf()
  plain_window(s.win_a)
  api.nvim_win_set_buf(s.win_a, scratch(s, 'a', { '', '  아래 트리에서 파일을 고르고 Enter  (? 도움말)' }))
  -- :tabnew 가 만든 빈 [No Name] 은 곧바로 치운다 (비교할 때마다 하나씩 남았다)
  if api.nvim_buf_is_valid(nb) and api.nvim_buf_get_name(nb) == '' and not vim.bo[nb].modified
      and api.nvim_buf_line_count(nb) == 1 and api.nvim_buf_get_lines(nb, 0, 1, false)[1] == ''
      and #vim.fn.win_findbuf(nb) == 0 then
    pcall(api.nvim_buf_delete, nb, {})
  end
  vim.cmd('rightbelow vsplit')
  s.win_b = api.nvim_get_current_win()
  api.nvim_win_set_buf(s.win_b, scratch(s, 'b', { '' }))
  s.buf_l = api.nvim_create_buf(false, true)
  vim.bo[s.buf_l].bufhidden = 'hide'
  -- airline 이 창을 옮길 때마다 상태줄을 제 것으로 바꿔 진행·합계가 사라졌다
  vim.b[s.buf_l].airline_disable_statusline = 1
  vim.bo[s.buf_l].filetype = 'vimidedirdiff'
  api.nvim_buf_set_name(s.buf_l, 'DirDiff ' .. vim.fn.fnamemodify(a, ':t') .. ' <> ' .. vim.fn.fnamemodify(b, ':t') .. ' #' .. s.buf_l)
  s.list_h = tonumber(vim.g.vimide_dirdiff_list_height) or math.max(10, math.floor(vim.o.lines * 0.4))
  open_tree_win(s)
  vim.t.vimide_dirdiff_view = true
  sessions[s.tab] = s
  map_list(s)
  if not start_job(s) then
    finish(s)
    return
  end
  request_list(s, '')
  render(s)
end

-- 편집 창에서 <C-n>/<C-p> (.vimrc 의 ListStep 이 먼저 묻는다): ]c / [c
function _G.vimide_dirdiff_step(dir)
  local s = sessions[api.nvim_get_current_tabpage()]
  if not s then
    return false
  end
  local w = api.nvim_get_current_win()
  if (w == s.win_a or w == s.win_b) and vim.wo[w].diff then
    -- dir 의 크기가 횟수다 (.vimrc 가 v:count1 을 넘긴다): 2<C-n> = 2]c
    pcall(vim.cmd, 'normal! ' .. math.max(1, math.abs(dir)) .. (dir > 0 and ']c' or '[c'))
    return true
  end
  return false
end

function _G.vimide_dirdiff_open(a, b)
  M.open(a, b)
end

local group = api.nvim_create_augroup('VimIdeDirDiffView', { clear = true })
-- 탭을 닫을 때 그 탭에 있었는지: 있던 탭을 닫으면 TabLeave 가 먼저 뜬다 (같은 명령 안에서).
-- 다른 탭에서 :Ntabclose 로 닫았으면 원래 탭으로 끌고 가지 않는다
local leaving
api.nvim_create_autocmd('TabLeave', {
  group = group,
  callback = function()
    leaving = api.nvim_get_current_tabpage()
    vim.schedule(function()
      leaving = nil
    end)
  end,
})
api.nvim_create_autocmd('TabClosed', {
  group = group,
  callback = function()
    for tab, s in pairs(sessions) do
      if not api.nvim_tabpage_is_valid(tab) then
        local was_here = leaving == tab
        vim.schedule(function()
          finish(s, not was_here)
        end)
      end
    end
  end,
})
-- 비교가 연 버퍼를 사용자가 비교 탭 밖에서 띄우면 사용자 것이 된다 - 치우지 않는다
api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  callback = function(ev)
    if sessions[api.nvim_get_current_tabpage()] then
      return
    end
    vim.b[ev.buf].vimide_dirdiff = nil
    for _, s in pairs(sessions) do
      s.opened[ev.buf] = nil
      s.unload[ev.buf] = nil   -- 도로 내려 둘 버퍼도: 사용자가 쓰기 시작했다
    end
  end,
})
api.nvim_create_autocmd('WinResized', {
  group = group,
  callback = function()
    for _, s in pairs(sessions) do
      if api.nvim_win_is_valid(s.win_l) and vim.tbl_contains(vim.v.event.windows or {}, s.win_l) then
        render(s)
      end
    end
  end,
})
-- 끝낼 때 비교 탭을 모두 닫는다. 이 VimLeavePre 가 vimidesession 의 것보다 먼저 돈다
-- (plugin/ 을 이름 순으로 읽는다) - 닫지 않았더니 세션에 비교 탭(두 파일, diff 도 트리도
-- 없이)이 저장되어 다음에 열 때 되살아났고, 그때는 보통 :edit 이라 BufRead 훅까지 돌았다
api.nvim_create_autocmd('VimLeavePre', {
  group = group,
  callback = function()
    local all = {}
    for _, s in pairs(sessions) do
      all[#all + 1] = s
    end
    for _, s in ipairs(all) do
      pcall(finish, s, true)
    end
  end,
})

-- vim-dirdiff 가 없어도 (PlugInstall 전 등) :DirDiff 는 이 트리로. 있으면 dirdifftab.vim 이
-- 그 플러그인을 읽은 뒤에 같은 것으로 다시 정한다
if vim.fn.exists(':DirDiff') ~= 2 and (tonumber(vim.g.vimide_dirdiff_view) or 1) ~= 0 then
  api.nvim_create_user_command('DirDiff', function(o)
    if #o.fargs ~= 2 then
      return say('디렉터리 두 개를 주세요 - :DirDiff <A> <B>', vim.log.levels.WARN)
    end
    M.open(o.fargs[1], o.fargs[2])
  end, { nargs = '*', complete = 'dir', desc = '두 디렉터리 비교 (나란한 트리)' })
end

return M
