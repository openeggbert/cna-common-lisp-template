;;;; cna-common-lisp-template.asd --- a standalone CNA-Lisp consumer.
;;;;
;;;; This system depends on the public CNA-Lisp system and on nothing else. It
;;;; does not depend on CFFI, it does not name a private CNA-Lisp package, and it
;;;; has no idea that a C ABI exists.

(defsystem "cna-common-lisp-template"
  :description "A real CNA-Lisp consumer and canary: a game that loads a PNG, draws it
moving, rotating and scaling, reads the keyboard, and counts the native callbacks it
received."
  :author "Robert Vokac <robertvokac@robertvokac.com>"
  :license "MS-PL"
  :version "0.1.0"
  :depends-on ("cna-common-lisp")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "hello-game")
               (:file "main")))
