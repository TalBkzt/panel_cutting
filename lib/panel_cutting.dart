/// 2D cutting optimization for panel saws.
library;

export 'src/consolidation.dart' show consolidateSheets;
export 'src/cutting_guide.dart';
export 'src/empty_rects.dart' show findEmptyRects;
export 'src/guillotine.dart';
export 'src/layout_quality.dart';
export 'src/max_rects.dart';
export 'src/models.dart' hide expandUnits;
export 'src/rect.dart';
export 'src/search.dart';
