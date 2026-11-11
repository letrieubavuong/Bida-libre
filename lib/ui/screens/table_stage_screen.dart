import 'package:flutter/material.dart';

import '../../geometry/path_geometry.dart';
import '../../geometry/table_constants.dart';
import '../../models/models.dart';
import '../../repositories/scene_storage.dart';
import '../../state/table_editor_controller.dart';
import '../widgets/billiard_table_canvas.dart';

/// Màn hình Dựng thế bi (Phase 1 + Phase 2):
/// - Hỗ trợ đặt/kéo 3 bi, nhập tọa độ X/Y bảo toàn độ chính xác, khóa bi.
/// - Hỗ trợ vẽ đường thẳng/gấp khúc, chỉnh điểm, đổi màu/nét/mũi tên, gắn điểm đầu với bi.
/// - Lưu và mở lại một sơ đồ vào thư mục dữ liệu bền vững của ứng dụng.
class TableStageScreen extends StatefulWidget {
  final TableEditorController? controller;
  final SceneStorage? storage;

  const TableStageScreen({
    super.key,
    this.controller,
    this.storage,
  });

  @override
  State<TableStageScreen> createState() => _TableStageScreenState();
}

class _TableStageScreenState extends State<TableStageScreen> {
  late final TableEditorController _controller;
  late final bool _ownsController;

  final TextEditingController _xController = TextEditingController();
  final TextEditingController _yController = TextEditingController();
  final FocusNode _xFocus = FocusNode();
  final FocusNode _yFocus = FocusNode();

  String? _coordinateError;
  String? _lastSyncedBallId;
  DiagramPoint? _lastSyncedCenter;
  int _lastAuthoritativeRevision = -1;

  String _syncedXText = '';
  String _syncedYText = '';
  bool _xDirty = false;
  bool _yDirty = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        TableEditorController(
          storage: widget.storage ?? FileSceneStorage(),
        );
    _controller.addListener(_onControllerChanged);
    _syncCoordinateFields(force: true);
    if (_ownsController) {
      _controller.loadFromStorage();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _xController.dispose();
    _yController.dispose();
    _xFocus.dispose();
    _yFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _syncCoordinateFields();
    if (mounted) {
      setState(() {});
    }
  }

  void _syncCoordinateFields({bool force = false}) {
    final ball = _controller.selectedBall;
    if (ball == null) return;

    final ballChanged = ball.id != _lastSyncedBallId;
    final revisionChanged =
        _controller.authoritativeRevision != _lastAuthoritativeRevision;
    final posChangedDuringDragOrCancel =
        ball.center != _lastSyncedCenter && (!_xDirty && !_yDirty);

    if (force ||
        ballChanged ||
        revisionChanged ||
        _controller.isDraggingBall ||
        posChangedDuringDragOrCancel) {
      if ((ballChanged || revisionChanged) &&
          (_xFocus.hasFocus || _yFocus.hasFocus)) {
        _xFocus.unfocus();
        _yFocus.unfocus();
      }
      _syncedXText = _formatCoord(ball.center.x);
      _syncedYText = _formatCoord(ball.center.y);
      _xController.value = TextEditingValue(
        text: _syncedXText,
        selection: TextSelection.collapsed(offset: _syncedXText.length),
      );
      _yController.value = TextEditingValue(
        text: _syncedYText,
        selection: TextSelection.collapsed(offset: _syncedYText.length),
      );
      _xDirty = false;
      _yDirty = false;
      _lastSyncedBallId = ball.id;
      _lastSyncedCenter = ball.center;
      _lastAuthoritativeRevision = _controller.authoritativeRevision;
      if (force ||
          ballChanged ||
          revisionChanged ||
          _controller.isDraggingBall) {
        _coordinateError = null;
      }
    }
  }

