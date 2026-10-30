import 'dart:math';

import 'package:panel_cutting/panel_cutting.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('MaxRectsBinPack', () {
    test('places a part in the top-left corner of an empty sheet', () {
      for (final h in MaxRectsHeuristic.values) {
        final p = MaxRectsBinPack(1000, 500, h).insert(300, 200)!;
        expect([p.x, p.y], [0, 0], reason: '$h');
      }
    });

    test('returns null once nothing fits', () {
      final packer = MaxRectsBinPack(100, 100, MaxRectsHeuristic.bestAreaFit);
      expect(packer.insert(100, 100), isNotNull);
      expect(packer.insert(1, 1), isNull);
    });

    test('turns a part that only fits turned, unless told not to', () {
      final h = MaxRectsHeuristic.bestShortSideFit;
      expect(MaxRectsBinPack(1000, 300, h).insert(300, 900)!.rotated, isTrue);
      expect(MaxRectsBinPack(1000, 300, h).insert(300, 900, allowRotation: false), isNull);
    });

    test('free rectangles never overlap a placed part and none contains another', () {
      final packer = MaxRectsBinPack(1000, 1000, MaxRectsHeuristic.bestAreaFit);
      final placed = <PackingRect>[];
      for (final (w, h) in [(400.0, 300.0), (250.0, 250.0), (600.0, 100.0), (120.0, 700.0)]) {
        final p = packer.insert(w, h)!;
        placed.add(r(p.x, p.y, p.width, p.height));
      }
      final free = packer.freeRectangles;
      for (final f in free) {
        for (final p in placed) {
          expect(f.intersects(p), isFalse);
        }
      }
      for (var i = 0; i < free.length; i++) {
        for (var j = 0; j < free.length; j++) {
          if (i != j) expect(free[i].contains(free[j]), isFalse);
        }
      }
    });
  });

  group('packMaxRects', () {
    test('places every unit on valid sheets', () {
      for (var seed = 0; seed < 40; seed++) {
        final parts = randomParts(Random(seed));
        final result = packMaxRects(parts, sheetWidth: 2070, sheetHeight: 2800, kerf: 4);
        expectAllAccountedFor(parts, result, reason: 'seed $seed');
        for (final sheet in result.sheets) {
          expectValidSheet(sheet, reason: 'seed $seed');
        }
      }
    });

    test('opens another sheet once the first is full', () {
      final result = packMaxRects(
        const [Part('half', width: 1000, height: 600, quantity: 3)],
        sheetWidth: 1000,
        sheetHeight: 1000,
      );
      expect(result.sheetCount, 3);
    });

    test('a part bigger than the sheet is reported, not dropped', () {
      const big = Part('big', width: 1200, height: 1200);
      final result = packMaxRects(const [big], sheetWidth: 1000, sheetHeight: 1000);
      expect(result.sheets, isEmpty);
      expect(result.oversized, [big]);
    });

    test('a random part order stays valid and does vary', () {
      final parts = randomParts(Random(3));
      final layouts = <String>{};
      for (var seed = 0; seed < 40; seed++) {
        final result = packMaxRects(
          parts,
          sheetWidth: 2070,
          sheetHeight: 2800,
          kerf: 4,
          random: Random(seed),
          candidateListSize: 3,
        );
        expectAllAccountedFor(parts, result, reason: 'seed $seed');
        for (final sheet in result.sheets) {
          expectValidSheet(sheet, reason: 'seed $seed');
        }
        layouts.add(result.sheets.first.parts.map((p) => '${p.x},${p.y}').join(';'));
      }
      expect(layouts.length, greaterThan(1));
    });
  });
}
