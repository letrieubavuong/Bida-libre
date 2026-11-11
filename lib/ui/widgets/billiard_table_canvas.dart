import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../geometry/path_geometry.dart';
import '../../geometry/table_constants.dart';
import '../../geometry/table_geometry.dart';
import '../../models/models.dart';
import '../../state/table_editor_controller.dart';

enum _ActiveDragKind { ball, vertex }

/// Bàn vẽ vector tĩnh theo mẫu TikZ (lòng bàn 188 x 376, khung -20..208 x -20..396):
/// - Chế độ Chọn / Di chuyển: kéo bi, chọn đường, kéo điểm điều khiển của đường đang chọn.
/// - Chế độ Vẽ đường: chạm đặt điểm gấp khúc với nét xem trước; không kéo nhầm bi.
class BilliardTableCanvas extends StatefulWidget {
  final DiagramScene scene;
  final EditorToolMode toolMode;
  final String? selectedBallId;
  final String? selectedPathId;
  final int? selectedVertexIndex;
  final Set<String> invalidPathIds;

  final List<DiagramPoint> draftPoints;
  final String draftOwnerBallId;
  final PathRole draftRole;
  final SnapSettings snapSettings;

  final ValueChanged<String> onBallTapped;
  final ValueChanged<String?> onPathTapped;

  final int? Function(String ballId, DiagramPoint touchPoint) onBallDragStart;
  final void Function(DiagramPoint touchPoint, int dragToken)
      onBallDragUpdateFromTouch;
  final ValueChanged<int> onBallDragEnd;
  final ValueChanged<int> onBallDragCancel;
  final ValueChanged<Ball>? onLockedBallTouched;

  final int? Function(String pathId, int vertexIndex, DiagramPoint touchPoint)
      onVertexDragStart;
  final void Function(DiagramPoint touchPoint, int dragToken)
      onVertexDragUpdateFromTouch;
  final ValueChanged<int> onVertexDragEnd;
  final ValueChanged<int> onVertexDragCancel;

  final ValueChanged<DiagramPoint> onDrawPointPlaced;

  const BilliardTableCanvas({
    super.key,
    required this.scene,
    required this.toolMode,
    required this.selectedBallId,
    required this.selectedPathId,
    required this.selectedVertexIndex,
    required this.invalidPathIds,
    required this.draftPoints,
    required this.draftOwnerBallId,
    required this.draftRole,
    required this.snapSettings,
    required this.onBallTapped,
    required this.onPathTapped,
    required this.onBallDragStart,
    required this.onBallDragUpdateFromTouch,
    required this.onBallDragEnd,
    required this.onBallDragCancel,
    this.onLockedBallTouched,
    required this.onVertexDragStart,
    required this.onVertexDragUpdateFromTouch,
    required this.onVertexDragEnd,
    required this.onVertexDragCancel,
    required this.onDrawPointPlaced,
  });

  @override
  State<BilliardTableCanvas> createState() => _BilliardTableCanvasState();
}

class _BilliardTableCanvasState extends State<BilliardTableCanvas> {
  int? _activePointerId;
  int? _activeDragToken;
  _ActiveDragKind? _activeDragKind;

  int? _drawPointerId;
  DiagramPoint? _liveDrawCursor;

