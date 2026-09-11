-- sihlindex.lua - 색인이 정의부를 아는 심볼만 초록으로 남기고, 모르는 것은
-- 검정으로 떨어뜨린다.
--
-- 요구: 구조체·enum·함수·매크로를 참조하는 자리는 '색인에서 정의부로 점프가
-- 가능한 경우에만' 초록, 색인이 모르면 검정.
--
-- 왜 이렇게 만들었나 ------------------------------------------------------
--
-- 1) 칠하는 것은 '모르는 것'뿐이다. 아는 것과 아직 안 물어본 것에는 아무것도
--    얹지 않아 오늘 화면 그대로 남는다. 그래서 화면이 검게 번쩍였다가
--    초록으로 돌아오는 일이 없다 - 스크롤 중에는 아무 일도 일어나지 않고,
--    답이 온 자리만 조용히 검정이 된다.
--
-- 2) 묶어서 묻는다. global 은 정규식으로 여러 이름을 한 번에 받는다:
--      global --result=ctags-x -d -e '^(a|b|c)$'
--    예전에 "안 된다"고 적어 둔 적이 있는데 그건 틀렸다. 진짜 원인은
--    global 의 패턴 버퍼가 512바이트라는 것이다 - 개발서버에서 잰 경계는
--    정확히 511바이트 성공 / 512바이트에서
--      global: buffer overflow. strlimcpy(dest, '...', 512)
--    와 빈 출력이었다. 그래서 480바이트로 끊어 담는다(이름 20개쯤).
--    심볼 20개가 498바이트 패턴 하나로 전부 답을 받았다.
--
-- 3) 지역 변수와 파라미터는 아예 묻지 않는다. GTAGS 는 전역 심볼만 담으므로
--    물어봤자 '없음'이고, 그러면 방금 파랗게 칠한 파라미터·지역변수 선언과
--    sihllocal.lua 의 연두색 참조가 전부 검정으로 덮인다. 특히 대문자
--    지역변수(LOCAL_MAX 같은)는 nvim 기본 쿼리가 @constant 로 잡아서 매크로와
--    구분되지 않는다 - 그래서 이름 기준으로 먼저 걸러 낸다.
--
-- 4) static/const/volatile 은 묻지 않는다. after/queries 가 저장 클래스와
--    한정자를 타입 참조(@si.type.ref)와 같은 캡처로 보내기 때문에, 노드
--    종류(type_identifier)로 한 번 더 거르지 않으면 예약어가 줄마다 검정이
--    된다.
--
-- 5) 프로세스는 배경 작업으로 다룬다. nice/ionice 를 붙이고(이 저장소의
--    autoindex.lua 와 같은 방식), 한 번에 하나만 돌리고, 감시 타이머로
--    프로세스 그룹째 죽이고, 분당 개수를 제한한다. 공용 서버(60코어를
--    840명이 쓴다)에서 고아 색인 프로세스에 코어 하나를 13시간 먹힌 적이
--    있다. 여기서는 nvim 이 꺼질 때도 같이 죽인다.
--
-- 알아 둘 것 --------------------------------------------------------------
--
-- preset 모드에서는 색인이 트리의 일부만 담는다. 그러면 커널 소스 한 화면의
-- 상당수가 검정이 된다 - 실제로 preset 이 701개 파일만 덮는 인덱스에서 화면
-- 심볼 42개 중 25개가 GTAGS 에 없었다(task_struct, WARN_ON, ENOMEM ...).
-- 이것은 고장이 아니라 "내 preset 이 거기를 안 덮는다"를 그대로 보여 주는
-- 것이다. 그 파일들을 색인에 넣으면(\fa, :ProjectFilesReindex) 초록으로
-- 돌아온다. 이 동작이 싫으면 g:sihl_index = 0.
--
-- 옵션
--   g:sihl_index        0 으로 끈다 (기본 1)
--   g:sihl_index_delay  커서가 멈춘 뒤 몇 ms 만에 물을지 (기본 200)
--   g:sihl_index_pad    화면 위아래로 더 볼 줄 수 (기본 20)
--   g:sihl_index_budget 분당 global 프로세스 수 (기본 30, 0 이면 무제한)
--   g:sihl_index_batch  한 번 칠할 때 시작할 배치 수 (기본 2)
--   g:sihl_index_names  한 번에 물을 이름 수 (기본 40)
--   g:sihl_index_db     'near'(기본) 파일에서 가장 가까운 DB / 'root' 가장 바깥
--   g:sihl_index_timeout  한 번의 global 감시 시간 ms (기본 5000)
--   g:sihl_index_nice   0 이면 nice/ionice 를 붙이지 않는다 (기본 1)
--   g:sihl_index_debug  1 이면 판단을 stdpath('cache')/sihlindex.log 에 남긴다
--   :SiHlIndexToggle / :SiHlIndexClear / :SiHlIndexStatus

