-- vimideperf.lua - 오래 띄운 nvim 이 느려지지 않게: 진단(:VimIdePerf)과 뒷정리
--
-- :VimIdePerf   지금 이 nvim 의 값을 보여 준다 (읽기만 한다)
--   tabline / statusline 한 번 그리는 ms (그 자리에서 여러 번 재어 가운데 값),
--   열린(listed) 버퍼 수, uv 핸들(종류별 - 끝났는데 안 닫힌 프로세스, 멈춘 채 남은
--   타이머, 도는 타이머), 메모리(RSS, Lua 힙), 이 nvim 을 띄운 지 얼마나.
--   '오래 띄웠더니 느리다' 싶으면 먼저 이것을 본다 (README 'Long sessions').
--   버퍼 수가 늘어도 tabline 이 그대로여야 하고, 끝났는데 안 닫힌 프로세스와 도는
--   타이머는 쉬는 동안 늘지 않아야 한다.
--
-- telescope: 피커를 열 때마다 생기는 타이머를 닫는다
--   pickers.lua 는 피커를 열 때마다 결과 수 표시를 늦추려고 debounce.throttle_leading
--   으로 uv 타이머를 하나 만들고 닫지 않는다 (그 함수의 설명에 'timer.close() 를
--   부르지 않으면 샌다' 라고 써 두고 돌려받은 타이머를 버린다). F3·\f* 를 열 때마다
--   하나씩 nvim 이 끝날 때까지 남았다. 그 피커의 프롬프트 버퍼가 없어지면 닫는다.
--   닫은 뒤 늦게 도착한 결과가 그 함수를 부르면 아무 일도 하지 않는다 (닫힌 타이머를
--   다시 켜면 오류다 - 그 피커는 이미 닫혀 보여 줄 곳도 없다).

if vim.g.loaded_vimide_perf then
  return
end
vim.g.loaded_vimide_perf = 1

local api = vim.api
local uv = vim.uv or vim.loop
local started = uv.hrtime()

-- telescope 피커의 throttle 타이머 ----------------------------------------
do
  local ok, db = pcall(require, 'telescope.debounce')
  if ok and type(db) == 'table' and type(db.throttle_leading) == 'function'
      and not db._vimide_orig_throttle_leading then
    local orig = db.throttle_leading
    db._vimide_orig_throttle_leading = orig
    db.throttle_leading = function(fn, ms)
      local wrapped, timer = orig(fn, ms)
      local dead = false
      local function close()
        if dead then
          return
        end
        dead = true
        if timer and not timer:is_closing() then
          pcall(timer.stop, timer)
          pcall(timer.close, timer)
        end
      end
      -- find() 가 끝나면 지금 창이 그 피커의 프롬프트다. 그 버퍼가 없어질 때 닫는다
      -- (프롬프트는 bufhidden=wipe). 프롬프트를 못 찾으면 예전처럼 그냥 둔다.
      vim.schedule(function()
        local buf = api.nvim_get_current_buf()
        if vim.bo[buf].filetype ~= 'TelescopePrompt' then
          return
        end
        api.nvim_create_autocmd('BufWipeout', {
          buffer = buf,
          once = true,
          callback = function()
            vim.schedule(close)
          end,
        })
      end)
      return function(...)
        if dead then
          return
        end
        return wrapped(...)
      end, timer
    end
  end
end

-- :VimIdePerf --------------------------------------------------------------
local function median_ms(f, n)
  local t = {}
  for i = 1, n do
    local a = uv.hrtime()
    f()
    t[i] = (uv.hrtime() - a) / 1e6
  end
  table.sort(t)
  return t[math.floor((n + 1) / 2)]
end

local function handles()
  local by = {}
  uv.walk(function(h)
    local ty = h:get_type()
    local c = by[ty] or { all = 0, active = 0, closing = 0 }
    by[ty] = c
    c.all = c.all + 1
    if h:is_closing() then
      c.closing = c.closing + 1
    elseif h:is_active() then
      c.active = c.active + 1
    end
  end)
  return by
end

local function perf()
  local lines = {}
  local function add(s)
    lines[#lines + 1] = s
  end
  local up = (uv.hrtime() - started) / 1e9
  add(('VimIdePerf  띄운 지 %dh%02dm  RSS %.0f MB  Lua %.1f MB'):format(
    math.floor(up / 3600), math.floor(up % 3600 / 60),
    (uv.resident_set_memory() or 0) / 1048576, collectgarbage('count') / 1024))

  local listed = #vim.fn.getbufinfo({ buflisted = 1 })
  local tl = vim.o.tabline
  if tl ~= '' and vim.o.showtabline > 0 then
    local ok, ms = pcall(median_ms, function()
      api.nvim_eval_statusline(tl, { use_tabline = true })
    end, 9)
    add(('  tabline     %s   열린 버퍼 %d개'):format(
      ok and ('%6.2f ms'):format(ms) or '   (오류)', listed))
  else
    add(('  tabline        -       열린 버퍼 %d개'):format(listed))
  end
  local win = api.nvim_get_current_win()
  local stl = vim.wo[win].statusline
  if stl == '' then
    stl = vim.o.statusline
  end
  if stl ~= '' then
    local ok, ms = pcall(median_ms, function()
      api.nvim_eval_statusline(stl, { winid = win })
    end, 9)
    add(('  statusline  %s   이 창'):format(ok and ('%6.2f ms'):format(ms) or '   (오류)'))
  end

  local by = handles()
  local p = by.process or { all = 0, active = 0, closing = 0 }
  local t = by.timer or { all = 0, active = 0, closing = 0 }
  add(('  uv process  %d개 - 끝났는데 안 닫힌 것 %d'):format(
    p.all, p.all - p.active - p.closing))
  add(('  uv timer    %d개 - 도는 것 %d, 멈춘 채 남은 것 %d'):format(
    t.all, t.active, t.all - t.active - t.closing))
  local rest = {}
  for ty, c in pairs(by) do
    if ty ~= 'process' and ty ~= 'timer' then
      rest[#rest + 1] = ('%s %d'):format(ty, c.all)
    end
  end
  table.sort(rest)
  if #rest > 0 then
    add('  uv 그 밖     ' .. table.concat(rest, ', '))
  end
  api.nvim_echo({ { table.concat(lines, '\n') } }, true, {})
end

api.nvim_create_user_command('VimIdePerf', perf,
  { desc = 'tabline/statusline 그리기 ms, 버퍼 수, uv 핸들, 메모리 (읽기만)' })
