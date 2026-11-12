import 'package:flutter/foundation.dart';

import '../geometry/annotation_geometry.dart';
import '../geometry/path_geometry.dart';
import '../geometry/table_geometry.dart';
import '../models/models.dart';
import '../repositories/scene_storage.dart';

enum EditorToolMode {
  select('Chọn / Di chuyển'),
  drawPolyline('Vẽ đường'),
  placeAnnotation('Chú thích');

  const EditorToolMode(this.label);
  final String label;
}

enum SaveStatus {
  savedAll,
  savedSnapshotWithNewerEdits,
  rejectedBusy,
  error,
}

class SaveOutcome {
  final SaveStatus status;
  final String message;

  const SaveOutcome(this.status, this.message);

  bool get isSuccess =>
      status == SaveStatus.savedAll ||
      status == SaveStatus.savedSnapshotWithNewerEdits;
}

enum LoadStatus {
  loaded,
  needsConfirmation,
  rejectedBusy,
  error,
}

class LoadOutcome {
  final LoadStatus status;
  final String? message;

  const LoadOutcome(this.status, [this.message]);
}

/// Quản lý trạng thái màn hình Dựng thế bi (Phase 1 + Phase 2):
/// - Hỗ trợ hai chế độ: Chọn/Di chuyển bi & chỉnh đường vs Vẽ đường thẳng/gấp khúc.
/// - Bảo vệ giao dịch kéo bằng `dragToken` và khóa sửa trong lúc đang tải từ kho.
/// - `saveToStorage` chụp snapshot trước khi `await` để phân biệt chỉnh sửa phát sinh sau snapshot.
class TableEditorController extends ChangeNotifier {
  static const int _maxHistory = 100;

  final SceneStorage? storage;
  DiagramScene _savedBaseline;
  DiagramScene _scene;

  String? _selectedBallId;
  String? _selectedPathId;
  int? _selectedVertexIndex;
  int? _selectedSegmentIndex;
  ({int segmentIndex, int handleIndex})? _selectedControlHandle;
  String? _selectedAnnotationId;

  EditorToolMode _toolMode = EditorToolMode.select;
  SnapSettings _snapSettings = const SnapSettings();

  String _draftOwnerBallId = 'ball_white';
  PathRole _draftRole = PathRole.ballCenter;
  bool _draftAnchorStart = false;
  final List<DiagramPoint> _draftPoints = [];
  AnnotationType _draftAnnotationType = AnnotationType.label;

  final List<DiagramScene> _undoStack = [];
  final List<DiagramScene> _redoStack = [];

  int _nextDragToken = 1;
  int _nextPathCounter = 1;
  int _nextAnnotationCounter = 1;

  int? _activeDragToken;
  String? _draggingBallId;
  DiagramScene? _dragStartSceneSnapshot;
  DiagramPoint? _dragStartCenter;
  DiagramPoint _dragFingerOffset = const DiagramPoint(0.0, 0.0);

  int? _activeVertexDragToken;
  String? _draggingVertexPathId;
  int? _draggingVertexIndex;
  DiagramScene? _vertexDragStartSceneSnapshot;
  DiagramPoint? _vertexDragStartPoint;
  DiagramPoint _vertexDragFingerOffset = const DiagramPoint(0.0, 0.0);

  int? _activeControlDragToken;
  String? _draggingControlPathId;
  int? _draggingControlSegIndex;
  int? _draggingControlHandleIndex;
  DiagramScene? _controlDragStartSceneSnapshot;
  DiagramPoint? _controlDragStartPoint;
  DiagramPoint _controlDragFingerOffset = const DiagramPoint(0.0, 0.0);

  int? _activeAnnotationDragToken;
  String? _draggingAnnotationId;
  DiagramScene? _annotationDragStartSceneSnapshot;
  DiagramPoint? _annotationDragStartPoint;
  DiagramPoint _annotationDragFingerOffset = const DiagramPoint(0.0, 0.0);

  int _authoritativeRevision = 0;

  bool _isDisposed = false;
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

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  DiagramScene get scene => _scene;
  DiagramScene get savedBaseline => _savedBaseline;
  List<Ball> get balls => _scene.balls;
  List<GuidePath> get paths => _scene.paths;
  List<DiagramAnnotation> get annotations => _scene.annotations;
  SceneViewSettings get viewSettings => _scene.viewSettings;
  SnapSettings get snapSettings => _snapSettings;

  String? get selectedBallId => _selectedBallId;
  String? get selectedPathId => _selectedPathId;
  int? get selectedVertexIndex => _selectedVertexIndex;
  int? get selectedSegmentIndex => _selectedSegmentIndex;
  ({int segmentIndex, int handleIndex})? get selectedControlHandle =>
      _selectedControlHandle;
  String? get selectedAnnotationId => _selectedAnnotationId;

  EditorToolMode get toolMode => _toolMode;
  String get draftOwnerBallId => _draftOwnerBallId;
  PathRole get draftRole => _draftRole;
  bool get draftAnchorStart => _draftAnchorStart;
  AnnotationType get draftAnnotationType => _draftAnnotationType;
  List<DiagramPoint> get draftPoints =>
      List<DiagramPoint>.unmodifiable(_draftPoints);

