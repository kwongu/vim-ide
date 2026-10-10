-- treepin.lua - \P: neo-tree 트리의 실시간 경로 모드 / 고정 모드 (토글)
--
-- 기본은 실시간 경로 모드다: 트리가 편집 파일을 따라간다. 모드는 둘로 따로 간다 (요청).
--   * F9 사이드바와 F11 부동 트리      g:vimide_tree_pinned       (기본 0 = 실시간 경로)
--   * F12 RelationView 열의 트리       g:relationview_tree_pinned (기본 0 = 실시간 경로)
-- 한쪽을 고정해도 다른 쪽은 그대로 따라간다. 아래 '고정' 설명은 고정 모드에서 무엇이
-- 멈추는지다.
--
-- EDIT 창에서 파일을 옮겨 다니면 neo-tree 가 그 파일까지 펼치고 커서를 옮긴다
-- (filesystem.follow_current_file). 다른 곳을 보면서 트리는 그대로 두고 싶을 때 \P 로
-- 고정한다.
--
--   \P                     고정 / 풀기. 어느 쪽을 바꿀지는 누른 곳으로 정한다:
--                            RelationView 열(트리·관계 목록·미리보기)에서 누르면 F12 트리,
--                            F9/F11 트리에서 누르면 그 트리. 편집 창에서 누르면 이 탭에
--                            보이는 트리 - F9 사이드바가 파일 트리로 떠 있으면 그것, 아니고
--                            RelationView 트리가 있으면 그것, 아무것도 없으면 F9/F11
--   :VimIdeTreePin         F9/F11 트리만.  :VimIdeTreePin on / off 로 정해서도
--   :RelationViewTreePin   F12 트리만.     :RelationViewTreePin on / off 로 정해서도
--
-- 시작할 때와 다른 모드가 된 트리 창마다 맨 위에 '[고정] \P 로 실시간 경로' (또는
-- '[실시간 경로] \P 로 고정') 가 뜬다. 되돌리면 그 줄이 사라진다. 풀 때는 그 트리가 곧바로
-- 지금 파일로 한 번 따라간다 (F9/F11 은 편집 창에서 풀었을 때, F12 는 그 트리 창 밖에서
-- 풀었을 때 - 그 트리 안이면 편집 창으로 돌아가는 순간 따라간다). 고정은 따라가기만
-- 막는다: 트리에서 직접 펼치기·열기, :Neotree reveal 처럼 일부러 드러내는 것은 된다. 고정
-- 중에 여는 트리는 지금 파일까지 펼치지 않는다 - 보던 자리(처음이면 뿌리)로 열린다.
-- 파일 트리(filesystem)만이다 - neo-tree 의 buffers 보기(< > 로 바꾸는 것)는 그대로
-- 따라가고, 거기에는 표시도 달지 않는다.
--
-- F12 트리의 따라가기는 relationview.lua 가 따로 한다 (follow_file 이
-- g:relationview_tree_pinned 를 본다). 여기서는 그 모드 값과 표시만 다룬다.
--
-- F9/F11 트리에서 막는 곳은 셋이다.
--   * neo-tree 의 BufEnter 따라가기 - 그 처리기는 follow_current_file.enabled 를 다시
--     보지 않고 filesystem.follow() 를 부르므로 follow 를 감싼다
--   * neo-tree 가 트리를 다시 그릴 때(git 표시 갱신 등)의 따라가기 - 상태마다의
--     follow_current_file.enabled 를 보므로 그 값을 끈다
--   * 새로 여는 트리 - 상태는 소스 기본 설정(neo-tree.setup 의 config.filesystem)을 복사해
--     만들어진다. 그 설정은 neo-tree 가 트리를 처음 열 때에야 합쳐 두므로(ensure_config),
--     ensure_config 를 감싸 합친 바로 뒤에 고친다 - 시작부터 고정이면 첫 트리가 그 파일까지
--     펼쳐졌다
-- (RelationView 열의 트리는 position=current 라 neo-tree 의 따라가기를 타지 않는다 - 상태를
-- 고치는 둘째·셋째는 그 트리의 상태에도 닿지만 효과가 없다)
--
-- neo-tree 의 모듈을 미리 부르지 않는다 (시작이 15ms 느려졌다). 감싸기는 트리가 처음
-- 생길 때(FileType neo-tree) 한다 - 그 전에는 따라갈 트리도 없다.
--
--   let g:vimide_tree_pinned = 1         " F9/F11 트리를 처음부터 고정 모드로
--   let g:relationview_tree_pinned = 1   " F12 트리를 처음부터 고정 모드로

