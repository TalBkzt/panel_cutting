import 'cutting_guide.dart';
import 'rect.dart';

/// A part to cut, [quantity] times. Sizes are in whatever unit the caller
/// uses for the sheet (usually mm).
class Part {
  final String label;
  final double width;
  final double height;
  final int quantity;

  /// False for parts that must keep their orientation, e.g. because of the
  /// grain direction of the board.
  final bool canRotate;

  const Part(
    this.label, {
    required this.width,
    required this.height,
    this.quantity = 1,
    this.canRotate = true,
  }) : assert(width > 0 && height > 0),
       assert(quantity >= 0);

  double get area => width * height;

  bool fitsOn(double sheetWidth, double sheetHeight) =>
      (width <= sheetWidth && height <= sheetHeight) ||
      (canRotate && height <= sheetWidth && width <= sheetHeight);

  @override
  String toString() => 'Part($label, ${width}x$height x$quantity)';
}

/// One unit of a [Part] placed on a sheet. [width]/[height] are the placed
/// size, i.e. already swapped when [rotated].
class PlacedPart {
  final Part part;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool rotated;

  const PlacedPart(
    this.part, {
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotated = false,
  });

  String get label => part.label;
  double get area => width * height;
  PackingRect get rect => PackingRect(x: x, y: y, width: width, height: height);

  @override
  String toString() => 'PlacedPart($label at $x,$y ${width}x$height${rotated ? ' rotated' : ''})';
}

/// One sheet of a layout.
class Sheet {
  final double width;
  final double height;

  /// Saw blade width the sheet was packed for: parts are at least this far
  /// apart, and every cut of [cuttingGuide] removes this much material.
  final double kerf;

  final List<PlacedPart> parts;

  Sheet(this.width, this.height, List<PlacedPart> parts, {this.kerf = 0})
    : parts = List.unmodifiable(parts);

  double get area => width * height;
  double get usedArea => parts.fold(0.0, (sum, p) => sum + p.area);
  double get freeArea => area - usedArea;

  /// Share of the sheet covered by parts, 0..1.
  double get utilization => area == 0 ? 0 : usedArea / area;

  /// The panel saw cut sequence for this sheet, or null when the layout can't
  /// be cut with straight edge-to-edge cuts. See [deriveCuttingGuide].
  late final GuillotineSliceNode? cuttingGuide = deriveCuttingGuide(width, height, [
    for (final p in parts) p.rect,
  ], kerf: kerf);

  /// Step-by-step cutting instruction with part labels, or null if the sheet
  /// has no [cuttingGuide].
  List<CuttingStep>? cuttingSteps() {
    final guide = cuttingGuide;
    if (guide == null) return null;
    return buildCuttingSteps(guide, (rect) {
      for (final p in parts) {
        if ((p.x - rect.x).abs() < 0.01 &&
            (p.y - rect.y).abs() < 0.01 &&
            (p.width - rect.width).abs() < 0.01 &&
            (p.height - rect.height).abs() < 0.01) {
          return p.label;
        }
      }
      return null;
    });
  }
}

/// The output of a packer.
class PackingResult {
  final double sheetWidth;
  final double sheetHeight;
  final List<Sheet> sheets;

  /// Units that don't fit on an empty sheet in any allowed orientation, one
  /// entry per unit.
  final List<Part> oversized;

  PackingResult({
    required this.sheetWidth,
    required this.sheetHeight,
    required List<Sheet> sheets,
    List<Part> oversized = const [],
  }) : sheets = List.unmodifiable(sheets),
       oversized = List.unmodifiable(oversized);

  int get sheetCount => sheets.length;
  int get placedCount => sheets.fold(0, (sum, s) => sum + s.parts.length);
  double get placedArea => sheets.fold(0.0, (sum, s) => sum + s.usedArea);

  /// Share of all used sheets covered by parts, 0..1.
  double get utilization {
    final total = sheets.length * sheetWidth * sheetHeight;
    return total == 0 ? 0 : placedArea / total;
  }

  PackingResult withSheets(List<Sheet> sheets) => PackingResult(
    sheetWidth: sheetWidth,
    sheetHeight: sheetHeight,
    sheets: sheets,
    oversized: oversized,
  );
}

/// Order in which parts are fed to a packer, largest first by the given
/// measure. Area is the classic first-fit-decreasing baseline; the others
/// give different layouts, which is useful when searching.
enum PartOrder {
  area,
  longerSide,
  perimeter,
  width,
  height;

  double keyOf(Part p) => switch (this) {
    PartOrder.area => p.width * p.height,
    PartOrder.longerSide => p.width > p.height ? p.width : p.height,
    PartOrder.perimeter => p.width + p.height,
    PartOrder.width => p.width,
    PartOrder.height => p.height,
  };
}

/// Expands [parts] into one entry per unit, split into those that fit on a
/// [sheetWidth]x[sheetHeight] sheet and those that never will.
({List<Part> fitting, List<Part> oversized}) expandUnits(
  List<Part> parts,
  double sheetWidth,
  double sheetHeight,
) {
  final fitting = <Part>[];
  final oversized = <Part>[];
  for (final part in parts) {
    final target = part.fitsOn(sheetWidth, sheetHeight) ? fitting : oversized;
    for (var i = 0; i < part.quantity; i++) {
      target.add(part);
    }
  }
  return (fitting: fitting, oversized: oversized);
}
