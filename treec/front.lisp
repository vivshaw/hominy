(in-package #:burke/treec)

;;;; Produce IR from source forms.

(defclass local-binding (cenv:binding) ())
(defun make-local-binding () (make-instance 'local-binding))

(defun plist->bindings (plist)
  (labels ((aux (plist)
             (etypecase plist
               ((or null i:ignore) nil)
               (symbol (list (cons plist (make-local-binding))))
               (cons (append (aux (car plist)) (aux (cdr plist)))))))
    (aux plist)))

;;; Return a binding alist for make-cenv.
(defun operative-bindings (plist eparam)
  (let ((binds (plist->bindings plist)))
    (etypecase eparam
      (symbol (list* (cons eparam (make-local-binding)) binds))
      (i:ignore binds))))

(defun convert-operative (plist eparam body cenv)
  (let* ((bindings (operative-bindings plist eparam))
         (cenv (apply #'cenv:make-cenv cenv bindings))
         (env-var (make-symbol "LOCAL-ENVIRONMENT"))
         (bodyn (convert-seq body env-var cenv))
         (free (free bodyn))
         ;; What variables are free in this operative that are not bound by it.
         (really-free
           (if (member env-var free)
               ;; the environment is free, so we need everything
               env-var
               ;; Subtract out variables we bind
               (set-difference free (mapcar #'car bindings)))))
      (make-instance 'operative
        :plist plist :eparam eparam :free really-free
        :body (convert-seq body env-var cenv))))

(defun convert-seq (forms env-var cenv)
  (cond ((null forms) (convert-constant i:inert env-var cenv))
        ((null (cdr forms)) (convert-form (car forms) env-var cenv))
        (t
         (make-seq (mapcar (lambda (f) (convert-form f env-var cenv)) (butlast forms))
                   (convert-form (first (last forms)) env-var cenv)))))

(defun convert-form (form env-var cenv)
  (typecase form
    (symbol (convert-symbol form env-var cenv))
    (cons (convert-cons form env-var cenv))
    (t (convert-constant form env-var cenv))))

(defun convert-constant (value env-var cenv)
  (declare (ignore env-var cenv))
  (make-const value))

(defun convert-symbol (symbol env-var cenv)
  (declare (ignore env-var))
  (let ((binding (cenv:lookup symbol cenv)))
    (etypecase binding
      (local-binding (make-ref symbol (cenv:info binding)))
      (cenv:binding
       ;; If it's not a local binding, it must be "global", i.e. in the static
       ;; environment of whatever operative we are overall compiling.
       ;; This is only true provided we aren't trying to convert forms in any
       ;; remotely exotic environments - e.g. from eval, $remote-eval, etc.
       (make-link symbol (cenv:info binding)))
      (null
       (unless binding (warn "Unknown variable ~a" symbol))
       (make-link symbol)))))

(defun convert-cons (form env-var cenv)
  (let* ((combinern (convert-form (car form) env-var cenv))
         (combineri (info combinern)))
    (etypecase combineri
      (t (make-combination combinern
                           (convert-constant (cdr form) env-var cenv)
                           (make-ref env-var))))))