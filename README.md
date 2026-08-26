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
CEF helper processes
        |
CEF CPU OnPaint callback (borrowed BGRA)
        |
        | copy + BGRA -> RGBA before callback returns
        v
Rust-owned latest complete frame + dimensions
        |
        | C ABI copy into caller-owned memory
        v
Dart native buffer -> ui.Image -> Flutter RawImage
```

The procedural Rust frame remains as a startup placeholder and a test backend.
The running app exposes URL navigation, pumps CEF from the Flutter UI isolate,
and displays CEF's frame generation. The Flutter surface reports its logical
size and device-pixel ratio to CEF, so `OnPaint` produces a native-resolution
frame instead of stretching the original 800×450 startup bitmap. Pointer move,
click, wheel, focus, and direct keyboard events are forwarded through the C
ABI in CEF view coordinates. `marionette_flutter` is enabled only in ordinary
debug runs; tests and release builds retain the standard Flutter binding.

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
popups, cursor-shape updates, clipboard integration, accessibility, and browser
lifecycle/shutdown are still missing. The browser cache currently lives in a
per-process directory under the system temporary directory, and CEF runs with
its sandbox disabled for this experiment.

The next rendering milestone is Linux accelerated OSR. CEF's
`OnAcceleratedPaint` supplies callback-lifetime DMA-BUF resources; those must be
GPU-copied into application-owned images before the callback returns, then
published through a Flutter Linux external texture. It should not reuse or hold
CEF's borrowed handles after the callback. See the phased ownership and
verification contract in [`docs/ACCELERATED_OSR.md`](docs/ACCELERATED_OSR.md).
