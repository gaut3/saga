import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga/shared/widgets/book_card.dart';

/// Every grid and strip of books lays out to [bookCardExtent] — the card's own
/// height — rather than to a hand-tuned number beside it. Both had been guessed
/// before, and both were wrong: Browse's grid left ~34 dp for ~51 dp of text, so
/// a wrapped title crowded the author line (issue #3), and Home's strip was a
/// 170 the card had to shrink its type to fit inside.
///
/// So the thing to hold still is that the reserved boxes really do hold the type
/// the card puts in them, and that a cell is as tall as the card it contains.
void main() {
  double textHeight(String text, TextStyle style, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 110); // narrowest real cell: a 3-up grid on a 360 dp phone
    return painter.height;
  }

  group('the reserved text boxes hold their type', () {
    test('two lines of a wrapping title fit the title box', () {
      final h = textHeight(
        'The Shadow Rising: Book Four of The Wheel of Time',
        bookCardTitleStyle,
        2,
      );
      expect(h, lessThanOrEqualTo(kBookCardTitleHeight));
    });

    test('a one-line title still reserves the full box', () {
      // Two cards side by side must put their author lines at the same height
      // whether or not the titles wrap — that is what the fixed box buys.
      final short = textHeight('Elantris', bookCardTitleStyle, 2);
      expect(short, lessThanOrEqualTo(kBookCardTitleHeight));
    });

    test('one line of author fits the author box', () {
      final h = textHeight(
        'Robert Jordan and Brandon Sanderson',
        bookCardAuthorStyle,
        1,
      );
      expect(h, lessThanOrEqualTo(kBookCardAuthorHeight));
    });
  });

  group('bookCardExtent', () {
    test('is the cover plus every piece laid out under it', () {
      expect(
        bookCardExtent(100),
        100 +
            kBookCardTitleGap +
            kBookCardTitleHeight +
            kBookCardAuthorGap +
            kBookCardAuthorHeight +
            2, // slack
      );
    });

    test('dropping the author line shortens the card by exactly that line', () {
      expect(
        bookCardExtent(100) - bookCardExtent(100, showAuthor: false),
        kBookCardAuthorGap + kBookCardAuthorHeight,
      );
    });

    test('a strip of cards is as tall as the cards in it', () {
      expect(kBookStripHeight, bookCardExtent(kBookStripCoverWidth));
    });
  });

  group('bookGridDelegate', () {
    /// Lays a real grid out at [width] and returns one cell's size, so the
    /// numbers come from Flutter's own layout rather than from restating the
    /// delegate's arithmetic here.
    Future<Size> cellSize(WidgetTester tester,
        {required double width,
        bool showAuthor = true,
        double padding = 16}) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: GridView.builder(
          padding: EdgeInsets.symmetric(horizontal: padding),
          gridDelegate: bookGridDelegate(showAuthor: showAuthor),
          itemCount: 6,
          itemBuilder: (_, i) => ColoredBox(
            key: ValueKey(i),
            color: const Color(0xFF000000),
          ),
        ),
      ));
      return tester.getSize(find.byKey(const ValueKey(0)));
    }

    // A cell width of (360 - 32 - 20) / 3 doesn't divide evenly, so compare
    // within a fraction of a pixel rather than exactly.
    testWidgets('a cell is a square cover plus the text under it',
        (tester) async {
      final size = await cellSize(tester, width: 360);
      // The cover is square, so its height is the cell's width — everything
      // left over is the text block the card lays out below it.
      expect(size.height - size.width, closeTo(bookCardExtent(0), 0.001));
    });

    testWidgets('the same holds on a wide screen', (tester) async {
      final size = await cellSize(tester, width: 800);
      expect(size.height - size.width, closeTo(bookCardExtent(0), 0.001));
    });

    testWidgets('and under a padding the delegate was never told about',
        (tester) async {
      // The cell is sized from the width the grid hands it, so a page that
      // pads differently can't end up with cells too short for their text.
      final size = await cellSize(tester, width: 360, padding: 40);
      expect(size.height - size.width, closeTo(bookCardExtent(0), 0.001));
    });

    testWidgets('an author page cell drops exactly the author line',
        (tester) async {
      final withAuthor = await cellSize(tester, width: 360);
      final without = await cellSize(tester, width: 360, showAuthor: false);
      expect(withAuthor.width, closeTo(without.width, 0.001));
      expect(withAuthor.height - without.height,
          closeTo(kBookCardAuthorGap + kBookCardAuthorHeight, 0.001));
    });
  });
}
