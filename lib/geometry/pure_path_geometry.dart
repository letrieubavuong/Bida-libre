import 'dart:math' as math;

import '../models/models.dart';
import 'table_constants.dart';

/// Hình học thuần Dart cho đường thẳng, đường gấp khúc và đường cong Bézier bậc ba.
/// Không phụ thuộc `dart:ui` hoặc Flutter để dùng chung cho model, controller và validator lưu trữ.
class PurePathGeometry {
  const PurePathGeometry._();

  static const double epsilon = 1e-6;
  static const double continuityTolerance = 1e-3;
  static const double minSegmentLength = 1e-3;

  static DiagramPoint lerpPoint(DiagramPoint a, DiagramPoint b, double t) {
    return DiagramPoint(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
    );
  }

  /// Tính điểm trên đoạn Bézier bậc ba tại tham số t in [0, 1].
  static DiagramPoint evaluateCubic(
    DiagramPoint p0,
    DiagramPoint c1,
    DiagramPoint c2,
    DiagramPoint p1,
    double t,
  ) {
    final mt = 1.0 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    final w0 = mt2 * mt;
    final w1 = 3.0 * mt2 * t;
    final w2 = 3.0 * mt * t2;
    final w3 = t2 * t;
    return DiagramPoint(
      w0 * p0.x + w1 * c1.x + w2 * c2.x + w3 * p1.x,
      w0 * p0.y + w1 * c1.y + w2 * c2.y + w3 * p1.y,
    );
  }

  /// Tính điểm trên một đoạn thẳng hoặc đoạn cubic tại tham số t in [0, 1].
  static DiagramPoint evaluateSegment(PathSegment seg, double t) {
    if (seg.type == SegmentType.cubic &&
        seg.control1 != null &&
        seg.control2 != null) {
      return evaluateCubic(seg.start, seg.control1!, seg.control2!, seg.end, t);
    }
    return lerpPoint(seg.start, seg.end, t);
  }

  /// Tìm các tham số cực trị t in (0, 1) cho hàm bậc ba 1 chiều (đạo hàm = 0).
  static List<double> _cubicCriticalParameters1D(
    double p0,
    double c1,
    double c2,
    double p1,
  ) {
    final v0 = c1 - p0;
    final v1 = c2 - c1;
    final v2 = p1 - c2;

    final a = v0 - 2.0 * v1 + v2;
    final b = 2.0 * (v1 - v0);
    final c = v0;

    final roots = <double>[];
    if (a.abs() < 1e-12) {
      if (b.abs() > 1e-12) {
        final t = -c / b;
        if (t > 1e-9 && t < 1.0 - 1e-9) {
          roots.add(t);
        }
      }
      return roots;
    }

    final disc = b * b - 4.0 * a * c;
    if (disc < -1e-12) return roots;
    final sqrtDisc = disc <= 0.0 ? 0.0 : math.sqrt(disc);
    final t1 = (-b - sqrtDisc) / (2.0 * a);
    final t2 = (-b + sqrtDisc) / (2.0 * a);
    if (t1 > 1e-9 && t1 < 1.0 - 1e-9) roots.add(t1);
    if (t2 > 1e-9 && t2 < 1.0 - 1e-9 && (t2 - t1).abs() > 1e-9) {
      roots.add(t2);
    }
    return roots;
  }

  /// Trả về tập các điểm ứng viên cực trị (hai đầu mút + các cực trị X/Y của cubic).
  static List<DiagramPoint> segmentExtremaPoints(PathSegment seg) {
    if (seg.type != SegmentType.cubic ||
        seg.control1 == null ||
        seg.control2 == null) {
      return [seg.start, seg.end];
    }
    final c1 = seg.control1!;
    final c2 = seg.control2!;
    final params = <double>{
      0.0,
      1.0,
      ..._cubicCriticalParameters1D(seg.start.x, c1.x, c2.x, seg.end.x),
      ..._cubicCriticalParameters1D(seg.start.y, c1.y, c2.y, seg.end.y),
    };
    return params
        .map((t) => evaluateCubic(seg.start, c1, c2, seg.end, t))
        .toList(growable: false);
  }

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

