import 'dart:math';

import 'package:panel_cutting/panel_cutting.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('deriveCuttingGuide', () {
    test('no pieces: the whole sheet is one free leaf, no cuts', () {
      final guide = deriveCuttingGuide(1000, 1000, const [])!;
      expect((guide as GuillotineLeafNode).isFree, isTrue);
      expect(preorderCuts(guide), isEmpty);
    });

    test('one piece filling the sheet: a part leaf, no cuts', () {
      final guide = deriveCuttingGuide(500, 500, [r(0, 0, 500, 500)])!;
      expect((guide as GuillotineLeafNode).isPart, isTrue);
      expect(preorderCuts(guide), isEmpty);
    });

    test('one piece with margins all round: four trim cuts', () {
      final guide = deriveCuttingGuide(1000, 1000, [r(10, 10, 980, 980)])!;
      expect(preorderCuts(guide), hasLength(4));
      expectTreeTilesExactly(guide, r(0, 0, 1000, 1000));
    });

    test('two parts a blade apart: one vertical cut, the blade taking the gap', () {
      final guide =
          deriveCuttingGuide(1000, 500, [r(0, 0, 400, 500), r(404, 0, 596, 500)], kerf: 4)!;
      final cut = preorderCuts(guide).single;
      expect(cut.orientation, CutOrientation.vertical);
      expect(cut.offset, 400);
      expect(cut.kerfWidth, 4);
      expect(cut.length, 500);
      expectTreeTilesExactly(guide, r(0, 0, 1000, 500));
    });

    test('a pinwheel has no straight-cut sequence', () {
      final pinwheel = [
        r(0, 0, 300, 100),
        r(300, 0, 100, 300),
        r(100, 300, 300, 100),
        r(0, 100, 100, 300),
      ];
      expect(deriveCuttingGuide(400, 400, pinwheel), isNull);
    });

    test('overlapping parts yield null', () {
      expect(deriveCuttingGuide(1000, 1000, [r(0, 0, 500, 500), r(200, 200, 500, 500)]), isNull);
    });

    test('a part hanging off the sheet yields null', () {
      expect(deriveCuttingGuide(1000, 1000, [r(800, 0, 400, 400)]), isNull);
    });

    test('a gap wider than the blade is material: one more cut and a remnant', () {
      // 200 mm between the parts, 4 mm blade: the first cut leaves a 596 mm
      // piece whose 192 mm strip needs a second cut.
      final guide =
          deriveCuttingGuide(1000, 500, [r(0, 0, 400, 500), r(600, 0, 400, 500)], kerf: 4)!;
      final cuts = preorderCuts(guide);
      expect(cuts, hasLength(2));
      expect(cuts.map((c) => c.kerfWidth), everyElement(4));
      final steps = buildCuttingSteps(guide, (_) => null);
      expect(steps.first.first.kind, CutResultKind.part);
      expect(steps.first.second.kind, CutResultKind.workpiece);
      expect(steps.first.second.rect.width, 596);
      expect(steps.last.first.kind, CutResultKind.remnant);
      expect(steps.last.first.rect.width, 192);
      expect(steps.last.second.kind, CutResultKind.part);
      expectTreeTilesExactly(guide, r(0, 0, 1000, 500));
    });

    test('parts closer together than the blade cannot be cut apart', () {
      final layout = [r(0, 0, 400, 500), r(402, 0, 598, 500)];
      expect(deriveCuttingGuide(1000, 500, layout, kerf: 4), isNull);
      expect(deriveCuttingGuide(1000, 500, layout, kerf: 2), isNotNull);
    });

    test('an edge trim puts the blade on the waste side', () {
      final guide = deriveCuttingGuide(1000, 500, [r(0, 0, 900, 500)], kerf: 4)!;
      final cut = preorderCuts(guide).single;
      expect(cut.offset, 900);
      expect(cut.markOffset, 900);
      expect(remnantRects(guide).single.width, 96);
      expectTreeTilesExactly(guide, r(0, 0, 1000, 500));
    });

    test('a strip no wider than the blade goes entirely to sawdust', () {
      // 3 mm leading and 2 mm trailing strip, 4 mm blade.
      final guide = deriveCuttingGuide(1000, 500, [r(3, 0, 995, 500)], kerf: 4)!;
      final cuts = preorderCuts(guide);
      expect(cuts, hasLength(2));
      expect(remnantRects(guide), isEmpty);
      final leading = cuts.firstWhere((c) => c.firstSideIsWaste);
      expect(leading.kerfWidth, 3);
      expect(leading.markOffset, 3);
      final trailing = cuts.firstWhere((c) => c.secondSideIsWaste);
      expect(trailing.kerfWidth, closeTo(2, 1e-9));
      final waste = [
        for (final s in buildCuttingSteps(guide, (_) => null))
          for (final res in [s.first, s.second])
            if (res.kind == CutResultKind.waste) res.rect.width,
      ]..sort();
      expect(waste, [closeTo(2, 1e-9), closeTo(3, 1e-9)]);
      expectTreeTilesExactly(guide, r(0, 0, 1000, 500));
    });

    test('every piece appears exactly once as a part leaf', () {
      final pieces = [r(10, 10, 300, 200), r(314, 10, 300, 200), r(10, 214, 604, 300)];
      final guide = deriveCuttingGuide(700, 600, pieces, kerf: 4)!;
      final parts = leaves(guide).where((l) => l.isPart).toList();
      expect(parts, hasLength(3));
      for (final p in pieces) {
        expect(parts.where((l) => l.rect == p), hasLength(1));
      }
    });
  });

  group('buildCuttingSteps', () {
    test('same order as preorderCuts, every part named once', () {
      final pieces = [r(0, 0, 400, 240), r(0, 244, 400, 256), r(404, 0, 596, 500)];
      final names = {pieces[0]: 'Door', pieces[1]: 'Shelf', pieces[2]: 'Side'};
      final guide = deriveCuttingGuide(1000, 500, pieces, kerf: 4)!;
      final steps = buildCuttingSteps(guide, (rect) => names[rect]);

      expect(steps.map((s) => s.cut), preorderCuts(guide));
      final finished = [
        for (final s in steps)
          for (final res in [s.first, s.second])
            if (res.kind == CutResultKind.part) res.partName,
      ];
      expect(finished..sort(), ['Door', 'Shelf', 'Side']);
    });

    test('the first cut squares off a margin: remnant on one side, workpiece on the other', () {
      final guide =
          deriveCuttingGuide(1000, 500, [r(10, 10, 400, 480), r(414, 10, 576, 480)], kerf: 4)!;
      final steps = buildCuttingSteps(guide, (_) => null);
      expect(steps.first.first.kind, CutResultKind.remnant);
      expect(steps.first.second.kind, CutResultKind.workpiece);
    });

    test('a sheet filled by one part needs no steps', () {
      final guide = deriveCuttingGuide(500, 500, [r(0, 0, 500, 500)])!;
      expect(buildCuttingSteps(guide, (_) => 'x'), isEmpty);
    });

    test('Sheet.cuttingSteps names parts by label', () {
      const door = Part('Door', width: 400, height: 500);
      const side = Part('Side', width: 596, height: 500);
      final sheet = Sheet(1000, 500, [
        const PlacedPart(door, x: 0, y: 0, width: 400, height: 500),
        const PlacedPart(side, x: 404, y: 0, width: 596, height: 500),
      ], kerf: 4);
      final step = sheet.cuttingSteps()!.single;
      expect([step.first.partName, step.second.partName], ['Door', 'Side']);
    });
  });

  group('cut order', () {
    test('peels shared waste off whole instead of in scraps', () {
      // Cutting between the columns first would leave a scrap under each.
      final guide =
          deriveCuttingGuide(1000, 1000, [r(0, 0, 400, 500), r(404, 0, 596, 500)], kerf: 4)!;
      final remnant = remnantRects(guide).single;
      expect(remnant.width, 1000);
      expect(remnant.height, 496);
      expect(countCuts(guide), 2);
      expectTreeTilesExactly(guide, r(0, 0, 1000, 1000));
    });

    test('never takes more cuts than the first valid sequence, and often fewer', () {
      var layouts = 0;
      var saved = 0;
      for (var seed = 0; seed < 100; seed++) {
        final parts = randomParts(Random(seed));
        final sheets = [
          ...packGuillotine(parts, sheetWidth: 2070, sheetHeight: 2800, kerf: 4).sheets,
          ...packMaxRects(parts, sheetWidth: 2070, sheetHeight: 2800, kerf: 4).sheets,
        ];
        for (final sheet in sheets) {
          final rects = [for (final p in sheet.parts) p.rect];
          final best = deriveCuttingGuide(sheet.width, sheet.height, rects, kerf: sheet.kerf);
          final first = deriveCuttingGuide(
            sheet.width,
            sheet.height,
            rects,
            kerf: sheet.kerf,
            optimize: false,
          );
          expect(best == null, first == null, reason: 'seed $seed');
          if (best == null || first == null) continue;
          layouts++;
          expect(countCuts(best), lessThanOrEqualTo(countCuts(first)), reason: 'seed $seed');
          expectTreeTilesExactly(best, r(0, 0, sheet.width, sheet.height), reason: 'seed $seed');
          saved += countCuts(first) - countCuts(best);
        }
      }
      expect(layouts, greaterThan(100));
      expect(saved, greaterThan(0));
    });

    test('remnantRects are exactly the remnants the steps end with', () {
      final pieces = [r(10, 10, 440, 480), r(454, 10, 300, 300), r(454, 314, 300, 176)];
      final guide = deriveCuttingGuide(1000, 1000, pieces, kerf: 4)!;
      String size(PackingRect x) => '${x.width.round()}x${x.height.round()}';
      final fromTree = remnantRects(guide).map(size).toList()..sort();
      final fromSteps = [
        for (final s in buildCuttingSteps(guide, (_) => null))
          for (final res in [s.first, s.second])
            if (res.kind == CutResultKind.remnant) size(res.rect),
      ]..sort();
      expect(fromSteps, fromTree);
    });
  });
}