  @override
  void didUpdateWidget(covariant BilliardTableCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.toolMode != EditorToolMode.drawPolyline &&
        (_drawPointerId != null || _liveDrawCursor != null)) {
      _drawPointerId = null;
      _liveDrawCursor = null;
    }
  }

  GuidePath? get _selectedPath {
    if (widget.selectedPathId == null) return null;
    for (final p in widget.scene.paths) {
      if (p.id == widget.selectedPathId) return p;
    }
    return null;
  }

  double get _draftOwnerRadius {
    for (final b in widget.scene.balls) {
      if (b.id == widget.draftOwnerBallId) return b.radius;
    }
    return widget.scene.balls.isNotEmpty
        ? widget.scene.balls.first.radius
        : TableConstants.defaultBallRadius;
  }

  DiagramPoint _snapDraftCursor(DiagramPoint raw) {
    return PathGeometry.snapPoint(
      raw,
      role: widget.draftRole,
      ownerRadius: _draftOwnerRadius,
      snapSettings: widget.snapSettings,
      width: widget.scene.width,
      height: widget.scene.height,
    );
  }

  void _cancelCurrentSelectDrag() {
    final token = _activeDragToken;
    final kind = _activeDragKind;
    _activePointerId = null;
    _activeDragToken = null;
    _activeDragKind = null;
    if (token != null && kind != null) {
      if (kind == _ActiveDragKind.ball) {
        widget.onBallDragCancel(token);
      } else {
        widget.onVertexDragCancel(token);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 540.0,
        );
        final mapper = TableCoordinateMapper(canvasSize: size);

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (widget.toolMode == EditorToolMode.drawPolyline) {
              if (_drawPointerId != null) return;
              _drawPointerId = event.pointer;
              final raw = mapper.screenToDiagram(event.localPosition);
              setState(() {
                _liveDrawCursor = _snapDraftCursor(raw);
              });
              return;
            }

            // Chế độ Chọn / Di chuyển
            if (_activePointerId != null) {
              _cancelCurrentSelectDrag();
              return;
            }

            // 1. Ưu tiên kiểm tra điểm điều khiển của đường đang chọn
            final currentSelectedPath = _selectedPath;
            if (currentSelectedPath != null) {
              final vertexHit = PathGeometry.hitTestPathVertex(
                screenPosition: event.localPosition,
                path: currentSelectedPath,
                mapper: mapper,
              );
              if (vertexHit != null) {
                final touchDiagram = mapper.screenToDiagram(event.localPosition);
                final token = widget.onVertexDragStart(
                  currentSelectedPath.id,
                  vertexHit.vertexIndex,
                  touchDiagram,
                );
                if (token != null) {
                  _activePointerId = event.pointer;
                  _activeDragToken = token;
                  _activeDragKind = _ActiveDragKind.vertex;
                }
                return;
              }
            }

            // 2. Kiểm tra chạm bi
            final ballHit = BallPlacementValidator.hitTestBall(
              screenPosition: event.localPosition,
              balls: widget.scene.balls,
              mapper: mapper,
              preferredBallId: widget.selectedBallId,
            );
            if (ballHit != null) {
              widget.onBallTapped(ballHit.id);
              final touchDiagram = mapper.screenToDiagram(event.localPosition);
              final token = widget.onBallDragStart(ballHit.id, touchDiagram);
              if (token != null) {
                _activePointerId = event.pointer;
                _activeDragToken = token;
                _activeDragKind = _ActiveDragKind.ball;
              } else if (ballHit.locked) {
                widget.onLockedBallTouched?.call(ballHit);
              }
              return;
            }

            // 3. Kiểm tra chạm thân đường (chọn đường gần nhất)
            final pathHit = PathGeometry.hitTestPath(
              screenPosition: event.localPosition,
              paths: widget.scene.paths,
              mapper: mapper,
              preferredPathId: widget.selectedPathId,
            );
            if (pathHit != null) {
              widget.onPathTapped(pathHit.path.id);
              return;
            }

            // 4. Chạm vùng trống -> bỏ chọn đường hiện tại (giữ bi chọn để xem X/Y)
            if (widget.selectedPathId != null) {
              widget.onPathTapped(null);
            }
          },
          onPointerMove: (event) {
            if (widget.toolMode == EditorToolMode.drawPolyline) {
              if (event.pointer != _drawPointerId) return;
              final raw = mapper.screenToDiagram(event.localPosition);
              setState(() {
                _liveDrawCursor = _snapDraftCursor(raw);
              });
              return;
            }

            final token = _activeDragToken;
            final kind = _activeDragKind;
            if (event.pointer != _activePointerId ||
                token == null ||
                kind == null) {
              return;
            }
            final touchDiagram = mapper.screenToDiagram(event.localPosition);
            if (kind == _ActiveDragKind.ball) {
              widget.onBallDragUpdateFromTouch(touchDiagram, token);
            } else {
              widget.onVertexDragUpdateFromTouch(touchDiagram, token);
            }
          },
          onPointerUp: (event) {
            if (widget.toolMode == EditorToolMode.drawPolyline) {
              if (event.pointer != _drawPointerId) return;
              final raw = mapper.screenToDiagram(event.localPosition);
              _drawPointerId = null;
              setState(() {
                _liveDrawCursor = null;
              });
              widget.onDrawPointPlaced(raw);
              return;
            }

            if (event.pointer != _activePointerId) return;
            final token = _activeDragToken;
            final kind = _activeDragKind;
            _activePointerId = null;
            _activeDragToken = null;
            _activeDragKind = null;
            if (token != null && kind != null) {
              if (kind == _ActiveDragKind.ball) {
                widget.onBallDragEnd(token);
              } else {
                widget.onVertexDragEnd(token);
              }
            }
          },
          onPointerCancel: (event) {
            if (widget.toolMode == EditorToolMode.drawPolyline) {
              if (event.pointer != _drawPointerId) return;
              _drawPointerId = null;
              setState(() {
                _liveDrawCursor = null;
              });
              return;
            }

            if (event.pointer != _activePointerId) return;
            _cancelCurrentSelectDrag();
          },
          child: CustomPaint(
            size: size,
            painter: _BilliardTablePainter(
              scene: widget.scene,
              mapper: mapper,
              toolMode: widget.toolMode,
              selectedBallId: widget.selectedBallId,
              selectedPathId: widget.selectedPathId,
              selectedVertexIndex: widget.selectedVertexIndex,
              invalidPathIds: widget.invalidPathIds,
              draftPoints: widget.draftPoints,
              draftOwnerBallId: widget.draftOwnerBallId,
              liveDrawCursor: _liveDrawCursor,
            ),
          ),
        );
      },
    );
  }
}

