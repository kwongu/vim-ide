#!/bin/sh

echo "### vim install start ###"

VIMIDE=${HOME}/.vim-ide

# ---------------------------------------------------------------------------
# 필요한 프로그램부터 본다 (tools/deps.sh)
# ---------------------------------------------------------------------------
# 예전에는 'command -v <이름>' 으로 있는지만 봤다. 그러면 낡은 것이 통과한다 -
# 개발서버의 git 2.25.1 이 그랬고, diffview 는 2.31 이상이라 \v 가 아무 말
# 없이 아무 일도 하지 않았다. 없는 것보다 낡은 것이 알아내기 어렵다.
#
# 이제 판까지 보고, 모자라면 이 기계에 맞는 길로 채운다:
#   맥      brew
#   우분투  암호 없이 sudo 가 되면 apt, 안 되면 홈($HOME/.local)에만
#   그 밖   무엇을 치면 되는지만 적는다
#
#   VIMIDE_DEPS=0 ./install.sh     확인만 하고 설치하지 않는다
#   tools/deps.sh --check          설치 없이 확인만
#   tools/deps.sh --list           무엇이 왜 필요한지
if [ -x "${VIMIDE}/tools/deps.sh" ]; then
	"${VIMIDE}/tools/deps.sh" || true
	echo
fi

if [ -e ${HOME}/.vimrc -o -e ${HOME}/.vim ]; then
	echo "note: 설치를 진행하려면 ${HOME}/.vim/ 디렉토리와 ${HOME}/.vimrc 기존 파일이 없어야 합니다."
	echo "Note:  ${HOME}/.vim/ 디렉토리와 ${HOME}/.vimrc 파일을 ${HOME}/.oldvim 디렉토리로 백업합니다."

	rm -rf ${HOME}/.oldvim
	mkdir -p ${HOME}/.oldvim
	mv -f ${HOME}/.vimrc ${HOME}/.vim ${HOME}/.oldvim
fi

