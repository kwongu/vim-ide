-- vimidewarm.lua - 쉬는 동안 무거운 기능의 모듈을 미리 불러 둔다 (nvim 전용, QA-24)
--
-- F9/F11/F12 트리, \D, F10, F1, :DiffviewOpen·\v, 첫 .h 파일을 처음 누르면
-- 그 기능의 Lua 모듈(neo-tree 100여 개, telescope, diffview ...)과 neo-tree 설정 합치기
-- (ensure_config), treesitter 쿼리 컴파일이 그 키 안에서 돈다. 실측(맥, 처음/두 번째):
-- F9 92/21ms, :DiffviewOpen 119/72, \D 106, F1 82, 첫 .h 163ms. 개발 서버는 더 느리다.
--
-- 시작한 뒤 쉬는 동안 그것들을 하나씩 미리 불러 둔다:
--   * VimEnter 0.3초 뒤부터, 키를 0.6초 안 친 normal 모드에서만
--   * 한 칸에 하나 (vim.defer_fn 사슬). 다음 몇 모듈의 파일은 뒤에서(스레드 풀) 미리 읽어
--     두어 한 칸은 컴파일·실행만 한다: 대부분 1~5ms, 가장 긴 칸(cpp 의 aerial 쿼리)이
--     12ms(부하 8 에서 20ms). 193칸 합 160~370ms (실측 - :VimIdeWarmup)
--   * 키를 치면 거기서 쉬고, 다시 0.6초 쉬면 이어 간다. 다 하면 on_key·자동 명령도 거둔다
-- 한 번에 20ms 를 넘고 쪼갤 수 없는 것(cpp 의 highlights 쿼리 컴파일 ~145ms, C 함수
-- 하나)은 터미널이 초점을 잃었을 때(FocusLost - 다른 창을 보는 동안)만 한다. 칠 수
-- 없을 때라야 멈춤을 느끼지 않는다. 초점 알림이 없는 터미널이면 예전처럼 첫 .h 에서.
--
-- 모듈을 미리 부르는 것은 그 기능이 처음 열릴 때 하던 일을 앞당기는 것뿐이다. 단
-- ensure_config 는 neo-tree 의 자동 명령(BufEnter 등)을 그때 단다 - 트리를 한 번이라도
-- 열면 어차피 달리는 것들이다.
--
--   :VimIdeWarmup   무엇을 몇 ms 에 불렀는지, 남은 것
--
-- 옵션 (.vimrc):
--   let g:vimide_warmup = 1    " 0 이면 하지 않는다

if vim.g.loaded_vimide_warmup then
  return
end
vim.g.loaded_vimide_warmup = 1

local api = vim.api
local uv = vim.uv or vim.loop

local START_MS = 300 -- VimEnter 뒤 첫 칸 (칸이 짧아 시작 때의 늦은 일들과 섞여도 된다)
local IDLE_MS = 600 -- 이만큼 키가 없어야 '쉰다'
local GAP_MS = 8 -- 칸 사이 (그 사이에 온 키는 바로 처리된다). 193칸이 2~3초에 끝난다

