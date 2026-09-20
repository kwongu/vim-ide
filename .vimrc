scripte utf-8
" vim: set fenc=utf-8 tw=0:

"==============================================================================
" General
"==============================================================================

" Revert all command settings before proceeding with other settings below
"
" 'set all&' 은 'columns'/'lines' 까지 기본값(80x24)으로 되돌린다. 터미널은
" 시작할 때 크기를 한 번 알려 주고 그 뒤로는 창이 바뀔 때만 알리므로, 여기서
" 되돌려 놓으면 화면이 80x24 인 채로 남는다. Ctrl+Z 로 나갔다 fg 로 돌아오면
" 그때 SIGWINCH 가 와서 제 크기가 되고, 그래서 '두 번째부터는 정상'으로
" 보였다. telescope 는 layout_config 의 비율(0.8)을 columns/lines 에 곱해
" 창 크기를 정하기 때문에 이게 그대로 작은 대화상자로 나타난다.
let s:vimide_size = [&columns, &lines]

set all&

" 붙어 있는 UI 의 크기가 권위 있는 값이다. UI 가 아직 없으면(--embed 로 띄운
" 경우) 붙을 때 알아서 맞춰지므로, 여기서는 되돌리기만 한다.
if has('nvim') && !empty(nvim_list_uis())
    let &columns = nvim_list_uis()[0].width
    let &lines = nvim_list_uis()[0].height
elseif s:vimide_size[0] > 0 && s:vimide_size[1] > 0
    let &columns = s:vimide_size[0]
    let &lines = s:vimide_size[1]
endif
unlet s:vimide_size

" 'set all&' resets 'runtimepath' too. Vim's built-in default includes
" ~/.vim, but nvim's does not - restore it so colors/ and plugin/ keep
" loading when this file is sourced from nvim (~/.config/nvim/init.vim).
if has('nvim')
    set runtimepath^=~/.vim
    set runtimepath+=~/.vim/after
endif

" 색인은 프로젝트 루트의 숨김 디렉터리 '.tags/' 에 있다. global(1) 은 위로
" 올라가며 '<dir>/$GTAGSOBJDIR/GTAGS' 도 함께 찾으므로, 이 한 줄이면
" :Gtags/gtags-cscope/RelationView/':!global' 이 모두 같은 DB 를 본다
" (루트에 예전처럼 GTAGS 가 있는 프로젝트도 그대로 동작한다).
" nvim 분기 밖에 두는 이유: plain vim 은 ~/.vim/plugin/*.lua 를 읽지 않아
" autoindex.lua 가 돌지 않는다. 이 줄이 두 편집기 모두를 덮는다.
" 터미널에서도 쓰려면 ~/.zshenv 에:  export GTAGSOBJDIR=.tags
let $GTAGSOBJDIR = get(g:, 'autoindex_dbdir', '.tags')

" Work in Vim compatible not Vi compatible
set nocompatible

" Keep 50 commands and 50 search patterns in the history.
" 50 is undo limit.
set history=100

" No need to understand this. Leave this when using Vim.
set magic

" No swap file. It's messy.
set noswapfile

" No backup file. You take your risk on your own.
set nobackup

" Turn on plugin and indent, depending on file type
filetype plugin indent on

" 매핑 두 키짜리를 얼마나 기다릴까.
"
" 예전에는 notimeout 이었다 - '\fr' 처럼 두 키짜리 매핑에서 다음 키를
" 영원히 기다린다는 뜻이다. 느긋해서 좋았지만, <C-]> 처럼 '한 번 눌러도
" 되고 두 번 눌러도 되는' 키가 생기면서 탈이 났다: 한 번만 누르면 vim 이
" 두 번째 키를 기다리느라 아무 일도 하지 않는다. 그래서 timeout 을 켜고
" 시간을 짧게 둔다.
"
" 대가: \fr \lt 같은 리더 매핑도 키 사이 간격이 이 시간을 넘으면 안 된다.
" 250 -> 500 -> 800 으로 올려 왔다. 리더 매핑(\fr \lt)이 쫓기지 않는 쪽을
" 우선한다 - <C-]> 한 번이 그만큼 늦게 뛰는 것은 감수한다.
"
"   let g:vimide_map_timeoutlen = 300   " <C-]> 를 더 빨리 (리더는 빠듯해진다)
"   let g:vimide_map_timeout = 0        " 예전처럼 영원히 기다린다
"                                       " (<C-]> 를 한 번만 쓰고 싶으면
"                                       "  g:vimide_ctx_jump_seq = 0 과 함께)
"
" ttimeout 은 따로다 - 아래 ttimeoutlen 은 키 코드(방향키 등)용이다.
if get(g:, 'vimide_map_timeout', 1)
	set timeout
else
	set notimeout
endif
set ttimeout

" In Milliseconds
" ttimeoutlen 은 Esc 를 눌렀을 때 '이게 방향키 같은 이스케이프 시퀀스의
" 시작인가'를 기다리는 시간이다. 100ms 면 SSH 왕복까지 더해 Esc 한 번이
" 실측 131ms 였다 - 삽입 모드를 빠져나올 때마다 매번. 25ms 로 줄이면 26ms 다.
" 0 으로 두지 않는 이유: 방향키의 ESC 시퀀스가 TCP 세그먼트로 쪼개져 도착할
" 여유는 남겨야 오작동이 없다. 25ms 는 실측 RTT(11.8ms)의 두 배다.
"   let g:vimide_esc_wait = 100   " 예전 동작으로 되돌리기
let &timeoutlen = get(g:, 'vimide_map_timeoutlen',
			\ get(g:, 'vimide_map_timeout', 1) ? 800 : 3000)
let &ttimeoutlen = get(g:, 'vimide_esc_wait', 25)

" Not redraw while executing macros, and commands.
set lazyredraw

"set visualbell

" Turn on syntax highlighting
syntax on

set backspace=indent,eol,start " for backspace

" 되돌리기를 파일에 남긴다: 어제 편집한 것도 오늘 u 로 되돌릴 수 있다.
" (Source Insight 의 checkpoint/Restore Lines 에 해당하는 부분)
" 저장 위치는 nvim 기본값 ~/.local/state/nvim/undo/ 이며 없으면 알아서 만든다.
set undofile
"set termguicolors

"==============================================================================
" Vim Plugin Settings
"==============================================================================

" Load plugins when starting up
set loadplugins

filetype off                   " required!

" NERDTree 를 쓸까.
"
" nvim 에서는 기본으로 끈다. 같은 일을 neo-tree(F9)가 하고 있고, NERDTree 는
" NERDTreeHijackNetrw 로 디렉터리를 가로채는 탓에 :e . 한 번에 곁창이
" 없어지는 사고의 근원이었다(실측: aerial 창이 통째로 사라졌다).
" 진짜 vim 8.1(개발서버)에는 neo-tree 가 없으므로 거기서는 그대로 쓴다.
"
"   let g:vimide_nerdtree = 1   " nvim 에서도 NERDTree 를 쓴다
if !exists('g:vimide_nerdtree')
	let g:vimide_nerdtree = has('nvim') ? 0 : 1
endif

