// Các kiểu liệt kê cốt lõi cho LibreBilliard.
// Chỉ mô tả phân loại biên tập và trạng thái tĩnh; không chứa thông số vật lý.

enum ArticleKind {
  technique('technique', 'Kĩ thuật', 'KT'),
  system('system', 'Bộ số', 'BS'),
  position('position', 'Hình bi', 'HB');

  const ArticleKind(this.storageKey, this.label, this.codePrefix);

  final String storageKey;
  final String label;
  final String codePrefix;

  static ArticleKind fromKey(String key) {
    return ArticleKind.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => ArticleKind.position,
    );
  }
}

enum Difficulty {
  basic('basic', 'Cơ bản'),
  intermediate('intermediate', 'Trung cấp'),
  advanced('advanced', 'Nâng cao'),
  unrated('unrated', 'Chưa đánh giá');

  const Difficulty(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static Difficulty fromKey(String key) {
    return Difficulty.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => Difficulty.unrated,
    );
  }
}

enum PracticeStatus {
  notStarted('not_started', 'Chưa tập'),
  practicing('practicing', 'Đang tập'),
  practiced('practiced', 'Đã tập');

  const PracticeStatus(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static PracticeStatus fromKey(String key) {
    return PracticeStatus.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => PracticeStatus.notStarted,
    );
  }
}

enum BallColor {
  white('white', 'Bi trắng'),
  yellow('yellow', 'Bi vàng'),
  red('red', 'Bi đỏ');

  const BallColor(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static BallColor fromKey(String key) {
    return BallColor.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => BallColor.white,
    );
  }
}

enum SegmentType {
  line('line'),
  cubic('cubic');

  const SegmentType(this.storageKey);

  final String storageKey;

  static SegmentType fromKey(String key) {
    return SegmentType.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => throw FormatException('Kiểu đoạn đường không hợp lệ: $key'),
    );
  }
}

enum PathRole {
  ballCenter('ball_center', 'Quỹ đạo tâm bi'),
  auxiliary('auxiliary', 'Đường phụ minh họa');

  const PathRole(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static PathRole fromKey(String key) {
    return PathRole.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => PathRole.ballCenter,
    );
  }
}

enum AnnotationType {
  label('label'),
  sequence('sequence'),
  marker('marker'),
  circleZone('circle_zone'),
  rectZone('rect_zone');

  const AnnotationType(this.storageKey);

  final String storageKey;

  static AnnotationType fromKey(String key) {
    return AnnotationType.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => AnnotationType.label,
    );
  }
}
