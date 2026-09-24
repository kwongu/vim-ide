-- reposearch.lua - \ff \fg \fi 를 '이 파일을 관리하는 git 저장소'에서 찾는다
--
--   \ff  파일 이름 찾기   (telescope find_files)
--   \fg  내용 찾기        (telescope live_grep)
--   \fi  커밋 목록        (telescope git_commits)
--
-- 기준 경로
--   편집 창        그 파일
--   neo-tree 창    커서 밑 항목 - 디렉터리 줄은 그 디렉터리, 파일 줄은 그
--                  파일이 든 디렉터리, 빈 줄은 트리의 루트. F9 왼쪽 트리,
--                  F11 뜬 트리, RelationView 의 트리 셋 다 같다 (.vimrc 의
--                  neo-tree window.mappings 에 건 같은 키가 커서 밑 항목을
--                  넘겨준다 - treesearch.lua 의 <C-g> <C-f> 와 같은 길).
--   그 밖의 창     마지막 편집 창의 파일 (RelationView 패널, quickfix ...)
--                  그것도 없으면 지금 디렉터리
-- 찾는 곳
--   기준 경로에서 위로 올라가며 처음 만나는 git 저장소의 맨 위.
--   저장소가 없으면 기준 경로 아래 (파일이면 그 파일이 든 디렉터리).
--   \fi 는 저장소가 없으면 볼 커밋이 없으니 알리고 끝난다.
--
-- 올라가다 멈추는 곳
--   .repo 가 있는 디렉터리   repo 도구로 받은 트리(안드로이드 SDK)의 맨 위다.
--                            git 저장소는 그 아래 프로젝트마다 따로 있고, 맨
--                            위의 .git 은 비어 있거나(실측: tsnd_2.0) 트리
--                            전체를 덮는 것이라, 거기까지 올라가면 SDK 전체
--                            (수십만 파일)를 뒤지게 된다. 프로젝트 밖의
--                            파일은 '저장소 없음'으로 본다.
--   홈 디렉터리              홈을 통째로 담은 저장소(dotfiles)가 있으면 홈
--                            아래 아무 파일에서나 홈 전체를 뒤지게 된다.
--   /                        끝
-- 커밋이 하나도 없는 .git(갓 'git init' 한 것, HEAD 만 있는 빈 디렉터리)과
-- 가리키는 곳이 사라진 gitfile 은 저장소로 치지 않고 더 올라간다. 개발서버에는
-- SDK 여럿을 담은 디렉터리에 빈 'git init' 이 있다(README) - 그것을 저장소로
-- 치면 SDK 전부(수백만 파일)를 뒤진다 (반대 심문).
--
-- 멈추는 곳은 '올라가기'만 막는다. 시작한 곳이 그 자리면:
--   SDK 맨 위(.repo)   그 아래 전체 (예전 \ff 가 SDK 루트에서 하던 것과 같다)
--   홈, 홈의 윗줄       맨 위 한 층만 (--max-depth 1). ~/.zshrc 에서 \fg 를
--   (/Users, /home), /  치면 홈 전체를 글자마다 뒤지게 된다 - 맥 홈에는
--                      OneDrive 폴더(Library/CloudStorage)가 있어 rg 가 읽는
--                      순간 클라우드 파일을 내려받는다. /Users 는 모든 사람의
--                      홈이다 (반대 심문).
--
-- 경로는 링크를 풀어서 본다. ~/.vimrc 는 ~/.vim-ide/.vimrc 로 가는 링크라,
-- 풀지 않으면 홈에서 멈춰 '저장소 없음'이 된다. nvim 은 버퍼 이름의
-- 디렉터리 링크는 풀지만 파일 링크는 풀지 않고, neo-tree 는 링크 줄에
-- 링크 자체의 경로를 준다 (반대 심문).

if vim.g.loaded_vimide_reposearch then
  return
end
vim.g.loaded_vimide_reposearch = 1

local api = vim.api
local uv = vim.uv or vim.loop
local WARN = vim.log.levels.WARN

local function readline(path)
  local fd = io.open(path, 'r')
  if not fd then
    return nil
  end
  local l = fd:read('*l')
  fd:close()
  return l and vim.trim(l) or nil
end

