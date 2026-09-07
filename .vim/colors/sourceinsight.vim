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
"     'bold'   (기본) 네이비 볼드 + 밑줄
"     'strong'        네이비 볼드 + 밑줄 + 옅은 회색 배경 (SI 의 큰 글자 +
"                     그림자에 가장 가까운 효과)
"     'off'           특별한 강조 없음
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
  let s:c.label    = ['#ff5f5f', 203, 'red']
  let s:c.comment  = ['#800080', 90,  'darkmagenta']
  " 상수 매크로/숫자: 굵어 보이지 않는 얇은 빨강. 어두운 빨강(#cc5555)은
  " 획이 두껍게 읽히고, 새빨강(#ff0000)은 눈에 세다. 이 값은 흰 배경 대비
  " 3.0:1 이라 본문보다 약하게 뜬다 - 더 진하게 원하면 #e06666(3.4:1),
  " #cc5555(4.2:1) 로 올리면 된다.
  let s:c.number   = ['#ff5f5f', 203, 'red']
  let s:c.macro    = s:c.keyword
  " #include / #define 은 초록 (#if/#ifdef/#endif 는 네이비 볼드로 둔다)
  let s:c.incdef   = ['#008000', 28,  'darkgreen']
endif
if !has_key(s:c, 'incdef')
  let s:c.incdef = s:c.preproc
endif
if !has_key(s:c, 'typeref')
  let s:c.typeref = s:c.ref
endif

" 평범한 키워드의 볼드 여부는 배색마다 다르다: 화면 기준은 볼드,
" SI 출고 기본값은 Keyword 에 볼드가 없다(제어 키워드에만 있다).
let s:kw = s:variant ==# 'factory' ? '' : 'bold'

function! s:hi(group, fg, bg, attr) abort
  let l:cmd = 'highlight ' . a:group
  if a:fg !=# ''
    let l:cmd .= ' guifg=' . s:c[a:fg][0] . ' ctermfg=' . s:c[a:fg][1]
  endif
  if a:bg !=# ''
    let l:cmd .= ' guibg=' . s:c[a:bg][0] . ' ctermbg=' . s:c[a:bg][1]
  endif
  let l:cmd .= ' gui=' . (a:attr ==# '' ? 'NONE' : a:attr)
  let l:cmd .= ' cterm=' . (a:attr ==# '' ? 'NONE' : substitute(a:attr, 'italic', 'NONE', 'g'))
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
call s:hi('Visual',        '',        'sel',       '')
call s:hi('VisualNOS',     '',        'sel',       '')
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
call s:hi('QuickFixLine',  '',        'sel',       '')
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
call s:hi('Type',          'type',    '',          'bold')
call s:hi('StorageClass',  'keyword', '',          s:kw)
call s:hi('Structure',     'keyword', '',          s:kw)
call s:hi('Typedef',       'type',    '',          'bold')
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
call s:hi('RvLoc',          'linenr',  '',           '')
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

" 점프가 착지한 심볼: 하늘색 상자는 두 테마 공통으로 쓴다
highlight RvCtxSym guifg=#101820 guibg=#87d7ff ctermfg=16 ctermbg=117
            \ gui=bold cterm=bold

if !has('nvim')
  finish
endif

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
      \ 'type':               ['type',    'bold'],
      \ 'type.builtin':       ['typeref', 'bold'],
      \ 'type.definition':    ['type',    'bold'],
      \ 'type.qualifier':     ['keyword', 'bold'],
      \ 'storageclass':       ['keyword', 'bold'],
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
call s:hi('@si.type.ref', 'typeref', '', 'bold')

" __iomem/__user/__init 같은 커널 주석 매크로 (after/queries 가 잡아 준다)
call s:hi('@si.kernel.attr', 'number', '', '')

" #ifdef/#if defined() 의 조건 이름: 지시문과 같은 색 (코드 안의 상수
" 매크로와 캡처가 같아서 확장 쿼리로 따로 잡아 낸다)
call s:hi('@si.directive.cond', s:variant ==# 'factory' ? 'preproc' : 'number',
      \ '', s:variant ==# 'factory' ? 'bold' : '')

" 선언 (~/.vim/after/queries/{c,cpp}/highlights.scm 이 잡아 준다)
" 함수/구조체/enum/typedef 의 '정의된 이름' 강조 (위 g:..._emphasis)
let s:name_attr = s:emph ==# 'off' ? '' :
      \ (s:emph ==# 'strong' ? 'bold,underline' : 'bold,underline')
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
  call s:hi('@si.declaration',           '',     '', 'underline')
  call s:hi('@si.declaration.function',  s:name_fg, s:name_bg, s:name_attr)
  call s:hi('@si.declaration.parameter', '',     '', 'underline')
  " enum 요소는 네이비 볼드 (상수 매크로의 옅은 빨강과 구분된다)
  call s:hi('@si.declaration.enumconst', 'decl', '', 'bold')
  call s:hi('@si.declaration.label',     'label', '', 'bold,underline')
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
