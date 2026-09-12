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
--   g:sihl_index_db     'chain'(기본) 현재 디렉터리 프로젝트부터 위로 /
--                       'near' 하나만 / 'root' 가장 바깥만
--   g:sihl_index_members 0 이면 구조체 멤버는 묻지 않는다 (기본 1).
--                        멤버는 이름이 아니라 베이스 변수의 타입을 풀어서
--                        판정한다 - GNU Global 이 멤버를 색인하지 않아서다
--   g:sihl_index_ctags  0 이면 ctags 스냅숏은 보지 않는다 (기본 1)
--   g:sihl_index_macro_navy  이 경로들에 정의된 매크로는 네이비 볼드
--                            (기본 { 'include/linux/module%.h' })
--   g:sihl_index_log_macros  로그 매크로 이름 패턴. 여기 걸리는 '함수형'
--                            매크로는 빨강이 아니라 초록 볼드로 둔다
--                            (ape_dbg, arpc_info, DIRAC_TRACE_ERR ...).
--                            [] 로 두면 예전처럼 전부 빨강
--   g:sihl_index_timeout  한 번의 global 감시 시간 ms (기본 5000)
--   g:sihl_index_nice   0 이면 nice/ionice 를 붙이지 않는다 (기본 1)
--   g:sihl_index_debug  1 이면 판단을 stdpath('cache')/sihlindex.log 에 남긴다
--   :SiHlIndexToggle / :SiHlIndexClear / :SiHlIndexStatus
--   :SiHlIndexWhy [심볼]  이 이름이 왜 그 색인지 (어느 DB, 캐시, 지금 물어본 결과)
--   :SiHlIndexAdd [심볼]  이 심볼을 정의한 파일을 찾아 색인에 넣는다

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
local OK_NODE = { identifier = true, type_identifier = true,
                  field_identifier = true }
-- 기본색이 빨강인 캡처. 찾았는데 매크로가 아니면 초록으로 돌려놔야 한다.
local CONST_CAP = { ['constant'] = true, ['constant.macro'] = true }
-- 기본색이 본문색(검정)인 캡처: 구조체 멤버. 찾았으면 초록으로 올린다.
--
-- GNU Global 의 기본 파서는 멤버를 대부분 색인하지 않는다 - 실제 커널
-- 인덱스에서 dai_link, num_links, codec_dai_name, runtime 은 전부 0 이고
-- private_data 만 1 이었다(줄 하나짜리 포인터 멤버라 정의로 읽힌 것 같다).
-- 그래서 대부분은 오늘과 같이 검정으로 남고, 색인이 진짜로 아는 멤버만
-- 초록이 된다 - 그게 '점프되는 것만 초록' 이라는 규칙 그대로다.
--   let g:sihl_index_members = 0   " 멤버는 묻지 않는다
local MEMBER_CAP = { ['property'] = true, ['variable.member'] = true }

-- 어떤 헤더의 매크로는 '코드'가 아니라 '선언'이다.
--
-- include/linux/module.h 의 MODULE_LICENSE, module_init, EXPORT_SYMBOL 같은
-- 것들은 화면에서 예약어처럼 읽힌다 - 무엇을 계산하는 자리가 아니라 무엇을
-- 선언하는 자리라서다. 정의가 어느 파일에 있는지는 색인이 알려 주므로
-- (ctags-x 의 세 번째 칼럼이 경로다) 경로로 고른다.
--
--   let g:sihl_index_macro_navy = ['include/linux/module%.h']   " 기본값
--   let g:sihl_index_macro_navy = []                            " 전부 빨강
-- 항목에 '/' 가 있으면 정의 파일의 경로로, 없으면 심볼 이름으로 본다.
-- 이름 쪽은 색인을 타지 않는다 - THIS_MODULE 이 그래서 필요했다:
-- include/linux/export.h 에 있는데 이 트리의 두 색인이 모두 모른다.
--
-- EXPORT_SYMBOL 도 경로가 아니라 이름으로 잡는다. 경로로는 못 잡는다:
-- 이 트리에서 바깥 루트는 그것을 include/linux/export.h 가 아니라
-- kernel/common/include/asm-generic/export.h 에서 찾고, kernel/common 을
-- 루트로 열면 아예 못 찾는다(그 헤더가 어느 목록에도 없다). 어느 쪽에서
-- 일하느냐에 따라 색이 달라지면 안 된다.
--
-- 패턴은 string.find 라 앵커가 없으므로 'EXPORT_SYMBOL' 하나가
-- EXPORT_SYMBOL_GPL / _NS / _NS_GPL 까지 함께 덮는다 - 색인된 파일에서
-- 실제로 쓰인 횟수는 GPL 872, 맨 것 165, NS 계열 5 이다.
local function navy_pats()
  local v = vim.g.sihl_index_macro_navy
  if v == nil then
    return { 'include/linux/module%.h', 'THIS_MODULE', 'EXPORT_SYMBOL' }
  end
  if type(v) == 'string' then
    return v ~= '' and { v } or {}
  end
  return type(v) == 'table' and v or {}
end

