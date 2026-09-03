;;;; package.lisp --- the template's one package.
;;;;
;;;; Three local nicknames, one per XNA namespace, and nothing else. There is no
;;;; nickname for a CNA-Lisp internal package because a consumer has no business
;;;; naming one.

(defpackage #:cna-lisp-template
  (:use #:cl)
  (:local-nicknames (#:xna   #:microsoft.xna.framework)
                    (#:gfx   #:microsoft.xna.framework.graphics)
                    (#:input #:microsoft.xna.framework.input))
  (:export #:hello-game #:main #:run-frames #:run-interactive
           #:update-count #:draw-count))
