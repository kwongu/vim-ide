-- gtagsasync.lua - :Gtags 찾기를 뒤에서 돌린다 (nvim 전용, QA-26)
--
-- gtags.vim 은 global 을 system() 으로 불러 끝날 때까지 nvim 이 멈춘다 (gtags.vim:413).
-- 154 파일 색인에서도 \\s 가 50~200ms, 시작 직후(자동 색인이 도는 중)의 첫 ':Gtags -r'
-- 은 1.1초, 커널 트리에서는 더 길다. 그동안 키가 먹지 않는다.
--
-- 그래서 global 을 vim.system 으로 돌린다:
--   * 누르면 바로 'Gtags -r 낱말: 찾는 중...' 을 띄우고 키를 돌려준다
--   * 답이 오면 gtags.vim 과 똑같이 quickfix 를 열고(botright copen) 채우고(cexpr!) 첫
--     자리로 뛴다. 찾기를 누른 편집 창 기준이다 - 그 사이 다른 창으로 갔으면 그 창으로
--     돌아와 뛴다 (곁창이 파일로 바뀌지 않게). 다른 탭으로 갔으면 목록만 채우고 알린다
--   * 새 찾기가 앞의 것을 끊는다 (앞 프로세스는 죽이고 늦은 답은 버린다)
--   * insert/명령줄 모드 중에 답이 오면 normal 로 돌아올 때까지 기다린다 (1초 넘게
--     기다렸으면 뛰지 않고 목록만 채운다)
--
-- 바꾸는 곳은 gtags.vim 의 s:ExecLoad 하나다 (system() 이 있는 곳). 그래서 그 앞의
-- 것은 그대로다: relationview.lua 의 :Gtags 덮어쓰기(패널이 떠 있으면 패널로 - 그쪽은
-- 이미 비동기), 곁창이면 편집 창으로 옮기기, GTAGSROOT/GTAGSDBPATH(with_file_db),
-- gtags.vim 의 낱말 해석·'Gtags for pattern:' 물음, :GtagsQf, :GtagsCursor.
--
-- 결과를 곧바로 읽는 호출은 예전처럼 기다린다. .vimrc 의 <C-]> 대체 길(s:RvCtxJump)은
-- 'Gtags -d' 바로 뒤에 getqflist() 가 비었는지로 다음 길을 고른다 - 그런 것은 비동기로
-- 돌리면 늘 빈 목록을 본다. 그래서 Vim 스크립트 함수 안에서 부른 것은 동기로 둔다.
-- 비동기는 명령줄에서 친 것(매핑의 ':Gtags ...<CR>' 포함)과 Lua 에서 부른 것, 그리고
-- 결과를 읽지 않는 아래 SAFE 함수들뿐이다 (expand('<stack>') 로 가린다).
--
-- 옵션 (.vimrc):
--   let g:vimide_gtags_async = 1    " 0 이면 gtags.vim 그대로 (system() 으로 기다린다)
--
-- vim 8.1 은 이 파일을 읽지 않는다 (plugin/*.lua) - gtags.vim 그대로다.

if vim.g.loaded_vimide_gtags_async then
  return
end
vim.g.loaded_vimide_gtags_async = 1

local api = vim.api
local uv = vim.uv or vim.loop

-- 결과를 읽지 않는 .vimrc 함수: 이 안에서 부른 :Gtags 도 비동기로 돌린다
--   MarkAndCallRefs  \\c (부르는 곳 찾기)
--   InEditWin        :VimIdeInEdit (<C-\><C-]> 의 GtagsCursor)
--   RvAddLand        <C-]> 대체 길의 '정의 파일 담고 다시 찾기' (늦게 오는 답)
local SAFE = { MarkAndCallRefs = true, InEditWin = true, RvAddLand = true }

local S = {
  sid = nil, -- gtags.vim 의 스크립트 번호
  gen = 0, -- 찾기 세대 (새 찾기가 앞의 것을 버린다)
  job = nil, -- 돌고 있는 global (vim.system)
}

local function enabled()
  local v = vim.g.vimide_gtags_async
  return v == nil or (v ~= 0 and v ~= false)
end

local function gvar(name, default)
  local v = vim.g[name]
  if v == nil then
    return default
  end
  return v
end

-- gtags.vim 의 s:Error 와 같게 (WarningMsg, :messages 에 남는다). 화면 폭을 넘으면
-- fitmsg.lua 가 화면에서만 줄인다 - 콜백에서 Press ENTER 가 뜨면 다음 키를 먹는다
local function gerror(msg)
  msg = 'Error: ' .. msg
  if _G.vimide_notify then
    return _G.vimide_notify(msg, vim.log.levels.WARN)
  end
  api.nvim_echo({ { msg, 'WarningMsg' } }, true, {})
end

-- s:TrimOption: global 에 넘기면 안 되는 글자 (c e n p q u v)
local function trim_option(o)
  return (o:gsub('[cenpquv]', ''))
end

-- 명령줄에서 친 것인가 (결과를 곧바로 읽는 Vim 스크립트 함수 안이 아닌가). 실측:
--   :Gtags -r x (relationview 의 Lua 명령이 gtags.vim 을 부른다)
--     'nvim_exec2()[1]..function <SNR>72_RunGlobal[23]..<SNR>72_ExecLoad[1]'
--   Vim 스크립트 함수 안의 execute 'Gtags -d x'
--     'function TestG[2]..script nvim_exec2() called at TestG:2[1]..function <SNR>72_...'
local function interactive(stack)
  for _, fr in ipairs(vim.split(stack or '', '..', { plain = true })) do
    local f = fr:gsub('^function ', '')
    if f ~= '' and f ~= 'command line' and not f:find('^nvim_exec2?%(%)')
        and not f:find('^script nvim_exec2?%(%)') then
      local name = f:match('^<SNR>(%d+_[%w_#]+)%[') or f:match('^([%w_#.:]+)%[')
      if not name then
        return false -- 자동 명령, :source 중인 파일 ... - 모르는 것은 예전처럼
      end
      local sid, fname = name:match('^(%d+)_(.+)$')
      if not ((sid and tonumber(sid) == S.sid) or SAFE[fname or name]) then
        return false
      end
    end
  end
  return true
end

-- quickfix 명령(cexpr! / cgete / cadde)을 g:Gtags_Efm 으로 돌린다. 목록 제목은
-- gtags.vim 과 같게 (상태줄에 ':cexpr! l:result' 로 보인다). 돌려주는 것: 오류
local function qf_run(cmd, result)
  local efm = vim.o.errorformat
  vim.g.__vimide_gtags_r = result
  vim.o.errorformat = gvar('Gtags_Efm', '%f\t%l\t%m')
  local ok, err = pcall(vim.cmd, cmd)
  vim.o.errorformat = efm
  vim.g.__vimide_gtags_r = nil
  if not ok then
    return err
  end
  local last = cmd:match('([^\n]*)$')
  if not last:find('^cadde') then
    local title = ':' .. (last:gsub('g:__vimide_gtags_r', 'l:result'))
    pcall(vim.fn.setqflist, {}, 'a', { title = title })
  end
  return nil
end

-- global 의 답을 quickfix 로 (s:ExecLoad 의 뒷부분 그대로). opt 는 global 에 넘긴
-- 옵션 글자 전체(--result=... 까지) - gtags.vim 이 빈 답의 알림을 그것으로 고른다.
-- 돌려주는 것: 실패했으면 그 오류 (cexpr! 의 E37 같은 것)
local function load(result, opt, pattern, flags, jump)
  if result == '' then
    local q = gvar('Gtags_Shell_Quote_Char', "'")
    if opt:find('f', 1, true) then
      gerror('Tag not found in ' .. pattern .. '.')
    elseif opt:find('P', 1, true) then
      gerror('Path which matches to ' .. pattern .. ' not found.')
    elseif opt:find('g', 1, true) then
      gerror('Line which matches to ' .. pattern .. ' not found.')
    else
      gerror('Tag which matches to ' .. q .. pattern .. q .. ' not found.')
    end
    return nil
  end
  if gvar('Gtags_OpenQuickfixWindow', 1) == 1 then
    local open = true
    if gvar('Gtags_Close_When_Single', 0) == 1 then
      local i = result:find('\n', 1, true)
      open = (i and i > 1 and result:find('\n', i + 1, true)) and true or false
    end
    if jump == 0 then
      open = true
    end
    if not open then
      vim.cmd('cclose')
    elseif gvar('Gtags_VerticalWindow', 0) == 1 then
      vim.cmd('topleft vertical copen')
    else
      vim.cmd('botright copen')
    end
  end
  local cmd
  if flags:find('a', 1, true) then
    cmd = 'cadde g:__vimide_gtags_r'
  elseif gvar('Gtags_No_Auto_Jump', 0) == 1 then
    cmd = 'cgete g:__vimide_gtags_r'
  else
    cmd = 'cexpr! g:__vimide_gtags_r'
  end
  if jump == 1 then
    cmd = cmd .. '\ncexpr! g:__vimide_gtags_r'
  end
  return qf_run(cmd, result)
end

local function failed(code, cmd)
  if code == 2 then
    gerror('invalid arguments. please use the latest GLOBAL.')
  elseif code == 3 then
    gerror('GTAGS not found.')
  else
    gerror('global command failed. command line: ' .. cmd)
  end
end

-- 줄 수 (보이는 답의 크기)
local function count_lines(s)
  local _, n = s:gsub('\n', '')
  return n
end

-- 한 줄로 (화면 폭을 넘으면 Press ENTER 가 뜬다)
local function say(msg, hl)
  local room = math.max(10, (vim.v.echospace or 60) - 1)
  if vim.fn.strdisplaywidth(msg) > room then
    msg = vim.fn.strcharpart(msg, 0, room - 1) .. '…'
  end
  api.nvim_echo({ { msg, hl or 'Comment' } }, false, {})
end

-- 답이 왔다. 지금 자리가 받기 좋을 때까지 (normal 모드) 기다렸다가 싣는다
local function land(gen, ctx, out, code)
  if gen ~= S.gen then
    return -- 더 새 찾기가 있다
  end
  local m = api.nvim_get_mode()
  if m.blocking or m.mode ~= 'n' then
    -- insert / 명령줄 / 피커 프롬프트 중: 끝날 때까지 기다린다 (새 찾기가 오면 버린다).
    -- 1초 넘게 기다렸으면 그 사이 다른 일을 하고 있었다 - 뛰지 않고 목록만 채운다
    ctx.wait0 = ctx.wait0 or uv.now()
    vim.defer_fn(function()
      land(gen, ctx, out, code)
    end, 100)
    return
  end
  local late = ctx.wait0 and uv.now() - ctx.wait0 > 1000
  S.job = nil
  -- '찾는 중...' 을 걷는다 (gtags.vim 처럼 이 뒤에는 오류나 quickfix 의 알림만)
  api.nvim_echo({ { '' } }, false, {})
  if code ~= 0 then
    return failed(code, ctx.cmd)
  end
  local tab = api.nvim_get_current_tabpage()
  local err
  if late or tab ~= ctx.tab or not api.nvim_win_is_valid(ctx.win)
      or api.nvim_win_get_tabpage(ctx.win) ~= tab then
    -- 다른 탭으로 갔다 (또는 오래 다른 일을 했다): 창을 열거나 뛰지 않는다. 목록만 채운다
    if out == '' then
      return load(out, ctx.opt, ctx.pattern, ctx.flags, 0)
    end
    err = qf_run(ctx.flags:find('a', 1, true) and 'cadde g:__vimide_gtags_r'
      or 'cgete g:__vimide_gtags_r', out)
    if not err then
      return say(('Gtags %s: %d건 - quickfix 에 담았습니다 (:copen)'):format(ctx.label,
        count_lines(out)), 'None')
    end
  else
    -- 찾기를 누른 창에서 (그 사이 곁창으로 갔어도 곁창이 파일로 바뀌지 않게)
    if api.nvim_get_current_win() ~= ctx.win then
      pcall(api.nvim_set_current_win, ctx.win)
    end
    -- 성공이면 load 가 돌려준 것(nil 또는 cexpr! 의 오류), 실패면 copen 등의 오류
    local _, e = pcall(load, out, ctx.opt, ctx.pattern, ctx.flags, ctx.jump)
    err = e
  end
  if err then
    -- 동기일 때처럼 Vim 오류 한 줄로 (콜백의 Lua 오류 더미가 아니라)
    api.nvim_echo({ { (tostring(err):gsub('^Vim%b():', '')), 'ErrorMsg' } }, true, {})
  end
end

-- 예전 그대로 기다려서 찾는다 (gtags.vim 의 system() 그 자리). 돌려주는 것: 오류
-- (copen/cexpr! 의 E...) - 갈아 끼운 ExecLoad 가 :echoerr 로 내서 부른 쪽의 try 가
-- 예전처럼 잡는다
local function run_sync(cmd, opt, pattern, flags, jump)
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return failed(vim.v.shell_error, cmd)
  end
  local _, err = pcall(load, out, opt, pattern, flags, jump)
  return err and (tostring(err):gsub('^Vim%b():', '')) or nil
end

-- gtags.vim 의 s:ExecLoad 자리에 들어간다 (인자도 같다)
function _G.vimide_gtags_execload(option, long_option, pattern, flags, jump, stack)
  option, long_option = tostring(option or ''), tostring(long_option or '')
  pattern, flags = tostring(pattern or ''), tostring(flags or '')
  jump = tonumber(jump) or 0
  -- 새 찾기는 앞의 것을 끊는다 (기다리는 찾기도)
  S.gen = S.gen + 1
  if S.job then
    pcall(function() S.job:kill(15) end)
    S.job = nil
  end
  local isfile = option:find('f', 1, true) ~= nil
  if isfile and vim.fn.filereadable(pattern) == 0 then
    gerror('File ' .. pattern .. ' not found.')
    return
  end
  local global = vim.env.GTAGSGLOBAL
  if not global or global == '' then
    global = 'global'
  end
  local opt = long_option ~= '' and (long_option .. ' ') or ''
  opt = opt .. '--result=' .. gvar('Gtags_Result', 'ctags-mod') .. ' -q' .. trim_option(option)
  local q = gvar('Gtags_Shell_Quote_Char', "'")
  local cmd
  if isfile then
    cmd = global .. ' ' .. opt .. ' ' .. q .. pattern .. q
  else
    cmd = global .. ' ' .. opt .. 'e ' .. q .. pattern .. q
  end

  if not (enabled() and interactive(stack)) then
    return run_sync(cmd, opt, pattern, flags, jump) -- 결과를 곧바로 읽는 호출
  end

  local o = trim_option(option)
  local ctx = {
    cmd = cmd, opt = opt, pattern = pattern, flags = flags, jump = jump,
    win = api.nvim_get_current_win(), tab = api.nvim_get_current_tabpage(),
    label = (o ~= '' and ('-' .. o .. ' ') or '') .. pattern,
  }
  -- GTAGSROOT/GTAGSDBPATH 는 relationview.lua 의 with_file_db 가 이 호출 동안만 단다.
  -- 프로세스는 지금 뜨므로 그대로 물려받는다 (vim.system 은 nvim 의 환경을 쓴다)
  local gen = S.gen
  -- exec: 셸이 global 로 바뀌어야 끊을 때 global 이 죽는다 (셸만 죽고 global 이 남지 않게)
  local ok, job = pcall(vim.system, { 'sh', '-c', 'exec ' .. cmd }, { text = true, cwd = vim.fn.getcwd() },
    function(r)
      local code = r.code or -1
      if (r.signal or 0) ~= 0 and code == 0 then
        code = 128 + r.signal -- 누가 죽였다 (우리가 끊은 것은 세대가 달라 버려진다)
      end
      vim.schedule(function()
        land(gen, ctx, r.stdout or '', code)
      end)
    end)
  if not ok then
    return run_sync(cmd, opt, pattern, flags, jump) -- 프로세스를 못 띄웠다
  end
  S.job = job
  say('Gtags ' .. ctx.label .. ': 찾는 중...')
end

-- gtags.vim 의 s:ExecLoad 를 갈아 끼운다. gtags.vim 은 이 파일보다 늦게 읽히므로 VimEnter 에서.
local function install()
  if not enabled() or S.sid or not vim.system then
    return -- vim.system 은 nvim 0.10 부터
  end
  local ok, info = pcall(vim.fn.getscriptinfo, { name = [[/gtags\.vim/plugin/gtags\.vim$]] })
  local sid = ok and type(info) == 'table' and info[1] and info[1].sid or nil
  if not sid or vim.fn.exists('*<SNR>' .. sid .. '_ExecLoad') ~= 1 then
    return -- gtags.vim 이 없거나 모양이 다르다: 그대로 둔다
  end
  local okx = pcall(api.nvim_exec2, table.concat({
    ('function! <SNR>%d_ExecLoad(option, long_option, pattern, flags, ...)'):format(sid),
    "  let l:err = v:lua.vimide_gtags_execload(a:option, a:long_option, a:pattern, a:flags,"
      .. " a:0 > 0 ? a:1 : 0, expand('<stack>'))",
    '  if !empty(l:err)',
    '    echoerr l:err',
    '  endif',
    'endfunction',
  }, '\n'), { output = false })
  if okx then
    S.sid = sid
  end
end

if vim.v.vim_did_enter == 1 then
  install()
else
  api.nvim_create_autocmd('VimEnter', {
    group = api.nvim_create_augroup('VimIdeGtagsAsync', { clear = true }),
    once = true,
    callback = install,
  })
end