if vim.g.loaded_vimide_treepin then
  return
end
vim.g.loaded_vimide_treepin = 1

local api = vim.api
local saved -- 고정하기 전의 follow_current_file.enabled (풀 때 되돌린다)

local function hl()
  api.nvim_set_hl(0, 'VimIdeTreePinned', { link = 'WarningMsg', default = true })
end
hl()

local function pinned()
  return vim.g.vimide_tree_pinned == 1
end
local function rv_pinned()
  return vim.g.relationview_tree_pinned == 1
end
-- 시작할 때의 모드 (.vimrc 의 두 값). 표시는 이것과 다른 모드일 때만 단다 -
-- 고정이 기본이 되자 모든 트리에 늘 '[고정]' 한 줄이 서 있었다
local start_pinned = vim.g.vimide_tree_pinned == 1
local start_rv_pinned = vim.g.relationview_tree_pinned == 1

-- 새 트리 상태가 복사해 가는 소스 기본 설정. neo-tree 가 아직 합치지 않았으면 nil
local function fs_follow_config()
  local setup = package.loaded['neo-tree.setup']
  local c = setup and setup.config and setup.config.filesystem
  return c and c.follow_current_file
end

-- 기본 설정을 지금 고정 상태에 맞춘다. 돌려주는 것: 따라가기를 켤지 (설정이 없으면 nil)
local function patch_cfg()
  local cfg = fs_follow_config()
  if not cfg then
    return nil
  end
  if pinned() then
    if saved == nil then
      saved = cfg.enabled
    end
    cfg.enabled = false
    return false
  end
  local want = saved
  if want == nil then
    want = cfg.enabled
  end
  if want == nil then
    want = true
  end
  saved = nil
  cfg.enabled = want
  return want
end

local function set_states(on)
  local mgr = package.loaded['neo-tree.sources.manager']
  if mgr then
    pcall(mgr._for_each_state, 'filesystem', function(st)
      if st.follow_current_file then
        st.follow_current_file.enabled = on
      end
    end)
  end
end

-- filesystem.follow (BufEnter 처리기가 부르는 것)을 한 번만 감싼다. 이미 불려 있을 때만
local function wrap_follow()
  local fs = package.loaded['neo-tree.sources.filesystem']
  if type(fs) ~= 'table' then
    return nil
  end
  if not fs._vimide_pin_wrapped and type(fs.follow) == 'function' then
    local orig = fs.follow
    fs.follow = function(...)
      if pinned() then
        return false
      end
      return orig(...)
    end
    fs._vimide_pin_wrapped = true
  end
  return fs
end

-- neo-tree 가 설정을 합친 바로 뒤에 고정 값을 넣는다 (상태가 복사해 가기 전)
local function hook_merge()
  local nt = package.loaded['neo-tree']
  if type(nt) ~= 'table' or nt._vimide_pin_hooked or type(nt.ensure_config) ~= 'function' then
    return
  end
  local orig = nt.ensure_config
  nt.ensure_config = function(...)
    local c = orig(...)
    if pinned() then
      pcall(patch_cfg)
      pcall(wrap_follow)
    end
    return c
  end
  nt._vimide_pin_hooked = true
end

-- 고정 표시. 우리 것은 값으로 알아본다 - 창 변수로 '우리가 달았다' 를 적었더니, 트리에서
-- < > 로 보기를 바꾸었다 돌아오거나 :split 하면 그 값이 버퍼·새 창을 따라가 풀린 뒤에도
-- 남았다. 다른 것이 winbar 를 쓰고 있으면 손대지 않는다
local BAR_PIN = '%#VimIdeTreePinned# [고정] \\P 로 실시간 경로 %*'
local BAR_LIVE = '%#VimIdeTreePinned# [실시간 경로] \\P 로 고정 %*'

-- neo-tree 창이 어느 모드를 따르나: 'rv' = F12 RelationView 열의 트리(w:rv_tree, 그 열 안에서
-- :split 한 사본도), 'fs' = 그 밖의 neo-tree 창 (F9 사이드바, F11 부동 창). neo-tree 창이 아니면 nil
local function tree_kind(win)
  local buf = api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype ~= 'neo-tree' then
    return nil
  end
  if vim.w[win].rv_tree then
    return 'rv'
  end
  if vim.b[buf].neo_tree_position == 'current' and _G.relationview_owns_win
      and _G.relationview_owns_win(win) then
    return 'rv'
  end
  return 'fs'
