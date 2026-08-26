# Browser texture experiment

This Flutter Linux experiment renders an off-screen browser directly into a
Flutter-owned GPU texture. Browser setup, callbacks, DMA-BUF handling, EGL
import, and texture publication are implemented in Rust and called through
Dart FFI. The experiment does not create a GTK browser widget and contains no
handwritten C or C++ browser/texture bridge.

The ordinary generated Flutter Linux runner still uses the platform's GTK
shell. That GTK code owns only the application window; it does not host or
transport browser content.

## Backends

The selected backend is recorded in [`tool/browser_backend`](tool/browser_backend):

- `wpe` uses the host's WPE WebKit runtime. It is the default and keeps the
  browser engine out of the application bundle.
- `cef` uses the pinned CEF development distribution under
  `third_party/cef/`. It remains available as the original reference backend.

[`native_toolchain_rust`](https://pub.dev/packages/native_toolchain_rust)
builds the Rust `cdylib` through Dart's native-assets hook.
[`irondash_engine_context`](https://pub.dev/packages/irondash_engine_context)
passes the Flutter engine handle through FFI, while
[`irondash_texture`](https://crates.io/crates/irondash_texture) implements the
Linux `FlTextureGL` registration in Rust.

The WPE path is:

```text
WPE WebProcess
      |
WPEBufferDMABuf + rendering fence
      |
      | callback-scoped Rust FFI
      v
Rust EGL import + GPU copy into a three-slot application-owned GL ring
      |
      v
Irondash FlTextureGL -> Flutter Texture widget
```

The rendering fence is resolved before importing the borrowed WPE buffer. Rust
imports up to four DMA-BUF planes, copies the frame while WPE still owns the
buffer, releases the WPE buffer, and publishes only the application-owned GL
texture. No browser pixels are read back through the CPU.

## Build with the system WPE runtime

Install a development package that provides `wpe-webkit-2.0.pc`, the
`libWPEWebKit-2.0` shared library, and the WPE Web/Network process executables.
For example, the package is named `wpewebkit` on Arch-based distributions.
Then keep `tool/browser_backend` set to `wpe` and run:

```sh
flutter analyze
flutter test
flutter build linux --release
flutter run -d linux
```

The WPE release built during this experiment was 23 MiB and contained no CEF
library, helper executable, resources, or locales. It dynamically depends on
the WPE WebKit installed on the target system. That measurement is specific to
this Linux host and current toolchain.

## Build with CEF

Change `tool/browser_backend` to `cef`, then install the pinned minimal CEF
distribution into the ignored `third_party/cef/` directory:

```sh
dart run tool/setup_cef.dart
flutter build linux --release
```

CEF is pinned through
[`tauri-apps/cef-rs`](https://github.com/tauri-apps/cef-rs) at commit
`a2e15ae659c4b3957883e34de879bd8b38360ce5` (CEF 151.8.0 / Chromium 151).
The setup download is about 306 MiB, and the exported development distribution
is about 1.5 GiB because its `libcef.so` contains debug information. A CEF
release therefore bundles a much larger, self-contained browser surface.

The accelerated CEF path can be enabled with
`CEF_TEXTURE_BROWSER_ACCELERATED_PROBE=1`. Its resource-ownership contract is
documented in [`docs/ACCELERATED_OSR.md`](docs/ACCELERATED_OSR.md).

## Current proof and remaining work

On the current Intel/Mesa Wayland host, WPE WebKit 2.52.6 rendered a real page
into the Flutter texture using a two-plane XR24 DMA-BUF with a modifier. The
visible probe reported 3/3 valid frames, three successful GPU copies, and zero
CPU fallback. Closing the window also removed the application and WPE helper
processes cleanly.

The experiment currently supports navigation, resize, audio, pointer movement,
primary/middle/secondary clicks, wheel input, common XKB keyboard input and
shortcuts, bidirectional plain-text clipboard bridging, and Flutter-rendered
context menus backed by WebKit actions. Before this is an application-ready
browser layer it still needs complete IME composition, cursor updates, browser
popups, rich clipboard formats, downloads, dialogs, accessibility, crash
recovery, repeated lifecycle testing, and validation across GPU drivers and
display protocols.

`marionette_flutter` is enabled in ordinary debug runs for inspecting the
Flutter controls around the browser surface; tests and release builds retain
the standard Flutter binding.
