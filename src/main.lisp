;;;; main.lisp --- the canary's entry points and its machine-readable verdict.
;;;;
;;;; Two modes:
;;;;
;;;;   --frames N   deterministic. Runs exactly N frames and fails unless it
;;;;                received exactly N updates and N draws.
;;;;   (no flag)    interactive. Runs until Escape or the window closes.
;;;;
;;;; The deterministic mode uses variable timing on purpose. Under CNA's fixed
;;;; time step a frame that overran its target is followed by catch-up updates,
;;;; so a frame count would not be an update count and "exactly N" would be a
;;;; claim about how fast the machine happened to be. Drawing is one per frame in
;;;; both modes.

(in-package #:cna-lisp-template)

(define-condition canary-failure (error)
  ((detail :initarg :detail :reader canary-failure-detail))
  (:report (lambda (condition stream)
             (format stream "~a" (canary-failure-detail condition)))))

(defun one-line (object)
  "OBJECT printed with every run of whitespace collapsed to one space.

The counter lines are meant to be grepped, so a condition report that wraps over
several indented lines has to become one."
  (let ((text (princ-to-string object))
        (out (make-string-output-stream))
        (pending nil)
        (started nil))
    (loop for character across text
          do (if (member character '(#\Space #\Tab #\Newline #\Return #\Page))
                 (setf pending started)
                 (progn (when pending (write-char #\Space out) (setf pending nil))
                        (write-char character out)
                        (setf started t))))
    (get-output-stream-string out)))

(defun content-file ()
  "The template's own PNG, resolved next to this system rather than to the
current directory."
  (namestring (asdf:system-relative-pathname "cna-common-lisp-template"
                                             "Content/logo.png")))

(defun content-directory ()
  "The ContentManager root, resolved next to this system for the same reason.

An XNA program says `Content.RootDirectory = \"Content\"' and gets away with a
relative path because the runtime sets the working directory to the game's own.
Nothing sets it here -- `run.lisp' is run from wherever the operator happens to
be standing -- so the path is resolved rather than assumed."
  (namestring (asdf:system-relative-pathname "cna-common-lisp-template" "Content/")))

(defun print-counters (game frames mode)
  "One machine-readable line per counter. Meant to be grepped, not read aloud."
  (format t "~&CANARY mode=~a~%" mode)
  (format t "CANARY frames_requested=~d~%" (or frames -1))
  (format t "CANARY updates=~d~%" (update-count game))
  (format t "CANARY draws=~d~%" (draw-count game))
  (format t "CANARY initializes=~d~%" (initialize-count game))
  (format t "CANARY loads=~d~%" (load-count game))
  (format t "CANARY unloads=~d~%" (unload-count game))
  (format t "CANARY renderer=~a~%" (or (renderer game) "unknown"))
  (format t "CANARY viewport=~a~%"
          (if (viewport-size game)
              (format nil "~dx~d" (car (viewport-size game)) (cdr (viewport-size game)))
              "unknown"))
  (format t "CANARY texture=~a~%"
          (if (texture game)
              (format nil "~dx~d" (gfx:width (texture game)) (gfx:height (texture game)))
              "none"))
  (format t "CANARY pixels=~a~%" (or (pixels-read game) "not-read"))
  (format t "CANARY triangle_pixel=~a~%" (or (triangle-pixel game) "not-read"))
  (format t "CANARY render_target_pixel=~a~%"
          (or (render-target-pixel game) "not-read"))
  (format t "CANARY font=~a~%" (or (font-description game) "none"))
  (format t "CANARY text_pixel=~a~%" (or (text-pixel game) "not-read"))
  (format t "CANARY draw_failure=~a~%"
          (if (draw-failure game) (one-line (draw-failure game)) "none"))
  (format t "CANARY disposed=~a~%" (if (resources-disposed-p game) "yes" "no"))
  (finish-output))

(defun run-frames (frames &key (content (content-file)))
  "Run exactly FRAMES native frames and check that exactly that many arrived.

Answers the game. Signals CANARY-FAILURE when the counts disagree with the
request, when drawing failed, or when anything was left undisposed."
  (check-type frames (integer 1))
  (let ((game (make-instance 'hello-game :content-path content
                                         :content-root (content-directory)
                                         :window-title "CNA-Lisp template canary"))
        (run-failure nil))
    ;; The counters are printed *after* disposal, because unload-content and the
    ;; disposal itself are part of what the canary measures. Printing them before
    ;; would report unloads=0 and disposed=no for a run that did both.
    (unwind-protect
         (handler-case
             (progn
               (setf (xna:is-fixed-time-step game) nil)
               (dotimes (i frames)
                 (xna:run-one-frame game)))
           (error (condition) (setf run-failure condition)))
      (dispose-everything game))
    (print-counters game frames "frames")
    (let ((problems '()))
      (when run-failure
        (push (format nil "the run failed: ~a: ~a"
                      (type-of run-failure) (one-line run-failure))
              problems))
      (unless (= frames (update-count game))
        (push (format nil "asked for ~d frames and received ~d updates"
                      frames (update-count game))
              problems))
      (unless (= frames (draw-count game))
        (push (format nil "asked for ~d frames and received ~d draws"
                      frames (draw-count game))
              problems))
      (unless (= 1 (initialize-count game))
        (push (format nil "initialize ran ~d times, not once" (initialize-count game))
              problems))
      (unless (= 1 (load-count game))
        (push (format nil "load-content ran ~d times, not once" (load-count game))
              problems))
      (unless (= 1 (unload-count game))
        (push (format nil "unload-content ran ~d times, not once" (unload-count game))
              problems))
      (when (draw-failure game)
        (push (format nil "drawing failed: ~a" (draw-failure game)) problems))
      (unless (resources-disposed-p game)
        (push "something the game created was still undisposed afterwards" problems))
      (when problems
        (error 'canary-failure :detail (format nil "~{~a~^; ~}" (nreverse problems)))))
    game))

(defun run-interactive (&key (content (content-file)))
  "Run until Escape is pressed or the window is closed."
  (let ((game (make-instance 'hello-game :content-path content
                                         :content-root (content-directory)
                                         :interactive t
                                         :window-title "CNA-Lisp template")))
    (unwind-protect (xna:run game)
      (dispose-everything game))
    (print-counters game nil "interactive")
    game))

(defun parse-arguments (arguments)
  "Answer two values: the requested frame count (NIL for interactive) and the
content path to use."
  (let ((frames nil)
        (content (content-file))
        (rest arguments))
    (loop while rest
          do (let ((argument (pop rest)))
               (cond
                 ((string= argument "--frames")
                  (unless rest
                    (error 'canary-failure :detail "--frames needs a count"))
                  (let ((value (parse-integer (pop rest) :junk-allowed t)))
                    (unless (and value (plusp value))
                      (error 'canary-failure
                             :detail "--frames needs a positive integer"))
                    (setf frames value)))
                 ((string= argument "--interactive") (setf frames nil))
                 ((string= argument "--content")
                  (unless rest
                    (error 'canary-failure :detail "--content needs a path"))
                  (setf content (pop rest)))
                 ((string= argument "--help")
                  (format t "~&usage: run.lisp [--frames N | --interactive] ~
                             [--content PATH]~%")
                  (return-from parse-arguments (values :help content)))
                 (t (error 'canary-failure
                           :detail (format nil "unknown argument ~s" argument))))))
    (values frames content)))

(defun main (arguments)
  "The canary. Answers 0 on success and a non-zero code on failure."
  (handler-case
      (multiple-value-bind (frames content) (parse-arguments arguments)
        (cond ((eq frames :help) 0)
              (frames (run-frames frames :content content)
                      (format t "CANARY result=pass~%") 0)
              (t (run-interactive :content content)
                 (format t "CANARY result=pass~%") 0)))
    (canary-failure (condition)
      (format t "~&CANARY result=fail~%CANARY reason=~a~%" (one-line condition))
      (finish-output)
      1)
    (xna:cna-error (condition)
      ;; A CNA-Lisp condition, reported as what it is. There is no result code to
      ;; print here, because the public API does not have one.
      (format t "~&CANARY result=fail~%CANARY reason=~a: ~a~%"
              (type-of condition) (one-line condition))
      (finish-output)
      1)
    (error (condition)
      (format t "~&CANARY result=fail~%CANARY reason=~a: ~a~%"
              (type-of condition) (one-line condition))
      (finish-output)
      1)))
