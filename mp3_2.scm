#lang eopl
(require trace/calltrace-lib)
;=================================Spec&Grammar=====================================
(define q1-spec
  '((whitespace (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier (letter (arbno (or letter digit))) symbol)
    (number (digit (arbno digit)) number)
    (arith-op ((or (or "-" "+") (or "*" "/"))) symbol)
    (compare-op ((or ">" "<")) symbol)
    ))

(define q1-grammar
  '((expression (number) num-exp)
    (expression (identifier) var-exp)
    (expression ("let" (arbno identifier "=" expression) "in" expression) let-exp) 
    (expression ("letrec" (arbno identifier "=" expression) "in" expression) letrec-exp)
    (expression ("proc" "(" (arbno identifier) ")" expression) proc-exp)
    (expression ( "(" expression (arbno expression) ")") exp-exp)
    (expression ("newref" "(" expression ")") newRef-exp)
    (expression ("set" identifier expression)set-exp)
    (expression ("begin" expression (arbno ";" expression) "end")begin-exp)
    (expression ("if" expression "then" expression "else" expression)if-exp)
    (expression (arith-op "(" expression (arbno "," expression) ")")arith-exp)
    (expression (compare-op "(" expression "," expression ")") compare-exp)
    (expression ("=" "(" expression "," expression ")") compare-equ-exp)
    (expression ("true") true-exp)
    (expression ("false") false-exp)
    (expression ("undefined") undefined-exp)
    ))

;;;;;;;;;;;;;;;; sllgen boilerplate ;;;;;;;;;;;;;;;;
(sllgen:make-define-datatypes q1-spec q1-grammar)

(define scan&parse
  (sllgen:make-string-parser q1-spec q1-grammar))

;=================================Interpreter=====================================
(define-datatype expval expval?
  (num-val
   (value number?))
  (bool-val
   (boolean boolean?))
  (proc-val
   (proc proc?))
  (ref-val
   (ref reference?)))

(define-datatype proc proc?
    (procedure
      (bvar list?)
      (body expression?)
      ))
  
(define-datatype environment environment?
  (empty-env)
  (extend-env 
   (bvar symbol?)
   (bval expval?)
   (next-env environment?))
  (extend-env-rec*
   (proc-names list?)
   (proc-vars list?)
   (proc-bodies expression?)
   (next-env environment?)))


(define apply-env
  (lambda (search-sym env)
    (cases environment env
      (empty-env ()
                 (undefined-exp ))
      (extend-env (bvar bval next-env)
                  (if (eqv? search-sym bvar)
                      bval
                      (apply-env  search-sym next-env)))
      (extend-env-rec* (procedureNamelist procedureVarList procedureBodyList next-env)
                       (cond 
                         ((location search-sym procedureNamelist)
                          => (lambda (n)
                               (proc-val
                                (procedure 
                                 (list-ref procedureVarList n)
                                 (list-ref procedureBodyList n)
                                 env))))
                         (else (apply-env search-sym  next-env)))))))

