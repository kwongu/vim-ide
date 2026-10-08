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
-- A preset's '.tags/files' (projectfiles.lua) comes before all of them; that
-- list is read here directly - it is already filtered - and a list change
-- reaches GTAGS without the script (see preset_snapshot / refresh).
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

-- expand() 의 둘째 인자 1: 'wildignore' 를 보지 않는다. .vimrc 가 */tmp/* 를
-- 넣어 두어서, 경로가 /tmp 아래면(HOME 이든 캐시 디렉터리든) expand() 가 ''
-- 를 돌려주고 그 도구는 '없는' 것이 됐다.
local function global_cmd()
  if vim.fn.executable('global') == 1 then
    return 'global'
  end
  local p = vim.fn.expand('~/.local/bin/global', 1)
  return vim.fn.executable(p) == 1 and p or nil
end

local function gtags_cmd()
  if vim.fn.executable('gtags') == 1 then
    return 'gtags'
  end
  local p = vim.fn.expand('~/.local/bin/gtags', 1)
  return vim.fn.executable(p) == 1 and p or nil
end

local function filelist_cmd()
  local p = vim.fn.expand('~/.local/bin/indexfiles.sh', 1)
  return vim.fn.executable(p) == 1 and p or nil
end

local drain        -- defined below; a finished build flushes the queue
local refresh      -- defined below; re-entered through the pending queue
local build        -- defined below; a queued rebuild runs from next_job
local next_job     -- defined below; what runs once this DB is free again
local wait_lock    -- defined below; retries while another nvim holds the lock
local ctags_build  -- defined below, used by guard_ctags
local ctags_apply
local ctags_stale
local ctags_follow -- defined below; ctags follows a list change

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
                       --         (merged: see merge_req)
  build_again = {},    -- root -> { why, opts } a build asked for while busy
  locked = {},         -- root -> true while THIS nvim holds the index lock
  gt = {},             -- gutentags 루트 -> 'no'/'yes' (붙일지 이미 판단했다)
  lock_wait = {},      -- root -> 다른 nvim 의 락이 풀리기를 기다린 횟수
  fast = {},           -- root -> + 한 파일을 single-update 하는 중 ({ waited = tagfunc
                       --         가 한 번 기다려 봤다 })
  refresh_fail = {},   -- root -> 실패한 강제 갱신을 다시 해 본 횟수
  fl = {},             -- root -> indexfiles.sh 결과를 잠깐 나눠 쓰기 (filelist)
  ct_pending = {},     -- ctags 파일 -> gutentags 가 끝나면 한 번 더 (ctags_follow)
  ct_setup = {},       -- root -> 모드를 고르기 전에 연 버퍼에 gutentags 를 붙여 봤다
  torn = {},           -- root -> 목록이 읽는 동안 바뀌어 다시 읽어 본 횟수 (refresh)
  gt_wait = {},        -- root -> 목록이 없거나 빈 목록이라 gutentags 를 붙이지 않았다
  ct_due = {},         -- root -> 이 nvim 이 낸 목록 변경을 ctags 가 아직 따라가지 않았다
  list_at = {},        -- root -> 이 nvim 이 목록을 바꾼 마지막 시각 (ctags_follow 의 since)
  wait_marker = {},    -- root -> 강제가 아닌 갱신이 남은 표지를 보고 기다린다 (wait_lock)
  count_mode = {},     -- root -> 파일 수를 세어 정한 것 { mode = 그때의 모드, big = 큰
                       --         트리로 정했다, put = 그래서 제외 목록에 넣은 것이 이 세기다 }
  switched = {},       -- root -> preset 을 바꿔 다시 센다 (guard_ctags_decide 가 뒤집는다)
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

-- 폭을 넘는 한 줄 알림은 Press ENTER 가 뜨며 다음 키를 먹는다 (fitmsg.lua)
--
-- 첫 화면이 뜨기 전(시작 중)의 알림은 모아 두었다가 화면이 뜬 뒤에 낸다 (F6).
-- 시작 중에 두 줄이 쌓이면 Press ENTER 가 뜨고, 떠 있는 동안 nvim 은 예약된
-- 콜백을 하나도 돌리지 않는다 - 색인이 없는 프로젝트를 처음 열 때 'indexing …'
-- 과 'tags NMB - ctags 는 여기서 직접 만듭니다'(gutentags 가 붙기 전에 묻는
-- 자리)가 같이 나서, 0.1초면 끝난 gtags 빌드가 DB 를 옮기고 락을 푸는 마무리가
-- 키를 누를 때까지(실측 150초) 멈췄다. 낼 때는 사이사이 redraw 해서 한 줄씩
-- 덮어 쓴다 (모두 :messages 에 남는다). 경고는 뒤로 보내 화면에 남게 한다.
local early -- 시작 중에 모은 알림 (nil: 바로 낸다)

local function notify(msg, level)
  if cfg('notify', 1) == 0 then
    return
  end
  level = level or vim.log.levels.INFO
  if vim.v.vim_did_enter == 1 and not early then
    (_G.vimide_notify or vim.notify)('autoindex: ' .. msg, level)
    return
  end
  if not early then
    early = {}
    local function flush()
      local q = early or {}
      early = nil
      table.sort(q, function(a, b)
        return a.level < b.level or (a.level == b.level and a.i < b.i)
      end)
      for i, m in ipairs(q) do
        if i > 1 then
          pcall(vim.cmd, 'redraw')
        end
        (_G.vimide_notify or vim.notify)('autoindex: ' .. m.msg, m.level)
      end
    end
    if vim.v.vim_did_enter == 1 then
      vim.schedule(flush)
    else
      api.nvim_create_autocmd('VimEnter', { once = true,
        callback = function() vim.schedule(flush) end })
    end
  end
  early[#early + 1] = { msg = msg, level = level, i = #early + 1 }
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

-- 락을 쥔 nvim 이 띄운 일꾼: '<db>/.autoindex.worker' (F5)
--
-- 락은 nvim 의 pid 로만 살았는지 본다. 그런데 nvim 이 SIGKILL·OOM 으로 죽어도
-- 그 nvim 이 띄운 'gtags -i' 는 산다 (PPID 1 이 된다 - 맥에는 timeout(1) 이
-- 없고, 리눅스의 timeout(1) 도 부모가 죽어도 남는다). 다음 nvim 은 죽은 락을
-- 치우고 들어가 + 한 파일을 넣었는데, 뒤늦게 끝난 고아 gtags -i 가 (그 파일이
-- 없는 예전 목록으로) 그것을 도로 지웠다 - 표지도 이미 지운 뒤라 아무도 다시
-- 하지 않았다 (재현). 그래서 DB 를 그 자리에서 고치는 일꾼(gtags -i, 저장
-- 갱신)은 pid 를 여기 적고, 끝나면 지운다. 락의 주인이 죽었어도 적힌 일꾼이
-- 살아 있으면 락은 아직 쥔 것으로 본다 - 고아를 죽이지 않고(쓰다 만 GTAGS 가
-- 깨진다) 끝나기를 기다린다. 끝난 뒤에 들어가는 쪽은 그때의 목록을 읽는다.
-- 셋째 칸은 그 일꾼의 시간 제한이 끝나는 시각이다: 그 뒤로는 pid 가 다른
-- 프로세스에 다시 쓰였을 수 있으니 기다리지 않는다.
local function worker_path(root)
  return dbpath(root) .. '/.autoindex.worker'
end

local function worker_note(root, h, timeout_ms)
  if not (h and h.pid) then
    return
  end
  local f = io.open(worker_path(root), 'w')
  if f then
    f:write(('%d\t%s\t%d\n'):format(h.pid, uv.os_gethostname(),
      os.time() + math.floor((timeout_ms or 30 * 60 * 1000) / 1000) + 60))
    f:close()
  end
end

local function worker_clear(root)
  pcall(os.remove, worker_path(root))
end

-- 그 pid 가 아직 우리 일꾼(또는 그 앞의 timeout/nice, 감싼 셸)인가. /proc 가
-- 있으면(리눅스) 이름을 본다 - 일꾼이 끝난 뒤 그 pid 를 다른 프로세스가 받았으면
-- 시간 제한까지 헛되이 기다린다. 없으면(맥) pid 만 믿는다.
local WORKER_COMM = {}
for c in ('gtags global timeout gtimeout nice ionice sh bash dash'):gmatch('%S+') do
  WORKER_COMM[c] = true
end

local function worker_comm_ok(pid)
  local f = io.open('/proc/' .. pid .. '/comm', 'r')
  if not f then
    return true
  end
  local c = (f:read('*l') or ''):gsub('%s+$', '')
  f:close()
  return WORKER_COMM[c] == true
end

-- 이 DB 를 아직 고치고 있는 남의 일꾼 (없으면 nil)
local function worker_alive(root)
  local f = io.open(worker_path(root), 'r')
  if not f then
    return nil
  end
  local line = f:read('*l') or ''
  f:close()
  local pid, host, till = line:match('^(%d+)\t([^\t]*)\t(%d+)$')
  if not pid or os.time() > tonumber(till) then
    return nil
  end
  pid = tonumber(pid)
  if host == uv.os_gethostname() then
    if not pid_alive(pid) or not worker_comm_ok(pid) then
      return nil
    end
    for h in pairs(jobs) do
      if h.pid == pid then
        return nil -- 내 일꾼이다
      end
    end
  end
  return { pid = pid, host = host }
end

local function write_lock(root, name)
  local body = ('%d\t%s\t%d\n'):format(uv.os_getpid(), uv.os_gethostname(),
    os.time())
  -- O_EXCL 로 만든다: 두 nvim 이 동시에 들어와도 하나만 성공한다.
  -- 실패하면 까닭(EEXIST/EACCES/EROFS …)도 넘긴다 (take_lock)
  local fd, _, ename = uv.fs_open(lock_path(root, name), 'wx', 420)
  if not fd then
    return false, ename
  end
  pcall(uv.fs_write, fd, body)
  pcall(uv.fs_close, fd)
  return true
end

-- 이 트리의 색인 권한을 잡는다. false 면 다른 nvim 이 이미 돌리고 있다.
--
-- false, 'unwritable' 은 다르다: 락 파일을 만들 수조차 없다 (남의 트리의 .tags,
-- 읽기 전용 마운트). 기다려도 풀릴 락이 없다 - 예전에는 '다른 nvim 이 쥐었다' 와
-- 같이 다뤄, 시작 갱신이 wait_lock 에서 1초마다 다시 돌며 세션 내내
-- 'waiting for another nvim' 으로 남았다 (D4, 재현). 부르는 쪽은 그만둔다.
local function take_lock(root, name)
  local key = (name or '') .. '\0' .. root
  if s.locked[key] then
    return true
  end
  pcall(vim.fn.mkdir, dbpath(root), 'p')
  local wrote, ename = write_lock(root, name)
  if not wrote then
    if ename ~= 'EEXIST' then
      dbg(('lock: 락 파일을 만들 수 없음 (%s) %s'):format(tostring(ename), root))
      return false, 'unwritable'
    end
    local cur = read_lock(root, name)
    if lock_held(cur) then
      dbg(('lock busy %s%s (pid %s @ %s)'):format(root,
        name and (' [' .. name .. ']') or '', tostring(cur.pid),
        tostring(cur.host)))
      return false
    end
    -- 주인이 죽은 락이다. 그 nvim 의 일꾼이 아직 DB 를 고치고 있으면 끝날
    -- 때까지 들어가지 않는다 (F5, worker_path 의 설명)
    if not name and worker_alive(root) then
      dbg('lock: 주인은 죽었고 일꾼이 아직 돈다 ' .. root)
      return false
    end
    -- 치우고 한 번만 다시 시도한다.
    pcall(os.remove, lock_path(root, name))
    local wrote2, ename2 = write_lock(root, name)
    if not wrote2 then
      -- 죽은 락을 치우지 못했다 (그 디렉터리에 쓸 수 없다): 역시 기다릴 것이 없다.
      -- EEXIST 이고 쓸 수 있으면 그 사이 다른 nvim 이 잡은 것이다
      if ename2 ~= 'EEXIST'
          or not uv.fs_access(vim.fs.dirname(lock_path(root, name)), 'W') then
        dbg(('lock: 죽은 락을 치울 수 없음 (%s) %s'):format(tostring(ename2), root))
        return false, 'unwritable'
      end
      return false
    end
  elseif not name and worker_alive(root) then
    -- 누군가 죽은 락을 이미 치웠지만 그 일꾼은 아직 돈다: 같은 이유로 물러선다
    pcall(os.remove, lock_path(root, name))
    dbg('lock: 남의 일꾼이 아직 돈다 ' .. root)
    return false
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
      if not l.name then
        worker_clear(l.root) -- 위에서 일꾼을 끝냈다
      end
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
--
-- '.repo' 는 repo 로 받은 SDK 의 루트다. SDK 루트에는 .git 이 없고(.git 은
-- kernel/common 같은 하위 프로젝트마다 있다) .repo 만 있어서, 예전에는 처음
-- 여는 SDK 에서 이 검색이 SDK 를 지나쳐 위로 올라갔다. 그 위에 SDK 여러 개를
-- 담아 둔 디렉터리가 있고 거기 빈 .git 이 하나 있으면(실제로 있었다:
-- ~/work1/tsnd/dev/tsnd_2.0, 커밋 0개) 그 디렉터리 전체 - 파일 496만 개 -
-- 가 '새 프로젝트'가 되어 첫 실행마다 목록 만들기(캐시가 식었을 때 find
-- 35초)와 ctags/gtags 전체 빌드를 시작했다. 가까운 표시가 이기므로 하위
-- 프로젝트(.git) 안에서는 예전과 같다. 이미 색인이 있는 SDK 는 GTAGS 가
-- 먼저 잡혀 여기까지 오지 않는다.
-- projectfiles.lua 의 root_from_dir/marked_root, .vimrc 의
-- g:gutentags_project_root 와 s:VimIdeSessRoot 가 같은 목록을 쓴다.
local function marker_root(path)
  local found = vim.fs.find({ '.git', '.repo', '.project', '.root' },
    { path = path, upward = true, type = 'directory' })[1]
      or vim.fs.find({ '.git', '.repo', '.project', '.root', '.indexfiles',
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
-- 색인이 따라가는 목록
-- ---------------------------------------------------------------------------
-- '<root>/.tags/files' 는 projectfiles.lua 가 preset 에서 펼쳐 쓴 목록이다.
local function list_file(root)
  return root .. '/' .. (dbdir_name() or '.tags') .. '/files'
end

-- 파일 상태를 견줄 열쇠. 초까지만 보면 같은 초 안에 두 번 쓴 것을 못
-- 알아본다 - '+ x' 다음 '- x' 가 100ms 안에 오면 in_list 가 지운 파일을
-- 계속 '목록에 있다'고 답했고, 그 파일을 저장하면 색인에 도로 들어갔다
-- (재현). 나노초·크기·inode 를 다 본다. stat 은 어차피 한 번이다.
local function stat_key(st)
  return ('%d.%d:%d:%d'):format(st.mtime.sec, st.mtime.nsec or 0, st.size,
    st.ino or 0)
end

-- 이 루트가 preset 모드인가. projectfiles 가 없으면 모른다(nil) - 그때는
-- 예전처럼 indexfiles.sh 가 정한다.
local function preset_mode(root)
  if type(_G.projectfiles_mode) ~= 'function' then
    return nil
  end
  local ok, m = pcall(_G.projectfiles_mode, root)
  if not ok or type(m) ~= 'string' then
    return nil
  end
  return m ~= 'auto' and m ~= 'none' and m ~= 'unset' and m ~= ''
end

-- 지금 모드의 이름 (preset 이름 / auto / none / unset). 모르면 nil.
local function mode_now(root)
  if type(_G.projectfiles_mode) ~= 'function' then
    return nil
  end
  local ok, m = pcall(_G.projectfiles_mode, root)
  return ok and type(m) == 'string' and m or nil
end

-- preset 을 목록 파일로 펼쳐 둔다 (projectfiles.lua). 바뀐 것이 없으면 그쪽이
-- 곧바로 돌아온다(계약 C1) - 시작할 때 여러 곳이 불러도 실제로 펼치는 것은
-- 한 번이다. 목록이 바뀌었으면 true.
local function materialize(root)
  if type(_G.projectfiles_materialize) ~= 'function' then
    return nil
  end
  local ok, changed = pcall(_G.projectfiles_materialize, root)
  return ok and changed or nil
end

-- 빈 preset 목록이 정말 '아무것도 색인하지 않기' 인가 (계약 K3). 저장된 preset
-- 이 항목 0개일 때만 그렇다고 projectfiles 가 답한다. 물을 곳이 없으면 아니다
-- (= 손대지 않는다): 저장한 적 없는 이름의 목록도 비어 있다.
local function intended_empty(root)
  if type(_G.projectfiles_list_intended_empty) ~= 'function' then
    return false
  end
  local ok, yes = pcall(_G.projectfiles_list_intended_empty, root)
  return ok and yes == true
end

-- 지금 목록으로 ctags 를 다시 만들어도 되는가. gutentags 는 indexfiles.sh 로
-- 목록을 받는데, 목록 파일이 없으면 그 스크립트가 git ls-files 로 떨어져 트리
-- 전체를 ctags 한다.
--   * 색인하지 않는 모드(none/미설정): 아니다. 미뤄 둔 따라가기(GutentagsUpdated
--     를 기다리던 것)가 마지막 항목을 빼 none 이 된 뒤에 돌아, none 인
--     프로젝트에 트리 전체(3,555개)의 ctags 를 만들었다 (F4)
--   * preset 인데 목록이 없다: 같은 까닭으로 아니다
--   * preset 인데 목록이 비었다: 일부러 비운 preset 일 때만 (K3 - 오타 한 번에
--     ctags 가 머리말 24줄이 됐다)
local function list_ready(root)
  if type(_G.projectfiles_should_index) == 'function'
      and not _G.projectfiles_should_index(root) then
    return false
  end
  if preset_mode(root) then
    local st = uv.fs_stat(list_file(root))
    if not st or (st.size == 0 and not intended_empty(root)) then
      return false
    end
  end
  return true
end

-- 목록이 없거나 빈 목록이라 gutentags 를 붙이지 않은 프로젝트(s.gt_wait)에 이제
-- 쓸 만한 목록이 생겼으면 붙인다: 시작할 때 뒤에서 다시 편 목록(지난 세션의
-- 이름이 저장한 적 없는 것이었다), 다른 preset 으로 바꿈. 그 사이 연 버퍼에 붙여
-- tags 를 지금 목록으로 만든다 (붙는 순간 gutentags 가 새로 만든다). 이렇게
-- 바뀐 목록은 GTAGS 가 이미 맞으면(사본과 같다) 갱신이 따라가기를 부르지 않는다.
local function gt_retry(root)
  if s.gt_wait[root] and list_ready(root) then
    s.gt_wait[root] = nil
    s.ct_setup[root] = nil
    vim.schedule(function() ctags_follow(root) end)
  end
end

-- preset 목록을 통째로 읽는다 (gtags 에 넘길 스냅숏).
--
-- indexfiles.sh 를 거치지 않는다. 그 스크립트의 preset 갈래는 목록의 파일마다
-- stat 과 읽기(grep -I)를 다시 했는데, projectfiles 가 방금 같은 규칙으로 거른
-- 목록이다 - 6,600개에서 +/- 한 번마다 0.5~1초, stat 이 느린 서버에서는 그
-- 몇 배였고, 그동안 색인은 예전 목록 그대로였다.
--
-- 다른 nvim 이 같은 목록을 쓰는 중일 수 있다(예전 vim-ide 의 writefile 은
-- 비우고 쓴다 - 지금 projectfiles 는 옆에 쓰고 이름을 바꾼다). 읽기 전후의
-- 상태가 같고 읽은 길이가 크기와 같을 때만 믿는다. 잘린 목록을 넘기면
-- 'gtags -i' 가 빠진 파일을 색인에서 지운다.
--
-- 마지막 줄바꿈이 없는 목록도 완성본일 수 있다: 손으로 고쳤거나
-- printf '%s' "$(cat …)" 처럼 $(…) 가 끝 줄바꿈을 떼고 쓴 것. 예전에는 그것을
-- 늘 '쓰는 중' 으로 보아 300ms 마다 영영 다시 읽었고, 시작 갱신도 :GtagsIndex
-- 도 아무 말 없이 돌지 않았다 (INT4). 제자리에 쓰다 멈춘 반쪽과 가르는 것은
-- 나이다 - 방금(2초 안) 바뀐 것만 쓰는 중으로 보고, 그보다 오래된 것은
-- 완성본으로 받는다 (넘길 때는 끝 줄바꿈을 붙인다).
--
-- 돌려주는 것: { lines, set, text, key } / nil, 'missing' | 'torn'
local function preset_snapshot(root)
  local file = list_file(root)
  for _ = 1, 3 do
    local st = uv.fs_stat(file)
    local f = st and io.open(file, 'rb')
    if not f then
      return nil, 'missing'
    end
    local raw = f:read('*a') or ''
    f:close()
    local st2 = uv.fs_stat(file)
    local whole = raw == '' or raw:sub(-1) == '\n'
    if not whole and st2 then
      -- 초 단위로 잰다. 시계가 어긋나 미래의 시각이면(NFS) 나이를 잴 수 없다:
      -- 완성본으로 본다
      local age = os.time() - st2.mtime.sec
      whole = age >= 2 or age < 0
    end
    if st2 and #raw == st.size and stat_key(st2) == stat_key(st) and whole then
      local lines, set, same = {}, {}, raw:sub(-1) == '\n' or raw == ''
      for l in raw:gmatch('[^\n]+') do
        -- 줄마다 gsub 를 부르지 않는다 (커널 크기 목록이면 그것만 수십 ms)
        if l:sub(1, 2) == './' then
          l, same = l:sub(3), false
        end
        if l:find('%s$') then
          l, same = l:gsub('%s+$', ''), false
        end
        if l ~= '' and not set[l] then
          set[l] = true
          lines[#lines + 1] = l
        else
          same = false
        end
      end
      -- 고칠 것이 없었으면 읽은 그대로가 곧 넘길 목록이다 (빈 줄은 gmatch 가
      -- 조용히 건너뛰므로 따로 본다)
      if not same or raw:sub(1, 1) == '\n' or raw:find('\n\n', 1, true) then
        raw = #lines > 0 and (table.concat(lines, '\n') .. '\n') or ''
      end
      return { lines = lines, set = set, key = stat_key(st), text = raw }
    end
  end
  return nil, 'torn'
end

-- GTAGS 가 지금 담고 있는 목록의 사본: '<db>/files.indexed'
--
-- '+' 하나에 'gtags -i' 를 돌리면 목록의 파일을 전부 stat 한다 (6,600개, stat
-- 이 느린 서버에서 수 초 - 그동안 락도 쥐고 있다). DB 가 어느 목록을 담고
-- 있는지 알면, 파일 몇 개를 더한 것뿐일 때는 그것만 'global --single-update'
-- 로 넣으면 된다 (파일 하나에 수십 ms, 목록 크기와 무관). 그걸 알려고 색인에
-- 넘긴 목록을 그대로 남긴다.
--
-- 첫 줄은 그 순간의 GPATH 상태다. GPATH 는 파일이 들고 날 때만 바뀐다 - 저장
-- 갱신이나 내용만 바뀐 'gtags -i' 로는 그대로다(실측). 다르면 이 사본을 모르는
-- 누군가(예전 vim-ide 의 nvim, 손으로 돌린 gtags, projectfiles 의 즉시 갱신)가
-- DB 의 파일 구성을 바꾼 것이니 사본을 믿지 않고 'gtags -i' 로 맞춘다.
-- 목록 옆에 둔다 ('<root>/.tags/'). DB 를 루트에 두는 예전 배치
-- (g:autoindex_dbdir = '')에서도 소스 트리에 파일을 흘리지 않는다.
local function side_dir(root)
  return root .. '/' .. (dbdir_name() or '.tags')
end

local function copy_path(root)
  return side_dir(root) .. '/files.indexed'
end

local function gpath_key(root)
  local st = uv.fs_stat(dbpath(root) .. '/GPATH')
  return st and stat_key(st) or nil
end

-- 사본을 남긴다. text 가 nil 이면 지운다 (auto 모드처럼 따라갈 목록이 없을 때).
local function write_copy(root, text)
  local p = copy_path(root)
  local key = text and gpath_key(root)
  if not key then
    if uv.fs_stat(p) then
      pcall(os.remove, p)
    end
    return
  end
  local tmp = p .. '.tmp'
  local f = io.open(tmp, 'wb')
  if not f then
    return
  end
  f:write('#vimide-indexed ', key, '\n', text)
  f:close()
  if not uv.fs_rename(tmp, p) then
    pcall(os.remove, tmp)
  end
end

-- 사본의 줄 집합과 개수. DB 와 어긋났거나 없으면 nil.
local function read_copy(root)
  local f = io.open(copy_path(root), 'rb')
  if not f then
    return nil
  end
  local key = (f:read('*l') or ''):match('^#vimide%-indexed (%S+)$')
  if not key or key ~= gpath_key(root) then
    f:close()
    return nil
  end
  local set, n = {}, 0
  for l in (f:read('*a') or ''):gmatch('[^\n]+') do
    if not set[l] then
      set[l] = true
      n = n + 1
    end
  end
  f:close()
  return set, n
end

-- 저장 갱신('global --single-update') 하나가 DB 의 파일 구성을 바꿨을 때(목록에
-- 있지만 아직 DB 에 없던 파일이 들어왔다) 사본도 같이 고친다. 그러지 않으면
-- GPATH 가 바뀌어 사본을 믿지 못하게 되고, 다음 + 하나가 single-update 대신
-- 목록 전체로 gtags -i 를 돌렸다 (INT1 의 실측: 4초 동안 락). 갱신 전에 사본이
-- DB 와 맞았을 때(key0)만 한다 - 이미 어긋난 사본을 고쳐 믿게 만들면 안 된다.
local function copy_follow(root, rel, key0)
  local key1 = gpath_key(root)
  if not (key0 and key1) or key0 == key1 or rel:sub(1, 1) == '/' then
    return
  end
  local p = copy_path(root)
  local f = io.open(p, 'rb')
  if not f then
    return
  end
  local head = f:read('*l')
  local body = f:read('*a') or ''
  f:close()
  if head ~= '#vimide-indexed ' .. key0 then
    return
  end
  if body ~= '' and body:sub(-1) ~= '\n' then
    body = body .. '\n'
  end
  local at = ('\n' .. body):find('\n' .. rel .. '\n', 1, true)
  if uv.fs_stat(root .. '/' .. rel) then
    if not at then
      body = body .. rel .. '\n'
    end
  elseif at then
    -- 없는 파일의 single-update 는 그 파일을 DB 에서 뺀다
    body = body:sub(1, at - 1) .. body:sub(at + #rel + 1)
  end
  local tmp = p .. '.tmp'
  f = io.open(tmp, 'wb')
  if not f then
    return
  end
  f:write('#vimide-indexed ', key1, '\n', body)
  f:close()
  if not uv.fs_rename(tmp, p) then
    pcall(os.remove, tmp)
  end
end

-- '아직 반영하지 못한 강제 갱신' 표지: '<db>/refresh.pending'
--
-- 목록을 바꾼 갱신(+/-)은 한 번 시도하고 잊혀졌다. 다른 nvim 이 락을 쥐고
-- 있으면 건너뛰고, gtags -i 가 도는 중에 nvim 을 닫으면 같이 죽고, 다음 시작의
-- 갱신은 축소 방지에 걸려 'n개 -> m개 축소, 자동 갱신 생략' 만 남겼다 - 사용자
-- 로그의 그 줄이다. 그래서 요청을 디스크에 남기고, 그 요청 뒤에 읽은 목록으로
-- 색인이 끝났을 때만 지운다. 어느 nvim 이 끝내든, 다음 시작에서 끝내든 같다.
--
-- 내용: '<host>:<pid>:<hrtime>\t<full 0/1>\t<why>\t<full 을 처음 청한 줄의 id>'
-- 한 줄 (넷째 칸은 full 일 때만). 끝낸 쪽은 시작할 때 읽은 줄과 지금 줄이 같을
-- 때만 지운다. 그 사이 새 요청이 들어왔으면 남겨 두고 한 번 더 돈다 - 그 요청을
-- 낸 nvim 이 이미 닫혔어도.
local function marker_path(root)
  return side_dir(root) .. '/refresh.pending'
end

local function read_marker(root)
  local f = io.open(marker_path(root), 'r')
  if not f then
    return nil
  end
  local l = f:read('*l')
  f:close()
  return (l and l ~= '') and l or nil
end

local function marker_full(line)
  return line ~= nil and line:match('^[^\t]*\t1') ~= nil
end

-- full 을 처음 청한 줄의 id. 넷째 칸이 없는 줄(예전 형식)은 자기 자신이다.
local function marker_origin(line)
  if not marker_full(line) then
    return nil
  end
  return line:match('^[^\t]*\t[^\t]*\t[^\t]*\t([^\t]+)$') or line:match('^([^\t]*)')
end

-- 옆에 쓰고 이름을 바꾼다: 비우고 쓰는 사이에 읽는 쪽이 '표지 없음' 을 보면 안 된다
local function put_marker(root, line)
  pcall(vim.fn.mkdir, side_dir(root), 'p')
  local p = marker_path(root)
  local tmp = ('%s.%d.tmp'):format(p, uv.os_getpid())
  local f = io.open(tmp, 'w')
  if not f then
    return
  end
  f:write(line, '\n')
  f:close()
  if not uv.fs_rename(tmp, p) then
    pcall(os.remove, tmp)
  end
end

local function write_marker(root, full, why)
  local id = ('%s:%d:%d'):format(uv.os_gethostname(), uv.os_getpid(), uv.hrtime())
  -- '목록이 그대로여도 gtags -i 를 돌려라' 는 뜻은 덮어쓰면서 잃지 않는다 - 그
  -- 뜻을 처음 낸 줄의 id 도 같이 옮긴다. 그 요청을 이미 맡아 돌던 쪽이 끝날 때
  -- 그것을 보고 '이 full 은 내가 끝냈다' 를 안다 (full_served). 예전에는 full
  -- 이 그대로 옮겨져, :GtagsIndexRefresh! 나 \fR 이 도는 사이의 + 하나가 끝난
  -- 뒤에 목록 전체로 gtags -i 를 한 번 더 돌렸다 (INT7: single-update 하나면 됐다).
  local origin = full and id or nil
  if not full then
    local old = read_marker(root)
    if marker_full(old) then
      full, origin = true, marker_origin(old)
    end
  end
  put_marker(root, ('%s\t%s\t%s%s'):format(id, full and '1' or '0',
    (tostring(why or ''):gsub('[\t\n]', ' ')), origin and ('\t' .. origin) or ''))
end

-- 이번에 끝낸 일(목록 전체로 돈 gtags -i, 또는 빌드)이 지금 표지(now)의 full
-- 까지 맡았는가: 시작할 때 읽은 표지(seen)가 이미 그 full 을 청하고 있었다.
-- 그러면 표지에서 full 을 내리고(아직 그 줄이면) 고친 줄을 돌려준다 - 다음
-- 차례는 그 사이 바뀐 것만 넣는다. 아니면 now 그대로.
local function full_served(root, seen, now, ran_full)
  if not (ran_full and marker_full(now) and marker_full(seen)
      and marker_origin(now) == marker_origin(seen)) then
    return now
  end
  local id, why = now:match('^([^\t]*)\t[^\t]*\t([^\t]*)')
  if not id or read_marker(root) ~= now then
    return now
  end
  local line = ('%s\t0\t%s'):format(id, why or '')
  put_marker(root, line)
  dbg('표지의 full 은 이번에 끝냈다 ' .. root)
  return line
end

-- 갱신 요청 하나. 기다리는 동안 들어온 요청은 하나로 합친다.
--   why    알림에 붙는 까닭
--   force  축소 방지를 건너뛴다 (목록을 일부러 바꿨다)
--   full   목록이 색인과 같아도 gtags -i 를 돌린다 (밖에서 고친 파일까지)
--   list   projectfiles 가 목록을 바꿨다 (ctags 도 따라가야 한다)
--   added  방금 더한 파일 (절대경로 집합) - 먼저 하나씩 넣어 C-] 가 곧바로 찾게
--   auto   사람이 직접 부른 것이 아니다 (색인하지 않는 모드면 버린다)
local function merge_req(a, b)
  if not a then
    return b
  end
  if not b then
    return a
  end
  local added
  for _, t in ipairs({ a.added or {}, b.added or {} }) do
    for p in pairs(t) do
      added = added or {}
      added[p] = true
    end
  end
  -- 사람이 부른 것(auto=false)이 하나라도 섞이면 모드로 막지 않는다.
  -- nil 은 '상관없음' (재시도할 때 덧붙이는 조각)
  local auto
  if a.auto == false or b.auto == false then
    auto = false
  elseif a.auto or b.auto then
    auto = true
  end
  -- 예전에는 나중 요청이 앞의 것을 그대로 덮었다: 대기 중인 강제 갱신(+/-)
  -- 뒤에 그냥 :GtagsIndexRefresh 가 오면 강제가 풀려 축소 방지에 걸렸다 (T8)
  return {
    why = b.why or a.why,
    force = (a.force or b.force) and true or false,
    full = (a.full or b.full) and true or false,
    list = (a.list or b.list) and true or false,
    auto = auto,
    added = added,
  }
end

-- 이 nvim 이 이 DB 를 고치고 있는가. 한 DB 에는 한 번에 한 일꾼만 붙인다:
-- 'global --single-update' 와 'gtags -i' 가 같은 DB 를 붙들면 서로 물려 끝나지
-- 않는다 (13시간 돈 그 경우). 예전 refresh() 는 저장 갱신(updating)을 보지
-- 않아서 저장 직후의 +/- 가 그 둘을 겹쳐 띄웠다.
local function busy(root)
  return s.building[root] or s.refreshing[root] or s.updating[root]
end

-- 색인이 바뀌었다고 알린다 (계약 C4):
--   User VimIdeIndexUpdated, data = { root, kind = 'build'|'update'|'single',
--                                     paths = { 절대경로... } (single 일 때) }
-- ProjectFilesChanged 는 목록이 바뀐 순간(gtags 가 돌기 전)에 오므로, 색칠
-- (sihlindex)이나 트리처럼 'DB 에 실제로 들어갔나' 를 보는 쪽은 이걸 듣는다.
-- 듣는 쪽의 오류가 이쪽 흐름(락 풀기, 다음 차례)을 끊지 않게 pcall 로 감싼다.
local function fire(root, kind, paths)
  pcall(api.nvim_exec_autocmds, 'User', {
    pattern = 'VimIdeIndexUpdated', modeline = false,
    data = { root = root, kind = kind, paths = paths },
  })
end

-- 이 DB 의 다음 차례. 저장 갱신(파일 하나, 수 ms) 먼저, 미뤄 둔 전체 빌드,
-- 그 다음 미뤄 둔 목록 갱신.
function next_job(root)
  if busy(root) then
    return
  end
  local q = s.pending[root]
  if q and next(q) then
    drain(root)
    return
  end
  local b = s.build_again[root]
  if b then
    s.build_again[root] = nil
    build(root, b.why, b.opts)
    return
  end
  local again = s.refresh_again[root]
  if again then
    s.refresh_again[root] = nil
    refresh(root, again)
  end
end

-- 다른 nvim 이 이 DB 의 락을 쥐고 있을 때: 요청을 버리지 않고 기다린다.
--
-- 예전에는 dbg 한 줄 남기고 돌아갔다. 그 nvim 의 gtags -i 는 이미 예전 목록을
-- 읽은 뒤라, + 한 파일은 트리에 [●] 로 보이면서 'global -P' 에는 영영 나오지
-- 않았다 (재현). 루트마다 타이머 하나로, 락이 풀릴 때까지 본다. 처음 30초는
-- 1초마다, 그 뒤로는 간격을 늘려 간다 (2, 4, 8, 15, 30초). 예전에는 처음부터
-- 늘려(1, 3, 7, 15초에 봤다) 다른 nvim 이 8초에 끝내도 15초에야 알아챘다 -
-- 그동안 <C-]> 의 정의 파일 담기도 답을 기다렸다 (병합 점검 열린 과제 1).
-- 횟수 상한은 두지 않는다 - 다른 nvim 의 전체 빌드는 30분까지 정상이고, 죽은
-- 락은 lock_held 가 걸러 낸다 (pid 확인, 다른 기계는 나이). 한 번에 락 파일
-- 하나를 읽을 뿐 프로세스는 띄우지 않는다.
function wait_lock(root)
  if s.lock_wait[root] then
    return
  end
  s.lock_wait[root] = 0
  local delays = { 2000, 4000, 8000, 15000, 30000 }
  local t0, late = uv.now(), 0
  local function tick()
    local n = s.lock_wait[root]
    if not n then
      return
    end
    local cur = read_lock(root)
    -- 락의 주인이 죽었어도 그 일꾼이 아직 DB 를 고치고 있으면 기다린다 (F5)
    local who = lock_held(cur) and cur or worker_alive(root)
    if who then
      n = n + 1
      s.lock_wait[root] = n
      if n == 1 then
        -- 1초를 넘겨 기다리게 됐을 때 한 번만 말한다 (짧은 겹침은 조용히).
        -- 타이머 안이라 명령의 다른 알림과 쌓여 Press ENTER 를 부르지 않는다.
        notify(('%s 은 다른 nvim 이 색인 중 (pid %s@%s) - 끝나면 반영합니다')
          :format(vim.fn.fnamemodify(root, ':~'), tostring(who.pid),
            tostring(who.host)))
      end
      local d = 1000
      if uv.now() - t0 >= 30000 then
        late = late + 1
        d = delays[math.min(late, #delays)]
      end
      vim.defer_fn(tick, d)
      return
    end
    s.lock_wait[root] = nil
    -- 기다리는 동안 다른 nvim 이 그 요청을 끝냈으면(표지가 지워졌다) 또 돌
    -- 필요가 없다 - 그 nvim 은 우리가 쓴 목록까지 읽고 색인했다.
    -- 남은 표지를 보고 기다린 시작 갱신(refresh 의 N2)도 버린다: 표지를 끝낸
    -- nvim 이 지금 목록을 색인했다 - 또 돌면 한 요청에 두 nvim 이 돈다. 단 그
    -- nvim 은 빠른 길(더한 파일만 single-update)로 끝냈을 수 있다 - 그러면 밖에서
    -- 고친 파일은 아무도 다시 읽지 않았다. 시작 갱신은 예전에도 락에 밀리면
    -- 건너뛰었으니 그대로 둔다. 사람이 부른 :GtagsIndexRefresh(auto=false, 합쳐진
    -- 것 포함)는 버리지 않는다 - '끝나면 반영합니다' 라고 해 놓고 아무 말 없이
    -- 버렸다 (D3, 재현). 그 요청은 아래 next_job 이 지금 돌린다 (! 를 붙인 것이
    -- 그 nvim 의 gtags -i 로 이미 끝났으면 한 번 더 도는 셈이지만, 바뀐 것이
    -- 없으면 금방이다). 표지 없이 고아 일꾼만 기다렸으면 아무도 하지 않았으니
    -- 한다.
    local marked = s.wait_marker[root]
    s.wait_marker[root] = nil
    local again = s.refresh_again[root]
    if again and again.auto ~= false and (again.force or marked)
        and not read_marker(root) then
      s.refresh_again[root] = nil
      dbg('refresh 대기 끝 - 다른 nvim 이 이미 반영 ' .. root)
      -- 그 nvim 이 고친 DB 다. 이 nvim 에서 그 변경을 기다리는 쪽(정의 파일
      -- 담기의 답 - projectfiles 의 when_indexed, 색칠, 트리)에도 알린다.
      -- 알리지 않으면 <C-]> 의 담기는 DB 에 이미 든 파일을 두고 제한 시간
      -- (20초)까지 답하지 않았다 (병합 점검 I1)
      fire(root, 'update')
      if again.list and ctags_follow then
        -- 그 nvim 이 끝나며 같은 tags 파일을 지금 목록으로 이미 따라갔으면 또
        -- 만들지 않는다 (N4/D2: ctags_follow 의 since 설명)
        ctags_follow(root, s.list_at[root] or 0)
      end
    end
    next_job(root)
  end
  vim.defer_fn(tick, 1000)
end

-- indexfiles.sh 한 번의 결과를 잠깐 나눠 쓴다 (auto 모드 - preset 은 목록
-- 파일을 바로 읽는다).
--
-- 시작할 때 같은 목록을 세 번 만들었다: BufReadPre 의 파일 수 세기
-- (count_files), VimEnter 의 증분 갱신, 큰 트리면 ctags 스냅숏. 커널
-- 트리에서는 git ls-files 와 파일마다의 stat/grep 이 세 번이다. 몇 초 안의
-- 결과는 같으니 하나를 띄우고, 기다리는 쪽이 모두 받는다.
--   max_age  이만큼(ms) 안에 만든 결과면 다시 쓴다. 0 이면 늘 새로 만든다
--            (목록을 바꾼 갱신).
local function filelist(root, max_age, cb)
  local fl = filelist_cmd()
  if not fl then
    cb(nil)
    return
  end
  local c = s.fl[root]
  if max_age > 0 and c then
    if c.waiting then
      table.insert(c.waiting, cb)
      return
    end
    if uv.now() - c.at <= max_age then
      vim.schedule(function() cb(c.o) end)
      return
    end
  end
  local mine = { waiting = { cb } }
  s.fl[root] = mine
  local h = spawn({ fl }, { text = true, cwd = root, env = env_for(root),
      timeout = (tonumber(cfg('filelist_timeout_sec', 300)) or 300) * 1000 },
    function(o)
      vim.schedule(function()
        local w = mine.waiting
        mine.waiting, mine.o, mine.at = nil, o, uv.now()
        -- 큰 트리의 목록은 수 MB 다. 나눠 쓸 때가 지나면 놓는다
        vim.defer_fn(function()
          if s.fl[root] == mine then
            s.fl[root] = nil
          end
        end, 30000)
        for _, f in ipairs(w) do
          f(o)
        end
      end)
    end)
  if not h then
    if s.fl[root] == mine then
      s.fl[root] = nil
    end
    for _, f in ipairs(mine.waiting) do
      f(nil)
    end
  end
end

-- ---------------------------------------------------------------------------
-- full build:  file list | gtags -f -
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
function build(root, why, opts)
  opts = opts or {}
  if not enabled() then
    return
  end
  -- 이 nvim 이 같은 DB 를 고치는 중이면 끝난 뒤에 한다. 예전에는 증분 갱신이
  -- 도는 중에도 그대로 들어가 한 DB 에 일꾼 둘이 붙었다 (락은 이 nvim 것이라
  -- 통과했다).
  if busy(root) then
    if s.building[root] then
      return
    end
    s.build_again[root] = { why = why, opts = opts }
    if opts.confirm then
      notify('지금 도는 색인 작업이 끝나면 다시 만듭니다')
    end
    return
  end
  local gt = gtags_cmd()
  if not gt then
    notify('gtags 를 찾을 수 없습니다', vim.log.levels.WARN)
    return
  end
  local short = vim.fn.fnamemodify(root, ':~')
  -- 다른 nvim 이 이미 이 트리를 색인 중이면 손대지 않는다. 이 락이 없던
  -- 동안에는 nvim 을 열 때마다 같은 트리에 gtags 가 하나씩 더 붙었다.
  local got, why_not = take_lock(root)
  if not got then
    notify(short .. (why_not == 'unwritable' and ' 의 색인 디렉터리에 쓸 수 없습니다 — 건너뜁니다'
      or ' 은 다른 nvim 이 색인 중입니다 — 건너뜁니다'))
    return
  end
  s.building[root] = true
  notify('indexing ' .. short .. (why and (' (' .. why .. ')') or '') .. ' …')
  local t0 = uv.now()
  -- 이 빌드가 맡는 요청: 지금 남아 있는 표지까지 (아래에서 읽는 목록은 그
  -- 요청들이 쓴 목록을 담는다)
  local seen = read_marker(root)
  local snaptext -- preset 목록이면 그 내용 (사본으로 남긴다)
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
    vim.schedule(function() next_job(root) end)
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
        if o.code == 0 then
          -- DB 가 이제 이 목록과 같다: 사본을 남기고, 그 전에 들어온 요청은 끝났다
          write_copy(root, snaptext)
          local now = read_marker(root)
          if now and now == seen then
            pcall(os.remove, marker_path(root))
          elseif now then
            -- 빌드는 목록 전체를 처음부터 넣었다: 시작할 때 이미 있던 full 은 끝났다
            now = full_served(root, seen, now, true)
            s.refresh_again[root] = merge_req(s.refresh_again[root], { why = '목록 변경',
              force = true, full = marker_full(now), list = true, auto = true })
          end
        else
          -- 반쯤 옮겨진 DB 를 사본이 설명한다고 믿으면 안 된다
          write_copy(root, nil)
        end
        s.building[root] = nil
        release_lock(root)
        s.roots = {} -- a new database may have appeared above other dirs too
        pcall(vim.fn.delete, tmp, 'rf')
        git_exclude(root)
        if o.code == 0 then
          fire(root, 'build')
          notify(string.format('%s indexed: %d files, %.1fs',
            short, n, (uv.now() - t0) / 1000))
        else
          notify('indexing failed: ' ..
            ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))),
            vim.log.levels.WARN)
        end
        -- files saved while the build ran were queued and skipped: flush them,
        -- then whatever list change came in meanwhile
        vim.schedule(function() next_job(root) end)
      end)
    end)
    if not ok then
      fail(nil)
    end
  end

  -- 2. refuse (or ask) when the new list covers far fewer files
  local function check_coverage(n)
    -- preset 목록은 projectfiles 가 통째로 쓴 '정답' 이다. 자동 빌드(색인이
    -- 없을 때, 자리 되찾기)는 그대로 따른다. :GtagsIndex 는 여전히 묻는다.
    if snaptext and not opts.confirm then
      run_gtags(n)
      return
    end
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
  materialize(root)
  if preset_mode(root) then
    local snap, why_not = preset_snapshot(root)
    if not snap or #snap.lines == 0 then
      -- preset 인데 목록이 없거나 비었다: 프로젝트 전체(indexfiles.sh 의 git
      -- ls-files)로 떨어지지 않는다
      fail(why_not == 'torn' and (short .. ': preset 목록을 다른 nvim 이 쓰는 중입니다 - 잠시 뒤 다시')
        or ('preset 목록에 색인할 파일이 없습니다: ' .. short))
      return
    end
    snaptext = snap.text
    write_filelist(list, snaptext)
    check_coverage(#snap.lines)
    return
  end
  -- 셸 없이 목록 생성기만 띄우고, 파일로 쓰는 것과 줄 세기는 Lua 가 한다.
  -- 시작할 때 방금 센 목록이면 그대로 쓴다 (filelist).
  filelist(root, opts.confirm and 0 or 10000, function(o)
    local n = write_filelist(list, o and o.code == 0 and o.stdout or nil)
    if not o or o.code ~= 0 or n == 0 then
      fail(o and ('색인할 파일을 찾지 못했습니다: ' .. short) or nil)
      return
    end
    check_coverage(n)
  end)
end

-- ---------------------------------------------------------------------------
-- incremental refresh of a whole project (startup, list changes)
-- ---------------------------------------------------------------------------
-- 'gtags -i -f list' reindexes only files whose timestamp moved and keeps the
-- database equal to the list - unlike 'global -u', which walks the tree itself
-- and would pull in files a project deliberately left out of .indexfiles.
-- 'equal to the list' cuts both ways: see the coverage check below.
--
-- req: merge_req 의 설명. 예전 모양 refresh(root, why, force) 도 받는다.
function refresh(root, req, force_old)
  if type(req) ~= 'table' then
    req = { why = req, force = force_old and true or false, full = true }
  end
  if not enabled() then
    return
  end
  -- 색인하지 않는 모드(none/미설정)로 바뀐 프로젝트는 건드리지 않는다. preset
  -- 의 마지막 항목을 빼면 none 이 되는데, 그 뒤의 강제 갱신이 목록 파일 없이
  -- indexfiles.sh 를 불러 git ls-files - 프로젝트 전체 - 를 색인했다 (50개 ->
  -- 6,500개). 사람이 직접 부른 :GtagsIndexRefresh 는 :GtagsIndex 처럼 둔다.
  if req.auto and type(_G.projectfiles_should_index) == 'function'
      and not _G.projectfiles_should_index(root) then
    dbg('refresh 건너뜀 (색인하지 않는 모드) ' .. root)
    return
  end
  -- A list change while a refresh is still running must not be dropped:
  -- remember it and run once more when this one finishes (adding a file to
  -- a preset right after switching to it would otherwise never be indexed).
  if busy(root) then
    s.refresh_again[root] = merge_req(s.refresh_again[root], req)
    return
  end
  local gt = gtags_cmd()
  if not gt then
    -- GTAGS 는 못 고쳐도 ctags 는 목록을 따라간다: projectfiles 는 갱신을 이리로
    -- 넘기면 직접 :GutentagsUpdate! 를 부르지 않는다 (K2)
    if req.list and ctags_follow then
      ctags_follow(root)
    end
    return
  end
  -- build 와 같은 이유로 인스턴스 간 락을 먼저 잡는다. 목록을 바꾼 갱신은
  -- 버리지 않고 기다린다 (wait_lock). 시작할 때의 갱신은 버려도 된다 - 그
  -- nvim 이 지금 같은 일을 하고 있다.
  --
  -- 단 아직 반영하지 못한 표지가 남아 있거나, 락의 주인은 죽었고 그 일꾼만
  -- 돌면(F5) 기다린다. 주인이 SIGKILL 로 죽으면 done() 이 없다: 그 nvim 이
  -- gtags -i 뒤에 줄 세운 + 의 표지를 아무도 이어받지 않아, 고아가 도는 사이
  -- 띄운 nvim 이 시작 갱신을 버리면 더한 파일이 세션 내내 GTAGS 밖에 남았다
  -- (N2, 재현). 고아가 끝나면 wait_lock 이 그 표지를 이어받는다. 살아 있는
  -- nvim 이 그 표지를 끝냈으면 wait_lock 이 시작 갱신은 버리고, 사람이 부른
  -- 것은 그 뒤에 돌린다 (D3).
  --
  -- 락 파일을 만들 수조차 없으면(DB 디렉터리에 쓸 수 없다) 기다리지 않는다 -
  -- 강제든 표지든 같다. 풀릴 락이 없어 wait_lock 이 1초마다 다시 왔다 (D4).
  local got, why_not = take_lock(root)
  if not got and why_not == 'unwritable' then
    dbg('refresh 그만둠 (락 파일을 만들 수 없음 - DB 디렉터리에 쓸 수 없다) ' .. root)
    if req.auto == false then
      notify(vim.fn.fnamemodify(root, ':~') .. ' 의 색인 디렉터리에 쓸 수 없습니다 — 건너뜁니다')
    end
    return
  end
  if not got then
    local marked = read_marker(root) ~= nil
    if req.force or marked or not lock_held(read_lock(root)) then
      if marked then
        s.wait_marker[root] = true
      end
      s.refresh_again[root] = merge_req(s.refresh_again[root], req)
      wait_lock(root)
    else
      dbg('refresh 건너뜀 (다른 nvim 이 색인 중) ' .. root)
      if not req.auto then
        notify(vim.fn.fnamemodify(root, ':~') ..
          ' 은 다른 nvim 이 색인 중입니다 — 건너뜁니다 (! 를 붙이면 기다렸다 합니다)')
      end
    end
    return
  end
  s.refreshing[root] = req
  local short = vim.fn.fnamemodify(root, ':~')
  local t0 = uv.now()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local list = tmp .. '/files'
  -- 이번 갱신이 맡는 요청: 지금 남아 있는 표지까지. 표지는 목록을 쓴 뒤에
  -- 남기므로, 이 뒤에 읽는 목록에는 그 요청들의 변경이 들어 있다.
  local seen = read_marker(root)
  local force, full = req.force, req.full or marker_full(seen)
  if seen and not force then
    -- 지난번에 끝내지 못한 강제 갱신이 남아 있다 (다른 nvim 의 락에 밀렸거나,
    -- 도는 중에 nvim 을 닫았다): 축소 방지를 건너 그 목록을 따른다
    force, full = true, true
    dbg('refresh: 남은 표지를 이어받음 ' .. root)
  end
  local snaptext   -- preset 목록 (성공하면 사본으로 남긴다)
  local changed    -- 목록이 사본(DB)과 달랐는가 (nil = 모른다)

  -- ok: true 성공 / false 실패 / nil 손대지 않음
  local function done(ok, msg, level, retry_ms)
    s.refreshing[root] = nil
    if ok then
      s.refresh_fail[root] = nil
      local now = read_marker(root)
      if now and now == seen then
        pcall(os.remove, marker_path(root))
      elseif now then
        -- 도는 동안 새 요청이 들어왔다 (다른 nvim 이 남긴 것일 수도): 그 목록은
        -- 이번에 읽은 것보다 나중 것이니 한 번 더 돈다. 그 줄의 full 이 이번에
        -- 끝낸 것을 물려받은 것뿐이면 바뀐 것만 넣는다 (INT7)
        now = full_served(root, seen, now, full)
        s.refresh_again[root] = merge_req(s.refresh_again[root], { why = '목록 변경',
          force = true, full = marker_full(now), list = true, auto = true })
      end
    elseif ok == false and force and not retry_ms then
      -- 실패한 강제 갱신은 두 번까지 다시 해 본다 (시간 제한에 끊긴 경우가
      -- 여기다). 그래도 안 되면 표지가 남아 다음 시작에서 한다.
      local n = (s.refresh_fail[root] or 0) + 1
      s.refresh_fail[root] = n <= 2 and n or nil
      retry_ms = n <= 2 and ({ 2000, 30000 })[n] or nil
    end
    release_lock(root)
    pcall(vim.fn.delete, tmp, 'rf')
    if msg then
      notify(msg, level)
    end
    -- ctags 는 목록이 색인과 달랐을 때 따라간다. 같았어도 이 nvim 이 낸 목록
    -- 변경을 아직 따라가지 않았으면(ct_due) 따라간다 - 그 변경을 앞의 빌드
    -- (:GtagsCompact, 자리 되찾기)가 먼저 GTAGS 에 담아 버리면 이 갱신은
    -- '목록이 색인과 같음' 으로 끝나 ctags 만 낡은 채 남았다.
    if ok and req.list and (changed ~= false or s.ct_due[root]) and ctags_follow then
      ctags_follow(root)
    end
    if retry_ms then
      vim.defer_fn(function()
        s.refresh_again[root] = merge_req(s.refresh_again[root],
          merge_req(req, { force = force, full = full }))
        next_job(root)
      end, retry_ms)
    end
    vim.schedule(function() next_job(root) end)
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
    local ims = imin > 0 and math.floor(imin * 60 * 1000) or 0
    local ok = spawn({ gt, '-i', '-f', list, dbpath(root) },
      { text = true, cwd = root, env = env_for(root), timeout = ims }, function(o)
        vim.schedule(function()
          worker_clear(root)
          local secs = (uv.now() - t0) / 1000
          dbg(('gtags -i rc=%s %.1fs %s'):format(tostring(o.code), secs, root))
          if o.code ~= 0 then
            -- 중간에 끊긴 DB 를 사본이 설명한다고 믿으면 안 된다
            write_copy(root, nil)
            done(false, short .. ' 색인 갱신 실패: ' ..
              ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))),
              vim.log.levels.WARN)
            return
          end
          -- DB 가 이제 이 목록과 같다. auto 모드 목록은 따라가지 않는다(nil).
          write_copy(root, snaptext)
          compact_bump(root)
          local due = compact_due(root, n)
          if due then
            -- 자리를 회수한다. done() 을 먼저 불러 이 갱신을 끝내고,
            -- 전체 빌드는 그 다음 차례에 새로 시작한다(build 는 스스로
            -- 락을 잡는다 - 지금 잡고 있는 것을 놓기 전에 부르면 '다른
            -- nvim 이 색인 중'으로 스스로를 막는다).
            done(true)
            fire(root, 'update')
            vim.schedule(function()
              compact_bump(root, true)
              build(root, '자리 되찾기 (' .. due .. ')', {})
            end)
            return
          end
          -- small projects finish before anyone notices; stay quiet there.
          -- 서버에서는 이 한 줄이 '+/- 가 색인에 들어갔다' 는 유일한 신호다
          done(true, secs > 3 and string.format('%s 색인 갱신 완료 (%d files, %.1fs%s)',
            short, n, secs, req.why and (', ' .. req.why) or '') or nil)
          fire(root, 'update')
        end)
      end)
    if not ok then
      done(false)
      return
    end
    -- 제한이 없으면(0) 기다리는 쪽도 끝을 모른다: 락의 나이 한도만큼만 믿는다
    worker_note(root, ok, ims > 0 and ims
      or (tonumber(cfg('lock_stale_min', 90)) or 90) * 60 * 1000)
  end

  -- 'gtags -i -f list' makes the database match the list: files missing from
  -- it are DELETED from the index. A half-written cscope.files or a narrowed
  -- .indexfiles would silently throw most of the project away, so the same
  -- coverage check the full build uses guards this too - but here it only
  -- skips (a background job at startup must not ask questions).
  --
  -- preset 목록은 예외다: projectfiles 가 preset 에서 통째로 쓴 '정답' 이다.
  -- preset 은 여러 루트가 같이 쓰고(git 으로 맥과 서버도) 다른 곳에서 고친
  -- 것이 이 루트의 다음 시작에서야 반영되는데, 그게 반 넘게 줄면 시작할
  -- 때마다 '축소, 자동 갱신 생략' 만 남기고 지운 파일을 계속 색인하고 있었다.
  -- 그때는 막지 않고 한 줄 알린다.
  local function check(n, preset, prev_n)
    -- 빠른 길(single-update)을 기다리는 사이 모드가 바뀌었으면 손대지 않는다
    if req.auto and type(_G.projectfiles_should_index) == 'function'
        and not _G.projectfiles_should_index(root) then
      done(nil)
      return
    end
    if force then
      run_incremental(n) -- the user just changed the list on purpose
      return
    end
    if preset then
      local function go(old)
        if old >= 100 and n < math.floor(old / 2) then
          notify(('%s: 색인 %d개 -> %d개 (preset 목록을 따름)'):format(short, old, n))
        end
        run_incremental(n)
      end
      if prev_n then
        go(prev_n)
      else
        db_file_count(root, go)
      end
      return
    end
    db_file_count(root, function(old)
      if old < 100 or n >= math.floor(old / 2) then
        run_incremental(n)
        return
      end
      done(nil, string.format(
        '%s: 색인 %d개 -> %d개 축소, 자동 갱신 생략 (:GtagsIndexRefresh! 로 강제)',
        short, old, n), vim.log.levels.WARN)
    end)
  end

  -- 더한 파일을 하나씩 바로 넣는다 ('global --single-update', 파일마다 수십
  -- ms, 목록 크기와 무관). gtags -i 를 기다리면 + 직후의 C-] 가 예전 DB 에서
  -- 답했다 - 정의 대신 원형으로 가거나 '정의를 찾지 못했습니다' (재현). 락은
  -- 이미 쥐고 있고 하나씩 돌리므로 한 DB 에 일꾼 둘이 붙지 않는다.
  local function run_fast(rels, cb)
    local prog = global_cmd()
    if not prog then
      cb(false)
      return
    end
    -- 표(table)로 둔다: tagfunc 가 한 번 기다려 본 것을 여기에 적는다 (INT3)
    s.fast[root] = {}
    local i, all_ok, paths = 0, true, {}
    local ums = (tonumber(cfg('update_timeout_sec', 120)) or 120) * 1000
    local function step()
      i = i + 1
      local rel = rels[i]
      if not rel then
        s.fast[root] = nil
        if #paths > 0 then
          fire(root, 'single', paths)
        end
        cb(all_ok)
        return
      end
      local h
      h = spawn({ prog, '--single-update', rel },
        { text = true, cwd = root, env = env_for(root), timeout = ums },
        function(o)
          vim.schedule(function()
            worker_clear(root)
            dbg('fast single-update rc=' .. tostring(o.code) .. ' ' .. rel)
            if o.code == 0 then
              paths[#paths + 1] = rel:sub(1, 1) == '/' and rel or (root .. '/' .. rel)
            else
              all_ok = false
            end
            step()
          end)
        end)
      if not h then
        all_ok = false
        step()
        return
      end
      worker_note(root, h, ums)
    end
    step()
  end

  -- a preset decides which files exist for the indexer: write it out before
  -- the list is read, or the very first build indexes the whole tree
  materialize(root)
  if preset_mode(root) then
    local snap, why_not = preset_snapshot(root)
    if not snap then
      if why_not == 'torn' then
        -- 다른 nvim 이 목록을 쓰는 중이다: 잠시 뒤 다시. 끝없이 하지는 않는다 -
        -- 예전에는 300ms 마다 영영 돌면서(:GtagsIndexStatus 에도 안 보였다)
        -- 아무 말도 없었다 (INT4). 그만두면 표지는 남는다: 다음 +/- 나 다음
        -- 시작이 그 목록으로 다시 한다.
        local tries = (s.torn[root] or 0) + 1
        if tries <= (tonumber(cfg('torn_retries', 20)) or 20) then
          s.torn[root] = tries
          done(nil, nil, nil, 300)
        else
          s.torn[root] = nil
          done(nil, short .. ': .tags/files 가 읽는 동안 계속 바뀝니다 - 색인 갱신을'
            .. ' 미룹니다 (:ProjectFilesReindex 로 다시 쓰기)', vim.log.levels.WARN)
        end
      else
        -- preset 인데 목록이 없다 (펼칠 수 없는 preset - projectfiles 가 이미
        -- 알렸다). 프로젝트 전체로 떨어지지 않는다: 목록과 색인을 그대로 둔다.
        dbg('refresh: preset 목록 없음 ' .. root)
        done(nil)
      end
      return
    end
    s.torn[root] = nil
    gt_retry(root)
    -- 저장 갱신의 '목록에 있나' 도 방금 읽은 것으로 (in_list)
    s.lists[root] = { key = snap.key, set = snap.set }
    local n = #snap.lines
    if n == 0 and not intended_empty(root) then
      -- 빈 목록인데 projectfiles 가 '일부러 비운 것' 이라고 하지 않는다 - 저장한
      -- 적 없는 preset 이름(오타), 지운 preset. 예전에는 그대로 넘겨 GTAGS 가 0개,
      -- ctags 가 머리말 24줄이 됐다 (F2/K3). 색인도 ctags 도 그대로 둔다. 요청은
      -- 끝난 것으로 친다 - 표지를 남기면 시작할 때마다 이 자리를 다시 돈다.
      dbg('refresh: 빈 목록 - 의도한 빈 preset 이 아니라 그대로 둠 ' .. root)
      changed = false
      done(true)
      return
    end
    local has_db = uv.fs_stat(dbpath(root) .. '/GTAGS') ~= nil
    if n == 0 and not has_db then
      done(true) -- 빈 preset 이고 색인도 없다
      return
    end
    snaptext = snap.text
    -- 목록과 DB(사본)를 견준다
    local prev, prev_n = read_copy(root)
    local add, removed = {}, 0
    if prev then
      for _, l in ipairs(snap.lines) do
        if not prev[l] then
          add[#add + 1] = l
        end
      end
      removed = prev_n - (n - #add)
      changed = #add > 0 or removed > 0
      if not changed and not full then
        dbg('refresh: 목록이 색인과 같음 ' .. root)
        done(true)
        return
      end
    end
    local fmax = tonumber(cfg('fast_add_max', 8)) or 8
    local fast = {}
    if has_db and fmax > 0 then
      if prev then
        if #add <= fmax then
          fast = add
        end
      elseif req.added then
        -- 사본이 없으면 무엇이 바뀌었는지 모른다: 요청이 알려 준 것만 먼저
        for p in pairs(req.added) do
          local rel = p:sub(1, #root + 1) == root .. '/' and p:sub(#root + 2) or p
          if snap.set[rel] then
            fast[#fast + 1] = rel
          end
        end
        table.sort(fast)
        if #fast > fmax then
          fast = {}
        end
      end
    end
    -- 더한 것뿐이면 그것만 넣고 끝낸다. 뺀 것이 있으면 gtags -i 가 맡는다
    -- (single-update 는 아직 있는 파일을 지우지 못한다).
    local only_fast = prev and removed == 0 and #fast > 0 and #fast == #add
        and not full
    dbg(('refresh: 목록 %d, 사본 %s, +%d -%d, 빠른 길 %d%s%s %s'):format(n,
      prev and tostring(prev_n) or '없음', #add, removed, #fast,
      only_fast and ' (그것만)' or '', full and ' full' or '', root))
    -- 일부러 비운 preset 의 빈 목록은 그대로 넘긴다: 'gtags -i -f <빈 목록>' 이
    -- DB 를 비운다 (예전에는 아무 것도 하지 않아, 빈 preset 으로 바꿔도 전의
    -- 색인이 답했다)
    local f = io.open(list, 'wb')
    if f then
      f:write(snaptext)
      f:close()
    end
    local function after_fast(all_ok)
      if only_fast and all_ok then
        write_copy(root, snaptext)
        done(true)
        return
      end
      check(n, true, prev_n)
    end
    if #fast > 0 then
      run_fast(fast, after_fast)
    else
      after_fast(true)
    end
    return
  end
  -- auto 모드(또는 projectfiles 없음): 목록은 indexfiles.sh 가 정한다.
  -- 시작할 때는 방금 센 목록을 나눠 쓴다 (filelist).
  filelist(root, force and 0 or 10000, function(o)
    if req.auto and type(_G.projectfiles_should_index) == 'function'
        and not _G.projectfiles_should_index(root) then
      done(nil)
      return
    end
    if preset_mode(root) then
      -- 목록을 만드는 사이 preset 으로 바뀌었다. 이 목록은 프로젝트 전체다 -
      -- 버리고 preset 목록으로 다시 한다.
      s.refresh_again[root] = merge_req(s.refresh_again[root],
        merge_req(req, { force = force, full = true }))
      done(nil)
      return
    end
    local n = write_filelist(list, o and o.code == 0 and o.stdout or nil)
    if not o or o.code ~= 0 or n == 0 then
      done(nil)
      return
    end
    check(n, false)
  end)
end

-- ---------------------------------------------------------------------------
-- incremental update of one file
-- ---------------------------------------------------------------------------
function drain(root)
  if busy(root) then
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
  local prog = global_cmd()
  if not prog then
    s.pending[root] = nil -- 넣을 수단이 없다: 다음 차례(목록 갱신)를 막지 않게
    return
  end
  -- 다른 nvim 이 이 DB 를 고치는 중이면 같이 쓰지 않는다 (한 DB 에 일꾼 둘이
  -- 붙으면 서로 물린다). 큐에 남겨 두고, 락이 풀리면 넣는다.
  -- 락 파일을 만들 수조차 없으면(DB 디렉터리에 쓸 수 없다) 기다릴 락이 없다:
  -- 큐를 버리고 다음 차례로 (D4 - 그대로 두면 wait_lock 이 1초마다 다시 왔다)
  local got, why_not = take_lock(root)
  if not got and why_not == 'unwritable' then
    s.pending[root] = nil
    dbg('drain 그만둠 (락 파일을 만들 수 없음) ' .. root)
    next_job(root)
    return
  end
  if not got then
    dbg('drain deferred (lock) ' .. root)
    wait_lock(root)
    return
  end
  q[path] = nil
  if not next(q) then
    s.pending[root] = nil
  end
  s.updating[root] = true
  local rel = path:sub(1, #root + 1) == root .. '/' and path:sub(#root + 2)
      or path
  dbg('single-update ' .. rel .. ' (cwd ' .. root .. ')')
  local ums = (tonumber(cfg('update_timeout_sec', 120)) or 120) * 1000
  local key0 = gpath_key(root)
  local ok = spawn({ prog, '--single-update', rel },
    { text = true, cwd = root, env = env_for(root), timeout = ums },
    function(o)
      vim.schedule(function()
        worker_clear(root)
        if o.code == 0 then
          copy_follow(root, rel, key0)
        end
        s.updating[root] = nil
        release_lock(root)
        dbg('single-update rc=' .. tostring(o.code) .. ' ' .. rel ..
          ((o.stderr or '') ~= '' and (' err=' .. o.stderr:gsub('%s+$', '')) or ''))
        if o.code == 0 then
          fire(root, 'single', { path })
        elseif not s.warned['u:' .. root] then
          s.warned['u:' .. root] = true
          notify('색인 갱신 실패(' .. rel .. '): ' ..
            ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))) ..
            ' - :GtagsIndex 로 다시 만들 수 있습니다', vim.log.levels.WARN)
        end
        next_job(root)
      end)
    end)
  if not ok then
    s.updating[root] = nil
    release_lock(root)
    return
  end
  worker_note(root, ok, ums)
end

-- '<root>/.tags/files' is the preset list (see projectfiles.lua). While it
-- exists, only the files in it belong to the index - saving anything else
-- must not quietly add it.
local function in_list(root, path)
  local file = list_file(root)
  local st = uv.fs_stat(file)
  if not st then
    return true -- auto mode: everything in the project counts
  end
  local key = stat_key(st)
  local c = s.lists[root]
  if not c or c.key ~= key then
    c = { key = key, set = {} }
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
  -- preset 모드면 목록 파일의 줄 수가 곧 답이다. indexfiles.sh 를 띄울 까닭이
  -- 없다 (그 스크립트도 이 파일을 그대로 내놓는다). 답은 다음 차례에 준다 -
  -- BufReadPre 안에서 곧바로 알림을 띄우면 Press ENTER 가 뜬 채로 시작이
  -- 멈췄다.
  if preset_mode(root) then
    if not uv.fs_stat(list_file(root)) then
      materialize(root)
    end
    -- 쓰는 중으로 보이면(torn) 잠깐 뒤 다시 센다. nil 을 넘기면 '모름 = 큰
    -- 트리' 로 gutentags 에서 떼어 버린다 - 방금 고쳐 쓴 목록 하나에 그 세션
    -- 내내 ctags 가 목록을 따라가지 않았다. 다섯 번(2.5초)이 지나도 그러면
    -- 읽은 그대로 줄을 센다.
    local tries = 0
    local function go()
      local snap, why = preset_snapshot(root)
      if not snap and why == 'torn' and tries < 5 then
        tries = tries + 1
        vim.defer_fn(go, 500)
        return
      end
      -- 목록이 아예 없다: preset 이 이 체크아웃에서 하나도 펼쳐지지 않거나(다른
      -- 체크아웃의 preset) 읽을 수 없다. 여기서도 nil 을 넘기면 1,600개 트리가
      -- '큰 트리' 가 되어 세션 내내 gutentags 에서 떼이고, 목록이 없어 실패할
      -- ctags_build 까지 돌았다 - + 로 목록이 생긴 뒤에도 ctags 는 다시 켤
      -- 때까지 따라오지 않았다 (R3). 정하지 않고 미뤄 둔다(false): 목록이 생기면
      -- ctags_follow·guard_ctags 가 다시 센다. 그동안 gutentags 는
      -- autoindex_gutentags_ok 가 막는다 (s.gt_wait).
      if not snap and why == 'missing' then
        counted[root] = false
        return
      end
      local n = snap and #snap.lines or nil
      if not snap and why == 'torn' then
        local ok, l = pcall(vim.fn.readfile, list_file(root))
        n = ok and #l or nil
      end
      cb(n)
    end
    vim.schedule(go)
    return
  end
  -- auto 모드: 곧이어 도는 시작 갱신·ctags 스냅숏과 같은 결과를 나눠 쓴다
  filelist(root, 10000, function(o)
    if not o or o.code ~= 0 then
      cb(nil)
      return
    end
    local n = 0
    for _ in (o.stdout or ''):gmatch('[^\n]+') do n = n + 1 end
    cb(n)
  end)
end

-- 이 루트를 gutentags 에서 떼어내고, 대신 ctags 스냅숏을 우리가 만든다.
-- no_build: gutentags 만 막고 우리 ctags 는 아직 만들지 않는다 (모드 미정/none)
-- rebuild : 있는 tags 가 다른 목록으로 만든 것이다 (preset 을 바꿨다) - 새로 만든다
-- 돌려주는 것: 이번에 제외 목록에 넣었으면 true. 이미 있었으면(사용자가 넣었다,
-- 크기 가드, 앞선 세기) false - guard_ctags_decide 는 제가 넣은 것만 되돌린다
local function exclude_gutentags(root, why, no_build, rebuild)
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
    notify(string.format(no_build and '%s: %s - 색인 모드를 고르면 ctags 를 여기서 직접 만듭니다'
      or '%s: %s - ctags 는 여기서 직접 만듭니다',
      vim.fn.fnamemodify(root, ':~'), why or 'big tree'))
  end
  if no_build then
    return not known
  end
  if cfg('ctags', 1) ~= 0 and not s.ctags_tried[root] then
    local have = ctags_apply(root)
    if not have or ctags_stale(root) or rebuild then
      s.ctags_tried[root] = true
      ctags_build(root, (have and not rebuild) and '오래됨' or (why or 'big tree'))
    end
  end
  return not known
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
  -- preset 의 목록이 없거나, 비었는데 일부러 비운 preset 이 아니면(저장한 적
  -- 없는 이름, 지운 preset) 붙지 않는다. 붙는 순간 gutentags 가 그 프로젝트의
  -- tags 를 새로 만드는데(generate_on_new) 그 목록으로는 머리말 24줄이나
  -- (빈 목록) 트리 전체(목록 없음 -> git ls-files)가 된다 (K3/F4). 목록이
  -- 제대로 생기면 ctags_follow 가 그때 붙인다.
  local dir = vim.fs.dirname(path)
  local proot = s.roots[dir] or scan_root(dir) or marker_root(path)
  if proot and preset_mode(proot) and not list_ready(proot) then
    s.gt_wait[proot] = true -- 목록이 생기면 붙인다 (ProjectFilesChanged)
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
local gutentags_flip      -- 아래에서 정의; preset 을 바꿔 그 판단이 뒤집혔을 때

local function guard_ctags(path)
  local max = cfg('ctags_max_files', 5000)
  if max <= 0 then
    return
  end
  local root = marker_root(path)
  if not root then
    return
  end
  if counted[root] then
    -- 모드를 정하기 전에 세어 두고 미뤄 둔 ctags 를, 모드를 고른 뒤 여는 첫
    -- 파일에서 만든다
    local why = s.ctags_deferred and s.ctags_deferred[root]
    if why and (not _G.projectfiles_should_index_file
        or _G.projectfiles_should_index_file(path)) then
      s.ctags_deferred[root] = nil
      exclude_gutentags(root, why)
    end
    return
  end
  -- 목록이 없어 미뤄 둔 루트(false)는 목록이 생긴 뒤에 센다 - 파일을 열 때마다
  -- 펼쳐지지 않는 preset 을 다시 펴 보지 않는다 (count_files)
  if counted[root] == false and preset_mode(root)
      and not uv.fs_stat(list_file(root)) then
    return
  end
  counted[root] = true
  count_files(root, function(n) guard_ctags_decide(root, max, n) end)
end

guard_ctags_decide = function(root, max, n)
  -- preset 을 바꿔 다시 센 것이면(autoindex_refresh) 예전 판단을 뒤집을 수 있다.
  -- 뒤집는 것은 세기가 정한 것뿐이다 (s.count_mode 의 big/put). 예전에는 제외
  -- 목록에 있기만 하면 큰 트리였다고 보았는데, 그 목록에는 크기 가드
  -- (autoindex_gutentags_ok, 'tags NMB')와 사용자가 넣은 루트도 있다 - preset 을
  -- 바꾸면 그것까지 빼고 tags 를 지워, gutentags 가 다시 붙어 저장마다 큰 tags 를
  -- 통째로 다시 썼다 (병합 점검 OI4, 재현)
  local switched = s.switched[root]
  s.switched[root] = nil
  local prev = s.count_mode[root]
  local rec = { mode = mode_now(root) }
  s.count_mode[root] = rec
  if n ~= nil and n <= max then
    if switched and prev and prev.big then
      gutentags_flip(root, false, prev.put)
    end
    -- 작아졌어도 제외가 남았다(크기 가드, 사용자가 넣었다): gutentags 가 따라오지
    -- 않으니 우리 스냅숏을 새 목록으로 다시 만든다. 그대로 두면 'tags' 와 SiHl 이
    -- 예전 preset 의 파일을 보았다 (병합 점검, 재현: 102개 목록에 1201개 tags).
    -- 스냅숏이 없던 루트에는 새로 만들지 않는다 (ctags_file 은 아래에서 정의된다)
    local tf = switched and _G.autoindex_ctags_file(root)
    if tf and uv.fs_stat(tf) and not (_G.projectfiles_should_index
        and not _G.projectfiles_should_index(root)) then
      for _, r in ipairs(vim.g.gutentags_exclude_project_root or {}) do
        if r == root then
          s.ctags_tried[root] = nil
          exclude_gutentags(root, n .. ' files', nil, true)
          break
        end
      end
    end
    return
  end
  -- 큰 트리다. 넣은 것이 이 세기가 아니어도 앞선 세기가 넣었으면 그것을 이어 간다
  rec.big = true
  rec.put = prev and prev.big and prev.put or nil
  -- 색인 모드를 아직 안 정했거나(unset) none 이면 우리 ctags 는 만들지 않는다 -
  -- 예전에는 파일 하나를 열자마자 5000개가 넘는 트리 전체의 ctags 를 만들었다
  -- (QA: 4만 파일, 9초, 9.7MB). 그래도 세기는 하고 gutentags 는 막아 둔다: 세기를
  -- 모드를 고른 뒤로 미루면, 고른 뒤 여는 첫 버퍼에 세기가 끝나기 전에
  -- gutentags 가 붙어 큰 트리 전체의 tags 를 만들었다 (반대 심문). 만들기는
  -- 모드를 고른 뒤 여는 첫 파일에서 한다 (위 guard_ctags).
  local why = n and (n .. ' files') or 'big tree'
  if _G.projectfiles_should_index and not _G.projectfiles_should_index(root) then
    s.ctags_deferred = s.ctags_deferred or {}
    s.ctags_deferred[root] = why
    rec.put = exclude_gutentags(root, why, true) or rec.put
    return
  end
  if switched then
    -- 붙어 있는 gutentags 를 뗀다: 작은 preset 에서 바꿨거나, 큰 트리로 시작할
    -- 때 세기(비동기)보다 먼저 첫 버퍼에 붙었다 - 그대로 두면 새 큰 목록의 tags
    -- 를 gutentags 가 통째로 만들고 저장마다 다시 썼다 (gutentags_flip).
    -- 큰 트리였어도 스냅숏은 예전 preset 의 목록이다 - 새 목록으로 다시 만든다
    gutentags_flip(root, true)
    s.ctags_tried[root] = nil
    rec.put = exclude_gutentags(root, why, nil, true) or rec.put
    return
  end
  rec.put = exclude_gutentags(root, why) or rec.put
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
    vim.fn.expand('~/.local/bin/ctags', 1), 'uctags', 'ctags' }) do
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
    -- expand(, 1): 캐시가 /tmp 아래면(.vimrc 의 /tmp/vimide-tags-$USER 대비책)
    -- 'wildignore' 의 */tmp/* 에 걸려 '' 가 되고, 스냅숏이 '/<이름>' 으로 가서
    -- 쓰지도 못한 채 시작할 때마다 ctags 를 처음부터 다시 만들었다
    return vim.fn.expand(dir, 1) .. '/' .. name
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
  local ct = ctags_cmd()
  if not ct then
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

  -- 목록을 절대경로로 적어 ctags 에 넘긴다
  -- (sed -e 's|^\./||' -e 's|^|<root>/|' 가 하던 일)
  local function write_list(lines)
    local out, n = {}, 0
    for _, line in ipairs(lines) do
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
  end

  -- preset 이면 목록 파일을 그대로 쓴다. 예전에는 여기서도 preset 을 다시
  -- 펼치고(시작할 때 세 번째) indexfiles.sh 를 한 번 더 돌렸다. 목록이 아직
  -- 없을 때만 펼친다 - 없으면 indexfiles.sh 가 git ls-files 로 떨어져 트리
  -- 전체의 ctags 를 만든다.
  if preset_mode(root) then
    if not uv.fs_stat(list_file(root)) then
      materialize(root)
    end
    local snap = preset_snapshot(root)
    if not snap then
      fail(short .. ' ctags: preset 목록을 읽지 못했습니다')
      return
    end
    write_list(snap.lines)
    return
  end
  -- 예전에는 fl | sed | ctags -L - && mv 를 sh -c 한 줄로 묶었다. nvim 이
  -- 죽으면 sh 만 죽고 ctags 는 손자로 살아남는다. 이제 세 단계로 나눈다:
  -- 목록 생성(셸 없이) -> Lua 가 경로를 절대경로로 정리 -> ctags(셸 없이).
  -- 시작할 때 방금 센 목록이면 그대로 쓴다 (filelist).
  filelist(root, 30000, function(o)
    if not o or o.code ~= 0 then
      fail(short .. ' ctags: 파일 목록을 만들지 못했습니다')
      return
    end
    local lines = {}
    for line in (o.stdout or ''):gmatch('[^\n]+') do
      lines[#lines + 1] = line
    end
    write_list(lines)
  end)
end

-- 목록이 바뀌면 ctags(gutentags) 도 따라가게 한다.
--
-- 예전에는 projectfiles 가 '지금 버퍼에 gutentags 가 붙어 있으면'
-- :GutentagsUpdate! 를 불렀다. 트리·quickfix·telescope 에서 +/- 하면 지금
-- 버퍼가 그 창이라 한 번도 돌지 않았고(그 명령은 버퍼 지역이다), 돌더라도
-- 앞의 갱신이 아직 돌면 gutentags 가 'already being updated' 로 버렸다
-- (silent! 라 보이지도 않았다). 그래서 tags 스냅숏은 저장하거나 다시 켤
-- 때까지 지운 파일의 심볼을 답했다 - 색칠과 C-] 의 ctags 대비책이 그걸 본다.
--
--   * 이 루트를 관리하는 버퍼(b:gutentags_root == root)를 찾아 그 버퍼 안에서
--     부른다. '루트 아래 아무 버퍼'가 아니다: 하위 저장소(.git) 안의 버퍼는
--     자기 tags 파일을 갖고 있다.
--   * 그 tags 파일을 갱신하는 중이면 끝난 뒤(User GutentagsUpdated) 한 번 더.
--     몇 번을 +/- 해도 도는 것 하나, 기다리는 것 하나다.
--   * 모드를 고르기 전에 연 버퍼에는 gutentags 가 붙지 않았고 다시 묻지도
--     않는다. 한 번 붙여 본다 (없던 tags 는 generate_on_missing 이 만든다).
--   * gutentags 에서 뗀 큰 트리(우리 ctags 스냅숏)는 여기서 다시 만들지 않는다
--     - 커널 트리에서 수십 초짜리를 +/- 마다 돌릴 수는 없다. 7일마다,
--     :CtagsIndex 로.
--   let g:autoindex_ctags_follow = 0   " 따라가지 않기
local function same_dir(a, b)
  if type(a) ~= 'string' or a == '' then
    return false
  end
  a, b = a:gsub('/+$', ''), b:gsub('/+$', '')
  if a == b then
    return true
  end
  local ra, rb = uv.fs_realpath(a), uv.fs_realpath(b)
  return ra ~= nil and ra == rb
end

-- 큰 트리로 정해 뗀 루트(s.gt 'no')의 버퍼는 붙어 있어도 치지 않는다 (gutentags_flip)
local function gutentags_buf(root)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == '' then
      local ok1, gf = pcall(api.nvim_buf_get_var, b, 'gutentags_files')
      local ok2, gr = pcall(api.nvim_buf_get_var, b, 'gutentags_root')
      if ok1 and type(gf) == 'table' and type(gf.ctags) == 'string'
          and ok2 and s.gt[gr] ~= 'no' and same_dir(gr, root) then
        return b, gf.ctags
      end
    end
  end
end

local function gutentags_running(tf)
  local ok, idx = pcall(vim.fn['gutentags#find_job_index_by_tags_file'], 'ctags', tf)
  return ok and type(idx) == 'number' and idx >= 0
end

-- '<tags>.followed': 이 tags 파일을 목록 전체로 다시 만들게 한(GutentagsUpdate!,
-- 붙이며 새로 만들기) 마지막 때의 목록 상태 열쇠 (stat_key). 그 작업은 이 열쇠
-- 뒤에 목록을 읽으므로, 지금 목록의 열쇠와 같으면 tags 는 이미 지금 목록을
-- 따랐거나 따르는 중이다. 시각이 아니라 열쇠로 본다 - 저장 한 번의 갱신(-s,
-- 파일 하나)은 이것을 쓰지 않으니 '누가 tags 를 고쳤다' 와 섞이지 않는다 (D2).
-- 캐시는 nvim 들이 같이 쓰므로 다른 nvim 이 쓴 것도 보인다.
local function list_key(root)
  local st = uv.fs_stat(list_file(root))
  return st and stat_key(st) or nil
end

local function read_followed(tf)
  local f = io.open(tf .. '.followed', 'r')
  if not f then
    return nil
  end
  local l = f:read('*l')
  f:close()
  return (l and l ~= '') and l or nil
end

local function put_followed(tf, key)
  if not key then
    return -- auto 모드: 견줄 목록 파일이 없다
  end
  local tmp = ('%s.followed.%d.tmp'):format(tf, uv.os_getpid())
  local f = io.open(tmp, 'w')
  if not f then
    return
  end
  f:write(key, '\n')
  f:close()
  if not uv.fs_rename(tmp, tf .. '.followed') then
    pcall(os.remove, tmp)
  end
end

-- preset 을 바꿔 다시 센 판단이 예전과 다르다 (guard_ctags_decide, 열린 과제 4).
-- 예전에는 처음 판단이 세션 내내 남아, 작은 트리로 세어 gutentags 가 붙은 루트를
-- 큰 preset 으로 바꾸면 gutentags 가 큰 목록의 tags 를 통째로 만들고 저장마다
-- 다시 썼다 (재현). 큰 트리로 시작했어도 첫 버퍼에는 세기(비동기) 전에 붙어
-- 있어 같았다 - 그 버퍼도 여기서 뗀다.
--   big = true : 이제 큰 트리다. 그 루트를 s.gt 'no' 로 둔다 - 붙어 있는 버퍼는
--                뗀 것으로 본다: 저장 갱신은 BufWritePre 가, 따라가기는
--                gutentags_buf 가 막는다. 버퍼 변수(b:gutentags_files/_root)는
--                지우지 않는다 - gutentags 가 작업 중에 저장해 줄 세운 갱신이
--                끝날 때 그 변수를 읽는데, 지워져 있으면 빈 경로(= 홈)에서
--                ctags 를 돌린다.
--   big = false: 이제 작은 트리다. 제외 목록에서 빼고, 큰 목록으로 만든 우리
--                스냅숏을 지운다 - 새 목록과 맞지 않고, 크면 크기 가드
--                (autoindex_gutentags_ok)가 다시 떼었다. 붙이는 것은 뒤이은
--                ctags_follow 가 한다 (붙어 있던 버퍼는 그대로 다시 쓰고, 없는
--                tags 는 gutentags 가 새로 만든다).
--                단 제외 목록에 넣은 것이 세기가 아니면(put 이 아니다 - 사용자가
--                넣었거나, 세기보다 먼저 크기 가드가 큰 tags 를 보고 넣었다) 그
--                제외도 s.gt 도 tags 도 그대로 둔다. 예전에는 그것까지 빼고 tags
--                를 지워, gutentags 가 다시 붙어 크기 가드가 막은 큰 tags 를 새로
--                만들고 저장마다 통째로 다시 썼다 (OI4). 세기가 넣었으면 크기
--                가드는 그 뒤로 묻지도 않았다 (제외된 루트는 get_project_root 가
--                거른다) - s.gt 'no' 는 세기(big = true)가 둔 것이다.
gutentags_flip = function(root, big, put)
  if not big and not put then
    if s.ctags_deferred then
      s.ctags_deferred[root] = nil -- 세기가 미뤄 둔 우리 ctags 만들기는 거둔다
    end
    dbg('gutentags 그대로 둠 (preset 을 바꿔 작은 트리지만 제외는 세기가 넣은 것이 아님) '
      .. root)
    return
  end
  for k in pairs(s.gt) do
    if same_dir(k, root) then
      s.gt[k] = big and 'no' or nil
    end
  end
  if big then
    local n = 0
    for _, b in ipairs(api.nvim_list_bufs()) do
      local ok, gr = pcall(api.nvim_buf_get_var, b, 'gutentags_root')
      if ok and type(gr) == 'string' and same_dir(gr, root) then
        s.gt[gr] = 'no'
        n = n + 1
      end
    end
    if n > 0 then
      dbg(('gutentags 뗌 (큰 트리, 붙어 있던 버퍼 %d) %s'):format(n, root))
    end
    return
  end
  local out = {}
  for _, r in ipairs(vim.g.gutentags_exclude_project_root or {}) do
    if r ~= root then
      out[#out + 1] = r
    end
  end
  vim.g.gutentags_exclude_project_root = out
  if s.ctags_deferred then
    s.ctags_deferred[root] = nil
  end
  s.ct_setup[root] = nil
  local tf = ctags_file(root)
  pcall(os.remove, tf)
  pcall(os.remove, tf .. '.followed')
  dbg('gutentags 되붙임 (preset 을 바꿔 작은 트리) ' .. root)
end

-- since: 락을 기다리다 다른 nvim 이 이 nvim 의 목록 변경까지 색인한 것을 본
-- 자리(wait_lock)에서 넘긴다 (그 변경의 시각 - 있다는 것만 본다). 아래 설명 (N4).
-- how: 'force' 면 tags 가 이미 지금 목록을 따랐어도 다시 만든다 (\fR,
-- autoindex_ctags_refresh). 'again' 은 since 의 다시 보기 (아래).
function ctags_follow(root, since, how)
  if cfg('ctags_follow', 1) == 0 or vim.fn.exists('g:loaded_gutentags') == 0 then
    return
  end
  -- 기다렸다 다시 부르는 자리(아래 GutentagsUpdated)도 여기를 지난다
  if not list_ready(root) then
    dbg('ctags follow 건너뜀 (색인하지 않는 모드/목록 없음) ' .. root)
    return
  end
  -- 목록이 없어 파일 수를 미뤄 둔 루트(count_files 의 false)에 목록이 생겼다:
  -- 먼저 센다 - 큰 트리면 gutentags 를 붙이기 전에 떼고 우리 ctags 를 만든다
  -- (R3). 세는 동안 온 따라가기는 세기가 끝난 뒤의 것 하나로 합친다.
  if counted[root] == false or counted[root] == 'counting' then
    if counted[root] == false then
      counted[root] = 'counting'
      local max = cfg('ctags_max_files', 5000)
      count_files(root, function(n)
        counted[root] = true
        guard_ctags_decide(root, max, n)
        ctags_follow(root, since, how)
      end)
    end
    return
  end
  -- s.ct_due 는 따라가기를 실제로 냈거나 이미 된 것을 알았을 때만 지운다 -
  -- 붙지 못했거나 기다리는 중이면 남겨 두어, 다음 갱신이 끝날 때 다시 온다
  local buf, tf = gutentags_buf(root)
  if not buf then
    if s.ct_setup[root] then
      return
    end
    s.ct_setup[root] = true
    local pre = root:gsub('/+$', '') .. '/'
    for _, b in ipairs(api.nvim_list_bufs()) do
      local n = api.nvim_buf_get_name(b)
      if api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == ''
          and n:sub(1, #pre) == pre then
        pcall(api.nvim_buf_call, b, function()
          vim.fn['gutentags#setup_gutentags']()
        end)
        buf, tf = gutentags_buf(root)
        if buf then
          break
        end
      end
    end
    -- 붙지 않았다 (큰 트리, 모드 없음)
    if not buf then
      return
    end
    -- 붙자마자 tags 를 목록 전체로 새로 만들기 시작했다 (generate_on_missing/
    -- _on_new): 그 작업이 지금 목록을 읽는다 - 그것이 이번 따라가기다. 열쇠를
    -- 남긴다: 예전에는 이 갱신이 끝날 때 GutentagsUpdate! 를 한 번 더 내서, 목록이
    -- 없던 프로젝트의 첫 + 에 ctags 가 두 번 돌았다 (열린 과제 3, 재현)
    if gutentags_running(tf) then
      s.ct_due[root] = nil
      put_followed(tf, list_key(root))
      return
    end
  end
  -- 다른 nvim 이 이 nvim 의 목록 변경을 맡아 색인했으면 그 nvim 도 끝나며 같은
  -- tags 파일(캐시는 하나다)을 따라갔다 - 또 만들면 + 하나에 tags 를 통째로 두
  -- 번 만들고, 둘이 겹치면 한쪽의 '<tags>.temp' 를 다른 쪽이 치워 'ctags job
  -- failed' 가 떴다 (N4, 재현). 그래서 since 가 있으면 누가(이 nvim 의 저장
  -- 갱신이든) 그 파일을 만들고 있는 동안은('<tags>.lock', update_tags.sh 가
  -- 쓴다) 끝난 뒤에 다시 본다.
  if since then
    local lk = uv.fs_stat(tf .. '.lock')
    if lk and os.time() - lk.mtime.sec < 600 then
      vim.defer_fn(function() ctags_follow(root, since, how) end, 1000)
      return
    end
  end
  -- 그 tags 를 지금 목록으로 이미 다시 만들었거나 만드는 중이면(누가 했든 -
  -- '<tags>.followed') 또 만들지 않는다. 예전 since 는 tags 파일의 mtime 을 봐서,
  -- 이 nvim 이 기다리는 사이 저장 한 번에 gutentags 가 그 파일 하나만 고쳐 써도
  -- '다른 nvim 이 이미 다시 씀' 으로 건너뛰었다 - 맡은 nvim 에 gutentags 버퍼가
  -- 없으면 더한 파일이 세션 내내 ctags 밖에 남았다 (D2, 재현).
  local key = list_key(root)
  if how ~= 'force' and key and read_followed(tf) == key
      and (gutentags_running(tf) or uv.fs_stat(tf)) then
    s.ct_due[root] = nil
    dbg('ctags follow 건너뜀 (이 목록으로 이미 다시 씀) ' .. root)
    return
  end
  -- 다른 nvim 은 락을 푼 뒤에 따라가기를 낸다 (refresh 의 done()). 그 틈에 본
  -- 것일 수 있으니 1초 뒤 한 번 더 본다. 그래도 아무도 하지 않았으면 - 그
  -- nvim 에 이 루트의 gutentags 버퍼가 없다 - 여기서 만든다. 그래서 wait_lock
  -- 의 부르기를 빼지 않는다.
  if since and how ~= 'again' then
    vim.defer_fn(function() ctags_follow(root, since, 'again') end, 1000)
    return
  end
  if gutentags_running(tf) then
    -- 다시 만들라는 뜻(force)은 기다리는 동안 잃지 않는다
    local had = s.ct_pending[tf]
    if how == 'force' then
      s.ct_pending[tf] = 'force'
    end
    if not had then
      s.ct_pending[tf] = s.ct_pending[tf] or true
      -- 다른 tags 파일의 작업이 끝나도 이 이벤트가 온다: 그때는 다시 보고
      -- 다시 기다린다
      api.nvim_create_autocmd('User', { pattern = 'GutentagsUpdated', once = true,
        callback = function()
          local f = s.ct_pending[tf]
          s.ct_pending[tf] = nil
          vim.schedule(function() ctags_follow(root, nil, f == 'force' and 'force' or nil) end)
        end })
    end
    return
  end
  s.ct_due[root] = nil
  put_followed(tf, key)
  dbg('ctags follow ' .. root .. ' -> ' .. tf)
  pcall(api.nvim_buf_call, buf, function()
    vim.cmd('silent! GutentagsUpdate!')
  end)
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
  local function ask(r)
    local ok, o = pcall(function()
      return vim.system({ prog, '-d', '--result=ctags-mod', pattern },
        { text = true, cwd = r, env = env_for(r) }):wait(3000)
    end)
    if not ok or not o or o.code ~= 0 or not o.stdout or o.stdout == '' then
      return nil
    end
    local items = {}
    for line in o.stdout:gmatch('[^\n]+') do
      local path, lno, text = line:match('^([^\t]+)\t(%d+)\t(.*)$')
      if path then
        items[#items + 1] = {
          name = pattern,
          filename = path:sub(1, 1) == '/' and path or (r .. '/' .. path),
          cmd = tostring(lno),
          kind = 'd',
          user_data = (text or ''):gsub('^%s+', ''),
        }
      end
    end
    return #items > 0 and items or nil
  end
  -- 가장 가까운 색인부터 묻고, 거기서 모르면 바깥 색인으로 올라간다.
  --
  -- 가까운 것이 먼저다: d5_qnx_hyp 처럼 안쪽(kernel/common) 색인만 아는
  -- 트리가 있다. 그러나 거기서 멈추면, 자기 '.tags' 를 가진 중첩 프로젝트
  -- (하위 저장소) 안에서 바깥에만 있는 심볼을 <C-]> 만 '정의를 찾지
  -- 못했습니다' 라고 했다 - \g, 패널, 초록 색칠(sihlindex 'chain')은 다
  -- 찾는데. 찾으면 비용은 그대로고, 못 찾을 때만 바깥 색인마다 global 이
  -- 한 번 는다. 한도는 sihlindex 의 walk_up 과 같다 (4단계, $HOME 에서 멈춤).
  local home = vim.env.HOME
  local function lookup()
    local r = root
    for _ = 1, 4 do
      if not r then
        break
      end
      local items = ask(r)
      if items then
        return items
      end
      if r == home then
        break
      end
      local parent = vim.fs.dirname(r)
      if not parent or parent == r then
        break
      end
      r = scan_root(parent)
    end
  end
  local items = lookup()
  if items or not root then
    return items or vim.NIL
  end
  -- 못 찾았는데 + 로 방금 넣은 파일을 색인에 넣는 중이면(빠른 길, 파일마다
  -- 수십 ms) 잠깐 기다렸다 다시 묻는다. 기다리지 않으면 + 직후의 C-] 가
  -- '정의를 찾지 못했습니다' 였다.
  --
  -- 먼저 지금 DB 에 묻고, 못 찾을 때만 기다린다. 예전에는 묻기 전에 기다려서,
  -- + 가 앞의 갱신(시작 갱신, :GtagsIndexRefresh!, 커널 트리에서 몇 분짜리
  -- 빌드) 뒤에 줄 서 있는 동안 C-]·:tag 가 어느 심볼이든 매번 1.5초씩 멈췄다
  -- (INT3). 그래서 기다리는 것은 지금 실제로 넣고 있거나(s.fast) 곧바로 넣을
  -- 차례인 것(줄 선 요청인데 이 DB 에서 도는 일이 없다)뿐이다. 다른 nvim 의
  -- 락을 기다리는 중이면 언제 풀릴지 모르니 기다리지 않는다. 한 요청에 한 번만
  -- 기다린다 - 시간을 넘기면 그 요청에 적어 두고 다음부터는 바로 답한다.
  --   let g:autoindex_tagfunc_wait_ms = 0   " 기다리지 않기
  local function fast_pending()
    local f = s.fast[root]
    if f then
      return not f.waited and f or nil
    end
    local a = s.refresh_again[root]
    if a and a.added and not a.waited and not s.lock_wait[root] and not busy(root) then
      return a
    end
    return nil
  end
  local wait = tonumber(cfg('tagfunc_wait_ms', 1500)) or 0
  if wait > 0 and fast_pending() then
    if not vim.wait(wait, function() return not fast_pending() end, 10) then
      local t = fast_pending()
      if t then
        t.waited = true
      end
    end
    items = lookup()
  end
  return items or vim.NIL
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

-- 목록 밖 파일의 저장은 ctags 스냅숏에도 들어가지 않는다 (F7).
--
-- gutentags 는 붙은 버퍼를 저장할 때마다 그 파일의 태그를 tags 파일에 덧붙인다
-- (generate_on_write, '-s <파일>'). .tags/files 를 보지 않으므로, - 로 뺀 파일을
-- 고쳐 저장하면 GTAGS 는 건너뛰는데(in_list) ctags 에는 도로 들어가 :tag 와
-- Telescope tags 가 뺀 파일을 내놓았다 - 'ctags 는 목록을 따른다' 가 다음
-- 저장까지만 맞았다. none 으로 바꾼 뒤에도 전에 붙은 버퍼는 그대로라, tags 파일이
-- 없으면 그 저장이 git ls-files 로 트리 전체를 ctags 했다.
-- 버퍼를 떼지는 않는다 - 'tags' 에 든 프로젝트 태그로 거기서도 :tag 가 된다.
-- 그 저장 한 번만 g:gutentags_generate_on_write 를 내려 두고, gutentags 의
-- BufWritePost 뒤에 되돌린다 (그 autocmd 는 버퍼에 붙을 때 만들었으니, 지금
-- 만드는 것이 뒤에 돈다).
local function gutentags_write_ok(path)
  if _G.projectfiles_should_index_file and not _G.projectfiles_should_index_file(path) then
    return false
  end
  local dir = vim.fs.dirname(path)
  local root = s.roots[dir] or scan_root(dir)
  if root and preset_mode(root) and uv.fs_stat(list_file(root)) then
    return in_list(root, path)
  end
  return true
end

api.nvim_create_autocmd('BufWritePre', {
  group = group,
  callback = function(a)
    local prev = vim.g.gutentags_generate_on_write
    if not prev or prev == 0 or cfg('gutentags_guard', 1) == 0 or not enabled()
        or vim.bo[a.buf].buftype ~= '' then
      return
    end
    local ok, gf = pcall(api.nvim_buf_get_var, a.buf, 'gutentags_files')
    local path = a.match ~= '' and vim.fn.fnamemodify(a.match, ':p') or nil
    if not (ok and type(gf) == 'table' and path) then
      return
    end
    -- 큰 트리로 정해 뗀 루트(gutentags_flip)에 붙어 있던 버퍼도 막는다 - 그대로
    -- 두면 저장마다 큰 목록의 tags 를 통째로 다시 썼다 (열린 과제 4)
    local okr, gr = pcall(api.nvim_buf_get_var, a.buf, 'gutentags_root')
    local big = okr and s.gt[gr] == 'no'
    if not big and gutentags_write_ok(path) then
      return
    end
    dbg('gutentags 저장 갱신 막음 (' .. (big and '큰 트리' or '목록 밖/색인하지 않는 모드')
      .. ') ' .. path)
    vim.g.gutentags_generate_on_write = 0
    local back = false
    local function restore()
      if not back then
        back = true
        if vim.g.gutentags_generate_on_write == 0 then
          vim.g.gutentags_generate_on_write = prev
        end
      end
    end
    api.nvim_create_autocmd('BufWritePost', { buffer = a.buf, once = true,
      callback = restore })
    vim.schedule(restore) -- 쓰기가 실패해 BufWritePost 가 오지 않아도
  end,
})

-- 목록이 바뀌었다 (projectfiles). 저장 갱신의 '목록에 있나' 캐시를 버린다 -
-- 파일 상태 열쇠(나노초)로도 잡지만, mtime 을 초 단위로만 적는 파일시스템
-- (일부 NFS/SMB)에서 같은 크기로 다시 쓴 목록은 그것으로 못 알아본다.
api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'ProjectFilesChanged',
  callback = function()
    s.lists = {}
    for root in pairs(s.gt_wait) do
      gt_retry(root)
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
  -- 목록을 따라 다시 만들 수 없는 프로젝트(색인하지 않는 모드, 목록이 없거나
  -- 일부러 비운 것이 아닌 빈 목록)의 tags 는 그대로 둔다 (F4/K3)
  local dir = vim.fs.dirname(vim.fn.fnamemodify(p, ':p'))
  local root = s.roots[dir] or scan_root(dir)
  if root and not list_ready(root) then
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
          with_mode(root, function()
            refresh(root, { why = 'startup', full = true, auto = true })
          end)
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
--
-- 넷째 인자(계약 C3): changes = { added = {절대경로...}, removed = {...} }.
-- 무엇이 바뀌었는지 알면 더한 파일은 곧바로 하나씩 넣고(single-update),
-- 목록이 색인과 같으면 gtags -i 를 건너뛴다. nil 이면 '모른다' - 예전처럼
-- 목록 전체로 gtags -i.
--
-- 강제 갱신은 잃어버리지 않는다: 다른 nvim 이 락을 쥐고 있으면 풀릴 때까지
-- 기다리고(wait_lock), 디스크에 표지를 남겨 이 nvim 이 그 전에 닫혀도 다음
-- 시작이 축소 방지를 건너 반영한다 (marker_path).
function _G.autoindex_refresh(root, force, why, changes)
  if not (root and root ~= '') then
    return false
  end
  if not enabled() then
    return false
  end
  force = force ~= false
  -- 목록이 바뀌었다: 저장 갱신의 '목록에 있나' 도 다시 본다
  s.lists[root] = nil
  -- 색인하지 않는 모드(none/미설정)면 여기서 끝낸다 - 표지도 남기지 않는다.
  -- true 를 돌려준다: false 면 projectfiles 가 :GtagsIndexRefresh! 로 다시
  -- 부르는데, 그쪽은 사람이 부른 것으로 보여 막지 않는다.
  if type(_G.projectfiles_should_index) == 'function'
      and not _G.projectfiles_should_index(root) then
    dbg('autoindex_refresh 건너뜀 (색인하지 않는 모드) ' .. root)
    return true
  end
  local added
  if type(changes) == 'table' and type(changes.added) == 'table' then
    for _, p in ipairs(changes.added) do
      if type(p) == 'string' and p ~= '' then
        added = added or {}
        added[p] = true
      end
    end
  end
  local req = { why = why or 'list changed', force = force, list = true,
    auto = true, full = type(changes) ~= 'table', added = added }
  s.ct_due[root] = true -- 이 변경이 끝나면 ctags 도 따라간다 (ctags_follow)
  -- 그 시각: 락을 기다리다 다른 nvim 이 맡아 끝냈을 때 넘기는 since (wait_lock).
  -- 건너뛸지는 시각이 아니라 '<tags>.followed' 의 목록 열쇠로 정한다 (D2)
  local sec, usec = uv.gettimeofday()
  s.list_at[root] = sec + (usec or 0) / 1e6
  -- preset 을 바꿨으면 파일 수를 다시 센다 (열린 과제 4). 처음 판단(작은 트리 ->
  -- gutentags, 큰 트리 -> 우리 스냅숏)이 세션 내내 남아, 작은 preset 에서 큰
  -- preset 으로 바꿔도 gutentags 가 큰 목록의 tags 를 저장마다 다시 썼다. 세기는
  -- 이 갱신이 끝날 때의 ctags_follow 나 다음 파일 열기(guard_ctags)가 한다 -
  -- 그때는 새 목록이 있다. 뒤집는 것은 guard_ctags_decide (gutentags_flip).
  local cm = s.count_mode[root]
  if counted[root] == true and cm and cm.mode ~= nil
      and mode_now(root) ~= cm.mode then
    dbg(('preset 바뀜 (%s -> %s) - 파일 수를 다시 센다 %s'):format(
      tostring(cm.mode), tostring(mode_now(root)), root))
    counted[root] = false
    s.switched[root] = true
  end
  if force then
    write_marker(root, req.full, req.why)
  end
  refresh(root, req)
  return true
end

-- 이 루트의 tags(gutentags)를 지금 목록에 맞춘다. projectfiles 가 직접
-- :GutentagsUpdate! 를 부르던 자리를 대신한다 (위 ctags_follow 설명).
-- 목록이 그대로여도 다시 만든다(force) - \fR 이 낡은 tags 를 고치는 길이다.
function _G.autoindex_ctags_refresh(root)
  if root and root ~= '' then
    ctags_follow(root, nil, 'force')
  end
end

-- 파일 몇 개를 이 nvim 의 단일 갱신 큐로 넣는다 (계약 K1). paths: 절대경로 목록.
--
-- projectfiles 의 자체 큐는 이 쪽의 gtags -i 도 락도 몰랐다. 그 큐가 넣은 파일을
-- 그때 돌던 gtags -i(예전 목록)가 끝나며 도로 지웠고, 다른 nvim 의 DB 에도 일꾼
-- 둘이 붙었다 (F1/INT1). 이제 projectfiles 는 목록을 바꾼 것은 autoindex_refresh
-- 의 빠른 길로, 이미 목록에 있는 파일을 다시 넣을 것만 이리로 보낸다.
--   * 저장 갱신과 같은 큐(drain): 한 DB 에 하나씩, 락 아래서. 이 nvim 의 갱신·
--     빌드가 돌면 그 뒤에, 다른 nvim 이 락을 쥐었으면 풀린 뒤에 (wait_lock) -
--     죽은 nvim 이 남긴 고아 gtags -i 가 아직 돌아도 그 뒤에 (F5).
--   * 넣은 파일이 DB 에 새로 들어오면 사본(files.indexed)도 따라 고친다
--     (copy_follow) - 다음 + 의 빠른 길이 살아 있다.
--   * 줄 선 채로 이 nvim 이 닫히면 표지로 남긴다 (아래 VimLeavePre).
--   * 색인하지 않는 모드면 아무 것도 하지 않고, 목록 밖 파일은 넣지 않는다
--     (GTAGS == 목록). 둘 다 '맡았다'(true)로 답한다 - false 면 projectfiles 가
--     자체 큐로 다시 넣는다.
function _G.autoindex_single_update(root, paths)
  if not (root and root ~= '' and enabled() and type(paths) == 'table') then
    return false
  end
  if type(_G.projectfiles_should_index) == 'function'
      and not _G.projectfiles_should_index(root) then
    dbg('single_update 건너뜀 (색인하지 않는 모드) ' .. root)
    return true
  end
  for _, p in ipairs(paths) do
    if type(p) == 'string' and p ~= '' then
      if p:sub(1, 1) ~= '/' then
        p = root .. '/' .. p
      end
      if in_list(root, p) then
        s.pending[root] = s.pending[root] or {}
        s.pending[root][p] = true
      else
        dbg('single_update: 목록 밖이라 건너뜀 ' .. p)
      end
    end
  end
  drain(root)
  return true
end

-- 넣지 못한 저장 갱신을 남긴 채 닫힐 때 (계약 K1 의 '같은 표지 규칙').
--
-- 저장 갱신의 큐는 이 nvim 의 기억에만 있다. 그 앞의 갱신이 돌던 중이거나 다른
-- nvim 의 락을 기다리던 중에 닫으면 그대로 사라졌다. preset 이면 표지를 남긴다:
-- 락을 쥔 nvim 이 끝날 때 그것을 보고 한 번 더, 아니면 다음 시작이 목록 전체로
-- gtags -i 를 돈다 (저장한 파일은 시각이 바뀌어 다시 읽힌다). full 이어야 한다 -
-- 목록은 그대로라 '바뀐 것만' 으로는 아무 것도 하지 않는다. auto 모드에는 남기지
-- 않는다: 표지는 축소 방지를 건너뛰게 하고, 시작 갱신이 어차피 다시 본다.
api.nvim_create_autocmd('VimLeavePre', {
  group = api.nvim_create_augroup('AutoIndexPendingMarker', { clear = true }),
  callback = function()
    for root, q in pairs(s.pending) do
      if next(q) and preset_mode(root) then
        pcall(write_marker, root, true, '저장 갱신 남음')
      end
    end
  end,
})

api.nvim_create_user_command('GtagsIndexRefresh', function(o)
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    if root then
      -- ! 는 '목록을 따르라' 는 뜻이라, 다른 nvim 이 색인 중이면 기다렸다 한다
      if o.bang then
        write_marker(root, true, 'manual!')
      end
      refresh(root, { why = o.bang and 'manual!' or 'manual', force = o.bang,
        full = true, auto = false })
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
  for root in pairs(s.refreshing) do
    lines[#lines + 1] = 'refreshing ' .. root
  end
  for root in pairs(s.ctags_building) do
    lines[#lines + 1] = 'building ctags ' .. root
  end
  for root, n in pairs(s.lock_wait) do
    lines[#lines + 1] = ('waiting for another nvim (%d) %s'):format(n, root)
  end
  for root, r in pairs(s.refresh_again) do
    lines[#lines + 1] = ('queued refresh%s %s'):format(r.force and '!' or '', root)
  end
  for root, q in pairs(s.pending) do
    local n = vim.tbl_count(q)
    if n > 0 then
      lines[#lines + 1] = ('queued single-update (%d) %s'):format(n, root)
    end
  end
  for root, n in pairs(s.torn) do
    lines[#lines + 1] = ('list changing while read, retry %d %s'):format(n, root)
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
      local m = read_marker(root)
      if m then
        lines[#lines + 1] = 'pending: ' .. m:gsub('\t', ' ')
      end
      local cf = ctags_file(root)
      local st = uv.fs_stat(cf)
      lines[#lines + 1] = 'ctags: ' .. cf ..
          (st and string.format(' (%.0f MB)', st.size / 1048576) or ' (없음)')
    end
    lines[#lines + 1] = 'tagfunc: ' .. (vim.o.tagfunc ~= '' and vim.o.tagfunc or '(unset)')
    vim.notify(table.concat(lines, '\n'))
  end)
end, { desc = 'Show what the GTAGS auto-indexer is doing' })
