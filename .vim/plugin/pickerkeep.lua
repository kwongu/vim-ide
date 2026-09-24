-- pickerkeep.lua - 텔레스코프 창을 닫지 않고 목록을 갈아 끼운다
--
-- 북마크 창(<Esc>d), \fo·F3·\fx(^d, <Esc>d, \fx 의 <CR>)에서 지운 뒤 창은
-- 그대로 두고 목록만 다시 읽어 바꾼다. 친 글자는 그대로 둔다.
--
--   _G.vimide_picker_keep(picker, finder, opts)
--     opts.title   프롬프트 제목 (개수가 바뀌었으면)
--     opts.key     항목 -> 새 목록에서 다시 찾을 열쇠 글자
--                  (기본: value 가 글자면 value, 아니면 ordinal)
--   _G.vimide_picker_busy(picker)   목록이 아직 따라오지 않았으면 true
--   _G.vimide_picker_track(picker)  바쁨을 재기 시작한다 (창을 열 때 한 번)
--   _G.vimide_picker_ready(picker, fn)  바쁘지 않으면 곧장, 바쁘면 목록이
--                                    따라온 뒤에 fn() - 여는 키(<CR>)용
--
-- 선택은 '그 자리'에 둔다: 커서 줄이 새 목록에 남아 있으면 그 줄, 없어졌으면
-- 그 자리를 채우며 올라온 줄. 몇 번째인지가 아니라 열쇠로 찾는다 - \fx 에서
-- 디렉터리 항목을 지우면 그 아래 파일 항목도 같이 빠지고, <Tab> 으로 다른
-- 줄들을 골라 지우면 커서 앞 번째가 여럿 빠진다. 번째로 찾으면 그만큼
-- 선택이 밀려났다 (tmux 화면 실측: f07 -> f09, 반대 심문: 디렉터리 항목).
--
-- 무엇이 빠졌는지는 '새 목록에 없는 것'으로 안다. 지우라고 한 것을 빠진
-- 것으로 치면, 확인 창에서 취소했거나 이미 없던 항목일 때도 선택이 다음
-- 줄로 넘어가서, \fx 의 다음 <CR> 이 고르지도 않은 항목을 지웠다 (반대 심문).
--
-- 바쁨: 목록이 화면의 프롬프트를 아직 따라오지 않은 동안은 지우기·열기 키를
-- 받지 않는다. 두 경우다.
--   1) 방금 지워서 갈아 끼우는 중 - refresh 는 찾기를 걸어 둘 뿐이고 새 목록과
--      선택은 한 박자 뒤에 들어온다. 그 사이의 선택은 방금 지운 항목이라,
--      빨리 친 두 번째 d 가 '목록에 없습니다'로 헛돌고 <CR> 은 지운 파일을
--      열었다.
--   2) 친 글자로 거르는 중 - 글자와 ^d 가 한꺼번에 오면(빠른 손, 느린 SSH)
--      nvim 은 쌓인 키를 먼저 처리해서, 새 글자로 거르기 전의 선택(이제는
--      걸러져 보이지 않는 항목)이 지워졌다.
-- 둘 다 '마지막으로 다 걸러진 프롬프트'가 지금 프롬프트와 다른가로 잰다.
-- 지우는 키는 그동안 버리고(빨리 친 dd 는 하나만 지운다), 여는 키(<CR>)는
-- 목록이 따라온 뒤에 실행한다 - 이름을 치자마자 <CR> 을 치는 손버릇에서
-- <CR> 이 먹히지 않으면 고장으로 보인다.
-- 갈아 끼우는 쪽은 따로 표시해 두고, 완료 콜백이 오지 않는 경우(창이
-- 닫혔다 등)를 위해 3초 뒤에도 푼다.

if vim.g.loaded_vimide_pickerkeep then
  return
end
vim.g.loaded_vimide_pickerkeep = 1

local gen = 0

local function default_key(e)
  if type(e) ~= 'table' then
    return nil
  end
  if type(e.value) == 'string' then
    return e.value
  end
  return type(e.ordinal) == 'string' and e.ordinal or nil
end

-- 목록의 항목을 차례로. cap 을 주면 거기서 멈춘다.
local function each_entry(picker, fn, cap)
  local m = picker.manager
  if not m then
    return
  end
  local i = 0
  for e in m:iter() do
    i = i + 1
    if (cap and i > cap) or fn(i, e) == false then
      return
    end
  end
end

-- 고를 수 있는 줄의 끝. telescope 의 스크롤 한도(__scrolling_limit, 기본
-- 250)다 - 창 높이가 아니다. 그 너머 항목은 목록에 있어도 고를 수 없다.
local function pick_cap(picker)
  return tonumber(picker.max_results) or 250
