import 'package:flutter/foundation.dart';

import '../geometry/table_geometry.dart';
import '../models/models.dart';

/// Quản lý trạng thái màn hình Dựng thế bi (Phase 1):
/// - Chọn bi, kéo bi (giữ độ lệch ngón tay, 1 lần kéo = 1 bước undo), nhập tọa độ X/Y.
/// - Khóa/mở khóa bi, đổi bán kính, đặt lại mặc định, Undo/Redo.
/// - Tất cả snapshot trong lịch sử Undo/Redo là DiagramScene bất biến (không dùng JSON copy).
class TableEditorController extends ChangeNotifier {
  static const int _maxHistory = 100;

  final DiagramScene _initialBaseline;
  DiagramScene _scene;
  String? _selectedBallId;

  final List<DiagramScene> _undoStack = [];
  final List<DiagramScene> _redoStack = [];

  // Trạng thái thao tác kéo đang diễn ra
  String? _draggingBallId;
  DiagramScene? _dragStartSceneSnapshot;
  DiagramPoint? _dragStartCenter;
  DiagramPoint _dragFingerOffset = const DiagramPoint(0.0, 0.0);

  TableEditorController({DiagramScene? initialScene})
      : _initialBaseline =
            initialScene ?? DiagramScene.defaultInitial(id: 'phase1_stage'),
        _scene =
            initialScene ?? DiagramScene.defaultInitial(id: 'phase1_stage'),
        _selectedBallId =
            (initialScene?.balls.isNotEmpty ?? true)
                ? (initialScene?.balls.first.id ?? 'ball_white')
                : null;

  DiagramScene get scene => _scene;
  List<Ball> get balls => _scene.balls;
  SceneViewSettings get viewSettings => _scene.viewSettings;
  String? get selectedBallId => _selectedBallId;
  bool get isDraggingBall => _draggingBallId != null;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Có thay đổi chưa lưu so với trạng thái ban đầu khi mở màn hình.
  bool get hasUnsavedChanges => !_ballsEqual(_scene.balls, _initialBaseline.balls);

  double get currentBallRadius =>
      _scene.balls.isNotEmpty ? _scene.balls.first.radius : 4.0;

  Ball? get selectedBall {
    if (_selectedBallId == null) return null;
    for (final ball in _scene.balls) {
      if (ball.id == _selectedBallId) return ball;
    }
    return null;
  }

  /// Bản sao chỉ đọc của lịch sử Undo (dùng cho kiểm thử tính bất biến).
  List<DiagramScene> get undoHistory => List<DiagramScene>.unmodifiable(_undoStack);

  void selectBall(String? ballId) {
    if (_selectedBallId == ballId) return;
    _selectedBallId = ballId;
    notifyListeners();
  }

