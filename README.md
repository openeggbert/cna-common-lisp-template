# CNA-Lisp template

A real, standalone Common Lisp consumer of [CNA-Lisp][binding], and the canary
that says whether the binding still works.

It is a game: it subclasses the public CLOS `game` class, constructs a graphics
device manager, overrides the lifecycle generic functions, decodes its own PNG
into a real `Texture2D`, creates a real `SpriteBatch` and a real `BasicEffect`,
clears to Cornflower Blue, draws one primitive triangle through the effect, draws
into a `RenderTarget2D` and then draws that target onto the screen, and draws the
sprite moving along a Lissajous path while it rotates and pulses. In interactive
mode it exits on Escape.

[binding]: https://github.com/openeggbert/cna-common-lisp

## What this proves, and what it does not

**Proves**, on the qualified configuration:

* CNA-Lisp is usable from an ordinary ASDF system that depends on nothing but the
  public `cna-common-lisp` system;
* a subclass of the public `game` class receives real native lifecycle callbacks
  — `initialize`, `load-content`, `update`, `draw`, `unload-content` — and the
  counts are exact;
* a project-owned PNG becomes a real native `Texture2D` whose extent is reported
  back;
* a real `SpriteBatch` accepts a textured draw with rotation, origin, scale, tint
  and layer depth, inside the **five-parameter `Begin`** — a sort mode and four
  state objects, two of them built by this program and two of them XNA's
  predefined ones;
* a real `BasicEffect` is created, its current technique's passes are applied
  through the collection API, and a `DrawUserPrimitives` triangle is drawn — which
  is not decoration: XNA refuses a primitive draw with no current effect
  (`GraphicsDevice.VerifyCanDraw`) and so does CNA, so a consumer that draws a
  primitive has to hold an effect and apply a pass, all through the public API;
* a `RenderTarget2D` is created, bound with `set-render-target`, cleared to a
  colour nothing else in the frame uses, unbound by passing `nil` — which is
  XNA's `SetRenderTarget(null)` — and then drawn onto the back buffer as the
  ordinary `Texture2D` it is. A consumer needs nothing private to do that;
* a `BlendState` and a `SamplerState` are built once in `load-content` and not
  per frame, because a state object becomes permanently read-only the moment it
  is applied and one rebuilt every frame is one thrown away every frame;
* the graphics device is reachable from inside a lifecycle method and answers its
  renderer and viewport;
* every resource is released, children before parent, through `unwind-protect`,
  and `disposed-p` says so afterwards — **content through
  `ContentManager.Unload`, everything else by hand**, which is the division XNA
  draws: `Unload` disposes every asset the manager loaded, in the order they have
  to go, so a program never has to know that a `SpriteFont` must be disposed
  before the atlas it draws from;
* `--frames 60` delivers exactly 60 updates and 60 draws, and `--frames 600`
  delivers exactly 600 of each — a run that does not is a failure, not a warning;
* **whether anything reached pixels, where the renderer can say.** After the
  clear, one pixel of the back buffer is read back. Under `HEADLESS` there is no
  back buffer to read and CNA refuses, which the canary reports as
  `CANARY pixels=not-supported` — the honest answer, not a failure. Under a
  rasterising renderer such as `SOFTWARE` it reports the colour, and
  `CANARY pixels=100,149,237,255` is CornflowerBlue, which is what was cleared.
  `CANARY triangle_pixel=` does the same for a point inside the triangle:
  `255,128,0,255` is the triangle's own vertex colour, so the line says the
  primitive really reached the back buffer. It has to check the *colour* and not
  merely that a pixel was read — a triangle wound the wrong way is culled, the
  draw still succeeds, and the pixel reads back as the clear colour.
  `CANARY render_target_pixel=0,200,90,255` is the third of these and the most
  particular: that colour exists nowhere in the frame except inside the render
  target, so reading it back from the screen says the target was bound, kept what
  was cleared into it, survived the unbind, and was sampled as a texture — the
  whole round trip, from the consumer's side.

