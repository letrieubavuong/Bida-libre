import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../geometry/annotation_geometry.dart';
import '../../geometry/path_geometry.dart';
import '../../geometry/table_constants.dart';
import '../../geometry/table_geometry.dart';
import '../../models/models.dart';
import '../../state/table_editor_controller.dart';

enum _ActiveDragKind { ball, vertex, controlHandle, annotation }

/// Bàn vẽ vector tĩnh theo mẫu TikZ (lòng bàn 188 x 376, khung -20..208 x -20..396):
/// - Chế độ Chọn / Di chuyển: kéo bi, chọn đường, kéo điểm nối, kéo tay nắm Bézier, kéo chú thích.
/// - Chế độ Vẽ đường: chạm đặt điểm gấp khúc với nét xem trước; không kéo nhầm bi.
/// - Chế độ Chú thích: chạm đặt nhãn, số thứ tự, chấm mốc hoặc vùng.
class BilliardTableCanvas extends StatefulWidget {
  final DiagramScene scene;
  final EditorToolMode toolMode;
  final String? selectedBallId;
  final String? selectedPathId;
  final int? selectedVertexIndex;
  final int? selectedSegmentIndex;
  final ({int segmentIndex, int handleIndex})? selectedControlHandle;
  final String? selectedAnnotationId;
  final Set<String> invalidPathIds;

  final List<DiagramPoint> draftPoints;
  final String draftOwnerBallId;
  final PathRole draftRole;
  final SnapSettings snapSettings;

  final ValueChanged<String> onBallTapped;
  final void Function(String? pathId, {int? segmentIndex}) onPathTapped;

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

  final int? Function(
    String pathId,
    int segmentIndex,
    int handleIndex,
    DiagramPoint touchPoint,
  )? onControlHandleDragStart;
  final void Function(DiagramPoint touchPoint, int dragToken)?
      onControlHandleDragUpdateFromTouch;
  final ValueChanged<int>? onControlHandleDragEnd;
  final ValueChanged<int>? onControlHandleDragCancel;

  final ValueChanged<String?>? onAnnotationTapped;
  final int? Function(String annotationId, DiagramPoint touchPoint)?
      onAnnotationDragStart;
  final void Function(DiagramPoint touchPoint, int dragToken)?
      onAnnotationDragUpdateFromTouch;
  final ValueChanged<int>? onAnnotationDragEnd;
  final ValueChanged<int>? onAnnotationDragCancel;
  final ValueChanged<DiagramAnnotation>? onLockedAnnotationTouched;
  final ValueChanged<DiagramPoint>? onAnnotationPlaceTapped;

  final ValueChanged<DiagramPoint> onDrawPointPlaced;

  final TransformationController? transformationController;

  const BilliardTableCanvas({
    super.key,
    required this.scene,
    required this.toolMode,
    required this.selectedBallId,
    required this.selectedPathId,
    required this.selectedVertexIndex,
    this.selectedSegmentIndex,
    this.selectedControlHandle,
    this.selectedAnnotationId,
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
    this.onControlHandleDragStart,
    this.onControlHandleDragUpdateFromTouch,
    this.onControlHandleDragEnd,
    this.onControlHandleDragCancel,
    this.onAnnotationTapped,
    this.onAnnotationDragStart,
    this.onAnnotationDragUpdateFromTouch,
    this.onAnnotationDragEnd,
    this.onAnnotationDragCancel,
    this.onLockedAnnotationTouched,
    this.onAnnotationPlaceTapped,
    required this.onDrawPointPlaced,
    this.transformationController,
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
  int _activePointersOnCanvas = 0;

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
      switch (kind) {
        case _ActiveDragKind.ball:
          widget.onBallDragCancel(token);
        case _ActiveDragKind.vertex:
          widget.onVertexDragCancel(token);
        case _ActiveDragKind.controlHandle:
          widget.onControlHandleDragCancel?.call(token);
        case _ActiveDragKind.annotation:
          widget.onAnnotationDragCancel?.call(token);
      }
    }
  }

