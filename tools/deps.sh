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
global|6.6|must|심볼 색인(gtags/global). <C-]> 와 관계 목록의 바탕|global --version|
ctags|5.9|want|Tagbar/aerial 의 심볼 목록. Universal Ctags 라야 C11 익명 구조체를 본다|ctags --version|Universal Ctags
rg|11|want|<C-g> 의 경로 검색. 없으면 grep 으로 떨어진다(느리다)|rg --version|
curl|7|must|vim-plug 부트스트랩과 플러그인 내려받기|curl --version|
make|3.8|want|telescope-fzf-native 와 소스 빌드|make --version|
node|16|want|coc.nvim 의 언어 서버|node --version|
python3|3.6|want|일부 플러그인과 :pyx|python3 --version|
'

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

install_one() {
	_t=$1; _min=$2
	_pkg=$(pkg_for "${_t}")
	case "${OS}" in
		darwin)
			if command -v brew >/dev/null 2>&1; then
				say "      brew install ${_pkg}"
				brew install "${_pkg}" && return 0
			fi
			note "brew 가 없습니다. https://brew.sh 를 먼저 설치하거나 직접 넣으세요."
			return 1
			;;
		debian)
			if can_sudo; then
				say "      sudo apt-get install -y ${_pkg}"
				sudo apt-get install -y "${_pkg}" && return 0
			fi
			# sudo 가 안 된다: 홈에 올릴 길이 있으면 그걸로
			if [ "${_t}" = git ] && install_git_local; then
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
