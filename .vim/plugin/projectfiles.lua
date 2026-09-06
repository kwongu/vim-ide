-- projectfiles.lua - decide WHICH files get indexed, and show them.
--
-- Two modes:
--   auto    the whole project, the way indexfiles.sh sees it (git ls-files,
--           cscope.files, find). This is what happens with no preset.
--   preset  only the files and directories of a named preset. A preset is a
--           list of project-relative paths, so the same preset can be reused
--           in another checkout: entries that do not exist there are skipped.
--
-- Where presets live
--   ~/.local/share/nvim/vim-ide/presets/   mine, written by every save
--   <vim-ide>/.vim/presets/                shared: kept in the vim-ide
--                                          repository, so a 'git pull' on
--                                          another machine (Linux) brings
--                                          them along
-- Both are listed; my copy wins when a name exists in both.
-- ':ProjectFilesPresetShare <name>' copies one into the repository (commit
-- and push it to hand it to the other machines).
--
-- The list is materialised as '<root>/.tags/files', which indexfiles.sh reads
-- before anything else, so gtags (autoindex.lua) and ctags (gutentags) both
-- index exactly the files in the view - and adding or removing one reindexes
-- straight away.
--
-- Commands
--   :ProjectFiles              find an indexed file and open it (telescope)
--   :ProjectFilesAdd [path]    add a file or directory (default: this buffer)
--   :ProjectFilesRemove [path] remove one
--   :ProjectFilesPreset [name] switch to a preset ('' = auto mode); no
--                              argument lists what there is
--   :ProjectFilesSave <name>   save the current entries as a preset
--   :ProjectFilesPresetShare [name]
--                              copy a preset into vim-ide (shared with the
--                              other machines after a commit/push)
--   :ProjectFilesReindex       rebuild the index for the current list
--
-- In a picker
--   <CR> take the entry     <Tab> several at once
--   ^a   add files (find)   ^d remove from the list, or delete a preset
--
-- Options (.vimrc)
--   g:projectfiles_preset      preset to use when a project has none yet
--   g:projectfiles_shared_presets
--                              where the shared presets are ('' disables
--                              them; default '<vim-ide>/.vim/presets')
--   g:projectfiles_width       view width (default: the context width)
--   g:projectfiles_height      view height in its column (default 12)
--   g:projectfiles_exts        indexed extensions (default as indexfiles.sh)

if vim.g.loaded_projectfiles then
  return
end
vim.g.loaded_projectfiles = 1

if vim.fn.has('nvim-0.10') == 0 then
  return
end

local api = vim.api
local uv = vim.uv

local function cfg(name, default)
  local v = vim.g['projectfiles_' .. name]
  if v == nil or v == '' then
    return default
  end
  return v
end

local EXT = {}
for e in tostring(cfg('exts', 'c h cpp cc s S dts dtsi reg')):gmatch('%S+') do
  EXT[e] = true
end

local s = {
  win = nil,
  buf = nil,
  rows = {},       -- line -> { path = , entry = }
  cache = {},      -- root -> { files = {...}, entries = {...}, preset = }
}

local group = api.nvim_create_augroup('ProjectFiles', { clear = true })

local function notify(msg, level)
  vim.notify('ProjectFiles: ' .. msg, level or vim.log.levels.INFO)
end

-- ---------------------------------------------------------------------------
-- project root and storage
-- ---------------------------------------------------------------------------
local function dbdir()
  local d = vim.g.autoindex_dbdir
  if d == nil then
    d = '.tags'
  end
  if d == '' or d == '.' then
    return nil
  end
  return (tostring(d):gsub('/+$', ''))
end

-- the same root autoindex.lua works with: a database above us, else a marker
local function root_of(path)
  local dir = path and path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  local d, hidden = dir, dbdir()
  while d and d ~= '' do
    if (hidden and uv.fs_stat(d .. '/' .. hidden .. '/GTAGS'))
        or uv.fs_stat(d .. '/GTAGS') then
      return d
    end
    local parent = vim.fs.dirname(d)
    if not parent or parent == d then
      break
    end
    d = parent
  end
  local found = vim.fs.find({ '.git', '.project', '.root' },
    { path = dir, upward = true })[1]
  return found and vim.fs.dirname(found) or vim.fn.getcwd()
end

local function cur_root()
  local name = api.nvim_buf_get_name(0)
  if name == '' or vim.bo.buftype ~= '' then
    return root_of(nil)
  end
  return root_of(name)
end

local function presets_dir()
  local d = vim.fn.stdpath('data') .. '/vim-ide/presets'
  vim.fn.mkdir(d, 'p')
  return d
end

-- only '~' and '$VAR' need expanding: vim.fn.expand() treats the rest of a
-- path as a file pattern and answers '' for anything it does not like
local function expand_dir(p)
  p = tostring(p or '')
  if p:sub(1, 1) == '~' or p:find('%$') then
    p = vim.fn.expand(p)
  end
  return (p:gsub('/+$', ''))
end

-- Presets that travel WITH vim-ide ('<vim-ide>/.vim/presets'). '~/.vim' is a
-- symlink into '~/.vim-ide' (install.sh), so a checkout on another machine -
-- the Linux box - sees the same presets with nothing to copy. A preset is a
-- list of project-relative paths, so it applies to any checkout of the same
-- tree. The writable copy in stdpath('data') shadows the shared one, so
-- saving over a shared preset stays local until ':ProjectFilesPresetShare'
-- puts it back into the repository.
-- where the shared presets could be, best first: next to this very file
-- (realpath, so the '~/.vim' symlink resolves to the vim-ide checkout - that
-- is the copy git tracks), then the usual install locations
local function shared_cands()
  local src = debug.getinfo(1, 'S').source:gsub('^@', '')
  local here = uv.fs_realpath(src) or src
  return {
    vim.fs.dirname(vim.fs.dirname(here)) .. '/presets', -- <...>/.vim/presets
    expand_dir('~/.vim/presets'),
    expand_dir('~/.vim-ide/.vim/presets'),
  }
end

