" sourceinsight.vim - Source Insight 기본 테마 배색
"
"   순백 배경 + 검정 본문 + 진한 네이비 볼드 키워드 + 초록 이탤릭 주석
"   + 마룬(적갈색) 문자열. 색을 아주 적게 쓰는 것이 SI 화면의 특징이다.
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
highlight Cursor guifg=#ffffff guibg=#000000
highlight! link CursorIM Cursor

" ── 코드: SI 는 색을 적게 쓴다 ─────────────────────────────────────────────
call s:hi('Comment',       'comment', '',          'italic')
call s:hi('Constant',      'number',  '',          '')
call s:hi('String',        'string',  '',          '')
call s:hi('Character',     'string',  '',          '')
call s:hi('Number',        'number',  '',          '')
call s:hi('Boolean',       'keyword', '',          'bold')
call s:hi('Float',         'number',  '',          '')
call s:hi('Identifier',    'fg',      '',          '')
call s:hi('Function',      'fg',      '',          '')
call s:hi('Statement',     'keyword', '',          'bold')
call s:hi('Conditional',   'keyword', '',          'bold')
call s:hi('Repeat',        'keyword', '',          'bold')
call s:hi('Label',         'keyword', '',          'bold')
call s:hi('Operator',      'fg',      '',          '')
call s:hi('Keyword',       'keyword', '',          'bold')
call s:hi('Exception',     'keyword', '',          'bold')
call s:hi('PreProc',       'preproc', '',          '')
call s:hi('Include',       'preproc', '',          '')
call s:hi('Define',        'preproc', '',          '')
call s:hi('Macro',         'macro',   '',          '')
call s:hi('PreCondit',     'preproc', '',          '')
call s:hi('Type',          'type',    '',          'bold')
call s:hi('StorageClass',  'keyword', '',          'bold')
call s:hi('Structure',     'type',    '',          'bold')
call s:hi('Typedef',       'type',    '',          'bold')
call s:hi('Special',       'fg',      '',          '')
call s:hi('SpecialChar',   'string',  '',          '')
call s:hi('Delimiter',     'fg',      '',          '')
call s:hi('SpecialComment','comment', '',          'bold,italic')
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
call s:hi('RvSection',      'keyword', '',           '')
call s:hi('RvName',         'fg',      '',           '')
call s:hi('RvLoc',          'linenr',  '',           '')
call s:hi('RvDim',          'linenr',  '',           '')
call s:hi('RvTree',         'linenr',  '',           '')
call s:hi('RvHint',         'linenr',  '',           'italic')
call s:hi('RvMarker',       'macro',   '',           '')
call s:hi('RvCursorSym',    'keyword', '',           'bold')
call s:hi('RvCursorLine',   '',        'sel',        '')
call s:hi('RvCursorLineNr', 'keyword', 'sel',        'bold')
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
      \ 'keyword':            ['keyword', 'bold'],
      \ 'keyword.function':   ['keyword', 'bold'],
      \ 'keyword.operator':   ['keyword', 'bold'],
      \ 'keyword.return':     ['keyword', 'bold'],
      \ 'keyword.repeat':     ['keyword', 'bold'],
      \ 'keyword.conditional':['keyword', 'bold'],
      \ 'keyword.modifier':   ['keyword', 'bold'],
      \ 'keyword.type':       ['keyword', 'bold'],
      \ 'keyword.exception':  ['keyword', 'bold'],
      \ 'keyword.directive':  ['preproc', ''],
      \ 'keyword.directive.define': ['preproc', ''],
      \ 'keyword.import':     ['preproc', ''],
      \ 'type':               ['type',    'bold'],
      \ 'type.builtin':       ['type',    'bold'],
      \ 'type.definition':    ['type',    'bold'],
      \ 'type.qualifier':     ['keyword', 'bold'],
      \ 'storageclass':       ['keyword', 'bold'],
      \ 'structure':          ['type',    'bold'],
      \ 'comment':            ['comment', 'italic'],
      \ 'comment.documentation': ['comment', 'italic'],
      \ 'string':             ['string',  ''],
      \ 'string.escape':      ['string',  'bold'],
      \ 'string.special':     ['string',  ''],
      \ 'character':          ['string',  ''],
      \ 'character.special':  ['string',  'bold'],
      \ 'number':             ['number',  ''],
      \ 'number.float':       ['number',  ''],
      \ 'boolean':            ['keyword', 'bold'],
      \ 'constant':           ['fg',      ''],
      \ 'constant.builtin':   ['number',  ''],
      \ 'constant.macro':     ['macro',   ''],
      \ 'function':           ['fg',      ''],
      \ 'function.call':      ['fg',      ''],
      \ 'function.builtin':   ['fg',      ''],
      \ 'function.macro':     ['macro',   ''],
      \ 'variable':           ['fg',      ''],
      \ 'variable.builtin':   ['keyword', 'bold'],
      \ 'variable.parameter': ['fg',      ''],
      \ 'variable.member':    ['fg',      ''],
      \ 'property':           ['fg',      ''],
      \ 'field':              ['fg',      ''],
      \ 'label':              ['keyword', 'bold'],
      \ 'operator':           ['fg',      ''],
      \ 'punctuation':        ['fg',      ''],
      \ 'punctuation.bracket':['fg',      ''],
      \ 'punctuation.delimiter': ['fg',   ''],
      \ 'punctuation.special':['macro',   ''],
      \ 'preproc':            ['preproc', ''],
      \ 'define':             ['preproc', ''],
      \ 'include':            ['preproc', ''],
      \ 'attribute':          ['macro',   ''],
      \ 'module':             ['fg',      ''],
      \ 'tag':                ['keyword', 'bold'],
      \ }
for [s:g, s:v] in items(s:ts)
  call s:hi('@' . s:g, s:v[0], '', s:v[1])
endfor

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
