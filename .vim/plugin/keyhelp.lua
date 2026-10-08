-- keyhelp.lua - F1: vim-ide 의 단축키 전부를 텔레스코프 창 하나로 (:VimIdeKeys)
--
-- 키를 하나 더할 때마다 도움말을 따로 고쳐 적는 방식은 언젠가 어긋난다. 그래서
-- 목록을 따로 두지 않고, F1 을 누를 때마다 '이미 있는 것'에서 모은다.
--
-- 무엇을 모으나
--   1) README.md
--      - '## Usage (shortcut)' 의 첫 ``` 블록. 0 열에서 'Key: 설명' 으로 시작하는
--        줄이 항목이고, 들여 쓴 줄이 그 항목에 이어진다. 'A / B', 'A, B',
--        'A or B', 'A (or B)' 는 키 여럿, '\fm: ...    \fS: ...' 처럼 한 줄에
--        여럿이면 나눈다. 키로 시작하지 않는 문단(설명)도 한 항목으로 넣는다 -
--        키 칸은 비지만 찾을 수는 있다.
--      - 다른 절의 키 표 '| `key` | 뜻 |'. 머리줄 첫 칸이 비었거나 'in the ...'
--        인 표만 본다 - 측정 표, '고친 것' 표, 변수 표는 키 표가 아니다. 키 앞의
--        횟수('1<C-r>', 'N<C-r>')는 보이기만 하고 키(<C-R>)로 읽는다.
--      - 다른 절의 ``` 블록 중 'Key: 설명' 줄이 셋 이상인 것 (패널 안의 키).
--      - 키 표가 아닌 표는 항목이 아니다. 키 줄이 그 절을 기울인 제목으로
--        가리키면('see *Views* below') 그 표와 바로 뒤의 목록을 그 줄의 찾기 글과
--        미리보기에 붙인다 (DirDiff 의 보기 이름과 id 로 트리의 f 가 찾인다).
--   2) 지금 걸린 매핑 (nvim_get_keymap: n x s o i c t, 전역). <Plug>/<SNR> 은 뺀다.
--      F1 을 누른 창이 특수 창(트리, 패널, quickfix, telescope 프롬프트 ...)이면
--      그 버퍼의 매핑도 맨 앞에 - 그 창에서 무슨 키가 먹는지가 그때 제일 궁금한
--      것이다. 그 줄의 '이 창 · ' 뒤는 filetype(읽기 어려운 것은 WIN_NAME 의 이름),
--      없으면 버퍼 이름, 그것도 없으면 부동 창의 제목. 키 표가 없는 창(DirDiff 의
--      보기 메뉴)은 그 창을 다루는 절의 표(보기 이름과 id)를 그 줄들에 붙인다.
--      보통 파일 버퍼면 그 버퍼에만 걸린 매핑(ftplugin, LSP ...)도 넣는다.
--   3) 명령 (nvim_get_commands + 그 버퍼의 -buffer 명령, 만든 파일로 가린다):
--      vim-ide 의 것과 그 버퍼의 것은 늘, 플러그인과 nvim 의 것은
--      g:vimide_keyhelp_others 가 켜져 있을 때 (매핑과 같은 규칙).
--   찾기는 README 항목의 본문 전체로 한다 (화면의 설명 칸은 첫 문장). 본문에
--   나오는 키(`w`, Ctrl+x ...)로 쳐도 그 항목이 위로 온다. 키는 vim 표기로도
--   README 표기로도, 대소문자 없이 친다: '<C-]>', 'Ctrl+]', 'ctrl+]' 이 같고,
--   'Shift+Tab', 'Ctrl+r', 'Space' 로 vim 표기 줄(<S-Tab>, <C-R>, <Space>)이
--   나온다. 크기만 다른 두 키(]q 와 ]Q)는 친 그대로인 것이 위. 키가 맞은
--   줄끼리는 F1 을 누른 창의 것이 위.
--
-- 겹치면 하나로 (README 글이 이긴다)
--   README 의 키가 실제로 걸려 있으면 한 항목이다. 모드 칸이 그 매핑의 모드
--   (n, x, nvo ...)로 차고 - 비어 있으면 전역 매핑이 아니라는 뜻이다 - 미리보기
--   에 실제 rhs 와 정의한 파일:줄이 같이 뜬다. README 가 낡았으면 거기서 보인다.
--   Usage 목록만 전역 매핑과 맞춘다. 다른 절의 표는 대개 그 창 안의 키라
--   (neo-tree 의 K, DirDiff 의 <C-n>), 같은 글자의 전역 매핑(K = 창 높이)과
--   묶으면 거짓말이 된다. 다른 절에서는 리더 키, F 키, Ctrl-W, ',' 키, 명령만 묶는다.
--   하나 더: DirDiff 가 비교 창에서만 쓰려고 감싼 전역 키(<C-r> <C-l> ...)는
--   DirDiff 의 'in the edit windows' 표와 묶고(그 줄의 미리보기에는 감싼 매핑만),
--   미리보기에 '그 탭의 비교 창에서만' 과 그 밖에서 하는 일(감싸기 전의 매핑 -
--   <C-l> 이면 .vimrc 의 :wincmd l - 이나 nvim 기본)을 적는다 (SCOPED).
--   버퍼에만 걸린 매핑이 전역 매핑과 모드가 하나도 겹치지 않으면 다른 매핑이라
--   묶지 않는다 (delimitMate 의 insert <C-H> 는 Ctrl+h 찾아 바꾸기가 아니다).
--   README 에 없는 매핑과 명령도 나온다 (desc 가 없으면 rhs).
--
-- 캐시
--   README 를 나눈 결과와 미리보기·보기 창에 쓰는 파일 줄을 기억한다. 열쇠는
--   파일의 mtime(나노초까지), 크기, inode 라, README 에 한 줄 적으면 다시 시작하지
--   않아도 다음 F1 에 나온다. 매핑과 명령은 늘 지금 것을 읽는다 (몇 ms) - 나중에
--   걸린 매핑, :source 로 바뀐 매핑도 그대로 보인다. :VimIdeKeys! 는 파일도 새로
--   읽는다. nvim 기본 매핑의 :help 태그는 $VIMRUNTIME/doc/tags 를 한 번 읽어 본다.
--
-- 창 안의 키
--   <CR>     README 항목: README 의 그 자리를 새 탭에 읽기 전용으로 연다
--            매핑: 정의한 파일의 그 줄을 같은 식으로 연다 (nvim 기본 매핑은 :help)
--            명령: 명령줄에 ':명령 ' 을 채운다
--   <C-y>    키를 vim 표기(<F12>, <C-]>)로 " 레지스터에 복사한다. 창은 그대로.
--            'clipboard' 가 unnamed(plus) 면 * / + 에도. 무엇을 복사했는지는
--            프롬프트 제목에 잠깐 (insert 모드에서는 메시지 줄이 바로 덮인다)
--   ^q M-q   보이는 줄 / 고른 줄을 quickfix 로 (README 의 그 줄, 정의한 줄 -
--            정의한 곳을 모르는 줄은 글만 있는 항목으로)
--   ^x ^v ^t 아무것도 하지 않는다 (열 파일이 아니다)
--   F1       이 창의 키(위의 것들과 telescope 의 키)를 맨 앞에 두고 다시 연다
--   Esc ^c   고르지 않고 닫으면 F1 을 누른 창, 그 커서 자리로 - insert 모드에서
--            눌렀으면 그 자리에서 insert 로 (Ctrl+g 의 입력 창 안에서도, R 과 gR
--            은 그 모드로, i_CTRL-O 뒤도), visual 모드면 같은 영역을 다시 고른
--            채로. 그 창의 앞 창(wincmd p)도 F1 을 누르기 전 것으로
--   열린 README/정의 탭은 q 로 닫는다 - F1 을 누른 탭과 창으로 돌아간다.
--   F1 을 누른 곳이 높은 부동 창(입력 창, 찾아 바꾸기 창)이면 목록이 떠 있는
--   동안 그 창을 숨긴다 - 안 그러면 목록 가운데를 가린다. DirDiff 의 보기 메뉴는
--   떠나면 스스로 닫혀서 돌아오지 않는다 - 목록을 닫거나 고르면 메뉴를 연 창
--   (트리)으로 간다 (F1 을 누른 창이 없어졌을 때는 늘 그 창의 앞 창으로).
--
-- 옵션
--   g:vimide_keyhelp_readme   README.md 경로 (기본: 이 파일이 든 vim-ide 의 README)
--   g:vimide_keyhelp_others   0 (또는 v:false)이면 플러그인과 nvim 기본 매핑·
--                             명령은 뺀다 (기본 1). F1 을 누른 버퍼의 매핑과
--                             명령(ftplugin, LSP, delimitMate ...)은 그래도 나온다
--
-- telescope 가 없으면 .vimrc 의 VimIdeKeyHelpBuf() (진짜 vim 이 쓰는 것 -
-- README 의 Usage 목록을 읽기 전용 탭에)로 떨어진다.

if vim.g.loaded_vimide_keyhelp then
  return
end
vim.g.loaded_vimide_keyhelp = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api
local uv = vim.uv or vim.loop

-- <vim-ide>/.vim/plugin/keyhelp.lua -> <vim-ide>. ~/.vim 은 ~/.vim-ide/.vim 으로
-- 가는 링크라 realpath 로 푼다 - 그래야 README 가 git 이 관리하는 그 사본이다.
local HERE = debug.getinfo(1, 'S').source:gsub('^@', '')
HERE = uv.fs_realpath(HERE) or HERE
local REPO = vim.fn.fnamemodify(HERE, ':h:h:h')

