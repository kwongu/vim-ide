-- marksjump.lua - :marks 를 텔레스코프로 보고 골라서 뛴다 (북마크)
--
-- vim 의 :marks 는 표를 한 번 뿌리고 끝이라, 스무 개쯤 쌓이면 눈으로 찾는
-- 일이 된다. 파일 이름이나 그 줄의 글자로 걸러 고를 수 있어야 쓸 만하다.
--
--   \'               마크 목록 (<Leader>', g:vimide_marks_key 로 바꾼다)
--   <C-'>            같은 것. 터미널이 Ctrl+' 를 따로 보낼 때만 먹는다 (.vimrc)
--   Ctrl+M 두 번     같은 것 (= Enter 두 번, 기다림 없이. .vimrc 의 s:MarksEnter)
--   :VimIdeMarks     같은 것
--
-- 이름 붙은 북마크
--   목록 맨 앞(프롬프트 바로 밑) '＋ 등록' 줄을 고르면 지금 자리를 북마크로
--   담는다. 창을 열면 그 줄이 골라져 있다.
--     심볼 위에서 열었으면   '＋ 등록: <심볼>'  - 그대로 Enter
--     빈 곳에서 열었으면     프롬프트에 이름을 치면 '＋ 등록: <친 이름>'
--   (심볼 위에서도 이름을 치면 그 이름으로 담는다.) 프롬프트를 심볼로 미리
--   채우지 않는다 - 채우면 목록이 그 심볼로 걸러져, 뛰러 열었을 때 다른
--   북마크가 가려진다.
--   북마크는 stdpath('data')/vim-ide/bookmarks.json 에 둔다(이름, 파일, 줄,
--   그 줄의 글자). vim 마크(A-Z)는 26개뿐이고 이름을 붙일 수 없어서 따로 둔다.
--   파일을 고쳐 줄이 밀려도 적어 둔 그 줄의 글자를 가까운 곳에서 다시 찾아
--   간다(없으면 이름을 낱말로 찾고, 그것도 없으면 적어 둔 줄).
--   같은 파일·같은 줄·같은 이름이면 시각만 새로 하고, 이름이 다르면 따로 담는다.
--   친 글자는 등록 줄에 붙어 있어서, 치고 Enter 면 늘 등록이다. 걸러진 항목으로
--   가려면 그 항목으로 옮긴 뒤 Enter.
--
-- 고르고 뛰기: 화살표(또는 <C-n>/<C-p>), <Esc> 뒤 j/k 로 옮기고 <CR>.
--
-- 목록에 무엇이 뜨나
--   ★    이름 붙은 북마크. 지금 프로젝트 것이 먼저, 그다음 최근 것.
--   A-Z  파일을 넘나드는 표시. 어느 파일이든 그리로 간다.
--   a-z  이 파일 안의 표시. 지금 버퍼 것만 보여준다.
--   0-9 와 ' " ^ . [ ] 같은 자동 표시는 뺀다. 사람이 찍은 것이 아니라서
--   목록만 길어진다 - 특히 0-9 는 '최근에 닫은 파일'이라 이 설정에서는
--   .tags/files 같은 색인 내부 파일이 올라온다(실측: 열 줄 중 여섯 줄).
--   g:vimide_marks_auto = 1 이면 같이 보여준다.
--
-- 고르면 '직전에 보던 EDIT 창'에서 연다. 곁창에서 불러도 트리나 패널이
-- 파일에 덮이지 않는다 (_G.vimide_last_edit_win 을 쓴다).
--
--   <Esc> 뒤 d   그 북마크나 마크를 지운다 (마크는 :delmarks). 노멀 모드에서만 -
--                검색창에서 d 를 치는 것은 글자 입력이어야 한다.
--
-- 옵션
--   g:vimide_marks_key   기본 ["<Leader>'", "<C-'>"] (글자 하나나 목록). '' 이면 키를
--                        걸지 않는다.
--                        <C-m> 은 터미널에서 <CR> 과 같은 바이트라 편집 창의
--                        Enter 를 가져간다 (.vimrc 설명)
--   g:vimide_marks_auto  1 이면 자동 표시(' " ^ . 등)도 보여준다

if vim.g.loaded_vimide_marks then
  return
end
vim.g.loaded_vimide_marks = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api

local function telescope()
  local ok, t = pcall(require, 'telescope')
  if not ok then
    return nil
  end
  return {
    pickers = require('telescope.pickers'),
    finders = require('telescope.finders'),
    conf = require('telescope.config').values,
    actions = require('telescope.actions'),
    state = require('telescope.actions.state'),
  }
end

-- 사람이 찍은 것이 아닌 표시. 목록에서 뺀다.
--
-- 0-9 도 여기 넣는다. vim 이 '최근에 닫은 파일'을 자동으로 채우는 자리인데,
-- 이 설정에서는 그게 색인 내부 파일까지 문다 - 실측으로 목록 열 줄 중
-- 여섯 줄이 .tags/files, .tags/preset, .tags/nested 였다. 북마크를 보러
-- 온 사람에게 보여줄 것이 아니다.
local function is_auto(name)
  if name:match('^%d$') then
    return true
  end
  return ({ ["'"] = true, ['"'] = true, ['^'] = true, ['.'] = true,
    ['['] = true, [']'] = true, ['<'] = true, ['>'] = true,
    ['`'] = true })[name] == true
end

-- 그 줄의 글자. 파일이 열려 있으면 버퍼에서, 아니면 파일에서 한 줄만 읽는다.
local function line_text(path, lnum)
  if not path or path == '' or not lnum or lnum < 1 then
    return ''
  end
  local buf = vim.fn.bufnr(path)
  if buf > 0 and api.nvim_buf_is_loaded(buf) then
    local l = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
    if l then
      return (l:gsub('^%s+', ''))
    end
  end
  if vim.fn.filereadable(path) ~= 1 then
    return ''
  end
  -- 큰 파일에서 앞부분만 읽는다. readfile 의 {max} 는 음수면 끝에서부터라
  -- 양수로 주고 마지막 줄을 쓴다.
  local ok, lines = pcall(vim.fn.readfile, path, '', lnum)
  if not ok or type(lines) ~= 'table' or #lines < lnum then
    return ''
  end
  return (tostring(lines[lnum]):gsub('^%s+', ''))
end

-- ---------------------------------------------------------------------------
-- 이름 붙은 북마크 저장소
-- ---------------------------------------------------------------------------
local uv = vim.uv or vim.loop

local function bm_file()
  local f = vim.fn.stdpath('data') .. '/vim-ide/bookmarks.json'
  -- 링크로 두었으면 링크를 따라간 자리를 고친다. 바꿔 치기(rename)를 링크에
  -- 하면 링크가 보통 파일로 갈린다.
  return uv.fs_realpath(f) or f
end

-- 한 줄 글자를 적어 둘 모양으로. 바이트가 아니라 글자로 자른다 - 200바이트에서
-- 자르면 한글이 반쪽으로 잘려 json_encode 가 E474 로 죽었다(반대 심문 실측).
local function cut(line)
  return vim.fn.strcharpart(vim.trim(line or ''), 0, 200)
end

-- 목록을 읽는다. 두 번째 값이 true 면 '읽을 수 없다' - 그때는 절대 쓰지 않는다.
-- 빈 목록으로 덮어쓰면 담아 둔 것을 전부 잃는다. '없다'와 '못 읽는다'를 가른다:
-- 권한이 없어 못 읽는 파일을 없는 것으로 보고 덮어쓴 적이 있다(반대 심문).
local function bm_read()
  local f = bm_file()
  if not uv.fs_stat(f) then
    return {}, false
  end
  local okr, lines = pcall(vim.fn.readfile, f)
  if not okr or type(lines) ~= 'table' then
    return {}, true
  end
  local ok, d = pcall(vim.fn.json_decode, table.concat(lines, '\n'))
  if not ok or type(d) ~= 'table' then
    return {}, true
  end
  local list = d
  if d.bookmarks ~= nil then
    list = d.bookmarks
  end
  if type(list) ~= 'table' then
    return {}, true
  end
  if next(list) == nil then
    return {}, false -- '{}', '[]', bookmarks: {} 는 빈 목록
  end
  if not vim.islist(list) then
    return {}, true
  end
  for _, e in ipairs(list) do
    if type(e) ~= 'table' then
      return {}, true
    end
  end
  return list, false
end

-- 여러 nvim 이 함께 쓴다. 잠금 파일로 '읽고-고치고-쓰기'를 한 번에 하나씩만
-- 하고(예전에는 둘이 동시에 쓰면 서로의 것을 잃었다), 임시 파일 이름은 프로세스
-- 마다 달리 해서 바꿔 친다. 10초 넘게 남은 잠금은 죽은 프로세스의 것으로 본다.
local function with_lock(f, fn)
  local lock = f .. '.lock'
  for _ = 1, 100 do
    local fd = uv.fs_open(lock, 'wx', 420)
    if fd then
      uv.fs_close(fd)
      local ok, a, b2 = pcall(fn)
      uv.fs_unlink(lock)
      if not ok then
        error(a, 0)
      end
      return a, b2
    end
    local st = uv.fs_stat(lock)
    if st and os.time() - st.mtime.sec > 10 then
      uv.fs_unlink(lock)
    else
      vim.wait(20)
    end
  end
  vim.notify('북마크 파일이 잠겨 있어 고치지 못했습니다: ' .. lock, vim.log.levels.ERROR)
  return false
end

-- fn(list) 는 고친 목록과 덧붙일 정보를 돌려준다. 성공하면 true, 정보.
local function bm_update(fn)
  local f = bm_file()
  vim.fn.mkdir(vim.fn.fnamemodify(f, ':h'), 'p')
  return with_lock(f, function()
    local list, bad = bm_read()
    if bad then
      vim.notify('북마크 파일을 읽을 수 없어 고치지 않았습니다: ' .. f, vim.log.levels.ERROR)
      return false
    end
    local nl, info = fn(list)
    list = nl or list
    local oke, text = pcall(vim.fn.json_encode, { version = 1, bookmarks = list })
    if not oke then
      vim.notify('북마크를 적지 못했습니다 (' .. tostring(text) .. ')', vim.log.levels.ERROR)
      return false
    end
    local tmp = f .. '.tmp.' .. vim.fn.getpid()
    if vim.fn.writefile({ text }, tmp, 's') ~= 0 then
      vim.notify('북마크 파일을 쓰지 못했습니다: ' .. tmp, vim.log.levels.ERROR)
      return false
    end
    local old = uv.fs_stat(f)
    if old then
      uv.fs_chmod(tmp, old.mode % 4096) -- 원래 권한 그대로
    end
    if not uv.fs_rename(tmp, f) then
      uv.fs_unlink(tmp)
      vim.notify('북마크 파일을 바꾸지 못했습니다: ' .. f, vim.log.levels.ERROR)
      return false
    end
    return true, info
  end)
end

-- 같은 파일·같은 줄·같은 이름이면 시각만 고친다('same'). 이름이 다르면 따로
-- 담는다 - 예전에는 같은 줄이면 이름을 갈아 끼워서, 빠르게 Enter 를 세 번 치거나
-- 걸러 놓고 Enter 를 치면 있던 북마크의 이름이 조용히 바뀌었다(반대 심문).
local function bm_add(pos, name)
  return bm_update(function(list)
    for _, b in ipairs(list) do
      if b.path == pos.path and b.line == pos.line and b.name == name then
        b.col, b.text, b.time = pos.col, pos.text, os.time()
        return list, 'same'
      end
    end
    list[#list + 1] = { name = name, path = pos.path, line = pos.line, col = pos.col,
      text = pos.text, time = os.time() }
    return list, 'new'
  end)
end

-- 지운 개수를 돌려준다 (0 이면 그새 없어진 것)
local function bm_remove(e)
  local ok, n = bm_update(function(list)
    local out, n = {}, 0
    for _, b in ipairs(list) do
      if b.path == e.path and b.line == e.bline and b.name == e.name then
        n = n + 1
      else
        out[#out + 1] = b
      end
    end
    return out, n
  end)
  return ok and (n or 0) or 0
end

local function collect()
  local out = {}
  local function add(m, global)
    local name = m.mark:sub(2)           -- "'a" -> "a"
    if name == '' then
      return
    end
    if is_auto(name) and (tonumber(vim.g.vimide_marks_auto) or 0) == 0 then
      return
    end
    -- expand() 를 거치지 않는다. expand() 는 경로가 'wildignore' 에 걸리면 빈
    -- 글자를 돌려주는데, 이 설정의 wildignore 에는 */tmp/* 가 있다 - Yocto
    -- 빌드 경로(build/.../tmp/work/...)의 마크가 빈 경로 -> 지금 디렉터리 ->
    -- '디렉터리 마크'로 걸러져 목록에서 조용히 사라졌다(실측: 마크 D, Q).
    -- ~ 는 fnamemodify 의 :p 가 푼다.
    local path = m.file and vim.fn.fnamemodify(m.file, ':p')
        or api.nvim_buf_get_name(m.pos[1] or 0)
    if not path or path == '' then
      return
    end
    -- 디렉터리를 가리키는 마크는 뺀다. 골라도 파일이 아니라 트리가 열린다
    -- (실측: 마크 D 가 kernel/common/ 을 가리켜서 NvimTree 가 떴다).
    if vim.fn.isdirectory(path) == 1 then
      return
    end
    local lnum = m.pos[2] or 1
    out[#out + 1] = {
      kind = 'mark',
      name = name,
      global = global,
      path = path,
      lnum = lnum,
      col = math.max(0, (m.pos[3] or 1) - 1),
      -- ':~:.' 가 빈 글자를 주는 자리가 있다(실측: 목록에 이름 없는 줄이
      -- 둘 있었다). 그러면 절대 경로라도 보여 준다 - 어느 파일인지 모르는
      -- 줄이 목록에 있으면 고를 수가 없다.
      short = (function()
        local sh = vim.fn.fnamemodify(path, ':~:.')
        return (sh ~= nil and sh ~= '') and sh or path
      end)(),
      text = line_text(path, lnum),
    }
  end
  for _, m in ipairs(vim.fn.getmarklist()) do   -- A-Z, 0-9
    add(m, true)
  end
  for _, m in ipairs(vim.fn.getmarklist(api.nvim_get_current_buf())) do
    add(m, false)
  end
  table.sort(out, function(a, b)
    if a.global ~= b.global then
      return a.global          -- 파일을 넘나드는 것부터
    end
    return a.name < b.name
  end)
  -- 이름 붙은 북마크는 마크보다 앞에. 지금 프로젝트 것이 먼저, 그다음 최근 것.
  local root = type(_G.projectfiles_root_of) == 'function'
      and select(2, pcall(_G.projectfiles_root_of, vim.fn.getcwd())) or nil
  if type(root) ~= 'string' or root == '' then
    root = vim.fn.getcwd()
  end
  local bms = {}
  for _, b in ipairs((bm_read())) do
    if type(b) == 'table' and type(b.path) == 'string' and b.path ~= '' then
      local sh = vim.fn.fnamemodify(b.path, ':~:.')
      bms[#bms + 1] = {
        kind = 'bookmark', name = tostring(b.name or '?'), path = b.path,
        lnum = tonumber(b.line) or 1, bline = b.line, col = tonumber(b.col) or 0,
        saved = tostring(b.text or ''), short = (sh ~= '' and sh or b.path),
        text = tostring(b.text or ''), time = tonumber(b.time) or 0,
        here = b.path:sub(1, #root + 1) == root .. '/',
      }
    end
  end
  table.sort(bms, function(a, b)
    if a.here ~= b.here then
      return a.here
    end
    return a.time > b.time
  end)
  return vim.list_extend(bms, out)
end

-- 표시 폭 w 칸에 맞춘다(넘치면 글자 단위로 잘라 …). 바이트로 자르고 채우면 한글
-- 이름이 반쪽으로 깨지고 칸이 어긋났다.
local function fit(str, w, from_end)
  str = tostring(str or '')
  if vim.fn.strdisplaywidth(str) > w then
    local n = vim.fn.strchars(str)
    while n > 0 and vim.fn.strdisplaywidth(str) > w - 1 do
      n = n - 1
      str = from_end and vim.fn.strcharpart(str, 1) or vim.fn.strcharpart(str, 0, n)
    end
    str = from_end and ('…' .. str) or (str .. '…')
  end
  return str .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(str)))
end

local function label(e)
  if e.kind == 'bookmark' then
    return ('★ %s %s %5d  %s'):format(fit(e.name, 20), fit(e.short, 30, true), e.lnum,
      vim.fn.strcharpart(e.text, 0, 50))
  end
  return ('%s %-2s  %-38s %5d  %s'):format(
    e.global and '↗' or ' ', e.name, e.short:sub(-38), e.lnum, e.text:sub(1, 60))
end

-- 북마크의 줄이 밀렸으면 다시 찾는다. 돌려주는 셋째 값이 어떻게 찾았는지다:
--   'same'  적어 둔 줄에 적어 둔 글자가 그대로 있다
--   'text'  그 글자를 가까운 곳에서 찾았다 (위아래 번갈아)
--   'name'  글자는 없어졌고 이름을 낱말로 찾았다 (위아래 가까운 쪽)
--   'none'  못 찾았다 - 적어 둔 줄 그대로
-- 빈 줄이나 '}' 같은 부호뿐인 줄은 글자로 찾지 않는다. 파일에 흔해서 가장 가까운
-- 같은 글자가 엉뚱한 곳이고, 빈 줄 북마크는 파일이 그대로인데도 이름이 처음 나오는
-- 곳으로 가서 그 줄을 저장해 버렸다(반대 심문). 이름 찾기는 적어 둔 글자가
-- 있었는데 못 찾았을 때만 한다.
local function relocate(e)
  local n = api.nvim_buf_line_count(0)
  local want = e.saved or ''
  local function text_at(l)
    return cut(api.nvim_buf_get_lines(0, l - 1, l, false)[1] or '')
  end
  local l0 = math.min(math.max(e.lnum, 1), n)
  if text_at(l0) == want then
    return l0, e.col, 'same'
  end
  if want:find('[%w\128-\255]') then
    for d = 1, n do
      local up, down = l0 - d, l0 + d
      if up >= 1 and text_at(up) == want then
        return up, e.col, 'text'
      end
      if down <= n and text_at(down) == want then
        return down, e.col, 'text'
      end
      if up < 1 and down > n then
        break
      end
    end
  end
  if want ~= '' and e.name ~= '' then
    -- 대소문자를 가린다(\C). 낱말 경계는 이름 끝이 낱말 글자일 때만 건다 -
    -- 'foo()' 나 '$end' 같은 이름은 \< \> 에 걸려 영영 못 찾았다.
    local nm = vim.fn.escape(e.name, '\\')
    local pat = '\\V\\C' .. (vim.fn.match(e.name, '^\\k') == 0 and '\\<' or '') .. nm
        .. (vim.fn.match(e.name, '\\k$') >= 0 and '\\>' or '')
    local save = api.nvim_win_get_cursor(0)
    pcall(api.nvim_win_set_cursor, 0, { l0, 0 })
    local fwd = vim.fn.search(pat, 'cnW')
    local bwd = vim.fn.search(pat, 'bnW')
    pcall(api.nvim_win_set_cursor, 0, save)
    local hit = 0
    if fwd > 0 and bwd > 0 then
      hit = (fwd - l0 <= l0 - bwd) and fwd or bwd
    else
      hit = fwd > 0 and fwd or bwd
    end
    if hit > 0 then
      local col = vim.fn.match(api.nvim_buf_get_lines(0, hit - 1, hit, false)[1] or '', pat)
      return hit, math.max(col, 0), 'name'
    end
  end
  return l0, e.col, 'none'
end

local function jump(e)
  local win = 0
  if type(_G.vimide_last_edit_win) == 'function' then
    local ok, w = pcall(_G.vimide_last_edit_win)
    if ok and type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w) then
      win = w
    end
  end
  if win ~= 0 then
    pcall(api.nvim_set_current_win, win)
  end
  -- 그새 지워진 파일의 북마크는 열지 않는다 - 열면 그 이름으로 빈 버퍼가 생기고
  -- :w 한 번에 빈 파일이 만들어진다. vim 마크는 예전처럼 둔다(저장 안 한 새
  -- 버퍼의 마크도 있다). 버퍼로 떠 있으면 그것도 연다.
  if e.kind == 'bookmark' and vim.fn.filereadable(e.path) ~= 1
      and vim.fn.bufexists(e.path) == 0 then
    vim.notify('그 파일이 없습니다: ' .. vim.fn.fnamemodify(e.path, ':~:.'),
      vim.log.levels.WARN)
    return
  end
  -- 마크로 뛰면 점프 목록에 자리가 남아 <C-o> 로 돌아올 수 있다
  pcall(vim.cmd, "normal! m'")
  local cur = api.nvim_buf_get_name(0)
  if vim.fn.fnamemodify(cur, ':p') ~= e.path then
    pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(e.path))
  end
  local lnum, col = e.lnum, e.col
  if e.kind == 'bookmark' then
    -- :edit 가 실패했으면(winfixbuf 창 등) 지금 버퍼는 다른 파일이다. 거기서 줄을
    -- 찾아 저장하면 엉뚱한 줄이 적힌다.
    if vim.fn.fnamemodify(api.nvim_buf_get_name(0), ':p') ~= e.path then
      vim.notify('그 파일을 열지 못했습니다: ' .. vim.fn.fnamemodify(e.path, ':~:.'),
        vim.log.levels.WARN)
      return
    end
    local how
    lnum, col, how = relocate(e)
    -- 글자나 이름으로 새 자리를 찾았을 때만 적어 둔 줄을 고친다('none' 은 찾은
    -- 것이 아니다). 이름으로 찾았으면 그 줄의 글자도 새로 적어 다음에는 글자로
    -- 곧장 찾게 한다.
    if (how == 'text' or how == 'name') and lnum ~= e.lnum then
      local nl, nc = lnum, col
      local nt = how == 'name' and cut(api.nvim_buf_get_lines(0, nl - 1, nl, false)[1]) or nil
      bm_update(function(list)
        for _, b in ipairs(list) do
          if b.path == e.path and b.line == e.bline and b.name == e.name then
            b.line, b.col = nl, nc
            if nt then
              b.text = nt
            end
          end
        end
        return list
      end)
    end
  end
  pcall(api.nvim_win_set_cursor, 0, { lnum, col })
  pcall(vim.cmd, 'normal! zz')
end

-- 지금 자리. 창을 열기 전에 읽는다 - 열고 나면 지금 창은 프롬프트다.
-- 파일이 아닌 창(트리, 패널, quickfix)이면 담을 자리가 없다.
local function here()
  local buf = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' or path == '' then
    return nil, ''
  end
  local c = api.nvim_win_get_cursor(0)
  local line = api.nvim_get_current_line()
  -- 커서가 낱말 글자 위일 때만 심볼로 친다. <cword> 는 빈칸 위에서도 그 뒤의
  -- 낱말을 주는데, 빈 곳에서 열면 이름을 직접 받기로 했다.
  -- 'iskeyword' 로 본다 - 바이트로 [%w_] 를 보면 한글 낱말 위를 빈 곳으로 쳤다.
  local on_kw = vim.fn.matchstr(line, '\\%' .. (c[2] + 1) .. 'c\\k') ~= ''
  local sym = on_kw and vim.fn.expand('<cword>') or ''
  return {
    path = vim.fn.fnamemodify(path, ':p'), line = c[1], col = c[2],
    text = cut(line),
  }, sym
end

local function register(pos, name)
  if not pos then
    vim.notify('파일 창에서 열어야 북마크를 담을 수 있습니다', vim.log.levels.WARN)
    return false
  end
  if vim.trim(name) == '' then
    vim.notify('북마크 이름을 프롬프트에 치세요', vim.log.levels.WARN)
    return false
  end
  local ok, how = bm_add(pos, vim.trim(name))
  if ok then
    vim.notify((how == 'same' and '이미 있는 북마크입니다 (시각만 새로): %s  (%s:%d)'
        or '북마크 등록: %s  (%s:%d)'):format(vim.trim(name),
      vim.fn.fnamemodify(pos.path, ':~:.'), pos.line))
    return true
  end
  return false
end

-- 창을 닫지 않고 목록을 갈아 끼운다 (pickerkeep.lua). 친 글자는 그대로 두고,
-- 선택은 지운 자리에 올라온 줄에 둔다. 항목은 collect() 가 새로 만든 표라
-- 표끼리 견줄 수 없어서 열쇠(종류·이름·파일·줄)로 다시 찾는다.
local function entry_key(e)
  local v = e and e.value
  if type(v) ~= 'table' then
    return nil
  end
  if v.kind == 'add' then
    return 'add'
  end
  return table.concat({ v.kind or '', v.name or '', v.path or '',
    tostring(v.bline or v.lnum or '') }, '\0')
end

local function refresh_keep(picker, finder, title)
  if type(_G.vimide_picker_keep) == 'function' then
    return _G.vimide_picker_keep(picker, finder, { title = title, key = entry_key })
  end
  pcall(function() picker.layout.prompt.border:change_title(title) end)
  picker:refresh(finder, { reset_prompt = false })
end

local function picker_busy(picker)
  return type(_G.vimide_picker_busy) == 'function' and _G.vimide_picker_busy(picker)
end

function _G.vimide_marks()
  local pos, sym = here()
  local origin_buf = api.nvim_get_current_buf()
  local items = collect()
  local t = telescope()
  if not t then
    -- 0 은 취소다(inputlist 는 Esc 나 빈 Enter 도 0 을 준다). 등록은 1 번.
    local lines = { '북마크/마크 (번호, Esc 는 취소):', '1. ＋ 지금 자리를 북마크로 담기' }
    for i, e in ipairs(items) do
      lines[#lines + 1] = ('%d. %s'):format(i + 1, label(e))
    end
    local ok, idx = pcall(vim.fn.inputlist, lines)
    if ok and idx == 1 then
      local nm = vim.fn.input('북마크 이름: ', sym)
      if nm ~= '' then
        register(pos, nm)
      end
    elseif ok and items[idx - 1] then
      jump(items[idx - 1])
    end
    return
  end
  local add = { kind = 'add' }
  -- 등록 줄의 이름: 프롬프트에 친 글자, 없으면 커서 밑 심볼
  local function add_name()
    local ok, p = pcall(t.state.get_current_line)
    p = ok and vim.trim(p or '') or ''
    return p ~= '' and p or sym
  end
  local function results()
    local r = { add }
    vim.list_extend(r, items)
    return r
  end
  -- 등록 줄은 무엇을 치든 걸러지지 않고 늘 맨 앞(프롬프트 바로 밑, 맨 위)에 있다
  local sorter = t.conf.generic_sorter({})
  local score = sorter.scoring_function
  sorter.scoring_function = function(self, prompt, line, entry, ...)
    if entry and entry.value == add then
      return 0
    end
    return score(self, prompt, line, entry, ...)
  end
  local opts = {
    -- :Telescope resume 이 옛 자리·옛 심볼의 등록 줄을 되살리지 않게
    cache_picker = false,
    -- 점수가 같으면 모아 온 순서(지금 프로젝트 -> 최근 -> 마크)를 지킨다.
    -- 기본 tiebreak 는 짧은 글자를 앞으로 올려서, 글자를 치는 순간 최근
    -- 것이 위라는 순서가 흐트러졌다 (반대 심문).
    tiebreak = function() return false end,
    -- 담을 자리가 없으면(파일 아닌 창) 등록 줄 대신 첫 항목을 골라 둔다
    default_selection_index = (not pos and #items > 0) and 2 or nil,
    finder = nil, -- 아래 make_finder() 로 채운다 (지운 뒤 같은 모양으로 다시 만든다)
  }
  local function make_entry(e)
    if e == add then
      return {
        value = add,
        display = function()
          if not pos then
            return '＋ 등록: (파일 창에서 열어야 담을 수 있습니다)'
          end
          local nm2 = add_name()
          local dup = ''
          for _, it in ipairs(items) do
            if it.kind == 'bookmark' and it.path == pos.path and it.bline == pos.line
                and it.name == vim.trim(nm2) then
              dup = '   (이미 있음)'
            end
          end
          return '＋ 등록: ' .. (nm2 ~= '' and nm2 or '(프롬프트에 이름을 치세요)')
            .. '   ← ' .. vim.fn.fnamemodify(pos.path, ':t') .. ':' .. pos.line .. dup
        end,
        ordinal = '',
        -- 미리보기에 '여기가 담긴다'를 보여 준다. 이것이 없으면 grep 미리보기가
        -- entry.value(표)를 경로로 읽으려다 오류를 내고, 창을 열자마자
        -- 'Press ENTER' 로 멈췄다(tmux 화면 실측 - 이 줄이 처음부터 골라져
        -- 있어서).
        filename = pos and pos.path or nil,
        lnum = pos and pos.line or nil,
      }
    end
    return {
      value = e,
      display = label(e),
      ordinal = e.name .. ' ' .. e.short .. ' ' .. e.text,
      filename = e.path,
      lnum = e.lnum,
    }
  end
  local function make_finder()
    return t.finders.new_table({ results = results(), entry_maker = make_entry })
  end
  local function title()
    local b, m = 0, 0
    for _, e in ipairs(items) do
      if e.kind == 'bookmark' then b = b + 1 else m = m + 1 end
    end
    return ('북마크 %d · 마크 %d   <CR> 등록/가기   <Esc>d 지우기'):format(b, m)
  end
  opts.prompt_title = title()
  opts.finder = make_finder()
  t.pickers.new({}, vim.tbl_extend('force', opts, {
    sorter = sorter,
    previewer = (function()
      -- 담을 자리가 없는(파일 창이 아닌 곳에서 연) 등록 줄은 미리보기를 건너뛴다
      local pv = t.conf.grep_previewer({})
      local show = pv.preview
      pv.preview = function(self, entry, status, ...)
        if entry and entry.value == add and not pos then
          return
        end
        return show(self, entry, status, ...)
      end
      return pv
    end)(),
    attach_mappings = function(bufnr, map)
      -- 바쁨을 재기 시작한다 (pickerkeep.lua) - 창이 다 선 뒤에
      vim.schedule(function()
        if type(_G.vimide_picker_track) == 'function' then
          pcall(_G.vimide_picker_track, t.state.get_current_picker(bufnr))
        end
      end)
      -- 등록 줄에서 Ctrl+V / Ctrl+X / Ctrl+T 는 아무것도 하지 않는다 (열 파일이 없다 -
      -- 그대로 두면 파일 아닌 창에서 연 경우 E5108 로 죽었다)
      local function on_add()
        local e = t.state.get_selected_entry()
        return e ~= nil and e.value == add
      end
      for _, a2 in ipairs({ 'select_vertical', 'select_horizontal', 'select_tab' }) do
        if t.actions[a2] then
          t.actions[a2]:replace_if(on_add, function() end)
        end
      end
      t.actions.select_default:replace(function()
        -- 목록이 프롬프트를 따라오지 않았으면 따라온 뒤에 (pickerkeep.lua)
        local pk0 = t.state.get_current_picker(bufnr)
        if pk0 and picker_busy(pk0) and type(_G.vimide_picker_ready) == 'function' then
          _G.vimide_picker_ready(pk0, function()
            t.actions.select_default(bufnr)
          end)
          return
        end
        local entry = t.state.get_selected_entry()
        if entry and entry.value == add then
          -- 프롬프트는 그 자리에서 읽는다. get_current_line 은 입력보다 한 박자
          -- 늦어서, 이름을 치자마자 Enter 가 한 덩어리로 오면 심볼 이름이 담겼다.
          local pk = t.state.get_current_picker(bufnr)
          local typed = pk and vim.trim(pk:_get_prompt() or '') or ''
          local name = typed ~= '' and typed or sym
          if pos and vim.trim(name) == '' then
            vim.notify('북마크 이름을 프롬프트에 치세요', vim.log.levels.WARN)
            return
          end
          t.actions.close(bufnr)
          vim.schedule(function() register(pos, name) end)
          return
        end
        t.actions.close(bufnr)
        if entry then
          -- 프롬프트가 닫히며 insert 를 빠져나갈 때 커서가 한 칸 왼쪽으로
          -- 밀린다. 한 박자 뒤에 뛴다.
          vim.schedule(function() jump(entry.value) end)
        end
      end)
      -- 'd' 는 노멀 모드에서만. 입력 모드에도 걸면 검색창에 d 를 칠 때마다
      -- 지워진다 - 'drivers' 를 치려다 두 개를 잃는다.
      -- 지워도 창은 그대로 두고 목록만 다시 읽어 갈아 끼운다. 친 글자는 두고,
      -- 선택은 지운 자리 근처에 둔다 - 여러 개를 이어서 지울 수 있다.
      map('n', 'd', function()
        local picker = t.state.get_current_picker(bufnr)
        -- 목록을 갈아 끼우는 중에 온 d 는 버린다 - 그 사이의 선택은 방금 지운 줄이다
        -- (빨리 친 dd 가 둘을 지우거나, 없는 줄을 지우려 헛돌지 않게)
        if picker_busy(picker) then
          return
        end
        local entry = t.state.get_selected_entry()
        if not entry or entry.value == add then
          return
        end
        local e = entry.value
        if e.kind == 'bookmark' then
          if bm_remove(e) > 0 then
            vim.notify(("북마크 '%s' 를 지웠습니다"):format(e.name))
          else
            vim.notify(("북마크 '%s' 는 그새 없어졌습니다"):format(e.name), vim.log.levels.WARN)
          end
        else
          -- 버퍼 마크(a-z)는 그 버퍼에서 지워야 한다. 지금 창은 프롬프트라, 마크를
          -- 모아 온 원래 버퍼에서 지운다.
          pcall(api.nvim_buf_call, origin_buf, function()
            vim.cmd('delmarks ' .. e.name)
          end)
          vim.notify(("마크 '%s' 를 지웠습니다"):format(e.name))
        end
        if not picker then
          return
        end
        items = api.nvim_buf_call(origin_buf, collect)
        refresh_keep(picker, make_finder(), title())
      end)
      return true
    end,
  })):find()
end

api.nvim_create_user_command('VimIdeMarks', function() _G.vimide_marks() end,
  { desc = '찍어 둔 마크를 골라서 그 자리로' })
