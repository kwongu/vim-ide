-- vimidesession.lua - :qa 로 나간 자리에서 다시 시작한다 (nvim 전용)
--
--   nvim            지금까지와 똑같이 뜬다. 아무것도 되살리지 않는다.
--   nvim +Restore   지난번 :qa 자리로 돌아간다 (창 배치 + 옆 창들).
--
-- 저장은 자동(:qa 할 때), 되살리기는 물어봤을 때만.
--
-- 창 배치와 파일과 커서는 vim 이 원래 가진 :mksession 이 다 한다. 이 파일이
-- 하는 일은 ':mksession 이 담지 못하는 것' 둘뿐이다.
--
--   1. 저장 직전에 패널을 닫는다. 패널 버퍼는 nofile 스크래치라 :mksession 이
--      'enew | file RelationView' 로 적어 버린다. 그대로 되살리면 프로젝트
--      안을 가리키는 '쓸 수 있는 빈 파일 버퍼'가 생기고, :wa 한 번이면
--      RelationView 라는 파일이 커널 트리에 진짜로 만들어진다. 게다가 그
--      유령 버퍼가 이름을 물고 있어서(E95) 다음에 여는 패널이 영영
--      [No Name] 이 된다. 닫고 찍은 세션에는 enew 가 한 줄도 없다.
--
--   2. 무엇이 떠 있었는지를 세션 옆에 따로 적어 두었다가 명령으로 다시 연다
--      (RelationView / neo-tree / aerial / tagbar / NERDTree / quickfix).
--
-- vim 8.1 은 plugin/*.lua 를 읽지 않는다. 이 파일이 .lua 라는 것 자체가
-- has('nvim') 가드다 - .vimrc 는 한 줄도 건드리지 않았다. 이 저장소가 이미
-- relationview.lua, projectfiles.lua 등 열 몇 개를 같은 방식으로 싣고 있고
-- 그것이 서버에서 매일 도는 것이 그 증거다.

if vim.g.loaded_vimide_session == 1 then
  return
end
vim.g.loaded_vimide_session = 1

-- 전체 스위치. .vimrc 는 plugin/ 보다 먼저 읽히므로 거기서 끄면 명령도
-- 만들지 않는다.
if (tonumber(vim.g.vimide_session) or 1) == 0 then
  return
end

local api, fn = vim.api, vim.fn
local uv = vim.uv or vim.loop
local M = {}

local SIDECAR_VERSION = 1

-- 되살리는 중이라는 표시. 이것이 없으면, 복원이 반쯤 끝난 상태에서 나가거나
-- (에러, :qa, 크래시) 하면 그 반쪽짜리 배치가 VimLeavePre 를 타고 멀쩡한
-- 세션을 덮어쓴다. 실제로 시제품 시험 중에 당한 사고다.
local restoring = false

-- ---------------------------------------------------------------------------
-- 어디에 두나
-- ---------------------------------------------------------------------------
-- 소스 트리에는 한 글자도 쓰지 않는다. <root>/.tags/ 는 preset 과 색인이
-- 사는 자리라 손대지 않는다 - 그 데이터는 실제로 날아간 적이 있고, 나갈
-- 때마다 덮어쓰는 파일을 그 사고 반경 안에 둘 이유가 없다. .tags 는 색인
-- 모드를 고르기 전에는 아예 없기도 하다.
--
-- stdpath('state') 는 소스 트리 밖이라 커널 저장소의 git status 에 구조적으로
-- 뜰 수 없고, 'rm -rf .tags' 나 gtags 재색인에도 살아남는다.
local function state_dir()
  local d = vim.g.vimide_session_dir
  if type(d) == 'string' and d ~= '' then
    return (fn.fnamemodify(fn.expand(d), ':p'):gsub('/+$', ''))
  end
  return fn.stdpath('state') .. '/vim-ide/sessions'
end

-- 세션의 주인은 cwd 가 아니라 '프로젝트 루트'다. 같은 SDK 를 여러
-- 디렉터리에서 열어도 세션은 하나여야 하기 때문이다.
local function project_root()
  if type(_G.projectfiles_root_of) == 'function' then
    local ok, r = pcall(_G.projectfiles_root_of, fn.getcwd())
    if ok and type(r) == 'string' and r ~= '' then
      return (fn.fnamemodify(r, ':p'):gsub('/+$', ''))
    end
  end
  return (fn.fnamemodify(fn.getcwd(), ':p'):gsub('/+$', ''))
end

-- 경로 하나를 파일 이름 하나로. 눈으로 알아볼 수 있게 뒤쪽을 남기고,
-- 길이(255바이트)와 충돌은 해시가 책임진다.
--
-- 구분자로 '%' 를 쓰지 않는다. 'nvim -S <파일>' 이 파일 이름 안의 % 와 # 를
-- '지금 버퍼 / 직전 버퍼'로 펴 버려서 아래가 난다(실측):
--   E499: Empty file name for '%' or '#', only works with ":p:h"
-- '+' 는 셸도 vim 도 그냥 글자로 본다. 이 한 글자가 -S 입구를 살린다.
local function slug_for(root)
  local full = (fn.fnamemodify(root, ':p'):gsub('/+$', ''))
  local tail = (full:gsub('[^%w%-%._]', '+'))
  if #tail > 80 then
    tail = tail:sub(-80)
  end
  return tail .. '-' .. fn.sha256(full):sub(1, 12)
end

-- <base>.vim  : :mksession 이 쓴 세션 (창 배치, 파일, 커서, 폴드, 탭)
-- <base>x.vim : 그 세션이 끝에서 스스로 source 하는 'extra' 파일 (:h mksession).
--               패널 상태를 여기 실으면 'nvim -S <파일>' 로 열어도 옆 창이
--               따라온다. SessionLoadPost 를 쓰지 않는 이유는 그것이 버퍼마다
--               한 번씩(6버퍼 세션에서 6번) 불리기 때문이다. x.vim 은 딱 한 번.
local function paths()
  local root = project_root()
  local base = state_dir() .. '/' .. slug_for(root)
  return root, base .. '.vim', base .. 'x.vim'
end

-- ---------------------------------------------------------------------------
-- 지금 무엇이 떠 있나
-- ---------------------------------------------------------------------------
-- RelationView 는 자기 상태를 알려 준다(relationview.lua 의
-- _G.relationview_state). 없는 버전이면 화면을 훑어서 흉내 낸다 - 원래
-- current_mode() 도 기억이 아니라 화면에서 읽는다.
local function rv_state()
  if type(_G.relationview_state) == 'function' then
    local ok, st = pcall(_G.relationview_state)
    if ok and type(st) == 'table' then
      return st
    end
  end
  local panel = type(_G.relationview_panel_win) == 'function'
      and _G.relationview_panel_win() or nil
  local ctx = type(_G.relationview_ctx_win) == 'function'
      and _G.relationview_ctx_win() or nil
  local mode = 'off'
  if panel and ctx then
    mode = 'both'
  elseif panel then
    mode = 'relation'
  elseif ctx then
    mode = 'context'
  end
  -- 세로 전체 미리보기는 작은 쪽과 '같은 버퍼'를 본다. ctx_win 이 아닌 다른
  -- 창이 그 버퍼를 들고 있으면 그게 큰 쪽이다.
  local big, ctxbuf = false, ctx and api.nvim_win_get_buf(ctx) or nil
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    if w ~= ctx and (b == ctxbuf
        or fn.fnamemodify(api.nvim_buf_get_name(b), ':t') == 'RelationView-Context') then
      big = true
    end
  end
  -- RelationView 가 자기 열에 얹은 트리는 패널이나 미리보기와 '같은 화면 열'에
  -- 선다. 그것으로 F9 의 왼쪽 트리와 가른다 - aerial 이 켜져 있으면 왼쪽
  -- 트리도 1열이 아니라서 위치만으로는 못 가른다.
  local col = {}
  if panel then col[fn.win_screenpos(panel)[2]] = true end
  if ctx then col[fn.win_screenpos(ctx)[2]] = true end
  local tw
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(w)].filetype == 'neo-tree'
        and col[fn.win_screenpos(w)[2]] then
      tw = w
    end
  end
  -- 트리를 못 찾았을 때 '사용자가 껐다'라고 단정하지 않는다. accessor 없이는
  -- \lt 로 끈 것인지 그냥 안 뜬 것인지 알 수 없다 - 모르면 tree_off 를 적지
  -- 않고, 되살릴 때 아무것도 하지 않는다.
  return { mode = mode, tree = tw and true or nil, tree_win = tw, big = big }
end

function M.capture()
  local st = rv_state()
  local p = {
    v        = SIDECAR_VERSION,
    rv_mode  = st.mode or 'off',
    -- true 는 '사용자가 \lt 로 껐다'일 때만이다(relationview 의 s.tree_off).
    -- 그냥 안 보이는 것과는 다르다.
    rv_tree_off = st.tree_off and true or false,
    rv_big   = st.big and true or false,
    neotree  = false,
    aerial   = false,
    tagbar   = false,
    nerdtree = false,
    quickfix = false,
  }

  local rv_tree_win = st.tree_win
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[api.nvim_win_get_buf(w)].filetype
    if ft == 'neo-tree' then
      -- RelationView 가 자기 열 위에 얹은 트리는 세지 않는다.
      -- RelationViewMode 가 같이 세워 주기 때문이다.
      if w ~= rv_tree_win then
        p.neotree = true     -- F9 의 왼쪽 트리
      end
    elseif ft == 'aerial' then
      p.aerial = true
    elseif ft == 'tagbar' then
      p.tagbar = true
    elseif ft == 'nerdtree' then
      p.nerdtree = true
    end
  end

  for _, wi in ipairs(fn.getwininfo()) do
    if wi.quickfix == 1 and wi.loclist == 0 then
      p.quickfix = true
    end
  end
  -- 옆 창이 하나라도 있었나. 되살린 뒤에 편집 창을 고르게 펴야 할지를
  -- 이것으로 정한다 (아래 reopen 의 주석).
  p.had_panels = (p.rv_mode ~= 'off') or p.neotree or p.aerial
      or p.tagbar or p.nerdtree or p.quickfix

  -- 돌아왔을 때 커서가 앉을 자리. 목록(quickfix)이나 패널이 아니라
  -- '마지막으로 글을 보던 창'이다.
  local ew = 0
  if type(_G.vimide_last_edit_win) == 'function' then
    local ok, w = pcall(_G.vimide_last_edit_win)
    if ok and type(w) == 'number' then
      ew = w
    end
  end
  if ew == 0 or not api.nvim_win_is_valid(ew) then
    ew = api.nvim_get_current_win()
  end
  local eb = api.nvim_win_get_buf(ew)
  if vim.bo[eb].buftype == '' and api.nvim_buf_get_name(eb) ~= '' then
    p.edit_file = api.nvim_buf_get_name(eb)
    p.edit_line = api.nvim_win_get_cursor(ew)[1]
  end
  return p
end

-- ---------------------------------------------------------------------------
-- 저장하기 전에 치운다
-- ---------------------------------------------------------------------------
function M.close_panels()
  -- RelationView 가 먼저다. A.close() 가 자기 열의 트리와 두 미리보기를
  -- 함께 치운다. Neotree close 를 먼저 하면 그 트리만 떨어져 나온다.
  pcall(vim.cmd, 'silent! RelationViewMode off')
  pcall(vim.cmd, 'silent! Neotree close')
  pcall(vim.cmd, 'silent! AerialClose')
  pcall(vim.cmd, 'silent! TagbarClose')
  pcall(vim.cmd, 'silent! NERDTreeClose')
  pcall(vim.cmd, 'silent! cclose')
  pcall(vim.cmd, 'silent! lclose')

  -- telescope 같은 떠 있는 창은 :mksession 이 아예 무시하지만, 남아 있으면
  -- 아래 정리에 걸리적거리니 먼저 닫는다.
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= '' then
      pcall(api.nvim_win_close, w, true)
    end
  end
  -- 그래도 남은 스크래치/터미널 창. 되살려서 좋을 것이 하나도 없다.
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_is_valid(w) and #api.nvim_tabpage_list_wins(0) > 1 then
      local bt = vim.bo[api.nvim_win_get_buf(w)].buftype
      if bt == 'terminal' or bt == 'nofile' or bt == 'quickfix' or bt == 'prompt' then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- 저장
-- ---------------------------------------------------------------------------
-- 두 nvim 이 같은 프로젝트에서 같이 나갈 수 있다. VimLeavePre 는 막을 수
-- 없으니 대신 '찢어지지 않게' 만든다: 임시 파일에 쓰고 rename 으로 갈아
-- 끼우면(POSIX rename 은 원자적) 반쯤 쓰인 파일은 생길 수 없다. 늦게 나간
-- 쪽이 이기고, 직전 것은 .bak 에 남는다.
local function write_atomic(path, lines)
  local tmp = ('%s.%d.tmp'):format(path, fn.getpid())
  if fn.writefile(lines, tmp) ~= 0 then
    return false
  end
  local ok = uv.fs_rename(tmp, path)
  if not ok then
    pcall(fn.delete, tmp)
  end
  return ok and true or false
end

-- 저장할 값어치가 있나.
-- 같은 프로젝트에서 'nvim 파일하나' 를 10초 열었다 닫는 일이 제일 흔한데,
-- 그때 애써 짜 둔 배치가 창 하나짜리로 덮이면 안 된다.
local function worth_saving(p, spath)
  if #api.nvim_tabpage_list_wins(0) > 1 then
    return true
  end
  if p.had_panels then
    return true
  end
  return fn.filereadable(spath) == 0   -- 처음 만드는 것은 그냥 저장
end

-- VimL 작은따옴표 문자열 리터럴. 안의 ' 만 겹쳐 주면 끝이다.
local function vimstr(s)
  return "'" .. tostring(s):gsub("'", "''") .. "'"
end

function M.save(opts)
  opts = opts or {}
  -- 복원 도중의 종료가 멀쩡한 세션을 덮어쓰지 못하게.
  if restoring then
    return false
  end
  if not opts.force and (tonumber(vim.g.vimide_session_save) or 1) == 0 then
    return false
  end
  local root, spath, xpath = paths()
  local ok, panels = pcall(M.capture)
  if not ok or type(panels) ~= 'table' then
    return false
  end
  if not opts.force and not worth_saving(panels, spath) then
    return false
  end

  fn.mkdir(fn.fnamemodify(spath, ':h'), 'p')
  -- 직전 것은 한 벌 남긴다. 덮어써서 잃는 사고가 제일 흔하다.
  if fn.filereadable(spath) == 1 then
    pcall(fn.rename, spath, spath .. '.bak')
    pcall(fn.rename, xpath, xpath .. '.bak')
  end

  pcall(M.close_panels)

  -- 인자 목록은 버린다. :mksession 이 '$argadd a.c' 를 적는데, 이 설정의
  -- wildignore(*/tmp/*, *.zip, *.so ...) 에 걸리는 경로면 되살릴 때마다
  -- E479: No match 를 뱉는다(실측). 어차피 창마다 edit 줄이 따로 적힌다.
  pcall(vim.cmd, 'silent! %argdelete')

  -- options/localoptions 는 넣지 않는다. 넣으면 세션이 .vimrc 를 이겨서
  -- runtimepath 와 매핑 466줄이 얼려진다 - 설정을 고쳐도 반영이 안 된다.
  -- globals 도 뺀다: 대문자로 시작하는 String/Number 만 담기므로 이 설정의
  -- g:relationview_* / g:vimide_* 는 하나도 못 담고, 남의 플러그인 변수
  -- 169줄만 끌고 온다. blank(빈 창), terminal(죽은 셸), resize/winpos
  -- (터미널 크기를 강제로 되돌린다)도 뺀다. winsize 는 비율로 적히므로
  -- 창 크기가 달라도 알아서 맞는다. skiprtp 는 vim 8.1 에 없으니 아예
  -- 쓰지 않는다.
  local so = vim.o.sessionoptions
  vim.o.sessionoptions = 'buffers,curdir,folds,help,tabpages,winsize'
  local wrote = pcall(vim.cmd, 'mksession! ' .. fn.fnameescape(spath))
  vim.o.sessionoptions = so
  if not wrote then
    return false
  end

  -- :VimIdeSessionSave 로 '살아 있는 판'을 저장한 것이면 방금 닫은 패널을
  -- 도로 세운다. 나가는 길(VimLeavePre)이면 그럴 필요가 없다.
  if vim.v.exiting == vim.NIL then
    pcall(M.reopen, panels)
  end

  -- 세션 파일은 마지막에 '<이름>x.vim' 이 있으면 스스로 source 한다.
  -- 그 자리에 패널 상태를 싣는다. json 이라 옛/깨진 파일도 조용히 버릴 수 있다.
  write_atomic(xpath, {
    '" vim-ide session extra - 자동 생성, 손으로 고치지 않는다',
    'try',
    '  let g:vimide_session_panels = json_decode(' .. vimstr(vim.json.encode(panels)) .. ')',
    '  let g:vimide_session_root = ' .. vimstr(root),
    -- 'nvim -S <파일>' 로 들어온 길에도 표시를 남긴다. 그래야 그 뒤에
    -- :Restore 를 눌러도 두 번 되살리지 않는다.
    '  let g:vimide_session_restored = 1',
    'catch',
    '  let g:vimide_session_panels = {}',
    'endtry',
    'if exists("*VimIdeSessionQueuePanels") | call VimIdeSessionQueuePanels() | endif',
  })
  return true
end

-- ---------------------------------------------------------------------------
-- 되살리기
-- ---------------------------------------------------------------------------
-- 창을 다시 재는 동안만 vim 의 '알아서 넓혀 주기'를 끈다.
--   winwidth = 20 (기본값) 은 포커스가 간 창을 20칸으로 넓힌다. 좁은
--   터미널에서 이것 때문에 마지막 창이 1칸으로 찌부러진다(실측 120칸:
--   20/20/1). equalalways 는 split 마다 스스로 고르게 펴서 우리와 싸운다.
local function frozen(f)
  local ww, wh, ea = vim.o.winwidth, vim.o.winheight, vim.o.equalalways
  vim.o.winwidth, vim.o.winheight, vim.o.equalalways = 1, 1, false
  pcall(f)
  vim.o.winwidth, vim.o.winheight, vim.o.equalalways = ww, wh, ea
end

-- neo-tree 와 aerial 은 창을 비동기로 만든다. 세션이 다 앉은 뒤에 연다.
function M.reopen(p)
  if type(p) ~= 'table' or tonumber(p.v) ~= SIDECAR_VERSION then
    return
  end
  if p.nerdtree then
    pcall(vim.cmd, 'call NERDTreeOnlyRight()')
  end
  -- aerial 을 neo-tree 보다 먼저 연다. aerial 은 placement='edge' 라 나중에
  -- 열면 맨 왼쪽을 차지해 순서가 'aerial | neo-tree' 로 뒤집힌다 - 저장 때
  -- (F10 다음 F9)는 'neo-tree | aerial' 이었다.
  --
  -- .vimrc 의 TagbarOnly() 를 부르지 않는다. 그 함수는 :Neotree close 를
  -- 하는데, relationview.lua 2847 줄의 주석대로 그것이 RelationView 열의
  -- 트리까지 데려간다. 여는 순서에 기대는 대신 의존을 없앤다.
  if p.aerial then
    pcall(vim.cmd, 'silent! AerialOpen')
  end
  if p.tagbar then
    pcall(vim.cmd, 'silent! TagbarOpen')
  end
  if p.neotree then
    pcall(vim.cmd, 'silent! Neotree show left')
  end
  -- RelationView 는 옆 창 중 마지막. 남은 편집 창을 기준으로 폭을 잡는다.
  if p.rv_mode and p.rv_mode ~= 'off' then
    pcall(vim.cmd, 'silent! RelationViewMode ' .. p.rv_mode)
    if p.rv_tree_off then
      pcall(vim.cmd, 'silent! RelationViewTree')   -- 껐던 사람은 꺼진 채로
    end
    if p.rv_big then
      pcall(vim.cmd, 'silent! RelationViewBigContext')
    end
  end
  -- quickfix 는 제일 마지막. 이 설정은 quickfix 를 EDIT 쪽에 여니까
  -- RelationView 열이 먼저 서 있어야 자리가 정해진다. 목록 자체는
  -- 되살리지 않는다 - 색인이 바뀌었으면 줄 번호가 거짓말을 한다.
  if p.quickfix then
    pcall(vim.cmd, 'silent! botright copen')
  end

  vim.defer_fn(function()
    -- 편집 창을 고르게 편다.
    --
    -- :mksession 은 창 크기를 '패널이 없던 때'의 비율로 적는다. 그래서
    -- 패널이 자리를 도로 가져가면 그 손해를 마지막 프레임이 혼자 뒤집어쓴다
    -- (실측: 28/28 로 저장한 것이 28/17 로 돌아왔다).
    --
    -- 고르게 펴는 것이 맞는 답인 이유: 이 설정은 옆 창을 켜고 끌 때마다
    -- VimIdeBalanceSoon() 으로 편집 창을 이미 고르게 편다(.vimrc 2723,
    -- NeoTreeOnlyLeft / TagbarOnly / NERDTreeOnlyRight 가 전부 부른다).
    -- 즉 패널이 하나라도 떠 있던 판이면 저장 시점의 편집 창은 이미 고른
    -- 상태였다. 되살릴 때 다시 고르게 펴면 그때 그대로가 된다.
    --
    -- 패널이 하나도 없었으면 손대지 않는다. 그때는 :mksession 의 비율이
    -- 처음부터 정확하고, 사용자가 손으로 만든 불균등 배치를 지울 이유가 없다.
    --
    -- VimIdeBalance() 가 아니라 'wincmd =' 를 직접 부른다. 저 함수는
    -- g:vimide_balance_on_toggle = 0 이면 아무것도 하지 않는데, 그 스위치는
    -- '토글할 때 펴지 마라'는 뜻이지 '세션을 비뚤게 되살려라'가 아니다.
    -- 옆 창들은 winfixwidth/winfixheight 라 이 명령이 건드리지 않는다.
    if p.had_panels then
      frozen(function() vim.cmd('wincmd =') end)
    end

    if p.edit_file and p.edit_file ~= '' then
      for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
        local b = api.nvim_win_get_buf(w)
        if vim.bo[b].buftype == '' and api.nvim_buf_get_name(b) == p.edit_file then
          pcall(api.nvim_set_current_win, w)
          if p.edit_line then
            pcall(api.nvim_win_set_cursor, w,
              { math.max(1, tonumber(p.edit_line) or 1), 0 })
          end
          break
        end
      end
    end
    restoring = false
  end, 250)
end

-- x.vim 이 부르는 입구. 아직 시작 중이면 VimEnter 로 미룬다.
function _G.VimIdeSessionQueuePanels()
  local p = vim.g.vimide_session_panels
  -- 옛/깨진 사이드카를 걸러낸다. json_decode 가 배열이나 숫자를 내놓을 수도
  -- 있으므로 표인지, 우리가 아는 형식인지까지 본다.
  if type(p) ~= 'table' or vim.islist(p) or tonumber(p.v) ~= SIDECAR_VERSION then
    return
  end
  restoring = true
  if vim.v.vim_did_enter == 1 then
    vim.defer_fn(function() M.reopen(p) end, 60)
  else
    api.nvim_create_autocmd('VimEnter', {
      once = true,
      callback = function() vim.defer_fn(function() M.reopen(p) end, 120) end,
      desc = 'vim-ide: 세션이 앉은 뒤에 옆 창을 다시 연다',
    })
  end
end
vim.cmd([[
function! VimIdeSessionQueuePanels() abort
  call luaeval('_G.VimIdeSessionQueuePanels()')
endfunction
]])

function M.restore()
  if vim.g.vimide_session_restored == 1 then
    vim.notify('vim-ide: 이미 세션을 되살렸습니다', vim.log.levels.INFO)
    return false
  end
  local _, spath = paths()
  if fn.filereadable(spath) == 0 then
    vim.notify('vim-ide: 저장된 세션이 없습니다 - ' .. spath, vim.log.levels.WARN)
    return false
  end
  -- 세션은 :silent only 로 시작한다. 고친 버퍼가 있으면 E37 이 난다.
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
      vim.notify('vim-ide: 저장하지 않은 버퍼가 있어 되살리지 않습니다',
        vim.log.levels.WARN)
      return false
    end
  end
  -- 'nvim +Restore foo.c' 는 세션을 편 뒤에 foo.c 를 편집 창에 연다.
  local args = {}
  for i = 0, fn.argc() - 1 do
    args[#args + 1] = fn.argv(i)
  end

  vim.g.vimide_session_restored = 1
  restoring = true
  -- 세션이 반쯤 열린 채로 나가도 멀쩡한 파일을 덮어쓰지 않게, 여기서부터
  -- reopen 의 꼬리까지 저장을 잠근다.

  local cwd_before = fn.getcwd()
  -- 옛 세션에 남아 있을 $argadd 가 wildignore 에 걸려 E479 를 뱉지 않게.
  local wi = vim.o.wildignore
  vim.o.wildignore = ''
  local ok, err = pcall(vim.cmd, 'silent! source ' .. fn.fnameescape(spath))
  vim.o.wildignore = wi
  if not ok then
    restoring = false
    vim.notify('vim-ide: 세션을 읽지 못했습니다 - ' .. tostring(err),
      vim.log.levels.WARN)
    return false
  end

  -- 세션은 sessionoptions 의 curdir 때문에 저장 당시 디렉터리로 :cd 한다.
  -- drivers/ 에서 열었는데 말없이 옮겨 가면 놀라는 사람이 있어서 끄는
  -- 스위치를 둔다.  let g:vimide_session_cd = 0
  if (tonumber(vim.g.vimide_session_cd) or 1) == 0 then
    pcall(vim.cmd, 'silent! cd ' .. fn.fnameescape(cwd_before))
  end

  -- 세션에 사이드카가 없었으면(옛 파일, 지워짐) 여기서 잠금을 푼다.
  -- 있었으면 QueuePanels 가 다시 걸고 reopen 의 꼬리가 푼다.
  if vim.g.vimide_session_panels == nil then
    restoring = false
  end

  if #args > 0 then
    vim.defer_fn(function()
      local w = type(_G.vimide_last_edit_win) == 'function'
        and _G.vimide_last_edit_win() or 0
      if w and w ~= 0 and api.nvim_win_is_valid(w) then
        pcall(api.nvim_set_current_win, w)
      end
      for _, a in ipairs(args) do
        pcall(vim.cmd, 'edit ' .. fn.fnameescape(a))
      end
    end, 400)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- 입구
-- ---------------------------------------------------------------------------
api.nvim_create_user_command('VimIdeRestore', function() M.restore() end,
  { desc = '지난번 :qa 자리로 되돌린다 (nvim +Restore)' })
-- 짧은 이름. ':R' 은 쓰지 않는다 - Rgrep/Regrep/Ragrep/RelationView* 등 R 로
-- 시작하는 명령이 이미 열댓 개라 exists(':R') 가 3(모호함)이다(실측).
api.nvim_create_user_command('Restore', function() M.restore() end,
  { desc = ':VimIdeRestore 의 짧은 이름' })
api.nvim_create_user_command('VimIdeSessionSave', function()
  if M.save({ force = true }) then
    local _, spath = paths()
    print('vim-ide: 세션 저장 - ' .. spath)
  end
end, { desc = '지금 배치를 이 프로젝트의 세션으로 저장한다' })
api.nvim_create_user_command('VimIdeSessionWhere', function()
  local root, spath, xpath = paths()
  print(('root = %s\n  %s%s\n  %s%s'):format(root,
    spath, fn.filereadable(spath) == 1 and '' or '   (없음)',
    xpath, fn.filereadable(xpath) == 1 and '' or '   (없음)'))
end, { desc = '이 프로젝트의 세션 파일 자리를 보여 준다' })

api.nvim_create_augroup('VimIdeSession', { clear = true })
api.nvim_create_autocmd('VimLeavePre', {
  group = 'VimIdeSession',
  callback = function() pcall(M.save) end,
  desc = 'vim-ide: 나가기 전에 창 배치와 옆 창을 적어 둔다',
})

_G.vimide_session = M
return M
