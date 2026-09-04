scripte utf-8
" vim: set fenc=utf-8 tw=0:

"==============================================================================
" General
"==============================================================================

" Revert all command settings before proceeding with other settings below
set all&

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

" Wait for a key code forever.
" Wait for a mapped key sequence to complete within ttimeoutlen.
set notimeout ttimeout

" In Milliseconds
set timeoutlen=3000 ttimeoutlen=100

" Not redraw while executing macros, and commands.
set lazyredraw

"set visualbell

" Turn on syntax highlighting
syntax on

set backspace=indent,eol,start " for backspace
"set termguicolors

"==============================================================================
" Vim Plugin Settings
"==============================================================================

" Load plugins when starting up
set loadplugins

filetype off                   " required!

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
Plug 'preservim/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'preservim/tagbar'
Plug 'vim-utils/vim-troll-stopper'
Plug 'Raimondi/delimitMate'
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
" Source Insight 스타일: ctags 자동 색인 / 심볼 아웃라인 / 파일 트리
Plug 'ludovicchabant/vim-gutentags'
Plug 'stevearc/aerial.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'nvim-neo-tree/neo-tree.nvim', { 'branch': 'v3.x' }

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
	}
}
require'telescope'.load_extension'fzf'
EOF

" ------------------------------------
" Neogit (Magit for nvim) + diffview
"   <leader>s : Neogit 상태 화면(새 탭)  -  s/u 스테이징, cc 커밋, P 푸시
"   <leader>v : DiffviewOpen (작업 트리 전체 diff)
"   (<leader>m 은 vim-mark 가 이미 쓰고 있어 s(tatus) 로 두었다)
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
rv_setup('diffview', {})
EOF
nnoremap <silent> <Leader>s <Cmd>Neogit<CR>
nnoremap <silent> <Leader>v <Cmd>DiffviewOpen<CR>

" ------------------------------------
" aerial: 현재 파일의 심볼 아웃라인(Source Insight 의 Symbol Window)
"   <leader>o 로 토글. treesitter 백엔드라 LSP 없이도 동작한다.
"   (F10 의 tagbar 는 그대로 유지 - 둘 중 편한 것을 쓰면 된다)
" ------------------------------------
lua << EOF
_G.rv_setup('aerial', {
  backends = { 'treesitter', 'lsp', 'markdown', 'man' },
  layout = { default_direction = 'right', width = 32 },
  attach_mode = 'window',
  close_on_select = false,
  show_guides = true,
})
EOF
nnoremap <silent> <Leader>o <Cmd>AerialToggle<CR>

" 프로젝트 전역 심볼 검색(소스인사이트의 Ctrl+O). tags 파일 기반이라
" gutentags 가 만든 색인을 그대로 쓴다. LSP(clangd) 를 켜면
" ':Telescope lsp_workspace_symbols' 도 함께 쓸 수 있다.
nnoremap <silent> <Leader>fs <Cmd>Telescope tags<CR>

" ------------------------------------
" neo-tree: 사이드바 파일 트리 (NERDTree 상위 호환)
"   F9 또는 <leader>t 로 토글. a 생성 / d 삭제 / r 이름변경 / ? 도움말
"   (F11 은 그대로 NERDTree 오른쪽 창)
"   netrw 는 nvim-tree 가 이미 가로채므로 neo-tree 는 건드리지 않는다.
"   대용량 트리에서 발열/지연이 없도록 git status 는 비동기, 파일
"   watcher 는 끈다.
" ------------------------------------
lua << EOF
_G.rv_setup('neo-tree', {
  close_if_last_window = true,
  enable_git_status = true,
  enable_diagnostics = false,
  git_status_async = true,
  window = { position = 'left', width = 32 },
  filesystem = {
    hijack_netrw_behavior = 'disabled',
    use_libuv_file_watcher = false,
    follow_current_file = { enabled = true },
    filtered_items = {
      visible = true,
      hide_dotfiles = false,
      hide_gitignored = false,
    },
  },
})
EOF
nnoremap <silent> <Leader>t <Cmd>Neotree toggle<CR>

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
			\ '*.so', '*.ko', '*.cmd', 'GTAGS', 'GRTAGS', 'GPATH']

