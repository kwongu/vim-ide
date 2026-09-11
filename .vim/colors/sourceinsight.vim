" sourceinsight.vim - Source Insight 기본 테마 배색
"
"   순백 배경 + 검정 본문 + 진한 네이비 볼드 키워드 + 초록 이탤릭 주석
"   + 마룬(적갈색) 문자열. 색을 아주 적게 쓰는 것이 SI 화면의 특징이다.
"
" 배색이 두 가지 있다 (g:sourceinsight_palette):
"
"   'screen'  (기본) 사용자가 실제로 쓰는 SI 화면 그대로:
"             초록 주석, 마룬 문자열(연노랑 배경), 네이비 볼드 키워드,
"             검정 타입, 모든 선언에 밑줄. VC6/Visual Studio 계열 배색을
"             SI 에 올린 스타일셋이다.
"   'factory' SI 4.0 이 출고될 때의 기본 스타일셋. 잉크가 일곱 색뿐이다:
"             #000000 #000080 #008000 #008080 #800080 #ff0000 #808080
"             - 평범한 키워드(int/char/static/struct)는 초록 #008000
"             - 제어 키워드(if/for/return/goto)와 전처리기는 네이비 볼드
"             - 주석은 보라 #800080, 숫자와 NULL 은 빨강 #ff0000
"             - 문자열은 네이비 글자 + 연노랑 배경
"             - 선언은 네이비 볼드, 밑줄은 '파라미터와 레이블만'
"             - 심볼 참조는 초록, 지역변수 참조는 청록 #008080
"             (themes.xml/스톡 설치본에서 확인한 값이다)
"
"   let g:sourceinsight_palette = 'factory'   " ~/.vimrc 에서
"
" 색을 바꾸고 싶으면 아래 s:c 표만 고치면 된다. Treesitter(@...) 그룹까지
" 같이 묶어 두었으므로 nvim-treesitter 를 켠 C/C++ 에서도 같은 배색이 난다.
"
" 어두운 화면은 이 파일이 담당하지 않는다: ~/.vimrc 의 g:vimide_theme 로
" 'dark'(jellybeans) / 'light'(PaperColor) / 'si'(이 테마) 를 고른다.

hi clear
if exists('syntax_on')
  syntax reset
endif
let g:colors_name = 'sourceinsight'
set background=light

let s:c = {
      \ 'bg':        ['#ffffff', 231, 'white'],
      \ 'fg':        ['#000000', 16,  'black'],
      \ 'keyword':   ['#000080', 18,  'darkblue'],
      \ 'type':      ['#0000a8', 19,  'darkblue'],
      \ 'comment':   ['#008000', 28,  'darkgreen'],
      \ 'string':    ['#800000', 88,  'darkred'],
      \ 'stringbg':  ['#ffffbb', 230, 'yellow'],
      \ 'declbg':    ['#e8e8e8', 254, 'lightgrey'],
      \ 'selbg':     ['#000080', 18,  'darkblue'],
      \ 'number':    ['#800000', 88,  'darkred'],
      \ 'preproc':   ['#000080', 18,  'darkblue'],
      \ 'macro':     ['#7f007f', 90,  'darkmagenta'],
      \ 'sel':       ['#cfe2f3', 153, 'lightblue'],
      \ 'cursorline':['#eff3f7', 254, 'lightgrey'],
      \ 'linenr':    ['#808080', 244, 'grey'],
      \ 'linenrbg':  ['#f2f2f2', 255, 'white'],
      \ 'ui':        ['#d9d9d9', 252, 'lightgrey'],
      \ 'uifg':      ['#333333', 236, 'black'],
      \ 'err':       ['#cc0000', 160, 'red'],
      \ 'warn':      ['#b35c00', 130, 'darkyellow'],
      \ 'match':     ['#ffe08a', 222, 'yellow'],
      \ 'diffadd':   ['#ddf5dd', 194, 'lightgreen'],
      \ 'diffdel':   ['#ffe0e0', 224, 'lightred'],
      \ 'diffchg':   ['#e6eeff', 189, 'lightblue'],
      \ }

