(in-package #:burke/interpreter)

(defun bindings->namesvec (bindings)
  (coerce (loop for (ptree) in bindings nconc (ptree-names ptree)) 'vector))

(defun fill-values (bindings vec env)
  (loop with start = 0
        for (ptree form) in bindings
        do (setf start (bind-ptree-to-vector ptree (eval form env) vec start))))

(defun exit (&rest values) (throw 'abort values))

;;; Returns a function that, given a combinand passed
;;; to an operative, returns a new augmentation of static-env with everything
;;; in the ptree and eparam bound. It sort of pre "compiles" a ptree.
(defun make-augmenter (static-env ptree eparam)
  (etypecase eparam
    (ignore
     (multiple-value-bind (names augmenter) (ptree-augmenter ptree 0)
       (declare (type (function (t simple-vector)) augmenter))
       (let* ((names-vec (coerce names 'vector))
              (nnames (length names-vec)))
         (lambda (dynamic-env combinand)
           (declare (cl:ignore dynamic-env))
           (let ((vvec (make-array nnames)))
             (funcall augmenter combinand vvec)
             (make-fixed-environment names-vec vvec static-env))))))
    (symbol
     (multiple-value-bind (names augmenter) (ptree-augmenter ptree 1)
       (declare (type (function (t simple-vector)) augmenter))
       (let* ((names-vec (coerce (list* eparam names) 'vector))
              (nnames (length names-vec)))
         (lambda (dynamic-env combinand)
           (let ((vvec (make-array nnames)))
             (setf (svref vvec 0) dynamic-env)
             (funcall augmenter combinand vvec)
             (make-fixed-environment names-vec vvec static-env))))))))

(defun make-derived-operative (static-env ptree eparam body)
  (let ((aug (make-augmenter static-env ptree eparam)))
    (make-instance 'derived-operative
      :ptree ptree :eparam eparam :env static-env :augmenter aug
      ;; Used to do (cons '$sequence body) here, but then $sequence becoming
      ;; rebound would be an issue, so instead the COMBINE method has been
      ;; modified to do a sequence of forms directly.
      :body body)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defenv *ground* ()
  ;; core semantics
  (defapp eval (form env) ignore (eval form env))
  (defapp combine (combiner combinand env) ignore (combine combiner combinand env))
  (defapp lookup (symbol env) ignore (lookup symbol env))
  ;; ignores
  (defpred ignore? ignorep)
  ;; environments
  (defpred environment? environmentp)
  (defapp make-environment (&rest parents) ignore (apply #'make-environment parents))
  (defapp make-fixed-environment (symbols values &rest parents) ignore
    (apply #'make-fixed-environment symbols values parents))
  (defop  $define! (ptree form) env
    (bind-ptree ptree (eval form env)
                (lambda (symbol val state)
                  (declare (cl:ignore state))
                  (define val symbol env))
                nil)
    inert)
  (defop  $set! (ptree form) env
    (bind-ptree ptree (eval form env)
                (lambda (symbol value state)
                  (declare (cl:ignore state))
                  (setf (lookup symbol env) value))
                nil)
    inert)
  ;; operatives
  (defop  $vau (ptree eparam &rest body) static
    (make-derived-operative static ptree eparam body))
  (defpred operative? operativep)
  ;; applicatives
  (defpred applicative? applicativep)
  (defapp wrap (combiner) ignore (wrap combiner))
  (defapp unwrap (applicative) ignore (unwrap applicative))
  ;; lists
  (defapp cons (car cdr) ignore (cons car cdr))
  (defapp car (cons) ignore
    (if (typep cons 'cons)
        (car (the cons cons))
        (error 'type-error :datum cons :expected-type 'cons)))
  (defapp cdr (cons) ignore
    (if (typep cons 'cons)
        (cdr (the cons cons))
        (error 'type-error :datum cons :expected-type 'cons)))
  (defpred cons? consp)
  (defpred null? null)
  ;; symbols
  (defpred symbol? symbolp)
  ;; equivalence
  (defapp eq? (object1 object2) ignore (boolify (eql object1 object2)))
  ;; booleans
  (defop  $if (condition then else) dynenv
    (let ((c (eval condition dynenv)))
      (cond ((eq c true) (eval then dynenv))
            ((eq c false) (eval else dynenv))
            (t (error 'type-error :datum c :expected-type 'boolean)))))
  (defpred boolean? booleanp)
  ;; control
  (defop  $sequence (&rest forms) dynenv (apply #'$sequence dynenv forms))
  (defop  $let (bindings &rest body) env
    (let* ((names (bindings->namesvec bindings))
           (values (make-array (length names)))
           (_ (fill-values bindings values env))
           (new-env (make-fixed-environment names values env)))
      (declare (cl:ignore _))
      (apply #'$sequence new-env body)))
  ;; This has slightly different behavior from Kernel with respect to forms
  ;; that immediately evaluate the newly bound names. In Kernel, doing such will
  ;; get you the outside binding value if there is one, or else error with an
  ;; unbound variable. (This is not stated outright but is the behavior of the
  ;; given derivation.) This here binds everything to #inert. I think the ideal
  ;; would be to signal an error. To do that, either there needs to be a special
  ;; "unbound" marker to put in temporarily, or something like symbol macros.
  ;; I'm inclined towards the latter.
  (defop  $letrec (bindings &rest body) env
    (let* ((names (bindings->namesvec bindings))
           (values (make-array (length names) :initial-element inert))
           (new-env (make-fixed-environment names values env)))
      (bind-ptree (mapcar #'first bindings) (mapcar #'second bindings)
                  (lambda (name form state)
                    (declare (cl:ignore state))
                    (setf (lookup name new-env) (eval form new-env)))
                  nil)
      (apply #'$sequence new-env body)))
  (defapp exit (&rest values) ignore (throw 'abort values)))