**Does not prove**:

* **anything about a physical display.** A back buffer is a back buffer. Under
  `HEADLESS` there is not even that, and "drew the sprite" means the draw was
  submitted and the renderer accepted it.
* anything about a window, a display server, or a real keyboard, in
  `--frames` mode: that mode never reads the keyboard, deliberately, because a
  key press would change the frame count.
* anything about audio, content pipelines, 3D, or any XNA surface CNA-Lisp does
  not implement. See the binding's `docs/compatibility.md`.

## Running it

```sh
export CNA_NATIVE_LIBRARY=/absolute/path/to/libcna_c_api.so
export CL_SOURCE_REGISTRY="/path/to/cna-common-lisp//"

sbcl --script run.lisp -- --frames 60
sbcl --script run.lisp -- --frames 600
sbcl --script run.lisp            # interactive; Escape exits
```

`CL_SOURCE_REGISTRY` is how ASDF finds CNA-Lisp. `run.lisp` adds its own
directory, so the template itself is always findable, and it loads Quicklisp when
the host has it — only to obtain CFFI, Babel and bordeaux-threads, which are
CNA-Lisp's dependencies. Nothing Quicklisp-specific is part of either system.

Options:

| | |
| --- | --- |
| `--frames N` | run exactly N frames and check that exactly N arrived |
| `--interactive` | run until Escape (the default with no arguments) |
| `--content PATH` | use a different image |
| `--help` | usage |

## The output

Every counter is printed on its own line, prefixed `CANARY `, so a script can
read them without parsing prose:

```text
CANARY mode=frames
CANARY frames_requested=60
CANARY updates=60
CANARY draws=60
CANARY initializes=1
CANARY loads=1
CANARY unloads=1
CANARY renderer=HEADLESS
CANARY viewport=800x480
CANARY texture=96x96
CANARY pixels=not-supported
CANARY draw_failure=none
CANARY disposed=yes
CANARY result=pass
```

The counters are printed **after** disposal, because `unload-content` and the
disposal itself are part of what is being measured. The exit code is 0 for
`result=pass` and 1 for `result=fail`.

A failing run says why, on one line:

```text
CANARY result=fail
CANARY reason=asked for 60 frames and received 61 updates
```

## Why `--frames` uses variable timing

Under CNA's **fixed** time step, a frame that took longer than the target step is
followed by catch-up updates — a garbage collection between frames is enough to
trigger it. Drawing stays one per frame, but the update count does not. So the
deterministic mode sets `is-fixed-time-step` to false, where a frame is exactly
one update and one draw. Claiming "exactly 60 updates" under a fixed step would
be a claim about how fast the machine happened to be.

## Only the public API

The template never names a CNA-Lisp internal package, never calls CFFI, and never
mentions a native handle or a result code. There is nothing to mention: the
public API has none of them.

```sh
tools/audit-public-only.sh
```

refuses any internal package reference, any CFFI reference, any raw handle or
result-code accessor, and any dependency other than `cna-common-lisp`.

## The asset

`Content/logo.png` is an original 96x96 image, generated from a short script
written for this repository. It is not a Microsoft or XNA sample asset, and no
Microsoft binary or asset is stored here.

## Structure

```
cna-common-lisp-template/
├── cna-common-lisp-template.asd   depends on cna-common-lisp, and nothing else
├── src/
│   ├── package.lisp               three local nicknames, one per XNA namespace
│   ├── hello-game.lisp            the game: a CLOS subclass and its methods
│   └── main.lisp                  the canary: modes, counters, verdict
├── Content/logo.png               an original project-owned image
├── tools/audit-public-only.sh     proves the template stays on the public API
└── run.lisp                       the shell entry point
```

## Licence

MS-PL, matching CNA and CNA-Lisp.
