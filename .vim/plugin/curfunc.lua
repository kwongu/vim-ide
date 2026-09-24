-- curfunc.lua - 상태줄의 '지금 함수' (airline 의 tagbar 자리) 를 treesitter 로
--
-- airline 의 tagbar 확장은 상태줄에 지금 함수를 보여 주려고 tagbar 를 깨운다.
-- 깨어난 tagbar 는 파일을 옮길 때(BufEnter)와 저장할 때마다 ctags 를 그 자리에서
-- 돌리고 그 출력을 Vim script 로 한 줄씩 푼다. 6600줄 C 파일(태그 608개)에서
-- 한 번에 약 340ms - <C-]> 로 다른 파일에 뛸 때마다, 저장할 때마다 화면이
-- 그만큼 멎었다 (개발서버 :profile 실측: ProcessFile 5번 1.69초). tagbar 창을
-- 열지 않아도 그렇다.
--
-- nvim 에서는 그 자리를 이 함수로 바꾼다 (.vimrc 의 AirlineAfterInit). 이미
-- 하이라이트 때문에 만들어 둔 구문 트리에서 커서를 감싸는 함수를 찾을 뿐이라
-- 프로세스도 파일 읽기도 없다. 모양은 tagbar 와 같다: 함수는 'name()', 함수
-- 밖에서는 감싸는 struct/union/enum 이름. 구문 분석기가 없는 파일에서는 빈칸.
-- 진짜 vim(서버의 vim 8.1)은 treesitter 가 없으니 tagbar 그대로다.
--
--   let g:vimide_curfunc = 0   " 되돌리기: tagbar 로 (다시 느려진다)

if vim.g.loaded_vimide_curfunc then
  return
end
vim.g.loaded_vimide_curfunc = 1

local api = vim.api

local FUNC = {
  function_definition = true,   -- C, C++, Python, ...
  function_declaration = true,  -- Lua, JS, Go
  local_function = true,        -- Lua (옛 문법)
  method_definition = true,
  method_declaration = true,
  function_item = true,         -- Rust
}
local TYPE = {
  struct_specifier = true,
  union_specifier = true,
  enum_specifier = true,
  class_specifier = true,
}

-- C/C++ 의 declarator 사슬(포인터, 괄호, 함수 declarator ...)을 따라 들어가
-- 가장 안쪽의 이름을 꺼낸다
local function inner_name(n, buf)
  local guard = 0
  while n and guard < 20 do
    guard = guard + 1
    local t = n:type()
    if t == 'identifier' or t == 'field_identifier' or t == 'qualified_identifier'
        or t == 'destructor_name' or t == 'operator_name' then
      return vim.treesitter.get_node_text(n, buf)
    end
    local d = n:field('declarator')[1]
    if not d then
      -- 괄호 declarator 등: 첫 이름 있는 자식
      d = n:named_child(0)
    end
    n = d
  end
  return nil
end

local function name_of(node, buf)
  local nm = node:field('name')[1]
  if nm then
    return vim.treesitter.get_node_text(nm, buf)
  end
  local d = node:field('declarator')[1]
  return d and inner_name(d, buf) or nil
end

-- 상태줄은 커서가 움직일 때마다 다시 그려진다. 같은 글자·같은 줄이면 답도
-- 같으니 담아 둔다.
local last = { buf = -1, tick = -1, line = -1, val = '' }

function _G.vimide_cur_func()
  local buf = api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' then
    return ''
  end
  local line = api.nvim_win_get_cursor(0)[1]
  local tick = api.nvim_buf_get_changedtick(buf)
  if last.buf == buf and last.tick == tick and last.line == line then
    return last.val
  end
  local val, answered = '', true
  -- 이미 있는 트리만 쓴다 (없으면 빈칸). 여기서 새로 분석하면 큰 파일에서
  -- 상태줄이 분석을 기다린다.
  local okp, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if okp and parser then
    local okn, node = pcall(vim.treesitter.get_node, { bufnr = buf, ignore_injections = true })
    -- 트리가 아직 없으면(큰 파일은 비동기로 분석한다) 빈칸을 담아 두지 않는다.
    -- 담아 두면 분석이 끝난 뒤에도 커서가 줄을 옮길 때까지 빈칸이었다 - <C-]>
    -- 로 다른 큰 파일에 뛰었을 때가 바로 그랬다 (반대 심문).
    --
    -- 커서 노드에서 parent() 로 거슬러 오른다. 루트에서 내려가며 형제를 Lua 로
    -- 훑는 쪽으로 바꿔 봤는데, parent() 는 C 안에서 싸게 돌고 형제 훑기는
    -- 형제마다 Lua 를 거쳐 60~1000배 느렸다 (반대 심문: 큰 파일에서 상태줄마다 5~7ms).
    answered = okn and node ~= nil
    local typename
    while okn and node do
      local t = node:type()
      if FUNC[t] then
        local nm = name_of(node, buf)
        if nm and nm ~= '' then
          val = nm .. '()'
          break
        end
      elseif TYPE[t] and not typename then
        typename = name_of(node, buf)
      end
      node = node:parent()
    end
    if val == '' and typename then
      val = typename
    end
  end
  if answered then
    last = { buf = buf, tick = tick, line = line, val = val }
  end
  return val
end