end

-- 고정되는 트리 창: neo-tree 파일 트리. 돌려주는 것은 tree_kind 와 같다
local function pinnable(win)
  local kind = tree_kind(win)
  if kind and vim.b[api.nvim_win_get_buf(win)].neo_tree_source == 'filesystem' then
    return kind
  end
  return nil
end

local function mark_win(win)
  if not api.nvim_win_is_valid(win) then
    return
  end
  local cur = vim.wo[win].winbar
  local kind = pinnable(win)
  local on, start = pinned(), start_pinned
  if kind == 'rv' then
    on, start = rv_pinned(), start_rv_pinned
  end
  local bar = on and BAR_PIN or BAR_LIVE
  local want = kind ~= nil and on ~= start
  if want and (cur == '' or cur == BAR_PIN or cur == BAR_LIVE) then
    vim.wo[win].winbar = bar
  elseif not want and (cur == BAR_PIN or cur == BAR_LIVE) then
    vim.wo[win].winbar = ''
  end
end

local function mark_all()
  for _, w in ipairs(api.nvim_list_wins()) do
    pcall(mark_win, w)
  end
end

local function apply()
  hook_merge()
  local want = patch_cfg()
  if pinned() then
    set_states(false)
  elseif want ~= nil then
    set_states(want)
  end
  wrap_follow()
  mark_all()
end

-- 모드를 알린다 (고정이면 경고 색). 61칸 안으로 적는다 - 80칸 화면에서 showcmd·ruler 를 빼면
-- 67칸이 남고, 상태줄이 없는 F11 부동 창에서는 ruler 가 명령줄 63칸째부터 앉는다. 그래도 넘으면 fitmsg.lua 가 가운데를 줄인다 (한 줄이 화면 폭을 넘으면 Press
-- ENTER 가 떠서 다음 키를 먹는다)
local function say(msg, warn)
  if type(_G.vimide_notify) == 'function' then
    _G.vimide_notify(msg, warn and vim.log.levels.WARN or vim.log.levels.INFO)
  else
    api.nvim_echo({ { msg, warn and 'WarningMsg' or 'None' } }, false, {})
  end
end

-- 편집 창에서 풀었으면 곧바로 지금 파일로 한 번 따라간다. 트리나 곁창에서 풀었으면
-- 편집 창에 들어가는 순간 neo-tree 가 따라가므로 따로 할 일이 없다
local function catch_up()
  if vim.bo.buftype ~= '' or api.nvim_buf_get_name(0) == '' then
    return
  end
  local fs = wrap_follow()   -- 트리를 한 번도 안 열었으면 nil - 따라갈 트리가 없다
  if fs and fs.follow then
    pcall(fs.follow)
  end
end

-- F9 사이드바·F11 부동 트리의 모드
function _G.vimide_tree_pin(on)
  if on == nil then
    on = not pinned()
  end
  vim.g.vimide_tree_pinned = on and 1 or 0
  apply()
  if not on then
    catch_up()
  end
  -- 되돌리는 길은 늘 맞는 것으로 적는다: 편집 창의 \\P 는 보이는 트리에 따라 F12 를 바꿀 수 있다
  say(on and 'F9/F11 트리 고정 (트리에서 \\P 또는 :VimIdeTreePin off)'
    or 'F9/F11 트리 실시간 경로 (트리에서 \\P 또는 :VimIdeTreePin on)', on)
end

-- F12 RelationView 열의 트리의 모드. 따라가기는 relationview.lua 가 이 값을 보고 한다
function _G.vimide_rv_tree_pin(on)
  if on == nil then
    on = not rv_pinned()
  end
  vim.g.relationview_tree_pinned = on and 1 or 0
  mark_all()
  if not on and _G.relationview_tree_catch_up then
    pcall(_G.relationview_tree_catch_up)
  end
  local msg = on and 'F12 트리 고정 (열에서 \\P 또는 :RelationViewTreePin off)'
    or 'F12 트리 실시간 경로 (열에서 \\P 또는 :RelationViewTreePin on)'
  if not on and tonumber(vim.g.relationview_tree_follow) == 0 then
    -- 따라가기 자체를 꺼 두었다 (relationview.lua 의 follow_file 이 먼저 본다)
    msg = 'F12 트리 실시간 경로 - g:relationview_tree_follow=0 이라 안 따라감'
  end
  say(msg, on)