-- 이 git 디렉터리에 커밋이 하나라도 있는가. 프로세스는 띄우지 않는다.
--   HEAD 가 커밋 해시(repo 도구 프로젝트는 대개 이렇다)     있다
--   HEAD 가 'ref: refs/heads/X' 면 그 ref 가 있어야 있다  (낱 파일, 또는
--   packed-refs 안의 한 줄. worktree 는 commondir 쪽도 본다. reftable 은
--   읽지 않고 있다고 친다)
local function has_commit(gitdir)
  local head = readline(gitdir .. '/HEAD')
  if not head then
    return false
  end
  if head:match('^%x+$') and #head >= 40 then
    return true
  end
  local ref = head:match('^ref:%s*(%S+)')
  if not ref then
    return false
  end
  local dirs = { gitdir }
  local common = readline(gitdir .. '/commondir')
  if common and common ~= '' then
    dirs[#dirs + 1] = common:sub(1, 1) == '/' and common or (gitdir .. '/' .. common)
  end
  for _, d in ipairs(dirs) do
    if uv.fs_stat(d .. '/' .. ref) or uv.fs_stat(d .. '/reftable') then
      return true
    end
    local fd = io.open(d .. '/packed-refs', 'r')
    if fd then
      local want = ' ' .. ref
      for line in fd:lines() do
        if line:sub(-#want) == want then
          fd:close()
          return true
        end
      end
      fd:close()
    end
  end
  return false
end

-- '.git' 은 디렉터리이거나 'gitdir: <경로>' 한 줄이 든 파일이다 (worktree,
-- submodule, repo 도구의 새 배치). 어느 쪽이든 커밋이 있어야 저장소로 친다.
local function git_ok(g)
  local st = uv.fs_stat(g)
  if not st then
    return false
  end
  if st.type == 'directory' then
    return has_commit(g)
  end
  if st.type == 'file' then
    local l = readline(g)
    local target = l and l:match('^gitdir:%s*(.-)%s*$')
    if not target or target == '' then
      return false
    end
    if target:sub(1, 1) ~= '/' then
      target = vim.fn.fnamemodify(g, ':h') .. '/' .. target
    end
    -- 가리키는 곳이 사라진 gitfile(옮기거나 지운 worktree)이면 git 이
    -- '저장소가 아니다'라고 한다 - \fi 가 날것의 오류로 죽었다 (반대 심문)
    return has_commit((target:gsub('/+$', '')))
  end
  return false
end

-- 홈 디렉터리들. $HOME 이 링크(/home/u -> /export/home/u)여도 걸리도록
-- 실제 경로도 넣는다 - 버퍼 이름과 getcwd() 는 실제 경로다 (반대 심문).
local function homes()
  local out = {}
  for _, h in ipairs({ uv.os_homedir(), vim.env.HOME }) do
    if type(h) == 'string' and h ~= '' then
      out[(h:gsub('/+$', ''))] = true
      local r = uv.fs_realpath(h)
      if r then
        out[(r:gsub('/+$', ''))] = true
      end
    end
  end
  return out
end

-- 홈, 홈을 품은 디렉터리(/Users, /home), / 에서 시작했는가 - 그 아래
-- 전체를 뒤지지 않는다
local function top_dir(d)
  if d == '/' then
    return true
  end
  for h in pairs(homes()) do
    if h == d or vim.startswith(h, d .. '/') then
      return true
    end
  end
  return false
end

local function repo_root(dir)
  local homes = homes()
  local d = dir
  while d and d ~= '' and d ~= '/' and not homes[d] do
    if vim.fn.isdirectory(d .. '/.repo') == 1 then
      return nil
    end
    if git_ok(d .. '/.git') then
      return d
    end
    local up = vim.fn.fnamemodify(d, ':h')
    if up == d then
      return nil
    end
    d = up
  end
  return nil
end

-- 경로(파일이나 디렉터리) -> 그 자리의 디렉터리. 없는 파일(아직 저장 안
-- 한 새 파일)이면 든 디렉터리가 있을 때 그것.
local function dir_of(p)
  if type(p) ~= 'string' or p:sub(1, 1) ~= '/' then
    return nil
  end
  if p ~= '/' then
    p = (p:gsub('/+$', ''))
  end
  -- 링크를 푼다. 없는 파일(새 파일)은 resolve 가 그대로 돌려준다. 링크가
  -- 돌고 돌면(a -> b -> a) resolve 가 E655 로 죽는다 - 풀지 않고 쓴다.
  local okr, rp = pcall(vim.fn.resolve, p)
  if okr and type(rp) == 'string' and rp ~= '' then
    p = rp
  end
  if p ~= '/' then
    p = (p:gsub('/+$', ''))
  end
  if vim.fn.isdirectory(p) == 1 then
    return p
  end
  local d = vim.fn.fnamemodify(p, ':h')
  return vim.fn.isdirectory(d) == 1 and d or nil
end

-- 버퍼의 파일 경로. expand() 는 쓰지 않는다 - 경로가 'wildignore'
-- (*/tmp/*)에 걸리면 빈 글자를 준다.
local function buf_file(buf)
  if not buf or not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then
    return nil
  end
  local n = api.nvim_buf_get_name(buf)
  if n == '' then
    return nil
  end
  -- fugitive 로 연 옛 판(:Gedit HEAD~1:a.c)은 이름이 fugitive:///.../.git//<rev>/a.c
  -- 다. 작업 트리의 그 파일 경로로 돌려 그 저장소에서 찾게 한다.
  if n:match('^fugitive://') and vim.fn.exists('*FugitiveReal') == 1 then
    local ok, r = pcall(vim.fn.FugitiveReal, n)
    if ok and type(r) == 'string' and r:sub(1, 1) == '/' then
      n = r
    end
  end
  return vim.fn.fnamemodify(n, ':p')
end

-- 기준 디렉터리. state 는 neo-tree 의 mapping 함수가 넘겨준 것.
local function base_dir(state)
  if not state and vim.bo.filetype == 'neo-tree' then
    pcall(function()
      state = require('neo-tree.sources.manager').get_state_for_window(
        api.nvim_get_current_win())
    end)
  end
  if state then
    local d, p
    if type(_G.vimide_tree_target) == 'function' then
      local td, _, tp = _G.vimide_tree_target(state)
      d, p = td, tp
    else
      d = state.path
    end
    -- 항목 자체의 경로에서 시작한다: 링크 파일(~/.vimrc)이면 풀어서
    -- 가리키는 파일이 든 디렉터리로. 경로가 없는 줄(빈 줄)은 트리의 루트.
    d = dir_of(p) or dir_of(d)
    if d then
      return d
    end
  end
  local d = dir_of(buf_file(api.nvim_get_current_buf()))
  if d then
    return d
  end
  if type(_G.vimide_last_edit_win) == 'function' then
    local ok, w = pcall(_G.vimide_last_edit_win)
    if ok and type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w) then
      d = dir_of(buf_file(api.nvim_win_get_buf(w)))
      if d then
        return d
      end
    end
  end
  return vim.fn.getcwd()
end

local KINDS = {
  files = { fn = 'find_files', title = 'Find Files' },
  grep = { fn = 'live_grep', title = 'Live Grep' },
  commits = { fn = 'git_commits', title = 'Git Commits', need_repo = true },
}

--- kind = 'files' | 'grep' | 'commits'. state 는 neo-tree 에서 부를 때만.
function _G.vimide_repo_search(kind, state)
  local k = KINDS[kind]
  if not k then
    vim.notify('reposearch: 모르는 종류 - ' .. tostring(kind), WARN)
    return
  end
  local ok, builtin = pcall(require, 'telescope.builtin')
  if not ok then
    vim.notify('telescope 가 올라와 있지 않습니다', WARN)
    return
  end
  local dir = base_dir(state)
  local root = repo_root(dir)
  if k.need_repo and not root then
    vim.notify('git 저장소가 아닙니다 - ' .. vim.fn.fnamemodify(dir, ':~'), WARN)
    return
  end
  local cwd = root or dir
  local where = root and '[git]' or '[저장소 없음: 이 아래]'
  local o = { cwd = cwd }
  if kind == 'commits' then
    -- 점수가 같으면 git log 순서(최신이 위)를 지킨다. 기본 tiebreak 는 짧은
    -- 글자를 앞으로 올려서, 글자를 치는 순간 옛 커밋이 위로 올라왔다.
    o.tiebreak = function() return false end
  end
  if not root and top_dir(cwd) then
    -- 홈이나 / : 맨 위 한 층만. 숨김 파일(~/.zshrc 같은)이 바로 그 층의
    -- 것이다. hidden 은 find 로 떨어졌을 때 점 파일을 걸러 내지 않게,
    -- follow 는 링크인 점 파일(~/.vimrc -> ~/.vim-ide/.vimrc)도 보이게.
    where = '[저장소 없음: 맨 위 한 층만]'
    if kind == 'files' then
      o.hidden = true
      o.follow = true
      o.find_command = vim.fn.executable('rg') == 1
          and { 'rg', '--files', '--max-depth', '1' }
          or { 'find', '.', '-maxdepth', '1', '(', '-type', 'f', '-o', '-type', 'l', ')' }
    elseif kind == 'grep' then
      o.additional_args = { '--hidden', '--max-depth', '1' }
    end
  end
  o.prompt_title = ('%s  →  %s  %s'):format(k.title, vim.fn.fnamemodify(cwd, ':~'), where)
  -- 저장소처럼 보여도 git 이 거절하는 경우(다른 사람 체크아웃의 'dubious
  -- ownership' 등)가 있다. 날것의 오류 대신 한 줄로 알린다.
  local ok2, err = pcall(builtin[k.fn], o)
  if not ok2 then
    vim.notify(('%s 를 열 수 없습니다 - %s (%s)'):format(k.title,
      vim.fn.fnamemodify(cwd, ':~'), (tostring(err):gsub('^.-:%d+: ', ''))), WARN)
  end
end

api.nvim_create_user_command('VimIdeRepoSearch', function(o)
  _G.vimide_repo_search(o.args)
end, {
  nargs = 1,
  -- Lua 로 준 완성 함수는 친 글자로 걸러 주지 않는다 (customlist 와 같다)
  complete = function(lead)
    return vim.tbl_filter(function(k) return vim.startswith(k, lead) end,
      { 'files', 'grep', 'commits' })
  end,
  desc = '지금 파일을 관리하는 git 저장소에서 찾기 (없으면 그 경로 아래)',
})
