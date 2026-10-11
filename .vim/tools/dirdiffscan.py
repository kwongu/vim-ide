#!/usr/bin/env python3
# dirdiffscan.py - vim-ide DirDiff 의 뒤쪽: 두 디렉터리를 훑어 비교 트리를 만든다
#
#   python3 -X utf8 dirdiffscan.py <A> <B> [--exclude 'pat,pat'] [--trust-mtime 1]
#                                          [--ignore-eol 1] [--eol-max-mb 4]
#                                          [--workers 16] [--debug]
#
# nvim(dirdiffview.lua)이 stdin 으로 명령을, 이 프로그램이 stdout 으로 사건을 한 줄에
# JSON 하나씩 주고받는다. 모형(트리)은 여기에만 있고 nvim 은 펼친 디렉터리만 받아 간다
# - Android 트리처럼 파일이 수십만이어도 nvim 쪽은 보이는 만큼이다.
#
# 빠른 이유 (DirDiff.vim 의 'diff -r --brief' 는 이름이 같은 파일을 모두 끝까지 읽은
# 뒤에야 결과를 내고, 그동안 편집기를 세운다 - Android 15 maincore/external 두 벌
# (15만·30만 파일)에서 120초 동안 한 줄도 내지 못했다, 실측):
#   * 디렉터리는 readdir 만으로 훑는다 (종류는 d_type) - stat 을 하지 않는다. 개발서버의
#     파일 시스템은 stat 한 번이 수 ms 라, 처음에는 맨 위 층 425 개를 stat 하느라 5초가
#     걸렸다 (실측). stat 은 양쪽에 다 있는 파일(크기를 견줄 것)과, nvim 이 펼쳐 둔
#     디렉터리의 항목(크기·날짜를 보일 것)에만
#   * 크기가 다르면 그 자리에서 '다름', 크기와 수정 시각이 같으면 '같음' (Beyond Compare
#     의 빠른 비교와 같다, --trust-mtime 0 으로 끈다). 나머지만 내용을 읽는다
#   * 줄 끝만 다른 짝 (--ignore-eol 1, 기본): 바이트가 달라도 CRLF -> LF 로 맞추고 파일 끝 줄바꿈이
#     없는 쪽에 하나 붙여 보아 같으면 '같음' 이고 항목에 eol 표시(아래)를 단다. 편집기의 줄 비교(vim
#     diff)는 줄 끝을 보지 않아 비교 탭에는 차이가 하나도 없는데, 트리만 크기가 1 바이트 다르다고
#     빨강 ≠ 이었다 (사용자 보고: tsnd_alsa.h 2,008 / 2,009 바이트 - A 에 마지막 줄바꿈이 없을 뿐).
#     맞추는 것은 비교 탭이 읽는 대로다: 줄마다 CRLF 인 쪽만 dos 로 읽어 CR 이 빠지고(dirdiffview.lua
#     의 show_file), CRLF·LF 가 섞인 쪽은 CR 이 글로 남아 ^M 줄이 차이로 보인다 - 그래서 섞인 쪽은
#     CRLF 를 맞추지 않는다 (eol_same 의 두 번째 견주기. 트리는 ≈ 인데 비교 탭은 빨강이면 거꾸로 된
#     같은 어긋남이다). 크기가 다른 짝을 모두 읽지는 않는다 - 그럴 수 있는 것만 (eol_maybe: 차이가
#     1~2 바이트(끝 줄바꿈), 또는 줄 수만큼(CRLF<->LF - 한 줄 평균 4 바이트 넘게 잡아 작은 쪽의 1/4 + 2
#     까지, 4 KB 이하 파일은 줄마다 1 바이트까지), 두 파일 모두 --eol-max-mb 이하). 그런 짝도 크기를
#     본 그 자리에서 정하지 않고 내용 읽기 패로 넘긴다 (편집기는 기다리지 않는다, 순서도 그대로). 거기서도
#     한쪽의 앞 64 KB 로 먼저 거른다 (eol_sizes - 정말 고친 파일은 대개 열기 한 번에 끝난다). 읽다가 처음
#     어긋나는 곳에서 멈추고, NUL 이 있으면(바이너리) 그 자리에서 '다름'. 크기가 같은데 바이트가
#     다른 짝은 어긋난 덩어리에 CR 이 있을 때만 다시 맞춰 본다 (CR 이 없으면 줄 끝 차이일 수 없다)
#   * readdir·stat·내용 읽기를 일꾼 여럿이 함께 - 네트워크 파일 시스템은 한 번 한 번이
#     기다림이라 여럿이 동시에 하면 그만큼 빠르다
#   * 순서 (job_key): nvim 이 펼쳐 둔 디렉터리의 항목 > 펼쳐 둔 디렉터리 아래 > 나머지,
#     그 안에서 맨 위 폴더를 화면 순서대로, 얕은 것부터. 일꾼은 두 패로 - 훑기·크기
#     (메타데이터) 패와 내용 읽기 패. 따로 두어야 한쪽만 하느라 다른 쪽이 멈추지 않는다:
#     훑기를 모두 끝낸 뒤에 크기를 보았더니 Android 트리에서 120초 동안 '다름' 을 4개밖에
#     못 찾았고, 크기를 모두 본 뒤에 내용을 읽게 하니 60초 동안 크기 28만 건을 보고도
#     내용 비교는 0 이었다 (따로 받은 두 벌은 수정 시각이 달라 거의 모두 내용을 읽어야
#     한다, 실측)
#
# 명령 (nvim -> 여기)
#   {"cmd":"list","id":N,"dir":"rel"}        그 디렉터리의 자식들 (그리고 바뀌면 알려 달라)
#   {"cmd":"unlist","dir":"rel"}             더는 알리지 않아도 된다
#   {"cmd":"next","id":N,"from":"rel","step":1|-1[,"bits":B]}   다음/앞 '차이' 항목 (조상 목록째).
#                                            bits 가 있으면 표시(mask)가 그 비트에 걸리는 항목 (보기)
#   {"cmd":"expand","id":N,"dir":"rel"[,"bits":B]}  아래의 '차이 있는'(bits: 그 비트에 걸리는)
#                                            디렉터리 목록을 한꺼번에
#   {"cmd":"refresh","paths":["rel",...]}    그 항목만 다시 본다. 목록을 받아 간 부모는 'list' 로
#                                            다시 보낸다
#   {"cmd":"copy","id":N,"from":"a"|"b","paths":["rel",...]}
#                                            파일·디렉터리를 반대쪽으로 복사하고 (copier) 그곳만
#                                            다시 본다. 끝나면 'copied' 를 먼저, 그다음 부모 'list'
#   {"cmd":"quit"}
# 사건 (여기 -> nvim)
#   {"ev":"list","id":N,"dir":rel,"entries":[[name,ka,kb,sa,sb,ma,mb,st,rerr,mask,eol],...]}
#   {"ev":"u","d":dir,"n":name,"s":st,"e":[...같은 항목...]}   목록을 받아 간 디렉터리 안
#   {"ev":"reveal","id":N,"path":rel|null,"lists":{dir:[entries]}}
#   {"ev":"lists","id":N,"lists":{dir:[entries]}}
#   {"ev":"progress", ...}                    again: 끝난 뒤 복사·저장으로 다시 보는 중
#                                            cats: {표시: 항목 수} (보기 메뉴의 수)
#   {"ev":"copied","id":N,"files":n,"dirs":n,"skipped":[[rel,why]],"failed":[[rel,why]],
#    "roots":[rel,...]}                      roots: 다시 본 곳 (그 아래 목록은 새로 받는다)
# 상태: same diff onlyA onlyB pend   종류: d f l o (없으면 null)
# 표시(mask): 보기(Beyond Compare 의 보기 거르기 - 좌측 최신, 고아 ...)에 쓴다. 아래 SAME ... UNK
# eol: 0, 또는 '같음' 인데 줄 끝만 다른 짝 - 쪽마다 3 비트 (A 는 아래 3 비트, B 는 그 위 3 비트):
#   1 CRLF 줄이 있다   2 LF 만인 줄이 있다   4 파일 끝 줄바꿈이 없다. 상태는 'same', 표시는 SAME 그대로라
#   보기·<C-n>/<C-p>·폴더의 판정·수(same)는 같은 파일로 다룬다 - nvim 은 이것으로 판정 칸에 ≈ 를 단다.
#   progress 의 eol 은 그런 짝의 수 (same 에 들어 있다)

