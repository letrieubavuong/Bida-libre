import 'package:flutter/foundation.dart';

import '../geometry/path_geometry.dart';
import '../geometry/table_geometry.dart';
import '../models/models.dart';
import '../repositories/scene_storage.dart';

enum EditorToolMode {
  select('Chọn / Di chuyển'),
  drawPolyline('Vẽ đường');

  const EditorToolMode(this.label);
  final String label;
}

/// Quản lý trạng thái màn hình Dựng thế bi (Phase 1 + Phase 2):
/// - Hỗ trợ hai chế độ: Chọn/Di chuyển bi & chỉnh đường vs Vẽ đường thẳng/gấp khúc.
/// - Bảo vệ giao dịch kéo (cho cả kéo bi và kéo điểm điều khiển đường) bằng `dragToken`.
/// - Lưu/tải một sơ đồ nguyên tử qua `SceneStorage` (chỉ báo thành công sau khi ghi xong).
class TableEditorController extends ChangeNotifier {
  static const int _maxHistory = 100;

  final SceneStorage? storage;
  DiagramScene _savedBaseline;
  DiagramScene _scene;

  String? _selectedBallId;
  String? _selectedPathId;
  int? _selectedVertexIndex;

  EditorToolMode _toolMode = EditorToolMode.select;
  SnapSettings _snapSettings = const SnapSettings();

  // Trạng thái vẽ đường gấp khúc đang dựng dở (chưa Hoàn tất)
  String _draftOwnerBallId = 'ball_white';
  PathRole _draftRole = PathRole.ballCenter;
  bool _draftAnchorStart = false;
  final List<DiagramPoint> _draftPoints = [];

  final List<DiagramScene> _undoStack = [];
  final List<DiagramScene> _redoStack = [];

  int _nextDragToken = 1;
  int _nextPathCounter = 1;

  // Giao dịch kéo bi
  int? _activeDragToken;
  String? _draggingBallId;
  DiagramScene? _dragStartSceneSnapshot;
  DiagramPoint? _dragStartCenter;
  DiagramPoint _dragFingerOffset = const DiagramPoint(0.0, 0.0);

  // Giao dịch kéo điểm điều khiển của đường
  int? _activeVertexDragToken;
  String? _draggingVertexPathId;
  int? _draggingVertexIndex;
  DiagramScene? _vertexDragStartSceneSnapshot;
  DiagramPoint? _vertexDragStartPoint;
  DiagramPoint _vertexDragFingerOffset = const DiagramPoint(0.0, 0.0);

  int _authoritativeRevision = 0;

  // Trạng thái lưu/tải sơ đồ
  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;
  String? _saveError;

  TableEditorController({
    DiagramScene? initialScene,
    this.storage,
  })  : _savedBaseline =
            initialScene ?? DiagramScene.defaultInitial(id: 'primary_scene'),
        _scene =
            initialScene ?? DiagramScene.defaultInitial(id: 'primary_scene'),
        _selectedBallId =
            (initialScene?.balls.isNotEmpty ?? true)
                ? (initialScene?.balls.first.id ?? 'ball_white')
                : null {
    _draftOwnerBallId = _selectedBallId ?? 'ball_white';
    _syncPathCounterWithScene(_scene);
  }

  DiagramScene get scene => _scene;
  DiagramScene get savedBaseline => _savedBaseline;
  List<Ball> get balls => _scene.balls;
  List<GuidePath> get paths => _scene.paths;
  SceneViewSettings get viewSettings => _scene.viewSettings;
  SnapSettings get snapSettings => _snapSettings;

  String? get selectedBallId => _selectedBallId;
  String? get selectedPathId => _selectedPathId;
  int? get selectedVertexIndex => _selectedVertexIndex;

  EditorToolMode get toolMode => _toolMode;
  String get draftOwnerBallId => _draftOwnerBallId;
  PathRole get draftRole => _draftRole;
  bool get draftAnchorStart => _draftAnchorStart;
  List<DiagramPoint> get draftPoints =>
      List<DiagramPoint>.unmodifiable(_draftPoints);