" 아이콘을 ASCII 로 내릴지. 여기서 정한다 - 진짜 vim 도 지나는 자리다.
"
" 예전에는 이 판정이 아래 'if has(\'nvim\')' 블록 안(702줄)에 있었다. 그런데
" 쓰는 쪽(airline 구분자)은 그 블록 밖이라, 진짜 vim 에서는 변수가 없는 채로
" 읽혔다:
"   E121: Undefined variable: g:vimide_ascii_icons
" vim 은 시작 중에 에러를 보이면 2초를 멈춰 서서 보여 준다(startuptime 의
" 'Warning delay' 2005ms). vim 시작이 2.3초였던 것의 거의 전부가 이것이었다.
" 정의만 앞으로 올린다 - 아래 702줄은 !exists 로 감싸 있어 그대로 두어도
" 아무 일도 하지 않는다.
"
"   let g:vimide_ascii_icons = 1   " 늘 ASCII 로
"   let g:vimide_ascii_icons = 0   " 늘 Nerd Font 로
if !exists('g:vimide_ascii_icons')
    let g:vimide_ascii_icons = ($TERM ==# 'xterm-color')
endif

" set the runtime path to include Vundle and initialize
if has('nvim')

call plug#begin('~/.vim/plugged')

" let Vundle manage Vundle, required
Plug 'VundleVim/Vundle.vim'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-unimpaired'
Plug 'preservim/nerdcommenter'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
" Source Insight 기본 테마(순백 배경 + 진한 네이비 키워드 + 초록 주석)에
" 가장 가까운 라이트 테마. 적용은 파일 끝의 '테마' 절에서 한다.
Plug 'NLKNguyen/papercolor-theme'
Plug 'inkarkat/vim-ingo-library'
Plug 'inkarkat/vim-mark'
Plug 'ervandew/supertab'
Plug 'jlanzarotta/bufexplorer'
Plug 'ivechan/gtags.vim'
Plug 'ronakg/quickr-cscope.vim'
Plug 'vim-scripts/grep.vim'
Plug 'vim-scripts/AutoComplPop'
"Plug 'vim-scripts/The-NERD-tree'
"Plug 'vim-scripts/Tagbar'
"Plug 'ryanoasis/vim-devicons'
"Plug 'kyazdani42/nvim-web-devicons'
if get(g:, 'vimide_nerdtree', 1)
	Plug 'preservim/nerdtree'
	Plug 'Xuyuanp/nerdtree-git-plugin'
endif
Plug 'preservim/tagbar'
Plug 'vim-utils/vim-troll-stopper'
Plug 'Raimondi/delimitMate'
" nvim 에서는 gitsigns 가 왼쪽 기둥을 맡는다. 둘 다 켜면 같은 자리에 두 번
" 그리고, 한쪽이 지운 표시를 다른 쪽이 되살려 깜빡인다. 진짜 vim 8.1(개발
" 서버)에는 gitsigns(lua)가 없으므로 거기서는 signify 가 그대로 맡는다.
"   let g:vimide_signify_in_nvim = 1   " 예전처럼 nvim 에서도 signify 를
if has('nvim') && !get(g:, 'vimide_signify_in_nvim', 0)
    let g:signify_disable_by_default = 1
endif
Plug 'mhinz/vim-signify'
Plug 'terryma/vim-smooth-scroll'
"Plug 'ctrlpvim/ctrlp.vim'
"Plug 'SirVer/ultisnips'
"Plug 'honza/vim-snippets'
"Plug 'airblade/vim-gitgutter'
"Plug 'altercation/vim-colors-solarized'
"Plug 'ludovicchabant/vim-gutentags'
"Plug 'skywind3000/gutentags_plus'
"Plug 'terryma/vim-multiple-cursors'
"
" coc.nvim Plugin Install
Plug 'neovim/nvim-lspconfig'
"Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'weirongxu/coc-explorer'
Plug 'SmiteshP/nvim-navic'
"Plug 'liuchengxu/vista.vim'
" nvim-tree.lua Plugin Install
Plug 'kyazdani42/nvim-tree.lua'
Plug 'nvim-tree/nvim-web-devicons'
"Plug 'Shougo/defx.nvim'

Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'nvim-lua/popup.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'nvim-telescope/telescope-fzf-native.nvim', { 'do': 'make' }
"Plug 'nvim-telescope/telescope.nvim', { 'tag': '0.1.5' }
" or                                , { 'branch': '0.1.x' }

Plug 'ronakg/quickr-preview.vim'

" Magit 스타일 git UI + diff 뷰어
Plug 'NeogitOrg/neogit'
Plug 'sindrets/diffview.nvim'
Plug 'lewis6991/gitsigns.nvim'
" Source Insight 스타일: ctags 자동 색인 / 심볼 아웃라인 / 파일 트리
Plug 'ludovicchabant/vim-gutentags'
Plug 'stevearc/aerial.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'nvim-neo-tree/neo-tree.nvim', { 'branch': 'v3.x' }

" supertab 이 로드되기 전에 nvim 의 기본 <S-Tab> 삽입 맵핑을 치운다.
"
" nvim 0.12 는 <Tab>/<S-Tab> 을 'snippet 이 활성이면 점프, 아니면 원래 키'
" 라는 Lua expr 맵핑으로 잡아 둔다(vim/_core/defaults:241). supertab 은
" 사용자가 이미 걸어 둔 <S-Tab> 맵핑을 보존하려고 그것을 함수로 만들려
" 하는데(plugin/supertab.vim:974  let s:ShiftTab = function(stab)), 넘어오는
" 값이 '<Lua 28: vim/_core/defaults:241>' 라서 실패한다. 그래서 nvim 을 켤
" 때마다 아래 두 줄이 떴다:
"     E129: Function name required
"     E475: Invalid argument: <Lua 28: vim/_core/defaults:241>
"
" 없애는 것이 아니라 순서를 맞추는 것이다: supertab 은 어차피 바로 뒤에서
" <S-Tab> 을 <Plug>SuperTabBackward 로 다시 맵핑하므로, 삽입 모드의 기본
" 맵핑은 지금 지워도 최종 상태가 같다. select 모드('s')의 같은 맵핑은
" 그대로 남으므로, snippet placeholder 안에서의 <S-Tab> 점프는 계속 된다
" (iunmap 은 {'i','s'} 중 삽입 모드만 떼어 낸다).
"
" <Tab> 쪽은 건드리지 않는다. supertab 의 <tab> 분기는 smart-tab 플러그인
" 패턴(\d\+_InsertSmartTab()$)만 보고 Lua 맵핑에는 반응하지 않아서 문제가
" 없고, 필요 없는 변경을 더하지 않는다.
"
"   let g:vimide_keep_snippet_tab = 1   " 이 손질을 하지 않는다(에러는 다시 뜬다)
if has('nvim') && get(g:, 'vimide_keep_snippet_tab', 0) == 0
            \ && has_key(get(g:, 'plugs', {}), 'supertab')
    silent! iunmap <S-Tab>
endif

call plug#end()
" ------------------------------------
" settings for nvim default
" ------------------------------------
lua << EOF
require'nvim-web-devicons'.setup { default = true }
EOF

" ------------------------------------
" option for lspconfig
" ------------------------------------
lua << EOF
require'nvim-navic'.setup {}
EOF

"lua << EOF
"require'lspconfig'.clangd.setup{}
"EOF


" ------------------------------------
" option for nvim-tree
" ------------------------------------
"open_on_setup = true,
lua << EOF
require'nvim-tree'.setup {
    -- 기본 설정
  open_on_tab = false,         -- 탭에서 자동으로 열기 (기본값: false)
  hijack_netrw = true,         -- netrw를 대체 (기본값: true)
  update_cwd = true,           -- 현재 작업 디렉토리 업데이트 (기본값: false)

  -- 렌더링 관련 설정
  renderer = {
    highlight_opened_files = "all", -- 열려 있는 파일 강조 (기본값: 'none')
    icons = {
      show = {
	file = true,
	folder = true,
	folder_arrow = true,
	git = true,
      },
    },
  },

  -- 필터링 관련 설정
  filters = {
    dotfiles = false,           -- 숨김 파일 표시 여부 (기본값: false)
    custom = {},                 -- 사용자 정의 필터 목록 (기본값: {})
  },

  -- 진단 관련 설정
  diagnostics = {
    enable = false,             -- 진단 정보 표시 여부 (기본값: false)
  },

  -- Git 관련 설정
  git = {
    enable = true,              -- Git 상태 표시 여부 (기본값: true)
    ignore = false,             -- Git 상태 무시 여부 (기본값: false)
  },

  -- 파일 열기 관련 설정
  actions = {
    open_file = {
      quit_on_open = true,      -- 파일 열 때 자동으로 닫기 (기본값: true)
      resize_window = true,    -- 창 크기 조정 (기본값: true)
    },
  },

  -- 파일 찾기 관련 설정
  view = {
    width = 40,                 -- 사이드바의 너비 (기본값: 30)
    side = 'right',              -- 사이드바 위치 (기본값: 'left')
  },
}
EOF


"Emphasize token under the cusor 
"autocmd CursorHold * silent call CocActionAsync('highlight')
" ------------------------------------
" nvim-treesitter setting
" ------------------------------------
lua << EOF
require'nvim-treesitter.configs'.setup {
	ensure_installed = { "vim", "c", "cpp", "lua", "rust", "python"},
	ignore_install = { "" },
		highlight = {
			enable = true,
			disable = { "" },
			additional_vim_regex_highlighting = true,
		},
	}
EOF

" ------------------------------------
" nvim-telescope setting
" ------------------------------------
lua << EOF
require'telescope'.setup{
	defaults = {
		prompt_prefix = "$ ",
		layout_config = {
			width = 0.80,
			height = 0.80,
			preview_cutoff = 120,
		},
		-- 고른 파일을 '직전에 포커스가 있던 편집 창'에 연다.
		--
		-- telescope 는 기본으로 0(=지금 창)을 돌려주는데, 픽커를 부른 자리가
		-- 트리나 아웃라인 같은 옆 창이면 그 옆 창에 파일이 열려 버린다.
		-- relationview.lua 가 편집 창만 골라 기억해 둔 것을 쓴다
		-- (_G.vimide_last_edit_win, 없으면 0 으로 떨어져 예전 동작).
		--
		-- 이 한 줄이 telescope 픽커 전부에 걸린다 - \ff \fg \fb \fr ... 포함.
		-- 0 으로 떨어지면 '지금 창' 이라는 뜻이라, 곁창만 있는 탭
		-- (Neogit/Diffview 탭이나 편집 창을 닫아 둔 탭)에서는 그 곁창이
		-- 파일에 덮였다. 편집 자리를 빌려 쓰는 창까지 본 뒤(edit_slot),
		-- 그래도 없으면 편집 창을 하나 만들어 그 창을 준다.
		get_selection_window = function()
			for _, f in ipairs({ _G.vimide_last_edit_win, _G.vimide_edit_slot }) do
				if type(f) == 'function' then
					local ok, w = pcall(f)
					if ok and type(w) == 'number' and w ~= 0
							and vim.api.nvim_win_is_valid(w) then
						return w
					end
				end
			end
			if type(_G.vimide_is_edit_win) == 'function'
					and not _G.vimide_is_edit_win() then
				local w
				local ok = pcall(function()
					vim.cmd('noautocmd topleft vertical split')
					w = vim.api.nvim_get_current_win()
				end)
				if ok and w and vim.api.nvim_win_is_valid(w) then
					for _, o in ipairs({ 'winfixbuf', 'winfixwidth',
						'winfixheight', 'previewwindow' }) do
						pcall(function() vim.wo[w][o] = false end)
					end
					return w
				end
			end
			return 0
		end,
	}
}
require'telescope'.load_extension'fzf'
EOF

" ------------------------------------
" Neogit (Magit for nvim) + diffview + gitsigns
"
" Emacs 의 Magit 과 같은 흐름을 셋이 나눠 맡는다.
"   Neogit    상태 화면, 스테이징, 커밋, 푸시 (Magit 의 팝업 메뉴)
"   Diffview  파일별 변경점을 나란히, 충돌은 3-way 로
"   gitsigns  편집 중인 창의 왼쪽 기둥에 실시간 표시 + 헝크 단위 조작
"
"   <leader>s : Neogit 상태 화면(새 탭)  -  s/u 스테이징, cc 커밋, P 푸시
"   <leader>v : DiffviewOpen (작업 트리 전체 diff)
"   <leader>ha: 커서 헝크를 스테이징       (비주얼로 고른 줄만도 된다)
"   <leader>hr: 커서 헝크를 되돌린다       (비주얼도 같다)
"   <leader>hv: 커서 헝크를 띄워 본다
"   <leader>ht: 이 줄 blame 을 켜고 끈다
"   ]h / [h   : 다음 / 이전 헝크
"   (<leader>m 은 vim-mark 가, <leader>g 는 :Gtags 가 이미 쓰고 있다.
"    \h* 는 예전 gitgutter 용으로 주석만 남아 있던 자리를 되살린 것이다)
"
" 왼쪽 기둥 표시는 nvim 에서 gitsigns 가, 진짜 vim 8.1 에서는 vim-signify 가
" 맡는다. 둘을 같이 켜면 같은 자리에 두 번 그린다 - 아래에서 갈라 둔다.
" ------------------------------------
lua << EOF
-- 아직 :PlugInstall 을 돌리지 않은 상태에서도 startup 이 깨지지 않게 한다
local function rv_setup(mod, opts)
  local ok, m = pcall(require, mod)
  if ok and type(m) == 'table' and m.setup then
    pcall(m.setup, opts)
  end
end
_G.rv_setup = rv_setup

rv_setup('neogit', {
  kind = 'tab',                                  -- Magit 처럼 새 탭에서 열기
  integrations = { diffview = true, telescope = true },
  disable_insert_on_commit = 'auto',
})
-- diffview 는 q 를 option_panel 과 help_panel 에만 걸어 둔다. 정작 파일
-- 패널과 diff 창에는 없어서, 이 IDE 의 다른 패널처럼 q 를 눌러도 아무 일도
-- 일어나지 않는다(눌러도 매크로 기록이 시작될 뿐이다). 여기 셋에 걸어 준다 -
-- RelationView 패널, quickfix, aerial 이 모두 q 로 닫히므로 손이 그걸 기억한다.
local dv_actions = (function()
  local ok, a = pcall(require, 'diffview.actions')
  return ok and a or nil
end)()
rv_setup('diffview', {
  keymaps = {
    view = {
      { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Diffview 닫기' } },
      -- <C-n>/<C-p> 를 ]c / [c 와 같은 자리로 (요청).
      --
      -- 이 두 키는 평소 RelationView 목록 이동이지만, diffview 의 keymaps 는
      -- 그 버퍼에만 걸리므로 밖에서는 예전 그대로다. ]c / [c 도 살아 있다.
      --
      -- 하는 일은 ]c / [c 그대로다. 마지막(처음) 변경에서 한 번 더 눌러도
      -- 거기 머문다 - vim 의 본래 동작이고, 한 바퀴 돌게 만들면 '끝인 줄
      -- 알았는데 처음으로 튀는' 놀람이 생긴다. pcall 은 에러가 나는 판에서
      -- 조용히 지나가려는 것뿐이다(실측: 이 판은 에러 없이 머문다).
      { 'n', '<C-n>', function() pcall(vim.cmd, 'normal! ]c') end,
        { desc = '다음 변경 (]c 와 같다)' } },
      { 'n', '<C-p>', function() pcall(vim.cmd, 'normal! [c') end,
        { desc = '이전 변경 ([c 와 같다)' } },
    },
    file_panel = {
      { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Diffview 닫기' } },
      -- 패널에서는 '다음 변경'이 곧 '다음 파일'이다. 같은 키로 이어지게 한다.
      { 'n', '<C-n>', dv_actions and dv_actions.select_next_entry, { desc = '다음 파일의 diff' } },
      { 'n', '<C-p>', dv_actions and dv_actions.select_prev_entry, { desc = '이전 파일의 diff' } },
    },
    file_history_panel = {
      { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Diffview 닫기' } },
    },
  },
})

-- gitsigns: 편집 중인 창의 왼쪽 기둥과 헝크 단위 조작
--
-- 이 줄 blame(current_line_blame)은 기본으로 꺼 둔다. 커서가 멈출 때마다
-- 'git blame -L' 을 그 파일에 돌리는데, 이 설정이 다루는 트리는 커널
-- (6만 파일)이고 더러 SMB/OneDrive 위에 있다. 예전에 nerdtree-git-plugin 의
-- git status 폭주로 맥이 뜨거워진 전례가 있어(50GB 읽기) 기본값으로 켜지
-- 않는다. \ht 로 언제든 켠다.
--   let g:gitsigns_blame_on = 1    " 처음부터 켜 두고 싶으면
rv_setup('gitsigns', {
  current_line_blame = (tonumber(vim.g.gitsigns_blame_on) or 0) ~= 0,
  current_line_blame_opts = { delay = 500, virt_text_pos = 'eol' },
  -- 큰 파일에서는 손을 뗀다 (커널에는 1만 줄짜리 헤더가 흔하다)
  max_file_length = tonumber(vim.g.gitsigns_max_lines) or 40000,
  attach_to_untracked = false,
})
EOF
nnoremap <silent> <Leader>s <Cmd>Neogit<CR>
" diffview 는 git 2.31 이상이 필요하다.
"
" 개발서버의 git 은 2.25.1 이라 :DiffviewOpen 이 'Not a repo (or any parent),
" or no supported VCS adapter!' 만 남기고 아무 일도 하지 않는다. 저장소가
" 아니어서가 아니라 git 이 낡아서인데, 그 말로는 알 수가 없다. 대신 말해 준다.
" (맥은 2.54 라 그냥 열린다. Neogit 과 gitsigns 는 낡은 git 에서도 된다)
func! s:Diffview() abort
	if !exists('s:diffview_git')
		let s:diffview_git = matchstr(system('git --version'), '\d\+\.\d\+\(\.\d\+\)\?')
		let l:p = split(s:diffview_git, '\.')
		let s:diffview_ok = len(l:p) >= 2 &&
					\ (str2nr(l:p[0]) > 2 ||
					\  (str2nr(l:p[0]) == 2 && str2nr(l:p[1]) >= 31))
	endif
	" 이미 떠 있으면 닫는다. 같은 키로 열고 닫는 편이 손에 맞고, 'q 가
	" 안 먹는다' 로 헤맬 일도 없다.
	if has('nvim') && exists('*luaeval')
		let l:open = luaeval('(function() local ok, l = pcall(require, "diffview.lib") '
					\ . 'if not ok or type(l.views) ~= "table" then return 0 end '
					\ . 'return #l.views > 0 and 1 or 0 end)()')
		if l:open == 1
			DiffviewClose
			return
		endif
	endif
	if !s:diffview_ok
		echohl WarningMsg
		echo printf('diffview 는 git 2.31 이상이 필요합니다 (여기는 %s). '
					\ . 'Neogit(\s)과 gitsigns(\ha \hv)는 그대로 됩니다.',
					\ empty(s:diffview_git) ? '알 수 없음' : s:diffview_git)
		echohl None
		return
	endif
	DiffviewOpen
endfunc
nnoremap <silent> <Leader>v :call <SID>Diffview()<CR>

" 헝크 단위 조작. nvim 에서만 - gitsigns 가 없으면 아무 일도 하지 않는다.
if has('nvim')
    nnoremap <silent> <Leader>ha <Cmd>Gitsigns stage_hunk<CR>
    nnoremap <silent> <Leader>hr <Cmd>Gitsigns reset_hunk<CR>
    " 비주얼로 고른 줄만 스테이징/되돌리기 (헝크 전체가 아니라)
    xnoremap <silent> <Leader>ha :Gitsigns stage_hunk<CR>
    xnoremap <silent> <Leader>hr :Gitsigns reset_hunk<CR>
    nnoremap <silent> <Leader>hv <Cmd>Gitsigns preview_hunk<CR>
    nnoremap <silent> <Leader>hu <Cmd>Gitsigns undo_stage_hunk<CR>
    nnoremap <silent> <Leader>ht <Cmd>Gitsigns toggle_current_line_blame<CR>
    " ]c / [c 는 vim 의 diff 모드가 쓰는 자리라 ]h / [h 로 둔다
    nnoremap <silent> ]h <Cmd>Gitsigns next_hunk<CR>
    nnoremap <silent> [h <Cmd>Gitsigns prev_hunk<CR>
endif

" ------------------------------------
" aerial: 현재 파일의 심볼 아웃라인(Source Insight 의 Symbol Window)
"   <leader>o 로 토글. treesitter 백엔드라 LSP 없이도 동작한다.
"   F10 도 같은 aerial 을 연다(예전에는 tagbar 였다 - 파일 열기가 태그 수에
"   비례해 느려져서 바꿨다. :Tagbar 로 tagbar 는 그대로 쓸 수 있다)
"
" g:vimide_outline_global
"   1 (기본) 아웃라인은 화면 맨 왼쪽에 '하나만' 선다. EDIT 를 4분할로 쓰든
"            몇 개로 쓰든 창은 하나고, 포커스를 옮기면 그 창의 파일로 내용이
"            바뀐다. aerial 의 attach_mode='global' + layout.placement='edge'.
"   0        예전 방식. EDIT 창마다 그 창에 붙은 아웃라인이 따로 뜬다
"            (attach_mode='window' + placement='window').
"
"   이 둘은 aerial 이 setup 에서 한 번 읽으므로 바꾸면 nvim 을 다시 켜야 한다.
"
"   'edge' 는 'vertical topleft' 로 연다(aerial/window.lua). 그래서 왼쪽
"   neo-tree 가 떠 있으면 aerial 이 그보다 더 바깥(맨 왼쪽)에 선다.
"   순서는 aerial | neo-tree | EDIT 다.
if !exists('g:vimide_outline_global')
    let g:vimide_outline_global = 1
endif
" ------------------------------------
lua << EOF
local outline_global = (tonumber(vim.g.vimide_outline_global) or 1) ~= 0
_G.rv_setup('aerial', {
  backends = { 'treesitter', 'lsp', 'markdown', 'man' },
  -- 아웃라인은 tagbar 시절부터 왼쪽에 있었다(g:tagbar_left=1). 그 자리를
  -- 그대로 쓴다 - 오른쪽은 RelationView 의 context 창이 쓰고 있다.
  --   placement='edge'   화면 맨 왼쪽에 세로 전체로. 어느 EDIT 에서 열든
  --                      같은 자리다.
  --   placement='window' 지금 창을 쪼갠다 (예전 방식).
  layout = {
    default_direction = 'left',
    width = 40,
    placement = outline_global and 'edge' or 'window',
  },
  -- 아웃라인은 F10 으로 켤 때만 연다.
  --
  -- 예전에는 심볼이 있는 파일을 열면 알아서 떴다. 문제는 aerial 이
  -- attach_mode = 'window' 라, '파일을 열 때'가 아니라 '편집 창에 들어갈
  -- 때마다' 이 함수를 다시 묻는다는 것이다. 창을 나누고 새 창으로 포커스를
  -- 옮기면 거기에도 또 떴고, F10 으로 닫아도 다음 창에 들어가는 순간 되살아
  -- 났다. 끈 것이 꺼진 채로 있지 않으면 그건 토글이 아니다.
  --
  -- 그래서 자동으로 여는 길을 아예 없앴다. 여는 것은 F10, <leader>o,
  -- :AerialOpen 뿐이고 셋 다 사람이 누르는 것이다.
  --
  -- 예전처럼 알아서 열리게 하려면:
  --   let g:vimide_outline_auto = 1
  --
  -- 그때 쓰던 검사는 그대로 남겨 둔다. neo-tree 가 떠 있으면 열지 않는다 -
  -- 둘 다 왼쪽을 쓰기 때문에 aerial 이 끼어들어 트리를 밀어낸다. true 를
  -- 주면 aerial 이 'is_ignored_buf 가 아니면 연다'로 바꿔 주므로, 함수로 줄
  -- 때도 그 검사를 그대로 이어 간다.
  -- 값은 부를 때마다 읽는다. setup 에서 한 번 읽어 굳혀 두면 나중에
  -- :let 으로 켤 수 없고, 이 설정의 다른 옵션들과도 어긋난다.
  open_automatic = function(bufnr)
    if (tonumber(vim.g.vimide_outline_auto) or 0) == 0 then
      return false
    end
    -- neo-tree 검사는 예전 방식에서만 뜻이 있다.
    --
    -- 그때는 aerial 이 '지금 창'을 쪼개며 왼쪽 트리를 밀어냈다. global+edge
    -- 는 topleft 로 서기 때문에 밀어내지 않고 그냥 나란히 선다.
    --
    -- 게다가 이 검사는 이제 늘 참이 된다 - RelationView 의 오른쪽 열에도
    -- neo-tree 가 하나 있어서, 'neo-tree 가 있으면 열지 않는다' 가
    -- 'g:vimide_outline_auto = 1 이어도 영영 안 연다' 가 돼 버렸다.
    -- 그래서 예전 방식일 때만 본다.
    if (tonumber(vim.g.vimide_outline_global) or 1) == 0 then
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.bo[b].filetype == 'neo-tree' then
          return false
        end
      end
    end
    local ok, util = pcall(require, 'aerial.util')
    return not (ok and util.is_ignored_buf(bufnr))
  end,
  -- 아웃라인에서 커서를 옮기면 편집 창이 그 심볼로 간다. 포커스는
  -- 아웃라인에 남는다 - tagbar 쪽에 손으로 만들어 둔 follow 동작과 같다
  -- (s:TagbarFollowCursor, 아래 Tagbar 절).
  --   autojump = false 로 끄면 <CR> 로만 이동한다.
  autojump = true,
  --   'global' 아웃라인 창 하나가 '지금 포커스된 창'을 따라간다.
  --   'window' 창마다 제 아웃라인을 갖는다 (예전 방식).
  attach_mode = outline_global and 'global' or 'window',
  close_on_select = false,
  show_guides = true,
  -- h / l 은 커서를 움직이는 키다.
  --
  -- aerial 은 그 둘에 트리 접기/펴기를 달아 둔다. 그래서 아웃라인 안에서는
  -- 위아래로는 움직이는데 좌우로는 못 움직였다 - h 를 누르면 커서가 왼쪽으로
  -- 가는 대신 그 항목이 접혔다.
  --
  -- 잃는 것은 없다: 접기/펴기는 o(토글), za/zo/zc 가 그대로 한다. 재귀
  -- 버전도 O 와 zA/zO/zC 에 남아 있다. H 와 L 은 건드리지 않았다 - vim 에서
  -- 그건 좌우가 아니라 화면 맨 위/맨 아래다. 그것까지 돌려받고 싶으면
  -- 아래에 ['H'] = false, ['L'] = false 를 더하면 된다.
  --
  -- false 를 주면 aerial 이 그 키에 맵을 아예 만들지 않는다
  -- (keymap_util.lua 의 'if rhs then'). keymaps 는 깊게 병합되므로 나머지
  -- 기본 키는 그대로다.
  keymaps = {
    ['h'] = false,
    ['l'] = false,
  },
})
EOF
nnoremap <silent> <Leader>o <Cmd>AerialToggle<CR>

" aerial 창만 옅은 회색 바탕으로 (SI 의 Symbol Window 처럼).
"
" 창 단위 배경은 Normal 을 그 창에서만 바꿔치기하는 방식이다 - overview.lua
" 가 이미 같은 방법을 쓴다. 색은 colorscheme 의 AerialBg(팔레트 'aerialbg').
"
"   let g:vimide_aerial_bg = 0   " 끄면 본문과 같은 흰 바탕
if !exists('g:vimide_aerial_bg')
    let g:vimide_aerial_bg = 1
endif
augroup VimIdeAerialBg
    autocmd!
    autocmd FileType aerial
        \ if get(g:, 'vimide_aerial_bg', 1)
        \ |   setlocal winhighlight=Normal:AerialBg,NormalNC:AerialBgNC,EndOfBuffer:AerialBg
        \ | endif
augroup END
" 아웃라인에서 더블클릭(또는 v)하면 편집 창에서 그 함수를 주석까지 블록으로
" 잡는다 - ~/.vim/plugin/aerialrange.lua

" 프로젝트 전역 심볼 검색(소스인사이트의 Ctrl+O)은 <leader>fs 와 <F7> =
" :ProjectSymbols 가 담당한다(gtags 색인 기반, 아래 Project files 절).
" ctags(tags 파일) 쪽 목록을 보고 싶으면 ':Telescope tags',
" LSP(clangd) 를 켰다면 ':Telescope lsp_workspace_symbols' 도 쓸 수 있다.

" ------------------------------------
" neo-tree: 사이드바 파일 트리 (NERDTree 상위 호환)
"   F9 또는 <leader>t 로 토글. a 생성 / d 삭제 / r 이름변경 / ? 도움말
"   (F11 은 그대로 NERDTree 오른쪽 창)
"   netrw 는 nvim-tree 가 이미 가로채므로 neo-tree 는 건드리지 않는다.
"   대용량 트리에서 발열/지연이 없도록 git status 는 비동기, 파일
"   watcher 는 끈다.
"
" git 표시(색깔 마크)의 비용 - 실측 (56,220 파일 커널 repo, 공유 서버):
"   git status --porcelain --ignored=traditional --untracked-files=no   10.2초
"   git status --porcelain --ignored=no --untracked-files=no             6.4초
"   git status ... -- drivers/spi        (경로 한정)                     109ms
"   git ls-files --others --ignored      (무시 목록)                      56ms
" 즉 무거운 것은 '전체 worktree 를 훑는 git status' 하나뿐이고, 그건 어떤
" 플래그를 줘도 6초 아래로 내려가지 않는다. 두 가지로 나눠서 막는다.
"
"   1) git_status_scope_to_path - 하위 디렉터리를 보고 있을 때는 그 경로만
"      묻는다. 6.4초 -> 109ms. 마크는 그대로 나온다.
"   2) 트리 루트에서는 경로 한정이 곧 전체라 싸게 만들 방법이 없다. 그래서
"      repo 가 크면(.git/index 크기 기준) git 표시를 아예 끈다. 마크만
"      사라지고 트리는 그대로다.
"
"   let g:vimide_neotree_git = 1        " 크기 무시하고 항상 켜기
"   let g:vimide_neotree_git = 0        " 항상 끄기
"   let g:vimide_neotree_git_max_mb = 2 " 이 크기를 넘으면 자동으로 끈다
" ------------------------------------

" Nerd Font 글자를 못 그리는 터미널에서는 ASCII 로 바꾼다.
"
" neo-tree 아이콘과 색인 표시가 iTerm2 에서는 멀쩡한데 Tera Term 에서는
" 아이콘이 아예 안 보이고 표시가 펑퍼짐했다. 두 가지가 겹쳤다:
"   * 아이콘은 Nerd Font 의 사용자 영역 글자다. 그 글꼴이 없는 터미널은
"     그릴 것이 없어 빈칸이 된다.
"   * 색인 표시로 쓰던 '●'(U+25CF)는 East Asian Ambiguous Width 글자다.
"     nvim 은 한 칸으로 세는데(ambiwidth=single) CJK 글꼴을 쓰는 터미널은
"     두 칸으로 그린다. 그 어긋남이 '펑퍼짐'으로 보인다.
"
" 구별은 TERM 으로 한다. 실측: 사용자의 서버 세션 6개가 모두
" TERM=xterm-color 였다 - Tera Term 이 자기를 그렇게 알린다(iTerm2 는
" xterm-256color). 어림짐작이므로 언제든 직접 정할 수 있다.
"   let g:vimide_ascii_icons = 1   " 늘 ASCII 로
"   let g:vimide_ascii_icons = 0   " 늘 Nerd Font 로
if !exists('g:vimide_ascii_icons')
    let g:vimide_ascii_icons = ($TERM ==# 'xterm-color')
endif
if g:vimide_ascii_icons
    " '*' 와 '.' 은 어느 터미널에서나 한 칸이다
    let g:projectfiles_tree_mark_file = '*'
    let g:projectfiles_tree_mark_dir  = '.'
    " 창 구분선 기본값도 U+2502 다. '|' 는 어느 터미널에서나 한 칸
    let &fillchars = 'vert:|,fold:-,eob:~'
endif

" git 표시를 켠다.
"
" 껐던 이유는 '전체 git status 가 수 초씩 걸린다'였는데, 다시 재 보니
" 그렇지 않았다 (kernel/common, .git/index 8.4MB):
"   git status --porcelain        0.15초
"   untracked 만 (ls-files -o)    0.12초
" 위 1)의 git_status_scope_to_path 가 이미 켜져 있어 보고 있는 경로만
" 묻는 것도 그대로다. 크기로 자동으로 끄는 판정(.git/index > 2MB)은 이
" repo 를 끄게 되므로, 여기서 명시적으로 켠다.
"
" 켜면 git 이 모르는 파일 이름이 주황(#ff8700)으로 뜬다 - NeoTreeGitUntracked.
" 껐을 때는 트리가 애초에 그 사실을 모르므로 아무 색도 나오지 않는다.
"   let g:vimide_neotree_git = 0   " 다시 끄기 (주황도 같이 사라진다)
let g:vimide_neotree_git = 1

" 그 주황에서 이탤릭만 뺀다.
"
" neo-tree 의 기본값은 주황 + 이탤릭인데, 이탤릭 글꼴이 없는 터미널은
" 이탤릭을 '반전'으로 그린다. Tera Term 에서 보라색이 음영으로 보였던 것과
" 같은 문제다(그때도 같은 이유로 껐다). 색은 그대로 두고 기울임만 뺀다.
"   let g:vimide_neotree_italic = 1   " 이탤릭도 그대로 두기
function! s:NeoTreeGitColors() abort
    if get(g:, 'vimide_neotree_italic', 0)
        return
    endif
    for l:g in ['NeoTreeGitUntracked', 'NeoTreeGitConflict']
        if hlexists(l:g)
            execute 'highlight' l:g 'cterm=NONE gui=NONE'
        endif
    endfor
endfunction
augroup VimIdeNeoTreeGitColors
    autocmd!
    autocmd ColorScheme,VimEnter * call <SID>NeoTreeGitColors()
    autocmd FileType neo-tree call <SID>NeoTreeGitColors()
augroup END

lua << EOF
-- Nerd Font 글자를 못 그리는 터미널이면 ASCII 로. provider 를 아무 일도
-- 하지 않는 함수로 두면 nvim-web-devicons 를 타지 않고 default 로 떨어진다
-- (neo-tree 의 icon 컴포넌트는 provider 의 반환값이 nil 이면 그대로 둔다).
local ascii_icons = (tonumber(vim.g.vimide_ascii_icons) or 0) ~= 0

_G.rv_setup('neo-tree', {
  default_component_configs = ascii_icons and {
    -- U+2502 세로줄은 East Asian Ambiguous 라 CJK 글꼴 터미널이 두 칸으로
    -- 그린다. 들여쓰기 안내선까지 ASCII 로 내려야 줄이 안 밀린다
    indent = {
      expander_collapsed = '+', expander_expanded = '-',
      indent_marker = '|', last_indent_marker = '+',
    },
    icon = {
      folder_closed = '+', folder_open = '-',
      folder_empty = ' ', folder_empty_open = ' ',
      selected = '>', default = ' ',
      provider = function() end,
    },
    modified = { symbol = '[+] ' },
    git_status = {
      symbols = {
        added = 'A', modified = 'M', deleted = 'D', renamed = 'R',
        untracked = '?', ignored = 'i', unstaged = 'u',
        staged = 's', conflict = 'C',
      },
    },
  } or nil,
  close_if_last_window = true,
  enable_git_status = true,
  enable_diagnostics = false,
  git_status_async = true,
  -- 하위 디렉터리를 볼 때 worktree 전체가 아니라 그 경로만 묻는다
  git_status_scope_to_path = true,
  -- NERDTree 손버릇을 그대로 쓰게 얹는다.
  --
  -- 파일 조작은 neo-tree 것을 그대로 둔다(a 생성, A 디렉터리, d 삭제,
  -- r 이름변경, c 복사, m 이동, y/x/p 클립보드, u 실행취소). 그래서
  -- 비어 있는 키에만 NERDTree 쪽을 넣었다. 'o' 만 예외인데, neo-tree 에서
  -- 그건 도움말이고 도움말은 '?' 로도 열리기 때문에 잃는 것이 없다.
  --
  --   o  열기            O  이 아래를 전부 펼치기
  --   X  이 아래를 접기   I  숨김 파일 토글 (neo-tree 의 H 도 그대로)
  --   K  형제 중 처음     J  형제 중 마지막
  --
  -- NERDTree 의 x(부모 접기) p(부모로) C(루트 변경) P(루트로) u(상위
  -- 디렉터리) 는 neo-tree 가 이미 다른 뜻으로 쓰고 있어 넣지 않았다.
  -- 대신 C 접기, . 루트 지정, <BS> 상위로 가 같은 일을 한다.
  window = {
    position = 'left',
    width = 32,
    mappings = {
      ['o'] = 'open',
      ['O'] = 'expand_all_subnodes',
      ['X'] = 'close_all_subnodes',
      ['I'] = 'toggle_hidden',
      ['K'] = function(state) _G.neotree_sibling(state, 'first') end,
      ['J'] = function(state) _G.neotree_sibling(state, 'last') end,
      -- 'w' 로 트리 폭을 넓혔다 줄인다 (RelationView 패널의 'w' 와 같다).
      -- 단계는 g:neotree_wide_steps, 하는 일은 neotree_nerd.lua 에 있다.
      -- neo-tree 기본의 open_with_window_picker 자리를 넘겨받는다.
      ['w'] = function() _G.neotree_toggle_wide() end,
    },
  },
  -- 파일을 열 때 이 창들은 고르지 않는다.
  --
  -- RelationView 의 context 창이 문제였다: buftype 은 nofile 인데
  -- filetype 은 미리보기 중인 파일의 것(c, h ...)이라 neo-tree 에게는
  -- 평범한 편집 창으로 보인다. 그런데 그 창에는 winfixbuf 가 걸려 있어서
  -- 거기로 파일을 열려다 이 에러가 났다:
  --   E1513: Cannot switch buffer. 'winfixbuf' is enabled
  -- (neo-tree 에 winfixbuf 복구 경로가 있긴 한데, 그 앞의
  --  assert(pcall(...)) 이 먼저 던져서 도달하지 못한다.)
  --
  -- buftype 도 함께 검사하므로 'nofile' 하나로 패널과 미리보기가 모두
  -- 빠진다 - 스크래치 창에 파일을 여는 일 자체가 없어야 맞다. 기본값
  -- 목록은 이 키를 주면 대체되므로 함께 적는다.
  open_files_do_not_replace_types = {
    'terminal', 'Trouble', 'qf', 'edgy',
    'nofile', 'relationview', 'aerial', 'tagbar', 'overview',
  },
  filesystem = {
    -- 색인 표시([O]/[.])를 이름 앞에 끼워 넣는다. 계산과 그리기는
    -- ~/.vim/plugin/projectfiles_neotree.lua 가 한다.
    --
    -- 전역 components/renderers 에 두면 안 된다: neo-tree 의
    -- merge_renderers(setup/init.lua)가 전역 렌더러를 소스로 옮길 때
    -- '그 소스의 components 에 있는 이름'만 남기고 나머지를 버린다.
    -- 그래서 소스(filesystem) 안에 함께 둔다.
    --
    -- 기본 렌더러 목록은 통째로 베끼지 않고 defaults 에서 가져와 끼운다
    -- (플러그인이 올라가도 따라간다).
    components = {
      projectfiles_index = function(config, node, state)
        if type(_G.projectfiles_neotree_mark) == 'function' then
          return _G.projectfiles_neotree_mark(config, node, state)
        end
        return { text = '' }
      end,
    },
    renderers = (function()
      local ok, nd = pcall(require, 'neo-tree.defaults')
      if not ok or not nd.renderers then
        return nil
      end
      local function with_mark(list)
        local out = vim.deepcopy(list)
        table.insert(out, 3, { 'projectfiles_index' }) -- indent, icon 다음
        return out
      end
      return {
        file = with_mark(nd.renderers.file),
        directory = with_mark(nd.renderers.directory),
      }
    end)(),
    -- '/' 는 NERDTree 처럼 vim 의 검색이다.
    --
    -- neo-tree 는 '/' 에 fuzzy finder 를 달아 둔다. 이름 조각을 치면 목록이
    -- 줄어드는 방식이라 편할 때도 있지만, 손이 기억하는 '/' 는 그냥 검색이다
    -- - 치고, n 으로 다음, N 으로 이전. 'none' 으로 두면 neo-tree 가 그 키에
    -- 버퍼 맵을 아예 걸지 않아서(ui/renderer.lua 의 skip_this_mapping) vim 의
    -- '/' 가 그대로 살아난다. 'noop' 은 안 된다 - 그건 '아무 일도 안 하는
    -- 맵'이라 오히려 '/' 를 먹는다.
    --
    -- fuzzy finder 를 잃지는 않는다: 비어 있던 F 로 옮겼다.
    --   /  검색 (n / N 으로 다음 / 이전)   F  fuzzy finder
    --   D  디렉터리 fuzzy finder           f  이름으로 거르기 (그대로)
    -- F 로 찾은 목록은 화면에 남는다 (keep_filter_on_submit).
    --
    -- 기본값은 반대다: 팝업에서 <CR> 을 누르면 고른 파일을 열면서 목록을
    -- 곧바로 지운다. 그러면 찾은 것들을 '가지고 할 수 있는 일'이 없다 -
    -- 마우스로 다른 줄을 누르는 순간 팝업이 닫히며 목록도 같이 사라졌고,
    -- 여러 개를 골라 색인에 넣는 것은 아예 불가능했다.
    --
    -- 목록을 남기면 그 뒤는 평소의 트리와 똑같다:
    --   <CR> / 더블클릭  EDIT 창에 연다
    --   V 로 영역 잡고 + / -   그 파일들을 색인 목록에 넣고 뺀다
    --   <C-x>            목록을 풀고 원래 트리로
    window = {
      mappings = {
        ['/'] = 'none',
        ['F'] = { 'fuzzy_finder', config = { keep_filter_on_submit = true } },
      },
    },
    hijack_netrw_behavior = 'disabled',
    use_libuv_file_watcher = false,
    follow_current_file = { enabled = true },
    -- H 로 숨김 파일을 켜고 끈다.
    --
    -- H(toggle_hidden)는 filtered_items.visible 만 뒤집는데, 그 값은
    -- '걸러진 항목을 흐리게라도 보여줄까'라는 뜻이다. hide_dotfiles 가
    -- false 면 애초에 걸러지는 것이 없어서 H 를 눌러도 화면이 그대로다 -
    -- 토글이 안 듣는 것처럼 보였던 이유다.
    --
    -- 그래서 거르기는 켜 두고(hide_dotfiles), 기본은 보이게 둔다
    -- (visible = true, 흐리게 표시). 그러면 H 가 '흐리게 보임 <-> 숨김'
    -- 을 오간다. .tags 나 .git 처럼 이 설정에서 자주 보는 것들이 기본
    -- 화면에서 사라지지 않는다.
    --
    -- gitignore 쪽은 건드리지 않는다(hide_gitignored = false): 빌드
    -- 산출물이 많은 트리에서 그것까지 걸면 화면이 크게 달라진다.
    filtered_items = {
      visible = true,
      hide_dotfiles = true,
      hide_gitignored = false,
    },
  },
  -- document_symbols 도 '/' 를 거르기로 쓴다. 같은 이유로 되돌린다.
  document_symbols = {
    window = {
      mappings = {
        ['/'] = 'none',
        ['F'] = 'filter',
      },
    },
  },
})

-- 큰 repo 에서 neo-tree 의 git 표시를 끈다.
--
-- neo-tree 는 스캔할 때마다 worktree 전체에 git status 를 돌린다. 파일이
-- 수만 개면 그게 6~10초짜리 프로세스라, find/검색으로 스캔이 반복될 때마다
-- CPU 를 하나씩 물고 늘어진다. repo 크기는 .git/index 크기로 즉시 알 수
-- 있으므로(stat 한 번), 크면 표시를 끄고 그 사실을 한 번 알려 준다.
do
  local uv = vim.uv or vim.loop
  local seen = {}       -- git dir -> 이미 알린 repo
  local decided = {}    -- git dir -> true/false

  -- '.git' 은 디렉터리이거나 'gitdir: <경로>' 한 줄이 든 파일이다
  -- (worktree, submodule). 어느 쪽이든 index 파일을 찾아 준다.
  local function index_path(dir)
    local d = dir
    for _ = 1, 40 do
      local dot = d .. '/.git'
      local st = uv.fs_stat(dot)
      if st then
        if st.type == 'directory' then
          return dot .. '/index'
        end
        local line = (vim.fn.readfile(dot, '', 1)[1] or '')
        local real = line:match('^gitdir:%s*(.+)$')
        if real then
          if real:sub(1, 1) ~= '/' then
            real = d .. '/' .. real
          end
          return (real:gsub('/+$', '')) .. '/index'
        end
        return nil
      end
      local up = vim.fs.dirname(d)
      if not up or up == d then
        break
      end
      d = up
    end
    return nil
  end

  -- true 면 git 표시를 켜도 된다
  local function affordable(dir)
    local forced = vim.g.vimide_neotree_git
    if forced ~= nil and forced ~= '' then
      return tonumber(forced) ~= 0
    end
    local idx = index_path(dir or vim.fn.getcwd())
    if not idx then
      return true -- git repo 가 아니면 status 도 안 돌아간다
    end
    if decided[idx] ~= nil then
      return decided[idx]
    end
    local st = uv.fs_stat(idx)
    local max = (tonumber(vim.g.vimide_neotree_git_max_mb) or 2) * 1024 * 1024
    local ok = not (st and st.size > max)
    decided[idx] = ok
    if not ok and not seen[idx] then
      seen[idx] = true
      vim.schedule(function()
        vim.notify(('neo-tree: git 표시를 끕니다 - 이 repo 는 큽니다 '
          .. '(.git/index %.1f MB). 전체 git status 가 수 초씩 걸려 '
          .. '검색할 때마다 CPU 를 물기 때문입니다. '
          .. 'let g:vimide_neotree_git = 1 로 강제할 수 있습니다.')
          :format((st and st.size or 0) / 1048576))
      end)
    end
    return ok
  end

  local function apply(dir)
    local okmod, nt = pcall(require, 'neo-tree')
    if not okmod or not nt.ensure_config then
      return
    end
    local okc, conf = pcall(nt.ensure_config)
    if okc and type(conf) == 'table' then
      conf.enable_git_status = affordable(dir)
    end
  end
  _G.vimide_neotree_git_apply = apply

  vim.api.nvim_create_autocmd({ 'VimEnter', 'DirChanged' }, {
    group = vim.api.nvim_create_augroup('VimIdeNeotreeGit', { clear = true }),
    callback = function() vim.schedule(function() pcall(apply, nil) end) end,
  })

  -- neo-tree 를 열기 직전에 한 번 더. 스캔이 시작되기 전에 결정되어야 한다.
  vim.api.nvim_create_user_command('NeotreeGuarded', function(o)
    pcall(apply, nil)
    vim.cmd('Neotree ' .. (o.args ~= '' and o.args or 'toggle'))
  end, { nargs = '*', desc = 'Neotree, with the git-status size guard applied' })

  -- 스캔 중에 처음 보는 worktree(중첩 repo 등)가 나타나면 그때도 판단한다.
  -- 이 훅은 status 명령이 나가기 직전에 불리므로, 여기서 끄면 다음 스캔부터
  -- 확실히 막힌다.
  local okev, events = pcall(require, 'neo-tree.events')
  if okev and events and events.subscribe then
    pcall(events.subscribe, {
      event = events.BEFORE_GIT_STATUS,
      handler = function(args)
        if args and args.git_root then
          pcall(apply, args.git_root)
        end
      end,
    })
  end
end
EOF
nnoremap <silent> <Leader>t <Cmd>NeotreeGuarded toggle<CR>

" ------------------------------------
" gutentags: ctags 자동 색인 (소스인사이트식 심볼 DB)
"   tags 가 없으면 백그라운드에서 한 번 만들고, 저장할 때마다 그 파일만
"   증분 갱신한다(전체 재색인이 아니라서 커널 트리에서도 가볍다).
"   수동 전체 재색인은 :GutentagsUpdate!
"   GTAGS 는 ~/.vim/plugin/autoindex.lua 가 같은 방식으로 관리한다
"   (:GtagsIndex / :GtagsIndexUpdate / :GtagsIndexStatus)
" ------------------------------------
let g:gutentags_modules = ['ctags']
let g:gutentags_define_advanced_commands = 1
let g:gutentags_project_root = ['.git', '.project', '.root']
let g:gutentags_add_default_project_roots = 0
let g:gutentags_cache_dir = expand('~/.cache/tags')
let g:gutentags_generate_on_new = 1
let g:gutentags_generate_on_missing = 1
let g:gutentags_generate_on_write = 1
let g:gutentags_generate_on_empty_buffer = 0
" gutentags 가 버퍼에 붙기 전에 autoindex.lua 에 물어본다. 저장 갱신이
" tags 파일을 통째로 다시 쓰기 때문에(plat/unix/update_tags.sh), 이미 커진
" 프로젝트는 붙기 전에 떼어내야 한다 - 붙은 뒤에 제외 목록에 넣어도 그
" 버퍼는 세션이 끝날 때까지 계속 다시 쓴다.
"   let g:autoindex_ctags_max_bytes = 0  " 크기로 막지 않기
"   let g:autoindex_gutentags_guard = 0  " 이 훅을 끄기
if has('nvim')
	function! VimIdeGutentagsOk(path) abort
		" luaeval 은 리스트를 1-기반으로 넘긴다 (_A[0] 은 nil 이다)
		return luaeval('_G.autoindex_gutentags_ok and
					\ _G.autoindex_gutentags_ok(_A[1]) or 1', [a:path])
	endfunction
	let g:gutentags_init_user_func = 'VimIdeGutentagsOk'
endif
" 색인할 파일은 indexfiles.sh 가 정한다(ctags 와 gtags 가 같은 목록을 쓴다):
"   .indexfiles -> cscope.files(F2) -> git ls-files -> find
" 커널처럼 큰 트리는 git 이 추적하는 소스만, 그 밖의 프로젝트는 .indexfiles
" 에 원하는 파일만 적어두면 딱 그만큼만 색인한다. 목록이 있으면 아래
" gutentags_ctags_exclude 는 쓰이지 않는다(목록 자체가 필터다).
if executable(expand('~/.local/bin/indexfiles.sh'))
	let g:gutentags_file_list_command = expand('~/.local/bin/indexfiles.sh')
endif
" '--extras=+q' 는 심볼마다 정규화 이름을 하나 더 넣어 tags 가 크게 부푼다
" (커널 트리에서 눈에 띄게 차이가 난다). 줄 번호와 시그니처만 담는다.
let g:gutentags_ctags_extra_args = ['--fields=+nS',
			\ '--c-kinds=+px', '--c++-kinds=+px']
let g:gutentags_ctags_exclude = ['.git', 'node_modules', 'build', 'out',
			\ 'Documentation', '*.json', '*.min.js', '*.o', '*.a',
			\ '*.so', '*.ko', '*.cmd', '.tags', 'GTAGS', 'GRTAGS', 'GPATH']

" ------------------------------------
" autoindex.lua: GTAGS 자동 색인
"   * vim 을 켜면 현재 프로젝트 색인을 백그라운드로 갱신한다
"     (있으면 증분 'gtags -i', 없으면 전체 빌드. 커널 69k 파일 기준
"      변경이 없으면 2초, 전체 빌드는 26초 정도)
"   * 파일을 저장하면 그 파일만 즉시 갱신한다
"   * C-] / :tag / g] 는 'tagfunc' 로 GTAGS 가 답한다(커널에서 8ms).
"     tags 파일이 없어도, 방금 저장한 심볼도 바로 점프된다. gtags 가
"     모르면 평소처럼 tags 파일을 찾는다(LSP 가 붙은 버퍼는 LSP 우선).
"   * gutentags 가 감당 못하는 큰 트리(g:autoindex_ctags_max_files 초과)는
"     여기서 ctags 파일을 만든다 - 커널 0.9GB / 47초, 저장할 때는 만들지
"     않는다(gutentags 는 저장마다 tags 전체를 재작성한다).
"     :CtagsIndex 로 다시 만들고, g:autoindex_ctags = 0 으로 끈다.
"   * GTAGS/GRTAGS/GPATH 는 프로젝트 루트의 숨김 디렉터리 '.tags/' 에 만든다
"     (예전처럼 루트에 있던 DB 는 처음 열 때 .tags/ 로 옮긴다).
"     찾는 방법은 $GTAGSOBJDIR 한 줄 - 아래 Telescope 블록 위를 보라.
"     터미널에서 global 을 쓸 때는:  eval "$(gtagsenv.sh)"
"   :GtagsIndex(전체) :GtagsIndexRefresh(증분) :GtagsIndexUpdate(현재 파일)
"   :GtagsIndexStatus(상태)
" 바꾸고 싶으면:
"   let g:autoindex_dbdir = '.tags'   " '' 로 두면 예전처럼 루트에 만든다
"   let g:autoindex_startup = 0       " 시작 시 자동 색인 끄기
"   let g:autoindex_startup_ctags = 0 " 시작 시 ctags 갱신만 끄기
"   let g:autoindex_notify = 0        " 알림 끄기
" ------------------------------------

" 색인은 가장 바깥 프로젝트 하나만 본다.
"
" 'chain'(기본)은 현재 디렉터리 프로젝트부터 위로 올라가며 차례로 묻는다.
" 이 트리는 바깥 루트와 kernel/common 이 preset 하나를 나눠 쓰므로, 바깥만
" 보는 편이 답이 한 곳에서만 나와 헷갈리지 않는다.
"   let g:sihl_index_db = 'chain'   " 기본: 현재 디렉터리부터 위로
"   let g:sihl_index_db = 'near'    " 가장 가까운 것 하나만
let g:sihl_index_db = 'root'

" Find files using Telescope command-line sugar.
nnoremap <leader>fi <cmd>Telescope git_commits<cr>
nnoremap <leader>ff <cmd>Telescope find_files<cr>
nnoremap <leader>fg <cmd>Telescope live_grep<cr>
nnoremap <leader>fb <cmd>Telescope buffers<cr>
nnoremap <leader>fh <cmd>Telescope help_tags<cr>

" Add your own custom formats or override the defaults
let g:NERDCustomDelimiters = { 
			\ 'dts': { 'left': '/*', 'right': '*/', 'leftAlt': '//' },
			\ 'dtsi': { 'left': '/*', 'right': '*/', 'leftAlt': '//' },
			\}

" nerdtree-git-plugin: CursorHold 마다 git status 를 재실행하지 않게 한다.
" updatetime=100(0.1초) + 커널 트리 git status 23초 = 프로세스가 무한히 쌓여
" 100개 이상 / 50GB / CPU 800% 까지 폭주했다(2026-09-03 실측). 저장 시에만 갱신하고
" 수동 갱신이 필요하면 NERDTree 에서 R 을 누른다.
let g:NERDTreeGitStatusUpdateOnCursorHold = 0

let g:NERDTreeGitStatusIndicatorMapCustom = {
    \ 'Modified'  : 'M',
    \ 'Staged'    : 'S',
    \ 'Untracked' : '?',
    \ 'Renamed'   : 'R',
    \ 'Unmerged'  : 'U',
    \ 'Deleted'   : 'D',
    \ 'Dirty'     : '*',
    \ 'Clean'     : 'C',
    \ 'Unknown'   : '?'
    \ }

" ------------------------------------
" vista
" ------------------------------------
"let g:vista_ctags_executable = 'ctags'
"let g:vista_ctags_ctagsargs = '-R --exclude=.git --fields=+lS --kinds-cpp=+p --kinds-c=+p --kinds-python=+i'
"let g:vista_default_executive = 'nvim_lsp'

" ------------------------------------
" settings for nvim
" ------------------------------------
"set encoding=utf-8
"set fileencoding=utf-8
"set guifont=3270NerdFontMono-Regular:h12

else

set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'
Plugin 'tpope/vim-fugitive'
Plugin 'tpope/vim-unimpaired'
Plugin 'preservim/nerdcommenter'
Plugin 'vim-airline/vim-airline'
Plugin 'vim-airline/vim-airline-themes'
Plugin 'inkarkat/vim-ingo-library'
Plugin 'inkarkat/vim-mark'
Plugin 'ervandew/supertab'
Plugin 'jlanzarotta/bufexplorer'
Plugin 'ivechan/gtags.vim'
Plugin 'ronakg/quickr-cscope.vim'
Plugin 'vim-scripts/grep.vim'
Plugin 'vim-scripts/AutoComplPop'
Plugin 'vim-scripts/The-NERD-tree'
Plugin 'vim-scripts/Tagbar'
Plugin 'vim-utils/vim-troll-stopper'
Plugin 'Raimondi/delimitMate'
Plugin 'mhinz/vim-signify'
Plugin 'terryma/vim-smooth-scroll'
"Plugin 'ctrlpvim/ctrlp.vim'
"Plugin 'SirVer/ultisnips'
"Plugin 'honza/vim-snippets'
"Plugin 'airblade/vim-gitgutter'
"Plugin 'altercation/vim-colors-solarized'
"Plugin 'ludovicchabant/vim-gutentags'
"Plugin 'skywind3000/gutentags_plus'
"Plugin 'terryma/vim-multiple-cursors'

call vundle#end()
endif

filetype plugin indent on     " required!

" :PluginList          - list configured bundles
" :PluginInstall(!)    - install(update) bundles
" :PluginSearch(!) foo - search(or refresh cache first) for foo
" :PluginClean(!)      - confirm(or auto-approve) removal of unused bundles
"
" see :h vundle for more details or wiki for FAQ
" NOTE: comments after Plugin command are not allowed..
"

" Ease my eyes
"colorscheme solarized

" Set airline
"set term=xterm-256color
set t_Co=256
let g:airline_powerline_fonts = 1
" 이게 없으면 airline 이 버퍼/창을 옮길 때마다(BufEnter) 하이라이트 그룹을
" 통째로 다시 계산한다. 실측 서버 4.5ms -> 2.7ms, 시작 시 45ms.
let g:airline_highlighting_cache = 1
let g:airline_theme='hybrid'
"let g:airline_theme='badwolf'
"let g:airline_theme='wombat'
"let g:airline_theme='dark'
"let g:airline_solarized_bg='dark'
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'unique_tail'
let g:airline#extensions#tagbar#enabled = 1
if !exists('g:airline_symbols')
    let g:airline_symbols = {}
endif
let g:airline_symbols.branch = ''
let g:airline_symbols.linenr = ''
let g:airline_symbols.maxlinenr = ''
let g:airline_section_error  = ''
let g:airline_section_warning = ''
let g:airline_symbols.notexists = ''
autocmd BufDelete * call airline#extensions#tabline#buflist#invalidate()

" Nerd Font 가 없는 터미널(Tera Term)에서는 airline 의 powerline 글자를 끈다.
" 위쪽 g:vimide_ascii_icons 판정을 그대로 쓴다. 앞의 설정은 건드리지 않고
" 여기서 되돌리기만 하므로, iTerm2 쪽 모양은 지금 그대로다.
"
" airline 은 g:airline_powerline_fonts 를 VimEnter 의 bootstrap 에서 읽으므로
" 플러그인이 이미 로드된 뒤인 여기서 바꿔도 늦지 않다.
if g:vimide_ascii_icons
    let g:airline_powerline_fonts = 0
    " 삼각형 구분자()를 없앤다. 빈 문자열이면 airline 이 아무것도 안 그린다
    let g:airline_left_sep  = ''
    let g:airline_right_sep = ''
    let g:airline_left_alt_sep  = '|'
    let g:airline_right_alt_sep = '|'
    let g:airline#extensions#tabline#left_sep      = ''
    let g:airline#extensions#tabline#right_sep     = ''
    let g:airline#extensions#tabline#left_alt_sep  = '|'
    let g:airline#extensions#tabline#right_alt_sep = '|'
    " 기본값은 branch=U+2387, dirty=U+26A1 처럼 폭이 애매한 글자들이라
    " 전부 ASCII 로 못 박는다
    let g:airline_symbols.branch     = 'b'
    let g:airline_symbols.readonly   = 'RO'
    let g:airline_symbols.linenr     = 'L'
    let g:airline_symbols.maxlinenr  = ''
    let g:airline_symbols.colnr      = ':'
    let g:airline_symbols.dirty      = '*'
    let g:airline_symbols.notexists  = '?'
    let g:airline_symbols.modified   = '+'
    let g:airline_symbols.paste      = 'PASTE'
    let g:airline_symbols.spell      = 'SPELL'
    let g:airline_symbols.whitespace = '!'
    let g:airline_symbols.crypt      = 'cr'
    let g:airline_symbols.ellipsis   = '...'
endif

"==============================================================================
" Set Supertab
"==============================================================================
let g:SuperTabDefaultCompletionType = "<c-n>"

"==============================================================================
" vim-smooth-scroll
"==============================================================================
"noremap <silent> <c-b> :call smooth_scroll#up(&scroll*2, 10, 9)<CR>
"noremap <silent> <c-f> :call smooth_scroll#down(&scroll*2, 10, 9)<CR>
"noremap <silent> <c-u> :call smooth_scroll#up(&scroll, 10, 5)<CR>
"noremap <silent> <c-d> :call smooth_scroll#down(&scroll, 10, 5)<CR>


"==============================================================================
" vim-multiple-cursor
"==============================================================================
"let g:multi_cursor_use_default_mapping=0

" Default mapping
"let g:multi_cursor_start_word_key      = '<A-j>'
"let g:multi_cursor_select_all_word_key = '<A-j>'
"let g:multi_cursor_start_key           = 'g<C-j>'
"let g:multi_cursor_select_all_key      = 'g<A-j>'
"let g:multi_cursor_next_key            = '<Tab>'
"let g:multi_cursor_prev_key            = '<S-Tab>'
"let g:multi_cursor_skip_key            = '<C-x>'
"let g:multi_cursor_quit_key            = '<Esc>'

"==============================================================================
" delimitMate
"==============================================================================
let delimitMate_expand_cr=1


"==============================================================================
" UltiSnips
"==============================================================================
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-tab>"
let g:UltiSnipsJumpBackwardTrigger="<s-tab>"
let g:UltiSnipsEditSplit="vertical"
let g:UltiSnipsSnippetDirectories=[$HOME.'/.vim/bundle/ultisnips']
"let g:python_host_prog="~/.local/bin/python3.7"
"let g:python3_host_prog="/home/B130111/.pyenv/shims/python3"


"==============================================================================
" cscope key map
"==============================================================================
"s : find this symbol, ctags와 마찬가지로 C심볼을 찾습니다. (변수, 함수, 매크로, 구조체 등)
"g : find this definition, 전역 선언만 검색합니다.
"d : find functions called by this function, 한 함수에 의해 호출되는 또다른 함수들을 찾습니다.
"c : find functions calling this function, 한 함수를 호출하는 모든 함수를 찾습니다.
"t : find assignments to, 텍스트 문자열을 검색
"e : find this egrep pattern, 정규식을 이용하여 소스코드 검색.
"f : find this file, 특정 이름을 포함한 파일을 모두 검색합니다.
"i : find this #including this file, 특정 헤더파일을 포함시키는 모든 소스코드 찾기.

"nmap <Leader><Leader>s :cs find s <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>g :cs find g <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>d :cs find d <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>c :cs find c <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>t :cs find t <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>e :cs find e <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>f :cs find f <C-R>=expand("<cfile>") <CR><CR>
"nmap <Leader><Leader>i :cs find i <C-R>=expand("<cfile>") <CR><CR>

"==============================================================================
" quickr-cscope.vim key map
"==============================================================================
"s : find this symbol, ctags와 마찬가지로 C심볼을 찾습니다. (변수, 함수, 매크로, 구조체 등)
"g : find this definition, 전역 선언만 검색합니다.
"d : find functions called by this function, 한 함수에 의해 호출되는 또다른 함수들을 찾습니다.
"c : find functions calling this function, 한 함수를 호출하는 모든 함수를 찾습니다.
"t : find assignments to, 텍스트 문자열을 검색
"e : find this egrep pattern, 정규식을 이용하여 소스코드 검색.
"f : find this file, 특정 이름을 포함한 파일을 모두 검색합니다.
"i : find this #including this file, 특정 헤더파일을 포함시키는 모든 소스코드 찾기.

let g:quickr_cscope_program = "gtags-cscope"
" 색인은 프로젝트 루트의 숨김 디렉터리에 있다(autoindex.lua 참고). 이 플러그인은
" findfile() 로 DB 파일을 직접 찾으므로 숨김 경로를 알려줘야 하고, 못 찾으면
" 조용히 죽는다(플러그인이 finish 해서 <plug> 매핑조차 만들어지지 않는다).
" 그래서 숨김 DB 가 있으면 그쪽을, 없으면 예전처럼 루트의 GTAGS 를 쓴다.
let s:rv_dbdir = get(g:, 'autoindex_dbdir', '.tags')
if !empty(s:rv_dbdir) && !empty(findfile(s:rv_dbdir . '/GTAGS', '.;'))
	let g:quickr_cscope_db_file = s:rv_dbdir . '/GTAGS'
else
	let g:quickr_cscope_db_file = 'GTAGS'
endif
let g:quickr_cscope_keymaps = 0
let g:quickr_cscope_autoload_db = 1
let g:quickr_cscope_use_qf_g = 1

nmap <Leader><Leader>g <plug>(quickr_cscope_global)
nmap <Leader><Leader>s <plug>(quickr_cscope_symbols)
"nmap <Leader><Leader>c <plug>(quickr_cscope_callers)
" \\c : 커서 밑 심볼을 부르는 곳(call reference)을 찾는다. 찾은 것을
" 목록에서 훑는 동안 본문에도 남게 F4 와 같은 색을 함께 입힌다 -
" :LookupReferences 와 같은 자리(_G.vimide_mark_text)를 쓴다.
function! s:MarkAndCallRefs() abort
    let l:w = expand('<cword>')
    if empty(l:w)
        return
    endif
    if has('nvim') && exists('*luaeval')
        silent! call luaeval('_G.vimide_mark_text ~= nil and _G.vimide_mark_text(_A) or 0', l:w)
    endif
    " caller 목록은 릴레이션 패널이 떠 있으면 패널에, 아니면 quickfix 로.
    "
    " :Gtags 는 relationview.lua 가 덮어써 두었다 - 패널이 떠 있으면 결과를
    " 패널에 싣고, 닫혀 있으면 gtags.vim 본래대로 quickfix 를 쓴다. 그러니
    " 여기서는 그냥 :Gtags 를 부르면 된다.
    "
    " 한동안 :GtagsQf 로 늘 quickfix 에 보냈다. 요청대로 패널 쪽으로
    " 되돌린다. :GtagsQf 명령 자체는 남겨 둔다 - 관계 트리를 지키면서
    " 찾고 싶을 때 직접 칠 수 있다.
    execute 'Gtags -r ' . l:w
endfunction
nnoremap <silent> <Leader><Leader>c :call <SID>MarkAndCallRefs()<CR>
nmap <Leader><Leader>f <plug>(quickr_cscope_files)
nmap <Leader><Leader>i <plug>(quickr_cscope_includes)
nmap <Leader><Leader>d <plug>(quickr_cscope_functions)
nmap <Leader><Leader>e <plug>(quickr_cscope_egrep) <C-R>=expand("<cword>") <CR><CR>
nmap <Leader><Leader>a <plug>(quickr_cscope_assignments)

"==============================================================================
" gtags key map
"==============================================================================
let g:Gtags_OpenQuickfixWindow = 1
"let g:Gtags_VerticalWindow = 0
"let g:Gtags_Auto_Map = 0
"let g:Gtags_Auto_Update = 0
" C-n / C-p 는 '지금 앞에 있는 목록'의 다음/이전이다.
"
"   릴레이션 뷰가 켜져 있으면  -> 패널 목록을 훑는다
"                               (context view 에만 미리보기가 뜨고 EDIT 창은
"                                움직이지 않는다. 포커스도 그대로. 실제로 그
"                                자리로 가려면 Ctrl+Enter 또는 패널에서 Enter)
"   꺼져 있으면                -> quickfix 를 훑는다
"
" 판단 기준은 '패널이 떠 있는가'(s:RvPanelOn)다. 명령이 있는지로만 보면
" 뷰를 꺼 둔 상태에서도 패널 쪽으로 가려 해서 quickfix 가 안 움직인다.
" <C-n>/<C-p> 는 목록을 한 칸 옮기고, '그 자리를 보여주는 창' 으로 커서까지
" 간다(명령 뒤의 ! 이 그 뜻이다). 패널이 있으면 미리보기 창, 없으면 편집 창.
" quickfix 쪽은 vimide#qf#Step 이 이미 편집 창으로 옮겨 준다.
"
" 엿보기만 하고 싶으면 <C-0>/<C-9> 를 쓴다 - 그 둘은 커서를 그대로 둔다.
"   let g:relationview_step_focus = 0   " <C-n>/<C-p> 도 엿보기만
func! s:ListStep(dir) abort
	if s:RvPanelOn() && exists(':RelationViewNext') == 2
		exe a:dir > 0 ? 'RelationViewNext!' : 'RelationViewPrev!'
		return
	endif
	call vimide#qf#Step(a:dir)
endfunc
nnoremap <silent> <C-n> :call <SID>ListStep(1)<CR>
nnoremap <silent> <C-p> :call <SID>ListStep(-1)<CR>

" 릴레이션 패널 리스트 전용: Ctrl+0 (다음) / Ctrl+9 (이전)
"   context view 에만 미리보기가 뜨고 EDIT 창은 움직이지 않는다. 포커스도
"   그대로다. 실제로 그 위치로 가려면 Ctrl+Enter 또는 패널에서 Enter.
"   패널이 비어 있으면 quickfix 를 훑는다(RelationViewNext 의 대비책).
" 이 두 키는 전통적인 터미널 인코딩으로는 아예 전달되지 않는다. CSI-u
" (kitty keyboard protocol) 를 쓰는 터미널이어야 nvim 까지 도달한다
" - iTerm2 3.5+, kitty, WezTerm, Ghostty, foot 등.
func! s:QfStep(dir) abort
	if exists(':RelationViewNext') == 2
		exe a:dir > 0 ? 'RelationViewNext' : 'RelationViewPrev'
		return
	endif
	call vimide#qf#Step(a:dir)
endfunc
" 리스트에서 고른 항목으로 실제 이동: Ctrl+Enter (어느 창에서 눌러도 된다)
"   C-n/C-p 는 미리보기만 하므로, 이 키가 그 순회의 마침표다.
func! s:RvJump() abort
	if exists(':RelationViewJump') == 2
		RelationViewJump
	endif
endfunc
nnoremap <silent> <C-CR> :call <SID>RvJump()<CR>

" C-] : 편집 창에서는 정의를 context view 에 열고 포커스를 그쪽으로 옮긴다
"       (편집 창은 그대로. C-t 로 편집 창에 돌아온다. context view 안에서는
"        그 창의 자체 점프 스택으로 계속 파고들 수 있다)
"       패널/미리보기가 없으면 예전처럼 tagfunc(gtags) 로 편집 창에서 점프.
" 릴레이션 뷰가 떠 있을 때, 점프한 심볼에 F4(vim-mark) 색을 자동으로 입힌다.
"
" 패널이 닫혀 있으면 아무것도 하지 않는다 - '릴레이션 뷰 Off 면 기존 유지'.
" 이미 칠해진 심볼은 건드리지 않는다(vimide_mark_text 의 keep). vim-mark 의
" DoMark 는 토글이라 두 번 부르면 색이 꺼지기 때문이다.
"
"   let g:vimide_jump_mark = 0   " 점프할 때 색칠하지 않는다
" ------------------------------------
" 점프 키 관련 옵션
"
" 이 셋은 바로 아래에서 매핑을 걸 때 읽으므로 여기(그 줄보다 앞)에 둔다.
" 나머지 vim-ide 옵션은 아래쪽 RelationView 설정 절에 모여 있다.

" 점프할 때(Ctrl+] / g] / f]) 그 심볼에 F4 색을 자동으로 칠할지.
" Ctrl+t 로 돌아오면 그만큼만 풀린다.
let g:vimide_jump_mark = 1

" 단축키가 자동으로 칠하는 색을 통째로 켜고 끄는 한 스위치.
"
" 여기에 딸린 것:
"   <C-]> / g] / f] / <C-t>   점프한 심볼의 F4 색  (g:vimide_jump_mark)
"   \\c                        caller 찾기가 칠하는 색 (g:vimide_lookup_mark)
"   <C-/> / <C-_> / \fr / \fF  :LookupReferences 가 칠하는 색  (같은 옵션)
"   커서 밑 심볼 음영          refhighlight        (g:refhighlight)
"
" 손으로 칠하는 것은 이 스위치와 상관없이 늘 동작한다:
"   <F4> vim-mark,  <F8> 노란 표시(yellowmark)
"
" 끄면 '자동으로 칠한 색'만 벗겨진다 - 손으로 칠해 둔 색은 그대로 남는다.
"
"   \C                        켜고 끄기
"   :VimIdeAutoColor          켜고 끄기
"   :VimIdeAutoColor on|off   직접 정하기
"
" 기능별로 따로 끄고 싶으면 이것 말고 위 괄호 안의 옵션을 쓴다.
let g:vimide_auto_color = 1

func! s:AutoColor(arg) abort
    let l:a = substitute(a:arg, '^\s*\|\s*$', '', 'g')
    if l:a ==? 'on' || l:a ==# '1'
        let g:vimide_auto_color = 1
    elseif l:a ==? 'off' || l:a ==# '0'
        let g:vimide_auto_color = 0
    else
        let g:vimide_auto_color = get(g:, 'vimide_auto_color', 1) ? 0 : 1
    endif
    " 끌 때는 자동으로 칠해 둔 것을 벗긴다. 손으로 칠한 것은 남는다.
    " (nvim 전용 - 칠하는 쪽이 relationview.lua 라 vim 8.1 에는 없다)
    if !g:vimide_auto_color && has('nvim') && exists('*luaeval')
        silent! call luaeval('_G.vimide_auto_color_clear ~= nil and (function() _G.vimide_auto_color_clear() return 1 end)() or 0')
    endif
    echohl ModeMsg
    echo '단축키 자동 색칠: ' . (g:vimide_auto_color ? '켬' : '끔')
    echohl None
endfunc
command! -nargs=? VimIdeAutoColor call s:AutoColor(<q-args>)
" \c 는 NERDCommenter 가 쓰고 있어서 대문자 \C 를 쓴다.
nnoremap <silent> <Leader>C :VimIdeAutoColor<CR>

" f] 도 g] 와 같이 '지금 EDIT 창에서 그 심볼로' 가게 할지.
" 0 으로 두면 f] 는 vim 본래의 '이 줄에서 다음 ] 로' 가 된다.
let g:vimide_edit_jump_fkey = 1

" 패널 목록의 다음/이전 대체키.
"
" Ctrl+0 / Ctrl+9 는 전통적인 터미널 인코딩에 자리가 없어 CSI-u 를 쓰는
" 터미널(iTerm2 3.5+, kitty, WezTerm, Ghostty, foot)에서만 닿는다.
" 테라텀 등에서는 맨 '0' / '9' 가 들어가 엉뚱하게 움직이므로 대체키를 둔다.
" 빈 문자열로 두면 대체키를 만들지 않는다.
let g:vimide_rvlist_next_key = ']r'
let g:vimide_rvlist_prev_key = '[r'

func! s:RvPanelOn() abort
	if !has('nvim') || !exists('*luaeval')
		return 0
	endif
	return luaeval('(_G.relationview_panel_win ~= nil and _G.relationview_panel_win() ~= nil) and 1 or 0')
endfunc

" a:1 이 1 이면 패널이 꺼져 있어도 칠한다.
"
" <C-]> 가 그렇다 - 릴레이션 뷰가 꺼져 있을 때도 '뛰면 칠하고 <C-t> 로
" 풀린다'가 요청된 동작이다. g] 는 예전대로 패널이 떠 있을 때만 칠한다
" ('릴레이션 뷰 Off 면 기존 유지').
func! s:RvMarkCword(...) abort
	" 진짜 vim(8.1)에는 luaeval 이 없다.
	"
	" 예전에는 s:RvPanelOn() 이 has('nvim') 을 보고 0 을 돌려주는 덕에 여기서
	" 걸러졌는데, always=1 이 그 검사를 건너뛰게 되면서 vim 8.1 의 <C-]> 가
	" 아래 luaeval 에서 E117 로 죽었다. 적재만 확인하고 키를 안 눌러 봐서
	" 놓쳤다. 이제 맨 앞에서 막는다.
	if !has('nvim') || !exists('*luaeval')
		return
	endif
	let l:always = a:0 > 0 && a:1
	if !get(g:, 'vimide_jump_mark', 1) || (!l:always && !s:RvPanelOn())
		return
	endif
	" 곁창에서는 칠하지 않는다.
	"
	" 점프 자체가 아래 buftype 가드에서 막히는데 색칠만 먼저 일어나면,
	" quickfix 나 NERDTree 에서 <C-]> 를 눌렀을 때 아무 일도 안 일어난 채
	" 색만 남고 스택도 한 칸 늘어난다(그 칸은 풀 길이 없다).
	if &buftype !=# '' && &buftype !=# 'help'
		return
	endif
	let l:w = expand('<cword>')
	if l:w !~# '^[A-Za-z_][A-Za-z0-9_]*$'
		return
	endif
	" 스택에 쌓아 둔다 - <C-t> 로 돌아올 때 그만큼만 되돌린다.
	call luaeval('_G.vimide_jump_mark_push ~= nil and (function() _G.vimide_jump_mark_push(_A) return 1 end)() or 0', l:w)
	return 1
endfunc

" 칠했는데 결국 안 뛴 경우, 방금 쌓은 것을 도로 푼다.
"
" 색칠이 점프보다 먼저라(커서가 움직이기 전의 <cword> 가 필요하다),
" #include 를 따라가거나 태그를 못 찾으면 심볼만 칠해진 채 남는다.
" 그 칸은 <C-t> 로 풀 수도 없다 - 되돌릴 점프가 없기 때문이다.
func! s:RvUnmark(marked) abort
	if !a:marked || !has('nvim') || !exists('*luaeval')
		return
	endif
	call luaeval('_G.vimide_jump_mark_pop ~= nil and (function() _G.vimide_jump_mark_pop() return 1 end)() or 0')
endfunc

" g] / <C-마우스왼쪽> : 미리보기가 아니라 '지금 편집 창'에서 그 심볼로 간다.
"
" <C-]> 는 패널이 떠 있으면 context view 로 보내는데, 편집 창 자체를 그
" 심볼로 옮기고 싶을 때가 있다. 그 길이다.
"
" <C-[> 를 쓰지 않은 이유: 터미널에서 <C-[> 는 ESC 와 같은 바이트(27)다
" (실측: 둘 다 { 27 }). 매핑하면 Esc 가 통째로 가로채여 insert 를 빠져
" 나오지 못한다. g] 는 원래 :tselect(태그 후보 목록)인데, 이 설정에서는
" 그 자리를 이 동작에 내준다 - 후보 목록은 <C-]> 가 패널에 띄워 준다.
" luaeval 을 감싼 try 가 삼킨 오류를 알린다.
"
" 그 try 들은 '그 lua 함수가 아직 없을 때'(E117)를 견디려고 둔 것인데, 바로
" catch 로 아무 오류나 다 삼키고 있었다. 그래서 우리 lua 안의 진짜 오류가
" 말없이 사라졌다 - relationview 의 is_edit_win 을 정의보다 위에서 부르는
" 바람에 nil 이 나왔고, <C-]> 가 아무 말도 없이 '편집 창에서 태그 점프' 로
" 떨어졌다. 화면에는 아무 표시도 없어서 찾는 데 오래 걸렸다.
" E117 만 조용히 넘기고 나머지는 알린다.
func! s:LuaOops() abort
	if v:exception =~# 'E117'
		return
	endif
	echohl WarningMsg
	echomsg 'vim-ide: ' . substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', '')
	echohl None
endfunc

" 이 창에서 점프해도 되나.
"
" 예전에는 &buftype 하나만 봤다. quickr-preview 의 미리보기 창(\p)은
" buftype 이 비어 있어서 그 검사를 그냥 통과했고, 거기서 <C-]>/g]/f]/gf/
" 더블클릭을 누르면 미리보기가 점프한 파일로 바뀌었다가 곁창 지킴이가 도로
" 끌어내는 깜빡임이 났다. 이제 창 단위로 묻는다 - &previewwindow 와 부동
" 창까지 그 판정기가 본다.
"
" help 창은 살려 둔다. 거기서 <C-]> 는 |태그| 를 따라가는 제 동작이다.
func! s:JumpHere() abort
	if &buftype ==# 'help'
		return 1
	endif
	if &buftype !=# ''
		return 0
	endif
	if has('nvim') && exists('*luaeval')
		return luaeval('_G.vimide_is_edit_win == nil and true or _G.vimide_is_edit_win()')
	endif
	return 1
endfunc

" 'buftype 은 비었는데 EDIT 창이 아닌' 자리(= 미리보기 창)에서 점프를
" 눌렀을 때. 커서 밑 낱말을 들고 EDIT 자리로 옮겨 거기서 태그로 간다.
" <C-]> 는 '지금 창의 커서 밑 낱말' 을 쓰기 때문에, 옮기고 나서 부르면
" 엉뚱한 낱말을 찾는다. 그래서 낱말을 먼저 들고 :tjump 로 넘긴다
" (tagfunc 가 걸려 있어 <C-]> 와 같은 곳을 본다).
" 1 = 여기서 처리했다.
func! s:JumpFromPeek() abort
	if &buftype !=# '' || s:JumpHere()
		return 0
	endif
	let l:cw = expand('<cword>')
	if empty(l:cw) || !s:GotoEditSlot(1)
		return 1
	endif
	try
		execute 'tjump ' . l:cw
	catch
	endtry
	return 1
endfunc

func! s:RvEditJump() abort
	let l:marked = s:RvMarkCword()
	if has('nvim') && exists('*luaeval')
		try
			if luaeval('_G.relationview_open_include ~= nil and _G.relationview_open_include() or false')
				call s:RvUnmark(l:marked)
				return
			endif
			if luaeval('_G.relationview_local_jump ~= nil and _G.relationview_local_jump() or false')
				return
			endif
		catch
			call s:LuaOops()
		endtry
	endif
	if !s:JumpHere()
		call s:JumpFromPeek()
		return
	endif
	execute "normal! \<C-]>"
endfunc
nnoremap <silent> g] :call <SID>RvEditJump()<CR>
" f] 도 같은 자리에 건다(요청). g] 는 그대로 둔다 - 손에 익은 쪽을 쓰면 된다.
"
" 대가: 원래 f] 는 '이 줄에서 다음 ] 로' 가는 움직임인데 그 자리를 내준다.
" 그 움직임이 필요하면 t] 나 F] 를 쓰거나, 아래 설정으로 이 매핑을 끈다.
"   let g:vimide_edit_jump_fkey = 0
if get(g:, 'vimide_edit_jump_fkey', 1)
	nnoremap <silent> f] :call <SID>RvEditJump()<CR>
endif
" <C-마우스왼쪽> 도 같은 자리로 걸어 두기는 한다. 다만 지금 쓰는 두
" 터미널에서는 이 키가 nvim 까지 오지 않는다 - 터미널이 먼저 먹는다.
"   Tera Term  Ctrl+드래그 = 사각 영역 선택 + 클립보드 복사
"   iTerm2     Ctrl+클릭  = 컨텍스트 메뉴
" 그래서 실제로 쓰는 길은 g] 다. 터미널 쪽 배정을 풀면(iTerm2 는
" Settings > Pointer) 이 매핑이 그때부터 살아난다. 지워 두면 그때 다시
" 만들어야 하므로 남겨 둔다 - 걸려 있어도 해가 없다.
nnoremap <silent> <C-LeftMouse> <LeftMouse>:call <SID>RvJumpPrimary()<CR>

func! s:RvCtxJump() abort
	let l:marked = s:RvMarkCword(1)
	if has('nvim') && exists('*luaeval')
		try
			" #include 줄이면 배치와 상관없이 그 헤더로 간다
			if luaeval('_G.relationview_open_include ~= nil and _G.relationview_open_include() or false')
				" 헤더는 심볼이 아니다: 칠한 것을 도로 푼다
				call s:RvUnmark(l:marked)
				return
			endif
			" 파라미터/지역변수는 색인에 없다: 이 함수 안의 선언으로 간다
			if luaeval('_G.relationview_local_jump ~= nil and _G.relationview_local_jump() or false')
				return
			endif
			" 패널이 떠 있으면 플러그인이 처리한다:
			"   미리보기 있음 -> context view 에서 열고 포커스 이동
			"   미리보기 없음 -> 패널만 그 심볼로 바꾸고(PINNED) false 를
			"                    돌려주어 아래 기본 점프가 EDIT 창에서 난다
			if luaeval('_G.relationview_ctx_jump ~= nil and _G.relationview_ctx_jump() or false')
				return
			endif
			" 여기부터는 릴레이션 뷰가 꺼져 있을 때다.
			" 패널도 미리보기도 없을 때만 온다. 예전에는 패널만 봐서,
			" context only 모드에서는 위 핸들러가 처리했는데도 이 줄이
			" 한 번 더 quickfix 를 열었다.
			if !luaeval('(_G.relationview_panel_win ~= nil and _G.relationview_panel_win() ~= nil) or (_G.relationview_ctx_win ~= nil and _G.relationview_ctx_win() ~= nil) or false')
				" 릴레이션 뷰가 꺼져 있으면 '지금 보고 있는 EDIT 창'에서 바로
				" 뛴다. tagfunc(GTAGS)가 답한다.
				"
				" 예전에는 여기서 곧장 quickfix 로 보냈다. 요청대로 먼저
				" 편집 창에서 뛰어 보고, 태그가 답하지 못할 때만 예전 길로
				" 떨어진다.
				if !s:JumpHere()
					" 미리보기 창이면 낱말을 들고 EDIT 자리로 옮겨 거기서 뛴다
					if s:JumpFromPeek()
						return
					endif
				endif
				if s:JumpHere()
					try
						execute "normal! \<C-]>"
						return
					catch
						" 태그를 못 찾았다(E426/E433 등). 칠한 것을 도로 푼다 -
						" 안 뛰었으니 <C-t> 로 풀 기회도 없다.
						call s:RvUnmark(l:marked)
						let l:marked = 0
						" 아래 :Gtags 길이 없으면 맨 끝에서 같은 <C-]> 를
						" 한 번 더 시도하게 된다. 이미 해 봤으니 여기서 끝낸다.
						if exists(':Gtags') != 2
							return
						endif
					endtry
				endif
				" 태그가 답하지 못했다: 예전처럼 quickfix 로 보내고, 거기서도
				" 못 찾으면 그 심볼을 정의한 파일을 project files 에 넣고
				" (색인까지) 한 번 더 찾는다.
				if exists(':Gtags') == 2
							\ && luaeval('_G.relationview_has_db ~= nil and _G.relationview_has_db() or false')
					let l:w = expand('<cword>')
					call setqflist([])
					try | execute 'Gtags -d ' . l:w | catch | endtry
					if empty(getqflist()) && l:w =~# '^[A-Za-z_][A-Za-z0-9_]*$'
						" 소스 전체 검색은 커널에서 1초를 훌쩍 넘긴다: 백그라운드로
						" 돌리고, 파일이 추가되면 그때 다시 찾는다
						call luaeval('_G.projectfiles_add_for_symbol_async ~= nil and (function() _G.projectfiles_add_for_symbol_async(_A, function(n) if n and n > 0 then vim.cmd("Gtags -d " .. _A) end end) return 1 end)() or 0', l:w)
					endif
					return
				endif
			endif
		catch
			call s:LuaOops()
		endtry
	endif
	" 특수 창(패널/ProjectFiles/Tagbar/NERDTree/quickfix ...)에서 builtin
	" C-] 는 그 창의 버퍼를 갈아치워 사이드바를 부순다. help 는 <C-]> 가
	" |태그| 점프라서 살려둔다. 미리보기 창은 낱말을 들고 EDIT 창으로 간다.
	if !s:JumpHere()
		call s:JumpFromPeek()
		return
	endif
	execute "normal! \<C-]>"
endfunc
" <C-]> 가 어디로 뛸까 - EDIT 창이냐, 미리보기(context)냐.
"
"   'edit' (기본)  <C-]>        EDIT 창에서 정의로 (g] / f] 와 같은 자리)
"                  <C-]><C-]>   미리보기 창에서 정의로
"   'ctx'          그 반대. 예전 동작이다.
"
" 마우스도 같은 짝이다:
"   Ctrl+왼쪽클릭  = <C-]>        (EDIT 창)
"   더블클릭       = <C-]><C-]>   (미리보기 창)
"
" 릴레이션 뷰가 꺼져 있으면 둘 다 EDIT 창으로 간다 - RvCtxJump 가 패널이
" 없을 때는 평범한 태그 점프로 떨어진다.
let g:vimide_jump_target = 'edit'

" 두 키짜리(<C-]><C-]>) 배정을 쓸지.
"
" 대가가 하나 있다: 두 키를 걸어 두면 vim 은 <C-]> 를 한 번 눌렀을 때
" '뒤에 <C-]> 가 더 올까' 하고 'timeoutlen'(기본 1000ms)만큼 기다렸다가
" 뛴다. 한 번 누르는 쪽이 그만큼 늦어진다는 뜻이다.
"
"   set timeoutlen=250              " 기다림을 짧게 (거의 안 느껴진다)
"   let g:vimide_ctx_jump_seq = 0   " 두 키를 아예 안 쓴다 (기다림도 없다)
"
" 0 으로 두면 미리보기 점프는 g:vimide_jump_target = 'ctx' 로 바꾸거나
" 패널의 <CR>, \lc 로 연다.
let g:vimide_ctx_jump_seq = 1

" 한 번 누르는 쪽 / 두 번 누르는 쪽. 더블클릭도 '한 번 누르는 쪽'을 따른다.
func! s:RvJumpPrimary() abort
	if get(g:, 'vimide_jump_target', 'edit') ==# 'ctx'
		call s:RvCtxJump()
	else
		call s:RvEditJump()
	endif
endfunc
func! s:RvJumpSecondary() abort
	if get(g:, 'vimide_jump_target', 'edit') ==# 'ctx'
		call s:RvEditJump()
	else
		call s:RvCtxJump()
	endif
endfunc
nnoremap <silent> <C-]> :call <SID>RvJumpPrimary()<CR>
if get(g:, 'vimide_ctx_jump_seq', 1)
	nnoremap <silent> <C-]><C-]> :call <SID>RvJumpSecondary()<CR>
endif

" gf : #include 줄에서는 relationview 의 헤더 해석기(포함한 파일 옆 →
"      GTAGS 경로 색인 → 'path')로 그 헤더를 편집창에 연다. 그 밖에는
"      평소의 gf.
func! s:RvGotoFile() abort
	if has('nvim') && exists('*luaeval')
		try
			if luaeval('_G.relationview_open_include ~= nil and _G.relationview_open_include() or false')
				return
			endif
		catch
			call s:LuaOops()
		endtry
	endif
	" 곁창에서는 그냥 둔다. <C-]>/g]/더블클릭은 이 가드가 있는데 gf 만
	" 빠져 있어서, NERDTree/aerial/tagbar/bufexplorer 에서 파일 이름처럼
	" 보이는 글자 위에 gf 를 누르면 그 사이드바에 파일이 실렸다.
	" 미리보기 창(\p)도 여기 걸린다 - buftype 은 비었지만 EDIT 창이 아니다.
	if !s:JumpHere()
		if &buftype ==# '' && s:GotoEditSlot(1)
			" 파일 이름은 낱말이 아니라 <cfile> 이다. 들고 옮겨서 연다.
			let l:f = expand('<cfile>')
			if !empty(l:f)
				execute 'silent! find ' . fnameescape(l:f)
			endif
		endif
		return
	endif
	normal! gf
endfunc
nnoremap <silent> gf :call <SID>RvGotoFile()<CR>

" C-c 매핑은 checksymbol.vim 을 source 한 뒤에 둔다(아래쪽 참고)

" 요청대로 C-0 이 다음, C-9 가 이전이다 (예전에는 반대였다).
nnoremap <silent> <C-0> :call <SID>QfStep(1)<CR>
nnoremap <silent> <C-9> :call <SID>QfStep(-1)<CR>

" 터미널이 Ctrl+0 / Ctrl+9 를 못 보낼 때의 대체키: ]r 다음 / [r 이전
"
" 이 두 키는 전통적인 터미널 인코딩에 자리가 없다. CSI-u(kitty keyboard
" protocol)를 쓰는 터미널만 nvim 까지 보낸다 - iTerm2 3.5+, kitty, WezTerm,
" Ghostty, foot. 테라텀 같은 데서는 아예 안 오고 맨 '0' / '9' 가 대신
" 들어간다. 그러면 0 은 줄 맨 앞으로 가고 9 는 count 가 되어 엉뚱하게
" 움직인다 - 안 먹는 것보다 나쁘다.
"
"   let g:vimide_rvlist_next_key = ']r'   " 다른 키로 바꾸려면
"   let g:vimide_rvlist_prev_key = '[r'
"   let g:vimide_rvlist_next_key = ''     " 대체키를 아예 안 만들려면
let s:rv_next = get(g:, 'vimide_rvlist_next_key', ']r')
let s:rv_prev = get(g:, 'vimide_rvlist_prev_key', '[r')
if !empty(s:rv_next)
	execute 'nnoremap <silent> ' . s:rv_next . ' :call <SID>QfStep(1)<CR>'
endif
if !empty(s:rv_prev)
	execute 'nnoremap <silent> ' . s:rv_prev . ' :call <SID>QfStep(-1)<CR>'
endif
"nmap <C-h> :.,$s/<C-R>=expand("<cword>")<CR>//gc<SPACE>
" 곁창에서 누르면 그 창의 파일 이름(NERD_tree_1 ...)으로 global 을 돌려
" 'global command failed' 만 났다. F6 과 같은 길로 EDIT 창에서 돌린다.
nnoremap <silent> <C-\><C-]> :VimIdeInEdit GtagsCursor<CR>
" <C-]> 는 위쪽 s:RvJumpPrimary() 매핑을 쓴다(기본은 EDIT 창 점프,
" <C-]><C-]> 가 미리보기 쪽 - g:vimide_jump_target 참고). 예전 매핑은:
"nmap <C-]> :Gtags -d <C-R>=expand("<cword>") <CR><CR>
" <C-t> : 태그 스택으로 되돌아간다. 비어 있으면 점프 목록으로 되돌아간다.
"
" 예전에는 'nmap <C-t> <C-o><CR>' 이었다. 뒤의 <CR> 은 되돌아간 자리에서
" 한 줄을 더 내려 보내는 군더더기였고(늘 한 줄 어긋나 돌아왔다), 태그
" 스택을 아예 쓰지 않으니 <C-]> 로 판 깊이를 되짚지도 못했다. 이제 심볼
" 점프가 태그 스택을 제대로 쌓으므로(relationview.lua 의 push_tag,
" projectfiles.lua 의 jump_to_symbol) 진짜 <C-t> 를 쓴다.
func! s:JumpBack() abort
	" 곁창에서 눌렀으면 먼저 편집 자리로 옮긴다.
	" 태그 스택도 점프 목록도 '창마다' 따로 쌓인다. 곁창에서 부르면 그 곁창이
	" 물려받은 남의 이력을 뒤지다가 거기에 파일을 실어 버린다 - aerial 이
	" 소스 파일로 바뀌는 식이다. s:GotoEditSlot 은 한참 아래(s:InEditWin 옆)에
	" 있다. 자리가 없으면 0 을 주는데, 그때는 예전처럼 그냥 해 본다.
	call s:GotoEditSlot(0)
	" 갈 때 칠해 둔 색을 먼저 푼다. 우리가 새로 칠한 것만 풀린다 -
	" 원래 칠해져 있던 심볼은 스택에 false 로 쌓여 그대로 남는다.
	if has('nvim') && exists('*luaeval')
		call luaeval('_G.vimide_jump_mark_pop ~= nil and (function() _G.vimide_jump_mark_pop() return 1 end)() or 0')
	endif
	let l:st = gettagstack(win_getid())
	if get(l:st, 'curidx', 1) > 1
		try
			execute "normal! \<C-t>"
			return
		catch
		endtry
	endif
	" 태그 스택이 비었으면 점프 목록으로. 그것도 비었으면 아무 일도 없다.
	execute "normal! \<C-o>"