-- 미리 부를 모듈. 그 기능을 처음 누를 때 실측한 '불린 차례'(의존하는 것이 먼저)라서 한
-- 칸은 그 모듈 몸통만 돈다. 묶음의 첫 모듈이 없으면(플러그인이 없다) 그 묶음은 건너뛴다.
local MODS = {
  -- neo-tree: F9 F11, F12 열의 트리, \D 의 두 트리
  [[neo-tree.command.parser nui.object vim.version nui.utils nui.text nui.line nui.tree.util
    nui.tree nui.utils.buf_storage nui.utils.autocmd nui.utils.keymap nui.layout.utils
    nui.split.utils nui.split nui.popup.border nui.popup neo-tree.ui.highlights
    neo-tree.ui.popups neo-tree.ui.windows neo-tree.ui.renderer
    neo-tree.sources.filesystem.lib.filter_external
    neo-tree.sources.filesystem.lib.globtopattern neo-tree.sources.common.file-nesting
    neo-tree.sources.common.file-items neo-tree.sources.filesystem.lib.fs_watch plenary.tbl
    plenary.vararg.rotate plenary.vararg plenary.errors plenary.async.async
    plenary.async.structs plenary.async.control plenary.async.util plenary.async.tests
    plenary.async neo-tree.sources.filesystem.lib.lua-glob
    neo-tree.sources.filesystem.lib.ignored neo-tree.sources.filesystem.lib.fs_scan nui.input
    neo-tree.ui.inputs neo-tree.sources.manager neo-tree.command.completion neo-tree.command
    neo-tree.setup.mapping-helper neo-tree.setup.netrw neo-tree.sources.common.hijack_cursor
    neo-tree.setup neo-tree.setup.deprecations neo-tree.sources.filesystem
    neo-tree.sources.buffers.lib.items neo-tree.sources.buffers
    neo-tree.sources.git_status.lib.items neo-tree.sources.git_status
    neo-tree.sources.common.container neo-tree.sources.common.components
    neo-tree.sources.buffers.components plenary.scandir neo-tree.utils.xdg
    neo-tree.trash.freedesktop neo-tree.trash.gio neo-tree.trash.windows neo-tree.trash
    neo-tree.sources.filesystem.lib.fs_actions neo-tree.sources.common.help
    neo-tree.sources.common.preview neo-tree.sources.common.node_expander
    neo-tree.sources.common.commands neo-tree.sources.buffers.commands
    neo-tree.sources.git_status.components neo-tree.sources.git_status.commands
    neo-tree.sources.filesystem.components neo-tree.sources.common.filters.filter_fzy
    neo-tree.sources.common.filters neo-tree.sources.filesystem.lib.filter
    neo-tree.sources.filesystem.commands neo-tree.clipboard neo-tree.clipboard.sync.base
    neo-tree.ui.selector neo-tree.utils.filesize.filesize]],
  -- aerial: F10, 그리고 F9 가 부른다
  [[aerial.config aerial.highlight aerial.util aerial.autocommands aerial.command
    aerial.backends aerial.data aerial.keymap_util aerial.layout aerial.loading aerial.render
    aerial.window aerial.backends.treesitter.helpers aerial.backends.util
    aerial.backends.treesitter aerial.fold aerial.backends.lsp.util
    aerial.backends.lsp.callbacks aerial.backends.lsp vim.lsp.client aerial.backends.markdown
    aerial.backends.man aerial.backends.treesitter.extensions aerial.actions aerial.navigation]],
  -- telescope: F1 F3 \f* 피커
  [[plenary.window.border plenary.window plenary.popup.utils plenary.popup
    telescope.pickers.scroller telescope.actions.state telescope.actions.utils
    telescope.actions.mt telescope.actions.set telescope.config.resolve
    telescope.pickers.entry_display telescope.from_entry telescope.actions telescope.mappings
    telescope.pickers.highlights telescope.pickers.window telescope.pickers.layout
    telescope.algos.linked_list telescope.entry_manager telescope.pickers.multi
    telescope.pickers telescope.make_entry telescope.finders.async_static_finder plenary.class
    telescope._ telescope.finders.async_oneshot_finder telescope.finders.async_job_finder
    telescope.finders telescope.previewers.previewer telescope.previewers.utils
    telescope.previewers.term_previewer telescope.previewers.buffer_previewer
    telescope.previewers telescope.pickers.layout_strategies]],
  -- diffview: \v, :DiffviewOpen
  [[diffview.arg_parser diffview.path diffview.debounce diffview.stream diffview.vcs.commit
    diffview.vcs.adapters.git.commit diffview.scene.window diffview.vcs.rev
    diffview.scene.layout diffview.scene.layouts.diff_2 diffview.scene.layouts.diff_2_hor
    diffview.scene.file_entry diffview.vcs.flag_option diffview.vcs.adapters.git.rev
    diffview.job diffview.ui.models.file_tree.node diffview.ui.model
    diffview.ui.models.file_tree.file_tree diffview.vcs.file_dict diffview.scanner
    diffview.vcs.utils diffview.vcs.log_entry diffview.multi_job diffview.vcs.adapter
    diffview.vcs.adapters.git diffview.vcs.adapters.hg.commit diffview.vcs.adapters.hg.rev
    diffview.vcs.adapters.hg diffview.vcs diffview.scene.view
    diffview.scene.views.standard.standard_view diffview.scene.views.diff.diff_view
    diffview.renderer diffview.vcs.file diffview.perf diffview.ui.panel
    diffview.scene.views.diff.file_panel diffview.scene.views.diff.render
    diffview.ui.panels.commit_log_panel diffview.scene.views.diff.listeners
    diffview.scene.layouts.diff_3 diffview.scene.layouts.diff_3_hor diffview.diff
    diffview.scene.layouts.diff_1 diffview.scene.views.file_history.file_history_view]],
  -- neogit 은 넣지 않는다: neogit.lib.git.repository 가 불릴 때의 현재 디렉터리를 저장소로
  -- 잡아 두어(lastDir), 미리 부르면 그 뒤 :cd 한 곳이 아니라 시작한 곳을 볼 수 있다.
  -- 처음 \s 의 대부분(192ms 중 176ms)도 모듈이 아니라 git 이다
}

