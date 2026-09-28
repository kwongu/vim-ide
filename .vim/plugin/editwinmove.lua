-- editwinmove.lua - 창 옮기기(Ctrl-W H J K L r R x T)를 EDIT 영역 안에서만
--
-- vim 의 Ctrl-W H/J/K/L 은 지금 창을 '화면 전체'의 맨 왼쪽/아래/위/오른쪽으로
-- 보낸다. vim-ide 배치(왼쪽 트리·aerial, 오른쪽 RelationView 열, 아래 quickfix)
-- 에서 그러면 편집 창이 곁창 바깥으로 나가 트리 옆에 세로로 길게 붙거나,
-- quickfix 아래로 내려간다. Ctrl-W r/R/x 도 곁창과 자리를 바꾼다.
--
-- 여기서는 곁창을 제자리에 두고 편집 창들끼리만 옮긴다. EDIT 창이 3분할 4분할
-- 이어도 그 안에서 vim 과 똑같이 움직인다:
--   1. 곁창을 잠시 숨은 부동 창으로 돌린다 - 그러면 창 배치에는 편집 창만 남아
--      vim 의 wincmd 가 편집 영역을 '화면 전체'로 알고 그대로 동작한다
--   2. vim 의 wincmd 를 그대로 부른다
--   3. 곁창을 원래 배치대로 되돌린다. 편집 창을 모두 담는 가장 작은 틀에서 편집
--      창들의 앞(왼쪽/위)과 뒤(오른쪽/아래)에 있던 곁창, 그리고 그 틀을 감싸는
--      바깥 겹의 곁창은 안쪽 겹부터 바깥으로 화면 가장자리에 붙이고(topleft/
--      botright 쪼개기) 그 안을 쪼개 채운다. 편집 창 사이에 끼어 있던 곁창
--      (location list 등)은 이웃 창 곁으로 - 이웃도 곁창이면 그것부터.
--      (vim-ide 배치에서는 :vsplit 한 편집 창들이 곁창과 같은 겹의 형제가 된다 -
--      row(aerial, 편집, 편집, RelationView 열) - 편집 영역이 따로 한 덩이가 아니다)
--   4. 크기: 곁창은 제 치수(열은 폭, 줄은 높이, 쌓인 것은 높이)를 바깥 것부터 여러
--      번 되돌리며 되돌린 것은 잠가 둔다 - 한 번에 창 목록 순서로 하면 나중에
--      되돌린 전폭 quickfix 가 RelationView 열의 줄을 도로 가져가 한 칸이 0줄이
--      되었다 (반대 심문). 편집 창은 x/r/R 이면 제 크기를, H/J/K/L 이면 vim 처럼
--      ('equalalways') 곁창을 잠근 채 고르게. 스크롤 위치(winsaveview)도 되돌린다.
-- 곁창에 서서 누르면 아무것도 하지 않는다(곁창은 제자리). 부동 창, 곁창이 없는 탭
-- 에서는 vim 그대로. Ctrl-W T 는 편집 창을 새 탭으로 옮기되, 곁창이 있는 탭에서
-- 편집 창이 하나뿐이면 그 자리에 대체 버퍼(없으면 빈 버퍼) 창을 남겨 원래 탭의
-- 배치를 지킨다. 되돌리다 실패해도 숨은 부동 창은 남기지 않는다.
--
--   let g:vimide_edit_winmove = 0   " 끄기 (vim 그대로)
--
-- nvim 전용이다 (부동 창). 진짜 vim 8.1 은 이 파일을 읽지 않는다.

if vim.g.loaded_vimide_editwinmove then
  return
end
vim.g.loaded_vimide_editwinmove = 1

local api = vim.api
local CMDS = { H = true, J = true, K = true, L = true, r = true, R = true, x = true, T = true }
local EDGE = { H = 'left', L = 'right', K = 'above', J = 'below' }

local function is_float(w)
  local ok, c = pcall(api.nvim_win_get_config, w)
  return ok and c.relative ~= nil and c.relative ~= ''
