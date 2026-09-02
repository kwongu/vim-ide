-- autoindex.lua - keep the GTAGS index up to date by itself, the way
-- vim-gutentags does it for ctags.
--
-- What it does
--   * saving a source file updates GTAGS for that file only
--     ('global --single-update', a few milliseconds)
--   * opening a source file in a project that has no GTAGS yet starts one
--     background build (once per project per session)
--   * :GtagsIndex        rebuild the whole index in the background
--   * :GtagsIndexUpdate  update the index for the current file now
--   * :GtagsIndexStatus  what is running / which database is in use
--
-- Which files are indexed is decided by ~/.local/bin/indexfiles.sh, so
-- ctags (gutentags) and gtags always agree:
--     .indexfiles  ->  cscope.files (F2/mktags.sh)  ->  git ls-files  ->  find
-- Drop a '.indexfiles' in a project root to index exactly what you want.
--
-- Options (.vimrc)
--   g:autoindex_gtags        1: enable everything here      (default 1)
--   g:autoindex_auto_create  1: build a missing index       (default 1)
--   g:autoindex_notify       1: report build start/end      (default 1)
--   g:autoindex_ctags_max_files  projects with more files than this are
--                            left to gtags only (default 5000, 0 = no limit)

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

local s = {
  roots = {},     -- dir -> gtags root ('' = none, only cached when found)
  building = {},  -- root -> true while a full build runs
  tried = {},     -- root -> true once an automatic build was started
  pending = {},   -- root -> { path = true } queued single updates
  updating = {},  -- root -> true while a single update runs
}

local function notify(msg, level)
  if cfg('notify', 1) ~= 0 then
    vim.notify('autoindex: ' .. msg, level or vim.log.levels.INFO)
  end
end

-- the GTAGS root above `dir`, or nil (cached; misses are not cached so a
-- freshly built index is picked up right away)
local function gtags_root(dir, cb)
  local hit = s.roots[dir]
  if hit then
    cb(hit)
    return
  end
  local prog = global_cmd()
  if not prog then
    cb(nil)
    return
  end
  local ok = pcall(vim.system, { prog, '-p' }, { text = true, cwd = dir },
    function(o)
      vim.schedule(function()
        local root = (o.stdout or ''):match('^[^\n]*') or ''
        if root ~= '' and uv.fs_stat(root .. '/GTAGS') then
          s.roots[dir] = root
          cb(root)
        else
          cb(nil)
        end
      end)
    end)
  if not ok then
    cb(nil)
  end
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
local function build(root, why)
  if not enabled() or s.building[root] then
    return
  end
  local gt, fl = gtags_cmd(), filelist_cmd()
  if not gt or not fl then
    notify('gtags 또는 indexfiles.sh 를 찾을 수 없습니다', vim.log.levels.WARN)
    return
  end
  s.building[root] = true
  notify('indexing ' .. vim.fn.fnamemodify(root, ':~') ..
    (why and (' (' .. why .. ')') or '') .. ' …')
  local t0 = uv.now()
  -- Build into a temporary database and move it in when it is complete:
  -- writing GTAGS in place would make every query in the meantime fail
  -- with "GTAGS seems corrupted".
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local cmd = { 'sh', '-c', vim.fn.shellescape(fl) .. ' | ' ..
    vim.fn.shellescape(gt) .. ' -f - ' .. vim.fn.shellescape(tmp) ..
    ' && mv -f ' .. vim.fn.shellescape(tmp) .. '/GTAGS ' ..
    vim.fn.shellescape(tmp) .. '/GRTAGS ' .. vim.fn.shellescape(tmp) ..
    '/GPATH ' .. vim.fn.shellescape(root) .. '/' }
  local ok = pcall(vim.system, cmd, { text = true, cwd = root }, function(o)
    vim.schedule(function()
      s.building[root] = nil
      s.roots = {} -- a new database may have appeared above other dirs too
      pcall(vim.fn.delete, tmp, 'rf')
      if o.code == 0 then
        notify(string.format('%s indexed in %.1fs',
          vim.fn.fnamemodify(root, ':~'), (uv.now() - t0) / 1000))
      else
        notify('indexing failed: ' ..
          ((o.stderr or ''):match('^[^\n]*') or ('rc=' .. tostring(o.code))),
          vim.log.levels.WARN)
      end
    end)
  end)
  if not ok then
    s.building[root] = nil
  end
end

-- ---------------------------------------------------------------------------
-- incremental update of one file
-- ---------------------------------------------------------------------------
local function drain(root)
  if s.updating[root] or s.building[root] then
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
  local ok = pcall(vim.system, { prog, '--single-update', rel },
    { text = true, cwd = root }, function()
      vim.schedule(function()
        s.updating[root] = nil
        drain(root)
      end)
    end)
  if not ok then
    s.updating[root] = nil
  end
end

local function update_file(path)
  if not (enabled() and indexed_file(path)) then
    return
  end
  gtags_root(vim.fs.dirname(path), function(root)
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
  notify(string.format(
    '%s: %s files - ctags 색인은 건너뜁니다(gtags 로 색인). ' ..
    '원하면 g:autoindex_ctags_max_files 를 올리거나 .indexfiles 로 범위를 줄이세요',
    vim.fn.fnamemodify(root, ':~'), n and tostring(n) or 'many'))
end

-- ---------------------------------------------------------------------------
-- autocmds and commands
-- ---------------------------------------------------------------------------
local group = api.nvim_create_augroup('AutoIndexGtags', { clear = true })

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

api.nvim_create_user_command('GtagsIndex', function()
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    build(root or marker_root(dir) or dir, 'manual')
  end)
end, { desc = 'Rebuild the GTAGS index of this project in the background' })

api.nvim_create_user_command('GtagsIndexUpdate', function()
  local path = api.nvim_buf_get_name(0)
  if path == '' then
    return
  end
  update_file(vim.fn.fnamemodify(path, ':p'))
end, { desc = 'Update the GTAGS index for the current file' })

api.nvim_create_user_command('GtagsIndexStatus', function()
  local lines = {}
  for root in pairs(s.building) do
    lines[#lines + 1] = 'building ' .. root
  end
  for root in pairs(s.updating) do
    lines[#lines + 1] = 'updating ' .. root
  end
  local path = api.nvim_buf_get_name(0)
  local dir = path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  gtags_root(dir, function(root)
    lines[#lines + 1] = 'database: ' .. (root or '(none - :GtagsIndex)')
    lines[#lines + 1] = 'file list: ' .. (filelist_cmd() or '(indexfiles.sh missing)')
    vim.notify(table.concat(lines, '\n'))
  end)
end, { desc = 'Show what the GTAGS auto-indexer is doing' })
