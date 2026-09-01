-- relationview.lua - Source Insight style "Relation Window" for nvim.
--
-- Shows the Definition and an expandable multi-depth CALLER TREE of the
-- symbol under the cursor in real time, backed by GNU Global (gtags) -
-- the same GTAGS database that F2 (mktags.sh) already creates.
--
--   F3                  toggle the relation window (was "Empty")
--   :RelationView [sym] open the window and show relations of sym/<cword>
--   :RelationViewToggle same as F3
--
-- Inside the panel:
--   <Enter> jump to the call site   o  jump but keep focus in the panel
--   <Space> expand/collapse the caller under the cursor ( + / - work too)
--   *  expand the whole tree (bounded by max_depth/max_nodes)
--   g  export the current tree as an HTML graph and open it in a browser
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
-- (source windows are untouched) and <C-t> returns along its own stack.
--
-- Options (set in .vimrc, all optional):
--   g:relationview_position   'bottom' (default) or 'right'
--   g:relationview_height     panel height for 'bottom'  (default 12)
--   g:relationview_width      panel width  for 'right'   (default 60)
--   g:relationview_auto       1: update as the cursor moves (default 1)
--   g:relationview_debounce   idle debounce in ms         (default 250)
--   g:relationview_max_refs   max references per level    (default 200)
--   g:relationview_max_depth  depth limit of '*'          (default 6)
--   g:relationview_max_nodes  node limit of '*'           (default 300)
--   g:relationview_context    1: open the context window with the panel
--                             (default 1; 'c' toggles it at runtime)
--   g:relationview_context_height  context height, 'right' layout (default 14)
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
  ctx_ph = nil,       -- placeholder buffer for an empty context window
  ctx_last = nil,     -- last location shown in the context window
  ctx_timer = nil,    -- context update debounce timer
  ctx_stack = {},     -- <C-]> jump stack of the context window (<C-t> pops)
  ctx_bound = nil,     -- buffer currently carrying the context <C-]>/<C-t>
  warned = false,
}

local A = {}          -- panel actions (jump/close/pin/...), defined below
local render_tree     -- forward declarations
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

local MAX_ENCLOSE_FILES = 40
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
  local max_refs = cfg('max_refs', 200)
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
    end, max_refs + 200)
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
  api.nvim_set_hl(0, 'RvHeader', { link = 'Title', default = true })
  api.nvim_set_hl(0, 'RvHint', { link = 'Comment', default = true })
  api.nvim_set_hl(0, 'RvSection', { link = 'Label', default = true })
  api.nvim_set_hl(0, 'RvMarker', { link = 'Special', default = true })
  api.nvim_set_hl(0, 'RvName', { link = 'Function', default = true })
  api.nvim_set_hl(0, 'RvLoc', { link = 'Directory', default = true })
  api.nvim_set_hl(0, 'RvDim', { link = 'Comment', default = true })
  api.nvim_set_hl(0, 'RvTree', { link = 'Comment', default = true })

  local function bmap(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  bmap('<CR>', function() A.jump(false) end, 'RelationView: jump')
  bmap('o', function() A.jump(true) end, 'RelationView: peek')
  bmap('<Space>', function() A.toggle('toggle') end, 'RelationView: expand/collapse')
  bmap('+', function() A.toggle('expand') end, 'RelationView: expand')
  bmap('-', function() A.toggle('collapse') end, 'RelationView: collapse')
  bmap('*', function() A.expand_all() end, 'RelationView: expand whole tree')
  bmap('g', function() A.graph() end, 'RelationView: export HTML graph')
  bmap('c', function() A.toggle_ctx() end, 'RelationView: toggle context window')
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
    vim.cmd('keepalt botright vertical ' .. cfg('width', 90) .. 'split')
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
  if cfg('context', 1) ~= 0 then
    ensure_ctx()
  end
  return win
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
  local flags = {}
  if s.pinned then flags[#flags + 1] = 'PINNED' end
  if not s.auto then flags[#flags + 1] = 'auto:off' end
  local tail = #flags > 0 and ('  [' .. table.concat(flags, ', ') .. ']') or ''
  return {
    '◆ ' .. (sym or '(none)') .. tail .. (note and ('  — ' .. note) or ''),
    '  [⏎]jump [o]peek [␣]open/close [*]all [g]graph [p]pin [r]refresh [q]close',
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

local function ctx_placeholder()
  if s.ctx_ph and api.nvim_buf_is_valid(s.ctx_ph) then
    return s.ctx_ph
  end
  local b = api.nvim_create_buf(false, true)
  pcall(api.nvim_buf_set_name, b, 'RelationView-Context')
  vim.bo[b].bufhidden = 'hide'
  vim.bo[b].swapfile = false
  api.nvim_buf_set_lines(b, 0, -1, false,
    { '(move the cursor in the relation list to preview a location here)' })
  vim.bo[b].modifiable = false
  s.ctx_ph = b
  return b
end

local function ctx_visible()
  return s.ctx_win ~= nil and api.nvim_win_is_valid(s.ctx_win)
      and api.nvim_win_get_tabpage(s.ctx_win) == api.nvim_get_current_tabpage()
end

-- open the context window attached to the panel: below the tree for the
-- 'right' layout, beside it for the 'bottom' layout
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
      vim.cmd('noautocmd rightbelow ' .. cfg('context_height', 30) .. 'split')
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
  api.nvim_win_set_buf(ctx, ctx_placeholder())
  local wo = vim.wo[ctx]
  wo.number = true
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

local show_context -- forward: used by the context <C-]> handler below

-- <C-]> / <C-t> inside the context window: follow definitions and come
-- back WITHOUT touching the source windows or the relation tree. The
-- mappings are buffer-local and re-applied whenever a buffer is shown in
-- the context window, so they never leak into normal editing.
local function ctx_tag_jump()
  if not ctx_visible() or api.nvim_get_current_win() ~= s.ctx_win then
    return
  end
  local sym = vim.fn.expand('<cword>')
  if not is_symbol(sym, true) then
    return
  end
  local buf = api.nvim_get_current_buf()
  local file = api.nvim_buf_get_name(buf)
  if file == '' then
    return
  end
  local pos = api.nvim_win_get_cursor(s.ctx_win)
  get_root(vim.fs.dirname(file), function(root)
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
          { path = file, line = pos[1], col = pos[2], sym = sym })
        s.ctx_last = nil -- this is a manual jump, not a list preview
        show_context({ path = d.path, line = d.line, sym = sym })
      end, 8)
  end)
