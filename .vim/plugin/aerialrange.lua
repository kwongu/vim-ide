-- aerialrange.lua - aerial 아웃라인에서 더블클릭하면 그 함수를 통째로 고른다.
--
-- Source Insight 의 Symbol Window 처럼 쓰기 위한 두 가지 중 하나다.
--   * 커서를 옮기면 편집 창이 그 심볼로 간다 -> aerial 의 autojump 옵션
--     (.vimrc 의 setup 에서 켠다)
--   * 더블클릭하면 편집 창에서 그 함수를 블록으로 잡는다 -> 이 파일
--
-- 잡는 범위는 '함수 위의 주석부터 함수 끝까지'다. 함수만 잡으면 그 함수가
-- 무엇인지 적어 둔 주석이 빠지는데, 복사하거나 옮길 때 필요한 것은 대개
-- 주석까지다.
--
-- 주석은 treesitter 로 판단한다(정규식이 아니라). 함수 바로 위 줄부터
-- 거슬러 올라가며 그 줄을 덮는 노드가 comment 인 동안 범위를 넓히고, 빈
-- 줄은 주석과 주석 사이라면 건너뛴다 - 주석 블록과 함수 사이에 한 줄
-- 비워 두는 스타일이 흔하다.
--
-- 옵션 (.vimrc)
--   g:aerial_range_comments = 0   " 주석은 빼고 함수만 잡는다
--   g:aerial_range_blank_gap = 1  " 주석과 함수 사이에 허용할 빈 줄 수
--   :AerialSelectRange            " 더블클릭과 같은 일을 커맨드로
--
-- yy / Y 는 같은 범위를 레지스터에 복사하고, p / P 는 aerial 커서의 함수 아래 / 위에
-- 편집 창에서 붙인다 (aerial 의 p = 미리보기 스크롤은 autojump 가 있어 쓰지 않는다)

if vim.g.loaded_aerialrange then
  return
end
vim.g.loaded_aerialrange = 1

if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api

local function cfg(name, default)
  local v = vim.g['aerial_range_' .. name]
  return v == nil and default or v
end

-- 이 줄을 덮는 노드가 주석인가. treesitter 가 없으면 nil 을 돌려주고,
-- 그때는 호출자가 주석 확장을 포기한다(추측으로 범위를 넓히지 않는다).
local function line_is_comment(buf, lnum)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return nil
  end
  local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  if not line then
    return false
  end
  local col = line:find('%S')
  if not col then
    return false -- 빈 줄: 주석은 아니다 (호출자가 따로 다룬다)
  end
  local okn, node = pcall(vim.treesitter.get_node,
    { bufnr = buf, pos = { lnum - 1, col - 1 } })
  if not okn or not node then
    return false
  end
  local t = node:type()
  return t:find('comment') ~= nil
end

-- 함수 시작 줄에서 위로 올라가며 붙어 있는 주석까지 범위를 넓힌다
local function extend_over_comments(buf, first)
  if cfg('comments', 1) == 0 then
    return first
  end
  local gap = tonumber(cfg('blank_gap', 1)) or 1
  local top = first
  local lnum = first - 1
  local blanks = 0
  while lnum >= 1 do
    local is_c = line_is_comment(buf, lnum)
    if is_c == nil then
      return top -- treesitter 가 없다: 넓히지 않는다
    end
    if is_c then
      top = lnum
      blanks = 0
    else
      local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
      if line:match('^%s*$') and blanks < gap then
        blanks = blanks + 1 -- 주석과 함수 사이의 빈 줄은 건너뛴다
      else
        break
      end
    end
    lnum = lnum - 1
  end
  return top
end

-- 심볼이 end_lnum 을 주지 않으면(백엔드에 따라 없다) treesitter 로 찾는다
local function end_of_symbol(buf, item)
  if item.end_lnum and item.end_lnum >= item.lnum then
    return item.end_lnum
  end
  local ok, node = pcall(vim.treesitter.get_node,
    { bufnr = buf, pos = { item.lnum - 1, math.max((item.col or 1) - 1, 0) } })
  if not ok or not node then
    return item.lnum
  end
  -- 정의 노드까지 올라간다
  while node do
    local t = node:type()
    if t:find('definition') or t:find('declaration') or t:find('specifier') then
      local _, _, erow = node:range()
      return erow + 1
    end
    node = node:parent()
  end
  return item.lnum
end