" SI 는 함수/구조체/enum 의 '선언된 이름'을 본문보다 크게(Scale 140%) 그리고
" 옅은 그림자(#c0c0c0)까지 넣어 그린다. Neovim 은 하이라이트 단위 글자 크기를
" 지원하지 않으므로(nvim_set_hl 은 scale/font 키를 거부한다) 크기 대신 굵기·
" 밑줄·옅은 배경으로 같은 '눈에 먼저 들어오는' 효과를 낸다.
"
"   g:sourceinsight_declaration_emphasis
"     'bold'   (기본) 네이비 볼드
"     'strong'        네이비 볼드 + 밑줄 + 옅은 회색 배경 (SI 의 큰 글자 +
"                     그림자에 가장 가까운 효과)
"     'off'           특별한 강조 없음
"
" 기본값에서 밑줄을 뺐다. 네이비 볼드만으로 이미 충분히 먼저 눈에 들어오고,
" 함수 정의가 몰려 있는 화면에서는 밑줄이 줄마다 그어져 오히려 시끄러웠다.
" 밑줄이 필요하면 'strong' 을 쓰면 된다 - 파라미터는 여전히 밑줄을 단다.
let s:variant = get(g:, 'sourceinsight_palette', 'screen')
let s:emph = get(g:, 'sourceinsight_declaration_emphasis', 'bold')
if s:variant ==# 'factory'
  " SI 4.0 출고 기본 스타일셋 (themes.xml / 스톡 설치본)
  let s:c.keyword  = ['#008000', 28,  'darkgreen']   " int, char, static, struct
  let s:c.control  = ['#000080', 18,  'darkblue']    " if, for, return, goto
  let s:c.type     = ['#008000', 28,  'darkgreen']
  let s:c.comment  = ['#800080', 90,  'darkmagenta']
  let s:c.string   = ['#000080', 18,  'darkblue']
  let s:c.number   = ['#ff0000', 196, 'red']
  let s:c.preproc  = ['#000080', 18,  'darkblue']
  let s:c.macro    = ['#000080', 18,  'darkblue']
  let s:c.decl     = ['#000080', 18,  'darkblue']
  let s:c.ref      = ['#008000', 28,  'darkgreen']
  let s:c.reflocal = ['#008080', 30,  'darkcyan']
  let s:c.delim    = ['#800080', 90,  'darkmagenta']
  let s:c.label    = ['#ff0000', 196, 'red']
else
  " 화면 기준 배색 (실제 SI 화면 판독):
  "   struct/int/static 등 예약어      네이비 볼드
  "   타입 이름 전부                    초록 볼드 (int/void/char, uint32_t,
  "                                    size_t, bool, struct·enum·typedef 이름)
  "                                    단, 정의하는 자리는 짙은 파랑 볼드
  "   함수 정의 이름                    네이비 볼드
  "   함수 호출(심볼 참조)              짙은 초록 (볼드)
  "   상수형 매크로/NULL/숫자           빨강
  "   함수형 매크로, #ifdef 조건         네이비 볼드
  "   주석 보라 #800080, 문자열 마룬 + 연노랑
  "   #include / #define 은 초록, #if/#ifdef/#endif 는 네이비 볼드
  "   #ifdef/#ifndef 의 조건 이름은 옅은 빨강 (상수 매크로와 같은 색)
  "   enum 요소는 네이비 볼드, '=' 같은 연산자는 초록, 값은 옅은 빨강
  let s:c.control  = s:c.keyword
  " 타입 이름은 모두 초록: 내장 타입(int/void/char)도, uint32_t/size_t/bool
  " 도, 프로젝트의 struct/enum/typedef 이름도. 정의하는 자리만 아래
  " @si.declaration.function 이 짙은 파랑으로 덮는다.
  " 타입 앞에 붙는 수식자도 모두 초록: 저장 클래스(static/extern/inline/
  " register)와 한정자(const/volatile/restrict) 둘 다.
  let s:c.type     = ['#008000', 28,  'darkgreen']
  let s:c.typeref  = ['#008000', 28,  'darkgreen']
  let s:c.decl     = s:c.keyword
  let s:c.ref      = ['#008000', 28,  'darkgreen']
  let s:c.reflocal = s:c.fg
  let s:c.delim    = s:c.fg
  " goto 레이블은 빨강 (SI 도 레이블만 빨강 볼드 밑줄로 그린다)
  let s:c.label    = ['#ff0000', 196, 'red']
  let s:c.comment  = ['#800080', 90,  'darkmagenta']
  " 상수 매크로/숫자/NULL, #ifdef 조건 이름, enum 값: 빨강.
  "
  " 한동안 옅은 빨강(#ff5f5f, 흰 배경 대비 3.0:1)을 썼다. 획이 얇아 보이라고
  " 고른 값인데, 실제로는 본문보다 약하게 떠서 '빨강으로 표시된 것'이라는
  " 신호가 죽었다. Source Insight 도 이 자리를 새빨강으로 그린다(이 파일
  " 맨 위 색상표의 '숫자와 NULL 은 빨강 #ff0000'). 다시 덜 세게 하고 싶으면
  " #e06666(3.4:1), #cc5555(4.2:1), #ff5f5f(3.0:1) 순으로 내리면 된다.
  let s:c.number   = ['#ff0000', 196, 'red']
  let s:c.macro    = s:c.keyword
  " #include / #define 은 초록 (#if/#ifdef/#endif 는 네이비 볼드로 둔다)
  let s:c.incdef   = ['#008000', 28,  'darkgreen']
  " 파라미터 / 함수 안 지역변수 선언: 남색 (예약어와 같은 파랑 계열)
  let s:c.decllocal = ['#000080', 18,  'darkblue']
