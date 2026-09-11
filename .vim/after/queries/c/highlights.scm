;; extends

;; -- 타입 이름을 '쓰는' 자리 ----------------------------------------------
;; uint32_t 같은 stdint 계열도, 프로젝트의 struct/enum/typedef 이름도 모두
;; type_identifier 다. 예약어(int/void/char = primitive_type)와 달리 이들은
;; typedef 이므로 SI 화면에서 심볼 참조 색(초록)으로 나온다.
;; 이 규칙은 파일 맨 앞에 있어야 한다: 아래의 선언 패턴들이 나중에 와서
;; '정의하는 자리'를 다시 덮어야 하기 때문이다(뒤에 온 캡처가 이긴다).
((type_identifier) @si.type.ref)

;; extern / static / inline / register / auto : 타입 앞에 붙는 저장 클래스.
;; nvim-treesitter 는 이것들을 const/volatile(type_qualifier)와 똑같은
;; @keyword.modifier 로 잡는데, SI 화면에서는 타입과 같은 초록으로 나온다.
;; 노드는 다르지만 둘 다 타입 색으로 보낸다.
((storage_class_specifier) @si.type.ref)

;; const / volatile / restrict / _Atomic : 타입 한정자도 타입과 같은 초록.
((type_qualifier) @si.type.ref)

;; int/void/char 같은 내장 타입(primitive_type)은 여기서 따로 잡지 않는다:
;; 컬러스킴이 @type.builtin 자체를 타입 색(초록)으로 칠하기 때문에
;; uint32_t·size_t·bool 도 같은 경로로 초록이 된다.

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

;; goto 레이블: 선언하는 자리 ('goto x' 의 x 는 @label 로 잡힌다).
;; SI 는 레이블을 빨강 볼드 밑줄로 그린다 - 선언 계열과 색이 다르므로
;; 전용 캡처를 쓴다.
(labeled_statement
  (statement_identifier) @si.declaration.label)

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

;; -- '#if 0' 안의 죽은 코드 ----------------------------------------------
;; SI 는 컴파일되지 않는 블록을 회색으로 눌러 보여 준다('Inactive Code').
;; 두 갈래로 잡는다: #else 가 없는 경우와 있는 경우(있으면 #else 지시문
;; 자체와 살아 있는 분기는 건드리지 않는다). 우선순위 105 로 두어 그 안의
;; 주석·문자열 색까지 회색이 이긴다.
(preproc_if
  condition: (number_literal) @_z
  (_) @si.inactive
  !alternative
  (#eq? @_z "0")
  (#set! priority 105))

(preproc_if
  condition: (number_literal) @_z
  (_) @si.inactive
  alternative: (_)
  (#eq? @_z "0")
  (#not-lua-match? @si.inactive "^#el")
  (#set! priority 105))

;; -- goto / default 는 제어 키워드다 -------------------------------------
;; nvim-treesitter 는 이 둘을 평범한 @keyword 로 잡는데, SI 는 제어 키워드
;; (if/for/return...)와 같은 색으로 그린다.
["goto" "default"] @keyword.exception

;; -- 함수 안에서 선언한 지역 변수 -------------------------------------------
;; 파라미터와 같은 파랑으로 칠하려고 따로 뽑는다. 위의 @si.declaration 은
;; 구조체 멤버와 파일 스코프 선언까지 함께 잡으므로 그것을 그대로 물들이면
;; 범위가 너무 넓다. '함수 본문(compound_statement) 안' 이라는 조건을 붙인다.
;; 뒤에 온 캡처가 이기므로 이 블록은 반드시 위 규칙들보다 뒤에 있어야 한다.
;;
;; 세 벌인 이유: int x;  /  int *p = NULL;  /  char buf[8] = {0} 처럼
;; declarator 가 init_declarator·pointer_declarator·array_declarator 로
;; 한두 겹 감싸이기 때문이다. 와일드카드 '_' 로 그 겹을 건너뛴다.
(compound_statement
  (declaration
    declarator: (identifier) @si.declaration.local))

(compound_statement
  (declaration
    declarator: (_ declarator: (identifier) @si.declaration.local)))

(compound_statement
  (declaration
    declarator: (_ declarator: (_ declarator: (identifier) @si.declaration.local))))

;; for (int i = 0; ...) 의 i 는 compound_statement 가 아니라 for_statement 밑이다
(for_statement
  initializer: (declaration
    declarator: (identifier) @si.declaration.local))

(for_statement
  initializer: (declaration
    declarator: (_ declarator: (identifier) @si.declaration.local)))

;; 포인터/배열/함수포인터 파라미터도 파라미터다.
;;   struct packet *p     -> parameter_declaration > pointer_declarator > identifier
;;   char *argv[]         -> ... > array_declarator > pointer_declarator > identifier
;;   int (*cb)(void)      -> ... > function_declarator > parenthesized_declarator
;;                                 > pointer_declarator > identifier
;; 위의 (parameter_declaration declarator: (identifier)) 는 겹이 없는 경우만
;; 잡으므로, 와일드카드 '_' 로 한~세 겹을 건너뛴 벌을 따로 둔다.
(parameter_declaration
  declarator: (_ declarator: (identifier) @si.declaration.parameter))

(parameter_declaration
  declarator: (_ declarator: (_ declarator: (identifier) @si.declaration.parameter)))

(parameter_declaration
  declarator: (_ declarator: (_ declarator: (_ declarator:
    (identifier) @si.declaration.parameter))))

;; int (*cb)(void) : parenthesized_declarator 의 자식은 'declarator:' 필드가
;; 아니라 이름 없는 자식이라 위의 와일드카드 벌이 닿지 않는다. 따로 적는다.
(parameter_declaration
  declarator: (function_declarator
    declarator: (parenthesized_declarator
      (pointer_declarator
        declarator: (identifier) @si.declaration.parameter))))

;; 지역변수로 선언한 함수 포인터도 같은 모양이다: int (*fn)(void) = NULL;
(compound_statement
  (declaration
    declarator: (function_declarator
      declarator: (parenthesized_declarator
        (pointer_declarator
          declarator: (identifier) @si.declaration.local)))))

;; 겹이 없는 구조체 멤버: int m;
;;
;; 위쪽의 (field_declaration declarator: (field_identifier)) 는 걸리지 않는다 -
;; 이 문법에서 field_declaration 바로 밑의 field_identifier 에는 'declarator'
;; 필드 이름이 붙지 않기 때문이다(char *p 처럼 pointer_declarator 를 한 겹
;; 거칠 때만 붙는다). 그래서 필드 이름 없이 잡는다. 이게 없으면 int m; 만
;; nvim 기본 쿼리의 @variable.member(검정)로 남아, 같은 구조체 안에서
;; char *p 는 네이비 볼드인데 int m 은 검정인 엇갈림이 생긴다.
(field_declaration
  (field_identifier) @si.declaration)