-- treesitter: { 언어, 쿼리 } (쿼리 nil = 파서만). 무거운 것(heavy)은 초점을 잃었을 때만.
-- nvim 의 쿼리 캐시는 약한 표라 잡아 두지 않으면 다음 GC 에 사라진다 (W.keep)
-- cpp 는 .h 가 cpp 일 때(nvim 기본)만 - g:c_syntax_for_h 로 .h 가 c 이면 C++ 파일을 연
-- 세션에서만 (안 쓸 쿼리를 컴파일해 들고 있지 않게)
local TS = {
  { 'cpp' }, { 'cpp', 'injections' }, { 'cpp', 'aerial' }, -- 첫 .h (C 프로젝트의 .h 도 cpp)
  { 'c', 'highlights', heavy = true }, { 'c', 'injections' }, { 'c', 'aerial' },
  { 'vimdoc' }, { 'vimdoc', 'highlights' }, { 'vimdoc', 'injections' }, { 'vimdoc', 'aerial' }, -- :help
  { 'cpp', 'highlights', heavy = true }, -- ~145ms, 쪼갤 수 없다
}

local W = {
  items = nil, -- 할 일 { name, fn, heavy, group }
  stats = {}, -- 한 일 { name, ms, err, heavy }
  keep = {}, -- treesitter 쿼리 (약한 캐시에서 사라지지 않게)
  skip = {}, -- 없는 플러그인 묶음
  last_key = 0,
  focused = true,
  tok = 0, -- 걸어 둔 칸 (새로 걸면 앞의 것은 빈손으로 끝난다)
  ns = nil,
  busy = nil, -- 마지막으로 칸을 미룬 까닭 (:VimIdeWarmup)
  started = false,
  finished = false,
  max_ms = 0,
  waits = 0, -- 지금 돌고 있는 vim.wait 의 깊이 (그 안에서는 칸을 돌리지 않는다)
  wait_orig = nil,
  wait_fn = nil,
}

local function enabled()
  local v = vim.g.vimide_warmup
  return v == nil or (v ~= 0 and v ~= false)
end

local function cpp_wanted()
  local h = vim.g.c_syntax_for_h
  if h == nil or h == 0 or h == false then
    return true
  end
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'cpp' then
      return true
    end
  end
  return false
end

