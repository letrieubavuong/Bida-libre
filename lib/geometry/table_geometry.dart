import 'dart:math' as math;
import 'dart:ui';

import '../models/models.dart';
import 'table_constants.dart';

/// Bộ chuyển đổi tọa độ hai chiều giữa hệ sơ đồ bàn (gốc dưới-trái, y tăng lên trên)
/// và tọa độ màn hình (gốc trên-trái, y tăng xuống dưới).
/// Luôn dùng một hệ số scale chung cho cả hai trục để giữ bi tròn tuyệt đối
/// và luôn tính theo toàn bộ khung (-20..208 x -20..396) để không cắt mép.
class TableCoordinateMapper {
  static const double totalDiagramWidth =
      TableConstants.frameMaxX - TableConstants.frameMinX; // 228.0
  static const double totalDiagramHeight =
      TableConstants.frameMaxY - TableConstants.frameMinY; // 416.0

  final Size canvasSize;
  final double paddingPx;
  late final double scale;
  late final Offset diagramOriginOnScreen;

  TableCoordinateMapper({
    required this.canvasSize,
    this.paddingPx = 8.0,
  }) {
    final safePadding = paddingPx.isFinite && paddingPx >= 0 ? paddingPx : 0.0;
    final availWidth = math.max(1.0, canvasSize.width - safePadding * 2.0);
    final availHeight = math.max(1.0, canvasSize.height - safePadding * 2.0);

    final scaleX = availWidth / totalDiagramWidth;
    final scaleY = availHeight / totalDiagramHeight;
    scale = math.max(0.0001, math.min(scaleX, scaleY));

    final renderedWidth = totalDiagramWidth * scale;
    final renderedHeight = totalDiagramHeight * scale;

    final frameLeft = (canvasSize.width - renderedWidth) / 2.0;
    final frameTop = (canvasSize.height - renderedHeight) / 2.0;

    diagramOriginOnScreen = Offset(
      frameLeft + (-TableConstants.frameMinX) * scale,
      frameTop + (TableConstants.frameMaxY) * scale,
    );
  }

  /// Chuyển tọa độ bàn (đơn vị sơ đồ) sang tọa độ màn hình (logical pixels).
  Offset diagramToScreen(DiagramPoint point) {
    return Offset(
      diagramOriginOnScreen.dx + point.x * scale,
      diagramOriginOnScreen.dy - point.y * scale,
    );
  }

  /// Chuyển tọa độ màn hình (logical pixels) sang tọa độ bàn (đơn vị sơ đồ).
  DiagramPoint screenToDiagram(Offset screenPoint) {
    final x = (screenPoint.dx - diagramOriginOnScreen.dx) / scale;
    final y = (diagramOriginOnScreen.dy - screenPoint.dy) / scale;
    return DiagramPoint(x, y);
  }

  /// Bán kính hiển thị trên màn hình (logical pixels).
  double radiusToScreen(double diagramRadius) => diagramRadius * scale;
}

/// Kiểm tra và giải quyết vị trí bi theo quy tắc hình học tĩnh (mục 6.2).
class BallPlacementValidator {
  const BallPlacementValidator._();

  static const double epsilon = 1e-6;
  static const double minBallRadius = 2.0;
  static const double maxBallRadius = 10.0;

