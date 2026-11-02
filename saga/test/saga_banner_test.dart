import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/core/providers.dart';
import 'package:saga/core/theme/saga_theme.dart';
import 'package:saga/shared/widgets/saga_toast.dart';

/// The update notice (GitHub #22). As a 2.5 s toast it fired while the app was
/// still opening and went unseen, so it stays until closed — and the one
/// person who ships releases is always on the newest version and never sees
/// it for real, so this is where it gets checked.
void main() {
  late int taps;
  late int closes;

  Future<void> pumpBanner(WidgetTester tester) async {
    taps = 0;
    closes = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sagaThemeVariantProvider
            .overrideWith((_) => SagaThemeVariant.values.first),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSagaBanner(
                  context,
                  'Update available: v9.9.9',
                  onTap: () => taps++,
                  onClose: () => closes++,
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
  }

  testWidgets('stays up long after a toast would have gone', (tester) async {
    await pumpBanner(tester);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Update available: v9.9.9'), findsOneWidget);
  });

  testWidgets('the close button closes it without running the tap',
      (tester) async {
    await pumpBanner(tester);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Update available: v9.9.9'), findsNothing);
    expect((taps, closes), (0, 1));
  });

  testWidgets('tapping the message runs the tap once and closes it',
      (tester) async {
    await pumpBanner(tester);
    await tester.tap(find.text('Update available: v9.9.9'));
    // A second tap during the fade-out must not run it again.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Update available: v9.9.9'),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Update available: v9.9.9'), findsNothing);
    expect((taps, closes), (1, 0));
  });
}
