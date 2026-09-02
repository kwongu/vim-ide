#!/bin/sh

# The bundled toolchain lives in ~/.local/bin. Non-interactive shells
# (nvim/vim ':!', GUI editors, cron) do not source ~/.zshrc/.bashrc, so
# put it on PATH here to be runnable from anywhere on Linux and macOS.
PATH="${HOME}/.local/bin:${PATH}"
export PATH

if ! command -v gtags >/dev/null 2>&1; then
	echo "error: 'gtags' not found (expected in ~/.local/bin or PATH)" >&2
	exit 1
fi

# The databases live in a hidden directory ('.tags/'), so nothing shows up
# in the source tree; DBPATH keeps the old layout reachable with
#   DBPATH=. ./mktags.sh
DBPATH="${DBPATH:-.tags}"
mkdir -p "${DBPATH}"

rm -f cscope.files cscope.out GPATH GRTAGS GTAGS tags
rm -f "${DBPATH}/GPATH" "${DBPATH}/GRTAGS" "${DBPATH}/GTAGS"

DIRS=$@

# define functions
build_ctags()
{
	echo "### start: ctags -L cscope.files ###"
	time ctags -L cscope.files
	echo "### end: ctags -L cscope.files ###"

}
build_gtags()
{
	arg1=$1

	if [ "${arg1}" = "dir" ]
	then
		echo "### start: gtags ${DIRS} ###"
		time gtags ${DIRS} "${DBPATH}"
		echo "### end: gtags ${DIRS} ###"

	else
		echo "### start: gtags -f cscope.files ${DBPATH} ###"
		time gtags -f cscope.files "${DBPATH}"
		echo "### end: gtags -f cscope.files ${DBPATH} ###"
		#echo "### start: gtags-cscope -F cscope.files ###"
		#time gtags-cscope -F cscope.files
		#echo "### end: gtags-cscope -F cscope.files ###"
	fi

}
build_cscope()
{
	echo "### start: cscope -i cscope.files ###"
	time cscope -i cscope.files
	echo "### end: cscope -i cscope.files ###"

}


if [ ${#} -eq 0 ];then
	echo "argument is" $#
	#find . \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' -o -name '*.lib' -o -name '*.def' \) -print > cscope.files
	#find . \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' -o -name '*.dll' \) -print > cscope.files
	#find * \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' \) -print > cscope.files
	find * \( -name '*.dts' -o -name '*.dtsi' -o -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' \) -print > cscope.files
	#build_ctags
	build_gtags
else
	echo "argument is" $#
	for i in $DIRS;do
		echo $i
		#find $i \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' \) -print >> cscope.files
		find $i \( -name '*.dts' -o -name '*.dtsi' -o -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' \) -print >> cscope.files
	done
	#echo "### ctags -R ${DIRS} ###"
	#time ctags -R ${DIRS}
	#build_ctags
	build_gtags
	#build_gtags "dir"
fi

#build_cscope
echo "############  end make tags ############"
if [ "${DBPATH}" != "." ]; then
	echo "database: ${DBPATH}/  (nvim finds it by itself; in a shell use:"
	echo "          eval \"\$(gtagsenv.sh)\" )"
fi
