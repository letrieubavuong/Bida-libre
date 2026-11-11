import 'dart:math' as math;
import 'dart:ui';

import '../models/models.dart';
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

/// Hình học tĩnh cho đường thẳng / đường gấp khúc (Phase 2).
/// Chỉ phục vụ dựng, bắt dính, giới hạn vùng và chọn đường; không tính cơ học.
class PathGeometry {
  const PathGeometry._();

  static const double epsilon = 1e-6;
  static const double minSegmentLength = 1e-3;

  /// Kẹp điểm trong miền hợp lệ theo vai trò đường:
  /// - Quỹ đạo tâm bi: [r, W - r] x [r, H - r]
  /// - Đường phụ minh họa: [0, W] x [0, H]
  static DiagramPoint clampPointForPath(
    DiagramPoint point, {
    required PathRole role,
    required double ownerRadius,
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    final safeX = point.x.isFinite ? point.x : width / 2.0;
    final safeY = point.y.isFinite ? point.y : height / 2.0;
    final margin = role == PathRole.ballCenter ? ownerRadius : 0.0;
    return DiagramPoint(
      safeX.clamp(margin, width - margin).toDouble(),
      safeY.clamp(margin, height - margin).toDouble(),
    );
  }

  /// Áp dụng bắt dính tùy chọn (lưới, đường giới hạn tâm sát băng), luôn bảo đảm
  /// quỹ đạo tâm bi nằm trong [r, W - r] x [r, H - r] và không dính lên chính mép băng.
  static DiagramPoint snapPoint(
    DiagramPoint rawPoint, {
    required PathRole role,
    required double ownerRadius,
    required SnapSettings snapSettings,
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
    double snapThreshold = 5.0,
  }) {
    var x = rawPoint.x.isFinite ? rawPoint.x : width / 2.0;
    var y = rawPoint.y.isFinite ? rawPoint.y : height / 2.0;

    final margin = role == PathRole.ballCenter ? ownerRadius : 0.0;

    // 1. Bắt dính đường giới hạn tâm sát băng (cách mép đúng r với quỹ đạo tâm bi)
    if (snapSettings.snapToRailLimit) {
      final minX = margin;
      final maxX = width - margin;
      final minY = margin;
      final maxY = height - margin;

      if ((x - minX).abs() <= snapThreshold) {
        x = minX;
      } else if ((x - maxX).abs() <= snapThreshold) {
        x = maxX;
      }
      if ((y - minY).abs() <= snapThreshold) {
        y = minY;
      } else if ((y - maxY).abs() <= snapThreshold) {
        y = maxY;
      }
    }

    // 2. Bắt dính theo lưới chia bước 47
    if (snapSettings.snapToGrid) {
      double? bestGridX;
      double bestDistX = snapThreshold;
      for (final gx in TableConstants.shortRailDiamondX) {
        final d = (x - gx).abs();
        if (d <= bestDistX) {
          bestDistX = d;
          bestGridX = gx;
        }
      }
      if (bestGridX != null) {
        x = bestGridX;
      }

      double? bestGridY;
      double bestDistY = snapThreshold;
      for (final gy in TableConstants.longRailDiamondY) {
        final d = (y - gy).abs();
        if (d <= bestDistY) {
          bestDistY = d;
          bestGridY = gy;
        }
      }
      if (bestGridY != null) {
        y = bestGridY;
      }
    }

    // Luôn kẹp lại theo giới hạn tâm bi để không bao giờ đặt tâm lên chính mép băng (0 hoặc W/H)
    return clampPointForPath(
      DiagramPoint(x, y),
      role: role,
      ownerRadius: ownerRadius,
      width: width,
      height: height,
    );
  }

  /// Trích danh sách đỉnh liên tục [P0, P1, ..., Pn] từ các đoạn của đường.
  static List<DiagramPoint> extractVertices(GuidePath path) {
    if (path.segments.isEmpty) return const [];
    final vertices = <DiagramPoint>[path.segments.first.start];
    for (final seg in path.segments) {
      vertices.add(seg.end);
    }
    return vertices;
  }

  /// Tạo danh sách đoạn thẳng liên tiếp từ các đỉnh (không tự bo cong).
  static List<PathSegment> buildLineSegments(List<DiagramPoint> vertices) {
    if (vertices.length < 2) {
      throw ArgumentError('Đường gấp khúc cần ít nhất 2 đỉnh.');
    }
    final segments = <PathSegment>[];
    for (var i = 0; i < vertices.length - 1; i++) {
      segments.add(
        PathSegment.line(start: vertices[i], end: vertices[i + 1]),
      );
    }
    return segments;
  }

  /// Cập nhật tọa độ một đỉnh cụ thể trong đường gấp khúc, giữ liên kết các đoạn liền kề.
  static GuidePath updateVertex(
    GuidePath path,
    int vertexIndex,
    DiagramPoint newPoint,
  ) {
    final vertices = extractVertices(path);
    if (vertexIndex < 0 || vertexIndex >= vertices.length) {
      return path;
    }
    vertices[vertexIndex] = newPoint;
    return path.copyWith(segments: buildLineSegments(vertices));
  }

  /// Chèn thêm đỉnh tại trung điểm của đoạn [segmentIndex].
  static GuidePath insertMidpointAtSegment(GuidePath path, int segmentIndex) {
    final vertices = extractVertices(path);
    if (segmentIndex < 0 || segmentIndex >= path.segments.length) {
      return path;
    }
    final a = vertices[segmentIndex];
    final b = vertices[segmentIndex + 1];
    final mid = DiagramPoint((a.x + b.x) / 2.0, (a.y + b.y) / 2.0);
    vertices.insert(segmentIndex + 1, mid);
    return path.copyWith(segments: buildLineSegments(vertices));
  }

  /// Xóa đỉnh [vertexIndex] nếu đường còn nhiều hơn 2 đỉnh.
  static GuidePath removeVertex(GuidePath path, int vertexIndex) {
    final vertices = extractVertices(path);
    if (vertices.length <= 2 ||
        vertexIndex < 0 ||
        vertexIndex >= vertices.length) {
      return path;
    }
    vertices.removeAt(vertexIndex);
    return path.copyWith(segments: buildLineSegments(vertices));
  }

  /// Đảo chiều đường hướng dẫn (các đỉnh đảo ngược, gỡ liên kết đầu nếu có).
  static GuidePath reversePath(GuidePath path) {
    final vertices = extractVertices(path).reversed.toList();
    return path.copyWith(
      segments: buildLineSegments(vertices),
      clearStartAnchor: true,
    );
  }

  /// Tính hướng vector đơn vị của đoạn cuối có độ dài > 0 (dùng cho vẽ mũi tên cuối).
  static Offset? lastNonZeroDirection(GuidePath path) {
    for (var i = path.segments.length - 1; i >= 0; i--) {
      final seg = path.segments[i];
      final dx = seg.end.x - seg.start.x;
      final dy = seg.end.y - seg.start.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > epsilon) {
        return Offset(dx / len, dy / len);
      }
    }
    return null;
  }