endfunc
nnoremap <silent> <C-t> :call <SID>JumpBack()<CR>

"------------------------------------------------------------------------------
"- 마우스 더블클릭 = <C-]> (심볼 정의로 점프)
"- '#include "foo.h"' / '#include <a/b.h>' 줄에서는 그 헤더 파일을 연다.
"- quickfix, NERDTree, Tagbar, RelationView 등 특수 창은 각자의 동작을 유지한다
"- (버퍼 로컬 매핑이 우선하고, buftype 이 빈 일반 파일 창에서만 아래가 동작).
"------------------------------------------------------------------------------
function! s:RvMouseJump() abort
	" 특수 버퍼(quickfix, help, terminal ...)는 기본 더블클릭 동작 유지.
	" 미리보기 창(\p)은 buftype 이 비어 있어 예전에는 이 검사를 통과했다 -
	" 거기서 더블클릭하면 미리보기가 점프한 파일로 바뀌었다.
	if !s:JumpHere()
		if !s:JumpFromPeek()
			execute "normal! \<2-LeftMouse>"
		endif
		return
	endif
	" 더블클릭 = <C-]><C-]> 다. 키와 마우스의 짝을 맞춘다:
	"   Ctrl+왼쪽클릭 = <C-]>       -> EDIT 창의 정의로
	"   더블클릭      = <C-]><C-]>  -> 미리보기(context) 창의 정의로
	" (g:vimide_jump_target = 'ctx' 면 둘이 맞바뀐다)
	"   #include        -> 그 헤더를 EDIT 창에서 연다
	"   파라미터/지역변수 -> 이 함수 안의 선언으로 (EDIT 창)
	" 패널+미리보기가 꺼져 있으면 미리보기 쪽도 EDIT 창/quickfix 로 떨어진다.
	if expand('<cword>') =~# '^[A-Za-z_][A-Za-z0-9_]*$'
		call s:RvJumpSecondary()
	else
		execute "normal! \<2-LeftMouse>"
	endif