-- aerial 창의 커서 줄이 가리키는 심볼의 범위: 위 주석부터 끝까지 (더블클릭·v·yy 가 같이 쓴다)
local function symbol_range()
  local ok_util, util = pcall(require, 'aerial.util')
  local ok_data, data = pcall(require, 'aerial.data')
  if not (ok_util and ok_data) then
    return nil
  end
  if not util.is_aerial_buffer(0) then
    return nil
  end
  local lnum = api.nvim_win_get_cursor(0)[1]
  local bufdata = data.get_or_create(0)
  local item = bufdata and bufdata:item(lnum)
  if not item or not item.lnum then
    return nil
  end
  local src_win = util.get_source_win(api.nvim_get_current_win())
  if not (src_win and api.nvim_win_is_valid(src_win)) then
    return nil
  end
  local buf = api.nvim_win_get_buf(src_win)
  local first = item.lnum
  local last = end_of_symbol(buf, item)
  local top = extend_over_comments(buf, first)
  local total = api.nvim_buf_line_count(buf)
  top = math.max(1, math.min(top, total))
  last = math.max(top, math.min(last, total))
  return { win = src_win, buf = buf, top = top, last = last, name = item.name or '?' }
end

-- aerial 창의 커서 줄이 가리키는 심볼을 편집 창에서 블록으로 잡는다
function _G.aerial_select_range()
  local r = symbol_range()
  if not r then
    return false
  end
  local src_win, top, last = r.win, r.top, r.last
  api.nvim_set_current_win(src_win)
  -- 점프 전 자리를 jumplist 에 남긴다 - C-o 로 돌아올 수 있게
  pcall(vim.cmd, "normal! m'")
  -- 끝에서 시작해 첫 줄로 올라오며 잡는다: 커서가 블록의 첫 줄에 서고, 그 줄을 창
  -- 맨 위로 올린다(zt). 예전에는 첫 줄에서 끝으로 내려가며 잡아 커서가 끝 줄에 섰고,
  -- 긴 함수면 화면이 함수 끝으로 가서 잡은 블록의 머리가 안 보였다 (zt 도 커서인 끝 줄을
  -- 맨 위로 올렸다). 짧은 함수도 첫 줄이 맨 위에 와서 블록이 통째로 보인다. 끝으로는 o
  api.nvim_win_set_cursor(src_win, { last, 0 })
  vim.cmd('normal! V')
  api.nvim_win_set_cursor(src_win, { top, 0 })
  vim.cmd('normal! zt')
  return true
end

-- yy / p : aerial 창에서 함수를 통째로 복사하고 붙인다 (요청).
--
-- yy 는 더블클릭으로 잡히는 범위(위 주석부터 함수 끝까지)를 줄 단위로 레지스터에
-- 담는다 - "ayy 처럼 레지스터를 고를 수 있고, 편집 창에서 p 해도 같은 것이 붙는다.
-- p / P 는 aerial 커서가 가리키는 함수의 아래 / 위에 편집 창에서 붙인다 (커서는
-- aerial 에 그대로). aerial 에서 yy 한 함수를 붙일 때는 함수 사이에 빈 줄 하나를
-- 둔다 - 끝 '}' 바로 밑에 다음 함수의 주석이 붙으면 읽기 어렵다. 다른 데서 복사한
-- 것은 줄 단위로 그대로 붙인다. 숫자를 주면(3p) 그만큼 붙인다. 되돌리기는 u 한 번.
local last_yank -- aerial yy 로 담은 줄 (붙일 때 함수 사이 빈 줄을 둘지 가린다)
local yank_ns = api.nvim_create_namespace('aerial_yank')

local function default_reg(reg)
  return reg == nil or reg == '' or reg == '"' or reg == '+' or reg == '*'
end