endif
if !has_key(s:c, 'incdef')
  let s:c.incdef = s:c.preproc
endif
if !has_key(s:c, 'decllocal')
  let s:c.decllocal = s:c.decl
endif
" 같은 함수 안에서 선언을 찾을 수 있는 지역 변수의 '쓰는 자리'
" (sihllocal.lua) = 청록 #008080.
"
" 이 값은 고른 것이 아니라 원래 있던 것이다. SI 출고 팔레트의 일곱 색 중
" 하나이고, 이 파일이 factory 변종에서 이미 s:c.reflocal - '지역 심볼 참조'
" - 로 쓰고 있다(위 s:c.reflocal). 처음에는 짙은 연두 #6b8e23 을 썼는데,
" 화면 기준 배색에서 지역 참조가 어떤 색이어야 하는지는 SI 자신이 이미
" 답해 두고 있었다. 초록 #008000(심볼 참조)과도, 네이비 #000080(선언)과도
" 섞이지 않는다.
"
"   let g:sourceinsight_local_color = '#6b8e23'   " 예전 짙은 연두
"   let g:sourceinsight_local_color = '#7cb342'   " 밝은 연두
if !has_key(s:c, 'jumplocal')
  let s:c.jumplocal = ['#008080', 30,  'darkcyan']
endif
" 전역 변수를 함수 안에서 쓰는 자리 (sihllocal.lua) = 보라 이탤릭.
"
" 보라 #800080 은 SI 팔레트의 색이고 주석이 쓰는 색이기도 한데, 주석은
" 식별자가 아니라 한 줄 통째로 보라라서 섞이지 않는다. 이탤릭이 한 번 더
" 갈라 준다 - '이건 이 함수 밖의 상태다'를 기울기로 읽는다.
"   let g:sourceinsight_global_color = '#6a1b9a'
if !has_key(s:c, 'globalref')
  let s:c.globalref = ['#800080', 90,  'darkmagenta']
endif
if exists('g:sourceinsight_global_color')
  let s:c.globalref = [g:sourceinsight_global_color,
        \ get(g:, 'sourceinsight_global_cterm', 90), 'darkmagenta']
endif
if exists('g:sourceinsight_local_color')
  let s:c.jumplocal = [g:sourceinsight_local_color,
        \ get(g:, 'sourceinsight_local_cterm', 30), 'darkcyan']
endif
if !has_key(s:c, 'typeref')
  let s:c.typeref = s:c.ref
endif

" 평범한 키워드의 볼드 여부는 배색마다 다르다: 화면 기준은 볼드,
" SI 출고 기본값은 Keyword 에 볼드가 없다(제어 키워드에만 있다).
let s:kw = s:variant ==# 'factory' ? '' : 'bold'
" 초록 계열(타입 이름, 타입 참조, 저장 클래스/한정자)은 굵게 하지 않는다.
"
" 굵기는 '함수 호출'의 표시로만 남긴다. 초록이 전부 굵으면 그 신호가 묻혀서,
" 화면에서 struct 이름과 함수 호출이 같은 무게로 읽혔다. 예약어(네이비)는
" s:kw 그대로 굵게 둔다 - 색이 달라 섞이지 않는다.
let s:tp = ''

