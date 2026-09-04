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
   ;; The stock effect the triangle is drawn with. Built once, in LOAD-CONTENT,
   ;; because it is a GraphicsResource with a native lifetime like any other.
   (effect           :initform nil :accessor effect-of)
   (pixels-read      :initform nil :accessor pixels-read)
   (triangle-pixel   :initform nil :accessor triangle-pixel)
   ;; A render target: a Texture2D the game draws *into*, and then draws onto the
   ;; screen like any other texture. Built once, in LOAD-CONTENT, because it is a
   ;; GraphicsResource with a native lifetime.
   (render-target    :initform nil :accessor render-target-of)
   (render-target-pixel :initform nil :accessor render-target-pixel)
   ;; A SpriteFont and the atlas it draws from, both loaded through the game's own
   ;; ContentManager. A font is the one asset a program cannot construct from
   ;; arguments -- it is glyph metrics plus a texture, and both have to come from
   ;; somewhere -- so this is also the template's only use of the content pipeline.
   (font             :initform nil :accessor font-of)
   (font-atlas       :initform nil :accessor font-atlas-of)
   (content-root     :initarg :content-root :initform "Content" :reader content-root)
   ;; Described while the font is alive. The canary prints after everything has
   ;; been disposed, and asking a disposed SpriteFont for its glyphs is refused --
   ;; correctly, and it is the caller's job not to ask.
   (font-description :initform nil :accessor font-description)
   (text-pixel       :initform nil :accessor text-pixel)
   (interactive      :initarg :interactive :initform nil :reader interactive-p)
   (draw-failure     :initform nil :accessor draw-failure))
  (:documentation
   "The template's game. It draws one primitive triangle through a BasicEffect and
one sprite that moves along a Lissajous path while rotating and pulsing, and
counts every native callback it received."))

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
          (gfx:address-v (sampler-state-of game)) :clamp)
    ;; A stock effect, so the game can draw a primitive as well as a sprite. XNA
    ;; refuses a primitive draw with no current Effect -- that is
    ;; GraphicsDevice.VerifyCanDraw -- and CNA refuses it too, so this is not
    ;; optional decoration.
    (setf (effect-of game) (make-instance 'gfx:basic-effect :graphics-device device)
          (gfx:effect-vertex-color-enabled (effect-of game)) t
          (gfx:effect-lighting-enabled (effect-of game)) nil)
    ;; A 32x32 render target. Nothing here is special: it is made against the
    ;; device like a texture, disposed like one, and drawn like one.
    (setf (render-target-of game)
          (make-instance 'gfx:render-target-2d :graphics-device device
                                               :width 32 :height 32))
    ;; The font, through the game's own content manager. `Load<SpriteFont>' is
    ;; MULTIPLE-VALUE-BIND here because CNA hands back the atlas as well as the
    ;; font: a SpriteFont *is* metrics plus a texture, and both are owned
    ;; resources this game has to dispose. Content/font.cnj describes it, and
    ;; tools/qualification/make-font-fixture.py in the binding's repository is
    ;; what produced the pair.
    (let ((content (xna:content game)))
      (setf (content:root-directory content) (content-root game))
      (multiple-value-bind (font atlas)
          (content:load-asset content 'gfx:sprite-font "font")
        (setf (font-of game) font
              (font-atlas-of game) atlas
              (font-description game)
              (format nil "~d glyphs, line-spacing ~d"
                      (length (gfx:characters font)) (gfx:line-spacing font)))))))

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