class _BilliardTablePainter extends CustomPainter {
  final DiagramScene scene;
  final TableCoordinateMapper mapper;
  final EditorToolMode toolMode;
  final String? selectedBallId;
  final String? selectedPathId;
  final int? selectedVertexIndex;
  final Set<String> invalidPathIds;
  final List<DiagramPoint> draftPoints;
  final String draftOwnerBallId;
  final DiagramPoint? liveDrawCursor;

  _BilliardTablePainter({
    required this.scene,
    required this.mapper,
    required this.toolMode,
    required this.selectedBallId,
    required this.selectedPathId,
    required this.selectedVertexIndex,
    required this.invalidPathIds,
    required this.draftPoints,
    required this.draftOwnerBallId,
    required this.liveDrawCursor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = mapper.scale;
    final view = scene.viewSettings;

    Rect rectFromDiagram(double x1, double y1, double x2, double y2) {
      final p1 = mapper.diagramToScreen(DiagramPoint(x1, y2));
      final p2 = mapper.diagramToScreen(DiagramPoint(x2, y1));
      return Rect.fromLTRB(p1.dx, p1.dy, p2.dx, p2.dy);
    }

    // 1. Khung ngoài xám bo góc: (-20, -20) -> (208, 396)
    final frameRect = rectFromDiagram(
      TableConstants.frameMinX,
      TableConstants.frameMinY,
      TableConstants.frameMaxX,
      TableConstants.frameMaxY,
    );
    final frameRRect = RRect.fromRectAndRadius(
      frameRect,
      Radius.circular(10.0 * s),
    );
    canvas.drawRRect(
      frameRRect.shift(const Offset(0.0, 2.0)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );
    canvas.drawRRect(
      frameRRect,
      Paint()..color = const Color(0xFF757A82),
    );
    canvas.drawRRect(
      frameRRect,
      Paint()
        ..color = const Color(0xFF4D5259)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 2. Băng xanh: (-5, -5) -> (193, 381)
    final railRect = rectFromDiagram(
      TableConstants.railMinX,
      TableConstants.railMinY,
      TableConstants.railMaxX,
      TableConstants.railMaxY,
    );
    canvas.drawRect(
      railRect,
      Paint()..color = const Color(0xFF1565C0),
    );

    // 3. Lòng bàn xanh (blue!80): (0, 0) -> (188, 376)
    final playfieldRect = rectFromDiagram(
      0.0,
      0.0,
      scene.width,
      scene.height,
    );
    canvas.drawRect(
      playfieldRect,
      Paint()..color = const Color(0xFF2B7FD9),
    );
    canvas.drawRect(
      playfieldRect,
      Paint()
        ..color = const Color(0xFF0D47A1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 4. Lưới chia bước 47 (nếu bật)
    if (view.showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      for (final gx in TableConstants.shortRailDiamondX) {
        if (gx <= 0 || gx >= scene.width) continue;
        canvas.drawLine(
          mapper.diagramToScreen(DiagramPoint(gx, 0)),
          mapper.diagramToScreen(DiagramPoint(gx, scene.height)),
          gridPaint,
        );
      }
      for (final gy in TableConstants.longRailDiamondY) {
        if (gy <= 0 || gy >= scene.height) continue;
        canvas.drawLine(
          mapper.diagramToScreen(DiagramPoint(0, gy)),
          mapper.diagramToScreen(DiagramPoint(scene.width, gy)),
          gridPaint,
        );
      }
    }

    // 5. Nút diamond và số diamond trên phần khung/băng
    if (view.showDiamonds || view.showDiamondNumbers) {
      _paintDiamondsAndNumbers(canvas, s, view);
    }

    // 6. Vẽ các đường hướng dẫn DƯỚI lớp bi
    for (final path in scene.paths) {
      _paintGuidePath(canvas, path);
    }

    // 7. Vẽ đường xem trước đang dựng (nếu có)
    if (toolMode == EditorToolMode.drawPolyline &&
        (draftPoints.isNotEmpty || liveDrawCursor != null)) {
      _paintDraftPreview(canvas);
    }

    // 8. Vẽ ba bi (trên lớp đường)
    for (final ball in scene.balls) {
      _paintBall(canvas, ball, s, view.showBallNumbers);
    }

    // 9. Tay nắm điểm điều khiển chỉ hiện khi đang chọn đường trong chế độ chỉnh sửa
    if (toolMode == EditorToolMode.select && selectedPathId != null) {
      for (final path in scene.paths) {
        if (path.id == selectedPathId) {
          _paintSelectedPathHandles(canvas, path);
          break;
        }
      }
    }
  }

  Color _resolvePathColor(GuidePath path) {
    if (path.customColorValue != null) {
      return Color(path.customColorValue!);
    }
    for (final b in scene.balls) {
      if (b.id == path.ownerBallId) {
        return PathGeometry.defaultColorForBall(b.color);
      }
    }
    return Colors.white;
  }

  void _paintGuidePath(Canvas canvas, GuidePath path) {
    final isSelected = path.id == selectedPathId;
    final isInvalid = invalidPathIds.contains(path.id);
    final baseColor = _resolvePathColor(path);
    final strokeWidth = path.strokeWidth;

    if (isInvalid) {
      final warnPaint = Paint()
        ..color = Colors.orangeAccent.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final seg in path.segments) {
        canvas.drawLine(
          mapper.diagramToScreen(seg.start),
          mapper.diagramToScreen(seg.end),
          warnPaint,
        );
      }
    } else if (isSelected) {
      final haloPaint = Paint()
        ..color = const Color(0xFF80D8FF).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final seg in path.segments) {
        canvas.drawLine(
          mapper.diagramToScreen(seg.start),
          mapper.diagramToScreen(seg.end),
          haloPaint,
        );
      }
    }

    final linePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final seg in path.segments) {
      final a = mapper.diagramToScreen(seg.start);
      final b = mapper.diagramToScreen(seg.end);
      if (path.isDashed) {
        _drawDashedLine(canvas, a, b, linePaint);
      } else {
        canvas.drawLine(a, b, linePaint);
      }
    }

    // Mũi tên cuối đường theo hướng đoạn cuối khác độ dài 0
    if (path.arrowMode == ArrowMode.end && path.segments.isNotEmpty) {
      final dir = PathGeometry.lastNonZeroDirection(path);
      if (dir != null) {
        final tip = mapper.diagramToScreen(path.segments.last.end);
        // Chuyển vector hướng từ hệ bàn (y lên) sang hệ màn hình (y xuống)
        final screenDir = Offset(dir.dx, -dir.dy);
        _drawArrowHead(canvas, tip, screenDir, baseColor, strokeWidth);
      }
    }
  }

  void _paintDraftPreview(Canvas canvas) {
    var ownerColor = Colors.white;
    for (final b in scene.balls) {
      if (b.id == draftOwnerBallId) {
        ownerColor = PathGeometry.defaultColorForBall(b.color);
        break;
      }
    }

    final previewPaint = Paint()
      ..color = ownerColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final previewPoints = <DiagramPoint>[
      ...draftPoints,
      ?liveDrawCursor,
    ];

    for (var i = 0; i < previewPoints.length - 1; i++) {
      final a = mapper.diagramToScreen(previewPoints[i]);
      final b = mapper.diagramToScreen(previewPoints[i + 1]);
      _drawDashedLine(canvas, a, b, previewPaint);
    }

    final dotFill = Paint()..color = ownerColor;
    final dotStroke = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final pt in previewPoints) {
      final c = mapper.diagramToScreen(pt);
      canvas.drawCircle(c, 4.5, dotFill);
      canvas.drawCircle(c, 4.5, dotStroke);
    }
  }

  void _paintSelectedPathHandles(Canvas canvas, GuidePath path) {
    final vertices = PathGeometry.extractVertices(path);
    for (var i = 0; i < vertices.length; i++) {
      final c = mapper.diagramToScreen(vertices[i]);
      final isAnchoredStart = i == 0 && path.startAnchorBallId != null;
      final isActiveVertex = i == selectedVertexIndex;

      canvas.drawCircle(
        c,
        isActiveVertex ? 7.5 : 6.0,
        Paint()
          ..color = isAnchoredStart
              ? Colors.amberAccent
              : (isActiveVertex ? const Color(0xFF80D8FF) : Colors.white),
      );
      canvas.drawCircle(
        c,
        isActiveVertex ? 7.5 : 6.0,
        Paint()
          ..color = const Color(0xFF0D47A1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isActiveVertex ? 2.2 : 1.5,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashLen = 8.0,
    double gapLen = 5.0,
  }) {
    final delta = end - start;
    final total = delta.distance;
    if (total <= 1e-3) return;
    final dir = delta / total;
    var dist = 0.0;
    while (dist < total) {
      final segEnd = math.min(total, dist + dashLen);
      canvas.drawLine(start + dir * dist, start + dir * segEnd, paint);
      dist += dashLen + gapLen;
    }
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset tip,
    Offset unitDir,
    Color color,
    double strokeWidth,
  ) {
    final headLength = 10.0 + strokeWidth * 1.4;
    const halfAngle = 0.44; // ~25 độ
    final base = tip - unitDir * headLength;
    final perp = Offset(-unitDir.dy, unitDir.dx);
    final wingOffset = perp * (headLength * math.tan(halfAngle));

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + wingOffset.dx, base.dy + wingOffset.dy)
      ..lineTo(base.dx - wingOffset.dx, base.dy - wingOffset.dy)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintDiamondsAndNumbers(
    Canvas canvas,
    double scale,
    SceneViewSettings view,
  ) {
    final diamondFill = Paint()..color = const Color(0xFFF5F5F5);
    final diamondStroke = Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final diamondHalfSize = math.max(2.4, 1.45 * scale);
    final labelFontSize = (3.6 * scale).clamp(8.0, 12.5).toDouble();

    void drawDiamondAt(DiagramPoint pt) {
      if (!view.showDiamonds) return;
      final c = mapper.diagramToScreen(pt);
      final path = Path()
        ..moveTo(c.dx, c.dy - diamondHalfSize)
        ..lineTo(c.dx + diamondHalfSize, c.dy)
        ..lineTo(c.dx, c.dy + diamondHalfSize)
        ..lineTo(c.dx - diamondHalfSize, c.dy)
        ..close();
      canvas.drawPath(path, diamondFill);
      canvas.drawPath(path, diamondStroke);
    }

    void drawLabelAt(DiagramPoint pt, String text) {
      if (!view.showDiamondNumbers) return;
      final c = mapper.diagramToScreen(pt);
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFFECEFF1),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx - tp.width / 2.0, c.dy - tp.height / 2.0));
    }

    for (var i = 0; i < TableConstants.shortRailDiamondX.length; i++) {
      final x = TableConstants.shortRailDiamondX[i];
      drawDiamondAt(DiagramPoint(x, -10.0));
      drawDiamondAt(DiagramPoint(x, 386.0));
      drawLabelAt(DiagramPoint(x, -16.0), '$i');
      drawLabelAt(DiagramPoint(x, 392.0), '$i');
    }

    for (var i = 0; i < TableConstants.longRailDiamondY.length; i++) {
      final y = TableConstants.longRailDiamondY[i];
      drawDiamondAt(DiagramPoint(-10.0, y));
      drawDiamondAt(DiagramPoint(198.0, y));
      drawLabelAt(DiagramPoint(-16.0, y), '$i');
      drawLabelAt(DiagramPoint(204.0, y), '$i');
    }
  }

