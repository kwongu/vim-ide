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

-- the same extensions mktags.sh and indexfiles.sh use
local INDEXED = {}
for e in ('c h cpp cc s S dts dtsi reg'):gmatch('%S+') do
  INDEXED[e] = true
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

-- nearest directory at or above `dir` that holds a database
local function scan_root(dir)
  local d = dir
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

local function indexed_file(path)
  local ext = path:match('%.([%w_]+)$')
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
  local ok = pcall(vim.system,
    { 'sh', '-c', vim.fn.shellescape(prog) .. ' -P "" 2>/dev/null | wc -l' },
    { text = true, cwd = root, env = env_for(root) }, function(o)
      vim.schedule(function()
        cb(tonumber(((o.stdout or ''):gsub('%s', ''))) or 0)
      end)
    end)
  if not ok then
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
  s.building[root] = true
  local short = vim.fn.fnamemodify(root, ':~')
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
    pcall(vim.fn.delete, tmp, 'rf')
    if msg then
      notify(msg, vim.log.levels.WARN)
    end
  end

  -- 3. gtags over the file list, then move the finished database in
  local function run_gtags(n)
    local dest = dbpath(root)
    vim.fn.mkdir(dest, 'p')
    local cmd = { 'sh', '-c', vim.fn.shellescape(gt) .. ' -f ' ..
      vim.fn.shellescape(list) .. ' ' .. vim.fn.shellescape(tmp) ..
      ' && mv -f ' .. vim.fn.shellescape(tmp) .. '/GTAGS ' ..
      vim.fn.shellescape(tmp) .. '/GRTAGS ' .. vim.fn.shellescape(tmp) ..
      '/GPATH ' .. vim.fn.shellescape(dest) .. '/' }
    local ok = pcall(vim.system, cmd,
      { text = true, cwd = root, env = { GTAGSROOT = root, GTAGSDBPATH = tmp } },
      function(o)
      vim.schedule(function()
        s.building[root] = nil
        s.roots = {} -- a new database may have appeared above other dirs too
        pcall(vim.fn.delete, tmp, 'rf')
        git_exclude(root)
        -- files saved while the build ran were queued and skipped: flush them
        drain(root)
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
  local ok = pcall(vim.system,
    { 'sh', '-c', vim.fn.shellescape(fl) .. ' > ' ..
      vim.fn.shellescape(list) .. ' && wc -l < ' .. vim.fn.shellescape(list) },
    { text = true, cwd = root }, function(o)
      vim.schedule(function()
        local n = tonumber(((o.stdout or ''):gsub('%s', ''))) or 0
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
local function refresh(root, why)
  if not enabled() or s.building[root] or s.refreshing[root] then
    return
  end
  local gt, fl = gtags_cmd(), filelist_cmd()
  if not gt or not fl then
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
    pcall(vim.fn.delete, tmp, 'rf')
    drain(root)
    if msg then
      notify(msg, level)
    end
  end

  local function run_incremental(n)
    local cmd = { 'sh', '-c', vim.fn.shellescape(gt) .. ' -i -f ' ..
      vim.fn.shellescape(list) .. ' ' .. vim.fn.shellescape(dbpath(root)) }
    local ok = pcall(vim.system, cmd,
      { text = true, cwd = root, env = env_for(root) }, function(o)
        vim.schedule(function()
          local secs = (uv.now() - t0) / 1000
          if o.code ~= 0 then
            done(short .. ' 색인 갱신 실패: ' ..
              ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))),
              vim.log.levels.WARN)
          elseif secs > 3 then
            -- small projects finish before anyone notices; stay quiet there
            done(string.format('%s 색인 갱신 완료 (%d files, %.1fs%s)', short, n,
              secs, why and (', ' .. why) or ''))
          else
            done(nil)
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

  local ok = pcall(vim.system,
    { 'sh', '-c', vim.fn.shellescape(fl) .. ' > ' .. vim.fn.shellescape(list) ..
      ' && wc -l < ' .. vim.fn.shellescape(list) },
    { text = true, cwd = root, env = env_for(root) }, function(o)
      vim.schedule(function()
        local n = tonumber(((o.stdout or ''):gsub('%s', ''))) or 0
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
  local ok = pcall(vim.system, { prog, '--single-update', rel },
    { text = true, cwd = root, env = env_for(root) }, function(o)
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

local function update_file(path)
  if not (enabled() and indexed_file(path)) then
    dbg('update_file ignored ' .. path)
    return
  end
  gtags_root(vim.fs.dirname(path), function(root)
    dbg('update_file ' .. path .. ' root=' .. tostring(root))
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
      build(mroot, 'no GTAGS yet')
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

-- number of files the project would index, or nil if counting took too long
local function count_files(root)
  local fl = filelist_cmd()
  if not fl then
    return nil
  end
  local ok, o = pcall(function()
    return vim.system({ 'sh', '-c', vim.fn.shellescape(fl) .. ' | wc -l' },
      { text = true, cwd = root }):wait(1500)
  end)
  if not ok or not o or o.code ~= 0 then
    return nil
  end
  return tonumber((o.stdout or ''):match('%d+'))
end

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
  local n = count_files(root)
  if n ~= nil and n <= max then
    return
  end
  local list = vim.g.gutentags_exclude_project_root or {}
  for _, r in ipairs(list) do
    if r == root then
      return
    end
  end
  table.insert(list, root)
  vim.g.gutentags_exclude_project_root = list
  -- keep this on one line: a wrapped message means a hit-enter prompt at
  -- every start in a narrow terminal
  notify(string.format('%s: %s files - ctags 는 여기서 직접 만듭니다',
    vim.fn.fnamemodify(root, ':~'), n and tostring(n) or 'many'))
  if cfg('ctags', 1) ~= 0 and not s.ctags_tried[root] then
    local have = ctags_apply(root)
    if not have or ctags_stale(root) then
      s.ctags_tried[root] = true
      ctags_build(root, have and '오래됨' or
        (n and (n .. ' files') or 'big tree'))
    end
  end
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
  if not uv.fs_stat(file) then
    return false
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
  s.ctags_building[root] = true
  local short = vim.fn.fnamemodify(root, ':~')
  local file = ctags_file(root)
  vim.fn.mkdir(vim.fs.dirname(file), 'p')
  notify('ctags 색인 생성 중(백그라운드): ' .. short ..
    (why and (' - ' .. why) or ''))
  local t0 = uv.now()
  local tmp = file .. '.building'
  -- '--excmd=number' drops the search pattern from every entry (~30% smaller,
  -- 0.88 GB instead of 1.3 GB on a 69k-file kernel tree); '--tag-relative=never'
  -- with an absolute file list keeps the paths valid from a cache directory.
  local sh = vim.fn.shellescape(fl) .. " | sed -e 's|^\\./||' -e 's|^|" ..
    root .. "/|' | " .. vim.fn.shellescape(ct) .. ' -f ' ..
    vim.fn.shellescape(tmp) .. ' -L - ' ..
    cfg('ctags_args', '--fields=+n --excmd=number') ..
    ' --tag-relative=never 2>/dev/null && mv -f ' .. vim.fn.shellescape(tmp) ..
    ' ' .. vim.fn.shellescape(file)
  local ok = pcall(vim.system, { 'sh', '-c', sh },
    { text = true, cwd = root }, function(o)
      vim.schedule(function()
        s.ctags_building[root] = nil
        if o.code ~= 0 then
          pcall(vim.fn.delete, tmp)
          notify(short .. ' ctags 색인 실패: ' ..
            ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))),
            vim.log.levels.WARN)
          return
        end
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
    s.ctags_building[root] = nil
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
        build(mroot, 'no GTAGS yet')
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
          refresh(root, 'startup')
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
        build(m, 'startup')
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

api.nvim_create_user_command('GtagsIndexUpdate', function()
  local path = api.nvim_buf_get_name(0)
  if path == '' then
    return
  end
  update_file(vim.fn.fnamemodify(path, ':p'))
end, { desc = 'Update the GTAGS index for the current file' })

api.nvim_create_user_command('GtagsIndexRefresh', function()
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    if root then
      refresh(root, 'manual')
    else
      notify('이 프로젝트에는 색인이 없습니다 (:GtagsIndex)', vim.log.levels.WARN)
    end
  end)
end, { desc = 'Incrementally refresh the GTAGS index of this project' })

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
