;; extends
;;
;; nvim-treesitter 의 queries/cpp/highlights.scm 첫 줄이 '; inherits: c' 이므로
;; after/queries/c/highlights.scm 이 C++ 에도 함께 실린다. 여기에는 C 문법에
;; 없는 C++ 전용 선언 형태만 더한다.

;; int32_t &ref_;  /  auto &r = x;
(reference_declarator
  (identifier) @si.declaration)

(reference_declarator
  (field_identifier) @si.declaration)

;; auto [a, b] = pair;
(structured_binding_declarator
  (identifier) @si.declaration)

;; void f(int x = 0)
(optional_parameter_declaration
  declarator: (identifier) @si.declaration.parameter)

;; template <typename... Ts> void f(Ts... ts)
(variadic_declarator
  (identifier) @si.declaration)

;; int32_t Caller::send(uint32_t len) { ... }  ->  send
(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @si.declaration.function))

(function_declarator
  declarator: (qualified_identifier
    name: (destructor_name) @si.declaration.function))

;; class Caller { ... };  (정의된 자리에서만)
(class_specifier
  name: (type_identifier) @si.declaration.function
  body: (field_declaration_list))

;; using handle_t = Caller *;
(alias_declaration
  name: (type_identifier) @si.declaration.function)

;; namespace arpc { ... }
(namespace_definition
  name: (namespace_identifier) @si.declaration.function)

;; -- c 쪽 규칙을 여기서 한 번 더 적는 이유 ----------------------------------
;; nvim-treesitter 의 cpp 쿼리는 '; inherits: c' 로 c 규칙을 먼저 싣고 그
;; 다음에 자기 규칙을 얹는다. 그래서 순서가
;;   c 기본 → after/queries/c (우리 것) → cpp 기본 → 여기
;; 가 되고, cpp 기본이 잡는 캡처는 우리 c 쪽 규칙을 덮어 버린다. 실제로
;; 헤더(.h 는 기본이 cpp 로 열린다)에서 'char *p' 는 네이비 볼드인데
;; 'int m' 만 검정(@variable.member)으로 남았다. 그 벌만 다시 적는다.

;; 겹 없는 구조체 멤버: int m;
(field_declaration
  (field_identifier) @si.declaration)

;; 헤더 안 inline 함수의 지역변수도 cpp 기본이 덮을 수 있으므로 같이 둔다
(compound_statement
  (declaration
    declarator: (identifier) @si.declaration.local))

(compound_statement
  (declaration
    declarator: (_ declarator: (identifier) @si.declaration.local)))

(compound_statement
  (declaration
    declarator: (_ declarator: (_ declarator: (identifier) @si.declaration.local))))
