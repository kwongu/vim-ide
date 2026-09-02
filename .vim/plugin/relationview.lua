-- relationview.lua - Source Insight style "Relation Window" for nvim.
--
-- Shows, in real time, what the symbol under the cursor is:
--   * a function          -> definition + an expandable multi-depth CALLER TREE
--   * a struct/union/enum -> definition + its members
--   * a variable          -> its declaration in the enclosing function
--                           (parameters included), the definition and members
--                           of its type, and its uses inside that function
-- Backed by GNU Global (gtags) - the same GTAGS database that F2
-- (mktags.sh) already creates - plus treesitter for the members and for
-- resolving a variable to its type.
--
--   F3                  toggle the relation window (was "Empty")
--   :RelationView [sym] open the window and show relations of sym/<cword>
--   :RelationViewToggle same as F3
--
-- Inside the panel:
--   <Enter> jump to the call site   o  jump but keep focus in the panel
--   double click            jump to the clicked entry in the edit window
--   mouse button 4 / 5      back / forward, like <C-o> / <C-i>
--   <Space> expand/collapse the caller under the cursor ( + / - work too)
--   *  expand the whole tree (bounded by max_depth/max_nodes)
--   x  export the current tree as an HTML graph and open it in a browser
--      (not 'g': that would break 'gg')
--   c  toggle the context window (Source Insight style: shows the source
--      around the location under the cursor, attached to the panel)
--   p  pin (freeze) current symbol            r  refresh (drop cache)
--   a  toggle realtime auto-update            q  close the panel
--
-- Expanding a node pins the panel automatically so a stray cursor move
-- does not rebuild the tree; press p to unpin.
--
-- Jumps land on the referenced symbol itself (line AND column); if the
-- file changed since the last gtags run, the symbol is re-located within
-- +-30 lines of the recorded position.
--
-- The context window is a preview, never a driver: resting the cursor on a
-- symbol there does NOT rebuild the tree. Inside it, <C-]> follows the
-- definition of the symbol under the cursor within the context window only
-- (source windows are untouched), <C-t> returns along its own stack, and a
-- double click follows the definition of the symbol under the mouse (same as
-- <C-]>), and <CR> takes the edit window to the line under the cursor.
--
-- Options (set in .vimrc, all optional):
--   g:relationview_position   'bottom' (default) or 'right'
--   g:relationview_height     panel height for 'bottom'  (default 12)
--   g:relationview_width      panel width  for 'right'   (default 50)
--   g:relationview_auto       1: update as the cursor moves (default 1)
--   g:relationview_debounce   idle debounce in ms         (default 250)
--   g:relationview_max_refs   max references per level    (default 1000)
--   g:relationview_max_depth  depth limit of '*'          (default 6)
--   g:relationview_max_nodes  node limit of '*'           (default 300)
--   g:relationview_max_sites  call sites listed per caller (default 8)
--   g:relationview_full_path  1: absolute paths; default 0 = relative to
--                             vim's current directory (:pwd)
--   g:relationview_auto_open  1: open the panel on startup (default 1)
--   g:relationview_context    1: open the context window with the panel
--                             (default 1; 'c' toggles it at runtime)
--   g:relationview_context_height  context height, 'right' layout (default 25,
--                             capped so the tree keeps at least 8 rows)
--   g:relationview_context_width   context width, 'bottom' layout (default 0 = half)
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

-- is the cursor on a TYPE usage ('struct foo') rather than on a plain name?
local function wants_type_at(buf, line, col)
  local ok, l = pcall(api.nvim_buf_get_lines, buf, line - 1, line, false)
  l = ok and l[1] or nil
  if not l then
    return false
  end
  local head = l:sub(1, (col or 0) + 1)
  return head:match('%f[%w_]struct%s+[%w_]*$') ~= nil
      or head:match('%f[%w_]union%s+[%w_]*$') ~= nil
      or head:match('%f[%w_]enum%s+[%w_]*$') ~= nil
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

local function basename(p)
  return p:match('([^/]+)$') or p
end

-- display-width helpers for the aligned columns (tree prefixes and paths
-- can contain multibyte characters, so plain '#' is not usable)
local function pad(text, w)
  local d = w - vim.fn.strwidth(text)
  return d > 0 and (text .. string.rep(' ', d)) or text
end

-- truncate to a display width, keeping the HEAD (tree prefix + name)
local function trunc_w(text, w)
  if vim.fn.strwidth(text) <= w then
    return text
  end
  local out = text
  while vim.fn.strwidth(out) > w - 1 and #out > 1 do
    out = out:sub(1, -2)
  end
  return out .. '…'
end

-- truncate to a display width, keeping the TAIL (basename:line of a path)
local function trunc_tail(text, w)
  if vim.fn.strwidth(text) <= w then
    return text
  end
  local out = text
  while vim.fn.strwidth(out) > w - 1 and #out > 1 do
    out = out:sub(2)
  end
  return '…' .. out
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

local s = {
  buf = nil,          -- panel buffer
  win = nil,          -- panel window
  src_win = nil,      -- window the last query came from
  sym = nil,          -- symbol currently displayed
  tree = nil,         -- current caller tree (see finish())
  pinned = false,
  auto = cfg('auto', 1) ~= 0,
  gen = 0,            -- generation counter, stale async results are dropped
  timer = nil,        -- debounce timer
  items = {},         -- panel line number -> {node=?, loc={path,line,sym}}
  cache = {},         -- key -> {mtime=..., data=...}
  cache_n = 0,
  roots = {},         -- dir -> gtags root (positive results only)
  procs = {},         -- in-flight vim.system handles of the current query
  inflight = {},      -- filedefs key -> list of waiting callbacks
  ctx_win = nil,      -- context window (Source Insight style)
  ctx_ph = nil,       -- the scratch buffer the preview renders into
  ctx_file = nil,     -- {path=, stamp=, off=, n=} currently copied into it
  ctx_last = nil,     -- last location shown in the context window
  ctx_timer = nil,    -- context update debounce timer
  ctx_stack = {},     -- <C-]> jump stack of the context window (<C-t> pops)
  note = nil,         -- header suffix, e.g. '[struct arpc_msg]'
  shown = nil,        -- symbol of the last render (cursor reset on change)
  ctx_hl_buf = nil,   -- buffer currently carrying the context highlight
  scope = nil,        -- function range a variable view is valid for
  as_type = false,    -- the current view read the symbol as a type usage
  warned = false,
}

-- sky blue for the symbol under the panel cursor, and for the same symbol
-- in the context window ('termguicolors' is off in this setup, so the
-- cterm colours are the ones that actually paint)
local NS_SYM = api.nvim_create_namespace('RelationViewSym')
local NS_CTX = api.nvim_create_namespace('RelationViewCtxSym')

-- every colour the panel uses, in one place. A ':colorscheme' wipes user
-- highlights, so this runs again on every ColorScheme event. All groups are
-- 'default', so anything set in .vimrc keeps winning.
local function set_highlights()
  local hl = {
    RvHeader = { link = 'Title' },
    RvHint = { link = 'Comment' },
    RvSection = { link = 'Label' },
    RvMarker = { link = 'Special' },
    RvName = { link = 'Function' },
    RvLoc = { link = 'Directory' },
    RvDim = { link = 'Comment' },
    RvTree = { link = 'Comment' },
    RvCursorSym = { fg = '#87d7ff', ctermfg = 117, bold = true },
    RvCtxSym = { fg = '#101820', bg = '#87d7ff', ctermfg = 16,
      ctermbg = 117, bold = true },
    -- the row the panel cursor is on: a visible bar, not the barely-there
    -- one most dark colorschemes ship
    RvCursorLine = { bg = '#4e5561', ctermbg = 240 },
    RvCursorLineNr = { fg = '#87d7ff', bg = '#4e5561', ctermfg = 117,
      ctermbg = 240, bold = true },
  }
  for name, spec in pairs(hl) do
    spec.default = true
    api.nvim_set_hl(0, name, spec)
  end
end
set_highlights()

local A = {}          -- panel actions (jump/close/pin/...), defined below
local render_tree     -- forward declarations
local render_rows
local source_text
local include_at
local resolve_include
local hl_cursor_row
local find_member
local ensure_ctx
local update_context
local group = api.nvim_create_augroup('RelationView', { clear = true })

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