endfunction

nnoremap <silent> <2-LeftMouse> :call <SID>RvMouseJump()<CR>
nnoremap <silent> <3-LeftMouse> :call <SID>RvMouseJump()<CR>
nnoremap <silent> <4-LeftMouse> :call <SID>RvMouseJump()<CR>

"------------------------------------------------------------------------------
"- 마우스 뒤로/앞으로 버튼 = <C-o> / <C-i> (점프 목록 이동)
"- RelationView 패널에서는 편집 창의 점프 목록을 움직이고, ContextView 에서는
"- 그 창의 <C-]> 스택을 되돌린다(각 창의 버퍼 로컬 매핑이 우선).
"------------------------------------------------------------------------------
" 곁창에서 눌렀을 때 그 곁창의 점프 목록을 뒤지지 않도록 한 번 거른다.
" (RelationView 패널과 context 창은 자기 버퍼 지역 매핑이 먼저라 그대로다)
func! s:JumpList(dir) abort
	call s:GotoEditSlot(0)
	try
		if a:dir ==# 'back'
			execute "normal! \<C-o>"
		else
			execute "normal! \<C-i>"
		endif
	catch /^Vim\%((\a\+)\)\=:E/
	endtry
endfunc
nnoremap <silent> <X1Mouse> :call <SID>JumpList('back')<CR>
nnoremap <silent> <X2Mouse> :call <SID>JumpList('forward')<CR>