-- 경로의 ~ 와 $VAR 만 푼다. expand() 는 'wildignore' 에 걸리는 경로를 빈 글자로
-- 돌려준다 - .vimrc 의 */tmp/* 때문에 /tmp 아래(Yocto 의 build/tmp, macOS 의
-- /private/tmp)에 있는 파일이 통째로 사라졌다.
local function norm(p)
  return vim.fs.normalize(p)
end

local function readme_path()
  local o = vim.g.vimide_keyhelp_readme
  if type(o) == 'string' and o ~= '' then
    return norm(o)
  end
  for _, c in ipairs({ REPO .. '/README.md', norm('~/.vim-ide/README.md') }) do
    if uv.fs_stat(c) then
      return c
    end
  end
  return nil
end

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- 알림은 한 줄로. 메시지가 showcmd·ruler 자리(오른쪽 11 칸)에 닿기만 해도
-- 'Press ENTER' 가 뜬다 - 80 칸 화면에서 82 칸짜리 경고가 그랬다. 화면 폭에서
-- 12 칸을 뺀 데까지 글자(칸) 단위로 자른다.
local function fit(msg)
  msg = tostring(msg or ''):gsub('[\n\r]+', ' ')
  local max = math.max(20, vim.o.columns - 12)
  local sdw = vim.fn.strdisplaywidth
  if sdw(msg) <= max then
    return msg
  end
  local cut = max - sdw('…')
  local lo, hi = 0, vim.fn.strchars(msg)
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if sdw(vim.fn.strcharpart(msg, 0, mid)) <= cut then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return vim.fn.strcharpart(msg, 0, lo) .. '…'
end

local function say(msg, level)
  vim.notify(fit(msg), level)
end

-- 마크다운 코드 조각(`x`, `` ` ``)을 속 글자로 바꾼다 (f 를 주면 f(속 글자)로).
-- 짝이 없는 ` 는 글자 그대로 둔다 - Usage 목록의 '`: 마크 자리로' 처럼 ` 자체가
-- 키인 줄이 있다. ` 를 몽땅 지우던 때는 그 키가 빈 글자가 되어 줄이 앞 항목의
-- 설명에 붙었고, 표의 `` ` `` 칸은 읽히지 않았다.
local function md_code(s, f)
  local out, pos = {}, 1
  while true do
    local a, b = s:find('`+', pos)
    if not a then
      break
    end
    local n = b - a + 1
    local c, d = nil, nil
    local p = b + 1
    while true do
      c, d = s:find('`+', p)
      if not c or d - c + 1 == n then
        break
      end
      p = d + 1
    end
    if not c then
      out[#out + 1] = s:sub(pos, b)
      pos = b + 1
    else
      local inner = s:sub(b + 1, c - 1)
      if inner:find('^ .* $') and inner:find('%S') then
        inner = inner:sub(2, -2)
      end
      out[#out + 1] = s:sub(pos, a - 1)
      out[#out + 1] = f and f(inner) or inner
      pos = d + 1
    end
  end
  out[#out + 1] = s:sub(pos)
  return table.concat(out)
end

-- 화면에 보일 글: 마크다운 표시(` ** )를 걷고 공백을 하나로
local function clean(s)
  s = md_code(s):gsub('%*%*', '')
  return trim((s:gsub('%s+', ' ')))
end

-- 한 줄 설명: 첫 문장. 'e.g.' 같은 것에서 잘못 끊기기도 하지만 보이는 칸이
-- 어차피 한 줄이라 괜찮다.
local function first_sentence(s)
  s = clean(s)
  local cut = s:find('%.%s+[%u`(\'"]')
  if cut and cut > 12 then
    s = s:sub(1, cut)
  end
  if #s > 240 then
    s = s:sub(1, 240)
  end
  return s
end

-- ---------------------------------------------------------------------------
-- README 의 키 표기 -> vim 키
-- ---------------------------------------------------------------------------

local NAMED = {
  enter = '<CR>', ['return'] = '<CR>', esc = '<Esc>', escape = '<Esc>',
  tab = '<Tab>', space = '<Space>', backspace = '<BS>', bs = '<BS>',
  del = '<Del>', delete = '<Del>', up = '<Up>', down = '<Down>',
  left = '<Left>', right = '<Right>', home = '<Home>', ['end'] = '<End>',
  pageup = '<PageUp>', pagedown = '<PageDown>', insert = '<Insert>',
}
local MODS = { ctrl = 'C', shift = 'S', alt = 'M', meta = 'M', cmd = 'D' }

-- 키처럼 생긴 낱말인가. 'si'(테마 이름), 'g:var', '@group', '1'(번호 목록)은
-- 아니다 - 이것들이 키로 잡히면 표 하나가 통째로 엉뚱한 항목이 된다.
local function is_key_tok(t)
  if not t or t == '' then
    return false
  end
  if t:find('^g:') or t:find('^@') or t:find("^'") or t:find('^%$') or t:find('^%d+$') then
    return false
  end
  -- <C-\>, <C-]>, <M-.> 처럼 꺾쇠 안에 문장 부호가 든 것도 키다
  if t:find('^:%a') or t:find('^<[^<>%s]+>') or t:find('^F%d%d?$') then
    return true
  end
  local l = t:lower()
  local mod = l:match('^(%a+)[-+].')
  if mod and MODS[mod] then
    return true
  end
  if NAMED[l] or l:find('^double%-click') or l:find('^mouse%-button') then
    return true
  end
  if (t:find('^\\%S') and #t <= 8) or (t:find('^,%S') and #t <= 6) then
    return true
  end
  if t:find('^[%[%]]%S$') or t:find('^[gz]%S$') or t:find('^%a[%+%-=]$') then
    return true
  end
  if #t == 1 then
    return true
  end
  return #t == 2 and t:sub(1, 1) == t:sub(2, 2) and t:find('^%a') ~= nil -- yy, dd
end

-- 문단 머리에 키가 오는 경우('Ctrl+M twice opens it too.')는 더 엄격하게 본다.
-- 한 글자를 받으면 'A file ...' 같은 문장이 'A' 키가 된다.
local function is_strong_tok(t)
  local l = t:lower()
  local mod = l:match('^(%a+)[-+].')
  return (mod and MODS[mod]) or t:find('^F%d%d?$') or t:find('^<[^<>%s]+>')
    or (t:find('^\\%S') and #t <= 8) or (t:find('^,%S') and #t <= 6)
    or l:find('^double%-click') or false
end

local function tok_lhs(t)
  local l = t:lower()
  if NAMED[l] then
    return NAMED[l]
  end
  if l:find('^double%-click') then
    return '<2-LeftMouse>'
  end
  if l:find('^mouse%-button') then
    return nil
  end
  -- 'Ctrl+Shift+F' 처럼 여럿이 겹친 것까지: <C-S-F>
  local ms, rest = {}, t
  while true do
    local mod, r = rest:match('^(%a+)[-+](.+)$')
    local M = mod and MODS[mod:lower()]
    if not M then
      break
    end
    ms[#ms + 1], rest = M, r
  end
  if #ms > 0 then
    if rest:lower():find('click') then
      return (#ms == 1 and ms[1] == 'C') and '<C-LeftMouse>' or nil
    end
    local r = NAMED[rest:lower()] and NAMED[rest:lower()]:sub(2, -2) or rest
    if #ms == 1 and ms[1] == 'S' and #r == 1 and r:find('%a') then
      return r:upper() -- Shift+h = H
    end
    if r == '<' then
      r = 'lt'
    end
    return '<' .. table.concat(ms, '-') .. '-' .. r .. '>'
  end
  if t:find('^F%d%d?$') then
    return '<' .. t .. '>'
  end
  return t
end

-- vim 이 보는 모양으로 맞춘다 (<C-n> -> <C-N>, <leader>fo -> \fo). 실제 매핑도
-- 같은 함수(keytrans)를 거치므로 두 쪽이 글자 그대로 맞는다.
local function canon(lhs)
  local ok, raw = pcall(api.nvim_replace_termcodes, lhs, true, true, true)
  if not ok then
    return nil
  end
  local ok2, s = pcall(vim.fn.keytrans, raw)
  return ok2 and s or nil
end

-- vim 표기 -> README 표기 (<S-Tab> -> Shift+Tab, <C-R> -> Ctrl+r, <Space> -> Space).
-- DirDiff 의 표와 창의 매핑은 vim 표기라, README 표기('Shift+Tab', 'Ctrl+r')로 치면
-- 글자가 맞지 않아 fuzzy 가 그 줄을 아예 걸러 냈다. 이 이름을 찾기 글에 넣는다.
-- 돌려주는 것: 소문자 글자판('Ctrl+r'), 대문자 글자판('Ctrl+R' - 다르면). 꺾쇠
-- 키가 없으면 nil.
local RS_MOD = { C = 'Ctrl', S = 'Shift', M = 'Alt', A = 'Alt', D = 'Cmd' }
local RS_NAME = {
  CR = 'Enter', Esc = 'Esc', Tab = 'Tab', Space = 'Space', BS = 'Backspace', Del = 'Del',
  Up = 'Up', Down = 'Down', Left = 'Left', Right = 'Right', Home = 'Home', End = 'End',
  PageUp = 'PageUp', PageDown = 'PageDown', Insert = 'Insert', lt = '<', Bar = '|',
  Bslash = '\\', ['2-LeftMouse'] = 'double click', LeftMouse = 'click',
}
local rs_cache = {}
local function readme_style(key)
  if not key or not key:find('<', 1, true) then
    return nil
  end
  local c = rs_cache[key]
  if c ~= nil then
    return c[1], c[2]
  end
  local lo, up, i, any = {}, {}, 1, false
  while i <= #key do
    local tok = key:match('^<[^<>]+>', i)
    if tok then
      local inner, mods = tok:sub(2, -2), {}
      while true do
        local m, r = inner:match('^(%a)%-(.+)$')
        if not (m and RS_MOD[m]) then
          break
        end
        mods[#mods + 1], inner = RS_MOD[m], r
      end
      local base = RS_NAME[inner] or inner
      local s1 = table.concat(mods, '+') .. (#mods > 0 and '+' or '')
      if #mods > 0 and #base == 1 then
        lo[#lo + 1], up[#up + 1] = s1 .. base:lower(), s1 .. base:upper()
      else
        lo[#lo + 1], up[#up + 1] = s1 .. base, s1 .. base
      end
      any = any or (#mods > 0 or RS_NAME[inner] ~= nil)
      i = i + #tok
    else
      local run = key:match('^[^<]+', i)
      lo[#lo + 1], up[#up + 1] = run, run
      i = i + #run
    end
  end
  local a, b = nil, nil
  if any then
    a, b = table.concat(lo, ' '), table.concat(up, ' ')
    if b == a then
      b = nil
    end
  end
  rs_cache[key] = { a, b }
  return a, b
end

local FILLER = { twice = true }

-- 키 하나(대안 하나)를 읽는다: 'Ctrl-W H', 'Ctrl+] Ctrl+]', ':GtagsIndex',
-- 'Ctrl+M twice'. 키가 아닌 낱말이 섞이면 nil.
local function parse_alt(s)
  s = trim(s)
  if s == '' then
    return nil
  end
  local cmd = s:match('^:([%a][%w_]*)')
  if cmd then
    return { disp = s, cmd = cmd }
  end
  s = s:gsub('[Dd]ouble[- ]click', 'double-click'):gsub('[Mm]ouse button', 'mouse-button')
  local seq, extra = {}, false
  for tk in s:gmatch('%S+') do
    -- 앞에 붙은 횟수('1<C-r>', 'N<C-r>')는 보이는 글에만 남기고 키로 읽는다.
    -- 꺾쇠 키만 - '10x' 같은 것까지 받으면 본문의 낱말이 키가 된다.
    if #seq == 0 and not is_key_tok(tk) then
      tk = tk:match('^%d+(<[^<>%s]+>)$') or tk:match('^N(<[^<>%s]+>)$') or tk
    end
    if FILLER[tk:lower()] and #seq > 0 then
      extra = true
    elseif is_key_tok(tk) and not extra then
      seq[#seq + 1] = tk
    elseif tk:find('^%d$') and #seq > 0 and seq[#seq]:find('^mouse%-button') then
      seq[#seq] = seq[#seq] .. tk -- 'mouse button 4'
    else
      return nil
    end
  end
  if #seq == 0 then
    return nil
  end
  local lhs = ''
  if not extra then
    for _, tk in ipairs(seq) do
      local x = tok_lhs(tk)
      if not x then
        lhs = nil
        break
      end
      lhs = lhs .. x
    end
  else
    lhs = nil
  end
  local disp = s:gsub('double%-click', 'double click'):gsub('mouse%-button', 'mouse button')
  return { disp = disp, canon = lhs and canon(lhs) }
end

-- 키 칸 하나('\' (Leader, then '), Ctrl+' or Ctrl+M twice', '\z (or \lz)',
-- 'Ctrl-W H/J/K/L/r/R/x/T')를 대안 목록으로. 키 칸이 아니면 nil.
local function parse_spec(spec)
  spec = trim(md_code(spec):gsub('%*%(default%)%*', ''))
  if spec == '' or #spec > 60 then
    return nil
  end
  local more = {}
  spec = spec:gsub('%(or%s+([^)]*)%)', function(x)
    more[#more + 1] = x
    return ''
  end)
  -- 다른 괄호는 키에 붙은 설명이다 ("(Leader, then ')")
  spec = spec:gsub('%b()', ' ')
  local SEP = '\1'
  spec = spec:gsub('%s+/%s+', SEP):gsub(',%s+', SEP):gsub('%s+or%s+', SEP):gsub('%s+and%s+', SEP)
  local parts = vim.split(spec, SEP, { plain = true })
  vim.list_extend(parts, more)
  local alts, skipped = {}, false
  for i, p in ipairs(parts) do
    p = trim(p)
    -- 'Ctrl-W H/J/K/L' -> Ctrl-W H, Ctrl-W J, ...
    local pre, list = p:match('^(.*%s)(%S/[%S/]+)$')
    local exp = nil
    if pre and is_key_tok(trim(pre)) then
      exp = {}
      for c in list:gmatch('[^/]+') do
        if #c ~= 1 then
          exp = nil
          break
        end
        exp[#exp + 1] = pre .. c
      end
    end
    for _, q in ipairs(exp or { p }) do
      local a = parse_alt(q)
      if a then
        alts[#alts + 1] = a
      elseif i == 1 or #q > 3 then
        -- 첫 키가 키가 아니면 키 칸이 아니다. 뒤쪽의 짧은 것('5')은 넘어간다
        return nil
      else
        skipped = true
      end
    end
  end
  if #alts == 0 then
    return nil
  end
  local d = {}
  for _, a in ipairs(alts) do
    d[#d + 1] = a.disp
  end
  -- 'Ctrl-W H/J/K/L' 처럼 펼친 것, 'mouse button 4 / 5' 처럼 넘어간 것이 있으면
  -- 원래 모양으로 보여 준다
  local disp = (#alts > 4 or skipped) and trim((spec:gsub(SEP, ' / '))) or table.concat(d, ' / ')
  return alts, disp
end

-- 'Key: 설명' 줄. 한 줄에 여럿('\fm: ...    \fS: ...')이면 나눈다.
-- kc0, kc1: 그 키 칸이 text 안에서 차지하는 바이트 자리 (0 부터, kc1 은 끝 다음).
-- 미리보기가 둘째, 셋째 키(\fS, \fR)를 칠할 때 쓴다.
local function split_keyline(text)
  local spec, sep, rest = text:match('^(%S.-)(%s*:%s+)(.*)$')
  if not spec then
    spec, sep, rest = text:match('^(%S.-)%s*:$'), '', ''
  end
  if not spec then
    return nil
  end
  local alts, disp = parse_spec(spec)
  if not alts then
    return nil
  end
  local out = { { alts = alts, disp = disp, rest = rest, kc0 = 0, kc1 = #spec, roff = #spec + #sep } }
  while true do
    local cur = out[#out]
    local a, sp, s2, colon, r2 = cur.rest:match('^(.-)(%s%s%s+)(%S+)(:%s+)(.*)$')
    local alts2, disp2
    if a then
      alts2, disp2 = parse_spec(s2)
    end
    if not alts2 then
      break
    end
    cur.rest = a
    local c0 = cur.roff + #a + #sp
    out[#out + 1] = { alts = alts2, disp = disp2, rest = r2, kc0 = c0, kc1 = c0 + #s2,
      roff = c0 + #s2 + #colon }
  end
  return out
end

-- 문단 머리의 키: 'Ctrl+M twice opens it too.', 'Ctrl+g and Ctrl+/ ask ...'
local function leading_keys(text)
  if not text:find('^[%a<\\,]') then
    return nil
  end
  local t = text:gsub('[Dd]ouble[- ]click', 'double-click')
  local pos, last, want = 1, nil, true
  while true do
    local s, e = t:find('%S+', pos)
    if not s then
      break
    end
    local w = t:sub(s, e)
    local bare = w:gsub(',$', '')
    if want and is_strong_tok(bare) then
      last, want = e, (bare ~= w)
    elseif not want and (w == '/' or w == 'or' or w == 'and') then
      want = true
    elseif not want and FILLER[w:lower()] then
      last = e
    else
      break
    end
    pos = e + 1
  end
  if not last or last >= #t - 1 then
    return nil
  end
  local spec = t:sub(1, last):gsub('double%-click', 'double click')
  local alts, disp = parse_spec(spec)
  if not alts then
    return nil
  end
  -- 넷째 값: 키 칸의 끝 (text 에서도 같은 자리 - 'Double click' 과
  -- 'double-click' 은 길이가 같다)
  return alts, disp, trim(t:sub(last + 1)), last
end

-- 본문에 나오는 키 (찾기용). ` 로 싼 것은 키처럼 생겼으면 다(`w`, `i+`, `]q`),
-- 그냥 적은 것은 Ctrl+x, <Tab>, F5, \fp, :명령 처럼 키가 분명한 것만 - 그냥 적은
-- 'a' 나 'I' 는 낱말이다. 화면의 설명 칸은 첫 문장뿐이라, 본문에만 나오는 키
-- (F9 트리 안의 w, 패널의 i+ i- i=)는 예전에 친 글자로 찾을 수 없었다.
local function body_keys(raw)
  local keys, seen = {}, {}
  local function put(s)
    if s and s ~= '' and not seen[s] then
      seen[s] = true
      keys[#keys + 1] = s
    end
  end
  local function alt(s)
    local a = parse_alt(s)
    -- '<text>' 같은 자리 표시는 키가 아니다 (nvim 이 모르는 <..> 는 <lt> 로 온다)
    if a and (a.cmd or (a.canon and not a.canon:find('^<lt>'))) then
      put(a.disp)
      put(a.canon)
      put(a.cmd)
    end
  end
  local plain = md_code(raw, function(inner)
    alt(inner)
    return ' '
  end)
  for w in plain:gmatch('%S+') do
    -- 문장 부호를 떼되 ']' 는 둔다 (Ctrl+])
    w = w:gsub('^%(+', ''):gsub('[),.;"\']+$', '')
    if w:find('^:%u') or (w ~= '' and is_strong_tok(w)) then
      alt((w:gsub(':$', '')))
    end
  end
  return keys
end

-- ---------------------------------------------------------------------------
-- README 읽기 (mtime·크기가 같으면 지난번 것)
-- ---------------------------------------------------------------------------

local function heading_text(s)
  return trim((s:gsub('^#+%s*', ''):gsub('`', '')))
end

local function is_usage(path)
  return path[1] ~= nil and path[1]:lower():find('^usage') ~= nil
end

local function parse_readme(file)
  local f = io.open(file, 'rb')
  if not f then
    return nil
  end
  -- 디렉터리도 io.open 은 된다 - read 가 nil 을 돌려준다
  local data = f:read('*a')
  f:close()
  if not data then
    return nil
  end
  local lines = vim.split((data:gsub('\r\n', '\n')), '\n', { plain = true })
  local items, mentions = {}, {}
  local heads = {} -- heads[2] = '## ...' 의 글, heads[3] ...
  local secs = {} -- 제목마다 { lv, text, lnum, lend, ntable = 키 표가 아닌 표가 있나 }
  local usage_seen = false

  local function path_now()
    local p = {}
    for lv = 2, 6 do
      if heads[lv] then
        p[#p + 1] = heads[lv]
      end
    end
    return p
  end

  local function add(e)
    e.usage = is_usage(e.path)
    e.where = e.path[#e.path] or 'README'
    items[#items + 1] = e
  end

  -- 'Key: 설명' 목록 블록. usage 면 0 열 문단도 항목(설명)으로 넣는다.
  local function keylist(rows, path, usage)
    local group = nil -- 같은 줄에서 나온 항목들 (+ 이어지는 줄)
    local function finish()
      if not group then
        return
      end
      local cont = table.concat(group.body, ' ', 2)
      for _, e in ipairs(group.entries) do
        e.lend = group.lend
        local txt = e.rest
        -- 한 줄에서 나눈 것이 아니면 이어지는 줄까지 읽어 첫 문장을 만든다
        if #group.entries == 1 then
          for k = 2, math.min(#group.body, 4) do
            txt = txt .. ' ' .. group.body[k]
          end
        end
        e.desc = first_sentence(txt)
        -- 찾기는 본문 전체로 한다. 한 줄에 여럿인 줄('\fm: ...  \fS: ...')의 이어지는
        -- 줄은 누구 것인지 모르니 모두에게 준다.
        local raw = e.rest .. ' ' .. cont
        e.body = clean(raw)
        e.bkeys = body_keys(raw)
        e.rest = nil
        add(e)
      end
      group = nil
    end
    local function start(ln, parts, style)
      finish()
      group = { entries = {}, lend = ln, body = { '' }, nlines = 1, last_ind = false, style = style }
      for _, p in ipairs(parts) do
        group.entries[#group.entries + 1] = {
          kind = 'readme', style = style, path = path, lnum = ln,
          alts = p.alts, keys = p.disp, rest = p.rest, kc0 = p.kc0, kc1 = p.kc1,
        }
      end
    end
    for _, r in ipairs(rows) do
      local ln, text = r[1], r[2]
      if text:find('^%s*$') then
        finish()
      elseif text:find('^%s') then
        if group then
          group.lend, group.last_ind = ln, true
          group.nlines = group.nlines + 1
          group.body[#group.body + 1] = trim(text)
        end
      else
        local parts = split_keyline(text)
        if parts then
          start(ln, parts, 'key')
        elseif not usage then
          finish() -- 다른 절: 0 열의 글은 키 설명이 아니라 본문이다
        else
          local alts, disp, rest, klast = leading_keys(text)
          -- 0 열 대문자 줄이 새 문단인 경우: 짧은 한 줄짜리 항목('F5: Clear all
          -- marks') 바로 다음이거나, 들여 쓴 줄로 이어 오던 항목 다음. 앞 키의
          -- 설명에 붙이면 거짓이 된다(F5 미리보기에 quickfix 의 + - = 이야기).
          -- 여러 줄로 감긴 문단('Ctrl+h (or ,ch): ...' 다음의 'Then Enter ...')은
          -- 대문자로 시작해도 잇는다.
          local new_para = group and group.style == 'key' and text:find('^%u')
            and ((group.nlines == 1 and #(lines[group.entries[1].lnum] or '') < 60)
              or group.last_ind)
          if alts then
            start(ln, { { alts = alts, disp = disp, rest = rest, kc0 = 0, kc1 = klast } }, 'note')
          elseif group and not new_para then
            group.lend, group.last_ind = ln, false
            group.nlines = group.nlines + 1
            group.body[#group.body + 1] = trim(text)
          else
            start(ln, { { alts = {}, disp = '', rest = text } }, 'note')
          end
        end
      end
    end
    finish()
  end

  local i, n = 1, #lines
  local fence, blk = false, nil
  while i <= n do
    local l = lines[i]
    for name in l:gmatch(':(%u[%w_]+)') do
      mentions[name] = mentions[name] or i
    end
    if l:find('^```') then
      if not fence then
        fence, blk = true, { path = path_now(), rows = {} }
      else
        fence = false
        local usage = is_usage(blk.path)
        if usage then
          -- Usage 절은 첫 블록이 키 목록이다 (둘째 블록은 :cs find 의 질의 번호)
          if not usage_seen then
            usage_seen = true
            keylist(blk.rows, blk.path, true)
          end
        else
          local cnt = 0
          for _, r in ipairs(blk.rows) do
            if not r[2]:find('^%s') and split_keyline(r[2]) then
              cnt = cnt + 1
            end
          end
          if cnt >= 3 then
            keylist(blk.rows, blk.path, false)
          end
        end
        blk = nil
      end
    elseif fence then
      blk.rows[#blk.rows + 1] = { i, l }
    elseif l:find('^#+%s') then
      local lv = #l:match('^(#+)')
      heads[lv] = heading_text(l)
      secs[#secs + 1] = { lv = lv, text = heads[lv], lnum = i }
      for k = lv + 1, 6 do
        heads[k] = nil
      end
    elseif l:find('^|') and lines[i + 1] and lines[i + 1]:find('^|[%s%-:|]+|%s*$') then
      -- 키 표: 머리줄 첫 칸이 비었거나 'in the ...'
      -- 칸은 '\|' 가 아닌 | 로만 나눈다 (`\|` 는 | 키다)
      local function cells(s)
        s = s:gsub('\\|', '\2'):gsub('^%s*|', ''):gsub('|%s*$', '')
        local c = vim.split(s, '|', { plain = true })
        for k, v in ipairs(c) do
          c[k] = v:gsub('\2', '|')
        end
        return c
      end
      local hc = cells(l)
      local h1 = trim(hc[1] or ''):lower()
      local keytable = h1 == '' or h1:find('^in the') ~= nil
      if not keytable and secs[#secs] then
        secs[#secs].ntable = true
      end
      local path = path_now()
      local j = i + 2
      while j <= n and lines[j]:find('^|') do
        for name in lines[j]:gmatch(':(%u[%w_]+)') do
          mentions[name] = mentions[name] or j
        end
        if keytable then
          local c = cells(lines[j])
          local c1 = trim(c[1] or '')
          if c1:find('^`') or c1:lower():find('^double') then
            local alts = {}
            local first = true
            local ok = true
            local toks = {}
            md_code(c1, function(inner)
              toks[#toks + 1] = inner
              return ''
            end)
            for _, tk in ipairs(toks) do
              local a = parse_alt(tk)
              if a then
                alts[#alts + 1] = a
              elseif first then
                ok = false
                break
              end
              first = false
            end
            -- '`Ctrl-W H` / `J` / `K`': 뒤의 한 글자는 앞 키의 머리(Ctrl-W)를 물려받는다.
            -- 그냥 두면 J, K 가 전역의 J, K(창 높이)로 읽힌다.
            local pre = ok and alts[1] and alts[1].disp:match('^(.*%s)%S$')
            if pre then
              for k = 2, #alts do
                if #alts[k].disp == 1 then
                  alts[k] = parse_alt(pre .. alts[k].disp) or alts[k]
                end
              end
            end
            if ok and #alts > 0 then
              local raw = table.concat(c, ' | ', 2)
              local cell = clean(raw)
              add({
                kind = 'readme', style = 'table', path = path, lnum = j, lend = j,
                alts = alts,
                keys = clean((c1:gsub('%*%(default%)%*', ''))),
                desc = first_sentence(c[2] or ''),
                cell = cell, body = cell, bkeys = body_keys(raw),
                hdr1 = trim(hc[1] or ''),
              })
            end
          end
        end
        j = j + 1
      end
      i = j - 1
    end
    i = i + 1
  end

  -- 키 표가 아닌 표(DirDiff 의 'view | id | shows')는 항목이 되지 않는다. 그 표를
  -- 가리키는 키 줄(트리의 f: '... see *Views* below')이 있으면 그 절의 글(표와 그
  -- 아래 목록)을 그 줄의 찾기 글에 붙이고, 미리보기에도 보인다. 그래서 '최신',
  -- '고아', 'right-newer', 'vimide_dirdiff_filter' 로 f 줄이 나온다.
  -- 가리키는 법은 기울인 절 제목(*Views*) 하나 - 큰따옴표로 적은 절 이름은 대개
  -- 다른 큰 절을 가리켜서 붙이지 않는다. 붙이는 글은 제목에서 표까지, 그리고 표
  -- 바로 뒤의 목록(빈 줄 없이 이어지는 '- ...' 들)까지 - 그 절의 나머지(Views
  -- 아래의 'Copying in the tree' 같은 것)는 다른 이야기다.
  for k, sc in ipairs(secs) do
    sc.lend = n
    for k2 = k + 1, #secs do
      if secs[k2].lv <= sc.lv then
        sc.lend = secs[k2].lnum - 1
        break
      end
    end
    if sc.ntable then
      local j, tbl = sc.lnum + 1, false
      while j <= sc.lend and not (tbl and not lines[j]:find('^|')) do
        tbl = tbl or lines[j]:find('^|') ~= nil
        j = j + 1
      end
      -- 표 다음: 빈 줄을 건너 목록이나 문단 하나
      while j <= sc.lend and lines[j]:find('^%s*$') do
        j = j + 1
      end
      while j <= sc.lend and not lines[j]:find('^%s*$') do
        j = j + 1
      end
      sc.bend = j - 1
    end
  end
  local byname, stext = {}, {}
  for _, sc in ipairs(secs) do
    local nm = sc.text:lower()
    if sc.ntable and not byname[nm] and sc.bend - sc.lnum <= 60 then
      byname[nm] = sc
    end
  end
  -- 그 절의 찾기 글과 미리보기에 보일 자리. 키 표가 없는 창(DirDiff 의 보기 메뉴)의
  -- 줄도 이것을 붙인다 (build 의 WIN_SECTION).
  local function sect_ref(sc)
    if not stext[sc] then
      local t = {}
      for k = sc.lnum + 1, sc.bend do
        local l = lines[k]
        if not l:find('^```') and not l:find('^|[%s%-:|]+|%s*$') then
          t[#t + 1] = (l:gsub('|', ' '))
        end
      end
      stext[sc] = { lnum = sc.lnum, lend = sc.bend, text = sc.text, body = clean(table.concat(t, ' ')) }
    end
    return stext[sc]
  end
  if next(byname) then
    for _, it in ipairs(items) do
      for nm in (it.body or ''):gmatch('%*([^%*]+)%*') do
        local sc = byname[nm:lower()]
        if sc and (sc.lnum > it.lnum or sc.lend < it.lnum) then
          it.ref = sect_ref(sc)
          it.body = it.body .. ' ' .. it.ref.body
          break
        end
      end
    end
  end
  local function ref_of(name)
    local sc = byname[name]
    return sc and sect_ref(sc) or nil
  end
  return { items = items, mentions = mentions, lines = lines, file = file, ref_of = ref_of }
end

-- 파일이 바뀌었는지 보는 열쇠. 초까지만 보면 같은 초 안에 같은 크기로 다시 쓴 것을
-- 놓친다 - 나노초, 크기, inode 까지 본다 (projectfiles.lua 와 같은 규칙).
local function stat_key(st)
  return ('%d.%d:%d:%d'):format(st.mtime.sec, st.mtime.nsec or 0, st.size, st.ino or 0)
end

local rcache = nil -- { key = 'path:stat_key', data = ... }

local function readme_data(force)
  local file = readme_path()
  if not file then
    return nil
  end
  local st = uv.fs_stat(file)
  if not st or st.type ~= 'file' then
    return nil
  end
  local key = file .. ':' .. stat_key(st)
  if not force and rcache and rcache.key == key then
    return rcache.data
  end
  local d = parse_readme(file)
  rcache = d and { key = key, data = d } or nil
  return d
end

-- ---------------------------------------------------------------------------
-- 지금 걸린 매핑과 명령
-- ---------------------------------------------------------------------------

-- vim-ide 의 파일인가. ~/.vim 이 링크면 그 부모(~/.vim-ide)가 통째로 vim-ide 다.
local exact, roots = {}, nil
local function vimide_roots()
  if roots then
    return roots
  end
  roots = {}
  local function add_dir(p)
    roots[#roots + 1] = (p:gsub('/*$', '/'))
  end
  add_dir(REPO)
  local dv = norm('~/.vim')
  local rv = uv.fs_realpath(dv)
  if rv then
    add_dir(rv ~= dv and vim.fn.fnamemodify(rv, ':h') or rv)
  end
  local fr = norm('~/.vimrc')
  local rr = uv.fs_realpath(fr)
  if rr then
    if rr ~= fr then
      add_dir(vim.fn.fnamemodify(rr, ':h'))
    end
    exact[rr] = true
  end
  return roots
end

local function is_vimide(p)
  if exact[p] then
    return true
  end
  for _, r in ipairs(vimide_roots()) do
    if p:sub(1, #r) == r then
      return true
    end
  end
  return false
end

local VIMRUNTIME = vim.env.VIMRUNTIME or ''
VIMRUNTIME = (uv.fs_realpath(VIMRUNTIME) or VIMRUNTIME):gsub('/*$', '/')

-- 종류 -> 순서. vim-ide 것이 먼저, 그다음 플러그인, nvim 기본.
local RANK = { vimide = 1, plugin = 2, other = 2, nvim = 3 }

local function classify(p)
  if not p then
    return 'other', 'Lua'
  end
  local plug = p:match('/plugged/([^/]+)/')
  if plug then
    return 'plugin', plug
  end
  if is_vimide(p) then
    return 'vimide', vim.fn.fnamemodify(p, ':t')
  end
  if VIMRUNTIME ~= '/' and p:sub(1, #VIMRUNTIME) == VIMRUNTIME then
    return 'nvim', p:match('/pack/[^/]+/opt/([^/]+)/') or 'nvim'
  end
  plug = p:match('/pack/[^/]+/[^/]+/([^/]+)/')
  if plug then
    return 'plugin', plug
  end
  return 'other', vim.fn.fnamemodify(p, ':t')
end

local snames = {} -- sid -> realpath ('' = 모름). 스크립트 번호는 세션 동안 그대로다.
local function script_path(sid)
  if type(sid) ~= 'number' or sid <= 0 then
    return nil
  end
  if snames[sid] == nil then
    -- getscriptinfo({sid = n}) 는 그 스크립트의 함수와 변수까지 다 담아 와서
    -- 무겁다(.vimrc 는 수백 개). 이름만 든 전체 목록을 읽어 한꺼번에 채운다.
    -- 나중에 읽힌 스크립트는 새 번호라 여기로 다시 온다.
    local ok, all = pcall(vim.fn.getscriptinfo)
    for _, s in ipairs(ok and all or {}) do
      if snames[s.sid] == nil and s.name and s.name ~= '' then
        local n = norm(s.name)
        snames[s.sid] = uv.fs_realpath(n) or n
      end
    end
    if snames[sid] == nil then
      snames[sid] = ''
    end
  end
  local p = snames[sid]
  return p ~= '' and p or nil
end

-- telescope 가 프롬프트에 건 매핑의 desc: 'telescope|동작 이름', 함수면
-- 'telescopej|{"source":..,"linedefined":..}'. callback 은 telescope 의 감싸개라
-- 그대로 따라가면 늘 telescope/mappings.lua 를 가리킨다 - 함수가 있는 자리는
-- desc 에 든 것을 쓴다. 보일 desc 는 동작 이름만 (함수면 없다).
local function tele_desc(desc)
  if type(desc) ~= 'string' then
    return desc, nil
  end
  local name = desc:match('^telescope|(.*)$')
  if name then
    return name ~= '' and name or nil, nil
  end
  local js = desc:match('^telescopej|(.*)$')
  if js then
    local ok, d = pcall(vim.json.decode, js)
    return nil, ok and type(d) == 'table' and d or {}
  end
  return desc, nil
end

-- 매핑을 정의한 자리: 경로, 줄(0 = 모름), 종류를 강제할 때 그 종류
local function def_source(m, tj)
  if tj then
    local s = type(tj.source) == 'string' and tj.source or ''
    if s:sub(1, 1) == '@' and s:find('^@[/~]') then
      s = norm(s:sub(2))
      return uv.fs_realpath(s) or s, tonumber(tj.linedefined) or 0
    end
    -- ':lua' (.vimrc 의 lua << EOF 안) - 파일과 줄을 알 수 없다
    return nil, 0
  end
  if m.callback then
    local ok, info = pcall(debug.getinfo, m.callback, 'S')
    local s = ok and info and info.source or ''
    if s:sub(1, 1) == '@' then
      s = s:sub(2)
      -- 'vim/_core/defaults' 처럼 nvim 안에 든 것
      if not s:find('^[/~]') then
        return nil, 0, 'nvim'
      end
      s = norm(s)
      return uv.fs_realpath(s) or s, info.linedefined or 0
    end
  end
  local p = script_path(m.sid)
  if p then
    return p, m.lnum or 0
  end
  if (m.desc or ''):find('^:help ') then
    return nil, 0, 'nvim'
  end
  -- 스크립트 번호 0 은 명령줄에서 손으로 친 매핑이다
  if m.sid == 0 then
    return nil, 0, 'cmdline'
  end
  return nil, 0
end

local MODES = { 'n', 'x', 's', 'o', 'i', 'c', 't' }

-- 어떤 탭·창 안에서만 일을 하고 그 밖에서는 가로채기 전의 뜻으로 넘기는 전역
-- 매핑. DirDiff 는 <C-r> <C-l> <C-S-r> <C-S-l> 을 비교 창에서만 쓰려고 전역 n/x
-- 매핑을 감싼다 - nvim 이 보는 것은 그 감싼 매핑 하나라, desc 만 보면 어디서나
-- DirDiff 복사를 하는 키처럼 읽혔다 (Usage 의 Ctrl+l '창 옮기기' 미리보기).
-- sect, hdr: 이 매핑과 묶을 README 표 (절 제목에 든 글자, 표 머리줄 첫 칸에 든
-- 글자 - 소문자). 같은 절의 'in the tree' 표의 <C-r> 은 트리 버퍼의 매핑이다.
-- up: 감싸기 전의 매핑을 든 표와 그 열쇠 - 감싼 함수의 upvalue 이름
-- (dirdiffview.lua 의 take_over: prev_maps[id], id = 'n<C-l>').
local SCOPED = {
  { desc = '^DirDiff 비교 창', sect = 'comparing directories', hdr = 'edit window',
    where = 'DirDiff 탭의 비교 창에서만', up = { 'prev_maps', 'id' } },
}
local function scope_of(d)
  for _, sc in ipairs(SCOPED) do
    if type(d.desc) == 'string' and d.desc:find(sc.desc) then
      return sc
    end
  end
  return nil
end

-- 감싼 매핑이 그 밖에서 넘기는 것. DirDiff 는 감싸기 전의 매핑을 제 파일 안의 표에만
-- 두어서 nvim 의 매핑 목록에는 없다 - Ctrl+l 미리보기가 DirDiff 복사만 말하고
-- 그 밖의 :wincmd l 은 말하지 못했다. 감싼 함수의 upvalue 에서 그 표와 열쇠를 찾는다.
-- 돌려주는 것: maparg() 의 사전, 감싸기 전에 매핑이 없었으면 { none = true },
-- 찾지 못하면(감싼 쪽이 바뀌었다) nil - 그때는 '원래 뜻' 이라고만 적는다.
local function scoped_prev(fn, sc)
  if type(fn) ~= 'function' or not sc.up then
    return nil
  end
  local tbl, key
  for i = 1, 60 do
    local n, v = debug.getupvalue(fn, i)
    if not n then
      break
    end
    if n == sc.up[1] and type(v) == 'table' then
      tbl = v
    elseif n == sc.up[2] and type(v) == 'string' then
      key = v
    end
  end
  if not (tbl and key) then
    return nil
  end
  local p = tbl[key]
  return type(p) == 'table' and next(p) and p or { none = true }
end

local function mode_str(set)
  local s = set.n and 'n' or ''
  if set.x and set.s then
    s = s .. 'v'
  elseif set.x then
    s = s .. 'x'
  elseif set.s then
    s = s .. 's'
  end
  for _, k in ipairs({ 'o', 'i', 'c', 't' }) do
    if set[k] then
      s = s .. k
    end
  end
  return s
end

-- get(mode) 가 돌려주는 매핑을 키(keytrans 한 lhs)로 묶는다. 같은 키라도 모드마다
-- rhs 가 다를 수 있어서(<C-g> 의 n / x) 정의는 따로 모은다.
local function collect_maps(get, modes, buf)
  local by, order = {}, {}
  for _, mode in ipairs(modes) do
    local ok, list = pcall(get, mode)
    for _, m in ipairs(ok and list or {}) do
      local lhs = m.lhs or ''
      local low = lhs:lower()
      if lhs ~= '' and not low:find('^<plug>') and not low:find('^<snr>') then
        local ok2, key = pcall(vim.fn.keytrans, m.lhsraw or lhs)
        key = ok2 and key or lhs
        local g = by[key]
        if not g then
          g = { key = key, lhs = lhs, modes = {}, defs = {}, ids = {}, buf = buf }
          by[key] = g
          order[#order + 1] = g
          if m.lhsrawalt then
            local ok3, alt = pcall(vim.fn.keytrans, m.lhsrawalt)
            if ok3 and alt ~= key and not by[alt] then
              by[alt] = g
            end
          end
        end
        g.modes[mode] = true
        -- 감싼 매핑(SCOPED)은 모드마다 함수가 따로라 n, x 가 두 정의로 갈렸다. 그 밖에서
        -- 하는 일이 같으면 하나로 (nx)
        local cb, prev = tostring(m.callback), nil
        local sc = m.callback and scope_of(m)
        if sc then
          prev = scoped_prev(m.callback, sc)
          cb = prev and ('scoped\0' .. (prev.none and 'none' or table.concat({ prev.rhs or '',
            prev.desc or '', tostring(prev.sid), tostring(prev.lnum), tostring(prev.callback) }, '\1')))
            or cb
        end
        local id = table.concat({ m.rhs or '', m.desc or '', tostring(m.sid), tostring(m.lnum), cb }, '\0')
        local d = g.ids[id]
        if not d then
          local desc, tj = tele_desc(m.desc)
          local p, line, force = def_source(m, tj)
          local kind, label = classify(p)
          if force == 'nvim' then
            kind, label = 'nvim', 'nvim'
          elseif force == 'cmdline' then
            kind, label = 'other', '명령줄'
          end
          d = {
            modes = {}, rhs = m.rhs, desc = desc, path = p, line = line,
            kind = kind, label = label, sid = m.sid,
            callback = m.callback ~= nil, expr = m.expr == 1,
            tele = (m.desc or ''):find('^telescopej?|') ~= nil, prev = prev,
          }
          g.ids[id] = d
          g.defs[#g.defs + 1] = d
        end
        d.modes[mode] = true
      end
    end
  end
  -- nvim 이 문자열 rhs 로 건 기본 매핑(<C-W><C-D> -> <C-W>d)은 함수도 스크립트도
  -- 없어서 사용자가 Lua 로 건 것과 구별되지 않는다. desc 가 nvim 기본 매핑의
  -- desc 와 같으면 nvim 것으로 친다 (<C-W>d 는 nvim 안의 함수다).
  local ndesc = {}
  for _, g in ipairs(order) do
    for _, d in ipairs(g.defs) do
      if d.kind == 'nvim' and d.desc and d.desc ~= '' then
        ndesc[d.desc] = true
      end
    end
  end
  for _, g in ipairs(order) do
    g.mode = mode_str(g.modes)
    for _, d in ipairs(g.defs) do
      d.mode = mode_str(d.modes)
      if not d.path and d.kind == 'other' and d.label == 'Lua' and d.desc and ndesc[d.desc] then
        d.kind, d.label = 'nvim', 'nvim'
      end
    end
    g.kind, g.label = g.defs[1].kind, g.defs[1].label
  end
  return by, order
end

-- 전역 명령에 F1 을 누른 버퍼의 명령(-buffer)을 겹친다. gutentags 의
-- :GutentagsUpdate 처럼 버퍼마다 거는 명령은 전역 목록에 없어서, README 에 적힌
-- 그 줄이 '지금 걸린 명령 없음' 으로 보였다. 이름이 같으면 버퍼 것이 이긴다
-- (vim 도 그렇게 부른다).
local function collect_cmds(buf)
  local by = {}
  local function put(cmds, is_buf)
    for name, d in pairs(cmds or {}) do
      local p = script_path(d.script_id)
      local kind, label = classify(p)
      -- definition 은 키 글자처럼 저장돼 있어서 0x80 바이트가 '0x80 0xfe X' 로
      -- 들어 있다. 한글('지' = EC A7 80)이 '지<fe>X' 로 깨져 보였다 - 되돌린다.
      -- 그 밖의 '0x80 ..' 은 키 코드다: <SID> 가 '0x80 0xfd R' 로 들어 있어서
      -- ':MarkPalette' 가 'call <80><fd>R63_SetPalette(...)' 로 보였다 - keytrans 로
      -- 이름을 붙인다 (<SNR>63_SetPalette, 매핑의 rhs 와 같은 모양)
      local def = (d.definition or ''):gsub('\128([^\254].)', function(x)
        local okk, s = pcall(vim.fn.keytrans, '\128' .. x)
        return okk and s or nil
      end):gsub('\128\254X', '\128')
      by[name] = {
        name = name, def = def, nargs = d.nargs, bang = d.bang,
        range = d.range, path = p, line = 0, kind = kind, label = label, buf = is_buf,
      }
    end
  end
  local ok, cmds = pcall(api.nvim_get_commands, { builtin = false })
  put(ok and cmds, false)
  if buf and api.nvim_buf_is_valid(buf) then
    local okb, bcmds = pcall(api.nvim_buf_get_commands, buf, {})
    put(okb and bcmds, true)
  end
  return by
end

-- ---------------------------------------------------------------------------
-- 목록 만들기
-- ---------------------------------------------------------------------------

local function leader()
  local l = vim.g.mapleader
  return (type(l) == 'string' and l ~= '') and l or '\\'
end

-- Usage 밖의 표에서 전역 매핑과 묶어도 되는 키: 리더, F 키, Ctrl-W, ','
local function global_looking(c)
  local L = canon(leader()) or '\\'
  return c:sub(1, #L) == L or c:find('^<F%d') ~= nil or c:find('^<C%-W>') ~= nil
    or c:sub(1, 1) == ','
end

local function one_line(s)
  return trim(((s or ''):gsub('[\n\r\t]+', ' ')))
end

-- 목록에 보일 키: ' '(<Space>) 같은 키는 글자로는 안 보인다 - keytrans 모양으로
local function lhs_disp(g)
  return g.lhs:find('%s') and g.key or g.lhs
end

-- 설명이 없는 매핑은 rhs, 함수면 '(Lua 함수)'
local function map_desc(d)
  local s = one_line(d.desc or (d.rhs and d.rhs ~= '' and d.rhs) or (d.callback and '(Lua 함수)') or '')
  -- 감싼 매핑이 제 desc 에 '그 밖' 을 적지 않았으면 그 밖에서 하는 일을 덧붙인다
  if scope_of(d) and not s:find('그 밖', 1, true) then
    local p = d.prev
    local what = (p and p.none and 'nvim 기본')
      or (p and one_line((p.rhs and p.rhs ~= '' and p.rhs) or p.desc or '(Lua 함수)'))
      or '원래 뜻'
    s = s .. ' (그 밖에서는 ' .. what .. ')'
  end
  return s
end

-- filetype 이 사람이 읽을 이름이 아닌 창 (목록 칸이 좁아 'vimid…' 로 잘렸다)
local WIN_NAME = {
  vimidedirdiffmenu = 'DirDiff 보기 메뉴',
}

-- '이 창 · <이름>' 의 이름: filetype(WIN_NAME), 없으면 버퍼 이름, 그것도 없으면
-- 부동 창의 제목. 셋 다 없는 창이 '이 창 · ' 로 비어 보였다.
local function win_label(win, buf)
  local ft = vim.bo[buf].filetype
  if ft ~= '' then
    return WIN_NAME[ft] or ft
  end
  local nm = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ':t')
  if nm ~= '' then
    return nm
  end
  local ok, cfg = pcall(api.nvim_win_get_config, win or 0)
  if ok and cfg.relative and cfg.relative ~= '' then
    local t = cfg.title
    if type(t) == 'table' then
      local parts = {}
      for _, c in ipairs(t) do
        parts[#parts + 1] = type(c) == 'table' and tostring(c[1] or '') or tostring(c)
      end
      t = table.concat(parts)
    end
    t = type(t) == 'string' and trim(t) or ''
    return t ~= '' and t or '부동 창'
  end
  local bt = vim.bo[buf].buftype
  return bt ~= '' and bt or '이름 없는 창'
end

-- 특수 창의 filetype -> 그 창의 키 표가 있는 README 절 (제목에 든 글자, 소문자).
-- 앞의 절이 이긴다. 키 표가 아닌 표만 있는 절(DirDiff 의 'Views' - 보기 이름과 id)은
-- 제목이 그 이름과 같을 때 그 표를 그 창의 줄마다 붙인다 (미리보기와 찾기 글).
-- 보기 메뉴의 키(<CR> q ...)를 트리의 같은 키와 묶으면 엉뚱한 뜻이 된다.
local WIN_SECTION = {
  ['neo-tree'] = { 'neo-tree' },
  relationview = { 'relation window' },
  vimidedirdiff = { 'side-by-side tree' },
  vimidedirdiffmenu = { 'views' },
  nerdtree = { 'nerdtree' },
  TelescopePrompt = { 'keys in a telescope list' },
}
-- 이 목록(단축키 도움말) 자신의 프롬프트: <CR>, <C-y> 는 F1 절의 뜻이다
local KEYHELP_SECTIONS = { 'shortcut help (f1)', 'keys in a telescope list' }

local function buf_keymap(buf)
  return function(m)
    return api.nvim_buf_get_keymap(buf, m)
  end
end

-- pre: telescope 프롬프트에서 F1 을 눌렀을 때 그 프롬프트를 닫기 전에 모아 둔
--      매핑 { order = ..., ft = 'TelescopePrompt', name = 'telescope' }.
--      닫고 나면 프롬프트 버퍼가 없어져서 여기서는 읽을 수 없다.
local function build(origin_buf, pre, origin_win)
  local rd = readme_data(false)
  local maps, morder = collect_maps(api.nvim_get_keymap, MODES)
  local valid = api.nvim_buf_is_valid(origin_buf)
  local cmds = collect_cmds(valid and origin_buf or nil)
  -- let g:vimide_keyhelp_others = v:false 도 0 과 같다 (Lua 에서 false ~= 0)
  local ov = vim.g.vimide_keyhelp_others
  local others = not (ov == 0 or ov == false)
  local out = {}

  -- 0) F1 을 누른 특수 창의 버퍼 매핑 (트리, 패널, quickfix, telescope ...)
  --    그 창을 다루는 README 절의 표에 같은 키가 있으면 한 항목으로 묶는다
  --    (README 글이 이긴다). neo-tree 의 J/K 는 desc 없는 Lua 함수라 그대로는
  --    '(Lua 함수)' 로밖에 보이지 않는다.
  local used = {}
  local lorder, ft, name
  if pre then
    lorder, ft, name = pre.order, pre.ft, pre.name
  elseif valid and vim.bo[origin_buf].buftype ~= '' then
    ft = vim.bo[origin_buf].filetype
    name = win_label(origin_win, origin_buf)
    local _
    _, lorder = collect_maps(buf_keymap(origin_buf), { 'n', 'x' }, true)
  end
  if lorder then
    local byk, sidx = {}, {}
    local sects = (pre and pre.keyhelp) and KEYHELP_SECTIONS or WIN_SECTION[ft] or {}
    local wref = nil -- 키 표가 아닌 표의 절 (DirDiff 보기 메뉴 -> Views)
    for si, sect in ipairs(rd and sects or {}) do
      wref = wref or rd.ref_of(sect)
      for _, it in ipairs(rd.items) do
        if table.concat(it.path, ' '):lower():find(sect, 1, true) then
          for _, a in ipairs(it.alts) do
            if a.canon and not byk[a.canon] then
              byk[a.canon] = it
              sidx[it] = sidx[it] or si
            end
          end
        end
      end
    end
    local rows = {}
    for i, g in ipairs(lorder) do
      local it = byk[g.key]
      if it then
        used[it] = true
      end
      -- telescope 프롬프트: README 에 적힌 키, telescope 의 동작, 그 밖의 것
      -- (delimitMate 처럼 모든 버퍼에 거는 플러그인의 insert 매핑) 순서로.
      -- 그대로 두면 <BS>, <C-G>g 가 맨 위를 차지했다.
      local rank = 0
      if pre then
        rank = it and 0 or (g.defs[1].tele and 1) or 2
      end
      rows[#rows + 1] = {
        src = 'map', g = g, it = it, mode = g.mode, keys = lhs_disp(g),
        desc = it and it.desc or map_desc(g.defs[1]),
        where = '이 창 · ' .. name, local_ = true, rank = rank, i = i,
        ref = not it and wref or nil,
      }
    end
    table.sort(rows, function(a, b)
      if a.rank ~= b.rank then
        return a.rank < b.rank
      end
      -- README 에 적힌 것은 앞선 절부터, 절 안에서는 README 순서로 (Enter,
      -- 여는 키, 고르기 ...)
      if pre and a.it and b.it then
        local x, y = sidx[a.it] or 0, sidx[b.it] or 0
        if x ~= y then
          return x < y
        end
        if a.it.lnum ~= b.it.lnum then
          return a.it.lnum < b.it.lnum
        end
      end
      return a.i < b.i
    end)
    vim.list_extend(out, rows)
  end

  -- 보통 파일 버퍼의 버퍼 매핑 (ftplugin, LSP, 플러그인이 버퍼마다 거는 것).
  -- README 의 키와 맞출 때 전역 매핑과 같이 보고, 남는 것은 아래 2) 에 넣는다.
  local bmaps, border = {}, {}
  if valid and vim.bo[origin_buf].buftype == '' then
    bmaps, border = collect_maps(buf_keymap(origin_buf), MODES, true)
  end

  -- 1) README (Usage 목록, 다른 절의 표와 블록) - 실제 매핑·명령과 묶는다
  for _, it in ipairs(rd and rd.items or {}) do
    if not used[it] then
      local e = { src = 'readme', it = it, maps = {}, cmds = {}, keys = it.keys,
        desc = it.desc, where = it.where }
      local mset, seen = {}, {}
      for _, a in ipairs(it.alts) do
        if a.cmd then
          local c = cmds[a.cmd]
          if c and not seen[c] then
            seen[c] = true
            e.cmds[#e.cmds + 1] = c
            c.doc = true
          end
        elseif a.canon then
          local g0, b0 = maps[a.canon], bmaps[a.canon]
          -- DirDiff 절의 표 줄('<C-r> / <C-l>')은 DirDiff 가 감싼 전역 매핑과 묶는다.
          -- 안 묶으면 모드 칸이 빈 README 줄과 그 전역 매핑 줄이 따로 둘 나왔다.
          local sc = nil
          if g0 and not it.usage and not global_looking(a.canon) then
            local ip = table.concat(it.path, ' '):lower()
            local h1 = (it.hdr1 or ''):lower()
            for _, d in ipairs(g0.defs) do
              local s0 = scope_of(d)
              if s0 and ip:find(s0.sect, 1, true) and h1:find(s0.hdr, 1, true) then
                sc = s0
                break
              end
            end
          end
          if it.usage or global_looking(a.canon) or sc then
            -- 버퍼 매핑이 먼저다 (vim 도 그것을 먼저 쓴다). 다만 전역 매핑과 모드가
            -- 하나도 겹치지 않는 버퍼 매핑은 다른 매핑이다 - delimitMate 의 insert
            -- <C-H>(백스페이스)가 Ctrl+h(찾아 바꾸기) 줄의 모드 칸에 i 를 더했다.
            -- 그런 것은 묶지 않고 아래 2) 에 '이 버퍼' 줄로 따로 나온다.
            local gs = {}
            if b0 then
              local overlap = not g0
              for k in pairs(g0 and b0.modes or {}) do
                if g0.modes[k] then
                  overlap = true
                end
              end
              if overlap then
                gs[#gs + 1] = b0
              end
            end
            gs[#gs + 1] = g0
            -- DirDiff 표와 묶은 전역 매핑은 미리보기에도 감싼 정의만 (map_lines)
            if sc then
              e.scoped = e.scoped or {}
              e.scoped[g0] = true
            end
            for _, g in ipairs(gs) do
              if not seen[g] then
                seen[g] = true
                e.maps[#e.maps + 1] = g
                g.doc = true
                for _, d in ipairs(g.defs) do
                  -- DirDiff 표와 묶은 것은 감싼 정의의 모드만 (같은 키의 s/o 는 남의 일)
                  if not sc or scope_of(d) then
                    for k in pairs(d.modes) do
                      mset[k] = true
                    end
                  end
                end
              end
            end
          end
        end
      end
      e.mode = mode_str(mset)
      if e.mode == '' and #e.cmds > 0 then
        e.mode = ':'
      end
      out[#out + 1] = e
    end
  end

  -- 2) README 에 없는 매핑과 명령 - vim-ide 것이 먼저, 파일·줄 순서로
  local rest = {}
  -- 한 키에 정의한 곳(파일, 없으면 종류)이 다른 매핑이 섞여 있으면 곳마다 한 줄로 나눈다.
  -- 한 줄로 두었더니 모드 칸은 모두의 것, 설명·이름표는 첫 정의의 것이라 init.vim 의
  -- iunmap <Tab> 뒤 supertab 의 i <Tab> 이 'si  vim.snippet.jump ...  매핑 · nvim' 줄에
  -- 묻혀 'SuperTabForward' 로 찾이지 않았다
  local function by_source(g)
    local parts, at = {}, {}
    for _, d in ipairs(g.defs) do
      local k = d.path or (tostring(d.kind) .. '\0' .. tostring(d.label))
      local p = at[k]
      if not p then
        p = {}
        for f, v in pairs(g) do
          p[f] = v
        end
        p.defs, p.modes = {}, {}
        at[k] = p
        parts[#parts + 1] = p
      end
      p.defs[#p.defs + 1] = d
      for m in pairs(d.modes) do
        p.modes[m] = true
      end
    end
    if #parts < 2 then
      return { g }
    end
    for _, p in ipairs(parts) do
      p.mode = mode_str(p.modes)
      p.kind, p.label = p.defs[1].kind, p.defs[1].label
    end
    return parts
  end
  -- all: g:vimide_keyhelp_others 와 상관없이 다 (F1 을 누른 버퍼의 것 - ftplugin 의
  -- [[ ]], delimitMate, LSP 는 그 버퍼에서 실제로 먹는 키다)
  local function add_maps(order, where, all)
    for _, g0 in ipairs(order) do
      for _, g in ipairs(g0.doc and {} or by_source(g0)) do
        if all or others or g.kind == 'vimide' then
          local d = g.defs[1]
          rest[#rest + 1] = {
            src = 'map', g = g, keys = lhs_disp(g), mode = g.mode, desc = map_desc(d),
            where = where .. (g.label or '?'),
            -- .vimrc 가 먼저, 그다음 플러그인 파일 - 각각 정의한 줄 순서로
            rank = RANK[g.kind] or 2,
            sk = (g.label == '.vimrc' and '0' or '1') .. (d.path or '~') .. ('%08d'):format(d.line or 0) .. g.key
              .. '\0' .. (g.label or ''),
          }
        end
      end
    end
  end
  add_maps(border, '이 버퍼 · ', true)
  add_maps(morder, '매핑 · ')
  -- 명령도 매핑과 같은 규칙: vim-ide 것, 그 버퍼의 것(-buffer)은 늘, 플러그인과
  -- nvim 의 것은 g:vimide_keyhelp_others 가 켜져 있을 때. 각각 같은 종류의 매핑
  -- 바로 뒤에 온다.
  for cname, c in pairs(cmds) do
    if not c.doc and (c.kind == 'vimide' or c.buf or others) then
      local desc = one_line(c.def)
      if desc == '' and rd and rd.mentions[cname] then
        desc = clean(rd.lines[rd.mentions[cname]] or '')
      end
      rest[#rest + 1] = {
        src = 'cmd', c = c, keys = ':' .. cname, mode = ':', desc = desc,
        where = (c.buf and '이 버퍼 명령 · ' or '명령 · ') .. c.label,
        rank = (RANK[c.kind] or 2) + 0.5, sk = c.label .. cname,
      }
    end
  end
  table.sort(rest, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.sk < b.sk
  end)
  vim.list_extend(out, rest)
  return out, rd
end

-- ---------------------------------------------------------------------------
-- 파일 읽기 (미리보기·정의 줄 찾기) - mtime 으로 기억한다
-- ---------------------------------------------------------------------------

-- 두 번째 값은 그 줄들을 읽은 때의 stat_key (보기 창이 다시 채울지 정할 때 쓴다)
local fcache = {}
local function file_lines(p)
  local st = p and uv.fs_stat(p)
  if not st or st.type ~= 'file' then
    return nil
  end
  local key = stat_key(st)
  local c = fcache[p]
  if c and c.key == key then
    return c.lines, key
  end
  local f = io.open(p, 'rb')
  if not f then
    return nil
  end
  local data = f:read('*a')
  f:close()
  if not data then
    return nil
  end
  local lines = vim.split(data, '\n', { plain = true })
  fcache[p] = { key = key, lines = lines }
  return lines, key
end

-- Lua 로 건 매핑·명령은 nvim 이 줄을 적어 두지 않는다('verbose' 0 에서 건 것).
-- 파일에서 desc 나 키 글자, 명령 이름을 찾아 그 줄로 친다.
local function find_line(p, needles, cmdname)
  local lines = file_lines(p)
  if not lines then
    return 0
  end
  -- 명령은 정의하는 줄을 먼저 찾는다. 이름만 찾으면 vim 파일에서는 그 명령을
  -- 부르는 줄(call s:call('DirDiff', ...))에 먼저 걸린다.
  if cmdname then
    local pat = '%f[%w_]' .. cmdname .. '%f[^%w_]'
    for i, l in ipairs(lines) do
      if (l:find('^%s*com%a*!?%s') or l:find('create_user_command%s*%(')) and l:find(pat) then
        return i
      end
    end
  end
  for _, nd in ipairs(needles) do
    if nd and #nd >= 2 then
      for i, l in ipairs(lines) do
        if l:find(nd, 1, true) then
          return i
        end
      end
    end
  end
  return 0
end

local function def_line(g_or_c, d)
  if d.line and d.line > 0 then
    return d.line
  end
  if not d.path then
    return 0
  end
  if d.lfound == nil then
    if g_or_c.name then -- 명령
      local n = g_or_c.name
      d.lfound = find_line(d.path, { "'" .. n .. "'", '"' .. n .. '"' }, n)
    else
      local desc = d.desc and d.desc:sub(1, 24) or nil
      local lhs = g_or_c.lhs
      d.lfound = find_line(d.path, { desc, "'" .. lhs .. "'", '"' .. lhs .. '"' })
    end
  end
  return d.lfound
end

-- ---------------------------------------------------------------------------
-- 읽기 전용 보기 (README, 정의 파일) - 새 탭 하나를 돌려 쓴다
-- ---------------------------------------------------------------------------

local VIEW_VAR = 'vimide_keyhelp_view'

-- 곁창(트리, 패널)이나 부동 창에서 탭을 열면 새 창이 그 창의 옵션을 물려받고,
-- neo-tree 는 그 창을 제 것으로 가져간다. 편집 창으로 먼저 옮긴다.
local function to_edit_win()
  for _, f in ipairs({ _G.vimide_last_edit_win, _G.vimide_edit_slot }) do
    if type(f) == 'function' then
      local ok, w = pcall(f)
      if ok and type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w) then
        pcall(api.nvim_set_current_win, w)
        return
      end
    end
  end
end

-- 보기 버퍼 -> 그 보기를 연 자리 { tab, win }. q 는 거기로 돌아간다. 탭을 닫으면
-- nvim 은 오른쪽 탭으로 가서('tabclose' 기본), 맨 끝이 아닌 탭(DirDiff 탭 ...)에서
-- 연 README 를 q 로 닫으면 엉뚱한 옆 탭에 떨어졌다.
local view_from = {}

local function view_close(buf)
  local from = view_from[buf]
  view_from[buf] = nil
  if #api.nvim_list_wins() > 1 then
    pcall(vim.cmd, 'close')
  else
    pcall(vim.cmd, 'bwipeout')
  end
  if from and api.nvim_tabpage_is_valid(from.tab) then
    pcall(api.nvim_set_current_tabpage, from.tab)
    if api.nvim_win_is_valid(from.win) and api.nvim_win_get_tabpage(from.win) == from.tab then
      pcall(api.nvim_set_current_win, from.win)
    end
  end
end

local function open_view(path, lnum, ft)
  local lines, stamp = file_lines(path)
  if not lines then
    say('읽지 못함: ' .. vim.fn.fnamemodify(path, ':~'), vim.log.levels.WARN)
    return
  end
  local from = { tab = api.nvim_get_current_tabpage(), win = api.nvim_get_current_win() }
  local name = 'vimide-keys://' .. vim.fn.fnamemodify(path, ':~')
  -- 이미 떠 있는 보기 창이 있으면 그 창을 쓴다
  local win, buf = nil, nil
  for _, w in ipairs(api.nvim_list_wins()) do
    local b = api.nvim_win_get_buf(w)
    if vim.b[b][VIEW_VAR] then
      win = w
      if api.nvim_buf_get_name(b) == name then
        buf = b
      end
      break
    end
  end
  if not buf then
    for _, b in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_get_name(b) == name then
        buf = b
        break
      end
    end
  end
  if not buf then
    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(buf, name)
  end
  if vim.b[buf][VIEW_VAR] ~= stamp then
    local bo = vim.bo[buf]
    bo.buftype, bo.bufhidden, bo.swapfile = 'nofile', 'wipe', false
    bo.modifiable, bo.readonly = true, false
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    bo.modifiable, bo.readonly, bo.modified = false, true, false
    vim.b[buf][VIEW_VAR] = stamp
    pcall(function()
      bo.filetype = ft
    end)
    vim.keymap.set('n', 'q', function()
      view_close(buf)
    end, { buffer = buf, nowait = true, desc = '단축키 도움말 보기 닫고 F1 을 누른 자리로' })
  end
  -- 이미 떠 있는 보기를 다시 쓸 때도 돌아갈 자리는 이번 것
  if not (win and api.nvim_win_get_tabpage(win) == from.tab and win == from.win) then
    view_from[buf] = from
  end
  if win then
    api.nvim_set_current_win(win)
    if api.nvim_win_get_buf(win) ~= buf then
      api.nvim_win_set_buf(win, buf)
    end
  else
    to_edit_win()
    vim.cmd('tab sbuffer ' .. buf)
    win = api.nvim_get_current_win()
    -- to_edit_win() 이 F1 을 누른 탭의 지금 창을 편집 창으로 옮겼다 (트리 -> A 창).
    -- 그 탭에 돌아갔을 때 커서가 F1 을 누른 창에 있게 되돌린다.
    if api.nvim_tabpage_set_win and api.nvim_tabpage_is_valid(from.tab)
      and api.nvim_win_is_valid(from.win) and api.nvim_win_get_tabpage(from.win) == from.tab then
      pcall(api.nvim_tabpage_set_win, from.tab, from.win)
    end
  end
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  lnum = math.max(1, math.min(lnum or 1, api.nvim_buf_line_count(buf)))
  api.nvim_win_set_cursor(win, { lnum, 0 })
  vim.cmd('normal! zt')
end

-- ---------------------------------------------------------------------------
-- 미리보기
-- ---------------------------------------------------------------------------

local ns = api.nvim_create_namespace('vimide_keyhelp')

local function def_text(d, g_or_c)
  local where = d.path and vim.fn.fnamemodify(d.path, ':~')
    or (d.kind == 'nvim' and 'nvim 기본')
    or (d.label == '명령줄' and '명령줄에서 건 매핑')
    or 'Lua (정의한 파일을 모름)'
  local ln = def_line(g_or_c, d)
  where = where .. (ln > 0 and (':' .. ln) or '')
  if g_or_c.buf then
    where = where .. '   (이 버퍼에만)'
  end
  return where, ln
end

-- 감싼 매핑(SCOPED)이 그 밖에서 하는 일: '→ :wincmd l<CR>' 과 그 매핑을 건 자리,
-- 감싸기 전에 매핑이 없었으면 nvim 기본(:help 태그), 모르면 nil
local help_tag -- 아래 'nvim 기본 매핑의 :help 태그' 에서 정한다
local function prev_lines(g, d, sc)
  local p = d.prev
  if not p then
    return nil
  end
  if p.none then
    local tag = help_tag(g, { mode = d.mode })
    return sc.where .. ' - 그 밖에서는  →  nvim 기본' .. (tag and ('   (:help ' .. tag .. ')') or ''), nil
  end
  local rhs = (p.rhs and p.rhs ~= '' and p.rhs) or (p.callback and '(Lua 함수)') or ''
  local pd, force = { desc = p.desc }, nil
  pd.path, pd.line, force = def_source(p)
  pd.line = pd.line or 0
  local where = pd.path and vim.fn.fnamemodify(pd.path, ':~')
    or (force == 'nvim' and 'nvim 기본') or (force == 'cmdline' and '명령줄에서 건 매핑')
    or 'Lua (정의한 파일을 모름)'
  local ln = def_line({ lhs = p.lhs or g.lhs }, pd)
  return sc.where .. ' - 그 밖에서는  →  ' .. rhs .. (p.desc and p.desc ~= '' and ('   ' .. one_line(p.desc)) or ''),
    where .. (ln > 0 and (':' .. ln) or '') .. '   (감싸기 전의 매핑)'
end

-- 매핑 하나의 설명 줄들. only_scoped: 감싼 정의만 (DirDiff 표와 묶은 줄 - 같은 키의
-- s/o 매핑(:wincmd l)은 그 표의 이야기가 아니다)
local function map_lines(g, out, hl, only_scoped)
  local lhs = lhs_disp(g)
  for _, d in ipairs(g.defs) do
    local sc = scope_of(d)
    if sc or not only_scoped then
      local loc = def_text(d, g)
      local rhs = d.rhs and d.rhs ~= '' and d.rhs or (d.callback and '(Lua 함수)' or '')
      out[#out + 1] = ('%-4s %s  →  %s'):format(d.mode, lhs, rhs)
      -- 모드 칸은 4 칸 이상, 그다음 빈칸 하나, 그다음 키
      hl[#hl + 1] = { #out - 1, 0, math.max(4, #d.mode) + 1 + #lhs, 'Identifier' }
      if d.desc and d.desc ~= '' then
        out[#out + 1] = '     ' .. one_line(d.desc)
      end
      if sc and not (d.desc or ''):find('그 밖', 1, true) then
        local what, ploc = prev_lines(g, d, sc)
        out[#out + 1] = '     ' .. (what or (sc.where .. ' - 그 밖에서는 가로채기 전의 뜻 (매핑이 없었으면 nvim 기본)'))
        hl[#hl + 1] = { #out - 1, 0, -1, 'WarningMsg' }
        if ploc then
          out[#out + 1] = '     ' .. ploc
          hl[#hl + 1] = { #out - 1, 0, -1, 'Comment' }
        end
      end
      out[#out + 1] = '     ' .. loc
      hl[#hl + 1] = { #out - 1, 0, -1, 'Comment' }
    end
  end
end

local function cmd_lines(c, out, hl)
  local loc = def_text(c, c)
  local flags = {}
  if c.nargs and c.nargs ~= '0' then
    flags[#flags + 1] = 'nargs=' .. c.nargs
  end
  if c.bang then
    flags[#flags + 1] = 'bang'
  end
  if c.range and c.range ~= '' then
    flags[#flags + 1] = 'range'
  end
  out[#out + 1] = ':' .. c.name .. (#flags > 0 and ('   (' .. table.concat(flags, ', ') .. ')') or '')
  hl[#hl + 1] = { #out - 1, 0, #c.name + 1, 'Identifier' }
  if c.def ~= '' then
    out[#out + 1] = '     ' .. one_line(c.def)
  end
  out[#out + 1] = '     ' .. loc
  hl[#hl + 1] = { #out - 1, 0, -1, 'Comment' }
end

-- nvim 기본 매핑의 :help 태그. desc 가 ':help X' 면 X, 아니면 키와 모드에서
-- 만든다 - <C-W><C-D> -> CTRL-W_CTRL-D, x 모드의 gc -> v_gc, g* -> gstar,
-- ]<Space> -> ]<Space>. 실제로 있는 태그만 쓴다. 없는 태그로 :help 를 부르면
-- 비슷한 엉뚱한 곳이 열린다. ]q [d gcc gx gr* gO 의 desc 는 ':help' 로 시작하지
-- 않아서 예전에는 <CR> 이 '정의한 자리를 알 수 없습니다' 로 끝났다.
--
-- 있는지는 $VIMRUNTIME/doc/tags 를 한 번 읽어 둔 표로 본다 (nvim 기본 매핑의
-- 도움말은 다 거기 있다). 후보마다 getcompletion(x, 'help') 를 부르던 때는 한
-- 번에 10 ms 넘게 걸려서(도움말 태그 전부를 정규식으로 훑는다) 미리보기가 nvim
-- 기본 매핑 줄마다 20-60 ms 씩 멎었다.
local TAG_CHAR = { ['*'] = 'star', ['|'] = 'bar', ['"'] = 'quote' }
local TAG_PRE = { n = '', v = 'v_', x = 'v_', s = 'v_', o = 'o_', i = 'i_', c = 'c_', t = 't_' }
local tag_cache = {}
local help_tags = nil -- 태그 -> 도움말 파일 이름 (insert.txt)
local function help_file(t)
  if not help_tags then
    help_tags = {}
    local f = io.open(VIMRUNTIME .. 'doc/tags', 'rb')
    if f then
      for l in f:lines() do
        local k, file = l:match('^([^\t]+)\t([^\t]+)')
        if k then
          help_tags[k] = file
        end
      end
      f:close()
    end
  end
  return help_tags[t]
end
local function has_help_tag(t)
  return help_file(t) ~= nil
end
function help_tag(g, d)
  local hd = (d.desc or ''):match('^:help%s+(%S+)')
  if hd then
    return hd
  end
  local ck = (d.mode or '') .. '\0' .. g.key
  if tag_cache[ck] ~= nil then
    return tag_cache[ck] or nil
  end
  local parts, i, k = {}, 1, g.key
  while i <= #k do
    local tok = k:match('^<[^<>]+>', i)
    if tok then
      local c = tok:match('^<C%-(.+)>$')
      parts[#parts + 1] = { c and ('CTRL-' .. c:upper()) or tok, c and 'ctrl' or 'key' }
      i = i + #tok
    else
      local ch = k:sub(i, i)
      parts[#parts + 1] = { TAG_CHAR[ch] or ch, false }
      i = i + 1
    end
  end
  -- CTRL-x 의 앞뒤는 '_' 로 잇는다 (CTRL-W_CTRL-D, g_CTRL-], CTRL-W_<Down>).
  -- 다른 <..> 는 그대로 붙인다 (]<Space>, z<CR>, g<Down>). 앞의 것이 맞지 않는
  -- 태그를 위해 <..> 앞뒤를 모두 '_' 로 이은 것도 본다.
  local function join(all)
    local tag = ''
    for n, pt in ipairs(parts) do
      local prev = parts[n - 1]
      if n > 1 and (pt[2] == 'ctrl' or prev[2] == 'ctrl' or (all and (pt[2] or prev[2]))) then
        tag = tag .. '_'
      end
      tag = tag .. pt[1]
    end
    return tag
  end
  local tags = { join(false) }
  local t2 = join(true)
  if t2 ~= tags[1] then
    tags[2] = t2
  end
  -- 매핑의 모드마다 그 모드의 머리(v_ i_ ...)를 붙여 본다. 's' 가 'i' 를 가리던
  -- 때는 si 모드의 <C-S> 가 i_CTRL-S 를 못 찾았다.
  local pres, seenp = {}, {}
  for mc in (d.mode or ''):gmatch('.') do
    local pre = TAG_PRE[mc]
    if pre and not seenp[pre] then
      seenp[pre] = true
      pres[#pres + 1] = pre
    end
  end
  local cands = {}
  for _, pre in ipairs(pres) do
    for _, tg in ipairs(tags) do
      cands[#cands + 1] = pre .. tg .. '-default'
    end
  end
  for _, pre in ipairs(pres) do
    for _, tg in ipairs(tags) do
      cands[#cands + 1] = pre .. tg
    end
  end
  -- desc 에 든 Lua 함수 이름 ('vim.snippet.jump if active ...')
  for w in (d.desc or ''):gmatch('[%w_]+%.[%w_.]+') do
    w = w:gsub('%.$', '')
    cands[#cands + 1] = w .. '()'
    cands[#cands + 1] = w
  end
  -- 머리 없는 태그는 '-default' 만. normal 모드 것은 위에서 이미 봤다 - 그 밖의
  -- 모드에서 맨 키 태그(<Tab> = 점프 목록의 CTRL-I)를 쓰면 엉뚱한 곳이 열린다.
  for _, tg in ipairs(tags) do
    cands[#cands + 1] = tg .. '-default'
  end
  local found = false
  for _, c in ipairs(cands) do
    if has_help_tag(c) then
      found = c
      break
    end
  end
  tag_cache[ck] = found
  return found or nil
end

-- 미리보기 버퍼에 쓸 줄, 강조, (정의 파일이면) 파일 종류
local function preview_of(e, rd)
  local out, hl = {}, {}
  local function title(s)
    out[#out + 1] = s
    hl[#hl + 1] = { #out - 1, 0, -1, 'Title' }
  end
  local function rule(s)
    out[#out + 1] = ''
    out[#out + 1] = '── ' .. s .. ' ──'
    hl[#hl + 1] = { #out - 1, 0, -1, 'Comment' }
  end
  -- 이 줄이 가리키는 절('see *Views* below', 보기 메뉴의 Views)의 표
  local function ref_part(ref)
    if not (ref and rd) then
      return
    end
    rule(('README.md:%d  %s'):format(ref.lnum, ref.text))
    local last = math.min(ref.lend, ref.lnum + 40)
    while last > ref.lnum and (rd.lines[last] or ''):find('^%s*$') do
      last = last - 1
    end
    for k = ref.lnum + 1, last do
      out[#out + 1] = rd.lines[k] or ''
    end
  end
  -- README 쪽: 절 제목, 그 항목의 줄(표면 키와 뜻), README 의 줄 번호
  local function readme_part(it)
    title(table.concat(it.path, '  ›  ') .. (it.hdr1 and it.hdr1 ~= '' and ('  ·  ' .. it.hdr1) or ''))
    out[#out + 1] = ''
    if it.style == 'table' then
      out[#out + 1] = it.keys
      hl[#hl + 1] = { #out - 1, 0, -1, 'Identifier' }
      out[#out + 1] = '    ' .. it.cell
    elseif rd then
      for k = it.lnum, it.lend do
        out[#out + 1] = rd.lines[k] or ''
      end
      -- 키 칸('F1:' 의 F1, '\fm: ...    \fS: ...' 의 \fS)을 칠한다
      local raw = rd.lines[it.lnum] or ''
      if it.keys ~= '' and it.kc1 and it.kc1 > (it.kc0 or 0) then
        hl[#hl + 1] = { 2, it.kc0 or 0, math.min(#raw, it.kc1), 'Identifier' }
      end
    end
    out[#out + 1] = ''
    out[#out + 1] = ('README.md:%d   (<CR> 로 그 자리를 연다)'):format(it.lnum)
    hl[#hl + 1] = { #out - 1, 0, -1, 'Comment' }
    ref_part(it.ref)
  end
  if e.src == 'map' and e.it then
    readme_part(e.it)
    rule('이 창의 매핑')
    map_lines(e.g, out, hl)
    return out, hl
  end
  if e.src == 'readme' then
    local it = e.it
    readme_part(it)
    if #e.maps > 0 or #e.cmds > 0 then
      rule('실제 매핑')
      for _, g in ipairs(e.maps) do
        map_lines(g, out, hl, e.scoped and e.scoped[g])
      end
      for _, c in ipairs(e.cmds) do
        cmd_lines(c, out, hl)
      end
    elseif it.usage and #it.alts > 0 then
      rule('지금 걸린 매핑·명령 없음 (전역과 F1 을 누른 버퍼)')
      out[#out + 1] = '특정 창(트리, 패널 ...)이나 다른 버퍼에서만 먹는 키이거나, README 가 낡은 것일 수 있다.'
    end
    return out, hl
  end
  local d, path, line, obj
  if e.src == 'map' then
    obj = e.g
    map_lines(e.g, out, hl)
    ref_part(e.ref)
    d = e.g.defs[1]
  else
    obj = e.c
    cmd_lines(e.c, out, hl)
    d = e.c
  end
  path = d.path
  line = def_line(obj, d)
  -- README 에 이 이름이 나오면 그 줄도 (README 표·목록에는 없지만 본문에 있는 것)
  if e.src == 'cmd' and rd and rd.mentions[e.c.name] then
    local ml = rd.mentions[e.c.name]
    rule(('README.md:%d 에서'):format(ml))
    for k = ml, math.min(ml + 2, #rd.lines) do
      out[#out + 1] = rd.lines[k]
    end
  end
  local lines = path and file_lines(path)
  if lines and line > 0 then
    rule(vim.fn.fnamemodify(path, ':t') .. ':' .. line)
    local from = math.max(1, line - 3)
    local base = #out
    for k = from, math.min(#lines, line + 60) do
      out[#out + 1] = lines[k]
    end
    hl[#hl + 1] = { base + (line - from), 0, -1, 'TelescopePreviewLine' }
    return out, hl, base
  elseif d.kind == 'nvim' and e.src == 'map' then
    local tag = help_tag(e.g, d)
    rule('nvim 기본 매핑')
    out[#out + 1] = tag and ('<CR> 로 :help ' .. tag) or '(:help 태그를 찾지 못했습니다)'
  end
  return out, hl
end

-- ---------------------------------------------------------------------------
-- 창
-- ---------------------------------------------------------------------------

-- <C-y> 로 복사할 키: vim 표기(<F12>, <C-]>, \fo)가 있으면 그것 - 매핑에 붙여
-- 쓰기 좋다. 'Ctrl+M twice' 처럼 vim 표기가 없는 것은 README 글자 그대로.
local function key_of(e)
  if e.src == 'cmd' then
    return ':' .. e.c.name
  end
  if e.src == 'map' then
    return e.g.key
  end
  local a = e.it.alts[1]
  return a and (a.canon or a.disp) or e.keys
end

-- 이 항목이 가리키는 파일과 줄 (<C-q>/<M-q> 로 quickfix 에 보낼 때)
local function loc_of(e, rd)
  if e.it and rd then
    return rd.file, e.it.lnum
  end
  if e.src == 'map' then
    local d = e.g.defs[1]
    return d.path, d.path and def_line(e.g, d) or 0
  end
  if e.src == 'cmd' and e.c.path then
    return e.c.path, def_line(e.c, e.c)
  end
  return nil, 0
end

-- F1 을 누른 창이 목록이 떠 있는 동안 없어졌으면 그 창의 앞 창으로 간다. DirDiff 의
-- 보기 메뉴는 떠나면 스스로 닫혀서, telescope 가 그 탭의 아무 창(A 편집 창)에 내려
-- 놓았다 - 앞 창은 메뉴를 연 트리다. 옮겼으면 true.
local function to_prev_win(back)
  if back and not api.nvim_win_is_valid(back.win) and back.prev and api.nvim_win_is_valid(back.prev) then
    return pcall(api.nvim_set_current_win, back.prev)
  end
  return false
end

local function do_enter(e, rd, back)
  -- README·정의 보기의 q 가 돌아갈 자리, ':명령 ' 을 부를 자리도 그 창이다
  to_prev_win(back)
  -- 프롬프트는 insert 모드라, 닫은 직후에는 아직 insert 일 수 있다 (nvim 은
  -- 프롬프트 창을 떠난 뒤에야 insert 를 끝낸다). 그대로 탭을 열면 읽기 전용
  -- 버퍼에서 insert 가 이어지고, ':명령 ' 은 명령줄이 아니라 본문에 찍힌다.
  local insert = api.nvim_get_mode().mode:find('^i') ~= nil
  if e.src == 'cmd' then
    local k = ':' .. e.c.name .. ' '
    if insert then
      k = api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true) .. k
    end
    api.nvim_feedkeys(k, 'n', false)
    return
  end
  if insert then
    vim.cmd('stopinsert')
  end
  if e.src == 'readme' or e.it then
    if rd then
      open_view(rd.file, e.it.lnum, 'markdown')
    end
    return
  end
  local d = e.g.defs[1]
  local line = def_line(e.g, d)
  if d.path then
    open_view(d.path, line, d.path:find('%.lua$') and 'lua' or 'vim')
    return
  end
  local tag = d.kind == 'nvim' and help_tag(e.g, d)
  -- 알림은 짧게 (80 칸 화면에서도 한 줄 - fit() 참고)
  if tag then
    pcall(vim.cmd, 'help ' .. tag)
    -- 같은 태그가 플러그인 도움말에도 있으면(vim-unimpaired 의 ]<Space>) :help 가
    -- 그쪽을 열기도 한다 - nvim 기본 매핑이니 nvim 의 도움말 파일에서 찾는다
    local file = help_file(tag)
    if file and vim.bo.buftype == 'help' and vim.fn.fnamemodify(api.nvim_buf_get_name(0), ':t') ~= file
      and pcall(vim.cmd, 'help ' .. file) then
      vim.fn.search('\\V*' .. vim.fn.escape(tag, '\\') .. '*', 'w')
      vim.cmd('normal! zt')
    end
  elseif d.kind == 'nvim' then
    say(('%s: nvim 기본 매핑 (:help 태그 없음)'):format(lhs_disp(e.g)))
  elseif d.label == '명령줄' then
    say(('%s: 명령줄에서 건 매핑 (파일 없음)'):format(lhs_disp(e.g)))
  else
    say(('%s: 정의한 파일을 모릅니다 (Lua 매핑)'):format(lhs_disp(e.g)))
  end
end

local function telescope()
  local ok = pcall(require, 'telescope')
  if not ok then
    return nil
  end
  return {
    pickers = require('telescope.pickers'),
    finders = require('telescope.finders'),
    conf = require('telescope.config').values,
    actions = require('telescope.actions'),
    state = require('telescope.actions.state'),
    previewers = require('telescope.previewers'),
    putils = require('telescope.previewers.utils'),
    display = require('telescope.pickers.entry_display'),
  }
end

-- 목록 프롬프트 버퍼 -> 고르지 않고 닫았을 때 돌아갈 자리
-- { win, cur, insert, visual, prev } (insert: 'i', 'R', 'Rv' 또는 nil - 아래
-- insert_kind(), visual: 'v', 'V', CTRL-V 또는 nil, prev: F1 을 누른 창의 앞 창 -
-- 그 창이 없어졌을 때 가고, 돌아온 창의 앞 창(wincmd p)으로도 되돌린다).
-- 이 목록 안에서 F1 을 다시 누르면 새 목록이 물려받는다.
local prompt_back = {}

-- 높은 부동 창(zindex > 50: Ctrl+g/Ctrl+/ 의 입력 창, Ctrl+h 의 찾아 바꾸기 창은
-- 200, DirDiff 의 보기 메뉴는 60)은 telescope 창(50)보다 위에 그려져서, 그 안에서
-- 누른 F1 목록의 가운데를 가렸다. 초점을 옮겨도 그리는 순서는 zindex 라 소용없다.
-- 목록이 떠 있는 동안 숨긴다 (nvim 0.10+). 그보다 옛 nvim 은 목록 창을 그 위로
-- 올린다. 돌려주는 것: 되돌리는 함수, 올릴 zindex (옛 nvim 이고 높은 창이 있을 때)
-- DirDiff 의 보기 메뉴는 숨겨도 프롬프트로 옮겨 가는 순간(WinLeave) 스스로 닫힌다 -
-- 되살릴 것이 없고, 닫은 뒤에는 back.prev(메뉴를 연 트리)로 간다.
local function hide_floats()
  local hidden, top = {}, nil
  local can_hide = vim.fn.has('nvim-0.10') == 1
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local ok, cfg = pcall(api.nvim_win_get_config, w)
    if ok and cfg.relative and cfg.relative ~= '' and (cfg.zindex or 50) > 50 and not cfg.hide then
      if can_hide then
        if pcall(api.nvim_win_set_config, w, { hide = true }) then
          hidden[#hidden + 1] = w
        end
      else
        top = math.max(top or 0, cfg.zindex + 1)
      end
    end
  end
  return function()
    for _, w in ipairs(hidden) do
      if api.nvim_win_is_valid(w) then
        pcall(api.nvim_win_set_config, w, { hide = false })
      end
    end
    hidden = {}
  end, top
end

-- 닫은 뒤 다시 들어갈 insert 의 종류 (back.insert): 'i', 'R', 'Rv'(gR 의 virtual
-- replace) 또는 nil. 'Rv' 를 'R' 로 줄이면 gR 에서 누른 F1 이 보통 R 로 돌아왔다.
-- i_CTRL-O 로 잠깐 나온 normal('niI', 'niR', 'niV')은 그 insert 로 친다.
local function insert_kind(mode)
  if mode:find('^Rv') or mode:find('^niV') then
    return 'Rv'
  elseif mode:find('^R') or mode:find('^niR') then
    return 'R'
  elseif mode:find('^i') or mode:find('^niI') then
    return 'i'
  end
  return nil
end

local function open(force, back0)
  -- 명령줄 창(q:)에서는 다른 창으로 갈 수 없다 (E11). telescope 가 그 오류를
  -- traceback 째로 냈다.
  -- 닫는 키는 :q 다 - vim-ide 에서는 normal 의 Ctrl+c 가 다른 일(RvUnpin)이라
  -- 이 창을 닫지 않는다. insert 모드에서는 바로 다시 그리는 '-- INSERT --' 가
  -- 메시지를 지워서 아무것도 안 보였다 - insert 를 끝내고 다음 틈에 띄운다.
  if vim.fn.getcmdwintype() ~= '' then
    local msg = 'vim-ide: q: 창에서는 F1 을 못 엽니다 - :q 로 닫고 F1'
    if api.nvim_get_mode().mode:find('^i') then
      vim.cmd('stopinsert')
      vim.defer_fn(function()
        say(msg, vim.log.levels.WARN)
      end, 0)
    else
      say(msg, vim.log.levels.WARN)
    end
    return
  end
  -- 다른 telescope 창 안에서 누르면 그 창을 먼저 닫는다 (창 위에 창). 닫기 전에
  -- 그 프롬프트의 매핑을 읽어 둔다 - 열기, 여러 개 고르기, quickfix 로 보내기
  -- 같은 키는 프롬프트 버퍼에만 걸려 있어서 전역 매핑으로는 보이지 않는다.
  --
  -- back: 고르지 않고 닫을 때(Esc, Ctrl+c) 돌아갈 자리. F1 을 insert 모드에서
  -- 눌렀으면 그 자리에서 insert 로 돌아간다 - 프롬프트는 프롬프트 버퍼라 nvim 이
  -- 그 창을 떠나면서 insert 를 끝내고, telescope 도 되살리지 않아서 normal 모드에
  -- 커서가 한 칸 왼쪽에 남았다 (다음에 친 글자가 명령으로 돌았다). visual 모드면
  -- 같은 영역을 다시 고른다 (x 의 F1 은 <Cmd> 라 모드와 커서가 그대로 여기 온다.
  -- '< '> 는 프롬프트로 옮겨 갈 때 nvim 이 적어 둔다).
  local pre, back = nil, nil
  if vim.bo.filetype == 'TelescopePrompt' then
    local pb = api.nvim_get_current_buf()
    local _, order = collect_maps(buf_keymap(pb), { 'i', 'n' }, true)
    local mine = vim.b[pb].vimide_keyhelp_prompt == true
    pre = { order = order, ft = 'TelescopePrompt', name = mine and '단축키 도움말' or 'telescope',
      keyhelp = mine }
    back = prompt_back[pb]
    if not back then
      -- 다른 목록(\ff ...): 그 목록을 연 창과 그때의 모드
      local okp, pk = pcall(function()
        return require('telescope.actions.state').get_current_picker(pb)
      end)
      local w = okp and pk and pk.original_win_id
      if w and api.nvim_win_is_valid(w) then
        back = { win = w, cur = api.nvim_win_get_cursor(w),
          insert = insert_kind(pk._original_mode or '') }
      end
    end
    pcall(function()
      require('telescope.actions').close(pb)
    end)
  elseif back0 then
    -- 아래 i_CTRL-O 길에서 다음 틈에 다시 부른 것 - 자리는 그때 적어 둔 것
    back = back0
  else
    -- insert: insert_kind() (replace 모드에도 imap 이 걸린다)
    local mode = api.nvim_get_mode().mode
    local pn = vim.fn.winnr('#')
    back = { win = api.nvim_get_current_win(), cur = api.nvim_win_get_cursor(0),
      insert = insert_kind(mode), visual = mode:match('^[vV\22]'),
      prev = pn > 0 and vim.fn.win_getid(pn) or nil }
    -- i_CTRL-O 다음의 F1: nvim 은 이 명령이 끝나면 insert 를 다시 시작하는데,
    -- 그 사이 커서는 telescope 프롬프트에 가 있다 - 프롬프트에 'A' 가 찍혀 목록이
    -- 'A' 로 걸러졌고, 닫으면 insert 가 아니라 normal 로 돌아왔다. 여기서 그
    -- 재시작을 끄고(stopinsert) 다음 틈에 연다. 돌아갈 자리는 지금 것이다 -
    -- 줄 끝에서 누른 CTRL-O 는 커서가 줄 끝 너머에 있어서 그대로 startinsert! 가 된다.
    if mode:find('^ni[IRV]') then
      vim.cmd('stopinsert')
      vim.schedule(function()
        if api.nvim_win_is_valid(back.win) and api.nvim_get_current_win() == back.win then
          open(force, back)
        end
      end)
      return
    end
  end
  local t = telescope()
  if not t then
    if vim.fn.exists('*VimIdeKeyHelpBuf') == 1 then
      vim.fn.VimIdeKeyHelpBuf()
    else
      say('vim-ide: telescope 가 없어 F1 목록을 못 엽니다', vim.log.levels.WARN)
    end
    return
  end
  if force then
    rcache, fcache = nil, {}
  end
  local origin_buf = api.nvim_get_current_buf()
  local entries, rd = build(origin_buf, pre, api.nvim_get_current_win())
  -- README 를 못 읽었다는 알림은 메시지 줄로는 보이지 않는다 - 곧 뜨는 프롬프트의
  -- '-- INSERT --' 가 바로 덮는다 (:messages 에만 남았다). 프롬프트 제목에도 적는다.
  local title = ('단축키 도움말 (%d개)   <CR> 열기   <C-y> 키 복사'):format(#entries)
  if not rd then
    say('vim-ide: README.md 가 없어 매핑과 명령만 보입니다', vim.log.levels.WARN)
    title = ('단축키 도움말 (%d개) - README.md 가 없어 매핑과 명령만'):format(#entries)
  end

  -- 키 칸: 가장 긴 키에 맞추되 16 칸까지. 설명 칸이 제일 넓어야 읽힌다.
  local kw = 6
  for _, e in ipairs(entries) do
    kw = math.max(kw, vim.fn.strdisplaywidth(e.keys))
    if kw >= 16 then
      kw = 16
      break
    end
  end
  local picker
  local displayer, dw_for
  local function make_display(ent)
    local e = ent.value
    local w = 100
    if picker and picker.results_win and api.nvim_win_is_valid(picker.results_win) then
      w = api.nvim_win_get_width(picker.results_win)
    end
    if not displayer or dw_for ~= w then
      local ww = math.max(10, math.min(22, math.floor(w * 0.2)))
      -- 선택 표시('> ') 2 칸, 칸 사이 3 칸, 그리고 한 칸 여유 (넘치면 오른쪽 칸이
      -- 창 테두리에서 잘린다)
      local dw = math.max(10, w - kw - 4 - ww - 2 - 3 - 1)
      displayer = t.display.create({
        separator = ' ',
        items = { { width = kw }, { width = 4 }, { width = dw }, { width = ww } },
      })
      dw_for = w
    end
    local whl = e.src == 'readme' and 'TelescopeResultsComment' or 'TelescopeResultsConstant'
    if e.local_ then
      whl = 'TelescopeResultsFunction'
    end
    return displayer({
      { e.keys, 'TelescopeResultsIdentifier' },
      { e.mode or '', 'TelescopeResultsSpecialComment' },
      e.desc or '',
      { e.where or '', whl },
    })
  end
  -- <C-q>/<M-q>(.vimrc 의 telescope 설정)는 항목의 filename/lnum/text 로
  -- quickfix 를 만든다. 없으면 value(표)를 글자로 쓰려다 E731 로 죽었다.
  -- README 항목은 README 의 그 줄, 매핑·명령은 정의한 줄 - 고를 때만 계산한다.
  -- 정의한 곳을 모르는 줄(nvim 의 Lua 기본 매핑, Lua·명령줄 매핑, Lua 플러그인의
  -- 명령)은 줄 번호를 0 으로 준다 - 파일도 줄도 없는 항목이라 quickfix 가 글만
  -- 있는 항목(valid 0, '|| ...')으로 받는다. 1 을 주었더니 bufnr 0 의 '유효한'
  -- 항목이 되어, :cc 나 Enter 가 지금 버퍼의 1 줄로 뛰었다.
  local QF = {
    filename = function(ent)
      return (loc_of(ent.value, rd)) or ''
    end,
    lnum = function(ent)
      local f, l = loc_of(ent.value, rd)
      if not f then
        return 0
      end
      return (l and l > 0) and l or 1
    end,
    text = function(ent)
      local e = ent.value
      return one_line((e.keys ~= '' and (e.keys .. '  ') or '') .. (e.desc or '') .. '  [' .. (e.where or '') .. ']')
    end,
  }
  local entry_mt = {
    __index = function(ent, k)
      local f = QF[k]
      return f and f(ent) or nil
    end,
  }
  local function make_entry(e)
    local extra = ''
    -- 이 항목의 키 이름들 (아래 sorter 가 '친 글자 = 키' 를 맨 위로 올릴 때 쓴다)
    local keys = {}
    local single = nil -- 키가 하나뿐인 줄의 그 키 (vim 표기)
    local it = e.it
    local alias = {}
    -- vim 표기 키에 README 표기 이름을 붙인다 (Shift+Tab, Ctrl+r)
    local function add_alias(k, disp)
      local lo, up = readme_style(k)
      if lo and lo:lower() ~= (disp or ''):lower() then
        keys[#keys + 1] = lo
        alias[#alias + 1] = lo
        alias[#alias + 1] = up
      end
    end
    if e.src == 'readme' then
      local c = {}
      for _, a in ipairs(it.alts) do
        c[#c + 1] = a.canon or ''
        keys[#keys + 1] = a.disp
        if a.canon then
          keys[#keys + 1] = a.canon
          add_alias(a.canon, a.disp)
        end
        if a.cmd then
          keys[#keys + 1] = a.cmd
        end
      end
      single = #it.alts == 1 and it.alts[1].canon or nil
      extra = table.concat(c, ' ') .. ' ' .. table.concat(it.path, ' ')
    elseif e.src == 'map' then
      extra = e.g.key .. ' map'
      keys = { e.g.lhs, e.g.key }
      add_alias(e.g.key, e.g.lhs)
      single = e.g.key
    else
      extra = 'command'
      keys = { ':' .. e.c.name, e.c.name }
    end
    if #alias > 0 then
      extra = extra .. ' ' .. table.concat(alias, ' ')
    end
    -- 찾기는 README 본문 전체로 (화면에는 첫 문장만). README 와 묶인 매핑의 desc 도
    -- 넣는다 - 트리의 f('보기 고르기')가 README 글만으로는 '고르기' 로 안 찾였다.
    local text = it and it.body or e.desc or ''
    if e.ref then
      -- 보기 메뉴의 줄: Views 표의 보기 이름과 id ('최신', 'right-newer')로도 찾인다
      text = text .. ' ' .. e.ref.body
    end
    if e.src == 'map' and it then
      text = text .. ' ' .. map_desc(e.g.defs[1])
    elseif e.src == 'map' then
      -- 한 줄에 묶인 같은 곳의 다른 정의(gc 의 o 'Comment textobject', <CR> 의 c)도
      -- 제 글로 찾이게
      for i = 2, #e.g.defs do
        text = text .. ' ' .. map_desc(e.g.defs[i])
      end
    elseif e.src == 'readme' and #e.maps > 0 then
      local ds = {}
      for _, g in ipairs(e.maps) do
        for _, d in ipairs(g.defs) do
          if d.desc and d.desc ~= '' then
            ds[#ds + 1] = one_line(d.desc)
          end
        end
      end
      text = text .. ' ' .. table.concat(ds, ' ')
    end
    return setmetatable({
      value = e,
      display = make_display,
      ordinal = table.concat({ e.keys, e.mode or '', text, e.where or '', extra }, ' '),
      keys = keys,
      bkeys = it and it.bkeys or nil,
      single = single,
    }, entry_mt)
  end

  -- 친 글자가 어떤 항목의 키와 똑같으면 그 항목이 맨 위다. fuzzy 점수만으로는
  -- '\fo' 를 쳤을 때 설명에 '\fo' 가 든 F3 줄과 '\fo / F3' 줄이 같은 점수라,
  -- README 순서대로 F3 이 먼저 왔다. 점수는 작을수록 위다 (-1 = 걸러짐).
  local sorter = t.conf.generic_sorter({})
  local score = sorter.scoring_function
  local pcanon = {}
  sorter.scoring_function = function(self, prompt, line, entry, ...)
    local sc = score(self, prompt, line, entry, ...)
    local p = prompt and trim(prompt) or ''
    if sc and p ~= '' and entry and entry.keys then
      -- 친 글자를 vim 표기로. 두 가지: vim 표기 그대로 맞추기('<c-]>' -> '<C-]>')와
      -- README 표기 읽기('ctrl+]' -> '<C-]>', 'Shift+Tab' -> '<S-Tab>',
      -- 'Space' -> '<Space>'). 항목마다 하지 않게 기억한다.
      local pc = pcanon[p]
      if pc == nil then
        local a = parse_alt(p)
        pc = { canon(p) or false, a and a.canon or false }
        pcanon[p] = pc
      end
      local c1, c2 = pc[1], pc[2]
      -- fuzzy(fzf)는 smart case 라 친 글자에 대문자가 하나라도 있으면('<C-' 의 C) 글자
      -- 크기까지 맞춘다. 항목에는 vim 표기가 keytrans 모양(<C-G>, H)으로만 들어 있어서
      -- README 가 쓰는 '<C-g>', '<C-w>H', '<S-h>', 'CTRL+G' 로 치면 그 키의 줄이 걸러졌다.
      -- 키가 똑같은 줄은 그 키(vim 표기)로 친 것처럼 다시 점수를 매긴다
      if sc < 0 then
        local x1, x2, hit = c1 ~= p and c1, c2 ~= p and c2, nil
        if x1 or x2 then
          for _, k in ipairs(entry.keys) do
            if k == x1 or k == x2 then
              hit = k
              break
            end
          end
        end
        if not hit then
          return sc
        end
        sc = score(self, hit, line, entry, ...)
        if not sc or sc < 0 then
          return sc
        end
      end
      local pl = p:lower()
      local function same(k)
        return k == p or (c1 and k == c1) or (c2 and k == c2)
      end
      local best = 1
      -- 키 칸 전체가 친 글자와 같으면 ('Ctrl+]', 'ctrl+]', '<C-]>') 그 키가 여럿 중
      -- 하나인 줄('gf / Ctrl+]', 'Ctrl+] / double click')보다 위다.
      -- 글자 크기까지 같은 키가 그보다 먼저다. 크기만 다른 키(']Q' 와 ']q', 트리의
      -- 'F' 와 'f')도 같은 점수를 받아서, fuzzy 점수까지 같은(smart case) 소문자로
      -- 치면 모은 순서(대문자가 앞)대로 ']q' 를 친 사람에게 ']Q' 가 먼저 왔다.
      -- 크기만 다른 줄은 0.0045: 아래에서 F1 을 누른 창의 줄이라 반을 깎아도
      -- (0.00225) 크기까지 같은 줄(0.002)보다는 아래, 키가 여럿인 줄(0.005,
      -- 0.01)보다는 위다 (DirDiff 트리에서 'r' 을 치면 트리의 'R' 보다 'r' 줄이 먼저).
      local ev = entry.value
      local ek = ev and type(ev.keys) == 'string' and ev.keys or nil
      if (ek and same(ek)) or (entry.single and same(entry.single)) then
        best = 0.002
      elseif ek and ek:lower() == pl then
        best = 0.0045
      end
      for _, k in ipairs(entry.keys) do
        if same(k) then
          best = math.min(best, 0.01)
        elseif k:lower() == pl then
          best = math.min(best, 0.05)
        elseif k:lower():sub(1, #pl) == pl then
          best = math.min(best, 0.3)
        end
      end
      -- 본문에만 나오는 키(F9 의 `w`, 패널의 `i+`)는 그 키의 줄보다는 아래,
      -- 그냥 글자가 비슷한 줄보다는 위
      if best == 1 and entry.bkeys then
        for _, k in ipairs(entry.bkeys) do
          if same(k) then
            best = 0.15
            break
          elseif k:lower() == pl then
            best = 0.2
          end
        end
      end
      -- 키가 맞은 줄끼리는 F1 을 누른 창의 것이 위 (트리의 <Tab> 이 neo-tree 나
      -- telescope 표의 Tab 보다)
      if best < 1 and ev and ev.local_ then
        best = best * 0.5
      end
      sc = sc * best
    end
    return sc
  end

  local previewer = t.previewers.new_buffer_previewer({
    title = '설명',
    define_preview = function(self, ent)
      local e = ent.value
      local lines, hls, code_from = preview_of(e, rd)
      local b = self.state.bufnr
      api.nvim_buf_set_lines(b, 0, -1, false, lines)
      api.nvim_buf_clear_namespace(b, ns, 0, -1)
      -- 정의 파일을 붙였으면 그 파일 종류로 칠한다. 그 위의 설명 줄은 코드가
      -- 아니라서 맨 글자색으로 덮는다 (아래 강조가 그 위에 다시 칠한다).
      local d = e.src == 'map' and e.g.defs[1] or (e.src == 'cmd' and e.c) or nil
      if code_from and d and d.path then
        pcall(t.putils.highlighter, b, d.path:find('%.lua$') and 'lua' or 'vim')
        -- 글자색만 Normal 로 (배경은 그대로 - 뜬 창의 배경이 Normal 과 다를 수 있다)
        local ok, n = pcall(api.nvim_get_hl, 0, { name = 'Normal', link = false })
        n = ok and n or {}
        pcall(api.nvim_set_hl, 0, 'VimIdeKeyHelpPlain', { fg = n.fg, ctermfg = n.ctermfg })
        for r = 0, code_from - 1 do
          pcall(api.nvim_buf_set_extmark, b, ns, r, 0, { end_row = r,
            end_col = #(lines[r + 1] or ''), hl_group = 'VimIdeKeyHelpPlain', priority = 150 })
        end
      end
      for _, h in ipairs(hls) do
        local c1 = h[3]
        if c1 < 0 then
          c1 = #(lines[h[1] + 1] or '')
        end
        pcall(api.nvim_buf_set_extmark, b, ns, h[1], h[2],
          { end_row = h[1], end_col = c1, hl_group = h[4], priority = 200 })
      end
      local w = self.state.winid
      if w and api.nvim_win_is_valid(w) then
        vim.wo[w].wrap, vim.wo[w].linebreak, vim.wo[w].breakindent = true, true, true
      end
    end,
  })

  local unhide, raise = function() end, nil
  local chosen = false
  -- <C-y> 가 바꾼 프롬프트 제목: 되돌릴 차례(마지막 것만)와 원래 제목
  local flash_n, title0 = 0, nil
  picker = t.pickers.new({}, {
    prompt_title = title,
    finder = t.finders.new_table({ results = entries, entry_maker = make_entry }),
    sorter = sorter,
    previewer = previewer,
    -- 점수가 같으면 모은 순서(이 창 -> Usage -> 다른 절 -> vim-ide 매핑·명령 ->
    -- 플러그인 -> nvim)를 지킨다. 기본 tiebreak 는 짧은 글자를 앞으로 올린다.
    tiebreak = function()
      return false
    end,
    -- README 는 80 칸 안쪽으로 감아 적었다. 미리보기가 그보다 좁으면 줄마다
    -- 꼬리가 한 낱말씩 넘어가 읽기 어렵다 - 되는 만큼 82 칸을 준다.
    layout_config = {
      horizontal = {
        preview_width = function(_, cols)
          return math.min(math.max(82, math.floor(cols * 0.42)), math.floor(cols * 0.55))
        end,
      },
    },
    attach_mappings = function(bufnr, map)
      -- 이 프롬프트에서 F1 을 다시 누르면 <CR>, <C-y> 를 F1 절의 뜻으로 보인다
      vim.b[bufnr].vimide_keyhelp_prompt = true
      prompt_back[bufnr] = back
      -- 숨긴 부동 창은 telescope 가 원래 창으로 돌아가기 전에 되살린다. 닫는 길이
      -- close 가 아닐 때(다른 창을 마우스로 눌러 BufLeave 로 닫힘)도 되살린다.
      api.nvim_create_autocmd('BufUnload', {
        buffer = bufnr,
        once = true,
        callback = function()
          prompt_back[bufnr] = nil
          vim.schedule(unhide)
        end,
      })
      t.actions.close:enhance({
        pre = function()
          unhide()
        end,
        post = function()
          if chosen or not back then
            return
          end
          vim.schedule(function()
            -- 이 목록 안에서 F1 을 다시 눌렀으면 새 목록이 떠 있다 - 그쪽이 맡는다
            if vim.bo.filetype == 'TelescopePrompt' or to_prev_win(back)
              or not api.nvim_win_is_valid(back.win) or api.nvim_get_current_win() ~= back.win then
              return
            end
            -- 그 창의 앞 창(wincmd p)도 F1 을 누르기 전 것으로 되돌린다. telescope 는
            -- 닫힌 프롬프트 창에서 이 창으로 돌아와서 앞 창이 사라진다. Ctrl+g /
            -- Ctrl+h 의 입력 창(부동)은 Esc 로 닫힐 때 nvim 이 앞 창으로 가는데, 그게
            -- 없어서 탭의 첫 창(왼쪽 aerial, neo-tree)에 떨어졌다. 자동 명령 없이 그
            -- 창에 한 번 들렀다 온다 (입력 창은 떠나면 닫힌다).
            if back.prev and back.prev ~= back.win and api.nvim_win_is_valid(back.prev)
              and api.nvim_win_get_tabpage(back.prev) == api.nvim_get_current_tabpage() then
              vim.cmd(('noautocmd call win_gotoid(%d)'):format(back.prev))
              vim.cmd(('noautocmd call win_gotoid(%d)'):format(back.win))
            end
            local row, col = back.cur[1], back.cur[2]
            local line = api.nvim_buf_get_lines(0, row - 1, row, false)[1]
            if not line then
              return
            end
            if back.insert then
              pcall(api.nvim_win_set_cursor, back.win, { row, col })
              -- gR 에서 눌렀으면 virtual replace 로 (startgreplace)
              local cmd = ({ R = 'startreplace', Rv = 'startgreplace' })[back.insert] or 'startinsert'
              vim.cmd(col >= #line and (cmd .. '!') or cmd)
            elseif api.nvim_get_mode().mode == 'n' then
              if back.visual then
                -- gv 는 커서도 고르던 때의 자리로 둔다
                pcall(vim.cmd, 'normal! gv')
              else
                -- 다른 목록(\fo ...) 안에서 누른 F1: 그 목록을 insert 모드로 닫으면
                -- telescope 는 원래 창 커서를 한 칸 오른쪽에 둔다 (insert 를 끝내며
                -- 한 칸 돌아올 것으로 친다). 이 목록을 normal 모드(Esc Esc)로 닫으면
                -- 그 한 칸이 남았다.
                pcall(api.nvim_win_set_cursor, back.win, { row, col })
              end
            end
          end)
        end,
      })
      vim.schedule(function()
        if type(_G.vimide_picker_track) == 'function' then
          pcall(_G.vimide_picker_track, t.state.get_current_picker(bufnr))
        end
      end)
      for _, a in ipairs({ 'select_vertical', 'select_horizontal', 'select_tab' }) do
        if t.actions[a] then
          t.actions[a]:replace(function() end)
        end
      end
      t.actions.select_default:replace(function()
        local ent = t.state.get_selected_entry()
        chosen = ent ~= nil
        t.actions.close(bufnr)
        if ent then
          -- 프롬프트가 닫히고 insert 를 빠져나간 뒤에
          vim.schedule(function()
            do_enter(ent.value, rd, back)
          end)
        end
      end)
      local function copy()
        local ent = t.state.get_selected_entry()
        if not ent then
          return
        end
        local k = key_of(ent.value)
        if not k or k == '' then
          return
        end
        -- " 레지스터에. 시스템 클립보드(+ *)는 'clipboard' 가 unnamed(plus) 일
        -- 때만 - 묻지 않고 덮으면 다른 앱에서 복사해 둔 것을 잃는다.
        vim.fn.setreg('"', k)
        local regs = { '"' }
        for _, o in ipairs(vim.split(vim.o.clipboard, ',', { plain = true })) do
          local r = (o == 'unnamedplus' and '+') or (o == 'unnamed' and '*') or nil
          if r and pcall(vim.fn.setreg, r, k) then
            regs[#regs + 1] = r
          end
        end
        local msg = ('복사: %s   (%s 레지스터)'):format(k, table.concat(regs, ' '))
        -- 프롬프트는 insert 모드라 메시지 줄은 바로 '-- INSERT --' 로 덮인다 - 프롬프트
        -- 제목에 2 초 보인다. 메시지는 :messages 에 남기려고 그대로 낸다.
        local bd = picker.layout and picker.layout.prompt and picker.layout.prompt.border
        if bd and bd.change_title then
          if flash_n == 0 then
            local o = bd._border_win_options and bd._border_win_options.title
            title0 = type(o) == 'table' and o[1] and o[1].text or o or picker.prompt_title
          end
          flash_n = flash_n + 1
          local n = flash_n
          pcall(bd.change_title, bd, msg)
          vim.defer_fn(function()
            if n == flash_n and api.nvim_buf_is_valid(bufnr) then
              pcall(bd.change_title, bd, title0)
            end
          end, 2000)
        end
        say(msg)
      end
      map('i', '<C-y>', copy, { desc = '키 복사 (단축키 도움말)' })
      map('n', '<C-y>', copy, { desc = '키 복사 (단축키 도움말)' })
      return true
    end,
  })
  unhide, raise = hide_floats()
  local before = {}
  if raise then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      before[w] = true
    end
  end
  local okf, err = pcall(picker.find, picker)
  if not okf then
    unhide()
    error(err, 0)
  end
  if raise then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      local ok, cfg = pcall(api.nvim_win_get_config, w)
      if not before[w] and ok and cfg.relative and cfg.relative ~= '' then
        pcall(api.nvim_win_set_config, w, { zindex = raise })
      end
    end
  end
end

_G.vimide_keyhelp = open

api.nvim_create_user_command('VimIdeKeys', function(o)
  open(o.bang)
end, { bang = true, desc = '단축키 도움말 (F1). ! 는 README 를 새로 읽는다' })