  /// Kẹp tay nắm trong khung hiển thị hợp lý của editor (không tự nắn vào lòng bàn
  /// để người dùng tự do chỉnh và bộ kiểm tra biên phát hiện chính xác nếu đường phình ra ngoài).
  static DiagramPoint clampHandleToCanvasFrame(DiagramPoint point) {
    final safeX = point.x.isFinite ? point.x : TableConstants.playfieldWidth / 2.0;
    final safeY =
        point.y.isFinite ? point.y : TableConstants.playfieldHeight / 2.0;
    return DiagramPoint(
      safeX
          .clamp(TableConstants.frameMinX, TableConstants.frameMaxX)
          .toDouble(),
      safeY
          .clamp(TableConstants.frameMinY, TableConstants.frameMaxY)
          .toDouble(),
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

    return clampPointForPath(
      DiagramPoint(x, y),
      role: role,
      ownerRadius: ownerRadius,
      width: width,
      height: height,
    );
  }

  /// Trích danh sách đỉnh nối liên tục [P0, P1, ..., Pn] từ các đoạn của đường.
  static List<DiagramPoint> extractVertices(GuidePath path) {
    if (path.segments.isEmpty) return const [];
    final vertices = <DiagramPoint>[path.segments.first.start];
    for (final seg in path.segments) {
      vertices.add(seg.end);
    }
    return vertices;
  }

  /// Tạo danh sách đoạn thẳng liên tiếp từ các đỉnh mới vẽ.
  static List<PathSegment> buildLineSegments(List<DiagramPoint> vertices) {
    if (vertices.length < 2) {
      throw ArgumentError('Đường cần ít nhất 2 đỉnh.');
    }
    final segments = <PathSegment>[];
    for (var i = 0; i < vertices.length - 1; i++) {
      segments.add(
        PathSegment.line(start: vertices[i], end: vertices[i + 1]),
      );
    }
    return segments;
  }

  /// Chuyển riêng một đoạn thẳng tại [segmentIndex] thành Bézier bậc ba, giữ nguyên hai đầu mút
  /// và không ảnh hưởng tới các đoạn khác.
  static GuidePath convertSegmentToCubic(GuidePath path, int segmentIndex) {
    if (segmentIndex < 0 || segmentIndex >= path.segments.length) {
      return path;
    }
    final seg = path.segments[segmentIndex];
    if (seg.type != SegmentType.line) {
      return path;
    }
    final updatedSeg = PathSegment.cubic(
      start: seg.start,
      end: seg.end,
      control1: lerpPoint(seg.start, seg.end, 1.0 / 3.0),
      control2: lerpPoint(seg.start, seg.end, 2.0 / 3.0),
      extraFields: seg.extraFields,
    );
    final updated = List<PathSegment>.from(path.segments);
    updated[segmentIndex] = updatedSeg;
    return path.copyWith(segments: updated);
  }

  /// Chuyển riêng một đoạn Bézier bậc ba tại [segmentIndex] về đoạn thẳng, giữ nguyên hai đầu mút
  /// và không làm đổi các đoạn khác.
  static GuidePath convertSegmentToLine(GuidePath path, int segmentIndex) {
    if (segmentIndex < 0 || segmentIndex >= path.segments.length) {
      return path;
    }
    final seg = path.segments[segmentIndex];
    if (seg.type != SegmentType.cubic) {
      return path;
    }
    final updatedSeg = PathSegment.line(
      start: seg.start,
      end: seg.end,
      extraFields: seg.extraFields,
    );
    final updated = List<PathSegment>.from(path.segments);
    updated[segmentIndex] = updatedSeg;
    return path.copyWith(segments: updated);
  }

  /// Cập nhật tọa độ một đỉnh nối, bảo toàn kiểu (thẳng/cubic/mở rộng) của mọi đoạn trong đường.
  static GuidePath updateVertex(
    GuidePath path,
    int vertexIndex,
    DiagramPoint newPoint,
  ) {
    final count = path.segments.length;
    if (count == 0 || vertexIndex < 0 || vertexIndex > count) {
      return path;
    }
    final oldPoint = vertexIndex < count
        ? path.segments[vertexIndex].start
        : path.segments[count - 1].end;
    if (oldPoint == newPoint) return path;

    final delta = newPoint - oldPoint;
    final nextSegments = List<PathSegment>.from(path.segments);

    if (vertexIndex > 0) {
      final prev = nextSegments[vertexIndex - 1];
      if ((prev.type == SegmentType.cubic || prev.type == SegmentType.unknown) &&
          prev.control2 != null) {
        nextSegments[vertexIndex - 1] = prev.copyWith(
          end: newPoint,
          control2: prev.control2! + delta,
        );
      } else {
        nextSegments[vertexIndex - 1] = prev.copyWith(end: newPoint);
      }
    }

    if (vertexIndex < count) {
      final next = nextSegments[vertexIndex];
      if ((next.type == SegmentType.cubic || next.type == SegmentType.unknown) &&
          next.control1 != null) {
        nextSegments[vertexIndex] = next.copyWith(
          start: newPoint,
          control1: next.control1! + delta,
        );
      } else {
        nextSegments[vertexIndex] = next.copyWith(start: newPoint);
      }
    }

    return path.copyWith(segments: nextSegments);
  }

  /// Cập nhật riêng một tay nắm (`handleIndex` = 1 hoặc 2) của đoạn cubic `[segmentIndex]`.
  static GuidePath updateControlHandle(
    GuidePath path,
    int segmentIndex,
    int handleIndex,
    DiagramPoint newControlPoint,
  ) {
    if (segmentIndex < 0 ||
        segmentIndex >= path.segments.length ||
        (handleIndex != 1 && handleIndex != 2)) {
      return path;
    }
    final seg = path.segments[segmentIndex];
    if (seg.type != SegmentType.cubic) return path;
    final nextSeg = handleIndex == 1
        ? seg.copyWith(control1: newControlPoint)
        : seg.copyWith(control2: newControlPoint);
    if (nextSeg == seg) return path;

    final nextSegments = List<PathSegment>.from(path.segments);
    nextSegments[segmentIndex] = nextSeg;
    return path.copyWith(segments: nextSegments);
  }

  /// Chia một đoạn thẳng hoặc cubic tại tham số `t` in (0, 1) (de Casteljau cho cubic).
  static List<PathSegment> splitSegmentAt(PathSegment seg, double t) {
    if (!(t > 1e-6 && t < 1.0 - 1e-6)) {
      throw ArgumentError.value(t, 't', 'Tham số chia đoạn phải nằm trong (0, 1).');
    }
    if (seg.type == SegmentType.cubic &&
        seg.control1 != null &&
        seg.control2 != null) {
      final p0 = seg.start;
      final c1 = seg.control1!;
      final c2 = seg.control2!;
      final p1 = seg.end;

      final q0 = lerpPoint(p0, c1, t);
      final q1 = lerpPoint(c1, c2, t);
      final q2 = lerpPoint(c2, p1, t);

      final r0 = lerpPoint(q0, q1, t);
      final r1 = lerpPoint(q1, q2, t);
      final mid = lerpPoint(r0, r1, t);

      return [
        PathSegment.cubic(
          start: p0,
          end: mid,
          control1: q0,
          control2: r0,
          extraFields: seg.extraFields,
        ),
        PathSegment.cubic(
          start: mid,
          end: p1,
          control1: r1,
          control2: q2,
          extraFields: seg.extraFields,
        ),
      ];
    }

    final mid = lerpPoint(seg.start, seg.end, t);
    return [
      PathSegment.line(start: seg.start, end: mid),
      PathSegment.line(start: mid, end: seg.end),
    ];
  }

  /// Chèn điểm chia trên đoạn [segmentIndex] tại tham số `t`.
  static GuidePath insertMidpointAtSegment(
    GuidePath path,
    int segmentIndex, {
    double t = 0.5,
  }) {
    if (segmentIndex < 0 || segmentIndex >= path.segments.length) {
      return path;
    }
    final split = splitSegmentAt(path.segments[segmentIndex], t);
    final nextSegments = <PathSegment>[
      ...path.segments.sublist(0, segmentIndex),
      ...split,
      ...path.segments.sublist(segmentIndex + 1),
    ];
    return path.copyWith(segments: nextSegments);
  }

  /// Xóa đỉnh [vertexIndex] theo quy tắc rõ ràng, không âm thầm biến dạng đoạn cong.
  static ({GuidePath? path, String? error}) tryRemoveVertex(
    GuidePath path,
    int vertexIndex,
  ) {
    final segCount = path.segments.length;
    if (segCount <= 1) {
      return (
        path: null,
        error:
            'Đường cần ít nhất 2 điểm. Hãy dùng "Xóa đường" để xóa toàn bộ đường.',
      );
    }
    if (vertexIndex < 0 || vertexIndex > segCount) {
      return (path: null, error: 'Điểm chọn không hợp lệ.');
    }

    if (vertexIndex == 0) {
      return (
        path: path.copyWith(segments: path.segments.sublist(1)),
        error: null,
      );
    }
    if (vertexIndex == segCount) {
      return (
        path: path.copyWith(segments: path.segments.sublist(0, segCount - 1)),
        error: null,
      );
    }

    final prev = path.segments[vertexIndex - 1];
    final next = path.segments[vertexIndex];
    if (prev.type != SegmentType.line || next.type != SegmentType.line) {
      return (
        path: null,
        error:
            'Điểm nối đang kề đoạn cong — hãy chuyển đoạn kề sang đường thẳng trước khi xóa điểm nối.',
      );
    }

    final merged = PathSegment.line(start: prev.start, end: next.end);
    final nextSegments = <PathSegment>[
      ...path.segments.sublist(0, vertexIndex - 1),
      merged,
      ...path.segments.sublist(vertexIndex + 1),
    ];
    return (path: path.copyWith(segments: nextSegments), error: null);
  }

  static GuidePath removeVertex(GuidePath path, int vertexIndex) {
    return tryRemoveVertex(path, vertexIndex).path ?? path;
  }

  /// Đảo chiều đường hướng dẫn.
  static GuidePath reversePath(GuidePath path) {
    final reversed = path.segments.reversed.map((seg) {
      if (seg.type == SegmentType.cubic &&
          seg.control1 != null &&
          seg.control2 != null) {
        return PathSegment.cubic(
          start: seg.end,
          end: seg.start,
          control1: seg.control2!,
          control2: seg.control1!,
          extraFields: seg.extraFields,
        );
      }
      if (seg.type == SegmentType.unknown) {
        return PathSegment.unknown(
          rawType: seg.unknownTypeKey ?? 'unknown',
          start: seg.end,
          end: seg.start,
          control1: seg.control2,
          control2: seg.control1,
          extraFields: seg.extraFields,
        );
      }
      return PathSegment.line(
        start: seg.end,
        end: seg.start,
        extraFields: seg.extraFields,
      );
    }).toList(growable: false);

    return path.copyWith(
      segments: reversed,
      clearStartAnchor: true,
    );
  }

  /// Vector tiếp tuyến đơn vị thuần Dart tại cuối đường (xử lý tiếp tuyến suy biến, không NaN).
  static ({double dx, double dy})? lastNonZeroTangentVector(GuidePath path) {
    for (var i = path.segments.length - 1; i >= 0; i--) {
      final seg = path.segments[i];
      final candidates = <DiagramPoint>[
        if (seg.type == SegmentType.cubic &&
            seg.control1 != null &&
            seg.control2 != null) ...[
          seg.end - seg.control2!,
          seg.end - seg.control1!,
          seg.end - seg.start,
        ] else
          seg.end - seg.start,
      ];

      for (final delta in candidates) {
        if (!delta.isFinite) continue;
        final lenSq = delta.x * delta.x + delta.y * delta.y;
        if (!lenSq.isFinite || lenSq <= epsilon * epsilon) continue;
        final len = math.sqrt(lenSq);
        if (len.isFinite && len > epsilon) {
          final ux = delta.x / len;
          final uy = delta.y / len;
          if (ux.isFinite && uy.isFinite) {
            return (dx: ux, dy: uy);
          }
        }
      }
    }
    return null;
  }

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

  /// Kiểm tra hình học đầy đủ của một đường dùng chung cho editor và bước lưu hoàn chỉnh:
  /// 1. Có bi sở hữu hợp lệ và ít nhất một đoạn.
  /// 2. Tọa độ và tay nắm hữu hạn.
  /// 3. Các đoạn liên tục (`seg[i].end == seg[i+1].start` trong dung sai).
  /// 4. Không có đoạn suy biến độ dài 0 (ngoài đoạn mở rộng chưa hỗ trợ).
  /// 5. Toàn bộ đường (kể cả cực trị cubic theo từng trục) nằm trong miền hợp lệ.
  /// 6. Điểm đầu có liên kết phải khớp tâm bi.
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

    if (path.segments.isEmpty) {
      return 'Đường cần ít nhất hai điểm.';
    }

    final isBallCenter = path.role == PathRole.ballCenter;
    final minBoundX = isBallCenter ? ownerBall.radius : 0.0;
    final maxBoundX = width - minBoundX;
    final minBoundY = isBallCenter ? ownerBall.radius : 0.0;
    final maxBoundY = height - minBoundY;

    for (var i = 0; i < path.segments.length; i++) {
      final seg = path.segments[i];
      if (!seg.start.isFinite || !seg.end.isFinite) {
        return 'Đường có tọa độ không hữu hạn.';
      }

      if (i > 0) {
        final prevEnd = path.segments[i - 1].end;
        if (prevEnd.distanceTo(seg.start) > continuityTolerance) {
          return 'Đường ${path.id} có đoạn $i và đoạn ${i + 1} không liên tục.';
        }
      }

      if (seg.type == SegmentType.cubic) {
        if (seg.control1 == null ||
            seg.control2 == null ||
            !seg.control1!.isFinite ||
            !seg.control2!.isFinite) {
          return 'Đoạn cong thiếu tay nắm hợp lệ.';
        }
        final hasSpan = seg.start.distanceTo(seg.end) >= minSegmentLength ||
            seg.start.distanceTo(seg.control1!) >= minSegmentLength ||
            seg.control1!.distanceTo(seg.control2!) >= minSegmentLength ||
            seg.control2!.distanceTo(seg.end) >= minSegmentLength;
        if (!hasSpan) {
          return 'Đoạn cong bị suy biến về độ dài 0 — hãy kéo tách tay nắm hoặc điểm nối.';
        }
      } else if (seg.type == SegmentType.line) {
        if (seg.start.distanceTo(seg.end) < minSegmentLength) {
          return 'Đường có đoạn độ dài bằng 0 — hãy kéo tách điểm trùng.';
        }
      } else {
        // Đoạn mở rộng chưa hỗ trợ: chỉ kiểm tra span nếu không có tay nắm riêng
        if (seg.control1 == null &&
            seg.control2 == null &&
            seg.start.distanceTo(seg.end) < minSegmentLength) {
          return 'Đường có đoạn độ dài bằng 0 — hãy kéo tách điểm trùng.';
        }
      }

      final extremaPts = segmentExtremaPoints(seg);
      for (final pt in extremaPts) {
        if (pt.x < minBoundX - epsilon ||
            pt.x > maxBoundX + epsilon ||
            pt.y < minBoundY - epsilon ||
            pt.y > maxBoundY + epsilon) {
          if (isBallCenter) {
            return 'Đường quỹ đạo tâm của ${ownerBall.color.label} vượt giới hạn lòng bàn '
                '[${minBoundX.toStringAsFixed(1)}, ${maxBoundX.toStringAsFixed(1)}] × '
                '[${minBoundY.toStringAsFixed(1)}, ${maxBoundY.toStringAsFixed(1)}]'
                '${seg.type == SegmentType.cubic ? ' (phần cong đoạn ${i + 1} phình ra ngoài).' : '.'}';
          } else {
            return 'Đường phụ vượt ra ngoài lòng bàn (đoạn ${i + 1}).';
          }
        }
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
          path.segments.first.start.distanceTo(anchorBall.center) >
              continuityTolerance) {
        return 'Điểm đầu liên kết chưa khớp tâm bi.';
      }
    }

    return null;
  }
}

