-- projectfiles_quickfix.lua - quickfix / location 목록에서 색인 목록을 고친다.
--
-- NERDTree, neo-tree, BufExplorer 에 이미 있는 기능이다. quickfix 에도 있어야
-- 하는 이유는 같다: :Gtags 나 <C-g> 가 찾아 준 그 파일들이야말로 지금 색인에
-- 넣고 싶은 파일이다 - 목록을 보고 트리에서 그 경로를 다시 찾아 내려가는 것은
-- 같은 일을 두 번 하는 것이다.
--
--   +   커서 줄(또는 선택 영역)의 파일을 색인 목록에 넣는다
--   -   뺀다
--   =   지금 들어 있는지 본다
--
-- 들어 있는 파일에는 줄 끝에 빨간 ● 를 붙인다. 목록이 다시 그려질 때마다
-- 표시도 다시 얹는다.
--
-- 한 파일이 여러 줄에 나오는 것이 quickfix 의 예사다(한 파일에서 열 곳을
-- 찾으면 열 줄). 영역을 골라 + 를 눌러도 같은 파일은 한 번만 넘긴다.
--
--   g:projectfiles_quickfix = 0    이 기능을 끈다
--   g:projectfiles_quickfix_mark   표시 문자 (기본은 트리와 같은 것)

if vim.g.loaded_projectfiles_quickfix then
  return
end
vim.g.loaded_projectfiles_quickfix = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local NS = api.nvim_create_namespace('projectfiles_quickfix')
local watched = {}   -- buf -> true (nvim_buf_attach 을 한 번만 건다)

local function on()
  local v = vim.g.projectfiles_quickfix
  return v == nil or (tonumber(v) or 1) ~= 0
end

-- 이 창이 들고 있는 목록. 위치 목록(:lopen)도 같이 받는다.
local function items_of(win)
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return {}
  end
  if info.loclist == 1 then
    return vim.fn.getloclist(win) or {}
  end
  return vim.fn.getqflist() or {}
end

-- 줄에서 경로를 얻는다. 줄 글자를 뜯지 않는다 - qfpath.lua 가 경로를
-- 프로젝트 루트 기준으로 줄여 놓기 때문에 화면 글자는 실제 경로가 아니다.
-- 목록의 n 번째 항목이 곧 n 번째 줄이다.
local function path_at(items, lnum)
  local e = items[lnum]
  if not e or not e.bufnr or e.bufnr <= 0 then
    return nil
  end
  if not api.nvim_buf_is_valid(e.bufnr) then
    return nil
  end
  local name = api.nvim_buf_get_name(e.bufnr)
  if name == '' then
    return nil
  end
  return vim.fn.fnamemodify(name, ':p')
end

-- 같은 파일이 여러 줄에 있어도 한 번만
local function paths_in_range(items, a, b)
  local out, seen = {}, {}
  for l = math.min(a, b), math.max(a, b) do
    local p = path_at(items, l)
    if p and not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  return out
end

