import 'cutting_guide.dart';
import 'models.dart';
import 'rect.dart';

const double _eps = 1e-6;

/// Tries to empty the last sheets of a layout by moving their parts into
/// gaps on earlier sheets, and drops every sheet it empties.
///
/// Packers fill one sheet at a time and close it once the next part doesn't
/// fit where they are looking, so a part that would fit in an awkward gap
/// still gets a new sheet. This looks at the gaps again geometrically.
///
/// A sheet's parts move all or nothing (moving some of them saves nothing).
/// Parts keep at least the target sheet's kerf from each other. With
/// [keepGuillotine], a sheet that could be cut with straight cuts stays
/// cuttable.
List<Sheet> consolidateSheets(List<Sheet> sheets, {bool keepGuillotine = false}) {
  var result = sheets;
  while (result.length >= 2) {
    final next = _emptyLastSheet(result, keepGuillotine);
    if (next == null) break;
    result = next;
  }
  return result;
}

double _areaOf(Iterable<PlacedPart> parts) => parts.fold(0.0, (sum, p) => sum + p.area);

/// [sheets] without the last one, its parts moved to the others, or null if
/// that isn't possible.
List<Sheet>? _emptyLastSheet(List<Sheet> sheets, bool keepGuillotine) {
  final last = sheets.last;
  if (last.parts.isEmpty) return sheets.sublist(0, sheets.length - 1);
  final earlier = sheets.sublist(0, sheets.length - 1);

  if (earlier.fold(0.0, (sum, s) => sum + s.freeArea) < last.usedArea) return null;

  // Fullest sheets first, so the emptiest keeps its big remnant whole.
  final targets = List<int>.generate(earlier.length, (i) => i)
    ..sort((a, b) => earlier[a].freeArea.compareTo(earlier[b].freeArea));

  // Placements are only planned until every part has a spot, so a failure
  // leaves the layout as it was.
  final planned = <int, List<PlacedPart>>{};
  final parts = [...last.parts]..sort((a, b) => b.area.compareTo(a.area));
  for (final part in parts) {
    PlacedPart? spot;
    for (final i in targets) {
      final extra = planned[i] ?? const [];
      if (earlier[i].freeArea - _areaOf(extra) < part.area) continue;
      spot = _findSpot(earlier[i], [...earlier[i].parts, ...extra], part, keepGuillotine);
      if (spot != null) {
        (planned[i] ??= []).add(spot);
        break;
      }
    }
    if (spot == null) return null;
  }

  return [
    for (var i = 0; i < earlier.length; i++)
      planned[i] == null
          ? earlier[i]
          : Sheet(earlier[i].width, earlier[i].height, [
            ...earlier[i].parts,
            ...planned[i]!,
          ], kerf: earlier[i].kerf),
  ];
}

/// The top-left-most spot on [sheet] where [part] fits with at least the
/// kerf clear all round, trying it turned when allowed.
PlacedPart? _findSpot(Sheet sheet, List<PlacedPart> onSheet, PlacedPart part, bool keepGuillotine) {
  final kerf = sheet.kerf;
  final others = [for (final p in onSheet) p.rect];
  // Only a sheet that is cuttable now has anything to preserve.
  final mustStayCuttable =
      keepGuillotine &&
      deriveCuttingGuide(sheet.width, sheet.height, others, kerf: kerf, optimize: false) != null;

  final orientations = [
    (w: part.width, h: part.height, turned: false),
    if (part.part.canRotate && (part.width - part.height).abs() > _eps)
      (w: part.height, h: part.width, turned: true),
  ];

  for (final o in orientations) {
    if (o.w > sheet.width + _eps || o.h > sheet.height + _eps) continue;

    // A part only needs to sit flush with the sheet edge or one kerf from a
    // neighbour, so those are the only coordinates worth trying.
    final xs =
        {
            0.0,
            for (final r in others) ...[r.x, r.right + kerf],
          }.where((x) => x + o.w <= sheet.width + _eps).toList()
          ..sort();
    final ys =
        {
            0.0,
            for (final r in others) ...[r.y, r.bottom + kerf],
          }.where((y) => y + o.h <= sheet.height + _eps).toList()
          ..sort();

    for (final y in ys) {
      for (final x in xs) {
        if (!_isClear(others, x, y, o.w, o.h, kerf)) continue;
        final rect = PackingRect(x: x, y: y, width: o.w, height: o.h);
        if (mustStayCuttable &&
            deriveCuttingGuide(
                  sheet.width,
                  sheet.height,
                  [...others, rect],
                  kerf: kerf,
                  optimize: false,
                ) ==
                null) {
          continue;
        }
        return PlacedPart(
          part.part,
          x: x,
          y: y,
          width: o.w,
          height: o.h,
          rotated: o.turned ? !part.rotated : part.rotated,
        );
      }
    }
  }
  return null;
}

/// Whether a [w]x[h] rectangle at ([x], [y]) stays at least [gap] away from
/// all of [others].
bool _isClear(List<PackingRect> others, double x, double y, double w, double h, double gap) {
  for (final r in others) {
    final apart =
        x + w + gap <= r.x + _eps ||
        r.right + gap <= x + _eps ||
        y + h + gap <= r.y + _eps ||
        r.bottom + gap <= y + _eps;
    if (!apart) return false;
  }
  return true;
}
