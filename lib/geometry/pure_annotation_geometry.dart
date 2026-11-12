import '../models/models.dart';
import 'table_constants.dart';

/// Quy tắc hình học và vị trí thuần Dart cho chú thích (không phụ thuộc Flutter/dart:ui).
class PureAnnotationGeometry {
  const PureAnnotationGeometry._();

  static const double _eps = 1e-6;

  static bool isZoneType(AnnotationType type) =>
      type == AnnotationType.circleZone || type == AnnotationType.rectZone;

  /// Nhãn chữ và số thứ tự theo quy tắc mới chỉ đặt trên dải băng gỗ xung quanh lòng bàn.
  static bool isRailOnlyType(AnnotationType type) =>
      type == AnnotationType.label || type == AnnotationType.sequence;

  static bool isOnWoodRailBand(
    DiagramPoint point, {
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    if (!point.isFinite) return false;
    final frameMinX = TableConstants.frameMinX;
    final frameMinY = TableConstants.frameMinY;
    final frameMaxX =
        width + (TableConstants.frameMaxX - TableConstants.playfieldWidth);
    final frameMaxY =
        height + (TableConstants.frameMaxY - TableConstants.playfieldHeight);

    final railMinX = TableConstants.railMinX;
    final railMinY = TableConstants.railMinY;
    final railMaxX =
        width + (TableConstants.railMaxX - TableConstants.playfieldWidth);
    final railMaxY =
        height + (TableConstants.railMaxY - TableConstants.playfieldHeight);

    final inOuterFrame = point.x >= frameMinX - _eps &&
        point.x <= frameMaxX + _eps &&
        point.y >= frameMinY - _eps &&
        point.y <= frameMaxY + _eps;
    if (!inOuterFrame) return false;

    final outsideInnerCloth = point.x <= railMinX + _eps ||
        point.x >= railMaxX - _eps ||
        point.y <= railMinY + _eps ||
        point.y >= railMaxY - _eps;
    return outsideInnerCloth;
  }

  static DiagramPoint clampPosition(
    DiagramPoint raw, {
    AnnotationType? type,
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    final safeX = raw.x.isFinite ? raw.x : width / 2.0;
    final safeY = raw.y.isFinite ? raw.y : height / 2.0;

    final frameMinX = TableConstants.frameMinX;
    final frameMinY = TableConstants.frameMinY;
    final frameMaxX =
        width + (TableConstants.frameMaxX - TableConstants.playfieldWidth);
    final frameMaxY =
        height + (TableConstants.frameMaxY - TableConstants.playfieldHeight);

    if (type != null && isRailOnlyType(type)) {
      final railMinX = TableConstants.railMinX;
      final railMinY = TableConstants.railMinY;
      final railMaxX =
          width + (TableConstants.railMaxX - TableConstants.playfieldWidth);
      final railMaxY =
          height + (TableConstants.railMaxY - TableConstants.playfieldHeight);

      final x = safeX.clamp(frameMinX, frameMaxX).toDouble();
      final y = safeY.clamp(frameMinY, frameMaxY).toDouble();

      if (x > railMinX && x < railMaxX && y > railMinY && y < railMaxY) {
        final dLeft = x - railMinX;
        final dRight = railMaxX - x;
        final dBottom = y - railMinY;
        final dTop = railMaxY - y;
        final minDist = [dLeft, dRight, dBottom, dTop]
            .reduce((a, b) => a < b ? a : b);
        if (minDist == dLeft) return DiagramPoint(railMinX, y);
        if (minDist == dRight) return DiagramPoint(railMaxX, y);
        if (minDist == dBottom) return DiagramPoint(x, railMinY);
        return DiagramPoint(x, railMaxY);
      }
      return DiagramPoint(x, y);
    }

    if (type == AnnotationType.marker) {
      return DiagramPoint(
        safeX.clamp(frameMinX, frameMaxX).toDouble(),
        safeY.clamp(frameMinY, frameMaxY).toDouble(),
      );
    }

    return DiagramPoint(
      safeX.clamp(0.0, width).toDouble(),
      safeY.clamp(0.0, height).toDouble(),
    );
  }

  /// Thu thập cảnh báo quy tắc vị trí (không coi là lỗi hỏng tệp đối với dữ liệu cũ).
  static Map<String, String> collectRuleWarnings(DiagramScene scene) {
    final warnings = <String, String>{};
    for (final ann in scene.annotations) {
      if (isRailOnlyType(ann.type) &&
          !isOnWoodRailBand(
            ann.position,
            width: scene.width,
            height: scene.height,
          )) {
        warnings[ann.id] =
            'Chú thích "${ann.text.isEmpty ? ann.type.displayName : ann.text}" '
            'từ bản cũ đang nằm trong mặt bàn — hãy kéo ra dải băng gỗ nếu muốn cập nhật.';
      }
    }
    return Map<String, String>.unmodifiable(warnings);
  }
}

