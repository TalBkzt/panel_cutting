import 'dart:math';

import 'package:panel_cutting/panel_cutting.dart';
import 'package:test/test.dart';

import 'support.dart';

PlacedPart _at(Part part, double x, double y, {bool turned = false}) => PlacedPart(
  part,
  x: x,
  y: y,
  width: turned ? part.height : part.width,
  height: turned ? part.width : part.height,
  rotated: turned,
);

void main() {
  const big = Part('big', width: 700, height: 1000);
  const strip = Part('strip', width: 250, height: 1000);

  test('moves the last sheet into a gap on an earlier one and drops it', () {
    final sheets = [
      Sheet(1000, 1000, [_at(big, 0, 0)], kerf: 4),
      Sheet(1000, 1000, [_at(strip, 0, 0)], kerf: 4),
    ];
    final result = consolidateSheets(sheets);
    expect(result, hasLength(1));
    expect(result.single.parts, hasLength(2));
    expectValidSheet(result.single);
  });

  test('all or nothing: if one part cannot move, nothing does', () {
    const wide = Part('wide', width: 600, height: 600);
    final sheets = [
      Sheet(1000, 1000, [_at(big, 0, 0)], kerf: 4),
      Sheet(1000, 1000, [_at(strip, 0, 0), _at(wide, 300, 0)], kerf: 4),
    ];
    final result = consolidateSheets(sheets);
    expect(result, hasLength(2));
    expect(result.first.parts, hasLength(1));
  });

  test('keeps the kerf: a gap one blade too narrow is not used', () {
    const tight = Part('tight', width: 300, height: 1000);
    final sheets = [
      Sheet(1000, 1000, [_at(big, 0, 0)], kerf: 4),
      Sheet(1000, 1000, [_at(tight, 0, 0)], kerf: 4),
    ];
    expect(consolidateSheets(sheets), hasLength(2));
  });

  test('turns a part to fit only when it may be turned', () {
    const lying = Part('lying', width: 1000, height: 250);
    const fixed = Part('fixed', width: 1000, height: 250, canRotate: false);
    Sheet first() => Sheet(1000, 1000, [_at(big, 0, 0)], kerf: 4);

    final turned = consolidateSheets([
      first(),
      Sheet(1000, 1000, [_at(lying, 0, 0)], kerf: 4),
    ]);
    expect(turned, hasLength(1));
    final moved = turned.single.parts.last;
    expect(moved.rotated, isTrue);
    expectValidSheet(turned.single);

    expect(
      consolidateSheets([
        first(),
        Sheet(1000, 1000, [_at(fixed, 0, 0)], kerf: 4),
      ]),
      hasLength(2),
    );
  });

  test('never uses more sheets, keeps every part, and with keepGuillotine stays cuttable', () {
    for (var seed = 0; seed < 30; seed++) {
      final parts = randomParts(Random(seed), maxSide: 900);
      final packed = packGuillotine(parts, sheetWidth: 2070, sheetHeight: 2800, kerf: 4);
      final result = packed.withSheets(consolidateSheets(packed.sheets, keepGuillotine: true));
      expect(result.sheetCount, lessThanOrEqualTo(packed.sheetCount));
      expectAllAccountedFor(parts, result, reason: 'seed $seed');
      for (final sheet in result.sheets) {
        expectValidSheet(sheet, reason: 'seed $seed');
        expect(sheet.cuttingGuide, isNotNull, reason: 'seed $seed');
      }
    }
  });
}
