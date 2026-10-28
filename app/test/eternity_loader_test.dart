import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamiipay/src/widgets/app_loading.dart';
import 'package:jamiipay/src/widgets/eternity_loader.dart';

void main() {
  group('EternityLoader', () {
    testWidgets('paints animated frames without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: EternityLoader(width: 72))),
        ),
      );
      // Pump through a full 1.6s loop plus some — every frame must paint.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(EternityLoader), findsOneWidget);
    });

    testWidgets('AppLoading appears after delay with label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppLoading(label: 'Sending…')),
        ),
      );
      // Before the 300ms delay: nothing (kills loader flash).
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sending…'), findsNothing);
      // After: loop + label.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sending…'), findsOneWidget);
      expect(find.byType(EternityLoader), findsOneWidget);
    });

    testWidgets('LoadingVeil shows loop + message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LoadingVeil(message: 'Holding in escrow…')),
        ),
      );
      await tester.pump();
      expect(find.text('Holding in escrow…'), findsOneWidget);
      expect(find.byType(EternityLoader), findsOneWidget);
    });
  });
}
