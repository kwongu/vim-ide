-- projectfiles_neotree.lua - neo-tree 에서도 색인 목록을 고친다.
--
-- NERDTree 쪽(projectfiles_tree.vim)과 같은 키, 같은 동작이다:
--
--   +   커서 밑(또는 고른 범위)을 색인 목록에 담는다
--   -   뺀다
--   =   지금 담겨 있는지, 어느 .tags 에 담기는지 말한다
--
-- v / V / <C-v> 로 여러 줄을 고른 뒤 + 나 - 를 누르면 그 범위 전체에
-- 적용된다. 범위는 한 번의 커밋으로 처리된다(목록을 여러 번 다시 쓰지
-- 않는다) - projectfiles.lua 의 배치 경로를 그대로 쓴다.
--
-- 옵션은 NERDTree 쪽과 공유한다(키를 한 곳에서 바꾸면 둘 다 바뀐다):
--   g:projectfiles_tree_add_key      기본 '+'
--   g:projectfiles_tree_remove_key   기본 '-'
--   g:projectfiles_tree_info_key     기본 '='
--   g:projectfiles_neotree = 0       neo-tree 쪽만 끄기

if vim.g.loaded_projectfiles_neotree then
  return
end
vim.g.loaded_projectfiles_neotree = 1

if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api

local function enabled()
  return vim.g.projectfiles_neotree == nil or vim.g.projectfiles_neotree ~= 0
end

local function key(name, default)
  local v = vim.g['projectfiles_tree_' .. name .. '_key']
  return (v == nil or v == '') and default or tostring(v)
end

-- 이 창의 neo-tree 상태. 창으로 먼저 묻고, 안 되면 버퍼가 알려 주는
-- source 이름으로 묻는다(neo-tree 가 버퍼에 neo_tree_source 를 심는다).
local function tree_state()
  local ok, manager = pcall(require, 'neo-tree.sources.manager')
  if not ok then
    return nil
  end
  local ok2, st = pcall(manager.get_state_for_window, api.nvim_get_current_win())
  if ok2 and st and st.tree then
    return st
  end
  local src = vim.b.neo_tree_source
  if src then
    local ok3, st2 = pcall(manager.get_state, src)
    if ok3 and st2 and st2.tree then
      return st2
    end
  end
  return nil
end

local function path_at(state, lnum)
  local ok, node = pcall(function()
    return state.tree:get_node(lnum)
  end)
  if not ok or not node then
    return nil
  end
  -- 'message' 같은 안내 노드에는 경로가 없다
  local p = node.path
  if type(p) ~= 'string' or p == '' then
    return nil
  end
  return p
end

-- 범위의 줄들이 가리키는 경로. 같은 경로가 여러 줄에 걸쳐도 한 번만.
local function paths_in(first, last)
  local st = tree_state()
  if not st then
    return {}
  end
  local out, seen = {}, {}
  for l = math.min(first, last), math.max(first, last) do
    local p = path_at(st, l)
    if p and not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  return out
end

local function cursor_paths()
  local l = api.nvim_win_get_cursor(0)[1]
  return paths_in(l, l)
end

-- 비주얼 모드에서 고른 줄 범위. 'v' 마크는 아직 갱신되지 않았을 수 있어
-- line('v') 와 line('.') 을 쓴다.
local function visual_range()
  local a = vim.fn.line('v')
  local b = vim.fn.line('.')
  return math.min(a, b), math.max(a, b)
end

local function leave_visual()
  api.nvim_feedkeys(
    api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

local function act(paths, fn, what)
  if #paths == 0 then
    vim.notify('ProjectFiles: 경로가 있는 줄이 아닙니다', vim.log.levels.WARN)
    return
  end
  local ok, err = pcall(fn, paths)
  if not ok then
    vim.notify('ProjectFiles: ' .. what .. ' 실패 - ' .. tostring(err),
      vim.log.levels.ERROR)
  end
end

local function do_add(paths)
  act(paths, _G.projectfiles_add, '추가')
end

local function do_remove(paths)
  act(paths, _G.projectfiles_remove, '제거')
end

local function do_info()
  local p = cursor_paths()[1]
  if not p then
    vim.notify('ProjectFiles: 경로가 있는 줄이 아닙니다', vim.log.levels.WARN)
    return
  end
  vim.notify('ProjectFiles: ' .. tostring(_G.projectfiles_status(p)))
end

local function map_buf(buf)
  local function nmap(lhs, fn, desc)
    if lhs == '' then
      return
    end
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, desc = desc })
  end
  local function xmap(lhs, fn, desc)
    if lhs == '' then
      return
    end
    vim.keymap.set('x', lhs, fn, { buffer = buf, silent = true, desc = desc })
  end
  local ka, kr, ki = key('add', '+'), key('remove', '-'), key('info', '=')

  nmap(ka, function() do_add(cursor_paths()) end, 'ProjectFiles: 색인에 담기')
  nmap(kr, function() do_remove(cursor_paths()) end, 'ProjectFiles: 색인에서 빼기')
  nmap(ki, do_info, 'ProjectFiles: 이 경로의 색인 상태')

  -- 범위: 고른 줄 전체에 한 번의 커밋으로
  xmap(ka, function()
    local f, l = visual_range()
    leave_visual()
    vim.schedule(function() do_add(paths_in(f, l)) end)
  end, 'ProjectFiles: 고른 범위를 색인에 담기')
  xmap(kr, function()
    local f, l = visual_range()
    leave_visual()
    vim.schedule(function() do_remove(paths_in(f, l)) end)
  end, 'ProjectFiles: 고른 범위를 색인에서 빼기')
end

-- neo-tree 가 자기 매핑을 건 뒤에 걸어야 우리 것이 이긴다. FileType 이
-- neo-tree 의 매핑보다 먼저 올 수 있어서 한 틱 미룬다.
api.nvim_create_autocmd('FileType', {
  group = api.nvim_create_augroup('ProjectFilesNeotree', { clear = true }),
  pattern = 'neo-tree',
  callback = function(a)
    if not enabled() then
      return
    end
    vim.schedule(function()
      if api.nvim_buf_is_valid(a.buf) then
        pcall(map_buf, a.buf)
      end
    end)
  end,
})
