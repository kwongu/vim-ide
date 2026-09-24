-- fitmsg.lua - 화면 폭을 넘는 한 줄 알림이 Press ENTER 를 띄우지 않게
--
--   _G.vimide_notify(msg, level)   vim.notify 와 똑같이 부른다
--
-- 한 줄 알림이 화면 폭을 넘으면 Press ENTER 가 뜨고, 그 뒤에 친 키(피커의 다음
-- <CR>, 확인 창 뒤의 키)를 그 프롬프트가 먹는다. 경로가 긴 트리(Yocto 빌드
-- 디렉터리, 깊은 SDK)에서 그랬다 - \fx 의 '제거: ... → <루트>/.tags [preset]',
-- 파일을 열자마자 뜨는 'autoindex: indexing <루트> …' (맥 시험장의 긴 경로에서
-- 실측: \fx 를 열어도 첫 <CR> 두 번을 이 프롬프트가 먹었다).
--
-- 폭을 넘으면 :messages 에는 원래 글자를 그대로 남기고, 화면에만 줄인 글자를
-- 보인다 - 뒤에 붙은 힌트(g:autoindex_tags_max_bytes, 건너뛴 경로, 대상 .tags)
-- 는 :messages 에서 다시 볼 수 있어야 한다 (반대 심문: 줄인 글자만 남기면 한 번만
-- 뜨는 경고의 해법이 영영 사라졌다).
--   1. 원래 글자를 nvim_echo(_truncate) 로 - 기록에 남고, 화면에서는 nvim 이
--      Press ENTER 없이 끝을 자른다 (nvim 이 사용 중단 경고에 쓰는 길)
--   2. 곧바로 redraw 뒤 줄인 글자를 기록 없이 덮어 쓴다 - 둘을 redraw 없이 잇달아
--      쓰면 두 줄이 되어 Press ENTER 가 뜬다 (실측)
-- 줄이는 법: 경로('/'·'~/' 로 시작하는 낱말)를 가장 많이 줄어드는 것부터 하나씩
-- pathshorten 해서 맞으면 멈춘다. 그래도 넘으면 가운데를 '…' 로 자른다 - 앞(무엇을)
-- 과 뒤(어디로·힌트)가 남는다. 여러 줄짜리는 일부러 그런 것이라 그대로 둔다.
-- 쓰는 곳: projectfiles.lua, autoindex.lua 의 notify().

if vim.g.loaded_vimide_fitmsg then
  return
end
vim.g.loaded_vimide_fitmsg = 1

local api = vim.api
local levels = vim.log.levels
-- 알림 플러그인(nvim-notify 등)이 vim.notify 를 바꿨으면 그쪽에 맡긴다 - 그런 것은
-- 긴 글자를 제 창에 싼다
local builtin = vim.notify

local function width(s)
  return vim.fn.strdisplaywidth(s)
end

-- 경로 낱말을 줄이는 이득이 큰 것부터 하나씩. 'GTAGS/GRTAGS/GPATH' 처럼
-- '/' 로 시작하지 않는 낱말은 경로로 치지 않는다 (반대 심문: 'GTAGS/G/GPATH').
local function shorten_paths(msg, room)
  local parts, paths, pos = {}, {}, 1
  for s, tok, e in msg:gmatch('()(%S+)()') do
    parts[#parts + 1] = msg:sub(pos, s - 1)
    pos = e
    local lead, path, trail = tok:match('^([%(%[\'"]*)(.-)([%]%)\'",:;]*)$')
    local short = path and (path:sub(1, 1) == '/' or path:sub(1, 2) == '~/') and vim.fn.pathshorten(path)
    if short and short ~= path then
      parts[#parts + 1] = lead
      parts[#parts + 1] = path
      paths[#paths + 1] = { idx = #parts, short = short, gain = width(path) - width(short) }
      parts[#parts + 1] = trail
    else
      parts[#parts + 1] = tok
    end
  end
  parts[#parts + 1] = msg:sub(pos)
  table.sort(paths, function(a, b)
    return a.gain > b.gain
  end)
  local w = width(msg)
  for _, p in ipairs(paths) do
    if w <= room then
      break
    end
    parts[p.idx] = p.short
    w = w - p.gain
  end
  return table.concat(parts)
end

-- 폭 limit 안에 드는 가장 긴 앞(from_end=false) 또는 뒤(true) 글자 수 (maxk 까지)
-- - 이분 탐색이라 아주 긴 알림에서도 몇 번만 잰다
local function fit_chars(s, n, maxk, limit, from_end)
  local lo, hi = 0, maxk
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    local part = from_end and vim.fn.strcharpart(s, n - mid, mid) or vim.fn.strcharpart(s, 0, mid)
    if width(part) <= limit then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo
end

local function fit(msg, room)
  local short = shorten_paths(msg, room)
  if width(short) <= room then
    return short
  end
  local n = vim.fn.strchars(short)
  local headw = math.floor((room - 1) / 2)
  local head = fit_chars(short, n, n, headw, false)
  local tail = fit_chars(short, n, n - head, room - 1 - width(vim.fn.strcharpart(short, 0, head)), true)
  return vim.fn.strcharpart(short, 0, head) .. '…' .. vim.fn.strcharpart(short, n - tail, tail)
end

function _G.vimide_notify(msg, level)
  level = level or levels.INFO
  if type(msg) ~= 'string' or msg:find('\n', 1, true) or vim.notify ~= builtin or vim.in_fast_event() then
    return vim.notify(msg, level)
  end
  local room = (tonumber(vim.v.echospace) or 80) - 1
  if width(msg) <= room then
    return vim.notify(msg, level)
  end
  -- vim.notify 와 같은 모양 (_core/editor.lua) + _truncate
  local hl = level == levels.WARN and 'WarningMsg' or nil
  local ok = pcall(api.nvim_echo, { { msg, hl } }, true, { err = level == levels.ERROR, _truncate = true })
  if not ok then
    -- _truncate 가 없어진 nvim: 줄인 글자만이라도 (Press ENTER 는 막는다)
    return vim.notify(room >= 20 and fit(msg, room) or msg, level)
  end
  if room < 20 then
    return
  end
  pcall(vim.cmd, 'redraw')
  api.nvim_echo({ { fit(msg, room), level == levels.ERROR and 'ErrorMsg' or hl } }, false, {})
end