-- 로그 매크로는 빨강이 아니라 초록 볼드다.
--
-- 'ape_dbg("...")' 는 읽을 때 함수 호출이다. 매크로라는 이유로 빨강이 되면
-- 본문에서 로그 줄만 눈에 튀어 정작 읽어야 할 코드를 가린다. 이 프로젝트의
-- #define 706개 중 110개가 로그 매크로였다(ape_dbg/ape_info/ape_err,
-- arpc_*_dbg, alsa_*, ak4601_*, DIRAC_TRACE_* ...).
--
-- 이름만으로는 부족했다. TCC_ENABLE_DIRAC_TRACE_DBG 나 DEBUG_INFO 는
-- '#define X (1 << 0)' 꼴의 스위치지 로그가 아니다. 그래서 두 가지를 모두
-- 본다: 이름이 로그 어휘이고, #define 이 '함수형'일 것
-- (이름 바로 뒤에 '(' 이 붙는다). 이 트리에서 오탐 4개가 전부 걸러졌다.
--
--   let g:sihl_index_log_macros = []                  " 전부 예전처럼 빨강
--   let g:sihl_index_log_macros = ['^my_trace']       " 내 것만
-- 이름은 소문자로 낮춰 비교하므로 _DBG 든 _dbg 든 같다. lua 패턴이다.
local function log_pats()
  local v = vim.g.sihl_index_log_macros
  if v == nil then
    return { '_dbg$', '_debug$', '_info$', '_err$', '_error$', '_warn$',
      '_warning$', '_log$', '_trace$', '_print$', '_printf$', '_msg$',
      '_verbose$', '_notice$', '_fatal$', '_assert$',
      '^pr_', '^dev_dbg', '^dev_err', '^dev_info', '^dev_warn', '^dev_printk',
      '^printk$', '^alog', '^log_', '^dbg_', '^trace_' }
  end
  if type(v) == 'string' then
    return v ~= '' and { v } or {}
  end
  return type(v) == 'table' and v or {}
end

-- 함수처럼 부르는 매크로인가: '#define NAME(' - 이름 바로 뒤에 '(' 이 붙는다.
-- src 는 색인이 준 '정의가 적힌 소스 줄'이다.
--
-- 이게 상수 매크로와 갈리는 자리다. '#define LIMIT (5)' 는 값에 괄호가
-- 있어도 이름과 '(' 사이가 떨어져 있어 여기 걸리지 않는다.
local function is_fn_macro(name, src)
  if not name or name == '' or not src then
    return false
  end
  return src:find('#%s*define%s+' .. name:gsub('%W', '%%%0') .. '%(') ~= nil
end

-- 이 #define 이 로그 매크로인가.
local function is_log_macro(name, src)
  if not is_fn_macro(name, src) then
    return false
  end
  local low = name:lower()
  for _, pat in ipairs(log_pats()) do
    local ok, hit = pcall(string.find, low, pat)
    if ok and hit then
      return true
    end
  end
  return false
end

-- enum 요소를 '쓰는' 자리인가.
--
-- 정의 줄이 이름으로 시작하고 그 뒤가 비었거나 ',' 이거나 '= 값' 이면
-- enum 요소다. 색인이 주는 줄은 이런 모양이다:
--   COMP_DISABLE            =  0,
--   BF_BYPASS,
-- 전역 변수는 'int G = 5;' 처럼 타입이 앞에 오고 ';' 로 끝나며, 매크로는
-- '#define ...' 으로 시작하므로 둘 다 여기 걸리지 않는다. 선언하는 자리는
-- 애초에 칠하지 않는다(@si.declaration.enumconst 가 decl_here 로 빠진다).
local function is_enum_const(name, src)
  if not src or src == '' or not name or name == '' then
    return false
  end
  local rest = src:match('^' .. name:gsub('%W', '%%%0') .. '%s*(.*)$')
  if not rest then
    return false
  end
  rest = rest:gsub('/%*.*$', ''):gsub('//.*$', ''):gsub('%s+$', '')
  if rest == '' or rest == ',' then
    return true
  end
  -- '=' 이어야 한다. 'FOO == 1' 은 값을 주는 자리가 아니라 비교하는 자리다.
  return rest:sub(1, 1) == '=' and rest:sub(2, 2) ~= '='
      and not rest:find(';', 1, true)
end

-- 이 자리가 '부르는' 자리인가: call_expression 의 function 자리.
--
-- 정의만 봐서는 모자란다. '#define MIX(a,b)' 는 함수형이지만 MIX 를 괄호
-- 없이 이름으로만 쓰면 그건 호출이 아니라 참조다 - 그때는 상수 매크로와
-- 같은 빨강이 맞다. treesitter 로 정확히 갈린다: MIX(p,2) 는 부모가
-- call_expression 이고 그 function 자리가 이 노드다.
local function is_called(node)
  local p = node:parent()
  if not p or p:type() ~= 'call_expression' then
    return false
  end
  local f = p:field('function')[1]
  return f ~= nil and f:id() == node:id()
end

-- EXPORT_SYMBOL(sym) 의 sym 자리인가.
--
-- 그 자리에 오는 이름은 언제나 이 파일이 정의한 함수나 변수다 - 내보내는
-- 대상이니까. 그래서 색인을 묻지 않고 함수 호출과 같은 초록 볼드로 둔다.
-- 기본 쿼리는 그 자리를 @variable 로 잡아 본문색(검정)으로 두고 있었다.
--   let g:sihl_index_export_macros = []   " 이 규칙을 끈다
local function export_pats()
  local v = vim.g.sihl_index_export_macros
  if v == nil then
    return { 'EXPORT_SYMBOL' }
  end
  if type(v) == 'string' then
    return v ~= '' and { v } or {}
  end
  return type(v) == 'table' and v or {}
end

local function export_arg(node, buf)
  local p = node:parent()
  if not p or p:type() ~= 'argument_list' then
    return false
  end
  local call = p:parent()
  if not call or call:type() ~= 'call_expression' then
    return false
  end
  local f = call:field('function')[1]
  if not f then
    return false
  end
  local okn, nm = pcall(vim.treesitter.get_node_text, f, buf)
  if not okn or type(nm) ~= 'string' then
    return false
  end
  for _, pat in ipairs(export_pats()) do
    local ok, hit = pcall(string.find, nm, pat)
    if ok and hit then
      return true
    end
  end
  return false
end

