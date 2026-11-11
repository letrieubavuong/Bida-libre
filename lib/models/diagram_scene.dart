import 'dart:math';
import 'enums.dart';

/// Điểm 2D trong hệ tọa độ sơ đồ bàn (đơn vị sơ đồ x: 0..188, y: 0..376).
class DiagramPoint {
  final double x;
  final double y;

  const DiagramPoint(this.x, this.y);

  bool get isFinite => x.isFinite && y.isFinite;

  DiagramPoint copyWith({double? x, double? y}) {
    return DiagramPoint(x ?? this.x, y ?? this.y);
  }

  DiagramPoint operator +(DiagramPoint other) =>
      DiagramPoint(x + other.x, y + other.y);

  DiagramPoint operator -(DiagramPoint other) =>
      DiagramPoint(x - other.x, y - other.y);

  double distanceTo(DiagramPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return sqrt(dx * dx + dy * dy);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory DiagramPoint.fromJson(Map<String, dynamic> json) {
    final rawX = json['x'];
    final rawY = json['y'];
    if (rawX is! num || rawY is! num) {
      throw const FormatException('Tọa độ điểm phải là giá trị số.');
    }
    final x = rawX.toDouble();
    final y = rawY.toDouble();
    if (!x.isFinite || !y.isFinite) {
      throw const FormatException('Tọa độ điểm phải hữu hạn.');
    }
    return DiagramPoint(x, y);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagramPoint &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'DiagramPoint(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// Một quả bi trên bàn.
class Ball {
  final String id;
  final BallColor color;
  final String label; // "1", "2", "3" hoặc tuỳ chọn
  final DiagramPoint center;
  final double radius; // Mặc định 4.0
  final bool locked;

  const Ball({
    required this.id,
    required this.color,
    this.label = '',
    required this.center,
    this.radius = 4.0,
    this.locked = false,
  });

  Ball copyWith({
    String? id,
    BallColor? color,
    String? label,
    DiagramPoint? center,
    double? radius,
    bool? locked,
  }) {
    return Ball(
      id: id ?? this.id,
      color: color ?? this.color,
      label: label ?? this.label,
      center: center ?? this.center,
      radius: radius ?? this.radius,
      locked: locked ?? this.locked,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'color': color.storageKey,
        'label': label,
        'center': center.toJson(),
        'radius': radius,
        'locked': locked,
      };

  factory Ball.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('ID bi không hợp lệ.');
    }
    final rawRadius = json['radius'];
    final radius = rawRadius == null
        ? 4.0
        : (rawRadius is num
            ? rawRadius.toDouble()
            : throw const FormatException('Bán kính bi phải là số.'));
    if (!radius.isFinite || radius <= 0) {
      throw const FormatException('Bán kính bi phải hữu hạn và lớn hơn 0.');
    }
    final centerJson = json['center'];
    if (centerJson is! Map<String, dynamic>) {
      throw const FormatException('Thiếu tọa độ tâm bi.');
    }
    return Ball(
      id: id,
      color: BallColor.fromKey(json['color'] as String),
      label: (json['label'] as String?) ?? '',
      center: DiagramPoint.fromJson(centerJson),
      radius: radius,
      locked: (json['locked'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ball &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          color == other.color &&
          label == other.label &&
          center == other.center &&
          radius == other.radius &&
          locked == other.locked;

  @override
  int get hashCode => Object.hash(id, color, label, center, radius, locked);
}

/// Đoạn trên đường hướng dẫn (thẳng hoặc Bézier bậc 3).
class PathSegment {
  final SegmentType type;
  final DiagramPoint start;
  final DiagramPoint end;
  final DiagramPoint? control1; // Dùng cho cubic
  final DiagramPoint? control2; // Dùng cho cubic

  const PathSegment.line({
    required this.start,
    required this.end,
  })  : type = SegmentType.line,
        control1 = null,
        control2 = null;

  const PathSegment.cubic({
    required this.start,
    required this.end,
    required this.control1,
    required this.control2,
  }) : type = SegmentType.cubic;

  Map<String, dynamic> toJson() => {
        'type': type.storageKey,
        'start': start.toJson(),
        'end': end.toJson(),
        if (control1 != null) 'control1': control1!.toJson(),
        if (control2 != null) 'control2': control2!.toJson(),
      };

  factory PathSegment.fromJson(Map<String, dynamic> json) {
    final type = SegmentType.fromKey(json['type'] as String);
    final start = DiagramPoint.fromJson(json['start'] as Map<String, dynamic>);
    final end = DiagramPoint.fromJson(json['end'] as Map<String, dynamic>);
    if (type == SegmentType.line) {
      return PathSegment.line(start: start, end: end);
    } else {
      return PathSegment.cubic(
        start: start,
        end: end,
        control1:
            DiagramPoint.fromJson(json['control1'] as Map<String, dynamic>),
        control2:
            DiagramPoint.fromJson(json['control2'] as Map<String, dynamic>),
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathSegment &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          start == other.start &&
          end == other.end &&
          control1 == other.control1 &&
          control2 == other.control2;

  @override
  int get hashCode => Object.hash(type, start, end, control1, control2);
}

/// Đường hướng dẫn tĩnh cho bi.
class GuidePath {
  final String id;
  final String ownerBallId; // Bi sở hữu đường
  final PathRole role;
  final List<PathSegment> segments;
  final bool isDashed;
  final double strokeWidth;
  final ArrowMode arrowMode;
  final int? customColorValue;
  final String? startAnchorBallId; // Gắn điểm đầu với tâm bi sở hữu

  GuidePath({
    required this.id,
    required this.ownerBallId,
    this.role = PathRole.ballCenter,
    required List<PathSegment> segments,
    this.isDashed = false,
    this.strokeWidth = 2.2,
    this.arrowMode = ArrowMode.end,
    this.customColorValue,
    this.startAnchorBallId,
  }) : segments = List<PathSegment>.unmodifiable(segments);

  GuidePath copyWith({
    String? id,
    String? ownerBallId,
    PathRole? role,
    List<PathSegment>? segments,
    bool? isDashed,
    double? strokeWidth,
    ArrowMode? arrowMode,
    int? customColorValue,
    bool clearCustomColor = false,
    String? startAnchorBallId,
    bool clearStartAnchor = false,
  }) {
    return GuidePath(
      id: id ?? this.id,
      ownerBallId: ownerBallId ?? this.ownerBallId,
      role: role ?? this.role,
      segments: segments ?? this.segments,
      isDashed: isDashed ?? this.isDashed,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      arrowMode: arrowMode ?? this.arrowMode,
      customColorValue:
          clearCustomColor ? null : (customColorValue ?? this.customColorValue),
      startAnchorBallId: clearStartAnchor
          ? null
          : (startAnchorBallId ?? this.startAnchorBallId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerBallId': ownerBallId,
        'role': role.storageKey,
        'segments': segments.map((s) => s.toJson()).toList(),
        'isDashed': isDashed,
        'strokeWidth': strokeWidth,
        'arrowMode': arrowMode.storageKey,
        if (customColorValue != null) 'customColorValue': customColorValue,
        if (startAnchorBallId != null) 'startAnchorBallId': startAnchorBallId,
      };

  factory GuidePath.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final ownerBallId = json['ownerBallId'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('ID đường hướng dẫn không hợp lệ.');
    }
    if (ownerBallId is! String || ownerBallId.trim().isEmpty) {
      throw const FormatException('ID bi sở hữu đường không hợp lệ.');
    }
    final rawSegments = json['segments'];
    if (rawSegments is! List<dynamic> || rawSegments.isEmpty) {
      throw const FormatException('Đường hướng dẫn phải có ít nhất một đoạn.');
    }
    final rawWidth = json['strokeWidth'];
    final strokeWidth = rawWidth == null
        ? 2.2
        : (rawWidth is num
            ? rawWidth.toDouble()
            : throw const FormatException('Độ dày nét vẽ phải là số.'));
    if (!strokeWidth.isFinite || strokeWidth <= 0) {
      throw const FormatException('Độ dày nét vẽ phải hữu hạn và lớn hơn 0.');
    }

    return GuidePath(
      id: id,
      ownerBallId: ownerBallId,
      role: PathRole.fromKey(json['role'] as String? ?? 'ball_center'),
      segments: rawSegments
          .map((s) => PathSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
      isDashed: (json['isDashed'] as bool?) ?? false,
      strokeWidth: strokeWidth,
      arrowMode: ArrowMode.fromKey(json['arrowMode'] as String? ?? 'end'),
      customColorValue: (json['customColorValue'] as num?)?.toInt(),
      startAnchorBallId: json['startAnchorBallId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GuidePath) return false;
    if (id != other.id ||
        ownerBallId != other.ownerBallId ||
        role != other.role ||
        isDashed != other.isDashed ||
        strokeWidth != other.strokeWidth ||
        arrowMode != other.arrowMode ||
        customColorValue != other.customColorValue ||
        startAnchorBallId != other.startAnchorBallId ||
        segments.length != other.segments.length) {
      return false;
    }
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] != other.segments[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        ownerBallId,
        role,
        isDashed,
        strokeWidth,
        arrowMode,
        customColorValue,
        startAnchorBallId,
        Object.hashAll(segments),
      );
}

/// Chú thích trên sơ đồ.
class DiagramAnnotation {
  final String id;
  final AnnotationType type;
  final DiagramPoint position;
  final String text;
  final int? colorValue;
  final bool locked;

  const DiagramAnnotation({
    required this.id,
    required this.type,
    required this.position,
    this.text = '',
    this.colorValue,
    this.locked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.storageKey,
        'position': position.toJson(),
        'text': text,
        if (colorValue != null) 'colorValue': colorValue,
        'locked': locked,
      };

  factory DiagramAnnotation.fromJson(Map<String, dynamic> json) {
    return DiagramAnnotation(
      id: json['id'] as String,
      type: AnnotationType.fromKey(json['type'] as String),
      position:
          DiagramPoint.fromJson(json['position'] as Map<String, dynamic>),
      text: (json['text'] as String?) ?? '',
      colorValue: json['colorValue'] as int?,
      locked: (json['locked'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagramAnnotation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          position == other.position &&
          text == other.text &&
          colorValue == other.colorValue &&
          locked == other.locked;

  @override
  int get hashCode =>
      Object.hash(id, type, position, text, colorValue, locked);
}

/// Ngoại lệ khi đọc hoặc ghi đè dữ liệu có schema mới hơn phiên bản ứng dụng hiện tại.
class SchemaVersionException extends FormatException {
  final int foundVersion;
  final int supportedVersion;

  const SchemaVersionException({
    required this.foundVersion,
    required this.supportedVersion,
  }) : super(
          'Dữ liệu sơ đồ thuộc phiên bản mới hơn (v$foundVersion, '
          'ứng dụng hiện hỗ trợ tới v$supportedVersion). Vui lòng cập nhật ứng dụng.',
        );
}

/// Thiết lập bắt dính tùy chọn khi dựng đường (lưới và đường giới hạn tâm bi sát băng).
class SnapSettings {
  final bool snapToGrid;
  final bool snapToRailLimit;

  const SnapSettings({
    this.snapToGrid = false,
    this.snapToRailLimit = true,
  });

  SnapSettings copyWith({
    bool? snapToGrid,
    bool? snapToRailLimit,
  }) {
    return SnapSettings(
      snapToGrid: snapToGrid ?? this.snapToGrid,
      snapToRailLimit: snapToRailLimit ?? this.snapToRailLimit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapSettings &&
          runtimeType == other.runtimeType &&
          snapToGrid == other.snapToGrid &&
          snapToRailLimit == other.snapToRailLimit;

  @override
  int get hashCode => Object.hash(snapToGrid, snapToRailLimit);
}

/// Thiết lập hiển thị các lớp trên bàn sơ đồ (lưới, nút diamond, số diamond, số bi).
class SceneViewSettings {
  final bool showGrid;
  final bool showDiamonds;
  final bool showDiamondNumbers;
  final bool showBallNumbers;
  final Map<String, String> systemRailLabels;

  SceneViewSettings({
    this.showGrid = false,
    this.showDiamonds = true,
    this.showDiamondNumbers = true,
    this.showBallNumbers = true,
    Map<String, String> systemRailLabels = const {},
  }) : systemRailLabels = Map<String, String>.unmodifiable(systemRailLabels);

  const SceneViewSettings.defaults()
      : showGrid = false,
        showDiamonds = true,
        showDiamondNumbers = true,
        showBallNumbers = true,
        systemRailLabels = const {};

  SceneViewSettings copyWith({
    bool? showGrid,
    bool? showDiamonds,
    bool? showDiamondNumbers,
    bool? showBallNumbers,
    Map<String, String>? systemRailLabels,
  }) {
    return SceneViewSettings(
      showGrid: showGrid ?? this.showGrid,
      showDiamonds: showDiamonds ?? this.showDiamonds,
      showDiamondNumbers: showDiamondNumbers ?? this.showDiamondNumbers,
      showBallNumbers: showBallNumbers ?? this.showBallNumbers,
      systemRailLabels: systemRailLabels ?? this.systemRailLabels,
    );
  }

  Map<String, dynamic> toJson() => {
        'showGrid': showGrid,
        'showDiamonds': showDiamonds,
        'showDiamondNumbers': showDiamondNumbers,
        'showBallNumbers': showBallNumbers,
        if (systemRailLabels.isNotEmpty) 'systemRailLabels': systemRailLabels,
      };

  factory SceneViewSettings.fromJson(Map<String, dynamic> json) {
    return SceneViewSettings(
      showGrid: (json['showGrid'] as bool?) ?? false,
      showDiamonds: (json['showDiamonds'] as bool?) ?? true,
      showDiamondNumbers: (json['showDiamondNumbers'] as bool?) ?? true,
      showBallNumbers: (json['showBallNumbers'] as bool?) ?? true,
      systemRailLabels: (json['systemRailLabels'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SceneViewSettings) return false;
    if (showGrid != other.showGrid ||
        showDiamonds != other.showDiamonds ||
        showDiamondNumbers != other.showDiamondNumbers ||
        showBallNumbers != other.showBallNumbers ||
        systemRailLabels.length != other.systemRailLabels.length) {
      return false;
    }
    for (final entry in systemRailLabels.entries) {
      if (other.systemRailLabels[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        showGrid,
        showDiamonds,
        showDiamondNumbers,
        showBallNumbers,
        Object.hashAllUnordered(
          systemRailLabels.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
}

/// Sơ đồ vector hoàn chỉnh của một bàn bi.
/// Hệ tọa độ lòng bàn: x: 0..188, y: 0..376 (tỉ lệ 1:2).
/// Tất cả danh sách được bọc bất biến để an toàn cho undo/redo.
class DiagramScene {
  static const int currentSchemaVersion = 1;
  static const double tableWidth = 188.0;
  static const double tableHeight = 376.0;
  static const double _validationEpsilon = 1e-6;

  final String id;
  final int version; // Schema version (hiện tại: 1)
  final double width;
  final double height;
  final List<Ball> balls;
  final List<GuidePath> paths;
  final List<DiagramAnnotation> annotations;
  final SceneViewSettings viewSettings;

  DiagramScene({
    required this.id,
    this.version = currentSchemaVersion,
    this.width = tableWidth,
    this.height = tableHeight,
    required List<Ball> balls,
    List<GuidePath> paths = const [],
    List<DiagramAnnotation> annotations = const [],
    this.viewSettings = const SceneViewSettings.defaults(),
  })  : balls = List<Ball>.unmodifiable(balls),
        paths = List<GuidePath>.unmodifiable(paths),
        annotations = List<DiagramAnnotation>.unmodifiable(annotations);

  DiagramScene copyWith({
    String? id,
    int? version,
    double? width,
    double? height,
    List<Ball>? balls,
    List<GuidePath>? paths,
    List<DiagramAnnotation>? annotations,
    SceneViewSettings? viewSettings,
  }) {
    return DiagramScene(
      id: id ?? this.id,
      version: version ?? this.version,
      width: width ?? this.width,
      height: height ?? this.height,
      balls: balls ?? this.balls,
      paths: paths ?? this.paths,
      annotations: annotations ?? this.annotations,
      viewSettings: viewSettings ?? this.viewSettings,
    );
  }

  /// Tạo bản scene mới với danh sách bi mới (không chỉnh sửa scene hiện tại).
  DiagramScene withBalls(List<Ball> newBalls) => copyWith(balls: newBalls);

  /// Tạo bản scene mới với danh sách đường hướng dẫn mới.
  DiagramScene withPaths(List<GuidePath> newPaths) => copyWith(paths: newPaths);

  /// Tạo bản scene mới với cả danh sách bi và đường hướng dẫn mới.
  DiagramScene withBallsAndPaths({
    required List<Ball> balls,
    required List<GuidePath> paths,
  }) =>
      copyWith(balls: balls, paths: paths);

  /// Tạo một scene mặc định có 3 bi (trắng, vàng, đỏ) ở các vị trí mẫu hợp lệ.
  factory DiagramScene.defaultInitial({required String id}) {
    return DiagramScene(
      id: id,
      version: 1,
      balls: const [
        Ball(
          id: 'ball_white',
          color: BallColor.white,
          label: '1',
          center: DiagramPoint(94.0, 94.0),
          radius: 4.0,
        ),
        Ball(
          id: 'ball_yellow',
          color: BallColor.yellow,
          label: '2',
          center: DiagramPoint(70.0, 200.0),
          radius: 4.0,
        ),
        Ball(
          id: 'ball_red',
          color: BallColor.red,
          label: '3',
          center: DiagramPoint(118.0, 200.0),
          radius: 4.0,
        ),
      ],
      paths: const [],
      annotations: const [],
      viewSettings: const SceneViewSettings.defaults(),
    );
  }

  /// Kiểm tra toàn vẹn dữ liệu scene phục vụ Phase 1.
  /// Trả về thông báo lỗi tiếng Việt hoặc null nếu hoàn toàn hợp lệ.
  String? validatePhase1() {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return 'Kích thước lòng bàn phải là số hữu hạn lớn hơn 0.';
    }
    final seenIds = <String>{};
    for (final ball in balls) {
      if (ball.id.trim().isEmpty) {
        return 'ID của bi không được để trống.';
      }
      if (!seenIds.add(ball.id)) {
        return 'Phát hiện ID bi bị trùng: ${ball.id}.';
      }
      if (!ball.center.isFinite) {
        return 'Tọa độ của ${ball.color.label} không hữu hạn.';
      }
      if (!ball.radius.isFinite || ball.radius <= 0) {
        return 'Bán kính của ${ball.color.label} phải hữu hạn và lớn hơn 0.';
      }
      if (ball.radius * 2.0 > width || ball.radius * 2.0 > height) {
        return 'Bán kính ${ball.radius} của ${ball.color.label} vượt quá kích thước bàn.';
      }
      if (ball.center.x < ball.radius - _validationEpsilon ||
          ball.center.x > width - ball.radius + _validationEpsilon ||
          ball.center.y < ball.radius - _validationEpsilon ||
          ball.center.y > height - ball.radius + _validationEpsilon) {
        return '${ball.color.label} nằm ngoài lòng bàn hợp lệ '
            '[${ball.radius}, ${width - ball.radius}] x [${ball.radius}, ${height - ball.radius}].';
      }
    }

    for (var i = 0; i < balls.length; i++) {
      for (var j = i + 1; j < balls.length; j++) {
        final a = balls[i];
        final b = balls[j];
        final minDist = a.radius + b.radius;
        if (a.center.distanceTo(b.center) < minDist - _validationEpsilon) {
          return '${a.color.label} và ${b.color.label} bị chồng lấp lên nhau.';
        }
      }
    }
    return null;
  }

  /// Kiểm tra toàn vẹn cấu trúc scene gồm bi và tham chiếu đường hướng dẫn.
  String? validateScene() {
    final ballErr = validatePhase1();
    if (ballErr != null) return ballErr;

    final ballIds = {for (final b in balls) b.id};
    final seenPathIds = <String>{};

    for (final path in paths) {
      if (path.id.trim().isEmpty) {
        return 'ID đường hướng dẫn không được để trống.';
      }
      if (!seenPathIds.add(path.id)) {
        return 'Phát hiện ID đường hướng dẫn bị trùng: ${path.id}.';
      }
      if (!ballIds.contains(path.ownerBallId)) {
        return 'Đường ${path.id} tham chiếu bi sở hữu không tồn tại: ${path.ownerBallId}.';
      }
      if (path.startAnchorBallId != null &&
          !ballIds.contains(path.startAnchorBallId)) {
        return 'Đường ${path.id} gắn liên kết tới bi không tồn tại: ${path.startAnchorBallId}.';
      }
      if (path.segments.isEmpty) {
        return 'Đường ${path.id} không có đoạn nào.';
      }
      if (!path.strokeWidth.isFinite || path.strokeWidth <= 0) {
        return 'Độ dày nét vẽ của đường ${path.id} không hợp lệ.';
      }
      for (final seg in path.segments) {
        if (!seg.start.isFinite || !seg.end.isFinite) {
          return 'Đường ${path.id} chứa tọa độ không hữu hạn.';
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'width': width,
        'height': height,
        'balls': balls.map((b) => b.toJson()).toList(),
        'paths': paths.map((p) => p.toJson()).toList(),
        'annotations': annotations.map((a) => a.toJson()).toList(),
        'viewSettings': viewSettings.toJson(),
      };

  factory DiagramScene.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('ID sơ đồ không hợp lệ.');
    }
    final rawVersion = json['version'];
    final version = rawVersion == null
        ? currentSchemaVersion
        : (rawVersion is num
            ? rawVersion.toInt()
            : throw const FormatException('Phiên bản sơ đồ phải là số nguyên.'));
    if (version > currentSchemaVersion) {
      throw SchemaVersionException(
        foundVersion: version,
        supportedVersion: currentSchemaVersion,
      );
    }

    final rawWidth = json['width'];
    final rawHeight = json['height'];
    final width = rawWidth == null
        ? tableWidth
        : (rawWidth is num
            ? rawWidth.toDouble()
            : throw const FormatException('Chiều rộng bàn phải là số.'));
    final height = rawHeight == null
        ? tableHeight
        : (rawHeight is num
            ? rawHeight.toDouble()
            : throw const FormatException('Chiều dài bàn phải là số.'));

    final rawBalls = json['balls'];
    if (rawBalls is! List<dynamic>) {
      throw const FormatException('Thiếu danh sách bi trong dữ liệu sơ đồ.');
    }

    final scene = DiagramScene(
      id: id,
      version: version,
      width: width,
      height: height,
      balls: rawBalls
          .map((b) => Ball.fromJson(b as Map<String, dynamic>))
          .toList(),
      paths: (json['paths'] as List<dynamic>?)
              ?.map((p) => GuidePath.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      annotations: (json['annotations'] as List<dynamic>?)
              ?.map((a) => DiagramAnnotation.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
      viewSettings: json['viewSettings'] != null
          ? SceneViewSettings.fromJson(
              json['viewSettings'] as Map<String, dynamic>,
            )
          : const SceneViewSettings.defaults(),
    );

    final validationError = scene.validateScene();
    if (validationError != null) {
      throw FormatException(validationError);
    }
    return scene;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DiagramScene) return false;
    if (id != other.id ||
        version != other.version ||
        width != other.width ||
        height != other.height ||
        viewSettings != other.viewSettings ||
        balls.length != other.balls.length ||
        paths.length != other.paths.length ||
        annotations.length != other.annotations.length) {
      return false;
    }
    for (var i = 0; i < balls.length; i++) {
      if (balls[i] != other.balls[i]) return false;
    }
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] != other.paths[i]) return false;
    }
    for (var i = 0; i < annotations.length; i++) {
      if (annotations[i] != other.annotations[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        version,
        width,
        height,
        viewSettings,
        Object.hashAll(balls),
        Object.hashAll(paths),
        Object.hashAll(annotations),
      );
}
