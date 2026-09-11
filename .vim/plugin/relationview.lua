-- relationview.lua - Source Insight style "Relation Window" for nvim.
--
-- Shows, in real time, what the symbol under the cursor is:
--   * a function          -> definition, an expandable multi-depth CALLER TREE
--                            and, below it, a flat CALLS list: what this
--                            function calls, read out of its body with
--                            treesitter. d cycles which direction is the
--                            expandable tree (both -> callers -> calls).
--                            g:relationview_relation picks the default.
--   * a struct/union/enum -> definition. The member list is folded away by
--                            default (kernel structs have dozens); set
--                            g:relationview_members = 1 to list them. The
--                            one member you selected is still shown.
--   * a variable          -> its declaration in the enclosing function
--                           (parameters included), the definition of its
--                           type, and its uses inside that function
-- Backed by GNU Global (gtags) - the same GTAGS database that F2
-- (mktags.sh) already creates - plus treesitter for the members and for
-- resolving a variable to its type.
--
--   F3                  cycle the layout:
--                         relation + context -> relation only ->
--                         context only -> off
--                       g:relationview_cycle 로 순서와 개수를 정하고,
--                       :RelationViewMode <이름> 으로 바로 고를 수도 있다
--   :RelationView [sym] open the window and show relations of sym/<cword>
--   :RelationViewToggle same as F3
--   :RelationViewBoth   both directions at once (the default)
--   :RelationViewCalls  the Calls direction as an expandable tree
--
-- Inside the panel:
--   <Enter> jump to the call site   o  jump but keep focus in the panel
--   double click            jump to the clicked entry in the edit window
--   mouse button 4 / 5      back / forward, like <C-o> / <C-i>
--   d       cycle direction: both -> Callers -> Calls (SI's Relation window
--           switches direction the same way; 'both' shows the other
--           direction as a flat list you can jump into but not expand)
--   <Space> expand/collapse the caller under the cursor ( + / - work too)
--   *  expand the whole tree (bounded by max_depth/max_nodes)
--   x  export the current tree as an HTML graph and open it in a browser
--      (not 'g': that would break 'gg')
--   c  toggle the context window (Source Insight style: shows the source
--      around the location under the cursor, attached to the panel)
--   p  pin (freeze) current symbol            r  refresh (drop cache)
--   C-n / C-p  next / previous item in the list, previewed in the context
--              window; the edit window does not move (works from any
--              window - including from inside the preview itself - and
--              falls back to :cnext/:cprevious with no list)
--   In the context window C-] (and a double click) follows the symbol under
--   the cursor inside that window - including a parameter or a local, whose
--   declaration is found in the function being previewed; C-t walks back.
--   C-c unpins the panel (:RelationViewUnpin); C-] in an edit window opens
--   the definition in the CONTEXT window, moves the focus there and switches
--   the panel to that symbol (pinned), C-t walks back and hands the focus to
--   the edit window again.
--   Without the preview window the edit window takes its role: C-] jumps
--   there (builtin, so C-t returns) while the panel still follows and pins,
--   C-n/C-p move the edit window through the list, and a :Gtags search shows
--   its first hit there. With the panel closed too, both go to quickfix.
--   Browsing the list (click, j/k, C-n/C-p) pins the panel; double click
--   takes the edit window there; resting on a symbol in a source window for
--   g:relationview_unpin_delay ms (3s) unpins and follows the cursor again.
--   C-CR (:RelationViewJump) jumps the edit window to the selected item from
--   any window - the way a C-n/C-p walk ends.
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
--   g:relationview_path_truncate  1: cut the path column to the window
--                             width, eliding the front ('…'); default 0
--                             shows the whole path and lets the line run
--                             past the edge instead
--   g:relationview_db_base    'outer' (default): always ask the outermost
--                             index that holds this file, so the answer does
--                             not depend on where nvim was started;
--                             'cwd': the old behaviour
--   g:relationview_path_base  'root' (default): paths relative to the
--                             outermost indexed project root, so the same
--                             file always reads the same no matter where
--                             nvim was started; 'pwd': relative to :pwd;
--                             'abs': absolute
--   g:relationview_full_path  1: absolute paths (old option, same as
--                             path_base = 'abs')
--   g:relationview_show_text  1: also show the source line (default 0:
--                             only the symbol and its file:line)
--   g:relationview_auto_open  1: open something on startup (default 1)
--   g:relationview_startup    what to open then: 'context' (default),
--                             'both', 'relation' or 'off'
--   g:relationview_cycle      the order <F3> walks, e.g.
--                             ['context', 'off'] or ['both', 'off']
--                             (default ['both','relation','context','off'])
--   g:relationview_context    1: open the context window with the panel
--                             (default 1; 'c' toggles it at runtime)
--   g:relationview_context_height  context height, 'right' layout (default 25,
--                             capped so the tree keeps at least 8 rows)
--   g:relationview_context_width   context width, 'bottom' layout (default 0 = half)
--   g:relationview_context_position  'panel' (default: a split inside the
--                             panel) or 'right'/'left' (a window of its own
--                             beside the edit window, so the panel keeps the
--                             whole bottom); context_width applies to both
--   g:relationview_unpin_delay ms on one symbol in a source window before a
--                             pinned panel follows the cursor again (3000)
--   g:relationview_capture_gtags  1: ':Gtags -d/-r/-s/-g' lists its results in
--                             the panel while it is open, instead of the
--                             quickfix window (default 1)
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
  -- 'callers' (누가 부르나) 또는 'callees' (무엇을 부르나). SI 의 Relation
  -- window 방향 전환에 해당하고, 패널에서 d 로 바꾼다. nil 이면 아직 사용자가
  -- 바꾼 적이 없다는 뜻이고, 그때는 g:relationview_relation 을 그때그때 읽는다.
  relation = nil,
  gen = 0,            -- generation counter, stale async results are dropped
  timer = nil,        -- debounce timer
  items = {},         -- panel line number -> {node=?, loc={path,line,sym}}
  cache = {},         -- key -> {mtime=..., data=...}
  cache_n = 0,
  roots = {},         -- dir -> gtags root (positive results only)
  procs = {},         -- in-flight vim.system handles of the current query
  inflight = {},      -- filedefs key -> list of waiting callbacks
  mode = nil,         -- <F3> 가 도는 상태: both/relation/context/off
  ctx_alone = false,  -- 패널 없이 context 만 떠 있다
  ctx_sym = nil,      -- 그때 따라가고 있는 심볼
  ctx_win = nil,      -- context window (Source Insight style)
  ctx_ph = nil,       -- the scratch buffer the preview renders into
  ctx_file = nil,     -- {path=, stamp=, off=, n=} currently copied into it
  ctx_last = nil,     -- last location shown in the context window
  ctx_timer = nil,    -- context update debounce timer
  ctx_stack = {},     -- <C-]> jump stack of the context window (<C-t> pops)
  ctx_fwd = {},       -- <C-t> 로 되돌린 것들 (<C-i> 가 다시 따라간다)
  note = nil,         -- header suffix, e.g. '[struct arpc_msg]'
  shown = nil,        -- symbol of the last render (cursor reset on change)
  ctx_hl_buf = nil,   -- buffer currently carrying the context highlight
  scope = nil,        -- function range a variable view is valid for
  rendered_w = nil,   -- panel geometry the current layout was computed for
  rendered_h = nil,
  rs_timer = nil,     -- resize debounce
  as_type = false,    -- the current view read the symbol as a type usage
  warned = false,
}

-- 관계 창이 보여 주는 방향. 질의 시점에 읽는다(로드 시점이 아니라). 그래야
-- 설정 파일 뒤쪽에서 g:relationview_relation 을 바꿔도 반영된다.
--
--   'both'    (기본) Callers 트리 + Calls 평면 목록을 한 패널에
--   'callers' 누가 이 심볼을 부르나 - 확장 가능한 트리
--   'callees' 이 심볼이 무엇을 부르나 - 확장 가능한 트리
--
-- SI 의 Relation window 는 방향을 버튼으로 바꾸지만, 한쪽만 보이면 반대쪽이
-- 있다는 걸 모르고 지나치기 쉽다. 그래서 기본은 양쪽을 같이 띄우고, d 로
-- 한쪽을 트리로 펼치도록 했다.
local function relation_mode()
  local v = s.relation or cfg('relation', 'both')
  if v == 'callees' or v == 'callers' or v == 'both' then
    return v
  end
  return 'both'
end

-- 확장 가능한 트리로 그릴 방향
local function relation()
  return relation_mode() == 'callees' and 'callees' or 'callers'
end

-- 'both' 에서 덧붙는 두 번째(평면) 섹션의 방향. 아니면 nil.
local function relation_extra()
  return relation_mode() == 'both' and 'callees' or nil
end

-- 캐시 키. 방향과 'both' 여부가 다르면 다른 트리다.
local function tree_key(sym, root, rel, extra)
  return 'S\0' .. ((rel or relation()) == 'callees' and 'C\0' or '')
      .. (((extra ~= nil) and extra or relation_extra()) and 'B\0' or '')
      .. sym .. '\0' .. root
end


-- sky blue for the symbol under the panel cursor, and for the same symbol
-- in the context window ('termguicolors' is off in this setup, so the
-- cterm colours are the ones that actually paint)
local NS_SYM = api.nvim_create_namespace('RelationViewSym')
-- the symbol a jump landed on, coloured until the cursor moves away
local NS_JUMP = api.nvim_create_namespace('RelationViewJumpSym')
local NS_CTX = api.nvim_create_namespace('RelationViewCtxSym')

-- every colour the panel uses, in one place. A ':colorscheme' wipes user
-- highlights, so this runs again on every ColorScheme event. All groups are
-- 'default', so anything set in .vimrc keeps winning.
local function set_highlights()
  local light = vim.o.background == 'light'
  local hl = {
    RvHeader = { link = 'Title' },
    RvHint = { link = 'Comment' },
    RvSection = { link = 'Label' },
    RvMarker = { link = 'Special' },
    RvName = { link = 'Function' },
    RvLoc = { link = 'Directory' },
    RvDim = { link = 'Comment' },
    RvTree = { link = 'Comment' },
    -- pale sky blue disappears on a white background: on a light theme the
    -- same role is played by a strong blue
    RvCursorSym = light and { fg = '#005f87', ctermfg = 24, bold = true }
        or { fg = '#87d7ff', ctermfg = 117, bold = true },
    -- where a jump landed. This one carries its own background, so the same
    -- sky blue box reads on either theme
    RvCtxSym = { fg = '#101820', bg = '#87d7ff', ctermfg = 16,
      ctermbg = 117, bold = true },
    -- the row the panel cursor is on: a visible bar, not the barely-there
    -- one most colorschemes ship
    RvCursorLine = light and { bg = '#d0d0d0', ctermbg = 252 }
        or { bg = '#4e5561', ctermbg = 240 },
    RvCursorLineNr = light
        and { fg = '#005f87', bg = '#d0d0d0', ctermfg = 24, ctermbg = 252,
          bold = true }
        or { fg = '#87d7ff', bg = '#4e5561', ctermfg = 117, ctermbg = 240,
          bold = true },
  }
  for name, spec in pairs(hl) do
    spec.default = true
    api.nvim_set_hl(0, name, spec)
  end
end
set_highlights()

local A = {}          -- panel actions (jump/close/pin/...), defined below
local render_tree     -- forward declarations
local update_header
local pick_src_win
local local_decl    -- treesitter: the declaration of a local/parameter
local member_jump   -- 'msg->cmd': where that member is declared
local update        -- the panel's own refresh, defined further down
local render_rows
local source_text
local ts_tree       -- treesitter: a file's parse tree (defined further down)
local include_at
local resolve_include
local hl_cursor_row
local find_member
local ensure_ctx
local update_context
-- context 만 켠 모드에서 커서를 따라간다. 실제 함수는 파일 아래쪽에 있고
-- 여기서 이름만 잡아 둔다 - CursorHold 훅이 그보다 위에서 등록되기 때문에,
-- 여기에 선언이 없으면 훅 안의 이름이 전역(nil)으로 잡혀 아무 일도 하지
-- 않는다.
local ctx_follow
local group = api.nvim_create_augroup('RelationView', { clear = true })

-- The database lives in a hidden directory in the project root
-- ('<root>/.tags/'), see ~/.vim/plugin/autoindex.lua. global(1) only finds it
-- through GTAGSROOT/GTAGSDBPATH, so every child process started here gets
-- them explicitly instead of relying on whatever the environment holds.
local function db_dir()
  local d = vim.g.autoindex_dbdir
  if d == nil then
    d = '.tags'
  end
  if d == '' or d == '.' then
    return nil
  end
  return (tostring(d):gsub('/+$', ''))
end

-- global reads '<root>/GTAGS' before '<root>/$GTAGSOBJDIR/GTAGS', so a project
-- holding both is answered from the root one; follow that for the mtime the
-- cache keys off (see autoindex.lua for the same rule)
local function db_path(root)
  if uv.fs_stat(root .. '/GTAGS') then
    return root
  end
  local d = db_dir()
  return d and (root .. '/' .. d) or root
end

-- global(1) finds '<dir>/$GTAGSOBJDIR/GTAGS' as it walks up, so one value
-- works for every project (autoindex.lua exports it for the session too)
local function db_env()
  local d = db_dir()
  return d and { GTAGSOBJDIR = d } or nil
end

-- nearest directory at or above `dir` that holds a database
local function db_root(dir)
  local d, hidden = dir, db_dir()
  while d and d ~= '' do
    if (hidden and uv.fs_stat(d .. '/' .. hidden .. '/GTAGS'))
        or uv.fs_stat(d .. '/GTAGS') then
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

