-- autoindex.lua - keep the GTAGS index up to date by itself, the way
-- vim-gutentags does it for ctags.
--
-- What it does
--   * starting nvim refreshes the index of the current project in the
--     background: an incremental 'gtags -i' when it exists, a full build
--     when it does not (and, unless it is switched off, gutentags is asked
--     to refresh the ctags index the same way)
--   * saving a source file updates GTAGS for that file only
--     ('global --single-update', a few milliseconds)
--   * opening a source file in a project that has no GTAGS yet starts one
--     background build (once per project per session)
--   * C-] / :tag / g] answer from GTAGS through 'tagfunc', so a jump works
--     the moment a file is saved and needs no ctags file at all; when gtags
--     has nothing the normal tags-file lookup still runs
--   * a tree too big for gutentags (see g:autoindex_ctags_max_files) gets its
--     ctags file built here instead, once, in the background - gutentags
--     rewrites the whole tags file on every save, which costs seconds on a
--     kernel-sized (~0.9 GB) index
--   * :GtagsIndex        rebuild the whole index in the background
--   * :GtagsIndexUpdate  update the index for the current file now
--   * :GtagsIndexStatus  what is running / which database is in use
--
-- Which files are indexed is decided by ~/.local/bin/indexfiles.sh, so
-- ctags (gutentags) and gtags always agree:
--     .indexfiles  ->  git ls-files  ->  cscope.files (F2/mktags.sh)  ->  find
-- Drop a '.indexfiles' in a project root to index exactly what you want.
--
-- Where the database lives
--   GTAGS, GRTAGS and GPATH go into a hidden directory in the project root
--   ('<root>/.tags/'), so nothing visible is dropped into the source tree.
--   GNU global only looks inside such a directory when GTAGSOBJDIR names it,
--   so this plugin exports GTAGSOBJDIR='.tags' once for the session - that is
--   what makes :Gtags, gtags-cscope, RelationView and a plain 'global' child
--   process work, in every project, without ever being re-pointed. A database
--   still lying at a project root (what mktags.sh used to write) keeps working
--   and is moved into the hidden directory the first time the project is seen.
--
-- Options (.vimrc)
--   g:autoindex_gtags        1: enable everything here      (default 1)
--   g:autoindex_auto_create  1: build a missing index       (default 1)
--   g:autoindex_notify       1: report build start/end      (default 1)
--   g:autoindex_dbdir        hidden database directory, relative to the
--                            project root (default '.tags', '' = the root
--                            itself, which is the old layout)
--   g:autoindex_startup      1: refresh/build the index of the current
--                            project at startup               (default 1)
--   g:autoindex_startup_ctags  1: also ask gutentags to refresh ctags at
--                            startup                          (default 1)
--   g:autoindex_migrate      1: move a database found at a project root
--                            into the hidden directory        (default 1)
--   g:autoindex_spotlight_exclude  0 to skip the '.metadata_never_index'
--                                marker in the database directory (macOS)
--   g:autoindex_ctags_max_files  projects with more files than this are
--                            too big for gutentags (default 5000, 0 = no
--                            limit); their ctags file is built here instead
--   g:autoindex_ctags        1: build that ctags file            (default 1)
--   g:autoindex_ctags_args   ctags flags for it (default
--                            '--fields=+n --excmd=number': line numbers
--                            instead of search patterns, ~30% smaller -
--                            1.0 GB instead of 1.4 GB on a kernel tree.
--                            Drop '--excmd=number' to keep the patterns,
--                            which survive edits made outside nvim)
--   g:autoindex_ctags_max_age  rebuild the snapshot when it is older than
--                            this many days (default 7, 0 = never)
--   g:autoindex_tagfunc      1: answer C-] from GTAGS            (default 1)

if vim.g.loaded_autoindex then
  return
end
vim.g.loaded_autoindex = 1

if vim.fn.has('nvim-0.10') == 0 then
  return
end

local api = vim.api
local uv = vim.uv

local function cfg(name, default)
  local v = vim.g['autoindex_' .. name]
  if v == nil or v == '' then
    return default
  end
  return v
end

local function enabled()
  return cfg('gtags', 1) ~= 0
end

-- the same set indexfiles.sh and projectfiles.lua use - keep the three in
-- step, or a save updates the index for a file the list does not contain
-- (or fails to update one it does). 'Makefile' has no extension, so names
-- are matched too.
local INDEXED, INDEXED_NAME = {}, {}
for e in ('c cc cpp cxx h hh hpp hxx s S java kt kts rs aidl py pl sh bash zsh ksh awk lua vim tcl mk mak cmake gradle pro bp bb bbappend bbclass inc dts dtsi xml json yaml yml toml ini cfg conf properties env rc reg md txt rst ld lds def map te pc'):gmatch('%S+') do
  INDEXED[e] = true
end
for b in ('Makefile makefile GNUmakefile Kconfig Kbuild BUILD WORKSPACE Dockerfile README LICENSE NOTICE'):gmatch('%S+') do
  INDEXED_NAME[b] = true
end

local function global_cmd()
  if vim.fn.executable('global') == 1 then
    return 'global'
  end
  local p = vim.fn.expand('~/.local/bin/global')
  return vim.fn.executable(p) == 1 and p or nil
end

local function gtags_cmd()
  if vim.fn.executable('gtags') == 1 then
    return 'gtags'
  end
  local p = vim.fn.expand('~/.local/bin/gtags')
  return vim.fn.executable(p) == 1 and p or nil
end

local function filelist_cmd()
  local p = vim.fn.expand('~/.local/bin/indexfiles.sh')
  return vim.fn.executable(p) == 1 and p or nil
end

local drain        -- defined below; a finished build flushes the queue
local refresh      -- defined below; re-entered through the pending queue
local ctags_build  -- defined below, used by guard_ctags
local ctags_apply
local ctags_stale

local s = {
  roots = {},     -- dir -> gtags root ('' = none, only cached when found)
  building = {},  -- root -> true while a full build runs
  tried = {},     -- root -> true once an automatic build was started
  pending = {},   -- root -> { path = true } queued single updates
  updating = {},  -- root -> true while a single update runs
  warned = {},    -- root -> true once a leftover root database was reported
  refreshing = {},-- root -> true while an incremental refresh runs
  ctags_building = {}, -- root -> true while a big-tree ctags build runs
  ctags_tried = {},    -- root -> true once a ctags build was started
  lists = {},          -- root -> cached '.tags/files' membership
  refresh_again = {},  -- root -> a refresh requested while one was running
  locked = {},         -- root -> true while THIS nvim holds the index lock
  gt = {},             -- gutentags 루트 -> 'no'/'yes' (붙일지 이미 판단했다)
}

-- g:autoindex_debug = 1 -> append a line per index action to
-- stdpath('cache')/autoindex.log (useful when an update seems to go missing)
local function dbg(msg)
  if cfg('debug', 0) == 0 then
    return
  end
  local f = io.open(vim.fn.stdpath('cache') .. '/autoindex.log', 'a')
  if f then
    f:write(os.date('%H:%M:%S ') .. msg .. '\n')
    f:close()
  end
end

local function notify(msg, level)
  if cfg('notify', 1) ~= 0 then
    vim.notify('autoindex: ' .. msg, level or vim.log.levels.INFO)
  end
end

-- ---------------------------------------------------------------------------
-- where the database lives
-- ---------------------------------------------------------------------------

-- '.tags' by default; nil means "in the project root itself" (old layout)
local function dbdir_name()
  local d = cfg('dbdir', '.tags')
  if d == nil or d == '' or d == '.' then
    return nil
  end
  return (tostring(d):gsub('/+$', ''))
end

-- The database global will actually use. It looks at '<root>/GTAGS' before
-- '<root>/$GTAGSOBJDIR/GTAGS', so when a project carries both (an old
-- mktags.sh run after the migration, say) the root one wins every query -
-- follow that here, or timestamps, counts and updates would be applied to a
-- database nothing reads.
local function dbpath(root)
  if uv.fs_stat(root .. '/GTAGS') then
    return root
  end
  local d = dbdir_name()
  return d and (root .. '/' .. d) or root
end

-- ---------------------------------------------------------------------------
-- 인덱서 프로세스 관리
--
-- 여기서 띄우는 것들은 몇 분씩 도는 명령이라 세 가지가 다 필요하다.
--
--  1. 고아가 되지 않을 것. 예전에는 전부 { 'sh', '-c', ... } 로 띄웠는데,
--     nvim 이 끝날 때 죽는 것은 sh 이고 진짜 일꾼인 gtags 는 손자여서
--     살아남아 PPID=1 이 된다. 공유 서버에서 실제로 gtags 11개가 각각
--     99.9% CPU 로 16시간을 돌고 있었다(11코어 상시 점유). 그래서 무거운
--     명령은 셸을 거치지 않고 argv 로 직접 띄운다. 그러면 vim.system 이
--     쥐고 있는 pid 가 일꾼 자신이라 죽일 수 있다.
--  2. 시간 제한. 한 번 멈춘 gtags 는 스스로 끝나지 않는다.
--  3. 인스턴스 간 락. s.building/s.refreshing 은 이 nvim 안에서만 유효해서,
--     같은 트리에 nvim 을 하나 더 띄우면 gtags 가 하나씩 더 붙었다.
--
--   g:autoindex_timeout_min    한 인덱스 작업의 제한 시간, 분 (기본 30, 0=무제한)
--   g:autoindex_lock_stale_min 이만큼 지난 락은 죽은 것으로 본다 (기본 90)
-- ---------------------------------------------------------------------------
local jobs = {}   -- 진행 중인 vim.system 핸들 -> 명령 이름