  bool get isDraggingBall => _activeDragToken != null;
  bool get isDraggingVertex => _activeVertexDragToken != null;
  bool get isDraggingControlHandle => _activeControlDragToken != null;
  bool get isDraggingAnnotation => _activeAnnotationDragToken != null;
  bool get isDraggingAny =>
      isDraggingBall ||
      isDraggingVertex ||
      isDraggingControlHandle ||
      isDraggingAnnotation;
  bool get isDrawingWithDraft =>
      _toolMode == EditorToolMode.drawPolyline && _draftPoints.isNotEmpty;
  bool get isEditingLocked => _isLoading || isDraggingAny;

  int? get activeDragToken => _activeDragToken;
  int? get activeVertexDragToken => _activeVertexDragToken;
  int? get activeControlDragToken => _activeControlDragToken;
  int? get activeAnnotationDragToken => _activeAnnotationDragToken;
  int get authoritativeRevision => _authoritativeRevision;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;
  String? get saveError => _saveError;

  bool get canUndo =>
      !_isLoading &&
      !isDraggingAny &&
      !isDrawingWithDraft &&
      _undoStack.isNotEmpty;
  bool get canRedo =>
      !_isLoading &&
      !isDraggingAny &&
      !isDrawingWithDraft &&
      _redoStack.isNotEmpty;

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

  int? get effectiveSelectedSegmentIndex {
    final path = selectedPath;
    if (path == null || path.segments.isEmpty) return null;
    if (_selectedSegmentIndex != null &&
        _selectedSegmentIndex! >= 0 &&
        _selectedSegmentIndex! < path.segments.length) {
      return _selectedSegmentIndex;
    }
    if (_selectedControlHandle != null &&
        _selectedControlHandle!.segmentIndex >= 0 &&
        _selectedControlHandle!.segmentIndex < path.segments.length) {
      return _selectedControlHandle!.segmentIndex;
    }
    if (_selectedVertexIndex != null) {
      final candidate = _selectedVertexIndex == 0 ? 0 : _selectedVertexIndex! - 1;
      return candidate.clamp(0, path.segments.length - 1);
    }
    return path.segments.length - 1;
  }

