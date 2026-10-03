-- dirdiffpick.lua - neo-tree 에서 두 곳을 골라 비교한다 (Tab 두 번, \d 도 같다)
--
-- 트리에서 비교할 첫 번째 디렉터리(또는 파일) 위에서 Tab 을 누르면 그 줄 끝에 [A] 가
-- 붙고, 두 번째 위에서 Tab 을 누르면 [B] 로 삼아 곧바로 비교 창을 띄운다: 디렉터리
-- 둘이면 DirDiff(나란한 트리, dirdiffview.lua), 파일 둘이면 새 탭에서 vimdiff. [A] 를
-- 고른 뒤 같은 줄에서 다시 Tab 은 취소. 트리가 달라도 된다(F9 트리에서 고르고
-- RelationView 트리에서 비교).
--
-- Tab 은 neo-tree 기본의 select(여러 줄 골라 두기)였다 - vim-ide 는 그것을 쓰지 않고,
-- 여러 줄은 V 로 골라도 된다. '=' 가 아닌 것은 트리의 = 가 이미 색인 목록
-- 정보(projectfiles_neotree.lua)라서다. neo-tree 매핑은 .vimrc 의 neo-tree
-- window.mappings ['<Tab>'] / ['<leader>d'] 에 있다.

if vim.g.loaded_vimide_dirdiffpick then
  return
end
vim.g.loaded_vimide_dirdiffpick = 1

local levels = vim.log.levels
local api = vim.api
local first = nil -- { path = ..., kind = 'dir' | 'file' }
local ns = api.nvim_create_namespace('vimide_dirdiff_pick')

api.nvim_set_hl(0, 'VimIdeDirDiffPickA', { link = 'Search', default = true })
api.nvim_create_autocmd('ColorScheme', {
  group = api.nvim_create_augroup('VimIdeDirDiffPick', { clear = true }),
  callback = function()
    api.nvim_set_hl(0, 'VimIdeDirDiffPickA', { link = 'Search', default = true })
  end,
})

-- 고른 [A] 를 트리 줄 끝에 보인다. 그릴 때마다(decoration provider) 그 창의 트리에서
-- [A] 노드의 줄을 찾아 단다 - 버퍼에 표시를 박아 두면, neo-tree 가 접기·펼치기·git 표시
-- 갱신 때 줄을 통째로 갈아 끼우면서 (그린 뒤 알림 AFTER_RENDER 도 없이) 표시가 다른 줄로
-- 밀렸다. 그 노드가 펼쳐져 보일 때만 (get_node(id) 가 줄 번호를 준다). neo-tree 모듈은
-- 부르지 않고 이미 불린 것만 본다
local function state_of(buf)
  local mgr = package.loaded['neo-tree.sources.manager']
  if not mgr then
    return nil
  end
  for _, st in ipairs(mgr._get_all_states()) do
    if st.bufnr == buf and st.tree then
      return st
    end
  end
end

-- 표시를 어디에 다나. 줄이 창 끝까지 차는 일이 흔하다 - neo-tree 는 오른쪽에 붙이는 것
-- (크기·날짜 열, git 표시)이 있으면 줄을 창 너비까지 채우고, 긴 이름은 창 끝에서 자른다.
-- 그런 줄에 줄 끝(eol) 표시를 달면 창 밖이라 보이지 않았다 (RelationView 트리, 깊은
-- 커널 경로, 루트 줄)
--   이름 바로 뒤가 빈칸이면       이름 뒤에 겹쳐 쓴다
--   줄 끝 뒤에 자리가 있으면      줄 끝에 (nvim 이 한 칸 띄워 단다)
--   아니면                        창 오른쪽 끝에 겹쳐 쓴다 (잘린 이름의 꼬리를 덮는다)
local function place(win, line, name)
  local _, e = line:find(name or '\0', 1, true)
  if e and line:sub(e + 1, e + 5) == '     ' then
    return e, { virt_text_pos = 'overlay' }, ' [A]'
  end
  local info = vim.fn.getwininfo(win)[1] or {}
  local width = api.nvim_win_get_width(win) - (info.textoff or 0)
  if vim.fn.strdisplaywidth(line) + 4 <= width then
    return 0, { virt_text_pos = 'eol' }, '[A]'
  end
  return 0, { virt_text_pos = 'overlay', virt_text_win_col = math.max(0, width - 4) }, ' [A]'
