-- reposearch.lua - \ff \fg \fi 를 '이 파일을 관리하는 git 저장소'에서 찾는다
--
--   \ff  파일 이름 찾기   (telescope find_files)
--   \fg  내용 찾기        (telescope live_grep)
--   \fi  커밋 목록        (telescope git_commits)
--
-- 기준 경로
--   편집 창        그 파일
--   그 밖의 창     마지막 편집 창의 파일 (RelationView 패널, quickfix ...)
--                  그것도 없으면 지금 디렉터리
-- 찾는 곳
--   기준 경로에서 위로 올라가며 처음 만나는 git 저장소의 맨 위.
--   저장소가 없으면 기준 경로 아래 (파일이면 그 파일이 든 디렉터리).
--   \fi 는 저장소가 없으면 볼 커밋이 없으니 알리고 끝난다.
--
-- neo-tree 창에서는 커서 밑 항목 '그것만' 찾는다 (저장소 전체가 아니다)
--   디렉터리 줄    \ff \fg 는 그 디렉터리 아래, \fi 는 그 아래를 바꾼 커밋만
--   파일 줄        \ff 는 그 파일 하나, \fg 는 그 파일 안, \fi 는 그 파일을
--                  바꾼 커밋만 (이름이 바뀐 것을 따라간다 - --follow)
--   빈 줄·안내 줄  트리의 루트를 디렉터리 줄처럼
--   트리에서 항목을 골라 누르는 것 자체가 '여기만 보겠다'는 뜻이다 - 저장소
--   전체는 편집 창에서 누르면 된다. F9 왼쪽 트리, F11 뜬 트리, RelationView 의
--   트리, \D 의 고르기 트리 모두 같다 (.vimrc 의 neo-tree window.mappings 에 건
--   같은 키가 커서 밑 항목을 넘겨준다 - treesearch.lua 의 <C-g> <C-f> 와 같은 길).
--   \fi 의 저장소는 그 항목을 품은 가장 안쪽 저장소다 (submodule, 저장소 안의
--   저장소는 그 안쪽 것). 항목이 저장소의 맨 위면 저장소 전체와 같다. 미리보기의
--   diff 도 그 경로만 보인다 - 다만 이름이 바뀌기 전 커밋은 미리보기가 비어 보일
--   수 있다 (미리보기는 지금 이름으로 거른다. 목록에는 다 나온다).
--   찾는 동안 키는 바로 돌아온다 - 목록은 git/rg 가 내놓는 대로 뒤에서 찬다.
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
    -- HEAD 가 가리키는 가지가 아직 없어도(orphan 가지로 막 옮김) 다른 가지에
    -- 커밋이 있으면 저장소다 (QA). 갓 git init 한 것은 refs/heads 가 비어 있다.
    local sd = uv.fs_scandir(d .. '/refs/heads')
    if sd and uv.fs_scandir_next(sd) then
      return true
    end
    local fd = io.open(d .. '/packed-refs', 'r')
    if fd then
      for line in fd:lines() do
        -- 주석(# pack-refs ...)과 벗긴 태그(^...) 줄이 아니면 ref 가 하나 있다
        if line ~= '' and not line:match('^[#^]') then
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
  -- 아직 없는 디렉터리의 새 파일(:e newdir/x.c)이면 가장 가까운 있는 윗
  -- 디렉터리에서 시작한다 - 예전에는 nvim 의 cwd 로 떨어졌다 (QA).
  local d = vim.fn.fnamemodify(p, ':h')
  local guard = 0
  while d ~= '/' and vim.fn.isdirectory(d) ~= 1 and guard < 64 do
    d = vim.fn.fnamemodify(d, ':h')
    guard = guard + 1
  end
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

-- neo-tree 에서 불렸으면 찾을 범위 = 커서 밑 항목. state 는 neo-tree 의
-- mapping 함수가 넘겨준 것(:VimIdeRepoSearch 를 트리 창에서 치면 여기서 얻는다).
--   { path = 항목의 경로(링크면 링크 그대로), dir = 디렉터리 줄이면 그 경로,
--     파일 줄이면 든 디렉터리, file = 파일 줄이면 true }
-- 경로가 없는 줄(빈 줄, '(3 hidden items)')은 트리의 루트를 디렉터리 줄처럼.
-- neo-tree 창이 아니면 nil.
local function tree_scope(state)
  if not state and vim.bo.filetype == 'neo-tree' then
    pcall(function()
      state = require('neo-tree.sources.manager').get_state_for_window(
        api.nvim_get_current_win())
    end)
  end
  if not state then
    return nil
  end
  local d, p
  if type(_G.vimide_tree_target) == 'function' then
    local td, _, tp = _G.vimide_tree_target(state)
    d, p = td, tp
  else
    d = state.path
  end
  if type(p) == 'string' and p:sub(1, 1) == '/' then
    if p ~= '/' then
      p = (p:gsub('/+$', ''))
    end
    -- 디렉터리를 가리키는 링크 줄도 디렉터리다 (isdirectory 는 링크를 따라간다)
    if vim.fn.isdirectory(p) == 1 then
      return { path = p, dir = p }
    end
    return { path = p, dir = vim.fn.fnamemodify(p, ':h'), file = true }
  end
  if type(d) == 'string' and d:sub(1, 1) == '/' and vim.fn.isdirectory(d) == 1 then
    return { path = d, dir = d }
  end
  return nil
end

-- 기준 디렉터리 (neo-tree 밖에서 부를 때)
local function base_dir()
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

-- 알림에 넣는 경로. 줄이 넘치면 Press ENTER 가 뜨므로 길면 줄여 쓴다 (QA).
local function short(p)
  local t = vim.fn.fnamemodify(p, ':~')
  local room = math.max(20, (tonumber(vim.v.echospace) or 80) - 40)
  if vim.fn.strdisplaywidth(t) > room then
    t = vim.fn.pathshorten(t)
  end
  return t
end

local KINDS = {
  files = { fn = 'find_files', title = 'Find Files' },
  grep = { fn = 'live_grep', title = 'Live Grep' },
  commits = { fn = 'git_commits', title = 'Git Commits', need_repo = true },
}

-- 홈이나 / : 맨 위 한 층만. 숨김 파일(~/.zshrc 같은)이 바로 그 층의 것이다.
-- hidden 은 find 로 떨어졌을 때 점 파일을 걸러 내지 않게, follow 는 링크인 점
-- 파일(~/.vimrc -> ~/.vim-ide/.vimrc)도 보이게.
local function one_level(kind, o)
  if kind == 'files' then
    o.hidden = true
    o.follow = true
    o.find_command = vim.fn.executable('rg') == 1
        and { 'rg', '--files', '--max-depth', '1' }
        or { 'find', '.', '-maxdepth', '1', '(', '-type', 'f', '-o', '-type', 'l', ')' }
  elseif kind == 'grep' then
    -- --follow: 링크인 점 파일(~/.vimrc)도 찾는다 (--max-depth 1 이라 링크된
    -- 디렉터리 안으로 들어가지는 않는다)
    o.additional_args = { '--hidden', '--follow', '--max-depth', '1' }
  end
end

-- git 을 뒤에서 돌리고 끝나면 cb(결과)를 본 스레드에서. 경로는 늘 글자 그대로.
local function git_async(root, args, cb)
  local cmd = { 'git', '-c', 'core.quotepath=off', '--literal-pathspecs' }
  vim.list_extend(cmd, args)
  local ok, err = pcall(vim.system, cmd, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      cb(r)
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb({ code = -1, stdout = '', stderr = tostring(err) })
    end)
  end
end

local function git_err(r)
  local m = vim.trim((r.stderr or ''):match('[^\n]*') or ''):gsub('^fatal:%s*', ''):gsub('^error:%s*', '')
  return vim.fn.strcharpart(m, 0, 60)
end

-- NUL 로 나눈 글자 -> 표
local function nul_split(s)
  local t = {}
  for p in (s or ''):gmatch('[^%z]+') do
    t[#t + 1] = p
  end
  return t
end

-- 알림은 한 줄에 들어가게: 넘치면 Press ENTER 가 떠서 다음 키를 먹는다. 덧붙일 말(hint)은
-- 자리가 있을 때만 붙인다.
local function say(msg, hint, level)
  local room = (tonumber(vim.v.echospace) or 80) - 1
  if hint and vim.fn.strdisplaywidth(msg .. hint) <= room then
    msg = msg .. hint
  end
  if vim.fn.strdisplaywidth(msg) > room then
    msg = vim.fn.strcharpart(msg, 0, math.max(10, room - 1)) .. '…'
  end
  vim.notify(msg, level or vim.log.levels.INFO)
end

-- 트리에서 연 \fi 의 Enter: 그 커밋으로 '그 경로만' 체크아웃한다. 저장소의 나머지와
-- HEAD 는 그대로다 (편집 창의 \fi 의 Enter 는 예전대로 저장소 전체 git checkout).
--   git restore --source=<커밋> --staged --worktree -- <경로>
-- 인덱스와 작업 트리의 그 경로를 그 커밋의 내용과 똑같이 만든다 - 그 커밋 뒤에 생긴
-- (추적 중인) 파일은 지워진다. git checkout <커밋> -- <경로> 는 그런 파일을 남겨서
-- '그 커밋의 내용'이 되지 않는다. 결과는 HEAD 에 견준 스테이징된 변경으로 보인다.
-- 덮어쓰기 전에 본다 (git 은 경로 체크아웃에서는 고친 것을 묻지 않고 덮는다):
--   그 커밋에 그 경로가 없으면    하지 않는다 - 파일은 이름이 바뀌기 전 커밋(목록은
--                                 --follow 라 나온다), 디렉터리는 통째로 지운 커밋.
--                                 그대로 하면 지금 것을 지운다.
--   커밋하지 않은 변경이 있으면   몇 개인지 보이고 묻는다 (기본: 아니오). 추적 중인
--                                 파일의 변경과, 그 커밋에 있는 이름의 새 파일(덮인다).
-- git 은 모두 뒤에서 돈다 - 커널 트리의 디렉터리라도 키는 바로 돌아온다.
--
-- head = true 는 Ctrl+h (HEAD 로 되돌리기): 같은 일을 HEAD 에서 한다. 앞서 Enter 로 바꾼
-- 것(스테이징된 변경으로 남아 있다)과 그 경로에서 고친 것을 거두고 지금 커밋된 내용으로
-- 돌린다. 이미 HEAD 와 같으면 아무것도 하지 않는다. 고친 것이 있으면 Enter 와 같이 묻는다.
local function path_checkout(root, rel, commit, subject, head)
  local label = commit .. (subject and subject ~= '' and (' "' .. vim.fn.strcharpart(subject, 0, 30) .. '"') or '')
  -- 알림에는 저장소 안의 경로 (picker 제목과 같다). 저장소는 제목에 이미 보였다.
  local where = rel
  local function restore()
    vim.api.nvim_echo({ { ('%s → %s %s하는 중...'):format(where, commit, head and '되돌리기' or '체크아웃') } }, false, {})
    git_async(root, { 'restore', '--source=' .. commit, '--staged', '--worktree', '--', rel }, function(r)
      if r.code ~= 0 then
        say(('%s 못했습니다 - %s (%s)'):format(head and '되돌리지' or '체크아웃하지', where, git_err(r)), nil, WARN)
        return
      end
      -- 열어 둔 그 파일들을 다시 읽는다 (고친 버퍼는 nvim 이 묻는다)
      pcall(vim.cmd, 'checktime')
      if head then
        say(('%s 를 HEAD 로 되돌렸습니다'):format(where))
      else
        say(('%s 만 %s 로 체크아웃 (나머지·HEAD 그대로)'):format(where, commit),
          '  되돌리기: 이 창에서 Ctrl+h')
      end
    end)
  end
  local function ask(n)
    if n == 0 then
      if head then
        say(('%s 는 이미 HEAD 와 같습니다'):format(where))
        return
      end
      restore()
      return
    end
    local ch = vim.fn.confirm(('%s 에 커밋하지 않은 변경이 %d개 있습니다.\n%s 의 내용으로 덮어쓰면 '
      .. '그 변경은 사라집니다. 덮어쓸까요?'):format(where, n, label), '&Yes\n&No', 2)
    -- 묻는 글이 여러 줄이라 그대로 두면 다음 알림이 Press ENTER 를 부른다 - 화면을 다시 그려
    -- 줄을 거둔다
    vim.cmd('redraw')
    if ch == 1 then
      restore()
    else
      say((head and '되돌리지 않았습니다 - ' or '체크아웃하지 않았습니다 - ') .. where)
    end
  end
  git_async(root, { 'cat-file', '-e', commit .. ':' .. rel }, function(r0)
    if r0.code ~= 0 then
      if head then
        say(('HEAD 에는 %s 가 없어 되돌리지 않았습니다 (아직 커밋된 적 없는 경로)'):format(where), nil, WARN)
      else
        say(('%s 에는 %s 가 없어 체크아웃하지 않았습니다'):format(commit, where),
          ' (이름이 바뀌기 전이거나 지운 커밋)', WARN)
      end
      return
    end
    git_async(root, { 'status', '--porcelain', '-z', '--untracked-files=all', '--', rel }, function(r)
      if r.code ~= 0 then
        say(('체크아웃하지 못했습니다 - %s (%s)'):format(where, git_err(r)), nil, WARN)
        return
      end
      local tracked, untracked = 0, {}
      local t = nul_split(r.stdout)
      local i = 1
      while i <= #t do
        local xy, name = t[i]:sub(1, 2), t[i]:sub(4)
        if xy == '??' then
          untracked[#untracked + 1] = name
        elseif xy ~= '!!' then
          tracked = tracked + 1
          -- 이름 바꿈·복사는 옛 이름이 다음 칸에 따로 온다
          if xy:find('[RC]') then
            i = i + 1
          end
        end
        i = i + 1
      end
      if #untracked == 0 then
        ask(tracked)
        return
      end
      -- 새 파일은 그 커밋에 같은 이름이 있을 때만 덮인다
      git_async(root, { 'ls-tree', '-r', '-z', '--name-only', commit, '--', rel }, function(r2)
        local hit = 0
        if r2.code == 0 then
          local in_tree = {}
          for _, p in ipairs(nul_split(r2.stdout)) do
            in_tree[p] = true
          end
          for _, p in ipairs(untracked) do
            if in_tree[p] then
              hit = hit + 1
            end
          end
        else
          hit = #untracked
        end
        ask(tracked + hit)
      end)
    end)
  end)
end

-- 트리에서 연 \fi 의 키: Enter 는 위의 경로 체크아웃, Ctrl+h 는 그 경로를 HEAD 로
-- 되돌리기 (고른 줄과 상관없다). <C-r>m/s/h(git reset)는 저장소 전체를 되돌리는 것이라
-- 이 창에서는 막는다 - 범위만 보는 창에서 범위 밖이 바뀐다.
-- Ctrl+h 는 입력 칸에서도 먹는다. Backspace 가 ^H 를 보내는 터미널이면 지우기 대신 이것이
-- 되지만, 고친 것이 있으면 묻고 없으면 하는 일이 없다 (iTerm2 기본값은 ^? 라 겹치지 않는다).
local function scoped_commit_keys(root, rel)
  return function(prompt_bufnr, map)
    local actions = require('telescope.actions')
    local astate = require('telescope.actions.state')
    actions.select_default:replace(function()
      local e = astate.get_selected_entry()
      actions.close(prompt_bufnr)
      if e and type(e.value) == 'string' and e.value ~= '' then
        path_checkout(root, rel, e.value, e.msg)
      end
    end)
    map({ 'i', 'n' }, '<c-h>', function()
      actions.close(prompt_bufnr)
      path_checkout(root, rel, 'HEAD', nil, true)
    end, { desc = '이 경로를 HEAD 로 되돌리기' })
    local function no_reset()
      say('트리에서 연 \\fi 에서는 <C-r>m/s/h(저장소 전체 reset)를 쓰지 않습니다', ' - 편집 창의 \\fi 에서', WARN)
    end
    for _, k in ipairs({ '<c-r>m', '<c-r>s', '<c-r>h' }) do
      map({ 'i', 'n' }, k, no_reset)
    end
    return true
  end
end

-- neo-tree 에서: 커서 밑 항목(sc)만 찾는 telescope 옵션.
-- 돌려주는 것: 옵션, 제목에 보일 경로, 꼬리표. 못 찾으면 알리고 nil.
local function scoped_opts(kind, sc)
  if kind == 'commits' then
    -- 링크는 풀어서 가리키는 쪽의 저장소와 경로로 (~/.vimrc -> ~/.vim-ide/.vimrc).
    -- 저장소는 그 항목을 품은 가장 안쪽 것 - 위로 올라가며 처음 만나는 .git 이다.
    local real = dir_of(sc.path)
    if sc.file then
      local okr, rp = pcall(vim.fn.resolve, sc.path)
      real = okr and type(rp) == 'string' and rp ~= '' and rp or sc.path
    end
    local root = real and repo_root(sc.file and vim.fn.fnamemodify(real, ':h') or real)
    if not root then
      vim.notify('git 저장소가 아닙니다 - ' .. short(sc.path), WARN)
      return nil
    end
    local o = { cwd = root }
    if real == root then
      return o, vim.fn.fnamemodify(root, ':~'), '[git: 저장소 전체]'
    end
    -- 저장소 맨 위에서 본 경로. git 은 맨 위에서 돌고(telescope 가 cwd 를 맨 위로
    -- 옮긴다) 미리보기도 같은 경로로 거른다(current_file). --literal-pathspecs:
    -- 이름에 * ? [ 나 맨 앞 : 이 있어도 그 이름 하나만 (pathspec 로 읽히지 않게).
    local rel = vim.startswith(real, root .. '/') and real:sub(#root + 2) or real
    local cmd = { 'git', '--literal-pathspecs', 'log', '--pretty=oneline', '--abbrev-commit' }
    if sc.file and tonumber(vim.g.vimide_tree_commits_follow or 1) ~= 0 then
      cmd[#cmd + 1] = '--follow'
    end
    cmd[#cmd + 1] = '--'
    cmd[#cmd + 1] = rel
    o.git_command = cmd
    o.current_file = rel
    o.attach_mappings = scoped_commit_keys(root, rel)
    return o, rel, ('[git: %s · Enter: 이 경로만 체크아웃 · ^h: HEAD 로]'):format(vim.fn.fnamemodify(root, ':~'))
  end
  if sc.file then
    if not uv.fs_stat(sc.path) then
      -- git_status 소스의 지운 파일 줄 같은 것
      vim.notify('그런 파일이 없습니다 - ' .. short(sc.path), WARN)
      return nil
    end
    -- 그 파일이 든 디렉터리에서 그 파일 하나만. rg 는 이름을 직접 주면 숨김·
    -- .gitignore 와 상관없이 읽는다. 맨 앞 - 는 rg 가 선택지로, 맨 앞 ~ 는
    -- telescope(search_dirs)가 홈으로 읽으니 ./ 를 붙인다.
    local name = vim.fn.fnamemodify(sc.path, ':t')
    if name:match('^[~-]') then
      name = './' .. name
    end
    return { cwd = sc.dir, search_dirs = { name } },
        vim.fn.fnamemodify(sc.path, ':~'), '[이 파일만]'
  end
  local o = { cwd = sc.dir }
  if top_dir(sc.dir) then
    one_level(kind, o)
    return o, vim.fn.fnamemodify(sc.dir, ':~'), '[맨 위 한 층만]'
  end
  return o, vim.fn.fnamemodify(sc.dir, ':~'), '[이 아래만]'
end

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
  local o, shown, where
  local sc = tree_scope(state)
  if sc then
    o, shown, where = scoped_opts(kind, sc)
    if not o then
      return
    end
  else
    local dir = base_dir()
    local root = repo_root(dir)
    if k.need_repo and not root then
      vim.notify('git 저장소가 아닙니다 - ' .. short(dir), WARN)
      return
    end
    o = { cwd = root or dir }
    shown = vim.fn.fnamemodify(o.cwd, ':~')
    where = root and '[git]' or '[저장소 없음: 이 아래]'
    if not root and top_dir(o.cwd) then
      one_level(kind, o)
      where = '[저장소 없음: 맨 위 한 층만]'
    end
  end
  local cwd = o.cwd
  if kind == 'commits' then
    -- 점수가 같으면 git log 순서(최신이 위)를 지킨다. 기본 tiebreak 는 짧은
    -- 글자를 앞으로 올려서, 글자를 치는 순간 옛 커밋이 위로 올라왔다.
    o.tiebreak = function() return false end
  end
  o.prompt_title = ('%s  →  %s  %s'):format(k.title, shown, where)
  -- 뜬 트리(F11)에서 불렸으면 편집 창으로 나간 뒤에 연다. telescope 는 부른
  -- 창으로 돌아가는데, 그게 곧 닫힐 뜬 창이면 <C-q>(quickfix 로 보내기)가
  -- 편집 창을 quickfix 로 덮었다 (QA).
  if api.nvim_win_get_config(0).relative ~= '' and type(_G.vimide_last_edit_win) == 'function' then
    local okw, w = pcall(_G.vimide_last_edit_win)
    if okw and type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w) then
      pcall(api.nvim_set_current_win, w)
    end
  end
  -- 저장소처럼 보여도 git 이 거절하는 경우(다른 사람 체크아웃의 'dubious
  -- ownership' 등)가 있다. 날것의 오류 대신 한 줄로 알린다.
  local ok2, err = pcall(builtin[k.fn], o)
  if not ok2 then
    local msg = tostring(err):gsub('^.-:%d+: ', ''):gsub('%s+', ' ')
    vim.notify(('%s 를 열 수 없습니다 - %s (%s)'):format(k.title, short(cwd),
      vim.fn.strcharpart(msg, 0, 60)), WARN)
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
