-- gitrepo.lua - \s (Neogit) 와 \v (Diffview) 를 '지금 보고 있는 것'의 저장소에서 연다
--
-- 예전에는 둘 다 nvim 의 지금 디렉터리(cwd)의 저장소를 열었다. 이 설정은 한 nvim
-- 에서 여러 저장소를 오간다 - SDK 안의 커널, 그 안의 다른 저장소, submodule,
-- worktree - 그래서 트리에서 다른 저장소의 파일을 보다가 \s 를 누르면 엉뚱한
-- 저장소의 상태 화면이 떴고, 그 저장소로 가려면 :cd 부터 해야 했다.
--
-- 기준 경로 (어느 저장소인가를 정하는 것)
--   neo-tree 창      커서 밑 항목 - 디렉터리 줄은 그 디렉터리, 파일 줄은 그 파일.
--                    F9 트리, F11 뜬 트리, RelationView 의 트리, 소스(filesystem /
--                    buffers / git_status) 모두 같다. 지금은 없는 경로(git_status 의
--                    지운 파일)는 가장 가까운 있는 윗 디렉터리, 경로가 없는 줄(안내
--                    줄, 버퍼 소스의 터미널 줄)은 트리의 루트.
--   편집 창          그 파일. 아직 저장하지 않은 새 파일은 가장 가까운 있는 윗
--                    디렉터리, 이름 없는 버퍼는 nvim 의 지금 디렉터리 (예전 그대로).
--                    커밋 메시지·리베이스 목록(.git/COMMIT_EDITMSG, git-rebase-todo
--                    ... Neogit 의 c c 창)은 그 git 디렉터리를 쓰는 작업 트리.
--   그 밖의 곁창     이 탭 편집 창(EDIT)의 파일 - quickfix, aerial, tagbar, help,
--                    terminal, RelationView 패널·미리보기, DirDiff 트리, telescope ...
--                    그 창들의 글자는 파일이 아니다. 편집 창이 없으면 지금 디렉터리.
--   Neogit 버퍼      그 화면의 저장소 (창의 lcd) - 상태 화면에서 \s 는 새로 고침이다
--                    (예전 그대로). 로그·커밋 화면도 그 화면을 연 상태 화면의 저장소.
--   Diffview 탭      그 view 의 저장소 - \v 는 그 view 를 닫는다 (아래)
--
-- 저장소
--   기준 경로를 품은 가장 안쪽 git 작업 트리의 맨 위. git 에게 묻는다
--   (git -C <디렉터리> rev-parse --show-toplevel) - Neogit 과 diffview 가 자기
--   저장소를 정할 때 묻는 것과 같은 질문이라 답이 어긋나지 않는다. 그래서 저장소
--   안의 다른 저장소(nested), submodule, 'git worktree add' 로 만든 트리는 저마다
--   자기 맨 위가 나온다. (\ff \fg 의 reposearch.lua 는 찾을 범위를 정하는 것이라
--   .repo 와 홈에서 멈추는 제 규칙이 따로 있다)
--   링크는 풀어서 가리키는 쪽의 저장소다. 디렉터리 링크는 git 이 chdir 하면서
--   스스로 풀지만, 파일 링크는 그 링크가 든 디렉터리에서 물으면 링크가 있는 쪽
--   저장소가 나온다 - 그래서 여기서 먼저 푼다.
--   작업 트리가 아니면(.git 안도) 한 줄로 알리고 아무것도 열지 않는다. Neogit 에
--   그대로 넘기면 'Initialize repository in ...?' 을 묻는데, 엉뚱한 곳에서 y 를
--   누르면 git init 이 된다. git 이 10초 안에 답하지 않으면(멈춘 SMB 마운트) 그렇다고
--   따로 알린다.
--
-- \s  Neogit 상태 화면 (새 탭, setup 의 kind='tab')
--   같은 저장소의 상태 화면이 다른 탭에 떠 있으면 그 탭으로 가서 새로 고친다.
--   다른 저장소의 상태 화면이 떠 있으면 그것을 닫고(q 와 같다) 새로 연다. 다만 그
--   탭에 다른 창(상태 화면 탭에서 :vsplit 한 파일, F9 트리 ...)이 같이 있으면 상태 화면
--   창만 닫는다 - q 는 탭을 통째로 닫아서 \s 를 누른 창까지 사라졌다 (고친 버퍼도 숨은
--   채로). 트리만 남아도 그 탭은 둔다 (keep_tree).
--   Neogit 은 상태 화면을 하나만 가질 수 있다: 버퍼 이름이 늘 'NeogitStatus' 라
--   둘째 저장소를 열면 첫째의 버퍼를 그대로 집어 와 덮어 그리고, git 명령은 모두
--   '마지막으로 연 저장소'(neogit.lib.git.repository 의 lastDir)에서 돈다. 둘을
--   같이 띄워 두면 앞의 화면에서 s 를 눌러도 뒤의 저장소에 스테이징된다.
--   같은 까닭으로 앞 저장소의 다른 Neogit 화면(로그, reflog, refs, stash, 커밋 화면
--   ...)도 같이 닫는다 - 남겨 두면 거기서 누른 Enter·b·X 가 뒤 저장소에서 돈다.
--   Neogit 의 d 팝업이 연 diff 중 d s, d u, d d (스테이징한 것·안 한 것 - Neogit 이 만든
--   view, CDiffView) 도 다른 저장소의 것이면 닫는다. 그 view 는 파일 목록과 내용을 Neogit
--   의 '마지막 저장소'에서 읽는다 - 남겨 두면 그 탭에 들어가는 순간 뒤 저장소의 목록으로
--   바뀌는데, 그 안의 '-'(스테이징)는 앞 저장소에서 돌았다 (실측: 앞 저장소 인덱스에 뒤
--   저장소의 파일이 올라갔다). diffview 가 스스로 저장소를 쥐고 도는 view 는 그대로 둔다 -
--   \v, :DiffviewOpen, :DiffviewFileHistory, Neogit 의 d w·d r·커밋·stash 가 연 것. 그런
--   view 는 열 때 받은 맨 위(-C)에서 git 을 돌려서 Neogit 이 저장소를 옮겨도 맞다.
--   다만 Neogit 으로 앞 저장소의 커밋 메시지(리베이스 목록 ...)를 쓰는 중이면 아무것도
--   닫지 않고 넘어가지 않는다 - 한 줄로 알린다.
--   떠 있는 화면들이 어느 저장소의 것인지는 git 에게 묻지 않고 가른다 (in_repo,
--   gitdir_of). git 에게 묻는 것은 열려는 저장소 하나뿐이다 - 다른 화면의 저장소가 멈춘
--   마운트 위에 있어도 \s 가 그 저장소의 git 을 기다리지 않는다.
--
-- \v  Diffview (git 2.31 이상)
--   diffview 탭 안이면              그 view 를 닫는다
--   같은 저장소의 작업 트리 diff 가  그 탭으로 간다 (diffview 가 들어가면서 새로 고친다)
--   다른 탭에 떠 있으면
--   아니면                           :DiffviewOpen -C<맨 위> 로 새 탭에 연다
--   저장소마다 view 를 따로 띄워 둘 수 있다. 기준이 파일이면 그 파일을 골라 둔 채
--   연다 (--selected-file, 바뀐 파일 목록에 있을 때). 다른 식으로 연 view - 커밋
--   범위, --cached, 경로를 좁힌 것, Neogit 의 d 팝업 - 는 그 저장소의 것이라도
--   건드리지 않고 새로 연다 (is_worktree_view).
--   예전에는 어느 탭에서 눌러도 '떠 있는 view 가 있으면 닫기'였는데, 실제로는
--   :DiffviewClose 가 지금 탭의 view 만 닫아서 다른 탭에서 누르면 아무 일도 없었다.
--
-- 새 탭은 편집 창에서 연다 (\s \v 둘 다)
--   diffview 와 Neogit 은 지금 창을 본떠(:tab split, :tab sb) 새 탭을 연다 - 창 옵션이
--   그대로 따라간다. 곁창(트리, quickfix, RelationView 패널 ...)에서 누르면 그 곁창의
--   옵션이 새 탭에 묻어 갔다 (실측):
--     RelationView 패널  winfixbuf 가 따라가 diffview 가 자기 버퍼를 못 넣는다 - 두 번째
--                        \v 부터 E1513 과 Press ENTER, diff 창에 패널 목록이 남은 탭.
--                        Neogit 상태 화면에는 패널의 줄 강조가 묻고, 거기서 파일을 Enter
--                        로 열면 패널(winfixbuf)로 가려다 아무 데도 열리지 않았다
--     트리               diff 창의 줄 번호·sign 기둥이 꺼진 채로 열렸다
--   그래서 곁창에서 불렸으면 이 탭 편집 창으로 옮겨서 연다 (F11 뜬 트리에서처럼).
--   이 탭으로 돌아오면 편집 창에 있다 - 누른 곁창으로 되돌려 두지 않는다: Neogit 의
--   Enter(파일 열기)와 diffview 의 gf 는 그 탭을 닫거나 떠나 '앞 탭의 지금 창'에 파일을
--   여는데, 그것이 곁창이면 거기 열려다 막혔다 (패널이면 아무 데도 열리지 않았다).
--   편집 창이 없는 탭(help 만 ...)에서는 그 자리에서 열되, winfixbuf 만은 여는 동안
--   잠시 끈다. diffview 탭 안에서는 옮기지 않는다 (예전 그대로).
--
-- 전역 함수 (.vimrc 의 <leader>s / <leader>v 가 부른다)
--   _G.vimide_git_status()      \s
--   _G.vimide_git_diffview()    \v
--   _G.vimide_git_target()      기준 경로와 저장소 - { path=, root=, err= }
--
-- nvim 전용이다. 진짜 vim 8.1 에는 \s \v 가 원래 없다 (Neogit·diffview 가 nvim 전용).

