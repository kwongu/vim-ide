-- findreplace.lua - 커서 밑 심볼을 이 파일 안에서 찾아 바꾼다
--
-- <C-h> 를 누르면 떠 있는 창이 뜬다. (,ch 는 명령행 쪽이다 - .vimrc 참고)
--
--   ╭─ 찾아 바꾸기 ──────────────────╮
--   │  Old   IO_UTIL_ReadECID        │
--   │  New   ▊                       │
--   ╰────────────────────────────────╯
--
-- Old 는 커서 밑 심볼로 채워 두지만 고칠 수 있다. 빈 곳에서 불렀으면 Old 가
-- 비어 있고 커서가 거기서 시작한다 - 찾을 말부터 직접 치면 된다.
-- Tab 으로 두 칸을 오간다.
--
-- 바꿀 말을 치고 Enter 를 누르면 어떻게 바꿀지 고르는 창이 뜬다.
--
--   ALL      한 번에 모두 바꾼다
--   하나씩   자리마다 Yes/No 로 물어본다 (vim 의 :s///gc 그대로 -
--            y 바꾼다, n 건너뛴다, a 여기서부터 전부, q 그만둔다)
--   취소
--
-- 어디서든 <Esc> 는 취소다. 바꾸기는 한 번의 :s 라서 u 한 번에 전부 되돌아온다.
--
-- 옵션 (.vimrc)
--   g:vimide_replace_word   1 이면 낱말 경계로 찾는다 (기본 1)
--                           struct 를 바꿀 때 structure 가 안 걸린다.
--   g:vimide_replace_ctrl_h 0 이면 <C-h> 를 창 이동(:wincmd h)으로 둔다
--   :VimIdeReplace [old]    같은 것을 명령으로

if vim.g.loaded_vimide_findreplace then
  return
end
vim.g.loaded_vimide_findreplace = 1

if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api

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