" 터미널이 그 버튼을 아예 안 보낼 때.
"
" xterm 의 마우스 보고는 버튼 1~5 까지고(4/5 는 휠), 앞/뒤 버튼은 그 밖이다.
" iTerm2 도 Tera Term 도 그래서 <X1Mouse>/<X2Mouse> 를 만들어 주지 못한다.
" 대신 터미널 쪽에서 그 버튼이 어떤 시퀀스를 보내도록 설정할 수 있으니,
" 그 시퀀스를 여기서 받는다. 기본은 ESC[15;2~ / ESC[17;2~ 이고, nvim 이
" 그것을 어떤 이름으로 읽는지는 TERM 에 따라 갈린다. pty 로 확인한 결과
" TERM=xterm 이면 <F17>/<F18>, TERM=vt100 이면 <S-F5>/<S-F6> 였다. 그래서
" 둘 다 걸어 둔다 - 어차피 하나만 들어온다. :JumpKeyTest 로 확인할 수 있다.
"
"   iTerm2   Settings > Profiles > (프로필) > ... 이 아니라 Pointer 탭:
"            'Mouse Button and Trackpad Gesture Actions' 에 버튼 4/5 를
"            추가하고 Action = 'Send Escape Sequence',
"            Text = '[15;2~' (뒤로) / '[17;2~' (앞으로)
"
"   ---- 윈도우 터미널들 ----
"
"   Windows Terminal, PuTTY, MobaXterm, TeraTerm 은 넷 다 '마우스 옆 버튼을
"   어떤 시퀀스로 보내라'는 설정이 없다. 터미널이 그 버튼을 아예 읽지 않고
"   창 관리자에게 넘긴다. 그래서 터미널 설정으로는 풀 수 없고, 윈도우 쪽에서
"   그 버튼을 '키'로 바꿔 줘야 한다. 바꿀 키는 <A-Left>/<A-Right> 가 가장
"   쉽다 - 브라우저의 뒤로/앞으로와 같은 키라 마우스 유틸리티가 대개 그
"   자리를 이미 갖고 있고, 넷 다 그 키를 그대로 흘려보낸다.
"
"   1) 마우스 제조사 유틸리티 (로지텍 Options+, 마우스 드라이버 ...)
"      가장 간단하다. 아무것도 설치하지 않아도 되는 경우가 많다.
"        옆 버튼 뒤로  ->  Alt+Left        (또는 Ctrl+O)
"        옆 버튼 앞으로 ->  Alt+Right       (또는 Ctrl+I)
"
"   2) AutoHotkey (유틸리티가 없을 때)
"      ~/.vim-ide/tools/vim-ide-mouse.ahk 를 윈도우로 복사해 더블클릭하면
"      끝이다. 알맹이는 세 줄이다:
"        #Requires AutoHotkey v2.0
"        XButton1::Send("!{Left}")
"        XButton2::Send("!{Right}")
"      (v1 이 깔려 있으면 tools/vim-ide-mouse-v1.ahk 쪽을 쓴다 - v1 과 v2 는
"       문법이 달라 서로의 스크립트를 못 돌린다)
"      창 조건(#HotIf)은 일부러 걸지 않았다. 실행 파일 이름이 제각각이라
"      (MobaXterm_Personal_24.2.exe) 조건이 조용히 안 맞는 일이 잦고,
"      Alt+화살표는 브라우저에서도 뒤로/앞으로라 전역이어도 손해가 없다.
"
"   3) 이스케이프 시퀀스를 직접 보내고 싶으면 위 자리에
"        XButton1::SendInput "{Esc}[15;2~"
"        XButton2::SendInput "{Esc}[17;2~"
"      로 두어도 된다. 그쪽은 <F17>/<F18>(또는 <S-F5>/<S-F6>)로 들어온다.
"
"   먹는지 확인: :JumpKeyTest 를 치고 그 버튼을 한 번 누른다.
"     <A-Left> 라고 나오면 끝이다. 아무 반응이 없으면 윈도우 쪽에서 아직
"     버튼이 키로 바뀌지 않은 것이다 - vim 을 더 고칠 일이 아니다.
"
"   <A-Left> 가 안 올 때: 터미널이 Alt 를 창 메뉴로 먹고 있는 것이다.
"     PuTTY/MobaXterm 은 기본으로 Alt+키를 ESC 를 앞에 붙여 그대로 보낸다
"     (그래서 따로 손댈 것이 없다). 그래도 안 오면 Alt 를 쓰지 말고 위 2)의
"     이스케이프 시퀀스 쪽이나 Ctrl+O / Ctrl+I 로 바꾸면 된다 - 그 둘은
"     패널과 미리보기 창도 같이 받는다.
"
" 마우스 조합도 같이 둔다. Tera Term 은 옆 버튼은 못 보내지만 수식키는
" 마우스 보고에 실어 보낸다(vtterm.c 의 MouseReport 는 Shift=4, Alt=8,
" Ctrl=16 을 버튼 바이트에 OR 한다). 그래서 Ctrl/Shift + 우클릭은 윈도우
" 쪽에 아무것도 설치하지 않고 바로 쓸 수 있다 - Ctrl+우클릭은 vim 이 원래
" <C-t>(태그 되돌리기)로 쓰는 자리이기도 해서 뜻도 맞는다.
"
"   let g:vimide_jump_back_key    = ['<F17>', '<S-F5>', '<A-Left>', '<C-RightMouse>']
"   let g:vimide_jump_forward_key = ['<F18>', '<S-F6>', '<A-Right>', '<S-RightMouse>']
"   let g:vimide_jump_back_key    = []     " 이 대체 키를 쓰지 않는다
func! s:MapJumpAlias(which, rhs) abort
	let l:v = get(g:, 'vimide_jump_' . a:which . '_key',
				\ a:which ==# 'back' ? ['<F17>', '<S-F5>', '<A-Left>', '<C-RightMouse>']
				\                   : ['<F18>', '<S-F6>', '<A-Right>', '<S-RightMouse>'])
	if type(l:v) == type('')
		let l:v = empty(l:v) ? [] : [l:v]
	endif
	for l:k in l:v
		execute 'nnoremap <silent> ' . l:k . ' ' . a:rhs
	endfor
endfunc
call s:MapJumpAlias('back', ":call <SID>JumpList('back')<CR>")
call s:MapJumpAlias('forward', ":call <SID>JumpList('forward')<CR>")

" :JumpKeyTest - 이 키가 여기까지 오기는 하는가
"
" 마우스 옆 버튼이 안 먹을 때, 터미널이 아무것도 안 보내는 것인지 보내는데
" 키 이름이 다른 것인지 가려 준다. 실행하고 그 버튼(또는 키)을 한 번 누르면
" nvim 이 받은 이름과 원시 바이트를 그대로 보여준다. 아무 반응이 없으면
" 터미널이 그 버튼을 아예 안 보내고 있는 것이다 - 그때는 vim 을 고칠 일이
" 아니라 터미널/AutoHotkey 쪽을 고쳐야 한다.
func! s:JumpKeyTest() abort
	echo '키(또는 마우스 버튼)를 한 번 누르세요... (아무 반응이 없으면 터미널이 안 보내는 것)'
	if exists('*getcharstr') && exists('*keytrans')
		let l:c = getcharstr()
		redraw
		echo printf('받은 키 = %s     원시 = %s', keytrans(l:c), strtrans(l:c))
	else
		let l:c = getchar()
		redraw
		echo printf('받은 키 = %s', type(l:c) == type(0) ? nr2char(l:c) : strtrans(l:c))
	endif
endfunc
command! JumpKeyTest call s:JumpKeyTest()

nmap <Leader>g <ESC>:Gtags<SPACE>
nmap <Leader>e <plug>(quickr_cscope_egrep) <C-R>=expand("<cword>") <CR>
nmap <Leader>f <plug>(quickr_cscope_files) <C-R>=expand("<cword>") <CR>
"nmap <Leader>e <ESC>:Cscope<SPACE>e<SPACE><C-R>=expand("<cword>")<CR>
"nmap <Leader>e <ESC>:GscopeFind<SPACE>e<SPACE><C-R>=expand("<cword>")<CR>

"==============================================================================
" nvim fallback: cscope support was removed in nvim 0.9+, so the
" quickr-cscope <plug> mappings above cannot work there. Remap them to the
" equivalent :Gtags queries (gtags.vim does not need cscope) and route the
" callee query to the RelationView panel. Plain vim keeps the original
" cscope behavior untouched.
"==============================================================================
if has('nvim') && !has('cscope')
    " quickr-cscope cannot 'cs add' without cscope; silence its warning
    let g:quickr_cscope_autoload_db = 0
    " gtags-cscope.vim (part of gtags.vim) only prints a startup warning
    " here - preload its guard so it skips silently
    let loaded_gtags_cscope = 1
    nmap <Leader><Leader>g :Gtags -d <C-R>=expand("<cword>")<CR><CR>
    nmap <Leader><Leader>s :Gtags -r <C-R>=expand("<cword>")<CR><CR>
    nmap <Leader><Leader>f :Gtags -P <C-R>=expand("<cfile>")<CR><CR>
    nmap <Leader><Leader>i :Gtags -g <C-R>=expand("<cfile>")<CR><CR>
    nmap <Leader><Leader>e :Gtags -g <C-R>=expand("<cword>")<CR><CR>
    nmap <Leader><Leader>a :Gtags -g <C-R>=expand("<cword>")<CR><CR>
    " 'functions called by this one' is cscope's 'd' query, which nvim
    " dropped with cscope. RelationView answers it now by reading the
    " function body with treesitter: <Leader><Leader>d opens that direction.
    nmap <Leader><Leader>d :RelationViewCalls<CR>
    nmap <Leader>e :Gtags -g <C-R>=expand("<cword>")<CR>
    nmap <Leader>f :Gtags -P <C-R>=expand("<cword>")<CR>
endif

""==============================================================================
"" gutentags key map
""==============================================================================

" Set vim-gutentags and gutentags_plus
"let g:gutentags_project_root = ['.root', 'README', '.git']
"let g:gutentags_cache_dir = expand('~/.cache/tags')
"let g:gutentags_modules = ['ctags', 'gtags-cscope']
"let g:gutentags_add_default_project_roots = 0
"let g:gutentags_trace = 1
"let g:gutentags_debug = 1
"let g:gutentags_define_advanced_commands = 1
"let g:gutentags_enabled = 0
"let g:GtagsCscope_Auto_Load = 1
"let g:gutentags_background_update = 0
"let g:gutentags_exclude_filetypes = []

"let g:gutentags_plus_nomap = 1
"nmap <Leader><Leader>s :GscopeFind s <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>g :GscopeFind g <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>d :GscopeFind d <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>c :GscopeFind c <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>t :GscopeFind t <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>e :GscopeFind e <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>f :GscopeFind f <C-R>=expand("<cfile>") <CR><CR>
"nmap <Leader><Leader>i :GscopeFind i <C-R>=expand("<cfile>") <CR><CR>
"nmap <Leader><Leader>a :GscopeFind a <C-R>=expand("<cword>") <CR><CR>
"nmap <Leader><Leader>z :GscopeFind z <C-R>=expand("<cword>") <CR><CR>

" To know when Gutentags is generating tags
"set statusline+=%{gutentags#statusline()}

"" To avoid conflict ctags key map
"map <C-]> :tjump <C-R>=expand("<cword>")<CR><CR>

"==============================================================================
"= Editing
"==============================================================================
" Tell Vim to delete the white space at the start of the line, a line break
"  and the character before where Insert mode started.
set backspace=indent,eol,start

" Display the current cursor position in the lower right corner of the
" Vim window. But for now this is no londer used thanks to airline plugin.
"set ruler

" Display an incomplete vim command in the lower right corner of the Vim window
" This is no longer used thanks to AutoComplPop plugin
"set showcmd

" Display line numbers
set nu

" Set line number width
set numberwidth=5

" Do not wrap lines
set nowrap

" Move the cursor to the first non-blank of the line when Vim
" move commands are used.
set startofline

" Turn on syntax highlighting
syntax on

" Whatever floats in your boat
set background=dark
"set background=light

" Delete trailing spaces at eol when a file is saved.
func! DeleteTrailingWS()
    exe "normal mz"
    %s/\s\+$//ge
    exe "normal `z"
endfunc
"autocmd BufWrite * :call DeleteTrailingWS()

" Locate the cursor in the last position when Vim is closed
au BufReadPost *
\ if line("'\"") > 0 && line("'\"") <= line("$") |
\   exe "norm g`\"" |
\ endif

" Set 80 column guideline
set colorcolumn=80
highlight ColorColumn ctermbg=red


"==============================================================================
" Tab & Indent
"==============================================================================
" Set tab size
set tabstop=4
set shiftwidth=4
set softtabstop=4

" Use spaces instead of tabs
set expandtab

" Work for C-like programs, but can also be used for other languages
set smartindent

" Copy indent from current line when starting a new line. This should be
" on when smartindent is used.
set autoindent

" Set indent for switch statement in C. Just my cup of tea.
set cinoptions=:0


"==============================================================================
" Encoding and Format
"==============================================================================
" Determine the 'fileencoding' of a file being opened.
set fileencodings=utf-8,cp949,cp932,euc-kr,shift-jis,big5,ucs-2le,latin1

" Represent data in memory
set encoding=utf-8

" Use only unix fileformat. "dos" can be added like "unix, dos"
" if you are a coward.
set fileformats=unix


"==============================================================================
" Search
"==============================================================================
" Highlight all matches
set hlsearch

" Not search wrap around the end of a file
set nowrapscan

" Ignore case in search patterns
set ignorecase

" Override ignorecase option if the search pattern contains an uppercase
" character.
set smartcase

" Show where the pattern matches as it was typed so far.
set incsearch

" Jump to one to the other using %. Various character can be added.
set matchpairs+=<:>

"==============================================================================
"= vim-mark
"==============================================================================
"https://jonasjacek.github.io/colors/


"let g:mwPalettes = {
"\	'mypalette': [
	"\   { 'ctermbg':'Cyan',         'ctermfg':'Black', 'guibg':'#8CCBEA', 'guifg':'Black' },
	"\   { 'ctermbg':'Green',        'ctermfg':'Black', 'guibg':'#A4E57E', 'guifg':'Black' },
	"\   { 'ctermbg':'Yellow',       'ctermfg':'Black', 'guibg':'#FFDB72', 'guifg':'Black' },
	"\   { 'ctermbg':'Red',          'ctermfg':'Black', 'guibg':'#FF7272', 'guifg':'Black' },
	"\   { 'ctermbg':'Magenta',      'ctermfg':'Black', 'guibg':'#FFB3FF', 'guifg':'Black' },
	"\   { 'ctermbg':'Blue',         'ctermfg':'Black', 'guibg':'#9999FF', 'guifg':'Black' },
	"\   { 'ctermbg':'White',        'ctermfg':'Black', 'guibg':'#FFFFFF', 'guifg':'Black' },
	"\   { 'ctermbg':'DarkBlue',     'ctermfg':'Black', 'guibg':'#800000', 'guifg':'Black' },
	"\   { 'ctermbg':'DarkYellow',   'ctermfg':'Black', 'guibg':'#808000', 'guifg':'Black' },
	"\   { 'ctermbg':'LightCyan',    'ctermfg':'Black', 'guibg':'#FF00FF', 'guifg':'Black' },
	"\   { 'ctermbg':'DarkMagenta',	'ctermfg':'Black', 'guibg':'#C0C0C0', 'guifg':'Black' },
	"\   { 'ctermbg':'LightRed',	'ctermfg':'Black', 'guibg':'#C0C0C0', 'guifg':'Black' },
"\	]
"\}

" Make it the default:
"let g:mwDefaultHighlightingPalette = 'mypalette'
" F4 색은 ~/.vim/markpalette.vim 에서 온다 (왜 직접 만들었는지는 그 파일에).
" 여기서 읽어야 한다 - vim-mark 은 plugin 이 읽힐 때(.vimrc 가 끝난 뒤)
" 이 변수를 보기 때문이다. 이 줄을 지우면 아래 'maximum' 으로 돌아간다.
if filereadable(expand('$HOME/.vim/markpalette.vim'))
    source $HOME/.vim/markpalette.vim
else
    let g:mwDefaultHighlightingPalette = 'maximum'
endif
"let g:mwDefaultHighlightingPalette = 'maximum'
"let g:mwDefaultHighlightingPalette = 'extended'
"let g:mwDefaultHighlightingNum = 3

"==============================================================================
"==============================================================================
"= 바깥에서 바뀐 파일을 알아채기
"==============================================================================
" 'autoread' 는 '물어보지 않고 다시 읽는다'는 뜻일 뿐, vim 이 스스로 파일을
" 들여다본다는 뜻이 아니다. :e 나 셸 명령처럼 뭔가 계기가 있을 때만 확인한다.
" 그래서 bazel 빌드나 git 이 파일을 바꿔 놓아도 버퍼는 옛 내용 그대로 앉아
" 있었다. 실측(개발서버):
"   파일을 열고 바깥에서 바꿈 -> 3초 뒤에도 버퍼는 옛 내용
"   :checktime 을 치면        -> 그때 새 내용
" autoread 는 켜져 있었고(기본값), checktime 을 부르는 것이 아무 데도 없었다.
"
" 커서가 멈출 때와 창으로 돌아올 때 확인한다. updatetime 이 100ms 라
" CursorHold 가 자주 오므로 1초에 한 번으로 묶는다 - checktime 은 열려 있는
" 버퍼마다 stat 한 번이라 싸지만, 초당 열 번씩 할 일은 아니다.
" 특수 창(터미널, 패널 …)은 건드리지 않는다.
"   let g:vimide_autocheck = 0   " 이 확인을 끄기
let s:last_check = 0
function! s:CheckTimeThrottled() abort
    if get(g:, 'vimide_autocheck', 1) == 0 || &buftype !=# '' || bufname('%') ==# ''
        return
    endif
    let l:now = localtime()
    if l:now - s:last_check < 1
        return
    endif
    let s:last_check = l:now
    silent! checktime
endfunction

augroup VimIdeAutoCheck
    autocmd!
    autocmd FocusGained,BufEnter,CursorHold,CursorHoldI *
                \ call <SID>CheckTimeThrottled()
    " 실제로 다시 읽었을 때만 알려 준다. 조용히 바뀌면 '내가 방금 본 것과
    " 다른 파일'을 보고 있게 되는데, 그게 제일 헷갈린다.
    autocmd FileChangedShellPost *
                \ echohl WarningMsg
                \ | echo '바깥에서 바뀌어 다시 읽었습니다: ' . expand('<afile>:t')
                \ . '   (]c / [c 로 바뀐 곳, \v 로 전체 diff)'
                \ | echohl None
augroup END

"= vim-signify
"==============================================================================

" default updatetime 4000ms is not good for async update
set updatetime=100



"==============================================================================
"= vim-gitgutter
"==============================================================================
"if empty(glob('~/.vim-swap'))
	"silent !mkdir -p ~/.vim-swap
"endif
"set directory=$HOME/.vim-swap
"let g:gitgutter_log=1
"set updatetime=100
"let g:gitgutter_realtime=1
"let g:gitgutter_eager=1
"let g:gitgutter_override_sign_column_highlight=0

"highlight SignColumn ctermbg=whatever    " terminal Vim
"highlight SignColumn guibg=whatever      " gVim/MacVim

let g:gitgutter_sign_column_always = 1
let g:gitgutter_max_signs = 500  " default value

"nmap ]h <Plug>GitGutterNextHunk
"nmap [h <Plug>GitGutterPrevHunk
"nmap <Leader>ha <Plug>GitGutterStageHunk
"nmap <Leader>hr :GitGutterUndoHunk<CR>
"nmap <Leader>hv <Plug>GitGutterPreviewHunk
"nmap <Leader>ht :GitGutterLineHighlightsToggle<CR>


"GitGutterAdd          " an added line
"GitGutterChange       " a changed line
"GitGutterDelete       " at least one removed line
"GitGutterChangeDelete " a changed line followed by at least one removed line

let g:gitgutter_sign_added = '+'
let g:gitgutter_sign_modified = 'm'
let g:gitgutter_sign_removed = '-'
let g:gitgutter_sign_removed_first_line = '^^'
let g:gitgutter_sign_modified_removed = 'ww'

"GitGutterAddLine          " default: links to DiffAdd
"GitGutterChangeLine       " default: links to DiffChange
"GitGutterDeleteLine       " default: links to DiffDelete
"GitGutterChangeDeleteLine " default: links to GitGutterChangeLineDefault, i.e. DiffChange

"The base of the diff
"By default buffers are diffed against the index. However you can diff against any commit by setting:
let g:gitgutter_diff_base = '<commit SHA>'

"Extra arguments for git diff
"If you want to pass extra arguments to git diff, for example to ignore whitespace, do so like this:
"let g:gitgutter_diff_args = '-w'

"Key mappings
"To disable all key mappings:
let g:gitgutter_map_keys = 1

" Default:
let g:gitgutter_grep_command = 'grep --color=never -e'

"To turn off vim-gitgutter by default
let g:gitgutter_enabled = 1
"To turn off signs by default
let g:gitgutter_signs = 1
"To turn on line highlighting by default
let g:gitgutter_highlight_lines = 0
"To turn off asynchronous updates
let g:gitgutter_async = 1


"==========================
"= autocmd
"==========================
" show space and tap
set list
command! Q silent! q
command! WQ silent! wq
set backupdir=/tmp
"set cmdheight=1

autocmd BufEnter *.c        setlocal ts=8 sw=8 sts=8 noexpandtab
autocmd BufEnter *.cpp      setlocal ts=4 sw=4 sts=4 noexpandtab
autocmd BufEnter *.h      setlocal ts=4 sw=4 sts=4 noexpandtab
autocmd BufEnter *.S        setlocal ts=8 sw=8 sts=8 noexpandtab
autocmd BufEnter *.py       setlocal ts=4 sw=4 sts=4 expandtab
autocmd BufEnter Makefile   setlocal ts=8 sw=8 sts=8 noexpandtab
autocmd BufEnter .*         setlocal ts=8 sw=8 sts=8 noexpandtab nocindent
autocmd BufEnter *.dtsi     setlocal ts=8 sw=8 sts=8 noexpandtab nocindent
autocmd BufEnter *.dts      setlocal ts=8 sw=8 sts=8 noexpandtab nocindent
autocmd BufEnter *.md       setlocal ts=8 sw=8 sts=8 noexpandtab nocindent
autocmd BufEnter *.sh       setlocal ts=4 sw=4 sts=4 noexpandtab nocindent
autocmd BufEnter *defconfig setlocal ts=4 sw=4 sts=4 noexpandtab nocindent
autocmd BufEnter *.bb       setlocal ts=4 sw=4 sts=4 noexpandtab nocindent
autocmd BufEnter *.bbclass  setlocal ts=4 sw=4 sts=4 noexpandtab nocindent
autocmd BufEnter *.bbappend setlocal ts=4 sw=4 sts=4 noexpandtab nocindent
autocmd BufEnter *.xml      setlocal ts=8 sw=8 sts=8 noexpandtab nocindent
autocmd BufEnter *.java     setlocal ts=4 sw=4 sts=4 expandtab nocindent
if has("autocmd")
  au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endif

"===== PageUP PageDown
map <PageUp> <C-U><C-U>
map <PageDown> <C-D><C-D>

"===== Resize between split windows
nmap <S-h> <C-W><
nmap <S-j> <C-W>+
nmap <S-k> <C-W>-
nmap <S-l> <C-W>>

"===== Move between split windows
" <C-h> 는 창 이동이 아니라 '찾아 바꾸기'다 (아래 g:vimide_replace_ctrl_h).
" 왼쪽 창으로 가는 길은 <C-w>h 가 그대로 있다.
if !get(g:, 'vimide_replace_ctrl_h', 1)
	map <C-h> :wincmd h<cr>
endif
map <C-l> :wincmd l<cr>
map <C-k> :wincmd k<cr>
map <C-j> :wincmd j<cr>


"===== 버퍼 이동
"
" 곁창에서는 아무 일도 하지 않는다. 이 매핑들은 bang 형태(:bn! :bp! :b!N)라
" winfixbuf 마저 뚫고 들어간다 - RelationView 패널이 이 매핑들에 버퍼를
" 빼앗겨 스스로 되돌리는 코드를 따로 들고 있을 정도였다. 곁창에서 눌러도
" 사이드바가 일반 파일로 바뀌지 않게 여기서 한 번에 막는다.
"
" 주석을 줄 위로 올린 이유: :map 은 줄 끝까지를 통째로 오른쪽 항으로 삼는다.
" 예전에는 `map ,r :bn!<CR>   " Switch to ...` 라서 <CR> 뒤의 글자들이 노멀
" 모드 키로 딸려 들어갔다.
func! s:BufCycle(cmd) abort
	if &buftype !=# ''
		return
	endif
	if has('nvim') && exists('*luaeval')
				\ && !luaeval('_G.vimide_is_edit_win == nil and true or _G.vimide_is_edit_win()')
		return
	endif
	execute a:cmd
endfunc

" <C-^> (대체 버퍼로 전환) 도 같은 자리에서.
"
" 이것만 매핑이 없어서 vim 본래 동작이 그대로 살아 있었다 - 곁창에서 누르면
" 그 사이드바에 대체 파일이 실리고, RelationView 패널에서는 winfixbuf 라
" E1513 만 났다. 숫자를 앞에 붙이는 꼴(3<C-^>)도 그대로 살린다.
func! s:AltBuf() abort
	let l:n = v:count > 0 ? v:count : 0
	if !s:GotoEditSlot(1)
		return
	endif
	try
		execute 'normal! ' . (l:n > 0 ? l:n : '') . "\<C-^>"
	catch /^Vim\%((\a\+)\)\=:E/
		echohl WarningMsg | echo v:exception | echohl None
	endtry
endfunc
nnoremap <silent> <C-^> :<C-u>call <SID>AltBuf()<CR>

" 다음 / 이전 / 지금 버퍼 닫기
" 찾아 바꾸기 - 커서 밑 심볼을 이 파일 안에서 바꾼다
"
"   <C-h>   떠 있는 창 (nvim). Old 를 보여주고 New 를 받는다.
"   ,ch     예전 그대로 :.,$s/<낱말>/ 을 명령줄에 띄운다 (아래 참고).
"           묻는 방식이 필요하면 :VimIdeReplaceCmd
"
" 둘 다 커서 밑 심볼을 Old 에 채워 두되 고칠 수 있다. 빈 곳에서 불렀으면
" Old 가 비어 있고 찾을 말부터 직접 치면 된다.
"
" 그 다음 '한 번에 모두 / 하나씩 Yes,No / 취소' 를 고른다. 하나씩은 vim 의
" :s///gc 그대로다 - y 바꾼다, n 건너뛴다, a 여기서부터 전부, q 그만둔다.
" 어디서든 <Esc>(또는 <C-c>) 는 취소. 바꾸기는 한 번의 :s 라서 u 한 번이면
" 통째로 되돌아온다.
"
" 치는 동안 EDIT 창이 실시간으로 바뀌지 않는다. nvim 의 inccommand 는 기본이
" nosplit 이라 :s 를 치는 사이 화면을 미리 바꿔 버리는데, 그러면 원래 내용이
" 뭐였는지 알 수가 없다. 이 기능이 도는 동안만 꺼 두었다가 되돌린다
" (평소의 :s 미리보기는 그대로 둔다).
"
"   let g:vimide_replace_word = 0     " 낱말 경계로 찾지 않는다
"                                     " (1 이면 struct 가 structure 에 안 걸린다)
"   let g:vimide_replace_ctrl_h = 0   " <C-h> 를 예전처럼 창 왼쪽 이동으로
"                                     " (그래도 ,ch 는 그대로 쓴다)
"   let g:vimide_replace_preview = 1  " 치는 동안 미리보기를 끄지 않는다
"   :VimIdeReplace [찾을말]           " 명령으로도 (떠 있는 창)
"   :VimIdeReplaceCmd [찾을말]        " 명령으로도 (명령행)
let g:vimide_replace_word = 1
let g:vimide_replace_ctrl_h = 1
" 1 (기본) :s 미리보기(nvim 의 inccommand)를 그대로 둔다.
"          0 이면 시작할 때 아예 꺼서 ,ch 로 바꾸는 동안 원래 내용이
"          가려지지 않게 한다.
let g:vimide_replace_preview = 1

" 치는 동안 미리보기를 끈다. 되돌리는 것까지 한 쌍이다.
func! s:ReplaceNoPreview() abort
	if get(g:, 'vimide_replace_preview', 0) || !exists('&inccommand')
		return ''
	endif
	let l:save = &inccommand
	set inccommand=
	return l:save
endfunc
func! s:ReplacePreviewBack(save) abort
	if exists('&inccommand') && type(a:save) == type('') && !empty(a:save)
		let &inccommand = a:save
	endif
endfunc

" 명령행 쪽 (,ch). vim 8.1 에서도 이 길을 쓴다 - 거기엔 떠 있는 창이 없다.
func! s:ReplaceCmd(...) abort
	if &buftype !=# '' || !&modifiable || &readonly
		echohl WarningMsg | echo '여기서는 바꿀 수 없습니다' | echohl None
		return
	endif
	let l:seed = a:0 > 0 && !empty(a:1) ? a:1 : expand('<cword>')
	let l:save = s:ReplaceNoPreview()
	try
		let l:old = ''
		let l:new = ''
		try
			echohl Question
			let l:old = input('찾을 말  Old: ', l:seed)
			if empty(l:old)
				return
			endif
			echo " "
			let l:new = input(printf("바꿀 말  '%s' -> New: ", l:old))
		catch /^Vim:Interrupt$/
			return
		finally
			echohl None
		endtry
		if empty(l:new) || l:new ==# l:old
			return
		endif
		let l:pat = '\V' . escape(l:old, '\/')
		if get(g:, 'vimide_replace_word', 1) && l:old =~# '^\w\+$'
			let l:pat = '\<' . l:pat . '\>'
		endif
		let l:rep = escape(l:new, '\/&~')
		" 몇 곳인지 먼저 세어 보여준다. 없으면 묻지 않는다.
		let l:n = 0
		try
			let l:out = execute('keeppatterns %s/' . l:pat . '//gn')
			let l:n = str2nr(matchstr(l:out, '\d\+'))
		catch
		endtry
		if l:n == 0
			redraw
			echohl WarningMsg | echo printf("'%s' 를 이 파일에서 찾지 못했습니다", l:old) | echohl None
			return
		endif
		redraw
		let l:c = confirm(printf("'%s' -> '%s'   (%d곳)", l:old, l:new, l:n),
					\ "한 번에 모두(&A)\n하나씩 Yes,No(&O)\n취소(&C)", 1)
		if l:c == 1
			execute 'keeppatterns %s/' . l:pat . '/' . l:rep . '/g'
			echo printf("'%s' -> '%s'  %d곳 바꿈", l:old, l:new, l:n)
		elseif l:c == 2
			echohl Question
			echo '바꿀까요?  y 예  n 아니오  a 여기서부터 전부  q 그만'
			echohl None
			execute 'keeppatterns %s/' . l:pat . '/' . l:rep . '/gc'
		endif
	finally
		call s:ReplacePreviewBack(l:save)
	endtry
endfunc
command! -nargs=? VimIdeReplaceCmd call s:ReplaceCmd(<q-args>)

" 떠 있는 창 쪽 (<C-h>). nvim 이 아니면 명령행 길로 떨어진다.
func! s:ReplaceFloat(...) abort
	let l:seed = a:0 > 0 ? a:1 : ''
	if !(has('nvim') && exists('*luaeval'))
		call s:ReplaceCmd(l:seed)
		return
	endif
	let l:save = s:ReplaceNoPreview()
	" 떠 있는 창은 비동기라 여기서 바로 되돌리면 안 된다. 창이 닫힐 때
	" 되돌리도록 한 박자 뒤로 미룬다 - 바꾸기까지 끝나고 나서다.
	call luaeval('_G.vimide_replace ~= nil and (function() _G.vimide_replace(_A) return 1 end)() or 0',
				\ empty(l:seed) ? expand('<cword>') : l:seed)
	if !empty(l:save)
		call timer_start(50, {-> s:ReplacePreviewBack(l:save)})
	endif
endfunc

" ,ch 는 예전 그대로 명령어모드다 (요청).
"
"   ,ch  ->  :.,$s/<커서 밑 낱말>/      여기서 바꿀 말과 플래그를 직접 친다
"
" 물어보는 방식(찾을 말 -> 바꿀 말 -> 한 번에/하나씩)은 <C-h> 에 있다.
" 명령으로도 부를 수 있다: :VimIdeReplaceCmd
"
" 치는 동안 화면이 실시간으로 바뀌는 것(nvim 의 inccommand)에 대하여
"   이 한 자리에서만 껐다 켜려고 CmdlineLeave 로 되돌리는 것을 만들어 봤는데
"   값이 제대로 돌아오지 않았다(실측: Esc 뒤 inccommand 가 빈 채로 남았다).
"   눈에 안 띄게 망가지는 장치를 두느니 손잡이를 하나 두는 편이 낫다.
"   거슬리면 아래 한 줄을 켜면 :s 미리보기가 통째로 꺼진다.
"
"     set inccommand=            " 미리보기 끔 (원래 내용이 안 가려진다)
"     set inccommand=nosplit     " nvim 기본 (치는 대로 미리 보여준다)
if exists('&inccommand') && get(g:, 'vimide_replace_preview', 1) == 0
	set inccommand=
endif
nmap ,ch :.,$s/<C-R>=expand("<cword>")<CR>/
if get(g:, 'vimide_replace_ctrl_h', 1)
	nnoremap <silent> <C-h> :call <SID>ReplaceFloat()<CR>
	" 블록(또는 문자/줄)으로 고른 뒤 <C-h> 면 고른 글자가 Old 로 들어간다.
	" 여러 줄을 골랐으면 첫 줄만 쓴다 - <C-g> 와 같은 규칙이고, 찾아 바꾸기는
	" 한 줄짜리 낱말을 다루는 일이라 그 편이 맞다.
	" :<C-u> 로 범위를 지운다. 안 지우면 함수가 범위를 받아 E481 이 난다.
	xnoremap <silent> <C-h> :<C-u>call <SID>ReplaceFloat(<SID>VisualText())<CR>
endif

map ,r :call <SID>BufCycle('bn!')<CR>
map ,e :call <SID>BufCycle('bp!')<CR>
map ,w :call <SID>BufCycle('bw!')<CR>

" 버퍼 번호로 바로 가기 (,1 ~ ,0)
map ,1 :call <SID>BufCycle('b!1')<CR>
map ,2 :call <SID>BufCycle('b!2')<CR>
map ,3 :call <SID>BufCycle('b!3')<CR>
map ,4 :call <SID>BufCycle('b!4')<CR>
map ,5 :call <SID>BufCycle('b!5')<CR>
map ,6 :call <SID>BufCycle('b!6')<CR>
map ,7 :call <SID>BufCycle('b!7')<CR>
map ,8 :call <SID>BufCycle('b!8')<CR>
map ,9 :call <SID>BufCycle('b!9')<CR>
map ,0 :call <SID>BufCycle('b!0')<CR>


"===== text change
nmap ,H :%s/<C-R>=expand("<cword>")<CR>/
" ,ch 는 위쪽 s:ReplaceCmd() 가 쓴다 - 찾을 말과 바꿀 말을 차례로 묻고
" '한 번에 모두 / 하나씩 / 취소' 를 고르게 한다. 예전 매핑은 남겨 둔다:
"nmap ,ch :.,$s/<C-R>=expand("<cword>")<CR>/

"===== make bootloader
let startbootdir = getcwd()
func Make1()
	exe "!cd ".startbootdir
	"exe "make tcc8920_evm_emmc -j8"
	exe "make"
endfunc
nmap ,mb :call Make1()<cr><cr>

"===== make kernel
let startkerneldir = getcwd()
func! Make()
	exe "!cd ".startkerneldir
	"exe "make -j12"
	"exe "make -j12;./tcc_mkrd.sh"
	"exe "make -j12;./tcc_initramfs_compress.sh"
	exe "!./mkall.sh -j12 ramdisk"
endfunc
nmap ,mk :call Make()<cr><cr>

"===== hexViewer
let b:hexViewer = 0
func! Hv()
        if (b:hexViewer == 0)
                let b:hexViewer = 1
                exe "%!xxd"
        else
                let b:hexViewer = 0
                exe "%!xxd -r"
        endif
endfunc
nmap ,hex :call Hv()<cr>

"==============================================================================
"= Project config
"==============================================================================
if filereadable(".project.vimrc")
	source .project.vimrc
endif

"==============================================================================
"= NERD Tree
"==============================================================================
"let g:NERDTreeWinPos="right"
let g:NERDTreeWinPos="left"
let g:NERDTreeWinSize=50
let g:NERDTreeDirArrows=0
let g:NERDTreeShowIcons = 1
"let g:NERDTreeDirArrowExpandable = '→'
"let g:NERDTreeDirArrowCollapsible = '▼'
function! AutoLoadNERDTree()
	if exists(':NERDTree') != 2
		return
	endif
	exe 'NERDTree'
endfunction
"autocmd VimEnter * call AutoLoadNERDTree()

"==============================================================================
"= Tagbar
"==============================================================================

"------------------------------------------------------------------------------
"- Tagbar 는 Universal Ctags 를 쓴다. Exuberant Ctags 5.8(2009) 은 C11 익명
"- 구조체/최신 kind 를 제대로 못 읽는다. install.sh 가 설치해 준다:
"-   mac    : brew install universal-ctags (구 ctags 포뮬러는 unlink)
"-   ubuntu : /usr/bin/ctags 가 이미 Universal 이거나 ~/.local 에 소스 빌드
"- 아래 순서대로 처음 찾은 것을 쓴다(직접 지정하려면 g:tagbar_ctags_bin 설정).
"------------------------------------------------------------------------------
if !exists('g:tagbar_ctags_bin')
	for s:ctags_cand in [$HOME . '/.local/bin/ctags', 'uctags', 'ctags']
		if executable(s:ctags_cand)
			let g:tagbar_ctags_bin = s:ctags_cand
			break
		endif
	endfor
	unlet! s:ctags_cand
endif
" gutentags 도 같은 바이너리를 쓴다(설정 블록이 이 위에 있어 여기서 넘긴다)
if exists('g:tagbar_ctags_bin')
	let g:gutentags_ctags_executable = g:tagbar_ctags_bin
	" 저장할 때마다 도는 ctags 는 양보하게 한다. 개발서버는 60코어에
	" 841 로그인이고, 그 ctags 가 에디터와 같은 우선순위로 CPU/IO 를
	" 다투면 타자가 걸린다. ctags-nice 는 우선순위만 바꾸고 인자는 그대로
	" 넘긴다(CTAGS_NICE=0 으로 끄고, CTAGS_REAL 로 실제 바이너리를 준다).
	" GTAGS 쪽은 autoindex.lua 의 spawn() 이 같은 정책을 쓴다.
	if executable(expand('~/.local/bin/ctags-nice'))
		let $CTAGS_REAL = g:tagbar_ctags_bin
		let g:gutentags_ctags_executable = expand('~/.local/bin/ctags-nice')
	endif
endif
"let g:tagbar_left=0
let g:tagbar_left=1
let g:tagbar_sort=0

" ------------------------------------
" tagbar: 아웃라인에서 #define 을 뺀다
" ------------------------------------
" tagbar 는 버퍼를 열 때마다 ctags 를 돌리고 그 출력을 vimscript 로 파싱해
" 트리를 만든다. ctags 자체는 싸다 - 3000줄 C 파일에 27ms. 비싼 것은
" 그다음이다: 같은 파일에서 tagbar 가 1538ms 를 썼다(맥 기준, 서버는
" 6399ms). 태그 하나당 0.5ms 쯤이라 태그 수에 그대로 비례한다.
"
" 이 트리의 하드웨어 헤더가 정확히 그 경우다:
"   kernel/common/sound/soc/telechips_dpcm/tcc_maic_hw.h
"   2313줄, 태그 1016개 - 그중 945개가 #define 이다.
" 945줄짜리 매크로 목록은 아웃라인으로 훑을 수 있는 것이 아니고, 매크로는
" \fs(gtags)로 즉시 찾힌다. 그래서 아웃라인에서는 뺀다 - 남는 71개가
" 실제로 이 파일을 돌아다닐 때 쓰는 것들이다.
"
"   let g:vimide_tagbar_macros = 1   " 매크로도 아웃라인에 넣기(예전 동작)
if !get(g:, 'vimide_tagbar_macros', 0)
	let s:tagbar_c_kinds = [
				\ 'h:header files:1:0',
				\ 'p:prototypes:1:0',
				\ 'g:enums:0:1',
				\ 'e:enumerators:0:0',
				\ 't:typedefs:0:0',
				\ 's:structs:0:1',
				\ 'u:unions:0:1',
				\ 'm:members:0:0',
				\ 'v:variables:0:0',
				\ 'f:functions:0:1',
				\ ]
	let g:tagbar_type_c = {
				\ 'ctagstype' : 'c',
				\ 'kinds'     : s:tagbar_c_kinds,
				\ 'sro'       : '::',
				\ 'kind2scope': {'g': 'enum', 's': 'struct', 'u': 'union'},
				\ 'scope2kind': {'enum': 'g', 'struct': 's', 'union': 'u'},
				\ }
	let g:tagbar_type_cpp = {
				\ 'ctagstype' : 'c++',
				\ 'kinds'     : s:tagbar_c_kinds + [
				\   'c:classes:0:1', 'n:namespaces:0:1' ],
				\ 'sro'       : '::',
				\ 'kind2scope': {'g': 'enum', 's': 'struct', 'u': 'union',
				\                'c': 'class', 'n': 'namespace'},
				\ 'scope2kind': {'enum': 'g', 'struct': 's', 'union': 'u',
				\                'class': 'c', 'namespace': 'n'},
				\ }
	unlet s:tagbar_c_kinds
endif
" 그래도 태그가 터무니없이 많은 파일이 있을 수 있다. 바이트로 마지막
" 안전선을 둔다 - 넘으면 그 버퍼의 아웃라인만 비고(:TagbarForceUpdate 로
" 직접 만들 수 있다), 파일 열기는 막히지 않는다.
let g:tagbar_file_size_limit = get(g:, 'tagbar_file_size_limit', 1024 * 1024)
"let g:tagbar_width=30
" 시작할 때 여는 심볼 아웃라인. F10 과 같은 것을 연다(기본 aerial).
" 이름은 예전 그대로 둔다 - 다른 곳에서 부르고 있을 수 있다.
function! AutoLoadTagbar()
	if get(g:, 'vimide_outline', 'aerial') ==# 'tagbar' || !exists(':AerialOpen')
		exe 'Tagbar'
		return
	endif
	" aerial 은 이제 스스로 뜨지 않는다 - F10 으로만 연다 (위 setup 참고).
	" 시작할 때부터 열어 두고 싶으면 g:vimide_outline_startup = 1.
	"
	" VimEnter 시점에는 버퍼도 treesitter 도 아직이라 지금 열면 빈 창만
	" 생긴다. 그래서 조금 미뤄서 연다.
	if get(g:, 'vimide_outline_startup', 0)
		call timer_start(200, { -> execute('silent! AerialOpen') })
	endif
endfunction
autocmd VimEnter * call AutoLoadTagbar()

"------------------------------------------------------------------------------
"- Tagbar: 커서가 심볼 위로 가면 EDIT 창이 그 심볼로 점프한다
"- j/k, 방향키, 마우스 클릭으로 태그 줄에 커서가 놓이면 편집 창이 해당 심볼로
"- 이동하고 포커스는 Tagbar 에 남는다(Tagbar 자체의 'preview' 매핑 재사용).
"- <CR> / 더블클릭은 기존처럼 점프 + 포커스 이동.
"- 'functions', '[members]' 같은 종류 헤더에서는 아무것도 하지 않는다
"- (그 줄에서 preview 를 누르면 폴드가 접히기 때문).
"- 끄려면: let g:tagbar_follow_cursor = 0
"------------------------------------------------------------------------------
let g:tagbar_follow_cursor = 1

" 커서가 놓인 줄이 실제 태그인지 판별한다. 이름 첫 글자의 구문 그룹이
" TagbarKind/NestedKind/Help 면 태그가 아니라 헤더다(Tagbar 의 syntax 규칙).
function! s:TagbarLineIsTag() abort
	let l:line = getline('.')
	if l:line =~# '^\s*$' || l:line =~# '^"' || l:line =~# '^\s*\[.*\]$'
		return 0
	endif
	let l:col = match(l:line, '[[:alnum:]_~]') + 1
	if l:col <= 0
		return 0
	endif
	let l:grp = synIDattr(synID(line('.'), l:col, 1), 'name')
	return l:grp !~# '^Tagbar\%(Kind\|NestedKind\|Help\)'
endfunction

function! s:TagbarFollowCursor() abort
	if !get(g:, 'tagbar_follow_cursor', 1) || get(s:, 'tagbar_following', 0)
		return
	endif
	" 사용자가 실제로 Tagbar 창에 들어와 있을 때만 (win_execute 로 Tagbar
	" 커서를 옮기는 하이라이트 갱신에 반응하면 편집 커서가 끌려간다)
	if !get(s:, 'tagbar_focused', 0) || bufname('%') !~# '^__Tagbar__'
		return
	endif
	if !s:TagbarLineIsTag() || get(s:, 'tagbar_follow_line', -1) == line('.')
		return
	endif
	let s:tagbar_follow_line = line('.')
	let l:key = get(g:, 'tagbar_map_preview', 'p')
	if type(l:key) == type([])
		let l:key = empty(l:key) ? 'p' : l:key[0]
	endif
	let s:tagbar_following = 1
	try
		execute 'normal ' . l:key
	catch
	finally
		let s:tagbar_following = 0
	endtry
endfunction

augroup TagbarFollowCursor
	autocmd!
	autocmd WinEnter __Tagbar__.* let s:tagbar_focused = 1
	autocmd WinLeave __Tagbar__.* let s:tagbar_focused = 0
	autocmd CursorMoved __Tagbar__.* call s:TagbarFollowCursor()
augroup END

"==============================================================================
"= CtrlP
"==============================================================================
let g:ctrlp_map = ',cp'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_working_path_mode = 'ra'
set wildignore+=*/tmp/*,*.so,*.swp,*.zip     " MacOSX/Linux
set wildignore+=*\\tmp\\*,*.swp,*.zip,*.exe  " Windows
let g:ctrlp_custom_ignore = '\v[\/]\.(git|hg|svn)$'
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\v[\/]\.(git|hg|svn)$',
  \ 'file': '\v\.(exe|pyc|so|dll)$',
  \ 'link': 'some_bad_symbolic_links',
  \ }
"let g:ctrlp_user_command = 'find %s -type f'        " MacOSX/Linux
"let g:ctrlp_user_command = 'dir %s /-n /b /s /a-d'  " Windows
let g:ctrlp_user_command = ['.git/', 'git --git-dir=%s/.git ls-files -oc --exclude-standard']       "Ignore in .gitignore
"let g:ctrlp_max_files = 10000
"let g:ctrlp_max_depth = 30
"let g:ctrlp_follow_symlinks = 1
"let g:ctrlp_use_readdir = 0
"let g:ctrlp_root_markers = ['ctrlp-marker']


"==============================================================================
"= minibufexpl
"==============================================================================
let g:miniBufExplMapWindowNavVim = 1
let g:miniBufExplMapWindowNavArrows = 1
let g:miniBufExplMapCTabSwitchBufs = 1
let g:miniBufExplModSelTarget = 1

"==============================================================================
"= cscope, ctags
"==============================================================================
function! LoadCscope()
  exe "silent cs reset"
  let db = findfile("cscope.out", ".;")
  if (!empty(db))
    let path = strpart(db, 0, match(db, "/cscope.out$"))
    set nocscopeverbose " suppress 'duplicate connection' error
    exe "cs add " . db . " " . path
    set cscopeverbose
  endif
endfunction
if has('cscope.out')
  au BufEnter /* call LoadCscope()
endif

set tags=tags;/


"==============================================================================
"= Check Symbol
"==============================================================================
source ${HOME}/.vim/plugin/checksymbol.vim

" C-c : RelationView 가 PINNED 면 해제하고(다시 커서를 따라간다), 그렇지
"       않으면 원래대로 checksymbol.vim 의 CONFIG 조회를 그대로 한다.
"       (checksymbol.vim 이 <C-c> 를 가져가므로 source 뒤에 다시 건다)
func! s:RvUnpin() abort
	if has('nvim') && exists('*luaeval')
		try
			if luaeval('_G.relationview_unpin ~= nil and _G.relationview_unpin() or false')
				return
			endif
		catch
			call s:LuaOops()
		endtry
	endif
	if exists('*CheckSymbol')
		call CheckSymbol(expand('<cword>'))
	endif
endfunc
" checksymbol.vim 은 ~/.vim/plugin/ 에 있어 vimrc 가 끝난 뒤 한 번 더
" 로드되며 <C-c> 를 다시 가져간다. 그래서 VimEnter 에서 건다.
augroup RvUnpinKey
	autocmd!
	autocmd VimEnter * nnoremap <silent> <C-c> :call <SID>RvUnpin()<CR>
augroup END


"==============================================================================
"= OverView: Source Insight style Overview (nvim only)
"  \b toggle / :OverView - see ~/.vim/plugin/overview.lua
"==============================================================================
let g:overview_smooth = 0        " 즉시 도착 (예전 동작)
let g:overview_smooth_step = 0.3 " 더 천천히 (기본 0.5)

"==============================================================================
"= RelationView: Source Insight style relation window (nvim only)
"  F3 toggle / :RelationView - see ~/.vim/plugin/relationview.lua
"==============================================================================
if has('nvim') && filereadable(expand('$HOME/.vim/plugin/relationview.lua'))
    execute 'source' fnameescape(expand('$HOME/.vim/plugin/relationview.lua'))
endif

" g:relationview_position   'bottom' (default) or 'right'
"   'bottom' 이면 화면 아래에 가로로 붙고, context view 는 그 안에서
"   오른쪽 절반을 차지한다(g:relationview_context_width, 0 = 절반).
let g:relationview_position = 'right'
" g:relationview_auto_open  1: open the panel on startup (default 1)
"
" 0 으로 둔다: vim 을 켜면 아무것도 열지 않고, F3 을 눌러야 열린다.
" 예전에는 context(미리보기)가 켜진 채로 시작했다.
"
" 닫힌 상태에서 F3 을 처음 누르면 순서의 첫 칸인 'both'(패널+미리보기)가
" 열린다. 예전처럼 미리보기부터 보고 싶으면 순서를 바꾸면 된다:
"   let g:relationview_cycle = ['context', 'both', 'relation', 'off']
"   let g:relationview_cycle = ['context', 'off']   " 미리보기만 켜고 끄기
let g:relationview_auto_open = 0
let g:relationview_height = 16
" 경로는 프로젝트 루트 기준의 전체 상대 경로로.
"   'root' (기본) 이 트리를 질의한 GTAGS 루트 기준 - 어느 디렉터리에서
"                 vim 을 켜든 같은 파일이 늘 같은 경로로 보인다
"   'pwd'         :pwd 기준 (켠 위치에 따라 달라진다)
"   'abs'         절대 경로
let g:relationview_path_base = 'root'

" quickfix 창의 경로를 무엇 기준으로 보여줄지 (qfpath.lua, nvim 전용)
"
"   'root' (기본) 프로젝트 루트 기준.  drivers/char/tcc_ecid.c|80| ...
"   'pwd'         :pwd 기준
"   'abs'         손대지 않는다 (예전 동작, 절대 경로 그대로)
"
" 기준이 되는 루트는 위 relationview_path_base 와 같은 것을 쓴다 - 색인이
" 있는 가장 바깥 디렉터리다. 그래야 패널과 quickfix 에서 같은 파일이 같은
" 이름으로 보인다. 루트 밖의 파일은 줄이지 않고 절대 경로로 둔다
" (../../.. 로 줄이면 절대 경로보다 읽기 나쁘다).
"
"   :VimIdeQfPath root|pwd|abs    지금 바로 바꿔 보기
let g:vimide_qf_path = 'root'
let g:relationview_full_path = 0
let g:relationview_startup = 'both'
"let g:relationview_cycle = ['context', 'off']          " 미리보기만 켜고 끄기
let g:relationview_cycle = ['both', 'off']             " 통째로 켜고 끄기
"let g:relationview_cycle = ['relation', 'context']     " 둘을 오간다
"let g:relationview_cycle = ['context', 'both', 'off']  " 셋만
" context view 는 패널 안이 아니라 편집 창 오른쪽에 따로 띄운다
"   -> RelationView 는 아래 전체 폭, ContextView 는 오른쪽 세로 한 칸
let g:relationview_context_position = 'right'
let g:relationview_context_width = 80
" 아래 둘은 'right' 배치에서만 쓰인다(되돌릴 때를 위해 남겨둔다)
let g:relationview_width = 80
let g:relationview_context_height = 60
" 리스트에 소스 코드 열까지 보여준다(심볼 | 파일경로 | 그 줄의 내용).
" 패널이 화면 아래 전체 폭을 쓰므로 세 열이 들어간다.
let g:relationview_show_text = 1
" 관계 방향. 패널 안에서 d 로 돌려 가며 볼 수 있고, 여기 값이 기본값이다.
"   'both'    Callers 트리 + Calls 평면 목록을 한 화면에 (기본)
"   'callers' 누가 부르나만, 확장 가능한 트리로
"   'callees' 무엇을 부르나만, 확장 가능한 트리로
" 'both' 의 Calls 목록은 점프는 되지만 펼쳐지지는 않는다. 펼치려면 d 를
" 눌러 그 방향을 트리로 바꾼다(<Leader><Leader>d 로 바로 갈 수도 있다).
let g:relationview_relation = 'callers'
" 'both' 의 두 번째 목록에 보여 줄 최대 줄 수
let g:relationview_max_extra = 40
" struct/union/enum 을 고르면 멤버를 전부 나열할지. 커널 구조체는 멤버가
" 수십 개라 그 목록만으로 패널이 가득 차서 기본은 꺼 둔다. 1 로 되살린다.
" (꺼져 있어도, 특정 멤버나 enum 상수를 골라 들어온 경우 그 한 줄은 남는다)
let g:relationview_members = 0
" 리스트를 훑으면 PINNED 로 고정되고, 소스 창에서 한 심볼에 이만큼
" 머무르면 고정이 풀리며 다시 커서를 따라간다
let g:relationview_unpin_delay = 2000

" ------------------------------------
" 오른쪽 열 구성 (relationview.lua)
"
"   g:relationview_position = 'right' 이면 오른쪽 한 열(width 만큼)을 셋으로
"   나눈다. 위에서부터 neo-tree / 관계 목록 / 미리보기다.
"
"     +--------+--------+-----------+
"     |        |        | neo-tree  |   t  (또는 \n)
"     |  EDIT  |  big   +-----------+
"     |        |  (T)   | relation  |
"     |        |        +-----------+
"     |        |        | context   |   c
"     +--------+--------+-----------+
"
"   'T' (또는 \b) 는 그 열 왼쪽에 세로 전체 높이로 미리보기를 하나 더 연다.
"   아래쪽 작은 미리보기와 같은 자리를 보여 주는 '넓게 읽는 창'이고, 둘은
"   따로 켜고 끈다.
"
"   position = 'bottom' (지금 설정) 이면 관계 목록이 아래를 통째로 쓰고,
"   오른쪽에는 neo-tree(위) 와 미리보기(아래)만 선다.
let g:relationview_tree = 1
let g:relationview_tree_height = 12
let g:relationview_tree_dir = 'root'
" 편집 창에서 파일을 잡으면 그 파일이 있는 경로까지 트리를 펼쳐 준다
" (NERDTreeFind 과 같은 동작). 0 이면 따라가지 않는다.
let g:relationview_tree_follow = 1
" 파일 사이를 빠르게 옮겨 다닐 때 트리를 매번 다시 그리지 않는다 (ms)
let g:relationview_tree_follow_delay = 200
" 뿌리 밖의 파일을 잡았을 때 트리 뿌리까지 그 파일 쪽으로 옮길지.
" 기본 0 = 가만둔다. neo-tree 는 1 일 때 뿌리를 그 파일의 상위로 바꾼다.
let g:relationview_tree_follow_cwd = 0
" 오른쪽 열 세 창의 높이를 12등분했을 때의 몫.
"   neo-tree(2) / 관계 목록(4) / 미리보기(6)
" 셋 중 일부만 열려 있으면 열린 것들끼리 같은 비율로 나눈다.
" 빈 목록([])으로 두면 예전 방식(아래 고정 줄수)을 쓴다.
let g:relationview_column_ratio = [2, 4, 6]
" 위 비율을 안 쓸 때만 의미가 있다: 관계 목록에 최소 이만큼은 남기고
" 나머지를 미리보기에 준다.
let g:relationview_list_min_height = 12
let g:relationview_right_stack = 1
let g:relationview_big_width = 0
" 'w' (또는 \lw) 를 누를 때마다 도는 단계. 화면의 몇 %까지 넓힐지.
"   1/2 -> 3/4 -> 기본 크기 -> (다시 1/2)
" 예전 기본은 [33, 50, 67] 이었다. 세 단계는 한 바퀴가 길어서 둘로 줄였다.
let g:relationview_wide_steps = [50, 75]
" 칸수를 박아 두면 위 단계 대신 그 한 단계만 돈다(기본 0 = 단계를 쓴다).
let g:relationview_wide_width = 0

" F9 의 왼쪽 neo-tree 도 'w' 로 폭을 넓혔다 줄인다.
"
" 트리 창 안에서 'w' 를 누를 때마다 도는 단계(화면 폭의 %).
" 마지막 단계에서 한 번 더 누르면 처음 폭(window.width, 32칸)으로 돌아온다.
" 다른 곁창(aerial, RelationView 패널)의 폭은 건드리지 않는다 - 늘어난
" 만큼은 EDIT 창이 낸다. RelationView 의 'w' 와 같은 규칙이다.
"
"   let g:neotree_wide_steps = [20, 35, 50]   " 세 단계로
"   let g:neotree_wide_steps = []             " 이 기능을 쓰지 않는다
"
" neo-tree 기본에서 'w' 는 open_with_window_picker 다. 이 설정은 창
" 고르개를 쓰지 않으므로(파일은 늘 직전 EDIT 창에 연다) 그 자리를 쓴다.
let g:neotree_wide_steps = [25, 40]
" 1 (기본) <C-n>/<C-p> 로 목록을 옮길 때 그 자리를 보여주는 창으로 커서까지 간다.
"          0 이면 미리보기만 하고 커서는 그대로 (엿보기용 <C-0>/<C-9> 와 같아진다).
let g:relationview_step_focus = 1
" 1 (기본) <C-g> 의 grep 을 낱말 경계로 찾는다(struct 가 structure 에 안 걸린다).
let g:relationview_grep_word = 1
" 1 (기본) <C-g> 로 찾을 말을 정한 뒤, 찾을 경로를 한 번 더 보여준다.
"          기본값은 지금 파일이 있는 디렉터리. <Tab> 으로 완성할 수 있고,
"          비우거나 Esc 면 그만둔다. 0 이면 묻지 않고 그 디렉터리에서 찾는다.
let g:relationview_grep_ask_dir = 1
" 0 (기본) rg 가 숨은 디렉터리와 .gitignore 에 걸린 곳을 건너뛴다.
"
"          소스를 읽을 때는 이편이 낫다 - 커널 트리에서 .gitignore 에 든
"          빌드 산출물(*.o, *.cmd, 생성 헤더)까지 나오면 결과가 파묻힌다.
"          1 로 두면 rg 에 --hidden --no-ignore 를 붙여 전부 뒤진다
"          (그러면 rg 가 없을 때의 grep 갈래와 결과가 더 가까워진다).
let g:relationview_grep_hidden = 0
" 1000 (기본) <C-g> 의 grep 이 이 줄 수를 넘으면 거기서 끊는다.
"            커널 트리에서 흔한 낱말 하나가 수만 줄이 되는 것을 막는다.
let g:relationview_grep_max = 1000
" 20 (기본) 넓힐 때 편집 영역에 최소한 남겨 둘 칸수. 0 이면 안 지킨다.
"
"           곁창(aerial, quickfix ...)은 'w' 로 크기가 바뀌지 않는다. 그
"           몫을 편집 창이 전부 떠안으므로, 단계를 크게 잡으면 편집 창이
"           쓸 수 없게 눌린다(실측 178칸, aerial 35칸, 75% 단계: 편집 창이
"           8칸). 그만큼 패널을 도로 물려서 이 칸수는 지킨다.
"           'bottom' 배치에서는 줄수로 읽고 기본값은 5 다.
let g:relationview_wide_min_edit = 20
" 'bottom' 배치에서 같은 뜻의 줄수.
let g:relationview_wide_height = 0

" ------------------------------------
" 점프 / 검색 결과를 어디에 보여 줄까
"
" (여기서 쓰는 매핑 관련 옵션 - g:vimide_jump_mark, g:vimide_edit_jump_fkey,
"  g:vimide_rvlist_next_key/prev_key - 는 이 파일 앞쪽 '점프 키' 절에 있다.
"  .vimrc 안에서 매핑을 걸 때 읽으므로 그 줄보다 앞에 있어야 한다.)
"
" Ctrl+/ (글자 찾기) 와 \c (caller 찾기) 는 릴레이션 패널이 떠 있으면
" 패널에, 닫혀 있으면 quickfix 에 싣는다. 0 으로 두면 늘 quickfix 다
" (보고 있던 관계 트리가 검색 결과로 덮이지 않는다).
let g:relationview_lookup_panel = 1

" ------------------------------------
" 창 규칙 (vimidewin.lua)
"
" 1 (기본) 곁창(패널/aerial/quickfix/neo-tree/NERDTree ...)에 파일이 실리면
"          그 파일을 '직전에 보던 EDIT 창'으로 옮기고 곁창을 되돌린다.
let g:vimide_win_guard = 1
" 1 (기본) 곁창만 남고 EDIT 창이 0개가 되면 vim 을 끝낸다.
"          저장 안 한 버퍼나 돌아가는 터미널이 있으면 끝내지 않는다.
let g:vimide_min_edit_win = 1
" 1 (기본) 패널/aerial/tagbar 등을 켜고 끌 때 EDIT 창 크기를 고르게 맞춘다.
let g:vimide_balance_on_toggle = 1
" 8 (기본) 곁창이 이 칸수 이하로 뭉개지면 원래 폭으로 되돌린다. 0 이면 끈다.
"
"          winfixwidth 는 '균등 분할이 이 폭을 건드리지 말라' 는 뜻이지,
"          이미 줄어든 것을 되돌려 주지는 않는다. 그래서 :e . 한 번이면
"          (NERDTree 가 디렉터리를 가로채며 자리를 빼앗는다) aerial 이
"          35칸에서 1칸이 된 채 :wincmd = 로도 안 돌아왔다.
"          조금 줄어든 것은 건드리지 않는다 - RelationView 의 w(wide)
"          토글이 일부러 줄이는 폭이 그 위(실측: 35 -> 43 -> 31 -> 20)다.
let g:vimide_side_min_width = 8

" 0 (기본) 초점이 어느 창으로 왜 옮겨 갔는지 적어 둘지.
"
"          '커서가 다른 창으로 갔다가 돌아온다' 처럼 가끔 나는 일을 잡을 때
"          켠다. 창이 바뀔 때마다 어디서 어디로, 그리고 그것을 부른 lua
"          스택을 남긴다 - 스택이 비면 사람이 옮긴 것이다. 메모리에만
"          쌓이고 마지막 g:vimide_focus_log_max 줄만 남는다.
"            :VimIdeFocusLog     적힌 것을 아래 창에 펼친다
"            :VimIdeFocusLog!    지우고 다시 시작한다
let g:vimide_focus_log = 0
let g:vimide_focus_log_max = 400

" ------------------------------------
" 마우스를 매핑으로 가로챌지 (터미널에 따라 탈이 날 수 있는 자리다)
"
" 1 (기본) 편집 창에서도 패널 목록의 [+]/[-] 를 한 번 클릭으로 펼친다.
"          패널이 떠 있는 동안에만 매핑을 건다.
let g:relationview_global_mouse = 1
" 1 (기본) overview 막대를 마우스로 끌어 화면을 옮긴다.
let g:overview_mouse = 1
" 마우스가 이상하면 이 둘을 0 으로 두고 :VimIdeMouseCheck / :VimIdeMouseOff 로 가른다.

" ------------------------------------
" 곁창에서 시작하면 안 되는 명령
"
" '지금 창'을 차지하는 기능(F6 BufExplorer, :Ex netrw, :e . ...)은 곁창에서
" 부르면 그 사이드바를 차지해 버린다. 그래서 먼저 직전 EDIT 창으로 옮긴 뒤
" 연다. 다른 명령도 그렇게 돌리고 싶으면:
"   :VimIdeInEdit <명령>
"
" 1 (기본) :only / <C-w>o 가 곁창은 그대로 두고 편집 창만 하나로 합친다.
"          :only! 은 늘 예전대로 모든 창을 닫는다.
let g:vimide_only_keeps_sides = 1
" 1 (기본) 곁창에서 친 아래 명령을 EDIT 창으로 옮겨서 실행한다.
"            :e :ene :find :view :sview :sfind :diffsplit
"            :b :bn :bp :sb :bd :bw  :h :tag :tjump :tselect :pop :tn :tp
"            :cn :cp :cc :cfirst :clast :lne :lp :ll  :next :previous
"            :terminal :Man :BufExplorer
"          <C-^>(대체 버퍼)
"          마우스 뒤로/앞으로 버튼과 <C-t>(되돌아가기)도 같이 따른다.
"          EDIT 창에서 친 것은 손대지 않는다 - 글자 하나 안 바뀐다.
" 0        곁창에서도 그대로 실행한다 (예전 그대로).
" <F6> 과 :Ex :Vex :Sex :Hex :Tex :Lex 는 이 값과 상관없이 늘 EDIT 창으로 간다.
let g:vimide_edit_route = 1

" 패널 밖에서도 쓰도록 전역 단축키를 준다. 패널 안에서는 t / T 다.
" (F1~F12 는 이미 전부 쓰고 있어서 <Leader> 를 쓴다. Leader 는 '\' 다)
" 'l' = layout. \n 은 vim-mark 가, \t 는 neo-tree 가 이미 쓰고 있어서
" 한 글자짜리는 남는 게 없다 - 실제로 \n 을 뺏었더니 vim-mark 가
" E227 로 자기 매핑을 못 걸었다.
" <Cmd> 는 vim 8.2 부터라 nvim 에서만 건다 (서버의 vim 8.1 이 이 파일을
" 그대로 읽는다). 명령 자체도 relationview.lua 가 만드는 것이라 nvim 전용이다.
if has('nvim')
    nnoremap <silent> <Leader>lt <Cmd>RelationViewTree<CR>
    nnoremap <silent> <Leader>lc <Cmd>RelationViewBigContext<CR>
    nnoremap <silent> <Leader>lw <Cmd>RelationViewWide<CR>
endif

" ------------------------------------
" Project files view (projectfiles.lua): 무엇을 색인할지 고르는 창
"   전부 telescope 픽커로 동작한다:
"     <leader>fo  색인된 파일 찾아 열기   (^a 추가, ^d 목록에서 제거)
"     <leader>fp  추가할 파일 고르기      (<Tab> 여러 개)
"     <leader>fd  추가할 디렉터리 고르기  (그 아래 전부)
"     <leader>fx  등록 항목 제거
"     <leader>fm  preset 선택/전환        (^d 내 사본 삭제, auto 포함)
"     <leader>fM  preset 가져오기        (새 SDK 로 목록을 옮긴다)
"                 [vim-ide]=저장소 공용본, [내 사본 ≠ vim-ide]=여기서 고쳐 갈라진 것
"     <leader>fS  지금 목록을 preset 으로 저장
"     <leader>fR  지금 목록으로 재색인
"     <leader>fs  색인된 심볼 검색 (<F3> 또는 ^g 로 relation window 로 넘김)
"                 <F7> 로도 같은 것을 연다
"     <leader>fw  커서 밑 심볼로 바로 검색
"     <leader>fk  북마크(mark) 목록      (ma..mz 로 표시, 'a 로 이동)
"   :ProjectFilesPresetShare <name>
"     preset 을 vim-ide 저장소(.vim/presets)에 넣는다. 커밋/푸시하면
"     다른 장비(리눅스)에서 git pull 만으로 같은 preset 을 쓴다.
"   auto 모드   = 프로젝트 전체(지금까지와 같음)
"   preset 모드 = 고른 파일/디렉터리만 색인
"   파일을 추가하면 그 파일이 쓰는 헤더와 심볼 정의 파일도 함께 들어간다
"   (g:projectfiles_expand = 0 으로 끄고, _expand_max 로 개수를 정한다).
"   추가·제거·전환은 곧바로 재색인되고, preset 밖 파일은 저장해도 색인에
"   들어가지 않는다. 목록은 <root>/.tags/files 로 떨어지고 gtags·ctags 가
"   같은 목록을 쓴다.
" 프로젝트에 지정된 preset 이 없을 때 쓸 기본값:
"   let g:projectfiles_preset = 'kernel-audio'
"
" 하위에서 만든 목록을 SDK 루트 목록으로 자동으로 가져온다.
"
" SDK 루트에서 fuzzy find 를 걸면 멈추다시피 느리다. 그래서 실제로는
" kernel/common 같은 하위에서 목록을 만들게 되는데, 그렇게 담은 항목은
" '그 루트 기준' 상대 경로로 적힌다 - SDK 루트에서 보면 그 경로가 없으니
" 색인에서 통째로 빠진다. 실측(tsnd SDK): 두 루트가 같은 preset 을 나눠
" 쓰는데 루트의 .tags/files 는 6줄, kernel/common 것은 257줄이었다.
" :ProjectFilesAbsorb 가 그 목록을 이 루트 기준으로 바꿔 '없던 것만'
" 더한다(빼지 않는다). 이 줄은 그것을 프로젝트를 처음 열 때 자동으로 한다.
"   let g:projectfiles_absorb = 0        " 알림만 하고 :ProjectFilesAbsorb 로
"   let g:projectfiles_absorb_hint = 0   " 알림도 끄기
"   let g:projectfiles_absorb_whole = 1  " 목록이 없는(auto) 하위도 통째로
let g:projectfiles_absorb = 1
" ------------------------------------
nnoremap <silent> <leader>fo :ProjectFilesFind<CR>
" F3 도 같은 것을 연다. RelationView 를 F12 로 옮기면서 비었다.
nnoremap <silent> <F3> :ProjectFilesFind<CR>
nnoremap <silent> <leader>fp :ProjectFilesAdd<CR>
nnoremap <silent> <leader>fd :ProjectFilesAddDir<CR>
nnoremap <silent> <leader>fx :ProjectFilesRemove<CR>
nnoremap <silent> <leader>fm :ProjectFilesPreset<CR>
" 새 SDK 를 받았을 때: 다른 프로젝트의 preset 목록을 이 트리로 가져온다.
"
" preset 은 프로젝트 상대 경로 목록이라 그대로 쓸 수 있고, 색인은 이 트리의
" 경로로 새로 만들어진다. \fm 과 다른 점은 고르기 전에 '그 목록 중 몇 개가
" 이 트리에 실제로 있나'를 보여준다는 것이다 - 다른 체크아웃의 preset 을
" 걸면 없는 경로는 조용히 빠지는데(실측: 246항목 중 101개), 그 수를 모르면
" 색인이 왜 작은지 알 수가 없다. 고른 뒤에는 공유할지(두 프로젝트가 같은
" 파일을 본다) 새 이름으로 복사할지 묻는다.
"
"   :ProjectFilesImport [이름]
" (\fi 는 Telescope git_commits 가 쓰고 있어서 \fm 옆자리인 \fM 이다)
nnoremap <silent> <leader>fM :ProjectFilesImport<CR>

" 북마크: 찍어 둔 마크를 텔레스코프로 골라서 그 자리로 (marksjump.lua)
"
"   <C-m>          마크 목록.  <CR> 가기,  d 지우기
"   :VimIdeMarks   같은 것
"
" 대문자(mA)로 찍으면 파일을 넘나들고, 소문자(ma)는 그 파일 안에서만이다.
" 0-9 와 ' " ^ . 같은 자동 표시는 뺀다. 특히 0-9 는 '최근에 닫은 파일'이라
" 이 설정에서는 .tags/files 같은 색인 내부 파일이 올라온다
" (g:vimide_marks_auto = 1 이면 같이 보여준다).
"
" <C-m> 을 쓰는 대가를 알고 쓴다
"   터미널에서 <C-m> 은 <CR> 과 같은 바이트(0x0D)다. 확인했다 - 이 설정에서
"   둘은 구별되지 않는다. 그러니 이 매핑은 '노멀 모드의 Enter' 를 가져간다.
"   Enter 는 원래 '다음 줄 첫 글자로' 인데 그 자리를 내준다(j 와 ^ 로 같은
"   일을 한다). 패널·quickfix·트리처럼 자기 <CR> 을 가진 창은 그쪽이 먼저라
"   영향이 없다 - 바뀌는 것은 보통 편집 창뿐이다.
"
"   let g:vimide_marks_key = '<Leader>mm'   " 다른 키로
"   let g:vimide_marks_key = ''             " 키를 걸지 않는다 (:VimIdeMarks 만)
let g:vimide_marks_key = '<C-m>'
if has('nvim') && !empty(get(g:, 'vimide_marks_key', '<C-m>'))
    execute 'nnoremap <silent> ' . g:vimide_marks_key . ' :VimIdeMarks<CR>'
endif
nnoremap <silent> <leader>fS :ProjectFilesSave<CR>
" 1 (기본) 새로 만든 파일을 저장하면 목록에 넣고 그 파일만 색인한다.
"
"          이미 목록에 있는 파일은 autoindex.lua 가 저장할 때마다 그 파일
"          하나만 갱신한다(global --single-update, 몇 ms). 함수를 넣거나
"          지우면 바로 반영되므로 이 옵션과 상관없이 늘 최신이다.
"          이 옵션이 메우는 것은 '목록에 없는 파일'뿐이다 - preset 의
"          디렉터리 항목 아래에 새로 만든 파일이 그렇다. 그때만 목록을
"          다시 펴고(0.36초) 그 파일 하나를 넣는다(0.04초). 전체 재색인은
"          하지 않는다. 디렉터리 항목 밖이면 아무 것도 하지 않는다.
"          잇달아 저장해도 마지막 저장 뒤 한 번만 돈다.
let g:projectfiles_index_new_on_save = 1
" 1000 (기본) 저장이 멈추고 이만큼(ms) 지나면 확인한다.
let g:projectfiles_index_new_on_save_delay = 1000

" 색인 목록을 '보는 자리에서 바로' 고치는 창들.
"
" 넷 다 같은 손버릇이다 - 커서 줄이나 고른 영역의 파일을 넣고(+) 빼고(-)
" 지금 들어 있는지 본다(=). 들어 있는 파일에는 줄 끝에 빨간 ● 가 붙는다.
"
"   NERDTree / neo-tree   +  -  =
"   netrw (:Ex)           +  -  =     g:projectfiles_netrw
"   BufExplorer (F6)      +  -  =     g:projectfiles_bufexplorer
"   quickfix (:copen)     +  -  =     g:projectfiles_quickfix
"   RelationView 패널     i+ i- i=    g:projectfiles_relationview
"
" 패널만 'i' 가 붙는 이유: 거기서 + 와 - 는 이미 트리 펼치기/접기다. 그
" 자리를 빼앗으면 관계 목록을 읽는 손버릇이 통째로 바뀐다. 앞머리는
" g:projectfiles_relationview_prefix 로 바꿀 수 있다.
"
" quickfix 와 패널은 한 파일이 여러 줄에 나오는 것이 예사다(한 파일에서 열
" 곳을 찾으면 열 줄). 영역을 골라도 같은 파일은 한 번만 넘긴다.
"
"   let g:projectfiles_quickfix = 0        " quickfix 쪽을 끈다
"   let g:projectfiles_relationview = 0    " 패널 쪽을 끈다
"   let g:projectfiles_relationview_prefix = 'g'   " g+ g- g= 로
"   let g:projectfiles_quickfix_mark = '*'         " 표시 문자를 바꾼다
let g:projectfiles_quickfix = 1
let g:projectfiles_relationview = 1
nnoremap <silent> <leader>fR :ProjectFilesReindex<CR>
" Source Insight 의 Lookup References: 색인된 파일 '안에서만' 글자를 찾는다.
" relation window 가 떠 있으면 거기에 파일별로 묶어서, 아니면 quickfix 로.
"   \fr        커서 밑 낱말        :LookupReferences [글자]
"   \fF        직접 입력           :LookupReferences! 는 정규식
nnoremap <silent> <leader>fr :LookupReferences<CR>
nnoremap <leader>fF :LookupReferences<Space>
" Ctrl+/ 로도 바로 입력할 수 있게. 두 가지를 다 건다 - 터미널마다 이 키를
" 보내는 방법이 다르기 때문이다.
"   <C-_>  0x1F 한 바이트. 예전부터 터미널이 Ctrl+/ 로 보내던 것이고
"          Tera Term 을 포함해 대부분이 이걸 보낸다.
"   <C-/>  터미널이 확장 키 규약(kitty keyboard / CSI-u)을 쓸 때 nvim 이
"          따로 알아보는 형태. iTerm2 가 그쪽이다.
" 둘 다 비어 있던 키라 부딪히는 것은 없다. 어느 쪽이 오든 같은 자리로 간다.
"
" 누르면 찾을 거리를 미리 채워 주고, 엔터는 사용자가 친다 - 치기 전에
" 고칠 수 있어야 하기 때문이다.
"   normal  커서 밑 낱말 (<C-R><C-W> 가 명령행에 넣어 준다)
"   visual  고른 영역의 글자
"
" 고른 영역이 여러 줄이면 공백 하나로 이어 붙인다. 줄바꿈이 든 글자는
" 어차피 한 줄에서 찾히지 않으므로, 그대로 보여 주고 사용자가 다듬게 둔다.
" '> 의 열은 linewise(V) 에서 아주 큰 수가 오는데, vim 의 문자열 자르기가
" 그걸 '줄 끝'으로 받아 주므로 따로 손대지 않는다.
function! s:LookupVisual() abort
    let [l:l1, l:c1] = getpos("'<")[1:2]
    let [l:l2, l:c2] = getpos("'>")[1:2]
    let l:lines = getline(l:l1, l:l2)
    if empty(l:lines)
        return ''
    endif
    let l:lines[-1] = l:lines[-1][: l:c2 - 1]
    let l:lines[0] = l:lines[0][l:c1 - 1 :]
    return substitute(join(l:lines, ' '), '^\s\+\|\s\+$', '', 'g')
endfunction

" 커서가 심볼 글자 위에 있을 때만 채운다.
"
" <cword> 는 빈칸 위에서 '그 줄의 다음 낱말'을 집어 온다 - 들여쓰기 탭
" 위에서 누르면 return 이 채워졌다. 가리키지도 않은 것을 찾게 되니 지우고
" 다시 쳐야 한다. '{' 같은 글자 위에서는 '{' 가 그대로 들어왔다.
" 그런 자리에서는 빈 채로 띄우고 직접 치게 둔다.
function! s:LookupCword() abort
    let l:ch = matchstr(getline('.'), '\%' . col('.') . 'c.')
    return (l:ch =~# '\k') ? expand('<cword>') : ''
endfunction

" <C-/> 도 떠 있는 창에서 받는다 (askform.lua). 찾을 말 한 칸이다 -
" 룩업은 색인에 든 파일 전체가 대상이라 경로를 물을 것이 없다.
"   let g:vimide_lookup_float = 0   " 예전처럼 명령줄로
func! s:LookupPrompt() abort
	if has('nvim') && exists('*luaeval') && get(g:, 'vimide_lookup_float', 1)
				\ && luaeval('_G.vimide_ask ~= nil')
		call luaeval('(function(a)'
					\ . ' _G.vimide_ask({ title = " 룩업 레퍼런스 ",'
					\ . '   fields = { { label = "찾을 말", value = a } },'
					\ . '   footer = " Enter 찾기 · Esc 취소 " },'
					\ . '  function(v) if v[1] ~= "" then'
					\ . '    vim.cmd("LookupReferences " .. vim.fn.escape(v[1], " \\\\"))'
					\ . '  end end) return 1 end)(_A)', s:LookupCword())
		return
	endif
	call feedkeys(':LookupReferences ' . s:LookupCword(), 'n')
endfunc
nnoremap <silent> <C-_> :call <SID>LookupPrompt()<CR>
nnoremap <silent> <C-/> :call <SID>LookupPrompt()<CR>
" visual 에서는 고른 글자에 F4 와 같은 색도 입힌다.
"
" 찾은 것을 목록에서 훑는 동안 '무엇을 찾고 있었는지'가 본문에도 남아
" 있어야 눈이 덜 헤맨다. F4 가 하는 일(<Plug>MarkSet)과 같은 호출이다:
" mark#DoMark(v:count, mark#GetVisualSelectionAsLiteralPattern()).
"
" 색을 입힌 글자와 찾는 글자는 같은 곳에서 얻는다 - mark#GetVisualSelection()
" 하나만 쓴다. 그 함수는 gvy 로 얻으면서 " 레지스터와 'clipboard' 를 스스로
" 저장했다 되돌린다(autoload/mark.vim:81). vim-mark 이 없으면 마크는
" 건너뛰고 마크 마크만으로 찾는다.
"
" 여러 줄을 골랐으면 찾을 때는 줄바꿈을 공백으로 바꾼다 - 한 줄에서 찾는
" 것이라 줄바꿈이 든 글자는 어차피 안 맞는다. 색은 고른 그대로 입는다.
" autoload 함수는 한 번 불러 보기 전에는 exists('*mark#...') 가 0 이다.
" 그래서 '있는지 묻고 부르는' 대신 불러 보고 없으면 받는다 - 부르는 순간
" autoload/mark.vim 이 읽히므로, 깔려 있으면 이때 해결된다.
function! s:LookupVisualMark() abort
    let l:have = 1
    try
        let l:raw = mark#GetVisualSelection()
    catch /E117/
        let l:have = 0
        let l:raw = s:LookupVisual()
    endtry
    let l:t = substitute(substitute(l:raw, '[\r\n]\+', ' ', 'g'),
                \ '^\s\+\|\s\+$', '', 'g')
    if empty(l:t)
        return
    endif
    " 색은 여기서 입히지 않는다. :LookupReferences 가 실제로 찾을 때 한 번만
    " 칠한다(relationview.lua 의 _G.vimide_mark_text) - vim-mark 은 같은 글자에
    " 두 번 부르면 '지우기'라서, 두 군데서 칠하면 서로를 지운다.
    " 명령행을 띄우고 거기서 멈춘다 - 엔터는 사용자가 친다
    call feedkeys(':LookupReferences ' . l:t, 'n')
endfunction

xnoremap <silent> <C-_> :<C-u>call <SID>LookupVisualMark()<CR>
xnoremap <silent> <C-/> :<C-u>call <SID>LookupVisualMark()<CR>
nnoremap <silent> <leader>fs :ProjectSymbols<CR>
" 같은 것을 <F7> 로도 연다 - 펑션키는 아래 F1..F12 블록에서 한꺼번에 맵한다.
nnoremap <silent> <leader>fw :execute 'ProjectSymbols' expand('<cword>')<CR>
" SI 의 Bookmark window: 표시는 ma..mz / mA..mZ (shada 가 세션 사이에도
" 기억한다), 목록은 <leader>fk. signcolumn 을 두 칸으로 둬서 vim-signify 의
" 변경 표시와 북마크 표시가 서로를 덮지 않게 한다.
nnoremap <silent> <leader>fk <cmd>Telescope marks<cr>
" 'auto:2' 는 nvim 전용이다 (vim 은 auto/yes/no 까지만 받는다: E474)
if has('nvim')
    set signcolumn=auto:2
else
    set signcolumn=auto
endif


"==============================================================================
"= my setting
"==============================================================================
set mouse=a
set path+=/root/work/include,/usr/include,/usr/local/include,/usr/src/include
set path+=./include,./include/linux

"==============================================================================
"= 테마 세 가지를 g:vimide_theme 로 고른다.
"=
"=   'si'     Source Insight 기본 배색 그대로 (~/.vim/colors/sourceinsight.vim)
"=            순백 배경 + 검정 본문 + 네이비 볼드 키워드 + 초록 이탤릭 주석
"=            + 마룬 문자열. Treesitter(@...) 그룹까지 같은 배색.
"=   'light'  PaperColor(light) - 기성 라이트 테마 중 SI 에 가장 가깝다
"=   'dark'   예전 jellybeans 어두운 화면
"=
"=   let g:vimide_theme = 'light'   " ~/.vimrc 보다 먼저 읽히는 곳에서
"=   :VimIdeTheme si / light / dark " 실행 중에 바꾸기
"=
"= 24bit 색이 있어야 팔레트가 제대로 나온다. $COLORTERM 이 truecolor 를
"= 알리면 자동으로 켜진다. SSH 는 COLORTERM 을 넘기지 않으므로 원격에서는
"= let g:vimide_truecolor = 1 을 넣어 직접 켠다. 꺼져 있으면 256색으로
"= 근사되고 커서색도 바뀌지 않는다. 진단은 :VimIdeColorCheck.
"==============================================================================
let g:vimide_theme = get(g:, 'vimide_theme', 'si')

function! s:VimIdeApplyTheme(which) abort
    let g:vimide_theme = a:which
    " 24bit 색을 켤지: 터미널이 스스로 알리는 $COLORTERM 이 1차 신호다.
    " SSH 는 TERM 만 넘기고 COLORTERM 은 넘기지 않으므로 원격에서는 비어
    " 있는 게 정상이다. 그때는 g:vimide_truecolor = 1 로 직접 켠다.
    " termguicolors 가 꺼지면 팔레트가 256색으로 근사되고, 터미널 커서색도
    " 바뀌지 않는다(nvim 은 24bit 일 때만 OSC 12 로 커서색을 내보낸다).
    if has('termguicolors') && (get(g:, 'vimide_truecolor', 0)
                \ || $COLORTERM ==# 'truecolor' || $COLORTERM ==# '24bit')
        set termguicolors
    endif
    " 터미널 커서 색은 guicursor 가 가리키는 하이라이트 그룹에서 온다.
    " 기본값은 그룹을 지정하지 않아 터미널 커서색이 그대로 쓰이고, 흰
    " 배경에서는 거의 보이지 않는다. 모드마다 Cursor 를 붙여 준다.
    " nvim 전용: vim 은 이 모드 조합을 거부하고(E546), 터미널 커서색을
    " 이렇게 바꾸지도 않는다.
    if has('nvim')
        set guicursor=n-v-c-sm:block-Cursor,i-ci-ve:ver25-Cursor,r-cr-o:hor20-Cursor,t:block-blinkon500-blinkoff500-TermCursor
    endif
    if a:which ==# 'si'
        set background=light
        silent! colorscheme sourceinsight
        let g:airline_theme = 'papercolor'
    elseif a:which ==# 'light'
        set background=light
        silent! colorscheme PaperColor
        let g:airline_theme = 'papercolor'
    else
        set background=dark
        silent! colorscheme jellybeans
        let g:airline_theme = 'hybrid'
        highlight Cursor guifg=#151515 guibg=#f0f0f0 ctermfg=233 ctermbg=255
        highlight! link lCursor Cursor
        highlight! link TermCursor Cursor
    endif
    if exists('*airline#switch_theme')
        silent! call airline#switch_theme(g:airline_theme)
    endif
endfunction

" 색·커서가 이상할 때 무엇이 켜져 있는지 한 눈에 (특히 SSH 원격)
function! s:VimIdeColorCheck() abort
    echo '테마          : ' . get(g:, 'colors_name', '?')
                \ . '  (g:vimide_theme = ' . get(g:, 'vimide_theme', '?') . ')'
    echo 'termguicolors : '
                \ . (has('termguicolors') ? (&termguicolors ? 'on' : 'off') : '기능 없음')
    echo '$COLORTERM    : ' . (empty($COLORTERM) ? '(비어 있음)' : $COLORTERM)
    echo '$TERM         : ' . $TERM
    echo '접속          : ' . (empty($SSH_TTY) ? '로컬' : 'SSH (' . $SSH_TTY . ')')
    echo 'guicursor     : ' . (&guicursor =~# 'Cursor' ? 'Cursor 그룹 연결됨' : '그룹 없음')
    echo 'Cursor 색      : ' . synIDattr(hlID('Cursor'), 'bg#')
                \ . ' / ' . synIDattr(hlID('Cursor'), 'fg#')
    echo '커서색 전송   : '
                \ . ((&termguicolors && &guicursor =~# 'Cursor') ? '예 (OSC 12)'
                \    : '아니오 - termguicolors 가 꺼져 있어 커서색을 못 바꾼다')
    if has('termguicolors') && !&termguicolors
        echo ''
        echo '켜는 방법 (하나만 하면 된다):'
        echo '  1) 원격 셸에  export COLORTERM=truecolor   (~/.bashrc)'
        echo '  2) ~/.vimrc 보다 먼저 읽히는 곳에  let g:vimide_truecolor = 1'
        echo '  3) 맥 ~/.ssh/config 에  SendEnv COLORTERM  (서버 sshd 는 AcceptEnv 필요)'
    endif
endfunction
command! VimIdeColorCheck call s:VimIdeColorCheck()

command! -nargs=1 -complete=customlist,s:VimIdeThemeComplete VimIdeTheme
            \ call s:VimIdeApplyTheme(<q-args>)
function! s:VimIdeThemeComplete(a, l, p) abort
    return filter(['si', 'light', 'dark'], 'v:val =~ "^" . a:a')
endfunction

"colorscheme desertEx
"colorscheme badwolf
"colorscheme jellybeans        " g:vimide_theme = 'dark' 가 이걸 쓴다
call s:VimIdeApplyTheme(g:vimide_theme)

"==============================================================================
"= Cursor line
"= jellybeans paints CursorLine one single shade above the background
"= (ctermbg 234 on 233), which is invisible, and leaves it off in edit
"= windows. Turn it on everywhere and make the focused line actually stand
"= out. Re-applied on every :colorscheme so it never gets wiped.
"= Tune these three lines if you want it stronger or weaker.
"==============================================================================
set cursorline

"==============================================================================
"= 원격 터미널에서 창이 커질수록 느려지는 것을 줄인다
"==============================================================================
" 테라텀에서 '창이 커질수록 느리다'는 신고가 들어와 재 봤다. 비용이 두
" 갈래이고 둘 다 창 크기에 비례한다 (개발서버, core.c 5182줄, 20초 동안
" Ctrl-D 연속):
"
"   nvim CPU        30줄 4.0s   60줄 5.6s   100줄 6.5s
"   터미널로 보낸 양  30줄 1.2KB  60줄 2.6KB  100줄 4.4KB  (화면 하나당)
"
" CPU 는 1.6배 느는데 바이트는 3.7배 는다. 터미널은 그 바이트를 받아서
" 그려야 하므로, 링크가 느릴수록 체감은 바이트 쪽이 지배한다. iTerm2
" (로컬, 빠른 링크)에서 덜 느껴지는 이유이기도 하다.
"
" 아래 세 줄은 전부 실측으로 고른 것이다. 보이는 동작이 달라지므로
" 각 줄을 지우면 예전 그대로 돌아간다.

" 색인 컬러링을 커서가 멈춘 뒤 얼마나 기다렸다 물을지. 200 -> 600ms.
" 100줄 창에서 6.5s -> 4.8s (-26%). 스크롤 중에는 아예 묻지 않게 된다.
"   let g:sihl_index = 0   " 색을 통째로 끄면 6.5s -> 4.5s
let g:sihl_index_delay = 600

" 커서 줄 강조를 줄 전체가 아니라 줄번호에만 두는 선택지도 있다. 커서를
" 한 줄 옮길 때마다 보내는 양이 1051 -> 약 300 바이트로 줄어든다.
" 켜지 않는다: 줄 전체에 깔리는 띠는 '지금 어느 줄에 있는지'를 한눈에
" 알려 주는 것이라, 바이트와 바꿀 만한 것이 아니라고 판단했다.
"   let g:vimide_light_cursorline = 1

" 스크롤을 5줄씩 몰아서 한다. 한 번에 11.1KB 씩 다시 그리던 것을 다섯 번에
" 나눠 보낸다. 총량은 같고, 한 번의 멈칫함이 짧아진다.
let g:vimide_scrolljump = 5

if get(g:, 'vimide_light_cursorline', 0) && !has('gui_running')
    set cursorlineopt=number
endif
if get(g:, 'vimide_scrolljump', 0) > 0 && !has('gui_running')
    let &scrolljump = g:vimide_scrolljump
    set sidescroll=1
endif

function! s:RvCursorLineColors() abort
    " sourceinsight 테마는 이 색들을 스스로 정한다 (SI 배색의 일부)
    if get(g:, 'colors_name', '') ==# 'sourceinsight'
        return
    endif
    if &background ==# 'light'
        " 흰 배경에서는 어두운 띠가 오히려 글자를 덮는다: 아주 옅은 회청색
        highlight CursorLine     term=NONE cterm=NONE ctermbg=254 guibg=#e4e4e4
        highlight CursorLineNr   cterm=bold ctermbg=254 ctermfg=24
                    \ gui=bold guibg=#e4e4e4 guifg=#005f87
        " the relation/context windows use a slightly stronger bar for the row
        " under the panel cursor (see ~/.vim/plugin/relationview.lua)
        highlight RvCursorLine   cterm=NONE ctermbg=252 guibg=#d0d0d0
        highlight RvCursorLineNr cterm=bold ctermbg=252 ctermfg=24
                    \ gui=bold guibg=#d0d0d0 guifg=#005f87
    else
        highlight CursorLine     term=NONE cterm=NONE ctermbg=238 guibg=#343a45
        highlight CursorLineNr   cterm=bold ctermbg=238 ctermfg=117
                    \ gui=bold guibg=#343a45 guifg=#87d7ff
        highlight RvCursorLine   cterm=NONE ctermbg=240 guibg=#4e5561
        highlight RvCursorLineNr cterm=bold ctermbg=240 ctermfg=117
                    \ gui=bold guibg=#4e5561 guifg=#87d7ff
    endif
endfunction

call s:RvCursorLineColors()
augroup RvCursorLineColors
    autocmd!
    autocmd ColorScheme * call s:RvCursorLineColors()
augroup END

"==============================================================================
" vim grep
"==============================================================================
"set grepprg=grep\ --color=always\ -n\ $*\ /dev/null
"set makeprg=make\ EXTRA_CFLAGS=-fcolor-diagnostic
"let $grepfile="*.[ch] *.cpp"
"map ,gr :grep --exclude="*svn*" --exclude="cscope.out" --exclude="*tags*" -nRI <cword> *<CR>
"map ,gf :grep --exclude="*svn*" --exclude="cscope.out" --exclude="*tags*" -nRI
map ,gr :!/bin/grep --color=auto --exclude="*svn*" --exclude="cscope.out" --exclude="*tags*" --exclude="*.lst" -nRI <cword> *<CR>
map ,gf :!/bin/grep --color=auto --exclude="*svn*" --exclude="cscope.out" --exclude="*tags*" -nRI

let g:Grep_Skip_Dirs='.svn'
"let g:Grep_Skip_Files = '*~ *,v s.*'
let Grep_Path = '/usr/bin/grep'
let Grep_OpenQuickfixWindow = 1
let Grep_Default_Options = '--exclude="*svn*" --exclude="cscope.out" --exclude="*tags*" --exclude="*.lst" --exclude="*.o.*" --exclude="*.o" --exclude="_.*" -nRI'
" <C-g> : 지금 파일이 있는 디렉터리 이하에서 커서 밑 낱말을 찾는다.
"
"   RelationView 패널이 떠 있으면  -> 패널 목록에
"   떠 있지 않으면                 -> quickfix 창에
"
" 색인(gtags)이 아니라 글자 그대로 찾는 길이다. 주석, 문자열, 매크로 조각,
" 아직 색인하지 않은 파일처럼 :Gtags 가 모르는 것을 찾을 때 쓴다.
" ripgrep(rg)이 있으면 그것을, 없으면 grep -rnI 를 쓴다.
"
" 예전에는 이 키가 grep.vim 의 :Grep(패턴과 경로를 하나씩 되묻는 대화식)
" 이었다. 그 명령은 그대로 남아 있으니 필요하면 :Grep 으로 부르면 된다.
"
"   let g:relationview_grep_word = 0    " 낱말 경계 없이 (부분 일치)
"   let g:relationview_grep_max = 1000  " 이 줄 수를 넘으면 끊는다
" 이 창에서 <C-g> 를 받아도 되나.
"
" 도움말 창은 뺀다. s:JumpHere() 는 help 를 통과시키는데(<C-]> 가 |태그|
" 점프라서), 여기서 통과시키면 vim 런타임의 doc 디렉터리를 뒤지게 되고,
" 패널이 떠 있는데 미리보기가 닫혀 있으면 첫 결과로 편집 창이 도움말
" 텍스트로 바뀐다. 도움말에서 낱말을 찾는 일은 :helpgrep 이 한다.
"
" 곁창도 뺀다 - 거기 커서 밑 낱말은 목록의 글자이지 소스의 심볼이 아니다.
" 다만 미리보기 창(\p)은 진짜 파일을 보여주는 자리라 낱말도 경로도 뜻이
" 있어서 받는다. <C-]>/gf 가 s:JumpFromPeek 으로 해 주는 것과 같은 대접이다.
func! s:GrepHere() abort
	if &buftype ==# 'help'
		return 0
	endif
	return s:JumpHere() || (&buftype ==# '' && !empty(expand('%:p')))
endfunc

" 찾을 말을 명령줄에 채워 보여준다. Enter 를 누르면 찾고, 고쳐 치면 고친
" 말을 찾고, Esc 면 그만둔다.
"
" 왜 input() 이 아니라 명령줄인가: 명령줄이면 지우고 고치는 손버릇이 그대로
" 통하고, ':' <Up> 으로 방금 찾은 것을 다시 불러 쓸 수 있다. :VimIdeGrep 은
" -nargs=1 이라 빈칸이 든 말도 통째로 하나로 받는다.
func! s:GrepPrompt(text) abort
	if !s:GrepHere()
		return
	endif
	" 떠 있는 창에서 두 칸을 받는다 - 찾을 말, 찾을 곳 (askform.lua).
	"
	" 예전에는 명령줄이었다: ':VimIdeGrep <말>' 을 띄우고, Enter 뒤에
	" input() 으로 경로를 다시 물었다. 두 물음이 화면 맨 아래 한 줄에서
	" 차례로 지나가서, 지금 무엇을 묻는 중인지 놓치기 쉬웠다. 두 칸을
	" 한 창에 같이 보여주면 고칠 것을 보고 고칠 수 있다.
	"
	"   let g:vimide_grep_float = 0   " 예전처럼 명령줄로
	if has('nvim') && exists('*luaeval') && get(g:, 'vimide_grep_float', 1)
				\ && luaeval('_G.vimide_ask ~= nil')
		let l:f = expand('%:p')
		let l:d = empty(l:f) ? getcwd() : fnamemodify(l:f, ':h')
		call luaeval('(function(a)'
					\ . ' _G.vimide_ask({ title = " 찾기 (grep) ",'
					\ . '   fields = { { label = "찾을 말", value = a[1] },'
					\ . '              { label = "찾을 곳", value = a[2], file = true } },'
					\ . '   footer = " Tab 칸 이동 · Enter 찾기 · Esc 취소 · <C-x><C-f> 경로 완성 " },'
					\ . '  function(v)'
					\ . '   if v[1] == "" then return end'
					\ . '   local d = vim.fn.fnamemodify(vim.fn.expand(v[2] == "" and a[2] or v[2]), ":p")'
					\ . '   d = d:gsub("/+$", "")'
					\ . '   if vim.fn.isdirectory(d) ~= 1 then'
					\ . '     vim.notify("그런 디렉터리가 없습니다 - " .. d, vim.log.levels.WARN) return'
					\ . '   end'
					\ . '   _G.relationview_grep(v[1], d)'
					\ . '  end) return 1 end)(_A)', [a:text, l:d])
		return
	endif
	" 낱말이 비어 있어도(빈칸 위에서 눌렀어도) 명령줄은 띄운다. 거기서
	" 찾을 말을 쳐 넣으면 된다. 그대로 Enter 면 :VimIdeGrep 이 인자 없이
	" 불려 조용히 끝난다(-nargs=?).
	call feedkeys(':VimIdeGrep ' . a:text, 'n')
endfunc

" 고른 글자를 읽는다. 레지스터는 건드린 뒤 되돌려 놓는다.
" 여러 줄을 골랐으면 첫 줄만 쓴다 - grep 은 한 줄 안에서 찾는다.
func! s:VisualText() abort
	let l:reg = getreg('"')
	let l:type = getregtype('"')
	silent normal! gvy
	let l:t = getreg('"')
	call setreg('"', l:reg, l:type)
	return trim(get(split(l:t, "\n"), 0, ''))
endfunc

" 실제로 찾는다. <C-g> 로 채운 명령줄에서 Enter 를 누르면 여기로 온다.
func! s:RunGrep(word) abort
	if !s:GrepHere()
		return
	endif
	let l:w = a:word
	if empty(l:w)
		return
	endif
	let l:f = expand('%:p')
	let l:d = empty(l:f) ? getcwd() : fnamemodify(l:f, ':h')
	" 찾을 경로를 한 번 더 보여준다.
	"
	" 기본은 지금 파일이 있는 디렉터리다. 그대로 Enter 면 거기서 찾고,
	" 고쳐 치면 그 경로에서 찾는다. <Tab> 으로 디렉터리를 완성할 수 있고,
	" 비우거나 Esc 면 그만둔다.
	"
	"   let g:relationview_grep_ask_dir = 0   " 묻지 않고 바로 찾는다
	if get(g:, 'relationview_grep_ask_dir', 1)
		" try/finally 로 감싸는 이유: <C-c> 로 그만두면 input() 이 인터럽트를
		" 올려 이 함수가 그 자리에서 끝난다. 그러면 echohl None 이 안 돌아
		" 그 뒤 메시지가 전부 Question 색으로 나온다(실측: vim 9.1, nvim 0.12
		" 둘 다). :help :echohl 도 '되돌려 놓는 것을 잊지 말라' 고 적고 있다.
		let l:in = ''
		try
			echohl Question
			let l:in = input('Grep "' . l:w . '" 에서 찾을 곳: ', l:d, 'dir')
		catch /^Vim:Interrupt$/
			return
		finally
			echohl None
		endtry
		redraw
		if empty(trim(l:in))
			return
		endif
		let l:d = fnamemodify(expand(trim(l:in)), ':p')
		" 끝의 '/' 는 떼어 둔다. rg 는 상관없지만 결과에 '//' 가 섞인다.
		let l:d = substitute(l:d, '/\+$', '', '')
		if !isdirectory(l:d)
			echohl WarningMsg
			echo 'vim-ide: 그런 디렉터리가 없습니다 - ' . l:d
			echohl None
			return
		endif
	endif
	if has('nvim') && exists('*luaeval')
				\ && luaeval('_G.relationview_grep ~= nil')
		call luaeval('(function() _G.relationview_grep(_A[1], _A[2]) return 1 end)()',
					\ [l:w, l:d])
		return
	endif
	" 진짜 vim 8.1: 패널도 lua 도 없다. quickfix 로 보낸다.
	"
	" 옵션은 nvim 쪽과 같은 것을 본다. 예전에는 -w 를 늘 붙이고 상한도
	" 없어서, 같은 키가 machine 마다 다르게 굴었다.
	" grepformat 도 같이 바꾼다 - rg --vimgrep 의 칸 번호가 기본 형식에는
	" 없어서, 안 바꾸면 그 숫자가 메시지 글자에 섞여 보인다.
	let l:save = [&grepprg, &grepformat]
	let l:wordf = get(g:, 'relationview_grep_word', 1) ? ' -w' : ''
	let l:hid = get(g:, 'relationview_grep_hidden', 0)
	try
		if executable('rg')
			let &grepprg = 'rg --vimgrep --no-heading --color=never -F'
						\ . l:wordf . (l:hid ? ' --hidden --no-ignore' : '') . ' $*'
			let &grepformat = '%f:%l:%c:%m'
		else
			let &grepprg = 'grep -rnI -F' . l:wordf
						\ . ' --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.tags $*'
			let &grepformat = '%f:%l:%m'
		endif
		" escape(..., '%#|') 가 왜 필요한가.
		"
		" :grep 은 :make 와 같아서 인자의 '%' 와 '#' 을 파일 이름으로 펼친다
		" (:help :make - "Characters '%' and '#' are expanded as usual").
		" shellescape 의 작은따옴표는 셸 단계의 방어라 그보다 뒤에 와서 소용이
		" 없다 - 따옴표 '안'에서 치환이 일어난다. 실측(가짜 rg 로 셸 인자를
		" 찍어서, vim 9.1):
		"   '#define'  -> '<대체파일경로>define'   조용히 0건
		"   '100%'     -> '100<현재파일경로>'
		"   대체 파일이 없으면 E194 로 죽는다
		" 이 기능의 존재 이유가 '색인이 모르는 매크로 조각' 인데 정작
		" #define/#include/#ifdef 가 통째로 안 되던 셈이다.
		"
		" '|' 도 같이 막는다. :grep 은 :bar 목록에 없어서 '|' 에서 명령이
		" 잘리고, 셸은 따옴표가 안 닫힌 조각을 받아 E40 으로 죽는다
		" (실측: 'a || b', 'FLAG|MASK'). 아래 -bar 주석이 ':VimIdeGrep 까지는
		" 참' 이라는 말의 나머지 절반이 이것이다.
		"
		" shellescape 바깥에 씌워야 한다. 안쪽에 넣으면 역슬래시가 찾을 말
		" 자체에 섞인다. shellescape(l:w, 1) 도 쓰면 안 된다 - '!' 앞 역슬래시를
		" :grep 은 안 지워서 a!b 가 'a\!b' 로 넘어간다(:! 만 지운다).
		execute 'silent grep! ' . escape(shellescape(l:w), '%#|')
					\ . ' ' . fnameescape(l:d)
	finally
		let [&grepprg, &grepformat] = l:save
	endtry
	if empty(getqflist())
		echohl WarningMsg | echo 'Grep ' . l:w . ' : 결과 없음' | echohl None
	else
		botright copen
	endif
endfunc
" -nargs=? 는 '없거나 하나' 이지 '빈칸에서 자른다' 가 아니다. 빈칸이 든 말도
" 통째로 하나로 온다. -bar 를 안 붙여서 '|' 도 찾을 말의 일부로 남는다 -
" 다만 그것은 여기까지만 참이고, 그 말을 :grep 에 넘길 때는 위에서처럼
" '\' 를 덧대야 한다(cmdline.txt 의 :bar - :grep 은 그 목록에 없다).
" 인자가 없으면(빈칸 위에서 <C-g> 를 누르고 그대로 Enter) 조용히 끝난다.
command! -nargs=? VimIdeGrep call s:RunGrep(<q-args>)

" <C-u> 로 카운트를 먹는다. 없으면 2<C-g> 가 ':.,.+1call ...' 이 되어
" E481(범위를 받지 않는다)로 죽는다 - vim 본래의 2<C-g>(전체 경로) 손버릇이
" 남아 있는 사람이 바로 만나는 자리다.
nnoremap <silent> <C-g> :<C-u>call <SID>GrepPrompt(expand('<cword>'))<CR>
" 비주얼: 고른 글자를 채워 보여준다. :<C-u> 로 '<,'> 범위를 지우고, 레지스터를
" 쓰는 s:VisualText 안에서 gv 로 그 선택을 되살린다.
xnoremap <silent> <C-g> :<C-u>call <SID>GrepPrompt(<SID>VisualText())<CR>
"map <Leader>r <ESC>:Rgrep <C-R>=expand("<cword>")<CR>
"map <Leader>jj :Grep -R --include=*.java --include=*.xml --include=*.aidl <C-R>=expand("<cword>")<CR>
"map <Leader>jc :Grep -R --include=*.c --include=*.cc --include=*.cpp --include=*.h <C-R>=expand("<cword>")<CR>
"map <C-x><C-x> :GitGrep <C-R>=expand("<cword>")<CR>


"==============================================================================
" load Coverity command
"==============================================================================
let coverity_vimrc = $HOME . "/.vim/coverity.vimrc"
if filereadable(coverity_vimrc)
  execute "source " . fnameescape(coverity_vimrc)
endif

"==============================================================================
" quickr-preview-vim
"==============================================================================
"let g:quickr_preview_keymaps = 0
nmap <leader>p <plug>(quickr_preview)
nmap <leader>q <plug>(quickr_preview_qf_close)
let g:quickr_preview_position = 'below'
let g:quickr_preview_size = '0'
let g:quickr_preview_line_hl = "Search"
let g:quickr_preview_options = 'number norelativenumber nofoldenable'
let g:quickr_preview_on_cursor = 0
let g:quickr_preview_exit_on_enter = 0
let g:quickr_preview_modifiable = 0


"==============================================================================
" Shortcuts
"==============================================================================

" Help man
func! Man()
	let sm = expand("<cword>")
	"exe "!man -S 2:3:4:5:6:7:8:9:tcl:n:l:p:o ".sm
endfunc

func! Maketags()
	":!find * \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' \) -print > cscope.files
	"exe "!time ctags -L cscope.files"
	"exe "!time gtags -f cscope.files"
	:!time mktags.sh .
endfunc

func! Deltags()
	let l:d = get(g:, 'autoindex_dbdir', '.tags')
	let l:extra = empty(l:d) ? ''
				\ : ' ' . l:d . '/GPATH ' . l:d . '/GRTAGS ' . l:d . '/GTAGS'
	exe "!time rm -f cscope.files cscope.out GPATH GRTAGS GTAGS tags" . l:extra
endfunc

" NERDTree 가 꺼져 있으면(g:vimide_nerdtree = 0, nvim 기본) 조용히 실패하는
" 대신 어디를 켜면 되는지 알려 준다.
func! s:NoNERDTree() abort
	if exists(':NERDTreeToggle') == 2
		return 0
	endif
	echohl WarningMsg
	echo 'vim-ide: NERDTree 를 끈 상태입니다 (let g:vimide_nerdtree = 1 로 켭니다). 트리는 F9 / F11 의 neo-tree 를 쓰세요'
	echohl None
	return 1
endfunc

func! NERDTreeOnlyLeft()
	if s:NoNERDTree() | return | endif
	:TagbarClose
	:AerialClose
	let g:NERDTreeWinPos="left"
	:NERDTreeToggle
endfunc

func! NERDTreeOnlyRight()
	if s:NoNERDTree() | return | endif
	let g:NERDTreeWinPos="right"
	:NERDTreeToggle
	call VimIdeBalanceSoon()
endfunc

" F9: neo-tree on the left (tagbar 도 왼쪽이라 함께 열면 좁아서 닫는다).
" 예전 NERDTree 왼쪽 창이 필요하면 :call NERDTreeOnlyLeft() 로 그대로 쓸 수 있다.
" 옆 창(F3 RelationView, F9 neo-tree, F10 aerial, F11 tagbar ...)을 켜고 끄면
" EDIT 창이 한쪽만 좁아진다. 새 창이 제 자리를 '이웃 하나'에서 통째로
" 가져가기 때문이다. 실측(220칸, EDIT 2분할):
"   F3 켬  -> EDIT 110 / 23     (85칸짜리 열이 한쪽에서만 나왔다)
"   F10 켬 -> EDIT 26 / 66
" 그래서 토글한 뒤에 'wincmd =' 로 EDIT 을 고르게 편다. 옆 창들은
" winfixwidth/winfixheight 라 이 명령이 건드리지 않는다 - 실측으로 위
" 두 경우가 66/67 과 46/46 이 되고 옆 창 크기는 그대로였다.
"
"   let g:vimide_balance_on_toggle = 0   " 끄면 예전처럼 그대로 둔다
if !exists('g:vimide_balance_on_toggle')
    let g:vimide_balance_on_toggle = 1
endif
function! VimIdeBalance(...) abort
    if !get(g:, 'vimide_balance_on_toggle', 1)
        return
    endif
    wincmd =
endfunction
" neo-tree 와 aerial 은 창을 비동기로 만든다. 다 앉은 뒤에 편다.
function! VimIdeBalanceSoon() abort
    if !get(g:, 'vimide_balance_on_toggle', 1)
        return
    endif
    if exists('*timer_start')
        call timer_start(80, function('VimIdeBalance'))
    else
        call VimIdeBalance()
    endif
endfunction

func! NeoTreeOnlyLeft()
	:TagbarClose
	:AerialClose
	" 예전 방식(g:vimide_outline_global = 0)에서만 아웃라인을 닫는다.
	" 그때는 aerial 이 '지금 창'을 쪼개며 왼쪽 트리를 밀어냈다.
	" 지금 기본인 global+edge 는 맨 왼쪽에 따로 서기 때문에 밀어내지 않는다
	" (aerial | neo-tree | EDIT). 고정해 달라고 한 창을 F9 가 닫으면 안 된다.
	if !get(g:, 'vimide_outline_global', 1)
		:AerialClose
	endif
	:Neotree toggle left
	call VimIdeBalanceSoon()
endfunc
func! NeoTreeOnlyRight()
	:Neotree toggle right
	call VimIdeBalanceSoon()
endfunc

" NERDTree 에서 파일을 열면 '직전에 포커스가 있던 EDIT 창'에 연다.
"
" 왜 필요한가: NERDTree 의 Opener._firstUsableWindow() 는 이름 그대로
" '첫 번째' 보통 창을 집는다 (lib/nerdtree/opener.vim:52). 'p'(previous)
" 로 바꿔도 _previousWindow() 가 winnr('#') 를 쓰다가, 그 창이 옆 창이면
" _isWindowUsable() 에서 걸러져 다시 _firstUsableWindow() 로 떨어진다.
" 그래서 '여는 키'만 우리 콜백으로 바꾼다.
"
" KeyMap.Invoke 는 FileNode -> DirNode -> Node -> Bookmark -> all 순으로
" 찾는다 (lib/nerdtree/key_map.vim). <CR> 은 기본이 'all' 로만 걸려 있어
" FileNode 로 새로 걸면 그보다 먼저 잡히고, 'o' 는 FileNode 가 이미 있어
" override 가 필요하다.
"
" 쪼개기/탭(s i t T gi gs)은 사용자가 일부러 고른 것이라 건드리지 않는다.
"
"   let g:vimide_nerdtree_last_edit = 0   " 끄면 예전 동작
" 어느 창에 열까 - stock 과 같은 순서다:
"   1) 이미 그 파일을 띄우고 있는 창 ('reuse':'all' 과 같다)
"   2) 트리에 들어오기 직전 창 winnr('#') 이 편집 창이면 그것
"   3) relationview.lua 가 기억해 둔 마지막 편집 창 (_G.vimide_last_edit_win)
"   4) 못 찾으면 NERDTree 가 늘 하던 대로 (stock opts 를 그대로 넘긴다)
function! s:NERDTreeEditWin() abort
    " 트리를 여는 동작 자체가 창을 밀어내며 WinEnter 를 여러 번 일으켜서
    " 전역 추적기가 엉뚱한 편집 창을 가리키는 경우가 있었다(실측: 3번째
    " 창에서 열었는데 4번째에 열렸다). 그래서 alternate 창을 먼저 본다.
    " (vim 8.1/9.1 에는 lua 추적기가 없어 이 줄만 남는다 - 그래도 곁창을
    "  거쳐 들어오지 않은 보통의 경우는 이것으로 맞는다.)
    let l:alt = winnr('#')
    if l:alt > 0
        let l:w = win_getid(l:alt)
        if vimide#qf#Usable(l:w)
            return l:w
        endif
    endif
    let l:w = vimide#qf#Win()
    return vimide#qf#Usable(l:w) ? l:w : 0
endfunction

" 새 NERDTree 는 nerdtree#closeTreeOnOpen() 을 주지만 서버의 예전 bundle
" (.vim/bundle/The-NERD-tree) 에는 없다. 없으면 g: 변수를 직접 본다.
function! s:NERDTreeQuitOnOpen() abort
    if exists('*nerdtree#closeTreeOnOpen')
        return nerdtree#closeTreeOnOpen()
    endif
    let l:q = get(g:, 'NERDTreeQuitOnOpen', 0)
    return l:q == 1 || l:q == 3
endfunction

func! s:NERDTreeOpen(node, stay) abort
    " stock 이 늘 주던 옵션. keepopen 을 빠뜨리면 Opener.New 의 has_opt()
    " 가 0 으로 읽어 _checkToCloseTree() 가 트리를 닫아 버린다
    " (opener.vim:141, 42) - 되돌아갈 트리가 사라진다.
    let l:quit = s:NERDTreeQuitOnOpen()
    let l:opts = {'reuse': 'all', 'where': 'p', 'stay': a:stay, 'keepopen': !l:quit}
    let l:tree = win_getid()
    let l:path = a:node.path.str()
    " 이미 그 파일을 띄운 창이 있으면 거기로 (stock 의 _reuseWindow 와 같다)
    let l:nr = bufwinnr('^' . l:path . '$')
    let l:win = l:nr > 0 ? win_getid(l:nr) : s:NERDTreeEditWin()
    if l:win <= 0 || l:win == l:tree
        " 편집 창이 없으면 NERDTree 가 늘 하던 대로 맡긴다 (쪼개기 등)
        call a:node.activate(l:opts)
        return
    endif
    " zoom 해 둔 트리는 stock 과 똑같이 먼저 푼다 (opener.vim:220)
    if !a:stay && !l:quit && get(b:, 'NERDTreeZoomed', 0)
        call b:NERDTree.ui.toggleZoom()
    endif
    call win_gotoid(l:win)
    if fnamemodify(bufname('%'), ':p') !=# fnamemodify(l:path, ':p')
        try
            execute 'edit ' . fnameescape(l:path)
        catch /^Vim\%((\a\+)\)\=:E/
            echohl WarningMsg
            echomsg substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', '')
            echohl None
            return
        endtry
    endif
    if l:quit
        call g:NERDTree.Close()
    elseif a:stay && win_id2win(l:tree) > 0
        call win_gotoid(l:tree)
    endif
endfunc

" 여는 키(<CR> o <2-LeftMouse>) 가 부른다
function! VimIdeNERDTreeOpen(node) abort
    call s:NERDTreeOpen(a:node, 0)
endfunction
" 미리보기(go): 파일은 EDIT 창에 뜨고 포커스는 트리에 남는다
function! VimIdeNERDTreePreview(node) abort
    call s:NERDTreeOpen(a:node, 1)
endfunction

" i / s / gi / gs (쪼개서 열기): 쪼개는 자리를 EDIT 창으로 옮긴다.
"
" stock 은 'wincmd p' 로 직전 창을 쪼갠다. 그 직전 창이 aerial 이나
" quickfix 면 곁창 옆에 낀 좁은 창에 소스가 뜨고 편집 창은 한 칸까지
" 눌렸다. '쪼개고 싶다' 는 뜻은 살리되 쪼개지는 자리만 편집 영역으로 옮긴다.
" t / T (새 탭) 는 창 자리와 상관없으니 그대로 둔다.
func! s:NERDTreeSplit(node, cmd, stay) abort
    let l:tree = win_getid()
    let l:path = a:node.path.str()
    let l:win = s:NERDTreeEditWin()
    if l:win <= 0 || l:win == l:tree
        " 편집 창이 없으면 NERDTree 가 늘 하던 대로 맡긴다
        call a:node.activate({'reuse': 'all',
                    \ 'where': a:cmd ==# 'vsplit' ? 'v' : 'h',
                    \ 'stay': a:stay, 'keepopen': !s:NERDTreeQuitOnOpen()})
        return
    endif
    call win_gotoid(l:win)
    try
        execute a:cmd . ' ' . fnameescape(l:path)
    catch /^Vim\%((\a\+)\)\=:E/
        echohl WarningMsg
        echomsg substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', '')
        echohl None
        return
    endtry
    if a:stay && win_id2win(l:tree) > 0
        call win_gotoid(l:tree)
    endif
endfunc
function! VimIdeNERDTreeSplit(node) abort
    call s:NERDTreeSplit(a:node, 'split', 0)
endfunction
function! VimIdeNERDTreeVSplit(node) abort
    call s:NERDTreeSplit(a:node, 'vsplit', 0)
endfunction
function! VimIdeNERDTreeSplitStay(node) abort
    call s:NERDTreeSplit(a:node, 'split', 1)
endfunction
function! VimIdeNERDTreeVSplitStay(node) abort
    call s:NERDTreeSplit(a:node, 'vsplit', 1)
endfunction

" e (그 디렉터리를 탐색기로 열기): stock 은 'wincmd p' 로 직전 창에
" 디렉터리를 :edit 한다. 직전 창이 aerial 이면 아웃라인이 통째로 디렉터리
" 목록으로 바뀌고 다시는 안 돌아왔다.
function! VimIdeNERDTreeExplore(node) abort
    let l:p = a:node.path.str()
    if !isdirectory(l:p)
        let l:p = fnamemodify(l:p, ':h')
    endif
    let l:win = s:NERDTreeEditWin()
    if l:win <= 0
        return
    endif
    call win_gotoid(l:win)
    execute 'silent! edit ' . fnameescape(l:p)
endfunction

func! NERDTreeOnly()
	if s:NoNERDTree() | return | endif
	:TagbarClose
	:NERDTreeToggle
	call VimIdeBalanceSoon()
endfunc

" F10 의 심볼 아웃라인. 기본은 aerial 이다.
"
" 왜 tagbar 가 아닌가: tagbar 는 파일을 열 때마다 ctags 를 돌리고 그 출력을
" vimscript 로 파싱해 트리를 만든다. ctags 는 싸다(3000줄 C 파일 27ms).
" 비싼 것은 파싱이고, 태그 하나당 0.5ms(맥)~1.6ms(서버)라 태그 수에 그대로
" 비례한다. 실측(서버, 파일 하나 열기):
"
"   파일                                  tagbar   aerial   둘 다 끔
"   tcc_maic_hw.h (태그 1016, 매크로 945)    47ms     29ms      32ms
"   합성 (태그 2400, 매크로 아님)          3908ms     47ms      46ms
"
" aerial 은 treesitter 가 하이라이트 때문에 이미 만들어 둔 트리를 Lua 로
" 훑어서, 아무것도 안 켠 것과 차이가 없다.
"
" 잃는 것: aerial 은 treesitter 파서가 있는 언어만 다룬다(백엔드는
" treesitter -> lsp -> markdown -> man 이고 ctags 폴백이 없다). 파서가 없는
" 파일에서는 :Tagbar 를 부르면 된다 - 그대로 남겨 뒀다.
"
"   let g:vimide_outline = 'tagbar'   " F10 을 예전처럼 tagbar 로
func! s:OutlineToggle() abort
	if get(g:, 'vimide_outline', 'aerial') ==# 'tagbar' || !exists(':AerialToggle')
		:TagbarToggle
	else
		:AerialToggle
	endif
endfunc

func! TagbarOnly()
	" NERDTree 는 nvim 에서 꺼 둘 수 있다(g:vimide_nerdtree). 없으면 조용히 넘어간다.
	silent! NERDTreeClose
	:Neotree close
	call s:OutlineToggle()
	call VimIdeBalanceSoon()
endfunc

func! NERDTree_and_Tagbar_Toggle()
	silent! NERDTreeClose
	:TagbarToggle
endfunc

"map <F1> :call Man()<cr><cr>
map <F1> :!man <C-R>=expand("<cword>") <cr><cr>
" <F2> 는 \fm 과 같다: 이 프로젝트의 색인 모드를 고른다
"   none  아무것도 하지 않는다 (기본 - .tags 가 없는 디렉터리)
"   auto  프로젝트 전체
"   <preset 이름>  그 목록만
" 모드를 고르기 전까지 vim 은 그 디렉터리에서 아무 색인도 시작하지 않는다.
" 예전 F2(Maketags -> mktags.sh 로 즉시 색인)는 :Maketags 로 남겨 둔다.
nnoremap <silent> <F2> :ProjectFilesPreset<CR>
command! -bar Maketags call Maketags()
map <F4> <Plug>MarkSet
map <F5> :MarkClear<CR> :noh<CR>
" 곁창에서 실행하면 먼저 직전 EDIT 창으로 옮긴 뒤 실행한다.
"
" '지금 창'을 차지하는 기능들이 있다 - BufExplorer(F6), netrw(:Ex) 같은
" 것들이다. 곁창에서 부르면 사이드바가 그 목록으로 바뀌고, 거기서 파일을
" 고르면 사이드바 자리에 파일이 열린다. 곁창은 그 플러그인 일만 해야 한다.
"
" 파일이 곁창에 '실린 뒤' 되돌리는 것은 vimidewin.lua 가 맡는다. 여기는
" 애초에 곁창에서 시작하지 않게 막는 쪽이다 - 되돌리는 것보다 낫다.
"
" EDIT 창이 하나도 없으면 아무것도 하지 않는다. 곁창을 부수느니 안 여는
" 편이 낫다.

" 곁창에 있으면 '편집 자리' 로 옮긴다.
"   1 = 이제 편집할 수 있는 창에 있다 (원래 EDIT 창이었거나, 옮겼다)
"   0 = 갈 자리가 없다
" a:always 가 0 이면 g:vimide_edit_route 를 따른다. <F6> 과 :Ex 처럼
" 늘 옮겨야 하는 것은 1 로 부른다.
func! s:GotoEditSlot(always) abort
	if !has('nvim') || !exists('*luaeval')
		return 1
	endif
	if !a:always && !get(g:, 'vimide_edit_route', 1)
		return 1
	endif
	if luaeval('_G.vimide_is_edit_win == nil and true or _G.vimide_is_edit_win()')
		return 1
	endif
	" '편집 자리' 를 묻는다. 진짜 EDIT 창이 없어도, BufExplorer 나 netrw 가
	" 잠시 빌려 쓰는 중인 창이 있으면 그 자리를 되찾아 쓴다.
	let l:w = luaeval('_G.vimide_edit_slot ~= nil and _G.vimide_edit_slot()'
				\ . ' or (_G.vimide_last_edit_win ~= nil and _G.vimide_last_edit_win() or 0)')
	if l:w > 0 && win_id2win(l:w) > 0
		call win_gotoid(l:w)
		return 1
	endif
	return 0
endfunc

func! s:InEditWin(cmd) abort
	if !s:GotoEditSlot(1)
		echohl WarningMsg
		echo 'vim-ide: EDIT 창이 없어 실행하지 않았습니다'
		echohl None
		return
	endif
	execute a:cmd
endfunc

" 아무 명령이나 EDIT 창에서 돌리고 싶을 때:  :VimIdeInEdit <명령>
command! -nargs=+ -complete=command VimIdeInEdit call s:InEditWin(<q-args>)

" F6 버퍼 목록
map <F6> :call <SID>InEditWin('BufExplorer')<CR>

" bufexplorer 는 '제 이름이 걸린 매핑이 없으면' 자기 기본 매핑을 만든다
" (\be \bt \bs \bv). <F6> 에 'BufExplorer' 가 들어 있어서 \be 는 안 생기지만
" 나머지 셋은 생기고, 그것들은 곁창에서 누르면 그 사이드바를 차지한다.
" 여기서 먼저 걸어 두면 (1) 그 자리를 EDIT 창으로 돌리고 (2) hasmapto() 가
" 참이 되어 플러그인이 제 것을 덧씌우지 않는다.
nnoremap <silent> <Leader>be :call <SID>InEditWin('BufExplorer')<CR>
nnoremap <silent> <Leader>bt :call <SID>InEditWin('ToggleBufExplorer')<CR>
nnoremap <silent> <Leader>bs :call <SID>InEditWin('BufExplorerHorizontalSplit')<CR>
nnoremap <silent> <Leader>bv :call <SID>InEditWin('BufExplorerVerticalSplit')<CR>

" netrw 목록에서 .h 를 다른 파일과 같이 이름순으로.
"
" netrw 기본 정렬 순서는 .h 를 .bak .o .swp .obj 와 한 묶음으로 보고 목록
" 맨 끝으로 보낸다. 실측(drivers/char, 항목 53개):
"
"   기본  : [\/]$,*,\(\.bak\|\~\|\.o\|\.h\|\.info\|\.swp\|\.obj\)[*@]\=$
"   결과  : ... tcc_ecid.c  tcc_mem.c ... virtio_console.c   <- .c 가 끝나고
"           applicom.h  nwbutton.h                           <- .h 는 맨 아래
"
" C 소스를 읽는 동안 헤더는 .c 만큼 자주 여는 파일이라, 목록 끝까지
" 내려가야 보이면 '안 나온다' 로 보인다. .h 만 그 묶음에서 뺀다 - 그러면
" '*'(나머지 전부) 에 들어가 이름순으로 섞인다. 디렉터리가 먼저인 것과
" 진짜 부산물(.o .swp .bak ~)이 끝으로 가는 것은 그대로다.
"
"   let g:netrw_sort_sequence = '[\/]$,*'   " 부산물도 섞으려면
let g:netrw_sort_sequence = '[\/]$,*,\(\.bak\|\~\|\.o\|\.info\|\.swp\|\.obj\)[*@]\=$'

" :Ex / :Explore (netrw, 또는 그것을 가로챈 nvim-tree) 도 EDIT 창에서.
"
" 명령을 덮어쓰면 그 안에서 원래 명령을 부를 때 제 자신을 다시 부른다.
" 그래서 명령줄 약어로 바꿔 준다 - 곁창이든 아니든 :Ex 를 치면 아래
" :VimIdeExplore 로 바뀌고, 그것이 EDIT 창으로 옮긴 뒤 진짜 :Explore 를 부른다.
" netrw(:Ex)는 자기 버퍼에 <unique> 로 <C-h> / <C-l> 을 걸려 한다. 그런데
" 이 설정은 그 둘을 창 이동(:wincmd h / l)에 전역으로 쓰고 있어서 충돌한다:
"   E225: Global mapping already exists for <C-h>
" 그러면 netrw 가 버퍼를 다 만들지 못한 채 죽어 :Ex 가 아무 창도 못 연다
" (실측: 이 설정에서 :Explore 가 늘 실패했다).
"
" 그 두 줄만 잠시 치웠다가 되돌린다. 창 이동 매핑을 내주지 않으면서 netrw 도
" 살리는 길이 이것뿐이다 - netrw 는 <unique> 를 조건 없이 쓴다.
func! s:Explore(cmd, args) abort
	let l:saved = {}
	for l:k in ['<C-h>', '<C-l>']
		let l:m = maparg(l:k, 'n', 0, 1)
		if !empty(l:m)
			let l:saved[l:k] = l:m
			execute 'silent! nunmap ' . l:k
		endif
	endfor
	try
		call s:InEditWin(a:cmd . ' ' . a:args)
	finally
		for [l:k, l:m] in items(l:saved)
			if exists('*mapset')
				silent! call mapset('n', 0, l:m)
			elseif has_key(l:m, 'rhs')
				execute 'silent! map ' . l:k . ' ' . l:m.rhs
			endif
		endfor
	endtry
endfunc

" 지금 곁창에 있는가. s:InEditWin 과 같은 잣대(_G.vimide_is_edit_win)를 쓴다.
"
" 진짜 vim 8.1 에는 그 판정기(lua)가 없다 - 거기서는 늘 0 이라 아래 약어가
" 아무것도 바꾸지 않는다. 서버에서는 예전 그대로 동작한다.
func! s:SideWin() abort
	if !get(g:, 'vimide_edit_route', 1)
		return 0
	endif
	if !has('nvim') || !exists('*luaeval')
		return 0
	endif
	return !luaeval('_G.vimide_is_edit_win == nil and true or _G.vimide_is_edit_win()')
endfunc

" 명령줄 약어 한 벌을 깐다.
"
"   a:full   진짜 명령 이름          'Explore'
"   a:short  잡기 시작할 가장 짧은 꼴 'Ex'  ->  Ex Exp Expl Explo Explor Explore
"   a:target 바꿔 칠 이름            'VimIdeExplore'
"   a:guard  1 이면 곁창에 있을 때만 바꾼다
"
" 왜 약어인가: 명령을 같은 이름으로 덮어쓰면 그 안에서 원래 명령을 부를 때
" 제 자신을 다시 부른다. 약어는 사람이 명령줄에 친 것에만 걸려서 그 고리가
" 없고, 스크립트의 :execute 'edit ...' 은 건드리지 않는다.
" 명령 앞에 붙을 수 있는 수식어. :vert Ex / :silent e . / :botright b 3
" 처럼 앞에 뭐가 붙어도 같은 길로 보내야 한다. 예전에는 '명령줄 전체가
" 그 낱말과 같은가' 만 봐서, :vert Ex 하나로 곁창이 그대로 쪼개졌다.
" 수식어 자체는 <mods> 로 그대로 넘겨 주니 :vert 의 뜻도 살아 있다.
let s:mod_pat = '\v^%(%(sil%[ent]!?|uns%[ilent]|verb%[ose]|noa%[utocmd]'
			\ . '|keepa%[lt]|keepj%[umps]|keepm%[arks]|keepp%[atterns]'
			\ . '|lock%[marks]|hid%[e]|conf%[irm]|bro%[wse]|leg%[acy]'
			\ . '|vert%[ical]|hor%[izontal]|lefta%[bove]|abo%[veleft]'
			\ . '|rightb%[elow]|bel%[owright]|to%[pleft]|bo%[tright]|tab)'
			\ . '!?\s+)*'

" 지금 명령줄이 '수식어들 + 이 낱말' 인가. 약어의 <expr> 에서 부른다.
func! s:RouteHit(key) abort
	if getcmdtype() !=# ':'
		return 0
	endif
	return getcmdline() =~# s:mod_pat . a:key . '$'
endfunc

" 깔아 둔 약어 장부. <CR> 가로채기(s:RouteCR)가 같은 표를 쓴다.
let s:route_map = {}
let s:route_guard = {}

func! s:RouteAbbrev(full, short, target, guard) abort
	let l:i = len(a:short)
	while l:i <= len(a:full)
		let l:k = strpart(a:full, 0, l:i)
		let s:route_map[l:k] = a:target
		let s:route_guard[l:k] = a:guard
		execute 'cnoreabbrev <expr> ' . l:k
					\ . ' (<SID>RouteHit("' . l:k . '")'
					\ . (a:guard ? ' && <SID>SideWin()' : '')
					\ . ') ? "' . a:target . '" : "' . l:k . '"'
		let l:i += 1
	endwhile
endfunc

" netrw 한 벌. :Ex 만이 아니라 쪼개 여는 것들도 같이 돌린다 - 곁창에서
" :Vex 를 치면 그 사이드바를 세로로 쪼개 거기에 목록을 편다.
" :Rexplore 는 뺀다. netrw 버퍼 안에서 '보던 디렉터리로 돌아가기' 라서
" EDIT 창으로 옮기면 뜻이 없어진다.
for s:x in ['Explore', 'Vexplore', 'Sexplore', 'Hexplore', 'Texplore',
			\ 'Lexplore', 'Ntree']
	execute 'command! -nargs=* -complete=dir VimIde' . s:x
				\ . " call s:Explore('<mods> " . s:x . "', <q-args>)"
	call s:RouteAbbrev(s:x, s:x ==# 'Explore' ? 'Ex' : strpart(s:x, 0, 3),
				\ 'VimIde' . s:x, 0)
	" :Ntree 는 netrw 가 '트리 꼴로 연다'. 곁창에서 치면 그 자리를 먹는다.
endfor
unlet! s:x

" 명령줄에서 <CR> 을 누를 때 한 번 더 거른다.
"
" 약어는 '사람이 그 낱말을 방금 칠 때' 만 걸린다. ':' <Up> 으로 예전 명령을
" 되부르거나 q: 창에서 실행하면 그냥 지나간다 - 곁창에 서서 예전 :Explore 를
" 되부르면 그 곁창이 netrw 목록으로 바뀌었다. 여기서 줄을 통째로 다시 써서
" 같은 길로 보낸다.
"
" setcmdline() 이 없는 vim(8.1)에서는 아무것도 하지 않는다. 거기서는 약어도
" 곁창 판정기도 없어서 예전 그대로다.
func! s:RouteCR() abort
	if getcmdtype() !=# ':' || !exists('*setcmdline')
		return "\<CR>"
	endif
	let l:line = getcmdline()
	let l:pre = matchstr(l:line, s:mod_pat)
	let l:rest = strpart(l:line, len(l:pre))
	let l:w = matchstr(l:rest, '^\a\+')
	if empty(l:w) || !has_key(s:route_map, l:w)
		return "\<CR>"
	endif
	if s:route_guard[l:w] && !s:SideWin()
		return "\<CR>"
	endif
	let l:tail = strpart(l:rest, len(l:w))
	let l:bang = strpart(l:tail, 0, 1) ==# '!' ? '!' : ''
	if !empty(l:bang)
		let l:tail = strpart(l:tail, 1)
	endif
	call setcmdline(l:pre . s:route_map[l:w] . l:bang . ' ' . l:tail)
	return "\<CR>"
endfunc
cnoremap <expr> <CR> <SID>RouteCR()

 " :only / <C-w>o 는 곁창까지 통째로 닫는다.
"
" 실측(178칸 F12 배치): EDIT 창에서 :only 한 번에 aerial / neo-tree /
" RelationView 패널 / context / overview 막대가 한꺼번에 사라지고 편집 창
" 하나만 남는다. 다시 세우려면 F12 와 F9/F10 을 손으로 눌러야 한다.
"
" 뜻은 살리되 범위를 편집 영역으로 좁힌다 - '편집 창을 하나로 합친다'.
" 곁창까지 진짜로 다 닫고 싶으면 :only! 로 예전 그대로 쓴다.
"
" 왜 '닫힌 뒤 되살리기' 가 아닌가: 닫히는 순간만 보고는 일부러 닫은 것과
" 딸려 닫힌 것을 가릴 수 없다. 실측한 여섯 가지 중
"   aerial 안에서 :q        -> 커서가 그 창에 있다
"   aerial 안에서 q(제 키)  -> 커서가 다른 창에 있다   <- 일부러인데
"   EDIT 에서 win_close()   -> 커서가 다른 창에 있다   <- 딸려인데 똑같다
" 둘이 구별되지 않는다. 그래서 되살리기를 만들면 aerial 에서 q 를 눌러도
" 도로 튀어나온다. 닫는 쪽을 고치는 것이 맞다.
"
"   let g:vimide_only_keeps_sides = 0   " :only 를 예전 그대로
func! s:OnlyEdit(bang) abort
	if !empty(a:bang) || !get(g:, 'vimide_only_keeps_sides', 1)
				\ || !has('nvim') || !exists('*luaeval')
		execute 'only' . a:bang
		return
	endif
	" 곁창에 선 채로 쳤으면 먼저 편집 자리로 옮긴다. 안 그러면 '이 창만
	" 남기기' 가 되어 편집 창이 전부 사라진다.
	if !s:GotoEditSlot(1)
		execute 'only' . a:bang
		return
	endif
	let l:keep = win_getid()
	for l:w in luaeval('_G.vimide_edit_wins ~= nil and _G.vimide_edit_wins() or {}')
		if l:w != l:keep && win_id2win(l:w) > 0
			execute win_id2win(l:w) . 'wincmd c'
		endif
	endfor
endfunc
command! -bang -bar VimIdeOnly call s:OnlyEdit('<bang>')
nnoremap <silent> <C-w>o :<C-u>VimIdeOnly<CR>
call s:RouteAbbrev('only', 'on', 'VimIdeOnly', 0)

" '지금 창'에 버퍼를 들이는 명령들. 곁창에서 치면 EDIT 창으로 돌린다.
"
" :e . 이 특히 나쁘다. nvim 0.12 에는 netrw 대신 NERDTree 가 디렉터리를
" 가로채는데, 곁창을 차지하는 데 그치지 않고 그 창을 아예 없앤다.
" 실측(개발서버, nvim 0.12.4):
"   aerial 창에서 :e .  -> aerial 이 사라지고 NERDTree 가 열150 에 새로 뜸
"   quickfix 창에서     -> quickfix 가 사라지고 NERDTree 가 새로 뜸
"   RelationView 패널   -> winfixbuf 라 E1513 만 나고 아무 일도 안 남
" 사후 복구(vimidewin.lua)로는 이것을 못 잡는다 - 되돌릴 창이 이미 없다.
"
" EDIT 창에서 친 것은 글자 하나 건드리지 않는다. :e 는 하루에 백 번 치는
" 명령이라 거기서까지 남의 이름으로 갈아 두면 <Tab> 파일 이름 완성처럼
" 미묘한 것이 조금만 달라져도 바로 걸림돌이 된다.
for s:r in [
			\ ['edit',      'e',   'file'],
			\ ['enew',      'ene', 'file'],
			\ ['find',      'fin', 'file_in_path'],
			\ ['view',      'vie', 'file'],
			\ ['buffer',    'b',   'buffer'],
			\ ['bnext',     'bn',  'buffer'],
			\ ['bprevious', 'bp',  'buffer'],
			\ ['sbuffer',   'sb',  'buffer'],
			\ ['bdelete',   'bd',  'buffer'],
			\ ['bwipeout',  'bw',  'buffer'],
			\ ['help',      'h',   'help'],
			\ ['tag',       'ta',  'tag'],
			\ ['tjump',     'tj',  'tag'],
			\ ['tselect',   'ts',  'tag'],
			\ ['BufExplorer',       'BufE',    'buffer'],
			\ ['ToggleBufExplorer', 'ToggleB', 'buffer'],
			\ ['terminal',  'ter',   ''],
			\ ['cnext',     'cn',    ''],
			\ ['cprevious', 'cp',    ''],
			\ ['cc',        'cc',    ''],
			\ ['cfirst',    'cfir',  ''],
			\ ['clast',     'cla',   ''],
			\ ['lnext',     'lne',   ''],
			\ ['lprevious', 'lp',    ''],
			\ ['ll',        'll',    ''],
			\ ['next',      'nex',   'file'],
			\ ['previous',  'prev',  'file'],
			\ ['pop',       'po',    ''],
			\ ['tnext',     'tn',    ''],
			\ ['tprevious', 'tp',    ''],
			\ ['sview',     'sv',    'file'],
			\ ['sfind',     'sf',    'file_in_path'],
			\ ['diffsplit', 'diffs', 'file'],
			\ ['Man',       'Man',   ''],
			\ ]
	let s:cmd = s:r[0]
	let s:nm = 'VimIde' . toupper(s:cmd[0]) . s:cmd[1:]
	execute 'command! -nargs=* -bang '
				\ . (empty(s:r[2]) ? '' : '-complete=' . s:r[2] . ' ') . s:nm
				\ . " call s:InEditWin('<mods> " . s:cmd . "<bang> ' . <q-args>)"
	call s:RouteAbbrev(s:cmd, s:r[1], s:nm, 1)
endfor
unlet! s:r s:cmd s:nm
" <F7> 은 \fs 와 같은 :ProjectSymbols (색인된 심볼 검색).
" <F8> 은 커서 밑 심볼에 노란 표시를 붙이고 뗀다 (yellowmark.lua).
" 예전에는 <F7> 이 'v]}zf'(함수 본문 접기), <F8> 이 'zo'(펼치기) 였다.
" 접기는 zf 와 za/zo/zc 가 그대로 한다.
"
" 먼저 해제한다: 예전 'map <F7>'/'map <F8>' 은 normal 뿐 아니라
" visual/operator 에도 걸려 있어서, 실행 중에 :source ~/.vimrc 하면
" nnoremap 이 normal 만 덮고 나머지 모드에 옛 접기 동작이 남는다.
silent! unmap <F7>
silent! unmap <F8>
nnoremap <silent> <F7> :ProjectSymbols<CR>
nnoremap <silent> <F8> <Cmd>lua _G.yellowmark_toggle()<CR>
"map <F9> :TagbarToggle<CR>
"map <F10> :CocCommand explorer<CR>
"map <F10> :NvimTreeToggle<CR>
"map <F10> :NERDTreeToggle<CR>
"map <F11> :call NERDTree_and_Tagbar_Toggle()<CR>
" F9 = neo-tree(왼쪽), F11 = NERDTree(오른쪽).
"
" 왼쪽은 아웃라인(aerial)도 쓰는 자리라 NeoTreeOnlyLeft 가 그것을 닫는다.
" 오른쪽은 RelationView 의 context 창이 쓰는데, NERDTree 는 토글이라
" 필요할 때만 잠깐 겹친다.
map <F9> :call NeoTreeOnlyLeft()<CR>
"map <F9> :call NeoTreeOnlyRight()<CR>
map <F10> :call TagbarOnly()<CR>
"map <F11> :call NERDTreeOnlyLeft()<CR>
" F11: neo-tree 를 telescope 처럼 '떠 있는 창' 으로 연다.
"
" 곁창으로 세우면 배치가 밀리는데, 파일을 하나 고르러 잠깐 여는 트리는
" 그럴 이유가 없다. 부동 창은 배치를 건드리지 않고 뜨고, 곁창 지킴이도
" 부동 창은 애초에 지키지 않는다(vimidewin.lua 의 remember).
"
" 옆에 세워 두고 쓰고 싶으면 F9(왼쪽) 를 쓰거나 아래 줄을 살리면 된다.
"map <F11> :call NeoTreeOnlyRight()<CR>
"map <F11> :call NERDTreeOnlyRight()<CR>
func! NeoTreeFloat() abort
	NeotreeGuarded toggle float
endfunc
map <F11> :call NeoTreeFloat()<CR>
"map <F11> :call NERDTree_and_Tagbar_Toggle()<CR>
"map <F12> :!time ctags -R;time gtags;time mktags.sh<CR>
" <F12> 는 이제 RelationView 를 켜고 끈다(예전 <F3>). relationview.lua 가
" 건다 - 여기서 F12 를 다시 잡으면 그쪽이 덮인다.
" Deltags 는 명령으로 그대로 쓸 수 있다:  :call Deltags()
" 다른 키에 걸고 싶으면 아래 줄을 살려서 키만 바꾸면 된다.
"map <F12> :call Deltags()<CR>
map ,pa :set paste<CR>		"paste
map ,np :set nopaste<CR>	"nopaste

" quickfix window control
nmap ,o :copen<CR>
nmap ,c :cclose<CR>

" Show quickfix window with full width
botright cwindow




" ------------------------------------
" :Restore - 진짜 vim 에서도 세션을 연다
" ------------------------------------
" 세션을 저장하는 쪽은 .vim/plugin/vimidesession.lua 이고 그것은 nvim 전용이다
" (vim 은 .vim/plugin/*.lua 를 읽지 않는다). 그래서 진짜 vim 에서 'vim +Restore'
" 를 치면 이렇게 됐다:
"
"   E492: Not an editor command: Restore
"   Press ENTER or type command to continue
"
" 느린 것이 아니라 키를 기다리고 있는 것인데, 시작이 멈춰 선 것처럼 보인다.
" 실측: exists(':Restore') 가 vim 에서 0 이었다.
"
" 세션 파일 자체는 :mksession 이 쓴 평범한 vimscript 라 vim 이 그대로 읽는다
" (실측: 44버퍼짜리를 source 해서 에러 0). 이름 규칙만 같이 맞춰 주면 된다 -
" '<경로를 +로 바꾼 꼬리 80자>-<sha256 앞 12자>.vim', nvim 의 stdpath('state')
" 아래. vim 에도 sha256() 이 있다(확인함).
if !has('nvim')
	" 프로젝트 루트. nvim 쪽(projectfiles.lua 의 root_from_dir)과 같은 판정을
	" 써야 한다 - 다르면 세션 파일 이름이 갈려서 'vim 으로 저장한 것을 vim 이
	" 못 찾는' 일이 난다.
	"
	" 실측으로 한 번 당했다: 처음에는 isdirectory('.tags') 만 봤더니 GTAGS 도
	" 없는 빈 /tmp/.tags 에 걸려 /tmp 를 루트로 잡았다. 순서는 이렇다.
	"   1) 색인이 있는 가장 가까운 위 (<d>/.tags/GTAGS 또는 <d>/GTAGS)
	"   2) 없으면 표식 (.git / .project / .root)
	"   3) 그것도 없으면 지금 디렉터리
	func! s:VimIdeSessRoot() abort
		let l:d = getcwd()
		" '<root>/.tags' 안에서 띄웠으면 거기서 나온다
		while l:d =~# '/\.tags$'
			let l:d = fnamemodify(l:d, ':h')
		endwhile
		let l:x = l:d
		while !empty(l:x)
			if filereadable(l:x . '/.tags/GTAGS') || filereadable(l:x . '/GTAGS')
				return l:x
			endif
			let l:p = fnamemodify(l:x, ':h')
			if l:p ==# l:x
				break
			endif
			let l:x = l:p
		endwhile
		let l:x = l:d
		while !empty(l:x)
			for l:m in ['.git', '.project', '.root']
				if isdirectory(l:x . '/' . l:m) || filereadable(l:x . '/' . l:m)
					return l:x
				endif
			endfor
			let l:p = fnamemodify(l:x, ':h')
			if l:p ==# l:x
				break
			endif
			let l:x = l:p
		endwhile
		return getcwd()
	endfunc

	func! s:VimIdeSessFile() abort
		let l:root = substitute(fnamemodify(s:VimIdeSessRoot(), ':p'), '/\+$', '', '')
		let l:tail = substitute(l:root, '[^0-9A-Za-z._-]', '+', 'g')
		if strlen(l:tail) > 80
			let l:tail = strpart(l:tail, strlen(l:tail) - 80)
		endif
		let l:dir = get(g:, 'vimide_session_dir',
					\ $HOME . '/.local/state/nvim/vim-ide/sessions')
		if !exists('*sha256')
			return ''
		endif
		return expand(l:dir) . '/' . l:tail . '-' . strpart(sha256(l:root), 0, 12) . '.vim'
	endfunc

	" vim 은 제 세션을 따로 쓴다.
	"
	" nvim 쪽 파일을 같이 쓰면 서로 덮는다 - nvim 세션에는 패널 상태를 담은
	" x.vim 이 딸려 있는데 vim 은 그것을 만들 수 없어서, vim 이 저장한 뒤
	" nvim 으로 열면 배치와 패널이 어긋난 짝이 된다. 파일을 갈라 두면 각자
	" 마지막 상태로 돌아간다.
	func! s:VimIdeSessFileVim() abort
		let l:f = s:VimIdeSessFile()
		return empty(l:f) ? '' : substitute(l:f, '\.vim$', '-vim.vim', '')
	endfunc

	" 나갈 때 적어 둔다. 이것이 없어서 'vim +Restore 가 이전 상태로 안
	" 돌아온다'가 났다 - 세션을 쓰는 쪽(vimidesession.lua)이 nvim 전용이라,
	" vim 으로 끝낸 상태는 어디에도 기록되지 않았다.
	func! s:VimIdeSessSave() abort
		if get(g:, 'vimide_session_save', 1) == 0
			return
		endif
		let l:f = s:VimIdeSessFileVim()
		if empty(l:f)
			return
		endif
		" 파일을 담은 창이 하나도 없으면 덮지 않는다. 빈 배치를 적으면
		" :mksession 이 edit 줄을 하나도 안 남겨 창 배치가 통째로 사라진다
		" (nvim 쪽에서 실제로 그렇게 잃었다).
		let l:has = 0
		for l:w in range(1, winnr('$'))
			if empty(getwinvar(l:w, '&buftype')) && !empty(bufname(winbufnr(l:w)))
				let l:has = 1
				break
			endif
		endfor
		if !l:has && filereadable(l:f)
			return
		endif
		call mkdir(fnamemodify(l:f, ':h'), 'p')
		if filereadable(l:f)
			call rename(l:f, l:f . '.bak')
		endif
		let l:so = &sessionoptions
		" options/localoptions 는 넣지 않는다 - 세션이 .vimrc 를 이겨서
		" 설정을 고쳐도 반영이 안 된다. nvim 쪽과 같은 생각이다.
		set sessionoptions=buffers,curdir,folds,help,tabpages,winsize
		try
			execute 'mksession! ' . fnameescape(l:f)
		catch
		finally
			let &sessionoptions = l:so
		endtry
	endfunc
	augroup VimIdeSessionVim
		autocmd!
		autocmd VimLeavePre * call s:VimIdeSessSave()
	augroup END

	func! s:VimIdeRestore() abort
		" vim 이 적어 둔 것이 있으면 그것을, 없으면 nvim 것을 읽는다.
		let l:f = s:VimIdeSessFileVim()
		if empty(l:f) || !filereadable(l:f)
			let l:f = s:VimIdeSessFile()
		endif
		if empty(l:f)
			echohl WarningMsg
			echo '이 vim 에는 sha256() 이 없어 세션 이름을 맞출 수 없습니다'
			echohl None
			return
		endif
		if empty(l:f) || !filereadable(l:f)
			echohl WarningMsg
			echo '저장된 세션이 없습니다: ' . (empty(l:f) ? '?' : fnamemodify(l:f, ':t'))
			echohl None
			echo '(vim 과 nvim 모두 :qa 로 나갈 때 저장합니다)'
			return
		endif
		try
			execute 'silent source ' . fnameescape(l:f)
			echo '세션 복원: ' . fnamemodify(l:f, ':t')
		catch
			echohl WarningMsg
			echo '세션을 여는 중 멈췄습니다: ' . v:exception
			echohl None
		endtry
	endfunc

	" vim 은 제 파일(-vim.vim)에 쓰고 읽는다. nvim 것은 없을 때만 읽는다.
	" -bar 를 준다. 없으면 ':Restore | 다른명령' 이 E488 로 깨진다
	" (사용자 명령은 -bar 가 없으면 줄의 나머지를 통째로 삼킨다).
	command! -bar Restore call s:VimIdeRestore()

	" 어느 파일을 보고 있는지. nvim 쪽 :VimIdeSessionWhere 와 짝이다 -
	" vim 과 nvim 이 프로젝트 루트를 다르게 보면 세션이 갈리는데, 그것을
	" 눈으로 맞춰 볼 데가 있어야 한다.
	func! s:VimIdeSessWhere() abort
		let l:v = s:VimIdeSessFileVim()
		let l:n = s:VimIdeSessFile()
		echo 'root = ' . s:VimIdeSessRoot()
		echo 'vim  = ' . l:v . (filereadable(l:v) ? '' : '   (없음)')
		echo 'nvim = ' . l:n . (filereadable(l:n) ? '' : '   (없음)')
	endfunc
	command! -bar VimIdeSessionWhere call s:VimIdeSessWhere()
endif