  DiagramAnnotation? get selectedAnnotation {
    if (_selectedAnnotationId == null) return null;
    for (final ann in _scene.annotations) {
      if (ann.id == _selectedAnnotationId) return ann;
    }
    return null;
  }

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
    for (final ann in scene.annotations) {
      final match = RegExp(r'^ann_(\d+)$').firstMatch(ann.id);
      if (match != null) {
        final numVal = int.tryParse(match.group(1)!);
        if (numVal != null && numVal >= _nextAnnotationCounter) {
          _nextAnnotationCounter = numVal + 1;
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

  /// Đổi chế độ công cụ. Không cho phép rời chế độ vẽ khi đang còn đường nháp;
  /// người dùng phải Hoàn tất hoặc Hủy đường nháp trước.
  bool setToolMode(EditorToolMode mode) {
    if (isEditingLocked) return false;
    if (_toolMode == mode) return true;
    if (isDrawingWithDraft && mode != EditorToolMode.drawPolyline) {
      return false;
    }
    _toolMode = mode;
    if (mode != EditorToolMode.select) {
      _selectedPathId = null;
      _selectedVertexIndex = null;
      _selectedSegmentIndex = null;
      _selectedControlHandle = null;
      _selectedAnnotationId = null;
      _selectedSegmentIndex = null;
      _selectedControlHandle = null;
      _selectedAnnotationId = null;
    }
    if (mode == EditorToolMode.drawPolyline && _selectedBallId != null) {
      _draftOwnerBallId = _selectedBallId!;
    }
    _safeNotify();
    return true;
  }

  void setDraftAnnotationType(AnnotationType type) {
    if (isEditingLocked) return;
    _draftAnnotationType = type;
    _safeNotify();
  }

  void updateSnapSettings(SnapSettings settings) {
    if (_isLoading || _snapSettings == settings) return;
    _snapSettings = settings;
    _safeNotify();
  }

  void updateViewSettings(SceneViewSettings settings) {
    if (_isLoading || _scene.viewSettings == settings) return;
    _scene = _scene.copyWith(viewSettings: settings);
    _safeNotify();
  }

  // ---------------------------------------------------------------------------
  // Chọn bi, đường & chú thích
  // ---------------------------------------------------------------------------

  bool selectBall(String? ballId) {
    if (isEditingLocked) return false;
    _selectedBallId = ballId;
    if (ballId != null) {
      _selectedPathId = null;
      _selectedVertexIndex = null;
      _selectedSegmentIndex = null;
      _selectedControlHandle = null;
      _selectedAnnotationId = null;
      _selectedSegmentIndex = null;
      _selectedControlHandle = null;
      _selectedAnnotationId = null;
      _draftOwnerBallId = ballId;
    }
    _safeNotify();
    return true;
  }

  bool selectPath(String? pathId, {int? vertexIndex, int? segmentIndex}) {
    if (isEditingLocked) return false;
    _selectedPathId = pathId;
    _selectedVertexIndex = vertexIndex;
    _selectedSegmentIndex = segmentIndex;
    _selectedControlHandle = null;
    if (pathId != null) {
      _selectedAnnotationId = null;
    }
    _safeNotify();
    return true;
  }

  bool selectSegment(int? segmentIndex) {
    if (isEditingLocked || _selectedPathId == null) return false;
    final path = selectedPath;
    if (path == null) return false;
    if (segmentIndex != null &&
        (segmentIndex < 0 || segmentIndex >= path.segments.length)) {
      return false;
    }
    _selectedSegmentIndex = segmentIndex;
    _selectedControlHandle = null;
    _safeNotify();
    return true;
  }

  bool selectAnnotation(String? annotationId) {
    if (isEditingLocked) return false;
    _selectedAnnotationId = annotationId;
    if (annotationId != null) {
      _selectedPathId = null;
      _selectedVertexIndex = null;
      _selectedSegmentIndex = null;
      _selectedControlHandle = null;
      _selectedAnnotationId = null;
      _selectedSegmentIndex = null;
      _selectedControlHandle = null;
    }
    _safeNotify();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Vẽ đường thẳng / gấp khúc
  // ---------------------------------------------------------------------------

  void setDraftOwnerBall(String ballId) {
    if (isEditingLocked) return;
    final ball = _findBall(ballId);
    if (ball == null) return;
    _draftOwnerBallId = ballId;
    if (_draftAnchorStart && _draftPoints.isNotEmpty) {
      _draftPoints[0] = ball.center;
    }
    _safeNotify();
  }

  void setDraftRole(PathRole role) {
    if (isEditingLocked) return;
    _draftRole = role;
    _safeNotify();
  }

  void setDraftAnchorStart(bool anchor) {
    if (isEditingLocked) return;
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
    _safeNotify();
  }

  DiagramPoint? addDraftPoint(DiagramPoint rawPoint) {
    if (isEditingLocked || _toolMode != EditorToolMode.drawPolyline) {
      return null;
    }
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
    _safeNotify();
    return snapped;
  }

  void undoDraftPoint() {
    if (isEditingLocked || _draftPoints.isEmpty) return;
    _draftPoints.removeLast();
    _safeNotify();
  }

  void cancelDraftPath() {
    if (isEditingLocked) return;
    _draftPoints.clear();
    _toolMode = EditorToolMode.select;
    _safeNotify();
  }

  String? completeDraftPath() {
    if (_isLoading) {
      return 'Đang tải dữ liệu, vui lòng chờ.';
    }
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
    _selectedSegmentIndex = newPath.segments.length - 1;
    _selectedControlHandle = null;
    _selectedAnnotationId = null;
    _safeNotify();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Giao dịch kéo bi
  // ---------------------------------------------------------------------------

  int? beginBallDrag(String ballId, {DiagramPoint? touchPoint}) {
    if (isEditingLocked || isDrawingWithDraft) return null;

    final ball = _findBall(ballId);
    if (ball == null) return null;

    _selectedBallId = ballId;
    _selectedPathId = null;
    _selectedVertexIndex = null;
    _selectedSegmentIndex = null;
    _selectedControlHandle = null;
    _selectedAnnotationId = null;
    _draftOwnerBallId = ballId;

    if (ball.locked) {
      _safeNotify();
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
    _safeNotify();
    return token;
  }

  void updateBallDragFromTouch(DiagramPoint touchPoint, {int? dragToken}) {
    if (!touchPoint.isFinite) return;
    updateBallDrag(touchPoint + _dragFingerOffset, dragToken: dragToken);
  }

  void updateBallDrag(DiagramPoint desiredCenter, {int? dragToken}) {
    if (_isLoading || _activeDragToken == null) return;
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
    _safeNotify();
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
    _safeNotify();
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
    _safeNotify();
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
  // Giao dịch kéo điểm điều khiển & chỉnh đường
  // ---------------------------------------------------------------------------

  int? beginVertexDrag(
    String pathId,
    int vertexIndex, {
    DiagramPoint? touchPoint,
    void Function(String message)? onBlocked,
  }) {
    if (isEditingLocked || isDrawingWithDraft) return null;

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
      _safeNotify();
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
    _safeNotify();
    return token;
  }

  void updateVertexDragFromTouch(DiagramPoint touchPoint, {int? dragToken}) {
    if (!touchPoint.isFinite) return;
    updateVertexDrag(touchPoint + _vertexDragFingerOffset, dragToken: dragToken);
  }

  void updateVertexDrag(DiagramPoint desiredPoint, {int? dragToken}) {
    if (_isLoading || _activeVertexDragToken == null) return;
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
    _safeNotify();
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
    _safeNotify();
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
    _safeNotify();
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

  // ---------------------------------------------------------------------------
  // Giao dịch kéo tay nắm Bézier (control1 / control2)
  // ---------------------------------------------------------------------------

  int? beginControlHandleDrag(
    String pathId,
    int segmentIndex,
    int handleIndex, {
    DiagramPoint? touchPoint,
  }) {
    if (isEditingLocked || isDrawingWithDraft) return null;
    if (handleIndex != 1 && handleIndex != 2) return null;

    final path = _findPath(pathId);
    if (path == null ||
        segmentIndex < 0 ||
        segmentIndex >= path.segments.length) {
      return null;
    }
    final seg = path.segments[segmentIndex];
    if (seg.type != SegmentType.cubic) return null;
    final handlePt = handleIndex == 1 ? seg.control1 : seg.control2;
    if (handlePt == null) return null;

    _selectedPathId = pathId;
    _selectedSegmentIndex = segmentIndex;
    _selectedControlHandle = (segmentIndex: segmentIndex, handleIndex: handleIndex);
    _selectedVertexIndex = null;
    _selectedAnnotationId = null;

    final token = _nextDragToken++;
    _activeControlDragToken = token;
    _draggingControlPathId = pathId;
    _draggingControlSegIndex = segmentIndex;
    _draggingControlHandleIndex = handleIndex;
    _controlDragStartSceneSnapshot = _scene;
    _controlDragStartPoint = handlePt;
    _controlDragFingerOffset = touchPoint != null
        ? (handlePt - touchPoint)
        : const DiagramPoint(0.0, 0.0);
    _safeNotify();
    return token;
  }

  void updateControlHandleDragFromTouch(
    DiagramPoint touchPoint, {
    int? dragToken,
  }) {
    if (!touchPoint.isFinite) return;
    updateControlHandleDrag(
      touchPoint + _controlDragFingerOffset,
      dragToken: dragToken,
    );
  }

  void updateControlHandleDrag(DiagramPoint desiredPoint, {int? dragToken}) {
    if (_isLoading || _activeControlDragToken == null) return;
    if (dragToken != null && dragToken != _activeControlDragToken) return;
    if (!desiredPoint.isFinite) return;

    final pathId = _draggingControlPathId;
    final segIdx = _draggingControlSegIndex;
    final handleIdx = _draggingControlHandleIndex;
    if (pathId == null || segIdx == null || handleIdx == null) return;

    final path = _findPath(pathId);
    if (path == null) return;

    final clamped = PathGeometry.clampHandleToCanvasFrame(desiredPoint);
    final updatedPath = PathGeometry.updateControlHandle(
      path,
      segIdx,
      handleIdx,
      clamped,
    );
    if (updatedPath == path) return;

    _scene = _scene.withPaths(
      _scene.paths
          .map((p) => p.id == pathId ? updatedPath : p)
          .toList(growable: false),
    );
    _safeNotify();
  }

  bool endControlHandleDrag({
    int? dragToken,
    void Function(String warning)? onInvalidPath,
  }) {
    if (_activeControlDragToken == null) return false;
    if (dragToken != null && dragToken != _activeControlDragToken) return false;

    final pathId = _draggingControlPathId;
    final segIdx = _draggingControlSegIndex;
    final handleIdx = _draggingControlHandleIndex;
    final snapshot = _controlDragStartSceneSnapshot;
    final startPoint = _controlDragStartPoint;

    _clearControlHandleDragState();

    if (pathId != null &&
        segIdx != null &&
        handleIdx != null &&
        snapshot != null &&
        startPoint != null) {
      final path = _findPath(pathId);
      if (path != null && segIdx < path.segments.length) {
        final seg = path.segments[segIdx];
        final currentPt = handleIdx == 1 ? seg.control1 : seg.control2;
        if (currentPt != null && currentPt != startPoint) {
          _pushUndoSnapshot(snapshot);
        }
        final err = PathGeometry.validatePath(
          path,
          _scene.balls,
          width: _scene.width,
          height: _scene.height,
        );
        if (err != null) {
          onInvalidPath?.call(err);
        }
      }
    }
    _safeNotify();
    return true;
  }

  bool cancelControlHandleDrag({int? dragToken}) {
    if (_activeControlDragToken == null) return false;
    if (dragToken != null && dragToken != _activeControlDragToken) return false;

    final snapshot = _controlDragStartSceneSnapshot;
    _clearControlHandleDragState();

    if (snapshot != null) {
      _scene = snapshot;
    }
    _safeNotify();
    return true;
  }

  void _clearControlHandleDragState() {
    _activeControlDragToken = null;
    _draggingControlPathId = null;
    _draggingControlSegIndex = null;
    _draggingControlHandleIndex = null;
    _controlDragStartSceneSnapshot = null;
    _controlDragStartPoint = null;
    _controlDragFingerOffset = const DiagramPoint(0.0, 0.0);
  }

  // ---------------------------------------------------------------------------
  // Chuyển kiểu đoạn thẳng / cubic & thao tác trên đường
  // ---------------------------------------------------------------------------

  bool convertSegmentToCubic(String pathId, int segmentIndex) {
    if (isEditingLocked || isDrawingWithDraft) return false;
    final path = _findPath(pathId);
    if (path == null) return false;
    final updated = PathGeometry.convertSegmentToCubic(path, segmentIndex);
    if (updated == path) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == pathId ? updated : p).toList(growable: false),
    );
    _selectedPathId = pathId;
    _selectedSegmentIndex = segmentIndex;
    _safeNotify();
    return true;
  }

  bool convertSegmentToLine(String pathId, int segmentIndex) {
    if (isEditingLocked || isDrawingWithDraft) return false;
    final path = _findPath(pathId);
    if (path == null) return false;
    final updated = PathGeometry.convertSegmentToLine(path, segmentIndex);
    if (updated == path) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == pathId ? updated : p).toList(growable: false),
    );
    _selectedPathId = pathId;
    _selectedSegmentIndex = segmentIndex;
    _selectedControlHandle = null;
    _safeNotify();
    return true;
  }

  bool toggleSelectedSegmentCurveType() {
    final path = selectedPath;
    final segIdx = effectiveSelectedSegmentIndex;
    if (path == null || segIdx == null) return false;
    final seg = path.segments[segIdx];
    if (seg.type == SegmentType.line) {
      return convertSegmentToCubic(path.id, segIdx);
    } else if (seg.type == SegmentType.cubic) {
      return convertSegmentToLine(path.id, segIdx);
    }
    return false;
  }

  bool insertVertexOnSelectedPath({int? segmentIndex, double t = 0.5}) {
    if (isEditingLocked || isDrawingWithDraft) return false;
    final path = selectedPath;
    if (path == null) return false;

    final targetSeg = segmentIndex ?? effectiveSelectedSegmentIndex ?? (path.segments.length - 1);

    final updated =
        PathGeometry.insertMidpointAtSegment(path, targetSeg, t: t);
    if (updated == path) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == path.id ? updated : p).toList(growable: false),
    );
    _selectedVertexIndex = targetSeg + 1;
    _selectedSegmentIndex = targetSeg;
    _selectedControlHandle = null;
    _safeNotify();
    return true;
  }

  String? deleteSelectedVertex() {
    if (_isLoading) return 'Đang tải dữ liệu, vui lòng chờ.';
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

    final res = PathGeometry.tryRemoveVertex(path, idx);
    if (res.error != null || res.path == null) {
      return res.error ?? 'Không thể xóa điểm chọn.';
    }

    final updated = res.path!;
    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == path.id ? updated : p).toList(growable: false),
    );
    final newLen = PathGeometry.extractVertices(updated).length;
    _selectedVertexIndex = idx.clamp(0, newLen - 1);
    _selectedSegmentIndex = updated.segments.isEmpty
        ? null
        : (idx - 1).clamp(0, updated.segments.length - 1);
    _selectedControlHandle = null;
    _safeNotify();
    return null;
  }

