import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:malody_catch_mobile/main.dart';

void main() {
  testWidgets('Core smoke page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MalodyCatchMobileApp());
    await tester.pump();

    expect(find.text('Core FFI Smoke'), findsOneWidget);
    expect(find.textContaining('library_loaded:'), findsOneWidget);
    expect(find.textContaining('abi_version:'), findsOneWidget);
    expect(find.textContaining('abi_min_required:'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Startup Check'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ElevatedButton, 'Open Session'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Add Rain'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Add Sound'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
