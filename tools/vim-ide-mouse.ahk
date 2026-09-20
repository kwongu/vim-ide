; vim-ide-mouse.ahk - 마우스 옆 버튼(뒤로/앞으로)을 터미널에서 쓰게 한다
;
; 왜 필요한가
;   Windows Terminal, PuTTY, MobaXterm, TeraTerm 은 넷 다 마우스 옆 버튼을
;   읽지 않는다. 그 버튼을 눌러도 터미널이 vim 에게 아무것도 보내지 않아서,
;   vim 쪽 설정으로는 손쓸 방법이 없다 (:JumpKeyTest 를 켜고 눌러도 아무
;   반응이 없는 것이 그 증거다).
;
;   그래서 윈도우에서 그 버튼을 '키'로 바꿔 준다. 바꿀 키는 Alt+화살표다 -
;   브라우저와 탐색기의 뒤로/앞으로가 같은 키라 뜻이 어긋나지 않고,
;   네 터미널 모두 이 키는 그대로 vim 에게 흘려보낸다.
;
;   vim-ide 는 <A-Left>/<A-Right> 를 EDIT 창, RelationView 패널,
;   미리보기 창 셋 다에서 뒤로/앞으로(<C-o>/<C-i>)로 받는다.
;
; 쓰는 법
;   1. https://www.autohotkey.com 에서 AutoHotkey v2 를 받아 설치한다.
;   2. 이 파일을 윈도우 PC 에 복사하고 더블클릭한다.
;      (트레이에 초록색 H 아이콘이 뜨면 돌고 있는 것이다)
;   3. 터미널에서 :JumpKeyTest 를 치고 옆 버튼을 한 번 누른다.
;      '<A-Left>' 라고 나오면 끝이다.
;   4. 부팅할 때마다 켜지게 하려면 이 파일의 바로 가기를
;      Win+R -> shell:startup 폴더에 넣는다.
;
; 창을 가리지 않는 이유
;   터미널일 때만 적용하려면 창 조건을 다는데, 실행 파일 이름이 제각각이라
;   (MobaXterm 은 MobaXterm_Personal_24.2.exe 처럼 버전이 붙는다) 조건이
;   조용히 안 맞는 일이 잦다. Alt+화살표는 다른 프로그램에서도 뒤로/앞으로라
;   전역으로 두어도 손해가 없다.
;
; 이게 싫으면
;   마우스 제조사 유틸리티(로지텍 Options+ 등)에서 옆 버튼을 Alt+Left /
;   Alt+Right 에 묶어도 똑같다. 그러면 이 파일도, AutoHotkey 도 필요 없다.

#Requires AutoHotkey v2.0
#SingleInstance Force

XButton1::Send("!{Left}")    ; 옆 버튼 1 (뒤로)  -> Alt+Left
XButton2::Send("!{Right}")   ; 옆 버튼 2 (앞으로) -> Alt+Right