if vim.g.loaded_sihlindex then
  return
end
vim.g.loaded_sihlindex = 1
if vim.fn.has('nvim-0.10') == 0 then
  return
end

local api = vim.api
local uv = vim.uv or vim.loop
local NS = api.nvim_create_namespace('sihl_index')

local function cfg(name, default)
  local v = vim.g['sihl_index' .. (name == '' and '' or '_' .. name)]
  if v == nil or v == '' then
    return default
  end
  return v
end

local function dbg(msg)
  if cfg('debug', 0) == 0 then
    return
  end
  local f = io.open(vim.fn.stdpath('cache') .. '/sihlindex.log', 'a')
  if f then
    f:write(os.date('%H:%M:%S ') .. msg .. '\n')
    f:close()
  end
end

local KEYWORD = {}
for w in ([[if else for while do switch case break continue return goto sizeof
  struct union enum typedef static const volatile extern inline register auto
  void int char short long float double signed unsigned bool restrict asm
  typeof NULL true false defined]]):gmatch('%S+') do
  KEYWORD[w] = true
end

-- 물어볼 후보인가: 캡처 이름과 노드 종류를 함께 본다.
--   type_identifier      struct/union/enum/typedef 이름을 쓰는 자리
--   identifier + 호출/상수 캡처  함수 호출, 매크로
-- storage_class_specifier / type_qualifier 는 @si.type.ref 를 달고 오지만
-- 노드가 type_identifier 가 아니라서 여기서 걸러진다(4번 주석).
local ASK_CAP = {
  ['function'] = true, ['function.call'] = true, ['function.builtin'] = true,
  ['function.macro'] = true, ['constant'] = true, ['constant.macro'] = true,
  ['si.type.ref'] = true, ['type'] = true,
}
local OK_NODE = { identifier = true, type_identifier = true }

local s = {
  cache = {},     -- root -> { key, found = {}, missing = {} }
  busy = false,
  want = {},      -- root -> { sym -> true }
  tokens = {}, timer = nil, proc = nil, watchdog = nil, killed = false,
}

--------------------------------------------------------------------- 캐시
local function dbkey(root)
  local st = uv.fs_stat(root .. '/.tags/GTAGS') or uv.fs_stat(root .. '/GTAGS')
  return st and (tostring(st.mtime.sec) .. ':' .. tostring(st.size)) or '-'
end

local function bucket(root)
  local b = s.cache[root]
  local key = dbkey(root)
  if not b then
    b = { key = key, found = {}, missing = {} }
    s.cache[root] = b
  elseif b.key ~= key then
    -- 색인이 바뀌면 '없음'만 버린다. 재색인은 없던 것을 생기게 할 뿐이고,
    -- 있던 것이 사라지는 경우는 드물다. 전부 버리면 저장할 때마다 화면의
    -- 검정이 통째로 사라졌다 다시 나타난다.
    b.key, b.missing = key, {}
  end
  return b
end