;return location(index) of procedure
(define location
    (lambda (sym syms)
      (cond
        ((null? syms) #f)
        ((eqv? sym (car syms)) 0)
        ((location sym (cdr syms))
         => (lambda (n) 
              (+ n 1)))
        (else #f))))


;======================Allocate stack in the-store=======================
(define the-store 'uninitialized)

  ;; empty-store : () -> Sto
  ;; Page: 111
  (define empty-store
    (lambda () '()))
  
  ;; initialize-store! : () -> Sto
  ;; usage: (initialize-store!) sets the-store to the empty-store
  ;; Page 111
  (define initialize-store!
    (lambda ()
      (set! the-store (empty-store))))

  ;; get-store : () -> Sto
  ;; Page: 111
  ;; This is obsolete.  Replaced by get-store-as-list below
  (define get-store
    (lambda () the-store))

  ;; reference? : SchemeVal -> Bool
  ;; Page: 111
  (define reference?
    (lambda (v)
      (integer? v)))

  ;; newref : ExpVal -> Ref
  ;; Page: 111
  (define newref
    (lambda (val)
      (let ((next-ref (length the-store)))
        (set! the-store
              (append the-store (list val)))                     
        next-ref)))                     

  ;; deref : Ref -> ExpVal
  ;; Page 111
  (define deref 
    (lambda (ref)
      (list-ref the-store ref)))

  ;; setref! : Ref * ExpVal -> Unspecified
  ;; Page: 112
  (define setref!                       
    (lambda (ref val)
      (set! the-store
        (letrec
          ((setref-inner
             ;; returns a list like store1, except that position ref1
             ;; contains val. 
             (lambda (store1 ref1)
               (cond
                 ((null? store1)
                  (report-invalid-reference ref the-store))
                 ((zero? ref1)
                  (cons val (cdr store1)))
                 (else
                   (cons
                     (car store1)
                     (setref-inner
                       (cdr store1) (- ref1 1))))))))
          (setref-inner the-store ref)))))

(define report-invalid-reference
    (lambda (ref the-store)
      (eopl:error 'setref
        "illegal reference ~s in store ~s"
        ref the-store)))

  ;; get-store-as-list : () -> Listof(List(Ref,Expval))
  ;; Exports the current state of the store as a scheme list.
  ;; (get-store-as-list '(foo bar baz)) = ((0 foo)(1 bar) (2 baz))
  ;;   where foo, bar, and baz are expvals.
  ;; If the store were represented in a different way, this would be
  ;; replaced by something cleverer.
  ;; Replaces get-store (p. 111)
   (define get-store-as-list
     (lambda ()
       (letrec
         ((inner-loop
            ;; convert sto to list as if its car was location n
            (lambda (sto n)
              (if (null? sto)
                '()
                (cons
                  (list n (car sto))
                  (inner-loop (cdr sto) (+ n 1)))))))
         (inner-loop the-store 0))))

(define expval->num
    (lambda (v)
      (cases expval v
	(num-val (num) num)
	(else (expval-extractor-error 'num v)))))

  (define expval->bool
    (lambda (v)
      (cases expval v
	(bool-val (bool) bool)
	(else (undefined-exp)))))

  (define expval->proc
    (lambda (v)
      (cases expval v
	(proc-val (proc) proc)
	(else (expval-extractor-error 'proc v)))))

  (define expval->ref
    (lambda (v)
      (cases expval v
	(ref-val (ref) ref)
	(else (expval-extractor-error 'reference v)))))

  (define expval-extractor-error
    (lambda (variant value)
      (eopl:error 'expval-extractors "Looking for a ~s, found ~s"
	variant value)))


;=====================================Value-of========================================
(define value-of
  (lambda (exp env)
    (cond
      [(number? exp) exp]
      ;[(symbol? exp) (value-of (var-exp exp) env)]
      [(expression? exp)
       ;(display "This is debug for value-of expression")
       (cases expression exp
         (num-exp (number) (num-val number))
         (var-exp (var) (apply-env var env))
         (true-exp () (bool-val #t))
         (false-exp () (bool-val #f))
         (undefined-exp () exp)
         (let-exp (var-list exp1-list exp2) (value-of-let var-list exp1-list exp2 env))
         (letrec-exp (var-list exp1-list body)(value-of-letrec var-list exp1-list body env) )
         (proc-exp(var-list exp) (proc-val (procedure var-list exp)))
         (exp-exp(rator rand-list) (value-of-exp rator rand-list env))
         (newRef-exp (exp) (ref-val (newref (value-of exp env))))
         (set-exp (var value) (value-of-set var value env))
         (begin-exp (exp1 exp2-list) (value-of-begin exp1 exp2-list env))
         (if-exp(exp1 exp2 exp3) (value-of-if exp1 exp2 exp3 env))
         (arith-exp(arith-op exp1 exp2) (value-of-arith-exp arith-op exp1 exp2 env))
         (compare-exp(compare-op exp1 exp2) (value-of-compare-exp compare-op exp1 exp2 env))
         (compare-equ-exp(exp1 exp2)(value-of-compare-exp '= exp1 exp2 env))
         (else exp))]
      [(expval? exp)
       (cases expval exp
         (ref-val(ref) exp);(deref ref))
         (else exp))])))
  

(define value-of-letrec
  (lambda(funtionNamesList exp-list body env)
    (value-of body
              (extend-env-rec*))))




(define value-of-set
  (lambda (var value env)
    (cond
      [(expval?(apply-env var env))
       (cases expval (apply-env var env)
         (ref-val(ref)(setref! ref (value-of value env)))
         (else '33))]
      [else (undefined-exp)])))




(define value-of-arith-exp
  (lambda (arith-op exp1 exp2-list env)
    (if (null? exp2-list)
        (value-of exp1 env)
        (cond
          [(equal? arith-op '+) (value-of-arith-exp arith-op (num-exp (+ (expval->num (autoDerefIfNeed (value-of exp1 env))) (expval->num (autoDerefIfNeed (value-of (car exp2-list) env))))) (cdr exp2-list) env)]
          [(equal? arith-op '-) (value-of-arith-exp arith-op (num-exp (- (expval->num (autoDerefIfNeed (value-of exp1 env))) (expval->num (autoDerefIfNeed (value-of (car exp2-list) env))))) (cdr exp2-list) env)]
          [(equal? arith-op '*) (value-of-arith-exp arith-op (num-exp (* (expval->num (autoDerefIfNeed (value-of exp1 env))) (expval->num (autoDerefIfNeed (value-of (car exp2-list) env))))) (cdr exp2-list) env)]
          [(equal? arith-op '/) (value-of-arith-exp arith-op (num-exp (/ (expval->num (autoDerefIfNeed (value-of exp1 env))) (expval->num (autoDerefIfNeed (value-of (car exp2-list) env))))) (cdr exp2-list) env)]
          [else display "no match"]))))

(define value-of-compare-exp
  (lambda (compare-op exp1 exp2 env)
    (cond
      [(equal? compare-op '<) (bool-val (< (expval->num (autoDerefIfNeed (value-of exp1 env))) (expval->num (autoDerefIfNeed (value-of exp2 env)))))]
      [(equal? compare-op '=) (bool-val (= (expval->num (autoDerefIfNeed (value-of exp1 env))) (expval->num (autoDerefIfNeed (value-of exp2 env)))))]
      [(equal? compare-op '>) (bool-val (> (expval->num (autoDerefIfNeed (value-of exp1 env))) (expval->num (autoDerefIfNeed (value-of exp2 env)))))])))

(define autoDerefIfNeed
  (lambda (exp)
    (cases expval exp
      (ref-val(ref) (deref ref))
      (else exp))))

(define value-of-let
  (lambda (var-list exp1-list exp2 env)
     (value-of exp2 (add-env var-list exp1-list env))))

(define value-of-exp
  (lambda (rator rand-list env)
    (let ((proc (expval->proc (autoDerefIfNeed (value-of rator env))))
          (arg (value-of-arg rand-list env)))
      (apply-procedure proc arg env))))
       
(define value-of-arg
  (lambda (arg-list env)
    (if (null? (cdr arg-list))
        (list (value-of (car arg-list) env))
        (append (list (value-of (car arg-list) env)) (value-of-arg (cdr arg-list) env)))))

(define value-of-begin
  (lambda (exp1 exps env)
    (letrec
        ((value-of-begins
          (lambda (e1 es)
            ;(display "Debug inside value-of-begins e1 es value-of-e1")
            ;(display e1)
            ;(display es)
            ;(value-of e1 env)
            (let ([v1 (value-of e1 env)])
              (if (null? es)
                  (autoDerefIfNeed v1)
                  ;v1
                  (value-of-begins (car es) (cdr es)))))))
      (value-of-begins exp1 exps))))

(define add-env
  (lambda (var-list exp1-list env)
            (display (value-of (car exp1-list) env) )
    (if (null? (cdr var-list))

        (if (expval? (value-of (car exp1-list) env))
            (extend-env (car var-list) (value-of (car exp1-list) env) env)
            env)
        (cond
          [(expval?(value-of (car exp1-list) env))  (extend-env (car var-list) (value-of (car exp1-list) env) (add-env (cdr var-list) (cdr exp1-list) env))]
          [else (add-env (cdr var-list) (cdr exp1-list) env)]))))

;;SEE Lecture 7 slide p57
(define value-of-if
  (lambda (exp1 exp2 exp3 env)
    (let ([val1 (value-of exp1 env)])
      (cond
        [(expval? (expval->bool val1))
            (if (expval->bool val1)
                (value-of exp2 env)
                (value-of exp3 env))]
        [else (undefined-exp)]))))

(define apply-procedure
  (lambda (proc1 arg env)
    (cases proc proc1
      (procedure (var body)
                 (let ((r arg))
                   (let ((new-env (add-env var r env)))
                     (value-of body new-env)))))))

(define add-env-proc
  (lambda (var-list exp1-list env)
    (if (null? (cdr var-list))
        (cond 
          [(expression? (car exp1-list)) 
           (extend-env (car var-list) (autoDerefIfNeed (value-of (car exp1-list) env)) env)]
          [else (extend-env (car var-list) (value-of (car exp1-list) env) env)])
        (cond 
          [(expression? (car exp1-list)) 
           (extend-env (car var-list) (autoDerefIfNeed (value-of (car exp1-list) env)) (add-env (cdr var-list) (cdr exp1-list) env))]
          [else (extend-env (car var-list) (value-of (car exp1-list) env) (add-env (cdr var-list) (cdr exp1-list) env))]))))

(define derefArg
  (lambda (arg-list env)
    (if (null? (cdr arg-list))
        (list (autoDerefIfNeed (value-of (car arg-list) env)))
        (append (list (autoDerefIfNeed (value-of (car arg-list) env))) (derefArg (cdr arg-list)env)))))


;==============================Wrap Func=================================
(define static-interpreter
  (lambda (exp)
    (initialize-store!)
    (let ([result (value-of (scan&parse exp) (empty-env))])
      (cond 
        [(expval? result)
         (cases expval result
           (ref-val(ref) (expval->num (deref ref)))
           (num-val(value) value)
           (bool-val(bool) 
                    (if bool
                        'true
                        'false))
           (proc-val(proc)  proc))]
        [(expression? result)
         (cases expression result
           (undefined-exp() 'undefined)
           (else result))]))))
        

;=====================================Test========================================
(trace static-interpreter)
(trace value-of)
(trace value-of-let)
(trace value-of-arith-exp)
(trace value-of-begin)
(trace newref)
(trace setref!)
(trace add-env)
(trace apply-env)
(trace scan&parse)
(trace value-of-set)
(trace value-of-exp)
(trace apply-procedure)
(trace autoDerefIfNeed)
(trace value-of-arg)
(trace expval->ref)
(trace derefArg)
(trace add-env-proc)
(trace value-of-if)
(trace value-of-compare-exp)

;(trace the-store)
;(display (scan&parse ">(3,+(1,2))"))
;(display (scan&parse "let x = 1 in let f = proc (y) +(x, y) in let x = 2 in (f 5)"))
;(display (scan&parse "let x = 1 in let f = proc (y) +(x, y) in let x = 2 in (f 5)"))
;(display (scan&parse "letrec ill = proc (x) (ill x) in let f = proc (y) 5 in (f (ill 2))"))

;(static-interpreter "let x = newref(1) in begin set x 2;x end")
;(static-interpreter "let x = let y = newref(1) in begin set y 2;y end in x")
;(static-interpreter "let x = newref(1) in let f= proc (y) set y 2 in begin (f x); x end")
;(static-interpreter "let f=proc(x y) +(x,y) g=proc(x y z) +(x,y,z) in (f (g 1 2 3)1)")
;(static-interpreter "let f = proc(x) proc(y) +(x,y) in let g= proc(x)proc(y)proc(z) +(x,y,z) in ((f (((g 1)2)3))1)")
;(static-interpreter "let f = newref (proc (x y) +(x,y)) in begin set f proc (x y) -(x,y); (f 5 1) end")
;(static-interpreter "newref(1)")
;(static-interpreter "let x = newref(1) g = proc(x) begin set x 5;x end h = proc(x) begin set x +(x,7); x end f = proc(x y) +(x,y) in (f (h x) (g x))")
;(static-interpreter "let x = newref(1) g = proc(x) begin set x 5;x end h = proc(x) begin set x +(x,7); x end f = proc(x y) +(x,y) in (f (g x) (h x))")
;(static-interpreter "let x = let inc = proc (x) +(1,x) in inc in (x 5)")
;(static-interpreter "let f = let inc = proc (x) +(1,x) in inc in (f 5)")
;(static-interpreter "let g = let counter = newref(0) in proc(dummy) begin set counter +(counter,1);counter end in let a = (g 11) in let b = (g 11) in -(a,b)")
;(static-interpreter"x")
;(static-interpreter "if 5 then 0 else 1")
;(static-interpreter "let x = undefined in x")
;(static-interpreter "let x = let y = set x 1 in y in x")
(static-interpreter "let x = 1 in let f = proc (y) +(x, y) in let x = 2 in (f 5)")

;(static-interpreter "let x = newref(1) in = (x, 1)")
;(static-interpreter "letrec factorial = proc (x) if =(x,0) then 1 else *(x, (factorial -(x,1))) in (factorial 5)")
;(static-interpreter "letrec x = 1 x = +(x,2) in x")