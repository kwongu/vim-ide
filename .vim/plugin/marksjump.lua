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
--   ★    이름 붙은 북마크. 이 SDK 의 것만 (아래). 최근 것이 위.
--   A-Z  파일을 넘나드는 표시. 어느 SDK 에서 열든 늘 뜬다.
--   a-z  파일 안의 표시. 어느 SDK 의 파일에서 찍은 것이든 다 - 지금 파일 것이 위.
--        이 nvim 에 그 파일의 버퍼가 있으면(읽어 둔 것, 한 번이라도 읽은 것 -
--        목록에 없어도, :bd 로 닫았어도) 그 버퍼의 것을, 버퍼가 없거나 한 번도
--        읽지 않은 파일(nvim 을 다시 켠 뒤 아직 안 연 파일, :badd)은 shada 파일에
--        적힌 것을 읽는다 (shada_marks - 읽기만 한다). 같은 파일이면 버퍼 쪽이
--        앞선다 - :bd 한 파일의 마크도 버퍼에 있고, nvim 은 닫을 때 그것을 적는다.
--        shada 를 못 읽으면 조용히 버퍼의 것만 보인다. 'shada' 가 비었거나
--        '0 이면(마크를 적지 않는다) 안 읽는다.
--   0-9 와 ' " ^ . [ ] 같은 자동 표시는 뺀다. 사람이 찍은 것이 아니라서
--   목록만 길어진다 - 특히 0-9 는 '최근에 닫은 파일'이라 이 설정에서는
--   .tags/files 같은 색인 내부 파일이 올라온다(실측: 열 줄 중 여섯 줄).
--   g:vimide_marks_auto = 1 이면 같이 보여준다.
--
-- SDK - ★ 목록은 SDK 마다 따로다
--   창을 연 편집 창의 파일(파일 창이 아니면 마지막 편집 창의 파일, 그것도
--   없으면 지금 디렉터리)이 든 SDK 의 북마크만 보여준다. SDK 루트는
--     1) '.repo' 를 가진 맨 위 디렉터리 (repo 로 받은 SDK, reposearch.lua).
--        안에 kernel/common, u-boot 처럼 제 색인을 가진 하위 프로젝트가 있어도,
--        위에 여러 SDK 를 품은 색인이 있어도 이것이 SDK 다.
--     2) 없으면 그 자리를 품은 가장 바깥 색인 루트 (RelationView·quickfix 가
--        경로를 줄이는 그 규칙. 안의 kernel/common 색인도 한 SDK 다)
--     3) 없으면 .git, .project, .root 를 가진 가장 바깥 디렉터리
--   셋 다 nvim 을 켠 자리(getcwd)를 보지 않는다 - 같은 파일은 늘 같은 SDK 다.
--   홈과 / 는 SDK 로 치지 않는다. 2) 나 3) 으로 정한 SDK 안의 '.repo' (3) 이면
--   그 안의 색인도)는 따로 선 SDK 다 - 그 아래 ★ 는 바깥 SDK 에 뜨지 않는다.
--   어느 SDK 에도 들지 않는 파일(~/.vimrc 같은)에서 열면 SDK 밖에서 담은
--   북마크만 뜬다. 경로는 링크를 푼 것으로도 견준다.
--   북마크를 담는 것은 그대로다 - 담은 파일의 SDK 에 들어간다.
--   창을 연 자리의 SDK 는 창을 열 때마다 새로 본다(그 사이 색인을 새로 만들었을
--   수 있다). 다른 북마크·마크의 디렉터리에 대해 알아낸 것(어느 SDK 인가, 링크를
--   푼 경로, 디렉터리마다 '.repo'·색인·.git 이 있나)은 세션 동안 기억한다 - 이
--   nvim 이 색인을 만들면(VimIdeIndexUpdated), 새로 본 것이 기억과 다르면, 창을
--   5분 동안 한 번도 열지 않았으면 버린다. 줄마다 git 을 부르지 않고, realpath 는
--   SDK 루트마다 한 번이다.
--
-- 경로와 칸
--   ★ 는 SDK 루트 기준 상대 경로 (kernel/common/sound/soc/telechips/tcc_i2s.c).
--   마크(A-Z, a-z)는 절대 경로 - 어느 SDK 의 파일인지 보인다. 'all' 로 본
--   다른 SDK·SDK 밖의 ★ 도 절대 경로다. 절대 경로는 SDK 루트의 링크를 푼 것을
--   보여준다 (/tmp 와 /private/tmp 가 다른 곳처럼 보이지 않게. 적어 둔 경로는
--   그대로).
--   어느 SDK 의 목록인지는 결과 창의 제목에도 적는다 (<C-s> 안내가 앞).
--   종류·이름, 경로, 줄, 그 줄의 글을 칸으로 맞춘다. 폭은 바이트가 아니라
--   화면 칸(strdisplaywidth - 한글은 한 글자가 두 칸)으로 잰다. 탭 문자는
--   쓰지 않는다 - 칸 폭이 탭 자리를 넘나들면 줄마다 어긋난다.
--   경로 칸이 그 줄의 글보다 먼저다(글은 미리보기에도 보인다). 그래도 넘치면
--   디렉터리 단위로 줄인다. 상대 경로는 처음과 끝을 남기고 가운데를 '…' 로
--   ('subcore/build/…/git/src/tsnd_arpc.c' - 첫 디렉터리와 파일 이름도 안
--   들어가면 앞을 '…/' 로 자른다). 절대 경로는 SDK 루트를 맨 나중에 줄인다 (clip_abs):
--     SDK 루트는 통째로, 그 아래만 앞을 자른다
--       '/home/B130111/work1/tsnd/dev/tsnd_2.1/Android14_IVI_1.1.0/…/telechips/tcc_i2s.c'
--     루트와 '…/파일 이름'도 안 들어가면 홈을 ~ 로 (루트의 나머지는 통째로)
--     그래도 안 되면 루트를 줄인다 - 이름이 같은 SDK 가 있으면(목록에 뜨든 안
--     뜨든: 모든 북마크·마크의 SDK, 창을 연 SDK) 둘이 갈리는 디렉터리는 남긴다
--     (root_labels). 결과 창이 아주 좁을 때(경로 칸 20칸 안팎)만 그것도 뺀다.
--   루트가 들어가지 않으면 이름 칸을 10칸까지 내준다 - 통째로, ~ 로, 가장 줄인
--   루트(SDK 이름은 다)로 들어가게 (그것으로 들어갈 때만). SDK 이름 가운데를
--   자르는 것은 그 뒤다.
--   지우거나(d) 범위를 바꾸면(<C-s>) 칸을 다시 잰다. 창이 닫힐 때까지 칸은 줄지
--   않고 갈리는 디렉터리도 그대로다 - 짝을 지워도 남은 줄의 모양이 바뀌지 않는다.
--
-- 고르면 '직전에 보던 EDIT 창'에서 연다. 곁창에서 불러도 트리나 패널이
-- 파일에 덮이지 않는다 (_G.vimide_last_edit_win 을 쓴다). 다른 파일의 a-z
-- 마크(shada 에서 읽은 것도)는 그 파일을 편집 창에 열고 마크 자리로 간다.
-- 열었는데 그 마크가 없으면(다른 nvim 이 그새 지웠다) 옛 줄로 가지 않고 알린다.
--
--   <Esc> 뒤 d   그 북마크나 마크를 지운다. a-z 는 그 마크의 버퍼에서(:bd 로
--                닫은 버퍼도), A-Z 는 전역으로. shada 에서 읽은 a-z 는 그 파일을
--                버퍼로 읽어(창은 그대로, 버퍼 목록에 오른다 - 읽어 둔 채 목록에
--                없는 버퍼는 nvim 이 닫을 때 그 파일의 a-z 를 하나도 적지 않는다)
--                거기서 지운다 - nvim 을 닫을 때 shada 에 적힌다. 알림은
--                "마크 'c' 를 지웠습니다 (파일을 버퍼로 읽음)". 노멀 모드에서만 -
--                검색창에서 d 를 치는 것은 글자 입력이어야 한다.
--   <C-d>        같은 것 (insert 모드에서도 - \fo, \fx 와 같은 키)
--   <C-s>        이 SDK 의 ★ 만 / 모든 SDK 의 ★ 를 이 창에서만 바꾼다
--                (<C-a> 는 vim-ide 의 tmux prefix 라 쓰지 않는다)
--
-- 옵션
--   g:vimide_marks_key   기본 ["<Leader>'", "<C-'>"] (글자 하나나 목록). '' 이면 키를
--                        걸지 않는다.
--                        <C-m> 은 터미널에서 <CR> 과 같은 바이트라 편집 창의
--                        Enter 를 가져간다 (.vimrc 설명)
--   g:vimide_marks_auto  1 이면 자동 표시(' " ^ . 등)도 보여준다
--   g:vimide_bookmarks_scope  'sdk'(기본) 이 SDK 의 ★ 만, 'all' 모든 SDK 의 ★
--                        (이 SDK 것이 먼저). 마크는 어느 쪽이든 다 뜬다.

if vim.g.loaded_vimide_marks then
  return
end
vim.g.loaded_vimide_marks = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api

-- 알림은 한 줄 안으로 (fitmsg.lua 의 _G.vimide_notify - 넘치면 화면에서만 줄이고
-- :messages 에는 다 남긴다). 피커 안에서 v:echospace 를 넘는 알림은 Press ENTER 를
-- 띄우고 다음 키를 먹는다 - 80칸 터미널에서 70칸짜리 알림이 그랬다(반대 심문).
-- 그래도 알림 글은 짧게 쓴다 (50칸 안팎). 긴 설명은 맨 위와 README 에.
local function notify(msg, level)
  return (_G.vimide_notify or vim.notify)(msg, level)
end

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

-- 두 번째 값이 true 면 '링크인데 가리키는 곳이 없다' (공유 폴더가 안 붙은 것
-- 같은). 그때는 읽을 수 없는 것으로 보고 쓰지 않는다 - 없는 것으로 보고 새로
-- 쓰면 rename 이 링크를 보통 파일로 갈아 치워, 공유 폴더가 돌아왔을 때 북마크가
-- 두 벌로 갈렸다 (QA).
local function bm_file()
  local f = vim.fn.stdpath('data') .. '/vim-ide/bookmarks.json'
  -- 링크로 두었으면 링크를 따라간 자리를 고친다. 바꿔 치기(rename)를 링크에
  -- 하면 링크가 보통 파일로 갈린다.
  local real = uv.fs_realpath(f)
  if real then
    return real, false
  end
  local l = uv.fs_lstat(f)
  return f, (l and l.type == 'link') or false
end

-- 알림에 넣는 경로: 파일 이름과 줄만. 경로가 길면 한 줄을 넘겨 Press ENTER 가 떴다 (QA).
local function where_of(path, line)
  local t = vim.fn.fnamemodify(path, ':t')
  return line and (t .. ':' .. line) or t
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
  local f, dangling = bm_file()
  if dangling then
    notify('북마크 파일이 가리키는 곳이 없습니다 (링크) - 읽지도 쓰지도 않습니다: '
      .. vim.fn.fnamemodify(f, ':~'), vim.log.levels.WARN)
    return {}, true
  end
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
  notify('북마크 파일이 잠겨 있어 고치지 못했습니다: ' .. lock, vim.log.levels.ERROR)
  return false
end

-- fn(list) 는 고친 목록과 덧붙일 정보를 돌려준다. 성공하면 true, 정보.
local function bm_update(fn)
  local f = bm_file()
  vim.fn.mkdir(vim.fn.fnamemodify(f, ':h'), 'p')
  return with_lock(f, function()
    local list, bad = bm_read()
    if bad then
      notify('북마크 파일을 읽을 수 없어 고치지 않았습니다: ' .. f, vim.log.levels.ERROR)
      return false
    end
    local nl, info = fn(list)
    list = nl or list
    local oke, text = pcall(vim.fn.json_encode, { version = 1, bookmarks = list })
    if not oke then
      notify('북마크를 적지 못했습니다 (' .. tostring(text) .. ')', vim.log.levels.ERROR)
      return false
    end
    local tmp = f .. '.tmp.' .. vim.fn.getpid()
    if vim.fn.writefile({ text }, tmp, 's') ~= 0 then
      notify('북마크 파일을 쓰지 못했습니다: ' .. tmp, vim.log.levels.ERROR)
      return false
    end
    local old = uv.fs_stat(f)
    if old then
      uv.fs_chmod(tmp, old.mode % 4096) -- 원래 권한 그대로
    end
    if not uv.fs_rename(tmp, f) then
      uv.fs_unlink(tmp)
      notify('북마크 파일을 바꾸지 못했습니다: ' .. f, vim.log.levels.ERROR)
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

-- ---------------------------------------------------------------------------
-- SDK - 이름 붙은 북마크는 SDK 마다 따로 본다 (맨 위 설명)
-- ---------------------------------------------------------------------------

-- path 가 root 이거나 그 아래인가
local function under(path, root)
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

local function home_dir()
  return ((uv.os_homedir() or vim.env.HOME or ''):gsub('/+$', ''))
end

-- 다른 디렉터리(북마크·마크의 파일)에 대해 알아낸 것은 세션 동안 기억한다:
--   seen   디렉터리마다 '.repo' / 색인 / .git 같은 표시가 있나 (has)
--   known  디렉터리 -> SDK 루트
--   kinds  찾은 SDK 루트 -> 그것을 정한 것 ('repo', 'index', 'mark')
--   reals  디렉터리 -> 링크를 푼 경로
-- 창을 열 때마다 북마크 수백 개의 디렉터리를 다시 걸으면 stat 이 느린 서버에서
-- 몇 초가 걸리고, 안 붙은 공유 폴더의 북마크 하나가 어느 SDK 에서 열든 창을
-- 붙들었다(반대 심문 실측: 열 때마다 stat 7천 번, realpath 240번. 표시를 창
-- 하나 동안만 기억했을 때는 .git 으로 정한 SDK 에서 열 때마다 stat 420번).
-- 여러 디렉터리가 같은 윗 디렉터리를 지나므로 처음 열 때도 한 번씩만 본다.
-- 창을 연 자리의 SDK 는 여기 기대지 않고 늘 새로 본다(new_ctx) - 새로 본 것이
-- 기억과 다르면(다른 nvim 이 색인을 만들었다 등) 기억을 다 버린다. 이 nvim 이
-- 색인을 만들면(VimIdeIndexUpdated) 버리고, 창을 KEEP_SEC 동안 한 번도 열지
-- 않았으면 버린다 - 다른 nvim 이 다른 SDK 에 만든 색인은 그때 들어온다. 채운
-- 때부터 재면 몇 분마다 쓰는 사람도 5분마다 처음부터 다시 걸었다 (반대 심문:
-- 그때마다 stat 3천 번, 또는 realpath 240번).
-- realpath 는 SDK 루트마다 한 번, 그리고 걸어 올라가도 루트를 못 찾은 디렉터리
-- 에만 부른다 - 북마크마다 부르지 않는다 (rel_in, shown_abs).
local KEEP_SEC = 300
local known, kinds, reals, seen, since = {}, {}, {}, {}, os.time()

local function forget()
  known, kinds, reals, seen = {}, {}, {}, {}
end

api.nvim_create_autocmd('User', {
  group = api.nvim_create_augroup('VimIdeMarks', { clear = true }),
  pattern = 'VimIdeIndexUpdated',
  callback = function(a)
    -- 저장 한 번의 갱신(single)은 루트를 바꾸지 않는다
    if not (a.data and a.data.kind == 'single') then
      forget()
    end
  end,
})

-- 디렉터리 d 에 SDK 루트의 표시가 있나. c 는 기억할 곳 - 창을 연 자리는 창
-- 하나의 표(new_ctx), 나머지는 세션의 seen.
--   repo   '.repo' 디렉터리 (repo 로 받은 SDK, reposearch.lua)
--   index  GTAGS 색인 (루트에, 또는 g:autoindex_dbdir 안에)
--   mark   .git, .project, .root
local function has(c, d, what)
  local k = d .. '\0' .. what
  local hit = c[k]
  if hit ~= nil then
    return hit
  end
  local function is(n)
    return uv.fs_stat(d .. '/' .. n)
  end
  local r
  if what == 'repo' then
    local st = is('.repo')
    r = st ~= nil and st.type == 'directory'
  elseif what == 'index' then
    local db = vim.g.autoindex_dbdir
    db = (db == nil) and '.tags' or (tostring(db):gsub('/+$', ''))
    r = ((db ~= '' and db ~= '.' and is(db .. '/GTAGS')) or is('GTAGS')) and true or false
  else
    r = (is('.git') or is('.project') or is('.root')) and true or false
  end
  c[k] = r
  return r
end

-- dir 와 그 위에서(홈과 / 는 빼고) what 을 가진 가장 바깥 디렉터리
local function outermost(dir, what, c)
  local home = home_dir()
  local best, d = nil, dir
  while d ~= '' and d ~= '/' and d ~= home do
    if has(c, d, what) then
      best = d
    end
    local up = vim.fs.dirname(d)
    if not up or up == d then
      break
    end
    d = up
  end
  return best
end

-- 디렉터리 -> SDK 루트와 그것을 정한 것('repo', 'index', 'mark'). 없으면 nil.
-- 순서는 맨 위 설명 그대로. 셋 다 가장 바깥 것이고 지금 디렉터리(getcwd)를
-- 보지 않는다 - 같은 파일은 nvim 을 어디서 켰든 같은 SDK 다. 예전에는
-- RelationView 의 색인 루트를 먼저 보고 '.repo' 는 색인이 없을 때만 봐서,
-- repo SDK 안의 kernel/common 만 색인했으면 그 안의 파일에서는 kernel/common
-- 이 SDK 가 되어 같은 SDK 의 다른 ★ 가 사라졌다(반대 심문). projectfiles 의
-- 루트는 가장 안쪽 표시에 켠 자리까지 보아서 켠 곳마다 목록이 달랐다.
local function sdk_of_dir(dir, c)
  if type(dir) ~= 'string' or dir:sub(1, 1) ~= '/' then
    return nil
  end
  if dir ~= '/' then
    dir = (dir:gsub('/+$', ''))
  end
  for _, what in ipairs({ 'repo', 'index', 'mark' }) do
    local r = outermost(dir, what, c)
    if r then
      return r, what
    end
  end
  return nil
end

-- 링크를 푼 디렉터리 (세션 동안 기억)
local function real_dir(dir)
  local hit = reals[dir]
  if hit ~= nil then
    return hit or nil
  end
  local r = uv.fs_realpath(dir)
  reals[dir] = r or false
  return r
end

-- 이미 찾은 SDK 루트 아래의 디렉터리면 끝까지 걸어 올라가지 않는다. 루트 R 을
-- 'repo' 로 찾았으면 R 위에 '.repo' 가 없고, 'index' 면 R 위에 '.repo'·색인이
-- 없고, 'mark' 면 R 위에 셋 다 없다 - 그러니 dir 에서 R 바로 밑까지만 보면 된다:
--   repo   그대로 R
--   index  그 사이 '.repo' 가 있으면 가장 바깥 것, 없으면 R
--   mark   그 사이 '.repo', 없으면 색인(가장 바깥 것), 둘 다 없으면 R
-- sdk_of_dir 과 답이 같다. 북마크 수백 개가 SDK 몇 개에 모여 있으면 처음 열 때
-- stat 이 반 아래로 준다(실측: 300개 5 SDK, 3060 -> 1230). 홈 아래의 디렉터리는
-- 홈이나 그 위의 루트(홈 밖에서 찾은 것)에 기대지 않는다 - sdk_of_dir 은 홈에서
-- 멈춘다.
local function below_known(dir)
  local home = home_dir()
  local in_home = home ~= '' and under(dir, home) and dir ~= home
  local best
  for r in pairs(kinds) do
    if under(dir, r) and (not best or #r > #best) and not (in_home and under(home, r)) then
      best = r
    end
  end
  if not best or kinds[best] == 'repo' then
    return best, best and 'repo' or nil
  end
  local function outer(what)
    local found, d = nil, dir
    while #d > #best do
      if has(seen, d, what) then
        found = d
      end
      d = vim.fs.dirname(d)
    end
    return found
  end
  local r = outer('repo')
  if r then
    return r, 'repo'
  end
  if kinds[best] == 'mark' then
    r = outer('index')
    if r then
      return r, 'index'
    end
  end
  return best, kinds[best]
end

-- 북마크·마크가 든 디렉터리의 SDK 루트 (세션 동안 기억). 링크를 거친 경로라
-- 제자리에서 못 찾으면 링크를 푼 경로로 한 번 더 찾는다.
local function known_sdk(dir)
  local hit = known[dir]
  if hit ~= nil then
    return hit or nil
  end
  local function find(d)
    local r, k = below_known(d)
    if not r then
      r, k = sdk_of_dir(d, seen)
    end
    if r then
      kinds[r] = k
    end
    return r
  end
  local r = find(dir)
  if not r then
    local rd = real_dir(dir)
    if rd and rd ~= dir then
      r = find(rd)
    end
  end
  known[dir] = r or false
  return r
end

-- path 의 SDK 루트(known_sdk)와, 루트 아래를 그 루트와 같은 철자로 쓴 path.
-- 적어 둔 경로로 루트를 찾았으면 path 그대로, 링크를 푼 경로로 찾았으면 푼 것.
local function sdk_and_path(path)
  local dir = vim.fs.dirname(path)
  local sdk = known_sdk(dir)
  if not sdk or under(dir, sdk) then
    return sdk, path
  end
  return sdk, (real_dir(dir) or dir) .. '/' .. vim.fs.basename(path)
end

-- 이 SDK 의 파일이면 SDK 루트 기준 상대 경로, 아니면 nil.
-- 그 파일이 든 디렉터리의 SDK(known_sdk)가 이 SDK 인가로 본다 - 루트 아래라도
-- 그 안에 따로 선 SDK('.repo', 표시로 정한 SDK 안의 색인)의 파일은 그 SDK 것이다
-- (sdk_of_dir 의 순서 그대로). 그래야 어느 파일에서 열든 한 ★ 는 한 SDK 에만 든다.
-- 링크는 루트에서 푼다: 적어 둔 경로로 찾은 루트('/tmp/…')의 realpath 가 이
-- SDK('/private/tmp/…')면 이 SDK 것이다. 루트는 몇 개뿐이라 realpath 도 몇 번뿐 -
-- 예전에는 이 SDK 밖의 북마크마다 디렉터리의 realpath 를 불렀다(반대 심문:
-- 처음 열 때 240번, 5분마다 또).
local function rel_in(ctx, path)
  if not ctx.root then
    return nil
  end
  local sdk, p = sdk_and_path(path)
  if not sdk or p == sdk then
    return nil
  end
  if sdk ~= ctx.root and sdk ~= ctx.rroot and (real_dir(sdk) or sdk) ~= ctx.rroot then
    return nil
  end
  return p:sub(#sdk + 2)
end

-- 보여줄 절대 경로와 그 SDK 루트 - 루트는 링크를 푼 것. 적어 둔 경로(북마크
-- 파일, 마크)는 그대로 두고 보이는 것만 푼다. 예전에는 '/tmp/…' 로 담은 것과
-- '/private/tmp/…' 로 담은 것이 다른 곳처럼 보였고, 줄일 때 그 둘이 갈리는
-- 조각(tmp 와 private)만 남아 정작 SDK 를 가르는 디렉터리가 사라졌다(반대 심문).
-- 푸는 것은 루트까지다 - 루트 아래는 적어 둔 그대로 잇는다(SDK 안의 링크는 그
-- SDK 의 것으로 보인다). SDK 밖의 경로는 디렉터리를 푼다.
-- 둘째 값은 nil 일 수 있다 (SDK 밖).
local function shown_abs(path)
  local sdk, p = sdk_and_path(path)
  if sdk then
    local rs = real_dir(sdk) or sdk
    return rs .. p:sub(#sdk + 1), rs
  end
  local dir = vim.fs.dirname(path)
  local rd = real_dir(dir) or dir
  return (rd == '/' and '' or rd) .. '/' .. vim.fs.basename(path), nil
end

-- 창 하나의 기준: 어느 SDK 에서 열었나, 범위.
-- file: 창을 연 편집 창의 파일 (없으면 nil - 지금 디렉터리로 본다)
local function new_ctx(file, buf)
  if os.time() - since >= KEEP_SEC then
    forget()
  end
  since = os.time() -- 쉰 시간으로 잰다 (열 때마다 새로)
  local ctx = { buf = buf }
  local fc = {} -- 창을 연 자리는 기억에 기대지 않고 새로 본다
  local dir = file and vim.fs.dirname(file) or vim.fn.getcwd()
  ctx.root, ctx.kind = sdk_of_dir(dir, fc)
  if not ctx.root then
    local rd = uv.fs_realpath(dir) -- 링크를 거쳐 연 파일
    if rd and rd ~= dir then
      ctx.root, ctx.kind = sdk_of_dir(rd, fc)
    end
  end
  -- 새로 본 것이 기억과 다르면 그사이 디스크가 바뀐 것이다 - 기억을 다 버린다
  local stale = known[dir] ~= nil and (known[dir] or nil) ~= ctx.root
  for k, v in pairs(fc) do
    if stale then
      break
    end
    stale = seen[k] ~= nil and seen[k] ~= v
  end
  if stale then
    forget()
  end
  for k, v in pairs(fc) do
    seen[k] = v
  end
  known[dir] = ctx.root or false
  if ctx.root then
    kinds[ctx.root] = ctx.kind
  end
  ctx.rroot = ctx.root and (real_dir(ctx.root) or ctx.root) or nil
  ctx.scope = tostring(vim.g.vimide_bookmarks_scope or 'sdk') == 'all' and 'all' or 'sdk'
  -- 이름이 같은 SDK 를 가릴 때 견줄 루트(링크를 푼 것): 이 SDK, 모든 북마크의
  -- SDK, 모든 마크(shada 의 것도)의 SDK. collect 가 채우고 창이 닫힐 때까지 줄지
  -- 않는다 - 지우거나(d) 범위를 바꿔도(<C-s>) 다른 줄의 모양이 그대로다.
  ctx.twins = {}
  if ctx.rroot then
    ctx.twins[ctx.rroot] = true
  end
  -- 칸 폭도 창이 닫힐 때까지 줄지 않는다 (범위마다, layout_of)
  ctx.cols = {}
  return ctx
end

-- ---------------------------------------------------------------------------
-- shada 의 a-z - 읽어 두지 않은 파일의 소문자 마크
-- ---------------------------------------------------------------------------
-- nvim 은 파일 안의 표시(a-z)를 그 파일을 버퍼로 읽을 때에야 shada 에서 붙인다.
-- 그래서 nvim 을 다시 켜면 아직 안 연 파일의 ma 는 목록에 없었다(반대 심문).
-- shada 파일을 직접 읽는다 - 읽기만 하고, 파일의 크기·시각이 그대로면 다시
-- 읽지 않는다. shada 는 [종류, 시각, 길이, 내용] 이 이어진 msgpack 이고, 파일
-- 안의 표시는 종류 10 (내용 {f=파일, l=줄, c=칸, n=이름 글자}; 빠진 것은 l=1,
-- c=0, n='"'). 다른 종류(이력, 레지스터, 점프 ...)는 길이만큼 건너뛴다 - 풀지
-- 않는다. 어디서든 틀리면(없다, 잠겼다, 쓰다 만 파일, 모르는 모양) 읽은 데까지만
-- 쓰고 알리지 않는다 - 그러면 떠 있는 버퍼의 것만 보인다.

-- nvim 과 같은 규칙으로 찾은 shada 파일. 'shada' 가 비었거나 '0 이면(마크를
-- 적지 않는다) nil. 'shadafile' 이 있으면 그것('NONE' 이면 안 쓴다), 없으면
-- 'shada' 의 n 항목(맨 끝이라 이름에 , 가 들어갈 수 있다), 그것도 없으면
-- stdpath('state')/shada/main.shada.
local function shada_file()
  local rest, name = vim.o.shada, nil
  if rest == '' then
    return nil
  end
  while rest ~= '' do
    local item, tail = rest:match('^([^,]*),?(.*)$')
    if item:sub(1, 1) == 'n' then
      name = rest:sub(2)
      break
    end
    if item:sub(1, 1) == "'" and tonumber(item:sub(2)) == 0 then
      return nil
    end
    rest = tail
  end
  local sf = vim.o.shadafile
  if sf ~= '' then
    return sf ~= 'NONE' and vim.fs.normalize(sf) or nil
  end
  if name and name ~= '' then
    return vim.fs.normalize(name)
  end
  return vim.fn.stdpath('state') .. '/shada/main.shada'
end

-- msgpack 의 음 아닌 정수 하나: 값, 다음 자리. 모자라면 nil (쓰다 만 파일)
local function mp_uint(s, p)
  local b = s:byte(p)
  if not b then
    return nil
  end
  if b < 0x80 then
    return b, p + 1
  end
  local n = ({ [0xcc] = 1, [0xcd] = 2, [0xce] = 4, [0xcf] = 8 })[b]
  if not n or p + n > #s then
    return nil
  end
  local v = 0
  for i = p + 1, p + n do
    v = v * 256 + s:byte(i)
  end
  return v, p + n + 1
end

-- 마지막으로 읽은 shada: 열쇠(파일·크기·시각), 마크, 이 shada 로 본 파일들의
-- 줄 글(seen: 경로 -> {줄 -> 글}, 없는 파일은 false)
local shada_memo = { marks = {}, seen = {} }

-- shada 마크가 가리키는 파일의 줄 글. 파일마다 한 번, 가장 아래 마크 줄까지만
-- 읽는다. 파일의 크기·시각이 그대로면 shada 가 바뀌어도(다른 nvim 이 닫힐 때마다
-- 바뀐다) 다시 읽지 않는다 - 마크마다 읽었더니 shada 의 파일 100개(마크 233개,
-- 2천 줄짜리)에서 창 열기가 35ms 늘었다(실측).
local file_texts = {} -- 경로 -> { key = 크기:시각, text = { [줄] = 글 } }

local function texts_of(path, lnums)
  local st = uv.fs_stat(path)
  if not st or st.type ~= 'file' then
    file_texts[path] = nil
    return nil
  end
  local k = st.size .. ':' .. st.mtime.sec .. '.' .. (st.mtime.nsec or 0)
  local ft = file_texts[path]
  if not ft or ft.key ~= k then
    ft = { key = k, text = {} }
    file_texts[path] = ft
  end
  local upto = 0
  for _, l in ipairs(lnums) do
    if ft.text[l] == nil then
      upto = math.max(upto, l)
    end
  end
  if upto > 0 then
    local ok, lines = pcall(vim.fn.readfile, path, '', upto)
    for _, l in ipairs(lnums) do
      if ft.text[l] == nil then
        local t = ok and type(lines) == 'table' and lines[l]
        ft.text[l] = t and (tostring(t):gsub('^%s+', '')) or ''
      end
    end
  end
  return ft.text
end

-- { {file=, name=, lnum=, col=}, ... } - 같은 파일·같은 이름이면 시각이 늦은 것
local function shada_marks()
  local ok, marks = pcall(function()
    local f = shada_file()
    local st = f and uv.fs_stat(f)
    if not st or st.type ~= 'file' then
      shada_memo = { marks = {}, seen = {} }
      return shada_memo.marks
    end
    local key = table.concat({ f, st.size, st.mtime.sec, st.mtime.nsec or 0, st.ino or 0 }, ':')
    if shada_memo.key == key then
      return shada_memo.marks
    end
    local fd = io.open(f, 'rb')
    if not fd then
      return {}
    end
    local s = fd:read('*a') or ''
    fd:close()
    local best, list = {}, {}
    local p, n = 1, #s
    while p <= n do
      local t, ts, len
      t, p = mp_uint(s, p)
      if t then
        ts, p = mp_uint(s, p)
      end
      if ts then
        len, p = mp_uint(s, p)
      end
      if not len or p + len - 1 > n then
        break
      end
      if t == 10 then
        local okd, d = pcall(vim.mpack.decode, s:sub(p, p + len - 1))
        local c = okd and type(d) == 'table' and type(d.f) == 'string' and (tonumber(d.n) or 34)
        if c and c >= 97 and c <= 122 then
          local f2 = d.f:sub(1, 1) == '~' and vim.fs.normalize(d.f) or d.f
          local k = f2 .. '\0' .. c
          if not best[k] or ts >= best[k].ts then
            best[k] = { file = f2, name = string.char(c), lnum = tonumber(d.l) or 1,
              col = tonumber(d.c) or 0, ts = ts }
          end
        end
      end
      p = p + len
    end
    local keep = {}
    for _, m in pairs(best) do
      list[#list + 1] = m
      keep[m.file] = file_texts[m.file]
    end
    file_texts = keep -- shada 에서 빠진 파일의 글은 버린다
    shada_memo = { key = key, marks = list, seen = {} }
    return list
  end)
  return ok and type(marks) == 'table' and marks or {}
end

local function collect(ctx)
  ctx = ctx or new_ctx(nil, api.nvim_get_current_buf())
  local out = {}
  local function add(m, global, buf)
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
    local path
    if m.file then
      path = vim.fn.fnamemodify(m.file, ':p')
    else
      local bn = api.nvim_buf_get_name(buf or m.pos[1] or 0)
      path = bn ~= '' and vim.fn.fnamemodify(bn, ':p') or ''
    end
    if not path or path == '' then
      return
    end
    -- 디렉터리를 가리키는 마크는 뺀다. 골라도 파일이 아니라 트리가 열린다
    -- (실측: 마크 D 가 kernel/common/ 을 가리켜서 NvimTree 가 떴다).
    if vim.fn.isdirectory(path) == 1 then
      return
    end
    local lnum = m.pos[2] or 1
    -- 마크는 절대 경로로 보여준다 - 어느 SDK 의 파일인지 보이게 (링크를 푼 것)
    local shown, sdk = shown_abs(path)
    out[#out + 1] = {
      kind = 'mark',
      name = name,
      global = global,
      buf = (not global) and buf or nil,   -- a-z 의 버퍼 (지우기·정렬)
      path = path,
      lnum = lnum,
      col = math.max(0, (m.pos[3] or 1) - 1),
      shown = shown,
      abs = true,
      sdk = sdk, -- 줄일 때 남길 SDK (링크를 푼 루트)
      text = line_text(path, lnum),
    }
  end
  for _, m in ipairs(vim.fn.getmarklist()) do   -- A-Z, 0-9
    add(m, true)
  end
  -- a-z: 지금 버퍼만이 아니라 이 nvim 에 있는 파일 버퍼 전부. 다른 SDK 의 파일
  -- 에서 찍은 ma 도 그 버퍼가 있으면 뜬다. 버퍼가 마크를 가진 파일(owned)은
  -- shada 의 것을 보지 않는다 - 이 세션에서 옮기거나 지운 것은 버퍼에 있다.
  -- 읽어 둔 버퍼, 한 번이라도 읽은 버퍼(changedtick > 1), a-z 를 가진 버퍼가
  -- 그렇다 - 목록에 있든 없든, :bd 로 닫아(내려) 있든. :bd 로 닫은 버퍼도 마크를
  -- 쥐고 있고 nvim 은 닫을 때 그것을 shada 에 적는다. 예전에는 목록에 있거나
  -- 떠 있는 버퍼만 봐서, :bd 한 파일은 옛 shada 의 마크(지운 것은 보이고 새로
  -- 찍은 것은 안 보이는)를 보였다(반대 심문). 목록에만 있고 한 번도 읽지 않은
  -- 버퍼(:badd - changedtick 1)에는 shada 의 마크가 아직 붙지 않았으니 a-z 가
  -- 없으면 shada 쪽을 쓴다.
  -- 옵션은 vim.bo[b] 로 읽지 않는다 - :bd 로 내린 버퍼의 옵션을 그렇게 읽으면
  -- (nvim_get_option_value) nvim 이 닫을 때 그 파일의 마크를 shada 에 하나도 적지
  -- 않는다 (nvim 0.12 실측. getbufvar 는 괜찮다).
  local owned = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    local bn = api.nvim_buf_get_name(b)
    if bn ~= '' and vim.fn.getbufvar(b, '&buftype') == '' then
      local mine = api.nvim_buf_is_loaded(b) or api.nvim_buf_get_changedtick(b) > 1
      for _, m in ipairs(vim.fn.getmarklist(b)) do
        mine = mine or m.mark:match("^'%l$") ~= nil
        add(m, false, b)
      end
      if mine then
        owned[#owned + 1] = vim.fn.fnamemodify(bn, ':p')
      end
    end
  end
  -- 읽어 두지 않은 파일의 a-z 는 shada 에서. 같은 파일인지는 SDK 루트의 링크를
  -- 푼 경로로도 본다 (shown_abs). 줄 글은 파일마다 한 번 읽어 shada 가 바뀔
  -- 때까지 기억하고(texts_of), 없어진 파일의 마크는 뺀다.
  local sh = shada_marks()
  if #sh > 0 then
    local function key_of(p)
      return (shown_abs(p))
    end
    local own = {}
    for _, p in ipairs(owned) do
      own[p], own[key_of(p)] = true, true
    end
    local rows, want = {}, {}
    for _, m in ipairs(sh) do
      local path = m.file
      if not own[path] and not own[key_of(path)] then
        rows[#rows + 1] = { m, path }
        if shada_memo.seen[path] == nil then
          want[path] = want[path] or {}
          table.insert(want[path], m.lnum)
        end
      end
    end
    for path, lnums in pairs(want) do
      shada_memo.seen[path] = texts_of(path, lnums) or false
    end
    for _, r in ipairs(rows) do
      local m, path = r[1], r[2]
      local tx = shada_memo.seen[path]
      if tx then
        local shown, sdk = shown_abs(path)
        out[#out + 1] = {
          kind = 'mark', name = m.name, global = false, shada = true,
          path = path, lnum = m.lnum, col = m.col,
          shown = shown, abs = true, sdk = sdk, text = tx[m.lnum] or '',
        }
      end
    end
  end
  for _, e in ipairs(out) do
    if e.sdk then
      ctx.twins[e.sdk] = true
    end
  end
  table.sort(out, function(a, b)
    if a.global ~= b.global then
      return a.global          -- 파일을 넘나드는 것부터
    end
    if not a.global then
      local ah, bh = a.buf == ctx.buf, b.buf == ctx.buf
      if ah ~= bh then
        return ah              -- 지금 파일의 a-z 가 먼저
      end
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.shown < b.shown
  end)
  -- 이름 붙은 북마크는 마크보다 앞에. 'sdk' 면 이 SDK 것만, 'all' 이면 이 SDK
  -- 것이 먼저. 그다음 최근 것.
  local bms = {}
  for _, b in ipairs((bm_read())) do
    if type(b) == 'table' and type(b.path) == 'string' and b.path ~= '' then
      local rel = rel_in(ctx, b.path)
      -- 그 SDK 는 목록에 뜨든 안 뜨든 이름이 같은 SDK 를 가릴 때 견준다 (layout_of)
      local s = known_sdk(vim.fs.dirname(b.path))
      if s then
        ctx.twins[real_dir(s) or s] = true
      end
      local here
      if ctx.root then
        here = rel ~= nil
      else
        -- SDK 밖에서 열었다: SDK 밖에서 담은 북마크가 '이곳' 것이다
        here = s == nil
      end
      if here or ctx.scope == 'all' then
        -- 이 SDK 밖의 것은 링크를 푼 절대 경로로 보여준다
        local shown, sdk = rel, nil
        if rel == nil then
          shown, sdk = shown_abs(b.path)
        end
        bms[#bms + 1] = {
          kind = 'bookmark', name = tostring(b.name or '?'), path = b.path,
          lnum = tonumber(b.line) or 1, bline = b.line, col = tonumber(b.col) or 0,
          saved = tostring(b.text or ''), shown = shown, abs = rel == nil, sdk = sdk,
          text = tostring(b.text or ''), time = tonumber(b.time) or 0,
          here = here,
        }
      end
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

-- ---------------------------------------------------------------------------
-- 줄 모양 - 칸 맞추기
-- ---------------------------------------------------------------------------
local dw = vim.fn.strdisplaywidth

local function chars(s)
  return vim.fn.split(s, '\\zs')
end

-- 표시 폭 w 칸 안으로. 넘치면 뒤(where='tail'), 앞('head'), 가운데('mid')를
-- … 로 자른다. 바이트로 자르면 한글이 반쪽으로 깨지고 칸이 어긋났다.
local function clip(str, w, where)
  str = tostring(str or '')
  if w <= 0 then
    return ''
  end
  if dw(str) <= w then
    return str
  end
  if w == 1 then
    return '…'
  end
  local ascii = not str:find('[\128-\255]')
  local function take_head(n) -- 앞에서 n 칸
    if ascii then
      return str:sub(1, n)
    end
    local acc, parts = 0, {}
    for _, c in ipairs(chars(str)) do
      local cw = dw(c)
      if acc + cw > n then
        break
      end
      acc = acc + cw
      parts[#parts + 1] = c
    end
    return table.concat(parts)
  end
  local function take_tail(n) -- 뒤에서 n 칸
    if ascii then
      return n > 0 and str:sub(-n) or ''
    end
    local cs, acc, parts = chars(str), 0, {}
    for i = #cs, 1, -1 do
      local cw = dw(cs[i])
      if acc + cw > n then
        break
      end
      acc = acc + cw
      table.insert(parts, 1, cs[i])
    end
    return table.concat(parts)
  end
  if where == 'dirmid' then
    -- 경로의 처음과 끝을 남기고 가운데 디렉터리를 '…' 로 (요청: 앞을 자르면
    -- 'subcore/build/' 같은 어디 밑인지가 사라졌다). 끝(파일 쪽)과 앞을 번갈아
    -- 디렉터리 단위로 늘린다 - 'subcore/build/…/git/src/tsnd_arpc.c'.
    -- 첫 디렉터리와 파일 이름도 다 안 들어가면 예전처럼 앞을 자른다('head')
    local p = vim.split(str, '/', { plain = true })
    if #p >= 3 then
      local function width(hh, tt)
        return dw(table.concat(p, '/', 1, hh)) + dw('/…/') + dw(table.concat(p, '/', #p - tt + 1, #p))
      end
      local h, t = 1, 1
      if width(h, t) <= w then
        local grew = true
        while grew and h + t < #p - 1 do
          grew = false
          if h + t < #p - 1 and width(h, t + 1) <= w then
            t, grew = t + 1, true
          end
          if h + t < #p - 1 and width(h + 1, t) <= w then
            h, grew = h + 1, true
          end
        end
        return table.concat(p, '/', 1, h) .. '/…/' .. table.concat(p, '/', #p - t + 1, #p)
      end
    end
    where = 'head'
  end
  if where == 'head' then
    -- 경로는 디렉터리 이름 가운데서 자르지 않는다. 잘린 조각('…g/alignment',
    -- '…mmon/sound')이 진짜 디렉터리 이름처럼 보였다(반대 심문). 잘린 첫 조각을
    -- 버리고 '…/' 로 잇는다 - 파일 이름도 다 안 들어갈 때만 글자로 자른다.
    local t = take_tail(w - 1)
    local s = t:find('/', 1, true)
    if s and s < #t then
      return '…' .. t:sub(s)
    end
    return '…' .. t
  elseif where == 'mid' then
    local h = math.floor((w - 1) * 0.45)
    return take_head(h) .. '…' .. take_tail(w - 1 - h)
  end
  return take_head(w - 1) .. '…'
end

-- 홈 아래면 ~ 로 줄인 경로
local function tilde(p)
  local home = home_dir()
  if home ~= '' and under(p, home) then
    return '~' .. p:sub(#home + 1)
  end
  return p
end

-- 이름이 같은 SDK 끼리 갈리는 조각. parts: 루트(링크를 푼 것)마다 ~ 로 줄인
-- 경로의 조각들. 이름(끝 조각)이 같은 둘을 앞에서 맞춰 보고 뒤에서 맞춰 보아,
-- 가운데 다른 토막의 첫 조각과 끝 조각을 늘 남길 것(must)으로 친다:
--   ~/work1/tsnd/dev/tsnd_2.0/Android14_IVI_1.1.0
--   ~/work2/tsnd/dev/tsnd_2.1/Android14_IVI_1.1.0   -> work1, tsnd_2.0 / work2, tsnd_2.1
-- 예전에는 처음 갈리는 조각 하나만 남겨서, '/tmp/…' 와 '/private/tmp/…' 로
-- 담은 둘은 tmp 와 private 만 남고 w1 과 w5 가 사라졌다(반대 심문).
local function distinct_parts(parts)
  local must = {}
  for a, pa in pairs(parts) do
    must[a] = {}
    for b, pb in pairs(parts) do
      if a ~= b and pa[#pa] == pb[#pb] then
        local i = 1
        while pa[i] ~= nil and pa[i] == pb[i] do
          i = i + 1
        end
        local j = 0
        while #pa - j > i and #pb - j > i and pa[#pa - j] == pb[#pb - j] do
          j = j + 1
        end
        if i <= #pa - j then
          must[a][i], must[a][#pa - j] = true, true
        end
      end
    end
  end
  return must
end

-- SDK 루트를 줄이는 차례 (덜 줄인 것부터, 링크를 푼 루트를 ~ 로 줄인 조각 p).
-- 늘 남기는 것: 맨 앞(~, 또는 /home 같은 / 밑 첫 디렉터리), SDK 이름, 이름이
-- 같은 다른 SDK 와 갈리는 조각(must). 나머지는 가운데 것부터 뺀다 - SDK 이름
-- 바로 위(판: tsnd_2.1)를 가장 오래, 그다음 맨 앞 바로 밑(work1)을 남긴다:
--   ~/work1/tsnd/dev/tsnd_2.1/Android14_IVI_1.1.0
--   ~/work1/…/dev/tsnd_2.1/Android14_IVI_1.1.0
--   ~/work1/…/tsnd_2.1/Android14_IVI_1.1.0
--   ~/…/tsnd_2.1/Android14_IVI_1.1.0
--   ~/…/Android14_IVI_1.1.0
--   …/Android14_IVI_1.1.0                 (맨 앞도 뺀다 - must 는 그래도 남긴다)
-- 이름이 같은 SDK 가 있으면 '맨 앞 바로 밑' 대신 그것과 처음 갈리는 조각부터
-- 센다. 홈 밖의 루트는 맨 앞이 /private, /Volumes 라 그 밑(tmp, 공유 이름)은
-- 어느 checkout 이나 같다 - 그 사이 조각은 가장 먼저 뺀다:
--   /private/tmp/x/h/work2/tsnd/dev/tsnd_2.0/A  ->  /private/…/work2/…/tsnd_2.0/A
local function root_ladder(p, must)
  local n = #p
  local h = p[1] == '' and 2 or 1 -- '/x/…' 는 [1] 이 '' 라 x 까지가 머리다
  local first
  for i in pairs(must or {}) do
    if i > h and i < n and (not first or i < first) then
      first = i
    end
  end
  local lo0 = first or h + 1
  local order, lo, hi = {}, lo0, n - 1
  while lo <= hi do
    order[#order + 1] = hi
    hi = hi - 1
    if lo <= hi then
      order[#order + 1] = lo
      lo = lo + 1
    end
  end
  for i = lo0 - 1, h + 1, -1 do
    order[#order + 1] = i -- 맨 앞과 처음 갈리는 조각 사이: 가장 먼저 뺀다
  end
  local labels = {}
  local function build(kept)
    kept[n] = true
    for i in pairs(must or {}) do
      kept[i] = true
    end
    -- 한 칸짜리 조각 하나(~)를 … 로 바꾸면 줄지 않고 알아보기만 어렵다
    for i = 1, n do
      if not kept[i] and kept[i + 1] and (i == 1 or kept[i - 1]) and dw(p[i]) <= 1 then
        kept[i] = true
      end
    end
    local out, gap = {}, false
    for i = 1, n do
      if kept[i] then
        out[#out + 1] = p[i]
        gap = false
      elseif not gap then
        out[#out + 1] = '…'
        gap = true
      end
    end
    local lab = table.concat(out, '/')
    if lab ~= labels[#labels] then
      labels[#labels + 1] = lab
    end
  end
  for k = #order, 0, -1 do
    local kept = {}
    for i = 1, math.min(h, n) do
      kept[i] = true
    end
    for x = 1, k do
      kept[order[x]] = true
    end
    build(kept)
  end
  build({})
  return labels
end

-- roots(목록의 절대 경로 줄의 SDK 와 창을 연 SDK, 링크를 푼 것)마다 줄이는 차례
local function root_labels(roots)
  local parts, labels = {}, {}
  for r in pairs(roots) do
    parts[r] = vim.split(tilde(r), '/', { plain = true })
  end
  local must = distinct_parts(parts)
  for r, p in pairs(parts) do
    labels[r] = root_ladder(p, must[r])
    labels[r].must = next(must[r]) ~= nil -- 갈리는 조각이 있다 (clip_abs 의 6)
    -- 갈리는 조각 이름들, 앞의 것부터 (clip_abs 의 7). 맨 앞(~, /x)은 빼고
    local h, idx = p[1] == '' and 2 or 1, {}
    for i in pairs(must[r]) do
      if i > h then
        idx[#idx + 1] = i
      end
    end
    table.sort(idx)
    labels[r].parts = vim.tbl_map(function(i) return p[i] end, idx)
  end
  return labels
end

-- SDK 루트 하나를 w 칸 안으로 (결과 창 제목). clip_abs 와 같은 차례.
local function clip_root(root, w, labels)
  if dw(root) <= w then
    return root
  end
  for _, lab in ipairs(labels or { tilde(root) }) do
    if dw(lab) <= w then
      return lab
    end
  end
  local last = labels and labels[#labels] or tilde(root)
  local name = vim.fs.basename(root)
  local head = last:sub(1, #last - #name)
  if last:sub(-#name) == name and w - dw(head) >= 5 then
    return head .. clip(name, w - dw(head), 'mid')
  end
  return w >= 7 and ('…/' .. clip(name, w - 2, 'mid')) or clip(name, w, 'mid')
end

-- 절대 경로를 w 칸 안으로. 덜 줄인 것부터 - SDK 루트를 줄이는 것은 맨 나중:
--   1) 다 들어가면 그대로
--   2) SDK 루트는 통째로 두고 그 아래만 디렉터리 단위로 앞을 자른다
--      '/home/B130111/work1/tsnd/dev/tsnd_2.1/Android14_IVI_1.1.0/…/telechips/tcc_i2s.c'
--   3) 루트와 '…/파일 이름'도 안 들어가면 홈을 ~ 로 (루트의 나머지는 통째로)
--   4) 그다음에야 루트를 줄인다 (root_ladder - 다른 SDK 와 갈리는 조각은 남긴다)
--   5) 끝으로 SDK 이름 가운데를 줄인다
--   6) 그래도 안 되면 SDK 이름을 빼고 갈리는 조각만 ('~/work2/…/tsnd_2.0/…/tcc_i2s.c')
--   7) 그것도 안 되면 갈리는 조각 하나만 ('…/work2/…/tcc_i2s.c'). 더 좁으면(경로 칸
--      20칸 안팎) 그것도 뺀다
-- 절대 경로를 보여주는 까닭이 '어느 SDK 의 것인가'라서다. 예전에는 루트를 먼저
-- '~/work1/…/SDK 이름' 으로 줄이고 그 아래를 남겨서, 같은 이름의 두 checkout
-- (tsnd_2.0 과 tsnd_2.1)이 넓은 창에서도 똑같이 보였다(반대 심문). SDK 를
-- 모르면 ~ 로 줄이고 첫 디렉터리와 끝을 남긴다 ('~/notes/…/a/b.md').
local function clip_abs(path, root, w, labels)
  if dw(path) <= w then
    return path
  end
  if root and under(path, root) and path ~= root then
    local below = path:sub(#root + 2)
    -- 아래 경로에 적어도 남길 것: 파일 이름 ('…/tcc_i2s.c')
    local least = math.min(dw(below), dw('…/' .. vim.fs.basename(below)))
    local tries = { root }
    for _, lab in ipairs(labels or { tilde(root) }) do
      if lab ~= tries[#tries] then
        tries[#tries + 1] = lab
      end
    end
    for _, lab in ipairs(tries) do
      local room = w - dw(lab) - 1
      if room >= least then
        return lab .. '/' .. clip(below, room, 'head')
      end
    end
    local last = tries[#tries]
    local name = vim.fs.basename(root)
    if last:sub(-#name) == name then
      local head = last:sub(1, #last - #name)
      local room = w - dw(head) - 1 - least
      if room >= 5 then
        return head .. clip(name, room, 'mid') .. '/' .. clip(below, least, 'head')
      end
      if labels and labels.must then
        local s6 = head .. (head:sub(-4) == '…/' and '' or '…/') .. vim.fs.basename(below)
        if dw(s6) <= w then
          return s6
        end
        -- 7) 갈리는 조각이 여럿이라 다 안 들어가면 하나만 ('…/work1/…/tcc_i2s.c').
        --    그것도 안 되면(경로 칸 20칸 안팎) 아래의 SDK 밖과 같이 줄인다
        for _, part in ipairs(labels.parts or {}) do
          local s7 = '…/' .. part .. '/…/' .. vim.fs.basename(below)
          if dw(s7) <= w then
            return s7
          end
        end
      end
    end
  end
  local t = tilde(path)
  if dw(t) <= w then
    return t
  end
  local p = vim.split(t, '/', { plain = true })
  if #p >= 4 then
    local head = p[1] .. '/' .. p[2] -- '~/notes', '/private'
    local room = w - dw(head) - 1
    if room >= dw('…/' .. p[#p]) then
      return head .. '/' .. clip(t:sub(#head + 2), room, 'head')
    end
  end
  return clip(t, w, 'head')
end

-- 오른쪽을 빈칸으로 채워 w 칸
local function pad(str, w)
  return str .. string.rep(' ', math.max(0, w - dw(str)))
end

local GAP = '  '

local function glyph(e)
  if e.kind == 'bookmark' then
    return '★'
  end
  return e.global and '↗' or ' '
end

-- 보여줄 줄 전체로 잰 칸 폭. 목록을 새로 모을 때마다(지운 뒤, 범위를 바꾼 뒤)
-- 다시 잰다. root: 창을 연 SDK (링크를 푼 것).
-- twins: 이름이 같은 SDK 를 가려 보일 때 견줄 루트 (ctx.twins - 모든 북마크·
-- 마크의 SDK). 목록에 뜬 것만 견주면 짝이 가려지거나(이 SDK 만) 지워지거나
-- 처음부터 목록에 없을 때 work1/work2 가 사라졌고, 짝을 지우면 남은 줄의 모양이
-- 바뀌었다(반대 심문). 목록의 절대 경로 줄의 SDK 와 root 도 넣는다.
-- need, need_t, need_m: 절대 경로 줄이 SDK 루트를 보이는 데 드는 칸 - 통째로,
-- 홈을 ~ 로 줄여서, 가장 줄인 모양(갈리는 조각과 SDK 이름은 다 남긴)으로 (cols_at)
-- keep: 창 하나·범위 하나 동안 칸 폭을 줄이지 않는다 - 지운 줄이 가장 긴 이름이나
-- 루트였어도 남은 줄은 그대로다.
local function layout_of(list, root, twins, keep)
  local L = { glyph = 1, name = 1, line = 1, need = 0, need_t = 0, need_m = 0, list = list, at = {} }
  local roots, abs = {}, {}
  for r in pairs(twins or {}) do
    roots[r] = true
  end
  if root then
    roots[root] = true
  end
  for _, e in ipairs(list) do
    if e.kind ~= 'add' then
      L.glyph = math.max(L.glyph, dw(glyph(e)))
      L.name = math.max(L.name, dw(e.name))
      L.line = math.max(L.line, #tostring(e.lnum))
      if e.abs and e.sdk and under(e.shown, e.sdk) and e.shown ~= e.sdk then
        roots[e.sdk] = true
        abs[#abs + 1] = e
      end
    end
  end
  L.labels = root_labels(roots)
  for _, e in ipairs(abs) do
    local below = e.shown:sub(#e.sdk + 2)
    local least = 1 + math.min(dw(below), dw('…/' .. vim.fs.basename(below)))
    local labs = L.labels[e.sdk]
    L.need = math.max(L.need, dw(e.sdk) + least)
    L.need_t = math.max(L.need_t, dw(tilde(e.sdk)) + least)
    L.need_m = math.max(L.need_m, dw(labs[#labs]) + least)
  end
  if keep then
    for _, k in ipairs({ 'glyph', 'name', 'line', 'need', 'need_t', 'need_m' }) do
      keep[k] = math.max(keep[k] or 0, L[k])
      L[k] = keep[k]
    end
  end
  return L
end

-- 결과 창 폭 width 에서의 칸: 이름 칸, 경로 칸, 줄마다 줄인 경로 (폭마다 한 번)
-- 경로 칸이 그 줄의 글보다 먼저다 - 경로는 어느 SDK·어느 파일인지를 말하고,
-- 글은 미리보기에도 보인다. 경로 칸은 줄인 경로 중 가장 긴 것만큼만 잡는다.
local function cols_at(L, width)
  local c = L.at[width]
  if c then
    return c
  end
  -- 이름 칸은 결과 창의 1/4 까지 (적어도 10칸, 길어도 32칸)
  local wn = math.min(L.name, math.max(10, math.min(32, math.floor(width / 4))))
  local fixed = L.glyph + 1 + #GAP + #GAP + L.line + #GAP
  -- 절대 경로 줄의 SDK 루트가 통째로 들어가지 않으면 이름 칸을 10칸까지
  -- 내준다 - 그대로 들어가게, 안 되면 홈을 ~ 로 줄여 들어가게, 그것도 안 되면
  -- 가장 줄인 루트(갈리는 조각과 SDK 이름은 다 남긴 것)가 들어가게. 잘린 이름도
  -- 걸러 찾을 수 있지만, 루트를 줄이면 어느 SDK 의 것인지가 흐려진다 - SDK 이름
  -- 가운데를 자르는 것은 이름 칸을 내줘도 안 될 때뿐이다(반대 심문: 2칸이면 되는
  -- 것을 잘랐다). 내줘도 모자라면 내주지 않는다 - 루트는 어차피 줄고 이름만 잘린다.
  for _, need in ipairs({ L.need, L.need_t, L.need_m }) do
    local short = need - (width - fixed - wn)
    if short <= 0 then
      break
    end
    if wn - short >= math.min(wn, 10) then
      wn = wn - short
      break
    end
  end
  local cap = math.max(12, width - fixed - wn)
  c = { wn = wn, wp = 1, paths = {} }
  for _, e in ipairs(L.list) do
    if e.kind ~= 'add' then
      local s = e.abs and clip_abs(e.shown, e.sdk, cap, L.labels[e.sdk])
        or clip(e.shown, cap, 'dirmid')
      c.paths[e] = s
      c.wp = math.max(c.wp, dw(s))
    end
  end
  L.at[width] = c
  return c
end

-- 한 줄. width 는 결과 창에서 이 줄이 쓸 수 있는 칸(앞의 '> ' 를 뺀 것).
--   ★ 이름        상대/경로.c              123  그 줄의 글
--   ↗ A           /절대/경로.c              45  그 줄의 글
local function label(e, L, width)
  L = L or layout_of({ e })
  local c = cols_at(L, width or 120)
  local text = vim.fn.strcharpart(e.text or '', 0, 300)
  return pad(glyph(e), L.glyph) .. ' ' .. pad(clip(e.name, c.wn, 'tail'), c.wn) .. GAP
    .. pad(c.paths[e] or clip(e.shown, c.wp, 'dirmid'), c.wp) .. GAP
    .. string.rep(' ', L.line - #tostring(e.lnum)) .. tostring(e.lnum) .. GAP .. text
end

-- 텔레스코프 결과 창에서 한 줄이 쓸 수 있는 칸
local function results_width(picker)
  local w
  if picker and picker.results_win and api.nvim_win_is_valid(picker.results_win) then
    w = api.nvim_win_get_width(picker.results_win)
  end
  w = w or math.floor(vim.o.columns * 0.8 * 0.6)
  return w - dw(tostring((picker and picker.entry_prefix) or '  '))
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
  -- :w 한 번에 빈 파일이 만들어진다. shada 에서 읽은 a-z 도 같다. 버퍼의 vim
  -- 마크는 예전처럼 둔다(저장 안 한 새 버퍼의 마크도 있다). 버퍼로 떠 있으면
  -- 그것도 연다.
  if (e.kind == 'bookmark' or e.shada) and vim.fn.filereadable(e.path) ~= 1
      and vim.fn.bufexists(e.path) == 0 then
    notify('그 파일이 없습니다: ' .. where_of(e.path),
      vim.log.levels.WARN)
    return
  end
  -- 마크로 뛰면 점프 목록에 자리가 남아 <C-o> 로 돌아올 수 있다
  pcall(vim.cmd, "normal! m'")
  -- 같은 파일인지는 링크를 푼 실제 경로로 본다. 링크로 등록한 북마크(linked.py
  -- -> real/real.py)를 실제 경로로 연 세션에서 고르면, :edit 가 이미 열린 버퍼를
  -- 다시 쓰는데(파일 id 로 맞춘다) 이름이 달라 '열지 못했다'고 했다 (QA).
  local function same(a, b)
    if a == b then
      return true
    end
    local ra, rb = uv.fs_realpath(a), uv.fs_realpath(b)
    return ra ~= nil and ra == rb
  end
  local cur = api.nvim_buf_get_name(0)
  if not same(vim.fn.fnamemodify(cur, ':p'), e.path) then
    pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(e.path))
  end
  local lnum, col = e.lnum, e.col
  if e.kind == 'mark' and not e.global then
    -- 다른 버퍼의 a-z: 그 파일을 열었을 때만 그 버퍼의 마크 자리로 간다.
    -- :edit 가 실패했으면 지금 버퍼에서 'a 로 가면 엉뚱한 마크다. shada 에서
    -- 읽은 것은 파일을 열 때 nvim 이 그 마크를 붙인다. 열었는데 그 마크가 없으면
    -- (다른 nvim 이 그새 지웠다 등) 읽어 둔 옛 줄로 가지 않고 알린다 - 예전에는
    -- 지운 마크의 옛 자리로 조용히 갔다(반대 심문).
    if not same(vim.fn.fnamemodify(api.nvim_buf_get_name(0), ':p'), e.path) then
      notify('그 파일을 열지 못했습니다: ' .. where_of(e.path),
        vim.log.levels.WARN)
      return
    end
    local ok, mp = pcall(api.nvim_buf_get_mark, 0, e.name)
    if not (ok and type(mp) == 'table' and (mp[1] or 0) > 0) then
      notify(("마크 '%s' 가 그 파일에 없습니다"):format(e.name), vim.log.levels.WARN)
      return
    end
    lnum, col = mp[1], mp[2]
  end
  if e.kind == 'bookmark' then
    -- :edit 가 실패했으면(winfixbuf 창 등) 지금 버퍼는 다른 파일이다. 거기서 줄을
    -- 찾아 저장하면 엉뚱한 줄이 적힌다.
    if not same(vim.fn.fnamemodify(api.nvim_buf_get_name(0), ':p'), e.path) then
      notify('그 파일을 열지 못했습니다: ' .. where_of(e.path),
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
    notify('파일 창에서 열어야 북마크를 담을 수 있습니다', vim.log.levels.WARN)
    return false
  end
  if vim.trim(name) == '' then
    notify('북마크 이름을 프롬프트에 치세요', vim.log.levels.WARN)
    return false
  end
  local ok, how = bm_add(pos, vim.trim(name))
  if ok then
    notify((how == 'same' and '이미 있는 북마크입니다 (시각만 새로): %s  (%s)'
        or '북마크 등록: %s  (%s)'):format(vim.trim(name), where_of(pos.path, pos.line)))
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
  local pos, sym, origin_buf
  -- 다른 텔레스코프 창(프롬프트)에서 열면 그 프롬프트는 곧 닫히며 지워진다.
  -- 담을 자리·커서 밑 심볼·마크를 모을 버퍼는 마지막 편집 창에서 가져온다 -
  -- 프롬프트 버퍼를 잡아 두었다가 d 에서 'Invalid buffer id' 로 죽었다 (QA).
  -- 트리·패널에서 열 때는 예전처럼 담지 않는다 (here() 의 규칙 그대로).
  local function last_edit()
    if type(_G.vimide_last_edit_win) ~= 'function' then
      return nil
    end
    local ok, w = pcall(_G.vimide_last_edit_win)
    return (ok and type(w) == 'number' and w ~= 0 and api.nvim_win_is_valid(w)) and w or nil
  end
  local ew = vim.bo.buftype == 'prompt' and last_edit() or nil
  if ew then
    api.nvim_win_call(ew, function()
      pos, sym = here()
      origin_buf = api.nvim_get_current_buf()
    end)
  else
    pos, sym = here()
    origin_buf = api.nvim_get_current_buf()
  end
  -- 어느 SDK 에서 열었나: 그 편집 창의 파일. 트리·패널에서 열었으면 마지막 편집
  -- 창의 파일, 그것도 없으면 지금 디렉터리.
  local function file_of(b)
    if not (b and api.nvim_buf_is_valid(b)) or vim.bo[b].buftype ~= '' then
      return nil
    end
    local n = api.nvim_buf_get_name(b)
    return n ~= '' and vim.fn.fnamemodify(n, ':p') or nil
  end
  local file = file_of(origin_buf)
  if not file then
    local w = last_edit()
    local b = w and api.nvim_win_get_buf(w)
    file = file_of(b)
    if file then
      origin_buf = b
    end
  end
  local ctx = new_ctx(file, origin_buf)
  local items = collect(ctx)
  -- 칸 폭: 이름이 같은 SDK 는 모든 북마크·마크의 SDK 와 견주고(ctx.twins), 폭은
  -- 창이 닫힐 때까지 범위마다 줄이지 않는다(ctx.cols)
  local function layout_now()
    ctx.cols[ctx.scope] = ctx.cols[ctx.scope] or {}
    return layout_of(items, ctx.rroot, ctx.twins, ctx.cols[ctx.scope])
  end
  local t = telescope()
  if not t then
    -- 0 은 취소다(inputlist 는 Esc 나 빈 Enter 도 0 을 준다). 등록은 1 번.
    local lines = { '북마크/마크 (번호, Esc 는 취소):', '1. ＋ 지금 자리를 북마크로 담기' }
    local L = layout_now()
    local w = vim.o.columns - #tostring(#items + 1) - 3
    for i, e in ipairs(items) do
      lines[#lines + 1] = ('%d. %s'):format(i + 1, label(e, L, w))
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
  -- 등록 줄에 보일 담길 자리: 이 SDK 안이면 상대 경로, 밖이면 ~ 로 줄인 경로
  local add_where = pos and ((rel_in(ctx, pos.path) or vim.fn.fnamemodify(pos.path, ':~'))
    .. ':' .. pos.line) or ''
  local layout = layout_now()
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
  -- 결과 창 제목: <C-s> 가 무엇으로 바꾸나, 그리고 어느 SDK 의 목록인가.
  -- 안내가 앞이다 - telescope 는 창보다 긴 제목의 끝을 자르는데, SDK 경로가
  -- 앞이면 서버 경로에서는 160칸 창에서도 안내가 잘려 <C-s> 를 알 길이
  -- 없었다(반대 심문). 경로는 남은 칸(창 폭 - 2)에 맞게 줄인다 (clip_root).
  -- picker 가 없으면(창을 세우기 전) 폭을 어림한다 - 선 뒤에 다시 단다.
  local function sdk_title(picker)
    local w
    if picker and picker.results_win and api.nvim_win_is_valid(picker.results_win) then
      w = api.nvim_win_get_width(picker.results_win)
    end
    w = (w or math.floor(vim.o.columns * 0.8 * 0.6)) - 2
    local hint = ctx.scope == 'all' and '^s 이 SDK 만' or '^s 모든 SDK'
    if not ctx.root then
      return hint .. (ctx.scope == 'all' and '   모든 SDK 의 ★' or '   SDK 밖 (어느 SDK 에도 들지 않은 ★)')
    end
    -- 'all' 머리는 짧게 ('모든 ★') - 120칸에서 이 SDK 의 갈리는 디렉터리(work1)가 잘렸다
    local head = hint .. (ctx.scope == 'all' and '   모든 ★ (이 SDK: ' or '   SDK  ')
    local tail = ctx.scope == 'all' and ')' or ''
    return head .. clip_root(ctx.rroot, math.max(8, w - dw(head) - dw(tail)),
      layout.labels[ctx.rroot]) .. tail
  end
  local function set_sdk_title(picker)
    pcall(function() picker.layout.results.border:change_title(sdk_title(picker)) end)
  end
  local opts = {
    -- :Telescope resume 이 옛 자리·옛 심볼의 등록 줄을 되살리지 않게
    cache_picker = false,
    -- 점수가 같으면 모아 온 순서(이 SDK -> 최근 -> 마크)를 지킨다.
    -- 기본 tiebreak 는 짧은 글자를 앞으로 올려서, 글자를 치는 순간 최근
    -- 것이 위라는 순서가 흐트러졌다 (반대 심문).
    tiebreak = function() return false end,
    -- 담을 자리가 없으면(파일 아닌 창) 등록 줄 대신 첫 항목을 골라 둔다
    default_selection_index = (not pos and #items > 0) and 2 or nil,
    results_title = sdk_title(),
    -- 줄이 칸 맞춘 표라 결과 칸을 조금 넓힌다 (넓은 화면에서 미리보기 0.5 -> 0.4.
    -- 150 칸보다 좁으면 telescope 기본도 0.4 다)
    layout_config = { preview_width = 0.4 },
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
            .. '   ← ' .. add_where .. dup
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
    -- 칸 폭은 결과 창 폭을 알아야 정해진다 - 그려질 때 만든다. 같은 폭·같은
    -- 칸이면 만든 것을 다시 쓴다.
    local memo_w, memo_l, memo
    return {
      value = e,
      display = function(_, picker)
        local w = results_width(picker)
        if memo_w ~= w or memo_l ~= layout then
          memo_w, memo_l, memo = w, layout, label(e, layout, w)
        end
        return memo
      end,
      -- 거르기는 이름, 보이는 경로 전체(잘리기 전), 그 줄의 글로
      ordinal = e.name .. ' ' .. e.shown .. ' ' .. e.text,
      filename = e.path,
      lnum = e.lnum,
    }
  end
  local function make_finder()
    layout = layout_now()
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
        local picker = t.state.get_current_picker(bufnr)
        if type(_G.vimide_picker_track) == 'function' then
          pcall(_G.vimide_picker_track, picker)
        end
        if picker then
          set_sdk_title(picker) -- 이제 결과 창의 폭을 안다
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
            notify('북마크 이름을 프롬프트에 치세요', vim.log.levels.WARN)
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
      -- 목록을 다시 모아 칸을 다시 재고 갈아 끼운다 (지운 뒤, 범위를 바꾼 뒤)
      local function reload(picker)
        items = collect(ctx)
        refresh_keep(picker, make_finder(), title())
        set_sdk_title(picker)
      end
      -- 'd' 는 노멀 모드에서만. 입력 모드에도 걸면 검색창에 d 를 칠 때마다
      -- 지워진다 - 'drivers' 를 치려다 두 개를 잃는다. 입력 모드에서는 <C-d>
      -- (\fo, \fx 와 같은 키. 미리보기 내려 보기는 이 창에서는 내준다).
      -- 지워도 창은 그대로 두고 목록만 다시 읽어 갈아 끼운다. 친 글자는 두고,
      -- 선택은 지운 자리 근처에 둔다 - 여러 개를 이어서 지울 수 있다.
      local function del()
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
            notify(("북마크 '%s' 를 지웠습니다"):format(e.name))
          else
            notify(("북마크 '%s' 는 그새 없어졌습니다"):format(e.name), vim.log.levels.WARN)
          end
        else
          -- a-z 는 그 마크의 버퍼에서 지운다 - 지금 창은 프롬프트고, 목록에는
          -- 다른 버퍼의 a-z 도 있다. :bd 로 닫은 버퍼도 그 버퍼에서 지운다(다시
          -- 읽지 않는다 - nvim 이 닫을 때 그 버퍼의 마크를 적는다). 전역 마크
          -- (A-Z, 0-9)는 어디서 지워도 된다.
          -- shada 에서 읽은 a-z(그 파일의 버퍼가 없다)는 그 파일을 버퍼로 읽어(창은
          -- 그대로) 지운다 - 읽을 때 nvim 이 shada 의 마크를 붙이고, 닫을 때 지운
          -- 것을 적는다. shada 파일은 고치지 않는다(다른 nvim 도 쓴다). 버퍼 목록
          -- 에도 올린다: 읽어 둔 채 목록에 없는 버퍼는 nvim 이 닫을 때 그 파일의
          -- a-z 를 하나도 적지 않는다(실측). 그 마크가 없으면(다른 nvim 이 그새
          -- 지웠다) 새로 만든 버퍼는 지워 처음 그대로 둔다.
          -- 알림은 짧게 - 파일 이름도 넣지 않는다 (80칸에서 Press ENTER, 맨 위 notify)
          local note = ''
          local okd, err = pcall(function()
            if e.global then
              vim.cmd('delmarks ' .. e.name)
            elseif e.shada then
              -- 버퍼를 만들기 전에 shada 를 다시 본다 (바뀌었을 때만 다시 읽는다). 창을 연
              -- 뒤 다른 nvim 이 그 마크를 지웠으면 버퍼를 만들지 않고 끝낸다 - 만들어 놓고
              -- 지우면(wipe) 그 파일을 가리키는 전역 마크(A-Z)까지 사라졌다 (재확인, 재현)
              local still = false
              for _, m in ipairs(shada_marks()) do
                if m.name == e.name and (m.file == e.path
                    or shown_abs(m.file) == shown_abs(e.path)) then
                  still = true
                  break
                end
              end
              if not still then
                error('그 파일에 없습니다', 0)
              end
              local b = vim.fn.bufadd(e.path)
              vim.fn.bufload(b)
              if not api.nvim_buf_del_mark(b, e.name) then
                -- 그래도 없으면(아주 짧은 틈) 지우지 않고 목록에 올려 둔다: 읽은 채 목록에
                -- 없는 버퍼는 nvim 이 닫을 때 그 파일의 a-z 를 적지 않고, 지우면 전역
                -- 마크가 사라진다
                vim.bo[b].buflisted = true
                error('그 파일에 없습니다', 0)
              end
              vim.bo[b].buflisted = true
              note = ' (파일을 버퍼로 읽음)'
            elseif e.buf and api.nvim_buf_is_valid(e.buf) then
              if not api.nvim_buf_del_mark(e.buf, e.name) then
                error('그 버퍼에 없습니다', 0)
              end
            else
              error('그 버퍼가 없어졌습니다', 0)
            end
          end)
          if okd then
            notify(("마크 '%s' 를 지웠습니다%s"):format(e.name, note))
          else
            notify(("마크 '%s' 를 지우지 못했습니다: %s"):format(e.name, tostring(err)),
              vim.log.levels.WARN)
          end
        end
        if picker then
          reload(picker)
        end
      end
      map('n', 'd', del)
      map({ 'i', 'n' }, '<C-d>', del)
      -- 화면 크기가 바뀌면 칸을 새 폭으로 다시 그린다. telescope 는 창 크기만 고치고
      -- 줄은 다시 그리지 않아서, 다음 글자를 칠 때까지 옛 폭의 표가 남았다.
      api.nvim_create_autocmd('VimResized', {
        buffer = bufnr,
        callback = function()
          vim.schedule(function()
            local picker = api.nvim_buf_is_valid(bufnr) and t.state.get_current_picker(bufnr)
            if picker then
              refresh_keep(picker, make_finder(), title())
              set_sdk_title(picker)
            end
          end)
        end,
      })
      -- 이 SDK 의 ★ 만 <-> 모든 SDK 의 ★ (이 창에서만. 기본은 g:vimide_bookmarks_scope)
      -- <C-a> 가 아니다 - vim-ide 의 .tmux.conf 는 tmux 의 prefix 가 ^A 라, tmux
      -- 안에서는 nvim 까지 오지 않았다(반대 심문: 실제로 붙은 클라이언트로 실측).
      -- telescope 도 <C-s> 는 쓰지 않는다.
      map({ 'i', 'n' }, '<C-s>', function()
        local picker = t.state.get_current_picker(bufnr)
        if not picker then
          return
        end
        ctx.scope = ctx.scope == 'all' and 'sdk' or 'all'
        reload(picker)
      end)
      return true
    end,
  })):find()
end

api.nvim_create_user_command('VimIdeMarks', function() _G.vimide_marks() end,
  { desc = '찍어 둔 마크를 골라서 그 자리로' })