-- create = this is a write ('ProjectFilesPresetShare'): make the directory
-- if it is not there yet. Returns nil when sharing is off
-- (g:projectfiles_shared_presets = '') - that answer is never overridden.
local function shared_dir(create)
  local o = vim.g.projectfiles_shared_presets
  if o ~= nil then
    local p = expand_dir(o)
    if p == '' then
      return nil -- explicitly disabled
    end
    if create then
      pcall(vim.fn.mkdir, p, 'p') -- mkdir() raises; the caller checks fs_stat
    end
    local st = uv.fs_stat(p)
    return (st and st.type == 'directory') and p or nil
  end
  local cands = shared_cands()
  for _, c in ipairs(cands) do
    local st = uv.fs_stat(c)
    if st and st.type == 'directory' then
      return c
    end
  end
  if create then
    pcall(vim.fn.mkdir, cands[1], 'p')
    local st = uv.fs_stat(cands[1])
    return (st and st.type == 'directory') and cands[1] or nil
  end
  return nil
end

-- The file name is the sanitised preset name, but a preset dropped into the
-- shared directory by hand may carry any name; open that one as it is, as
-- long as it cannot climb out of the directory.
local function preset_file(dir, name)
  if not name:find('/') and name ~= '.' and name ~= '..' then
    local exact = dir .. '/' .. name .. '.json'
    if uv.fs_stat(exact) then
      return exact
    end
  end
  return dir .. '/' .. name:gsub('[^%w%-_.]', '_') .. '.json'
end

local function preset_path(name) -- my own copy: what a save writes
  return preset_file(presets_dir(), name)
end

local function shared_path(name) -- the copy vim-ide carries, if there is one
  local d = shared_dir()
  return d and preset_file(d, name) or nil
end

-- scandir, not glob(): glob() can miss a preset written moments ago in this
-- same session (and it honours 'wildignore'), and a save has to show up in
-- the list straight away
local function json_names(dir)
  local out = {}
  local h = dir and uv.fs_scandir(dir)
  if not h then
    return out
  end
  while true do
    local n = uv.fs_scandir_next(h)
    if not n then
      break
    end
    local base = n:match('^(.+)%.json$')
    -- glob() skipped dotfiles; scandir does not. '._default.json'
    -- (an AppleDouble sidecar) is not a preset.
    if base and base:sub(1, 1) ~= '.' then
      out[#out + 1] = base
    end
  end
  return out
end

local function preset_list()
  local seen, out = {}, {}
  for _, d in ipairs({ presets_dir(), shared_dir() }) do
    for _, n in ipairs(json_names(d)) do
      if not seen[n] then
        seen[n] = true
        out[#out + 1] = n
      end
    end
  end
  table.sort(out)
  return out
end

local function read_preset_file(f)
  if not f or not uv.fs_stat(f) then
    return nil
  end
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(f), '\n'))
  end)
  if not ok or type(data) ~= 'table' or type(data.entries) ~= 'table' then
    return nil
  end
  return data
end

local function preset_read(name)
  return read_preset_file(preset_path(name))
      or read_preset_file(shared_path(name))
end

