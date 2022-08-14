(defpackage #:burke/quickc
  (:use #:cl)
  (:shadow #:compile #:tailp)
  (:local-nicknames (#:i #:burke/interpreter)
                    (#:o #:burke/vm/ops)
                    (#:vm #:burke/vm)
                    (#:asm #:burke/vm/asm))
  (:export #:compile #:empty-cenv))

(in-package #:burke/quickc)

;;; Info about a value known at compile time.
(defclass info () ())

(defgeneric info-type (info))

(defclass ginfo (info) ; generic info
  (;; TODO: Type objects
   (%type :initform t :initarg :type :reader info-type)))

(defclass local-operative-info (info)
  ((%cfunction :initarg :cfunction :reader cfunction)
   (%ret-info :initarg :ret :reader ret-info :type info)))

(defmethod info-type ((info local-operative-info))
  ;; I'm just making up these types as I go along.
  `(operative * * ,(info-type (ret-info info))))

(defclass applicative-info (info)
  ((%underlying :initarg :underlying :reader underlying)))

(defmethod info-type ((info applicative-info))
  `(applicative ,(info-type (underlying info))))

(defclass constant-info (info)
  ((%value :initarg :value :reader value)))

(defmethod info-type ((info constant-info))
  ;; Probably don't actually want eql types in this compiler.
  `(eql ,(value info)))

(defun applicative-type-p (type) (and (consp type) (eq (first type) 'applicative)))
(defun applicative-type-underlying (type) (second type))
(defun operative-type-p (type) (and (consp type) (eq (first type) 'operative)))

;;; Info about a variable binding.
(defclass binding ()
  ((%type :initarg :type :initform t :reader binding-type)))

;;; A locally bound variable.
(defclass local-binding (binding)
  (;; Register assignment.
   (%index :initarg :index :reader index)))

(defclass cenvironment ()
  (;; A list of CENVIRONMENTs.
   (%parents :initarg :parents :reader parents :type list)
   ;; An alist (symbol . binding)
   (%bindings :initarg :bindings :reader bindings :type list)
   ;; A boolean indicating whether this environment may have additional, unknown bindings.
   ;; Note that this does not include any parent environments, i.e. a complete
   ;; cenvironment may have incomplete ancestors.
   (%completep :initarg :completep :initform t :reader completep :type boolean)))

(defun empty-cenv ()
  (make-instance 'cenvironment :parents nil :bindings nil))

;;; Do a simple augmentation - complete, only one parent.
(defun augment1 (parent bindings)
  (if (null bindings)
      parent
      (make-instance 'cenvironment
        :parents (list parent) :completep t :bindings bindings)))

(defun lookup (symbol cenv)
  ;; FIXME: Parents
  (let ((pair (assoc symbol (bindings cenv))))
    (if pair (cdr pair) pair)))

;;; Represents information about something that has just been compiled.
;;; Name kinda sucks.
(defclass result ()
  ((%info :initarg :info :reader info)
   ;; How many locals it binds.
   (%nlocals :initarg :nlocals :reader nlocals :type (and unsigned-byte fixnum))
   ;; How much stack space it needs.
   (%nstack :initarg :nstack :reader nstack :type (and unsigned-byte fixnum))))

(defun result (info nlocals nstack)
  (make-instance 'result :info info :nlocals nlocals :nstack nstack))

(defclass context ()
  ((%cfunction :initarg :cfunction :reader cfunction :type asm:cfunction)
   ;; Are we expected to produce a value? This is important for making sure that
   ;; the stack is in the same state after either branch of an $if, for example.
   (%valuep :initform t :initarg :valuep :reader valuep :type boolean)
   ;; Tail context? Note that (not valuep) implies (not tailp).
   (%tailp :initform t :initarg :tailp :reader tailp :type boolean)
   ;; Local index bound to the current environment.
   (%env-index :initarg :env-index :reader env-index :type (and unsigned-byte fixnum))
   ;; Next index to use if we need to bind.
   (%nlocals :initarg :nlocals :reader nlocals :type (and unsigned-byte fixnum))))

(defun context (context &key (valuep (valuep context))
                          (tailp (if valuep (tailp context) nil))
                          (new-locals 0))
  (make-instance 'context
    :cfunction (cfunction context) :tailp tailp :valuep valuep
    :nlocals (+ (nlocals context) new-locals) :env-index (env-index context)))

(defun assemble (context &rest items)
  (apply #'asm:assemble (cfunction context) items))

(defun constant-index (value context)
  (asm:constant-index value (asm:cmodule (cfunction context))))

(defun compile (plist eparam body cenvironment environment)
  (let* ((result (compile-operative plist eparam body cenvironment
                                    (make-instance 'asm:cmodule)))
         (code (asm:link (cfunction (info result)))))
    (vm:enclose code (vector environment))))

(defun linearize-plist (plist)
  (etypecase plist
    ((or null i:ignore) nil)
    (symbol (list plist))
    (cons (append (linearize-plist (car plist)) (linearize-plist (cdr plist))))))

(defun compile-operative (plist eparam body cenv module)
  (let* ((cf (make-instance 'asm:cfunction
               :cmodule module :plist plist :eparam eparam))
         (cenv (if (symbolp eparam)
                   (augment1 cenv
                             (list (cons eparam (make-instance 'local-binding :index 1))))
                   cenv)))
    (multiple-value-bind (bindings context nlocals nstack) (gen-plist cf plist)
      (setf (asm:sep cf) (asm:nbytes (cfunction context)))
      ;; Set up the current environment to be in index 2.
      ;; We assume the closed over environment is in closure 0.
      (assemble context 'o:closure 0)
      (let* ((estack
               (cond ((and (typep plist '(or null i:ignore))
                           (typep eparam 'i:ignore))
                      (assemble context 'o:set 2)
                      1)
                     ((and (typep plist '(and symbol (not null))) (symbolp eparam))
                      (assemble context 'o:ref 0 'o:ref 1
                        'o:make-environment (constant-index (list plist eparam) context))
                      3)
                     ((and (typep plist '(and symbol (not null))) (typep eparam 'i:ignore))
                      (assemble context 'o:ref 0
                        'o:make-environment (constant-index (list plist) context))
                      2)
                     ((symbolp eparam)
                      (assemble context 'o:ref 1)
                      (let* ((lin (linearize-plist plist))
                             (llin (length lin)))
                        (loop repeat llin
                              for i from 3
                              do (assemble context 'o:ref i))
                        (assemble context 'o:make-environment
                          (constant-index (list* eparam (linearize-plist lin)) context)
                          'o:set 2)
                        (+ 2 llin)))
                     (t
                      (let* ((lin (linearize-plist plist))
                             (llin (length lin)))
                        (loop repeat llin
                              for i from 3
                              do (assemble context 'o:ref i))
                        (assemble context 'o:make-environment (constant-index lin context)
                          'o:set 2)
                        (+ 1 llin)))))
             ;; Compile the body.
             (body (compile-seq body (augment1 cenv bindings) context))
             (info (make-instance 'local-operative-info
                     :cfunction cf :ret (info body)))
             (nlocals (+ 2 nlocals (nlocals body)))
             (nstack (max nstack estack (nstack body))))
        (setf (asm:nlocals cf) nlocals (asm:nstack cf) nstack)
        (result info 0 0)))))

;;; Generate code to do argument parsing.
;;; Return four values:
;;; A list of bindings. A context. And the amounts of registers and stack used.
(defun gen-plist (cfunction plist)
  (let* ((context
          (make-instance 'context
            :cfunction cfunction :env-index 2 :nlocals 3)))
    (etypecase plist
      (null
       (assemble context 'o:ref 0 'o:err-if-not-null)
       (values nil context 0 1))
      (symbol
       ;; Just use index 0 and don't bind anything.
       (values (list (cons plist (make-instance 'local-binding :index 0)))
               context 0 0))
      (i:ignore (values nil context 0 0))
      (cons ; this is the hard part.
       (let* ((vars (linearize-plist plist))
              (nvars (length vars))
              (context (context context :new-locals nvars))
              (next-var-local 3))
         (labels ((next-var-local () (prog1 next-var-local (incf next-var-local)))
                  (aux (plist next-temp-local)
                    (etypecase plist
                      (i:ignore (values nil 0))
                      (null (assemble context 'o:err-if-not-null) (values nil 0))
                      (symbol
                       (let ((l (next-var-local)))
                         (assemble context 'o:set l)
                         (values (list (cons plist (make-instance 'local-binding :index l)))
                                 0)))
                      (cons
                       (let ((cons-local next-temp-local))
                         (assemble context 'o:set cons-local
                           'o:ref cons-local 'o:err-if-not-cons
                           'o:ref cons-local 'o:car)
                         (multiple-value-bind (car-locals car-temps)
                             (aux (car plist) (1+ next-temp-local))
                           (assemble context 'o:ref cons-local 'o:cdr)
                           (multiple-value-bind (cdr-locals cdr-temps)
                               ;; We can just stomp on any temporaries the
                               ;; car plist made, and on the cons now that we
                               ;; don't need to do anything else with it.
                               (aux (cdr plist) next-temp-local)
                             (values (append car-locals cdr-locals)
                                     (max (1+ car-temps) cdr-temps)))))))))
           (assemble context 'o:ref 0)
           (multiple-value-bind (bindings ntemps) (aux plist (+ 3 nvars))
             (values bindings context (+ 3 ntemps) 1))))))))

(defun compile-seq (body cenv context)
  (cond ((null body) (compile-constant i:inert context))
        ((null (cdr body)) (compile-form (car body) cenv context))
        (t
         (let ((nlocals 0) (nstack 0))
           (loop with context = (context context :valuep nil)
                 for form in (butlast body)
                 for result = (compile-form form cenv context)
                 do (setf nlocals (max nlocals (nlocals result))
                          nstack (max nstack (nstack result))))
           (let ((final (compile-form (first (last body)) cenv context)))
             (setf nlocals (max nlocals (nlocals final))
                   nstack (max nstack (nstack final)))
             (result (info final) nlocals nstack))))))

(defun compile-constant (value context)
  (cond ((valuep context)
         (assemble context 'o:const (constant-index value context))
         (when (tailp context) (assemble context 'o:return))
         (result (make-instance 'constant-info :value value) 0 1))
        (t (result (make-instance 'constant-info :value value) 0 0))))

(defun compile-form (form cenv context)
  (typecase form
    (symbol (compile-symbol form cenv context))
    (cons (compile-cons (car form) (cdr form) cenv context))
    (t (compile-constant form context))))

(defun compile-symbol (symbol cenv context)
  (let ((binding (lookup symbol cenv)))
    (etypecase binding
      (local-binding
       (cond ((valuep context)
              (assemble context 'o:ref (index binding))
              (when (tailp context) (assemble context 'o:return))
              (result (make-instance 'ginfo :type (binding-type binding)) 0 1))
             (t (result (make-instance 'ginfo :type (binding-type binding)) 0 0)))))))

(defun compile-cons (combinerf combinand cenv context)
  (let* ((combinerr (compile-form combinerf cenv (context context :valuep t :tailp nil)))
         #+(or)
         (combinert (info-type (info combinerr)))
         (nlocals (nlocals combinerr)) (nstack (nstack combinerr)))
    ;; Generic. FIXME
    (let ((res (compile-constant combinand (context context :valuep t :tailp nil))))
      (assemble context 'o:ref (env-index context))
      (cond ((tailp context)
             (assemble context 'o:tail-combine)
             (result (make-instance 'ginfo)
                     (max nlocals (nlocals res)) (max nstack (nstack res) 1)))
            ((valuep context)
             (assemble context 'o:combine)
             (result (make-instance 'ginfo)
                     (max nlocals (nlocals res)) (max nstack (nstack res) 1)))
            (t
             (assemble context 'o:combine 'o:drop)
             (result (make-instance 'ginfo)
                     (max nlocals (nlocals res)) (max nstack (nstack res) 1)))))))