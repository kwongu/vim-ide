#!/bin/sh

echo "### vim install start ###"

VIMIDE=${HOME}/.vim-ide

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

pip install pathlib

echo "### vim install end ###"