local function mark(buf, win)
  pcall(api.nvim_buf_clear_namespace, buf, NS, 0, -1)
  if not on() or not _G.projectfiles_tree_flag then
    return
  end
  local items = items_of(win)
  local n = api.nvim_buf_line_count(buf)
  for l = 1, math.min(n, #items) do
    local p = path_at(items, l)
    if p then
      local ok, flag = pcall(_G.projectfiles_tree_flag, p)
      if ok and flag and flag ~= '' then
        pcall(api.nvim_buf_set_extmark, buf, NS, l - 1, 0, {
          virt_text = { { ' ' .. tostring(vim.g.projectfiles_quickfix_mark or flag),
                          'ProjectFilesIndexMark' } },
          virt_text_pos = 'eol',
        })
      end
    end
  end
end

-- 여러 프로젝트에 걸친 선택을 나눈다.
--
-- projectfiles_add/remove 는 paths[1] 의 프로젝트만 보고, 다른 프로젝트의
-- 경로는 경고만 내고 버린다(projectfiles.lua 의 tree_apply). 이 목록은
-- 프로젝트를 넘나드는 것이 예사라(헤더 하나가 다른 트리에서 온다) 여기서
-- 미리 갈라 프로젝트마다 한 번씩 부른다.
local function by_project(paths)
  local groups, order = {}, {}
  for _, p in ipairs(paths) do
    local ok, r = pcall(_G.projectfiles_root_of, p)
    local key = (ok and r) or ''
    if not groups[key] then
      groups[key] = {}
      order[#order + 1] = key
    end
    table.insert(groups[key], p)
  end
  return groups, order
end

-- 많이 뺄 때는 한 번 묻는다.
--
-- 마지막 항목까지 빠지면 preset 사본이 지워지고 그 프로젝트는 '색인하지
-- 않음'이 된다(projectfiles.lua 의 save_entries). 목록 전체를 골라 '-' 를
-- 누르는 것은 한 손짓이라, 그 한 손짓으로 색인이 통째로 꺼질 수 있다.
-- projectfiles 안쪽에도 확인이 있지만 배치로 부르면 경고만 하고 지나간다.
local function ok_to_drop(n)
  local lim = tonumber(vim.g.projectfiles_confirm_drop) or 20
  if lim <= 0 or n < lim then
    return true
  end
  -- confirm() 의 물음은 한 줄로 둔다. 줄바꿈을 넣었더니 한글이 잘려 나왔다
  -- (실측: '목록이 비면' 이 '목록이 비' 로).
  return vim.fn.confirm(
    ('색인 목록에서 %d개를 뺍니다. 목록이 비면 preset 이 지워지고 이 프로젝트는 색인하지 않게 됩니다.'):format(n),
    "빼기(&Y)\n그만두기(&N)", 2) == 1
end

local function act(buf, win, a, b, fn, label)
  local paths = paths_in_range(items_of(win), a, b)
  if #paths == 0 then
    vim.notify('quickfix: 이 줄에는 파일이 없습니다', vim.log.levels.WARN)
    return
  end
  if not fn then
    vim.notify('projectfiles 가 없습니다', vim.log.levels.WARN)
    return
  end
  if label == '제거' and not ok_to_drop(#paths) then
    return
  end
  local groups, order = by_project(paths)
  for _, key in ipairs(order) do
    pcall(fn, groups[key])
  end
  vim.notify(('색인 %s: %d개%s'):format(label, #paths,
    #order > 1 and (' (프로젝트 %d곳)'):format(#order) or ''))
  vim.defer_fn(function()
    if api.nvim_buf_is_valid(buf) and api.nvim_win_is_valid(win) then
      pcall(_G.projectfiles_tree_invalidate)
      mark(buf, win)
    end
  end, 120)
end

-- 세 가지 비주얼 모드를 모두 본다 (<C-v> 는 mode() 가 \22 를 준다)
local function visual_range()
  local m = vim.fn.mode()
  if m == 'v' or m == 'V' or m == '\22' then
    return vim.fn.line('v'), vim.fn.line('.'), true
  end
  local l = vim.fn.line('.')
  return l, l, false
end

local function leave_visual()
  api.nvim_feedkeys(
    api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

local function attach(buf, win)
  if not on() then
    return
  end
  local function bmap(lhs, rhs, desc)
    pcall(vim.keymap.set, { 'n', 'x' }, lhs, rhs,
      { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  local function ranged(fn, label)
    return function()
      local a, b, vis = visual_range()
      if vis then
        leave_visual()
      end
      local w = api.nvim_get_current_win()
      vim.schedule(function() act(buf, w, a, b, fn(), label) end)
    end
  end
  bmap('+', ranged(function() return _G.projectfiles_add end, '추가'),
    '색인 목록에 추가')
  bmap('-', ranged(function() return _G.projectfiles_remove end, '제거'),
    '색인 목록에서 제거')
  -- 목록이 바뀌어도 TextChanged 는 오지 않는다.
  --
  -- quickfix 버퍼는 사람이 고치는 것이 아니라 vim 이 쓴다. QuickFixCmdPost
  -- 도 :make/:grep 갈래에서만 오고, lua 에서 setqflist() 로 갈아 끼우면
  -- (relationview 의 lookup_to_qf 가 그렇다) 아무 신호가 없다. 창이 이미
  -- 열려 있는 채로 목록만 바뀌면 표시가 옛것으로 남는다. 줄이 바뀌는 것을
  -- 직접 듣는 것이 유일하게 확실한 길이다.
  if not watched[buf] then
    watched[buf] = true
    api.nvim_buf_attach(buf, false, {
      on_lines = function()
        vim.schedule(function()
          if not api.nvim_buf_is_valid(buf) then
            watched[buf] = nil
            return
          end
          for _, w in ipairs(api.nvim_list_wins()) do
            if api.nvim_win_is_valid(w) and api.nvim_win_get_buf(w) == buf then
              mark(buf, w)
              return
            end
          end
        end)
      end,
      on_detach = function() watched[buf] = nil end,
    })
  end
  bmap('=', function()
    local p = path_at(items_of(api.nvim_get_current_win()), vim.fn.line('.'))
    if not p then
      return
    end
    local ok, st = pcall(_G.projectfiles_status, p)
    vim.notify(('%s : %s'):format(vim.fn.fnamemodify(p, ':~:.'),
      (ok and st and st ~= '') and st or '색인에 없음'))
  end, '색인 상태 보기')
  mark(buf, win)
end

local group = api.nvim_create_augroup('ProjectFilesQuickfix', { clear = true })
api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'qf',
  callback = function(a)
    local win = api.nvim_get_current_win()
    vim.schedule(function()
      if api.nvim_buf_is_valid(a.buf) and api.nvim_win_is_valid(win) then
        attach(a.buf, win)
      end
    end)
  end,
})

-- 목록이 바뀌면(:Gtags 를 다시 돌리면) 표시도 다시
api.nvim_create_autocmd({ 'QuickFixCmdPost', 'BufWinEnter', 'TextChanged' }, {
  group = group,
  callback = function()
    vim.schedule(function()
      for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
        local b = api.nvim_win_get_buf(w)
        if vim.bo[b].buftype == 'quickfix' then
          mark(b, w)
        end
      end
    end)
  end,
})
