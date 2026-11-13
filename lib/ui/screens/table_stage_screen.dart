import 'package:flutter/material.dart';

import '../../geometry/scene_validator.dart';
import '../../geometry/table_constants.dart';
import '../../models/models.dart';
import '../../repositories/scene_storage.dart';
import '../../state/table_editor_controller.dart';
import '../widgets/billiard_table_canvas.dart';

/// Màn hình Dựng thế bi toàn vùng (Phase 1–3 + tích hợp biên tập sơ đồ bài viết Phase 4A):
/// - Canvas bàn bi phủ toàn vùng editor trong Stack, giữ đúng tỉ lệ 1:2 khi đóng/mở công cụ nổi hay bàn phím.
/// - Thanh công cụ nổi gọn (kéo bằng tay nắm riêng, thu gọn/mở rộng, giữ trong vùng an toàn khi xoay).
/// - Khi [returnSceneOnSave] = true, lưu sẽ trả về `DiagramScene` cho bài viết đang soạn mà không đụng `primary_scene.json`.
class TableStageScreen extends StatefulWidget {
  final TableEditorController? controller;
  final SceneStorage? storage;
  final DiagramScene? initialScene;
  final bool returnSceneOnSave;

  const TableStageScreen({
    super.key,
    this.controller,
    this.storage,
    this.initialScene,
    this.returnSceneOnSave = false,
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

  final GlobalKey _toolbarKey = GlobalKey();
  Offset? _toolbarOffset;
  bool _toolbarCollapsed = false;
  bool _contextPanelCollapsed = false;
  bool _isDraggingToolbar = false;

  final ValueNotifier<String?> _coordinateErrorNotifier =
      ValueNotifier<String?>(null);
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
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else if (widget.returnSceneOnSave || widget.initialScene != null) {
      _controller = TableEditorController(
        initialScene: widget.initialScene,
        storage: null,
      );
    } else {
      _controller = TableEditorController(
        storage: widget.storage ?? FileSceneStorage(),
      );
    }
    _controller.addListener(_onControllerChanged);
    _syncCoordinateFields(force: true);
    if (_ownsController && !widget.returnSceneOnSave && widget.initialScene == null) {
      _controller.loadFromStorage(force: true);
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
    _coordinateErrorNotifier.dispose();
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
        _coordinateErrorNotifier.value = null;
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
    if (widget.returnSceneOnSave) {
      if (_controller.isDraggingAny || _controller.isDrawingWithDraft) {
        _showSnack('Hãy hoàn tất thao tác hiện tại trước khi áp dụng sơ đồ.');
        return;
      }
      final err = SceneValidator.validateCompleteForSave(_controller.scene);
      if (err != null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sơ đồ chưa hợp lệ'),
            content: Text(err),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
        return;
      }
      if (mounted) {
        Navigator.of(context).pop<DiagramScene>(_controller.scene);
      }
      return;
    }

    final outcome = await _controller.saveToStorage();
    if (!mounted) return;
    if (outcome.isSuccess) {
      _showSnack(outcome.message);
    } else if (outcome.status == SaveStatus.rejectedBusy) {
      _showSnack(outcome.message);
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lỗi lưu sơ đồ'),
          content: Text(
            '${outcome.message}\n\nBản đang chỉnh vẫn được giữ lại để bạn thử lại.',
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

  Future<void> _reloadScene() async {
    final firstTry = await _controller.loadFromStorage();
    if (!mounted) return;
    if (firstTry.status == LoadStatus.needsConfirmation) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tải lại sơ đồ đã lưu?'),
          content: const Text(
            'Bạn đang có thay đổi chưa lưu. Tải lại từ bộ nhớ máy sẽ bỏ các thay đổi hiện tại.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Tải lại'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        final forced = await _controller.loadFromStorage(force: true);
        if (mounted && forced.status == LoadStatus.error) {
          _showSnack('Lỗi tải sơ đồ: ${forced.message}');
        }
      }
    } else if (firstTry.status == LoadStatus.error) {
      _showSnack('Lỗi tải sơ đồ: ${firstTry.message}');
    } else if (firstTry.status == LoadStatus.loaded) {
      _showSnack('Đã tải lại sơ đồ từ máy');
    }
  }

  Future<void> _confirmDiscardAndExit() async {
    if (_controller.isDraggingAny || _controller.isLoading) return;
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

  Future<void> _switchToolModeSafely(EditorToolMode targetMode) async {
    if (_controller.isEditingLocked) return;
    if (!_controller.isDrawingWithDraft ||
        targetMode == EditorToolMode.drawPolyline) {
      _controller.setToolMode(targetMode);
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đang có đường vẽ dở'),
        content: Text(
          'Đường hiện tại đang có ${_controller.draftPoints.length} điểm. '
          'Hãy chọn Hoàn tất hoặc Hủy đường nháp trước khi chuyển công cụ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('continue'),
            child: const Text('Tiếp tục vẽ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Hủy đường nháp'),
          ),
          if (_controller.canCompleteDraft)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('complete'),
              child: const Text('Hoàn tất đường'),
            ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'complete') {
      final err = _controller.completeDraftPath();
      if (err != null) {
        _showSnack(err);
        return;
      }
      _controller.setToolMode(targetMode);
    } else if (action == 'cancel') {
      _controller.cancelDraftPath();
      _controller.setToolMode(targetMode);
    }
  }

  bool _applyManualCoordinates() {
    if (_controller.isEditingLocked || _controller.isDrawingWithDraft) {
      return false;
    }
    final ball = _controller.selectedBall;
    if (ball == null) return false;

    if (ball.locked) {
      _coordinateErrorNotifier.value =
          '${ball.color.label} đang bị khóa. Hãy mở khóa trước khi sửa tọa độ.';
      return false;
    }

    if (!_xDirty && !_yDirty) {
      FocusScope.of(context).unfocus();
      _coordinateErrorNotifier.value = null;
      return true;
    }

    double nextX = ball.center.x;
    double nextY = ball.center.y;

    if (_xDirty) {
      final rawX = _xController.text.trim().replaceAll(',', '.');
      final parsedX = double.tryParse(rawX);
      if (parsedX == null || !parsedX.isFinite) {
        _coordinateErrorNotifier.value =
            'Vui lòng nhập số hữu hạn hợp lệ cho X.';
        return false;
      }
      nextX = parsedX;
    }

    if (_yDirty) {
      final rawY = _yController.text.trim().replaceAll(',', '.');
      final parsedY = double.tryParse(rawY);
      if (parsedY == null || !parsedY.isFinite) {
        _coordinateErrorNotifier.value =
            'Vui lòng nhập số hữu hạn hợp lệ cho Y.';
        return false;
      }
      nextY = parsedY;
    }

    final error = _controller.setBallPosition(
      ball.id,
      DiagramPoint(nextX, nextY),
    );
    if (error != null) {
      _coordinateErrorNotifier.value = error;
      return false;
    }

    FocusScope.of(context).unfocus();
    _coordinateErrorNotifier.value = null;
    _syncCoordinateFields(force: true);
    return true;
  }

  void _openCoordinateEditorSheet() {
    if (_controller.isEditingLocked || _controller.selectedBall == null) return;
    _syncCoordinateFields(force: true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: Listenable.merge([_controller, _coordinateErrorNotifier]),
          builder: (context, _) {
            final selected = _controller.selectedBall;
            if (selected == null) return const SizedBox.shrink();
            final r = selected.radius;
            final coordError = _coordinateErrorNotifier.value;
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

            return Padding(
              key: const Key('xy_editor_sheet'),
              padding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _BallDot(color: selected.color),
                      const SizedBox(width: 8.0),
                      Text(
                        'Tọa độ ${selected.color.label}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12.0),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('coord_x_input'),
                          controller: _xController,
                          focusNode: _xFocus,
                          enabled: !selected.locked && !_controller.isEditingLocked,
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
                          enabled: !selected.locked && !_controller.isEditingLocked,
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
                          onPressed: (selected.locked ||
                                  _controller.isEditingLocked)
                              ? null
                              : () {
                                  if (_applyManualCoordinates() &&
                                      sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                },
                          child: const Text('Đặt'),
                        ),
                      ),
                    ],
                  ),
                  if (coordError != null) ...[
                    const SizedBox(height: 8.0),
                    Text(
                      coordError,
                      key: const Key('coordinate_error_text'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDisplaySettingsSheet() {
    if (_controller.isEditingLocked || _controller.isDrawingWithDraft) return;
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
                            onSelected: _controller.isEditingLocked
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

  void _showDrawOptionsSheet() {
    if (_controller.isEditingLocked) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tùy chọn đường đang vẽ',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8.0),
                    SwitchListTile(
                      key: const Key('draft_anchor_chip'),
                      title: const Text('Gắn điểm đầu với bi'),
                      subtitle: const Text('Kéo bi sẽ cập nhật theo điểm đầu'),
                      value: _controller.draftAnchorStart,
                      onChanged: _controller.setDraftAnchorStart,
                    ),
                    SwitchListTile(
                      key: const Key('draft_aux_chip'),
                      title: const Text('Đường phụ minh họa'),
                      subtitle: const Text(
                        'Đường chính nằm trong vùng tâm bi [r, W-r] × [r, H-r]',
                      ),
                      value: _controller.draftRole == PathRole.auxiliary,
                      onChanged: (v) => _controller.setDraftRole(
                        v ? PathRole.auxiliary : PathRole.ballCenter,
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
    if (_controller.selectedPath == null || _controller.isEditingLocked) return;
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
                      'Thuộc tính đường hướng dẫn',
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

  Offset _clampToolbarOffset(Offset raw, Size areaSize) {
    const margin = 8.0;
    final maxAllowedWidth = (areaSize.width - 72.0).clamp(120.0, 440.0);
    final box = _toolbarKey.currentContext?.findRenderObject() as RenderBox?;
    final fallbackWidth = _toolbarCollapsed
        ? 100.0
        : (428.0 > maxAllowedWidth ? maxAllowedWidth : 428.0);
    final estWidth = box?.size.width ?? fallbackWidth;
    final estHeight = box?.size.height ?? 52.0;

    final maxX = (areaSize.width - estWidth - margin).clamp(margin, double.infinity);
    final maxY = (areaSize.height - estHeight - margin).clamp(margin, double.infinity);

    return Offset(
      raw.dx.clamp(margin, maxX).toDouble(),
      raw.dy.clamp(margin, maxY).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draggingOrLoading = _controller.isEditingLocked;
    final warnings = _controller.invalidPathWarnings;
    final ruleNotices = _controller.annotationRuleWarnings;

    return PopScope(
      canPop: !draggingOrLoading && !_controller.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !draggingOrLoading) {
          _confirmDiscardAndExit();
        }
      },
      child: Scaffold(
        // Không co canvas khi bàn phím bật (tránh đổi kích thước canvas hoặc làm nhảy điểm đang kéo).
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final areaSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final maxAllowedWidth = (areaSize.width - 72.0).clamp(120.0, 440.0);
              final defaultToolbarWidth = _toolbarCollapsed
                  ? 100.0
                  : (428.0 > maxAllowedWidth ? maxAllowedWidth : 428.0);
              final initialOffset = Offset(
                (areaSize.width - defaultToolbarWidth - 8.0)
                    .clamp(8.0, double.infinity),
                8.0,
              );
              final clampedToolbarOffset = _clampToolbarOffset(
                _toolbarOffset ?? initialOffset,
                areaSize,
              );

              return Stack(
                children: [
                  // LỚP 0: Canvas toàn vùng giữ nguyên kích thước & tỉ lệ 1:2
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: AbsorbPointer(
                        absorbing: _controller.isLoading || _isDraggingToolbar,
                        child: BilliardTableCanvas(
                          key: const Key('billiard_table_canvas'),
                          scene: _controller.scene,
                          toolMode: _controller.toolMode,
                          selectedBallId: _controller.selectedBallId,
                          selectedPathId: _controller.selectedPathId,
                          selectedVertexIndex: _controller.selectedVertexIndex,
                          selectedSegmentIndex:
                              _controller.effectiveSelectedSegmentIndex,
                          selectedControlHandle:
                              _controller.selectedControlHandle,
                          selectedAnnotationId:
                              _controller.selectedAnnotationId,
                          invalidPathIds: warnings.keys.toSet(),
                          draftPoints: _controller.draftPoints,
                          draftOwnerBallId: _controller.draftOwnerBallId,
                          draftRole: _controller.draftRole,
                          snapSettings: _controller.snapSettings,
                          onBallTapped: _controller.selectBall,
                          onPathTapped: (pathId, {segmentIndex}) =>
                              _controller.selectPath(
                            pathId,
                            segmentIndex: segmentIndex,
                          ),
                          onBallDragStart: (ballId, touchPoint) {
                            if (_xFocus.hasFocus || _yFocus.hasFocus) {
                              _xFocus.unfocus();
                              _yFocus.unfocus();
                            }
                            return _controller.beginBallDrag(
                              ballId,
                              touchPoint: touchPoint,
                            );
                          },
                          onBallDragUpdateFromTouch:
                              (touchPoint, dragToken) =>
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
                          onVertexDragStart:
                              (pathId, vertexIndex, touchPoint) {
                            return _controller.beginVertexDrag(
                              pathId,
                              vertexIndex,
                              touchPoint: touchPoint,
                              onBlocked: _showSnack,
                            );
                          },
                          onVertexDragUpdateFromTouch:
                              (touchPoint, dragToken) =>
                                  _controller.updateVertexDragFromTouch(
                            touchPoint,
                            dragToken: dragToken,
                          ),
                          onVertexDragEnd: (dragToken) =>
                              _controller.endVertexDrag(dragToken: dragToken),
                          onVertexDragCancel: (dragToken) =>
                              _controller.cancelVertexDrag(dragToken: dragToken),
                          onControlHandleDragStart:
                              (pathId, segIndex, handleIndex, touchPoint) {
                            return _controller.beginControlHandleDrag(
                              pathId,
                              segIndex,
                              handleIndex,
                              touchPoint: touchPoint,
                            );
                          },
                          onControlHandleDragUpdateFromTouch:
                              (touchPoint, dragToken) => _controller
                                  .updateControlHandleDragFromTouch(
                            touchPoint,
                            dragToken: dragToken,
                          ),
                          onControlHandleDragEnd: (dragToken) =>
                              _controller.endControlHandleDrag(
                            dragToken: dragToken,
                            onInvalidPath: _showSnack,
                          ),
                          onControlHandleDragCancel: (dragToken) =>
                              _controller.cancelControlHandleDrag(
                            dragToken: dragToken,
                          ),
                          onAnnotationTapped: _controller.selectAnnotation,
                          onAnnotationDragStart: (annId, touchPoint) {
                            return _controller.beginAnnotationDrag(
                              annId,
                              touchPoint: touchPoint,
                              onBlocked: _showSnack,
                            );
                          },
                          onAnnotationDragUpdateFromTouch:
                              (touchPoint, dragToken) =>
                                  _controller.updateAnnotationDragFromTouch(
                            touchPoint,
                            dragToken: dragToken,
                          ),
                          onAnnotationDragEnd: (dragToken) =>
                              _controller.endAnnotationDrag(
                            dragToken: dragToken,
                          ),
                          onAnnotationDragCancel: (dragToken) =>
                              _controller.cancelAnnotationDrag(
                            dragToken: dragToken,
                          ),
                          onLockedAnnotationTouched: (_) {
                            _showSnack('Chú thích đang bị khóa vị trí.');
                          },
                          onAnnotationPlaceTapped: (pt) {
                            _controller.addAnnotation(
                              type: _controller.draftAnnotationType,
                              position: pt,
                              onRejected: _showSnack,
                            );
                          },
                          onDrawPointPlaced: _controller.addDraftPoint,
                        ),
                      ),
                    ),
                  ),

                  // Thanh tiến trình mảnh khi đang tải từ kho
                  if (_controller.isLoading)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 3.0),
                    ),

                  // Nút Quay lại nổi gọn ở góc trên trái (chặn xuyên chạm xuống bàn)
                  Positioned(
                    top: 8.0,
                    left: 8.0,
                    child: _FloatingSurfaceBarrier(
                      child: Material(
                        elevation: 4.0,
                        borderRadius: BorderRadius.circular(24.0),
                        color: Theme.of(context).colorScheme.surface,
                        child: IconButton(
                          key: const Key('back_button'),
                          tooltip: 'Quay lại',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: draggingOrLoading
                              ? null
                              : _confirmDiscardAndExit,
                        ),
                      ),
                    ),
                  ),

                  // Cảnh báo lỗi đường, lỗi tải hoặc nhắc vị trí nhãn/số thứ tự bản cũ
                  if (warnings.isNotEmpty ||
                      _controller.loadError != null ||
                      ruleNotices.isNotEmpty)
                    Positioned(
                      top: 64.0,
                      left: 12.0,
                      right: 12.0,
                      child: _FloatingSurfaceBarrier(
                        child: Center(
                          child: Material(
                            elevation: 4.0,
                            borderRadius: BorderRadius.circular(12.0),
                            color: Colors.orange.shade50,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 8.0,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.deepOrange,
                                    size: 18.0,
                                  ),
                                  const SizedBox(width: 8.0),
                                  Flexible(
                                    child: Text(
                                      _controller.loadError != null
                                          ? 'Lỗi tải sơ đồ: ${_controller.loadError}'
                                          : (warnings.isNotEmpty
                                              ? warnings.values.first
                                              : ruleNotices.values.first),
                                      key: const Key(
                                          'invalid_path_warning_banner'),
                                      style: const TextStyle(
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // LỚP NỔI 1: Thanh công cụ chính kéo được bằng tay nắm riêng
                  Positioned(
                    left: clampedToolbarOffset.dx,
                    top: clampedToolbarOffset.dy,
                    child: _FloatingSurfaceBarrier(
                      child: _buildFloatingMainToolbar(
                        context,
                        areaSize,
                        clampedToolbarOffset,
                      ),
                    ),
                  ),

                  // LỚP NỔI 2: Bảng thuộc tính gọn theo đối tượng đang chọn / đang vẽ
                  Positioned(
                    left: 8.0,
                    right: 8.0,
                    bottom: 8.0,
                    child: Center(
                      child: _FloatingSurfaceBarrier(
                        child: _buildFloatingContextPanel(context),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingMainToolbar(
    BuildContext context,
    Size areaSize,
    Offset currentOffset,
  ) {
    final dragging = _controller.isDraggingAny;
    final loading = _controller.isLoading;
    final busySave =
        loading || dragging || _controller.isDrawingWithDraft || _controller.isSaving;

    const btnConstraints = BoxConstraints(minWidth: 48.0, minHeight: 48.0);
    final maxToolbarWidth = (areaSize.width - 72.0).clamp(120.0, 440.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxToolbarWidth),
      child: Material(
        key: _toolbarKey,
        elevation: 6.0,
        borderRadius: BorderRadius.circular(28.0),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Tay nắm riêng để kéo thanh công cụ nổi
              GestureDetector(
                key: const Key('floating_toolbar_drag_handle'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  if (_controller.isDraggingAny || _controller.isLoading) return;
                  setState(() {
                    _isDraggingToolbar = true;
                    _toolbarOffset ??= currentOffset;
                  });
                },
                onPanUpdate: (details) {
                  if (!_isDraggingToolbar) return;
                  setState(() {
                    final next = (_toolbarOffset ?? currentOffset) + details.delta;
                    _toolbarOffset = _clampToolbarOffset(next, areaSize);
                  });
                },
                onPanEnd: (_) {
                  if (_isDraggingToolbar) {
                    setState(() => _isDraggingToolbar = false);
                  }
                },
                onPanCancel: () {
                  if (_isDraggingToolbar) {
                    setState(() => _isDraggingToolbar = false);
                  }
                },
                child: const SizedBox(
                  width: 36.0,
                  height: 48.0,
                  child: Icon(Icons.drag_indicator, size: 20.0),
                ),
              ),

              if (_toolbarCollapsed) ...[
                Icon(
                  _controller.toolMode == EditorToolMode.drawPolyline
                      ? Icons.timeline
                      : Icons.pan_tool_alt_outlined,
                  size: 20.0,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4.0),
              ] else ...[
                IconButton(
                  key: const Key('mode_select_chip'),
                  tooltip: 'Chọn / Di chuyển',
                  constraints: btnConstraints,
                  padding: EdgeInsets.zero,
                  isSelected: _controller.toolMode == EditorToolMode.select,
                  icon: const Icon(Icons.pan_tool_alt_outlined),
                  onPressed: (dragging || loading)
                      ? null
                      : () => _switchToolModeSafely(EditorToolMode.select),
                ),
                IconButton(
                  key: const Key('mode_draw_chip'),
                  tooltip: 'Vẽ đường',
                  constraints: btnConstraints,
                  padding: EdgeInsets.zero,
                  isSelected:
                      _controller.toolMode == EditorToolMode.drawPolyline,
                  icon: const Icon(Icons.timeline),
                  onPressed: (dragging || loading)
                      ? null
                      : () =>
                          _switchToolModeSafely(EditorToolMode.drawPolyline),
                ),
                IconButton(
                  key: const Key('mode_annotation_chip'),
                  tooltip: 'Chú thích',
                  constraints: btnConstraints,
                  padding: EdgeInsets.zero,
                  isSelected:
                      _controller.toolMode == EditorToolMode.placeAnnotation,
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: (dragging || loading)
                      ? null
                      : () => _switchToolModeSafely(
                            EditorToolMode.placeAnnotation,
                          ),
                ),
                IconButton(
                  key: const Key('undo_button'),
                  tooltip: 'Hoàn tác',
                  constraints: btnConstraints,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.undo),
                  onPressed: _controller.canUndo ? _controller.undo : null,
                ),
                IconButton(
                  key: const Key('redo_button'),
                  tooltip: 'Làm lại',
                  constraints: btnConstraints,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.redo),
                  onPressed: _controller.canRedo ? _controller.redo : null,
                ),
                IconButton(
                  key: const Key('save_scene_button'),
                  tooltip: widget.returnSceneOnSave
                      ? 'Hoàn tất sơ đồ'
                      : 'Lưu sơ đồ',
                  constraints: btnConstraints,
                  padding: EdgeInsets.zero,
                  icon: _controller.isSaving
                      ? const SizedBox(
                          width: 18.0,
                          height: 18.0,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        )
                      : Badge(
                          isLabelVisible: _controller.hasUnsavedChanges,
                          smallSize: 7.0,
                          child: Icon(
                            widget.returnSceneOnSave
                                ? Icons.check_circle_outline
                                : Icons.save_outlined,
                          ),
                        ),
                  onPressed: busySave ? null : _saveScene,
                ),
                PopupMenuButton<String>(
                  key: const Key('more_menu_button'),
                  tooltip: 'Menu thêm',
                  padding: EdgeInsets.zero,
                  constraints: btnConstraints,
                  enabled: !dragging && !loading && !_controller.isDrawingWithDraft,
                  onSelected: (value) {
                    if (value == 'display') {
                      _showDisplaySettingsSheet();
                    } else if (value == 'reset') {
                      _controller.resetBalls();
                    } else if (value == 'reload') {
                      _reloadScene();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      key: Key('menu_display_settings'),
                      value: 'display',
                      child: Text('Hiển thị & Bắt dính'),
                    ),
                    const PopupMenuItem(
                      key: Key('menu_reset_balls'),
                      value: 'reset',
                      child: Text('Đặt lại vị trí bi'),
                    ),
                    if (!widget.returnSceneOnSave)
                      const PopupMenuItem(
                        key: Key('menu_reload_scene'),
                        value: 'reload',
                        child: Text('Tải lại từ máy'),
                      ),
                  ],
                ),
              ],

              IconButton(
                key: const Key('floating_toolbar_collapse_button'),
                tooltip: _toolbarCollapsed ? 'Mở rộng công cụ' : 'Thu gọn công cụ',
                constraints: btnConstraints,
                padding: EdgeInsets.zero,
                icon: Icon(
                  _toolbarCollapsed ? Icons.unfold_more : Icons.unfold_less,
                ),
                onPressed: () {
                  setState(() {
                    _toolbarCollapsed = !_toolbarCollapsed;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingContextPanel(BuildContext context) {
    if (_contextPanelCollapsed) {
      return Material(
        key: const Key('floating_panel_collapsed_pill'),
        elevation: 6.0,
        borderRadius: BorderRadius.circular(20.0),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        child: InkWell(
          key: const Key('floating_panel_expand_button'),
          borderRadius: BorderRadius.circular(20.0),
          onTap: () => setState(() => _contextPanelCollapsed = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune,
                  size: 16.0,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6.0),
                Text(
                  'Thuộc tính',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4.0),
                const Icon(Icons.expand_less, size: 16.0),
              ],
            ),
          ),
        ),
      );
    }
    if (_controller.toolMode == EditorToolMode.drawPolyline) {
      return _buildFloatingDrawPanel(context);
    }
    if (_controller.toolMode == EditorToolMode.placeAnnotation) {
      return _buildFloatingPlaceAnnotationPanel(context);
    }
    final selectedPath = _controller.selectedPath;
    if (selectedPath != null) {
      return _buildFloatingPathPanel(context, selectedPath);
    }
    final selectedAnnotation = _controller.selectedAnnotation;
    if (selectedAnnotation != null) {
      return _buildFloatingAnnotationPanel(context, selectedAnnotation);
    }
    return _buildFloatingBallPanel(context);
  }

  Widget _buildFloatingDrawPanel(BuildContext context) {
    final pointCount = _controller.draftPoints.length;
    final locked = _controller.isEditingLocked;

    return Material(
      key: const Key('floating_draw_panel'),
      elevation: 6.0,
      borderRadius: BorderRadius.circular(24.0),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('floating_panel_collapse_button'),
              tooltip: 'Thu gọn thuộc tính',
              constraints:
                  const BoxConstraints(minWidth: 40.0, minHeight: 40.0),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.expand_more, size: 20.0),
              onPressed: () => setState(() => _contextPanelCollapsed = true),
            ),
            const SizedBox(width: 4.0),
            for (final b in _controller.balls) ...[
              ChoiceChip(
                key: Key('draw_owner_${b.id}'),
                avatar: _BallDot(color: b.color),
                label: Text(b.label.isNotEmpty ? b.label : b.color.label),
                selected: _controller.draftOwnerBallId == b.id,
                onSelected: locked
                    ? null
                    : (_) => _controller.setDraftOwnerBall(b.id),
              ),
              const SizedBox(width: 4.0),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Text(
                '$pointCount điểm',
                key: const Key('draft_point_count_badge'),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              key: const Key('undo_draft_point_button'),
              tooltip: 'Lùi 1 điểm',
              icon: const Icon(Icons.backspace_outlined),
              onPressed:
                  (!locked && pointCount > 0) ? _controller.undoDraftPoint : null,
            ),
            IconButton(
              key: const Key('draw_options_button'),
              tooltip: 'Tùy chọn đường',
              icon: const Icon(Icons.tune),
              onPressed: locked ? null : _showDrawOptionsSheet,
            ),
            OutlinedButton(
              key: const Key('cancel_draft_path_button'),
              onPressed: locked ? null : _controller.cancelDraftPath,
              child: const Text('Hủy'),
            ),
            const SizedBox(width: 6.0),
            FilledButton(
              key: const Key('complete_draft_path_button'),
              onPressed: (!locked && _controller.canCompleteDraft)
                  ? () {
                      final err = _controller.completeDraftPath();
                      if (err != null) _showSnack(err);
                    }
                  : null,
              child: const Text('Hoàn tất'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingPathPanel(BuildContext context, GuidePath path) {
    final locked = _controller.isEditingLocked;
    final isAnchored = path.startAnchorBallId != null;
    final segIdx = _controller.effectiveSelectedSegmentIndex ?? 0;
    final activeSeg = path.segments[segIdx];
    final isCubic = activeSeg.type == SegmentType.cubic;
    final isUnknown = activeSeg.type == SegmentType.unknown;

    return Material(
      key: const Key('floating_path_panel'),
      elevation: 6.0,
      borderRadius: BorderRadius.circular(24.0),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('floating_panel_collapse_button'),
              tooltip: 'Thu gọn thuộc tính',
              constraints:
                  const BoxConstraints(minWidth: 40.0, minHeight: 40.0),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.expand_more, size: 20.0),
              onPressed: () => setState(() => _contextPanelCollapsed = true),
            ),
            const SizedBox(width: 4.0),
            if (path.segments.length > 1) ...[
              ActionChip(
                key: const Key('cycle_segment_button'),
                label: Text('Đoạn ${segIdx + 1}/${path.segments.length}'),
                onPressed: locked
                    ? null
                    : () => _controller.selectSegment(
                          (segIdx + 1) % path.segments.length,
                        ),
              ),
              const SizedBox(width: 6.0),
            ],
            if (!isUnknown) ...[
              ActionChip(
                key: const Key('convert_segment_button'),
                avatar: Icon(
                  isCubic ? Icons.show_chart : Icons.gesture,
                  size: 16.0,
                ),
                label: Text(isCubic ? 'Về thẳng' : 'Thành cong'),
                onPressed: locked
                    ? null
                    : _controller.toggleSelectedSegmentCurveType,
              ),
              const SizedBox(width: 6.0),
            ],
            ActionChip(
              key: const Key('insert_vertex_button'),
              avatar: const Icon(Icons.add_circle_outline, size: 16.0),
              label: const Text('Chèn điểm'),
              onPressed:
                  locked ? null : () => _controller.insertVertexOnSelectedPath(),
            ),
            const SizedBox(width: 6.0),
            ActionChip(
              key: const Key('delete_vertex_button'),
              avatar: const Icon(Icons.remove_circle_outline, size: 16.0),
              label: const Text('Xóa điểm'),
              onPressed: locked
                  ? null
                  : () {
                      final err = _controller.deleteSelectedVertex();
                      if (err != null) _showSnack(err);
                    },
            ),
            const SizedBox(width: 6.0),
            ActionChip(
              key: const Key('reverse_path_button'),
              avatar: const Icon(Icons.swap_horiz, size: 16.0),
              label: const Text('Đảo chiều'),
              onPressed: locked ? null : _controller.reverseSelectedPath,
            ),
            const SizedBox(width: 6.0),
            FilterChip(
              key: const Key('toggle_anchor_button'),
              label: Text(isAnchored ? 'Đang gắn bi' : 'Gắn bi'),
              selected: isAnchored,
              onSelected: locked
                  ? null
                  : (_) => _controller.toggleSelectedPathStartAnchor(),
            ),
            const SizedBox(width: 6.0),
            ActionChip(
              key: const Key('path_style_button'),
              avatar: const Icon(Icons.palette_outlined, size: 16.0),
              label: const Text('Kiểu nét'),
              onPressed: locked ? null : _showPathStyleSheet,
            ),
            const SizedBox(width: 6.0),
            ActionChip(
              key: const Key('delete_path_button'),
              avatar: const Icon(Icons.delete_outline, size: 16.0),
              label: const Text('Xóa đường'),
              onPressed: locked ? null : _controller.deleteSelectedPath,
            ),
            const SizedBox(width: 4.0),
            IconButton(
              tooltip: 'Đóng chọn đường',
              icon: const Icon(Icons.close),
              onPressed: locked ? null : () => _controller.selectPath(null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingBallPanel(BuildContext context) {
    final selected = _controller.selectedBall;
    final locked = _controller.isEditingLocked;

    return Material(
      key: const Key('floating_ball_panel'),
      elevation: 6.0,
      borderRadius: BorderRadius.circular(24.0),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4.0,
          runSpacing: 4.0,
          children: [
            for (final ball in _controller.balls)
              ChoiceChip(
                key: Key('select_${ball.id}'),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BallDot(color: ball.color),
                    const SizedBox(width: 4.0),
                    Text(
                      switch (ball.color) {
                        BallColor.white => 'Trắng',
                        BallColor.yellow => 'Vàng',
                        BallColor.red => 'Đỏ',
                      },
                    ),
                    if (ball.locked) ...[
                      const SizedBox(width: 2.0),
                      const Icon(Icons.lock, size: 12.0),
                    ],
                  ],
                ),
                selected: ball.id == _controller.selectedBallId,
                onSelected:
                    locked ? null : (_) => _controller.selectBall(ball.id),
              ),
            if (selected != null) ...[
              IconButton.filledTonal(
                key: const Key('lock_ball_button'),
                tooltip: selected.locked ? 'Mở khóa bi' : 'Khóa bi',
                icon: Icon(selected.locked ? Icons.lock : Icons.lock_open),
                onPressed: locked
                    ? null
                    : () => _controller.toggleBallLock(selected.id),
              ),
              OutlinedButton.icon(
                key: const Key('open_xy_button'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  minimumSize: const Size(48.0, 48.0),
                ),
                onPressed: locked ? null : _openCoordinateEditorSheet,
                icon: const Icon(Icons.my_location, size: 16.0),
                label: Text(
                  '${_formatCoord(selected.center.x)}, ${_formatCoord(selected.center.y)}',
                ),
              ),
            ],
            IconButton(
              key: const Key('floating_panel_collapse_button'),
              tooltip: 'Thu gọn thuộc tính',
              constraints:
                  const BoxConstraints(minWidth: 40.0, minHeight: 40.0),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.expand_more, size: 20.0),
              onPressed: () => setState(() => _contextPanelCollapsed = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingPlaceAnnotationPanel(BuildContext context) {
    final locked = _controller.isEditingLocked;
    return Material(
      key: const Key('floating_place_annotation_panel'),
      elevation: 6.0,
      borderRadius: BorderRadius.circular(24.0),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in AnnotationType.values) ...[
              ChoiceChip(
                key: Key('place_ann_${type.storageKey}'),
                showCheckmark: false,
                label: Text(type.displayName),
                selected: _controller.draftAnnotationType == type,
                onSelected: locked
                    ? null
                    : (_) => _controller.setDraftAnnotationType(type),
              ),
              const SizedBox(width: 4.0),
            ],
            Text(
              (_controller.draftAnnotationType == AnnotationType.label ||
                      _controller.draftAnnotationType == AnnotationType.sequence)
                  ? 'Chạm dải băng gỗ để đặt'
                  : 'Chạm bàn để đặt',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 4.0),
            IconButton(
              key: const Key('close_place_annotation_button'),
              tooltip: 'Xong',
              icon: const Icon(Icons.close),
              onPressed: locked
                  ? null
                  : () => _controller.setToolMode(EditorToolMode.select),
            ),
            IconButton(
              key: const Key('floating_panel_collapse_button'),
              tooltip: 'Thu gọn thuộc tính',
              constraints:
                  const BoxConstraints(minWidth: 40.0, minHeight: 40.0),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.expand_more, size: 20.0),
              onPressed: () => setState(() => _contextPanelCollapsed = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingAnnotationPanel(
    BuildContext context,
    DiagramAnnotation ann,
  ) {
    final locked = _controller.isEditingLocked;
    return Material(
      key: const Key('floating_annotation_panel'),
      elevation: 6.0,
      borderRadius: BorderRadius.circular(24.0),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('floating_panel_collapse_button'),
              tooltip: 'Thu gọn thuộc tính',
              constraints:
                  const BoxConstraints(minWidth: 40.0, minHeight: 40.0),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.expand_more, size: 20.0),
              onPressed: () => setState(() => _contextPanelCollapsed = true),
            ),
            const SizedBox(width: 4.0),
            Chip(
              label: Text(
                ann.text.isNotEmpty
                    ? '${ann.type.displayName}: ${ann.text}'
                    : ann.type.displayName,
              ),
            ),
            const SizedBox(width: 6.0),
            ActionChip(
              key: const Key('edit_annotation_button'),
              avatar: const Icon(Icons.edit_outlined, size: 16.0),
              label: const Text('Sửa & Kích thước'),
              onPressed:
                  locked ? null : () => _showAnnotationEditSheet(ann.id),
            ),
            const SizedBox(width: 6.0),
            IconButton.filledTonal(
              key: const Key('lock_annotation_button'),
              tooltip: ann.locked ? 'Mở khóa chú thích' : 'Khóa chú thích',
              icon: Icon(ann.locked ? Icons.lock : Icons.lock_open),
              onPressed: locked
                  ? null
                  : () => _controller.toggleAnnotationLock(ann.id),
            ),
            const SizedBox(width: 4.0),
            ActionChip(
              key: const Key('delete_annotation_button'),
              avatar: const Icon(Icons.delete_outline, size: 16.0),
              label: const Text('Xóa'),
              onPressed: locked ? null : _controller.deleteSelectedAnnotation,
            ),
            const SizedBox(width: 4.0),
            IconButton(
              tooltip: 'Đóng chọn chú thích',
              icon: const Icon(Icons.close),
              onPressed:
                  locked ? null : () => _controller.selectAnnotation(null),
            ),
          ],
        ),
      ),
    );
  }

  void _showAnnotationEditSheet(String annotationId) {
    if (_controller.isEditingLocked) return;
    final ann = _controller.selectedAnnotation;
    if (ann == null || ann.id != annotationId) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AnnotationEditSheet(
        controller: _controller,
        annotationId: annotationId,
      ),
    );
  }
}

class _AnnotationEditSheet extends StatefulWidget {
  final TableEditorController controller;
  final String annotationId;

  const _AnnotationEditSheet({
    required this.controller,
    required this.annotationId,
  });

  @override
  State<_AnnotationEditSheet> createState() => _AnnotationEditSheetState();
}

class _AnnotationEditSheetState extends State<_AnnotationEditSheet> {
  late final TextEditingController _textCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _radiusCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ann = widget.controller.selectedAnnotation!;
    _textCtrl = TextEditingController(text: ann.text);
    _widthCtrl = TextEditingController(text: ann.width.toStringAsFixed(1));
    _heightCtrl = TextEditingController(text: ann.height.toStringAsFixed(1));
    _radiusCtrl = TextEditingController(text: ann.radius.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final ann = widget.controller.selectedAnnotation;
    if (ann == null || ann.id != widget.annotationId) return;

    double? w;
    double? h;
    double? r;
    if (ann.type == AnnotationType.rectZone) {
      w = double.tryParse(_widthCtrl.text.trim().replaceAll(',', '.'));
      h = double.tryParse(_heightCtrl.text.trim().replaceAll(',', '.'));
      if (w == null || h == null || !w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
        setState(() => _error = 'Chiều rộng và chiều cao phải là số dương.');
        return;
      }
    } else if (ann.type == AnnotationType.circleZone ||
        ann.type == AnnotationType.marker) {
      r = double.tryParse(_radiusCtrl.text.trim().replaceAll(',', '.'));
      if (r == null || !r.isFinite || r <= 0) {
        setState(() => _error = 'Bán kính phải là số dương.');
        return;
      }
    }

    final err = widget.controller.updateSelectedAnnotation(
      text: _textCtrl.text.trim(),
      width: w,
      height: h,
      radius: r,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final ann = widget.controller.selectedAnnotation;
        if (ann == null || ann.id != widget.annotationId) {
          return const SizedBox.shrink();
        }
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        final colorChoices = <(String, int?)>[
          ('Mặc định', null),
          ('Trắng', 0xFFFFFFFF),
          ('Vàng', 0xFFFFD54F),
          ('Ngọc', 0xFF80DEEA),
          ('Lục', 0xFFA5D6A7),
          ('Cam', 0xFFFFCC80),
        ];

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0 + bottomInset),
            child: Column(
              key: const Key('annotation_edit_sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Chỉnh ${ann.type.displayName}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12.0),
                TextField(
                  key: const Key('ann_text_input'),
                  controller: _textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung / Nhãn',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10.0),
                if (ann.type == AnnotationType.rectZone) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('ann_width_input'),
                          controller: _widthCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Rộng',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: TextField(
                          key: const Key('ann_height_input'),
                          controller: _heightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Cao',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                ] else if (ann.type == AnnotationType.circleZone ||
                    ann.type == AnnotationType.marker) ...[
                  TextField(
                    key: const Key('ann_radius_input'),
                    controller: _radiusCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Bán kính',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10.0),
                ],
                Wrap(
                  spacing: 6.0,
                  children: colorChoices.map((entry) {
                    final selected = entry.$2 == null
                        ? ann.colorValue == null
                        : ann.colorValue == entry.$2;
                    return ChoiceChip(
                      label: Text(entry.$1),
                      selected: selected,
                      onSelected: (_) => widget.controller.updateSelectedAnnotation(
                        colorValue: entry.$2,
                        clearColor: entry.$2 == null,
                      ),
                    );
                  }).toList(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Nét đứt'),
                  value: ann.isDashed,
                  onChanged: (v) =>
                      widget.controller.updateSelectedAnnotation(isDashed: v),
                ),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 8.0),
                ],
                FilledButton(
                  key: const Key('apply_annotation_button'),
                  onPressed: _apply,
                  child: const Text('Áp dụng'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lớp chắn pointer giúp thao tác chạm/kéo trên công cụ nổi không xuyên xuống bàn bên dưới.
class _FloatingSurfaceBarrier extends StatelessWidget {
  final Widget child;

  const _FloatingSurfaceBarrier({required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {},
      onPointerMove: (_) {},
      onPointerUp: (_) {},
      child: child,
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
