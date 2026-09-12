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
--   :ProjectFilesPreset [name] switch mode: 'none' / 'auto' / a preset; no
--                              argument lists what there is
--   :ProjectFilesSave <name>   save the current entries as a preset
--   :ProjectFilesPresetShare [name]
--                              copy a preset into vim-ide (shared with the
--                              other machines after a commit/push)
--   :ProjectFilesMode          pick the indexing mode (the dialog that comes
--                              up on startup when a project has none yet)
--   :ProjectFilesAbsorb        pull the index lists of nested projects (a
--                              subdirectory with its own '.tags') into this
--                              project's preset, rebased on this root
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
--   (g:projectfiles_ask_mode 는 더 쓰이지 않는다: 모드를 정하지 않은
--    디렉터리에서는 묻지도 색인하지도 않고, <F2>/\fm 으로 고른다)
--   g:projectfiles_ask_mode    (옛 옵션) 1 (default): a project whose mode was never
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
--   g:projectfiles_names       indexed by exact name, for files with no
--                              extension (default 'Makefile makefile
--                              Kconfig Kbuild')
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

-- 색인 목록에 넣을 파일: 확장자로 고르는 것과, 이름 그대로 고르는 것.
--
-- 'Makefile' 처럼 확장자가 없는 파일이 있어서 두 벌이 필요하다.
-- indexfiles.sh 와 autoindex.lua 의 같은 목록과 맞춰 두어야 한다 - 세
-- 군데가 어긋나면 auto 모드와 preset 모드가 서로 다른 파일을 색인한다.
--
-- gtags 가 심볼까지 읽는 것은 C/C++/Java/asm 정도다. 나머지(.py, .xml,
-- .json, .bp, .bb, Makefile …)는 목록에만 들어간다 - \fo 로 찾아 열 수는
-- 있고, ctags 쪽(gutentags / :CtagsIndex)은 python·java·make 도 읽는다.
-- .dts/.dtsi 가 원래 그런 상태였다.
--
--   let g:projectfiles_exts  = 'c h cpp java …'   " 확장자
--   let g:projectfiles_names = 'Makefile Kconfig' " 이름 그대로
local DEFAULT_EXTS = table.concat({
  'c cc cpp cxx h hh hpp hxx s',
  'S java kt kts rs aidl py pl sh',
  'bash zsh',
  'ksh awk lua vim tcl mk mak cmake gradle',
  'pro bp bb bbappend bbclass inc dts dtsi xml',
  'json yaml yml toml ini cfg conf properties env',
  'rc reg md txt rst ld lds def map',
  'te pc',
}, ' ')
local DEFAULT_NAMES = table.concat({
  'Makefile makefile GNUmakefile Kconfig Kbuild BUILD WORKSPACE Dockerfile README',
  'LICENSE NOTICE',
}, ' ')

-- 기본은 '모든 파일'이다. 확장자 허용목록으로 고르면 새 언어나 설정 파일이
-- 나올 때마다 목록을 늘려야 하고, 그때까지 그 파일은 색인에 없다.
-- 그래서 반대로 뒤집었다: 전부 넣고, 넣어서 해로운 것만 뺀다.
--
-- 빼는 것은 산출물과 바이너리다. 목록에 넣어도 열어 볼 일이 없고, 수만
-- 개가 들어와 피커와 색인을 느리게 만든다(.o/.so/.png/.zip …).
--
-- 확장자보다 디렉터리 가지치기가 훨씬 크게 듣는다. 실측: QNX+Android SDK
-- 트리에서 '모든 파일'이 222,616개였고 그중 221,151개가 'android/out/' 한
-- 곳에 있었다(Android 빌드 산출물). 그래서 'out' 은 기본으로 가지치기
-- 한다. 'build' 는 하지 않는다 - 이 트리의 android/build 는 진짜 소스다.
--   let g:projectfiles_prune_dirs = '.git out build .gradle'
--
--   let g:projectfiles_all_files = 0        " 예전처럼 허용목록만
--   let g:projectfiles_exclude_exts_extra = 'log bak'
local EXCLUDE_EXTS = table.concat({
  'o a so ko obj lo la exe',
  'dll dylib bin img elf hex bpf gz',
  'bz2 xz zst lz4 zip tar tgz tbz',
  'jar apk aar dex odex vdex rar 7z',
  'iso dmg png jpg jpeg gif bmp ico',
  'webp tiff tif psd svgz mp3 mp4 avi',
  'mkv wav flac ogg opus webm pdf doc',
  'docx xls xlsx ppt pptx odt ods pyc',
  'pyo pyd class pdb ilk exp d cmd',
  'pack idx swp swo swn ttf otf woff',
  'woff2 eot db sqlite sqlite3 dat rom fw',
  'uimage',
  'flat rsp srcjar kapt_metadata jack toc lst gcno',
  'gcda su i ii stamp timestamp',
}, ' ')
local EXCLUDE_NAMES = table.concat({
  'tags TAGS cscope.out cscope.in.out cscope.po.out GTAGS GRTAGS GPATH',
  'core .DS_Store',
}, ' ')

local EXT, BASE = {}, {}
-- exts/names 를 통째로 갈아치우는 대신 덧붙이고 싶을 때가 대부분이다:
--   let g:projectfiles_exts_extra = 'proto gn'
for e in tostring(cfg('exts', DEFAULT_EXTS)):gmatch('%S+') do
  EXT[e] = true
end
for e in tostring(cfg('exts_extra', '')):gmatch('%S+') do
  EXT[e] = true
end
for b in tostring(cfg('names', DEFAULT_NAMES)):gmatch('%S+') do
  BASE[b] = true
end
for b in tostring(cfg('names_extra', '')):gmatch('%S+') do
  BASE[b] = true
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

-- 표시(marker)나 색인이 실제로 있는 루트만 돌려준다. root_from_dir 은 아무
-- 것도 못 찾으면 cwd 를 돌려주는데, 그건 '프로젝트를 찾았다'가 아니다.
local function marked_root(dir)
  local r = root_from_dir(dir)
  if not r or r == '' then
    return nil
  end
  local hidden = dbdir()
  if (hidden and uv.fs_stat(r .. '/' .. hidden .. '/GTAGS'))
      or uv.fs_stat(r .. '/GTAGS') then
    return r
  end
  for _, m in ipairs({ '.git', '.project', '.root' }) do
    if uv.fs_stat(r .. '/' .. m) then
      return r
    end
  end
  return nil
end

-- 어느 프로젝트의 목록에 담는가 - 현재 디렉터리(nvim 을 띄운 곳) 기준.
--
-- 하위 디렉터리가 자기 '.tags' 를 갖고 있으면 위로 올라가는 탐색은 그
-- 하위 프로젝트를 답한다. 그러면 상위 트리에서 작업하는 동안 \fo / \fp /
-- NERDTree 가 하위 프로젝트의 목록을 보여 주고 담는 것도 그쪽으로 가서,
-- '지금 보고 있는 프로젝트'와 어긋난다. 그래서 cwd 의 프로젝트가 그 경로를
-- 품고 있으면 그 프로젝트를 기준으로 삼는다.
--
-- $HOME 이나 / 처럼 표시가 없는 곳에서 띄웠으면 고정하지 않는다(모든 것을
-- 한 프로젝트로 삼아 버린다).
--   let g:projectfiles_anchor_cwd = 0   " 경로가 속한 프로젝트를 그대로 쓴다
local function root_of(path)
  local dir = path and path ~= '' and vim.fs.dirname(vim.fn.fnamemodify(path, ':p'))
      or vim.fn.getcwd()
  local r = root_from_dir(dir)
  if cfg('anchor_cwd', 1) == 0 then
    return r
  end
  local base = marked_root(vim.fn.getcwd())
  local home = vim.fn.expand('~')
  if base and base ~= r and base ~= home and base ~= '/'
      and (dir == base or dir:sub(1, #base + 1) == base .. '/') then
    return base
  end
  return r
end

-- sihlindex.lua 가 같은 규칙으로 프로젝트를 고르게 내준다.
-- (현재 디렉터리 기준 고정까지 포함 - anchor_cwd)
function _G.projectfiles_root_of(path)
  local ok, r = pcall(root_of, path)
  return ok and r or nil
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

-- 항목 경로를 preset 에 담기 전에 다듬는다.
--
-- grep 폴백('grep -rl ... .')의 출력은 './android/...' 처럼 './' 를 달고
-- 나오고, add_for_symbol 은 그것을 rel_to 를 거치지 않고 그대로 담았다.
-- 그렇게 담긴 항목은 문자열 비교로 찾을 수 없어서 제거도 안 되고 중복도
-- 생긴다. 저장 직전에 한 곳에서 다듬으면 어느 경로로 들어와도 같은 모양이
-- 된다.
local function norm_rel(path)
  local p = tostring(path or ''):gsub('/+', '/')
  while p:sub(1, 2) == './' do
    p = p:sub(3)
  end
  return (p:gsub('/+$', ''))
end

-- 같은 경로가 두 번 담기지 않게 한다.
--
-- remove_path 는 디렉터리 항목 아래의 파일 하나를 빼라고 하면 그 디렉터리를
-- 개별 파일 목록으로 펼쳐 되쓴다. 그때 이미 목록에 있던 파일과 겹치는지
-- 보지 않아서, 실제로 telechips_dpcm/ 아래 21개가 두 번씩 들어간 적이 있다.
local function dedupe_entries(entries)
  local seen, out, dropped = {}, {}, 0
  for _, e in ipairs(entries) do
    local path = norm_rel(e.path)
    if path == '' then
      dropped = dropped + 1
    elseif seen[path] then
      dropped = dropped + 1
    else
      seen[path] = true
      out[#out + 1] = { path = path, kind = e.kind or 'file' }
    end
  end
  return out, dropped
end

-- 저장 직전의 사본.
--
-- preset 쓰기는 제자리 truncate 다 - 되돌릴 방법이 없었다. 트리에서
-- 디렉터리 하나에 '-' 를 누르면 그 아래 항목이 전부 빠지는데(의도된
-- 동작이다), 그렇게 487개가 한 번에 사라진 뒤 남은 흔적이 아무것도 없었다.
-- 그래서 쓰기 전마다 사본을 남기고 최근 것만 돌려 둔다.
--   let g:projectfiles_backups = 0   " 백업 끄기
local function backup_preset(name)
  local keep = tonumber(cfg('backups', 20)) or 20
  if keep <= 0 then
    return nil
  end
  local src = preset_path(name)
  if not uv.fs_stat(src) then
    return nil -- 아직 없는 preset: 지킬 것이 없다
  end
  local dir = presets_dir() .. '/.backup'
  local base = name:gsub('[^%w%-_.]', '_')
  local dst = ('%s/%s.%s.json'):format(dir, base, os.date('%Y%m%d-%H%M%S'))
  if uv.fs_stat(dst) then
    return dst -- 같은 초에 두 번 저장: 먼저 남긴 것이 원본에 더 가깝다
  end
  pcall(vim.fn.mkdir, dir, 'p')
  local lines = nil
  local ok = pcall(function()
    lines = vim.fn.readfile(src)
  end)
  if not ok or not lines then
    return nil
  end
  if not write_json(dst, lines) then
    return nil
  end
  -- 오래된 것부터 버린다 (이름에 시각이 들어 있으니 이름순 = 시간순)
  local mine = {}
  local h = uv.fs_scandir(dir)
  while h do
    local n = uv.fs_scandir_next(h)
    if not n then
      break
    end
    if n:sub(1, #base + 1) == base .. '.' and n:sub(-5) == '.json' then
      mine[#mine + 1] = n
    end
  end
  table.sort(mine)
  for i = 1, #mine - keep do
    pcall(vim.fn.delete, dir .. '/' .. mine[i])
  end
  return dst
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
  local clean, dupes = dedupe_entries(entries)
  if dupes > 0 then
    notify(('중복 항목 %d개를 합쳤습니다 (%d -> %d)'):format(
      dupes, #entries, #clean))
  end
  entries = clean
  backup_preset(name)
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

-- auto 로 되돌아가며 잃어버린 preset 이름. 되돌리기(:ProjectFilesRestore)가
-- 백업을 찾으려면 이름이 필요한데, 목록이 비면 set_active(root,'') 로 이름을
-- 지워 버려서 정작 가장 필요한 순간에 찾을 수 없었다.
local function last_file(root)
  local d = dbdir() or '.tags'
  return root .. '/' .. d .. '/preset.last'
end

local function last_preset(root)
  local f = last_file(root)
  if not uv.fs_stat(f) then
    return nil
  end
  local l = (vim.fn.readfile(f)[1] or ''):gsub('%s+$', '')
  return l ~= '' and l or nil
end

local function set_last(root, name)
  local f = last_file(root)
  pcall(vim.fn.mkdir, vim.fs.dirname(f), 'p')
  pcall(vim.fn.writefile, { name or '' }, f)
end

-- 색인 모드는 셋이다.
--
--   none          아무것도 하지 않는다. 프로젝트로 등록만 되어 있다.
--   auto          프로젝트 전체를 색인한다 (git ls-files / find).
--   <preset 이름>  그 목록만 색인한다.
--
-- 그리고 '.tags/preset 이 아예 없는' 네 번째 상태가 있다: 아직 아무것도
-- 정하지 않은 디렉터리다. 그런 곳에서는 vim 을 켜도 아무 일도 하지 않는다 -
-- 남의 트리나 홈 디렉터리에서 잠깐 파일을 열었을 뿐인데 색인이 시작되는
-- 일이 없어야 한다. 모드를 고르는 것은 <F2> 나 \fm 이다.
--
-- 파일 내용이 곧 모드다. 예전 파일은 '빈 줄 = auto' 였으므로 그대로 읽어
-- 준다(그때는 none 이 없었다).
local MODE_NONE = 'none'
local MODE_AUTO = 'auto'
local MODE_UNSET = '\0unset'

local function mode_of(root)
  local f = active_file(root)
  if not uv.fs_stat(f) then
    -- g:projectfiles_preset 을 정해 뒀으면 그것이 기본값이다
    local d = cfg('preset', nil)
    return d and tostring(d) or MODE_UNSET
  end
  local l = (vim.fn.readfile(f)[1] or ''):gsub('%s+$', '')
  if l == '' then
    return MODE_AUTO -- 예전 파일: 빈 줄이 '명시적 auto' 였다
  end
  return l
end

-- 이 프로젝트가 쓰는 preset 이름 (auto/none/미설정이면 nil).
local function active_preset(root)
  local m = mode_of(root)
  if m == MODE_AUTO or m == MODE_NONE or m == MODE_UNSET then
    return nil
  end
  return m
end

-- 자동으로(시작할 때, 저장할 때) 색인해도 되는 프로젝트인가.
local function mode_indexes(root)
  local m = mode_of(root)
  return m ~= MODE_NONE and m ~= MODE_UNSET
end

local function set_active(root, name)
  local f = active_file(root)
  vim.fn.mkdir(vim.fs.dirname(f), 'p')
  -- '' 는 예전 호출부가 'auto' 를 뜻하며 쓰던 값이다. 이제는 글자로 적는다 -
  -- 파일만 보고도 무슨 모드인지 알 수 있어야 한다.
  local v = name
  if v == nil or v == '' then
    v = MODE_AUTO
  end
  pcall(vim.fn.writefile, { v }, f)
end

-- autoindex.lua 가 색인을 시작하기 전에 물어보는 자리.
function _G.projectfiles_mode(root)
  if not root or root == '' then
    return MODE_UNSET
  end
  local m = mode_of(root)
  return m == MODE_UNSET and 'unset' or m
end

function _G.projectfiles_should_index(root)
  if not root or root == '' then
    return false
  end
  return mode_indexes(root)
end

-- 경로가 속한 프로젝트가 색인 대상인가. gutentags 는 자기 루트 판정
-- (.git/.project/.root)을 쓰는데 모드는 '<projectfiles 루트>/.tags/preset'
-- 에 있으므로, 루트가 아니라 파일 경로로 물어야 답이 맞는다.
function _G.projectfiles_should_index_file(path)
  path = tostring(path or '')
  if path == '' then
    return false
  end
  local ok, root = pcall(root_of, path)
  if not ok or not root or root == '' then
    return false
  end
  return mode_indexes(root)
end

-- 색인 목록이 어느 .tags 에 저장되는지 한 줄로. NERDTree/피커/커맨드가
-- 모두 이걸 보여 준다 - '어디에 담겼는지'를 화면에서 알 수 있어야 한다.
--   ~/work2/.../d5_qnx_hyp/.tags [qnx_hypervisor_ivi_sdk_d5]
local function target_label(root)
  local d = dbdir() or '.tags'
  local m = mode_of(root)
  return ('%s/%s [%s]'):format(vim.fn.fnamemodify(root, ':~'), d,
    m == MODE_UNSET and '미설정' or m)
end

-- ---------------------------------------------------------------------------
-- expanding a preset into a file list
-- ---------------------------------------------------------------------------
local EXCL, EXCL_NAME = {}, {}
for e in tostring(cfg('exclude_exts', EXCLUDE_EXTS)):gmatch('%S+') do
  EXCL[e:lower()] = true
end
for e in tostring(cfg('exclude_exts_extra', '')):gmatch('%S+') do
  EXCL[e:lower()] = true
end
for b in tostring(cfg('exclude_names', EXCLUDE_NAMES)):gmatch('%S+') do
  EXCL_NAME[b] = true
end
for b in tostring(cfg('exclude_names_extra', '')):gmatch('%S+') do
  EXCL_NAME[b] = true
end

-- 색인에서 뺀 것을 한 번만 보고하기 위한 집계 (materialize 가 읽는다)
local skipped = { big = 0, binary = 0, worst = nil }

-- 확장자만으로는 걸러지지 않는 것: 이름에 점이 없는 바이너리.
--
-- '전부 넣는다'(all_files)는 확장자 거부목록으로만 판단하고 있었다. 그래서
-- 확장자가 없는 'qnx/disk/qnx-ifs'(64MB QNX IFS 이미지),
-- 'qnx/disk/guests/android/kernel-6.1'(33MB EFI 실행파일),
-- '*.sym'(15MB ELF)이 색인 목록에 그대로 들어갔다. 실측(d5_qnx_hyp):
-- 목록 1540개 중 83개가 바이너리로 합 164MB - ctags/gtags 가 매번 그걸
-- 읽고 태그는 한 줄도 내지 않았다.
--
-- 크기도 본다. 생성된 헤더 vmlinux_*.h 3개(각 3MB)가 태그 485,469줄을
-- 만들어 120MB tags 파일의 절반을 차지했고, gutentags 는 저장할 때 그
-- 파일을 다시 쓴다.
--
--   let g:projectfiles_max_bytes = 0    " 크기 제한 없음
--   let g:projectfiles_skip_binary = 0  " 내용 검사 안 함
local function text_file(path)
  local st = uv.fs_stat(path)
  -- 볼 수 없으면 판단하지 않는다: 여기서 거절하면 상대 경로로 불린
  -- 자리에서 멀쩡한 파일이 조용히 빠진다
  if not st or st.type ~= 'file' then
    return true
  end
  local max = tonumber(cfg('max_bytes', 2 * 1024 * 1024)) or 0
  if max > 0 and st.size > max then
    skipped.big = skipped.big + 1
    if not skipped.worst or st.size > skipped.worst.size then
      skipped.worst = { size = st.size, path = path }
    end
    return false
  end
  if cfg('skip_binary', 1) == 0 then
    return true
  end
  local fd = uv.fs_open(path, 'r', 438)
  if not fd then
    return true
  end
  local data = uv.fs_read(fd, 1024, 0)
  uv.fs_close(fd)
  if data and data:find('\0', 1, true) then
    skipped.binary = skipped.binary + 1
    return false
  end
  return true
end

local function indexed(path)
  local base = path:match('([^/]+)$') or path
  if cfg('all_files', 1) ~= 0 then
    -- 전부 넣고, 산출물/바이너리만 뺀다
    if EXCL_NAME[base] then
      return false
    end
    local e = base:match('%.([%w_]+)$')
    if e and EXCL[e:lower()] then
      return false
    end
    return text_file(path)
  end
  if BASE[base] then
    return text_file(path)
  end
  local e = base:match('%.([%w_]+)$')
  return e ~= nil and EXT[e] == true and text_file(path)
end

-- '/a/b/c' 처럼 더 손댈 것이 없는 절대 경로인가
local function plain_abs(p)
  if p:sub(1, 1) ~= '/' or p:sub(-1) == '/' or p:find('//', 1, true) then
    return false
  end
  for seg in p:gmatch('[^/]+') do
    if seg == '.' or seg == '..' then
      return false
    end
  end
  return true
end

local function rel_to(root, path)
  -- 이미 정규화된 절대 경로면 fnamemodify() 를 건너뛴다. find 가 주는 경로가
  -- 전부 그 모양이고 목록 하나에 1500~2000번 불리는 자리라, 그만큼 eval
  -- 다리를 덜 건넌다 (1452개에 9ms).
  local p = plain_abs(path) and path
      or (vim.fn.fnamemodify(path, ':p'):gsub('/+$', ''))
  if p == root then
    return '.' -- 프로젝트 루트 자체. 절대 경로로 적으면 이식되지 않는다
  end
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

-- 하위 프로젝트 목록은 디스크에도 적어 둔다.
--
-- 이걸 구하는 것은 프로젝트 전체를 훑는 find 다. tsnd 트리에서 3.15초
-- 걸렸고, 이 파일의 예전 주석은 Android SDK(디렉터리 14만 개)에서 콜드로
-- 몇 분이라고 적고 있다. 메모리 캐시는 TTL 이 2초라 세션 사이는 물론이고
-- 사실상 매번 다시 걷는다.
--
-- '.tags/nested' 는 그 답을 그대로 담는다. 루트 디렉터리보다 새 것이면
-- 그대로 쓴다 - 하위 프로젝트가 생기거나 없어지면 루트의 mtime 이 바뀌므로
-- 그때는 다시 걷는다. :ProjectFilesReindex 나 DirChanged 로도 버려진다.
local function nested_file(root)
  return root .. '/' .. (dbdir() or '.tags') .. '/nested'
end

local function nested_read(root)
  local f = nested_file(root)
  local st, rs = uv.fs_stat(f), uv.fs_stat(root)
  if not st or not rs or st.mtime.sec < rs.mtime.sec then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, f)
  if not ok then
    return nil
  end
  local out = {}
  for _, l in ipairs(lines) do
    if l ~= '' then
      out[#out + 1] = l
    end
  end
  return out
end

local function nested_save(root, list)
  local f = nested_file(root)
  pcall(vim.fn.mkdir, vim.fs.dirname(f), 'p')
  pcall(vim.fn.writefile, list, f)
end

local function nested_cmd(root, depth)
  local d = dbdir() or '.tags'
  return ('find %s -mindepth 2 -maxdepth %d -type d -name %s -prune -print 2>/dev/null')
      :format(vim.fn.shellescape(root), depth + 1, vim.fn.shellescape(d))
end

local function nested_parse(root, lines)
  local d = dbdir() or '.tags'
  local tail = '/' .. d
  local list = {}
  for _, l in ipairs(lines or {}) do
    if l:sub(-#tail) == tail then
      local dir = l:sub(1, #l - #tail)
      if dir:sub(1, #root + 1) == root .. '/' then
        list[#list + 1] = dir:sub(#root + 2) .. '/'
      end
    end
  end
  return list
end

local function nested_prefixes(root)
  local depth = tonumber(cfg('nested_depth', 6)) or 6
  if depth <= 0 then
    return {}
  end
  local now = uv.now()
  local c = nested_cache[root]
  if c and c.depth == depth and (now - c.at) < 2000 then
    return c.list
  end
  local disk = nested_read(root)
  if disk then
    nested_cache[root] = { at = now, depth = depth, list = disk }
    return disk
  end
  local list = nested_parse(root,
    vim.fn.systemlist({ 'sh', '-c', nested_cmd(root, depth) }))
  nested_cache[root] = { at = now, depth = depth, list = list }
  nested_save(root, list)
  return list
end

-- 같은 것을 메인 루프를 잡지 않고 구한다. 시작할 때(absorb)는 아무도 그
-- 반환값을 기다리지 않으므로 이쪽을 쓴다.
local function nested_prefixes_async(root, cb)
  local depth = tonumber(cfg('nested_depth', 6)) or 6
  if depth <= 0 then
    cb({})
    return
  end
  local now = uv.now()
  local c = nested_cache[root]
  if c and c.depth == depth and (now - c.at) < 2000 then
    cb(c.list)
    return
  end
  local disk = nested_read(root)
  if disk then
    nested_cache[root] = { at = now, depth = depth, list = disk }
    cb(disk)
    return
  end
  local ok = pcall(vim.system, { 'sh', '-c', nested_cmd(root, depth) },
    { text = true }, vim.schedule_wrap(function(res)
      local lines = {}
      for l in ((res and res.stdout) or ''):gmatch('[^\n]+') do
        lines[#lines + 1] = l
      end
      local list = nested_parse(root, lines)
      nested_cache[root] = { at = uv.now(), depth = depth, list = list }
      nested_save(root, list)
      cb(list)
    end))
  if not ok then
    cb({})
  end
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

local function prune_expr()
  local prune = {}
  for d in tostring(cfg('prune_dirs',
      '.git .svn .hg .tags node_modules __pycache__ .repo .ccache out')):gmatch('%S+') do
    prune[#prune + 1] = "-name '" .. d .. "'"
  end
  return "\\( " .. table.concat(prune, ' -o ') .. " \\) -prune -o "
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
  -- 파일은 전부 찾고 indexed() 로 걸른다: 무엇을 넣을지 정하는 곳이 하나여야
  -- '모든 파일' 모드와 허용목록 모드가 어긋나지 않는다.
  local cmd = 'find ' .. vim.fn.shellescape(abs) .. ' ' .. prune_expr() ..
      ' -type f -print 2>/dev/null'
  for _, l in ipairs(vim.fn.systemlist(cmd)) do
    if l ~= '' and indexed(l) then
      out[#out + 1] = rel_to(root, l)
    end
  end
  return out, true
end

-- 디렉터리 항목 여러 개를 find 한 번으로 편다.
--
-- find 는 시작점을 여러 개 받는다. 항목마다 따로 부르면 그만큼 셸을 fork 하고,
-- fork 비용은 부모(nvim)의 크기에 비례해 커진다. dir 항목 17개짜리 실제
-- preset 에서 17번 부르면 118ms, 한 번에 부르면 26ms 였다 - 찾아낸 파일은
-- 1992개로 똑같다.
--
-- 명령줄이 너무 길면 실행 자체가 안 되므로(ARG_MAX) 끊어서 부른다.
local function expand_dirs(root, dirs)
  local out = {}
  if #dirs == 0 then
    return out
  end
  local pe = prune_expr()
  local i = 1
  while i <= #dirs do
    local args, len = {}, 0
    while i <= #dirs and #args < 500 and len < 100000 do
      local a = vim.fn.shellescape(dirs[i])
      args[#args + 1] = a
      len, i = len + #a + 1, i + 1
    end
    local cmd = 'find ' .. table.concat(args, ' ') .. ' ' .. pe ..
        ' -type f -print 2>/dev/null'
    for _, l in ipairs(vim.fn.systemlist(cmd)) do
      if l ~= '' and indexed(l) then
        out[#out + 1] = rel_to(root, l)
      end
    end
  end
  return out
end

-- preset 항목 전부를 편다. 디렉터리는 묶어서 한 번에 훑는다.
local function expand_all(root, entries)
  local out, dirs = {}, {}
  for _, e in ipairs(entries) do
    local abs = e.path:sub(1, 1) == '/' and e.path or (root .. '/' .. e.path)
    local st = uv.fs_stat(abs)
    -- preset 의 kind 는 적어 둔 값일 뿐이고, 실제로 무엇인지는 파일 시스템이
    -- 답한다 - 디렉터리였던 것이 파일로 바뀌어 있을 수 있다
    if st and st.type == 'directory' then
      dirs[#dirs + 1] = abs
    else
      for _, f in ipairs((expand_entry(root, e))) do
        out[#out + 1] = f
      end
    end
  end
  for _, f in ipairs(expand_dirs(root, dirs)) do
    out[#out + 1] = f
  end
  return out
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
  skipped = { big = 0, binary = 0, worst = nil }
  for _, f in ipairs(expand_all(root, entries)) do
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
  -- 크기/바이너리로 뺀 것을 한 번만 말한다. 조용히 빼면 '왜 이 파일이
  -- \fo 에 없지'가 된다.
  if (skipped.big + skipped.binary) > 0 then
    local key = ('%s\0%d\0%d'):format(root, skipped.big, skipped.binary)
    if s.skip_told ~= key then
      s.skip_told = key
      local parts = {}
      if skipped.binary > 0 then
        parts[#parts + 1] = ('바이너리 %d개'):format(skipped.binary)
      end
      if skipped.big > 0 then
        local w = skipped.worst
        parts[#parts + 1] = ('%s 초과 %d개%s'):format(
          ('%.0fMB'):format((tonumber(cfg('max_bytes', 2 * 1024 * 1024)) or 0) / 1048576),
          skipped.big,
          w and (' (최대 %s, %.0fMB)'):format(vim.fs.basename(w.path), w.size / 1048576) or '')
      end
      notify('색인에서 뺐습니다: ' .. table.concat(parts, ', ')
        .. '  (g:projectfiles_max_bytes / _skip_binary 로 조절)')
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
      -- 지우기 전에 사본을 남긴다. 이 경로가 곧 '마지막 항목까지 빠진'
      -- 순간이고, 되돌리고 싶은 지점이 바로 여기다.
      backup_preset(name)
      pcall(vim.fn.delete, mine)
    end
    set_last(root, name)
    -- 예전에는 여기서 auto 로 돌아갔다. 이제 none 이 있으니 그쪽이 맞다 -
    -- '담아 둔 것이 하나도 남지 않았다'가 '프로젝트 전체를 색인해라'로
    -- 바뀌는 것은 놀라운 일이다. :ProjectFilesRestore 로 되돌릴 수 있다.
    set_active(root, MODE_NONE)
    if batch then
      batch.emptied = name
      return nil -- 커밋은 배치 끝에서
    end
    materialize(root)
    reindex(root)
    local sp = shared_path(name)
    notify(sp and uv.fs_stat(sp)
      and ("목록이 비어 none 모드로 돌아갑니다 (내 '%s' 사본은 지웠고 vim-ide "
        .. '공용본은 그대로입니다)'):format(name)
      or '목록이 비어 none 모드로 돌아갑니다 (색인하지 않습니다)')
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
  -- preset 은 '프로젝트 상대 경로 목록'이다. 그게 다른 체크아웃에서도 쓸 수
  -- 있게 만드는 유일한 이유이고, vim-ide 로 공유하는 근거이기도 하다.
  -- 이 프로젝트 밖의 경로는 상대 경로로 적을 수 없으니 절대 경로가 되어
  -- 버리는데, 그런 항목은 다른 기계에서 무의미하고 지우기도 어렵다
  -- (상대 경로로 :ProjectFilesRemove 해도 맞지 않는다). 담지 않는다.
  if rel:sub(1, 1) == '/' then
    bnotify(('이 프로젝트(%s) 밖의 경로는 담을 수 없습니다: %s'):format(
      vim.fn.fnamemodify(root, ':~'), rel), vim.log.levels.WARN)
    return
  end
  for _, e in ipairs(entries) do
    if e.path == rel then
      bnotify('이미 있습니다: ' .. rel .. '  →  ' .. target_label(root), nil, true)
      return
    end
  end
  entries[#entries + 1] = { path = rel, kind = st.type == 'directory' and 'dir' or 'file' }
  save_entries(root, name, entries)
  bnotify('추가: ' .. rel .. '  →  ' .. target_label(root), nil, true)
end

-- 한 번의 제거가 목록의 상당 부분을 지우려 하면 되묻는다.
--
-- 'arch/arm64/boot/dts/telechips' 디렉터리 노드에서 '-' 한 번이 항목 487개를
-- 조용히 지웠다. 규칙 자체는 의도된 것이지만(디렉터리를 빼면 그 아래도
-- 빠진다), 그 규모를 말해 주지 않는 것은 의도가 아니었다.
--   let g:projectfiles_confirm_drop = 0    " 되묻지 않기
--   let g:projectfiles_confirm_drop = 100  " 100개 이상일 때만
local function confirm_drop(root, rel, dropped, total)
  local limit = tonumber(cfg('confirm_drop', 20)) or 20
  if limit <= 0 or dropped < limit then
    return true
  end
  local msg = ("'%s' 를 빼면 항목 %d개가 목록에서 빠집니다 (전체 %d개). "):format(
    rel, dropped, total) .. target_label(root)
  -- 배치(비주얼 범위)는 끝에서 합계를 보고하고, 줄마다 물으면 쓸 수 없다.
  local uis = pcall(api.nvim_list_uis) and #api.nvim_list_uis() or 0
  if batch or uis == 0 then
    notify(msg, vim.log.levels.WARN)
    return true
  end
  local ans = 0
  pcall(function()
    ans = vim.fn.confirm(msg .. '\n계속할까요?', "&예\n&아니오", 2, 'Question')
  end)
  return ans == 1
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
  local kept, hit, dropped = {}, false, 0
  for _, e in ipairs(entries) do
    -- removing a directory drops the files under it too
    if e.path == rel or e.path:sub(1, #rel + 1) == rel .. '/' then
      hit = true
      dropped = dropped + 1
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
      -- 펼치면서 이미 있던 항목과 겹칠 수 있다. 겹친 것을 그대로 두면
      -- 목록에 같은 파일이 두 번 남는다.
      kept = (dedupe_entries(expanded))
    end
  end
  if not hit then
    bnotify('목록에 없습니다: ' .. rel, vim.log.levels.WARN)
    return
  end
  -- 몇 개가 빠지는지 말한다. 디렉터리에 '-' 를 한 번 누르면 그 아래가 전부
  -- 빠지는데, 예전에는 '제거: <경로>' 한 줄만 나와서 487개가 사라진 것을
  -- 화면에서 알 수 없었다.
  if not confirm_drop(root, rel, dropped, #entries) then
    bnotify('제거를 취소했습니다: ' .. rel, vim.log.levels.WARN)
    return
  end
  save_entries(root, name, kept)
  bnotify(('제거: %s (항목 %d개)  →  %s'):format(rel,
    dropped > 0 and dropped or (#entries - #kept), target_label(root)), nil, true)
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
  local head = ('%s %d개 (항목 %d -> %d)  →  %s'):format(what, b.done,
    before, after, target_label(root))
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
  local items = {
    { name = MODE_NONE, label = 'none — 아무것도 하지 않는다 (자동 색인 없음)' },
    { name = MODE_AUTO, label = 'auto — 프로젝트 전체 (git ls-files / find)' },
  }
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
    if choice.name == MODE_NONE then
      materialize(root)
      notify('none 모드: 이 프로젝트는 색인하지 않습니다'
        .. ' (<F2> 나 \\fm 으로 다시 고를 수 있습니다)')
      cb(false)
      return
    end
    local files = materialize(root)
    if choice.name == MODE_AUTO then
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
-- 어느 '.tags' 에 저장되는지 짧게 (피커 제목에도 같은 값을 넣는다)

-- 색인 목록을 고칠 때마다 어디에 쓰는지 말해 준다. 보고 있던 프로젝트와
-- 다르면 그것도 같이 - 그 침묵이 preset 이 엉뚱한 트리의 경로로 채워지는
-- 것을 눈치채지 못한 원인이었다.
local function announce_root(root)
  if not root then
    return
  end
  local ok, cur = pcall(cur_root)
  if ok and cur and root ~= cur then
    notify(('색인 대상: %s   (보고 있던 곳: %s)'):format(
      target_label(root), vim.fn.fnamemodify(cur, ':~')))
  else
    notify('색인 대상: ' .. target_label(root))
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

-- treeroot: 파일 트리가 열고 있는 디렉터리. 주면 그 프로젝트의 목록으로
-- 표시한다 - 트리에서 보이는 것은 '지금 보고 있는 프로젝트'의 색인이어야
-- 하고, 하위 프로젝트의 목록이 섞이면 같은 화면에 두 기준이 겹친다.
function _G.projectfiles_tree_flag(path, treeroot)
  path = tostring(path or ''):gsub('/+$', '')
  if path == '' then
    return ''
  end
  local dir = path:match('^(.*)/[^/]*$') or path
  local key = dir .. '\0' .. tostring(treeroot or '')
  local root = flag_root[key]
  if root == nil then
    if treeroot and treeroot ~= '' then
      -- root_of 를 거쳐야 '현재 디렉터리 기준' 고정(anchor_cwd)이 함께
      -- 적용된다. root_of 는 인자의 dirname 에서 출발하므로 자식 하나를
      -- 붙여 준다.
      root = root_of((tostring(treeroot):gsub('/+$', '')) .. '/x') or false
    else
      root = root_of(path) or false
    end
    flag_root[key] = root
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
-- 하위 프로젝트가 골라 둔 목록을 가져오기
-- ---------------------------------------------------------------------------
-- 상위 트리에서 일하는데 정작 보고 싶은 파일은 하위 프로젝트가 자기 preset
-- 으로 골라 둔 것일 때가 있다(예: d5_qnx_hyp 에서 일하지만 목록은
-- kernel/common 에 있다). 그 목록을 현재 프로젝트 기준 경로로 바꿔 현재
-- preset 에 넣는다.
--
-- 가져오는 것은 하위 프로젝트의 '색인 목록'(.tags/files)이다 - 그게 그
-- 프로젝트가 실제로 색인하는 것이고, 파일 하나하나로 들어오므로 상위에서
-- 다시 펼칠 때 설정 차이로 달라지지 않는다.
--
-- 목록 파일이 없는 하위는 가져오지 않는다. 예전에는 'auto 모드니까 그 트리
-- 전체'로 읽고 디렉터리 하나를 담았는데, 두 가지가 겹쳐 위험했다:
--   * 빈 '.tags' 디렉터리만 남은 자리가 있다(중단된 실행이 남긴 껍데기).
--     GTAGS 도 preset 도 files 도 없는데 auto 모드로 읽혔다.
--   * 그 한 줄이 트리 전체로 펼쳐진다. 실측: tsnd SDK 에서
--     maincore/bootable/bootloader/u-boot 의 빈 껍데기 하나 때문에 목록이
--     6개에서 19,581개가 됐다(gtags 19,200 파일, 10.3초).
-- 진짜로 트리 전체를 원하면 :ProjectFilesAdd 로 그 디렉터리를 담으면 된다.
--   let g:projectfiles_absorb_whole = 1   " 예전처럼 auto 모드 하위도 통째로
--
-- 자동으로 하지 않는다: preset 은 사람이 고른 것이고, 시작할 때 말없이
-- 수백 개를 밀어 넣는 것은 좋지 않다. 가져올 것이 있으면 한 번 알려 준다.
--   :ProjectFilesAbsorb              지금 가져오기
--   let g:projectfiles_absorb = 1    프로젝트를 처음 열 때 자동으로
--   let g:projectfiles_absorb_hint = 0   알림도 끄기
local function nested_lists(root)
  local out = {}
  local d = dbdir() or '.tags'
  for _, pre in ipairs(nested_prefixes(root)) do
    local nroot = root .. '/' .. pre:gsub('/$', '')
    local lf = nroot .. '/' .. d .. '/files'
    local item = { rel = pre, files = {}, whole = false }
    if uv.fs_stat(lf) then
      for _, f in ipairs(vim.fn.readfile(lf)) do
        if f ~= '' then
          item.files[#item.files + 1] = pre .. f
        end
      end
    elseif cfg('absorb_whole', 0) ~= 0
        and uv.fs_stat(nroot .. '/' .. d .. '/GTAGS') then
      -- auto 모드인 하위 프로젝트: 그 트리 전체 (GTAGS 가 있어야 진짜다)
      item.whole = true
    end
    if item.whole or #item.files > 0 then
      out[#out + 1] = item
    end
  end
  return out
end

local function absorb_nested(root, quiet)
  local lists = nested_lists(root)
  if #lists == 0 then
    if not quiet then
      notify('가져올 하위 프로젝트 목록이 없습니다  →  ' .. target_label(root))
    end
    return 0
  end
  -- 이미 있는 항목은 건너뛴다
  local have = {}
  for _, e in ipairs(entries_of(root) or {}) do
    have[e.path] = true
  end
  local todo, per = {}, {}
  for _, it in ipairs(lists) do
    local c = 0
    if it.whole then
      local dirrel = it.rel:gsub('/$', '')
      if not have[dirrel] then
        todo[#todo + 1] = dirrel
        c = 1
      end
    else
      for _, f in ipairs(it.files) do
        if not have[f] then
          todo[#todo + 1] = f
          c = c + 1
        end
      end
    end
    per[#per + 1] = ('%s %d개%s'):format(it.rel:gsub('/$', ''), c,
      it.whole and ' (트리 전체)' or '')
  end
  if #todo == 0 then
    if not quiet then
      notify(('하위 프로젝트 %d개의 목록은 이미 다 들어와 있습니다  →  %s')
        :format(#lists, target_label(root)))
    end
    return 0
  end
  in_batch(root, '가져오기', function()
    for _, rel in ipairs(todo) do
      add_path(root, rel)
    end
  end)
  notify(('하위 프로젝트에서 가져왔습니다: %s  →  %s'):format(
    table.concat(per, ', '), target_label(root)))
  return #todo
end

-- 가져올 것이 있으면 한 번만 알려 준다 (프로젝트당 세션당 한 번)
local absorb_hinted = {}
local function absorb_hint(root)
  if cfg('absorb_hint', 1) == 0 or absorb_hinted[root] then
    return
  end
  -- 모드를 정하지 않은(none 포함) 프로젝트는 건드리지 않는다. 아래
  -- nested_lists() → nested_prefixes() 의 find 는 vim.fn.systemlist() -
  -- 동기 호출이라 끝날 때까지 키 입력이 하나도 처리되지 않는다. Android
  -- SDK 처럼 depth 7 에 디렉터리가 14만 개인 트리에서는 콜드 캐시 기준
  -- 수 분이 걸린다. 파일 상단 주석의 설계 의도('모드를 정하지 않은
  -- 디렉터리에서는 묻지도 색인하지도 않는다')와 맞춘다.
  if not mode_indexes(root) then
    return
  end
  absorb_hinted[root] = true
  if cfg('absorb', 0) ~= 0 then
    absorb_nested(root, true)
    return
  end
  local lists = nested_lists(root)
  if #lists == 0 then
    return
  end
  local have = {}
  for _, e in ipairs(entries_of(root) or {}) do
    have[e.path] = true
  end
  local n = 0
  for _, it in ipairs(lists) do
    if it.whole then
      n = n + ((have[(it.rel:gsub('/$', ''))]) and 0 or 1)
    else
      for _, f in ipairs(it.files) do
        n = n + (have[f] and 0 or 1)
      end
    end
  end
  if n > 0 then
    notify(('하위 프로젝트 %d곳이 골라 둔 파일 %d개를 이 프로젝트 목록으로 '):format(
        #lists, n)
      .. '가져올 수 있습니다 (:ProjectFilesAbsorb)')
  end
end

-- 시작할 때 한 번, 가져올 것이 있는지 알려 준다.
--
-- 하위 프로젝트 목록을 먼저 '자식 프로세스로' 구해 둔다. absorb_hint 는
-- 그 목록을 동기로 구하는데(nested_prefixes), 그게 프로젝트 전체를 훑는
-- find 라 시작 직후 메인 루프를 3초 넘게 잡았다. 여기서 미리 채워 두면
-- absorb_hint 가 도는 시점에는 캐시에서 바로 나온다 - 아무도 이 반환값을
-- 기다리지 않으므로 비동기로 해도 잃는 것이 없다.
api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    vim.defer_fn(function()
      local ok, root = pcall(cur_root)
      if not (ok and root) then
        return
      end
      nested_prefixes_async(root, function()
        pcall(absorb_hint, root)
      end)
    end, 900)
  end,
})


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

-- 정의를 찾는 패턴을 두 단계로 나눈다.
--
-- 예전에는 한 벌이었고 'struct foo;' 도 받아들였다. 그래서 커널에서
-- platform_device 를 찾으면 'struct platform_device;' 한 줄만 들어 있는
-- 헤더들이 먼저 나왔다 - arch/arm/mach-s3c/cpu.h, drivers/clk/qcom/common.h,
-- drivers/dma/dw/internal.h ... 정의가 아니라 언급이다. 그것들이 그대로
-- preset 에 들어갔다.
--
-- strong 은 '여기서 정의된다'가 분명한 것만 잡는다: 여는 중괄호가 있는
-- struct/union/enum/typedef, #define, 함수 모양. weak 는 예전 패턴이고,
-- strong 이 하나도 못 찾았을 때만 쓴다 ('struct foo\n{' 처럼 중괄호가 다음
-- 줄로 내려간 정의는 줄 단위 grep 으로는 strong 에 안 걸린다).
local function def_patterns(sym, weak)
  local strong = {
    "-e '^[A-Za-z_].*[^A-Za-z0-9_]" .. sym .. "[[:space:]]*\\('",
    "-e '^#[[:space:]]*define[[:space:]]+" .. sym .. "[^A-Za-z0-9_]'",
    "-e '^(typedef|struct|union|enum)[[:space:]]+([^;{]*[^A-Za-z0-9_])?" ..
      sym .. "[[:space:]]*\\{'",
  }
  if not weak then
    return strong
  end
  strong[#strong + 1] = "-e '^(typedef|struct|union|enum)[[:space:]]+([^;{]*[^A-Za-z0-9_])?"
      .. sym .. "[^A-Za-z0-9_]*[;{]'"
  strong[#strong + 1] = "-e '^[A-Za-z_].*[^A-Za-z0-9_]" .. sym .. "[[:space:]]*[=;[]'"
  return strong
end

local function grep_defining(root, sym)
  local cmds = {}
  for _, weak in ipairs({ false, true }) do
    local pats = def_patterns(sym, weak)
    if uv.fs_stat(root .. '/.git') then
      cmds[#cmds + 1] = 'git grep -lE ' .. table.concat(pats, ' ') .. ' -- ' .. GLOBS
    end
    cmds[#cmds + 1] = "grep -rlE " .. table.concat(pats, ' ') ..
        " --include='*.c' --include='*.h' --include='*.cpp' --include='*.cc' ."
  end
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
  local max = tonumber(cfg('grep_max', 5)) or 5
  local cmds = {}
  -- strong 을 먼저 전부 시도하고, 그래도 없으면 weak 으로 내려간다
  for _, weak in ipairs({ false, true }) do
    local pats = def_patterns(sym, weak)
    if uv.fs_stat(root .. '/.git') then
      cmds[#cmds + 1] = 'git grep -lE ' .. table.concat(pats, ' ') .. ' -- ' .. GLOBS
    end
    cmds[#cmds + 1] = 'grep -rlE ' .. table.concat(pats, ' ') ..
        " --include='*.c' --include='*.h' --include='*.cpp' --include='*.cc' ."
  end
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

-- ---------------------------------------------------------------------------
-- 'global --single-update': 한 DB 에 하나씩, 감독하면서
-- ---------------------------------------------------------------------------
--
-- 예전에는 추가된 파일마다 이것을 한꺼번에 띄웠다. 한 데이터베이스에 동시
-- 갱신이 들어가면 서로 물려 끝나지 않는다 - 실제로 gtags 두 개가 같은
-- .tags 를 붙들고 13시간 동안 각각 CPU 100% 로 돌았다(사용자 CPU 47,927초,
-- 상태 R, wchan 0 - 커널을 기다리는 게 아니라 그냥 돌고 있었다). 게다가
-- 동기판은 ':wait(5000)' 이라 5초 뒤 손을 떼기만 하고 죽이지는 않아서,
-- nvim 이 먼저 사라져도 일꾼은 남았다.
--
-- 그래서 셋을 지킨다: 루트마다 한 번에 하나, 시간이 지나면 정말 죽인다,
-- nvim 이 끝날 때 같이 정리한다.
--   let g:projectfiles_single_update_max = 0   " 즉시 갱신을 아예 끄기
--   let g:projectfiles_single_update_timeout = 20   " 초
local update_jobs = {}       -- 진행 중인 핸들 -> 명령 이름
local update_queue = {}      -- root -> { rels..., running = bool, done = fn }
local update_timeout_cmd     -- nil=미탐색, false=없음

local function update_timeout_prefix(ms)
  if update_timeout_cmd == nil then
    update_timeout_cmd = false
    for _, c in ipairs({ 'timeout', 'gtimeout' }) do
      if vim.fn.executable(c) == 1 then
        update_timeout_cmd = c
        break
      end
    end
  end
  if not update_timeout_cmd or not ms then
    return nil
  end
  -- global 은 gtags 를 자식으로 띄운다. nvim 이 global 만 죽이면 gtags 가
  -- 고아로 남아 계속 돈다 - timeout(1) 은 자기 프로세스 그룹에 신호를
  -- 보내므로 자식까지 함께 끊는다. nvim 쪽 제한보다 늦게 잡아서 정상
  -- 경로에서는 nvim 이 먼저 처리하게 둔다.
  return { update_timeout_cmd, '-k', '5', tostring(math.floor(ms / 1000) + 10) }
end

local function global_prog()
  return vim.fn.executable('global') == 1 and 'global'
      or vim.fn.expand('~/.local/bin/global')
end

-- 프로세스 그룹째 끊는다. 리더로 띄웠으니(detach) pgid == pid 다.
-- nvim 의 h:kill() 은 리더 하나만 끊어서 자식이 남는다.
local function kill_group(pid)
  if not pid or pid <= 0 then
    return
  end
  for _, sig in ipairs({ 'TERM', 'KILL' }) do
    -- '-<pid>' = 그 프로세스 그룹 전체. 이미 없으면 조용히 실패한다.
    pcall(vim.system, { 'kill', '-' .. sig, '-' .. tostring(pid) },
      { text = true }, function() end)
  end
end

local function update_step(root)
  local q = update_queue[root]
  if not q then
    return
  end
  local rel = table.remove(q, 1)
  if not rel then
    q.running = false
    update_queue[root] = nil
    if q.done then
      q.done()
    end
    return
  end
  local ms = (tonumber(cfg('single_update_timeout', 20)) or 20) * 1000
  local argv = { global_prog(), '--single-update', rel }
  local pre = update_timeout_prefix(ms)
  if pre then
    argv = vim.list_extend(pre, argv)
  end
  -- 저장할 때 도는 배경 작업이다. 타자보다 늦어도 되니 양보한다
  -- (autoindex.lua 의 spawn() 과 같은 정책).
  local np = {}
  local n = tonumber(cfg('nice', 10)) or 0
  if n > 0 and vim.fn.executable('nice') == 1 then
    vim.list_extend(np, { 'nice', '-n', tostring(math.min(19, n)) })
  end
  local io_n = tonumber(cfg('ionice', 7)) or 0
  if io_n > 0 and vim.fn.executable('ionice') == 1 then
    vim.list_extend(np, { 'ionice', '-c', '2', '-n', tostring(math.min(7, io_n)) })
  end
  if #np > 0 then
    argv = vim.list_extend(np, argv)
  end
  local h, watch, timed_out = nil, nil, false
  local ok = pcall(function()
    h = vim.system(argv, {
      cwd = root,
      env = { GTAGSOBJDIR = dbdir() or '.tags' },
      -- 자기 프로세스 그룹의 리더로 띄운다: 'global' 은 'gtags' 를 자식으로
      -- 두는데, global 만 죽이면 gtags 가 고아로 남아 계속 돈다(그게 13시간
      -- 짜리였다). 리더로 두면 pgid == pid 라 그룹째 끊을 수 있다.
      detach = true,
      -- vim.system 의 timeout 은 여기서 쓰지 않는다: 그건 리더만 끊고,
      -- 손자가 stdout 을 붙들고 있으면 종료 콜백 자체가 손자가 끝날 때까지
      -- 오지 않는다. 그래서 시간 감시는 아래에서 직접 한다 - 콜백을
      -- 기다렸다가 끊으면 순환이다.
    }, function(o)
      if watch then
        pcall(function() watch:stop() end)
      end
      if h then
        update_jobs[h] = nil
      end
      if timed_out then
        vim.schedule(function()
          notify(("'%s' 즉시 색인이 %d초를 넘겨 끊었습니다 - 뒤따르는 "):format(
            rel, math.floor(ms / 1000)) .. '재색인이 맡습니다',
            vim.log.levels.WARN)
        end)
      end
      vim.schedule(function() update_step(root) end)
    end)
  end)
  if not ok or not h then
    return update_step(root) -- 못 띄웠으면 다음 것으로
  end
  update_jobs[h] = 'global'
  watch = vim.defer_fn(function()
    if update_jobs[h] then -- 아직 안 끝났다
      timed_out = true
      kill_group(h.pid)
      pcall(function() h:kill('sigkill') end)
    end
  end, ms)
end

-- rels 를 이 루트의 큐에 붙인다. done 은 큐가 다 빌 때 한 번 불린다.
local function single_update(root, rels, done)
  local max = tonumber(cfg('single_update_max', 4)) or 4
  local todo = {}
  for i, rel in ipairs(rels) do
    if max > 0 and i > max then
      notify(('즉시 색인은 %d개까지만 합니다 (%d개는 재색인이 맡습니다)'):format(
        max, #rels - max))
      break
    end
    todo[#todo + 1] = rel
  end
  if #todo == 0 then
    if done then
      done()
    end
    return
  end
  local q = update_queue[root]
  if q then
    -- 이미 이 루트에서 돌고 있다: 뒤에 붙이고 done 을 이어 붙인다
    for _, rel in ipairs(todo) do
      q[#q + 1] = rel
    end
    local prev = q.done
    q.done = function()
      if prev then
        prev()
      end
      if done then
        done()
      end
    end
    return
  end
  q = todo
  q.running = true
  q.done = done
  update_queue[root] = q
  update_step(root)
end

-- 테스트용 진입점. 큐가 정말 하나씩 돌리고 시간이 지나면 죽이는지는
-- 가짜 'global' 을 PATH 앞에 두고 이걸 불러서 확인한다.
function _G.projectfiles_single_update(root, rels, cb)
  return single_update(root, rels, cb)
end

-- nvim 이 끝날 때 같이 정리한다. 이게 없으면 고아가 남는다.
api.nvim_create_autocmd('VimLeavePre', {
  group = api.nvim_create_augroup('ProjectFilesUpdateCleanup', { clear = true }),
  callback = function()
    for h in pairs(update_jobs) do
      pcall(function() h:kill('sigterm') end)
      -- 자식(gtags)까지. nvim 이 사라진 뒤에 남으면 아무도 치우지 않는다.
      pcall(function()
        vim.fn.system({ 'kill', '-KILL', '-' .. tostring(h.pid) })
      end)
    end
  end,
})

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
    -- 새 파일을 지금 색인해 둔다: 이걸 부른 점프를 곧바로 다시 시도할 수
    -- 있게. 한 번에 하나씩만 돌린다 (single_update 참고 - 동시에 띄우면
    -- 같은 DB 를 붙들고 끝나지 않는다).
    single_update(root, added, function()
      reindex(root)
      notify(("'%s' 정의 파일 %d개 추가: %s")
        :format(sym, #added, table.concat(added, ', ')))
      cb(#added)
    end)
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
  --
  -- 예전에는 여기서 ':wait(5000)' 로 기다렸다. 5초가 지나면 손을 떼기만
  -- 하고 죽이지 않아서, 늦게 끝나는 일꾼이 그대로 남아 다음 파일의 갱신과
  -- 같은 DB 에서 겹쳤다. 지금은 큐가 하나씩 돌리고 시간이 지나면 죽인다.
  single_update(root, added, function()
    reindex(root)
    notify(("'%s' 을(를) 정의한 파일 %d개를 추가했습니다: %s")
      :format(sym, #added, table.concat(added, ', ')))
  end)
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

-- 백업에서 되돌린다.
--
-- 저장 전마다 사본을 남기니(backup_preset), 잘못 지운 직후라면 그 사본이
-- 지우기 전 상태다. 되돌리기 자체도 저장이므로 지금 상태의 사본이 먼저
-- 남는다 - 되돌린 것을 다시 되돌릴 수 있다.
api.nvim_create_user_command('ProjectFilesRestore', function(o)
  local root = cur_root()
  -- auto 로 돌아간 뒤에도 되돌릴 수 있어야 한다: 마지막으로 쓰던 이름을 본다
  local name = active_preset(root)
  local revive = false
  if not name then
    name = last_preset(root)
    revive = name ~= nil
  end
  if not name then
    notify('auto 모드입니다 (되돌릴 preset 이 없습니다)', vim.log.levels.WARN)
    return
  end
  local dir = presets_dir() .. '/.backup'
  local base = name:gsub('[^%w%-_.]', '_')
  local list = {}
  local h = uv.fs_scandir(dir)
  while h do
    local n = uv.fs_scandir_next(h)
    if not n then
      break
    end
    if n:sub(1, #base + 1) == base .. '.' and n:sub(-5) == '.json' then
      local d = read_preset_file(dir .. '/' .. n)
      list[#list + 1] = {
        file = dir .. '/' .. n,
        stamp = n:sub(#base + 2, -6),
        count = d and d.entries and #d.entries or 0,
      }
    end
  end
  if #list == 0 then
    notify(("'%s' 의 백업이 없습니다 (%s)"):format(name,
      vim.fn.fnamemodify(dir, ':~')), vim.log.levels.WARN)
    return
  end
  table.sort(list, function(a, b) return a.stamp > b.stamp end)
  local cur = preset_read(name)
  local now = cur and cur.entries and #cur.entries or 0
  if o.args ~= '' then
    -- :ProjectFilesRestore <stamp> - 확인 없이 그 사본으로
    for _, it in ipairs(list) do
      if it.stamp == o.args then
        local d = read_preset_file(it.file)
        if not d then
          notify('백업을 읽을 수 없습니다: ' .. it.file, vim.log.levels.ERROR)
          return
        end
        if revive then
          set_active(root, name)
        end
        save_entries(root, name, d.entries)
        notify(('%s 로 되돌렸습니다 (항목 %d -> %d)%s'):format(it.stamp, now,
          #d.entries, revive and (" - preset '" .. name .. "' 을 다시 켰습니다") or ''))
        return
      end
    end
    notify('그런 백업이 없습니다: ' .. o.args, vim.log.levels.WARN)
    return
  end
  local items = {}
  for _, it in ipairs(list) do
    items[#items + 1] = ('%s  항목 %d개%s'):format(it.stamp, it.count,
      it.count > now and ('  (+%d)'):format(it.count - now)
      or it.count < now and ('  (-%d)'):format(now - it.count) or '  (같음)')
  end
  vim.ui.select(items, {
    prompt = ("'%s' 를 어느 시점으로? (지금 %d개)"):format(name, now),
  }, function(_, idx)
    if not idx then
      return
    end
    local d = read_preset_file(list[idx].file)
    if not d then
      notify('백업을 읽을 수 없습니다: ' .. list[idx].file, vim.log.levels.ERROR)
      return
    end
    if revive then
      set_active(root, name)
    end
    save_entries(root, name, d.entries)
    notify(('%s 로 되돌렸습니다 (항목 %d -> %d)  →  %s'):format(
      list[idx].stamp, now, #d.entries, target_label(root)))
  end)
end, { nargs = '?', desc = 'Restore the preset from a backup taken before a write' })

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
  -- 떠나는 자리는 창을 옮기기 전에 적어 둔다 - <C-t> 가 쓰는 태그 스택은
  -- 점프 목록과 다른 것이고, 우리 점프는 :tag 가 아니라서 vim 이 스스로
  -- 쌓아 주지 않는다
  local from = { vim.fn.bufnr('%'), vim.fn.line('.'), vim.fn.col('.'), 0 }
  local ok = pcall(open_in_edit, root, e.path)
  if not ok then
    notify('편집할 창을 찾지 못했습니다: ' .. e.path, vim.log.levels.WARN)
    return
  end
  local win = api.nvim_get_current_win()
  if vim.fn.getbufvar(from[1], '&buftype') == '' then
    pcall(vim.fn.settagstack, win,
      { items = { { tagname = e.name or '?', from = from } } }, 'a')
  end
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
    prompt_title = ('Project files (%d)  →  %s   ^a add  ^d remove')
        :format(#files, target_label(root)),
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
          announce_root(root)
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
    prompt_title = ('Add to project files (%d)  →  %s   <Tab> 여러 개')
        :format(#items, target_label(root)),
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
        announce_root(root)
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
    prompt_title = ('Add directories (%d)  →  %s   <Tab> 여러 개')
        :format(#items, target_label(root)),
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
        announce_root(root)
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
  local m = mode_of(root)
  local names = preset_list()
  local items = {
    -- 아직 모드를 정하지 않은 프로젝트(MODE_UNSET)의 기본값은 none 이다.
    -- 예전에는 auto 에 표시가 붙어서, 처음 F2 를 누른 사람이 '이 프로젝트는
    -- 전체 색인 상태'로 읽고 그대로 <CR> 하면 SDK 전체를 색인했다.
    { name = MODE_NONE, label = ((m == MODE_NONE or m == MODE_UNSET) and '● ' or '  ') ..
      'none  (아무것도 하지 않는다)' ..
      (m == MODE_UNSET and '   ← 기본값 (아직 정하지 않음)' or '') },
    { name = MODE_AUTO, label = (m == MODE_AUTO and '● ' or '  ') ..
      'auto  (프로젝트 전체 색인)' },
  }
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
    set_active(root, it.name)
    materialize(root)
    if it.name == MODE_NONE then
      notify('none 모드: 이 프로젝트는 색인하지 않습니다  →  ' .. target_label(root))
      return
    end
    reindex(root)
    if it.name == MODE_AUTO then
      notify('auto 모드: 프로젝트 전체를 색인합니다  →  ' .. target_label(root))
      return
    end
    notify(("preset '%s'  →  %s"):format(it.name, target_label(root)))
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
          -- 쓰던 preset 이 사라졌다: 전체 색인으로 올라타지 말고 멈춘다
          set_active(root, MODE_NONE)
          materialize(root)
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
    prompt_title = ('Remove from project files (%d)  →  %s')
        :format(#items, target_label(root)),
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
        announce_root(root)
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
  local r
  if a:sub(1, 1) == '/' then
    r = root_of(a)
  else
    r = cur_root()
  end
  announce_root(r)
  return r
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
api.nvim_create_user_command('ProjectFilesAbsorb', function()
  local root = cur_root()
  -- 손으로 부른 것은 늘 새로 본다. 하위에 프로젝트를 '방금' 만들었으면
  -- 루트의 mtime 은 그대로라 디스크 캐시가 그것을 놓친다 - 그 경우가
  -- 바로 이 명령을 치는 이유다.
  if root then
    nested_cache[root] = nil
    pcall(vim.fn.delete, nested_file(root))
  end
  absorb_nested(root, false)
end, { desc = "Pull nested projects' index lists into this project's preset" })

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
  set_active(root, o.args)
  materialize(root)
  if o.args == MODE_NONE then
    notify('none 모드: 이 프로젝트는 색인하지 않습니다  →  ' .. target_label(root))
    return
  end
  reindex(root)
  notify(o.args == MODE_AUTO and ('auto 모드  →  ' .. target_label(root))
    or ("preset '" .. o.args .. "'  →  " .. target_label(root)))
  if o.args ~= MODE_AUTO then
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
local booted -- 시작할 때 이미 펼쳐 둔 '<root>\0<preset>'
pcall(function()
  local root = root_of(nil)
  local name = active_preset(root)
  if name then
    materialize(root)
    booted = root .. '\0' .. name
  end
end)

api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    vim.defer_fn(function()
      local root = cur_root()
      local name = active_preset(root)
      local was = booted
      booted = nil
      if not name then
        return
      end
      -- 200ms 전에 같은 프로젝트, 같은 preset 으로 이미 펼쳤으면 결과가
      -- 같다. 실제 SDK 트리에서 한 번이 150~250ms 라, 뜨자마자 그만큼
      -- 멈칫하는 것이 그대로 보인다. 다른 프로젝트로 판명됐을 때만
      -- 다시 만든다 - 그게 이 VimEnter 가 있는 이유다.
      if was == root .. '\0' .. name then
        return
      end
      materialize(root)
    end, 200)
  end,
})
