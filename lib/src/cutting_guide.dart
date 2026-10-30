import 'dart:math' as math;

import 'rect.dart';

enum CutOrientation { horizontal, vertical }

/// How close to an edge counts as "on" it. Well below anything measurable,
/// well above float noise.
const double _sideEps = 1e-6;

/// One straight, edge-to-edge saw cut through [workRect]. Along the cut axis
/// the workpiece comes apart as
///
///     | first side: [offset] | blade: [kerfWidth] | second side: the rest |
///
/// One side may be empty (an edge strip no wider than the blade, which the
/// blade takes whole), but never both.
class GuideCut {
  final PackingRect workRect;
  final CutOrientation orientation;
  final double offset;
  final double kerfWidth;

  const GuideCut._(this.workRect, this.orientation, this.offset, this.kerfWidth);

  /// Null for a "cut" that doesn't separate anything: outside the workpiece,
  /// both sides empty, or an edge trim that removes nothing.
  static GuideCut? tryCreate(
    PackingRect workRect,
    CutOrientation orientation,
    double offset,
    double kerfWidth,
  ) {
    final span = orientation == CutOrientation.horizontal ? workRect.height : workRect.width;
    if (offset < 0 || kerfWidth < 0 || offset + kerfWidth > span + _sideEps) return null;
    final firstEmpty = offset <= _sideEps;
    final secondEmpty = offset + kerfWidth >= span - _sideEps;
    if (firstEmpty && secondEmpty) return null;
    if ((firstEmpty || secondEmpty) && kerfWidth <= _sideEps) return null;
    return GuideCut._(workRect, orientation, offset, kerfWidth);
  }

  /// The workpiece's extent along which [offset] is measured: its height for
  /// a horizontal cut, its width for a vertical one.
  double get span => orientation == CutOrientation.horizontal ? workRect.height : workRect.width;

  /// How far the saw travels: the workpiece's width for a horizontal cut, its
  /// height for a vertical one.
  double get length => orientation == CutOrientation.horizontal ? workRect.width : workRect.height;

  /// The blade takes the whole leading strip.
  bool get firstSideIsWaste => offset <= _sideEps;

  /// The blade takes the whole trailing strip.
  bool get secondSideIsWaste => offset + kerfWidth >= span - _sideEps;

  /// Where the operator measures to from the leading edge: the end of the
  /// first piece (blade runs just past the mark), or, when the first side is
  /// waste, the start of what is kept (blade runs just before it).
  double get markOffset => firstSideIsWaste ? kerfWidth : offset;
}

/// Cutting guide for one sheet: a binary tree of [GuillotineCutNode]s whose
/// leaves are parts or leftover material. Reading [preorderCuts] top to
/// bottom gives a physically valid cut order.
sealed class GuillotineSliceNode {
  const GuillotineSliceNode();
}

class GuillotineCutNode extends GuillotineSliceNode {
  final GuideCut cut;
  final GuillotineSliceNode first;
  final GuillotineSliceNode second;

  const GuillotineCutNode(this.cut, this.first, this.second);
}

class GuillotineLeafNode extends GuillotineSliceNode {
  final PackingRect rect;

  /// Whether this leaf is a part (as opposed to leftover material).
  final bool isPart;

  const GuillotineLeafNode.free(this.rect) : isPart = false;
  const GuillotineLeafNode.part(this.rect) : isPart = true;

  bool get isFree => !isPart;

  /// A free leaf with no area: the empty side of a trim whose strip the
  /// blade took whole. Not a remnant.
  bool get isEmpty => rect.width <= _sideEps || rect.height <= _sideEps;
}

/// What one side of a cut turns into.
enum CutResultKind {
  /// A finished part.
  part,

  /// Leftover material that is not cut any further.
  remnant,

  /// A smaller workpiece that gets cut again in a later step.
  workpiece,

  /// Nothing: a strip no wider than the blade, turned into sawdust.
  /// [CutResult.rect] is that strip.
  waste,
}

class CutResult {
  final CutResultKind kind;
  final PackingRect rect;

  /// Set for [CutResultKind.part] when the part could be identified.
  final String? partName;

  const CutResult(this.kind, this.rect, {this.partName});
}

