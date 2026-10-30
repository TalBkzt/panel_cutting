import 'package:panel_cutting/panel_cutting.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('an empty sheet is one empty rect', () {
    expect(findEmptyRects(1000, 800, const []), [r(0, 0, 1000, 800)]);
  });

  test('a corner part leaves the larger strip first', () {
    // Bottom strip 1000x700 beats the right strip 600x1000.
    expect(findEmptyRects(1000, 1000, [r(0, 0, 400, 300)]).first, r(0, 300, 1000, 700));
  });

  test('found rects stay on the sheet and off the occupied space', () {
    final occupied = [r(0, 0, 400, 300), r(400, 0, 600, 400)];
    for (final e in findEmptyRects(1000, 1000, occupied, maxCount: 5)) {
      for (final o in occupied) {
        expect(e.intersects(o), isFalse);
      }
      expect(r(0, 0, 1000, 1000).contains(e), isTrue);
    }
  });

  test('a full sheet has none', () {
    expect(findEmptyRects(1000, 1000, [r(0, 0, 1000, 1000)]), isEmpty);
  });

  test('slivers under minSide are skipped', () {
    expect(findEmptyRects(1000, 1000, [r(0, 0, 1000, 950)], minSide: 150), isEmpty);
  });

  test('respects maxCount', () {
    expect(findEmptyRects(1000, 1000, [r(400, 400, 200, 200)], maxCount: 2), hasLength(2));
  });
}
