(defsystem :burke
  :depends-on (#+(or):cl-conspack :trivial-garbage)
  :components
  ((:module "interpreter"
    :depends-on ()
    :components ((:file "packages")
                 (:file "interpret" :depends-on ("packages"))
                 (:file "ptree" :depends-on ("packages"))
                 #+(or) ; needs special conspack
                 (:file "marshal" :depends-on ("interpret" "packages"))))
   (:file "packages" :depends-on ("interpreter"))
   (:module "baselib"
    :depends-on ("interpreter" "packages")
    :components ((:file "defenv")
                 (:file "ground" :depends-on ("defenv"))
                 (:file "continuation" :depends-on ("ground" "defenv"))
                 (:file "static" :depends-on ("ground" "defenv"))
                 (:file "numbers" :depends-on ("defenv"))
                 (:file "macro" :depends-on ("ground" "defenv"))
                 (:file "core" :depends-on ("continuation" "ground"))
                 (:file "base" :depends-on ("core" "macro" "numbers" "static" "continuation"))))
   (:file "repl" :depends-on ("baselib" "packages"))
   (:module "vm"
    :depends-on ("interpreter" "packages")
    :components ((:file "ops")
                 (:file "packages" :depends-on ("ops"))
                 (:file "vm" :depends-on ("ops" "packages"))
                 (:file "asm" :depends-on ("vm" "packages"))
                 (:file "dis" :depends-on ("vm" "ops" "packages"))))
   (:file "type" :depends-on ("packages"))
   (:file "info" :depends-on ("type" "packages"))
   (:file "compilation-environment" :depends-on ("interpreter" "info"
                                                               "packages"))
   (:module "treec"
    :depends-on ("compilation-environment" "info" "vm" "interpreter")
    :components ((:file "packages")
                 (:file "ptree" :depends-on ("packages"))
                 (:file "ir" :depends-on ("packages"))
                 (:file "free" :depends-on ("ptree" "ir"))
                 (:file "known" :depends-on ("ir"))
                 (:file "eval" :depends-on ("packages"))
                 (:file "front" :depends-on ("eval" "known" "ir" "free" "packages"))
                 (:file "primitives" :depends-on ("front" "packages"))
                 (:file "back" :depends-on ("free" "ir" "primitives" "packages"))
                 (:file "compile" :depends-on ("eval" "front" "back" "packages"))))
   (:module "ir"
    :depends-on ("info" "packages")
    :components ((:file "ir")
                 (:file "instructions" :depends-on ("ir"))
                 (:file "copy" :depends-on ("ir"))
                 (:file "linearize" :depends-on ("ir"))
                 (:file "assemble" :depends-on ("linearize" "ir"))
                 (:file "disassemble" :depends-on ("ir"))
                 (:file "verify" :depends-on ("instructions" "ir"))))
   (:module "flowc"
    :depends-on ("ir" "info" "interpreter" "packages")
    :components ((:file "compile-initial" :depends-on ())
                 (:file "runtime" :depends-on ())
                 (:file "ir2cl" :depends-on ())
                 (:file "flow" :depends-on ())
                 (:file "optimize" :depends-on ("flow"))
                 (:file "compile" :depends-on ("runtime" "optimize" "ir2cl"))))))
