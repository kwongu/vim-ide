; vim-ide-mouse-v1.ahk - 같은 것, AutoHotkey v1 용
;
; v1 과 v2 는 문법이 달라서 서로의 스크립트를 못 돌린다. 이미 v1 이 깔려
; 있다면 이 파일을, 새로 받는다면 v2 와 vim-ide-mouse.ahk 를 쓴다.
; 설명은 vim-ide-mouse.ahk 에 있다.

#SingleInstance Force

XButton1::SendInput !{Left}    ; 옆 버튼 1 (뒤로)  -> Alt+Left
XButton2::SendInput !{Right}   ; 옆 버튼 2 (앞으로) -> Alt+Right