  Offset _transformLocalPosition(Offset screenPos) {
    final tc = widget.transformationController;
    if (tc == null) return screenPos;
    return tc.toScene(screenPos);
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
            _activePointersOnCanvas++;
            if (_activePointersOnCanvas >= 2) {
              if (_activePointerId != null) {
                _cancelCurrentSelectDrag();
              }
              if (_drawPointerId != null) {
                _drawPointerId = null;
                setState(() {
                  _liveDrawCursor = null;
                });
              }
              return;
            }
            final effectiveLocalPos = _transformLocalPosition(event.localPosition);
            if (widget.toolMode == EditorToolMode.drawPolyline) {
              if (_drawPointerId != null) return;
              _drawPointerId = event.pointer;
              final raw = mapper.screenToDiagram(effectiveLocalPos);
              setState(() {
                _liveDrawCursor = _snapDraftCursor(raw);
              });
              return;
            }

            if (widget.toolMode == EditorToolMode.placeAnnotation) {
              final raw = mapper.screenToDiagram(effectiveLocalPos);
              widget.onAnnotationPlaceTapped?.call(raw);
              return;
            }

            // Chế độ Chọn / Di chuyển
            if (_activePointerId != null) {
              _cancelCurrentSelectDrag();
              return;
            }

            // 1. Ưu tiên kiểm tra tay nắm Bézier & điểm nối của đường đang chọn
            final currentSelectedPath = _selectedPath;
            if (currentSelectedPath != null) {
              final controlHit = PathGeometry.hitTestControlHandle(
                screenPosition: effectiveLocalPos,
                path: currentSelectedPath,
                mapper: mapper,
              );
              final vertexHit = PathGeometry.hitTestPathVertex(
                screenPosition: effectiveLocalPos,
                path: currentSelectedPath,
                mapper: mapper,
              );
              final preferControl = controlHit != null &&
                  (vertexHit == null ||
                      controlHit.distancePx < vertexHit.distancePx);
              if (preferControl && widget.onControlHandleDragStart != null) {
                final touchDiagram = mapper.screenToDiagram(effectiveLocalPos);
                final token = widget.onControlHandleDragStart!(
                  currentSelectedPath.id,
                  controlHit.segmentIndex,
                  controlHit.handleIndex,
                  touchDiagram,
                );
                if (token != null) {
                  _activePointerId = event.pointer;
                  _activeDragToken = token;
                  _activeDragKind = _ActiveDragKind.controlHandle;
                }
                return;
              }
              if (vertexHit != null) {
                final touchDiagram = mapper.screenToDiagram(effectiveLocalPos);
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
              screenPosition: effectiveLocalPos,
              balls: widget.scene.balls,
              mapper: mapper,
              preferredBallId: widget.selectedBallId,
            );
            if (ballHit != null) {
              widget.onBallTapped(ballHit.id);
              final touchDiagram = mapper.screenToDiagram(effectiveLocalPos);
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

            // 3. Kiểm tra chạm chú thích nổi (nhãn, số thứ tự, chấm mốc)
            final fgAnnHit = AnnotationGeometry.hitTestAnnotation(
              screenPosition: effectiveLocalPos,
              annotations: widget.scene.annotations,
              mapper: mapper,
              preferredAnnotationId: widget.selectedAnnotationId,
              foregroundOnly: true,
            );
            if (fgAnnHit != null) {
              _handleAnnotationHit(fgAnnHit.annotation, effectiveLocalPos, event.pointer, mapper);
              return;
            }

            // 4. Kiểm tra chạm thân đường (theo đường cong thực)
            final pathHit = PathGeometry.hitTestPath(
              screenPosition: effectiveLocalPos,
              paths: widget.scene.paths,
              mapper: mapper,
              preferredPathId: widget.selectedPathId,
            );
            if (pathHit != null) {
              widget.onPathTapped(
                pathHit.path.id,
                segmentIndex: pathHit.segmentIndex,
              );
              return;
            }

            // 5. Kiểm tra chạm chú thích vùng (vùng tròn / vùng chữ nhật)
            final zoneHit = AnnotationGeometry.hitTestAnnotation(
              screenPosition: effectiveLocalPos,
              annotations: widget.scene.annotations,
              mapper: mapper,
              preferredAnnotationId: widget.selectedAnnotationId,
              zonesOnly: true,
            );
            if (zoneHit != null) {
              _handleAnnotationHit(zoneHit.annotation, effectiveLocalPos, event.pointer, mapper);
              return;
            }

            // 6. Chạm vùng trống -> bỏ chọn đường & chú thích hiện tại
            if (widget.selectedPathId != null) {
              widget.onPathTapped(null);
            }
            if (widget.selectedAnnotationId != null) {
              widget.onAnnotationTapped?.call(null);
            }
          },
          onPointerMove: (event) {
            final effectiveLocalPos = _transformLocalPosition(event.localPosition);
            if (widget.toolMode == EditorToolMode.drawPolyline) {
              if (event.pointer != _drawPointerId) return;
              final raw = mapper.screenToDiagram(effectiveLocalPos);
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
            final touchDiagram = mapper.screenToDiagram(effectiveLocalPos);
            switch (kind) {
              case _ActiveDragKind.ball:
                widget.onBallDragUpdateFromTouch(touchDiagram, token);
              case _ActiveDragKind.vertex:
                widget.onVertexDragUpdateFromTouch(touchDiagram, token);
              case _ActiveDragKind.controlHandle:
                widget.onControlHandleDragUpdateFromTouch
                    ?.call(touchDiagram, token);
              case _ActiveDragKind.annotation:
                widget.onAnnotationDragUpdateFromTouch
                    ?.call(touchDiagram, token);
            }
          },
          onPointerUp: (event) {
            if (_activePointersOnCanvas > 0) {
              _activePointersOnCanvas--;
            }
            final effectiveLocalPos = _transformLocalPosition(event.localPosition);
            if (widget.toolMode == EditorToolMode.drawPolyline) {
              if (event.pointer != _drawPointerId) return;
              final raw = mapper.screenToDiagram(effectiveLocalPos);
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
              switch (kind) {
                case _ActiveDragKind.ball:
                  widget.onBallDragEnd(token);
                case _ActiveDragKind.vertex:
                  widget.onVertexDragEnd(token);
                case _ActiveDragKind.controlHandle:
                  widget.onControlHandleDragEnd?.call(token);
                case _ActiveDragKind.annotation:
                  widget.onAnnotationDragEnd?.call(token);
              }
            }
          },
          onPointerCancel: (event) {
            if (_activePointersOnCanvas > 0) {
              _activePointersOnCanvas--;
            }
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
              selectedSegmentIndex: widget.selectedSegmentIndex,
              selectedControlHandle: widget.selectedControlHandle,
              selectedAnnotationId: widget.selectedAnnotationId,
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

  void _handleAnnotationHit(
    DiagramAnnotation ann,
    Offset effectivePos,
    int pointerId,
    TableCoordinateMapper mapper,
  ) {
    widget.onAnnotationTapped?.call(ann.id);
    if (widget.onAnnotationDragStart != null) {
      final touchDiagram = mapper.screenToDiagram(effectivePos);
      final token = widget.onAnnotationDragStart!(ann.id, touchDiagram);
      if (token != null) {
        _activePointerId = pointerId;
        _activeDragToken = token;
        _activeDragKind = _ActiveDragKind.annotation;
      } else if (ann.locked) {
        widget.onLockedAnnotationTouched?.call(ann);
      }
    } else if (ann.locked) {
      widget.onLockedAnnotationTouched?.call(ann);
    }
  }
}

/// Khung hiển thị sơ đồ bàn chỉ đọc dành cho màn hình xem chi tiết bài viết hoặc thẻ xem trước:
/// không gắn tay nắm điều khiển và không nhận kéo/chạm làm thay đổi vị trí bi hoặc đường.
class BilliardTableReadOnlyView extends StatelessWidget {
  final DiagramScene scene;
  final double paddingPx;

  const BilliardTableReadOnlyView({
    super.key,
    required this.scene,
    this.paddingPx = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AspectRatio(
        aspectRatio: TableCoordinateMapper.totalDiagramWidth /
            TableCoordinateMapper.totalDiagramHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(
              constraints.maxWidth.isFinite ? constraints.maxWidth : 228.0,
              constraints.maxHeight.isFinite ? constraints.maxHeight : 416.0,
            );
            final mapper = TableCoordinateMapper(
              canvasSize: size,
              paddingPx: paddingPx,
            );
            return CustomPaint(
              size: size,
              painter: _BilliardTablePainter(
                scene: scene,
                mapper: mapper,
                toolMode: EditorToolMode.select,
                selectedBallId: null,
                selectedPathId: null,
                selectedVertexIndex: null,
                selectedSegmentIndex: null,
                selectedControlHandle: null,
                selectedAnnotationId: null,
                invalidPathIds: const {},
                draftPoints: const [],
                draftOwnerBallId: 'ball_white',
                liveDrawCursor: null,
              ),
            );
          },
        ),
      ),
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
  final int? selectedSegmentIndex;
  final ({int segmentIndex, int handleIndex})? selectedControlHandle;
  final String? selectedAnnotationId;
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
    required this.selectedSegmentIndex,
    required this.selectedControlHandle,
    required this.selectedAnnotationId,
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

    // 1. Khung ngoài xám sáng bo góc theo mẫu: (-20, -20) -> (208, 396)
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
      Paint()..color = const Color(0xFFD5D9DC),
    );
    canvas.drawRRect(
      frameRRect,
      Paint()
        ..color = const Color(0xFF8F969E)
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
      Paint()..color = const Color(0xFF1358A8),
    );

    // 3. Lòng bàn xanh sáng theo mẫu: (0, 0) -> (188, 376)
    final playfieldRect = rectFromDiagram(
      0.0,
      0.0,
      scene.width,
      scene.height,
    );
    canvas.drawRect(
      playfieldRect,
      Paint()..color = const Color(0xFF1C75CD),
    );
    canvas.drawRect(
      playfieldRect,
      Paint()
        ..color = const Color(0xFF0C407A)
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

    // 5b. Chú thích dạng vùng (vùng tròn, vùng chữ nhật) nằm dưới lớp đường & bi
    for (final ann in scene.annotations) {
      if (AnnotationGeometry.isZoneType(ann.type)) {
        _paintAnnotation(canvas, ann, s);
      }
    }

    // 6. Vẽ các đường hướng dẫn DƯỚI lớp bi (hỗ trợ cả đoạn thẳng và Bézier bậc ba)
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

    // 8b. Chú thích nổi (chấm mốc, số thứ tự, nhãn chữ) trên lớp đường và bi
    for (final ann in scene.annotations) {
      if (!AnnotationGeometry.isZoneType(ann.type)) {
        _paintAnnotation(canvas, ann, s);
      }
    }

    // 9. Tay nắm điểm nối & tay nắm Bézier chỉ hiện khi chỉnh đường đang chọn
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

  Path _buildScreenPath(GuidePath path) {
    final screenPath = Path();
    if (path.segments.isEmpty) return screenPath;
    final first = mapper.diagramToScreen(path.segments.first.start);
    screenPath.moveTo(first.dx, first.dy);
    for (final seg in path.segments) {
      final endPt = mapper.diagramToScreen(seg.end);
      if (seg.type == SegmentType.cubic &&
          seg.control1 != null &&
          seg.control2 != null) {
        final c1 = mapper.diagramToScreen(seg.control1!);
        final c2 = mapper.diagramToScreen(seg.control2!);
        screenPath.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, endPt.dx, endPt.dy);
      } else {
        screenPath.lineTo(endPt.dx, endPt.dy);
      }
    }
    return screenPath;
  }

  void _paintGuidePath(Canvas canvas, GuidePath path) {
    final isSelected = path.id == selectedPathId;
    final isInvalid = invalidPathIds.contains(path.id);
    final baseColor = _resolvePathColor(path);
    final strokeWidth = path.strokeWidth;
    final screenPath = _buildScreenPath(path);

    if (isInvalid) {
      final warnPaint = Paint()
        ..color = Colors.orangeAccent.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(screenPath, warnPaint);
    } else if (isSelected) {
      final haloPaint = Paint()
        ..color = const Color(0xFF80D8FF).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(screenPath, haloPaint);
    }

    final linePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (path.isDashed) {
      _drawDashedPath(canvas, screenPath, linePaint);
    } else {
      canvas.drawPath(screenPath, linePaint);
    }

    // Mũi tên cuối đường theo tiếp tuyến cuối (kể cả đoạn cong cubic và tiếp tuyến suy biến)
    if (path.arrowMode == ArrowMode.end && path.segments.isNotEmpty) {
      final dir = PathGeometry.lastNonZeroDirection(path);
      if (dir != null) {
        final tip = mapper.diagramToScreen(path.segments.last.end);
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
    // 1. Vẽ tay nắm Bézier (chỉ cho đường đang chọn và chế độ Chọn)
    final tangentLinePaint = Paint()
      ..color = const Color(0xFFB3E5FC).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    for (var sIdx = 0; sIdx < path.segments.length; sIdx++) {
      final seg = path.segments[sIdx];
      if (seg.type != SegmentType.cubic ||
          seg.control1 == null ||
          seg.control2 == null) {
        continue;
      }
      final startPx = mapper.diagramToScreen(seg.start);
      final endPx = mapper.diagramToScreen(seg.end);
      final c1Px = mapper.diagramToScreen(seg.control1!);
      final c2Px = mapper.diagramToScreen(seg.control2!);

      _drawDashedLine(canvas, startPx, c1Px, tangentLinePaint, dashLen: 4.0, gapLen: 3.0);
      _drawDashedLine(canvas, endPx, c2Px, tangentLinePaint, dashLen: 4.0, gapLen: 3.0);

      for (final entry in [(1, c1Px), (2, c2Px)]) {
        final handleIdx = entry.$1;
        final pos = entry.$2;
        final isActive = selectedControlHandle != null &&
            selectedControlHandle!.segmentIndex == sIdx &&
            selectedControlHandle!.handleIndex == handleIdx;
        final r = isActive ? 7.0 : 5.5;
        final diamond = Path()
          ..moveTo(pos.dx, pos.dy - r)
          ..lineTo(pos.dx + r, pos.dy)
          ..lineTo(pos.dx, pos.dy + r)
          ..lineTo(pos.dx - r, pos.dy)
          ..close();
        canvas.drawPath(
          diamond,
          Paint()..color = isActive ? const Color(0xFF00E5FF) : const Color(0xFFFFECB3),
        );
        canvas.drawPath(
          diamond,
          Paint()
            ..color = const Color(0xFF0D47A1)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isActive ? 2.0 : 1.4,
        );
      }
    }

    // 2. Vẽ các đỉnh nối
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

  void _paintAnnotation(Canvas canvas, DiagramAnnotation ann, double scale) {
    final isSelected = ann.id == selectedAnnotationId;
    final color = ann.colorValue != null
        ? Color(ann.colorValue!)
        : AnnotationGeometry.defaultColorFor(ann.type);
    final center = mapper.diagramToScreen(ann.position);

    switch (ann.type) {
      case AnnotationType.circleZone:
        final radiusPx = ann.radius * scale;
        final zonePath = Path()
          ..addOval(Rect.fromCircle(center: center, radius: radiusPx));
        canvas.drawPath(
          zonePath,
          Paint()..color = color.withValues(alpha: 0.16),
        );
        if (isSelected) {
          canvas.drawPath(
            zonePath,
            Paint()
              ..color = const Color(0xFF80D8FF).withValues(alpha: 0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = ann.strokeWidth + 4.0,
          );
        }
        final strokePaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ann.strokeWidth;
        if (ann.isDashed) {
          _drawDashedPath(canvas, zonePath, strokePaint);
        } else {
          canvas.drawPath(zonePath, strokePaint);
        }
        if (ann.text.isNotEmpty) {
          _drawCenteredAnnotationText(
            canvas,
            center,
            ann.text,
            color,
            11.0,
          );
        }

      case AnnotationType.rectZone:
        final wPx = ann.width * scale;
        final hPx = ann.height * scale;
        final rect = Rect.fromCenter(center: center, width: wPx, height: hPx);
        final rectPath = Path()..addRect(rect);
        canvas.drawRect(
          rect,
          Paint()..color = color.withValues(alpha: 0.16),
        );
        if (isSelected) {
          canvas.drawRect(
            rect,
            Paint()
              ..color = const Color(0xFF80D8FF).withValues(alpha: 0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = ann.strokeWidth + 4.0,
          );
        }
        final strokePaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ann.strokeWidth;
        if (ann.isDashed) {
          _drawDashedPath(canvas, rectPath, strokePaint);
        } else {
          canvas.drawRect(rect, strokePaint);
        }
        if (ann.text.isNotEmpty) {
          _drawCenteredAnnotationText(
            canvas,
            center,
            ann.text,
            color,
            11.0,
          );
        }

      case AnnotationType.marker:
        final rPx = (ann.radius * scale).clamp(4.0, 24.0);
        if (isSelected) {
          canvas.drawCircle(
            center,
            rPx + 4.0,
            Paint()
              ..color = const Color(0xFF80D8FF).withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4,
          );
        }
        canvas.drawCircle(center, rPx, Paint()..color = color);
        canvas.drawCircle(
          center,
          rPx,
          Paint()
            ..color = Colors.black87
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );

      case AnnotationType.sequence:
        final rPx = (ann.radius * scale).clamp(11.0, 26.0);
        if (isSelected) {
          canvas.drawCircle(
            center,
            rPx + 4.0,
            Paint()
              ..color = const Color(0xFF80D8FF).withValues(alpha: 0.75)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
        }
        canvas.drawCircle(center, rPx, Paint()..color = color);
        canvas.drawCircle(
          center,
          rPx,
          Paint()
            ..color = const Color(0xFF212121)
            ..style = PaintingStyle.stroke
            ..strokeWidth = ann.strokeWidth.clamp(1.0, 3.0),
        );
        _drawCenteredAnnotationText(
          canvas,
          center,
          ann.text.isEmpty ? '1' : ann.text,
          const Color(0xFF1A1A1A),
          (rPx * 1.05).clamp(10.0, 16.0),
        );

      case AnnotationType.label:
        final content = ann.text.isEmpty ? 'Nhãn' : ann.text;
        final tp = TextPainter(
          text: TextSpan(
            text: content,
            style: TextStyle(
              color: const Color(0xFF0D253F),
              fontSize: 12.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pillRect = Rect.fromCenter(
          center: center,
          width: tp.width + 14.0,
          height: tp.height + 8.0,
        );
        final rrect = RRect.fromRectAndRadius(pillRect, const Radius.circular(8.0));
        if (isSelected) {
          canvas.drawRRect(
            rrect.inflate(3.0),
            Paint()
              ..color = const Color(0xFF80D8FF).withValues(alpha: 0.75)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4,
          );
        }
        canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.92));
        final borderPaint = Paint()
          ..color = const Color(0xFF0D47A1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ann.strokeWidth.clamp(1.0, 3.0);
        if (ann.isDashed) {
          _drawDashedPath(canvas, Path()..addRRect(rrect), borderPaint);
        } else {
          canvas.drawRRect(rrect, borderPaint);
        }
        tp.paint(
          canvas,
          Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0),
        );
    }

    if (ann.locked) {
      final badgePos = center + const Offset(10.0, -10.0);
      canvas.drawCircle(badgePos, 4.5, Paint()..color = const Color(0xFF263238));
      canvas.drawCircle(
        badgePos,
        4.5,
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  void _drawCenteredAnnotationText(
    Canvas canvas,
    Offset center,
    String text,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
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

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dashLen = 8.0,
    double gapLen = 5.0,
  }) {
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final nextEnd = math.min(metric.length, dist + dashLen);
        canvas.drawPath(metric.extractPath(dist, nextEnd), paint);
        dist += dashLen + gapLen;
      }
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
        oldDelegate.selectedSegmentIndex != selectedSegmentIndex ||
        oldDelegate.selectedControlHandle != selectedControlHandle ||
        oldDelegate.selectedAnnotationId != selectedAnnotationId ||
        oldDelegate.invalidPathIds.length != invalidPathIds.length ||
        !oldDelegate.invalidPathIds.containsAll(invalidPathIds) ||
        oldDelegate.draftPoints.length != draftPoints.length ||
        oldDelegate.draftOwnerBallId != draftOwnerBallId ||
        oldDelegate.liveDrawCursor != liveDrawCursor ||
        oldDelegate.mapper.scale != mapper.scale ||
        oldDelegate.mapper.canvasSize != mapper.canvasSize;
  }
}
