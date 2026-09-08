#!/bin/sh
# indexfiles.sh - 현재 디렉터리(프로젝트) 에서 색인할 파일 목록을 출력한다.
# ctags(gutentags) 와 gtags 가 같은 목록을 쓰도록 한 곳에서 정한다.
#
# 우선순위
#   0. .tags/files   : preset 으로 고른 목록(:ProjectFiles 가 관리)
#
# 2/3/4 로 목록을 만들 때는, 하위에 자기 '.tags' 를 가진 디렉터리(= 별개의
# 프로젝트)의 파일을 뺀다. filter_nested 를 보라.
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

# 하위에 자기 색인('.tags')을 가진 디렉터리는 별개의 프로젝트다. 그 밑의
# 파일은 이 프로젝트의 목록에서 뺀다. 넣으면 같은 파일이 두 색인에 들어가고,
# 상위에서 만든 목록이 하위 프로젝트의 것을 밀어내는 것처럼 보인다.
#
#   INDEXFILES_NESTED_DEPTH   하위 프로젝트를 찾는 깊이 (기본 6, 0 이면 끔)
#
# 명시적으로 적어 둔 목록(.tags/files, .indexfiles)에는 손대지 않는다 -
# 그건 사람이 고른 것이다. 생성되는 목록(git / cscope.files / find)만 걸른다.
NESTED_DEPTH=${INDEXFILES_NESTED_DEPTH:-6}

nested_prefixes() {
	[ "$NESTED_DEPTH" -le 0 ] && return 0
	find . -mindepth 2 -maxdepth $((NESTED_DEPTH + 1)) \
		-type d -name .tags -prune -print 2>/dev/null |
		sed -e 's|/\.tags$||' -e 's|^\./||' |
		grep -v '^$' || true
}

filter_nested() {
	if [ "$NESTED_DEPTH" -le 0 ]; then
		cat
		return 0
	fi
	_nf=$(mktemp 2>/dev/null) || { cat; return 0; }
	nested_prefixes > "$_nf"
	if [ ! -s "$_nf" ]; then
		rm -f "$_nf"
		cat
		return 0
	fi
	awk -v pf="$_nf" '
		BEGIN { while ((getline l < pf) > 0) if (l != "") p[++n] = l "/" }
		{ s = $0; sub(/^\.\//, "", s)
		  for (i = 1; i <= n; i++) if (index(s, p[i]) == 1) next
		  print }'
	rm -f "$_nf"
}

if [ -f .tags/files ]; then
	# preset 모드: projectfiles.lua 가 만들어 둔 목록 (파일/디렉터리 preset)
	grep -v '^[[:space:]]*$' .tags/files
elif [ -f .indexfiles ]; then
	grep -v '^[[:space:]]*$' .indexfiles | grep -v '^[[:space:]]*#'
elif [ -d .git ] && command -v git >/dev/null 2>&1; then
	# --others --exclude-standard: 아직 커밋하지 않은 새 파일도 색인 대상
	# (.gitignore 는 그대로 존중한다)
	git ls-files --cached --others --exclude-standard | grep "$EXT_RE" |
		filter_nested
elif [ -f cscope.files ]; then
	grep -v '^[[:space:]]*$' cscope.files | filter_nested
else
	find . \( -name .git -o -name .svn -o -name node_modules \
		-o -name .tags \) -prune -o \
		-type f \( -name '*.dts' -o -name '*.dtsi' -o -name '*.c' \
		-o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' \
		-o -name '*.S' -o -name '*.reg' \) -print | filter_nested
fi