end

-- \P 가 바꿀 모드: 'rv' (F12 트리) 또는 'fs' (F9/F11 트리). 머리말의 규칙대로
local function target()
  local cur = api.nvim_get_current_win()
  local kind = tree_kind(cur)
  if kind then
    return kind
  end
  if _G.relationview_owns_win and _G.relationview_owns_win(cur) then
    return 'rv'
  end
  local rv = false
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    -- F9 사이드바는 파일 트리일 때만 친다 - buffers 보기(< >)는 고정하지 않으니 바꿔도 보이는 것이 없다
    if pinnable(w) == 'fs' and api.nvim_win_get_config(w).relative == '' then
      return 'fs' -- F9 사이드바가 보인다
    elseif tree_kind(w) == 'rv' then
      rv = true
    end
  end
  return rv and 'rv' or 'fs'
end

local function pin_cmd(fn)
  return function(o)
    local a = vim.trim(o.args)
    if a == 'on' then
      fn(true)
    elseif a == 'off' then
      fn(false)
    else
      fn()
    end
  end
end

local function on_off()
  return { 'on', 'off' }
end
api.nvim_create_user_command('VimIdeTreePin', pin_cmd(function(on) _G.vimide_tree_pin(on) end), {
  nargs = '?',
  complete = on_off,
  desc = 'F9/F11 neo-tree 트리 고정 (편집 파일을 따라가지 않게) 켜고 끄기',
})
api.nvim_create_user_command('RelationViewTreePin', pin_cmd(function(on) _G.vimide_rv_tree_pin(on) end), {
  nargs = '?',
  complete = on_off,
  desc = 'F12 RelationView 열의 트리 고정 (편집 파일을 따라가지 않게) 켜고 끄기',
})

vim.keymap.set('n', '<Leader>P', function()
  if target() == 'rv' then
    _G.vimide_rv_tree_pin()
  else
    _G.vimide_tree_pin()
  end
end, { silent = true, desc = '트리 고정 모드 <-> 실시간 경로 모드 (RelationView 열에서는 F12 트리, F9/F11 트리에서는 그 트리, 편집 창에서는 보이는 트리: F9 파일 트리 > F12 트리 > F9/F11)' })

local group = api.nvim_create_augroup('VimIdeTreePin', { clear = true })
-- 트리가 생기면 감싸고(처음 한 번), 고정 중이면 새 상태의 따라가기도 끈다
api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'neo-tree',
  callback = function()
    vim.schedule(function()
      hook_merge()
      wrap_follow()
      if pinned() then
        patch_cfg()
        set_states(false)
      end
      mark_all()
    end)
  end,
})
-- 창에 버퍼가 들어올 때마다 표시를 맞춘다 (트리가 아닌 버퍼가 들어오면 거둔다)
api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  callback = function(ev)
    vim.schedule(function()
      if api.nvim_buf_is_valid(ev.buf) then
        for _, w in ipairs(vim.fn.win_findbuf(ev.buf)) do
          pcall(mark_win, w)
        end
      end
    end)
  end,
})
-- 탭을 옮기면 그 탭의 표시를 다시 맞춘다. 다른 탭에서 모드를 바꾸면 그 탭의 RelationView 트리 사본은
-- 지금 탭에서만 알아보는 잣대(relationview_owns_win) 탓에 F9/F11 것으로 쳐졌다
api.nvim_create_autocmd('TabEnter', {
  group = group,
  callback = function()
    vim.schedule(function()
      for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
        pcall(mark_win, w)
      end
    end)
  end,
})
api.nvim_create_autocmd('ColorScheme', { group = group, callback = hl })

-- 시작 값. neo-tree 본 모듈은 .vimrc 의 setup 에서 이미 불려 있어 감싸는 데 비용이 없다
local function init()
  hook_merge()
  if pinned() then
    apply()
  end
end
if vim.v.vim_did_enter == 1 then
  vim.schedule(init)
else
  api.nvim_create_autocmd('VimEnter', {
    group = group,
    once = true,
    callback = function()
      vim.schedule(init)
    end,
  })
end
