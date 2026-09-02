#!/bin/sh
# indexfiles.sh - 현재 디렉터리(프로젝트) 에서 색인할 파일 목록을 출력한다.
# ctags(gutentags) 와 gtags 가 같은 목록을 쓰도록 한 곳에서 정한다.
#
# 우선순위
#   1. .indexfiles   : 프로젝트에서 직접 고른 목록(한 줄에 파일 하나)
#   2. git ls-files  : git 저장소면 추적 중인 소스 전체 (커널 트리 기본값)
#   3. cscope.files  : git 이 아닐 때, mktags.sh(F2) 가 만든 목록
#   4. find          : 그 외
#
# cscope.files 를 git 보다 뒤에 두는 이유: F2 가 중간에 끊기면 부분 목록이
# 남고(예: 6만개 트리에 1.4만개), 그 목록으로 색인을 다시 만들면 나머지
# 심볼이 통째로 사라진다. 특정 파일만 색인하려면 .indexfiles 를 쓴다.
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
elif [ -d .git ] && command -v git >/dev/null 2>&1; then
	# --others --exclude-standard: 아직 커밋하지 않은 새 파일도 색인 대상
	# (.gitignore 는 그대로 존중한다)
	git ls-files --cached --others --exclude-standard | grep "$EXT_RE"
elif [ -f cscope.files ]; then
	grep -v '^[[:space:]]*$' cscope.files
else
	find . \( -name .git -o -name .svn -o -name node_modules \
		-o -name .tags \) -prune -o \
		-type f \( -name '*.dts' -o -name '*.dtsi' -o -name '*.c' \
		-o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' \
		-o -name '*.S' -o -name '*.reg' \) -print
fi
