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
EXTS=${INDEXFILES_EXTS-'c cc cpp cxx h hh hpp hxx s S java kt kts rs aidl py pl sh bash zsh ksh awk lua vim tcl mk mak cmake gradle pro bp bb bbappend bbclass inc dts dtsi xml json yaml yml toml ini cfg conf properties env rc reg md txt rst ld lds def map te pc'}
NAMES=${INDEXFILES_NAMES-'Makefile makefile GNUmakefile Kconfig Kbuild BUILD WORKSPACE Dockerfile README LICENSE NOTICE'}

# grep 용 정규식. 확장 정규식(grep -E)을 쓴다: POSIX 기본 정규식에서는
# '$' 와 '^' 가 정규식의 맨 끝/맨 앞이 아니면 앵커가 아니라 그냥 문자라서,
# '\.\(c\)$\|^\(Makefile\)$' 처럼 여러 대안에 앵커를 붙이면 마지막
# 대안만 동작한다(실제로 그래서 .c/.java 가 하나도 걸리지 않았다).
_alt() { printf '%s' "$1" | tr ' ' '\n' | grep -v '^$' | paste -sd'|' -; }
# 통째로 갈아치우지 않고 덧붙이는 쪽이 흔하다
EXTS="$EXTS ${INDEXFILES_EXTS_EXTRA:-}"
NAMES="$NAMES ${INDEXFILES_NAMES_EXTRA:-}"

# 기본은 '모든 파일'이다. 확장자 허용목록으로 고르면 새로운 종류가 나올
# 때마다 목록을 늘려야 하고 그때까지 그 파일은 색인에 없다. 그래서 뒤집어서
# 전부 넣고, 넣어서 해로운 것(산출물·바이너리)만 뺀다.
#   INDEXFILES_ALL=0                    허용목록만 쓰기
#   INDEXFILES_EXCLUDE_EXTS_EXTRA='log' 제외를 덧붙이기
ALL=${INDEXFILES_ALL:-1}
EXCL_EXTS=${INDEXFILES_EXCLUDE_EXTS-'o a so ko obj lo la exe dll dylib bin img elf hex bpf gz bz2 xz zst lz4 zip tar tgz tbz jar apk aar dex odex vdex rar 7z iso dmg png jpg jpeg gif bmp ico webp tiff tif psd svgz mp3 mp4 avi mkv wav flac ogg opus webm pdf doc docx xls xlsx ppt pptx odt ods pyc pyo pyd class pdb ilk exp d cmd pack idx swp swo swn ttf otf woff woff2 eot db sqlite sqlite3 dat rom fw uimage flat rsp srcjar kapt_metadata jack toc lst gcno gcda su i ii stamp timestamp'}
EXCL_NAMES=${INDEXFILES_EXCLUDE_NAMES-'tags TAGS cscope.out cscope.in.out cscope.po.out GTAGS GRTAGS GPATH core .DS_Store'}
EXCL_EXTS="$EXCL_EXTS ${INDEXFILES_EXCLUDE_EXTS_EXTRA:-}"
EXCL_NAMES="$EXCL_NAMES ${INDEXFILES_EXCLUDE_NAMES_EXTRA:-}"
PRUNE_DIRS=${INDEXFILES_PRUNE_DIRS-'.git .svn .hg .tags node_modules __pycache__ .repo .ccache out'}
EXT_ALT=$(_alt "$EXTS")
NAME_ALT=$(_alt "$NAMES")
EXCL_ALT=$(_alt "$EXCL_EXTS")
EXCL_NAME_ALT=$(_alt "$EXCL_NAMES")
EXCL_RE=''
if [ -n "$EXCL_ALT" ]; then
	EXCL_RE="\.($EXCL_ALT)$"
fi
if [ -n "$EXCL_NAME_ALT" ]; then
	[ -n "$EXCL_RE" ] && EXCL_RE="$EXCL_RE|"
	EXCL_RE="$EXCL_RE(^|/)($EXCL_NAME_ALT)$"
