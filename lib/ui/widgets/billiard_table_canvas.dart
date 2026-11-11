import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../geometry/table_constants.dart';
import '../../geometry/table_geometry.dart';
import '../../models/models.dart';

/// Bàn vẽ vector tĩnh theo mẫu TikZ (lòng bàn 188 x 376, khung -20..208 x -20..396)
/// hỗ trợ chọn và kéo thả ba bi trong lòng bàn với token giao dịch riêng cho từng lần kéo.
class BilliardTableCanvas extends StatefulWidget {
  final DiagramScene scene;
  final String? selectedBallId;
  final ValueChanged<String> onBallTapped;
  final int? Function(String ballId, DiagramPoint touchPoint) onBallDragStart;
  final void Function(DiagramPoint touchPoint, int dragToken)
      onBallDragUpdateFromTouch;
  final ValueChanged<int> onBallDragEnd;
  final ValueChanged<int> onBallDragCancel;
  final ValueChanged<Ball>? onLockedBallTouched;

  const BilliardTableCanvas({
    super.key,
    required this.scene,
    required this.selectedBallId,
    required this.onBallTapped,
    required this.onBallDragStart,
    required this.onBallDragUpdateFromTouch,
    required this.onBallDragEnd,
    required this.onBallDragCancel,
    this.onLockedBallTouched,
  });

  @override
  State<BilliardTableCanvas> createState() => _BilliardTableCanvasState();
}

class _BilliardTableCanvasState extends State<BilliardTableCanvas> {
  int? _activePointerId;
  int? _activeDragToken;

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
            if (_activePointerId != null) {
              // Ngón tay thứ hai chạm vào canvas trong lúc đang kéo -> hủy đúng giao dịch đang chạy.
              final token = _activeDragToken;
              _activePointerId = null;
              _activeDragToken = null;
              if (token != null) {
                widget.onBallDragCancel(token);
              }
              return;
            }

            final hit = BallPlacementValidator.hitTestBall(
              screenPosition: event.localPosition,
              balls: widget.scene.balls,
              mapper: mapper,
              preferredBallId: widget.selectedBallId,
            );
            if (hit == null) return;

            widget.onBallTapped(hit.id);
            final touchDiagram = mapper.screenToDiagram(event.localPosition);
            final token = widget.onBallDragStart(hit.id, touchDiagram);
            if (token != null) {
              _activePointerId = event.pointer;
              _activeDragToken = token;
            } else if (hit.locked) {
              widget.onLockedBallTouched?.call(hit);
            }
          },
          onPointerMove: (event) {
            final token = _activeDragToken;
            if (event.pointer != _activePointerId || token == null) {
              return;
            }
            final touchDiagram = mapper.screenToDiagram(event.localPosition);
            widget.onBallDragUpdateFromTouch(touchDiagram, token);
          },
          onPointerUp: (event) {
            if (event.pointer != _activePointerId) return;
            final token = _activeDragToken;
            _activePointerId = null;
            _activeDragToken = null;
            if (token != null) {
              widget.onBallDragEnd(token);
            }
          },
          onPointerCancel: (event) {
            if (event.pointer != _activePointerId) return;
            final token = _activeDragToken;
            _activePointerId = null;
            _activeDragToken = null;
            if (token != null) {
              widget.onBallDragCancel(token);
            }
          },
          child: CustomPaint(
            size: size,
            painter: _BilliardTablePainter(
              scene: widget.scene,
              mapper: mapper,
              selectedBallId: widget.selectedBallId,
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
  final String? selectedBallId;

  _BilliardTablePainter({
    required this.scene,
    required this.mapper,
    required this.selectedBallId,
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

    // 4. Lưới chia bước 47 (nếu bật) - vẽ trước bi để không che bi
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

    // 5. Nút diamond và số diamond trên phần khung/băng (nếu bật)
    if (view.showDiamonds || view.showDiamondNumbers) {
      _paintDiamondsAndNumbers(canvas, s, view);
    }

    // 6. Vẽ ba bi (sau cùng để lưới/đường trang trí không bao giờ che bi)
    for (final ball in scene.balls) {
      _paintBall(canvas, ball, s, view.showBallNumbers);
    }
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

    // Băng ngắn dưới & trên: x = 0, 47, 94, 141, 188
    for (var i = 0; i < TableConstants.shortRailDiamondX.length; i++) {
      final x = TableConstants.shortRailDiamondX[i];
      drawDiamondAt(DiagramPoint(x, -10.0));
      drawDiamondAt(DiagramPoint(x, 386.0));
      drawLabelAt(DiagramPoint(x, -16.0), '$i');
      drawLabelAt(DiagramPoint(x, 392.0), '$i');
    }

    // Băng dài trái & phải: y = 0, 47, ..., 376
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
    final isSelected = ball.id == selectedBallId;

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
        oldDelegate.selectedBallId != selectedBallId ||
        oldDelegate.mapper.scale != mapper.scale ||
        oldDelegate.mapper.canvasSize != mapper.canvasSize;
  }
}
