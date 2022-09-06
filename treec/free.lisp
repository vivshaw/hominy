(in-package #:burke/treec)

;;;; FIXME: Code duplication
;;;; Also this is all pretty inefficient.

;;; Return a list of lvars free in NODE.
(defgeneric free (node))

;; OPERATIVE and LETN have FREE as a slot reader.
(defmethod free ((link link)) nil)
(defmethod free ((ref ref)) (list (ref-symbol ref)))
(defmethod free ((const const)) nil)
(defmethod free ((combination combination))
  (union (free (combiner combination))
         (union (free (combinand combination)) (free (env combination)))))
(defmethod free ((node listn))
  (reduce #'union (elements node) :key #'free :initial-value ()))
(defmethod free ((node unwrap)) (free (applicative node)))
(defmethod free ((seq seq))
  (union (free (final seq))
         (reduce #'union (for-effect seq) :key #'free :initial-value ())))
(defmethod free ((ifn ifn))
  (union (free (if-cond ifn)) (union (free (then ifn)) (free (else ifn)))))

(defgeneric enclosed-sets (node))
(defmethod enclosed-sets ((link link)) nil)
(defmethod enclosed-sets ((ref ref)) nil)
(defmethod enclosed-sets ((const const)) nil)
(defmethod enclosed-sets ((setn setn)) nil) ; not enclosed
(defmethod enclosed-sets ((combination combination))
  (union (enclosed-sets (combiner combination))
         (union (enclosed-sets (combinand combination))
                (enclosed-sets (env combination)))))
(defmethod enclosed-sets ((listn listn))
  (reduce #'union (elements listn) :key #'enclosed-sets :initial-value ()))
(defmethod enclosed-sets ((unwrap unwrap)) (enclosed-sets (applicative unwrap)))
(defmethod enclosed-sets ((seq seq))
  (union (enclosed-sets (final seq))
         (reduce #'union (for-effect seq) :key #'enclosed-sets :initial-value ())))
(defmethod enclosed-sets ((ifn ifn))
  (union (enclosed-sets (if-cond ifn))
         (union (enclosed-sets (then ifn)) (enclosed-sets (else ifn)))))
(defmethod enclosed-sets ((letn letn))
  (union
   ;; Stuff that's enclosed-sets in the body but also bound here is irrelevant.
   ;; (The LETN will check the enclosed-sets of its body, not itself.)
   (set-difference (enclosed-sets (body letn))
                   (reduce #'append (ptrees letn) :key #'ptree-symbols))
   (reduce #'union (value-nodes letn) :key #'enclosed-sets :initial-value ())))
(defmethod enclosed-sets ((op operative))
  (intersection (free op) (sets (body op))))

(defgeneric sets (node))
(defmethod sets ((link link)) nil)
(defmethod sets ((ref ref)) nil)
(defmethod sets ((const const)) nil)
(defmethod sets ((setn setn)) (ptree-symbols (ptree setn)))
(defmethod sets ((combination combination))
  (union (sets (combiner combination))
         (union (sets (combinand combination)) (sets (env combination)))))
(defmethod sets ((listn listn))
  (reduce #'union (elements listn) :key #'sets :initial-value ()))
(defmethod sets ((unwrap unwrap)) (sets (applicative unwrap)))
(defmethod sets ((seq seq))
  (union (sets (final seq))
         (reduce #'union (for-effect seq) :key #'sets :initial-value ())))
(defmethod sets ((ifn ifn))
  (union (sets (if-cond ifn)) (union (sets (then ifn)) (sets (else ifn)))))
(defmethod sets ((letn letn))
  (union
   (set-difference (sets (body letn))
                   (reduce #'append (ptrees letn) :key #'ptree-symbols))
   (reduce #'union (value-nodes letn) :key #'sets :initial-value ())))
(defmethod sets ((op operative))
  (set-difference (sets (body op)) (ptree-symbols (cons (eparam op) (ptree op)))))
