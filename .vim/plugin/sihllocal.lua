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

-- 이 노드를 감싸는 함수 정의
local function enclosing_fn(node)
  local n = node
  while n do
    local t = n:type()
    if t == 'function_definition' then
      return n
    end
    n = n:parent()
  end
  return nil
end

local s = { timer = nil }

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

  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return
  end
  local pad = tonumber(cfg('pad', 40)) or 40
  local last = api.nvim_buf_line_count(buf)
  local lo = math.max(0, (info.topline or 1) - 1 - pad)
  local hi = math.min(last, (info.botline or last) + pad)
  if (hi - lo) > (tonumber(cfg('max', 4000)) or 4000) then
    hi = lo + (tonumber(cfg('max', 4000)) or 4000)
  end

  -- 보이는 줄이 걸쳐 있는 함수들을 모으고, 함수마다 선언된 이름을 센다.
  -- 함수 단위로 보는 이유: C 에서 블록마다 가리는 경우는 드물고, 블록까지
  -- 따지면 한 줄을 칠할 때마다 스코프를 거슬러 올라가야 한다. 함수 하나를
  -- 한 번 훑어 이름 집합을 만들어 두는 쪽이 훨씬 싸고, 틀리는 경우는
  -- '같은 함수 안 다른 블록의 같은 이름' 뿐인데 그것도 점프는 된다.
  local fns, seen = {}, {}
  for _, node in q.ref:iter_captures(root, buf, lo, hi) do
    local fn = enclosing_fn(node)
    if fn and not seen[fn:id()] then
      seen[fn:id()] = true
      fns[#fns + 1] = fn
    end
  end
  if #fns == 0 then
    return
  end

  -- 이 파일이 파일 스코프에서 선언한 변수들. 함수 안에서 이 이름을 쓰면
  -- 전역 변수를 건드리는 것이고, 그건 지역 변수와 눈에 띄게 달라야 한다.
  -- 헤더에서 온 전역(extern)은 여기서 보이지 않는다 - 이 파일이 가진
  -- 정보만으로 말할 수 있는 것만 말한다.
  local globals = {}
  if q.glob then
    for _, node in q.glob:iter_captures(root, buf, 0, -1) do
      local t = vim.treesitter.get_node_text(node, buf)
      if t and t ~= '' then globals[t] = true end
    end
  end

  local prio = tonumber(vim.g.sihl_priority) or 200
  for _, fn in ipairs(fns) do
    local declared = {}
    local decl_at = {}
    local fs, _, fe, _ = fn:range()
    for _, node in q.decl:iter_captures(fn, buf, fs, fe + 1) do
      local r1, c1, r2, c2 = node:range()
      local name = vim.treesitter.get_node_text(node, buf)
      if name and name ~= '' then
        declared[name] = true
        decl_at[r1 .. ':' .. c1 .. ':' .. r2 .. ':' .. c2] = true
      end
    end
    if next(declared) then
      for _, node in q.ref:iter_captures(fn, buf, math.max(lo, fs), math.min(hi, fe + 1)) do
        local r1, c1, r2, c2 = node:range()
        if r1 >= lo and r1 < hi and r1 == r2 then
          local name = vim.treesitter.get_node_text(node, buf)
          -- 선언한 자리 자체는 이미 파랑이다 (item 1/2). 덮지 않는다.
          local at = r1 .. ':' .. c1 .. ':' .. r2 .. ':' .. c2
          local hl
          if declared[name] and not decl_at[at] then
            hl = 'SiJumpLocal'
          elseif globals[name] and not declared[name]
              and (tonumber(vim.g.sihl_local_global) or 1) ~= 0 then
            -- 지역에 같은 이름이 있으면 그게 이긴다 (가리는 쪽이 실제로
            -- 쓰이는 것이므로)
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