-- 떠 있는 창 하나. 지울 때 창과 버퍼를 같이 거둔다.
local function float(lines, opts)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  local width = opts.width or 60
  local height = #lines
  local win = api.nvim_open_win(buf, true, {
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
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder'
  vim.wo[win].cursorline = opts.cursorline and true or false
  return buf, win
end

local function close(win)
  if win and api.nvim_win_is_valid(win) then
    pcall(api.nvim_win_close, win, true)
  end
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

-- ':s' 의 찾을 쪽. \V(아주 곧이곧대로) 라서 심볼에 든 . * [ ] 가 안 튄다.
local function search_pat(old)
  local p = '\\V' .. vim.fn.escape(old, '\\/')
  if cfg('replace_word', 1) ~= 0 and old:match('^[%a_][%w_]*$') then
    p = '\\<' .. p .. '\\>'
  end
  return p
end

-- ':s' 의 바꿀 쪽. & 와 ~ 는 '찾은 것 전체'라는 뜻이라 그대로 두면 안 된다.
local function repl_text(new)
  return vim.fn.escape(new, '\\/&~')
end

local function count_hits(pat)
  local ok, out = pcall(vim.fn.execute, '%s/' .. pat .. '//gn', 'silent!')
  if not ok or type(out) ~= 'string' then
    return 0
  end
  return tonumber(out:match('(%d+)')) or 0
end

local function run(old, new, all)
  local pat = search_pat(old)
  local rep = repl_text(new)
  local flags = all and 'g' or 'gc'
  if not all then
    api.nvim_echo({ { '바꿀까요?  y 예  n 아니오  a 여기서부터 전부  q 그만', 'Question' } },
      false, {})
  end
  local before = count_hits(pat)
  local ok, err = pcall(vim.cmd, 'keeppatterns %s/' .. pat .. '/' .. rep .. '/' .. flags)
  if not ok then
    -- 사용자가 q 로 그만둔 것은 잘못이 아니다
    if tostring(err):match('E486') then
      vim.notify(("'%s' 를 찾지 못했습니다"):format(old), vim.log.levels.WARN)
    end
    return
  end
  local left = count_hits(pat)
  local done = before - left
  vim.notify(("'%s' -> '%s'  %d곳 바꿈%s"):format(old, new, done,
    left > 0 and (' (%d곳 남음)'):format(left) or ''))
end

-- 2단계: 한 번에 바꿀까, 하나씩 물어볼까
local function ask_how(old, new, hits)
  local rows = {
    { key = 'a', label = '  ALL      한 번에 모두 바꾼다', how = 'all' },
    { key = 'o', label = '  하나씩   자리마다 Yes / No 로 물어본다', how = 'one' },
    { key = 'q', label = '  취소', how = nil },
  }
  local lines = {}
  for _, r in ipairs(rows) do
    lines[#lines + 1] = r.label
  end
  local buf, win = float(lines, {
    width = 60,
    cursorline = true,
    title = (" %s  →  %s   (%d곳) "):format(old, new, hits),
    footer = ' j/k 고르기 · Enter 확인 · Esc 취소 ',
  })
  vim.bo[buf].filetype = 'vimide-replace'

  local function pick(how)
    close(win)
    if how then
      vim.schedule(function() run(old, new, how == 'all') end)
    end
  end
  local function here()
    return rows[api.nvim_win_get_cursor(win)[1]]
  end
  vim.keymap.set('n', '<CR>', function() local r = here(); pick(r and r.how) end,
    { buffer = buf, nowait = true })
  for _, r in ipairs(rows) do
    vim.keymap.set('n', r.key, function() pick(r.how) end, { buffer = buf, nowait = true })
  end
  for _, k in ipairs({ '<Esc>', 'q', '<C-c>' }) do
    vim.keymap.set('n', k, function() pick(nil) end, { buffer = buf, nowait = true })
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
local function ask_new(old)
  local LAB = { '  Old   ', '  New   ' }
  local buf, win = float({ old, '' }, {
    width = math.max(46, #old + 22),
    title = ' 찾아 바꾸기 ',
    footer = ' Tab 칸 이동 · Enter 다음 · Esc 취소 ',
  })
  vim.bo[buf].filetype = 'vimide-replace'
  vim.bo[buf].complete = ''
  acp(false)

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
    api.nvim_win_set_cursor(win, { n, #l })
    vim.cmd('startinsert!')
  end
  goto_line(old == '' and 1 or 2)

  local function field(n)
    local l = api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ''
    return (l:gsub('^%s+', ''):gsub('%s+$', ''))
  end
  local function done()
    -- 아직 바꿀 말을 안 썼으면 Enter 는 'New 로 넘어가기'다
    if api.nvim_win_is_valid(win) and api.nvim_win_get_cursor(win)[1] == 1
        and field(2) == '' then
      goto_line(2)
      return
    end
    local o, n = field(1), field(2)
    close(win)
    acp(true)
    vim.cmd('stopinsert')
    if o == '' then
      vim.notify('찾을 말이 비어 있습니다', vim.log.levels.WARN)
      return
    end
    if n == '' then
      vim.notify('바꿀 말이 비어 있습니다', vim.log.levels.WARN)
      return
    end
    if n == o then
      vim.notify('같은 말입니다', vim.log.levels.WARN)
      return
    end
    vim.schedule(function()
      local hits = count_hits(search_pat(o))
      if hits == 0 then
        vim.notify(("'%s' 를 이 파일에서 찾지 못했습니다"):format(o), vim.log.levels.WARN)
        return
      end
      ask_how(o, n, hits)
    end)
  end
  local function cancel()
    close(win)
    acp(true)
    vim.cmd('stopinsert')
  end
  local function other()
    goto_line(api.nvim_win_get_cursor(win)[1] == 1 and 2 or 1)
  end
  for _, m in ipairs({ 'n', 'i' }) do
    vim.keymap.set(m, '<CR>', done, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<Tab>', other, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<S-Tab>', other, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<Esc>', cancel, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<C-c>', cancel, { buffer = buf, nowait = true })
  end
  -- 칸은 둘 뿐이다. 줄을 늘리거나 합치는 키는 막는다.
  --
  -- 특히 <BS>: 칸 맨 앞에서 한 번 더 누르면 vim 은 윗줄과 합친다
  -- ('backspace' 에 eol 이 있으면). 그러면 New 칸이 Old 줄로 끌려 올라가고
  -- 이름표 둘이 한 줄에 겹친다(실측: 백스페이스 스무 번에 그렇게 됐다).
  -- 칸 맨 앞에서는 아무 일도 하지 않는다.
  -- expr 매핑은 돌려준 글자의 <BS> 를 스스로 키로 바꾼다(replace_keycodes).
  -- 여기서 미리 nvim_replace_termcodes 를 거치면 두 번 바뀌어 '<80>kb' 가
  -- 글자로 들어간다(실측). 문자열 그대로 돌려준다.
  vim.keymap.set('i', '<BS>', function()
    return api.nvim_win_get_cursor(win)[2] == 0 and '' or '<BS>'
  end, { buffer = buf, expr = true, replace_keycodes = true, nowait = true })
  -- <Del> 은 반대쪽이다. 줄 끝에서 누르면 아랫줄을 끌어올린다.
  vim.keymap.set('i', '<Del>', function()
    local c = api.nvim_win_get_cursor(win)
    local l = api.nvim_buf_get_lines(buf, c[1] - 1, c[1], false)[1] or ''
    return c[2] >= #l and '' or '<Del>'
  end, { buffer = buf, expr = true, replace_keycodes = true, nowait = true })
  for _, k in ipairs({ 'o', 'O', 'dd', 'J', 'gJ' }) do
    vim.keymap.set('n', k, '<Nop>', { buffer = buf, nowait = true })
  end
end

function _G.vimide_replace(old)
  if vim.bo.buftype ~= '' then
    vim.notify('여기서는 바꿀 수 없습니다 (편집 창에서 쓰세요)', vim.log.levels.WARN)
    return
  end
  if vim.bo.modifiable == false or vim.bo.readonly then
    vim.notify('이 파일은 고칠 수 없습니다', vim.log.levels.WARN)
    return
  end
  -- 빈 곳에서 불러도 창은 뜬다. Old 가 비어 있고 거기서부터 친다.
  old = (old and old ~= '') and old or vim.fn.expand('<cword>')
  ask_new(old or '')
end

api.nvim_create_user_command('VimIdeReplace', function(a) _G.vimide_replace(a.args) end,
  { nargs = '?', desc = '커서 밑 심볼을 이 파일에서 찾아 바꾼다' })
