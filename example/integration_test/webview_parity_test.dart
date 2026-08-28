// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requestedPaths = <String>[];
  unawaited(
    server.forEach((request) async {
      requestedPaths.add(request.uri.path);
      if (request.uri.path == '/headers') {
        request.response.headers.contentType = ContentType.text;
        request.response.write(
          jsonEncode(<String, Object?>{
            'method': request.method,
            'parity-header': request.headers.value('parity-header'),
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/http-error') {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.text;
        request.response.write('missing');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/http-basic-authentication') {
        final authorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        final authorized =
            authorization != null &&
            authorization.startsWith('Basic ') &&
            utf8.decode(base64Decode(authorization.substring(6))) ==
                'user:password';
        if (!authorized) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Basic realm="Linux parity"',
            );
        }
        request.response.headers.contentType = ContentType.text;
        request.response.write(authorized ? 'Authorized' : 'Unauthorized');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/download') {
        const payload = 'downloaded by WPE WebKit';
        request.response.headers
          ..contentType = ContentType.text
          ..set(
            'content-disposition',
            'attachment; filename="parity-download.txt"',
          );
        request.response.contentLength = payload.length;
        request.response.write(payload);
        await request.response.close();
        return;
      }
      if (request.uri.path == '/fullscreen') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<style>
  html, body, button { width: 100%; height: 100%; margin: 0; border: 0; }
</style>
<button id="fullscreen">Enter fullscreen</button>
<script>
  document.querySelector('#fullscreen').addEventListener('click', () => {
    window.__fullscreenButtonClicked = true;
    document.documentElement.requestFullscreen();
  });
</script>''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/display-capture') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<style>
  html, body, button { width: 100%; height: 100%; margin: 0; border: 0; }
</style>
<button id="capture">Share display</button>
<script>
  window.__displayCaptureResolved = false;
  window.__displayCaptureError = null;
  window.__displayCaptureTrackKinds = [];
  document.querySelector('#capture').addEventListener('click', async () => {
    window.__displayCaptureButtonClicked = true;
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({
        video: true
      });
      window.__displayCaptureTrackKinds = stream.getTracks()
        .filter(track => track.readyState === 'live')
        .map(track => track.kind)
        .sort();
      stream.getTracks().forEach(track => track.stop());
      window.__displayCaptureResolved = true;
    } catch (error) {
      window.__displayCaptureError = `${error.name}: ${error.message}`;
    }
  });
</script>''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/input') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<style>
  html, body { width: 100%; height: 100%; margin: 0; }
  input { box-sizing: border-box; width: 100%; height: 100%; font-size: 32px; }
</style>
<input id="editor" autocomplete="off">''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/javascript-mode') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<script>window.__pageScriptRan = true;</script>
<body onload="window.__markupHandlerRan = true"></body>''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/scroll') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<style>
  html, body { margin: 0; min-height: 4000px; }
  body { background: linear-gradient(#fff, #000); }
</style>''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/subframe-host') {
        final target = request.uri.queryParameters['target'] ?? 'about:blank';
        request.response.headers.contentType = ContentType.html;
        request.response.write('''<!doctype html>
<meta charset="utf-8">
<iframe id="child" src="${htmlEscape.convert(target)}"></iframe>''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/subframe-redirect') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/subframe-target');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/main-frame-redirect') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/secondary');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/main-frame-cross-site-redirect') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://localhost:${server.port}/secondary',
          );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/accessibility') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<style>button { width: 240px; height: 80px; }</style>
<button aria-label="Accessible parity control">Continue</button>
<script>
  document.querySelector('button').addEventListener('click', () => {
    window.__accessibleButtonActivated = true;
  });
</script>''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/clipboard') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<style>
  html, body { width: 100%; height: 100%; margin: 0; }
  input { box-sizing: border-box; width: 100%; height: 100%; font-size: 32px; }
</style>
<input id="clipboard-editor" autocomplete="off">''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/file-chooser') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<style>
  html, body { width: 100%; height: 100%; margin: 0; }
  input { width: 100%; height: 100%; }
</style>
<input id="file" type="file" accept="text/plain">''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/option-menu') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(r'''<!doctype html>
<meta charset="utf-8">
<style>
  html, body { width: 100%; height: 100%; margin: 0; }
  select { width: 100%; height: 100%; font-size: 32px; }
</style>
<select id="choice">
  <option value="one">First choice</option>
  <option value="two">Second choice</option>
</select>''');
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write('''<!doctype html>
<meta charset="utf-8">
<title>${request.uri.path}</title>
<body>${request.uri.path}</body>''');
      await request.response.close();
    }),
  );
  final origin = 'http://${server.address.address}:${server.port}';
  final primaryUrl = '$origin/primary';
  final secondaryUrl = '$origin/secondary';
  final crossSiteSecondaryUrl = 'http://localhost:${server.port}/secondary';
  final headersUrl = '$origin/headers';
  final httpErrorUrl = '$origin/http-error';
  final basicAuthUrl = '$origin/http-basic-authentication';

  // This certificate is intentionally self-signed and exists only to exercise
  // the federated TLS decision contract against a deterministic local origin.
  final certificate = await rootBundle.load('assets/test_tls_server_cert.pem');
  final privateKey = await rootBundle.load('assets/test_tls_server_key.pem');
  final securityContext = SecurityContext()
    ..useCertificateChainBytes(
      certificate.buffer.asUint8List(
        certificate.offsetInBytes,
        certificate.lengthInBytes,
      ),
    )
    ..usePrivateKeyBytes(
      privateKey.buffer.asUint8List(
        privateKey.offsetInBytes,
        privateKey.lengthInBytes,
      ),
    );
  final secureServer = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    securityContext,
  );
  unawaited(
    secureServer.forEach((request) async {
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/third-party-cookie') {
        final cookieName =
            request.uri.queryParameters['name'] ?? 'linuxThirdParty';
        request.response.headers.set(
          HttpHeaders.setCookieHeader,
          '$cookieName=accepted; Path=/; SameSite=None; Secure',
        );
        request.response.write('''<!doctype html>
<meta charset="utf-8">
<script>parent.postMessage(${jsonEncode(cookieName)}, '*');</script>''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/third-party-host') {
        final iframeUrl =
            request.uri.queryParameters['iframe'] ?? 'about:blank';
        request.response.write('''<!doctype html>
<meta charset="utf-8">
<script>window.__thirdPartyLoaded = null;</script>
<iframe id="third-party" src="${htmlEscape.convert(iframeUrl)}"></iframe>
<script>
  const thirdPartyFrame = document.querySelector('#third-party');
  thirdPartyFrame.addEventListener('load', () => {
    window.__thirdPartyLoaded =
      new URL(thirdPartyFrame.src).searchParams.get('name');
  });
</script>''');
        await request.response.close();
        return;
      }
      request.response.write(
        '<!doctype html><title>TLS parity</title><body>trusted locally</body>',
      );
      await request.response.close();
    }),
  );
  final tlsUrl =
      'https://${secureServer.address.address}:${secureServer.port}/secure';
  final tlsLocalhostOrigin = 'https://localhost:${secureServer.port}';

  tearDownAll(() async {
    await Future.wait<void>([
      server.close(force: true),
      secureServer.close(force: true),
    ]);
  });

  group('official webview_flutter runtime baseline', () {
    testWidgets('custom request headers reach the main resource', (
      tester,
    ) async {
      final pageFinished = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!pageFinished.isCompleted) pageFinished.complete();
          },
        ),
      );

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await controller.loadRequest(
        Uri.parse(headersUrl),
        headers: const <String, String>{'parity-header': 'linux-wpe'},
      );
      await pageFinished.future.timeout(const Duration(seconds: 10));

      expect(
        await controller.runJavaScriptReturningResult(
          'document.documentElement.innerText',
        ),
        contains('linux-wpe'),
      );
    });

    testWidgets('JavaScript channels deliver browser messages to Dart', (
      tester,
    ) async {
      final pageFinished = Completer<void>();
      final message = Completer<String>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'ParityChannel',
        onMessageReceived: (event) {
          if (!message.isCompleted) message.complete(event.message);
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
      );
      await controller.loadHtmlString('<!doctype html><title>channel</title>');

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      await controller.runJavaScript(
        'ParityChannel.postMessage("message from WPE");',
      );

      expect(
        await message.future.timeout(const Duration(seconds: 10)),
        'message from WPE',
      );
    });

    testWidgets('cyclic console values retain their serializable structure', (
      tester,
    ) async {
      final pageFinished = Completer<void>();
      final consoleMessage = Completer<JavaScriptConsoleMessage>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setOnConsoleMessage((message) {
        if (!consoleMessage.isCompleted) consoleMessage.complete(message);
      });
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
      );
      await controller.loadRequest(Uri.parse(primaryUrl));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      await controller.runJavaScript(r'''
        const obj1 = {name: 'obj1'};
        const obj2 = {name: 'obj2', obj1};
        const obj = {obj1, obj2};
        obj.self = obj;
        console.log(obj);
      ''');

      final message = await consoleMessage.future.timeout(
        const Duration(seconds: 10),
      );
      expect(message.level, JavaScriptLogLevel.log);
      expect(
        message.message,
        '{"obj1":{"name":"obj1"},'
        '"obj2":{"name":"obj2","obj1":{"name":"obj1"}}}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('JavaScript dialogs resolve through Flutter callbacks', (
      tester,
    ) async {
      final pageFinished = Completer<void>();
      final alertRequest = Completer<JavaScriptAlertDialogRequest>();
      final confirmRequest = Completer<JavaScriptConfirmDialogRequest>();
      final promptRequest = Completer<JavaScriptTextInputDialogRequest>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setOnJavaScriptAlertDialog((request) async {
        if (!alertRequest.isCompleted) alertRequest.complete(request);
      });
      await controller.setOnJavaScriptConfirmDialog((request) async {
        if (!confirmRequest.isCompleted) confirmRequest.complete(request);
        return false;
      });
      await controller.setOnJavaScriptTextInputDialog((request) async {
        if (!promptRequest.isCompleted) promptRequest.complete(request);
        return 'Flutter response';
      });
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
      );
      await controller.loadHtmlString('<!doctype html><title>dialogs</title>');

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));

      await controller.runJavaScript('alert("Alert from WPE");');
      final alert = await alertRequest.future.timeout(
        const Duration(seconds: 10),
      );
      expect(alert.message, 'Alert from WPE');

      await controller.runJavaScript(
        'window.__confirmResult = confirm("Confirm from WPE");',
      );
      final confirm = await confirmRequest.future.timeout(
        const Duration(seconds: 10),
      );
      expect(confirm.message, 'Confirm from WPE');
      expect(
        await controller.runJavaScriptReturningResult('window.__confirmResult'),
        isFalse,
      );

      await controller.runJavaScript(
        'window.__promptResult = prompt("Prompt from WPE", "Default value");',
      );
      final prompt = await promptRequest.future.timeout(
        const Duration(seconds: 10),
      );
      expect(prompt.message, 'Prompt from WPE');
      expect(prompt.defaultText, 'Default value');
      expect(
        await controller.runJavaScriptReturningResult('window.__promptResult'),
        _javaScriptString('Flutter response'),
      );
    });

    testWidgets('resizing the Flutter surface resizes the CSS viewport', (
      tester,
    ) async {
      final pageFinished = Completer<void>();
      final resized = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      var resizeRequested = false;
      await controller.addJavaScriptChannel(
        'Resize',
        onMessageReceived: (_) {
          if (resizeRequested && !resized.isCompleted) resized.complete();
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
      );
      await controller.loadHtmlString('''<!doctype html>
<meta name="viewport" content="width=device-width">
<script>
  addEventListener('resize', () => Resize.postMessage('resized'));
</script>''');

      var size = const Size(320, 240);
      late StateSetter setHarnessState;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setHarnessState = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: WebViewWidget(controller: controller),
                ),
              );
            },
          ),
        ),
      );
      await pageFinished.future.timeout(const Duration(seconds: 10));
      // The asynchronous renderer attachment schedules the first interactive
      // surface build. Widget tests must explicitly render that pending frame
      // before its post-frame native resize can run.
      await tester.pump();
      await _waitForJavaScriptTrue(
        controller,
        'window.innerWidth === 320 && window.innerHeight === 240',
      );

      resizeRequested = true;
      setHarnessState(() => size = const Size(500, 360));
      await tester.pump();
      await resized.future.timeout(const Duration(seconds: 10));
      await _waitForJavaScriptTrue(
        controller,
        'window.innerWidth === 500 && window.innerHeight === 360',
      );
    });

    testWidgets('custom user agent and document title use native values', (
      tester,
    ) async {
      final pageFinished = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setUserAgent('webview_flutter_linux parity agent');
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
      );
      await controller.loadHtmlString(
        '<!doctype html><title>Linux parity title</title>',
      );

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      await controller.runJavaScript('1;');

      expect(
        await controller.getUserAgent(),
        'webview_flutter_linux parity agent',
      );
      expect(await controller.getTitle(), 'Linux parity title');
    });

    testWidgets('audio autoplay follows the configured gesture policy', (
      tester,
    ) async {
      final audioData = await rootBundle.load('assets/sample_audio.ogg');
      final audioBase64 = base64Encode(
        audioData.buffer.asUint8List(
          audioData.offsetInBytes,
          audioData.lengthInBytes,
        ),
      );
      final html =
          '''<!doctype html>
<audio id="audio" src="data:audio/ogg;base64,$audioBase64"></audio>
<script>
  window.__autoplaySettled = false;
  window.__autoplayStarted = false;
  addEventListener('load', () => {
    document.querySelector('#audio').play().then(() => {
      window.__autoplayStarted = true;
      window.__autoplaySettled = true;
    }).catch(() => {
      window.__autoplayStarted = false;
      window.__autoplaySettled = true;
    });
  });
</script>''';

      final allowedFinished = Completer<void>();
      final allowedController = _controllerForTest(tester);
      await allowedController.setJavaScriptMode(JavaScriptMode.unrestricted);
      await (allowedController.platform as LinuxWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
      await allowedController.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => allowedFinished.complete()),
      );
      await allowedController.loadHtmlString(html);
      await tester.pumpWidget(_ParityHarness(controller: allowedController));
      await allowedFinished.future.timeout(const Duration(seconds: 10));
      await _waitForJavaScriptTrue(
        allowedController,
        'window.__autoplaySettled === true',
      );
      expect(
        await allowedController.runJavaScriptReturningResult(
          'window.__autoplayStarted',
        ),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      final blockedFinished = Completer<void>();
      final blockedController = _controllerForTest(tester);
      await blockedController.setJavaScriptMode(JavaScriptMode.unrestricted);
      await blockedController.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => blockedFinished.complete()),
      );
      await blockedController.loadHtmlString(html);
      await tester.pumpWidget(_ParityHarness(controller: blockedController));
      await blockedFinished.future.timeout(const Duration(seconds: 10));
      await _waitForJavaScriptTrue(
        blockedController,
        'window.__autoplaySettled === true',
      );
      expect(
        await blockedController.runJavaScriptReturningResult(
          'window.__autoplayStarted',
        ),
        isFalse,
      );
    });

    testWidgets('programmatic scrolling updates position and callback', (
      tester,
    ) async {
      final pageFinished = Completer<void>();
      final controller = _controllerForTest(tester);
      ScrollPositionChange? reportedPosition;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setOnScrollPositionChange((position) {
        reportedPosition = position;
      });
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
      );
      await controller.loadHtmlString('''<!doctype html>
<style>html, body { margin: 0; width: 5000px; height: 5000px; }</style>''');

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      await controller.scrollTo(123, 321);
      await _waitForScrollPosition(controller, const Offset(123, 321));
      await controller.scrollBy(123, 321);
      await _waitForScrollPosition(controller, const Offset(246, 642));
      await _waitForControllerTrue(
        () async => reportedPosition?.x == 246 && reportedPosition?.y == 642,
        'scroll callback',
      );

      expect(reportedPosition?.x, 246);
      expect(reportedPosition?.y, 642);
    });

    testWidgets('asynchronous navigation decisions allow and prevent loads', (
      tester,
    ) async {
      var pageFinished = Completer<void>();
      NavigationRequest? blockedRequest;
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!pageFinished.isCompleted) pageFinished.complete();
          },
          onNavigationRequest: (request) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            if (request.url == secondaryUrl) blockedRequest = request;
            return request.url == secondaryUrl
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
        ),
      );
      await controller.loadRequest(Uri.parse(primaryUrl));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      pageFinished = Completer<void>();
      await controller.runJavaScript('location.href = "$secondaryUrl";');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await controller.currentUrl(), primaryUrl);
      expect(pageFinished.isCompleted, isFalse);
      expect(blockedRequest?.isMainFrame, isTrue);
    });

    testWidgets('HTTP failures reach the federated navigation delegate', (
      tester,
    ) async {
      final responseError = Completer<HttpResponseError>();
      final controller = _controllerForTest(tester);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onHttpError: (error) {
            if (!responseError.isCompleted) responseError.complete(error);
          },
        ),
      );
      await controller.loadRequest(Uri.parse(httpErrorUrl));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      final error = await responseError.future.timeout(
        const Duration(seconds: 10),
      );
      expect(error.response?.statusCode, HttpStatus.notFound);
    });

    testWidgets('main-resource failures report WebResourceError', (
      tester,
    ) async {
      final unavailableServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final unavailableUrl =
          'http://${unavailableServer.address.address}:'
          '${unavailableServer.port}/unavailable';
      await unavailableServer.close(force: true);

      final resourceError = Completer<WebResourceError>();
      final controller = _controllerForTest(tester);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (!resourceError.isCompleted) resourceError.complete(error);
          },
        ),
      );
      await controller.loadRequest(Uri.parse(unavailableUrl));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      final error = await resourceError.future.timeout(
        const Duration(seconds: 10),
      );
      expect(error.isForMainFrame, isTrue);
      expect(error.url, unavailableUrl);
    });

    testWidgets('HTTP basic authentication accepts Flutter credentials', (
      tester,
    ) async {
      final pageFinished = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onHttpAuthRequest: (request) => request.onProceed(
            const WebViewCredential(user: 'user', password: 'password'),
          ),
          onPageFinished: (_) {
            if (!pageFinished.isCompleted) pageFinished.complete();
          },
          onWebResourceError: (error) =>
              fail('Authentication failed: ${error.description}'),
        ),
      );
      await controller.loadRequest(Uri.parse(basicAuthUrl));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      expect(await controller.currentUrl(), basicAuthUrl);
    });

    testWidgets('TLS failures can be cancelled and explicitly trusted', (
      tester,
    ) async {
      final firstError = Completer<SslAuthError>();
      final secondError = Completer<SslAuthError>();
      final pageFinished = Completer<void>();
      var errorCount = 0;
      final controller = _controllerForTest(tester);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onSslAuthError: (error) {
            errorCount += 1;
            if (errorCount == 1) {
              firstError.complete(error);
            } else if (errorCount == 2) {
              secondError.complete(error);
            }
          },
          onPageFinished: (url) {
            if (url == tlsUrl && !pageFinished.isCompleted) {
              pageFinished.complete();
            }
          },
        ),
      );
      await controller.loadRequest(Uri.parse(tlsUrl));
      await tester.pumpWidget(_ParityHarness(controller: controller));

      final cancelledError = await firstError.future.timeout(
        const Duration(seconds: 10),
      );
      final cancelledLinuxError = cancelledError.platform as LinuxSslAuthError;
      expect(cancelledLinuxError.url, tlsUrl);
      expect(cancelledLinuxError.errorFlags, isNot(0));
      expect(cancelledLinuxError.description, isNotEmpty);
      expect(cancelledError.certificate?.data, isNotEmpty);
      await cancelledError.cancel();
      expect(cancelledLinuxError.isResolved, isTrue);
      expect(
        await Future.any<bool>([
          pageFinished.future.then((_) => true),
          Future<bool>.delayed(const Duration(milliseconds: 250), () => false),
        ]),
        isFalse,
      );

      await controller.loadRequest(Uri.parse(tlsUrl));
      final trustedError = await secondError.future.timeout(
        const Duration(seconds: 10),
      );
      await trustedError.proceed();
      await pageFinished.future.timeout(const Duration(seconds: 10));
      expect(
        await controller.runJavaScriptReturningResult(
          'document.body.textContent',
        ),
        _javaScriptString('trusted locally'),
      );
    });

    testWidgets('clearLocalStorage removes data from the current origin', (
      tester,
    ) async {
      var pageFinished = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!pageFinished.isCompleted) pageFinished.complete();
          },
        ),
      );
      await controller.loadRequest(Uri.parse(primaryUrl));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      await controller.runJavaScript('localStorage.setItem("parity", "set");');
      expect(
        await controller.runJavaScriptReturningResult(
          'localStorage.getItem("parity")',
        ),
        _javaScriptString('set'),
      );

      await controller.clearLocalStorage();
      pageFinished = Completer<void>();
      await controller.reload();
      await pageFinished.future.timeout(const Duration(seconds: 10));
      expect(
        await controller.runJavaScriptReturningResult(
          'localStorage.getItem("parity")',
        ),
        'null',
      );
    });

    testWidgets('clearCache removes Cache API entries', (tester) async {
      final pageFinished = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
      );
      await controller.loadRequest(Uri.parse(primaryUrl));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      await controller.runJavaScript(r'''
        window.__cacheWriteFinished = false;
        caches.open('webview-flutter-linux-parity')
          .then(cache => cache.put('/parity-cache-entry', new Response('set')))
          .then(() => { window.__cacheWriteFinished = true; });
      ''');
      await _waitForJavaScriptTrue(
        controller,
        'window.__cacheWriteFinished === true',
      );

      await controller.clearCache();
      await controller.runJavaScript(r'''
        window.__cacheCheckFinished = false;
        window.__cacheStillPresent = true;
        caches.has('webview-flutter-linux-parity').then(present => {
          window.__cacheStillPresent = present;
          window.__cacheCheckFinished = true;
        });
      ''');
      await _waitForJavaScriptTrue(
        controller,
        'window.__cacheCheckFinished === true',
      );
      expect(
        await controller.runJavaScriptReturningResult(
          'window.__cacheStillPresent',
        ),
        isFalse,
      );
    });
  });

  testWidgets('History API URL changes reach the federated controller', (
    tester,
  ) async {
    final pageFinished = Completer<void>();
    final historyUrlChanged = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!pageFinished.isCompleted) pageFinished.complete();
        },
        onUrlChange: (change) {
          if (change.url == secondaryUrl && !historyUrlChanged.isCompleted) {
            historyUrlChanged.complete();
          }
        },
      ),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));

    await controller.runJavaScript(
      'history.pushState(null, "", "$secondaryUrl");',
    );
    await historyUrlChanged.future.timeout(const Duration(seconds: 10));

    expect(await controller.currentUrl(), secondaryUrl);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('main-frame redirects finish and allow the next host load', (
    tester,
  ) async {
    var pageFinished = Completer<String>();
    final requestedUrls = <String>[];
    final controller = _controllerForTest(tester);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.isMainFrame) requestedUrls.add(request.url);
          return NavigationDecision.navigate;
        },
        onPageFinished: (url) {
          if (!pageFinished.isCompleted) pageFinished.complete(url);
        },
      ),
    );

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await controller.loadRequest(Uri.parse('$origin/main-frame-redirect'));
    expect(
      await pageFinished.future.timeout(const Duration(seconds: 10)),
      secondaryUrl,
    );
    expect(await controller.currentUrl(), secondaryUrl);

    pageFinished = Completer<String>();
    await controller.loadRequest(Uri.parse(primaryUrl));
    expect(
      await pageFinished.future.timeout(const Duration(seconds: 10)),
      primaryUrl,
    );
    expect(await controller.currentUrl(), primaryUrl);
    expect(
      requestedUrls,
      containsAllInOrder(<String>[
        '$origin/main-frame-redirect',
        secondaryUrl,
        primaryUrl,
      ]),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cross-site main-frame redirects finish in the new process', (
    tester,
  ) async {
    final pageFinished = Completer<String>();
    final mainFrameRequests = <String>[];
    final controller = _controllerForTest(tester);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.isMainFrame) mainFrameRequests.add(request.url);
          return NavigationDecision.navigate;
        },
        onPageFinished: (url) {
          if (!pageFinished.isCompleted) pageFinished.complete(url);
        },
      ),
    );

    await tester.pumpWidget(_ParityHarness(controller: controller));
    final redirectUrl = '$origin/main-frame-cross-site-redirect';
    await controller.loadRequest(Uri.parse(redirectUrl));

    expect(
      await pageFinished.future.timeout(const Duration(seconds: 10)),
      crossSiteSecondaryUrl,
    );
    expect(await controller.currentUrl(), crossSiteSecondaryUrl);
    expect(
      mainFrameRequests,
      containsAllInOrder(<String>[redirectUrl, crossSiteSecondaryUrl]),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('navigation decisions identify subframe requests', (
    tester,
  ) async {
    final pageFinished = Completer<void>();
    final subframeDecision = Completer<NavigationRequest>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!pageFinished.isCompleted) pageFinished.complete();
        },
        onNavigationRequest: (request) {
          if (Uri.parse(request.url).path == '/subframe-target' &&
              !subframeDecision.isCompleted) {
            subframeDecision.complete(request);
          }
          return NavigationDecision.navigate;
        },
      ),
    );
    await controller.loadRequest(Uri.parse('$origin/subframe-host'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript(
      "document.querySelector('#child').src = "
      "${_javaScriptString('$origin/subframe-target')}",
    );
    final request = await subframeDecision.future.timeout(
      const Duration(seconds: 10),
    );
    expect(request.isMainFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'initial subframe decisions survive disabled page JavaScript and redirects',
    (tester) async {
      final subframeRequests = <NavigationRequest>[];
      final finalSubframeDecision = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final path = Uri.parse(request.url).path;
            if (path == '/subframe-redirect' || path == '/subframe-target') {
              subframeRequests.add(request);
              if (path == '/subframe-target' &&
                  !finalSubframeDecision.isCompleted) {
                finalSubframeDecision.complete();
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      );
      final hostUri = Uri.parse('$origin/subframe-host').replace(
        queryParameters: <String, String>{
          'target': '$origin/subframe-redirect',
        },
      );
      await controller.loadRequest(hostUri);

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await finalSubframeDecision.future.timeout(const Duration(seconds: 10));
      expect(
        subframeRequests.map((request) => request.isMainFrame),
        everyElement(isFalse),
      );
      expect(
        subframeRequests.map((request) => Uri.parse(request.url).path),
        containsAllInOrder(<String>['/subframe-redirect', '/subframe-target']),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'prevented subframe navigation is cancelled before network dispatch',
    (tester) async {
      requestedPaths.removeWhere((path) => path == '/subframe-target');
      final subframeDecision = Completer<NavigationRequest>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (Uri.parse(request.url).path == '/subframe-target') {
              if (!subframeDecision.isCompleted) {
                subframeDecision.complete(request);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
      final hostUri = Uri.parse('$origin/subframe-host').replace(
        queryParameters: <String, String>{'target': '$origin/subframe-target'},
      );
      await controller.loadRequest(hostUri);

      await tester.pumpWidget(_ParityHarness(controller: controller));
      final request = await subframeDecision.future.timeout(
        const Duration(seconds: 10),
      );
      expect(request.isMainFrame, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requestedPaths, isNot(contains('/subframe-target')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disabled JavaScript classifies data URL subframe navigation', (
    tester,
  ) async {
    const dataUrl = 'data:text/html,%3Ctitle%3Esubframe%3C/title%3E';
    final subframeDecision = Completer<NavigationRequest>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.disabled);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.url == dataUrl && !subframeDecision.isCompleted) {
            subframeDecision.complete(request);
          }
          return NavigationDecision.navigate;
        },
      ),
    );
    final hostUri = Uri.parse(
      '$origin/subframe-host',
    ).replace(queryParameters: <String, String>{'target': dataUrl});
    await controller.loadRequest(hostUri);

    await tester.pumpWidget(_ParityHarness(controller: controller));
    final request = await subframeDecision.future.timeout(
      const Duration(seconds: 10),
    );
    expect(request.isMainFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'prevented data subframe is stopped before its document commits',
    (tester) async {
      requestedPaths.removeWhere((path) => path == '/data-subframe-committed');
      final dataUrl = Uri.dataFromString(
        '<img src="$origin/data-subframe-committed">',
        mimeType: 'text/html',
      ).toString();
      final subframeDecision = Completer<NavigationRequest>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url == dataUrl) {
              if (!subframeDecision.isCompleted) {
                subframeDecision.complete(request);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
      final hostUri = Uri.parse(
        '$origin/subframe-host',
      ).replace(queryParameters: <String, String>{'target': dataUrl});
      await controller.loadRequest(hostUri);

      await tester.pumpWidget(_ParityHarness(controller: controller));
      final request = await subframeDecision.future.timeout(
        const Duration(seconds: 10),
      );
      expect(request.isMainFrame, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requestedPaths, isNot(contains('/data-subframe-committed')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disabled JavaScript classifies local-file subframe navigation', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'webview-flutter-linux-frame-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final child = File('${directory.path}/child.html');
    final host = File('${directory.path}/host.html');
    await child.writeAsString('<title>local child</title>');
    await host.writeAsString(
      '<iframe src="${htmlEscape.convert(child.uri.toString())}"></iframe>',
    );
    final subframeDecision = Completer<NavigationRequest>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.disabled);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.url == child.uri.toString() &&
              !subframeDecision.isCompleted) {
            subframeDecision.complete(request);
          }
          return NavigationDecision.navigate;
        },
      ),
    );
    await controller.loadFile(host.path);

    await tester.pumpWidget(_ParityHarness(controller: controller));
    final request = await subframeDecision.future.timeout(
      const Duration(seconds: 10),
    );
    expect(request.isMainFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'disabled JavaScript classifies unsupported-scheme subframe navigation',
    (tester) async {
      const childUrl = 'webview-flutter-linux-probe://subframe-target';
      final subframeDecision = Completer<NavigationRequest>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url == childUrl && !subframeDecision.isCompleted) {
              subframeDecision.complete(request);
            }
            return request.url == childUrl
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
        ),
      );
      final hostUri = Uri.parse(
        '$origin/subframe-host',
      ).replace(queryParameters: <String, String>{'target': childUrl});
      await controller.loadRequest(hostUri);

      await tester.pumpWidget(_ParityHarness(controller: controller));
      final request = await subframeDecision.future.timeout(
        const Duration(seconds: 10),
      );
      expect(request.isMainFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'disabled content JavaScript preserves host JavaScript evaluation',
    (tester) async {
      final pageFinished = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!pageFinished.isCompleted) pageFinished.complete();
          },
        ),
      );
      await controller.loadRequest(Uri.parse('$origin/javascript-mode'));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      expect(
        await controller.runJavaScriptReturningResult(
          '[typeof window.__pageScriptRan, '
          'typeof window.__markupHandlerRan]',
        ),
        <Object?>['undefined', 'undefined'],
      );
      await controller.runJavaScript('window.__hostEvaluationRan = true;');
      expect(
        await controller.runJavaScriptReturningResult(
          'window.__hostEvaluationRan',
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('window.open navigates the current view and preserves history', (
    tester,
  ) async {
    var pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));

    pageFinished = Completer<void>();
    await controller.runJavaScript('window.open("$secondaryUrl", "_blank")');
    await pageFinished.future.timeout(const Duration(seconds: 10));
    expect(await controller.currentUrl(), secondaryUrl);
    expect(await controller.canGoBack(), isTrue);

    pageFinished = Completer<void>();
    await controller.goBack();
    await pageFinished.future.timeout(const Duration(seconds: 10));
    expect(await controller.currentUrl(), primaryUrl);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('accepted related WebViews render, interact, and close', (
    tester,
  ) async {
    final popupCreated = Completer<LinuxWebViewPopupRequest>();
    final primaryFinished = Completer<void>();
    final primaryController = _controllerForTest(tester);
    final primaryPlatform =
        primaryController.platform as LinuxWebViewController;
    await primaryPlatform.setOnCreateWindow((request) {
      if (!popupCreated.isCompleted) popupCreated.complete(request);
      return true;
    });
    await primaryController.setJavaScriptMode(JavaScriptMode.unrestricted);
    await primaryController.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => primaryFinished.complete()),
    );
    await primaryController.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: primaryController));
    await primaryFinished.future.timeout(const Duration(seconds: 10));
    await primaryController.runJavaScript(
      'window.open("$secondaryUrl", "_blank")',
    );
    final popupRequest = await popupCreated.future.timeout(
      const Duration(seconds: 10),
    );
    final popupController = WebViewController.fromPlatform(
      popupRequest.platformController,
    );
    var popupMounted = false;
    addTearDown(() async {
      if (popupMounted) {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      popupRequest.dispose();
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_ParityHarness(controller: popupController));
    popupMounted = true;
    // The adopted native renderer already exists, but its Flutter attachment
    // still completes asynchronously. Render that pending frame so the
    // texture-backed Listener, rather than the temporary loading surface,
    // receives the visible interaction below.
    await tester.pump(const Duration(milliseconds: 200));
    await _waitForControllerTrue(
      () async => await popupController.currentUrl() == secondaryUrl,
      'related WebView URL',
    );
    await _waitForControllerTrue(
      () async => await popupController.getTitle() == '/secondary',
      'related WebView title',
    );
    await popupController.runJavaScript(r'''
      document.body.innerHTML = `
        <button id="popup-action" style="width:100%;height:100vh">
          Activate popup
        </button>`;
      document.querySelector('#popup-action').addEventListener('click', () => {
        window.__popupActivated = true;
      });
    ''');
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForJavaScriptTrue(
      popupController,
      'window.__popupActivated === true',
    );

    await popupController.runJavaScript('window.close()');
    await popupRequest.onCloseRequested.timeout(const Duration(seconds: 10));
    expect(popupRequest.isCloseRequested, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    popupMounted = false;
    popupRequest.dispose();
  });

  testWidgets('controller state and input survive widget remounting', (
    tester,
  ) async {
    var pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!pageFinished.isCompleted) pageFinished.complete();
        },
      ),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    pageFinished = Completer<void>();
    await controller.loadRequest(Uri.parse(secondaryUrl));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    pageFinished = Completer<void>();
    await controller.goBack();
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript(r'''
      document.body.style.margin = '0';
      document.body.style.minHeight = '4000px';
      document.body.innerHTML = `
        <button id="remount-action" style="
          position:fixed;inset:0;width:100%;height:100vh
        ">Activate remounted view</button>`;
      window.__remountValue = 'preserved';
      window.__remountClicks = 0;
      document.querySelector('#remount-action').addEventListener('click', () => {
        window.__remountClicks += 1;
      });
    ''');
    await controller.scrollTo(0, 640);
    await _waitForScrollPosition(controller, const Offset(0, 640));
    expect(await controller.canGoForward(), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    await controller.runJavaScript('window.__detachedMutation = true;');
    expect(await controller.getScrollPosition(), const Offset(0, 640));
    expect(
      await controller.runJavaScriptReturningResult(
        'window.__remountValue === "preserved" && '
        'window.__detachedMutation === true',
      ),
      isTrue,
    );

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await tester.pump(const Duration(milliseconds: 200));
    expect(await controller.currentUrl(), primaryUrl);
    expect(await controller.canGoForward(), isTrue);
    await _waitForScrollPosition(controller, const Offset(0, 640));
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForJavaScriptTrue(controller, 'window.__remountClicks === 1');

    pageFinished = Completer<void>();
    await controller.goForward();
    await pageFinished.future.timeout(const Duration(seconds: 10));
    expect(await controller.currentUrl(), secondaryUrl);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('controller state and input survive app backgrounding', (
    tester,
  ) async {
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript(r'''
      document.body.style.margin = '0';
      document.body.style.minHeight = '4000px';
      document.body.innerHTML = `
        <button id="resume-action" style="
          position:fixed;inset:0;width:100%;height:100vh
        ">Activate resumed view</button>`;
      window.__backgroundValue = 'preserved';
      window.__resumeClicks = 0;
      document.querySelector('#resume-action').addEventListener('click', () => {
        window.__resumeClicks += 1;
      });
    ''');
    await controller.scrollTo(0, 720);
    await _waitForScrollPosition(controller, const Offset(0, 720));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 200));
    await controller.runJavaScript('window.__backgroundMutation = true;');
    expect(await controller.getScrollPosition(), const Offset(0, 720));
    expect(
      await controller.runJavaScriptReturningResult(
        'window.__backgroundValue === "preserved" && '
        'window.__backgroundMutation === true',
      ),
      isTrue,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));
    await _waitForScrollPosition(controller, const Offset(0, 720));
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForJavaScriptTrue(controller, 'window.__resumeClicks === 1');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mouse side buttons traverse native browser history', (
    tester,
  ) async {
    var pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!pageFinished.isCompleted) pageFinished.complete();
        },
      ),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump();
    pageFinished = Completer<void>();
    await controller.loadRequest(Uri.parse(secondaryUrl));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await _waitForControllerTrue(controller.canGoBack, 'canGoBack');

    pageFinished = Completer<void>();
    await _clickMouseButton(
      tester,
      tester.getCenter(find.byType(WebViewWidget)),
      kBackMouseButton,
    );
    await pageFinished.future.timeout(const Duration(seconds: 10));
    expect(await controller.currentUrl(), primaryUrl);
    await _waitForControllerTrue(controller.canGoForward, 'canGoForward');

    pageFinished = Completer<void>();
    await _clickMouseButton(
      tester,
      tester.getCenter(find.byType(WebViewWidget)),
      kForwardMouseButton,
    );
    await pageFinished.future.timeout(const Duration(seconds: 10));
    expect(await controller.currentUrl(), secondaryUrl);
  });

  testWidgets('JavaScript strings and null match the non-WKWebView contract', (
    tester,
  ) async {
    var pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));

    await controller.runJavaScript('localStorage.setItem("pet", "Tom")');
    expect(
      await controller.runJavaScriptReturningResult(
        'localStorage.getItem("pet")',
      ),
      '"Tom"',
    );

    await controller.clearLocalStorage();
    pageFinished = Completer<void>();
    await controller.reload();
    await pageFinished.future.timeout(const Duration(seconds: 10));
    expect(
      await controller.runJavaScriptReturningResult(
        'localStorage.getItem("pet")',
      ),
      'null',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('local files can load sibling resources', (tester) async {
    final directory = await Directory.systemTemp.createTemp(
      'webview_flutter_linux_file_parity.',
    );
    addTearDown(() => directory.delete(recursive: true));
    final script = File('${directory.path}/title.js');
    final html = File('${directory.path}/index.html');
    await script.writeAsString(
      'document.title = "Sibling resource loaded";',
      flush: true,
    );
    await html.writeAsString('''<!doctype html>
<meta charset="utf-8">
<title>Sibling resource missing</title>
<script src="title.js"></script>''', flush: true);

    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadFile(html.path);

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));

    // The native finished event describes the main document. Give the linked
    // script's observable side effect its own condition instead of assuming
    // it has already reached Dart in the same pump cycle.
    await _waitForJavaScriptTrue(
      controller,
      'document.title === "Sibling resource loaded"',
    );
    expect(await controller.getTitle(), 'Sibling resource loaded');
    expect(await controller.currentUrl(), Uri.file(html.path).toString());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('packaged Flutter assets load their linked resources', (
    tester,
  ) async {
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadFlutterAsset('assets/secondary/index.html');

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));

    expect(await controller.getTitle(), 'Independent WebView');
    expect(
      await controller.runJavaScriptReturningResult(r'''
        [
          document.querySelector('link[rel="stylesheet"]')?.sheet !== null,
          document.querySelector('img')?.complete === true
        ]
      '''),
      <Object>[true, true],
    );
    expect(await controller.currentUrl(), startsWith('file:'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the shared cookie manager and page observe the same store', (
    tester,
  ) async {
    final manager = WebViewCookieManager();
    await manager.clearCookies();
    await manager.setCookie(
      WebViewCookie(
        name: 'linuxParity',
        value: 'round-trip',
        domain: server.address.address,
      ),
    );
    final cookieUrl = Uri.parse(primaryUrl);
    expect(
      await manager.getCookies(domain: cookieUrl),
      contains(
        isA<WebViewCookie>()
            .having((cookie) => cookie.name, 'name', 'linuxParity')
            .having((cookie) => cookie.value, 'value', 'round-trip'),
      ),
    );

    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(cookieUrl);

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    expect(
      await controller.runJavaScriptReturningResult(
        'document.cookie.includes("linuxParity=round-trip")',
      ),
      isTrue,
    );

    expect(await manager.clearCookies(), isTrue);
    expect(await manager.getCookies(domain: cookieUrl), isEmpty);
    expect(
      await controller.runJavaScriptReturningResult(
        'document.cookie.includes("linuxParity=round-trip")',
      ),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('third-party cookie policy controls secure cross-site frames', (
    tester,
  ) async {
    final manager = WebViewCookieManager();
    final linuxManager = manager.platform as LinuxWebViewCookieManager;
    final originalItp = await linuxManager
        .isIntelligentTrackingPreventionEnabled();
    if (originalItp) {
      await linuxManager.setIntelligentTrackingPreventionEnabled(false);
    }
    final originalPolicy = await linuxManager.getCookieAcceptPolicy();
    addTearDown(() async {
      await manager.clearCookies();
      await linuxManager.setIntelligentTrackingPreventionEnabled(false);
      await linuxManager.setCookieAcceptPolicy(originalPolicy);
      await linuxManager.setIntelligentTrackingPreventionEnabled(originalItp);
    });

    await manager.clearCookies();
    await linuxManager.setIntelligentTrackingPreventionEnabled(false);
    await linuxManager.setCookieAcceptPolicy(
      LinuxCookieAcceptPolicy.noThirdParty,
    );

    var pageFinished = Completer<String>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          if (!pageFinished.isCompleted) pageFinished.complete(url);
        },
        onSslAuthError: (error) => unawaited(error.proceed()),
      ),
    );
    await tester.pumpWidget(_ParityHarness(controller: controller));

    // Trust the test certificate for localhost before it is used as a
    // subordinate origin. WebKit only exposes the host decision for a main
    // resource, while the subsequent iframe shares the network-session trust
    // exception.
    await controller.loadRequest(Uri.parse('$tlsLocalhostOrigin/secure'));
    await pageFinished.future.timeout(const Duration(seconds: 10));

    final blockedCookieUrl = Uri.parse(
      '$tlsLocalhostOrigin/third-party-cookie?name=blockedThirdParty',
    );
    final firstPartyHostUrl = Uri.parse(
      'https://${secureServer.address.address}:${secureServer.port}'
      '/third-party-host?iframe=${Uri.encodeQueryComponent(blockedCookieUrl.toString())}',
    );
    pageFinished = Completer<String>();
    await controller.loadRequest(firstPartyHostUrl);
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await _waitForJavaScriptTrue(
      controller,
      'window.__thirdPartyLoaded === "blockedThirdParty"',
    );
    expect(
      await manager.getCookies(domain: blockedCookieUrl),
      isNot(
        contains(
          isA<WebViewCookie>().having(
            (cookie) => cookie.name,
            'name',
            'blockedThirdParty',
          ),
        ),
      ),
    );

    await linuxManager.setIntelligentTrackingPreventionEnabled(true);
    expect(await linuxManager.isIntelligentTrackingPreventionEnabled(), isTrue);
    expect(
      await linuxManager.getCookieAcceptPolicy(),
      LinuxCookieAcceptPolicy.always,
    );
    await linuxManager.setIntelligentTrackingPreventionEnabled(false);
    expect(
      await linuxManager.isIntelligentTrackingPreventionEnabled(),
      isFalse,
    );
    expect(
      await linuxManager.getCookieAcceptPolicy(),
      LinuxCookieAcceptPolicy.noThirdParty,
    );

    await linuxManager.setCookieAcceptPolicy(LinuxCookieAcceptPolicy.always);
    final acceptedCookieUrl = Uri.parse(
      '$tlsLocalhostOrigin/third-party-cookie?name=acceptedThirdParty',
    );
    await controller.runJavaScript('''
      window.__thirdPartyLoaded = null;
      document.querySelector('#third-party').src =
        ${jsonEncode(acceptedCookieUrl.toString())};
    ''');
    await _waitForJavaScriptTrue(
      controller,
      'window.__thirdPartyLoaded === "acceptedThirdParty"',
    );
    expect(
      await manager.getCookies(domain: acceptedCookieUrl),
      contains(
        isA<WebViewCookie>()
            .having((cookie) => cookie.name, 'name', 'acceptedThirdParty')
            .having((cookie) => cookie.value, 'value', 'accepted'),
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('browser downloads use the Flutter-selected destination', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'webview_flutter_linux_download_parity.',
    );
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/download.txt');
    final requested = Completer<LinuxWebViewDownloadRequest>();
    final finished = Completer<LinuxWebViewDownloadEvent>();
    final events = <LinuxWebViewDownloadEvent>[];

    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    final linuxController = controller.platform as LinuxWebViewController;
    await linuxController.setOnDownloadDestination((request) async {
      if (!requested.isCompleted) requested.complete(request);
      return LinuxWebViewDownloadDestination(destination.path);
    });
    await linuxController.setOnDownloadEvent((event) {
      events.add(event);
      if (event.kind == LinuxWebViewDownloadEventKind.finished &&
          !finished.isCompleted) {
        finished.complete(event);
      }
    });
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript('''
      (() => {
        const anchor = document.createElement('a');
        anchor.href = '$origin/download';
        anchor.download = 'parity-download.txt';
        document.body.append(anchor);
        anchor.click();
        anchor.remove();
      })();
    ''');

    final request = await requested.future.timeout(const Duration(seconds: 10));
    expect(request.url, '$origin/download');
    expect(request.suggestedFilename, 'parity-download.txt');
    expect(request.mimeType, 'text/plain');
    expect(request.contentLength, 'downloaded by WPE WebKit'.length);
    final completion = await finished.future.timeout(
      const Duration(seconds: 10),
    );
    expect(completion.destination, destination.path);
    expect(
      events.map((event) => event.kind),
      containsAllInOrder(<LinuxWebViewDownloadEventKind>[
        LinuxWebViewDownloadEventKind.createdDestination,
        LinuxWebViewDownloadEventKind.finished,
      ]),
    );
    expect(
      events,
      isNot(
        contains(
          isA<LinuxWebViewDownloadEvent>().having(
            (event) => event.kind,
            'kind',
            LinuxWebViewDownloadEventKind.failed,
          ),
        ),
      ),
    );
    expect(await destination.readAsString(), 'downloaded by WPE WebKit');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('media permission requests remain pending for Flutter', (
    tester,
  ) async {
    final permissionRequested = Completer<PlatformWebViewPermissionRequest>();
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    final linuxController = controller.platform as LinuxWebViewController;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await linuxController.setWebRtcEnabled(true);
    await linuxController.setMockCaptureDevicesEnabled(true);
    await linuxController.setOnPlatformPermissionRequest((request) {
      if (!permissionRequested.isCompleted) {
        permissionRequested.complete(request);
      }
    });
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript(r'''
      window.__permissionDenied = false;
      navigator.mediaDevices.getUserMedia({audio: true})
        .then(stream => stream.getTracks().forEach(track => track.stop()))
        .catch(() => { window.__permissionDenied = true; });
    ''');

    final request = await permissionRequested.future.timeout(
      const Duration(seconds: 10),
    );
    expect(request.types, contains(WebViewPermissionResourceType.microphone));
    expect(request, isA<LinuxWebViewPermissionRequest>());
    await request.deny();
    await _waitForJavaScriptTrue(controller, 'window.__permissionDenied');
    await controller.runJavaScript(r'''
      window.__microphonePermissionAfter = null;
      navigator.permissions.query({name: 'microphone'}).then(status => {
        window.__microphonePermissionAfter = status.state;
      });
    ''');
    await _waitForJavaScriptTrue(
      controller,
      "window.__microphonePermissionAfter === 'denied'",
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('granted media permission produces live audio and video tracks', (
    tester,
  ) async {
    final permissionRequested = Completer<PlatformWebViewPermissionRequest>();
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    final linuxController = controller.platform as LinuxWebViewController;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await linuxController.setWebRtcEnabled(true);
    await linuxController.setMockCaptureDevicesEnabled(true);
    await linuxController.setOnPlatformPermissionRequest((request) {
      if (!permissionRequested.isCompleted) {
        permissionRequested.complete(request);
      }
    });
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript(r'''
      window.__captureResolved = false;
      window.__captureError = null;
      window.__captureTrackKinds = [];
      navigator.mediaDevices.getUserMedia({audio: true, video: true})
        .then(stream => {
          window.__captureTrackKinds = stream.getTracks()
            .filter(track => track.readyState === 'live')
            .map(track => track.kind)
            .sort();
          stream.getTracks().forEach(track => track.stop());
          window.__captureResolved = true;
        })
        .catch(error => {
          window.__captureError = `${error.name}: ${error.message}`;
        });
    ''');

    final request = await permissionRequested.future.timeout(
      const Duration(seconds: 10),
    );
    expect(
      request.types,
      containsAll(<WebViewPermissionResourceType>[
        WebViewPermissionResourceType.camera,
        WebViewPermissionResourceType.microphone,
      ]),
    );
    await request.grant();
    await _waitForJavaScriptTrue(controller, 'window.__captureResolved');
    expect(
      await controller.runJavaScriptReturningResult(
        'window.__captureTrackKinds',
      ),
      <Object>['audio', 'video'],
    );
    expect(
      await controller.runJavaScriptReturningResult('window.__captureError'),
      'null',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('granted display capture produces a live video track', (
    tester,
  ) async {
    final permissionRequested = Completer<PlatformWebViewPermissionRequest>();
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    final linuxController = controller.platform as LinuxWebViewController;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await linuxController.setWebRtcEnabled(true);
    await linuxController.setMockCaptureDevicesEnabled(true);
    await linuxController.setOnPlatformPermissionRequest((request) {
      if (!permissionRequested.isCompleted) {
        permissionRequested.complete(request);
      }
    });
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/display-capture'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForJavaScriptTrue(
      controller,
      'window.__displayCaptureButtonClicked === true',
    );

    final request = await permissionRequested.future.timeout(
      const Duration(seconds: 10),
    );
    expect(
      request.types,
      contains(LinuxWebViewPermissionResourceType.displayCapture),
    );
    await request.grant();
    await _waitForJavaScriptTrue(controller, 'window.__displayCaptureResolved');
    expect(
      await controller.runJavaScriptReturningResult(
        'window.__displayCaptureTrackKinds',
      ),
      <Object>['video'],
    );
    expect(
      await controller.runJavaScriptReturningResult(
        'window.__displayCaptureError',
      ),
      'null',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a browser tap enters and exits Flutter-owned fullscreen', (
    tester,
  ) async {
    final entered = Completer<void>();
    final exited = Completer<void>();
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    final linuxController = controller.platform as LinuxWebViewController;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await linuxController.setOnFullscreenChanged((isFullscreen) {
      final completer = isFullscreen ? entered : exited;
      if (!completer.isCompleted) completer.complete();
    });
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/fullscreen'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForJavaScriptTrue(
      controller,
      'window.__fullscreenButtonClicked === true',
    );
    await entered.future.timeout(const Duration(seconds: 10));
    expect(
      await controller.runJavaScriptReturningResult(
        'document.fullscreenElement !== null',
      ),
      isTrue,
    );

    await controller.runJavaScript('document.exitFullscreen()');
    await exited.future.timeout(const Duration(seconds: 10));
    await _waitForJavaScriptTrue(
      controller,
      'document.fullscreenElement === null',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HTML input accepts IME updates and Ctrl+A selection', (
    tester,
  ) async {
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/input'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForJavaScriptTrue(
      controller,
      'document.activeElement?.id === "editor"',
    );
    await tester.pump(const Duration(milliseconds: 200));

    const text = 'Composed café 🎉';
    TextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await _waitForJavaScriptTrue(
      controller,
      'document.querySelector("#editor").value === ${_javaScriptString(text)}',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _waitForJavaScriptTrue(
      controller,
      'document.querySelector("#editor").selectionStart === 0 && '
      'document.querySelector("#editor").selectionEnd === ${text.length}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HTML input clipboard shortcuts paste, copy, and cut', (
    tester,
  ) async {
    const pastedText = 'Keyboard clipboard parity';
    await Clipboard.setData(const ClipboardData(text: pastedText));
    await _waitForClipboardText(pastedText);
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/input'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForJavaScriptTrue(
      controller,
      'document.activeElement?.id === "editor"',
    );

    await _sendControlKey(tester, LogicalKeyboardKey.keyV);
    await _waitForJavaScriptTrue(
      controller,
      'document.querySelector("#editor").value === '
      '${_javaScriptString(pastedText)}',
    );

    await Clipboard.setData(const ClipboardData(text: 'stale clipboard'));
    await _sendControlKey(tester, LogicalKeyboardKey.keyA);
    await _sendControlKey(tester, LogicalKeyboardKey.keyC);
    await _waitForClipboardText(pastedText);

    await _sendControlKey(tester, LogicalKeyboardKey.keyX);
    await _waitForJavaScriptTrue(
      controller,
      'document.querySelector("#editor").value === ""',
    );
    await _waitForClipboardText(pastedText);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('touch gestures scroll in content direction', (tester) async {
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/scroll'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    final webView = find.byType(WebViewWidget);

    await tester.drag(webView, const Offset(0, -300));
    await _waitForJavaScriptTrue(controller, 'window.scrollY > 0');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mouse wheel scrolls in content direction', (tester) async {
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/scroll'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    final webView = find.byType(WebViewWidget);
    final center = tester.getCenter(webView);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 53),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await _waitForJavaScriptTrue(controller, 'window.scrollY > 0');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('touchpad gestures scroll in content direction', (tester) async {
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/scroll'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    final webView = find.byType(WebViewWidget);
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    final center = tester.getCenter(webView);
    await trackpad.panZoomStart(center);
    await trackpad.panZoomUpdate(
      center,
      pan: const Offset(0, -300),
      scale: 1,
      rotation: 0,
    );
    await trackpad.panZoomEnd();
    await _waitForJavaScriptTrue(controller, 'window.scrollY > 0');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('one WebView can switch from touch to touchpad scrolling', (
    tester,
  ) async {
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/scroll'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    final webView = find.byType(WebViewWidget);

    await tester.drag(webView, const Offset(0, -300));
    await _waitForJavaScriptTrue(controller, 'window.scrollY > 0');
    await controller.runJavaScript('window.scrollTo(0, 0)');
    await _waitForJavaScriptTrue(controller, 'window.scrollY === 0');

    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    final center = tester.getCenter(webView);
    await trackpad.panZoomStart(center);
    await trackpad.panZoomUpdate(
      center,
      pan: const Offset(0, -300),
      scale: 1,
      rotation: 0,
    );
    await trackpad.panZoomEnd();
    await _waitForJavaScriptTrue(controller, 'window.scrollY > 0');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('WebKit accessibility nodes enter Flutter semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final pageFinished = Completer<void>();
      final controller = _controllerForTest(tester);
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
      );
      await controller.loadRequest(Uri.parse('$origin/accessibility'));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 20));
      await _waitForSemanticsLabel(tester, 'Accessible parity control');

      expect(
        find.bySemanticsLabel('Accessible parity control'),
        findsOneWidget,
      );
      tester.semantics.tap(find.semantics.byLabel('Accessible parity control'));
      await _waitForJavaScriptTrue(
        controller,
        'window.__accessibleButtonActivated === true',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('accessibility survives web-process termination and reload', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var pageFinished = Completer<void>();
      final processTerminated = Completer<void>();
      final controller = _controllerForTest(tester);
      final linuxController = controller.platform as LinuxWebViewController;
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!pageFinished.isCompleted) pageFinished.complete();
          },
          onWebResourceError: (error) {
            if (error.errorType ==
                    WebResourceErrorType.webContentProcessTerminated &&
                !processTerminated.isCompleted) {
              processTerminated.complete();
            }
          },
        ),
      );
      await controller.loadRequest(Uri.parse('$origin/accessibility'));

      await tester.pumpWidget(_ParityHarness(controller: controller));
      await pageFinished.future.timeout(const Duration(seconds: 10));
      await _waitForSemanticsLabel(tester, 'Accessible parity control');

      linuxController.terminateWebProcessForTesting();
      await processTerminated.future.timeout(const Duration(seconds: 10));
      pageFinished = Completer<void>();
      await controller.reload();
      await pageFinished.future.timeout(const Duration(seconds: 10));
      await _waitForSemanticsLabel(tester, 'Accessible parity control');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('context-menu paste and copy bridge the system clipboard', (
    tester,
  ) async {
    const pastedText = 'Flutter clipboard to WebKit';
    const copiedText = 'WebKit clipboard to Flutter';
    await Clipboard.setData(const ClipboardData(text: pastedText));
    await _waitForClipboardText(pastedText);
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/clipboard'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    final webView = find.byType(WebViewWidget);
    final center = tester.getCenter(webView);
    await tester.tap(webView, warnIfMissed: false);
    await _waitForJavaScriptTrue(
      controller,
      'document.activeElement?.id === "clipboard-editor"',
    );

    await _secondaryClick(tester, center);
    await _waitForText(tester, 'Paste');
    final pasteItem = find.widgetWithText(PopupMenuItem<int>, 'Paste');
    expect(pasteItem, findsOneWidget);
    expect(tester.widget<PopupMenuItem<int>>(pasteItem).enabled, isTrue);
    await _waitForClipboardText(pastedText);
    _resolvePopupMenuItem(tester, pasteItem);
    await tester.pump(const Duration(milliseconds: 350));
    await _waitForJavaScriptTrue(
      controller,
      'document.querySelector("#clipboard-editor").value === '
      '${_javaScriptString(pastedText)}',
    );

    await controller.runJavaScript('''
      (() => {
        const editor = document.querySelector('#clipboard-editor');
        editor.value = ${_javaScriptString(copiedText)};
        editor.select();
      })();
    ''');
    await _secondaryClick(tester, center);
    await _waitForText(tester, 'Copy');
    final copyItem = find.widgetWithText(PopupMenuItem<int>, 'Copy');
    expect(copyItem, findsOneWidget);
    _resolvePopupMenuItem(tester, copyItem);
    await tester.pump(const Duration(milliseconds: 350));
    await _waitForClipboardText(copiedText);

    expect((await Clipboard.getData('text/plain'))?.text, copiedText);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('trusted page scripts can copy through the bridged clipboard', (
    tester,
  ) async {
    const copiedText = 'Page script clipboard for Flutter';
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    final linuxController = controller.platform as LinuxWebViewController;
    await linuxController.setJavaScriptCanAccessClipboard(true);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/clipboard'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    await controller.runJavaScript('''
      (() => {
        const editor = document.querySelector('#clipboard-editor');
        window.__scriptCopyResult = null;
        editor.addEventListener('click', () => {
          editor.value = ${_javaScriptString(copiedText)};
          editor.select();
          window.__scriptCopyResult = document.execCommand('copy');
        }, { once: true });
      })()
    ''');
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForJavaScriptTrue(
      controller,
      'window.__scriptCopyResult === true',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await _waitForClipboardText(copiedText);

    expect((await Clipboard.getData('text/plain'))?.text, copiedText);
    expect(linuxController.javaScriptCanAccessClipboard, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HTML file input uses the Flutter file selector', (tester) async {
    final directory = await Directory.systemTemp.createTemp(
      'webview_flutter_linux_file_chooser_parity.',
    );
    addTearDown(() => directory.delete(recursive: true));
    final selectedFile = File('${directory.path}/selected.txt');
    await selectedFile.writeAsString('selected by Flutter', flush: true);
    final chooserShown = Completer<LinuxFileSelectorParams>();
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    final linuxController = controller.platform as LinuxWebViewController;
    await linuxController.setOnShowFileSelector((params) async {
      if (!chooserShown.isCompleted) chooserShown.complete(params);
      return <String>[selectedFile.path];
    });
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/file-chooser'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);

    final params = await chooserShown.future.timeout(
      const Duration(seconds: 10),
    );
    expect(params.mode, LinuxFileSelectorMode.open);
    expect(params.acceptedMimeTypes, contains('text/plain'));
    await _waitForJavaScriptTrue(
      controller,
      'document.querySelector("#file").files.length === 1 && '
      'document.querySelector("#file").files[0].name === "selected.txt"',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HTML select uses the Flutter option menu', (tester) async {
    final pageFinished = Completer<void>();
    final controller = _controllerForTest(tester);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse('$origin/option-menu'));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(WebViewWidget), warnIfMissed: false);
    await _waitForText(tester, 'Second choice');
    await tester.tap(find.text('Second choice'));
    await _waitForJavaScriptTrue(
      controller,
      'document.querySelector("#choice").value === "two"',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'permission state follows the Flutter geolocation decision by origin',
    (tester) async {
      final manager = LinuxWebViewGeolocationManager.instance;
      final providerActive = Completer<void>();
      var positionSent = false;
      await manager.setOnGeolocationChanged((state) async {
        if (!state.active || positionSent) return;
        positionSent = true;
        if (!providerActive.isCompleted) providerActive.complete();
        await manager.updatePosition(
          const LinuxWebViewGeolocationPosition(
            latitude: 18.0179,
            longitude: -76.8099,
            accuracy: 4.5,
          ),
        );
      });
      try {
        final permissionGranted = Completer<void>();
        final pageFinished = Completer<void>();
        final controller = _controllerForTest(tester);
        final linuxController = controller.platform as LinuxWebViewController;
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await linuxController.setOnPlatformPermissionRequest((request) {
          if (request.types.contains(
            LinuxWebViewPermissionResourceType.geolocation,
          )) {
            unawaited(
              request.grant().then((_) {
                if (!permissionGranted.isCompleted) {
                  permissionGranted.complete();
                }
              }),
            );
          } else {
            unawaited(request.deny());
          }
        });
        await controller.setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
        );
        await controller.loadRequest(Uri.parse(primaryUrl));

        await tester.pumpWidget(_ParityHarness(controller: controller));
        await pageFinished.future.timeout(const Duration(seconds: 10));
        await controller.runJavaScript(r'''
        window.__geolocationPermissionBefore = null;
        navigator.permissions.query({name: 'geolocation'}).then(status => {
          window.__geolocationPermissionBefore = status.state;
        });
      ''');
        await _waitForJavaScriptTrue(
          controller,
          "window.__geolocationPermissionBefore === 'prompt'",
        );
        await controller.runJavaScript(r'''
        window.__geolocationReceived = false;
        navigator.geolocation.getCurrentPosition(position => {
          window.__geolocation = [
            position.coords.latitude,
            position.coords.longitude,
            position.coords.accuracy
          ];
          window.__geolocationReceived = true;
        });
      ''');

        await permissionGranted.future.timeout(const Duration(seconds: 10));
        await providerActive.future.timeout(const Duration(seconds: 10));
        await _waitForJavaScriptTrue(
          controller,
          'window.__geolocationReceived === true',
        );
        await controller.runJavaScript(r'''
        window.__geolocationPermissionAfter = null;
        navigator.permissions.query({name: 'geolocation'}).then(status => {
          window.__geolocationPermissionAfter = status.state;
        });
      ''');
        await _waitForJavaScriptTrue(
          controller,
          "window.__geolocationPermissionAfter === 'granted'",
        );
        expect(
          await controller.runJavaScriptReturningResult('window.__geolocation'),
          <Object>[18.0179, -76.8099, 4.5],
        );
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await manager.setOnGeolocationChanged(null);
      }
    },
  );

  testWidgets('Web Notifications are presented and controlled by Flutter', (
    tester,
  ) async {
    final pageFinished = Completer<void>();
    final permissionGranted = Completer<void>();
    final presented = Completer<LinuxWebViewNotification>();
    final processNotificationPresented = Completer<LinuxWebViewNotification>();
    var notificationCount = 0;
    final controller = _controllerForTest(tester);
    final linuxController = controller.platform as LinuxWebViewController;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await linuxController.setOnPlatformPermissionRequest((request) {
      if (request.types.contains(
        LinuxWebViewPermissionResourceType.notifications,
      )) {
        unawaited(
          request.grant().then((_) {
            if (!permissionGranted.isCompleted) permissionGranted.complete();
          }),
        );
      } else {
        unawaited(request.deny());
      }
    });
    await linuxController.setOnShowNotification((notification) {
      notificationCount += 1;
      final completer = notificationCount == 1
          ? presented
          : processNotificationPresented;
      if (!completer.isCompleted) completer.complete(notification);
    });
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(_ParityHarness(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript(r'''
      window.__notificationClicked = false;
      window.__notificationClosed = false;
      window.__notificationPermission = null;
      Notification.requestPermission().then(permission => {
        window.__notificationPermission = permission;
        window.__notification = new Notification('Linux parity notification', {
          body: 'Presented by Flutter',
          tag: 'linux-parity'
        });
        window.__notification.onclick = () => {
          window.__notificationClicked = true;
        };
        window.__notification.onclose = () => {
          window.__notificationClosed = true;
        };
      });
    ''');

    await permissionGranted.future.timeout(const Duration(seconds: 10));
    final notification = await presented.future.timeout(
      const Duration(seconds: 10),
    );
    expect(notification.title, 'Linux parity notification');
    expect(notification.body, 'Presented by Flutter');
    expect(notification.tag, 'linux-parity');
    expect(notification.url, Uri.parse(primaryUrl));
    await _waitForJavaScriptTrue(
      controller,
      "window.__notificationPermission === 'granted'",
    );

    await notification.click();
    await _waitForJavaScriptTrue(
      controller,
      'window.__notificationClicked === true',
    );
    expect(notification.isClicked, isTrue);
    expect(notification.isClosed, isFalse);

    await notification.close();
    await notification.onClosed.timeout(const Duration(seconds: 10));
    await _waitForJavaScriptTrue(
      controller,
      'window.__notificationClosed === true',
    );
    expect(notification.isClosed, isTrue);

    await controller.runJavaScript(r'''
      window.__processNotification = new Notification(
        'Process-bound notification'
      );
    ''');
    final processNotification = await processNotificationPresented.future
        .timeout(const Duration(seconds: 10));
    expect(processNotification.isClosed, isFalse);
    linuxController.terminateWebProcessForTesting();
    await processNotification.onClosed.timeout(const Duration(seconds: 10));
    expect(processNotification.isClosed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

WebViewController _controllerForTest(WidgetTester tester) {
  final controller = WebViewController();
  addTearDown(() async {
    // Unmount first so the surface releases its attachment lease. Explicit
    // controller disposal then proves that each case releases its WPE view,
    // even when the test body fails before reaching its normal cleanup.
    await tester.pumpWidget(const SizedBox.shrink());
    final linuxController = controller.platform as LinuxWebViewController;
    linuxController.dispose();
  });
  return controller;
}

String _javaScriptString(String value) => jsonEncode(value);

Future<void> _waitForJavaScriptTrue(
  WebViewController controller,
  String expression,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (await controller.runJavaScriptReturningResult(expression) == true) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException(
    'JavaScript expression did not become true: $expression',
  );
}

Future<void> _waitForScrollPosition(
  WebViewController controller,
  Offset expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  Offset? lastPosition;
  while (DateTime.now().isBefore(deadline)) {
    lastPosition = await controller.getScrollPosition();
    if (lastPosition == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException(
    'Scroll position did not become $expected; last position was '
    '$lastPosition',
  );
}

Future<void> _waitForControllerTrue(
  Future<bool> Function() operation,
  String description,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (await operation()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('$description did not become true');
}

Future<void> _waitForSemanticsLabel(WidgetTester tester, String label) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (find.bySemanticsLabel(label).evaluate().isNotEmpty) return;
  }
  throw TimeoutException('Semantics label did not appear: $label');
}

Future<void> _secondaryClick(WidgetTester tester, Offset position) async {
  await _clickMouseButton(tester, position, kSecondaryMouseButton);
}

Future<void> _clickMouseButton(
  WidgetTester tester,
  Offset position,
  int buttons,
) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await gesture.down(position);
  await gesture.up();
  await tester.pump();
}

Future<void> _sendControlKey(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text(text).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 350));
      return;
    }
  }
  throw TimeoutException('Flutter text did not appear: $text');
}

Future<void> _waitForClipboardText(String expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if ((await Clipboard.getData('text/plain'))?.text == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Clipboard text did not become: $expected');
}

void _resolvePopupMenuItem(WidgetTester tester, Finder itemFinder) {
  final item = tester.widget<PopupMenuItem<int>>(itemFinder);
  expect(item.enabled, isTrue);
  Navigator.of(tester.element(itemFinder)).pop(item.value);
}

class _ParityHarness extends StatelessWidget {
  const _ParityHarness({required this.controller});

  final WebViewController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: WebViewWidget(controller: controller)),
  );
}