  /// Đưa điểm về trong miền lòng bàn [r, W - r] x [r, H - r] gần vị trí yêu cầu nhất.
  static DiagramPoint clampToPlayfield(
    DiagramPoint point,
    double radius, {
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    final safeX = point.x.isFinite ? point.x : width / 2.0;
    final safeY = point.y.isFinite ? point.y : height / 2.0;
    return DiagramPoint(
      safeX.clamp(radius, width - radius).toDouble(),
      safeY.clamp(radius, height - radius).toDouble(),
    );
  }

  static bool isWithinPlayfield(
    DiagramPoint point,
    double radius, {
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    if (!point.x.isFinite || !point.y.isFinite || !radius.isFinite) {
      return false;
    }
    if (radius <= 0 || radius * 2.0 > width || radius * 2.0 > height) {
      return false;
    }
    return point.x >= radius - epsilon &&
        point.x <= width - radius + epsilon &&
        point.y >= radius - epsilon &&
        point.y <= height - radius + epsilon;
  }

  static bool overlapsAnyBall(
    DiagramPoint center,
    double radius,
    String ballId,
    List<Ball> allBalls,
  ) {
    for (final other in allBalls) {
      if (other.id == ballId) continue;
      final minAllowed = radius + other.radius;
      if (center.distanceTo(other.center) < minAllowed - epsilon) {
        return true;
      }
    }
    return false;
  }

  /// Kiểm tra tọa độ nhập tay cho bi; trả về thông báo lỗi tiếng Việt hoặc null nếu hợp lệ.
  static String? validateManualPlacement({
    required Ball targetBall,
    required DiagramPoint candidateCenter,
    required List<Ball> allBalls,
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    if (!candidateCenter.x.isFinite || !candidateCenter.y.isFinite) {
      return 'Tọa độ phải là số hữu hạn.';
    }
    final r = targetBall.radius;
    if (!isWithinPlayfield(candidateCenter, r, width: width, height: height)) {
      return 'Tọa độ vượt quá lòng bàn hợp lệ: '
          'X phải trong [${r.toStringAsFixed(1)}, ${(width - r).toStringAsFixed(1)}], '
          'Y phải trong [${r.toStringAsFixed(1)}, ${(height - r).toStringAsFixed(1)}].';
    }
    for (final other in allBalls) {
      if (other.id == targetBall.id) continue;
      final minDist = r + other.radius;
      if (candidateCenter.distanceTo(other.center) < minDist - epsilon) {
        return 'Bi chồng lên ${other.color.label} '
            '(khoảng cách tâm tối thiểu ${minDist.toStringAsFixed(1)}).';
      }
    }
    return null;
  }

  /// Giải quyết vị trí khi kéo bi:
  /// - Kéo vượt băng/khung: đưa tới vị trí hợp lệ gần nhất trong lòng bàn (không nhảy sang phía đối diện).
  /// - Kéo vào bi khác: không đẩy bi khác; giữ vị trí tiếp xúc gần nhất ở cùng phía tiếp cận
  ///   hoặc giữ vị trí hợp lệ cuối cùng nếu bị kẹt. Không nhảy xuyên qua phía đối diện bi đang chắn.
  static DiagramPoint resolveDragPosition({
    required Ball draggedBall,
    required DiagramPoint desiredCenter,
    required DiagramPoint lastValidCenter,
    required List<Ball> allBalls,
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    final r = draggedBall.radius;
    final clamped = clampToPlayfield(
      desiredCenter,
      r,
      width: width,
      height: height,
    );

    final blockingAlongSegment = _findFirstSegmentBlockingBall(
      from: lastValidCenter,
      to: clamped,
      draggedBall: draggedBall,
      allBalls: allBalls,
    );

    if (blockingAlongSegment == null &&
        !overlapsAnyBall(clamped, r, draggedBall.id, allBalls)) {
      return clamped;
    }

    final blocking = blockingAlongSegment ??
        _findOverlappingBall(clamped, r, draggedBall.id, allBalls);

    if (blocking != null) {
      final contactDist = r + blocking.radius + 1e-4;
      final prevDx = lastValidCenter.x - blocking.center.x;
      final prevDy = lastValidCenter.y - blocking.center.y;
      final curDx = clamped.x - blocking.center.x;
      final curDy = clamped.y - blocking.center.y;

      final dot = prevDx * curDx + prevDy * curDy;
      final curLen = math.sqrt(curDx * curDx + curDy * curDy);

      // Nếu điểm kéo mới vẫn ở cùng phía và không đi xuyên qua tâm bi chắn -> trượt tiếp tuyến
      if (dot >= 0 && curLen > epsilon && blockingAlongSegment == null) {
        final tangentCandidate = DiagramPoint(
          blocking.center.x + (curDx / curLen) * contactDist,
          blocking.center.y + (curDy / curLen) * contactDist,
        );
        if (isWithinPlayfield(
              tangentCandidate,
              r,
              width: width,
              height: height,
            ) &&
            !overlapsAnyBall(tangentCandidate, r, draggedBall.id, allBalls)) {
          return tangentCandidate;
        }
      }

      // Trường hợp kéo đâm thẳng vào hoặc vượt qua bi chắn: dừng tại điểm tiếp xúc phía gần
      final entryPoint = _segmentCircleEntryPoint(
        from: lastValidCenter,
        to: clamped,
        circleCenter: blocking.center,
        circleRadius: contactDist,
      );
      if (entryPoint != null &&
          isWithinPlayfield(entryPoint, r, width: width, height: height) &&
          !overlapsAnyBall(entryPoint, r, draggedBall.id, allBalls)) {
        return entryPoint;
      }

      // Thử chiếu dọc theo hướng tiếp cận từ vị trí hợp lệ cuối
      final prevLen = math.sqrt(prevDx * prevDx + prevDy * prevDy);
      if (prevLen > epsilon) {
        final nearCandidate = DiagramPoint(
          blocking.center.x + (prevDx / prevLen) * contactDist,
          blocking.center.y + (prevDy / prevLen) * contactDist,
        );
        if (isWithinPlayfield(nearCandidate, r, width: width, height: height) &&
            !overlapsAnyBall(nearCandidate, r, draggedBall.id, allBalls)) {
          return nearCandidate;
        }
      }
    }

    return lastValidCenter;
  }

  static Ball? _findOverlappingBall(
    DiagramPoint center,
    double radius,
    String ballId,
    List<Ball> allBalls,
  ) {
    for (final other in allBalls) {
      if (other.id == ballId) continue;
      if (center.distanceTo(other.center) < radius + other.radius - epsilon) {
        return other;
      }
    }
    return null;
  }

  /// Tìm bi đầu tiên bị đoạn thẳng [from -> to] cắt qua hình tròn cấm (khi kéo nhanh qua bi khác).
  static Ball? _findFirstSegmentBlockingBall({
    required DiagramPoint from,
    required DiagramPoint to,
    required Ball draggedBall,
    required List<Ball> allBalls,
  }) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final segLenSq = dx * dx + dy * dy;
    if (segLenSq <= epsilon) return null;

    Ball? closestBall;
    double closestT = double.infinity;

    for (final other in allBalls) {
      if (other.id == draggedBall.id) continue;
      final minDist = draggedBall.radius + other.radius - epsilon;
      final fx = from.x - other.center.x;
      final fy = from.y - other.center.y;

      final b = 2.0 * (fx * dx + fy * dy);
      final c = fx * fx + fy * fy - minDist * minDist;
      final disc = b * b - 4.0 * segLenSq * c;
      if (disc <= 0) continue;

      final sqrtDisc = math.sqrt(disc);
      final t1 = (-b - sqrtDisc) / (2.0 * segLenSq);
      final t2 = (-b + sqrtDisc) / (2.0 * segLenSq);

      final entersInside = (t1 >= 0.0 && t1 <= 1.0) || (t2 > 0.0 && t2 <= 1.0);
      if (entersInside) {
        final hitT = t1 >= 0.0 ? t1 : 0.0;
        if (hitT < closestT) {
          closestT = hitT;
          closestBall = other;
        }
      }
    }

    return closestBall;
  }

  static DiagramPoint? _segmentCircleEntryPoint({
    required DiagramPoint from,
    required DiagramPoint to,
    required DiagramPoint circleCenter,
    required double circleRadius,
  }) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final a = dx * dx + dy * dy;
    if (a <= epsilon) return null;

    final fx = from.x - circleCenter.x;
    final fy = from.y - circleCenter.y;
    final b = 2.0 * (fx * dx + fy * dy);
    final c = fx * fx + fy * fy - circleRadius * circleRadius;
    final disc = b * b - 4.0 * a * c;
    if (disc < 0) return null;

    final t = (-b - math.sqrt(disc)) / (2.0 * a);
    if (t < 0.0 || t > 1.0) return null;
    return DiagramPoint(from.x + t * dx, from.y + t * dy);
  }

  /// Kiểm tra toàn bộ bố cục hiện tại có hợp lệ với bán kính mới hay không.
  static String? validateLayoutForRadius(
    List<Ball> balls,
    double newRadius, {
    double width = TableConstants.playfieldWidth,
    double height = TableConstants.playfieldHeight,
  }) {
    if (!newRadius.isFinite ||
        newRadius < minBallRadius ||
        newRadius > maxBallRadius) {
      return 'Bán kính bi phải nằm trong khoảng '
          '${minBallRadius.toStringAsFixed(1)} đến ${maxBallRadius.toStringAsFixed(1)}.';
    }

    for (final ball in balls) {
      if (!isWithinPlayfield(
        ball.center,
        newRadius,
        width: width,
        height: height,
      )) {
        return 'Không thể đặt r = ${newRadius.toStringAsFixed(1)} vì '
            '${ball.color.label} sẽ vượt mép lòng bàn.';
      }
    }

    for (var i = 0; i < balls.length; i++) {
      for (var j = i + 1; j < balls.length; j++) {
        final dist = balls[i].center.distanceTo(balls[j].center);
        final minDist = newRadius * 2.0;
        if (dist < minDist - epsilon) {
          return 'Không thể đặt r = ${newRadius.toStringAsFixed(1)} vì '
              '${balls[i].color.label} và ${balls[j].color.label} sẽ chồng lên nhau.';
        }
      }
    }
    return null;
  }

  /// Hit-test bi trên màn hình với vùng bắt chạm đủ lớn (>= 48dp đường kính),
  /// không đổi bán kính hình học. Khi vùng bắt chạm giao nhau, chọn bi gần nhất ổn định.
  static Ball? hitTestBall({
    required Offset screenPosition,
    required List<Ball> balls,
    required TableCoordinateMapper mapper,
    String? preferredBallId,
    double minTouchRadiusPx = 24.0,
  }) {
    Ball? bestBall;
    double bestDistance = double.infinity;

    for (final ball in balls) {
      final centerPx = mapper.diagramToScreen(ball.center);
      final ballPxRadius = mapper.radiusToScreen(ball.radius);
      final hitRadius = math.max(ballPxRadius, minTouchRadiusPx);
      final dist = (screenPosition - centerPx).distance;

      if (dist <= hitRadius) {
        final isCloser = dist < bestDistance - 1e-6;
        final isTiePreferSelected =
            (dist - bestDistance).abs() <= 1e-6 && ball.id == preferredBallId;
        if (isCloser || isTiePreferSelected) {
          bestDistance = dist;
          bestBall = ball;
        }
      }
    }
    return bestBall;
  }
}
