-- projectfiles_relationview.lua - RelationView 목록에서 색인 목록을 고친다.
--
-- NERDTree, neo-tree, BufExplorer, quickfix 에 이미 있는 기능이다. 관계
-- 목록에도 있어야 하는 이유는 같다: 지금 따라 읽고 있는 그 호출자/피호출자
-- 파일이야말로 색인에 넣고 싶은 파일이다.
--
--   i+   커서 줄(또는 선택 영역)의 파일을 색인 목록에 넣는다
--   i-   뺀다
--   i=   지금 들어 있는지 본다
--
-- 왜 '+' 가 아니라 'i+' 인가
--   이 패널에서 + 와 - 는 이미 트리 펼치기/접기다. 거기를 빼앗으면 관계
--   목록을 읽는 손버릇이 통째로 바뀐다. 그래서 'i'(index)를 앞에 붙였다 -
--   다른 창의 + / - / = 와 짝이 맞으면서 펼치기/접기는 그대로다.
--
-- 들어 있는 파일에는 줄 끝에 빨간 ● 를 붙인다. 목록이 다시 그려지면 표시도
-- 다시 얹는다. 파일이 없는 줄(머리글, 빈 줄)에는 아무것도 붙지 않는다.
--
-- 한 파일이 여러 줄에 나오는 것이 예사다(한 파일에서 열 곳을 부르면 열 줄).
-- 영역을 골라도 같은 파일은 한 번만 넘긴다.
--
--   g:projectfiles_relationview = 0    이 기능을 끈다
--   g:projectfiles_relationview_mark   표시 문자 (기본은 트리와 같은 것)
--   g:projectfiles_relationview_prefix 키 앞머리 (기본 'i')

if vim.g.loaded_projectfiles_relationview then
  return
end
vim.g.loaded_projectfiles_relationview = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local NS = api.nvim_create_namespace('projectfiles_relationview')
local watched = {}   -- buf -> true (nvim_buf_attach 을 한 번만 건다)

local function on()
  local v = vim.g.projectfiles_relationview
  return v == nil or (tonumber(v) or 1) ~= 0
end

local function path_at(lnum)
  if type(_G.relationview_path_at) ~= 'function' then
    return nil
  end
  local ok, p = pcall(_G.relationview_path_at, lnum)
  return ok and p or nil
end

local function paths_in_range(a, b)
  local out, seen = {}, {}
  for l = math.min(a, b), math.max(a, b) do
    local p = path_at(l)
    if p and not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  return out
end

local function mark(buf)
  pcall(api.nvim_buf_clear_namespace, buf, NS, 0, -1)
  if not on() or not _G.projectfiles_tree_flag then
    return
  end
  for l = 1, api.nvim_buf_line_count(buf) do
    local p = path_at(l)
    if p then
      local ok, flag = pcall(_G.projectfiles_tree_flag, p)
      if ok and flag and flag ~= '' then
        pcall(api.nvim_buf_set_extmark, buf, NS, l - 1, 0, {
          virt_text = { { ' ' .. tostring(vim.g.projectfiles_relationview_mark or flag),
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

local function act(buf, a, b, fn, label)
  local paths = paths_in_range(a, b)
  if #paths == 0 then
    vim.notify('RelationView: 이 줄에는 파일이 없습니다', vim.log.levels.WARN)
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
    if api.nvim_buf_is_valid(buf) then
      pcall(_G.projectfiles_tree_invalidate)
      mark(buf)
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

local function attach(buf)
  if not on() then
    return
  end
  local pre = tostring(vim.g.projectfiles_relationview_prefix or 'i')
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
      vim.schedule(function() act(buf, a, b, fn(), label) end)
    end
  end
  bmap(pre .. '+', ranged(function() return _G.projectfiles_add end, '추가'),
    '색인 목록에 추가')
  bmap(pre .. '-', ranged(function() return _G.projectfiles_remove end, '제거'),
    '색인 목록에서 제거')
  bmap(pre .. '=', function()
    local p = path_at(vim.fn.line('.'))
    if not p then
      return
    end
    local ok, st = pcall(_G.projectfiles_status, p)
    vim.notify(('%s : %s'):format(vim.fn.fnamemodify(p, ':~:.'),
      (ok and st and st ~= '') and st or '색인에 없음'))
  end, '색인 상태 보기')

  -- 패널은 프로그램이 다시 그린다(nvim_buf_set_lines). 사람이 고치는 것이
  -- 아니라 TextChanged 가 오지 않으므로, 줄이 바뀌는 것을 직접 듣는다.
  if not watched[buf] then
    watched[buf] = true
    api.nvim_buf_attach(buf, false, {
      on_lines = function()
        vim.schedule(function()
          if api.nvim_buf_is_valid(buf) then
            mark(buf)
          else
            watched[buf] = nil
          end
        end)
      end,
      on_detach = function() watched[buf] = nil end,
    })
  end
  mark(buf)
end

local group = api.nvim_create_augroup('ProjectFilesRelationView', { clear = true })
api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
  group = group,
  pattern = { 'relationview', '*' },
  callback = function(a)
    if vim.bo[a.buf].filetype ~= 'relationview' then
      return
    end
    vim.schedule(function()
      if api.nvim_buf_is_valid(a.buf) then
        attach(a.buf)
      end
    end)
  end,
})
