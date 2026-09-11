-- neotree_nerd.lua - neo-tree 에서 NERDTree 의 K/J (형제 중 처음/마지막).
--
-- neo-tree 에는 이에 해당하는 명령이 없어서 직접 만든다. 나머지 NERDTree
-- 키(o O X I)는 neo-tree 의 명령에 그대로 붙일 수 있어 .vimrc 에서 맵으로만
-- 얹었다. 파일 조작 키(a A d r c m y x p u)는 neo-tree 것을 건드리지 않는다.

if vim.g.loaded_neotree_nerd then
  return
end
vim.g.loaded_neotree_nerd = 1

-- state.tree 에서 커서 노드의 형제 목록을 얻는다. 최상위 노드는 부모가
-- 없으므로 트리의 루트 자식들을 쓴다.
function _G.neotree_sibling(state, which)
  local ok, renderer = pcall(require, 'neo-tree.ui.renderer')
  if not ok or not state or not state.tree then
    return
  end
  local node = state.tree:get_node()
  if not node then
    return
  end
  local ids
  local pid = node:get_parent_id()
  if pid then
    local parent = state.tree:get_node(pid)
    ids = parent and parent:get_child_ids() or nil
  end
  if not ids then
    ids = state.tree:get_nodes()
    local out = {}
    for _, n in ipairs(ids) do
      out[#out + 1] = n:get_id()
    end
    ids = out
  end
  if not ids or #ids == 0 then
    return
  end
  local target = which == 'first' and ids[1] or ids[#ids]
  pcall(renderer.focus_node, state, target)
end