/// One step of the instruction: make [cut]; [first] and [second] are the
/// left/right sides of a vertical cut, top/bottom of a horizontal one.
class CuttingStep {
  final GuideCut cut;
  final CutResult first;
  final CutResult second;

  const CuttingStep(this.cut, this.first, this.second);
}

/// [guide]'s cuts as ordered steps, in [preorderCuts] order: each step's
/// workpiece is something an earlier step produced. [partNameAt] names the
/// part at a given rect, or returns null.
List<CuttingStep> buildCuttingSteps(
  GuillotineSliceNode guide,
  String? Function(PackingRect rect) partNameAt,
) {
  CutResult describe(GuillotineSliceNode node) => switch (node) {
    GuillotineCutNode(:final cut) => CutResult(CutResultKind.workpiece, cut.workRect),
    GuillotineLeafNode(:final rect, isPart: false) => CutResult(CutResultKind.remnant, rect),
    GuillotineLeafNode(:final rect) => CutResult(
      CutResultKind.part,
      rect,
      partName: partNameAt(rect),
    ),
  };

  CutResult wasteStrip(GuideCut cut, {required bool first}) {
    final w = cut.workRect;
    final start = first ? 0.0 : cut.offset;
    return CutResult(
      CutResultKind.waste,
      cut.orientation == CutOrientation.vertical
          ? PackingRect(x: w.x + start, y: w.y, width: cut.kerfWidth, height: w.height)
          : PackingRect(x: w.x, y: w.y + start, width: w.width, height: cut.kerfWidth),
    );
  }

  List<CuttingStep> walk(GuillotineSliceNode node) => switch (node) {
    GuillotineCutNode(:final cut, :final first, :final second) => [
      CuttingStep(
        cut,
        cut.firstSideIsWaste ? wasteStrip(cut, first: true) : describe(first),
        cut.secondSideIsWaste ? wasteStrip(cut, first: false) : describe(second),
      ),
      ...walk(first),
      ...walk(second),
    ],
    GuillotineLeafNode() => const [],
  };

  return walk(guide);
}

/// Finds a straight-cut sequence that reproduces [pieces] where they are on a
/// [sheetWidth]x[sheetHeight] sheet, with a blade [kerf] wide. Returns null if
/// there is none: a pinwheel arrangement, overlapping or off-sheet pieces, or
/// two pieces closer together than the blade.
///
/// The guide is derived from final positions rather than recorded while
/// packing, so it works for any packer whose output happens to be
/// guillotine-cuttable, and for layouts edited by hand afterwards.
///
/// The blade is modelled physically. A separating cut runs right after the
/// pieces before it and removes exactly [kerf]; any wider gap is real
/// material that a later trim cut takes off as a remnant (a 200 mm gap cut
/// with a 4 mm blade leaves a 196 mm strip on the next workpiece). Edge trims
/// put the blade on the waste side, so remnant sizes are what is really left.
///
/// Most layouts have many valid cut orders, and the order decides how the
/// empty space ends up: cut across a big empty area early and it stays one
/// offcut, cut the parts around it first and it comes out as scraps that
/// each cost a cut. With [optimize] this picks the order with the fewest
/// cuts and, among those, the largest whole remnant. The search is memoized
/// per region and falls back to the first valid cut past a budget, so it
/// always finishes quickly. With [optimize] = false it returns the first
/// valid sequence, which is enough to answer "is this cuttable at all?".
GuillotineSliceNode? deriveCuttingGuide(
  double sheetWidth,
  double sheetHeight,
  List<PackingRect> pieces, {
  double kerf = 0,
  double tolerance = 0.01,
  bool optimize = true,
}) {
  assert(kerf >= 0, 'kerf must not be negative');
  for (final p in pieces) {
    if (p.x < -tolerance ||
        p.y < -tolerance ||
        p.right > sheetWidth + tolerance ||
        p.bottom > sheetHeight + tolerance) {
      return null;
    }
  }
  final solver = _GuideSolver(tolerance, math.max(0.0, kerf), optimize);
  return solver
      .solve(PackingRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight), pieces)
      ?.tree;
}

/// Number of saw cuts in [guide].
int countCuts(GuillotineSliceNode guide) => switch (guide) {
  GuillotineCutNode(:final first, :final second) => 1 + countCuts(first) + countCuts(second),
  GuillotineLeafNode() => 0,
};

