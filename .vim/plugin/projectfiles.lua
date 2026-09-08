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
--   :ProjectFilesMode          pick the indexing mode (the dialog that comes
--                              up on startup when a project has none yet)
--   :ProjectFilesReindex       rebuild the index for the current list
--   :ProjectSymbols [name]     find any symbol the index knows and jump to
--                              its definition (<F3> in the picker hands it
--                              to the relation window)
--
-- In a picker
--   <CR> take the entry     <Tab> several at once
--   ^a   add files (find)   ^d remove from the list, or delete a preset
--
-- Options (.vimrc)
--   g:projectfiles_ask_mode    1 (default): a project whose mode was never
--                              chosen asks on startup instead of silently
--                              indexing everything. 0 keeps the old
--                              behaviour. Never asks when headless.
--   g:projectfiles_preset      preset to use when a project has none yet
--   g:projectfiles_shared_presets
--                              where the shared presets are ('' disables
--                              them; default '<vim-ide>/.vim/presets')
--   g:projectfiles_width       view width (default: the context width)
--   g:projectfiles_height      view height in its column (default 12)
--   g:projectfiles_exts        indexed extensions (default as indexfiles.sh)
--   g:projectfiles_symbol_db_max_mb
--                              past this much GTAGS, ':ProjectSymbols'
--                              wants a prefix instead of listing
--                              everything (default 40)
--   g:projectfiles_symbol_max  most symbols to list at once (default 200000)
--   g:projectfiles_symbol_timeout
--                              ms to wait for the definition dump
--                              (default 20000)

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
  symbols = {},    -- root -> { key = <GTAGS mtime>, list = {...} }
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
local function root_from_dir(dir)
  local hidden = dbdir()
  -- '<root>/.tags' 안의 파일에서 출발하면 그 데이터베이스 디렉터리 자체가
  -- 프로젝트 루트로 잡힌다: 예전 배치는 루트에 GTAGS 를 두었으므로 아래
  -- 순회가 '<d>/GTAGS' 도 루트 표시로 인정하고, '<root>/.tags/GTAGS' 가
  -- 바로 그 모양이기 때문이다.
  --
  -- 그렇게 잡히면 프로젝트가 '.tags' 가 되어 그 안을 색인하려 들고, 소스가
  -- 없으니 목록이 비고, 빈 목록으로 색인이 지워진다. 실제로 22개 파일짜리
  -- 프로젝트의 색인이 그렇게 0이 됐다. 그러니 먼저 그 디렉터리에서 나온다.
  if hidden and hidden ~= '' then
    local tail = '/' .. hidden
    while #dir > #tail and dir:sub(-#tail) == tail do
      dir = dir:sub(1, #dir - #tail)
    end
  end
  local d = dir
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

local function root_of(path)
  local dir = path and path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  return root_from_dir(dir)
end

-- 지금 보고 있는 프로젝트.
--
-- 특수 버퍼 - NERDTree, telescope 프롬프트, quickfix - 에는 파일 이름이 없다.
-- 예전에는 그때 곧바로 cwd 로 떨어졌는데, 그러면 트리에서 프로젝트 A 에
-- 파일을 담고 그 창에서 그대로 \fo 를 누르면 cwd 의 프로젝트 B 목록이 나온다.
-- '추가해도 \fo 에 반영이 안 된다'로 보이는 것이 이것이었다.
--
-- 그래서 이름 없는 버퍼에서는 cwd 로 가기 전에 두 군데를 먼저 본다.
local function cur_root()
  local name = api.nvim_buf_get_name(0)
  if name ~= '' and vim.bo.buftype == '' then
    return root_of(name)
  end
  -- 1) 파일 트리가 현재 창이면, 그 트리가 열고 있는 곳이 사용자가 보는
  --    프로젝트다 (NERDTree 는 b:NERDTree.root, neo-tree 는 state.path).
  local ok, troot = pcall(function()
    if vim.b.NERDTree then
      return vim.fn.eval('b:NERDTree.root.path.str()')
    end
    local okm, mgr = pcall(require, 'neo-tree.sources.manager')
    if okm and mgr and mgr.get_state then
      local st = mgr.get_state('filesystem')
      return st and st.path or nil
    end
  end)
  if ok and type(troot) == 'string' and troot ~= '' then
    return root_from_dir((troot:gsub('/+$', '')))
  end
  -- 2) 이 탭에 보이는 실제 파일 버퍼, 없으면 가장 최근에 쓴 파일 버퍼
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    local bn = api.nvim_buf_get_name(b)
    if bn ~= '' and vim.bo[b].buftype == '' then
      return root_of(bn)
    end
  end
  local best
  for _, bi in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if bi.name ~= '' and vim.bo[bi.bufnr].buftype == ''
        and (not best or (bi.lastused or 0) > (best.lastused or 0)) then
      best = bi
    end
  end
  if best then
    return root_of(best.name)
  end
  return root_from_dir(vim.fn.getcwd())
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

-- same set of entries? (order does not matter: the pickers append)
local function entries_differ(a, b)
  a, b = a or {}, b or {}
  if #a ~= #b then
    return true
  end
  local seen = {}
  for _, e in ipairs(a) do
    seen[(e.kind or 'file') .. '\0' .. (e.path or '')] = true
  end
  for _, e in ipairs(b) do
    if not seen[(e.kind or 'file') .. '\0' .. (e.path or '')] then
      return true
    end
  end
  return false
end

