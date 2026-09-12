" markpalette.vim - F4(vim-mark)로 입히는 색.
"
" .vimrc 에서 source 한다. plugin/ 이 아니라 ~/.vim 바로 아래 두는 이유는
" 순서 때문이다: vim-mark 은 plugin 이 읽힐 때 g:mwDefaultHighlightingPalette
" 를 보는데, 그건 .vimrc 가 끝난 뒤다. 그래서 .vimrc 안에서 읽혀야 한다.
"
" 기준은 F8 노랑이다
" ------------------
" yellowmark.lua 의 SiYellowMark 는 ctermbg=11 / #ffff00 에 검은 글자다.
" 상대 휘도 0.93, 채도 1.00 - 밝으면서 '진하다'. 그게 읽히는 이유다.
" 그래서 이 팔레트의 1번은 그 색 그대로다(256색으로는 226번).
"
" 고르는 기준
"   * 휘도 0.58 이상 - 검은 글자가 읽힌다
"   * 채도 0.45 이상 - 흰 배경에서 '색 블록'으로 보인다. 이게 없으면
"     #ffffd7 같은 것이 '가장 밝은 색'으로 뽑히는데, 그건 종이와 구별이
"     안 된다. 밝기만으로 줄 세우면 안 되는 이유다.
"
" 늘어놓는 기준
"   밝은 것을 앞에 두되, 이미 나온 색들과 색상이 충분히 떨어져야 한다.
"   그 각도를 못 채우면 기준을 한 단계 낮춘다. 그래서 앞쪽이 이렇게 된다:
"     1 노랑  2 하늘  3 분홍  4 연두  5 빨강  6 파랑  7 라임  8 민트  9 주황
"   한눈에 갈리는 여섯 색이 먼저 오고, 각자 그 색상에서 낼 수 있는 만큼
"   밝다. 빨강과 파랑이 노랑보다 어두운 것은 고른 탓이 아니라 원래 그렇다
"   (같은 채도에서 사람 눈이 받는 밝기가 다르다).
"
" 값은 256색 번호(ctermbg)가 본체다. 이 설정은 두 기계 모두 termguicolors
" 가 꺼져 있어서(SSH 로는 COLORTERM 이 안 넘어온다) guibg 는 쓰이지 않는다
" - 나중에 켤 때를 위해 같은 색을 함께 적어 둔다.
"
" 되돌리려면 .vimrc 의 source 줄을 지우면 된다. vim-mark 의 팔레트도 그대로
" 살아 있으므로 :MarkPalette maximum / extended / soft / softer 로 언제든
" 바꿔 볼 수 있다.

