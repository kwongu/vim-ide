-- dirdifflaunch.lua - DirDiff 선택: 비교할 두 곳(A | B)을 텔레스코프 같은 탭에서 고른다
--
-- 여는 길: \D (g:vimide_dirdiff_launch_key), 인자 없는 :DirDiff, :DirDiffPick [A] [B]. 열 때마다 새 탭
-- 'DirDiff 선택' 이 하나씩 생긴다 (여럿이 같이 있어도 된다 - 탭마다 제 A | B 다).
--
--   +- [A] 경로 · 선택: ... -----+- [B] 경로 · 선택: ... -----+
--   | > /src/a/                  | > /src/b/                  |   경로 칸 (한 줄, buftype=prompt)
--   +- [A] Space/Tab 고르기 ... -+- [B] Space/Tab 고르기 ... -+
--   | neo-tree (그 칸의 뿌리)    | neo-tree                   |   트리 (position='current')
--   +----------------------------+----------------------------+
--
--   경로 칸   치는 대로 따라간다: 있는 디렉터리를 치면 (g:vimide_dirdiff_launch_follow_ms 쉰 뒤) 그 칸의 트리
--             뿌리가 거기로. Enter 는 그 경로를 그 칸의 선택으로 - 디렉터리는 트리 뿌리도 거기로, 파일은 그
--             디렉터리를 뿌리로 하고 파일을 드러낸다. 없는 경로는 알리고 그대로. Tab / S-Tab 은 경로 완성
--             (명령줄처럼 - 하나면 채우고, 여럿이면 같은 앞부분까지, 더 없으면 목록). Esc 는 보통 모드.
--             알림은 그 칸의 창 머리에도 (입력 중에는 알림 줄이 '-- 입력 --' 에 덮인다). 경로는 디렉터리 쪽
--             링크를 푼 꼴로 다룬다 - neo-tree 의 뿌리가 그렇다 (real_of)
--   트리      Space / Tab 이 그 칸의 선택 ([A] 트리면 A, [B] 트리면 B). neo-tree 의 Space/Tab(.vimrc)이 부르는
--             _G.vimide_dirdiff_pick(dirdiffpick.lua)이 이 탭의 트리인지 먼저 묻는다 - F9·F11·RelationView
--             트리는 예전 그대로 [A] -> [B]. 고른 줄 끝에 [A] / [B] (다른 칸의 선택도 보이면 단다). 고른 줄에서
--             다시 누르면 취소. 파일에서 Enter(o, 두 번 누르기, s S t)도 고르기다 - 이 탭에서는 파일을 열지
--             않는다 (neo-tree 의 file_open_requested: relationview.lua 의 열기 훅이 먼저 묻고, 그 훅이
--             없을 때를 위해 여기서도 건다). 폴더의 Enter 는 neo-tree 그대로 펼치기/접기
--   두 칸 모두 고르고 종류가 같으면 곧바로 새 탭에 비교한다: 디렉터리 둘이면 DirDiff 탭(:DirDiff A B), 파일
--   둘이면 DirDiff 의 비교 탭 - neo-tree 의 Space 두 번과 같은 길(dirdiffpick.lua 의 _G.vimide_dirdiff_compare).
--   종류가 다르면 알리기만. 선택 탭은 남고 고른 것도 그대로 - gT / ,e 로 돌아와 한쪽을 바꾸면 또 하나가
--   열린다. 비교 탭을 q(:tabclose)로 닫으면 연 곳(이 탭, 누른 창)으로 돌아온다 (DirDiff 의 origin)
--   \x        A 와 B 를 바꾼다 (경로 칸·선택·트리 뿌리·커서 줄). 비교 창의 \x 와 같은 글자
--   q         선택 탭을 닫는다 (경로 칸의 보통 모드, 트리). 창 하나를 :q 로 닫아도 탭째 닫는다
--   Ctrl+h/l  A 칸 / B 칸으로, Ctrl+j/k 트리 / 경로 칸으로. 경로 칸의 입력 중에는 Ctrl+l·Ctrl+j 만 - Ctrl+h 는
--             지우기로 남긴다 (Tera Term 의 Backspace 가 ^H 다). 입력 중에도 Ctrl+w h 는 된다
--   ,r / ,e   gt / gT (DirDiff 탭처럼)
--
-- neo-tree 를 창 안에 그리는 길은 RelationView 열의 트리와 같다 (relationview.lua 의 ensure_tree): 창을 먼저
-- 만들고 get_state('filesystem', 탭, 창) 의 상태를 position='current' 로. 다른 것 둘:
--   * filesystem.navigate 대신 _navigate_internal - navigate 는 'filesystem_navigate' 라는 열쇠 하나로 모든
--     트리의 부름을 100ms 묶는다 (CALL_FIRST_AND_LAST). A·B 를 잇달아 부르면(처음, \x) 사이의 것이 버려지거나
--     나중에 돌아, 그때의 지금 창에 :lcd 를 했다
--   * 그 부름은 nvim_win_call 로 트리 창 안에서 - neo-tree 는 뿌리를 바꿀 때 '지금 창' 에 :lcd 한다
--     (bind_to_cwd, cwd_target.current = 'window'). 그 창의 :lcd 는 그대로 둔다: 없으면 :cd 할 때마다
--     neo-tree 의 dir_changed 가 이 트리들을 :cd 한 곳으로 옮긴다
-- 그 :lcd 는 :tabnew 가 물려준다 - 트리에서 연 비교 탭의 창들에서는 걷는다 (drop_lcd). nvim_win_call 안의 첫
-- :lcd 는 프로세스 디렉터리를 그 트리의 것으로 남겨 두어서 바로 되돌린다 (sync_cwd).
-- 끝낼 때(VimLeavePre) 선택 탭을 닫는다 - 세션에 빈 탭으로 남지 않게 (dirdiffview.lua 의 비교 탭처럼). 나가지 않는
-- 세션 저장(:VimIdeSessionSave)은 저장하는 동안 닫았다가 같은 자리에 그대로 되살린다 (_G.vimide_dirdiff_launch_stash).
-- 경로 칸은 winfixbuf, 네 창의 점프 목록은 비우고 시작한다 - Ctrl+O·Ctrl+^·:e 가 그 자리에 다른 버퍼를 열지 않게.
-- 곁창 지킴이(vimidewin.lua)는 이 탭을 남의 것으로 본다 (FOREIGN_FT 의 vimidedirdifflaunch).
--
-- 옵션 (.vimrc)
--   let g:vimide_dirdiff_launch_key = '<leader>D'   " 여는 키 ('' 이면 걸지 않는다 - :DirDiffPick 은 그대로)
--   let g:vimide_dirdiff_launch_follow_ms = 150     " 경로 칸을 트리가 따라가기까지 쉬는 ms (0 이면 Enter 때만)
--
-- nvim 전용이다. 진짜 vim 8.1 은 .vim/plugin/*.lua 를 읽지 않는다 (인자 없는 :DirDiff 는 예전대로 알림).

if vim.fn.has('nvim') ~= 1 or vim.g.loaded_vimide_dirdifflaunch then
  return
end
vim.g.loaded_vimide_dirdifflaunch = 1

local api = vim.api
local uv = vim.uv or vim.loop
local levels = vim.log.levels
local FT = 'vimidedirdifflaunch'
local PREFIX = '> '
local ns = api.nvim_create_namespace('vimide_dirdiff_launch')        -- 트리의 [A]/[B] (ephemeral)
local ns_pre = api.nvim_create_namespace('vimide_dirdiff_launch_pre') -- 경로 칸의 '> '
local group = api.nvim_create_augroup('VimIdeDiffLaunch', { clear = true })
local SIDES = { 'a', 'b' }

-- 탭 -> L = { tab, origin, a = 칸, b = 칸 }
-- 칸 = { prompt_win, prompt_buf, tree_win, state(neo-tree), pick = { path, kind = 'dir'|'file' },
--        last(경로 칸의 마지막 글 - 따라가기는 바뀐 것만), timer, gen(트리 부름 순번) }
local launchers = {}

local function say(msg, level)
  (_G.vimide_notify or vim.notify)('DirDiff 선택: ' .. msg, level or levels.INFO)
end

local function short(p)
  return vim.fn.strtrans(vim.fn.fnamemodify(p, ':~'))
end

local function valid(w)
  return w ~= nil and api.nvim_win_is_valid(w)
end

local function kind_name(k)
  return k == 'dir' and '디렉터리' or '파일'
end

-- 경로 칸에 보일 꼴: ~ 로 줄이고 디렉터리는 끝에 / (Tab 완성이 그 안을 보인다)
local function shown(p, kind)
  local s = vim.fn.fnamemodify(p, ':~')
  if kind == 'dir' and s:sub(-1) ~= '/' then
    s = s .. '/'
  end
  return s
end

-- ---------------------------------------------------------------------------
-- 색: 텔레스코프 것을 빌린다 (없으면 비슷한 기본 무리). 우리가 건 링크만 다시 건다 - 사용자가 :hi 로
-- 바꾼 것은 그대로. :colorscheme 은 모두 지우므로 그때 다시.
-- 이름이 VimIdeDirDiff 로 시작하면 안 된다: dirdiffview.lua 의 strip_inherited 가 winhighlight 에 그 글자가 있는
-- 창을 '비교 창의 색을 물려받은 창' 으로 보고 winhighlight·number 를 걷었다 (트리에 줄 번호가 생겼다)
-- ---------------------------------------------------------------------------
local HL = {
  VimIdeDiffLaunchTitle = { 'TelescopePromptTitle', 'Title' },
  VimIdeDiffLaunchPrefix = { 'TelescopePromptPrefix', 'Identifier' },
  VimIdeDiffLaunchBorder = { 'TelescopePromptBorder', 'TelescopeBorder', 'FloatBorder' },
  VimIdeDiffLaunchInfo = { 'TelescopePromptCounter', 'Comment' },
  VimIdeDiffLaunchHint = { 'TelescopeResultsComment', 'Comment' },
  VimIdeDiffLaunchA = { 'VimIdeDirDiffPickA', 'Search' },
  VimIdeDiffLaunchB = { 'IncSearch' },
}
local linked = {}

local function set_hl()
  for name, links in pairs(HL) do
    local to = links[#links]
    for _, l in ipairs(links) do
      if vim.fn.hlexists(l) == 1 then
        to = l
        break
      end
    end
    local ok, cur = pcall(api.nvim_get_hl, 0, { name = name, link = true })
    if not ok or vim.tbl_isempty(cur) or (cur.link and cur.link == linked[name]) then
      api.nvim_set_hl(0, name, { link = to })
      linked[name] = to
    end
  end
end

api.nvim_create_autocmd('ColorScheme', {
  group = group,
  callback = function()
    linked = {}
    set_hl()
  end,
})

-- ---------------------------------------------------------------------------
-- 어느 선택 탭의 어느 칸인가
-- ---------------------------------------------------------------------------

-- 창 -> L, 칸('a'|'b'), 역할('prompt'|'tree')
local function where(win)
  win = win or api.nvim_get_current_win()
  if not valid(win) then
    return nil
  end
  local side = vim.w[win].vimide_dirdiff_launch
  if side ~= 'a' and side ~= 'b' then
    return nil
  end
  local L = launchers[api.nvim_win_get_tabpage(win)]
  if not L or L.closing then
    return nil
  end
  return L, side, vim.w[win].vimide_dirdiff_launch_role
end

local function other(side)
  return side == 'a' and 'b' or 'a'
end

-- ---------------------------------------------------------------------------
-- 경로 칸
-- ---------------------------------------------------------------------------

local function prompt_text(b)
  if not (b and api.nvim_buf_is_valid(b)) then
    return ''
  end
  local ok, t = pcall(vim.fn.prompt_getinput, b)
  if ok and type(t) == 'string' then
    return t
  end
  local line = api.nvim_buf_get_lines(b, -2, -1, false)[1] or ''
  if line:sub(1, #PREFIX) == PREFIX then
    line = line:sub(#PREFIX + 1)
  end
  return line
end

-- 경로 칸의 글을 바꾼다. follow: 친 것처럼 트리가 따라가게 (Tab 완성). 아니면 따라가지 않는다 (고른 것을
-- 적을 때 - 트리에서 하위 디렉터리를 골랐는데 뿌리가 그리로 옮겨 가면 안 된다)
local function set_prompt(L, side, text, follow)
  local sd = L[side]
  local b = sd.prompt_buf
  if not (b and api.nvim_buf_is_valid(b)) then
    return
  end
  if not follow then
    sd.last = text
  end
  api.nvim_buf_set_lines(b, 0, -1, false, { PREFIX .. text })
  api.nvim_buf_clear_namespace(b, ns_pre, 0, -1)
  pcall(api.nvim_buf_set_extmark, b, ns_pre, 0, 0,
    { end_col = #PREFIX, hl_group = 'VimIdeDiffLaunchPrefix', right_gravity = false })
  vim.bo[b].modified = false
  if valid(sd.prompt_win) then
    pcall(api.nvim_win_set_cursor, sd.prompt_win, { 1, #PREFIX + #text })
  end
end

-- 디렉터리 쪽 링크를 푼 경로 (파일 자신이 링크면 그 이름은 그대로 - 그 링크를 골랐다). neo-tree 의 트리 뿌리는
-- 늘 이 꼴이다: 뿌리를 바꿀 때 :lcd 하고, getcwd() 는 푼 경로(macOS 의 /tmp -> /private/tmp)를 주어 dir_changed
-- 가 그리로 다시 옮긴다 - 친 경로 그대로 두면 [A]/[B] 표시가 트리의 줄을 못 찾았고 드러낸 파일도 놓쳤다
local function real_of(p)
  local st = p and uv.fs_stat(p)
  if not st then
    return p
  end
  if st.type == 'directory' then
    return uv.fs_realpath(p) or p
  end
  local d, name = p:match('^(.*)/([^/]+)$')
  local rd = d and uv.fs_realpath(d == '' and '/' or d)
  return rd and ((rd:gsub('/$', '')) .. '/' .. name) or p
end

-- 친 경로를 절대 경로로 (없으면 nil). 있는 경로는 글자 그대로 ('a$b' 의 $b 를 풀지 않게), 없으면 ~ · $VAR 를
-- 풀어 본다 (expand(, 1): 'wildignore' 를 쓰지 않는다 - .vimrc 의 '*/tmp/*' 가 Yocto 의 build/tmp 를 지웠다).
-- 상대 경로는 경로 칸 창의 지금 디렉터리에서 (:DirDiff 의 완성처럼)
local function resolve(text, win)
  text = vim.trim(text or '')
  if text == '' then
    return nil
  end
  local base = valid(win) and vim.fn.getcwd(win) or vim.fn.getcwd()
  local function abs(p)
    if p:sub(1, 1) ~= '/' then
      p = base .. '/' .. p
    end
    p = vim.fn.simplify(p)
    return (p:gsub('(.)/+$', '%1'))
  end
  local p = abs(text)
  if not uv.fs_stat(p) and (text:find('^~') or text:find('%$')) then
    local e = vim.fn.expand(text, 1)
    if e ~= '' then
      p = abs(e)
    end
  end
  return real_of(p)
end

local function kind_of(p)
  local st = p and uv.fs_stat(p)
  if not st then
    return nil
  end
  if st.type == 'directory' then
    return 'dir'
  end
  if st.type == 'file' then
    return 'file'
  end
  return nil
end

local function parent(p)
  local d = p:match('^(.*)/[^/]+$')
  return (d == nil or d == '') and '/' or d
end

-- ---------------------------------------------------------------------------
-- 창 머리 / 상태줄
-- ---------------------------------------------------------------------------

local function esc(s)
  return (s:gsub('%%', '%%%%'))
end

-- 창 폭에 맞춰 자른다 (tail: 앞을 잘라 끝을 남긴다 - 경로). 'statusline' 의 %< 는 가운데를 잘랐다
local function fit(s, w, tail)
  if w <= 0 then
    return ''
  end
  if vim.fn.strdisplaywidth(s) <= w then
    return s
  end
  local chars = vim.fn.split(s, '\\zs')
  local out, n = {}, 1
  local from, to, step = 1, #chars, 1
  if tail then
    from, to, step = #chars, 1, -1
  end
  for i = from, to, step do
    local cw = vim.fn.strdisplaywidth(chars[i])
    if n + cw > w then
      break
    end
    out[#out + 1] = chars[i]
    n = n + cw
  end
  if tail then
    return '<' .. table.concat(vim.fn.reverse(out))
  end
  return table.concat(out) .. '>'
end

local HINT_PROMPT = ' Enter 고르기 · Tab 완성 · Ctrl+j 트리 · Ctrl+l / Ctrl+w h 옆 칸 · \\x A↔B 교환 · Esc 뒤 q 닫기 '
local HINT_TREE = ' Space/Tab 고르기·취소 · Enter 펼치기·파일 고르기 · \\x A↔B 교환 · q 닫기 · Ctrl+h/l A↔B'
    .. ' · Ctrl+k 경로 칸 '

local function width(w)
  return valid(w) and api.nvim_win_get_width(w) or 0
end

local function update_bars(L)
  for _, side in ipairs(SIDES) do
    local sd, S = L[side], side:upper()
    local p = sd.pick
    local title = (' [%s] 경로'):format(S)
    if valid(sd.prompt_win) then
      local w = width(sd.prompt_win) - vim.fn.strdisplaywidth(title)
      local info = p and (' 선택: ' .. fit(vim.fn.strtrans(shown(p.path, p.kind)), w - 8, true) .. ' ')
          or fit(' 선택 없음 - 트리에서 Space/Tab, 경로 칸에서 Enter ', w)
      local hl = 'VimIdeDiffLaunchInfo'
      if sd.note then
        -- 입력 중에는 알림 줄이 '-- 입력 --' 에 덮인다 - 창 머리에 (다음 입력·고르기까지)
        info, hl = fit(' ' .. sd.note[1] .. ' ', w), sd.note[2]
      end
      vim.wo[sd.prompt_win].winbar = '%#VimIdeDiffLaunchTitle#' .. title .. '%*%#' .. hl .. '#'
          .. esc(info) .. '%*'
      vim.wo[sd.prompt_win].statusline = '%#VimIdeDiffLaunchHint#' .. esc(fit(HINT_PROMPT, width(sd.prompt_win)))
          .. '%*'
    end
    if valid(sd.tree_win) then
      local tt = (' [%s]'):format(S)
      local root = sd.state and sd.state.path
      vim.wo[sd.tree_win].winbar = '%#VimIdeDiffLaunchTitle#' .. tt .. '%*%#VimIdeDiffLaunchHint#'
          .. esc(fit(HINT_TREE, width(sd.tree_win) - #tt)) .. '%*'
      if root then
        vim.wo[sd.tree_win].statusline = '%#VimIdeDiffLaunchInfo#'
            .. esc(fit((' [%s] 트리: %s '):format(S, vim.fn.strtrans(shown(root, 'dir'))), width(sd.tree_win), true))
            .. '%*'
      end
    end
  end
end

-- 알린다 - 그 칸의 창 머리에도 (경로 칸의 입력 중에는 알림 줄이 보이지 않는다)
local function note(L, side, msg, level)
  local sd = L[side]
  sd.note = { vim.fn.strtrans(msg), level == levels.WARN and 'WarningMsg' or 'VimIdeDiffLaunchInfo' }
  -- 지금 글은 본 것으로: 빨리 치고 곧바로 Enter / Tab 이면 TextChangedI 가 그 키 뒤에 와서 (입력이 밀려 있는
  -- 동안은 오지 않는다) on_text 가 방금 단 알림을 지웠다
  sd.last = prompt_text(sd.prompt_buf)
  update_bars(L)
  say(msg, level)
end

-- ---------------------------------------------------------------------------
-- 트리의 [A] / [B] 표시 - dirdiffpick.lua 의 [A] 와 같은 방식 (그릴 때마다 노드의 줄을 찾아 ephemeral 로.
-- neo-tree 는 접기·펼치기·git 표시 때 줄을 통째로 갈아 끼운다). 자리도 같다: 이름 뒤가 빈칸이면 겹쳐 쓰고,
-- 줄 끝 뒤에 자리가 있으면 줄 끝에, 아니면 창 오른쪽 끝에
-- ---------------------------------------------------------------------------

local function place(win, line, name, width_text)
  local need = width_text + 2
  local _, e = line:find(name or '\0', 1, true)
  if e and line:sub(e + 1, e + need) == string.rep(' ', need) then
    return e, { virt_text_pos = 'overlay' }, ' '
  end
  local info = vim.fn.getwininfo(win)[1] or {}
  local width = api.nvim_win_get_width(win) - (info.textoff or 0)
  if vim.fn.strdisplaywidth(line) + width_text <= width then
    return 0, { virt_text_pos = 'eol' }, ''
  end
  return 0, { virt_text_pos = 'overlay', virt_text_win_col = math.max(0, width - width_text - 1) }, ' '
end

api.nvim_set_decoration_provider(ns, {
  on_win = function(_, win, buf, top, bot)
    if next(launchers) == nil or vim.w[win].vimide_dirdiff_launch_role ~= 'tree' then
      return false
    end
    pcall(function()
      local L, side = where(win)
      local st = L and L[side].state
      if not (st and st.tree and st.bufnr == buf) then
        return
      end
      local rows = {}
      for _, s2 in ipairs(SIDES) do
        local p = L[s2].pick
        if p then
          local okn, node, lnum = pcall(st.tree.get_node, st.tree, p.path)
          if okn and node and lnum and lnum - 1 >= top and lnum - 1 <= bot then
            local r = rows[lnum] or { node = node, chunks = {} }
            rows[lnum] = r
            r.chunks[#r.chunks + 1] = { '[' .. s2:upper() .. ']', s2 == 'a' and 'VimIdeDiffLaunchA' or 'VimIdeDiffLaunchB' }
          end
        end
      end
      for lnum, r in pairs(rows) do
        local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
        local col, opts, lead = place(win, line, r.node.name, 3 * #r.chunks)
        r.chunks[1][1] = lead .. r.chunks[1][1]
        opts.virt_text = r.chunks
        opts.hl_mode = 'combine'
        opts.ephemeral = true
        api.nvim_buf_set_extmark(buf, ns, lnum - 1, col, opts)
      end
    end)
    return false
  end,
})

local function redraw_trees(L)
  for _, side in ipairs(SIDES) do
    local w = L[side].tree_win
    if valid(w) and not pcall(api.nvim__redraw, { win = w, valid = false }) then
      vim.cmd('redraw!')
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- 트리 (neo-tree, position='current')
-- ---------------------------------------------------------------------------

-- 이 탭의 트리에서 파일을 '열면' 그 칸의 선택으로 (relationview.lua 의 열기 훅과 아래 hook_open 이 부른다).
-- 다룬 것이면 true
local launch_open

-- neo-tree 가 제 길로 뿌리를 바꾸면 (<BS>, '.' 뿌리로 ...) 그 칸의 상태줄('[A] 트리: ...')도 따라간다. 고른 것이
-- 없고 경로 칸이 예전 뿌리를 보이고 있었으면 경로 칸도 새 뿌리로 (친 경로는 그대로 둔다)
local function rooted(st)
  local L, side, role = where(st.winid)
  if not L or role ~= 'tree' then
    return
  end
  local sd = L[side]
  local root = st.path
  if not root or root == sd.seen_root then
    return
  end
  local old = sd.seen_root
  sd.seen_root = root
  if old and not sd.pick and resolve(prompt_text(sd.prompt_buf), sd.prompt_win) == old then
    set_prompt(L, side, shown(root, 'dir'))
  end
  update_bars(L)
end

local hooked = false
local function hook_open()
  if hooked then
    return
  end
  local ok, ev = pcall(require, 'neo-tree.events')
  if not ok then
    return
  end
  hooked = true
  pcall(ev.subscribe, {
    event = ev.FILE_OPEN_REQUESTED or 'file_open_requested',
    id = 'vimide_dirdiff_launch_open',
    handler = function(args)
      if launch_open(args) then
        return { handled = true }
      end
    end,
  })
  pcall(ev.subscribe, {
    event = ev.AFTER_RENDER or 'after_render',
    id = 'vimide_dirdiff_launch_render',
    handler = function(st)
      if next(launchers) ~= nil and type(st) == 'table' and st.winid then
        pcall(rooted, st)
      end
    end,
  })
end

local map_tree -- 아래 (키)

local function tree_ready(L, side, gen)
  local sd = L[side]
  if L.closing or gen ~= sd.gen then
    return
  end
  local st, win = sd.state, sd.tree_win
  if not (st and valid(win)) then
    return
  end
  local b = st.bufnr
  if b and api.nvim_buf_is_valid(b) and api.nvim_win_get_buf(win) == b then
    if vim.b[b].vimide_dirdiff_launch_maps ~= 1 then
      map_tree(b)
      vim.b[b].vimide_dirdiff_launch_maps = 1
      -- 상태줄은 그 칸의 뿌리 (airline 의 것은 이 탭에서 '입력' 을 엉뚱한 트리에 보였다)
      vim.b[b].airline_disable_statusline = 1
    end
    -- neo-tree 의 winhighlight(창마다 한 번 건다)에 칸 사이 줄의 색만 덧붙인다
    local whl = vim.wo[win].winhighlight
    if not whl:find('VimIdeDiffLaunchBorder', 1, true) then
      whl = whl:gsub(',?WinSeparator:[^,]*', '')
      vim.wo[win].winhighlight = (whl ~= '' and (whl .. ',') or '') .. 'WinSeparator:VimIdeDiffLaunchBorder'
    end
  end
  update_bars(L)
  redraw_trees(L)
end

-- nvim_win_call 안에서 :lcd 하면 (그 창의 첫 :lcd 일 때 - 전의 것이 없으면 nvim 은 들어가며 디렉터리를 적어 두지
-- 않는다) 프로세스의 디렉터리가 그 창의 것으로 남는다: 지금 창은 :lcd 가 없는데 getcwd() 가 트리의 뿌리를 주어, 다음
-- 선택 탭이 그 디렉터리에서 열렸고 상대 경로·:e 가 엉뚱한 데서 풀렸다. 창을 옮길 때 nvim 이 하듯 지금 창의 것으로
local function sync_cwd()
  local want = vim.fn.getcwd(0, 0)
  if vim.fn.getcwd() ~= want then
    pcall(vim.cmd, 'noautocmd call chdir(' .. vim.fn.string(want) .. ')')
  end
end

-- side 칸의 트리 뿌리를 dir 로 (reveal: 드러낼 경로)
local function tree_go(L, side, dir, reveal)
  local sd = L[side]
  sd.first = nil   -- 처음 자리(open_tab 의 first_trees)는 이제 갈 일이 없다 - 이것이 그 뒤의 자리다
  local win = sd.tree_win
  if not valid(win) then
    return
  end
  local okm, mgr = pcall(require, 'neo-tree.sources.manager')
  local okf, fs = pcall(require, 'neo-tree.sources.filesystem')
  if not (okm and okf and fs._navigate_internal) then
    return say('neo-tree 가 없습니다 (:PlugInstall)', levels.WARN)
  end
  pcall(function()
    require('neo-tree').ensure_config()
  end)
  hook_open()
  local st = mgr.get_state('filesystem', L.tab, win)
  st.current_position = 'current'
  sd.state = st
  sd.gen = (sd.gen or 0) + 1
  local gen = sd.gen
  st._ready = false
  local ok, err = pcall(api.nvim_win_call, win, function()
    fs._navigate_internal(st, dir, reveal, function()
      vim.schedule(function()
        tree_ready(L, side, gen)
      end)
    end, false)
  end)
  sync_cwd()
  if not ok then
    say('트리를 못 열었습니다 - ' .. tostring(err), levels.WARN)
  end
end

-- 아직 그리지 않은 트리(open_tab 뒤 first_trees 가 그린다)는 갈 뿌리
local function tree_root(sd)
  return (sd.state and sd.state.path) or (sd.first and sd.first.root)
end

-- 트리 창의 커서 줄의 경로 (\x 뒤에 그 줄로). 아직 그리지 않은 트리는 드러낼 경로
local function cursor_path(sd)
  local st, win = sd.state, sd.tree_win
  if not (st and st.tree and valid(win)) then
    return sd.first and sd.first.reveal or nil
  end
  local ok, node = pcall(st.tree.get_node, st.tree, api.nvim_win_get_cursor(win)[1])
  return ok and node and node.path or nil
end

-- ---------------------------------------------------------------------------
-- 고르기와 비교
-- ---------------------------------------------------------------------------

-- 트리에서 연 비교 탭의 창들이 물려받은 그 트리의 :lcd 를 걷는다 (:cd 는 창의 :lcd 를 지운다 - 전역 디렉터리는
-- 같은 곳으로 다시 정할 뿐). 트리를 닫을 때 그 디렉터리에 남지 않게
local function drop_lcd(dir)
  local g = vim.fn.getcwd(-1, -1)
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.fn.haslocaldir(w) == 1 and vim.fn.getcwd(w) == dir then
      pcall(api.nvim_win_call, w, function()
        vim.cmd('noautocmd cd ' .. vim.fn.fnameescape(g))
      end)
    end
  end
  sync_cwd()
end

local function open_compare(L, a, b, kind)
  if not _G.vimide_dirdiff_compare then
    return say('dirdiffpick.lua 가 없습니다', levels.WARN)
  end
  if api.nvim_get_current_tabpage() ~= L.tab and api.nvim_tabpage_is_valid(L.tab) then
    api.nvim_set_current_tabpage(L.tab)
  end
  local from = api.nvim_get_current_win()
  local lcd = vim.fn.haslocaldir(from) == 1 and vim.fn.getcwd(from) or nil
  _G.vimide_dirdiff_compare(a, b, kind)
  if lcd and api.nvim_get_current_tabpage() ~= L.tab then
    drop_lcd(lcd)
  end
end

-- 두 칸이 다 골랐으면 비교를 연다. later: 입력 중(경로 칸의 Enter)이면 보통 모드로 돌아온 뒤에 연다 - 입력
-- 모드인 채로 새 탭을 열면 그 탭의 창이 입력 모드를 이어받는다
local function maybe_compare(L, side, later)
  local a, b = L.a.pick, L.b.pick
  if not (a and b) then
    local p = L[side].pick
    if p then
      say(('[%s] %s: %s - [%s] 를 고르면 곧바로 비교합니다'):format(side:upper(), kind_name(p.kind),
        short(p.path), other(side):upper()))
    end
    return
  end
  if a.kind ~= b.kind then
    return note(L, side, ('[A] 는 %s, [B] 는 %s입니다 - 같은 종류끼리 비교합니다'):format(kind_name(a.kind),
      kind_name(b.kind)), levels.WARN)
  end
  local ra, rb = uv.fs_realpath(a.path) or a.path, uv.fs_realpath(b.path) or b.path
  if ra == rb then
    return note(L, side, '[A] 와 [B] 가 같은 곳입니다: ' .. short(a.path), levels.WARN)
  end
  if later then
    vim.cmd('stopinsert')
    vim.schedule(function()
      if not L.closing then
        open_compare(L, a.path, b.path, a.kind)
      end
    end)
  else
    open_compare(L, a.path, b.path, a.kind)
  end
end

-- side 칸의 선택을 path 로 (nil 이면 취소). 경로 칸에 적고 표시를 다시 그린다
local function set_pick(L, side, path, kind)
  local sd = L[side]
  sd.pick = path and { path = path, kind = kind } or nil
  -- 알림은 두 칸 다 걷는다 - 한 칸의 '종류가 다르다' 는 다른 칸을 고쳐 고르면 풀린다 (남으면 그 칸의 선택을 가렸다)
  L.a.note, L.b.note = nil, nil
  if path then
    set_prompt(L, side, shown(path, kind))
  else
    local r = tree_root(sd)
    if r then
      set_prompt(L, side, shown(r, 'dir'))
    end
  end
  update_bars(L)
  redraw_trees(L)
end

-- neo-tree 의 Space / Tab (.vimrc -> dirdiffpick.lua 의 _G.vimide_dirdiff_pick). 이 탭의 트리면 true
function _G.vimide_dirdiff_launch_pick(state)
  local win = state and state.winid
  if not win then
    return false
  end
  local L, side, role = where(win)
  if not L or role ~= 'tree' then
    return false
  end
  local ok, node = pcall(function()
    return state.tree:get_node()
  end)
  local path = ok and node and node.path
  local t = ok and node and node.type
  if not path or (t ~= 'directory' and t ~= 'file') then
    say('디렉터리나 파일 줄에서 누르세요', levels.WARN)
    return true
  end
  local kind = t == 'directory' and 'dir' or 'file'
  local cur = L[side].pick
  if cur and cur.path == path then
    set_pick(L, side, nil)
    say(('[%s] 고른 것을 취소했습니다'):format(side:upper()))
    return true
  end
  if not kind_of(path) then
    say('디스크에 없는 ' .. kind_name(kind) .. '입니다: ' .. short(path), levels.WARN)
    return true
  end
  set_pick(L, side, path, kind)
  maybe_compare(L, side)
  return true
end

launch_open = function(args)
  local st = args and args.state
  if not (st and st.winid) then
    return false
  end
  local L, side, role = where(st.winid)
  if not L or role ~= 'tree' or not args.path then
    return false
  end
  local path = args.path
  if kind_of(path) ~= 'file' then
    say('디스크에 없는 파일입니다: ' .. short(path), levels.WARN)
    return true
  end
  set_pick(L, side, path, 'file')
  -- neo-tree 의 열기 명령 안이다 - 새 탭은 그 뒤에
  vim.schedule(function()
    if not L.closing and L[side].pick and L[side].pick.path == path then
      maybe_compare(L, side)
    end
  end)
  return true
end
_G.vimide_dirdiff_launch_open = launch_open

-- 경로 칸의 Enter: 친 경로를 그 칸의 선택으로
local function enter(L, side)
  local sd = L[side]
  local text = prompt_text(sd.prompt_buf)
  local p = resolve(text, sd.prompt_win)
  if not p then
    return note(L, side, '경로를 넣으세요 (Tab 으로 완성)', levels.WARN)
  end
  local kind = kind_of(p)
  if not kind then
    return note(L, side, '없는 경로입니다: ' .. text, levels.WARN)
  end
  if kind == 'dir' then
    if tree_root(sd) ~= p then
      tree_go(L, side, p)
    end
  else
    tree_go(L, side, parent(p), p)
  end
  set_pick(L, side, p, kind)
  maybe_compare(L, side, api.nvim_get_mode().mode:sub(1, 1) == 'i')
end

-- 치는 대로 따라가기: 있는 디렉터리면 트리 뿌리를 거기로 (고른 것은 그대로)
local function follow(L, side, text)
  local sd = L[side]
  if L.closing or text ~= prompt_text(sd.prompt_buf) then
    return
  end
  local p = resolve(text, sd.prompt_win)
  if p and kind_of(p) == 'dir' and tree_root(sd) ~= p then
    tree_go(L, side, p)
  end
end

local function on_text(L, side)
  local sd = L[side]
  local text = prompt_text(sd.prompt_buf)
  -- 줄바꿈이 붙은 붙여넣기는 경로 칸을 여러 줄로 만든다 (한 줄 창이라 빈 끝 줄만 보였다) - 처음의 빈 줄 아닌
  -- 줄 하나로 모은다. 모은 글이 다시 이리로 온다
  if text:find('\n', 1, true) then
    local one = ''
    for l in vim.gsplit(text, '\n', { plain = true }) do
      if vim.trim(l) ~= '' then
        one = vim.trim(l)
        break
      end
    end
    vim.schedule(function()
      if not L.closing then
        set_prompt(L, side, one, true)
      end
    end)
    return
  end
  if text == sd.last then
    return
  end
  sd.last = text
  if sd.note then
    sd.note = nil
    update_bars(L)
  end
  local ms = tonumber(vim.g.vimide_dirdiff_launch_follow_ms) or 150
  if ms <= 0 then
    return
  end
  sd.timer = sd.timer or uv.new_timer()
  sd.timer:stop()
  sd.timer:start(ms, 0, vim.schedule_wrap(function()
    follow(L, side, text)
  end))
end

-- 같은 앞부분 (UTF-8 글자 가운데서 자르지 않는다)
local function common(list)
  local first = list[1]
  local n = #first
  for i = 2, #list do
    local s = list[i]
    local k = 0
    while k < n and k < #s and first:byte(k + 1) == s:byte(k + 1) do
      k = k + 1
    end
    n = k
  end
  while n > 0 and (first:byte(n + 1) or 0) >= 0x80 and (first:byte(n + 1) or 0) < 0xC0 do
    n = n - 1
  end
  return first:sub(1, n)
end

-- 경로 칸의 Tab: 명령줄의 파일 완성처럼
local function complete(L, side)
  local sd = L[side]
  local text = prompt_text(sd.prompt_buf)
  local wi = vim.o.wildignore
  vim.o.wildignore = ''
  local ok, items = pcall(vim.fn.getcompletion, text, 'file')
  vim.o.wildignore = wi
  if not ok or #items == 0 then
    return note(L, side, '맞는 이름이 없습니다: ' .. text, levels.WARN)
  end
  if #items == 1 then
    return set_prompt(L, side, items[1], true)
  end
  local c = common(items)
  if #c > #text then
    return set_prompt(L, side, c, true)
  end
  if api.nvim_get_mode().mode:sub(1, 1) ~= 'i' then
    return note(L, side, ('%d개가 맞습니다 - 더 치세요'):format(#items))
  end
  local menu = {}
  for _, it in ipairs(items) do
    menu[#menu + 1] = { word = it, abbr = it:match('([^/]+/?)$') or it }
  end
  vim.fn.complete(#PREFIX + 1, menu)
end

-- ---------------------------------------------------------------------------
-- 바꾸기 / 옮기기 / 닫기
-- ---------------------------------------------------------------------------

local function swap(L)
  local a, b = L.a, L.b
  local ta, tb = prompt_text(a.prompt_buf), prompt_text(b.prompt_buf)
  local ra, rb = tree_root(a), tree_root(b)
  local ca, cb = cursor_path(a), cursor_path(b)
  a.pick, b.pick = b.pick, a.pick
  a.note, b.note = nil, nil
  set_prompt(L, 'a', tb)
  set_prompt(L, 'b', ta)
  if rb then
    tree_go(L, 'a', rb, cb)
  end
  if ra then
    tree_go(L, 'b', ra, ca)
  end
  update_bars(L)
  redraw_trees(L)
  say('[A] 와 [B] 를 바꿨습니다')
end

-- Ctrl+h/l: 같은 줄(경로 칸 / 트리)의 A / B 칸, Ctrl+j/k: 같은 칸의 트리 / 경로 칸
local function move(L, side, role, key)
  if key == 'h' then
    side = 'a'
  elseif key == 'l' then
    side = 'b'
  elseif key == 'j' then
    role = 'tree'
  else
    role = 'prompt'
  end
  local w = L[side][role .. '_win']
  if not valid(w) or w == api.nvim_get_current_win() then
    return
  end
  local ins = api.nvim_get_mode().mode:sub(1, 1) == 'i'
  api.nvim_set_current_win(w)
  -- 입력 중에 다른 경로 칸으로 가면 거기서도 입력 (텔레스코프처럼). 이 키(<Cmd>)가 끝나야 한다: 아직 입력
  -- 모드라 :startinsert 는 듣지 않고, nvim 은 입력 중에 prompt 창을 떠나면 입력을 멈춘다 (그 칸이 입력 중에
  -- 떠난 칸이었으면 nvim 이 입력으로 되돌려 놓는다 - 그때는 그대로)
  if ins and role == 'prompt' then
    vim.schedule(function()
      if api.nvim_get_current_win() == w and api.nvim_get_mode().mode:sub(1, 1) ~= 'i' then
        vim.cmd('startinsert!')
      end
    end)
  end
end

local function plain(win)
  for _, o in ipairs({ 'winhighlight', 'winfixwidth', 'winfixheight', 'winfixbuf', 'number', 'relativenumber',
    'signcolumn', 'foldcolumn', 'cursorline', 'list', 'wrap', 'spell', 'statuscolumn', 'winbar',
    'statusline', 'colorcolumn', 'scrolloff', 'sidescrolloff' }) do
    pcall(api.nvim_win_call, win, function()
      vim.cmd('setlocal ' .. o .. '<')
    end)
  end
end

-- neo-tree 는 'current' 트리의 창이 닫힐 때(WinClosed) 그 창에 # 버퍼나 새 [No Name](나열된)을 넣어 트리를 숨긴다 -
-- 창은 곧 없어지니 그 버퍼만 남는다 (relationview.lua 의 close_tree 와 같은 청소). 우리 WinClosed 가 neo-tree 의
-- 것보다 먼저 돌 수도(neo-tree 는 setup 때 건다 - 보통 이쪽이 먼저), 나중에 돌 수도 있다: 먼저면 그때의 버퍼 목록을
-- 적어 두었다가 새로 생긴 빈 버퍼를, 나중이면 닫히는 창에 들어 있는 버퍼(orphans)를 지운다
local orphans = {}

local function blank(b)
  return api.nvim_buf_is_valid(b) and api.nvim_buf_get_name(b) == '' and vim.bo[b].buftype == ''
      and not vim.bo[b].modified and #vim.fn.win_findbuf(b) == 0
      and api.nvim_buf_line_count(b) <= 1 and (api.nvim_buf_get_lines(b, 0, 1, false)[1] or '') == ''
end

local function sweep(before)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if (orphans[b] or (before and not before[b])) and blank(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
  orphans = {}
end

local function close(L)
  if L.closing then
    return
  end
  L.closing = true
  launchers[L.tab] = nil
  for _, side in ipairs(SIDES) do
    local t = L[side].timer
    if t then
      pcall(t.stop, t)
      pcall(t.close, t)
      L[side].timer = nil
    end
  end
  local before = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    before[b] = true
  end
  local tab = L.tab
  if api.nvim_tabpage_is_valid(tab) then
    if #api.nvim_list_tabpages() > 1 then
      pcall(vim.cmd, 'tabclose ' .. api.nvim_tabpage_get_number(tab))
    else
      -- 마지막 탭: 빈 편집 창 하나로 (DirDiff 의 끝내기처럼)
      api.nvim_set_current_tabpage(tab)
      local w = valid(L.a.prompt_win) and L.a.prompt_win or api.nvim_get_current_win()
      api.nvim_set_current_win(w)
      pcall(vim.cmd, 'stopinsert')
      pcall(vim.cmd, 'silent! only')
      -- 경로 칸은 winfixbuf 다 (아래 열기) - 풀어야 enew 가 된다
      pcall(api.nvim_set_option_value, 'winfixbuf', false, { scope = 'local', win = 0 })
      pcall(vim.cmd, 'enew')
      plain(api.nvim_get_current_win())
      pcall(api.nvim_win_del_var, api.nvim_get_current_win(), 'vimide_dirdiff_launch')
      pcall(api.nvim_win_del_var, api.nvim_get_current_win(), 'vimide_dirdiff_launch_role')
      pcall(api.nvim_tabpage_del_var, tab, 'title')
      pcall(api.nvim_tabpage_del_var, tab, 'vimide_dirdiff_launch')
    end
  end
  if L.origin and api.nvim_tabpage_is_valid(L.origin) and api.nvim_get_current_tabpage() ~= L.origin then
    api.nvim_set_current_tabpage(L.origin)
  end
  sweep(before)
  vim.schedule(function()
    sweep(before)
  end)
end

-- 키에서: 지금 창의 선택 탭과 칸으로
local ACT = {
  enter = enter,
  complete = complete,
  swap = function(L) swap(L) end,
  close = function(L) close(L) end,
}
function _G.vimide_dirdiff_launch_do(name, key)
  local L, side, role = where()
  if not L then
    return
  end
  if name == 'move' then
    return move(L, side, role, key)
  end
  if name == 'tab' then
    -- ,r / ,e : gt / gT (횟수도)
    local n = vim.v.count
    pcall(vim.cmd, (n > 0 and tostring(n) or '') .. (key == 'next' and 'tabnext' or 'tabprevious'))
    return
  end
  local f = ACT[name]
  if f then
    f(L, side)
  end
end

local function cmd(name, key)
  return ('<Cmd>lua _G.vimide_dirdiff_launch_do(%q%s)<CR>'):format(name, key and (', %q'):format(key) or '')
end

-- 경로 칸과 트리에 같이 거는 키
local function map_common(b)
  local function m(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = b, nowait = true, silent = true, desc = 'DirDiff 선택: ' .. desc })
  end
  m('n', 'q', cmd('close'), '선택 탭 닫기')
  m('n', '<leader>x', cmd('swap'), 'A 와 B 바꾸기 (경로·선택·트리)')
  m('n', '<C-h>', cmd('move', 'h'), 'A 칸으로')
  m('n', '<C-l>', cmd('move', 'l'), 'B 칸으로')
  m('n', '<C-j>', cmd('move', 'j'), '트리로')
  m('n', '<C-k>', cmd('move', 'k'), '경로 칸으로')
  m('n', ',r', cmd('tab', 'next'), '다음 탭 (gt)')
  m('n', ',e', cmd('tab', 'prev'), '앞 탭 (gT)')
end

map_tree = function(b)
  map_common(b)
end

local function map_prompt(b)
  map_common(b)
  local function m(mode, lhs, rhs, desc, expr)
    vim.keymap.set(mode, lhs, rhs, { buffer = b, nowait = true, silent = true, expr = expr,
      desc = 'DirDiff 선택: ' .. desc })
  end
  m('i', '<CR>', function()
    return vim.fn.pumvisible() == 1 and '<C-y>' or cmd('enter')
  end, '경로 적용 - 이 칸의 선택으로 (디렉터리·파일)', true)
  m('n', '<CR>', cmd('enter'), '경로 적용 - 이 칸의 선택으로 (디렉터리·파일)')
  m('i', '<Tab>', function()
    return vim.fn.pumvisible() == 1 and '<C-n>' or cmd('complete')
  end, '경로 완성 (여럿이면 목록, 목록에서는 다음)', true)
  m('i', '<S-Tab>', function()
    return vim.fn.pumvisible() == 1 and '<C-p>' or ''
  end, '경로 완성 목록에서 앞', true)
  m('i', '<C-l>', cmd('move', 'l'), 'B 칸으로 (입력 중)')
  m('i', '<C-j>', cmd('move', 'j'), '트리로 (입력 중)')
  -- 경로 칸의 글이 바뀌면 (치기, 완성 목록에서 고르기, 보통 모드의 고치기)
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    group = group,
    buffer = b,
    callback = function()
      local L, side = where()
      if L and L[side].prompt_buf == b then
        on_text(L, side)
      end
    end,
  })
end

-- ---------------------------------------------------------------------------
-- 열기
-- ---------------------------------------------------------------------------

-- 비교 창에서 열면 :tabnew 가 diff·묶기·접기도 물려준다 - 모두 끈다
local WO = { number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0', list = false,
  wrap = false, spell = false, colorcolumn = '', statuscolumn = '', cursorline = false, scrolloff = 0,
  sidescrolloff = 0, diff = false, scrollbind = false, cursorbind = false, foldenable = false,
  winfixbuf = false }

local function set_wo(win, opts)
  for k, v in pairs(opts) do
    pcall(api.nvim_set_option_value, k, v, { scope = 'local', win = win })
  end
end

local function new_prompt(side)
  local b = api.nvim_create_buf(false, true)
  -- delimitMate 가 ( [ { " ' 짝 매핑을 걸지 않게 (askform.lua 처럼, 창에 띄우기 전에)
  vim.b[b].loaded_delimitMate = 1
  -- airline 이 상태줄을 제 것으로 바꾸지 않게 (아래 상태줄의 키 안내)
  vim.b[b].airline_disable_statusline = 1
  vim.bo[b].buftype = 'prompt'
  vim.bo[b].bufhidden = 'wipe'
  vim.bo[b].swapfile = false
  vim.fn.prompt_setprompt(b, PREFIX)
  -- 한 낱말 이름 (dirdiffview.lua 의 tr.bufname 과 같은 꼴 - 빈칸·# 가 든 이름은 neo-tree 의 ':bdelete <이름>' 에서
  -- 여러 인자로 갈렸다. QA-03)
  pcall(api.nvim_buf_set_name, b, ('DirDiff:launch-%s:%d'):format(side, b))
  vim.bo[b].filetype = FT
  vim.b[b].vimide_dirdiff_launch = side
  map_prompt(b)
  return b
end

local function mark_win(win, side, role)
  vim.w[win].vimide_dirdiff_launch = side
  vim.w[win].vimide_dirdiff_launch_role = role
end

-- 두 칸을 같은 폭으로, 경로 칸은 한 줄로
local function relayout(L)
  local pa, pb = L.a.prompt_win, L.b.prompt_win
  if not (valid(pa) and valid(pb)) then
    return
  end
  for _, w in ipairs({ pa, pb }) do
    pcall(api.nvim_win_set_height, w, 1)
  end
  pcall(api.nvim_win_set_width, pa, math.floor((vim.o.columns - 1) / 2))
  update_bars(L)
end

-- 처음 자리: A 는 지금 파일의 디렉터리(없으면 지금 디렉터리), B 는 지금 디렉터리. 인자로 주면 그것 - 파일이면
-- 그 디렉터리를 뿌리로 하고 그 파일을 드러낸다 (고르지는 않는다 - Enter 로 고른다)
local function start_at(arg, fallback, win)
  if arg and arg ~= '' then
    local p = resolve(arg, win)
    local k = kind_of(p)
    if k == 'dir' then
      return p, nil, p
    elseif k == 'file' then
      return parent(p), p, p
    end
    say('없는 경로라 지금 디렉터리에서 엽니다: ' .. vim.fn.strtrans(arg), levels.WARN)
  end
  return fallback, nil, fallback
end

-- 처음 트리 그리기 (QA-24). open_tab 은 경로 칸과 빈 트리('읽는 중…')만 세우고 돌아간다 - 그 화면이 곧바로 뜬다.
-- neo-tree 싣기(처음이면 manager 모듈, ensure_config - 각각 수십 ms)와 두 트리 그리기(_navigate_internal - 따뜻해도
-- 트리마다 10~20ms)는 그 뒤 한 틱에 하나씩 (vim.defer_fn 0: 틱 사이에 다시 그리기와 누른 키가 먼저 돈다). 그 사이
-- 그 칸의 트리를 옮겼으면(경로 칸의 Enter·따라가기, \x - tree_go 가 sd.first 를 비운다) 건너뛴다.
-- 실측(맥, 부하 14): 키 처리 처음 180~290ms -> 30~50ms, 따뜻할 때 70~170ms -> 20~50ms. 그 뒤 틱은 하나에 25~50ms
local function first_trees(L)
  local steps = {
    function()
      pcall(require, 'neo-tree.sources.manager')
    end,
    function()
      pcall(require, 'neo-tree.sources.filesystem')
      pcall(function()
        require('neo-tree').ensure_config()
      end)
    end,
  }
  for _, side in ipairs(SIDES) do
    steps[#steps + 1] = function()
      local f = L[side].first
      if f then
        tree_go(L, side, f.root, f.reveal)
      end
    end
  end
  local i = 0
  local function step()
    i = i + 1
    if L.closing or not steps[i] or not api.nvim_tabpage_is_valid(L.tab) then
      return
    end
    steps[i]()
    vim.defer_fn(step, 0)
  end
  vim.defer_fn(step, 0)
end

-- 선택 탭을 하나 연다. spec = { a = { root, reveal, text }, b = { ... }, at = 탭 번호 (그 자리에 - 없으면 지금 탭
-- 뒤에), insert = A 경로 칸에서 입력으로 }
local function open_tab(spec)
  set_hl()
  -- 곁창(트리 등)에서 :tabnew 하면 새 창이 그 창 옵션을 물려받고 neo-tree 가 가져간다 - EDIT 창에서
  local w = _G.vimide_edit_slot and _G.vimide_edit_slot()
  if w and w ~= 0 and valid(w) then
    api.nvim_set_current_win(w)
  end
  local origin = api.nvim_get_current_tabpage()
  -- 다른 선택 탭의 트리에서 열면 새 탭이 그 트리의 :lcd 를 물려받는다 - 걷는다 (경로 칸의 상대 경로 기준)
  local cur = api.nvim_get_current_win()
  local lcd = vim.w[cur].vimide_dirdiff_launch_role == 'tree' and vim.fn.haslocaldir(cur) == 1
      and vim.fn.getcwd(cur) or nil
  local at = spec.at and math.max(0, math.min(spec.at - 1, #api.nvim_list_tabpages())) or nil
  vim.cmd((at and tostring(at) or '') .. 'tabnew')
  if lcd then
    drop_lcd(lcd)
  end
  local tab = api.nvim_get_current_tabpage()
  local L = { tab = tab, origin = origin, a = {}, b = {} }
  launchers[tab] = L
  vim.t[tab].vimide_dirdiff_launch = true
  -- airline 의 탭 줄은 t:title 을 먼저 본다 (dirdiffview.lua 처럼)
  vim.t[tab].title = 'DirDiff 선택'
  local pa = api.nvim_get_current_win()
  local nb = api.nvim_get_current_buf()
  plain(pa)
  L.a.prompt_buf = new_prompt('a')
  api.nvim_win_set_buf(pa, L.a.prompt_buf)
  if api.nvim_buf_is_valid(nb) and nb ~= L.a.prompt_buf and api.nvim_buf_get_name(nb) == ''
      and not vim.bo[nb].modified and #vim.fn.win_findbuf(nb) == 0 then
    pcall(api.nvim_buf_delete, nb, { force = true })
  end
  L.a.prompt_win = pa
  L.b.prompt_buf = new_prompt('b')
  L.b.prompt_win = api.nvim_open_win(L.b.prompt_buf, false, { split = 'right', win = pa })
  for _, side in ipairs(SIDES) do
    local sd = L[side]
    local hold = api.nvim_create_buf(false, true)
    vim.bo[hold].bufhidden = 'wipe'
    api.nvim_buf_set_lines(hold, 0, -1, false, { '  (읽는 중…)' })
    -- 트리는 다음 틱부터 그린다 (first_trees) - 그 사이 이리 와도 q·Ctrl+k·\x 는 듣게, 글은 고칠 수 없게
    vim.bo[hold].modifiable = false
    map_common(hold)
    sd.tree_win = api.nvim_open_win(hold, false, { split = 'below', win = sd.prompt_win })
    mark_win(sd.prompt_win, side, 'prompt')
    mark_win(sd.tree_win, side, 'tree')
    set_wo(sd.prompt_win, WO)
    set_wo(sd.tree_win, WO)
    -- winfixbuf: Ctrl+O·Ctrl+^·:e·:b 가 경로 칸 자리에 다른 버퍼를 열지 않게 (E1513 으로 막힌다. 트리는 neo-tree
    -- 가 제 버퍼를 갈아 끼우므로 걸지 않는다)
    set_wo(sd.prompt_win, { winfixheight = true, winfixbuf = true,
      winhighlight = 'WinSeparator:VimIdeDiffLaunchBorder,StatusLine:VimIdeDiffLaunchHint,'
        .. 'StatusLineNC:VimIdeDiffLaunchHint' })
  end
  -- 점프 목록·태그 스택을 비운다: :tabnew 는 지금 창의 것을 물려주고, nvim_open_win 의 split 은 이웃 경로 칸
  -- 버퍼를 넣는다 - Ctrl+O 가 그 파일·버퍼를 경로 칸이나 트리 자리에 열어 그 칸이 망가졌다
  for _, side in ipairs(SIDES) do
    for _, w2 in ipairs({ L[side].prompt_win, L[side].tree_win }) do
      pcall(api.nvim_win_call, w2, function()
        vim.cmd('clearjumps')
      end)
      pcall(vim.fn.settagstack, w2, { items = {} }, 'r')
    end
  end
  -- 창 머리(winbar)를 먼저 단다: 경로 칸을 한 줄로 줄인 뒤에 머리가 붙으면 그 칸이 이웃에서 한 줄을 빌려 nvim 의
  -- 창 높이 셈이 어긋났고, 다음 크기 바꾸기(VimResized) 때 트리의 상태줄이 명령줄 밑으로 밀려 되돌아오지 않았다
  update_bars(L)
  relayout(L)
  set_prompt(L, 'a', spec.a.text)
  set_prompt(L, 'b', spec.b.text)
  update_bars(L)
  L.a.first = { root = spec.a.root, reveal = spec.a.reveal }
  L.b.first = { root = spec.b.root, reveal = spec.b.reveal }
  first_trees(L)
  api.nvim_set_current_win(pa)
  if spec.insert then
    vim.cmd('startinsert!')
  end
  return L
end

function _G.vimide_dirdiff_launch(arg_a, arg_b)
  if not pcall(require, 'neo-tree') then
    return say('neo-tree 가 없습니다 (:PlugInstall)', levels.WARN)
  end
  -- 선택 탭의 창에서 열면 탭(없으면 전역) 디렉터리에서 - 그 트리의 :lcd(트리 뿌리)는 '지금 디렉터리' 가 아니다
  local cwd = real_of(vim.w.vimide_dirdiff_launch and vim.fn.getcwd(-1, 0) or vim.fn.getcwd())
  local fdir = cwd
  local name = api.nvim_buf_get_name(0)
  if vim.bo.buftype == '' and name ~= '' and vim.fn.filereadable(name) == 1 then
    fdir = real_of(vim.fn.fnamemodify(name, ':p:h'))
  end
  local here = api.nvim_get_current_win()
  local ra, va, ta = start_at(arg_a, fdir, here)
  local rb, vb, tb = start_at(arg_b, cwd, here)
  return open_tab({
    a = { root = ra, reveal = va, text = shown(ta, kind_of(ta)) },
    b = { root = rb, reveal = vb, text = shown(tb, kind_of(tb)) },
    insert = true,
  })
end

-- 세션 저장(vimidesession.lua 의 M.save)이 부른다: 선택 탭을 모두 닫고, 같은 자리(탭 번호)에 같은 경로 칸·선택·
-- 뿌리·커서 줄로 되살리는 함수를 돌려준다 (선택 탭이 없으면 nil, 선택 탭뿐이라 저장할 것이 없으면 false).
-- 경로 칸·트리뿐이라 :mksession 이 빈 탭으로 적었고(되살리면 빈 탭이 하나), 지금 탭이면 저장의 패널 세기·닫기가
-- 이 탭의 트리를 F9 트리로 세고 경로 칸을 닫아 탭째 닫혔다. 나가는 길에는 아래 VimLeavePre 가 먼저 닫아 둔다
function _G.vimide_dirdiff_launch_stash()
  if next(launchers) == nil then
    return nil
  end
  local tabs = api.nvim_list_tabpages()
  local plain_tab = false
  for _, t in ipairs(tabs) do
    if not launchers[t] then
      plain_tab = true
      break
    end
  end
  if not plain_tab then
    return false
  end
  local cur_tab, cur_win = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
  local cL, cside, crole = where(cur_win)
  local list = {}
  for tab, L in pairs(launchers) do
    if api.nvim_tabpage_is_valid(tab) then
      local e = { nr = api.nvim_tabpage_get_number(tab), tab = tab, origin = L.origin, L = L }
      if L == cL then
        e.side, e.role = cside, crole
      end
      for _, side in ipairs(SIDES) do
        local sd = L[side]
        e[side] = { text = prompt_text(sd.prompt_buf), pick = sd.pick, root = tree_root(sd), reveal = cursor_path(sd) }
      end
      list[#list + 1] = e
    end
  end
  table.sort(list, function(x, y)
    return x.nr < y.nr
  end)
  pcall(vim.cmd, 'stopinsert')
  for _, e in ipairs(list) do
    pcall(close, e.L)
    e.L = nil
  end
  -- close 는 연 곳으로 옮긴다 - 선택 탭이 아닌 곳에 있었으면 그 창으로 (저장은 거기서)
  if not cL and valid(cur_win) then
    api.nvim_set_current_tabpage(cur_tab)
    api.nvim_set_current_win(cur_win)
  end
  return function()
    if vim.v.exiting ~= vim.NIL then
      return
    end
    local back_tab, back_win = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
    local focus
    local new_of = {} -- 닫은 탭 -> 되살린 L (연 곳이 다른 선택 탭이었으면 되살린 그 탭으로)
    for _, e in ipairs(list) do
      local fallback = real_of(vim.fn.getcwd(-1, 0))
      local spec = { at = e.nr }
      for _, side in ipairs(SIDES) do
        local s = e[side]
        local root = (s.root and kind_of(s.root) == 'dir') and s.root or fallback
        spec[side] = { root = root, reveal = s.reveal, text = s.text }
      end
      local ok, L = pcall(open_tab, spec)
      if ok and L then
        new_of[e.tab] = L
        for _, side in ipairs(SIDES) do
          local s = e[side]
          if s.pick and kind_of(s.pick.path) == s.pick.kind then
            set_pick(L, side, s.pick.path, s.pick.kind)
          end
          if prompt_text(L[side].prompt_buf) ~= s.text then
            set_prompt(L, side, s.text)
          end
        end
        if e.role then
          focus = L[e.side][e.role .. '_win']
        end
      end
    end
    for _, e in ipairs(list) do
      local L = new_of[e.tab]
      local o = e.origin and (new_of[e.origin] and new_of[e.origin].tab or e.origin)
      if L and o and api.nvim_tabpage_is_valid(o) then
        L.origin = o
      end
    end
    if valid(focus) then
      api.nvim_set_current_win(focus)
    elseif api.nvim_tabpage_is_valid(back_tab) then
      api.nvim_set_current_tabpage(back_tab)
      if valid(back_win) then
        api.nvim_set_current_win(back_win)
      end
    end
  end
end

api.nvim_create_user_command('DirDiffPick', function(o)
  _G.vimide_dirdiff_launch(o.fargs[1], o.fargs[2])
end, { nargs = '*', complete = 'file', desc = 'DirDiff 선택: 비교할 두 곳(A | B)을 트리와 경로 칸으로 고르는 탭' })

do
  local key = vim.g.vimide_dirdiff_launch_key
  if key == nil then
    key = '<leader>D'
  end
  if type(key) == 'string' and key ~= '' then
    vim.keymap.set('n', key, function()
      _G.vimide_dirdiff_launch()
    end, { silent = true, desc = 'DirDiff 선택: 비교할 두 곳(A | B)을 트리와 경로 칸으로 고르는 탭 (:DirDiffPick)' })
  end
end

-- 창 하나가 닫히면 (:q, <C-w>o ...) 탭째 닫는다. 탭이 :tabclose 로 닫혔으면 치운다
api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(a)
    local w = tonumber(a.match)
    if not (w and api.nvim_win_is_valid(w)) or not vim.w[w].vimide_dirdiff_launch then
      return
    end
    local b = api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == '' and api.nvim_buf_get_name(b) == '' then
      orphans[b] = true
    end
    local snap = {}
    for _, x in ipairs(api.nvim_list_bufs()) do
      snap[x] = true
    end
    local L = where(w)
    vim.schedule(function()
      if L then
        close(L)
      end
      sweep(snap)
    end)
  end,
})

api.nvim_create_autocmd('TabClosed', {
  group = group,
  callback = function()
    for tab, L in pairs(launchers) do
      if not api.nvim_tabpage_is_valid(tab) then
        close(L)
      end
    end
  end,
})

-- 끝낼 때 선택 탭을 닫는다 (dirdiffview.lua 의 비교 탭처럼 - vimidesession 의 VimLeavePre 보다 먼저 돈다:
-- plugin/ 을 이름 순으로 읽는다). 그대로 두면 세션에 빈 탭으로 적혀 다음에 빈 탭이 하나 되살아났다
api.nvim_create_autocmd('VimLeavePre', {
  group = group,
  callback = function()
    for _, L in pairs(vim.tbl_values(launchers)) do
      pcall(close, L)
    end
  end,
})

api.nvim_create_autocmd({ 'VimResized', 'TabEnter' }, {
  group = group,
  callback = function()
    local L = launchers[api.nvim_get_current_tabpage()]
    if L then
      relayout(L)
    end
  end,
})

-- 다른 까닭으로 창 폭이 바뀌어도 (이 탭에 F9·quickfix 를 열고 닫기) 창 머리·상태줄을 새 폭으로 다시 자른다 -
-- 그대로 두면 nvim 이 앞을 '<' 로 잘랐다
api.nvim_create_autocmd('WinResized', {
  group = group,
  callback = function()
    if next(launchers) == nil then
      return
    end
    local done = {}
    for _, w in ipairs(vim.v.event.windows or {}) do
      local L = where(w)
      if L and not done[L] then
        done[L] = true
        update_bars(L)
      end
    end
  end,
})