local function macro_kind(path, name, src)
  -- 경로로 정한 네이비가 먼저다. 이름 어휘보다도 먼저여야 한다:
  -- include/linux/module.h 의 MODULE_INFO(tag, info) 는 이름이 '_info' 로
  -- 끝나 로그 어휘에 걸리는데, 그건 로그가 아니라 선언하는 자리다.
  -- (이 트리의 색인은 module.h 를 담고 있지 않아 지금은 화면에 안 나오지만,
  --  담기는 순간 초록 볼드가 됐을 것이다.)
  for _, pat in ipairs(navy_pats()) do
    if pat:find('/') and path and path ~= '' then
      local ok, hit = pcall(string.find, path, pat)
      if ok and hit then
        return 'macrokw'
      end
    end
  end
  if is_log_macro(name, src) then
    return 'logmacro'
  end
  -- 함수처럼 부르는 매크로는 읽을 때 함수 호출이다: 빨강은 상수 매크로 몫.
  if is_fn_macro(name, src) then
    return 'fnmacro'
  end
  return 'macro'
end

-- 이름만으로 네이비로 정한 것인가 (색인을 묻지 않는다)
local function navy_name(name)
  for _, pat in ipairs(navy_pats()) do
    if not pat:find('/') then
      local ok, hit = pcall(string.find, name, pat)
      if ok and hit then
        return true
      end
    end
  end
  return false
end

