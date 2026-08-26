// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (kDebugMode && !isFlutterTest) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const WebViewExampleApp());
}

class WebViewExampleApp extends StatelessWidget {
  const WebViewExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WebView Flutter Linux',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff695de9),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BrowserPage(),
    );
  }
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final TextEditingController _addressController = TextEditingController(
    text: 'https://example.com',
  );
  late final WebViewController _primaryController;
  late final WebViewController _secondaryController;
  int _progress = 0;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _primaryController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onUrlChange: (change) {
            if (!mounted) return;
            setState(() => _currentUrl = change.url);
          },
        ),
      )
      ..loadRequest(Uri.parse(_addressController.text));
    _secondaryController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString('''
        <!doctype html>
        <html>
          <body style="margin:0;background:#17152a;color:#ede9ff;
                       font:24px system-ui;display:grid;place-items:center;
                       height:100vh">
            <main style="text-align:center">
              <h1>Independent WebView</h1>
              <p>Second native handle and Flutter texture</p>
            </main>
          </body>
        </html>
      ''');
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    final raw = _addressController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || !uri.hasScheme) return;
    await _primaryController.loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView Flutter Linux'),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => _primaryController.goBack(),
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: () => _primaryController.goForward(),
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: 'Reload',
                  onPressed: () => _primaryController.reload(),
                  icon: const Icon(Icons.refresh),
                ),
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _navigate(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _navigate, child: const Text('Go')),
              ],
            ),
          ),
          if (_currentUrl case final url?)
            Semantics(
              label: 'Current URL',
              child: SizedBox.shrink(key: ValueKey<String>(url)),
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: WebViewWidget(controller: _primaryController)),
                const VerticalDivider(width: 1),
                Expanded(
                  child: WebViewWidget(controller: _secondaryController),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
