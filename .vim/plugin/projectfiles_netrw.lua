-- projectfiles_netrw.lua - netrw 목록에서도 색인 목록을 고친다.
--
-- NERDTree, neo-tree, F6 버퍼 목록에 이미 있는 것과 같은 세 키다. netrw 는
-- ':Explore' 나 gf 로 우연히 들어가게 되는 창이라, 거기서만 못 고치면
-- 그때마다 다른 창을 열어야 한다.
--
--   +   커서 줄(또는 선택 영역)의 파일/디렉터리를 색인 목록에 넣는다
--   -   뺀다
--   =   지금 들어 있는지 본다
--
-- 들어 있는 항목은 줄 끝에 빨간 표시. netrw 는 자기 버퍼를 자주 다시
-- 그리므로 표시도 그때마다 다시 얹는다.
--
--   g:projectfiles_netrw = 0   이 기능을 끈다

if vim.g.loaded_projectfiles_netrw then
  return
end
vim.g.loaded_projectfiles_netrw = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local NS = api.nvim_create_namespace('projectfiles_netrw')

local function on()
  local v = vim.g.projectfiles_netrw
  return v == nil or (tonumber(v) or 1) ~= 0
end

-- 커서 줄의 항목 이름. netrw 는 목록 모양(thin/long/wide/tree)에 따라 줄이
-- 전혀 달라서 직접 파싱하지 않는다 - netrw 자신에게 묻는다.
local function word_at(win, lnum)
  local save = api.nvim_win_get_cursor(win)
  api.nvim_win_set_cursor(win, { lnum, 0 })
  local ok, w = pcall(vim.fn['netrw#Call'], 'NetrwGetWord')
  pcall(api.nvim_win_set_cursor, win, save)
  if not ok or type(w) ~= 'string' then
    return nil
  end
  return w
end

local function path_at(win, lnum)
  local w = word_at(win, lnum)
  if not w or w == '' then
    return nil
  end
  w = w:gsub('[%*@|=/]+$', '')   -- 목록 장식과 디렉터리 표시를 뗀다
  if w == '' or w == '.' or w == '..' then
    return nil
  end
  local dir = vim.b.netrw_curdir
  if not dir or dir == '' then
    dir = vim.fn.getcwd()
  end
  local p = (dir:gsub('/+$', '')) .. '/' .. w
  return vim.fn.fnamemodify(p, ':p'):gsub('/+$', '')
end

local function paths_in_range(win, a, b)
  local out, seen = {}, {}
  for l = math.min(a, b), math.max(a, b) do
    local p = path_at(win, l)
    if p and not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  return out
end

local function mark(win)
  local buf = api.nvim_win_get_buf(win)
  pcall(api.nvim_buf_clear_namespace, buf, NS, 0, -1)
  if not on() or not _G.projectfiles_tree_flag then
    return
  end
  for l = 1, api.nvim_buf_line_count(buf) do
    local p = path_at(win, l)
    if p then
      local ok, flag = pcall(_G.projectfiles_tree_flag, p)
      if ok and flag and flag ~= '' then
        pcall(api.nvim_buf_set_extmark, buf, NS, l - 1, 0, {
          virt_text = { { ' ' .. flag, 'ProjectFilesIndexMark' } },
          virt_text_pos = 'eol',
        })
      end
    end
  end
end

local function act(fn, label)
  local win = api.nvim_get_current_win()
  local m = vim.fn.mode()
  local a, b = vim.fn.line('.'), vim.fn.line('.')
  if m == 'v' or m == 'V' then
    a, b = vim.fn.line('v'), vim.fn.line('.')
    api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  end
  local paths = paths_in_range(win, a, b)
  if #paths == 0 then
    vim.notify('netrw: 이 줄에는 항목이 없습니다', vim.log.levels.WARN)
    return
  end
  if not fn then
    vim.notify('projectfiles 가 없습니다', vim.log.levels.WARN)
    return
  end
  pcall(fn, paths)
  vim.notify(('색인 %s: %d개'):format(label, #paths))
  vim.defer_fn(function()
    if api.nvim_win_is_valid(win) then
      pcall(_G.projectfiles_tree_invalidate)
      mark(win)
    end
  end, 120)
end

local function attach(buf)
  if not on() then
    return
  end
  local function bmap(lhs, fn, desc)
    pcall(vim.keymap.set, { 'n', 'x' }, lhs, fn,
      { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  bmap('+', function() act(_G.projectfiles_add, '추가') end, '색인 목록에 추가')
  bmap('-', function() act(_G.projectfiles_remove, '제거') end, '색인 목록에서 제거')
  bmap('=', function()
    local p = path_at(api.nvim_get_current_win(), vim.fn.line('.'))
    if not p then
      return
    end
    local ok, st = pcall(_G.projectfiles_status, p)
    vim.notify(('%s : %s'):format(vim.fn.fnamemodify(p, ':~:.'),
      (ok and st and st ~= '') and st or '색인에 없음'))
  end, '색인 상태 보기')
  vim.schedule(function()
    local win = api.nvim_get_current_win()
    if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
      mark(win)
    end
  end)
end

local group = api.nvim_create_augroup('ProjectFilesNetrw', { clear = true })
api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'netrw',
  callback = function(a)
    attach(a.buf)
  end,
})
-- netrw 는 같은 버퍼를 다시 그리므로 들어올 때마다 표시를 새로 얹는다
api.nvim_create_autocmd({ 'BufWinEnter', 'CursorHold' }, {
  group = group,
  callback = function(a)
    if vim.bo[a.buf].filetype == 'netrw' then
      local win = api.nvim_get_current_win()
      if api.nvim_win_get_buf(win) == a.buf then
        mark(win)
      end
    end
  end,
})
