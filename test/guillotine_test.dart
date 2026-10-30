import 'dart:math';

import 'package:panel_cutting/panel_cutting.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('GuillotineBinPack', () {
    test('places a part in the top-left corner of an empty sheet', () {
      final p = GuillotineBinPack(1000, 500).insert(300, 200, allowRotation: false)!;
      expect([p.x, p.y, p.width, p.height, p.rotated], [0, 0, 300, 200, false]);
    });

    test('turns a part when that leaves a tighter fit', () {
      // 200x300 leaves a 200 mm strip on the short side, 300x200 a 300 mm one.
      final p = GuillotineBinPack(1000, 500).insert(300, 200)!;
      expect([p.width, p.height, p.rotated], [200, 300, true]);
    });

    test('returns null once nothing fits', () {
      final packer = GuillotineBinPack(100, 100);
      expect(packer.insert(100, 100), isNotNull);
      expect(packer.insert(1, 1), isNull);
    });

    test('turns a part that only fits turned, unless told not to', () {
      expect(GuillotineBinPack(1000, 300).insert(300, 900)!.rotated, isTrue);
      expect(GuillotineBinPack(1000, 300).insert(300, 900, allowRotation: false), isNull);
    });

    test('free rectangles stay disjoint and account for exactly the unused area', () {
      final packer = GuillotineBinPack(1000, 1000);
      var used = 0.0;
      for (final (w, h) in [(400.0, 300.0), (250.0, 250.0), (600.0, 100.0), (120.0, 700.0)]) {
        final p = packer.insert(w, h)!;
        used += p.width * p.height;
      }
      final free = packer.freeRectangles;
      expect(free.fold(0.0, (s, f) => s + f.area), closeTo(1000 * 1000 - used, 1e-6));
      for (var i = 0; i < free.length; i++) {
        for (var j = i + 1; j < free.length; j++) {
          expect(free[i].intersects(free[j]), isFalse);
        }
      }
    });

    test('a random pick among candidates can differ from the best pick', () {
      final seen = <String>{};
      for (var seed = 0; seed < 30; seed++) {
        final packer = GuillotineBinPack(1000, 1000)..insert(600, 600);
        final p = packer.insert(100, 100, random: Random(seed), candidateListSize: 3)!;
        seen.add('${p.x},${p.y}');
      }
      expect(seen.length, greaterThan(1));
    });
  });

  group('packGuillotine', () {
    test('places every unit on valid sheets', () {
      const parts = [
        Part('door', width: 400, height: 700, quantity: 4),
        Part('shelf', width: 560, height: 300, quantity: 6),
        Part('side', width: 300, height: 1800, quantity: 2, canRotate: false),
      ];
      final result = packGuillotine(parts, sheetWidth: 2070, sheetHeight: 2800, kerf: 4);
      expectAllAccountedFor(parts, result);
      expect(result.oversized, isEmpty);
      for (final sheet in result.sheets) {
        expectValidSheet(sheet);
      }
    });

    test('opens another sheet once the first is full', () {
      final result = packGuillotine(
        const [Part('half', width: 1000, height: 600, quantity: 3)],
        sheetWidth: 1000,
        sheetHeight: 1000,
      );
      expect(result.sheetCount, 3);
    });

    test('a part bigger than the sheet is reported, not dropped', () {
      const big = Part('big', width: 3000, height: 100, canRotate: false);
      const small = Part('small', width: 100, height: 100);
      final result = packGuillotine(const [big, small], sheetWidth: 1000, sheetHeight: 1000);
      expect(result.oversized, [big]);
      expect(result.placedCount, 1);
    });

    test('the kerf trailing the last part at the sheet edge costs no room', () {
      // Two 498 mm parts and a 4 mm blade fill a 1000 mm sheet exactly.
      final result = packGuillotine(
        const [Part('p', width: 498, height: 1000, quantity: 2)],
        sheetWidth: 1000,
        sheetHeight: 1000,
        kerf: 4,
      );
      expect(result.sheetCount, 1);
      expectValidSheet(result.sheets.single);
    });

    test('every rule combination gives valid sheets that can be cut with straight cuts', () {
      for (var seed = 0; seed < 8; seed++) {
        final parts = randomParts(Random(seed));
        for (final split in GuillotineSplit.values) {
          for (final choice in GuillotineChoice.values) {
            for (final order in PartOrder.values) {
              final why = 'seed $seed, $split, $choice, $order';
              final result = packGuillotine(
                parts,
                sheetWidth: 2070,
                sheetHeight: 2800,
                kerf: 4,
                split: split,
                choice: choice,
                order: order,
              );
              expectAllAccountedFor(parts, result, reason: why);
              for (final sheet in result.sheets) {
                expectValidSheet(sheet, reason: why);
                expect(sheet.cuttingGuide, isNotNull, reason: why);
              }
            }
          }
        }
      }
    });

    test('randomized runs stay valid and cuttable and do vary', () {
      final parts = randomParts(Random(7));
      final layouts = <String>{};
      for (var seed = 0; seed < 60; seed++) {
        final result = packGuillotine(
          parts,
          sheetWidth: 2070,
          sheetHeight: 2800,
          kerf: 4,
          random: Random(seed),
          candidateListSize: 3,
          randomizeRules: true,
        );
        expectAllAccountedFor(parts, result, reason: 'seed $seed');
        for (final sheet in result.sheets) {
          expectValidSheet(sheet, reason: 'seed $seed');
          expect(sheet.cuttingGuide, isNotNull, reason: 'seed $seed');
        }
        layouts.add(result.sheets.first.parts.map((p) => '${p.x},${p.y}').join(';'));
      }
      expect(layouts.length, greaterThan(1));
    });
  });
}