  void _pushUndoSnapshot(DiagramScene previousScene) {
    _undoStack.add(previousScene);
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Bắt đầu kéo một quả bi. Nếu [touchPoint] được truyền vào, lưu độ lệch giữa tâm bi
  /// và điểm chạm ngón tay để khi bắt đầu kéo không làm bi nhảy về phía ngón tay.
  bool beginBallDrag(String ballId, {DiagramPoint? touchPoint}) {
    final ball = _findBall(ballId);
    if (ball == null) return false;
    _selectedBallId = ballId;
    if (ball.locked) {
      notifyListeners();
      return false;
    }
    _draggingBallId = ballId;
    _dragStartSceneSnapshot = _scene;
    _dragStartCenter = ball.center;
    _dragFingerOffset = touchPoint != null
        ? (ball.center - touchPoint)
        : const DiagramPoint(0.0, 0.0);
    notifyListeners();
    return true;
  }

  /// Cập nhật vị trí kéo từ tọa độ điểm chạm ngón tay trên bàn (giữ nguyên độ lệch ban đầu).
  void updateBallDragFromTouch(DiagramPoint touchPoint) {
    if (!touchPoint.isFinite) return;
    updateBallDrag(touchPoint + _dragFingerOffset);
  }

  /// Cập nhật vị trí tâm bi mong muốn khi đang kéo; tự kẹp trong lòng bàn và chống chồng bi.
  void updateBallDrag(DiagramPoint desiredCenter) {
    final ballId = _draggingBallId;
    if (ballId == null) return;
    final ball = _findBall(ballId);
    if (ball == null || ball.locked) return;

    final resolved = BallPlacementValidator.resolveDragPosition(
      draggedBall: ball,
      desiredCenter: desiredCenter,
      lastValidCenter: ball.center,
      allBalls: _scene.balls,
      width: _scene.width,
      height: _scene.height,
    );

    if (resolved == ball.center) return;

    final updatedBalls = _scene.balls
        .map((b) => b.id == ballId ? b.copyWith(center: resolved) : b)
        .toList(growable: false);
    _scene = _scene.withBalls(updatedBalls);
    notifyListeners();
  }

  /// Kết thúc lần kéo: ghi nhận đúng 1 bước Undo chỉ khi tọa độ bi thực sự thay đổi.
  void endBallDrag() {
    final ballId = _draggingBallId;
    final snapshot = _dragStartSceneSnapshot;
    final startCenter = _dragStartCenter;

    _draggingBallId = null;
    _dragStartSceneSnapshot = null;
    _dragStartCenter = null;
    _dragFingerOffset = const DiagramPoint(0.0, 0.0);

    if (ballId == null || snapshot == null || startCenter == null) return;

    final currentBall = _findBall(ballId);
    if (currentBall != null && currentBall.center != startCenter) {
      _pushUndoSnapshot(snapshot);
      notifyListeners();
    }
  }

  /// Xử lý pan cancel: hủy thao tác kéo đang dở, khôi phục về trước khi kéo, không tạo Undo dở dang.
  void cancelBallDrag() {
    final snapshot = _dragStartSceneSnapshot;
    if (_draggingBallId == null) return;

    _draggingBallId = null;
    _dragStartSceneSnapshot = null;
    _dragStartCenter = null;
    _dragFingerOffset = const DiagramPoint(0.0, 0.0);

    if (snapshot != null) {
      _scene = snapshot;
    }
    notifyListeners();
  }

  /// Nhập tọa độ X/Y thủ công cho một quả bi (theo đơn vị sơ đồ).
  /// Trả về thông báo lỗi tiếng Việt nếu không hợp lệ hoặc bi đang khóa; null nếu thành công.
  String? setBallPosition(String ballId, DiagramPoint newCenter) {
    final ball = _findBall(ballId);
    if (ball == null) return 'Không tìm thấy bi.';
    if (ball.locked) {
      return '${ball.color.label} đang bị khóa. Hãy mở khóa trước khi sửa tọa độ.';
    }

    final error = BallPlacementValidator.validateManualPlacement(
      targetBall: ball,
      candidateCenter: newCenter,
      allBalls: _scene.balls,
      width: _scene.width,
      height: _scene.height,
    );
    if (error != null) return error;

    if (ball.center == newCenter) return null;

    _pushUndoSnapshot(_scene);
    final updatedBalls = _scene.balls
        .map((b) => b.id == ballId ? b.copyWith(center: newCenter) : b)
        .toList(growable: false);
    _scene = _scene.withBalls(updatedBalls);
    notifyListeners();
    return null;
  }

  /// Khóa hoặc mở khóa vị trí của một quả bi (tạo 1 bước Undo).
  void toggleBallLock(String ballId) {
    final ball = _findBall(ballId);
    if (ball == null) return;
    _pushUndoSnapshot(_scene);
    final updatedBalls = _scene.balls
        .map((b) => b.id == ballId ? b.copyWith(locked: !b.locked) : b)
        .toList(growable: false);
    _scene = _scene.withBalls(updatedBalls);
    notifyListeners();
  }

  /// Kiểm tra và thay đổi bán kính bi; nếu làm bố cục không hợp lệ thì báo lỗi và giữ nguyên.
  String? trySetBallRadius(double newRadius) {
    final error = BallPlacementValidator.validateLayoutForRadius(
      _scene.balls,
      newRadius,
      width: _scene.width,
      height: _scene.height,
    );
    if (error != null) return error;

    if ((currentBallRadius - newRadius).abs() < 1e-6) return null;

    _pushUndoSnapshot(_scene);
    final updatedBalls = _scene.balls
        .map((b) => b.copyWith(radius: newRadius))
        .toList(growable: false);
    _scene = _scene.withBalls(updatedBalls);
    notifyListeners();
    return null;
  }

  /// Đặt lại vị trí mặc định cho 3 bi (là một thao tác có thể Undo).
  void resetBalls() {
    final defaults = _initialBaseline.balls;
    if (_ballsEqual(_scene.balls, defaults)) return;
    _pushUndoSnapshot(_scene);
    _scene = _scene.withBalls(defaults);
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_scene);
    final previous = _undoStack.removeLast();
    _scene = previous.copyWith(viewSettings: _scene.viewSettings);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_scene);
    final next = _redoStack.removeLast();
    _scene = next.copyWith(viewSettings: _scene.viewSettings);
    notifyListeners();
  }

  void updateViewSettings(SceneViewSettings settings) {
    if (_scene.viewSettings == settings) return;
    _scene = _scene.copyWith(viewSettings: settings);
    notifyListeners();
  }

  Ball? _findBall(String id) {
    for (final ball in _scene.balls) {
      if (ball.id == id) return ball;
    }
    return null;
  }

  bool _ballsEqual(List<Ball> a, List<Ball> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
