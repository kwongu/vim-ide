-- vimidewin.lua - 창의 역할을 지킨다
--
-- 두 가지를 한다.
--
--   1. 곁창(플러그인 창)에서는 그 플러그인 일만 하게 한다.
--      파일이 곁창에 실리면 그 파일을 '직전에 보던 EDIT 창'으로 옮기고,
--      곁창은 원래 내용으로 되돌린다.
--
--   2. EDIT 창은 최소 하나를 지킨다.
--      곁창만 남고 EDIT 창이 0개가 되면 vim 을 끝낸다.
--
-- 왜 한 파일에 같이 두나: 둘 다 '이 창이 EDIT 창인가'라는 같은 질문에
-- 매달려 있기 때문이다. 이 설정에는 그 판정기가 서로 다른 기준으로 넷이나
-- 흩어져 있었다(overview.lua:120, relationview.lua 의 is_edit_win,
-- projectfiles.lua, vimide#qf#Usable). 여기서 하나를 정본으로 세우고
-- _G.vimide_is_edit_win 으로 내놓는다.
--
-- 끄는 법:
--   let g:vimide_win_guard    = 0   " 1번(곁창 보호) 끄기
--   let g:vimide_min_edit_win = 0   " 2번(EDIT 최소 1개) 끄기
--
-- nvim 전용이다. 개발서버의 진짜 vim 8.1 은 .vim/plugin/*.lua 를 읽지 않으니
-- 거기서는 이 규칙이 통째로 없다 - 그쪽은 예전 그대로 동작한다.

if vim.fn.has('nvim') ~= 1 then
  return
end

local api = vim.api

local function cfg(name, default)
  local v = vim.g['vimide_' .. name]
  if v == nil then
    return default
  end
  -- false / v:false 로 끄는 사람이 있다. tonumber(false) 는 nil 이라
  -- 그대로 두면 default 로 되돌아가 '껐는데 켜진 채'가 된다.
  if v == false or v == 0 then
    return 0
  end
  if v == true then
    return 1
  end
  return tonumber(v) or default
end

-- ---------------------------------------------------------------------------
-- 이 창이 EDIT 창인가
-- ---------------------------------------------------------------------------
-- 흩어져 있던 넷을 합쳤다. 가장 촘촘하던 overview.lua 의 판정을 뼈대로,
-- relationview 의 '자기 창 제외'와 qf.vim 의 &previewwindow 를 더했다.

-- 곁창임이 확실한 filetype
local PLUGIN_FT = {
  ['neo-tree'] = true, ['neo-tree-popup'] = true,
  ['nerdtree'] = true, ['tagbar'] = true, ['aerial'] = true,
  ['qf'] = true, ['relationview'] = true, ['overview'] = true,
  ['NvimTree'] = true, ['netrw'] = true, ['bufexplorer'] = true,
  ['help'] = true, ['man'] = true, ['fugitive'] = true,
  ['DiffviewFiles'] = true, ['DiffviewFileHistory'] = true,
}

-- 곁창임이 확실한 버퍼 '파일 이름'(경로 말고 마지막 조각) 패턴.
--
-- 경로 전체에 대고 찾으면 진짜 소스 파일을 곁창으로 오해한다. 실제로
-- 이 저장소 안에 .vim/plugged/nerdtree/plugin/NERD_tree.vim 이 있다 -
-- 그 파일을 열어 고치는 동안 그 창이 EDIT 창이 아니게 되면, 곁창 하나만
-- 닫아도 'EDIT 0개' 로 계산되어 nvim 이 꺼진다.
local PLUGIN_NAME = {
  '^RelationView$',          -- 패널
  '^RelationView%-',         -- 미리보기(작은/큰 둘 다)
  '^NERD_tree_',             -- NERD_tree_1 / NERD_tree_tab_1
  '^%[BufExplorer%]$',
  '^neo%-tree filesystem',
}

local function is_plugin_buf(buf)
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return true -- 알 수 없으면 편집 창으로 치지 않는다
  end
  if vim.bo[buf].buftype ~= '' then
    return true -- nofile / quickfix / terminal / prompt / help ...
  end
  local ft = vim.bo[buf].filetype or ''
  if PLUGIN_FT[ft] or ft:match('^Telescope') or ft:match('^Neogit') then
    return true
  end
  local base = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ':t')
  for _, pat in ipairs(PLUGIN_NAME) do
    if base:match(pat) then
      return true
    end
  end
  return false
end

--- 이 창을 '파일을 열어도 되는 EDIT 창'으로 볼 수 있는가.
--- @param win integer|nil 창 id (없으면 지금 창)
function _G.vimide_is_edit_win(win)
  win = win or api.nvim_get_current_win()
  if not (win and api.nvim_win_is_valid(win)) then
    return false
  end
  if api.nvim_win_get_tabpage(win) ~= api.nvim_get_current_tabpage() then
    return false
  end
  -- 부동 창(telescope, overview 막대, 각종 popup)은 EDIT 창이 아니다.
  -- relationview 쪽 판정이 이것을 빠뜨리고 있었다.
  local ok, conf = pcall(api.nvim_win_get_config, win)
  if ok and conf and conf.relative and conf.relative ~= '' then
    return false
  end
  -- quickr-preview 의 pedit 창은 buftype 도 filetype 도 평범한 파일과 같다.
  -- &previewwindow 로만 갈린다.
  if vim.wo[win].previewwindow then
    return false
  end
  return not is_plugin_buf(api.nvim_win_get_buf(win))
end

--- 지금 탭의 EDIT 창 목록. '파일을 어디에 열까'는 지금 탭 안에서 고른다.
--- @param skip integer|nil 세지 않을 창 (닫히는 중인 창을 빼는 데 쓴다)
function _G.vimide_edit_wins(skip)
  local out = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if w ~= skip and _G.vimide_is_edit_win(w) then
      out[#out + 1] = w
    end
  end
  return out
end

--- 모든 탭을 통틀어 EDIT 창이 몇 개인가.
---
--- '끝낼까'는 반드시 이쪽으로 센다. 지금 탭만 보면 다른 탭에 편집 창이
--- 멀쩡히 있어도 nvim 이 통째로 꺼진다 - neogit 은 kind='tab' 이라 늘 새
--- 탭에 뜨고, 그 탭에는 곁창밖에 없어서 거기서 창 하나만 닫아도 발동한다.
--- @param skip integer|nil 세지 않을 창
function _G.vimide_edit_win_count_all(skip)
  local n = 0
  local cur = api.nvim_get_current_tabpage()
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    for _, w in ipairs(api.nvim_tabpage_list_wins(tab)) do
      -- is_edit_win 은 '지금 탭' 조건을 달고 있어 남의 탭을 못 센다.
      -- 여기서는 그 조건만 빼고 같은 잣대를 쓴다.
      if w ~= skip and api.nvim_win_is_valid(w) then
        local ok, conf = pcall(api.nvim_win_get_config, w)
        local floating = ok and conf and conf.relative and conf.relative ~= ''
        if not floating and not vim.wo[w].previewwindow
            and not is_plugin_buf(api.nvim_win_get_buf(w)) then
          n = n + 1
        end
      end
    end
  end
  local _ = cur
  return n
end

--- 살아 있는 터미널 작업이 붙은 창이 있는가.
--- 빌드나 ssh 를 돌려 두고 편집 창을 닫았을 뿐인데 20분짜리 작업이
--- 말없이 죽으면 안 된다.
function _G.vimide_has_live_terminal()
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    for _, w in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if api.nvim_win_is_valid(w) then
        local b = api.nvim_win_get_buf(w)
        if api.nvim_buf_is_valid(b) and vim.bo[b].buftype == 'terminal' then
          return true
        end
      end
    end
  end
  return false
end

-- 나가는 중이거나 세션을 되살리는 중인가. 둘 다일 때는 아무 규칙도 돌면 안 된다.
local function busy()
  if vim.v.exiting ~= vim.NIL then
    return true
  end
  local sess = _G.vimide_session
  if type(sess) == 'table' and type(sess.is_restoring) == 'function' then
    local ok, r = pcall(sess.is_restoring)
    if ok and r then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- 1. 곁창에 실린 파일을 EDIT 창으로 돌려보낸다
-- ---------------------------------------------------------------------------
-- 마우스 매핑과 같은 사정이다. 파일이 곁창에 실리는 길은 한둘이 아니다 -
-- gf, <C-^>, :edit/:find/:buffer 를 직접 치기, 전역 버퍼 순환 매핑(,r ,e ,w
-- ,1~,0), 남의 플러그인이 고른 창... 길마다 가드를 다는 대신, 실리고 난
-- '뒤'를 한 곳에서 되돌린다.
--
-- RelationView 패널/미리보기 세 창에는 winfixbuf 가 걸려 있어 애초에 거부되고
-- (E1513), 여기 오는 것은 그것이 없는 나머지 곁창들이다.

local guarded = {} -- winid -> { buf = 곁창 버퍼, kind = 'quickfix'|'loclist'|'other' }
local sweeping = false

local function kind_of(buf)
  if vim.bo[buf].buftype == 'quickfix' then
    -- quickfix 와 location list 는 buftype 도 filetype 도 같다
    local ok, info = pcall(vim.fn.getwininfo, vim.fn.bufwinid(buf))
    if ok and info and info[1] and info[1].loclist == 1 then
      return 'loclist'
    end
    return 'quickfix'
  end
  return 'other'
end

-- 이 곁창을 어떻게 다시 세우나. 버퍼가 함께 사라지는 종류가 있어서,
-- 되돌릴 버퍼가 없을 때는 이 명령으로 새로 연다.
local REOPEN = {
  quickfix = 'botright copen',
  aerial = 'AerialOpen',
  tagbar = 'TagbarOpen',
  nerdtree = 'NERDTree',
}

local function remember(win)
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  -- is_plugin_buf(버퍼 기준)만 보면 모자란다. 부동 창과 미리보기 창
  -- (&previewwindow)은 버퍼가 평범한 파일이라 곁창인 줄 모른다 - 판정이
  -- 두 갈래로 갈리면 '지키는 목록'과 'EDIT 창 목록'이 어긋난다.
  if _G.vimide_is_edit_win(win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  guarded[win] = {
    buf = buf,
    kind = kind_of(buf),
    reopen = REOPEN[vim.bo[buf].filetype] or REOPEN[kind_of(buf)],
  }
end

-- 곁창에 실린 파일을 EDIT 창으로 옮기고 곁창을 되돌린다
local function rescue(win)
  local g = guarded[win]
  if not g then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  if buf == g.buf or is_plugin_buf(buf) then
    return -- 아직 제자리다
  end

  -- 되돌리기 전에 커서를 기억해 둔다. 사용자가 보려던 자리다.
  local pos = api.nvim_win_get_cursor(win)

  -- 곁창을 원래대로.
  --
  -- quickfix 버퍼는 창이 빼앗기는 순간 함께 사라진다(실측: 되돌릴 버퍼가
  -- 이미 무효). 그때는 되살릴 것이 없으니 그 창을 닫는다 - 같은 파일이
  -- 두 창에 뜬 채 남는 것보다 낫다.
  if g.buf and api.nvim_buf_is_valid(g.buf) then
    local ok = pcall(api.nvim_win_set_buf, win, g.buf)
    if not ok or api.nvim_win_get_buf(win) ~= g.buf then
      -- 되돌리지 못했다(winfixbuf 가 걸린 창에 :b!N 을 직접 친 경우 등).
      -- 여기서 포기하지 않으면 창을 옮길 때마다 rescue 가 다시 깨어나
      -- 매번 포커스를 빼앗는다. 한 번만 알리고 그 창은 놓아준다.
      guarded[win] = nil
      vim.notify('이 창은 원래대로 되돌리지 못했습니다 (g:vimide_win_guard)',
        vim.log.levels.WARN)
      return
    end
  else
    -- 버퍼가 창과 함께 사라지는 곁창이 있다(quickfix, aerial 처럼
    -- bufhidden=wipe). 되돌릴 것이 없으니 창을 닫고, 다시 세울 수 있는
    -- 종류면 아래에서 그 명령으로 새로 연다.
    guarded[win] = nil
    pcall(api.nvim_win_close, win, false)
  end

  -- 그 파일은 '직전에 보던 EDIT 창'에 연다.
  local target
  if type(_G.vimide_last_edit_win) == 'function' then
    local ok, w = pcall(_G.vimide_last_edit_win)
    if ok and w and w ~= 0 and _G.vimide_is_edit_win(w) then
      target = w
    end
  end
  target = target or _G.vimide_edit_wins()[1]
  if not target then
    -- EDIT 창이 하나도 없다: 하나 만든다. 여기서 포기하면 사용자가 연
    -- 파일이 아무 데도 안 뜬 채 사라진다.
    local ok = pcall(function()
      vim.cmd('noautocmd topleft vertical split')
      target = api.nvim_get_current_win()
    end)
    if not ok or not target then
      return
    end
    -- :split 은 지금 창의 창 옵션을 물려준다. 곁창에서 갈랐으면 winfixbuf
    -- 까지 따라와, 정작 그 창에 파일을 못 넣는다.
    for _, o in ipairs({ 'winfixbuf', 'winfixwidth', 'winfixheight',
      'previewwindow' }) do
      pcall(function() vim.wo[target][o] = false end)
    end
  end
  -- 세 번의 pcall 을 따로 두면 안 된다. 버퍼를 못 넣었는데 커서와 포커스만
  -- 옮기면, 사용자는 열려던 파일 대신 엉뚱한 창에 끌려가 있게 된다.
  if not pcall(api.nvim_win_set_buf, target, buf) then
    vim.notify('파일을 EDIT 창으로 옮기지 못했습니다 (g:vimide_win_guard)',
      vim.log.levels.WARN)
    return
  end
  pcall(api.nvim_win_set_cursor, target, pos)
  pcall(api.nvim_set_current_win, target)

  -- 닫아 버린 곁창은 다시 세워 준다. 보던 중이었을 테니까.
  if g.reopen and not api.nvim_win_is_valid(win) then
    pcall(vim.cmd, 'silent! ' .. g.reopen)
    pcall(api.nvim_set_current_win, target)
  end
end

-- 탭의 모든 창을 한 번 훑는다.
--
-- 지금 창만 보면 모자란다 - 포커스를 준 적 없는 곁창은 기록조차 안 되고,
-- 파일이 실려도 아무도 모른다.
local function sweep()
  if sweeping or busy() then
    return
  end
  sweeping = true
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if guarded[w] then
      pcall(rescue, w)
    end
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    pcall(remember, w)
  end
  sweeping = false
end

-- 지금 무엇을 지키고 있는지. 시험과 문제 추적용이다.
function _G.vimide_win_guard_state()
  local out = {}
  for w, g in pairs(guarded) do
    out[#out + 1] = string.format('%d=%s(%s)', w,
      (g.buf and api.nvim_buf_is_valid(g.buf)) and tostring(g.buf) or 'dead', g.kind)
  end
  table.sort(out)
  return table.concat(out, ' ')
end

api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'WinEnter', 'WinNew' }, {
  group = api.nvim_create_augroup('VimIdeWinGuard', { clear = true }),
  callback = function()
    if cfg('win_guard', 1) == 0 or busy() then
      return
    end
    -- 한 틱 미룬다. 곁창을 세우는 플러그인은 먼저 보통 버퍼를 :edit 로
    -- 띄우고 그 다음에 buftype 을 박는다(NERDTree 가 그렇다). 그 찰나에
    -- 판정하면 멀쩡한 곁창을 '파일이 실렸다'고 오해한다.
    vim.schedule(function()
      if cfg('win_guard', 1) == 0 then
        return
      end
      sweep()
    end)
  end,
  desc = '곁창에 실린 파일을 직전 EDIT 창으로 되돌린다',
})

api.nvim_create_autocmd('WinClosed', {
  group = 'VimIdeWinGuard',
  callback = function(a)
    guarded[tonumber(a.match) or -1] = nil
  end,
  desc = '닫힌 창의 기록을 지운다',
})

-- ---------------------------------------------------------------------------
-- 2. EDIT 창이 0개가 되면 끝낸다
-- ---------------------------------------------------------------------------
-- 지금은 편집 창을 전부 닫아도 nvim 이 안 죽는다. neo-tree 와 RelationView
-- 만 남은 채로 살아 있고, 그 상태에서는 파일을 열 자리도 없다.
--
-- 함정이 여럿이라 하나씩 막는다(전부 실측으로 확인한 것들이다):
--
--   * WinClosed 콜백 '안'에서 :qa 를 부르면 QuitPre/ExitPre/VimLeavePre/
--     VimLeave 가 통째로 건너뛰어진다. 세션이 저장되지 않고 gtags 자식과
--     autoindex 락이 고아로 남는데 종료 코드는 0 이라 겉보기엔 멀쩡하다.
--     그래서 반드시 한 틱 이상 미뤄서 부른다.
--   * 미룬 뒤에는 다시 센다. 그 사이에 relationview 의 트리 재생성이나
--     세션 복원이 창을 도로 열 수 있다.
--   * 세션 복원 중에는 정상적으로 'EDIT 0개'인 순간이 생긴다(세션 파일 첫
--     줄의 `silent only` 가 하필 편집 창부터 닫는다. 실측 3회).
--   * 미저장 버퍼가 숨어 있으면 :qa 가 E37 로 실패한다. 그때 그냥 두면
--     'EDIT 창도 없고 나갈 수도 없는' 상태가 된다 - 그 버퍼를 띄워 준다.
--
-- :qa / :wqa / :xa 와는 겹치지 않는다. 그 명령들은 창을 하나씩 닫지 않아
-- WinClosed 를 한 번도 쏘지 않는다(실측).

local pending = false

local function dirty_bufs()
  local out = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    -- acwrite 도 센다. fugitive 의 커밋 버퍼, 원격 편집(scp://), diffview 가
    -- 그것을 쓰는데 vim 은 이것도 '저장 안 함' 으로 치고 :qa 를 E37 로 막는다.
    -- 안 세면 pcall 이 그 오류를 삼켜, 나갈 수도 없고 보여 줄 창도 없는
    -- 상태로 남는다.
    local bt = vim.bo[b].buftype
    if api.nvim_buf_is_loaded(b) and vim.bo[b].modified
        and (bt == '' or bt == 'acwrite') then
      out[#out + 1] = b
    end
  end
  return out
end

api.nvim_create_autocmd('WinClosed', {
  group = api.nvim_create_augroup('VimIdeMinEdit', { clear = true }),
  callback = function(a)
    if cfg('min_edit_win', 1) == 0 or pending or busy() then
      return
    end
    -- WinClosed 는 창이 아직 목록에 있을 때 뜬다: 닫히는 창은 빼고 센다.
    -- 세는 것은 반드시 탭 전체다(지금 탭만 보면 남의 탭까지 끄게 된다).
    if _G.vimide_edit_win_count_all(tonumber(a.match)) > 0 then
      return
    end
    pending = true
    -- 120ms: vim.schedule 한 틱으로는 relationview 의 '트리 닫고 다시 열기'
    -- 와 같은 큐에 들어가 순서가 안 정해진다. 조금 더 미뤄 두고 다시 센다.
    vim.defer_fn(function()
      pending = false
      if cfg('min_edit_win', 1) == 0 or busy() then
        return
      end
      if _G.vimide_edit_win_count_all() > 0 then
        return -- 누가 도로 열어 주었다
      end
      -- 돌아가는 터미널이 있으면 끝내지 않는다. 사용자는 편집 창 하나를
      -- 닫았을 뿐인데 빌드나 ssh 가 말없이 죽으면 안 된다.
      if _G.vimide_has_live_terminal() then
        vim.notify('EDIT 창이 없지만 터미널 창이 있어 끝내지 않았습니다',
          vim.log.levels.WARN)
        return
      end
      local dirty = dirty_bufs()
      if #dirty > 0 then
        -- 저장 안 한 것이 있으면 끝내지 않는다. :qa 는 어차피 E37 로
        -- 막히고, 그 상태로 두면 보여 줄 창조차 없다.
        pcall(function()
          vim.cmd('noautocmd topleft split')
          api.nvim_win_set_buf(api.nvim_get_current_win(), dirty[1])
        end)
        vim.notify(
          ('EDIT 창이 없지만 저장하지 않은 버퍼가 %d개 있어 끝내지 않았습니다')
          :format(#dirty), vim.log.levels.WARN)
        return
      end
      -- 여기서의 :qa 는 WinClosed 밖이라 VimLeavePre 가 정상으로 돈다
      -- (세션 저장, gtags 자식 정리, autoindex 락 해제).
      pcall(vim.cmd, 'qa')
    end, 120)
  end,
  desc = 'EDIT 창이 0개가 되면 vim 을 끝낸다',
})