import collections
import fnmatch
import gc
import heapq
import io
import json
import os
import re
import shutil
import signal
import stat
import sys
import threading
import time
import unicodedata

BAD = ('diff', 'onlyA', 'onlyB')
started = time.monotonic()

# 표시(mask): 항목이 무엇인지 비트로. nvim 은 이것으로 보기를 거른다 (dirdiffview.lua 의 MODES)
#   SAME 같음   NA A 가 최신 (양쪽에 있고 내용이 다르고 A 의 수정 시각이 늦다)   NB B 가 최신
#   DX 그 밖의 다름 (시각이 같거나 모름, 디렉터리 / 파일로 종류가 다름)   OA A 에만   OB B 에만
#   PEND 아직 견주는 중   UNK 아직 훑지 않은 디렉터리 (아래에 무엇이 있을지 모른다)
# 양쪽에 다 있는 디렉터리의 표시는 그 아래 항목들의 것을 합한 것이다 - '그 아래에 좌측 최신이 있는
# 디렉터리' 만 보이려면 nvim 이 받아 가지 않은(접힌) 아래까지 알아야 해서 여기서 센다
SAME, NA, NB, DX, OA, OB, PEND, UNK = 1, 2, 4, 8, 16, 32, 64, 128


def opt(name, default):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


ROOT = {'a': os.path.abspath(sys.argv[1]), 'b': os.path.abspath(sys.argv[2])}
EXCLUDES = [p for p in opt('--exclude', '').split(',') if p]
# 무늬 여럿을 정규식 하나로 - 항목마다 fnmatch 를 무늬 수만큼 부르면 그것만으로 CPU 를 먹는다
EXCLUDE_RE = re.compile('|'.join('(?:%s)' % fnmatch.translate(p) for p in EXCLUDES)).match \
    if EXCLUDES else None
TRUST_MTIME = opt('--trust-mtime', '1') == '1'
IGNORE_EOL = opt('--ignore-eol', '1') == '1'
try:
    EOL_MAX = int(float(opt('--eol-max-mb', '4')) * 1048576)
except (ValueError, OverflowError):
    # 'inf'·'1e400' 은 OverflowError (nvim 에서 1.0/0 을 넘기면 tostring 이 'inf' 다) - 시작부터 죽었다
    EOL_MAX = 4 << 20
WORKERS = max(1, int(opt('--workers', '16')))
DEBUG = '--debug' in sys.argv

SCAN, STAT, INFO, CMP = 0, 1, 2, 3


def dbg(*a):
    if DEBUG:
        sys.stderr.write('%.3f %s\n' % (time.monotonic() - started, ' '.join(str(x) for x in a)))
        sys.stderr.flush()


def excluded(name):
    return EXCLUDE_RE is not None and EXCLUDE_RE(name) is not None


class Node:
    __slots__ = ('name', 'parent', 'ka', 'kb', 'sa', 'sb', 'ma', 'mb', 'status', 'kids',
                 'scanned', 'pend', 'bad', 'sub', 'depth', 'done', 'waiters', 'group',
                 'queued', 'rerr', 'dead', 'mask', 'agg', 'eol')

    def __init__(self, name, parent):
        self.name = name
        self.parent = parent
        self.ka = self.kb = None
        self.sa = self.sb = self.ma = self.mb = None
        self.status = 'pend'
        self.kids = None          # name -> Node (디렉터리만)
        self.scanned = False
        self.pend = 0
        self.bad = 0
        self.sub = False          # nvim 이 목록을 받아 갔다
        self.depth = 0 if parent is None else parent.depth + 1
        self.group = 0 if parent is None else parent.group   # 맨 위 폴더의 화면 순서
        self.done = 0             # 맡긴 일 (1 << SCAN/STAT/INFO/CMP) - 두 번 하지 않는다
        self.waiters = None       # 훑기가 끝나면 목록을 돌려줄 요청들
        self.queued = 0           # 줄에 넣어 둔 일 (종류 x 급수 3 비트씩) - 같은 것을 또 넣지 않는다
        self.rerr = None          # 디렉터리를 못 읽은 쪽 'a' 'b' 'ab'
        self.dead = False         # refresh 로 모형에서 떼어 냈다 (늦게 온 결과는 버린다)
        self.mask = 0             # 표시 (SAME ... UNK)
        self.agg = None           # 훑은 '양쪽 디렉터리': 자식들의 표시 비트마다 그 비트를 가진 자식 수
        self.eol = 0              # 같음인데 줄 끝만 다르다 (쪽마다 3 비트 - 맨 위의 eol)

    def rel(self):
        parts = []
        n = self
        while n.parent is not None:
            parts.append(n.name)
            n = n.parent
        return '/'.join(reversed(parts))

    def isdir(self):
        return self.ka == 'd' or self.kb == 'd'

    def both_dirs(self):
        return self.ka == 'd' and self.kb == 'd'


out = []
last_flush = [0.0]


def emit(obj, now=False):
    # 이름은 바이트 그대로 낸다: UTF-8 이 아닌 이름(CP949 zip 을 푼 것 등)은 파이썬이
    # '\udcXX' 로 읽는데, ensure_ascii 로 내면 그 이스케이프를 nvim 의 json 이 못 읽어 사건
    # 하나(그 디렉터리 목록 전체)를 통째로 버렸다. stdout/stdin 은 surrogateescape 라
    # 원래 바이트로 나가고, nvim 이 돌려보내는 이름도 같은 이름으로 돌아온다
    out.append(json.dumps(obj, ensure_ascii=False, separators=(',', ':')))
    if now:
        flush()


def flush():
    if out:
        data = '\n'.join(out) + '\n'
        del out[:]
        try:
            sys.stdout.write(data)
            sys.stdout.flush()
        except BrokenPipeError:
            bail(0)
    last_flush[0] = time.monotonic()


counts = {'pend': 0, 'diff': 0, 'onlyA': 0, 'onlyB': 0, 'same': 0, 'dirs': 0, 'err': 0,
          'eol': 0}       # eol: same 가운데 줄 끝만 다른 것 (따로 더하지 않는다)
masks = {}                # 표시 -> 항목 수 (counts 처럼 한쪽에만 있는 디렉터리 안은 세지 않는다)
masks_ver = [0]
root = Node('', None)
root.ka = root.kb = 'd'
root.mask = UNK
# 일꾼과 주고받기. 처음에는 queue.Queue 와 일 하나마다 잠금·깨우기였는데, 일꾼 16 이
# 잠금과 GIL 을 다투느라 결과가 5만 건씩 밀렸다 (실측) - 그래서
#   * 일 넣기(submit)는 주 줄기에서만 - staged 에 모았다가 한 번에 (push_staged)
#   * 일꾼은 같은 종류를 여럿 한꺼번에 꺼내고 (BATCH), 결과도 한 묶음으로 보낸다
#   * 결과 받기는 deque (잠금 없음) + 주 줄기가 잘 때만 깨운다
# 줄에는 (순서 정수, 항목) 만 - 항목이 수십만이라 튜플을 길게 두면 메모리가 크다
jobs = ([], [])           # 0 메타데이터 (훑기·크기·날짜), 1 내용 읽기
job_lock = threading.Lock()
job_cond = threading.Condition(job_lock)
staged = []
seq = [0]
outstanding = [0]         # 맡겼지만 결과가 아직 안 온 일 (주 줄기에서만 센다)
ops = [0, 0, 0, 0]        # 한 일 (SCAN STAT INFO CMP) - 진행 상황에 낸다
inbox = collections.deque()
wake = threading.Event()
main_idle = [False]


def post(item):
    inbox.append(item)
    if main_idle[0]:
        wake.set()


def entry(n):
    return [n.name, n.ka, n.kb, n.sa, n.sb, n.ma, n.mb, n.status, n.rerr, n.mask, n.eol]


def is_item(n):
    return (n.status in BAD and not n.both_dirs()) or n.rerr is not None


