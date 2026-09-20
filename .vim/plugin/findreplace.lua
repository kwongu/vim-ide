-- findreplace.lua - 커서 밑 심볼을 이 파일 안에서 찾아 바꾼다
--
-- <C-h> 또는 ,ch 를 누르면 떠 있는 창이 뜬다.
--
--   ╭─ 찾아 바꾸기 ──────────────────╮
--   │  Old   IO_UTIL_ReadECID        │
--   │  New   ▊                       │
--   ╰────────────────────────────────╯
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

-- 1단계: Old 를 보여주고 New 를 받는다
local function ask_new(old)
  local buf, win = float({ '  Old   ' .. old, '  New   ' }, {
    width = math.max(46, #old + 22),
    title = ' 찾아 바꾸기 ',
    footer = ' Enter 다음 · Esc 취소 ',
  })
  vim.bo[buf].filetype = 'vimide-replace'
  api.nvim_win_set_cursor(win, { 2, #'  New   ' })
  vim.cmd('startinsert!')

  local function done()
    local l = api.nvim_buf_get_lines(buf, 0, -1, false)
    local new
    for _, line in ipairs(l) do
      local m = line:match('^%s*New%s+(.*)$')
      if m then
        new = m
        break
      end
    end
    new = new or ''
    close(win)
    vim.cmd('stopinsert')
    if new == '' then
      vim.notify('바꿀 말이 비어 있습니다', vim.log.levels.WARN)
      return
    end
    if new == old then
      vim.notify('같은 말입니다', vim.log.levels.WARN)
      return
    end
    vim.schedule(function()
      local hits = count_hits(search_pat(old))
      if hits == 0 then
        vim.notify(("'%s' 를 이 파일에서 찾지 못했습니다"):format(old), vim.log.levels.WARN)
        return
      end
      ask_how(old, new, hits)
    end)
  end
  local function cancel()
    close(win)
    vim.cmd('stopinsert')
  end
  for _, m in ipairs({ 'n', 'i' }) do
    vim.keymap.set(m, '<CR>', done, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<Esc>', cancel, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<C-c>', cancel, { buffer = buf, nowait = true })
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
  old = (old and old ~= '') and old or vim.fn.expand('<cword>')
  if not old or old == '' then
    vim.notify('커서 밑에 바꿀 말이 없습니다', vim.log.levels.WARN)
    return
  end
  ask_new(old)
end

api.nvim_create_user_command('VimIdeReplace', function(a) _G.vimide_replace(a.args) end,
  { nargs = '?', desc = '커서 밑 심볼을 이 파일에서 찾아 바꾼다' })