/// The leftover pieces [guide] ends with: every free leaf that still has
/// material in it.
List<PackingRect> remnantRects(GuillotineSliceNode guide) => switch (guide) {
  GuillotineCutNode(:final first, :final second) => [
    ...remnantRects(first),
    ...remnantRects(second),
  ],
  GuillotineLeafNode(:final rect) => guide.isFree && !guide.isEmpty ? [rect] : const [],
};

/// The cuts in an order an operator can follow: each cut comes before the
/// cuts inside the pieces it produces.
List<GuideCut> preorderCuts(GuillotineSliceNode node) => switch (node) {
  GuillotineCutNode(:final cut, :final first, :final second) => [
    cut,
    ...preorderCuts(first),
    ...preorderCuts(second),
  ],
  GuillotineLeafNode() => const [],
};

class _Solution {
  final GuillotineSliceNode tree;
  final int cuts;
  final double largestFree;

  const _Solution(this.tree, this.cuts, this.largestFree);

  /// Fewer cuts first; at equal cuts, the bigger whole remnant.
  bool betterThan(_Solution other) =>
      cuts != other.cuts ? cuts < other.cuts : largestFree > other.largestFree + 1e-9;
}

class _Plan {
  final GuideCut cut;
  final PackingRect firstRegion;
  final List<PackingRect> firstPieces;
  final PackingRect secondRegion;
  final List<PackingRect> secondPieces;

  const _Plan(this.cut, this.firstRegion, this.firstPieces, this.secondRegion, this.secondPieces);
}

class _GuideSolver {
  final double eps;
  final double kerf;
  final bool optimize;

  _GuideSolver(this.eps, this.kerf, this.optimize);

  final Map<String, _Solution?> _memo = {};
  var _expanded = 0;

  /// Regions that get the full "try every cut" search before the rest settle
  /// for the first valid cut. A 5x14 grid of equal parts is about 1500
  /// regions; real layouts are far below that.
  static const int _fullSearchBudget = 4000;

  bool get _greedy => !optimize || _expanded > _fullSearchBudget;

  // Every split partitions the pieces by position, so the pieces inside a
  // region follow from the region alone, which makes it a sound memo key.
  _Solution? solve(PackingRect region, List<PackingRect> pieces) {
    if (pieces.isEmpty) {
      return _Solution(GuillotineLeafNode.free(region), 0, region.area);
    }
    if (pieces.length == 1 && _fills(region, pieces.first)) {
      return _Solution(GuillotineLeafNode.part(region), 0, 0);
    }
    final key =
        '${region.x.toStringAsFixed(3)},${region.y.toStringAsFixed(3)},'
        '${region.width.toStringAsFixed(3)},${region.height.toStringAsFixed(3)}';
    if (_memo.containsKey(key)) return _memo[key];
    _expanded++;

    _Solution? best;
    for (final plan in _plans(region, pieces)) {
      final first = solve(plan.firstRegion, plan.firstPieces);
      if (first == null) continue;
      final second = solve(plan.secondRegion, plan.secondPieces);
      if (second == null) continue;
      final candidate = _Solution(
        GuillotineCutNode(plan.cut, first.tree, second.tree),
        1 + first.cuts + second.cuts,
        math.max(first.largestFree, second.largestFree),
      );
      if (best == null || candidate.betterThan(best)) best = candidate;
      if (_greedy) break;
    }
    _memo[key] = best;
    return best;
  }

  bool _fills(PackingRect region, PackingRect piece) =>
      (piece.x - region.x).abs() <= eps &&
      (piece.y - region.y).abs() <= eps &&
      (piece.width - region.width).abs() <= eps &&
      (piece.height - region.height).abs() <= eps;

