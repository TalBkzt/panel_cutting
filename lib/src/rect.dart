/// Axis-aligned rectangle. Not `dart:ui`'s `Rect`, so the package stays
/// pure Dart.
class PackingRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const PackingRect({required this.x, required this.y, required this.width, required this.height});

  double get right => x + width;
  double get bottom => y + height;
  double get area => width * height;

  bool intersects(PackingRect other) =>
      x < other.right && right > other.x && y < other.bottom && bottom > other.y;

  bool contains(PackingRect other) =>
      x <= other.x && y <= other.y && right >= other.right && bottom >= other.bottom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackingRect &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'PackingRect($x, $y, $width, $height)';
}
