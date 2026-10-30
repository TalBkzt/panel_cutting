import 'dart:math';

import 'models.dart';
import 'rect.dart';

/// How to split the L-shaped leftover after a part goes into a free
/// rectangle (Jylänki's guillotine split rules). The rule decides how the
/// leftover space is carved up, and so how whole the offcuts come out.
enum GuillotineSplit {
  /// The shorter leftover strip becomes the small piece (the default).
  shorterLeftoverAxis,

  /// The longer leftover strip becomes the small piece.
  longerLeftoverAxis,

  /// Make one of the two leftovers as small as possible.
  minimizeArea,

  /// Make the bigger leftover as big as possible.
  maximizeArea,

  /// Cut along the free rectangle's shorter side first.
  shorterAxis,

  /// Cut along the free rectangle's longer side first.
  longerAxis,
}

/// How to pick the free rectangle a part goes into.
enum GuillotineChoice {
  /// Least leftover area (the default).
  bestAreaFit,

  /// Smallest leftover on the tighter side.
  bestShortSideFit,

  /// Smallest leftover on the looser side.
  bestLongSideFit,
}

class GuillotinePlacement {
  final double x;
  final double y;
  final double width;
  final double height;
  final bool rotated;

  const GuillotinePlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotated,
  });
}

/// Single-sheet guillotine packer. Every split is one straight cut across
/// the whole free rectangle, so the free rectangles stay disjoint and every
/// layout it produces can be made on a panel saw.
///
/// Free rectangles are deliberately never merged back together: a merged
/// rectangle can straddle two earlier cuts and make the layout impossible to
/// reproduce with straight cuts.
///
/// Based on J. Jylänki, "A Thousand Ways to Pack the Bin" (2010).
class GuillotineBinPack {
  final double binWidth;
  final double binHeight;
  final GuillotineSplit split;
  final GuillotineChoice choice;
  final List<PackingRect> _freeRects;

  GuillotineBinPack(
    this.binWidth,
    this.binHeight, {
    this.split = GuillotineSplit.shorterLeftoverAxis,
    this.choice = GuillotineChoice.bestAreaFit,
  }) : _freeRects = [PackingRect(x: 0, y: 0, width: binWidth, height: binHeight)];

  List<PackingRect> get freeRectangles => List.unmodifiable(_freeRects);

  /// Places a [width]x[height] part (also trying it turned when
  /// [allowRotation]) and returns where it went, or null if it fits nowhere.
  ///
  /// With a [random] and [candidateListSize] > 1 the free rectangle is picked
  /// at random among the [candidateListSize] best-scoring ones instead of
  /// always the best (GRASP-style semi-greedy construction), so repeated runs
  /// produce different layouts for a search to choose from.
  GuillotinePlacement? insert(
    double width,
    double height, {
    bool allowRotation = true,
    Random? random,
    int candidateListSize = 1,
  }) {
    final candidates = <_Candidate>[];
    for (final free in _freeRects) {
      if (width <= free.width && height <= free.height) {
        candidates.add(_score(free, width, height, rotated: false));
      }
      if (allowRotation && height != width && height <= free.width && width <= free.height) {
        candidates.add(_score(free, height, width, rotated: true));
      }
    }
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => a.score.compareTo(b.score));
    final chosen =
        (random != null && candidateListSize > 1)
            ? candidates[random.nextInt(min(candidateListSize, candidates.length))]
            : candidates.first;
    _split(chosen.free, chosen.placed);

    return GuillotinePlacement(
      x: chosen.placed.x,
      y: chosen.placed.y,
      width: chosen.placed.width,
      height: chosen.placed.height,
      rotated: chosen.rotated,
    );
  }

  _Candidate _score(PackingRect free, double w, double h, {required bool rotated}) {
    final leftoverArea = free.area - w * h;
    final leftoverW = free.width - w;
    final leftoverH = free.height - h;
    final shortSide = min(leftoverW, leftoverH);
    final longSide = max(leftoverW, leftoverH);
    // The primary measure is scaled up so the secondary one only breaks ties.
    final score = switch (choice) {
      GuillotineChoice.bestAreaFit => leftoverArea * 1e6 + shortSide,
      GuillotineChoice.bestShortSideFit => shortSide * 1e6 + longSide,
      GuillotineChoice.bestLongSideFit => longSide * 1e6 + shortSide,
    };
    return _Candidate(free, PackingRect(x: free.x, y: free.y, width: w, height: h), score, rotated);
  }

  /// Replaces [free] with the (at most two) disjoint rectangles left around
  /// [placed], which sits in its top-left corner.
  void _split(PackingRect free, PackingRect placed) {
    _freeRects.remove(free);

    final leftoverW = free.width - placed.width;
    final leftoverH = free.height - placed.height;
    // true: the bottom strip runs the full width of [free] and the right
    // strip only spans the placed part's height (a horizontal cut first).
    final bottomIsFullWidth = switch (split) {
      GuillotineSplit.shorterLeftoverAxis => leftoverW <= leftoverH,
      GuillotineSplit.longerLeftoverAxis => leftoverW > leftoverH,
      GuillotineSplit.minimizeArea => placed.width * leftoverH > leftoverW * placed.height,
      GuillotineSplit.maximizeArea => placed.width * leftoverH <= leftoverW * placed.height,
      GuillotineSplit.shorterAxis => free.width <= free.height,
      GuillotineSplit.longerAxis => free.width > free.height,
    };
    if (leftoverW > 0) {
      _freeRects.add(
        PackingRect(
          x: placed.right,
          y: free.y,
          width: leftoverW,
          height: bottomIsFullWidth ? placed.height : free.height,
        ),
      );
    }
    if (leftoverH > 0) {
      _freeRects.add(
        PackingRect(
          x: free.x,
          y: placed.bottom,
          width: bottomIsFullWidth ? free.width : placed.width,
          height: leftoverH,
        ),
      );
    }
  }
}

