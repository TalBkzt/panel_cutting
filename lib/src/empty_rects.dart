import 'dart:math' as math;

import 'rect.dart';

/// Up to [maxCount] non-overlapping empty rectangles on a
/// [sheetWidth]x[sheetHeight] sheet around the [occupied] ones, largest
/// first. Stops at the first candidate whose shorter side is under
/// [minSide].
///
/// Greedy: finds the largest empty rectangle, marks it occupied and repeats.
/// That can miss a better pair than largest-first would find, but it's
/// simple and fast enough to run on every redraw.
List<PackingRect> findEmptyRects(
  double sheetWidth,
  double sheetHeight,
  List<PackingRect> occupied, {
  int maxCount = 3,
  double minSide = 0,
}) {
  final blocked = [...occupied];
  final results = <PackingRect>[];
  for (var i = 0; i < maxCount; i++) {
    final candidate = _largestEmptyRect(sheetWidth, sheetHeight, blocked);
    if (candidate == null) break;
    if (math.min(candidate.width, candidate.height) < minSide) break;
    results.add(candidate);
    blocked.add(candidate);
  }
  return results;
}

/// Exact, not grid-based: the largest empty rectangle always starts at the
/// sheet origin or at an occupied rectangle's right/bottom edge, so only
/// those corners are tried. From each corner the rectangle is shrunk until
/// it hits nothing; each pass only shrinks, so it terminates.
PackingRect? _largestEmptyRect(double sheetWidth, double sheetHeight, List<PackingRect> blocked) {
  final xs =
      <double>{0, ...blocked.map((r) => r.right)}.where((x) => x < sheetWidth).toList()..sort();
  final ys =
      <double>{0, ...blocked.map((r) => r.bottom)}.where((y) => y < sheetHeight).toList()..sort();

  PackingRect? best;
  for (final x0 in xs) {
    for (final y0 in ys) {
      if (blocked.any((r) => x0 >= r.x && x0 < r.right && y0 >= r.y && y0 < r.bottom)) continue;
      var w = sheetWidth - x0;
      var h = sheetHeight - y0;
      var changed = true;
      while (changed) {
        changed = false;
        for (final r in blocked) {
          final overlapsY = r.y < y0 + h && r.bottom > y0;
          if (r.x >= x0 && r.x < x0 + w && overlapsY) {
            w = r.x - x0;
            changed = true;
          }
          final overlapsX = r.x < x0 + w && r.right > x0;
          if (r.y >= y0 && r.y < y0 + h && overlapsX) {
            h = r.y - y0;
            changed = true;
          }
        }
      }
      if (w <= 0 || h <= 0) continue;
      if (best == null || w * h > best.area) {
        best = PackingRect(x: x0, y: y0, width: w, height: h);
      }
    }
  }
  return best;
}
