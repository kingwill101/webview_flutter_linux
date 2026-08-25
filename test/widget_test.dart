// SPDX-License-Identifier: UNLICENSED

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zikzak_inappwebview_latest_probe/main.dart';

void main() {
  testWidgets('Rust native frame reaches the Flutter surface', (tester) async {
    await tester.pumpWidget(const ProbeApp(animate: false));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();

    final failureDetails = find
        .byType(SelectableText)
        .evaluate()
        .map((element) => (element.widget as SelectableText).data)
        .whereType<String>()
        .join('\n');

    expect(find.text('Rust FFI browser-surface probe'), findsOneWidget);
    expect(
      find.text('Rust native asset online'),
      findsOneWidget,
      reason: failureDetails.isEmpty ? null : failureDetails,
    );
    expect(find.text('ABI v1'), findsOneWidget);
    expect(find.text('800×450 RGBA'), findsOneWidget);
    expect(find.text('Frames: 1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