-- 바깥쪽 시간 제한.
--
-- vim.system 의 timeout 은 nvim 이 살아 있어야 동작한다. nvim 이 SIGKILL 로
-- 죽거나 SSH 세션이 끊기면 그 제한도 같이 사라져서, 멈춘 색인이 영영 남는다
-- (실제로 그렇게 16시간짜리가 생겼다). GNU timeout 은 별개의 프로세스라
-- nvim 이 사라져도 제한을 지키고, 자기가 받은 TERM 을 자식에게 그대로
-- 넘기므로 위의 h:kill() 도 여전히 통한다. 실측으로 확인했다.
-- 없는 환경(맥 기본)에서는 nvim 쪽 제한만 걸린다.
local timeout_cmd  -- nil: 아직 안 찾음, false: 없음
local function timeout_prefix(ms)
  if timeout_cmd == nil then
    timeout_cmd = false
    for _, c in ipairs({ 'timeout', 'gtimeout' }) do
      if vim.fn.executable(c) == 1 then
        timeout_cmd = c
        break
      end
    end
  end
  if not timeout_cmd or not ms then
    return nil
  end
  -- nvim 쪽 제한보다 조금 늦게 끊는다. 정상 경로에서는 nvim 이 먼저 처리해
  -- 로그와 알림이 남고, 이건 nvim 이 없을 때만 실제로 발동한다.
  return { timeout_cmd, '-k', '10', tostring(math.floor(ms / 1000) + 30) }
end

-- 셸 없이 띄우고, 핸들을 기억하고, 시간 제한을 건다.
-- 공유 서버에서는 색인이 에디터와 CPU/IO 를 다툰다.
--
-- 개발서버는 60코어에 841 로그인이고, 여기서 도는 색인기는 지금까지
-- 에디터와 같은 우선순위였다. 색인은 몇 초 늦어도 되지만 타자는 그렇지
-- 않으니, 배경 일꾼은 양보하게 한다.
--
-- 이 파일의 spawn() 은 전부 배경 작업이다(전체/증분 빌드, 파일목록,
-- 저장 후 단일 갱신, ctags 빌드). C-] 이 쓰는 tagfunc 의 'global -d' 는
-- spawn 을 거치지 않는다 - 그건 사용자가 답을 기다리는 자리라서 양보하면
-- 오히려 나빠진다.
--
--   let g:autoindex_nice = 0     " 양보하지 않기
--   let g:autoindex_nice = 19    " 최대한 양보 (부하가 높으면 굶을 수 있다)
--   let g:autoindex_ionice = 0   " IO 우선순위는 건드리지 않기
local nice_cmd, ionice_cmd  -- nil=미탐색, false=없음