end

local function ctx_tag_back()
  if not ctx_visible() or api.nvim_get_current_win() ~= s.ctx_win then
    return
  end
  local prev = table.remove(s.ctx_stack)
  if not prev then
    vim.notify('RelationView context: jump stack is empty')
    return
  end
  s.ctx_last = nil
  local buf = vim.fn.bufadd(prev.path)
  if not pcall(api.nvim_win_set_buf, s.ctx_win, buf) then
    return
  end
  api.nvim_win_call(s.ctx_win, function()
    pcall(api.nvim_win_set_cursor, s.ctx_win, { prev.line, prev.col })
    vim.cmd('normal! zz')
  end)
  pcall(function()
    vim.wo[s.ctx_win].winbar = ' ' ..
      (basename(prev.path) .. ':' .. prev.line):gsub('%%', '%%%%')
  end)
end

-- the maps live on the buffer only while the context window has focus, so
-- the same file opened in a normal window keeps the global <C-]> (:Gtags)
local function ctx_unbind()
  local buf = s.ctx_bound
  s.ctx_bound = nil
  if buf and api.nvim_buf_is_valid(buf) then
    pcall(vim.keymap.del, 'n', '<C-]>', { buffer = buf })
    pcall(vim.keymap.del, 'n', '<C-t>', { buffer = buf })
  end
end

local function ctx_bind()
  if not ctx_visible() or api.nvim_get_current_win() ~= s.ctx_win then
    return
  end
  local buf = api.nvim_win_get_buf(s.ctx_win)
  if s.ctx_bound == buf then
    return
  end
  ctx_unbind()
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  s.ctx_bound = buf
  vim.keymap.set('n', '<C-]>', ctx_tag_jump,
    { buffer = buf, nowait = true, desc = 'RelationView context: goto definition' })
  vim.keymap.set('n', '<C-t>', ctx_tag_back,
    { buffer = buf, nowait = true, desc = 'RelationView context: jump back' })
end

api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
  group = group,
  callback = function()
    if s.ctx_win and api.nvim_get_current_win() == s.ctx_win then
      ctx_bind()
    elseif s.ctx_bound then
      ctx_unbind()
    end
  end,
})

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
  local buf = vim.fn.bufadd(loc.path)
  if not pcall(api.nvim_win_set_buf, s.ctx_win, buf) then
    return
  end
  local line, col = locate(buf, loc.line, loc.sym)
  api.nvim_win_call(s.ctx_win, function()
    pcall(api.nvim_win_set_cursor, s.ctx_win, { line, col })
    vim.cmd('normal! zz')
  end)
  local label = basename(loc.path) .. ':' .. line
      .. (loc.sym and ('  ◆ ' .. loc.sym) or '')
  pcall(function()
    vim.wo[s.ctx_win].winbar = ' ' .. label:gsub('%%', '%%%%')
  end)
  ctx_bind() -- the shown buffer changed; keep <C-]>/<C-t> on it
end