if vim.fn.has('nvim') ~= 1 or vim.g.loaded_vimide_gitrepo then
  return
end
vim.g.loaded_vimide_gitrepo = 1

local api = vim.api
local uv = vim.uv or vim.loop
local WARN = vim.log.levels.WARN

local function notify(msg, level)
  local f = type(_G.vimide_notify) == 'function' and _G.vimide_notify or vim.notify
  f(msg, level or WARN)
end

-- 알림에 넣는 경로 (홈은 ~ 로)
local function show(p)
  return vim.fn.fnamemodify(p, ':~')
end

local function strip(p)
  if type(p) ~= 'string' or p == '' then
    return nil
  end
  if p ~= '/' then
    p = (p:gsub('/+$', ''))
  end
  return p ~= '' and p or '/'
end

-- 같은 디렉터리인가. 링크(맥의 /tmp -> /private/tmp)를 풀어서 견준다.
local function same(a, b)
  a, b = strip(a), strip(b)
  if not a or not b then
    return false
  end
  if a == b then
    return true
  end
  return (uv.fs_realpath(a) or a) == (uv.fs_realpath(b) or b)
end

local function is_dir(p)
  local st = p and uv.fs_stat(p)
  return st ~= nil and st.type == 'directory'
end

-- ---------------------------------------------------------------------------
-- 기준 경로 -> 저장소
-- ---------------------------------------------------------------------------

