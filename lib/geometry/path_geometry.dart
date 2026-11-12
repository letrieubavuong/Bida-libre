import 'dart:ui';

import '../models/models.dart';
import 'pure_path_geometry.dart';
import 'table_constants.dart';
import 'table_geometry.dart';

class PathHitResult {
  final GuidePath path;
  final int segmentIndex;
  final double distancePx;

  const PathHitResult({
    required this.path,
    required this.segmentIndex,
    required this.distancePx,
  });
}

class VertexHitResult {
  final int vertexIndex;
  final double distancePx;

  const VertexHitResult({
    required this.vertexIndex,
    required this.distancePx,
  });
}

class ControlHandleHitResult {
  final int segmentIndex;
  final int handleIndex; // 1 for control1, 2 for control2
  final double distancePx;

  const ControlHandleHitResult({
    required this.segmentIndex,
    required this.handleIndex,
    required this.distancePx,
  });
}

/// Giao diện hình học kèm phép quy đổi màn hình / màu sắc cho UI canvas.
/// Mọi phép toán thuần Dart được ủy quyền về [PurePathGeometry].
class PathGeometry {
  const PathGeometry._();

  static const double epsilon = PurePathGeometry.epsilon;
  static const double minSegmentLength = PurePathGeometry.minSegmentLength;

  static DiagramPoint lerpPoint(DiagramPoint a, DiagramPoint b, double t) =>
      PurePathGeometry.lerpPoint(a, b, t);

  static DiagramPoint evaluateCubic(
    DiagramPoint p0,
    DiagramPoint c1,
    DiagramPoint c2,
    DiagramPoint p1,
    double t,
  ) =>
      PurePathGeometry.evaluateCubic(p0, c1, c2, p1, t);

  static DiagramPoint evaluateSegment(PathSegment seg, double t) =>
      PurePathGeometry.evaluateSegment(seg, t);

  static List<DiagramPoint> segmentExtremaPoints(PathSegment seg) =>
      PurePathGeometry.segmentExtremaPoints(seg);