local function nice_prefix()
  local out = {}
  local n = tonumber(cfg('nice', 10)) or 0
  if n > 0 then
    if nice_cmd == nil then
      nice_cmd = vim.fn.executable('nice') == 1
    end
    if nice_cmd then
      out[#out + 1] = 'nice'
      out[#out + 1] = '-n'
      out[#out + 1] = tostring(math.min(19, n))
    end
  end
  -- ionice 는 리눅스 것이다 (맥에는 없다). best-effort 의 가장 낮은
  -- 우선순위를 쓴다 - idle 클래스(-c3)는 부하가 계속 있으면 아예 진행하지
  -- 못할 수 있다.
  local io_n = tonumber(cfg('ionice', 7)) or 0
  if io_n > 0 then
    if ionice_cmd == nil then
      ionice_cmd = vim.fn.executable('ionice') == 1
    end
    if ionice_cmd then
      out[#out + 1] = 'ionice'
      out[#out + 1] = '-c'
      out[#out + 1] = '2'
      out[#out + 1] = '-n'
      out[#out + 1] = tostring(math.min(7, io_n))
    end
  end
  return #out > 0 and out or nil
end

local function spawn(cmd, opts, cb)
  opts = vim.tbl_extend('keep', opts or {}, {})
  if opts.timeout == nil then
    local m = tonumber(cfg('timeout_min', 30)) or 30
    opts.timeout = m > 0 and math.floor(m * 60 * 1000) or nil
  elseif opts.timeout == 0 then
    opts.timeout = nil
  end
  local argv = cmd
  local pre = timeout_prefix(opts.timeout)
  if pre then
    argv = vim.list_extend(pre, cmd)
  end
  -- nice 를 가장 앞에: 'nice ionice timeout <초> <명령>' 이라 timeout 이
  -- 재는 대상은 명령 그대로다
  local np = nice_prefix()
  if np then
    argv = vim.list_extend(np, argv)
  end
  local h
  local ok, err = pcall(function()
    h = vim.system(argv, opts, function(o)
      if h then
        jobs[h] = nil
      end
      cb(o)
    end)
  end)
  if not ok or not h then
    dbg('spawn 실패 (' .. tostring(cmd[1]) .. '): ' .. tostring(err))
    return nil
  end
  jobs[h] = cmd[1]
  return h
end

-- 목록 생성기의 stdout 을 파일로 쓰고 줄 수를 돌려준다. 예전에는 셸의
-- '> list && wc -l' 이 하던 일이다.
local function write_filelist(path, text)
  if not text or text == '' then
    return 0
  end
  if text:sub(-1) ~= '\n' then
    text = text .. '\n'
  end
  local f = io.open(path, 'w')
  if not f then
    return 0
  end
  f:write(text)
  f:close()
  local n = 0
  for _ in text:gmatch('[^\n]+') do n = n + 1 end
  return n
end

local function pid_alive(pid)
  if not pid or pid <= 0 then
    return false
  end
  local ok, res, err = pcall(uv.kill, pid, 0)
  if not ok then
    return false
  end
  if res == 0 then
    return true
  end
  -- 다른 사용자의 프로세스면 EPERM 이 온다. 살아 있다는 뜻이다.
  return type(err) == 'string' and err:find('EPERM') ~= nil
end

local function lock_path(root, name)
  return dbpath(root) .. '/.autoindex' .. (name and ('-' .. name) or '') .. '.lock'
end

local function read_lock(root, name)
  local f = io.open(lock_path(root, name), 'r')
  if not f then
    return nil
  end
  local line = f:read('*l') or ''
  f:close()
  local pid, host, t = line:match('^(%d+)\t([^\t]*)\t(%d+)$')
  if not pid then
    return nil -- 형식이 깨진 락은 없는 것으로 본다
  end
  return { pid = tonumber(pid), host = host, t = tonumber(t) }
end

local function lock_held(info)
  if not info then
    return false
  end
  local stale = (tonumber(cfg('lock_stale_min', 90)) or 90) * 60
  if os.time() - (info.t or 0) > stale then
    return false
  end
  if info.host ~= uv.os_gethostname() then
    return true -- 다른 기계의 pid 는 확인할 수 없으니 나이만 믿는다
  end
  return pid_alive(info.pid)
end

local function write_lock(root, name)
  local body = ('%d\t%s\t%d\n'):format(uv.os_getpid(), uv.os_gethostname(),
    os.time())
  -- O_EXCL 로 만든다: 두 nvim 이 동시에 들어와도 하나만 성공한다
  local fd = uv.fs_open(lock_path(root, name), 'wx', 420)
  if not fd then
    return false
  end
  pcall(uv.fs_write, fd, body)
  pcall(uv.fs_close, fd)
  return true
end

-- 이 트리의 색인 권한을 잡는다. false 면 다른 nvim 이 이미 돌리고 있다.
local function take_lock(root, name)
  local key = (name or '') .. '\0' .. root
  if s.locked[key] then
    return true
  end
  pcall(vim.fn.mkdir, dbpath(root), 'p')
  if not write_lock(root, name) then
    local cur = read_lock(root, name)
    if lock_held(cur) then
      dbg(('lock busy %s%s (pid %s @ %s)'):format(root,
        name and (' [' .. name .. ']') or '', tostring(cur.pid),
        tostring(cur.host)))
      return false
    end
    -- 주인이 없는 락이다. 치우고 한 번만 다시 시도한다.
    pcall(os.remove, lock_path(root, name))
    if not write_lock(root, name) then
      return false
    end
  end
  s.locked[key] = { root = root, name = name }
  return true
end

local function release_lock(root, name)
  local key = (name or '') .. '\0' .. root
  if not s.locked[key] then
    return
  end
  s.locked[key] = nil
  local cur = read_lock(root, name)
  if cur and cur.pid == uv.os_getpid() and cur.host == uv.os_gethostname() then
    pcall(os.remove, lock_path(root, name))
  end
end

-- nvim 이 끝날 때 일꾼과 락을 같이 정리한다. 이게 없으면 고아가 남는다.
api.nvim_create_autocmd('VimLeavePre', {
  group = api.nvim_create_augroup('AutoIndexCleanup', { clear = true }),
  callback = function()
    for h in pairs(jobs) do
      pcall(function() h:kill('sigterm') end)
    end
    for _, l in pairs(s.locked) do
      release_lock(l.root, l.name)
    end
  end,
})


-- global(1) walks up looking for '<dir>/GTAGS'; with GTAGSOBJDIR set it also
-- looks for '<dir>/$GTAGSOBJDIR/GTAGS'. One value covers every project (and
-- still finds a database left at a project root), so unlike
-- GTAGSROOT/GTAGSDBPATH it never has to be re-pointed per buffer.
local function db_env()
  local d = dbdir_name()
  return d and { GTAGSOBJDIR = d } or nil
end

-- children are always started with cwd = the project root, so the objdir
-- name is all they need
local function env_for(_)
  return db_env()
end

local function has_db(dir)
  local d = dbdir_name()
  return (d and uv.fs_stat(dir .. '/' .. d .. '/GTAGS') ~= nil)
      or uv.fs_stat(dir .. '/GTAGS') ~= nil
end

-- Move a database written at the project root (mktags.sh/F2, or an older
-- version of this plugin) into the hidden directory. Renaming inside the
-- same directory is atomic and instant even for a kernel-sized database.
local function migrate(root)
  local d = dbdir_name()
  if not d or cfg('migrate', 1) == 0 or not uv.fs_stat(root .. '/GTAGS') then
    return
  end
  -- 루트가 데이터베이스 디렉터리 자체면 옮기지 않는다: '<root>/.tags' 의
  -- DB 를 '<root>/.tags/.tags/' 로 넣는 짓이 된다 (scan_root 의 설명 참고).
  if vim.fs.basename(root) == d then
    return
  end
  if uv.fs_stat(root .. '/' .. d .. '/GTAGS') then
    -- both layouts present: the hidden one is used, say so once
    if not s.warned[root] then
      s.warned[root] = true
      notify(vim.fn.fnamemodify(root, ':~') ..
        ': GTAGS 가 루트에도 있어 그쪽이 쓰입니다(global 우선순위). ' ..
        d .. '/ 만 쓰려면 루트의 GTAGS/GRTAGS/GPATH 를 지우세요(F12)',
        vim.log.levels.WARN)
    end
    return
  end
  vim.fn.mkdir(root .. '/' .. d, 'p')
  local moved = 0
  for _, f in ipairs({ 'GTAGS', 'GRTAGS', 'GPATH' }) do
    if uv.fs_stat(root .. '/' .. f) then
      if uv.fs_rename(root .. '/' .. f, root .. '/' .. d .. '/' .. f) then
        moved = moved + 1
      end
    end
  end
  if moved > 0 then
    notify(vim.fn.fnamemodify(root, ':~') .. ': 색인을 ' .. d .. '/ 로 옮겼습니다')
  end
end

-- Keep the database out of 'git status' (and out of the nerdtree git
-- plugin's way). .git/info/exclude is local to the clone and never committed.
local function git_exclude(root)
  local d = dbdir_name()
  if not d or cfg('git_exclude', 1) == 0 then
    return
  end
  local info = root .. '/.git/info'
  if not uv.fs_stat(root .. '/.git') or not uv.fs_stat(info) then
    return
  end
  local file = info .. '/exclude'
  local line = '/' .. d .. '/'
  local lines = uv.fs_stat(file) and vim.fn.readfile(file) or {}
  for _, l in ipairs(lines) do
    if l == line or l == d or l == d .. '/' then
      return
    end
  end
  lines[#lines + 1] = line
  pcall(vim.fn.writefile, lines, file)
end

-- The databases are rewritten whole on every full index (GTAGS+GRTAGS are
-- megabytes), and on macOS every rewrite is work for Spotlight - which can
-- never do anything useful with a gtags database anyway. One marker file
-- keeps mdworker out of the directory.
local function never_index(dir)
  if cfg('spotlight_exclude', 1) == 0 or vim.fn.has('mac') == 0 then
    return
  end
  local marker = dir .. '/.metadata_never_index'
  if uv.fs_stat(marker) then
    return
  end
  pcall(vim.fn.writefile, {}, marker)
end

-- nearest directory at or above `dir` that holds a database
local function scan_root(dir)
  -- 데이터베이스 디렉터리 자체를 프로젝트 루트로 잡지 않는다.
  --
  -- has_db(d) 는 예전 배치(루트에 GTAGS)도 인정하므로, '<root>/.tags' 에서
  -- 출발하면 거기서 '<root>/.tags/GTAGS' 를 보고 '.tags' 를 루트라고 답한다.
  -- 그러면 migrate() 가 그 DB 를 '<root>/.tags/.tags/' 로 옮기고, 색인은
  -- 원래 자리에서 사라진다. 실제로 그렇게 프로젝트 색인이 통째로 없어졌다
  -- (그 안의 파일을 버퍼로 열기만 해도 걸린다). 먼저 그 디렉터리에서 나온다.
  local d = dir
  local dbn = dbdir_name()
  if dbn and dbn ~= '' then
    local tail = '/' .. dbn
    while d and #d > #tail and d:sub(-#tail) == tail do
      d = d:sub(1, #d - #tail)
    end
  end
  while d and d ~= '' do
    if has_db(d) then
      return d
    end
    local parent = vim.fs.dirname(d)
    if not parent or parent == d then
      return nil
    end
    d = parent
  end
  return nil
end

-- Every child of nvim - :Gtags, gtags-cscope, RelationView, :! - inherits
-- this, and it stays correct whatever project the child runs in.
local function apply_env()
  local d = dbdir_name()
  if d and vim.env.GTAGSOBJDIR ~= d then
    vim.env.GTAGSOBJDIR = d
  end
end

apply_env()

-- the project root of the database above `dir`, or nil. Resolved on the
-- file system (a hidden database is invisible to 'global -p'), cached per
-- directory; misses are not cached so a fresh build is picked up at once.
local function gtags_root(dir, cb)
  local hit = s.roots[dir]
  if hit then
    cb(hit)
    return
  end
  local root = scan_root(dir)
  if root then
    migrate(root)
    git_exclude(root)
    s.roots[dir] = root
  end
  cb(root)
end

-- project root by marker, for the case where no index exists yet
local function marker_root(path)
  local found = vim.fs.find({ '.git', '.project', '.root' },
    { path = path, upward = true, type = 'directory' })[1]
      or vim.fs.find({ '.git', '.project', '.root', '.indexfiles',
        'cscope.files' }, { path = path, upward = true })[1]
  return found and vim.fs.dirname(found) or nil
end

local EXCLUDED, EXCLUDED_NAME = {}, {}
for e in ('o a so ko obj lo la exe dll dylib bin img elf hex bpf gz bz2 xz zst lz4 zip tar tgz tbz jar apk aar dex odex vdex rar 7z iso dmg png jpg jpeg gif bmp ico webp tiff tif psd svgz mp3 mp4 avi mkv wav flac ogg opus webm pdf doc docx xls xlsx ppt pptx odt ods pyc pyo pyd class pdb ilk exp d cmd pack idx swp swo swn ttf otf woff woff2 eot db sqlite sqlite3 dat rom fw uimage flat rsp srcjar kapt_metadata jack toc lst gcno gcda su i ii stamp timestamp'):gmatch('%S+') do
  EXCLUDED[e] = true
end
for b in ('tags TAGS cscope.out cscope.in.out cscope.po.out GTAGS GRTAGS GPATH core .DS_Store'):gmatch('%S+') do
  EXCLUDED_NAME[b] = true
end

-- 기본은 '모든 파일'이다: 전부 색인 대상으로 보고 산출물/바이너리만 뺀다.
-- projectfiles.lua 와 indexfiles.sh 의 같은 판정과 맞춰 두어야 한다.
--   let g:autoindex_all_files = 0   " 예전처럼 확장자 허용목록만
local function indexed_file(path)
  local base = path:match('([^/]+)$') or path
  if cfg('all_files', 1) ~= 0 then
    if EXCLUDED_NAME[base] then
      return false
    end
    local e = base:match('%.([%w_]+)$')
    return not (e and EXCLUDED[e:lower()])
  end
  if INDEXED_NAME[base] then
    return true
  end
  local ext = base:match('%.([%w_]+)$')
  return ext ~= nil and INDEXED[ext] == true
end

-- ---------------------------------------------------------------------------
-- full build:  indexfiles.sh | gtags -f -
-- ---------------------------------------------------------------------------
-- how many files the index at root currently covers (0: no index)
local function db_file_count(root, cb)
  local prog = global_cmd()
  if not prog or not uv.fs_stat(dbpath(root) .. '/GTAGS') then
    cb(0)
    return
  end
  -- 셸을 거치지 않는다(고아 방지). wc -l 은 Lua 가 대신 센다.
  local h = spawn({ prog, '-P', '' },
    { text = true, cwd = root, env = env_for(root),
      timeout = 60 * 1000 }, function(o)
      vim.schedule(function()
        local nlines = 0
        if o.code == 0 then
          for _ in (o.stdout or ''):gmatch('[^\n]+') do nlines = nlines + 1 end
        end
        cb(nlines)
      end)
    end)
  if not h then
    cb(0)
  end
end

-- Build the whole index in the background.
--   opts.confirm: ask before an index that covers far fewer files than the
--                 current one replaces it (a partial cscope.files or a
--                 narrow .indexfiles otherwise silently drops most symbols)
local function build(root, why, opts)
  opts = opts or {}
  if not enabled() or s.building[root] then
    return
  end
  local gt, fl = gtags_cmd(), filelist_cmd()
  if not gt or not fl then
    notify('gtags 또는 indexfiles.sh 를 찾을 수 없습니다', vim.log.levels.WARN)
    return
  end
  local short = vim.fn.fnamemodify(root, ':~')
  -- 다른 nvim 이 이미 이 트리를 색인 중이면 손대지 않는다. 이 락이 없던
  -- 동안에는 nvim 을 열 때마다 같은 트리에 gtags 가 하나씩 더 붙었다.
  if not take_lock(root) then
    notify(short .. ' 은 다른 nvim 이 색인 중입니다 — 건너뜁니다')
    return
  end
  s.building[root] = true
  notify('indexing ' .. short .. (why and (' (' .. why .. ')') or '') .. ' …')
  local t0 = uv.now()
  -- Build into a temporary database and move it in when it is complete:
  -- writing GTAGS in place would make every query in the meantime fail
  -- with "GTAGS seems corrupted".
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local list = tmp .. '/files'

  local function fail(msg)
    s.building[root] = nil
    release_lock(root)
    pcall(vim.fn.delete, tmp, 'rf')
    if msg then
      notify(msg, vim.log.levels.WARN)
    end
  end

  -- 3. gtags over the file list, then move the finished database in
  local function run_gtags(n)
    local dest = dbpath(root)
    vim.fn.mkdir(dest, 'p')
    never_index(dest)
    -- 셸 없이 gtags 자체를 띄운다. 완성된 DB 를 옮기는 일은 Lua 가 한다.
    -- (예전에는 sh -c '... && mv ...' 이라, nvim 이 죽으면 sh 만 죽고
    --  gtags 는 손자로 살아남아 CPU 를 문 채 고아가 됐다.)
    local ok = spawn({ gt, '-f', list, tmp },
      { text = true, cwd = root, env = { GTAGSROOT = root, GTAGSDBPATH = tmp } },
      function(o)
      vim.schedule(function()
        if o.code == 0 then
          for _, f in ipairs({ 'GTAGS', 'GRTAGS', 'GPATH' }) do
            local from, to = tmp .. '/' .. f, dest .. '/' .. f
            if not uv.fs_rename(from, to) then
              -- 파일시스템이 다르면 rename 이 안 된다: 복사로 대신한다
              if uv.fs_copyfile(from, to) then
                pcall(uv.fs_unlink, from)
              else
                o = vim.tbl_extend('force', o,
                  { code = 1, stderr = (o.stderr or '') ..
                    '\n색인을 옮기지 못했습니다: ' .. to })
                break
              end
            end
          end
        end
        s.building[root] = nil
        release_lock(root)
        s.roots = {} -- a new database may have appeared above other dirs too
        pcall(vim.fn.delete, tmp, 'rf')
        git_exclude(root)
        -- files saved while the build ran were queued and skipped: flush them
        drain(root)
        local again = s.refresh_again[root]
        if again then
          s.refresh_again[root] = nil
          vim.schedule(function() refresh(root, again.why, again.force) end)
        end
        if o.code == 0 then
          notify(string.format('%s indexed: %d files, %.1fs',
            short, n, (uv.now() - t0) / 1000))
        else
          notify('indexing failed: ' ..
            ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))),
            vim.log.levels.WARN)
        end
      end)
    end)
    if not ok then
      fail(nil)
    end
  end

  -- 2. refuse (or ask) when the new list covers far fewer files
  local function check_coverage(n)
    db_file_count(root, function(old)
      if old < 100 or n >= math.floor(old / 2) then
        run_gtags(n)
        return
      end
      local msg = string.format(
        '%s: 색인 대상이 %d개 -> %d개로 줄어듭니다 (부분 cscope.files/.indexfiles?)',
        short, old, n)
      if not opts.confirm then
        fail(msg .. ' - 자동 재색인을 건너뜁니다 (:GtagsIndex 로 강제)')
        return
      end
      if vim.fn.confirm(msg .. '\n그대로 다시 색인할까요?', '&Yes\n&No', 2) == 1 then
        run_gtags(n)
      else
        fail(nil)
      end
    end)
  end

  -- 1. file list first, so its size can be judged before the index is replaced
  -- a preset decides which files exist for the indexer: write it out before
  -- the list is generated, or the very first build indexes the whole tree
  pcall(function()
    if _G.projectfiles_materialize then
      _G.projectfiles_materialize(root)
    end
  end)
  -- 셸 없이 목록 생성기만 띄우고, 파일로 쓰는 것과 줄 세기는 Lua 가 한다
  local ok = spawn({ fl }, { text = true, cwd = root,
      timeout = (tonumber(cfg('filelist_timeout_sec', 300)) or 300) * 1000 },
    function(o)
      vim.schedule(function()
        local n = write_filelist(list, o.code == 0 and o.stdout or nil)
        if o.code ~= 0 or n == 0 then
          fail('색인할 파일을 찾지 못했습니다: ' .. short)
          return
        end
        check_coverage(n)
      end)
    end)
  if not ok then
    fail(nil)
  end
end

-- ---------------------------------------------------------------------------
-- incremental refresh of a whole project (startup)
-- ---------------------------------------------------------------------------
-- 'gtags -i -f list' reindexes only files whose timestamp moved and keeps the
-- database equal to the list - unlike 'global -u', which walks the tree itself
-- and would pull in files a project deliberately left out of .indexfiles.
-- 'equal to the list' cuts both ways: see the coverage check below.
function refresh(root, why, force)
  if not enabled() then
    return
  end
  -- A list change while a refresh is still running must not be dropped:
  -- remember it and run once more when this one finishes (adding a file to
  -- a preset right after switching to it would otherwise never be indexed).
  if s.building[root] or s.refreshing[root] then
    s.refresh_again[root] = { why = why, force = force }
    return
  end
  local gt, fl = gtags_cmd(), filelist_cmd()
  if not gt or not fl then
    return
  end
  -- build 와 같은 이유로 인스턴스 간 락을 먼저 잡는다
  if not take_lock(root) then
    dbg('refresh 건너뜀 (다른 nvim 이 색인 중) ' .. root)
    return
  end
  s.refreshing[root] = true
  local short = vim.fn.fnamemodify(root, ':~')
  local t0 = uv.now()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local list = tmp .. '/files'

  local function done(msg, level)
    s.refreshing[root] = nil
    release_lock(root)
    pcall(vim.fn.delete, tmp, 'rf')
    drain(root)
    if msg then
      notify(msg, level)
    end
    local again = s.refresh_again[root]
    if again then
      s.refresh_again[root] = nil
      vim.schedule(function() refresh(root, again.why, again.force) end)
    end
  end

  -- 증분 갱신은 자리를 되돌려주지 않는다.
  --
  -- 'gtags -i' 는 바뀐 파일만 다시 넣지만 빠진 자리를 회수하지는 않는다.
  -- 실측(2026-09-12, kernel/common): 목록 273개 / DB 가 담은 것 205개인데
  -- GTAGS 707MB + GRTAGS 551MB 였다. 같은 목록으로 처음부터 다시 만들면
  -- 0.18초에 GTAGS 656KB + GRTAGS 2.1MB - 1,100배와 260배다. 답은 똑같다.
  -- 그동안 'global' 은 질의마다 그 1.25GB 를 뒤지고 있었다.
  --
  -- 그래서 가끔 통째로 다시 만든다. 둘 중 먼저 걸리는 쪽으로:
  --   * 증분 갱신을 g:autoindex_compact_every 번 했을 때 (기본 200)
  --   * DB 가 파일당 g:autoindex_compact_bytes 를 넘었을 때 (기본 256KB.
  --     정상은 파일당 2KB 안팎이다 - 루트 프로젝트가 1091 파일에 2.3MB)
  -- 전체 빌드는 임시 디렉터리에 만들고 다 되면 옮기므로, 만드는 동안에도
  -- 질의는 예전 DB 로 계속 답한다.
  --   let g:autoindex_compact_every = 0   " 횟수로는 다시 만들지 않기
  --   let g:autoindex_compact_bytes = 0   " 크기로는 다시 만들지 않기
  --   :GtagsCompact                       " 지금 한 번
  local function compact_file(r)
    return dbpath(r) .. '/compact'
  end

  local function compact_count(r)
    local ok, l = pcall(vim.fn.readfile, compact_file(r), '', 1)
    return (ok and l and tonumber(l[1])) or 0
  end

  local function compact_bump(r, reset)
    local n = reset and 0 or (compact_count(r) + 1)
    pcall(vim.fn.writefile, { tostring(n) }, compact_file(r))
    return n
  end

  -- 지금 다시 만들 때가 되었는가. 이유를 돌려준다(없으면 nil).
  local function compact_due(r, nfiles)
    local every = tonumber(cfg('compact_every', 200)) or 200
    if every > 0 and compact_count(r) >= every then
      return ('증분 갱신 %d회'):format(compact_count(r))
    end
    local per = tonumber(cfg('compact_bytes', 256 * 1024)) or 256 * 1024
    if per > 0 and nfiles and nfiles > 0 then
      local tot = 0
      for _, f in ipairs({ 'GTAGS', 'GRTAGS' }) do
        local st = uv.fs_stat(dbpath(r) .. '/' .. f)
        tot = tot + ((st and st.size) or 0)
      end
      if tot > per * nfiles then
        return ('DB %dMB / 파일 %d개'):format(math.floor(tot / 1048576), nfiles)
      end
    end
    return nil
  end

  local function run_incremental(n)
    -- 셸 없이. 고아가 된 gtags 11개가 전부 이 자리에서 나왔다.
    -- 증분 갱신에 30분(spawn 의 기본값)은 너무 관대하다. 목록이 정해져
    -- 있으니 정상이면 초 단위로 끝나는데, gtags 가 이 DB 에서 병적으로
    -- 도는 경우가 실제로 있었다 - 입력 파일은 하나도 열지 않고
    -- GPATH/GTAGS 만 붙든 채 상태 R 로 코어 하나를 계속 먹었다(한 번은
    -- 13시간, 한 번은 13분까지 확인). 전체 빌드는 커널 트리에서 수십 초가
    -- 정상이라 그쪽 기본값은 그대로 둔다.
    --   let g:autoindex_incremental_timeout_min = 0   " 제한 없음
    local imin = tonumber(cfg('incremental_timeout_min', 5)) or 5
    local ok = spawn({ gt, '-i', '-f', list, dbpath(root) },
      { text = true, cwd = root, env = env_for(root),
        timeout = imin > 0 and math.floor(imin * 60 * 1000) or 0 }, function(o)
        vim.schedule(function()
          local secs = (uv.now() - t0) / 1000
          if o.code ~= 0 then
            done(short .. ' 색인 갱신 실패: ' ..
              ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))),
              vim.log.levels.WARN)
          else
            compact_bump(root)
            local due = compact_due(root, n)
            if due then
              -- 자리를 회수한다. done() 을 먼저 불러 이 갱신을 끝내고,
              -- 전체 빌드는 그 다음 차례에 새로 시작한다(build 는 스스로
              -- 락을 잡는다 - 지금 잡고 있는 것을 놓기 전에 부르면 '다른
              -- nvim 이 색인 중'으로 스스로를 막는다).
              done(nil)
              vim.schedule(function()
                compact_bump(root, true)
                build(root, '자리 되찾기 (' .. due .. ')', {})
              end)
              return
            end
            if secs > 3 then
              -- small projects finish before anyone notices; stay quiet there
              done(string.format('%s 색인 갱신 완료 (%d files, %.1fs%s)', short,
                n, secs, why and (', ' .. why) or ''))
            else
              done(nil)
            end
          end
        end)
      end)
    if not ok then
      done(nil)
    end
  end

  -- 'gtags -i -f list' makes the database match the list: files missing from
  -- it are DELETED from the index. A half-written cscope.files or a narrowed
  -- .indexfiles would silently throw most of the project away, so the same
  -- coverage check the full build uses guards this too - but here it only
  -- skips (a background job at startup must not ask questions).
  local function check(n)
    if force then
      run_incremental(n) -- the user just changed the list on purpose
      return
    end
    db_file_count(root, function(old)
      if old < 100 or n >= math.floor(old / 2) then
        run_incremental(n)
        return
      end
      done(string.format(
        '%s: 색인 %d개 -> %d개 축소, 자동 갱신 생략 (:GtagsIndex)',
        short, old, n), vim.log.levels.WARN)
    end)
  end

  -- a preset decides which files exist for the indexer: write it out before
  -- the list is generated, or the very first build indexes the whole tree
  pcall(function()
    if _G.projectfiles_materialize then
      _G.projectfiles_materialize(root)
    end
  end)
  local ok = spawn({ fl }, { text = true, cwd = root, env = env_for(root),
      timeout = (tonumber(cfg('filelist_timeout_sec', 300)) or 300) * 1000 },
    function(o)
      vim.schedule(function()
        local n = write_filelist(list, o.code == 0 and o.stdout or nil)
        if o.code ~= 0 or n == 0 then
          done(nil)
          return
        end
        check(n)
      end)
    end)
  if not ok then
    done(nil)
  end
end

-- ---------------------------------------------------------------------------
-- incremental update of one file
-- ---------------------------------------------------------------------------
function drain(root)
  if s.updating[root] or s.building[root] or s.refreshing[root] then
    dbg('drain deferred (busy) ' .. root)
    return
  end
  local q = s.pending[root]
  if not q then
    return
  end
  local path = next(q)
  if not path then
    s.pending[root] = nil
    return
  end
  q[path] = nil
  local prog = global_cmd()
  if not prog then
    return
  end
  s.updating[root] = true
  local rel = path:sub(1, #root + 1) == root .. '/' and path:sub(#root + 2)
      or path
  dbg('single-update ' .. rel .. ' (cwd ' .. root .. ')')
  local ok = spawn({ prog, '--single-update', rel },
    { text = true, cwd = root, env = env_for(root),
      timeout = (tonumber(cfg('update_timeout_sec', 120)) or 120) * 1000 },
    function(o)
      vim.schedule(function()
        s.updating[root] = nil
        dbg('single-update rc=' .. tostring(o.code) .. ' ' .. rel ..
          ((o.stderr or '') ~= '' and (' err=' .. o.stderr:gsub('%s+$', '')) or ''))
        if o.code ~= 0 and not s.warned['u:' .. root] then
          s.warned['u:' .. root] = true
          notify('색인 갱신 실패(' .. rel .. '): ' ..
            ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))) ..
            ' - :GtagsIndex 로 다시 만들 수 있습니다', vim.log.levels.WARN)
        end
        drain(root)
      end)
    end)
  if not ok then
    s.updating[root] = nil
  end
end

-- '<root>/.tags/files' is the preset list (see projectfiles.lua). While it
-- exists, only the files in it belong to the index - saving anything else
-- must not quietly add it.
local function in_list(root, path)
  local file = dbpath(root) .. '/files'
  if dbpath(root) == root then
    file = root .. '/' .. (dbdir_name() or '.tags') .. '/files'
  end
  local st = uv.fs_stat(file)
  if not st then
    return true -- auto mode: everything in the project counts
  end
  local c = s.lists[root]
  if not c or c.mtime ~= st.mtime.sec then
    c = { mtime = st.mtime.sec, set = {} }
    for _, l in ipairs(vim.fn.readfile(file)) do
      l = l:gsub('^%./', ''):gsub('%s+$', '')
      if l ~= '' then
        c.set[l] = true
      end
    end
    s.lists[root] = c
  end
  local rel = path:sub(1, #root + 1) == root .. '/' and path:sub(#root + 2) or path
  return c.set[rel] == true
end

-- 색인을 시작하기 전에 '어떤 모드로 색인할지'가 정해져 있는지 확인한다.
-- 정해져 있으면 그대로 진행하고(요청 1), 정해진 적이 없으면 projectfiles 가
-- 물어본 뒤 진행한다(요청 2). 물어볼 수 없는 상황 - 헤드리스, 기능을 끈
-- 경우, projectfiles 가 없는 경우 - 에서는 곧바로 통과한다.
--
-- 색인이 처음 만들어지는 자리가 셋이다: 시작할 때, 색인이 없는 프로젝트의
-- 파일을 열 때, 그런 프로젝트에서 저장할 때. 세 곳 모두 여기를 지나야 한다.
-- 색인을 시작해도 되는 프로젝트인가.
--
-- 모드는 projectfiles.lua 가 '<root>/.tags/preset' 하나로 관리한다:
--   (파일 없음)   아직 아무것도 정하지 않았다 - 아무 일도 하지 않는다
--   none          정해 두었다: 색인하지 않는다
--   auto          프로젝트 전체
--   <preset 이름>  그 목록만
--
-- 예전에는 모드가 없으면 여기서 물어봤다(vim.ui.select). 이제는 묻지
-- 않는다 - 남의 트리나 홈 디렉터리에서 파일 하나 열었을 뿐인데 대화상자가
-- 뜨거나 색인이 시작되는 일이 없어야 한다. 모드를 고르는 것은 <F2> 나
-- \fm 이고, 고르기 전까지 이 프로젝트는 조용하다.
local function with_mode(root, run)
  if not (root and root ~= '') then
    return
  end
  if _G.projectfiles_should_index then
    if _G.projectfiles_should_index(root) then
      run()
    else
      dbg('색인 건너뜀 (모드 ' ..
        tostring(_G.projectfiles_mode and _G.projectfiles_mode(root) or '?')
        .. ') ' .. root)
    end
    return
  end
  run()
end

local function update_file(path)
  if not (enabled() and indexed_file(path)) then
    dbg('update_file ignored ' .. path)
    return
  end
  gtags_root(vim.fs.dirname(path), function(root)
    dbg('update_file ' .. path .. ' root=' .. tostring(root))
    -- none / 미설정 프로젝트는 저장해도 색인하지 않는다. in_list() 는
    -- 목록 파일이 없으면 '전부 대상'으로 답하므로 그 앞에서 막아야 한다.
    if root and _G.projectfiles_should_index
        and not _G.projectfiles_should_index(root) then
      dbg('update_file skipped (색인하지 않는 모드) ' .. path)
      return
    end
    if root and not in_list(root, path) then
      dbg('update_file skipped (not in preset list) ' .. path)
      return
    end
    if root then
      s.pending[root] = s.pending[root] or {}
      s.pending[root][path] = true
      drain(root)
      return
    end
    -- no index yet: build one, once per project per session
    if cfg('auto_create', 1) == 0 then
      return
    end
    local mroot = marker_root(path)
    if mroot and not s.tried[mroot] then
      s.tried[mroot] = true
      with_mode(mroot, function() build(mroot, 'no GTAGS yet') end)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- keep the ctags index (gutentags) out of very large trees
--
-- A kernel tree yields a ~1GB tags file with 4.8M entries: building it is
-- fine but nothing loads it quickly afterwards (:Telescope tags, :tag).
-- gtags covers those trees, so ctags is left to projects small enough for
-- it - and '.indexfiles' can narrow any project down to what you care
-- about, for both indexes at once.
-- ---------------------------------------------------------------------------
local counted = {}

-- 이 프로젝트가 색인할 파일 수를 세어 cb 로 넘긴다(모르면 nil).
--
-- 예전에는 여기서 vim.system(...):wait(1500) 으로 동기 대기를 했고, 그게
-- BufReadPre 에 걸려 있어서 커널 트리에서 첫 파일을 열 때마다 최대 1.5초를
-- 통째로 멈춰 세웠다. 이제는 비동기로 세고, 답이 오면 그때 판단한다.
local function count_files(root, cb)
  local fl = filelist_cmd()
  if not fl then
    cb(nil)
    return
  end
  local h = spawn({ fl }, { text = true, cwd = root,
      timeout = (tonumber(cfg('filelist_timeout_sec', 300)) or 300) * 1000 },
    function(o)
      vim.schedule(function()
        if o.code ~= 0 then
          cb(nil)
          return
        end
        local n = 0
        for _ in (o.stdout or ''):gmatch('[^\n]+') do n = n + 1 end
        cb(n)
      end)
    end)
  if not h then
    cb(nil)
  end
end

-- 이 루트를 gutentags 에서 떼어내고, 대신 ctags 스냅숏을 우리가 만든다.
local function exclude_gutentags(root, why)
  local list = vim.g.gutentags_exclude_project_root or {}
  local known = false
  for _, r in ipairs(list) do
    if r == root then
      known = true
      break
    end
  end
  if not known then
    table.insert(list, root)
    vim.g.gutentags_exclude_project_root = list
    -- keep this on one line: a wrapped message means a hit-enter prompt at
    -- every start in a narrow terminal
    notify(string.format('%s: %s - ctags 는 여기서 직접 만듭니다',
      vim.fn.fnamemodify(root, ':~'), why or 'big tree'))
  end
  if cfg('ctags', 1) ~= 0 and not s.ctags_tried[root] then
    local have = ctags_apply(root)
    if not have or ctags_stale(root) then
      s.ctags_tried[root] = true
      ctags_build(root, have and '오래됨' or (why or 'big tree'))
    end
  end
end

-- gutentags 가 버퍼에 붙기 전에 묻는 자리 (g:gutentags_init_user_func).
-- 0 을 돌려주면 그 버퍼에는 붙지 않는다 - 저장할 때 tags 를 다시 쓰지 않는다.
--
-- 왜 여기서 판단해야 하는가: guard_ctags 는 파일 수를 **비동기로** 센 뒤에
-- 루트를 제외 목록에 넣는데, gutentags 는 그 답을 기다리지 않는다. 그래서
-- 그 루트의 첫 버퍼는 이미 붙은 상태로 남고, 세션이 끝날 때까지 저장마다
-- tags 를 통째로 다시 쓴다. 실측: android/external/bcc 가 제외 목록에
-- 들어간 뒤에도 저장 때 update_tags.sh 가 181MB 파일을 다시 썼다.
--
-- 그리고 파일 수는 비용의 척도가 아니다. bcc 는 git 추적 1,145개인데 tags 가
-- 181MB 다(5000개 기준으로는 영원히 걸리지 않는다). 비용은 바이트다 -
-- gutentags 의 저장 갱신(plat/unix/update_tags.sh)은
--   grep --text -Ev '^[^\t]+\t<그 파일>\t' tags > tags.temp
-- 로 **전체를 읽어 다시 쓴다**. 그래서 stat 한 번으로 바로 정한다.
--
--   let g:autoindex_ctags_max_bytes = 0   " 크기로는 막지 않기
--   let g:autoindex_gutentags_guard = 0   " 이 훅을 아예 끄기
function _G.autoindex_gutentags_ok(path)
  if cfg('gutentags_guard', 1) == 0 or not enabled() then
    return 1
  end
  path = tostring(path or '')
  if path == '' then
    return 1
  end
  -- 모드를 고르지 않은 디렉터리(.tags 없음)와 none 모드에서는 gutentags 도
  -- 붙지 않는다. generate_on_missing 이 켜져 있어서, 붙는 순간 그 트리의
  -- ctags 전체 빌드가 시작된다 - 남의 트리에서 파일 하나 열었을 뿐인데
  -- 그러면 안 된다.
  if _G.projectfiles_should_index_file
      and not _G.projectfiles_should_index_file(path) then
    return 0
  end
  local ok, root = pcall(vim.fn['gutentags#get_project_root'], path)
  if not ok or type(root) ~= 'string' or root == '' then
    return 1
  end
  if s.gt[root] then
    return s.gt[root] == 'no' and 0 or 1
  end
  local max = tonumber(cfg('ctags_max_bytes', 32 * 1024 * 1024)) or 0
  if max > 0 then
    local ok2, cache = pcall(vim.fn['gutentags#get_cachefile'], root, 'tags')
    local st = ok2 and type(cache) == 'string' and uv.fs_stat(cache) or nil
    if st and st.size > max then
      s.gt[root] = 'no'
      exclude_gutentags(root, ('tags %.0fMB'):format(st.size / 1048576))
      return 0
    end
  end
  -- 아직 크지 않다: gutentags 에 맡기고, 파일 수 가드는 그대로 돈다
  s.gt[root] = 'yes'
  return 1
end

local guard_ctags_decide  -- 아래에서 정의; 파일 수를 다 센 뒤에 불린다

local function guard_ctags(path)
  local max = cfg('ctags_max_files', 5000)
  if max <= 0 then
    return
  end
  local root = marker_root(path)
  if not root or counted[root] then
    return
  end
  counted[root] = true
  count_files(root, function(n) guard_ctags_decide(root, max, n) end)
end

guard_ctags_decide = function(root, max, n)
  if n ~= nil and n <= max then
    return
  end
  exclude_gutentags(root, n and (n .. ' files') or 'big tree')
end

-- ---------------------------------------------------------------------------
-- ctags for the trees gutentags refuses
-- ---------------------------------------------------------------------------
-- guard_ctags() keeps huge projects away from gutentags because gutentags
-- rebuilds the WHOLE tags file whenever a file in it is saved (its
-- update_tags.sh greps the old entries out and appends the new ones), which
-- on a kernel-sized index means rewriting ~0.9 GB per ':w'. Those projects
-- still deserve a tags file, so build it here: once, in the background, and
-- never on save - C-] stays correct through 'tagfunc'/GTAGS anyway.

local function ctags_cmd()
  for _, c in ipairs({ vim.g.gutentags_ctags_executable, vim.g.tagbar_ctags_bin,
    vim.fn.expand('~/.local/bin/ctags'), 'uctags', 'ctags' }) do
    if c and c ~= '' and vim.fn.executable(c) == 1 then
      return c
    end
  end
  return nil
end

-- the same path gutentags would use, so there is only ever one tags file per
-- project (gutentags#get_cachefile: '/' ':' -> '-', ' ' -> '_')
local function ctags_file(root)
  local dir = vim.g.gutentags_cache_dir
  if dir and dir ~= '' then
    local name = (root .. '/tags'):gsub('[\\/:]', '-'):gsub(' ', '_')
    name = (name:gsub('^%-+', ''))
    return vim.fn.expand(dir) .. '/' .. name
  end
  return dbpath(root) .. '/tags'
end

-- sihlindex.lua 가 이 스냅숏을 직접 이분 탐색할 수 있게 경로를 내준다.
-- 스냅숏이 커서 &tags 에서 빠진 프로젝트(여기서는 1747MB)에서는 vim 의
-- taglist() 가 아예 답하지 못하므로, 색이 'C-] 로 갈 수 있다'와 어긋난다.
function _G.autoindex_ctags_file(root)
  local ok, p = pcall(ctags_file, root)
  return ok and p or nil
end

-- true when the snapshot is older than g:autoindex_ctags_max_age days
function ctags_stale(root)
  local days = cfg('ctags_max_age', 7)
  if days <= 0 then
    return false
  end
  local st = uv.fs_stat(ctags_file(root))
  return st ~= nil and (os.time() - st.mtime.sec) > days * 86400
end

-- put the project's tags file in front of &tags for this buffer
function ctags_apply(root, buf)
  local file = ctags_file(root)
  local st = uv.fs_stat(file)
  if not st then
    return false
  end
  -- 거대한 스냅숏은 디스크에 두되 'tags' 에는 넣지 않는다.
  --
  -- 'ignorecase' + 'smartcase' 에서 모든 매치를 찾아야 하는 태그 조회는
  -- vim 이 이진 검색을 포기하고 tags 파일을 처음부터 끝까지 읽는다. 1.8GB
  -- 짜리가 'tags' 에 들어 있으면 완성 한 번, :tag 한 번이 그 파일을 통째로
  -- 훑는다. C-] 는 tagfunc(GTAGS)이 먼저 답하므로 이걸 빼도 점프는 그대로다.
  --   let g:autoindex_tags_max_bytes = 0   " 크기와 무관하게 넣기
  local cap = tonumber(cfg('tags_max_bytes', 256 * 1024 * 1024)) or 0
  if cap > 0 and st.size > cap then
    if not s.warned['tags:' .. root] then
      s.warned['tags:' .. root] = true
      notify(('%s: ctags 스냅숏이 %.0fMB 라 \'tags\' 에 넣지 않았습니다'):format(
          vim.fn.fnamemodify(root, ':~'), st.size / 1048576)
        .. ' - C-] 는 GTAGS 가 답합니다 (g:autoindex_tags_max_bytes)')
    end
    return true -- 파일은 있다: 다시 만들라고 하지는 않는다
  end
  buf = buf or api.nvim_get_current_buf()
  if not api.nvim_buf_is_valid(buf) then
    return false
  end
  local cur = vim.bo[buf].tags ~= '' and vim.bo[buf].tags or vim.o.tags
  if cur:find(vim.pesc(file), 1, false) then
    return true
  end
  api.nvim_buf_call(buf, function()
    vim.opt_local.tags:prepend(file)
  end)
  return true
end

function ctags_build(root, why)
  if cfg('ctags', 1) == 0 or s.ctags_building[root] then
    return
  end
  local ct, fl = ctags_cmd(), filelist_cmd()
  if not ct or not fl then
    return
  end
  local short = vim.fn.fnamemodify(root, ':~')
  -- gtags 색인과는 별도의 자원이므로 락도 따로 잡는다
  if not take_lock(root, 'ctags') then
    dbg('ctags 빌드 건너뜀 (다른 nvim 이 만드는 중) ' .. root)
    return
  end
  s.ctags_building[root] = true
  local file = ctags_file(root)
  vim.fn.mkdir(vim.fs.dirname(file), 'p')
  notify('ctags 색인 생성 중(백그라운드): ' .. short ..
    (why and (' - ' .. why) or ''))
  local t0 = uv.now()
  local tmp = file .. '.building'
  local listf = tmp .. '.files'

  local function fail(msg)
    s.ctags_building[root] = nil
    release_lock(root, 'ctags')
    pcall(vim.fn.delete, tmp)
    pcall(os.remove, listf)
    if msg then
      notify(msg, vim.log.levels.WARN)
    end
  end

  -- '--excmd=number' drops the search pattern from every entry (~30% smaller,
  -- 0.88 GB instead of 1.3 GB on a 69k-file kernel tree); '--tag-relative=never'
  -- with an absolute file list keeps the paths valid from a cache directory.
  local function run_ctags()
    local args = { ct, '-f', tmp, '-L', listf }
    for a in tostring(cfg('ctags_args', '--fields=+n --excmd=number')):gmatch('%S+') do
      args[#args + 1] = a
    end
    args[#args + 1] = '--tag-relative=never'
    local ok = spawn(args, { text = true, cwd = root }, function(o)
      vim.schedule(function()
        pcall(os.remove, listf)
        if o.code ~= 0 then
          fail(short .. ' ctags 색인 실패: ' ..
            ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))))
          return
        end
        if not uv.fs_rename(tmp, file) then
          fail(short .. ' ctags: tags 파일을 옮기지 못했습니다 -> ' .. file)
          return
        end
        s.ctags_building[root] = nil
        release_lock(root, 'ctags')
        local st = uv.fs_stat(file)
        notify(string.format('%s ctags 색인 완료 (%.0f MB, %.0fs)', short,
          (st and st.size or 0) / 1048576, (uv.now() - t0) / 1000))
        -- every buffer of this project can use it right away
        for _, b in ipairs(api.nvim_list_bufs()) do
          local n = api.nvim_buf_get_name(b)
          if n ~= '' and n:sub(1, #root + 1) == root .. '/' then
            ctags_apply(root, b)
          end
        end
      end)
    end)
    if not ok then
      fail(nil)
    end
  end

  -- a preset decides which files exist for the indexer: write it out before
  -- the list is generated, or the very first build indexes the whole tree
  pcall(function()
    if _G.projectfiles_materialize then
      _G.projectfiles_materialize(root)
    end
  end)
  -- 예전에는 fl | sed | ctags -L - && mv 를 sh -c 한 줄로 묶었다. nvim 이
  -- 죽으면 sh 만 죽고 ctags 는 손자로 살아남는다. 이제 세 단계로 나눈다:
  -- 목록 생성(셸 없이) -> Lua 가 경로를 절대경로로 정리 -> ctags(셸 없이).
  local ok = spawn({ fl }, { text = true, cwd = root,
      timeout = (tonumber(cfg('filelist_timeout_sec', 300)) or 300) * 1000 },
    function(o)
      vim.schedule(function()
        if o.code ~= 0 then
          fail(short .. ' ctags: 파일 목록을 만들지 못했습니다')
          return
        end
        -- sed -e 's|^\./||' -e 's|^|<root>/|' 가 하던 일
        local out, n = {}, 0
        for line in (o.stdout or ''):gmatch('[^\n]+') do
          if line:sub(1, 2) == './' then
            line = line:sub(3)
          end
          if line:sub(1, 1) ~= '/' then
            line = root .. '/' .. line
          end
          n = n + 1
          out[n] = line
        end
        if n == 0 then
          fail(short .. ' ctags: 색인할 파일이 없습니다')
          return
        end
        local f = io.open(listf, 'w')
        if not f then
          fail(short .. ' ctags: 파일 목록을 쓰지 못했습니다')
          return
        end
        f:write(table.concat(out, '\n'), '\n')
        f:close()
        run_ctags()
      end)
    end)
  if not ok then
    fail(nil)
  end
end


-- ---------------------------------------------------------------------------
-- 'tagfunc': C-], :tag, g], C-w ] answered from GTAGS
-- ---------------------------------------------------------------------------
-- The tags file is a snapshot; GTAGS is updated on every save, so a jump to
-- something written a second ago works. Returning v:null leaves the normal
-- tags-file lookup untouched, which is what happens outside indexed projects.
function _G.autoindex_tagfunc(pattern, flags, info)
  if cfg('tagfunc', 1) == 0 or not enabled() then
    return vim.NIL
  end
  -- only plain identifiers; regex/prefix lookups stay with the tags file
  if type(pattern) ~= 'string' or not pattern:match('^[%w_]+$') then
    return vim.NIL
  end
  if type(flags) == 'string' and flags:find('i') then
    return vim.NIL -- insert-mode completion
  end
  local prog = global_cmd()
  if not prog then
    return vim.NIL
  end
  local name = api.nvim_buf_get_name(0)
  local dir = name ~= '' and vim.bo.buftype == ''
      and vim.fs.dirname(vim.fn.fnamemodify(name, ':p')) or vim.fn.getcwd()
  local root = s.roots[dir] or scan_root(dir)
  if not root then
    return vim.NIL
  end
  local ok, o = pcall(function()
    return vim.system({ prog, '-d', '--result=ctags-mod', pattern },
      { text = true, cwd = root, env = env_for(root) }):wait(3000)
  end)
  if not ok or not o or o.code ~= 0 or not o.stdout or o.stdout == '' then
    return vim.NIL
  end
  local items = {}
  for line in o.stdout:gmatch('[^\n]+') do
    local path, lno, text = line:match('^([^\t]+)\t(%d+)\t(.*)$')
    if path then
      items[#items + 1] = {
        name = pattern,
        filename = path:sub(1, 1) == '/' and path or (root .. '/' .. path),
        cmd = tostring(lno),
        kind = 'd',
        user_data = (text or ''):gsub('^%s+', ''),
      }
    end
  end
  if #items == 0 then
    return vim.NIL
  end
  return items
end

-- ---------------------------------------------------------------------------
-- autocmds and commands
-- ---------------------------------------------------------------------------
local group = api.nvim_create_augroup('AutoIndexGtags', { clear = true })

-- GTAGS answers C-] / :tag / g] (an LSP client still overrides this per
-- buffer, which is what you want where clangd is running)
if cfg('tagfunc', 1) ~= 0 and vim.o.tagfunc == '' then
  vim.o.tagfunc = 'v:lua.autoindex_tagfunc'
