(defsystem :burke
  :depends-on (:cl-conspack)
  :components
  ((:module "interpreter"
    :depends-on ()
    :components ((:file "packages")
                 (:file "interpret" :depends-on ("packages"))
                 (:file "plist" :depends-on ("packages"))
                 (:file "marshal" :depends-on ("interpret" "packages"))
                 (:file "ground" :depends-on ("interpret" "plist" "packages"))))
   (:file "packages" :depends-on ("interpreter"))
   (:file "repl" :depends-on ("interpreter" "packages"))
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
   (:module "quickc"
    :depends-on ("compilation-environment" "info" "vm" "interpreter")
    :components ((:file "compile")
                 (:file "known" :depends-on ("compile"))))
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
