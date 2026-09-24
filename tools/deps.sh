#!/bin/sh
# deps.sh - vim-ide 가 필요로 하는 프로그램을 확인하고, 없거나 낡으면 설치한다.
#
# install.sh 가 맨 처음 부른다. 따로 돌려도 된다:
#
#   tools/deps.sh            확인하고 모자란 것만 설치한다
#   tools/deps.sh --check    확인만 한다 (아무것도 바꾸지 않는다)
#   tools/deps.sh --list     무엇이 왜 필요한지 보여준다
#
# 왜 '있는지'가 아니라 '몇 판인지'를 보나
#   예전에는 install.sh 가 'command -v git' 만 봤다. 그러면 git 2.25.1 도
#   '있음'이라 통과하는데, diffview 는 2.31 이상을 요구해서 \v 가 아무 말
#   없이 아무 일도 하지 않았다. 없는 것보다 낡은 것이 더 알아내기 어렵다.
#
# 남의 기계를 조용히 고치지 않는다
#   개발서버는 826명이 함께 쓰고 sudo 에 암호가 걸려 있다. 그래서 순서가
#   이렇다:
#     1) 암호 없이 sudo 가 되면 그것으로 (개인 장비)
#     2) 안 되면 홈($HOME/.local)에만 올린다 - 남에게 영향이 없다
#     3) 그것도 길이 없으면 '이 명령을 직접 치세요'만 적고 지나간다
#   VIMIDE_DEPS_SUDO=0 이면 1)을 아예 건너뛴다.
#
# 아무것도 설치하지 않게 하려면  VIMIDE_DEPS=0 ./install.sh

set -u

DEPS_DIR=$(cd "$(dirname "$0")" && pwd)
VIMIDE=$(cd "${DEPS_DIR}/.." && pwd)
LOCAL=${HOME}/.local
MODE=install
case "${1:-}" in
	--check) MODE=check ;;
	--list)  MODE=list ;;
	'') ;;
	*) echo "쓰임: $0 [--check|--list]"; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# 이 기계는 무엇인가
# ---------------------------------------------------------------------------
os_kind() {
	case "$(uname -s)" in
		Darwin) echo darwin; return ;;
	esac
	if [ -r /etc/os-release ]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		case "${ID:-}${ID_LIKE:-}" in
			*debian*|*ubuntu*) echo debian; return ;;
			*rhel*|*fedora*|*centos*) echo rhel; return ;;
			*arch*) echo arch; return ;;
		esac
	fi
	echo other
}
OS=$(os_kind)