  String _formatCoord(double v) {
    var fixed = v.toStringAsFixed(3);
    if (fixed.contains('.')) {
      fixed = fixed.replaceFirst(RegExp(r'0+$'), '');
      fixed = fixed.replaceFirst(RegExp(r'\.$'), '');
    }
    return fixed == '-0' ? '0' : fixed;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _saveScene() async {
    final err = await _controller.saveToStorage();
    if (!mounted) return;
    if (err == null) {
      _showSnack('Đã lưu sơ đồ');
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lỗi lưu sơ đồ'),
          content: Text(
            '$err\n\nBản đang chỉnh vẫn được giữ lại để bạn thử lại.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _saveScene();
              },
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _confirmDiscardAndExit() async {
    if (_controller.isDraggingAny) return;
    if (!_controller.hasUnsavedChanges) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thay đổi chưa được lưu'),
        content: const Text(
          'Bạn có muốn bỏ các thay đổi trên bàn dựng hiện tại và thoát không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tiếp tục chỉnh sửa'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ thay đổi'),
          ),
        ],
      ),
    );

    if (shouldDiscard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _applyManualCoordinates() {
    if (_controller.isDraggingAny || _controller.isDrawingWithDraft) return;
    final ball = _controller.selectedBall;
    if (ball == null) return;

    if (ball.locked) {
      setState(() {
        _coordinateError =
            '${ball.color.label} đang bị khóa. Hãy mở khóa trước khi sửa tọa độ.';
      });
      return;
    }

    if (!_xDirty && !_yDirty) {
      FocusScope.of(context).unfocus();
      setState(() {
        _coordinateError = null;
      });
      return;
    }

    double nextX = ball.center.x;
    double nextY = ball.center.y;

    if (_xDirty) {
      final rawX = _xController.text.trim().replaceAll(',', '.');
      final parsedX = double.tryParse(rawX);
      if (parsedX == null || !parsedX.isFinite) {
        setState(() {
          _coordinateError = 'Vui lòng nhập số hữu hạn hợp lệ cho X.';
        });
        return;
      }
      nextX = parsedX;
    }

    if (_yDirty) {
      final rawY = _yController.text.trim().replaceAll(',', '.');
      final parsedY = double.tryParse(rawY);
      if (parsedY == null || !parsedY.isFinite) {
        setState(() {
          _coordinateError = 'Vui lòng nhập số hữu hạn hợp lệ cho Y.';
        });
        return;
      }
      nextY = parsedY;
    }

    final error = _controller.setBallPosition(
      ball.id,
      DiagramPoint(nextX, nextY),
    );
    if (error != null) {
      setState(() {
        _coordinateError = error;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _coordinateError = null;
    });
    _syncCoordinateFields(force: true);
  }

  void _showDisplaySettingsSheet() {
    if (_controller.isDraggingAny || _controller.isDrawingWithDraft) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final view = _controller.viewSettings;
            final snap = _controller.snapSettings;
            final currentR = _controller.currentBallRadius;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hiển thị & Bắt dính',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8.0),
                    SwitchListTile(
                      title: const Text('Hiển thị lưới'),
                      value: view.showGrid,
                      onChanged: (v) => _controller.updateViewSettings(
                        view.copyWith(showGrid: v),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Hiển thị nút diamond'),
                      value: view.showDiamonds,
                      onChanged: (v) => _controller.updateViewSettings(
                        view.copyWith(showDiamonds: v),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Hiển thị số diamond'),
                      value: view.showDiamondNumbers,
                      onChanged: (v) => _controller.updateViewSettings(
                        view.copyWith(showDiamondNumbers: v),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Hiển thị số trên bi (1/2/3)'),
                      value: view.showBallNumbers,
                      onChanged: (v) => _controller.updateViewSettings(
                        view.copyWith(showBallNumbers: v),
                      ),
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('Bắt dính theo lưới'),
                      value: snap.snapToGrid,
                      onChanged: (v) => _controller.updateSnapSettings(
                        snap.copyWith(snapToGrid: v),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Bắt dính đường giới hạn sát băng'),
                      subtitle: const Text('Cách mép lòng bàn đúng bán kính r'),
                      value: snap.snapToRailLimit,
                      onChanged: (v) => _controller.updateSnapSettings(
                        snap.copyWith(snapToRailLimit: v),
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'Bán kính bi (đơn vị sơ đồ): r = ${currentR.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Wrap(
                        spacing: 8.0,
                        children: [3.0, 4.0, 5.0, 6.0].map((r) {
                          final selected = (currentR - r).abs() < 0.01;
                          return ChoiceChip(
                            label: Text('r = ${r.toStringAsFixed(0)}'),
                            selected: selected,
                            onSelected: _controller.isDraggingAny
                                ? null
                                : (_) async {
                                    final err = _controller.trySetBallRadius(r);
                                    if (err == null) return;
                                    if (err.contains('đánh dấu lỗi')) {
                                      final proceed = await showDialog<bool>(
                                        context: context,
                                        builder: (dlgCtx) => AlertDialog(
                                          title: const Text(
                                              'Đường vượt giới hạn'),
                                          content: Text(err),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(dlgCtx)
                                                      .pop(false),
                                              child: const Text('Hủy'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(dlgCtx)
                                                      .pop(true),
                                              child: const Text(
                                                  'Vẫn đổi & đánh dấu'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (proceed == true) {
                                        _controller.trySetBallRadius(
                                          r,
                                          allowInvalidPaths: true,
                                        );
                                      }
                                    } else {
                                      _showSnack(err);
                                    }
                                  },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPathStyleSheet() {
    if (_controller.selectedPath == null || _controller.isDraggingAny) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final path = _controller.selectedPath;
            if (path == null) {
              return const SizedBox.shrink();
            }

            final colorChoices = <(String, int?)>[
              ('Theo bi', null),
              ('Trắng', 0xFFFFFFFF),
              ('Vàng', 0xFFFFE082),
              ('Đỏ', 0xFFFF6E6E),
              ('Ngọc', 0xFF80DEEA),
              ('Cam', 0xFFFFB74D),
            ];

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kiểu hiển thị đường',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      'Bi sở hữu',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6.0),
                    Wrap(
                      spacing: 6.0,
                      children: _controller.balls.map((b) {
                        return ChoiceChip(
                          avatar: _BallDot(color: b.color),
                          label: Text(b.color.label),
                          selected: path.ownerBallId == b.id,
                          onSelected: (_) => _controller.updateSelectedPathStyle(
                            ownerBallId: b.id,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      'Màu đường',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6.0),
                    Wrap(
                      spacing: 6.0,
                      children: colorChoices.map((entry) {
                        final label = entry.$1;
                        final colorVal = entry.$2;
                        final isSelected = colorVal == null
                            ? path.customColorValue == null
                            : path.customColorValue == colorVal;
                        return ChoiceChip(
                          avatar: colorVal == null
                              ? null
                              : Container(
                                  width: 14.0,
                                  height: 14.0,
                                  decoration: BoxDecoration(
                                    color: Color(colorVal),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black38),
                                  ),
                                ),
                          label: Text(label),
                          selected: isSelected,
                          onSelected: (_) => _controller.updateSelectedPathStyle(
                            customColorValue: colorVal,
                            clearCustomColor: colorVal == null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      'Độ dày nét',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6.0),
                    Wrap(
                      spacing: 6.0,
                      children: [
                        ('Mảnh', 1.5),
                        ('Vừa', 2.2),
                        ('Đậm', 3.4),
                      ].map((entry) {
                        final selected =
                            (path.strokeWidth - entry.$2).abs() < 0.2;
                        return ChoiceChip(
                          label: Text(entry.$1),
                          selected: selected,
                          onSelected: (_) => _controller.updateSelectedPathStyle(
                            strokeWidth: entry.$2,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8.0),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Nét đứt'),
                      value: path.isDashed,
                      onChanged: (v) => _controller.updateSelectedPathStyle(
                        isDashed: v,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mũi tên cuối đường'),
                      value: path.arrowMode == ArrowMode.end,
                      onChanged: (v) => _controller.updateSelectedPathStyle(
                        arrowMode: v ? ArrowMode.end : ArrowMode.none,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Đường phụ minh họa'),
                      subtitle: const Text(
                        'Đường chính (tắt) bị giới hạn trong vùng tâm bi [r, W-r] × [r, H-r]',
                      ),
                      value: path.role == PathRole.auxiliary,
                      onChanged: (v) => _controller.updateSelectedPathStyle(
                        role: v ? PathRole.auxiliary : PathRole.ballCenter,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final busy = _controller.isDraggingAny || _controller.isDrawingWithDraft;

    return PopScope(
      canPop: !_controller.isDraggingAny && !_controller.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_controller.isDraggingAny) {
          _confirmDiscardAndExit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0.0,
          leading: IconButton(
            tooltip: 'Quay lại',
            icon: const Icon(Icons.arrow_back),
            onPressed: _controller.isDraggingAny ? null : _confirmDiscardAndExit,
          ),
          title: const Text(
            'Dựng thế bi',
            style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              key: const Key('undo_button'),
              tooltip: 'Hoàn tác',
              icon: const Icon(Icons.undo),
              onPressed: _controller.canUndo ? _controller.undo : null,
            ),
            IconButton(
              key: const Key('redo_button'),
              tooltip: 'Làm lại',
              icon: const Icon(Icons.redo),
              onPressed: _controller.canRedo ? _controller.redo : null,
            ),
            IconButton(
              key: const Key('save_scene_button'),
              tooltip: 'Lưu sơ đồ',
              icon: _controller.isSaving
                  ? const SizedBox(
                      width: 20.0,
                      height: 20.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    )
                  : const Icon(Icons.save_outlined),
              onPressed: (busy || _controller.isSaving) ? null : _saveScene,
            ),
            IconButton(
              key: const Key('reset_button'),
              tooltip: 'Đặt lại',
              icon: const Icon(Icons.restart_alt),
              onPressed: busy ? null : _controller.resetBalls,
            ),
            IconButton(
              key: const Key('display_settings_button'),
              tooltip: 'Hiển thị bàn',
              icon: const Icon(Icons.tune),
              onPressed: busy ? null : _showDisplaySettingsSheet,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_controller.isLoading)
                const LinearProgressIndicator(minHeight: 2.0),
              Expanded(
                child: isLandscape
                    ? _buildLandscapeBody(context)
                    : _buildPortraitBody(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitBody(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      children: [
        if (_controller.loadError != null)
          MaterialBanner(
            content: Text('Lỗi tải sơ đồ: ${_controller.loadError}'),
            actions: [
              TextButton(
                onPressed: _controller.loadFromStorage,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        Expanded(
          child: _buildTableArea(context),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: keyboardOpen ? 210.0 : 300.0,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 12.0),
            child: _buildControlPanel(context, compact: keyboardOpen),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeBody(BuildContext context) {
    final totalWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = (totalWidth * 0.45).clamp(320.0, 430.0);
    return Row(
      children: [
        Expanded(
          child: _buildTableArea(context),
        ),
        SizedBox(
          width: panelWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: _buildControlPanel(context, compact: false),
          ),
        ),
      ],
    );
  }

  Widget _buildTableArea(BuildContext context) {
    final invalidIds = _controller.invalidPathWarnings.keys.toSet();
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Center(
        child: BilliardTableCanvas(
          key: const Key('billiard_table_canvas'),
          scene: _controller.scene,
          toolMode: _controller.toolMode,
          selectedBallId: _controller.selectedBallId,
          selectedPathId: _controller.selectedPathId,
          selectedVertexIndex: _controller.selectedVertexIndex,
          invalidPathIds: invalidIds,
          draftPoints: _controller.draftPoints,
          draftOwnerBallId: _controller.draftOwnerBallId,
          draftRole: _controller.draftRole,
          snapSettings: _controller.snapSettings,
          onBallTapped: _controller.selectBall,
          onPathTapped: (pathId) => _controller.selectPath(pathId),
          onBallDragStart: (ballId, touchPoint) {
            if (_xFocus.hasFocus || _yFocus.hasFocus) {
              _xFocus.unfocus();
              _yFocus.unfocus();
            }
            return _controller.beginBallDrag(ballId, touchPoint: touchPoint);
          },
          onBallDragUpdateFromTouch: (touchPoint, dragToken) =>
              _controller.updateBallDragFromTouch(
            touchPoint,
            dragToken: dragToken,
          ),
          onBallDragEnd: (dragToken) =>
              _controller.endBallDrag(dragToken: dragToken),
          onBallDragCancel: (dragToken) =>
              _controller.cancelBallDrag(dragToken: dragToken),
          onLockedBallTouched: (ball) {
            _showSnack('${ball.color.label} đang bị khóa vị trí.');
          },
          onVertexDragStart: (pathId, vertexIndex, touchPoint) {
            return _controller.beginVertexDrag(
              pathId,
              vertexIndex,
              touchPoint: touchPoint,
              onBlocked: _showSnack,
            );
          },
          onVertexDragUpdateFromTouch: (touchPoint, dragToken) =>
              _controller.updateVertexDragFromTouch(
            touchPoint,
            dragToken: dragToken,
          ),
          onVertexDragEnd: (dragToken) =>
              _controller.endVertexDrag(dragToken: dragToken),
          onVertexDragCancel: (dragToken) =>
              _controller.cancelVertexDrag(dragToken: dragToken),
          onDrawPointPlaced: _controller.addDraftPoint,
        ),
      ),
    );
  }

  Widget _buildControlPanel(BuildContext context, {required bool compact}) {
    final dragging = _controller.isDraggingAny;
    final warnings = _controller.invalidPathWarnings;
    final selectedPath = _controller.selectedPath;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (warnings.isNotEmpty) ...[
              Container(
                key: const Key('invalid_path_warning_banner'),
                padding: const EdgeInsets.all(8.0),
                margin: const EdgeInsets.only(bottom: 8.0),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.orangeAccent),
                ),
                child: Text(
                  warnings.values.first,
                  style: const TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            // Thanh chuyển chế độ công cụ: Chọn / Di chuyển bi <-> Vẽ đường
            if (!compact) ...[
              Wrap(
                spacing: 8.0,
                runSpacing: 6.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    key: const Key('mode_select_chip'),
                    avatar: const Icon(Icons.pan_tool_alt_outlined, size: 16.0),
                    label: const Text('Chọn / Di chuyển'),
                    selected: _controller.toolMode == EditorToolMode.select,
                    onSelected: dragging
                        ? null
                        : (_) => _controller.setToolMode(EditorToolMode.select),
                  ),
                  ChoiceChip(
                    key: const Key('mode_draw_chip'),
                    avatar: const Icon(Icons.timeline, size: 16.0),
                    label: const Text('Vẽ đường'),
                    selected:
                        _controller.toolMode == EditorToolMode.drawPolyline,
                    onSelected: dragging
                        ? null
                        : (_) =>
                            _controller.setToolMode(EditorToolMode.drawPolyline),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
            ],
            if (_controller.toolMode == EditorToolMode.drawPolyline)
              _buildDrawPolylinePanel(context)
            else if (selectedPath != null && !compact)
              _buildSelectedPathPanel(context, selectedPath)
            else
              _buildBallControlPanel(context, compact: compact),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawPolylinePanel(BuildContext context) {
    final pointCount = _controller.draftPoints.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          children: [
            for (final ball in _controller.balls)
              ChoiceChip(
                key: Key('draw_owner_${ball.id}'),
                avatar: _BallDot(color: ball.color),
                label: Text(ball.color.label),
                selected: _controller.draftOwnerBallId == ball.id,
                onSelected: (_) => _controller.setDraftOwnerBall(ball.id),
              ),
          ],
        ),
        const SizedBox(height: 8.0),
        Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          children: [
            FilterChip(
              key: const Key('draft_anchor_chip'),
              label: const Text('Gắn điểm đầu với bi'),
              selected: _controller.draftAnchorStart,
              onSelected: _controller.setDraftAnchorStart,
            ),
            FilterChip(
              key: const Key('draft_aux_chip'),
              label: const Text('Đường phụ'),
              selected: _controller.draftRole == PathRole.auxiliary,
              onSelected: (v) => _controller.setDraftRole(
                v ? PathRole.auxiliary : PathRole.ballCenter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('undo_draft_point_button'),
                onPressed:
                    pointCount > 0 ? _controller.undoDraftPoint : null,
                icon: const Icon(Icons.backspace_outlined, size: 18.0),
                label: Text('Lùi ($pointCount)'),
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: OutlinedButton(
                key: const Key('cancel_draft_path_button'),
                onPressed: _controller.cancelDraftPath,
                child: const Text('Hủy đường'),
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: FilledButton(
                key: const Key('complete_draft_path_button'),
                onPressed: _controller.canCompleteDraft
                    ? () {
                        final err = _controller.completeDraftPath();
                        if (err != null) _showSnack(err);
                      }
                    : null,
                child: const Text('Hoàn tất'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedPathPanel(BuildContext context, GuidePath path) {
    final dragging = _controller.isDraggingAny;
    final vertices = PathGeometry.extractVertices(path);
    final ownerBall = _controller.balls
        .where((b) => b.id == path.ownerBallId)
        .firstOrNull;
    final isAnchored = path.startAnchorBallId != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (ownerBall != null) ...[
              _BallDot(color: ownerBall.color),
              const SizedBox(width: 6.0),
            ],
            Expanded(
              child: Text(
                '${path.role.label} • ${vertices.length} điểm',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            TextButton(
              onPressed:
                  dragging ? null : () => _controller.selectPath(null),
              child: const Text('Xong'),
            ),
          ],
        ),
        const SizedBox(height: 6.0),
        Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          children: [
            FilterChip(
              key: const Key('toggle_anchor_button'),
              label: Text(
                isAnchored ? 'Đang gắn tâm bi' : 'Gắn điểm đầu với bi',
              ),
              selected: isAnchored,
              onSelected: dragging
                  ? null
                  : (_) => _controller.toggleSelectedPathStartAnchor(),
            ),
            ActionChip(
              key: const Key('insert_vertex_button'),
              avatar: const Icon(Icons.add_circle_outline, size: 16.0),
              label: const Text('Chèn điểm'),
              onPressed: dragging
                  ? null
                  : () => _controller.insertVertexOnSelectedPath(),
            ),
            ActionChip(
              key: const Key('delete_vertex_button'),
              avatar: const Icon(Icons.remove_circle_outline, size: 16.0),
              label: const Text('Xóa điểm'),
              onPressed: dragging
                  ? null
                  : () {
                      final err = _controller.deleteSelectedVertex();
                      if (err != null) _showSnack(err);
                    },
            ),
            ActionChip(
              key: const Key('reverse_path_button'),
              avatar: const Icon(Icons.swap_horiz, size: 16.0),
              label: const Text('Đảo chiều'),
              onPressed:
                  dragging ? null : _controller.reverseSelectedPath,
            ),
            ActionChip(
              key: const Key('path_style_button'),
              avatar: const Icon(Icons.palette_outlined, size: 16.0),
              label: const Text('Kiểu nét'),
              onPressed: dragging ? null : _showPathStyleSheet,
            ),
            ActionChip(
              key: const Key('delete_path_button'),
              avatar: const Icon(Icons.delete_outline, size: 16.0),
              label: const Text('Xóa đường'),
              onPressed:
                  dragging ? null : _controller.deleteSelectedPath,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBallControlPanel(BuildContext context, {required bool compact}) {
    final selected = _controller.selectedBall;
    final view = _controller.viewSettings;
    final r = selected?.radius ?? TableConstants.defaultBallRadius;
    final dragging = _controller.isDraggingAny;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6.0,
          runSpacing: 6.0,
          children: [
            for (final ball in _controller.balls)
              ChoiceChip(
                key: Key('select_${ball.id}'),
                avatar: _BallDot(color: ball.color),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ball.color.label),
                    if (ball.locked) ...[
                      const SizedBox(width: 4.0),
                      const Icon(Icons.lock, size: 14.0),
                    ],
                  ],
                ),
                selected: ball.id == _controller.selectedBallId,
                onSelected: dragging
                    ? null
                    : (_) => _controller.selectBall(ball.id),
              ),
          ],
        ),
        const SizedBox(height: 8.0),
        if (selected != null) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('coord_x_input'),
                  controller: _xController,
                  focusNode: _xFocus,
                  enabled: !selected.locked && !dragging,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'X (${r.toStringAsFixed(0)}..${(TableConstants.playfieldWidth - r).toStringAsFixed(0)})',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    _xDirty = value != _syncedXText;
                  },
                  onSubmitted: (_) => _applyManualCoordinates(),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: TextField(
                  key: const Key('coord_y_input'),
                  controller: _yController,
                  focusNode: _yFocus,
                  enabled: !selected.locked && !dragging,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Y (${r.toStringAsFixed(0)}..${(TableConstants.playfieldHeight - r).toStringAsFixed(0)})',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    _yDirty = value != _syncedYText;
                  },
                  onSubmitted: (_) => _applyManualCoordinates(),
                ),
              ),
              const SizedBox(width: 8.0),
              SizedBox(
                height: 48.0,
                child: FilledButton(
                  key: const Key('apply_coords_button'),
                  onPressed: (selected.locked || dragging)
                      ? null
                      : _applyManualCoordinates,
                  child: const Text('Đặt'),
                ),
              ),
              const SizedBox(width: 4.0),
              IconButton.filledTonal(
                key: const Key('lock_ball_button'),
                tooltip: selected.locked ? 'Mở khóa bi' : 'Khóa bi',
                icon: Icon(selected.locked ? Icons.lock : Icons.lock_open),
                onPressed: dragging
                    ? null
                    : () => _controller.toggleBallLock(selected.id),
              ),
            ],
          ),
          if (_coordinateError != null) ...[
            const SizedBox(height: 6.0),
            Text(
              _coordinateError!,
              key: const Key('coordinate_error_text'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
        if (!compact) ...[
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            children: [
              FilterChip(
                key: const Key('toggle_grid_chip'),
                label: const Text('Lưới'),
                selected: view.showGrid,
                onSelected: (v) => _controller.updateViewSettings(
                  view.copyWith(showGrid: v),
                ),
              ),
              FilterChip(
                key: const Key('toggle_diamonds_chip'),
                label: const Text('Diamond'),
                selected: view.showDiamonds,
                onSelected: (v) => _controller.updateViewSettings(
                  view.copyWith(showDiamonds: v),
                ),
              ),
              FilterChip(
                key: const Key('toggle_diamond_numbers_chip'),
                label: const Text('Số diamond'),
                selected: view.showDiamondNumbers,
                onSelected: (v) => _controller.updateViewSettings(
                  view.copyWith(showDiamondNumbers: v),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BallDot extends StatelessWidget {
  final BallColor color;

  const _BallDot({required this.color});

  @override
  Widget build(BuildContext context) {
    final fill = switch (color) {
      BallColor.white => const Color(0xFFFAFAFA),
      BallColor.yellow => const Color(0xFFFFD54F),
      BallColor.red => const Color(0xFFE53935),
    };
    return Container(
      width: 14.0,
      height: 14.0,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black38, width: 1.0),
      ),
    );
  }
}
