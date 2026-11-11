/// Hằng số hình học sơ đồ tĩnh của bàn libre (theo mẫu TikZ trong đặc tả).
/// Đây là đơn vị sơ đồ, không phải kích thước vật lý cm/mm hay tham số mô phỏng.
class TableConstants {
  const TableConstants._();

  static const double frameMinX = -20.0;
  static const double frameMinY = -20.0;
  static const double frameMaxX = 208.0;
  static const double frameMaxY = 396.0;

  static const double railMinX = -5.0;
  static const double railMinY = -5.0;
  static const double railMaxX = 193.0;
  static const double railMaxY = 381.0;

  static const double playfieldWidth = 188.0;
  static const double playfieldHeight = 376.0;

  static const double defaultBallRadius = 4.0;

  static const List<double> shortRailDiamondX = [0.0, 47.0, 94.0, 141.0, 188.0];
  static const List<double> longRailDiamondY = [
    0.0,
    47.0,
    94.0,
    141.0,
    188.0,
    235.0,
    282.0,
    329.0,
    376.0,
  ];
}

