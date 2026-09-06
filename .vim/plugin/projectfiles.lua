-- projectfiles.lua - decide WHICH files get indexed, and show them.
--
-- Two modes:
--   auto    the whole project, the way indexfiles.sh sees it (git ls-files,
--           cscope.files, find). This is what happens with no preset.
--   preset  only the files and directories of a named preset. A preset is a
--           list of project-relative paths, so the same preset can be reused
--           in another checkout: entries that do not exist there are skipped.
--
-- The list is materialised as '<root>/.tags/files', which indexfiles.sh reads
-- before anything else, so gtags (autoindex.lua) and ctags (gutentags) both
-- index exactly the files in the view - and adding or removing one reindexes
-- straight away.
--
-- Commands
--   :ProjectFiles              toggle the view (right column, above the
--                              context preview)
--   :ProjectFilesAdd [path]    add a file or directory (default: this buffer)
--   :ProjectFilesRemove [path] remove one
--   :ProjectFilesPreset [name] switch to a preset ('' = auto mode); no
--                              argument lists what there is
--   :ProjectFilesSave <name>   save the current entries as a preset
--   :ProjectFilesReindex       rebuild the index for the current list
--
-- In the view
--   <CR> open the file      a add path      d remove entry under the cursor
--   p    pick a preset      s save preset   m auto/preset      r reindex
--   q    close
--
-- Options (.vimrc)
--   g:projectfiles_preset      preset to use when a project has none yet
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

local function preset_path(name)
  return presets_dir() .. '/' .. name:gsub('[^%w%-_.]', '_') .. '.json'
end

local function preset_list()
  local out = {}
  for _, f in ipairs(vim.fn.glob(presets_dir() .. '/*.json', false, true)) do
    out[#out + 1] = vim.fn.fnamemodify(f, ':t:r')
  end
  table.sort(out)
  return out
end

local function preset_read(name)
  local f = preset_path(name)
  if not uv.fs_stat(f) then
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

local function preset_write(name, entries)
  local f = preset_path(name)
  local data = vim.json.encode({ name = name, entries = entries })
  pcall(vim.fn.writefile, vim.split(data, '\n'), f)
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
  preset_write(name, entries)
  local files = materialize(root)
  reindex(root)
  return files
end

local function add_path(root, path)
  local entries, name = entries_of(root)
  if not name then
    -- auto mode: adding a path means "start a preset here"
    name = tostring(cfg('preset', 'default'))
    entries = {}
    set_active(root, name)
    notify("auto -> preset '" .. name .. "'")
  end
  local abs = vim.fn.fnamemodify(path, ':p'):gsub('/+$', '')
  local st = uv.fs_stat(abs)
  if not st then
    notify('없는 경로: ' .. path, vim.log.levels.WARN)
    return
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
  local abs = vim.fn.fnamemodify(path, ':p'):gsub('/+$', '')
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
-- the view
-- ---------------------------------------------------------------------------
local function visible()
  return s.win ~= nil and api.nvim_win_is_valid(s.win)
      and api.nvim_win_get_buf(s.win) == s.buf
end

-- relationview asks for this so its context preview lands BELOW the view
function _G.projectfiles_win()
  return visible() and s.win or nil
end

local function ensure_buf()
  if s.buf and api.nvim_buf_is_valid(s.buf) then
    return s.buf
  end
  local buf = api.nvim_create_buf(false, true)
  pcall(api.nvim_buf_set_name, buf, 'ProjectFiles')
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'projectfiles'
  s.buf = buf
  return buf
end

local render -- forward
local open    -- forward

local function row_here()
  if not visible() then
    return nil
  end
  return s.rows[api.nvim_win_get_cursor(s.win)[1]]
end

local function src_win()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    local n = api.nvim_buf_get_name(b)
    if vim.bo[b].buftype == '' and w ~= s.win
        and not n:match('RelationView') then
      return w
    end
  end
  return nil
end

local A = {}

function A.open_file()
  local r = row_here()
  if not (r and r.path) then
    return
  end
  local root = cur_root()
  local abs = r.path:sub(1, 1) == '/' and r.path or (root .. '/' .. r.path)
  local w = src_win()
  if not w then
    notify('열 편집 창이 없습니다', vim.log.levels.WARN)
    return
  end
  local buf = vim.fn.bufadd(abs)
  vim.bo[buf].buflisted = true
  api.nvim_win_set_buf(w, buf)
  api.nvim_set_current_win(w)
end

function A.add()
  local root = cur_root()
  local cur = api.nvim_buf_get_name(0)
  local def = (cur ~= '' and vim.bo.buftype == '') and rel_to(root, cur) or ''
  vim.ui.input({ prompt = '추가할 파일/디렉터리: ', default = def,
    completion = 'file' }, function(input)
    if input and input ~= '' then
      add_path(root, input)
      render()
    end
  end)
end

function A.remove()
  local r = row_here()
  local root = cur_root()
  if r and r.entry then
    remove_path(root, r.entry.path)
  elseif r and r.path then
    remove_path(root, r.path)
  else
    return
  end
  render()
end

function A.preset()
  local root = cur_root()
  local names = preset_list()
  local items = { '(auto - 프로젝트 전체)' }
  vim.list_extend(items, names)
  vim.ui.select(items, { prompt = 'preset 선택' }, function(choice, idx)
    if not choice then
      return
    end
    set_active(root, idx == 1 and '' or names[idx - 1])
    materialize(root)
    reindex(root)
    render()
    notify(idx == 1 and 'auto 모드' or ("preset '" .. names[idx - 1] .. "'"))
  end)
end

function A.save()
  local root = cur_root()
  local entries = entries_of(root)
  if not entries or #entries == 0 then
    notify('저장할 항목이 없습니다 (a 로 추가하세요)', vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = '이 목록을 저장할 preset 이름: ',
    default = active_preset(root) or 'default' }, function(name)
    if not name or name == '' then
      return
    end
    preset_write(name, entries)
    set_active(root, name)
    materialize(root)
    render()
    notify("preset '" .. name .. "' 저장")
  end)