fi
[ -n "$EXCL_RE" ] || EXCL_RE='$^'

# 무엇을 넣을지 정하는 곳을 하나로: 모든 파일 모드면 제외목록만, 아니면
# 허용목록만 본다.
# git ls-files / cscope.files 에는 디렉터리 가지치기가 적용되지 않는다
# (find 는 -prune 으로 하지만 git 은 자기 목록을 그대로 준다). 보통은
# .gitignore 가 걸러 주지만, 커밋된 node_modules 같은 것도 있다.
filter_prune() {
	if [ -z "$PRUNE_DIRS" ]; then
		cat
		return 0
	fi
	_pf=$(mktemp 2>/dev/null) || { cat; return 0; }
	printf '%s\n' $PRUNE_DIRS > "$_pf"
	awk -v pf="$_pf" '
		BEGIN { while ((getline l < pf) > 0) if (l != "") p[++n] = l }
		{ s = $0; sub(/^\.\//, "", s)
		  split(s, seg, "/")
		  for (i = 1; i < length(seg); i++)
		    for (j = 1; j <= n; j++)
		      if (seg[i] == p[j]) next
		  print }'
	rm -f "$_pf"
}

filter_types() {
	if [ "$ALL" -eq 1 ]; then
		grep -Eiv "$EXCL_RE"
	else
		grep -E "$EXT_RE"
	fi
}

# 확장자로는 걸러지지 않는 것: 이름에 점이 없는 바이너리, 그리고 거대한
# 생성물.
#
# 실측(QNX+Android SDK 트리): 색인 목록 1540개 중 83개가 바이너리였다 -
# 'qnx/disk/qnx-ifs'(64MB IFS 이미지), 'kernel-6.1'(33MB EFI 실행파일),
# '*.sym'(15MB ELF). ctags/gtags 는 그 164MB 를 매번 읽고 태그는 한 줄도
# 내지 않는다. 크기 쪽은 vmlinux_*.h 3개(각 3MB)가 태그 485,469줄을 만들어
# 120MB tags 의 절반을 차지했고, gutentags 는 저장마다 그 파일을 다시 쓴다.
#
#   INDEXFILES_MAX_BYTES=0    크기 제한 없음
#   INDEXFILES_SKIP_BINARY=0  내용 검사 안 함
MAX_BYTES=${INDEXFILES_MAX_BYTES:-2097152}
SKIP_BINARY=${INDEXFILES_SKIP_BINARY:-1}

# GNU 와 BSD 의 stat 은 서로 다른 플래그를 쓴다 (맥과 리눅스 둘 다에서 돈다).
#
# 형식 문자열은 **한 인자**여야 한다. 예전에 이걸 'stat -c %s %n' 이라는
# 문자열로 만들어 뒀다가 셸이 단어로 쪼개서 '%n' 이 파일 이름으로 먹혔고,
# stat 이 아무것도 내놓지 못해 목록 1540개가 통째로 사라졌다.
if stat -c %s . >/dev/null 2>&1; then
	STAT_KIND=gnu
elif stat -f %z . >/dev/null 2>&1; then
	STAT_KIND=bsd
else
	STAT_KIND=none
fi

# 크기와 이름을 '<바이트> <경로>' 로 내놓는다. 파일마다 stat 을 띄우면 큰
# 목록에서 그 자체가 비용이라 xargs 로 묶는다 - '-0' 은 GNU/BSD 양쪽에
# 있다('-d' 는 GNU 전용이라 쓰지 않는다).
_sizes() {
	case $STAT_KIND in
	gnu) tr '\n' '\0' | xargs -0 stat -c '%s %n' 2>/dev/null ;;
	bsd) tr '\n' '\0' | xargs -0 stat -f '%z %N' 2>/dev/null ;;
	esac
}

filter_size() {
	[ "$MAX_BYTES" -le 0 ] && { cat; return; }
	[ "$STAT_KIND" = none ] && { cat; return; }
	_sizes | awk -v m="$MAX_BYTES" '$1 <= m { sub(/^[0-9]+[ \t]+/, ""); print }'
}

