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
-- 그리고 아웃라인을 vim 처럼 고친다 - 한 줄이 그 함수(위 주석부터 끝까지)다:
--   yy Y y{이동} 비주얼 y 복사, dd d{이동} 비주얼 d/x 잘라내기, p P 붙이기,
--   u <C-r> 되돌리기 / 다시, . 되풀이 - 모두 편집 창의 원본에 (아래 '아웃라인에서
--   vim 처럼 고치기'). aerial 의 p (미리보기 스크롤) 는 autojump 가 있어 쓰지 않는다

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
local function source_win()
  local ok_util, util = pcall(require, 'aerial.util')
  if not ok_util or not util.is_aerial_buffer(0) then
    return nil
  end
  local w = util.get_source_win(api.nvim_get_current_win())
  return (w and api.nvim_win_is_valid(w)) and w or nil
end

-- 아웃라인 줄 l1..l2 가 가리키는 심볼들의 원본 범위: 첫 심볼은 위 주석부터, 끝은
-- 마지막 심볼의 끝까지 (사이에 있는 것도 함께 - 원본에서 이어진 한 덩어리다)
local function rows_range(l1, l2)
  local ok_data, data = pcall(require, 'aerial.data')
  local src_win = source_win()
  if not ok_data or not src_win then
    return nil
  end
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  local bufdata = data.get_or_create(0)
  local buf = api.nvim_win_get_buf(src_win)
  local top, last, first, name, n
  for l = l1, l2 do
    local item = bufdata and bufdata:item(l)
    if item and item.lnum then
      local t = extend_over_comments(buf, item.lnum)
      local e = end_of_symbol(buf, item)
      if not top or t < top then
        top, first, name = t, item.lnum, item.name
      end
      last = math.max(last or e, e)
      n = (n or 0) + 1
    end
  end
  if not top then
    return nil
  end
  local total = api.nvim_buf_line_count(buf)
  top = math.max(1, math.min(top, total))
  last = math.max(top, math.min(last, total))
  return { win = src_win, buf = buf, top = top, last = last, first = math.max(top, math.min(first, last)),
    name = name or '?', n = n }
end

local function symbol_range()
  local l = api.nvim_win_get_cursor(0)[1]
  return rows_range(l, l)
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

-- 아웃라인에서 vim 처럼 고치기 (요청: 'aerial 창에서 vim 기본 기능인 복사 붙여넣기
-- 삭제 등을 똑같이 하고, 그것이 편집 창에 그대로 반영').
--
-- 아웃라인의 한 줄 = 원본의 그 심볼 한 덩어리(위 주석부터 끝까지, 더블클릭과 같은
-- 범위)로 보고 vim 의 키를 그대로 쓴다:
--   yy Y 3yy y{이동} 비주얼 y   복사        dd 3dd d{이동} 비주얼 d   잘라내기
--   p P 3p                      붙이기      u <C-r>                  되돌리기 / 다시
--   .                           마지막 d / y / p 를 다시
-- 레지스터는 vim 그대로다("ayy, "add, "_dd, "0, "1-"9) - 복사·삭제는 편집 창에서
-- :yank / :delete 로 하기 때문이다. 그래서 dd 로 잘라 다른 함수에서 p 하면 옮겨지고
-- (ddp 는 아래 함수와 자리 바꾸기), 편집 창의 p 로도 붙는다.
-- 여러 줄(3dd, 비주얼)은 원본에서 첫 심볼의 주석부터 마지막 심볼 끝까지 이어진 한
-- 덩어리다 - 사이의 빈 줄이나 전역 변수도 함께 간다.
-- 빈 줄: 지울 때는 이웃 사이에 빈 줄이 두 겹으로 남지 않게 하나를 함께 지우고, 아웃
-- 라인에서 복사하거나 지운 덩어리를 붙일 때는 이웃 함수와 사이에 빈 줄 하나를 둔다.
-- 다른 데서 복사한 것은 줄 단위로 그대로 붙인다.
-- 고칠 때마다 아웃라인을 바로 다시 읽는다 - API 로 고친 버퍼는 TextChanged 가 나지
-- 않아(지금 버퍼가 아니다) 편집 창에 들어가야 aerial 이 따라왔다. 커서는 vim 처럼
-- 붙인 덩어리로, 지운 뒤에는 그 자리의 다음 심볼로 간다. 포커스는 aerial 에 그대로.
local last_yank -- 아웃라인에서 복사·삭제한 덩어리 (붙일 때 빈 줄을 둘지 가린다)
local last_yank_head = 0 -- 그 덩어리에서 첫 심볼의 정의 줄까지 (위 주석 줄 수)
local yank_ns = api.nvim_create_namespace('aerial_yank')

local function blank(l)
  return l == nil or l:match('^%s*$') ~= nil
end

local function line_at(buf, l)
  if l < 1 or l > api.nvim_buf_line_count(buf) then
    return nil
  end
  return api.nvim_buf_get_lines(buf, l - 1, l, false)[1]
end

-- Ex 명령의 레지스터 자리 (이름 없는 레지스터 " 는 Ex 에서 주석이라 비운다)
local function reg_arg(reg)
  if reg == nil or reg == '' or reg == '"' then
    return ''
  end
  return ' ' .. reg
end

local function remember(r)
  last_yank = table.concat(api.nvim_buf_get_lines(r.buf, r.top - 1, r.last, false), '\n')
  last_yank_head = r.first - r.top
end

local function flash(r)
  pcall(function()
    vim.hl.range(r.buf, yank_ns, 'IncSearch', { r.top - 1, 0 }, { r.last - 1, -1 }, { regtype = 'V' })
    vim.defer_fn(function()
      pcall(api.nvim_buf_clear_namespace, r.buf, yank_ns, 0, -1)
    end, 250)
  end)
end

-- 아웃라인을 다시 읽고, 편집 창 커서를 line 에서 시작하는 심볼의 이름 칸에 둔 뒤 aerial
-- 커서를 맞춘다. aerial 은 커서가 심볼 이름(selection range) 앞이면 그 앞 심볼로 쳐서,
-- 줄 맨 앞에 두면 aerial 커서가 엉뚱한 심볼에 남았다 (실측). at_or_after: line 에 심볼이
-- 없으면 그 뒤 첫 심볼로 (지운 뒤)
local function refresh_outline(win, buf, line, at_or_after)
  local ok, backends = pcall(require, 'aerial.backends')
  local be = ok and backends.get(buf) or nil
  if be and be.fetch_symbols_sync then
    pcall(be.fetch_symbols_sync, buf)
  else
    pcall(function() require('aerial').refetch_symbols(buf) end)
  end
  if line then
    pcall(function()
      local best
      for _, item in require('aerial.data').get_or_create(buf):iter({ skip_hidden = true }) do
        if item.lnum == line or (at_or_after and item.lnum >= line and not best) then
          best = item
          if item.lnum == line then
            break
          end
        end
      end
      if best then
        local sel = best.selection_range or best
        api.nvim_win_set_cursor(win, { sel.lnum, sel.col or 0 })
      else
        api.nvim_win_set_cursor(win, { math.min(line, api.nvim_buf_line_count(buf)), 0 })
      end
    end)
  end
  pcall(function() require('aerial.window').update_position(win, win) end)
end

local function modifiable(buf)
  if not vim.bo[buf].modifiable then
    vim.notify('편집 창 버퍼를 고칠 수 없습니다 (modifiable 꺼짐)', vim.log.levels.WARN)
    return false
  end
  return true
end

-- 복사: 원본의 그 덩어리를 :yank 로 ("0 과 이름 없는 레지스터가 vim 그대로)
local function do_yank(r, reg)
  remember(r)
  api.nvim_win_call(r.win, function()
    vim.cmd(('%d,%dyank%s'):format(r.top, r.last, reg_arg(reg)))
  end)
  flash(r)
  vim.notify(('복사: %s%s (%d줄)'):format(r.name, r.n > 1 and (' 외 ' .. (r.n - 1)) or '',
    r.last - r.top + 1))
end

-- 잘라내기: :delete 로 ("1-"9 가 밀리는 것까지 vim 그대로)
local function do_delete(r, reg)
  if not modifiable(r.buf) then
    return
  end
  remember(r)
  local top = r.top
  api.nvim_win_call(r.win, function()
    vim.cmd(('%d,%ddelete%s'):format(r.top, r.last, reg_arg(reg)))
    -- 빈 줄이 두 겹으로 남지 않게 (덩어리 앞뒤가 둘 다 빈 줄이면 하나를 함께 지운다).
    -- 블랙홀로 지워 레지스터는 건드리지 않는다
    local before, after = line_at(r.buf, top - 1), line_at(r.buf, top)
    if blank(after) and after ~= nil and (top == 1 or blank(before)) then
      vim.cmd(('%ddelete _'):format(top))
    end
  end)
  refresh_outline(r.win, r.buf, math.min(top, api.nvim_buf_line_count(r.buf)), true)
  vim.notify(('잘라냄: %s%s (%d줄)'):format(r.name, r.n > 1 and (' 외 ' .. (r.n - 1)) or '',
    r.last - r.top + 1))
end

-- 붙이기: 아웃라인 커서의 심볼 아래(p) / 위(P)에
local function do_put(before, reg, count)
  local src = source_win()
  if not src then
    return
  end
  local buf = api.nvim_win_get_buf(src)
  if not modifiable(buf) then
    return
  end
  reg = (reg == nil or reg == '') and '"' or reg
  local lines = vim.fn.getreg(reg, 1, true)
  if type(lines) ~= 'table' or #lines == 0 then
    vim.notify(('레지스터 %s 가 비어 있습니다'):format(reg), vim.log.levels.WARN)
    return
  end
  local r = symbol_range()
  local at -- 이 줄 앞(0 기준)에 넣는다
  if r then
    at = before and r.top - 1 or r.last
  else
    at = before and 0 or api.nvim_buf_line_count(buf) -- 아웃라인이 비었다
  end
  local block = last_yank ~= nil and table.concat(lines, '\n') == last_yank
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
  if block then
    if before then
      -- 위 심볼과 붙지 않게: 넣을 자리 바로 위가 빈 줄이 아니면 앞에도 빈 줄
      if at > 0 and not blank(line_at(buf, at)) then
        table.insert(out, 1, '')
      end
      if at == 0 then
        -- 파일 맨 앞: 앞 빈 줄 없이
        while out[1] == '' do
          table.remove(out, 1)
        end
      end
    elseif blank(line_at(buf, at + 1)) and at < api.nvim_buf_line_count(buf) then
      -- 덩어리 끝 바로 밑이 이미 빈 줄이면 그 뒤에 넣는다 (빈 줄이 두 겹이 되지 않게)
      table.remove(out, 1)
      at = at + 1
      out[#out + 1] = ''
    elseif at == 0 then
      table.remove(out, 1)
    end
  end
  api.nvim_buf_set_lines(buf, at, at, false, out)
  pcall(api.nvim_buf_set_mark, buf, '[', at + 1, 0, {})
  pcall(api.nvim_buf_set_mark, buf, ']', at + #out, 0, {})
  local first = at + 1
  while first <= at + #out and blank(line_at(buf, first)) do
    first = first + 1
  end
  if block then
    first = first + last_yank_head -- 붙인 심볼의 정의 줄 (주석 다음)
  end
  refresh_outline(src, buf, math.min(first, api.nvim_buf_line_count(buf)), not block)
  vim.notify(('붙임: %d줄 (%s)'):format(#out, before and '위' or '아래'))
end

-- 되돌리기 / 다시 하기: 편집 창의 버퍼에서
local function do_undo(redo, count)
  local src = source_win()
  if not src then
    return
  end
  local buf = api.nvim_win_get_buf(src)
  local ok, err = pcall(api.nvim_win_call, src, function()
    -- :undo N 은 'N 번 되돌리기' 가 아니라 'N 번째 변경 상태로' 라서 세기만큼 되풀이한다
    for _ = 1, math.max(1, count or 1) do
      vim.cmd(redo and 'silent redo' or 'silent undo')
    end
  end)
  if not ok then
    vim.notify(tostring(err):gsub('^.-(E%d+:)', '%1'), vim.log.levels.WARN)
  end
  local l = api.nvim_win_get_cursor(src)[1]
  refresh_outline(src, buf, l, true)
end

-- d / y 연산자 (vim 의 operatorfunc - 그래서 d{이동}, 3dd, . 이 vim 처럼 된다)
local pending_op
function _G.aerial_outline_opfunc()
  local l1 = api.nvim_buf_get_mark(0, '[')[1]
  local l2 = api.nvim_buf_get_mark(0, ']')[1]
  local r = rows_range(l1, l2)
  if not r then
    vim.notify('심볼 줄이 아닙니다', vim.log.levels.WARN)
    return
  end
  local reg = vim.v.register
  if pending_op == 'd' then
    do_delete(r, reg)
  elseif pending_op == 'y' then
    do_yank(r, reg)
    -- y 는 커서를 덩어리 첫 줄로 (vim 처럼)
    pcall(api.nvim_win_set_cursor, 0, { math.min(l1, l2), 0 })
  end
end

local put_args = { false, 1 }
function _G.aerial_outline_putfunc()
  do_put(put_args[1], vim.v.register, put_args[2])
end

function _G.aerial_yank_range(reg)
  local r = symbol_range()
  if not r then
    return false
  end
  do_yank(r, reg or vim.v.register)
  return true
end

function _G.aerial_put_range(before, reg, count)
  do_put(before, reg or vim.v.register, count)
  return true
end

api.nvim_create_user_command('AerialSelectRange', function()
  if not _G.aerial_select_range() then
    vim.notify('aerial 창에서, 심볼 줄 위에서 쓰세요', vim.log.levels.WARN)
  end
end, { desc = 'Select the symbol (with its leading comment) in the edit window' })

-- aerial 버퍼가 생길 때 키를 붙인다
api.nvim_create_autocmd('FileType', {
  group = api.nvim_create_augroup('AerialRange', { clear = true }),
  pattern = 'aerial',
  callback = function(a)
    local function map(mode, lhs, rhs, desc, expr)
      vim.keymap.set(mode, lhs, rhs, { buffer = a.buf, desc = 'aerial: ' .. desc, expr = expr })
    end
    map('n', '<2-LeftMouse>', function()
      -- 클릭한 줄로 커서가 옮겨진 뒤에 잡아야 한다
      vim.schedule(function() _G.aerial_select_range() end)
    end, '함수를 주석까지 블록으로 잡기')
    map('n', 'v', function() _G.aerial_select_range() end, '함수를 주석까지 블록으로 잡기')
    local function op(kind, motion)
      return function()
        pending_op = kind
        vim.o.operatorfunc = 'v:lua.aerial_outline_opfunc'
        return 'g@' .. (motion or '')
      end
    end
    map('n', 'd', op('d'), '함수 잘라내기 (d{이동}, 편집 창에서)', true)
    map('n', 'dd', op('d', '_'), '함수를 주석까지 잘라내기 (편집 창에서)', true)
    map('n', 'y', op('y'), '함수 복사 (y{이동})', true)
    map('n', 'yy', op('y', '_'), '함수를 주석까지 통째로 복사', true)
    map('n', 'Y', op('y', '_'), '함수를 주석까지 통째로 복사', true)
    local function visual(kind)
      return function()
        local l1, l2 = vim.fn.line('v'), vim.fn.line('.')
        api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
        local r = rows_range(l1, l2)
        if not r then
          return
        end
        if kind == 'd' then
          do_delete(r, vim.v.register)
        else
          do_yank(r, vim.v.register)
          pcall(api.nvim_win_set_cursor, 0, { math.min(l1, l2), 0 })
        end
      end
    end
    map('x', 'd', visual('d'), '고른 함수들 잘라내기 (편집 창에서)')
    map('x', 'x', visual('d'), '고른 함수들 잘라내기 (편집 창에서)')
    map('x', 'y', visual('y'), '고른 함수들 복사')
    local function put(before)
      return function()
        put_args = { before, vim.v.count1 }
        vim.o.operatorfunc = 'v:lua.aerial_outline_putfunc'
        -- 세기는 put_args 로 넘겼다. g@ 에 세기가 붙지 않게 먼저 지운다
        return (vim.v.count > 0 and '<Esc>' or '') .. 'g@_'
      end
    end
    map('n', 'p', put(false), '복사한 것을 이 함수 아래에 붙이기 (편집 창)', true)
    map('n', 'P', put(true), '복사한 것을 이 함수 위에 붙이기 (편집 창)', true)
    map('n', 'u', function() do_undo(false, vim.v.count1) end, '편집 창에서 되돌리기')
    map('n', '<C-r>', function() do_undo(true, vim.v.count1) end, '편집 창에서 다시 하기')
  end,
})