end

api.nvim_set_decoration_provider(ns, {
  on_win = function(_, win, buf, top, bot)
    if not first or vim.bo[buf].filetype ~= 'neo-tree' then
      return false
    end
    pcall(function()
      local node, lnum = state_of(buf).tree:get_node(first.path)
      if not (lnum and lnum - 1 >= top and lnum - 1 <= bot) then
        return
      end
      local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
      local col, opts, text = place(win, line, node.name)
      opts.virt_text = { { text, 'VimIdeDirDiffPickA' } }
      opts.hl_mode = 'combine'
      opts.ephemeral = true
      api.nvim_buf_set_extmark(buf, ns, lnum - 1, col, opts)
    end)
    return false
  end,
})

-- 고른 것이 바뀌면 트리 창들을 다시 그리게 한다 (바뀌지 않은 창은 다시 그리지 않으므로)
local function mark_all()
  for _, w in ipairs(api.nvim_list_wins()) do
    local b = api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == 'neo-tree' then
      if not pcall(api.nvim__redraw, { win = w, valid = false }) then
        vim.cmd('redraw!')
        return
      end
    end
  end
end

local function say(msg, level)
  (_G.vimide_notify or vim.notify)('비교: ' .. msg, level or levels.INFO)
end

local function short(p)
  return vim.fn.fnamemodify(p, ':~')
end

local function key()
  return 'Tab'
end

local function kind_name(kind)
  return kind == 'dir' and '디렉터리' or '파일'
end

-- 조사가 붙은 이름 ('파일' 은 받침이 있다)
local JOSA = {
  dir = { topic = '디렉터리는', with = '디렉터리와', subj = '디렉터리가' },
  file = { topic = '파일은', with = '파일과', subj = '파일이' },
}

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
  -- [A] 줄에서 다시 누르면 취소. 디스크에서 없어졌어도 - 파일 감시를 꺼 두어
  -- (use_libuv_file_watcher) 밖에서 지운 줄은 R 로 새로 고칠 때까지 트리에 남는다
  if first and first.path == path then
    first = nil
    mark_all()
    return say('고른 것을 취소했습니다')
  end
  -- buffers 소스의 이름 없는 버퍼는 path 가 '[No Name]' 이다
  if not exists(kind, path) then
    return say('디스크에 없는 ' .. kind_name(kind) .. '입니다: ' .. short(path), levels.WARN)
  end
  -- 먼저 고른 것이 그 사이 없어졌으면 버리고 이것을 [A] 로
  if first and not exists(first.kind, first.path) then
    say('먼저 고른 ' .. JOSA[first.kind].subj .. ' 없어져 버렸습니다: ' .. short(first.path), levels.WARN)
    first = nil
    mark_all()
  end
  if not first then
    first = { path = path, kind = kind }
    mark_all()
    return say(('[A] %s: %s - 비교할 곳에서 %s ([B]). 같은 줄에서 다시 누르면 취소')
      :format(kind_name(kind), short(path), key()))
  end
  if first.kind ~= kind then
    return say(('%s %s 비교합니다 - [A]: %s (같은 줄에서 다시 누르면 취소)')
      :format(JOSA[first.kind].topic, JOSA[first.kind].with, short(first.path)), levels.WARN)
  end
  local a = first.path
  first = nil
  mark_all()
  if kind == 'dir' then
    -- :DirDiff 를 거치지 않고 바로 부른다 (VimIdeDirDiff 가 EDIT 창에서 새 탭을 연다)
    if _G.vimide_dirdiff_open and (tonumber(vim.g.vimide_dirdiff_view) or 1) ~= 0 then
      _G.vimide_dirdiff_open(a, path)
    elseif vim.fn.exists('*VimIdeDirDiff') == 1 then
      vim.fn.VimIdeDirDiff(a, path)
    else
      say('dirdifftab.vim 이 없습니다', levels.WARN)
    end
  else
    tab_from_edit('tabnew ' .. vim.fn.fnameescape(a))
    vim.cmd('rightbelow vertical diffsplit ' .. vim.fn.fnameescape(path))
  end
end
