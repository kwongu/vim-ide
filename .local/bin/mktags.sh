#!/bin/sh

red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
blue=`tput setaf 4`
magenta=`tput setaf 5`
cyan=`tput setaf 6`
white=`tput setaf 7`
reset=`tput sgr0`

bold=$(tput bold)
normal=$(tput sgr0)
blinking="\x1b[5m"

function help() {
    echo -e "\n"
    echo "Usage : ${bold}${green}mktags.sh${reset} ${bold}${blue}{DIR1}${reset} ${bold}${magenta}{DIR2}...${reset}"
    echo -e "\n"
    echo "${bold}${white}        ===============================================================================${reset}"
        echo -e "\t${bold}${cyan}Ex1) mktags.sh . ${reset}"
        echo -e "\t${bold}${cyan}Ex2) mktags.sh maincore/external/tinyalsa maincore/kernel${reset}"
        echo -e "\t${bold}${cyan}Ex3) mktags.sh maincore/external/tinyalsa maincore/kernel subcore/build/tcc8050-sub/tmp/work/aarch64-telechips-linux/t-sound/1.1.0-r0/git${reset}"
        echo -e "\t${bold}${cyan}     ... ${reset}"
    echo "${bold}${white}        -------------------------------------------------------------------------------${reset}"
    echo -e "\n"
    exit 1
}

if [ $# -lt 1 ]; then
    help
fi

rm -f cscope.files cscope.out GPATH GRTAGS GTAGS tags

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
		time gtags ${DIRS}
		echo "### end: gtags ${DIRS} ###"

	else
		echo "### start: gtags -f cscope.files ###"
		time gtags -f cscope.files
		echo "### end: gtags -f cscope.files ###"
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
