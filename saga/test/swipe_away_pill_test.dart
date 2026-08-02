import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/shared/widgets/swipe_away_pill.dart';

/// The pill dismisses like a notification in Android 16's shade: it sticks,
/// snaps free, then tracks the finger, with spring physics on release.
///
/// The gate is the important part. Dismissing stops playback, and the snap is
/// what stands between a stray horizontal graze and a stopped book — so a flick
/// that never breaks the pill free must never dismiss it, however fast.
void main() {
  const pillWidth = 300.0;
  const commit = pillWidth / 3;
  // Matches the widget's own gate; the finger also has to clear kTouchSlop
  // before the recogniser reports any delta at all.
  const unstick = 34.0;

  final counters = <int Function()>[];

  Future<int Function()> pumpPill(WidgetTester tester,
      {VoidCallback? onLongPress}) async {
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: pillWidth,
              child: SwipeAwayPill(
                onDismissed: () => dismissed++,
                onLongPress: onLongPress,
                // The real pill wraps its content in an InkWell that opens the
                // player. That tap recogniser matters here: with it in the
                // arena the drag has to clear kTouchSlop to win, and without it
                // the drag is the sole competitor and is accepted at
                // pointer-down — so every distance below would be off by the
                // slop, and the resistance gate would look weaker than it is.
                child: Material(
                  child: InkWell(
                    onTap: () {},
                    // Explicit width: the Stack inside SwipeAwayPill hands its
                    // child loose constraints, so a bare SizedBox(height:) would
                    // collapse to zero width and nothing would be hittable.
                    child: const SizedBox(width: pillWidth, height: 64),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the route transition finish: while it runs, an IgnorePointer swallows
    // pointer events and gestures land only partially.
    await tester.pumpAndSettle();
    int read() => dismissed;
    counters.add(read);
    return read;
  }

  /// Drags [dx] across [steps] pointer samples [gap] apart.
  ///
  /// The timestamps have to be passed explicitly: `moveBy` defaults them to
  /// zero, and `tester.pump` advances the *widget* clock, not the event clock —
  /// so without this every sample shares a timestamp and the velocity tracker
  /// reports nothing.
  Future<void> drag(
    WidgetTester tester,
    double dx, {
    required int steps,
    required Duration gap,
  }) async {
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(SwipeAwayPill)));
    var at = Duration.zero;
    for (var i = 0; i < steps; i++) {
      at += gap;
      await gesture.moveBy(Offset(dx / steps, 0), timeStamp: at);
      await tester.pump(gap);
    }
    await gesture.up(timeStamp: at);
    await tester.pumpAndSettle();
  }

  /// A deliberate drag: well under the escape velocity.
  Future<void> slowDrag(WidgetTester tester, double dx) =>
      drag(tester, dx, steps: 12, gap: const Duration(milliseconds: 24));

  /// A genuinely fast flick — same travel as a slow drag that wouldn't
  /// dismiss, but thrown.
  Future<void> fastFlick(WidgetTester tester, double dx) =>
      drag(tester, dx, steps: 8, gap: const Duration(milliseconds: 4));

  testWidgets('a short drag springs back', (tester) async {
    final dismissed = await pumpPill(tester);
    await slowDrag(tester, kTouchSlop + commit - 30);
    expect(dismissed(), 0);
  });

  testWidgets('a drag past a third of the width dismisses', (tester) async {
    final dismissed = await pumpPill(tester);
    await slowDrag(tester, kTouchSlop + commit + 30);
    expect(dismissed(), 1);
  });

  testWidgets('dismisses to the left as well as the right', (tester) async {
    final dismissed = await pumpPill(tester);
    await slowDrag(tester, -(kTouchSlop + commit + 30));
    expect(dismissed(), 1);
  });

  testWidgets('a fast flick that snaps free but stops short still dismisses',
      (tester) async {
    final dismissed = await pumpPill(tester);
    // Past the snap, well short of the distance threshold — the throw is what
    // carries it, exactly as a flicked notification leaves the shade.
    //
    // Hand-rolled rather than tester.fling: fling spreads a short travel over
    // so few frames that the velocity tracker has nothing to estimate from and
    // reports ~0. This emits enough samples at a genuinely fast rate.
    await fastFlick(tester, kTouchSlop + unstick + 25);
    expect(dismissed(), 1);
  });

  testWidgets('a slow drag the same distance does not dismiss', (tester) async {
    final dismissed = await pumpPill(tester);
    await slowDrag(tester, kTouchSlop + unstick + 25);
    expect(dismissed(), 0);
  });

  testWidgets('a fast flick that never snaps free does NOT dismiss',
      (tester) async {
    final dismissed = await pumpPill(tester);
    // The accident the stick exists to prevent: high velocity, tiny travel.
    // Velocity may only relax the *distance* requirement once free; it must
    // never substitute for the snap itself.
    await fastFlick(tester, kTouchSlop + unstick - 8);
    expect(dismissed(), 0);
  });

  testWidgets('a fling back toward the slot never dismisses', (tester) async {
    final dismissed = await pumpPill(tester);
    // Drag well out to the right, then flick back toward the slot without
    // crossing it — the pill is still on the right, travelling left, fast.
    // Honouring the fling's sign here would sling it off the *left* edge.
    //
    // Both legs are sampled like a real finger. The velocity tracker fits over
    // roughly the last 100 ms, so a single large outbound jump would still be
    // inside the window at release and drag the fit positive.
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(SwipeAwayPill)));
    var at = Duration.zero;
    const step = Duration(milliseconds: 8);
    // Out to +150 (past the commit distance), 14 px at a time.
    for (var i = 0; i < 12; i++) {
      at += step;
      await gesture.moveBy(const Offset((kTouchSlop + 150) / 12, 0),
          timeStamp: at);
      await tester.pump(step);
    }
    // Back to +40 at -1000 px/s, over enough samples to own the window.
    for (var i = 0; i < 14; i++) {
      at += step;
      await gesture.moveBy(const Offset(-110 / 14, 0), timeStamp: at);
      await tester.pump(step);
    }
    await gesture.up(timeStamp: at);
    await tester.pumpAndSettle();
    expect(dismissed(), 0);
  });

  testWidgets('the pill catches up to the finger after it snaps free',
      (tester) async {
    // Measured off a screen recording of Android 16's shade: the card holds
    // still while stuck, then covers *more* ground than the finger until it is
    // back under it. Keeping the gap open instead would leave the pill trailing
    // for the rest of the drag, which is what it used to do.
    await pumpPill(tester);
    final pill = find.byType(SwipeAwayPill);
    final gesture = await tester.startGesture(tester.getCenter(pill));
    var at = Duration.zero;
    const step = Duration(milliseconds: 16);

    double offset() => tester
        .widget<Transform>(find.descendant(
            of: pill, matching: find.byType(Transform).first))
        .transform
        .getTranslation()
        .x;

    // Well past the snap.
    for (var i = 0; i < 10; i++) {
      at += step;
      await gesture.moveBy(const Offset((kTouchSlop + unstick + 60) / 10, 0),
          timeStamp: at);
      await tester.pump(step);
    }
    // Let the catch-up spring settle while the finger holds still.
    for (var i = 0; i < 30; i++) {
      at += step;
      await gesture.moveBy(Offset.zero, timeStamp: at);
      await tester.pump(step);
    }

    // The finger travelled unstick + 60 past the slop. Exact agreement isn't
    // assertable — the recogniser discards the whole move in which slop was
    // crossed, not just the slop — so this pins the thing that matters: the
    // pill ended up *under* the finger, not trailing it by the distance it gave
    // up while stuck.
    const underFinger = unstick + 60;
    expect(offset(), closeTo(underFinger, 12.0));
    expect(offset(), greaterThan(underFinger - unstick + 10));

    await gesture.up(timeStamp: at);
    await tester.pumpAndSettle();
  });

  testWidgets('a tap is not a dismiss', (tester) async {
    final dismissed = await pumpPill(tester);
    await tester.tap(find.byType(SwipeAwayPill));
    await tester.pumpAndSettle();
    expect(dismissed(), 0);
  });

  testWidgets('long press reaches the options menu', (tester) async {
    var longPressed = 0;
    final dismissed = await pumpPill(tester, onLongPress: () => longPressed++);
    await tester.longPress(find.byType(SwipeAwayPill));
    await tester.pumpAndSettle();
    expect(longPressed, 1);
    expect(dismissed(), 0);
  });

  testWidgets('dismisses exactly once, however hard it is thrown',
      (tester) async {
    final dismissed = await pumpPill(tester);
    await fastFlick(tester, kTouchSlop + 260);
    expect(dismissed(), 1);
  });

  testWidgets('a released pill re-sticks for the next drag', (tester) async {
    final dismissed = await pumpPill(tester);
    // Snaps free, then springs back.
    await slowDrag(tester, kTouchSlop + unstick + 25);
    expect(dismissed(), 0);
    // The second drag must face the full resistance again, not start free.
    await fastFlick(tester, kTouchSlop + unstick - 8);
    expect(dismissed(), 0);
  });
}