-- 경로(파일이나 디렉터리) -> git 에게 물을 디렉터리. 링크는 끝까지 푼다.
-- 없는 경로면 가장 가까운 있는 윗 디렉터리. 경로 말고 expand() 는 쓰지 않는다:
-- 'wildignore' 의 */tmp/* 에 걸리면 빈 글자가 된다 (Yocto 의 build/tmp).
local function dir_for(p)
  p = strip(p)
  if not p or p:sub(1, 1) ~= '/' then
    return nil
  end
  local real = uv.fs_realpath(p)
  if real then
    return is_dir(real) and real or vim.fs.dirname(real)
  end
  local d = p
  for _ = 1, 128 do
    local up = vim.fs.dirname(d)
    if not up or up == d then
      break
    end
    d = up
    local r = uv.fs_realpath(d)
    if r and is_dir(r) then
      return r
    end
  end
  return nil
end

-- git 을 돌린다: 표준 출력(앞뒤 빈칸 뺀 것), 아니면 nil 과 git 의 말.
-- 셋째 값이 true 면 git 이 10초 안에 끝나지 않은 것이다.
--
-- 멈춘 SMB 마운트나 잠든 네트워크 디렉터리에서 git 이 그렇게 된다. 그때 vim.system
-- 의 wait 는 git 을 죽이고 code 124 (signal 9)를 준다. git 이 띄운 자식이 파이프를
-- 쥐고 있으면 10초를 더 기다렸다가 아예 nil 을 준다. 둘 다 따로 알린다 - 예전에는
-- 첫째를 'git 의 말이 비었다'로만 보고 '작업 트리가 아닙니다 (.git 안이거나 bare)'
-- 라고, 둘째는 'git 을 띄울 수 없습니다'라고 해서 멀쩡한 작업 트리의 파일을 두고
-- 엉뚱한 까닭을 댔다 (실측: 12초 자는 git 으로 10초 멈춘 뒤 그 말).
local function git(argv)
  if not vim.system then
    local out = vim.fn.system(argv)
    if vim.v.shell_error ~= 0 then
      return nil, vim.trim(out)
    end
    return vim.trim(out)
  end
  local ok, obj = pcall(vim.system, argv, { text = true })
  if not ok or not obj then
    return nil, 'git 을 띄울 수 없습니다'
  end
  local r = obj:wait(10000)
  if not r or (r.code == 124 and (r.signal or 0) ~= 0) then
    return nil, '', true
  end
  if r.code ~= 0 then
    local err = vim.trim(r.stderr or '')
    return nil, err ~= '' and err or ('exit ' .. r.code)
  end
  return vim.trim(r.stdout or '')
end

-- git 의 답: 맨 위 경로, 아니면 nil 과 git 의 말 (셋째 값은 git() 과 같다).
-- 빈 답('')은 옛 git 의 '작업 트리 밖' 이다 - git 2.25 전에는 .git 안이나 bare
-- 에서 --show-toplevel 이 아무것도 찍지 않고 0 으로 끝났다.
local function toplevel(dir, gitdir)
  local argv = { 'git', '-C', dir, 'rev-parse', '--show-toplevel' }
  if gitdir then
    table.insert(argv, 4, '--git-dir=' .. gitdir)
  end
  local out, err, slow = git(argv)
  if out and out:sub(1, 1) == '/' then
    return out
  end
  return nil, out or err, slow
end

-- git 이 쓰라고 연 파일의 작업 트리 - 커밋·머지·태그 메시지(COMMIT_EDITMSG,
-- MERGE_MSG, TAG_EDITMSG)와 리베이스 목록(git-rebase-todo). Neogit 의 c c 가 여는
-- 메시지 창이 이것이다 (filetype gitcommit, buftype 은 보통 파일과 같은 '').
-- 이 파일들은 .git 안에 있어서 --show-toplevel 에게는 '작업 트리가 아니다'가
-- 나온다. 그러면 메시지 창에서 \s \v 가 아무것도 열지 못한다 (예전 :Neogit 은
-- 창의 lcd 로 상태 화면에 갔다). 그 git 디렉터리를 쓰는 작업 트리를 찾는다:
--   worktree add 로 만든 트리   <git 디렉터리>/gitdir 에 그 트리의 .git 경로가 있다
--   그 밖                        git --git-dir=<git 디렉터리> 에게 맨 위를 묻는다 -
--                                submodule 은 core.worktree 로, 보통 저장소는 .git 의
--                                부모로 답하고, bare 는 작업 트리가 없다고 답한다
-- .git 안의 파일이 아니면 nil - 보통 파일처럼 다룬다.
-- 돌려주는 것: { root=, err=, slow= } (toplevel 의 셋과 같다)
local function msgfile_root(file)
  local dir = dir_for(file)
  if not dir then
    return nil
  end
  local g, err, slow = git({ 'git', '-C', dir, 'rev-parse', '--absolute-git-dir' })
  if slow then
    return { err = err, slow = true }
  end
  g = g and g:sub(1, 1) == '/' and (uv.fs_realpath(g) or g)
  if not g or (dir ~= g and dir:sub(1, #g + 1) ~= g .. '/') then
    return nil
  end
  local wt
  local f = io.open(g .. '/gitdir', 'r')
  if f then
    wt = f:read('*l')
    f:close()
  end
  if wt and wt ~= '' then
    if wt:sub(1, 1) ~= '/' then -- worktree.useRelativePaths (git 2.48~)
      wt = g .. '/' .. wt
    end
    wt = vim.fs.dirname(wt)
    if not is_dir(wt) then
      return { err = 'must be run in a work tree' } -- 지운 worktree
    end
    local root, e2, s2 = toplevel(wt)
    return { root = root, err = e2, slow = s2 }
  end
  local root, e2, s2 = toplevel(vim.fs.dirname(g), g)
  return { root = root, err = e2, slow = s2 }
end

-- Neogit 상태 화면들: { buf, wins, cwd }. cwd 는 그 창의 지금 디렉터리다 -
-- Neogit 이 연 cwd 로 lcd 해 두고, 인스턴스도 그 cwd 로 찾는다.
local function neogit_statuses()
  local out = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and vim.bo[b].filetype == 'NeogitStatus' then
      local wins = vim.fn.win_findbuf(b)
      -- getcwd(창, 탭). nvim_win_call 안의 getcwd() 는 그 창의 lcd 가 아니라
      -- 전역 디렉터리를 준다 (실측).
      local cwd
      if wins[1] then
        pcall(function()
          local tw = vim.fn.win_id2tabwin(wins[1])
          cwd = vim.fn.getcwd(tw[2], tw[1])
        end)
      end
      out[#out + 1] = { buf = b, wins = wins, cwd = cwd }
    end
  end
  return out
end

-- Neogit 창의 저장소 (디렉터리).
-- 창의 lcd 가 먼저다. Neogit 은 상태 화면 창을 그 저장소로 lcd 해 두고, 거기서 연
-- 로그·reflog·refs·커밋 화면(새 탭이나 옆 창)은 그 lcd 를 물려받는다. lcd 가 없을
-- 때만 Neogit 이 지금 다루는 저장소(lastDir). 그것부터 보면 안 된다 - 다른 저장소의
-- 상태 화면을 여는 순간 바뀌어서, 앞 저장소에서 남은 로그 화면의 \s 가 뒤 저장소로
-- 갔다 (실측. 예전 :Neogit 은 lcd 를 따라 앞 저장소로 갔다).
local function neogit_win_dir(win)
  local tw = vim.fn.win_id2tabwin(win)
  if vim.bo[api.nvim_win_get_buf(win)].filetype == 'NeogitStatus'
      or vim.fn.haslocaldir(tw[2], tw[1]) == 1 then
    return vim.fn.getcwd(tw[2], tw[1])
  end
  local ok, root = pcall(function()
    return require('neogit.lib.git').repo.worktree_root
  end)
  if ok and type(root) == 'string' and root ~= '' then
    return root
  end
  return vim.fn.getcwd(tw[2], tw[1])
end

-- dir(이미 떠 있는 Neogit 화면의 디렉터리)이 root 저장소의 것인가. git 을 부르지 않는다.
--
-- 예전에는 떠 있는 상태 화면과 로그·커밋 화면마다 git rev-parse 를 돌렸다. 그 화면의
-- 저장소가 멈춘 SMB 마운트 위에 있으면 하나에 10초씩 걸려, 지금 여는 저장소는 멀쩡한데
-- \s 가 아무 말 없이 멈췄다 (실측: 앞 저장소의 상태·로그 화면을 띄워 둔 채 그 저장소의
-- git 이 멈추면 10.3초). 답은 이미 있다:
--   Neogit 이 아는 것  그 디렉터리로 연 상태 화면 인스턴스의 root - Neogit 이 열 때 git
--                      에게 물어 둔 맨 위다. 상태 화면 창은 그 디렉터리로 lcd 하고, 거기서
--                      연 로그·커밋 화면은 그 lcd 를 물려받는다.
--   경로               root 와 같으면 같은 저장소, root 밖이면 다른 저장소 - 맨 위는 늘 그
--                      디렉터리를 품는다. 글자로 견준다: getcwd() 는 링크를 푼 실제 경로를
--                      주고 root 도 git 이 준 실제 경로다 (멈춘 쪽 경로를 realpath 하면
--                      그것도 멈출 수 있다).
--   root 안이면        그 사이에 .git 이 있으면 안쪽 저장소(nested, submodule, worktree),
--                      없으면 같은 저장소 - git 이 저장소를 찾는 방법과 같다. root 쪽 파일
--                      시스템만 본다 (지금 여는 저장소라 멀쩡하다).
local function in_repo(dir, root)
  dir, root = strip(dir), strip(root)
  if not dir or not root then
    return false
  end
  local ok, status = pcall(require, 'neogit.buffers.status')
  local inst
  if ok and type(status) == 'table' and type(status.instance) == 'function' then
    local ok2, i = pcall(status.instance, dir)
    inst = ok2 and type(i) == 'table' and i or nil
  end
  if inst and type(inst.root) == 'string' and inst.root ~= '' then
    return strip(inst.root) == root
  end
  if dir == root then
    return true
  end
  local pre = root == '/' and '/' or root .. '/'
  if dir:sub(1, #pre) ~= pre then
    return false
  end
  local d = dir
  while #d > #root do
    if uv.fs_stat(d .. '/.git') then
      return false
    end
    d = vim.fs.dirname(d)
  end
  return true
end

-- root 저장소의 git 디렉터리 - git 없이. <root>/.git 이 디렉터리면 그것, 파일이면
-- (worktree, submodule) 그 안의 'gitdir: ...'. 알 수 없으면 nil.
local function gitdir_of(root)
  local p = root .. '/.git'
  local st = uv.fs_stat(p)
  if not st then
    return nil
  end
  if st.type == 'directory' then
    return uv.fs_realpath(p) or p
  end
  local f = io.open(p, 'r')
  local line = f and f:read('*l')
  if f then
    f:close()
  end
  local g = line and line:match('^gitdir:%s*(.-)%s*$')
  if not g or g == '' then
    return nil
  end
  if g:sub(1, 1) ~= '/' then
    g = root .. '/' .. g
  end
  return uv.fs_realpath(g) or g
end

-- diffview 탭이면 그 view. diffview.lib 가 아직 안 올라왔으면 view 도 없다 -
-- \s 를 누를 때마다 diffview 를 올리지 않는다.
local function diffview_here()
  local lib = package.loaded['diffview.lib']
  if type(lib) ~= 'table' or type(lib.get_current_view) ~= 'function' then
    return nil
  end
  local ok2, v = pcall(lib.get_current_view)
  return ok2 and v or nil
end

local function view_root(v)
  local ok, r = pcall(function()
    return v.adapter.ctx.toplevel
  end)
  return ok and type(r) == 'string' and r ~= '' and r or nil
end

-- neo-tree 창의 state. position=current(RelationView 트리)에서는
-- get_state_for_window 가 nil 을 주는 일이 있어 전체 목록에서 버퍼로 찾는다
-- (searchctx.lua 와 같다).
local function neotree_state(win, buf)
  local ok, m = pcall(require, 'neo-tree.sources.manager')
  if not ok then
    return nil
  end
  local ok1, st = pcall(m.get_state_for_window, win)
  if ok1 and st and st.tree and st.bufnr == buf then
    return st
  end
  local ok2, all = pcall(m._get_all_states)
  for _, x in ipairs(ok2 and all or {}) do
    if x.bufnr == buf and x.tree then
      return x
    end
  end
end

-- 커서 밑 항목의 경로. get_node 에는 줄 번호를 꼭 준다 - 없으면 nui 가 '그
-- 버퍼를 보여 주는 첫 창'의 커서를 읽는다 (treesearch.lua).
local function neotree_path(win, buf)
  local st = neotree_state(win, buf)
  if not st then
    return nil
  end
  local node
  pcall(function()
    node = st.tree:get_node(api.nvim_win_get_cursor(win)[1])
  end)
  local p, t = node and node.path, node and node.type
  -- 진짜 파일·디렉터리만. 안내 줄('(3 hidden items)')에는 경로가 없고, buffers
  -- 소스의 터미널 줄은 path 가 그 터미널의 cwd, '[No Name]' 줄은 상대 경로다.
  if type(p) == 'string' and p:sub(1, 1) == '/'
      and (t == 'file' or t == 'directory' or t == 'link') then
    return p
  end
  return type(st.path) == 'string' and st.path ~= '' and st.path or nil
end

-- 버퍼의 파일 경로 (보통 파일만). fugitive 로 연 옛 판은 작업 트리의 그 파일로.
local function buf_file(buf)
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return nil
  end
  local n = api.nvim_buf_get_name(buf)
  if n:match('^fugitive://') and vim.fn.exists('*FugitiveReal') == 1 then
    local ok, r = pcall(vim.fn.FugitiveReal, n)
    return ok and type(r) == 'string' and r:sub(1, 1) == '/' and r or nil
  end
  if vim.bo[buf].buftype ~= '' or n == '' then
    return nil
  end
  return vim.fn.fnamemodify(n, ':p')
end

-- 이 탭 편집 창(EDIT)의 파일. 없으면 nil.
local function edit_win_file()
  for _, f in ipairs({ _G.vimide_edit_slot, _G.vimide_last_edit_win }) do
    if type(f) == 'function' then
      local ok, w = pcall(f)
      if ok and type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w)
          and api.nvim_win_get_tabpage(w) == api.nvim_get_current_tabpage() then
        local p = buf_file(api.nvim_win_get_buf(w))
        if p then
          return p
        end
      end
    end
  end
  -- vimidewin.lua 가 없을 때: 이 탭에서 직전 창, 그다음 아무 보통 파일 창
  local prev = vim.fn.win_getid(vim.fn.winnr('#'))
  local wins = api.nvim_tabpage_list_wins(0)
  table.insert(wins, 1, prev)
  for _, w in ipairs(wins) do
    if w ~= 0 and api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative == '' then
      local p = buf_file(api.nvim_win_get_buf(w))
      if p then
        return p
      end
    end
  end
  return nil
end

--- 기준 경로와 그 저장소.
--- @return table { path = 기준 경로, root = 맨 위 (아니면 nil), err = git 의 말,
---                 slow = git 이 10초 안에 답하지 않았다,
---                 file = 기준이 보통 파일이면 그 실제 경로, view = diffview 탭의 view }
function _G.vimide_git_target()
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  local path

  local v = diffview_here()
  if v then
    path = view_root(v)
    if path then
      return { path = path, root = path, view = v }
    end
  end
  if ft:match('^Neogit') then
    path = neogit_win_dir(win)
  elseif ft == 'neo-tree' then
    path = neotree_path(win, buf)
  elseif vim.bo[buf].buftype == '' then
    -- 편집 창. 이름 없는 버퍼면 지금 디렉터리.
    path = buf_file(buf)
    -- 커밋 메시지·리베이스 목록 (Neogit 의 c c 창도): 그 git 디렉터리의 작업 트리
    if path and (ft == 'gitcommit' or ft == 'gitrebase') then
      local m = msgfile_root(path)
      if m then
        return { path = path, root = m.root, err = m.err, slow = m.slow }
      end
    end
  else
    path = buf_file(buf) or edit_win_file()
  end
  path = path or vim.fn.getcwd()

  local dir = dir_for(path)
  if not dir then
    return { path = path, missing = true }
  end
  local root, err, slow = toplevel(dir)
  local real = uv.fs_realpath(path)
  local file = real and not is_dir(real) and real or nil
  return { path = path, root = root, err = err, slow = slow, file = file }
end

-- 저장소가 아니면 알린다 (한 줄). 저장소면 맨 위를 돌려준다.
local function root_or_warn(who, t)
  if t.root then
    return t.root
  end
  local err = t.err or ''
  local why
  if t.missing then
    why = '그런 경로가 없습니다'
  elseif t.slow then
    why = 'git 이 10초 안에 답하지 않았습니다 (멈춘 SMB·네트워크 마운트?)'
  elseif err:match('must be run in a work tree') or err == '' then
    why = 'git 작업 트리가 아닙니다 (.git 안이거나 bare)'
  elseif err:match('not a git repository') then
    why = 'git 저장소가 아닙니다'
  else
    -- 'dubious ownership' (남의 체크아웃) 같은 것. 날것 그대로 짧게.
    why = 'git 이 거절했습니다 (' .. vim.fn.strcharpart((err:gsub('^fatal:%s*', ''):gsub('%s+', ' ')), 0, 50) .. ')'
  end
  notify(('%s: %s - %s'):format(who, why, show(t.path)))
  return nil
end

-- 뜬 창(F11 트리)에서 불렸으면 편집 창으로 나간 뒤에 연다. 새 탭을 여는 쪽에서
-- 보면 뜬 창은 '지금 창'이 될 수 없고, F11 트리는 초점을 잃으면 닫힌다.
local function leave_float()
  if api.nvim_win_get_config(0).relative == '' then
    return
  end
  for _, f in ipairs({ _G.vimide_last_edit_win, _G.vimide_edit_slot }) do
    if type(f) == 'function' then
      local ok, w = pcall(f)
      if ok and type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w) then
        pcall(api.nvim_set_current_win, w)
        return
      end
    end
  end
  pcall(vim.cmd, 'wincmd p')
end

-- 창 옵션. 이 nvim 에 없는 옵션(옛 nvim 의 winfixbuf)이면 nil.
local function wopt(w, name)
  local ok, v = pcall(function()
    return vim.wo[w][name]
  end)
  return ok and v or nil
end

-- 새 탭을 본뜰 수 있는 보통 창인가: 뜨지 않았고, 파일(이름 없는 버퍼도)을 보여 주고,
-- winfixbuf·미리보기가 아닌 창. 곁창은 buftype 이 있거나(nofile, quickfix, help,
-- terminal ...) RelationView 패널처럼 winfixbuf 가 걸려 있다.
local function plain_win(w)
  return type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w)
    and api.nvim_win_get_config(w).relative == ''
    and vim.bo[api.nvim_win_get_buf(w)].buftype == ''
    and not wopt(w, 'winfixbuf') and not wopt(w, 'previewwindow')
end

-- 이 탭의 편집 창 (보통 창이어야 한다). 없으면 nil.
local function tab_edit_win()
  local tab = api.nvim_get_current_tabpage()
  for _, f in ipairs({ _G.vimide_edit_slot, _G.vimide_last_edit_win }) do
    if type(f) == 'function' then
      local ok, w = pcall(f)
      if ok and plain_win(w) and api.nvim_win_get_tabpage(w) == tab then
        return w
      end
    end
  end
  -- vimidewin.lua 가 없을 때: 이 탭에서 직전 창, 그다음 아무 보통 창
  local wins = api.nvim_tabpage_list_wins(0)
  table.insert(wins, 1, vim.fn.win_getid(vim.fn.winnr('#')))
  for _, w in ipairs(wins) do
    if plain_win(w) then
      return w
    end
  end
end

-- fn(새 탭을 연다)을 이 탭 편집 창에서 부른다 (머리말의 '새 탭은 편집 창에서 연다').
-- 돌려주는 것은 pcall(fn) 과 같다.
local function open_from_plain(fn)
  local float = api.nvim_win_get_config(0).relative ~= ''
  leave_float()
  local tab = api.nvim_get_current_tabpage()
  local back -- 누른 곁창 (편집 창으로 옮겼을 때만)
  local w = api.nvim_get_current_win()
  -- diffview 탭은 그대로 둔다: 거기 창은 모두 diffview 의 것이라 '편집 창'이 없고, 그
  -- 패널에서 연 상태 화면에는 묻어 가는 것도 없다 (실측). 옮기면 q 로 돌아올 때 패널
  -- 대신 diff 창에 떨어진다.
  if not plain_win(w) and not diffview_here() then
    local e = tab_edit_win()
    if e then
      pcall(api.nvim_set_current_win, e)
      if api.nvim_get_current_win() == e then
        back = not float and w or nil -- 뜬 창은 초점을 잃으면 닫힌다
        w = e
      end
    end
  end
  local buf = api.nvim_win_get_buf(w)
  -- 편집 창이 없는 탭: 그 자리에서 열되 winfixbuf 는 잠시 끈다 - 새 탭의 창들이
  -- 그것을 물려받으면 diffview 가 자기 버퍼를 넣지 못한다 (E1513)
  local fixed = wopt(w, 'winfixbuf') == true
  if fixed then
    pcall(function() vim.wo[w].winfixbuf = false end)
  end
  local ok, err = pcall(fn)
  if fixed and api.nvim_win_is_valid(w) then
    pcall(function() vim.wo[w].winfixbuf = true end)
  end
  -- 아무것도 열리지 않았으면(diffview 가 거절 ...) 누른 곁창으로 돌아간다. 열렸으면
  -- 이 탭에서는 편집 창에 남는다 (머리말)
  if back and api.nvim_win_is_valid(back) and api.nvim_get_current_tabpage() == tab
      and api.nvim_get_current_win() == w and api.nvim_win_get_buf(w) == buf then
    pcall(api.nvim_set_current_win, back)
  end
  return ok, err
end

-- ---------------------------------------------------------------------------
-- \s  Neogit
-- ---------------------------------------------------------------------------

-- 다른 저장소의 상태 화면을 닫는다.
--
-- kind='tab'(이 설정의 기본)과 'replace' 는 Neogit 의 q(인스턴스의 close)로 닫는다 -
-- 접힘·커서 자리를 기억해 두었다가 다음에 그 저장소를 열 때 돌려준다. close 는
-- kind='tab' 이면 '지금 탭'을 닫으므로 그 창으로 가서 부른다.
-- 다른 kind(:Neogit kind=split, floating ...)는 close 를 부르지 않는다. 그쪽 close 는
-- 창을 '나중에'(vim.schedule) 닫고, 그때 창이 이미 없으면 그 순간의 지금 창에서 :b#
-- 를 한다 - 그 사이에 새로 연 상태 화면이 그 :b# 에 밀려나 지워졌다 (실측: 'Invalid
-- buffer id' 와 Press ENTER). 그런 것은 여기서 창을 닫고 버퍼를 지운다.
-- 버퍼는 어느 쪽이든 남기지 않는다: 남아 있으면 새 상태 화면이 이름이 같은 그 버퍼를
-- 집어 쓴다.
-- kind='tab' 이라도 그 탭에 다른 창이 같이 있으면(상태 화면 탭에서 :vsplit 한 파일 ...)
-- close 를 부르지 않는다. 그 close 는 :tabclose 라 그 창들까지 - \s 를 누른 창일 수도
-- 있다 - 닫고, 고친 버퍼는 숨은 채로 남았다 (실측). 상태 화면 창만 아래에서 닫는다.
-- 접힘·커서 자리는 close 가 하듯 적어 둔다.
local function close_status(s)
  local ok, status = pcall(require, 'neogit.buffers.status')
  local inst = ok and s.cwd and status.instance(s.cwd) or nil
  local nb = inst and inst.buffer
  local w1 = s.wins[1]
  if nb and nb.handle == s.buf and (nb.kind == 'tab' or nb.kind == 'replace')
      and w1 and api.nvim_win_is_valid(w1) then
    local shared = false
    if nb.kind == 'tab' then
      for _, w in ipairs(api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(w1))) do
        if api.nvim_win_get_config(w).relative == '' and api.nvim_win_get_buf(w) ~= s.buf then
          shared = true
        end
      end
    end
    if shared then
      pcall(api.nvim_win_call, w1, function()
        inst.fold_state = nb.ui:get_fold_state()
        inst.cursor_state = nb:cursor_line()
        inst.view_state = nb:save_view()
      end)
    else
      pcall(api.nvim_set_current_win, w1)
      pcall(inst.close, inst)
    end
  end
  if api.nvim_buf_is_valid(s.buf) then
    for _, w in ipairs(vim.fn.win_findbuf(s.buf)) do
      if #api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(w)) > 1 then
        pcall(api.nvim_win_close, w, true)
      end
    end
    pcall(api.nvim_buf_delete, s.buf, { force = true })
  end
  -- close 를 부르지 않은 인스턴스는 지운 버퍼를 아직 쥐고 있다. 그대로 두면 이미
  -- 떠난 새로 고침이 돌아와 그 버퍼에 그리려다 'Invalid buffer id' 로 죽는다 -
  -- close 가 하듯 놓아 준다 (Neogit 의 redraw 는 buffer 가 nil 이면 그냥 돌아간다).
  if inst and inst.buffer and inst.buffer.handle == s.buf then
    inst.buffer = nil
  end
end

-- 다른 저장소의 Neogit 화면들을 닫는다 - 로그, reflog, refs, stash, 커밋 화면,
-- $ 명령 기록, 그 탭의 팝업. 상태 화면을 닫는 것과 같은 까닭이다: Neogit 의 git
-- 명령은 어느 화면에서 누르든 '마지막으로 연 저장소'에서 돈다. 앞 저장소의 로그
-- 화면이 남아 있으면 거기서 Enter(git show)가 뒤 저장소에서 돌아 'log.lua:63:
-- Failed to parse line' 과 Press ENTER 로 끝나고, 두 저장소가 커밋을 나눠 가진
-- worktree 라면 b(브랜치)·X(reset)가 말없이 뒤 저장소에 한다 (둘 다 실측).
-- 예전에는 저장소를 바꾸려면 :cd 부터 해야 했지만 이제는 트리 줄 하나에서 \s 라,
-- 이렇게 남는 화면이 흔해진다.
--
-- 그 창의 저장소는 neogit_win_dir 와 in_repo 로 안다 (git 을 부르지 않는다). 탭
-- 하나가 통째로 그런 화면이면(kind 'tab' 이 이 화면들의 기본이다) 그 탭을 닫고, 다른
-- 창과 같이 있으면 그 창만 닫는다. 버퍼는 bufhidden=wipe 라 창과 같이 사라지고, 남은
-- 것은 지운다. 콘솔(NeogitConsole, 돌고 있는 git 의 출력)은 저장소 화면이 아니라 둔다.
local function close_views(root)
  local stale, bufs = {}, {}
  for _, w in ipairs(api.nvim_list_wins()) do
    local b = api.nvim_win_get_buf(w)
    local ft = vim.bo[b].filetype
    if ft:match('^Neogit') and ft ~= 'NeogitStatus' and ft ~= 'NeogitConsole'
        and not in_repo(neogit_win_dir(w), root) then
      stale[w], bufs[b] = true, true
    end
  end
  if next(stale) == nil then
    return
  end
  local tabs = api.nvim_list_tabpages()
  for i = #tabs, 1, -1 do -- 뒤에서부터 닫아야 앞 탭의 번호가 그대로다
    local all = false
    for _, w in ipairs(api.nvim_tabpage_list_wins(tabs[i])) do
      if api.nvim_win_get_config(w).relative == '' then -- 머리 줄 같은 뜬 창은 빼고
        all = stale[w] or false
        if not all then
          break
        end
      end
    end
    if all and #api.nvim_list_tabpages() > 1 then
      pcall(vim.cmd, 'tabclose! ' .. api.nvim_tabpage_get_number(tabs[i]))
    end
  end
  for w in pairs(stale) do
    if api.nvim_win_is_valid(w)
        and #api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(w)) > 1 then
      pcall(api.nvim_win_close, w, true)
    end
  end
  for b in pairs(bufs) do
    if api.nvim_buf_is_valid(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
end

-- Neogit 이 만든 diffview (d 팝업의 d s, d u, d d - CDiffView) 중 root 의 것이 아닌 것을
-- 닫는다 (머리말). 저장소는 view 의 맨 위로 가른다 - Neogit 이 열 때 git 에게 물어 둔
-- 것이고, root 도 git 이 준 실제 경로라 글자로 견준다 (in_repo 와 같은 까닭으로 git 도
-- realpath 도 부르지 않는다). diffview 나 그 view 가 아직 안 올라왔으면 닫을 것도 없다.
local function close_neogit_diffviews(root)
  local lib = package.loaded['diffview.lib']
  local m = package.loaded['diffview.api.views.diff.diff_view']
  local C = type(m) == 'table' and m.CDiffView
  if type(lib) ~= 'table' or type(lib.views) ~= 'table' or not C then
    return
  end
  local stale = {}
  for _, v in ipairs(lib.views) do
    if v.class == C and strip(view_root(v)) ~= strip(root) then
      stale[#stale + 1] = v
    end
  end
  -- :DiffviewClose 가 하는 것과 같다 (view 의 close 는 그 탭을 :tabclose 한다)
  for _, v in ipairs(stale) do
    local ok = pcall(function()
      v:close()
    end)
    pcall(lib.dispose_view, v)
    if not ok and v.tabpage and api.nvim_tabpage_is_valid(v.tabpage)
        and #api.nvim_list_tabpages() > 1 then
      pcall(vim.cmd, 'tabclose! ' .. api.nvim_tabpage_get_number(v.tabpage))
    end
  end
end

-- fn(앞 저장소의 화면들을 닫는 것)을 neo-tree 의 close_if_last_window(이 설정은 켠다)를
-- 잠시 끈 채로 부른다. 그 규칙은 창이 닫힐 때(WinClosed) 닫히는 창의 탭이 아니라 '지금
-- 탭'을 보고, 거기 neo-tree 창 하나만 남으면 :q! 를 미뤄 두었다가(vim.schedule) '그때의
-- 지금 창'에 한다. 상태 화면 탭에서 F9 트리를 열고 그 트리의 다른 저장소 줄에서 \s 를
-- 누르면 앞 상태 화면 창을 닫는 순간 그것이 걸려, 그사이에 연 새 상태 화면이 닫히고, 그
-- 창이 닫히며 또 걸린 :q! 에 트리의 탭까지 닫혔다 - 알림도 없이 아무것도 남지 않았다
-- (실측). 여기서 닫는 것은 앞 저장소의 화면뿐이고 같은 탭의 다른 창은 남긴다
-- (close_status) - 트리도 그렇고, \s 를 누른 창이면 더욱 그렇다. 트리만 남은 그 탭도 둔다.
local function keep_tree(fn)
  local cfg
  if package.loaded['neo-tree'] then
    local ok, c = pcall(function()
      return require('neo-tree').ensure_config()
    end)
    cfg = ok and type(c) == 'table' and c.close_if_last_window == true and c or nil
  end
  if cfg then
    cfg.close_if_last_window = false
  end
  local ok, err = pcall(fn)
  if cfg then
    cfg.close_if_last_window = true
  end
  if not ok then
    error(err, 0)
  end
end

-- Neogit 으로 다른 저장소의 메시지·목록을 쓰고 있으면 그 버퍼 (c c 의 커밋 메시지,
-- 머지·태그 메시지, 리베이스 목록). Neogit 이 만든 버퍼에는 'neogit-buffer-<번호>'
-- 이름공간이 있다 - 터미널의 git commit 이 띄운 메시지 버퍼와 가른다.
local WIP = {
  COMMIT_EDITMSG = '커밋 메시지를',
  MERGE_MSG = '머지 메시지를',
  TAG_EDITMSG = '태그 메시지를',
  EDIT_DESCRIPTION = '브랜치 설명을',
  ['git-rebase-todo'] = '리베이스 목록을',
}
-- 그 버퍼가 root 의 것인지는 root 의 git 디렉터리(gitdir_of)로 가른다 - git 을 부르지
-- 않는다. 메시지를 쓰는 저장소의 git 이 멈춰 있어도 \s 가 그쪽 git 을 기다리지 않게
-- (in_repo 와 같은 까닭). 메시지 파일은 그 작업 트리의 git 디렉터리에 있다 (리베이스
-- 목록은 rebase-merge/ 밑). git 디렉터리 밑이라도 worktrees/, modules/ 밑은 다른 작업
-- 트리(worktree add, submodule)의 것이다. root 의 .git 을 읽을 수 없을 때만 git 에게
-- 묻는다 (msgfile_root).
local function neogit_wip(root)
  local ns = api.nvim_get_namespaces()
  local gd = gitdir_of(root)
  for _, b in ipairs(api.nvim_list_bufs()) do
    local ft = vim.bo[b].filetype
    if (ft == 'gitcommit' or ft == 'gitrebase') and api.nvim_buf_is_loaded(b)
        and ns['neogit-buffer-' .. b] then
      local name = api.nvim_buf_get_name(b)
      local mine
      if gd then
        local rel = name:sub(1, #gd + 1) == gd .. '/' and name:sub(#gd + 2)
        mine = rel and not (rel:match('^worktrees/') or rel:match('^modules/'))
      else
        local m = msgfile_root(name)
        mine = m and same(m.root, root)
      end
      if not mine then
        return b
      end
    end
  end
end

function _G.vimide_git_status()
  local t = _G.vimide_git_target()
  local root = root_or_warn('Neogit', t)
  if not root then
    return
  end
  local ok, neogit = pcall(require, 'neogit')
  if not ok or type(neogit) ~= 'table' or type(neogit.open) ~= 'function' then
    notify('Neogit 이 올라와 있지 않습니다 (:PlugInstall)')
    return
  end

  local origin = api.nvim_get_current_win()
  -- 떠 있는 상태 화면이 어느 저장소의 것인지는 git 에게 묻지 않는다 (in_repo)
  local statuses = neogit_statuses()
  local hit
  for _, s in ipairs(statuses) do
    if not hit and s.wins[1] and in_repo(s.cwd, root) then
      hit = s
    end
  end

  if not hit then
    -- 다른 저장소로 넘어간다. Neogit 으로 다른 저장소의 메시지를 쓰는 중이면
    -- 넘어가지 않는다 - 넘어가면 그 창의 M-p(앞 메시지)·생성 같은 것이 새 저장소에서
    -- 돌고, 같이 뜬 Staged Changes 창도 닫혀 버린다. 닫지도 않고 한 줄로 알린다.
    local b = neogit_wip(root)
    if b then
      local name = api.nvim_buf_get_name(b)
      notify(('Neogit: %s 쓰는 중이라 다른 저장소로 넘어가지 않습니다 - 먼저 마치거나 닫으세요 (%s)')
        :format(WIP[vim.fs.basename(name)] or '메시지를', show(name)))
      return
    end
  end

  -- 닫는 동안 트리의 규칙이 \s 를 누른 창·새로 열 상태 화면을 닫지 않게 (keep_tree)
  keep_tree(function()
    for _, s in ipairs(statuses) do
      if s ~= hit then
        close_status(s)
      end
    end
    -- 같은 저장소로 가도 Neogit 의 '마지막 저장소'는 root 가 된다 (:Neogit 으로 옮겨 둔
    -- 것이 남아 있을 수 있다)
    close_neogit_diffviews(root)
    if not hit then
      close_views(root)
    end
  end)
  local ok2, err
  if hit then
    -- 같은 저장소: 그 창으로 간다. 지금 탭에 보이면 Neogit 은 새로 열지 않고
    -- 그 창에 초점을 준 채 새로 고친다. 인스턴스는 처음 연 cwd 로 찾으므로 그
    -- cwd 를 넘긴다 (:Neogit 으로 하위 디렉터리에서 연 것도 같은 화면으로).
    pcall(api.nvim_set_current_win, hit.wins[1])
    ok2, err = pcall(neogit.open, { cwd = hit.cwd, no_expand = true })
  else
    if api.nvim_win_is_valid(origin) then
      pcall(api.nvim_set_current_win, origin)
    end
    ok2, err = open_from_plain(function()
      neogit.open({ cwd = root, no_expand = true })
    end)
  end
  if not ok2 then
    notify(('Neogit 을 열 수 없습니다 - %s (%s)'):format(show(root),
      vim.fn.strcharpart((tostring(err):gsub('^.-:%d+: ', ''):gsub('%s+', ' ')), 0, 60)))
  end
end

-- ---------------------------------------------------------------------------
-- \v  Diffview
-- ---------------------------------------------------------------------------

-- diffview 는 git 2.31 이상이 필요하다.
--
-- 개발서버의 git 은 2.25.1 이라 :DiffviewOpen 이 'Not a repo (or any parent),
-- or no supported VCS adapter!' 만 남기고 아무 일도 하지 않는다. 저장소가
-- 아니어서가 아니라 git 이 낡아서인데, 그 말로는 알 수가 없다. 대신 말해 준다.
-- (맥은 2.54 라 그냥 열린다. Neogit 과 gitsigns 는 낡은 git 에서도 된다)
local git_ver -- { ver = '2.25.1', ok = false }
local function diffview_git_ok()
  if not git_ver then
    local okv, out = pcall(vim.fn.system, { 'git', '--version' })
    out = okv and type(out) == 'string' and out or ''
    local ver = vim.fn.matchstr(out, [[\d\+\.\d\+\(\.\d\+\)\?]])
    local p = vim.split(ver, '.', { plain = true })
    local major, minor = tonumber(p[1]) or 0, tonumber(p[2]) or 0
    git_ver = { ver = ver, ok = #p >= 2 and (major > 2 or (major == 2 and minor >= 31)) }
  end
  if not git_ver.ok then
    notify(('diffview 는 git 2.31 이상이 필요합니다 (여기는 %s). '
      .. 'Neogit(\\s)과 gitsigns(\\ha \\hv)는 그대로 됩니다.')
      :format(git_ver.ver == '' and '알 수 없음' or git_ver.ver))
  end
  return git_ver.ok
end

-- diffview 의 인자 해석은 -C 값을 expand() 에 넣는다. 그래서
--   1) 'wildignore' 를 비운 채 부른다 - */tmp/* 에 걸리면 '' 가 되어 지금
--      디렉터리의 저장소가 열린다 (dirdifftab.vim 의 s:call 과 같은 까닭)
--   2) expand() 와 diffview 의 낱말 나누기가 특별히 보는 글자를 \ 로 막는다 -
--      빈칸, $VAR, * ? [ ] { }, ~, `셸 명령`, 따옴표. diffview 의 scan 은 \x 를
--      그대로 두고, expand() 가 \ 를 벗긴다 (실측: 24가지 이름이 그대로 돌아온다)
local function esc(p)
  return (p:gsub('[\\%*%?%[%]{}`\'"%$~ #%%<>|;&(),!=]', '\\%0'))
end

-- \v 가 여는 것과 같은 view 인가: 작업 트리 전체 diff - 인자 없는 :DiffviewOpen
-- 처럼 왼쪽은 인덱스, 오른쪽은 작업 트리이고 커밋도 경로도 좁히지 않은 것.
-- 같은 저장소라도 커밋 범위(:DiffviewOpen HEAD~1..HEAD), --cached, 경로를 좁힌 것
-- (-- x.c), Neogit 의 d 팝업이 연 view 는 다른 것을 보여 준다. 그런 탭으로 가면
-- \v 로는 작업 트리 diff 를 볼 수 없었다 - 그 view 를 닫고(\v) 다시 눌러야 했다.
-- Neogit 의 view(CDiffView)는 DiffView 를 물려받고 rev 도 인덱스·작업 트리라
-- instanceof 나 rev 로는 못 가른다 - 클래스가 꼭 DiffView 인지 본다.
local function is_worktree_view(v)
  local ok, r = pcall(function()
    local RevType = require('diffview.vcs.rev').RevType
    return v.class == require('diffview.scene.views.diff.diff_view').DiffView
      and v.rev_arg == nil and (v.path_args == nil or #v.path_args == 0)
      and v.left ~= nil and v.left.type == RevType.STAGE
      and v.right ~= nil and v.right.type == RevType.LOCAL
  end)
  return ok and r == true
end

function _G.vimide_git_diffview()
  -- diffview 탭 안이면 그 view 를 닫는다 (git 이 낡아도 - 떠 있는 것은 닫혀야 한다)
  if diffview_here() then
    vim.cmd('DiffviewClose')
    return
  end
  if not diffview_git_ok() then
    return
  end
  local t = _G.vimide_git_target()
  local root = root_or_warn('Diffview', t)
  if not root then
    return
  end
  local okl, lib = pcall(require, 'diffview.lib')
  if okl and type(lib.views) == 'table' then
    for _, v in ipairs(lib.views) do
      if is_worktree_view(v) and v.tabpage and api.nvim_tabpage_is_valid(v.tabpage)
          and same(view_root(v), root) then
        api.nvim_set_current_tabpage(v.tabpage)
        return
      end
    end
  end
  if vim.fn.exists(':DiffviewOpen') ~= 2 then
    notify('diffview 가 올라와 있지 않습니다 (:PlugInstall)')
    return
  end
  local cmd = 'DiffviewOpen -C' .. esc(root)
  if t.file then
    cmd = cmd .. ' --selected-file=' .. esc(t.file)
  end
  local wi = vim.o.wildignore
  local ok, err = open_from_plain(function()
    vim.o.wildignore = ''
    vim.cmd(cmd)
  end)
  vim.o.wildignore = wi
  if not ok then
    notify(('Diffview 를 열 수 없습니다 - %s (%s)'):format(show(root),
      vim.fn.strcharpart((tostring(err):gsub('^.-:%d+: ', ''):gsub('%s+', ' ')), 0, 60)))
  end
end