end

api.nvim_create_autocmd('BufReadPre', {
  group = group,
  callback = function(a)
    if not enabled() or vim.bo[a.buf].buftype ~= '' then
      return
    end
    local path = a.match ~= '' and vim.fn.fnamemodify(a.match, ':p') or nil
    if path and indexed_file(path) then
      guard_ctags(path)
    end
  end,
})

api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function(a)
    dbg('BufWritePost match=' .. tostring(a.match) .. ' buf=' .. tostring(a.buf))
    local path = a.match ~= '' and vim.fn.fnamemodify(a.match, ':p') or nil
    if path and vim.bo[a.buf].buftype == '' then
      update_file(path)
    end
  end,
})

-- opening a source file in a project without an index starts one build
api.nvim_create_autocmd('BufReadPost', {
  group = group,
  callback = function(a)
    if not (enabled() and cfg('auto_create', 1) ~= 0) then
      return
    end
    if vim.bo[a.buf].buftype ~= '' then
      return
    end
    local path = a.match ~= '' and vim.fn.fnamemodify(a.match, ':p') or nil
    if not (path and indexed_file(path)) then
      return
    end
    gtags_root(vim.fs.dirname(path), function(root)
      if root then
        if cfg('ctags', 1) ~= 0 then
          ctags_apply(root, a.buf)
        end
        return -- already indexed
      end
      local mroot = marker_root(path)
      if mroot and not s.tried[mroot] then
        s.tried[mroot] = true
        with_mode(mroot, function() build(mroot, 'no GTAGS yet') end)
      end
    end)
  end,
})

