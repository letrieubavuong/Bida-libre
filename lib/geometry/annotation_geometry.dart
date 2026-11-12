import 'dart:ui';

import '../models/models.dart';
import 'table_constants.dart';
import 'table_geometry.dart';

class AnnotationHitResult {
  final DiagramAnnotation annotation;
  final double distancePx;

  const AnnotationHitResult({
    required this.annotation,
    required this.distancePx,
  });
}

/// Hình học tĩnh cho chú thích trên bàn (nhãn chữ, số thứ tự, chấm mốc, vùng tròn, vùng chữ nhật).
class AnnotationGeometry {
  const AnnotationGeometry._();

  static const double _eps = 1e-6;

  static bool isZoneType(AnnotationType type) =>
      type == AnnotationType.circleZone || type == AnnotationType.rectZone;

  /// Nhãn chữ và số thứ tự chỉ nằm trên phần dải băng gỗ xung quanh lòng bàn.
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

  static Color defaultColorFor(AnnotationType type) {
    switch (type) {
      case AnnotationType.label:
        return const Color(0xFFFFFFFF);
      case AnnotationType.sequence:
        return const Color(0xFFFFD54F);
      case AnnotationType.marker:
        return const Color(0xFF80DEEA);
      case AnnotationType.circleZone:
        return const Color(0xFFA5D6A7);
      case AnnotationType.rectZone:
        return const Color(0xFFFFCC80);
    }
  }

  static AnnotationHitResult? hitTestAnnotation({
    required Offset screenPosition,
    required List<DiagramAnnotation> annotations,
    required TableCoordinateMapper mapper,
    String? preferredAnnotationId,
    bool zonesOnly = false,
    bool foregroundOnly = false,
    double minTouchRadiusPx = 22.0,
  }) {
    AnnotationHitResult? best;
    double bestScore = double.infinity;

    for (final ann in annotations.reversed) {
      final isZone = isZoneType(ann.type);
      if (zonesOnly && !isZone) continue;
      if (foregroundOnly && isZone) continue;

      final centerPx = mapper.diagramToScreen(ann.position);
      double? hitScore;

      switch (ann.type) {
        case AnnotationType.marker:
        case AnnotationType.sequence:
          final rPx = (ann.radius * mapper.scale).clamp(14.0, 40.0);
          final dist = (screenPosition - centerPx).distance;
          if (dist <= (rPx + 10.0 > minTouchRadiusPx ? rPx + 10.0 : minTouchRadiusPx)) {
            hitScore = dist;
          }
        case AnnotationType.label:
          final halfW = (ann.text.length * 4.5 + 16.0).clamp(24.0, 96.0);
          const halfH = 20.0;
          final dx = (screenPosition.dx - centerPx.dx).abs();
          final dy = (screenPosition.dy - centerPx.dy).abs();
          if (dx <= halfW && dy <= halfH) {
            hitScore = (screenPosition - centerPx).distance;
          }
        case AnnotationType.circleZone:
          final rPx = ann.radius * mapper.scale;
          final distCenter = (screenPosition - centerPx).distance;
          final distEdge = (distCenter - rPx).abs();
          if (distCenter <= rPx + 12.0) {
            hitScore = distEdge;
          }
        case AnnotationType.rectZone:
          final halfW = (ann.width * mapper.scale) / 2.0;
          final halfH = (ann.height * mapper.scale) / 2.0;
          final dx = (screenPosition.dx - centerPx.dx).abs();
          final dy = (screenPosition.dy - centerPx.dy).abs();
          if (dx <= halfW + 12.0 && dy <= halfH + 12.0) {
            hitScore = ((dx - halfW).abs()).clamp(0.0, double.infinity);
          }
      }

      if (hitScore != null) {
        final isCloser = hitScore < bestScore - 1e-6;
        final isPreferred = (hitScore - bestScore).abs() <= 1e-6 &&
            ann.id == preferredAnnotationId;
        if (isCloser || isPreferred) {
          bestScore = hitScore;
          best = AnnotationHitResult(annotation: ann, distancePx: hitScore);
        }
      }
    }
    return best;
  }
}