filter_binary() {
	[ "$SKIP_BINARY" -eq 0 ] && { cat; return; }
	# 'grep -I' 는 바이너리를 '일치 없음'으로 취급한다. 빈 패턴은 모든 줄에
	# 일치하니 텍스트 파일만 이름이 나온다. 파일마다 head 를 띄우는 것보다
	# 훨씬 싸다 - 한 프로세스가 여러 파일을 읽는다.
	tr '\n' '\0' | xargs -0 grep -Il -e '' -- 2>/dev/null
}

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
	# preset 모드: projectfiles.lua 가 만들어 둔 목록 (파일/디렉터리 preset).
	# 그쪽에서 이미 걸렀지만, 목록을 손으로 고칠 수도 있으니 여기서도 본다.
	grep -v '^[[:space:]]*$' .tags/files | filter_size | filter_binary
elif [ -f .indexfiles ]; then
	grep -v '^[[:space:]]*$' .indexfiles | grep -v '^[[:space:]]*#' |
		filter_size | filter_binary
elif [ -d .git ] && command -v git >/dev/null 2>&1; then
	# --others --exclude-standard: 아직 커밋하지 않은 새 파일도 색인 대상
	# (.gitignore 는 그대로 존중한다)
	# 'core.quotepath=off': 이게 없으면 git 이 ASCII 밖의 이름을
	# "\355\225\234…" 처럼 escape 해서 내놓고, 그 문자열로는 파일을
	# 열 수도 색인할 수도 없다(한글 파일명이 그렇게 깨진다).
	#
	# 가지치기 디렉터리는 git 에게 '--exclude' 로 알려 준다. 나중에
	# filter_prune 으로 걸러도 결과는 같지만, '--others' 는 무엇이
	# untracked 인지 알려고 트리를 다 훑기 때문에 그 전에 막아야 한다.
	# 실측(QNX+Android SDK 트리): 그냥 489,302개 2,978ms →
	# --exclude=out 으로 63,211개 617ms → .repo 까지 1,491개 62ms.
	# ':(exclude)' pathspec 은 훑은 뒤에 거르는 것이어서 효과가 없었다.
	set -f
	gitex=''
	for d in $PRUNE_DIRS; do
		case $d in .git) continue ;; esac
		gitex="$gitex --exclude=$d"
	done
	# shellcheck disable=SC2086  # gitex 는 옵션 목록이라 쪼개져야 한다
	git -c core.quotepath=off ls-files --cached --others --exclude-standard \
		$gitex |
		filter_prune | filter_types | filter_nested |
		filter_size | filter_binary
	set +f
elif [ -f cscope.files ]; then
	grep -v '^[[:space:]]*$' cscope.files | filter_prune | filter_types |
		filter_nested | filter_size | filter_binary
else
	# 'set -f' 로 글로브를 끈 뒤에 쪼갠다. 이게 없으면 '-name *.java' 의
	# '*.java' 가 셸에서 현재 디렉터리 기준으로 먼저 확장되어(-name Foo.java)
	# 하위 디렉터리의 같은 확장자를 놓친다.
	# 디렉터리 가지치기만 find 가 하고, 무엇을 넣을지는 filter_types 가 본다
	set -f
	prune=''
	for d in $PRUNE_DIRS; do
		[ -z "$prune" ] && prune="-name $d" || prune="$prune -o -name $d"
	done
	# shellcheck disable=SC2086  # prune 은 술어 목록이라 쪼개져야 한다
	# find 는 크기를 이미 알고 있으니 stat 을 다시 부를 필요가 없다
	if [ "$MAX_BYTES" -gt 0 ]; then
		find . \( $prune \) -prune -o -type f -size -"$((MAX_BYTES / 512 + 1))" -print |
			filter_types | filter_nested | filter_binary
	else
		find . \( $prune \) -prune -o -type f -print |
			filter_types | filter_nested | filter_binary
	fi
	set +f
fi
