-- projectfiles_bufexplorer.lua - F6 의 버퍼 목록에서 색인 목록을 고친다.
--
-- NERDTree 와 neo-tree 에는 이미 있는 기능이다(+ 추가, - 제거, = 상태,
-- 영역 지정도 된다). 버퍼 목록에도 같은 것이 있어야 하는 이유는, 지금
-- 열어 놓고 보고 있는 파일이야말로 색인에 넣고 싶은 파일이기 때문이다 -
-- 트리에서 그 파일을 다시 찾아 내려가는 것은 같은 일을 두 번 하는 것이다.
--
--   +   커서 줄(또는 선택 영역)의 파일을 색인 목록에 넣는다
--   -   뺀다
--   =   지금 들어 있는지 본다
--
-- 들어 있는 파일에는 줄 끝에 빨간 ● 를 붙인다. BufExplorer 는 자기 버퍼를
-- 통째로 다시 그리므로 표시는 그릴 때마다 다시 얹는다.
--
--   g:projectfiles_bufexplorer = 0   이 기능을 끈다
--   g:projectfiles_bufexplorer_mark  표시 문자 (기본 '●')

if vim.g.loaded_projectfiles_bufexplorer then
  return
end
vim.g.loaded_projectfiles_bufexplorer = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local NS = api.nvim_create_namespace('projectfiles_bufexplorer')

local function on()
  local v = vim.g.projectfiles_bufexplorer
  return v == nil or (tonumber(v) or 1) ~= 0
end

local function is_bex(buf)
  return api.nvim_buf_get_name(buf):match('%[BufExplorer%]$') ~= nil
end

-- 줄 앞머리의 버퍼 번호로 실제 파일 경로를 얻는다. BufExplorer 가 보여
-- 주는 이름은 잘려 있을 수 있어서 줄을 파싱하지 않는다.
local function path_at(buf, lnum)
  local l = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
  local nr = tonumber(l:match('^%s*(%d+)'))
  if not nr or not api.nvim_buf_is_valid(nr) then
    return nil
  end
  local name = api.nvim_buf_get_name(nr)
  if name == '' or vim.bo[nr].buftype ~= '' then
    return nil
  end
  return vim.fn.fnamemodify(name, ':p')
end

local function paths_in_range(buf, a, b)
  local out = {}
  for l = math.min(a, b), math.max(a, b) do
    local p = path_at(buf, l)
    if p then
      out[#out + 1] = p
    end
  end
  return out
end

-- 표시는 트리와 같은 판정을 쓴다.
--
-- 처음에는 projectfiles_status() 를 봤는데, 그건 사람이 읽는 문장을
-- 돌려주므로 늘 비어 있지 않았다 - 모든 줄에 표시가 붙었다. 트리가 쓰는
-- projectfiles_tree_flag() 가 '이 파일이 preset 에 들어 있나'를 바로
-- 답하고, 표시 문자도 거기서 나온다(auto 모드는 전부 대상이라 빈 문자열).
local function mark(buf)
  pcall(api.nvim_buf_clear_namespace, buf, NS, 0, -1)
  if not on() or not _G.projectfiles_tree_flag then
    return
  end
  for l = 1, api.nvim_buf_line_count(buf) do
    local p = path_at(buf, l)
    if p then
      local ok, flag = pcall(_G.projectfiles_tree_flag, p)
      if ok and flag and flag ~= '' then
        pcall(api.nvim_buf_set_extmark, buf, NS, l - 1, 0, {
          virt_text = { { ' ' .. tostring(vim.g.projectfiles_bufexplorer_mark or flag),
                          'ProjectFilesIndexMark' } },
          virt_text_pos = 'eol',
        })
      end
    end
  end
end

local function act(buf, a, b, fn, label)
  local paths = paths_in_range(buf, a, b)
  if #paths == 0 then
    vim.notify('BufExplorer: 이 줄에는 파일이 없습니다', vim.log.levels.WARN)
    return
  end
  if not fn then
    vim.notify('projectfiles 가 없습니다', vim.log.levels.WARN)
    return
  end
  pcall(fn, paths)
  vim.notify(('색인 %s: %d개'):format(label, #paths))
  -- 추가/제거는 목록 파일을 다시 쓰고 색인까지 건드리므로, 표시는 그 뒤에
  -- 다시 그린다
  vim.defer_fn(function()
    if api.nvim_buf_is_valid(buf) then
      pcall(_G.projectfiles_tree_invalidate)
      mark(buf)
    end
  end, 120)
end

local function attach(buf)
  if not on() then
    return
  end
  local function bmap(lhs, rhs, desc)
    pcall(vim.keymap.set, { 'n', 'x' }, lhs, rhs,
      { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  bmap('+', function()
    local m = vim.fn.mode()
    local a, b = vim.fn.line('.'), vim.fn.line('.')
    if m == 'v' or m == 'V' then
      a, b = vim.fn.line('v'), vim.fn.line('.')
      api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    end
    act(buf, a, b, _G.projectfiles_add, '추가')
  end, '색인 목록에 추가')
  bmap('-', function()
    local m = vim.fn.mode()
    local a, b = vim.fn.line('.'), vim.fn.line('.')
    if m == 'v' or m == 'V' then
      a, b = vim.fn.line('v'), vim.fn.line('.')
      api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    end
    act(buf, a, b, _G.projectfiles_remove, '제거')
  end, '색인 목록에서 제거')
  bmap('=', function()
    local p = path_at(buf, vim.fn.line('.'))
    if not p then
      return
    end
    local ok, st = pcall(_G.projectfiles_status, p)
    vim.notify(('%s : %s'):format(vim.fn.fnamemodify(p, ':~:.'),
      (ok and st and st ~= '') and st or '색인에 없음'))
  end, '색인 상태 보기')
  mark(buf)
end

local group = api.nvim_create_augroup('ProjectFilesBufExplorer', { clear = true })
api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'TextChanged' }, {
  group = group,
  callback = function(a)
    if is_bex(a.buf) then
      vim.schedule(function()
        if api.nvim_buf_is_valid(a.buf) then
          attach(a.buf)
        end
      end)
    end
  end,
})
