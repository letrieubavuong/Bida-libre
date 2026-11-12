import 'dart:ui';

import '../models/models.dart';
import 'pure_annotation_geometry.dart';
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

/// Hình học tĩnh cho chú thích trên bàn; logic vị trí/kẹp thuần Dart nằm ở [PureAnnotationGeometry].
class AnnotationGeometry {
  const AnnotationGeometry._();

  static bool isZoneType(AnnotationType type) =>
      PureAnnotationGeometry.isZoneType(type);

  static bool isRailOnlyType(AnnotationType type) =>
      PureAnnotationGeometry.isRailOnlyType(type);

  static bool isOnWoodRailBand(
    DiagramPoint point, {
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) =>
      PureAnnotationGeometry.isOnWoodRailBand(
        point,
        width: width,
        height: height,
      );

  static DiagramPoint clampPosition(
    DiagramPoint raw, {
    AnnotationType? type,
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) =>
      PureAnnotationGeometry.clampPosition(
        raw,
        type: type,
        width: width,
        height: height,
      );

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

