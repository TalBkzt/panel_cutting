import 'dart:math';

import 'models.dart';
import 'rect.dart';

/// Free-rectangle choice rules for [MaxRectsBinPack].
enum MaxRectsHeuristic { bestShortSideFit, bestAreaFit, bottomLeftRule }

class MaxRectsPlacement {
  final double x;
  final double y;
  final double width;
  final double height;
  final bool rotated;

  const MaxRectsPlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotated,
  });
}

/// Single-sheet MaxRects packer (J. Jylänki, "A Thousand Ways to Pack the
/// Bin", 2010). It keeps every maximal free rectangle, so a part can go into
/// any gap rather than just the next shelf. Usually denser than guillotine
/// packing on mixed part lists, but the result is not always cuttable with
/// straight cuts (see [Sheet.cuttingGuide]).
class MaxRectsBinPack {
  final double binWidth;
  final double binHeight;
  final MaxRectsHeuristic heuristic;
  final List<PackingRect> _freeRects;

  MaxRectsBinPack(this.binWidth, this.binHeight, this.heuristic)
    : _freeRects = [PackingRect(x: 0, y: 0, width: binWidth, height: binHeight)];

  List<PackingRect> get freeRectangles => List.unmodifiable(_freeRects);

  /// Places a [width]x[height] part (also trying it turned when
  /// [allowRotation]) and returns where it went, or null if it fits nowhere.
  MaxRectsPlacement? insert(double width, double height, {bool allowRotation = true}) {
    var best = _bestFor(width, height, rotated: false);
    if (allowRotation && height != width) {
      final turned = _bestFor(height, width, rotated: true);
      if (turned != null && (best == null || turned.score < best.score)) best = turned;
    }
    if (best == null) return null;

    _splitAround(best.rect);
    _prune();
    return MaxRectsPlacement(
      x: best.rect.x,
      y: best.rect.y,
      width: best.rect.width,
      height: best.rect.height,
      rotated: best.rotated,
    );
  }

  _Candidate? _bestFor(double width, double height, {required bool rotated}) {
    _Candidate? best;
    for (final free in _freeRects) {
      if (width > free.width || height > free.height) continue;
      final leftoverX = free.width - width;
      final leftoverY = free.height - height;
      final score = switch (heuristic) {
        MaxRectsHeuristic.bestShortSideFit => min(leftoverX, leftoverY),
        MaxRectsHeuristic.bestAreaFit => free.area - width * height,
        // Lowest bottom edge first, leftmost on a tie.
        MaxRectsHeuristic.bottomLeftRule => (free.y + height) * 1e7 + free.x,
      };
      if (best == null || score < best.score) {
        best = _Candidate(
          PackingRect(x: free.x, y: free.y, width: width, height: height),
          score,
          rotated,
        );
      }
    }
    return best;
  }

  /// Splits every free rectangle the placed part overlaps into up to four
  /// slivers around it. Each sliver keeps the full extent of the original on
  /// the other axis, so slivers overlap each other; [_prune] removes the
  /// ones contained in others.
  void _splitAround(PackingRect placed) {
    final next = <PackingRect>[];
    for (final free in _freeRects) {
      if (!free.intersects(placed)) {
        next.add(free);
        continue;
      }
      if (placed.x > free.x) {
        next.add(PackingRect(x: free.x, y: free.y, width: placed.x - free.x, height: free.height));
      }
      if (placed.right < free.right) {
        next.add(
          PackingRect(
            x: placed.right,
            y: free.y,
            width: free.right - placed.right,
            height: free.height,
          ),
        );
      }
      if (placed.y > free.y) {
        next.add(PackingRect(x: free.x, y: free.y, width: free.width, height: placed.y - free.y));
      }
      if (placed.bottom < free.bottom) {
        next.add(
          PackingRect(
            x: free.x,
            y: placed.bottom,
            width: free.width,
            height: free.bottom - placed.bottom,
          ),
        );
      }
    }
    _freeRects
      ..clear()
      ..addAll(next);
  }

  void _prune() {
    for (var i = 0; i < _freeRects.length; i++) {
      for (var j = i + 1; j < _freeRects.length; j++) {
        if (_freeRects[j].contains(_freeRects[i])) {
          _freeRects.removeAt(i);
          i--;
          break;
        }
        if (_freeRects[i].contains(_freeRects[j])) {
          _freeRects.removeAt(j);
          j--;
        }
      }
    }
  }
}

