import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trega/app.dart';

void main() {
  testWidgets('Trega app builds without crashing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: TregaApp()),
    );

    // Splash screen should be the first thing rendered.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
