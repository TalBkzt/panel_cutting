import 'dart:async';
import 'dart:math';

import 'package:panel_cutting/panel_cutting.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final parts = randomParts(Random(11));

  PackingResult build(Random? random) => packGuillotine(
    parts,
    sheetWidth: 2070,
    sheetHeight: 2800,
    kerf: 4,
    random: random,
    candidateListSize: random == null ? 1 : 3,
    randomizeRules: true,
  );

  Stream<SearchResult> search({int? maxIterations}) => searchLayouts(
    build,
    random: Random(1),
    maxIterations: maxIterations,
    pause: Duration.zero,
    emitInterval: Duration.zero,
  );

  test('the first result is the deterministic layout', () async {
    final first = await search().first;
    expect(first.iterations, 1);
    expect(first.layout.sheetCount, build(null).sheetCount);
  });

  test('every result is better than the one before', () async {
    final results = await search(maxIterations: 300).toList();
    expect(results, isNotEmpty);
    for (var i = 1; i < results.length; i++) {
      expect(isBetterLayout(results[i].layout, results[i - 1].layout), isTrue);
    }
    for (final res in results) {
      expectAllAccountedFor(parts, res.layout);
    }
  });

  test('stops by itself after maxIterations', () async {
    final results = await search(maxIterations: 50).toList();
    expect(results.last.iterations, lessThanOrEqualTo(50));
  });

  test('a seeded search is reproducible', () async {
    final a = await search(maxIterations: 100).toList();
    final b = await search(maxIterations: 100).toList();
    expect(a.map((x) => x.iterations), b.map((x) => x.iterations));
  });

  test('stops working once the listener cancels', () async {
    var calls = 0;
    final stream = searchLayouts((random) {
      calls++;
      return build(random);
    }, pause: Duration.zero);
    final sub = stream.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    final atCancel = calls;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, lessThanOrEqualTo(atCancel + 1));
  });

  test('polish runs only on improvements', () async {
    var polished = 0;
    final results =
        await searchLayouts(
          build,
          polish: (layout) {
            polished++;
            return layout.withSheets(consolidateSheets(layout.sheets, keepGuillotine: true));
          },
          random: Random(2),
          maxIterations: 200,
          pause: Duration.zero,
          emitInterval: Duration.zero,
        ).toList();
    expect(polished, results.length - 1);
  });
}
