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
    | EGL_EXT_image_dma_buf_import_modifiers
    | GPU copy before callback returns
    v
application-owned GL_RGBA8 texture (double/triple buffered)
    |
    | shared EGL context + atomic completed-slot publication
    v
FlTextureGL.populate
    |
    v
Flutter Texture widget
```

The stock Flutter runner may pass its `FlTextureRegistrar*` and current EGL
share context to exported Rust C ABI functions. That is a narrow registration
shim, not a GTK browser implementation. Browser creation, CEF callbacks,
DMA-BUF import, synchronization, and texture ownership remain in Rust.

## Implementation phases and gates

1. **Capability probe**
   - Build the reserved Cargo feature `cef-accelerated`.
   - Enable `shared_texture_enabled`, GPU compositing, `--use-angle=gl-egl`,
     and an explicitly selected Ozone platform.
   - Record paint count, plane count, format, modifier, coded size, and visible
     rectangle without retaining any callback resource.
   - Gate: repeated valid callbacks on the target AMD/Intel/NVIDIA host.

2. **Flutter texture registration seam**
   - Add one runner-to-Rust initialization call carrying the Flutter texture
     registrar and EGL context/display information.
   - Implement an `FlTextureGL` instance and expose its texture ID to Dart.
   - Gate: application-owned generated GL texture is visible and survives
     resize, hot reload, and app shutdown.

3. **Callback-time GPU copy**
   - Validate every plane, stride, offset, modifier, coded size, and visible
     rectangle.
   - Import the borrowed DMA-BUF as an EGL image in a shared context.
   - Copy into the next application-owned RGBA8 slot, fence it, destroy the EGL
     image, and close imported descriptors before returning.
   - Gate: no CEF handle or imported image is retained after callback return.

4. **Publication and fallback**
   - Publish only completed/fenced slots to Flutter and mark a texture frame
     available.
   - Keep CPU OSR selectable as a diagnostic fallback, not as an implicit copy
     inside the accelerated path.
   - Gate: navigation, click, wheel, keyboard, DPR changes, and rapid resize
     pass the same smoke flow on both transports.

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
