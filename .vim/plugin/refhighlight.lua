-- refhighlight.lua - Source Insight 의 'Reference Highlight'.
--
-- SI 는 커서가 심볼 위에 있으면 화면에 보이는 그 심볼의 모든 등장 위치에
-- 옅은 파란 음영(#aae1ff)을 깔아 준다. 눈으로 "이 변수가 이 함수 안에서
-- 어디에 쓰이는지"를 즉시 보는 기능이고, 색인이나 점프와는 무관하다.
--
-- 구현: 커서가 멈추면(80ms) 창 단위 matchadd 를 하나 걸고, 움직이면 지운다.
-- matchadd 는 보이는 화면만 계산하므로 2만 줄 파일에서도 비용이 없다.
--
-- 하지 않는 경우
--   * 특수 버퍼(패널/트리/quickfix/터미널)
--   * 커서가 단어 위가 아닐 때, 한 글자 이름, C 예약어
--   * 커서가 문자열·주석 안일 때 (treesitter 가 알려 준다)
--
-- 옵션 (.vimrc)
--   g:refhighlight        0 으로 끈다 (기본 1)
--   g:refhighlight_delay  커서가 멈춘 뒤 몇 ms 만에 칠할지 (기본 80)
--   g:refhighlight_min    이 길이 미만 이름은 무시 (기본 2)
--   g:refhighlight_priority  matchadd 우선순위 (기본 -50, F4 마크 아래)
--   :RefHighlightToggle   실행 중에 켜고 끄기
--
-- vim-mark(F4) 와 겹치지 않는다: vim-mark 는 -10 이하(g:mwMaxMatchPriority)
-- 를 쓰므로 여기서는 -50 을 써서, F4 로 칠한 색과 검색 하이라이트가 항상
-- 위에 온다.

if vim.g.loaded_refhighlight then
  return
end
vim.g.loaded_refhighlight = 1

if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local uv = vim.uv or vim.loop

local KEYWORD = {}
for w in ([[if else for while do switch case break continue return goto
  struct union enum typedef sizeof static const volatile extern inline
  register auto void int char short long float double signed unsigned
  bool restrict asm typeof NULL true false]]):gmatch('%S+') do
  KEYWORD[w] = true
end

local s = { timer = nil, word = nil, id = nil, win = nil }

local function cfg(name, default)
  local v = vim.g['refhighlight_' .. name]
  if v == nil then
    return default
  end
  return v
end

local function clear()
  if s.id and s.win and api.nvim_win_is_valid(s.win) then
    pcall(vim.fn.matchdelete, s.id, s.win)
  end
  s.id, s.word, s.win = nil, nil, nil
end

-- 커서가 문자열이나 주석 안인가? (treesitter 가 붙어 있을 때만 판단한다)
local function in_string_or_comment(buf, row, col)
  local ok, caps = pcall(vim.treesitter.get_captures_at_pos, buf, row, col)
  if not ok or not caps then
    return false
  end
  for _, c in ipairs(caps) do
    local n = c.capture
    if n == 'string' or n == 'comment' or n:match('^string%.')
        or n:match('^comment%.') then
      return true
    end
  end
  return false
end

local function paint()
  if vim.g.refhighlight == 0 then
    return
  end
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' then
    clear()
    return
  end
  -- 커서가 단어 위인가
  local pos = api.nvim_win_get_cursor(win)
  local line = api.nvim_get_current_line()
  local ch = line:sub(pos[2] + 1, pos[2] + 1)
  if not ch:match('[%w_]') then
    clear()
    return
  end
  local word = vim.fn.expand('<cword>')
  if word == '' or #word < cfg('min', 2) or KEYWORD[word]
      or not word:match('^[%a_][%w_]*$') then
    clear()
    return
  end
  if in_string_or_comment(buf, pos[1] - 1, pos[2]) then
    clear()
    return
  end
  if s.word == word and s.win == win and s.id then
    return -- 이미 같은 심볼에 칠해져 있다
  end
  clear()
  local pat = [[\V\<]] .. vim.fn.escape(word, '\\') .. [[\>]]
  local ok, id = pcall(vim.fn.matchadd, 'SiRefHighlight', pat,
    cfg('priority', -50), -1, { window = win })
  if ok then
    s.id, s.word, s.win = id, word, win
  end
end

local function schedule()
  if not s.timer then
    s.timer = uv.new_timer()
  end
  s.timer:stop()
  s.timer:start(cfg('delay', 80), 0, vim.schedule_wrap(function()
    local ok, err = pcall(paint)
    if not ok and vim.g.refhighlight_debug then
      vim.notify('refhighlight: ' .. tostring(err), vim.log.levels.WARN)
    end
  end))
end

local group = api.nvim_create_augroup('RefHighlight', { clear = true })

api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  group = group,
  callback = schedule,
})

api.nvim_create_autocmd({ 'WinLeave', 'BufLeave', 'InsertEnter' }, {
  group = group,
  callback = clear,
})

-- 색은 컬러스킴이 정한다. 정하지 않은 테마에서도 보이도록 기본값을 둔다
-- (SI 의 Reference Highlight: 검정 글자 + #aae1ff 배경).
local function set_hl()
  api.nvim_set_hl(0, 'SiRefHighlight', {
    fg = '#000000', bg = '#aae1ff', ctermfg = 16, ctermbg = 153,
    default = true,
  })
end
set_hl()
api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_hl })

api.nvim_create_user_command('RefHighlightToggle', function()
  vim.g.refhighlight = (vim.g.refhighlight == 0) and 1 or 0
  if vim.g.refhighlight == 0 then
    clear()
    vim.notify('RefHighlight: 끔')
  else
    paint()
    vim.notify('RefHighlight: 켬')
  end
end, { desc = 'Source Insight style highlight of the symbol under the cursor' })