# 암호 없이 sudo 가 되는가. 되묻지 않는다 - 스크립트가 암호를 기다리며
# 멈춰 있으면 무엇을 기다리는지 알 수가 없다.
can_sudo() {
	[ "${VIMIDE_DEPS_SUDO:-1}" = "0" ] && return 1
	command -v sudo >/dev/null 2>&1 || return 1
	sudo -n true >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 판 비교
# ---------------------------------------------------------------------------
# 출력 어디에 있든 첫 'a.b' 또는 'a.b.c' 를 집는다.
#   git version 2.50.1           -> 2.50.1
#   NVIM v0.12.4                 -> 0.12.4
#   Universal Ctags 6.2.1, ...   -> 6.2.1
#   VIM - Vi IMproved 9.1 (...)  -> 9.1
ver_of() {
	"$@" 2>&1 | head -3 |
		grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

# a >= b ?  sort -V 는 맥(BSD)과 리눅스(GNU) 둘 다 있다 - 확인했다.
ver_ge() {
	[ -n "$1" ] || return 1
	[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# ---------------------------------------------------------------------------
# 무엇이 왜 필요한가
# ---------------------------------------------------------------------------
# 한 줄에 하나:  이름 | 최소판 | 등급 | 왜 | 판을 묻는 명령 | 판 대신 볼 글자
#   등급 must = 없으면 vim-ide 의 큰 축이 통째로 죽는다
#        want = 없으면 그 기능만 빠진다
#   '판 대신 볼 글자'가 있고 그 글자가 출력에 보이면 숫자는 묻지 않는다.
#   Universal Ctags 는 git 스냅샷으로 빌드하면 스스로를 0.0.0 이라고 말한다
#   (실측: 개발서버가 그렇다). 숫자로 재면 멀쩡한 것을 낡았다고 한다.
REQS='
git|2.31|must|diffview 의 나란히 보기와 3-way 병합 (leader v). 낡으면 "Not a repo" 만 남기고 아무 일도 안 한다|git --version|
nvim|0.9|must|RelationView, Neogit, neo-tree, 색인 자동화 - lua 로 된 것 전부|nvim --version|
global|6.6|must|심볼 색인을 읽는 쪽. <C-]>(tagfunc), RelationView, \fs, SiHlIndex 가 전부 이것을 거친다|global --version|
gtags|6.6|must|색인을 만드는 쪽. global 과 같은 꾸러미지만 따로 확인한다 - 하나만 있으면 찾기는 되는데 갱신이 안 되는 상태가 된다|gtags --version|
ctags|5.9|want|Tagbar/aerial 의 심볼 목록. Universal Ctags 라야 한다 - autoindex 가 --tag-relative=never 를 넘기는데 Exuberant 5.8 은 yes/no 만 받는다|ctags --version|Universal Ctags
rg|11|want|<C-g> 의 경로 검색. 없으면 grep 으로 떨어진다(느리다)|rg --version|
curl|7|must|vim-plug 부트스트랩과 플러그인 내려받기|curl --version|
make|3.8|want|telescope-fzf-native 빌드와 소스 설치|make --version|
cc|4|want|위와 같다. 소스로 빌드할 때만 쓴다|cc --version|
python3|3.6|want|install.sh 가 vim 을 python 지원으로 빌드할 때만 쓴다|python3 --version|
tmux|3.2|want|tmux 안에서 nvim 을 쓸 때 Ctrl+작은따옴표 같은 확장 키를 넘긴다(extended-keys, 3.2 부터). 모자라면 GitHub 의 최신 릴리스를 올린다|tmux -V|
'

# node 는 넣지 않는다.
#   coc.nvim 이 .vimrc:194 에서 주석으로 꺼져 있다. 남아 있는 coc-explorer 는
#   coc 없이는 아무 일도 하지 않으므로 node 도 필요 없다. 있으면 좋은 것이
#   아니라 '쓰지 않는 것'이라, 목록에 두면 없는 사람에게 헛일을 시킨다.
#   coc 를 다시 켠다면 그때 node|16|want 를 넣으면 된다.

# 이름 -> 패키지 이름 (배급판마다 다르다)
pkg_for() {
	_t=$1
	case "${OS}:${_t}" in
		darwin:global)  echo global ;;
		darwin:ctags)   echo universal-ctags ;;
		darwin:rg)      echo ripgrep ;;
		darwin:nvim)    echo neovim ;;
		darwin:node)    echo node ;;
		darwin:python3) echo python ;;
		debian:global)  echo global ;;
		debian:ctags)   echo universal-ctags ;;
		debian:rg)      echo ripgrep ;;
		debian:nvim)    echo neovim ;;
		debian:node)    echo nodejs ;;
		debian:python3) echo python3 ;;
		*:*)            echo "${_t}" ;;
	esac
}

# ---------------------------------------------------------------------------
# 설치
# ---------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
note() { printf '      %s\n' "$*"; }

