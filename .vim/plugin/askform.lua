-- askform.lua - 떠 있는 창에서 몇 칸을 받아 온다
--
-- 명령행 input() 대신 쓴다. 텔레스코프처럼 화면 가운데 뜨고, 칸 이름은
-- 지울 수 없으며, Tab 으로 칸을 오가고 마지막 칸에서 Enter 면 확정이다.
--
--   _G.vimide_ask({
--     title  = ' 찾기 ',
--     fields = { { label = '찾을 말', value = 'foo' },
--                { label = '찾을 곳', value = '/src', file = true } },
--     width  = 60,
--   }, function(vals) ... end)
--
-- 이름표는 버퍼 글자가 아니라 extmark 의 inline 가상 텍스트다. 버퍼에
-- 넣으면 지우다가 이름표까지 지워져서 그 줄이 무엇을 담는 칸인지 알 수
-- 없게 된다(찾아 바꾸기 창에서 실제로 겪었다).
--
-- file = true 인 칸에서는 <C-x><C-f> 로 경로를 완성한다. <Tab> 은 칸
-- 이동이라 완성에 쓸 수 없다.

if vim.g.loaded_vimide_askform then
  return
end
vim.g.loaded_vimide_askform = 1
if vim.fn.has('nvim-0.9') == 0 then
  return
end

local api = vim.api

-- 자동완성이 <Tab>/<CR> 을 가로채지 않게 잠깐 재운다 (찾아 바꾸기 창과 같다)
local function acp(on)
  if vim.fn.exists(':AcpEnable') == 2 then
    pcall(vim.cmd, on and 'AcpEnable' or 'AcpDisable')
  end
end

function _G.vimide_ask(spec, on_ok)
  spec = spec or {}
  local fields = spec.fields or {}
  if #fields == 0 then
    return
  end
  local lines, labw = {}, 0
  for _, f in ipairs(fields) do
    lines[#lines + 1] = tostring(f.value or '')
    labw = math.max(labw, vim.fn.strdisplaywidth(f.label or ''))
  end
  local width = spec.width or 64
  for _, l in ipairs(lines) do
    width = math.max(width, #l + labw + 8)
  end
  width = math.min(width, math.max(40, vim.o.columns - 8))

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].complete = ''
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 2),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = 'minimal',
    border = 'rounded',
    title = spec.title,
    title_pos = 'center',
    footer = spec.footer or ' Tab 칸 이동 · Enter 확인 · Esc 취소 ',
    footer_pos = 'center',
    zindex = 200,
  })
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder'
  acp(false)

  local NS = api.nvim_create_namespace('vimide_askform')
  for i, f in ipairs(fields) do
    pcall(api.nvim_buf_set_extmark, buf, NS, i - 1, 0, {
      virt_text = { { ('  %-' .. labw .. 's  '):format(f.label or ''), 'Question' } },
      virt_text_pos = 'inline',
      right_gravity = false,
    })
  end

  local done = false
  local function goto_line(n)
    local l = api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ''
    pcall(api.nvim_win_set_cursor, win, { n, #l })
    vim.cmd('startinsert!')
  end
  local function finish(vals)
    if done then
      return
    end
    done = true
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
    acp(true)
    vim.cmd('stopinsert')
    if vals and on_ok then
      vim.schedule(function() on_ok(vals) end)
    end
  end
  local function values()
    local out = {}
    for i = 1, #fields do
      local l = api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ''
      out[i] = (l:gsub('^%s+', ''):gsub('%s+$', ''))
    end
    return out
  end
  local function confirm()
    local cur = api.nvim_win_get_cursor(win)[1]
    -- 아직 뒤 칸이 비어 있으면 Enter 는 '다음 칸으로'다
    for i = cur + 1, #fields do
      if (api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or '') == '' then
        goto_line(i)
        return
      end
    end
    finish(values())
  end
  local function other(step)
    local cur = api.nvim_win_get_cursor(win)[1]
    local n = cur + step
    if n < 1 then n = #fields elseif n > #fields then n = 1 end
    goto_line(n)
  end

  for _, m in ipairs({ 'n', 'i' }) do
    vim.keymap.set(m, '<CR>', confirm, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<Tab>', function() other(1) end, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<S-Tab>', function() other(-1) end, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<Esc>', function() finish(nil) end, { buffer = buf, nowait = true })
    vim.keymap.set(m, '<C-c>', function() finish(nil) end, { buffer = buf, nowait = true })
  end
  -- 칸 경계에서 줄이 합쳐지지 않게. 합쳐지면 이름표 둘이 한 줄에 겹친다.
  vim.keymap.set('i', '<BS>', function()
    return api.nvim_win_get_cursor(win)[2] == 0 and '' or '<BS>'
  end, { buffer = buf, expr = true, replace_keycodes = true, nowait = true })
  vim.keymap.set('i', '<Del>', function()
    local c = api.nvim_win_get_cursor(win)
    local l = api.nvim_buf_get_lines(buf, c[1] - 1, c[1], false)[1] or ''
    return c[2] >= #l and '' or '<Del>'
  end, { buffer = buf, expr = true, replace_keycodes = true, nowait = true })
  for _, k in ipairs({ 'o', 'O', 'dd', 'J', 'gJ' }) do
    vim.keymap.set('n', k, '<Nop>', { buffer = buf, nowait = true })
  end

  goto_line(1)
  -- 첫 칸이 이미 차 있으면 다음 빈 칸에서 시작한다 - 커서 밑 낱말이
  -- 들어온 자리에서 다시 칠 일은 드물다.
  for i = 1, #fields do
    if (lines[i] or '') == '' then
      goto_line(i)
      break
    end
  end
end
