-- marksjump.lua - :marks 를 텔레스코프로 보고 골라서 뛴다 (북마크)
--
-- vim 의 :marks 는 표를 한 번 뿌리고 끝이라, 스무 개쯤 쌓이면 눈으로 찾는
-- 일이 된다. 파일 이름이나 그 줄의 글자로 걸러 고를 수 있어야 쓸 만하다.
--
--   <C-m>            마크 목록 (g:vimide_marks_key 로 바꾼다)
--   :VimIdeMarks     같은 것
--
-- 목록에 무엇이 뜨나
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
--   <Esc> 뒤 d   그 마크를 지운다 (:delmarks). 노멀 모드에서만 -
--                검색창에서 d 를 치는 것은 글자 입력이어야 한다.
--
-- 옵션
--   g:vimide_marks_key   기본 '<C-m>'. '' 이면 키를 걸지 않는다.
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
    local path = m.file and vim.fn.fnamemodify(vim.fn.expand(m.file), ':p')
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
  return out
end

local function label(e)
  return ('%s %-2s  %-38s %5d  %s'):format(
    e.global and '↗' or ' ', e.name, e.short:sub(-38), e.lnum, e.text:sub(1, 60))
end

-- '직전에 보던 EDIT 창'에서 연다. 곁창에서 불러도 거기를 덮지 않는다.
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
  -- 마크로 뛰면 점프 목록에 자리가 남아 <C-o> 로 돌아올 수 있다
  pcall(vim.cmd, "normal! m'")
  local cur = api.nvim_buf_get_name(0)
  if vim.fn.fnamemodify(cur, ':p') ~= e.path then
    pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(e.path))
  end
  pcall(api.nvim_win_set_cursor, 0, { e.lnum, e.col })
  pcall(vim.cmd, 'normal! zz')
end

function _G.vimide_marks()
  local items = collect()
  if #items == 0 then
    vim.notify('찍어 둔 마크가 없습니다  (mA 처럼 대문자로 찍으면 파일을 넘나듭니다)',
      vim.log.levels.WARN)
    return
  end
  local t = telescope()
  if not t then
    local lines = {}
    for i, e in ipairs(items) do
      lines[#lines + 1] = ('%d. %s'):format(i, label(e))
    end
    local ok, idx = pcall(vim.fn.inputlist, vim.list_extend({ '마크로 가기:' }, lines))
    if ok and items[idx] then
      jump(items[idx])
    end
    return
  end
  t.pickers.new({}, {
    prompt_title = ('마크 %d개   <CR> 가기   <Esc>d 지우기'):format(#items),
    finder = t.finders.new_table({
      results = items,
      entry_maker = function(e)
        return {
          value = e,
          display = label(e),
          ordinal = e.name .. ' ' .. e.short .. ' ' .. e.text,
          filename = e.path,
          lnum = e.lnum,
        }
      end,
    }),
    sorter = t.conf.generic_sorter({}),
    previewer = t.conf.grep_previewer({}),
    attach_mappings = function(bufnr, map)
      t.actions.select_default:replace(function()
        local entry = t.state.get_selected_entry()
        t.actions.close(bufnr)
        if entry then
          -- 프롬프트가 닫히며 insert 를 빠져나갈 때 커서가 한 칸 왼쪽으로
          -- 밀린다. 한 박자 뒤에 뛴다.
          vim.schedule(function() jump(entry.value) end)
        end
      end)
      -- 'd' 는 노멀 모드에서만. 입력 모드에도 걸면 검색창에 d 를 칠 때마다
      -- 마크가 지워진다 - 'drivers' 를 치려다 두 개를 잃는다.
      map('n', 'd', function()
        local entry = t.state.get_selected_entry()
        if not entry then
          return
        end
        t.actions.close(bufnr)
        pcall(vim.cmd, 'delmarks ' .. entry.value.name)
        vim.notify(("마크 '%s' 를 지웠습니다"):format(entry.value.name))
      end)
      return true
    end,
  }):find()
end

api.nvim_create_user_command('VimIdeMarks', function() _G.vimide_marks() end,
  { desc = '찍어 둔 마크를 골라서 그 자리로' })