# git 만은 홈에 올리는 길이 따로 있다. 개발서버(Ubuntu 20.04)의 git 은
# 2.25.1 이고 sudo 가 막혀 있는데, diffview 는 2.31 이상을 요구한다.
# git-core PPA 의 .deb 를 풀어 쓴다 - 데비안 빌드는 /usr/lib/git-core 를
# 박아 두므로 래퍼로 제 짝을 가리켜 준다(안 그러면 낡은 헬퍼를 쓴다).
install_git_local() {
	command -v curl >/dev/null 2>&1 || return 1
	command -v dpkg >/dev/null 2>&1 || return 1
	_code=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")
	[ -n "${_code}" ] || return 1
	_base=https://ppa.launchpadcontent.net/git-core/ppa/ubuntu/pool/main/g/git/
	_deb=$(curl -sL --max-time 60 "${_base}" |
		grep -oE "git_[0-9.]+-[^\"<>]*ubuntu${_code}[^\"<>]*_amd64\.deb" |
		sort -V | tail -1)
	[ -n "${_deb}" ] || return 1
	_ver=$(echo "${_deb}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
	say "      git ${_ver} 를 ${LOCAL}/git-${_ver} 에 올립니다 (sudo 없이, 내 홈에만)"
	_d=${LOCAL}/git-${_ver}
	curl -sL --max-time 300 -o /tmp/vimide-git.deb "${_base}${_deb}" || return 1
	rm -rf "${_d}"; mkdir -p "${_d}"
	dpkg -x /tmp/vimide-git.deb "${_d}" || { rm -f /tmp/vimide-git.deb; return 1; }
	rm -f /tmp/vimide-git.deb
	mkdir -p "${LOCAL}/bin"
	cat > "${LOCAL}/bin/git" <<EOF
#!/bin/sh
# vim-ide/tools/deps.sh 가 만든 래퍼. 데비안 빌드가 박아 둔
# /usr/lib/git-core 대신 제 짝을 가리킨다.
GIT_EXEC_PATH=${_d}/usr/lib/git-core
GIT_TEMPLATE_DIR=${_d}/usr/share/git-core/templates
export GIT_EXEC_PATH GIT_TEMPLATE_DIR
exec ${_d}/usr/bin/git "\$@"
EOF
	chmod +x "${LOCAL}/bin/git"
	return 0
}

# tmux 는 소스로 홈에 올린다. 개발서버(Ubuntu 20.04)의 apt 판은 3.0a 라
# extended-keys(3.2+)가 없고, sudo 도 막혀 있다. 받는 것은 공식 릴리스뿐이다:
#   tmux      github.com/tmux/tmux/releases       (최신 태그를 물어서)
#   libevent  github.com/libevent/libevent/releases (헤더가 없을 때만, 정적으로)
# libevent 를 정적으로 묶어 두면 실행할 때 LD_LIBRARY_PATH 가 필요 없다.
# ncurses 헤더는 기계에 있어야 한다(개발서버에는 있다). 없으면 멈추고 알린다.
# 결과: ${LOCAL}/tmux-<판>/ 에 설치하고 ${LOCAL}/bin/tmux 가 그것을 가리킨다.
#   VIMIDE_TMUX_VERSION=3.5a  최신 대신 이 판으로
install_tmux_local() {
	for _c in curl cc make; do
		command -v "${_c}" >/dev/null 2>&1 || { note "${_c} 가 없어 tmux 를 빌드할 수 없습니다"; return 1; }
	done
	if ! { [ -r /usr/include/ncurses.h ] || [ -r /usr/include/curses.h ] ||
			pkg-config --exists ncurses tinfo 2>/dev/null; }; then
		note "ncurses 헤더가 없어 tmux 를 빌드할 수 없습니다 (libncurses-dev)"
		return 1
	fi
	_tag=${VIMIDE_TMUX_VERSION:-$(curl -s --max-time 30 \
		https://api.github.com/repos/tmux/tmux/releases/latest |
		sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)}
	[ -n "${_tag}" ] || { note "tmux 최신 판을 GitHub 에서 알아내지 못했습니다"; return 1; }
	_w=$(mktemp -d "${TMPDIR:-/tmp}/vimide-tmux.XXXXXX") || return 1
	_j=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
	[ "${_j}" -gt 4 ] && _j=4 # 함께 쓰는 서버다 - 코어를 다 쓰지 않는다
	_ev=${LOCAL}/tmux-deps
	_evflags=''
	# 빌드 출력(컴파일러 경고가 수십 줄)은 파일로 받고, 실패했을 때만 끝을 보여 준다
	_log=${_w}/build.log
	fail_log() { note "$1 (기록: ${_log})"; tail -15 "${_log}" 2>/dev/null | sed 's/^/        /'; }
	if ! pkg-config --exists libevent 2>/dev/null && [ ! -r "${_ev}/lib/libevent.a" ]; then
		say "      libevent 2.1.12 를 ${_ev} 에 정적으로 빌드합니다 (시스템에 헤더가 없음)"
		curl -sL --max-time 300 -o "${_w}/ev.tgz" \
			https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz &&
			tar -xzf "${_w}/ev.tgz" -C "${_w}" &&
			( cd "${_w}/libevent-2.1.12-stable" &&
				./configure --prefix="${_ev}" --disable-shared --enable-static \
					--disable-openssl --disable-samples --disable-libevent-regress &&
				make -j"${_j}" && make install ) >>"${_log}" 2>&1 ||
			{ fail_log "libevent 빌드 실패 (${_w} 에 남겨 둠)"; return 1; }
	fi
	if [ -r "${_ev}/lib/libevent.a" ]; then
		_evflags="LIBEVENT_CFLAGS=-I${_ev}/include LIBEVENT_LIBS=-L${_ev}/lib -levent"
	fi
	say "      tmux ${_tag} 를 ${LOCAL}/tmux-${_tag} 에 빌드합니다 (sudo 없이, 내 홈에만)"
	curl -sL --max-time 300 -o "${_w}/tmux.tgz" \
		"https://github.com/tmux/tmux/releases/download/${_tag}/tmux-${_tag}.tar.gz" &&
		tar -xzf "${_w}/tmux.tgz" -C "${_w}" || { note "tmux ${_tag} 을 받지 못했습니다"; return 1; }
	if ! ( cd "${_w}/tmux-${_tag}" &&
			if [ -n "${_evflags}" ]; then
				./configure --prefix="${LOCAL}/tmux-${_tag}" \
					LIBEVENT_CFLAGS="-I${_ev}/include" LIBEVENT_LIBS="-L${_ev}/lib -levent"
			else
				./configure --prefix="${LOCAL}/tmux-${_tag}"
			fi &&
			make -j"${_j}" && make install ) >>"${_log}" 2>&1; then
		fail_log "tmux 빌드 실패 (${_w} 에 남겨 둠)"
		return 1
	fi
	rm -rf "${_w}"
	mkdir -p "${LOCAL}/bin"
	# 링크가 아니라 래퍼를 둔다. 이미 떠 있는 tmux 서버는 옛 판이고, 새
	# 클라이언트는 거기 붙지 못한다 - 'tmux -2 a' 가 'server version is too
	# old for client' 로 끝난다(개발서버 실측). 서버를 대신 끄지 않는다(남은
	# 세션이 그 사람의 작업이다). 대신 래퍼가 기본 소켓에 옛 서버가 떠 있으면
	# 옛 클라이언트로 보내고, 그 서버를 다 쓰고 끄면 그때부터 새 판을 쓴다.
	# -L/-S 로 소켓을 고른 호출은 곧장 새 판으로 간다.
	_old=$(PATH=/usr/local/bin:/usr/bin:/bin command -v tmux 2>/dev/null || true)
	rm -f "${LOCAL}/bin/tmux"
	{
		echo '#!/bin/sh'
		echo "# vim-ide/tools/deps.sh 가 만든 tmux 래퍼 (새 판: tmux ${_tag})."
		echo "NEW=${LOCAL}/tmux-${_tag}/bin/tmux"
		echo "OLD=${_old}"
		cat <<'EOF'
# 새 tmux 를 쓰되, 고른 소켓(기본, -L, -S)에 옛 판 서버가 떠 있으면 옛
# 클라이언트로 보낸다. 새 클라이언트는 옛 서버에 붙지 못하고('server version
# is too old for client'), 그런데도 종료 코드는 0 이라 has-session 으로는
# 가려지지 않는다(실측) - 그 메시지로 가린다. 옛 서버를 다 쓰고 끄면
# (tmux kill-server) 그다음부터 새 판이 뜬다.
L=''; S=''; want=''
for a do
	if [ -n "$want" ]; then eval "$want=\$a"; want=''; continue; fi
	case "$a" in
		-L) want=L ;; -S) want=S ;; -L?*) L=${a#-L} ;; -S?*) S=${a#-S} ;;
		-c|-f|-T) want=_ ;;
		-*) ;;
		*) break ;;
	esac
