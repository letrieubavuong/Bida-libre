import 'package:flutter/material.dart';

import '../../geometry/table_constants.dart';
import '../../models/models.dart';
import '../../state/table_editor_controller.dart';
import '../widgets/billiard_table_canvas.dart';

/// Màn hình Dựng thế bi độc lập (Phase 1):
/// Cho phép đặt/kéo 3 bi trong lòng bàn, nhập tọa độ X/Y, khóa bi,
/// bật/tắt lưới/diamond/số diamond và Undo/Redo/Đặt lại.
class TableStageScreen extends StatefulWidget {
  final TableEditorController? controller;

  const TableStageScreen({
    super.key,
    this.controller,
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

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TableEditorController();
    _controller.addListener(_onControllerChanged);
    _syncCoordinateFields(force: true);
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
    final posChanged = ball.center != _lastSyncedCenter;

    if (force || ballChanged || (posChanged && !_xFocus.hasFocus && !_yFocus.hasFocus)) {
      _xController.text = _formatCoord(ball.center.x);
      _yController.text = _formatCoord(ball.center.y);
      _lastSyncedBallId = ball.id;
      _lastSyncedCenter = ball.center;
      if (ballChanged || posChanged) {
        _coordinateError = null;
      }
    }
  }

  String _formatCoord(double v) {
    final fixed = v.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  Future<void> _confirmDiscardAndExit() async {
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
    final ball = _controller.selectedBall;
    if (ball == null) return;

    if (ball.locked) {
      setState(() {
        _coordinateError =
            '${ball.color.label} đang bị khóa. Hãy mở khóa trước khi sửa tọa độ.';
      });
      return;
    }

    final rawX = _xController.text.trim().replaceAll(',', '.');
    final rawY = _yController.text.trim().replaceAll(',', '.');
    final x = double.tryParse(rawX);
    final y = double.tryParse(rawY);

    if (x == null || y == null || !x.isFinite || !y.isFinite) {
      setState(() {
        _coordinateError = 'Vui lòng nhập số hữu hạn hợp lệ cho X và Y.';
      });
      return;
    }

    final error = _controller.setBallPosition(ball.id, DiagramPoint(x, y));
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final view = _controller.viewSettings;
            final currentR = _controller.currentBallRadius;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hiển thị bàn & bi',
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
                            onSelected: (_) {
                              final err = _controller.trySetBallRadius(r);
                              if (err != null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)),
                                );
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

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;

    return PopScope(
      canPop: !_controller.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmDiscardAndExit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0.0,
          leading: IconButton(
            tooltip: 'Quay lại',
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmDiscardAndExit,
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
              key: const Key('reset_button'),
              tooltip: 'Đặt lại',
              icon: const Icon(Icons.restart_alt),
              onPressed: _controller.resetBalls,
            ),
            IconButton(
              key: const Key('display_settings_button'),
              tooltip: 'Hiển thị bàn',
              icon: const Icon(Icons.tune),
              onPressed: _showDisplaySettingsSheet,
            ),
          ],
        ),
        body: SafeArea(
          child: isLandscape
              ? _buildLandscapeBody(context)
              : _buildPortraitBody(context),
        ),
      ),
    );
  }

  Widget _buildPortraitBody(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      children: [
        Expanded(
          child: _buildTableArea(context),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: keyboardOpen ? 200.0 : 280.0,
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
    final panelWidth = (totalWidth * 0.45).clamp(320.0, 420.0);
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
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Center(
        child: BilliardTableCanvas(
          key: const Key('billiard_table_canvas'),
          scene: _controller.scene,
          selectedBallId: _controller.selectedBallId,
          onBallTapped: _controller.selectBall,
          onBallDragStart: (ballId, touchPoint) =>
              _controller.beginBallDrag(ballId, touchPoint: touchPoint),
          onBallDragUpdateFromTouch: _controller.updateBallDragFromTouch,
          onBallDragEnd: _controller.endBallDrag,
          onBallDragCancel: _controller.cancelBallDrag,
          onLockedBallTouched: (ball) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text('${ball.color.label} đang bị khóa vị trí.'),
                  duration: const Duration(seconds: 1),
                ),
              );
          },
        ),
      ),
    );
  }

  Widget _buildControlPanel(BuildContext context, {required bool compact}) {
    final selected = _controller.selectedBall;
    final view = _controller.viewSettings;
    final r = selected?.radius ?? TableConstants.defaultBallRadius;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Chọn bi
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
                    onSelected: (_) => _controller.selectBall(ball.id),
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
                      enabled: !selected.locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'X (${r.toStringAsFixed(0)}..${(TableConstants.playfieldWidth - r).toStringAsFixed(0)})',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _applyManualCoordinates(),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: TextField(
                      key: const Key('coord_y_input'),
                      controller: _yController,
                      focusNode: _yFocus,
                      enabled: !selected.locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Y (${r.toStringAsFixed(0)}..${(TableConstants.playfieldHeight - r).toStringAsFixed(0)})',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _applyManualCoordinates(),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  SizedBox(
                    height: 48.0,
                    child: FilledButton(
                      key: const Key('apply_coords_button'),
                      onPressed: selected.locked ? null : _applyManualCoordinates,
                      child: const Text('Đặt'),
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  IconButton.filledTonal(
                    key: const Key('lock_ball_button'),
                    tooltip: selected.locked ? 'Mở khóa bi' : 'Khóa bi',
                    icon: Icon(selected.locked ? Icons.lock : Icons.lock_open),
                    onPressed: () => _controller.toggleBallLock(selected.id),
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
              // Công tắc nhanh bật/tắt lưới, diamond, số diamond & thông tin trạng thái lưu
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
              const SizedBox(height: 4.0),
              Text(
                'Bản dựng tạm để đặt thế bi — chưa lưu bài viết.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ],
        ),
      ),
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