-- one entry per line, keys in a fixed order: a preset kept in git should
-- produce a readable diff when a file is added or removed
local function encode_preset(name, entries)
  local out = { '{', '  "name": ' .. vim.json.encode(name) .. ',',
    '  "entries": [' }
  for i, e in ipairs(entries) do
    out[#out + 1] = ('    {"kind": %s, "path": %s}%s'):format(
      vim.json.encode(e.kind or 'file'), vim.json.encode(e.path or ''),
      i < #entries and ',' or '')
  end
  out[#out + 1] = '  ]'
  out[#out + 1] = '}'
  return out
end

-- writefile() answers -1 instead of throwing, so pcall alone would call a
-- failed write a success and quietly lose the preset
local function write_json(f, lines)
  local ok, ret = pcall(vim.fn.writefile, lines, f)
  return ok and ret == 0
end

local function preset_write(name, entries)
  local f = preset_path(name)
  if not write_json(f, encode_preset(name, entries)) then
    notify('preset 을 저장하지 못했습니다: ' .. f, vim.log.levels.ERROR)
    return false
  end
  return true
end

-- which preset this project uses ('' = auto mode)
local function active_file(root)
  local d = dbdir() or '.tags'
  return root .. '/' .. d .. '/preset'
end

local function active_preset(root)
  local f = active_file(root)
  if uv.fs_stat(f) then
    local l = (vim.fn.readfile(f)[1] or ''):gsub('%s+$', '')
    if l ~= '' then
      return l
    end
    return nil -- explicit auto mode
  end
  local d = cfg('preset', nil)
  return d and tostring(d) or nil
end

local function set_active(root, name)
  local f = active_file(root)
  vim.fn.mkdir(vim.fs.dirname(f), 'p')
  pcall(vim.fn.writefile, { name or '' }, f)
end

-- ---------------------------------------------------------------------------
-- expanding a preset into a file list
-- ---------------------------------------------------------------------------
local function indexed(path)
  local e = path:match('%.([%w_]+)$')
  return e ~= nil and EXT[e] == true
end

local function rel_to(root, path)
  local p = vim.fn.fnamemodify(path, ':p'):gsub('/+$', '')
  if p:sub(1, #root + 1) == root .. '/' then
    return p:sub(#root + 2)
  end
  return p
end

-- files of one entry, relative to root
local function expand_entry(root, entry)
  local abs = entry.path:sub(1, 1) == '/' and entry.path
      or (root .. '/' .. entry.path)
  local st = uv.fs_stat(abs)
  if not st then
    return {}, false -- not in this project: skipped, not an error
  end
  if st.type == 'file' then
    return indexed(abs) and { rel_to(root, abs) } or {}, true
  end
  local out = {}
  local names = {}
  for e in pairs(EXT) do
    names[#names + 1] = "-name '*." .. e .. "'"
  end
  local cmd = "find " .. vim.fn.shellescape(abs) ..
      " \\( -name .git -o -name .tags -o -name node_modules \\) -prune -o " ..
      " -type f \\( " .. table.concat(names, ' -o ') .. " \\) -print 2>/dev/null"
  for _, l in ipairs(vim.fn.systemlist(cmd)) do
    if l ~= '' then
      out[#out + 1] = rel_to(root, l)
    end
  end
  return out, true
end

local function entries_of(root)
  local name = active_preset(root)
  if not name then
    return nil, nil -- auto mode
  end
  local p = preset_read(name)
  if not p then
    return {}, name -- named but not saved yet: an empty preset to fill
  end
  return p.entries, name
end

-- write '<root>/.tags/files' (preset mode) or remove it (auto mode)
local function materialize(root)
  local entries, name = entries_of(root)
  local d = dbdir() or '.tags'
  local list = root .. '/' .. d .. '/files'
  if not entries then
    if uv.fs_stat(list) then
      pcall(vim.fn.delete, list)
    end
    s.cache[root] = { files = nil, entries = nil, preset = nil }
    return nil, nil
  end
  local files, seen = {}, {}
  for _, e in ipairs(entries) do
    for _, f in ipairs((expand_entry(root, e))) do
      if not seen[f] then
        seen[f] = true
        files[#files + 1] = f
      end
    end
  end
  table.sort(files)
  vim.fn.mkdir(root .. '/' .. d, 'p')
  pcall(vim.fn.writefile, files, list)
  s.cache[root] = { files = files, entries = entries, preset = name }
  return files, name
end

-- autoindex.lua calls this before it builds a file list, so a preset is in
-- place BEFORE the first index runs (otherwise the very first build - the one
-- that happens when a project has no index yet - would index the whole tree)
function _G.projectfiles_materialize(root)
  if not root or root == '' then
    return false
  end
  local entries = entries_of(root)
  if not entries then
    return false -- auto mode: nothing to write
  end
  materialize(root)
  return true
end

-- ---------------------------------------------------------------------------
-- reindex what we just decided
-- ---------------------------------------------------------------------------
-- The list just changed on purpose, so the incremental refresh runs with a
-- bang: 'gtags -i' makes the database equal to the list (it drops what is no
-- longer there), and the usual "this would shrink the index" guard must not
-- get in the way.
local function reindex(root)
  if vim.fn.exists(':GtagsIndexRefresh') == 2 then
    pcall(vim.cmd, 'GtagsIndexRefresh!')
  end
  if vim.fn.exists(':GutentagsUpdate') == 2 and vim.b.gutentags_files ~= nil then
    pcall(vim.cmd, 'silent! GutentagsUpdate!')
  end
end

-- ---------------------------------------------------------------------------
-- entry editing
-- ---------------------------------------------------------------------------
local function save_entries(root, name, entries)
  if #entries == 0 then
    -- an empty preset indexes nothing, and an empty file list makes the
    -- indexer skip its run - which would leave the old index in place and
    -- quietly stale. Dropping the last entry means "index everything again".
    -- Never WRITE that empty list: my copy is preferred over the one vim-ide
    -- carries, so an empty file would hide the shared preset of that name on
    -- this machine, in every project. Drop my copy instead.
    local mine = preset_path(name)
    local had_mine = uv.fs_stat(mine) ~= nil
    if had_mine then
      pcall(vim.fn.delete, mine)
    end
    set_active(root, '')
    materialize(root)
    reindex(root)
    local sp = shared_path(name)
    notify(sp and uv.fs_stat(sp)
      and ("목록이 비어 auto 모드로 돌아갑니다 (내 '%s' 사본은 지웠고 vim-ide "
        .. '공용본은 그대로입니다)'):format(name)
      or '목록이 비어 auto 모드로 돌아갑니다 (프로젝트 전체 색인)')
    return nil
  end
  preset_write(name, entries)
  local files = materialize(root)
  reindex(root)
  return files
end

-- A path typed in the view is meant relative to the PROJECT (that is what
-- the rows show); a path completed on the command line is relative to the
-- cwd. Try the project first, then the cwd.
local function abs_of(root, path)
  local cand
  if path:sub(1, 1) == '/' then
    cand = path
  elseif uv.fs_stat(root .. '/' .. path) then
    cand = root .. '/' .. path
  else
    cand = vim.fn.fnamemodify(path, ':p')
  end
  cand = vim.fn.fnamemodify(cand, ':p'):gsub('/+$', '')
  return uv.fs_realpath(cand) or cand
end

local function add_path(root, path)
  local entries, name = entries_of(root)
  local abs = abs_of(root, path)
  local st = uv.fs_stat(abs)
  if not st then
    -- check BEFORE switching modes: a typo must not turn the project into
    -- an empty preset (which would index nothing at all)
    notify('없는 경로: ' .. path, vim.log.levels.WARN)
    return
  end
  if not name then
    -- auto mode: adding a path means "start a preset here"
    name = tostring(cfg('preset', 'default'))
    if preset_read(name) then
      -- that name is taken - by one of mine, or by one vim-ide carries.
      -- Starting an empty list under it would HIDE the saved preset instead
      -- of extending it, so take a free name (this project's directory).
      local base = vim.fn.fnamemodify(root, ':t')
      if base == '' then
        base = name
      end
      local free = base
      local i = 2
      while preset_read(free) do
        free = base .. '-' .. i
        i = i + 1
      end
      name = free
    end
    entries = {}
    set_active(root, name)
    notify("auto -> preset '" .. name .. "'")
  end
  local rel = rel_to(root, abs)
  for _, e in ipairs(entries) do
    if e.path == rel then
      notify('이미 있습니다: ' .. rel)
      return
    end
  end
  entries[#entries + 1] = { path = rel, kind = st.type == 'directory' and 'dir' or 'file' }
  save_entries(root, name, entries)
  notify('추가: ' .. rel)
end

local function remove_path(root, path)
  local entries, name = entries_of(root)
  if not name then
    notify('auto 모드에서는 제거할 목록이 없습니다', vim.log.levels.WARN)
    return
  end
  local abs = abs_of(root, path)
  local rel = rel_to(root, abs)
  local kept, hit = {}, false
  for _, e in ipairs(entries) do
    -- removing a directory drops the files under it too
    if e.path == rel or e.path:sub(1, #rel + 1) == rel .. '/' then
      hit = true
    else
      kept[#kept + 1] = e
    end
  end
  if not hit then
    -- the path may be covered by a directory entry: keep the entry, exclude
    -- the file by rewriting that directory into its remaining files
    local expanded = {}
    for _, e in ipairs(entries) do
      if e.kind == 'dir' and rel:sub(1, #e.path + 1) == e.path .. '/' then
        hit = true
        for _, f in ipairs((expand_entry(root, e))) do
          if f ~= rel then
            expanded[#expanded + 1] = { path = f, kind = 'file' }
          end
        end
      else
        expanded[#expanded + 1] = e
      end
    end
    if hit then
      kept = expanded
    end
  end
  if not hit then
    notify('목록에 없습니다: ' .. rel, vim.log.levels.WARN)
    return
  end
  save_entries(root, name, kept)
  notify('제거: ' .. rel)
end

-- ---------------------------------------------------------------------------
-- what a file drags in with it
-- ---------------------------------------------------------------------------
-- Picking one file is rarely what you mean: that file needs its headers, and
-- the files defining the symbols it calls. Both are pulled in with it (one
-- level deep), bounded by g:projectfiles_expand_max.

local KEYWORD = {}
for w in ([[if else for while do switch case break continue return goto sizeof
  struct union enum typedef static const volatile extern inline void char short
  int long float double signed unsigned register auto default typeof asm
  __attribute__ NULL true false]]):gmatch('%S+') do
  KEYWORD[w] = true
end

local function global_cmd()
  if vim.fn.executable('global') == 1 then
    return 'global'
  end
  local p = vim.fn.expand('~/.local/bin/global')
  return vim.fn.executable(p) == 1 and p or nil
end

local function global_lines(root, args)
  local cmd = { global_cmd() }
  if not cmd[1] then
    return {}
  end
  vim.list_extend(cmd, args)
  local ok, o = pcall(function()
    return vim.system(cmd, { text = true, cwd = root,
      env = { GTAGSOBJDIR = dbdir() } }):wait(4000)
  end)
  if not ok or not o or o.code ~= 0 or not o.stdout then
    return {}
  end
  return vim.split(o.stdout, '\n', { trimempty = true })
end

-- headers this file includes, as far as they exist inside the project
local function includes_of(root, abs)
  local out, dir = {}, vim.fs.dirname(abs)
  local ok, lines = pcall(vim.fn.readfile, abs, '', 3000)
  if not ok then
    return out
  end
  for _, l in ipairs(lines) do
    local inc = l:match('^%s*#%s*include%s*"([^"]+)"')
        or l:match('^%s*#%s*include%s*<([^>]+)>')
    if inc then
      local cand = dir .. '/' .. inc
      if not uv.fs_stat(cand) then
        cand = nil
        -- ask the index where that header is: '-P' matches whole paths
        local pat = '/' .. inc:gsub('([%.%+%-%*%?%[%]%^%$%(%)%%])', '\\%1') .. '$'
        for _, hit in ipairs(global_lines(root, { '-P', pat })) do
          local p2 = hit:sub(1, 1) == '/' and hit or (root .. '/' .. hit)
          if uv.fs_stat(p2) then
            cand = p2
            break
          end
        end
      end
      if cand then
        out[#out + 1] = cand
      end
    end
  end
  return out
end

-- files defining the symbols this one uses
local function symbol_files(root, abs)
  local out, seen = {}, {}
  local ok, lines = pcall(vim.fn.readfile, abs, '', 3000)
  if not ok then
    return out
  end
  local max = tonumber(cfg('expand_max', 40)) or 40
  local syms, n = {}, 0
  for _, l in ipairs(lines) do
    if not l:match('^%s*#') then
      for w in l:gmatch('[A-Za-z_][A-Za-z0-9_]*') do
        if not KEYWORD[w] and #w > 2 and not seen[w] and n < max then
          seen[w] = true
          n = n + 1
          syms[#syms + 1] = w
        end
      end
    end
  end
  local self_rel = rel_to(root, abs)
  local files, added = {}, {}
  for _, sym in ipairs(syms) do
    for _, hit in ipairs(global_lines(root, { '--result=ctags-mod', '-d', sym })) do
      local path = hit:match('^([^\t]+)')
      if path then
        local rel = path:sub(1, 1) == '/' and rel_to(root, path) or path
        if rel ~= self_rel and not added[rel] and uv.fs_stat(root .. '/' .. rel) then
          added[rel] = true
          files[#files + 1] = rel
        end
      end
    end
  end
  for _, f in ipairs(files) do
    out[#out + 1] = root .. '/' .. f
  end
  return out
end

-- everything `abs` needs, as project-relative paths
local function related_of(root, abs)
  if cfg('expand', 1) == 0 then
    return {}
  end
  local out, seen = {}, {}
  for _, list in ipairs({ includes_of(root, abs), symbol_files(root, abs) }) do
    for _, p in ipairs(list) do
      local rel = rel_to(root, p)
      if indexed(p) and rel:sub(1, 1) ~= '/' and not seen[rel] then
        seen[rel] = true
        out[#out + 1] = rel
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- adding, with what the file needs
-- ---------------------------------------------------------------------------
local function add_with_related(root, path)
  local before = select(1, entries_of(root)) or {}
  local n0 = #before
  add_path(root, path)
  local entries, name = entries_of(root)
  if not name then
    return -- add_path refused (bad path)
  end
  if #entries == n0 then
    return -- nothing new
  end
  local abs = abs_of(root, path)
  local st = uv.fs_stat(abs)
  if not (st and st.type == 'file') then
    return -- a directory already brings its own tree
  end
  local have = {}
  for _, e in ipairs(entries) do
    have[e.path] = true
  end
  local extra = {}
  for _, rel in ipairs(related_of(root, abs)) do
    if not have[rel] then
      have[rel] = true
      extra[#extra + 1] = { path = rel, kind = 'file' }
    end
  end
  if #extra == 0 then
    return
  end
  vim.list_extend(entries, extra)
  save_entries(root, name, entries)
  notify(('연관 파일 %d개 함께 추가 (헤더/심볼 정의)'):format(#extra))
end

-- ---------------------------------------------------------------------------
-- a symbol the index does not know: find the file that defines it
-- ---------------------------------------------------------------------------
-- 'global' can only answer for files that are already indexed, so this looks
-- at the SOURCE instead - definitions first, any mention as a last resort.
local GLOBS = "'*.c' '*.h' '*.cpp' '*.cc' '*.S' '*.dts' '*.dtsi'"

-- Side trees (tools/, samples/, selftests ...) carry their own copies of
-- kernel headers; pulling those into a project is noise.
local function rank_hits(lines, root, max)
  local function side(x)
    return x:match('^tools/') ~= nil or x:match('^samples/') ~= nil
        or x:match('^Documentation/') ~= nil or x:match('^scripts/') ~= nil
        or x:match('/selftests/') ~= nil or x:match('/test[s]?/') ~= nil
  end
  local main, all = {}, {}
  for _, l in ipairs(lines) do
    if l ~= '' and uv.fs_stat(root .. '/' .. l) then
      all[#all + 1] = l
      if not side(l) then
        main[#main + 1] = l
      end
    end
  end
  local pick = #main > 0 and main or all
  table.sort(pick, function(a, b)
    if #a ~= #b then
      return #a < #b
    end
    return a < b
  end)
  local out = {}
  for _, l in ipairs(pick) do
    if #out < max then
      out[#out + 1] = l
    end
  end
  return out
end

local function def_patterns(sym)
  return {
    "-e '^[A-Za-z_].*[^A-Za-z0-9_]" .. sym .. "[[:space:]]*\\('",
    "-e '^#[[:space:]]*define[[:space:]]+" .. sym .. "[^A-Za-z0-9_]'",
    -- 'struct foo {' has no separator left before the name once
    -- '[[:space:]]' has eaten the space, so the middle part is optional
    "-e '^(typedef|struct|union|enum)[[:space:]]+([^;{]*[^A-Za-z0-9_])?" ..
      sym .. "[^A-Za-z0-9_]*[;{]'",
    "-e '^[A-Za-z_].*[^A-Za-z0-9_]" .. sym .. "[[:space:]]*[=;[]'",
  }
end

local function grep_defining(root, sym)
  local pats = def_patterns(sym)
  local cmds = {}
  if uv.fs_stat(root .. '/.git') then
    cmds[#cmds + 1] = 'git grep -lE ' .. table.concat(pats, ' ') .. ' -- ' .. GLOBS
  end
  cmds[#cmds + 1] = "grep -rlE " .. table.concat(pats, ' ') ..
      " --include='*.c' --include='*.h' --include='*.cpp' --include='*.cc' ."
  local max = tonumber(cfg('grep_max', 5)) or 5
  for _, c in ipairs(cmds) do
    local ok, lines = pcall(vim.fn.systemlist, { 'sh', '-c',
      'cd ' .. vim.fn.shellescape(root) .. ' && ' .. c .. ' 2>/dev/null | head -' ..
      (max * 4) })
    if ok then
      local hits = rank_hits(lines, root, max)
      if #hits > 0 then
        return hits
      end
    end
  end
  return {}
end

-- Same search, off the main loop: 'git grep' over a kernel-sized tree takes
-- well over a second, and nothing may block the editor for that.
local function grep_defining_async(root, sym, cb)
  local pats = def_patterns(sym)
  local max = tonumber(cfg('grep_max', 5)) or 5
  local cmds = {}
  if uv.fs_stat(root .. '/.git') then
    cmds[#cmds + 1] = 'git grep -lE ' .. table.concat(pats, ' ') .. ' -- ' .. GLOBS
  end
  cmds[#cmds + 1] = 'grep -rlE ' .. table.concat(pats, ' ') ..
      " --include='*.c' --include='*.h' --include='*.cpp' --include='*.cc' ."
  local i = 0
  local function step()
    i = i + 1
    if i > #cmds then
      cb({})
      return
    end
    local ok = pcall(vim.system, { 'sh', '-c',
      'cd ' .. vim.fn.shellescape(root) .. ' && ' .. cmds[i] ..
      ' 2>/dev/null | head -' .. (max * 4) },
      { text = true }, function(o)
        vim.schedule(function()
          local hits = rank_hits(vim.split(o.stdout or '', '\n'), root, max)
          if #hits > 0 then
            cb(hits)
          else
            step()
          end
        end)
      end)
    if not ok then
      cb({})
    end
  end
  step()
end

function _G.projectfiles_add_for_symbol_async(sym, cb)
  cb = cb or function() end
  if type(sym) ~= 'string' or not sym:match('^[A-Za-z_][A-Za-z0-9_]*$') then
    return cb(0)
  end
  local root = cur_root()
  local entries, name = entries_of(root)
  if not name then
    return cb(0) -- auto mode indexes everything already
  end
  grep_defining_async(root, sym, function(hits)
    local have = {}
    for _, e in ipairs(entries) do
      have[e.path] = true
    end
    local added = {}
    for _, rel in ipairs(hits) do
      if not have[rel] then
        have[rel] = true
        entries[#entries + 1] = { path = rel, kind = 'file' }
        added[#added + 1] = rel
      end
    end
    if #added == 0 then
      return cb(0)
    end
    preset_write(name, entries)
    materialize(root)
    local prog = vim.fn.executable('global') == 1 and 'global'
        or vim.fn.expand('~/.local/bin/global')
    local left = #added
    for _, rel in ipairs(added) do
      local ok = pcall(vim.system, { prog, '--single-update', rel },
        { cwd = root, env = { GTAGSOBJDIR = dbdir() or '.tags' } },
        function()
          vim.schedule(function()
            left = left - 1
            if left == 0 then
              reindex(root)
              notify(("'%s' 정의 파일 %d개 추가: %s")
                :format(sym, #added, table.concat(added, ', ')))
              cb(#added)
            end
          end)
        end)
      if not ok then
        left = left - 1
      end
    end
    if left <= 0 then
      reindex(root)
      cb(#added)
    end
  end)
end

-- add the files that define `sym`, index them straight away, and say how
-- many were added (0 = nothing found / nothing new)
function _G.projectfiles_add_for_symbol(sym)
  if type(sym) ~= 'string' or not sym:match('^[A-Za-z_][A-Za-z0-9_]*$') then
    return 0
  end
  local root = cur_root()
  local entries, name = entries_of(root)
  if not name then
    return 0 -- auto mode indexes everything already
  end
  local have = {}
  for _, e in ipairs(entries) do
    have[e.path] = true
  end
  local hits = grep_defining(root, sym)
  local added = {}
  for _, rel in ipairs(hits) do
    if not have[rel] then
      have[rel] = true
      entries[#entries + 1] = { path = rel, kind = 'file' }
      added[#added + 1] = rel
    end
  end
  if #added == 0 then
    return 0
  end
  preset_write(name, entries)
  materialize(root)
  -- index the new files NOW so the jump that triggered this can be retried
  -- immediately; the full refresh below keeps everything else in step
  local prog = vim.fn.executable('global') == 1 and 'global'
      or vim.fn.expand('~/.local/bin/global')
  for _, rel in ipairs(added) do
    pcall(function()
      vim.system({ prog, '--single-update', rel },
        { cwd = root, env = { GTAGSOBJDIR = dbdir() or '.tags' } }):wait(5000)
    end)
  end
  reindex(root)
  notify(("'%s' 을(를) 정의한 파일 %d개를 추가했습니다: %s")
    :format(sym, #added, table.concat(added, ', ')))
  return #added
end

-- side-tree entries an earlier, less picky expansion may have pulled in
api.nvim_create_user_command('ProjectFilesPrune', function()
  local root = cur_root()
  local entries, name = entries_of(root)
  if not name then
    notify('auto 모드입니다 (정리할 목록 없음)')
    return
  end
  local kept, gone = {}, {}
  for _, e in ipairs(entries) do
    local p2 = e.path
    if p2:match('^tools/') or p2:match('^samples/') or p2:match('^Documentation/')
        or p2:match('^scripts/') or p2:match('/selftests/') then
      gone[#gone + 1] = p2
    else
      kept[#kept + 1] = e
    end
  end
  if #gone == 0 then
    notify('정리할 항목이 없습니다 (' .. #entries .. ' entries)')
    return
  end
  save_entries(root, name, kept)
  notify(('%d개 제거 (tools/ samples/ scripts/ Documentation/ selftests), %d개 남음')
    :format(#gone, #kept))
end, { desc = 'Drop tools//samples//scripts entries from the preset' })

api.nvim_create_user_command('ProjectFilesAddSymbol', function(o)
  local sym = o.args ~= '' and o.args or vim.fn.expand('<cword>')
  if _G.projectfiles_add_for_symbol(sym) == 0 then
    notify("'" .. sym .. "' 을(를) 정의한 파일을 찾지 못했습니다",
      vim.log.levels.WARN)
  end
end, { nargs = '?', desc = 'Add the file that defines a symbol to the list' })

-- ---------------------------------------------------------------------------
-- pickers (telescope when it is there, vim.ui.select otherwise)
-- ---------------------------------------------------------------------------
local function telescope()
  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    return nil
  end
  return {
    pickers = pickers,
    finders = require('telescope.finders'),
    conf = require('telescope.config').values,
    actions = require('telescope.actions'),
    state = require('telescope.actions.state'),
  }
end

-- the files that are indexed right now (preset list, or the whole project)
local function current_files(root)
  local d = dbdir() or '.tags'
  local list = root .. '/' .. d .. '/files'
  if uv.fs_stat(list) then
    return vim.fn.readfile(list)
  end
  local fl = vim.fn.expand('~/.local/bin/indexfiles.sh')
  if vim.fn.executable(fl) == 1 then
    local o = vim.fn.systemlist({ 'sh', '-c', 'cd ' .. vim.fn.shellescape(root)
      .. ' && ' .. vim.fn.shellescape(fl) })
    local out = {}
    for _, l in ipairs(o) do
      l = l:gsub('^%./', '')
      if l ~= '' then
        out[#out + 1] = l
      end
    end
    return out
  end
  return {}
end

local function open_in_edit(root, rel)
  local abs = rel:sub(1, 1) == '/' and rel or (root .. '/' .. rel)
  local target
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    local n = api.nvim_buf_get_name(b)
    if vim.bo[b].buftype == '' and not n:match('RelationView') then
      target = w
      break
    end
  end
  local buf = vim.fn.bufadd(abs)
  vim.bo[buf].buflisted = true
  if target then
    api.nvim_win_set_buf(target, buf)
    api.nvim_set_current_win(target)
  else
    vim.cmd('edit ' .. vim.fn.fnameescape(abs))
  end
end

local function fallback_select(items, prompt, on_choice)
  if #items == 0 then
    notify('목록이 비어 있습니다')
    return
  end
  vim.ui.select(items, { prompt = prompt }, function(choice)
    if choice then
      on_choice(choice)
    end
  end)
end

-- <leader>fo : find a project file and jump to it
local function pick_find()
  local root = cur_root()
  local files = current_files(root)
  local t = telescope()
  if not t then
    return fallback_select(files, 'Project files',
      function(c) open_in_edit(root, c) end)
  end
  t.pickers.new({}, {
    prompt_title = ('Project files [%s] (%d)  ^a add  ^d remove')
        :format(active_preset(root) or 'auto', #files),
    finder = t.finders.new_table({
      results = files,
      entry_maker = function(e)
        return { value = e, display = e, ordinal = e, path = root .. '/' .. e }
      end,
    }),
    sorter = t.conf.generic_sorter({}),
    previewer = t.conf.file_previewer({}),
    attach_mappings = function(bufnr, map)
      t.actions.select_default:replace(function()
        local entry = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if entry then
          open_in_edit(root, entry.value)
        end
      end)
      map({ 'i', 'n' }, '<C-d>', function()
        local entry = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if entry then
          remove_path(root, entry.value)
        end
      end)
      map({ 'i', 'n' }, '<C-a>', function()
        t.actions.close(bufnr)
        vim.schedule(function() vim.cmd('ProjectFilesAdd') end)
      end)
      return true
    end,
  }):find()
end

-- files in the project that are NOT in the list yet
local function candidates(root)
  local have = {}
  for _, f in ipairs(current_files(root)) do
    have[f] = true
  end
  local cmd = "cd " .. vim.fn.shellescape(root) .. " && { git ls-files --cached --others"
      .. " --exclude-standard 2>/dev/null || find . -type f | sed 's|^\\./||'; }"
  local out = {}
  for _, l in ipairs(vim.fn.systemlist({ 'sh', '-c', cmd })) do
    l = l:gsub('^%./', '')
    if l ~= '' and indexed(l) and not have[l] then
      out[#out + 1] = l
    end
  end
  table.sort(out)
  return out
end

-- pick files (multi-select) to register
local function pick_add()
  local root = cur_root()
  local items = candidates(root)
  local t = telescope()
  if not t then
    return fallback_select(items, '추가할 파일',
      function(c) add_with_related(root, c) end)
  end
  t.pickers.new({}, {
    prompt_title = 'Add to project files (' .. #items ..
        ')  <Tab> 여러 개  <CR> 추가',
    finder = t.finders.new_table({
      results = items,
      entry_maker = function(e)
        return { value = e, display = e, ordinal = e, path = root .. '/' .. e }
      end,
    }),
    sorter = t.conf.generic_sorter({}),
    previewer = t.conf.file_previewer({}),
    attach_mappings = function(bufnr)
      t.actions.select_default:replace(function()
        local picker = t.state.get_current_picker(bufnr)
        local picks = picker:get_multi_selection()
        if #picks == 0 then
          local e = t.state.get_selected_entry()
          picks = e and { e } or {}
        end
        t.actions.close(bufnr)
        for _, e in ipairs(picks) do
          add_with_related(root, e.value)
        end
      end)
      return true
    end,
  }):find()
end

-- directories of the project that are not registered yet
local function dir_candidates(root)
  local entries = entries_of(root) or {}
  local have = {}
  for _, e in ipairs(entries) do
    if e.kind == 'dir' then
      have[e.path] = true
    end
  end
  local cmd = 'cd ' .. vim.fn.shellescape(root) ..
      " && find . \\( -name .git -o -name .tags -o -name node_modules " ..
      "-o -name .svn \\) -prune -o -type d -print 2>/dev/null | sed 's|^\\./||'"
  local out = {}
  for _, l in ipairs(vim.fn.systemlist({ 'sh', '-c', cmd })) do
    if l ~= '' and l ~= '.' and not have[l] then
      out[#out + 1] = l
    end
  end
  table.sort(out)
  return out
end

-- pick directories to register (everything indexable under them)
local function pick_add_dir()
  local root = cur_root()
  local items = dir_candidates(root)
  local t = telescope()
  if not t then
    return fallback_select(items, '추가할 디렉터리',
      function(c) add_path(root, c) end)
  end
  t.pickers.new({}, {
    prompt_title = ('Add directories (%d)  <Tab> 여러 개  <CR> 추가')
        :format(#items),
    finder = t.finders.new_table({ results = items }),
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      t.actions.select_default:replace(function()
        local picker = t.state.get_current_picker(bufnr)
        local picks = picker:get_multi_selection()
        if #picks == 0 then
          local e = t.state.get_selected_entry()
          picks = e and { e } or {}
        end
        t.actions.close(bufnr)
        for _, e in ipairs(picks) do
          add_path(root, e[1] or e.value)
        end
      end)
      return true
    end,
  }):find()
end

-- pick which preset this project uses ('auto' = index everything)
local function pick_preset()
  local root = cur_root()
  local cur = active_preset(root)
  local names = preset_list()
  local items = { { name = nil, label = (cur == nil and '● ' or '  ') ..
    'auto  (프로젝트 전체 색인)' } }
  for _, n in ipairs(names) do
    local p = preset_read(n)
    local sp = shared_path(n)
    local shared = sp ~= nil and uv.fs_stat(sp) ~= nil
    -- say where a preset comes from: the ones vim-ide carries are on every
    -- machine, mine are only here
    local tag = shared
        and (uv.fs_stat(preset_path(n)) and '  [vim-ide + 내 사본]'
          or '  [vim-ide]')
        or ''
    items[#items + 1] = { name = n, label = ('%s%s  (%d entries)%s')
      :format(cur == n and '● ' or '  ', n, p and #p.entries or 0, tag) }
  end
  local function use(it)
    set_active(root, it.name or '')
    materialize(root)
    reindex(root)
    notify(it.name and ("preset '" .. it.name .. "'") or 'auto 모드')
  end
  local t = telescope()
  if not t then
    local labels = {}
    for _, it in ipairs(items) do
      labels[#labels + 1] = it.label
    end
    return fallback_select(labels, 'preset', function(_, idx)
      if idx then
        use(items[idx])
      end
    end)
  end
  t.pickers.new({}, {
    prompt_title = 'Preset  <CR> 사용  ^d 삭제',
    finder = t.finders.new_table({
      results = items,
      entry_maker = function(e)
        return { value = e, display = e.label, ordinal = e.label }
      end,
    }),
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(bufnr, map)
      t.actions.select_default:replace(function()
        local e = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if e then
          use(e.value)
        end
      end)
      map({ 'i', 'n' }, '<C-d>', function()
        local e = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if not (e and e.value.name) then
          return
        end
        local nm = e.value.name
        local had_mine = uv.fs_stat(preset_path(nm)) ~= nil
        if had_mine then
          pcall(vim.fn.delete, preset_path(nm))
        end
        -- a preset that vim-ide carries belongs to every machine: deleting
        -- my copy only drops the local override, the shared one stays
        local sp = shared_path(nm)
        if sp and uv.fs_stat(sp) then
          if had_mine and cur == nm then
            -- my override went away: the shared list is in force now
            materialize(root)
            reindex(root)
          end
          notify(had_mine
            and ("preset '" .. nm .. "' 내 사본 삭제 (vim-ide 공용본으로 복귀)")
            or ("preset '" .. nm .. "' 은 vim-ide 공용본입니다. 저장소에서 지우세요: "
              .. sp),
            had_mine and vim.log.levels.INFO or vim.log.levels.WARN)
          return
        end
        if cur == nm then
          set_active(root, '')
          materialize(root)
          reindex(root)
        end
        notify("preset '" .. nm .. "' 삭제")
      end)
      return true
    end,
  }):find()
end

-- save the current entries under a name (existing one, or a new one)
local function pick_save()
  local root = cur_root()
  local entries = entries_of(root) or {}
  if #entries == 0 then
    notify('저장할 항목이 없습니다 (,fp 로 추가하세요)', vim.log.levels.WARN)
    return
  end
  local function save(name)
    if not name or name == '' then
      return
    end
    preset_write(name, entries)
    set_active(root, name)
    materialize(root)
    notify(("preset '%s' 저장 (%d entries)"):format(name, #entries))
  end
  local NEW = '＋ 새 이름 입력…'
  local items = { NEW }
  vim.list_extend(items, preset_list())
  local function chosen(label)
    if label == NEW then
      vim.ui.input({ prompt = 'preset 이름: ',
        default = active_preset(root) or 'default' }, save)
    else
      save(label)
    end
  end
  local t = telescope()
  if not t then
    return fallback_select(items, '저장할 preset', chosen)
  end
  t.pickers.new({}, {
    prompt_title = ('Save %d entries as…'):format(#entries),
    finder = t.finders.new_table({ results = items }),
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      t.actions.select_default:replace(function()
        local e = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if e then
          vim.schedule(function() chosen(e[1] or e.value) end)
        end
      end)
      return true
    end,
  }):find()
end

-- pick entries to drop
local function pick_remove()
  local root = cur_root()
  local entries = entries_of(root) or {}
  local items = {}
  for _, e in ipairs(entries) do
    items[#items + 1] = e.kind .. '  ' .. e.path
  end
  local t = telescope()
  local function drop(label)
    remove_path(root, (label:gsub('^%a+%s+', '')))
  end
  if not t then
    return fallback_select(items, '제거할 항목', drop)
  end
  t.pickers.new({}, {
    prompt_title = 'Remove from project files (' .. #items .. ')',
    finder = t.finders.new_table({ results = items }),
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      t.actions.select_default:replace(function()
        local picker = t.state.get_current_picker(bufnr)
        local picks = picker:get_multi_selection()
        if #picks == 0 then
          local e = t.state.get_selected_entry()
          picks = e and { e } or {}
        end
        t.actions.close(bufnr)
        for _, e in ipairs(picks) do
          drop(e[1] or e.value)
        end
      end)
      return true
    end,
  }):find()
end

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------
api.nvim_create_user_command('ProjectFiles', function() pick_find() end,
  { desc = 'Find a project file (telescope) - ^a add, ^d remove' })
api.nvim_create_user_command('ProjectFilesFind', function() pick_find() end,
  { desc = 'Find a project file and jump to it' })

api.nvim_create_user_command('ProjectFilesAdd', function(o)
  local root = cur_root()
  if o.args == '' then
    pick_add()
    return
  end
  add_with_related(root, o.args)
end, { nargs = '?', complete = 'file',
  desc = 'Add a file/directory (with the headers and definitions it uses)' })

api.nvim_create_user_command('ProjectFilesRemove', function(o)
  local root = cur_root()
  if o.args == '' then
    pick_remove()
    return
  end
  remove_path(root, o.args)
end, { nargs = '?', complete = 'file', desc = 'Remove a file/directory' })

api.nvim_create_user_command('ProjectFilesAddDir', function(o)
  local root = cur_root()
  if o.args == '' then
    pick_add_dir()
    return
  end
  add_path(root, o.args)
end, { nargs = '?', complete = 'dir',
  desc = 'Add a directory (everything indexable under it)' })

api.nvim_create_user_command('ProjectFilesPreset', function(o)
  local root = cur_root()
  if o.args == '' then
    pick_preset()
    return
  end
  set_active(root, o.args == 'auto' and '' or o.args)
  materialize(root)
  reindex(root)
  notify(o.args == 'auto' and 'auto 모드' or ("preset '" .. o.args .. "'"))
end, { nargs = '?', complete = function()
  local n = preset_list()
  table.insert(n, 1, 'auto')
  return n
end, desc = 'Use a preset (auto = whole project)' })

api.nvim_create_user_command('ProjectFilesSave', function(o)
  local root = cur_root()
  local entries = entries_of(root) or {}
  if o.args == '' then
    pick_save()
    return
  end
  preset_write(o.args, entries)
  set_active(root, o.args)
  materialize(root)
  notify(("preset '%s' 저장 (%d entries)"):format(o.args, #entries))
end, { nargs = '?', desc = 'Save the current entries as a named preset' })

-- put a preset into vim-ide itself, so the other machines (the Linux box)
-- get it with the next 'git pull'. The repository copy is what every
-- checkout reads; my own copy in stdpath('data') keeps shadowing it.
api.nvim_create_user_command('ProjectFilesPresetShare', function(o)
  local name = o.args ~= '' and o.args or active_preset(cur_root())
  if not name or name == '' then
    notify('공유할 preset 이름을 지정하세요 (:ProjectFilesPresetShare <name>)',
      vim.log.levels.WARN)
    return
  end
  local d = shared_dir(true)
  if not d then
    notify(vim.g.projectfiles_shared_presets == ''
      and '공유 preset 이 꺼져 있습니다 (g:projectfiles_shared_presets)'
      or 'vim-ide 의 presets 디렉터리를 만들지 못했습니다',
      vim.log.levels.WARN)
    return
  end
  local p = preset_read(name)
  if not p then
    notify("preset '" .. name .. "' 이(가) 없습니다", vim.log.levels.WARN)
    return
  end
  if #p.entries == 0 then
    notify("preset '" .. name .. "' 이 비어 있어 공유하지 않습니다",
      vim.log.levels.WARN)
    return
  end
  local dst = preset_file(d, name)
  -- the file in the repository is shared with the other machines: do not
  -- quietly shrink it
  local old = read_preset_file(dst)
  if old and #old.entries > #p.entries then
    local ans = vim.fn.confirm(
      ("vim-ide 의 '%s' 는 %d개, 지금 것은 %d개입니다. 덮어쓸까요?")
      :format(name, #old.entries, #p.entries), "&Yes\n&No", 2)
    if ans ~= 1 then
      notify('취소했습니다')
      return
    end
  end
  if not write_json(dst, encode_preset(name, p.entries)) then
    notify('저장하지 못했습니다 (쓰기 권한을 확인하세요): ' .. dst,
      vim.log.levels.ERROR)
    return
  end
  -- the hint has to be a command that actually runs: '-C <root>' means the
  -- pathspec is relative to <root>, and there may be no repository at all
  -- when g:projectfiles_shared_presets points somewhere else
  local repo = vim.fs.dirname(vim.fs.dirname(d))
  local rel = dst:sub(#repo + 2)
  local head = ("preset '%s' (%d entries) -> %s"):format(name, #p.entries, dst)
  if dst:sub(1, #repo + 1) == repo .. '/' and uv.fs_stat(repo .. '/.git') then
    notify(head .. '\n커밋해야 다른 장비에 반영됩니다: '
      .. ("git -C %s add %s && git commit && git push"):format(repo, rel))
  else
    notify(head)
  end
end, { nargs = '?', complete = function()
  return preset_list()
end, desc = 'Copy a preset into vim-ide so other machines get it' })

api.nvim_create_user_command('ProjectFilesReindex', function()
  local root = cur_root()
  materialize(root)
  reindex(root)
  notify('재색인 시작')
end, { desc = 'Rebuild the index for the current file list' })

-- a preset is applied as soon as the session knows which project it is in
-- as early as possible (the indexer may start on the first BufReadPost),
-- and again once the session is up and the real project is known
pcall(function()
  local root = root_of(nil)
  if active_preset(root) then
    materialize(root)
  end
end)

api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    vim.defer_fn(function()
      local root = cur_root()
      if active_preset(root) then
        materialize(root)
      end
    end, 200)
  end,
})
