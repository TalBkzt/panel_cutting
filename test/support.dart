import 'dart:math';

import 'package:panel_cutting/panel_cutting.dart';
import 'package:test/test.dart';

PackingRect r(double x, double y, double w, double h) =>
    PackingRect(x: x, y: y, width: w, height: h);

/// A random order of 8..32 part types, 1..3 of each.
List<Part> randomParts(Random rand, {double minSide = 80, double maxSide = 1580}) {
  final types = 8 + rand.nextInt(25);
  final range = (maxSide - minSide).round();
  return [
    for (var i = 0; i < types; i++)
      Part(
        'p$i',
        width: minSide + rand.nextInt(range),
        height: minSide + rand.nextInt(range),
        quantity: 1 + rand.nextInt(3),
        canRotate: rand.nextInt(4) != 0,
      ),
  ];
}

/// Every part on the sheet, no part off it, no two parts closer than the
/// kerf, and every placed size matching its part (turned only if allowed).
void expectValidSheet(Sheet sheet, {String reason = ''}) {
  const eps = 1e-6;
  for (final p in sheet.parts) {
    expect(p.x, greaterThanOrEqualTo(-eps), reason: reason);
    expect(p.y, greaterThanOrEqualTo(-eps), reason: reason);
    expect(p.x + p.width, lessThanOrEqualTo(sheet.width + eps), reason: reason);
    expect(p.y + p.height, lessThanOrEqualTo(sheet.height + eps), reason: reason);
    if (p.rotated) {
      expect(p.part.canRotate, isTrue, reason: '$reason: ${p.label} must not be turned');
      expect([p.width, p.height], [p.part.height, p.part.width], reason: reason);
    } else {
      expect([p.width, p.height], [p.part.width, p.part.height], reason: reason);
    }
  }
  for (var i = 0; i < sheet.parts.length; i++) {
    for (var j = i + 1; j < sheet.parts.length; j++) {
      final a = sheet.parts[i];
      final b = sheet.parts[j];
      final apart =
          a.x + a.width + sheet.kerf <= b.x + eps ||
          b.x + b.width + sheet.kerf <= a.x + eps ||
          a.y + a.height + sheet.kerf <= b.y + eps ||
          b.y + b.height + sheet.kerf <= a.y + eps;
      expect(apart, isTrue, reason: '$reason: $a and $b are closer than the kerf');
    }
  }
}

/// Every unit of [parts] is either placed exactly once or reported oversized.
void expectAllAccountedFor(List<Part> parts, PackingResult result, {String reason = ''}) {
  final expected = parts.fold(0, (sum, p) => sum + p.quantity);
  expect(result.placedCount + result.oversized.length, expected, reason: reason);
  for (final part in parts) {
    final placed = result.sheets.expand((s) => s.parts).where((p) => identical(p.part, part));
    final over = result.oversized.where((p) => identical(p, part));
    expect(placed.length + over.length, part.quantity, reason: '$reason: ${part.label}');
  }
}

/// The leaves of [node], walked from [bounds], tile [bounds] exactly: each
/// cut's two sides partition its work rect, the second starting after the
/// blade.
void expectTreeTilesExactly(GuillotineSliceNode node, PackingRect bounds, {String reason = ''}) {
  void same(PackingRect a, PackingRect b) {
    expect(a.x, closeTo(b.x, 1e-6), reason: reason);
    expect(a.y, closeTo(b.y, 1e-6), reason: reason);
    expect(a.width, closeTo(b.width, 1e-6), reason: reason);
    expect(a.height, closeTo(b.height, 1e-6), reason: reason);
  }

  switch (node) {
    case GuillotineLeafNode(:final rect):
      same(rect, bounds);
    case GuillotineCutNode(:final cut, :final first, :final second):
      same(cut.workRect, bounds);
      final after = cut.offset + cut.kerfWidth;
      if (cut.orientation == CutOrientation.vertical) {
        expectTreeTilesExactly(
          first,
          r(bounds.x, bounds.y, cut.offset, bounds.height),
          reason: reason,
        );
        expectTreeTilesExactly(
          second,
          r(bounds.x + after, bounds.y, bounds.width - after, bounds.height),
          reason: reason,
        );
      } else {
        expectTreeTilesExactly(
          first,
          r(bounds.x, bounds.y, bounds.width, cut.offset),
          reason: reason,
        );
        expectTreeTilesExactly(
          second,
          r(bounds.x, bounds.y + after, bounds.width, bounds.height - after),
          reason: reason,
        );
      }
  }
}

List<GuillotineLeafNode> leaves(GuillotineSliceNode node) => switch (node) {
  GuillotineCutNode(:final first, :final second) => [...leaves(first), ...leaves(second)],
  GuillotineLeafNode() => [node],
};
