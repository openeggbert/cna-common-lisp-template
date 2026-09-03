;;;; run.lisp --- run the CNA-Lisp template canary from a shell.
;;;;
;;;;   CNA_NATIVE_LIBRARY=/absolute/path/to/libcna_c_api.so \
;;;;     sbcl --script run.lisp -- --frames 60
;;;;
;;;; The trailing `--' is optional; SBCL passes it through in *POSIX-ARGV* and
;;;; this script skips it.
;;;;
;;;; ASDF must be able to find this system and CNA-Lisp. In a checkout that is
;;;; usually CL_SOURCE_REGISTRY; this script also adds its own directory, so the
;;;; template itself is always findable.

(require :asdf)

;;; Third-party dependencies come from wherever the host keeps them. Quicklisp is
;;; one such place and is used when present; nothing Quicklisp-specific is part of
;;; the template or of CNA-Lisp.
(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file setup)
    (handler-bind ((warning #'muffle-warning)) (load setup))))

(let ((here (make-pathname :name nil :type nil :defaults *load-truename*)))
  (pushnew here asdf:*central-registry* :test #'equal))

(handler-case (asdf:load-system "cna-common-lisp-template")
  (error (condition)
    (format *error-output*
            "~&cannot load the template: ~a~%~%~
             CNA-Lisp must be visible to ASDF. In a checkout:~%~
             ~%    export CL_SOURCE_REGISTRY=\"/path/to/cna-common-lisp//\"~%~%"
            condition)
    (uiop:quit 2)))

(let* ((argv (rest sb-ext:*posix-argv*))
       (arguments (if (and argv (string= (first argv) "--")) (rest argv) argv)))
  (uiop:quit (funcall (uiop:find-symbol* '#:main '#:cna-lisp-template) arguments)))
