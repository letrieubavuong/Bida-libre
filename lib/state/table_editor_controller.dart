import 'package:flutter/foundation.dart';

import '../geometry/table_geometry.dart';
import '../models/models.dart';

/// Quản lý trạng thái màn hình Dựng thế bi (Phase 1):
/// - Chính sách giao dịch kéo: mỗi lần kéo có một `dragToken` duy nhất; trong lúc đang kéo
///   (`isDraggingBall == true`), controller vô hiệu hóa mọi thao tác xung đột
///   (beginBallDrag mới, undo, redo, resetBalls, toggleBallLock, setBallPosition,
///   trySetBallRadius, selectBall) để không làm hỏng snapshot hoặc sai thứ tự lịch sử Undo.
/// - Tất cả snapshot trong lịch sử Undo/Redo là DiagramScene bất biến (không dùng JSON copy).
class TableEditorController extends ChangeNotifier {
  static const int _maxHistory = 100;

  final DiagramScene _initialBaseline;
  DiagramScene _scene;
  String? _selectedBallId;

  final List<DiagramScene> _undoStack = [];
  final List<DiagramScene> _redoStack = [];

  int _nextDragToken = 1;
  int? _activeDragToken;
  String? _draggingBallId;
  DiagramScene? _dragStartSceneSnapshot;
  DiagramPoint? _dragStartCenter;
  DiagramPoint _dragFingerOffset = const DiagramPoint(0.0, 0.0);

  /// Tăng mỗi khi một lệnh hoàn chỉnh (undo/redo/reset/đặt tọa độ/khóa/đổi r) thay đổi scene,
  /// giúp UI đồng bộ lại ô nhập X/Y và xóa nháp nhập dở có chủ đích.
  int _authoritativeRevision = 0;

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
  bool get isDraggingBall => _activeDragToken != null;
  int? get activeDragToken => _activeDragToken;
  int get authoritativeRevision => _authoritativeRevision;

  bool get canUndo => !isDraggingBall && _undoStack.isNotEmpty;
  bool get canRedo => !isDraggingBall && _redoStack.isNotEmpty;

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

  bool selectBall(String? ballId) {
    if (isDraggingBall) return false;
    if (_selectedBallId == ballId) return true;
    _selectedBallId = ballId;
    notifyListeners();
    return true;
  }

  void _pushUndoSnapshot(DiagramScene previousScene) {
    _undoStack.add(previousScene);
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _authoritativeRevision++;
  }

  /// Bắt đầu một giao dịch kéo bi. Trả về `dragToken` nếu hợp lệ;
  /// trả về `null` nếu đang có giao dịch kéo khác chưa xử lý, không tìm thấy bi hoặc bi đang khóa.
  int? beginBallDrag(String ballId, {DiagramPoint? touchPoint}) {
    if (isDraggingBall) return null;

    final ball = _findBall(ballId);
    if (ball == null) return null;

    _selectedBallId = ballId;
    if (ball.locked) {
      notifyListeners();
      return null;
    }

    final token = _nextDragToken++;
    _activeDragToken = token;
    _draggingBallId = ballId;
    _dragStartSceneSnapshot = _scene;
    _dragStartCenter = ball.center;
    _dragFingerOffset = touchPoint != null
        ? (ball.center - touchPoint)
        : const DiagramPoint(0.0, 0.0);
    notifyListeners();
    return token;
  }

  /// Cập nhật vị trí kéo từ tọa độ điểm chạm ngón tay trên bàn (giữ nguyên độ lệch ban đầu).
  void updateBallDragFromTouch(DiagramPoint touchPoint, {int? dragToken}) {
    if (!touchPoint.isFinite) return;
    updateBallDrag(touchPoint + _dragFingerOffset, dragToken: dragToken);
  }