-- using a preset whose local copy has drifted from the repository's: say so
-- once, at the moment it starts being used, or a 'git pull' that updated it
-- would look like it did nothing
local function announce_fork(name)
  if not name or name == '' then
    return
  end
  local mine = read_preset_file(preset_file(presets_dir(), name))
  local sp = shared_path(name)
  local sh = sp and read_preset_file(sp) or nil
  if mine and sh and entries_differ(mine.entries, sh.entries) then
    local how = (#mine.entries == #sh.entries)
        and ('개수는 같지만 내용이 다릅니다 (%d개)'):format(#sh.entries)
        or ('%d개로 다릅니다'):format(#sh.entries)
    notify(('내 사본을 씁니다 (%d개). vim-ide 공용본은 '):format(#mine.entries)
      .. how .. ' - ^d 로 내 사본을 지우면 공용본을 따라갑니다',
      vim.log.levels.WARN)
  end
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

-- Writing always targets MY copy, and my copy is the one that gets read. The
-- first write against a name vim-ide carries therefore forks it on this
-- machine: from then on a 'git pull' that updates the shared preset changes
-- nothing here. That fork is often not a deliberate save - C-] on a symbol
-- outside the preset adds the file that defines it - so say it out loud.
local function preset_write(name, entries)
  local f = preset_path(name)
  local sp = shared_path(name)
  local forking = uv.fs_stat(f) == nil and sp ~= nil and uv.fs_stat(sp) ~= nil
  if not write_json(f, encode_preset(name, entries)) then
    notify('preset 을 저장하지 못했습니다: ' .. f, vim.log.levels.ERROR)
    return false
  end
  if forking then
    notify(("vim-ide 공용 preset '%s' 를 이 장비 사본으로 갈랐습니다. "):format(name)
      .. '앞으로 git pull 은 이 preset 을 바꾸지 않습니다 '
      .. '(<leader>fm 에서 ^d 로 내 사본을 지우면 다시 따라갑니다)',
      vim.log.levels.WARN)
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

-- 하위에 자기 색인('.tags')을 가진 디렉터리는 별개의 프로젝트다.
--
-- 그 밑의 파일을 이 프로젝트 목록에 넣으면 같은 파일이 두 색인에 들어가고,
-- 상위에서 만든 목록이 하위 프로젝트의 preset 을 밀어내는 것처럼 보인다
-- (실제로 그렇게 꼬였다: 상위 트리에서 저장한 preset 이 하위 트리의 경로로
--  가득 차 있었다). 그래서 목록을 만들 때마다 빼 준다.
--
-- 단, 걸르는 것은 '자동으로 만들어진 목록'뿐이다 (auto 모드의 git ls-files /
-- find - indexfiles.sh 가 처리한다). preset 에 담긴 항목은 사람이 직접 고른
-- 것이므로 하위 프로젝트 안이라도 그대로 둔다. '.indexfiles' 를 건드리지
-- 않는 것과 같은 이유다 - 명시적으로 고른 것이 규칙보다 우선한다.
-- 그래도 preset 까지 걸르고 싶으면 g:projectfiles_nested_presets = 1.
--
-- '실시간'이 요점이라 캐시는 아주 짧게만 둔다 - 한 번의 목록 생성 중에
-- 여러 번 물어보는 것만 묶고, 다음 동작에서는 다시 찾는다.
--   let g:projectfiles_nested_depth = 6   " 찾는 깊이 (0 이면 이 기능을 끈다)
--   let g:projectfiles_nested_presets = 1 " preset 항목도 걸른다 (기본 0)
local nested_cache = {}

local function nested_prefixes(root)
  local depth = tonumber(cfg('nested_depth', 6)) or 6
  if depth <= 0 then
    return {}
  end
  local d = dbdir() or '.tags'
  local now = uv.now()
  local c = nested_cache[root]
  if c and c.depth == depth and (now - c.at) < 2000 then
    return c.list
  end
  local cmd = ('find %s -mindepth 2 -maxdepth %d -type d -name %s -prune -print 2>/dev/null')
      :format(vim.fn.shellescape(root), depth + 1, vim.fn.shellescape(d))
  local list = {}
  local tail = '/' .. d
  for _, l in ipairs(vim.fn.systemlist({ 'sh', '-c', cmd })) do
    if l:sub(-#tail) == tail then
      local dir = l:sub(1, #l - #tail)
      if dir:sub(1, #root + 1) == root .. '/' then
        list[#list + 1] = dir:sub(#root + 2) .. '/'
      end
    end
  end
  nested_cache[root] = { at = now, depth = depth, list = list }
  return list
end

-- 이 상대 경로가 하위 프로젝트 안인가 (그렇다면 그 프로젝트의 상대 접두어)
local function nested_owner(root, rel)
  for _, pre in ipairs(nested_prefixes(root)) do
    if rel:sub(1, #pre) == pre then
      return (pre:gsub('/$', ''))
    end
  end
  return nil
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
    -- 파일이 아예 없으면 '이름만 정해 두고 아직 저장 안 한' 정상 상태다:
    -- 빈 목록으로 시작한다. 파일은 있는데 읽히지 않으면(깨진 JSON 등)
    -- 얘기가 다르다 - 빈 목록으로 시작하면 다음 저장이 그 preset 을
    -- 한 항목으로 덮어써서 담아 둔 것을 전부 잃는다. 그건 막는다.
    for _, f in ipairs({ preset_path(name), shared_path(name) }) do
      if f and uv.fs_stat(f) then
        notify(("preset '%s' 을 읽을 수 없습니다 (%s) — 덮어쓰지 않기 위해 "):format(
            name, vim.fn.fnamemodify(f, ':~'))
          .. '목록을 비워 시작하지 않습니다. 파일을 고치거나 '
          .. ':ProjectFilesMode 로 다른 모드를 고르세요.',
          vim.log.levels.ERROR)
        return nil, nil, true -- 세 번째 값 = 읽을 수 없다(손대지 마라)
      end
    end
    return {}, name -- named but not saved yet: an empty preset to fill
  end
  return p.entries, name
end

-- write '<root>/.tags/files' (preset mode) or remove it (auto mode)
local function materialize(root)
  local entries, name, bad = entries_of(root)
  if bad then
    return nil, nil -- 읽을 수 없는 preset: 목록도 색인도 그대로 둔다
  end
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
  -- preset 항목은 사람이 고른 것이라 기본적으로 걸르지 않는다 (위 설명 참고)
  local pre = cfg('nested_presets', 0) ~= 0 and nested_prefixes(root) or {}
  local dropped = 0
  for _, e in ipairs(entries) do
    for _, f in ipairs((expand_entry(root, e))) do
      if not seen[f] then
        local nested = false
        for _, q in ipairs(pre) do
          if f:sub(1, #q) == q then
            nested = true
            break
          end
        end
        if nested then
          dropped = dropped + 1
        else
          seen[f] = true
          files[#files + 1] = f
        end
      end
    end
  end
  if dropped > 0 and s.nested_told ~= (root .. '\0' .. dropped) then
    s.nested_told = root .. '\0' .. dropped
    notify(('하위 프로젝트(자기 .tags 가 있는 디렉터리)의 파일 %d개를 '):format(dropped)
      .. '목록에서 뺐습니다: ' .. table.concat(pre, ' ')
      .. '  (g:projectfiles_nested_presets = 0 으로 끌 수 있습니다)')
  end
  -- 항목은 있는데 펼친 결과가 하나도 없으면 빈 목록을 쓰지 않는다.
  --
  -- 빈 '.tags/files' 는 indexfiles.sh 에게 '색인할 파일이 없다'로 읽히고,
  -- 그러면 색인이 낡은 채로 남거나 통째로 비워진다. 실제로 그렇게 22개
  -- 파일짜리 프로젝트의 색인이 0이 됐다. 이 프로젝트에 없는 경로만 담긴
  -- preset 을 골랐을 때도 같은 일이 난다. 조용히 넘길 일이 아니다.
  if #files == 0 and #entries > 0 then
    notify(("preset '%s' 의 경로가 이 프로젝트에서 하나도 펼쳐지지 않았습니다"):format(
        name or '?')
      .. ' — 목록과 색인을 그대로 둡니다. 다른 체크아웃의 preset 이거나'
      .. ' 전부 하위 프로젝트 안입니다.', vim.log.levels.WARN)
    return nil, name
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
  local entries, _, bad = entries_of(root)
  if bad or not entries then
    return false -- auto mode(또는 읽을 수 없는 preset): 쓸 것이 없다
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
  if s.symbols then
    s.symbols[root] = nil -- the symbol list is about to change
  end
  if type(_G.projectfiles_tree_invalidate) == 'function' then
    pcall(_G.projectfiles_tree_invalidate) -- 트리 표시도 다시 계산되게
  end
  -- 루트를 그대로 넘긴다. ':GtagsIndexRefresh' 는 현재 버퍼에서 프로젝트를
  -- 다시 찾는데, 트리 창이나 telescope 프롬프트에서 부르면 그 버퍼에 이름이
  -- 없어서 cwd 로 떨어진다 - cwd 가 다른 프로젝트면 엉뚱한 색인을 갱신하거나
  -- 아무 것도 하지 않는다. 그래서 여기서 목록을 고친 프로젝트를 직접 준다.
  local done = false
  if type(_G.autoindex_refresh) == 'function' then
    local ok, res = pcall(_G.autoindex_refresh, root, true, '목록 변경')
    done = ok and res == true
  end
  if not done and vim.fn.exists(':GtagsIndexRefresh') == 2 then
    pcall(vim.cmd, 'GtagsIndexRefresh!')
  end
  if vim.fn.exists(':GutentagsUpdate') == 2 and vim.b.gutentags_files ~= nil then
    pcall(vim.cmd, 'silent! GutentagsUpdate!')
  end
end

-- ---------------------------------------------------------------------------
-- entry editing
-- ---------------------------------------------------------------------------
-- 여러 경로를 한 번에 담거나 뺄 때(트리에서 범위를 골랐을 때) 쓰는 문맥.
--
-- add_path 하나가 preset 쓰기 + 목록 다시 펼치기(디렉터리마다 find) +
-- 재색인까지 전부 한다. 50줄을 고르면 그게 50번 도는데, 중간 상태는 아무도
-- 보지 않는다. 그래서 배치 중에는 preset 파일만 갱신하고(다음 항목이 그걸
-- 읽어야 한다) 펼치기와 재색인은 끝에서 한 번만 한다. 알림도 모아서 한 줄로.
local batch = nil   -- { root =, msgs = {}, emptied = }

-- done = true 는 '경로 하나를 실제로 처리했다'는 뜻이다. 요약에서 세는 것은
-- 이것뿐이다 - 모드 전환 같은 일회성 알림까지 세면 개수가 부풀려진다.
local function bnotify(msg, level, done)
  if batch then
    batch.msgs[#batch.msgs + 1] = { msg = msg, level = level }
    if done then
      batch.done = batch.done + 1
    end
    return
  end
  notify(msg, level)
end

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
    if batch then
      batch.emptied = name
      return nil -- 커밋은 배치 끝에서
    end
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
  if batch then
    return nil -- 커밋은 배치 끝에서
  end
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
  local entries, name, bad = entries_of(root)
  if bad then
    return -- 읽을 수 없는 preset: 새 preset 을 시작해 버리면 더 나쁘다
  end
  local abs = abs_of(root, path)
  local st = uv.fs_stat(abs)
  if not st then
    -- check BEFORE switching modes: a typo must not turn the project into
    -- an empty preset (which would index nothing at all)
    bnotify('없는 경로: ' .. path, vim.log.levels.WARN)
    return
  end
  -- 하위 프로젝트 안의 경로라도, 직접 담으라고 한 것은 담는다. 다만 그
  -- 프로젝트가 자기 색인을 따로 갖고 있다는 사실은 알려 준다.
  local owner = nested_owner(root, rel_to(root, abs))
  if owner then
    if cfg('nested_presets', 0) ~= 0 then
      bnotify(("'%s' 는 자기 색인(.tags)을 가진 하위 프로젝트입니다 - "):format(owner)
        .. '거기서 담으세요', vim.log.levels.WARN)
      return
    end
    bnotify(("참고: '%s' 는 자기 색인(.tags)을 가진 하위 프로젝트입니다"):format(owner))
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
    bnotify("auto -> preset '" .. name .. "'")
  end
  local rel = rel_to(root, abs)
  for _, e in ipairs(entries) do
    if e.path == rel then
      bnotify('이미 있습니다: ' .. rel, nil, true)
      return
    end
  end
  entries[#entries + 1] = { path = rel, kind = st.type == 'directory' and 'dir' or 'file' }
  save_entries(root, name, entries)
  bnotify('추가: ' .. rel, nil, true)
end

local function remove_path(root, path)
  local entries, name, bad = entries_of(root)
  if bad then
    return
  end
  if not name then
    bnotify('auto 모드에서는 제거할 목록이 없습니다', vim.log.levels.WARN)
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
    bnotify('목록에 없습니다: ' .. rel, vim.log.levels.WARN)
    return
  end
  save_entries(root, name, kept)
  bnotify('제거: ' .. rel, nil, true)
end

-- 여러 경로를 한 번의 커밋으로 처리한다. fn 안에서는 add_path/remove_path 를
-- 몇 번이든 불러도 되고, 목록 펼치기와 재색인은 여기서 한 번만 일어난다.
local function in_batch(root, what, fn)
  if batch then
    fn() -- 중첩: 바깥 배치가 커밋한다
    return
  end
  local before = #(entries_of(root) or {})
  batch = { root = root, msgs = {}, done = 0 }
  local ok, err = pcall(fn)
  local b = batch
  batch = nil

  if b.emptied then
    -- 배치로 마지막 항목까지 빠졌다: 단일 경로와 같은 규칙으로 auto 복귀
    save_entries(root, b.emptied, {})
  else
    materialize(root)
    reindex(root)
  end

  -- 알림은 한 줄로. 경고는 몇 개만 보여 주고 나머지는 수만 알린다.
  local warns = {}
  for _, m in ipairs(b.msgs) do
    if m.level == vim.log.levels.WARN then
      warns[#warns + 1] = m.msg
    end
  end
  local after = #(entries_of(root) or {})
  local head = ('%s %d개 (항목 %d -> %d)'):format(what, b.done, before, after)
  if #warns > 0 then
    local shown = {}
    for i = 1, math.min(#warns, 3) do
      shown[i] = warns[i]
    end
    if #warns > 3 then
      shown[#shown + 1] = ('그 외 %d건'):format(#warns - 3)
    end
    notify(head .. ' | 건너뜀 ' .. #warns .. '개: '
      .. table.concat(shown, ', '), vim.log.levels.WARN)
  else
    notify(head)
  end
  if not ok then
    error(err)
  end
end


-- ---------------------------------------------------------------------------
-- 시작할 때 색인 모드를 물어보기
-- ---------------------------------------------------------------------------
-- 색인 모드는 '<root>/.tags/preset' 한 줄에 적힌다: 빈 줄이면 auto, 이름이
-- 있으면 그 preset. 그 파일이 아예 없으면 아직 아무도 고르지 않은 것이고,
-- 그때는 프로젝트 전체가 조용히 색인되기 시작한다 - 커널 트리에서는 그게
-- 몇 분씩 걸리는 일이라 물어보는 편이 낫다.
--
-- 이미 골라 둔 프로젝트는 묻지 않는다. 다시 고르려면 :ProjectFilesMode.
--   let g:projectfiles_ask_mode = 0   " 묻지 않고 예전처럼 auto 로 시작
local ask_state = { open = false, queue = {}, asked = {} }

local function mode_recorded(root)
  return uv.fs_stat(active_file(root)) ~= nil
end

-- 헤드리스(스크립트/테스트)에서는 물어볼 상대가 없다. UI 가 붙어 있는지로
-- 판단한다 - --headless 로 띄우면 목록이 비어 있다.
local function interactive()
  local ok, uis = pcall(api.nvim_list_uis)
  return ok and #uis > 0
end

local NEW_PRESET = '\0new'
local SKIP = '\0skip'

local function mode_items(root)
  local items = { { name = '', label = 'auto — 프로젝트 전체 (git ls-files / find)' } }
  for _, nm in ipairs(preset_list()) do
    local pr = preset_read(nm)
    local cnt = pr and pr.entries and #pr.entries or 0
    local where = preset_path and uv.fs_stat(preset_path(nm)) and '' or ' [vim-ide]'
    items[#items + 1] = {
      name = nm,
      label = ("preset '%s' — %d entries%s"):format(nm, cnt, where),
    }
  end
  items[#items + 1] = { name = NEW_PRESET, label = '새 preset 만들기 …' }
  items[#items + 1] = { name = SKIP, label = '이번에는 색인하지 않기' }
  return items
end

local choose_mode  -- 아래에서 정의

-- 한 번에 하나만 띄운다. 시작할 때 버퍼의 디렉터리와 cwd 가 서로 다른
-- 프로젝트면 두 번 물어볼 수 있는데, 창이 겹치면 답을 잃는다.
local function ask_next()
  if ask_state.open then
    return
  end
  local job = table.remove(ask_state.queue, 1)
  if not job then
    return
  end
  ask_state.open = true
  choose_mode(job.root, function(ok)
    ask_state.open = false
    job.cb(ok)
    vim.schedule(ask_next)
  end)
end

choose_mode = function(root, cb)
  local items = mode_items(root)
  local short = vim.fn.fnamemodify(root, ':~')
  vim.ui.select(items, {
    prompt = '색인 모드 — ' .. short,
    format_item = function(it) return it.label end,
  }, function(choice)
    if not choice or choice.name == SKIP then
      notify('색인을 건너뜁니다 (:ProjectFilesMode 로 다시 고를 수 있습니다)')
      cb(false)
      return
    end
    if choice.name == NEW_PRESET then
      vim.ui.input({ prompt = '새 preset 이름: ' }, function(nm)
        nm = nm and nm:gsub('^%s+', ''):gsub('%s+$', '') or ''
        if nm == '' then
          cb(false)
          return
        end
        set_active(root, nm)
        materialize(root)
        notify(("preset '%s' 시작 — NERDTree 에서 m 으로 파일을 담으세요"):format(nm))
        cb(true)
      end)
      return
    end
    set_active(root, choice.name)
    local files = materialize(root)
    if choice.name == '' then
      notify('auto 모드: 프로젝트 전체를 색인합니다')
    elseif files and #files == 0 then
      -- preset 은 프로젝트 상대 경로 목록이라 다른 체크아웃에서도 쓸 수
      -- 있는데, 그 대가로 여기 없는 경로는 조용히 빠진다. 전부 빠지면
      -- 색인이 텅 비므로 그건 말해 줘야 한다.
      notify(("preset '%s' 의 경로가 이 프로젝트에 하나도 없습니다 — "):format(
          choice.name) .. '색인이 비어 있습니다. NERDTree 에서 + 로 담거나 '
          .. ':ProjectFilesMode 로 auto 를 고르세요',
        vim.log.levels.WARN)
    else
      notify(("preset '%s' 로 색인합니다 (%d files)"):format(choice.name,
        files and #files or 0))
      announce_fork(choice.name)
    end
    cb(true)
  end)
end

-- autoindex.lua 가 색인을 시작하기 전에 부른다. 모드가 이미 정해져 있으면
-- 그대로 통과시키고(=요청 1), 정해진 적이 없으면 물어본 뒤 통과시킨다.
-- cb(false) 는 '이번에는 색인하지 말라'는 뜻이다.
function _G.projectfiles_ensure_mode(root, cb)
  cb = cb or function() end
  if not root or root == '' then
    cb(true)
    return
  end
  if cfg('ask_mode', 1) == 0 or not interactive() or mode_recorded(root) then
    cb(true)
    return
  end
  if ask_state.asked[root] then
    cb(false) -- 이 세션에서 이미 물었고 답이 '건너뛰기'였다
    return
  end
  ask_state.asked[root] = true
  ask_state.queue[#ask_state.queue + 1] = { root = root, cb = cb }
  ask_next()
end

-- ---------------------------------------------------------------------------
-- 파일 트리(NERDTree 등)에서 부르는 진입점
-- ---------------------------------------------------------------------------
-- 커맨드 쪽은 cur_root() 로 프로젝트를 찾는데, NERDTree 창의 버퍼에는 이름이
-- 없어서 cwd 로 떨어진다. 트리에서 고른 노드는 절대 경로를 알고 있으니,
-- 여기서는 그 경로에서 루트를 구한다.
local function tree_root(path)
  return root_of(path)
end

-- 경로 하나 또는 여러 개. 트리에서 범위를 고르면 목록이 넘어온다.
-- 여러 개일 때는 한 번만 펼치고 한 번만 재색인한다.
local function tree_paths(arg)
  local out = {}
  if type(arg) == 'table' then
    for _, p in ipairs(arg) do
      p = tostring(p or ''):gsub('/+$', '')
      if p ~= '' then
        out[#out + 1] = p
      end
    end
  else
    local p = tostring(arg or ''):gsub('/+$', '')
    if p ~= '' then
      out[1] = p
    end
  end
  return out
end

-- 트리 루트 자체는 건너뛴다. 범위를 크게 잡으면 루트 줄이 함께 들어오는데,
-- 그걸 담으면 preset 이 프로젝트 전체가 되어 고른 범위와 무관해진다.
local function drop_root(paths)
  local keep, dropped = {}, 0
  for _, p in ipairs(paths) do
    if p == tree_root(p) then
      dropped = dropped + 1
    else
      keep[#keep + 1] = p
    end
  end
  return keep, dropped
end

-- 대상 프로젝트가 지금 보고 있는 프로젝트와 다르면 그렇다고 말한다.
--
-- 경로는 스스로 어느 프로젝트에 속하는지 정한다(그래야 트리 창에서도 맞는
-- 곳에 담긴다). 그 대신 '내가 보던 곳이 아닌 다른 프로젝트에 들어갔다'는
-- 사실이 조용히 지나가면 안 된다 - 상위 트리에서 저장한 preset 이 하위
-- 트리의 경로로 가득 찬 것을 아무도 눈치채지 못한 것이 그래서였다.
local function announce_root(root)
  local ok, cur = pcall(cur_root)
  if ok and root and cur and root ~= cur then
    notify(('대상 프로젝트: %s   (보고 있던 곳: %s)'):format(
      vim.fn.fnamemodify(root, ':~'), vim.fn.fnamemodify(cur, ':~')))
  end
end

local function tree_apply(arg, what, one)
  local paths, dropped = drop_root(tree_paths(arg))
  if #paths == 0 then
    if dropped > 0 then
      notify('트리 루트는 건너뜁니다 (범위에 루트만 있었습니다)',
        vim.log.levels.WARN)
    end
    return false
  end
  local root = tree_root(paths[1])
  announce_root(root)
  if #paths == 1 then
    one(root, paths[1])
  else
    in_batch(root, what, function()
      for _, p in ipairs(paths) do
        one(root, p)
      end
    end)
  end
  if dropped > 0 then
    notify('트리 루트 ' .. dropped .. '줄은 건너뜀')
  end
  return true
end

function _G.projectfiles_add(arg)
  return tree_apply(arg, '추가', add_path)
end

function _G.projectfiles_remove(arg)
  return tree_apply(arg, '제거', remove_path)
end

-- 트리 노드 옆의 표시.
--
-- NERDTree 는 그릴 때 노드마다 이 함수를 부른다. 그래서 읽는 것은 전부
-- 캐시에서 나와야 한다: 목록 파일이 바뀌지 않는 한 다시 읽지 않고,
-- 경로->루트 도 디렉터리 단위로 기억한다(root_of 는 상위로 올라가며
-- fs_stat 을 반복한다).
local flag_cache = {}   -- root -> { key =, files =, dirs =, preset = }
local flag_root = {}    -- dir -> root

local function flag_data(root)
  local d = dbdir() or '.tags'
  local lf = root .. '/' .. d .. '/files'
  local st = uv.fs_stat(lf)
  local key = st and ('%d:%d:%d'):format(st.mtime.sec, st.mtime.nsec or 0,
    st.size) or 'none'
  local c = flag_cache[root]
  if c and c.key == key then
    return c
  end
  local files, dirs = {}, {}
  if st then
    for _, rel in ipairs(vim.fn.readfile(lf)) do
      if rel ~= '' then
        files[rel] = true
        -- 상위 디렉터리도 전부 표시 대상으로 (아래에 색인된 파일이 있다)
        local up = rel
        while true do
          local parent = up:match('^(.*)/[^/]+$')
          if not parent or parent == '' then
            break
          end
          dirs[parent] = true
          up = parent
        end
      end
    end
  end
  c = { key = key, files = files, dirs = dirs, preset = st ~= nil }
  flag_cache[root] = c
  return c
end

-- 목록을 고쳤으니 다음 렌더에서 다시 읽으라는 뜻
function _G.projectfiles_tree_invalidate()
  flag_cache = {}
  flag_root = {}
end

function _G.projectfiles_tree_flag(path)
  path = tostring(path or ''):gsub('/+$', '')
  if path == '' then
    return ''
  end
  local dir = path:match('^(.*)/[^/]*$') or path
  local root = flag_root[dir]
  if root == nil then
    root = root_of(path) or false
    flag_root[dir] = root
  end
  if not root then
    return ''
  end
  local c = flag_data(root)
  if not c.preset then
    return '' -- auto 모드: 전부 대상이라 표시할 게 없다
  end
  if path:sub(1, #root + 1) ~= root .. '/' then
    return ''
  end
  local rel = path:sub(#root + 2)
  if c.files[rel] then
    return tostring(cfg('tree_mark_file', '●'))
  end
  if c.dirs[rel] then
    return tostring(cfg('tree_mark_dir', '·'))
  end
  return ''
end

-- 이 경로가 지금 색인에 들어 있나. 트리에서 눌러 확인하는 용도.
function _G.projectfiles_status(path)
  path = tostring(path or '')
  if path == '' then
    return '(경로 없음)'
  end
  local root = tree_root(path)
  local _, name = entries_of(root)
  local rel = rel_to(root, abs_of(root, path))
  local inlist = false
  local d = dbdir() or '.tags'
  local lf = root .. '/' .. d .. '/files'
  if uv.fs_stat(lf) then
    for _, l in ipairs(vim.fn.readfile(lf)) do
      if l == rel or l:sub(1, #rel + 1) == rel .. '/' then
        inlist = true
        break
      end
    end
  else
    inlist = true -- auto 모드: 목록 파일이 없고 전체가 대상이다
  end
  return ("%s  |  모드: %s  |  색인: %s"):format(rel,
    name and ("preset '" .. name .. "'") or 'auto',
    inlist and '포함' or '제외')
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

local function global_lines(root, args, timeout)
  local cmd = { global_cmd() }
  if not cmd[1] then
    return {}
  end
  vim.list_extend(cmd, args)
  local ok, o = pcall(function()
    return vim.system(cmd, { text = true, cwd = root,
      env = { GTAGSOBJDIR = dbdir() } }):wait(timeout or 4000)
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
local db_stat   -- 아래에서 정의: 색인 데이터베이스의 stat

-- root -> { key = <파일 stat>, list = {...} }
-- \fo 는 누를 때마다 이 목록을 통째로 다시 읽었다. 커널 트리에서 46,000 줄
-- 이라 그 자체가 100ms 대의 정지였고, 목록이 바뀌지도 않았는데 매번 그랬다.
--   let g:projectfiles_files_cache = 0   " 항상 다시 읽기
local files_cache = {}

local function current_files(root)
  local d = dbdir() or '.tags'
  local list = root .. '/' .. d .. '/files'
  local st = uv.fs_stat(list)
  if st then
    -- 초 단위 mtime 만으로는 같은 초 안에 다시 쓰인 목록을 놓친다: 크기와
    -- 나노초까지 키에 넣는다
    local key = ('%d:%d:%d'):format(st.mtime.sec, st.mtime.nsec or 0, st.size)
    local c = files_cache[root]
    if cfg('files_cache', 1) ~= 0 and c and c.key == key then
      return c.list
    end
    local out = vim.fn.readfile(list)
    files_cache[root] = { key = key, list = out }
    return out
  end
  local fl = vim.fn.expand('~/.local/bin/indexfiles.sh')
  if vim.fn.executable(fl) == 1 then
    -- 목록 파일이 없는 트리(예전 mktags.sh 로 만든 색인)에서는 \fo 를 누를
    -- 때마다 44,000 파일을 훑는 스크립트가 통째로 돌았다. 색인이 그대로면
    -- 목록도 그대로라고 보고 색인 stat 을 키로 삼는다. 색인을 다시 만들면
    -- (F2 / :GtagsIndex) 키가 바뀌어 자동으로 새로 읽는다.
    local st2 = db_stat(root)
    local key = st2 and ('gt:%d:%d'):format(st2.mtime.sec, st2.size) or nil
    local c = key and files_cache[root]
    if cfg('files_cache', 1) ~= 0 and c and c.key == key then
      return c.list
    end
    local o = vim.fn.systemlist({ 'sh', '-c', 'cd ' .. vim.fn.shellescape(root)
      .. ' && ' .. vim.fn.shellescape(fl) })
    local out = {}
    for _, l in ipairs(o) do
      l = l:gsub('^%./', '')
      if l ~= '' then
        out[#out + 1] = l
      end
    end
    if key and #out > 0 then
      files_cache[root] = { key = key, list = out }
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
  elseif vim.bo.buftype == '' then
    vim.cmd('edit ' .. vim.fn.fnameescape(abs))
  else
    -- every window is a panel/preview/terminal: make one rather than
    -- replacing a special buffer (or failing with a stack traceback)
    vim.cmd('botright split ' .. vim.fn.fnameescape(abs))
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

-- ---------------------------------------------------------------------------
-- symbols in the index (telescope)
-- ---------------------------------------------------------------------------
-- 'global -x -d' hands over every definition the database holds - name,
-- line, file and the source line - and it answers in milliseconds even for
-- a kernel-sized index (31k definitions in ~10 ms here), so the whole list
-- goes into the picker and telescope (fzf-native) does the filtering. The
-- list is built once per database and rebuilt after a re-index.

-- what kind of thing a definition line defines. Cosmetic, but it is what
-- makes a list of 30000 names readable: the struct and the function that
-- share a name are told apart at a glance.
-- the column of 'name' in 'text' as a WHOLE word. A plain find lands inside
-- a longer identifier on 866 of this index's 31480 definitions
-- ('SR_FGT(SYS_AFSR0_EL1, HFGxTR, AFSR0_EL1, 1)' when looking for
-- AFSR0_EL1), which would leave the cursor - and therefore <cword>, and the
-- next C-] - on the wrong symbol.
local function word_col(text, name)
  local at = 1
  while true do
    local b, e = text:find(name, at, true)
    if not b then
      return nil
    end
    local before = b > 1 and text:sub(b - 1, b - 1) or ''
    local after = text:sub(e + 1, e + 1)
    if not before:match('[%w_]') and not after:match('[%w_]') then
      return b
    end
    at = e + 1
  end
end

local function symbol_kind(name, text)
  local t = text:gsub('^%s+', '')
  if t:match('^#%s*define') then
    return t:match('^#%s*define%s+' .. vim.pesc(name) .. '%s*%(') and 'macro()'
        or 'macro'
  end
  if t:match('^typedef') then
    return 'typedef'
  end
  for _, kw in ipairs({ 'struct', 'union', 'enum' }) do
    if t:match('^' .. kw .. '[%s{]') then
      if t:match('^' .. kw .. '%s+' .. vim.pesc(name) .. '[%s{;,]')
          or t:match('^' .. kw .. '%s+' .. vim.pesc(name) .. '$') then
        return kw -- the tag itself
      end
      -- the name is something INSIDE that definition: a member, or one of
      -- the values of a single-line 'enum { A, B }'
      return kw == 'enum' and 'enum val' or 'member'
    end
  end
  -- the same whole-word rule as the cursor: a plain find would see the '('
  -- of a LONGER identifier ('SR_FGT(SYS_AFSR0_EL1, ...)' when the symbol is
  -- AFSR0_EL1) and call 167 rows of this index functions
  local at = word_col(t, name)
  if at and t:sub(at + #name):match('^%s*%(') then
    return 'func'
  end
  if t:match('^[%u_][%u%d_]*%s*[=,]') then
    return 'enum val'
  end
  return 'var'
end

-- the paths the database holds, as a set. 'global -x' separates the path
-- from the source line with spaces and quotes nothing, so a path with a
-- space in it can only be recovered by asking which paths exist.
-- 색인된 경로 전부. 공백이 든 경로를 되살릴 때만 쓰인다.
--
-- 커널 트리에서 'global -P' 자체가 49ms 인데, 접두어를 바꿔 가며 검색하면
-- 심볼 캐시가 무효화되면서 매번 다시 돌았다. 이건 접두어와 무관하므로
-- 데이터베이스가 바뀌지 않는 한 한 번만 읽는다.
--   let g:projectfiles_path_cache = 0   " 매번 다시 읽기
local paths_cache = {}   -- root -> { key =, set =, n = }

local function indexed_paths(root)
  local st = db_stat(root)
  local key = st and ('%d:%d'):format(st.mtime.sec, st.size) or 'none'
  local c = paths_cache[root]
  if cfg('path_cache', 1) ~= 0 and c and c.key == key then
    return c.set, c.n
  end
  local set, n = {}, 0
  for _, l in ipairs(global_lines(root, { '-P', '' })) do
    local rel = l:gsub('^%./', '')
    if rel ~= '' then
      set[rel] = true
      n = n + 1
    end
  end
  if n > 0 then
    paths_cache[root] = { key = key, set = set, n = n }
  end
  return set, n
end

-- 'global' answers from the database GTAGSOBJDIR points at, so the cache has
-- to be keyed on the same one - and on its size, because mtime seconds alone
-- would serve a stale list after a re-index that finished inside the same
-- second ('global --single-update' takes about 20 ms).
db_stat = function(root)
  local d = dbdir()
  if d and d ~= '' then
    local st = uv.fs_stat(root .. '/' .. d .. '/GTAGS')
    if st then
      return st
    end
  end
  return uv.fs_stat(root .. '/GTAGS')
end

-- A whole kernel tree in auto mode holds millions of definitions: dumping
-- all of them would build millions of Lua tables and freeze nvim. Past this
-- much database, the picker asks 'global' for the prefix that was typed
-- instead of for everything.
local function huge_db(st)
  return st ~= nil
      and st.size > (cfg('symbol_db_max_mb', 40) * 1024 * 1024)
end

local function symbols_of(root, prefix)
  local st = db_stat(root)
  local key = st and (tostring(st.mtime.sec) .. ':' .. tostring(st.size))
      or 'none'
  key = key .. '\0' .. (prefix or '')
  local hit = s.symbols and s.symbols[root]
  if hit and hit.key == key then
    return hit.list
  end
  local pat = '.*'
  if prefix and prefix ~= '' then
    pat = '^' .. prefix:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?{}|\\]', '\\%0')
  end
  -- 공백이 든 경로('my dir/a b.c')를 되살리는 데 쓴다. 이 트리에 그런 경로가
  -- 하나도 없어도 목록 자체는 필요하다 - 어떤 줄이 잘렸는지는 이걸 봐야만
  -- 알 수 있고, global -P 는 경로 패턴으로 걸러 주지 않는다(실측: 패턴을
  -- 무시하고 전부 돌려준다). 대신 indexed_paths 를 캐시해 두어서, 접두어를
  -- 바꿔 가며 검색해도 데이터베이스당 한 번만 읽는다.
  local known, npaths = indexed_paths(root)
  local list = {}
  local cap = cfg('symbol_max', 200000)
  -- a whole definition dump is worth more than four seconds: on a timeout
  -- vim.system kills global and its output is lost, and with nothing cached
  -- every '\fs' would pay that wait again
  for _, l in ipairs(global_lines(root, { '-x', '-d', '-e', pat },
      cfg('symbol_timeout', 20000))) do
    if #list >= cap then
      break
    end
    -- 'name  line  path  text', the columns padded by global
    local name, line, rest = l:match('^(%S+)%s+(%d+)%s+(.*)$')
    local path, text = nil, nil
    if name then
      path, text = rest:match('^(%S+)%s+(.*)$')
      if path and npaths > 0 and not known[path] then
        -- the path holds a space: take tokens from the text until the
        -- database recognises what we have
        local acc, tail = path, text or ''
        for _ = 1, 8 do
          local tok, more = tail:match('^(%S+)%s*(.*)$')
          if not tok then
            break
          end
          acc, tail = acc .. ' ' .. tok, more
          if known[acc] then
            path, text = acc, tail
            break
          end
        end
      end
    end
    if name and path then
      local kind = symbol_kind(name, text or '')
      list[#list + 1] = {
        name = name, line = tonumber(line), path = path,
        text = ((text or ''):gsub('^%s+', ''):gsub('%s+$', '')),
        kind = kind,
        -- never truncate the name: 924 names here are longer than the
        -- column, and 176 of them share a 32-character prefix with another
        display = ('%-32s %-8s %s:%d'):format(name, kind, path, line),
        ordinal = name .. ' ' .. path,
      }
    end
  end
  if #list == 0 then
    return list -- a failed 'global' run must not be remembered as "no symbols"
  end
  s.symbols = s.symbols or {}
  s.symbols[root] = { key = key, list = list, capped = #list >= cap }
  return list
end

-- jump to a definition in a real source window (never the panel or the
-- preview), leaving the jumplist intact so C-o comes back
local function jump_to_symbol(root, e)
  local abs = e.path:sub(1, 1) == '/' and e.path or (root .. '/' .. e.path)
  -- the database can outlive the file: opening it would silently make an
  -- empty buffer under that name, which a later ':w' would turn into a file
  if not uv.fs_stat(abs) then
    notify(('%s 는 더 이상 없습니다 (색인이 오래되었습니다: <leader>fR)')
      :format(e.path), vim.log.levels.WARN)
    return
  end
  -- the jumplist entry belongs to where we are NOW: nvim_win_set_buf pushes
  -- one by itself, and an 'm\'' after the switch would mark the file we just
  -- landed in instead
  pcall(vim.cmd, [[normal! m']])
  local ok = pcall(open_in_edit, root, e.path)
  if not ok then
    notify('편집할 창을 찾지 못했습니다: ' .. e.path, vim.log.levels.WARN)
    return
  end
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  -- and the file can have changed since it was indexed
  local last = api.nvim_buf_line_count(buf)
  local line = math.max(1, math.min(e.line, last))
  local text = api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ''
  local at = word_col(text, e.name) or text:find(e.name, 1, true)
  pcall(api.nvim_win_set_cursor, win, { line, at and (at - 1) or 0 })
  pcall(vim.cmd, 'normal! zz')
  if line ~= e.line then
    notify(('%s:%d 은 파일 끝을 넘어갑니다 (색인이 오래되었습니다: <leader>fR)')
      :format(e.path, e.line), vim.log.levels.WARN)
  elseif _G.relationview_flash then
    pcall(_G.relationview_flash, buf, line, e.name)
  end
end

-- \fs is often pressed while the cursor sits in the relation panel or its
-- preview - both 'nofile' buffers, for which cur_root() falls back to the
-- cwd and would answer for the wrong project. Prefer a real source buffer
-- from this tab.
local function symbol_root()
  if vim.bo.buftype == '' and api.nvim_buf_get_name(0) ~= '' then
    return cur_root()
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    local n = api.nvim_buf_get_name(b)
    if vim.bo[b].buftype == '' and n ~= '' and not n:match('RelationView') then
      return root_of(n)
    end
  end
  return cur_root()
end

-- <leader>fs : find any symbol the index knows and jump to its definition
local function pick_symbol(prefill)
  local root = symbol_root()
  local st = db_stat(root)
  local huge = huge_db(st)
  if huge and (prefill == nil or #prefill < 2) then
    notify(('색인이 커서(%d MB) 접두어가 필요합니다: '):format(
        math.floor((st and st.size or 0) / 1024 / 1024))
      .. ':ProjectSymbols <접두어> 또는 <leader>fw (커서 밑 심볼)',
      vim.log.levels.WARN)
    return
  end
  local syms = symbols_of(root, huge and prefill or nil)
  if #syms == 0 then
    local d = dbdir() or '.tags'
    local why
    if not global_cmd() then
      why = 'GNU Global(global) 을 찾을 수 없습니다'
    elseif not uv.fs_stat(root .. '/' .. d .. '/GTAGS')
        and not uv.fs_stat(root .. '/GTAGS') then
      why = '이 프로젝트에 색인이 없습니다 (:GtagsIndex)'
    elseif prefill == nil or prefill == '' then
      why = 'global 이 정의를 돌려주지 않았습니다 - 접두어로 좁혀보세요'
          .. ' (:ProjectSymbols <접두어>, 또는 :GtagsIndexStatus 로 확인)'
    else
      why = ("'%s' 로 시작하는 정의가 없습니다"):format(prefill)
    end
    notify(why, vim.log.levels.WARN)
    return
  end
  local t = telescope()
  if not t then
    -- no telescope: narrow by the prefill and let vim.ui.select do it
    local items, map = {}, {}
    local want = prefill and prefill ~= '' and prefill:lower() or nil
    local more = false
    for _, e in ipairs(syms) do
      if want == nil or e.name:lower():find(want, 1, true) then
        if #items >= 200 then
          more = true
          break
        end
        items[#items + 1] = e.display
        map[e.display] = e
      end
    end
    return fallback_select(items,
      more and 'Project symbols (앞 200개만)' or 'Project symbols',
      function(c)
        if map[c] then
          jump_to_symbol(root, map[c])
        end
      end)
  end
  t.pickers.new({}, {
    prompt_title = ('Symbols %d  <CR> jump  <F3> relation'):format(#syms),
    default_text = prefill,
    finder = t.finders.new_table({
      results = syms,
      entry_maker = function(e)
        return { value = e, display = e.display, ordinal = e.ordinal,
          filename = root .. '/' .. e.path, lnum = e.line, col = 1,
          text = e.text }
      end,
    }),
    sorter = t.conf.generic_sorter({}),
    previewer = t.conf.grep_previewer({}),
    attach_mappings = function(bufnr, map)
      t.actions.select_default:replace(function()
        local entry = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if entry then
          -- after the prompt closes: leaving insert mode moves the cursor
          -- one column left, which would take it off the symbol
          vim.schedule(function() jump_to_symbol(root, entry.value) end)
        end
      end)
      -- the relation window answers the next question ('who calls this?').
      -- Not <C-r>: telescope owns that as the prefix of <C-r><C-w> and
      -- friends, so a bare mapping there waits for a second key and then
      -- leaks it. <F3> is what opens the relation window outside telescope.
      local to_relation = function()
        local entry = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if entry then
          vim.schedule(function()
            pcall(vim.cmd, 'RelationView ' .. vim.fn.fnameescape(entry.value.name))
          end)
        end
      end
      map({ 'i', 'n' }, '<F3>', to_relation)
      map({ 'i', 'n' }, '<C-g>', to_relation)
      return true
    end,
  }):find()
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
        -- <Tab> 으로 여러 개를 골랐으면 한 번만 펼치고 한 번만 재색인한다
        in_batch(root, '추가', function()
          for _, e in ipairs(picks) do
            add_with_related(root, e.value)
          end
        end)
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
    if l ~= '' and l ~= '.' and not have[l]
        and not (cfg('nested_presets', 0) ~= 0
          and nested_owner(root, l .. '/')) then
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
        in_batch(root, '추가', function()
          for _, e in ipairs(picks) do
            add_path(root, e[1] or e.value)
          end
        end)
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
    -- say where a preset comes from: the ones vim-ide carries are on every
    -- machine, mine are only here. When both exist mine is the one in use,
    -- so show when it has drifted from what the repository holds - that is
    -- the case where a 'git pull' looks like it did nothing (^d drops my
    -- copy and follows the shared one again).
    local mine = read_preset_file(preset_path(n))
    local sh = read_preset_file(shared_path(n))
    local p = mine or sh
    local tag = ''
    if sh and mine then
      tag = entries_differ(mine.entries, sh.entries)
          and ('  [내 사본 ≠ vim-ide %d개]'):format(#sh.entries)
          or '  [vim-ide]'
    elseif sh then
      tag = '  [vim-ide]'
    end
    items[#items + 1] = { name = n, label = ('%s%s  (%d entries)%s')
      :format(cur == n and '● ' or '  ', n, p and #p.entries or 0, tag) }
  end
  local function use(it)
    set_active(root, it.name or '')
    materialize(root)
    reindex(root)
    notify(it.name and ("preset '" .. it.name .. "'") or 'auto 모드')
    announce_fork(it.name)
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
        in_batch(root, '제거', function()
          for _, e in ipairs(picks) do
            drop(e[1] or e.value)
          end
        end)
      end)
      return true
    end,
  }):find()
end

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------
-- 인자로 절대 경로를 받으면 그 경로가 속한 프로젝트가 맞다.
--
-- cur_root() 는 현재 버퍼(이름이 없으면 cwd)를 본다. 이름 없는 버퍼에서 -
-- 트리 창, telescope 프롬프트, :enew - 다른 프로젝트의 절대 경로를 주면
-- 엉뚱한 프로젝트의 목록에 그 경로가 들어가고, 재색인도 그쪽으로 간다.
-- 상대 경로는 지금까지처럼 '프로젝트 기준'으로 남긴다(abs_of 가 그렇게 푼다).
local function root_for_arg(arg)
  local a = tostring(arg or '')
  if a:sub(1, 1) == '~' then
    a = vim.fn.expand(a)
  end
  if a:sub(1, 1) == '/' then
    local r = root_of(a)
    announce_root(r)
    return r
  end
  return cur_root()
end

api.nvim_create_user_command('ProjectFiles', function() pick_find() end,
  { desc = 'Find a project file (telescope) - ^a add, ^d remove' })
api.nvim_create_user_command('ProjectFilesFind', function() pick_find() end,
  { desc = 'Find a project file and jump to it' })

api.nvim_create_user_command('ProjectFilesAdd', function(o)
  if o.args == '' then
    pick_add()
    return
  end
  add_with_related(root_for_arg(o.args), o.args)
end, { nargs = '?', complete = 'file',
  desc = 'Add a file/directory (with the headers and definitions it uses)' })

api.nvim_create_user_command('ProjectFilesRemove', function(o)
  if o.args == '' then
    pick_remove()
    return
  end
  remove_path(root_for_arg(o.args), o.args)
end, { nargs = '?', complete = 'file', desc = 'Remove a file/directory' })

api.nvim_create_user_command('ProjectFilesAddDir', function(o)
  if o.args == '' then
    pick_add_dir()
    return
  end
  add_path(root_for_arg(o.args), o.args)
end, { nargs = '?', complete = 'dir',
  desc = 'Add a directory (everything indexable under it)' })

-- 모드를 지금 다시 고른다. 시작할 때 뜨는 것과 같은 다이얼로그다.
api.nvim_create_user_command('ProjectFilesMode', function()
  local root = cur_root()
  choose_mode(root, function(ok)
    if ok then
      reindex(root)
    end
  end)
end, { desc = 'Pick the indexing mode for this project (auto / a preset)' })

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
  if o.args ~= 'auto' then
    announce_fork(o.args)
  end
end, { nargs = '?', complete = function()
  local n = preset_list()
  table.insert(n, 1, 'auto')
  return n
end, desc = 'Use a preset (auto = whole project)' })

api.nvim_create_user_command('ProjectFilesSave', function(o)
  local root = cur_root()
  local entries, _, bad = entries_of(root)
  if bad then
    return -- 읽을 수 없는 preset을 빈 목록으로 덮어쓰지 않는다
  end
  entries = entries or {}
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

api.nvim_create_user_command('ProjectSymbols', function(o)
  pick_symbol(o.args ~= '' and o.args or nil)
end, { nargs = '?', complete = function(arg)
  if #arg < 2 then
    return {}
  end
  local out = {}
  for _, n in ipairs(global_lines(cur_root(), { '-c', arg })) do
    out[#out + 1] = n
    if #out >= 100 then
      break
    end
  end
  return out
end, desc = 'Find a symbol in the index and jump to its definition' })

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