  void _paintBall(
    Canvas canvas,
    Ball ball,
    double scale,
    bool showNumbers,
  ) {
    final center = mapper.diagramToScreen(ball.center);
    final radiusPx = ball.radius * scale;
    final isSelected = ball.id == selectedBallId && selectedPathId == null;

    Color fillColor;
    Color rimColor;
    Color textColor;

    switch (ball.color) {
      case BallColor.white:
        fillColor = const Color(0xFFFAFAFA);
        rimColor = const Color(0xFF757575);
        textColor = const Color(0xFF212121);
      case BallColor.yellow:
        fillColor = const Color(0xFFFFD54F);
        rimColor = const Color(0xFFF57F17);
        textColor = const Color(0xFF212121);
      case BallColor.red:
        fillColor = const Color(0xFFE53935);
        rimColor = const Color(0xFFB71C1C);
        textColor = Colors.white;
    }

    if (isSelected) {
      canvas.drawCircle(
        center,
        radiusPx + math.max(3.0, 1.3 * scale),
        Paint()
          ..color = const Color(0xFF80D8FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }

    canvas.drawCircle(
      center + const Offset(1.0, 1.5),
      radiusPx,
      Paint()..color = Colors.black.withValues(alpha: 0.26),
    );

    canvas.drawCircle(center, radiusPx, Paint()..color = fillColor);
    canvas.drawCircle(
      center,
      radiusPx,
      Paint()
        ..color = rimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    if (showNumbers && ball.label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: ball.label,
          style: TextStyle(
            color: textColor,
            fontSize: math.max(8.0, radiusPx * 1.15),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0),
      );
    }

    if (ball.locked) {
      final badgeCenter = center + Offset(radiusPx * 0.78, -radiusPx * 0.78);
      final badgeRadius = math.max(4.5, radiusPx * 0.42);
      canvas.drawCircle(
        badgeCenter,
        badgeRadius,
        Paint()..color = const Color(0xFF263238),
      );
      canvas.drawCircle(
        badgeCenter,
        badgeRadius,
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BilliardTablePainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.toolMode != toolMode ||
        oldDelegate.selectedBallId != selectedBallId ||
        oldDelegate.selectedPathId != selectedPathId ||
        oldDelegate.selectedVertexIndex != selectedVertexIndex ||
        oldDelegate.invalidPathIds.length != invalidPathIds.length ||
        !oldDelegate.invalidPathIds.containsAll(invalidPathIds) ||
        oldDelegate.draftPoints.length != draftPoints.length ||
        oldDelegate.draftOwnerBallId != draftOwnerBallId ||
        oldDelegate.liveDrawCursor != liveDrawCursor ||
        oldDelegate.mapper.scale != mapper.scale ||
        oldDelegate.mapper.canvasSize != mapper.canvasSize;
  }
}
