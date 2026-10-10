-- dirdiffview.lua - Beyond Compare 처럼: 두 디렉터리를 나란한 트리로, 바로
--
--   :DirDiff <A> <B>        새 탭에 비교 트리. 파일을 고르면 비교 탭(A | B, diff)이 따로 열린다
--   neo-tree 에서 \d 두 번  같은 것 (dirdiffpick.lua)
--   :DirDiffClassic <A> <B> 예전 DirDiff.vim 목록 (dirdifftab.vim)
--
-- 트리 창은 왼쪽이 A, 오른쪽이 B 의 트리다 (Beyond Compare 의 폴더 비교처럼). 같은 줄에 같은
-- 이름이 오고, 한쪽에만 있으면(고아) 다른 쪽은 비어 있다. 반쪽마다 칸이 셋: 이름(안내선 + 폴더
-- 아이콘 또는 파일 표시 + 이름), 크기(천 단위 쉼표), 수정일('2026-10-10 오후 11:09:40' -
-- g:vimide_dirdiff_date_format). 반쪽이 좁으면 시각, 날짜, 크기 순으로 뺀다. 맨 위 한 줄(경로 줄
-- 창)에 A·B 의 뿌리, 그 아래 한 줄에 칸 제목(이름 크기 수정일) - 트리를 내려도 그대로다.
-- 가운데 칸이 판정이다 (Beyond Compare 처럼 다른 파일과 같은 파일에만):
--   ≠(x) 다르다      =  같다      ·(.) 확인 중      (고아와 폴더는 비운다)
-- 색 (g:vimide_dirdiff_colors = 'bc', 기본 - Beyond Compare 의 색. background 가 dark 면 어두운 짝):
--   같은 파일 보통 글자, 다른 파일은 수정 시각이 늦은 쪽 빨강·이른 쪽 회색 (시각이 같거나 모르면
--   둘 다 빨강), 고아 파일(한쪽에만 있는 파일)은 파랑. 폴더는 (한쪽에만 있는 것도) 이름은 보통 글자,
--   크기·날짜는 옅은 회색이고 아이콘이 그 아래를 말한다 (그쪽에서 보아): 늦은 쪽인 차이가 있으면
--   빨강, 아니고 이른 쪽인 차이가 있으면 회색, 그 밖(같음·고아만)은 보통 폴더색 (Beyond Compare 의
--   첫 사진). 뒤쪽이 주는 폴더의 표시(mask - 그 아래 모두를 합한 것)로 가린다 (folder_g). 지금 줄은
--   커서가 있는 쪽(A 또는 B)의 반 칸만 연두 (Beyond Compare 의 고른 줄 - 그쪽만 골라진다).
-- 'neogit' 이면 Neogit 상태 화면의 무리에 잇고(다른 것 NeogitChangeModified, A 에만
-- NeogitChangeDeleted, B 에만 NeogitChangeNewFile), 'classic' 이면 예전 색 (다른 것 빨강, 한쪽에만
-- 파랑) - 이 둘은 판정 칸도 예전 것(◀ ▶ 까지)이다.
--
-- 파일 짝은 비교 탭에서 본다 (g:vimide_dirdiff_pair_tab = 1, 기본): 짝마다 탭 하나 - A | B 를
-- diff 로 (Beyond Compare 의 글 비교처럼). 창 머리(winbar)에 쪽·경로(좁으면 가운데를 줄인다)·수정
-- 일시·크기(바이트)·인코딩·줄 끝, B 쪽 끝에 보기와 키. 바뀐 줄은 연분홍 바탕, 줄 안의 다른
-- 글자와 한쪽에만 있는 줄은 빨강, 다른 쪽의 빈자리(끼인 줄)는 회색 빗금(╱). 지금 차이 덩어리의
-- 첫 줄에 노란 화살표(A ⇨, B ⇦)와 덩어리 끝까지 가는 괄호선, 탭 맨 왼쪽에 개요 막대(파일 전체를
-- 줄여서 - 빨강 차이, 회색 빗금 빈자리, 파랑 빈 줄, 오른쪽 칸이 보이는 곳. 누르면 그리로,
-- g:vimide_dirdiff_overview), 맨 아래에 줄 자세히 두 줄(커서 줄과 맞은편 줄, 빈칸 · 탭 → 줄 끝 ¶,
-- g:vimide_dirdiff_line_details). 바뀐 덩어리 안의 빈 줄은 연보라 (Beyond Compare 의 '중요하지
-- 않은' 줄 - bc 색에서만). 한쪽에만 있는 파일은 있는 쪽이 모두 분홍에 빨강, 없는 쪽은 빗금뿐이다.
-- 개요 막대·줄 자세히는 그 비교 탭에만 있고 들어가지 않는다 (cmp - 아래 '비교 탭의 곁').
-- 같은 짝을 다시 고르면 그 탭으로 간다. 비교 탭의 q 는 그 탭을
-- 닫고 트리의 그 줄로 (:tabclose 도 같다). 트리를 끝내면(q) 그 비교 탭들도 닫힌다.
-- g:vimide_dirdiff_pair_tab = 0 이면 예전처럼 트리 탭 위쪽의 편집 창 둘에서 본다.
-- 비교 창의 보기 (\d 로 고른다, Beyond Compare 의 글 비교 보기): 모두 보이기(기본 - 접지
-- 않는다), 차이 보이기(바뀐 줄만, 나머지는 접는다), 문맥 보이기(바뀐 줄과 위아래 N 줄).
-- 접기는 foldmethod=diff 그대로라 zR(모두) / zM(접기)도 된다.
--
-- 트리 창의 키
--   <CR>        파일: 비교 탭을 열고(있으면 그 탭으로) 커서를 첫 차이로
--               디렉터리: 펼치기/접기
--   o           파일: 비교 탭을 뒤에서 열고(열려 있으면 다시 읽고) 커서는 트리에 그대로 -
--               여러 짝을 열어 두고 gt 로 돌아본다. pair_tab = 0 이면 위 두 창에 열기만
--   <C-n>/<C-p> 다음/앞 '차이' 파일로 (접힌 디렉터리는 펼치며). 모두·차이 밖의 보기에서는 그
--               보기가 보이는 것으로 (좌측 최신이면 A 가 최신인 파일, 동일이면 같은 파일)
--   l / h       펼치기 / 접기(접혀 있으면 부모로)
--   O / X       차이 있는 디렉터리를 모두 펼치기 / 모두 접기 (트리 전체). 모두·차이 밖의 보기에서는
--               그 보기가 보이는 것이 아래에 있는 디렉터리를
--   f           보기 고르기 (Beyond Compare 의 보기: 모두 / 차이 / 고아 없음 / 좌측 최신 ...)
--   F           모두 보이기 <-> 차이 보이기
--   <Tab>       비교할 곳 고르기: 지금 쪽의 항목을 [A] 로, 다음 Tab 의 것을 [B] 로 - 곧바로 새
--               탭에서 비교 (디렉터리 둘이면 DirDiff, 파일 둘이면 vimdiff). [A] 줄에서 다시 Tab 은
--               취소. neo-tree 의 Tab 과 같은 [A] 다 (dirdiffpick.lua) - 트리가 달라도 된다
--   <S-Tab>     A 쪽 / B 쪽 (커서가 그쪽 이름으로. 마우스로 눌러도 된다)
--   <Space>     지금 쪽의 항목 고르기/풀기 (다음 줄로)       U  고른 것 모두 풀기
--   <C-r>/<C-l> A → B / B → A 로 파일·디렉터리 복사: 원본 쪽(A→B 면 A 트리)에서 고른 것,
--               없으면 비주얼 줄, 그것도 없으면 커서 줄. 이름을 보이고 묻고 나서, 뒤쪽이
--               항목마다 안전하게 한다 (같은 이름은 덮어쓰고 디렉터리는 합친다 - 지우지
--               않는다, 제외 목록은 건드리지 않는다, 대상 쪽 링크를 따라가 쓰지 않는다).
--               복사한 곳만 다시 본다 (그곳이 든 다른 비교 탭도)
--   R           다시 훑기        q  끝내기(탭을 닫는다, 비교 탭들도)       ?  도움말
--   ,r / ,e     이 비교의 다음 / 앞 탭 (트리 탭과 비교 탭들 사이 - 비교 창에서도. 아래 tab_cycle)
-- 비교 창(비교 탭의 두 창, pair_tab = 0 이면 위의 편집 창 둘)에서는 \d 가 보기 고르기, 비교 탭의
-- q 는 그 탭 닫기 (매크로를 적는 중이면 q 그대로 - 적기 끝),
-- <C-n>/<C-p> 가 ]c/[c (다음/앞 차이), <C-r>/<C-l> 은
-- 커서가 있는 차이 덩어리째 오른쪽(B)/왼쪽(A)으로 (diffput/diffget - 저장은 :w).
-- <C-S-r>/<C-S-l> 은 커서 줄만 (Ctrl+Shift 가 nvim 까지 따로 올 때 - 아래 TAKE 의 설명: tmux 안이면
-- tmux '서버'가 3.2 이상이어야 한다), 어디서나 되는 것은 횟수(1<C-r> = 커서 줄, N<C-r> = N 줄)와
-- 비주얼(고른 줄).
-- 커서 줄만(<C-S-r>, 1<C-r>)인데 그 줄이 바뀐 줄이 아니면, 바로 위(먼저)·아래에 끼인 줄(저쪽에만
-- 있는 줄) 덩어리째다 - 여러 줄일 수 있다.
-- 비교 탭 밖의 <C-r>(되돌리기 취소)·<C-l>(창 옮기기)은 그대로다.
-- 비교 창의 <C-w>w/<C-w>W 는 곁 창(개요 막대·줄 자세히)을 건너뛴 다음/앞 창이다 (A·B 를 오간다).
--
-- 빠른 이유는 뒤쪽 dirdiffscan.py 에 적었다: 찾는 대로 보여 주고(펼쳐 둔 디렉터리
-- 먼저), 크기가 다르면 바로 '다름', 크기·시각이 같으면 '같음', 나머지만 뒤에서
-- 내용을 읽는다. 편집기는 한 번도 기다리지 않는다.
--
--   let g:vimide_dirdiff_view = 0          " :DirDiff 를 예전 목록(DirDiff.vim)으로
--   let g:vimide_dirdiff_only_diff = 1     " 처음부터 차이 보이기
--   let g:vimide_dirdiff_filter = 'right-newer'  " 처음 보기 (아래 MODES 의 id, only_diff 보다 먼저)
--   let g:vimide_dirdiff_trust_mtime = 0   " 크기·시각이 같아도 내용까지 읽기
--   let g:vimide_dirdiff_list_height = 16  " 트리 창 높이 (pair_tab = 0 일 때만, 기본: 화면의 40%)
--   let g:vimide_dirdiff_max_mb = 20       " 이보다 큰 파일은 열지 않고 알림만
--   let g:vimide_dirdiff_confirm_copy = 0  " 트리의 <C-r>/<C-l> 복사를 묻지 않고
--   let g:vimide_dirdiff_copy_keys = 0     " <C-r>/<C-l>(<C-S-r>/<C-S-l>) 을 가로채지 않기 (편집 창)
--   let g:vimide_dirdiff_colors = 'neogit' " Neogit 상태 화면의 색 ('classic' 예전 색, 기본 'bc': Beyond Compare)
--   let g:vimide_dirdiff_pair_tab = 0      " 파일 짝을 비교 탭 대신 트리 위의 편집 창 둘에서
--   let g:vimide_dirdiff_file_view = 'diff' " 비교 창의 처음 보기 (all / diff / context)
--   let g:vimide_dirdiff_context = 3       " 문맥 보이기의 위아래 줄 수
--   let g:vimide_dirdiff_date_format = '%Y-%m-%d %H:%M'  " 수정일 꼴 (strftime + %p 오전/오후, %l 12시간제 시)
--   let g:vimide_dirdiff_overview = 0      " 비교 탭 맨 왼쪽의 개요 막대 없이
--   let g:vimide_dirdiff_line_details = 0  " 비교 탭 맨 아래의 줄 자세히(두 줄) 없이
--   (제외 목록은 DirDiff.vim 과 같은 g:DirDiffExcludes)

if vim.g.loaded_vimide_dirdiffview then
  return
end
vim.g.loaded_vimide_dirdiffview = 1

local api = vim.api
local uv = vim.uv or vim.loop
local ns = api.nvim_create_namespace('vimide_dirdiffview')
local ns_open = api.nvim_create_namespace('vimide_dirdiffview_open')
local ns_side = api.nvim_create_namespace('vimide_dirdiffview_side')
local ns_pick = api.nvim_create_namespace('vimide_dirdiffview_pick')
-- 새 것은 한 표에 (이 파일은 맨 위 지역 이름이 LuaJIT 의 한도 200 가까이 있다)
--   head 경로 줄, arrow 비교 창의 화살표·괄호선, blank 연보라 빈 줄·한쪽에만 있는 줄의 빨강,
--   over 개요 막대, line 줄 자세히
local NS = {}
for _, k in ipairs({ 'head', 'arrow', 'blank', 'over', 'line' }) do
  NS[k] = api.nvim_create_namespace('vimide_dirdiffview_' .. k)
end
-- tr: 트리 창의 Beyond Compare 꼴 (칸·안내선·색·경로 줄), cmp: 비교 탭의 곁 (개요 막대, 줄 자세히,
-- 화살표, 연보라 빈 줄). 함수와 상태는 이 두 표의 필드로 - 지역 이름을 늘리지 않으려고
local tr, cmp = {}, {}

local M = {}
local sessions = {} -- tabpage handle -> session

-- 짝을 보이는 창 둘(view): { s = 세션, tab, win_a, win_b, rel = 보이는 짝, bin, empty_a, empty_b, fmode = 보기 }.
-- pair_tab 이면 짝마다 비교 탭 하나(s.views[탭]), 아니면 트리 탭 위의 편집 창 둘 하나뿐(s.main)
local function views_of(s)
  local out = {}
  if s.main then
    out[#out + 1] = s.main
  end
  for _, v in pairs(s.views or {}) do
    out[#out + 1] = v
  end
  return out
end
local views_of_fn = views_of

local function all_views()
  local out = {}
  for _, s in pairs(sessions) do
    vim.list_extend(out, views_of(s))
  end
  return out
end

-- 이 창이 비교 창(두 창 중 하나)인 view
local function view_of_win(w)
  for _, v in ipairs(all_views()) do
    if w == v.win_a or w == v.win_b then
      return v
    end
  end
end

-- 이 탭의 view: 비교 탭, 또는 편집 창 둘을 가진 트리 탭 (pair_tab = 0)
local function view_of_tab(tab)
  for _, s in pairs(sessions) do
    if s.views[tab] then
      return s.views[tab]
    end
    if s.main and s.tab == tab then
      return s.main
    end
  end
end

local BAD = { diff = true, onlyA = true, onlyB = true }

-- 보기 (Beyond Compare 의 보기 거르기). 항목의 표시(mask)는 뒤쪽이 매긴다 (dirdiffscan.py 의
-- SAME ... UNK): 고아 = 한쪽에만 있는 것 (좌측 고아 = A 에만), 최신 = 양쪽에 있고 내용이 다른데
-- 그쪽의 수정 시각이 늦은 것, 동일 = 같은 것. 양쪽에 있는 디렉터리의 표시는 그 아래 모두의 것을
-- 합한 것이라, 그 아래에 보일 것이 있는 디렉터리만 보인다 (접혀 있어도)
local band = bit.band
local SAME, NA, NB, DX, OA, OB, PEND, UNK = 1, 2, 4, 8, 16, 32, 64, 128
local MODES = {
  { id = 'all', label = '모두 보이기' },
  { id = 'diff', label = '차이 보이기', bits = NA + NB + DX + OA + OB },
  { id = 'no-orphans', label = '고아 없음 보이기', bits = SAME + NA + NB + DX, both = true },
  { id = 'diff-no-orphans', label = '고아 없는 차이 보이기', bits = NA + NB + DX },
  { id = 'orphans', label = '고아 보이기', bits = OA + OB },
  { id = 'left-newer', label = '좌측 최신 보이기', bits = NA },
  { id = 'right-newer', label = '우측 최신 보이기', bits = NB },
  { id = 'left-newer-orphans', label = '좌측의 최신과 고아 보이기', bits = NA + OA },
  { id = 'right-newer-orphans', label = '우측 최신과 고아 보이기', bits = NB + OB },
  { id = 'left-orphans', label = '좌측 고아 보이기', bits = OA },
  { id = 'right-orphans', label = '우측 고아 보이기', bits = OB },
  { id = 'same', label = '동일 보이기', bits = SAME },
}
local MODE = {}
for i, md in ipairs(MODES) do
  md.i = i
  MODE[md.id] = md
end

local function ascii()
  return (tonumber(vim.g.vimide_ascii_icons) or 0) ~= 0
end

-- 예전 판정 칸 (neogit·classic 색). bc 는 tr.verdict
local function sym(st)
  if ascii() then
    return ({ same = '=', diff = 'x', onlyA = '<', onlyB = '>', pend = '.' })[st] or ' '
  end
  return ({ same = '=', diff = '≠', onlyA = '◀', onlyB = '▶', pend = '·' })[st] or ' '
end

-- 옵션이 켜져 있는가 (없으면 기본값 d)
local function on(v, d)
  return (tonumber(v) or d) ~= 0
end

local function say(msg, level)
  (_G.vimide_notify or vim.notify)('DirDiff: ' .. msg, level or vim.log.levels.INFO)
end

-- 색 무리 (g:vimide_dirdiff_colors):
--   'bc'      (기본) Beyond Compare 의 색 - 사용자가 Beyond Compare 처럼 보이기를 바랐다. 'background' 가
--             dark 면 어두운 짝 (jellybeans 같은 어두운 화면), cterm 은 256 색 근사
--   'neogit'  Neogit 상태 화면의 무리에 잇는다. 그 무리가 없으면(Neogit 을 setup 하지 않았다) 그 줄만 예전 색
--   'classic' 예전 색 그대로
-- 모르는 값은 'bc'. 무리마다 { 이름, Neogit 무리(앞의 것부터 있는 것), 예전 정의, bc 밝은, bc 어두운 }
-- (bc 정의가 없으면 예전 정의). 비교 창(A·B 두 창)의 것은 그 창의 winhighlight 로만 단다 (diff_whl):
-- bc 는 두 쪽 모두 바뀐 줄이 연분홍 바탕, 줄 안의 다른 글자·한쪽에만 있는 줄이 빨강 (Beyond Compare 의
-- 글 비교). neogit 은 A 쪽이 Neogit 의 빨강(지운 줄), B 쪽이 초록(더한 줄), 줄 안의 바뀐 글자(DiffText)는
-- Neogit 의 줄 안 차이 (NeogitDiff*Inline) - Highlight 는 그 줄과 바탕색이 같아 바뀐 글자가 보이지 않았다
-- (sourceinsight 색, 실측)
local function pal()
  local p = vim.g.vimide_dirdiff_colors
  if p == 'neogit' or p == 'classic' then
    return p
  end
  return 'bc'
end

-- classic 이 아닌가 (bc, neogit): 비교 창의 winhighlight 와 상태줄·창 머리의 토막 색을 단다
local function neo()
  return pal() ~= 'classic'
end

-- bc 정의를 짧게: fg, ctermfg, bg, ctermbg, 덧붙일 것 (bold 등)
local function C(fg, cf, bg, cb, more)
  local t = { fg = fg, ctermfg = cf, bg = bg, ctermbg = cb }
  for k, v in pairs(more or {}) do
    t[k] = v
  end
  return t
end
local BOLD = { bold = true, cterm = { bold = true } }

local HL = {
  -- 트리. 다름 (상태줄의 다름 수, 시각이 같거나 모르는 다른 파일)
  { 'VimIdeDirDiffChanged', { 'NeogitChangeModified' }, { fg = '#e06c75', ctermfg = 167 },
    C('#f00000', 196), C('#ff6b6b', 203) },
  -- 다른 파일의 수정 시각이 늦은 쪽 / 이른 쪽 (neogit·classic 은 둘 다 다름 색 - 예전처럼)
  { 'VimIdeDirDiffNewer', { 'NeogitChangeModified' }, { link = 'VimIdeDirDiffChanged' },
    C('#f00000', 196), C('#ff6b6b', 203) },
  { 'VimIdeDirDiffOlder', { 'NeogitChangeModified' }, { link = 'VimIdeDirDiffChanged' },
    C('#8b8b8b', 245), C('#7c7c7c', 243) },
  { 'VimIdeDirDiffOrphan', nil, { fg = '#61afef', ctermfg = 75 },   -- 고아 (A·B 가 같은 색)
    C('#1a1aff', 21), C('#7aa6ff', 75) },
  { 'VimIdeDirDiffOnlyA', { 'NeogitChangeDeleted' }, { link = 'VimIdeDirDiffOrphan' } },
  { 'VimIdeDirDiffOnlyB', { 'NeogitChangeNewFile', 'NeogitChangeAdded' }, { link = 'VimIdeDirDiffOrphan' } },
  { 'VimIdeDirDiffPending', { 'NeogitSubtleText' }, { link = 'Comment' },
    C('#a8a8a8', 248), C('#666666', 241) },
  { 'VimIdeDirDiffSame', nil, { link = 'Normal' } },
  { 'VimIdeDirDiffDir', nil, { link = 'Directory' } },
  { 'VimIdeDirDiffSize', { 'NeogitSubtleText' }, { link = 'Number' } },
  { 'VimIdeDirDiffDate', { 'NeogitSubtleText' }, { link = 'Comment' } },
  -- bc: 양쪽에 있는 폴더의 크기·날짜 (옅은 회색), 안내선, 보통 폴더 아이콘(Beyond Compare 의 연보라 폴더)
  { 'VimIdeDirDiffDim', { 'NeogitSubtleText' }, { link = 'VimIdeDirDiffSize' },
    C('#c7c7c7', 251), C('#707070', 242) },
  { 'VimIdeDirDiffGuide', nil, { link = 'NonText' }, C('#c4c4c4', 250), C('#444444', 238) },
  { 'VimIdeDirDiffFolder', nil, { link = 'Directory' }, C('#8f8fff', 105), C('#8f9fe0', 104) },
  -- 판정 칸 (bc): ≠ 빨강 굵게, = 보통 글자 굵게
  { 'VimIdeDirDiffNeq', nil, { link = 'VimIdeDirDiffChanged' },
    C('#f00000', 196, nil, nil, BOLD), C('#ff6b6b', 203, nil, nil, BOLD) },
  { 'VimIdeDirDiffEq', nil, { link = 'VimIdeDirDiffPending' }, BOLD, BOLD },
  -- 트리의 지금 줄 (창에만 CursorLine 을 이것으로 - tree_opts)
  { 'VimIdeDirDiffSelect', nil, { link = 'CursorLine' }, C(nil, nil, '#d7ffd0', 194), C(nil, nil, '#24402a', 22) },
  { 'VimIdeDirDiffOpened', nil, { link = 'Visual' }, C(nil, nil, '#e8eefc', 189), C(nil, nil, '#2a3346', 237) },
  { 'VimIdeDirDiffMark', nil, { link = 'Search' } },        -- Space 로 고른 항목
  -- 커서 줄의 지금 쪽(A/B) 반 칸: 고른 줄의 연두 (Beyond Compare 처럼 그쪽만 - mark_side).
  -- neogit·classic 은 VimIdeDirDiffSelect 가 CursorLine 이라 그 색 그대로
  { 'VimIdeDirDiffSide', nil, { link = 'VimIdeDirDiffSelect' } },
  { 'VimIdeDirDiffPickA', nil, { link = 'Search' } },      -- Tab 으로 고른 [A] (dirdiffpick.lua 와 같은 것)
  { 'VimIdeDirDiffMenuNow', { 'NeogitSectionHeader' }, { link = 'Title' } },  -- 보기 메뉴의 지금 보기
  -- 창 머리·상태줄의 이름표 (Neogit 의 절 머리 - 'Unstaged changes'). neogit·bc 색일 때만 단다
  { 'VimIdeDirDiffHeader', { 'NeogitSectionHeader' }, { link = 'Title' }, BOLD, BOLD },
  -- 트리 위 경로 줄: 다른 쪽 / 지금 쪽 (Beyond Compare 의 경로 칸 - 지금 쪽이 연두), 그 아래 칸 제목
  { 'VimIdeDirDiffPath', nil, { link = 'StatusLineNC' },
    C('#000000', 16, '#f0f0f0', 255), C('#d0d0d0', 252, '#262626', 235) },
  { 'VimIdeDirDiffPathOn', nil, { link = 'StatusLine' },
    C('#000000', 16, '#ddffdd', 194), C('#e0e0e0', 254, '#1f3a22', 22) },
  -- 칸 제목은 nocombine: 상태줄의 토막 색은 StatusLine 과 섞여서 jellybeans 의 기울임이 따라왔다
  { 'VimIdeDirDiffColHead', nil, { link = 'StatusLineNC' },
    C('#303030', 236, '#f6f6f6', 255, { nocombine = true }), C('#b0b0b0', 249, '#202020', 234, { nocombine = true }) },
  -- 트리 상태줄의 수 (다름·A만·B만). 여섯째 true: 'background' 가 아니라 상태줄 바탕으로 밝은·어두운 짝을
  -- 고른다 - jellybeans 는 어두운 화면에 밝은 상태줄이라 어두운 짝(옅은 빨강·파랑)이 바탕에 묻혔다
  { 'VimIdeDirDiffStChanged', nil, { link = 'VimIdeDirDiffChanged' }, C('#e00000', 160), C('#ff6b6b', 203), true },
  { 'VimIdeDirDiffStOnlyA', nil, { link = 'VimIdeDirDiffOnlyA' }, C('#1a1aff', 21), C('#7aa6ff', 75), true },
  { 'VimIdeDirDiffStOnlyB', nil, { link = 'VimIdeDirDiffOnlyB' }, C('#1a1aff', 21), C('#7aa6ff', 75), true },
  -- 비교 창 (winhighlight 의 대상 - classic 이 아닐 때만 단다). Neogit 이 없으면 원래 Diff* 그대로
  { 'VimIdeDirDiffAddA', { 'NeogitDiffDelete' }, { link = 'DiffAdd' },
    C('#ff0000', 196, '#ffe3e3', 224), C('#ff8a8a', 210, '#3a1d20', 52) },
  { 'VimIdeDirDiffChangeA', { 'NeogitDiffDelete' }, { link = 'DiffChange' },
    C(nil, nil, '#ffe3e3', 224), C(nil, nil, '#3a1d20', 52) },
  { 'VimIdeDirDiffTextA', { 'NeogitDiffDeleteInline', 'NeogitDiffDeleteHighlight' }, { link = 'DiffText' },
    C('#ff0000', 196, '#ffe3e3', 224), C('#ff8a8a', 210, '#3a1d20', 52) },
  { 'VimIdeDirDiffAddB', { 'NeogitDiffAdd' }, { link = 'DiffAdd' }, { link = 'VimIdeDirDiffAddA' },
    { link = 'VimIdeDirDiffAddA' } },
  { 'VimIdeDirDiffChangeB', { 'NeogitDiffAdd' }, { link = 'DiffChange' }, { link = 'VimIdeDirDiffChangeA' },
    { link = 'VimIdeDirDiffChangeA' } },
  { 'VimIdeDirDiffTextB', { 'NeogitDiffAddInline', 'NeogitDiffAddHighlight' }, { link = 'DiffText' },
    { link = 'VimIdeDirDiffTextA' }, { link = 'VimIdeDirDiffTextA' } },
  -- 끼인 줄 (neogit 은 흐리게, bc 는 Beyond Compare 의 회색 빗금 - fillchars diff:╱ 의 글자색)
  { 'VimIdeDirDiffFiller', { 'NeogitSubtleText' }, { link = 'DiffDelete' },
    C('#c4c4c4', 250, '#fcfcfc'), C('#3a3a3a', 237, '#181818') },
  -- bc: 파일 끝 아래 (fillchars eob 는 비운다), 바뀐 덩어리 안의 빈 줄 (연보라 - Beyond Compare 의 '중요하지 않은' 줄)
  { 'VimIdeDirDiffEob', nil, { link = 'EndOfBuffer' }, C('#e6e6e6', 254), C('#2a2a2a', 235) },
  { 'VimIdeDirDiffBlank', nil, { link = 'DiffChange' }, C(nil, nil, '#efefff', 189), C(nil, nil, '#24243a', 17) },
  -- bc: 한쪽에만 있는 줄의 글자 (구문 색 위에 - DiffAdd 의 글자색은 키워드 등의 구문 색에 진다)
  { 'VimIdeDirDiffAddText', nil, { link = 'DiffAdd' }, C('#ff0000', 196), C('#ff8a8a', 210) },
  -- 비교 창의 창 머리: 지금 창 (WinBar) / 다른 창 (WinBarNC) - bc 만
  { 'VimIdeDirDiffBarOn', nil, { link = 'WinBar' }, C('#000000', 16, '#ddffdd', 194), C('#e0e0e0', 254, '#1f3a22', 22) },
  { 'VimIdeDirDiffBar', nil, { link = 'WinBarNC' }, C('#000000', 16, '#f0f0f0', 255), C('#d0d0d0', 252, '#262626', 235) },
  -- 창 머리의 정보(일시·크기·인코딩): Beyond Compare 의 정보 줄은 검은 글자다 - 키 안내의 흐린 색으로는
  -- 연두·회색 바탕에서 읽기 어려웠다 (대비 2:1 남짓)
  { 'VimIdeDirDiffBarInfo', nil, { link = 'VimIdeDirDiffPending' }, C('#505050', 239), C('#a8a8a8', 248) },
  -- 지금 차이의 노란 화살표 (A ⇨ / B ⇦ - 줄 자세히의 앞에도), 그 덩어리 끝까지의 괄호선
  { 'VimIdeDirDiffArrow', nil, { fg = '#d7a000', ctermfg = 178, bold = true },
    C('#3c4a34', 58, '#fbdc74', 221, BOLD), C('#151515', 233, '#e5c062', 179, BOLD) },
  { 'VimIdeDirDiffBracket', nil, { link = 'NonText' }, C('#a0a0a0', 247), C('#606060', 241) },
  -- 줄 자세히의 빈칸·탭·줄 끝 표시
  { 'VimIdeDirDiffWs', nil, { link = 'NonText' }, C('#a0a0a0', 247), C('#5a5a5a', 240) },
  -- 개요 막대: 차이, 빈자리(한쪽에 줄이 없다), 빈 줄(연보라 줄), 보이는 곳
  { 'VimIdeDirDiffOvChange', nil, { link = 'DiffText' }, C(nil, nil, '#ff0000', 196), C(nil, nil, '#d04545', 167) },
  { 'VimIdeDirDiffOvFill', nil, { link = 'DiffDelete' }, C('#b8b8b8', 249, '#f0f0f0', 255), C('#4a4a4a', 239, '#202020', 234) },
  { 'VimIdeDirDiffOvBlank', nil, { link = 'DiffAdd' }, C(nil, nil, '#5050ff', 63), C(nil, nil, '#4a6cff', 63) },
  { 'VimIdeDirDiffOvView', nil, { link = 'Visual' }, C(nil, nil, '#a0a0a0', 247), C(nil, nil, '#5a5a5a', 240) },
}

local function has_hl(name)
  local ok, h = pcall(api.nvim_get_hl, 0, { name = name })
  return ok and next(h) ~= nil
end

-- 마지막으로 단 정의 (nvim_get_hl 로 읽은 것, default 표시는 빼고). 지금 정의가 이것과 같거나 비었을
-- 때만 다시 단다 - 사용자가 :hi 로 바꾼 것(또는 색 구성표가 정한 것)은 그대로 둔다. 다시 달 때는
-- :hi clear 로 우리 것을 걷고 default 로: 그냥 default 로 덮으면 '있는 정의' 라 바뀌지 않는다.
-- :hi clear(색 구성표 바꾸기)는 default 링크를 남겨 두므로(default 표시 없이) 견줄 때 그 표시를 뺀다
local hl_mine = {}
local function hl_now(name)
  local h = api.nvim_get_hl(0, { name = name, link = true })
  h.default = nil
  return h
end

-- 상태줄(StatusLine) 바탕이 어두운가. 바탕이 없으면 'background' 로 (reverse 면 글자색이 바탕이다)
function tr.st_dark()
  local ok, h = pcall(api.nvim_get_hl, 0, { name = 'StatusLine', link = false })
  local bg = ok and (h.reverse and h.fg or h.bg) or nil
  if type(bg) ~= 'number' then
    return vim.o.background == 'dark'
  end
  local r, g, b = math.floor(bg / 65536) % 256, math.floor(bg / 256) % 256, bg % 256
  return 0.299 * r + 0.587 * g + 0.114 * b < 128
end

local function set_hl()
  local p = pal()
  local dark = vim.o.background == 'dark'
  local st_dark = tr.st_dark()
  for _, d in ipairs(HL) do
    local name, spec = d[1], d[3]
    if p == 'neogit' and d[2] then
      for _, g in ipairs(d[2]) do
        if has_hl(g) then
          spec = { link = g }
          break
        end
      end
    elseif p == 'bc' then
      local dk = dark
      if d[6] then
        dk = st_dark
      end
      spec = (dk and d[5]) or d[4] or spec
    end
    local cur = hl_now(name)
    if next(cur) == nil or (hl_mine[name] and vim.deep_equal(cur, hl_mine[name])) then
      if next(cur) ~= nil then
        pcall(vim.cmd, 'hi clear ' .. name)
      end
      api.nvim_set_hl(0, name, vim.tbl_extend('force', spec, { default = true }))
      hl_mine[name] = hl_now(name)
    end
  end
end
set_hl()
-- Neogit 도 ColorScheme 에서 제 무리를 다시 정한다 - 그 뒤에 (먼저 보면 :hi clear 로 비어 있어 예전 색이 된다).
-- bc 는 'background' 로 밝은·어두운 짝을 고르므로 그것이 바뀔 때도 (색 구성표 없이 :set bg= 만 해도)
api.nvim_create_autocmd('ColorScheme', {
  group = api.nvim_create_augroup('VimIdeDirDiffViewHl', { clear = true }),
  callback = function()
    vim.schedule(set_hl)
  end,
})
api.nvim_create_autocmd('OptionSet', {
  group = 'VimIdeDirDiffViewHl',
  pattern = 'background',
  callback = function()
    vim.schedule(set_hl)
  end,
})

-- 창에만(local) 다는 창 옵션. vim.wo[w].x = 는 :set 처럼 그 창의 전역 값까지 바꾸어, 그 창에서 연
-- 새 탭(:tabnew)·창이 그 값(트리의 상태줄·머리)을 전역 값으로 물려받았다 - pair_tab 에서 트리 창에서
-- 비교 탭을 열면 plain_window(setlocal x<) 뒤에도 비교 창에 트리의 상태줄이 떴다
local function set_wo(win, name, val)
  pcall(api.nvim_set_option_value, name, val, { scope = 'local', win = win })
end

-- 비교 창의 winhighlight (side: 'a' / 'b', nil 이면 걷는다). classic 이 아닐 때만 단다. 창에만(local) - :set 처럼
-- 그 창의 전역 값까지 바꾸면 그 창에서 갈라 만든 창과 setlocal winhighlight< 가 그것을 물려받는다.
-- 무리 이름의 VimIdeDirDiff 는 표시이기도 하다: 비교 창이 아닌 창이 이것을 달고 있으면 물려받은 것이다
-- (strip_inherited). bc 는 창 머리(지금 창 연두)와 파일 끝 아래도, 그리고 창에만 fillchars 의 diff(끼인 줄의
-- 빗금)·eob 를 바꾼다. 화살표 자리로 signcolumn 을 늘 한 칸은 둔다 (모든 색 - 있다 없다 하면 글자가 밀린다.
-- cmp.signcol)
local WHL = {
  a = 'DiffAdd:VimIdeDirDiffAddA,DiffChange:VimIdeDirDiffChangeA,DiffText:VimIdeDirDiffTextA,DiffDelete:VimIdeDirDiffFiller',
  b = 'DiffAdd:VimIdeDirDiffAddB,DiffChange:VimIdeDirDiffChangeB,DiffText:VimIdeDirDiffTextB,DiffDelete:VimIdeDirDiffFiller',
  bc = ',WinBar:VimIdeDirDiffBarOn,WinBarNC:VimIdeDirDiffBar,EndOfBuffer:VimIdeDirDiffEob',
}
local function diff_whl(win, side)
  if not api.nvim_win_is_valid(win) then
    return
  end
  local p = pal()
  local want = (side and p ~= 'classic') and WHL[side] or ''
  if side and p == 'bc' then
    want = want .. WHL.bc
  end
  if vim.wo[win].winhighlight ~= want then
    pcall(api.nvim_set_option_value, 'winhighlight', want, { scope = 'local', win = win })
  end
  if side then
    if p == 'bc' then
      set_wo(win, 'fillchars', cmp.fillchars())
    end
    set_wo(win, 'signcolumn', cmp.signcol())
  else
    -- 걷을 때는 그 창의 전역 값으로 (plain_window 와 같은 길)
    pcall(api.nvim_win_call, win, function()
      vim.cmd('setlocal fillchars< signcolumn<')
    end)
  end
end

-- 상태줄·창 머리의 한 토막에 색 (classic 이 아닐 때만). %$무리$ 는 앞의 색(StatusLine·WinBar 의 바탕)을
-- 물려받는다 - %#무리# 는 Neogit 무리에 바탕이 없어 그 토막만 Normal 바탕으로 떴다
local function hl_part(group, text)
  if not neo() then
    return text
  end
  if vim.fn.has('nvim-0.11') == 0 then
    return '%#' .. group .. '#' .. text .. '%*'   -- %$ $ (바탕 유지)는 0.11 부터
  end
  return '%$' .. group .. '$' .. text .. '%*'
end

local function script_path()
  local f = api.nvim_get_runtime_file('tools/dirdiffscan.py', false)[1]
  if f then
    return f
  end
  local here = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(here, ':h:h') .. '/tools/dirdiffscan.py'
end

local function commas(n)
  if type(n) ~= 'number' then
    return ''
  end
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

local function nz(v)
  if v == vim.NIL then
    return nil
  end
  return v
end

-- 이름을 폭 w 안에 (넘치면 …)
local function fit(s, w)
  if w <= 0 then
    return ''
  end
  if vim.fn.strdisplaywidth(s) <= w then
    return s .. string.rep(' ', w - vim.fn.strdisplaywidth(s))
  end
  local n = vim.fn.strchars(s)
  while n > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(s, 0, n)) > w - 1 do
    n = n - 1
  end
  local t = vim.fn.strcharpart(s, 0, n) .. '…'
  return t .. string.rep(' ', w - vim.fn.strdisplaywidth(t))
end

local function rjust(s, w)
  local d = vim.fn.strdisplaywidth(s)
  if d >= w then
    return s
  end
  return string.rep(' ', w - d) .. s
end

-- 경로를 폭 w 안에, 넘치면 앞쪽을 자른다 (…뒤쪽 - Beyond Compare 의 경로 칸처럼 끝이 남는다)
function tr.fit_left(s, w)
  if w <= 0 then
    return ''
  end
  local d = vim.fn.strdisplaywidth(s)
  if d <= w then
    return s .. string.rep(' ', w - d)
  end
  local n = vim.fn.strchars(s)
  local k = 0
  while k < n and vim.fn.strdisplaywidth(vim.fn.strcharpart(s, k)) > w - 1 do
    k = k + 1
  end
  local t = '…' .. vim.fn.strcharpart(s, k)
  return t .. string.rep(' ', w - vim.fn.strdisplaywidth(t))
end

-- 경로를 폭 w 안에, 넘치면 가운데 디렉터리를 … 로 (Beyond Compare 의 'Y:\...\subcore\...\파일'): 맨 앞
-- (~ 또는 /)과 파일 이름은 남기고, 그 앞 디렉터리를 뒤에서부터 들어가는 만큼. 파일 이름만으로도 넘치면
-- 그것의 앞쪽을 자른다. 비교 창의 머리 - 앞쪽부터 잘랐더니(%<) 정보(일시·크기)는 보이는데 파일 이름이
-- 잘렸다 ('<egroup-subcore-tsound.bb'). 채우는 빈칸은 붙이지 않는다
function tr.mid_path(p, w)
  local sw = vim.fn.strdisplaywidth
  if sw(p) <= w then
    return p
  end
  local parts = vim.split(p, '/', { plain = true })
  local base = parts[#parts]
  if #parts > 2 then
    local function cand(t)
      return parts[1] .. '/…/' .. t
    end
    if sw(cand(base)) <= w then
      local tail = base
      for i = #parts - 1, 2, -1 do
        if sw(cand(parts[i] .. '/' .. tail)) > w then
          break
        end
        tail = parts[i] .. '/' .. tail
      end
      return cand(tail)
    end
  end
  if #parts > 1 and sw('…/' .. base) <= w then
    return '…/' .. base
  end
  return (tr.fit_left(base, w):gsub(' +$', ''))
end

-- 수정일 꼴 (g:vimide_dirdiff_date_format, 기본 '%Y-%m-%d %p %l:%M:%S' = '2026-10-10 오후 11:09:40').
-- strftime 꼴에 둘을 더했다: %p 오전/오후 (C 의 %p 는 지역 설정을 따라 AM/PM 이거나, 맥 ko_KR 에서는
-- 6 바이트라 칸이 어긋났다 - neo-tree 의 날짜 칸에서 겪은 것), %l 12시간제 시 (앞 0 없이 - %l 은
-- strftime 마다 있거나 없다). 좁을 때 빼는 '시각' 은 처음 나오는 시각 꼴(%p %H %I %l %M %S %T %R %r %X)부터
-- 끝까지, 그 앞이 '날짜' 다. 칸 너비는 가장 넓을 때로 (10~12시, 12월 28일 - 줄마다 너비가 달라 칸이 흔들리지 않게)
tr.DATE_FMT = '%Y-%m-%d %p %l:%M:%S'
function tr.strf(fmt, t)
  local tm = os.date('*t', t)
  local out = fmt:gsub('%%(.)', function(c)
    if c == 'p' then
      return tm.hour < 12 and '오전' or '오후'
    elseif c == 'l' then
      local h = tm.hour % 12
      return tostring(h == 0 and 12 or h)
    end
    return '%' .. c
  end)
  local ok, r = pcall(os.date, out, t)
  return ok and r or out
end

function tr.datefmt()
  local f = vim.g.vimide_dirdiff_date_format
  if type(f) ~= 'string' or f == '' then
    f = tr.DATE_FMT
  end
  local c = tr.dfc
  if c and c.src == f then
    return c
  end
  -- 앞에서부터 % 꼴을 하나씩 (%% 는 글자 % 라 건너뛴다 - '%%p' 는 시각이 아니다)
  local cut
  local i = 1
  while i <= #f do
    if f:sub(i, i) == '%' then
      if ('pHIlMSTRrX'):find(f:sub(i + 1, i + 1), 1, true) and f:sub(i + 1, i + 1) ~= '' then
        cut = i
        break
      end
      i = i + 2
    else
      i = i + 1
    end
  end
  local dpart = cut and vim.trim(f:sub(1, cut - 1)) or f
  local tpart = cut and vim.trim(f:sub(cut)) or ''
  local wide = os.time({ year = 2000, month = 12, day = 28, hour = 22, min = 58, sec = 58 })
  c = { src = f, date = dpart, time = tpart, cache = {}, n = 0 }
  c.dw = dpart ~= '' and vim.fn.strdisplaywidth(tr.strf(dpart, wide)) or 0
  c.tw = tpart ~= '' and vim.fn.strdisplaywidth(tr.strf(tpart, wide)) or 0
  tr.dfc = c
  return c
end

-- 수정일 칸 한 토막 (날짜 또는 시각, 폭 w 에 왼쪽 맞춤). 같은 시각이 많아 꼴낸 것을 담아 둔다
function tr.cell(f, part, mt, w)
  if not mt then
    return string.rep(' ', w)
  end
  local key = part .. '\1' .. mt
  local t = f.cache[key]
  if not t then
    if f.n > 20000 then
      f.cache, f.n = {}, 0
    end
    t = fit(tr.strf(part == 'd' and f.date or f.time, mt), w)
    f.cache[key] = t
    f.n = f.n + 1
  end
  return t
end

-- ---------------------------------------------------------------------------
-- 뒤쪽(dirdiffscan.py)과의 이야기
-- ---------------------------------------------------------------------------

local function send(s, obj)
  if s.job and s.job > 0 then
    pcall(vim.fn.chansend, s.job, vim.json.encode(obj) .. '\n')
  end
end

local render, render_rows, schedule_render, on_event, open_pair_fn, goto_row, mark_side, copied_fn, entry_of_fn
local menu_fill, step_bits, restart_fn, walk_fn

local function start_job(s)
  local excl = vim.g.DirDiffExcludes or ''
  local cmd = { 'python3', '-X', 'utf8', script_path(), s.a, s.b, '--exclude', excl,
    '--trust-mtime', (tonumber(vim.g.vimide_dirdiff_trust_mtime) or 1) ~= 0 and '1' or '0' }
  if (tonumber(vim.g.vimide_dirdiff_debug) or 0) ~= 0 then
    cmd[#cmd + 1] = '--debug'
  end
  local partial = ''
  local me
  me = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      -- R 로 멈춘 앞의 뒤쪽이 아직 내보내던 것은 버린다 (새 비교에 섞였다)
      if not data or me ~= s.job then
        return
      end
      data[1] = partial .. data[1]
      partial = data[#data]
      for i = 1, #data - 1 do
        local line = data[i]
        if line ~= '' then
          local ok, ev = pcall(vim.json.decode, line)
          if ok and type(ev) == 'table' then
            on_event(s, ev)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if me ~= s.job then
        return
      end
      local msg = table.concat(data or {}, '\n'):gsub('%s+$', '')
      if msg ~= '' then
        s.stderr = (s.stderr or '') .. msg .. '\n'
      end
    end,
    on_exit = function(_, code)
      if me ~= s.job or s.closing then
        return
      end
      vim.schedule(function()
        if me ~= s.job then
          return
        end
        -- 뒤쪽이 죽었다: 하던 복사는 끝나지 않는다 ('copied' 가 오지 않는다). 풀어 두지 않았더니
        -- q 와 그 뒤의 복사가 끝내 '복사하는 중' 으로 거절되었다
        s.job = nil
        local c = s.copying
        s.copying = nil
        local msg = {}
        if c then
          msg[#msg + 1] = ('%s → %s 복사가 중간에 멈췄습니다 - %s 쪽에 일부만 복사되었을 수 있습니다 (R 로 다시 훑기)')
            :format(c.from:upper(), c.to:upper(), c.to:upper())
        end
        if code ~= 0 then
          msg[#msg + 1] = '비교가 멈췄습니다 (code ' .. code .. ') ' .. (s.stderr or '')
        end
        if #msg > 0 then
          say(table.concat(msg, ' / '), vim.log.levels.WARN)
        end
      end)
    end,
  })
  s.job = me
  if s.job <= 0 then
    say('python3 을 찾을 수 없습니다', vim.log.levels.WARN)
    return false
  end
  return true
end

local function request_list(s, rel)
  s.req = s.req + 1
  s.loading[rel] = true
  send(s, { cmd = 'list', id = s.req, dir = rel })
end

local function store_list(s, rel, entries)
  local d = { entries = {}, idx = {} }
  for _, e in ipairs(entries) do
    local x = { name = e[1], ka = nz(e[2]), kb = nz(e[3]), sa = nz(e[4]), sb = nz(e[5]),
      ma = nz(e[6]), mb = nz(e[7]), st = e[8], rerr = nz(e[9]), m = nz(e[10]) }
    d.entries[#d.entries + 1] = x
    d.idx[x.name] = x
    if e[10] == nil then
      s.nomask = true   -- 예전 뒤쪽 (표시를 보내지 않는다 - mask_of 가 어림한다, walk)
    end
  end
  s.dirs[rel] = d
  s.loading[rel] = nil
  s.need_full = true
end

local function join(dir, name)
  return dir == '' and name or (dir .. '/' .. name)
end

local function is_dir(e)
  return e.ka == 'd' or e.kb == 'd'
end

local function both_dirs(e)
  return e.ka == 'd' and e.kb == 'd'
end

local function is_item(e)
  return (BAD[e.st] and not both_dirs(e)) or e.rerr ~= nil
end

on_event = function(s, ev)
  local k = ev.ev
  if k == 'copied' then
    copied_fn(s, ev)
    return
  end
  if k == 'list' then
    store_list(s, ev.dir, ev.entries or {})
    for _, ro in pairs(s.reopen or {}) do
      if ev.dir == ro.parent then
        ro.ready = true       -- 복사한 뒤의 새 판정이 왔다 - 이제 그 짝을 다시 연다
      end
    end
    if s.walk and s.walk.wait == ev.dir then
      s.walk.wait = nil
      walk_fn(s)              -- 예전 뒤쪽의 보기 <C-n>/<C-p>: 기다리던 목록이 왔다 (walk)
    end
    -- R 뒤: 펼쳐 두었던 아래 디렉터리는 부모의 목록이 온 뒤에 청한다 (한꺼번에 청했더니
    -- 새 뒤쪽이 아직 부모를 훑지 않아 빈 목록을 돌려주었고, 펼친 폴더가 모두 비었다)
    for _, e in ipairs(s.dirs[ev.dir].entries) do
      local c = join(ev.dir, e.name)
      if is_dir(e) and s.expanded[c] and not s.dirs[c] and not s.loading[c] then
        request_list(s, c)
      end
    end
    schedule_render(s)
  elseif k == 'lists' or k == 'reveal' then
    for rel, entries in pairs(ev.lists or {}) do
      store_list(s, rel, entries)
      s.expanded[rel] = true
    end
    local path = nz(ev.path)   -- JSON null 은 vim.NIL (참) 이다
    if k == 'reveal' then
      s.reveal_path = path
      if not path then
        local done = s.prog and s.prog.done
        if step_bits(s) then
          say(s.reveal_step > 0 and (done and '이 보기에서 마지막입니다' or '아래로는 아직 이 보기에 맞는 것이 없습니다 (훑는 중)')
            or (done and '이 보기에서 처음입니다' or '위로는 아직 이 보기에 맞는 것이 없습니다 (훑는 중)'))
        else
          say(s.reveal_step > 0 and (done and '마지막 차이입니다' or '아래로는 아직 찾은 차이가 없습니다 (훑는 중)')
            or (done and '첫 차이입니다' or '위로는 아직 찾은 차이가 없습니다 (훑는 중)'))
        end
      end
    end
    if next(ev.lists or {}) ~= nil or not (path and s.row_of[path]) then
      render(s)
    end
    if k == 'reveal' and path and s.row_of[path] and api.nvim_win_is_valid(s.win_l) then
      goto_row(s, s.row_of[path])
      mark_side(s)
    end
  elseif k == 'u' then
    local d = s.dirs[ev.d]
    local e = d and d.idx[ev.n]
    if e then
      e.st = ev.s
      local x = ev.e
      if type(x) == 'table' then
        e.sa, e.sb, e.ma, e.mb, e.rerr, e.m = nz(x[4]), nz(x[5]), nz(x[6]), nz(x[7]), nz(x[9]), nz(x[10])
      end
      s.dirty[join(ev.d, ev.n)] = true
      schedule_render(s)
    end
  elseif k == 'progress' then
    s.prog = ev
    s.prog_dirty = true
    schedule_render(s)
    if s.menu then
      menu_fill(s)   -- 보기 메뉴의 수도 훑는 대로
    end
  elseif k == 'error' then
    say(ev.msg or '?', vim.log.levels.WARN)
  end
end

-- ---------------------------------------------------------------------------
-- 그리기
-- ---------------------------------------------------------------------------

-- 지금 보기가 거르는가 (모두 보이기가 아닌가)
local function filtering(s)
  return MODE[s.mode].bits ~= nil
end

-- 표시가 없으면 (뒤쪽이 예전 것) 판정으로 어림한다 - 디렉터리는 '같음' 이 아니면 늘 보인다. '다름' 은
-- 뒤쪽의 item_mask 처럼 날짜로 최신 쪽을 가린다 (예전 뒤쪽도 날짜는 보낸다): 모두 DX 로 두었더니 좌측·우측
-- 최신 보기에 파일이 하나도 보이지 않았다
local function mask_of(e)
  if e.m then
    return e.m
  end
  if both_dirs(e) then
    -- '같음' 인 디렉터리는 그 아래를 다 훑었고 모두 같다 - 동일이다. 늘 UNK 로 두었더니 차이·고아·최신
    -- 보기에도 같은 디렉터리(빈 것도)가 남았다 (예전 .lua 는 '같음' 을 걸렀다)
    return e.st == 'same' and SAME or UNK
  end
  if e.st == 'diff' then
    if e.ka ~= e.kb then
      return DX + (e.ka == 'd' and OA or 0) + (e.kb == 'd' and OB or 0)
    end
    if e.ma and e.mb and e.ma ~= e.mb then
      return e.ma > e.mb and NA or NB
    end
    return DX
  end
  return ({ same = SAME, onlyA = OA, onlyB = OB, pend = PEND })[e.st] or DX
end

-- 보기에 이 줄이 보이는가. 아직 모르는 것(견주는 중, 훑지 않은 디렉터리)은 될 수 있는 것이면
-- 보인다 - 그래야 훑는 동안 줄이 새로 생기지 않고 빠지기만 해서, 바뀐 줄만 지우면 된다
-- (render_dirty. 생기는 줄이 있으면 그때마다 트리 전체를 다시 그려야 한다)
local function visible(s, e)
  local bits = MODE[s.mode].bits
  if not bits then
    return true
  end
  local m = mask_of(e)
  if band(m, bits) ~= 0 or band(m, UNK) ~= 0 then
    return true
  end
  if both_dirs(e) then
    -- 디렉터리 자신: 양쪽에 있으니 고아가 아니고, '같음' 이면 동일이다
    if MODE[s.mode].both or (band(bits, SAME) ~= 0 and e.st == 'same') then
      return true
    end
    return band(m, PEND) ~= 0 and band(bits, SAME + NA + NB + DX) ~= 0
  end
  if band(m, PEND) == 0 then
    return false
  end
  -- 견주는 중인 파일: 고아는 아니다. 날짜를 알면 최신 쪽으로 좁힌다 - 그러지 않으면 좌측 최신
  -- 보기에 B 쪽이 늦은 파일도 내용을 다 읽을 때까지 보인다
  if band(bits, SAME + DX) ~= 0 then
    return true
  end
  local known = e.ma and e.mb
  return (band(bits, NA) ~= 0 and (not known or e.ma > e.mb))
    or (band(bits, NB) ~= 0 and (not known or e.mb > e.ma)) or false
end

-- 펼친 디렉터리만 따라 내려가며 줄을 만든다. 줄마다 안내선 거리도 쪽마다 적는다 (Beyond Compare 는 반쪽마다
-- 제 트리의 가지를 긋는다 - 다른 쪽에만 있는 형제는 세지 않는다): pa/pb = 조상(깊이 1 부터)마다 그쪽에서
-- 그 아래로 형제가 더 있는지('1'/'0'), la/lb = 그쪽에서 이 줄 뒤로 형제가 없는지 (tr.guide)
render_rows = function(s)
  local rows = {}
  local function walk(rel, depth, pa, pb)
    local d = s.dirs[rel]
    if not d then
      if s.loading[rel] then
        rows[#rows + 1] = { rel = rel .. '/', depth = depth, loading = true, pa = pa, pb = pb, la = true, lb = true }
      end
      return
    end
    local vis = {}
    local lasta, lastb = 0, 0
    for _, e in ipairs(d.entries) do
      if visible(s, e) then
        vis[#vis + 1] = e
        if e.ka ~= nil then
          lasta = #vis
        end
        if e.kb ~= nil then
          lastb = #vis
        end
      end
    end
    for i, e in ipairs(vis) do
      local r = join(rel, e.name)
      local row = { rel = r, dir = rel, depth = depth, e = e, pa = pa, pb = pb, la = i >= lasta, lb = i >= lastb }
      rows[#rows + 1] = row
      if is_dir(e) and s.expanded[r] then
        -- 맨 위 줄의 아이들은 맨 왼쪽에서 가지를 친다 (그 위로는 선이 없다)
        if depth == 0 then
          walk(r, 1, '', '')
        else
          walk(r, depth + 1, pa .. (row.la and '0' or '1'), pb .. (row.lb and '0' or '1'))
        end
      end
    end
  end
  walk('', 0, '', '')
  s.rows = rows
  s.row_of = {}
  for i, r in ipairs(rows) do
    if r.e then
      s.row_of[r.rel] = i
    end
  end
end

-- 줄이 빠진 뒤(render_dirty - 보기가 거르는 중에 '같음' 이 된 줄) 안내선 거리를 지금 줄들로 다시 센다.
-- render_rows 의 walk 와 같은 셈을 부모마다: 그쪽에 있는 마지막 형제(la/lb), 조상의 이음(pa/pb - 부모가
-- 앞 줄이라 먼저 고쳐져 있다). 돌려주는 것: 바뀐 줄 번호들
function tr.reguide(s)
  local rows = s.rows
  local kids = {}
  for i, r in ipairs(rows) do
    if r.e then
      kids[r.dir] = kids[r.dir] or {}
      table.insert(kids[r.dir], i)
    end
  end
  local la, lb = {}, {}
  for _, list in pairs(kids) do
    local lasta, lastb = 0, 0
    for k, i in ipairs(list) do
      if rows[i].e.ka ~= nil then
        lasta = k
      end
      if rows[i].e.kb ~= nil then
        lastb = k
      end
    end
    for k, i in ipairs(list) do
      la[i], lb[i] = k >= lasta, k >= lastb
    end
  end
  local changed = {}
  for i, r in ipairs(rows) do
    if r.e then
      local pa, pb = '', ''
      local p = r.depth > 1 and rows[s.row_of[r.dir] or 0]
      if p then
        pa, pb = p.pa .. (p.la and '0' or '1'), p.pb .. (p.lb and '0' or '1')
      end
      if pa ~= r.pa or pb ~= r.pb or la[i] ~= r.la or lb[i] ~= r.lb then
        r.pa, r.pb, r.la, r.lb = pa, pb, la[i], lb[i]
        changed[#changed + 1] = i
      end
    end
  end
  return changed
end

-- 반쪽의 칸 (Beyond Compare 의 폴더 비교): 이름(안내선 + 아이콘 + 이름) | 크기 | 날짜 | 시각. 좁으면
-- 시각, 날짜, 크기 순으로 뺀다 (이름 칸이 크기 18, 날짜 22, 시각 24 칸은 남게)
local function layout(s)
  local W = api.nvim_win_get_width(s.win_l)
  local half = math.floor((W - 3) / 2)
  local f = tr.datefmt()
  local SZ = 12   -- ' ' + 11 칸 (9,999,999,999)
  local dw = f.dw > 0 and (1 + f.dw) or 0
  local tw = f.tw > 0 and (1 + f.tw) or 0
  local size = half - SZ >= 18
  local date = size and dw > 0 and half - SZ - dw >= 22
  local time = size and tw > 0 and (date or dw == 0) and half - SZ - dw - tw >= 24
  return { W = W, half = half, size = size, date = date, time = time, f = f,
    sz = SZ, dw = date and dw or 0, tw = time and tw or 0 }
end

-- 한쪽(A 또는 B) 반 칸
-- 화면에 쓸 이름: 줄바꿈 같은 제어 문자는 ^J 로 (줄에 \n 이 들어가면 nvim_buf_set_lines 가
-- 트리 전체를 못 그렸다). 경로·주고받기에는 원래 이름을 쓴다
local function shown(name)
  return vim.fn.strtrans(name)
end

-- 안내선 (Beyond Compare 의 옅은 점선 가지): 조상마다 '│ ' / '  ', 제 가지 '├─' / '└─'. 깊이 0 은 없다.
-- 그쪽에 없는 줄(고아의 빈 반쪽)은 가지 없이 지나가는 선만 ('│ ' - 그쪽에 뒤 형제가 있을 때).
-- ASCII 는 '| ' '|-' '`-' (│ ├ └ 는 East Asian Ambiguous 라 CJK 글꼴 터미널이 두 칸으로 그려 줄이 밀린다 -
-- neo-tree 의 안내선과 같은 까닭)
function tr.guide(r, side, absent)
  if r.depth == 0 then
    return ''
  end
  local a = ascii()
  local pre = side == 'b' and r.pb or r.pa
  local last
  if side == 'b' then
    last = r.lb
  else
    last = r.la
  end
  local t = {}
  for k = 1, #pre do
    t[k] = pre:sub(k, k) == '1' and (a and '| ' or '│ ') or '  '
  end
  if absent then
    t[#t + 1] = last and '  ' or (a and '| ' or '│ ')
  else
    t[#t + 1] = last and (a and '`-' or '└─') or (a and '|-' or '├─')
  end
  return table.concat(t)
end

-- 아이콘: 폴더는 열림/닫힘 (Nerd Font , ASCII v >), 파일은 작은 네모 (Beyond Compare 의 색 네모 -
-- 이름과 같은 색, ASCII -). 모두 두 칸 (Nerd Font 글자는 한 칸을 넘쳐 그려지므로 뒤에 빈칸)
function tr.icon(k, open)
  if k == 'd' then
    if ascii() then
      return open and 'v ' or '> '
    end
    return open and '\u{f07c} ' or '\u{f07b} '
  end
  return ascii() and '- ' or '▪ '
end

local function side_text(s, L, r, side)
  local e = r.e
  -- 'side == "a" and e.ka or e.kb' 로 썼더니 A 에 없는 것(e.ka == nil)이 B 의 것으로
  -- 떨어져 B 에만 있는 줄이 A 쪽에도 그려졌다
  local k, sz, mt
  if side == 'a' then
    k, sz, mt = e.ka, e.sa, e.ma
  else
    k, sz, mt = e.kb, e.sb, e.mb
  end
  if k == nil then
    -- 그쪽에 없다: 지나가는 안내선만 (absent - 이름·고르기는 없다)
    local g = vim.fn.strcharpart(tr.guide(r, side, true), 0, L.half)
    if g:find('%S') then
      return g .. string.rep(' ', L.half - vim.fn.strchars(g)), { absent = true, g_end = #g }
    end
    return string.rep(' ', L.half), nil
  end
  local tail = ''
  if L.size then
    -- 폴더의 크기는 비운다: 뒤쪽은 폴더 아래 크기의 합을 세지 않는다 (펼친 것만 더하면 거짓 수다)
    tail = ' ' .. rjust(k == 'd' and '' or commas(sz), L.sz - 1)
  end
  if L.date then
    tail = tail .. ' ' .. tr.cell(L.f, 'd', mt, L.dw - 1)
  end
  if L.time then
    tail = tail .. ' ' .. tr.cell(L.f, 't', mt, L.tw - 1)
  end
  local guide = tr.guide(r, side)
  local icon = tr.icon(k, s.expanded[r.rel])
  local gw = 2 * r.depth
  local iconw = 2
  local tailw = (L.size and L.sz or 0) + L.dw + L.tw
  local namew = L.half - gw - iconw - tailw
  -- 깊은 줄이 반 칸을 넘으면 판정 칸과 B 쪽이 밀린다: 안내선을 뿌리 쪽부터 덜고, 그다음 크기·날짜를 줄인다
  if namew < 8 then
    local cut = math.min(gw, 8 - namew)
    guide = vim.fn.strcharpart(guide, cut)
    gw = gw - cut
    namew = L.half - gw - iconw - tailw
  end
  if namew < 1 then
    tail = ''
    namew = L.half - gw - iconw
  end
  if namew < 1 then
    guide, gw = '', 0
    namew = L.half - iconw
  end
  local bad = e.rerr and e.rerr:find(side, 1, true) and ' (못 읽음)' or ''
  local name = fit(shown(e.name) .. (k == 'l' and ' @' or '') .. bad, namew)
  local ie = #guide + #icon
  -- name_vis: 채운 빈칸을 뺀 이름 끝 (Tab 으로 고른 [A] 를 그 뒤에 단다). g_end/i_end: 안내선·아이콘 끝
  return guide .. icon .. name .. tail, { g_end = #guide, i_end = ie, name_start = ie, name_end = ie + #name,
    tail = #tail, name_vis = ie + #(name:gsub(' +$', '')) }
end

-- 다른 파일의 그쪽 색: 수정 시각이 늦으면 빨강, 이르면 회색, 같거나 모르면 빨강
function tr.newer_g(mine, other)
  if mine and other and mine < other then
    return 'VimIdeDirDiffOlder'
  end
  return 'VimIdeDirDiffNewer'
end

-- 양쪽에 있는 폴더의 아이콘 색 (그쪽에서 본 그 아래): 뒤쪽이 주는 폴더의 표시(mask - 아래 모두를 합한
-- 것, dirdiffscan.py 의 dir_mask)로 가린다. Beyond Compare 처럼 늦은 쪽인 차이(그쪽 최신, 또는 시각이 같은·
-- 모르는·종류가 다른 다름 DX)가 있으면 빨강 > 이른 쪽인 차이가 있으면 회색 > 그 밖(같음, 고아만, 아직
-- 훑는 중)은 보통 폴더색. 고아만 든 폴더를 파랑으로 했더니 Beyond Compare 의 첫 사진과 달랐다 (거기서는
-- 고아만 든 폴더도 보통 연보라 폴더다 - 파랑은 고아 파일의 이름뿐). 예전 뒤쪽(표시 없음)은 폴더의 판정과
-- 폴더 자신의 수정 시각으로 어림한다 - 다르면 늦은 쪽 빨강·이른 쪽 회색
function tr.folder_g(e, side)
  local m = e.m
  local mine_t, other_t
  if side == 'a' then
    mine_t, other_t = e.ma, e.mb
  else
    mine_t, other_t = e.mb, e.ma
  end
  if not m then
    return e.st == 'diff' and tr.newer_g(mine_t, other_t) or 'VimIdeDirDiffFolder'
  end
  local mine_new, other_new = NA, NB
  if side == 'b' then
    mine_new, other_new = NB, NA
  end
  if band(m, mine_new + DX) ~= 0 then
    return 'VimIdeDirDiffNewer'
  elseif band(m, other_new) ~= 0 then
    return 'VimIdeDirDiffOlder'
  end
  return 'VimIdeDirDiffFolder'
end

-- 반쪽의 색: 이름, 크기·날짜, 아이콘 (nil 은 보통 글자)
function tr.classes(e, side)
  local k, other, mine_t, other_t
  if side == 'a' then
    k, other, mine_t, other_t = e.ka, e.kb, e.ma, e.mb
  else
    k, other, mine_t, other_t = e.kb, e.ka, e.mb, e.ma
  end
  local st = e.st
  if pal() ~= 'bc' then
    -- neogit·classic: 예전 색 (다른 것은 양쪽이 같은 다름 색, 한쪽에만은 그쪽 색)
    local group
    if st == 'diff' then
      group = 'VimIdeDirDiffChanged'
    elseif st == 'pend' then
      group = 'VimIdeDirDiffPending'
    elseif st == 'same' then
      group = is_dir(e) and 'VimIdeDirDiffDir' or nil
    end
    local mine = (side == 'a' and st == 'onlyA' and 'VimIdeDirDiffOnlyA')
      or (side == 'b' and st == 'onlyB' and 'VimIdeDirDiffOnlyB') or nil
    local g = mine or group
    local data = (st == 'diff' or mine) and g or 'VimIdeDirDiffSize'
    return g, data, k == 'd' and (g or 'VimIdeDirDiffFolder') or g
  end
  if both_dirs(e) then
    local bad = e.rerr and e.rerr:find(side, 1, true) and 'VimIdeDirDiffChanged' or nil
    return bad, 'VimIdeDirDiffDim', tr.folder_g(e, side)
  end
  if e.rerr and e.rerr:find(side, 1, true) then
    return 'VimIdeDirDiffChanged', 'VimIdeDirDiffChanged', 'VimIdeDirDiffChanged'
  end
  if k == 'd' then
    -- 고아 폴더 (한쪽은 폴더, 한쪽은 파일인 줄의 폴더 쪽도): Beyond Compare 처럼 양쪽에 있는 폴더와 같은
    -- 꼴 - 이름 보통 글자, 날짜 옅은 회색, 보통 폴더 아이콘 (첫 사진의 chime_16bit·tcc805x)
    return nil, 'VimIdeDirDiffDim', 'VimIdeDirDiffFolder'
  end
  if st == 'onlyA' or st == 'onlyB' then
    -- 고아 파일
    return 'VimIdeDirDiffOrphan', 'VimIdeDirDiffOrphan', 'VimIdeDirDiffOrphan'
  end
  if st == 'diff' then
    -- 폴더와 견주는 파일 쪽은 시각을 견줄 것이 아니다 - 다름 그대로
    local g = other == 'd' and 'VimIdeDirDiffChanged' or tr.newer_g(mine_t, other_t)
    return g, g, g
  end
  -- 같음, 확인 중(판정 칸의 흐린 · 가 알린다): 보통 글자
  return nil, nil, nil
end

-- 가운데 판정 칸 (글자, 색). bc: 다른 파일 ≠, 같은 파일 =, 확인 중 ·, 고아와 양쪽에 있는 폴더는 비운다
-- (Beyond Compare 처럼). neogit·classic 은 예전 것 (◀ ▶ 까지)
function tr.verdict(e)
  local st = e.st
  if pal() ~= 'bc' then
    local g
    if st == 'same' then
      g = 'VimIdeDirDiffPending'
    else
      g = (st == 'diff' and 'VimIdeDirDiffChanged') or (st == 'onlyA' and 'VimIdeDirDiffOnlyA')
        or (st == 'onlyB' and 'VimIdeDirDiffOnlyB') or 'VimIdeDirDiffPending'
    end
    return sym(st), g
  end
  if both_dirs(e) then
    return ' ', nil
  end
  if st == 'diff' then
    return ascii() and 'x' or '≠', 'VimIdeDirDiffNeq'
  elseif st == 'same' then
    return '=', 'VimIdeDirDiffEq'
  elseif st == 'pend' then
    return ascii() and '.' or '·', 'VimIdeDirDiffPending'
  end
  return ' ', nil
end

-- 반쪽의 색을 hls 에 (off: 그 반쪽이 줄에서 시작하는 바이트)
function tr.side_hls(hls, e, side, m, off)
  if not m then
    return
  end
  if m.absent then
    hls[#hls + 1] = { 'VimIdeDirDiffGuide', off, off + m.g_end }
    return
  end
  local name_g, data_g, icon_g = tr.classes(e, side)
  if m.g_end > 0 then
    hls[#hls + 1] = { 'VimIdeDirDiffGuide', off, off + m.g_end }
  end
  if icon_g then
    hls[#hls + 1] = { icon_g, off + m.g_end, off + m.i_end }
  end
  if name_g then
    hls[#hls + 1] = { name_g, off + m.name_start, off + m.name_end }
  end
  if data_g and m.tail > 0 then
    hls[#hls + 1] = { data_g, off + m.name_end, off + m.name_end + m.tail }
  end
end

local function line_of(s, L, r)
  if r.loading then
    local g = tr.guide(r, 'a')
    return g .. '  (읽는 중…)', { { 'VimIdeDirDiffGuide', 0, #g } }, nil
  end
  local e = r.e
  local lt, lm = side_text(s, L, r, 'a')
  local vt, vg = tr.verdict(e)
  local g = ' ' .. vt .. ' '
  local rt, rm = side_text(s, L, r, 'b')
  local text = lt .. g .. rt
  local hls = {}
  local off_g = #lt
  local off_b = #lt + #g
  tr.side_hls(hls, e, 'a', lm, 0)
  tr.side_hls(hls, e, 'b', rm, off_b)
  if vg then
    hls[#hls + 1] = { vg, off_g, off_b }
  end
  if lm and not lm.absent and s.marks.a[r.rel] then
    hls[#hls + 1] = { 'VimIdeDirDiffMark', lm.name_start, lm.name_end }
  end
  if rm and not rm.absent and s.marks.b[r.rel] then
    hls[#hls + 1] = { 'VimIdeDirDiffMark', off_b + rm.name_start, off_b + rm.name_end }
  end
  return text, hls, off_b, off_g
end

local function put_hls(s, lnum, hls)
  for _, h in ipairs(hls) do
    if h[1] then
      pcall(api.nvim_buf_set_extmark, s.buf_l, ns, lnum - 1, h[2], { end_col = h[3], hl_group = h[1] })
    end
  end
end

-- 트리 창의 상태줄 ('statusline' 에 그대로 쓰는 글 - % 는 이미 %% 로). classic 이 아니면 이름표에 색:
-- 'DirDiff'·보기 이름은 절 머리, 다름·A만·B만 은 트리의 그 색(bc 는 상태줄 바탕에 맞춘 짝 - VimIdeDirDiffSt*),
-- 도움말은 흐리게
local function status_text(s)
  local p = s.prog or {}
  local parts = {}
  local function esc(t)
    return (t:gsub('%%', '%%%%'))
  end
  if p.done then
    parts[#parts + 1] = ('끝 %.1f초'):format(p.sec or 0)
  elseif p.again then
    parts[#parts + 1] = '바뀐 곳을 다시 보는 중'   -- 복사한 곳, :w 로 저장한 파일
  else
    parts[#parts + 1] = ('훑는 중 %d초 · 디렉터리 %s'):format(math.floor(p.sec or 0), commas(p.dirs or 0))
  end
  parts[#parts + 1] = ('파일 %s'):format(commas(p.files or 0))
  parts[#parts + 1] = hl_part('VimIdeDirDiffStChanged', ('다름 %s'):format(commas(p.diff or 0)))
  parts[#parts + 1] = hl_part('VimIdeDirDiffStOnlyA', ('A만 %s'):format(commas(p.onlyA or 0)))
  parts[#parts + 1] = hl_part('VimIdeDirDiffStOnlyB', ('B만 %s'):format(commas(p.onlyB or 0)))
  if (p.pend or 0) > 0 then
    parts[#parts + 1] = hl_part('VimIdeDirDiffPending', ('확인 중 %s'):format(commas(p.pend)))
  end
  if (p.err or 0) > 0 then
    parts[#parts + 1] = ('읽기 실패 %s'):format(commas(p.err))
  end
  local na, nb = vim.tbl_count(s.marks.a), vim.tbl_count(s.marks.b)
  if na + nb > 0 then
    parts[#parts + 1] = ('고름 A %d / B %d'):format(na, nb)
  end
  return ' ' .. hl_part('VimIdeDirDiffHeader', 'DirDiff') .. '  ' .. table.concat(parts, ' · ')
    .. '   ' .. hl_part('VimIdeDirDiffHeader', '[' .. esc(MODE[s.mode].label) .. ']')
    .. '   [' .. (s.side == 'b' and 'B' or 'A') .. ' 쪽]   ' .. hl_part('VimIdeDirDiffPending', '(? 도움말)')
end

-- 보이는 줄이 하나도 없을 때
local function empty_text(s)
  if not (s.prog and s.prog.done) then
    return '  (훑는 중…)'
  end
  if s.mode == 'all' or s.mode == 'diff' then
    return '  (차이가 없습니다)'
  end
  return ('  (%s: 보일 것이 없습니다 - f 로 보기를 바꿉니다)'):format(MODE[s.mode].label)
end

-- 트리 위의 두 줄 (Beyond Compare 의 경로 칸 둘과 칸 제목): 경로 줄 창(트리 바로 위의 한 줄짜리 창,
-- filetype vimidedirdiffhead)에 A·B 의 뿌리를 반쪽마다 - 지금 쪽(A/B)이 연두 칸 -, 그 창의 상태줄에 칸
-- 제목(이름 크기 수정일). 'laststatus' 가 0·3 이면 창마다 상태줄이 없어서 칸 제목은 트리 창의 winbar 에.
-- 둘 다 트리를 내려도 그대로고, 트리를 그릴 때마다(창 너비가 바뀌면 WinResized) 트리와 같은 칸에 다시
-- 맞춘다. winbar 하나로는 두 줄을 둘 수 없고, 버퍼 첫 줄에 두면 내려가며 사라진다. 경로 줄 창에는 들어가지
-- 않는다 (들어가면 트리로 - 누른 쪽으로 A/B 쪽을 바꾼다, cmp.bounce). :only 등으로 닫히면 그 탭에서 다음에
-- 그릴 때 다시 만든다
function tr.titles_in_head()
  local ls = vim.o.laststatus
  return ls ~= 0 and ls ~= 3
end

-- 칸 제목 반쪽 (트리 줄과 같은 칸: 이름 | 오른쪽 맞춘 크기 | 수정일)
function tr.title_half(L)
  local tailw = (L.size and L.sz or 0) + L.dw + L.tw
  local t = fit(' 이름', L.half - tailw)
  if L.size then
    t = t .. rjust('크기', L.sz)
  end
  if L.dw + L.tw > 0 then
    t = t .. ' ' .. fit('수정일', L.dw + L.tw - 1)
  end
  return t
end

function tr.titles(L)
  local h = tr.title_half(L)
  local t = h .. '   ' .. h
  t = t .. string.rep(' ', math.max(0, L.W - vim.fn.strdisplaywidth(t)))
  return '%#VimIdeDirDiffColHead#' .. (t:gsub('%%', '%%%%'))
end

-- 곁 창(경로 줄·개요 막대·줄 자세히)의 창 옵션: 갈라 만든 창의 옵션(트리의 상태줄, 비교 창의 diff·
-- 묶기·접기·winbar ...)을 물려받으므로 모두 걷는다. 파일이 이 창에 열리지 않게 winfixbuf (0.10 부터)
function tr.plain_extra(w)
  for k, v in pairs({ number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0',
    statuscolumn = '', cursorline = false, cursorcolumn = false, colorcolumn = '', wrap = false,
    list = false, spell = false, winbar = '', winhighlight = '', scrolloff = 0, sidescrolloff = 0,
    diff = false, scrollbind = false, cursorbind = false, foldenable = false, foldmethod = 'manual',
    fillchars = 'eob: ', statusline = ' ', winfixbuf = true }) do
    set_wo(w, k, v)
  end
end

function tr.head_ensure(s)
  if not (api.nvim_win_is_valid(s.win_l) and api.nvim_buf_is_valid(s.buf_l)) then
    return false
  end
  if s.hwin and api.nvim_win_is_valid(s.hwin) then
    return true
  end
  -- 다른 탭의 창 옆에는 만들지 않는다 (그 탭에 들어가 다시 그릴 때)
  if api.nvim_win_get_tabpage(s.win_l) ~= api.nvim_get_current_tabpage() then
    return false
  end
  if not (s.hbuf and api.nvim_buf_is_valid(s.hbuf)) then
    local b = api.nvim_create_buf(false, true)
    vim.bo[b].bufhidden = 'wipe'
    vim.b[b].airline_disable_statusline = 1   -- airline 이 칸 제목(상태줄)을 제 것으로 바꾸지 않게
    vim.bo[b].filetype = 'vimidedirdiffhead'
    pcall(api.nvim_buf_set_name, b, 'DirDiff 경로 #' .. b)
    s.hbuf = b
  end
  local w = cmp.open_extra(s.hbuf, { split = 'above', win = s.win_l, height = 1 })
  if not w then
    return false
  end
  s.hwin = w
  tr.plain_extra(w)
  set_wo(w, 'winfixheight', true)
  -- 편집 창 둘 아래의 트리(pair_tab = 0)는 높이를 지킨다 (한 줄을 편집 창에서 가져온다)
  if not s.pair_tab and s.list_h then
    pcall(api.nvim_win_set_height, s.win_l, s.list_h)
  end
  return true
end

-- 경로 줄: 반쪽마다 ' A  경로' (넘치면 앞쪽을 자른다), 지금 쪽 칸은 연두
function tr.head_line(s, L)
  local function half(tag, path)
    return ' ' .. tag .. '  ' .. tr.fit_left(shown(vim.fn.fnamemodify(path, ':~')), L.half - 4)
  end
  local a, b = half('A', s.a), half('B', s.b)
  local line = a .. '   ' .. b
  line = line .. string.rep(' ', math.max(0, L.W - vim.fn.strdisplaywidth(line)))
  local ob = #a + 3
  local hls = {
    { s.side == 'a' and 'VimIdeDirDiffPathOn' or 'VimIdeDirDiffPath', 0, #a },
    { 'VimIdeDirDiffColHead', #a, ob },
    { s.side == 'b' and 'VimIdeDirDiffPathOn' or 'VimIdeDirDiffPath', ob, ob + #b },
    { 'VimIdeDirDiffColHead', ob + #b, #line },
    { 'VimIdeDirDiffHeader', 1, 2 },
    { 'VimIdeDirDiffHeader', ob + 1, ob + 2 },
  }
  return line, hls
end

function tr.head_render(s, L)
  local in_head = tr.titles_in_head()
  if tr.head_ensure(s) then
    local line, hls = tr.head_line(s, L)
    local b = api.nvim_win_get_buf(s.hwin)
    vim.bo[b].modifiable = true
    api.nvim_buf_set_lines(b, 0, -1, false, { line })
    vim.bo[b].modifiable = false
    api.nvim_buf_clear_namespace(b, NS.head, 0, -1)
    for i, h in ipairs(hls) do
      pcall(api.nvim_buf_set_extmark, b, NS.head, 0, h[2], { end_col = h[3], hl_group = h[1], priority = 100 + i })
    end
    set_wo(s.hwin, 'statusline', in_head and tr.titles(L) or ' ')
    if api.nvim_win_get_height(s.hwin) ~= 1 then
      pcall(api.nvim_win_set_height, s.hwin, 1)
    end
  else
    in_head = false   -- 경로 줄 창이 없다 (다른 탭에서 그렸다): 칸 제목은 트리의 winbar 에
  end
  set_wo(s.win_l, 'winbar', in_head and '' or tr.titles(L))
end

-- 줄 i 로, 지금 쪽(A/B)의 이름 자리에 커서를
goto_row = function(s, i)
  if not (i and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  local col = s.side == 'b' and (s.offb and s.offb[i]) or 0
  pcall(api.nvim_win_set_cursor, s.win_l, { i, col or 0 })
end

-- 커서 줄의 지금 쪽 반 칸을 고른 줄 색(연두)으로. 줄 전체는 칠하지 않는다 (트리 창은 cursorline
-- 을 끈다 - tree_opts): Beyond Compare 처럼 커서가 있는 쪽만 골라진 것으로 보인다. B 쪽은 창 오른쪽
-- 끝까지 (hl_eol). 우선순위는 열어 둔 짝의 줄 색(mark_open 의 line_hl_group)보다 위 - 그 줄에서도
-- 고른 반 칸이 보이고, 나머지 반 칸에는 열어 둔 표시가 남는다
mark_side = function(s)
  if not (api.nvim_buf_is_valid(s.buf_l) and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  api.nvim_buf_clear_namespace(s.buf_l, ns_side, 0, -1)
  local i = api.nvim_win_get_cursor(s.win_l)[1]
  local ob = s.offb and s.offb[i]
  if not ob then
    return
  end
  if s.side == 'b' then
    pcall(api.nvim_buf_set_extmark, s.buf_l, ns_side, i - 1, ob,
      { end_row = i, end_col = 0, hl_eol = true, hl_group = 'VimIdeDirDiffSide', priority = 4200 })
  else
    pcall(api.nvim_buf_set_extmark, s.buf_l, ns_side, i - 1, 0,
      { end_col = (s.offg and s.offg[i]) or ob, hl_group = 'VimIdeDirDiffSide', priority = 4200 })
  end
end

-- 지금 열어 둔 짝의 줄에 바탕색: 위의 편집 창 둘에 보이는 것(pair_tab = 0), 비교 탭이 열려 있는
-- 짝 모두 (pair_tab - 어느 짝에 탭이 있는지 트리에서 보인다)
local function mark_open(s)
  if not api.nvim_buf_is_valid(s.buf_l) then
    return
  end
  api.nvim_buf_clear_namespace(s.buf_l, ns_open, 0, -1)
  local rels = {}
  if s.main and s.main.rel then
    rels[s.main.rel] = true
  end
  for _, v in pairs(s.views) do
    if v.rel then
      rels[v.rel] = true
    end
  end
  -- 커서 줄에도 단다. line_hl_group 이 아니라 줄 끝까지(hl_eol) 덮는 글자 색으로, 고른 반 칸(mark_side,
  -- 우선순위 4200)보다 낮게: line_hl_group 은 우선순위와 상관없이 글자 색의 바탕을 덮어 고른 반 칸이
  -- 사라졌다. 이러면 커서 줄에서 고른 반 칸은 연두, 다른 반 칸은 이 색이다
  for rel in pairs(rels) do
    local i = s.row_of[rel]
    if i then
      pcall(api.nvim_buf_set_extmark, s.buf_l, ns_open, i - 1, 0,
        { end_row = i, end_col = 0, hl_eol = true, hl_group = 'VimIdeDirDiffOpened', priority = 100 })
    end
  end
end

render = function(s)
  s.render_pending = false
  if not (api.nvim_buf_is_valid(s.buf_l) and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  local keep = s.rows and s.rows[api.nvim_win_get_cursor(s.win_l)[1]]
  keep = keep and keep.rel
  render_rows(s)
  local L = layout(s)
  local lines, all = {}, {}
  s.offb, s.offg = {}, {}
  for i, r in ipairs(s.rows) do
    local t, h, ob, og = line_of(s, L, r)
    lines[i] = t
    all[i] = h
    s.offb[i], s.offg[i] = ob, og
  end
  if #lines == 0 then
    lines = { empty_text(s) }
  end
  vim.bo[s.buf_l].modifiable = true
  api.nvim_buf_set_lines(s.buf_l, 0, -1, false, lines)
  vim.bo[s.buf_l].modifiable = false
  api.nvim_buf_clear_namespace(s.buf_l, ns, 0, -1)
  for i, h in ipairs(all) do
    put_hls(s, i, h)
  end
  mark_open(s)
  s.dirty = {}
  tr.head_render(s, L)
  set_wo(s.win_l, 'statusline', status_text(s))
  if s.want_rel and s.row_of[s.want_rel] then
    goto_row(s, s.row_of[s.want_rel])
    s.want_rel = nil
  elseif keep and s.row_of[keep] then
    goto_row(s, s.row_of[keep])
  end
  mark_side(s)
  -- 복사로 바뀐 파일을 보고 있었으면 그 짝을 다시 연다 (없던 쪽이 생겼다). 부모의 새 목록이
  -- 온 뒤에만 - 먼저 열었더니 옛 항목(없던 쪽 그대로)으로 열고 끝났다. 짝마다 (비교 탭이 여럿일 수 있다):
  -- 그 짝을 보이는 창(위의 편집 창, 그 짝의 비교 탭)에서만 다시 채운다 - 탭을 새로 열거나 옮기지 않는다
  for rel, ro in pairs(s.reopen or {}) do
    if ro.ready then
      s.reopen[rel] = nil
      local e = entry_of_fn(s, rel)
      if e and not is_dir(e) then
        vim.schedule(function()
          if not s.done then
            open_pair_fn(s, { rel = rel, e = e, dir = rel:match('^(.*)/[^/]+$') or '' }, 'refill')
          end
        end)
      end
    end
  end
  if s.want_rel and s.prog and s.prog.done and next(s.loading) == nil then
    s.want_rel = nil   -- 다시 훑은 뒤에 없어진 줄
  end
  s.last_render = uv.now()
end

-- 바뀐 줄만 다시 그린다. 보기가 거르고 있으면(차이 보이기 등) 보기에서 빠진 줄은 그 줄만(펼친
-- 아래까지) 지우고, 새로 보일 줄이 생길 때만 전부 그린다 - 처음에는 거르기가 켜져 있으면 늘 전부 그렸더니,
-- 훑는 동안 60ms 마다 트리 전체를 다시 만들어 편집기가 훑는 시간의 60% 동안 멎었다 (2만 파일
-- 한 폴더, 실측)
local function render_dirty(s)
  s.render_pending = false
  if not (api.nvim_buf_is_valid(s.buf_l) and api.nvim_win_is_valid(s.win_l)) then
    return
  end
  local drop = {}
  if filtering(s) then
    for rel in pairs(s.dirty) do
      local i = s.row_of[rel]
      if not i then
        -- 없던 줄이 보이게 되었다 (펼쳐 보이는 디렉터리 안에서 '같음' 이 아니게 되었다)
        local e = entry_of_fn(s, rel)
        local parent = rel:match('^(.*)/[^/]+$') or ''
        if e and visible(s, e) and (parent == '' or (s.row_of[parent] and s.expanded[parent])) then
          return render(s)
        end
      elseif not visible(s, s.rows[i].e) then
        local j = i
        while s.rows[j + 1] and s.rows[j + 1].depth > s.rows[i].depth do
          j = j + 1
        end
        drop[#drop + 1] = { i, j }
      end
    end
  end
  local L = layout(s)
  vim.bo[s.buf_l].modifiable = true
  for rel in pairs(s.dirty) do
    local i = s.row_of[rel]
    if i and s.rows[i] and visible(s, s.rows[i].e) then
      local t, h, ob, og = line_of(s, L, s.rows[i])
      s.offb[i], s.offg[i] = ob, og
      api.nvim_buf_set_lines(s.buf_l, i - 1, i, false, { t })
      api.nvim_buf_clear_namespace(s.buf_l, ns, i - 1, i)
      put_hls(s, i, h)
    end
  end
  if #drop > 0 then
    local gone = {}
    for _, d in ipairs(drop) do
      for k = d[1], d[2] do
        gone[k] = true
      end
    end
    -- 아래에서부터 이어진 덩어리째 지운다. 색(extmark)을 먼저 걷는다 - 줄만 지웠더니 폭 0 짜리
    -- 색이 다음 줄에 쌓였다
    local k = #s.rows
    while k >= 1 do
      if gone[k] then
        local hi = k
        while k > 1 and gone[k - 1] do
          k = k - 1
        end
        api.nvim_buf_clear_namespace(s.buf_l, ns, k - 1, hi)
        api.nvim_buf_set_lines(s.buf_l, k - 1, hi, false, {})
      end
      k = k - 1
    end
    local rows, offb, offg = {}, {}, {}
    for i, r in ipairs(s.rows) do
      if not gone[i] then
        local n = #rows + 1
        rows[n], offb[n], offg[n] = r, s.offb[i], s.offg[i]
      end
    end
    s.rows, s.offb, s.offg, s.row_of = rows, offb, offg, {}
    for i, r in ipairs(rows) do
      if r.e then
        s.row_of[r.rel] = i
      end
    end
    -- 빠진 줄의 형제·그 아래 줄의 안내선이 바뀌었을 수 있다 (마지막 형제가 빠지면 앞 형제가 └─ 로,
    -- 그 아래의 │ 는 끊긴다) - 바뀐 줄만 다시 쓴다
    for _, i in ipairs(tr.reguide(s)) do
      local t, h, ob, og = line_of(s, L, s.rows[i])
      s.offb[i], s.offg[i] = ob, og
      api.nvim_buf_set_lines(s.buf_l, i - 1, i, false, { t })
      api.nvim_buf_clear_namespace(s.buf_l, ns, i - 1, i)
      put_hls(s, i, h)
    end
  end
  vim.bo[s.buf_l].modifiable = false
  s.dirty = {}
  if #s.rows == 0 then
    return render(s)   -- '(차이가 없습니다)' / '(훑는 중…)'
  end
  if #drop > 0 then
    mark_side(s)
  end
  mark_open(s)
  if s.prog_dirty then
    s.prog_dirty = false
    set_wo(s.win_l, 'statusline', status_text(s))
    tr.head_render(s, L)   -- 지금 쪽(A/B)이 바뀌었을 수 있다 (경로 칸의 연두)
  end
end

schedule_render = function(s)
  if s.render_pending then
    return
  end
  s.render_pending = true
  -- 목록이 새로 오면 전부, 상태만 바뀌면 바뀐 줄만 - 60ms 씩 모아서
  vim.defer_fn(function()
    -- 트리에서 비주얼로 고르는 중에는 줄을 다시 쓰지 않는다 - 목록이 오며 줄이 밀리면
    -- 비주얼 시작 줄은 그대로라 고르지 않은 줄까지 복사되었다 (보기가 거르고 있으면 바뀐 줄만
    -- 그려도 보기에서 빠진 줄이 지워지며 밀린다)
    if (s.need_full or filtering(s)) and api.nvim_get_current_win() == s.win_l
        and api.nvim_get_mode().mode:match('^[vV\22]') then
      s.render_pending = false
      vim.defer_fn(function()
        schedule_render(s)
      end, 200)
      return
    end
    if s.need_full then
      s.need_full = false
      render(s)
    else
      render_dirty(s)
    end
  end, 60)
end

-- ---------------------------------------------------------------------------
-- 비교 열기 (비교 탭, 또는 위의 두 편집 창 - pair_tab = 0)
-- ---------------------------------------------------------------------------

-- 창 옵션을 전역 값으로 되돌린다 (곁창·트리 창에서 갈라 만든 창은 그 옵션을 물려받는다). 곁 창(경로 줄·
-- 개요 막대·줄 자세히 - tr.plain_extra)이 다는 것도 모두: 마지막 탭에서 트리를 닫으면 남는 창이 경로 줄
-- 창일 수 있다 - winfixbuf 가 남아 그 창에서 :edit 이 E1513 으로 거절되었다
local function plain_window(win)
  for _, o in ipairs({ 'winhighlight', 'winfixwidth', 'winfixheight', 'number', 'relativenumber',
    'signcolumn', 'foldcolumn', 'cursorline', 'list', 'wrap', 'spell', 'statuscolumn', 'winbar',
    'statusline', 'winfixbuf', 'scrolloff', 'sidescrolloff', 'fillchars', 'foldenable', 'foldmethod',
    'colorcolumn', 'cursorcolumn', 'cursorlineopt' }) do
    pcall(api.nvim_win_call, win, function()
      vim.cmd('setlocal ' .. o .. '<')
    end)
  end
end

-- :diffoff 는 foldmethod 가 manual 로 돌아오면 diff 가 만든 접기를 manual 접기로 남겨 두고 'foldenable' 을
-- 끈다 - 그 접기를 지우고 'foldenable' 은 이 창의 전역 값으로 (새로 연 창과 같게). 지금 창에서, diff 였던
-- 창의 :diffoff 바로 뒤에 부른다. 버퍼가 창에서 내려가거나 창이 닫히면 nvim 은 그 창의 옵션과 접기를
-- 버퍼에 적어 두었다가(wininfo) 그 버퍼를 다음에 여는 창에 입힌다: 비교에서 내려간 버퍼(다른 짝으로
-- 바꿨을 때의 사용자 버퍼, q 뒤에 남긴 고친 버퍼)를 다시 열면 nofoldenable 에 닫힌 diff 접기가 남아 있었다
local function undiff_folds()
  if vim.wo.foldmethod == 'manual' then
    pcall(vim.cmd, 'normal! zE')
    pcall(vim.cmd, 'let &l:foldenable = &g:foldenable')
  end
end

-- 비교 창에 띄우는 빈 버퍼 / 안내 버퍼. 반드시 이름을 붙인다: 이름 없는 빈 버퍼가
-- 떠 있는 창에서 :edit 하면 vim 은 그 버퍼를 파일 버퍼로 '다시 쓴다' - 그 뒤 안내를
-- 써 넣으면 그 글이 진짜 파일 버퍼에 들어갔다 (실측: B 창의 hunks.c 버퍼에
-- '(B 에 없음)' 이 들어갔다. 저장했으면 파일이 덮였다).
--
-- 이름은 처음 한 번만 붙이고 바꾸지 않는다. 무엇을 보이는지는 창 머리(winbar)와 버퍼 글에
-- 쓴다 - 처음에는 볼 때마다 이름을 바꾸었더니, nvim 이 바꾸기 전 이름으로 버퍼를 하나씩
-- 새로 만들어 두어(rename_buffer) 끝낸 뒤에도 'DirDiff A (A 에 없음) …' 버퍼가 쌓였다.
-- 짝을 보이는 곳(view)마다 하나씩 (비교 탭마다 따로 - 한 버퍼를 두 탭이 같이 쓰면 한 탭의 알림이 다른 탭에도 떴다)
local function scratch(v, side, text)
  local b = v['empty_' .. side]
  if not (b and api.nvim_buf_is_valid(b)) then
    b = api.nvim_create_buf(false, true)
    vim.bo[b].bufhidden = 'hide'
    vim.bo[b].swapfile = false
    pcall(api.nvim_buf_set_name, b, ('DirDiff %s #%d'):format(side:upper(), b))
    v['empty_' .. side] = b
  end
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, text)
  vim.bo[b].modifiable = false
  vim.bo[b].modified = false
  return b
end

local function is_binary(path)
  local f = io.open(path, 'rb')
  if not f then
    return false
  end
  local chunk = f:read(8000) or ''
  f:close()
  return chunk:find('\0', 1, true) ~= nil
end

-- 한쪽에만 있는 파일: 있는 쪽에 파일을, 없는 쪽에는 빈 버퍼를 diff 로 (Beyond Compare
-- 처럼 - 있는 쪽 줄이 모두 '더해진 줄'로 보인다). 무엇인지는 창 머리(winbar)에 쓴다.
local function show_file(v, win, path, side)
  local s = v.s
  if not path then
    api.nvim_win_set_buf(win, scratch(v, side, {}))
    return
  end
  -- 이 창에 이미 그 파일이 떠 있고 고친 채면 다시 읽지 않는다. :edit 이 같은 버퍼를
  -- 다시 읽으려다 'E37: No write since last change' 를 냈다 - <C-r>/<C-l> 로 복사해
  -- 놓고 트리에서 같은 줄을 o / Enter 로 다시 열 때 (서버에서 실제로 났다, 재현).
  -- 고친 것을 그대로 두고 비교만 다시 맞춘다 (고치지 않았으면 디스크에서 다시 읽는다)
  local cur = api.nvim_win_get_buf(win)
  if vim.bo[cur].modified then
    local rc, rp = uv.fs_realpath(api.nvim_buf_get_name(cur)), uv.fs_realpath(path)
    if rc and rc == rp then
      return
    end
  end
  -- 누구 버퍼인지는 열기 바로 앞에 본다 (비교를 시작할 때 한 번 찍어 둔 목록으로 보았더니,
  -- 그 뒤 사용자가 연 버퍼를 비교가 연 것으로 알고 지웠다). 이름으로 찾지 않고 연 뒤의 버퍼가
  -- 열기 전에도 있던 것인지로 본다: nvim 은 같은 파일이면 철자가 달라도(macOS 의 Foo.c/foo.c,
  -- NFC/NFD - 트리는 A 쪽 철자로 연다) 있던 버퍼를 쓰는데, 이름으로 찾았더니 그런 사용자 버퍼를
  -- 비교의 것으로 알고 치웠다 (bufnr() 는 이름을 무늬로 보아 쓰지 않는다)
  -- buflisted() 로 본다. :bd 로 닫은(내려 둔) 버퍼의 옵션을 vim.bo 로 읽으면 nvim 이
  -- 끝날 때 그 파일의 소문자 마크와 마지막 자리('")를 shada 에 적지 않는다 (실측) -
  -- 비교 쌍을 열 때마다 모든 버퍼를 돌므로 그 파일들의 마크가 사라졌다
  local before = {}
  for _, x in ipairs(api.nvim_list_bufs()) do
    before[x] = { listed = vim.fn.buflisted(x) == 1, loaded = api.nvim_buf_is_loaded(x), ours = vim.b[x].vimide_dirdiff }
  end
  -- noautocmd: 비교하려고 연 파일에서 vim-ide 의 BufRead 훅이 돌지 않게 - 색인이 없는
  -- 트리면 autoindex 가 그 트리 전체의 GTAGS 를 만들기 시작하고(트리 안에 .tags/ 를
  -- 쓴다), gutentags 도 붙는다. 비교는 보기일 뿐이다. 구문 색은 filetype 을 따로 준다.
  -- 이름은 Ex 줄로 만들지 않고 인자로 넘긴다: 이름에 줄바꿈이 있으면 fnameescape 로도 줄이
  -- 갈라져, 없는 'nl\' 을 열고 나머지 'name.c' 를 명령으로 돌렸다 (E492). magic.file=false 라
  -- % # 이나 무늬도 풀지 않는다
  local wi = vim.o.wildignore
  vim.o.wildignore = ''
  local ok, err = pcall(api.nvim_win_call, win, function()
    vim.cmd.edit({ args = { path }, magic = { file = false },
      mods = { silent = true, keepalt = true, noautocmd = true, hide = true } })
  end)
  vim.o.wildignore = wi
  if not ok then
    -- nvim_win_call 이 붙여 오는 stack traceback 은 뺀다 (여러 줄이라 Press ENTER 가 떴다)
    say((tostring(err):gsub('\nstack traceback:.*$', ''):gsub('^.-(E%d+:)', '%1')), vim.log.levels.WARN)
    return
  end
  local b = api.nvim_win_get_buf(win)
  local pre = before[b]
  if not pre or pre.ours or (not pre.listed and not pre.loaded) then
    -- 없던 것, 다른 비교가 연 것(함께 가진다), 지워져 있던 것: 이 비교의 것
    s.opened[b] = true
    vim.b[b].vimide_dirdiff = true
  elseif not pre.loaded then
    -- 목록에만 있고 읽지 않은 사용자 버퍼(세션의 badd): 끝나면 도로 내려 둔다 - 여기서
    -- noautocmd 로 읽었으니 그대로 두면 그 버퍼의 BufRead 훅이 끝내 돌지 않는다
    s.unload[b] = true
  end
  if vim.bo[b].filetype == '' then
    local okf, ft = pcall(vim.filetype.match, { buf = b, filename = path })
    if okf and ft then
      pcall(function()
        vim.bo[b].filetype = ft
      end)
    end
  end
end

-- 앞에서 열었던 파일 버퍼를 치운다 (이 비교에서 연 것, 고치지 않았고 어디에도 안 보이는 것)
local function unused(b)
  -- getbufvar: :bd 로 닫은 버퍼를 vim.bo 로 읽으면 그 파일의 마크가 shada 에서 빠진다 (위 show_file)
  return api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 0
    and vim.fn.getbufvar(b, '&modified') ~= 1
end

local function sweep(s)
  for b in pairs(s.opened) do
    if unused(b) then
      pcall(api.nvim_buf_delete, b, { force = false })
      s.opened[b] = nil
    elseif not api.nvim_buf_is_valid(b) then
      s.opened[b] = nil
    end
  end
  for b in pairs(s.unload) do
    if unused(b) then
      pcall(api.nvim_buf_delete, b, { unload = true })
      s.unload[b] = nil
    elseif not api.nvim_buf_is_valid(b) then
      s.unload[b] = nil
    end
  end
end

-- 링크는 가리키는 것을 본다: 디렉터리를 가리키면 디렉터리처럼(열면 nvim-tree 가 창을
-- 가져갔다), 끊겼으면 안내, 파일이면 크기·바이너리 검사도 그 파일로
local function real_kind(k, p)
  if k ~= 'l' or not p then
    return k
  end
  if vim.fn.isdirectory(p) == 1 then
    return 'ld'
  end
  if vim.fn.filereadable(p) == 1 then
    return 'lf'
  end
  return 'lx'
end

local NOTE = { d = '디렉터리', o = '특수 파일', ld = '디렉터리를 가리키는 링크', lx = '끊긴 링크' }

local function pair_tab_on()
  return (tonumber(vim.g.vimide_dirdiff_pair_tab) or 1) ~= 0
end

-- 비교 창의 보기 (Beyond Compare 의 글 비교 보기). 접기는 diff 의 것(foldmethod=diff)을 그대로 쓴다:
--   all      모두 보이기 - 접기를 모두 연다 (foldlevel 99). 그 뒤 zM 이면 'diffopt' 의 문맥대로 접힌다
--   diff     차이 보이기 - 바뀐 줄만 (context:0. vim 은 0 을 1 로 친다 - 접기 사이에는 줄 하나가 있어야 한다)
--   context  문맥 보이기 - 바뀐 줄과 위아래 g:vimide_dirdiff_context 줄
-- 'diffopt' 의 context 는 전역 하나라 비교 탭에 들어올 때 그 탭의 보기로 바꾸고, 다른 탭에 들어가면
-- 되돌린다 (dip_sync - 그러지 않으면 사용자의 vimdiff 탭도 같이 접혔다). 두 창의 접기가 diff 의 한
-- 덩어리 목록에서 나오므로 함께 내려간다 (scrollbind, zR·zM·zo·zc 도 두 창에 같이 - vim 이 맞춘다).
-- 동일 보이기(같은 줄만)는 넣지 않았다: 바뀐 덩어리를 접으면 접힌 자리는 창마다 한 줄인데, 끼인
-- 줄(filler)은 접을 수 없고(덩어리 다음 줄 위에 붙는다) 한쪽에만 있는 덩어리는 다른 쪽에 접을 줄이
-- 없다 - 덩어리마다 두 창의 줄 수가 어긋나 내려갈수록 벌어졌다 (manual 접기로 실측). diff 의
-- scrollbind 는 줄 번호로 맞추지 화면 줄로 맞추지 않는다
local FMODES = {
  { id = 'all', label = '모두 보이기' },
  { id = 'diff', label = '차이 보이기' },
  { id = 'context', label = '문맥 보이기' },
}
local FMODE = {}
for i, md in ipairs(FMODES) do
  md.i = i
  FMODE[md.id] = md
end

local function ctx_lines()
  return math.max(0, math.floor(tonumber(vim.g.vimide_dirdiff_context) or 3))
end

local function fmode_label(id)
  if id == 'context' then
    return ('문맥 보이기 (%d줄)'):format(ctx_lines())
  end
  return FMODE[id].label
end

-- 처음 보기: g:vimide_dirdiff_file_view (FMODES 의 id, 기본 all = 모두 보이기). 짝을 새로 열 때마다
-- 이 보기로 시작한다 (요청: 기본은 모두 보이기) - \d 로 고른 보기는 그 짝에만 남는다
local function start_fmode()
  local v = vim.g.vimide_dirdiff_file_view
  if type(v) == 'string' and FMODE[v] then
    return v
  end
  if v ~= nil and v ~= '' then
    say(('g:vimide_dirdiff_file_view 를 모릅니다: %s (all diff context)'):format(tostring(v)), vim.log.levels.WARN)
  end
  return 'all'
end

-- 'diffopt' 의 context: 지금 탭이 짝을 보이는 탭이고 그 보기가 차이·문맥이면 그 값, 아니면 사용자 것.
-- dip.saved: 바꾸기 전 사용자 값, dip.ours: 우리가 넣은 값 - 그 사이 사용자가 :set diffopt 로 바꿨으면
-- 그것을 둔다 (그 위에 다시 context 만 얹는다)
local dip = {}
local function with_context(opt, n)
  local parts = {}
  for p in opt:gmatch('[^,]+') do
    if not p:match('^context:') then
      parts[#parts + 1] = p
    end
  end
  parts[#parts + 1] = 'context:' .. n
  return table.concat(parts, ',')
end

local function dip_sync()
  local v = view_of_tab(api.nvim_get_current_tabpage())
  local n = nil
  if v and v.rel and not v.bin then
    if v.fmode == 'diff' then
      n = 0
    elseif v.fmode == 'context' then
      n = ctx_lines()
    end
  end
  if dip.ours and vim.o.diffopt ~= dip.ours then
    -- 그 사이 사용자가 :set diffopt 로 바꿨다: 그 값을 두되 우리가 넣은 context 는 걷고, 원래 값에
    -- context 가 있었으면 그것을 돌려놓는다 (안 그러면 context:0 이 남아 사용자의 vimdiff 가 1줄만 보였다)
    local own = dip.saved and dip.saved:match('context:%d+')
    local now = {}
    for p in vim.o.diffopt:gmatch('[^,]+') do
      if not p:match('^context:') then
        now[#now + 1] = p
      end
    end
    if own then
      now[#now + 1] = own
    end
    dip.saved, dip.ours = table.concat(now, ','), nil
  end
  if n then
    dip.saved = dip.saved or vim.o.diffopt
    local want = with_context(dip.saved, n)
    if vim.o.diffopt ~= want then
      vim.o.diffopt = want
    end
    dip.ours = want
  elseif dip.saved then
    if vim.o.diffopt ~= dip.saved then
      vim.o.diffopt = dip.saved
    end
    dip.saved, dip.ours = nil, nil
  end
  -- 접기는 계산한 그때의 context 로 남는다: 다른 탭에 있을 때 다시 채운 짝(트리 복사 뒤)은 그때의 'diffopt'
  -- 로 접혔고, 같은 보기의 다른 비교 탭에서 넘어오면 'diffopt' 가 그대로라 nvim 이 다시 접지 않았다.
  -- 이 짝을 마지막으로 접은 context(ctx_done)와 다르면 다시 접게 한다 (foldmethod 를 다시 넣으면 다시 접는다)
  local key = n or -1
  if v and v.rel and not v.bin and v.ctx_done ~= key then
    v.ctx_done = key
    for _, w in ipairs({ v.win_a, v.win_b }) do
      if api.nvim_win_is_valid(w) and vim.wo[w].diff then
        set_wo(w, 'foldmethod', 'diff')
      end
    end
  end
end

-- 비교 창의 머리(winbar) - Beyond Compare 의 경로 칸과 그 아래 정보 줄을 한 줄에: ' A: 경로  수정 일시  크기
-- 바이트  인코딩  줄 끝' / ' B: …', B 쪽 오른쪽 끝에 지금 보기와 키. 좁으면 정보를 빼고 경로의 가운데
-- 디렉터리를 … 로 줄인다 (파일 이름은 남는다 - tr.mid_path). 없는 쪽은 '(없음) 경로' (Beyond Compare 의 빈
-- 경로 칸). bc 색이면 A:·B: 는 굵게, 정보는 진한 회색(VimIdeDirDiffBarInfo), 머리는 지금
-- 창이 연두 (winhighlight 의 WinBar - diff_whl), neogit 색이면 A:·B: 는 트리의 A 에만·B 에만 색, 보기는 절
-- 머리 색. 창에만(set_wo) - 그 창의 전역 값까지 바꾸면 setlocal winbar< 가 머리를 되돌려 놓는다 (strip_inherited)
local function set_heads(v)
  local function esc(t)
    return (t:gsub('%%', '%%%%'))
  end
  local sw = vim.fn.strdisplaywidth
  for _, side in ipairs({ 'a', 'b' }) do
    local w = v['win_' .. side]
    local h = v.head and v.head[side]
    if h and api.nvim_win_is_valid(w) then
      local tg = pal() == 'bc' and 'VimIdeDirDiffHeader' or (side == 'a' and 'VimIdeDirDiffOnlyA' or 'VimIdeDirDiffOnlyB')
      local gone = (v.gone and v.gone[side]) and ' (없음)' or ''
      local left = ' ' .. hl_part(tg, side:upper() .. ':') .. gone .. ' %<'
      local used = 1 + 2 + sw(gone) + 1
      local W = api.nvim_win_get_width(w)
      -- 경로는 파일 이름과 맨 앞(~/…/)만큼은 남게 - 정보·보기·키는 그것이 안 들어가면 뺀다
      local need = math.min(sw(h), sw(vim.fn.fnamemodify(h, ':t')) + 4)
      local right, rw = '', 0
      if side == 'b' then
        -- B 쪽 끝의 보기와 키: 좁으면 키 안내, 그다음 보기 이름을 뺀다 (파일 이름이 먼저다)
        local keys = v.inline and '' or 'q 닫기'
        local label = ''
        if not v.bin then
          keys = '\\d 보기' .. (keys ~= '' and (' · ' .. keys) or '')
          label = '[' .. fmode_label(v.fmode) .. ']'
        end
        local function width_of(lb, ks)
          return (lb ~= '' and 1 + sw(lb) or 0) + (ks ~= '' and 2 + sw(ks) or 1)
        end
        if W - used - need - width_of(label, keys) < 0 then
          keys = ''
        end
        if W - used - need - width_of(label, keys) < 0 then
          label = ''
        end
        if label ~= '' then
          right = ' ' .. hl_part('VimIdeDirDiffHeader', esc(label))
        end
        right = right .. (keys ~= '' and (' ' .. hl_part('VimIdeDirDiffPending', esc(keys)) .. ' ') or ' ')
        rw = width_of(label, keys)
      end
      -- 정보는 좁으면 뒤에서부터 뺀다 (인코딩·줄 끝, 크기, 일시) - 경로가 파일 이름과 맨 앞만큼은 남게
      -- (20 칸만 남겼더니 긴 파일 이름이 잘린 채 일시가 보였다). 남은 칸에 경로를 가운데부터 줄여 넣는다
      -- (tr.mid_path - 파일 이름은 끝까지 남는다). %< 는 그래도 넘칠 때(창이 더 좁다)의 마지막 자르기
      local parts = cmp.info(v, side)
      local room = W - used - need - rw
      local info = table.concat(parts, '  ')
      while #parts > 0 and 2 + sw(info) > room do
        parts[#parts] = nil
        info = table.concat(parts, '  ')
      end
      local pw = W - used - rw - (info ~= '' and 2 + sw(info) or 0)
      local text = left .. esc(tr.mid_path(h, math.max(1, pw)))
      if info ~= '' then
        text = text .. '  ' .. hl_part('VimIdeDirDiffBarInfo', esc(info))
      end
      if side == 'b' then
        text = text .. '%=' .. right
      end
      set_wo(w, 'winbar', text)
    end
  end
end

-- 보기를 두 창에: 'diffopt' 의 context(지금 탭이면)를 맞추고, 접기를 켜고 foldlevel 로 열거나 닫는다
-- (모두 99, 나머지 0). 알림(바이너리·큰 파일)은 diff 가 아니라 건드리지 않는다
local function apply_fmode(v)
  if v.tab == api.nvim_get_current_tabpage() then
    dip_sync()
  end
  for _, w in ipairs({ v.win_a, v.win_b }) do
    if api.nvim_win_is_valid(w) and vim.wo[w].diff then
      set_wo(w, 'foldenable', true)
      set_wo(w, 'foldlevel', v.fmode == 'all' and 99 or 0)
    end
  end
  set_heads(v)
end

-- 짝의 창에서 비교의 흔적(diff, 접기, 머리, winhighlight)을 걷는다 - 창을 닫거나 버퍼가 내려가기 앞에:
-- nvim 은 창에서 내려가는 버퍼에 그 창의 옵션을 적어 두었다가(wininfo) 그 버퍼를 다음에 여는 창에 입힌다
local function unview_win(w)
  if not api.nvim_win_is_valid(w) then
    return
  end
  pcall(api.nvim_win_call, w, function()
    local was = vim.wo.diff
    vim.cmd('diffoff')
    if was then
      undiff_folds()
      -- 보기의 foldlevel(모두 보이기 99)도: :diffoff 는 되돌리지 않아 고친 채 남긴 버퍼를 다시 열면 따라왔다
      pcall(vim.cmd, 'setlocal foldlevel<')
    end
  end)
  set_wo(w, 'winbar', '')
  diff_whl(w, nil)
  cmp.ungone(w)
  vim.w[w].overview_off = nil
  -- 화살표·연보라 빈 줄은 버퍼에 단 것이라 (창에만 보이게 한 것은 nvim__ns_set 이 있을 때뿐) 걷는다
  local b = api.nvim_win_get_buf(w)
  api.nvim_buf_clear_namespace(b, NS.arrow, 0, -1)
  api.nvim_buf_clear_namespace(b, NS.blank, 0, -1)
end

-- 짝을 view 의 두 창에 채운다. jump: 커서를 첫 차이로
local function fill(v, r, jump)
  local s = v.s
  local e = r.e
  local rel = shown(r.rel)
  local pa = e.ka and (s.a .. '/' .. r.rel) or nil
  local pb = e.kb and (s.b .. '/' .. r.rel) or nil
  local ka, kb = real_kind(e.ka, pa), real_kind(e.kb, pb)
  -- 디렉터리를 :edit 하면 nvim-tree 가 창을 가져간다 - 파일(과 파일 링크)만 연다
  local function note(k, side, p)
    if not NOTE[k] then
      return nil
    end
    local to = (k == 'ld' or k == 'lx') and uv.fs_readlink(p)
    return ('  (%s 쪽은 %s: %s%s)'):format(side, NOTE[k], rel, to and (' -> ' .. shown(to)) or '')
  end
  local na, nb = note(ka, 'A', pa), note(kb, 'B', pb)
  -- 다른 탭의 짝을 다시 채울 때(다른 탭에서 한 복사·저장 뒤) 그 탭의 지금 창을 지킨다: 아래
  -- BufEnter 훅(BufExplorer 등)이 nvim_win_call 안에서 그 탭의 지금 창을 B 창으로 옮겨 놓아, gT·q 로
  -- 돌아가면 커서가 트리가 아니라 B 창에 있었다 (f 는 f{char}, <C-r> 은 diffget 이 되었다)
  local tab_win = v.tab ~= api.nvim_get_current_tabpage() and api.nvim_tabpage_is_valid(v.tab)
    and api.nvim_tabpage_get_win(v.tab) or nil
  -- 다른 버퍼로 바꾸는 동안은 아래 BufWinEnter(짝이 아닌 버퍼면 색·머리를 걷는다)가 보지 않게
  v.filling = true
  -- 창 머리(winbar)·winhighlight 도 걷고 나서 버퍼를 바꾼다: nvim 은 창에서 내려가는 버퍼에 그 창의 옵션을
  -- 적어 두었다가(wininfo) 그 버퍼를 새 창에 띄울 때 입힌다 - 그대로 두었더니 앞에 본 파일을 다른 탭에서
  -- 열면(Tab/Tab 의 vimdiff, :tabnew) 이 비교의 ' A: …' 머리가 따라왔다. 새 머리는 아래 set_heads 가 단다
  -- diff 접기도 같은 까닭으로 걷는다 (undiff_folds)
  for _, w in ipairs({ v.win_a, v.win_b }) do
    unview_win(w)
  end
  local max = (tonumber(vim.g.vimide_dirdiff_max_mb) or 20) * 1024 * 1024
  local function size_of(k, p, sz)
    if k == 'lf' then
      return math.max(0, vim.fn.getfsize(p))
    end
    return k == 'f' and sz or 0
  end
  local sa, sb = size_of(ka, pa, e.sa), size_of(kb, pb, e.sb)
  local big = (sa or 0) > max or (sb or 0) > max
  local function binary(k, p)
    return p and (k == 'f' or k == 'lf') and is_binary(p)
  end
  local bin = big or binary(ka, pa) or binary(kb, pb)
  if bin then
    local info = {
      '',
      (big and ('  큰 파일(%d MB 넘음 - g:vimide_dirdiff_max_mb): '):format(max / 1048576) or '  바이너리 파일: ') .. rel,
      '',
      '  A: ' .. (e.ka and (commas(sa) .. ' 바이트') or '없음'),
      '  B: ' .. (e.kb and (commas(sb) .. ' 바이트') or '없음'),
      '',
      '  판정: ' .. ({ same = '같다', diff = '다르다', onlyA = 'A 에만', onlyB = 'B 에만', pend = '확인 중' })[e.st],
    }
    api.nvim_win_set_buf(v.win_a, scratch(v, 'a', info))
    api.nvim_win_set_buf(v.win_b, scratch(v, 'b', info))
  else
    if na then
      api.nvim_win_set_buf(v.win_a, scratch(v, 'a', { '', na }))
    else
      show_file(v, v.win_a, pa, 'a')
    end
    if nb then
      api.nvim_win_set_buf(v.win_b, scratch(v, 'b', { '', nb }))
    else
      show_file(v, v.win_b, pb, 'b')
    end
    for _, w in ipairs({ v.win_a, v.win_b }) do
      pcall(api.nvim_win_call, w, function()
        vim.cmd('diffthis')
        -- 파일별 BufEnter 설정(.c 의 ts=8 등)을 양쪽 모두에 - noautocmd 로 열어서 커서가
        -- 들어가는 쪽만 받았고, 탭 들여쓰기가 A 와 B 에서 다르게 보였다. BufRead 는 여전히 없다
        if vim.bo.buftype == '' then
          vim.cmd('silent! doautocmd <nomodeline> BufEnter')
        end
      end)
    end
  end
  -- 없는 쪽은 경로를 보이되 (없음) 을 붙인다 - (없음) 은 자르지 않는 자리에 (set_heads)
  local function head(k, root)
    if k == nil then
      return rel
    end
    return shown(vim.fn.fnamemodify(root .. '/' .. r.rel, ':~'))
  end
  v.head = { a = head(e.ka, s.a), b = head(e.kb, s.b) }
  v.gone = { a = e.ka == nil, b = e.kb == nil }
  if v.rel ~= r.rel then
    v.fmode = s.fmode   -- 다른 짝을 실었다 (pair_tab = 0 의 편집 창) - 처음 보기로
  end
  v.rel = r.rel
  v.ctx_done = nil   -- 지금 'diffopt' 로 새로 접혔다 - 이 탭에 들어올 때 그 탭의 context 로 (dip_sync)
  v.bin = bin   -- 두 창이 알림이다 (편집 창의 <C-r>/<C-l> 이 알린다, 보기는 접을 것이 없다)
  v.buf_a, v.buf_b = api.nvim_win_get_buf(v.win_a), api.nvim_win_get_buf(v.win_b)
  -- 창 머리의 수정 일시·크기 (디스크의 것 - :w 하면 다시, BufWritePost)
  v.path = { a = pa, b = pb }
  v.info = { a = pa and uv.fs_stat(pa) or nil, b = pb and uv.fs_stat(pb) or nil }
  -- 비교 색 (bc: 두 쪽 분홍·빨강, neogit: A 쪽 빨강, B 쪽 초록). 알림 창에는 달지 않는다
  diff_whl(v.win_a, not bin and 'a' or nil)
  diff_whl(v.win_b, not bin and 'b' or nil)
  cmp.gone_side(v)
  -- 알림(바이너리·큰 파일)에는 곁 창이 쓸모없다 (빈 개요 막대, 'A – B –' 뿐인 줄 자세히) - 닫고 두 창을 반반으로
  if bin and (v.ov or v.ld) then
    cmp.detach(v)
    if api.nvim_win_is_valid(v.win_a) and api.nvim_win_is_valid(v.win_b) then
      local tw = api.nvim_win_get_width(v.win_a) + api.nvim_win_get_width(v.win_b)
      pcall(api.nvim_win_set_width, v.win_a, math.floor(tw / 2))
    end
  end
  cmp.own_overview(v)
  -- 탭 이름: airline 의 탭 줄은 탭에 목록 버퍼가 없으면 첫 창의 버퍼 이름을 쓴다 - 두 창이 다 알림이면 그
  -- 첫 창이 개요 막대라 'DirDiff 개요 #20' 이 떴다. 그때만 짝의 파일 이름을 t:title 로 (보통 짝은 airline
  -- 이 파일 이름을 그대로 쓴다)
  if not v.inline and api.nvim_tabpage_is_valid(v.tab) then
    if vim.fn.buflisted(v.buf_a) == 0 and vim.fn.buflisted(v.buf_b) == 0 then
      vim.t[v.tab].title = vim.fn.fnamemodify(rel, ':t')
    else
      pcall(api.nvim_tabpage_del_var, v.tab, 'title')
    end
  end
  apply_fmode(v)
  -- 개요 막대·화살표·줄 자세히·연보라 빈 줄을 새 짝으로
  cmp.kick(v, true)
  v.filling = false
  sweep(s)
  mark_open(s)
  if tab_win and api.nvim_win_is_valid(tab_win) and api.nvim_tabpage_is_valid(v.tab)
      and api.nvim_tabpage_get_win(v.tab) ~= tab_win then
    pcall(api.nvim_tabpage_set_win, v.tab, tab_win)
  end
  if jump then
    local w = pa and v.win_a or v.win_b
    api.nvim_set_current_win(w)
    pcall(vim.cmd, 'normal! gg')
    if not bin then
      if vim.fn.diff_filler(1) > 0 then
        -- 첫 차이가 1줄 위에 끼인 줄(다른 쪽에만 있는 첫머리)이면 그대로 두고 보이게만.
        -- ]c 는 그것을 건너 두 번째 차이로 갔다
        pcall(vim.fn.winrestview, { topline = 1, topfill = vim.fn.diff_filler(1) })
      elseif vim.fn.diff_hlID(1, 1) == 0 then
        pcall(vim.cmd, 'normal! ]c')
      end
    end
  end
end

-- 이 짝(rel)의 비교 탭
local function view_of_rel(s, rel)
  for _, v in pairs(s.views) do
    if v.rel == rel then
      return v
    end
  end
end

-- :tabnew 가 만든 빈 [No Name] 은 곧바로 치운다 (비교할 때마다 하나씩 남았다)
local function drop_noname(nb)
  if api.nvim_buf_is_valid(nb) and api.nvim_buf_get_name(nb) == '' and not vim.bo[nb].modified
      and api.nvim_buf_line_count(nb) == 1 and api.nvim_buf_get_lines(nb, 0, 1, false)[1] == ''
      and #vim.fn.win_findbuf(nb) == 0 then
    pcall(api.nvim_buf_delete, nb, {})
  end
end

-- 새 비교 탭: 이 세션의 탭들(트리 탭과 그 비교 탭) 중 맨 뒤의 것 바로 다음에 (열수록 오른쪽으로 -
-- 그냥 :tabnew 는 트리 탭 바로 뒤라 연 차례가 거꾸로 섰다). 트리 창에서 열면 새 창이 트리의 창 옵션을
-- 물려받으므로 plain_window 로 되돌린다. 트리 창의 상태줄·머리는 창에만(set_wo) 달아 두어 전역 값으로는
-- 따라오지 않는다
local function new_view(s)
  local last = api.nvim_tabpage_get_number(s.tab)
  for t in pairs(s.views) do
    if api.nvim_tabpage_is_valid(t) then
      last = math.max(last, api.nvim_tabpage_get_number(t))
    end
  end
  vim.cmd(last .. 'tabnew')
  local v = { s = s, tab = api.nvim_get_current_tabpage(), fmode = s.fmode }
  -- vim-ide 의 곁창 지킴이(vimidewin.lua)가 이 탭을 남의 것으로 보게 (빈 버퍼 창을 곁창으로 알고 파일을
  -- 다른 창으로 빼냈다)
  vim.t[v.tab].vimide_dirdiff_pair = true
  v.win_a = api.nvim_get_current_win()
  local nb = api.nvim_get_current_buf()
  plain_window(v.win_a)
  api.nvim_win_set_buf(v.win_a, scratch(v, 'a', {}))
  drop_noname(nb)
  v.win_b = api.nvim_open_win(scratch(v, 'b', {}), false, { split = 'right', win = v.win_a })
  plain_window(v.win_b)
  s.views[v.tab] = v
  -- 맨 왼쪽 개요 막대, 맨 아래 줄 자세히 (이 탭에만 - 짝을 채우면 cmp.kick 이 그린다)
  cmp.attach(v)
  return v
end

-- 비교 탭의 창 하나를 닫아 버렸으면 남은 창 옆에 다시 만든다. 둘 다 없으면(탭에 다른 창만 남았다) 그
-- 탭은 놓아주고 nil - 새 탭을 연다
-- 두 번째 값: 창을 다시 만들었다 (그 창은 빈 자리라 다시 채워야 한다)
local function repair_view(v)
  local s = v.s
  local okA, okB = api.nvim_win_is_valid(v.win_a), api.nvim_win_is_valid(v.win_b)
  if okA and okB then
    return v, false
  end
  if not okA and not okB then
    v.closed = true
    s.views[v.tab] = nil
    -- 놓는 다른 길(release_view, finish)처럼: 다시 그리기 시계를 멈추고 버퍼의 표시를 걷는다
    cmp.clear(v)
    if api.nvim_tabpage_is_valid(v.tab) then
      cmp.detach(v)
      pcall(api.nvim_tabpage_del_var, v.tab, 'vimide_dirdiff_pair')
      pcall(api.nvim_tabpage_del_var, v.tab, 'title')
    end
    return nil
  end
  if okA then
    v.win_b = api.nvim_open_win(scratch(v, 'b', {}), false, { split = 'right', win = v.win_a })
    plain_window(v.win_b)
  else
    v.win_a = api.nvim_open_win(scratch(v, 'a', {}), false, { split = 'left', win = v.win_b })
    plain_window(v.win_a)
  end
  return v, true
end

-- 짝을 연다. jump: true = 그 짝으로 가서 커서를 첫 차이로 (<CR>), false = 열되 트리에 그대로 (o),
-- 'refill' = 그 짝을 보이고 있는 창만 다시 채운다 (복사·저장 뒤 - 새 탭을 열거나 옮기지 않는다)
--
-- pair_tab: 짝마다 비교 탭 하나. 이미 열린 짝이면 <CR> 은 그 탭으로 (다시 읽지 않는다 - 고친 것·커서
-- 그대로), o 는 그 탭을 다시 채우고 트리에 그대로. 새 짝의 o 는 뒤에서 탭을 열고 트리로 돌아온다
-- (여러 짝을 열어 두고 gt 로 돌아본다)
local function open_pair(s, r, jump)
  local v = s.main
  if v then
    -- pair_tab = 0: 위의 편집 창 둘. 닫아 버렸으면 트리 위에 다시 만든다. 트리 창에서 가르면 트리 옵션
    -- (번호 끔 등)을 물려받으므로 plain_window 로 되돌리고, 트리 높이도 되돌린다
    if jump == 'refill' and v.rel ~= r.rel then
      return
    end
    local made = {}
    if not api.nvim_win_is_valid(v.win_a) and not api.nvim_win_is_valid(v.win_b) then
      -- 트리 위의 경로 줄 창보다 위에 (그 사이에 끼면 경로 줄이 트리와 떨어진다). 높이를 주고 연다: 한 줄짜리
      -- 경로 줄 창(winfixheight)을 그냥 가르면 새 창이 두 줄이 되고, 그 뒤 트리 높이를 되돌려도 줄이 모자라
      -- 화면 맨 아래에 옛 상태줄이 한 줄 남았다. 트리가 list_h 로 돌아가고 남는 만큼 (상태줄 한 줄을 빼고)
      local above = (s.hwin and api.nvim_win_is_valid(s.hwin)) and s.hwin or s.win_l
      local h = math.max(2, api.nvim_win_get_height(s.win_l) - (s.list_h or 0) - 1)
      v.win_a = api.nvim_open_win(scratch(v, 'a', {}), false, { split = 'above', win = above, height = h })
      made[#made + 1] = v.win_a
    end
    if not api.nvim_win_is_valid(v.win_a) then
      v.win_a = api.nvim_open_win(scratch(v, 'a', {}), false, { split = 'left', win = v.win_b })
      made[#made + 1] = v.win_a
    elseif not api.nvim_win_is_valid(v.win_b) then
      v.win_b = api.nvim_open_win(scratch(v, 'b', {}), false, { split = 'right', win = v.win_a })
      made[#made + 1] = v.win_b
    end
    for _, w in ipairs(made) do
      plain_window(w)
    end
    if #made > 0 and s.list_h then
      pcall(api.nvim_win_set_height, s.win_l, s.list_h)
    end
    return fill(v, r, jump == true)
  end
  v = view_of_rel(s, r.rel)
  local repaired = false
  if v then
    v, repaired = repair_view(v)
  end
  if jump == 'refill' then
    if v then
      fill(v, r, false)
    end
    return
  end
  if v then
    if jump then
      api.nvim_set_current_tabpage(v.tab)
      if repaired then
        -- 닫아 버린 창을 빈 자리로 다시 세웠다 - 두 창을 다시 채우고 diff 를 다시 건다
        -- (그냥 넘어가면 남은 창은 diff 가 꺼진 채, 새 창은 빈 채였다)
        fill(v, r, true)
      end
    else
      fill(v, r, false)
      -- 한쪽이 디렉터리인 줄의 <CR> 은 펼치고 접기라 그 탭으로 가지 않는다 - 그 줄에서는 gt 로
      say(('비교 탭을 다시 읽었습니다 (탭 %d) - %s 로 그 탭으로'):format(api.nvim_tabpage_get_number(v.tab),
        is_dir(r.e) and 'gt' or '<CR>'))
    end
    return
  end
  v = new_view(s)
  -- 새 탭은 o 로 열어도 커서를 첫 차이에 두고 연다 (지금 탭이 그 탭이다) - 나중에 gt 로 가면 거기서 시작
  fill(v, r, true)
  if not jump and api.nvim_tabpage_is_valid(s.tab) then
    -- o: 트리로 돌아온다 (커서는 트리의 그 줄 그대로)
    api.nvim_set_current_tabpage(s.tab)
    if api.nvim_win_is_valid(s.win_l) then
      api.nvim_set_current_win(s.win_l)
    end
  end
end

open_pair_fn = open_pair

-- ---------------------------------------------------------------------------
-- 트리 창의 동작
-- ---------------------------------------------------------------------------

local function cur_row(s)
  if not api.nvim_win_is_valid(s.win_l) then
    return nil
  end
  return s.rows[api.nvim_win_get_cursor(s.win_l)[1]]
end

local function toggle(s, r, want)
  local open = s.expanded[r.rel]
  if want ~= nil and want == (open and true or false) then
    return
  end
  if open then
    s.expanded[r.rel] = nil
    send(s, { cmd = 'unlist', dir = r.rel })
  else
    s.expanded[r.rel] = true
    request_list(s, r.rel)
  end
  render(s)
end

local function act_enter(s, jump)
  local r = cur_row(s)
  if not r or r.loading then
    return
  end
  if is_dir(r.e) then
    if jump == nil or jump == true then
      toggle(s, r)
    end
    -- 한쪽은 디렉터리, 한쪽은 파일(링크·특수 파일): 파일 쪽을 안내 옆에 보인다. 디렉터리면
    -- 늘 여기서 끝냈더니 o 는 아무것도 하지 않았고, 다른 쪽의 파일은 트리에서 열 수 없었다
    if r.e.ka and r.e.kb and not both_dirs(r.e) then
      -- 비교 탭이 멀쩡히 있으면 <CR> 로 펼치고 접을 때마다 다시 읽지 않는다. o 는 다시 읽고(파일
      -- 줄의 o 와 같게), 창 하나를 닫아 버린 탭이면 <CR> 도 다시 세운다
      local v = not s.main and view_of_rel(s, r.rel)
      local intact = v and api.nvim_win_is_valid(v.win_a) and api.nvim_win_is_valid(v.win_b)
      if jump == false or not intact then
        open_pair(s, r, false)
      end
    end
    return
  end
  open_pair(s, r, jump)
end

-- <C-n>/<C-p>·O 가 찾을 것 (뒤쪽 next/expand 의 bits). 모두·차이 보기는 nil - 예전대로 '차이'.
-- 다른 보기는 그 보기의 차이(최신·고아 ...)를, 차이가 없는 보기(동일)는 그 보기의 것을 - 보이지
-- 않는 줄로 가면 커서가 갈 곳이 없다
step_bits = function(s)
  local bits = MODE[s.mode].bits
  if not bits or s.mode == 'diff' then
    return nil
  end
  local b = band(bits, NA + NB + DX + OA + OB)
  return b ~= 0 and b or bits
end

-- 예전 뒤쪽(dirdiffscan.py 를 빼고 .lua 만 바꿔 넣었을 때 - 항목에 표시가 없다)에서 보기의 <C-n>/<C-p>.
-- 그 뒤쪽의 next 는 bits 를 몰라 '차이' 만 돌려준다: 보기가 감춘 차이면 그 뒤부터 다시 묻게 했더니 감춘
-- 것이 200 개를 넘으면 아무 말 없이 멈췄고, 동일 보기는 '같음' 을 받지 못해 늘 '마지막' 이었고, 물으며
-- 지난 디렉터리(접어 둔 것도)가 모두 펼쳐졌다. 그래서 여기서 걷는다: 받은 목록을 트리 차례로 따라가며
-- 그 보기의 항목(뒤쪽 items_in_order 의 기준 - 양쪽에 있는 디렉터리는 들어가 보고, 나머지는 표시로)을
-- 찾는다. 목록이 없거나 옛것인(접혀 있어 'u' 를 받지 않는) 디렉터리는 청해 받고 이어 걷는다 (on_event
-- 의 'list'). 펼치는 것은 찾은 항목의 조상만, 걸으며 받은 나머지 목록은 뒤쪽에 도로 내려 둔다(unlist)
local function walk_hit(e, bits)
  if both_dirs(e) then
    return e.rerr ~= nil and band(bits, DX) ~= 0
  end
  return band(mask_of(e), bits) ~= 0
end

local function walk_into(e, bits)
  return both_dirs(e) and e.rerr == nil and (e.st ~= 'same' or band(bits, SAME) ~= 0)
end

-- 걸으며 받은 목록 중 펼치지 않은 것은 뒤쪽이 더 따라가지 않게 (접을 때의 unlist 처럼)
local function walk_drop(s, w)
  for rel in pairs(w.fresh) do
    if rel ~= '' and not s.expanded[rel] then
      send(s, { cmd = 'unlist', dir = rel })
    end
  end
end

local function walk_end(s, w, path)
  s.walk = nil
  local p = path and path:match('^(.*)/[^/]+$')
  while p do
    s.expanded[p] = true
    p = p:match('^(.*)/[^/]+$')
  end
  walk_drop(s, w)
  if not path then
    local done = s.prog and s.prog.done
    return say(w.step > 0 and (done and '이 보기에서 마지막입니다' or '아래로는 아직 이 보기에 맞는 것이 없습니다 (훑는 중)')
      or (done and '이 보기에서 처음입니다' or '위로는 아직 이 보기에 맞는 것이 없습니다 (훑는 중)'))
  end
  render(s)
  if s.row_of[path] and api.nvim_win_is_valid(s.win_l) then
    goto_row(s, s.row_of[path])
    mark_side(s)
  end
end

-- 예전 뒤쪽에서 보기의 O 도 여기서 걷는다: 그 뒤쪽의 expand 는 bits 를 몰라 '차이' 가 있는 디렉터리를
-- 모두 펼쳤다 - 동일 보기에서 보기가 감춘 차이의 디렉터리가 속이 빈 채 펼쳐지고, 보기의 것(같은 파일)이
-- 든 디렉터리는 접힌 채였다. 양쪽에 있는 디렉터리를 들어가 보며(walk_into) 보기의 항목(walk_hit)이 든
-- 디렉터리와 그 조상만 펼친다 (새 뒤쪽 cmd_expand 와 같은 것, 목록 2000 개까지). w.todo: 볼 디렉터리,
-- w.open: 보기의 항목이 든 디렉터리. 걸으며 받은 나머지 목록은 도로 내려 둔다 (walk_drop)
local function expand_walk(s)
  local w = s.walk
  while #w.todo > 0 do
    local rel = w.todo[#w.todo]
    local d = s.dirs[rel]
    if not (d and (rel == '' or s.expanded[rel] or w.fresh[rel])) then
      w.fresh[rel] = true
      w.wait = rel
      return request_list(s, rel)
    end
    w.todo[#w.todo] = nil
    w.n = w.n + 1
    for _, e in ipairs(d.entries) do
      if walk_hit(e, w.bits) then
        w.open[rel] = true
      end
      if walk_into(e, w.bits) and w.n + #w.todo < 2000 then
        w.todo[#w.todo + 1] = join(rel, e.name)
      end
    end
  end
  s.walk = nil
  for rel in pairs(w.open) do
    while rel ~= '' do
      s.expanded[rel] = true
      rel = rel:match('^(.*)/[^/]+$') or ''
    end
  end
  walk_drop(s, w)
  render(s)
end

-- w.cur: 마지막으로 본 경로, w.down: 그 디렉터리 안을 볼 차례 (앞으로는 먼저, 뒤로는 그 디렉터리보다 먼저)
local function walk(s)
  local w = s.walk
  if not w or w.wait then
    return
  end
  if w.todo then
    return expand_walk(s)   -- O 의 걷기 (on_event 의 'list' 가 이리로 이어 준다)
  end
  local function list(rel)
    local d = s.dirs[rel]
    if d and (rel == '' or s.expanded[rel] or w.fresh[rel]) then
      return d
    end
    w.fresh[rel] = true
    w.wait = rel
    request_list(s, rel)
  end
  local function find(d, name)
    for i, e in ipairs(d.entries) do
      if e.name == name then
        return i
      end
    end
  end
  while true do
    local e, rel
    if w.down then
      local d = list(w.cur)
      if not d then
        return
      end
      w.down = false
      local x = w.step > 0 and d.entries[1] or d.entries[#d.entries]
      if x then
        e, rel = x, join(w.cur, x.name)
      end
    end
    if not e then
      if w.cur == '' then
        return walk_end(s, w, nil)
      end
      local parent, name = w.cur:match('^(.*)/([^/]+)$')
      parent, name = parent or '', name or w.cur
      local d = list(parent)
      if not d then
        return
      end
      local i = find(d, name)
      if not i then
        return walk_end(s, w, nil)
      end
      local x = d.entries[i + w.step]
      if x then
        e, rel = x, join(parent, x.name)
      elseif w.step > 0 then
        w.cur = parent   -- 이 디렉터리를 다 보았다 - 부모의 다음으로
      else
        -- 뒤로: 디렉터리 안을 다 본 뒤에 그 디렉터리 자신
        w.cur = parent
        local pp, pn = parent:match('^(.*)/([^/]+)$')
        local pd = parent ~= '' and s.dirs[pp or '']
        local pe = pd and pd.idx[pn or parent]
        if pe and walk_hit(pe, w.bits) then
          return walk_end(s, w, parent)
        end
      end
    end
    if e then
      w.cur = rel
      if w.step < 0 and walk_into(e, w.bits) then
        w.down = true    -- 뒤로: 안의 것이 먼저
      elseif walk_hit(e, w.bits) then
        return walk_end(s, w, rel)
      elseif w.step > 0 then
        w.down = walk_into(e, w.bits)
      end
    end
  end
end
walk_fn = walk

local function act_step(s, step)
  local r = cur_row(s)
  local from = r and (r.loading and r.rel:gsub('/$', '') or r.rel) or ''
  s.req = s.req + 1
  s.reveal_step = step
  if s.walk then
    walk_drop(s, s.walk)   -- 아직 목록을 기다리던 앞의 것
    s.walk = nil
  end
  if s.nomask and step_bits(s) then
    local e = from ~= '' and entry_of_fn(s, from)
    s.walk = { step = step, bits = step_bits(s), fresh = {}, cur = from,
      down = from == '' or (step > 0 and e and walk_into(e, step_bits(s))) or false }
    return walk(s)
  end
  send(s, { cmd = 'next', id = s.req, from = from, step = step, bits = step_bits(s) })
end

local function act_h(s)
  local r = cur_row(s)
  if not r or r.loading then
    return
  end
  if is_dir(r.e) and s.expanded[r.rel] then
    return toggle(s, r, false)
  end
  local parent = r.dir
  if parent and parent ~= '' and s.row_of[parent] then
    goto_row(s, s.row_of[parent])
  end
end

-- O / X 는 트리 전체 (Beyond Compare 의 Expand All / Collapse All). 처음에는 커서의
-- 디렉터리 아래만 했더니 맨 윗줄(한쪽에만 있는 디렉터리)에서 O 가 아무것도 펼치지 않았다
local function act_expand_all(s)
  s.req = s.req + 1
  if s.walk then
    walk_drop(s, s.walk)   -- 아직 목록을 기다리던 앞의 것 (act_step 처럼)
    s.walk = nil
  end
  if s.nomask and step_bits(s) then
    -- 예전 뒤쪽: 보기를 따라 여기서 걷는다 (expand_walk). 뒤쪽의 expand 는 '차이' 의 디렉터리를 펼친다
    s.walk = { todo = { '' }, open = {}, fresh = {}, n = 0, bits = step_bits(s) }
    return walk(s)
  end
  send(s, { cmd = 'expand', id = s.req, dir = '', bits = step_bits(s) })
end

local function act_collapse_all(s)
  local r = cur_row(s)
  local top = r and r.rel and r.rel:match('^[^/]+')
  if s.walk then
    walk_drop(s, s.walk)   -- 걷던 O·<C-n> 이 목록이 온 뒤에 도로 펼치지 않게
    s.walk = nil
  end
  for k in pairs(s.expanded) do
    if k ~= '' then
      s.expanded[k] = nil
      send(s, { cmd = 'unlist', dir = k })
    end
  end
  render(s)
  -- 커서는 있던 줄의 맨 위 조상에
  if top and s.row_of[top] then
    goto_row(s, s.row_of[top])
  end
end

-- ---------------------------------------------------------------------------
-- 고르기(A/B 쪽 따로)와 파일·디렉터리 복사 (Beyond Compare 의 Copy to Right / Left)
-- ---------------------------------------------------------------------------

local function cursor_side(s)
  -- 커서가 트리의 오른쪽 반(B)에 있는지 - 마우스로 눌렀거나 l/w 로 옮겼을 때
  local pos = api.nvim_win_get_cursor(s.win_l)
  local ob = s.offb and s.offb[pos[1]]
  if ob then
    s.side = pos[2] >= ob and 'b' or 'a'
  end
end

local function act_side(s)
  s.side = s.side == 'a' and 'b' or 'a'
  goto_row(s, api.nvim_win_get_cursor(s.win_l)[1])
  mark_side(s)
  s.prog_dirty = true
  schedule_render(s)
end

local function act_mark(s)
  local r = cur_row(s)
  if r and r.e then
    local side = s.side
    -- 'side == "a" and ka or kb' 로 썼더니 B 에만 있는 줄의 빈 A 쪽에서도 골라졌다
    local has
    if side == 'a' then
      has = r.e.ka
    else
      has = r.e.kb
    end
    if has then
      local m = s.marks[side]
      m[r.rel] = (not m[r.rel]) or nil
      s.dirty[r.rel] = true
      s.prog_dirty = true
      schedule_render(s)
    else
      say(('%s 쪽에 없는 항목입니다'):format(side:upper()))
    end
  end
  local i = api.nvim_win_get_cursor(s.win_l)[1]
  if i < api.nvim_buf_line_count(s.buf_l) then
    goto_row(s, i + 1)
    mark_side(s)
  end
end

-- ---------------------------------------------------------------------------
-- 비교할 곳 고르기 (Tab: [A] -> [B], neo-tree 의 Tab 처럼). [A] 는 neo-tree 의 것과 같은 하나다
-- - dirdiffpick.lua 가 들고 있고 [B] 에서 연다. 그래서 트리가 달라도 된다: 이 트리에서 [A],
-- 다른 비교 탭의 트리나 neo-tree 에서 [B]
-- ---------------------------------------------------------------------------

local function act_pick(s)
  local r = cur_row(s)
  if not (r and r.e) then
    return
  end
  cursor_side(s)
  local side = s.side
  local k
  if side == 'a' then
    k = r.e.ka
  else
    k = r.e.kb
  end
  if k == nil then
    -- 다른 쪽에만 있는 줄의 빈칸: 고를 것이 없다
    return say(('%s 쪽에 없는 항목입니다 - %s 쪽에서 고르세요 (<S-Tab> 쪽 바꾸기)')
      :format(side:upper(), side == 'a' and 'B' or 'A'))
  end
  if not _G.vimide_dirdiff_pick_path then
    return say('dirdiffpick.lua 가 없습니다', vim.log.levels.WARN)
  end
  local path = s[side] .. '/' .. r.rel
  -- 링크는 가리키는 것으로 (디렉터리를 가리키면 디렉터리)
  local rk = real_kind(k, path)
  local kind = (rk == 'd' or rk == 'ld') and 'dir' or ((rk == 'f' or rk == 'lf') and 'file') or nil
  if not kind then
    return say(('고를 수 없습니다 - %s 쪽은 %s: %s'):format(side:upper(), NOTE[rk] or '특수 파일', shown(r.rel)),
      vim.log.levels.WARN)
  end
  local tab = api.nvim_get_current_tabpage()
  _G.vimide_dirdiff_pick_path(path, kind)
  -- [B] 로 새 탭을 열었다. 새 탭은 편집 창에서 연다 (M.open, dirdiffpick.lua 의 tab_from_edit) -
  -- 그대로 두면 그 탭을 닫고 돌아왔을 때 이 탭의 커서가 위의 편집 창에 있다. 트리로 되돌려 둔다
  -- (키는 모두 트리에 있다). 잠깐 오가는 것이라 autocmd 는 돌리지 않는다
  if api.nvim_get_current_tabpage() ~= tab and api.nvim_win_is_valid(s.win_l) then
    local w = api.nvim_get_current_win()
    vim.cmd(('noautocmd call nvim_set_current_win(%d) | noautocmd call nvim_set_current_win(%d)'):format(s.win_l, w))
  end
end

local function session_of_buf(buf)
  for _, s in pairs(sessions) do
    if s.buf_l == buf then
      return s
    end
  end
end

-- [A] 를 그 줄의 그쪽 이름 바로 뒤에 (이름이 칸을 채웠으면 칸 끝에 겹쳐). 그릴 때마다 줄을
-- 찾는다 (dirdiffpick.lua 와 같은 까닭): 트리는 펼치기·보기 바꾸기·훑은 결과로 줄을 통째로 다시
-- 쓴다 - 표시를 버퍼에 박아 두면 다른 줄로 밀리거나 지워진다. 보기에서 빠져 줄이 없으면 달지 않는다
local function pick_mark(s, buf, top, bot, first)
  for _, p in ipairs({ first.path, first.real }) do
    for _, side in ipairs({ 'a', 'b' }) do
      local root = s[side] .. '/'
      if p:sub(1, #root) == root then
        local i = s.row_of[p:sub(#root + 1)]
        local r = i and s.rows[i]
        local has = r and r.e and ((side == 'a' and r.e.ka) or (side == 'b' and r.e.kb))
        if has and i - 1 >= top and i - 1 <= bot then
          local _, meta = side_text(s, layout(s), r, side)
          local off = side == 'b' and (s.offb[i] or 0) or 0
          local line = api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ''
          local room = meta.name_end - meta.name_vis >= 4
          local col = off + (room and meta.name_vis or meta.name_end)
          local dcol = vim.fn.strdisplaywidth(line:sub(1, col)) - (room and 0 or 4)
          api.nvim_buf_set_extmark(buf, ns_pick, i - 1, 0, {
            virt_text = { { ' [A]', 'VimIdeDirDiffPickA' } }, virt_text_pos = 'overlay',
            virt_text_win_col = math.max(0, dcol), hl_mode = 'combine', ephemeral = true,
          })
          return
        end
      end
    end
  end
end

api.nvim_set_decoration_provider(ns_pick, {
  on_win = function(_, _, buf, top, bot)
    if vim.bo[buf].filetype ~= 'vimidedirdiff' then
      return false
    end
    local first = _G.vimide_dirdiff_picked and _G.vimide_dirdiff_picked()
    local s = first and session_of_buf(buf)
    if s then
      pcall(pick_mark, s, buf, top, bot, first)
    end
    return false
  end,
})

local function clear_marks(s)
  if next(s.marks.a) or next(s.marks.b) then
    s.marks = { a = {}, b = {} }
    render(s)
  end
end

local function entry_of(s, rel)
  local dir, name = rel:match('^(.*)/([^/]+)$')
  dir, name = dir or '', name or rel
  local d = s.dirs[dir]
  return d and d.idx[name]
end
entry_of_fn = entry_of

-- 복사할 것: 원본 쪽(A→B 면 A)에서 Space 로 고른 것 > 비주얼 줄 > 커서 줄.
-- 반대쪽에서 고른 것은 쓰지 않는다 (B 에서 고른 것을 A→B 원본으로 써 B 쪽을 덮었다)
local function picked(s, from, l1, l2)
  local set, by_mark = {}, false
  if next(s.marks[from]) then
    by_mark = true
    for rel in pairs(s.marks[from]) do
      set[rel] = true
    end
  elseif l1 then
    for i = math.min(l1, l2), math.max(l1, l2) do
      local r = s.rows[i]
      if r and r.e then
        set[r.rel] = true
      end
    end
  else
    local r = cur_row(s)
    if r and r.e then
      set[r.rel] = true
    end
  end
  local list = vim.tbl_keys(set)
  table.sort(list)
  local out = {}
  for _, rel in ipairs(list) do
    local inside = false
    for _, o in ipairs(out) do
      if rel:sub(1, #o + 1) == o .. '/' then
        inside = true
        break
      end
    end
    if not inside then
      out[#out + 1] = rel
    end
  end
  return out, by_mark
end

-- 버퍼 이름은 nvim 이 디렉터리 쪽 링크를 풀어서 붙인다 - 뿌리를 M.open 에서 풀어 두었으니
-- 여기서도 버퍼 이름을 풀어서 견준다
local function real(p)
  return uv.fs_realpath(p) or vim.fn.resolve(p)
end

local function modified_under(path, is_dir_)
  -- 견줄 경로도 푼다: macOS 에서 트리의 이름(A 쪽 철자 - dirdiffscan.py 의 alias)과 버퍼 이름을
  -- 푼 것(디스크의 철자 - 대소문자·NFD)이 달라, 고친 채 저장하지 않은 B 의 foo.c 를 Foo.c 로
  -- 복사할 때 알아보지 못했다
  path = real(path)
  for _, b in ipairs(api.nvim_list_bufs()) do
    local n = api.nvim_buf_get_name(b)
    if n ~= '' and api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
      local rn = real(n)
      if rn == path or (is_dir_ and rn:sub(1, #path + 1) == path .. '/') then
        return vim.fn.fnamemodify(n, ':~:.')
      end
    end
  end
end

local WHY = {
  ['source missing'] = '원본에 없음', kind = '종류가 다름 (디렉터리 / 파일)',
  special = '특수 파일 (FIFO 등)', ['bad path'] = '경로가 이상함',
}
local function why_text(to, w)
  local parent = w:match('^parent:(.*)$')
  if parent then
    return ('%s 쪽 %s 가 진짜 디렉터리가 아님 (링크 등) - 따라가 쓰지 않는다'):format(to:upper(), shown(parent))
  end
  return WHY[w] or w
end

-- dir: 1 = A -> B (<C-r>), -1 = B -> A (<C-l>). 실제 복사는 뒤쪽(dirdiffscan.py 의 copier)이
-- 항목마다 안전하게 한다 - 여기서는 고르고, 묻고, 끝난 뒤를 정리한다
local function act_copy(s, dir, l1, l2)
  local from, to = dir > 0 and 'a' or 'b', dir > 0 and 'b' or 'a'
  if s.copying then
    return say('앞의 복사가 아직 끝나지 않았습니다', vim.log.levels.WARN)
  end
  -- 뒤쪽이 죽은 뒤에 보내면 아무도 받지 않아 '복사하는 중' 이 풀리지 않는다
  if not (s.job and s.job > 0) then
    return say('비교가 멈췄습니다 - R 로 다시 훑은 뒤 복사하세요', vim.log.levels.WARN)
  end
  local list, by_mark = picked(s, from, l1, l2)
  local paths, skipped, names = {}, {}, {}
  local nfile, ndir = 0, 0
  for _, rel in ipairs(list) do
    local e = entry_of(s, rel)
    local ks = e and (from == 'a' and e.ka or nil)
    if e and from == 'b' then
      ks = e.kb
    end
    local kt
    if e then
      if to == 'a' then
        kt = e.ka
      else
        kt = e.kb
      end
    end
    local w
    if not e or ks == nil then
      w = from:upper() .. ' 에 없음'
    elseif (ks == 'd') ~= (kt == 'd') and kt ~= nil then
      w = '종류가 다름 (디렉터리 / 파일)'
    elseif ks == 'o' then
      w = '특수 파일'
    else
      local m = modified_under(s[to] .. '/' .. rel, ks == 'd')
      if m then
        w = '저장하지 않은 버퍼: ' .. m
      end
    end
    if w then
      skipped[#skipped + 1] = shown(rel) .. ' - ' .. w
    else
      paths[#paths + 1] = rel
      names[#names + 1] = shown(rel) .. (ks == 'd' and '/' or '')
      if ks == 'd' then
        ndir = ndir + 1
      else
        nfile = nfile + 1
      end
    end
  end
  if #paths == 0 then
    return say(#skipped > 0 and ('복사할 것이 없습니다: ' .. table.concat(skipped, ', ')) or '복사할 것이 없습니다',
      vim.log.levels.WARN)
  end
  if (tonumber(vim.g.vimide_dirdiff_confirm_copy) or 1) ~= 0 then
    local what = {}
    if nfile > 0 then
      what[#what + 1] = ('파일 %d'):format(nfile)
    end
    if ndir > 0 then
      what[#what + 1] = ('디렉터리 %d'):format(ndir)
    end
    -- 무엇을 덮는지 이름으로 보인다 (수만으로는 엉뚱한 줄이 섞여도 알 수 없었다)
    local shown_names = vim.list_slice(names, 1, 8)
    local more = #names > 8 and (' 외 %d개'):format(#names - 8) or ''
    local msg = ('%s → %s: %s  (%s%s)\n%s 쪽의 같은 이름은 덮어씁니다. 디렉터리는 합칩니다 (지우지 않음).%s')
      :format(from:upper(), to:upper(), table.concat(what, ', '), table.concat(shown_names, ', '), more,
        to:upper(), #skipped > 0 and ('\n건너뜀: ' .. table.concat(skipped, ', ')) or '')
    local yes = vim.fn.confirm(msg, '&Yes\n&No', 2) == 1
    -- 물음이 차지한 줄을 치운다 - 그대로 두면 다음 알림이 Press ENTER 를 띄우고, 그동안은
    -- vim.schedule 이 돌지 않아 복사가 키를 누를 때까지 멈춰 있었다
    vim.cmd('redraw')
    if not yes then
      return say('복사하지 않았습니다')
    end
  end
  s.req = s.req + 1
  s.copying = { id = s.req, from = from, to = to, by_mark = by_mark, skipped = skipped }
  send(s, { cmd = 'copy', id = s.req, from = from, paths = paths })
  say(('복사하는 중… (%d 개)'):format(#paths))
end

-- 디스크에서 바뀐 경로 하나(저장한 파일, 복사한 곳)가 비교 o 의 어디인가: 뿌리에서의 경로들 (A·B
-- 양쪽에 들 수 있다), 그리고 그 경로가 o 의 뿌리이거나 그 위인지 (뿌리째 바뀌었다).
-- 버퍼 이름 그대로가 먼저다: 트리가 연 파일은 트리의 이름으로 열려 있다. 링크를 푼 이름(rp - macOS
-- 는 디스크의 철자, NFD·대소문자)으로 찾으면 트리에 없는 이름이 새 줄로 생긴다. 푼 이름은 그 경로가
-- 뿌리 밖일 때(/tmp 와 /private/tmp 등)와, 파일 링크를 저장해 가리키는 파일이 바뀌었을 때만
local function rels_in(o, full, rp, link)
  local paths, whole = {}, false
  for _, root in ipairs({ o.a, o.b }) do
    local pre = root .. '/'
    local mine = full:sub(1, #pre) == pre
    if mine then
      paths[#paths + 1] = full:sub(#pre + 1)
    end
    if (link or not mine) and rp ~= full and rp:sub(1, #pre) == pre then
      paths[#paths + 1] = rp:sub(#pre + 1)
    end
    for _, p in ipairs({ full, rp }) do
      if pre:sub(1, #p + 1) == p .. '/' then
        whole = true
      end
    end
  end
  return paths, whole
end

-- 다시 볼 곳(rels: 뿌리에서의 경로)의 목록을 버린다 - 그 아래 펼쳐 둔 디렉터리는 부모의 새 목록이
-- 온 뒤에 다시 청한다 (on_event 의 'list'). 보고 있던 짝이 그 안이면 부모의 새 목록이 온 뒤에 다시 연다
local function forget(s, rels)
  for _, rr in ipairs(rels) do
    for k in pairs(s.dirs) do
      if k == rr or k:sub(1, #rr + 1) == rr .. '/' then
        s.dirs[k] = nil
        s.loading[k] = nil
      end
    end
  end
  -- 열어 둔 짝마다 (위의 편집 창, 비교 탭들). rel -> { parent, ready }
  for _, v in ipairs(views_of_fn(s)) do
    local o = v.rel
    for _, rr in ipairs(o and rels or {}) do
      if o == rr or o:sub(1, #rr + 1) == rr .. '/' then
        local parent = o:match('^(.*)/[^/]+$') or ''
        s.reopen = s.reopen or {}
        s.reopen[o] = { parent = parent }
        if parent ~= '' and not s.expanded[parent] then
          request_list(s, parent)   -- 접혀 있어도 새 판정을 받아 온다
        end
        break
      end
    end
  end
  s.need_full = true
end

-- 뒤쪽의 'copied': 목록을 새로 받게 하고, 버퍼를 다시 읽고, 알린다
local function on_copied(s, ev)
  local c = s.copying
  s.copying = nil
  local to = c and c.to or 'b'
  local from = c and c.from or 'a'
  local roots = ev.roots or {}
  forget(s, roots)
  -- 대상 쪽 버퍼를 새로 읽는다 (비교가 연 것은 BufRead 훅 없이)
  local base = s[to]
  local tops = {}
  for i, rr in ipairs(roots) do
    tops[i] = real(base .. '/' .. rr)   -- 버퍼 이름처럼 푼다 (modified_under 와 같은 까닭)
  end
  for _, b in ipairs(api.nvim_list_bufs()) do
    local n = api.nvim_buf_get_name(b)
    if n ~= '' and api.nvim_buf_is_loaded(b) and not vim.bo[b].modified then
      local rn = real(n)
      for _, p in ipairs(tops) do
        if rn == p or rn:sub(1, #p + 1) == p .. '/' then
          if vim.b[b].vimide_dirdiff then
            pcall(api.nvim_buf_call, b, function()
              vim.cmd('silent! noautocmd edit!')
            end)
          else
            pcall(vim.cmd, 'silent! checktime ' .. b)
          end
          break
        end
      end
    end
  end
  if c and c.by_mark then
    s.marks[from] = {}
  end
  schedule_render(s)
  -- 같은 곳이 든 다른 비교에도 알린다 (:w 의 BufWritePost 처럼) - Tab/Tab 으로 연 안쪽 비교에서
  -- 복사했더니 바깥 비교 탭은 R 을 누를 때까지 옛 판정(=)·크기·수를 그대로 보였다. 복사한 디렉터리가
  -- 그 비교의 뿌리를 품으면(뿌리째 바뀌었다) 다시 훑는다 (R. 그쪽도 복사하는 중이면 그 복사가 끝난 뒤에)
  for _, o in pairs(sessions) do
    if o ~= s and not o.done then
      local rels, whole = {}, false
      for _, rr in ipairs(roots) do
        local full = base .. '/' .. rr
        local r, w = rels_in(o, full, real(full), false)
        vim.list_extend(rels, r)
        whole = whole or w
      end
      if whole then
        if o.copying then
          o.rescan = true
        else
          restart_fn(o)
        end
      elseif #rels > 0 then
        forget(o, rels)
        schedule_render(o)
        send(o, { cmd = 'refresh', paths = rels })
      end
    end
  end
  if s.rescan then
    -- 이 뒤쪽이 이어 보내는 것(부모의 'list')을 다 받은 뒤에 바꾼다
    s.rescan = nil
    vim.schedule(function()
      if not s.done then
        restart_fn(s)
      end
    end)
  end
  local skipped = vim.list_extend(vim.deepcopy(c and c.skipped or {}), {})
  for _, x in ipairs(ev.skipped or {}) do
    skipped[#skipped + 1] = shown(x[1]) .. ' - ' .. why_text(to, x[2])
  end
  local failed = {}
  for _, x in ipairs(ev.failed or {}) do
    failed[#failed + 1] = shown(x[1]) .. ': ' .. tostring(x[2])
  end
  local msg = ('%s → %s 복사: 파일 %d, 디렉터리 %d'):format(from:upper(), to:upper(), ev.files or 0, ev.dirs or 0)
  if #failed > 0 then
    say(msg .. ' / 실패 ' .. table.concat(failed, '; ') .. (#skipped > 0 and (' / 건너뜀 ' .. table.concat(skipped, ', ')) or ''),
      vim.log.levels.WARN)
  elseif #skipped > 0 then
    say(msg .. ' / 건너뜀 ' .. table.concat(skipped, ', '), vim.log.levels.WARN)
  else
    say(msg)
  end
end
copied_fn = on_copied

-- 편집 창(비교 중인 두 창)에서 <C-r>/<C-l>: 커서가 있는 차이 덩어리째 오른쪽/왼쪽으로 (범위
-- 없는 :diffput / :diffget 처럼). 횟수가 있으면 커서 줄부터 그만큼(1<C-r> = 커서 줄만), 비주얼이면
-- 고른 줄만, <C-S-r>/<C-S-l> 도 커서 줄만. 커서 줄 하나(<C-S-r>, 1<C-r>)는 바뀐 줄이 아니면 바로
-- 위·아래에 끼인 줄(다른 쪽에만 있는 줄)이 있을 때만 그 덩어리째 (여러 줄일 수 있다)
--
-- 'diff' 가 꺼진 편집 창도, 안내 버퍼(바이너리·큰 파일의 알림 - diffthis 를 하지 않는다)를 띄우고
-- 있으면 받는다: 넘겼더니 <C-r> 은 되돌리기 취소(E21), <C-l> 은 창 옮기기가 되어 트리 복사를 알리지
-- 못했다. 처음의 빈 창(아직 연 짝이 없다)과 사용자가 :e 로 띄운 파일은 넘긴다
local function applies()
  local w = api.nvim_get_current_win()
  local v = view_of_win(w)
  if not v then
    return nil
  end
  if vim.wo[w].diff or (v.rel and vim.bo[api.nvim_win_get_buf(w)].buftype ~= '') then
    return v
  end
end

-- 0 바이트 파일(빈 버퍼): 줄은 하나('')로 보이지만 diff 에는 줄이 없다 (그 자리 줄 위에 저쪽 줄
-- 수만큼 끼인 줄이 붙는다). line2byte(1) 은 버퍼를 만든 길에 따라 -1 이 아니어서 바이트 수로 본다
local function empty_buf(b)
  return api.nvim_buf_line_count(b) == 1 and api.nvim_buf_get_lines(b, 0, 1, false)[1] == ''
    and api.nvim_buf_call(b, function()
      return vim.fn.wordcount().bytes
    end) == 0
end

-- 0 바이트 파일(빈 버퍼)로: 이쪽에 줄이 없으니 저쪽 줄 모두가 한 덩어리다 - diffopt 와 상관없이 직접
-- 넣는다 (한 번에 바꾸니 u 한 번에 빈 파일로). iblank·filler 없음에서는 행을 셀 수 없어 범위로(:diffput)
-- 맡겼더니 nvim 의 그 탈(copy_rows 에 적은 둘째)이 돌아와 u 뒤에 줄 하나가 남았다. 덩어리째와 가져오기
-- (커서가 빈 쪽)는 원본 전체, 보내기의 횟수·비주얼·커서 줄은 그 줄들 (copy_into_blank 와 같다).
-- iblank 인데 원본이 빈 줄뿐이면 차이가 없다.
-- 돌려주는 것: 바꿨으면 true, 차이가 없으면 false, 대상이 빈 버퍼가 아니면(또는 원본도 비었으면) nil
local function copy_into_empty(put, whole, l1, l2, tb, sb)
  if not empty_buf(tb) or empty_buf(sb) then
    return nil
  end
  local src = api.nvim_buf_get_lines(sb, 0, -1, false)
  if (',' .. vim.o.diffopt .. ','):find(',iblank,', 1, true) then
    local any = false
    for _, x in ipairs(src) do
      if x:find('%S') then
        any = true
        break
      end
    end
    if not any then
      return false
    end
  end
  if put and not whole then
    src = vim.list_slice(src, l1, l2)
  end
  api.nvim_buf_set_lines(tb, 0, -1, false, src)
  return true
end

-- (copy_rows 가 셀 수 없을 때) 지금 창에서 줄 l 이 든 차이 덩어리를 :r1,r2diffput 의 범위로: 바뀐
-- 줄이 이어진 데와 그 사이·위·아래에 끼인 줄(이 창에는 줄 번호가 없다). l 이 바뀐 줄이 아니면 바로
-- 위, 그다음 바로 아래에 끼인 줄의 덩어리. 끼인 줄은 그 아래 줄 앞에 붙어 있어서(diff_filler) 위에
-- 끼인 줄은 한 줄 위부터, 아래에 끼인 줄은 한 줄 아래까지 잡는다 (그 줄이 다음 조각의 첫 줄이면
-- 그 조각도 따라온다 - copy_rows 를 먼저 쓰는 까닭)
local function hunk_range(l)
  local n = vim.fn.line('$')
  local function changed(x)
    return x >= 1 and x <= n and vim.fn.diff_hlID(x, 1) ~= 0
  end
  local h1, h2
  if changed(l) then
    h1, h2 = l, l
  elseif vim.fn.diff_filler(l) > 0 then
    h1, h2 = l, l - 1
  elseif vim.fn.diff_filler(l + 1) > 0 then -- l 이 마지막 줄이면 파일 끝 아래에 끼인 줄
    h1, h2 = l + 1, l
  else
    return nil
  end
  while changed(h1 - 1) do
    h1 = h1 - 1
  end
  while changed(h2 + 1) do
    h2 = h2 + 1
  end
  -- 끼인 줄만인 덩어리는 위·아래가 같은 끼인 줄이라 범위가 h2,h1 이 된다
  local r1 = vim.fn.diff_filler(h1) > 0 and h1 - 1 or h1
  local r2 = vim.fn.diff_filler(h2 + 1) > 0 and h2 + 1 or h2
  return { r1, r2, n }
end

-- 창의 행: 끼인 줄은 false, 진짜 줄은 줄 번호 (빈 버퍼의 자리 줄은 행이 아니다). diff_filler 는
-- 줄마다 조각 목록을 처음부터 찾아서 줄 수 x 조각 수만큼 걸린다 - deadline 을 넘기면 nil
local function rows_of(win, deadline)
  local rows = {}
  local done = api.nvim_win_call(win, function()
    local n = empty_buf(0) and 0 or vim.fn.line('$')
    for l = 1, n + 1 do
      if l % 512 == 0 and uv.hrtime() > deadline then
        return false
      end
      for _ = 1, vim.fn.diff_filler(l) do
        rows[#rows + 1] = false
      end
      if l <= n then
        rows[#rows + 1] = l
      end
    end
    return true
  end)
  return done and rows or nil
end

-- 덩어리째 복사: 두 창의 행(끼인 줄 포함)을 처음부터 세어 맞추고 대상의 그 줄들을 직접 바꾼다.
-- :diffput/:diffget 에 범위를 주어 맡기지 않는 까닭 (무작위 비교로 찾았다):
--  - linematch(nvim 기본 diffopt)는 한 덩어리를 조각으로 나누고 같은 줄을 맞춰 보인다. 범위로는
--    "줄 L 위에 끼인 줄"과 "줄 L 에서 시작하는 조각"을 가를 수 없어서, 덩어리 끝의 끼인 줄을 잡으려고
--    한 줄 넓히면 옆 조각(같은 줄로 보이는 줄 뒤에 저쪽 줄이 더 붙은 것)까지 옮겨 저쪽 줄이 지워졌다.
--    범위 없이 치면 커서가 있는 조각만 옮긴다
--  - 대상이 빈 줄 하나뿐인 때(처음부터, 또는 조각을 옮기는 사이)를 만나면 그것을 빈 버퍼의 자리
--    줄로 알고 넣은 줄 다음 줄을 지운다 (vim 도 같다). 0 바이트 파일에 넣은 것은 u 한 번에 줄
--    하나가 남았다
-- linematch 는 화면에 보이는 줄을 물을 때에야 조각낸다 - 이 창, 저 창, 다시 이 창 순으로 세어
-- 조각이 굳은 뒤의 행을 쓴다. 너무 크면(250ms) nil - 범위로 옮긴다 (copy_hunk).
-- 돌려주는 것: 바꿨으면 true, 덩어리가 없으면 false, 셀 수 없으면 nil.
-- 행으로 셀 수 없는 diffopt: iblank 는 빈 줄만인 덩어리를 끼인 줄 없이 지우고(두 창의 행이 어긋난다),
-- filler 가 없으면 끼인 줄이 아예 없다. 어긋난 것이 양쪽에서 비기면 행 수가 같아 아래 #rw ~= #ro 로도
-- 못 걸렀고, 바뀌지 않은 줄을 덮어썼다 (A '\nx\ny\nw\n', B 'x\nz\nw\n\n' 의 y 에서 <C-r>: B 의 w 가
-- y 로, z 는 그대로). 그때는 범위로 옮긴다 (copy_hunk - nvim 이 맞춘다). 0 바이트 파일로 넣는 것은
-- 그 앞에서 copy_into_empty 가 한다 (범위로 맡기면 위의 둘째 탈이 돌아온다)
local function copy_rows(w, other, put)
  local dopt = ',' .. vim.o.diffopt .. ','
  if dopt:find(',iblank,', 1, true) or not dopt:find(',filler,', 1, true) then
    return nil
  end
  local deadline = uv.hrtime() + 250e6
  local rw = rows_of(w, deadline)
  local ro = rw and rows_of(other, deadline)
  rw = ro and rows_of(w, deadline)
  if not rw or #rw ~= #ro then
    return nil
  end
  local function changed(i)
    return rw[i] == false or ro[i] == false or vim.fn.diff_hlID(rw[i], 1) ~= 0
  end
  local c, cur = #rw + 1, vim.fn.line('.') -- 빈 버퍼의 자리 줄은 모든 행 아래에 있다
  for i, l in ipairs(rw) do
    if l == cur then
      c = i
      break
    end
  end
  -- 커서 줄이 바뀐 줄이 아니면 바로 위(범위 없는 :diffput 처럼 위가 먼저), 바로 아래에 끼인 줄
  local s, e
  if c <= #rw and changed(c) then
    s, e = c, c
  elseif c > 1 and rw[c - 1] == false then
    s, e = c - 1, c - 1
  elseif c < #rw and rw[c + 1] == false then
    s, e = c + 1, c + 1
  else
    return false
  end
  while s > 1 and changed(s - 1) do
    s = s - 1
  end
  while e < #rw and changed(e + 1) do
    e = e + 1
  end
  local src, dst = put and rw or ro, put and ro or rw
  local first, cnt, a, b = 0, 0, nil, nil
  for i = 1, e do
    if dst[i] then
      if i < s then
        first = first + 1
      else
        cnt = cnt + 1
      end
    end
    if i >= s and src[i] then
      a, b = a or src[i], src[i]
    end
  end
  local sb, tb = api.nvim_win_get_buf(put and w or other), api.nvim_win_get_buf(put and other or w)
  local lines = a and api.nvim_buf_get_lines(sb, a - 1, b, false) or {}
  if empty_buf(tb) then
    api.nvim_buf_set_lines(tb, 0, -1, false, lines)   -- 자리 줄은 남기지 않는다
  else
    api.nvim_buf_set_lines(tb, first, first + cnt, false, lines)
  end
  return true
end

-- 덩어리째 복사를 범위로 (copy_rows 가 셀 수 없을 때 - 큰 파일): :r1,r2diffput (put: 이 창 -> 저 창).
-- 파일 맨 위·맨 아래에 끼인 줄은 범위로 잡을 수 없다 (0 줄은 1 로 바뀌고 $+1 은 E16) - 그때는 저
-- 창에서 거꾸로(put <-> get) 한다. 이 창의 그 끝이 끼인 줄이면 저 창의 그 끝은 진짜 줄이라서 저 창의
-- 맨 위(맨 아래) 줄이 같은 덩어리에 든다. 저 창도 반대쪽 끝이 걸리면 덩어리가 파일 전체다
local function copy_hunk(w, other, put, h)
  local mine, theirs = api.nvim_win_get_buf(w), api.nvim_win_get_buf(other)
  if h[1] >= 1 and h[2] <= h[3] then
    vim.cmd(('%d,%d%s %d'):format(h[1], h[2], put and 'diffput' or 'diffget', theirs))
    return true
  end
  local o = api.nvim_win_call(other, function()
    return hunk_range(h[1] < 1 and 1 or vim.fn.line('$')) or false
  end)
  if not o then
    -- 끼인 줄이 맞지 않는 diffopt(iblank 등): nvim 이 고르는 대로
    vim.cmd((put and 'diffput' or 'diffget') .. ' ' .. theirs)
  elseif o[1] >= 1 and o[2] <= o[3] then
    api.nvim_win_call(other, function()
      vim.cmd(('%d,%d%s %d'):format(o[1], o[2], put and 'diffget' or 'diffput', mine))
    end)
  else
    local from, to = put and mine or theirs, put and theirs or mine
    api.nvim_buf_set_lines(to, 0, -1, false, api.nvim_buf_get_lines(from, 0, -1, false))
  end
  return true
end

-- 줄 단위 복사에서 대상이 빈 줄 하나뿐("\n")이거나 빈 버퍼일 때 (copy_rows 에 적은 둘째 탈): 대상에
-- 줄이 없거나 하나뿐이라 줄 맞춤이 쉽다 - 행으로 세어 직접 바꾼다. 행: 대상은 위에 끼인 줄 fa 개,
-- 그 줄(k 행, 빈 버퍼면 자리 줄이라 행이 아니다), 아래에 끼인 줄. 원본에는 k 행에만 끼인 줄이 있을
-- 수 있다 (대상의 빈 줄이 원본에 없는 줄일 때). 원본이 빈 버퍼면 넣을 줄이 없어 nvim 에 맡긴다.
-- whole: 덩어리째 (copy_rows 가 셀 수 없는 diffopt - iblank, filler 없음 - 에서 빈 줄 하나뿐인 대상. 범위로
-- 맡겼더니 nvim 의 :diffput 이 줄 하나를 잃었다). 그 줄이 바뀐 줄이면 저쪽 모두가 한 덩어리라 끼인 줄을
-- 세지 않는다. 아니면 위(먼저)·아래에 끼인 줄 덩어리 - 보내기는 커서 줄이 든 쪽
-- 돌려주는 것: 바꿨으면 true, 그 자리에 차이가 없으면 false, 행이 맞지 않으면 nil
local function copy_into_blank(put, visual, l1, l2, tw, sw, whole)
  local tb, sb = api.nvim_win_get_buf(tw), api.nvim_win_get_buf(sw)
  if empty_buf(sb) then
    return nil
  end
  local t = api.nvim_win_call(tw, function()
    return { vim.fn.diff_filler(1), vim.fn.diff_filler(2), vim.fn.diff_hlID(1, 1) ~= 0 }
  end)
  local none = empty_buf(tb)
  local fa, tch = t[1], t[3]
  local k, total = fa + 1, fa + (none and 0 or 1) + t[2]
  local src = api.nvim_buf_get_lines(sb, 0, -1, false)
  if whole and tch and not none then
    api.nvim_buf_set_lines(tb, 0, -1, false, src)
    return true
  end
  local sk = total - #src
  if sk < 0 or sk > 1 or (sk == 1 and not tch) or (none and (tch or t[2] > 0)) then
    return nil
  end
  local function srow(i)
    return i < k and i or i + sk
  end
  local x1, x2
  if whole then
    local r = put and srow(l1) or k
    if r < k or (not put and fa > 0) then
      x1, x2 = 1, fa
    elseif r > k or (not put and total > k) then
      x1, x2 = k + 1, total
    end
  elseif not put then                   -- 커서가 대상의 그 줄에
    if tch then
      x1, x2 = k, k
    elseif fa > 0 then
      x1, x2 = 1, fa
    elseif total > k then
      x1, x2 = k + 1, total
    end
  elseif visual or tch or srow(l1) ~= k then
    x1, x2 = srow(l1), srow(l2)
  end
  if not x1 then
    return false
  end
  local up, mid, down = {}, none and {} or { '' }, {}
  for r = x1, x2 do
    if r < k then
      up[#up + 1] = src[r]
    elseif r > k then
      down[#down + 1] = src[r - sk]
    else
      mid = sk == 0 and { src[k] } or {}
    end
  end
  api.nvim_buf_set_lines(tb, 0, -1, false, vim.list_extend(vim.list_extend(up, mid), down))
  return true
end

-- tmux 안이고 그 서버가 extended-keys(3.2+)를 모르면 그 판('3.0a'), 아니면 false. 한 번만 묻는다.
-- 그런 서버 안에서는 Ctrl+Shift+R/L 이 <C-r>/<C-l> 로 온다 (TAKE 의 설명). #{version} 은 서버의 판이다
-- (tmux -V 는 클라이언트의 판). 개발서버의 ~/.local/bin/tmux 래퍼는 옛 서버에는 옛 클라이언트로 묻는다
local tmux_old_v, tmux_told
local function tmux_old()
  if tmux_old_v == nil then
    tmux_old_v = false
    if (vim.env.TMUX or '') ~= '' and vim.system and vim.fn.executable('tmux') == 1 then
      local ok, r = pcall(function()
        return vim.system({ 'tmux', 'display-message', '-p', '#{version}' }, { text = true }):wait(1000)
      end)
      local maj, min = (ok and r.code == 0 and vim.trim(r.stdout or '') or ''):match('^(%d+)%.(%d+)')
      if maj and (tonumber(maj) < 3 or (tonumber(maj) == 3 and tonumber(min) < 2)) then
        tmux_old_v = vim.trim(r.stdout)
      end
    end
  end
  return tmux_old_v
end

-- one: <C-S-r>/<C-S-l> - 횟수가 없어도 커서 줄만
function _G.vimide_dirdiff_copy_lines(dir, one)
  local v = applies()
  if not v then
    return
  end
  local w = api.nvim_get_current_win()
  local mode = api.nvim_get_mode().mode
  local visual = mode:match('^[vV\22]') ~= nil
  local whole = not visual and not one and vim.v.count == 0
  local count = vim.v.count1
  -- 횟수는 마지막 줄에서 멈춘다 (15dd 처럼). 그대로 두었더니 30,44diffput 이 E16 으로 실패해
  -- 있는 줄까지 하나도 복사되지 않았다
  local l1, l2 = vim.fn.line('.'), math.min(vim.fn.line('.') + count - 1, vim.fn.line('$'))
  if visual then
    l1, l2 = vim.fn.line('v'), vim.fn.line('.')
    if l1 > l2 then
      l1, l2 = l2, l1
    end
    -- 비주얼을 끝낸다. feedkeys('<Esc>', 'x') 는 뒤에 쌓인 키까지 비주얼 안에서 먼저 돌렸다
    vim.cmd('normal! \27')
  end
  local in_a = w == v.win_a
  local put = (dir > 0) == in_a          -- 내 창에서 저쪽으로 보내기 / 저쪽에서 가져오기
  local other = in_a and v.win_b or v.win_a
  if not api.nvim_win_is_valid(other) then
    return
  end
  local mine, theirs = api.nvim_get_current_buf(), api.nvim_win_get_buf(other)
  local tb = put and theirs or mine
  -- 양쪽 다 진짜 파일이어야 한다: 빈 쪽(한쪽에만 있는 파일)·안내 쪽에서 가져오면 안내 글이
  -- 파일에 들어가거나 줄이 지워졌다
  for _, b in ipairs({ mine, theirs }) do
    if vim.bo[b].buftype ~= '' then
      if v.bin then
        return say('바이너리·큰 파일은 줄로 복사할 수 없습니다 - 파일째는 트리에서 <C-r>/<C-l> 로 복사하세요',
          vim.log.levels.WARN)
      end
      local side = (b == v.empty_a or api.nvim_win_get_buf(v.win_a) == b) and 'A' or 'B'
      return say(side .. ' 쪽은 파일이 아닙니다 - 파일째는 트리에서 <C-r>/<C-l> 로 복사하세요',
        vim.log.levels.WARN)
    end
  end
  -- 덩어리째는 대상 버퍼를 직접 바꾸므로(copy_rows) 미리 본다 - 그대로 두면 API 오류가 파일·줄
  -- 번호를 단 채 나왔다 (:diffput 은 E21)
  if not vim.bo[tb].modifiable then
    return say(((tb == api.nvim_win_get_buf(v.win_a)) and 'A' or 'B')
      .. " 쪽 버퍼는 고칠 수 없습니다 ('modifiable' 꺼짐)", vim.log.levels.WARN)
  end
  -- 저쪽 버퍼를 이름으로 준다: 이 탭에 diff 창이 셋 이상이면 이름 없는 :diffput 은 E101 이었다
  local cmd = (put and 'diffput' or 'diffget') .. ' ' .. theirs
  local range
  if whole then
    range = nil
  elseif visual or l2 > l1 or vim.fn.diff_hlID(l1, 1) ~= 0 then
    -- 여러 줄(비주얼, N<C-r>)은 그 줄들 - 커서 줄만 보았더니 N<C-r> 이 커서 줄이 바뀌지 않았으면
    -- 범위를 버리고 '차이가 없다' 고 하거나 커서 옆에 끼인 줄 덩어리(범위 밖일 수도)를 옮겼다.
    -- 마지막 줄에서 잘려 한 줄이 된 횟수는 아래의 커서 줄 규칙대로 (2<C-l> 이 그 아래 줄을 가져온다)
    range = ('%d,%d'):format(l1, l2)
  elseif vim.fn.diff_filler(l1) > 0 then
    range = ''                           -- 바로 위에 끼인 줄: 그 덩어리
  elseif vim.fn.diff_filler(l1 + 1) > 0 then
    -- 바로 아래에 끼인 줄. 마지막 줄 아래는 범위로 못 잡는다(E16) - 범위 없는 :diffput 이
    -- 마지막 줄에서는 그 아래를 잡는다
    range = l1 < vim.fn.line('$') and ('%d,%d'):format(l1, l1 + 1) or ''
  elseif not put and empty_buf(tb) then
    range = ''   -- 빈 버퍼(0 바이트)의 자리 줄로 가져오기: filler 가 없어 끼인 줄이 안 보여도 저쪽 전체
  else
    return say('이 줄에는 차이가 없습니다')
  end
  local tick = vim.b[tb].changedtick
  local ok, res = pcall(function()
    local into = copy_into_empty(put, whole, l1, l2, tb, put and mine or theirs)
    if into ~= nil then
      return into
    end
    if whole then
      local done = copy_rows(w, other, put)
      if done == nil and api.nvim_buf_line_count(tb) == 1 and api.nvim_buf_get_lines(tb, 0, 1, false)[1] == '' then
        done = copy_into_blank(put, false, l1, l1, put and other or w, put and w or other, true)
      end
      if done ~= nil then
        return done
      end
      local h = hunk_range(l1)
      if not h then
        return false
      end
      return copy_hunk(w, other, put, h)
    end
    if api.nvim_buf_line_count(tb) == 1 and api.nvim_buf_get_lines(tb, 0, 1, false)[1] == '' then
      local done = copy_into_blank(put, visual or l2 > l1, l1, l2, put and other or w, put and w or other)
      if done ~= nil then
        return done
      end
    end
    vim.cmd(range .. cmd)
    return true
  end)
  if not ok then
    say(tostring(res):gsub('^.-(E%d+:)', '%1'), vim.log.levels.WARN)
  elseif not res or (not whole and vim.b[tb].changedtick == tick) then
    -- 범위로 옮겼는데 바뀐 것이 없으면 그 줄들에 차이가 없는 것이다 - 비주얼·횟수는 아무 말이
    -- 없었다 (범위 첫 줄 바로 위에 끼인 줄은 범위에 들지 않는다 - nvim 의 :1,1diffget 도 같다)
    local msg = '이 줄에는 차이가 없습니다'
    if whole then
      msg = '커서가 차이 덩어리에 있지 않습니다 (다음·앞 차이는 <C-n>/<C-p>)'
    elseif visual then
      msg = '고른 줄에는 차이가 없습니다'
    elseif l2 > l1 then
      msg = ('커서 줄부터 %d 줄에는 차이가 없습니다'):format(l2 - l1 + 1)
    end
    return say(msg)
  elseif vim.b[tb].changedtick ~= tick then
    -- 복사 하나를 되돌리기 한 번으로 (그대로 두면 이어진 복사들이 한 번에 되돌려졌다)
    pcall(api.nvim_buf_call, tb, function()
      vim.cmd('let &g:undolevels = &g:undolevels')
    end)
  end
  pcall(vim.cmd, 'diffupdate')
  -- 옛 tmux 서버 안에서 덩어리째 복사했으면 한 번 알린다 - Ctrl+Shift+R 을 눌렀어도 여기로 온다
  if ok and whole and not tmux_told and vim.b[tb].changedtick ~= tick and tmux_old() then
    tmux_told = true
    say(('덩어리째 복사했습니다 - 이 tmux 서버(%s)는 Ctrl+Shift+R/L 도 <C-r>/<C-l> 로 넘깁니다.'
      .. ' 커서 줄만은 1<C-r>/1<C-l> (Ctrl+Shift 는 tmux 3.2 이상 서버에서)'):format(tmux_old()))
  end
end

-- 전역 <C-r>/<C-l> 를 비교 창에서만 가로챈다. 그 밖에서는 원래대로 (<C-r> 되돌리기 취소,
-- <C-l> 은 .vimrc 의 창 옮기기): expr 매핑이라 원래 키가 그 자리(쌓인 키 앞)에서 돈다 -
-- feedkeys 로 넘겼더니 빠르게 친 뒤의 키가 먼저 돌았다.
-- 키 -> { 방향, 커서 줄만 }. <C-S-r>/<C-S-l> 은 Ctrl+Shift 가 nvim 까지 따로 올 때만 온다 -
-- Tera Term 등에서는 그냥 <C-r>/<C-l> 이 오므로 1<C-r>/1<C-l> 이 같은 일을 한다.
-- iTerm2 는 따로 켤 것이 없다: nvim(또는 tmux)이 modifyOtherKeys 2 를 달라고 하면 Ctrl+Shift+R 을
-- CSI 27;6;82~ 로 보낸다 (Profiles > Keys 의 'Apps can change how keys are reported', 기본 켜짐).
-- tmux 안이면 tmux '서버'가 3.2 이상이고 extended-keys on 이어야 한다. 3.0a(Ubuntu 20.04 apt 판)는
-- iTerm2 에 아무것도 달라고 하지 않아 Ctrl+Shift+R 이 그냥 0x12(<C-r>)로 와서 덩어리째 복사된다
-- (iTerm2 를 흉내 낸 pty 로 tmux 3.0a / 3.7c 를 실측). ~/.local/bin/tmux 래퍼는 옛 서버가 떠 있는
-- 동안 그 서버에 옛 판으로 붙으므로, 깔아 둔 새 판은 그 서버를 끝낸 뒤에야 쓰인다 - 그 사이에는
-- 덩어리째 복사할 때 한 번 알리고(tmux_old) 도움말에도 적는다.
-- 비교 창 밖의 <C-S-r>/<C-S-l> 도 그 키 그대로 넘긴다
-- (매핑이 없을 때 nvim 은 <C-S-r> 을 <C-r> 처럼 되돌리기 취소로 친다)
local TAKE = {
  ['<C-r>'] = { 1 }, ['<C-l>'] = { -1 },
  ['<C-S-r>'] = { 1, true }, ['<C-S-l>'] = { -1, true },
}
local prev_maps = {}

function _G.vimide_dirdiff_prev_key(id)
  local p = prev_maps[id]
  if p and p.callback then
    return p.callback()
  end
end

-- 전역 매핑 lhs(mode)를 감싼다: when() 이 돌릴 키를 주면 그것, 아니면 감싸기 전의 매핑(없으면 그 키
-- 그대로). 감싸기 전의 것은 prev_maps[id] 에 - 단축키 도움말(keyhelp.lua 의 SCOPED)이 이 함수의
-- upvalue prev_maps·id 로 '그 밖에서는 …' 을 찾는다 (이름을 바꾸면 거기도)
local function wrap(mode, lhs, when, desc)
  -- 전역 매핑만 본다. maparg() 는 지금 버퍼의 매핑을 먼저 돌려주어서, 그런 창(neo-tree 등)에서
  -- .vimrc 를 다시 읽으면(:source - 이것을 다시 부른다) 그 버퍼의 q 를 어디서나 돌렸다
  local prev
  local want = api.nvim_replace_termcodes(
    lhs:gsub('<[Ll]eader>', ((vim.g.mapleader or '\\'):gsub('%%', '%%%%'))), true, true, true)
  for _, m in ipairs(api.nvim_get_keymap(mode)) do
    if api.nvim_replace_termcodes(m.lhs, true, true, true) == want then
      prev = m
      break
    end
  end
  if type(prev) == 'table' and prev.desc and prev.desc:match('^DirDiff 비교 창') then
    prev = prev_maps[mode .. lhs]   -- 벌써 가로챈 것 - 처음 것을 그대로
  end
  if type(prev) ~= 'table' or vim.tbl_isempty(prev) then
    prev = nil
  end
  prev_maps[mode .. lhs] = prev
  local id = mode .. lhs
  vim.keymap.set(mode, lhs, function()
    local keys = when()
    if keys then
      return keys
    end
    local p = prev_maps[id]
    if not p then
      return lhs
    end
    if p.callback then
      -- replace_keycodes 가 id 안의 <leader> 까지 바꾸므로 < 를 <lt> 로 (그대로면 "n\d" 로 Lua 오류)
      return ('<Cmd>lua _G.vimide_dirdiff_prev_key(%q)<CR>'):format((id:gsub('<', '<lt>')))
    end
    return p.rhs
  end, { expr = true, silent = true, replace_keycodes = true, desc = desc })
end

local function take_over()
  for lhs, t in pairs(TAKE) do
    local dir, one = t[1], t[2] == true
    for _, mode in ipairs({ 'n', 'x' }) do
      wrap(mode, lhs, function()
        if applies() then
          return ('<Cmd>lua _G.vimide_dirdiff_copy_lines(%d, %s)<CR>'):format(dir, tostring(one))
        end
      end, 'DirDiff 비교 창: ' .. (one and '커서 줄을 ' or '차이 덩어리를 ')
        .. (dir > 0 and '오른쪽(B)' or '왼쪽(A)') .. '으로')
    end
  end
end

-- <C-w>w / <C-w><C-w> / <C-w>W 를 비교 창(비교 탭의 두 창, pair_tab = 0 의 편집 창 둘)에서만: 곁 창(경로 줄·
-- 개요 막대·줄 자세히)을 건너뛰고 다음/앞 창으로. 감싸지 않았더니 비교 창 B 에서 <C-w>w 가 줄 자세히로 갔다가
-- 돌려보내져 늘 B 에 머물렀다 (A·B 를 <C-w>w 로 오가는 vimdiff 버릇). 횟수가 있으면(3<C-w>w) 원래대로.
-- 다른 창(트리 등)에서는 원래대로 - 곁 창에 들어가면 cmp.bounce 가 알맞은 창으로 보낸다
function _G.vimide_dirdiff_cycle(dir)
  local wins = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local c = api.nvim_win_get_config(w)
    if (c.relative == '' or c.focusable) and not cmp.FT[vim.bo[api.nvim_win_get_buf(w)].filetype] then
      wins[#wins + 1] = w
    end
  end
  local cur = api.nvim_get_current_win()
  local i = 0
  for k, w in ipairs(wins) do
    if w == cur then
      i = k
    end
  end
  if #wins > 0 then
    api.nvim_set_current_win(wins[((i - 1 + dir) % #wins) + 1])
  end
end

-- 비교 창에서만 쓰는 다른 키 (copy_keys 와 상관없이 늘): \d 보기 고르기 - 리더 d 는 neo-tree 밖에서
-- 비어 있다 (neo-tree 의 \d 는 그 버퍼의 매핑이라 이것보다 먼저다). q 는 비교 탭의 것만 - 그 탭을
-- 닫는다 (diffview 의 diff 창에 vim-ide 가 건 q 와 같다). 매크로를 적는 중이면 q 그대로 (적기 끝).
-- pair_tab = 0 의 편집 창에서 q 는 예전대로 매크로다. <C-w>w <C-w><C-w> <C-w>W 는 곁 창을 건너뛴다
-- (위 _G.vimide_dirdiff_cycle)
local function take_over_view_keys()
  for _, spec in ipairs({ { '<C-w>w', 1 }, { '<C-w><C-w>', 1 }, { '<C-w>W', -1 } }) do
    wrap('n', spec[1], function()
      if vim.v.count == 0 and view_of_win(api.nvim_get_current_win()) then
        return ('<Cmd>lua _G.vimide_dirdiff_cycle(%d)<CR>'):format(spec[2])
      end
    end, 'DirDiff 비교 창: ' .. (spec[2] > 0 and '다음' or '앞') .. ' 창으로 (경로 줄·개요 막대·줄 자세히는 건너뛴다)')
  end
  wrap('n', '<leader>d', function()
    if view_of_win(api.nvim_get_current_win()) then
      return '<Cmd>lua _G.vimide_dirdiff_file_menu()<CR>'
    end
  end, 'DirDiff 비교 창: 보기 고르기 (모두 / 차이 / 문맥 보이기)')
  wrap('n', 'q', function()
    local v = view_of_win(api.nvim_get_current_win())
    if v and not v.inline and vim.fn.reg_recording() == '' then
      return '<Cmd>lua _G.vimide_dirdiff_pair_quit()<CR>'
    end
  end, 'DirDiff 비교 창: 비교 탭 닫기 (트리의 그 줄로)')
end

-- .vimrc 를 다시 읽으면(:source) 그 map <C-l> 이 이것을 덮는다 - .vimrc 가 이것을 다시 부른다
-- ,r / ,e (.vimrc 의 BufCycle 이 먼저 묻는다): DirDiff 탭(트리 탭과 그 비교 탭들) 안에서는 버퍼가 아니라
-- 그 비교의 탭 사이를 오간다 (요청). 탭이 여럿이면 airline 의 탭 줄이 버퍼 대신 탭을 보이므로 같은 키가
-- 그 탭들을 따라가는 것이 맞다 - 버퍼 이동(:bn!)은 트리(buftype nofile)에서는 아무 일도 하지 않았고,
-- 비교 창에서는 그 창의 파일을 다른 버퍼로 바꿔 비교를 깼다. 차례는 탭 번호 차례, 끝에서 처음으로 돈다.
-- 그 비교의 탭만 돈다 - 다른 탭(편집하던 탭, 다른 비교)으로는 gt / gT. 다룬 것이면 true (BufCycle 은
-- 그때 :bn! 을 하지 않는다), DirDiff 탭이 아니면 false
function _G.vimide_dirdiff_tab_cycle(dir)
  local cur = api.nvim_get_current_tabpage()
  local s
  for _, x in pairs(sessions) do
    if x.tab == cur or (x.views and x.views[cur]) then
      s = x
      break
    end
  end
  if not s then
    return false
  end
  local tabs = {}
  if api.nvim_tabpage_is_valid(s.tab) then
    tabs[#tabs + 1] = s.tab
  end
  for t in pairs(s.views or {}) do
    if t ~= s.tab and api.nvim_tabpage_is_valid(t) then
      tabs[#tabs + 1] = t
    end
  end
  if #tabs < 2 then
    -- pair_tab = 0 이거나 아직 짝을 열지 않았다. :bn! 으로 넘기면 편집 창(비교 창)의 파일이 바뀌므로 막는다
    say('이 비교의 탭은 하나뿐입니다 (<CR> 로 짝을 열면 비교 탭이 생긴다, 다른 탭은 gt)')
    return true
  end
  table.sort(tabs, function(a, b)
    return api.nvim_tabpage_get_number(a) < api.nvim_tabpage_get_number(b)
  end)
  local idx = 1
  for i, t in ipairs(tabs) do
    if t == cur then
      idx = i
      break
    end
  end
  idx = (idx - 1 + (dir < 0 and -1 or 1)) % #tabs + 1
  api.nvim_set_current_tabpage(tabs[idx])
  return true
end

function _G.vimide_dirdiff_take_over()
  if (tonumber(vim.g.vimide_dirdiff_copy_keys) or 1) ~= 0 then
    take_over()
  end
  take_over_view_keys()
end
_G.vimide_dirdiff_take_over()

-- ---------------------------------------------------------------------------
-- 보기 (f: 메뉴, F: 모두 <-> 차이) - Beyond Compare 의 보기 거르기
-- ---------------------------------------------------------------------------

local function set_mode(s, id)
  if not MODE[id] or s.mode == id then
    return
  end
  s.mode = id
  render(s)
end

-- 처음 보기: g:vimide_dirdiff_filter (MODES 의 id), 없으면 g:vimide_dirdiff_only_diff.
-- g:vimide_dirdiff_view 에 싣지 않은 것은 그 이름이 이미 ':DirDiff 를 이 트리로' (0/1) 라서다 -
-- dirdifftab.vim 의 get(g:, 'vimide_dirdiff_view', 1) 은 'diff' 같은 글자를 0 으로 읽어
-- :DirDiff 가 예전 목록이 된다
local function start_mode()
  local v = vim.g.vimide_dirdiff_filter
  if type(v) == 'string' and v ~= '' then
    if MODE[v] then
      return v
    end
    local ids = {}
    for _, md in ipairs(MODES) do
      ids[#ids + 1] = md.id
    end
    say(('g:vimide_dirdiff_filter 를 모릅니다: %s (%s)'):format(v, table.concat(ids, ' ')), vim.log.levels.WARN)
  end
  return (tonumber(vim.g.vimide_dirdiff_only_diff) or 0) ~= 0 and 'diff' or 'all'
end

-- 보기마다 항목 수: 뒤쪽의 cats (표시 -> 수). 한쪽에만 있는 디렉터리는 하나로 센다 (상태줄처럼).
-- 견주는 중인 것은 '모두' 에만 든다
local function mode_count(s, md)
  local cats = s.prog and s.prog.cats
  if type(cats) ~= 'table' then
    return nil
  end
  local n = 0
  for k, v in pairs(cats) do
    local m = tonumber(k)
    if m and type(v) == 'number' and (not md.bits or band(m, md.bits) ~= 0) then
      n = n + v
    end
  end
  return n
end

menu_fill = function(s)
  local mu = s.menu
  if not (mu and api.nvim_buf_is_valid(mu.buf) and api.nvim_win_is_valid(mu.win)) then
    s.menu = nil
    return
  end
  local cnt, lw, cw = {}, 0, 0
  for i, md in ipairs(MODES) do
    local c = mode_count(s, md)
    cnt[i] = c and commas(c) or ''
    lw = math.max(lw, vim.fn.strdisplaywidth(md.label))
    cw = math.max(cw, #cnt[i])
  end
  local dot = ascii() and '*' or '●'
  local lines, width = {}, 0
  for i, md in ipairs(MODES) do
    lines[i] = (' %s %s  %s '):format(md.id == s.mode and dot or ' ', fit(md.label, lw), rjust(cnt[i], cw))
    width = math.max(width, vim.fn.strdisplaywidth(lines[i]))
  end
  vim.bo[mu.buf].modifiable = true
  api.nvim_buf_set_lines(mu.buf, 0, -1, false, lines)
  vim.bo[mu.buf].modifiable = false
  api.nvim_buf_clear_namespace(mu.buf, ns, 0, -1)
  for i, md in ipairs(MODES) do
    local l = lines[i]
    local c1 = #l - 1
    if cnt[i] ~= '' then
      pcall(api.nvim_buf_set_extmark, mu.buf, ns, i - 1, c1 - #cnt[i],
        { end_col = c1, hl_group = cnt[i] == '0' and 'Comment' or 'VimIdeDirDiffSize' })
    end
    if md.id == s.mode then
      pcall(api.nvim_buf_set_extmark, mu.buf, ns, i - 1, 1, { end_col = c1 - #cnt[i], hl_group = 'VimIdeDirDiffMenuNow' })
    end
  end
  local pend = s.prog and tonumber(s.prog.pend) or 0
  local title = pend > 0 and (' 보기 · 확인 중 %s '):format(commas(pend)) or ' 보기 '
  width = math.max(width, vim.fn.strdisplaywidth(title) + 2, vim.fn.strdisplaywidth(mu.footer) + 2)
  pcall(api.nvim_win_set_config, mu.win, { title = title, title_pos = 'center', width = width })
end

local function open_menu(s)
  if s.menu and api.nvim_win_is_valid(s.menu.win) then
    return api.nvim_set_current_win(s.menu.win)
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  -- 이름·filetype 이 없으면 단축키 도움말(F1)이 이 창을 '이 창 · ' 으로만 불렀다
  vim.bo[buf].filetype = 'vimidedirdiffmenu'
  pcall(api.nvim_buf_set_name, buf, 'DirDiff 보기 #' .. buf)
  local footer = ' Enter 고르기 · q 닫기 '
  local h = #MODES
  local border = ascii() and { '+', '-', '+', '|', '+', '-', '+', '|' } or 'rounded'
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor', row = 0, col = 0, width = 30, height = h, style = 'minimal', border = border,
    title = ' 보기 ', title_pos = 'center', footer = footer, footer_pos = 'center', zindex = 60,
  })
  vim.wo[win].cursorline = true
  s.menu = { buf = buf, win = win, footer = footer }
  menu_fill(s)
  -- 트리 창 위, 가운데. 트리가 낮아도 화면 안에 들게
  local tp = api.nvim_win_get_position(s.win_l)
  local tw = api.nvim_win_get_width(s.win_l)
  local width = api.nvim_win_get_width(win)
  local row = math.max(0, math.min(tp[1] + 1, vim.o.lines - vim.o.cmdheight - h - 3))
  local col = tp[2] + math.max(0, math.floor((tw - width - 2) / 2))
  pcall(api.nvim_win_set_config, win, { relative = 'editor', row = row, col = col })
  pcall(api.nvim_win_set_cursor, win, { MODE[s.mode].i, 1 })
  local function close(back)
    if not (s.menu and s.menu.buf == buf) then
      return
    end
    s.menu = nil
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
    if back and api.nvim_win_is_valid(s.win_l) then
      pcall(api.nvim_set_current_win, s.win_l)
    end
  end
  local function choose()
    local md = MODES[api.nvim_win_get_cursor(win)[1]]
    close(true)
    if md then
      set_mode(s, md.id)
    end
  end
  -- desc 가 없으면 단축키 도움말(F1)에 '(Lua 함수)' 로만 보였다
  local function o(desc)
    return { buffer = buf, nowait = true, silent = true, desc = desc }
  end
  for _, k in ipairs({ '<CR>', '<2-LeftMouse>', '<Space>' }) do
    vim.keymap.set('n', k, choose, o('이 보기로 (보기 메뉴)'))
  end
  for _, k in ipairs({ 'q', '<Esc>', 'f' }) do
    vim.keymap.set('n', k, function()
      close(true)
    end, o('보기 메뉴 닫기'))
  end
  -- F1(단축키 도움말)은 메뉴를 닫고 트리에서 연다: 메뉴에서 그대로 열었더니 목록이 뜨며 메뉴가 닫혀
  -- (아래 WinLeave) 도움말을 닫은 뒤 커서가 돌아갈 창이 없어 트리가 아니라 편집 창 A 로 갔다.
  -- VimIdeKeyHelp(.vimrc 의 F1)가 없으면 걸지 않는다 - 전역 F1 그대로
  if vim.fn.exists('*VimIdeKeyHelp') == 1 then
    vim.keymap.set('n', '<F1>', function()
      close(true)
      vim.fn.VimIdeKeyHelp()
    end, o('단축키 도움말 (보기 메뉴를 닫고 트리에서)'))
  end
  -- 다른 창을 누르는 등으로 떠나면 닫는다 (메뉴 밖으로 간 것이니 트리로 끌고 오지 않는다)
  api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        close(false)
      end)
    end,
  })
end

local HELP_PAIR = {
  '비교 창 (비교 탭의 두 창, pair_tab = 0 이면 트리 위의 편집 창 둘)',
  '  개요 막대(맨 왼쪽)를 누르면 그 자리로. 맨 아래 두 줄은 커서 줄과 맞은편 줄 (빈칸 · 탭 → 줄 끝 ¶)',
  '  <C-w>w <C-w>W 다음 / 앞 창 (개요 막대·줄 자세히는 건너뛴다 - A·B 를 오간다)',
  '  \\d          보기 고르기: 모두 보이기(기본) / 차이 보이기 / 문맥 보이기 (Enter 고르기, 1 2 3)',
  '               - 접기는 diff 의 것이라 zR 모두 열기, zM 모두 접기, zo zc 도 두 창에 같이',
  '  q           비교 탭 닫기 - 트리의 그 줄로 (:tabclose 도 같다. 편집 창 둘에서는 예전대로 매크로)',
  '  <C-n> <C-p> = ]c [c (다음 / 앞 차이)',
  '  <C-r> <C-l> 커서가 있는 차이 덩어리째 오른쪽(B) / 왼쪽(A) 으로 (저장은 :w - 트리 판정도 다시)',
  '  <C-S-r> <C-S-l> 커서 줄만 (Ctrl+Shift 가 안 오는 터미널·tmux 3.2 미만 서버에서는 1<C-r> 1<C-l>)',
  '                - 바뀌지 않은 줄이면 바로 위(먼저)·아래에 끼인 저쪽 줄 덩어리째',
  '  N<C-r> N<C-l> 커서 줄부터 N 줄, 비주얼은 고른 줄만',
}

-- 옛 tmux 서버 안이면 지금 Ctrl+Shift 가 안 온다는 줄을 붙인다
local function help_pair()
  local old = tmux_old()
  if not old then
    return HELP_PAIR
  end
  return vim.list_extend(vim.list_extend({}, HELP_PAIR), {
    ('  ! 지금 tmux 서버(%s)는 Ctrl+Shift 를 넘기지 못해 <C-S-r> <C-S-l> 이 <C-r> <C-l> 로 온다'):format(old),
    '    - 커서 줄만은 1<C-r> 1<C-l>. tmux 3.2 이상 서버(extended-keys on)에서는 그대로 된다',
  })
end

local function help()
  local lines = {
    'DirDiff 트리',
    '  <CR>        파일: 비교 탭을 열고(열려 있으면 그 탭으로) 첫 차이로 / 디렉터리: 펼치기·접기',
    '  o           비교 탭을 뒤에서 열고(열려 있으면 다시 읽고) 트리에 그대로 - gt 로 돌아본다',
    '              (pair_tab = 0 이면 둘 다 트리 위의 편집 창 둘에 - o 는 열기만)',
    '  <C-n> <C-p> 다음 / 앞 차이 파일 (모두·차이 밖의 보기: 그 보기가 보이는 것 - 동일이면 같은 파일)',
    '  l h         펼치기 / 접기(부모로)',
    '  O X         차이 있는 디렉터리 모두 펼치기 (다른 보기: 그 보기가 보이는 것이 있는 디렉터리) / 모두 접기',
    '  f           보기 고르기 (모두 / 차이 / 고아 없음 / 좌측 최신 / 우측 고아 / 동일 ...)',
    '  F           모두 보이기 <-> 차이 보이기',
    '  R           다시 훑기      q  끝내기 (비교 탭들도 닫는다)',
    '  ,r ,e       이 비교의 다음 / 앞 탭 (트리 탭과 비교 탭들 사이를 돈다 - 비교 창에서도)',
    '  <Tab>       비교할 곳 고르기: 지금 쪽 항목을 [A] 로, 다음 Tab 의 것을 [B] 로 - 새 탭에서 비교',
    '              ([A] 줄에서 다시 Tab 은 취소. neo-tree 의 Tab 과 같은 [A])',
    '  <S-Tab>     A 쪽 / B 쪽 오가기     <Space> 그쪽 항목 고르기    U 고른 것 모두 풀기',
    '  <C-r> <C-l> 고른 것(또는 비주얼 줄, 커서 줄)을 A→B / B→A 로 복사 (묻고 나서)',
  }
  vim.list_extend(lines, help_pair())
  vim.notify(table.concat(lines, '\n'))
end

-- 비교 탭 하나를 놓는다: 목록에서 빼고, 그 탭의 빈·알림 버퍼를 지우고, 이 비교가 연 버퍼 중 어디에도
-- 안 보이는 것을 치운다 (고친 것은 남기고 알린다 - 끝낼 때의 finish 처럼). back: 트리의 그 줄로
local function release_view(v, back)
  local s = v.s
  v.closed = true
  s.views[v.tab] = nil
  cmp.clear(v)   -- 버퍼에 남은 화살표·연보라 빈 줄 (탭째 닫혀 창이 없을 때)
  if api.nvim_tabpage_is_valid(v.tab) then
    -- 탭이 남았으면(:tabonly 로 트리 탭이 닫혔다) 보통 탭으로 - 곁창 지킴이도 다시 본다. 곁 창은 닫는다
    cmp.detach(v)
    pcall(api.nvim_tabpage_del_var, v.tab, 'vimide_dirdiff_pair')
    pcall(api.nvim_tabpage_del_var, v.tab, 'title')
  end
  for _, b in ipairs({ v.empty_a or false, v.empty_b or false }) do
    if b and api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 0 then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
  local kept = {}
  for _, b in ipairs({ v.buf_a or false, v.buf_b or false }) do
    if b and s.opened[b] and api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 0
        and vim.fn.getbufvar(b, '&modified') == 1 then
      kept[#kept + 1] = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ':~:.')
    end
  end
  sweep(s)
  if #kept > 0 then
    say('고친 채 남겨 둔 버퍼: ' .. table.concat(kept, ', '), vim.log.levels.WARN)
  end
  if s.done then
    return
  end
  mark_open(s)
  if back and api.nvim_tabpage_is_valid(s.tab) then
    api.nvim_set_current_tabpage(s.tab)
    if api.nvim_win_is_valid(s.win_l) then
      api.nvim_set_current_win(s.win_l)
      local i = v.rel and s.row_of[v.rel]
      if i then
        goto_row(s, i)
        mark_side(s)
      end
    end
  end
  dip_sync()
end

-- 비교 탭을 닫는다 (그 탭의 q, 트리를 끝낼 때). 먼저 목록에서 빼서 TabClosed·WinClosed 가 다시
-- 치우지 않게 하고, 두 창의 흔적(diff·머리·winhighlight)을 걷은 뒤 닫는다. 탭이 하나뿐일 수는 없다
-- (트리 탭이 있다) - 그래도 마지막이면 닫지 않는다
local function close_view(v, back)
  if v.closed then
    return
  end
  v.closed = true
  v.s.views[v.tab] = nil
  for _, w in ipairs({ v.win_a, v.win_b }) do
    unview_win(w)
  end
  if api.nvim_tabpage_is_valid(v.tab) and #api.nvim_list_tabpages() > 1 then
    pcall(vim.cmd, 'tabclose ' .. api.nvim_tabpage_get_number(v.tab))
  end
  release_view(v, back)
end

function _G.vimide_dirdiff_pair_quit()
  local v = view_of_win(api.nvim_get_current_win())
  if v and not v.inline then
    close_view(v, true)
  end
end

-- 비교 창의 보기 메뉴 (\d): 트리의 f 메뉴처럼 작은 창 - 지금 보기에 ●, Enter·더블클릭·Space 로 고르기,
-- 1 2 3 은 바로, q·Esc·\d 닫기, ? 도움말. 그 비교 창 가운데에 뜬다
local function set_fmode(v, id)
  v.fmode = id   -- 이 짝만. 다음에 여는 짝은 처음 보기(s.fmode)로 시작한다
  apply_fmode(v)
end

local function open_fmenu(v)
  if v.menu and api.nvim_win_is_valid(v.menu.win) then
    return api.nvim_set_current_win(v.menu.win)
  end
  if not v.rel then
    return say('트리에서 파일을 먼저 고르세요')
  end
  if v.bin then
    return say('바이너리·큰 파일은 줄로 비교하지 않아 보기가 없습니다')
  end
  local from = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  -- 이름·filetype: 단축키 도움말(F1)이 이 창을 이름으로 부른다 (keyhelp.lua 의 WIN_NAME)
  vim.bo[buf].filetype = 'vimidedirdifffile'
  pcall(api.nvim_buf_set_name, buf, 'DirDiff 비교 보기 #' .. buf)
  local dot = ascii() and '*' or '●'
  local lines, width = {}, 0
  for i, md in ipairs(FMODES) do
    lines[i] = (' %s %d  %s '):format(md.id == v.fmode and dot or ' ', i, fmode_label(md.id))
    width = math.max(width, vim.fn.strdisplaywidth(lines[i]))
  end
  local footer = ' Enter 고르기 · q 닫기 · ? 도움말 '
  width = math.max(width, vim.fn.strdisplaywidth(footer) + 2)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for i, md in ipairs(FMODES) do
    if md.id == v.fmode then
      pcall(api.nvim_buf_set_extmark, buf, ns, i - 1, 1, { end_col = #lines[i] - 1, hl_group = 'VimIdeDirDiffMenuNow' })
    end
  end
  local h = #lines
  local fw, fh = api.nvim_win_get_width(from), api.nvim_win_get_height(from)
  local border = ascii() and { '+', '-', '+', '|', '+', '-', '+', '|' } or 'rounded'
  local win = api.nvim_open_win(buf, true, {
    relative = 'win', win = from, row = math.max(0, math.floor((fh - h) / 2) - 1),
    col = math.max(0, math.floor((fw - width) / 2)), width = width, height = h, style = 'minimal',
    border = border, title = ' 보기 ', title_pos = 'center', footer = footer, footer_pos = 'center', zindex = 60,
  })
  vim.wo[win].cursorline = true
  v.menu = { buf = buf, win = win }
  pcall(api.nvim_win_set_cursor, win, { FMODE[v.fmode].i, 1 })
  local function close(back)
    if not (v.menu and v.menu.buf == buf) then
      return
    end
    v.menu = nil
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
    if back and api.nvim_win_is_valid(from) then
      pcall(api.nvim_set_current_win, from)
    end
  end
  local function choose(i)
    local md = FMODES[i or api.nvim_win_get_cursor(win)[1]]
    close(true)
    if md and not v.closed then
      set_fmode(v, md.id)
    end
  end
  local function o(desc)
    return { buffer = buf, nowait = true, silent = true, desc = desc }
  end
  for _, k in ipairs({ '<CR>', '<2-LeftMouse>', '<Space>' }) do
    vim.keymap.set('n', k, function()
      choose()
    end, o('이 보기로 (비교 보기 메뉴)'))
  end
  for i in ipairs(FMODES) do
    vim.keymap.set('n', tostring(i), function()
      choose(i)
    end, o(fmode_label(FMODES[i].id) .. ' (비교 보기 메뉴)'))
  end
  for _, k in ipairs({ 'q', '<Esc>', '<leader>d' }) do
    vim.keymap.set('n', k, function()
      close(true)
    end, o('비교 보기 메뉴 닫기'))
  end
  vim.keymap.set('n', '?', function()
    close(true)
    vim.notify(table.concat(help_pair(), '\n'))
  end, o('비교 창의 키 (도움말)'))
  -- F1: 메뉴를 닫고 비교 창에서 연다 (트리의 f 메뉴와 같은 까닭 - 떠난 창이 없어져 엉뚱한 창으로 갔다)
  if vim.fn.exists('*VimIdeKeyHelp') == 1 then
    vim.keymap.set('n', '<F1>', function()
      close(true)
      vim.fn.VimIdeKeyHelp()
    end, o('단축키 도움말 (비교 보기 메뉴를 닫고 비교 창에서)'))
  end
  api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        close(false)
      end)
    end,
  })
end

function _G.vimide_dirdiff_file_menu()
  local v = view_of_win(api.nvim_get_current_win())
  if v then
    open_fmenu(v)
  end
end

-- ---------------------------------------------------------------------------
-- 열기 / 끝내기
-- ---------------------------------------------------------------------------

-- stay: 다른 탭에서 이 비교 탭을 닫았다 - 사용자가 있던 탭에 그대로 둔다
local function finish(s, stay)
  if s.done then
    return
  end
  s.done = true
  s.closing = true
  if s.job and s.job > 0 then
    send(s, { cmd = 'quit' })
    pcall(vim.fn.jobstop, s.job)
  end
  -- :tabclose·:qa 는 q 와 달리 기다리지 않는다 - 뒤쪽이 쓰던 임시 파일을 지우고 멈춘다
  if s.copying and vim.v.exiting == vim.NIL then
    local c = s.copying
    say(('%s → %s 복사를 멈췄습니다 - 다 쓴 것만 %s 쪽에 남았습니다'):format(c.from:upper(), c.to:upper(),
      c.to:upper()), vim.log.levels.WARN)
  end
  local here = api.nvim_get_current_tabpage()
  -- 비교 탭들도 닫는다 (트리를 끝내면 그 짝들도 끝난다). 고친 버퍼는 아래에서 한꺼번에 알린다
  for _, v in ipairs(vim.tbl_values(s.views)) do
    v.closed = true
    s.views[v.tab] = nil
    for _, w in ipairs({ v.win_a, v.win_b }) do
      unview_win(w)
    end
    cmp.clear(v)
    if api.nvim_tabpage_is_valid(v.tab) and #api.nvim_list_tabpages() > 1 then
      pcall(vim.cmd, 'tabclose ' .. api.nvim_tabpage_get_number(v.tab))
    end
    if api.nvim_tabpage_is_valid(v.tab) then
      -- 마지막 탭이라 남았다 (:tabonly, 트리 탭을 먼저 닫았다): 보통 탭으로 - 곁 창도 닫는다
      cmp.detach(v)
      pcall(api.nvim_tabpage_del_var, v.tab, 'vimide_dirdiff_pair')
      pcall(api.nvim_tabpage_del_var, v.tab, 'title')
    end
    for _, b in ipairs({ v.empty_a or false, v.empty_b or false }) do
      if b and api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 0 then
        pcall(api.nvim_buf_delete, b, { force = true })
      end
    end
  end
  sessions[s.tab] = nil
  local m = s.main
  if api.nvim_tabpage_is_valid(s.tab) then
    api.nvim_set_current_tabpage(s.tab)
    local was = {}
    for _, w in ipairs(m and { m.win_a, m.win_b } or {}) do
      was[w] = api.nvim_win_is_valid(w) and vim.wo[w].diff
    end
    pcall(vim.cmd, 'diffoff!')
    -- 남는 버퍼(사용자 것, 고친 것)에 창 머리·비교 색·diff 접기가 적혀 남지 않게 (open_pair 의 winbar 와
    -- 같은 까닭, undiff_folds)
    for _, w in ipairs(m and { m.win_a, m.win_b } or {}) do
      if api.nvim_win_is_valid(w) then
        set_wo(w, 'winbar', '')
        diff_whl(w, nil)
        if was[w] then
          pcall(api.nvim_win_call, w, function()
            undiff_folds()
            pcall(vim.cmd, 'setlocal foldlevel<')
          end)
        end
      end
    end
    if m then
      cmp.clear(m)
    end
    if #api.nvim_list_tabpages() > 1 then
      pcall(vim.cmd, 'tabclose')
    else
      -- 마지막 탭: 창 하나를 새 빈 버퍼로. 트리 창(트리를 :q 로 닫았으면 경로 줄 창)을 물려 쓰게 되므로 그
      -- 옵션을 걷는다 - winfixbuf 는 먼저 (그대로면 enew 가 E1513 으로 거절되어 경로 줄 버퍼가 남았다)
      set_wo(api.nvim_get_current_win(), 'winfixbuf', false)
      pcall(vim.cmd, 'silent! only | enew')
      plain_window(api.nvim_get_current_win())
      pcall(api.nvim_tabpage_del_var, s.tab, 'title')
    end
  end
  if stay and api.nvim_tabpage_is_valid(here) then
    api.nvim_set_current_tabpage(here)
  elseif s.origin and api.nvim_tabpage_is_valid(s.origin) then
    api.nvim_set_current_tabpage(s.origin)
  end
  local kept = {}
  for b in pairs(s.opened) do
    if api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 0 then
      if vim.fn.getbufvar(b, '&modified') == 1 then
        kept[#kept + 1] = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ':~:.')
      else
        pcall(api.nvim_buf_delete, b, { force = false })
      end
    end
  end
  for b in pairs(s.unload) do
    if unused(b) then
      pcall(api.nvim_buf_delete, b, { unload = true })
    end
  end
  for _, b in ipairs({ s.buf_l, s.hbuf or false, m and m.empty_a or false, m and m.empty_b or false }) do
    if b and api.nvim_buf_is_valid(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
  if #kept > 0 then
    say('고친 채 남겨 둔 버퍼: ' .. table.concat(kept, ', '), vim.log.levels.WARN)
  end
  dip_sync()
end

local function restart(s)
  -- q 처럼 복사가 끝나기를 기다린다. 뒤쪽을 바꾸면 하던 복사가 중간에 끊기고(대상에 반쯤 쓴
  -- 디렉터리가 남았다), 그 'copied' 는 새 뒤쪽에서 오지 않아 q 와 복사가 끝내 거절되었다
  if s.copying then
    return say('복사하는 중입니다 - 끝난 뒤에 R', vim.log.levels.WARN)
  end
  if s.job and s.job > 0 then
    local old = s.job
    s.job = nil
    pcall(vim.fn.chansend, old, vim.json.encode({ cmd = 'quit' }) .. '\n')
    pcall(vim.fn.jobstop, old)
  end
  local r = cur_row(s)
  s.want_rel = r and r.e and r.rel or nil   -- 커서가 있던 줄로 돌아간다 (그 줄이 다시 생기면)
  s.dirs, s.loading, s.dirty, s.prog, s.walk = {}, {}, {}, nil, nil
  if not start_job(s) then
    return
  end
  -- 맨 위만 청한다. 펼쳐 두었던 아래 디렉터리는 부모의 목록이 오면 on_event 가 청한다
  request_list(s, '')
  render(s)
end
restart_fn = restart

local function map_list(s)
  local b = s.buf_l
  local function m(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = b, nowait = true, silent = true, desc = desc })
  end
  m('<CR>', function() act_enter(s, true) end, '비교 탭 열기(있으면 그 탭으로) / 펼치기')
  m('<2-LeftMouse>', function() act_enter(s, true) end, '비교 열기')
  m('o', function() act_enter(s, false) end, '비교 탭을 뒤에서 열기·다시 읽기 (트리에 그대로)')
  m('<C-n>', function() act_step(s, 1) end, '다음 차이 (보기에 따라)')
  m('<C-p>', function() act_step(s, -1) end, '앞 차이 (보기에 따라)')
  m('l', function()
    local r = cur_row(s)
    if r and r.e and is_dir(r.e) then
      toggle(s, r, true)
    end
  end, '펼치기')
  m('h', function() act_h(s) end, '접기 / 부모로')
  m('O', function() act_expand_all(s) end, '차이 있는 디렉터리 모두 펼치기 (보기에 따라)')
  m('X', function() act_collapse_all(s) end, '모두 접기')
  m('f', function() open_menu(s) end, '보기 고르기')
  m('F', function() set_mode(s, s.mode == 'all' and 'diff' or 'all') end, '모두 보이기 / 차이 보이기')
  m('R', function() restart(s) end, '다시 훑기')
  m('<Tab>', function() act_pick(s) end, '비교할 곳 고르기 [A] -> [B]')
  -- 쪽 바꾸기는 Tab 에서 옮겨 왔다 (Tab 은 neo-tree 처럼 비교할 곳 고르기)
  m('<S-Tab>', function() act_side(s) end, 'A 쪽 / B 쪽')
  m('<Space>', function() act_mark(s) end, '고르기')
  -- <Esc> 로 두었더니 습관처럼 누르는 Esc 에 고른 것이 사라졌다
  m('U', function() clear_marks(s) end, '고른 것 모두 풀기')
  m('<C-r>', function() act_copy(s, 1) end, 'A → B 복사')
  m('<C-l>', function() act_copy(s, -1) end, 'B → A 복사')
  for _, spec in ipairs({ { '<C-r>', 1 }, { '<C-l>', -1 } }) do
    vim.keymap.set('x', spec[1], function()
      local l1, l2 = vim.fn.line('v'), vim.fn.line('.')
      vim.cmd('normal! \27')   -- feedkeys('<Esc>', 'x') 는 뒤에 쌓인 키를 비주얼 안에서 먼저 돌렸다
      act_copy(s, spec[2], l1, l2)
    end, { buffer = b, nowait = true, silent = true, desc = spec[2] > 0 and 'A → B 복사' or 'B → A 복사' })
  end
  api.nvim_create_autocmd('CursorMoved', {
    buffer = b,
    callback = function()
      local old = s.side
      cursor_side(s)
      mark_side(s)
      mark_open(s)
      if old ~= s.side then
        s.prog_dirty = true
        schedule_render(s)
      end
    end,
  })
  m('q', function()
    if s.copying then
      return say('복사하는 중입니다 - 끝난 뒤에 q', vim.log.levels.WARN)
    end
    finish(s)
  end, '끝내기')
  m('?', help, '도움말')
end

local function full_dir(d)
  -- 있는 경로는 그대로 ('P$x' 의 $x 를 환경 변수로 풀지 않게), 없으면 ~ · $VAR 를 풀어 본다
  if vim.fn.isdirectory(d) == 0 then
    d = vim.fn.expand(d, 1)
  end
  return (vim.fn.fnamemodify(d, ':p'):gsub('(.)/+$', '%1'))
end

-- 트리 창의 옵션. 창에만(local) - vim.wo 는 :set 처럼 그 창의 전역 값까지 바꾸어, 그 창에서 갈라
-- 만든 창과 끝낸 뒤 남은 창이 번호 없이 남았다. 지금 줄은 cursorline 을 끄고 커서가 있는 쪽 반 칸만
-- 연두로 칠한다 (mark_side - Beyond Compare 처럼 그쪽만 골라진다. 줄 전체를 칠했더니 어느 쪽을 고른
-- 것인지 밑줄로만 보였다).
-- colorcolumn(vim-ide 는 80)·statuscolumn 은 끈다 - 칸 제목(winbar·경로 줄 창의 상태줄)이 0 칸부터라
-- 줄 앞에 무엇이 붙으면 칸이 어긋난다
local function tree_opts(s)
  for k, v in pairs({ number = false, relativenumber = false, wrap = false, cursorline = false,
    winfixheight = not s.pair_tab, signcolumn = 'no', foldcolumn = '0', list = false, spell = false,
    colorcolumn = '', statuscolumn = '', winhighlight = '' }) do
    pcall(api.nvim_set_option_value, k, v, { scope = 'local', win = s.win_l })
  end
end

-- 트리 창 (탭 맨 아래, 전체 너비 - pair_tab 이면 탭 전체)
local function open_tree_win(s)
  s.win_l = api.nvim_open_win(s.buf_l, true, { split = 'below', win = -1, height = not s.pair_tab and s.list_h or nil })
  tree_opts(s)
end

function M.open(a, b)
  a, b = full_dir(a), full_dir(b)
  -- 링크를 푼 진짜 경로로: nvim 은 버퍼 이름의 디렉터리 쪽 링크를 풀어서 붙이므로, 그대로
  -- 두면 사용자 버퍼를 못 알아보고(우리 것으로 알고 지웠다) 저장 안 한 버퍼 검사도 비껴갔다
  a, b = uv.fs_realpath(a) or a, uv.fs_realpath(b) or b
  for _, d in ipairs({ a, b }) do
    if vim.fn.isdirectory(d) == 0 then
      return say('디렉터리가 아닙니다: ' .. d, vim.log.levels.WARN)
    end
  end
  if vim.fn.resolve(a) == vim.fn.resolve(b) then
    return say('같은 디렉터리입니다: ' .. vim.fn.fnamemodify(a, ':~'), vim.log.levels.WARN)
  end
  -- 같은 두 디렉터리를 이미 비교하고 있으면 그 탭으로 (새로 훑지 않는다 - 다시 훑기는 R)
  for tab, o in pairs(sessions) do
    if o.a == a and o.b == b and api.nvim_tabpage_is_valid(tab) then
      api.nvim_set_current_tabpage(tab)
      if not api.nvim_win_is_valid(o.win_l) and api.nvim_buf_is_valid(o.buf_l) then
        open_tree_win(o)   -- 트리 창을 닫아 버렸으면 (키는 모두 트리에 있다) 다시 연다
        render(o)
      end
      if api.nvim_win_is_valid(o.win_l) then
        api.nvim_set_current_win(o.win_l)
      end
      return say('이미 비교 중입니다 - 이 탭입니다 (다시 훑기는 R, 끝내기는 q)')
    end
  end
  if vim.fn.executable('python3') ~= 1 then
    return say('python3 이 없습니다 - :DirDiffClassic 을 쓰세요', vim.log.levels.WARN)
  end
  -- 색 다시 보기: g:vimide_dirdiff_colors 를 바꿨거나 Neogit 이 늦게 setup 되었으면 이 비교부터
  set_hl()
  local s = {
    a = a, b = b, req = 0, dirs = {}, loading = {}, dirty = {},
    expanded = { [''] = true }, rows = {}, row_of = {}, opened = {}, unload = {},
    side = 'a', marks = { a = {}, b = {} }, offb = {}, offg = {},
    mode = start_mode(), reveal_step = 1,
    origin = api.nvim_get_current_tabpage(),
    -- 짝을 보일 곳: 비교 탭들(views) 또는 위의 편집 창 둘(main). 비교 중에 옵션을 바꿔도 이 비교는 그대로
    views = {}, pair_tab = pair_tab_on(), fmode = start_fmode(),
  }
  -- 곁창에서 :tabnew 하면 그 창 옵션을 물려받고 neo-tree 가 가져간다 - EDIT 창에서
  local back = api.nvim_get_current_win()
  local w = _G.vimide_edit_slot and _G.vimide_edit_slot()
  if w and w ~= 0 and api.nvim_win_is_valid(w) then
    api.nvim_set_current_win(w)
  end
  vim.cmd('tabnew')
  -- 떠난 곳이 비교 탭이면 그 탭의 지금 창은 도로 그 창으로: EDIT 창(편집 창 A)으로 옮긴 채 두었더니, 비교
  -- 탭의 트리에서 :DirDiff 로 연 비교를 q 로 닫거나 gT 로 돌아가면 커서가 트리가 아니라 편집 창 A 에 있었다
  if sessions[s.origin] and back ~= w and api.nvim_win_is_valid(back)
      and api.nvim_win_get_tabpage(back) == s.origin then
    pcall(api.nvim_tabpage_set_win, s.origin, back)
  end
  s.tab = api.nvim_get_current_tabpage()
  local nb = api.nvim_get_current_buf()
  s.buf_l = api.nvim_create_buf(false, true)
  vim.bo[s.buf_l].bufhidden = 'hide'
  -- airline 이 창을 옮길 때마다 상태줄을 제 것으로 바꿔 진행·합계가 사라졌다
  vim.b[s.buf_l].airline_disable_statusline = 1
  vim.bo[s.buf_l].filetype = 'vimidedirdiff'
  api.nvim_buf_set_name(s.buf_l, 'DirDiff ' .. vim.fn.fnamemodify(a, ':t') .. ' <> ' .. vim.fn.fnamemodify(b, ':t') .. ' #' .. s.buf_l)
  if s.pair_tab then
    -- 트리만 (탭 전체). 짝은 비교 탭에서 본다 (open_pair)
    s.win_l = api.nvim_get_current_win()
    plain_window(s.win_l)
    api.nvim_win_set_buf(s.win_l, s.buf_l)
    tree_opts(s)
    drop_noname(nb)
  else
    local v = { s = s, tab = s.tab, inline = true, fmode = s.fmode }
    s.main = v
    v.win_a = api.nvim_get_current_win()
    plain_window(v.win_a)
    api.nvim_win_set_buf(v.win_a, scratch(v, 'a', { '', '  아래 트리에서 파일을 고르고 Enter  (? 도움말)' }))
    drop_noname(nb)
    vim.cmd('rightbelow vsplit')
    v.win_b = api.nvim_get_current_win()
    api.nvim_win_set_buf(v.win_b, scratch(v, 'b', { '' }))
    s.list_h = tonumber(vim.g.vimide_dirdiff_list_height) or math.max(10, math.floor(vim.o.lines * 0.4))
    open_tree_win(s)
  end
  vim.t.vimide_dirdiff_view = true
  -- 탭 이름: airline 의 탭 줄은 탭에 목록 버퍼가 없으면 첫 창의 버퍼 이름을 쓰는데, 첫 창이 이제 경로 줄
  -- 창이다 ('DirDiff 경로' 가 떴다). 그 탭 줄이 먼저 보는 t:title 에 트리의 이름을 둔다
  vim.t.title = 'DirDiff ' .. vim.fn.fnamemodify(a, ':t') .. ' <> ' .. vim.fn.fnamemodify(b, ':t')
  sessions[s.tab] = s
  map_list(s)
  if not start_job(s) then
    finish(s)
    return
  end
  request_list(s, '')
  render(s)
end

-- ---------------------------------------------------------------------------
-- 비교 탭의 곁 (Beyond Compare 의 글 비교): 개요 막대, 줄 자세히, 노란 화살표, 연보라 빈 줄
-- ---------------------------------------------------------------------------
-- 곁 창은 그 비교 탭에만 있는 nofile 창이다 (filetype 이 cmp.FT). 들어가지 않는다: <C-w>w·<C-w>W 는 건너뛰고
-- (_G.vimide_dirdiff_cycle), 그래도 들어가면(<C-w>h <C-w>j, 마우스) 비교 창으로 돌려보낸다 (cmp.bounce -
-- 개요 막대를 눌렀으면 그 자리로, 키보드로 개요 막대에 왔으면 A 로). 파일이 열리지 않게 winfixbuf, 곁창
-- 지킴이는 이 탭을 남의 것으로 본다 (t:vimide_dirdiff_pair). 크기는 지킨다 (cmp.keep_size). 비교 창 둘이 다
-- 닫히면 곁 창도 닫는다 (cmp.orphans) - 탭이 닫혀 TabClosed 가 짝을 놓는다. 짝을 놓았는데 탭이 남으면
-- (:tabonly) 곁 창도 닫는다 (cmp.detach), 알림(바이너리·큰 파일)에는 곁 창이 없다. vim-ide 의 overview 막대는
-- 개요 막대가 있는 비교 창에 띄우지 않는다 (w:overview_off). pair_tab = 0 의 편집 창 둘에는 곁 창 없이
-- 화살표·연보라만 단다.
-- 그리는 것은 모두 v.dd (cmp.compute) 에서: 버퍼 글을 vim.diff 로 한 번 견준 덩어리 목록이다 - vim 의
-- diff 를 줄마다 묻는 diff_hlID·diff_filler 는 부를 때마다 조각 목록을 처음부터 찾아서 줄 수 x 조각 수가
-- 걸린다. 'diffopt' 의 알고리즘·무시·linematch 를 그대로 넘겨 화면과 같은 덩어리가 나온다. 다시 세는 것은
-- 짝을 채울 때, 글이 바뀔 때(TextChanged), DiffUpdated, 창 크기가 바뀔 때만 (마지막 부름에서 120ms 쉰 뒤),
-- 커서·화면이 움직이면 화살표·줄 자세히·보이는 곳만 (20ms 뒤) - cmp.kick

cmp.FT = { vimidedirdiffhead = true, vimidedirdiffover = true, vimidedirdiffline = true }

-- 끼인 줄의 빗금 (bc): 그 창의 전역 fillchars 에서 diff·eob 만 바꿔 창에만 단다 - 창에만 단 fillchars 는
-- 전역 값을 통째로 덮으므로 (다른 항목이 기본값으로 돌아가지 않게 전역 값에서 시작한다). 파일 끝 아래는
-- ~ 없이 비운다 (Beyond Compare 처럼 - 그 자리 줄 맨 앞 한 칸의 표시는 빗금처럼 보이지 않았다).
-- ASCII 는 '/' (╱ 는 East Asian Ambiguous)
function cmp.fillchars()
  local parts = {}
  for item in (vim.go.fillchars or ''):gmatch('[^,]+') do
    if not item:match('^diff:') and not item:match('^eob:') then
      parts[#parts + 1] = item
    end
  end
  parts[#parts + 1] = 'diff:' .. (ascii() and '/' or '╱')
  parts[#parts + 1] = 'eob: '
  return table.concat(parts, ',')
end

-- 그쪽 창이 짝의 버퍼를 보이고 있으면 그 버퍼 (아니면 nil): 비교 창에서 :e 로 다른 파일을 열었으면 화살표·
-- 연보라·줄 자세히는 그쪽을 짝으로 보지 않는다 - 그 파일에 노란 화살표가 달리고 줄 자세히가 그 파일의 줄을
-- 짝의 줄과 나란히 보였다. 짝의 버퍼로 돌아오면(<C-^>) 다시 (BufWinEnter 가 cmp.kick)
function cmp.pbuf(v, side)
  local w = v['win_' .. side]
  if not api.nvim_win_is_valid(w) then
    return nil
  end
  local b = api.nvim_win_get_buf(w)
  if b ~= v['buf_' .. side] then
    return nil
  end
  return b
end

-- 없는 쪽(한쪽에만 있는 파일의 빈 쪽)은 빗금뿐이게 (bc): 그 창의 줄 번호·지금 줄 색·colorcolumn 을 끈다 - 빗금 아래 홀로
-- 남은 빈 버퍼의 '1' 줄이 번호와 지금 줄 색을 달고 떴다 (Beyond Compare 의 빈 쪽에는 아무것도 없다). 창
-- 변수(w:vimide_dirdiff_gone)로 적어 두고 unview_win 이 되돌린다 (cmp.ungone)
function cmp.gone_side(v)
  for _, side in ipairs({ 'a', 'b' }) do
    local w = v['win_' .. side]
    if api.nvim_win_is_valid(w) and v.gone and v.gone[side] and not v.bin and pal() == 'bc' then
      for _, o in ipairs({ 'number', 'relativenumber', 'cursorline' }) do
        set_wo(w, o, false)
      end
      set_wo(w, 'colorcolumn', '')
      vim.w[w].vimide_dirdiff_gone = 1
    end
  end
end

function cmp.ungone(w)
  if vim.w[w].vimide_dirdiff_gone then
    vim.w[w].vimide_dirdiff_gone = nil
    pcall(api.nvim_win_call, w, function()
      vim.cmd('setlocal number< relativenumber< cursorline< colorcolumn<')
    end)
  end
end

-- 비교 창의 signcolumn: 화살표 자리로 늘 한 칸(있다 없다 하면 글자가 밀린다), 사용자의 것이 여러 칸(auto:2,
-- yes:2)이면 그만큼까지 - yes:1 로 못박았더니 gitsigns·진단의 sign 이 화살표(우선순위 200)에 가렸다
function cmp.signcol()
  local g = vim.go.signcolumn or ''
  local n = tonumber(g:match('^yes:(%d)$'))
  if n then
    return 'yes:' .. n
  end
  local hi = tonumber(g:match('^auto:%d%-(%d)$') or g:match('^auto:(%d)$'))
  if hi and hi > 1 then
    return 'auto:1-' .. hi
  end
  return 'yes:1'
end

-- 지금 비교 창 (A 또는 B): 지금 창이 그것이면 그것, 아니면 마지막으로 있던 것, 없으면 A
function cmp.cur(v)
  local w = api.nvim_get_current_win()
  if w == v.win_a or w == v.win_b then
    return w
  end
  if v.cur_win and (v.cur_win == v.win_a or v.cur_win == v.win_b) and api.nvim_win_is_valid(v.cur_win) then
    return v.cur_win
  end
  return api.nvim_win_is_valid(v.win_a) and v.win_a or v.win_b
end

-- 곁 창(경로 줄·개요 막대·줄 자세히)을 연다. focusable = false 는 쓰지 않는다: 0.12 에서도 나눈 창은 <C-w>w
-- 가 그대로 들어가고(창 번호만 없어진다), airline 의 탭 이름이 엉뚱한 창을 보았다 (실측). <C-w>w 는 그 탭에서
-- 곁 창을 건너뛰게 감싸고 (_G.vimide_dirdiff_cycle), 그래도 들어오면(<C-w>h <C-w>j, 마우스) 돌려보낸다 (cmp.bounce)
function cmp.open_extra(b, cfg)
  local ok, w = pcall(api.nvim_open_win, b, false, cfg)
  return ok and w or nil
end

-- 곁 창 하나 (kind: 이름, ft, 창 설정)
function cmp.extra(kind, ft, cfg)
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'wipe'
  vim.b[b].airline_disable_statusline = 1
  vim.bo[b].filetype = ft
  pcall(api.nvim_buf_set_name, b, ('DirDiff %s #%d'):format(kind, b))
  local w = cmp.open_extra(b, cfg)
  if not w then
    pcall(api.nvim_buf_delete, b, { force = true })
    return nil
  end
  tr.plain_extra(w)
  return { win = w, buf = b }
end

function cmp.attach(v)
  if v.inline then
    return
  end
  if on(vim.g.vimide_dirdiff_overview, 1) then
    v.ov = cmp.extra('개요', 'vimidedirdiffover', { split = 'left', win = v.win_a, width = 3 })
    if v.ov then
      set_wo(v.ov.win, 'winfixwidth', true)
      -- 빈 winbar 한 줄: 막대의 칸이 비교 창의 글 줄과 같은 높이에 서게 (비교 창에는 창 머리가 있다)
      set_wo(v.ov.win, 'winbar', '%#VimIdeDirDiffBar# ')
      -- A 가 막대만큼 좁아졌다 - 두 창을 같은 너비로
      local tw = api.nvim_win_get_width(v.win_a) + api.nvim_win_get_width(v.win_b)
      pcall(api.nvim_win_set_width, v.win_a, math.floor(tw / 2))
    end
  end
  if on(vim.g.vimide_dirdiff_line_details, 1) then
    v.ld = cmp.extra('줄', 'vimidedirdiffline', { split = 'below', win = -1, height = 2 })
    if v.ld then
      set_wo(v.ld.win, 'winfixheight', true)
    end
  end
  cmp.own_overview(v)
end

-- 곁 창의 크기를 지킨다 (개요 막대 3 칸, 줄 자세히 2 줄): winfixwidth 가 있어도 왼쪽 곁창(neo-tree·Tagbar)을
-- 열었다 닫으면 nvim 이 비워진 칸을 맨 왼쪽 창인 개요 막대에 주어 36 칸이 되었고, <C-w>| 뒤에는 1 칸으로
-- 남았다. 넓어진 막대를 되돌렸으면(곁창이 내준 칸이 A 로 간다) A·B 를 다시 반반으로 (WinResized). 좁아진
-- 것(<C-w>|)은 되돌리기만 - 반반으로 하면 사용자가 넓힌 창이 도로 줄었다
function cmp.keep_size(v)
  local fixed = false
  if v.ov and api.nvim_win_is_valid(v.ov.win) and api.nvim_win_get_width(v.ov.win) ~= 3 then
    fixed = api.nvim_win_get_width(v.ov.win) > 3
    pcall(api.nvim_win_set_width, v.ov.win, 3)
  end
  if v.ld and api.nvim_win_is_valid(v.ld.win) and api.nvim_win_get_height(v.ld.win) ~= 2 then
    pcall(api.nvim_win_set_height, v.ld.win, 2)
  end
  if fixed and api.nvim_win_is_valid(v.win_a) and api.nvim_win_is_valid(v.win_b) then
    local tw = api.nvim_win_get_width(v.win_a) + api.nvim_win_get_width(v.win_b)
    pcall(api.nvim_win_set_width, v.win_a, math.floor(tw / 2))
  end
end

-- 비교 창 둘이 다 닫혔으면 곁 창도 닫는다 (WinClosed 뒤)
function cmp.orphans(v)
  if v.closed or api.nvim_win_is_valid(v.win_a) or api.nvim_win_is_valid(v.win_b) then
    return
  end
  cmp.detach(v)
end

-- 곁 창을 닫는다: 짝을 놓았는데 탭이 남을 때(:tabonly·트리 탭을 닫아 비교 탭이 마지막 탭, 비교 창 둘이 다
-- 닫혔다), 알림(바이너리·큰 파일)이 된 짝. 그대로 두었더니 다시 그리지 않는 개요 막대·줄 자세히가 옛 글을
-- 단 채 남았고, 짝이 없어 돌려보내지도 않아 <C-w>h 로 들어가 머물렀다. vim-ide 의 overview 막대도 돌려준다
function cmp.detach(v)
  for _, x in ipairs({ v.ov or false, v.ld or false }) do
    if x and api.nvim_win_is_valid(x.win) then
      pcall(api.nvim_win_close, x.win, true)
    end
  end
  v.ov, v.ld = nil, nil
  cmp.own_overview(v)
end

-- vim-ide 의 overview 막대(overview.lua - 편집 창 오른쪽 끝의 부동 막대)를 비교 창에서 끈다 (w:overview_off):
-- 개요 막대가 있으면 막대가 둘이었다 (A 와 B 사이에 검은 막대). 개요 막대가 없으면(꺼 두었거나 pair_tab = 0)
-- 그대로 둔다. 창 변수라 갈라 만든 창은 물려받지 않는다
function cmp.own_overview(v)
  local off = (v.ov and api.nvim_win_is_valid(v.ov.win)) and 1 or nil
  for _, w in ipairs({ v.win_a, v.win_b }) do
    if api.nvim_win_is_valid(w) then
      vim.w[w].overview_off = off
    end
  end
end

-- 버퍼에 단 화살표·연보라를 걷는다 (짝을 놓을 때). 다시 그리기 시계도 멈춘다
function cmp.clear(v)
  if v.cx and v.cx.timer then
    v.cx.timer:stop()
    if not v.cx.timer:is_closing() then
      v.cx.timer:close()
    end
    v.cx.timer = nil
  end
  for _, t in ipairs({ v.ab or {}, v.mb or {} }) do
    for _, b in pairs(t) do
      if api.nvim_buf_is_valid(b) then
        api.nvim_buf_clear_namespace(b, NS.arrow, 0, -1)
        api.nvim_buf_clear_namespace(b, NS.blank, 0, -1)
      end
    end
  end
  v.ab, v.mb = nil, nil
  v.dd = nil
end

-- 화살표·연보라는 버퍼에 단다 - 같은 파일을 다른 창에도 띄우면 거기도 보인다. nvim__ns_set(있으면)으로 그
-- 이름 공간을 비교 창들에만 보이게 한다 (0.10~ 의 실험 API 라 없거나 바뀌면 그냥 버퍼 전체)
function cmp.scope()
  if not api.nvim__ns_set then
    return
  end
  local wins = {}
  for _, v in ipairs(all_views()) do
    for _, w in ipairs({ v.win_a, v.win_b }) do
      if api.nvim_win_is_valid(w) then
        wins[#wins + 1] = w
      end
    end
  end
  if #wins > 0 then
    pcall(api.nvim__ns_set, NS.arrow, { wins = wins })
    pcall(api.nvim__ns_set, NS.blank, { wins = wins })
  end
end

-- 'diffopt' 을 vim.diff 의 것으로 (화면의 diff 와 같은 덩어리가 나오게): 알고리즘, 빈칸·빈 줄 무시,
-- linematch (덩어리 안의 줄 맞춤 - 화면도 그렇게 맞춘다), indent-heuristic. icase 는 vim.diff 에 없어서
-- 소문자로 바꿔 견준다
function cmp.diffopts()
  local o = { result_type = 'indices' }
  local icase = false
  for p in vim.o.diffopt:gmatch('[^,]+') do
    local k, val = p:match('^([^:]+):?(.*)$')
    if k == 'algorithm' and val ~= '' then
      o.algorithm = val
    elseif k == 'iwhite' then
      o.ignore_whitespace_change = true
    elseif k == 'iwhiteall' then
      o.ignore_whitespace = true
    elseif k == 'iwhiteeol' then
      o.ignore_whitespace_change_at_eol = true
    elseif k == 'iblank' then
      o.ignore_blank_lines = true
    elseif k == 'indent-heuristic' then
      o.indent_heuristic = true
    elseif k == 'linematch' then
      o.linematch = tonumber(val)
    elseif k == 'icase' then
      icase = true
    end
  end
  return o, icase
end

-- 두 창의 차이를 센다 (v.dd): hunks (a0 a1 b0 b1 - 반열린 구간, 1 부터. 빈 쪽은 a0 == a1 이고 그 줄 바로
-- 위가 끼인 줄 자리, r0 = 가지런한 행 - 끼인 줄 포함, 0 부터), N 가지런한 행 수, blocks (사이에 같은 줄
-- 없이 붙은 덩어리를 묶은 것 - linematch 가 조각낸 한 덩어리, 화살표), blank (연보라 빈 줄: 짝 없는 빈
-- 줄, 짝이 있으면 둘 다 빈 줄 - 빈칸만 다르다). 덩어리 안에서 앞의 min(ca, cb) 줄이 짝을 이루고 남은 줄의
-- 맞은편이 끼인 줄이다 (vim 의 diff 가 그린다). 아주 큰 것(두 쪽 합 40만 줄 넘음)은 세지 않는다
function cmp.compute(v)
  v.dd = nil
  if v.bin or not v.rel then
    return
  end
  local wa, wb = v.win_a, v.win_b
  local ba, bb = cmp.pbuf(v, 'a'), cmp.pbuf(v, 'b')
  if not (ba and bb and vim.wo[wa].diff and vim.wo[wb].diff) then
    return
  end
  if api.nvim_buf_line_count(ba) + api.nvim_buf_line_count(bb) > 400000 then
    return
  end
  local la = empty_buf(ba) and {} or api.nvim_buf_get_lines(ba, 0, -1, false)
  local lb = empty_buf(bb) and {} or api.nvim_buf_get_lines(bb, 0, -1, false)
  local opts, icase = cmp.diffopts()
  local ta = #la > 0 and (table.concat(la, '\n') .. '\n') or ''
  local tb = #lb > 0 and (table.concat(lb, '\n') .. '\n') or ''
  if icase then
    ta, tb = ta:lower(), tb:lower()
  end
  local df = (vim.text and vim.text.diff) or vim.diff
  -- linematch 는 덩어리마다 따로: 파일 전체에 linematch 를 주면 vim.diff 가 덩어리마다 글 전체를 다시 훑어
  -- (15만 줄, 덩어리 400 개에 0.36 초 - linematch 없이는 0.016 초, 실측) 고칠 때마다 멈췄다. 먼저 줄 맞춤
  -- 없이 덩어리를 찾고, 화면처럼(diffopt linematch:N - 두 쪽 합이 N 줄 이하인 덩어리) 그 덩어리의 글만
  -- 다시 견주어 조각낸다
  local lm = opts.linematch
  opts.linematch = nil
  local ok, hk = pcall(df, ta, tb, opts)
  if not ok or type(hk) ~= 'table' then
    return
  end
  if lm and lm > 0 then
    local out = {}
    local sub_opts = vim.tbl_extend('force', opts, { linematch = lm })
    for _, h in ipairs(hk) do
      local sa, ca, sb, cb = h[1], h[2], h[3], h[4]
      local done = false
      if ca > 0 and cb > 0 and ca + cb <= lm then
        local xa = table.concat(la, '\n', sa, sa + ca - 1) .. '\n'
        local xb = table.concat(lb, '\n', sb, sb + cb - 1) .. '\n'
        if icase then
          xa, xb = xa:lower(), xb:lower()
        end
        local ok2, sub = pcall(df, xa, xb, sub_opts)
        if ok2 and type(sub) == 'table' and #sub > 0 then
          for _, x in ipairs(sub) do
            out[#out + 1] = { sa - 1 + x[1], x[2], sb - 1 + x[3], x[4] }
          end
          done = true
        end
      end
      if not done then
        out[#out + 1] = h
      end
    end
    hk = out
  end
  local d = { na = #la, nb = #lb, hunks = {}, blocks = {}, blank = { a = {}, b = {} }, added = { a = {}, b = {} } }
  local row, pa = 0, 1
  local want_blank = pal() == 'bc'
  local nblank = 0
  for _, h in ipairs(hk) do
    local sa, ca, sb, cb = h[1], h[2], h[3], h[4]
    local a0 = ca == 0 and sa + 1 or sa
    local b0 = cb == 0 and sb + 1 or sb
    row = row + (a0 - pa)
    local x = { a0 = a0, a1 = a0 + ca, b0 = b0, b1 = b0 + cb, r0 = row }
    d.hunks[#d.hunks + 1] = x
    local last = d.blocks[#d.blocks]
    if last and last.a1 == a0 and last.b1 == b0 then
      last.a1, last.b1 = x.a1, x.b1
    else
      d.blocks[#d.blocks + 1] = { a0 = a0, a1 = x.a1, b0 = b0, b1 = x.b1 }
    end
    -- 짝 없는 줄 (맞은편이 끼인 줄): 그 줄들의 글자를 빨강으로 (bc - cmp.marks)
    if ca > cb then
      d.added.a[#d.added.a + 1] = { a0 + cb, x.a1 }
    elseif cb > ca then
      d.added.b[#d.added.b + 1] = { b0 + ca, x.b1 }
    end
    if want_blank and nblank < 20000 then
      for k = 0, math.max(ca, cb) - 1 do
        local xa = k < ca and la[a0 + k] or nil
        local xb = k < cb and lb[b0 + k] or nil
        local ea = xa ~= nil and not xa:find('%S')
        local eb = xb ~= nil and not xb:find('%S')
        if ea and (xb == nil or eb) then
          d.blank.a[#d.blank.a + 1] = a0 + k
          nblank = nblank + 1
        end
        if eb and (xa == nil or ea) then
          d.blank.b[#d.blank.b + 1] = b0 + k
          nblank = nblank + 1
        end
      end
    end
    row = row + math.max(ca, cb)
    pa = x.a1
  end
  d.N = row + (#la + 1 - pa)
  v.dd = d
end

-- 한쪽 줄 l 의 가지런한 행(0 부터), 맞은편 줄(없으면 nil - 그 행은 맞은편이 끼인 줄), 바뀐 줄인가
function cmp.locate(d, side, l)
  local s0, s1, o0, o1 = 'a0', 'a1', 'b0', 'b1'
  if side == 'b' then
    s0, s1, o0, o1 = 'b0', 'b1', 'a0', 'a1'
  end
  local hs = d.hunks
  local lo, hi, k = 1, #hs, 0
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if hs[mid][s0] <= l then
      k, lo = mid, mid + 1
    else
      hi = mid - 1
    end
  end
  if k == 0 then
    return l - 1, l, false
  end
  local h = hs[k]
  if l < h[s1] then
    local kk = l - h[s0]
    local other = h[o0] + kk
    return h.r0 + kk, (other < h[o1]) and other or nil, true
  end
  local off = l - h[s1]
  return h.r0 + math.max(h.a1 - h.a0, h.b1 - h.b0) + off, h[o1] + off, false
end

-- 가지런한 행 row 의 그쪽 줄 (끼인 줄 자리면 그 아래 첫 줄)
function cmp.line_at(d, side, row)
  local s0, s1 = side == 'b' and 'b0' or 'a0', side == 'b' and 'b1' or 'a1'
  local prow, pl = 0, 1
  for _, h in ipairs(d.hunks) do
    if row < h.r0 then
      return pl + (row - prow)
    end
    local rows = math.max(h.a1 - h.a0, h.b1 - h.b0)
    if row < h.r0 + rows then
      local kk = row - h.r0
      return kk < h[s1] - h[s0] and h[s0] + kk or h[s1]
    end
    prow, pl = h.r0 + rows, h[s1]
  end
  return pl + (row - prow)
end

-- 커서 줄 l 이 든 블록, 없으면 가장 가까운 것 (같으면 앞의 것)
function cmp.block_at(d, side, l)
  local s0, s1 = side == 'b' and 'b0' or 'a0', side == 'b' and 'b1' or 'a1'
  local bs = d.blocks
  local lo, hi, k = 1, #bs, 0
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if bs[mid][s0] <= l then
      k, lo = mid, mid + 1
    else
      hi = mid - 1
    end
  end
  local function dist(b)
    if b[s0] == b[s1] then
      return math.abs(l - b[s0])
    end
    if l < b[s0] then
      return b[s0] - l
    end
    return l >= b[s1] and (l - b[s1] + 1) or 0
  end
  local best, bd
  for _, i in ipairs({ k, k + 1 }) do
    local b = bs[i]
    if b and (not bd or dist(b) < bd) then
      best, bd = b, dist(b)
    end
  end
  return best
end

-- 노란 화살표 (Beyond Compare 의 지금 차이): 커서가 있는(없으면 가까운) 덩어리의 첫 줄에 A ⇨, B ⇦,
-- 그 덩어리 끝까지 옅은 괄호선 (│ … └ - 500 줄 넘으면 끝만). 줄이 없는 쪽(빈자리 - 끼인 줄은 sign 을 달
-- 수 없다)은 빗금 바로 위 줄에 (첫 줄 위면 그 아래 줄에)
function cmp.arrows(v)
  v.ab = v.ab or {}
  for _, side in ipairs({ 'a', 'b' }) do
    local old = v.ab[side]
    if old and api.nvim_buf_is_valid(old) then
      api.nvim_buf_clear_namespace(old, NS.arrow, 0, -1)
    end
    v.ab[side] = nil
  end
  local d = v.dd
  if not (d and #d.blocks > 0) then
    return
  end
  local cw = cmp.cur(v)
  if not api.nvim_win_is_valid(cw) then
    return
  end
  local blk = cmp.block_at(d, cw == v.win_b and 'b' or 'a', api.nvim_win_get_cursor(cw)[1])
  if not blk then
    return
  end
  local a = ascii()
  for _, side in ipairs({ 'a', 'b' }) do
    local b = cmp.pbuf(v, side)
    -- 줄이 하나도 없는 쪽(한쪽에만 있는 파일의 빈 쪽)에는 달지 않는다: 빗금을 모두 지나 맨 아래의 빈 줄에
    -- 홀로 섰다 (끼인 줄에는 sign 을 달 수 없다)
    if b and d['n' .. side] > 0 then
      local n = api.nvim_buf_line_count(b)
      local x0, x1 = blk[side .. '0'], blk[side .. '1']
      local at = x0
      if x1 == x0 then
        at = x0 > 1 and x0 - 1 or 1
      end
      at = math.max(1, math.min(at, n))
      local arrow = side == 'a' and (a and '>' or '⇨') or (a and '<' or '⇦')
      pcall(api.nvim_buf_set_extmark, b, NS.arrow, at - 1, 0,
        { sign_text = arrow, sign_hl_group = 'VimIdeDirDiffArrow', priority = 200 })
      if x1 - x0 > 1 then
        local last = math.min(x1 - 1, n)
        if x1 - x0 <= 500 then
          for l = x0 + 1, last - 1 do
            pcall(api.nvim_buf_set_extmark, b, NS.arrow, l - 1, 0,
              { sign_text = a and '|' or '│', sign_hl_group = 'VimIdeDirDiffBracket', priority = 200 })
          end
        end
        pcall(api.nvim_buf_set_extmark, b, NS.arrow, last - 1, 0,
          { sign_text = a and '`' or '└', sign_hl_group = 'VimIdeDirDiffBracket', priority = 200 })
      end
      v.ab[side] = b
    end
  end
end

-- 연보라 빈 줄 (bc 만): 바뀐 덩어리 안의 빈 줄 (Beyond Compare 의 '중요하지 않은' 차이). 줄 바탕을 덮는다.
-- 한쪽에만 있는 줄의 글자 빨강도 여기서 (같은 이름 공간 - 같이 걷는다)
function cmp.marks(v)
  v.mb = v.mb or {}
  for _, side in ipairs({ 'a', 'b' }) do
    local old = v.mb[side]
    if old and api.nvim_buf_is_valid(old) then
      api.nvim_buf_clear_namespace(old, NS.blank, 0, -1)
    end
    v.mb[side] = nil
    local b = cmp.pbuf(v, side)
    if v.dd and pal() == 'bc' and b then
      -- line_hl_group 은 diff 의 줄 색(DiffAdd·DiffChange)에 진다 (실측) - 줄 끝까지 가는 범위 색은 이긴다
      local n = api.nvim_buf_line_count(b)
      -- 줄 l0 ~ l1-1 (1 부터): 끝은 다음 줄 첫머리. 마지막 줄이면 버퍼 끝 너머(줄 수, 0 - strict = false)로:
      -- 그 줄 끝까지로 했더니 마지막 줄이 빈 줄이면 폭 0 이라 연보라가 그려지지 않았다
      local function lines(l0, l1, opt)
        opt.end_row, opt.end_col = math.min(l1, n + 1) - 1, 0
        opt.strict = false
        pcall(api.nvim_buf_set_extmark, b, NS.blank, l0 - 1, 0, opt)
      end
      for _, l in ipairs(v.dd.blank[side]) do
        lines(l, l + 1, { hl_group = 'VimIdeDirDiffBlank', hl_eol = true, priority = 50 })
      end
      -- 한쪽에만 있는 줄은 글자를 모두 빨강으로 (Beyond Compare - 구문 색보다 위, 덩어리마다 하나)
      for _, x in ipairs(v.dd.added[side]) do
        lines(x[1], x[2], { hl_group = 'VimIdeDirDiffAddText', priority = 150 })
      end
      v.mb[side] = b
    end
  end
end

-- 개요 막대 (Beyond Compare 의 맨 왼쪽 막대): 파일 전체(가지런한 행)를 창 높이로 줄여 칸마다 A | B |
-- 보이는 곳. 칸의 색은 그 행들 중 가장 센 것 - 차이(빨강) > 연보라 빈 줄(파랑) > 빈자리(그쪽에 줄이
-- 없다 - 회색 빗금). 셋째 칸이 지금 보이는 곳 (회색). 누르면 그 자리로 (cmp.over_click)
function cmp.over_fill(v)
  local ov = v.ov
  if not (ov and api.nvim_win_is_valid(ov.win) and api.nvim_buf_is_valid(ov.buf)) then
    return
  end
  -- 글 줄의 높이 (winheight - 창 머리 한 줄을 뺀 것): nvim_win_get_height 는 창 머리까지 세어 칸이 한 줄
  -- 많았고, 마지막 칸(파일 끝의 차이, G 의 보이는 곳)은 창 밖이라 보이지 않았다
  local H = math.max(1, vim.fn.winheight(ov.win))
  local W = math.max(3, api.nvim_win_get_width(ov.win))
  local lines = {}
  for i = 1, H do
    lines[i] = string.rep(' ', W)
  end
  vim.bo[ov.buf].modifiable = true
  api.nvim_buf_set_lines(ov.buf, 0, -1, false, lines)
  vim.bo[ov.buf].modifiable = false
  ov.cells = nil
  local d = v.dd
  if d and d.N > 0 then
    -- 창보다 짧은 파일은 행 하나가 칸 하나 (막대가 글과 같은 줄에 선다 - 늘이면 짧은 파일의 차이가 엉뚱한
    -- 높이에 찍혔다). 긴 파일은 창 높이로 줄인다
    local N = math.max(d.N, H)
    local cells = { a = {}, b = {} }
    local function mark(t, r0, r1, val)
      if r1 <= r0 then
        return
      end
      local c1 = math.min(H - 1, math.floor((r1 - 1) * H / N))
      for c = math.floor(r0 * H / N), c1 do
        if (t[c] or 0) < val then
          t[c] = val
        end
      end
    end
    local blank = { a = {}, b = {} }
    for _, side in ipairs({ 'a', 'b' }) do
      for _, l in ipairs(d.blank[side]) do
        blank[side][l] = true
      end
    end
    for _, h in ipairs(d.hunks) do
      local rows = math.max(h.a1 - h.a0, h.b1 - h.b0)
      for _, side in ipairs({ 'a', 'b' }) do
        local x0, x1 = h[side .. '0'], h[side .. '1']
        local t, bl = cells[side], blank[side]
        if x1 - x0 > 2000 or next(bl) == nil then
          mark(t, h.r0, h.r0 + (x1 - x0), 3)
        else
          for k = 0, x1 - x0 - 1 do
            mark(t, h.r0 + k, h.r0 + k + 1, bl[x0 + k] and 2 or 3)
          end
        end
        mark(t, h.r0 + (x1 - x0), h.r0 + rows, 1)
      end
    end
    ov.cells = cells
  end
  cmp.over_paint(v)
end

-- 지금 보이는 곳의 칸 (c0, c1 - 0 부터)
function cmp.view_cells(v, H)
  local d = v.dd
  local w = cmp.cur(v)
  if not (d and d.N > 0 and api.nvim_win_is_valid(w)) then
    return nil
  end
  local side = w == v.win_b and 'b' or 'a'
  local top, bot = vim.fn.line('w0', w), vim.fn.line('w$', w)
  local r0 = cmp.locate(d, side, top)
  local r1 = cmp.locate(d, side, bot)
  local N = math.max(d.N, H)
  return math.floor(r0 * H / N), math.min(H - 1, math.floor(r1 * H / N))
end

function cmp.over_paint(v)
  local ov = v.ov
  if not (ov and api.nvim_win_is_valid(ov.win) and api.nvim_buf_is_valid(ov.buf)) then
    return
  end
  api.nvim_buf_clear_namespace(ov.buf, NS.over, 0, -1)
  local H = api.nvim_buf_line_count(ov.buf)
  local G = { 'VimIdeDirDiffOvFill', 'VimIdeDirDiffOvBlank', 'VimIdeDirDiffOvChange' }
  local hatch = ascii() and '/' or '╱'
  local cells = ov.cells
  local v0, v1 = cmp.view_cells(v, H)
  for c = 0, H - 1 do
    for i, side in ipairs({ 'a', 'b' }) do
      local st = cells and cells[side][c]
      if st then
        local opt = { end_col = i, hl_group = G[st] }
        if st == 1 then
          opt.virt_text, opt.virt_text_pos = { { hatch, G[1] } }, 'overlay'
        end
        pcall(api.nvim_buf_set_extmark, ov.buf, NS.over, c, i - 1, opt)
      end
    end
    if v0 and c >= v0 and c <= v1 then
      pcall(api.nvim_buf_set_extmark, ov.buf, NS.over, c, 2, { end_col = 3, hl_group = 'VimIdeDirDiffOvView' })
    end
  end
end

-- 개요 막대를 눌렀다: 그 칸의 행으로 (지금 비교 창에서, 가운데로). cell: 누른 칸 (1 부터 - getmousepos() 의
-- line, 막대 버퍼의 줄. winrow 는 창 머리까지 세어 한 칸 아래로 갔다)
function cmp.over_click(v, cell)
  local d = v.dd
  local w = cmp.cur(v)
  if not api.nvim_win_is_valid(w) then
    return
  end
  api.nvim_set_current_win(w)
  if not (d and d.N > 0 and v.ov and api.nvim_win_is_valid(v.ov.win)) then
    return
  end
  local H = math.max(1, api.nvim_buf_line_count(v.ov.buf))
  cell = math.max(1, math.min(cell, H))
  local row = math.max(0, math.min(d.N - 1, math.floor((cell - 0.5) * math.max(d.N, H) / H)))
  local l = cmp.line_at(d, w == v.win_b and 'b' or 'a', row)
  l = math.max(1, math.min(l, api.nvim_buf_line_count(api.nvim_win_get_buf(w))))
  pcall(api.nvim_win_set_cursor, w, { l, 0 })
  pcall(vim.cmd, 'normal! zz')
  cmp.kick(v)
end

-- 줄 하나를 빈칸이 보이게 (빈칸 ·, 탭 → 와 다음 탭 자리까지, 줄 끝 ¶ - ASCII 는 . > $). 돌려주는 것:
-- 글, 원래 바이트(1 부터) -> 새 바이트(0 부터), 표시들의 [시작, 끝) 바이트
function cmp.show_ws(text, ts)
  local a = ascii()
  local SP, TAB, EOL = a and '.' or '·', a and '>' or '→', a and '$' or '¶'
  if #text > 1000 then
    text = vim.fn.strcharpart(text:sub(1, 1000), 0, vim.fn.strchars(text:sub(1, 1000)) - 1)
  end
  local out, map, ws = {}, {}, {}
  local ob, col, i, n = 0, 0, 1, #text
  while i <= n do
    local c = text:byte(i)
    local clen = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
    local ch = text:sub(i, i + clen - 1)
    map[i] = ob
    local piece
    if ch == ' ' then
      piece = SP
      ws[#ws + 1] = { ob, ob + #piece }
      col = col + 1
    elseif ch == '\t' then
      local w = ts - (col % ts)
      piece = TAB .. string.rep(a and '-' or ' ', w - 1)
      ws[#ws + 1] = { ob, ob + #piece }
      col = col + w
    else
      piece = ch
      col = col + (clen == 1 and 1 or vim.fn.strdisplaywidth(ch))
    end
    out[#out + 1] = piece
    ob = ob + #piece
    i = i + clen
  end
  map[n + 1] = ob
  ws[#ws + 1] = { ob, ob + #EOL }
  out[#out + 1] = EOL
  return table.concat(out), map, ws
end

-- 줄 자세히 (Beyond Compare 의 맨 아래 두 줄): ⇨ A 의 줄, ⇦ B 의 줄 - 커서 줄과 맞은편 줄 (맞은편이 끼인
-- 줄이면 비운다). 빈칸이 보이게, 비교 창과 같은 색 (바뀐 줄은 분홍 바탕에 다른 글자 빨강 - vim 의
-- diff_hlID 로, 한쪽에만 있는 줄은 빨강). 커서가 창 밖으로 나가면 가로로 따라간다. 상태줄에 두 줄의 번호
function cmp.details(v)
  local ld = v.ld
  if not (ld and api.nvim_win_is_valid(ld.win) and api.nvim_buf_is_valid(ld.buf)) then
    return
  end
  local d = v.dd
  local cw = cmp.cur(v)
  local cur = {}
  local on_side = cw == v.win_b and 'b' or 'a'
  if not v.bin and v.rel and api.nvim_win_is_valid(cw) then
    local l = api.nvim_win_get_cursor(cw)[1]
    cur[on_side] = l
    local other = on_side == 'a' and 'b' or 'a'
    if d then
      local _, o = cmp.locate(d, on_side, l)
      cur[other] = o
      if (on_side == 'a' and d.na == 0) or (on_side == 'b' and d.nb == 0) then
        cur[on_side] = nil
      end
    elseif api.nvim_win_is_valid(v['win_' .. other]) then
      cur[other] = api.nvim_win_get_cursor(v['win_' .. other])[1]
    end
  end
  local lines, marks = {}, {}
  -- 다른 글자: DiffText, 그리고 0.12 의 diffopt inline:char 가 줄 안에 더한 글자에 쓰는 DiffTextAdd (그 무리가
  -- 있으면 - 비교 창에서는 그것이 DiffText 에 이어져 빨강인데 줄 자세히는 DiffText 만 보아 검게 남았다)
  local text_id = vim.fn.hlID('DiffText')
  local add_id = vim.fn.hlexists('DiffTextAdd') == 1 and vim.fn.hlID('DiffTextAdd') or -1
  local pcol
  for i, side in ipairs({ 'a', 'b' }) do
    local pre = side == 'a' and (ascii() and '>' or '⇨') or (ascii() and '<' or '⇦')
    local l = cur[side]
    local w = v['win_' .. side]
    local line = ''
    local mk = { { 'VimIdeDirDiffArrow', 0, #pre, 130 } }
    -- 짝이 아닌 버퍼를 띄운 쪽은 비운다 (cmp.pbuf)
    local b = cmp.pbuf(v, side)
    if l and b then
      local src = api.nvim_buf_get_lines(b, l - 1, l, false)[1] or ''
      local body, map, ws = cmp.show_ws(src, vim.bo[b].tabstop)
      line = body
      local o = #pre
      local S = side:upper()
      local other, inh
      if d then
        other, inh = select(2, cmp.locate(d, side, l))
      end
      if inh then
        if other then
          mk[#mk + 1] = { 'VimIdeDirDiffChange' .. S, o, o + #body, 100 }
          -- 다른 글자: vim 의 diff 가 그 창에서 DiffText 로 그리는 바이트 (앞 400 바이트까지)
          local runs = api.nvim_win_call(w, function()
            local r, st = {}, nil
            for c = 1, math.min(#src, 400) do
              local id = vim.fn.diff_hlID(l, c)
              local hit = id == text_id or id == add_id
              if hit and not st then
                st = c
              elseif not hit and st then
                r[#r + 1] = { st, c }
                st = nil
              end
            end
            if st then
              r[#r + 1] = { st, math.min(#src, 400) + 1 }
            end
            return r
          end)
          for _, x in ipairs(runs) do
            if map[x[1]] and map[x[2]] then
              mk[#mk + 1] = { 'VimIdeDirDiffText' .. S, o + map[x[1]], o + map[x[2]], 110 }
            end
          end
        else
          mk[#mk + 1] = { 'VimIdeDirDiffAdd' .. S, o, o + #body, 100 }
        end
      end
      for _, x in ipairs(ws) do
        mk[#mk + 1] = { 'VimIdeDirDiffWs', o + x[1], o + x[2], 120 }
      end
      if side == on_side then
        local cc = api.nvim_win_get_cursor(cw)[2] + 1
        local ob = map[cc] or map[#src + 1] or 0
        pcol = vim.fn.strdisplaywidth(pre .. body:sub(1, ob))
      end
    end
    lines[i] = pre .. line
    marks[i] = mk
  end
  vim.bo[ld.buf].modifiable = true
  api.nvim_buf_set_lines(ld.buf, 0, -1, false, lines)
  vim.bo[ld.buf].modifiable = false
  api.nvim_buf_clear_namespace(ld.buf, NS.line, 0, -1)
  for i, mk in ipairs(marks) do
    for _, m in ipairs(mk) do
      pcall(api.nvim_buf_set_extmark, ld.buf, NS.line, i - 1, m[2], { end_col = m[3], hl_group = m[1], priority = m[4] })
    end
  end
  local width = api.nvim_win_get_width(ld.win)
  local left = (pcol and pcol > width - 4) and math.max(0, pcol - math.floor(width / 2)) or 0
  pcall(api.nvim_win_call, ld.win, function()
    vim.fn.winrestview({ leftcol = left, topline = 1 })
  end)
  set_wo(ld.win, 'statusline', ('%%#VimIdeDirDiffPending# 줄 자세히   A %s   B %s'):format(
    cur.a and tostring(cur.a) or '-', cur.b and tostring(cur.b) or '-'))
end

-- 창 머리의 정보 (cmp: 비교 탭의 일부라 여기에): { 수정 일시, 크기, 인코딩·줄 끝 } - 좁으면 뒤에서부터 뺀다
-- (set_heads). 알림 창(바이너리·큰 파일)은 일시·크기만, 파일이 아닌 쪽(없음, 디렉터리)은 없다
function cmp.info(v, side)
  local st = v.info and v.info[side]
  if not (st and st.type == 'file') then
    return {}
  end
  local f = tr.datefmt()
  local parts = { tr.strf(f.src, st.mtime.sec), commas(st.size) .. ' 바이트' }
  local w = v['win_' .. side]
  if not v.bin and api.nvim_win_is_valid(w) then
    local b = api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == '' then
      local fenc = vim.bo[b].fileencoding
      parts[#parts + 1] = (fenc ~= '' and fenc or vim.o.encoding) .. '  ' .. vim.bo[b].fileformat
    end
  end
  return parts
end

-- 다시 그리기를 모은다: all 이면 차이를 다시 세고 개요 막대·연보라까지, 아니면 화살표·줄 자세히·보이는
-- 곳만. 마지막 부름에서 잠깐 뒤에 한 번 (글을 치는 동안 큰 파일을 줄곧 다시 세지 않게 all 은 120ms 쉰 뒤)
function cmp.kick(v, all)
  if not v or v.closed then
    return
  end
  local cx = v.cx or {}
  v.cx = cx
  if all then
    cx.all = true
  end
  if not cx.timer then
    cx.timer = uv.new_timer()
  end
  cx.timer:stop()
  cx.timer:start(cx.all and 120 or 20, 0, vim.schedule_wrap(function()
    if v.closed then
      return
    end
    local ok, err = pcall(cmp.update, v)
    if not ok and on(vim.g.vimide_dirdiff_debug, 0) then
      say('곁 창: ' .. tostring(err), vim.log.levels.WARN)
    end
  end))
end

function cmp.update(v)
  if v.cx.all then
    v.cx.all = false
    cmp.scope()
    cmp.compute(v)
    cmp.marks(v)
    cmp.over_fill(v)
  else
    cmp.over_paint(v)
  end
  cmp.arrows(v)
  cmp.details(v)
end

-- 마우스로 들어왔는가: 마지막으로 받은 키가 마우스 키였나 (vim.on_key - 키를 받을 때마다, 그 키로 창을
-- 옮기기 앞에 불린다). getmousepos() 만 보았더니 그것은 마지막 마우스 자리라, 한 번 누른 뒤에는(또는 한 번도
-- 안 눌러 (1,1) - 개요 막대가 왼쪽 위다) 키보드로 들어와도(<C-w>h <C-w>t) 누른 것으로 알고 옛 자리로 뛰었다
cmp.MOUSE = {}
for _, k in ipairs({ '<LeftMouse>', '<LeftRelease>', '<LeftDrag>', '<RightMouse>', '<MiddleMouse>' }) do
  cmp.MOUSE[#cmp.MOUSE + 1] = api.nvim_replace_termcodes(k, true, true, true)
end
cmp.mouse = false
-- key 는 매핑을 푼 뒤, typed 는 친 그대로 (overview.lua 처럼 마우스 키를 매핑으로 감싼 것이 있어 둘 다 본다)
vim.on_key(function(key, typed)
  local k = (key or '') .. (typed or '')
  if k == '' then
    return
  end
  local m = false
  if k:find('\128', 1, true) then
    for _, x in ipairs(cmp.MOUSE) do
      if k:find(x, 1, true) then
        m = true
        break
      end
    end
  end
  cmp.mouse = m
end, api.nvim_create_namespace('vimide_dirdiffview_key'))

-- 곁 창에 들어왔다 (WinEnter 뒤, click: 마우스로 들어왔다 - WinEnter 때의 cmp.mouse): 경로 줄이면 트리로
-- (누른 쪽으로 A/B. pair_tab = 0 에서 트리에서 <C-w>k 로 왔으면 그 위의 편집 창으로 지나간다 - 트리로
-- 돌려보냈더니 편집 창에 갈 수 없었다), 개요 막대를 눌렀으면 그 자리로, 키보드로 개요 막대에 왔으면 A 로
-- (<C-w>h <C-w>t 1<C-w>w - 왼쪽·첫 창으로 가려던 것), 그 밖에는 마지막 비교 창으로. 돌아간 비교 창의
-- '앞 창'(<C-w>p)은 다른 비교 창으로 둔다 - 곁 창이 앞 창으로 남아 <C-w>p 가 그리 갔다가 돌아오기만 했다
function cmp.bounce(w, click)
  if api.nvim_get_current_win() ~= w or not api.nvim_win_is_valid(w) then
    return
  end
  local mp = vim.fn.getmousepos()
  click = click and mp.winid == w
  local from = vim.fn.win_getid(vim.fn.winnr('#'))
  for _, s in pairs(sessions) do
    if s.hwin == w then
      if api.nvim_win_is_valid(s.win_l) then
        if not click and from == s.win_l then
          local up = vim.fn.win_getid(vim.fn.winnr('k'))
          if up ~= 0 and up ~= w then
            api.nvim_set_current_win(up)
            return
          end
        end
        if click then
          s.side = mp.wincol > layout(s).half + 2 and 'b' or 'a'
        end
        api.nvim_set_current_win(s.win_l)
        goto_row(s, api.nvim_win_get_cursor(s.win_l)[1])
        mark_side(s)
        s.prog_dirty = true
        schedule_render(s)
      else
        pcall(vim.cmd, 'wincmd p')
      end
      return
    end
  end
  for _, v in ipairs(all_views()) do
    local is_ov = v.ov and v.ov.win == w
    if is_ov or (v.ld and v.ld.win == w) then
      local back = cmp.cur(v)
      if is_ov and not click and api.nvim_win_is_valid(v.win_a) then
        back = v.win_a
      end
      if api.nvim_win_is_valid(back) then
        local alt = back == v.win_a and v.win_b or v.win_a
        if api.nvim_win_is_valid(alt) then
          pcall(vim.cmd, 'noautocmd call win_gotoid(' .. alt .. ')')
        end
        api.nvim_set_current_win(back)
      end
      if click and is_ov then
        cmp.over_click(v, mp.line)
      end
      return
    end
  end
  pcall(vim.cmd, 'wincmd p')
end

-- 트리 창이 닫혔는데 경로 줄 창이 남았다: 닫는다 (그 탭에 그것뿐이면 탭이 닫혀 TabClosed 가 끝낸다).
-- 마지막 탭의 마지막 창이라 닫을 수 없으면 끝낸다 (finish 가 빈 버퍼 하나로 남긴다)
function tr.head_orphan(s)
  local hw = s.hwin
  if not (hw and api.nvim_win_is_valid(hw)) or api.nvim_win_is_valid(s.win_l) then
    return
  end
  if #api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(hw)) > 1 or #api.nvim_list_tabpages() > 1 then
    pcall(api.nvim_win_close, hw, true)
  elseif not s.done then
    finish(s)
  end
end

-- 편집 창에서 <C-n>/<C-p> (.vimrc 의 ListStep 이 먼저 묻는다): ]c / [c
function _G.vimide_dirdiff_step(dir)
  local w = api.nvim_get_current_win()
  if view_of_win(w) and vim.wo[w].diff then
    -- dir 의 크기가 횟수다 (.vimrc 가 v:count1 을 넘긴다): 2<C-n> = 2]c
    pcall(vim.cmd, 'normal! ' .. math.max(1, math.abs(dir)) .. (dir > 0 and ']c' or '[c'))
    return true
  end
  return false
end

-- 트리 커서 줄이 가리키는 경로 (A 쪽, 없으면 B 쪽). 디렉터리면 끝에 '/' -
-- 곁창에서 <C-g>/<C-/> 로 찾을 때의 기준 (searchctx.lua)
function _G.vimide_dirdiff_path_at()
  local s = sessions[api.nvim_get_current_tabpage()]
  if not (s and api.nvim_get_current_win() == s.win_l) then
    return nil
  end
  local r = s.rows[api.nvim_win_get_cursor(s.win_l)[1]]
  if not (r and r.e) then
    return nil
  end
  -- 쪽을 고른 뒤 그 쪽의 종류로 '/' 를 붙인다 (A 는 파일, B 는 디렉터리인 줄에서
  -- A 의 파일에 '/' 를 붙여 찾을 곳이 파일이 되었다)
  local k = r.e.ka or r.e.kb
  local root = r.e.ka and s.a or s.b
  return root .. '/' .. r.rel .. (k == 'd' and '/' or '')
end

function _G.vimide_dirdiff_open(a, b)
  M.open(a, b)
end

local group = api.nvim_create_augroup('VimIdeDirDiffView', { clear = true })
-- 탭을 닫을 때 그 탭에 있었는지: 있던 탭을 닫으면 TabLeave 가 먼저 뜬다 (같은 명령 안에서).
-- 다른 탭에서 :Ntabclose 로 닫았으면 원래 탭으로 끌고 가지 않는다
local leaving
api.nvim_create_autocmd('TabLeave', {
  group = group,
  callback = function()
    leaving = api.nvim_get_current_tabpage()
    vim.schedule(function()
      leaving = nil
    end)
  end,
})
api.nvim_create_autocmd('TabClosed', {
  group = group,
  callback = function()
    for tab, s in pairs(sessions) do
      if not api.nvim_tabpage_is_valid(tab) then
        local was_here = leaving == tab
        vim.schedule(function()
          finish(s, not was_here)
        end)
      end
    end
    -- 비교 탭을 :tabclose(:q, <C-w>c ...)로 닫았다: 그 짝을 놓고, 그 탭에 있었으면 트리의 그 줄로 (q 처럼)
    for _, v in ipairs(all_views()) do
      if not v.inline and not api.nvim_tabpage_is_valid(v.tab) then
        local was_here = leaving == v.tab
        v.closed = true
        v.s.views[v.tab] = nil
        vim.schedule(function()
          release_view(v, was_here)
        end)
      end
    end
  end,
})
-- 'diffopt' 의 context 를 들어온 탭의 보기로 (비교 탭이 아니면 사용자 것으로 되돌린다 - dip_sync).
-- 비교 탭이면 곁(화살표·연보라·빨강·개요 막대)을 다시 센다: 이것들은 버퍼에 단 것이라 같은 파일을 보이는
-- 다른 비교 탭(겹친 Tab/Tab, 뿌리를 같이 쓰는 비교 둘)이 제 짝으로 덮어 놓았을 수 있다. 터미널 크기가
-- 바뀐 뒤 처음이면 두 창을 반반으로 (cmp.rebalance)
api.nvim_create_autocmd('TabEnter', {
  group = group,
  callback = function()
    dip_sync()
    local v = view_of_tab(api.nvim_get_current_tabpage())
    if v then
      if v.rebal then
        cmp.rebalance(v)
      end
      cmp.kick(v, true)
    end
  end,
})
-- :tabclose (또는 <C-w>c) 로 편집 창이 닫힐 때도 남는 버퍼(고친 것, 사용자 것)에 머리와 diff 접기가 적혀
-- 남지 않게, 창이 닫히기 바로 앞에 걷는다 (finish 는 탭이 닫힌 뒤에 돌아 창이 이미 없다). 탭의 마지막 창은
-- 여기 오기 전에 nvim 이 diff 를 이미 꺼 두어(nofoldenable, 접기는 남은 채) diff 였는지 묻지 않는다 - 편집
-- 창의 manual 접기는 diff 가 남긴 것뿐이다. q 로 닫을 때는 finish 가 먼저 sessions 에서 뺀 뒤라 그냥 지나간다
api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(ev)
    local w = tonumber(ev.match)
    local v = w and view_of_win(w)
    if v and api.nvim_win_is_valid(w) then
      pcall(api.nvim_win_call, w, function()
        vim.cmd('diffoff')
        undiff_folds()
        pcall(vim.cmd, 'setlocal foldlevel<')
      end)
      set_wo(w, 'winbar', '')
      diff_whl(w, nil)
      -- 비교 창 둘이 다 닫히면 곁 창(개요 막대·줄 자세히)도 - 그것만 남은 탭이 닫혀야 예전처럼
      -- TabClosed 가 짝을 놓고 트리로 돌아간다
      if not v.inline then
        vim.schedule(function()
          cmp.orphans(v)
        end)
      end
    end
    -- 트리 창이 닫히면 그 위의 경로 줄 창도 (경로 줄만 남은 탭이 되지 않게)
    for _, s in pairs(sessions) do
      if w and w == s.win_l and s.hwin and api.nvim_win_is_valid(s.hwin) then
        vim.schedule(function()
          tr.head_orphan(s)
        end)
      end
    end
  end,
})
-- 편집 창에 떠 있는 파일을 다른 창·탭에 띄우면 nvim 은 그 버퍼가 떠 있는 창(편집 창)의 옵션을 새 창에
-- 입힌다: 비교의 머리(' A: …' winbar)에 diff·scrollbind·cursorbind·foldmethod=diff 까지 따라왔다
-- (:tabnew 파일, :tabnew 뒤 :e, :vsplit 파일, neo-tree 의 Enter, Tab/Tab 의 vimdiff). 버퍼를 바꿀 때 머리를
-- 걷는 것(open_pair, finish)은 내려간 버퍼에만 듣는다. 그래서 들어온 쪽에서 걷는다: 두 편집 창이 아닌 창이
-- 편집 창과 같은 머리를 달고 있으면 거기서 받은 옵션이다 - 머리를 걷고 diff 였으면 :diffoff (그 창만,
-- 묶기·접기도 diff 전으로). :diffoff 가 남긴 manual 접기와 'foldenable' 은 undiff_folds 가 되돌린다.
-- 사용자가 :diffsplit·vimdiff 로 켜는 diff 는 그 명령이 버퍼를 띄운 뒤에 켜므로 남는다.
-- 머리가 다른(사용자가 켠) diff 창은 건드리지 않는다.
-- 비교 색(winhighlight - VimIdeDirDiff* 로 잇는 것)도 같다: 비교 창이 아닌 창이 그것을 달고 있으면 물려받은
-- 것이라 걷는다 (그 창에 같은 파일이 떠도 보통 색으로)
local function strip_inherited()
  if next(sessions) == nil then
    return
  end
  -- 트리와 곁 창(경로 줄·개요 막대·줄 자세히)은 제 창 옵션(winhighlight·cursorline 등)을 단 우리 창이다
  local ft = vim.bo.filetype
  if ft == 'vimidedirdiff' or cmp.FT[ft] then
    return
  end
  local w = api.nvim_get_current_win()
  local wb = vim.wo[w].winbar
  local hl = vim.wo[w].winhighlight:find('VimIdeDirDiff', 1, true) ~= nil
  if wb == '' and not hl then
    return
  end
  local views = all_views()
  local from = false
  for _, v in ipairs(views) do
    if w == v.win_a or w == v.win_b then
      return
    end
    for _, x in ipairs({ v.win_a, v.win_b }) do
      if wb ~= '' and api.nvim_win_is_valid(x) and vim.wo[x].winbar == wb then
        from = true
      end
    end
  end
  if from then
    pcall(vim.cmd, 'setlocal winbar<')
  end
  if hl then
    pcall(vim.cmd, 'setlocal winhighlight<')
    if vim.wo[w].winhighlight:find('VimIdeDirDiff', 1, true) then
      set_wo(w, 'winhighlight', '')
    end
  end
  if from or hl then
    -- 비교 창에만 단 화살표 자리(signcolumn)와 빗금(fillchars)도 물려받았다 (diff_whl). 없는 쪽 창에서
    -- 갈랐으면 꺼 둔 줄 번호·지금 줄 색·colorcolumn 도 (cmp.gone_side)
    pcall(vim.cmd, 'setlocal signcolumn< fillchars<')
    if vim.wo[w].number ~= vim.go.number or vim.wo[w].cursorline ~= vim.go.cursorline then
      pcall(vim.cmd, 'setlocal number< relativenumber< cursorline< colorcolumn<')
    end
  end
  if (from or hl) and vim.wo[w].diff then
    pcall(vim.cmd, 'diffoff')
    undiff_folds()
    pcall(vim.cmd, 'setlocal foldlevel<')   -- 보기의 foldlevel(모두 보이기 99)도 물려받았다
  end
end
api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'WinEnter' }, {
  group = group,
  callback = strip_inherited,
})
-- 비교가 연 버퍼를 사용자가 비교 탭 밖에서 띄우면 사용자 것이 된다 - 치우지 않는다
api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  callback = function(ev)
    -- 트리 탭과 비교 탭 안은 비교의 것이다
    local tab = api.nvim_get_current_tabpage()
    if sessions[tab] or view_of_tab(tab) then
      return
    end
    vim.b[ev.buf].vimide_dirdiff = nil
    for _, s in pairs(sessions) do
      s.opened[ev.buf] = nil
      s.unload[ev.buf] = nil   -- 도로 내려 둘 버퍼도: 사용자가 쓰기 시작했다
    end
  end,
})
-- 비교 창에 짝이 아닌 버퍼를 띄우면(:e 다른 파일, :b, <C-^>) 그 창의 비교 색과 머리를 걷는다 - 그
-- 파일은 짝이 아니다. 짝의 버퍼로 돌아오면 다시 단다. 채우는 동안(fill)은 보지 않는다
api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  callback = function(ev)
    local w = api.nvim_get_current_win()
    local v = view_of_win(w)
    if not v or v.filling or not v.rel then
      return
    end
    local side = w == v.win_a and 'a' or 'b'
    if ev.buf == v['buf_' .. side] then
      diff_whl(w, not v.bin and side or nil)
      cmp.gone_side(v)
      set_heads(v)
    else
      diff_whl(w, nil)
      set_wo(w, 'winbar', '')
      cmp.ungone(w)
    end
    -- 화살표·연보라·개요 막대·줄 자세히도 (짝이 아닌 쪽은 비운다 - cmp.pbuf)
    cmp.kick(v, true)
  end,
})
-- 비교 중인 두 디렉터리 안의 파일을 :w 로 저장하면 그 항목만 다시 본다 (트리 복사처럼).
-- 없었을 때는 편집 창에서 두 파일을 같게 만들어 저장해도 R 을 누를 때까지 트리가 옛 판정·
-- 크기·날짜(≠)를 그대로 보였다
api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function(ev)
    if next(sessions) == nil then
      return
    end
    local full = vim.fn.fnamemodify(ev.match, ':p')
    local rp = real(full)
    -- 어느 이름으로 찾는지는 rels_in 에 (트리 복사의 on_copied 와 같이 쓴다)
    local link = (uv.fs_lstat(full) or {}).type == 'link'
    for _, s in pairs(sessions) do
      local paths = rels_in(s, full, rp, link)
      if #paths > 0 then
        send(s, { cmd = 'refresh', paths = paths })
      end
    end
  end,
})
api.nvim_create_autocmd('WinResized', {
  group = group,
  callback = function()
    local wins = vim.v.event.windows or {}
    for _, s in pairs(sessions) do
      if api.nvim_win_is_valid(s.win_l) and vim.tbl_contains(wins, s.win_l) then
        render(s)
      end
    end
    -- 개요 막대의 높이가 바뀌면 칸을 다시 나눈다. 비교 창의 너비가 바뀌면 창 머리에 넣을 정보도. 곁 창의
    -- 크기가 바뀌었으면 되돌린다 (cmp.keep_size)
    for _, v in ipairs(all_views()) do
      if (v.ov and vim.tbl_contains(wins, v.ov.win)) or (v.ld and vim.tbl_contains(wins, v.ld.win)) then
        cmp.keep_size(v)
      end
      if v.ov and vim.tbl_contains(wins, v.ov.win) then
        cmp.kick(v, true)
      end
      if vim.tbl_contains(wins, v.win_a) or vim.tbl_contains(wins, v.win_b) then
        set_heads(v)
      end
    end
  end,
})
-- 터미널 크기가 바뀌면 비교 탭의 두 창을 다시 같은 너비로 (nvim 은 늘어난 칸을 오른쪽 창에 모두 준다 -
-- Beyond Compare 처럼 반반. 그 사이 손으로 바꾼 너비도 반반으로 돌아간다). 다른 탭의 것은 그 탭에 들어갈
-- 때 (v.rebal - 아래 TabEnter): 다른 탭의 창 너비를 지금 바꾸면 그 탭에 들어갈 때 nvim 이 늘어난 칸을 다시
-- 오른쪽 창에 주어 A=77, B=118 이 되었다
function cmp.rebalance(v)
  v.rebal = nil
  if not v.inline and api.nvim_win_is_valid(v.win_a) and api.nvim_win_is_valid(v.win_b) then
    local tw = api.nvim_win_get_width(v.win_a) + api.nvim_win_get_width(v.win_b)
    pcall(api.nvim_win_set_width, v.win_a, math.floor(tw / 2))
  end
end
api.nvim_create_autocmd('VimResized', {
  group = group,
  callback = function()
    local here = api.nvim_get_current_tabpage()
    for _, v in ipairs(all_views()) do
      if v.tab == here then
        cmp.rebalance(v)
      elseif not v.inline then
        v.rebal = true
      end
    end
  end,
})
-- 비교 탭의 곁 (cmp): 커서·화면이 움직이면 화살표·줄 자세히·개요 막대의 보이는 곳을, 글이 바뀌거나
-- diff 가 다시 계산되면 차이를 다시 센다. 모두 모아서 (cmp.kick)
api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  group = group,
  callback = function()
    if next(sessions) == nil then
      return
    end
    local w = api.nvim_get_current_win()
    local v = view_of_win(w)
    if v then
      v.cur_win = w
      cmp.kick(v)
    end
  end,
})
api.nvim_create_autocmd('WinScrolled', {
  group = group,
  callback = function()
    if next(sessions) == nil then
      return
    end
    local v = view_of_tab(api.nvim_get_current_tabpage())
    if v then
      cmp.kick(v)
    end
  end,
})
api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'DiffUpdated' }, {
  group = group,
  callback = function(ev)
    if next(sessions) == nil then
      return
    end
    local v = view_of_tab(api.nvim_get_current_tabpage())
    -- 글이 바뀐 것은 짝의 버퍼일 때만: 그 탭의 다른 버퍼(pair_tab = 0 에서 훑는 동안 다시 그리는 트리 등)가
    -- 바뀔 때마다 두 버퍼를 다시 견주었다
    if v and (ev.event == 'DiffUpdated' or ev.buf == cmp.pbuf(v, 'a') or ev.buf == cmp.pbuf(v, 'b')) then
      cmp.kick(v, true)
    end
  end,
})
-- 곁 창(경로 줄·개요 막대·줄 자세히)에 들어오면 돌려보낸다. 비교 창에 들어오면 그 창이 '지금 쪽' (줄 자세히)
api.nvim_create_autocmd('WinEnter', {
  group = group,
  callback = function()
    if next(sessions) == nil then
      return
    end
    local w = api.nvim_get_current_win()
    if cmp.FT[vim.bo[api.nvim_win_get_buf(w)].filetype] then
      local click = cmp.mouse
      vim.schedule(function()
        cmp.bounce(w, click)
      end)
      return
    end
    local v = view_of_win(w)
    if v then
      v.cur_win = w
      cmp.kick(v)
    end
  end,
})
-- :w 하면 창 머리의 수정 일시·크기를 다시 (디스크의 것)
api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function(ev)
    for _, v in ipairs(all_views()) do
      local hit = false
      for _, side in ipairs({ 'a', 'b' }) do
        local w = v['win_' .. side]
        local p = v.path and v.path[side]
        if p and api.nvim_win_is_valid(w) and api.nvim_win_get_buf(w) == ev.buf then
          v.info = v.info or {}
          v.info[side] = uv.fs_stat(p)
          hit = true
        end
      end
      if hit then
        set_heads(v)
      end
    end
  end,
})
-- 'laststatus' 가 바뀌면 칸 제목의 자리(경로 줄 창의 상태줄 / 트리의 winbar)도 바뀐다
api.nvim_create_autocmd('OptionSet', {
  group = group,
  pattern = 'laststatus',
  callback = function()
    vim.schedule(function()
      for _, s in pairs(sessions) do
        render(s)
      end
    end)
  end,
})
-- 끝낼 때 비교 탭을 모두 닫는다. 이 VimLeavePre 가 vimidesession 의 것보다 먼저 돈다
-- (plugin/ 을 이름 순으로 읽는다) - 닫지 않았더니 세션에 비교 탭(두 파일, diff 도 트리도
-- 없이)이 저장되어 다음에 열 때 되살아났고, 그때는 보통 :edit 이라 BufRead 훅까지 돌았다
api.nvim_create_autocmd('VimLeavePre', {
  group = group,
  callback = function()
    local all = {}
    for _, s in pairs(sessions) do
      all[#all + 1] = s
    end
    for _, s in ipairs(all) do
      pcall(finish, s, true)
    end
  end,
})

-- vim-dirdiff 가 없어도 (PlugInstall 전 등) :DirDiff 는 이 트리로. 있으면 dirdifftab.vim 이
-- 그 플러그인을 읽은 뒤에 같은 것으로 다시 정한다
if vim.fn.exists(':DirDiff') ~= 2 and (tonumber(vim.g.vimide_dirdiff_view) or 1) ~= 0 then
  api.nvim_create_user_command('DirDiff', function(o)
    if #o.fargs ~= 2 then
      return say('디렉터리 두 개를 주세요 - :DirDiff <A> <B>', vim.log.levels.WARN)
    end
    M.open(o.fargs[1], o.fargs[2])
  end, { nargs = '*', complete = 'dir', desc = '두 디렉터리 비교 (나란한 트리)' })
end

return M
