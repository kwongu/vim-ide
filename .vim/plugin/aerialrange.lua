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

-- aerial 창의 커서 줄이 가리키는 심볼을 편집 창에서 블록으로 잡는다
function _G.aerial_select_range()
  local ok_util, util = pcall(require, 'aerial.util')
  local ok_data, data = pcall(require, 'aerial.data')
  if not (ok_util and ok_data) then
    return false
  end
  if not util.is_aerial_buffer(0) then
    return false
  end
  local lnum = api.nvim_win_get_cursor(0)[1]
  local bufdata = data.get_or_create(0)
  local item = bufdata and bufdata:item(lnum)
  if not item or not item.lnum then
    return false
  end
  local src_win = util.get_source_win(api.nvim_get_current_win())
  if not (src_win and api.nvim_win_is_valid(src_win)) then
    return false
  end
  local buf = api.nvim_win_get_buf(src_win)
  local first = item.lnum
  local last = end_of_symbol(buf, item)
  local top = extend_over_comments(buf, first)
  local total = api.nvim_buf_line_count(buf)
  top = math.max(1, math.min(top, total))
  last = math.max(top, math.min(last, total))

  api.nvim_set_current_win(src_win)
  -- 점프 전 자리를 jumplist 에 남긴다 - C-o 로 돌아올 수 있게
  pcall(vim.cmd, "normal! m'")
  api.nvim_win_set_cursor(src_win, { top, 0 })
  vim.cmd('normal! V')
  api.nvim_win_set_cursor(src_win, { last, 0 })
  -- 화면에 다 안 들어오면 시작 줄이 보이도록
  if last - top + 1 > api.nvim_win_get_height(src_win) then
    vim.cmd('normal! zt')
  end
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
  end,
})
