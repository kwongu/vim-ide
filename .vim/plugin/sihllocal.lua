-- sihllocal.lua - 지역 변수를 '여기서 선언된 것'으로 알아보고 색을 준다.
--
-- 요구는 "함수 내 로컬 변수를 참조하는 자리를 짙은 연두색으로, 단 정의부로
-- 점프가 가능한 경우만" 이었다. 지역 변수는 gtags 에 없다 - GTAGS 는 전역
-- 심볼만 담고 지역 변수와 파라미터는 아예 넣지 않는다. 그래서 이 질문에
-- 답하는 것은 색인이 아니라 treesitter 다: 같은 함수 안에서 그 이름의 선언을
-- 찾을 수 있으면 점프할 수 있고, 못 찾으면 없는 것이다.
--
-- 프로세스를 하나도 띄우지 않는다. 공용 서버(60코어를 840명이 쓴다)에서
-- 돌아야 하고, 이 저장소는 이미 고아 색인 프로세스에 코어 하나를 13시간
-- 먹힌 적이 있다. 파싱은 treesitter 가 하이라이트 때문에 이미 해 둔 것을
-- 다시 훑는 것뿐이다.
--
-- 칠하는 것은 '찾은 것'뿐이다. 못 찾은 이름은 아무것도 얹지 않아 오늘과
-- 똑같은 본문색(검정)으로 남는다 - 요구의 "심볼을 찾을 수 없는 경우
-- 검은색" 이 그대로 만족되고, 아직 계산 전인 화면이 잠깐 검게 번쩍이는
-- 일도 생기지 않는다.
--
-- 범위: 화면에 보이는 줄 + 위아래 여유. 2만 줄 파일에서도 비용이 화면
-- 크기에 비례한다.
--
-- 옵션
--   g:sihl_local        0 으로 끈다 (기본 1)
--   g:sihl_local_delay  커서가 멈춘 뒤 몇 ms 만에 칠할지 (기본 120)
--   g:sihl_local_pad    화면 위아래로 더 볼 줄 수 (기본 40)
--   g:sihl_local_max    한 번에 훑을 최대 줄 수 (기본 4000)
--   g:sihl_local_global 0 이면 전역 변수 표시를 하지 않는다 (기본 1)
--   :SiHlLocalToggle    실행 중에 켜고 끄기
--
-- 색은 컬러스킴이 준다: SiJumpLocal(지역, 청록), SiGlobalRef(전역, 보라
-- 이탤릭). 전역은 이 파일이 파일 스코프에서 선언한 것만 안다 - 헤더에서
-- 온 extern 변수는 이 파일만 봐서는 변수인지 함수인지도 알 수 없다.

if vim.g.loaded_sihllocal then
  return
end
vim.g.loaded_sihllocal = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local NS = api.nvim_create_namespace('sihl_local')

local function cfg(name, default)
  local v = vim.g['sihl_local' .. (name == '' and '' or '_' .. name)]
  if v == nil or v == '' then
    return default
  end
  return v
end

-- 선언을 잡는 쿼리. after/queries 의 @si.declaration.local / .parameter 와
-- 같은 모양이지만 여기서는 색이 아니라 '이름의 집합'이 필요해서 따로 둔다
-- (하이라이트 쿼리는 nvim 기본 것과 합쳐져 있어 그대로 쓰기에는 넓다).
local DECL_SRC = [[
  (parameter_declaration declarator: (identifier) @d)
  (parameter_declaration declarator: (_ declarator: (identifier) @d))
  (parameter_declaration declarator: (_ declarator: (_ declarator: (identifier) @d)))
  (parameter_declaration declarator: (function_declarator declarator:
    (parenthesized_declarator (pointer_declarator declarator: (identifier) @d))))
  (declaration declarator: (identifier) @d)
  (declaration declarator: (_ declarator: (identifier) @d))
  (declaration declarator: (_ declarator: (_ declarator: (identifier) @d)))
  (declaration declarator: (function_declarator declarator:
    (parenthesized_declarator (pointer_declarator declarator: (identifier) @d))))
]]
local REF_SRC = '((identifier) @r)'

