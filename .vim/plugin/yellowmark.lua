-- yellowmark.lua - <F8> 로 심볼에 노란 표시를 붙이고 뗀다.
--
-- Source Insight 에서 심볼을 눈에 박아 두고 코드를 읽는 방식이다. 커서를
-- 심볼에 놓고 <F8> 을 누르면 그 심볼의 모든 등장 위치가 노랗게 되고, 이미
-- 노란 심볼 위에서 다시 누르면 벗겨진다. 여러 심볼을 동시에 노랗게 둘 수
-- 있고, 창을 옮기거나 다른 파일을 열어도 표시는 남는다.
--
-- F4(vim-mark)와 무엇이 다른가
--   F4 는 심볼마다 다른 색을 돌려 쓴다 - 여러 개를 색으로 구분하려는 것.
--   <F8> 은 한 가지 노란색만 쓴다 - '지금 보는 것'을 표시하려는 것.
--   refhighlight(커서 밑 심볼 자동 음영)는 커서를 따라 사라지지만
--   이 표시는 지울 때까지 남는다.
--
-- 우선순위: vim-mark 는 -10 에서 -67 까지 쓰고 refhighlight 는 -1010 이다.
-- 이 표시는 사용자가 일부러 붙인 것이니 그 둘보다 위(-8)에 온다.
--
-- 옵션 (.vimrc)
--   g:yellowmark_priority   matchadd 우선순위 (기본 -8)
--   g:yellowmark_min        이 길이 미만 이름은 무시 (기본 1)
--   :YellowMarkClear        전부 지우기
--   :YellowMarkList         지금 표시된 심볼 보기

if vim.g.loaded_yellowmark then
  return
end
vim.g.loaded_yellowmark = 1

if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api

local function cfg(name, default)
  local v = vim.g['yellowmark_' .. name]
  return v == nil and default or v
end

local function notify(msg, level)
  vim.notify('YellowMark: ' .. msg, level or vim.log.levels.INFO)
end

local words = {}  -- 표시된 단어 -> true
local ids = {}    -- winid -> matchadd id

local function count()
  local n = 0
  for _ in pairs(words) do
    n = n + 1
  end
  return n
end

-- 표시된 단어 전부를 한 패턴으로 묶는다. 창마다 match 를 하나만 걸면
-- 되니 단어가 늘어도 창당 비용은 그대로다.
local function pattern()
  local list = {}
  for w in pairs(words) do
    list[#list + 1] = w
  end
  if #list == 0 then
    return nil
  end
  table.sort(list)
  local parts = {}
  for _, w in ipairs(list) do
    -- \V(very nomagic) 안에서도 \< \> 는 낱말 경계다
    parts[#parts + 1] = [[\<]] .. vim.fn.escape(w, [[\]]) .. [[\>]]
  end
  return [[\V\%(]] .. table.concat(parts, [[\|]]) .. [[\)]]
end

local function clear_win(win)
  if ids[win] then
    pcall(vim.fn.matchdelete, ids[win], win)
    ids[win] = nil
  end
end

local function paint_win(win)
  if not api.nvim_win_is_valid(win) then
    ids[win] = nil
    return
  end
  clear_win(win)
  local pat = pattern()
  if not pat then
    return
  end
  local ok, id = pcall(vim.fn.matchadd, 'SiYellowMark', pat,
    cfg('priority', -8), -1, { window = win })
  if ok then
    ids[win] = id
  end
end

local function paint_all()
  -- 사라진 창의 기록은 흘려보낸다
  for win in pairs(ids) do
    if not api.nvim_win_is_valid(win) then
      ids[win] = nil
    end
  end
  for _, win in ipairs(api.nvim_list_wins()) do
    paint_win(win)
  end
end

-- 커서 밑 심볼을 켜고 끈다
function _G.yellowmark_toggle()
  local word = vim.fn.expand('<cword>')
  if type(word) ~= 'string' or word == ''
      or not word:match('^[%a_][%w_]*$')
      or #word < (tonumber(cfg('min', 1)) or 1) then
    notify('심볼 위가 아닙니다', vim.log.levels.WARN)
    return
  end
  local on
  if words[word] then
    words[word] = nil
    on = false
  else
    words[word] = true
    on = true
  end
  paint_all()
  local n = count()
  notify(("%s '%s'%s"):format(on and '표시' or '해제', word,
    n > 0 and ('  (표시 %d개)'):format(n) or '  (남은 표시 없음)'))
end

local group = api.nvim_create_augroup('YellowMark', { clear = true })

-- 새로 생긴 창에도 깔아 준다. 표시는 창이 아니라 '지금 읽는 코드'에
-- 붙는 것이라, 창을 나누거나 다른 파일을 열어도 따라와야 한다.
api.nvim_create_autocmd({ 'WinNew', 'WinEnter', 'BufWinEnter', 'TabEnter' }, {
  group = group,
  callback = function()
    if next(words) == nil then
      return
    end
    local win = api.nvim_get_current_win()
    if not ids[win] then
      paint_win(win)
    end
  end,
})

api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(a)
    local win = tonumber(a.match)
    if win then
      ids[win] = nil
    end
  end,
})

-- 색은 컬러스킴이 정할 수 있게 default 로 둔다. 정하지 않은 테마에서도
-- 보이도록 기본값은 SI 의 노란 표시(검정 글자 + 노란 배경)다.
local function set_hl()
  api.nvim_set_hl(0, 'SiYellowMark', {
    fg = '#000000', bg = '#ffff00', ctermfg = 16, ctermbg = 11,
    default = true,
  })
end
set_hl()
api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_hl })

api.nvim_create_user_command('YellowMarkClear', function()
  local n = count()
  if n == 0 then
    notify('표시된 것이 없습니다')
    return
  end
  words = {}
  paint_all()
  notify(('%d개를 지웠습니다'):format(n))
end, { desc = 'Drop every yellow mark' })

api.nvim_create_user_command('YellowMarkList', function()
  local list = {}
  for w in pairs(words) do
    list[#list + 1] = w
  end
  if #list == 0 then
    notify('표시된 것이 없습니다')
    return
  end
  table.sort(list)
  notify(('%d개: %s'):format(#list, table.concat(list, ', ')))
end, { desc = 'List the symbols carrying a yellow mark' })

api.nvim_create_user_command('YellowMarkToggle', function()
  _G.yellowmark_toggle()
end, { desc = 'Toggle the yellow mark on the symbol under the cursor' })