" ------------------------------------
" autoindex.lua: GTAGS 자동 색인
"   * vim 을 켜면 현재 프로젝트 색인을 백그라운드로 갱신한다
"     (있으면 증분 'gtags -i', 없으면 전체 빌드. 커널 69k 파일 기준
"      변경이 없으면 2초, 전체 빌드는 26초 정도)
"   * 파일을 저장하면 그 파일만 즉시 갱신한다
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
nmap <Leader><Leader>c :Gtags -r <C-R>=expand("<cword>") <CR><CR>
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
nmap <C-n> :cn<CR>
nmap <C-p> :cp<CR>
"nmap <C-h> :.,$s/<C-R>=expand("<cword>")<CR>//gc<SPACE>
nmap <C-\><C-]> :GtagsCursor<CR>
nmap <C-]> :Gtags -d <C-R>=expand("<cword>") <CR><CR>
nmap <C-t> <C-o><CR>

"------------------------------------------------------------------------------
"- 마우스 더블클릭 = <C-]> (심볼 정의로 점프)
"- '#include "foo.h"' / '#include <a/b.h>' 줄에서는 그 헤더 파일을 연다.
"- quickfix, NERDTree, Tagbar, RelationView 등 특수 창은 각자의 동작을 유지한다
"- (버퍼 로컬 매핑이 우선하고, buftype 이 빈 일반 파일 창에서만 아래가 동작).
"------------------------------------------------------------------------------
function! s:RvMouseJump() abort
	" 특수 버퍼(quickfix, help, terminal ...)는 기본 더블클릭 동작 유지
	if &buftype !=# ''
		execute "normal! \<2-LeftMouse>"
		return
	endif
	" #include 줄이면 그 헤더로 이동 (nvim + relationview.lua 가 있을 때)
	if has('nvim') && exists('*luaeval')
		try
			if luaeval('_G.relationview_open_include ~= nil and _G.relationview_open_include() or false')
				return
			endif
		catch
		endtry
	endif
	" 그 밖에는 커서 아래 심볼로 점프 (<C-]> 매핑을 그대로 사용)
	if expand('<cword>') =~# '^[A-Za-z_][A-Za-z0-9_]*$'
		execute "normal \<C-]>"
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
nnoremap <X1Mouse> <C-o>
nnoremap <X2Mouse> <C-i>

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
    " no gtags equivalent for 'functions called by' -> open the
    " RelationView caller tree instead
    nmap <Leader><Leader>d :RelationView<CR>
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
let g:mwDefaultHighlightingPalette = 'maximum'
"let g:mwDefaultHighlightingPalette = 'extended'
"let g:mwDefaultHighlightingNum = 3

"==============================================================================
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
map <C-h> :wincmd h<cr>
map <C-l> :wincmd l<cr>
map <C-k> :wincmd k<cr>
map <C-j> :wincmd j<cr>


"===== 버퍼?????동
map ,r :bn!<CR>	  " Switch to Next File Buffer
map ,e :bp!<CR>	  " Switch to Previous File Buffer
map ,w :bw!<CR>	  " Close Current File Buffer

map ,1 :b!1<CR>	  " Switch to File Buffer #1
map ,2 :b!2<CR>	  " Switch to File Buffer #2
map ,3 :b!3<CR>	  " Switch to File Buffer #3
map ,4 :b!4<CR>	  " Switch to File Buffer #4
map ,5 :b!5<CR>	  " Switch to File Buffer #5
map ,6 :b!6<CR>	  " Switch to File Buffer #6
map ,7 :b!7<CR>	  " Switch to File Buffer #7
map ,8 :b!8<CR>	  " Switch to File Buffer #8
map ,9 :b!9<CR>	  " Switch to File Buffer #9
map ,0 :b!0<CR>	  " Switch to File Buffer #0


"===== text change
nmap ,H :%s/<C-R>=expand("<cword>")<CR>/
nmap ,ch :.,$s/<C-R>=expand("<cword>")<CR>/

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
endif
"let g:tagbar_left=0
let g:tagbar_left=1
let g:tagbar_sort=0
"let g:tagbar_width=30
function! AutoLoadTagbar()
	exe 'Tagbar'
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

"==============================================================================
"= RelationView: Source Insight style relation window (nvim only)
"  F3 toggle / :RelationView - see ~/.vim/plugin/relationview.lua
"==============================================================================
if has('nvim') && filereadable(expand('$HOME/.vim/plugin/relationview.lua'))
    execute 'source' fnameescape(expand('$HOME/.vim/plugin/relationview.lua'))