class _Candidate {
  final PackingRect free;
  final PackingRect placed;
  final double score;
  final bool rotated;

  const _Candidate(this.free, this.placed, this.score, this.rotated);
}

/// Packs [parts] onto as many [sheetWidth]x[sheetHeight] sheets as needed,
/// filling one sheet at a time with [GuillotineBinPack]. Every resulting
/// sheet can be cut with straight cuts (see [Sheet.cuttingGuide]).
///
/// [kerf] is the blade width kept between parts. Parts that don't fit on an
/// empty sheet end up in [PackingResult.oversized].
///
/// With a [random], [candidateListSize] > 1 also varies which of the largest
/// remaining parts goes next, and [randomizeRules] (most of the time) picks a
/// random [split], [choice] and [order] for the run.
PackingResult packGuillotine(
  List<Part> parts, {
  required double sheetWidth,
  required double sheetHeight,
  double kerf = 0,
  GuillotineSplit split = GuillotineSplit.shorterLeftoverAxis,
  GuillotineChoice choice = GuillotineChoice.bestAreaFit,
  PartOrder order = PartOrder.area,
  Random? random,
  int candidateListSize = 1,
  bool randomizeRules = false,
}) {
  if (randomizeRules && random != null && random.nextDouble() < 0.6) {
    split = GuillotineSplit.values[random.nextInt(GuillotineSplit.values.length)];
    choice = GuillotineChoice.values[random.nextInt(GuillotineChoice.values.length)];
    order = PartOrder.values[random.nextInt(PartOrder.values.length)];
  }
  final units = expandUnits(parts, sheetWidth, sheetHeight);
  final pending = units.fitting..sort((a, b) => order.keyOf(b).compareTo(order.keyOf(a)));
  final oversized = units.oversized;

  final sheets = <Sheet>[];
  while (pending.isNotEmpty) {
    // Parts are packed grown by the kerf into a sheet grown by the same
    // amount. That guarantees the kerf between any two parts, while the kerf
    // trailing the last part at the sheet edge costs no room.
    final packer = GuillotineBinPack(
      sheetWidth + kerf,
      sheetHeight + kerf,
      split: split,
      choice: choice,
    );
    final placed = <PlacedPart>[];
    // A part that didn't fit stays out for the rest of this sheet (it only
    // gets fuller) but is retried on the next one.
    final rejected = <Part>[];

    while (pending.isNotEmpty) {
      final part = pending.removeAt(_pickNext(pending, random, candidateListSize, order));
      final p = packer.insert(
        part.width + kerf,
        part.height + kerf,
        allowRotation: part.canRotate,
        random: random,
        candidateListSize: candidateListSize,
      );
      if (p == null) {
        rejected.add(part);
        continue;
      }
      placed.add(
        PlacedPart(
          part,
          x: p.x,
          y: p.y,
          width: p.width - kerf,
          height: p.height - kerf,
          rotated: p.rotated,
        ),
      );
    }

    pending.addAll(rejected);
    if (placed.isEmpty) {
      // Can't happen (every pending part fits on an empty sheet), but never
      // loop forever or drop parts silently.
      oversized.addAll(pending);
      break;
    }
    sheets.add(Sheet(sheetWidth, sheetHeight, placed, kerf: kerf));
  }

  return PackingResult(
    sheetWidth: sheetWidth,
    sheetHeight: sheetHeight,
    sheets: sheets,
    oversized: oversized,
  );
}

/// Index of the next part to place: the largest by [order], or with a
/// [random] a random one of the [candidateListSize] largest. [pending] is not
/// kept sorted after the first sheet, so the top ones are looked up here.
int _pickNext(List<Part> pending, Random? random, int candidateListSize, PartOrder order) {
  if (random == null || candidateListSize <= 1 || pending.length <= 1) return 0;
  final size = min(candidateListSize, pending.length);
  final indices = List<int>.generate(pending.length, (i) => i)
    ..sort((a, b) => order.keyOf(pending[b]).compareTo(order.keyOf(pending[a])));
  return indices[random.nextInt(size)];
}