function! s:hi(group, fg, bg, attr) abort
  let l:cmd = 'highlight ' . a:group
  if a:fg !=# ''
    let l:cmd .= ' guifg=' . s:c[a:fg][0] . ' ctermfg=' . s:c[a:fg][1]
  endif
  if a:bg !=# ''
    let l:cmd .= ' guibg=' . s:c[a:bg][0] . ' ctermbg=' . s:c[a:bg][1]
  endif
  let l:cmd .= ' gui=' . (a:attr ==# '' ? 'NONE' : a:attr)
  " cterm 에도 italic 을 그대로 넘긴다.
  "
  " 예전에는 여기서 italic 을 지웠다. 이탤릭을 쓰는 그룹이 하나도 없을 때
  " 넣어 둔 예방책이었는데, 전역 변수 참조(SiGlobalRef)가 생기면서 그것이
  " 바로 문제가 됐다: termguicolors 가 꺼진 터미널 세션에서는 cterm 쪽만
  " 쓰이므로 이탤릭이 아예 나오지 않았다.
  "
  " 이탤릭을 반전(reverse)으로 그리는 터미널이 있으면:
  "   let g:sourceinsight_no_cterm_italic = 1
  let l:cattr = a:attr ==# '' ? 'NONE' : a:attr
  if get(g:, 'sourceinsight_no_cterm_italic', 0)
    let l:cattr = substitute(l:cattr, 'italic', 'NONE', 'g')
    let l:cattr = l:cattr ==# '' ? 'NONE' : l:cattr
  endif
  let l:cmd .= ' cterm=' . l:cattr
  execute l:cmd
endfunction

" ── 기본 텍스트와 화면 요소 ────────────────────────────────────────────────
call s:hi('Normal',        'fg',      'bg',        '')
call s:hi('NormalNC',      'fg',      'bg',        '')
call s:hi('NormalFloat',   'fg',      'linenrbg',  '')
call s:hi('FloatBorder',   'linenr',  'linenrbg',  '')
call s:hi('LineNr',        'linenr',  'linenrbg',  '')
call s:hi('SignColumn',    'linenr',  'linenrbg',  '')
call s:hi('CursorLine',    '',        'cursorline','')
call s:hi('CursorColumn',  '',        'cursorline','')
call s:hi('CursorLineNr',  'keyword', 'cursorline','bold')
call s:hi('ColorColumn',   '',        'cursorline','')
" SI 의 선택 색: 흰 글자 + 네이비 배경 (구문 색을 덮는다).
" 예전처럼 옅은 파랑만 깔고 글자색을 살리려면 두 줄을 'sel' 로 되돌리면 된다.
call s:hi('Visual',        'bg',      'selbg',     '')
call s:hi('VisualNOS',     'bg',      'selbg',     '')
call s:hi('Search',        'fg',      'match',     '')
call s:hi('IncSearch',     'bg',      'warn',      'bold')
call s:hi('CurSearch',     'bg',      'warn',      'bold')
call s:hi('MatchParen',    'err',     'match',     'bold')
call s:hi('StatusLine',    'uifg',    'ui',        '')
call s:hi('StatusLineNC',  'linenr',  'linenrbg',  '')
call s:hi('VertSplit',     'ui',      'bg',        '')
call s:hi('WinSeparator',  'ui',      'bg',        '')
call s:hi('TabLine',       'linenr',  'linenrbg',  '')
call s:hi('TabLineSel',    'fg',      'bg',        'bold')
call s:hi('TabLineFill',   'linenr',  'ui',        '')
call s:hi('Pmenu',         'fg',      'linenrbg',  '')
call s:hi('PmenuSel',      'fg',      'sel',       'bold')
call s:hi('PmenuSbar',     '',        'ui',        '')
call s:hi('PmenuThumb',    '',        'linenr',    '')
call s:hi('WildMenu',      'fg',      'sel',       'bold')
call s:hi('Folded',        'linenr',  'linenrbg',  '')
call s:hi('FoldColumn',    'linenr',  'linenrbg',  '')
call s:hi('Directory',     'keyword', '',          '')
call s:hi('Title',         'keyword', '',          'bold')
call s:hi('Question',      'comment', '',          '')
call s:hi('MoreMsg',       'comment', '',          '')
call s:hi('ModeMsg',       'fg',      '',          'bold')
call s:hi('ErrorMsg',      'err',     '',          'bold')
call s:hi('WarningMsg',    'warn',    '',          '')
call s:hi('NonText',       'ui',      '',          '')
call s:hi('SpecialKey',    'ui',      '',          '')
call s:hi('Whitespace',    'ui',      '',          '')
call s:hi('Conceal',       'linenr',  '',          '')
call s:hi('QuickFixLine',  'fg',      'sel',       '')
" 커서. 터미널 커서 색은 guicursor 가 가리키는 하이라이트 그룹에서 오므로
" ~/.vimrc 의 s:VimIdeApplyTheme() 이 guicursor 에 'Cursor' 를 붙여 준다.
" 색을 바꾸려면: let g:sourceinsight_cursor = '#0087ff'
let s:cur = get(g:, 'sourceinsight_cursor', '#000000')
execute 'highlight Cursor guifg=' . s:c.bg[0] . ' guibg=' . s:cur
            \ . ' ctermfg=' . s:c.bg[1] . ' ctermbg=16'
highlight! link lCursor Cursor
highlight! link CursorIM Cursor
highlight! link TermCursor Cursor

" ── 코드: SI 는 색을 적게 쓴다 ─────────────────────────────────────────────
call s:hi('Comment',       'comment', '',          '')
call s:hi('Constant',      'number',  '',          '')
" SI 의 String 스타일은 글자색뿐 아니라 연노랑 배경까지 포함한다
call s:hi('String',        'string',  'stringbg',  '')
call s:hi('Character',     'string',  'stringbg',  '')
call s:hi('Number',        'number',  '',          '')
call s:hi('Boolean',       'keyword', '',          s:kw)
call s:hi('Float',         'number',  '',          '')
call s:hi('Identifier',    'fg',      '',          '')
call s:hi('Function',      'ref',     '',          'bold')
" 제어 키워드(if/for/return/goto)는 factory 에서 일반 키워드와 색이 다르다
call s:hi('Statement',     'control', '',          'bold')
call s:hi('Conditional',   'control', '',          'bold')
call s:hi('Repeat',        'control', '',          'bold')
call s:hi('Label',         'label',   '',          'bold')
call s:hi('Operator',      'ref',     '',          '')
call s:hi('Keyword',       'keyword', '',          s:kw)
call s:hi('Exception',     'control', '',          'bold')
call s:hi('PreProc',       'preproc', '',          '')
call s:hi('Include',       'incdef',  '',          '')
call s:hi('Define',        'incdef',  '',          '')
call s:hi('Macro',         'macro',   '',          '')
call s:hi('PreCondit',     'preproc', '',          '')
" struct/typedef/enum 이름은 초록 볼드(심볼 참조 색). 'int'/'uint32_t' 처럼
" 언어가 아는 타입은 키워드 색이 된다.
call s:hi('Type',          'type',    '',          s:tp)
call s:hi('StorageClass',  'keyword', '',          s:kw)
call s:hi('Structure',     'keyword', '',          s:kw)
call s:hi('Typedef',       'type',    '',          s:tp)
call s:hi('Special',       'fg',      '',          '')
call s:hi('SpecialChar',   'string',  'stringbg',  '')
call s:hi('Delimiter',     'delim',   '',          '')
call s:hi('SpecialComment','comment', '',          'bold')
call s:hi('Debug',         'macro',   '',          '')
call s:hi('Underlined',    'keyword', '',          'underline')
call s:hi('Ignore',        'linenr',  '',          '')
call s:hi('Error',         'err',     '',          'bold')
call s:hi('Todo',          'err',     'match',     'bold')

" ── diff / spell / diagnostics ────────────────────────────────────────────
call s:hi('DiffAdd',       'fg',      'diffadd',   '')
call s:hi('DiffChange',    'fg',      'diffchg',   '')
call s:hi('DiffDelete',    'err',     'diffdel',   '')
call s:hi('DiffText',      'fg',      'match',     'bold')
call s:hi('SpellBad',      'err',     '',          'underline')
call s:hi('SpellCap',      'warn',    '',          'underline')
call s:hi('SpellLocal',    'comment', '',          'underline')
call s:hi('SpellRare',     'macro',   '',          'underline')

" ── RelationView / ProjectSymbols 패널 ────────────────────────────────────
" 패널은 코드가 아니라 목록이다: 주석 초록이 아니라 회색이 맞다.
" (relationview.lua 는 이 그룹들을 default 로만 정의하므로 여기가 이긴다)
call s:hi('RvHeader',       'keyword', '',           'bold')
call s:hi('RvSection',      'keyword', '',           'bold')
call s:hi('RvName',         'fg',      '',           '')
" 경로는 파랑. 목록의 나머지(트리 선, 힌트, 부가 정보)는 회색으로 두고
" 파일 경로만 눈에 띄게 한다 - vim 이 경로에 쓰는 Directory 와 같은 남색이고,
" relationview.lua 도 원래 RvLoc 를 Directory 에 link 해 두었다.
call s:hi('RvLoc',          'keyword', '',           '')
call s:hi('RvDim',          'linenr',  '',           '')
call s:hi('RvTree',         'linenr',  '',           '')
call s:hi('RvHint',         'linenr',  '',           '')
call s:hi('RvMarker',       'macro',   '',           '')
call s:hi('RvCursorSym',    'keyword', '',           'bold')
call s:hi('RvCursorLine',   '',        'sel',        '')
call s:hi('RvCursorLineNr', 'keyword', 'sel',        'bold')
" telescope 픽커(ProjectSymbols/ProjectFiles)도 SI 의 목록 창처럼:
" 흰 바탕 + 검정 글자, 고른 줄은 옅은 파랑, 일치한 글자만 네이비 볼드
highlight! link TelescopeNormal        Normal
highlight! link TelescopePreviewNormal Normal
call s:hi('TelescopeBorder',        'ui',      '',        '')
call s:hi('TelescopePromptBorder',  'ui',      '',        '')
call s:hi('TelescopeResultsBorder', 'ui',      '',        '')
call s:hi('TelescopePreviewBorder', 'ui',      '',        '')
call s:hi('TelescopeTitle',         'keyword', '',        'bold')
highlight! link TelescopePromptTitle   TelescopeTitle
highlight! link TelescopeResultsTitle  TelescopeTitle
highlight! link TelescopePreviewTitle  TelescopeTitle
call s:hi('TelescopeSelection',     'fg',      'sel',     '')
call s:hi('TelescopeSelectionCaret', 'keyword', 'sel',    'bold')
call s:hi('TelescopeMatching',      'keyword', '',        'bold')
call s:hi('TelescopePromptCounter', 'linenr',  '',        '')
call s:hi('TelescopeResultsComment', 'linenr', '',        '')
call s:hi('TelescopePreviewLine',   '',        'cursorline', '')

" 커서 밑 심볼의 모든 등장 위치 (SI 의 'Reference Highlight' 스타일 값)
highlight SiRefHighlight guifg=#000000 guibg=#aae1ff ctermfg=16 ctermbg=153


" 점프가 착지한 심볼: 하늘색 상자는 두 테마 공통으로 쓴다
highlight RvCtxSym guifg=#101820 guibg=#87d7ff ctermfg=16 ctermbg=117
            \ gui=bold cterm=bold

if !has('nvim')
  finish
endif

" ── 여기부터는 Neovim 전용 ────────────────────────────────────────────────
" vim 은 '@' 로 시작하는 하이라이트 그룹 이름을 받지 않는다(E475). 그래서
" treesitter/LSP 관련 그룹은 모두 이 아래에 있어야 한다.

" clangd 등 LSP 를 켜도 커서 밑 심볼과 같은 음영을 쓰게 한다
highlight! link LspReferenceText  SiRefHighlight
highlight! link LspReferenceRead  SiRefHighlight
highlight! link LspReferenceWrite SiRefHighlight

" '#if 0' 안의 죽은 코드: SI 의 'Inactive Code' 처럼 회색으로 눌러 둔다
" (after/queries/c/highlights.scm 이 우선순위 105 로 잡아 준다)
call s:hi('@si.inactive', 'linenr', '', '')

" 지역 변수를 '여기서 선언된 것'으로 알아본 자리 (sihllocal.lua)
call s:hi('SiJumpLocal', 'jumplocal', '', '')
" 색인이 정의부를 모르는 심볼 (sihlindex.lua). 본문색으로 떨어뜨린다 -
" 초록이 '점프할 수 있다'는 뜻이 되려면, 못 하는 것은 초록이 아니어야 한다.
call s:hi('SiJumpNone', 'fg', '', '')
" 함수 안에서 쓰는 전역 변수 (sihllocal.lua)
call s:hi('SiGlobalRef', 'globalref', '', 'italic')
" 색인이 '#define' 으로 확인해 준 매크로 (sihlindex.lua). 상수 매크로가
" 원래 쓰던 빨강과 같은 색이다 - 함수형 매크로도 같은 것으로 보여야 한다.
call s:hi('SiMacroRef', 'number', '', '')

call s:hi('DiagnosticError', 'err',     '', '')
call s:hi('DiagnosticWarn',  'warn',    '', '')
call s:hi('DiagnosticInfo',  'keyword', '', '')
call s:hi('DiagnosticHint',  'comment', '', '')
highlight! link DiagnosticUnderlineError SpellBad
highlight! link DiagnosticUnderlineWarn  SpellCap
highlight! link DiagnosticUnderlineInfo  SpellLocal
highlight! link DiagnosticUnderlineHint  SpellRare

" ── Treesitter: C/C++ 를 SI 처럼 보이게 하는 핵심 ─────────────────────────
" nvim-treesitter 가 붙으면 @... 그룹이 위의 고전 그룹을 덮어쓰므로
" 여기서 같은 배색으로 다시 묶어 준다.
let s:ts = {
      \ 'keyword':            ['keyword', s:kw],
      \ 'keyword.function':   ['keyword', s:kw],
      \ 'keyword.operator':   ['keyword', s:kw],
      \ 'keyword.return':     ['control', 'bold'],
      \ 'keyword.repeat':     ['control', 'bold'],
      \ 'keyword.conditional':['control', 'bold'],
      \ 'keyword.modifier':   ['keyword', s:kw],
      \ 'keyword.type':       ['keyword', s:kw],
      \ 'keyword.exception':  ['control', 'bold'],
      \ 'keyword.directive':  ['preproc', s:kw],
      \ 'keyword.directive.define': ['incdef', ''],
      \ 'keyword.import':     ['incdef', ''],
      \ 'type':               ['type',    s:tp],
      \ 'type.builtin':       ['typeref', s:tp],
      \ 'type.definition':    ['type',    s:tp],
      \ 'type.qualifier':     ['keyword', s:kw],
      \ 'storageclass':       ['keyword', s:kw],
      \ 'structure':          ['keyword', s:kw],
      \ 'comment':            ['comment', ''],
      \ 'comment.documentation': ['comment', ''],
      \ 'string':             ['string',  ''],
      \ 'string.escape':      ['string',  'bold'],
      \ 'string.special':     ['string',  ''],
      \ 'character':          ['string',  ''],
      \ 'character.special':  ['string',  'bold'],
      \ 'number':             ['number',  ''],
      \ 'number.float':       ['number',  ''],
      \ 'boolean':            ['keyword', s:kw],
      \ 'constant':           ['number',  ''],
      \ 'constant.builtin':   ['number',  ''],
      \ 'constant.macro':     ['macro',   s:kw],
      \ 'function':           ['ref',     'bold'],
      \ 'function.call':      ['ref',     'bold'],
      \ 'function.builtin':   ['ref',     'bold'],
      \ 'function.macro':     ['macro',   'bold'],
      \ 'variable':           ['fg',      ''],
      \ 'variable.builtin':   ['keyword', 'bold'],
      \ 'variable.parameter': ['reflocal', ''],
      \ 'variable.member':    ['fg',      ''],
      \ 'property':           ['fg',      ''],
      \ 'field':              ['fg',      ''],
      \ 'label':              ['label',   'bold'],
      \ 'operator':           ['ref',     ''],
      \ 'punctuation':        ['fg',      ''],
      \ 'punctuation.bracket':['fg',      ''],
      \ 'punctuation.delimiter': ['delim', ''],
      \ 'punctuation.special':['macro',   ''],
      \ 'preproc':            ['preproc', s:kw],
      \ 'define':             ['incdef', ''],
      \ 'include':            ['incdef', ''],
      \ 'attribute':          ['macro',   ''],
      \ 'module':             ['fg',      ''],
      \ 'tag':                ['keyword', 'bold'],
      \ }
for [s:g, s:v] in items(s:ts)
  call s:hi('@' . s:g, s:v[0], '', s:v[1])
endfor

" 문자열은 연노랑 배경까지가 SI 의 String 스타일이다 (표는 글자색만 다룬다)
for s:g in ['string', 'string.escape', 'string.special', 'string.special.path',
      \ 'string.special.url', 'character', 'character.special']
  call s:hi('@' . s:g, 'string', 'stringbg', '')
endfor

" 선언에 밑줄 (~/.vim/after/queries/c/highlights.scm 이 잡아 준다).
" SI 는 선언을 색이 아니라 밑줄로 구분한다: 색은 본문과 같다.
" 타입 이름을 '쓰는' 자리: uint32_t, enum tcc_asrc_drv_sync_mode_t 등
" (정의하는 자리는 아래 @si.declaration.function 이 짙은 파랑으로 덮는다)
call s:hi('@si.type.ref', 'typeref', '', s:tp)

" __iomem/__user/__init 같은 커널 주석 매크로 (after/queries 가 잡아 준다)
call s:hi('@si.kernel.attr', 'number', '', '')

" #ifdef/#if defined() 의 조건 이름: 지시문과 같은 색 (코드 안의 상수
" 매크로와 캡처가 같아서 확장 쿼리로 따로 잡아 낸다)
call s:hi('@si.directive.cond', s:variant ==# 'factory' ? 'preproc' : 'number',
      \ '', s:variant ==# 'factory' ? 'bold' : '')

" 선언 (~/.vim/after/queries/{c,cpp}/highlights.scm 이 잡아 준다)
" 함수/구조체/enum/typedef 의 '정의된 이름' 강조 (위 g:..._emphasis)
let s:name_attr = s:emph ==# 'off' ? '' :
      \ (s:emph ==# 'strong' ? 'bold,underline' : 'bold')
let s:name_bg   = s:emph ==# 'strong' ? 'declbg' : ''
let s:name_fg   = s:emph ==# 'off' ? '' : 'decl'

if s:variant ==# 'factory'
  " 출고 기본값: 선언은 네이비 볼드고, 밑줄은 파라미터와 레이블에만 붙는다
  call s:hi('@si.declaration',           'decl', '', 'bold')
  call s:hi('@si.declaration.function',  s:name_fg, s:name_bg,
        \ s:emph ==# 'off' ? 'bold' : 'bold')
  call s:hi('@si.declaration.parameter', 'decl', '', 'bold,underline')
  call s:hi('@si.declaration.enumconst', 'decl', '', 'bold')
  call s:hi('@si.declaration.label',     'label', '', 'bold,underline')
else
  " 화면 기준: 함수/타입 정의 이름은 네이비 볼드, 변수·파라미터 선언은
  " 본문색에 밑줄만 (화면에서 그렇게 보인다)
  " 구조체 멤버와 파일 스코프(전역) 변수 선언도 네이비 볼드.
  "
  " 밑줄은 여기서도 뺐다. 밑줄이 남는 곳은 함수 파라미터 하나뿐이다 -
  " 파라미터는 바로 옆 지역변수와 같은 네이비 볼드라 밑줄 말고는 갈라
  " 놓을 것이 없지만, 그 밖의 선언은 자리만으로 이미 구분된다. 선언마다
  " 밑줄이 그어지면 강조가 아니라 소음이 된다.
  call s:hi('@si.declaration',           'decllocal', '', 'bold')
  call s:hi('@si.declaration.function',  s:name_fg, s:name_bg, s:name_attr)
  " 함수 파라미터와 함수 안에서 선언한 지역 변수는 네이비 볼드.
  "
  " 밑줄은 파라미터에만 남긴다. 둘 다 네이비 볼드라 색으로는 구별되지
  " 않는데, 파라미터는 '밖에서 들어온 값'이고 지역변수는 '여기서 만든 값'
  " 이라 한눈에 갈라져야 한다. 밑줄 하나가 그 차이를 진다 - 출고 기본값
  " (factory)에서 밑줄이 파라미터와 레이블에만 붙는 것과도 같아진다.
  "
  " 구조체 멤버와 파일 스코프 선언은 위 @si.declaration 그대로
  " (본문색 + 밑줄) 둔다.
  call s:hi('@si.declaration.parameter', 'decllocal', '', 'bold,underline')
  call s:hi('@si.declaration.local',     'decllocal', '', 'bold')
  " enum 요소는 네이비 볼드 (상수 매크로의 옅은 빨강과 구분된다)
  call s:hi('@si.declaration.enumconst', 'decl', '', 'bold')
  " goto 레이블도 밑줄을 뺀다 - 빨강 볼드라 이미 다른 무엇과도 섞이지 않는다
  call s:hi('@si.declaration.label',     'label', '', 'bold')
endif

" LSP 의미 토큰도 같은 배색으로
highlight! link @lsp.type.class      @type
highlight! link @lsp.type.struct     @type
highlight! link @lsp.type.enum       @type
highlight! link @lsp.type.typedef    @type
highlight! link @lsp.type.macro      @function.macro
highlight! link @lsp.type.keyword    @keyword
highlight! link @lsp.type.comment    @comment
highlight! link @lsp.type.string     @string
highlight! link @lsp.type.number     @number
highlight! link @lsp.type.function   @function
highlight! link @lsp.type.method     @function
highlight! link @lsp.type.variable   @variable
highlight! link @lsp.type.parameter  @variable.parameter
highlight! link @lsp.type.property   @property
