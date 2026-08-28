# webview_flutter_linux

An experimental, non-endorsed Linux implementation of Flutter's official
[`webview_flutter`](https://pub.dev/packages/webview_flutter) plugin. It uses
the WPE WebKit runtime installed on the host and renders web content into a
Flutter texture without embedding a GTK browser widget or bundling a browser
engine.

Add the official plugin and this Linux implementation to a Flutter app:

```yaml
dependencies:
  webview_flutter: ^4.14.1
  webview_flutter_linux: ^0.1.0-dev.2
```

## Usage

Use the standard `webview_flutter` API:

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

final controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..loadRequest(Uri.parse('https://flutter.dev'));

class BrowserView extends StatelessWidget {
  const BrowserView({super.key});

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: controller);
  }
}
```

See [`example/lib/main.dart`](example/lib/main.dart) for a complete example.

The host must provide WPE WebKit 2.52 or newer and its runtime dependencies.

## License

`webview_flutter_linux` is available under the BSD 3-Clause License. See
[`LICENSE`](LICENSE).