-- ask gutentags for a fresh ctags index of the project of the current buffer
local function ctags_startup()
  if cfg('startup_ctags', 1) == 0 or vim.fn.exists(':GutentagsUpdate') ~= 2 then
    return
  end
  local p = api.nvim_buf_get_name(0)
  if p == '' or vim.bo.buftype ~= '' then
    return
  end
  if not indexed_file(vim.fn.fnamemodify(p, ':p')) then
    return
  end
  -- b:gutentags_files is set only for buffers gutentags actually manages, so
  -- this also honours guard_ctags()'s "too big for ctags" exclusion - without
  -- it a kernel-sized tags file would be rebuilt at every start
  if vim.b.gutentags_files == nil then
    return
  end
  -- when there is no tags file yet, gutentags' own generate_on_missing is
  -- already building one; only refresh an existing (possibly stale) index
  if #vim.fn.tagfiles() == 0 then
    return
  end
  -- ! means "the whole project"; gutentags runs it in the background and
  -- skips roots that guard_ctags() put on g:gutentags_exclude_project_root
  pcall(vim.cmd, 'silent! GutentagsUpdate!')
end

-- starting nvim refreshes (or creates) the index of the project in front of us
local function startup()
  dbg('startup begin')
  if not (enabled() and cfg('startup', 1) ~= 0) then
    return
  end
  local dirs, p = {}, api.nvim_buf_get_name(0)
  if p ~= '' and vim.bo.buftype == '' then
    dirs[#dirs + 1] = vim.fs.dirname(vim.fn.fnamemodify(p, ':p'))
  end
  dirs[#dirs + 1] = vim.fn.getcwd()
  local home = vim.fn.expand('~')
  local seen = {}
  for _, dir in ipairs(dirs) do
    gtags_root(dir, function(root)
      if root then
        if not seen[root] then
          seen[root] = true
          with_mode(root, function() refresh(root, 'startup') end)
        end
        return
      end
      if cfg('auto_create', 1) == 0 then
        return
      end
      -- no index yet: build one, but never for $HOME or / by accident
      local m = marker_root(dir)
      if m and m ~= home and m ~= '/' and not seen[m] and not s.tried[m] then
        seen[m] = true
        s.tried[m] = true
        with_mode(m, function() build(m, 'startup') end)
      end
    end)
  end
  ctags_startup()
end

api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    dbg('VimEnter')
    -- after the session has settled (plugins, session files, RelationView)
    vim.defer_fn(startup, 300)
  end,
})

