# Rust + CEF browser-surface probe

This Flutter Linux experiment renders Chromium Embedded Framework content
without creating a WebKitGTK or GTK browser widget. The stock Flutter Linux
shell and prebuilt CEF runtime still link Linux platform libraries including
GTK/ATK, but this project does not create a GTK browser widget or implement a
GTK/C++ browser bridge.

## Current architecture

[`native_toolchain_rust`](https://pub.dev/packages/native_toolchain_rust)
builds the Rust `cdylib` through Dart's native-assets hook. The browser layer is
[`tauri-apps/cef-rs`](https://github.com/tauri-apps/cef-rs), pinned to commit
`a2e15ae659c4b3957883e34de879bd8b38360ce5` (CEF 151.8.0 / Chromium 151).

```text
CEF GPU process
        |
OnAcceleratedPaint (callback-scoped DMA-BUF)
        |
        | synchronous Rust -> C FFI callback
        v
EGL import + GPU blit into a three-slot application-owned GL ring
        |
        | publish only after fence completion
        v
Flutter Linux FlTextureGL -> Texture widget
```

The accelerated transport is ABI v5 and remains opt-in while the experiment is
being hardened. It enables CEF shared textures, imports every callback-scoped
DMA-BUF through EGL, and GPU-copies it before returning to CEF. The texture size
must exactly equal CEF's visible physical-pixel size; a mismatch is rejected
instead of silently stretching a browser frame. A bounded GL fence wait protects
the borrowed resource lifetime, with an explicit `glFinish` fallback that is
counted in the diagnostics.

The CPU `OnPaint` path remains available as the behavioral reference and
diagnostic fallback. The procedural Rust frame is only a startup placeholder
and test backend. The running app exposes URL navigation, pumps CEF outside
Flutter's active frame phase, and forwards pointer move, click, wheel, focus,
and direct keyboard events through the C ABI in CEF view coordinates.
`marionette_flutter` is enabled only in ordinary debug runs; tests and release
builds retain the standard Flutter binding.

## One-time CEF setup

CEF is much larger than one shared library. Install the pinned minimal Linux
distribution into the ignored `third_party/cef/` directory:

```sh
dart run tool/setup_cef.dart
```

The download is about 306 MiB. The exported development distribution is about
1.5 GiB because its `libcef.so` contains debug information. The Linux CMake
bundle installs `libcef`, resources, locales, graphics support libraries, and
the dedicated `zikzak_cef_helper` beside the Rust native asset.

## Run and verify

```sh
flutter analyze
flutter test
CEF_PATH="$PWD/third_party/cef" \
  rustup run 1.95.0 cargo test --manifest-path rust/Cargo.toml \
  --features cef-runtime
flutter build linux --debug
flutter run -d linux
```

Run the accelerated callback probe with:

```sh
ZIKZAK_CEF_ACCELERATED_PROBE=1 flutter run -d linux
```

The probe selects Ozone Wayland when running in a Wayland session and otherwise
uses X11. Override it for driver comparisons with
`ZIKZAK_CEF_OZONE_PLATFORM=x11` or `ZIKZAK_CEF_OZONE_PLATFORM=wayland`. The
surface reports paint validity, coded size, plane count, CEF pixel format, DRM
modifier, first-plane stride, Flutter GL texture identity, successful copy
count, copy latency, fence fallback count, and exact-size status.

For Marionette inspection, copy the VM-service WebSocket URI from `flutter run`
and use:

```sh
marionette --uri <ws-uri> get-interactive-elements
marionette --uri <ws-uri> enter-text --key address-field --input https://flutter.dev
marionette --uri <ws-uri> tap --key navigate-button
```

For a deterministic input, resize, and sharpness check, navigate to the local
smoke page (replace `$PWD` with the absolute checkout path in the URL field):

```text
file://$PWD/tool/cef_smoke_test.html
```

The page prints its CSS viewport and device-pixel ratio, records wheel/resize
events, accepts direct keyboard input, and changes visible status when its
button is clicked through the Flutter surface.

## Proven and remaining boundaries

The current milestone proves real CEF CPU off-screen pixels can cross Rust FFI
and appear inside Flutter at the viewport's physical-pixel resolution. It also
forwards mouse movement, primary/middle/secondary clicks, wheel scrolling,
focus, and direct keyboard events. Full IME composition, touch, drag-and-drop,
popups, cursor-shape updates, clipboard integration, accessibility, downloads,
and browser dialogs are still missing. The browser cache currently lives in a
per-process directory under the system temporary directory, and CEF runs with
its sandbox disabled for this experiment.

The Linux accelerated path has received valid, resize-aware, single-plane
BGRA8888 DMA-BUF descriptions and registered an application-owned
`FlTextureGL`. A narrow C runner shim creates an EGL context shared with
Flutter, and Rust invokes its FFI copy callback synchronously from
`OnAcceleratedPaint`. The imported EGL image is destroyed before CEF's callback
returns; only the application-owned texture ring survives. Normal application
shutdown closes the browser, pumps until CEF reports `on_before_close`, and then
unloads the native runtime.

On the current Intel/Mesa Wayland development host, the animated local smoke
page sustained about 63 valid paints per second over a three-second sample,
preserved exact 1:1 output through 918×634, 1240×449, and 960×303 surfaces,
rotated all three GL slots, and recorded zero fence fallbacks. A one-pixel CSS
grid line remained one physical pixel, and click plus direct keyboard input
updated the page. These are host-specific experiment results, not cross-driver
or 4K proof. The remaining transport work includes 1080p/4K profiling,
multi-plane formats, GPU/renderer crash recovery, hidden-window behavior, and
repeated lifecycle cycles. See the ownership and verification contract in
[`docs/ACCELERATED_OSR.md`](docs/ACCELERATED_OSR.md).
