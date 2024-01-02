#!/bin/sh

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