  /// Cập nhật vị trí tâm bi mong muốn khi đang kéo; chỉ tác động đúng `dragToken` đang hoạt động.
  void updateBallDrag(DiagramPoint desiredCenter, {int? dragToken}) {
    if (_activeDragToken == null) return;
    if (dragToken != null && dragToken != _activeDragToken) return;

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

  /// Kết thúc giao dịch kéo đang hoạt động: ghi nhận đúng 1 bước Undo nếu tọa độ thực sự đổi.
  bool endBallDrag({int? dragToken}) {
    if (_activeDragToken == null) return false;
    if (dragToken != null && dragToken != _activeDragToken) return false;

    final ballId = _draggingBallId;
    final snapshot = _dragStartSceneSnapshot;
    final startCenter = _dragStartCenter;

    _clearDragState();

    if (ballId != null && snapshot != null && startCenter != null) {
      final currentBall = _findBall(ballId);
      if (currentBall != null && currentBall.center != startCenter) {
        _pushUndoSnapshot(snapshot);
      }
    }
    notifyListeners();
    return true;
  }

  /// Xử lý pan cancel: chỉ hủy đúng giao dịch kéo đang hoạt động, khôi phục về trước khi kéo.
  bool cancelBallDrag({int? dragToken}) {
    if (_activeDragToken == null) return false;
    if (dragToken != null && dragToken != _activeDragToken) return false;

    final snapshot = _dragStartSceneSnapshot;
    _clearDragState();

    if (snapshot != null) {
      _scene = snapshot;
    }
    notifyListeners();
    return true;
  }

  void _clearDragState() {
    _activeDragToken = null;
    _draggingBallId = null;
    _dragStartSceneSnapshot = null;
    _dragStartCenter = null;
    _dragFingerOffset = const DiagramPoint(0.0, 0.0);
  }

  /// Nhập tọa độ X/Y thủ công cho một quả bi (theo đơn vị sơ đồ).
  /// Bị chặn nếu đang có giao dịch kéo hoạt động hoặc bi đang bị khóa.
  String? setBallPosition(String ballId, DiagramPoint newCenter) {
    if (isDraggingBall) {
      return 'Đang kéo bi, hãy thả tay trước khi sửa tọa độ.';
    }
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

  /// Khóa hoặc mở khóa vị trí của một quả bi (vô hiệu hóa trong lúc đang kéo).
  bool toggleBallLock(String ballId) {
    if (isDraggingBall) return false;
    final ball = _findBall(ballId);
    if (ball == null) return false;

    _pushUndoSnapshot(_scene);
    final updatedBalls = _scene.balls
        .map((b) => b.id == ballId ? b.copyWith(locked: !b.locked) : b)
        .toList(growable: false);
    _scene = _scene.withBalls(updatedBalls);
    notifyListeners();
    return true;
  }

  /// Kiểm tra và thay đổi bán kính bi; bị chặn trong lúc đang kéo.
  String? trySetBallRadius(double newRadius) {
    if (isDraggingBall) {
      return 'Đang kéo bi, hãy thả tay trước khi đổi bán kính.';
    }
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

  /// Đặt lại vị trí mặc định cho 3 bi; bị chặn trong lúc đang kéo.
  bool resetBalls() {
    if (isDraggingBall) return false;
    final defaults = _initialBaseline.balls;
    if (_ballsEqual(_scene.balls, defaults)) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withBalls(defaults);
    notifyListeners();
    return true;
  }

  bool undo() {
    if (isDraggingBall || _undoStack.isEmpty) return false;
    _redoStack.add(_scene);
    final previous = _undoStack.removeLast();
    _scene = previous.copyWith(viewSettings: _scene.viewSettings);
    _authoritativeRevision++;
    notifyListeners();
    return true;
  }

  bool redo() {
    if (isDraggingBall || _redoStack.isEmpty) return false;
    _undoStack.add(_scene);
    final next = _redoStack.removeLast();
    _scene = next.copyWith(viewSettings: _scene.viewSettings);
    _authoritativeRevision++;
    notifyListeners();
    return true;
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