  bool get isDraggingBall => _activeDragToken != null;
  bool get isDraggingVertex => _activeVertexDragToken != null;
  bool get isDraggingAny => isDraggingBall || isDraggingVertex;
  bool get isDrawingWithDraft =>
      _toolMode == EditorToolMode.drawPolyline && _draftPoints.isNotEmpty;

  int? get activeDragToken => _activeDragToken;
  int? get activeVertexDragToken => _activeVertexDragToken;
  int get authoritativeRevision => _authoritativeRevision;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;
  String? get saveError => _saveError;

  bool get canUndo =>
      !isDraggingAny && !isDrawingWithDraft && _undoStack.isNotEmpty;
  bool get canRedo =>
      !isDraggingAny && !isDrawingWithDraft && _redoStack.isNotEmpty;

  /// Có thay đổi chưa lưu so với bản đã lưu (hoặc mặc định ban đầu).
  bool get hasUnsavedChanges => _scene != _savedBaseline || isDrawingWithDraft;

  double get currentBallRadius =>
      _scene.balls.isNotEmpty ? _scene.balls.first.radius : 4.0;

  Ball? get selectedBall {
    if (_selectedBallId == null) return null;
    for (final ball in _scene.balls) {
      if (ball.id == _selectedBallId) return ball;
    }
    return null;
  }

  GuidePath? get selectedPath {
    if (_selectedPathId == null) return null;
    for (final path in _scene.paths) {
      if (path.id == _selectedPathId) return path;
    }
    return null;
  }

  /// Danh sách đường đang bị lỗi hình học (ví dụ vượt giới hạn sau khi đổi bán kính
  /// hoặc đoạn độ dài 0 sau khi kéo bi có liên kết).
  Map<String, String> get invalidPathWarnings {
    final map = <String, String>{};
    for (final path in _scene.paths) {
      final err = PathGeometry.validatePath(
        path,
        _scene.balls,
        width: _scene.width,
        height: _scene.height,
      );
      if (err != null) {
        map[path.id] = err;
      }
    }
    return Map<String, String>.unmodifiable(map);
  }

  List<DiagramScene> get undoHistory =>
      List<DiagramScene>.unmodifiable(_undoStack);

  bool get canCompleteDraft {
    if (_draftPoints.length < 2) return false;
    for (var i = 1; i < _draftPoints.length; i++) {
      if (_draftPoints[i].distanceTo(_draftPoints.first) >=
          PathGeometry.minSegmentLength) {
        return true;
      }
    }
    return false;
  }

  void _syncPathCounterWithScene(DiagramScene scene) {
    for (final path in scene.paths) {
      final match = RegExp(r'^path_(\d+)$').firstMatch(path.id);
      if (match != null) {
        final numVal = int.tryParse(match.group(1)!);
        if (numVal != null && numVal >= _nextPathCounter) {
          _nextPathCounter = numVal + 1;
        }
      }
    }
  }

  void _pushUndoSnapshot(DiagramScene previousScene) {
    _undoStack.add(previousScene);
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _authoritativeRevision++;
  }

  // ---------------------------------------------------------------------------
  // Chế độ công cụ & bắt dính
  // ---------------------------------------------------------------------------

  bool setToolMode(EditorToolMode mode) {
    if (isDraggingAny) return false;
    if (_toolMode == mode) return true;
    if (_toolMode == EditorToolMode.drawPolyline &&
        mode != EditorToolMode.drawPolyline) {
      _draftPoints.clear();
    }
    _toolMode = mode;
    if (mode == EditorToolMode.drawPolyline) {
      _selectedPathId = null;
      _selectedVertexIndex = null;
      if (_selectedBallId != null) {
        _draftOwnerBallId = _selectedBallId!;
      }
    }
    notifyListeners();
    return true;
  }

  void updateSnapSettings(SnapSettings settings) {
    if (_snapSettings == settings) return;
    _snapSettings = settings;
    notifyListeners();
  }

