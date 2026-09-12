" markpalette.vim - F4(vim-mark)로 입히는 색.
"
" .vimrc 에서 source 한다. plugin/ 이 아니라 ~/.vim 바로 아래 두는 이유는
" 순서 때문이다: vim-mark 은 plugin 이 읽힐 때 g:mwDefaultHighlightingPalette
" 를 보는데, 그건 .vimrc 가 끝난 뒤다. 그래서 .vimrc 안에서 읽혀야 한다.
"
" 왜 직접 만들었나
" ----------------
" vim-mark 이 주는 것 중 가장 큰 'maximum' 이 58개인데, 7번째부터는 어두운
" 바탕에 흰 글자다. 이 설정은 흰 배경(sourceinsight, background=light)이라
" 그 블록들이 본문 사이에서 지나치게 튄다. 그리고 이웃한 색이 비슷해서
" 두세 개를 동시에 켜 두면 어느 것이 어느 것인지 구별이 잘 안 됐다.
"
" 여기 것은 세 가지가 다르다.
"   1) 전부 '밝은 바탕 + 검은 글자'다. 밝기(상대 휘도)가 0.53~0.93 안에만
"      있게 골랐다 - 검은 글자가 편하게 읽히는 구간이다.
"   2) 이웃끼리 최대한 다른 색이 오도록 황금각(약 137.5도)으로 돌려 놓았다.
"      처음 열 개의 색상각: 0 120 240 46 166 320 93 210 30 150 - 빨강,
"      초록, 파랑, 노랑, 청록, 자홍 … 순으로 갈린다. 색상환을 순서대로
"      돌면 이웃이 늘 비슷해지는데, 그걸 피하는 표준적인 방법이다.
"   3) 75개다 (maximum 의 58개보다 많다).
"
" 값은 256색 번호(ctermbg)가 본체다. 이 설정은 두 기계 모두
" termguicolors 가 꺼져 있어서(SSH 로는 COLORTERM 이 안 넘어온다) guibg 는
" 쓰이지 않는다 - 나중에 켤 때를 위해 같은 색을 함께 적어 둔다.
"
" 되돌리려면 .vimrc 의 source 줄을 지우면 된다. vim-mark 의 팔레트도 그대로
" 살아 있으므로 :MarkPalette maximum / extended / soft / softer 로 언제든
" 바꿔 볼 수 있다.

