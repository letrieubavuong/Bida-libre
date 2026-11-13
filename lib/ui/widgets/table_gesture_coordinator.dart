import 'package:flutter/widgets.dart';

import '../../geometry/table_geometry.dart';
import '../../models/models.dart';

/// Trạng thái phân quyền cử chỉ trên bàn bi-a.
/// Giúp phân định độc quyền giữa:
/// - idle: Sẵn sàng nhận thao tác mới.
/// - objectDrag: Đang kéo 1 bi, 1 điểm đỉnh đường, 1 tay nắm Bézier hoặc 1 chú thích bằng 1 ngón.
/// - drawing: Đang vẽ đường hoặc đặt chú thích bằng 1 ngón.
/// - viewportGesture: Đang zoom / pan khung nhìn bằng hai ngón (pinch / pan).
enum TableGestureState {
  idle,
  objectDrag,
  drawing,
  viewportGesture,
}

/// Tiện ích chuyển đổi tọa độ chuẩn mực:
/// Độc lập, rõ ràng giữa không gian Viewport (trước biến đổi),
/// không gian Canvas cục bộ (sau biến đổi) và không gian Sơ đồ (Diagram 188×376).
class TableCoordinateConverter {
  const TableCoordinateConverter._();

  /// Đổi tọa độ sơ đồ sang tọa độ cục bộ của canvas.
  static Offset diagramToCanvas(DiagramPoint point, TableCoordinateMapper mapper) {
    return mapper.diagramToScreen(point);
  }

  /// Đổi tọa độ cục bộ của canvas sang tọa độ sơ đồ.
  static DiagramPoint canvasToDiagram(Offset canvasPos, TableCoordinateMapper mapper) {
    return mapper.screenToDiagram(canvasPos);
  }

  /// Đổi tọa độ viewport (ngoài InteractiveViewer) sang tọa độ cục bộ canvas (trong InteractiveViewer).
  static Offset viewportToCanvas(Offset viewportPos, Matrix4 transformMatrix) {
    final inverse = Matrix4.tryInvert(transformMatrix);
    if (inverse == null) return viewportPos;
    return MatrixUtils.transformPoint(inverse, viewportPos);
  }

  /// Đổi tọa độ cục bộ canvas sang tọa độ viewport.
  static Offset canvasToViewport(Offset canvasPos, Matrix4 transformMatrix) {
    return MatrixUtils.transformPoint(transformMatrix, canvasPos);
  }

  /// Đổi tọa độ viewport sang tọa độ sơ đồ đúng 1 lần (xét ma trận và mapper).
  static DiagramPoint viewportToDiagram({
    required Offset viewportPos,
    required Matrix4 transformMatrix,
    required TableCoordinateMapper mapper,
  }) {
    final canvasPos = viewportToCanvas(viewportPos, transformMatrix);
    return canvasToDiagram(canvasPos, mapper);
  }

  /// Đổi tọa độ sơ đồ sang tọa độ viewport đúng 1 lần (xét mapper và ma trận).
  static Offset diagramToViewport({
    required DiagramPoint diagramPoint,
    required Matrix4 transformMatrix,
    required TableCoordinateMapper mapper,
  }) {
    final canvasPos = diagramToCanvas(diagramPoint, mapper);
    return canvasToViewport(canvasPos, transformMatrix);
  }
}

/// Bộ điều phối phân quyền gesture (Coordinator):
/// - Một luồng duy nhất kiểm soát quyền kéo đối tượng, vẽ hoặc thao tác khung nhìn.
/// - 1 ngón: Kéo bi/đối tượng hoặc vẽ, không bao giờ pan bàn (InteractiveViewer panEnabled = false).
/// - 2 ngón: Zoom / pan khung nhìn. Tự động hủy giao dịch kéo bi nếu đang kéo dở.
/// - Khi quay về 1 ngón sau pinch: Giữ trạng thái viewportGesture cho tới khi nhấc hết ngón,
///   không lập tức kéo bi hay tạo điểm vẽ ngoài ý muốn.
class TableGestureCoordinator extends ChangeNotifier {
  TableGestureState _state = TableGestureState.idle;
  TableGestureState get state => _state;

  final Map<int, Offset> _activePointers = {};
  int get activePointerCount => _activePointers.length;

  bool get isViewportGestureActive => _state == TableGestureState.viewportGesture;

  /// Chỉ cho phép InteractiveViewer pan/zoom khi có từ 2 ngón trở lên.
  bool get panEnabled => _activePointers.length >= 2;
  bool get scaleEnabled => _activePointers.length >= 2;

  void onPointerDown(
    PointerDownEvent event, {
    VoidCallback? onCancelActiveDrag,
  }) {
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length >= 2) {
      if (_state == TableGestureState.objectDrag ||
          _state == TableGestureState.drawing) {
        onCancelActiveDrag?.call();
      }
      _state = TableGestureState.viewportGesture;
      notifyListeners();
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event.position;
    }
  }

  void onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _state = TableGestureState.idle;
      notifyListeners();
    } else if (_state == TableGestureState.viewportGesture) {
      notifyListeners();
    }
  }

  void onPointerCancel(
    PointerCancelEvent event, {
    VoidCallback? onCancelActiveDrag,
  }) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _state = TableGestureState.idle;
      notifyListeners();
    } else if (_state == TableGestureState.viewportGesture) {
      notifyListeners();
    }
  }

  void notifyDragStarted() {
    if (_state == TableGestureState.idle && _activePointers.length <= 1) {
      _state = TableGestureState.objectDrag;
    }
  }

  void notifyDrawingStarted() {
    if (_state == TableGestureState.idle && _activePointers.length <= 1) {
      _state = TableGestureState.drawing;
    }
  }

  void notifyDragEnded() {
    if (_state == TableGestureState.objectDrag) {
      _state = _activePointers.isEmpty ? TableGestureState.idle : _state;
    }
  }

  void notifyDrawingEnded() {
    if (_state == TableGestureState.drawing) {
      _state = _activePointers.isEmpty ? TableGestureState.idle : _state;
    }
  }

  void reset() {
    _activePointers.clear();
    _state = TableGestureState.idle;
    notifyListeners();
  }
}