def count(n, st, sign):
    if n.both_dirs() or n.parent is None or not n.parent.both_dirs():
        return  # 한쪽에만 있는 디렉터리 안의 것은 세지 않는다 (그 디렉터리 하나로 센다)
    if st in counts:
        counts[st] += sign


def visible(n):
    return n.sub or (n.parent is not None and n.parent.sub)


def item_mask(n):
    st = n.status
    if st == 'same':
        return SAME
    if st == 'pend':
        return PEND
    if st == 'onlyA':
        return OA
    if st == 'onlyB':
        return OB
    if n.ka != n.kb:
        # 한쪽은 디렉터리, 한쪽은 파일 (또는 못 읽은 쪽): 다름. 디렉터리인 쪽은 그쪽에만 있는
        # 디렉터리이기도 하다 - 그 아래는 모두 그쪽 고아라, 고아 보기에서도 펼쳐 볼 수 있게
        return DX | (OA if n.ka == 'd' else 0) | (OB if n.kb == 'd' else 0)
    if n.ma is not None and n.mb is not None:
        if n.ma > n.mb:
            return NA
        if n.mb > n.ma:
            return NB
    return DX


def dir_mask(n):
    if n.agg is None:
        return UNK
    m = DX if n.rerr else 0   # 못 읽은 쪽이 있다 - 그 자체로 '다름' (on_scan 의 unsure)
    a = n.agg
    for i in range(8):
        if a[i]:
            m |= 1 << i
    return m


def tally(m, sign):
    masks[m] = masks.get(m, 0) + sign
    masks_ver[0] += 1


def agg_move(a, old, new):
    # 자식 하나의 표시가 old -> new 로: 셈을 옮기고, 0 을 넘나든 비트가 있었는지 돌려준다
    cross = False
    d = old ^ new
    i = 0
    while d:
        if d & 1:
            if (new >> i) & 1:
                a[i] += 1
                cross = cross or a[i] == 1
            else:
                a[i] -= 1
                cross = cross or a[i] == 0
        d >>= 1
        i += 1
    return cross


def mask_up(p, old, new):
    # p 의 자식 하나의 표시가 바뀌었다. p 의 표시가 바뀔 때만 그 위로 - 비트가 생기거나 없어질
    # 때만이다. 파일 하나가 정해질 때마다 맨 위까지 올라가지 않는다 (파일이 수십만이다)
    while p is not None and p.agg is not None:
        if not agg_move(p.agg, old, new):
            return
        m = dir_mask(p)
        if m == p.mask:
            return
        old, new = p.mask, m
        p.mask = m
        notify_parent(p)
        p = p.parent


def remask(n):
    # n 의 표시를 다시 셈한다. 바뀌었으면 True - n 자신의 줄은 부르는 쪽이 알린다
    m = dir_mask(n) if n.both_dirs() else item_mask(n)
    old = n.mask
    if m == old:
        return False
    n.mask = m
    p = n.parent
    if p is not None and p.agg is not None:
        if not n.both_dirs():
            tally(old, -1)
            tally(m, 1)
        mask_up(p, old, m)
    return True


def tier(n, force_vis):
    # 0 펼쳐 둔 디렉터리의 항목, 1 펼쳐 둔 디렉터리 아래 (맨 위는 빼고), 2 나머지
    if force_vis or visible(n):
        return 0
    p = n.parent
    while p is not None and p.parent is not None:
        if p.sub:
            return 1
        p = p.parent
    return 2


def submit(kind, n, force_vis=False):
    if n.done & (1 << kind):
        return    # 이미 꺼내 갔다 (결과가 오는 중) - 또 넣어도 일꾼은 건너뛴다
    t = tier(n, force_vis)
    # 같은 급수나 더 급한 것으로 이미 줄에 있으면 넣지 않는다. 처음에는 C-n·펼치기 때마다
    # 펼친 디렉터리의 남은 일을 모두 한 벌씩 또 넣어, C-n 30번에 줄이 5만에서 143만으로,
    # 메모리가 63MB 에서 211MB 로 불었다 (실측)
    mask = ((1 << (t + 1)) - 1) << (kind * 3)
    if n.queued & mask:
        return
    n.queued |= 1 << (kind * 3 + t)
    seq[0] += 1
    key = ((t << 16 | min(n.group, 0xffff)) << 8 | min(n.depth, 0xff)) << 2 | kind
    staged.append((key << 36 | seq[0], n))
    outstanding[0] += 1


def job_kind(job):
    return (job[0] >> 36) & 3


def job_tier(job):
    return job[0] >> 62


def push_staged():
    if not staged:
        return
    with job_cond:
        for job in staged:
            heapq.heappush(jobs[job_kind(job) == CMP], job)
        job_cond.notify(len(staged))
    del staged[:]


def notify_parent(n):
    p = n.parent
    if p is not None and p.sub:
        emit({'ev': 'u', 'd': p.rel(), 'n': n.name, 's': n.status, 'e': entry(n)})


def set_status(n, st):
    old = n.status
    if old == st or n.dead:
        return
    n.status = st
    if not n.both_dirs():
        remask(n)   # 알리기 전에 - 알리는 항목에 새 표시가 실린다
    count(n, old, -1)
    count(n, st, 1)
    notify_parent(n)
    p = n.parent
    if p is None:
        return
    if old == 'pend':
        p.pend -= 1
    elif old in BAD:
        p.bad -= 1
    if st == 'pend':
        p.pend += 1
    elif st in BAD:
        p.bad += 1
    if p.both_dirs():
        set_status(p, dir_status(p))


def dir_status(n):
    if n.bad > 0:
        return 'diff'
    if not n.scanned or n.pend > 0:
        return 'pend'
    return 'same'


# ---------------------------------------------------------------------------
# 일꾼이 하는 일 (파일 시스템에 닿는 것은 모두 여기)
# ---------------------------------------------------------------------------

def listdir(side, rel):
    base = ROOT[side]
    path = os.path.join(base, rel) if rel else base
    res = {}
    err = 0
    try:
        with os.scandir(path) as it:
            for e in it:
                if excluded(e.name):
                    continue
                try:
                    # d_type 으로 - stat 하지 않는다 (d_type 을 모르는 파일 시스템이면 파이썬이 lstat)
                    if e.is_symlink():
                        k = 'l'
                    elif e.is_dir(follow_symlinks=False):
                        k = 'd'
                    elif e.is_file(follow_symlinks=False):
                        k = 'f'
                    else:
                        k = 'o'
                except OSError:
                    err += 1
                    continue
                res[e.name] = k
    except OSError:
        return {}, err + 1, True
    return res, err, False


def alias(rel, la, lb):
    # macOS(APFS)는 이름의 정규화(NFC/NFD)와 기본으로 대소문자를 가리지 않는다: A 의 'café'(NFC)
    # 와 B 의 'café'(NFD), 'Foo.c' 와 'foo.c' 가 같은 파일이다. 이름 그대로 짝지었더니 두 줄
    # ('A 에만'·'B 에만')로 나뉘어 내용을 견주지 않았고, A 쪽을 복사하면 말없이 B 의 다른 철자
    # 파일을 덮었는데 그 줄은 그대로 남았다. 그런 B 쪽 이름을 A 의 철자로 바꾼다 - 그 철자로
    # 열어도 B 의 같은 파일이 열린다. 같은 파일임을 lstat 으로 확인한 것만 (두 철자가 따로
    # 있는 리눅스·SMB 는 그대로). 한쪽에만 있는 이름끼리만 보므로 양쪽에 다 있는 것은 공짜다
    only_b = [x for x in lb if x not in la]
    if not only_b:
        return
    keys = {}
    for x in la:
        if x not in lb:
            keys.setdefault(unicodedata.normalize('NFC', x).casefold(), []).append(x)
    if not keys:
        return
    base = os.path.join(ROOT['b'], rel) if rel else ROOT['b']
    for x in only_b:
        ys = keys.get(unicodedata.normalize('NFC', x).casefold())
        if not ys or len(ys) != 1 or ys[0] in lb:
            continue
        try:
            if not os.path.samestat(os.lstat(os.path.join(base, x)), os.lstat(os.path.join(base, ys[0]))):
                continue
        except OSError:
            continue
        lb[ys[0]] = lb.pop(x)


