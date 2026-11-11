import 'dart:math';
import 'enums.dart';

/// Điểm 2D trong hệ tọa độ sơ đồ bàn (đơn vị sơ đồ x: 0..188, y: 0..376).
class DiagramPoint {
  final double x;
  final double y;

  const DiagramPoint(this.x, this.y);

  DiagramPoint copyWith({double? x, double? y}) {
    return DiagramPoint(x ?? this.x, y ?? this.y);
  }

  double distanceTo(DiagramPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return sqrt(dx * dx + dy * dy);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory DiagramPoint.fromJson(Map<String, dynamic> json) {
    return DiagramPoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
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
  String toString() => 'DiagramPoint(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
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
    return Ball(
      id: json['id'] as String,
      color: BallColor.fromKey(json['color'] as String),
      label: (json['label'] as String?) ?? '',
      center: DiagramPoint.fromJson(json['center'] as Map<String, dynamic>),
      radius: (json['radius'] as num?)?.toDouble() ?? 4.0,
      locked: (json['locked'] as bool?) ?? false,
    );
  }
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
        control1: DiagramPoint.fromJson(json['control1'] as Map<String, dynamic>),
        control2: DiagramPoint.fromJson(json['control2'] as Map<String, dynamic>),
      );
    }
  }
}

/// Đường hướng dẫn tĩnh cho bi.
class GuidePath {
  final String id;
  final String ownerBallId; // Bi sở hữu đường
  final PathRole role;
  final List<PathSegment> segments;
  final bool isDashed;
  final double strokeWidth;
  final int? customColorValue;
  final String? startAnchorBallId; // Gắn điểm đầu với tâm bi sở hữu

  const GuidePath({
    required this.id,
    required this.ownerBallId,
    this.role = PathRole.ballCenter,
    required this.segments,
    this.isDashed = false,
    this.strokeWidth = 2.0,
    this.customColorValue,
    this.startAnchorBallId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerBallId': ownerBallId,
        'role': role.storageKey,
        'segments': segments.map((s) => s.toJson()).toList(),
        'isDashed': isDashed,
        'strokeWidth': strokeWidth,
        if (customColorValue != null) 'customColorValue': customColorValue,
        if (startAnchorBallId != null) 'startAnchorBallId': startAnchorBallId,
      };

  factory GuidePath.fromJson(Map<String, dynamic> json) {
    return GuidePath(
      id: json['id'] as String,
      ownerBallId: json['ownerBallId'] as String,
      role: PathRole.fromKey(json['role'] as String? ?? 'ball_center'),
      segments: (json['segments'] as List<dynamic>)
          .map((s) => PathSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
      isDashed: (json['isDashed'] as bool?) ?? false,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      customColorValue: json['customColorValue'] as int?,
      startAnchorBallId: json['startAnchorBallId'] as String?,
    );
  }
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
      position: DiagramPoint.fromJson(json['position'] as Map<String, dynamic>),
      text: (json['text'] as String?) ?? '',
      colorValue: json['colorValue'] as int?,
      locked: (json['locked'] as bool?) ?? false,
    );
  }
}

/// Sơ đồ vector hoàn chỉnh của một bàn bi.
/// Hệ tọa độ lòng bàn: x: 0..188, y: 0..376 (tỉ lệ 1:2).
class DiagramScene {
  static const double tableWidth = 188.0;
  static const double tableHeight = 376.0;

  final String id;
  final int version; // Schema version (ví dụ: 1)
  final double width;
  final double height;
  final List<Ball> balls;
  final List<GuidePath> paths;
  final List<DiagramAnnotation> annotations;

  const DiagramScene({
    required this.id,
    this.version = 1,
    this.width = tableWidth,
    this.height = tableHeight,
    required this.balls,
    this.paths = const [],
    this.annotations = const [],
  });

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
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'width': width,
        'height': height,
        'balls': balls.map((b) => b.toJson()).toList(),
        'paths': paths.map((p) => p.toJson()).toList(),
        'annotations': annotations.map((a) => a.toJson()).toList(),
      };

  factory DiagramScene.fromJson(Map<String, dynamic> json) {
    return DiagramScene(
      id: json['id'] as String,
      version: (json['version'] as num?)?.toInt() ?? 1,
      width: (json['width'] as num?)?.toDouble() ?? tableWidth,
      height: (json['height'] as num?)?.toDouble() ?? tableHeight,
      balls: (json['balls'] as List<dynamic>)
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
    );
  }
}