  bool reverseSelectedPath() {
    if (isEditingLocked || isDrawingWithDraft) return false;
    final path = selectedPath;
    if (path == null) return false;

    final updated = PathGeometry.reversePath(path);
    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.map((p) => p.id == path.id ? updated : p).toList(growable: false),
    );
    _selectedVertexIndex = null;
    _selectedSegmentIndex = null;
    _selectedControlHandle = null;
    _safeNotify();
    return true;
  }

  bool deleteSelectedPath() {
    if (isEditingLocked || isDrawingWithDraft) return false;
    final pathId = _selectedPathId;
    if (pathId == null) return false;
    if (_findPath(pathId) == null) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withPaths(
      _scene.paths.where((p) => p.id != pathId).toList(growable: false),
    );
    _selectedPathId = null;
    _selectedVertexIndex = null;
    _selectedSegmentIndex = null;
    _selectedControlHandle = null;
    _safeNotify();
    return true;
  }

  bool toggleSelectedPathStartAnchor() {
    if (isEditingLocked || isDrawingWithDraft) return false;
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
    _safeNotify();
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
    if (isEditingLocked || isDrawingWithDraft) return false;
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
    _safeNotify();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Chú thích (Nhãn chữ, số thứ tự, chấm đánh dấu, vùng tròn, vùng chữ nhật)
  // ---------------------------------------------------------------------------

  String _defaultAnnotationText(AnnotationType type) {
    if (type == AnnotationType.label) return 'Nhãn';
    if (type == AnnotationType.sequence) {
      final seqCount = _scene.annotations
          .where((a) => a.type == AnnotationType.sequence)
          .length;
      return '${seqCount + 1}';
    }
    return '';
  }

  DiagramAnnotation? addAnnotation({
    required AnnotationType type,
    required DiagramPoint position,
    String? text,
    double? width,
    double? height,
    double? radius,
    int? colorValue,
    bool isDashed = false,
    double strokeWidth = 1.8,
    void Function(String message)? onRejected,
  }) {
    if (isEditingLocked || isDrawingWithDraft || !position.isFinite) {
      return null;
    }
    if (strokeWidth.isFinite == false || strokeWidth <= 0) return null;

    if (AnnotationGeometry.isRailOnlyType(type) &&
        !AnnotationGeometry.isOnWoodRailBand(
          position,
          width: _scene.width,
          height: _scene.height,
        )) {
      onRejected?.call(
        'Nhãn chữ và Số thứ tự chỉ đặt trên phần dải băng gỗ xung quanh lòng bàn.',
      );
      return null;
    }

    final safeWidth = width ?? DiagramAnnotation.defaultWidthFor(type);
    final safeHeight = height ?? DiagramAnnotation.defaultHeightFor(type);
    final safeRadius = radius ?? DiagramAnnotation.defaultRadiusFor(type);
    if (!safeWidth.isFinite ||
        safeWidth < 0 ||
        !safeHeight.isFinite ||
        safeHeight < 0 ||
        !safeRadius.isFinite ||
        safeRadius < 0) {
      return null;
    }
    if (type == AnnotationType.rectZone && (safeWidth <= 0 || safeHeight <= 0)) {
      return null;
    }
    if ((type == AnnotationType.circleZone || type == AnnotationType.marker) &&
        safeRadius <= 0) {
      return null;
    }

    final clampedPos = AnnotationGeometry.clampPosition(
      position,
      type: type,
      width: _scene.width,
      height: _scene.height,
    );
    final created = DiagramAnnotation(
      id: 'ann_${_nextAnnotationCounter++}',
      type: type,
      position: clampedPos,
      width: safeWidth,
      height: safeHeight,
      radius: safeRadius,
      text: text ?? _defaultAnnotationText(type),
      colorValue: colorValue,
      isDashed: isDashed,
      strokeWidth: strokeWidth,
    );

    _pushUndoSnapshot(_scene);
    _scene = _scene.withAnnotations([..._scene.annotations, created]);
    _selectedAnnotationId = created.id;
    _selectedPathId = null;
    _selectedVertexIndex = null;
    _selectedSegmentIndex = null;
    _selectedControlHandle = null;
    _toolMode = EditorToolMode.select;
    _safeNotify();
    return created;
  }

  int? beginAnnotationDrag(
    String annotationId, {
    DiagramPoint? touchPoint,
    void Function(String message)? onBlocked,
  }) {
    if (isEditingLocked || isDrawingWithDraft) return null;
    final ann = _findAnnotation(annotationId);
    if (ann == null) return null;

    _selectedAnnotationId = annotationId;
    _selectedPathId = null;
    _selectedVertexIndex = null;
    _selectedSegmentIndex = null;
    _selectedControlHandle = null;

    if (ann.locked) {
      onBlocked?.call('Chú thích đang bị khóa. Hãy mở khóa trước khi di chuyển.');
      _safeNotify();
      return null;
    }

    final token = _nextDragToken++;
    _activeAnnotationDragToken = token;
    _draggingAnnotationId = annotationId;
    _annotationDragStartSceneSnapshot = _scene;
    _annotationDragStartPoint = ann.position;
    _annotationDragFingerOffset = touchPoint != null
        ? (ann.position - touchPoint)
        : const DiagramPoint(0.0, 0.0);
    _safeNotify();
    return token;
  }

  void updateAnnotationDragFromTouch(
    DiagramPoint touchPoint, {
    int? dragToken,
  }) {
    if (!touchPoint.isFinite) return;
    updateAnnotationDrag(
      touchPoint + _annotationDragFingerOffset,
      dragToken: dragToken,
    );
  }

  void updateAnnotationDrag(DiagramPoint desiredPos, {int? dragToken}) {
    if (_isLoading || _activeAnnotationDragToken == null) return;
    if (dragToken != null && dragToken != _activeAnnotationDragToken) return;
    if (!desiredPos.isFinite) return;

    final annId = _draggingAnnotationId;
    if (annId == null) return;
    final ann = _findAnnotation(annId);
    if (ann == null || ann.locked) return;

    final clamped = AnnotationGeometry.clampPosition(
      desiredPos,
      type: ann.type,
      width: _scene.width,
      height: _scene.height,
    );
    if (clamped == ann.position) return;

    _scene = _scene.withAnnotations(
      _scene.annotations
          .map((a) => a.id == annId ? a.copyWith(position: clamped) : a)
          .toList(growable: false),
    );
    _safeNotify();
  }

  bool endAnnotationDrag({int? dragToken}) {
    if (_activeAnnotationDragToken == null) return false;
    if (dragToken != null && dragToken != _activeAnnotationDragToken) return false;

    final annId = _draggingAnnotationId;
    final snapshot = _annotationDragStartSceneSnapshot;
    final startPos = _annotationDragStartPoint;

    _clearAnnotationDragState();

    if (annId != null && snapshot != null && startPos != null) {
      final current = _findAnnotation(annId);
      if (current != null && current.position != startPos) {
        _pushUndoSnapshot(snapshot);
      }
    }
    _safeNotify();
    return true;
  }

  bool cancelAnnotationDrag({int? dragToken}) {
    if (_activeAnnotationDragToken == null) return false;
    if (dragToken != null && dragToken != _activeAnnotationDragToken) return false;

    final snapshot = _annotationDragStartSceneSnapshot;
    _clearAnnotationDragState();

    if (snapshot != null) {
      _scene = snapshot;
    }
    _safeNotify();
    return true;
  }

  void _clearAnnotationDragState() {
    _activeAnnotationDragToken = null;
    _draggingAnnotationId = null;
    _annotationDragStartSceneSnapshot = null;
    _annotationDragStartPoint = null;
    _annotationDragFingerOffset = const DiagramPoint(0.0, 0.0);
  }

  String? updateSelectedAnnotation({
    String? text,
    double? width,
    double? height,
    double? radius,
    int? colorValue,
    bool clearColor = false,
    bool? isDashed,
    double? strokeWidth,
  }) {
    if (_isLoading) return 'Đang tải dữ liệu, vui lòng chờ.';
    if (isDraggingAny || isDrawingWithDraft) {
      return 'Hãy hoàn tất thao tác hiện tại trước khi sửa chú thích.';
    }
    final ann = selectedAnnotation;
    if (ann == null) return 'Chưa chọn chú thích nào.';

    final nextW = width ?? ann.width;
    final nextH = height ?? ann.height;
    final nextR = radius ?? ann.radius;
    final nextStroke = strokeWidth ?? ann.strokeWidth;

    if (!nextW.isFinite ||
        nextW < 0 ||
        !nextH.isFinite ||
        nextH < 0 ||
        !nextR.isFinite ||
        nextR < 0) {
      return 'Kích thước chú thích phải là số hữu hạn không âm.';
    }
    if (ann.type == AnnotationType.rectZone && (nextW <= 0 || nextH <= 0)) {
      return 'Chiều rộng và chiều cao vùng chữ nhật phải lớn hơn 0.';
    }
    if ((ann.type == AnnotationType.circleZone ||
            ann.type == AnnotationType.marker) &&
        nextR <= 0) {
      return 'Bán kính chú thích phải lớn hơn 0.';
    }
    if (!nextStroke.isFinite || nextStroke <= 0) {
      return 'Độ dày nét chú thích phải lớn hơn 0.';
    }

    final updated = ann.copyWith(
      text: text,
      width: nextW,
      height: nextH,
      radius: nextR,
      colorValue: colorValue,
      clearColor: clearColor,
      isDashed: isDashed,
      strokeWidth: nextStroke,
    );
    if (updated == ann) return null;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withAnnotations(
      _scene.annotations
          .map((a) => a.id == ann.id ? updated : a)
          .toList(growable: false),
    );
    _safeNotify();
    return null;
  }

  bool toggleAnnotationLock(String annotationId) {
    if (isEditingLocked || isDrawingWithDraft) return false;
    final ann = _findAnnotation(annotationId);
    if (ann == null) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withAnnotations(
      _scene.annotations
          .map((a) => a.id == annotationId ? a.copyWith(locked: !a.locked) : a)
          .toList(growable: false),
    );
    _safeNotify();
    return true;
  }

  bool deleteSelectedAnnotation() {
    if (isEditingLocked || isDrawingWithDraft) return false;
    final annId = _selectedAnnotationId;
    if (annId == null || _findAnnotation(annId) == null) return false;

    _pushUndoSnapshot(_scene);
    _scene = _scene.withAnnotations(
      _scene.annotations
          .where((a) => a.id != annId)
          .toList(growable: false),
    );
    _selectedAnnotationId = null;
    _safeNotify();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Nhập X/Y, khóa bi, bán kính, đặt lại, Undo/Redo
  // ---------------------------------------------------------------------------

  String? setBallPosition(String ballId, DiagramPoint newCenter) {
    if (_isLoading) return 'Đang tải dữ liệu, vui lòng chờ.';
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
    _safeNotify();
    return null;
  }

  bool toggleBallLock(String ballId) {
    if (isEditingLocked || isDrawingWithDraft) return false;
    final ball = _findBall(ballId);
    if (ball == null) return false;

    _pushUndoSnapshot(_scene);
    final updatedBalls = _scene.balls
        .map((b) => b.id == ballId ? b.copyWith(locked: !b.locked) : b)
        .toList(growable: false);
    _scene = _scene.withBalls(updatedBalls);
    _safeNotify();
    return true;
  }

  String? trySetBallRadius(double newRadius, {bool allowInvalidPaths = false}) {
    if (_isLoading) return 'Đang tải dữ liệu, vui lòng chờ.';
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
    _safeNotify();
    return null;
  }

  bool resetBalls() {
    if (isEditingLocked || isDrawingWithDraft) return false;
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
    _safeNotify();
    return true;
  }

  bool undo() {
    if (!canUndo) return false;
    _redoStack.add(_scene);
    final previous = _undoStack.removeLast();
    _scene = previous.copyWith(viewSettings: _scene.viewSettings);
    _normalizeSelectionAfterSceneSwap();
    _authoritativeRevision++;
    _safeNotify();
    return true;
  }

  bool redo() {
    if (!canRedo) return false;
    _undoStack.add(_scene);
    final next = _redoStack.removeLast();
    _scene = next.copyWith(viewSettings: _scene.viewSettings);
    _normalizeSelectionAfterSceneSwap();
    _authoritativeRevision++;
    _safeNotify();
    return true;
  }

  void _normalizeSelectionAfterSceneSwap() {
    if (_selectedPathId != null) {
      final found = _findPath(_selectedPathId!);
      if (found == null) {
        _selectedPathId = null;
        _selectedVertexIndex = null;
        _selectedSegmentIndex = null;
        _selectedControlHandle = null;
      } else {
        if (_selectedSegmentIndex != null &&
            _selectedSegmentIndex! >= found.segments.length) {
          _selectedSegmentIndex = found.segments.length - 1;
        }
        _selectedControlHandle = null;
      }
    }
    if (_selectedAnnotationId != null &&
        _findAnnotation(_selectedAnnotationId!) == null) {
      _selectedAnnotationId = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Lưu và tải bất đồng bộ an toàn
  // ---------------------------------------------------------------------------

  /// Tải sơ đồ từ kho lưu trữ.
  /// - Khóa thao tác chỉnh sửa trong suốt quá trình tải.
  /// - Nếu [force] == false và đang có thay đổi chưa lưu, trả về `needsConfirmation`
  ///   và không ghi đè dữ liệu đang chỉnh.
  /// - Nếu tải lỗi, giữ nguyên toàn bộ trạng thái hiện tại.
  Future<LoadOutcome> loadFromStorage({bool force = false}) async {
    final repo = storage;
    if (repo == null) {
      return const LoadOutcome(LoadStatus.loaded);
    }
    if (_isLoading || _isSaving || isDraggingAny) {
      return const LoadOutcome(
        LoadStatus.rejectedBusy,
        'Đang bận thao tác khác, chưa thể tải lại.',
      );
    }
    if (!force && hasUnsavedChanges) {
      return const LoadOutcome(
        LoadStatus.needsConfirmation,
        'Đang có thay đổi chưa lưu.',
      );
    }

    _isLoading = true;
    _loadError = null;
    _safeNotify();

    try {
      final loaded = await repo.loadScene();
      if (_isDisposed) {
        _isLoading = false;
        return const LoadOutcome(LoadStatus.loaded);
      }

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
      _selectedSegmentIndex = null;
      _selectedControlHandle = null;
      _selectedAnnotationId = null;
      _authoritativeRevision++;
      _isLoading = false;
      _safeNotify();
      return const LoadOutcome(LoadStatus.loaded);
    } catch (e) {
      _isLoading = false;
      _loadError = e.toString();
      _safeNotify();
      return LoadOutcome(LoadStatus.error, _loadError);
    }
  }

  /// Lưu sơ đồ với snapshot cố định được chụp trước khi `await`:
  /// - Không nhận hai yêu cầu lưu đồng thời.
  /// - Khi thành công chỉ cập nhật `savedBaseline = snapshotToSave`.
  /// - Nếu có chỉnh sửa mới trong lúc đang lưu, `hasUnsavedChanges` vẫn giữ `true`
  ///   và không báo đã lưu toàn bộ.
  Future<SaveOutcome> saveToStorage() async {
    final repo = storage;
    if (repo == null) {
      return const SaveOutcome(
        SaveStatus.error,
        'Chưa cấu hình kho lưu trữ.',
      );
    }
    if (_isSaving) {
      return const SaveOutcome(
        SaveStatus.rejectedBusy,
        'Đang lưu sơ đồ, vui lòng chờ.',
      );
    }
    if (_isLoading || isDraggingAny || isDrawingWithDraft) {
      return const SaveOutcome(
        SaveStatus.rejectedBusy,
        'Hãy hoàn tất thao tác hiện tại trước khi lưu.',
      );
    }

    final snapshotToSave = _scene;
    _isSaving = true;
    _saveError = null;
    _safeNotify();

    try {
      await repo.saveScene(snapshotToSave);
      _savedBaseline = snapshotToSave;
      _isSaving = false;

      if (_isDisposed) {
        return const SaveOutcome(SaveStatus.savedAll, 'Đã lưu sơ đồ');
      }

      if (_scene == _savedBaseline) {
        _safeNotify();
        return const SaveOutcome(SaveStatus.savedAll, 'Đã lưu sơ đồ');
      } else {
        _safeNotify();
        return const SaveOutcome(
          SaveStatus.savedSnapshotWithNewerEdits,
          'Đã lưu bản trước đó; vẫn còn thay đổi mới chưa lưu.',
        );
      }
    } catch (e) {
      _isSaving = false;
      _saveError = 'Không thể lưu sơ đồ: $e';
      _safeNotify();
      return SaveOutcome(SaveStatus.error, _saveError!);
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

  DiagramAnnotation? _findAnnotation(String id) {
    for (final ann in _scene.annotations) {
      if (ann.id == id) return ann;
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