  /// Khoảng cách từ điểm P đến đoạn thẳng AB.
  static double distancePointToSegment(
    DiagramPoint p,
    DiagramPoint a,
    DiagramPoint b,
  ) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final lenSq = abx * abx + aby * aby;
    if (lenSq <= epsilon) {
      return p.distanceTo(a);
    }
    final t = (((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq)
        .clamp(0.0, 1.0)
        .toDouble();
    final proj = DiagramPoint(a.x + t * abx, a.y + t * aby);
    return p.distanceTo(proj);
  }

  /// Hit-test các điểm điều khiển của đường đang chọn (vùng chạm >= 48dp).
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

  /// Hit-test toàn bộ danh sách đường trên bàn; khi các đường gần nhau, chọn đường gần nhất.
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
        final aScreen = mapper.diagramToScreen(seg.start);
        final bScreen = mapper.diagramToScreen(seg.end);
        final distPx = _distanceOffsetToSegment(screenPosition, aScreen, bScreen);

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

  /// Kiểm tra một đường có đang hợp lệ với bán kính và vị trí bi hiện tại hay không.
  static String? validatePath(
    GuidePath path,
    List<Ball> balls, {
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    Ball? ownerBall;
    for (final b in balls) {
      if (b.id == path.ownerBallId) {
        ownerBall = b;
        break;
      }
    }
    if (ownerBall == null) {
      return 'Không tìm thấy bi sở hữu của đường.';
    }

    final vertices = extractVertices(path);
    if (vertices.length < 2) {
      return 'Đường cần ít nhất hai điểm.';
    }

    if (path.role == PathRole.ballCenter) {
      final r = ownerBall.radius;
      for (final v in vertices) {
        if (v.x < r - epsilon ||
            v.x > width - r + epsilon ||
            v.y < r - epsilon ||
            v.y > height - r + epsilon) {
          return 'Đường quỹ đạo tâm của ${ownerBall.color.label} vượt giới hạn lòng bàn '
              '(cần nằm trong [${r.toStringAsFixed(1)}, ${(width - r).toStringAsFixed(1)}] × '
              '[${r.toStringAsFixed(1)}, ${(height - r).toStringAsFixed(1)}]).';
        }
      }
    } else {
      for (final v in vertices) {
        if (v.x < -epsilon ||
            v.x > width + epsilon ||
            v.y < -epsilon ||
            v.y > height + epsilon) {
          return 'Đường phụ vượt ra ngoài lòng bàn.';
        }
      }
    }

    for (final seg in path.segments) {
      if (seg.start.distanceTo(seg.end) < minSegmentLength) {
        return 'Đường có đoạn độ dài bằng 0 — hãy kéo tách điểm trùng.';
      }
    }

    if (path.startAnchorBallId != null) {
      Ball? anchorBall;
      for (final b in balls) {
        if (b.id == path.startAnchorBallId) {
          anchorBall = b;
          break;
        }
      }
      if (anchorBall == null ||
          vertices.first.distanceTo(anchorBall.center) > 1e-3) {
        return 'Điểm đầu liên kết chưa khớp tâm bi.';
      }
    }

    return null;
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