end

function A.mode()
  local root = cur_root()
  if active_preset(root) then
    set_active(root, '')
    notify('auto 모드 (프로젝트 전체 색인)')
  else
    local names = preset_list()
    set_active(root, names[1] or tostring(cfg('preset', 'default')))
    notify("preset '" .. (names[1] or tostring(cfg('preset', 'default'))) .. "'")
  end
  materialize(root)
  reindex(root)
  render()
end

function A.reindex()
  local root = cur_root()
  materialize(root)
  reindex(root)
  render()
  notify('재색인 시작')
end

function A.close()
  if visible() then
    local w = s.win
    with_panel_height(function() api.nvim_win_close(w, false) end)
  end
  s.win = nil
end

local function map_keys(buf)
  local function m(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  m('<CR>', A.open_file, 'ProjectFiles: open')
  m('<2-LeftMouse>', A.open_file, 'ProjectFiles: open')
  m('a', A.add, 'ProjectFiles: add path')
  m('d', A.remove, 'ProjectFiles: remove entry')
  m('x', A.remove, 'ProjectFiles: remove entry')
  m('p', A.preset, 'ProjectFiles: pick preset')
  m('s', A.save, 'ProjectFiles: save preset')
  m('m', A.mode, 'ProjectFiles: auto/preset')
  m('r', A.reindex, 'ProjectFiles: reindex')
  m('q', A.close, 'ProjectFiles: close')
end

render = function()
  if not visible() then
    return
  end
  local root = cur_root()
  local entries, name = entries_of(root)
  local cached = s.cache[root]
  local files = cached and cached.files
  if entries and not files then
    files = materialize(root)
  end
  local lines, rows = {}, {}
  local short = vim.fn.fnamemodify(root, ':~')
  lines[1] = string.format('◆ %s  [%s]', short,
    name and ('preset: ' .. name) or 'auto')
  lines[2] = '  [⏎]open [a]dd [d]rop [p]reset [s]ave [m]ode [r]eindex [q]close'
  lines[3] = ''
  if entries then
    lines[#lines + 1] = string.format('── Entries (%d) ──', #entries)
    for _, e in ipairs(entries) do
      lines[#lines + 1] = string.format('  %-4s %s', e.kind, e.path)
      rows[#lines] = { entry = e, path = e.path }
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = string.format('── Files (%d) ──', files and #files or 0)
    for _, f in ipairs(files or {}) do
      lines[#lines + 1] = '  ' .. f
      rows[#lines] = { path = f }
    end
  else
    lines[#lines + 1] = '── Files ──'
    lines[#lines + 1] = '  auto 모드: 이 프로젝트 전체를 색인합니다'
    lines[#lines + 1] = '  (a 로 파일/디렉터리를 추가하면 preset 모드로 바뀝니다)'
  end
  s.rows = rows
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
end

-- A window with 'winfixheight' will not give rows to a new neighbour: nvim
-- grows the whole column instead and takes the rows from the relation panel
-- at the bottom. So relax the preview while splitting it, and put the
-- panel's height back if it moved anyway.
local function with_panel_height(fn)
  local panel = _G.relationview_panel_win and _G.relationview_panel_win() or nil
  local h = panel and api.nvim_win_is_valid(panel)
      and api.nvim_win_get_height(panel) or nil
  fn()
  if panel and h and api.nvim_win_is_valid(panel)
      and api.nvim_win_get_height(panel) ~= h then
    pcall(api.nvim_win_set_height, panel, h)
  end
end

open = function()
  if visible() then
    return s.win
  end
  local buf = ensure_buf()
  local ctx = _G.relationview_ctx_win and _G.relationview_ctx_win() or nil
  local win
  if ctx and api.nvim_win_is_valid(ctx) then
    -- the view belongs above the context preview, in the same column
    local fixed = vim.wo[ctx].winfixheight
    vim.wo[ctx].winfixheight = false
    with_panel_height(function()
      api.nvim_win_call(ctx, function()
        vim.cmd('noautocmd aboveleft split')
        win = api.nvim_get_current_win()
        pcall(vim.cmd, 'resize ' .. (tonumber(cfg('height', 12)) or 12))
      end)
    end)
    if api.nvim_win_is_valid(ctx) then
      vim.wo[ctx].winfixheight = fixed
    end
  else
    local host = src_win()
    if not host then
      notify('창을 만들 자리가 없습니다', vim.log.levels.WARN)
      return nil
    end
    local w = cfg('width', vim.g.relationview_context_width or 0)
    w = tonumber(w) or 0
    if w <= 0 then
      w = math.max(40, math.floor(vim.o.columns / 4))
    end
    local hw = api.nvim_win_get_width(host)
    w = math.min(w, math.max(20, math.floor(hw / 2)))
    with_panel_height(function()
      api.nvim_win_call(host, function()
        vim.cmd('noautocmd rightbelow vertical split')
        vim.cmd('vertical resize ' .. w)
        win = api.nvim_get_current_win()
      end)
    end)
  end
  if not (win and api.nvim_win_is_valid(win)) then
    return nil
  end
  api.nvim_win_set_buf(win, buf)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.wrap = false
  wo.cursorline = true
  wo.signcolumn = 'no'
  wo.foldcolumn = '0'
  wo.winfixheight = true
  wo.winfixwidth = true
  wo.winhighlight = 'CursorLine:RvCursorLine,CursorLineNr:RvCursorLineNr'
  s.win = win
  map_keys(buf)
  render()
  return win
end

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------
api.nvim_create_user_command('ProjectFiles', function()
  if visible() then
    A.close()
  else
    open()
  end
end, { desc = 'Toggle the project files view' })

api.nvim_create_user_command('ProjectFilesAdd', function(o)
  local root = cur_root()
  local p = o.args ~= '' and o.args or api.nvim_buf_get_name(0)
  if p == '' then
    notify('경로를 지정하세요', vim.log.levels.WARN)
    return
  end
  add_path(root, p)
  render()
end, { nargs = '?', complete = 'file', desc = 'Add a file/directory to the preset' })

api.nvim_create_user_command('ProjectFilesRemove', function(o)
  local root = cur_root()
  local p = o.args ~= '' and o.args or api.nvim_buf_get_name(0)
  remove_path(root, p)
  render()
end, { nargs = '?', complete = 'file', desc = 'Remove a file/directory from the preset' })

api.nvim_create_user_command('ProjectFilesPreset', function(o)
  local root = cur_root()
  if o.args == '' then
    local names = preset_list()
    notify('presets: ' .. (#names > 0 and table.concat(names, ', ') or '(없음)')
      .. '  |  현재: ' .. (active_preset(root) or 'auto'))
    return
  end
  set_active(root, o.args == 'auto' and '' or o.args)
  materialize(root)
  reindex(root)
  render()
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
    notify('이름이 필요합니다: :ProjectFilesSave <name>', vim.log.levels.WARN)
    return
  end
  preset_write(o.args, entries)
  set_active(root, o.args)
  materialize(root)
  render()
  notify("preset '" .. o.args .. "' 저장 (" .. #entries .. " entries)")
end, { nargs = '?', desc = 'Save the current entries as a named preset' })

api.nvim_create_user_command('ProjectFilesReindex', function()
  A.reindex()
end, { desc = 'Rebuild the index for the current file list' })

-- ---------------------------------------------------------------------------
-- keep the list live
-- ---------------------------------------------------------------------------
-- a preset is applied as soon as the session knows which project it is in
api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    vim.defer_fn(function()
      local root = cur_root()
      if active_preset(root) then
        materialize(root)
      end
    end, 400)
  end,
})

-- a file saved while the view is open may be new to the list
api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function()
    if visible() then
      vim.defer_fn(render, 200)
    end
  end,
})