def lstat(side, rel):
    try:
        st = os.lstat(os.path.join(ROOT[side], rel))
        return (None if stat.S_ISDIR(st.st_mode) else st.st_size, int(st.st_mtime))
    except OSError:
        return None


def eol_maybe(sa, sb):
    # 크기가 다른 짝이 줄 끝만 다를 수 있는가 (그런 것만 내용을 읽는다 - 크기가 다른 짝은 대개 정말
    # 고친 파일이고, 예전에는 읽지 않고 곧바로 '다름' 이었다). 차이 d 는 CRLF 줄 수의 차 + 끝 줄바꿈
    # (0~2 바이트). 빈 파일은 줄 끝을 맞출 것이 없다 ('' 와 '\n' 은 다르다)
    if not IGNORE_EOL or sa is None or sb is None:
        return False
    lo, hi = min(sa, sb), max(sa, sb)
    if lo <= 0 or hi > EOL_MAX:
        return False
    d = hi - lo
    # 끝 줄바꿈 (LF 1, CRLF 2) / CRLF<->LF: 한 줄 평균이 4 바이트를 넘는다고 보고 작은 쪽의 1/4 (+ 끝
    # 줄바꿈) 까지 / 4 KB 이하는 읽기가 한 번이라 줄마다 1 바이트(짧은 줄)까지. 고른 짝도 eol_sizes 가
    # 한쪽의 앞 64 KB 로 먼저 거르므로 (1/8 이던 것을) 넓혔다 - 'abc\r\n' 같은 짧은 줄 파일
    return d <= 2 or (d - 2) * 4 <= lo or (hi <= 4096 and d <= lo + 2)


class _EolSide:
    # 줄 끝을 맞춘 글을 조금씩 (eol_same). held: 덩어리 끝의 CR - 다음 덩어리가 LF 로 시작하면 CRLF.
    # norm: CRLF 를 LF 로 맞춘다 (False: 바이트 그대로 - 끝 줄바꿈만 맞춘다. 섞인 쪽, eol_same)
    __slots__ = ('f', 'buf', 'held', 'eof', 'bits', 'total', 'last', 'norm')

    def __init__(self, f, norm=True):
        self.f = f
        self.buf = b''
        self.held = False
        self.eof = False
        self.bits = 0         # 1 CRLF 줄, 2 LF 만인 줄, 4 끝 줄바꿈 없음 (맨 위의 eol)
        self.total = 0
        self.last = 0
        self.norm = norm

    def feed(self, size):
        raw = self.f.read(size)
        if not raw:
            self.eof = True
            if self.held:
                self.buf += b'\r'    # 파일 끝의 홀로 선 CR 은 줄 끝이 아니라 글이다
                self.held = False
            if self.total and self.last != 10:
                self.bits |= 4
                self.buf += b'\n'    # 끝 줄바꿈이 없는 쪽에 하나 (vim 의 noeol 과 같게 본다)
            return True
        if b'\0' in raw:
            return False          # 바이너리 - 줄 끝을 맞출 것이 아니다
        self.total += len(raw)
        self.last = raw[-1]
        if self.held:
            raw = b'\r' + raw
            self.held = False
        if raw[-1] == 13:
            raw = raw[:-1]
            self.held = True
        crlf = raw.count(b'\r\n')
        if crlf:
            self.bits |= 1
            if self.norm:
                raw = raw.replace(b'\r\n', b'\n')
        if raw.count(b'\n') > crlf:
            self.bits |= 2
        self.buf += raw
        return True


def eol_same(fa, fb, na=True, nb=True):
    # 줄 끝을 맞추면 같은가: 같으면 eol 표시(0 이 아닌 수), 아니면 False. 앞에서부터 처음 어긋나는 곳까지만
    # 읽는다 (덩어리는 64 KB 에서 1 MB 까지 늘린다 - 정말 다른 파일은 대개 앞쪽에서 끝난다).
    # na / nb: 그쪽의 CRLF 를 맞춘다. 처음에는 두 쪽 다 맞춰 보고, 섞인 쪽(CRLF 줄과 LF 만인 줄이 함께 -
    # bits & 3 == 3)이 있으면 비교 탭이 읽는 대로 한 번 더 견준다: 편집기는 줄마다 CRLF 인 파일만 dos 로
    # 읽고('fileformats' 가 unix,dos 여도 LF 만인 줄이 하나라도 있으면 unix), 섞인 쪽의 CR 은 글로 남는다.
    # 그러니 섞인 쪽은 바이트 그대로, 맞은편은 줄마다 CRLF 일 때만 맞춘다. 맞추지 않으면 트리는 ≈(같음,
    # 보기·<C-n> 에서 빠진다)인데 비교 탭은 ^M 줄마다 빨강이었다 - 사용자 보고의 거꾸로 (검토에서 실측).
    # 두 번째 견주기는 섞인 파일에서만 (드물다)
    a, b = _EolSide(fa, na), _EolSide(fb, nb)
    size = 1 << 16
    while True:
        for x in (a, b):
            if not x.eof and len(x.buf) < size and not x.feed(size):
                return False
        m = min(len(a.buf), len(b.buf))
        if m:
            if a.buf[:m] != b.buf[:m]:
                return False
            a.buf = a.buf[m:]
            b.buf = b.buf[m:]
        if a.eof and b.eof:
            if a.buf or b.buf:
                return False
            bits = a.bits | b.bits << 3
            if na and nb and (a.bits & 3 == 3 or b.bits & 3 == 3):
                # 섞인 쪽은 norm=False 라 다시 들어와도 여기는 지나지 않는다
                fa.seek(0)
                fb.seek(0)
                return bits if eol_same(fa, fb, a.bits & 3 == 1, b.bits & 3 == 1) else False
            return bits or 1
        if (a.eof and not a.buf and b.buf) or (b.eof and not b.buf and a.buf):
            return False
        size = min(size << 1, 1 << 20)


def eol_sizes(pa, pb, sa, sb):
    # 크기가 다른 짝 (eol_maybe 가 고른 것). 두 파일을 견주기 앞에 한쪽의 앞 64 KB 로 거른다 - 크기가
    # 조금 다른 짝은 대개 정말 고친 파일이고(예전에는 읽지 않고 '다름'), 서버의 파일 시스템은 열기 한
    # 번이 몇 ms 다. 차이 d 로 (섞인 쪽은 CRLF 를 맞추지 않으니 - eol_same - 그런 짝의 크기는 끝 줄바꿈
    # 1 바이트밖에 다를 수 없다):
    #   d > 2   CRLF<->LF 뿐이고 큰 쪽이 줄마다 CRLF 다. 큰 쪽의 앞에 LF 만인 줄이 있거나, 다 읽혔는데
    #           CRLF 가 d - 1 개보다 적으면(끝 줄바꿈은 많아야 2 바이트) 다르다 - 작은 쪽은 열지도 않는다
    #   d <= 2  끝 줄바꿈만 다르면 작은 쪽에 끝 줄바꿈이 없다. 작은 쪽이 줄바꿈으로 끝나면 CRLF<->LF 인데
    #           그러면 줄이 넷 이하다 (n 줄의 크기 차는 n-2 ~ n+1) - 줄바꿈이 넷을 넘으면 다르다. 1~2
    #           바이트 고친 파일(오타, 숫자 하나)은 대개 여기서 끝난다
    big, small = (pa, pb) if sa > sb else (pb, pa)
    d = abs(sa - sb)
    with open(big if d > 2 else small, 'rb') as f:
        head = f.read(1 << 16)
        nl = head.count(b'\n')
        if d > 2:
            crlf = head.count(b'\r\n')   # 맨 앞의 LF 는 앞에 CR 이 없다 (파일의 처음)
            if nl > crlf or (len(head) < 1 << 16 and crlf < d - 1):
                return False
        elif nl > 4:
            if len(head) < 1 << 16:
                tail = head[-1:]
            else:
                f.seek(-1, 2)
                tail = f.read(1)
            if tail == b'\n':
                return False
    with open(pa, 'rb') as fa, open(pb, 'rb') as fb:
        return eol_same(fa, fb)