cd ${VIMIDE}
mkdir -p ${HOME}/.local/bin
cp -rf ${VIMIDE}/.local/bin/* ${HOME}/.local/bin

# The symbol databases live in '<project>/.tags/'. vim and nvim export
# GTAGSOBJDIR themselves (.vimrc); a shell needs it once to run 'global' or
# 'gtags-cscope' by hand.
if ! (env | grep -q '^GTAGSOBJDIR='); then
	echo "tip: 터미널에서 global 을 쓰려면  echo 'export GTAGSOBJDIR=.tags' >> ~/.zshenv"
	echo "     (한 번만; 현재 셸에는  eval \"\$(gtagsenv.sh)\" )"
fi
ln -sf ${VIMIDE}/.vim ${HOME}/.vim
ln -sf ${VIMIDE}/.vimrc ${HOME}/.vimrc
vim +PluginInstall +qall

# Preinstall for vim
if [ ! -e ${HOME}/.local/bin/vim ]; then
cd ${VIMIDE}/.program
git clone https://github.com/vim/vim.git
cd vim
./configure --prefix=${HOME}/.local --enable-python3interp=yes --enable-pythoninterp=yes --with-features=huge --enable-multibyte --with-vim-name=vim
make -j8 && make install
cd -
rm -rf vim
fi

# Preinstall for navigation symbols
if [ ! -e ${HOME}/.local/bin/cscope ]; then
cd ${VIMIDE}/.program
tar xvzf cscope-15.9.tar.gz
cd cscope-15.9
./configure --prefix=${HOME}/.local
make -j8 && make install
cd -
rm -rf cscope-15.9
fi

if [ ! -e ${HOME}/.local/bin/gtags ]; then
cd ${VIMIDE}/.program
tar xvzf global-6.6.11.tar.gz
cd global-6.6.11
./configure --prefix=${HOME}/.local
make -j8 && make install
cd -
rm -rf global-6.6.11
fi

# Preinstall for Universal Ctags
# Tagbar 의 심볼 목록은 ctags 가 만든다. Exuberant Ctags 5.8(2009) 은 C11 익명
# 구조체/최신 kind 를 놓치므로 Universal Ctags 를 쓴다. 이미 있으면 건너뛴다.
find_universal_ctags() {
	for c in "${HOME}/.local/bin/ctags" uctags ctags; do
		if command -v "$c" >/dev/null 2>&1; then
			if "$c" --version 2>/dev/null | grep -qi 'universal ctags'; then
				echo "$c"
				return 0
			fi
		fi
	done
	return 1
}

if UCTAGS=$(find_universal_ctags); then
	echo "### Universal Ctags: ${UCTAGS} (already installed) ###"
elif [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
	echo "### install Universal Ctags (brew) ###"
	# 구 ctags(Exuberant) 포뮬러와 bin/ctags 가 충돌하므로 먼저 unlink 한다
	# (되돌리려면: brew unlink universal-ctags && brew link ctags)
	if brew list ctags >/dev/null 2>&1; then
		brew unlink ctags
	fi
	brew install universal-ctags
elif command -v autoconf >/dev/null 2>&1 && command -v automake >/dev/null 2>&1; then
	echo "### build Universal Ctags -> ${HOME}/.local ###"
	cd ${VIMIDE}/.program
	rm -rf ctags
	git clone --depth 1 https://github.com/universal-ctags/ctags.git
	cd ctags
	./autogen.sh && ./configure --prefix=${HOME}/.local && make -j8 && make install
	cd -
	rm -rf ctags
	cd ${VIMIDE}
else
	echo "note: Universal Ctags 를 설치하지 못했습니다(Tagbar 는 기존 ctags 로 동작)."
	echo "      Ubuntu: sudo apt-get install -y universal-ctags"
	echo "      또는  : sudo apt-get install -y autoconf automake pkg-config gcc make"
	echo "              설치 후 ./install.sh 를 다시 실행하면 소스로 빌드합니다."
fi
cd ${VIMIDE}

# Setup for Neovim
# nvim 은 ~/.vimrc 를 읽지 않으므로 ~/.config/nvim/init.vim 에서 불러오고,
# 플러그인은 vim-plug 로 받는다(Vundle 은 plain vim 쪽만 쓴다).
if command -v nvim >/dev/null 2>&1; then
	echo "### setup neovim (vim-plug + init.vim) ###"
	NVIM_AUTOLOAD=${HOME}/.local/share/nvim/site/autoload
	if [ ! -e ${NVIM_AUTOLOAD}/plug.vim ]; then
		mkdir -p ${NVIM_AUTOLOAD}
		curl -fLo ${NVIM_AUTOLOAD}/plug.vim \
			https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
	fi
	if [ ! -e ${HOME}/.config/nvim/init.vim ]; then
		mkdir -p ${HOME}/.config/nvim
		cat > ${HOME}/.config/nvim/init.vim <<'INITVIM'
" nvim bootstrap: reuse the existing vim-ide configuration as-is.
" ~/.vim and ~/.vimrc are symlinks into ~/.vim-ide (see ~/.vim-ide/install.sh).
set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath

" nvim 0.11+ ships default <Tab>/<S-Tab> insert-mode Lua mappings
" (vim.snippet.jump) that supertab cannot wrap (E129). supertab maps both
" keys itself, so dropping the defaults restores the classic behavior.
silent! iunmap <Tab>
silent! iunmap <S-Tab>

source ~/.vimrc
INITVIM
	fi
	# 플러그인 설치 + treesitter 파서(C/C++ 등) 빌드
	nvim --headless "+set nomore" +PlugInstall +qall 2>&1 | tail -3
	nvim --headless "+set nomore" \
		"+TSUpdateSync c cpp lua vim vimdoc query python bash make devicetree" \
		+qall 2>&1 | tail -3
else
	echo "note: nvim 이 없어 Neovim 설정(RelationView, Neogit, neo-tree 등)은"
	echo "      건너뜁니다. Ubuntu: sudo apt-get install -y neovim"
fi

# vim-ide 가 얹는 것들이 제자리에 왔는지 확인한다.
#
# ~/.vim 이 통째로 심볼릭 링크라 파일 자체는 저절로 따라온다. 그래도 굳이
# 확인하는 이유는, 링크가 안 걸렸거나 예전 설치가 남아 있으면 조용히 기능만
# 빠진 채로 돌기 때문이다 - 그 상태는 눈으로 알아채기 어렵다.
echo "### check vim-ide add-ons ###"
VIMIDE_MISS=0
# 목록을 손으로 적지 않는다. 손으로 적으면 파일이 늘 때마다 낡는다 -
# 실제로 21개 중 8개만 들고 있었다. 저장소에 있는 것을 훑어 견준다.
for f in $(cd ${VIMIDE} && ls \
	.vim/plugin/*.lua .vim/plugin/*.vim \
	.vim/autoload/vimide/*.vim \
	.vim/after/ftplugin/*.vim \
	.vim/nerdtree_plugin/*.vim \
	.vim/colors/sourceinsight.vim 2>/dev/null); do
	if [ -r "${HOME}/${f}" ]; then
		echo "  ok    ${f}"
	else
		echo "  MISS  ${f}"
		VIMIDE_MISS=1
	fi
done
if [ ${VIMIDE_MISS} -ne 0 ]; then
	echo "note: 위 파일이 안 보이면 ${HOME}/.vim 링크를 확인하세요"
	echo "      (ls -l ${HOME}/.vim  ->  ${VIMIDE}/.vim 를 가리켜야 합니다)"
fi

# 예전에 만들어 둔 init.vim 은 ~/.vim/after 를 runtimepath 에 안 넣을 수
# 있다. quickfix 의 <CR> 을 EDIT 창으로 돌리는 파일이 거기 산다
# (.vim/after/ftplugin/qf.vim). init.vim 은 이미 있으면 새로 쓰지 않으므로
# 여기서 짚어만 준다 - 남의 설정을 말없이 고치지 않는다.
if [ -e ${HOME}/.config/nvim/init.vim ] && \
   ! grep -q 'runtimepath+=~/.vim/after' ${HOME}/.config/nvim/init.vim; then
	echo "note: ${HOME}/.config/nvim/init.vim 에 아래 한 줄이 없습니다."
	echo "        set runtimepath^=~/.vim runtimepath+=~/.vim/after"
	echo "      없으면 quickfix 의 <CR> 이 EDIT 창으로 가지 않습니다."
fi

echo "tip: :qa 로 나간 자리에서 다시 시작하려면  nvim +Restore"
echo "     (그냥  nvim  은 지금까지와 똑같이 기본 상태로 뜹니다)"

# 켜고 끌 수 있는 것들. 여기에 값을 늘어놓지 않는다 - 늘어놓으면 .vimrc 와
# 두 군데가 되어 곧 어긋난다. 어디를 보면 되는지만 가리킨다.
echo "tip: 기능을 켜고 끄는 설정은 모두 ${HOME}/.vimrc 에 'let g:...' 로 있습니다."
echo "     주요 절: '점프 키 관련 옵션' / 'RelationView' / '창 규칙' / '마우스'"
echo "              / '곁창에서 시작하면 안 되는 명령'"
VIMIDE_OPTS=$(grep -c '^let g:\(vimide\|relationview\|overview\)_' ${HOME}/.vimrc 2>/dev/null || echo 0)
echo "     (지금 ${VIMIDE_OPTS}개. 값을 고치고 nvim 을 다시 띄우면 바로 먹습니다)"
echo "tip: 마우스가 이상하면  :VimIdeMouseCheck  /  :VimIdeMouseOff  로 가릅니다."
echo "tip: <C-g> 는 '찾기 (grep)' 창을 띄웁니다. 찾을 말(커서 밑 낱말 또는 고른 글자)과"
echo "     찾을 곳(기본은 지금 파일의 디렉터리). Tab 칸 이동, Enter 찾기, Esc 취소."
echo "     RelationView 가 떠 있으면 패널에, 아니면 quickfix 에 목록이 뜹니다"
echo "     (rg 가 있으면 그것을 씁니다. 예전 대화식 grep 은 :Grep 로 남아 있습니다)"
echo "tip: neo-tree(F9 / F11 / RelationView 트리)에서는 커서 자리 이하를 찾습니다."
echo "     <C-g> 내용으로 찾기(grep), <C-f> 파일 이름으로 찾기(find)"
echo "tip: tmux 는 3.2 이상이어야 Ctrl+' 가 nvim 까지 갑니다 (위 의존성에서 새 판을 올립니다)."
echo "     이미 떠 있는 tmux 서버는 옛 판이라 새 tmux 로 붙지 못합니다 - 옛 세션은"
echo "     /usr/bin/tmux attach 로 붙고, 다 쓴 뒤 그 서버를 끄고 새로 여세요."
echo "     ~/.tmux.conf 에는 set -sq extended-keys on 이 있어야 합니다 (저장소 .tmux.conf 참고)"
echo "tip: nvim 에서는 NERDTree 를 끄고 neo-tree 를 씁니다 (F9 왼쪽 / F11 뜬 창)."
echo "     다시 쓰려면  let g:vimide_nerdtree = 1  (진짜 vim 8.1 은 원래 켬)"
echo "tip: RelationView 에서 w 로 넓혀도 aerial/quickfix 폭은 그대로입니다."
echo "     늘고 주는 것은 편집 창뿐이고, 편집 영역은 최소 20칸을 지킵니다"
echo "     (let g:relationview_wide_steps / g:relationview_wide_min_edit)"
echo "tip: :only / <C-w>o 는 곁창을 두고 편집 창만 하나로 합칩니다."
echo "     예전처럼 전부 닫으려면  :only!  (또는 let g:vimide_only_keeps_sides = 0)"
echo "tip: 곁창이 한두 칸으로 뭉개지면 저절로 원래 폭으로 돌아옵니다."
echo "     기준을 바꾸려면  let g:vimide_side_min_width = 8  (0 이면 끔)"
echo "tip: 곁창(aerial/quickfix/RelationView/neo-tree ...)에서 친 :e :b :bn :bd"
echo "     :find :h :tag 와 <C-t> / <C-^> / 마우스 뒤로·앞으로 버튼은 EDIT 창으로"
echo "     옮겨서 실행합니다. 끄려면  let g:vimide_edit_route = 0"
echo "     아무 명령이나 그렇게 돌리려면  :VimIdeInEdit <명령>"

# pip install pathlib 는 하지 않는다.
#
# pathlib 는 python 3.4 부터 표준 라이브러리다. PyPI 의 'pathlib' 는 그
# 시절 백포트이고, 지금 python 에 깔면 표준 것을 가리면서 오히려 깨진다
# (setuptools 가 'pathlib is obsolete' 로 막기도 한다). 남겨는 둔다 -
# 예전에 무엇을 했는지 알 수 있어야 하기 때문이다.
#pip install pathlib

echo "### vim install end ###"

