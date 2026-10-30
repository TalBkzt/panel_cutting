import 'dart:async';
import 'dart:math';

import 'layout_quality.dart';
import 'models.dart';

/// Produces one layout. Called with null once for a deterministic baseline,
/// then repeatedly with a [Random] to get varied layouts.
typedef LayoutBuilder = PackingResult Function(Random? random);

/// A layout found by [searchLayouts].
class SearchResult {
  final PackingResult layout;

  /// Attempts made when this layout was found.
  final int iterations;
  final Duration elapsed;

  const SearchResult(this.layout, this.iterations, this.elapsed);
}

/// Keeps calling [build] with a random source and emits each layout that
/// [isBetterLayout] ranks above the best so far. The first event is the
/// deterministic `build(null)` result, so stopping early is never worse than
/// not searching.
///
/// The stream runs until the listener cancels or [maxIterations] attempts
/// have been made. [polish] (e.g. `consolidateSheets`) runs only on a new
/// best, not on every attempt, since it's usually much slower than [build].
///
/// The search runs on the current isolate. One attempt is cheap, and between
/// attempts it waits [pause]; keep that above zero in Flutter, where a tight
/// loop of zero-length timers can starve frame rendering. Improvements are
/// emitted at most once per [emitInterval] (the latest one is never lost),
/// and [onProgress] gets the attempt count on the same schedule, so a UI can
/// show the search is alive while the best layout stays the same.
Stream<SearchResult> searchLayouts(
  LayoutBuilder build, {
  PackingResult Function(PackingResult layout)? polish,
  Random? random,
  int? maxIterations,
  Duration pause = const Duration(milliseconds: 4),
  Duration emitInterval = const Duration(milliseconds: 250),
  void Function(int iterations)? onProgress,
}) {
  // An async* generator only notices a cancel at a yield, and this loop
  // stops yielding once it stops finding improvements, so it would never
  // stop. A controller with an explicit flag does.
  late final StreamController<SearchResult> controller;
  var stopped = false;

  Future<void> run() async {
    final clock = Stopwatch()..start();
    var iterations = 1;
    var best = SearchResult(build(null), iterations, clock.elapsed);
    if (stopped) return;
    controller.add(best);
    await Future<void>.delayed(pause);

    final rand = random ?? Random();
    final sinceEmit = Stopwatch()..start();
    SearchResult? unsent;
    while (!stopped && (maxIterations == null || iterations < maxIterations)) {
      iterations++;
      final candidate = build(rand);
      if (isBetterLayout(candidate, best.layout)) {
        best = SearchResult(polish?.call(candidate) ?? candidate, iterations, clock.elapsed);
        unsent = best;
      }
      if (sinceEmit.elapsed >= emitInterval) {
        if (stopped) return;
        if (unsent != null) {
          controller.add(unsent);
          unsent = null;
        }
        onProgress?.call(iterations);
        sinceEmit.reset();
      }
      await Future<void>.delayed(pause);
    }
    if (!stopped && unsent != null) controller.add(unsent);
  }

  controller = StreamController<SearchResult>(
    onListen:
        () => run().whenComplete(() {
          if (!controller.isClosed) controller.close();
        }),
    onCancel: () => stopped = true,
  );
  return controller.stream;
}