local function build()
  local items = {}
  for gi, list in ipairs(MODS) do
    local first = true
    for name in list:gmatch('%S+') do
      local is_first = first
      first = false
      items[#items + 1] = {
        name = name,
        mod = name,
        group = gi,
        fn = function()
          if package.loaded[name] ~= nil then
            return
          end
          local ok, err = pcall(require, name)
          if not ok and is_first then
            W.skip[gi] = true -- 플러그인이 없다: 이 묶음의 나머지도
          end
          if not ok then
            error(err, 0)
          end
        end,
      }
      if name == 'neo-tree.utils.filesize.filesize' then -- neo-tree 묶음의 끝
        -- 모듈이 다 불린 뒤 설정 합치기 (모듈을 앞서 불러 두어 이 칸은 짧다)
        items[#items + 1] = {
          name = 'neo-tree.ensure_config()',
          group = gi,
          fn = function()
            local nt = package.loaded['neo-tree']
            if type(nt) == 'table' and type(nt.ensure_config) == 'function' then
              nt.ensure_config()
            end
          end,
        }
      end
    end
  end
  for _, t in ipairs(TS) do
    local lang, query = t[1], t[2]
    items[#items + 1] = {
      name = 'ts ' .. lang .. (query and ('/' .. query) or ''),
      heavy = t.heavy,
      -- 파서 .so 와 쿼리 .scm 도 뒤에서 미리 읽는다 (dlopen·query.get 이 읽을 것)
      file = query and ('queries/' .. lang .. '/' .. query .. '.scm') or ('parser/' .. lang .. '.so'),
      fn = function()
        if lang == 'cpp' and not cpp_wanted() then
          return
        end
        if not pcall(vim.treesitter.language.add, lang) or not query then
          return
        end
        local q = vim.treesitter.query.get(lang, query)
        if q then
          W.keep[#W.keep + 1] = q
        end
      end,
    }
  end
  return items
end

-- 다음 몇 모듈(과 파서 .so, 쿼리)의 파일을 뒤에서(libuv 스레드 풀) 미리 읽어 둔다. 처음 여는
-- 파일은 디스크와 맥의 실시간 검사(Defender)가 수십 ms 를 잡는데(실측: plenary.scandir
-- 벽시계 41ms, CPU 2ms), 그 기다림이 칸 밖으로 나가 require 는 캐시에서 읽는다
local PREFETCH = 10
local function prefetch(from)
  local n = 0
  for k = from, #W.items do
    local it = W.items[k]
    if n >= PREFETCH then
      return
    end
    if (it.mod or it.file) and not it.fetched
        and not (it.mod and package.loaded[it.mod] ~= nil) then
      it.fetched = true
      n = n + 1
      local files
      if it.mod then
        local rel = 'lua/' .. (it.mod:gsub('%.', '/'))
        files = { api.nvim_get_runtime_file(rel .. '.lua', false)[1]
            or api.nvim_get_runtime_file(rel .. '/init.lua', false)[1] }
      else
        files = api.nvim_get_runtime_file(it.file, true) -- 쿼리는 after/ 의 것까지
      end
      for _, f in ipairs(files) do
        uv.fs_open(f, 'r', 438, function(err, fd)
          if not err and fd then
            uv.fs_read(fd, 4194304, 0, function()
              uv.fs_close(fd)
            end)
          end
        end)
      end
    end
  end
end

-- vim.wait 안에서는 칸을 돌리지 않는다. vim.wait 는 기다리는 동안 타이머·schedule 콜백을
-- 돌리는데, diffview/neogit 은 코루틴 안에서 vim.wait 를 쓴다(diffview job.lua, async.lua).
-- 이 맥(nvim 0.12.4 + Homebrew LuaJIT)에서는 그런 vim.wait 안으로 Lua 가 다시 들어가면
-- SIGBUS 로 죽는 일이 있다 (QA 하네스 README: Lua RPC 를 초당 100번 넣으면 매번 죽었다).
-- 시작 직후 :DiffviewOpen 은 이것(과 아래 칸 안의 jit.off) 없이 6번에 5번 죽었고, 넣은
-- 뒤로는 16번에 5번이다 (미리 부르기를 끈 nvim 16번에 12번 - 원래 있던 문제다). 그래서
-- 칸을 돌리는 동안만 vim.wait 를 감싸 깊이를 세고, 그 안이면 쉰다. 가벼운 것을 다 하면
-- 되돌린다 (그 사이 남이 또 감쌌으면 손대지 않는다).
local function pack(...)
  return { n = select('#', ...), ... }
end

local function unwrap_wait()
  if W.wait_fn and vim.wait == W.wait_fn then
    vim.wait = W.wait_orig
  end
  W.wait_fn = nil
end

local function wrap_wait()
  if W.wait_fn then
    return
  end
  local orig = vim.wait
  W.wait_orig = orig
  W.wait_fn = function(...)
    W.waits = W.waits + 1
    local r = pack(pcall(orig, ...))
    W.waits = W.waits - 1
    if not r[1] then
      error(r[2], 0) -- 기다리던 조건 함수의 오류는 그대로 부른 쪽으로
    end
    return unpack(r, 2, r.n)
  end
  vim.wait = W.wait_fn
end

local function finish()
  W.finished = true
  W.tok = W.tok + 1
  if W.ns then
    vim.on_key(nil, W.ns)
  end
  unwrap_wait()
  pcall(api.nvim_del_augroup_by_name, 'VimIdeWarmup')
end

-- 남은 것 (없는 플러그인 묶음은 뺀다). 초점이 있으면 가벼운 것만 고른다
local function next_item(allow_heavy)
  local left = false
  for i, it in ipairs(W.items) do
    if not (it.group and W.skip[it.group]) then
      left = true
      if allow_heavy or not it.heavy then
        return i, it, true
      end
    end
  end
  return nil, nil, left
end

local tick

-- ms 뒤에 한 칸 (vim.defer_fn - 타이머는 그때마다 닫힌다). 앞서 걸어 둔 칸은 버린다
local function later(ms)
  W.tok = W.tok + 1
  local tok = W.tok
  vim.defer_fn(function()
    if tok == W.tok then
      tick()
    end
  end, ms)
end

tick = function()
  if W.finished then
    return
  end
  if not enabled() then
    return finish()
  end
  local quiet = uv.now() - W.last_key >= IDLE_MS
  local m = api.nvim_get_mode()
  local busy = (not quiet and '키') or (W.waits > 0 and 'vim.wait') or (m.blocking and '물음')
      or (m.mode ~= 'n' and ('모드 ' .. m.mode)) or (vim.fn.state('mo') ~= '' and 'state')
  W.busy = busy
  if busy then
    return later(IDLE_MS) -- 쓰는 중이다 (또는 누가 vim.wait 로 기다린다): 쉬면 이어 간다
  end
  if not W.items then
    W.items = build()
    prefetch(1) -- 첫 칸들의 파일부터 뒤에서 읽어 두고, 다 읽혔을 즈음 시작한다
    return later(100)
  end
  local i, it, left = next_item(not W.focused)
  if not i then
    if not left then
      return finish()
    end
    -- 가벼운 것은 다 했다. 무거운 것은 초점을 잃을 때까지 (FocusLost 가 다시 건다).
    -- 그때까지 vim.wait 는 되돌려 둔다
    return unwrap_wait()
  end
  table.remove(W.items, i)
  local t0 = uv.hrtime()
  -- 칸 안에서는 JIT 를 끈다 (모듈 몸통은 한 번 돌고 마는 코드라 잃는 것이 없다). 이 맥의
  -- LuaJIT 는 JIT 기계어 쪽에서 SIGBUS 로 죽는다 (QA-04, jit.off 면 0번) - 미리 부르기가
  -- 그 기계어를 늘리지 않게
  local j = rawget(_G, 'jit')
  local jon = j and j.status and j.status()
  if jon then
    j.off()
  end
  local ok, err = pcall(it.fn)
  if jon then
    j.on()
  end
  local ms = (uv.hrtime() - t0) / 1e6
  W.stats[#W.stats + 1] = { it.name, ms, not ok and tostring(err):match('^[^\n]*') or nil, it.heavy }
  if not it.heavy and ms > W.max_ms then
    W.max_ms = ms
  end
  prefetch(i)
  -- 칸이 길었으면(기계가 바쁘다) 그만큼 더 쉬었다 간다 - 키가 칸과 겹칠 틈을 줄인다
  later(math.max(GAP_MS, math.floor(ms * 2)))
end

local function start()
  if not enabled() or W.started then
    return
  end
  W.started = true
  wrap_wait()
  W.ns = api.nvim_create_namespace('vimide_warmup')
  W.last_key = 0 -- 시작할 때 미리 친 키(typeahead)는 on_key 가 적는다
  -- 키마다 시각만 적는다 (가장 싼 일). 다 하면 거둔다
  vim.on_key(function()
    W.last_key = uv.now()
  end, W.ns)
  local group = api.nvim_create_augroup('VimIdeWarmup', { clear = true })
  api.nvim_create_autocmd('FocusLost', {
    group = group,
    callback = function()
      W.focused = false
      wrap_wait()
      later(200)
    end,
  })
  api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      W.focused = true
    end,
  })
  later(START_MS)
