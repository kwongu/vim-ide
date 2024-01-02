#!/bin/sh
rm -rf cscope.files cscope.files

DIRS=$@

if [ ${#} -eq 0 ];then
	echo "argument is" $#
	#find . \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' -o -name '*.lib' -o -name '*.def' \) -print > cscope.files
	#find . \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' -o -name '*.dll' \) -print > cscope.files
	find . \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' \) -print > cscope.files
else
	echo "argument is" $#
	for i in $DIRS;do
		echo $i
		find $i \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name '*.S' -o -name '*.reg' \) -print >> cscope.files
	done
fi

cscope -i cscope.files
