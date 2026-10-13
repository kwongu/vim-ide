-- findreplace.lua - 이 파일 안에서 찾아 바꾸기 (Ctrl+h)
--
-- <C-h> 를 누르면 떠 있는 창이 뜬다. (,ch 는 명령행 쪽이다 - .vimrc 참고)
--
--   ╭─ 찾아 바꾸기 ──────────────────╮
--   │  Old   tsnd                    │
--   │  New   tsnd_test▊              │
--   ╰────────────────────────────────╯
--
-- Old 는 커서 밑 심볼로 채워 두지만 고칠 수 있다. 빈 곳에서 불렀으면 Old 가
-- 비어 있고 커서가 거기서 시작한다 - 찾을 말부터 직접 치면 된다.
-- Tab 으로 두 칸을 오간다.
--
-- 바꿀 말을 치고 Enter 를 누르면 어디를, 어떻게 바꿀지 고르는 창이 뜬다.
-- 줄마다 지금 규칙으로 몇 곳이 걸리는지 보이고, 규칙을 바꾸면 숫자도 바로 바뀐다.
--
--   ╭───── 'tsnd' → 'tsnd_test' · 부분 일치 · 대소문자 구분 ─────╮
--   │  a  파일 전체 모두 바꾸기                            314곳 │
--   │  o  파일 전체 하나씩 (y/n/a/q)                       314곳 │
--   │  e  커서부터 끝까지 모두 바꾸기                      120곳 │
--   │  E  커서부터 끝까지 하나씩 (y/n/a/q)                 120곳 │
--   │  w  [ ] 낱말만                                  켜면 167곳 │
--   │  i  [ ] 대소문자 무시                           켜면 376곳 │
--   │  q  취소                                                   │
--   ╰─────────── Enter 고르기 · w i 규칙 · Esc 취소 ─────────────╯
--
--   a / o 는 예전 그대로(파일 전체), e / E 는 커서부터 끝까지 - 큰 글자가 하나씩이다.
--   그 줄에서 Enter (또는 두 번 누르기) 도 같다.
--
-- 찾는 규칙 - 기본은 '같은 글자'
--   Old 를 글자 그대로(. * [ ] \ / & ~ 도 그냥 글자), 낱말 가운데 든 것까지,
--   대소문자를 가려 찾는다. 'ignorecase' / 'smartcase' 와는 상관없다.
--   예전 기본은 '낱말만'(\<old\>)이고 대소문자는 'ignorecase' 를 따랐다. 그래서
--   'tsnd' 를 바꾸면 함수 안의 지역 변수 tsnd 만 바뀌고 tsnd_init, g_tsnd_data,
--   tsnd_apu_... 는 그대로 남았으며 (실측 tsnd_main.c: 같은 글자 314곳 중 172곳),
--   그 172곳에는 대문자 TSND 5곳이 섞여 있었다 ('같은 글자를 찾아 바꾸는 게
--   아닌 것 같다'). 이제 314곳이 바뀌고 TSND 는 그대로다.
--   w 로 낱말만(struct 를 바꿀 때 structure 가 안 걸린다), i 로 대소문자 무시를
--   켜고 끈다. 낱말 경계는 Old 의 앞뒤 글자가 낱말 글자('iskeyword')일 때만 건다.
--
-- 커서부터 끝까지 (e, E)
--   Ctrl+h 를 누른 때의 커서 자리부터 파일 끝까지. 커서 줄에서는 커서 뒤에서
--   시작하는 것만 센다 (바이트 열로 - 커서 앞의 한글은 몇 칸이든 상관없다).
--   커서가 걸린 낱말 가운데 있으면 그 낱말부터다 - Old 가 커서 밑 심볼로
--   채워지는데 그것이 빠지면 이상하다. 그 아래 줄은 전부.
--
-- 하나씩 (o, E) 은 vim 의 :s///gc 그대로다 - y 바꾼다, n 건너뛴다, a 여기서부터
-- 전부, q 그만둔다. 무엇을 골라도 바꾸기는 한 번의 :s 라서 u 한 번에 통째로
-- 되돌아온다. 모두 바꾸기는 커서를 그 자리에 둔다.
-- 끝나면 바꾼 수와, 파일 전체에서 아직 안 바꾼 것(지금 규칙으로)을 알린다:
--   'tsnd' -> 'tsnd_test'  커서부터 120곳 바꿈 · 파일에 194곳 남음
-- 남은 수는 '원래 있던 것 - 바꾼 것' 이다. New 가 Old 를 품으면(tsnd -> tsnd_test)
-- 바꾼 뒤에 다시 세면 바꾼 것까지 다시 걸린다 - 예전에는 그래서 '0곳 바꿈'이 떴다.
--
-- 떠 있는 창은 스스로 닫힌다
--   예전 두 창은 제 키(Enter/Esc/q ...)로만 닫혔다. 그 창을 떠나면(다른 창을
--   마우스로 누르기, <C-w>w, 명령, 다른 플러그인이 연 창, 콜백 오류) 화면 가운데
--   (zindex 200)에 그대로 남았고, 그 상태로 Ctrl+h 를 다시 누르면 하나가 더 겹쳐
--   떴다. 이제
--     - 창을 떠나면 취소로 닫는다. 입력 모드와 자동완성(AutoComplPop)도 되돌린다.
--     - Ctrl+h 를 다시 누르면 떠 있던 것부터 닫는다 (그 창 안에서 눌렀으면 편집
--       창으로 돌아가 새로 시작한다).
--     - 콜백에서 오류가 나도 닫는다.
--     - 둘째 창은 :s 가 돌기 전에 닫는다 (하나씩의 y/n 물음 때도).
--   F1(단축키 도움말)만은 잠깐 다녀오는 곳이다 - 그 목록은 이 창을 숨겼다가 닫힐 때
--   되살려 이리로 돌아온다 (keyhelp.lua). 그 목록이 닫힌 뒤에 다시 본다.
--
-- 어디서든 <Esc> 는 취소다.
--
-- 옵션 (.vimrc)
--   g:vimide_replace_word        1 이면 처음부터 낱말만 (기본 0 - 예전 기본은 1)
--   g:vimide_replace_ignorecase  1 이면 처음부터 대소문자 무시 (기본 0)
--   g:vimide_replace_ctrl_h      0 이면 <C-h> 를 창 이동(:wincmd h)으로 둔다
--   :VimIdeReplace [old]         같은 것을 명령으로

if vim.g.loaded_vimide_findreplace then
  return
end
vim.g.loaded_vimide_findreplace = 1

if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local WARN = vim.log.levels.WARN

local function cfg(name, default)
  local v = vim.g['vimide_' .. name]
  if v == nil then
    return default
  end
  if v == false then
    return 0
  end
  return tonumber(v) or v
end

-- 화면 폭을 넘는 알림이 Press ENTER 를 띄우지 않게 fitmsg.lua 의 것을 쓴다 (없으면 그냥)
local function notify(msg, level)
  local f = _G.vimide_notify or vim.notify
  f(msg, level)
end

local function dw(s)
  return vim.fn.strdisplaywidth(s)
end

-- 화면 칸 n 을 넘으면 뒤를 … 로 자른다 (제목과 알림이 80 칸에 들게)
local function short(s, n)
  n = n or 16
  if dw(s) <= n then
    return s
  end
  local k = vim.fn.strchars(s)
  local out = s
  while k > 0 and dw(out) > n - 1 do
    k = k - 1
    out = vim.fn.strcharpart(s, 0, k)
  end
  return out .. '…'
end

local function close(win)
  if win and api.nvim_win_is_valid(win) then
    pcall(api.nvim_win_close, win, true)
  end
end

-- 떠 있는 창과, 그 버퍼를 실은 다른 창까지 닫는다. 떠 있는 창에서 :sp 를 하면 새 창(부동
-- 아님)이 같은 버퍼를 싣는다 - 떠 있는 창만 닫았더니 그 창이 고르는 창의 글을 단 채
-- 남았다 (실측). 마지막 창이면 못 닫는다 (pcall).
local function close_all(win, buf)
  close(win)
  if buf and api.nvim_buf_is_valid(buf) then
    for _, w in ipairs(vim.fn.win_findbuf(buf)) do
      close(w)
    end
  end
end

-- 입력 모드로 연 창을 닫은 뒤의 stopinsert 는 돌아간 창에서 <Esc> 처럼 커서를 한 칸
-- 왼쪽으로 민다 (쓸 때마다 밀렸다). 그 창의 커서를 지금(밀리기 전) 잡아 두고 입력 모드를
-- 나가는 그 순간(InsertLeave) 되돌린다 - askform.lua 의 vimide_leave_insert_keep_cursor
-- 와 같은 수다. 다만 남은 자동명령을 치우는 것은 vim.schedule 이 아니라 타이머로 한다:
-- 창을 떠나서 닫힐 때는 이 함수가 이미 vim.schedule 안에서 도는데, 그러면 vim.schedule
-- 로 건 치우기가 stopinsert 가 먹기 전에 같이 돌아서 되돌리기가 사라졌다 (실측: 입력
-- 창에서 다른 창을 마우스로 누르면 커서가 누른 자리보다 한 칸 왼쪽, <C-o><C-w>w 와
-- <C-o>:sp 도 같았다). stopinsert 는 그 박자 안에 먹으니 0.2 초면 넉넉하다.
local function leave_insert()
  if vim.fn.mode():sub(1, 1) ~= 'i' then
    vim.cmd('stopinsert')
    return
  end
  local cw = api.nvim_get_current_win()
  local cc = api.nvim_win_get_cursor(cw)
  local id = api.nvim_create_autocmd('InsertLeave', {
    once = true,
    callback = function()
      if api.nvim_get_current_win() == cw then
        pcall(api.nvim_win_set_cursor, cw, cc)
      end
    end,
  })
  vim.cmd('stopinsert')
  vim.defer_fn(function()
    pcall(api.nvim_del_autocmd, id)
  end, 200)
end

-- 자동완성을 잠깐 재운다.
--
-- 이 창에서는 두 글자만 치면 되는데 AutoComplPop 이 목록을 띄우고,
-- 그 상태의 <Tab>/<CR> 은 우리 매핑이 아니라 '후보 고르기'로 먹힌다.
-- 실측: Old 에 old_name 을 치고 <Tab> 을 눌렀더니 그 낱말이 통째로
-- 후보로 갈려 나갔다.
local function acp(on)
  if vim.fn.exists(':AcpEnable') == 2 then
    pcall(vim.cmd, on and 'AcpEnable' or 'AcpDisable')
  end
end

-- ---------------------------------------------------------------------------
-- 떠 있는 창과 그 뒷정리
-- ---------------------------------------------------------------------------

-- 지금 떠 있는 찾아 바꾸기 창. 한 번에 하나뿐이다 (둘째 창은 첫째 창을 닫은 뒤에 뜬다).
--   { win, buf, grp, origin, on_close, closed }
local live = nil

-- 창을 닫는다. 몇 번 불러도 된다 - 제 키, 창 떠나기, 오류, 다시 누른 Ctrl+h 가 다 이리로 온다.
local function drop(st)
  if not st or st.closed then
    return
  end
  st.closed = true
  if live == st then
    live = nil
  end
  if st.grp then
    pcall(api.nvim_del_augroup_by_id, st.grp)
  end
  -- 뒷정리(자동완성, 입력 모드)는 창이 정말 닫힌 뒤에 한다 - 아직 남아 있으면 그 창으로
  -- 돌아가 입력 모드를 이어 가기 때문이다
  local function after()
    if st.on_close then
      pcall(st.on_close)
    end
  end
  close_all(st.win, st.buf)
  if not api.nvim_win_is_valid(st.win) then
    after()
    return
  end
  local function again()
    close_all(st.win, st.buf)
    after()
  end
  if vim.fn.getcmdwintype() ~= '' then
    -- 명령줄 창(q:) 안에서는 다른 창을 닫을 수 없다 (E11). 그 창을 나간 뒤에 닫는다.
    -- 입력 창에서 <C-o>q: 로 갔다가 나오면 입력 창의 입력 모드로 돌아온다 - 뒷정리를 그때
    -- 해야 편집 창이 입력 모드로 남지 않는다 (실측)
    api.nvim_create_autocmd('CmdwinLeave', {
      once = true,
      callback = function()
        vim.schedule(again)
      end,
    })
  else
    -- 그 밖의 까닭(textlock 따위)으로 못 닫았으면 한 박자 뒤에 다시
    vim.schedule(again)
  end
end

local function drop_live()
  drop(live)
end

-- 콜백을 감싼다. 오류가 나도 창은 닫는다 - 안 그러면 화면 가운데에 남는다.
-- 알림은 한 줄로 (파일:줄: 오류). 스택까지 찍으면 여러 줄이 되어 Press ENTER 가 떴다
local function guarded(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      drop_live()
      local first = vim.split(tostring(err), '\n', { plain = true })[1]
      notify('찾아 바꾸기: ' .. first, vim.log.levels.ERROR)
    end
  end
end

-- 창을 떠나면 취소로 닫는다.
--
-- 떠나는 순간(WinLeave)에는 어디로 가는지 아직 모른다. 한 박자 뒤(vim.schedule)
-- 초점이 어디 있는지 보고 정한다 - 그 사이 돌아왔으면 그대로 둔다. 창이 닫혔거나
-- (WinClosed - :q, <C-w>o) 버퍼가 바뀌었으면(BufLeave/BufWipeout - :e, :b) 그 창도
-- 거둔다 (안 그러면 파일을 실은 부동 창이 남는다).
local function watch(st)
  st.grp = api.nvim_create_augroup('vimide_replace_float_' .. st.buf, { clear = true })
  local function check()
    if st.closed then
      return
    end
    if api.nvim_win_is_valid(st.win) and api.nvim_win_get_buf(st.win) == st.buf then
      if api.nvim_get_current_win() == st.win then
        return
      end
      -- F1 목록(keyhelp.lua)은 이 창을 숨겼다가 닫힐 때 되살리고 이리로 돌아온다.
      -- 그 목록이 닫힌 뒤(BufUnload)에 다시 본다 - 거기서 다른 탭(README)으로 갔으면 그때 닫는다
      local cb = api.nvim_get_current_buf()
      if vim.b[cb].vimide_keyhelp_prompt then
        api.nvim_create_autocmd('BufUnload', {
          group = st.grp,
          buffer = cb,
          once = true,
          callback = function()
            vim.schedule(check)
          end,
        })
        return
      end
    end
    drop(st)
  end
  local function later()
    vim.schedule(check)
  end
  api.nvim_create_autocmd({ 'WinLeave', 'BufLeave', 'BufWipeout' },
    { group = st.grp, buffer = st.buf, callback = later })
  api.nvim_create_autocmd('WinClosed', { group = st.grp, pattern = tostring(st.win), callback = later })
end

-- 떠 있는 창 하나를 열고 들어간다. 지울 때 창과 버퍼를 같이 거둔다.
-- 못 열었으면 nil.
local function float(lines, opts)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  -- delimitMate 이 ( [ { " ' 짝 매핑을 걸지 않게 (창을 열기 전에). 걸리면 New 칸에
  -- 친 'cnt[' 가 'cnt[]' 로 바뀌었다 (QA). 뒤이은 filetype 설정이 FileType 으로
  -- setup 을 다시 불러도 이 변수가 있으면 그냥 돌아간다.
  vim.b[buf].loaded_delimitMate = 1
  local width = math.min(opts.width or 60, math.max(20, vim.o.columns - 4))
  local height = #lines
  -- enter=false 로 열고 따로 들어간다 (askform.lua 와 같은 까닭 - 지금 버퍼의
  -- BufLeave 가 새 창 안에서 돌아 그 창째 닫히는 일이 있었다)
  local ok, win = pcall(api.nvim_open_win, buf, false, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 2),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = 'minimal',
    border = 'rounded',
    title = opts.title,
    title_pos = 'center',
    footer = opts.footer,
    footer_pos = opts.footer and 'center' or nil,
    zindex = 200,
  })
  if ok then
    pcall(api.nvim_set_current_win, win)
  end
  if not ok or not api.nvim_win_is_valid(win) or api.nvim_get_current_win() ~= win then
    if ok then
      close(win)
    end
    if api.nvim_buf_is_valid(buf) then
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
    notify('찾아 바꾸기 창을 열지 못했습니다 - 다시 눌러 주세요', WARN)
    return nil
  end
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder'
  vim.wo[win].cursorline = opts.cursorline and true or false
  return buf, win
end

-- ---------------------------------------------------------------------------
-- 찾기: 패턴과 세기
-- ---------------------------------------------------------------------------

-- 찾는 규칙 (처음 값은 .vimrc 의 옵션)
local function start_rules()
  return {
    word = cfg('replace_word', 0) ~= 0,
    icase = cfg('replace_ignorecase', 0) ~= 0,
  }
end

local function rules_text(r)
  return (r.word and '낱말만' or '부분 일치') .. ' · ' .. (r.icase and '대소문자 무시' or '대소문자 구분')
end

-- ':s' 의 찾을 쪽. \V(아주 곧이곧대로) 라서 Old 에 든 . * [ ] ~ 가 안 튄다 - 남는 특수
-- 글자는 \ 와 구분자 / 뿐이다. \C / \c 는 'ignorecase' 와 'smartcase' 를 이긴다.
-- 낱말만이면 Old 의 앞뒤 글자가 낱말 글자('iskeyword', 이 버퍼의 것)일 때만 경계를
-- 건다 - 'a.b' 를 낱말만으로 찾으면 \<a.b\> 이고 '(x' 면 \<(x 가 아니라 (x\> 다.
-- from = { row, col } 이면 그 줄은 col(0 부터 센 바이트) 뒤에서 시작하는 것만,
-- 아랫줄은 전부. row 가 0 이면 줄 하나(문자열)에 쓰는 꼴 - 문자열에는 줄 번호가 없다.
-- 이 버퍼 안에서(nvim_buf_call) 부른다.
local function search_pat(old, r, from)
  local body = vim.fn.escape(old, '\\/')
  if r.word then
    if vim.fn.match(vim.fn.matchstr(old, '^.'), '\\k') == 0 then
      body = '\\<' .. body
    end
    if vim.fn.match(vim.fn.matchstr(old, '.$'), '\\k') == 0 then
      body = body .. '\\>'
    end
  end
  local p = (r.icase and '\\c' or '\\C') .. '\\V'
  if from and from.col > 0 then
    if from.row > 0 then
      p = p .. ('\\%%(\\%%>%dl\\|\\%%>%dc\\)'):format(from.row, from.col)
    else
      p = p .. ('\\%%>%dc'):format(from.col)
    end
  end
  return p .. body
end

-- ':s' 의 바꿀 쪽. & 와 ~ 는 '찾은 것 전체', '앞의 바꿀 말' 이라 그대로 두면 안 된다.
local function repl_text(new)
  return vim.fn.escape(new, '\\/&~')
end

-- 한 줄에서 pat 이 걸리는 자리들 { {s, e}, ... } (0 부터 센 바이트, e 는 빼고).
-- :s 와 같은 차례로 - 앞 자리의 끝에서 다음을 찾는다 (겹치지 않게).
-- matchstrpos 에 {count}(1)를 같이 준다. start 만 주면 줄을 start 에서 잘라 놓고
-- 찾아서 \< 와 \%>c 가 어긋났다 - 'xtsnd tsnd' 에서 \<tsnd 가 1 에 걸렸고, 커서 줄의
-- \%>9c 가 셋째 자리를 놓쳐 '커서부터' 가 하나 모자랐다 (실측). {count} 가 있으면
-- 줄은 그대로 두고 start 앞의 것만 건너뛴다. vim.regex 의 match_line 도 start 에서
-- 줄을 잘라 쓸 수 없었다.
local function spans_in(line, pat)
  local out, start = {}, 0
  while start <= #line do
    local m = vim.fn.matchstrpos(line, pat, start, 1)
    local s, e = m[2], m[3]
    if s < 0 then
      break
    end
    out[#out + 1] = { s, e }
    start = e > s and e or e + 1
  end
  return out
end

-- matchstrpos 를 부를 만한 줄인가 (빠른 걸러내기 - 큰 파일에서 줄마다 부르지 않게).
-- 대소문자 무시는 Lua 가 ASCII 만 접을 줄 안다. ASCII 밖의 글자가 든 줄은 vim 에 맡긴다.
local function quick_test(old, r)
  if not r.icase then
    return function(line)
      return line:find(old, 1, true) ~= nil
    end
  end
  if old:find('[\128-\255]') then
    return function()
      return true
    end
  end
  local low = old:lower()
  return function(line)
    return line:find('[\128-\255]') ~= nil or line:lower():find(low, 1, true) ~= nil
  end
end

-- 지금 규칙으로 센다. :s///gn 의 알림 글('N matches on M lines')을 읽던 것을 그만뒀다 -
-- 'lazyredraw' 가 켜져 있고 키가 미리 쌓여 있으면 그 알림이 아예 안 나와 0 으로 셌다.
--   all   파일 전체에서 걸리는 수
--   tail  커서부터 끝까지 걸리는 수
--   from  커서 줄에서 셀 첫 바이트 (커서가 걸린 자리 가운데 있으면 그 자리의 머리)
--   spans spans 가 'all' / 'tail' 이면 그 범위의 줄 번호 -> 자리들 (같은 길이로 바꿀 때
--         몇 곳이 바뀌었는지 세는 데 쓴다)
-- lines 를 주면 그것을 센다 (한 번에 여러 규칙으로 셀 때 줄을 한 번만 읽게 - 30 만 줄에서
-- 고르는 창이 뜨는 데 0.5 초쯤이었다)
local function scan(o, old, r, spans, lines)
  return api.nvim_buf_call(o.buf, function()
    local pat = search_pat(old, r)
    local test = quick_test(old, r)
    local res = { all = 0, tail = 0, from = o.col, spans = spans and {} or nil }
    for i, line in ipairs(lines or api.nvim_buf_get_lines(o.buf, 0, -1, false)) do
      if test(line) then
        local sp = spans_in(line, pat)
        res.all = res.all + #sp
        if spans == 'all' and #sp > 0 then
          res.spans[i] = sp
        end
        if i > o.row then
          res.tail = res.tail + #sp
          if spans == 'tail' and #sp > 0 then
            res.spans[i] = sp
          end
        elseif i == o.row and #sp > 0 then
          for _, s in ipairs(sp) do
            if s[1] <= o.col and o.col < s[2] then
              res.from = s[1]
              break
            end
          end
          local tsp = sp
          if res.from > 0 then
            tsp = spans_in(line, search_pat(old, r, { row = 0, col = res.from }))
          end
          res.tail = res.tail + #tsp
          if spans == 'tail' and #tsp > 0 then
            res.spans[i] = tsp
          end
        end
      end
    end
    return res
  end)
end

local function origin_ok(o)
  return api.nvim_win_is_valid(o.win) and api.nvim_buf_is_valid(o.buf)
    and api.nvim_win_get_buf(o.win) == o.buf
end

local function buf_bytes(buf)
  return api.nvim_buf_get_offset(buf, api.nvim_buf_line_count(buf))
end

-- ---------------------------------------------------------------------------
-- 바꾸기
-- ---------------------------------------------------------------------------

-- tail: 커서부터 끝까지, ask: 하나씩 (:s///gc)
local function run(o, old, new, r, tail, ask)
  if not origin_ok(o) then
    notify('바꾸려던 창이 없어졌습니다', WARN)
    return
  end
  if api.nvim_get_current_win() ~= o.win then
    api.nvim_set_current_win(o.win)
  end
  -- 다시 센다 - 창이 떠 있는 사이 파일이 바뀌었을 수도 있다
  local same_len = #new == #old
  local c = scan(o, old, r, same_len and (tail and 'tail' or 'all') or nil)
  local want = tail and c.tail or c.all
  if want == 0 then
    notify(("'%s' 를 %s 찾지 못했습니다"):format(short(old), tail and '커서 뒤에서' or '이 파일에서'), WARN)
    return
  end
  local pat = api.nvim_buf_call(o.buf, function()
    return search_pat(old, r, tail and { row = o.row, col = c.from } or nil)
  end)
  local flags = (vim.o.gdefault and '' or 'g') .. (ask and 'c' or '')
  local cmd = ('keeppatterns %ss/%s/%s/%s'):format(tail and (o.row .. ',$') or '%', pat, repl_text(new), flags)
  local before = buf_bytes(o.buf)
  local view, report
  if ask then
    -- :s 가 끝에 내는 'N substitutions on M lines' 를 재운다 - 바로 뒤 우리 알림과
    -- 두 줄이 되면 Press ENTER 가 떴다. 물음(replace with ...?)은 그대로 나온다
    report = vim.o.report
    vim.o.report = 999999999
    api.nvim_echo({ { '바꿀까요?  y 예  n 아니오  a 여기서부터 전부  q 그만', 'Question' } }, false, {})
  else
    -- 모두 바꾸기는 커서를 그 자리에 둔다 (:s 는 마지막으로 바꾼 줄로 간다)
    view = vim.fn.winsaveview()
    cmd = 'silent ' .. cmd
  end
  local ok, err = pcall(vim.cmd, cmd)
  if report then
    vim.o.report = report
    -- 물음 줄은 길면(긴 New, 80 칸) 두 줄로 감긴다. 그대로 알림을 더하면 Press ENTER 가
    -- 떴다 (실측). :redraw 는 메시지 칸을 비우고 '기다리기'도 거둔다
    pcall(vim.cmd, 'redraw')
  end
  if view then
    pcall(vim.fn.winrestview, view)
  end
  -- 몇 곳이 바뀌었나. 하나씩이면 :s 는 수를 돌려주지 않는다.
  --   길이가 다르면 파일 크기의 차이 / 한 곳의 차이 (Old 와 같은 글자만 걸리므로 정확하다)
  --   길이가 같으면 자리가 그대로라, 바꾸기 전의 자리마다 지금 New 가 있는지 본다
  local done = 0
  if not same_len then
    done = math.floor((buf_bytes(o.buf) - before) / (#new - #old) + 0.5)
  else
    for lnum, sp in pairs(c.spans) do
      local l = api.nvim_buf_get_lines(o.buf, lnum - 1, lnum, false)[1] or ''
      for _, s in ipairs(sp) do
        if l:sub(s[1] + 1, s[2]) == new then
          done = done + 1
        end
      end
    end
  end
  done = math.max(0, math.min(done, want))
  if not ok then
    local e = tostring(err)
    -- 사용자가 <C-c> 로 그만둔 것은 잘못이 아니다. nvim 이 내는 글은 'Keyboard
    -- interrupt' (소문자 i) 라서 대소문자 없이 본다 - 'Interrupt' 로만 찾았더니 하나씩의
    -- 물음에서 <C-c> 를 누를 때마다 '바꾸기 실패: ... Keyboard interrupt' 가 떴다
    if not e:lower():find('interrupt', 1, true) then
      notify(("'%s' 바꾸기 실패: %s"):format(short(old), (e:gsub('^.-Vim%(%a+%):', ''))), WARN)
      if done == 0 then
        return
      end
    end
  end
  -- 남은 것 = 원래 있던 것 - 바꾼 것 (파일 전체, 지금 규칙). 바꾼 뒤에 다시 세지 않는다:
  -- New 가 Old 를 품으면(tsnd -> tsnd_test) 바꾼 자리가 다시 걸린다.
  local left = c.all - done
  local what = done > 0 and ('%s%d곳 바꿈'):format(tail and '커서부터 ' or '', done) or '바꾼 곳 없음'
  if left > 0 then
    what = what .. (' · 파일에 %d곳 남음'):format(left)
  end
  -- 한 줄에 들게 Old / New 를 자른다. 화면 폭에서 12 칸(showcmd·ruler 자리)을 뺀 데까지 -
  -- 거기를 넘으면 fitmsg.lua 가 가운데를 잘라 '커…부터' 처럼 됐다 (80 칸 실측)
  local cap = math.max(6, math.floor((vim.o.columns - 12 - dw(what) - 10) / 2))
  notify(("'%s' -> '%s'  %s"):format(short(old, cap), short(new, cap), what))
end

-- 2단계: 어디를(파일 전체 / 커서부터 끝까지), 어떻게(모두 / 하나씩) 바꿀까
local ROWS = {
  { key = 'a', what = '파일 전체 모두 바꾸기', tail = false, ask = false },
  { key = 'o', what = '파일 전체 하나씩 (y/n/a/q)', tail = false, ask = true },
  { key = 'e', what = '커서부터 끝까지 모두 바꾸기', tail = true, ask = false },
  { key = 'E', what = '커서부터 끝까지 하나씩 (y/n/a/q)', tail = true, ask = true },
  { key = 'w', what = '낱말만', flip = 'word' },
  { key = 'i', what = '대소문자 무시', flip = 'icase' },
  { key = 'q', what = '취소', quit = true },
}

local function ask_how(o, old, new)
  if not origin_ok(o) then
    notify('바꾸려던 창이 없어졌습니다', WARN)
    return
  end
  local r = start_rules()
  local c = scan(o, old, r)
  if c.all == 0 then
    -- 지금 규칙으로는 없어도 규칙을 넓히면 있을 수 있다 (대문자로 쓴 매크로 ...).
    -- 가장 넓은 규칙으로도 없을 때만 창 없이 끝낸다
    local loose = scan(o, old, { word = false, icase = true })
    if loose.all == 0 then
      notify(("'%s' 를 이 파일에서 찾지 못했습니다"):format(short(old)), WARN)
      return
    end
  end

  -- 줄 글과 제목. 숫자는 지금 규칙으로, w / i 줄은 그것을 바꾸면 몇 곳이 되는지
  local function build()
    local all_lines = api.nvim_buf_get_lines(o.buf, 0, -1, false)
    c = scan(o, old, r, nil, all_lines)
    local fw = scan(o, old, { word = not r.word, icase = r.icase }, nil, all_lines).all
    local fi = scan(o, old, { word = r.word, icase = not r.icase }, nil, all_lines).all
    local left, right = {}, {}
    for i, row in ipairs(ROWS) do
      if row.flip then
        local on = r[row.flip]
        left[i] = ('  %s  [%s] %s'):format(row.key, on and 'x' or ' ', row.what)
        right[i] = ('%s %d곳'):format(on and '끄면' or '켜면', row.flip == 'word' and fw or fi)
      elseif row.quit then
        left[i], right[i] = ('  %s  %s'):format(row.key, row.what), ''
      else
        left[i] = ('  %s  %s'):format(row.key, row.what)
        right[i] = ('%d곳'):format(row.tail and c.tail or c.all)
      end
    end
    local title = (" '%s' → '%s' · %s "):format(short(old, 14), short(new, 14), rules_text(r))
    local width = math.max(56, dw(title) + 6)
    for i = 1, #ROWS do
      width = math.max(width, dw(left[i]) + dw(right[i]) + 4)
    end
    width = math.min(width, math.max(20, vim.o.columns - 4))
    local lines = {}
    for i = 1, #ROWS do
      local pad = math.max(1, width - dw(left[i]) - dw(right[i]) - 1)
      lines[i] = left[i] .. (' '):rep(pad) .. right[i]
    end
    return lines, title, width
  end

  local lines, title, width = build()
  local buf, win = float(lines, {
    width = width,
    cursorline = true,
    title = title,
    footer = ' Enter 고르기 · w i 규칙 · Esc 취소 ',
  })
  if not buf then
    return
  end
  vim.bo[buf].filetype = 'vimide-replace'
  -- 고르는 창이다 - x, dd 따위로 글이 지워지지 않게
  vim.bo[buf].modifiable = false
  local st = { win = win, buf = buf, origin = o }
  live = st
  watch(st)

  local function redraw()
    local l, t, w = build()
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, l)
    vim.bo[buf].modifiable = false
    pcall(api.nvim_win_set_config, win, {
      relative = 'editor',
      width = w,
      height = #l,
      row = math.max(0, math.floor((vim.o.lines - #l) / 2) - 2),
      col = math.max(0, math.floor((vim.o.columns - w) / 2)),
      title = t,
      title_pos = 'center',
    })
  end

  local function act(row)
    if st.closed or not row then
      return
    end
    if row.quit then
      drop(st)
    elseif row.flip then
      r[row.flip] = not r[row.flip]
      redraw()
    else
      local n = row.tail and c.tail or c.all
      if n == 0 then
        api.nvim_echo({ { ('지금 규칙(%s)으로는 %s 바꿀 곳이 없습니다'):format(rules_text(r),
          row.tail and '커서 뒤에' or '이 파일에'), 'WarningMsg' } }, false, {})
        return
      end
      -- :s 가 돌기 전에 닫는다 - 하나씩의 y/n 물음이 이 창 밑에 깔리지 않게
      drop(st)
      vim.schedule(guarded(function()
        run(o, old, new, { word = r.word, icase = r.icase }, row.tail, row.ask)
      end))
    end
  end
  local function here()
    if not api.nvim_win_is_valid(win) then
      return nil
    end
    return ROWS[api.nvim_win_get_cursor(win)[1]]
  end
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, guarded(fn), { buffer = buf, nowait = true, desc = desc })
  end
  map('<CR>', function() act(here()) end, '이 줄로 (찾아 바꾸기)')
  map('<2-LeftMouse>', function() act(here()) end, '이 줄로 (찾아 바꾸기)')
  for _, row in ipairs(ROWS) do
    map(row.key, function() act(row) end, row.what .. ' (찾아 바꾸기)')
  end
  for _, k in ipairs({ '<Esc>', '<C-c>' }) do
    map(k, function() drop(st) end, '취소 (찾아 바꾸기)')
  end
end

-- 1단계: Old 와 New 를 받는다
--
-- 'Old' / 'New' 라는 글자는 버퍼에 넣지 않는다.
--
-- 예전에는 '  Old   이름' 을 통째로 한 줄로 넣었다. 그러면 지우다가 이름표까지
-- 지워진다 - 백스페이스 몇 번이면 'Old' 가 사라지고, 그 줄이 무엇을 담는
-- 칸인지 알 수 없게 된다. 이제 이름표는 extmark 의 inline 가상 텍스트다.
-- 화면에는 같은 자리에 보이지만 버퍼 글자가 아니라서 지울 수가 없고, 커서는
-- 자연히 그 오른쪽(칸의 시작)에 선다.
--
-- 그래서 줄의 내용이 곧 값이다 - 뜯어낼 것이 없다.
local function ask_new(o, old)
  local LAB = { '  Old   ', '  New   ' }
  local buf, win = float({ old, '' }, {
    width = math.max(46, dw(old) + 22),
    title = ' 찾아 바꾸기 ',
    footer = ' Tab 칸 이동 · Enter 다음 · Esc 취소 ',
  })
  if not buf then
    return
  end
  vim.bo[buf].filetype = 'vimide-replace'
  vim.bo[buf].complete = ''
  acp(false)
  local st = { win = win, buf = buf, origin = o }
  -- 어떻게 닫히든(Enter, Esc, 창 떠나기, 오류) 자동완성을 다시 켜고, 아직 입력 모드면
  -- 끝낸다 - 커서는 밀지 않고. 프롬프트(telescope)와 터미널은 그쪽이 입력 모드를
  -- 쓰는 곳이라 그대로 둔다 (입력 중에 마우스로 그런 창을 눌렀을 때)
  st.on_close = function()
    acp(true)
    if api.nvim_get_mode().mode:sub(1, 1) == 'i'
        and vim.bo.buftype ~= 'prompt' and vim.bo.buftype ~= 'terminal' then
      leave_insert()
    end
  end
  live = st
  watch(st)

  local NS = api.nvim_create_namespace('vimide_replace_labels')
  for i, lab in ipairs(LAB) do
    pcall(api.nvim_buf_set_extmark, buf, NS, i - 1, 0, {
      virt_text = { { lab, 'Question' } },
      virt_text_pos = 'inline',
      right_gravity = false, -- 앞에 글자를 넣어도 이름표는 맨 앞에 남는다
    })
  end

  local function goto_line(n)
    local l = api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ''
    pcall(api.nvim_win_set_cursor, win, { n, #l })
    vim.cmd('startinsert!')
  end
  goto_line(old == '' and 1 or 2)

  local function field(n)
    local l = api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ''
    return (l:gsub('^%s+', ''):gsub('%s+$', ''))
  end
  -- 칸 수와 줄 수가 어긋났으면(어떻게든 줄이 합쳐지거나 늘었으면) 조용히 멈추지
  -- 말고 닫으며 알린다 - 다시 열면 된다 (askform.lua 와 같다)
  local function broken()
    if api.nvim_buf_line_count(buf) ~= 2 then
      drop(st)
      notify('입력 칸이 흐트러져 닫았습니다 - 다시 열어 주세요', WARN)
      return true
    end
    return false
  end
  local function done()
    if st.closed or broken() then
      return
    end
    -- 아직 바꿀 말을 안 썼으면 Enter 는 'New 로 넘어가기'다
    if api.nvim_win_get_cursor(win)[1] == 1 and field(2) == '' then
      goto_line(2)
      return
    end
    local o_, n_ = field(1), field(2)
    drop(st)
    if o_ == '' then
      notify('찾을 말이 비어 있습니다', WARN)
      return
    end
    if n_ == '' then
      notify('바꿀 말이 비어 있습니다', WARN)
      return
    end
    if n_ == o_ then
      notify('같은 말입니다', WARN)
      return
    end
    vim.schedule(guarded(function()
      ask_how(o, o_, n_)
    end))
  end
  local function cancel()
    drop(st)
  end
  local function other()
    if st.closed or broken() then
      return
    end
    goto_line(api.nvim_win_get_cursor(win)[1] == 1 and 2 or 1)
  end
  -- desc: F1(단축키 도움말)에 '(Lua 함수)' 대신 뜻이 보이게
  for _, m in ipairs({ 'n', 'i' }) do
    vim.keymap.set(m, '<CR>', guarded(done), { buffer = buf, nowait = true, desc = '다음 칸 / 고르는 창으로 (찾아 바꾸기)' })
    vim.keymap.set(m, '<Tab>', guarded(other), { buffer = buf, nowait = true, desc = 'Old ↔ New 칸 (찾아 바꾸기)' })
    vim.keymap.set(m, '<S-Tab>', guarded(other), { buffer = buf, nowait = true, desc = 'Old ↔ New 칸 (찾아 바꾸기)' })
    vim.keymap.set(m, '<Esc>', guarded(cancel), { buffer = buf, nowait = true, desc = '취소 (찾아 바꾸기)' })
    vim.keymap.set(m, '<C-c>', guarded(cancel), { buffer = buf, nowait = true, desc = '취소 (찾아 바꾸기)' })
  end
  -- 칸은 둘 뿐이다. 줄을 늘리거나 합치는 키는 막는다.
  --
  -- 특히 <BS>: 칸 맨 앞에서 한 번 더 누르면 vim 은 윗줄과 합친다
  -- ('backspace' 에 eol 이 있으면). 그러면 New 칸이 Old 줄로 끌려 올라가고
  -- 이름표 둘이 한 줄에 겹친다(실측: 백스페이스 스무 번에 그렇게 됐다).
  -- <C-h>(입력 모드에서는 백스페이스), <C-u>, <C-w> 도 칸 머리에서는 줄바꿈을
  -- 지웠다 (askform.lua 의 QA). 칸 맨 앞에서는 아무 일도 하지 않는다.
  -- expr 매핑은 돌려준 글자의 <BS> 를 스스로 키로 바꾼다(replace_keycodes).
  -- 여기서 미리 nvim_replace_termcodes 를 거치면 두 번 바뀌어 '<80>kb' 가
  -- 글자로 들어간다(실측). 문자열 그대로 돌려준다.
  for _, k in ipairs({ '<BS>', '<C-h>', '<C-u>', '<C-w>' }) do
    vim.keymap.set('i', k, function()
      local ok, c = pcall(api.nvim_win_get_cursor, win)
      return (not ok or c[2] == 0) and '' or k
    end, { buffer = buf, expr = true, replace_keycodes = true, nowait = true })
  end
  -- <Del> 은 반대쪽이다. 줄 끝에서 누르면 아랫줄을 끌어올린다.
  vim.keymap.set('i', '<Del>', function()
    local ok, c = pcall(api.nvim_win_get_cursor, win)
    if not ok then
      return ''
    end
    local l = api.nvim_buf_get_lines(buf, c[1] - 1, c[1], false)[1] or ''
    return c[2] >= #l and '' or '<Del>'
  end, { buffer = buf, expr = true, replace_keycodes = true, nowait = true })
  for _, k in ipairs({ 'o', 'O', 'dd', 'J', 'gJ' }) do
    vim.keymap.set('n', k, '<Nop>', { buffer = buf, nowait = true })
  end
end

local function start(old)
  -- 떠 있던 찾아 바꾸기 창부터 닫는다. 그 창 안에서 Ctrl+h 를 눌렀으면 그 창을
  -- 연 편집 창으로 돌아가서 새로 시작한다 (예전에는 '여기서는 바꿀 수 없습니다'만
  -- 뜨고 창은 그대로였다. 밖에서 누르면 하나가 더 겹쳐 떴다)
  if live then
    local st = live
    local inside = api.nvim_get_current_win() == st.win
    drop(st)
    if inside and st.origin and api.nvim_win_is_valid(st.origin.win) then
      pcall(api.nvim_set_current_win, st.origin.win)
    end
  end
  if vim.bo.buftype ~= '' then
    notify('여기서는 바꿀 수 없습니다 (편집 창에서 쓰세요)', WARN)
    return
  end
  if vim.bo.modifiable == false or vim.bo.readonly then
    notify('이 파일은 고칠 수 없습니다', WARN)
    return
  end
  -- '커서부터 끝까지' 의 기준. 창이 뜨기 전에 잡아 둔다
  local cur = api.nvim_win_get_cursor(0)
  local o = {
    win = api.nvim_get_current_win(),
    buf = api.nvim_get_current_buf(),
    row = cur[1],
    col = cur[2],
  }
  -- 빈 곳에서 불러도 창은 뜬다. Old 가 비어 있고 거기서부터 친다.
  old = (old and old ~= '') and old or vim.fn.expand('<cword>')
  ask_new(o, old or '')
end

-- old 가 비었으면 커서 밑 심볼 (.vimrc 의 <C-h> 는 블록으로 고른 글자만 넘긴다 -
-- <cword> 는 떠 있던 창을 닫고 돌아간 편집 창에서 읽어야 하니 여기서)
function _G.vimide_replace(old)
  guarded(start)(old)
end

api.nvim_create_user_command('VimIdeReplace', function(a) _G.vimide_replace(a.args) end,
  { nargs = '?', desc = '이 파일에서 찾아 바꾼다 (Old 는 커서 밑 심볼)' })
