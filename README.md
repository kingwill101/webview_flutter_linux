# webview_flutter_linux

An experimental Linux implementation of the official
[`webview_flutter`](https://pub.dev/packages/webview_flutter) platform
interface, backed by the host's WPE WebKit runtime.

Web content is rendered off-screen into DMA-BUFs, copied on the GPU into an
application-owned EGL texture, and published as a Flutter `Texture` through
Irondash. Browser setup and texture transport are implemented in Rust and
called through Dart FFI. There is no handwritten C or C++ browser bridge and no
embedded browser engine in the application bundle.

This package is currently a non-endorsed federated implementation. Applications
must depend on both packages:

```yaml
dependencies:
  webview_flutter: ^4.14.1
  webview_flutter_linux: ^0.1.0-dev.1
```

The generated Linux plugin registrant selects `WebViewFlutterLinux`
automatically. Application code continues to use the ordinary
`WebViewController` and `WebViewWidget` APIs from `webview_flutter`.

```dart
final controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setNavigationDelegate(
    NavigationDelegate(
      onProgress: (progress) {},
      onPageStarted: (url) {},
      onPageFinished: (url) {},
    ),
  )
  ..loadRequest(Uri.parse('https://flutter.dev'));

WebViewWidget(controller: controller);
```

## Linux requirements

The build currently requires a development package providing
`wpe-webkit-2.0.pc`, WPE WebKit 2.52 or newer, `libepoxy`, and the corresponding
WPE Web/Network process executables. For example, the WPE WebKit package is
named `wpewebkit` on Arch-based distributions.

The Rust library is compiled and bundled by Dart's native-assets build hook via
[`native_toolchain_rust`](https://pub.dev/packages/native_toolchain_rust).
The browser runtime remains a system dependency.

## Implemented surface

- GET navigation, HTML strings, local files, and Flutter text assets
- current URL, reload, and controller-managed back/forward history
- navigation decisions, URL changes, page start/finish, and progress callbacks
- resizing and HiDPI scaling
- pointer movement, primary/middle/secondary clicks, and wheel input
- common XKB keyboard input and shortcuts
- audio through WebKit/GStreamer
- bidirectional plain-text clipboard bridging
- Flutter-rendered context menus backed by WebKit actions
- multiple simultaneous `WebViewWidget`s with handle-scoped native state

## Current limitations

- JavaScript evaluation/channels, cookies, custom HTTP requests, IME
  composition, cursor updates, popups, rich clipboard formats, downloads,
  dialogs, permissions, accessibility, and crash recovery are not complete.
- Page completion is currently inferred from the first rendered frame. Native
  WebKit load/error events still need to be exposed through the event bridge.
- The runtime has been visibly validated on the current Intel/Mesa Wayland
  host. Broader GPU, display-server, and distribution validation remains.

## Development

```sh
flutter pub get
flutter analyze
flutter test
cd example
flutter pub get
flutter run -d linux
```
