(defpackage #:burke/treec
  (:use #:cl)
  (:shadow #:compile #:tailp)
  (:local-nicknames (#:i #:burke/interpreter)
                    (#:syms #:burke/interpreter/syms)
                    (#:baselib #:burke/baselib)
                    (#:cenv #:burke/cenv)
                    (#:info #:burke/info)
                    (#:o #:burke/vm/ops)
                    (#:vm #:burke/vm)
                    (#:asm #:burke/vm/asm))
  (:export #:compile #:module))
