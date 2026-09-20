-- qfpath.lua - quickfix 목록의 경로를 프로젝트 루트 기준으로 보여준다
--
-- 기본으로 vim 은 버퍼 이름을 그대로 쓴다. :Gtags 나 <C-g> 처럼 절대 경로로
-- 담기는 결과는 quickfix 창이 이렇게 보인다:
--
--   /home/B130111/work1/tsnd/dev/tsnd_2.0/Android14_IVI_1.1.0/kernel/common/drivers/char/tcc_ecid.c|80| ...
--
-- 앞의 예순 칸이 매번 같은 글자라 정작 읽어야 할 파일 이름과 본문이 밀려
-- 나간다. 프로젝트 루트를 기준으로 줄이면 이렇게 된다:
--
--   drivers/char/tcc_ecid.c|80| ...
--
-- 기준이 되는 루트는 RelationView 패널이 쓰는 것과 같다(색인이 있는 가장
-- 바깥 디렉터리). 그래야 패널과 quickfix 의 같은 파일이 같은 이름으로 보인다.
--
-- 옵션 (.vimrc)
--   g:vimide_qf_path  'root' (기본) 프로젝트 루트 기준
--                     'pwd'         지금 디렉터리 기준 (:pwd)
--                     'abs'         손대지 않는다 (예전 동작)
--   :VimIdeQfPath [root|pwd|abs]    지금 목록에 바로 적용해서 확인
--
-- 루트 밖의 파일(다른 프로젝트의 헤더 등)은 줄이지 않고 그대로 둔다 -
-- 줄이려다 ../../.. 가 되면 절대 경로보다 읽기 나쁘다.

if vim.g.loaded_vimide_qfpath then
  return
end
vim.g.loaded_vimide_qfpath = 1

if vim.fn.has('nvim-0.9') == 0 or vim.fn.exists('&quickfixtextfunc') == 0 then
  return
end

local function mode()
  local v = vim.g.vimide_qf_path
  if v == nil then
    return 'root'
  end
  v = tostring(v)
  return (v == 'pwd' or v == 'abs') and v or 'root'
end

-- 이 파일이 속한 프로젝트의 루트. RelationView 와 같은 답을 쓰고, 없으면
-- projectfiles 의 루트, 그것도 없으면 포기한다.
local root_cache = {}

local function root_of(path)
  local dir = vim.fs.dirname(path)
  if not dir or dir == '' then
    return nil
  end
  local hit = root_cache[dir]
  if hit ~= nil then
    return hit or nil
  end
  local r
  if type(_G.relationview_display_root) == 'function' then
    local ok, v = pcall(_G.relationview_display_root, path)
    if ok and type(v) == 'string' and v ~= '' then
      r = v
    end
  end
  if not r and type(_G.projectfiles_root_of) == 'function' then
    local ok, v = pcall(_G.projectfiles_root_of, path)
    if ok and type(v) == 'string' and v ~= '' then
      r = v
    end
  end
  root_cache[dir] = r or false
  return r
end

local function shorten(path)
  if path == '' then
    return path
  end
  local m = mode()
  if m == 'abs' then
    return path
  end
  local base = m == 'pwd' and vim.fn.getcwd() or root_of(path)
  if not base or base == '' or base == '/' then
    return path
  end
  base = base:gsub('/+$', '')
  if path:sub(1, #base + 1) == base .. '/' then
    return path:sub(#base + 2)
  end
  return path -- 루트 밖이다: 그대로 둔다
end

-- quickfix 창의 한 줄을 통째로 우리가 만든다. vim 의 기본 모양을 따른다:
--   파일|줄 col 칸|  본문
function _G.vimide_qftext(info)
  local what = { id = info.id, items = 1 }
  local got = info.quickfix == 1 and vim.fn.getqflist(what)
      or vim.fn.getloclist(info.winid, what)
  local items = got.items or {}
  local out = {}
  for i = info.start_idx, info.end_idx do
    local e = items[i]
    if not e then
      break
    end
    local name = ''
    if e.bufnr and e.bufnr > 0 then
      name = vim.fn.bufname(e.bufnr)
      if name ~= '' then
        name = shorten(vim.fn.fnamemodify(name, ':p'))
      end
    elseif e.module and e.module ~= '' then
      name = e.module
    end
    local where = ''
    if name ~= '' then
      where = name
      if (e.lnum or 0) > 0 then
        where = where .. '|' .. e.lnum
        if (e.col or 0) > 0 then
          where = where .. ' col ' .. e.col
        end
        if e.type and e.type ~= '' and e.type ~= ' ' then
          where = where .. ' ' .. e.type
        end
      end
      where = where .. '|'
    end
    local text = (e.text or ''):gsub('^%s+', ''):gsub('%s+$', '')
    out[#out + 1] = where == '' and text or (where .. ' ' .. text)
  end
  return out
end

vim.o.quickfixtextfunc = 'v:lua.vimide_qftext'

vim.api.nvim_create_user_command('VimIdeQfPath', function(a)
  if a.args ~= '' then
    vim.g.vimide_qf_path = a.args
  end
  root_cache = {}
  -- 담긴 것을 그대로 다시 넣어 창만 다시 그리게 한다.
  -- setqflist({}, 'r') 은 '빈 목록으로 갈아치우기'라 여기서 쓰면 안 된다 -
  -- 경로 표시를 바꾸려다 목록을 통째로 날린다.
  local cur = vim.fn.getqflist({ items = 1, title = 1 })
  if cur.items and #cur.items > 0 then
    pcall(vim.fn.setqflist, {}, 'r', { items = cur.items, title = cur.title })
  end
  vim.cmd('redraw!')
  vim.notify('quickfix 경로 표시: ' .. mode())
end, { nargs = '?', complete = function() return { 'root', 'pwd', 'abs' } end,
  desc = 'quickfix 경로를 루트 기준 / pwd 기준 / 절대 경로로' })
