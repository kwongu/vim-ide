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
  -- root -> { files = {...}(정렬), entries =, exclude =, preset =, 키들 }
  -- (materialize 와 apply_delta 가 채운다. 키의 뜻은 cache_valid 참고)
  cache = {},
  symbols = {},    -- root -> { key = <GTAGS mtime>, list = {...} }
  collect = nil,   -- one_line 이 모으는 알림
}

-- 파일 stat 을 캐시 키로. 초 단위 mtime 만으로는 같은 초 안에 다시 쓴 것을
-- 놓치고(같은 초에 + 와 - 를 하면 둘 다 그 초다), 크기는 같은 길이로 다시 쓴
-- 것을 놓친다. 나노초와 inode 까지 넣는다 (목록은 이름 바꾸기로 쓰므로 쓸
-- 때마다 inode 가 바뀐다).
local function stat_key(st)
  if not st then
    return 'none'
  end
  return ('%d:%d:%d:%d'):format(st.mtime.sec, st.mtime.nsec or 0, st.size,
    st.ino or 0)
end

local group = api.nvim_create_augroup('ProjectFiles', { clear = true })

-- 폭을 넘는 한 줄 알림은 Press ENTER 가 뜨며 다음 키를 먹는다 (fitmsg.lua)
--
-- 한 번의 손짓(명령 하나, 키 하나)은 알림도 한 줄이다 (one_line).
-- ':ProjectFilesAdd x' 처럼 Ex 명령 안에서 알림이 두 줄 쌓이면 Press ENTER 가
-- 뜨고, 그게 떠 있는 동안 nvim 은 vim.schedule/defer_fn 을 하나도 돌리지 않는다.
-- autoindex 의 indexfiles.sh -> gtags -i 사슬이 바로 그 콜백으로 이어지므로
-- 색인 반영이 키를 누를 때까지 멈췄다 (실측 3~16초). 그래서 모아 두었다가
-- 끝에서 한 줄로 낸다 - 화면은 fitmsg 가 폭에 맞게 줄이고, :messages 에는
-- 다 남는다.
local function notify(msg, level)
  level = level or vim.log.levels.INFO
  if s.collect then
    s.collect[#s.collect + 1] = { msg = msg, level = level }
    return
  end
  (_G.vimide_notify or vim.notify)('ProjectFiles: ' .. msg, level)
end

-- fn 이 내는 알림을 한 줄로 모은다. 겹쳐 부르면 바깥 것이 한 번만 낸다.
local function one_line(fn, ...)
  if s.collect then
    return fn(...)
  end
  s.collect = {}
  local ok, a, b = pcall(fn, ...)
  local msgs = s.collect
  s.collect = nil
  if #msgs > 0 then
    local parts, lvl = {}, vim.log.levels.INFO
    for _, m in ipairs(msgs) do
      parts[#parts + 1] = m.msg
      if m.level > lvl then
        lvl = m.level
      end
    end
    notify(table.concat(parts, '  |  '), lvl)
  end
  if not ok then
    error(a, 0)
  end
  return a, b
end

-- 사용자 명령: 알림은 한 줄로 (one_line)
local function ucmd(name, fn, opts)
  api.nvim_create_user_command(name, function(o)
    return one_line(fn, o)
  end, opts)
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
  -- '.repo' 는 repo 로 받은 SDK 의 루트 (autoindex.lua 의 marker_root 설명)
  local found = vim.fs.find({ '.git', '.repo', '.project', '.root' },
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
  for _, m in ipairs({ '.git', '.repo', '.project', '.root' }) do
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

-- 디렉터리는 세션에 한 번만 만든다. preset_path 를 부를 때마다 mkdir -p 가
-- 돌아서 + 한 번에 열 번 남짓 불렸다 (쓰기가 실패하면 preset_write 가 다시 만든다).
local function presets_dir()
  local d = vim.fn.stdpath('data') .. '/vim-ide/presets'
  if s.presets_dir ~= d then
    vim.fn.mkdir(d, 'p')
    s.presets_dir = d
  end
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
local function shared_dir_find(create)
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

-- 읽기(create 없이)의 답은 옵션 값별로 기억한다: 이 파일의 realpath 와 후보
-- 디렉터리 stat 을 preset 을 읽을 때마다 다시 할 이유가 없다. 만드는 쪽
-- (create)은 늘 새로 보고 기억도 지운다.
local function shared_dir(create)
  local mk = tostring(vim.g.projectfiles_shared_presets)
  s.shared_memo = s.shared_memo or {}
  if create then
    s.shared_memo = {}
    return shared_dir_find(true)
  end
  if s.shared_memo[mk] == nil then
    s.shared_memo[mk] = shared_dir_find(false) or false
  end
  return s.shared_memo[mk] or nil
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

-- preset JSON 을 읽은 결과를 파일 stat 으로 기억한다.
--
-- + 한 번에 같은 JSON 을 4~9번 읽고 풀었다(add_path, materialize 두 번,
-- 배치 앞뒤 ...). 6,500항목짜리에서 그것만 +마다 13~33ms 였다. 키는
-- mtime 나노초·크기·inode 까지 - 초 단위로는 같은 초 안의 다시 쓰기를 놓친다.
--
-- 돌려주는 것은 늘 새 사본이다. add_path 와 add_for_symbol 은 받은 목록에
-- 제자리로 덧붙이는데, 기억해 둔 표를 그대로 주면 쓰기가 실패했을 때 디스크에
-- 없는 항목이 기억에만 남는다 (반대 심문: preset 을 읽기 전용으로 두고 + 하니
-- 목록에는 들어가고 preset 에는 없었고, 다시 + 하면 '이미 있습니다').
s.preset_memo = {}  -- 파일 -> { key =, data = }

-- "exclude": 디렉터리 항목 아래에서 뺀 경로들 (C5). 'entries' 와 따로 두는
-- 것은 예전 vim-ide 사본(다른 장비, 같은 저장소의 공용 preset)이 이 키를
-- 모르고 지나가게 하려는 것이다 - 그쪽은 뺀 파일을 조금 더 색인할 뿐 깨지지
-- 않는다. entries 안에 새 kind 로 넣으면 예전 코드는 그것을 '담을 경로'로
-- 읽어 바로 그 파일을 색인한다.
local function clean_exclude(x)
  local out, seen = {}, {}
  for _, p in ipairs(type(x) == 'table' and x or {}) do
    if type(p) == 'string' then
      p = p:gsub('/+', '/'):gsub('^%./', ''):gsub('/+$', '')
      if p ~= '' and p ~= '.' and not seen[p] then
        seen[p] = true
        out[#out + 1] = p
      end
    end
  end
  table.sort(out)
  return out
end

local function copy_preset(d)
  local e = {}
  for i, x in ipairs(d.entries) do
    e[i] = { kind = x.kind, path = x.path }
  end
  local x = {}
  for i, p in ipairs(d.exclude or {}) do
    x[i] = p
  end
  return { name = d.name, entries = e, exclude = x }
end

local function read_preset_file(f)
  if not f then
    return nil
  end
  local st = uv.fs_stat(f)
  if not st then
    s.preset_memo[f] = nil
    return nil
  end
  local key = stat_key(st)
  local c = s.preset_memo[f]
  if c and c.key == key then
    return copy_preset(c.data)
  end
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(f), '\n'))
  end)
  if not ok or type(data) ~= 'table' or type(data.entries) ~= 'table' then
    s.preset_memo[f] = nil
    return nil
  end
  local entries = {}
  for _, e in ipairs(data.entries) do
    if type(e) == 'table' and type(e.path) == 'string' then
      entries[#entries + 1] = { kind = e.kind or 'file', path = e.path }
    end
  end
  data = { name = data.name, entries = entries, exclude = clean_exclude(data.exclude) }
  s.preset_memo[f] = { key = key, data = data }
  return copy_preset(data)
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

-- 두 preset 이 다른가: 항목과, 디렉터리 항목에서 뺀 것(exclude)까지
local function presets_differ(a, b)
  if entries_differ(a.entries, b.entries) then
    return true
  end
  return table.concat(clean_exclude(a.exclude), '\n')
      ~= table.concat(clean_exclude(b.exclude), '\n')
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
  if mine and sh and presets_differ(mine, sh) then
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
-- "exclude" 는 있을 때만 적는다: 뺀 것이 없는 preset 은 예전과 글자 하나
-- 다르지 않아야 공용 preset 의 diff 가 조용하다.
local function encode_preset(name, entries, exclude)
  -- 따옴표·역슬래시·제어 문자가 없는 경로는 vim.json.encode 와 같은 글자를
  -- 손으로 만든다 (6,000항목이면 encode 가 12,000번이었다)
  local function jstr(v)
    v = tostring(v)
    if v:find('[%c"\\]') then
      return vim.json.encode(v)
    end
    return '"' .. v .. '"'
  end
  local out = { '{', '  "name": ' .. vim.json.encode(name) .. ',',
    '  "entries": [' }
  for i, e in ipairs(entries) do
    out[#out + 1] = ('    {"kind": %s, "path": %s}%s'):format(
      jstr(e.kind or 'file'), jstr(e.path or ''),
      i < #entries and ',' or '')
  end
  local x = clean_exclude(exclude)
  if #x == 0 then
    out[#out + 1] = '  ]'
  else
    out[#out + 1] = '  ],'
    out[#out + 1] = '  "exclude": ['
    for i, p in ipairs(x) do
      out[#out + 1] = '    ' .. jstr(p) .. (i < #x and ',' or '')
    end
    out[#out + 1] = '  ]'
  end
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
  local p = tostring(path or '')
  -- 이미 다듬어진 모양이면 그대로 (preset 을 읽고 쓸 때마다 항목 수천 개가
  -- 여기를 지나간다 - gsub 세 번이 6,000항목에 3ms 였다)
  if not p:find('//', 1, true) and p:sub(1, 2) ~= './' and p:sub(-1) ~= '/' then
    return p
  end
  p = p:gsub('/+', '/')
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
-- 어느 항목 아래에도 있지 않은 제외는 버린다. 덮던 디렉터리 항목이 빠진 뒤
-- 남은 제외는 아무 일도 하지 않다가, 나중에 그 디렉터리를 다시 담으면 그
-- 아래를 조용히 막는다.
local function live_exclude(entries, exclude)
  local inc = {}
  for _, e in ipairs(entries) do
    inc[norm_rel(e.path)] = true
  end
  local out = {}
  for _, x in ipairs(clean_exclude(exclude)) do
    if not inc[x] then
      local p, covered = x, inc['.'] == true
      while not covered do
        p = p:match('^(.*)/[^/]+$')
        if not p or p == '' then
          break
        end
        covered = inc[p] == true
      end
      if covered then
        out[#out + 1] = x
      end
    end
  end
  return out
end

-- exclude 가 nil 이면 지금 preset 의 것을 그대로 둔다 (그것을 모르는 호출부 -
-- Prune, add_for_symbol - 가 뺀 것을 지우지 않게).
local function preset_write(name, entries, exclude)
  local f = preset_path(name)
  local sp = shared_path(name)
  local forking = uv.fs_stat(f) == nil and sp ~= nil and uv.fs_stat(sp) ~= nil
  local clean, dupes = dedupe_entries(entries)
  if dupes > 0 then
    notify(('중복 항목 %d개를 합쳤습니다 (%d -> %d)'):format(
      dupes, #entries, #clean))
  end
  entries = clean
  if exclude == nil then
    local cur = read_preset_file(f) or (sp and read_preset_file(sp)) or nil
    exclude = cur and cur.exclude or {}
  end
  exclude = live_exclude(entries, exclude)
  backup_preset(name)
  local lines = encode_preset(name, entries, exclude)
  local ok = write_json(f, lines)
  if not ok then
    -- 세션 중에 presets 디렉터리가 지워졌으면 한 번 만들고 다시 쓴다
    -- (presets_dir 는 세션에 한 번만 mkdir 한다)
    pcall(vim.fn.mkdir, vim.fs.dirname(f), 'p')
    ok = write_json(f, lines)
  end
  if not ok then
    s.preset_memo[f] = nil
    notify('preset 을 저장하지 못했습니다: ' .. f, vim.log.levels.ERROR)
    return false
  end
  -- 방금 쓴 것을 기억해 둔다: 바로 뒤의 읽기가 JSON 을 다시 풀지 않게
  s.preset_memo[f] = {
    key = stat_key(uv.fs_stat(f)),
    data = copy_preset({ name = name, entries = entries, exclude = exclude }),
  }
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

-- 모드 파일도 stat 으로 기억한다: target_label/active_preset 이 + 한 번에
-- 여섯 번 남짓 이 파일을 읽었다.
s.mode_memo = {}   -- 파일 -> { key =, mode = }

local function mode_of(root)
  local f = active_file(root)
  local st = uv.fs_stat(f)
  if not st then
    s.mode_memo[f] = nil
    -- g:projectfiles_preset 을 정해 뒀으면 그것이 기본값이다
    local d = cfg('preset', nil)
    return d and tostring(d) or MODE_UNSET
  end
  local key = stat_key(st)
  local c = s.mode_memo[f]
  if c and c.key == key then
    return c.mode
  end
  local l = (vim.fn.readfile(f)[1] or ''):gsub('%s+$', '')
  if l == '' then
    l = MODE_AUTO -- 예전 파일: 빈 줄이 '명시적 auto' 였다
  end
  s.mode_memo[f] = { key = key, mode = l }
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
  local ok, ret = pcall(vim.fn.writefile, { v }, f)
  -- 쓴 것을 곧바로 기억한다. 'pfa' -> 'pfb' 처럼 같은 길이를 같은 초에 다시
  -- 쓰면 초 단위 시각만 보는 파일 시스템에서는 stat 이 같아 보인다.
  s.mode_memo[f] = (ok and ret == 0)
      and { key = stat_key(uv.fs_stat(f)), mode = v } or nil
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

-- 빈 목록(.tags/files)이 정말 '아무것도 색인하지 않기'인가 (K3).
--
-- 저장된 preset 이 항목 0개일 때만 그렇다. 저장한 적 없는 이름(오타, 막 시작한
-- 새 preset)의 목록도 비어 있지만, 그건 '아직 아무것도 고르지 않았다'이다.
-- 예전에는 둘을 가리지 않아서 ':ProjectFilesPreset kp1x' 오타 한 번에 GTAGS 가
-- 0개, ctags 가 머리말 24줄이 됐다 (F2). autoindex 는 빈 목록을 보면 이것을
-- 묻고, false 면 색인을 그대로 둔다.
function _G.projectfiles_list_intended_empty(root)
  local name = root and root ~= '' and active_preset(root)
  if not name then
    return false
  end
  local p = preset_read(name)
  return p ~= nil and #(p.entries or {}) == 0
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
--
-- st: 부른 쪽이 이미 한 stat (nil 이면 여기서 한다). 파일 항목 하나가
-- expand_all, expand_entry, 여기서 세 번 stat 되었다 - 느린 stat 의 서버에서
-- 6,000개짜리 목록이면 그것만 +마다 1초 넘게였다 (P2).
-- sk: 뺀 것을 세는 곳 (nil 이면 materialize 의 집계)
local function text_file(path, st, sk)
  sk = sk or skipped
  if st == nil then
    st = uv.fs_stat(path)
  end
  -- 볼 수 없으면 판단하지 않는다: 여기서 거절하면 상대 경로로 불린
  -- 자리에서 멀쩡한 파일이 조용히 빠진다
  if not st or st.type ~= 'file' then
    return true
  end
  local max = tonumber(cfg('max_bytes', 2 * 1024 * 1024)) or 0
  if max > 0 and st.size > max then
    sk.big = sk.big + 1
    if not sk.worst or st.size > sk.worst.size then
      sk.worst = { size = st.size, path = path }
    end
    return false
  end
  if cfg('skip_binary', 1) == 0 then
    return true
  end
  -- 바이너리 판정은 크기·수정 시각이 그대로인 동안 담아 둔다. 항목 하나를
  -- 넣고 뺄 때마다 목록 전체를 다시 펼치는데, 4000개짜리 preset 에서 파일마다
  -- 앞 1KB 를 다시 읽느라 +/-/^d 한 번에 400~850ms 가 멎었다 (QA).
  local key = st.size .. ':' .. st.mtime.sec .. ':' .. (st.mtime.nsec or 0)
  s.bin_cache = s.bin_cache or {}
  local hit = s.bin_cache[path]
  local isbin
  if hit and hit.key == key then
    isbin = hit.bin
  elseif s.known_text and s.known_text[path] and st.ctime
      and st.ctime.sec < s.known_text[path] then
    -- 지난번에 쓴 목록에 있던 파일이고 그 뒤로 inode 가 바뀐 적이 없다
    -- (ctime 은 내용·이름·권한이 바뀌면 함께 바뀌고 되돌릴 수 없다): 그때
    -- 텍스트였으니 지금도 텍스트다. 세션을 새로 열 때마다 목록의 모든 파일
    -- 앞 1KB 를 다시 읽던 것(6,500개에 6,500번 open)을 이것으로 건너뛴다 (P3).
    isbin = false
    s.bin_cache[path] = { key = key, bin = false }
  else
    local fd = uv.fs_open(path, 'r', 438)
    if not fd then
      return true
    end
    local data = uv.fs_read(fd, 1024, 0)
    uv.fs_close(fd)
    isbin = (data and data:find('\0', 1, true)) and true or false
    s.bin_cache[path] = { key = key, bin = isbin }
  end
  if isbin then
    sk.binary = sk.binary + 1
    return false
  end
  return true
end

local function indexed(path, st, sk)
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
    return text_file(path, st, sk)
  end
  if BASE[base] then
    return text_file(path, st, sk)
  end
  local e = base:match('%.([%w_]+)$')
  return e ~= nil and EXT[e] == true and text_file(path, st, sk)
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
local function nested_owner_in(list, rel)
  for _, pre in ipairs(list) do
    if rel:sub(1, #pre) == pre then
      return (pre:gsub('/$', ''))
    end
  end
  return nil
end

-- 경로 하나만 묻는 자리(add_path)는 위로 올라가며 '.tags' 를 직접 본다.
--
-- 목록 전체(nested_prefixes)를 구하는 것은 프로젝트 전체를 훑는 find 이고,
-- 디스크 캐시는 루트의 mtime 이 바뀌면(빌드가 루트에 파일 하나만 만들어도)
-- 버려진다. 그러면 그 뒤 첫 + 가 키를 누른 채 그 find 를 기다렸다 - 실측
-- 1,057 디렉터리에 0.2초, 1만 2천 디렉터리에 4~8초 (P7). 여기서는 많아야
-- nested_depth 번의 lstat 이고, 늘 지금 상태를 본다. 디렉터리 자신이 하위
-- 프로젝트일 때도 잡는다 (README: 그 디렉터리를 담으면 그렇다고 말한다).
local function nested_owner(root, rel, is_dir)
  local depth = tonumber(cfg('nested_depth', 6)) or 6
  if depth <= 0 or rel == '.' or rel == '' or rel:sub(1, 1) == '/' then
    return nil -- 루트 자신의 .tags 는 하위 프로젝트가 아니다
  end
  local d = dbdir() or '.tags'
  local parts = vim.split(rel, '/', { plain = true, trimempty = true })
  local pre = ''
  for i = 1, math.min(is_dir and #parts or #parts - 1, depth) do
    pre = pre .. parts[i] .. '/'
    local st = uv.fs_lstat(root .. '/' .. pre .. d)
    if st and st.type == 'directory' then
      return (pre:gsub('/$', ''))
    end
  end
  return nil
end

-- find 가 늘 가지치기하는 디렉터리 이름들. add_path 도 본다 - 이 안의 경로는
-- 담아도 파일이 하나도 나오지 않는다.
local function pruned_names()
  local out = {}
  for d in tostring(cfg('prune_dirs',
      '.git .svn .hg .tags node_modules __pycache__ .repo .ccache out')):gmatch('%S+') do
    out[#out + 1] = d
  end
  return out
end

-- 경로의 한 마디라도 가지치기 이름(.git, out ...)이나 색인 데이터베이스 자리
-- (.tags)이면 그 이름을 돌려준다. find 를 거치지 않고 경로 하나를 목록에
-- 넣는 자리(+, 저장)가 find 와 같은 것을 빼도록.
local function pruned_part(rel)
  local skip = { [dbdir() or '.tags'] = true }
  for _, d in ipairs(pruned_names()) do
    skip[d] = true
  end
  for part in rel:gmatch('[^/]+') do
    if skip[part] then
      return part
    end
  end
  return nil
end

local function prune_expr()
  local prune = {}
  for _, d in ipairs(pruned_names()) do
    prune[#prune + 1] = "-name '" .. d .. "'"
  end
  return "\\( " .. table.concat(prune, ' -o ') .. " \\) -prune -o "
end

-- 항목 하나의 절대 경로. '.'(트리의 루트 줄에서 + 한 번)은 루트 자신으로:
-- 'root/.' 로 find 하면 'root/./x' 가 나와 rel_to 가 파일마다 fnamemodify 로
-- 떨어지고, 바이너리 판정 캐시의 키(경로)도 다른 모양이 되어 늘 빗나갔다.
local function entry_abs(root, e)
  local p = e.path or ''
  if p == '.' or p == '' then
    return root
  end
  return p:sub(1, 1) == '/' and p or (root .. '/' .. p)
end

-- 무엇이 목록에 드는가: 항목(entries)과 제외(exclude, C5).
--
-- 경로 자신부터 위로 올라가며 처음 만나는 규칙이 이긴다 (gitignore 의 '!' 와
-- 같은 모양). 'drivers' 를 담고 'drivers/net' 을 뺀 뒤 'drivers/net/a.c' 를
-- 담으면 그 파일만 들어간다. 같은 자리에 둘 다 있으면 담는 쪽이 이긴다.
local function make_rules(entries, exclude)
  local inc, exc, any = {}, {}, false
  for _, e in ipairs(entries or {}) do
    inc[norm_rel(e.path)] = true
  end
  for _, x in ipairs(exclude or {}) do
    exc[x] = true
    any = true
  end
  return { inc = inc, exc = exc, any_exc = any }
end

-- true = 든다, false = 뺐다, nil = 어느 항목 아래도 아니다
local function rule_of(rules, rel)
  local p = rel
  while p and p ~= '' do
    if rules.inc[p] then
      return true
    end
    if rules.exc[p] then
      return false
    end
    p = p:match('^(.*)/[^/]+$')
  end
  if rules.inc['.'] then
    return true
  end
  return nil
end

-- rel 의 위에서(자신은 빼고) 처음 만나는 규칙: rel 을 다른 항목이 덮고 있나
local function rule_above(rules, rel)
  local p = rel:match('^(.*)/[^/]+$')
  if p and p ~= '' then
    return rule_of(rules, p)
  end
  return rules.inc['.'] and true or nil
end

-- 디렉터리 항목 여러 개를 find 한 번으로 편다.
--
-- find 는 시작점을 여러 개 받는다. 항목마다 따로 부르면 그만큼 셸을 fork 하고,
-- fork 비용은 부모(nvim)의 크기에 비례해 커진다. dir 항목 17개짜리 실제
-- preset 에서 17번 부르면 118ms, 한 번에 부르면 26ms 였다 - 찾아낸 파일은
-- 1992개로 똑같다.
--
-- 명령줄이 너무 길면 실행 자체가 안 되므로(ARG_MAX) 끊어서 부른다.
local function find_cmds(dirs)
  local pe = prune_expr()
  local cmds = {}
  local i = 1
  while i <= #dirs do
    local args, len = {}, 0
    while i <= #dirs and #args < 500 and len < 100000 do
      local a = vim.fn.shellescape(dirs[i])
      args[#args + 1] = a
      len, i = len + #a + 1, i + 1
    end
    cmds[#cmds + 1] = 'find ' .. table.concat(args, ' ') .. ' ' .. pe ..
        ' -type f -print 2>/dev/null'
  end
  return cmds
end

-- 찾은 파일(절대 경로) 하나를 판정해 상대 경로를 돌려준다 (빠지면 nil).
-- 파일은 전부 찾고 여기서 거른다: 무엇을 넣을지 정하는 곳이 하나여야 '모든
-- 파일' 모드와 허용목록 모드가 어긋나지 않는다. 제외 규칙을 먼저 본다 - 뺀
-- 것으로 정해진 경로에는 stat 도 하지 않는다.
-- seen: 이미 판정한 상대 경로 (항목이 겹치면 - '.' 과 'drivers' - 같은 파일이
-- 두 번 나온다. 두 번 stat 하고 '색인 제외' 를 두 번 세지 않게)
local function keep_file(root, rules, abs, st, sk, seen)
  local rel = rel_to(root, abs)
  if seen then
    if seen[rel] then
      return nil
    end
    seen[rel] = true
  end
  if rules.any_exc and rule_of(rules, rel) ~= true then
    return nil
  end
  if not indexed(abs, st, sk) then
    return nil
  end
  return rel
end

-- preset 항목 전부를 편다. 디렉터리는 묶어서 한 번에 훑는다.
local function expand_all(root, entries, rules, sk)
  local out, dirs, seen = {}, {}, {}
  for _, e in ipairs(entries) do
    local abs = entry_abs(root, e)
    local st = uv.fs_stat(abs)
    -- preset 의 kind 는 적어 둔 값일 뿐이고, 실제로 무엇인지는 파일 시스템이
    -- 답한다 - 디렉터리였던 것이 파일로 바뀌어 있을 수 있다
    if st and st.type == 'directory' then
      dirs[#dirs + 1] = abs
    elseif st and st.type == 'file' then
      -- 여기서 한 stat 을 그대로 넘긴다 (예전에는 같은 파일을 세 번 stat 했다)
      local rel = keep_file(root, rules, abs, st, sk, seen)
      if rel then
        out[#out + 1] = rel
      end
    end
    -- 그 밖(없는 경로, fifo 같은 특수 파일)은 예전처럼 아무것도 내지 않는다
  end
  for _, cmd in ipairs(find_cmds(dirs)) do
    for _, l in ipairs(vim.fn.systemlist(cmd)) do
      if l ~= '' then
        local rel = keep_file(root, rules, l, nil, sk, seen)
        if rel then
          out[#out + 1] = rel
        end
      end
    end
  end
  return out
end

-- expand_all 의 비동기판. 판정은 같은 keep_file 이라 결과가 같다.
-- find 는 자식 프로세스가 하고, 파일마다의 stat 은 메인 루프에서 한 번에
-- 몇 ms 씩만 한다 - 그 사이 키 입력이 처리된다. cb(rels, sk) (실패하면 nil)
local function expand_async(root, entries, rules, cb)
  local sk = { big = 0, binary = 0 }
  local out, dirs, seen = {}, {}, {}
  local function run(items, fn, done)
    local i = 1
    local function step()
      local stop = uv.hrtime() + 8e6
      while i <= #items do
        fn(items[i])
        i = i + 1
        if uv.hrtime() >= stop then
          break
        end
      end
      if i <= #items then
        vim.defer_fn(step, 1)
      else
        done()
      end
    end
    vim.defer_fn(step, 1)
  end
  run(entries, function(e)
    local abs = entry_abs(root, e)
    local st = uv.fs_stat(abs)
    if st and st.type == 'directory' then
      dirs[#dirs + 1] = abs
    elseif st and st.type == 'file' then
      local rel = keep_file(root, rules, abs, st, sk, seen)
      if rel then
        out[#out + 1] = rel
      end
    end
  end, function()
    local cmds, k = find_cmds(dirs), 0
    local function next_cmd()
      k = k + 1
      if k > #cmds then
        return cb(out, sk)
      end
      local ok = pcall(vim.system, { 'sh', '-c', cmds[k] }, { text = true },
        function(o)
          vim.schedule(function()
            run(vim.split(o.stdout or '', '\n', { trimempty = true }), function(l)
              local rel = keep_file(root, rules, l, nil, sk, seen)
              if rel then
                out[#out + 1] = rel
              end
            end, next_cmd)
          end)
        end)
      if not ok then
        cb(nil)
      end
    end
    next_cmd()
  end)
end

-- 배치 중이면 { root =, msgs = {}, done =, pend =, delta =, emptied =, rules = }
-- (in_batch)
local batch = nil

-- 지금 항목·제외의 규칙. 배치 중에는 한 번 만들고 add_path/remove_path 가
-- 바꾼 만큼만 고쳐 쓴다 - 경로마다 새로 만들면 6,000항목에 경로당 몇 ms 씩,
-- 50줄 범위면 그것만 수백 ms 였다.
local function rules_for(root, entries, exclude)
  if batch and batch.root == root then
    if not batch.rules then
      batch.rules = make_rules(entries, exclude)
    end
    return batch.rules
  end
  return make_rules(entries, exclude)
end

local function entries_of(root)
  -- 배치 중에는 아직 쓰지 않은 항목이 지금 상태다 (preset 은 커밋에서 한 번 쓴다)
  if batch and batch.root == root and batch.pend then
    return batch.pend.entries, batch.pend.name, nil, batch.pend.exclude
  end
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
    return {}, name, nil, {} -- named but not saved yet: an empty preset to fill
  end
  return p.entries, name, nil, p.exclude
end

-- ---------------------------------------------------------------------------
-- '<root>/.tags/files' 와 그것을 무엇으로 만들었는지 (C1)
-- ---------------------------------------------------------------------------
local function list_path(root)
  return root .. '/' .. (dbdir() or '.tags') .. '/files'
end

-- 목록 옆에 '이 목록을 어떤 preset 내용과 설정으로 만들었나'를 적어 둔다:
--   1행 내용 키(preset 이름·항목·제외·설정의 sha256)  2행 목록 파일의 stat
--   3행 설정 서명  4행 preset 이름
-- 다음 세션이 같은 내용이면 목록을 다시 펴지 않고 그대로 받는다 (adopt).
local function key_path(root)
  return list_path(root) .. '.key'
end

-- 목록에 무엇이 드는지를 바꾸는 설정들 (한 줄짜리 해시로)
local function cfg_sig()
  local t = {}
  for _, k in ipairs({ 'all_files', 'max_bytes', 'skip_binary', 'nested_presets',
      'nested_depth', 'exts', 'exts_extra', 'names', 'names_extra',
      'exclude_exts', 'exclude_exts_extra', 'exclude_names',
      'exclude_names_extra', 'prune_dirs' }) do
    t[#t + 1] = tostring(cfg(k, ''))
  end
  return vim.fn.sha256(table.concat(t, '\1')):sub(1, 16)
end

local function content_key(name, entries, exclude)
  local t = { tostring(name), cfg_sig() }
  for _, e in ipairs(entries or {}) do
    t[#t + 1] = (e.kind or 'file') .. ' ' .. tostring(e.path)
  end
  t[#t + 1] = '!'
  for _, x in ipairs(exclude or {}) do
    t[#t + 1] = x
  end
  return vim.fn.sha256(table.concat(t, '\n'))
end

-- preset 파일(내 사본, 공용본)의 stat. 다른 nvim 이 preset 을 고쳤는지 본다.
local function preset_key(name)
  local sp = shared_path(name)
  return stat_key(uv.fs_stat(preset_path(name))) .. '|'
      .. stat_key(sp and uv.fs_stat(sp) or nil)
end

local function read_key(root)
  local ok, l = pcall(vim.fn.readfile, key_path(root), '', 4)
  if ok and l and #l >= 4 then
    return { ckey = l[1], lkey = l[2], sig = l[3], name = l[4] }
  end
  return nil
end

-- 작은 파일이라 io 로 쓴다 (writefile 은 'fsync' 로 + 마다 몇 ms 를 더 썼다)
local function write_key(root, ckey, st, name)
  local k = read_key(root)
  local lines = { ckey, stat_key(st), cfg_sig(), tostring(name) }
  if k and k.ckey == lines[1] and k.lkey == lines[2] and k.sig == lines[3]
      and k.name == lines[4] then
    return
  end
  local fh = io.open(key_path(root), 'w')
  if fh then
    fh:write(table.concat(lines, '\n'), '\n')
    fh:close()
  end
end

-- 목록 파일을 쓴다. 내용이 같으면 쓰지 않는다 (P8).
--
-- 목록을 stat 키로 기억하는 쪽들(트리 표시, \fo, RelationView, autoindex)은
-- 다시 쓰일 때마다 6,500줄을 다시 읽는데, 내용이 같은 목록을 시작할 때마다
-- 두세 번, +/- 마다 두 번 다시 썼다. 비교는 디스크와 한다 - 기억(s.cache)만
-- 믿으면 목록 파일이 지워졌거나 쓰기가 실패했을 때 다시 만들지 않는다
-- (반대 심문: 그러면 indexfiles.sh 가 git ls-files 로 떨어져 preset 밖의
-- 파일까지 색인했다).
--
-- 쓸 때는 옆에 쓰고 이름을 바꾼다. 제자리 쓰기는 파일을 먼저 비우므로, 그
-- 순간 indexfiles.sh 가 읽으면 반쪽 목록으로 'gtags -i' 가 색인을 줄인다
-- (6,500줄을 되풀이해 쓰는 동안 읽는 쪽이 784번 중 35번 잘린 목록을 봤다).
-- 돌려주는 것: 바뀌었나, 성공했나, 쓴 뒤의 stat
local function write_list(root, files)
  local list = list_path(root)
  local st = uv.fs_stat(list)
  if st and st.type == 'file' then
    local size = 0
    for _, f in ipairs(files) do
      size = size + #f + 1
    end
    if size == st.size then
      local c = s.cache[root]
      local cur
      if c and c.files and c.list_key == stat_key(st) then
        cur = c.files -- 디스크와 같다고 확인해 둔 기억
      else
        local ok, lines = pcall(vim.fn.readfile, list)
        cur = ok and lines or nil
      end
      if cur and #cur == #files then
        local same = true
        for i = 1, #files do
          if cur[i] ~= files[i] then
            same = false
            break
          end
        end
        if same then
          return false, true, st
        end
      end
    end
  end
  pcall(vim.fn.mkdir, vim.fs.dirname(list), 'p')
  local tmp = ('%s.%d.tmp'):format(list, uv.os_getpid())
  local fh = io.open(tmp, 'w')
  local ok = fh ~= nil
  if fh then
    ok = fh:write(table.concat(files, '\n'), #files > 0 and '\n' or '') ~= nil
    ok = fh:close() and ok
  end
  ok = ok and uv.fs_rename(tmp, list) and true or false
  if not ok then
    pcall(os.remove, tmp)
    return false, false, uv.fs_stat(list)
  end
  return true, true, uv.fs_stat(list)
end

-- 정렬된 목록에서 x 보다 작지 않은 첫 자리. 정렬된 목록에서는 한 접두어로
-- 시작하는 줄이 한데 모여 있어서, 디렉터리 하나 아래를 반씩 나눠 찾을 수 있다.
local function lower_bound(list, x)
  local lo, hi = 1, #list + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if list[mid] < x then
      lo = mid + 1
    else
      hi = mid
    end
  end
  return lo
end

-- 지난번에 쓴 목록을 '그때 텍스트로 판정된 파일'로 기억한다 (text_file 이
-- 그런 파일은 앞 1KB 를 다시 읽지 않는다). 목록을 쓰기 전 1분 안에 바뀐
-- 파일은 다시 본다 - 펴는 동안 바뀌었을 수 있고, 시계가 조금 어긋나도 되게.
local function learn_known(root, files, st)
  s.known_text = s.known_text or {}
  local cut = st.mtime.sec - 60
  for _, f in ipairs(files) do
    s.known_text[f:sub(1, 1) == '/' and f or (root .. '/' .. f)] = cut
  end
end

-- 세션에서 처음 펼 때 한 번: 우리가 같은 설정으로 쓴 목록일 때만 믿는다
local function load_known(root)
  s.known_loaded = s.known_loaded or {}
  if s.known_loaded[root] then
    return
  end
  s.known_loaded[root] = true
  local k = read_key(root)
  local st = uv.fs_stat(list_path(root))
  if not (k and st and k.sig == cfg_sig() and k.lkey == stat_key(st)) then
    return
  end
  local ok, lines = pcall(vim.fn.readfile, list_path(root))
  if ok then
    learn_known(root, lines, st)
  end
end

-- write '<root>/.tags/files' (preset mode) or remove it (auto mode)
-- 돌려주는 것: 목록(정렬됨, 못 만들었으면 nil), preset 이름, 바뀌었나
-- got: 뒤에서 미리 편 것 { found =, sk =, pre =, ckey = } (:ProjectFilesReindex,
-- P2). 그 사이 항목이 바뀌었으면(ckey 가 다르다) 쓰지 않고 여기서 다시 편다.
local function materialize(root, got)
  local entries, name, bad, exclude = entries_of(root)
  if bad then
    return nil, nil -- 읽을 수 없는 preset: 목록도 색인도 그대로 둔다
  end
  local list = list_path(root)
  if not entries then
    local had = uv.fs_stat(list) ~= nil
    if had then
      pcall(vim.fn.delete, list)
    end
    pcall(vim.fn.delete, key_path(root))
    s.cache[root] = { files = nil, entries = nil, preset = nil }
    return nil, nil, had
  end
  load_known(root)
  if got and got.ckey ~= content_key(name, entries, exclude) then
    got = nil
  end
  local files, seen = {}, {}
  -- preset 항목은 사람이 고른 것이라 기본적으로 걸르지 않는다 (위 설명 참고)
  local pre = got and got.pre
    or (cfg('nested_presets', 0) ~= 0 and nested_prefixes(root) or {})
  local dropped = 0
  skipped = got and got.sk or { big = 0, binary = 0, worst = nil }
  for _, f in ipairs(got and got.found
      or expand_all(root, entries, make_rules(entries, exclude))) do
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
  --
  -- 한 줄을 넘기지 않는다. 예전에는 가장 큰 파일 이름과 옵션 두 개를 모두
  -- 적어서 110자가 넘었고, 그러면 vim 이 'Press ENTER or type command to
  -- continue' 로 멈춰 선다. 이 알림은 시작할 때 뜨므로, 매번 키를 한 번씩
  -- 더 눌러야 했다 - 사용자에게는 '시작이 느려졌다'로 보인다.
  -- 자세한 것은 :ProjectFilesSkipped 로 본다.
  if (skipped.big + skipped.binary) > 0 then
    local key = ('%s\0%d\0%d'):format(root, skipped.big, skipped.binary)
    s.skip_detail = {
      root = root, big = skipped.big, binary = skipped.binary,
      worst = skipped.worst,
      max = tonumber(cfg('max_bytes', 2 * 1024 * 1024)) or 0,
    }
    if s.skip_told ~= key then
      s.skip_told = key
      local parts = {}
      if skipped.binary > 0 then
        parts[#parts + 1] = ('바이너리 %d'):format(skipped.binary)
      end
      if skipped.big > 0 then
        parts[#parts + 1] = ('%.0fMB 초과 %d'):format(
          (tonumber(cfg('max_bytes', 2 * 1024 * 1024)) or 0) / 1048576, skipped.big)
      end
      notify('색인 제외: ' .. table.concat(parts, ', ') .. '  (:ProjectFilesSkipped)')
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
    -- 항목을 빼다 이렇게 된 경우는 부른 쪽(none_for_empty)이 따로 알린다
    --
    -- 한 세션에 (루트, preset, 내용)마다 한 번만 알린다 (R4). 이때는 목록도
    -- 기억(s.cache)도 남지 않아서 목록을 찾는 쪽(autoindex 의 BufReadPre 세기,
    -- 첫 빌드, 시작 갱신, VimEnter 뒤 확인)이 부를 때마다 다시 펴고 다시
    -- 알렸다 - 한 세션에 같은 경고가 다섯 번. 화면이 뜨기 전에 난 것은 F6 처럼
    -- VimEnter 뒤로 미룬다: 바로 내면 autoindex 의 알림과 쌓여 첫 화면에
    -- Press ENTER 가 떴고, 키를 누를 때까지 시작 갱신이 멈췄다.
    if not s.quiet_empty then
      local key = root .. '\0' .. tostring(name) .. '\0'
        .. content_key(name, entries, exclude)
      s.empty_told = s.empty_told or {}
      if not s.empty_told[key] then
        s.empty_told[key] = true
        local msg = ("preset '%s' 의 경로가 이 프로젝트에서 하나도 펼쳐지지 않았습니다"):format(
            name or '?')
          .. ' — 목록과 색인을 그대로 둡니다. 다른 체크아웃의 preset 이거나'
          .. ' 전부 하위 프로젝트 안입니다.'
        if s.collect or vim.v.vim_did_enter == 1 then
          notify(msg, vim.log.levels.WARN) -- 모으는 중이면 모으는 쪽이 낸다
        else
          api.nvim_create_autocmd('VimEnter', { group = group, once = true,
            callback = function()
              vim.schedule(function()
                notify(msg, vim.log.levels.WARN)
              end)
            end })
        end
      end
    end
    return nil, name
  end
  table.sort(files)
  local changed, ok, st = write_list(root, files)
  if not ok then
    s.cache[root] = nil
    notify('색인 목록을 쓰지 못했습니다: ' .. vim.fn.fnamemodify(list, ':~'),
      vim.log.levels.ERROR)
    return files, name, false
  end
  local ckey = content_key(name, entries, exclude)
  s.cache[root] = {
    files = files, entries = entries, exclude = exclude, preset = name,
    list_key = stat_key(st), pkey = preset_key(name), ckey = ckey,
    verified = true,
  }
  write_key(root, ckey, st, name)
  return files, name, changed
end

-- 바뀐 항목만큼만 목록을 고친다 (P1).
--
-- 예전에는 +/- 한 번마다 preset 전체를 두 번 다시 폈다 (여기서 한 번, 이어
-- autoindex 의 refresh 가 _G.projectfiles_materialize 로 또 한 번). 디렉터리
-- 항목마다 find, 목록의 파일마다 stat - 6,500개에 13,000번의 stat 이 키를
-- 누른 채 돌았고, 느린 stat 의 서버를 흉내 내면 +/- 한 번이 1.7~4초였다.
-- 여기서는 바뀐 경로 아래만 본다.
--
--   delta.drop  빠진 상대 경로들 (그 자신과 그 아래가 목록에서 빠진다)
--   delta.add   새로 들 수 있는 경로들 { abs =, st = } (파일이면 그것,
--               디렉터리면 그 아래를 find - 그 아래 목록은 찾은 것이 된다)
-- 디스크의 preset 은 이미 바뀐 뒤이고, 판정은 바뀐 뒤의 규칙으로 한다. 빼는
-- 것을 먼저, 더하는 것을 나중에 하면 배치로 모은 순서와 상관없이 통째로 편
-- 것과 같다 (빼기는 그 경로 아래의 규칙만 바꾸고, 더하기는 그 경로 아래를
-- 새 규칙으로 다시 찾는다).
--
-- 기억이 없거나 이 preset 것이 아니면 false: 부른 쪽이 통째로 편다. 디렉터리
-- 항목 아래에 그새 생긴 파일은 여기서 보지 않는다 - :ProjectFilesReindex,
-- 세션 시작(verify_async), 새 파일 저장이 잡는다.
local function apply_delta(root, delta)
  local c = s.cache[root]
  if not (c and c.files) or cfg('nested_presets', 0) ~= 0 then
    return false
  end
  local entries, name, bad, exclude = entries_of(root)
  if bad or not name or name ~= c.preset or #entries == 0 then
    return false
  end
  local files, removed, added = c.files, {}, {}
  -- 빼기: 목록이 정렬돼 있으니 빠질 경로마다 그 자신과 'p/' 로 시작하는
  -- 한 덩어리를 반씩 나눠 찾는다 (줄마다 조상을 훑지 않는다)
  local del = {}
  for _, p in ipairs(delta.drop or {}) do
    if p == '.' or p == '' or p:sub(1, 1) == '/' then
      return false -- 루트 항목이나 프로젝트 밖: 통째로
    end
    local i = lower_bound(files, p)
    if files[i] == p then
      del[i] = true
    end
    local pre = p .. '/'
    i = lower_bound(files, pre)
    while files[i] and files[i]:sub(1, #pre) == pre do
      del[i] = true
      i = i + 1
    end
  end
  if next(del) then
    local kept = {}
    for i, f in ipairs(files) do
      if del[i] then
        removed[#removed + 1] = f
      else
        kept[#kept + 1] = f
      end
    end
    files = kept
  end
  if #(delta.add or {}) > 0 then
    local rules = make_rules(entries, exclude)
    local have = {} -- 이번에 더한 것 (목록에 이미 있는지는 반씩 나눠 찾는다)
    local found = {} -- 찾아서 남긴 것 전부 (목록에 이미 있던 것까지)
    local turned = {} -- find 가 내놓았지만 지금 규칙이 거른 것 (바이너리가 됐다 등)
    local sk = { big = 0, binary = 0 }
    local dirs = {}
    local function take(abs, st)
      local rel = keep_file(root, rules, abs, st, sk)
      if rel then
        found[rel] = true
      elseif not st then
        turned[rel_to(root, abs)] = true
      end
      if rel and not have[rel] and files[lower_bound(files, rel)] ~= rel then
        have[rel] = true
        added[#added + 1] = rel
      end
    end
    for _, a in ipairs(delta.add) do
      local st = a.st or uv.fs_stat(a.abs)
      if st and st.type == 'directory' then
        dirs[#dirs + 1] = a.abs
      elseif st and st.type == 'file' and not pruned_part(rel_to(root, a.abs)) then
        take(a.abs, st) -- find 를 거치지 않으니 가지치기는 여기서 본다
      end
    end
    local find_ok = true
    for _, cmd in ipairs(find_cmds(dirs)) do
      local out = vim.fn.systemlist(cmd)
      if #out == 0 and vim.v.shell_error ~= 0 then
        find_ok = false -- find 가 아예 못 돌았다: 아래에서 빼지 않는다
      end
      for _, l in ipairs(out) do
        if l ~= '' then
          take(l, nil)
        end
      end
    end
    -- 디렉터리를 다시 찾았으면 그 아래는 찾은 것이 전부다 (N3). 이미 담은
    -- 디렉터리를 + 로 다시 훑을 때(F8) 새 파일만 더하고 셸이나 git 이 그새
    -- 지운 파일은 목록에 남겨서, \fo 에 계속 보였고 GTAGS 도 다음 gtags -i
    -- 까지 그것을 답했다 - 알림은 '새 파일 없음' 이라 맞는 것처럼 보였다.
    --
    -- 다만 'find 가 이번에 못 봤다' 가 곧 '지워졌다' 는 아니다 (D1). d 아래의
    -- 다른 항목이 담은 것 중에 이 find 가 닿지 않는 것이 있다 - 가지치기 이름
    -- 안의 항목(drivers/net/out/gen, node_modules/x: 이 find 는 out/ 를 쳐 내지만
    -- 통째로 펴는 쪽은 그 항목 자체를 find 한다), 심볼릭 링크로 든 디렉터리,
    -- 파일 항목. 예전에는 파일 항목만 stat 으로 지켜서 나머지는 디스크에 멀쩡히
    -- 있는데도 목록과 GTAGS·ctags 에서 빠졌고, 알림은 '사라진 파일 N개' 였다
    -- (\fR 이 도로 넣고, 다음 + 가 또 뺐다). 그래서 find 가 못 본 것은 전부 stat
    -- 하고 더는 보통 파일이 아닐 때만 뺀다 - 보통은 지운 파일만 stat 된다. find 가
    -- 내놓았는데 지금 규칙이 거른 것(바이너리·크기)은 통째로 펼 때처럼 뺀다.
    if find_ok and #dirs > 0 then
      local gone = {}
      for _, d in ipairs(dirs) do
        local r = rel_to(root, d)
        local pre = r == '.' and '' or (r .. '/')
        local i = lower_bound(files, pre)
        while files[i] and files[i]:sub(1, #pre) == pre do
          local f = files[i]
          if turned[f] then
            gone[i] = true
          elseif not found[f] then
            local fst = uv.fs_stat(f:sub(1, 1) == '/' and f or (root .. '/' .. f))
            if not (fst and fst.type == 'file') then
              gone[i] = true
            end
          end
          i = i + 1
        end
      end
      if next(gone) then
        local kept = {}
        for i, f in ipairs(files) do
          if gone[i] then
            removed[#removed + 1] = f
          else
            kept[#kept + 1] = f
          end
        end
        files = kept
      end
    end
    -- 담았지만 색인에서 빠진 것 (통째로 펼 때의 '색인 제외' 알림 대신)
    if sk.big + sk.binary > 0 then
      local parts = {}
      if sk.binary > 0 then
        parts[#parts + 1] = ('바이너리 %d'):format(sk.binary)
      end
      if sk.big > 0 then
        parts[#parts + 1] = ('%.0fMB 초과 %d'):format(
          (tonumber(cfg('max_bytes', 2 * 1024 * 1024)) or 0) / 1048576, sk.big)
      end
      notify('색인 제외: ' .. table.concat(parts, ', '))
    end
  end
  -- 빈 목록의 규칙(none 모드로 가기, 쓰지 않기)은 통째로 펴는 쪽이 정한다
  if #files + #added == 0 then
    return false
  end
  if #added > 0 then
    -- 정렬된 둘을 합친다 (목록 전체를 다시 정렬하지 않는다)
    table.sort(added)
    local merged, i, j = {}, 1, 1
    while i <= #files or j <= #added do
      if j > #added or (i <= #files and files[i] < added[j]) then
        merged[#merged + 1] = files[i]
        i = i + 1
      else
        merged[#merged + 1] = added[j]
        j = j + 1
      end
    end
    files = merged
  end
  local changed, ok, st = write_list(root, files)
  if not ok then
    s.cache[root] = nil
    return false
  end
  c.files, c.entries, c.exclude = files, entries, exclude
  c.list_key, c.pkey = stat_key(st), preset_key(name)
  c.ckey = content_key(name, entries, exclude)
  write_key(root, c.ckey, st, name)
  local function abs_list(rels)
    local out = {}
    for i, r in ipairs(rels) do
      out[i] = r:sub(1, 1) == '/' and r or (root .. '/' .. r)
    end
    return out
  end
  return files, name, changed, { added = abs_list(added), removed = abs_list(removed) }
end

-- 지금 기억(s.cache)이 디스크의 이 preset 과 목록 그대로인가. 고치기 전에
-- 본다: 다른 nvim 이 preset 이나 목록을 그새 바꿨으면 바뀐 만큼만 고칠 수
-- 없다 - 그 기억에 고친 것을 얹으면 그쪽이 더한 것이 빠진다.
local function cache_valid(root, name)
  local c = s.cache[root]
  return c ~= nil and c.files ~= nil and c.preset == name
      and c.list_key == stat_key(uv.fs_stat(list_path(root)))
      and c.pkey == preset_key(name)
end

local reindex -- 아래 (reindex what we just decided)

-- 세션을 시작할 때 지난번 목록을 받는다. 다시 펴지 않고 그대로 쓰고,
-- verify_async 가 뒤에서 한 번 다시 펴서 다른 것만 고친다.
--   known = 같은 설정으로 우리가 쓴 그 목록이다(files.key) - 그 목록의
--           파일은 바이너리 판정을 다시 하지 않는다 (learn_known)
-- 정렬이 깨진 목록(손으로 고쳤다)은 받지 않는다 - apply_delta 가 정렬을 믿는다.
local function adopt(root, name, entries, exclude, ckey, lst, known)
  local ok, lines = pcall(vim.fn.readfile, list_path(root))
  if not ok then
    return false
  end
  for i = 2, #lines do
    if lines[i - 1] >= lines[i] then
      return false
    end
  end
  if lines[#lines] == '' then
    return false
  end
  s.cache[root] = {
    files = lines, entries = entries, exclude = exclude, preset = name,
    list_key = stat_key(lst), pkey = preset_key(name), ckey = ckey,
    verified = false,
  }
  s.known_loaded = s.known_loaded or {}
  if not s.known_loaded[root] then
    s.known_loaded[root] = true
    if known then
      learn_known(root, lines, lst)
    end
  end
  return true
end

-- 받아 둔 목록을 뒤에서 한 번 다시 편다 (세션마다 한 번).
--
-- 디렉터리 항목 아래에 세션 사이에 생기거나 없어진 파일(git pull, 빌드
-- 산출물)을 잡는 자리다. 예전에는 플러그인을 읽는 순간 목록 전체를 동기로
-- 다시 폈다 - 6,600개에 0.5~1초, 느린 stat 을 흉내 내면 3~4초 동안 첫 화면이
-- 뜨지 않았다 (P3). 여기서는 find 는 자식 프로세스가, 파일마다의 stat 은
-- 메인 루프에서 몇 ms 씩 나눠 한다. 달라진 것이 있을 때만 목록을 쓰고
-- 재색인한다 (더하고 뺀 파일을 함께 넘긴다, C3).
local function verify_async(root)
  local c = s.cache[root]
  if not c or not c.files or c.verified or c.verifying then
    return
  end
  c.verifying = true
  local ckey, entries = c.ckey, c.entries
  -- 하위 프로젝트(자기 .tags 가 있는 디렉터리)를 거르는 설정
  -- (g:projectfiles_nested_presets)에서도 확인한다 (INT6). 예전에는 그때 확인을
  -- 건너뛰어서, 세션 사이에 디렉터리 항목 아래 생긴 파일이 다음 \fR 까지 목록과
  -- 색인에 없었고 지운 파일은 남았다 (그 전 판은 시작할 때마다 통째로 폈다).
  -- 거를 접두어도 materialize 와 같은 것을, 메인 루프를 잡지 않고 구한다.
  local function check(pre)
    expand_async(root, entries, make_rules(entries, c.exclude), function(found, sk)
      c.verifying = false
      if s.cache[root] ~= c then
        return -- 그새 통째로 다시 폈다
      end
      if c.ckey ~= ckey then
        return verify_async(root) -- 그새 +/- 가 있었다: 지금 항목으로 다시
      end
      c.verified = true
      if not found then
        return
      end
      local files, seen = {}, {}
      for _, f in ipairs(found) do
        if not seen[f] then
          seen[f] = true
          local nested = false
          for _, q in ipairs(pre) do
            if f:sub(1, #q) == q then
              nested = true
              break
            end
          end
          if not nested then
            files[#files + 1] = f
          end
        end
      end
      if (sk.big + sk.binary) > 0 then
        s.skip_detail = {
          root = root, big = sk.big, binary = sk.binary, worst = sk.worst,
          max = tonumber(cfg('max_bytes', 2 * 1024 * 1024)) or 0,
        }
      end
      if #files == 0 and #entries > 0 then
        return -- 빈 목록은 쓰지 않는다 (materialize 와 같은 규칙)
      end
      if stat_key(uv.fs_stat(list_path(root))) ~= c.list_key then
        return -- 그새 다른 손(다른 nvim)이 목록을 바꿨다
      end
      table.sort(files)
      local added, removed = {}, {}
      local old = {}
      for _, f in ipairs(c.files) do
        old[f] = true
      end
      for _, f in ipairs(files) do
        if not old[f] then
          added[#added + 1] = root .. '/' .. f
        end
        old[f] = nil
      end
      for f in pairs(old) do
        removed[#removed + 1] = root .. '/' .. f
      end
      if #added == 0 and #removed == 0 then
        -- 그대로다: 이 목록을 지금 내용과 설정으로 확인했다고 적어 둔다 - 다음
        -- 세션이 바이너리 판정을 다시 하지 않는다 (예전 판이 쓴 목록이었어도)
        write_key(root, c.ckey, uv.fs_stat(list_path(root)), c.preset)
        return
      end
      local _, ok, st = write_list(root, files)
      if not ok then
        return
      end
      c.files, c.list_key = files, stat_key(st)
      write_key(root, c.ckey, st, c.preset)
      if reindex then
        reindex(root, { added = added, removed = removed })
      end
    end)
  end
  if cfg('nested_presets', 0) ~= 0 then
    nested_prefixes_async(root, check)
  else
    check({})
  end
end

-- autoindex.lua calls this before it builds a file list, so a preset is in
-- place BEFORE the first index runs (otherwise the very first build - the one
-- that happens when a project has no index yet - would index the whole tree)
--
-- 같은 것을 두 번 펴지 않는다 (C1). +/- 는 목록을 고친 직후 autoindex 의
-- refresh 를 부르고, refresh 는 목록을 만들기 전에 늘 이것을 부른다 - 그래서
-- 키 한 번에 preset 이 두 번 펴졌다. 목록 파일·preset 파일·모드 파일의
-- stat(mtime 나노초와 크기까지)이 마지막으로 편 뒤 그대로면 바로 돌아간다.
-- 목록이 바뀌었으면 true, 아니면 false.
function _G.projectfiles_materialize(root)
  if not root or root == '' then
    return false
  end
  local name = active_preset(root)
  if not name then
    return false -- auto/none/미설정: 쓸 목록이 없다
  end
  local c = s.cache[root]
  local lst = uv.fs_stat(list_path(root))
  local lkey = stat_key(lst)
  if c and c.files and c.preset == name and c.list_key == lkey
      and c.pkey == preset_key(name) then
    verify_async(root)
    return false
  end
  local entries, nm, bad, exclude = entries_of(root)
  if bad or not entries then
    return false -- 읽을 수 없는 preset: 쓸 것이 없다
  end
  -- 같은 내용을 다시 쓴 것뿐이면(다른 nvim 이 같은 preset 을 저장했다) 다시
  -- 펴지 않는다
  local ckey = content_key(nm, entries, exclude)
  if c and c.files and c.preset == nm and c.ckey == ckey and c.list_key == lkey then
    c.pkey = preset_key(nm)
    return false
  end
  -- 세션의 처음: 지난번 목록을 그대로 받고 뒤에서 확인한다 (P3). 그 목록이
  -- 지금 preset 내용으로 만든 것이 아니어도(git pull 이 공용 preset 을 바꿨다)
  -- 받는다 - 다른 것만 verify_async 가 곧 고친다. 다른 preset 의 목록이면
  -- (모드를 그새 바꿨다) 지금 편다: 그 목록으로 색인을 시작하면 안 된다.
  if not (c and c.files) and lst then
    local k = read_key(root)
    -- 우리가 같은 설정으로 쓴 그 목록인가 (그렇다면 그 파일들은 텍스트였다)
    local known = k and k.lkey == lkey and k.sig == cfg_sig()
    if (not k or k.name == nm)
        and adopt(root, nm, entries, exclude, ckey, lst, known) then
      verify_async(root)
      return false
    end
  end
  local _, _, changed = materialize(root)
  return changed and true or false
end

-- ---------------------------------------------------------------------------
-- reindex what we just decided
-- ---------------------------------------------------------------------------
-- The list just changed on purpose, so the incremental refresh runs with a
-- bang: 'gtags -i' makes the database equal to the list (it drops what is no
-- longer there), and the usual "this would shrink the index" guard must not
-- get in the way.
--
-- changes = { added = {절대 경로}, removed = {절대 경로} } - 이번에 목록에
-- 들고 빠진 파일 (C3). autoindex 는 이것으로 더한 파일을 먼저 색인해 둘 수
-- 있다. nil 은 '모른다'(통째로 다시 편 경우) - 보통의 강제 갱신이다.
-- 돌려주는 것: autoindex 가 맡았으면(또는 색인할 것이 없는 모드면) true
reindex = function(root, changes)
  if s.symbols then
    s.symbols[root] = nil -- the symbol list is about to change
  end
  if type(_G.projectfiles_tree_invalidate) == 'function' then
    pcall(_G.projectfiles_tree_invalidate) -- 트리 표시도 다시 계산되게
  end
  -- none / 미설정 모드에서는 색인을 건드리지 않는다 (T2). 마지막 항목을 빼서
  -- none 이 된 직후에도 이 강제 갱신이 돌았는데, 목록 파일이 없으니
  -- indexfiles.sh 가 git ls-files 로 떨어져 프로젝트 전체를 색인했다 (실측:
  -- 50개짜리 색인이 none 모드에서 6,500개가 됐다). gutentags 도 같은 길로
  -- 트리 전체를 ctags 했다. 있던 색인은 그대로 둔다.
  if not mode_indexes(root) then
    return true
  end
  -- 루트를 그대로 넘긴다. ':GtagsIndexRefresh' 는 현재 버퍼에서 프로젝트를
  -- 다시 찾는데, 트리 창이나 telescope 프롬프트에서 부르면 그 버퍼에 이름이
  -- 없어서 cwd 로 떨어진다 - cwd 가 다른 프로젝트면 엉뚱한 색인을 갱신하거나
  -- 아무 것도 하지 않는다. 그래서 여기서 목록을 고친 프로젝트를 직접 준다.
  local done = false
  if type(_G.autoindex_refresh) == 'function' then
    local ok, res = pcall(_G.autoindex_refresh, root, true, '목록 변경', changes)
    done = ok and res == true
  end
  if not done and vim.fn.exists(':GtagsIndexRefresh') == 2 then
    pcall(vim.cmd, 'GtagsIndexRefresh!')
  end
  -- ctags(gutentags) 스냅숏은 autoindex 만 다시 만든다 (K2). 여기서도
  -- GutentagsUpdate! 를 부르면 autoindex 의 ctags_follow 가 갱신이 끝날 때 또
  -- 불러서 +/- 한 번에 ctags 전체가 두 번 돌았다 (INT2, 실측 0.4초 x 2). 게다가
  -- 이 호출은 '지금 버퍼'의 프로젝트를 다시 만든다 - 다른 프로젝트의 트리
  -- 창에서 + 하면 엉뚱한 tags 를 다시 썼다. autoindex 가 갱신을 맡았으면
  -- (done) 그쪽이 끝나며 따라간다. 맡지 않았으면(꺼져 있다) 루트를 짚어 부탁한다.
  -- autoindex 가 아예 없을 때만 예전처럼 직접 부른다.
  if done then
    return true
  end
  if type(_G.autoindex_ctags_refresh) == 'function' then
    pcall(_G.autoindex_ctags_refresh, root)
  elseif vim.fn.exists(':GutentagsUpdate') == 2 and vim.b.gutentags_files ~= nil then
    pcall(vim.cmd, 'silent! GutentagsUpdate!')
  end
  return false
end

-- ---------------------------------------------------------------------------
-- entry editing
-- ---------------------------------------------------------------------------
-- 여러 경로를 한 번에 담거나 뺄 때(트리에서 범위를 골랐을 때) 쓰는 문맥.
--
-- add_path 하나가 preset 쓰기 + 목록 고치기 + 재색인까지 전부 한다. 50줄을
-- 고르면 그게 50번 도는데, 중간 상태는 아무도 보지 않는다. 그래서 배치
-- 중에는 바뀐 항목을 메모리에만 두고(entries_of 가 그것을 돌려준다) preset
-- 쓰기와 목록 고치기, 재색인을 끝에서 한 번만 한다. 알림도 모아서 한 줄로.
-- (예전에는 preset 파일은 경로마다 다시 쓰고 다시 읽었다 - 50개를 6,500항목
-- preset 에 담는 데 0.8초, 그중 preset 쓰기만 0.5초였다. S7)

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

-- 남은 preset 항목이 이 체크아웃에서 하나도 펼쳐지지 않을 때: none 모드
local function none_for_empty(root, name)
  set_last(root, name)
  set_active(root, MODE_NONE)
  materialize(root) -- none 모드: .tags/files 를 지우고 캐시를 비운다
  reindex(root) -- 표시만 다시 (none 이라 색인은 건드리지 않는다)
  notify(("preset '%s' 의 남은 항목이 이 체크아웃에 없어 none 모드로 돌아갑니다 (preset 과 있던 색인은 그대로)")
    :format(name), vim.log.levels.WARN)
end

-- 목록을 고친다: 바뀐 만큼 고칠 수 있으면 그렇게(apply_delta), 아니면 통째로.
-- 돌려주는 것: 목록, preset 이름, 바뀐 파일(모르면 nil)
local function commit_list(root, delta)
  if delta then
    local files, nm, _, changes = apply_delta(root, delta)
    if files then
      return files, nm, changes
    end
  end
  local files, nm = materialize(root)
  return files, nm, nil
end

-- 항목을 저장하고 목록을 고친 뒤 재색인한다.
--   exclude  nil 이면 지금 preset 의 것을 그대로 (preset_write)
--   delta    바뀐 만큼 (apply_delta 참고). nil 이면 목록을 통째로 다시 편다
--   opts.no_reindex  목록까지만 (add_for_symbol: 즉시 색인 뒤에 직접 부른다)
-- 돌려주는 것: 목록, 바뀐 파일
local function save_entries(root, name, entries, exclude, delta, opts)
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
      s.preset_memo[mine] = nil
    end
    set_last(root, name)
    -- 예전에는 여기서 auto 로 돌아갔다. 이제 none 이 있으니 그쪽이 맞다 -
    -- '담아 둔 것이 하나도 남지 않았다'가 '프로젝트 전체를 색인해라'로
    -- 바뀌는 것은 놀라운 일이다. :ProjectFilesRestore 로 되돌릴 수 있다.
    set_active(root, MODE_NONE)
    if batch and batch.root == root then
      batch.emptied = name
      batch.pend = nil
      batch.rules = nil
      return nil -- 커밋은 배치 끝에서
    end
    materialize(root)
    reindex(root) -- 표시만 다시: none 모드는 색인하지 않는다 (T2)
    local sp = shared_path(name)
    notify(sp and uv.fs_stat(sp)
      and ("목록이 비어 none 모드로 돌아갑니다 (내 '%s' 사본은 지웠고 vim-ide "
        .. '공용본과 있던 색인은 그대로입니다)'):format(name)
      or '목록이 비어 none 모드로 돌아갑니다 (더 색인하지 않고, 있던 색인은 그대로 둡니다)')
    return nil
  end
  if batch and batch.root == root then
    if exclude == nil then
      exclude = select(4, entries_of(root)) or {}
    end
    batch.pend = { name = name, entries = entries, exclude = exclude }
    if delta and batch.delta then
      vim.list_extend(batch.delta.drop, delta.drop or {})
      vim.list_extend(batch.delta.add, delta.add or {})
    else
      batch.delta = nil -- 모르는 변경이 섞였다: 끝에서 통째로 편다
    end
    if not delta then
      batch.rules = nil -- 무엇이 바뀌었는지 모른다: 다음에 새로 만든다
    end
    return nil -- 커밋은 배치 끝에서
  end
  -- 고치기 전의 기억이 디스크 그대로일 때만 바뀐 만큼 고친다
  local valid = cache_valid(root, name)
  if not preset_write(name, entries, exclude) then
    valid = false -- 디스크의 preset 은 그대로다: 통째로 펴서 그것을 따른다
  end
  -- 뺄 때만: 더할 때(담은 경로에 색인할 파일이 없을 때)는 예전처럼 알리고
  -- 목록을 그대로 둔다 - 더하다가 none 모드로 바뀌면 안 된다 (반대 심문)
  s.quiet_empty = s.removing
  local files, nm, changes = commit_list(root, valid and delta or nil)
  s.quiet_empty = nil
  if not files and nm and s.removing then
    -- 남은 항목이 이 체크아웃에서 하나도 펼쳐지지 않는다 (다른 체크아웃에만 있는
    -- 경로들). 목록이 빈 것과 같은 규칙으로 none 모드로 - preset 파일은 다른
    -- 체크아웃에서 쓰이므로 그대로 둔다. 예전에는 목록과 색인이 옛것 그대로
    -- 남아 \fo 에 계속 보였고 지우려 하면 '목록에 없습니다' 였다 (QA).
    none_for_empty(root, name)
    return nil
  end
  if not (opts and opts.no_reindex) then
    reindex(root, changes)
  end
  return files, changes
end

-- 항목은 그대로 두고 목록에만 더한다: 디렉터리 항목 안에 그새 생긴 파일을
-- + 했을 때, 이미 담은 디렉터리를 다시 + 했을 때 (preset 을 다시 쓸 일이 없다)
-- 돌려주는 것: 목록에 새로 든 파일 수, 빠진 파일 수 (디렉터리를 다시 훑으면
-- 그새 지워진 것이 빠진다. 배치 중이거나 통째로 다시 폈으면 nil)
local function list_add(root, abs, st)
  local a = { abs = abs, st = st }
  if batch and batch.root == root then
    if batch.delta then
      batch.delta.add[#batch.delta.add + 1] = a
    end
    batch.list_only = true
    return nil
  end
  local files, _, changes = commit_list(root,
    cache_valid(root, active_preset(root)) and { add = { a } } or nil)
  if not files then
    return 0, 0
  end
  if changes and #changes.added == 0 and #changes.removed == 0 then
    return 0, 0 -- 목록이 그대로다: 색인도 그대로
  end
  reindex(root, changes)
  if not changes then
    return nil
  end
  return #changes.added, #changes.removed
end

-- 지금 목록 (기억이 디스크 그대로면 그것, 아니면 읽는다). 둘째 값: 정렬을 믿어도 되나
local function listed_files(root)
  local c = s.cache[root]
  if c and c.files and c.list_key == stat_key(uv.fs_stat(list_path(root))) then
    return c.files, true
  end
  local ok, lines = pcall(vim.fn.readfile, list_path(root))
  return ok and lines or {}, false
end

-- 지금 목록에 rel 과 그 아래 파일이 몇 개 있나 (목록을 다시 펴지 않고).
-- 기억한 목록은 정렬돼 있어서 'rel/' 로 시작하는 줄은 한데 모여 있다 -
-- 반씩 나눠 찾는다 (범위의 50줄을 빼면 6,500줄을 50번 훑던 것).
local function count_listed(root, rel)
  local files, sorted = listed_files(root)
  local pre = rel .. '/'
  local n = 0
  if sorted then
    local i = lower_bound(files, rel)
    n = files[i] == rel and 1 or 0
    i = lower_bound(files, pre)
    while files[i] and files[i]:sub(1, #pre) == pre do
      n = n + 1
      i = i + 1
    end
    return n
  end
  for _, f in ipairs(files) do
    if f == rel or f:sub(1, #pre) == pre then
      n = n + 1
    end
  end
  return n
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

-- p 가 base 자신이거나 그 아래 ('.' 은 루트 항목이라 모두를 덮는다)
local function under_rel(p, base)
  return base == '.' or p == base or p:sub(1, #base + 1) == base .. '/'
end

-- 무언가 바뀌었으면 true
local function add_path(root, path)
  local entries, name, bad, exclude = entries_of(root)
  if bad then
    return false -- 읽을 수 없는 preset: 새 preset 을 시작해 버리면 더 나쁘다
  end
  local abs = abs_of(root, path)
  local st = uv.fs_stat(abs)
  if not st then
    -- check BEFORE switching modes: a typo must not turn the project into
    -- an empty preset (which would index nothing at all)
    bnotify('없는 경로: ' .. path, vim.log.levels.WARN)
    return false
  end
  -- 아래 두 거절도 모드를 바꾸기 전에 한다. 예전에는 auto/미설정 프로젝트를
  -- 빈 preset 으로 먼저 바꿔 놓고 거절해서, 담지도 못한 채 그 프로젝트가
  -- '아무것도 색인하지 않는' 상태가 됐다(반대 심문에서 나온 것).
  local rel = rel_to(root, abs)
  -- preset 은 '프로젝트 상대 경로 목록'이다. 그게 다른 체크아웃에서도 쓸 수
  -- 있게 만드는 유일한 이유이고, vim-ide 로 공유하는 근거이기도 하다.
  -- 이 프로젝트 밖의 경로는 상대 경로로 적을 수 없으니 절대 경로가 되어
  -- 버리는데, 그런 항목은 다른 기계에서 무의미하고 지우기도 어렵다
  -- (상대 경로로 :ProjectFilesRemove 해도 맞지 않는다). 담지 않는다.
  if rel:sub(1, 1) == '/' then
    bnotify(('이 프로젝트(%s) 밖의 경로는 담을 수 없습니다: %s'):format(
      vim.fn.fnamemodify(root, ':~'), rel), vim.log.levels.WARN)
    return false
  end
  -- 색인 데이터베이스 자리(.tags)와 find 가 늘 가지치기하는 디렉터리(.git,
  -- .repo ...)는 담아도 파일이 하나도 나오지 않는다. 빈 항목만 쌓인다.
  do
    local part = pruned_part(rel)
    if part then
      bnotify(("'%s' 안은 색인에서 늘 빠지는 자리라 담지 않습니다: %s"):format(
        part, rel), vim.log.levels.WARN)
      return false
    end
  end
  -- 하위 프로젝트 안의 경로라도, 직접 담으라고 한 것은 담는다. 다만 그
  -- 프로젝트가 자기 색인을 따로 갖고 있다는 사실은 알려 준다.
  local owner = nested_owner(root, rel, st.type == 'directory')
  if owner then
    if cfg('nested_presets', 0) ~= 0 then
      bnotify(("'%s' 는 자기 색인(.tags)을 가진 하위 프로젝트입니다 - "):format(owner)
        .. '거기서 담으세요', vim.log.levels.WARN)
      return false
    end
    bnotify(("참고: '%s' 는 자기 색인(.tags)을 가진 하위 프로젝트입니다"):format(owner))
  end
  if not name then
    -- auto mode: adding a path means "start a preset here"
    local was = mode_of(root)
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
    entries, exclude = {}, {}
    set_active(root, name)
    -- none 이나 미설정에서 시작해도 'auto ->' 라고 적던 것을 바로잡는다
    bnotify(("%s -> preset '%s'"):format(
      was == MODE_NONE and 'none' or (was == MODE_UNSET and '미설정' or 'auto'), name))
  end
  -- 이 경로와 그 아래에서 뺀 것(exclude)은 푼다 - 다시 담으라는 뜻이다
  local rules = rules_for(root, entries, exclude)
  local ex2, lifted = {}, {}
  for _, x in ipairs(exclude or {}) do
    if under_rel(x, rel) then
      lifted[#lifted + 1] = { abs = root .. '/' .. x, rel = x }
    else
      ex2[#ex2 + 1] = x
    end
  end
  -- 배치의 규칙을 바뀐 만큼 고친다 (rules_for)
  local function sync_rules(new_entry)
    for _, l in ipairs(lifted) do
      rules.exc[l.rel] = nil
    end
    if new_entry then
      rules.inc[rel] = true
    end
    rules.any_exc = next(rules.exc) ~= nil
  end
  local same = false
  for _, e in ipairs(entries) do
    if e.path == rel then
      same = true
      break
    end
  end
  -- 이미 항목이거나 다른 디렉터리 항목이 덮고 있으면 항목을 늘리지 않는다.
  -- 예전에는 덮인 파일도 파일 항목으로 하나 더 담았다 - '-' 로 디렉터리를
  -- 빼도 그 파일만 남는 군더더기였고, :ProjectFilesAdd 의 연관 파일이 그렇게
  -- 디렉터리 안의 파일을 몇 개씩 다시 담았다 (S10).
  local cover = not same and rule_above(rules, rel) == true
  if same or cover then
    -- 디렉터리면 그 아래를 한 번 다시 훑는다 (F8): 셸이나 빌드가 그새 만든
    -- 파일이 함께 든다. 예전에는 '이미 있습니다' 로 끝나서, 그런 파일은 \fR 이나
    -- 다음 시작까지 목록에 없었다 (+/- 는 바뀐 경로 아래만 본다).
    local isdir = st.type == 'directory'
    if #lifted > 0 then
      sync_rules(false)
      -- 뺐던 것은 다 이 경로 아래다: 디렉터리 하나를 찾으면 함께 들어온다
      save_entries(root, name, entries, ex2,
        { add = isdir and { { abs = abs, st = st } } or lifted })
      bnotify(('다시 넣음: %s (뺐던 %d곳을 풂)  →  %s'):format(rel, #lifted,
        target_label(root)), nil, true)
      return true
    end
    if isdir then
      local n, gone = list_add(root, abs, st)
      if batch then
        batch.same = (batch.same or 0) + 1 -- 새 파일은 커밋에서 목록에 든다
        return false
      end
      -- 더한 것과 뺀 것을 따로 센다 (N3): 지워진 것만 빠졌는데 '새 파일 없음'
      -- 이라고 하면 디렉터리가 목록과 맞는 것처럼 들린다
      local parts = {}
      if n and n > 0 then
        parts[#parts + 1] = ('새 파일 %d개'):format(n)
      end
      if gone and gone > 0 then
        parts[#parts + 1] = ('사라진 파일 %d개'):format(gone)
      end
      local fmt = '다시 훑음: %s  →  %s'
      if #parts > 0 then
        fmt = '다시 훑음: %s (' .. table.concat(parts, ', ') .. ')  →  %s'
      elseif n == 0 then
        fmt = '이미 있습니다: %s (다시 훑음, 새 파일 없음)  →  %s'
      end
      bnotify(fmt:format(rel, target_label(root)), nil, true)
      return n ~= 0 or #parts > 0
    end
    -- 디렉터리 항목 안에 그새 만든 파일: 항목은 그대로, 목록에만 넣는다
    if cover and st.type == 'file' and count_listed(root, rel) == 0 then
      if not indexed(abs, st, { big = 0, binary = 0 }) then
        bnotify('색인 규칙에서 빠지는 파일입니다 (바이너리·크기·확장자): ' .. rel,
          vim.log.levels.WARN)
        return false
      end
      list_add(root, abs, st)
      bnotify('추가: ' .. rel .. '  →  ' .. target_label(root), nil, true)
      return true
    end
    -- 배치에서는 '추가'로 세지 않는다. 예전에는 완료로 세어서, 이미 있던
    -- 파일까지 '추가 27개 (항목 2 -> 27)' 처럼 보고했다.
    if batch then
      batch.same = (batch.same or 0) + 1
    else
      bnotify('이미 있습니다: ' .. rel .. '  →  ' .. target_label(root), nil, true)
    end
    return false
  end
  entries[#entries + 1] = { path = rel, kind = st.type == 'directory' and 'dir' or 'file' }
  sync_rules(true)
  -- 뺐던 것은 이 경로 아래이므로 이 경로 하나를 다시 찾으면 함께 들어온다
  save_entries(root, name, entries, ex2, { add = { { abs = abs, st = st } } })
  bnotify('추가: ' .. rel .. '  →  ' .. target_label(root), nil, true)
  return true
end

-- 한 번의 제거가 목록의 상당 부분을 지우려 하면 되묻는다.
--
-- 'arch/arm64/boot/dts/telechips' 디렉터리 노드에서 '-' 한 번이 항목 487개를
-- 조용히 지웠다. 규칙 자체는 의도된 것이지만(디렉터리를 빼면 그 아래도
-- 빠진다), 그 규모를 말해 주지 않는 것은 의도가 아니었다.
--   let g:projectfiles_confirm_drop = 0    " 되묻지 않기
--   let g:projectfiles_confirm_drop = 100  " 100개 이상일 때만
--
-- 알림은 둘을 따로 말한다 (F9): 목록(.tags/files)에서 빠지는 파일, preset 에서
-- 지워지는 항목. 예전에는 둘을 더해 '항목' 이라 부르고 전체는 항목 수로 적어서
-- '항목 50개가 빠집니다 (전체 9개)' 가 나왔다 - 디렉터리 항목 안의 디렉터리를
-- 빼면 지워지는 항목은 0개이고 빠지는 것은 파일 50개다.
--
-- 묻는 때는 예전 그대로다: 지워지는 항목 수 + 남는 디렉터리 항목에서 빼는(exclude)
-- 파일 수(nexcl)가 한도에 닿을 때. 디렉터리 항목 하나를 통째로 빼는 것은 항목
-- 1개라 묻지 않는다 - 트리에서 +/- 로 늘 하는 일이다. 빠지는 파일 수로 물으면
-- 파일 30개짜리 디렉터리 항목을 뺄 때마다 새로 물음이 떴다 (병합 점검). 항목
-- 수는 이 체크아웃에 없는 경로도 센다 - 파일로는 세어지지 않지만 다른 체크
-- 아웃에서 쓰는 preset 에서는 사라진다.
-- 단 루트 항목('.')은 빠지는 파일 수로 묻는다: 항목 하나지만 프로젝트 전체라,
-- 마지막 항목이면 preset 이 지워지고 none 이 된다 (병합 점검: 1704개가 묻지
-- 않고 빠졌다).
local function confirm_drop(root, rel, nfiles, nent, total_ent, nexcl)
  local limit = tonumber(cfg('confirm_drop', 20)) or 20
  local n = nent + (nexcl or 0)
  if rel == '.' then
    n = math.max(n, nfiles)
  end
  if limit <= 0 or n < limit then
    return true
  end
  local msg = ("'%s' 를 빼면 목록에서 파일 %d개가 빠집니다 (목록 %d개 중; preset 항목은 %d개 중 %d개). ")
    :format(rel, nfiles, #listed_files(root), total_ent, nent) .. target_label(root)
  -- 배치(비주얼 범위)는 끝에서 합계를 보고하고, 줄마다 물으면 쓸 수 없다.
  local uis = pcall(api.nvim_list_uis) and #api.nvim_list_uis() or 0
  if batch or uis == 0 then
    notify(msg, vim.log.levels.WARN)
    return true
  end
  local ans = 0
  pcall(function()
    -- 단축글자는 ASCII 로. '&예/&아니오' 는 nvim 0.12 의 confirm() 이 여러 바이트
    -- 글자를 단축키로 맞추지 못해 '예'를 고를 방법이 없었다 - 늘 취소됐다 (QA).
    ans = vim.fn.confirm(msg .. '\n계속할까요?', "&y 예\n&n 아니오", 2, 'Question')
  end)
  -- 여러 줄짜리 물음이 지나간 자리에 바로 알림을 쓰면 Press ENTER 가 뜬다
  pcall(vim.cmd, 'redraw')
  return ans == 1
end

-- 무언가 바뀌었으면 true
local function remove_path(root, path)
  local entries, name, bad, exclude = entries_of(root)
  if bad then
    return false
  end
  if not name then
    local m = mode_of(root)
    bnotify(m == MODE_NONE and '색인하지 않는(none) 모드라 뺄 목록이 없습니다'
      or (m == MODE_UNSET and '아직 색인 모드를 정하지 않아 뺄 목록이 없습니다'
        or 'auto 모드(프로젝트 전체)에서는 뺄 목록이 없습니다'), vim.log.levels.WARN)
    return false
  end
  local abs = abs_of(root, path)
  local rel = rel_to(root, abs)
  local kept, dropped, gone = {}, 0, {}
  for _, e in ipairs(entries) do
    -- removing a directory drops the files under it too
    if e.path == rel or e.path:sub(1, #rel + 1) == rel .. '/' then
      dropped = dropped + 1
      gone[#gone + 1] = norm_rel(e.path)
    else
      kept[#kept + 1] = e
    end
  end
  local rules = rules_for(root, entries, exclude)
  -- 이미 빠진 경로(어느 항목 아래도 아니거나, 뺀 것 아래)에 다시 '-' 를 누르면
  -- 아무것도 하지 않는다. 그 자리를 '제거' 로 답하면 이미 빠진 것이 또 빠진 것처럼 보인다.
  if dropped == 0 and rule_of(rules, rel) ~= true then
    bnotify('목록에 없습니다: ' .. rel, vim.log.levels.WARN)
    return false
  end
  -- 이 경로 아래에서 뺀 것은 이 경로가 대신한다. 루트 항목('.')은 예외다 -
  -- 그것을 빼도 그 아래의 다른 항목은 남으므로 그 항목들의 제외도 남는다
  -- (덮는 항목이 없어진 제외는 preset_write 가 버린다).
  local ex2, unex = {}, {}
  for _, x in ipairs(exclude or {}) do
    if rel == '.' or not under_rel(x, rel) then
      ex2[#ex2 + 1] = x
    else
      unex[#unex + 1] = x
    end
  end
  -- 목록에서 빠지는 파일 수 (confirm_drop 의 알림). rel 아래가 전부 빠진다 - 다만
  -- 루트 항목('.')을 빼면 남은 항목이 덮는 것은 남는다.
  local nfiles = 0
  if rel ~= '.' then
    nfiles = count_listed(root, rel)
  elseif dropped > 0 then
    local left = make_rules(kept, ex2)
    for _, f in ipairs((listed_files(root))) do
      if rule_of(left, f) ~= true then
        nfiles = nfiles + 1
      end
    end
  end
  -- 남은 디렉터리 항목이 이 경로를 덮고 있으면(그 위 디렉터리를 담아 두었으면)
  -- 이 경로를 '뺀 것'(exclude)으로 적는다.
  --
  -- 예전에는 그 디렉터리 항목을 남은 파일들로 풀어 썼다 (P5/T6/S3). 6,000개
  -- 헤더를 담은 include/ 에서 파일 하나를 빼면 preset 이 3항목에서 6,001항목
  -- (350KB)이 됐고, 그 뒤 모든 +/- 가 세 배로 느려졌다. 더 나쁜 것은 디렉터리
  -- 항목이 사라져서, 그 디렉터리에 새로 만든 파일이 저장해도 목록에 들어가지
  -- 않았다는 것이다. 이제 디렉터리 항목은 그대로 남는다.
  -- 몇 개가 빠지는지는 지금 목록에서 센다 - 다시 펴지(find) 않는다.
  -- (rel 자신과 그 아래만 바뀌므로, 덮는지는 지금 규칙으로 rel 의 위를 보면 된다)
  local excluded = 0
  if rel ~= '.' and rule_above(rules, rel) == true then
    excluded = nfiles
    if excluded == 0 then
      -- 목록에는 아직 없지만 다시 펴면 들어올 파일(그새 만든 파일)도 뺀다
      local st = uv.fs_stat(abs)
      if st and st.type == 'file' and not pruned_part(rel)
          and indexed(abs, st, { big = 0, binary = 0 }) then
        excluded = 1
      end
    end
    if excluded > 0 then
      ex2[#ex2 + 1] = rel
    end
  end
  if dropped == 0 and excluded == 0 then
    bnotify('목록에 없습니다: ' .. rel, vim.log.levels.WARN)
    return false
  end
  -- 몇 개가 빠지는지 말한다. 디렉터리에 '-' 를 한 번 누르면 그 아래가 전부
  -- 빠지는데, 예전에는 '제거: <경로>' 한 줄만 나와서 487개가 사라진 것을
  -- 화면에서 알 수 없었다.
  if not confirm_drop(root, rel, nfiles, dropped, #entries, excluded) then
    bnotify('제거를 취소했습니다: ' .. rel, vim.log.levels.WARN)
    return false
  end
  -- 배치의 규칙을 바뀐 만큼 고친다 (rules_for)
  for _, p in ipairs(gone) do
    rules.inc[p] = nil
  end
  for _, x in ipairs(unex) do
    rules.exc[x] = nil
  end
  if excluded > 0 then
    rules.exc[rel] = true
  end
  rules.any_exc = next(rules.exc) ~= nil
  -- 빼다가 남은 항목이 이 체크아웃에서 하나도 안 펼쳐지면 none 모드로 (save_entries)
  s.removing = true
  local okS, errS = pcall(save_entries, root, name, kept, ex2, { drop = { rel } })
  s.removing = nil
  if not okS then
    error(errS)
  end
  local parts = {}
  if dropped > 0 then
    parts[#parts + 1] = ('항목 %d개'):format(dropped)
  end
  if excluded > 0 then
    parts[#parts + 1] = ('디렉터리 항목에서 파일 %d개 제외'):format(excluded)
  end
  bnotify(('제거: %s (%s)  →  %s'):format(rel, table.concat(parts, ', '),
    target_label(root)), nil, true)
  return true
end

-- 여러 경로를 한 번의 커밋으로 처리한다. fn 안에서는 add_path/remove_path 를
-- 몇 번이든 불러도 되고, preset 쓰기·목록 고치기·재색인은 여기서 한 번만
-- 일어난다. opts.head(b, before, after) 는 요약 줄을 바꿔 쓴다.
local function in_batch(root, what, fn, opts)
  if batch then
    fn() -- 중첩: 바깥 배치가 커밋한다
    return
  end
  if not s.collect then
    return one_line(in_batch, root, what, fn, opts) -- 요약과 함께 한 줄로
  end
  local before = #(entries_of(root) or {})
  local name0 = active_preset(root)
  -- 시작할 때의 기억이 디스크 그대로여야 끝에서 모은 만큼만 고칠 수 있다
  local valid = cache_valid(root, name0)
  batch = { root = root, msgs = {}, done = 0, delta = { add = {}, drop = {} } }
  local ok, err = pcall(fn)
  local b = batch
  batch = nil

  if b.pend then
    -- 모은 항목을 한 번에 쓴다 (preset 쓰기와 백업이 한 번)
    if b.pend.name ~= name0 then
      valid = false -- auto/none 에서 preset 을 새로 시작했다
    end
    if not preset_write(b.pend.name, b.pend.entries, b.pend.exclude) then
      valid = false
    end
    -- 이 배치가 실제로 뺀 것이 있을 때만 none 모드로 (아무것도 안 바뀐 배치가
    -- 모드를 바꾸면 안 된다 - 반대 심문). 더하는 배치는 예전 그대로.
    local removing = what == '제거' and (b.done or 0) > 0
    s.quiet_empty = removing
    local files, nm, changes = commit_list(root, valid and b.delta or nil)
    s.quiet_empty = nil
    if not files and nm and removing then
      none_for_empty(root, nm) -- 남은 항목이 이 체크아웃에 하나도 없다
    else
      reindex(root, changes)
    end
  elseif b.emptied then
    -- 배치로 마지막 항목까지 빠졌다: 단일 경로와 같은 규칙으로 none 모드
    save_entries(root, b.emptied, {})
  elseif b.list_only then
    -- 항목은 그대로, 목록에만 더했다 (디렉터리 항목 안의 새 파일, 다시 훑은
    -- 디렉터리). 새로 든 것이 없으면 색인도 그대로 둔다.
    local files, _, changes = commit_list(root, valid and b.delta or nil)
    if files and not (changes and #changes.added == 0 and #changes.removed == 0) then
      reindex(root, changes)
    end
  end
  -- 아무것도 바뀌지 않은 배치는 목록도 색인도 건드리지 않는다

  -- 알림은 한 줄로. 경고는 몇 개만 보여 주고 나머지는 수만 알린다.
  local warns = {}
  for _, m in ipairs(b.msgs) do
    if m.level == vim.log.levels.WARN then
      warns[#warns + 1] = m.msg
    end
  end
  local after = #(entries_of(root) or {})
  local head = opts and opts.head and opts.head(b, before, after)
      or ('%s %d개%s (항목 %d -> %d)  →  %s'):format(what, b.done,
        (b.same or 0) > 0 and (', 이미 있음 %d개'):format(b.same) or '',
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
    -- 고르는 창(inputlist)이 남긴 줄 위에 알림을 쓰면 Press ENTER 가 뜨고, 그
    -- 동안 색인이 멈춘다 (실측 4초 - 누를 때까지). 한 번 지우고 쓴다.
    pcall(vim.cmd, 'redraw')
    if not choice or choice.name == SKIP then
      notify('색인을 건너뜁니다 (:ProjectFilesMode 로 다시 고를 수 있습니다)')
      cb(false)
      return
    end
    if choice.name == NEW_PRESET then
      vim.ui.input({ prompt = '새 preset 이름: ' }, function(nm)
        pcall(vim.cmd, 'redraw') -- 입력 줄 위에 쓰면 Press ENTER (위와 같다)
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

-- 대상 프로젝트가 지금 보고 있는 프로젝트와 다르면 그렇다고 말한다.
--
-- 경로는 스스로 어느 프로젝트에 속하는지 정한다(그래야 트리 창에서도 맞는
-- 곳에 담긴다). 그 대신 '내가 보던 곳이 아닌 다른 프로젝트에 들어갔다'는
-- 사실이 조용히 지나가면 안 된다 - 상위 트리에서 저장한 preset 이 하위
-- 트리의 경로로 가득 찬 것을 아무도 눈치채지 못한 것이 그래서였다.
--
-- 같은 프로젝트면 말하지 않는다: 결과 줄('추가: x  →  <루트>/.tags [preset]')
-- 이 이미 어디에 썼는지 말한다. 예전에는 '색인 대상: …' 을 따로 한 줄 더
-- 냈고, Ex 명령 안에서 그 두 줄이 쌓여 Press ENTER 가 떴다 (B2). 다를 때의
-- 한 마디도 같은 줄에 붙는다 (one_line).
local function announce_root(root)
  if not root then
    return
  end
  local ok, cur = pcall(cur_root)
  if ok and cur and root ~= cur then
    notify(('(보고 있던 곳: %s)'):format(vim.fn.fnamemodify(cur, ':~')))
  end
end

-- 여러 경로를 프로젝트별로 묶어 프로젝트마다 한 번씩 커밋한다 (C2).
--
-- 범위의 첫 경로가 프로젝트를 정하던 예전에는 다른 프로젝트의 경로가 '이
-- 프로젝트 밖' 경고와 함께 버려졌다. 경로마다 root_of 는 위로 올라가며
-- stat 하므로 디렉터리 단위로 기억한다.
--
-- 트리 루트 자체는 범위(경로 둘 이상)일 때만 건너뛴다. 범위를 크게 잡으면
-- 루트 줄이 함께 들어오는데, 그걸 담으면 preset 이 프로젝트 전체가 되어 고른
-- 범위와 무관해진다. 루트 줄에서 + 를 한 번 누른 것은 '루트를 담아라'다
-- (README) - 예전에는 한 줄도 범위처럼 걸러서 '범위에 루트만 있었습니다'
-- 라며 아무것도 안 했다 (QA).
local function apply_many(arg, what, one)
  local all = tree_paths(arg)
  local ranged = type(arg) == 'table' and #all > 1
  local by_dir, groups, order, dropped = {}, {}, {}, 0
  for _, p in ipairs(all) do
    -- root_of 와 같은 출발점으로 묶는다 (디렉터리는 ':p' 가 '/' 를 붙여 자기
    -- 자신에서 출발한다 - 자기 .tags 를 가진 하위 디렉터리가 그렇다)
    local dir = vim.fs.dirname(vim.fn.fnamemodify(p, ':p'))
    local r = by_dir[dir]
    if r == nil then
      r = tree_root(p) or false
      by_dir[dir] = r
    end
    if ranged and p == r then
      dropped = dropped + 1
    elseif r then
      if not groups[r] then
        groups[r] = {}
        order[#order + 1] = r
      end
      table.insert(groups[r], p)
    end
  end
  if #order == 0 then
    if dropped > 0 then
      notify('트리 루트는 건너뜁니다 (범위에 루트만 있었습니다)',
        vim.log.levels.WARN)
    end
    return false
  end
  one_line(function()
    for _, root in ipairs(order) do
      local paths = groups[root]
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
    end
    if dropped > 0 then
      notify('트리 루트 ' .. dropped .. '줄은 건너뜀')
    end
  end)
  return true
end

function _G.projectfiles_add(arg)
  return apply_many(arg, '추가', add_path)
end

function _G.projectfiles_remove(arg)
  return apply_many(arg, '제거', remove_path)
end

-- 절대 경로 여러 개(프로젝트가 섞여도 된다)를 한 번에. 프로젝트마다 preset
-- 쓰기 한 번, 목록 고치기 한 번, 재색인 한 번 (C2). 트리의 범위 선택과
-- telescope/quickfix 의 여러 줄 선택이 이것을 쓴다.
function _G.projectfiles_add_many(paths)
  return apply_many(paths, '추가', add_path)
end

function _G.projectfiles_remove_many(paths)
  return apply_many(paths, '제거', remove_path)
end

-- 트리에서 이름을 바꾸거나 옮긴 경로(neo-tree 의 r / m / x,p)를 색인 목록이
-- 따라간다. projectfiles_neotree.lua 가 neo-tree 의 FILE_RENAMED / FILE_MOVED
-- 에서 부른다.
--
-- preset 항목은 프로젝트 기준 경로라, 예전에는 이름을 바꾸면 항목이 없는
-- 경로를 가리킨 채 남았다 (QA). 바뀐 이름에는 표시가 없고 '=' 도 '제외',
-- .tags/files 와 색인은 옛 이름 그대로였다. 다음 재색인에서 그 아래 파일이
-- 말없이 빠졌고, 항목이 전부 낡으면 '다른 체크아웃의 preset' 이라는 엉뚱한
-- 경고가 떴다. 이제는
--   * 그 경로와 그 아래 항목을 새 이름으로 고쳐 쓴다
--   * 담아 둔 디렉터리에서 담지 않은 곳으로 꺼낸 것은 새 자리를 담는다
--   * 프로젝트 밖으로 나간 것은 뺀 것과 같다 (none 모드로 가는 규칙도 같다)
--   * 항목은 그대로인데 목록만 낡은 경우(담아 둔 디렉터리 안에서 옮김, 그
--     안으로 들여옴)는 목록과 색인만 다시 만든다. preset 은 쓰지 않는다 -
--     쓰면 고친 것도 없이 vim-ide 공용 preset 이 이 장비 사본으로 갈라진다
-- 색인과 무관한 경로면 아무것도 하지 않는다. 고친 항목 수를 돌려준다.
local function rename_path(src_abs, dst_abs)
  -- 옛 경로는 이미 없으므로 부모로 실제 경로를 맞춘다 (/tmp 와 /private/tmp).
  -- 끝까지 풀면 심볼릭 링크의 이름을 바꿨을 때 링크 대상으로 읽힌다.
  local function real(p)
    p = tostring(p or ''):gsub('/+$', '')
    local d = p ~= '' and uv.fs_realpath(vim.fs.dirname(p))
    return d and (d .. '/' .. vim.fs.basename(p)) or p
  end
  src_abs, dst_abs = real(src_abs), real(dst_abs)
  if src_abs == '' or dst_abs == '' or src_abs == dst_abs then
    return 0
  end
  local root = root_of(src_abs)
  local entries, name, bad, exclude = entries_of(root)
  if bad or not name or #entries == 0 then
    return 0 -- auto / none / 미설정 / 읽을 수 없는 preset: 고칠 목록이 없다
  end
  local src, dst = rel_to(root, src_abs), rel_to(root, dst_abs)
  if src == '.' or src:sub(1, 1) == '/' then
    return 0
  end
  local outside = dst == '.' or dst:sub(1, 1) == '/'
  -- p 가 base 자신이거나 그 아래 ('.' 은 루트 항목이라 모두를 덮는다)
  local function under(p, base)
    return base == '.' or p == base or p:sub(1, #base + 1) == base .. '/'
  end
  local out, moved, cover_dst = {}, 0, false
  for _, e in ipairs(entries) do
    local p = norm_rel(e.path)
    if under(p, src) then
      moved = moved + 1
      if not outside then
        out[#out + 1] = { path = dst .. p:sub(#src + 1), kind = e.kind }
      end
    else
      out[#out + 1] = e
      cover_dst = cover_dst or (not outside and under(dst, p))
    end
  end
  -- 옮기기 전에 색인에 들어 있던 곳인가: 항목만이 아니라 뺀 것(exclude)까지 본다
  -- (F3). 항목만 보면 '-' 로 뺀 drivers/net/net_040.c 도 'drivers/net 이 덮는
  -- 곳'으로 읽혀서, 밖으로 꺼내면 아래의 '담아 둔 디렉터리에서 꺼냈다'가 새
  -- 자리를 파일 항목으로 담았다 - 뺀 파일이 옮기기만 하면 색인에 다시 들어왔다.
  local cover_src = rule_of(make_rules(entries, exclude), src) == true
  -- 디렉터리 항목 아래에서 뺀 것(exclude)도 따라간다 - 이름을 바꾼 뒤에도
  -- 빠진 채여야 한다. 프로젝트 밖으로 나갔으면 지운다.
  local xout, xmoved = {}, 0
  for _, x in ipairs(exclude or {}) do
    if under(x, src) then
      xmoved = xmoved + 1
      if not outside then
        xout[#xout + 1] = dst .. x:sub(#src + 1)
      end
    else
      xout[#xout + 1] = x
    end
  end
  if moved == 0 and xmoved == 0 and not cover_src and not cover_dst then
    return 0 -- 색인과 무관한 경로
  end
  local added = 0
  if moved == 0 and cover_src and not outside and not cover_dst then
    local st = uv.fs_stat(dst_abs)
    out[#out + 1] = { path = dst, kind = (st and st.type == 'directory') and 'dir' or 'file' }
    added = 1
  end
  local removing = outside and (moved > 0 or cover_src)
  if moved + added + xmoved > 0 then
    s.removing = removing or nil
    local ok, err = pcall(save_entries, root, name, out, xout)
    s.removing = nil
    if not ok then
      error(err)
    end
  else
    s.quiet_empty = removing
    local files, nm = materialize(root)
    s.quiet_empty = nil
    if not files and nm and removing then
      none_for_empty(root, nm)
    else
      reindex(root)
    end
  end
  if removing then
    notify(('프로젝트 밖으로 나가 색인에서 뺐습니다: %s%s  →  %s'):format(src,
      moved > 0 and (' (항목 %d개)'):format(moved) or '', target_label(root)),
      vim.log.levels.WARN)
  elseif moved + added > 0 then
    notify(('색인 항목이 따라갔습니다: %s → %s%s  →  %s'):format(src, dst,
      moved > 1 and (' (항목 %d개)'):format(moved) or '', target_label(root)))
  end
  return moved + added
end

function _G.projectfiles_renamed(src, dst)
  local ok, n = pcall(one_line, rename_path, src, dst)
  if not ok then
    notify('색인 목록을 고치지 못했습니다: ' .. tostring(n), vim.log.levels.ERROR)
    return 0
  end
  return n
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
  s.real_cache = nil
  -- 표시를 가진 곳들(quickfix/위치 목록, RelationView 패널, neo-tree)에
  -- 알린다. 예전에는 키를 누른 그 창만 다시 칠해서, 다른 곳에서 목록을
  -- 바꾸면(quickfix 에서 + 하고 트리를 보면, :ProjectFilesAdd 뒤 목록을
  -- 보면) 표시가 낡은 채 남았다. 한 번의 변경에 여러 번 불려도 한 틱에
  -- 한 번만 쏜다.
  if not s.changed_pending then
    s.changed_pending = true
    vim.schedule(function()
      s.changed_pending = false
      pcall(api.nvim_exec_autocmds, 'User',
        { pattern = 'ProjectFilesChanged', modeline = false })
    end)
  end
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
  -- 추가/제거/상태(=)는 abs_of 로 심볼릭 링크를 풀어 실제 경로로 다룬다. 표시도
  -- 같은 경로로 판정해야 링크 줄의 점이 = 과 어긋나지 않는다(예전에는 링크를
  -- 담으면 대상 파일이 들어가고, 누른 링크 줄에는 점이 끝내 붙지 않았다).
  -- 풀린 경로가 이 프로젝트 안일 때만 쓴다 - 밖이면 담을 수 없으니 점도 없다.
  s.real_cache = s.real_cache or {}
  local rp = s.real_cache[path]
  if rp == nil then
    rp = uv.fs_realpath(path) or path
    s.real_cache[path] = rp
  end
  if rp ~= path and rp:sub(1, #root + 1) == root .. '/' then
    path = rp
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
  -- '=' 한 번에 preset JSON 을 통째로 풀고(이름만 쓰려고) 목록 파일을 처음부터
  -- 읽어 훑었다 (S14). 이름은 모드 파일에서, 포함 여부는 트리 표시가 쓰는 것과
  -- 같은 집합(flag_data, 목록 파일의 stat 으로 기억)에서 - 표시와 답이 어긋나지
  -- 않는다.
  local m = mode_of(root)
  local name = active_preset(root)
  local rel = rel_to(root, abs_of(root, path))
  local c = flag_data(root)
  local inlist
  if c.preset then
    inlist = c.files[rel] or c.dirs[rel] or false
  else
    -- 목록 파일이 없다: auto 는 전체가 대상이고, none/미설정은 아무것도 아니다
    inlist = m == MODE_AUTO
  end
  return ("%s  |  모드: %s  |  색인: %s"):format(rel,
    name and ("preset '" .. name .. "'")
    or (m == MODE_NONE and 'none' or (m == MODE_UNSET and '미설정' or 'auto')),
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
      -- 모드를 정하지 않은(none 포함) 프로젝트는 훑지도 않는다. absorb_hint 가
      -- 어차피 그런 곳에서는 아무것도 하지 않는데, 그 앞에서 depth 7 의 find 가
      -- 배경에서 돌고 '<root>/.tags' 를 만들었다 - $HOME 에서 띄워도 홈 전체를
      -- 걸었다 (P7).
      if not mode_indexes(root) then
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

-- 여러 global 질의를 셸 하나로 묻는다 (질의마다 줄 목록을 돌려준다).
--
-- 예전에는 질의마다 vim.system 으로 nvim 을 fork 해 기다렸다 - :ProjectFilesAdd
-- 파일 하나에 '#include' 마다 'global -P', 쓰는 심볼마다 'global -d' 로
-- 20~60번, 그동안 화면이 멎었다 (S10). 'global -d' 를 '^(a|b)$' 하나로 묶지
-- 않는 것은, 앞이 고정되지 않은 정규식은 커널 크기 GTAGS 를 통째로 훑기 때문이다.
--   qs: { {'-P', 경로 패턴} | {'-d', 심볼} ... }
local function global_many(root, qs)
  local out = {}
  for i = 1, #qs do
    out[i] = {}
  end
  local g = global_cmd()
  if not g or #qs == 0 then
    return out
  end
  local argv = { 'sh', '-c', 'g=$1; shift; while [ $# -gt 1 ]; do '
    .. 'if [ "$1" = P ]; then "$g" -P "$2"; else "$g" --result=ctags-mod -d "$2"; fi; '
    .. 'echo @@pf@@; shift 2; done', 'sh', g }
  for _, q in ipairs(qs) do
    argv[#argv + 1] = q[1] == '-P' and 'P' or 'D'
    argv[#argv + 1] = q[2]
  end
  local ok, o = pcall(function()
    return vim.system(argv, { text = true, cwd = root,
      env = { GTAGSOBJDIR = dbdir() } }):wait(math.min(20000, 4000 + 200 * #qs))
  end)
  if not ok or not o or not o.stdout then
    return out
  end
  local i = 1
  for l in o.stdout:gmatch('[^\n]+') do
    if l == '@@pf@@' then
      i = i + 1
    elseif out[i] then
      table.insert(out[i], l)
    end
  end
  return out
end

-- everything `abs` needs, as project-relative paths: the headers it
-- includes (next to it, then through the index) and the files defining the
-- symbols it uses (through the index)
--
-- use_global = false 면 색인에 묻지 않는다: preset 모드에서는 색인이 곧
-- 목록이라 global 이 답할 수 있는 파일은 이미 목록에 있다 (옆 디렉터리의
-- '#include "x.h"' 는 그대로 본다 - stat 하나다).
local function related_of(root, abs, use_global)
  if cfg('expand', 1) == 0 then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, abs, '', 3000)
  if not ok then
    return {}
  end
  local dir = vim.fs.dirname(abs)
  local order, qs = {}, {} -- order: { p = 절대 경로 } 또는 { q = 질의 번호 }
  for _, l in ipairs(lines) do
    local inc = l:match('^%s*#%s*include%s*"([^"]+)"')
        or l:match('^%s*#%s*include%s*<([^>]+)>')
    if inc then
      local cand = dir .. '/' .. inc
      if uv.fs_stat(cand) then
        order[#order + 1] = { p = cand }
      elseif use_global then
        -- ask the index where that header is: '-P' matches whole paths
        qs[#qs + 1] = { '-P', '/' .. inc:gsub('([%.%+%-%*%?%[%]%^%$%(%)%%])', '\\%1') .. '$' }
        order[#order + 1] = { q = #qs }
      end
    end
  end
  local nsym0 = #qs
  if use_global then
    -- files defining the symbols this one uses
    local max = tonumber(cfg('expand_max', 40)) or 40
    local seen, n = {}, 0
    for _, l in ipairs(lines) do
      if not l:match('^%s*#') then
        for w in l:gmatch('[A-Za-z_][A-Za-z0-9_]*') do
          if not KEYWORD[w] and #w > 2 and not seen[w] and n < max then
            seen[w] = true
            n = n + 1
            qs[#qs + 1] = { '-d', w }
          end
        end
      end
    end
  end
  local res = global_many(root, qs)
  local cands = {}
  for _, o in ipairs(order) do
    if o.p then
      cands[#cands + 1] = o.p
    else
      for _, hit in ipairs(res[o.q] or {}) do
        local p2 = hit:sub(1, 1) == '/' and hit or (root .. '/' .. hit)
        if uv.fs_stat(p2) then
          cands[#cands + 1] = p2
          break
        end
      end
    end
  end
  local self_rel = rel_to(root, abs)
  local added = {}
  for i = nsym0 + 1, #qs do
    for _, hit in ipairs(res[i] or {}) do
      local path = hit:match('^([^\t]+)')
      if path then
        local rel = path:sub(1, 1) == '/' and rel_to(root, path) or path
        if rel ~= self_rel and not added[rel] and uv.fs_stat(root .. '/' .. rel) then
          added[rel] = true
          cands[#cands + 1] = root .. '/' .. rel
        end
      end
    end
  end
  local out, seen = {}, {}
  for _, p in ipairs(cands) do
    local rel = rel_to(root, p)
    if indexed(p) and rel:sub(1, 1) ~= '/' and not seen[rel] then
      seen[rel] = true
      out[#out + 1] = rel
    end
  end
  return out
end

-- 지금 목록에 든 파일들 (집합). 기억이 디스크 그대로면 그것을, 아니면 읽는다.
local function listed_set(root)
  local set = {}
  for _, f in ipairs((listed_files(root))) do
    set[f] = true
  end
  return set
end

-- ---------------------------------------------------------------------------
-- adding, with what the file needs
-- ---------------------------------------------------------------------------
-- 연관 파일을 먼저 구하고 본 파일과 함께 한 번에 담는다 (S10). 예전에는 본
-- 파일을 담아 저장·목록 펴기·재색인을 한 번 하고, 연관 파일로 또 한 번 했다 -
-- auto 모드에서 처음 담을 때는 첫 저장이 6,560개짜리 색인을 1개로 줄였다가
-- 다시 늘려서 '자리 되찾기' 전체 빌드까지 불렀다.
local function add_with_related(root, path)
  local abs = abs_of(root, path)
  local st = uv.fs_stat(abs)
  if not (st and st.type == 'file') or cfg('expand', 1) == 0 then
    return add_path(root, path) -- 디렉터리는 제 아래를 데려온다 / 없는 경로는 add_path 가 알린다
  end
  local main = rel_to(root, abs)
  -- 이미 목록에 있는 것(디렉터리 항목 안의 파일 포함)은 다시 담지 않는다.
  -- 예전에는 항목 경로만 보고 골라서, 디렉터리 항목이 이미 덮는 파일을 파일
  -- 항목으로 또 담았고 그것이 두 번째 저장을 불렀다.
  local have = listed_set(root)
  for _, e in ipairs(entries_of(root) or {}) do
    have[e.path] = true
  end
  if have[main] then
    return add_path(root, path) -- '이미 있습니다' (또는 뺐던 것을 다시 넣음)
  end
  local extra = {}
  for _, r in ipairs(related_of(root, abs, active_preset(root) == nil)) do
    if not have[r] and r ~= main then
      have[r] = true
      extra[#extra + 1] = r
    end
  end
  if #extra == 0 then
    return add_path(root, path)
  end
  in_batch(root, '추가', function()
    if not add_path(root, path) then
      return -- 본 파일을 담지 못했으면 연관 파일도 담지 않는다
    end
    for _, r in ipairs(extra) do
      add_path(root, root .. '/' .. r)
    end
  end, {
    head = function(b, before, after)
      if b.done == 0 then
        return nil
      end
      return ('추가: %s (+연관 파일 %d개, 항목 %d -> %d)  →  %s'):format(main,
        b.done - 1, before, after, target_label(root))
    end,
  })
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

-- autoindex 가 이 파일들(절대 경로)을 색인에 넣었다고 알리면 cb() 를 한 번 부른다.
--
-- 색인은 autoindex 한 곳이 한다 (K1). 위의 자체 큐는 autoindex 의 락도, 도는
-- 중인 gtags -i 도 몰랐다. 저장한 새 파일을 그 큐가 넣는 사이 autoindex 의
-- gtags -i 가 (그 파일이 없는 예전 목록으로) 끝나며 도로 지웠고, 표지
-- (refresh.pending)도 없어 아무도 다시 하지 않았다 (F1/INT1). 이제 그 큐는
-- autoindex 가 없을 때만 쓴다.
--   single        넣은 파일을 paths 로 준다 - 다 왔으면 끝
--   update/build  목록 전체를 다시 넣었다 - 그 안에 들었는지는 sym 의 정의를
--                 물어 본다 (먼저 돌던 갱신의 끝일 수 있다: 그건 예전 목록이다)
-- 다른 nvim 의 전체 빌드 뒤에 줄을 서면 몇 분이 걸린다. 부른 쪽(점프 다시
-- 하기, sihlindex 의 '찾는 중')이 그만큼 묶이지 않게 시간 제한에서는 그냥 부른다.
local function when_indexed(root, abs, sym, cb)
  local want, left, fin, id = {}, 0, false, nil
  for _, p in ipairs(abs) do
    if not want[p] then
      want[p] = true
      left = left + 1
    end
  end
  local function finish()
    if fin then
      return
    end
    fin = true
    if id then
      pcall(api.nvim_del_autocmd, id)
    end
    cb()
  end
  id = api.nvim_create_autocmd('User', {
    pattern = 'VimIdeIndexUpdated',
    callback = function(ev)
      local d = type(ev.data) == 'table' and ev.data or {}
      if fin or d.root ~= root then
        return
      end
      if d.kind == 'single' then
        for _, p in ipairs(d.paths or {}) do
          if want[p] then
            want[p] = nil
            left = left - 1
          end
        end
        if left <= 0 then
          vim.schedule(finish)
        end
      elseif not sym or #global_lines(root, { '-d', sym }, 2000) > 0 then
        vim.schedule(finish)
      end
    end,
  })
  vim.defer_fn(finish, (tonumber(cfg('single_update_timeout', 20)) or 20) * 1000)
end

-- 테스트용 진입점. autoindex 가 있으면 그쪽 큐(락 아래서 하나씩)로 넣는다 -
-- 이 nvim 안에서도 한 DB 에 일꾼 둘이 붙지 않게 (K1). 없을 때의 자체 큐가
-- 정말 하나씩 돌리고 시간이 지나면 죽이는지는 가짜 'global' 을 PATH 앞에
-- 두고 이걸 불러서 확인한다.
function _G.projectfiles_single_update(root, rels, cb)
  if type(_G.autoindex_single_update) == 'function' then
    local abs = {}
    for i, r in ipairs(rels or {}) do
      abs[i] = r:sub(1, 1) == '/' and r or (root .. '/' .. r)
    end
    if cb then
      when_indexed(root, abs, nil, cb)
    end
    return _G.autoindex_single_update(root, abs)
  end
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

-- 심볼을 정의한 파일들(hits, 상대 경로)을 담는다. 목록까지만 고치고(바뀐
-- 만큼만), 색인은 부른 쪽이 index_symbol_files 로 autoindex 에 맡긴다.
-- 돌려주는 것: 색인할 파일들, 새로 담은 것, 바뀐 파일
local function add_symbol_files(root, name, hits)
  local entries, _, _, exclude = entries_of(root)
  local listed = listed_set(root)
  local have = {}
  for _, e in ipairs(entries or {}) do
    have[e.path] = true
  end
  local fresh, todo, adds = {}, {}, {}
  for _, rel in ipairs(hits) do
    rel = norm_rel(rel)
    if not have[rel] then
      have[rel] = true
      if listed[rel] then
        -- 이미 목록에 있는데(디렉터리 항목 안) 색인이 답하지 못했다: 항목은
        -- 늘리지 않고 그 파일만 다시 색인한다. 예전에는 군더더기 파일 항목을
        -- 하나 더 담으면서 그 즉시 색인으로 이 경우를 우연히 고쳤다.
        todo[#todo + 1] = rel
      else
        entries[#entries + 1] = { path = rel, kind = 'file' }
        fresh[#fresh + 1] = rel
        todo[#todo + 1] = rel
        adds[#adds + 1] = { abs = root .. '/' .. rel }
      end
    end
  end
  local changes
  if #fresh > 0 then
    -- 그 파일 자신을 뺐던 기록(exclude)은 지운다 (파일 항목이 이기기는 한다)
    local isnew, ex2 = {}, {}
    for _, r in ipairs(fresh) do
      isnew[r] = true
    end
    for _, x in ipairs(exclude or {}) do
      if not isnew[x] then
        ex2[#ex2 + 1] = x
      end
    end
    local _
    _, changes = save_entries(root, name, entries, ex2, { add = adds },
      { no_reindex = true })
  end
  return todo, fresh, changes
end

-- 담은 파일을 색인에 넣고, 들어가면 fin() (K1).
--
-- 예전에는 자체 큐로 'global --single-update' 를 돌린 뒤 reindex 를 불렀다.
-- 그 단일 갱신이 GPATH 를 바꿔서 autoindex 가 사본(files.indexed)을 믿지
-- 못하게 됐고, 이어진 reindex 가 같은 파일을 한 번 더 넣고 목록 전체로
-- gtags -i 까지 돌렸다 (INT1: 실측 4초 동안 락). 이제는
--   새로 담은 파일  목록이 바뀌었다 -> reindex(changes) -> autoindex_refresh 의
--                   빠른 길이 락 아래서 그 파일만 넣는다
--   이미 있던 파일  목록은 그대로다 -> _G.autoindex_single_update (락 아래서)
-- autoindex 가 없거나 꺼져 있으면 예전처럼 자체 큐로 넣는다.
local function index_symbol_files(root, sym, todo, fresh, changes, fin)
  local isnew, abs, again, added = {}, {}, {}, {}
  for _, r in ipairs(fresh) do
    isnew[r] = true
    added[#added + 1] = root .. '/' .. r
  end
  for _, r in ipairs(todo) do
    abs[#abs + 1] = root .. '/' .. r
    if not isnew[r] then
      again[#again + 1] = root .. '/' .. r
    end
  end
  -- changes 가 없으면(목록을 통째로 다시 폈다) 담은 것만이라도 알려 준다:
  -- autoindex 는 어차피 목록을 색인 사본과 견주어 나머지를 찾는다
  local took = #added == 0 or reindex(root, changes or { added = added })
  if took and #again > 0 then
    local ok, res = pcall(_G.autoindex_single_update, root, again)
    took = ok and res == true
  end
  if took then
    -- 알림(VimIdeIndexUpdated)은 예약된 콜백에서만 오므로 지금 걸어도 늦지 않다
    when_indexed(root, abs, sym, fin)
  else
    -- autoindex 가 없거나 꺼져 있다 (g:autoindex_gtags = 0): 이 DB 에 다른
    -- 일꾼이 없으니 예전처럼 자체 큐로 넣는다
    single_update(root, todo, fin)
  end
end

function _G.projectfiles_add_for_symbol_async(sym, cb)
  cb = cb or function() end
  if type(sym) ~= 'string' or not sym:match('^[A-Za-z_][A-Za-z0-9_]*$') then
    return cb(0)
  end
  local root = cur_root()
  local _, name = entries_of(root)
  if not name then
    return cb(0) -- auto mode indexes everything already
  end
  grep_defining_async(root, sym, function(hits)
    -- 찾는 사이(커널 트리의 git grep 은 몇 초) preset 을 바꿨으면 담지 않는다
    -- (INT5). 항목은 지금 preset 에서 읽고 저장은 찾기 전의 이름으로 해서,
    -- 바꾼 preset 의 항목이 예전 preset 을 덮어썼다 (kp 의 drivers·include 가
    -- 사라졌다). 새 preset 에 몰래 담는 것도 부른 사람이 뜻한 게 아니다.
    local now = active_preset(root)
    if now ~= name then
      local m = mode_of(root)
      now = now or (m == MODE_UNSET and '미설정' or m)
      cb(0)
      -- 부른 쪽이 cb(0) 에서 '찾지 못했습니다' 를 낼 수 있다: 두 줄이 쌓이면
      -- Press ENTER 가 뜨고 그동안 색인 콜백이 멈춘다. 지우고 이것을 남긴다.
      pcall(vim.cmd, 'redraw')
      notify(("'%s' 정의를 찾는 사이 preset 이 바뀌어 (%s -> %s) 담지 않았습니다"):format(
        sym, name, now), vim.log.levels.WARN)
      return
    end
    local todo, fresh, changes = add_symbol_files(root, name, hits)
    if #todo == 0 then
      return cb(0)
    end
    -- 새 파일을 지금 색인해 둔다: 이걸 부른 점프를 곧바로 다시 시도할 수
    -- 있게. cb 는 색인에 들어간 뒤에 부른다.
    index_symbol_files(root, sym, todo, fresh, changes, function()
      notify(("'%s' 정의 파일 %d개 추가: %s")
        :format(sym, #todo, table.concat(#fresh > 0 and fresh or todo, ', ')))
      cb(#todo)
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
  local _, name = entries_of(root)
  if not name then
    return 0 -- auto mode indexes everything already
  end
  local hits = grep_defining(root, sym)
  local todo, fresh, changes = add_symbol_files(root, name, hits)
  if #todo == 0 then
    return 0
  end
  -- index the new files NOW so the jump that triggered this can be retried
  -- immediately (autoindex 가 락 아래서 하나씩 넣는다 - index_symbol_files)
  index_symbol_files(root, sym, todo, fresh, changes, function()
    notify(("'%s' 을(를) 정의한 파일 %d개를 추가했습니다: %s")
      :format(sym, #todo, table.concat(#fresh > 0 and fresh or todo, ', ')))
  end)
  return #todo
end

-- side-tree entries an earlier, less picky expansion may have pulled in
ucmd('ProjectFilesPrune', function()
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
ucmd('ProjectFilesRestore', function(o)
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
        save_entries(root, name, d.entries, d.exclude or {})
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
    save_entries(root, name, d.entries, d.exclude or {})
    notify(('%s 로 되돌렸습니다 (항목 %d -> %d)  →  %s'):format(
      list[idx].stamp, now, #d.entries, target_label(root)))
  end)
end, { nargs = '?', desc = 'Restore the preset from a backup taken before a write' })

ucmd('ProjectFilesAddSymbol', function(o)
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

-- 줄이 파일이 아닌 픽커(\fm/F2, \fM, \fS, \fx, :ProjectFilesAddDir)에서
-- Ctrl+X / Ctrl+V / Ctrl+T 는 아무것도 하지 않는다. telescope 의 기본 동작은
-- 줄의 글자를 파일 이름으로 :split 해서 '● none  (아무것도 …)' 같은 이름의
-- 빈 버퍼가 남았고, :w 하면 그 이름의 파일이 생겼다 (QA). 바꿔 끼운 것은
-- 픽커가 닫힐 때 telescope 가 걷으므로 다른 픽커의 분할 열기는 그대로다.
local function no_split_open(t)
  for _, a in ipairs({ 'select_horizontal', 'select_vertical', 'select_tab' }) do
    if t.actions[a] then
      t.actions[a]:replace(function() end)
    end
  end
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
    local key = st2 and ('gt:' .. stat_key(st2)) or nil
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

-- 고른 파일을 어느 창에 열까.
--
-- 예전에는 탭의 '첫 번째' 편집 창을 집었다. 그래서 EDIT 을 넷으로 나눠
-- 놓고 어느 창에서 \fo 를 부르든 늘 맨 앞 창에 열렸다. 지금 보고 있던
-- 자리를 잃는 셈이다.
--
-- 이제는 '부를 때 포커스가 있던 창'을 먼저 쓴다. telescope 는 닫을 때
-- 원래 창으로 돌려주므로 대개 지금 창이 그것이지만, 확실하게 하려고
-- 픽커가 열릴 때 잡아 둔 창(prefer)을 넘겨받는다.
local function open_in_edit(root, rel, prefer)
  local abs = rel:sub(1, 1) == '/' and rel or (root .. '/' .. rel)
  -- 편집에 쓸 수 있는 창인가.
  --
  -- 판정은 정본(vimidewin.lua)에 맡긴다. 여기 있던 잣대는 buftype 만 봐서
  -- quickr-preview 의 미리보기 창(\p)을 편집 창으로 쳤다.
  local function usable(w)
    if not (w and api.nvim_win_is_valid(w)) then
      return false
    end
    if type(_G.vimide_is_edit_win) == 'function' then
      local ok, r = pcall(_G.vimide_is_edit_win, w)
      if ok then
        return r and true or false
      end
    end
    if api.nvim_win_get_tabpage(w) ~= api.nvim_get_current_tabpage() then
      return false
    end
    local b = api.nvim_win_get_buf(w)
    return vim.bo[b].buftype == ''
        and not api.nvim_buf_get_name(b):match('RelationView')
  end
  -- 어느 창에 열까.
  --
  -- 예전에는 셋째 수가 '이 탭의 첫 번째 편집 창' 이었다. 그래서 곁창
  -- (aerial/quickfix/트리/패널)에 커서를 둔 채 \fo 나 \fs/F7 로 파일을
  -- 고르면, 직전까지 보던 창이 아니라 맨 왼쪽/위 창이 바뀌어 보던 자리를
  -- 잃었다. 이제 '직전에 보던 편집 창'(_G.vimide_last_edit_win) 을 먼저
  -- 묻고, 그래도 없으면 편집 자리를 빌려 쓰는 창까지 본다.
  local target
  if usable(prefer) then
    target = prefer
  elseif usable(api.nvim_get_current_win()) then
    target = api.nvim_get_current_win()
  else
    for _, fn in ipairs({ '_G.vimide_last_edit_win', '_G.vimide_edit_slot' }) do
      local f = fn == '_G.vimide_last_edit_win' and _G.vimide_last_edit_win
          or _G.vimide_edit_slot
      if type(f) == 'function' then
        local ok, w = pcall(f)
        if ok and w and w ~= 0 and api.nvim_win_is_valid(w) then
          target = w
          break
        end
      end
    end
  end
  if not target then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if usable(w) then
        target = w
        break
      end
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
  -- 나노초까지: 'gtags -i' 는 파일을 빼도 GTAGS 크기가 그대로라, 초와 크기만
  -- 보면 같은 초 안의 갱신을 놓친다 (T8)
  local key = stat_key(db_stat(root))
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

-- autoindex 가 색인을 바꿀 때마다 알린다 (C4). 심볼·경로 목록은 GTAGS 의
-- stat 으로도 버려지지만, 같은 틱 안의 두 번째 갱신처럼 stat 이 못 보는 것까지
-- 여기서 확실히 버린다.
api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'VimIdeIndexUpdated',
  callback = function(a)
    local r = type(a.data) == 'table' and a.data.root or nil
    if type(r) == 'string' and r ~= '' then
      if s.symbols then
        s.symbols[r] = nil
      end
      paths_cache[r] = nil
    end
  end,
})

-- A whole kernel tree in auto mode holds millions of definitions: dumping
-- all of them would build millions of Lua tables and freeze nvim. Past this
-- much database, the picker asks 'global' for the prefix that was typed
-- instead of for everything.
local function huge_db(st)
  return st ~= nil
      and st.size > (cfg('symbol_db_max_mb', 40) * 1024 * 1024)
end

local function symbols_of(root, prefix)
  local key = stat_key(db_stat(root)) .. '\0' .. (prefix or '')
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
  -- 쌓아 주지 않는다. 쌓을 때는 :tag 처럼 't' 로 - 'a' 는 <C-t> 로 되짚어
  -- 나온 칸을 남긴 채 덧붙여, 다음 <C-t> 가 그 칸을 다시 들렀다 (QA).
  local from = { vim.fn.bufnr('%'), vim.fn.line('.'), vim.fn.col('.'), 0 }
  local ok = pcall(open_in_edit, root, e.path)
  if not ok then
    notify('편집할 창을 찾지 못했습니다: ' .. e.path, vim.log.levels.WARN)
    return
  end
  local win = api.nvim_get_current_win()
  if vim.fn.getbufvar(from[1], '&buftype') == '' then
    pcall(vim.fn.settagstack, win,
      { items = { { tagname = e.name or '?', from = from } } }, 't')
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
    prompt_title = ('Symbols %d  <CR> jump  <F12> relation'):format(#syms),
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
      -- 이름을 치자마자 넘기면 걸러지기 전 첫 심볼이 넘어갔다 (반대 심문) -
      -- 목록이 따라온 뒤에 넘긴다
      local function to_relation_ready()
        local pk = t.state.get_current_picker(bufnr)
        if pk and type(_G.vimide_picker_ready) == 'function' then
          _G.vimide_picker_ready(pk, to_relation)
        else
          to_relation()
        end
      end
      map({ 'i', 'n' }, '<F12>', to_relation_ready)
      map({ 'i', 'n' }, '<C-g>', to_relation_ready)
      return true
    end,
  }):find()
end

-- <leader>fo : find a project file and jump to it
-- 텔레스코프 창을 닫지 않고 목록을 갈아 끼운다 (\fo, F3, \fx 에서 지운 뒤).
-- 친 글자·선택 자리를 지키는 것과, 갈아 끼우는 동안 키를 받지 않는 것은
-- pickerkeep.lua 가 한다. 그것이 없으면(따로 떼어 쓴 경우) 그냥 다시 찾는다.
local function picker_refresh(picker, finder, title)
  if type(_G.vimide_picker_keep) == 'function' then
    return _G.vimide_picker_keep(picker, finder, { title = title })
  end
  pcall(function() picker.layout.prompt.border:change_title(title) end)
  picker:refresh(finder, { reset_prompt = false })
end

local function picker_busy(picker)
  return type(_G.vimide_picker_busy) == 'function' and _G.vimide_picker_busy(picker)
end

-- 두 목록이 같은가. 지우기가 취소됐거나(확인 창) 이미 없던 항목이면 목록이
-- 그대로다 - 그때는 갈아 끼우지 않는다. 갈아 끼우면 <Tab> 표시가 지워진다.
local function same_list(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- 바쁨을 재기 시작한다 (pickerkeep.lua). 창이 다 선 뒤에.
local function picker_track(t, bufnr)
  vim.schedule(function()
    if type(_G.vimide_picker_track) == 'function' then
      pcall(_G.vimide_picker_track, t.state.get_current_picker(bufnr))
    end
  end)
end

-- 픽커에서 지울 것: <Tab> 으로 골라 둔 것들, 없으면 커서 줄 하나
local function picker_picks(t, bufnr)
  local picker = t.state.get_current_picker(bufnr)
  local picks = picker and picker:get_multi_selection() or {}
  if #picks == 0 then
    local e = t.state.get_selected_entry()
    picks = e and { e } or {}
  end
  return picker, picks
end

local function pick_find()
  local root = cur_root()
  -- none / unset 모드에는 색인 목록이 없다. 예전에는 그때 프로젝트 전체를
  -- 훑는 스크립트를 그 자리에서 돌려(4만 파일 트리에서 3.4초) F3 을 누를
  -- 때마다 멎었다 (QA). 목록 대신 전체 파일을 비동기로 찾는 창을 연다.
  local m0 = mode_of(root)
  if m0 == MODE_NONE or m0 == MODE_UNSET then
    local okb, builtin = pcall(require, 'telescope.builtin')
    if okb then
      -- 뜬 트리(F11)에서 불렸으면 편집 창으로 나간 뒤에 연다 (<C-q> 가 편집 창을
      -- quickfix 로 덮지 않게 - reposearch.lua 와 같다)
      if api.nvim_win_get_config(0).relative ~= '' and type(_G.vimide_last_edit_win) == 'function' then
        local okw, w = pcall(_G.vimide_last_edit_win)
        if okw and type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w) then
          pcall(api.nvim_set_current_win, w)
        end
      end
      builtin.find_files({
        cwd = root,
        prompt_title = ('Project files  →  %s   [%s: 색인 목록 없음 - 전체에서 찾기]')
            :format(target_label(root), m0 == MODE_NONE and 'none' or '모드 미정'),
      })
      return
    end
  end
  local files = current_files(root)
  -- 고른 파일은 '여기서 불렀다'는 그 창에 연다
  local from_win = api.nvim_get_current_win()
  local t = telescope()
  if not t then
    return fallback_select(files, 'Project files',
      function(c) open_in_edit(root, c, from_win) end)
  end
  local function title()
    return ('Project files (%d)  →  %s   ^d/<Esc>d 제거 (<Tab> 여럿)')
        :format(#files, target_label(root))
  end
  local function make_finder()
    return t.finders.new_table({
      results = files,
      entry_maker = function(e)
        return { value = e, display = e, ordinal = e, path = root .. '/' .. e }
      end,
    })
  end
  -- 지워도 창은 그대로 둔다. 한 번의 커밋으로 빼고(재색인 한 번, 알림 한
  -- 줄) 목록을 다시 읽어 갈아 끼운다.
  --
  -- <C-a>(추가 창 열기)는 뺐다. \fp 와 같은 창인데, 느려서 \fp·\fd 를 껐다.
  local function remove(bufnr)
    local picker, picks = picker_picks(t, bufnr)
    -- 목록을 갈아 끼우는 중에 온 키는 버린다 - 그 사이의 선택은 방금 지운 항목이다
    if #picks == 0 or picker_busy(picker) then
      return
    end
    -- 목록이 없는 모드(auto 등)에서는 뺄 것이 없다. 배치로 돌리면 아무것도
    -- 안 빠졌는데 재색인(프로젝트 전체)만 돈다 - remove_path 가 한 번 알리고
    -- 끝나게 둔다. 하나만 지울 때도 remove_path 를 곧장 부른다: 디렉터리
    -- 항목이 한꺼번에 많이 빠지면 물어보는 것은 배치 밖에서만 한다.
    local _, name, bad = entries_of(root)
    if bad or not name or #picks == 1 then
      one_line(remove_path, root, picks[1].value)
    else
      in_batch(root, '제거', function()
        for _, e in ipairs(picks) do
          remove_path(root, e.value)
        end
      end)
    end
    if not picker or bad or not name then
      return
    end
    -- 마지막 항목까지 빠지면 none 모드가 되고 목록 파일이 지워진다. 그때
    -- current_files 는 프로젝트 전체를 훑는 스크립트로 떨어지므로 부르지
    -- 않는다 - 빈 목록이 맞다.
    local fresh = mode_of(root) == MODE_NONE and {} or current_files(root)
    if same_list(files, fresh) then
      return
    end
    files = fresh
    picker_refresh(picker, make_finder(), title())
  end
  t.pickers.new({}, {
    prompt_title = title(),
    finder = make_finder(),
    sorter = t.conf.generic_sorter({}),
    previewer = t.conf.file_previewer({}),
    attach_mappings = function(bufnr, map)
      t.actions.select_default:replace(function()
        -- 목록이 프롬프트를 아직 따라오지 않았으면(방금 지웠다, 방금 쳤다)
        -- 따라온 뒤에 연다 - 그 사이의 선택은 방금 지운 파일이거나 새 글자로
        -- 걸러지기 전의 항목이다.
        local function go()
          local entry = t.state.get_selected_entry()
          t.actions.close(bufnr)
          if entry then
            open_in_edit(root, entry.value, from_win)
          end
        end
        local pk = t.state.get_current_picker(bufnr)
        if pk and type(_G.vimide_picker_ready) == 'function' then
          _G.vimide_picker_ready(pk, go)
        else
          go()
        end
      end)
      map({ 'i', 'n' }, '<C-d>', function() remove(bufnr) end)
      -- 'd' 는 노멀 모드에서만 (입력 모드에서는 검색할 글자다)
      map('n', 'd', function() remove(bufnr) end)
      picker_track(t, bufnr)
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
      function(c) one_line(add_with_related, root, c) end)
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
        -- <Tab> 으로 여러 개를 골랐으면 한 번만 쓰고 한 번만 재색인한다
        one_line(function()
          announce_root(root)
          in_batch(root, '추가', function()
            for _, e in ipairs(picks) do
              add_with_related(root, e.value)
            end
          end)
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
          and nested_owner_in(nested_prefixes(root), l .. '/')) then
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
      function(c) one_line(add_path, root, c) end)
  end
  t.pickers.new({}, {
    prompt_title = ('Add directories (%d)  →  %s   <Tab> 여러 개')
        :format(#items, target_label(root)),
    finder = t.finders.new_table({ results = items }),
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      no_split_open(t)
      t.actions.select_default:replace(function()
        local picker = t.state.get_current_picker(bufnr)
        local picks = picker:get_multi_selection()
        if #picks == 0 then
          local e = t.state.get_selected_entry()
          picks = e and { e } or {}
        end
        t.actions.close(bufnr)
        one_line(function()
          announce_root(root)
          in_batch(root, '추가', function()
            for _, e in ipairs(picks) do
              add_path(root, e[1] or e.value)
            end
          end)
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
      tag = presets_differ(mine, sh)
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
      no_split_open(t)
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
  local entries, _, _, exclude = entries_of(root)
  entries = entries or {}
  if #entries == 0 then
    notify('저장할 항목이 없습니다 (트리에서 + 나 :ProjectFilesAdd 로 추가하세요)', vim.log.levels.WARN)
    return
  end
  local function save(name)
    if not name or name == '' then
      return
    end
    preset_write(name, entries, exclude or {})
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
      no_split_open(t)
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
  local function items_of()
    local items = {}
    for _, e in ipairs(entries_of(root) or {}) do
      items[#items + 1] = e.kind .. '  ' .. e.path
    end
    return items
  end
  local items = items_of()
  local t = telescope()
  local function drop(label)
    one_line(remove_path, root, (label:gsub('^%a+%s+', '')))
  end
  if not t then
    return fallback_select(items, '제거할 항목', drop)
  end
  local function title()
    return ('Remove from project files (%d)  →  %s   <CR>/^d/<Esc>d 제거 (<Tab> 여럿)')
        :format(#items, target_label(root))
  end
  -- 지워도 창은 그대로 둔다 (\fo 와 같다). 닫기는 <Esc> 두 번 / <C-c>.
  local function remove(bufnr)
    local picker, picks = picker_picks(t, bufnr)
    -- 목록을 갈아 끼우는 중에 온 키는 버린다 - 그 사이의 선택은 방금 지운 항목이다
    if #picks == 0 or picker_busy(picker) then
      return
    end
    -- 하나면 곧장 (디렉터리 항목이 많이 빠질 때 물어본다), 여럿이면 한 번의 커밋으로
    if #picks == 1 then
      drop(picks[1][1] or picks[1].value)
    else
      in_batch(root, '제거', function()
        for _, e in ipairs(picks) do
          drop(e[1] or e.value)
        end
      end)
    end
    if not picker then
      return
    end
    local fresh = items_of()
    if same_list(items, fresh) then
      return
    end
    items = fresh
    picker_refresh(picker, t.finders.new_table({ results = items }), title())
  end
  t.pickers.new({}, {
    prompt_title = title(),
    finder = t.finders.new_table({ results = items }),
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(bufnr, map)
      no_split_open(t)
      t.actions.select_default:replace(function() remove(bufnr) end)
      -- 여기서는 <CR> 도 지우는 키다. 전역 <CR>(목록이 따라온 뒤에 한다)을 거치면
      -- 갈아 끼우는 동안 온 두 번째 <CR> 이 버려지지 않고 줄을 섰다가 다음 항목을
      -- 지웠다 (반대 심문: 빠른 <CR><CR> 에 둘이 빠짐). 곧장 remove 로 보내
      -- '바쁘면 버린다'를 지킨다.
      map({ 'i', 'n' }, '<CR>', function() remove(bufnr) end)
      map({ 'i', 'n' }, '<C-d>', function() remove(bufnr) end)
      map('n', 'd', function() remove(bufnr) end)
      picker_track(t, bufnr)
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
  { desc = 'Find a project file (telescope) - ^d remove, <Tab> several' })
api.nvim_create_user_command('ProjectFilesFind', function() pick_find() end,
  { desc = 'Find a project file and jump to it' })

ucmd('ProjectFilesAdd', function(o)
  if o.args == '' then
    pick_add()
    return
  end
  add_with_related(root_for_arg(o.args), o.args)
end, { nargs = '?', complete = 'file',
  desc = 'Add a file/directory (with the headers and definitions it uses)' })

ucmd('ProjectFilesRemove', function(o)
  if o.args == '' then
    pick_remove()
    return
  end
  remove_path(root_for_arg(o.args), o.args)
end, { nargs = '?', complete = 'file', desc = 'Remove a file/directory' })

ucmd('ProjectFilesAddDir', function(o)
  if o.args == '' then
    pick_add_dir()
    return
  end
  add_path(root_for_arg(o.args), o.args)
end, { nargs = '?', complete = 'dir',
  desc = 'Add a directory (everything indexable under it)' })

-- 모드를 지금 다시 고른다. 시작할 때 뜨는 것과 같은 다이얼로그다.
ucmd('ProjectFilesAbsorb', function()
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

ucmd('ProjectFilesMode', function()
  local root = cur_root()
  choose_mode(root, function(ok)
    if ok then
      reindex(root)
    end
  end)
end, { desc = 'Pick the indexing mode for this project (auto / a preset)' })

ucmd('ProjectFilesPreset', function(o)
  local root = cur_root()
  if o.args == '' then
    pick_preset()
    return
  end
  -- 저장된 적 없는 이름은 받지 않는다 (F2). 예전에는 오타('kp1x')도 '이름만
  -- 정한 새 preset' 으로 받아 빈 목록을 썼고, 그 빈 목록이 GTAGS 를 0개로,
  -- ctags 를 머리말 24줄로 비웠다 - 알림은 평소와 같은 한 줄이라 몰랐다.
  -- 새 preset 은 \fm 의 '새 preset 만들기' 나 :ProjectFilesSave <이름> 으로.
  -- (지금 쓰고 있는 이름은 그대로 받는다 - 바뀌는 것이 없다)
  if o.args ~= MODE_AUTO and o.args ~= MODE_NONE and o.args ~= active_preset(root) then
    local sp = shared_path(o.args)
    if not (uv.fs_stat(preset_path(o.args)) or (sp and uv.fs_stat(sp))) then
      notify(("그런 preset 이 없습니다: '%s' (새로 만들려면 \\fm 의 '새 preset 만들기')")
        :format(o.args), vim.log.levels.WARN)
      return
    end
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

-- 다른 프로젝트의 preset 을 이 프로젝트로 가져온다 (:ProjectFilesImport)
--
-- 새 SDK 를 받으면 색인할 파일 목록은 거의 그대로다 - 트리 경로만 다르다.
-- preset 은 프로젝트 상대 경로 목록이라 그대로 쓸 수 있고, 색인은 이 트리의
-- 경로로 새로 만들어진다.
--
-- :ProjectFilesPreset 과 무엇이 다른가
--   그쪽은 '이 preset 을 쓴다'만 한다. 새 SDK 로 옮길 때 정작 알고 싶은
--   것은 '그 목록 중 몇 개가 이 트리에 실제로 있나'인데, 그걸 말해 주지
--   않는다. 실측: 246항목짜리 preset 을 다른 체크아웃에 걸었더니 101개는
--   그 트리에 없는 경로였다 - 조용히 빠졌다.
--   여기서는 고르기 전에 그 수를 보여주고, 고른 뒤에 '공유할지 복사할지'를
--   묻는다.
--
--   공유  두 프로젝트가 같은 preset 파일을 본다. 한쪽에서 파일을 넣으면
--         다른 쪽 목록도 같이 바뀐다.
--   복사  새 이름으로 떠서 따로 관리한다. SDK 판마다 목록이 갈리기
--         시작하면 이쪽이다 (qnx_..._d5 와 qnx_..._d5_A14 처럼).
local function pick_import()
  local root = cur_root()
  if not root or root == '' then
    notify('프로젝트를 찾지 못했습니다', vim.log.levels.WARN)
    return
  end
  local cur = active_preset(root)
  local items = {}
  -- 항목이 이 트리에 있는지는 부모 디렉터리를 한 번씩 읽어(readdir) 본다.
  -- 항목마다 stat 하면 모든 preset 의 항목 수만큼 stat 이 돈다 - 실측 46,800번,
  -- stat 이 느린 서버에서는 그것만 수십 초다 (S14). readdir 은 거기서 싸다.
  local listing = {} -- 디렉터리 -> { 이름 = 종류 } (없거나 못 읽으면 false)
  local function exists(abs)
    if abs == root then
      return true
    end
    local dir, base = vim.fs.dirname(abs), vim.fs.basename(abs)
    local l = listing[dir]
    if l == nil then
      l = false
      local h = uv.fs_scandir(dir)
      if h then
        l = {}
        while true do
          local nm, ty = uv.fs_scandir_next(h)
          if not nm then
            break
          end
          l[nm] = ty or 'unknown'
        end
      end
      listing[dir] = l
    end
    local ty = l and l[base]
    if not ty then
      return false
    end
    if ty == 'link' or ty == 'unknown' then
      return uv.fs_stat(abs) ~= nil -- 끊어진 링크는 없는 것 (예전 stat 과 같게)
    end
    return true
  end
  for _, n in ipairs(preset_list()) do
    local p = read_preset_file(preset_path(n)) or read_preset_file(shared_path(n))
    local es = p and p.entries or {}
    local here = 0
    for _, e in ipairs(es) do
      local rel = norm_rel(e.path)
      local abs = rel:sub(1, 1) == '/' and rel
          or ((rel == '.' or rel == '') and root or (root .. '/' .. rel))
      if exists(abs) then
        here = here + 1
      end
    end
    local pct = #es > 0 and math.floor(here * 100 / #es) or 0
    items[#items + 1] = {
      name = n, entries = es, exclude = p and p.exclude or {}, here = here,
      label = ('%s%-46s %4d항목 중 %4d개가 이 트리에 있음  (%d%%)')
          :format(cur == n and '● ' or '  ', n, #es, here, pct),
    }
  end
  if #items == 0 then
    notify('가져올 preset 이 없습니다', vim.log.levels.WARN)
    return
  end

  local function apply(name)
    set_active(root, name)
    local files = materialize(root)
    reindex(root)
    notify(("preset '%s' 을 가져왔습니다  →  파일 %d개  →  %s")
      :format(name, files and #files or 0, target_label(root)))
  end

  local function use(it)
    if it.here == 0 then
      notify(("'%s' 의 경로가 이 트리에는 하나도 없습니다 - 다른 체크아웃의 preset 입니다")
        :format(it.name), vim.log.levels.WARN)
      return
    end
    local c = vim.fn.confirm(
      ("'%s' (%d/%d 항목이 이 트리에 있음)"):format(it.name, it.here, #it.entries),
      "그대로 쓴다 - 목록을 공유(&S)\n새 이름으로 복사(&C)\n취소(&Q)", 1)
    if c == 1 then
      apply(it.name)
    elseif c == 2 then
      local suggest = it.name .. '_' .. vim.fn.fnamemodify(root, ':t')
      local ok, nm = pcall(vim.fn.input, '새 preset 이름: ', suggest)
      nm = ok and vim.trim(nm or '') or ''
      if nm == '' then
        return
      end
      preset_write(nm, it.entries, it.exclude)
      apply(nm)
    end
  end

  local t = telescope()
  if not t then
    local labels = {}
    for _, it in ipairs(items) do
      labels[#labels + 1] = it.label
    end
    return fallback_select(labels, '가져올 preset', function(_, idx)
      if idx then
        use(items[idx])
      end
    end)
  end
  t.pickers.new({}, {
    prompt_title = 'preset 가져오기  <CR> 고르기',
    finder = t.finders.new_table({
      results = items,
      entry_maker = function(e)
        return { value = e, display = e.label, ordinal = e.label }
      end,
    }),
    sorter = t.conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      no_split_open(t)
      t.actions.select_default:replace(function()
        local e = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if e then
          vim.schedule(function() use(e.value) end)
        end
      end)
      return true
    end,
  }):find()
end

ucmd('ProjectFilesImport', function(o)
  if o.args == '' then
    pick_import()
    return
  end
  local root = cur_root()
  local p = read_preset_file(preset_path(o.args)) or read_preset_file(shared_path(o.args))
  if not p then
    notify(("preset '%s' 을 찾지 못했습니다"):format(o.args), vim.log.levels.WARN)
    return
  end
  set_active(root, o.args)
  local files = materialize(root)
  reindex(root)
  notify(("preset '%s' 을 가져왔습니다  →  파일 %d개  →  %s")
    :format(o.args, files and #files or 0, target_label(root)))
end, { nargs = '?', complete = function() return preset_list() end,
  desc = '다른 프로젝트의 preset 목록을 이 프로젝트로 가져온다' })

ucmd('ProjectFilesSave', function(o)
  local root = cur_root()
  local entries, _, bad, exclude = entries_of(root)
  if bad then
    return -- 읽을 수 없는 preset을 빈 목록으로 덮어쓰지 않는다
  end
  entries = entries or {}
  if o.args == '' then
    pick_save()
    return
  end
  preset_write(o.args, entries, exclude or {})
  set_active(root, o.args)
  materialize(root)
  notify(("preset '%s' 저장 (%d entries)"):format(o.args, #entries))
end, { nargs = '?', desc = 'Save the current entries as a named preset' })

-- put a preset into vim-ide itself, so the other machines (the Linux box)
-- get it with the next 'git pull'. The repository copy is what every
-- checkout reads; my own copy in stdpath('data') keeps shadowing it.
ucmd('ProjectFilesPresetShare', function(o)
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
  if not write_json(dst, encode_preset(name, p.entries, p.exclude)) then
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

-- 무엇을 왜 색인에서 뺐는지. 시작할 때 뜨는 한 줄짜리 알림의 자세한 판이다
-- (그 알림을 길게 두면 vim 이 'Press ENTER' 로 멈춰 서므로 갈라 두었다).
api.nvim_create_user_command('ProjectFilesSkipped', function()
  local d = s.skip_detail
  if not d or (d.big + d.binary) == 0 then
    notify('색인에서 뺀 파일이 없습니다')
    return
  end
  local out = {
    ('%s 에서 색인에서 뺀 파일'):format(vim.fn.fnamemodify(d.root, ':~')),
    ('  바이너리      %d개  (g:projectfiles_skip_binary = 0 으로 끕니다)'):format(d.binary),
    ('  %.0fMB 초과    %d개  (g:projectfiles_max_bytes 로 조절합니다)'):format(
      d.max / 1048576, d.big),
  }
  if d.worst then
    out[#out + 1] = ('  가장 큰 것   %s  (%.1fMB)'):format(
      vim.fn.fnamemodify(d.worst.path, ':~:.'), d.worst.size / 1048576)
  end
  vim.api.nvim_echo({ { table.concat(out, '\n') } }, true, {})
end, { desc = '색인에서 뺀 파일과 그 이유' })

ucmd('ProjectFilesReindex', function()
  local root = cur_root()
  -- none / 미설정 모드에는 색인할 목록이 없다. 예전에는 여기서도 강제 갱신이
  -- 돌아 git ls-files 로 프로젝트 전체를 색인했다 (T2)
  if not mode_indexes(root) then
    notify('색인하지 않는 모드입니다 (' .. target_label(root)
      .. ') - <F2> 나 \\fm 으로 모드를 고르세요', vim.log.levels.WARN)
    return
  end
  -- 손으로 부른 것은 늘 통째로 다시 편다: 디렉터리 항목 아래에 그새 생기거나
  -- 없어진 파일까지 (+/- 는 바뀐 만큼만 고친다)
  --
  -- 펴기는 뒤에서 한다 (P2). 예전에는 키를 누른 채 목록 전체를 폈다 - 파일마다
  -- stat 이라 6,500개, 느린 stat 의 서버를 흉내 내면 0.7초 동안 화면이 멎었다.
  -- 시작할 때의 확인(verify_async)과 같은 길이다: find 는 자식 프로세스가,
  -- 파일마다의 stat 은 메인 루프에서 몇 ms 씩. 다 펴면 예전과 같은 순서로
  -- 목록을 쓰고 재색인하고 같은 알림을 한 줄로 낸다.
  local function finish(got)
    local changed = false
    if got ~= false then
      changed = select(3, materialize(root, got))
    end
    reindex(root)
    -- ctags 도 다시 만든다. 목록이 바뀌었으면 autoindex 가 갱신을 끝내며 따라가고
    -- (K2), 그대로면 따라가지 않으므로 여기서 부탁한다 - 예전에는 reindex 가 늘
    -- GutentagsUpdate! 를 불러서 \fR 이 낡은 tags 를 고치는 길이기도 했다.
    if not changed and type(_G.autoindex_ctags_refresh) == 'function' then
      pcall(_G.autoindex_ctags_refresh, root)
    end
    notify('재색인 시작')
  end
  -- 도는 것이 있으면 묶는다. 1분이 넘도록 끝나지 않은 것(find 가 멈췄다)은
  -- 믿지 않는다 - 그것의 답은 아래 표(mine)로 버려진다.
  s.reindexing = s.reindexing or {}
  local busy = s.reindexing[root]
  if busy and uv.now() - busy.t < 60000 then
    busy.again = true
    return
  end
  local function run()
    local entries, name, bad, exclude = entries_of(root)
    if bad then
      return one_line(finish, false) -- 읽을 수 없는 preset: 알림은 entries_of 가 냈다
    end
    if not (entries and name) then
      return one_line(finish, nil) -- auto 모드: 펼 것이 없다 (materialize 가 목록을 지운다)
    end
    -- lkey: 펴기 시작할 때의 목록 파일. 그 사이 목록만 바뀐 것(새 파일 저장이
    -- 그 파일을 넣었다, 다른 nvim)은 항목이 그대로라 아래 ckey 로는 모른다
    local mine = { t = uv.now(), lkey = stat_key(uv.fs_stat(list_path(root))) }
    s.reindexing[root] = mine
    load_known(root)
    local ckey = content_key(name, entries, exclude)
    local function go(pre)
      expand_async(root, entries, make_rules(entries, exclude), function(found, sk)
        if s.reindexing[root] ~= mine then
          return -- 더 새 \fR 이 맡았다
        end
        s.reindexing[root] = nil
        -- 모드를 그새 none 으로 바꿨으면 그쪽이 할 일을 했다
        if not mode_indexes(root) then
          return
        end
        one_line(function()
          -- 그 사이 또 불렀거나 항목이 바뀌었거나(+/-, 다른 preset) 목록이
          -- 바뀌었으면 지금 것으로 처음부터 다시 편다 - 낡은 펴기로 목록을 쓰면
          -- 그쪽이 고친 것이 빠진다 (펴기 전에 찾은 것만 쓰니 그새 저장한 새
          -- 파일이 목록과 GTAGS 에서 도로 빠졌다)
          local e2, n2, bad2, x2 = entries_of(root)
          if mine.again or (not bad2 and e2 and n2
              and content_key(n2, e2, x2) ~= ckey)
              or stat_key(uv.fs_stat(list_path(root))) ~= mine.lkey then
            return run()
          end
          -- found 가 nil: find 를 띄우지 못했다 - 예전처럼 여기서 편다
          finish(found and { found = found, sk = sk, pre = pre, ckey = ckey })
        end)
      end)
    end
    if cfg('nested_presets', 0) ~= 0 then
      nested_prefixes_async(root, go)
    else
      go({})
    end
  end
  run()
end, { desc = 'Rebuild the index for the current file list' })

-- 새로 만든 파일을 저장하면 그것만 색인에 넣는다
--
-- 이미 목록에 있는 파일은 autoindex.lua 의 BufWritePost 가 저장할 때마다
-- 'global --single-update' 로 갱신한다(그 파일 하나, 몇 ms). 함수를 넣거나
-- 지우면 바로 반영되므로 여기서 할 일이 없다 - 그냥 돌아간다.
--
-- 남는 것은 '목록에 없는 파일'이다. 새로 만든 파일이 대표적인데,
-- autoindex 는 목록 밖이라 일부러 건너뛴다. preset 의 디렉터리 항목 아래에
-- 생긴 파일이라면 목록에 들어가야 맞다. 그래서 그때만:
--   1) 그 파일 하나만 목록에 넣는다 (다시 펴지 않는다)
--   2) autoindex 에게 그 파일을 알린다 - 락 아래서 그 파일만
--      'global --single-update' 로 넣는다 (K1)
-- 전체 재색인('gtags -i')은 하지 않는다. 실측(개발서버, 목록 273개):
-- 한 파일 넣기 0.04초.
--
-- 디렉터리 항목 아래가 아니면 다시 펴 봐야 목록에 들어갈 수 없다. 그건
-- 경로만 보고 미리 걸러서 아무 것도 하지 않는다 - 임시 파일을 저장할
-- 때마다 find 가 도는 일이 없어야 한다.
--
-- 묶어서 한 번만 돈다. :wa 처럼 잇달아 저장해도 마지막 저장 뒤 한 번이다.
-- 그 사이 저장한 경로는 전부 모아 두었다가(s.save_pending) 그 한 번에 함께
-- 본다 (N1). 예전에는 마지막 저장의 경로 하나만 봤다 - 새 파일을 저장하고
-- 1초 안에 다른 파일을 저장하면(:wa, foo.c 다음 foo.h) 앞의 새 파일은 목록에도
-- GTAGS 에도 ctags 에도 들지 못했고, 다음 \fR 이나 다음 시작까지 그대로였다.
--
--   let g:projectfiles_index_new_on_save = 0     " 끈다
--   let g:projectfiles_index_new_on_save_delay = 1000
local save_gen = 0
api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function(a)
    if tonumber(cfg('index_new_on_save', 1)) == 0 then
      return
    end
    if not (a.buf and api.nvim_buf_is_valid(a.buf))
        or vim.bo[a.buf].buftype ~= '' then
      return
    end
    local path = a.match ~= '' and vim.fn.fnamemodify(a.match, ':p') or nil
    if not path then
      return
    end
    s.save_pending = s.save_pending or {}
    s.save_pending[path] = true
    save_gen = save_gen + 1
    local mine = save_gen
    local delay = tonumber(cfg('index_new_on_save_delay', 1000)) or 1000
    vim.defer_fn(function()
      if mine ~= save_gen then
        return -- 그 사이 또 저장했다. 마지막 것이 모은 것을 다 한다.
      end
      local saved = s.save_pending or {}
      s.save_pending = nil
      -- 프로젝트마다 한 번: 목록 고치기 한 번, autoindex 부르기 한 번
      local function take(root, paths)
        -- '색인하지 않는 모드' 는 사용자가 그렇게 고른 것이다. 건드리지 않는다.
        if type(_G.projectfiles_should_index) == 'function'
            and not _G.projectfiles_should_index(root) then
          return
        end
        local list = root .. '/' .. (dbdir() or '.tags') .. '/files'
        if not uv.fs_stat(list) then
          return -- auto 모드(목록이 없다): autoindex 가 이미 넣었다
        end
        -- 목록이 정렬돼 있으니 반씩 나눠 찾는다
        local function listed(files, rel)
          return files ~= nil and files[lower_bound(files, rel)] == rel
        end
        -- 목록과 항목을 기억에 올린다 (세션의 처음이면 지난 목록을 받는다 -
        -- 펴지 않는다)
        pcall(_G.projectfiles_materialize, root)
        local c = s.cache[root]
        if not (c and c.files) then
          return
        end
        -- 목록에 없고 지금 규칙으로 목록에 드는 것만 - 디렉터리 항목 아래이고
        -- 빼 둔 곳(exclude)이 아니어야 한다. 아니면 다시 펴도 들어갈 수 없다.
        -- (루트 항목 '.' 도 덮는다 - 예전 검사는 그것을 놓쳤다. .git 아래의
        -- 커밋 메시지 같은 것은 find 가 늘 빼는 자리다.) 이미 목록에 있는 것은
        -- autoindex 가 저장할 때 방금 갱신했다.
        local rules = make_rules(c.entries, c.exclude)
        local adds, rels = {}, {}
        for _, p in ipairs(paths) do
          local rel = rel_to(root, p)
          if not listed(c.files, rel) and rule_of(rules, rel) == true
              and not pruned_part(rel) then
            local st = uv.fs_stat(p)
            if st and st.type == 'file' then
              adds[#adds + 1] = { abs = p, st = st }
              rels[#rels + 1] = rel
            end
          end
        end
        if #adds == 0 then
          return
        end
        -- 그 파일들만 목록에 넣는다. 예전에는 목록 전체를 다시 폈다 (실측
        -- 0.36초, 느린 stat 의 서버에서는 목록 크기만큼 더).
        local ok, files, _, changes = pcall(commit_list, root,
          cache_valid(root, c.preset) and { add = adds } or nil)
        if not ok then
          return
        end
        local got, abs = {}, {}
        for _, rel in ipairs(rels) do
          if listed(files, rel) then
            got[#got + 1] = rel
            abs[#abs + 1] = root .. '/' .. rel
          end
        end
        if #got == 0 then
          return -- 목록에 못 들어갔다: 색인은 그대로 둔다
        end
        if type(_G.projectfiles_tree_invalidate) == 'function' then
          pcall(_G.projectfiles_tree_invalidate) -- 표시도 따라오게
        end
        -- 색인은 autoindex 에 맡긴다 (K1). 예전에는 자체 큐로 그 파일만 넣었는데,
        -- 그 큐는 autoindex 의 락을 몰라서 그때 돌던 gtags -i(예전 목록)가 끝나며
        -- 이 파일을 도로 지웠고, 표지도 없어 아무도 다시 하지 않았다 (F1/INT1).
        -- autoindex_refresh 는 표지를 남기고, 도는 갱신이 있으면 그 뒤에, 없으면
        -- 락 아래서 이 파일들만 넣는다 (gtags -i 없이). reindex 는 부르지 않는다 -
        -- 심볼 목록·트리 표시까지 버릴 일이 아니다 (트리는 위에서 고쳤다).
        local okA, took = pcall(_G.autoindex_refresh, root, true, '새 파일 저장',
          changes or { added = abs })
        if not (okA and took == true) then
          -- autoindex 가 없거나 꺼져 있다: 다른 일꾼이 없으니 자체 큐로
          pcall(single_update, root, got)
        end
      end
      local by_root, order = {}, {}
      for p in pairs(saved) do
        local root = root_of(p)
        if root and root ~= '' then
          if not by_root[root] then
            by_root[root] = {}
            order[#order + 1] = root
          end
          table.insert(by_root[root], p)
        end
      end
      for _, root in ipairs(order) do
        pcall(take, root, by_root[root])
      end
    end, delay)
  end,
  desc = '새 파일을 저장하면 목록에 넣고 그것만 색인 (g:projectfiles_index_new_on_save)',
})

-- a preset is applied as soon as the session knows which project it is in
-- as early as possible (the indexer may start on the first BufReadPost),
-- and again once the session is up and the real project is known
--
-- 플러그인을 읽는 동안에는 목록을 펴지 않는다 (P3). 예전에는 여기서 목록 전체를
-- 동기로 다시 폈다 - 바이너리 판정 캐시가 비어 있으니 목록의 모든 파일을 열어
-- 앞 1KB 를 읽었고, 6,600개짜리 preset 에서 첫 화면이 0.5~1초(느린 stat 을
-- 흉내 내면 3~4초) 늦게 떴다. 지난번 목록이 있으면 그것을 그대로 쓰고(adopt),
-- VimEnter 뒤에 받아 두고 뒤에서 한 번 확인한다 (verify_async). 목록이 아예
-- 없을 때만 여기서 만든다 - gutentags 가 첫 BufReadPost 에서 그것을 읽고,
-- 없으면 git ls-files 로 트리 전체를 ctags 한다.
--
-- 이때 나는 알림('색인 제외: 바이너리 1', 하위 프로젝트 거르기)은 모아 두었다가
-- 화면이 뜬 뒤 한 줄로 낸다 (F6). 바로 내면 곧이어 autoindex 의 'indexing …'
-- 이 쌓여 첫 화면에 Press ENTER 가 떴고, 그게 떠 있는 동안 nvim 은 예약된
-- 콜백을 하나도 돌리지 않는다 - 0.1초면 끝난 첫 gtags 빌드가 DB 를 옮기고 락을
-- 푸는 마무리가 키를 누를 때까지(실측 10초 넘게) 멈췄다.
pcall(function()
  local root = root_of(nil)
  if active_preset(root) and not uv.fs_stat(list_path(root)) then
    s.collect = {}
    pcall(materialize, root)
    local msgs = s.collect
    s.collect = nil
    if #msgs == 0 then
      return
    end
    local function tell()
      local parts, lvl = {}, vim.log.levels.INFO
      for _, m in ipairs(msgs) do
        parts[#parts + 1] = m.msg
        lvl = math.max(lvl, m.level)
      end
      notify(table.concat(parts, '  |  '), lvl)
    end
    if vim.v.vim_did_enter == 1 then
      vim.schedule(tell)
    else
      api.nvim_create_autocmd('VimEnter', { group = group, once = true,
        callback = function() vim.schedule(tell) end })
    end
  end
end)

api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    vim.defer_fn(function()
      -- 받아 두고(같은 preset 의 목록) 뒤에서 확인한다. autoindex 의 시작
      -- 갱신도 곧 같은 것을 부르지만, autoindex 가 꺼져 있어도 목록이 세션마다
      -- 한 번은 새로워지게 여기서도 부른다 (두 번째는 바로 돌아간다, C1).
      -- 다른 프로젝트로 판명됐거나 목록이 없으면 이것이 목록을 만든다.
      local root = cur_root()
      if active_preset(root) then
        pcall(_G.projectfiles_materialize, root)
      end
    end, 200)
  end,
})
