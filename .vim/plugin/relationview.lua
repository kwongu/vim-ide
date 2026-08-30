-- relationview.lua - Source Insight style "Relation Window" for nvim.
--
-- Shows Definition / Callers / Callees of the symbol under the cursor in
-- real time, backed by GNU Global (gtags) - the same GTAGS database that
-- F2 (mktags.sh) already creates for this vim-ide setup.
--
--   F3                  toggle the relation window (was "Empty")
--   :RelationView [sym] open the window and show relations of sym/<cword>
--   :RelationViewToggle same as F3
--
-- Inside the panel:
--   <Enter> jump to location   o  jump but keep focus in the panel
--   p  pin (freeze) current symbol                 r  refresh (drop cache)
--   a  toggle realtime auto-update                 q  close the panel
--
-- Options (set in .vimrc before this file is sourced, all optional):
--   g:relationview_position   'bottom' (default) or 'right'
--   g:relationview_height     panel height for 'bottom'  (default 12)
--   g:relationview_width      panel width  for 'right'   (default 60)
--   g:relationview_auto       1: update as the cursor moves (default 1)
--   g:relationview_debounce   idle debounce in ms         (default 250)
--   g:relationview_max_refs   max caller lines shown      (default 200)
--   g:relationview_global_cmd path of the global binary   (default auto)

if vim.g.loaded_relationview then
  return
end
vim.g.loaded_relationview = 1

if vim.fn.has('nvim-0.10') == 0 then
  return
end

local api = vim.api
local uv = vim.uv

-- ---------------------------------------------------------------------------
-- config / small helpers
-- ---------------------------------------------------------------------------

local function cfg(name, default)
  local v = vim.g['relationview_' .. name]
  if v == nil or v == '' then
    return default
  end
  return v
end

local function global_cmd()
  local c = cfg('global_cmd', nil)
  if c then
    return vim.fn.executable(c) == 1 and c or nil
  end
  if vim.fn.executable('global') == 1 then
    return 'global'
  end
  local fallback = vim.fn.expand('~/.local/bin/global')
  if vim.fn.executable(fallback) == 1 then
    return fallback
  end
  return nil
end

-- words that are never worth querying automatically
local KEYWORDS = {}
for w in ([[
  if else for while do switch case default break continue return goto sizeof
  typedef struct union enum static extern const volatile register unsigned
  signed int char short long float double void inline restrict auto bool
  true false NULL defined asm __asm__ __attribute__ likely unlikely
  new delete class namespace template typename public private protected
  virtual operator this using try catch throw nullptr constexpr noexcept
  override final static_cast dynamic_cast const_cast reinterpret_cast
  def pass None True False self elif not and or in is lambda import from
  u8 u16 u32 u64 s8 s16 s32 s64 uint8_t uint16_t uint32_t uint64_t
  int8_t int16_t int32_t int64_t size_t ssize_t
]]):gmatch('%S+') do
  KEYWORDS[w] = true
end

-- ubiquitous local-variable names: the expensive '-s' (undefined-symbol
-- reference) fallback is suppressed for these on the automatic cursor path
local COMMON_LOCALS = {}
for w in ('ret err len buf val tmp idx pos cnt num ptr str arg res out'):gmatch('%S+') do
  COMMON_LOCALS[w] = true
end

local function is_symbol(w, allow_keyword)
  if not w or w == '' then
    return false
  end
  if KEYWORDS[w] and not allow_keyword then
    return false
  end
  return w:match('^[%a_][%w_]*$') ~= nil
end