done
probe() {
	if [ -n "$S" ]; then "$NEW" -S "$S" "$@"
	elif [ -n "$L" ]; then "$NEW" -L "$L" "$@"
	else "$NEW" "$@"; fi
}
if [ -n "$OLD" ] && [ -x "$OLD" ] &&
		probe list-sessions 2>&1 | grep -q 'server version is too old'; then
	exec "$OLD" "$@"
fi
exec "$NEW" "$@"
EOF
	} > "${LOCAL}/bin/tmux"
	chmod +x "${LOCAL}/bin/tmux"
	note "${LOCAL}/bin/tmux -> tmux ${_tag} (래퍼)"
	if [ -n "${_old}" ] && "${_old}" has-session 2>/dev/null; then
		note "지금 떠 있는 tmux 서버는 옛 판(${_old})입니다. 'tmux' 는 그 서버가 떠 있는"
		note "동안 옛 클라이언트로 붙고, 그 서버를 끄면 그다음부터 새 판으로 엽니다."
	fi
	return 0
}

install_one() {
	_t=$1; _min=$2
	_pkg=$(pkg_for "${_t}")
	case "${OS}" in
		darwin)
			if command -v brew >/dev/null 2>&1; then
				# 이미 깔려 있고 낡았으면 install 은 아무것도 안 한다 - upgrade 로
				if brew list --formula "${_pkg}" >/dev/null 2>&1; then
					say "      brew upgrade ${_pkg}"
					brew upgrade "${_pkg}" && return 0
				fi
				say "      brew install ${_pkg}"
				brew install "${_pkg}" && return 0
			fi
			note "brew 가 없습니다. https://brew.sh 를 먼저 설치하거나 직접 넣으세요."
			return 1
			;;
		debian)
			if can_sudo; then
				say "      sudo apt-get install -y ${_pkg}"
				if sudo apt-get install -y "${_pkg}"; then
					# apt 판이 모자랄 수 있다 (Ubuntu 20.04 의 tmux 는 3.0a)
					_now=$(ver_of "${_t}" -V 2>/dev/null)
					if [ "${_t}" != tmux ] || ver_ge "${_now}" "${_min}"; then
						return 0
					fi
					note "apt 의 tmux ${_now} 는 ${_min} 보다 낮습니다 - 홈에 새 판을 빌드합니다"
				fi
			fi
			# sudo 가 안 된다(또는 apt 판이 모자라다): 홈에 올릴 길이 있으면 그걸로
			if [ "${_t}" = git ] && install_git_local; then
				return 0
			fi
			if [ "${_t}" = tmux ] && install_tmux_local; then
				return 0
			fi
			note "sudo 에 암호가 필요해 시스템에 설치하지 않았습니다."
			note "직접 치실 명령:  sudo apt-get install -y ${_pkg}"
			[ "${_t}" = git ] && note "(git 은 새 판이 필요합니다: sudo add-apt-repository -y ppa:git-core/ppa)"
			return 1
			;;
		rhel)
			can_sudo && { say "      sudo dnf install -y ${_pkg}"; sudo dnf install -y "${_pkg}" && return 0; }
			note "직접 치실 명령:  sudo dnf install -y ${_pkg}"
			return 1
			;;
		arch)
			can_sudo && { say "      sudo pacman -S --noconfirm ${_pkg}"; sudo pacman -S --noconfirm "${_pkg}" && return 0; }
			note "직접 치실 명령:  sudo pacman -S ${_pkg}"
			return 1
			;;
		*)
			note "이 배급판은 모릅니다. ${_t} ${_min} 이상을 직접 넣어 주세요."
			return 1
			;;
	esac
}