let g:mwDefaultHighlightingPalette = [
	\ {'ctermbg':226,'ctermfg':'Black','guibg':'#ffff00','guifg':'Black'},
	\ {'ctermbg':123,'ctermfg':'Black','guibg':'#87ffff','guifg':'Black'},
	\ {'ctermbg':213,'ctermfg':'Black','guibg':'#ff87ff','guifg':'Black'},
	\ {'ctermbg':120,'ctermfg':'Black','guibg':'#87ff87','guifg':'Black'},
	\ {'ctermbg':210,'ctermfg':'Black','guibg':'#ff8787','guifg':'Black'},
	\ {'ctermbg':111,'ctermfg':'Black','guibg':'#87afff','guifg':'Black'},
	\ {'ctermbg':155,'ctermfg':'Black','guibg':'#afff5f','guifg':'Black'},
	\ {'ctermbg': 85,'ctermfg':'Black','guibg':'#5fffaf','guifg':'Black'},
	\ {'ctermbg':215,'ctermfg':'Black','guibg':'#ffaf5f','guifg':'Black'},
	\ {'ctermbg':141,'ctermfg':'Black','guibg':'#af87ff','guifg':'Black'},
	\ {'ctermbg':117,'ctermfg':'Black','guibg':'#87d7ff','guifg':'Black'},
	\ {'ctermbg':212,'ctermfg':'Black','guibg':'#ff87d7','guifg':'Black'},
	\ {'ctermbg':211,'ctermfg':'Black','guibg':'#ff87af','guifg':'Black'},
	\ {'ctermbg':177,'ctermfg':'Black','guibg':'#d787ff','guifg':'Black'},
	\ {'ctermbg':192,'ctermfg':'Black','guibg':'#d7ff87','guifg':'Black'},
	\ {'ctermbg':122,'ctermfg':'Black','guibg':'#87ffd7','guifg':'Black'},
	\ {'ctermbg':121,'ctermfg':'Black','guibg':'#87ffaf','guifg':'Black'},
	\ {'ctermbg':119,'ctermfg':'Black','guibg':'#87ff5f','guifg':'Black'},
	\ {'ctermbg':222,'ctermfg':'Black','guibg':'#ffd787','guifg':'Black'},
	\ {'ctermbg':216,'ctermfg':'Black','guibg':'#ffaf87','guifg':'Black'},
	\ {'ctermbg': 75,'ctermfg':'Black','guibg':'#5fafff','guifg':'Black'},
	\ {'ctermbg':228,'ctermfg':'Black','guibg':'#ffff87','guifg':'Black'},
	\ {'ctermbg':227,'ctermfg':'Black','guibg':'#ffff5f','guifg':'Black'},
	\ {'ctermbg':191,'ctermfg':'Black','guibg':'#d7ff5f','guifg':'Black'},
	\ {'ctermbg':156,'ctermfg':'Black','guibg':'#afff87','guifg':'Black'},
	\ {'ctermbg':190,'ctermfg':'Black','guibg':'#d7ff00','guifg':'Black'},
	\ {'ctermbg': 87,'ctermfg':'Black','guibg':'#5fffff','guifg':'Black'},
	\ {'ctermbg':154,'ctermfg':'Black','guibg':'#afff00','guifg':'Black'},
	\ {'ctermbg': 86,'ctermfg':'Black','guibg':'#5fffd7','guifg':'Black'},
	\ {'ctermbg':221,'ctermfg':'Black','guibg':'#ffd75f','guifg':'Black'},
	\ {'ctermbg': 84,'ctermfg':'Black','guibg':'#5fff87','guifg':'Black'},
	\ {'ctermbg':118,'ctermfg':'Black','guibg':'#87ff00','guifg':'Black'},
	\ {'ctermbg': 83,'ctermfg':'Black','guibg':'#5fff5f','guifg':'Black'},
	\ {'ctermbg':220,'ctermfg':'Black','guibg':'#ffd700','guifg':'Black'},
	\ {'ctermbg':185,'ctermfg':'Black','guibg':'#d7d75f','guifg':'Black'},
	\ {'ctermbg': 82,'ctermfg':'Black','guibg':'#5fff00','guifg':'Black'},
	\ {'ctermbg': 51,'ctermfg':'Black','guibg':'#00ffff','guifg':'Black'},
	\ {'ctermbg':184,'ctermfg':'Black','guibg':'#d7d700','guifg':'Black'},
	\ {'ctermbg': 50,'ctermfg':'Black','guibg':'#00ffd7','guifg':'Black'},
	\ {'ctermbg':149,'ctermfg':'Black','guibg':'#afd75f','guifg':'Black'},
	\ {'ctermbg': 49,'ctermfg':'Black','guibg':'#00ffaf','guifg':'Black'},
	\ {'ctermbg': 81,'ctermfg':'Black','guibg':'#5fd7ff','guifg':'Black'},
	\ {'ctermbg': 48,'ctermfg':'Black','guibg':'#00ff87','guifg':'Black'},
	\ {'ctermbg':148,'ctermfg':'Black','guibg':'#afd700','guifg':'Black'},
	\ {'ctermbg': 80,'ctermfg':'Black','guibg':'#5fd7d7','guifg':'Black'},
	\ {'ctermbg':113,'ctermfg':'Black','guibg':'#87d75f','guifg':'Black'},
	\ {'ctermbg': 47,'ctermfg':'Black','guibg':'#00ff5f','guifg':'Black'},
	\ {'ctermbg': 79,'ctermfg':'Black','guibg':'#5fd7af','guifg':'Black'},
	\ {'ctermbg': 78,'ctermfg':'Black','guibg':'#5fd787','guifg':'Black'},
	\ {'ctermbg':112,'ctermfg':'Black','guibg':'#87d700','guifg':'Black'},
	\ {'ctermbg': 46,'ctermfg':'Black','guibg':'#00ff00','guifg':'Black'},
	\ {'ctermbg': 77,'ctermfg':'Black','guibg':'#5fd75f','guifg':'Black'},
	\ {'ctermbg':214,'ctermfg':'Black','guibg':'#ffaf00','guifg':'Black'},
	\ {'ctermbg':179,'ctermfg':'Black','guibg':'#d7af5f','guifg':'Black'},
	\ {'ctermbg': 76,'ctermfg':'Black','guibg':'#5fd700','guifg':'Black'},
	\ {'ctermbg': 45,'ctermfg':'Black','guibg':'#00d7ff','guifg':'Black'},
	\ {'ctermbg':178,'ctermfg':'Black','guibg':'#d7af00','guifg':'Black'},
	\ {'ctermbg': 44,'ctermfg':'Black','guibg':'#00d7d7','guifg':'Black'},
	\ {'ctermbg':143,'ctermfg':'Black','guibg':'#afaf5f','guifg':'Black'},
	\ {'ctermbg': 43,'ctermfg':'Black','guibg':'#00d7af','guifg':'Black'},
	\ {'ctermbg': 42,'ctermfg':'Black','guibg':'#00d787','guifg':'Black'},
	\ {'ctermbg':142,'ctermfg':'Black','guibg':'#afaf00','guifg':'Black'},
	\ {'ctermbg': 74,'ctermfg':'Black','guibg':'#5fafd7','guifg':'Black'},
	\ {'ctermbg':107,'ctermfg':'Black','guibg':'#87af5f','guifg':'Black'},
	\ {'ctermbg': 41,'ctermfg':'Black','guibg':'#00d75f','guifg':'Black'},
	\ {'ctermbg': 73,'ctermfg':'Black','guibg':'#5fafaf','guifg':'Black'},
	\ {'ctermbg':209,'ctermfg':'Black','guibg':'#ff875f','guifg':'Black'},
	\ {'ctermbg': 72,'ctermfg':'Black','guibg':'#5faf87','guifg':'Black'},
	\ {'ctermbg':106,'ctermfg':'Black','guibg':'#87af00','guifg':'Black'},
	\ {'ctermbg': 40,'ctermfg':'Black','guibg':'#00d700','guifg':'Black'},
	\ {'ctermbg': 71,'ctermfg':'Black','guibg':'#5faf5f','guifg':'Black'},
	\ {'ctermbg':208,'ctermfg':'Black','guibg':'#ff8700','guifg':'Black'},
	\ {'ctermbg':173,'ctermfg':'Black','guibg':'#d7875f','guifg':'Black'},
	\ ]
