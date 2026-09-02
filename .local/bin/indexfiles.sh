#!/bin/sh
# indexfiles.sh - 현재 디렉터리(프로젝트) 에서 색인할 파일 목록을 출력한다.
# ctags(gutentags) 와 gtags 가 같은 목록을 쓰도록 한 곳에서 정한다.
#
# 우선순위
#   1. .indexfiles   : 프로젝트에서 직접 고른 목록(한 줄에 파일 하나)
#   2. cscope.files  : mktags.sh(F2) 가 만든 목록
#   3. git ls-files  : git 저장소면 추적 중인 소스만 (커널 트리 기본값)
#   4. find          : 그 외
#
# 확장자 집합은 mktags.sh 와 같다.
#
# 사용:  indexfiles.sh [dir]        (dir 기본값 = 현재 디렉터리)

set -e
DIR=${1:-.}
cd "$DIR"

EXT_RE='\.\(dts\|dtsi\|c\|cpp\|cc\|h\|s\|S\|reg\)$'

if [ -f .indexfiles ]; then
	grep -v '^[[:space:]]*$' .indexfiles | grep -v '^[[:space:]]*#'
elif [ -f cscope.files ]; then
	grep -v '^[[:space:]]*$' cscope.files
elif [ -d .git ] && command -v git >/dev/null 2>&1; then
	git ls-files | grep "$EXT_RE"
else
	find . \( -name .git -o -name .svn -o -name node_modules \) -prune -o \
		-type f \( -name '*.dts' -o -name '*.dtsi' -o -name '*.c' \
		-o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' \
		-o -name '*.S' -o -name '*.reg' \) -print
fi