end

local function is_edit(w)
  if _G.vimide_is_edit_win then
    return _G.vimide_is_edit_win(w)
  end
  return vim.bo[api.nvim_win_get_buf(w)].buftype == '' and not is_float(w)
end

local function say(msg)
  (_G.vimide_notify or vim.notify)('창 옮기기: ' .. msg, vim.log.levels.INFO)
end

local function leaves(node, out)
  out = out or {}
  if node[1] == 'leaf' then
    out[#out + 1] = node[2]
  else
    for _, ch in ipairs(node[2]) do
      leaves(ch, out)
    end
  end
  return out
end

local function first_leaf(node)
  while node[1] ~= 'leaf' do
    node = node[2][1]
  end
  return node[2]
end

local function last_leaf(node)
  while node[1] ~= 'leaf' do
    node = node[2][#node[2]]
  end
  return node[2]
end

-- 편집 창을 모두 담는 가장 작은 노드와, 뿌리에서 거기까지의 길
local function edit_root(layout, is_e, total)
  local path = {}
  local node = layout
  while node[1] ~= 'leaf' do
    local hit
    for i, ch in ipairs(node[2]) do
      local n = 0
      for _, w in ipairs(leaves(ch)) do
        if is_e[w] then
          n = n + 1
        end
      end
      if n == total then
        hit = i
        break
      elseif n > 0 then
        hit = nil
        break
      end
    end
    if not hit then
      break
    end
    path[#path + 1] = { node = node, idx = hit }
    node = node[2][hit]
  end
  return node, path
end

local function to_split(w, dir, anchor)
  api.nvim_win_set_config(w, { split = dir, win = anchor })
end

-- node 의 창들을 첫 잎(이미 제자리) 안에 쪼개 채운다. 한 겹의 첫 잎들을 먼저
-- 나란히 놓고 나서 안으로 들어간다 - 안부터 채우면 다음 형제가 그 안쪽 틀에 붙는다.
local function build(node)
  if node[1] == 'leaf' then
    return
  end
  local dir = node[1] == 'row' and 'right' or 'below'
  local prev = first_leaf(node[2][1])
  for i = 2, #node[2] do
    local f = first_leaf(node[2][i])
    to_split(f, dir, prev)
    prev = f
  end
  for _, ch in ipairs(node[2]) do
    build(ch)
  end
end

-- 곁창 덩이를 화면 가장자리에 붙인다 (topleft/botright - 중간 쪼개기 없이 한 번에)
local function place_edge(sub, edge)
  to_split(first_leaf(sub), EDGE[edge], -1)
  build(sub)
end

local function set_fix(w, fw, fh)
  vim.wo[w].winfixwidth = fw
  vim.wo[w].winfixheight = fh
end

-- 곁창을 숨기고 fn 을 부른 뒤 되돌린다. fn 이 지금 창을 바꾸면(x) 그 창에 선다.
local function with_sides_hidden(cmd, cur, sides, edits, is_e, fn)
  local layout = vim.fn.winlayout()
  local eroot, path = edit_root(layout, is_e, #edits)

  local function has_edit(node)
    for _, w in ipairs(leaves(node)) do
      if is_e[w] then
        return true
      end
    end
    return false
  end

  -- 편집 창 사이에 끼어 있는 곁창 덩이. 편집 창이 든 형제 안부터 적고(그 안의 곁창이
  -- 이웃의 닻이 될 수 있다), 이 겹에서는 첫 편집 형제 뒤의 것은 앞 이웃의 마지막 잎
  -- 곁에(앞에서부터), 앞의 것은 뒤 이웃의 첫 잎 곁에(뒤에서부터) - 닻이 늘 먼저
  -- 제자리에 있게 (반대 심문: help 위 preview 처럼 이웃도 곁창이면 닻이 아직 숨은
  -- 창이라 현재 창 아래로 떨어졌다)
  local inner = {}
  local function scan(node, lo, hi)
    if node[1] == 'leaf' then
      return
    end
    local kids = node[2]
    lo, hi = lo or 1, hi or #kids
    local first_e
    for i = lo, hi do
      if has_edit(kids[i]) then
        first_e = first_e or i
        scan(kids[i])
      end
    end
    if not first_e then
      return
    end
    local row = node[1] == 'row'
    for i = first_e + 1, hi do
      if not has_edit(kids[i]) then
        inner[#inner + 1] = { sub = kids[i], anchor = last_leaf(kids[i - 1]), dir = row and 'right' or 'below' }
      end
    end
    for i = first_e - 1, lo, -1 do
      inner[#inner + 1] = { sub = kids[i], anchor = first_leaf(kids[i + 1]), dir = row and 'left' or 'above' }
    end
  end
  local fi, li = 1, 1
  if eroot[1] ~= 'leaf' then
    fi, li = nil, nil
    for i, ch in ipairs(eroot[2]) do
      if has_edit(ch) then
        fi = fi or i
        li = i
      end
    end
    scan(eroot, fi, li)
  end

  -- 곁창이 제 치수로 되돌릴 것: 가장자리 열(H/L)은 폭, 가장자리 줄(J/K)은 높이,
  -- 사이에 낀 것은 쪼갠 방향의 치수. 덩이 안에서는 쌓인 것은 높이, 나란한 것은 폭.
  -- depth: 바깥 겹일수록 작다 - 바깥 것부터 되돌린다.
  local keep = {}
  local function mark(sub, w_axis, h_axis, depth)
    local function walk(node, parent)
      if node[1] == 'leaf' then
        local k = keep[node[2]] or { depth = depth }
        k.w = k.w or w_axis or parent == 'row'
        k.h = k.h or h_axis or parent == 'col'
        keep[node[2]] = k
        return
      end
      for _, ch in ipairs(node[2]) do
        walk(ch, node[1])
      end
    end
    walk(sub, nil)
  end

  local size, view, fix = {}, {}, {}
  for _, w in ipairs(sides) do
    size[w] = { api.nvim_win_get_width(w), api.nvim_win_get_height(w) }
    fix[w] = { vim.wo[w].winfixwidth, vim.wo[w].winfixheight }
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if not is_float(w) then
      view[w] = api.nvim_win_call(w, vim.fn.winsaveview)
    end
  end
  local esize = {}
  for _, w in ipairs(edits) do
    esize[w] = { api.nvim_win_get_width(w), api.nvim_win_get_height(w) }
  end

  local ei = vim.o.eventignore
  vim.o.eventignore = 'all'
  local hidden = {}
  local ok, err = pcall(function()
    for _, w in ipairs(sides) do
      api.nvim_win_set_config(w, {
        relative = 'editor', row = 0, col = 0, width = 1, height = 1, hide = true,
      })
      hidden[w] = true
    end
    api.nvim_set_current_win(cur)
    fn()
  end)
  local focus = api.nvim_get_current_win()
  if not api.nvim_win_is_valid(focus) or is_float(focus) then
    focus = cur
  end

  local fails = {}
  local function try(what, f)
    local good, e = pcall(f)
    if not good then
      fails[#fails + 1] = what .. ': ' .. tostring(e):gsub('^.-(E%d+:)', '%1')
    end
  end
  local function host()
    -- 가장 넓은 보통 창에 붙인다 (좁은 창을 쪼개다 E36 이 나지 않게)
    local best, area = nil, -1
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if not is_float(w) then
        local a = api.nvim_win_get_width(w) * api.nvim_win_get_height(w)
        if a > area then
          best, area = w, a
        end
      end
    end
    return best
  end

  for _, r in ipairs(inner) do
    mark(r.sub, r.dir == 'left' or r.dir == 'right', r.dir == 'above' or r.dir == 'below', 1000)
    try('곁창', function()
      local f = first_leaf(r.sub)
      if r.anchor and api.nvim_win_is_valid(r.anchor) and not is_float(r.anchor) then
        to_split(f, r.dir, r.anchor)
      else
        to_split(f, 'below', host())
      end
      build(r.sub)
    end)
  end
  -- 가장자리: 가장 작은 틀의 앞뒤, 그다음 바깥 겹들 (안쪽부터)
  local levels = {}
  if eroot[1] ~= 'leaf' then
    levels[1] = { node = eroot, lo = fi, hi = li, depth = #path + 1 }
  end
  for k = #path, 1, -1 do
    levels[#levels + 1] = { node = path[k].node, lo = path[k].idx, hi = path[k].idx, depth = k }
  end
  for _, lv in ipairs(levels) do
    local kids = lv.node[2]
    local row = lv.node[1] == 'row'
    for j = lv.hi + 1, #kids do
      mark(kids[j], row, not row, lv.depth)
      try('곁창', function()
        place_edge(kids[j], row and 'L' or 'J')
      end)
    end
    for j = lv.lo - 1, 1, -1 do
      mark(kids[j], row, not row, lv.depth)
      try('곁창', function()
        place_edge(kids[j], row and 'H' or 'K')
      end)
    end
  end
  -- 되돌리지 못한 것이 있으면 아래 가장자리에라도 - 숨은 부동 창으로 남기지 않는다
  for _, w in ipairs(sides) do
    if api.nvim_win_is_valid(w) and is_float(w) then
      local good = pcall(to_split, w, 'below', -1)
      if not good then
        pcall(api.nvim_win_set_config, w, { relative = 'editor', row = 1, col = 1,
          width = math.max(20, math.floor(vim.o.columns / 3)), height = 5, hide = false, border = 'single' })
      end
    end
  end

  -- 크기: 곁창을 바깥 것부터 여러 번 되돌리며 되돌린 것은 잠근다
  local order = {}
  for _, w in ipairs(sides) do
    if api.nvim_win_is_valid(w) and not is_float(w) and keep[w] then
      order[#order + 1] = w
    end
  end
  table.sort(order, function(a, b)
    return keep[a].depth < keep[b].depth
  end)
  for _ = 1, 3 do
    for _, w in ipairs(order) do
      set_fix(w, false, false)
      if keep[w].w then
        pcall(api.nvim_win_set_width, w, size[w][1])
      end
      if keep[w].h then
        pcall(api.nvim_win_set_height, w, size[w][2])
      end
      set_fix(w, keep[w].w or fix[w][1], keep[w].h or fix[w][2])
    end
  end
  -- 편집 창: x/r/R 은 제 크기, H/J/K/L 은 vim 처럼 고르게 (곁창은 잠근 채)
  if ok then
    if cmd == 'x' or cmd == 'r' or cmd == 'R' then
      for _ = 1, 2 do
        for w, sz in pairs(esize) do
          if api.nvim_win_is_valid(w) then
            pcall(api.nvim_win_set_width, w, sz[1])
            pcall(api.nvim_win_set_height, w, sz[2])
          end
        end
      end
    elseif vim.o.equalalways then
      pcall(vim.cmd, 'wincmd =')
    end
  end
  for _, w in ipairs(sides) do
    if api.nvim_win_is_valid(w) then
      pcall(set_fix, w, fix[w][1], fix[w][2])
    end
  end
  -- 스크롤 위치
  for w, v in pairs(view) do
    if api.nvim_win_is_valid(w) and not is_float(w) then
      pcall(api.nvim_win_call, w, function()
        vim.fn.winrestview(v)
      end)
    end
  end

  vim.o.eventignore = ei
  if api.nvim_win_is_valid(focus) then
    api.nvim_set_current_win(focus)
  end
  if #fails > 0 then
    vim.notify('창 옮기기: 곁창을 제자리에 다 되돌리지 못했습니다 - ' .. fails[1], vim.log.levels.WARN)
  end
  if not ok then
    -- vim 의 오류(E443 등)를 그대로 보여 준다
    local msg = tostring(err):gsub('^.-(E%d+:)', '%1')
    vim.notify(msg, vim.log.levels.WARN)
  end
end

local function tab_move(cur, edits, count)
  local native = (count > 0 and count or '') .. 'wincmd T'
  if #edits > 1 then
    return vim.cmd(native)
  end
  -- 편집 창이 하나뿐: 그 자리에 대체 버퍼(없으면 빈 버퍼) 창을 남기고 옮긴다
  local alt = vim.fn.bufnr('#')
  local here = api.nvim_win_get_buf(cur)
  local keep = api.nvim_open_win(0, false, { split = 'above', win = cur })
  if alt > 0 and alt ~= here and vim.fn.buflisted(alt) == 1 and vim.bo[alt].buftype == '' then
    api.nvim_win_set_buf(keep, alt)
  else
    api.nvim_win_call(keep, function()
      vim.cmd('enew')
    end)
  end
  api.nvim_set_current_win(cur)
  vim.cmd(native)
end

function _G.vimide_edit_wincmd(cmd, count)
  count = count or vim.v.count
  local native = (count > 0 and count or '') .. 'wincmd ' .. cmd
  local cur = api.nvim_get_current_win()
  if vim.g.vimide_edit_winmove == 0 or is_float(cur) then
    return vim.cmd(native)
  end
  local sides, edits, is_e = {}, {}, {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if not is_float(w) then
      if is_edit(w) then
        edits[#edits + 1] = w
        is_e[w] = true
      else
        sides[#sides + 1] = w
      end
    end
  end
  if #sides == 0 then
    return vim.cmd(native) -- 곁창이 없는 탭은 vim 그대로 (T 의 'Already only one window' 도)
  end
  if not is_edit(cur) then
    return say('곁창은 제자리에 둡니다 - 편집 창에서 누르세요')
  end
  if cmd == 'T' then
    return tab_move(cur, edits, count)
  end
  if #edits < 2 then
    return -- 편집 창이 하나면 편집 영역 안에서 옮길 곳이 없다
  end
  with_sides_hidden(cmd, cur, sides, edits, is_e, function()
    vim.cmd(native)
  end)
end

local function run(k, count)
  local ok, err = pcall(_G.vimide_edit_wincmd, k, count)
  if not ok then
    vim.notify(tostring(err):gsub('^.-(E%d+:)', '%1'), vim.log.levels.WARN)
  end
end

for k in pairs(CMDS) do
  vim.keymap.set({ 'n', 'x' }, '<C-w>' .. k, function()
    if vim.fn.mode():match('^[vV\22]') then
      vim.cmd('normal! \27')
    end
    run(k)
  end, { desc = 'EDIT 영역 안에서 wincmd ' .. k })
end
for _, k in ipairs({ 'r', 'x' }) do
  vim.keymap.set({ 'n', 'x' }, '<C-w><C-' .. k .. '>', function()
    if vim.fn.mode():match('^[vV\22]') then
      vim.cmd('normal! \27')
    end
    run(k)
  end, { desc = 'EDIT 영역 안에서 wincmd ' .. k })
end
-- Ctrl-W 뒤에 치는 수(Ctrl-W 3 x)도 받는다. 우리 명령이 아니면 vim 에 그대로 넘긴다.
for d = 1, 9 do
  vim.keymap.set({ 'n', 'x' }, '<C-w>' .. d, function()
    local digits = tostring(d)
    local c = vim.fn.getcharstr()
    while c:match('^%d$') do
      digits = digits .. c
      c = vim.fn.getcharstr()
    end
    if CMDS[c] then
      if vim.fn.mode():match('^[vV\22]') then
        vim.cmd('normal! \27')
      end
      run(c, tonumber(digits))
    else
      api.nvim_feedkeys(api.nvim_replace_termcodes('<C-w>', true, false, true) .. digits .. c, 'n', false)
    end
  end, { desc = 'Ctrl-W 수 명령' })
end
