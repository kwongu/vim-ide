;; extends

;; Source Insight 기본 스타일 흉내: "선언"에 밑줄을 그어 준다.
;; SI 화면에서는 함수 정의의 이름, 파라미터, 지역변수 선언, 구조체 멤버,
;; goto 레이블이 밑줄로 표시되고, 같은 이름을 본문에서 참조할 때는 밑줄이
;; 없다. 색은 본문과 같은 검정이고 밑줄만 다르다.
;;
;; 패턴은 nvim-treesitter 의 queries/c/locals.scm 과 같은 모양을 쓴다:
;; 안쪽 선언자만 잡으면 pointer/array/init 조합이 모두 덮인다.
;; 밑줄이 싫으면 이 파일을 지우거나 :highlight link @si.declaration NONE.

;; 함수와 매크로: 이름 자체가 선언 (SI 는 굵게 + 밑줄)
(function_declarator
  declarator: (identifier) @si.declaration.function)

(preproc_def
  name: (identifier) @si.declaration.function)

(preproc_function_def
  name: (identifier) @si.declaration.function)

;; 변수/파라미터/멤버 선언
;; 파라미터: SI 팩토리 기본 스타일셋에서 밑줄이 붙는 것은 여기(와 레이블)뿐
;; 이라서 따로 잡아 둔다. 화면 기준 배색에서는 나머지 선언과 같이 취급한다.
(parameter_declaration
  declarator: (identifier) @si.declaration.parameter)

;; #define arpc_dbg(fmt, arg) 의 fmt, arg
(preproc_params
  (identifier) @si.declaration.parameter)

(init_declarator
  declarator: (identifier) @si.declaration)

(array_declarator
  declarator: (identifier) @si.declaration)

(pointer_declarator
  declarator: (identifier) @si.declaration)

(declaration
  declarator: (identifier) @si.declaration)

(field_declaration
  declarator: (field_identifier) @si.declaration)

;; struct arpc_device *dev;  /  uint8_t buf[N];  /  int32_t (*done)(void *);
(pointer_declarator
  declarator: (field_identifier) @si.declaration)

(array_declarator
  declarator: (field_identifier) @si.declaration)

(function_declarator
  declarator: (field_identifier) @si.declaration)

;; enum 요소는 그 자리에서 정의된다. 상수 매크로(@constant)와 색을 따로
;; 줘야 해서 전용 캡처를 쓴다.
(enum_specifier
  (enumerator_list
    (enumerator
      name: (identifier) @si.declaration.enumconst)))

;; 타입 이름은 '정의하는 자리'에서만 (본문에서 쓰는 자리는 밑줄 없음)
(type_definition
  declarator: (type_identifier) @si.declaration.function)

;; typedef struct x *handle_t;  /  typedef int (*cb_t)(void);
;; typedef int cb_t(void);      /  typedef int arr_t[4];
(pointer_declarator
  declarator: (type_identifier) @si.declaration.function)

(function_declarator
  declarator: (type_identifier) @si.declaration.function)

(array_declarator
  declarator: (type_identifier) @si.declaration.function)

(struct_specifier
  name: (type_identifier) @si.declaration.function
  body: (field_declaration_list))

(union_specifier
  name: (type_identifier) @si.declaration.function
  body: (field_declaration_list))

(enum_specifier
  name: (type_identifier) @si.declaration.function
  body: (enumerator_list))

;; goto 레이블: 선언하는 자리만 ('goto x' 의 x 는 참조)
(labeled_statement
  (statement_identifier) @si.declaration.function)

;; -- #ifdef/#ifndef/#if defined() 의 조건 이름 ----------------------------
;; nvim-treesitter 는 이 이름을 코드 안의 상수 매크로(GFP_KERNEL 같은)와
;; 똑같이 @constant 로 잡는다. 색을 따로 주고 싶을 때가 있어 전용 캡처를
;; 둔다 (지금은 상수 매크로와 같은 옅은 빨강).
(preproc_ifdef
  name: (identifier) @si.directive.cond)

((preproc_call
  directive: (preproc_directive) @_d
  argument: (preproc_arg) @si.directive.cond)
  (#any-of? @_d "#ifndef" "#ifdef"))

(preproc_defined
  (identifier) @si.directive.cond)

;; -- 커널 주석 매크로 (__iomem, __user, __init, __percpu, ...) ------------
;; C 문법에 없는 토큰이라 'void __iomem *reg' 는 ERROR 노드가 되고, 그 안의
;; __iomem 은 그냥 identifier/field_identifier 로 잡힌다. 구조로는 겨냥할 수
;; 없으니 이름 규칙(__ + 소문자)으로 고른다.
((identifier) @si.kernel.attr
  (#lua-match? @si.kernel.attr "^__%l"))

((field_identifier) @si.kernel.attr
  (#lua-match? @si.kernel.attr "^__%l"))

((type_identifier) @si.kernel.attr
  (#lua-match? @si.kernel.attr "^__%l"))