function _G.aerial_yank_range(reg)
  local r = symbol_range()
  if not r then
    return false
  end
  local lines = api.nvim_buf_get_lines(r.buf, r.top - 1, r.last, false)
  reg = reg or vim.v.register
  if reg == '' then
    reg = '"'
  end
  vim.fn.setreg(reg, lines, 'V')
  if default_reg(reg) then
    -- 보통 yank 처럼 "0 과 이름 없는 레지스터에도 (편집 창의 p 가 그것을 쓴다)
    vim.fn.setreg('0', lines, 'V')
    vim.fn.setreg('"', lines, 'V')
  end
  last_yank = table.concat(lines, '\n')
  -- 복사한 범위를 편집 창에서 잠깐 칠한다 (yank 했다는 표시)
  pcall(function()
    vim.hl.range(r.buf, yank_ns, 'IncSearch', { r.top - 1, 0 }, { r.last - 1, -1 },
      { regtype = 'V' })
    vim.defer_fn(function()
      pcall(api.nvim_buf_clear_namespace, r.buf, yank_ns, 0, -1)
    end, 250)
  end)
  vim.notify(('함수 복사: %s (%d줄)'):format(r.name, #lines))
  return true
end

function _G.aerial_put_range(before, reg, count)
  local r = symbol_range()
  if not r then
    return false
  end
  if not vim.bo[r.buf].modifiable then
    vim.notify('편집 창 버퍼를 고칠 수 없습니다 (modifiable 꺼짐)', vim.log.levels.WARN)
    return false
  end
  reg = reg or vim.v.register
  if reg == '' then
    reg = '"'
  end
  local lines = vim.fn.getreg(reg, 1, true)
  if type(lines) ~= 'table' or #lines == 0 then
    vim.notify(('레지스터 %s 가 비어 있습니다'):format(reg), vim.log.levels.WARN)
    return false
  end
  local block = last_yank ~= nil and table.concat(lines, '\n') == last_yank
  local function blank(l)
    return l == nil or l:match('^%s*$') ~= nil
  end
  local out = {}
  for _ = 1, math.max(1, count or 1) do
    if block and before then
      vim.list_extend(out, lines)
      out[#out + 1] = ''
    else
      if block then
        out[#out + 1] = ''
      end
      vim.list_extend(out, lines)
    end
  end
  local at -- 이 줄 앞(0 기준)에 넣는다
  if before then
    at = r.top - 1
    -- 위 함수와 붙지 않게: 넣을 자리 바로 위가 빈 줄이 아니면 앞에도 빈 줄
    if block and at > 0 and not blank(api.nvim_buf_get_lines(r.buf, at - 1, at, false)[1]) then
      table.insert(out, 1, '')
    end
  else
    at = r.last
    -- 함수 끝 바로 밑이 이미 빈 줄이면 그 빈 줄 뒤에 넣는다 (빈 줄이 두 겹이 되지 않게)
    if block and blank(api.nvim_buf_get_lines(r.buf, at, at + 1, false)[1])
        and at < api.nvim_buf_line_count(r.buf) then
      table.remove(out, 1)
      at = at + 1
      out[#out + 1] = ''
    end
  end
  api.nvim_buf_set_lines(r.buf, at, at, false, out)
  -- 붙인 함수의 첫 줄로 편집 창 커서를 (포커스는 aerial 에 그대로)
  local first = at + 1
  while first <= at + #out and blank(api.nvim_buf_get_lines(r.buf, first - 1, first, false)[1]) do
    first = first + 1
  end
  pcall(api.nvim_buf_set_mark, r.buf, '[', at + 1, 0, {})
  pcall(api.nvim_buf_set_mark, r.buf, ']', at + #out, 0, {})
  pcall(api.nvim_win_set_cursor, r.win, { math.min(first, api.nvim_buf_line_count(r.buf)), 0 })
  vim.notify(('붙임: %d줄 (%s %s)'):format(#out, r.name, before and '위' or '아래'))
  return true
end

api.nvim_create_user_command('AerialSelectRange', function()
  if not _G.aerial_select_range() then
    vim.notify('aerial 창에서, 심볼 줄 위에서 쓰세요', vim.log.levels.WARN)
  end
end, { desc = 'Select the symbol (with its leading comment) in the edit window' })

-- aerial 버퍼가 생길 때 더블클릭을 붙인다
api.nvim_create_autocmd('FileType', {
  group = api.nvim_create_augroup('AerialRange', { clear = true }),
  pattern = 'aerial',
  callback = function(a)
    vim.keymap.set('n', '<2-LeftMouse>', function()
      -- 클릭한 줄로 커서가 옮겨진 뒤에 잡아야 한다
      vim.schedule(function() _G.aerial_select_range() end)
    end, { buffer = a.buf, desc = 'aerial: 함수를 주석까지 블록으로 잡기' })
    vim.keymap.set('n', 'v', function()
      _G.aerial_select_range()
    end, { buffer = a.buf, desc = 'aerial: 함수를 주석까지 블록으로 잡기' })
    vim.keymap.set('n', 'yy', function()
      _G.aerial_yank_range(vim.v.register)
    end, { buffer = a.buf, desc = 'aerial: 함수를 주석까지 통째로 복사' })
    vim.keymap.set('n', 'Y', function()
      _G.aerial_yank_range(vim.v.register)
    end, { buffer = a.buf, desc = 'aerial: 함수를 주석까지 통째로 복사' })
    vim.keymap.set('n', 'p', function()
      _G.aerial_put_range(false, vim.v.register, vim.v.count1)
    end, { buffer = a.buf, desc = 'aerial: 복사한 것을 이 함수 아래에 붙이기 (편집 창)' })
    vim.keymap.set('n', 'P', function()
      _G.aerial_put_range(true, vim.v.register, vim.v.count1)
    end, { buffer = a.buf, desc = 'aerial: 복사한 것을 이 함수 위에 붙이기 (편집 창)' })
  end,
})
