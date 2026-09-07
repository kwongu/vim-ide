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