-- preview the location under the panel cursor (falls back to the
-- definition of the current symbol)
update_context = function()
  if not ctx_visible() then
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
  local function rel(p)
    if p:sub(1, #t.root + 1) == t.root .. '/' then
      return p:sub(#t.root + 2)
    end
    return p
  end

  -- pass 1: collect the three columns of every row so they can be padded
  -- to a common width (symbol | file:line | source text)
  local rows = {}      -- {kind='row', sym=, loc=, text=, item=, node=}
                       -- or {kind='raw', text=}
  local function raw(text)
    rows[#rows + 1] = { kind = 'raw', text = text }
  end
  local function row(symcol, path, line, text, item)
    rows[#rows + 1] = { kind = 'row', sym = symcol,
      loc = string.format('%s:%d', rel(path), line),
      text = text, item = item }
    return rows[#rows]
  end

  raw('')
  raw(section_line('Definition'))
  if t.def then
    row('  ' .. t.sym, t.def.path, t.def.line, t.def.text,
      { loc = { path = t.def.path, line = t.def.line, sym = t.sym } })
  else
    raw('  (no definition)')
  end

  local title = t.kind == 'symbol'
      and 'References (undefined symbol)' or 'Callers'
  raw('')
  raw(section_line(title, #t.nodes))
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
          loc = { path = nd.site.path, line = nd.site.line, sym = nd.ref_sym } })
      r.node = nd
      if nd.expanded and nd.children then
        emit(nd.children, prefix .. (last and '   ' or '│  '))
      end
    end
  end
  emit(t.nodes, '  ')

  if t.truncated and t.truncated > 0 then
    -- lower bound: the query is capped, the real total may be larger
    raw(string.format('  … %d+ more refs  (:Gtags -r %s)', t.truncated, t.sym))
  end

  -- pass 2: size the columns to the widest entry, capped so the source
  -- text still gets room in a narrow panel
  local wsym, wloc = 0, 0
  for _, r in ipairs(rows) do
    if r.kind == 'row' then
      wsym = math.max(wsym, vim.fn.strwidth(r.sym))
      wloc = math.max(wloc, vim.fn.strwidth(r.loc))
    end
  end
  local avail = (s.win and api.nvim_win_is_valid(s.win))
      and api.nvim_win_get_width(s.win) or 80
  wsym = math.min(wsym, math.max(24, math.floor(avail * 0.45)))
  wloc = math.min(wloc, math.max(16, math.floor(avail * 0.35)))

  local lines = header(t.sym)
  local items = {}
  for _, r in ipairs(rows) do
    if r.kind == 'raw' then
      lines[#lines + 1] = r.text
    else
      lines[#lines + 1] = string.format('%s  %s │ %s',
        pad(trunc_w(r.sym, wsym), wsym), pad(trunc_tail(r.loc, wloc), wloc),
        trunc(r.text, 200))
      items[#lines] = r.item
      if r.node then
        r.node.line = #lines
      end
    end
  end
  render(lines, items)
  vim.schedule(update_context)
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
  local t = {
    sym = sym,
    root = root,
    mtime = mtime,
    def = data.def,
    kind = data.refs_kind,
    truncated = data.refs_truncated,
    nodes = make_nodes(group_refs(data.refs), nil, sym),
  }
  if gtags_mtime(root) == mtime then
    cache_put('S\0' .. sym .. '\0' .. root, mtime, t)
  end
  s.tree = t
  render_tree()
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
        s.tree = hit -- expansions done earlier on this tree are kept
        render_tree()
        return
      end
    end
    render_msg(sym, 'querying gtags …')

    local max_refs = cfg('max_refs', 200)
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
            annotate_and_finish()
          end, max_refs + 200)
      else
        annotate_and_finish()
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

function A.jump(peek)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local item = s.items[lnum]
  local loc = item and item.loc
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
  -- land exactly on the referenced symbol (re-located if the file drifted)
  local line, col = locate(buf, loc.line, loc.sym)
  api.nvim_win_call(win, function()
    pcall(api.nvim_win_set_cursor, win, { line, col })
    vim.cmd('normal! zz')
  end)
  if not peek then
    api.nvim_set_current_win(win)
  end
end

-- expand/collapse the caller node under the cursor.
-- mode: 'toggle' | 'expand' | 'collapse'
function A.toggle(mode)
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
  if not t or t.expanding then
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
  if not t then
    vim.notify('RelationView: no tree to export', vim.log.levels.WARN)
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
  ctx_unbind()
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
    ctx_unbind()
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
    if win ~= s.ctx_win then
      s.src_win = win -- jumps go to real source windows, never the preview
    end
    update(sym, file, false, false)
  end))
end

api.nvim_create_autocmd('CursorHold', { group = group, callback = on_hold })

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

api.nvim_create_user_command('RelationViewGraph', function()
  A.graph()
end, { desc = 'Export the relation tree as an HTML graph' })

if vim.fn.maparg('<F3>', 'n') == '' then
  vim.keymap.set('n', '<F3>', '<Cmd>RelationViewToggle<CR>',
    { desc = 'RelationView toggle' })
end