api.nvim_create_user_command('GtagsIndex', function()
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    build(root or marker_root(dir) or dir, 'manual', { confirm = true })
  end)
end, { desc = 'Rebuild the GTAGS index of this project in the background' })

-- 지금 통째로 다시 만든다 (자리 되찾기).
--
-- 증분 갱신은 빠진 자리를 회수하지 않아서 DB 가 계속 부푼다. 평소에는
-- refresh() 가 알아서 때를 보지만(g:autoindex_compact_every / _bytes),
-- 눈에 띄게 느려졌을 때 직접 부를 수 있게 둔다. :GtagsIndex 와 달리
-- 파일 수가 줄었는지 묻지 않는다 - 목록은 그대로 두고 DB 만 다시 만드는
-- 것이 이 명령의 뜻이라서다.
api.nvim_create_user_command('GtagsCompact', function()
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    root = root or marker_root(dir) or dir
    pcall(vim.fn.delete, dbpath(root) .. '/compact')
    build(root, '자리 되찾기 (수동)', {})
  end)
end, { desc = 'Rebuild this project index from scratch to reclaim space' })

api.nvim_create_user_command('GtagsIndexUpdate', function()
  local path = api.nvim_buf_get_name(0)
  if path == '' then
    return
  end
  update_file(vim.fn.fnamemodify(path, ':p'))
end, { desc = 'Update the GTAGS index for the current file' })

