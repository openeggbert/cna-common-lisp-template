;;;; hello-game.lisp --- a CNA-Lisp game, written the way one should be.
;;;;
;;;; Everything here is public CNA-Lisp: a CLOS class subclassing XNA:GAME,
;;;; methods on the lifecycle generic functions, Lisp value objects, and
;;;; conditions. No handle, no result code, no CFFI, no private package.

(in-package #:cna-lisp-template)

(defclass hello-game (xna:game)
  ((graphics-manager :initform nil :accessor graphics-manager)
   (sprite-batch     :initform nil :accessor sprite-batch)
   (texture          :initform nil :accessor texture)
   (content-path     :initarg :content-path :initform "Content/logo.png"
                     :reader content-path)
   ;; --- animation state, all of it plain Lisp values --------------------
   (position         :initform (xna:make-vector2 0.0 0.0) :accessor sprite-position)
   (rotation         :initform 0.0 :accessor rotation)
   (scale            :initform 1.0 :accessor scale)
   (phase            :initform 0.0 :accessor phase-of)
   ;; --- what the canary measures -----------------------------------------
   (update-count     :initform 0 :accessor update-count)
   (draw-count       :initform 0 :accessor draw-count)
   (load-count       :initform 0 :accessor load-count)
   (unload-count     :initform 0 :accessor unload-count)
   (initialize-count :initform 0 :accessor initialize-count)
   (renderer         :initform nil :accessor renderer)
   (viewport-size    :initform nil :accessor viewport-size)
   ;; The blend state the sprite is drawn with, built once rather than per frame:
   ;; XNA makes a state object read-only the moment it is applied, so one that is
   ;; rebuilt every frame is one that is thrown away every frame.
   (blend-state      :initform nil :accessor blend-state-of)
   (sampler-state    :initform nil :accessor sampler-state-of)
   (pixels-read      :initform nil :accessor pixels-read)
   (interactive      :initarg :interactive :initform nil :reader interactive-p)
   (draw-failure     :initform nil :accessor draw-failure))
  (:documentation
   "The template's game. It draws one sprite that moves along a Lissajous path
while rotating and pulsing, and counts every native callback it received."))

(defmethod initialize-instance :after ((game hello-game) &key)
  ;; XNA constructs the graphics device manager in the game's constructor, and so
  ;; does this: INITIALIZE-INSTANCE :AFTER is where a CLOS program builds itself.
  (setf (graphics-manager game)
        (make-instance 'xna:graphics-device-manager :game game)))

(defmethod xna:initialize ((game hello-game))
  (incf (initialize-count game)))

(defmethod xna:load-content ((game hello-game))
  (incf (load-count game))
  (let ((device (xna:graphics-device game)))
    (setf (renderer game) (gfx:renderer-name device))
    (let ((viewport (gfx:viewport device)))
      (setf (viewport-size game)
            (cons (gfx:viewport-width viewport) (gfx:viewport-height viewport))))
    (setf (texture game) (gfx:texture-2d-from-png-file device (content-path game))
          (sprite-batch game) (make-instance 'gfx:sprite-batch
                                             :graphics-device device))
    ;; Built once, here, and not per frame. A state object becomes permanently
    ;; read-only the moment it is applied -- that is XNA's rule, not this
    ;; binding's -- so one built inside DRAW would be a new object every frame
    ;; and the old one would be garbage after its first use.
    (setf (blend-state-of game) (make-instance 'gfx:blend-state)
          (sampler-state-of game) (make-instance 'gfx:sampler-state))
    (setf (gfx:color-source-blend (blend-state-of game)) :source-alpha
          (gfx:color-destination-blend (blend-state-of game)) :inverse-source-alpha
          (gfx:alpha-source-blend (blend-state-of game)) :one
          (gfx:alpha-destination-blend (blend-state-of game)) :inverse-source-alpha
          (gfx:filter (sampler-state-of game)) :linear
          (gfx:address-u (sampler-state-of game)) :clamp
          (gfx:address-v (sampler-state-of game)) :clamp)))

(defmethod xna:unload-content ((game hello-game))
  (incf (unload-count game)))

(defmethod xna:update ((game hello-game) game-time)
  (declare (ignore game-time))
  (incf (update-count game))
  ;; Deterministic animation: driven by the frame number, not by wall-clock time,
  ;; so two runs of the same length draw exactly the same frames.
  (let* ((n (update-count game))
         (angle (* n 0.031415f0))
         (width (or (car (viewport-size game)) 800))
         (height (or (cdr (viewport-size game)) 480)))
    (setf (phase-of game) angle
          (rotation game) (* n 0.02f0)
          (scale game) (+ 1.0f0 (* 0.35f0 (sin (* n 0.05f0))))
          (sprite-position game)
          (xna:make-vector2 (+ (/ width 2.0f0) (* (* width 0.30f0) (sin angle)))
                            (+ (/ height 2.0f0) (* (* height 0.30f0) (sin (* 2 angle)))))))
  ;; Interactive runs stop on Escape. A deterministic run must not, or the frame
  ;; count would depend on whether somebody leaned on the keyboard.
  (when (interactive-p game)
    (when (input:is-key-down (input:keyboard-get-state) :escape)
      (xna:exit game))))

(defmethod xna:draw ((game hello-game) game-time)
  (declare (ignore game-time))
  (incf (draw-count game))
  (handler-case
      (let ((device (xna:graphics-device game))
            (batch (sprite-batch game))
            (texture (texture game)))
        (gfx:clear device (xna:cornflower-blue))
        ;; Where a renderer can answer, read one pixel of what was just cleared.
        ;; A Headless renderer refuses -- it has no back buffer to read -- and
        ;; that refusal is the honest answer, so it is recorded rather than
        ;; treated as a failure. `CANARY pixels=' says which happened.
        (unless (pixels-read game)
          (setf (pixels-read game)
                (handler-case
                    (let ((pixel (aref (gfx:get-back-buffer-data
                                        device :source (xna:make-rectangle 0 0 1 1))
                                       0)))
                      (format nil "~d,~d,~d,~d"
                              (xna:color-r pixel) (xna:color-g pixel)
                              (xna:color-b pixel) (xna:color-a pixel)))
                  (xna:cna-not-supported-error () "not-supported"))))
        (when (and batch texture)
          ;; The five-parameter Begin, with the state objects the sprite is drawn
          ;; under. XNA's other two Begin shapes take an Effect, which CNA-Lisp
          ;; does not have yet and does not pretend to.
          (gfx:begin batch
                     :sort-mode :deferred
                     :blend-state (blend-state-of game)
                     :sampler-state (sampler-state-of game)
                     :depth-stencil-state (gfx:depth-stencil-state-none)
                     :rasterizer-state (gfx:rasterizer-state-cull-counter-clockwise))
          (unwind-protect
               (gfx:draw-texture
                batch texture
                :position (sprite-position game)
                :color (xna:white)
                :rotation (rotation game)
                :origin (xna:make-vector2 (/ (gfx:width texture) 2.0f0)
                                          (/ (gfx:height texture) 2.0f0))
                :scale (scale game)
                :effects :none
                :layer-depth 0.0f0)
            (gfx:end batch))))
    ;; A condition raised here would be contained by CNA-Lisp and re-signalled
    ;; after the frame; catching it makes the canary report it instead of dying
    ;; halfway through a run.
    (error (condition) (setf (draw-failure game) condition))))

(defun dispose-everything (game)
  "Dispose the game's resources, children before parent, whatever happened.

CNA destroys children before their parent and refuses the other order, and
CNA-Lisp refuses it one step earlier with a diagnosable condition. So the order
here is not a style preference."
  (when (sprite-batch game)
    (xna:dispose (sprite-batch game)))
  (when (texture game)
    (xna:dispose (texture game)))
  (when (graphics-manager game)
    (xna:dispose (graphics-manager game)))
  (xna:dispose game))

(defun resources-disposed-p (game)
  "True when every resource this game made has been disposed.

Asked entirely through the public API: DISPOSED-P is the question CNA-Lisp
offers, and a consumer needs no more than that to know it left nothing alive."
  (and (or (null (sprite-batch game)) (xna:disposed-p (sprite-batch game)))
       (or (null (texture game)) (xna:disposed-p (texture game)))
       (or (null (graphics-manager game)) (xna:disposed-p (graphics-manager game)))
       (xna:disposed-p game)))
