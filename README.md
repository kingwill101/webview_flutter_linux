# Rust browser-surface probe

This Flutter Linux experiment is testing a GTK-free browser rendering layer.
The stock Flutter Linux application shell still uses GTK, but the browser and
frame-production path will not use a `GtkWidget`, WebKitGTK, or
`gtk_widget_draw`.

## Current milestone

[`native_toolchain_rust`](https://pub.dev/packages/native_toolchain_rust)
builds `rust/` through Dart's native-assets hook and bundles
`libzikzak_browser_native.so` with the Flutter application.

The first vertical slice is intentionally smaller than CEF:

```text
Rust procedural RGBA renderer
        |
        | C ABI generated-frame call
        v
Dart-owned native buffer
        |
        v
Flutter raw-pixel decoder -> ui.Image -> RawImage
```

Keeping the destination buffer owned by Dart makes the lifetime explicit. The
future asynchronous browser callback must publish or copy a complete frame
without lending Dart memory that CEF may recycle after its paint callback.

The C ABI is declared in `rust/include/zikzak_browser_ffi.h`, implemented in
`rust/src/lib.rs`, and consumed by `lib/src/native_frame_bindings.dart`.

## Run and verify

```sh
flutter analyze
flutter test
rustup run 1.95.0 cargo test --manifest-path rust/Cargo.toml
flutter build linux --debug
flutter run -d linux
```

The application should show an animated browser-shaped frame and an increasing
frame counter. The native library should be present at:

```text
build/linux/x64/debug/bundle/lib/libzikzak_browser_native.so
```

## Next milestone: CEF OSR

The next slice replaces the procedural renderer with a pinned
[`cef-rs`](https://github.com/tauri-apps/cef-rs) off-screen browser:

1. Add a Rust CEF runtime behind a Cargo feature and prove CPU `OnPaint` into
   the same RGBA frame contract.
2. Add navigation, resize, mouse, wheel, keyboard, focus, and IME functions to
   the C ABI.
3. Move browser work onto a native runtime thread and publish frames through a
   bounded ring so Flutter never blocks CEF.
4. After the CPU path is visibly correct, consume Linux `OnAcceleratedPaint`
   DMA-BUF frames and GPU-copy them into application-owned buffers.
5. Import those buffers through Flutter's Linux external-texture API.

`native_toolchain_rust` bundles the Rust library, but a CEF distribution also
contains `libcef`, a subprocess executable, sandbox support, locale packs, and
Chromium resource/snapshot files. Packaging those files is a distinct part of
the CEF milestone; it should not be hidden inside the FFI frame contract.
