import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamiipay/src/widgets/eternity_loader.dart';
import 'package:jamiipay/src/widgets/eternity_refresh.dart';

Widget _harness({required Future<void> Function() onRefresh}) {
  return MaterialApp(
    home: Scaffold(
      body: EternityRefresh(
        onRefresh: onRefresh,
        child: ListView.builder(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          itemCount: 3,
          itemBuilder: (_, i) =>
              SizedBox(height: 200, child: Text('row $i')),
        ),
      ),
    ),
  );
}

void main() {
  group('EternityRefresh', () {
    testWidgets('pull past trigger fires onRefresh, no spinner anywhere',
        (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(_harness(onRefresh: () async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }));

      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.byType(EternityLoader), findsNothing);
      expect(refreshes, 0);

      // Drag down well past the 70px trigger, then release. The
      // ScrollEnd settles over a few frames — pump until refresh fires.
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      for (var i = 0; i < 40 && refreshes == 0; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(refreshes, 1);
      // Loop is parked while the refresh future runs.
      expect(find.byType(EternityLoader), findsOneWidget);
      // Settles back once the refresh future completes.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(refreshes, 1);
      expect(find.byType(EternityLoader), findsNothing);
    });

    testWidgets('short pull does not refresh', (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(_harness(onRefresh: () async {
        refreshes++;
      }));

      await tester.drag(find.byType(ListView), const Offset(0, 20));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(refreshes, 0);
      expect(find.byType(EternityLoader), findsNothing);
    });
  });
}
