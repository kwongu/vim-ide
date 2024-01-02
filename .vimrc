scripte utf-8
" vim: set fenc=utf-8 tw=0:

"==============================================================================
" General
"==============================================================================

" Revert all command settings before proceeding with other settings below
set all&

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
"Plugin 'SirVer/ultisnips'
"Plugin 'honza/vim-snippets'
"Plugin 'airblade/vim-gitgutter'
"Plugin 'altercation/vim-colors-solarized'
"Plugin 'ludovicchabant/vim-gutentags'
"Plugin 'skywind3000/gutentags_plus'
"Plugin 'terryma/vim-multiple-cursors'

call vundle#end()
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
set term=xterm-256color
"set t_Co=256
"let g:airline_powerline_fonts = 1
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
noremap <silent> <c-b> :call smooth_scroll#up(&scroll*2, 10, 8)<CR>
noremap <silent> <c-f> :call smooth_scroll#down(&scroll*2, 10, 8)<CR>
noremap <silent> <c-u> :call smooth_scroll#up(&scroll, 10, 5)<CR>
noremap <silent> <c-d> :call smooth_scroll#down(&scroll, 10, 5)<CR>


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
let g:quickr_cscope_db_file = "GTAGS"
let g:quickr_cscope_keymaps = 0
let g:quickr_cscope_autoload_db = 1
let g:quickr_cscope_use_qf_g = 1

nmap <leader><leader>g <plug>(quickr_cscope_global)
nmap <leader><leader>s <plug>(quickr_cscope_symbols)
nmap <leader><leader>c <plug>(quickr_cscope_callers)
nmap <leader><leader>f <plug>(quickr_cscope_files)
nmap <leader><leader>i <plug>(quickr_cscope_includes)
"nmap <leader><leader>t <plug>(quickr_cscope_text)
nmap <leader><leader>d <plug>(quickr_cscope_functions)
nmap <leader><leader>e <plug>(quickr_cscope_egrep) <C-R>=expand("<cword>") <CR><CR>
nmap <leader><leader>a <plug>(quickr_cscope_assignments)

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
nmap <C-]> :GtagsCursor<CR>
nmap <C-t> <C-o><CR>

nnoremap <Leader>g <ESC>:Gtags<SPACE>
nnoremap <leader>e <plug>(quickr_cscope_egrep) <C-R>=expand("<cword>") <CR>
nnoremap <leader>f <plug>(quickr_cscope_files) <C-R>=expand("<cword>") <CR>
"nnoremap <Leader>e <ESC>:Cscope<SPACE>e<SPACE><C-R>=expand("<cword>")<CR>
"nnoremap <Leader>e <ESC>:GscopeFind<SPACE>e<SPACE><C-R>=expand("<cword>")<CR>

"==============================================================================
" gutentags key map
"==============================================================================

"" Set vim-gutentags and gutentags_plus
"let g:gutentags_project_root = ['.root', 'README', '.git']
"let g:gutentags_cache_dir = expand('~/.cache/tags')
"let g:gutentags_modules = ['ctags', 'gtags_cscope']
""let g:gutentags_add_default_project_roots = 0
""let g:gutentags_trace = 1
""let g:gutentags_define_advanced_commands = 1
""let g:gutentags_enabled = 0
""let g:GtagsCscope_Auto_Load = 1
""let g:gutentags_background_update = 0
""let g:gutentags_exclude_filetypes = []

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

"" To know when Gutentags is generating tags
"set statusline+=%{gutentags#statusline()}

" To avoid conflict ctags key map
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
nmap <Leader>ht :GitGutterLineHighlightsToggle<CR>


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
"let NERDTreeWinPos="right"
let NERDTreeWinPos="left"
let g:NERDTreeWinSize=25
let g:NERDTreeDirArrows=0
function! AutoLoadNERDTree()
	exe 'NERDTree'
endfunction
"autocmd VimEnter * call AutoLoadNERDTree()

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
au BufEnter /* call LoadCscope()

set tags=tags;/


"==============================================================================
"= Check Symbol
"==============================================================================
source ${HOME}/.vim/plugin/checksymbol.vim


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
" Shortcuts
"==============================================================================

" Help man
func! Man()
	let sm = expand("<cword>")
	exe "!man -S 2:3:4:5:6:7:8:9:tcl:n:l:p:o ".sm
endfunc

func! Maketags()
	":!find * \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' \) -print > cscope.files
	"exe "!time ctags -L cscope.files"
	"exe "!time gtags -f cscope.files"
	:!time mktags.sh .
endfunc

func! Deltags()
	exe "!time rm -f cscope.files cscope.out GPATH GRTAGS GTAGS tags"
endfunc

map <F1> :call Man()<cr><cr>
map <F2> :call Maketags()<cr><cr>
map <F4> <Plug>MarkSet
map <F5> :MarkClear<CR> :noh<CR>
map <F6> :BufExplorer<CR>
map <F7> v]}zf
map <F8> zo
map <F9> :NERDTreeToggle<CR>
map <F10> :TagbarToggle<CR>
"map <F12> :!time ctags -R;time gtags;time mktags.sh<CR>
map <F12> :call Deltags()<CR>
map ,pa :set paste<CR>		"paste
map ,np :set nopaste<CR>	"nopaste

" quickfix window control
nmap ,o :copen<CR>
nmap ,c :cclose<CR>

" Show quickfix window with full width
botright cwindow