endif

" g:relationview_position   'bottom' (default) or 'right'
let g:relationview_position = 'right'
" g:relationview_auto_open  1: open the panel on startup (default 1)
let g:relationview_auto_open = 1
let g:relationview_width = 80
let g:relationview_context_height = 40
let g:relationview_show_text = 0


"==============================================================================
"= my setting
"==============================================================================
set mouse=a
set path+=/root/work/include,/usr/include,/usr/local/include,/usr/src/include
set path+=./include,./include/linux

"colorscheme desertEx
"colorscheme badwolf
colorscheme jellybeans

"==============================================================================
"= Cursor line
"= jellybeans paints CursorLine one single shade above the background
"= (ctermbg 234 on 233), which is invisible, and leaves it off in edit
"= windows. Turn it on everywhere and make the focused line actually stand
"= out. Re-applied on every :colorscheme so it never gets wiped.
"= Tune these three lines if you want it stronger or weaker.
"==============================================================================
set cursorline

function! s:RvCursorLineColors() abort
    highlight CursorLine     term=NONE cterm=NONE ctermbg=238 guibg=#343a45
    highlight CursorLineNr   cterm=bold ctermbg=238 ctermfg=117
                \ gui=bold guibg=#343a45 guifg=#87d7ff
    " the relation/context windows use a slightly stronger bar for the row
    " under the panel cursor (see ~/.vim/plugin/relationview.lua)
    highlight RvCursorLine   cterm=NONE ctermbg=240 guibg=#4e5561
    highlight RvCursorLineNr cterm=bold ctermbg=240 ctermfg=117
                \ gui=bold guibg=#4e5561 guifg=#87d7ff
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
nnoremap <silent> <C-g> :Grep<CR>
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

func! NERDTreeOnlyLeft()
	:TagbarClose
	let g:NERDTreeWinPos="left"
	:NERDTreeToggle
endfunc

func! NERDTreeOnlyRight()
	let g:NERDTreeWinPos="right"
	:NERDTreeToggle
endfunc

" F9: neo-tree on the left (tagbar 도 왼쪽이라 함께 열면 좁아서 닫는다).
" 예전 NERDTree 왼쪽 창이 필요하면 :call NERDTreeOnlyLeft() 로 그대로 쓸 수 있다.
func! NeoTreeOnlyLeft()
	:TagbarClose
	:Neotree toggle left
endfunc
func! NeoTreeOnlyRight()
	:Neotree toggle right
endfunc

func! NERDTreeOnly()
	:TagbarClose
	:NERDTreeToggle
endfunc

func! TagbarOnly()
	:NERDTreeClose
	:Neotree close
	:TagbarToggle
endfunc

func! NERDTree_and_Tagbar_Toggle()
	:NERDTreeClose
	:TagbarToggle
endfunc

"map <F1> :call Man()<cr><cr>
map <F1> :!man <C-R>=expand("<cword>") <cr><cr>
map <F2> :call Maketags()<cr><cr>
map <F4> <Plug>MarkSet
map <F5> :MarkClear<CR> :noh<CR>
map <F6> :BufExplorer<CR>
map <F7> v]}zf
map <F8> zo
"map <F9> :TagbarToggle<CR>
"map <F10> :CocCommand explorer<CR>
"map <F10> :NvimTreeToggle<CR>
"map <F10> :NERDTreeToggle<CR>
"map <F11> :call NERDTree_and_Tagbar_Toggle()<CR>
map <F9> :call NERDTreeOnlyLeft()<CR>
"map <F9> :call NeoTreeOnlyLeft()<CR>
map <F10> :call TagbarOnly()<CR>
"map <F11> :call NERDTreeOnlyRight()<CR>
map <F11> :call NeoTreeOnlyRight()<CR>
"map <F11> :call NERDTree_and_Tagbar_Toggle()<CR>
"map <F12> :!time ctags -R;time gtags;time mktags.sh<CR>
map <F12> :call Deltags()<CR>
map ,pa :set paste<CR>		"paste
map ,np :set nopaste<CR>	"nopaste

" quickfix window control
nmap ,o :copen<CR>
nmap ,c :cclose<CR>

" Show quickfix window with full width
botright cwindow