--------------------------------------------------------------------- 루트
-- 어느 데이터베이스에 물을 것인가.
--
-- 파일에서 위로 올라가다 처음 만나는 GTAGS 를 쓴다. 바깥쪽(가장 상위)
-- 데이터베이스가 아니다 - 그건 RelationView 의 경로 표시 기준이고, 여기서
-- 필요한 것은 'C-] 이 실제로 닿는 곳'이다. 이 트리는 프로젝트 안에 프로젝트가
-- 있어서 둘이 다르다: d5_qnx_hyp 의 GTAGS 는 kernel/common 파일을 39개만
-- 담고, platform_get_drvdata 나 snd_soc_card_get_drvdata 는 거기 없다
-- (kernel/common 자기 GTAGS 에는 있다). 바깥에 물었더니 점프가 멀쩡히 되는
-- 심볼이 전부 검정이 됐다.
--
--   let g:sihl_index_db = 'root'   " 예전처럼 가장 바깥 DB 에 묻는다
local root_cache = {}
local function root_of(buf)
  local name = api.nvim_buf_get_name(buf)
  if name == '' then
    return nil
  end
  local dir = vim.fs.dirname(name)
  if root_cache[dir] ~= nil then
    return root_cache[dir] or nil
  end
  local r
  if tostring(cfg('db', 'near')) == 'root' and _G.relationview_root_for then
    local ok, v = pcall(_G.relationview_root_for, name)
    if ok then r = v end
  end
  if not r then
    local d = dir
    while d and d ~= '/' and d ~= '' do
      if uv.fs_stat(d .. '/.tags/GTAGS') or uv.fs_stat(d .. '/GTAGS') then
        r = d
        break
      end
      local up = vim.fs.dirname(d)
      if up == d then break end
      d = up
    end
  end
  root_cache[dir] = r or false
  return r
end

------------------------------------------------------------------ 프로세스
-- global 이 어디 있는지. ~/.local/bin 은 ~/.profile 에서 PATH 에 붙는데
-- 비대화형 세션은 그것을 읽지 않는다. 절대 경로로 풀어 두지 않으면
-- nice/ionice 가 대신 실패한다 ('ionice: failed to execute global').
local prog_cache
local function prog()
  if prog_cache ~= nil then
    return prog_cache or nil
  end
  local p
  if _G.relationview_global_cmd then
    local ok, v = pcall(_G.relationview_global_cmd)
    if ok then p = v end
  end
  if not p and vim.fn.executable('global') == 1 then
    p = 'global'
  end
  if not p then
    local fb = vim.fn.expand('~/.local/bin/global')
    if vim.fn.executable(fb) == 1 then
      p = fb
    end
  end
  if p and p ~= '' then
    local abs = vim.fn.exepath(p)
    p = (abs ~= '' and abs) or p
  end
  prog_cache = p or false
  return p
end

local function nice_prefix()
  if cfg('nice', 1) == 0 or vim.fn.has('mac') == 1 then
    return {}
  end
  local out = {}
  if vim.fn.executable('nice') == 1 then
    vim.list_extend(out, { 'nice', '-n', '10' })
  end
  if vim.fn.executable('ionice') == 1 then
    vim.list_extend(out, { 'ionice', '-c', '2', '-n', '7' })
  end
  return out
end

-- 프로세스 그룹째 죽인다. TERM 뒤에 KILL 을 '미뤄서' 보내면 안 된다 -
-- nvim 이 그 사이에 끝나면 미룬 것이 사라지고 global 이 살아남는다. 실제로
-- 개발서버에서 98% CPU 로 도는 global 하나가 그렇게 남았다. 둘 다 지금
-- 보낸다. detach = true 라 자식이 세션 리더이므로 pgid == pid 다.
local function kill_group(pid)
  if not pid then return end
  local g = '-' .. tostring(pid)
  pcall(vim.fn.system, { 'kill', '-TERM', g })
  pcall(vim.fn.system, { 'kill', '-KILL', g })
end

local function token_ok()
  local budget = tonumber(cfg('budget', 30)) or 30
  if budget <= 0 then
    return true
  end
  local now = os.time()
  local t = s.tokens
  if t.at ~= now - (now % 60) then
    t.at, t.n = now - (now % 60), 0
  end
  if (t.n or 0) >= budget then
    return false
  end
  t.n = (t.n or 0) + 1
  return true
end

local repaint  -- forward

-- global 은 '<root>/GTAGS' 를 먼저 보고, 없으면 '<root>/$GTAGSOBJDIR/GTAGS'
-- 를 본다. 이 설정은 .tags 를 쓰므로 GTAGSOBJDIR 을 넘겨 줘야 한다 -
-- 비대화형 세션은 ~/.profile 을 읽지 않아 환경에 그 값이 없다. 실제로 이걸
-- 빼먹었더니 개발서버에서 아무것도 칠해지지 않았다(전부 '모름'으로 남았다).
local function db_env(root)
  if _G.relationview_db_env then
    local ok, e = pcall(_G.relationview_db_env)
    if ok and e then
      return e
    end
  end
  if uv.fs_stat(root .. '/GTAGS') then
    return nil
  end
  local d = vim.g.gtags_objdir or vim.env.GTAGSOBJDIR or '.tags'
  return uv.fs_stat(root .. '/' .. d .. '/GTAGS') and { GTAGSOBJDIR = d } or nil