local s = {
  cache = {},     -- root -> { key, found = {}, missing = {} }
  snap_ok = {},   -- root -> 이 루트에서 ctags 스냅숏까지 봐도 되는가
  snaps = {},     -- root -> 그때 볼 스냅숏 경로들 (체인 전체의 것)
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
    b = { key = key, found = {}, missing = {}, how = {} }
    s.cache[root] = b
  elseif b.key ~= key then
    -- 색인이 바뀌면 '없음'만 버린다. 재색인은 없던 것을 생기게 할 뿐이고,
    -- 있던 것이 사라지는 경우는 드물다. 전부 버리면 저장할 때마다 화면의
    -- 검정이 통째로 사라졌다 다시 나타난다.
    b.key, b.missing = key, {}
    b.how = b.how or {}
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
-- 파일 위쪽의 데이터베이스를 가까운 것부터 전부 모은다.
--
-- 하나만 보면 안 된다. 이 트리에는 Android14_IVI_1.1.0 아래에
-- kernel/common 이 자기 색인을 또 갖고 있는데, 그 색인 목록은 5개 파일뿐
-- 이라 device_create 를 모른다 - 바깥 색인(435 파일)은 안다. 반대로
-- d5_qnx_hyp 에서는 바깥이 39개만 담고 안쪽이 다 안다. 어느 쪽이 맞다고
-- 정할 수가 없으니 가까운 것부터 차례로 묻고, 하나라도 알면 찾은 것이다 -
-- C-] 도 결국 그중 하나로 닿는다.
--
--   let g:sihl_index_db = 'near'   " 시작점의 DB 하나만
--   let g:sihl_index_db = 'root'   " 가장 바깥 DB 하나만
--
-- 시작점은 '현재 디렉터리의 프로젝트'다 (projectfiles 의 anchor_cwd 와 같은
-- 규칙). 그 아래에 있는 preset 은 쓰지 않는다.
local chain_cache = {}
local function roots_of(buf)
  local name = api.nvim_buf_get_name(buf)
  if name:match('RelationView%-Context$') and _G.relationview_ctx_path then
    local ok, pth = pcall(_G.relationview_ctx_path)
    if ok and pth and pth ~= '' then
      name = pth
    end
  end
  if name == '' then
    return {}
  end
  local dir = vim.fs.dirname(name)
  if chain_cache[dir] then
    return chain_cache[dir]
  end
  local mode = tostring(cfg('db', 'chain'))
  local out = {}
  local home = vim.env.HOME or '/'

  -- 출발점은 '지금 디렉터리의 프로젝트'다.
  --
  -- projectfiles 의 규칙(anchor_cwd)과 같다: 열고 있는 파일이 현재 디렉터리
  -- 프로젝트 안에 있으면 그 프로젝트를 쓰고, 그 아래에 있는 preset 은 쓰지
  -- 않는다. 예전에는 파일에서부터 위로 올라가며 가장 가까운 DB 를 먼저
  -- 물었는데, 그러면 Android14_IVI_1.1.0 에서 일하는 중에도 그 밑의
  -- kernel/common preset(파일 5개)이 먼저 답해 버렸다. preset 을 고르는
  -- 곳과 색을 정하는 곳이 다른 프로젝트를 보고 있으면 안 된다.
  local function walk_up(from)
    local list = {}
    local d = from
    while d and d ~= '/' and d ~= '' and #list < 4 do
      if uv.fs_stat(d .. '/.tags/GTAGS') or uv.fs_stat(d .. '/GTAGS') then
        list[#list + 1] = d
      end
      if d == home then
        break
      end
      local up = vim.fs.dirname(d)
      if up == d then break end
      d = up
    end
    return list
  end

  local start = dir
  if _G.projectfiles_root_of then
    local okr, r = pcall(_G.projectfiles_root_of, dir .. '/x')
    if okr and r and r ~= '' then
      start = r
    end
  end
  out = walk_up(start)
  -- 시작점 위에 DB 가 하나도 없으면(그 프로젝트에 아직 색인이 없는 경우)
  -- 예전처럼 파일에서부터 올라가며 찾는다 - 아무 답도 못 하는 것보다 낫다.
  if #out == 0 then
    out = walk_up(dir)
  end
  if mode == 'near' and #out > 1 then
    out = { out[1] }
  elseif mode == 'root' and #out > 1 then
    out = { out[#out] }
  end
  chain_cache[dir] = out
  return out
end

local root_cache = {}
local function root_of(buf)
  local name = api.nvim_buf_get_name(buf)
  -- 미리보기 버퍼는 파일의 사본이라 이름으로 루트를 못 찾는다. 지금 무엇을
  -- 보여 주고 있는지 RelationView 에게 묻는다.
  if name:match('RelationView%-Context$') and _G.relationview_ctx_path then
    local ok, p = pcall(_G.relationview_ctx_path)
    if ok and p and p ~= '' then
      name = p
    end
  end
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

local repaint, repaint_ctx  -- forward: 아래 drain() 이 둘 다 부른다.

-- 멤버 판정은 이름마다 따로 돌아온다. 돌아올 때마다 칠하면 화면 하나에
-- 스무 번을 칠하게 되므로 한 번으로 묶는다.
local redraw_pending = false
local function redraw_soon()
  if redraw_pending then
    return
  end
  redraw_pending = true
  vim.defer_fn(function()
    redraw_pending = false
    pcall(repaint)
    pcall(repaint_ctx)
  end, 60)
end
-- 이 저장소에서 '정의가 사용처보다 뒤에 있어 nil 전역이 되는' Lua 함정을
-- 세 번 밟았다. 쓰는 곳보다 앞에 선언해 둔다.

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
-- gtags 가 모른다고 한 이름을 ctags 스냅숏에도 물어본다.
--
-- 둘은 서로 다른 파서다. GNU Global 의 기본 파서는 구조체 멤버와 일부
-- 매크로·inline 을 정의로 기록하지 않는데, gutentags 가 만드는 ctags
-- 스냅숏에는 들어 있다. 그리고 이 설정에서 C-] 는 그 스냅숏으로도 점프한다
-- (&tags 가 걸려 있을 때). 그러니 gtags 만 보고 '없음'이라고 하면 점프가
-- 멀쩡히 되는 이름이 검정이 된다 - 실제로 tcc-snd-card.c 한 파일에서
-- 검정 22개 중 12개가 ctags 에는 있었다(num_rtd, kzalloc, of_node,
-- snd_soc_dai_set_sysclk ...).
--
-- 'tagcase' 를 잠깐 match 로 바꾼다. 이 설정은 ignorecase 라 기본값
-- followic 이면 정렬된 파일을 이분 탐색하지 못하고 훑는다: 7MB 스냅숏에서
-- 이름당 7.01ms 대 0.16ms, 44배 차이였다(찾는 개수는 똑같다).
--   let g:sihl_index_ctags = 0   " ctags 스냅숏은 보지 않는다
local function in_tags(syms, allow)
  local out = {}
  if not allow or (tonumber(cfg('ctags', 1)) or 1) == 0
      or #vim.fn.tagfiles() == 0 then
    return out
  end
  local save = vim.o.tagcase
  vim.o.tagcase = 'match'
  local ok = pcall(function()
    for _, sym in ipairs(syms) do
      local t = vim.fn.taglist('^' .. sym .. '$')
      if t and #t > 0 then
        -- ctags 의 kind 'd' 는 #define 이다
        out[sym] = (t[1].kind == 'd')
                and macro_kind(t[1].filename, sym, t[1].cmd)
            or (t[1].kind == 'e' and 'enum')
            or true
      end
    end
  end)
  vim.o.tagcase = save
  if not ok then
    return {}
  end
  return out
end

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
  --
  -- --result=ctags-x 는 정의가 적힌 '소스 줄'까지 준다:
  --   ADD    4 defs.h   #define ADD(a, b) ((a) + (b))
  --   thing  5 defs.h   struct thing { int m; };
  -- 이걸로 매크로인지 아닌지를 안다. treesitter 는 알 수가 없다 - 함수형
  -- 매크로 ADD(x, 2) 는 함수 호출과 구문이 똑같아서 초록 볼드로 나왔다.
  -- gtags 가 못 찾으면 ctags 스냅숏을 'look' 으로 이분 탐색한다.
  --
  -- vim 의 taglist() 를 쓸 수 없는 프로젝트가 있다: 스냅숏이 커서(여기서는
  -- 1747MB) autoindex 가 &tags 에 넣지 않기 때문이다. 그런데 파일은 정렬돼
  -- 있으므로 look -b 로 바로 찾을 수 있다 - 1.7GB 에서 이름당 0.04~0.12초,
  -- 한 셸 안에서 네 개를 잇달아 물으면 사실상 0초였다(페이지 캐시).
  -- 이게 없으면 구조체 멤버(mbox_ch 같은)는 영영 검정이다: GNU Global 은
  -- 멤버를 색인하지 않고, 이 프로젝트에는 taglist 가 볼 파일이 없다.
  local script = 'for s in ' .. table.concat(syms, ' ') ..
      '; do o=$("$SIHL_G" -d --result=ctags-x "$s" 2>/dev/null | head -1);' ..
      ' if [ -z "$o" ] && [ -n "$SIHL_SNAPS" ]; then' ..
      ' for f in $SIHL_SNAPS; do [ -r "$f" ] || continue;' ..
      ' a=$(LC_ALL=C look -b "$(printf \'%s\\t\' "$s")" "$f" 2>/dev/null | head -40);' ..
      ' [ -z "$a" ] && continue;' ..
      ' o=$(printf \'%s\\n\' "$a" | grep -m1 "#define" );' ..
      ' [ -z "$o" ] && o=$(printf \'%s\\n\' "$a" | head -1);' ..
      ' o="TAG\t$o"; break; done; fi;' ..
      ' if [ -n "$o" ]; then printf \'%s\\t%s\\n\' "$s" "$o"; fi; done'
  local argv = nice_prefix()
  vim.list_extend(argv, { 'sh', '-c', script })
  local env = db_env(root) or {}
  env = vim.tbl_extend('force', env, { SIHL_G = g })
  -- 스냅숏은 체인의 마지막 DB 에서만 본다.
  --
  -- 가까운 DB 단계에서 먼저 보면 거기서 '찾음'이 나와 버려 바깥 gtags 가
  -- 주는 더 정확한 답(정의 파일 경로)을 못 본다. 실제로 MODULE_AUTHOR 가
  -- 스냅숏의 엉뚱한 #define 으로 먼저 잡혀서, module.h 매크로인데 네이비가
  -- 아니라 초록이 됐다.
  if s.snap_ok[root] and (tonumber(cfg('ctags', 1)) or 1) ~= 0
      and vim.fn.executable('look') == 1 then
    -- 체인의 스냅숏을 전부 넘긴다. 스냅숏은 프로젝트마다 따로 있고, 찾는
    -- 심볼이 어느 프로젝트 것인지는 모른다 - 실제로 구조체 멤버는
    -- kernel/common 의 1.7GB 스냅숏에만 있는데 체인의 마지막 루트는 그
    -- 바깥이라, 바깥 것만 보면 못 찾는다.
    local list = s.snaps[root] or {}
    if #list > 0 then
      env.SIHL_SNAPS = table.concat(list, ' ')
    end
  end
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
      local hit, snap_hit = {}, {}
      if res and res.code == 0 and res.stdout then
        for line in res.stdout:gmatch('[^\n]+') do
          local name, rest = line:match('^([^\t]+)\t(.*)$')
          if name then
            if rest:sub(1, 4) == 'TAG\t' then
              snap_hit[name] = true
              -- ctags 스냅숏 한 줄: 이름 \t 경로 \t 검색패턴 ...
              --
              -- kind 필드로 판단하지 않는다. 이 설정은 --fields=+nS 라
              -- 마지막 필드가 kind 가 아니고(line:123 이 뒤에 온다), 게다가
              -- look 은 정렬 순서로 첫 줄을 주므로 MODULE_LICENSE 의 경우
              -- '#define' 이 아니라 그것을 '쓰는' 줄이 먼저 나왔다. 그래서
              -- 셸에서 '#define' 이 들어간 줄을 먼저 고르고, 여기서는
              -- gtags 쪽과 같은 규칙(검색패턴에 #define 이 있는가)을 쓴다.
              local fields = vim.split(rest:sub(5), '\t', { plain = true })
              local path = fields[2] or ''
              -- 검색 패턴이 정의가 적힌 소스 줄이다. --fields=+nS 로 만든
              -- 스냅숏은 그 필드를 '/^...$/;"' 로 끝내므로, 닫는 '/' 뒤에
              -- 무엇이 오든 받아 준다. 예전 패턴은 '/' 로 끝나야만 맞아서
              -- 여기서 늘 빈 문자열이 나왔고, 스냅숏 쪽 enum 판정이 죽어
              -- 있었다.
              local f3 = fields[3] or ''
              local pat = f3:match('^/%^?(.-)%$?/') or ''
              hit[name] = (rest:find('#define', 1, true)
                    and macro_kind(path, name, rest))
                  or (is_enum_const(name, (pat:gsub('^%s+', ''))) and 'enum')
                  or true
            else
              local path, src = rest:match('^%S+%s+%d+%s+(%S+)%s+(.*)$')
              -- 파싱이 어긋나도 path 를 nil 로 넘기지 않는다. 넘기면 경로로
              -- 정하는 네이비 규칙이 조용히 빠져 초록이 된다.
              src, path = src or rest, path or ''
              hit[name] = src:match('^%s*#%s*define')
                  and macro_kind(path, name, src)
                  or (is_enum_const(name, src) and 'enum' or true)
            end
          end
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
        -- gtags 가 못 찾은 것만 ctags 에 다시 물어본다
        local rest = {}
        for _, sym in ipairs(syms) do
          if not hit[sym] then
            rest[#rest + 1] = sym
          end
        end
        local tags = #rest > 0 and in_tags(rest, s.snap_ok[root]) or {}
        for _, sym in ipairs(syms) do
          local v = hit[sym] or tags[sym]
          if v then
            b.found[sym] = v
            -- 어디가 답했는지 적어 둔다. :SiHlIndexWhy 가 'gtags 는 모르는데
            -- 캐시는 찾았다고 한다'로 보이지 않으려면 이게 있어야 한다.
            b.how[sym] = hit[sym] and (snap_hit[sym] and 'ctags' or 'gtags') or 'taglist'
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
    pcall(repaint_ctx)
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

repaint = function(win)
  win = win or api.nvim_get_current_win()
  if not api.nvim_win_is_valid(win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  -- 일반 파일 창과 RelationView 미리보기. 편집 창과 미리보기가 서로 다른
  -- 색으로 보이면 그게 더 헷갈린다.
  if vim.bo[buf].buftype ~= ''
      and not api.nvim_buf_get_name(buf):match('RelationView%-Context$') then
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
  local roots = roots_of(buf)
  if #roots == 0 then
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
  local buckets = {}
  for i, r in ipairs(roots) do
    buckets[i] = bucket(r)
  end
  local prio = tonumber(vim.g.sihl_priority) or 200
  local decl_here = {}

  -- 체인 전체를 보고 판정한다.
  --   하나라도 알면        -> 찾음 (그 종류를 쓴다)
  --   전부 '없음'이면      -> 검정
  --   아직 안 물어본 DB 가 있으면 -> 그 DB 에 물어본다 (칠하지 않는다)
  local function verdict(name)
    local unasked
    for i, bk in ipairs(buckets) do
      local v = bk.found[name]
      if v then
        return 'found', v
      end
      if bk.missing[name] == nil and not unasked then
        unasked = i
      end
    end
    if unasked then
      return 'ask', unasked
    end
    return 'missing'
  end

  -- 선언하는 자리는 건드리지 않는다: 파랑(item 1/2)을 덮으면 안 된다
  for id, node in q:iter_captures(trees[1]:root(), buf, lo, hi) do
    local cap = q.captures[id]
    if cap:match('^si%.declaration') then
      local r1, c1 = node:range()
      decl_here[r1 .. ':' .. c1] = true
    end
  end

  -- 한 자리에 캡처가 여러 개 붙을 수 있다(@function.call 과 @constant 가
  -- 같은 이름에 함께 오는 식). 같은 자리를 두 번 칠하지 않는다.
  local done = {}
  local members_on = (tonumber(cfg('members', 1)) or 1) ~= 0
  local asked = false
  for id, node in q:iter_captures(trees[1]:root(), buf, lo, hi) do
    local cap = q.captures[id]
    local exp = OK_NODE[node:type()] and export_arg(node, buf) or false
    if (ASK_CAP[cap] or (members_on and MEMBER_CAP[cap]) or exp)
        and OK_NODE[node:type()] then
      local r1, c1, r2, c2 = node:range()
      if r1 == r2 and r1 >= lo and r1 < hi and not decl_here[r1 .. ':' .. c1]
          and not done[r1 .. ':' .. c1] then
        done[r1 .. ':' .. c1] = true
        local name = vim.treesitter.get_node_text(node, buf)
        -- 지역 변수 필터는 이름으로 거르므로 멤버에는 적용하면 안 된다.
        -- '->' 뒤의 이름은 절대 지역 변수가 아닌데, 같은 이름의 지역 변수가
        -- 그 파일 어딘가에 있으면 멤버까지 통째로 빠졌다. 실제로
        -- tcc-snd-card.c 에는 'struct tcc_dai_info_t *dai_info;' 라는 지역이
        -- 있고 'card_info->dai_info' 라는 멤버도 있어서, ctags 가 아는 그
        -- 멤버가 검정으로 남았다.
        local is_member = node:type() == 'field_identifier'
        if exp then
          -- EXPORT_SYMBOL(sym): 내보내는 그 이름. 같은 이름의 지역 변수가
          -- 있어도 이건 지역이 아니므로 아래 필터보다 먼저 칠한다.
          pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
            end_row = r2, end_col = c2,
            hl_group = 'SiExportSym', priority = prio,
          })
        elseif name and #name > 1 and not KEYWORD[name]
            and (is_member or not locals[name])
            and name:match('^[A-Za-z_][A-Za-z0-9_]*$') then
          local how, extra = verdict(name)
          if navy_name(name) then
            how, extra = 'found', 'macrokw'
          end
          -- 멤버는 이름으로 물어서는 답이 안 나온다: GNU Global 의 기본
          -- 파서가 구조체 멤버를 색인하지 않기 때문이다(tsnd.h 의 멤버
          -- 158개를 물었더니 'global -d' 가 아는 것은 0개였다). 그래서
          -- <C-]> 가 쓰는 길을 그대로 쓴다 - 베이스 변수의 타입을 풀어서
          -- 그 타입이 이 멤버를 가졌는지 본다. 갈 수 있으면 초록이다.
          if is_member and members_on and how ~= 'found'
              and _G.relationview_member_known then
            local okm, known = pcall(_G.relationview_member_known, buf,
              r1 + 1, c1, redraw_soon)
            if okm and known == true then
              how, extra = 'found', 'member'
            elseif okm and known == nil and how ~= 'ask' then
              -- 답을 기다리는 중이다. 검정으로 칠했다가 초록으로 되돌리면
              -- 화면이 깜빡이므로, 답이 올 때까지는 손대지 않는다.
              how = 'wait'
            end
          end
          if how == 'missing' then
            pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
              end_row = r2, end_col = c2,
              hl_group = 'SiJumpNone', priority = prio,
            })
          elseif how == 'found' and extra == 'macrokw' then
            -- module.h 계열 매크로: 선언처럼 읽히므로 네이비 볼드
            pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
              end_row = r2, end_col = c2,
              hl_group = 'SiMacroKw', priority = prio,
            })
          elseif how == 'found' and extra == 'fnmacro' then
            -- 함수형 매크로라도 '부르는' 자리에서만 초록이다. 괄호 없이
            -- 이름으로만 쓰면 그건 참조라 상수 매크로와 같은 빨강.
            pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
              end_row = r2, end_col = c2,
              hl_group = is_called(node) and 'SiFnMacro' or 'SiMacroRef',
              priority = prio,
            })
          elseif how == 'found' and extra == 'logmacro' then
            -- 로그 매크로: 읽을 때 함수 호출이므로 호출과 같은 초록 볼드
            pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
              end_row = r2, end_col = c2,
              hl_group = 'SiLogMacro', priority = prio,
            })
          elseif how == 'found' and extra == 'macro' then
            -- 매크로는 찾았으면 빨강. 이름만 보고는 함수와 구분되지 않아서
            -- ADD(x, 2) 가 함수 호출과 같은 초록 볼드로 나왔었다.
            pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
              end_row = r2, end_col = c2,
              hl_group = 'SiMacroRef', priority = prio,
            })
          elseif how == 'found' and extra == 'enum' then
            -- enum 요소를 쓰는 자리: 빨강. 선언하는 자리는 위 decl_here 가
            -- 이미 빼 두었으므로 여기는 '역참조'뿐이다.
            pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
              end_row = r2, end_col = c2,
              hl_group = 'SiEnumRef', priority = prio,
            })
          elseif how == 'found' and (extra == 'member'
              or CONST_CAP[cap] or MEMBER_CAP[cap]) then
            -- 찾았는데 매크로가 아니다 = enum 상수이거나 구조체 멤버다.
            --
            -- 둘 다 '아무것도 안 칠하기'로는 초록이 되지 않는다. enum 상수는
            -- nvim 기본 쿼리가 상수 매크로와 똑같이 @constant 로 잡아 빨강
            -- 으로 시작하고, 멤버는 @property 라 본문색(검정)으로 시작한다.
            -- 초록으로 올려 준다.
            pcall(api.nvim_buf_set_extmark, buf, NS, r1, c1, {
              end_row = r2, end_col = c2,
              hl_group = 'SiJumpFound', priority = prio,
            })
          elseif how == 'ask' and not navy_name(name) then
            local r = roots[extra]
            s.want[r] = s.want[r] or {}
            s.want[r][name] = true
            s.snap_ok[r] = (extra == #roots)
            if s.snap_ok[r] and not s.snaps[r] then
              local list = {}
              for _, rr in ipairs(roots) do
                if _G.autoindex_ctags_file then
                  local okc, snap = pcall(_G.autoindex_ctags_file, rr)
                  if okc and snap and snap ~= '' and uv.fs_stat(snap) then
                    list[#list + 1] = snap
                  end
                end
              end
              s.snaps[r] = list
            end
            asked = true
          end
        end
      end
    end
  end
  if asked then
    local n = tonumber(cfg('batch', 2)) or 2
    for _ = 1, n do
      drain()
    end
  end
end

-- 미리보기 창이 떠 있으면 그쪽도 칠한다
repaint_ctx = function()
  if not _G.relationview_ctx_win then
    return
  end
  local ok, cw = pcall(_G.relationview_ctx_win)
  if ok and cw and api.nvim_win_is_valid(cw) then
    pcall(repaint, cw)
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
    pcall(repaint_ctx)
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
  s.cache, s.want, root_cache, chain_cache = {}, {}, {}, {}
  s.snap_ok, s.snaps = {}, {}
  s.off, s.fails, prog_cache = nil, 0, nil
  -- 멤버 판정은 relationview 쪽 캐시에 들어 있다
  if _G.relationview_member_cache_clear then
    pcall(_G.relationview_member_cache_clear)
  end
  vim.notify('SiHlIndex: 캐시를 비웠습니다')
  schedule()
end, { desc = '색인 판정 캐시 비우기' })

-- :SiHlIndexWhy - 커서 아래(또는 인자로 준) 이름이 왜 그 색인지 한 번에 본다.
--
-- '점프는 되는데 검정이다'는 신고가 반복됐는데, 원인이 매번 달랐다: 바깥
-- DB 에 물어서, 세션이 옛 캐시를 들고 있어서, 정의 파일이 preset 밖이라
-- 색인에 진짜로 없어서. 어느 쪽인지는 한 번 물어보면 끝나는 일이라
-- 명령으로 만들어 둔다.
-- 검정으로 나온 심볼의 '정의가 있는 파일'을 찾아 색인에 넣는다.
--
-- projectfiles 에 이미 있는 기구를 부른다: 소스를 훑어 그 심볼을 정의한
-- 파일을 찾고, preset 에 넣고, 그 파일만 색인한 뒤 재색인한다.
--
-- 자동으로 하되 '커서가 멈춘 그 심볼 하나'만 한다. 화면에 보이는 검정을
-- 전부 자동으로 처리하면 한 화면에 수십 번의 소스 전체 검색이 된다 -
-- 커널 트리에서 한 번이 1초를 훌쩍 넘고, 이건 60코어를 840명이 쓰는
-- 서버다. 한 번에 하나, 최소 간격을 두고, 같은 심볼은 다시 시도하지 않는다.
--
--   let g:sihl_index_autoadd = 1     커서가 멈추면 자동으로 (기본 0)
--   let g:sihl_index_autoadd_gap = 5 최소 간격 초 (기본 5)
--   :SiHlIndexAdd [심볼]             지금 이 심볼로 직접
local function forget(name)
  for _, b in pairs(s.cache) do
    b.missing[name] = nil
    b.found[name] = nil
  end
end

local adding = false
local last_add = 0
local tried = {}

-- 이 심볼을 이미 어느 색인이 알고 있나
local function already(sym)
  for _, r in ipairs(roots_of(api.nvim_get_current_buf())) do
    local b = bucket(r)
    if b.found[sym] then
      return r, b.how[sym]
    end
  end
  return nil
end

local function add_for(sym, quiet)
  if adding or not sym or not sym:match('^[A-Za-z_][A-Za-z0-9_]*$') then
    return
  end
  -- 이미 찾아지는 심볼이면 아무것도 하지 않는다.
  --
  -- 찾아지는데도 검색을 돌리면 소스 전체를 훑고, 그 결과가 preset 에
  -- 들어간다. platform_device 로 실제로 그렇게 됐다: DB 가 이미
  -- include/linux/platform_device.h 를 알고 있는데도 검색이 돌아
  -- 'struct platform_device;' 라고만 적힌 전방 선언 헤더 5개
  -- (arch/arm/mach-s3c/cpu.h, drivers/clk/qcom/common.h ...)가 색인 목록에
  -- 들어갔다. 정의가 아니라 언급일 뿐인 파일들이다.
  local r, how = already(sym)
  if r then
    if not quiet then
      vim.notify(("'%s' 는 이미 색인에 있습니다 (%s, %s) - 추가하지 않습니다")
        :format(sym, vim.fn.fnamemodify(r, ':~'), how or '?'))
    end
    return
  end
  if not _G.projectfiles_add_for_symbol_async then
    if not quiet then
      vim.notify('projectfiles 가 없습니다', vim.log.levels.WARN)
    end
    return
  end
  adding = true
  last_add = os.time()
  tried[sym] = true
  if not quiet then
    vim.notify(("'%s' 를 정의한 파일을 찾는 중..."):format(sym))
  end
  local ok = pcall(_G.projectfiles_add_for_symbol_async, sym, function(n)
    adding = false
    if n and n > 0 then
      forget(sym)
      vim.schedule(function()
        pcall(repaint)
        pcall(repaint_ctx)
      end)
    elseif not quiet then
      vim.notify(("'%s' 를 정의한 파일을 찾지 못했습니다"):format(sym),
        vim.log.levels.WARN)
    end
  end)
  if not ok then
    adding = false
  end
end

api.nvim_create_user_command('SiHlIndexAdd', function(o)
  add_for(o.args ~= '' and o.args or vim.fn.expand('<cword>'), false)
end, { nargs = '?', desc = '이 심볼을 정의한 파일을 색인에 넣는다' })

-- 자동: 커서가 검정 심볼 위에서 멈췄을 때만
api.nvim_create_autocmd('CursorHold', {
  group = group,
  callback = function()
    if (tonumber(cfg('autoadd', 0)) or 0) == 0 or adding then
      return
    end
    local gap = tonumber(cfg('autoadd_gap', 5)) or 5
    if os.time() - last_add < gap then
      return
    end
    local ft = vim.bo.filetype
    if ft ~= 'c' and ft ~= 'cpp' then
      return
    end
    local sym = vim.fn.expand('<cword>')
    if not sym:match('^[A-Za-z_][A-Za-z0-9_]*$') or KEYWORD[sym] or tried[sym] then
      return
    end
    -- 정말 '없음'으로 판정된 것만
    local miss = false
    for _, r in ipairs(roots_of(api.nvim_get_current_buf())) do
      local b = bucket(r)
      if b.found[sym] then
        return
      end
      if b.missing[sym] then
        miss = true
      end
    end
    if miss then
      add_for(sym, true)
    end
  end,
})

api.nvim_create_user_command('SiHlIndexWhy', function(o)
  local sym = o.args ~= '' and o.args or vim.fn.expand('<cword>')
  local buf = api.nvim_get_current_buf()
  local roots = roots_of(buf)
  local out = { ('심볼: %s'):format(sym) }
  if #roots == 0 then
    out[#out + 1] = '이 파일 위에 GTAGS 가 없습니다 (색인되지 않은 트리)'
    vim.notify(table.concat(out, '\n'), vim.log.levels.WARN)
    return
  end
  local g = prog()
  for i, root in ipairs(roots) do
    local b = bucket(root)
    local cached = b.found[sym] and ('찾음' .. (
        b.found[sym] == 'macro' and ' (매크로)'
        or b.found[sym] == 'macrokw' and ' (매크로/네이비)' or ''))
        or (b.missing[sym] and '없음' or '아직 안 물어봄')
    local live = '(global 없음)'
    if g then
      local r = vim.system({ g, '--result=ctags-x', '-d', sym },
        { cwd = root, text = true, env = db_env(root) }):wait(4000)
      live = (r and r.stdout and r.stdout:match('[^\n]+')) or '(정의 없음)'
    end
    local list = root .. '/' .. (vim.g.gtags_objdir or '.tags') .. '/files'
    local n = 0
    if uv.fs_stat(list) then
      for _ in io.lines(list) do n = n + 1 end
    end
    out[#out + 1] = ('DB %d: %s  [목록 %s]'):format(i, vim.fn.fnamemodify(root, ':~'),
      n > 0 and (n .. '개') or 'auto')
    out[#out + 1] = ('     캐시=%s%s  gtags=%s'):format(cached,
      b.how[sym] and (' (' .. b.how[sym] .. ')') or '', live:sub(1, 60))
    -- ctags 스냅숏도 직접 물어본다. 여기를 빼먹어서 'gtags 는 모르는데
    -- 캐시는 찾았다'는 모순된 화면이 나왔다 - 답한 것은 스냅숏이었다.
    if _G.autoindex_ctags_file and vim.fn.executable('look') == 1 then
      local okc, snap = pcall(_G.autoindex_ctags_file, root)
      if okc and snap and snap ~= '' and uv.fs_stat(snap) then
        local r2 = vim.system({ 'sh', '-c',
          'LC_ALL=C look -b "$(printf \'%s\\t\' "$1")" "$2" 2>/dev/null | head -1',
          '_', sym, snap }, { text = true }):wait(4000)
        local hitline = r2 and r2.stdout and r2.stdout:match('[^\n]+')
        out[#out + 1] = ('     ctags=%s'):format(
          hitline and hitline:gsub('\t', ' '):sub(1, 60) or '(없음)')
      end
    end
  end
  -- 멤버는 이름이 아니라 '베이스 변수의 타입'으로 푼다. 커서가 멤버 위에
  -- 있으면 그 길의 결과도 같이 보여 준다 - 안 그러면 'gtags 도 ctags 도
  -- 모른다는데 왜 초록이냐'로 읽힌다.
  if _G.relationview_member_known then
    local pos = api.nvim_win_get_cursor(0)
    local okm, known = pcall(_G.relationview_member_known, buf, pos[1], pos[2])
    if okm and known ~= false then
      out[#out + 1] = ('멤버    : %s (베이스 변수의 타입으로 푼 결과)'):format(
        known == true and '찾음' or '알아보는 중 - 잠시 뒤 다시 물어보세요')
    end
  end
  if #vim.fn.tagfiles() > 0 then
    local save = vim.o.tagcase
    vim.o.tagcase = 'match'
    local t = vim.fn.taglist('^' .. sym .. '$')
    vim.o.tagcase = save
    out[#out + 1] = ('ctags   : %s'):format(
      (t and #t > 0) and ((t[1].filename or '?') .. ' (kind=' .. (t[1].kind or '?') .. ')')
        or '(없음)')
  end
  out[#out + 1] = 'preset 모드면 목록 밖 파일의 심볼은 색인에 없습니다'
      .. ' (\\fa 로 넣고 :ProjectFilesReindex)'
  if s.off then
    out[#out + 1] = '중지됨: ' .. s.off
  end
  vim.notify(table.concat(out, '\n'))
end, { nargs = '?', desc = '이 심볼이 왜 그 색인지 설명' })

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