class _Candidate {
  final PackingRect rect;
  final double score;
  final bool rotated;

  const _Candidate(this.rect, this.score, this.rotated);
}

/// Packs [parts] onto as many [sheetWidth]x[sheetHeight] sheets as needed
/// with [MaxRectsBinPack]. For each sheet the remaining parts are run
/// through every heuristic in [heuristics] and the attempt placing the most
/// area wins; near-ties go to the attempt leaving the biggest free rectangle.
///
/// [kerf] is the blade width kept between parts. Parts that don't fit on an
/// empty sheet end up in [PackingResult.oversized]. With a [random] and
/// [candidateListSize] > 1 the part order is randomized among the
/// [candidateListSize] largest at each step.
PackingResult packMaxRects(
  List<Part> parts, {
  required double sheetWidth,
  required double sheetHeight,
  double kerf = 0,
  List<MaxRectsHeuristic> heuristics = MaxRectsHeuristic.values,
  Random? random,
  int candidateListSize = 1,
}) {
  assert(heuristics.isNotEmpty);
  final units = expandUnits(parts, sheetWidth, sheetHeight);
  // Largest first: small parts fill the gaps large ones leave, not the other
  // way around.
  final pending = units.fitting..sort((a, b) => b.area.compareTo(a.area));
  final oversized = units.oversized;

  // Attempts within this share of the sheet area count as equally dense.
  final tieTolerance = sheetWidth * sheetHeight * 0.005;

  final sheets = <Sheet>[];
  while (pending.isNotEmpty) {
    final order = _graspOrder(pending, random, candidateListSize);
    _Attempt? best;
    for (final heuristic in heuristics) {
      final attempt = _attemptSheet(order, sheetWidth, sheetHeight, heuristic, kerf);
      if (best == null) {
        best = attempt;
        continue;
      }
      final areaDiff = attempt.placedArea - best.placedArea;
      if (areaDiff > tieTolerance ||
          (areaDiff >= -tieTolerance && attempt.largestFreeArea > best.largestFreeArea)) {
        best = attempt;
      }
    }
    if (best!.placed.isEmpty) {
      // Can't happen (every pending part fits on an empty sheet).
      oversized.addAll(pending);
      break;
    }
    for (final p in best.placed) {
      pending.remove(p.part);
    }
    sheets.add(Sheet(sheetWidth, sheetHeight, best.placed, kerf: kerf));
  }

  return PackingResult(
    sheetWidth: sheetWidth,
    sheetHeight: sheetHeight,
    sheets: sheets,
    oversized: oversized,
  );
}

class _Attempt {
  final List<PlacedPart> placed;
  final double placedArea;
  final double largestFreeArea;

  _Attempt(this.placed, this.placedArea, this.largestFreeArea);
}

/// Runs [order] through one fresh packer using [heuristic] for every part.
_Attempt _attemptSheet(
  List<Part> order,
  double sheetWidth,
  double sheetHeight,
  MaxRectsHeuristic heuristic,
  double kerf,
) {
  // Parts grown by the kerf in a sheet grown by the kerf: no two real parts
  // end up closer than the kerf on any side, and the kerf after the last
  // part at the sheet edge costs no room.
  final packer = MaxRectsBinPack(sheetWidth + kerf, sheetHeight + kerf, heuristic);
  final placed = <PlacedPart>[];
  var area = 0.0;
  for (final part in order) {
    final p = packer.insert(part.width + kerf, part.height + kerf, allowRotation: part.canRotate);
    if (p == null) continue;
    final placedPart = PlacedPart(
      part,
      x: p.x,
      y: p.y,
      width: p.width - kerf,
      height: p.height - kerf,
      rotated: p.rotated,
    );
    placed.add(placedPart);
    area += placedPart.area;
  }
  final largestFree = packer.freeRectangles.fold(0.0, (m, r) => max(m, r.area));
  return _Attempt(placed, area, largestFree);
}

/// [pending] as is, or with a [random] a semi-greedy permutation: each next
/// part is drawn at random from the [candidateListSize] largest remaining.
List<Part> _graspOrder(List<Part> pending, Random? random, int candidateListSize) {
  if (random == null || candidateListSize <= 1 || pending.length <= 1) return pending;
  final remaining = [...pending];
  final result = <Part>[];
  while (remaining.isNotEmpty) {
    remaining.sort((a, b) => b.area.compareTo(a.area));
    result.add(remaining.removeAt(random.nextInt(min(candidateListSize, remaining.length))));
  }
  return result;
}
