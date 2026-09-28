-- dirdiffpick.lua - neo-tree 에서 두 곳을 골라 비교한다 (\d 를 두 번)
--
-- 트리에서 비교할 첫 번째 디렉터리 위에서 \d , 두 번째 디렉터리 위에서 \d 를
-- 누르면 :DirDiff 가 새 탭에서 두 디렉터리를 비교한다 (dirdifftab.vim). 파일
-- 둘이면 새 탭에서 vimdiff 로 연다. 첫 번째를 고른 뒤 같은 줄에서 다시 \d 는
-- 취소. 트리가 달라도 된다(F9 트리에서 고르고 RelationView 트리에서 비교).
--
-- '=' 가 아닌 것은 트리의 = 가 이미 색인 목록 정보(projectfiles_neotree.lua)라서다.
-- neo-tree 매핑은 .vimrc 의 neo-tree window.mappings ['<leader>d'] 에 있다.

if vim.g.loaded_vimide_dirdiffpick then
  return
end
vim.g.loaded_vimide_dirdiffpick = 1

local levels = vim.log.levels
local first = nil -- { path = ..., kind = 'dir' | 'file' }

local function say(msg, level)
  (_G.vimide_notify or vim.notify)('비교: ' .. msg, level or levels.INFO)
end

local function short(p)
  return vim.fn.fnamemodify(p, ':~')
end

local function key()
  local l = vim.g.mapleader
  return (type(l) == 'string' and l ~= '' and l or '\\') .. 'd'
end

local function kind_name(kind)
  return kind == 'dir' and '디렉터리' or '파일'
end

-- 트리 창에서 :tabnew 하면 새 창이 트리의 창 옵션을 물려받고, neo-tree 가 그 창을
-- 제 것으로 알고 도로 가져간다 (dirdifftab.vim 과 같은 사정). EDIT 창으로 옮겨서
-- 열고, 그런 창이 없으면 새 창의 창 옵션을 전역값으로 되돌린다.
local PLAIN = { 'winhighlight', 'winfixwidth', 'winfixheight', 'number', 'relativenumber',
  'signcolumn', 'foldcolumn', 'cursorline', 'list', 'wrap', 'statuscolumn', 'winbar' }

local function tab_from_edit(cmd)
  local w = _G.vimide_edit_slot and _G.vimide_edit_slot()
  local moved = false
  if w and w ~= 0 and vim.api.nvim_win_is_valid(w) then
    vim.api.nvim_set_current_win(w)
    moved = true
  end
  vim.cmd(cmd)
  if not moved then
    for _, o in ipairs(PLAIN) do
      pcall(vim.cmd, 'setlocal ' .. o .. '<')
    end
  end
end

local function exists(kind, path)
  if kind == 'dir' then
    return vim.fn.isdirectory(path) == 1
  end
  return vim.fn.filereadable(path) == 1
end

function _G.vimide_dirdiff_pick(state)
  local ok, node = pcall(function()
    return state.tree:get_node()
  end)
  local path = ok and node and node.path
  local t = ok and node and node.type
  if not path or (t ~= 'directory' and t ~= 'file') then
    return say('디렉터리나 파일 줄에서 누르세요', levels.WARN)
  end
  local kind = t == 'directory' and 'dir' or 'file'
  -- buffers 소스의 이름 없는 버퍼는 path 가 '[No Name]' 이다
  if not exists(kind, path) then
    return say('디스크에 없는 ' .. kind_name(kind) .. '입니다: ' .. short(path), levels.WARN)
  end
  -- 먼저 고른 것이 그 사이 없어졌으면 버린다 (그 줄이 없어 같은 줄 취소도 못 한다)
  if first and not exists(first.kind, first.path) then
    say('먼저 고른 ' .. kind_name(first.kind) .. '가 없어져 버렸습니다: ' .. short(first.path), levels.WARN)
    first = nil
  end
  if not first then
    first = { path = path, kind = kind }
    return say(('첫 번째 %s: %s - 두 번째에서 %s (같은 줄에서 다시 누르면 취소)')
      :format(kind_name(kind), short(path), key()))
  end
  if first.path == path then
    first = nil
    return say('고른 것을 취소했습니다')
  end
  if first.kind ~= kind then
    return say(('%s는 %s와 비교합니다 - 첫 번째: %s (같은 줄에서 다시 누르면 취소)')
      :format(kind_name(first.kind), kind_name(first.kind), short(first.path)), levels.WARN)
  end
  local a = first.path
  first = nil
  if kind == 'dir' then
    -- :DirDiff 를 거치지 않고 바로 부른다 (VimIdeDirDiff 가 EDIT 창에서 새 탭을 연다)
    if vim.fn.exists('*VimIdeDirDiff') == 1 then
      vim.fn.VimIdeDirDiff(a, path)
    else
      say('dirdifftab.vim 이 없습니다', levels.WARN)
    end
  else
    tab_from_edit('tabnew ' .. vim.fn.fnameescape(a))
    vim.cmd('rightbelow vertical diffsplit ' .. vim.fn.fnameescape(path))
  end
end