-- 파일 스코프(전역) 변수의 '선언'. 함수 선언은 일부러 빼 둔다 -
-- 'int helper(int);' 도 declaration 이지만 declarator 가 function_declarator
-- 라, 와일드카드로 잡으면 함수 이름까지 전역 변수로 물들인다.
local GLOBAL_SRC = [[
  (translation_unit (declaration declarator: (identifier) @g))
  (translation_unit (declaration declarator: (init_declarator
    declarator: (identifier) @g)))
  (translation_unit (declaration declarator: (pointer_declarator
    declarator: (identifier) @g)))
  (translation_unit (declaration declarator: (array_declarator
    declarator: (identifier) @g)))
  (translation_unit (declaration declarator: (init_declarator
    declarator: (pointer_declarator declarator: (identifier) @g))))
  (translation_unit (declaration declarator: (init_declarator
    declarator: (array_declarator declarator: (identifier) @g))))
  (preproc_ifdef (declaration declarator: (identifier) @g))
  (preproc_ifdef (declaration declarator: (init_declarator
    declarator: (identifier) @g)))
  (preproc_ifdef (declaration declarator: (pointer_declarator
    declarator: (identifier) @g)))
]]

-- 파일 스코프 전역을 모은다. 위 GLOBAL_SRC 와 같은 것을 잡되 쿼리 대신 맨 위
-- 노드들만 걷는다 - 전역 선언은 translation_unit 의 자식(또는 맨 위 #ifdef
-- 사슬 안)에만 있으므로 파일 전체를 훑을 까닭이 없다. 6600줄 파일에서 쿼리는
-- 35ms, 이 걷기는 1ms 안쪽이다 (개발서버 실측). 글자를 고칠 때마다 새로 세야
-- 하는 값이라(스크롤은 담아 둔 것으로 끝난다) 여기가 고친 뒤의 멎음이었다.
--
-- 쿼리와 다른 점 하나: 함수 본문 안의 #ifdef 속 선언은 전역으로 치지 않는다.
-- 쿼리의 (preproc_ifdef (declaration ...)) 는 어디에 있든 잡아서 함수 안
-- 지역 선언까지 전역 색으로 칠했다.
local PREPROC = {
  preproc_ifdef = true, preproc_if = true, preproc_else = true,
  preproc_elif = true, preproc_elifdef = true,
}

-- 함수 정의를 품을 수 있는 그릇들 - 칠할 때(visit) 이 안으로도 내려간다.
-- C 의 '#ifdef __cplusplus / extern "C" {' 가드, C++ 의 namespace/class/
-- template, 구문 오류(ERROR) 조각. 여기로 안 내려가면 그 안의 함수는 '함수
-- 밖'으로 여겨져 지역 색이 빠지고, 전역과 이름이 같은 지역이 전역 색으로
-- 칠해졌다 (반대 심문).
local SCOPE = {
  linkage_specification = true, declaration_list = true,
  namespace_definition = true, template_declaration = true,
  class_specifier = true, struct_specifier = true, union_specifier = true,
  field_declaration_list = true, ERROR = true,
}

local function globals_of(root, buf)
  local globals, gdecl_at = {}, {}
  local function add(id)
    local t = vim.treesitter.get_node_text(id, buf)
    if t and t ~= '' then
      local r1, c1, r2, c2 = id:range()
      globals[t] = true
      gdecl_at[r1 .. ':' .. c1 .. ':' .. r2 .. ':' .. c2] = true
    end
  end
  local function inner(d)
    local x = d and d:field('declarator')[1]
    return (x and x:type() == 'identifier') and x or nil
  end
  -- top: translation_unit 바로 밑, ifdef: #ifdef 바로 밑 (GLOBAL_SRC 의 두 무리)
  local function decl(n, top)
    for _, d in ipairs(n:field('declarator')) do
      local t = d:type()
      if t == 'identifier' then
        add(d)
      elseif t == 'init_declarator' then
        local x = d:field('declarator')[1]
        local xt = x and x:type()
        if xt == 'identifier' then
          add(x)
        elseif top and (xt == 'pointer_declarator' or xt == 'array_declarator') then
          local y = inner(x)
          if y then add(y) end
        end
      elseif t == 'pointer_declarator' or (top and t == 'array_declarator') then
        local y = inner(d)
        if y then add(y) end
      end
    end
  end
  local function walk(parent, is_root)
    for c in parent:iter_children() do
      local t = c:type()
      if t == 'declaration' then
        if is_root then
          decl(c, true)
        elseif parent:type() == 'preproc_ifdef' then
          decl(c, false)
        end
      elseif PREPROC[t] then
        walk(c, false)
      end
    end
  end
  walk(root, true)
  return globals, gdecl_at
end