-- global compares an absolute argument against the real path of the project,
-- so a tree reached through a symlink ('/tmp' -> '/private/tmp') is rejected
-- as 'out of the source project'. Relative to the root it always matches.
local function rel_to(root, path)
  if root and path:sub(1, #root + 1) == root .. '/' then
    return path:sub(#root + 2)
  end
  local rp = root and uv.fs_realpath(root)
  local pp = uv.fs_realpath(path)
  if rp and pp and pp:sub(1, #rp + 1) == rp .. '/' then
    return pp:sub(#rp + 2)
  end
  return path
end

local function gtags_mtime(root)
  local st = uv.fs_stat(db_path(root) .. '/GTAGS')
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
  local env = db_env()

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

  local ok, ret = pcall(vim.system, full,
    { cwd = cwd, env = env, stdout = on_stdout },
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

-- 가장 바깥쪽 색인 루트.
--
-- db_root 는 위로 올라가다 처음 만나는 GTAGS 에서 멈춘다. 그런데 이 트리에는
-- 중첩 프로젝트가 있다(d5_qnx_hyp 와 그 안의 kernel/common 이 각각 .tags 를
-- 갖는다). 그래서 어디서 vim 을 켰느냐에 따라 같은 파일이
--   kernel/common/include/sound/soc.h   (바깥에서 켰을 때)
--   include/sound/soc.h                 (kernel/common 안에서 켰을 때)
-- 로 달리 보였다. 경로 표시는 켠 위치와 무관하게 늘 같아야 하므로, 여기서는
-- 멈추지 않고 끝까지 올라가 가장 바깥의 색인 루트를 쓴다.
local outer_cache = {}

local function outer_root(dir)
  if not dir or dir == '' then
    return nil
  end
  local hit = outer_cache[dir]
  if hit ~= nil then
    return hit or nil
  end
  local hidden = db_dir()
  local best, d = nil, dir
  local home = vim.fn.expand('~')
  while d and d ~= '' and d ~= '/' do
    if (hidden and uv.fs_stat(d .. '/' .. hidden .. '/GTAGS'))
        or uv.fs_stat(d .. '/GTAGS') then
      best = d
    end
    if d == home then
      break -- 홈보다 위로는 올라가지 않는다
    end
    local parent = vim.fs.dirname(d)
    if not parent or parent == d then
      break
    end
    d = parent
  end
  outer_cache[dir] = best or false
  return best
end

-- find the GTAGS project root for a directory (async; only positive results
-- are cached, so the panel recovers right after the user indexes with F2)
local function get_root(dir, cb)
  local hit = s.roots[dir]
  if hit then
    cb(hit)
    return
  end
  local root = db_root(dir)
  if root then
    s.roots[dir] = root
  end
  cb(root)
end

-- 이 색인이 그 파일을 담고 있나. '<root>/.tags/files' 를 읽어 본다.
--   true  담고 있다   false 담고 있지 않다   nil  알 수 없다
-- (목록 파일이 없는 auto 모드에서는 알 수 없다 - 그때는 담고 있다고 본다)
local list_cache = {}

local function indexed_in(root, path)
  if path:sub(1, #root + 1) ~= root .. '/' then
    return false
  end
  local lf = root .. '/' .. (db_dir() or '.tags') .. '/files'
  local st = uv.fs_stat(lf)
  if not st then
    return nil
  end
  local key = ('%d:%d'):format(st.mtime.sec, st.size)
  local c = list_cache[root]
  if not c or c.key ~= key then
    local ok, lines = pcall(vim.fn.readfile, lf)
    if not ok then
      return nil
    end
    local set = {}
    for _, l in ipairs(lines) do
      if l ~= '' then
        set[l] = true
      end
    end
    c = { key = key, set = set }
    list_cache[root] = c
  end
  return c.set[path:sub(#root + 2)] == true
end

-- 어느 데이터베이스에 물을 것인가.
--
-- 이 트리에는 프로젝트 안에 프로젝트가 있다(d5_qnx_hyp 와 그 안의
-- kernel/common 이 각각 .tags 를 갖는다). 어느 쪽에 묻느냐로 같은 심볼의
-- 답이 달라진다 - 실제로 참조가 4개로도 3개로도 나왔다.
--
-- 기본은 '가장 바깥 색인'이다: 어디서 vim 을 켜든 같은 답이 나온다. 다만
-- 바깥 색인이 그 파일을 담고 있지 않으면(바깥은 kernel/common 파일을
-- 39개만, 중첩은 407개를 담는다) 거기 물어도 아무것도 안 나오므로, 그때는
-- 예전 방식으로 물러선다: 작업 디렉터리의 색인, 그다음 파일 자신의 것.
--
-- 예전 주석의 이유도 그대로 유효하다: 하위 디렉터리에 몇 달 전 만들어 둔
-- GTAGS 가 남아 있으면 파일 자신의 디렉터리에서 찾는 것이 그걸 집어 들어
-- 다른 파일, 다른 줄 번호를 답한다.
--
--   let g:relationview_db_base = 'cwd'   " 예전처럼 작업 디렉터리 기준
local function root_for(path, cb)
  if tostring(cfg('db_base', 'outer')) ~= 'cwd' then
    local o = outer_root(vim.fs.dirname(path))
    if o and indexed_in(o, path) ~= false then
      cb(o)
      return
    end
  end
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
  run_global({ '-a', '-f', rel_to(root, path) }, root, function(lines)
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
-- Tokens that can stand right before the '(' of a signature without being
-- the name of the thing being defined.
local SIG_SKIP = {
  ['if'] = true, ['for'] = true, ['while'] = true, ['switch'] = true,
  ['return'] = true, ['sizeof'] = true, ['do'] = true, ['else'] = true,
  ['void'] = true, ['int'] = true, ['char'] = true, ['long'] = true,
  ['short'] = true, ['unsigned'] = true, ['signed'] = true,
  ['float'] = true, ['double'] = true, ['bool'] = true,
  ['struct'] = true, ['union'] = true, ['enum'] = true,
  ['const'] = true, ['volatile'] = true, ['static'] = true,
  ['extern'] = true, ['inline'] = true, ['typedef'] = true,
  ['register'] = true, ['asm'] = true, ['typeof'] = true,
  ['__typeof__'] = true,
  -- the annotations that sit between the type and the name, or on their own
  -- line under the signature: none of them is ever the name
  ['__attribute__'] = true, ['__attribute'] = true, ['__asm__'] = true,
  ['__acquires'] = true, ['__releases'] = true, ['__must_hold'] = true,
  ['__cond_acquires'] = true, ['__acquire'] = true, ['__release'] = true,
  ['__printf'] = true, ['__scanf'] = true, ['__aligned'] = true,
  ['__section'] = true, ['__alloc_size'] = true, ['__realloc_size'] = true,
  ['__diagnose_as'] = true, ['__no_sanitize'] = true, ['__copy'] = true,
  ['__alias'] = true, ['__assume_aligned'] = true, ['__nonstring'] = true,
  ['__counted_by'] = true, ['__free'] = true, ['__cleanup'] = true,
  ['__used'] = true, ['__weak'] = true, ['__init'] = true, ['__exit'] = true,
}

-- The name of the definition whose body opens at 'brace_line', read off the
-- signature above it. Needed because gtags stops recording definitions
-- after the first unbalanced brace in a file - kernel sources hide those
-- inside an inactive '#ifdef', so they compile and nobody notices - and
-- every function below that point would otherwise have no name to group
-- its callers under. Returns nil for a block that is not a function
-- (a struct body, an initializer: no parameter list above it).
-- The name in front of the OUTERMOST parameter list of 'text', or nil when
-- that list starts further up ('text' begins inside it, i.e. a ')' closes
-- something that was never opened here). Tracking the depth is what keeps
-- the sparse annotations that follow a signature from winning:
--   ') __releases(sl811->lock) __acquires(sl811->lock)' - the name is five
-- lines above, and '__releases' is not it.
-- the identifier ending at byte 'e' (inclusive), or nil. Walks backwards
-- over bytes: no substring is copied, which matters because this runs on
-- machine-generated C whose lines can be thousands of characters wide.
local function word_before(text, e)
  while e >= 1 do
    local b = text:byte(e)
    if b ~= 32 and b ~= 9 then
      break
    end
    e = e - 1
  end
  local last = e
  while e >= 1 do
    local b = text:byte(e)
    local word = b == 95 or (b >= 48 and b <= 57)
        or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
    if not word then
      break
    end
    e = e - 1
  end
  if e >= last then
    return nil -- nothing, or something that is not an identifier
  end
  local b = text:byte(e + 1)
  if b >= 48 and b <= 57 then
    return nil -- a number, not a name
  end
  -- is there anything but whitespace in front of it?
  local bare = true
  local k = e
  while k >= 1 do
    local c = text:byte(k)
    if c ~= 32 and c ~= 9 then
      bare = false
      break
    end
    k = k - 1
  end
  return text:sub(e + 1, last), bare
end

local function decl_name(text)
  -- Does this text close a parenthesis that was opened above it? Then it is
  -- the tail of a parameter list, and any name in it is a PARAMETER:
  --   'ssize_t (*format)(const struct net_device *, char *))' - the ')' at
  -- the end belongs to 'netdev_show(' three lines up. Checking that FIRST
  -- matters: the type in front of a function-pointer parameter would
  -- otherwise be picked up before the stray ')' is ever reached.
  local depth, i = 0, 1
  while true do
    local p = text:find('[()]', i)
    if not p then
      break
    end
    if text:byte(p) == 40 then
      depth = depth + 1
    else
      depth = depth - 1
      if depth < 0 then
        return nil
      end
    end
    i = p + 1
  end
  depth, i = 0, 1
  while true do
    local p = text:find('[()]', i)
    if not p then
      break
    end
    if text:byte(p) == 41 then
      depth = depth - 1
    else
      if depth == 0 then
        -- was there a return type in front of the name? An identifier
        -- standing alone with its parameter list ('__must_hold(&x->lock)',
        -- a macro-generated definition) is a weaker answer than one that
        -- looks like a signature.
        local pre, bare = word_before(text, p - 1)
        if pre and not SIG_SKIP[pre] then
          return pre, bare
        end
      end
      depth = depth + 1
    end
    i = p + 1
  end
  return nil
end

local function sig_name(lines, brace_line)
  local text = ''
  local weak, weak_line = nil, nil
  for k = brace_line, math.max(1, brace_line - 12), -1 do
    local raw = lines[k]
    if not raw or raw:match('^%s*#') then
      break
    end
    local l = raw:gsub('/%*.-%*/', ' '):gsub('//.*$', '')
    if k < brace_line then
      if l:match('%*/%s*$') or l:match('^%s*%*') then
        break -- a comment block: a name inside it is not this signature
      end
      if l:match('[;}{]%s*$') then
        break -- that line ends a previous statement
      end
    end
    if #text + #l > 4000 then
      break -- no hand-written signature is this wide; stop before it costs
    end
    text = l .. ' ' .. text
    local nm, bare = decl_name(text)
    if nm and not bare then
      return nm, k, false
    end
    if nm and not weak then
      weak, weak_line = nm, k -- keep looking for a real signature above it
    end
  end
  if weak then
    return weak, weak_line, true
  end
  return nil
end

-- Does this line start a definition at file scope? Used to recover from a
-- brace count that has gone wrong: a signature in the first column while
-- the count still says we are inside a function means we are not, and the
-- range that is open has run away. Kernel C indents everything inside a
-- function, so a signature at column 0 is a reliable marker - much more so
-- than a '}' there, which is often just a hand-unindented block or a local
-- initializer written '};'.
local function starts_definition(lines, i)
  local l = lines[i]
  if not l or not l:match('^[%a_]') then
    return false
  end
  local code = l:gsub('/%*.-%*/', ' '):gsub('//.*$', '')
  if code:match(';%s*$') or code:match('^[%a_][%w_]*%s*:') then
    return false -- a statement, a declaration, or a label
  end
  return decl_name(code) ~= nil
end

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
  local def_by_name = {} -- first definition of each name, for the owner above
  for _, d in ipairs(defs) do
    if d.name and def_by_name[d.name] == nil then
      def_by_name[d.name] = d
    end
  end
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
      -- One unbalanced brace - typically inside an '#ifdef' that is never
      -- compiled, so it never breaks a build and nobody notices - used to
      -- leave a range open to the end of the file and blame every reference
      -- below it on that one function (tcc_asrc_drv.c:1240 is exactly
      -- that). A definition starting in the first column says the count is
      -- wrong: close the runaway here and carry on from file scope.
      if depth > 0 and raw:match('^[%a_]') and starts_definition(lines, i) then
        if open_start then
          ranges[#ranges + 1] = { s = open_start, e = i - 1,
            name = open_owner and open_owner.name or nil }
          open_start, open_owner = nil, nil
        end
        depth = 0
      end
      local opens = select(2, code:gsub('{', ''))
      local closes = select(2, code:gsub('}', ''))
      if depth == 0 and opens > 0 then
        -- Who owns this block? The name in front of the parameter list is
        -- the reliable answer: gtags misses a function whose parameters
        -- span two lines and records the PARAMETERS instead ('name', 'root',
        -- 'fn' for 'static void eeh_pe_report(const char *name, ... \n
        -- eeh_report_fn fn, ...)'), and the last definition before the '{'
        -- is then a parameter name. Blocks that are not functions (a struct
        -- body, an initializer) have no parameter list above them, and
        -- those still belong to the definition that precedes them.
        --
        -- A definition owns at most ONE top-level brace range: an anonymous
        -- block after it (e.g. a static variable initializer that gtags
        -- does not record) must not be blamed on it again.
        local nm, nline, weak = sig_name(lines, i)
        -- never reach back into the previous range
        local floor_ = ranges[#ranges] and (ranges[#ranges].e + 1) or 1
        -- A name read off a real signature beats the definition list, which
        -- misses a function whose parameters span two lines and records the
        -- PARAMETERS instead. A name standing alone with its parameter list
        -- (a macro-generated definition) does not: gtags usually knows what
        -- that macro produced.
        local take = nm and (not weak or not (last_def and not used[last_def]))
        if take then
          local d = def_by_name[nm]
          open_owner = (d and not used[d]) and d or { name = nm, line = nline }
          if d then
            used[d] = true
          end
          open_start = math.max(math.min(nline or i, i), floor_)
        elseif last_def and not used[last_def] then
          open_owner = last_def
          used[last_def] = true
          -- include the signature line(s) above the opening brace
          open_start = math.max(math.min(last_def.line, i), floor_)
        else
          open_owner = nil
          open_start = i
        end
        -- everything the definition list recorded inside the signature (the
        -- parameters, the annotations) is consumed with it, or the next
        -- block would be blamed on one of them
        for k = di - 1, 1, -1 do
          local d = defs[k]
          if d.line < open_start then
            break
          end
          used[d] = true
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
-- 참조가 걸린 파일들의 정의 목록을 한 번에 받아 둔다.
--
-- 예전에는 파일마다 'global -f <file>' 을 하나씩 띄웠다. 질의 자체는 싸지만
-- 프로세스를 띄우는 값이 파일당 ~2ms 라, 참조 파일이 100개면 그것만으로
-- 200ms 가 나간다. global -f 는 파일을 여러 개 받으므로 한 번에 물어보고
-- 경로별로 나눠 담는다 (서버 실측: 60개를 개별로 125ms, 배치로 12ms).
--
-- get_filedefs 와 같은 캐시('F\0'..path)와 같은 inflight 큐를 쓰므로, 배치가
-- 도는 중에 누가 같은 파일을 물어봐도 여기서 함께 답한다.
--   let g:relationview_batch_filedefs = 0   " 예전처럼 파일마다 하나씩
local BATCH_FILES = 40   -- 인자 줄 길이 한계를 넘지 않게 끊는다

local function prefetch_filedefs(root, mtime, paths, cb)
  if cfg('batch_filedefs', 1) == 0 then
    cb()
    return
  end
  local want = {}
  for _, path in ipairs(paths) do
    local key = 'F\0' .. path
    if not cache_get(key, mtime) and not s.inflight[key] then
      want[#want + 1] = path
      s.inflight[key] = {} -- 이 배치가 답한다는 표시
    end
  end
  if #want == 0 then
    cb()
    return
  end
  local chunks = {}
  for i = 1, #want, BATCH_FILES do
    local c = {}
    for j = i, math.min(i + BATCH_FILES - 1, #want) do
      c[#c + 1] = want[j]
    end
    chunks[#chunks + 1] = c
  end
  local left = #chunks
  for _, chunk in ipairs(chunks) do
    local args = { '-a', '-f' }
    for _, path in ipairs(chunk) do
      args[#args + 1] = rel_to(root, path)
    end
    run_global(args, root, function(lines)
      local by = {}
      for _, path in ipairs(chunk) do
        by[path] = {}
      end
      if lines then
        for _, l in ipairs(lines) do
          -- cxref: name line path text. 색인에 없는 파일이면 global 이
          -- 사람이 읽는 문장을 뱉으므로, 우리가 물어본 경로만 받는다.
          local name, lno, fpath = l:match('^(%S+)%s+(%d+)%s+(%S+)')
          if name and by[fpath] then
            local t = by[fpath]
            t[#t + 1] = { name = name, line = tonumber(lno) }
          end
        end
      end
      for _, path in ipairs(chunk) do
        local key = 'F\0' .. path
        local defs = by[path]
        table.sort(defs, function(a, b) return a.line < b.line end)
        if lines then
          cache_put(key, mtime, defs) -- 실패했을 땐 캐시하지 않는다
        end
        local waiters = s.inflight[key] or {}
        s.inflight[key] = nil
        for _, w in ipairs(waiters) do
          w(defs)
        end
      end
      left = left - 1
      if left == 0 then
        cb()
      end
    end, math.min(4000 * #chunk, 120000))
  end
end

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
  -- 파일별 정의 목록을 먼저 한 번에 받아 두면, 아래 루프는 캐시만 읽는다
  local batch = {}
  for i = 1, n do
    batch[i] = order[i]
  end
  prefetch_filedefs(root, mtime, batch, function()
    if not alive() then
      return
    end
    launch()
  end)
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

-- ---------------------------------------------------------------------------
-- callees: the other direction of Source Insight's Relation window
-- ---------------------------------------------------------------------------
-- gtags cannot answer "what does this function call" - GRTAGS is an index of
-- references BY name, not by containing function - but treesitter can: parse
-- the file that defines the symbol, find its function body, and collect the
-- calls in it in source order. Each callee name is then resolved with the
-- same 'global -d' the Definition row uses, so a row points at the callee's
-- own definition and reading top-down works.

-- the function_definition node whose name is 'sym', preferring the one that
-- contains 'line' (a file can define the same name twice under #ifdef)
local function func_body(root_node, source, sym, line)
  local best
  local function name_of(fd)
    local d = fd:field('declarator')[1]
    while d do
      local t = d:type()
      if t == 'identifier' then
        return vim.treesitter.get_node_text(d, source)
      end
      if t == 'function_declarator' or t == 'pointer_declarator'
          or t == 'parenthesized_declarator' or t == 'array_declarator' then
        d = d:field('declarator')[1]
      else
        return nil
      end
    end
    return nil
  end
  local function walk(node)
    if node:type() == 'function_definition' then
      if name_of(node) == sym then
        local sr, _, er, _ = node:range()
        if line and line >= sr + 1 - 2 and line <= er + 1 then
          return node -- the one the definition line points into
        end
        best = best or node
      end
    end
    for ch in node:iter_children() do
      local hit = walk(ch)
      if hit then
        return hit
      end
    end
    return nil
  end
  return walk(root_node) or best
end

-- ts_tree() 의 'source' 는 버퍼 번호이거나 파일 내용이다 (get_node_text 가
-- 둘 다 받는다). 줄 텍스트를 꺼내려면 어느 쪽인지 가려야 하고, 문자열이면
-- 한 번만 쪼개 둔다.
local function line_reader(source)
  if type(source) == 'number' then
    return function(row)
      return (api.nvim_buf_get_lines(source, row, row + 1, false)[1] or '')
    end
  end
  local lines = vim.split(source, '\n', { plain = true })
  return function(row)
    return lines[row + 1] or ''
  end
end

-- every call inside 'body', in source order, grouped by callee name
local function calls_in(body, source, path, sym)
  local order, map = {}, {}
  local text_at = line_reader(source)
  local function add(name, node)
    if not name or name == sym or not is_symbol(name) then
      return
    end
    local sr = select(1, node:range())
    local e = map[name]
    if not e then
      e = { name = name, sites = {} }
      map[name] = e
      order[#order + 1] = e
    end
    if #e.sites < 20 then
      e.sites[#e.sites + 1] = { path = path, line = sr + 1,
        text = text_at(sr):gsub('^%s+', ''), fn = sym }
    end
  end
  local function walk(node)
    local t = node:type()
    if t == 'call_expression' then
      local f = node:field('function')[1]
      if f then
        local ft = f:type()
        if ft == 'identifier' then
          add(vim.treesitter.get_node_text(f, source), f)
        elseif ft == 'field_expression' then
          -- ops->probe(dev): the interesting name is the member
          local m = f:field('field')[1]
          if m then
            add(vim.treesitter.get_node_text(m, source), m)
          end
        elseif ft == 'parenthesized_expression' then
          local inner = f:named_child(0)
          if inner and inner:type() == 'identifier' then
            add(vim.treesitter.get_node_text(inner, source), inner)
          end
        end
      end
    end
    for ch in node:iter_children() do
      walk(ch)
    end
  end
  walk(body)
  return order
end

-- entries for the panel, in the shape group_refs() produces, with each
-- callee's own definition resolved so the row jumps into it
local function fetch_callees_raw(root, mtime, sym, alive, cb, prefer)
  local cap = cfg('max_callees', 200)
  run_global({ '--result=ctags-mod', '-a', '-d', '-e', sym }, root,
    function(lines)
      if not alive() then
        return
      end
      local defs = parse_ctags_mod(lines, 8)
      -- the same name can be defined in several files (a static function per
      -- driver): read the body in the file the query came from
      if prefer and prefer ~= '' then
        table.sort(defs, function(a, b)
          local pa = a.path == prefer and 0 or 1
          local pb = b.path == prefer and 0 or 1
          if pa ~= pb then
            return pa < pb
          end
          return (a.line or 0) < (b.line or 0)
        end)
      end
      local entries
      for _, d in ipairs(defs) do
        local rnode, source = ts_tree(d.path)
        if rnode then
          local body = source and func_body(rnode, source, sym, d.line)
          if body then
            entries = calls_in(body, source, d.path, sym)
            break
          end
        end
      end
      if not entries then
        cb(nil) -- not a function we can read (a macro, a header prototype)
        return
      end
      if #entries > cap then
        local cut = {}
        for i = 1, cap do
          cut[i] = entries[i]
        end
        cut.truncated = #entries - cap
        entries = cut
      end
      -- resolve each callee's definition, a few at a time
      local idx, active, conc = 0, 0, ENCLOSE_CONC
      local function launch()
        if not alive() then
          return
        end
        while active < conc and idx < #entries do
          idx = idx + 1
          local e = entries[idx]
          active = active + 1
          run_global({ '--result=ctags-mod', '-a', '-d', '-e', e.name }, root,
            function(dl)
              local d = parse_ctags_mod(dl or {}, 1)[1]
              if d then
                -- the row points at the definition; the call site stays in
                -- 'sites' so <C-n>/<C-p> can still walk the call sites
                e.def = d
                table.insert(e.sites, 1, { path = d.path, line = d.line,
                  text = d.text, fn = sym })
              end
              active = active - 1
              if active == 0 and idx >= #entries then
                if alive() then
                  cb(entries)
                end
              else
                launch()
              end
            end, 8)
        end
        if #entries == 0 and alive() then
          cb(entries)
        end
      end
      launch()
    end, 8)
end

-- Calls 방향의 결과를 캐시한다.
--
-- 이건 gtags 질의 하나 + 본문 treesitter 파싱 + callee 하나당 정의 해석
-- (spawn N개)이라 함수 하나에 수십 ms 가 든다. relation='both' 가 기본이 된
-- 뒤로는 함수 심볼을 볼 때마다 걸리므로, 같은 심볼로 되돌아올 때 다시 하지
-- 않도록 한다. 키에 prefer 가 들어가는 이유: 같은 이름의 static 함수가 여러
-- 파일에 있으면 어느 파일의 본문을 읽었는지에 따라 결과가 다르다.
--   let g:relationview_callee_cache = 0   " 매번 새로 읽기
local function fetch_callees(root, mtime, sym, alive, cb, prefer)
  if cfg('callee_cache', 1) == 0 then
    fetch_callees_raw(root, mtime, sym, alive, cb, prefer)
    return
  end
  local key = 'E\0' .. sym .. '\0' .. (prefer or '') .. '\0' .. root
  local hit = cache_get(key, mtime)
  if hit ~= nil then
    -- false 는 '함수가 아니라 읽을 본문이 없다'를 캐시한 것이다
    cb(hit ~= false and hit or nil)
    return
  end
  fetch_callees_raw(root, mtime, sym, alive, function(entries)
    if gtags_mtime(root) == mtime then
      cache_put(key, mtime, entries == nil and false or entries)
    end
    cb(entries)
  end, prefer)
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
      " a real lookbehind, not '\zs': RvMarker already matches at the '['
      " and would otherwise consume the position before this rule is tried
      syntax match RvName     /\%(\[[-+…]\] \|↺ \|· \)\@<=\S\+/
      syntax match RvName     /^  \zs\S\+\ze\s\s/
      " the source column may be off (g:relationview_show_text = 0), so the
      " path can be followed by the '│' separator or by end of line
      syntax match RvLoc      /\S\+:\d\+\ze\s*\%(│\|$\)/
      " '(x2)', '(util.h)' and the notes are dim: they are not symbols
      syntax match RvDim      /(no definition)\|(none)\|(x\d\+)\|…\d\++\? more.*\|([^ )]\+\.[^ )]\+)/
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
  bmap('<C-CR>', function() A.jump(false) end, 'RelationView: jump')
  bmap('<C-c>', function() A.unpin() end, 'RelationView: unpin')
  bmap('<C-n>', function() A.step(1) end, 'RelationView: next item')
  bmap('<C-p>', function() A.step(-1) end, 'RelationView: previous item')
  bmap('a', function() A.toggle_auto() end, 'RelationView: toggle auto')
  bmap('d', function() A.toggle_relation() end,
    'RelationView: callers <-> calls')

  -- Source Insight style: moving in the list previews the location under
  -- the cursor in the context window
  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    buffer = buf,
    callback = function()
      hl_cursor_row()
      -- Browsing the list (a mouse click, j/k, C-n/C-p) means "hold this
      -- tree": pin, so a stray cursor move in the edit window cannot
      -- rebuild it under us. Resting on a symbol in a source window for
      -- g:relationview_unpin_delay releases it again (see watch_unpin).
      if not s.rendering and not s.pinned then
        s.pinned = true
        update_header()
      end
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

-- 패널을 열 때 context 도 같이 열까. 'relation only' 모드에서는 열지 않는다.
local function want_ctx()
  if s.mode == 'relation' then
    return false
  end
  return cfg('context', 1) ~= 0
end

local function panel_open()
  if panel_visible() then
    if want_ctx() then
      ensure_ctx()
    end
    return s.win
  end
  local buf = ensure_buf()
  local existing = panel_win_here()
  if existing then
    s.win = existing
    if want_ctx() then
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
  if want_ctx() then
    ensure_ctx()
  end
  return win
end

-- Opening or closing another window (a file tree, quickfix, ...) hands the
-- freed columns to whatever sits next to it - the panel included, and
-- 'winfixwidth' does not stop that. Remember the panel's size the moment a
-- window appears or disappears and put that size back once the layout has
-- settled; anything the user resized by hand is therefore kept as it is.
local function restore_geom(w, h)
  if not (s.win and api.nvim_win_is_valid(s.win)) then
    return
  end
  if cfg('position', 'bottom') == 'right' then
    if w and api.nvim_win_get_width(s.win) ~= w then
      pcall(api.nvim_win_set_width, s.win, w)
    end
  elseif h and api.nvim_win_get_height(s.win) ~= h then
    pcall(api.nvim_win_set_height, s.win, h)
  end
end

-- colour the symbol on the row the panel cursor is on
-- colour `sym` on `line` of `buf` (sky blue, the same as the panel uses)
-- until the cursor moves off it
local function flash_symbol(buf, line, sym)
  if not (buf and api.nvim_buf_is_valid(buf) and line and sym and sym ~= '') then
    return
  end
  pcall(api.nvim_buf_clear_namespace, buf, NS_JUMP, 0, -1)
  local okl, lines = pcall(api.nvim_buf_get_lines, buf, line - 1, line, false)
  local text = okl and lines[1] or nil
  if not text then
    return
  end
  local at, init = nil, 1
  while true do
    local sidx, eidx = text:find(sym, init, true)
    if not sidx then
      break
    end
    local before = sidx > 1 and text:sub(sidx - 1, sidx - 1) or ''
    local after = text:sub(eidx + 1, eidx + 1)
    if not before:match('[%w_]') and not after:match('[%w_]') then
      at = sidx
      break
    end
    init = eidx + 1
  end
  if not at then
    return
  end
  pcall(api.nvim_buf_set_extmark, buf, NS_JUMP, line - 1, at - 1,
    { end_col = at - 1 + #sym, hl_group = 'RvCtxSym' })
  -- the jump itself moves the cursor, so start watching a moment later
  vim.defer_fn(function()
    if not api.nvim_buf_is_valid(buf) then
      return
    end
    api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufLeave' }, {
      buffer = buf,
      once = true,
      callback = function()
        pcall(api.nvim_buf_clear_namespace, buf, NS_JUMP, 0, -1)
      end,
    })
  end, 150)
end

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
  s.rendering = true
  vim.schedule(function() s.rendering = false end)
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
  local mode = relation_mode()
  local dir = mode == 'both' and 'both' or (mode == 'callees' and 'calls' or 'callers')
  return {
    '◆ ' .. (sym or '(none)') .. tail .. (note and ('  — ' .. note) or ''),
    '  [⏎/^⏎]jump [o]peek [␣]open/close [*]all [^n/^p]next/prev [x]graph ' ..
      '[d]dir:' .. dir .. ' [c]ctx [p]pin [r]refresh [q]close',
  }
end

-- rewrite only the two header lines (pin/auto flags changed)
function update_header()
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
local ctx_tag_jump, ctx_tag_back, ctx_tag_forward, ctx_enter_from

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
  -- 뒤로는 <C-t> 와 <C-o> 둘 다 받는다. 편집 창에서 몸에 익은 쪽이 사람마다
  -- 다르고, 여기서 <C-o> 는 어차피 할 일이 없다(파일 버퍼가 아니라 점프
  -- 목록이 비어 있다) - 아무 일도 안 일어나는 키를 남겨 둘 이유가 없다.
  for _, lhs in ipairs({ '<C-t>', '<C-o>' }) do
    vim.keymap.set('n', lhs, function() ctx_tag_back() end,
      { buffer = b, nowait = true, desc = 'RelationView context: jump back' })
  end
  vim.keymap.set('n', '<C-i>', function() ctx_tag_forward() end,
    { buffer = b, nowait = true, desc = 'RelationView context: jump forward' })
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
  vim.keymap.set('n', '<X2Mouse>', function() ctx_tag_forward() end,
    { buffer = b, nowait = true, desc = 'RelationView context: jump forward' })
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

-- projectfiles.lua asks for these: one to sit above the preview, one to put
-- the panel's height back if a new window in that column stole rows from it
-- other plugins land on a symbol too (the ProjectSymbols picker): the same
-- sky blue marker that C-] leaves, so a jump always looks the same
function _G.relationview_flash(buf, line, sym)
  if buf and line and sym then
    pcall(flash_symbol, buf, line, sym)
  end
end

function _G.relationview_panel_win()
  return (s.win and api.nvim_win_is_valid(s.win)) and s.win or nil
end

function _G.relationview_ctx_win()
  return (s.ctx_win and api.nvim_win_is_valid(s.ctx_win)) and s.ctx_win or nil
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
  -- context 만 켜는 모드에서는 패널이 없다. 그때는 'panel' 위치를 쓸 수
  -- 없으니(쪼갤 패널이 없다) 편집 창 옆에 세운다.
  local standalone = s.ctx_alone and not panel_visible()
  if not panel_visible() and not standalone then
    return nil
  end
  local ctx
  local where = cfg('context_position', 'panel')
  if standalone and where ~= 'left' then
    where = 'right'
  end
  if where == 'left' or where == 'right' then
    -- A window of its own, beside the file you are editing, instead of a
    -- split inside the panel: the panel keeps the whole bottom and the
    -- preview gets the full height of the edit area.
    -- the project files view owns the top of the right column: put the
    -- preview under it instead of splitting the edit window again
    local host = pick_src_win()
    if not (host and api.nvim_win_is_valid(host)) then
      return nil
    end
    -- measure before the split: afterwards `host` is already halved
    local host_w = api.nvim_win_get_width(host)
    api.nvim_win_call(host, function()
      vim.cmd('noautocmd ' ..
        (where == 'right' and 'rightbelow' or 'leftabove') .. ' vertical split')
      local w = cfg('context_width', 0)
      if w <= 0 then
        w = math.max(40, math.floor(vim.o.columns / 3))
      end
      -- never leave the file you are editing thinner than the preview
      w = math.min(w, math.max(20, math.floor(host_w / 2)))
      vim.cmd('vertical resize ' .. w)
      ctx = api.nvim_get_current_win()
    end)
  else
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
  end
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
        -- the stack belongs to that window: a reopened preview must not
        -- inherit jumps (and origins) from the closed one
        s.ctx_last = nil
        s.ctx_stack = {}
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
  -- 새로 따라가면 되돌릴 곳은 사라진다 - 점프 목록과 같은 규칙이다
  s.ctx_fwd = {}
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

  -- A parameter or a local variable is in no index; its declaration is in
  -- the function we are looking at. The preview holds only a slice of the
  -- file, which treesitter cannot always parse into a function, so ask the
  -- real file's buffer and then move the preview to the declaration.
  local here = pos[1] + off
  local okb, fbuf = pcall(vim.fn.bufadd, file)
  if okb and fbuf and fbuf > 0 then
    pcall(vim.fn.bufload, fbuf)
    -- 'msg->cmd' first: the member belongs to the base variable's struct,
    -- not to whatever else carries that name (a local, say)
    local taken = member_jump(fbuf, here, pos[2], function(loc)
      table.insert(s.ctx_stack,
        { path = file, line = here, col = pos[2], sym = sym })
      s.ctx_last = nil
      show_context(loc)
      vim.defer_fn(function()
        if ctx_visible() then
          local off2 = (s.ctx_file and s.ctx_file.off) or 0
          flash_symbol(api.nvim_win_get_buf(s.ctx_win), loc.line - off2, loc.sym)
        end
      end, 60)
    end)
    if taken then
      return
    end
    local okd, d = pcall(local_decl, fbuf, here, sym)
    if okd and d and d.line then
      if d.line ~= here then
        table.insert(s.ctx_stack,
          { path = file, line = here, col = pos[2], sym = sym })
        s.ctx_last = nil
        show_context({ path = file, line = d.line, sym = sym })
      end
      vim.defer_fn(function()
        if ctx_visible() then
          local off2 = (s.ctx_file and s.ctx_file.off) or 0
          flash_symbol(api.nvim_win_get_buf(s.ctx_win), d.line - off2, sym)
        end
      end, 60)
      return
    end
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
  -- 어디에서 되돌아왔는지 적어 둔다: <C-i> 가 여기로 다시 온다
  if s.ctx_file then
    local cur = api.nvim_win_get_cursor(s.ctx_win)
    table.insert(s.ctx_fwd, {
      back = prev,
      to = { path = s.ctx_file.path, line = cur[1] + (s.ctx_file.off or 0),
             col = cur[2] },
    })
  end
  s.ctx_last = nil
  -- no 'sym' here on purpose: the recorded line/column is the exact spot,
  -- re-locating the symbol could land back where we just came from
  show_context({ path = prev.path, line = prev.line, col = prev.col or 0 })
  -- the bottom of the stack is the edit window we were sent here from:
  -- walking back past it means going back to that window, not just showing
  -- its line in the preview
  local ow = prev.origin and prev.origin.win
  if ow and api.nvim_win_is_valid(ow) then
    -- only put the cursor back when that window still shows the file we
    -- left: it may have been sent somewhere else since (<CR> here does
    -- exactly that), and a line number from another file is a wrong jump
    if prev.origin.buf and api.nvim_buf_is_valid(prev.origin.buf)
        and api.nvim_win_get_buf(ow) == prev.origin.buf then
      pcall(api.nvim_win_set_cursor, ow, { prev.line, prev.col or 0 })
    end
    pcall(api.nvim_set_current_win, ow)
  end
end

-- <C-i>: <C-t> 로 되돌린 자리를 다시 따라간다 (편집 창의 점프 목록과 같은
-- 짝을 context 창에도 준다 - 되돌리기만 있고 앞으로 가기가 없으면, 한 칸
-- 잘못 되돌렸을 때 처음부터 다시 파고들어야 한다)
ctx_tag_forward = function()
  if not ctx_visible() or api.nvim_get_current_win() ~= s.ctx_win then
    return
  end
  local nxt = table.remove(s.ctx_fwd)
  if not nxt then
    vim.notify('RelationView context: 앞으로 갈 곳이 없습니다')
    return
  end
  table.insert(s.ctx_stack, nxt.back)
  s.ctx_last = nil
  show_context(nxt.to)
end

-- C-] (and \\c) in an EDIT window: show the definition in the context
-- window and move the focus there. The edit window itself stays put - it is
-- the reading window; C-t brings the focus back to it.
ctx_enter_from = function(win, loc, sym)
  if not ctx_visible() then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  local pos = api.nvim_win_get_cursor(win)
  local entry = { origin = { win = win, buf = buf },
    path = api.nvim_buf_get_name(buf), line = pos[1], col = pos[2], sym = sym }
  -- one origin per trip: pressing C-] again in the same edit window replaces
  -- the way back instead of stacking another dead C-t on top of it
  local top = s.ctx_stack[#s.ctx_stack]
  if top and top.origin and top.origin.win == win then
    s.ctx_stack[#s.ctx_stack] = entry
  else
    table.insert(s.ctx_stack, entry)
  end
  s.ctx_last = nil
  if loc then
    show_context(loc)
  end
  pcall(api.nvim_set_current_win, s.ctx_win)
  return true
end

-- Where the ctags snapshot thinks a symbol is. Used when gtags has nothing:
-- the location still belongs in the preview, not in the edit window.
local function tag_loc(sym)
  if #vim.fn.tagfiles() == 0 then
    return nil
  end
  local ok, tl = pcall(vim.fn.taglist, '^' .. vim.fn.escape(sym, '\\.*$^~[]') .. '$')
  if not ok or type(tl) ~= 'table' then
    return nil
  end
  for _, t in ipairs(tl) do
    local path = t.filename
    if path and path ~= '' and uv.fs_stat(path) then
      local line = tonumber(t.cmd)
      if not line then
        -- '/^int foo(void)$/' : find that line in the file
        local pat = tostring(t.cmd):match('^/%^?(.-)%$?/$')
        if pat then
          local okr, lines = pcall(vim.fn.readfile, path, '', 20000)
          if okr then
            for i, l in ipairs(lines) do
              if l:find(pat, 1, true) then
                line = i
                break
              end
            end
          end
        end
      end
      return { path = path, line = line or 1 }
    end
  end
  return nil
end

function A.ctx_jump_from_edit()
  -- 패널이든 미리보기든, 우리 창이 하나라도 떠 있으면 우리가 처리한다.
  --
  -- 예전에는 패널만 봤다. F3 에 'context only' 모드가 생기고 그것이 시작
  -- 기본값이 되면서, 가장 흔한 배치에서 이 함수가 첫 줄에 빠져나갔다 -
  -- <C-]> 가 정의를 context view 에 띄우는 대신 편집 창을 옮기고 quickfix
  -- 를 열었다. 아래 코드는 이미 ctx_visible() 로 두 경우를 갈라 쓰고 있으니
  -- 여기서 막을 이유가 없다.
  if not (panel_visible() or ctx_visible()) then
    return false -- nothing of ours is up: the caller falls back to :Gtags
  end
  local win = api.nvim_get_current_win()
  if win == s.win or win == s.ctx_win then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' then
    return false
  end
  local name = api.nvim_buf_get_name(buf)
  if name == '' then
    return false
  end
  -- an '#include' line is about a file: open the header in the EDIT window
  -- (the panel/preview show what is in it, as they already do)
  if include_at(buf, api.nvim_win_get_cursor(win)[1]) then
    local opened = false
    api.nvim_win_call(win, function()
      opened = _G.relationview_open_include and _G.relationview_open_include()
          or false
    end)
    if opened then
      return true
    end
  end
  local sym = vim.fn.expand('<cword>')
  if not is_symbol(sym, true) then
    return false
  end
  if not ctx_visible() then
    -- panel without a preview: the edit window does the jump (the builtin
    -- one, so the tag stack and C-t keep working) and the panel follows the
    -- symbol, pinned - the same state the preview path leaves behind
    s.pinned = true
    update(sym, name, true, false, nil)
    return false -- the caller performs the jump itself
  end
  -- every dead end below has to land somewhere: fall back to the builtin
  -- tag jump IN THE EDIT WINDOW, or the key would silently do nothing for
  -- anything gtags has no definition for (a macro, a struct member, ...)
  local jump_via_gtags -- forward: used by the retry below
  -- gtags has no definition for this one. With the preview up the answer
  -- still belongs there, never in the edit window:
  --   1. pull the file that defines it into the project and ask gtags again
  --   2. failing that, use the ctags snapshot's location
  --   3. failing that, say so
  -- Without a preview the edit window IS the reading window, so the builtin
  -- tag jump is the right thing there.
  local function fallback(retried)
    if not api.nvim_win_is_valid(win) then
      return
    end
    if not ctx_visible() then
      api.nvim_win_call(win, function()
        pcall(vim.cmd, 'normal! ' ..
          api.nvim_replace_termcodes('<C-]>', true, false, true))
      end)
      return
    end
    -- The ctags snapshot answers in a few milliseconds, so ask it FIRST and
    -- show the definition straight away. Searching the sources for the file
    -- that defines the symbol takes over a second on a kernel tree, so that
    -- runs in the background afterwards - it only enriches the panel (real
    -- callers next time), it must never make the jump wait.
    local loc = tag_loc(sym)
    if loc then
      s.pinned = true
      update(sym, loc.path, true, false, nil)
      ctx_enter_from(win, { path = loc.path, line = loc.line, sym = sym }, sym)
      if not retried and _G.projectfiles_add_for_symbol_async then
        vim.defer_fn(function()
          pcall(_G.projectfiles_add_for_symbol_async, sym, function(n)
            if n and n > 0 and s.sym == sym and panel_visible() then
              update(sym, loc.path, true, false, nil) -- now with callers
            end
          end)
        end, 30)
      end
      return
    end
    if not retried and _G.projectfiles_add_for_symbol_async then
      pcall(_G.projectfiles_add_for_symbol_async, sym, function(n)
        if n and n > 0 then
          jump_via_gtags(true)
        else
          vim.notify('RelationView: ' .. sym .. ' 의 정의를 찾지 못했습니다',
            vim.log.levels.WARN)
        end
      end)
      return
    end
    vim.notify('RelationView: ' .. sym .. ' 의 정의를 찾지 못했습니다',
      vim.log.levels.WARN)
  end
  s.ctx_jump_gen = (s.ctx_jump_gen or 0) + 1
  local gen = s.ctx_jump_gen
  jump_via_gtags = function(retried)
  root_for(name, function(root)
    if gen ~= s.ctx_jump_gen and not retried then
      return -- a newer C-] is on its way: that one wins
    end
    if not root or not ctx_visible() then
      fallback(retried)
      return
    end
    run_global({ '--result=ctags-mod', '-a', '-d', '-e', sym }, root,
      function(lines)
        if gen ~= s.ctx_jump_gen and not retried then
          return
        end
        local d = parse_ctags_mod(lines, 4)[1]
        if not d then
          fallback(retried) -- no gtags definition: let the tag stack try
          return
        end
        if api.nvim_win_is_valid(win) then
          -- the panel follows the jump as well and freezes on it, so the
          -- callers of what you just opened are right there (C-c, or 2s on
          -- a symbol in the edit window, lets it follow the cursor again)
          s.pinned = true
          update(sym, d.path, true, false, nil)
          ctx_enter_from(win, { path = d.path, line = d.line, sym = sym }, sym)
        end
      end, 8)
  end)
  end
  jump_via_gtags(false)
  return true
end

-- the .vimrc <C-]> mapping asks this when nothing of ours handled the key:
-- with a database around the fallback is ':Gtags -d' (quickfix), otherwise
-- the builtin tag jump
function _G.relationview_has_db()
  local name = api.nvim_buf_get_name(0)
  local dir = (name ~= '' and vim.bo.buftype == '')
      and vim.fs.dirname(vim.fn.fnamemodify(name, ':p')) or vim.fn.getcwd()
  return db_root(dir) ~= nil
end

-- A parameter or a local variable is in no index - ctags and gtags only
-- know globals - so C-] on one used to end in 'E426: tag not found'. Its
-- declaration is right here in the enclosing function: take the EDIT window
-- there (the panel/preview show the variable's type by themselves).
function _G.relationview_local_jump()
  local buf = api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' then
    return false
  end
  local sym = vim.fn.expand('<cword>')
  if not is_symbol(sym) then
    return false
  end
  local win = api.nvim_get_current_win()
  local pos = api.nvim_win_get_cursor(0)

  -- a member access resolves through the base variable's type, not by name
  if member_jump(buf, pos[1], pos[2], function(loc)
        if ctx_visible() then
          ctx_enter_from(win, loc, loc.sym)
          vim.defer_fn(function()
            if ctx_visible() then
              local cbuf = api.nvim_win_get_buf(s.ctx_win)
              local off = (s.ctx_file and s.ctx_file.off) or 0
              flash_symbol(cbuf, loc.line - off, loc.sym)
            end
          end, 60)
        elseif api.nvim_win_is_valid(win) then
          api.nvim_win_call(win, function()
            pcall(vim.cmd, [[normal! m']])
            vim.cmd('edit ' .. vim.fn.fnameescape(loc.path))
            pcall(api.nvim_win_set_cursor, win, { loc.line, 0 })
            pcall(vim.cmd, 'normal! zz')
          end)
          flash_symbol(api.nvim_win_get_buf(win), loc.line, loc.sym)
        end
      end) then
    return true
  end

  local ok, d = pcall(local_decl, buf, pos[1], sym)
  if not ok or not d or not d.line then
    return false
  end
  if d.line == pos[1] then
    flash_symbol(buf, d.line, sym)
    return true -- already on the declaration: nothing to jump to, but this
                -- is still 'handled' (do not fall through to a tag error)
  end
  pcall(vim.cmd, [[normal! m']])
  local text = api.nvim_buf_get_lines(buf, d.line - 1, d.line, false)[1] or ''
  local at = text:find(sym, 1, true)
  pcall(api.nvim_win_set_cursor, 0, { d.line, at and (at - 1) or 0 })
  pcall(vim.cmd, 'normal! zz')
  flash_symbol(buf, d.line, sym)
  return true
end

-- the .vimrc <C-]> mapping asks this first and falls back to the builtin
function _G.relationview_ctx_jump()
  return A.ctx_jump_from_edit()
end

-- the .vimrc <C-c> mapping: true when a pin was actually released, so the
-- key can fall through to whatever it meant before (checksymbol.vim)
function _G.relationview_unpin()
  return A.unpin()
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
  -- 미리보기 창 제목도 패널과 같은 기준으로 (render_tree 의 rel 참고)
  local lbase = tostring(cfg('path_base', 'root'))
  if cfg('full_path', 0) ~= 0 then
    lbase = 'abs'
  elseif lbase ~= 'pwd' and lbase ~= 'abs' then
    lbase = 'root'
  end
  local lroot = s.tree and s.tree.root
  if lbase == 'root' and lroot and lroot ~= '' then
    lroot = outer_root(lroot) or lroot
  end
  local shown = loc.path
  if lbase == 'root' and lroot and lroot ~= ''
      and loc.path:sub(1, #lroot + 1) == lroot .. '/' then
    shown = loc.path:sub(#lroot + 2)
  elseif lbase ~= 'abs' then
    shown = vim.fn.fnamemodify(loc.path, ':.')
  end
  local label = shown
      .. ':' .. (line + off) .. (loc.sym and ('  ◆ ' .. loc.sym) or '')
  pcall(function()
    vim.wo[s.ctx_win].winbar = ' ' .. label:gsub('%%', '%%%%')
  end)
end

-- preview the location under the panel cursor (falls back to the
-- definition of the current symbol)
-- force: the user asked for this one (C-n/C-p), so show it even while the
-- focus is inside the preview
update_context = function(force)
  if not ctx_visible() then
    return
  end
  -- while the user is browsing inside the context window (<C-]>/<C-t>), a
  -- late render must not yank the preview back to the list item - but an
  -- explicit step through the list must
  if not force and api.nvim_get_current_win() == s.ctx_win then
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
  -- 경로를 무엇을 기준으로 보여줄까.
  --
  --   'root'  프로젝트 루트 기준 (기본). 이 트리를 만들 때 실제로 질의한
  --           GTAGS 루트다 - 한 데이터베이스에서 나온 줄들이므로 그 루트를
  --           기준으로 삼는 것이 앞뒤가 맞고, 어느 디렉터리에서 vim 을
  --           켜든 같은 파일이 늘 같은 경로로 보인다.
  --   'pwd'   :pwd 기준 (vim 이 '%:.' 로 보여주는 방식). 켠 위치에 따라
  --           달라지고, 바깥 파일은 절대 경로가 된다.
  --   'abs'   절대 경로.
  --
  --   let g:relationview_path_base = 'pwd'
  --
  -- g:relationview_full_path = 1 은 예전 옵션이라 'abs' 로 읽는다.
  local base = tostring(cfg('path_base', 'root'))
  if cfg('full_path', 0) ~= 0 then
    base = 'abs'
  elseif base ~= 'pwd' and base ~= 'abs' then
    base = 'root'
  end
  -- 질의한 루트가 중첩 프로젝트일 수 있으므로 가장 바깥 루트로 올린다
  local troot = (base == 'root' and t.root and t.root ~= '')
      and (outer_root(t.root) or t.root) or nil
  local function rel(p)
    if base == 'abs' then
      return p
    end
    if troot and p:sub(1, #troot + 1) == troot .. '/' then
      return p:sub(#troot + 2)
    end
    -- 루트 밖의 파일(다른 트리의 헤더 등)과 'pwd' 모드는 vim 의 방식대로
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

  -- a flat result list (:Gtags -d/-r/-s/-g captured from the quickfix window)
  if t.kind == 'results' then
    raw('')
    raw(section_line(t.title or 'Results', #t.results))
    if #t.results == 0 then
      raw('  (none)')
    else
      for i, res in ipairs(t.results) do
        local name = res.name or t.sym
        local rr = row('  ' .. name, res.path, res.line, res.text or '',
          { loc = { path = res.path, line = res.line, sym = res.name } }, name)
        if i == 1 then
          rr.focus = true
        end
      end
      if t.truncated and t.truncated > 0 then
        raw('  … ' .. t.truncated .. ' more')
      end
    end
    render_rows(t, rows)
    return
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

    -- SI 는 타입을 고르면 멤버를 전부 나열한다. 커널 구조체는 멤버가 수십
    -- 개라 그 목록만으로 패널이 가득 차므로 기본은 접어 둔다.
    --   let g:relationview_members = 1   " 다시 나열
    -- 목록을 껐어도, 특정 멤버나 enum 상수를 골라 들어온 경우에는 그 한 줄만
    -- 보여 준다. 그게 없으면 무엇을 골랐는지가 화면에서 사라진다.
    local show_members = cfg('members', 0) ~= 0
    local mlist, mtitle = t.members, 'Members'
    if not show_members then
      local one = (t.focus_member and t.members)
          and find_member(t.members, t.focus_member) or nil
      mlist, mtitle = one and { one } or nil, 'Member'
    end
    -- members only exist once the type definition was found and parsed
    if t.def and (show_members or mlist) then
      raw('')
      raw(section_line(mtitle, mlist and #mlist or nil))
      if not mlist or #mlist == 0 then
        raw('  ' .. (t.members_note or '(none)'))
      else
        for _, m in ipairs(mlist) do
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

  local title = t.relation == 'callees' and 'Calls'
      or (t.kind == 'symbol' and 'References (undefined symbol)' or 'Callers')
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

  -- 'both': 반대 방향을 평면 목록으로 덧붙인다. 점프는 되고 확장은 안 된다
  -- (확장하려면 d 로 그 방향을 트리로 바꾼다). 아직 오는 중이면 그렇게 적어
  -- 두어야 목록이 없는 것과 구별된다.
  if t.extra_rel then
    local etitle = t.extra_rel == 'callees' and 'Calls' or 'Callers'
    raw('')
    if t.extra_pending then
      raw(section_line(etitle .. ' …'))
      raw('  (읽는 중)')
    else
      local ex = t.extra or {}
      raw(section_line(etitle, #ex))
      if #ex == 0 then
        raw('  (none)')
      else
        local cap = cfg('max_extra', 40)
        local shown = math.min(#ex, cap)
        for i = 1, shown do
          local nd = ex[i]
          local branch = (i == shown) and '└─' or '├─'
          row('  ' .. branch .. ' · ' .. nd.label,
            nd.site.path, nd.site.line, nd.site.text,
            { loc = { path = nd.site.path, line = nd.site.line,
                      sym = nd.ref_sym } },
            nd.label)
        end
        if #ex > shown then
          raw(string.format('     … %d more  ([d] 로 트리로 펼침)',
            #ex - shown))
        end
      end
    end
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
  local avail = 80
  if s.win and api.nvim_win_is_valid(s.win) then
    avail = api.nvim_win_get_width(s.win)
    s.rendered_w = avail
    s.rendered_h = api.nvim_win_get_height(s.win)
  end
  -- 'symbol | path' only by default: g:relationview_show_text = 1 puts the
  -- source line back as a third column
  local show_text = cfg('show_text', 0) ~= 0
  -- 경로는 자르지 않는다.
  --
  -- 예전에는 경로 칸을 창 폭에 맞춰 잘라 앞을 '…'로 줄였다. 깊은 트리에서는
  -- 그게 자주 걸린다 - 어느 파일인지는 알겠는데 어디에 있는 파일인지가
  -- 사라진다. 잘리느니 줄이 창 밖으로 나가는 편이 낫다: 경로는 줄 앞쪽에
  -- 있으니 화면에 남고, 밀려나는 것은 그 뒤의 소스 줄이다.
  --
  -- 심볼 칸은 그대로 제한한다(이름 하나가 창을 다 먹으면 경로가 오른쪽으로
  -- 밀려 그것대로 안 보인다).
  --   let g:relationview_path_truncate = 1   " 예전처럼 창 폭에 맞춰 자른다
  local trunc_path = cfg('path_truncate', 0) ~= 0
  if show_text then
    local wide = cfg('full_path', 0) ~= 0
    wsym = math.min(wsym, math.max(24, math.floor(avail * (wide and 0.35 or 0.45))))
    if trunc_path then
      wloc = math.min(wloc, math.max(16, math.floor(avail * (wide and 0.62 or 0.35))))
    end
  else
    -- no source column: the symbol keeps what it needs, the path gets the rest
    wsym = math.min(wsym, math.max(24, math.floor(avail * 0.5)))
    if trunc_path then
      wloc = math.min(wloc, math.max(16, avail - wsym - 3))
    end
  end

  local lines = header(t.sym)
  local items = {}
  local focus
  for _, r in ipairs(rows) do
    if r.kind == 'raw' then
      lines[#lines + 1] = r.text
    else
      local symcell = pad(trunc_w(r.sym, wsym), wsym)
      -- 경로 칸을 맞출지.
      --
      -- 자르지 않기로 했으니 가장 긴 경로에 맞춰 패딩하면, 깊은 경로 하나
      -- 때문에 모든 줄이 그만큼 벌어지고 소스 줄이 화면 밖으로 밀린다.
      -- 그래서 창에 들어갈 때만 칸을 맞추고, 넘치면 각 줄이 제 길이만 쓴다
      -- (줄은 들쭉날쭉해지지만 잘리는 것은 없다).
      local loccell
      if trunc_path then
        loccell = pad(trunc_tail(r.loc, wloc), wloc)
      elseif wsym + 2 + wloc + 3 <= avail then
        loccell = pad(r.loc, wloc)
      else
        loccell = r.loc
      end
      if show_text then
        lines[#lines + 1] = string.format('%s  %s │ %s',
          symcell, loccell, trunc(r.text, 200))
      else
        lines[#lines + 1] = symcell .. '  ' .. loccell
      end
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
ts_tree = function(path)
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

-- the line the member's NAME is on. A declaration can span many lines
-- ('struct { ... } pair[N];' starts at the 'struct {'), and the useful place
-- to land is where the name is.
local function name_line(node)
  -- Only the declarator side: the TYPE of this field may itself be an
  -- anonymous struct, and its members would otherwise be mistaken for the
  -- name of this one ('struct { ... struct x y; ... } pair[N];').
  local decls = node:field('declarator')
  if not decls or #decls == 0 then
    return nil
  end
  local found
  local function walk(n)
    if found then
      return
    end
    if n:type() == 'field_identifier' then
      found = n:start() + 1
      return
    end
    for c in n:iter_children() do
      walk(c)
    end
  end
  for _, d in ipairs(decls) do
    walk(d)
  end
  return found
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
                line = name_line(f) or (f:start() + 1),
              }
            end
          end
        else
          -- 'struct { ... } hw;' - the member has a name but its type does
          -- not, so a chain can only continue by descending into that body
          -- right here. Remember where it starts.
          local sub
          for x in c:iter_children() do
            if TYPE_NODES[x:type()] and not field1(x, 'name') then
              for y in x:iter_children() do
                if y:type() == 'field_declaration_list' then
                  sub = x:start() + 1
                  break
                end
              end
            end
          end
          out[#out + 1] = {
            name = #names > 0 and table.concat(names, ', ') or '(anonymous)',
            text = ntext(c, source):gsub('%s+', ' '),
            line = name_line(c) or (c:start() + 1),
            sub = sub,
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
local_decl = function(bufnr, line, sym)
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
        return vim.system({ prog, '-P', pat },
          { text = true, cwd = root, env = db_env() }):wait(3000)
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
  run_global({ '-a', '-f', rel_to(root, path) }, root, function(lines)
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
-- 'both' 모드의 두 번째 섹션: 트리와 반대 방향을 평면 목록으로 덧붙인다.
-- 트리 확장 로직은 한 방향만 다루므로 여기서는 노드를 만들되 자식은 펼치지
-- 않는다. d 로 방향을 바꾸면 같은 목록이 완전한 트리가 된다.
--
-- t 는 캐시에 들어간 바로 그 테이블이라, 여기서 t.extra 를 채우면 캐시된
-- 값도 같이 갱신된다. 따로 다시 넣을 필요가 없다.
local function fetch_extra(gen, t)
  if not (t and t.extra_pending) then
    return
  end
  local alive = function() return gen == s.gen end
  fetch_callees(t.root, t.mtime, t.sym, alive, function(entries)
    if gen ~= s.gen or s.tree ~= t then
      return
    end
    t.extra_pending = nil
    if not entries then
      -- 함수가 아니거나 본문을 못 읽었다: Calls 섹션 자체를 그리지 않는다
      t.extra_rel = nil
    else
      t.extra = make_nodes(entries, nil, t.sym)
    end
    render_tree()
  end, t.def and t.def.path or nil)
end

local function finish(gen, sym, root, mtime, data)
  if gen ~= s.gen then
    return
  end
  s.scope = nil
  -- callees arrive already grouped by name; references need grouping
  local entries = data.entries or group_refs(data.refs)
  local t = {
    sym = sym,
    root = root,
    mtime = mtime,
    def = data.def,
    kind = data.refs_kind,
    relation = data.relation or relation(),
    truncated = data.refs_truncated or entries.truncated,
    shown = data.entries and #entries or #data.refs,
    capped = (data.refs_total or 0) >= REF_STREAM_CAP,
    nodes = make_nodes(entries, nil, sym),
  }
  -- Callers 트리 옆에 Calls 를 덧붙일지. 정의가 있어야(=함수여야) 본문을
  -- 읽을 수 있으므로 정의가 없으면 애초에 시도하지 않는다.
  t.extra_rel = relation_extra()
  if t.extra_rel and t.relation == 'callers' and data.def then
    t.extra_pending = true
  else
    t.extra_rel = nil
  end
  if gtags_mtime(root) == mtime then
    cache_put(tree_key(sym, root, t.relation, t.extra_rel), mtime, t)
  end
  s.tree = t
  render_tree()
  fetch_extra(gen, t)
end

-- a type NAME -> the definition that really has a body. Follows
-- 'typedef struct foo foo_t;' (and typedef-of-typedef) and prefers, among
-- several gtags hits, the one that parses into members.
-- gen ties a lookup to the panel render that started it, so a stale answer
-- cannot overwrite a newer view. A jump the user asked for belongs to no
-- render: it passes nil and runs to completion.
local function resolve_type_def(gen, root, name, hops, cb)
  run_global({ '--result=ctags-mod', '-a', '-d', '-e', name }, root,
    function(lines)
      if gen and gen ~= s.gen then
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
local resolve_chain

-- the same walk, but inside an anonymous struct/union body of the SAME file
-- ('struct { struct { u32 max_channel; } hw; } pair[N];' - the kernel is
-- full of these, and there is no type name anywhere to look up)
local function anon_chain(gen, root, path, sub_line, fields, i, cb)
  local sm = members_of(path, sub_line)
  if not sm then
    return false
  end
  local hit = find_member(sm.members, fields[i])
  if not hit then
    return false
  end
  local def = { path = path, line = sm.line }
  if i >= #fields then
    cb({ def = def, members = sm.members, member = hit, name = fields[i] })
    return true
  end
  if hit.sub and anon_chain(gen, root, path, hit.sub, fields, i + 1, cb) then
    return true
  end
  local nty = type_from_text(hit.text)
  if nty then
    resolve_chain(gen, root, nty, fields, i + 1, cb)
    return true
  end
  cb({ def = def, members = sm.members, member = hit, name = fields[i] })
  return true
end

resolve_chain = function(gen, root, ty, fields, i, cb)
  resolve_type_def(gen, root, ty.name, 3, function(tdef, m, ty2)
    if gen and gen ~= s.gen then
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
    -- an anonymous struct/union member: continue inside it, same file
    if hit.sub and tdef.path
        and anon_chain(gen, root, tdef.path, hit.sub, fields, i + 1, cb) then
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
-- 'msg->cmd' / 'ctx.id' under the cursor: where is THAT member declared?
-- Matching by name alone is what sends such a jump to a local variable that
-- happens to share the name, or to an unrelated global - so resolve the type
-- of the BASE variable and take the member out of that struct.
-- Returns true when it took the jump on (the answer arrives asynchronously).
member_jump = function(buf, line, col, cb, retried)
  local okc, base, fields = pcall(cursor_field, buf, line, col)
  if not okc or not base or not fields or #fields == 0 then
    return false
  end
  local name = api.nvim_buf_get_name(buf)
  if name == '' then
    return false
  end
  local okd, decl = pcall(local_decl, buf, line, base)
  local ty = (okd and decl) and type_from_text(decl.text) or nil
  if not ty then
    return false -- base is not a local we can type: let the others try
  end
  local want = fields[#fields]
  root_for(name, function(root)
    if not root then
      return
    end
    resolve_chain(nil, root, ty, fields, 1, function(res)
      local m = res and res.member
      local def = res and res.def
      if not (m and def and def.path) then
        -- The chain stops where a type is not in the index - and then even
        -- the first member of 'a->b[i].c.d' cannot be resolved. Pull the
        -- file that defines that type into the project and try once more.
        local missing = (res and res.type and res.type.name) or ty.name
        if not retried and missing and _G.projectfiles_add_for_symbol_async then
          pcall(_G.projectfiles_add_for_symbol_async, missing, function(n)
            if n and n > 0 then
              vim.defer_fn(function()
                member_jump(buf, line, col, cb, true)
              end, 150)
            else
              vim.notify('RelationView: ' .. missing ..
                ' 의 정의를 찾지 못했습니다 (멤버 ' .. want .. ')',
                vim.log.levels.WARN)
            end
          end)
          return
        end
        vim.notify('RelationView: 멤버 ' .. want .. ' 를 찾지 못했습니다',
          vim.log.levels.WARN)
        return
      end
      cb({ path = def.path, line = m.line or def.line, sym = want })
    end)
  end)
  return true
end

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
function update(sym, srcfile, force, manual, ctx)
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
    -- 같은 심볼로 되돌아오는 것은 코드를 읽을 때 가장 흔한 동작인데, 트리
    -- 캐시는 지금까지 기록만 되고 한 번도 읽히지 않았다. 조건이 'ctx.buf 가
    -- 없을 때'였고 ctx.buf 는 거의 언제나 있기 때문이다.
    --
    -- 캐시에 들어 있는 것은 함수 트리뿐이다. 지금 커서 자리가 (1) 타입
    -- 쓰임새이거나 (2) msg->cmd 같은 멤버 접근이거나 (3) 이 함수 안의 지역
    -- 변수/파라미터라면 트리가 아니라 다른 뷰가 나와야 한다. 그 셋은 gtags
    -- 없이 버퍼만 보고 판정되므로 여기서 확인하고 넘어간다.
    --   let g:relationview_tree_cache = 0   " 캐시를 아예 쓰지 않기
    local function tree_cache_ok()
      if force or cfg('tree_cache', 1) == 0 then
        return false
      end
      if not (ctx and ctx.buf and api.nvim_buf_is_valid(ctx.buf)) then
        return true
      end
      if s.as_type then
        return false
      end
      local okf, _, fields = pcall(cursor_field, ctx.buf, ctx.line or 1,
        ctx.col or 0)
      if okf and fields and #fields > 0 then
        return false
      end
      local okd, decl = pcall(local_decl, ctx.buf, ctx.line or 1, sym)
      if okd and decl then
        return false
      end
      return true
    end
    if tree_cache_ok() then
      local hit = cache_get(tree_key(sym, root), mtime)
      -- '#include' 줄은 심볼이 아니라 파일에 대한 것이다: 캐시보다 먼저 본다
      local inc0 = (ctx and ctx.buf and api.nvim_buf_is_valid(ctx.buf))
          and include_at(ctx.buf, ctx.line or 1) or nil
      if hit and not inc0 then
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

    -- Calls 방향(SI 의 Relation window 방향 전환): 이 심볼이 부르는 함수들.
    -- 정의를 읽어 본문의 호출을 모으는 것이라 참조 검색과 경로가 다르다.
    if relation() == 'callees' then
      local alive0 = function() return gen == s.gen end
      run_global({ '--result=ctags-mod', '-a', '-d', '-e', sym }, root,
        function(dl)
          if gen ~= s.gen then
            return
          end
          local defs0 = parse_ctags_mod(dl, 8)
          local def = defs0[1]
          for _, d in ipairs(defs0) do
            if d.path == srcfile then
              def = d -- 커서가 있는 파일의 정의를 Definition 행에 보여 준다
              break
            end
          end
          fetch_callees(root, mtime, sym, alive0, function(entries)
            if gen ~= s.gen then
              return
            end
            if not entries then
              s.note = '본문을 읽을 수 없습니다 (함수가 아니거나 원형만 있음)'
              finish(gen, sym, root, mtime,
                { refs = {}, entries = {}, def = def, relation = 'callees' })
              return
            end
            finish(gen, sym, root, mtime,
              { refs = {}, entries = entries, def = def, relation = 'callees' })
          end, srcfile)
        end, 8)
      return
    end

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

pick_src_win = function()
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

-- <C-t> 가 쓰는 태그 스택에 '여기서 떠났다'를 적는다.
--
-- 우리 점프는 :tag 가 아니라 nvim_win_set_buf 라 vim 이 스스로 쌓아 주지
-- 않는다. 그래서 스택이 늘 비어 있었고, <C-t> 는 아무 데도 못 갔다
-- (.vimrc 는 그것을 <C-o> 로 흉내 내고 있었는데, 그러면 점프 목록과 태그
-- 스택이 뒤섞여 둘 다 어긋난다).
local function push_tag(win, sym)
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  local ok, from = pcall(api.nvim_win_call, win, function()
    return { vim.fn.bufnr('%'), vim.fn.line('.'), vim.fn.col('.'), 0 }
  end)
  if not ok or not from then
    return
  end
  pcall(vim.fn.settagstack, win,
    { items = { { tagname = sym or '?', from = from } } }, 'a')
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
  push_tag(win, loc.sym)
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

-- Jump to the item the PANEL cursor is on, from wherever the user is.
-- C-n/C-p only preview, so this is how a walk finally ends in the edit
-- window. Returns false when the panel has no selectable item.
function A.jump_here(peek)
  if not (s.win and api.nvim_win_is_valid(s.win) and s.buf
      and api.nvim_win_get_buf(s.win) == s.buf) then
    return false
  end
  local item = s.items[api.nvim_win_get_cursor(s.win)[1]]
  if not (item and item.loc) then
    return false
  end
  jump_to(item.loc, peek)
  return true
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
      if t.relation == 'callees' then
        local prefer = nd.site and nd.site.path or nil
        fetch_callees(t.root, t.mtime, nd.name, alive, function(entries)
          nd.loading = false
          nd.children = make_nodes(entries or {}, nd, t.sym)
          nd.expanded = true
          if not entries then
            nd.expandable = false -- 읽을 함수 본문이 없다 (원형/매크로)
          end
          if s.tree == t then
            render_tree()
          end
        end, prefer)
      else
        fetch_callers(t.root, t.mtime, nd.name, alive, function(refs)
          nd.loading = false
          nd.children = make_nodes(group_refs(refs), nd, t.sym)
          nd.expanded = true
          if s.tree == t then
            render_tree()
          end
        end)
      end
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
        local callees = t.relation == 'callees'
        local grab = callees and fetch_callees or fetch_callers
        grab(t.root, t.mtime, nd.name, alive, function(got)
          nd.loading = false
          if not alive() then
            t.expanding = nil
            return
          end
          nd.children = make_nodes(
            callees and (got or {}) or group_refs(got), nd, t.sym)
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

-- C-c: let the panel follow the cursor again (the 2-3s dwell rule does this
-- by itself, this is the "right now" version)
function A.unpin()
  -- no panel on screen: the key was not ours, let it mean what it used to
  if not (s.pinned and panel_visible()) then
    return false
  end
  s.pinned = false
  update_header()
  -- A captured ':Gtags' list is frozen, and on_hold() will not rebuild it
  -- (it refuses while the cursor sits in the preview, and the symbol has
  -- not changed), so bring the live view back from a real source window.
  local w = pick_src_win()
  if w and api.nvim_win_is_valid(w) then
    local b = api.nvim_win_get_buf(w)
    local name = api.nvim_buf_get_name(b)
    if name ~= '' and vim.bo[b].buftype == '' then
      local pos = api.nvim_win_get_cursor(w)
      local sym = api.nvim_win_call(w, function()
        return vim.fn.expand('<cword>')
      end)
      if is_symbol(sym) then
        update(sym, name, true, false,
          { buf = b, line = pos[1], col = pos[2] })
      end
    end
  end
  return true
end

-- Walk the list: move the panel's cursor to the next/previous row that
-- carries a location and preview that location in the CONTEXT window. The
-- edit window is deliberately left alone - this is for looking through the
-- call sites, not for going to them (Enter in the panel still goes). The
-- focus stays where it was, so the key can be pressed again.
-- Returns false when there is no list to walk, which is what makes the
-- mapping fall through to quickfix.
function A.step(dir)
  if not (s.win and api.nvim_win_is_valid(s.win)
      and s.buf and api.nvim_buf_is_valid(s.buf)
      and api.nvim_win_get_buf(s.win) == s.buf) then
    return false
  end
  local total = api.nvim_buf_line_count(s.buf)
  local any = false
  for i = 1, total do
    if s.items[i] and s.items[i].loc then
      any = true
      break
    end
  end
  if not any then
    return false -- nothing in the panel: let quickfix have the key
  end
  local lnum = api.nvim_win_get_cursor(s.win)[1]
  local found
  for _ = 1, total do
    lnum = lnum + dir
    if lnum < 1 or lnum > total then
      break
    end
    if s.items[lnum] and s.items[lnum].loc then
      found = lnum
      break
    end
  end
  if not found then
    vim.notify('RelationView: ' ..
      (dir > 0 and '리스트의 마지막입니다' or '리스트의 처음입니다'))
    return true
  end
  if not s.pinned then
    s.pinned = true
    update_header()
  end
  pcall(api.nvim_win_set_cursor, s.win, { found, 0 })
  hl_cursor_row()
  if ctx_visible() then
    -- the panel's own CursorMoved does this on a timer; we are moving
    -- another window's cursor, so do it here and now - and force it,
    -- because stepping is often done from inside the preview after a C-]
    -- took the focus there
    s.ctx_last = nil
    update_context(true)
  else
    -- no preview window: the edit window is where you read, so show it
    -- there instead (peek: the focus stays where the key was pressed)
    jump_to(s.items[found].loc, true)
  end
  return true
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

-- SI 의 Relation window 방향 전환. both -> callers -> callees -> both.
-- both 는 양쪽을 같이 보여 주고(Calls 는 평면), 단일 방향은 그 방향을
-- 확장 가능한 트리로 보여 준다.
local RELATION_CYCLE = { both = 'callers', callers = 'callees', callees = 'both' }

function A.toggle_relation()
  s.relation = RELATION_CYCLE[relation_mode()] or 'both'
  update_header()
  local t = s.tree
  local sym = s.sym or (t and t.sym)
  if not sym then
    return
  end
  local src = (t and t.def and t.def.path)
      or (s.src_win and api.nvim_win_is_valid(s.src_win)
        and api.nvim_buf_get_name(api.nvim_win_get_buf(s.src_win)))
      or vim.fn.getcwd()
  s.pinned = true
  update(sym, src, true, true, nil)
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

-- context 만 켜 둔 모드에서 커서가 멈추면 그 심볼의 정의로 미리보기를 옮긴다
api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
  group = group,
  callback = function()
    if ctx_follow then
      pcall(ctx_follow, false)
    end
  end,
})

-- A pinned panel is frozen on purpose (the user is walking the list), but
-- resting on a symbol in a source window means "this one now": after
-- g:relationview_unpin_delay ms on the same symbol the pin is released and
-- the panel follows the cursor again.
local function watch_unpin()
  if not (s.pinned and panel_visible()) then
    return
  end
  local win = api.nvim_get_current_win()
  if win == s.win or win == s.ctx_win then
    return -- the list and the preview are where the pin is meant to hold
  end
  local buf = api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' then
    return
  end
  local sym = vim.fn.expand('<cword>')
  if not is_symbol(sym) then
    return
  end
  if not s.unpin_timer then
    s.unpin_timer = uv.new_timer()
  end
  s.unpin_timer:stop()
  s.unpin_timer:start(cfg('unpin_delay', 3000), 0, vim.schedule_wrap(function()
    if not (s.pinned and panel_visible()) then
      return
    end
    if api.nvim_get_current_win() ~= win or vim.fn.expand('<cword>') ~= sym then
      return
    end
    s.pinned = false
    update_header()
    on_hold() -- rebuild for the symbol the cursor has been resting on
  end))
end

api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' },
  { group = group, callback = watch_unpin })
api.nvim_create_autocmd('ColorScheme',
  { group = group, callback = set_highlights })
api.nvim_create_autocmd('OptionSet',
  { group = group, pattern = 'background', callback = set_highlights })

-- the column widths (and therefore how much of each path fits) come from
-- the panel's size, so a resize has to lay the rows out again
api.nvim_create_autocmd({ 'WinNew', 'WinClosed' }, {
  group = group,
  callback = function()
    if not (s.win and api.nvim_win_is_valid(s.win)) then
      return -- the panel itself is being created/closed
    end
    local w = api.nvim_win_get_width(s.win)
    local h = api.nvim_win_get_height(s.win)
    vim.schedule(function() restore_geom(w, h) end)
  end,
})

api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, {
  group = group,
  callback = function()
    if not (s.win and api.nvim_win_is_valid(s.win)) then
      return
    end
    if not s.tree then
      return
    end
    if api.nvim_win_get_width(s.win) == s.rendered_w
        and api.nvim_win_get_height(s.win) == s.rendered_h then
      return
    end
    if not s.rs_timer then
      s.rs_timer = uv.new_timer()
    end
    s.rs_timer:stop()
    s.rs_timer:start(50, 0, vim.schedule_wrap(function()
      if not (s.tree and s.win and api.nvim_win_is_valid(s.win)) then
        return
      end
      -- keep the cursor and the scroll position across the re-render
      local view
      api.nvim_win_call(s.win, function() view = vim.fn.winsaveview() end)
      render_tree()
      if view then
        api.nvim_win_call(s.win, function() vim.fn.winrestview(view) end)
      end
      hl_cursor_row()
    end))
  end,
})

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
  -- 설정된 기본 방향으로 되돌린다(g:relationview_relation). 예전에는 여기서
  -- 'callers' 를 못박아서 그 설정이 F3 이외의 경로에서 무시되었다.
  s.relation = nil
  open_and_query(o.args)
end, { nargs = '?', desc = 'Source Insight style relation window' })

api.nvim_create_user_command('RelationViewBoth', function(o)
  s.relation = 'both'
  open_and_query(o.args)
end, { nargs = '?', desc = 'Relation window, Callers tree + Calls list' })

-- the other direction: what this function calls. cscope's 'd' query, which
-- nvim dropped along with cscope support.
api.nvim_create_user_command('RelationViewCalls', function(o)
  s.relation = 'callees'
  open_and_query(o.args)
end, { nargs = '?', desc = 'Relation window, Calls direction (callees)' })

-- ---------------------------------------------------------------------------
-- <F3>: 네 상태를 돌아가며 켠다
-- ---------------------------------------------------------------------------
--   both      relation window + context window   (Source Insight 의 기본 배치)
--   relation  relation window 만
--   context   context window 만 - 편집 창의 커서 밑 심볼의 정의를 보여 준다
--   off       둘 다 닫는다
--
-- 지금 상태는 기억해 두지 않고 화면에서 읽는다. 창을 손으로 닫았거나 다른
-- 탭으로 옮겨 갔어도 <F3> 한 번이 늘 '다음 상태'로 간다.
local function current_mode()
  local p, c = panel_visible(), ctx_visible()
  if p and c then
    return 'both'
  elseif p then
    return 'relation'
  elseif c then
    return 'context'
  end
  return 'off'
end

local MODE_LABEL = {
  both = 'relation + context',
  relation = 'relation only',
  context = 'context only',
  off = 'off',
}
local MODE_DEFAULT_CYCLE = { 'both', 'relation', 'context', 'off' }

-- <F3> 가 도는 순서는 사용자가 정한다. 네 배치를 다 거치고 싶지 않은 쪽이
-- 많다 - 미리보기만 켜고 끄면 되는 사람에게 네 번 누르게 할 이유가 없다.
--
--   let g:relationview_cycle = ['context', 'off']         " 미리보기만 켜고 끄기
--   let g:relationview_cycle = ['both', 'off']            " 통째로 켜고 끄기
--   let g:relationview_cycle = ['context', 'both', 'off'] " 셋만
--   let g:relationview_cycle = ['relation', 'context']    " 둘을 오간다
--
-- 모르는 이름은 버리고 한 번만 알려 준다. 남는 것이 없으면 기본 순서를 쓴다.
local function cycle_list()
  local raw = vim.g.relationview_cycle
  if type(raw) ~= 'table' then
    return MODE_DEFAULT_CYCLE
  end
  local out, bad = {}, {}
  for _, v in ipairs(raw) do
    local m = tostring(v):lower():gsub('%s', '')
    if MODE_LABEL[m] then
      out[#out + 1] = m
    else
      bad[#bad + 1] = tostring(v)
    end
  end
  if #bad > 0 and not s.cycle_warned then
    s.cycle_warned = true
    vim.notify(('RelationView: g:relationview_cycle 에 모르는 이름 %s'):format(
        table.concat(bad, ', '))
      .. ' — both / relation / context / off 중에서 고르세요',
      vim.log.levels.WARN)
  end
  if #out == 0 then
    return MODE_DEFAULT_CYCLE
  end
  return out
end

-- 지금 화면 상태의 '다음'. 지금 상태가 목록에 없으면(사용자가 목록에서 뺀
-- 배치에 있거나 창을 손으로 닫았으면) 목록의 처음으로 간다.
local function next_mode()
  local list = cycle_list()
  local cur = current_mode()
  for i, m in ipairs(list) do
    if m == cur then
      return list[(i % #list) + 1]
    end
  end
  return list[1]
end

-- context 만 떠 있을 때, 편집 창의 커서 밑 심볼의 정의를 보여 준다.
--
-- 패널이 있을 때의 context 는 '목록에서 고른 항목'을 미리 보는 창이라
-- update_context() 가 패널의 커서 줄에서 값을 얻는다. 패널이 없으면 그
-- 출처가 없으므로, Source Insight 의 Context Window 처럼 편집 창의 커서를
-- 따라간다: 심볼 하나를 gtags 에 물어 정의 위치를 얻고 그 자리를 띄운다.
local function ctx_follow_impl(force)
  local function trace(why)
    if vim.g.relationview_ctx_debug ~= nil and vim.g.relationview_ctx_debug ~= 0 then
      pcall(vim.fn.writefile, { os.date('%H:%M:%S') .. ' ' .. why },
        vim.fn.stdpath('cache') .. '/rvctx.log', 'a')
    end
  end
  if not (s.ctx_alone and ctx_visible()) then
    trace(('멈춤: alone=%s visible=%s'):format(tostring(s.ctx_alone), tostring(ctx_visible())))
    return
  end
  local win = api.nvim_get_current_win()
  if win == s.ctx_win then
    trace('멈춤: 미리보기 안')
    return
  end
  local buf = api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' then
    return
  end
  local file = api.nvim_buf_get_name(buf)
  if file == '' then
    return
  end
  local sym = vim.fn.expand('<cword>')
  if not is_symbol(sym) then
    trace('멈춤: 심볼 아님 ' .. tostring(sym))
    return
  end
  if not force and s.ctx_sym == sym then
    trace('멈춤: 같은 심볼 ' .. sym)
    return
  end
  s.ctx_sym = sym
  trace('조회 ' .. sym)
  root_for(file, function(root)
    if not root or not (s.ctx_alone and ctx_visible()) or s.ctx_sym ~= sym then
      trace('멈춤(root cb): root=' .. tostring(root) .. ' alone=' .. tostring(s.ctx_alone))
      return
    end
    run_global({ '--result=ctags-mod', '-a', '-d', '-e', sym }, root,
      function(lines)
        if not (s.ctx_alone and ctx_visible()) or s.ctx_sym ~= sym then
          return
        end
        local defs = parse_ctags_mod(lines, 8)
        local d = defs and defs[1]
        trace(('결과 %s: %d개'):format(sym, defs and #defs or -1))
        if d then
          show_context({ path = d.path, line = d.line, sym = sym })
        end
      end)
  end)
end

local function apply_mode(m)
  s.mode = m
  if m == 'off' then
    s.ctx_alone = false
    A.close()
    return
  end
  if m == 'context' then
    -- 패널을 닫고 context 만 남긴다. A.close() 가 context 도 같이 닫으므로
    -- 순서가 중요하다: 닫고 나서 다시 세운다.
    s.ctx_alone = true
    A.close()
    if ensure_ctx() then
      s.ctx_sym = nil
      ctx_follow(true)
    end
    return
  end
  s.ctx_alone = false
  if m == 'relation' and ctx_visible() then
    api.nvim_win_close(s.ctx_win, false)
    s.ctx_win, s.ctx_last, s.ctx_stack = nil, nil, {}
  end
  if not panel_visible() then
    open_and_query(nil)
  elseif m == 'both' and not ctx_visible() then
    if ensure_ctx() then
      update_context(true)
    end
  end
end

ctx_follow = ctx_follow_impl

api.nvim_create_user_command('RelationViewCycle', function()
  local m = next_mode()
  apply_mode(m)
  vim.notify('RelationView: ' .. MODE_LABEL[m])
end, { desc = 'Cycle the layout (g:relationview_cycle sets the order)' })

api.nvim_create_user_command('RelationViewMode', function(o)
  local m = o.args
  if not MODE_LABEL[m] then
    vim.notify('RelationView: both | relation | context | off 중에서',
      vim.log.levels.WARN)
    return
  end
  apply_mode(m)
  vim.notify('RelationView: ' .. MODE_LABEL[m])
end, {
  nargs = 1,
  complete = function() return { 'both', 'relation', 'context', 'off' } end,
  desc = 'Set the relation/context layout',
})

api.nvim_create_user_command('RelationViewToggle', function()
  if panel_visible() or panel_win_here() then
    A.close()
  else
    open_and_query(nil)
  end
end, { desc = 'Toggle the relation window (F3 cycles instead)' })

-- One key for "next item in whatever list is in front of me": the relation
-- list when the panel holds one, the quickfix list otherwise.
local function step_or_qf(dir)
  if A.step(dir) then
    return
  end
  local ok, err = pcall(vim.cmd, dir > 0 and 'cnext' or 'cprevious')
  if not ok then
    vim.notify((tostring(err):gsub('^.*Vim%b():', '')), vim.log.levels.INFO)
  end
end

-- ---------------------------------------------------------------------------
-- ':Gtags -d/-r/...' results in the panel instead of the quickfix window
-- ---------------------------------------------------------------------------
-- gtags.vim fills the quickfix list with 'cexpr' and opens it. While the
-- panel is up that is the wrong place to read a symbol search, so the same
-- query is run here and rendered as a result list, which then behaves like
-- any other panel list (C-n/C-p, preview, Enter, C-CR). With the panel
-- closed the original command runs untouched.
local gtags_orig -- function(args): calls gtags.vim's own s:RunGlobal

-- which single-letter flags map straight onto global(1)
local GFLAG = {}
for c in ('drsgPfaie'):gmatch('.') do
  GFLAG[c] = true
end

local function show_results(title, sym, results, truncated, origin)
  s.gen = s.gen + 1
  kill_procs()
  s.tree = { kind = 'results', sym = sym, title = title, results = results,
    truncated = truncated }
  s.note = nil
  s.as_type = false
  s.sym = sym
  s.pinned = true -- a search result is a fixed list, not a live view
  render_tree()
  hl_cursor_row()
  update_context()
  -- reading the hit is the next thing you do, so land in the preview - and
  -- leave a way back to where the search was started (C-t)
  if origin and api.nvim_win_is_valid(origin) and #results > 0 then
    if ctx_visible() then
      ctx_enter_from(origin, nil, sym)
    else
      -- no preview: show the first hit in the edit window instead, the way
      -- the quickfix jump used to (the focus stays where you are)
      local first = results[1]
      jump_to({ path = first.path, line = first.line, sym = first.name }, true)
    end
  end
end

function A.gtags(args, retried)
  local flags, pat = {}, {}
  for w in tostring(args):gmatch('%S+') do
    if w:sub(1, 1) == '-' and #w > 1 then
      flags[#flags + 1] = w
    else
      pat[#pat + 1] = w
    end
  end
  local pattern = table.concat(pat, ' ')
  local ok_flags = pattern ~= ''
  for _, f in ipairs(flags) do
    if f:sub(1, 2) == '--' then
      ok_flags = false
    else
      for c in f:sub(2):gmatch('.') do
        if not GFLAG[c] then
          ok_flags = false
        end
      end
    end
  end
  if not (panel_visible() and ok_flags) then
    if gtags_orig then
      gtags_orig(args)
    end
    return
  end
  local paths_only = false
  for _, f in ipairs(flags) do
    if f:find('P', 1, true) then
      paths_only = true
    end
  end
  -- Which project this searches must come from a real file, not from
  -- whatever scratch window happens to hold the focus (the preview, the
  -- panel, the project files view, quickfix ...) - otherwise the root is
  -- resolved from the cwd and the search finds nothing.
  local win = api.nvim_get_current_win()
  local sbuf = api.nvim_win_get_buf(win)
  if vim.bo[sbuf].buftype ~= '' or api.nvim_buf_get_name(sbuf) == '' then
    local sw = pick_src_win()
    if sw and api.nvim_win_is_valid(sw) then
      win, sbuf = sw, api.nvim_win_get_buf(sw)
    end
  end
  local file = api.nvim_buf_get_name(sbuf)
  local origin = (vim.bo[sbuf].buftype == '' and file ~= '') and win or nil
  local dir = file ~= '' and vim.fs.dirname(vim.fn.fnamemodify(file, ':p'))
      or vim.fn.getcwd()
  get_root(dir, function(root)
    root = root or vim.fn.getcwd()
    local argv = {}
    if not paths_only then
      argv[#argv + 1] = '--result=ctags-mod'
    end
    vim.list_extend(argv, flags)
    argv[#argv + 1] = pattern
    local cap = cfg('max_refs', 1000)
    run_global(argv, root, function(lines, err)
      if not lines then
        render_msg(pattern, 'Gtags: ' .. (err or 'no result'))
        return
      end
      local results = {}
      for _, l in ipairs(lines) do
        if paths_only then
          results[#results + 1] = { name = basename(l), path = l, line = 1 }
        else
          local path, lno, text = l:match('^([^\t]+)\t(%d+)\t(.*)$')
          if path then
            results[#results + 1] = { name = pattern, path = path,
              line = tonumber(lno), text = (text or ''):gsub('^%s+', '') }
          end
        end
        if #results >= cap then
          break
        end
      end
      if #results == 0 and not retried and _G.projectfiles_add_for_symbol_async
      then
        -- the project files may simply not contain it yet; the search for
        -- the defining file runs in the background, the empty list is shown
        -- meanwhile and replaced when it lands
        pcall(_G.projectfiles_add_for_symbol_async, pattern, function(n)
          if n and n > 0 then
            A.gtags(args, true)
          end
        end)
      end
      show_results('Gtags ' .. tostring(args), pattern, results,
        math.max(0, #lines - #results), origin)
    end, cap + 200)
  end)
end

-- gtags.vim is loaded after this file, so take the command over once
-- everything is up; nvim_get_commands hands us the original function to
-- fall back on (call s:RunGlobal(<q-args>, '')).
local function capture_gtags()
  if cfg('capture_gtags', 1) == 0 then
    return
  end
  local c = api.nvim_get_commands({ builtin = false })['Gtags']
  if not (c and c.script_id and (c.definition or ''):match('RunGlobal')) then
    return
  end
  local sid = c.script_id
  gtags_orig = function(args)
    pcall(vim.cmd, string.format("call <SNR>%d_RunGlobal(%s, '')", sid,
      vim.fn.string(tostring(args))))
  end
  api.nvim_create_user_command('Gtags', function(o) A.gtags(o.args) end,
    { nargs = '*', complete = 'custom,GtagsCandidate',
      desc = 'gtags search - into the relation panel while it is open' })
end

api.nvim_create_autocmd('VimEnter', { group = group, callback = capture_gtags })

api.nvim_create_user_command('RelationViewUnpin', function()
  if not A.unpin() then
    return
  end
  -- follow the cursor again straight away
  pcall(function() api.nvim_exec_autocmds('CursorHold', {}) end)
end, { desc = 'Unpin the relation panel (follow the cursor again)' })

api.nvim_create_user_command('RelationViewJump', function()
  if not A.jump_here(false) then
    vim.notify('RelationView: 선택된 항목이 없습니다')
  end
end, { desc = 'Jump the edit window to the item under the panel cursor' })

api.nvim_create_user_command('RelationViewNext', function() step_or_qf(1) end,
  { desc = 'Next item in the relation list (falls back to :cnext)' })
api.nvim_create_user_command('RelationViewPrev', function() step_or_qf(-1) end,
  { desc = 'Previous item in the relation list (falls back to :cprevious)' })

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
  -- 시작할 때 어느 상태로 열까. 기본은 context 만 - relation window 는
  -- 아래를 12줄 가져가는데 늘 필요한 것은 아니고, 커서 밑 심볼의 정의를
  -- 옆에 띄워 두는 쪽이 읽을 때 계속 쓰인다. <F3> 로 넘긴다.
  --   let g:relationview_startup = 'both'      " 예전처럼 패널+미리보기
  --   let g:relationview_startup = 'relation'  " 패널만
  --   let g:relationview_startup = 'off'       " 아무것도 열지 않기
  local m = tostring(cfg('startup', 'context'))
  if not MODE_LABEL[m] then
    m = 'context'
  end
  vim.schedule(function()
    if m == 'off' then
      return
    end
    local prev = api.nvim_get_current_win()
    if m == 'context' then
      s.ctx_alone = true
      s.mode = 'context'
      if ensure_ctx() then
        s.ctx_sym = nil
        if ctx_follow then
          pcall(ctx_follow, true)
        end
      end
    else
      if panel_visible() then
        return
      end
      s.mode = m
      panel_open()
      if s.buf and api.nvim_buf_line_count(s.buf) <= 1 then
        render_msg(nil, 'move the cursor onto a symbol in a source window')
      end
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
  vim.keymap.set('n', '<F3>', '<Cmd>RelationViewCycle<CR>',
    { desc = 'RelationView: relation+context -> relation -> context -> off' })
end