def same_content(rel, sa=None, sb=None):
    # True 같음, False 다름, None 못 읽음, 0 이 아닌 수: 줄 끝만 다르다 (eol 표시)
    pa = os.path.join(ROOT['a'], rel)
    pb = os.path.join(ROOT['b'], rel)
    try:
        if sa != sb:
            # 크기가 다르면 eol_maybe 가 고른 것만 읽는다 - 보통은 on_stat 이 고른 것만 오지만, INFO(펼친
            # 디렉터리의 날짜)로 크기를 먼저 안 짝은 submit_pending 이 on_stat 을 거치지 않고 곧바로 보낸다
            # (--ignore-eol 0 이나 한도를 넘는 파일도)
            if not eol_maybe(sa, sb):
                return False
            try:
                return eol_sizes(pa, pb, sa, sb)
            except OSError:
                # 크기가 달라 '다름' 은 이미 안다 - 줄 끝만 다른지 보려던 것이라 읽기 실패로 세지 않는다
                # (예전처럼 ≠ 만. 세었더니 못 읽는 파일이 상태줄에 '읽기 실패' 로 새로 나왔다)
                return False
        with open(pa, 'rb') as fa, open(pb, 'rb') as fb:
            held = False
            nl = 0
            while True:
                x = fa.read(1 << 20)
                y = fb.read(1 << 20)
                if x != y:
                    # 크기가 같은데 다르다: 줄 끝만 다르려면 처음 어긋난 자리가 어느 쪽의 CR 이어야
                    # 한다 (앞은 같으니) - 그 덩어리에 CR 이 없으면 다시 읽지 않는다. 또 크기가 같으면
                    # 'X\r\nY' 와 'X\nY\n' 꼴뿐이다 (줄마다 CRLF 인 쪽의 CRLF 하나 = 맞은편의 끝 줄바꿈 -
                    # eol_sizes 의 크기 셈) - 한쪽의 줄바꿈이 하나여야 한다. CRLF 파일 안에서 고친 글자
                    # (크기 같음)를 처음부터 다시 읽지 않는다
                    if IGNORE_EOL and sa is not None and 0 < sa <= EOL_MAX and \
                            (held or b'\r' in x or b'\r' in y) and \
                            nl + min(x.count(b'\n'), y.count(b'\n')) <= 1:
                        fa.seek(0)
                        fb.seek(0)
                        return eol_same(fa, fb)
                    return False
                if not x:
                    return True
                held = x[-1] == 13
                if nl < 2:
                    nl += x.count(b'\n')   # 둘이 넘으면 더 셀 것 없다 (같은 파일을 끝까지 읽는 길)
    except OSError:
        return None


BATCH = {SCAN: 4, STAT: 64, INFO: 64, CMP: 1}


