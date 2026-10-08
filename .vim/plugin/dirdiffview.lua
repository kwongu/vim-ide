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
--   <C-n>/<C-p> 다음/앞 '차이' 파일로 (접힌 디렉터리는 펼치며). 모두·차이 밖의 보기에서는 그
--               보기가 보이는 것으로 (좌측 최신이면 A 가 최신인 파일, 동일이면 같은 파일)
--   l / h       펼치기 / 접기(접혀 있으면 부모로)
--   O / X       차이 있는 디렉터리를 모두 펼치기 / 모두 접기 (트리 전체). 모두·차이 밖의 보기에서는
--               그 보기가 보이는 것이 아래에 있는 디렉터리를
--   f           보기 고르기 (Beyond Compare 의 보기: 모두 / 차이 / 고아 없음 / 좌측 최신 ...)
--   F           모두 보이기 <-> 차이 보이기
--   <Tab>       비교할 곳 고르기: 지금 쪽의 항목을 [A] 로, 다음 Tab 의 것을 [B] 로 - 곧바로 새
--               탭에서 비교 (디렉터리 둘이면 DirDiff, 파일 둘이면 vimdiff). [A] 줄에서 다시 Tab 은
--               취소. neo-tree 의 Tab 과 같은 [A] 다 (dirdiffpick.lua) - 트리가 달라도 된다
--   <S-Tab>     A 쪽 / B 쪽 (커서가 그쪽 이름으로. 마우스로 눌러도 된다)
--   <Space>     지금 쪽의 항목 고르기/풀기 (다음 줄로)       U  고른 것 모두 풀기
--   <C-r>/<C-l> A → B / B → A 로 파일·디렉터리 복사: 원본 쪽(A→B 면 A 트리)에서 고른 것,
--               없으면 비주얼 줄, 그것도 없으면 커서 줄. 이름을 보이고 묻고 나서, 뒤쪽이
--               항목마다 안전하게 한다 (같은 이름은 덮어쓰고 디렉터리는 합친다 - 지우지
--               않는다, 제외 목록은 건드리지 않는다, 대상 쪽 링크를 따라가 쓰지 않는다).
--               복사한 곳만 다시 본다 (그곳이 든 다른 비교 탭도)
--   R           다시 훑기        q  끝내기(탭을 닫는다)       ?  도움말
-- 편집 창(비교 중인 두 창)에서는 <C-n>/<C-p> 가 ]c/[c (다음/앞 차이), <C-r>/<C-l> 은
-- 커서가 있는 차이 덩어리째 오른쪽(B)/왼쪽(A)으로 (diffput/diffget - 저장은 :w).
-- <C-S-r>/<C-S-l> 은 커서 줄만 (터미널이 Ctrl+Shift 를 알려 줄 때 - iTerm2 CSI u, tmux
-- extended-keys), 어디서나 되는 것은 횟수(1<C-r> = 커서 줄, N<C-r> = N 줄)와 비주얼(고른 줄).
-- 커서 줄만(<C-S-r>, 1<C-r>)인데 그 줄이 바뀐 줄이 아니면, 바로 위(먼저)·아래에 끼인 줄(저쪽에만
-- 있는 줄) 덩어리째다 - 여러 줄일 수 있다.
-- 비교 탭 밖의 <C-r>(되돌리기 취소)·<C-l>(창 옮기기)은 그대로다.
--
-- 빠른 이유는 뒤쪽 dirdiffscan.py 에 적었다: 찾는 대로 보여 주고(펼쳐 둔 디렉터리
-- 먼저), 크기가 다르면 바로 '다름', 크기·시각이 같으면 '같음', 나머지만 뒤에서
-- 내용을 읽는다. 편집기는 한 번도 기다리지 않는다.
--
--   let g:vimide_dirdiff_view = 0          " :DirDiff 를 예전 목록(DirDiff.vim)으로
--   let g:vimide_dirdiff_only_diff = 1     " 처음부터 차이 보이기
--   let g:vimide_dirdiff_filter = 'right-newer'  " 처음 보기 (아래 MODES 의 id, only_diff 보다 먼저)
--   let g:vimide_dirdiff_trust_mtime = 0   " 크기·시각이 같아도 내용까지 읽기
--   let g:vimide_dirdiff_list_height = 16  " 트리 창 높이 (기본: 화면의 40%)
--   let g:vimide_dirdiff_max_mb = 20       " 이보다 큰 파일은 열지 않고 알림만
--   let g:vimide_dirdiff_confirm_copy = 0  " 트리의 <C-r>/<C-l> 복사를 묻지 않고
--   let g:vimide_dirdiff_copy_keys = 0     " <C-r>/<C-l>(<C-S-r>/<C-S-l>) 을 가로채지 않기 (편집 창)
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
local ns_pick = api.nvim_create_namespace('vimide_dirdiffview_pick')

local M = {}
local sessions = {} -- tabpage handle -> session

local BAD = { diff = true, onlyA = true, onlyB = true }

-- 보기 (Beyond Compare 의 보기 거르기). 항목의 표시(mask)는 뒤쪽이 매긴다 (dirdiffscan.py 의
-- SAME ... UNK): 고아 = 한쪽에만 있는 것 (좌측 고아 = A 에만), 최신 = 양쪽에 있고 내용이 다른데
-- 그쪽의 수정 시각이 늦은 것, 동일 = 같은 것. 양쪽에 있는 디렉터리의 표시는 그 아래 모두의 것을
-- 합한 것이라, 그 아래에 보일 것이 있는 디렉터리만 보인다 (접혀 있어도)
local band = bit.band
local SAME, NA, NB, DX, OA, OB, PEND, UNK = 1, 2, 4, 8, 16, 32, 64, 128
local MODES = {
  { id = 'all', label = '모두 보이기' },
  { id = 'diff', label = '차이 보이기', bits = NA + NB + DX + OA + OB },
  { id = 'no-orphans', label = '고아 없음 보이기', bits = SAME + NA + NB + DX, both = true },
  { id = 'diff-no-orphans', label = '고아 없는 차이 보이기', bits = NA + NB + DX },
  { id = 'orphans', label = '고아 보이기', bits = OA + OB },
  { id = 'left-newer', label = '좌측 최신 보이기', bits = NA },
  { id = 'right-newer', label = '우측 최신 보이기', bits = NB },
  { id = 'left-newer-orphans', label = '좌측의 최신과 고아 보이기', bits = NA + OA },
  { id = 'right-newer-orphans', label = '우측 최신과 고아 보이기', bits = NB + OB },
  { id = 'left-orphans', label = '좌측 고아 보이기', bits = OA },
  { id = 'right-orphans', label = '우측 고아 보이기', bits = OB },
  { id = 'same', label = '동일 보이기', bits = SAME },
}
local MODE = {}
for i, md in ipairs(MODES) do
  md.i = i
  MODE[md.id] = md
end

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
  def('VimIdeDirDiffPickA', { link = 'Search' })      -- Tab 으로 고른 [A] (dirdiffpick.lua 와 같은 것)
  def('VimIdeDirDiffMenuNow', { link = 'Title' })     -- 보기 메뉴의 지금 보기
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
local menu_fill, step_bits, restart_fn, walk_fn

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
      if me ~= s.job or s.closing then
        return
      end
      vim.schedule(function()
        if me ~= s.job then
          return
        end
        -- 뒤쪽이 죽었다: 하던 복사는 끝나지 않는다 ('copied' 가 오지 않는다). 풀어 두지 않았더니
        -- q 와 그 뒤의 복사가 끝내 '복사하는 중' 으로 거절되었다
        s.job = nil
        local c = s.copying
        s.copying = nil
        local msg = {}
        if c then
          msg[#msg + 1] = ('%s → %s 복사가 중간에 멈췄습니다 - %s 쪽에 일부만 복사되었을 수 있습니다 (R 로 다시 훑기)')
            :format(c.from:upper(), c.to:upper(), c.to:upper())
        end
        if code ~= 0 then
          msg[#msg + 1] = '비교가 멈췄습니다 (code ' .. code .. ') ' .. (s.stderr or '')
        end
        if #msg > 0 then
          say(table.concat(msg, ' / '), vim.log.levels.WARN)
        end
      end)
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
      ma = nz(e[6]), mb = nz(e[7]), st = e[8], rerr = nz(e[9]), m = nz(e[10]) }
    d.entries[#d.entries + 1] = x
    d.idx[x.name] = x
    if e[10] == nil then
      s.nomask = true   -- 예전 뒤쪽 (표시를 보내지 않는다 - mask_of 가 어림한다, walk)
    end
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
    if s.walk and s.walk.wait == ev.dir then
      s.walk.wait = nil
      walk_fn(s)              -- 예전 뒤쪽의 보기 <C-n>/<C-p>: 기다리던 목록이 왔다 (walk)
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
        if step_bits(s) then
          say(s.reveal_step > 0 and (done and '이 보기에서 마지막입니다' or '아래로는 아직 이 보기에 맞는 것이 없습니다 (훑는 중)')
            or (done and '이 보기에서 처음입니다' or '위로는 아직 이 보기에 맞는 것이 없습니다 (훑는 중)'))
        else
          say(s.reveal_step > 0 and (done and '마지막 차이입니다' or '아래로는 아직 찾은 차이가 없습니다 (훑는 중)')
            or (done and '첫 차이입니다' or '위로는 아직 찾은 차이가 없습니다 (훑는 중)'))
        end
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
        e.sa, e.sb, e.ma, e.mb, e.rerr, e.m = nz(x[4]), nz(x[5]), nz(x[6]), nz(x[7]), nz(x[9]), nz(x[10])
      end
      s.dirty[join(ev.d, ev.n)] = true
      schedule_render(s)
    end
  elseif k == 'progress' then
    s.prog = ev
    s.prog_dirty = true
    schedule_render(s)
    if s.menu then
      menu_fill(s)   -- 보기 메뉴의 수도 훑는 대로
    end
  elseif k == 'error' then
    say(ev.msg or '?', vim.log.levels.WARN)
  end
end

-- ---------------------------------------------------------------------------
-- 그리기
-- ---------------------------------------------------------------------------

-- 지금 보기가 거르는가 (모두 보이기가 아닌가)
local function filtering(s)
  return MODE[s.mode].bits ~= nil
end

-- 표시가 없으면 (뒤쪽이 예전 것) 판정으로 어림한다 - 디렉터리는 '같음' 이 아니면 늘 보인다. '다름' 은
-- 뒤쪽의 item_mask 처럼 날짜로 최신 쪽을 가린다 (예전 뒤쪽도 날짜는 보낸다): 모두 DX 로 두었더니 좌측·우측
-- 최신 보기에 파일이 하나도 보이지 않았다
local function mask_of(e)
  if e.m then
    return e.m
  end
  if both_dirs(e) then
    -- '같음' 인 디렉터리는 그 아래를 다 훑었고 모두 같다 - 동일이다. 늘 UNK 로 두었더니 차이·고아·최신
    -- 보기에도 같은 디렉터리(빈 것도)가 남았다 (예전 .lua 는 '같음' 을 걸렀다)
    return e.st == 'same' and SAME or UNK
  end
  if e.st == 'diff' then
    if e.ka ~= e.kb then
      return DX + (e.ka == 'd' and OA or 0) + (e.kb == 'd' and OB or 0)
    end
    if e.ma and e.mb and e.ma ~= e.mb then
      return e.ma > e.mb and NA or NB
    end
    return DX
  end
  return ({ same = SAME, onlyA = OA, onlyB = OB, pend = PEND })[e.st] or DX
end

-- 보기에 이 줄이 보이는가. 아직 모르는 것(견주는 중, 훑지 않은 디렉터리)은 될 수 있는 것이면
-- 보인다 - 그래야 훑는 동안 줄이 새로 생기지 않고 빠지기만 해서, 바뀐 줄만 지우면 된다
-- (render_dirty. 생기는 줄이 있으면 그때마다 트리 전체를 다시 그려야 한다)
local function visible(s, e)
  local bits = MODE[s.mode].bits
  if not bits then
    return true
  end
  local m = mask_of(e)
  if band(m, bits) ~= 0 or band(m, UNK) ~= 0 then
    return true
  end
  if both_dirs(e) then
    -- 디렉터리 자신: 양쪽에 있으니 고아가 아니고, '같음' 이면 동일이다
    if MODE[s.mode].both or (band(bits, SAME) ~= 0 and e.st == 'same') then
      return true
    end
    return band(m, PEND) ~= 0 and band(bits, SAME + NA + NB + DX) ~= 0
  end
  if band(m, PEND) == 0 then
    return false
  end
  -- 견주는 중인 파일: 고아는 아니다. 날짜를 알면 최신 쪽으로 좁힌다 - 그러지 않으면 좌측 최신
  -- 보기에 B 쪽이 늦은 파일도 내용을 다 읽을 때까지 보인다
  if band(bits, SAME + DX) ~= 0 then
    return true
  end
  local known = e.ma and e.mb
  return (band(bits, NA) ~= 0 and (not known or e.ma > e.mb))
    or (band(bits, NB) ~= 0 and (not known or e.mb > e.ma)) or false
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
  -- name_vis: 채운 빈칸을 뺀 이름 끝 (Tab 으로 고른 [A] 를 그 뒤에 단다)
  return ind .. icon .. name .. tail, { name_start = #ind + #icon, name_end = #ind + #icon + #name, tail = #tail,
    name_vis = #ind + #icon + #(name:gsub(' +$', '')) }
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
    parts[#parts + 1] = '바뀐 곳을 다시 보는 중'   -- 복사한 곳, :w 로 저장한 파일
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
  return ' DirDiff  ' .. table.concat(parts, ' · ') .. '   [' .. MODE[s.mode].label .. ']'
    .. '   [' .. (s.side == 'b' and 'B' or 'A') .. ' 쪽]   (? 도움말)'
end

-- 보이는 줄이 하나도 없을 때
local function empty_text(s)
  if not (s.prog and s.prog.done) then
    return '  (훑는 중…)'
  end
  if s.mode == 'all' or s.mode == 'diff' then
    return '  (차이가 없습니다)'
  end
  return ('  (%s: 보일 것이 없습니다 - f 로 보기를 바꿉니다)'):format(MODE[s.mode].label)
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
    lines = { empty_text(s) }
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

-- 바뀐 줄만 다시 그린다. 보기가 거르고 있으면(차이 보이기 등) 보기에서 빠진 줄은 그 줄만(펼친
-- 아래까지) 지우고, 새로 보일 줄이 생길 때만 전부 그린다 - 처음에는 거르기가 켜져 있으면 늘 전부 그렸더니,
-- 훑는 동안 60ms 마다 트리 전체를 다시 만들어 편집기가 훑는 시간의 60% 동안 멎었다 (2만 파일
-- 한 폴더, 실측)
local function render_dirty(s)
  s.render_pending = false
  if not (api.nvim_buf_is_valid(s.buf_l) and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  local drop = {}
  if filtering(s) then
    for rel in pairs(s.dirty) do
      local i = s.row_of[rel]
      if not i then
        -- 없던 줄이 보이게 되었다 (펼쳐 보이는 디렉터리 안에서 '같음' 이 아니게 되었다)
        local e = entry_of_fn(s, rel)
        local parent = rel:match('^(.*)/[^/]+$') or ''
        if e and visible(s, e) and (parent == '' or (s.row_of[parent] and s.expanded[parent])) then
          return render(s)
        end
      elseif not visible(s, s.rows[i].e) then
        local j = i
        while s.rows[j + 1] and s.rows[j + 1].depth > s.rows[i].depth do
          j = j + 1
        end
        drop[#drop + 1] = { i, j }
      end
    end
  end
  local L = layout(s)
  vim.bo[s.buf_l].modifiable = true
  for rel in pairs(s.dirty) do
    local i = s.row_of[rel]
    if i and s.rows[i] and visible(s, s.rows[i].e) then
      local t, h, ob, og = line_of(s, L, s.rows[i])
      s.offb[i], s.offg[i] = ob, og
      api.nvim_buf_set_lines(s.buf_l, i - 1, i, false, { t })
      api.nvim_buf_clear_namespace(s.buf_l, ns, i - 1, i)
      put_hls(s, i, h)
    end
  end
  if #drop > 0 then
    local gone = {}
    for _, d in ipairs(drop) do
      for k = d[1], d[2] do
        gone[k] = true
      end
    end
    -- 아래에서부터 이어진 덩어리째 지운다. 색(extmark)을 먼저 걷는다 - 줄만 지웠더니 폭 0 짜리
    -- 색이 다음 줄에 쌓였다
    local k = #s.rows
    while k >= 1 do
      if gone[k] then
        local hi = k
        while k > 1 and gone[k - 1] do
          k = k - 1
        end
        api.nvim_buf_clear_namespace(s.buf_l, ns, k - 1, hi)
        api.nvim_buf_set_lines(s.buf_l, k - 1, hi, false, {})
      end
      k = k - 1
    end
    local rows, offb, offg = {}, {}, {}
    for i, r in ipairs(s.rows) do
      if not gone[i] then
        local n = #rows + 1
        rows[n], offb[n], offg[n] = r, s.offb[i], s.offg[i]
      end
    end
    s.rows, s.offb, s.offg, s.row_of = rows, offb, offg, {}
    for i, r in ipairs(rows) do
      if r.e then
        s.row_of[r.rel] = i
      end
    end
  end
  vim.bo[s.buf_l].modifiable = false
  s.dirty = {}
  if #s.rows == 0 then
    return render(s)   -- '(차이가 없습니다)' / '(훑는 중…)'
  end
  if #drop > 0 then
    mark_side(s)
  end
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
    -- 비주얼 시작 줄은 그대로라 고르지 않은 줄까지 복사되었다 (보기가 거르고 있으면 바뀐 줄만
    -- 그려도 보기에서 빠진 줄이 지워지며 밀린다)
    if (s.need_full or filtering(s)) and api.nvim_get_current_win() == s.win_l
        and api.nvim_get_mode().mode:match('^[vV\22]') then
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

-- :diffoff 는 foldmethod 가 manual 로 돌아오면 diff 가 만든 접기를 manual 접기로 남겨 두고 'foldenable' 을
-- 끈다 - 그 접기를 지우고 'foldenable' 은 이 창의 전역 값으로 (새로 연 창과 같게). 지금 창에서, diff 였던
-- 창의 :diffoff 바로 뒤에 부른다. 버퍼가 창에서 내려가거나 창이 닫히면 nvim 은 그 창의 옵션과 접기를
-- 버퍼에 적어 두었다가(wininfo) 그 버퍼를 다음에 여는 창에 입힌다: 비교에서 내려간 버퍼(다른 짝으로
-- 바꿨을 때의 사용자 버퍼, q 뒤에 남긴 고친 버퍼)를 다시 열면 nofoldenable 에 닫힌 diff 접기가 남아 있었다
local function undiff_folds()
  if vim.wo.foldmethod == 'manual' then
    pcall(vim.cmd, 'normal! zE')
    pcall(vim.cmd, 'let &l:foldenable = &g:foldenable')
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
local function show_file(s, win, path, side)
  if not path then
    api.nvim_win_set_buf(win, scratch(s, side, {}))
    return
  end
  -- 이 창에 이미 그 파일이 떠 있고 고친 채면 다시 읽지 않는다. :edit 이 같은 버퍼를
  -- 다시 읽으려다 'E37: No write since last change' 를 냈다 - <C-r>/<C-l> 로 복사해
  -- 놓고 트리에서 같은 줄을 o / Enter 로 다시 열 때 (서버에서 실제로 났다, 재현).
  -- 고친 것을 그대로 두고 비교만 다시 맞춘다 (고치지 않았으면 디스크에서 다시 읽는다)
  local cur = api.nvim_win_get_buf(win)
  if vim.bo[cur].modified then
    local rc, rp = uv.fs_realpath(api.nvim_buf_get_name(cur)), uv.fs_realpath(path)
    if rc and rc == rp then
      return
    end
  end
  -- 누구 버퍼인지는 열기 바로 앞에 본다 (비교를 시작할 때 한 번 찍어 둔 목록으로 보았더니,
  -- 그 뒤 사용자가 연 버퍼를 비교가 연 것으로 알고 지웠다). 이름으로 찾지 않고 연 뒤의 버퍼가
  -- 열기 전에도 있던 것인지로 본다: nvim 은 같은 파일이면 철자가 달라도(macOS 의 Foo.c/foo.c,
  -- NFC/NFD - 트리는 A 쪽 철자로 연다) 있던 버퍼를 쓰는데, 이름으로 찾았더니 그런 사용자 버퍼를
  -- 비교의 것으로 알고 치웠다 (bufnr() 는 이름을 무늬로 보아 쓰지 않는다)
  -- buflisted() 로 본다. :bd 로 닫은(내려 둔) 버퍼의 옵션을 vim.bo 로 읽으면 nvim 이
  -- 끝날 때 그 파일의 소문자 마크와 마지막 자리('")를 shada 에 적지 않는다 (실측) -
  -- 비교 쌍을 열 때마다 모든 버퍼를 돌므로 그 파일들의 마크가 사라졌다
  local before = {}
  for _, x in ipairs(api.nvim_list_bufs()) do
    before[x] = { listed = vim.fn.buflisted(x) == 1, loaded = api.nvim_buf_is_loaded(x), ours = vim.b[x].vimide_dirdiff }
  end
  -- noautocmd: 비교하려고 연 파일에서 vim-ide 의 BufRead 훅이 돌지 않게 - 색인이 없는
  -- 트리면 autoindex 가 그 트리 전체의 GTAGS 를 만들기 시작하고(트리 안에 .tags/ 를
  -- 쓴다), gutentags 도 붙는다. 비교는 보기일 뿐이다. 구문 색은 filetype 을 따로 준다.
  -- 이름은 Ex 줄로 만들지 않고 인자로 넘긴다: 이름에 줄바꿈이 있으면 fnameescape 로도 줄이
  -- 갈라져, 없는 'nl\' 을 열고 나머지 'name.c' 를 명령으로 돌렸다 (E492). magic.file=false 라
  -- % # 이나 무늬도 풀지 않는다
  local wi = vim.o.wildignore
  vim.o.wildignore = ''
  local ok, err = pcall(api.nvim_win_call, win, function()
    vim.cmd.edit({ args = { path }, magic = { file = false },
      mods = { silent = true, keepalt = true, noautocmd = true, hide = true } })
  end)
  vim.o.wildignore = wi
  if not ok then
    -- nvim_win_call 이 붙여 오는 stack traceback 은 뺀다 (여러 줄이라 Press ENTER 가 떴다)
    say((tostring(err):gsub('\nstack traceback:.*$', ''):gsub('^.-(E%d+:)', '%1')), vim.log.levels.WARN)
    return
  end
  local b = api.nvim_win_get_buf(win)
  local pre = before[b]
  if not pre or pre.ours or (not pre.listed and not pre.loaded) then
    -- 없던 것, 다른 비교가 연 것(함께 가진다), 지워져 있던 것: 이 비교의 것
    s.opened[b] = true
    vim.b[b].vimide_dirdiff = true
  elseif not pre.loaded then
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
  -- getbufvar: :bd 로 닫은 버퍼를 vim.bo 로 읽으면 그 파일의 마크가 shada 에서 빠진다 (위 show_file)
  return api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 0
    and vim.fn.getbufvar(b, '&modified') ~= 1
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
  -- 다른 탭의 비교에서 짝을 다시 열 때(다른 탭에서 한 복사·저장 뒤) 그 탭의 지금 창을 지킨다: 아래
  -- BufEnter 훅(BufExplorer 등)이 nvim_win_call 안에서 그 탭의 지금 창을 B 창으로 옮겨 놓아, gT·q 로
  -- 돌아가면 커서가 트리가 아니라 B 창에 있었다 (f 는 f{char}, <C-r> 은 diffget 이 되었다)
  local tab_win = s.tab ~= api.nvim_get_current_tabpage() and api.nvim_tabpage_get_win(s.tab) or nil
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
  -- 창 머리(winbar)도 걷고 나서 버퍼를 바꾼다: nvim 은 창에서 내려가는 버퍼에 그 창의 옵션을 적어
  -- 두었다가(wininfo) 그 버퍼를 새 창에 띄울 때 입힌다 - 그대로 두었더니 앞에 본 파일을 다른 탭에서
  -- 열면(Tab/Tab 의 vimdiff, :tabnew) 이 비교의 ' A: …' 머리가 따라왔다. 새 머리는 아래 set_head 가 단다
  -- diff 접기도 같은 까닭으로 걷는다 (undiff_folds)
  for _, w in ipairs({ s.win_a, s.win_b }) do
    pcall(api.nvim_win_call, w, function()
      local was = vim.wo.diff
      vim.cmd('diffoff')
      if was then
        undiff_folds()
      end
      vim.wo.winbar = ''
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
  s.bin = bin   -- 두 창이 알림이다 (편집 창의 <C-r>/<C-l> 이 알린다)
  mark_open(s)
  if tab_win and api.nvim_win_is_valid(tab_win) and api.nvim_tabpage_is_valid(s.tab)
      and api.nvim_tabpage_get_win(s.tab) ~= tab_win then
    pcall(api.nvim_tabpage_set_win, s.tab, tab_win)
  end
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
    -- 한쪽은 디렉터리, 한쪽은 파일(링크·특수 파일): 파일 쪽을 안내 옆에 보인다. 디렉터리면
    -- 늘 여기서 끝냈더니 o 는 아무것도 하지 않았고, 다른 쪽의 파일은 트리에서 열 수 없었다
    if r.e.ka and r.e.kb and not both_dirs(r.e) then
      open_pair(s, r, false)
    end
    return
  end
  open_pair(s, r, jump)
end

-- <C-n>/<C-p>·O 가 찾을 것 (뒤쪽 next/expand 의 bits). 모두·차이 보기는 nil - 예전대로 '차이'.
-- 다른 보기는 그 보기의 차이(최신·고아 ...)를, 차이가 없는 보기(동일)는 그 보기의 것을 - 보이지
-- 않는 줄로 가면 커서가 갈 곳이 없다
step_bits = function(s)
  local bits = MODE[s.mode].bits
  if not bits or s.mode == 'diff' then
    return nil
  end
  local b = band(bits, NA + NB + DX + OA + OB)
  return b ~= 0 and b or bits
end

-- 예전 뒤쪽(dirdiffscan.py 를 빼고 .lua 만 바꿔 넣었을 때 - 항목에 표시가 없다)에서 보기의 <C-n>/<C-p>.
-- 그 뒤쪽의 next 는 bits 를 몰라 '차이' 만 돌려준다: 보기가 감춘 차이면 그 뒤부터 다시 묻게 했더니 감춘
-- 것이 200 개를 넘으면 아무 말 없이 멈췄고, 동일 보기는 '같음' 을 받지 못해 늘 '마지막' 이었고, 물으며
-- 지난 디렉터리(접어 둔 것도)가 모두 펼쳐졌다. 그래서 여기서 걷는다: 받은 목록을 트리 차례로 따라가며
-- 그 보기의 항목(뒤쪽 items_in_order 의 기준 - 양쪽에 있는 디렉터리는 들어가 보고, 나머지는 표시로)을
-- 찾는다. 목록이 없거나 옛것인(접혀 있어 'u' 를 받지 않는) 디렉터리는 청해 받고 이어 걷는다 (on_event
-- 의 'list'). 펼치는 것은 찾은 항목의 조상만, 걸으며 받은 나머지 목록은 뒤쪽에 도로 내려 둔다(unlist)
local function walk_hit(e, bits)
  if both_dirs(e) then
    return e.rerr ~= nil and band(bits, DX) ~= 0
  end
  return band(mask_of(e), bits) ~= 0
end

local function walk_into(e, bits)
  return both_dirs(e) and e.rerr == nil and (e.st ~= 'same' or band(bits, SAME) ~= 0)
end

-- 걸으며 받은 목록 중 펼치지 않은 것은 뒤쪽이 더 따라가지 않게 (접을 때의 unlist 처럼)
local function walk_drop(s, w)
  for rel in pairs(w.fresh) do
    if rel ~= '' and not s.expanded[rel] then
      send(s, { cmd = 'unlist', dir = rel })
    end
  end
end

local function walk_end(s, w, path)
  s.walk = nil
  local p = path and path:match('^(.*)/[^/]+$')
  while p do
    s.expanded[p] = true
    p = p:match('^(.*)/[^/]+$')
  end
  walk_drop(s, w)
  if not path then
    local done = s.prog and s.prog.done
    return say(w.step > 0 and (done and '이 보기에서 마지막입니다' or '아래로는 아직 이 보기에 맞는 것이 없습니다 (훑는 중)')
      or (done and '이 보기에서 처음입니다' or '위로는 아직 이 보기에 맞는 것이 없습니다 (훑는 중)'))
  end
  render(s)
  if s.row_of[path] and api.nvim_win_is_valid(s.win_l) then
    goto_row(s, s.row_of[path])
    mark_side(s)
  end
end

-- 예전 뒤쪽에서 보기의 O 도 여기서 걷는다: 그 뒤쪽의 expand 는 bits 를 몰라 '차이' 가 있는 디렉터리를
-- 모두 펼쳤다 - 동일 보기에서 보기가 감춘 차이의 디렉터리가 속이 빈 채 펼쳐지고, 보기의 것(같은 파일)이
-- 든 디렉터리는 접힌 채였다. 양쪽에 있는 디렉터리를 들어가 보며(walk_into) 보기의 항목(walk_hit)이 든
-- 디렉터리와 그 조상만 펼친다 (새 뒤쪽 cmd_expand 와 같은 것, 목록 2000 개까지). w.todo: 볼 디렉터리,
-- w.open: 보기의 항목이 든 디렉터리. 걸으며 받은 나머지 목록은 도로 내려 둔다 (walk_drop)
local function expand_walk(s)
  local w = s.walk
  while #w.todo > 0 do
    local rel = w.todo[#w.todo]
    local d = s.dirs[rel]
    if not (d and (rel == '' or s.expanded[rel] or w.fresh[rel])) then
      w.fresh[rel] = true
      w.wait = rel
      return request_list(s, rel)
    end
    w.todo[#w.todo] = nil
    w.n = w.n + 1
    for _, e in ipairs(d.entries) do
      if walk_hit(e, w.bits) then
        w.open[rel] = true
      end
      if walk_into(e, w.bits) and w.n + #w.todo < 2000 then
        w.todo[#w.todo + 1] = join(rel, e.name)
      end
    end
  end
  s.walk = nil
  for rel in pairs(w.open) do
    while rel ~= '' do
      s.expanded[rel] = true
      rel = rel:match('^(.*)/[^/]+$') or ''
    end
  end
  walk_drop(s, w)
  render(s)
end

-- w.cur: 마지막으로 본 경로, w.down: 그 디렉터리 안을 볼 차례 (앞으로는 먼저, 뒤로는 그 디렉터리보다 먼저)
local function walk(s)
  local w = s.walk
  if not w or w.wait then
    return
  end
  if w.todo then
    return expand_walk(s)   -- O 의 걷기 (on_event 의 'list' 가 이리로 이어 준다)
  end
  local function list(rel)
    local d = s.dirs[rel]
    if d and (rel == '' or s.expanded[rel] or w.fresh[rel]) then
      return d
    end
    w.fresh[rel] = true
    w.wait = rel
    request_list(s, rel)
  end
  local function find(d, name)
    for i, e in ipairs(d.entries) do
      if e.name == name then
        return i
      end
    end
  end
  while true do
    local e, rel
    if w.down then
      local d = list(w.cur)
      if not d then
        return
      end
      w.down = false
      local x = w.step > 0 and d.entries[1] or d.entries[#d.entries]
      if x then
        e, rel = x, join(w.cur, x.name)
      end
    end
    if not e then
      if w.cur == '' then
        return walk_end(s, w, nil)
      end
      local parent, name = w.cur:match('^(.*)/([^/]+)$')
      parent, name = parent or '', name or w.cur
      local d = list(parent)
      if not d then
        return
      end
      local i = find(d, name)
      if not i then
        return walk_end(s, w, nil)
      end
      local x = d.entries[i + w.step]
      if x then
        e, rel = x, join(parent, x.name)
      elseif w.step > 0 then
        w.cur = parent   -- 이 디렉터리를 다 보았다 - 부모의 다음으로
      else
        -- 뒤로: 디렉터리 안을 다 본 뒤에 그 디렉터리 자신
        w.cur = parent
        local pp, pn = parent:match('^(.*)/([^/]+)$')
        local pd = parent ~= '' and s.dirs[pp or '']
        local pe = pd and pd.idx[pn or parent]
        if pe and walk_hit(pe, w.bits) then
          return walk_end(s, w, parent)
        end
      end
    end
    if e then
      w.cur = rel
      if w.step < 0 and walk_into(e, w.bits) then
        w.down = true    -- 뒤로: 안의 것이 먼저
      elseif walk_hit(e, w.bits) then
        return walk_end(s, w, rel)
      elseif w.step > 0 then
        w.down = walk_into(e, w.bits)
      end
    end
  end
end
walk_fn = walk

local function act_step(s, step)
  local r = cur_row(s)
  local from = r and (r.loading and r.rel:gsub('/$', '') or r.rel) or ''
  s.req = s.req + 1
  s.reveal_step = step
  if s.walk then
    walk_drop(s, s.walk)   -- 아직 목록을 기다리던 앞의 것
    s.walk = nil
  end
  if s.nomask and step_bits(s) then
    local e = from ~= '' and entry_of_fn(s, from)
    s.walk = { step = step, bits = step_bits(s), fresh = {}, cur = from,
      down = from == '' or (step > 0 and e and walk_into(e, step_bits(s))) or false }
    return walk(s)
  end
  send(s, { cmd = 'next', id = s.req, from = from, step = step, bits = step_bits(s) })
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
  if s.walk then
    walk_drop(s, s.walk)   -- 아직 목록을 기다리던 앞의 것 (act_step 처럼)
    s.walk = nil
  end
  if s.nomask and step_bits(s) then
    -- 예전 뒤쪽: 보기를 따라 여기서 걷는다 (expand_walk). 뒤쪽의 expand 는 '차이' 의 디렉터리를 펼친다
    s.walk = { todo = { '' }, open = {}, fresh = {}, n = 0, bits = step_bits(s) }
    return walk(s)
  end
  send(s, { cmd = 'expand', id = s.req, dir = '', bits = step_bits(s) })
end

local function act_collapse_all(s)
  local r = cur_row(s)
  local top = r and r.rel and r.rel:match('^[^/]+')
  if s.walk then
    walk_drop(s, s.walk)   -- 걷던 O·<C-n> 이 목록이 온 뒤에 도로 펼치지 않게
    s.walk = nil
  end
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

-- ---------------------------------------------------------------------------
-- 비교할 곳 고르기 (Tab: [A] -> [B], neo-tree 의 Tab 처럼). [A] 는 neo-tree 의 것과 같은 하나다
-- - dirdiffpick.lua 가 들고 있고 [B] 에서 연다. 그래서 트리가 달라도 된다: 이 트리에서 [A],
-- 다른 비교 탭의 트리나 neo-tree 에서 [B]
-- ---------------------------------------------------------------------------

local function act_pick(s)
  local r = cur_row(s)
  if not (r and r.e) then
    return
  end
  cursor_side(s)
  local side = s.side
  local k
  if side == 'a' then
    k = r.e.ka
  else
    k = r.e.kb
  end
  if k == nil then
    -- 다른 쪽에만 있는 줄의 빈칸: 고를 것이 없다
    return say(('%s 쪽에 없는 항목입니다 - %s 쪽에서 고르세요 (<S-Tab> 쪽 바꾸기)')
      :format(side:upper(), side == 'a' and 'B' or 'A'))
  end
  if not _G.vimide_dirdiff_pick_path then
    return say('dirdiffpick.lua 가 없습니다', vim.log.levels.WARN)
  end
  local path = s[side] .. '/' .. r.rel
  -- 링크는 가리키는 것으로 (디렉터리를 가리키면 디렉터리)
  local rk = real_kind(k, path)
  local kind = (rk == 'd' or rk == 'ld') and 'dir' or ((rk == 'f' or rk == 'lf') and 'file') or nil
  if not kind then
    return say(('고를 수 없습니다 - %s 쪽은 %s: %s'):format(side:upper(), NOTE[rk] or '특수 파일', shown(r.rel)),
      vim.log.levels.WARN)
  end
  local tab = api.nvim_get_current_tabpage()
  _G.vimide_dirdiff_pick_path(path, kind)
  -- [B] 로 새 탭을 열었다. 새 탭은 편집 창에서 연다 (M.open, dirdiffpick.lua 의 tab_from_edit) -
  -- 그대로 두면 그 탭을 닫고 돌아왔을 때 이 탭의 커서가 위의 편집 창에 있다. 트리로 되돌려 둔다
  -- (키는 모두 트리에 있다). 잠깐 오가는 것이라 autocmd 는 돌리지 않는다
  if api.nvim_get_current_tabpage() ~= tab and api.nvim_win_is_valid(s.win_l) then
    local w = api.nvim_get_current_win()
    vim.cmd(('noautocmd call nvim_set_current_win(%d) | noautocmd call nvim_set_current_win(%d)'):format(s.win_l, w))
  end
end

local function session_of_buf(buf)
  for _, s in pairs(sessions) do
    if s.buf_l == buf then
      return s
    end
  end
end

-- [A] 를 그 줄의 그쪽 이름 바로 뒤에 (이름이 칸을 채웠으면 칸 끝에 겹쳐). 그릴 때마다 줄을
-- 찾는다 (dirdiffpick.lua 와 같은 까닭): 트리는 펼치기·보기 바꾸기·훑은 결과로 줄을 통째로 다시
-- 쓴다 - 표시를 버퍼에 박아 두면 다른 줄로 밀리거나 지워진다. 보기에서 빠져 줄이 없으면 달지 않는다
local function pick_mark(s, buf, top, bot, first)
  for _, p in ipairs({ first.path, first.real }) do
    for _, side in ipairs({ 'a', 'b' }) do
      local root = s[side] .. '/'
      if p:sub(1, #root) == root then
        local i = s.row_of[p:sub(#root + 1)]
        local r = i and s.rows[i]
        local has = r and r.e and ((side == 'a' and r.e.ka) or (side == 'b' and r.e.kb))
        if has and i - 1 >= top and i - 1 <= bot then
          local _, meta = side_text(s, layout(s), r, side)
          local off = side == 'b' and (s.offb[i] or 0) or 0
          local line = api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ''
          local room = meta.name_end - meta.name_vis >= 4
          local col = off + (room and meta.name_vis or meta.name_end)
          local dcol = vim.fn.strdisplaywidth(line:sub(1, col)) - (room and 0 or 4)
          api.nvim_buf_set_extmark(buf, ns_pick, i - 1, 0, {
            virt_text = { { ' [A]', 'VimIdeDirDiffPickA' } }, virt_text_pos = 'overlay',
            virt_text_win_col = math.max(0, dcol), hl_mode = 'combine', ephemeral = true,
          })
          return
        end
      end
    end
  end
end

api.nvim_set_decoration_provider(ns_pick, {
  on_win = function(_, _, buf, top, bot)
    if vim.bo[buf].filetype ~= 'vimidedirdiff' then
      return false
    end
    local first = _G.vimide_dirdiff_picked and _G.vimide_dirdiff_picked()
    local s = first and session_of_buf(buf)
    if s then
      pcall(pick_mark, s, buf, top, bot, first)
    end
    return false
  end,
})

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
  -- 견줄 경로도 푼다: macOS 에서 트리의 이름(A 쪽 철자 - dirdiffscan.py 의 alias)과 버퍼 이름을
  -- 푼 것(디스크의 철자 - 대소문자·NFD)이 달라, 고친 채 저장하지 않은 B 의 foo.c 를 Foo.c 로
  -- 복사할 때 알아보지 못했다
  path = real(path)
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
  -- 뒤쪽이 죽은 뒤에 보내면 아무도 받지 않아 '복사하는 중' 이 풀리지 않는다
  if not (s.job and s.job > 0) then
    return say('비교가 멈췄습니다 - R 로 다시 훑은 뒤 복사하세요', vim.log.levels.WARN)
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

-- 디스크에서 바뀐 경로 하나(저장한 파일, 복사한 곳)가 비교 o 의 어디인가: 뿌리에서의 경로들 (A·B
-- 양쪽에 들 수 있다), 그리고 그 경로가 o 의 뿌리이거나 그 위인지 (뿌리째 바뀌었다).
-- 버퍼 이름 그대로가 먼저다: 트리가 연 파일은 트리의 이름으로 열려 있다. 링크를 푼 이름(rp - macOS
-- 는 디스크의 철자, NFD·대소문자)으로 찾으면 트리에 없는 이름이 새 줄로 생긴다. 푼 이름은 그 경로가
-- 뿌리 밖일 때(/tmp 와 /private/tmp 등)와, 파일 링크를 저장해 가리키는 파일이 바뀌었을 때만
local function rels_in(o, full, rp, link)
  local paths, whole = {}, false
  for _, root in ipairs({ o.a, o.b }) do
    local pre = root .. '/'
    local mine = full:sub(1, #pre) == pre
    if mine then
      paths[#paths + 1] = full:sub(#pre + 1)
    end
    if (link or not mine) and rp ~= full and rp:sub(1, #pre) == pre then
      paths[#paths + 1] = rp:sub(#pre + 1)
    end
    for _, p in ipairs({ full, rp }) do
      if pre:sub(1, #p + 1) == p .. '/' then
        whole = true
      end
    end
  end
  return paths, whole
end

-- 다시 볼 곳(rels: 뿌리에서의 경로)의 목록을 버린다 - 그 아래 펼쳐 둔 디렉터리는 부모의 새 목록이
-- 온 뒤에 다시 청한다 (on_event 의 'list'). 보고 있던 짝이 그 안이면 부모의 새 목록이 온 뒤에 다시 연다
local function forget(s, rels)
  for _, rr in ipairs(rels) do
    for k in pairs(s.dirs) do
      if k == rr or k:sub(1, #rr + 1) == rr .. '/' then
        s.dirs[k] = nil
        s.loading[k] = nil
      end
    end
  end
  if s.opened_rel then
    for _, rr in ipairs(rels) do
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
  s.need_full = true
end

-- 뒤쪽의 'copied': 목록을 새로 받게 하고, 버퍼를 다시 읽고, 알린다
local function on_copied(s, ev)
  local c = s.copying
  s.copying = nil
  local to = c and c.to or 'b'
  local from = c and c.from or 'a'
  local roots = ev.roots or {}
  forget(s, roots)
  -- 대상 쪽 버퍼를 새로 읽는다 (비교가 연 것은 BufRead 훅 없이)
  local base = s[to]
  local tops = {}
  for i, rr in ipairs(roots) do
    tops[i] = real(base .. '/' .. rr)   -- 버퍼 이름처럼 푼다 (modified_under 와 같은 까닭)
  end
  for _, b in ipairs(api.nvim_list_bufs()) do
    local n = api.nvim_buf_get_name(b)
    if n ~= '' and api.nvim_buf_is_loaded(b) and not vim.bo[b].modified then
      local rn = real(n)
      for _, p in ipairs(tops) do
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
  if c and c.by_mark then
    s.marks[from] = {}
  end
  schedule_render(s)
  -- 같은 곳이 든 다른 비교에도 알린다 (:w 의 BufWritePost 처럼) - Tab/Tab 으로 연 안쪽 비교에서
  -- 복사했더니 바깥 비교 탭은 R 을 누를 때까지 옛 판정(=)·크기·수를 그대로 보였다. 복사한 디렉터리가
  -- 그 비교의 뿌리를 품으면(뿌리째 바뀌었다) 다시 훑는다 (R. 그쪽도 복사하는 중이면 그 복사가 끝난 뒤에)
  for _, o in pairs(sessions) do
    if o ~= s and not o.done then
      local rels, whole = {}, false
      for _, rr in ipairs(roots) do
        local full = base .. '/' .. rr
        local r, w = rels_in(o, full, real(full), false)
        vim.list_extend(rels, r)
        whole = whole or w
      end
      if whole then
        if o.copying then
          o.rescan = true
        else
          restart_fn(o)
        end
      elseif #rels > 0 then
        forget(o, rels)
        schedule_render(o)
        send(o, { cmd = 'refresh', paths = rels })
      end
    end
  end
  if s.rescan then
    -- 이 뒤쪽이 이어 보내는 것(부모의 'list')을 다 받은 뒤에 바꾼다
    s.rescan = nil
    vim.schedule(function()
      if not s.done then
        restart_fn(s)
      end
    end)
  end
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

-- 편집 창(비교 중인 두 창)에서 <C-r>/<C-l>: 커서가 있는 차이 덩어리째 오른쪽/왼쪽으로 (범위
-- 없는 :diffput / :diffget 처럼). 횟수가 있으면 커서 줄부터 그만큼(1<C-r> = 커서 줄만), 비주얼이면
-- 고른 줄만, <C-S-r>/<C-S-l> 도 커서 줄만. 커서 줄 하나(<C-S-r>, 1<C-r>)는 바뀐 줄이 아니면 바로
-- 위·아래에 끼인 줄(다른 쪽에만 있는 줄)이 있을 때만 그 덩어리째 (여러 줄일 수 있다)
--
-- 'diff' 가 꺼진 편집 창도, 안내 버퍼(바이너리·큰 파일의 알림 - diffthis 를 하지 않는다)를 띄우고
-- 있으면 받는다: 넘겼더니 <C-r> 은 되돌리기 취소(E21), <C-l> 은 창 옮기기가 되어 트리 복사를 알리지
-- 못했다. 처음의 빈 창(아직 연 짝이 없다)과 사용자가 :e 로 띄운 파일은 넘긴다
local function applies()
  local s = sessions[api.nvim_get_current_tabpage()]
  local w = api.nvim_get_current_win()
  if not (s and (w == s.win_a or w == s.win_b)) then
    return nil
  end
  if vim.wo[w].diff or (s.opened_rel and vim.bo[api.nvim_win_get_buf(w)].buftype ~= '') then
    return s
  end
end

-- 0 바이트 파일(빈 버퍼): 줄은 하나('')로 보이지만 diff 에는 줄이 없다 (그 자리 줄 위에 저쪽 줄
-- 수만큼 끼인 줄이 붙는다). line2byte(1) 은 버퍼를 만든 길에 따라 -1 이 아니어서 바이트 수로 본다
local function empty_buf(b)
  return api.nvim_buf_line_count(b) == 1 and api.nvim_buf_get_lines(b, 0, 1, false)[1] == ''
    and api.nvim_buf_call(b, function()
      return vim.fn.wordcount().bytes
    end) == 0
end

-- 0 바이트 파일(빈 버퍼)로: 이쪽에 줄이 없으니 저쪽 줄 모두가 한 덩어리다 - diffopt 와 상관없이 직접
-- 넣는다 (한 번에 바꾸니 u 한 번에 빈 파일로). iblank·filler 없음에서는 행을 셀 수 없어 범위로(:diffput)
-- 맡겼더니 nvim 의 그 탈(copy_rows 에 적은 둘째)이 돌아와 u 뒤에 줄 하나가 남았다. 덩어리째와 가져오기
-- (커서가 빈 쪽)는 원본 전체, 보내기의 횟수·비주얼·커서 줄은 그 줄들 (copy_into_blank 와 같다).
-- iblank 인데 원본이 빈 줄뿐이면 차이가 없다.
-- 돌려주는 것: 바꿨으면 true, 차이가 없으면 false, 대상이 빈 버퍼가 아니면(또는 원본도 비었으면) nil
local function copy_into_empty(put, whole, l1, l2, tb, sb)
  if not empty_buf(tb) or empty_buf(sb) then
    return nil
  end
  local src = api.nvim_buf_get_lines(sb, 0, -1, false)
  if (',' .. vim.o.diffopt .. ','):find(',iblank,', 1, true) then
    local any = false
    for _, x in ipairs(src) do
      if x:find('%S') then
        any = true
        break
      end
    end
    if not any then
      return false
    end
  end
  if put and not whole then
    src = vim.list_slice(src, l1, l2)
  end
  api.nvim_buf_set_lines(tb, 0, -1, false, src)
  return true
end

-- (copy_rows 가 셀 수 없을 때) 지금 창에서 줄 l 이 든 차이 덩어리를 :r1,r2diffput 의 범위로: 바뀐
-- 줄이 이어진 데와 그 사이·위·아래에 끼인 줄(이 창에는 줄 번호가 없다). l 이 바뀐 줄이 아니면 바로
-- 위, 그다음 바로 아래에 끼인 줄의 덩어리. 끼인 줄은 그 아래 줄 앞에 붙어 있어서(diff_filler) 위에
-- 끼인 줄은 한 줄 위부터, 아래에 끼인 줄은 한 줄 아래까지 잡는다 (그 줄이 다음 조각의 첫 줄이면
-- 그 조각도 따라온다 - copy_rows 를 먼저 쓰는 까닭)
local function hunk_range(l)
  local n = vim.fn.line('$')
  local function changed(x)
    return x >= 1 and x <= n and vim.fn.diff_hlID(x, 1) ~= 0
  end
  local h1, h2
  if changed(l) then
    h1, h2 = l, l
  elseif vim.fn.diff_filler(l) > 0 then
    h1, h2 = l, l - 1
  elseif vim.fn.diff_filler(l + 1) > 0 then -- l 이 마지막 줄이면 파일 끝 아래에 끼인 줄
    h1, h2 = l + 1, l
  else
    return nil
  end
  while changed(h1 - 1) do
    h1 = h1 - 1
  end
  while changed(h2 + 1) do
    h2 = h2 + 1
  end
  -- 끼인 줄만인 덩어리는 위·아래가 같은 끼인 줄이라 범위가 h2,h1 이 된다
  local r1 = vim.fn.diff_filler(h1) > 0 and h1 - 1 or h1
  local r2 = vim.fn.diff_filler(h2 + 1) > 0 and h2 + 1 or h2
  return { r1, r2, n }
end

-- 창의 행: 끼인 줄은 false, 진짜 줄은 줄 번호 (빈 버퍼의 자리 줄은 행이 아니다). diff_filler 는
-- 줄마다 조각 목록을 처음부터 찾아서 줄 수 x 조각 수만큼 걸린다 - deadline 을 넘기면 nil
local function rows_of(win, deadline)
  local rows = {}
  local done = api.nvim_win_call(win, function()
    local n = empty_buf(0) and 0 or vim.fn.line('$')
    for l = 1, n + 1 do
      if l % 512 == 0 and uv.hrtime() > deadline then
        return false
      end
      for _ = 1, vim.fn.diff_filler(l) do
        rows[#rows + 1] = false
      end
      if l <= n then
        rows[#rows + 1] = l
      end
    end
    return true
  end)
  return done and rows or nil
end

-- 덩어리째 복사: 두 창의 행(끼인 줄 포함)을 처음부터 세어 맞추고 대상의 그 줄들을 직접 바꾼다.
-- :diffput/:diffget 에 범위를 주어 맡기지 않는 까닭 (무작위 비교로 찾았다):
--  - linematch(nvim 기본 diffopt)는 한 덩어리를 조각으로 나누고 같은 줄을 맞춰 보인다. 범위로는
--    "줄 L 위에 끼인 줄"과 "줄 L 에서 시작하는 조각"을 가를 수 없어서, 덩어리 끝의 끼인 줄을 잡으려고
--    한 줄 넓히면 옆 조각(같은 줄로 보이는 줄 뒤에 저쪽 줄이 더 붙은 것)까지 옮겨 저쪽 줄이 지워졌다.
--    범위 없이 치면 커서가 있는 조각만 옮긴다
--  - 대상이 빈 줄 하나뿐인 때(처음부터, 또는 조각을 옮기는 사이)를 만나면 그것을 빈 버퍼의 자리
--    줄로 알고 넣은 줄 다음 줄을 지운다 (vim 도 같다). 0 바이트 파일에 넣은 것은 u 한 번에 줄
--    하나가 남았다
-- linematch 는 화면에 보이는 줄을 물을 때에야 조각낸다 - 이 창, 저 창, 다시 이 창 순으로 세어
-- 조각이 굳은 뒤의 행을 쓴다. 너무 크면(250ms) nil - 범위로 옮긴다 (copy_hunk).
-- 돌려주는 것: 바꿨으면 true, 덩어리가 없으면 false, 셀 수 없으면 nil.
-- 행으로 셀 수 없는 diffopt: iblank 는 빈 줄만인 덩어리를 끼인 줄 없이 지우고(두 창의 행이 어긋난다),
-- filler 가 없으면 끼인 줄이 아예 없다. 어긋난 것이 양쪽에서 비기면 행 수가 같아 아래 #rw ~= #ro 로도
-- 못 걸렀고, 바뀌지 않은 줄을 덮어썼다 (A '\nx\ny\nw\n', B 'x\nz\nw\n\n' 의 y 에서 <C-r>: B 의 w 가
-- y 로, z 는 그대로). 그때는 범위로 옮긴다 (copy_hunk - nvim 이 맞춘다). 0 바이트 파일로 넣는 것은
-- 그 앞에서 copy_into_empty 가 한다 (범위로 맡기면 위의 둘째 탈이 돌아온다)
local function copy_rows(w, other, put)
  local dopt = ',' .. vim.o.diffopt .. ','
  if dopt:find(',iblank,', 1, true) or not dopt:find(',filler,', 1, true) then
    return nil
  end
  local deadline = uv.hrtime() + 250e6
  local rw = rows_of(w, deadline)
  local ro = rw and rows_of(other, deadline)
  rw = ro and rows_of(w, deadline)
  if not rw or #rw ~= #ro then
    return nil
  end
  local function changed(i)
    return rw[i] == false or ro[i] == false or vim.fn.diff_hlID(rw[i], 1) ~= 0
  end
  local c, cur = #rw + 1, vim.fn.line('.') -- 빈 버퍼의 자리 줄은 모든 행 아래에 있다
  for i, l in ipairs(rw) do
    if l == cur then
      c = i
      break
    end
  end
  -- 커서 줄이 바뀐 줄이 아니면 바로 위(범위 없는 :diffput 처럼 위가 먼저), 바로 아래에 끼인 줄
  local s, e
  if c <= #rw and changed(c) then
    s, e = c, c
  elseif c > 1 and rw[c - 1] == false then
    s, e = c - 1, c - 1
  elseif c < #rw and rw[c + 1] == false then
    s, e = c + 1, c + 1
  else
    return false
  end
  while s > 1 and changed(s - 1) do
    s = s - 1
  end
  while e < #rw and changed(e + 1) do
    e = e + 1
  end
  local src, dst = put and rw or ro, put and ro or rw
  local first, cnt, a, b = 0, 0, nil, nil
  for i = 1, e do
    if dst[i] then
      if i < s then
        first = first + 1
      else
        cnt = cnt + 1
      end
    end
    if i >= s and src[i] then
      a, b = a or src[i], src[i]
    end
  end
  local sb, tb = api.nvim_win_get_buf(put and w or other), api.nvim_win_get_buf(put and other or w)
  local lines = a and api.nvim_buf_get_lines(sb, a - 1, b, false) or {}
  if empty_buf(tb) then
    api.nvim_buf_set_lines(tb, 0, -1, false, lines)   -- 자리 줄은 남기지 않는다
  else
    api.nvim_buf_set_lines(tb, first, first + cnt, false, lines)
  end
  return true
end

-- 덩어리째 복사를 범위로 (copy_rows 가 셀 수 없을 때 - 큰 파일): :r1,r2diffput (put: 이 창 -> 저 창).
-- 파일 맨 위·맨 아래에 끼인 줄은 범위로 잡을 수 없다 (0 줄은 1 로 바뀌고 $+1 은 E16) - 그때는 저
-- 창에서 거꾸로(put <-> get) 한다. 이 창의 그 끝이 끼인 줄이면 저 창의 그 끝은 진짜 줄이라서 저 창의
-- 맨 위(맨 아래) 줄이 같은 덩어리에 든다. 저 창도 반대쪽 끝이 걸리면 덩어리가 파일 전체다
local function copy_hunk(w, other, put, h)
  local mine, theirs = api.nvim_win_get_buf(w), api.nvim_win_get_buf(other)
  if h[1] >= 1 and h[2] <= h[3] then
    vim.cmd(('%d,%d%s %d'):format(h[1], h[2], put and 'diffput' or 'diffget', theirs))
    return true
  end
  local o = api.nvim_win_call(other, function()
    return hunk_range(h[1] < 1 and 1 or vim.fn.line('$')) or false
  end)
  if not o then
    -- 끼인 줄이 맞지 않는 diffopt(iblank 등): nvim 이 고르는 대로
    vim.cmd((put and 'diffput' or 'diffget') .. ' ' .. theirs)
  elseif o[1] >= 1 and o[2] <= o[3] then
    api.nvim_win_call(other, function()
      vim.cmd(('%d,%d%s %d'):format(o[1], o[2], put and 'diffget' or 'diffput', mine))
    end)
  else
    local from, to = put and mine or theirs, put and theirs or mine
    api.nvim_buf_set_lines(to, 0, -1, false, api.nvim_buf_get_lines(from, 0, -1, false))
  end
  return true
end

-- 줄 단위 복사에서 대상이 빈 줄 하나뿐("\n")이거나 빈 버퍼일 때 (copy_rows 에 적은 둘째 탈): 대상에
-- 줄이 없거나 하나뿐이라 줄 맞춤이 쉽다 - 행으로 세어 직접 바꾼다. 행: 대상은 위에 끼인 줄 fa 개,
-- 그 줄(k 행, 빈 버퍼면 자리 줄이라 행이 아니다), 아래에 끼인 줄. 원본에는 k 행에만 끼인 줄이 있을
-- 수 있다 (대상의 빈 줄이 원본에 없는 줄일 때). 원본이 빈 버퍼면 넣을 줄이 없어 nvim 에 맡긴다.
-- whole: 덩어리째 (copy_rows 가 셀 수 없는 diffopt - iblank, filler 없음 - 에서 빈 줄 하나뿐인 대상. 범위로
-- 맡겼더니 nvim 의 :diffput 이 줄 하나를 잃었다). 그 줄이 바뀐 줄이면 저쪽 모두가 한 덩어리라 끼인 줄을
-- 세지 않는다. 아니면 위(먼저)·아래에 끼인 줄 덩어리 - 보내기는 커서 줄이 든 쪽
-- 돌려주는 것: 바꿨으면 true, 그 자리에 차이가 없으면 false, 행이 맞지 않으면 nil
local function copy_into_blank(put, visual, l1, l2, tw, sw, whole)
  local tb, sb = api.nvim_win_get_buf(tw), api.nvim_win_get_buf(sw)
  if empty_buf(sb) then
    return nil
  end
  local t = api.nvim_win_call(tw, function()
    return { vim.fn.diff_filler(1), vim.fn.diff_filler(2), vim.fn.diff_hlID(1, 1) ~= 0 }
  end)
  local none = empty_buf(tb)
  local fa, tch = t[1], t[3]
  local k, total = fa + 1, fa + (none and 0 or 1) + t[2]
  local src = api.nvim_buf_get_lines(sb, 0, -1, false)
  if whole and tch and not none then
    api.nvim_buf_set_lines(tb, 0, -1, false, src)
    return true
  end
  local sk = total - #src
  if sk < 0 or sk > 1 or (sk == 1 and not tch) or (none and (tch or t[2] > 0)) then
    return nil
  end
  local function srow(i)
    return i < k and i or i + sk
  end
  local x1, x2
  if whole then
    local r = put and srow(l1) or k
    if r < k or (not put and fa > 0) then
      x1, x2 = 1, fa
    elseif r > k or (not put and total > k) then
      x1, x2 = k + 1, total
    end
  elseif not put then                   -- 커서가 대상의 그 줄에
    if tch then
      x1, x2 = k, k
    elseif fa > 0 then
      x1, x2 = 1, fa
    elseif total > k then
      x1, x2 = k + 1, total
    end
  elseif visual or tch or srow(l1) ~= k then
    x1, x2 = srow(l1), srow(l2)
  end
  if not x1 then
    return false
  end
  local up, mid, down = {}, none and {} or { '' }, {}
  for r = x1, x2 do
    if r < k then
      up[#up + 1] = src[r]
    elseif r > k then
      down[#down + 1] = src[r - sk]
    else
      mid = sk == 0 and { src[k] } or {}
    end
  end
  api.nvim_buf_set_lines(tb, 0, -1, false, vim.list_extend(vim.list_extend(up, mid), down))
  return true
end

-- one: <C-S-r>/<C-S-l> - 횟수가 없어도 커서 줄만
function _G.vimide_dirdiff_copy_lines(dir, one)
  local s = applies()
  if not s then
    return
  end
  local w = api.nvim_get_current_win()
  local mode = api.nvim_get_mode().mode
  local visual = mode:match('^[vV\22]') ~= nil
  local whole = not visual and not one and vim.v.count == 0
  local count = vim.v.count1
  -- 횟수는 마지막 줄에서 멈춘다 (15dd 처럼). 그대로 두었더니 30,44diffput 이 E16 으로 실패해
  -- 있는 줄까지 하나도 복사되지 않았다
  local l1, l2 = vim.fn.line('.'), math.min(vim.fn.line('.') + count - 1, vim.fn.line('$'))
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
      if s.bin then
        return say('바이너리·큰 파일은 줄로 복사할 수 없습니다 - 파일째는 트리에서 <C-r>/<C-l> 로 복사하세요',
          vim.log.levels.WARN)
      end
      local side = (b == s.empty_a or api.nvim_win_get_buf(s.win_a) == b) and 'A' or 'B'
      return say(side .. ' 쪽은 파일이 아닙니다 - 파일째는 트리에서 <C-r>/<C-l> 로 복사하세요',
        vim.log.levels.WARN)
    end
  end
  -- 덩어리째는 대상 버퍼를 직접 바꾸므로(copy_rows) 미리 본다 - 그대로 두면 API 오류가 파일·줄
  -- 번호를 단 채 나왔다 (:diffput 은 E21)
  if not vim.bo[tb].modifiable then
    return say(((tb == api.nvim_win_get_buf(s.win_a)) and 'A' or 'B')
      .. " 쪽 버퍼는 고칠 수 없습니다 ('modifiable' 꺼짐)", vim.log.levels.WARN)
  end
  -- 저쪽 버퍼를 이름으로 준다: 이 탭에 diff 창이 셋 이상이면 이름 없는 :diffput 은 E101 이었다
  local cmd = (put and 'diffput' or 'diffget') .. ' ' .. theirs
  local range
  if whole then
    range = nil
  elseif visual or l2 > l1 or vim.fn.diff_hlID(l1, 1) ~= 0 then
    -- 여러 줄(비주얼, N<C-r>)은 그 줄들 - 커서 줄만 보았더니 N<C-r> 이 커서 줄이 바뀌지 않았으면
    -- 범위를 버리고 '차이가 없다' 고 하거나 커서 옆에 끼인 줄 덩어리(범위 밖일 수도)를 옮겼다.
    -- 마지막 줄에서 잘려 한 줄이 된 횟수는 아래의 커서 줄 규칙대로 (2<C-l> 이 그 아래 줄을 가져온다)
    range = ('%d,%d'):format(l1, l2)
  elseif vim.fn.diff_filler(l1) > 0 then
    range = ''                           -- 바로 위에 끼인 줄: 그 덩어리
  elseif vim.fn.diff_filler(l1 + 1) > 0 then
    -- 바로 아래에 끼인 줄. 마지막 줄 아래는 범위로 못 잡는다(E16) - 범위 없는 :diffput 이
    -- 마지막 줄에서는 그 아래를 잡는다
    range = l1 < vim.fn.line('$') and ('%d,%d'):format(l1, l1 + 1) or ''
  elseif not put and empty_buf(tb) then
    range = ''   -- 빈 버퍼(0 바이트)의 자리 줄로 가져오기: filler 가 없어 끼인 줄이 안 보여도 저쪽 전체
  else
    return say('이 줄에는 차이가 없습니다')
  end
  local tick = vim.b[tb].changedtick
  local ok, res = pcall(function()
    local into = copy_into_empty(put, whole, l1, l2, tb, put and mine or theirs)
    if into ~= nil then
      return into
    end
    if whole then
      local done = copy_rows(w, other, put)
      if done == nil and api.nvim_buf_line_count(tb) == 1 and api.nvim_buf_get_lines(tb, 0, 1, false)[1] == '' then
        done = copy_into_blank(put, false, l1, l1, put and other or w, put and w or other, true)
      end
      if done ~= nil then
        return done
      end
      local h = hunk_range(l1)
      if not h then
        return false
      end
      return copy_hunk(w, other, put, h)
    end
    if api.nvim_buf_line_count(tb) == 1 and api.nvim_buf_get_lines(tb, 0, 1, false)[1] == '' then
      local done = copy_into_blank(put, visual or l2 > l1, l1, l2, put and other or w, put and w or other)
      if done ~= nil then
        return done
      end
    end
    vim.cmd(range .. cmd)
    return true
  end)
  if not ok then
    say(tostring(res):gsub('^.-(E%d+:)', '%1'), vim.log.levels.WARN)
  elseif not res or (not whole and vim.b[tb].changedtick == tick) then
    -- 범위로 옮겼는데 바뀐 것이 없으면 그 줄들에 차이가 없는 것이다 - 비주얼·횟수는 아무 말이
    -- 없었다 (범위 첫 줄 바로 위에 끼인 줄은 범위에 들지 않는다 - nvim 의 :1,1diffget 도 같다)
    local msg = '이 줄에는 차이가 없습니다'
    if whole then
      msg = '커서가 차이 덩어리에 있지 않습니다 (다음·앞 차이는 <C-n>/<C-p>)'
    elseif visual then
      msg = '고른 줄에는 차이가 없습니다'
    elseif l2 > l1 then
      msg = ('커서 줄부터 %d 줄에는 차이가 없습니다'):format(l2 - l1 + 1)
    end
    return say(msg)
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
-- feedkeys 로 넘겼더니 빠르게 친 뒤의 키가 먼저 돌았다.
-- 키 -> { 방향, 커서 줄만 }. <C-S-r>/<C-S-l> 은 터미널이 Ctrl+Shift 를 따로 알려 줄 때만 온다
-- (iTerm2 의 CSI u, tmux 의 extended-keys) - Tera Term 등에서는 그냥 <C-r>/<C-l> 이 오므로
-- 1<C-r>/1<C-l> 이 같은 일을 한다. 비교 창 밖의 <C-S-r>/<C-S-l> 도 그 키 그대로 넘긴다
-- (매핑이 없을 때 nvim 은 <C-S-r> 을 <C-r> 처럼 되돌리기 취소로 친다)
local TAKE = {
  ['<C-r>'] = { 1 }, ['<C-l>'] = { -1 },
  ['<C-S-r>'] = { 1, true }, ['<C-S-l>'] = { -1, true },
}
local prev_maps = {}

function _G.vimide_dirdiff_prev_key(id)
  local p = prev_maps[id]
  if p and p.callback then
    return p.callback()
  end
end

local function take_over()
  for lhs, t in pairs(TAKE) do
    local dir, one = t[1], t[2] == true
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
          return ('<Cmd>lua _G.vimide_dirdiff_copy_lines(%d, %s)<CR>'):format(dir, tostring(one))
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
        desc = 'DirDiff 비교 창: ' .. (one and '커서 줄을 ' or '차이 덩어리를 ')
          .. (dir > 0 and '오른쪽(B)' or '왼쪽(A)') .. '으로' })
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

-- ---------------------------------------------------------------------------
-- 보기 (f: 메뉴, F: 모두 <-> 차이) - Beyond Compare 의 보기 거르기
-- ---------------------------------------------------------------------------

local function set_mode(s, id)
  if not MODE[id] or s.mode == id then
    return
  end
  s.mode = id
  render(s)
end

-- 처음 보기: g:vimide_dirdiff_filter (MODES 의 id), 없으면 g:vimide_dirdiff_only_diff.
-- g:vimide_dirdiff_view 에 싣지 않은 것은 그 이름이 이미 ':DirDiff 를 이 트리로' (0/1) 라서다 -
-- dirdifftab.vim 의 get(g:, 'vimide_dirdiff_view', 1) 은 'diff' 같은 글자를 0 으로 읽어
-- :DirDiff 가 예전 목록이 된다
local function start_mode()
  local v = vim.g.vimide_dirdiff_filter
  if type(v) == 'string' and v ~= '' then
    if MODE[v] then
      return v
    end
    local ids = {}
    for _, md in ipairs(MODES) do
      ids[#ids + 1] = md.id
    end
    say(('g:vimide_dirdiff_filter 를 모릅니다: %s (%s)'):format(v, table.concat(ids, ' ')), vim.log.levels.WARN)
  end
  return (tonumber(vim.g.vimide_dirdiff_only_diff) or 0) ~= 0 and 'diff' or 'all'
end

-- 보기마다 항목 수: 뒤쪽의 cats (표시 -> 수). 한쪽에만 있는 디렉터리는 하나로 센다 (상태줄처럼).
-- 견주는 중인 것은 '모두' 에만 든다
local function mode_count(s, md)
  local cats = s.prog and s.prog.cats
  if type(cats) ~= 'table' then
    return nil
  end
  local n = 0
  for k, v in pairs(cats) do
    local m = tonumber(k)
    if m and type(v) == 'number' and (not md.bits or band(m, md.bits) ~= 0) then
      n = n + v
    end
  end
  return n
end

menu_fill = function(s)
  local mu = s.menu
  if not (mu and api.nvim_buf_is_valid(mu.buf) and api.nvim_win_is_valid(mu.win)) then
    s.menu = nil
    return
  end
  local cnt, lw, cw = {}, 0, 0
  for i, md in ipairs(MODES) do
    local c = mode_count(s, md)
    cnt[i] = c and commas(c) or ''
    lw = math.max(lw, vim.fn.strdisplaywidth(md.label))
    cw = math.max(cw, #cnt[i])
  end
  local dot = ascii() and '*' or '●'
  local lines, width = {}, 0
  for i, md in ipairs(MODES) do
    lines[i] = (' %s %s  %s '):format(md.id == s.mode and dot or ' ', fit(md.label, lw), rjust(cnt[i], cw))
    width = math.max(width, vim.fn.strdisplaywidth(lines[i]))
  end
  vim.bo[mu.buf].modifiable = true
  api.nvim_buf_set_lines(mu.buf, 0, -1, false, lines)
  vim.bo[mu.buf].modifiable = false
  api.nvim_buf_clear_namespace(mu.buf, ns, 0, -1)
  for i, md in ipairs(MODES) do
    local l = lines[i]
    local c1 = #l - 1
    if cnt[i] ~= '' then
      pcall(api.nvim_buf_set_extmark, mu.buf, ns, i - 1, c1 - #cnt[i],
        { end_col = c1, hl_group = cnt[i] == '0' and 'Comment' or 'VimIdeDirDiffSize' })
    end
    if md.id == s.mode then
      pcall(api.nvim_buf_set_extmark, mu.buf, ns, i - 1, 1, { end_col = c1 - #cnt[i], hl_group = 'VimIdeDirDiffMenuNow' })
    end
  end
  local pend = s.prog and tonumber(s.prog.pend) or 0
  local title = pend > 0 and (' 보기 · 확인 중 %s '):format(commas(pend)) or ' 보기 '
  width = math.max(width, vim.fn.strdisplaywidth(title) + 2, vim.fn.strdisplaywidth(mu.footer) + 2)
  pcall(api.nvim_win_set_config, mu.win, { title = title, title_pos = 'center', width = width })
end

local function open_menu(s)
  if s.menu and api.nvim_win_is_valid(s.menu.win) then
    return api.nvim_set_current_win(s.menu.win)
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  -- 이름·filetype 이 없으면 단축키 도움말(F1)이 이 창을 '이 창 · ' 으로만 불렀다
  vim.bo[buf].filetype = 'vimidedirdiffmenu'
  pcall(api.nvim_buf_set_name, buf, 'DirDiff 보기 #' .. buf)
  local footer = ' Enter 고르기 · q 닫기 '
  local h = #MODES
  local border = ascii() and { '+', '-', '+', '|', '+', '-', '+', '|' } or 'rounded'
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor', row = 0, col = 0, width = 30, height = h, style = 'minimal', border = border,
    title = ' 보기 ', title_pos = 'center', footer = footer, footer_pos = 'center', zindex = 60,
  })
  vim.wo[win].cursorline = true
  s.menu = { buf = buf, win = win, footer = footer }
  menu_fill(s)
  -- 트리 창 위, 가운데. 트리가 낮아도 화면 안에 들게
  local tp = api.nvim_win_get_position(s.win_l)
  local tw = api.nvim_win_get_width(s.win_l)
  local width = api.nvim_win_get_width(win)
  local row = math.max(0, math.min(tp[1] + 1, vim.o.lines - vim.o.cmdheight - h - 3))
  local col = tp[2] + math.max(0, math.floor((tw - width - 2) / 2))
  pcall(api.nvim_win_set_config, win, { relative = 'editor', row = row, col = col })
  pcall(api.nvim_win_set_cursor, win, { MODE[s.mode].i, 1 })
  local function close(back)
    if not (s.menu and s.menu.buf == buf) then
      return
    end
    s.menu = nil
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
    if back and api.nvim_win_is_valid(s.win_l) then
      pcall(api.nvim_set_current_win, s.win_l)
    end
  end
  local function choose()
    local md = MODES[api.nvim_win_get_cursor(win)[1]]
    close(true)
    if md then
      set_mode(s, md.id)
    end
  end
  -- desc 가 없으면 단축키 도움말(F1)에 '(Lua 함수)' 로만 보였다
  local function o(desc)
    return { buffer = buf, nowait = true, silent = true, desc = desc }
  end
  for _, k in ipairs({ '<CR>', '<2-LeftMouse>', '<Space>' }) do
    vim.keymap.set('n', k, choose, o('이 보기로 (보기 메뉴)'))
  end
  for _, k in ipairs({ 'q', '<Esc>', 'f' }) do
    vim.keymap.set('n', k, function()
      close(true)
    end, o('보기 메뉴 닫기'))
  end
  -- F1(단축키 도움말)은 메뉴를 닫고 트리에서 연다: 메뉴에서 그대로 열었더니 목록이 뜨며 메뉴가 닫혀
  -- (아래 WinLeave) 도움말을 닫은 뒤 커서가 돌아갈 창이 없어 트리가 아니라 편집 창 A 로 갔다.
  -- VimIdeKeyHelp(.vimrc 의 F1)가 없으면 걸지 않는다 - 전역 F1 그대로
  if vim.fn.exists('*VimIdeKeyHelp') == 1 then
    vim.keymap.set('n', '<F1>', function()
      close(true)
      vim.fn.VimIdeKeyHelp()
    end, o('단축키 도움말 (보기 메뉴를 닫고 트리에서)'))
  end
  -- 다른 창을 누르는 등으로 떠나면 닫는다 (메뉴 밖으로 간 것이니 트리로 끌고 오지 않는다)
  api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        close(false)
      end)
    end,
  })
end

local function help()
  vim.notify(table.concat({
    'DirDiff 트리',
    '  <CR>        파일: 비교를 열고 편집 창으로 / 디렉터리: 펼치기·접기',
    '  o           비교를 열되 트리에 그대로',
    '  <C-n> <C-p> 다음 / 앞 차이 파일 (모두·차이 밖의 보기: 그 보기가 보이는 것 - 동일이면 같은 파일)',
    '  l h         펼치기 / 접기(부모로)',
    '  O X         차이 있는 디렉터리 모두 펼치기 (다른 보기: 그 보기가 보이는 것이 있는 디렉터리) / 모두 접기',
    '  f           보기 고르기 (모두 / 차이 / 고아 없음 / 좌측 최신 / 우측 고아 / 동일 ...)',
    '  F           모두 보이기 <-> 차이 보이기',
    '  R           다시 훑기      q  끝내기',
    '  <Tab>       비교할 곳 고르기: 지금 쪽 항목을 [A] 로, 다음 Tab 의 것을 [B] 로 - 새 탭에서 비교',
    '              ([A] 줄에서 다시 Tab 은 취소. neo-tree 의 Tab 과 같은 [A])',
    '  <S-Tab>     A 쪽 / B 쪽 오가기     <Space> 그쪽 항목 고르기    U 고른 것 모두 풀기',
    '  <C-r> <C-l> 고른 것(또는 비주얼 줄, 커서 줄)을 A→B / B→A 로 복사 (묻고 나서)',
    '편집 창: <C-n> <C-p> = ]c [c (다음 / 앞 차이)',
    '         <C-r> <C-l> 커서가 있는 차이 덩어리째 오른쪽(B) / 왼쪽(A) 으로 (저장은 :w)',
    '         <C-S-r> <C-S-l> 커서 줄만 (Ctrl+Shift 가 안 오는 터미널에서는 1<C-r> 1<C-l>)',
    '                   - 바뀌지 않은 줄이면 바로 위(먼저)·아래에 끼인 저쪽 줄 덩어리째',
    '         N<C-r> N<C-l> 커서 줄부터 N 줄, 비주얼은 고른 줄만',
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
  -- :tabclose·:qa 는 q 와 달리 기다리지 않는다 - 뒤쪽이 쓰던 임시 파일을 지우고 멈춘다
  if s.copying and vim.v.exiting == vim.NIL then
    local c = s.copying
    say(('%s → %s 복사를 멈췄습니다 - 다 쓴 것만 %s 쪽에 남았습니다'):format(c.from:upper(), c.to:upper(),
      c.to:upper()), vim.log.levels.WARN)
  end
  sessions[s.tab] = nil
  local here = api.nvim_get_current_tabpage()
  if api.nvim_tabpage_is_valid(s.tab) then
    api.nvim_set_current_tabpage(s.tab)
    local was = {}
    for _, w in ipairs({ s.win_a, s.win_b }) do
      was[w] = api.nvim_win_is_valid(w) and vim.wo[w].diff
    end
    pcall(vim.cmd, 'diffoff!')
    -- 남는 버퍼(사용자 것, 고친 것)에 창 머리와 diff 접기가 적혀 남지 않게 (open_pair 의 winbar 와 같은
    -- 까닭, undiff_folds)
    for _, w in ipairs({ s.win_a, s.win_b }) do
      if api.nvim_win_is_valid(w) then
        pcall(function()
          vim.wo[w].winbar = ''
        end)
        if was[w] then
          pcall(api.nvim_win_call, w, undiff_folds)
        end
      end
    end
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
      if vim.fn.getbufvar(b, '&modified') == 1 then
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
  -- q 처럼 복사가 끝나기를 기다린다. 뒤쪽을 바꾸면 하던 복사가 중간에 끊기고(대상에 반쯤 쓴
  -- 디렉터리가 남았다), 그 'copied' 는 새 뒤쪽에서 오지 않아 q 와 복사가 끝내 거절되었다
  if s.copying then
    return say('복사하는 중입니다 - 끝난 뒤에 R', vim.log.levels.WARN)
  end
  if s.job and s.job > 0 then
    local old = s.job
    s.job = nil
    pcall(vim.fn.chansend, old, vim.json.encode({ cmd = 'quit' }) .. '\n')
    pcall(vim.fn.jobstop, old)
  end
  local r = cur_row(s)
  s.want_rel = r and r.e and r.rel or nil   -- 커서가 있던 줄로 돌아간다 (그 줄이 다시 생기면)
  s.dirs, s.loading, s.dirty, s.prog, s.walk = {}, {}, {}, nil, nil
  if not start_job(s) then
    return
  end
  -- 맨 위만 청한다. 펼쳐 두었던 아래 디렉터리는 부모의 목록이 오면 on_event 가 청한다
  request_list(s, '')
  render(s)
end
restart_fn = restart

local function map_list(s)
  local b = s.buf_l
  local function m(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = b, nowait = true, silent = true, desc = desc })
  end
  m('<CR>', function() act_enter(s, true) end, '비교 열고 편집 창으로 / 펼치기')
  m('<2-LeftMouse>', function() act_enter(s, true) end, '비교 열기')
  m('o', function() act_enter(s, false) end, '비교 열기 (트리에 그대로)')
  m('<C-n>', function() act_step(s, 1) end, '다음 차이 (보기에 따라)')
  m('<C-p>', function() act_step(s, -1) end, '앞 차이 (보기에 따라)')
  m('l', function()
    local r = cur_row(s)
    if r and r.e and is_dir(r.e) then
      toggle(s, r, true)
    end
  end, '펼치기')
  m('h', function() act_h(s) end, '접기 / 부모로')
  m('O', function() act_expand_all(s) end, '차이 있는 디렉터리 모두 펼치기 (보기에 따라)')
  m('X', function() act_collapse_all(s) end, '모두 접기')
  m('f', function() open_menu(s) end, '보기 고르기')
  m('F', function() set_mode(s, s.mode == 'all' and 'diff' or 'all') end, '모두 보이기 / 차이 보이기')
  m('R', function() restart(s) end, '다시 훑기')
  m('<Tab>', function() act_pick(s) end, '비교할 곳 고르기 [A] -> [B]')
  -- 쪽 바꾸기는 Tab 에서 옮겨 왔다 (Tab 은 neo-tree 처럼 비교할 곳 고르기)
  m('<S-Tab>', function() act_side(s) end, 'A 쪽 / B 쪽')
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
    mode = start_mode(), reveal_step = 1,
    origin = api.nvim_get_current_tabpage(),
  }
  -- 곁창에서 :tabnew 하면 그 창 옵션을 물려받고 neo-tree 가 가져간다 - EDIT 창에서
  local back = api.nvim_get_current_win()
  local w = _G.vimide_edit_slot and _G.vimide_edit_slot()
  if w and w ~= 0 and api.nvim_win_is_valid(w) then
    api.nvim_set_current_win(w)
  end
  vim.cmd('tabnew')
  -- 떠난 곳이 비교 탭이면 그 탭의 지금 창은 도로 그 창으로: EDIT 창(편집 창 A)으로 옮긴 채 두었더니, 비교
  -- 탭의 트리에서 :DirDiff 로 연 비교를 q 로 닫거나 gT 로 돌아가면 커서가 트리가 아니라 편집 창 A 에 있었다
  if sessions[s.origin] and back ~= w and api.nvim_win_is_valid(back)
      and api.nvim_win_get_tabpage(back) == s.origin then
    pcall(api.nvim_tabpage_set_win, s.origin, back)
  end
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

-- 트리 커서 줄이 가리키는 경로 (A 쪽, 없으면 B 쪽). 디렉터리면 끝에 '/' -
-- 곁창에서 <C-g>/<C-/> 로 찾을 때의 기준 (searchctx.lua)
function _G.vimide_dirdiff_path_at()
  local s = sessions[api.nvim_get_current_tabpage()]
  if not (s and api.nvim_get_current_win() == s.win_l) then
    return nil
  end
  local r = s.rows[api.nvim_win_get_cursor(s.win_l)[1]]
  if not (r and r.e) then
    return nil
  end
  -- 쪽을 고른 뒤 그 쪽의 종류로 '/' 를 붙인다 (A 는 파일, B 는 디렉터리인 줄에서
  -- A 의 파일에 '/' 를 붙여 찾을 곳이 파일이 되었다)
  local k = r.e.ka or r.e.kb
  local root = r.e.ka and s.a or s.b
  return root .. '/' .. r.rel .. (k == 'd' and '/' or '')
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
-- :tabclose (또는 <C-w>c) 로 편집 창이 닫힐 때도 남는 버퍼(고친 것, 사용자 것)에 머리와 diff 접기가 적혀
-- 남지 않게, 창이 닫히기 바로 앞에 걷는다 (finish 는 탭이 닫힌 뒤에 돌아 창이 이미 없다). 탭의 마지막 창은
-- 여기 오기 전에 nvim 이 diff 를 이미 꺼 두어(nofoldenable, 접기는 남은 채) diff 였는지 묻지 않는다 - 편집
-- 창의 manual 접기는 diff 가 남긴 것뿐이다. q 로 닫을 때는 finish 가 먼저 sessions 에서 뺀 뒤라 그냥 지나간다
api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(ev)
    local w = tonumber(ev.match)
    for _, s in pairs(sessions) do
      if w and (w == s.win_a or w == s.win_b) and api.nvim_win_is_valid(w) then
        pcall(api.nvim_win_call, w, function()
          vim.cmd('diffoff')
          undiff_folds()
          vim.wo.winbar = ''
        end)
      end
    end
  end,
})
-- 편집 창에 떠 있는 파일을 다른 창·탭에 띄우면 nvim 은 그 버퍼가 떠 있는 창(편집 창)의 옵션을 새 창에
-- 입힌다: 비교의 머리(' A: …' winbar)에 diff·scrollbind·cursorbind·foldmethod=diff 까지 따라왔다
-- (:tabnew 파일, :tabnew 뒤 :e, :vsplit 파일, neo-tree 의 Enter, Tab/Tab 의 vimdiff). 버퍼를 바꿀 때 머리를
-- 걷는 것(open_pair, finish)은 내려간 버퍼에만 듣는다. 그래서 들어온 쪽에서 걷는다: 두 편집 창이 아닌 창이
-- 편집 창과 같은 머리를 달고 있으면 거기서 받은 옵션이다 - 머리를 걷고 diff 였으면 :diffoff (그 창만,
-- 묶기·접기도 diff 전으로). :diffoff 가 남긴 manual 접기와 'foldenable' 은 undiff_folds 가 되돌린다.
-- 사용자가 :diffsplit·vimdiff 로 켜는 diff 는 그 명령이 버퍼를 띄운 뒤에 켜므로 남는다.
-- 머리가 다른(사용자가 켠) diff 창은 건드리지 않는다
local function strip_inherited()
  if next(sessions) == nil then
    return
  end
  local w = api.nvim_get_current_win()
  local wb = vim.wo[w].winbar
  if wb == '' then
    return
  end
  local from = false
  for _, s in pairs(sessions) do
    if w == s.win_a or w == s.win_b then
      return
    end
    for _, x in ipairs({ s.win_a, s.win_b }) do
      if api.nvim_win_is_valid(x) and vim.wo[x].winbar == wb then
        from = true
      end
    end
  end
  if from then
    pcall(vim.cmd, 'setlocal winbar<')
    if vim.wo[w].diff then
      pcall(vim.cmd, 'diffoff')
      undiff_folds()
    end
  end
end
api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'WinEnter' }, {
  group = group,
  callback = strip_inherited,
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
-- 비교 중인 두 디렉터리 안의 파일을 :w 로 저장하면 그 항목만 다시 본다 (트리 복사처럼).
-- 없었을 때는 편집 창에서 두 파일을 같게 만들어 저장해도 R 을 누를 때까지 트리가 옛 판정·
-- 크기·날짜(≠)를 그대로 보였다
api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function(ev)
    if next(sessions) == nil then
      return
    end
    local full = vim.fn.fnamemodify(ev.match, ':p')
    local rp = real(full)
    -- 어느 이름으로 찾는지는 rels_in 에 (트리 복사의 on_copied 와 같이 쓴다)
    local link = (uv.fs_lstat(full) or {}).type == 'link'
    for _, s in pairs(sessions) do
      local paths = rels_in(s, full, rp, link)
      if #paths > 0 then
        send(s, { cmd = 'refresh', paths = paths })
      end
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