  static DiagramPoint clampPointForPath(
    DiagramPoint point, {
    required PathRole role,
    required double ownerRadius,
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) =>
      PurePathGeometry.clampPointForPath(
        point,
        role: role,
        ownerRadius: ownerRadius,
        width: width,
        height: height,
      );

  static DiagramPoint clampHandleToCanvasFrame(DiagramPoint point) =>
      PurePathGeometry.clampHandleToCanvasFrame(point);

  static DiagramPoint snapPoint(
    DiagramPoint rawPoint, {
    required PathRole role,
    required double ownerRadius,
    required SnapSettings snapSettings,
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
    double snapThreshold = 5.0,
  }) =>
      PurePathGeometry.snapPoint(
        rawPoint,
        role: role,
        ownerRadius: ownerRadius,
        snapSettings: snapSettings,
        width: width,
        height: height,
        snapThreshold: snapThreshold,
      );

  static List<DiagramPoint> extractVertices(GuidePath path) =>
      PurePathGeometry.extractVertices(path);

  static List<PathSegment> buildLineSegments(List<DiagramPoint> vertices) =>
      PurePathGeometry.buildLineSegments(vertices);

  static GuidePath convertSegmentToCubic(GuidePath path, int segmentIndex) =>
      PurePathGeometry.convertSegmentToCubic(path, segmentIndex);

  static GuidePath convertSegmentToLine(GuidePath path, int segmentIndex) =>
      PurePathGeometry.convertSegmentToLine(path, segmentIndex);

  static GuidePath updateVertex(
    GuidePath path,
    int vertexIndex,
    DiagramPoint newPoint,
  ) =>
      PurePathGeometry.updateVertex(path, vertexIndex, newPoint);

  static GuidePath updateControlHandle(
    GuidePath path,
    int segmentIndex,
    int handleIndex,
    DiagramPoint newControlPoint,
  ) =>
      PurePathGeometry.updateControlHandle(
        path,
        segmentIndex,
        handleIndex,
        newControlPoint,
      );

  static List<PathSegment> splitSegmentAt(PathSegment seg, double t) =>
      PurePathGeometry.splitSegmentAt(seg, t);

  static GuidePath insertMidpointAtSegment(
    GuidePath path,
    int segmentIndex, {
    double t = 0.5,
  }) =>
      PurePathGeometry.insertMidpointAtSegment(path, segmentIndex, t: t);

  static ({GuidePath? path, String? error}) tryRemoveVertex(
    GuidePath path,
    int vertexIndex,
  ) =>
      PurePathGeometry.tryRemoveVertex(path, vertexIndex);

  static GuidePath removeVertex(GuidePath path, int vertexIndex) =>
      PurePathGeometry.removeVertex(path, vertexIndex);

  static GuidePath reversePath(GuidePath path) =>
      PurePathGeometry.reversePath(path);

  static Offset? lastNonZeroDirection(GuidePath path) {
    final vec = PurePathGeometry.lastNonZeroTangentVector(path);
    return vec == null ? null : Offset(vec.dx, vec.dy);
  }

  static double distancePointToSegment(
    DiagramPoint p,
    DiagramPoint a,
    DiagramPoint b,
  ) =>
      PurePathGeometry.distancePointToSegment(p, a, b);

  static String? validatePath(
    GuidePath path,
    List<Ball> balls, {
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) =>
      PurePathGeometry.validatePath(
        path,
        balls,
        width: width,
        height: height,
      );

  /// Hit-test các đỉnh điều khiển của đường đang chọn (vùng chạm >= 48dp).
  static VertexHitResult? hitTestPathVertex({
    required Offset screenPosition,
    required GuidePath path,
    required TableCoordinateMapper mapper,
    double minTouchRadiusPx = 24.0,
  }) {
    final vertices = extractVertices(path);
    int? bestIdx;
    double bestDist = double.infinity;

    for (var i = 0; i < vertices.length; i++) {
      final ptScreen = mapper.diagramToScreen(vertices[i]);
      final dist = (screenPosition - ptScreen).distance;
      if (dist <= minTouchRadiusPx && dist < bestDist - 1e-6) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    if (bestIdx == null) return null;
    return VertexHitResult(vertexIndex: bestIdx, distancePx: bestDist);
  }

  /// Hit-test hai tay nắm Bézier (`control1`, `control2`) của đường đang chọn.
  static ControlHandleHitResult? hitTestControlHandle({
    required Offset screenPosition,
    required GuidePath path,
    required TableCoordinateMapper mapper,
    double minTouchRadiusPx = 24.0,
  }) {
    ControlHandleHitResult? best;
    double bestDist = double.infinity;

    for (var i = 0; i < path.segments.length; i++) {
      final seg = path.segments[i];
      if (seg.type != SegmentType.cubic ||
          seg.control1 == null ||
          seg.control2 == null) {
        continue;
      }
      for (final handleIndex in const [1, 2]) {
        final handlePt = handleIndex == 1 ? seg.control1! : seg.control2!;
        final handleScreen = mapper.diagramToScreen(handlePt);
        final dist = (screenPosition - handleScreen).distance;
        final endpointPt = handleIndex == 1 ? seg.start : seg.end;
        if (handlePt.distanceTo(endpointPt) < 1e-3) continue;
        if (dist <= minTouchRadiusPx && dist < bestDist - 1e-6) {
          bestDist = dist;
          best = ControlHandleHitResult(
            segmentIndex: i,
            handleIndex: handleIndex,
            distancePx: dist,
          );
        }
      }
    }
    return best;
  }

  /// Hit-test toàn bộ danh sách đường trên bàn; đoạn cong cubic được lấy mẫu theo đường cong thực.
  static PathHitResult? hitTestPath({
    required Offset screenPosition,
    required List<GuidePath> paths,
    required TableCoordinateMapper mapper,
    String? preferredPathId,
    double maxTouchDistancePx = 22.0,
  }) {
    PathHitResult? best;
    double bestDistPx = double.infinity;

    for (final path in paths) {
      for (var i = 0; i < path.segments.length; i++) {
        final seg = path.segments[i];
        final distPx = _distanceScreenToSegment(screenPosition, seg, mapper);

        if (distPx <= maxTouchDistancePx) {
          final isCloser = distPx < bestDistPx - 1e-6;
          final isTiePreferSelected =
              (distPx - bestDistPx).abs() <= 1e-6 && path.id == preferredPathId;
          if (isCloser || isTiePreferSelected) {
            bestDistPx = distPx;
            best = PathHitResult(
              path: path,
              segmentIndex: i,
              distancePx: distPx,
            );
          }
        }
      }
    }
    return best;
  }

  static double _distanceScreenToSegment(
    Offset screenPosition,
    PathSegment seg,
    TableCoordinateMapper mapper,
  ) {
    if (seg.type != SegmentType.cubic ||
        seg.control1 == null ||
        seg.control2 == null) {
      return _distanceOffsetToSegment(
        screenPosition,
        mapper.diagramToScreen(seg.start),
        mapper.diagramToScreen(seg.end),
      );
    }

    final p0s = mapper.diagramToScreen(seg.start);
    final c1s = mapper.diagramToScreen(seg.control1!);
    final c2s = mapper.diagramToScreen(seg.control2!);
    final p1s = mapper.diagramToScreen(seg.end);

    final controlPolyLen =
        (c1s - p0s).distance + (c2s - c1s).distance + (p1s - c2s).distance;
    final steps = (controlPolyLen / 6.0).ceil().clamp(24, 96);

    var prev = p0s;
    var minDist = double.infinity;
    var bestStep = 0;
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final curr = mapper.diagramToScreen(
        evaluateCubic(seg.start, seg.control1!, seg.control2!, seg.end, t),
      );
      final d = _distanceOffsetToSegment(screenPosition, prev, curr);
      if (d < minDist) {
        minDist = d;
        bestStep = s;
      }
      prev = curr;
    }

    final tLow = ((bestStep - 1) / steps).clamp(0.0, 1.0);
    final tHigh = ((bestStep + 1) / steps).clamp(0.0, 1.0);
    var lo = tLow;
    var hi = tHigh;
    for (var iter = 0; iter < 12; iter++) {
      final m1 = lo + (hi - lo) / 3.0;
      final m2 = hi - (hi - lo) / 3.0;
      final d1 = (screenPosition -
              mapper.diagramToScreen(
                evaluateCubic(
                    seg.start, seg.control1!, seg.control2!, seg.end, m1),
              ))
          .distance;
      final d2 = (screenPosition -
              mapper.diagramToScreen(
                evaluateCubic(
                    seg.start, seg.control1!, seg.control2!, seg.end, m2),
              ))
          .distance;
      if (d1 < minDist) minDist = d1;
      if (d2 < minDist) minDist = d2;
      if (d1 < d2) {
        hi = m2;
      } else {
        lo = m1;
      }
    }

    return minDist;
  }

  static double _distanceOffsetToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq <= 1e-9) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq)
        .clamp(0.0, 1.0)
        .toDouble();
    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - proj).distance;
  }

  /// Màu vẽ mặc định tương phản cao trên nền bàn xanh dương.
  static Color defaultColorForBall(BallColor color) {
    switch (color) {
      case BallColor.white:
        return const Color(0xFFFFFFFF);
      case BallColor.yellow:
        return const Color(0xFFFFE082);
      case BallColor.red:
        return const Color(0xFFFF6E6E);
    }
  }
}
