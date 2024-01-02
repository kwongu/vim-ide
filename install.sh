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
cd ${VIMIDE}

pip install pathlib

echo "### vim install end ###"