-- 루트를 이미 아는 호출자를 위한 진입점.
--
-- :GtagsIndexRefresh 는 현재 버퍼의 이름에서(없으면 cwd 에서) 프로젝트를
-- 다시 찾는다. NERDTree 창이나 telescope 프롬프트에서 부르면 그 버퍼에는
-- 이름이 없어서 cwd 로 떨어지고, cwd 가 다른 프로젝트면 엉뚱한 색인을
-- 갱신하거나 '색인이 없습니다' 로 끝난다. projectfiles 는 어느 프로젝트의
-- 목록을 고쳤는지 정확히 알고 있으므로, 그 루트를 그대로 받는다.
function _G.autoindex_refresh(root, force, why)
  if not (root and root ~= '') then
    return false
  end
  if not enabled() then
    return false
  end
  refresh(root, why or 'list changed', force ~= false)
  return true
end

api.nvim_create_user_command('GtagsIndexRefresh', function(o)
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    if root then
      refresh(root, o.bang and 'manual!' or 'manual', o.bang)
    else
      notify('이 프로젝트에는 색인이 없습니다 (:GtagsIndex)', vim.log.levels.WARN)
    end
  end)
end, { bang = true,
  desc = 'Incrementally refresh the GTAGS index (! skips the shrink guard)' })

