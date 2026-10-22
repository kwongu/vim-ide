-- plenaryguard.lua - plenary.strings 의 글자 폭을 창과 무관하게, truncate 를 끝나게 (nvim 전용)
--
-- plenary.strings.strdisplaywidth 는 linetabsize_col(ffi) 이나 strdisplaywidth() 를 쓴다.
-- nvim 0.12 는 거기에 '지금 창'의 linebreak·breakindent 몫까지 더한다. 그래서 wrap+linebreak
-- 창(F1 의 README·정의 보기, .vimrc 의 글 창)에서 피커를 열면 telescope 테두리 제목의
-- truncate 가 '통째 폭 > len' 으로 들어가는데 글자 하나씩 더한 폭은 len 을 못 넘어,
-- 글자가 다 떨어진 뒤에도 빈 글자를 더하며 영영 돈다 (Q01 - 140x40, README 보기 탭에서
-- F12 다음 F3: nvim 이 CPU 100% 로 멈추고 키도 RPC 도 안 받는다. 저장 안 한 것을 잃는다).
-- 모든 피커(F1 F3 \f* ...)가 같은 길을 지난다.
--
-- plugged 는 건드리지 않고, plenary.strings 를 처음 부를 때(package.preload) 두 가지를 바꾼다:
--   * strdisplaywidth: 창과 무관한 폭 - 출력 가능한 ASCII 는 #str, 그 밖은 nvim_strwidth,
--     탭은 tabstop 으로 펼친다. fast event 안에서는 api 를 못 불러 원래 함수 그대로
--   * truncate: 원래와 같은 일, 단 도는 횟수를 글자 바이트 수로 묶는다 (폭 계산이 어긋나도
--     끝난다)
-- 모듈이 이미 불렸으면 그 자리에서 바꾼다 - vim-ide 는 .vimrc 의 telescope 설정이 먼저 부른다 (시작 비용
-- 0.1ms 안쪽). 그 전에 잡아 둔 truncate(telescope.utils)는 원래 것이지만 폭을 표(S.strdisplaywidth)에서
-- 찾아 쓰므로 그것도 끝난다.

if vim.g.loaded_vimide_plenaryguard then
  return
end
vim.g.loaded_vimide_plenaryguard = 1

local NAME = 'plenary.strings'

local function patch(S)
  if type(S) ~= 'table' or S._vimide_guard then
    return S
  end
  S._vimide_guard = true
  local api = vim.api
  local orig_sdw = S.strdisplaywidth

  S.strdisplaywidth = function(str, col)
    str = tostring(str)
    -- 흔한 경우: 출력 가능한 ASCII 만 - 시작 칸과 무관하게 바이트 수
    if not str:find('[^\32-\126]') then
      return #str
    end
    if vim.in_fast_event() then
      return orig_sdw(str, col)
    end
    if not str:find('\t', 1, true) then
      return api.nvim_strwidth(str)
    end
    -- 탭: col 칸에서 시작해 tabstop 으로 펼친다 (원래 linetabsize_col 처럼)
    local ts = api.nvim_get_option_value('tabstop', {})
    if ts < 1 then
      ts = 8
    end
    col = col or 0
    local w = col
    for seg, tab in str:gmatch('([^\t]*)(\t?)') do
      w = w + api.nvim_strwidth(seg)
      if tab ~= '' then
        w = w + ts - (w % ts)
      end
    end
    return w - col
  end

  -- plenary 의 local truncate 와 같다. 'while true' 만 횟수 있는 for 로
  local function trunc(str, len, dots, direction)
    if S.strdisplaywidth(str) <= len then
      return str
    end
    local start = direction > 0 and 0 or str:len()
    local current = 0
    local result = ''
    local len_of_dots = S.strdisplaywidth(dots)
    local function concat(a, b, dir)
      if dir > 0 then
        return a .. b
      end
      return b .. a
    end
    -- 뒤에서 자르면 start 가 바이트 수에서 시작해 빈 글자를 몇 번 지난다: 바이트 수 + 2 면 넉넉
    for _ = 0, #str + 1 do
      local part = S.strcharpart(str, start, 1)
      current = current + S.strdisplaywidth(part)
      if (current + len_of_dots) > len then
        return concat(result, dots, direction)
      end
      result = concat(result, part, direction)
      start = start + direction
    end
    return result
  end

  S.truncate = function(str, len, dots, direction)
    str = tostring(str)
    dots = dots or '…'
    direction = direction or 1
    if direction ~= 0 then
      return trunc(str, len, dots, direction)
    end
    if S.strdisplaywidth(str) <= len then
      return str
    end
    local len1 = math.floor((len + S.strdisplaywidth(dots)) / 2)
    local s1 = trunc(str, len1, dots, 1)
    local len2 = len - S.strdisplaywidth(s1) + S.strdisplaywidth(dots)
    local s2 = trunc(str, len2, dots, -1)
    return s1 .. s2:sub(dots:len() + 1)
  end
  return S
end

if package.loaded[NAME] ~= nil then
  patch(package.loaded[NAME])
  return
end

-- require 가 처음 부를 때: 진짜 모듈을 나머지 loader 로 찾아 불러 고친 뒤 돌려준다
-- (preload 안에서 require 를 다시 부르면 '도는 require' 오류라 loader 를 직접 돈다)
package.preload[NAME] = function(name)
  package.preload[name] = nil
  local errs = {}
  local loaders = package.loaders or package.searchers
  for i = 2, #loaders do
    local f = loaders[i](name)
    if type(f) == 'function' then
      return patch(f(name))
    elseif type(f) == 'string' then
      errs[#errs + 1] = f
    end
  end
  error(("module '%s' not found:%s"):format(name, table.concat(errs)), 2)
end