end

api.nvim_create_user_command('VimIdeWarmup', function()
  local lines, total, heavy = {}, 0, {}
  for _, s in ipairs(W.stats) do
    total = total + s[2]
    if s[3] or s[2] >= 5 or s[4] then
      lines[#lines + 1] = ('  %7.1f ms  %s%s%s'):format(s[2], s[1], s[4] and ' (초점 잃었을 때)' or '',
        s[3] and ('  ! ' .. s[3]) or '')
    end
  end
  for _, it in ipairs(W.items or {}) do
    if not (it.group and W.skip[it.group]) then
      heavy[#heavy + 1] = it.name
    end
  end
  local state = W.finished and '끝' or (W.items and '도는 중' or (W.started and '시작 전' or '꺼짐'))
  if not W.finished and W.busy then
    state = state .. ' (쉬는 중: ' .. W.busy .. ')'
  end
  local head = ('미리 불러 두기: %s - %d칸, 합 %.0f ms, 가장 긴 칸 %.1f ms (가벼운 것)'):format(
    state, #W.stats, total, W.max_ms)
  local out = { head }
  if #lines > 0 then
    out[#out + 1] = ' 5ms 이상 / 오류:'
    vim.list_extend(out, lines)
  end
  if #heavy > 0 then
    out[#out + 1] = ' 남은 것: ' .. table.concat(heavy, ', ')
  end
  api.nvim_echo({ { table.concat(out, '\n') } }, false, {})
end, { desc = '쉬는 동안 미리 불러 둔 모듈 (vimidewarm.lua)' })

if vim.v.vim_did_enter == 1 then
  start()
else
  api.nvim_create_autocmd('VimEnter', {
    group = api.nvim_create_augroup('VimIdeWarmupStart', { clear = true }),
    once = true,
    callback = start,
  })
end