api.nvim_create_user_command('CtagsIndex', function()
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    root = root or marker_root(dir) or dir
    s.ctags_tried[root] = true
    ctags_build(root, 'manual')
  end)
end, { desc = 'Rebuild this project\'s ctags file in the background' })

api.nvim_create_user_command('GtagsIndexStatus', function()
  local lines = {}
  for root in pairs(s.building) do
    lines[#lines + 1] = 'building ' .. root
  end
  for root in pairs(s.updating) do
    lines[#lines + 1] = 'updating ' .. root
  end
  for root in pairs(s.ctags_building) do
    lines[#lines + 1] = 'building ctags ' .. root
  end
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    lines[#lines + 1] = 'database: ' ..
        (root and dbpath(root) or '(none - :GtagsIndex)')
    lines[#lines + 1] = 'GTAGSOBJDIR: ' .. (vim.env.GTAGSOBJDIR or '(unset)')
    lines[#lines + 1] = 'file list: ' .. (filelist_cmd() or '(indexfiles.sh missing)')
    if root then
      local cf = ctags_file(root)
      local st = uv.fs_stat(cf)
      lines[#lines + 1] = 'ctags: ' .. cf ..
          (st and string.format(' (%.0f MB)', st.size / 1048576) or ' (없음)')
    end
    lines[#lines + 1] = 'tagfunc: ' .. (vim.o.tagfunc ~= '' and vim.o.tagfunc or '(unset)')
    vim.notify(table.concat(lines, '\n'))
  end)
end, { desc = 'Show what the GTAGS auto-indexer is doing' })