-- '#if 0' 안의 죽은 코드 줄 구간들 (after/queries/c/highlights.scm 의
-- @si.inactive 와 같은 규칙: #if 0 부터 #else 앞까지, #else 가 없으면 #endif
-- 까지). 거기는 SI 처럼 회색으로 두고 칠하지도 색인에 묻지도 않는다 - 우선
-- 순위 200 의 색이 회색(105)을 덮어 죽은 코드가 살아 있는 것처럼 보였다 (QA).
local INACT_Q = {}
local function inactive_rows(lang, root, buf, lo, hi, out)
  if INACT_Q[lang] == nil then
    local ok, q = pcall(vim.treesitter.query.parse, lang,
      '(preproc_if condition: (number_literal) @z) @blk')
    INACT_Q[lang] = ok and q or false
  end
  local q = INACT_Q[lang]
  if not q then
    return out
  end
  for id, node in q:iter_captures(root, buf, lo, hi) do
    if q.captures[id] == 'blk' then
      local cond = node:field('condition')[1]
      if cond and vim.treesitter.get_node_text(cond, buf) == '0' then
        local sr = node:start()
        local alt = node:field('alternative')[1]
        local er = alt and alt:start() or select(3, node:range())
        out[#out + 1] = { sr, er }
      end
    end
  end
  return out
end

local function in_rows(rs, r)
  for _, x in ipairs(rs) do
    if r > x[1] and r < x[2] then
      return true
    end
  end
  return false
end

-- 창마다 모은 줄 구간을 겹치거나 맞닿는 것끼리 합친다 (같은 곳을 보는 :vsplit 이
-- 같은 일을 두 번 하지 않게 - 반대 심문)
local function merge_ranges(rs)
  table.sort(rs, function(x, y) return x[1] < y[1] end)
  local out = {}
  for _, r in ipairs(rs) do
    local last = out[#out]
    if last and r[1] <= last[2] then
      if r[2] > last[2] then
        last[2] = r[2]
      end
    else
      out[#out + 1] = { r[1], r[2] }
    end
  end
  return out
end

local qcache = {}
local function queries(lang)
  if qcache[lang] == nil then
    local okd, d = pcall(vim.treesitter.query.parse, lang, DECL_SRC)
    local okr, r = pcall(vim.treesitter.query.parse, lang, REF_SRC)
    local okg, g = pcall(vim.treesitter.query.parse, lang, GLOBAL_SRC)
    qcache[lang] = (okd and okr) and { decl = d, ref = r, glob = okg and g or nil }
        or false
  end
  return qcache[lang] or nil
end


local s = { timer = nil }

-- 버퍼마다 '글자가 그대로인 동안은 같은' 계산을 담아 둔다: 파일 스코프 전역
-- 목록과 함수별 선언 이름. 키는 b:changedtick 이다 - 글자가 바뀌면 새로 센다.
--
-- 예전에는 칠할 때마다(스크롤할 때마다) 전역 쿼리를 파일 전체(0..-1)에 돌렸다.
-- 6600줄 파일에서 한 번에 35ms, 전역이 하나도 없어도 그렇다 - 스크롤 한 번에
-- 입력이 50~80ms 씩 멎었다 (개발서버 실측). 스크롤은 글자를 바꾸지 않으니 두
-- 번째부터는 공짜다. RelationView 미리보기 버퍼도 파일이 바뀔 때만 다시 채워지므로
-- 같은 규칙이 먹는다.
local memo = {}   -- buf -> { tick =, globals =, gdecl_at =, fninfo = }

local function memo_of(buf)
  local tick = api.nvim_buf_get_changedtick(buf)
  local m = memo[buf]
  if not m or m.tick ~= tick then
    m = { tick = tick, fninfo = {} }
    memo[buf] = m
  end
  return m
end

local function clear(buf)
  pcall(api.nvim_buf_clear_namespace, buf, NS, 0, -1)
end

local function paint(win)
  if not api.nvim_win_is_valid(win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  -- 일반 파일 창과 RelationView 의 미리보기. 미리보기는 nofile 사본이지만
  -- 내용은 그 파일 그대로라, 같은 색 규칙이 그대로 적용된다 - 편집 창과
  -- 미리보기가 다른 색으로 보이면 그게 더 헷갈린다.
  if vim.bo[buf].buftype ~= ''
      and not api.nvim_buf_get_name(buf):match('RelationView%-Context$') then
    return
  end
  clear(buf)
  if cfg('', 1) == 0 then
    return
  end
  local lang = vim.bo[buf].filetype
  if lang == 'cpp' then
    lang = 'cpp'
  elseif lang ~= 'c' then
    return
  end
  local q = queries(lang)
  if not q then
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
  local root = trees[1]:root()

  -- 이 버퍼를 보여 주는 (지금 탭의) 창마다 그 창의 보이는 줄(+여유)을 칠한다.
  -- 네임스페이스는 버퍼에 붙으므로 한 창 몫만 칠하면 같은 버퍼를 보여 주는 다른
  -- 창(:vsplit)의 색이 통째로 지워졌다 (QA 실측). 다른 탭의 창은 그 탭에 들어갈
  -- 때(BufWinEnter/WinScrolled/CursorHold) 다시 칠해진다.
  local pad = tonumber(cfg('pad', 40)) or 40
  local maxl = tonumber(cfg('max', 4000)) or 4000
  local last = api.nvim_buf_line_count(buf)
  local ranges = {}
  local wins = { win }
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if w ~= win and api.nvim_win_get_buf(w) == buf then
      wins[#wins + 1] = w
    end
  end
  for _, w in ipairs(wins) do
    local info = vim.fn.getwininfo(w)[1]
    if info then
      local a = math.max(0, (info.topline or 1) - 1 - pad)
      local b = math.min(last, (info.botline or last) + pad)
      if (b - a) > maxl then
        b = a + maxl
      end
      ranges[#ranges + 1] = { a, b }
    end
  end
  if #ranges == 0 then
    return
  end
  ranges = merge_ranges(ranges)
  local lo, hi = ranges[1][1], ranges[1][2]

  -- 보이는 줄이 걸쳐 있는 함수들을 모으고, 함수마다 선언된 이름을 센다.
  -- 함수 단위로 보는 이유: C 에서 블록마다 가리는 경우는 드물고, 블록까지
  -- 따지면 한 줄을 칠할 때마다 스코프를 거슬러 올라가야 한다. 함수 하나를
  -- 한 번 훑어 이름 집합을 만들어 두는 쪽이 훨씬 싸고, 틀리는 경우는
  -- '같은 함수 안 다른 블록의 같은 이름' 뿐인데 그것도 점프는 된다.
  -- 이 파일이 파일 스코프에서 선언한 변수들. 이 이름을 어디서 쓰든 -
  -- 함수 안이든, 다른 전역의 초기값이든, 구조체 초기화 목록 안이든 -
  -- 이 함수 밖의 상태를 건드리는 것이라 눈에 띄어야 한다.
  --
  -- 헤더에서 온 전역(extern)은 여기서 보이지 않는다. 이 파일만 봐서는
  -- extern 이름이 변수인지 함수인지도 알 수 없다.
  local m = memo_of(buf)
  if not m.globals then
    if q.glob then
      m.globals, m.gdecl_at = globals_of(root, buf)
    else
      m.globals, m.gdecl_at = {}, {}
    end
  end
  local globals, gdecl_at = m.globals, m.gdecl_at

  -- 함수마다 '여기서 선언된 이름'을 한 번만 모아 둔다.
  --
  -- 함수 단위로 보는 이유: C 에서 블록마다 가리는 경우는 드물고, 블록까지
  -- 따지면 한 줄을 칠할 때마다 스코프를 거슬러 올라가야 한다. 틀리는 경우는
  -- '같은 함수 안 다른 블록의 같은 이름' 뿐인데 그것도 점프는 된다.
  -- 같은 글자면 같은 트리이고, 노드 id 도 같다 - 함수별 이름 집합도 담아 둔다
  local fninfo = m.fninfo
  local function info_of(fn)
    local id = fn:id()
    if fninfo[id] then
      return fninfo[id]
    end
    local declared, decl_at = {}, {}
    local fs, _, fe, _ = fn:range()
    for _, node in q.decl:iter_captures(fn, buf, fs, fe + 1) do
      local r1, c1, r2, c2 = node:range()
      local name = vim.treesitter.get_node_text(node, buf)
      if name and name ~= '' then
        declared[name] = true
        decl_at[r1 .. ':' .. c1 .. ':' .. r2 .. ':' .. c2] = true
      end
    end
    fninfo[id] = { declared = declared, decl_at = decl_at }
    return fninfo[id]
  end

  local prio = tonumber(vim.g.sihl_priority) or 200
  local glob_on = (tonumber(vim.g.sihl_local_global) or 1) ~= 0
  local done = {}
  local inact = {}
  for _, r in ipairs(ranges) do
    inactive_rows(lang, root, buf, r[1], r[2], inact)
  end
  local function paint_ref(node, fn)
    local r1, c1, r2, c2 = node:range()
    if r1 == r2 and r1 >= lo and r1 < hi and not in_rows(inact, r1) then
      local at = r1 .. ':' .. c1 .. ':' .. r2 .. ':' .. c2
      if not done[at] then
        done[at] = true
        local name = vim.treesitter.get_node_text(node, buf)
        local hl
        if fn then
          local i = info_of(fn)
          -- 선언한 자리 자체는 이미 파랑이다 (파라미터/지역변수). 덮지 않는다.
          if i.declared[name] and not i.decl_at[at] then
            hl = 'SiJumpLocal'
          elseif glob_on and globals[name] and not i.declared[name]
              and not gdecl_at[at] then
            -- 지역에 같은 이름이 있으면 그게 이긴다 (가리는 쪽이 실제로
            -- 쓰이는 것이므로)
            hl = 'SiGlobalRef'
          end
        elseif glob_on and globals[name] and not gdecl_at[at] then
          hl = 'SiGlobalRef'
        end
        if hl then
          pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
            end_row = r2, end_col = c2,
            hl_group = hl, priority = prio,
          })
        end
      end
    end
  end
  -- 위에서 아래로 내려가며 이름을 센다: 보이는 줄에 걸친 맨 위 노드를 골라,
  -- 함수 정의면 그 안의 이름은 모두 그 함수 것이다. 예전에는 이름마다
  -- node:parent() 로 거슬러 올라가 감싸는 함수를 찾았는데, treesitter 의
  -- parent() 는 매번 루트에서부터 다시 내려오며 찾는다 - 함수가 600개인
  -- 파일에서 이름 하나에 0.13ms, 한 번 칠하는 데 50~100ms 가 들었다
  -- (개발서버 실측). #ifdef 사슬은 안으로 들어간다. C 에는 함수 안의 함수가
  -- 없으니 결과는 같다.
  local function visit(parent)
    for c in parent:iter_children() do
      local sr, _, er, _ = c:range()
      if er >= lo and sr < hi then
        local t = c:type()
        if PREPROC[t] or SCOPE[t] then
          visit(c)
        else
          local fn = (t == 'function_definition') and c or nil
          for _, node in q.ref:iter_captures(c, buf, math.max(lo, sr), math.min(hi, er + 1)) do
            paint_ref(node, fn)
          end
        end
      end
    end
  end
  for _, r in ipairs(ranges) do
    lo, hi = r[1], r[2]
    visit(root)
  end
end

local function schedule()
  if s.timer then
    s.timer:stop()
    s.timer:close()
    s.timer = nil
  end
  local win = api.nvim_get_current_win()
  local delay = tonumber(cfg('delay', 120)) or 120
  s.timer = (vim.uv or vim.loop).new_timer()
  s.timer:start(delay, 0, vim.schedule_wrap(function()
    if s.timer then
      s.timer:stop()
      s.timer:close()
      s.timer = nil
    end
    pcall(paint, win)
  end))
end

local group = api.nvim_create_augroup('SiHlLocal', { clear = true })
api.nvim_create_autocmd({ 'BufWipeout', 'BufUnload' }, {
  group = group,
  callback = function(a) memo[a.buf] = nil end,
})
api.nvim_create_autocmd({ 'BufWinEnter', 'WinScrolled', 'TextChanged', 'InsertLeave',
                          'CursorHold', 'BufWritePost', 'ColorScheme' }, {
  group = group,
  callback = function()
    local ft = vim.bo.filetype
    if ft == 'c' or ft == 'cpp' then
      schedule()
    end
    -- 미리보기는 편집 창의 커서가 움직일 때 내용이 바뀐다. 그 창이 떠
    -- 있으면 같이 다시 칠한다.
    if _G.relationview_ctx_win then
      local ok, cw = pcall(_G.relationview_ctx_win)
      if ok and cw and api.nvim_win_is_valid(cw) then
        vim.defer_fn(function() pcall(paint, cw) end,
          (tonumber(cfg('delay', 120)) or 120) + 60)
      end
    end
  end,
})

api.nvim_create_user_command('SiHlLocalToggle', function()
  vim.g.sihl_local = (cfg('', 1) == 0) and 1 or 0
  if cfg('', 1) == 0 then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      clear(api.nvim_win_get_buf(w))
    end
    vim.notify('SiHlLocal: off')
  else
    vim.notify('SiHlLocal: on')
    schedule()
  end
end, { desc = '지역 변수 참조 색칠 켜고 끄기' })