end

-- 한 프로세스 안에서 이름을 하나씩 묻는다.
--
-- 처음에는 정규식 하나로 묶어 물었다 - global -d -e '^(a|b|c)$'. 문법은
-- 되는데 실제 데이터베이스에서 쓸 수가 없다: 앵커된 alternation 에는 리터럴
-- 접두사가 없어서 global 이 색인을 타지 못하고 DB 를 통째로 훑는다.
-- 개발서버의 70MB GTAGS 에서 이름 11개짜리 질의가 60초 타임아웃까지 98%
-- CPU 로 돌았다. 같은 11개를 셸 반복문 안에서 단건으로 물으면 0.16초다
-- (건당 15ms, btree 탐색). 400배 차이라 고민할 여지가 없다.
--
-- 프로세스 수는 여전히 하나다 - 비싼 것은 global 호출이 아니라 fork 라서,
-- 셸 하나 안에서 도는 것은 공용 서버에 티가 나지 않는다.
local function run_batch(root, syms, done)
  local g = prog()
  if not g then
    s.off = 'global 을 찾지 못했습니다'
    done()
    return
  end
  -- 이름은 이미 ^[A-Za-z_][A-Za-z0-9_]*$ 로 걸러져 있어 셸에 그대로 둔다
  -- 종료 코드로 판정하면 안 된다: global -d 는 못 찾아도 0 을 준다(빈
  -- 출력만 다르다). 그렇게 했더니 없는 이름까지 전부 '찾음'이 되어 아무것도
  -- 칠해지지 않았다. 출력이 있는지로 본다.
  local script = 'for s in ' .. table.concat(syms, ' ') ..
      '; do if [ -n "$("$SIHL_G" -d "$s" 2>/dev/null)" ]; then echo "$s"; fi; done'
  local argv = nice_prefix()
  vim.list_extend(argv, { 'sh', '-c', script })
  local env = db_env(root) or {}
  env = vim.tbl_extend('force', env, { SIHL_G = g })
  dbg(('batch root=%s n=%d'):format(root, #syms))
  local ok, proc = pcall(vim.system, argv,
    { cwd = root, text = true, detach = true, env = env },
    vim.schedule_wrap(function(res)
      s.proc = nil
      if s.watchdog then
        pcall(function() s.watchdog:stop(); s.watchdog:close() end)
        s.watchdog = nil
      end
      local b = bucket(root)
      local hit = {}
      if res and res.code == 0 and res.stdout then
        for line in res.stdout:gmatch('[^\n]+') do
          local name = line:match('^%s*(%S+)%s*$')
          if name then hit[name] = true end
        end
      elseif res and res.code ~= 0 then
        dbg(('batch failed rc=%s err=%s'):format(tostring(res.code),
          (res.stderr or ''):sub(1, 120)))
        -- 실패는 '없음'으로 적지 않는다. 그러면 같은 이름을 다음 칠할 때
        -- 또 묻게 되므로, 연달아 실패하면 이 세션에서는 그만둔다.
        -- 예전에 여기서 무한히 재시도한 적이 있다(ionice 가 global 을 못
        -- 찾아 rc=127 이 반복됐다).
        s.fails = (s.fails or 0) + 1
        if s.fails >= 3 then
          s.off = ('global 이 계속 실패합니다 (rc=%s): %s'):format(
            tostring(res.code), (res.stderr or ''):gsub('%s+$', ''):sub(1, 80))
          vim.notify('SiHlIndex 중지 - ' .. s.off, vim.log.levels.WARN)
        end
      end
      if res and res.code == 0 then
        s.fails = 0
        local nf = 0
        for _ in pairs(hit) do nf = nf + 1 end
        dbg(('batch ok n=%d found=%d'):format(#syms, nf))
      end
      -- rc ~= 0 이면 '모른다'로 둔다. 실패를 '없음'으로 적으면 패턴이 한 번
      -- 길었던 것만으로 화면이 통째로 검정이 된다.
      if res and res.code == 0 then
        for _, sym in ipairs(syms) do
          if hit[sym] then
            b.found[sym] = true
          else
            b.missing[sym] = true
          end
        end
      end
      done()
    end))
  if not ok then
    s.proc = nil
    done()
    return
  end
  s.proc = proc
  local ms = tonumber(cfg('timeout', 5000)) or 5000
  s.watchdog = uv.new_timer()
  s.watchdog:start(ms, 0, vim.schedule_wrap(function()
    if s.watchdog then
      pcall(function() s.watchdog:stop(); s.watchdog:close() end)
      s.watchdog = nil
    end
    if s.proc then
      dbg('watchdog kill')
      kill_group(s.proc.pid)
      s.proc = nil
      done()
    end
  end))
end

local function pack(root)
  local want = s.want[root]
  if not want then
    return nil
  end
  local b = bucket(root)
  local out = {}
  local cap = tonumber(cfg('names', 40)) or 40
  for sym in pairs(want) do
    if b.found[sym] == nil and b.missing[sym] == nil then
      out[#out + 1] = sym
    end
    want[sym] = nil
    if #out >= cap then
      break
    end
  end
  if next(want) == nil then
    s.want[root] = nil
  end
  return #out > 0 and out or nil
end

local function drain()
  if s.busy or s.off then
    return
  end
  local root = next(s.want)
  if not root then
    return
  end
  local syms = pack(root)
  if not syms then
    if next(s.want) then
      return drain()
    end
    return
  end
  if not token_ok() then
    dbg('budget exhausted')
    s.want = {}
    return
  end
  s.busy = true
  run_batch(root, syms, function()
    s.busy = false
    -- 답이 왔으면 지금 보이는 화면을 무조건 다시 칠한다. 세대 검사로
    -- 거르면 '스크롤을 멈춘 화면에 표시가 안 뜨다가 키를 누르면 뜨는'
    -- 증상이 난다.
    pcall(repaint)
    drain()
  end)
end

------------------------------------------------------------------- 칠하기
-- 같은 함수 안에서 선언된 이름은 묻지 않는다 (3번 주석)
local function local_names(buf, lang, lo, hi)
  local names = {}
  local ok, q = pcall(vim.treesitter.query.parse, lang, [[
    (parameter_declaration declarator: (identifier) @d)
    (parameter_declaration declarator: (_ declarator: (identifier) @d))
    (parameter_declaration declarator: (_ declarator: (_ declarator: (identifier) @d)))
    (declaration declarator: (identifier) @d)
    (declaration declarator: (_ declarator: (identifier) @d))
    (declaration declarator: (_ declarator: (_ declarator: (identifier) @d)))
  ]])
  if not ok then
    return names
  end
  local okp, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if not okp or not parser then
    return names
  end
  local trees = parser:parse()
  if not trees or not trees[1] then
    return names
  end
  for _, node in q:iter_captures(trees[1]:root(), buf, math.max(0, lo - 400), hi + 400) do
    local t = vim.treesitter.get_node_text(node, buf)
    if t then names[t] = true end
  end
  return names
end

repaint = function()
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then
    return
  end
  local lang = vim.bo[buf].filetype
  if lang ~= 'c' and lang ~= 'cpp' then
    return
  end
  pcall(api.nvim_buf_clear_namespace, buf, NS, 0, -1)
  if cfg('', 1) == 0 then
    return
  end
  local root = root_of(buf)
  if not root then
    return
  end
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return
  end
  local pad = tonumber(cfg('pad', 20)) or 20
  local last = api.nvim_buf_line_count(buf)
  local lo = math.max(0, (info.topline or 1) - 1 - pad)
  local hi = math.min(last, (info.botline or last) + pad)

  local okq, q = pcall(vim.treesitter.query.get, lang, 'highlights')
  if not okq or not q then
    return
  end
  local okp, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if not okp or not parser then
    return
  end
  local trees = parser:parse()
  if not trees or not trees[1] then
    return
  end
  local locals = local_names(buf, lang, lo, hi)
  local b = bucket(root)
  local prio = tonumber(vim.g.sihl_priority) or 200
  local want = s.want[root]
  local decl_here = {}

  -- 선언하는 자리는 건드리지 않는다: 파랑(item 1/2)을 덮으면 안 된다
  for id, node in q:iter_captures(trees[1]:root(), buf, lo, hi) do
    local cap = q.captures[id]
    if cap:match('^si%.declaration') then
      local r1, c1 = node:range()
      decl_here[r1 .. ':' .. c1] = true
    end
  end

  for id, node in q:iter_captures(trees[1]:root(), buf, lo, hi) do
    local cap = q.captures[id]
    if ASK_CAP[cap] and OK_NODE[node:type()] then
      local r1, c1, r2, c2 = node:range()
      if r1 == r2 and r1 >= lo and r1 < hi and not decl_here[r1 .. ':' .. c1] then
        local name = vim.treesitter.get_node_text(node, buf)
        if name and #name > 1 and not KEYWORD[name] and not locals[name]
            and name:match('^[A-Za-z_][A-Za-z0-9_]*$') then
          if b.missing[name] then
            pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
              end_row = r2, end_col = c2,
              hl_group = 'SiJumpNone', priority = prio,
            })
          elseif b.found[name] == nil then
            want = want or {}
            want[name] = true
          end
        end
      end
    end
  end
  if want and next(want) then
    s.want[root] = want
    local n = tonumber(cfg('batch', 2)) or 2
    for _ = 1, n do
      drain()
    end
  end
end

local function schedule()
  if s.timer then
    pcall(function() s.timer:stop(); s.timer:close() end)
    s.timer = nil
  end
  s.timer = uv.new_timer()
  s.timer:start(tonumber(cfg('delay', 200)) or 200, 0, vim.schedule_wrap(function()
    if s.timer then
      pcall(function() s.timer:stop(); s.timer:close() end)
      s.timer = nil
    end
    pcall(repaint)
  end))
end

local group = api.nvim_create_augroup('SiHlIndex', { clear = true })
api.nvim_create_autocmd({ 'BufWinEnter', 'WinScrolled', 'CursorHold',
                          'TextChanged', 'InsertLeave', 'ColorScheme' }, {
  group = group,
  callback = function()
    local ft = vim.bo.filetype
    if ft == 'c' or ft == 'cpp' then
      schedule()
    end
  end,
})

-- nvim 이 끝날 때 남은 것을 반드시 죽인다. 여기서 미루면(defer) 그 콜백이
-- 실행되기 전에 nvim 이 사라져 global 이 그대로 남는다.
api.nvim_create_autocmd({ 'VimLeavePre', 'VimSuspend' }, {
  group = group,
  callback = function()
    if s.proc then
      kill_group(s.proc.pid)
      s.proc = nil
    end
  end,
})

api.nvim_create_user_command('SiHlIndexToggle', function()
  vim.g.sihl_index = (cfg('', 1) == 0) and 1 or 0
  if cfg('', 1) == 0 then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      pcall(api.nvim_buf_clear_namespace, api.nvim_win_get_buf(w), NS, 0, -1)
    end
    vim.notify('SiHlIndex: off')
  else
    vim.notify('SiHlIndex: on')
    schedule()
  end
end, { desc = '색인에 없는 심볼 검정 표시 켜고 끄기' })

api.nvim_create_user_command('SiHlIndexClear', function()
  s.cache, s.want, root_cache = {}, {}, {}
  s.off, s.fails, prog_cache = nil, 0, nil
  vim.notify('SiHlIndex: 캐시를 비웠습니다')
  schedule()
end, { desc = '색인 판정 캐시 비우기' })

api.nvim_create_user_command('SiHlIndexStatus', function()
  local out = {}
  for root, b in pairs(s.cache) do
    local f, m = 0, 0
    for _ in pairs(b.found) do f = f + 1 end
    for _ in pairs(b.missing) do m = m + 1 end
    out[#out + 1] = ('%s  찾음 %d / 없음 %d'):format(vim.fn.fnamemodify(root, ':~'), f, m)
  end
  out[#out + 1] = ('진행 중: %s   global: %s'):format(s.busy and 'yes' or 'no',
    tostring(prog() or '(없음)'))
  if s.off then
    out[#out + 1] = '중지됨: ' .. s.off
  end
  vim.notify(table.concat(out, '\n'))
end, { desc = '색인 판정 현황' })