(defun corner-triangle ()
  "Three VertexPositionColor vertices in clip space, in the top-left corner.

Wound so the default CullCounterClockwise keeps it once the viewport transform
has flipped Y -- get that backwards and the triangle is culled, the draw still
succeeds, and the pixel reads back as the clear colour. On an 800x480 window the
vertices land at (0,0), (240,0) and (0,144), so (40,40) is inside it."
  (vector (gfx:make-vertex-position-color (xna:make-vector3 -1.0 1.0 0.0)
                                          (xna:make-color 255 128 0 255))
          (gfx:make-vertex-position-color (xna:make-vector3 -0.4 1.0 0.0)
                                          (xna:make-color 255 128 0 255))
          (gfx:make-vertex-position-color (xna:make-vector3 -1.0 0.4 0.0)
                                          (xna:make-color 255 128 0 255))))

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
        ;; A primitive, through the effect. The vertices are in clip space --
        ;; BasicEffect's World, View and Projection start at the identity -- and
        ;; the triangle sits in the top-left corner so the sprite has the rest of
        ;; the window to move around in.
        (when (effect-of game)
          (dolist (pass (gfx:collection-elements
                         (gfx:effect-technique-passes
                          (gfx:effect-current-technique (effect-of game)))))
            (gfx:apply-effect-pass pass))
          (gfx:draw-user-primitives device :triangle-list (corner-triangle)
                                    :primitive-count 1)
          ;; And read one pixel of it back, where the renderer can. This is the
          ;; consumer's own evidence that the primitive reached the back buffer,
          ;; obtained through nothing but the public API.
          (unless (triangle-pixel game)
            (setf (triangle-pixel game)
                  (handler-case
                      (let ((pixel (aref (gfx:get-back-buffer-data
                                          device
                                          :source (xna:make-rectangle 40 40 1 1))
                                         0)))
                        (format nil "~d,~d,~d,~d"
                                (xna:color-r pixel) (xna:color-g pixel)
                                (xna:color-b pixel) (xna:color-a pixel)))
                    (xna:cna-not-supported-error () "not-supported")))))
        ;; Draw into the render target, then put the target on the screen. The
        ;; whole point of a render target is that what goes into it is not on the
        ;; screen until the game puts it there, so this clears it to a colour
        ;; nothing else in the frame uses.
        (when (render-target-of game)
          (gfx:set-render-target device (render-target-of game))
          (gfx:clear device (xna:make-color 0 200 90 255))
          ;; NIL is XNA's SetRenderTarget(null): back to the back buffer.
          (gfx:set-render-target device nil))
        (when (and batch texture)
          ;; The five-parameter Begin, with the state objects the sprite is drawn
          ;; under. The two that take an Effect exist as well; the sprite wants
          ;; the stock sprite effect, which is what leaving :EFFECT out selects.
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
            ;; The render target, drawn as the ordinary texture it is, in the
            ;; bottom-left corner where nothing else goes.
            (when (render-target-of game)
              (gfx:draw-texture batch (render-target-of game)
                                :destination (xna:make-rectangle 16 400 32 32)
                                :color (xna:white)))
            ;; Text, in the same batch as everything else -- DrawString is a
            ;; SpriteBatch operation and obeys the same Begin/End discipline as a
            ;; sprite draw, because in XNA it *is* a sprite draw.
            (when (font-of game)
              (gfx:draw-string batch (font-of game) "CNA-Lisp"
                               :position (xna:make-vector2 16.0 16.0)
                               :color (xna:white))
              (gfx:draw-string batch (font-of game)
                               (format nil "frame ~d" (draw-count game))
                               :position (xna:make-vector2 16.0 40.0)
                               :color (xna:make-color 255 220 0 255)))
            (gfx:end batch))
          ;; And read one pixel of it back, where the renderer can. Evidence, from
          ;; the consumer's side and through nothing but the public API, that the
          ;; target kept what was drawn into it and reached the screen.
          (unless (render-target-pixel game)
            (setf (render-target-pixel game)
                  (handler-case
                      (let ((pixel (aref (gfx:get-back-buffer-data
                                          device
                                          :source (xna:make-rectangle 30 414 1 1))
                                         0)))
                        (format nil "~d,~d,~d,~d"
                                (xna:color-r pixel) (xna:color-g pixel)
                                (xna:color-b pixel) (xna:color-a pixel)))
                    (xna:cna-not-supported-error () "not-supported"))))
          ;; One pixel inside the 'C' of "CNA-Lisp", drawn white on cornflower
          ;; blue at (16,16). Evidence from the consumer's side that a font it
          ;; *loaded* put glyphs on the screen -- not that DrawString was called.
          (unless (text-pixel game)
            (setf (text-pixel game)
                  (handler-case
                      (let ((pixel (aref (gfx:get-back-buffer-data
                                          device
                                          :source (xna:make-rectangle 18 24 1 1))
                                         0)))
                        (format nil "~d,~d,~d,~d"
                                (xna:color-r pixel) (xna:color-g pixel)
                                (xna:color-b pixel) (xna:color-a pixel)))
                    (xna:cna-not-supported-error () "not-supported"))))))
    ;; A condition raised here would be contained by CNA-Lisp and re-signalled
    ;; after the frame; catching it makes the canary report it instead of dying
    ;; halfway through a run.
    (error (condition) (setf (draw-failure game) condition))))

(defun dispose-everything (game)
  "Dispose the game's resources, children before parent, whatever happened.

CNA destroys children before their parent and refuses the other order, and
CNA-Lisp refuses it one step earlier with a diagnosable condition. So the order
here is not a style preference."
  ;; The font before its atlas: a SpriteFont keeps the texture it draws from
  ;; alive, and CNA refuses to destroy the atlas while the font exists.
  (when (font-of game)
    (xna:dispose (font-of game)))
  (when (font-atlas-of game)
    (xna:dispose (font-atlas-of game)))
  (when (render-target-of game)
    (xna:dispose (render-target-of game)))
  (when (effect-of game)
    (xna:dispose (effect-of game)))
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
  (and (or (null (font-of game)) (xna:disposed-p (font-of game)))
       (or (null (font-atlas-of game)) (xna:disposed-p (font-atlas-of game)))
       (or (null (render-target-of game)) (xna:disposed-p (render-target-of game)))
       (or (null (effect-of game)) (xna:disposed-p (effect-of game)))
       (or (null (sprite-batch game)) (xna:disposed-p (sprite-batch game)))
       (or (null (texture game)) (xna:disposed-p (texture game)))
       (or (null (graphics-manager game)) (xna:disposed-p (graphics-manager game)))
       (xna:disposed-p game)))
