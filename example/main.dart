import 'dart:math';

import 'package:panel_cutting/panel_cutting.dart';

/// Cuts a small kitchen cabinet order from 2800x2070 mm boards with a 4 mm
/// blade, searches for a better layout for half a second, and prints the cut
/// list for the first sheet.
Future<void> main() async {
  const parts = [
    Part('Side', width: 720, height: 560, quantity: 8, canRotate: false),
    Part('Bottom', width: 564, height: 560, quantity: 4),
    Part('Shelf', width: 564, height: 520, quantity: 6),
    Part('Door', width: 716, height: 396, quantity: 8, canRotate: false),
    Part('Back rail', width: 564, height: 100, quantity: 8),
  ];
  const sheetWidth = 2800.0;
  const sheetHeight = 2070.0;

  PackingResult build(Random? random) => packGuillotine(
    parts,
    sheetWidth: sheetWidth,
    sheetHeight: sheetHeight,
    kerf: 4,
    random: random,
    candidateListSize: random == null ? 1 : 3,
    randomizeRules: true,
  );

  var best = build(null);
  print('First layout: ${_summary(best)}');

  await for (final found in searchLayouts(
    build,
    polish: (layout) => layout.withSheets(consolidateSheets(layout.sheets, keepGuillotine: true)),
  ).timeout(const Duration(milliseconds: 500), onTimeout: (sink) => sink.close())) {
    best = found.layout;
  }
  print('After search:  ${_summary(best)}');
  print('Best possible: ${minimumSheets(parts, sheetWidth, sheetHeight)} sheets');

  final sheet = best.sheets.first;
  print('\nSheet 1 (${(sheet.utilization * 100).toStringAsFixed(1)}% used):');
  for (final (i, step) in (sheet.cuttingSteps() ?? const <CuttingStep>[]).indexed) {
    final cut = step.cut;
    final direction = cut.orientation == CutOrientation.vertical ? 'vertical' : 'horizontal';
    print(
      '${i + 1}. $direction cut at ${cut.markOffset.toStringAsFixed(0)} mm '
      'through ${_size(cut.workRect)} -> ${_describe(step.first)} | ${_describe(step.second)}',
    );
  }
}

String _summary(PackingResult r) =>
    '${r.sheetCount} sheets, ${(r.utilization * 100).toStringAsFixed(1)}% used, '
    '${totalCuts(r.sheets)} cuts';

String _size(PackingRect r) => '${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}';

String _describe(CutResult r) => switch (r.kind) {
  CutResultKind.part => r.partName ?? 'part',
  CutResultKind.remnant => 'offcut ${_size(r.rect)}',
  CutResultKind.workpiece => 'piece ${_size(r.rect)}',
  CutResultKind.waste => 'sawdust',
};
