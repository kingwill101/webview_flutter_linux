# webview_flutter_linux

An experimental, non-endorsed Linux implementation of Flutter's official
[`webview_flutter`](https://pub.dev/packages/webview_flutter) plugin, backed by
the WPE WebKit runtime installed on the host.

The package renders web content without embedding a GTK browser widget or
shipping a browser engine with the application. WPE renders off-screen into
DMA-BUFs, Rust copies those frames on the GPU into an application-owned EGL
texture, and Irondash publishes that texture to Flutter. Flutter input,
clipboard data, context-menu actions, and lifecycle state travel back through
the same Dart FFI bridge.

> [!IMPORTANT]
> This package is under active development. It is not published on pub.dev and
> does not yet implement the complete `webview_flutter` platform interface.

## Status

| Area | Current support |
| --- | --- |
| Flutter constraint | 3.38.0 or newer |
| Dart constraint | 3.10.0 or newer, but earlier than 4.0.0 |
| Operating system | Linux; currently validated on Wayland only |
| Architecture | x86-64 only in the current Rust toolchain manifest |
| Browser build floor | `wpe-webkit-2.0` version 2.52 or newer |
| Native delivery | `native_prebuilt` resolution with a Rust source fallback |
| Federated status | Non-endorsed implementation of `webview_flutter` |

## Installation

Until the first pub.dev release, GitHub collaborators with SSH access to the
private repository can use a Git dependency:

```yaml
dependencies:
  webview_flutter: ^4.14.1
  webview_flutter_linux:
    git:
      url: git@github.com:kingwill101/webview_flutter_linux.git
      ref: main
```

Pin `ref` to a commit SHA when reproducible application builds matter.

The generated Linux plugin registrant selects `WebViewFlutterLinux`
automatically. Application code should import and use `webview_flutter`, not
the Linux implementation package directly.

## System requirements

### Build dependencies

The current source-build path needs `rustup`, the exact Rust 1.95.0 toolchain
declared in `rust/rust-toolchain.toml`, `pkg-config`, WPE WebKit development
files that provide `wpe-webkit-2.0.pc`, and linkable libepoxy development files.
The WPE pkg-config metadata supplies the required GLib/GIO link configuration.

Verify the toolchain and native metadata before building:

```sh
(cd rust && rustc --version)
pkg-config --atleast-version=2.52 wpe-webkit-2.0
pkg-config --modversion wpe-webkit-2.0 glib-2.0 gio-2.0
```

Package names differ by distribution. On Arch-based systems, the WPE WebKit
package is named `wpewebkit`. The development package must provide
`wpe-webkit-2.0.pc`; installing only the runtime shared library is not enough
for the current source-build path.

The validated Arch/Manjaro setup can be installed with:

```sh
sudo pacman -S --needed wpewebkit libepoxy pkgconf rustup
```

For other distributions, consult WPE WebKit's [distribution package
list](https://wpewebkit.org/about/get-wpe.html) and verify the version with the
commands above. Debian, Ubuntu, Fedora, and other distribution recipes have not
yet been validated for this package.

### Runtime dependencies

The released application still needs the ABI-compatible WPE WebKit, libepoxy,
GLib, and GIO shared libraries. The WPE installation must include its matching
Web and Network process executables. Media playback additionally depends on the
GStreamer plugins required for the content being played. Distribution package
splits differ, so verify these components against the WPE package supplied by
the target distribution rather than assuming a package name is portable.

## Usage

Use the ordinary `WebViewController`, `NavigationDelegate`, and
`WebViewWidget` APIs. The following can be placed after Flutter binding
initialization; [`example/lib/main.dart`](example/lib/main.dart) contains a
complete application:

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

final controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setNavigationDelegate(
    NavigationDelegate(
      onProgress: (progress) {},
      onPageStarted: (url) {},
      onPageFinished: (url) {},
      onNavigationRequest: (request) => NavigationDecision.navigate,
    ),
  )
  ..loadRequest(Uri.parse('https://flutter.dev'));

class BrowserView extends StatelessWidget {
  const BrowserView({super.key});

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: controller);
  }
}
```

## How it works

Each mounted `WebViewWidget` has its own native view handle and Flutter texture:

1. The Dart controller obtains the current Flutter engine handle through
   Irondash.
2. The Dart build hook compiles and bundles the Rust code asset.
3. Rust creates a headless WPE view and registers an external texture with the
   Flutter engine.
4. WPE exports accelerated frames as DMA-BUFs.
5. Rust imports and copies the frame into an EGL texture owned by the
   application.
6. Flutter composites that texture with the rest of the widget tree.

The package bundles neither Chromium nor WPE WebKit. Browser code, media
support, and WPE subprocesses come from the host installation.

## Native artifact delivery

Prebuilt Rust libraries are **not currently published**. The build hook is
initialized with [`native_prebuilt`](https://pub.dev/packages/native_prebuilt)
for `linux-x64`, but the manifest intentionally contains no artifact hashes
until a release binary is produced. An unhashed artifact is never downloaded;
the hook instead compiles and bundles the bridge through
`native_toolchain_rust`.

Once populated, the manifest lets the hook download, verify, and cache a
matching Rust bridge while retaining the existing source fallback. A successful
prebuilt path removes Rust, `pkg-config`, and WPE/libepoxy development or
link-time artifacts from the consumer build, but it does not remove the system
WPE WebKit, libepoxy, GLib, or media runtime requirements.

Prebuilt artifacts will only be advertised after they are built against a
documented Linux ABI baseline and visibly tested on every published target.
While this repository is private, unauthenticated `native_prebuilt` downloads
from its GitHub release URL cannot succeed. The source fallback remains active;
automatic release downloads become available when the repository is public.

## Implemented

These code paths exist, but only the subset named in [Validation
snapshot](#validation-snapshot) has been exercised through visible interaction.

- GET navigation, HTML strings, local files, and Flutter text assets
- current URL, reload, and controller-managed back/forward history
- controller-initiated navigation decisions, URL changes, synthetic page
  start/finish events, and synthetic progress callbacks
- resizing and HiDPI scaling
- pointer movement, primary/middle/secondary clicks, and wheel input
- common XKB keyboard input and shortcuts
- audio through WPE WebKit and GStreamer
- bidirectional plain-text clipboard bridging
- Flutter-rendered context menus backed by native WebKit actions
- multiple simultaneous WebViews with handle-scoped native state

## Known limitations

- JavaScript is always enabled. Requesting `JavaScriptMode.disabled` throws;
  do not rely on this implementation to disable scripting for untrusted pages.
- JavaScript evaluation and channels are not implemented.
- Cookie APIs and custom HTTP request methods, headers, and bodies are not
  implemented.
- IME composition, cursor updates, popups, rich clipboard formats, downloads,
  dialogs, permissions, accessibility, and crash recovery are incomplete.
- Page completion is inferred from the first painted frame. Native WebKit
  load/error events are not yet exposed through the event bridge.
- Navigation callbacks and back/forward history only track
  controller-initiated navigation; page-driven links and redirects are not yet
  reflected in the Dart controller.
- Plain-text clipboard synchronization is bidirectional. Flutter copies the
  system clipboard into WPE when the WebView gains focus and before paste or
  secondary-click input; browser clipboard changes are polled and can overwrite
  the system clipboard. Applications handling sensitive clipboard data should
  account for this behavior.
- APIs not listed under [Implemented](#implemented) should be treated as
  unsupported even if they exist on the platform interface.

## Validation snapshot

The current interactive validation host is Manjaro Linux on x86-64 with
Wayland, Intel UHD Graphics (Comet Lake), Mesa 26.1.7, WPE WebKit 2.52.6,
Flutter 3.47.1, and Dart 3.13.1. Visible checks covered page rendering,
navigation, pointer and keyboard input, audio, plain-text clipboard transfer,
and context-menu actions.

Automated tests cover Dart-side registration, controller history/navigation
decisions, and keyboard mapping. They do not prove GPU, browser-process, audio,
clipboard, context-menu, HiDPI, lifecycle, or multi-view behavior, including on
the named validation host. Broader GPU, X11, architecture, and distribution
validation remains outstanding.

## Development

Fetch dependencies and run the Dart checks from the package root:

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
```