  void updateViewSettings(SceneViewSettings settings) {
    if (_scene.viewSettings == settings) return;
    _scene = _scene.copyWith(viewSettings: settings);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Chọn bi & chọn đường
  // ---------------------------------------------------------------------------

  bool selectBall(String? ballId) {
    if (isDraggingAny) return false;
    _selectedBallId = ballId;
    if (ballId != null) {
      _selectedPathId = null;
      _selectedVertexIndex = null;
      _draftOwnerBallId = ballId;
    }
    notifyListeners();
    return true;
  }

  bool selectPath(String? pathId, {int? vertexIndex}) {
    if (isDraggingAny) return false;
    _selectedPathId = pathId;
    _selectedVertexIndex = vertexIndex;
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Vẽ đường thẳng / gấp khúc
  // ---------------------------------------------------------------------------

  void setDraftOwnerBall(String ballId) {
    if (isDraggingAny) return;
    final ball = _findBall(ballId);
    if (ball == null) return;
    _draftOwnerBallId = ballId;
    if (_draftAnchorStart && _draftPoints.isNotEmpty) {
      _draftPoints[0] = ball.center;
    }
    notifyListeners();
  }

  void setDraftRole(PathRole role) {
    if (isDraggingAny) return;
    _draftRole = role;
    notifyListeners();
  }

  void setDraftAnchorStart(bool anchor) {
    if (isDraggingAny) return;
    _draftAnchorStart = anchor;
    if (anchor) {
      final owner = _findBall(_draftOwnerBallId);
      if (owner != null) {
        if (_draftPoints.isEmpty) {
          _draftPoints.add(owner.center);
        } else {
          _draftPoints[0] = owner.center;
        }
      }
    }
    notifyListeners();
  }

  /// Đặt một điểm mới khi đang ở chế độ Vẽ đường thẳng / Gấp khúc.
  DiagramPoint? addDraftPoint(DiagramPoint rawPoint) {
    if (isDraggingAny || _toolMode != EditorToolMode.drawPolyline) return null;
    if (!rawPoint.isFinite) return null;

    final owner = _findBall(_draftOwnerBallId);
    final ownerRadius = owner?.radius ?? currentBallRadius;
    final snapped = PathGeometry.snapPoint(
      rawPoint,
      role: _draftRole,
      ownerRadius: ownerRadius,
      snapSettings: _snapSettings,
      width: _scene.width,
      height: _scene.height,
    );

    if (_draftPoints.isNotEmpty &&
        _draftPoints.last.distanceTo(snapped) < PathGeometry.minSegmentLength) {
      return null;
    }

    _draftPoints.add(snapped);
    notifyListeners();
    return snapped;
  }

  void undoDraftPoint() {
    if (_draftPoints.isEmpty) return;
    _draftPoints.removeLast();
    notifyListeners();
  }

  void cancelDraftPath() {
    _draftPoints.clear();
    _toolMode = EditorToolMode.select;
    notifyListeners();
  }

  /// Hoàn tất đường đang vẽ và đưa vào scene như một bước Undo duy nhất.
  String? completeDraftPath() {
    if (isDraggingAny) {
      return 'Hãy hoàn tất thao tác kéo hiện tại trước.';
    }
    if (!canCompleteDraft) {
      return 'Đường cần ít nhất hai điểm phân biệt.';
    }

    final owner = _findBall(_draftOwnerBallId);
    if (owner == null) {
      return 'Không tìm thấy bi sở hữu.';
    }

    final points = List<DiagramPoint>.from(_draftPoints);
    if (_draftAnchorStart) {
      points[0] = owner.center;
    }

    final newPath = GuidePath(
      id: 'path_${_nextPathCounter++}',
      ownerBallId: owner.id,
      role: _draftRole,
      segments: PathGeometry.buildLineSegments(points),
      arrowMode: ArrowMode.end,
      startAnchorBallId: _draftAnchorStart ? owner.id : null,
    );

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths([..._scene.paths, newPath]);
    _draftPoints.clear();
    _toolMode = EditorToolMode.select;
    _selectedPathId = newPath.id;
    _selectedVertexIndex = points.length - 1;
    notifyListeners();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Giao dịch kéo bi (Phase 1 + cập nhật điểm đầu đường đang liên kết)
  // ---------------------------------------------------------------------------

  int? beginBallDrag(String ballId, {DiagramPoint? touchPoint}) {
    if (isDraggingAny || isDrawingWithDraft) return null;

    final ball = _findBall(ballId);
    if (ball == null) return null;

    _selectedBallId = ballId;
    _selectedPathId = null;
    _selectedVertexIndex = null;
    _draftOwnerBallId = ballId;

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

  void updateBallDragFromTouch(DiagramPoint touchPoint, {int? dragToken}) {
    if (!touchPoint.isFinite) return;
    updateBallDrag(touchPoint + _dragFingerOffset, dragToken: dragToken);
  }

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
    final updatedPaths = _syncAnchoredPaths(
      ballId: ballId,
      newCenter: resolved,
      paths: _scene.paths,
    );
    _scene = _scene.withBallsAndPaths(balls: updatedBalls, paths: updatedPaths);
    notifyListeners();
  }

  bool endBallDrag({int? dragToken}) {
    if (_activeDragToken == null) return false;
    if (dragToken != null && dragToken != _activeDragToken) return false;

    final ballId = _draggingBallId;
    final snapshot = _dragStartSceneSnapshot;
    final startCenter = _dragStartCenter;

    _clearBallDragState();

    if (ballId != null && snapshot != null && startCenter != null) {
      final currentBall = _findBall(ballId);
      if (currentBall != null && currentBall.center != startCenter) {
        _pushUndoSnapshot(snapshot);
      }
    }
    notifyListeners();
    return true;
  }

  bool cancelBallDrag({int? dragToken}) {
    if (_activeDragToken == null) return false;
    if (dragToken != null && dragToken != _activeDragToken) return false;

    final snapshot = _dragStartSceneSnapshot;
    _clearBallDragState();

    if (snapshot != null) {
      _scene = snapshot;
    }
    notifyListeners();
    return true;
  }

  void _clearBallDragState() {
    _activeDragToken = null;
    _draggingBallId = null;
    _dragStartSceneSnapshot = null;
    _dragStartCenter = null;
    _dragFingerOffset = const DiagramPoint(0.0, 0.0);
  }

  // ---------------------------------------------------------------------------
  // Giao dịch kéo điểm điều khiển của đường & chỉnh đường
  // ---------------------------------------------------------------------------

  int? beginVertexDrag(
    String pathId,
    int vertexIndex, {
    DiagramPoint? touchPoint,
    void Function(String message)? onBlocked,
  }) {
    if (isDraggingAny || isDrawingWithDraft) return null;

    final path = _findPath(pathId);
    if (path == null) return null;
    final vertices = PathGeometry.extractVertices(path);
    if (vertexIndex < 0 || vertexIndex >= vertices.length) return null;

    _selectedPathId = pathId;
    _selectedVertexIndex = vertexIndex;

    if (vertexIndex == 0 && path.startAnchorBallId != null) {
      onBlocked?.call(
        'Điểm đầu đang gắn với tâm bi. Hãy gỡ liên kết nếu muốn kéo tách điểm đầu.',
      );
      notifyListeners();
      return null;
    }

    final token = _nextDragToken++;
    _activeVertexDragToken = token;
    _draggingVertexPathId = pathId;
    _draggingVertexIndex = vertexIndex;
    _vertexDragStartSceneSnapshot = _scene;
    _vertexDragStartPoint = vertices[vertexIndex];
    _vertexDragFingerOffset = touchPoint != null
        ? (vertices[vertexIndex] - touchPoint)
        : const DiagramPoint(0.0, 0.0);
    notifyListeners();
    return token;
  }

  void updateVertexDragFromTouch(DiagramPoint touchPoint, {int? dragToken}) {
    if (!touchPoint.isFinite) return;
    updateVertexDrag(touchPoint + _vertexDragFingerOffset, dragToken: dragToken);
  }

  void updateVertexDrag(DiagramPoint desiredPoint, {int? dragToken}) {
    if (_activeVertexDragToken == null) return;
    if (dragToken != null && dragToken != _activeVertexDragToken) return;

    final pathId = _draggingVertexPathId;
    final vertexIdx = _draggingVertexIndex;
    if (pathId == null || vertexIdx == null) return;

    final path = _findPath(pathId);
    if (path == null) return;

    final owner = _findBall(path.ownerBallId);
    final ownerRadius = owner?.radius ?? currentBallRadius;

    final snapped = PathGeometry.snapPoint(
      desiredPoint,
      role: path.role,
      ownerRadius: ownerRadius,
      snapSettings: _snapSettings,
      width: _scene.width,
      height: _scene.height,
    );

    final updatedPath = PathGeometry.updateVertex(path, vertexIdx, snapped);
    if (updatedPath == path) return;

    final updatedPaths = _scene.paths
        .map((p) => p.id == pathId ? updatedPath : p)
        .toList(growable: false);
    _scene = _scene.withPaths(updatedPaths);
    notifyListeners();
  }

  bool endVertexDrag({int? dragToken}) {
    if (_activeVertexDragToken == null) return false;
    if (dragToken != null && dragToken != _activeVertexDragToken) return false;

    final pathId = _draggingVertexPathId;
    final vertexIdx = _draggingVertexIndex;
    final snapshot = _vertexDragStartSceneSnapshot;
    final startPoint = _vertexDragStartPoint;

    _clearVertexDragState();

    if (pathId != null &&
        vertexIdx != null &&
        snapshot != null &&
        startPoint != null) {
      final path = _findPath(pathId);
      if (path != null) {
        final vertices = PathGeometry.extractVertices(path);
        if (vertexIdx < vertices.length && vertices[vertexIdx] != startPoint) {
          _pushUndoSnapshot(snapshot);
        }
      }
    }
    notifyListeners();
    return true;
  }

  bool cancelVertexDrag({int? dragToken}) {
    if (_activeVertexDragToken == null) return false;
    if (dragToken != null && dragToken != _activeVertexDragToken) return false;

    final snapshot = _vertexDragStartSceneSnapshot;
    _clearVertexDragState();

    if (snapshot != null) {
      _scene = snapshot;
    }
    notifyListeners();
    return true;
  }

  void _clearVertexDragState() {
    _activeVertexDragToken = null;
    _draggingVertexPathId = null;
    _draggingVertexIndex = null;
    _vertexDragStartSceneSnapshot = null;
    _vertexDragStartPoint = null;
    _vertexDragFingerOffset = const DiagramPoint(0.0, 0.0);
  }

  /// Chèn thêm một điểm điều khiển tại trung điểm của đoạn [segmentIndex] (hoặc đoạn đang chọn).
  bool insertVertexOnSelectedPath({int? segmentIndex}) {
    if (isDraggingAny || isDrawingWithDraft) return false;
    final path = selectedPath;
    if (path == null) return false;

    final targetSeg = segmentIndex ??
        (_selectedVertexIndex != null
            ? _selectedVertexIndex!.clamp(0, path.segments.length - 1)
            : path.segments.length - 1);

    final updated = PathGeometry.insertMidpointAtSegment(path, targetSeg);
    if (updated == path) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == path.id ? updated : p).toList(),
    );
    _selectedVertexIndex = targetSeg + 1;
    notifyListeners();
    return true;
  }

  /// Xóa điểm đang chọn (nếu đường có > 2 điểm). Trả về thông báo nếu không thể xóa.
  String? deleteSelectedVertex() {
    if (isDraggingAny || isDrawingWithDraft) {
      return 'Đang có thao tác khác chưa hoàn tất.';
    }
    final path = selectedPath;
    if (path == null) return 'Chưa chọn đường nào.';

    final vertices = PathGeometry.extractVertices(path);
    if (vertices.length <= 2) {
      return 'Đường cần ít nhất 2 điểm. Hãy dùng "Xóa đường" để xóa toàn bộ đường.';
    }

    final idx = (_selectedVertexIndex ?? vertices.length - 1)
        .clamp(0, vertices.length - 1);

    if (idx == 0 && path.startAnchorBallId != null) {
      return 'Điểm đầu đang gắn với tâm bi. Hãy gỡ liên kết trước khi xóa điểm đầu.';
    }

    final updated = PathGeometry.removeVertex(path, idx);
    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == path.id ? updated : p).toList(),
    );
    final newLen = PathGeometry.extractVertices(updated).length;
    _selectedVertexIndex = idx.clamp(0, newLen - 1);
    notifyListeners();
    return null;
  }

  bool reverseSelectedPath() {
    if (isDraggingAny || isDrawingWithDraft) return false;
    final path = selectedPath;
    if (path == null) return false;

    final updated = PathGeometry.reversePath(path);
    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == path.id ? updated : p).toList(),
    );
    _selectedVertexIndex = null;
    notifyListeners();
    return true;
  }

  bool deleteSelectedPath() {
    if (isDraggingAny || isDrawingWithDraft) return false;
    final pathId = _selectedPathId;
    if (pathId == null) return false;
    if (_findPath(pathId) == null) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.where((p) => p.id != pathId).toList(growable: false),
    );
    _selectedPathId = null;
    _selectedVertexIndex = null;
    notifyListeners();
    return true;
  }

  bool toggleSelectedPathStartAnchor() {
    if (isDraggingAny || isDrawingWithDraft) return false;
    final path = selectedPath;
    if (path == null) return false;

    late final GuidePath updated;
    if (path.startAnchorBallId != null) {
      updated = path.copyWith(clearStartAnchor: true);
    } else {
      final owner = _findBall(path.ownerBallId);
      if (owner == null) return false;
      final withAnchoredStart = PathGeometry.updateVertex(path, 0, owner.center);
      updated = withAnchoredStart.copyWith(startAnchorBallId: owner.id);
    }

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == path.id ? updated : p).toList(),
    );
    notifyListeners();
    return true;
  }

  bool updateSelectedPathStyle({
    String? ownerBallId,
    PathRole? role,
    bool? isDashed,
    double? strokeWidth,
    ArrowMode? arrowMode,
    int? customColorValue,
    bool clearCustomColor = false,
  }) {
    if (isDraggingAny || isDrawingWithDraft) return false;
    final path = selectedPath;
    if (path == null) return false;

    var updated = path.copyWith(
      ownerBallId: ownerBallId,
      role: role,
      isDashed: isDashed,
      strokeWidth: strokeWidth,
      arrowMode: arrowMode,
      customColorValue: customColorValue,
      clearCustomColor: clearCustomColor,
    );

    if (ownerBallId != null && path.startAnchorBallId != null) {
      final newOwner = _findBall(ownerBallId);
      if (newOwner != null) {
        updated = PathGeometry.updateVertex(updated, 0, newOwner.center)
            .copyWith(startAnchorBallId: newOwner.id);
      }
    }

    if (updated == path) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == path.id ? updated : p).toList(),
    );
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Nhập X/Y, khóa bi, bán kính, đặt lại, Undo/Redo
  // ---------------------------------------------------------------------------

  String? setBallPosition(String ballId, DiagramPoint newCenter) {
    if (isDraggingAny) {
      return 'Đang kéo, hãy thả tay trước khi sửa tọa độ.';
    }
    if (isDrawingWithDraft) {
      return 'Hãy Hoàn tất hoặc Hủy đường đang vẽ trước khi sửa bi.';
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
    final updatedPaths = _syncAnchoredPaths(
      ballId: ballId,
      newCenter: newCenter,
      paths: _scene.paths,
    );
    _scene = _scene.withBallsAndPaths(balls: updatedBalls, paths: updatedPaths);
    notifyListeners();
    return null;
  }

  bool toggleBallLock(String ballId) {
    if (isDraggingAny || isDrawingWithDraft) return false;
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

  /// Kiểm tra bán kính mới với cả bi và các đường hiện có.
  /// Nếu [allowInvalidPaths] == false (mặc định), trả về thông báo nếu đổi bán kính làm
  /// đường bị vượt giới hạn; nếu true, áp dụng bán kính mới và đánh dấu các đường lỗi.
  String? trySetBallRadius(double newRadius, {bool allowInvalidPaths = false}) {
    if (isDraggingAny || isDrawingWithDraft) {
      return 'Hãy hoàn tất thao tác hiện tại trước khi đổi bán kính.';
    }
    final error = BallPlacementValidator.validateLayoutForRadius(
      _scene.balls,
      newRadius,
      width: _scene.width,
      height: _scene.height,
    );
    if (error != null) return error;

    if ((currentBallRadius - newRadius).abs() < 1e-6) return null;

    final updatedBalls = _scene.balls
        .map((b) => b.copyWith(radius: newRadius))
        .toList(growable: false);

    if (!allowInvalidPaths) {
      for (final path in _scene.paths) {
        final pathErr = PathGeometry.validatePath(
          path,
          updatedBalls,
          width: _scene.width,
          height: _scene.height,
        );
        if (pathErr != null) {
          return 'Đổi sang r = ${newRadius.toStringAsFixed(1)} sẽ làm một số đường '
              'vượt giới hạn lòng bàn. Hãy chỉnh lại đường hoặc xác nhận đánh dấu lỗi.';
        }
      }
    }

    _pushUndoSnapshot(_scene);
    _scene = _scene.withBalls(updatedBalls);
    notifyListeners();
    return null;
  }

  bool resetBalls() {
    if (isDraggingAny || isDrawingWithDraft) return false;
    final defaults = DiagramScene.defaultInitial(id: _scene.id).balls;
    if (_ballsEqual(_scene.balls, defaults)) return false;

    _pushUndoSnapshot(_scene);
    var updatedPaths = _scene.paths;
    for (final b in defaults) {
      updatedPaths = _syncAnchoredPaths(
        ballId: b.id,
        newCenter: b.center,
        paths: updatedPaths,
      );
    }
    _scene = _scene.withBallsAndPaths(balls: defaults, paths: updatedPaths);
    notifyListeners();
    return true;
  }

  bool undo() {
    if (!canUndo) return false;
    _redoStack.add(_scene);
    final previous = _undoStack.removeLast();
    _scene = previous.copyWith(viewSettings: _scene.viewSettings);
    if (_selectedPathId != null && _findPath(_selectedPathId!) == null) {
      _selectedPathId = null;
      _selectedVertexIndex = null;
    }
    _authoritativeRevision++;
    notifyListeners();
    return true;
  }

  bool redo() {
    if (!canRedo) return false;
    _undoStack.add(_scene);
    final next = _redoStack.removeLast();
    _scene = next.copyWith(viewSettings: _scene.viewSettings);
    if (_selectedPathId != null && _findPath(_selectedPathId!) == null) {
      _selectedPathId = null;
      _selectedVertexIndex = null;
    }
    _authoritativeRevision++;
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Lưu và tải lại một sơ đồ
  // ---------------------------------------------------------------------------

  Future<String?> loadFromStorage() async {
    final repo = storage;
    if (repo == null) return null;

    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      final loaded = await repo.loadScene();
      if (loaded != null) {
        _savedBaseline = loaded;
        _scene = loaded;
        _syncPathCounterWithScene(loaded);
      } else {
        final fallback = DiagramScene.defaultInitial(id: 'primary_scene');
        _savedBaseline = fallback;
        _scene = fallback;
      }
      _undoStack.clear();
      _redoStack.clear();
      _draftPoints.clear();
      _selectedPathId = null;
      _selectedVertexIndex = null;
      _authoritativeRevision++;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _isLoading = false;
      _loadError = e.toString();
      notifyListeners();
      return _loadError;
    }
  }

  Future<String?> saveToStorage() async {
    final repo = storage;
    if (repo == null) {
      return 'Chưa cấu hình kho lưu trữ.';
    }
    if (isDraggingAny || isDrawingWithDraft) {
      return 'Hãy hoàn tất hoặc hủy thao tác đang vẽ/kéo trước khi lưu.';
    }

    _isSaving = true;
    _saveError = null;
    notifyListeners();

    try {
      await repo.saveScene(_scene);
      _savedBaseline = _scene;
      _isSaving = false;
      notifyListeners();
      return null;
    } catch (e) {
      _isSaving = false;
      _saveError = 'Không thể lưu sơ đồ: $e';
      notifyListeners();
      return _saveError;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<GuidePath> _syncAnchoredPaths({
    required String ballId,
    required DiagramPoint newCenter,
    required List<GuidePath> paths,
  }) {
    var changed = false;
    final next = paths.map((path) {
      if (path.startAnchorBallId != ballId || path.segments.isEmpty) {
        return path;
      }
      if (path.segments.first.start == newCenter) {
        return path;
      }
      changed = true;
      return PathGeometry.updateVertex(path, 0, newCenter);
    }).toList(growable: false);
    return changed ? next : paths;
  }

  Ball? _findBall(String id) {
    for (final ball in _scene.balls) {
      if (ball.id == id) return ball;
    }
    return null;
  }

  GuidePath? _findPath(String id) {
    for (final path in _scene.paths) {
      if (path.id == id) return path;
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
