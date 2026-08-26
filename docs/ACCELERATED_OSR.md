# Linux accelerated OSR plan

The CPU path is the behavioral reference implementation. It owns navigation,
surface sizing, input forwarding, lifecycle decisions, and visible smoke-test
evidence. Accelerated rendering must replace only the frame transport; it must
not fork those browser semantics.

## Non-negotiable ownership rule

CEF's `OnAcceleratedPaint` Linux payload contains one or more DMA-BUF file
descriptors. CEF explicitly states that the resource cannot be cached or used
after the callback returns. Every callback must import the supplied planes and
GPU-copy them into an application-owned texture before returning. Duplicating
an fd does not extend the lifetime of the pooled image contents.

Reference: [`CefRenderHandler::OnAcceleratedPaint`](https://github.com/chromiumembedded/cef/blob/master/include/cef_render_handler.h)

## Intended Linux path

```text
CEF GPU process
    |
    | OnAcceleratedPaint: DMA-BUF planes + modifier + visible rect
    v
Rust CEF callback
    |
    | synchronous call with borrowed descriptors
    v
Rust texture provider
    |
    | EGL_EXT_image_dma_buf_import_modifiers
    | shared EGL context + GPU blit before callback returns
    v
Irondash application-owned GL_RGBA8 FlTextureGL
    |
    v
Flutter Texture widget
```

The stock Flutter runner is unmodified. Dart obtains the engine handle through
`irondash_engine_context`, passes it through FFI, and Rust uses
`irondash_texture` to register `FlTextureGL`. Rust also creates the context
shared with Flutter and performs the synchronous import/blit. Browser creation,
browser behavior, CEF callbacks, texture ownership, and the callback lifetime
decision all remain in Rust.

## Implementation phases and gates

1. **Capability probe — implemented and verified on the development host**
   - Select the opt-in ABI v6 transport with
     `ZIKZAK_CEF_ACCELERATED_PROBE=1`.
   - Enable `shared_texture_enabled`, GPU compositing, `--use-angle=gl-egl`,
     and an explicitly selected Ozone platform.
   - Record paint count, plane count, format, modifier, coded size, and visible
     rectangle without retaining any callback resource.
   - Gate: repeated valid callbacks on the target AMD/Intel/NVIDIA host.
   - Evidence on the Intel UHD/Mesa Wayland host: valid single-plane BGRA8888
     callbacks with both Ozone Wayland and X11, linear DRM modifier `0x0`,
     resize-aware coded dimensions, and matching row stride. Ozone Wayland
     avoids the X11/GDK assertions seen when mixing Ozone X11 with Flutter's
     Wayland shell. The persistent probe state stores numeric metadata only and
     never retains an fd.

2. **Flutter texture registration seam — implemented and visually verified**
   - Pass the engine handle from Dart through FFI and register `FlTextureGL`
     from Rust through Irondash.
   - Allocate the destination GL texture at the surface's physical dimensions
     and expose its texture ID, GL name, and import status to Dart.
   - Evidence: the Rust-generated one-pixel grid and diagonal rendered sharply
     through texture name 3 at the full Flutter surface size.

3. **Callback-time GPU copy — implemented for single-plane RGBA/BGRA**
   - Validate every plane, stride, offset, modifier, coded size, and visible
     rectangle.
   - Import the borrowed DMA-BUF as an EGL image in a shared context.
   - Copy into the next slot of a three-texture application-owned RGBA8 ring,
     wait on a bounded GL fence, and destroy the EGL image before returning.
     A fence timeout or unavailable fence falls back to `glFinish` and is
     exposed as a diagnostic counter. The CEF fd is borrowed only for the
     synchronous call and is never closed or retained by the host.
   - Gate: no CEF handle or imported image is retained after callback return.
   - Evidence: example.com and the local asymmetric smoke page rendered upright
     at 1878x746 through `FlTextureGL`; mouse click and direct keyboard input
     updated the smoke page through the same accelerated surface.

4. **Publication and fallback — implemented and stress-checked on the development host**
   - Publish only completed/fenced slots to Flutter and mark a texture frame
     available.
   - Reject destination/visible-size mismatches instead of presenting a
     filtered or stale-size browser frame.
   - Keep CPU OSR selectable as a diagnostic fallback, not as an implicit copy
     inside the accelerated path.
   - Close the browser from Dart lifecycle shutdown, pump until
     `on_before_close`, then release the Irondash texture.
   - Evidence after the Irondash migration: the animated local smoke page
     reached 190/190 valid paints; the GL name rotated through the texture ring;
     1878×700 and 1240×369 surfaces reported 1:1; copy time peaked at 14.688 ms
     with zero fence fallbacks; click and direct keyboard input updated the
     page; normal window close left no application or CEF helper processes.
   - Gate remaining: DPR changes, hidden/minimized windows, rapid resize loops,
     and repeated lifecycle transitions pass the same smoke flow on both
     transports.

5. **Performance and correctness**
   - Measure CEF callback time, GPU copy time, Flutter frame pacing, dropped
     slots, process CPU, and memory at 1080p and 4K.
   - Test GPU-process restart, renderer crash, minimized/hidden windows, and
     repeated app shutdown.
   - Gate: no borrowed-resource lifetime violations, no unbounded queue, no
     stale-size presentation, and materially lower CPU than CPU OSR.

## Known platform constraints

- CEF's Linux shared-texture path requires ANGLE/EGL configuration; its
  behavior differs across Ozone/X11/Wayland and GPU drivers.
- Flutter's Linux `FlTextureGL.populate` callback runs with Flutter's GL context
  current, but `OnAcceleratedPaint` is a different callback boundary. A shared
  context and explicit fences are therefore part of the design, not optional
  optimizations.
- Flutter accepts an RGBA8 GL texture. CEF formats/modifiers must be validated
  and converted when direct copying is not compatible.
- IME, accessibility, popups, dialogs, downloads, and drag-and-drop are browser
  integration concerns independent of the frame transport.

## WebScene findings

The pinned WebScene Flutter backend publishes immutable semantic scene
revisions, compiles them into `ui.Picture` objects, and paints through
`CustomPaint`. It has no Flutter texture registrar or framebuffer bridge, so
that renderer cannot accept CEF's DMA-BUF output. Its acquire/apply/ack/release
discipline still validates our choice to publish only complete owned frames,
and its resize-plus-DPR and visibility handling informed the browser lifecycle.

Its frame ticker cannot be copied literally. CEF's external message pump may
dispatch GLib work synchronously; invoking it inside Flutter's ticker caused a
verified scheduler re-entrancy assertion. The CEF pump therefore runs from an
isolate timer, outside Flutter's active frame phase.