If an existing Flutter application does not have Linux scaffolding yet, create
it from that application's root before adding the dependencies:

```sh
flutter create --platforms=linux .
```

Run the example application on a host satisfying the system requirements:

```sh
cd example
flutter pub get
flutter run -d linux
```

Run the native checks separately:

```sh
cd rust
cargo fmt --check
cargo clippy --features wpe-runtime --all-targets -- -D warnings
cargo test --features wpe-runtime
```

Inspect and build the initialized prebuilt target from the package root:

```sh
dart run native_prebuilt doctor
dart run native_prebuilt plan --target linux-x64
dart run native_prebuilt build \
  --target linux-x64 \
  --output built-library \
  --from-source
```

After validating that binary against the documented Linux ABI baseline,
package it and generate its checksummed release lock:

```sh
dart run native_prebuilt manifest update \
  --config native_prebuilt.yaml \
  --output native_prebuilt.lock.yaml \
  --built-library-dir built-library \
  --release-assets-dir release-assets
dart run native_prebuilt manifest verify \
  --config native_prebuilt.yaml \
  --output native_prebuilt.lock.yaml \
  --built-library-dir built-library \
  --release-assets-dir release-assets
```

Publish the archive in `release-assets/` at the tag declared in
`native_prebuilt.yaml`, then commit the generated `native_prebuilt.lock.yaml`
with the matching package release. Do not commit a lock that refers to an
archive that consumers cannot download yet.

Maintainers can run the same checked release path on GitHub after pushing the
desired source revision:

```sh
gh workflow run native-release.yml \
  --ref main \
  -f tag=webview_flutter_linux-v0.1.0-dev.1
```

The workflow builds in an Arch Linux container, requires WPE WebKit 2.52 or
newer, rejects a bridge requiring symbols newer than `GLIBC_2.34`, verifies the
generated archive, and attaches both the archive and lock file to a GitHub
prerelease. Commit that exact lock file only after the release succeeds.

## License

`webview_flutter_linux` is available under the BSD 3-Clause License. See
[`LICENSE`](LICENSE).