# ---------------------------------------------------------------------------
# 훑기
# ---------------------------------------------------------------------------
if [ "${MODE}" = list ]; then
	say "vim-ide 가 쓰는 프로그램"
	printf '%-9s %-7s %-5s %s\n' 이름 최소판 등급 쓰임
	echo "${REQS}" | while IFS='|' read -r t min grade why _cmd _ok; do
		[ -z "${t}" ] && continue
		printf '%-9s %-7s %-5s %s\n' "${t}" "${min}" "${grade}" "${why}"
	done
	exit 0
fi

say "### 의존성 확인 (${OS}) ###"
MISSING=''
printf '  %-10s %-10s %-8s %s\n' tool now need state
echo "${REQS}" | while IFS='|' read -r t min grade why cmd okpat; do
	[ -z "${t}" ] && continue
	if ! command -v "${t}" >/dev/null 2>&1; then
		printf '  %-10s %-10s %-8s %s\n' "${t}" '-' "${min}+" "MISS (${grade})"
		echo "${t}|${min}|${grade}" >> /tmp/vimide-deps-missing.$$
		continue
	fi
	out=$(${cmd} 2>&1 | head -3)
	got=$(printf '%s' "${out}" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
	if [ -n "${okpat}" ] && printf '%s' "${out}" | grep -qi "${okpat}"; then
		# 숫자가 아니라 '무엇인지'로 판정한다 (Universal Ctags 0.0.0)
		printf '  %-10s %-10s %-8s %s\n' "${t}" "${got:-?}" "${min}+" "ok (${okpat})"
	elif [ -z "${got}" ]; then
		printf '  %-10s %-10s %-8s %s\n' "${t}" '?' "${min}+" 'ok (판을 못 읽음)'
	elif ver_ge "${got}" "${min}"; then
		printf '  %-10s %-10s %-8s %s\n' "${t}" "${got}" "${min}+" ok
	else
		printf '  %-10s %-10s %-8s %s\n' "${t}" "${got}" "${min}+" "OLD (${grade})"
		echo "${t}|${min}|${grade}" >> /tmp/vimide-deps-missing.$$
	fi
done

# while 이 파이프 안이라 부모의 변수를 못 고친다(POSIX sh). 파일로 받는다.
if [ -s /tmp/vimide-deps-missing.$$ ]; then
	MISSING=$(cat /tmp/vimide-deps-missing.$$)
fi
rm -f /tmp/vimide-deps-missing.$$

# 저장소가 들고 다니는 도우미가 ~/.local/bin 에 왔는지도 본다.
#
# indexfiles.sh 가 없으면 autoindex 는 아무것도 만들지 않는다 - 조용히.
# '무엇을 색인할까'를 정하는 단 한 곳이라, 없으면 ctags_build 가 그냥
# 돌아 나간다. install.sh 가 복사하지만, 복사가 안 됐는지는 눈에 안 띈다.
for _h in indexfiles.sh ctags-nice; do
	if [ -x "${LOCAL}/bin/${_h}" ]; then
		printf '  %-10s %-10s %-8s %s\n' "${_h}" '-' '-' 'ok (저장소 것)'
	elif [ -r "${VIMIDE}/.local/bin/${_h}" ]; then
		if [ "${MODE}" = check ]; then
			printf '  %-10s %-10s %-8s %s\n' "${_h}" '-' '-' 'MISS (복사하면 된다)'
		else
			mkdir -p "${LOCAL}/bin"
			cp -f "${VIMIDE}/.local/bin/${_h}" "${LOCAL}/bin/${_h}"
			chmod +x "${LOCAL}/bin/${_h}"
			printf '  %-10s %-10s %-8s %s\n' "${_h}" '-' '-' '넣었음'
		fi
	else
		printf '  %-10s %-10s %-8s %s\n' "${_h}" '-' '-' '저장소에도 없음'
	fi
done

if [ -z "${MISSING}" ]; then
	say "### 의존성 모두 충족 ###"
	exit 0
fi

if [ "${MODE}" = check ]; then
	say "### 모자란 것이 있습니다 (--check 라 설치하지 않습니다) ###"
	exit 1
fi

if [ "${VIMIDE_DEPS:-1}" = "0" ]; then
	say "### VIMIDE_DEPS=0 이라 설치하지 않습니다 ###"
	exit 0
fi

say "### 모자란 것을 채웁니다 ###"
echo "${MISSING}" | while IFS='|' read -r t min grade; do
	[ -z "${t}" ] && continue
	say "  - ${t} (${min} 이상 필요)"
	install_one "${t}" "${min}" || true
done

say "### 다시 확인 ###"
echo "${REQS}" | while IFS='|' read -r t min grade why cmd okpat; do
	[ -z "${t}" ] && continue
	command -v "${t}" >/dev/null 2>&1 || { printf '  %-10s 아직 없음\n' "${t}"; continue; }
	out=$(${cmd} 2>&1 | head -3)
	got=$(printf '%s' "${out}" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
	if { [ -n "${okpat}" ] && printf '%s' "${out}" | grep -qi "${okpat}"; } \
			|| ver_ge "${got:-0}" "${min}"; then
		printf '  %-10s %s  ok\n' "${t}" "${got:-?}"
	else
		printf '  %-10s %s  아직 %s 미만\n' "${t}" "${got:-?}" "${min}"
	fi
done