def worker(role):
    own, other = jobs[role], jobs[1 - role]
    while True:
        with job_cond:
            while not own and not other:
                job_cond.wait()
            # 제 패의 일이 먼저, 없거나 다른 패에 더 급한 것(펼쳐 둔 디렉터리)이 있으면 그것
            if not own or (other and job_tier(other[0]) < job_tier(own[0])):
                h = other
            else:
                h = own
            job = heapq.heappop(h)
            kind = job_kind(job)
            # 남은 일이 많을 때만 여럿을 - 적으면 다른 일꾼도 나눠 하게
            lim = min(BATCH[kind], 1 + len(h) // WORKERS)
            batch = [job[1]]
            while h and len(batch) < lim and job_kind(h[0]) == kind:
                batch.append(heapq.heappop(h)[1])
            bit = 1 << kind
            todo = []
            for n in batch:
                if not n.done & bit:
                    n.done |= bit
                    todo.append(n)
        res = []
        for n in todo:
            rel = n.rel()
            if kind == SCAN:
                la, ea, fa = listdir('a', rel) if n.ka == 'd' else ({}, 0, False)
                lb, eb, fb = listdir('b', rel) if n.kb == 'd' else ({}, 0, False)
                if la and lb:
                    alias(rel, la, lb)
                res.append((n, la, lb, ea + eb, fa, fb))
            elif kind == STAT or kind == INFO:
                ra = lstat('a', rel) if n.ka else None
                rb = lstat('b', rel) if n.kb else None
                same_link = None
                if kind == STAT and n.ka == 'l' and n.kb == 'l':
                    try:
                        same_link = os.readlink(os.path.join(ROOT['a'], rel)) == \
                            os.readlink(os.path.join(ROOT['b'], rel))
                    except OSError:
                        same_link = False
                res.append((n, kind, ra, rb, same_link))
            else:
                r = same_content(rel, n.sa, n.sb)
                dbg('compared', rel, r)
                res.append((n, r))
        ops[kind] += len(todo)
        post(('done', kind, res, len(batch)))


# ---------------------------------------------------------------------------
# 결과를 모형에 넣는다 (여기부터는 한 줄기에서만)
# ---------------------------------------------------------------------------

def sort_key(n):
    return (0 if n.isdir() else 1, n.name.lower(), n.name)


def children(n):
    return sorted(n.kids.values(), key=sort_key) if n.kids else []


def submit_pending(c, force_vis):
    # 판정이 남은 항목의 다음 일. 크기를 이미 알면 내용, 크기를 보는 중이면 기다린다
    if c.both_dirs():
        if not c.scanned:
            submit(SCAN, c, force_vis)
    elif c.sa is not None and c.sb is not None:
        submit(CMP, c, force_vis)
    elif not (c.done & (1 << STAT)):
        submit(STAT, c, force_vis)


def want_info(n):
    # 펼쳐 둔 디렉터리의 항목: 크기·날짜가 있어야 하고, 판정이 남은 것은 먼저 한다
    for c in n.kids.values():
        if c.status == 'pend':
            submit_pending(c, True)
            if c.both_dirs():
                submit(INFO, c, True)   # 날짜
        elif not (c.done & ((1 << STAT) | (1 << INFO))):
            submit(INFO, c, True)


def boost(n, limit=20000):
    # 새로 펼친 디렉터리 아래에서 이미 줄 서 있는 일을 앞으로 당긴다. 같은 일을 한 번 더
    # 넣는다 - 먼저 꺼낸 쪽이 하고 뒤의 것은 건너뛴다 (worker 의 done)
    stack = [c for c in n.kids.values() if c.both_dirs() and c.scanned]
    seen = 0
    while stack and seen < limit:
        d = stack.pop()
        for c in d.kids.values():
            seen += 1
            if c.status != 'pend':
                continue
            if c.both_dirs() and c.scanned:
                stack.append(c)
            else:
                submit_pending(c, False)


def judge(n, c, unsure=False):
    # 훑은 그 자리에서 정할 수 있는 판정 (나머지는 'pend' - 크기·내용을 볼 것)
    if not n.both_dirs():
        return 'onlyA' if n.ka == 'd' else 'onlyB'
    if unsure:
        return 'diff'
    if c.ka is None:
        return 'onlyB'
    if c.kb is None:
        return 'onlyA'
    if c.ka != c.kb:
        return 'diff'
    if c.ka == 'o':
        return 'same'
    return 'pend'


def on_scan(n, la, lb, err, fa=False, fb=False):
    if n.scanned:
        return
    counts['err'] += err
    counts['dirs'] += 1
    n.kids = {}
    pend = bad = 0
    orphan = not n.both_dirs()
    # 못 읽은 쪽이 있으면 빈 디렉터리로 보지 않는다: 읽은 쪽의 것을 'B 에만' 으로 세면
    # 거짓이고, 양쪽 다 못 읽으면 '같음' 이 되었다. 읽은 쪽의 것은 '다름'(견줄 수 없음)으로,
    # 디렉터리는 언제나 '다름' 으로 둔다 (아래 phantom)
    rerr = ('a' if fa else '') + ('b' if fb else '')
    if rerr:
        n.rerr = rerr
    unsure = bool(rerr) and not orphan
    todo = []
    agg = None if orphan else [0] * 8
    for name in set(la) | set(lb):
        c = Node(name, n)
        c.ka = la.get(name)
        c.kb = lb.get(name)
        st = judge(n, c, unsure)
        c.status = st
        count(c, st, 1)
        if c.both_dirs():
            c.mask = UNK
        else:
            c.mask = item_mask(c)
            if agg is not None:
                tally(c.mask, 1)
        if agg is not None:
            agg_move(agg, 0, c.mask)
        n.kids[name] = c
        if st == 'pend':
            pend += 1
            if not n.sub:
                todo.append(c)
        elif st in BAD:
            bad += 1
    if unsure:
        bad += 1    # 어느 항목에도 딸리지 않은 '다름' - 이 디렉터리는 '같음' 이 될 수 없다
    if n.parent is None:
        for i, c in enumerate(children(n)):
            c.group = i
    for c in todo:
        submit(SCAN if c.ka == 'd' else STAT, c)
    n.pend = pend
    n.bad = bad
    n.scanned = True
    n.agg = agg
    if remask(n):
        notify_parent(n)   # UNK 에서 아래의 것으로 (판정이 그대로여도)
    if n.sub:
        want_info(n)
    if n.both_dirs():
        set_status(n, dir_status(n))
    if rerr:
        notify_parent(n)   # 못 읽은 쪽을 알린다 (판정이 그대로여도)
    if n.waiters:
        rel = n.rel()
        for rid in n.waiters:
            emit({'ev': 'list', 'id': rid, 'dir': rel, 'entries': [entry(c) for c in children(n)]}, now=True)
        n.waiters = None


def on_stat(n, kind, ra, rb, same_link):
    if ra:
        n.sa, n.ma = ra
    if rb:
        n.sb, n.mb = rb
    if kind == INFO or n.status != 'pend':
        if not n.both_dirs():
            remask(n)   # 날짜가 생기면 '최신' 쪽이 정해진다
        notify_parent(n)
        return
    if n.ka == 'l':
        set_status(n, 'same' if same_link else 'diff')
        return
    if ra is None or rb is None:
        counts['err'] += 1
        set_status(n, 'diff')
        return
    if n.sa != n.sb:
        if eol_maybe(n.sa, n.sb):
            notify_parent(n)   # 크기·날짜가 생겼다 - 줄 끝만 다른지는 내용 읽기 패가 본다
            submit(CMP, n)
        else:
            set_status(n, 'diff')
    elif n.sa == 0 or (TRUST_MTIME and n.ma == n.mb):
        set_status(n, 'same')
    else:
        notify_parent(n)   # 크기·날짜가 생겼다
        submit(CMP, n)


def on_cmp(n, r):
    if n.status == 'pend':
        if r is None:
            counts['err'] += 1
        elif r is not True and r:
            # 줄 끝만 다르다: 표시를 먼저 달아야 set_status 가 알리는 항목에 실린다
            n.eol = r
            count(n, 'eol', 1)
        set_status(n, 'same' if r else 'diff')


def find(rel):
    n = root
    if rel:
        for part in rel.split('/'):
            n = n.kids.get(part) if n.kids else None
            if n is None:
                return None
    return n


def listing(n, rid=None, lift=False):
    # 훑은 디렉터리면 곧바로, 아니면 훑기를 앞세우고 끝나면 돌려준다
    # lift: 사용자가 연 디렉터리 - 그 아래 일도 앞으로 (boost)
    fresh = not n.sub
    n.sub = True
    if n.scanned:
        want_info(n)
        if lift and fresh and n.parent is not None:
            boost(n)
        return [entry(c) for c in children(n)]
    if rid is not None:
        n.waiters = (n.waiters or []) + [rid]
    submit(SCAN, n, True)
    return None


def path_key(rel, guess=False):
    # guess: 모형에 없는 경로(지운 파일 - R 로 다시 훑었다)면 있었다면 섰을 자리로 (sort_key 와 같은 꼴, 끝은
    # 파일·가운데는 디렉터리로 친다). 비교 창의 '다음 차이 파일' 이 그런 짝에서 물으면 맨 앞 것을 돌려주었다
    n = root
    parts = []
    names = rel.split('/') if rel else []
    for i, name in enumerate(names):
        c = n.kids.get(name) if n.kids else None
        if c is None:
            if not guess:
                return None
            for j in range(i, len(names)):
                parts.append((1 if j == len(names) - 1 else 0, names[j].lower(), names[j]))
            return parts
        parts.append(sort_key(c))
        n = c
    return parts


def items_in_order(n, prefix, bits=None):
    # bits: 보기의 비트 - 그 비트에 걸리는 항목만, 그런 것이 아래에 있는 디렉터리로만 내려간다
    for c in children(n):
        k = prefix + [sort_key(c)]
        if bits is None:
            if is_item(c):
                yield k, c
            elif c.both_dirs() and c.status == 'diff':
                for x in items_in_order(c, k):
                    yield x
        elif c.both_dirs() and not (c.rerr and bits & DX):
            if c.mask & bits and c.kids:
                for x in items_in_order(c, k, bits):
                    yield x
        elif c.mask & bits:
            yield k, c


def cmd_next(msg):
    fk = path_key(msg.get('from') or '', guess=True)
    step = msg.get('step', 1)
    bits = msg.get('bits')
    best = None
    for k, c in items_in_order(root, [], bits if isinstance(bits, int) and bits else None):
        if step > 0:
            if k > fk:
                best = c
                break
        else:
            if k < fk:
                best = c
            else:
                break
    res = {'ev': 'reveal', 'id': msg.get('id'), 'path': None, 'lists': {}}
    if best is not None:
        res['path'] = best.rel()
        p = best.parent
        while p is not None:
            # 이미 목록을 받아 간 디렉터리는 'u' 로 따라가고 있으니 다시 보내지 않는다
            had = p.sub
            lst = listing(p, lift=p is best.parent)
            if not had:
                res['lists'][p.rel()] = lst or []
            p = p.parent
    emit(res, now=True)


def cmd_expand(msg):
    n = find(msg.get('dir') or '')
    bits = msg.get('bits')
    if not (isinstance(bits, int) and bits):
        bits = None
    lists = {}
    stack = [n] if n is not None and n.isdir() and n.scanned else []
    while stack and len(lists) < 2000:
        d = stack.pop()
        lists[d.rel()] = listing(d, lift=d is n) or []
        for c in reversed(children(d)):
            if c.both_dirs() and c.scanned and (c.bad > 0 if bits is None else c.mask & bits):
                stack.append(c)
    emit({'ev': 'lists', 'id': msg.get('id'), 'lists': lists}, now=True)


finished = [None]
last_snap = [None]
complete = [False]
again = [False]           # 끝난 뒤에 refresh 로 새 일이 생겼다


def progress(done):
    # 끝난 뒤에는 끝난 때의 시각을 둔다 (계속 늘어나는 '경과 시간' 이 아니라)
    if done and finished[0] is None:
        finished[0] = round(time.monotonic() - started, 2)
    with job_lock:
        waiting = len(jobs[0]) + len(jobs[1])
    snap = (done, counts['dirs'], counts['pend'], counts['diff'], counts['onlyA'],
            counts['onlyB'], counts['same'], counts['err'], counts['eol'], masks_ver[0])
    if done and snap == last_snap[0]:
        return
    last_snap[0] = snap
    emit({'ev': 'progress', 'done': done, 'dirs': counts['dirs'], 'queued': waiting,
          'files': counts['pend'] + counts['diff'] + counts['onlyA'] + counts['onlyB'] + counts['same'],
          'pend': counts['pend'], 'diff': counts['diff'], 'onlyA': counts['onlyA'],
          'onlyB': counts['onlyB'], 'same': counts['same'], 'err': counts['err'], 'eol': counts['eol'],
          'ops': list(ops), 'backlog': len(inbox), 'again': again[0] and not done,
          'cats': {str(k): v for k, v in masks.items() if v > 0},
          'sec': finished[0] if done else round(time.monotonic() - started, 1)})


def kind_of(side, rel):
    try:
        st = os.lstat(os.path.join(ROOT[side], rel))
    except OSError:
        return None
    if stat.S_ISLNK(st.st_mode):
        return 'l'
    if stat.S_ISDIR(st.st_mode):
        return 'd'
    if stat.S_ISREG(st.st_mode):
        return 'f'
    return 'o'


def detach(n):
    # n 과 그 아래를 모형에서 뗀다: 세던 것을 빼고, 줄에 남은 일과 늦게 온 결과는 버려진다
    p = n.parent
    stack = [n]
    while stack:
        x = stack.pop()
        count(x, x.status, -1)
        if x.eol:
            count(x, 'eol', -1)
        if not x.both_dirs() and x.parent.agg is not None:
            tally(x.mask, -1)
        if x.scanned:
            counts['dirs'] -= 1
        x.dead = True
        if x.kids:
            stack.extend(x.kids.values())
    del p.kids[n.name]
    if n.status == 'pend':
        p.pend -= 1
    elif n.status in BAD:
        p.bad -= 1
    mask_up(p, n.mask, 0)


def spelled(p, parent_rel, name):
    # 트리에 다른 철자(alias)로 있는 같은 파일의 이름. nvim 이 macOS 에서 버퍼 이름의 대소문자를
    # 디스크의 것으로 고쳐(foo.c) :w 의 refresh 가 그 이름으로 오면, 트리의 Foo.c 옆에 같은
    # 파일의 줄이 하나 더 생겼다
    key = unicodedata.normalize('NFC', name).casefold()
    for k in p.kids:
        if k != name and unicodedata.normalize('NFC', k).casefold() == key:
            for side in ('a', 'b'):
                base = os.path.join(ROOT[side], parent_rel) if parent_rel else ROOT[side]
                try:
                    if os.path.samestat(os.lstat(os.path.join(base, k)), os.lstat(os.path.join(base, name))):
                        return k
                except OSError:
                    pass
    return None


def refresh_one(rel):
    # 그 항목을 새로 만든다 (복사로 한쪽이 생겼거나 바뀌었다). 부모를 돌려준다
    if not rel:
        return None
    parent_rel, _, name = rel.rpartition('/')
    p = find(parent_rel)
    if p is None or not p.scanned or p.dead or excluded(name):
        return None
    old = p.kids.get(name)
    if old is None:
        k = spelled(p, parent_rel, name)
        if k is not None:
            name, rel = k, (parent_rel + '/' + k if parent_rel else k)
            old = p.kids[k]
    group = old.group if old is not None else p.group
    if old is not None:
        detach(old)
    ka = kind_of('a', rel) if p.ka == 'd' else None
    kb = kind_of('b', rel) if p.kb == 'd' else None
    if ka is None and kb is None:
        if p.both_dirs():
            set_status(p, dir_status(p))
        return p
    c = Node(name, p)
    c.group = group
    c.ka, c.kb = ka, kb
    st = judge(p, c, bool(p.rerr) and p.both_dirs())
    c.status = st
    count(c, st, 1)
    c.mask = UNK if c.both_dirs() else item_mask(c)
    p.kids[name] = c
    if p.agg is not None:
        if not c.both_dirs():
            tally(c.mask, 1)
        mask_up(p, 0, c.mask)
    if st == 'pend':
        p.pend += 1
        submit_pending(c, p.sub)
    elif st in BAD:
        p.bad += 1
    if p.sub:
        submit(INFO, c, True)   # 크기·날짜
    if p.both_dirs():
        set_status(p, dir_status(p))
    return p


def cmd_refresh(msg):
    paths = sorted(set(x for x in (msg.get('paths') or []) if isinstance(x, str)), key=len)
    done_paths = []
    parents = {}
    for rel in paths:
        # 이미 다시 만든 것의 아래는 건너뛴다 (그 디렉터리를 통째로 새로 훑는다)
        if any(rel == d or rel.startswith(d + '/') for d in done_paths):
            continue
        p = refresh_one(rel)
        done_paths.append(rel)
        if p is not None and p.sub:
            parents[p.rel()] = p
    if done_paths and complete[0]:
        # 끝난 뒤의 refresh 는 새 판정거리다 - 다 볼 때까지 '끝' 이 아니다 (끝난 시각은 처음 것)
        complete[0] = False
        again[0] = True
    for rel, p in parents.items():
        emit({'ev': 'list', 'id': None, 'dir': rel, 'entries': [entry(c) for c in children(p)]}, now=True)


# ---------------------------------------------------------------------------
# 복사 (nvim 트리의 <C-r>/<C-l>). 따로 된 줄기에서 하나씩 - 그동안에도 훑기는 돈다
#
# 대상 쪽을 망가뜨리지 않는 것이 먼저다 (처음에는 cp -R 로 했다가 검토에서 모두 걸렸다):
#   * 대상 경로의 위 디렉터리가 하나라도 진짜 디렉터리가 아니면(링크 등) 하지 않는다 -
#     링크를 따라가 트리 밖의 파일을 덮어썼다
#   * 파일은 같은 디렉터리의 임시 이름에 다 쓴 뒤 os.replace 로 바꿔 끼운다: 실패하면
#     대상이 그대로 남고(먼저 지웠더니 실패할 때 대상이 사라졌다), 대상이 링크여도 그
#     링크를 바꿀 뿐 따라가 쓰지 않는다
#   * 디렉터리는 합친다 - 항목마다 같은 규칙으로. 대상에만 있는 것은 두고, 제외 목록
#     (.git, GTAGS, *.o ...)은 원본에서도 대상에서도 건드리지 않는다 (cp -R 은 .git 의
#     HEAD·index 까지 덮었다). 특수 파일(FIFO 등)은 건너뛴다 (cp 가 멈춰 섰다)
# ---------------------------------------------------------------------------

copy_q = collections.deque()
copy_cv = threading.Condition()
copier_started = [False]
copy_tmp = [None]         # 복사 줄기가 지금 쓰고 있는 임시 파일
copy_mx = threading.RLock()   # 임시 파일 만들기·바꿔 끼우기 <-> bail (RLock: bail 안에서 SIGTERM 이 또 와도)
stopping = [False]


def bail(code):
    # 끝낸다 - 복사 줄기가 쓰던 임시 파일은 지우고. os._exit 는 그 줄기를 그 자리에서 없애
    # copy_file 의 뒷정리가 돌지 않았다: :tabclose·:qa (quit + jobstop 의 SIGTERM) 로 끝내면
    # 반쯤 쓴 '.dirdiff~PID~이름' 이 대상 쪽에 남았고, 다음 비교에 'B 에만' 으로 보였다
    with copy_mx:
        stopping[0] = True
        t = copy_tmp[0]
    if t:
        try:
            os.unlink(t)
        except OSError:
            pass
    os._exit(code)


def why(e):
    return getattr(e, 'strerror', None) or str(e)


def copy_file(src, dst, sst):
    d, base = os.path.split(dst)
    tmp = os.path.join(d, '.dirdiff~%d~%s' % (os.getpid(), base[:80]))
    try:
        os.unlink(tmp)
    except OSError:
        pass
    try:
        # 임시 파일을 만들고 바꿔 끼우는 것은 copy_mx 안에서: bail 이 그 사이에 끼면 지울
        # 이름을 모르거나, 지운 뒤에 새로 생긴다
        with copy_mx:
            if stopping[0]:
                raise OSError('stopped')
            copy_tmp[0] = tmp
            if stat.S_ISLNK(sst.st_mode):
                os.symlink(os.readlink(src), tmp)
                fd = None
            else:
                fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        if fd is not None:
            with os.fdopen(fd, 'wb') as out, open(src, 'rb') as inp:
                shutil.copyfileobj(inp, out, 1 << 20)
            shutil.copystat(src, tmp)
        with copy_mx:
            if stopping[0]:
                raise OSError('stopped')
            os.replace(tmp, dst)
            copy_tmp[0] = None
    except BaseException:
        copy_tmp[0] = None
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def copy_entry(src, dst, rel, rep):
    try:
        sst = os.lstat(src)
    except OSError:
        rep['skipped'].append([rel, 'source missing'])
        return
    try:
        dstt = os.lstat(dst)
    except FileNotFoundError:
        dstt = None
    except OSError as e:
        rep['failed'].append([rel, why(e)])
        return
    if stat.S_ISDIR(sst.st_mode):
        if dstt is not None and not stat.S_ISDIR(dstt.st_mode):
            rep['skipped'].append([rel, 'kind'])
            return
        try:
            if dstt is None:
                os.mkdir(dst, 0o700)
            names = sorted(os.listdir(src))
        except OSError as e:
            rep['failed'].append([rel, why(e)])
            return
        for name in names:
            if not excluded(name):
                copy_entry(os.path.join(src, name), os.path.join(dst, name), rel + '/' + name, rep)
        try:
            shutil.copystat(src, dst)
        except OSError:
            pass
        rep['dirs'] += 1
    elif stat.S_ISREG(sst.st_mode) or stat.S_ISLNK(sst.st_mode):
        if dstt is not None and stat.S_ISDIR(dstt.st_mode):
            rep['skipped'].append([rel, 'kind'])
            return
        try:
            copy_file(src, dst, sst)
            rep['files'] += 1
        except OSError as e:
            rep['failed'].append([rel, why(e)])
    else:
        rep['skipped'].append([rel, 'special'])


def copy_one(frm, to, rel, rep):
    # 돌려주는 것: 다시 볼 곳 (새로 만든 맨 위 디렉터리, 아니면 rel). 하지 않았으면 None
    parts = rel.split('/')
    if not rel or any(p in ('', '.', '..') for p in parts):
        rep['skipped'].append([rel, 'bad path'])
        return None
    cur = ROOT[to]
    made = []
    for i, part in enumerate(parts[:-1]):
        cur = os.path.join(cur, part)
        try:
            st = os.lstat(cur)
        except FileNotFoundError:
            try:
                os.mkdir(cur, 0o700)
            except OSError as e:
                rep['failed'].append([rel, why(e)])
                return '/'.join(parts[:made[0] + 1]) if made else None
            made.append(i)
            continue
        except OSError as e:
            rep['failed'].append([rel, why(e)])
            return None
        if not stat.S_ISDIR(st.st_mode):
            rep['skipped'].append([rel, 'parent:' + '/'.join(parts[:i + 1])])
            return None
    copy_entry(os.path.join(ROOT[frm], rel), os.path.join(ROOT[to], rel), rel, rep)
    for i in reversed(made):
        try:
            shutil.copystat(os.path.join(ROOT[frm], *parts[:i + 1]), os.path.join(ROOT[to], *parts[:i + 1]))
        except OSError:
            pass
    return '/'.join(parts[:made[0] + 1]) if made else rel


def copier():
    while True:
        with copy_cv:
            while not copy_q:
                copy_cv.wait()
            msg = copy_q.popleft()
        frm = 'b' if msg.get('from') == 'b' else 'a'
        to = 'a' if frm == 'b' else 'b'
        rep = {'files': 0, 'dirs': 0, 'skipped': [], 'failed': [], 'roots': []}
        done_rels = []
        for rel in sorted(set(x for x in (msg.get('paths') or []) if isinstance(x, str))):
            if any(rel.startswith(d + '/') for d in done_rels):
                continue   # 고른 디렉터리 안의 것 - 이미 했다
            done_rels.append(rel)
            try:
                r = copy_one(frm, to, rel, rep)
            except Exception as e:   # 모르는 실패도 알린다 (복사 줄기가 죽지 않게)
                rep['failed'].append([rel, why(e)])
                r = rel
            if r:
                rep['roots'].append(r)
        post(('copied', msg.get('id'), rep))


def cmd_copy(msg):
    with copy_cv:
        copy_q.append(msg)
        copy_cv.notify()
    if not copier_started[0]:
        copier_started[0] = True
        threading.Thread(target=copier, daemon=True).start()


def on_copied(rid, rep):
    ev = {'ev': 'copied', 'id': rid}
    ev.update(rep)
    emit(ev, now=True)
    cmd_refresh({'paths': rep['roots']})


def handle(msg):
    c = msg.get('cmd')
    if c == 'list':
        rel = msg.get('dir') or ''
        n = find(rel)
        if n is None or not n.isdir():
            emit({'ev': 'list', 'id': msg.get('id'), 'dir': rel, 'entries': []}, now=True)
            return
        entries = listing(n, msg.get('id'), lift=True)
        if entries is not None:
            emit({'ev': 'list', 'id': msg.get('id'), 'dir': rel, 'entries': entries}, now=True)
    elif c == 'unlist':
        n = find(msg.get('dir') or '')
        if n is not None:
            n.sub = False
    elif c == 'next':
        cmd_next(msg)
    elif c == 'expand':
        cmd_expand(msg)
    elif c == 'refresh':
        cmd_refresh(msg)
    elif c == 'copy':
        cmd_copy(msg)
    elif c == 'quit':
        flush()
        bail(0)


def reader():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            post(('cmd', json.loads(line)))
        except ValueError:
            pass
    post(('cmd', {'cmd': 'quit'}))


def main():
    # -X utf8 없이 불려도(3.6 은 -X utf8 을 모른다) UTF-8 이 아닌 이름에서 죽지 않게
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='surrogateescape')
        sys.stdin.reconfigure(encoding='utf-8', errors='surrogateescape')
    except (AttributeError, ValueError):
        sys.stdout = io.TextIOWrapper(sys.stdout.detach(), encoding='utf-8', errors='surrogateescape')
        sys.stdin = io.TextIOWrapper(sys.stdin.detach(), encoding='utf-8', errors='surrogateescape')
    # 순환 쓰레기 수거를 끈다. 모형은 끝날 때까지 버리지 않으므로 거둘 것이 없는데, 켜 두면
    # 항목이 수십만이 되면서 전체 수거가 거듭 모형 전체를 훑는다 (몇 초씩 멎고 CPU 를 먹는다)
    gc.disable()
    # nvim 의 jobstop 은 SIGTERM 이다 - 그냥 죽으면 쓰던 임시 파일이 남는다 (bail). 주 줄기는
    # wake.wait 에서 자고 있어도 시그널 처리기는 곧바로 돈다. 끝 코드는 시그널로 죽은 것과 같게
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda n, _f: bail(128 + n))
    for side in ('a', 'b'):
        if not os.path.isdir(ROOT[side]):
            emit({'ev': 'error', 'msg': 'not a directory: ' + ROOT[side]}, now=True)
            os._exit(1)
    threading.Thread(target=reader, daemon=True).start()
    readers = max(1, WORKERS * 3 // 8) if WORKERS > 1 else 0   # 내용 읽기 패 (16 이면 6)
    for i in range(WORKERS):
        threading.Thread(target=worker, args=(1 if i < readers else 0,), daemon=True).start()
    root.sub = True
    submit(SCAN, root, True)
    last_prog = 0.0
    announced = False
    apply = {SCAN: on_scan, STAT: on_stat, INFO: on_stat, CMP: on_cmp}
    while True:
        push_staged()
        if not inbox:
            if announced:
                # 자기 전에 마지막 상황을 낸다 (끝난 뒤의 refresh 로 수가 바뀌었을 수 있다 -
                # 같은 수면 progress 가 내지 않는다)
                progress(True)
                flush()
            # 다 끝났으면 다음 명령까지 잔다 (post 가 깨운다)
            main_idle[0] = True
            wake.clear()
            if not inbox:
                wake.wait(None if announced else 0.1)
            main_idle[0] = False
        handled = 0
        while inbox and handled < 5000:
            item = inbox.popleft()
            if item[0] == 'cmd':
                dbg('cmd', item[1].get('cmd'), item[1].get('dir'))
                handle(item[1])
                handled += 1
            elif item[0] == 'copied':
                on_copied(item[1], item[2])
                handled += 1
            else:
                _, kind, res, taken = item
                outstanding[0] -= taken
                fn = apply[kind]
                for r in res:
                    if not r[0].dead:
                        fn(*r)
                handled += len(res) + 1
            if len(staged) >= 256:
                push_staged()
        push_staged()
        now = time.monotonic()
        # 한 번 끝나면 끝이다 - 그 뒤의 일(펼친 디렉터리의 날짜, 한쪽에만 있는 디렉터리
        # 훑기)은 보여 주기용이라 판정이 바뀌지 않는다. 처음에는 그 일이 생길 때마다 '끝' 을
        # 풀었다가 다시 매겨 끝난 시각이 3.5초에서 12.8초로 바뀌었다 (실측)
        if not complete[0] and outstanding[0] == 0 and counts['pend'] == 0 and root.scanned:
            complete[0] = True
            again[0] = False
        done = complete[0]
        if now - last_prog > 0.25 or (done and not announced):
            dbg('progress', done, counts['pend'], outstanding[0])
            progress(done)
            last_prog = now
        announced = done
        if now - last_flush[0] > 0.05 or done:
            flush()


if __name__ == '__main__':
    main()
