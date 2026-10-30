import 'package:panel_cutting/panel_cutting.dart';
import 'package:test/test.dart';

const _p = Part('p', width: 1, height: 1);

PlacedPart _at(double x, double y, double w, double h) =>
    PlacedPart(_p, x: x, y: y, width: w, height: h);

// Parts in these layouts are a 4 mm blade apart.
Sheet _sheet(List<PlacedPart> parts) => Sheet(1000, 1000, parts, kerf: 4);

PackingResult _layout(List<Sheet> sheets) =>
    PackingResult(sheetWidth: 1000, sheetHeight: 1000, sheets: sheets);

void main() {
  group('area bounds', () {
    test('parts totalling 3.4 sheets need 4, so 85% is the best possible', () {
      const parts = [
        Part('panel', width: 1000, height: 1000, quantity: 3),
        Part('strip', width: 1000, height: 400),
      ];
      expect(minimumSheets(parts, 1000, 1000), 4);
      expect(maximumUtilization(parts, 1000, 1000), closeTo(0.85, 1e-9));
    });

    test('parts filling whole sheets exactly give 100%', () {
      const parts = [Part('half', width: 1000, height: 500, quantity: 4)];
      expect(minimumSheets(parts, 1000, 1000), 2);
      expect(maximumUtilization(parts, 1000, 1000), closeTo(1, 1e-9));
    });

    test('parts bigger than the sheet are left out', () {
      const parts = [
        Part('fits', width: 500, height: 500),
        Part('too big', width: 5000, height: 5000, quantity: 3),
      ];
      expect(fittableArea(parts, 1000, 1000), 250000);
      expect(minimumSheets(parts, 1000, 1000), 1);
    });

    test('a part that only fits turned counts only if it may be turned', () {
      expect(fittableArea(const [Part('t', width: 400, height: 1500)], 1500, 500), 600000);
      expect(
        fittableArea(const [Part('t', width: 400, height: 1500, canRotate: false)], 1500, 500),
        0,
      );
    });

    test('no parts: zero, not a division by zero', () {
      expect(minimumSheets(const [], 1000, 1000), 0);
      expect(maximumUtilization(const [], 1000, 1000), 0);
    });
  });

  group('cuts and remnants', () {
    test('cutsOf counts real cuts and largestRemnantOf the biggest piece left', () {
      // One 800x1000 part: one cut leaves 200 mm less the 4 mm blade.
      final sheet = _sheet([_at(0, 0, 800, 1000)]);
      expect(cutsOf(sheet), 1);
      expect(largestRemnantOf(sheet), 196 * 1000);
      expect(totalCuts([sheet, sheet]), 2);
    });

    test('cut length is the distance the saw travels', () {
      // A vertical cut through a 1000 mm tall sheet.
      expect(cutLengthOf(_sheet([_at(0, 0, 800, 1000)])), 1000);
      // A horizontal cut across, then a vertical one through the 500 mm strip.
      expect(cutLengthOf(_sheet([_at(0, 0, 800, 500)])), 1000 + 500);
    });

    test('offcutsOf drops pieces with a side under minSide', () {
      final sheet = _sheet([_at(0, 0, 900, 1000)]);
      expect(offcutsOf(sheet, minSide: 50), hasLength(1));
      expect(offcutsOf(sheet, minSide: 100), isEmpty);
    });
  });

  group('isBetterLayout', () {
    test('at equal cuts, the bigger whole offcut wins', () {
      final wide = _layout([
        _sheet([_at(0, 0, 400, 400)]),
      ]);
      final shorter = _layout([
        _sheet([_at(0, 0, 400, 395)]),
      ]);
      expect(isBetterLayout(shorter, wide), isTrue);
      expect(isBetterLayout(wide, shorter), isFalse);
    });

    test('at equal area, fewer cuts win', () {
      // Moving the second column 100 mm away costs a cut and leaves a scrap.
      final together = _layout([
        _sheet([_at(0, 0, 400, 1000), _at(404, 0, 400, 500), _at(404, 504, 400, 496)]),
      ]);
      final apart = _layout([
        _sheet([_at(0, 0, 400, 1000), _at(504, 0, 400, 500), _at(504, 504, 400, 496)]),
      ]);
      expect(totalCuts(together.sheets), 3);
      expect(totalCuts(apart.sheets), 4);
      expect(isBetterLayout(together, apart), isTrue);
      expect(isBetterLayout(apart, together), isFalse);
    });

    test('more parts placed beats fewer cuts', () {
      final one = _layout([
        _sheet([_at(0, 0, 300, 300)]),
      ]);
      final three = _layout([
        _sheet([_at(0, 0, 300, 300), _at(304, 0, 300, 300), _at(0, 304, 300, 300)]),
      ]);
      expect(isBetterLayout(three, one), isTrue);
      expect(isBetterLayout(one, three), isFalse);
    });

    test('fewer sheets come before area and cuts', () {
      final oneSheet = _layout([
        _sheet([_at(0, 0, 500, 500)]),
      ]);
      final twoSheets = _layout([
        _sheet([_at(0, 0, 500, 500)]),
        _sheet(const []),
      ]);
      expect(isBetterLayout(oneSheet, twoSheets), isTrue);
      expect(isBetterLayout(twoSheets, oneSheet), isFalse);
    });

    test('an exact tie is not an improvement', () {
      final a = _layout([
        _sheet([_at(0, 0, 400, 400)]),
      ]);
      final b = _layout([
        _sheet([_at(0, 0, 400, 400)]),
      ]);
      expect(isBetterLayout(a, b), isFalse);
    });
  });
}