let g:mwDefaultHighlightingPalette = [
	\ {'ctermbg':210,'ctermfg':'Black','guibg':'#ff8787','guifg':'Black'},
	\ {'ctermbg': 40,'ctermfg':'Black','guibg':'#00d700','guifg':'Black'},
	\ {'ctermbg':104,'ctermfg':'Black','guibg':'#8787d7','guifg':'Black'},
	\ {'ctermbg':136,'ctermfg':'Black','guibg':'#af8700','guifg':'Black'},
	\ {'ctermbg': 36,'ctermfg':'Black','guibg':'#00af87','guifg':'Black'},
	\ {'ctermbg':212,'ctermfg':'Black','guibg':'#ff87d7','guifg':'Black'},
	\ {'ctermbg': 76,'ctermfg':'Black','guibg':'#5fd700','guifg':'Black'},
	\ {'ctermbg':110,'ctermfg':'Black','guibg':'#87afd7','guifg':'Black'},
	\ {'ctermbg':215,'ctermfg':'Black','guibg':'#ffaf5f','guifg':'Black'},
	\ {'ctermbg': 85,'ctermfg':'Black','guibg':'#5fffaf','guifg':'Black'},
	\ {'ctermbg':207,'ctermfg':'Black','guibg':'#ff5fff','guifg':'Black'},
	\ {'ctermbg':154,'ctermfg':'Black','guibg':'#afff00','guifg':'Black'},
	\ {'ctermbg': 81,'ctermfg':'Black','guibg':'#5fd7ff','guifg':'Black'},
	\ {'ctermbg':217,'ctermfg':'Black','guibg':'#ffafaf','guifg':'Black'},
	\ {'ctermbg': 77,'ctermfg':'Black','guibg':'#5fd75f','guifg':'Black'},
	\ {'ctermbg':103,'ctermfg':'Black','guibg':'#8787af','guifg':'Black'},
	\ {'ctermbg':220,'ctermfg':'Black','guibg':'#ffd700','guifg':'Black'},
	\ {'ctermbg': 50,'ctermfg':'Black','guibg':'#00ffd7','guifg':'Black'},
	\ {'ctermbg':175,'ctermfg':'Black','guibg':'#d787af','guifg':'Black'},
	\ {'ctermbg':113,'ctermfg':'Black','guibg':'#87d75f','guifg':'Black'},
	\ {'ctermbg':111,'ctermfg':'Black','guibg':'#87afff','guifg':'Black'},
	\ {'ctermbg':172,'ctermfg':'Black','guibg':'#d78700','guifg':'Black'},
	\ {'ctermbg': 42,'ctermfg':'Black','guibg':'#00d787','guifg':'Black'},
	\ {'ctermbg':176,'ctermfg':'Black','guibg':'#d787d7','guifg':'Black'},
	\ {'ctermbg': 70,'ctermfg':'Black','guibg':'#5faf00','guifg':'Black'},
	\ {'ctermbg': 74,'ctermfg':'Black','guibg':'#5fafd7','guifg':'Black'},
	\ {'ctermbg':209,'ctermfg':'Black','guibg':'#ff875f','guifg':'Black'},
	\ {'ctermbg': 78,'ctermfg':'Black','guibg':'#5fd787','guifg':'Black'},
	\ {'ctermbg':140,'ctermfg':'Black','guibg':'#af87d7','guifg':'Black'},
	\ {'ctermbg':184,'ctermfg':'Black','guibg':'#d7d700','guifg':'Black'},
	\ {'ctermbg': 44,'ctermfg':'Black','guibg':'#00d7d7','guifg':'Black'},
	\ {'ctermbg':211,'ctermfg':'Black','guibg':'#ff87af','guifg':'Black'},
	\ {'ctermbg': 46,'ctermfg':'Black','guibg':'#00ff00','guifg':'Black'},
	\ {'ctermbg':105,'ctermfg':'Black','guibg':'#8787ff','guifg':'Black'},
	\ {'ctermbg':221,'ctermfg':'Black','guibg':'#ffd75f','guifg':'Black'},
	\ {'ctermbg': 86,'ctermfg':'Black','guibg':'#5fffd7','guifg':'Black'},
	\ {'ctermbg':206,'ctermfg':'Black','guibg':'#ff5fd7','guifg':'Black'},
	\ {'ctermbg':155,'ctermfg':'Black','guibg':'#afff5f','guifg':'Black'},
	\ {'ctermbg': 75,'ctermfg':'Black','guibg':'#5fafff','guifg':'Black'},
	\ {'ctermbg':216,'ctermfg':'Black','guibg':'#ffaf87','guifg':'Black'},
	\ {'ctermbg': 41,'ctermfg':'Black','guibg':'#00d75f','guifg':'Black'},
	\ {'ctermbg':177,'ctermfg':'Black','guibg':'#d787ff','guifg':'Black'},
	\ {'ctermbg':148,'ctermfg':'Black','guibg':'#afd700','guifg':'Black'},
	\ {'ctermbg': 38,'ctermfg':'Black','guibg':'#00afd7','guifg':'Black'},
	\ {'ctermbg':174,'ctermfg':'Black','guibg':'#d78787','guifg':'Black'},
	\ {'ctermbg': 83,'ctermfg':'Black','guibg':'#5fff5f','guifg':'Black'},
	\ {'ctermbg':147,'ctermfg':'Black','guibg':'#afafff','guifg':'Black'},
	\ {'ctermbg':178,'ctermfg':'Black','guibg':'#d7af00','guifg':'Black'},
	\ {'ctermbg': 43,'ctermfg':'Black','guibg':'#00d7af','guifg':'Black'},
	\ {'ctermbg':205,'ctermfg':'Black','guibg':'#ff5faf','guifg':'Black'},
	\ {'ctermbg': 82,'ctermfg':'Black','guibg':'#5fff00','guifg':'Black'},
	\ {'ctermbg':153,'ctermfg':'Black','guibg':'#afd7ff','guifg':'Black'},
	\ {'ctermbg':208,'ctermfg':'Black','guibg':'#ff8700','guifg':'Black'},
	\ {'ctermbg': 48,'ctermfg':'Black','guibg':'#00ff87','guifg':'Black'},
	\ {'ctermbg':213,'ctermfg':'Black','guibg':'#ff87ff','guifg':'Black'},
	\ {'ctermbg':112,'ctermfg':'Black','guibg':'#87d700','guifg':'Black'},
	\ {'ctermbg': 39,'ctermfg':'Black','guibg':'#00afff','guifg':'Black'},
	\ {'ctermbg':138,'ctermfg':'Black','guibg':'#af8787','guifg':'Black'},
	\ {'ctermbg': 84,'ctermfg':'Black','guibg':'#5fff87','guifg':'Black'},
	\ {'ctermbg':141,'ctermfg':'Black','guibg':'#af87ff','guifg':'Black'},
	\ {'ctermbg':226,'ctermfg':'Black','guibg':'#ffff00','guifg':'Black'},
	\ {'ctermbg': 51,'ctermfg':'Black','guibg':'#00ffff','guifg':'Black'},
	\ {'ctermbg':218,'ctermfg':'Black','guibg':'#ffafd7','guifg':'Black'},
	\ {'ctermbg':119,'ctermfg':'Black','guibg':'#87ff5f','guifg':'Black'},
	\ {'ctermbg': 69,'ctermfg':'Black','guibg':'#5f87ff','guifg':'Black'},
	\ {'ctermbg':214,'ctermfg':'Black','guibg':'#ffaf00','guifg':'Black'},
	\ {'ctermbg': 49,'ctermfg':'Black','guibg':'#00ffaf','guifg':'Black'},
	\ {'ctermbg':219,'ctermfg':'Black','guibg':'#ffafff','guifg':'Black'},
	\ {'ctermbg':118,'ctermfg':'Black','guibg':'#87ff00','guifg':'Black'},
	\ {'ctermbg':117,'ctermfg':'Black','guibg':'#87d7ff','guifg':'Black'},
	\ {'ctermbg':173,'ctermfg':'Black','guibg':'#d7875f','guifg':'Black'},
	\ {'ctermbg': 47,'ctermfg':'Black','guibg':'#00ff5f','guifg':'Black'},
	\ {'ctermbg':183,'ctermfg':'Black','guibg':'#d7afff','guifg':'Black'},
	\ {'ctermbg':190,'ctermfg':'Black','guibg':'#d7ff00','guifg':'Black'},
	\ {'ctermbg': 45,'ctermfg':'Black','guibg':'#00d7ff','guifg':'Black'},
	\ ]