  /// Every way to make the next cut in [region]. Empty strips along the
  /// region's edges are trimmed off first when there are any; otherwise every
  /// gap that no piece crosses and that is at least a blade wide is a
  /// candidate.
  List<_Plan> _plans(PackingRect region, List<PackingRect> pieces) {
    final left = pieces.map((p) => p.x).reduce(math.min);
    final right = pieces.map((p) => p.right).reduce(math.max);
    final top = pieces.map((p) => p.y).reduce(math.min);
    final bottom = pieces.map((p) => p.bottom).reduce(math.max);

    final plans = <_Plan>[];
    void add(_Plan? plan) {
      if (plan != null) plans.add(plan);
    }

    if (top - region.y > eps) {
      add(_leadingTrim(region, pieces, vertical: false, strip: top - region.y));
    }
    if (region.bottom - bottom > eps) {
      add(_trailingTrim(region, pieces, vertical: false, keep: bottom - region.y));
    }
    if (left - region.x > eps) {
      add(_leadingTrim(region, pieces, vertical: true, strip: left - region.x));
    }
    if (region.right - right > eps) {
      add(_trailingTrim(region, pieces, vertical: true, keep: right - region.x));
    }
    if (plans.isNotEmpty) return plans;

    for (final vertical in [false, true]) {
      final sorted = [...pieces]
        ..sort((a, b) => vertical ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
      var reach = double.negativeInfinity;
      for (var i = 0; i < sorted.length - 1; i++) {
        final end = vertical ? sorted[i].right : sorted[i].bottom;
        if (end > reach) reach = end;
        final nextStart = vertical ? sorted[i + 1].x : sorted[i + 1].y;
        // A later piece still overlaps this stretch.
        if (nextStart < reach - eps) continue;
        // The blade needs a full kerf of clearance or it bites into the next
        // piece.
        if (nextStart - reach < kerf - eps) continue;
        final offset = reach - (vertical ? region.x : region.y);
        final cut = GuideCut.tryCreate(
          region,
          vertical ? CutOrientation.vertical : CutOrientation.horizontal,
          offset,
          kerf,
        );
        if (cut == null) continue;
        // Material between the blade and the next piece stays on the second
        // workpiece; its own solve trims it off as a remnant.
        final firstRegion = _slice(region, vertical: vertical, from: 0, size: offset);
        final secondRegion = _slice(
          region,
          vertical: vertical,
          from: offset + kerf,
          size: cut.span - offset - kerf,
        );
        plans.add(
          _Plan(cut, firstRegion, sorted.sublist(0, i + 1), secondRegion, sorted.sublist(i + 1)),
        );
      }
    }
    return plans;
  }

  /// Takes an empty [strip] off the leading (top/left) edge with the blade on
  /// the waste side. What is left of the strip is a remnant, or nothing when
  /// the strip is no wider than the blade.
  _Plan? _leadingTrim(
    PackingRect region,
    List<PackingRect> pieces, {
    required bool vertical,
    required double strip,
  }) {
    final orientation = vertical ? CutOrientation.vertical : CutOrientation.horizontal;
    final waste = strip - kerf;
    final cut =
        waste > eps
            ? GuideCut.tryCreate(region, orientation, waste, kerf)
            : GuideCut.tryCreate(region, orientation, 0, strip);
    if (cut == null) return null;
    final firstSize = waste > eps ? waste : 0.0;
    return _Plan(
      cut,
      _slice(region, vertical: vertical, from: 0, size: firstSize),
      const [],
      _slice(region, vertical: vertical, from: strip, size: cut.span - strip),
      pieces,
    );
  }

  /// Cuts off everything past [keep] on the trailing (bottom/right) edge,
  /// blade on the waste side.
  _Plan? _trailingTrim(
    PackingRect region,
    List<PackingRect> pieces, {
    required bool vertical,
    required double keep,
  }) {
    final orientation = vertical ? CutOrientation.vertical : CutOrientation.horizontal;
    final span = vertical ? region.width : region.height;
    final strip = span - keep;
    final waste = strip - kerf;
    final cut = GuideCut.tryCreate(region, orientation, keep, waste > eps ? kerf : strip);
    if (cut == null) return null;
    final secondFrom = waste > eps ? keep + kerf : span;
    return _Plan(
      cut,
      _slice(region, vertical: vertical, from: 0, size: keep),
      pieces,
      _slice(region, vertical: vertical, from: secondFrom, size: span - secondFrom),
      const [],
    );
  }

  /// The part of [region] from [from] to [from] + [size] along the cut axis.
  static PackingRect _slice(
    PackingRect region, {
    required bool vertical,
    required double from,
    required double size,
  }) =>
      vertical
          ? PackingRect(x: region.x + from, y: region.y, width: size, height: region.height)
          : PackingRect(x: region.x, y: region.y + from, width: region.width, height: size);
}