local function trunc(text, n)
  text = (text or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if #text > n then
    return text:sub(1, n - 1) .. '…'
  end
  return text
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

local s = {
  buf = nil,          -- panel buffer
  win = nil,          -- panel window
  src_win = nil,      -- window the last query came from
  sym = nil,          -- symbol currently displayed
  pinned = false,
  auto = cfg('auto', 1) ~= 0,
  gen = 0,            -- generation counter, stale async results are dropped
  timer = nil,        -- debounce timer
  locs = {},          -- panel line number -> {path=..., line=...}
  cache = {},         -- key -> {mtime=..., data=...}
  cache_n = 0,
  roots = {},         -- dir -> gtags root (positive results only)
  procs = {},         -- in-flight vim.system handles of the current query
  inflight = {},      -- filedefs key -> list of waiting callbacks
  warned = false,
}

local A = {}          -- panel actions (jump/close/pin/...), defined below

local function gtags_mtime(root)
  local st = uv.fs_stat(root .. '/GTAGS')
  return st and st.mtime.sec or -1
end

local function cache_get(key, mtime)
  local e = s.cache[key]
  if e and e.mtime == mtime then
    return e.data
  end
  return nil
end

local function cache_put(key, mtime, data)
  if s.cache_n > 500 then -- crude but effective bound
    s.cache = {}
    s.cache_n = 0
  end
  if not s.cache[key] then
    s.cache_n = s.cache_n + 1
  end
  s.cache[key] = { mtime = mtime, data = data }
end

-- kill every global process still running for the previous query
local function kill_procs()
  for _, p in ipairs(s.procs) do
    pcall(function() p:kill(15) end)
  end
  s.procs = {}
end

-- ---------------------------------------------------------------------------
-- global(1) runners (all async)
-- ---------------------------------------------------------------------------

-- Run global with args, call cb(lines) on success or cb(nil, err) on failure.
-- cap: stop reading (and kill the child) once more than cap lines arrived,
-- so a hot symbol on a kernel-scale database cannot buffer tens of MB.
local function run_global(args, cwd, cb, cap)
  local prog = global_cmd()
  if not prog then
    cb(nil, 'GNU Global(global) not found in $PATH')
    return
  end
  local full = { prog }
  vim.list_extend(full, args)

  local chunks, nlines, delivered = {}, 0, false
  local obj
  local function deliver(lines, err)
    if delivered then
      return
    end
    delivered = true
    cb(lines, err)
  end
  local function on_stdout(err, chunk)
    if err or not chunk then
      return
    end
    chunks[#chunks + 1] = chunk
    local _, c = chunk:gsub('\n', '')
    nlines = nlines + c
    if cap and nlines > cap and obj then
      pcall(function() obj:kill(15) end)
    end
  end

  local ok, ret = pcall(vim.system, full, { cwd = cwd, stdout = on_stdout },
    function(o)
      vim.schedule(function()
        local out = table.concat(chunks)
        local capped = cap ~= nil and nlines > cap
        if o.code ~= 0 and out == '' and not capped then
          deliver(nil, (o.stderr or ''):gsub('%s+$', ''))
          return
        end
        local lines = {}
        for l in out:gmatch('[^\n]+') do
          lines[#lines + 1] = l
          if cap and #lines > cap then
            break
          end
        end
        deliver(lines)
      end)
    end)
  if not ok then
    vim.schedule(function() deliver(nil, tostring(ret)) end)
    return
  end
  obj = ret
  s.procs[#s.procs + 1] = obj
end

-- '--result=ctags-mod' output: path<TAB>lineno<TAB>source-text
local function parse_ctags_mod(lines, max)
  local out = {}
  for _, l in ipairs(lines or {}) do
    if max and #out >= max then
      out.truncated = #lines - max
      break
    end
    local path, lno, text = l:match('^([^\t]+)\t(%d+)\t(.*)$')
    if path then
      out[#out + 1] = { path = path, line = tonumber(lno), text = text }
    end
  end
  return out
end

-- find the GTAGS project root for a directory (async; only positive results
-- are cached, so the panel recovers right after the user indexes with F2)
local function get_root(dir, cb)
  local hit = s.roots[dir]
  if hit then
    cb(hit)
    return
  end
  run_global({ '-p' }, dir, function(lines)
    local root = lines and lines[1] or ''
    if root ~= '' then
      s.roots[dir] = root
    end
    cb(root ~= '' and root or nil)
  end, 2)
end

-- definitions inside one file: 'global -f' -> { {name=..., line=...} ... }
-- (used to find the enclosing function of every reference); concurrent
-- requests for the same file share one process
local function get_filedefs(root, mtime, path, cb)
  local key = 'F\0' .. path
  local hit = cache_get(key, mtime)
  if hit then
    cb(hit)
    return
  end
  if s.inflight[key] then
    table.insert(s.inflight[key], cb)
    return
  end
  s.inflight[key] = { cb }
  run_global({ '-a', '-f', path }, root, function(lines)
    local defs = {}
    if lines then
      for _, l in ipairs(lines) do
        -- cxref format: name line path text (name/line are space-free)
        local name, lno = l:match('^(%S+)%s+(%d+)%s')
        if name then
          defs[#defs + 1] = { name = name, line = tonumber(lno) }
        end
      end
      table.sort(defs, function(a, b) return a.line < b.line end)
      cache_put(key, mtime, defs) -- do not cache on error/kill (lines == nil)
    end
    local waiters = s.inflight[key] or {}
    s.inflight[key] = nil
    for _, w in ipairs(waiters) do
      w(defs)
    end
  end, 4000)
end

local function enclosing(defs, line)
  local found = nil
  for _, d in ipairs(defs) do
    if d.line > line then
      break
    end
    found = d.name
  end
  return found
end

-- ---------------------------------------------------------------------------
-- callee extraction (treesitter first, brace scanning as fallback)
-- ---------------------------------------------------------------------------

local CALL_QUERY = '(call_expression function: (_) @fn)'

-- source is a buffer number or a content string
local function node_calls(lang, fnnode, source)
  local okq, query = pcall(vim.treesitter.query.parse, lang, CALL_QUERY)
  if not okq then
    return nil
  end
  local calls = {}
  for _, n in query:iter_captures(fnnode, source) do
    local ok, text = pcall(vim.treesitter.get_node_text, n, source)
    -- keep the trailing identifier: 'foo', 'obj->foo', 'ns::foo' -> 'foo'
    local name = ok and text:match('([%a_][%w_]*)%s*$') or nil
    if name and not KEYWORDS[name] then
      calls[#calls + 1] = { name = name, line = n:start() + 1 }
    end
  end
  return calls
end

local function fn_node_at(root_node, defline)
  local row = defline - 1
  local node = root_node:named_descendant_for_range(row, 0, row, 0)
  while node and node:type() ~= 'function_definition' do
    node = node:parent()
  end
  return node
end

-- reuse the incrementally-updated tree of an already-loaded buffer:
-- no file io, no from-scratch parse
local function ts_callees_buf(bufnr, defline)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end
  local okp, trees = pcall(function() return parser:parse() end)
  if not okp or not trees or not trees[1] then
    return nil
  end
  local node = fn_node_at(trees[1]:root(), defline)
  if not node then
    return nil
  end
  return node_calls(parser:lang(), node, bufnr)
end

local function ts_callees_str(content, path, defline)
  local ft = vim.filetype.match({ filename = path })
  if not ft then
    return nil
  end
  local lang = vim.treesitter.language.get_lang(ft) or ft
  local ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
  if not ok or not parser then
    return nil
  end
  local okp, trees = pcall(function() return parser:parse() end)
  if not okp or not trees or not trees[1] then
    return nil
  end
  local node = fn_node_at(trees[1]:root(), defline)
  if not node then
    return nil
  end
  return node_calls(lang, node, content)
end

local function brace_callees(lines, defline)
  local calls = {}
  local depth, started = 0, false
  local i = defline
  while i <= #lines and i < defline + 4000 do
    local code = lines[i]:gsub('//.*$', '')
    if started or code:find('{', 1, true) then
      for name in code:gmatch('([%a_][%w_]*)%s*%(') do
        if not KEYWORDS[name] then
          calls[#calls + 1] = { name = name, line = i }
        end
      end
    end
    local opens = select(2, code:gsub('{', ''))
    local closes = select(2, code:gsub('}', ''))
    if not started then
      if opens > 0 then
        started = true
        depth = opens - closes
        -- drop identifiers picked up from the signature line itself
        if i == defline then
          calls = {}
        end
      elseif code:find(';') then
        return {} -- prototype, not a definition
      end
    else
      depth = depth + opens - closes
    end
    if started and depth <= 0 then
      break
    end
    i = i + 1
  end
  return calls
end

local MAX_TS_FILE = 1 * 1024 * 1024   -- string-parse cutoff for unloaded files
local MAX_READ_FILE = 8 * 1024 * 1024 -- absolute read cutoff

-- returns (ordered unique { name=..., line=<first call site> }, note);
-- results are cached per (path, defline) keyed by the file's own mtime
local function extract_callees(path, defline)
  local st = uv.fs_stat(path)
  if not st then
    return nil, '(cannot read file)'
  end
  local key = 'C\0' .. path .. '\0' .. defline
  local hit = cache_get(key, st.mtime.sec)
  if hit then
    return hit.calls, hit.note
  end

  local calls
  local bufnr = -1
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and api.nvim_buf_get_name(b) == path then
      bufnr = b
      break
    end
  end

  if bufnr ~= -1 then
    calls = ts_callees_buf(bufnr, defline)
    if not calls or #calls == 0 then
      calls = brace_callees(api.nvim_buf_get_lines(bufnr, 0, -1, false), defline)
    end
  else
    if st.size > MAX_READ_FILE then
      return nil, '(file too large)'
    end
    local f = io.open(path, 'r')
    if not f then
      return nil, '(cannot read file)'
    end
    local content = f:read('*a')
    f:close()
    if st.size <= MAX_TS_FILE then
      calls = ts_callees_str(content, path, defline)
    end
    if not calls or #calls == 0 then
      calls = brace_callees(vim.split(content, '\n', { plain = true }), defline)
    end
  end

  local seen, out = {}, {}
  for _, c in ipairs(calls or {}) do
    if not seen[c.name] then
      seen[c.name] = true
      out[#out + 1] = c
    end
  end
  cache_put(key, st.mtime.sec, { calls = out })
  return out, nil
end

-- Resolve callee names to their definitions with one exact (indexed) lookup
-- per name through a small worker pool. Exact lookups hit Global's B-tree
-- index (milliseconds regardless of DB size) whereas a '^(a|b|...)$' regex
-- forces a full key scan, and each result is keyed by the queried name so
-- attribution can never be wrong. Results are cached per (root, name).
local function resolve_callees(root, mtime, names, cb)
  local resolved = {}
  local idx, active = 0, 0
  local CONC = 6
  local launch
  launch = function()
    while active < CONC and idx < #names do
      idx = idx + 1
      local name = names[idx]
      local key = 'D\0' .. root .. '\0' .. name
      local hit = cache_get(key, mtime)
      if hit ~= nil then
        if hit.path then
          resolved[name] = hit
        end
      else
        active = active + 1
        run_global({ '--result=ctags-mod', '-a', '-d', name }, root,
          function(lines)
            if lines then
              local d = parse_ctags_mod(lines, 2)[1] or {} -- {} = external
              cache_put(key, mtime, d)
              if d.path then
                resolved[name] = d
              end
            end
            active = active - 1
            launch()
          end, 4)
      end
    end
    if active == 0 and idx >= #names then
      cb(resolved)
    end
  end
  launch()
end

-- ---------------------------------------------------------------------------
-- panel window / rendering
-- ---------------------------------------------------------------------------

local function ensure_buf()
  if s.buf and api.nvim_buf_is_valid(s.buf) then
    return s.buf
  end
  local buf = api.nvim_create_buf(false, true)
  pcall(api.nvim_buf_set_name, buf, 'RelationView')
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'relationview'

  api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax match RvHeader   /^◆.*/
      syntax match RvHint     /^  \[.*\]$/
      syntax match RvSection  /^──.*/
      syntax match RvName     /^  \zs[^ │]\+/
      syntax match RvLoc      /[^ │]\+:\d\+/
      syntax match RvDim      /(external)\|(no definition)\|(none)\|(file too large)/
    ]])
  end)
  api.nvim_set_hl(0, 'RvHeader', { link = 'Title', default = true })
  api.nvim_set_hl(0, 'RvHint', { link = 'Comment', default = true })
  api.nvim_set_hl(0, 'RvSection', { link = 'Label', default = true })
  api.nvim_set_hl(0, 'RvName', { link = 'Function', default = true })
  api.nvim_set_hl(0, 'RvLoc', { link = 'Directory', default = true })
  api.nvim_set_hl(0, 'RvDim', { link = 'Comment', default = true })

  local function bmap(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  bmap('<CR>', function() A.jump(false) end, 'RelationView: jump')
  bmap('o', function() A.jump(true) end, 'RelationView: peek')
  bmap('q', function() A.close() end, 'RelationView: close')
  bmap('p', function() A.pin() end, 'RelationView: pin/unpin')
  bmap('r', function() A.refresh() end, 'RelationView: refresh')
  bmap('a', function() A.toggle_auto() end, 'RelationView: toggle auto')

  s.buf = buf
  return buf
end

local function panel_visible()
  return s.win ~= nil and api.nvim_win_is_valid(s.win)
      and api.nvim_win_get_tabpage(s.win) == api.nvim_get_current_tabpage()
end

-- find a window in the current tabpage already showing the panel buffer
local function panel_win_here()
  if not (s.buf and api.nvim_buf_is_valid(s.buf)) then
    return nil
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(w) == s.buf then
      return w
    end
  end
  return nil
end

local function panel_open()
  if panel_visible() then
    return s.win
  end
  local buf = ensure_buf()
  local existing = panel_win_here()
  if existing then
    s.win = existing
    return existing
  end
  local prev = api.nvim_get_current_win()
  if cfg('position', 'bottom') == 'right' then
    vim.cmd('keepalt botright vertical ' .. cfg('width', 60) .. 'split')
  else
    vim.cmd('keepalt botright ' .. cfg('height', 12) .. 'split')
  end
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.list = false
  wo.wrap = false
  wo.signcolumn = 'no'
  wo.foldenable = false
  wo.spell = false
  wo.cursorline = true
  wo.colorcolumn = ''
  wo.winfixheight = true
  wo.winfixwidth = true
  pcall(function() wo.winfixbuf = true end)
  s.win = win
  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      if s.win == win then
        s.win = nil
      end
    end,
  })
  if api.nvim_win_is_valid(prev) then
    api.nvim_set_current_win(prev)
  end
  return win
end

local function render(lines, locs)
  local buf = ensure_buf()
  s.locs = locs or {}
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if s.win and api.nvim_win_is_valid(s.win) then
    -- self-heal: global buffer-cycle maps (,r ,e ,w ...) can swap the
    -- panel window to another buffer; take the window back
    if api.nvim_win_get_buf(s.win) ~= buf then
      pcall(function()
        vim.wo[s.win].winfixbuf = false
        api.nvim_win_set_buf(s.win, buf)
        vim.wo[s.win].winfixbuf = true
      end)
    end
    if api.nvim_win_get_buf(s.win) == buf then
      local pos = api.nvim_win_get_cursor(s.win)
      if pos[1] > #lines then
        api.nvim_win_set_cursor(s.win, { math.max(1, #lines), 0 })
      end
    end
  end
end

local function header(sym, note)
  local flags = {}
  if s.pinned then flags[#flags + 1] = 'PINNED' end
  if not s.auto then flags[#flags + 1] = 'auto:off' end
  local tail = #flags > 0 and ('  [' .. table.concat(flags, ', ') .. ']') or ''
  return {
    '◆ ' .. (sym or '(none)') .. tail .. (note and ('  — ' .. note) or ''),
    '  [Enter]jump  [o]peek  [p]pin  [r]refresh  [a]auto  [q]close  [F3]toggle',
  }
end

-- rewrite only the two header lines (pin/auto flags changed)
local function update_header()
  if not (s.buf and api.nvim_buf_is_valid(s.buf)) then
    return
  end
  local n = api.nvim_buf_line_count(s.buf)
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, math.min(2, n), false, header(s.sym))
  vim.bo[s.buf].modifiable = false
end

local function render_msg(sym, msg)
  local lines = header(sym)
  lines[#lines + 1] = ''
  lines[#lines + 1] = '  ' .. msg
  render(lines, {})
end

local function section_line(title, n)
  local label = n ~= nil and string.format('%s (%d)', title, n) or title
  -- note: '─' is multibyte, always build the bar with rep(), never sub()
  local w = math.max(4, 50 - vim.fn.strwidth(label))
  return '── ' .. label .. ' ' .. string.rep('─', w)
end

local function fmt_name(name)
  if #name <= 22 then
    return name .. string.rep(' ', 22 - #name)
  end
  return name
end

-- data = { def = {..}|nil, refs = { {path,line,text,fn=} }, refs_kind,
--          refs_truncated, callees = { {name,path,line,text,external,site} },
--          callees_note }
local function render_data(sym, root, data)
  local lines = header(sym)
  local locs = {}
  local function rel(p)
    if p:sub(1, #root + 1) == root .. '/' then
      return p:sub(#root + 2)
    end
    return p
  end
  local function add(text, loc)
    lines[#lines + 1] = text
    if loc then
      locs[#lines] = loc
    end
  end

  add('')
  add(section_line('Definition'))
  if data.def then
    local d = data.def
    add(string.format('  %s:%d │ %s', rel(d.path), d.line, trunc(d.text, 90)),
      { path = d.path, line = d.line })
  else
    add('  (no definition)')
  end

  local title = data.refs_kind == 'symbol'
      and 'References (undefined symbol)' or 'Callers / References'
  add('')
  add(section_line(title, #data.refs))
  if #data.refs == 0 then
    add('  (none)')
  end
  for _, r in ipairs(data.refs) do
    add(string.format('  %s %s:%d │ %s',
        fmt_name(r.fn or '─'), rel(r.path), r.line, trunc(r.text, 80)),
      { path = r.path, line = r.line })
  end
  if data.refs_truncated and data.refs_truncated > 0 then
    -- lower bound: the query is capped, the real total may be larger
    add(string.format('  … %d+ more  (:Gtags -r %s)', data.refs_truncated, sym))
  end

  add('')
  add(section_line('Callees', data.callees and #data.callees or nil))
  if not data.callees or #data.callees == 0 then
    add('  ' .. (data.callees_note or '(none)'))
  else
    for _, c in ipairs(data.callees) do
      if c.external then
        add(string.format('  %s (external)  call @ %s:%d',
            fmt_name(c.name), rel(c.site.path), c.site.line),
          { path = c.site.path, line = c.site.line })
      else
        add(string.format('  %s %s:%d │ %s',
            fmt_name(c.name), rel(c.path), c.line, trunc(c.text, 80)),
          { path = c.path, line = c.line })
      end
    end
  end
  render(lines, locs)
end

-- ---------------------------------------------------------------------------
-- query pipeline
-- ---------------------------------------------------------------------------

local MAX_ENCLOSE_FILES = 40
local ENCLOSE_CONC = 5

-- mtime is the GTAGS mtime captured when the query STARTED: if the database
-- was rebuilt mid-query the result may mix old and new data, so render it
-- but never cache it
local function finish(gen, sym, root, mtime, data)
  if gen ~= s.gen then
    return
  end
  if gtags_mtime(root) == mtime then
    cache_put('S\0' .. sym .. '\0' .. root, mtime, data)
  end
  render_data(sym, root, data)
end

-- annotate refs with their enclosing function through a small worker pool,
-- then finish
local function annotate_refs(gen, sym, root, mtime, data)
  local seen, order = {}, {}
  for _, r in ipairs(data.refs) do
    if not seen[r.path] then
      seen[r.path] = true
      order[#order + 1] = r.path
    end
  end
  local n = math.min(#order, MAX_ENCLOSE_FILES)
  if n == 0 then
    finish(gen, sym, root, mtime, data)
    return
  end
  local idx, active = 0, 0
  local launch
  launch = function()
    if gen ~= s.gen then
      return -- stale generation: stop dispatching, drop silently
    end
    while active < ENCLOSE_CONC and idx < n do
      idx = idx + 1
      local path = order[idx]
      active = active + 1
      get_filedefs(root, mtime, path, function(defs)
        for _, r in ipairs(data.refs) do
          if r.path == path then
            r.fn = enclosing(defs, r.line)
          end
        end
        active = active - 1
        if active == 0 and idx >= n then
          finish(gen, sym, root, mtime, data)
        else
          launch()
        end
      end)
    end
  end
  launch()
end

local function gather_callees(gen, sym, root, mtime, data, then_)
  if not data.def then
    then_()
    return
  end
  local calls, note = extract_callees(data.def.path, data.def.line)
  if note then
    data.callees_note = note
  end
  if not calls or #calls == 0 then
    then_()
    return
  end
  if #calls > 120 then
    local t = {}
    for i = 1, 120 do t[i] = calls[i] end
    calls = t
  end
  local names = {}
  for _, c in ipairs(calls) do
    names[#names + 1] = c.name
  end
  resolve_callees(root, mtime, names, function(resolved)
    if gen ~= s.gen then
      return
    end
    local out = {}
    for _, c in ipairs(calls) do
      local d = resolved[c.name]
      if d then
        out[#out + 1] = { name = c.name, path = d.path, line = d.line,
          text = d.text }
      elseif c.name ~= sym then
        out[#out + 1] = { name = c.name, external = true,
          site = { path = data.def.path, line = c.line } }
      end
    end
    data.callees = out
    then_()
  end)
end

-- manual: explicit request (:RelationView / 'r'), relaxes the guards that
-- keep the automatic cursor path cheap
local function update(sym, srcfile, force, manual)
  s.sym = sym
  s.gen = s.gen + 1
  kill_procs()
  local gen = s.gen
  local dir = vim.fs.dirname(srcfile)

  if not global_cmd() then
    if not s.warned then
      s.warned = true
      vim.notify('RelationView: GNU Global(global)을 찾을 수 없습니다.',
        vim.log.levels.WARN)
    end
    render_msg(sym, 'GNU Global(global) not found in $PATH')
    return
  end

  get_root(dir, function(root)
    if gen ~= s.gen then
      return
    end
    if not root then
      render_msg(sym, 'GTAGS not found — press F2 (mktags.sh) to index '
        .. 'this project first.  dir: ' .. dir)
      return
    end
    local mtime = gtags_mtime(root)
    if mtime == -1 then
      -- GTAGS was deleted after the root was cached (F12/Deltags)
      s.roots[dir] = nil
      render_msg(sym, 'GTAGS was removed — press F2 (mktags.sh) to re-index. '
        .. ' root: ' .. root)
      return
    end
    if not force then
      local hit = cache_get('S\0' .. sym .. '\0' .. root, mtime)
      if hit then
        render_data(sym, root, hit)
        return
      end
    end
    render_msg(sym, 'querying gtags …')

    local max_refs = cfg('max_refs', 200)
    local data = { refs = {}, refs_kind = 'ref' }
    local pending = 2

    local function join()
      pending = pending - 1
      if pending > 0 or gen ~= s.gen then
        return
      end
      local function resolve_rest()
        gather_callees(gen, sym, root, mtime, data, function()
          if gen ~= s.gen then
            return
          end
          annotate_refs(gen, sym, root, mtime, data)
        end)
      end
      -- undefined symbol: fall back to '-s' references. This can scan a
      -- huge GRTAGS, so the automatic cursor path only does it for longer,
      -- non-generic names; an explicit :RelationView always may.
      local want_s = not data.def and #data.refs == 0
          and (manual and #sym >= 3
            or (#sym >= 5 and not COMMON_LOCALS[sym]))
      if want_s then
        run_global({ '--result=ctags-mod', '-a', '-s', '-e', sym }, root,
          function(lines)
            if gen ~= s.gen then
              return
            end
            local refs = parse_ctags_mod(lines, max_refs)
            data.refs, data.refs_kind = refs, 'symbol'
            data.refs_truncated = refs.truncated
            resolve_rest()
          end, max_refs + 200)
      else
        resolve_rest()
      end
    end

    run_global({ '--result=ctags-mod', '-a', '-d', '-e', sym }, root,
      function(lines)
        if gen ~= s.gen then
          return
        end
        data.def = parse_ctags_mod(lines, 8)[1]
        join()
      end, 16)
    run_global({ '--result=ctags-mod', '-a', '-r', '-e', sym }, root,
      function(lines)
        if gen ~= s.gen then
          return
        end
        local refs = parse_ctags_mod(lines, max_refs)
        data.refs = refs
        data.refs_truncated = refs.truncated
        join()
      end, max_refs + 200)
  end)
end

-- ---------------------------------------------------------------------------
-- panel actions
-- ---------------------------------------------------------------------------

local function pick_src_win()
  if s.src_win and api.nvim_win_is_valid(s.src_win)
      and api.nvim_win_get_tabpage(s.src_win) == api.nvim_get_current_tabpage()
  then
    return s.src_win
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == '' and b ~= s.buf then
      return w
    end
  end
  return nil
end

function A.jump(peek)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local loc = s.locs[lnum]
  if not loc then
    return
  end
  local win = pick_src_win()
  if not win then
    vim.notify('RelationView: no source window to jump in', vim.log.levels.WARN)
    return
  end
  local buf = vim.fn.bufadd(loc.path)
  vim.bo[buf].buflisted = true
  api.nvim_win_call(win, function()
    pcall(vim.cmd, [[normal! m']])
  end)
  api.nvim_win_set_buf(win, buf)
  api.nvim_win_call(win, function()
    pcall(api.nvim_win_set_cursor, win, { loc.line, 0 })
    vim.cmd('normal! zz')
  end)
  if not peek then
    api.nvim_set_current_win(win)
  end
end

-- close the panel window of the CURRENT tabpage (panels may exist per tab)
function A.close()
  local target = nil
  local cur = api.nvim_get_current_win()
  if s.buf and api.nvim_win_get_buf(cur) == s.buf then
    target = cur
  else
    target = panel_win_here()
  end
  if target and api.nvim_win_is_valid(target) then
    api.nvim_win_close(target, false)
  end
  if s.win == target or (s.win and not api.nvim_win_is_valid(s.win)) then
    s.win = nil
  end
  if s.timer then
    s.timer:stop()
  end
  kill_procs()
end

function A.pin()
  s.pinned = not s.pinned
  update_header()
end

function A.refresh()
  s.roots = {} -- a new GTAGS may have appeared since (F2)
  if not s.sym then
    return
  end
  local win = pick_src_win()
  if not win then
    return
  end
  s.src_win = win
  local file = api.nvim_buf_get_name(api.nvim_win_get_buf(win))
  if file ~= '' then
    update(s.sym, file, true, true)
  end
end

function A.toggle_auto()
  s.auto = not s.auto
  update_header()
end

-- ---------------------------------------------------------------------------
-- realtime trigger + commands + default mapping
-- ---------------------------------------------------------------------------

local function on_hold()
  if not s.auto or s.pinned or not panel_visible() then
    return
  end
  local buf = api.nvim_get_current_buf()
  if buf == s.buf or vim.bo[buf].buftype ~= '' then
    return
  end
  local file = api.nvim_buf_get_name(buf)
  if file == '' then
    return
  end
  local sym = vim.fn.expand('<cword>')
  if not is_symbol(sym) or sym == s.sym then
    return
  end
  if not s.timer then
    s.timer = uv.new_timer()
  end
  s.timer:stop()
  local win = api.nvim_get_current_win()
  s.timer:start(cfg('debounce', 250), 0, vim.schedule_wrap(function()
    -- re-check: the cursor may have moved on
    if not panel_visible() or api.nvim_get_current_win() ~= win then
      return
    end
    local now = vim.fn.expand('<cword>')
    if now ~= sym or not is_symbol(now) then
      return
    end
    s.src_win = win
    update(sym, file, false, false)
  end))
end

local group = api.nvim_create_augroup('RelationView', { clear = true })
api.nvim_create_autocmd('CursorHold', { group = group, callback = on_hold })

local function open_and_query(arg)
  panel_open()
  local buf = api.nvim_get_current_buf()
  local sym = (arg and arg ~= '') and arg or vim.fn.expand('<cword>')
  local file = api.nvim_buf_get_name(buf)
  local explicit = arg ~= nil and arg ~= ''
  if vim.bo[buf].buftype == '' and file ~= '' and is_symbol(sym, explicit) then
    s.src_win = api.nvim_get_current_win()
    update(sym, file, false, true)
  elseif not s.sym then
    render_msg(nil, 'move the cursor onto a symbol in a source window')
  end
end

api.nvim_create_user_command('RelationView', function(o)
  open_and_query(o.args)
end, { nargs = '?', desc = 'Source Insight style relation window' })

api.nvim_create_user_command('RelationViewToggle', function()
  if panel_visible() or panel_win_here() then
    A.close()
  else
    open_and_query(nil)
  end
end, { desc = 'Toggle the relation window' })

if vim.fn.maparg('<F3>', 'n') == '' then
  vim.keymap.set('n', '<F3>', '<Cmd>RelationViewToggle<CR>',
    { desc = 'RelationView toggle' })
end