end

-- 완료 콜백을 한 번(fn 이 true 를 돌려줄 때까지) 쓰고 뗀다.
--
-- 떼기는 한 박자 뒤에 한다. telescope 는 콜백 목록을 ipairs 로 돌며 부르는데,
-- 도는 도중에 제 자리를 빼면 바로 뒤 콜백이 한 칸 당겨져 그 차례를 건너뛴다
-- (선택 되돌리기가 빠지면서 '<CR> 은 목록이 따라온 뒤에'가 불리지 않았다).
local function once(picker, fn)
  local dead = false
  local function cb(p)
    if dead then
      return
    end
    if fn(p) then
      dead = true
      vim.schedule(function()
        for i, f in ipairs(p._completion_callbacks or {}) do
          if f == cb then
            table.remove(p._completion_callbacks, i)
            break
          end
        end
      end)
    end
  end
  picker:register_completion_callback(cb)
end

local function current_line()
  local ok, st = pcall(require, 'telescope.state')
  return ok and st.get_global_key('current_line') or nil
end

function _G.vimide_picker_track(picker)
  if not picker or picker._vimide_tracked then
    return
  end
  picker._vimide_tracked = true
  -- 지금 걸러진(걸러지는 중인) 프롬프트로 시작한다
  picker._vimide_done = current_line()
  picker:register_completion_callback(function(p)
    -- 완료는 찾기가 끝난 직후, 다음 찾기가 시작되기 전에 불린다. 그때의
    -- current_line 이 방금 다 걸러진 프롬프트다.
    p._vimide_done = current_line()
  end)
end

function _G.vimide_picker_busy(picker)
  if not picker then
    return false
  end
  if picker._vimide_busy ~= nil then
    return true
  end
  if not picker._vimide_tracked then
    _G.vimide_picker_track(picker)
    return false
  end
  local ok, now = pcall(picker._get_prompt, picker)
  return ok and picker._vimide_done ~= nil and now ~= picker._vimide_done
end

function _G.vimide_picker_ready(picker, fn)
  if not _G.vimide_picker_busy(picker) then
    return fn()
  end
  -- 선택이 새 목록으로 옮겨진 뒤에 부른다: 갈아 끼우는 쪽의 콜백이 먼저
  -- 등록돼 있으면 같은 차례에 앞서 돈다. 한 박자 더 미뤄 확실히 뒤에 둔다.
  once(picker, function(p)
    if _G.vimide_picker_busy(p) then
      return false -- 아직 (거르기가 또 걸렸다)
    end
    vim.schedule(fn)
    return true
  end)
end

function _G.vimide_picker_keep(picker, finder, opts)
  opts = opts or {}
  local key = opts.key or default_key
  _G.vimide_picker_track(picker)
  -- 선택 후보: 커서 줄부터 뒤로(그 자리를 채우러 올라올 줄들), 그다음
  -- 앞으로. 한도(250) 너머까지 본다 - 한도의 마지막 줄을 지우면 그 너머
  -- 항목이 그 자리로 올라온다 (반대 심문: 한 줄 위로 튀었다).
  local idx = picker:get_index(picker:get_selection_row())
  local after, before = {}, {}
  each_entry(picker, function(i, e)
    local k = key(e)
    if k then
      if i >= idx then
        after[#after + 1] = k
      else
        table.insert(before, 1, k)
      end
    end
  end)
  local rank, r = {}, 0 -- 열쇠 -> 우선순위 (1 이 먼저)
  for _, list in ipairs({ after, before }) do
    for _, k in ipairs(list) do
      if not rank[k] then
        r = r + 1
        rank[k] = r
      end
    end
  end

  gen = gen + 1
  local my = gen
  picker._vimide_busy = my
  local function unbusy()
    if picker._vimide_busy == my then
      picker._vimide_busy = nil
    end
  end
  local function cb(p)
    unbusy()
    local best, best_rank, n = nil, math.huge, 0
    each_entry(p, function(i, e)
      n = i
      local k = key(e)
      local rk = k and rank[k]
      if rk and rk < best_rank then
        best, best_rank = i, rk
      end
    end, pick_cap(p))
    if best then
      p:set_selection(p:get_row(best))
    elseif n > 0 then
      p:set_selection(p:get_row(math.min(idx, n)))
    end
    return true
  end
  if opts.title then
    pcall(function() picker.layout.prompt.border:change_title(opts.title) end)
  end
  once(picker, cb)
  vim.defer_fn(unbusy, 3000)
  picker:refresh(finder, { reset_prompt = false })
end
