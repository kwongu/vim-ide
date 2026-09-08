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

# 색인 목록에 넣을 파일. projectfiles.lua 와 autoindex.lua 의 같은 목록과
# 맞춰 두어야 한다 - 어긋나면 auto 모드와 preset 모드가 서로 다른 파일을
# 색인한다.
#
# 'Makefile' 처럼 확장자가 없는 것이 있어서 두 벌로 둔다.
# gtags 가 심볼까지 읽는 것은 C/C++/Java/asm 정도이고, 나머지는 목록에만
# 들어간다(찾아서 열 수는 있다). ctags 쪽은 python·java·make 도 읽는다.
#
#   INDEXFILES_EXTS / INDEXFILES_NAMES 로 바꿀 수 있다.
# ':-' 가 아니라 '-' 다: 빈 값을 명시하면 그대로 비운다 (한쪽만 쓰고 싶을 때)
EXTS=${INDEXFILES_EXTS-'c h cpp cc cxx hxx hh hpp s S dts dtsi reg java bp xml json py bb bbappend mk'}
NAMES=${INDEXFILES_NAMES-'Makefile makefile Kconfig Kbuild'}

# grep 용 정규식. 확장 정규식(grep -E)을 쓴다: POSIX 기본 정규식에서는
# '$' 와 '^' 가 정규식의 맨 끝/맨 앞이 아니면 앵커가 아니라 그냥 문자라서,
# '\.\(c\)$\|^\(Makefile\)$' 처럼 여러 대안에 앵커를 붙이면 마지막
# 대안만 동작한다(실제로 그래서 .c/.java 가 하나도 걸리지 않았다).
_alt() { printf '%s' "$1" | tr ' ' '\n' | grep -v '^$' | paste -sd'|' -; }
EXT_ALT=$(_alt "$EXTS")
NAME_ALT=$(_alt "$NAMES")
EXT_RE=''
if [ -n "$EXT_ALT" ]; then
	EXT_RE="\.($EXT_ALT)$"
fi
if [ -n "$NAME_ALT" ]; then
	[ -n "$EXT_RE" ] && EXT_RE="$EXT_RE|"
	EXT_RE="$EXT_RE(^|/)($NAME_ALT)$"
fi
# 둘 다 비면 아무 것도 고르지 않는다(맞지 않는 정규식)
[ -n "$EXT_RE" ] || EXT_RE='$^'

# find 용 술어:  -name '*.c' -o -name '*.h' … -o -name 'Makefile' …
find_names() {
	first=1
	for e in $EXTS; do
		[ $first -eq 1 ] && first=0 || printf ' -o '
		printf -- "-name *.%s" "$e"
	done
	for b in $NAMES; do
		[ $first -eq 1 ] && first=0 || printf ' -o '
		printf -- "-name %s" "$b"
	done
}

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
	git ls-files --cached --others --exclude-standard | grep -E "$EXT_RE" |
		filter_nested
elif [ -f cscope.files ]; then
	grep -v '^[[:space:]]*$' cscope.files | filter_nested
else
	# 'set -f' 로 글로브를 끈 뒤에 쪼갠다. 이게 없으면 '-name *.java' 의
	# '*.java' 가 셸에서 현재 디렉터리 기준으로 먼저 확장되어(-name Foo.java)
	# 하위 디렉터리의 같은 확장자를 놓친다.
	set -f
	# shellcheck disable=SC2046  # find_names 는 술어 목록을 의도적으로 쪼갠다
	find . \( -name .git -o -name .svn -o -name node_modules \
		-o -name .tags \) -prune -o \
		-type f \( $(find_names) \) -print | filter_nested
	set +f
fi