-- The database ':Gtags' uses is the one above the WORKING directory. A tree
-- can hold stale nested GTAGS (a sub-directory indexed months ago), and
-- searching from the file's own directory would silently pick that one -
-- different files, different line numbers. Prefer the working directory's
-- database whenever it covers this file, and fall back to the file's own.
local function root_for(path, cb)
  local cwd = vim.fn.getcwd()
  get_root(cwd, function(cwdroot)
    if cwdroot and path:sub(1, #cwdroot + 1) == cwdroot .. '/' then
      cb(cwdroot)
      return
    end
    get_root(vim.fs.dirname(path), cb)
  end)
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

-- last definition starting at or before the line (coarse fallback: it
-- cannot tell where a function ENDS, so file-scope lines between two
-- functions would be blamed on the previous one)
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
-- precise enclosing-function detection: brace-scan the file once to turn
-- the start lines from 'global -f' into real [start,end] ranges, so a
-- prototype / EXPORT_SYMBOL / table between two functions is no longer
-- misattributed to the previous function
-- ---------------------------------------------------------------------------

local MAX_SCAN_FILE = 8 * 1024 * 1024

local function read_file_async(path, cb)
  uv.fs_open(path, 'r', 438, function(oerr, fd)
    if oerr or not fd then
      vim.schedule(function() cb(nil) end)
      return
    end
    uv.fs_fstat(fd, function(serr, st)
      if serr or not st or st.size > MAX_SCAN_FILE then
        uv.fs_close(fd, function() end)
        vim.schedule(function() cb(nil) end)
        return
      end
      uv.fs_read(fd, st.size, 0, function(rerr, data)
        uv.fs_close(fd, function() end)
        vim.schedule(function() cb(rerr == nil and data or nil) end)
      end)
    end)
  end)
end

-- top-level brace ranges of the file, each owned by the nearest preceding
-- definition: functions, but also global initializers/struct bodies.
--
-- The scan is PREPROCESSOR-AWARE, which matters a lot on kernel-style C:
--  * every '#...' directive line (and its '\' continuations) is excluded
--    from brace counting, so multi-line macros with unbalanced braces
--    (do { ... } while (0) split across #defines) cannot drift the depth
--  * '#if/#elif/#else/#endif' branches are tracked with a stack: each
--    branch is scanned starting from the depth of the '#if', and after
--    '#endif' the depth continues from the CHOSEN branch's result
--    (the first branch, or the '#else' branch for '#if 0'), so split
--    function signatures across branches no longer double-count braces
local function build_ranges(content, defs)
  local lines = vim.split(content, '\n', { plain = true })
  local ranges = {}
  local depth = 0
  local in_block = false
  local cont = false -- inside a multi-line '#' directive ('\' continuation)
  local pp = {}      -- '#if' stack: {start=, chosen=, idx=, result=}
  local open_owner, open_start = nil, nil
  local di, last_def = 1, nil
  local used = {} -- local marker: never mutate the cached defs table
  for i, raw in ipairs(lines) do
    local skip = false
    if cont then
      skip = true
      cont = raw:match('\\%s*$') ~= nil
    elseif not in_block and raw:match('^%s*#') then
      skip = true
      cont = raw:match('\\%s*$') ~= nil
      local kw = raw:match('^%s*#%s*(%a+)')
      if kw == 'if' or kw == 'ifdef' or kw == 'ifndef' then
        -- '#if 0 /* reason */' and '#if 0 // reason' are dead too
        local cond = raw:gsub('/%*.*$', ''):gsub('//.*$', '')
        local dead = kw == 'if'
            and cond:match('^%s*#%s*if%s+0[LlUu]*%s*$') ~= nil
        pp[#pp + 1] = { start = depth, chosen = dead and 2 or 1, idx = 1 }
      elseif kw == 'elif' or kw == 'else' then
        local top = pp[#pp]
        if top then
          if top.idx == top.chosen then
            top.result = depth
          end
          top.idx = top.idx + 1
          depth = top.start
        end
      elseif kw == 'endif' then
        local top = table.remove(pp)
        if top then
          if top.idx == top.chosen then
            top.result = depth
          end
          depth = top.result or top.start
        end
      end
    elseif raw:find('extern%s*"C"') then
      skip = true -- its '{' has no code meaning; the stray '}' self-corrects
    end

    -- lines inside a non-chosen preprocessor branch are invisible
    local active = not skip
    if active then
      for _, e in ipairs(pp) do
        if e.idx ~= e.chosen then
          active = false
          break
        end
      end
    end

    -- consume the definitions on this line; only ACTIVE code lines provide
    -- owner candidates ('#define' lines and defs inside dead/non-chosen
    -- branches must never own the next brace block)
    while di <= #defs and defs[di].line <= i do
      if active then
        last_def = defs[di]
      end
      di = di + 1
    end

    if active then
      local code = raw
      -- crude comment/string stripping, good enough for brace counting
      if in_block then
        local e = code:find('*/', 1, true)
        if e then
          code = code:sub(e + 2)
          in_block = false
        else
          code = ''
        end
      end
      if code ~= '' then
        code = code:gsub('\\\\', '')      -- doubled backslashes first: '\\'
        code = code:gsub('\\[\'"]', '')   -- escaped quotes
        code = code:gsub("'\"'", "''")    -- '"' must not pair with a string
        code = code:gsub('"[^"]*"', '""')
        code = code:gsub("'[^']*'", "''")
        code = code:gsub('/%*.-%*/', '')
        -- whichever of '//' or an unterminated '/*' comes first wins:
        -- a '//' comment containing '/*' (banner lines, glob paths) must
        -- not open a block comment
        local bs = code:find('/*', 1, true)
        local ls = code:find('//', 1, true)
        if ls and (not bs or ls < bs) then
          code = code:sub(1, ls - 1)
        elseif bs then
          code = code:sub(1, bs - 1)
          in_block = true
        end
      end
      local opens = select(2, code:gsub('{', ''))
      local closes = select(2, code:gsub('}', ''))
      if depth == 0 and opens > 0 then
        -- a definition owns at most ONE top-level brace range: an anonymous
        -- block after it (e.g. a static variable initializer that gtags
        -- does not record) must not be blamed on it again
        if last_def and not used[last_def] then
          open_owner = last_def
          used[last_def] = true
          -- include the signature line(s) above the opening brace, but
          -- never reach back into the previous range
          local floor_ = ranges[#ranges] and (ranges[#ranges].e + 1) or 1
          open_start = math.max(math.min(last_def.line, i), floor_)
        else
          open_owner = nil
          open_start = i
        end
      end
      depth = depth + opens - closes
      if depth <= 0 then
        if open_start then
          -- definitions recorded INSIDE the closed range (enum members,
          -- the typedef name on '} name_t;') can never own a later block
          local closing_semi = code:match(';%s*$') ~= nil
          for k = di - 1, 1, -1 do
            local d = defs[k]
            if d.line < open_start then
              break
            end
            if d.line < i or (d.line == i and closing_semi) then
              used[d] = true
            end
          end
          ranges[#ranges + 1] = { s = open_start, e = i,
            name = open_owner and open_owner.name or nil }
          open_start, open_owner = nil, nil
        end
        depth = 0 -- self-correct on miscounts
      end
    end
  end
  if open_start then
    ranges[#ranges + 1] = { s = open_start, e = #lines,
      name = open_owner and open_owner.name or nil }
  end
  return ranges
end

-- defs + ranges of one file, cached against BOTH the GTAGS mtime (defs)
-- and the file's own mtime (content); concurrent requests share one scan
local function get_fileranges(root, mtime, path, cb)
  local st = uv.fs_stat(path)
  local ck = tostring(mtime) .. ':' .. tostring(st and st.mtime.sec or -1)
  local key = 'R\0' .. path
  local hit = cache_get(key, ck)
  if hit then
    cb(hit)
    return
  end
  local ikey = 'IR\0' .. path
  if s.inflight[ikey] then
    table.insert(s.inflight[ikey], cb)
    return
  end
  s.inflight[ikey] = { cb }
  local function done(res)
    local waiters = s.inflight[ikey] or {}
    s.inflight[ikey] = nil
    for _, w in ipairs(waiters) do
      w(res)
    end
  end
  get_filedefs(root, mtime, path, function(defs)
    read_file_async(path, function(content)
      local res = { defs = defs, ranges = content and build_ranges(content, defs) or nil }
      cache_put(key, ck, res)
      done(res)
    end)
  end)
end

-- the function a reference line really belongs to, nil = file scope
local function enclosing_at(res, line)
  if res.ranges then
    for _, rg in ipairs(res.ranges) do
      if rg.s > line then
        break
      end
      if line <= rg.e then
        return rg.name
      end
    end
    -- a definition on the very same line still owns the reference
    -- (single-line macro bodies: #define CALL() foo())
    for _, d in ipairs(res.defs) do
      if d.line == line then
        return d.name
      end
      if d.line > line then
        break
      end
    end
    return nil
  end
  return enclosing(res.defs, line) -- unreadable/huge file: coarse fallback
end

-- ---------------------------------------------------------------------------
-- caller tree building
-- ---------------------------------------------------------------------------

-- read far more lines than are displayed, so the "N of M" total is real
local REF_STREAM_CAP = 20000
local MAX_ENCLOSE_FILES = 100
local ENCLOSE_CONC = 5

-- annotate every ref with its enclosing function (r.fn) through a small
-- worker pool; alive() aborts stale work, done() fires when all are set
local function annotate_pool(root, mtime, refs, alive, done)
  local seen, order = {}, {}
  for _, r in ipairs(refs) do
    if not seen[r.path] then
      seen[r.path] = true
      order[#order + 1] = r.path
    end
  end
  local n = math.min(#order, MAX_ENCLOSE_FILES)
  if n == 0 then
    done()
    return
  end
  local idx, active = 0, 0
  local launch
  launch = function()
    if not alive() then
      return -- stale: stop dispatching, drop silently
    end
    while active < ENCLOSE_CONC and idx < n do
      idx = idx + 1
      local path = order[idx]
      active = active + 1
      get_fileranges(root, mtime, path, function(res)
        for _, r in ipairs(refs) do
          if r.path == path then
            r.fn = enclosing_at(res, r.line)
          end
        end
        active = active - 1
        if active == 0 and idx >= n then
          done()
        else
          launch()
        end
      end)
    end
  end
  launch()
end

-- callers of one symbol: annotated references, ready for grouping
local function fetch_callers(root, mtime, sym, alive, cb)
  local max_refs = cfg('max_refs', 1000)
  run_global({ '--result=ctags-mod', '-a', '-r', '-e', sym }, root,
    function(lines)
      if not alive() then
        return
      end
      local refs = parse_ctags_mod(lines, max_refs)
      annotate_pool(root, mtime, refs, alive, function()
        if alive() then
          cb(refs)
        end
      end)
    end, REF_STREAM_CAP)
end

-- group references by their enclosing function (Source Insight shows one
-- box per calling function, not one per call site)
local function group_refs(refs)
  local map, order = {}, {}
  for _, r in ipairs(refs) do
    local key = r.fn and ('f\0' .. r.fn) or ('p\0' .. r.path)
    local e = map[key]
    if not e then
      e = { name = r.fn, sites = {} }
      map[key] = e
      order[#order + 1] = e
    end
    e.sites[#e.sites + 1] = r
  end
  return order
end

-- tree node: name (caller function, nil = file-scope ref), label, sites
-- (call sites of the parent symbol inside this caller), children (nil =
-- not loaded yet), expanded/loading flags, cycle marker
local function make_nodes(entries, parent, rootsym)
  -- the symbol referenced at this level's call sites: the parent caller
  -- for deeper levels, the queried symbol itself at the top level
  local of_sym = parent and parent.name or rootsym
  local nodes = {}
  for _, e in ipairs(entries) do
    local node = {
      name = e.name,
      label = e.name or ('(' .. basename(e.sites[1].path) .. ')'),
      sites = e.sites,
      site = e.sites[1],
      ref_sym = of_sym,
      parent = parent,
      expandable = e.name ~= nil,
      expanded = false,
    }
    if node.name then
      if node.name == rootsym then
        node.cycle = true
      end
      local p = parent
      while p and not node.cycle do
        if p.name == node.name then
          node.cycle = true
        end
        p = p.parent
      end
      if node.cycle then
        node.expandable = false
      end
    end
    nodes[#nodes + 1] = node
  end
  return nodes
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
      syntax match RvTree     /[│├└─]/
      syntax match RvHeader   /^◆.*/
      syntax match RvHint     /^  \[.*/
      syntax match RvSection  /^──.*/
      syntax match RvMarker   /\[[-+…]\]\|↺\|·/
      syntax match RvName     /\%(\[[-+…]\] \|↺ \|· \)\zs\S\+/
      syntax match RvName     /^  \zs\S\+\ze\s\s/
      syntax match RvLoc      /\S\+:\d\+\ze\s*│/
      syntax match RvDim      /(no definition)\|(none)\|(x\d\+)\|…\d\++ more.*/
    ]])
  end)
  local function bmap(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  bmap('<CR>', function() A.jump(false) end, 'RelationView: jump')
  bmap('o', function() A.jump(true) end, 'RelationView: peek')
  -- clicking two rows in quick succession makes nvim count the 3rd/4th
  -- click, so those must jump as well or the second row would do nothing
  for _, lhs in ipairs({ '<2-LeftMouse>', '<3-LeftMouse>', '<4-LeftMouse>' }) do
    bmap(lhs, function() A.mouse_jump(false) end,
      'RelationView: jump (double click)')
  end
  bmap('<Space>', function() A.toggle('toggle') end, 'RelationView: expand/collapse')
  bmap('+', function() A.toggle('expand') end, 'RelationView: expand')
  bmap('-', function() A.toggle('collapse') end, 'RelationView: collapse')
  bmap('*', function() A.expand_all() end, 'RelationView: expand whole tree')
  -- 'g' would swallow the first key of 'gg', so the graph lives on 'x'
  bmap('x', function() A.graph() end, 'RelationView: export HTML graph')
  bmap('c', function() A.toggle_ctx() end, 'RelationView: toggle context window')
  -- the mouse side buttons act on the source window while the list has focus
  bmap('<X1Mouse>', function() A.back() end, 'RelationView: back (<C-o>)')
  bmap('<X2Mouse>', function() A.forward() end, 'RelationView: forward (<C-i>)')
  bmap('q', function() A.close() end, 'RelationView: close')
  bmap('p', function() A.pin() end, 'RelationView: pin/unpin')
  bmap('r', function() A.refresh() end, 'RelationView: refresh')
  bmap('a', function() A.toggle_auto() end, 'RelationView: toggle auto')

  -- Source Insight style: moving in the list previews the location under
  -- the cursor in the context window
  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    buffer = buf,
    callback = function()
      hl_cursor_row()
      if not s.ctx_timer then
        s.ctx_timer = uv.new_timer()
      end
      s.ctx_timer:stop()
      s.ctx_timer:start(80, 0, vim.schedule_wrap(function()
        update_context()
      end))
    end,
  })

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
    if cfg('context', 1) ~= 0 then
      ensure_ctx()
    end
    return s.win
  end
  local buf = ensure_buf()
  local existing = panel_win_here()
  if existing then
    s.win = existing
    if cfg('context', 1) ~= 0 then
      ensure_ctx()
    end
    return existing
  end
  local prev = api.nvim_get_current_win()
  if cfg('position', 'bottom') == 'right' then
    vim.cmd('keepalt botright vertical ' .. cfg('width', 50) .. 'split')
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
  wo.winhighlight = 'CursorLine:RvCursorLine,CursorLineNr:RvCursorLineNr'
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
  if cfg('context', 1) ~= 0 then
    ensure_ctx()
  end
  return win
end

-- colour the symbol on the row the panel cursor is on
hl_cursor_row = function()
  if not (s.buf and api.nvim_buf_is_valid(s.buf)) then
    return
  end
  api.nvim_buf_clear_namespace(s.buf, NS_SYM, 0, -1)
  if not (s.win and api.nvim_win_is_valid(s.win))
      or api.nvim_win_get_buf(s.win) ~= s.buf then
    return
  end
  local lnum = api.nvim_win_get_cursor(s.win)[1]
  local it = s.items[lnum]
  if it and it.hl then
    pcall(api.nvim_buf_set_extmark, s.buf, NS_SYM, lnum - 1, it.hl[1],
      { end_col = it.hl[2], hl_group = 'RvCursorSym' })
  end
end

local function render(lines, items)
  local buf = ensure_buf()
  s.items = items or {}
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
  note = note or s.note
  local flags = {}
  if s.pinned then flags[#flags + 1] = 'PINNED' end
  if not s.auto then flags[#flags + 1] = 'auto:off' end
  local tail = #flags > 0 and ('  [' .. table.concat(flags, ', ') .. ']') or ''
  return {
    '◆ ' .. (sym or '(none)') .. tail .. (note and ('  — ' .. note) or ''),
    '  [⏎]jump [o]peek [␣]open/close [*]all [x]graph [c]ctx [p]pin [r]refresh [q]close',
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

-- ---------------------------------------------------------------------------
-- precise landing + context window (Source Insight style)
-- ---------------------------------------------------------------------------

-- exact position of the referenced symbol: cursor lands ON the symbol, not
-- at column 0, and if the file drifted since the last gtags run the symbol
-- is re-located within +-30 lines of the recorded line
local function locate(buf, line, sym)
  if not sym then
    return line, 0
  end
  local pat = '%f[%w_]' .. sym .. '%f[^%w_]'
  local function col_at(l)
    local txt = (api.nvim_buf_get_lines(buf, l - 1, l, false)[1]) or ''
    local st = txt:find(pat)
    return st and st - 1 or nil
  end
  local c = col_at(line)
  if c then
    return line, c
  end
  for d = 1, 30 do
    for _, l in ipairs({ line - d, line + d }) do
      if l >= 1 then
        local cc = col_at(l)
        if cc then
          return l, cc
        end
      end
    end
  end
  return line, 0
end

-- The preview shows a COPY of the file in a scratch buffer, never the file
-- buffer itself. That is what keeps ':cnext' from a ':Gtags -r' quickfix
-- list (and :tag, gf, ...) from hijacking this window: there is no file
-- buffer here to jump into, so those commands always land in a real edit
-- window. It also means the preview can never be edited by accident.
local ctx_tag_jump, ctx_tag_back

local function ctx_buf()
  if s.ctx_ph and api.nvim_buf_is_valid(s.ctx_ph) then
    return s.ctx_ph
  end
  local b = api.nvim_create_buf(false, true)
  pcall(api.nvim_buf_set_name, b, 'RelationView-Context')
  vim.bo[b].buftype = 'nofile'
  vim.bo[b].bufhidden = 'hide'
  vim.bo[b].swapfile = false
  api.nvim_buf_set_lines(b, 0, -1, false,
    { '(move the cursor in the relation list to preview a location here)' })
  vim.bo[b].modifiable = false
  -- the maps live on this buffer forever: it is ours, so they can never
  -- leak into a real file the user is editing
  vim.keymap.set('n', '<C-]>', function() ctx_tag_jump() end,
    { buffer = b, nowait = true, desc = 'RelationView context: goto definition' })
  vim.keymap.set('n', '<C-t>', function() ctx_tag_back() end,
    { buffer = b, nowait = true, desc = 'RelationView context: jump back' })
  -- double click follows the definition of the symbol under the mouse,
  -- exactly like <C-]> does here
  for _, lhs in ipairs({ '<2-LeftMouse>', '<3-LeftMouse>', '<4-LeftMouse>' }) do
    vim.keymap.set('n', lhs, function() ctx_tag_jump() end,
      { buffer = b, nowait = true,
        desc = 'RelationView context: goto definition (double click)' })
  end
  -- <CR> takes the edit window to the line under the cursor
  vim.keymap.set('n', '<CR>', function() A.ctx_jump() end,
    { buffer = b, nowait = true,
      desc = 'RelationView context: open this line in the edit window' })
  -- in the preview the back button walks the same stack as <C-t>
  vim.keymap.set('n', '<X1Mouse>', function() ctx_tag_back() end,
    { buffer = b, nowait = true, desc = 'RelationView context: jump back' })
  s.ctx_ph = b
  return b
end

local function ctx_apply_opts(win)
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  local wo = vim.wo[win]
  wo.number = true
  wo.relativenumber = false
  wo.list = false
  wo.wrap = false
  wo.signcolumn = 'no'
  wo.foldenable = false
  wo.spell = false
  wo.cursorline = true
  wo.colorcolumn = ''
  wo.winhighlight = 'CursorLine:RvCursorLine,CursorLineNr:RvCursorLineNr'
  pcall(function() wo.winfixbuf = true end)
end

local function ctx_visible()
  return s.ctx_win ~= nil and api.nvim_win_is_valid(s.ctx_win)
      and api.nvim_win_get_tabpage(s.ctx_win) == api.nvim_get_current_tabpage()
end

-- copy `path` into the preview buffer (once per file version) and return the
-- offset between the file's line numbers and the buffer's
local MAX_CTX_LINES = 50000

local function ctx_fill(path, line)
  local cur = s.ctx_file
  local st = uv.fs_stat(path)
  local info = vim.fn.getbufinfo(path)[1]
  local stamp = tostring(st and st.mtime.sec or -1) .. ':'
      .. tostring(info and info.changedtick or 0)
  if cur and cur.path == path and cur.stamp == stamp
      and (cur.off == 0 or (line > cur.off + 2 and line < cur.off + cur.n - 2))
  then
    return cur.off
  end
  local content, srcbuf = source_text(path)
  if not content then
    return nil
  end
  local all = vim.split(content, '\n', { plain = true })
  local off, chunk = 0, all
  if #all > MAX_CTX_LINES then
    -- huge generated file: show a window around the target and shift the
    -- numbers back to the file's own with 'statuscolumn'
    local from = math.max(1, line - 2000)
    off = from - 1
    chunk = vim.list_slice(all, from, math.min(#all, from + 4000))
  end
  local b = ctx_buf()
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, chunk)
  vim.bo[b].modifiable = false
  local ft = vim.filetype.match({ filename = path, buf = srcbuf }) or ''
  if vim.bo[b].filetype ~= ft then
    vim.bo[b].filetype = ft
  end
  s.ctx_file = { path = path, stamp = stamp, off = off, n = #chunk }
  if s.ctx_win and api.nvim_win_is_valid(s.ctx_win) then
    vim.wo[s.ctx_win].statuscolumn = off > 0
        and '%{v:lnum + ' .. off .. '}  ' or ''
  end
  return off
end

ensure_ctx = function()
  if ctx_visible() then
    return s.ctx_win
  end
  if not panel_visible() then
    return nil
  end
  local ctx
  api.nvim_win_call(s.win, function()
    if cfg('position', 'bottom') == 'right' then
      -- keep the tree usable: on a short terminal a fixed height would
      -- squash the list down to a row or two, so leave it at least 8 rows
      local avail = api.nvim_win_get_height(s.win)
      local h = math.min(cfg('context_height', 25), math.max(3, avail - 9))
      vim.cmd('noautocmd rightbelow ' .. h .. 'split')
    else
      vim.cmd('noautocmd rightbelow vertical split')
      local w = cfg('context_width', 0)
      if w > 0 then
        vim.cmd('vertical resize ' .. w)
      end
    end
    ctx = api.nvim_get_current_win()
  end)
  if not (ctx and api.nvim_win_is_valid(ctx)) then
    return nil
  end
  api.nvim_win_set_buf(ctx, ctx_buf())
  ctx_apply_opts(ctx)
  local wo = vim.wo[ctx]
  wo.winfixheight = true
  wo.winfixwidth = true
  s.ctx_win = ctx
  s.ctx_last = nil
  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(ctx),
    once = true,
    callback = function()
      if s.ctx_win == ctx then
        s.ctx_win = nil
      end
    end,
  })
  return ctx
end

-- <C-]> / <C-t> inside the context window: follow definitions and come back
-- WITHOUT touching the source windows or the relation tree
ctx_tag_jump = function()
  if not ctx_visible() or api.nvim_get_current_win() ~= s.ctx_win then
    return
  end
  -- a double click reports where the mouse is; the keyboard path is a no-op
  local m = vim.fn.getmousepos()
  if m and m.winid == s.ctx_win and m.line and m.line > 0 then
    pcall(api.nvim_win_set_cursor, s.ctx_win,
      { m.line, math.max(0, (m.column or 1) - 1) })
  end
  local file = s.ctx_file and s.ctx_file.path or nil
  if not file then
    return
  end
  local pos = api.nvim_win_get_cursor(s.ctx_win)
  local off = s.ctx_file.off or 0

  -- '#include "foo.h"' is about a file: follow it here, like a symbol
  local inc = include_at(api.nvim_win_get_buf(s.ctx_win), pos[1])
  if inc then
    root_for(file, function(root)
      local path = resolve_include(inc, file, root)
      if not path then
        vim.notify('RelationView context: header not found: ' .. inc,
          vim.log.levels.WARN)
        return
      end
      table.insert(s.ctx_stack,
        { path = file, line = pos[1] + off, col = pos[2] })
      s.ctx_last = nil
      show_context({ path = path, line = 1 })
    end)
    return
  end

  local sym = vim.fn.expand('<cword>')
  if not is_symbol(sym, true) then
    return
  end
  root_for(file, function(root)
    if not root or not ctx_visible() then
      return
    end
    run_global({ '--result=ctags-mod', '-a', '-d', '-e', sym }, root,
      function(lines)
        local d = parse_ctags_mod(lines, 4)[1]
        if not d then
          vim.notify('RelationView context: no definition of ' .. sym,
            vim.log.levels.WARN)
          return
        end
        if not ctx_visible() then
          return
        end
        table.insert(s.ctx_stack,
          { path = file, line = pos[1] + off, col = pos[2], sym = sym })
        s.ctx_last = nil -- a manual jump, not a list preview
        show_context({ path = d.path, line = d.line, sym = sym })
      end, 8)
  end)
end

ctx_tag_back = function()
  if not ctx_visible() or api.nvim_get_current_win() ~= s.ctx_win then
    return
  end
  local prev = table.remove(s.ctx_stack)
  if not prev then
    vim.notify('RelationView context: jump stack is empty')
    return
  end
  s.ctx_last = nil
  -- no 'sym' here on purpose: the recorded line/column is the exact spot,
  -- re-locating the symbol could land back where we just came from
  show_context({ path = prev.path, line = prev.line, col = prev.col or 0 })
end

show_context = function(loc)
  if not ctx_visible() then
    return
  end
  local last = s.ctx_last
  if last and last.path == loc.path and last.line == loc.line
      and last.sym == loc.sym then
    return
  end
  s.ctx_last = loc
  local off = ctx_fill(loc.path, loc.line)
  if not off then
    return
  end
  local b = ctx_buf()
  if api.nvim_win_get_buf(s.ctx_win) ~= b then
    pcall(function() vim.wo[s.ctx_win].winfixbuf = false end)
    pcall(api.nvim_win_set_buf, s.ctx_win, b)
    ctx_apply_opts(s.ctx_win)
  end
  local line, col = locate(b, loc.line - off, loc.sym)
  if loc.col and loc.sym == nil then
    col = loc.col
  end
  api.nvim_win_call(s.ctx_win, function()
    pcall(api.nvim_win_set_cursor, s.ctx_win, { line, col })
    vim.cmd('normal! zz')
  end)
  api.nvim_buf_clear_namespace(b, NS_CTX, 0, -1)
  s.ctx_hl_buf = nil
  if loc.sym then
    local txt = api.nvim_buf_get_lines(b, line - 1, line, false)[1]
    if txt and txt:sub(col + 1, col + #loc.sym) == loc.sym then
      pcall(api.nvim_buf_set_extmark, b, NS_CTX, line - 1, col,
        { end_col = col + #loc.sym, hl_group = 'RvCtxSym' })
      s.ctx_hl_buf = b
    end
  end
  local label = (cfg('full_path', 0) ~= 0 and loc.path
      or vim.fn.fnamemodify(loc.path, ':.'))
      .. ':' .. (line + off) .. (loc.sym and ('  ◆ ' .. loc.sym) or '')
  pcall(function()
    vim.wo[s.ctx_win].winbar = ' ' .. label:gsub('%%', '%%%%')
  end)
end

-- preview the location under the panel cursor (falls back to the
-- definition of the current symbol)
update_context = function()
  if not ctx_visible() then
    return
  end
  -- while the user is browsing inside the context window (<C-]>/<C-t>),
  -- a late render must not yank the preview back to the list item
  if api.nvim_get_current_win() == s.ctx_win then
    return
  end
  if not (s.win and api.nvim_win_is_valid(s.win)) then
    return
  end
  local lnum = api.nvim_win_get_cursor(s.win)[1]
  local item = s.items[lnum]
  local loc = item and item.loc
  if not loc and s.tree and s.tree.def then
    loc = { path = s.tree.def.path, line = s.tree.def.line, sym = s.tree.sym }
  end
  if loc then
    show_context(loc)
  end
end

-- render the whole caller tree of s.tree into the panel
render_tree = function()
  local t = s.tree
  if not t then
    return
  end
  -- paths relative to vim's current directory, the way vim itself shows
  -- them ('%:.'); g:relationview_full_path = 1 keeps them absolute
  local full_path = cfg('full_path', 0) ~= 0
  local function rel(p)
    if full_path then
      return p
    end
    return vim.fn.fnamemodify(p, ':.')
  end

  -- pass 1: collect the three columns of every row so they can be padded
  -- to a common width (symbol | file:line | source text)
  local rows = {}      -- {kind='row', sym=, loc=, text=, item=, node=}
                       -- or {kind='raw', text=}
  local function raw(text)
    rows[#rows + 1] = { kind = 'raw', text = text }
  end
  local function row(symcol, path, line, text, item, name)
    rows[#rows + 1] = { kind = 'row', sym = symcol,
      loc = string.format('%s:%d', rel(path), line),
      text = text, item = item, name = name }
    return rows[#rows]
  end

  -- an '#include' target: the header itself plus what it defines
  if t.kind == 'header' then
    raw('')
    raw(section_line('Definition'))
    local r = row('  ' .. basename(t.def.path), t.def.path, t.def.line,
      t.def.text, { loc = { path = t.def.path, line = t.def.line } },
      basename(t.def.path))
    r.focus = true
    raw('')
    raw(section_line('Symbols in this file', t.defs and #t.defs or nil))
    if not t.defs or #t.defs == 0 then
      raw('  ' .. (t.defs_note or '(none)'))
    else
      for _, d in ipairs(t.defs) do
        row('  ' .. d.name, t.def.path, d.line, d.text,
          { loc = { path = t.def.path, line = d.line, sym = d.name } }, d.name)
      end
    end
    render_rows(t, rows)
    return
  end

  -- a type or a variable: definition + members, no call tree
  if t.kind == 'members' or t.kind == 'variable' then
    if t.decl then
      raw('')
      raw(section_line(t.decl.is_param and 'Parameter' or 'Declaration'))
      local dname = t.decl.name or t.sym
      local r = row('  ' .. dname, t.decl.path, t.decl.line, t.decl.text,
        { loc = { path = t.decl.path, line = t.decl.line, sym = dname } },
        dname)
      r.focus = true -- until the type definition below claims it
    end
    if t.type or t.def then
      raw('')
      local tname = t.type and (t.type.kind .. ' ' .. (t.type.name or t.sym))
          or 'Definition'
      raw(section_line(tname))
      if t.def then
        local label = (t.type and t.type.name) or t.sym
        local r = row('  ' .. label, t.def.path, t.def.line, t.def.text,
          { loc = { path = t.def.path, line = t.def.line, sym = label } },
          label)
        for _, other in ipairs(rows) do
          other.focus = nil
        end
        -- the context window opens on the type, or on the member that was
        -- under the cursor when one was picked out of an expression
        r.focus = not t.focus_member
      else
        raw('  ' .. (t.type_note or '(no type definition)'))
      end
    elseif t.type_note then
      raw('  ' .. t.type_note)
    end

    -- members only exist once the type definition was found and parsed
    if t.def then
      raw('')
      raw(section_line('Members', t.members and #t.members or nil))
      if not t.members or #t.members == 0 then
        raw('  ' .. (t.members_note or '(none)'))
      else
        for _, m in ipairs(t.members) do
          local r = row('  ' .. m.name, t.def.path, m.line, m.text,
            { loc = { path = t.def.path, line = m.line, sym = m.name } },
            m.name)
          if t.focus_member and find_member({ m }, t.focus_member) then
            for _, other in ipairs(rows) do
              other.focus = nil
            end
            r.focus = true
          end
        end
      end
    end

    if t.uses and #t.uses > 0 then
      raw('')
      raw(section_line('Uses in ' .. (t.fnname or 'function'), #t.uses))
      for _, u in ipairs(t.uses) do
        row('  ' .. t.sym, t.srcpath, u.line, u.text,
          { loc = { path = t.srcpath, line = u.line, sym = t.sym } }, t.sym)
      end
    end

    render_rows(t, rows)
    return
  end

  raw('')
  raw(section_line('Definition'))
  if t.def then
    local r = row('  ' .. t.sym, t.def.path, t.def.line, t.def.text,
      { loc = { path = t.def.path, line = t.def.line, sym = t.sym } }, t.sym)
    r.focus = true
  else
    raw('  (no definition)')
  end

  local title = t.kind == 'symbol'
      and 'References (undefined symbol)' or 'Callers'
  raw('')
  if t.truncated and t.truncated > 0 then
    raw(section_line(string.format('%s (%d) — %d of %d refs shown', title,
      #t.nodes, t.shown or 0, (t.shown or 0) + t.truncated)))
  else
    raw(section_line(title, #t.nodes))
  end
  if #t.nodes == 0 then
    raw('  (none)')
  end

  local function emit(nodes, prefix)
    for i, nd in ipairs(nodes) do
      local last = i == #nodes
      local branch = last and '└─' or '├─'
      local marker
      if nd.loading then
        marker = '[…]'
      elseif nd.cycle then
        marker = ' ↺ '
      elseif not nd.expandable then
        marker = ' · '
      elseif nd.expanded then
        marker = '[-]'
      else
        marker = '[+]'
      end
      local cnt = #nd.sites > 1 and string.format(' (x%d)', #nd.sites) or ''
      local r = row(prefix .. branch .. marker .. ' ' .. nd.label .. cnt,
        nd.site.path, nd.site.line, nd.site.text,
        { node = nd,
          loc = { path = nd.site.path, line = nd.site.line, sym = nd.ref_sym } },
        nd.label)
      r.node = nd
      -- one caller can call the symbol several times: show every call site,
      -- not just the first, so nothing is missing next to ':Gtags -r'
      if #nd.sites > 1 then
        local pre = prefix .. (last and '   ' or '│  ')
        local cap = cfg('max_sites', 8)
        for k = 2, math.min(#nd.sites, cap) do
          local st = nd.sites[k]
          row(pre .. ' ·  ' .. nd.label, st.path, st.line, st.text,
            { loc = { path = st.path, line = st.line, sym = nd.ref_sym } },
            nd.label)
        end
        if #nd.sites > cap then
          raw(string.format('%s … %d more call sites', pre,
            #nd.sites - cap))
        end
      end
      if nd.expanded and nd.children then
        emit(nd.children, prefix .. (last and '   ' or '│  '))
      end
    end
  end
  emit(t.nodes, '  ')

  if t.truncated and t.truncated > 0 then
    -- lower bound: the query is capped, the real total may be larger
    raw(string.format('  … %d more refs%s  (:Gtags -r %s)', t.truncated,
      t.capped and '+' or '', t.sym))
  end

  render_rows(t, rows)
end

-- pass 2: size the columns to the widest entry, capped so the source text
-- still gets room in a narrow panel, then paint the buffer
render_rows = function(t, rows)
  local wsym, wloc = 0, 0
  for _, r in ipairs(rows) do
    if r.kind == 'row' then
      wsym = math.max(wsym, vim.fn.strwidth(r.sym))
      wloc = math.max(wloc, vim.fn.strwidth(r.loc))
    end
  end
  local avail = (s.win and api.nvim_win_is_valid(s.win))
      and api.nvim_win_get_width(s.win) or 80
  local wide = cfg('full_path', 0) ~= 0
  wsym = math.min(wsym, math.max(24, math.floor(avail * (wide and 0.35 or 0.45))))
  wloc = math.min(wloc, math.max(16, math.floor(avail * (wide and 0.62 or 0.35))))

  local lines = header(t.sym)
  local items = {}
  local focus
  for _, r in ipairs(rows) do
    if r.kind == 'raw' then
      lines[#lines + 1] = r.text
    else
      local symcell = pad(trunc_w(r.sym, wsym), wsym)
      lines[#lines + 1] = string.format('%s  %s │ %s',
        symcell, pad(trunc_tail(r.loc, wloc), wloc), trunc(r.text, 200))
      items[#lines] = r.item
      if r.item and r.name then
        local st = symcell:find(r.name, 1, true)
        if st then
          r.item.hl = { st - 1, st - 1 + #r.name }
        end
      end
      if r.node then
        r.node.line = #lines
      end
      if r.focus then
        focus = #lines
      end
    end
  end
  render(lines, items)
  -- a new symbol starts on its most useful row (the definition, or the
  -- member that was under the cursor), so the context window shows that
  -- without the user moving anything
  if focus and s.shown ~= t.sym and s.win and api.nvim_win_is_valid(s.win) then
    pcall(api.nvim_win_set_cursor, s.win, { focus, 0 })
  end
  s.shown = t.sym
  hl_cursor_row()
  vim.schedule(update_context)
end

-- ---------------------------------------------------------------------------
-- types (struct / union / enum / typedef) and local variables
--
-- Source Insight shows the members of a type, and for a variable the type it
-- was declared with. Both are derived with treesitter: gtags knows WHERE a
-- type is defined, the parser knows what is INSIDE it.
-- ---------------------------------------------------------------------------

local MAX_READ_FILE = 8 * 1024 * 1024

-- content of a file, preferring a loaded buffer (unsaved edits included)
source_text = function(path)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and api.nvim_buf_get_name(b) == path then
      return table.concat(api.nvim_buf_get_lines(b, 0, -1, false), '\n'), b
    end
  end
  local st = uv.fs_stat(path)
  if not st or st.size > MAX_READ_FILE then
    return nil
  end
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local c = f:read('*a')
  f:close()
  return c, nil
end

-- '__attribute__((packed))' derails the C grammar ('enum __attribute__(())
-- e {' parses as a function). Blank it out with the SAME number of bytes so
-- every node range still lines up with the original text.
local function strip_attrs(text)
  local function blank(m) return (' '):rep(#m) end
  return (text:gsub('__attribute__%s*%b()', blank)
              :gsub('__declspec%s*%b()', blank))
end

-- parse a file and return its root node plus the 'source' get_node_text needs
local function ts_tree(path)
  local content, bufnr = source_text(path)
  if not content then
    return nil
  end
  if content:find('__attribute__', 1, true)
      or content:find('__declspec', 1, true) then
    bufnr = nil -- parse a blanked copy instead of the live buffer
    content = strip_attrs(content)
  end
  if bufnr then
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if ok and parser then
      local okp, trees = pcall(function() return parser:parse() end)
      if okp and trees and trees[1] then
        return trees[1]:root(), bufnr
      end
    end
  end
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
  return trees[1]:root(), content
end

local function ntext(node, source)
  local ok, t = pcall(vim.treesitter.get_node_text, node, source)
  return ok and t or ''
end

local function field1(node, name)
  local f = node:field(name)
  return f and f[1] or nil
end

local TYPE_NODES = {
  struct_specifier = 'struct',
  union_specifier = 'union',
  enum_specifier = 'enum',
  class_specifier = 'class',
}

local PRIMITIVES = {}
for w in ('int char short long float double void bool _Bool signed unsigned'):gmatch('%S+') do
  PRIMITIVES[w] = true
end
local QUALIFIERS = {}
for w in ('static const volatile extern register inline restrict __restrict auto struct union enum'):gmatch('%S+') do
  QUALIFIERS[w] = true
end

-- 'struct arpc_msg *msg;' -> struct/arpc_msg, 'enum color c' -> enum/color,
-- 'arpc_msg_t msg' -> typedef/arpc_msg_t, 'int i' -> nil (nothing to open)
local function type_from_text(text)
  for _, k in ipairs({ 'struct', 'union', 'enum' }) do
    local name = text:match('%f[%w_]' .. k .. '%s+([%a_][%w_]*)')
    if name then
      return { kind = k, name = name }
    end
  end
  for w in text:gmatch('[%a_][%w_]*') do
    if PRIMITIVES[w] then
      return nil
    end
    if not QUALIFIERS[w] then
      return { kind = 'typedef', name = w }
    end
  end
  return nil
end

-- the type a treesitter 'type' field stands for
local function type_of_node(tnode, source)
  if not tnode then
    return nil
  end
  local kind = TYPE_NODES[tnode:type()]
  if kind then
    local n = field1(tnode, 'name')
    return n and { kind = kind, name = ntext(n, source) } or nil
  end
  if tnode:type() == 'type_identifier' then
    return { kind = 'typedef', name = ntext(tnode, source) }
  end
  return nil -- primitive_type, sized_type_specifier, ...
end

-- does this gtags definition line define a type whose members we can list?
local function def_is_type(text, sym)
  local t = strip_attrs(text)
  for _, k in ipairs({ 'struct', 'union', 'enum', 'class' }) do
    -- only a real definition/declaration of the tag counts: a function
    -- taking 'struct sym *x' merely mentions it
    if t:match('%f[%w_]' .. k .. '%s+' .. sym .. '%s*[{;]')
        or t:match('%f[%w_]' .. k .. '%s+' .. sym .. '%s*$') then
      return k
    end
  end
  -- 'typedef struct { ... } name_t;' is recorded on its closing line
  if t:match('^%s*}') or t:match('%f[%w_]typedef%f[^%w_]') then
    return 'typedef'
  end
  return nil
end

-- smallest struct/union/enum (or typedef wrapper) spanning `line`
local function find_type_node(root, line)
  local row = line - 1
  local best
  local function walk(node)
    local sr, _, er, _ = node:range()
    if sr > row or er < row then
      return
    end
    if TYPE_NODES[node:type()] or node:type() == 'type_definition' then
      if not best then
        best = node
      else
        local bsr, _, ber, _ = best:range()
        if (er - sr) <= (ber - bsr) then
          best = node
        end
      end
    end
    for c in node:iter_children() do
      walk(c)
    end
  end
  walk(root)
  if best and best:type() == 'type_definition' then
    for c in best:iter_children() do
      if TYPE_NODES[c:type()] then
        return c
      end
    end
  end
  return best
end

-- members of the type defined at path:line
-- -> { kind=, name=, line=, members = { {name=, text=, line=} } }
-- every field name of ONE field_declaration, without descending into the
-- body of a nested struct/union (those belong to the nested type)
local function field_names(node, source)
  local names = {}
  local function walk(n)
    local nt = n:type()
    if nt == 'field_declaration_list' or nt == 'enumerator_list' then
      return
    end
    if nt == 'field_identifier' then
      names[#names + 1] = ntext(n, source)
    end
    for c in n:iter_children() do
      walk(c)
    end
  end
  walk(node)
  return names
end

-- the body of a C11 anonymous struct/union member, whose fields belong to
-- the enclosing type ('n->ival'), or nil
local function anon_body(node)
  for x in node:iter_children() do
    if TYPE_NODES[x:type()] then
      for y in x:iter_children() do
        if y:type() == 'field_declaration_list' then
          return y
        end
      end
    end
  end
  return nil
end

local function members_of(path, line, want)
  local st = uv.fs_stat(path)
  local info = vim.fn.getbufinfo(path)[1]
  local key = 'M\0' .. path .. '\0' .. line .. '\0' .. tostring(want)
  local stamp = tostring(st and st.mtime.sec or -1) .. ':'
      .. tostring(info and info.changedtick or 0)
  local hit = cache_get(key, stamp)
  if hit then
    return hit.v
  end
  local root, source = ts_tree(path)
  if not root then
    return nil
  end
  local node = find_type_node(root, line)
  if node and want then
    -- the file may have drifted since the last F2: if the type sitting on
    -- that line is a different one, look the wanted name up instead
    local nn = node:field('name')[1]
    local got = nn and ntext(nn, source) or nil
    if got and got ~= want then
      local alt
      local function walk(n)
        if alt then
          return
        end
        if TYPE_NODES[n:type()] then
          local x = n:field('name')[1]
          if x and ntext(x, source) == want then
            alt = n
          end
        end
        for c in n:iter_children() do
          walk(c)
        end
      end
      walk(root)
      node = alt
    end
  end
  if not node then
    return nil
  end
  local kind = TYPE_NODES[node:type()] or 'type'
  local nn = field1(node, 'name')
  local body
  for c in node:iter_children() do
    local ct = c:type()
    if ct == 'field_declaration_list' or ct == 'enumerator_list' then
      body = c
      break
    end
  end
  local out = {}
  if body then
    for c in body:iter_children() do
      local ct = c:type()
      if ct == 'field_declaration' then
        local names = field_names(c, source)
        local inner = #names == 0 and anon_body(c) or nil
        if inner then
          -- anonymous struct/union: its fields are members of THIS type
          for f in inner:iter_children() do
            if f:type() == 'field_declaration' then
              local ns = field_names(f, source)
              out[#out + 1] = {
                name = #ns > 0 and table.concat(ns, ', ') or '(anonymous)',
                text = ntext(f, source):gsub('%s+', ' '),
                line = f:start() + 1,
              }
            end
          end
        else
          out[#out + 1] = {
            name = #names > 0 and table.concat(names, ', ') or '(anonymous)',
            text = ntext(c, source):gsub('%s+', ' '),
            line = c:start() + 1,
          }
        end
      elseif ct == 'enumerator' then
        local n = field1(c, 'name')
        out[#out + 1] = {
          name = n and ntext(n, source) or ntext(c, source),
          text = ntext(c, source):gsub('%s+', ' '),
          line = c:start() + 1,
        }
      end
    end
  end
  local alias
  if #out == 0 then
    if node:type() == 'type_definition' then
      alias = type_of_node(field1(node, 'type'), source)
    elseif TYPE_NODES[node:type()] and not body and nn then
      alias = { kind = kind, name = ntext(nn, source) }
    end
  end
  local res = { kind = kind, name = nn and ntext(nn, source) or nil, alias = alias,
    line = node:start() + 1, members = out,
    text = (ntext(node, source):match('^[^\n]*') or ''):gsub('%s+$', '') }
  cache_put(key, stamp, { v = res })
  return res
end

-- the function_definition containing `line`
local function fn_node_at(root, line)
  local row = line - 1
  local found
  local function walk(node)
    local sr, _, er, _ = node:range()
    if sr > row or er < row then
      return
    end
    if node:type() == 'function_definition' then
      found = node
    end
    for c in node:iter_children() do
      walk(c)
    end
  end
  walk(root)
  return found
end

-- declaration of `sym` inside the function containing `line` (parameters
-- included) -> { line=, text=, type=, is_param=, fnname=, fns=, fne= }
local function local_decl(bufnr, line, sym)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end
  local okp, trees = pcall(function() return parser:parse() end)
  if not okp or not trees or not trees[1] then
    return nil
  end
  local fn = fn_node_at(trees[1]:root(), line)
  if not fn then
    return nil
  end
  local fnname
  do -- the declarator's innermost identifier is the function name
    local d = field1(fn, 'declarator')
    local function findname(n)
      if not n then
        return nil
      end
      if n:type() == 'identifier' then
        return ntext(n, bufnr)
      end
      for c in n:iter_children() do
        local r = findname(c)
        if r then
          return r
        end
      end
      return nil
    end
    fnname = findname(d)
  end

  local found
  local function scan(n)
    local nt = n:type()
    if nt == 'declaration' or nt == 'parameter_declaration' then
      local tnode = field1(n, 'type')
      local hit = false
      -- walk only the declarator: 'struct msg *p = alloc(N);' declares p,
      -- it does not declare alloc or N
      local function decl_ids(d)
        if not d then
          return
        end
        local dt = d:type()
        if dt == 'identifier' then
          if ntext(d, bufnr) == sym then
            hit = true
          end
          return
        end
        if dt == 'init_declarator' or dt == 'function_declarator'
            or dt == 'array_declarator' or dt == 'pointer_declarator'
            or dt == 'parenthesized_declarator' then
          decl_ids(field1(d, 'declarator') or d:named_child(0))
          return
        end
        for ch in d:iter_children() do
          decl_ids(ch)
        end
      end
      for c in n:iter_children() do
        if c ~= tnode and c:type() ~= 'storage_class_specifier'
            and c:type() ~= 'type_qualifier' then
          decl_ids(c)
        end
      end
      if hit then
        local srow = n:start() + 1
        -- the declaration closest above the cursor wins (shadowing)
        if not found or (srow <= line and srow >= found.line) then
          found = {
            line = srow,
            text = ntext(n, bufnr):gsub('%s+', ' '),
            type = type_of_node(tnode, bufnr),
            type_text = tnode and ntext(tnode, bufnr) or nil,
            is_param = nt == 'parameter_declaration',
          }
        end
      end
    end
    for c in n:iter_children() do
      scan(c)
    end
  end
  scan(fn)
  if found then
    found.fnname = fnname
    found.fns = fn:start() + 1
    found.fne = select(3, fn:range()) + 1
  end
  return found
end

-- 'msg->cmd', 'ctx.id', 'pdev->dev.of_node' under the cursor:
-- -> base identifier name + the field names from the base outward
local function cursor_field(bufnr, line, col)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end
  pcall(function() parser:parse() end)
  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { line - 1, col } })
  if not node or node:type() ~= 'field_identifier' then
    return nil
  end
  local fields = {}
  local cur, depth = node:parent(), 0
  while cur and cur:type() == 'field_expression' and depth < 6 do
    depth = depth + 1
    local f = field1(cur, 'field')
    if f then
      table.insert(fields, 1, ntext(f, bufnr))
    end
    local arg = field1(cur, 'argument')
    while arg and (arg:type() == 'parenthesized_expression'
        or arg:type() == 'pointer_expression'
        or arg:type() == 'subscript_expression'
        or arg:type() == 'cast_expression') do
      arg = field1(arg, 'argument') or arg:named_child(arg:named_child_count() - 1)
    end
    if arg and arg:type() == 'identifier' then
      return ntext(arg, bufnr), fields
    end
    cur = arg
  end
  return nil
end

-- a member by name, tolerating 'int a, b;' style multi-declarators
find_member = function(members, want)
  for _, m in ipairs(members or {}) do
    for one in m.name:gmatch('[%a_][%w_]*') do
      if one == want then
        return m
      end
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- #include support
-- ---------------------------------------------------------------------------

-- the header named on an '#include' line, or nil
include_at = function(buf, line)
  local ok, l = pcall(api.nvim_buf_get_lines, buf, line - 1, line, false)
  l = ok and l[1] or nil
  if not l or not l:match('^%s*#%s*include') then
    return nil
  end
  return l:match('"([^"]+)"') or l:match('<([^>]+)>')
end

-- absolute path of an included header. Cheap and synchronous: the file next
-- to the including one, then the gtags path index, then 'path'.
resolve_include = function(name, srcpath, root)
  local dir = srcpath and vim.fs.dirname(srcpath) or nil
  if dir then
    local p = dir .. '/' .. name
    if uv.fs_stat(p) then
      return p
    end
  end
  if root then
    local prog = global_cmd()
    if prog then
      -- '-P' matches whole paths, so anchor the tail: 'a/b.h' -> '/a/b%.h$'
      local pat = '/' .. name:gsub('([%.%+%-%*%?%[%]%^%$%(%)%%])', '\\%1') .. '$'
      local ok, o = pcall(function()
        return vim.system({ prog, '-P', pat }, { text = true, cwd = root })
          :wait(3000)
      end)
      if ok and o and o.stdout then
        for rel in o.stdout:gmatch('[^\n]+') do
          local p = rel:sub(1, 1) == '/' and rel or (root .. '/' .. rel)
          if uv.fs_stat(p) then
            return p
          end
        end
      end
    end
  end
  local found = vim.fn.findfile(name, vim.o.path)
  if found ~= '' then
    return vim.fn.fnamemodify(found, ':p')
  end
  return nil
end

-- every symbol gtags recorded in one file: { {name=, line=, text=} ... }
local function file_symbols(root, path, cb)
  run_global({ '-a', '-f', path }, root, function(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do
      local name, lno, _, text = l:match('^(%S+)%s+(%d+)%s+(%S+)%s?(.*)$')
      if name then
        out[#out + 1] = { name = name, line = tonumber(lno),
          text = (text or ''):gsub('^%s+', '') }
      end
    end
    table.sort(out, function(a, b) return a.line < b.line end)
    cb(out)
  end, 4000)
end

-- every occurrence of `sym` between two lines of a buffer
local function uses_in_range(bufnr, s_, e_, sym)
  local out = {}
  local lines = api.nvim_buf_get_lines(bufnr, s_ - 1, e_, false)
  local pat = '%f[%w_]' .. sym .. '%f[^%w_]'
  for i, l in ipairs(lines) do
    if l:find(pat) then
      out[#out + 1] = { line = s_ + i - 1, text = l:gsub('^%s+', '') }
      if #out >= 200 then
        break
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- query pipeline (root level)
-- ---------------------------------------------------------------------------

-- mtime is the GTAGS mtime captured when the query STARTED: if the database
-- was rebuilt mid-query the result may mix old and new data, so render it
-- but never cache it
local function finish(gen, sym, root, mtime, data)
  if gen ~= s.gen then
    return
  end
  s.scope = nil
  local t = {
    sym = sym,
    root = root,
    mtime = mtime,
    def = data.def,
    kind = data.refs_kind,
    truncated = data.refs_truncated,
    shown = #data.refs,
    capped = (data.refs_total or 0) >= REF_STREAM_CAP,
    nodes = make_nodes(group_refs(data.refs), nil, sym),
  }
  if gtags_mtime(root) == mtime then
    cache_put('S\0' .. sym .. '\0' .. root, mtime, t)
  end
  s.tree = t
  render_tree()
end

-- a type NAME -> the definition that really has a body. Follows
-- 'typedef struct foo foo_t;' (and typedef-of-typedef) and prefers, among
-- several gtags hits, the one that parses into members.
local function resolve_type_def(gen, root, name, hops, cb)
  run_global({ '--result=ctags-mod', '-a', '-d', '-e', name }, root,
    function(lines)
      if gen ~= s.gen then
        return
      end
      local defs = parse_ctags_mod(lines, 8)
      local best, bestm
      for _, d in ipairs(defs) do
        local m = members_of(d.path, d.line, name)
        if m and m.members and #m.members > 0 then
          best, bestm = d, m
          break
        end
        best = best or d
      end
      if bestm or not best then
        cb(best, bestm, nil)
        return
      end
      if hops > 0 then
        -- an alias: 'typedef struct arpc_msg arpc_msg_t;'
        local nxt = type_from_text(strip_attrs(best.text)
          :gsub('%f[%w_]typedef%f[^%w_]', ''):gsub('%f[%w_]' .. name
            .. '%f[^%w_]%s*;?%s*$', ''))
        if nxt and nxt.name ~= name then
          resolve_type_def(gen, root, nxt.name, hops - 1,
            function(d2, m2, ty2)
              if d2 and m2 then
                cb(d2, m2, ty2 or nxt)
              else
                cb(best, nil, nil)
              end
            end)
          return
        end
      end
      cb(best, nil, nil)
    end, 16)
end

-- follow 'a->b.c': look the type up, parse it, take the next field, repeat
local function resolve_chain(gen, root, ty, fields, i, cb)
  resolve_type_def(gen, root, ty.name, 3, function(tdef, m, ty2)
    if gen ~= s.gen then
      return
    end
    ty = ty2 or ty
    if not tdef then
      cb(nil, ty)
      return
    end
    local hit = m and find_member(m.members, fields[i]) or nil
    if i >= #fields or not hit then
      cb({ def = tdef, type = ty, members = m and m.members or nil,
        member = hit, name = fields[i] })
      return
    end
    local nty = type_from_text(hit.text)
    if not nty then
      cb({ def = tdef, type = ty, members = m and m.members or nil,
        member = hit, name = fields[i] })
      return
    end
    resolve_chain(gen, root, nty, fields, i + 1, cb)
  end)
end

-- show a type (members) or a variable (declaration + its type's members)
local function finish_type(gen, sym, root, opts)
  if gen ~= s.gen then
    return
  end
  local t = {
    sym = sym,
    root = root,
    kind = opts.decl and 'variable' or 'members',
    def = opts.def,
    type = opts.type,
    decl = opts.decl,
    uses = opts.uses,
    fnname = opts.fnname,
    srcpath = opts.srcpath,
    type_note = opts.type_note,
    members_note = opts.members_note,
    focus_member = opts.focus_member,
  }
  -- members are either handed in (the caller already followed typedef
  -- aliases) or parsed straight from the definition
  if opts.members then
    t.members = opts.members
    if #opts.members == 0 then
      t.members_note = t.members_note
        or '(no members — opaque or forward declaration)'
    end
  elseif opts.def then
    local m = members_of(opts.def.path, opts.def.line,
      opts.type and opts.type.name or nil)
    if m then
      t.members = m.members
      if m.name and not (t.type and t.type.name) then
        t.type = { kind = m.kind, name = m.name }
      end
      if #m.members == 0 then
        t.members_note = '(no members — opaque or forward declaration)'
      end
    else
      t.members_note = '(definition moved — press F2 to re-index)'
    end
  end
  s.scope = opts.scope -- variable views are only valid inside one function
  s.note = t.type and ('[' .. t.type.kind .. ' ' .. (t.type.name or sym) .. ']')
      or (t.decl and '[variable]' or nil)
  s.tree = t
  render_tree()
end

-- '#include "foo.h"': the header goes in Definition and the context window
-- shows the file itself; the symbols gtags knows about it follow below
local function finish_header(gen, sym, root, path)
  if gen ~= s.gen then
    return
  end
  local first = ''
  local f = io.open(path, 'r')
  if f then
    first = (f:read('*l') or ''):gsub('%s+$', '')
    f:close()
  end
  local t = {
    sym = sym,
    root = root,
    kind = 'header',
    def = { path = path, line = 1, text = first },
  }
  s.scope = nil
  s.note = '[header]'
  s.tree = t
  render_tree()
  file_symbols(root, path, function(defs)
    if gen ~= s.gen or s.tree ~= t then
      return
    end
    t.defs = defs
    render_tree()
  end)
end

-- manual: explicit request (:RelationView / 'r'), relaxes the guards that
-- keep the automatic cursor path cheap
local function update(sym, srcfile, force, manual, ctx)
  s.sym = sym
  s.as_type = ctx and ctx.buf and api.nvim_buf_is_valid(ctx.buf)
      and wants_type_at(ctx.buf, ctx.line or 1, ctx.col or 0) or false
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

  root_for(srcfile, function(root)
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
    if not force and not (ctx and ctx.buf) then
      -- only the caller tree is cached: type/variable views depend on the
      -- cursor's function, which the key does not capture
      local hit = cache_get('S\0' .. sym .. '\0' .. root, mtime)
      if hit then
        s.note = nil
        s.tree = hit -- expansions done earlier on this tree are kept
        render_tree()
        return
      end
    end
    -- an '#include' line is about a FILE, not a symbol
    if ctx and ctx.buf and api.nvim_buf_is_valid(ctx.buf) then
      local inc = include_at(ctx.buf, ctx.line or 1)
      if inc then
        local path = resolve_include(inc, api.nvim_buf_get_name(ctx.buf), root)
        if path then
          finish_header(gen, inc, root, path)
        else
          s.note = nil
          render_msg(inc, 'header not found: ' .. inc)
        end
        return
      end
    end

    render_msg(sym, 'querying gtags …')

    local max_refs = cfg('max_refs', 1000)
    local data = { refs = {}, refs_kind = 'ref' }
    local pending = 2
    local alive = function() return gen == s.gen end

    local function join()
      pending = pending - 1
      if pending > 0 or gen ~= s.gen then
        return
      end
      local function annotate_and_finish()
        annotate_pool(root, mtime, data.refs, alive, function()
          finish(gen, sym, root, mtime, data)
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
            data.refs_total = lines and #lines or 0
            annotate_and_finish()
          end, REF_STREAM_CAP)
      else
        annotate_and_finish()
      end
    end

    -- the definition decides what the panel shows: a type lists its
    -- members, a local variable its declaration and its type, and anything
    -- else (a function) keeps the caller tree
    run_global({ '--result=ctags-mod', '-a', '-d', '-e', sym }, root,
      function(lines)
        if gen ~= s.gen then
          return
        end
        local defs = parse_ctags_mod(lines, 8)
        local type_def, other_def
        for _, d in ipairs(defs) do
          if def_is_type(d.text, sym) then
            type_def = type_def or d
          else
            other_def = other_def or d
          end
        end
        -- 'struct dma_config' and 'int dma_config(...)' can both exist: the
        -- keyword right before the cursor says which one is meant
        local wants_type = ctx and ctx.buf and api.nvim_buf_is_valid(ctx.buf)
            and wants_type_at(ctx.buf, ctx.line or 1, ctx.col or 0) or false
        if type_def and other_def and not wants_type then
          type_def = nil -- the function is the more useful answer
        end
        local def = type_def or other_def

        if type_def then
          -- an alias ('typedef struct foo foo_t;') has no body of its own
          resolve_type_def(gen, root, sym, 3, function(d, m, ty)
            if gen ~= s.gen then
              return
            end
            finish_type(gen, sym, root, {
              def = d or type_def,
              members = m and m.members or nil,
              type = ty,
            })
          end)
          return
        end

        local have_ctx = ctx and ctx.buf and api.nvim_buf_is_valid(ctx.buf)

        -- 'msg->cmd': resolve through the VARIABLE's type, so the member of
        -- the right struct is shown even when many structs share the name
        if have_ctx then
          local base, fields = cursor_field(ctx.buf, ctx.line or 1, ctx.col or 0)
          local bdecl = base and local_decl(ctx.buf, ctx.line or 1, base) or nil
          local bty = bdecl and (bdecl.type
            or (bdecl.type_text and type_from_text(bdecl.type_text))) or nil
          if bty and fields and #fields > 0 then
            local srcpath = api.nvim_buf_get_name(ctx.buf)
            local decl_row = { path = srcpath, line = bdecl.line,
              text = bdecl.text, is_param = bdecl.is_param, name = base }
            resolve_chain(gen, root, bty, fields, 1, function(res, failed)
              if gen ~= s.gen then
                return
              end
              if not res then
                finish_type(gen, sym, root, { decl = decl_row, type = failed,
                  type_note = '(no definition of ' .. (failed and failed.name
                    or '?') .. ' in GTAGS)' })
                return
              end
              finish_type(gen, sym, root, {
                def = res.def,
                members = res.members,
                type = res.type,
                decl = decl_row,
                focus_member = res.name,
                fnname = bdecl.fnname,
                srcpath = srcpath,
                scope = { buf = ctx.buf, s = bdecl.fns or bdecl.line,
                  e = bdecl.fne or bdecl.line },
                uses = uses_in_range(ctx.buf, bdecl.fns or bdecl.line,
                  bdecl.fne or bdecl.line, sym),
              })
            end)
            return
          end
        end

        local decl = have_ctx and local_decl(ctx.buf, ctx.line or 1, sym) or nil
        if decl then
          local srcpath = api.nvim_buf_get_name(ctx.buf)
          local uses = uses_in_range(ctx.buf, decl.fns or decl.line,
            decl.fne or decl.line, sym)
          local ty = decl.type
              or (decl.type_text and type_from_text(decl.type_text))
          local opts = {
            decl = { path = srcpath, line = decl.line, text = decl.text,
              is_param = decl.is_param },
            type = ty,
            uses = uses,
            fnname = decl.fnname,
            srcpath = srcpath,
            scope = { buf = ctx.buf, s = decl.fns or decl.line,
              e = decl.fne or decl.line },
          }
          if not ty then
            opts.type_note = '(plain type: ' ..
              trunc(decl.type_text or decl.text, 40) .. ')'
            finish_type(gen, sym, root, opts)
            return
          end
          resolve_type_def(gen, root, ty.name, 3, function(tdef, m, ty2)
            if gen ~= s.gen then
              return
            end
            opts.def = tdef
            opts.members = m and m.members or nil
            opts.type = ty2 or ty
            if not tdef then
              opts.type_note = '(no definition of ' .. ty.name .. ' in GTAGS)'
            end
            finish_type(gen, sym, root, opts)
          end)
          return
        end

        -- an enum constant (gtags records those) or any member whose own
        -- line gtags indexed: show the type it belongs to, focused on it
        if def then
          local m = members_of(def.path, def.line)
          if m and m.members and #m.members > 0
              and find_member(m.members, sym) then
            local owner = find_member(m.members, sym)
            if owner.line == def.line or m.line ~= def.line then
              finish_type(gen, sym, root, {
                def = { path = def.path, line = m.line, text = m.text },
                type = { kind = m.kind, name = m.name },
                focus_member = sym,
              })
              return
            end
          end
        end

        s.note = nil
        data.def = def
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
        data.refs_total = lines and #lines or 0
        join()
      end, REF_STREAM_CAP)
  end)
end

-- ---------------------------------------------------------------------------
-- panel actions
-- ---------------------------------------------------------------------------

local function pick_src_win()
  if s.src_win and s.src_win ~= s.ctx_win and api.nvim_win_is_valid(s.src_win)
      and api.nvim_win_get_tabpage(s.src_win) == api.nvim_get_current_tabpage()
  then
    return s.src_win
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == '' and b ~= s.buf and w ~= s.ctx_win then
      return w
    end
  end
  return nil
end

-- jump the edit window to loc = {path, line, sym?, col?}: with `col` the
-- position is taken as-is, otherwise the symbol is located on that line
local function jump_to(loc, peek)
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
  -- land exactly on the referenced symbol (re-located if the file drifted)
  local line, col
  if loc.col then
    line, col = loc.line, loc.col
  else
    line, col = locate(buf, loc.line, loc.sym)
  end
  api.nvim_win_call(win, function()
    pcall(api.nvim_win_set_cursor, win, { line, col })
    vim.cmd('normal! zz')
  end)
  if not peek then
    api.nvim_set_current_win(win)
  end
end

function A.jump(peek)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local item = s.items[lnum]
  if item and item.loc then
    jump_to(item.loc, peek)
  end
end

-- double click in the preview: take the edit window to exactly the line and
-- column the preview cursor is on
function A.ctx_jump()
  if not (s.ctx_win and api.nvim_win_is_valid(s.ctx_win)) then
    return
  end
  local f = s.ctx_file
  if not f then
    return
  end
  local m = vim.fn.getmousepos()
  if m and m.winid == s.ctx_win and m.line and m.line > 0 then
    pcall(api.nvim_win_set_cursor, s.ctx_win,
      { m.line, math.max(0, (m.column or 1) - 1) })
  end
  local pos = api.nvim_win_get_cursor(s.ctx_win)
  jump_to({ path = f.path, line = pos[1] + (f.off or 0), col = pos[2] })
end

-- double click in the list: jump to the CLICKED line, not to wherever the
-- cursor happened to be (getmousepos is authoritative for the click)
function A.mouse_jump(peek)
  local m = vim.fn.getmousepos()
  if m and m.winid == s.win and m.line and m.line > 0 then
    pcall(api.nvim_win_set_cursor, s.win, { m.line, 0 })
  end
  A.jump(peek)
end

-- Back / forward = the jumplist, exactly like <C-o> / <C-i> (our own jumps
-- land there too). From the panel they move the source window, since a
-- jumplist inside the list itself would mean nothing; the preview walks its
-- own <C-]> stack instead.
local function jumplist_step(lhs)
  local cur = api.nvim_get_current_win()
  local win = cur
  if s.buf and api.nvim_win_get_buf(cur) == s.buf then
    win = pick_src_win()
  end
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  -- ':normal! <C-i>' does not move the jumplist forward, so feed the key
  -- with the target window current and hand the focus straight back
  local keys = api.nvim_replace_termcodes(lhs, true, false, true)
  if win == cur then
    api.nvim_feedkeys(keys, 'nx', false)
    return
  end
  api.nvim_set_current_win(win)
  api.nvim_feedkeys(keys, 'nx', false)
  if api.nvim_win_is_valid(cur) then
    api.nvim_set_current_win(cur)
  end
end

function A.back()
  if s.ctx_win and api.nvim_get_current_win() == s.ctx_win then
    ctx_tag_back()
    return
  end
  jumplist_step('<C-o>')
end

function A.forward()
  if s.ctx_win and api.nvim_get_current_win() == s.ctx_win then
    return -- the preview stack has no forward step
  end
  jumplist_step('<C-i>')
end

-- expand/collapse the caller node under the cursor.
-- mode: 'toggle' | 'expand' | 'collapse'
function A.toggle(mode)
  if s.tree and not s.tree.nodes then
    return -- a type/variable view has no expandable nodes
  end
  local lnum = api.nvim_win_get_cursor(0)[1]
  local item = s.items[lnum]
  local nd = item and item.node
  if not nd or nd.loading then
    return
  end
  if nd.expanded and mode ~= 'expand' then
    nd.expanded = false
    render_tree()
  elseif not nd.expanded and mode ~= 'collapse' and nd.expandable then
    -- deeper exploration should survive cursor moves: pin automatically
    s.pinned = true
    if nd.children then
      nd.expanded = true
      render_tree()
    else
      nd.loading = true
      render_tree()
      local t = s.tree
      local alive = function() return s.tree == t end
      fetch_callers(t.root, t.mtime, nd.name, alive, function(refs)
        nd.loading = false
        nd.children = make_nodes(group_refs(refs), nd, t.sym)
        nd.expanded = true
        if s.tree == t then
          render_tree()
        end
      end)
    end
  else
    return
  end
  if nd.line then
    pcall(api.nvim_win_set_cursor, 0, { nd.line, 0 })
  end
end

-- expand the whole visible tree, breadth-first, bounded by
-- g:relationview_max_depth / g:relationview_max_nodes
function A.expand_all()
  local t = s.tree
  if not t or t.expanding or not t.nodes then
    return
  end
  s.pinned = true
  t.expanding = true
  local maxdepth = cfg('max_depth', 6)
  local maxnodes = cfg('max_nodes', 300)
  local total = 0
  local queue = {}
  local alive = function() return s.tree == t end

  local function absorb(nodes, depth)
    for _, nd in ipairs(nodes) do
      total = total + 1
      if depth < maxdepth and nd.expandable and not nd.cycle then
        queue[#queue + 1] = { nd, depth }
      end
    end
  end
  absorb(t.nodes, 1)

  local function step()
    while true do
      if not alive() then
        t.expanding = nil
        return
      end
      if total >= maxnodes then
        t.expanding = nil
        render_tree()
        vim.notify(string.format('RelationView: %d nodes — stopped '
          .. '(g:relationview_max_nodes)', total))
        return
      end
      local entry = table.remove(queue, 1)
      if not entry then
        t.expanding = nil
        render_tree()
        return
      end
      local nd, depth = entry[1], entry[2]
      if nd.children then
        nd.expanded = true
        absorb(nd.children, depth + 1)
      else
        nd.loading = true
        fetch_callers(t.root, t.mtime, nd.name, alive, function(refs)
          nd.loading = false
          if not alive() then
            t.expanding = nil
            return
          end
          nd.children = make_nodes(group_refs(refs), nd, t.sym)
          nd.expanded = true
          absorb(nd.children, depth + 1)
          render_tree() -- progressive feedback
          step()
        end)
        return
      end
    end
  end
  update_header()
  step()
end

-- export the currently expanded tree as a self-contained HTML graph
-- (Source Insight style boxes, root on the left, callers to the right)
local GRAPH_CSS = [[
body{font:13px/1.45 'SF Mono',Menlo,Consolas,monospace;background:#f4f6f9;
  color:#1c2733;padding:28px}
h1{font:600 15px -apple-system,'Segoe UI',sans-serif;margin:0 0 4px}
p.meta{font:11px -apple-system,'Segoe UI',sans-serif;color:#7b8898;
  margin:0 0 20px}
.node{display:flex;align-items:center;position:relative;padding:4px 0}
.box{border:1px solid #6f8db4;background:#fff;border-radius:4px;
  padding:5px 10px;box-shadow:1px 1px 3px rgba(30,50,80,.18);
  white-space:nowrap;position:relative;z-index:1}
.box.root{background:#2f66b3;border-color:#2f66b3;color:#fff}
.box.root .loc{color:#cfe0f5}
.box.cycle{border-style:dashed;color:#9a6b1f}
.box.leaf{border-color:#b6c2d2;color:#5a6a7d}
.fn{font-weight:600;display:block}
.loc{display:block;font-size:11px;color:#7b8898}
.kids{display:flex;flex-direction:column;justify-content:center;
  margin-left:36px;position:relative}
.kids::before{content:'';position:absolute;left:-36px;top:50%;width:18px;
  height:1px;background:#8fa3bd}
.kids>.node::before{content:'';position:absolute;left:-18px;top:50%;
  width:18px;height:1px;background:#8fa3bd}
.kids>.node::after{content:'';position:absolute;left:-18px;top:0;bottom:0;
  width:1px;background:#8fa3bd}
.kids>.node:first-child::after{top:50%}
.kids>.node:last-child::after{bottom:50%}
.kids>.node:only-child::after{display:none}
]]

local function html_escape(x)
  return (tostring(x):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

function A.graph()
  local t = s.tree
  if not t or not t.nodes then
    vim.notify('RelationView: no caller tree to export', vim.log.levels.WARN)
    return
  end
  local function rel(p)
    if p:sub(1, #t.root + 1) == t.root .. '/' then
      return p:sub(#t.root + 2)
    end
    return p
  end
  local function box(label, loc, cls)
    return string.format(
      '<div class="box %s"><span class="fn">%s</span><span class="loc">%s</span></div>',
      cls or '', html_escape(label), html_escape(loc or ''))
  end
  local function emit(nd)
    local loc = string.format('%s:%d', rel(nd.site.path), nd.site.line)
    local kids = ''
    if nd.expanded and nd.children and #nd.children > 0 then
      local ks = {}
      for _, c in ipairs(nd.children) do
        ks[#ks + 1] = emit(c)
      end
      kids = '<div class="kids">' .. table.concat(ks) .. '</div>'
    end
    local cls = nd.cycle and 'cycle' or (not nd.expandable and 'leaf' or '')
    local label = nd.label .. (nd.cycle and ' ↺' or '')
        .. (#nd.sites > 1 and (' (x' .. #nd.sites .. ')') or '')
    return '<div class="node">' .. box(label, loc, cls) .. kids .. '</div>'
  end

  local kids = {}
  for _, nd in ipairs(t.nodes) do
    kids[#kids + 1] = emit(nd)
  end
  local defloc = t.def and string.format('%s:%d', rel(t.def.path), t.def.line)
      or '(no definition)'
  local html = table.concat({
    '<!doctype html><html><head><meta charset="utf-8">',
    '<title>callers of ' .. html_escape(t.sym) .. '</title>',
    '<style>', GRAPH_CSS, '</style></head><body>',
    '<h1>Callers of ' .. html_escape(t.sym) .. '</h1>',
    '<p class="meta">' .. html_escape(t.root) .. ' — generated by RelationView'
    .. ' (expand more nodes in nvim to widen the graph)</p>',
    '<div class="node">', box(t.sym, defloc, 'root'),
    #kids > 0 and ('<div class="kids">' .. table.concat(kids) .. '</div>') or '',
    '</div></body></html>',
  }, '\n')

  local dir = vim.fn.stdpath('cache')
  vim.fn.mkdir(dir, 'p')
  local path = dir .. '/relationview-' .. t.sym .. '.html'
  vim.fn.writefile(vim.split(html, '\n', { plain = true }), path)
  local ok = pcall(vim.ui.open, path)
  vim.notify('RelationView graph: ' .. path .. (ok and '' or ' (open manually)'))
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
  if s.ctx_win and api.nvim_win_is_valid(s.ctx_win)
      and api.nvim_win_get_tabpage(s.ctx_win) == api.nvim_get_current_tabpage()
  then
    api.nvim_win_close(s.ctx_win, false)
  end
  s.ctx_win = nil
  s.ctx_last = nil
  s.ctx_stack = {}
  if target and api.nvim_win_is_valid(target) then
    api.nvim_win_close(target, false)
  end
  if s.win == target or (s.win and not api.nvim_win_is_valid(s.win)) then
    s.win = nil
  end
  if s.timer then
    s.timer:stop()
  end
  if s.ctx_timer then
    s.ctx_timer:stop()
  end
  kill_procs()
end

-- toggle the Source Insight style context window under/beside the panel
function A.toggle_ctx()
  if ctx_visible() then
    api.nvim_win_close(s.ctx_win, false)
    s.ctx_win = nil
    s.ctx_last = nil
    s.ctx_stack = {}
  elseif ensure_ctx() then
    update_context()
  end
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
  local wbuf = api.nvim_win_get_buf(win)
  local file = api.nvim_buf_get_name(wbuf)
  if file ~= '' then
    local cpos = api.nvim_win_get_cursor(win)
    update(s.sym, file, true, true,
      { buf = wbuf, line = cpos[1], col = cpos[2] })
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
  -- the context window is a preview: resting the cursor on a symbol there
  -- must never rebuild the relation tree
  if s.ctx_win and api.nvim_get_current_win() == s.ctx_win then
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
  if not is_symbol(sym) then
    return
  end
  local cline = api.nvim_win_get_cursor(0)[1]
  local ccol = api.nvim_win_get_cursor(0)[2]
  local as_type = wants_type_at(buf, cline, ccol)
  if sym == s.sym and as_type == (s.as_type or false) then
    -- 'ret' in another function is a different variable: only skip while
    -- the cursor stays inside the range the current view was built for
    local r = s.scope
    if not r or (r.buf == buf and cline >= r.s and cline <= r.e) then
      return
    end
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
    if win ~= s.ctx_win then
      s.src_win = win -- jumps go to real source windows, never the preview
    end
    local cpos = api.nvim_win_get_cursor(win)
    update(sym, file, false, false,
      { buf = buf, line = cpos[1], col = cpos[2] })
  end))
end

api.nvim_create_autocmd('CursorHold', { group = group, callback = on_hold })
api.nvim_create_autocmd('ColorScheme',
  { group = group, callback = set_highlights })

local function open_and_query(arg)
  panel_open()
  local buf = api.nvim_get_current_buf()
  local sym = (arg and arg ~= '') and arg or vim.fn.expand('<cword>')
  local file = api.nvim_buf_get_name(buf)
  local explicit = arg ~= nil and arg ~= ''
  if vim.bo[buf].buftype == '' and file ~= '' and is_symbol(sym, explicit) then
    local cur = api.nvim_get_current_win()
    if cur ~= s.ctx_win then
      s.src_win = cur
    end
    local cpos = api.nvim_win_get_cursor(cur)
    update(sym, file, false, true,
      { buf = buf, line = cpos[1], col = cpos[2] })
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

api.nvim_create_user_command('RelationViewGraph', function()
  A.graph()
end, { desc = 'Export the relation tree as an HTML graph' })

-- open the panel on startup. Runs after every other VimEnter handler (so
-- the tagbar/NERDTree layout is already in place), never steals focus, and
-- does NOT query anything yet: the first time the cursor rests on a symbol
-- fills it in. Skipped without a UI (headless scripts), in diff mode and in
-- git's editor sessions. Set g:relationview_auto_open = 0 to keep it closed.
local function auto_open()
  if vim.g.rv_auto_opened or cfg('auto_open', 1) == 0 then
    return
  end
  if vim.o.diff or #api.nvim_list_uis() == 0 then
    return
  end
  local ft = vim.bo.filetype
  if ft == 'gitcommit' or ft == 'gitrebase' or ft == 'help' then
    return
  end
  vim.g.rv_auto_opened = true
  vim.schedule(function()
    if panel_visible() then
      return
    end
    local prev = api.nvim_get_current_win()
    panel_open()
    if s.buf and api.nvim_buf_line_count(s.buf) <= 1 then
      render_msg(nil, 'move the cursor onto a symbol in a source window')
    end
    if api.nvim_win_is_valid(prev) then
      api.nvim_set_current_win(prev)
    end
  end)
end

api.nvim_create_autocmd({ 'VimEnter', 'UIEnter' },
  { group = group, callback = auto_open })

-- Used by the <2-LeftMouse> mapping in .vimrc: when the cursor sits on an
-- '#include' line, open that header in this window and report it as handled
-- so the mapping does not fall through to <C-]>.
function _G.relationview_open_include()
  local buf = api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' then
    return false
  end
  local pos = api.nvim_win_get_cursor(0)
  local inc = include_at(buf, pos[1])
  if not inc then
    return false
  end
  local file = api.nvim_buf_get_name(buf)
  local dir = file ~= '' and vim.fs.dirname(file) or vim.fn.getcwd()
  local done = false
  root_for(file ~= '' and file or (dir .. '/x'), function(root)
    local path = resolve_include(inc, file, root)
    if path then
      pcall(vim.cmd, [[normal! m']])
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
      done = true
    else
      vim.notify('RelationView: header not found: ' .. inc,
        vim.log.levels.WARN)
      done = true
    end
  end)
  vim.wait(3000, function() return done end, 20)
  return true
end

if vim.fn.maparg('<F3>', 'n') == '' then
  vim.keymap.set('n', '<F3>', '<Cmd>RelationViewToggle<CR>',
    { desc = 'RelationView toggle' })
end


