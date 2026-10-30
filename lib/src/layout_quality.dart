import 'dart:math' as math;

import 'cutting_guide.dart';
import 'empty_rects.dart';
import 'models.dart';
import 'rect.dart';

/// Total area of the parts that fit on a [sheetWidth]x[sheetHeight] sheet at
/// all (bigger ones are never placed by any packer).
double fittableArea(List<Part> parts, double sheetWidth, double sheetHeight) => parts
    .where((p) => p.fitsOn(sheetWidth, sheetHeight))
    .fold(0.0, (sum, p) => sum + p.area * p.quantity);

/// Lower bound on the number of sheets: total part area over sheet area,
/// rounded up. No layout can use fewer.
int minimumSheets(List<Part> parts, double sheetWidth, double sheetHeight) {
  final sheetArea = sheetWidth * sheetHeight;
  final area = fittableArea(parts, sheetWidth, sheetHeight);
  if (sheetArea <= 0 || area <= 0) return 0;
  return (area / sheetArea - 1e-9).ceil();
}

/// Upper bound on utilization (0..1): everything packed into exactly
/// [minimumSheets] sheets. Parts totalling 3.4 sheets need 4 sheets, so no
/// layout of them can be better than 85%.
double maximumUtilization(List<Part> parts, double sheetWidth, double sheetHeight) {
  final sheets = minimumSheets(parts, sheetWidth, sheetHeight);
  if (sheets == 0) return 0;
  return fittableArea(parts, sheetWidth, sheetHeight) / (sheets * sheetWidth * sheetHeight);
}

/// Saw cuts needed for [sheet]. A sheet that can't be cut with straight cuts
/// gets one per part plus one, the same for any layout of the same parts, so
/// it never tips a comparison either way.
int cutsOf(Sheet sheet) {
  final guide = sheet.cuttingGuide;
  return guide == null ? sheet.parts.length + 1 : countCuts(guide);
}

int totalCuts(List<Sheet> sheets) => sheets.fold(0, (sum, s) => sum + cutsOf(s));

/// Total saw travel on [sheet]; 0 when it has no cutting guide.
double cutLengthOf(Sheet sheet) {
  final guide = sheet.cuttingGuide;
  return guide == null ? 0 : preorderCuts(guide).fold(0.0, (sum, c) => sum + c.length);
}

double totalCutLength(List<Sheet> sheets) => sheets.fold(0.0, (sum, s) => sum + cutLengthOf(s));

/// Area of the biggest leftover piece on [sheet] once it's cut. Without a
/// cutting guide, the biggest empty rectangle.
double largestRemnantOf(Sheet sheet) {
  final guide = sheet.cuttingGuide;
  if (guide != null) {
    return remnantRects(guide).fold(0.0, (m, r) => math.max(m, r.area));
  }
  final rects = findEmptyRects(sheet.width, sheet.height, [
    for (final p in sheet.parts) p.rect,
  ], maxCount: 1);
  return rects.isEmpty ? 0 : rects.first.area;
}

/// Leftover pieces of [sheet] with both sides at least [minSide]: what the
/// cutting guide ends with, or the biggest empty rectangles without one.
List<PackingRect> offcutsOf(Sheet sheet, {required double minSide}) {
  final guide = sheet.cuttingGuide;
  if (guide != null) {
    return remnantRects(guide).where((r) => math.min(r.width, r.height) >= minSide).toList();
  }
  return findEmptyRects(sheet.width, sheet.height, [
    for (final p in sheet.parts) p.rect,
  ], minSide: minSide);
}

/// How many of the emptiest sheets [isBetterLayout] looks at for remnants.
/// Most sheets of a layout are packed tight anyway, and computing remnants on
/// every sheet of a big order slows a search down noticeably.
const int remnantSheetCap = 3;

/// Sum of the largest remnant on each of the [remnantSheetCap] emptiest
/// sheets.
double sparsestSheetsRemnantArea(List<Sheet> sheets) {
  final emptiestFirst = [...sheets]..sort((a, b) => a.usedArea.compareTo(b.usedArea));
  return emptiestFirst.take(remnantSheetCap).fold(0.0, (sum, s) => sum + largestRemnantOf(s));
}

/// Whether [candidate] is a real improvement over [current], by in turn:
///
/// 1. more parts placed (a layout that saves a sheet by dropping a part
///    never wins);
/// 2. fewer sheets;
/// 3. more area placed, by more than 0.5% of a sheet;
/// 4. fewer saw cuts in total;
/// 5. bigger whole remnants on the emptiest sheets.
///
/// An exact tie is not an improvement.
bool isBetterLayout(PackingResult candidate, PackingResult current) {
  final placedDiff = candidate.placedCount - current.placedCount;
  if (placedDiff != 0) return placedDiff > 0;
  if (candidate.sheetCount != current.sheetCount) {
    return candidate.sheetCount < current.sheetCount;
  }
  final tolerance = candidate.sheetWidth * candidate.sheetHeight * 0.005;
  final areaDiff = candidate.placedArea - current.placedArea;
  if (areaDiff.abs() > tolerance) return areaDiff > 0;
  final cutDiff = totalCuts(candidate.sheets) - totalCuts(current.sheets);
  if (cutDiff != 0) return cutDiff < 0;
  return sparsestSheetsRemnantArea(candidate.sheets) > sparsestSheetsRemnantArea(current.sheets);
}
