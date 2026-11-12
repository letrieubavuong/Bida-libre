import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/notebook_controller.dart';
import '../widgets/billiard_table_canvas.dart';
import 'table_stage_screen.dart';

/// Màn hình soạn / chỉnh sửa bài viết (Phase 4A):
/// - Form đơn giản cho Kĩ thuật / Bộ số / Hình bi + Thông số cách đánh tĩnh + Sơ đồ theo thứ tự.
/// - Tích hợp trình dựng sơ đồ trả kết quả về bản nháp (không đụng `primary_scene.json`).
/// - Cảnh báo khi thoát có thay đổi chưa lưu (Lưu / Bỏ thay đổi / Ở lại).
class ArticleEditorScreen extends StatefulWidget {
  final NotebookController controller;
  final Article? existingArticle;
  final ArticleKind initialKind;

  const ArticleEditorScreen({
    super.key,
    required this.controller,
    this.existingArticle,
    this.initialKind = ArticleKind.technique,
  });

  @override
  State<ArticleEditorScreen> createState() => _ArticleEditorScreenState();
}

class _ArticleEditorScreenState extends State<ArticleEditorScreen> {
  final Random _random = Random.secure();

  late ArticleKind _kind;
  late String _primaryGroupId;
  late Difficulty _difficulty;
  late bool _isDraft;
  late StrokeParameters _stroke;
  late List<ArticleDiagram> _diagrams;
  late List<TextEditingController> _stepControllers;
  late List<TextEditingController> _diagramCaptionControllers;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _goalCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _mistakesCtrl;
  late final TextEditingController _sourceCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _sourcePageCtrl;
  late final TextEditingController _exactThickCtrl;
  late final TextEditingController _tipXCtrl;
  late final TextEditingController _tipZCtrl;
  late final TextEditingController _tipNoteCtrl;
  late final TextEditingController _forceCtrl;
  late final TextEditingController _styleCtrl;

  late final String _workingArticleId;
  late final Article _initialBaseline;
  bool _savedPopped = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingArticle;
    _workingArticleId = existing?.id ?? '';
    _kind = existing?.kind ?? widget.initialKind;

    final groups = widget.controller.groupsForKind(_kind);
    _primaryGroupId = existing?.primaryGroupId ??
        (groups.isNotEmpty ? groups.first.id : 'unclassified');
    _difficulty = existing?.difficulty ?? Difficulty.unrated;
    _isDraft = existing?.isDraft ?? false;
    _stroke = existing?.strokeParameters ?? const StrokeParameters.defaults();
    _diagrams = List<ArticleDiagram>.from(existing?.diagrams ?? const []);

    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _summaryCtrl = TextEditingController(text: existing?.summary ?? '');
    _goalCtrl = TextEditingController(text: existing?.goal ?? '');
    _contentCtrl = TextEditingController(text: existing?.content ?? '');
    _mistakesCtrl =
        TextEditingController(text: existing?.commonMistakes ?? '');
    _sourceCtrl = TextEditingController(text: existing?.source ?? '');
    _authorCtrl = TextEditingController(text: existing?.author ?? '');
    _sourcePageCtrl = TextEditingController(text: existing?.sourcePage ?? '');

    _exactThickCtrl = TextEditingController(
      text: _stroke.exactThicknessValue?.toString() ?? '',
    );
    _tipXCtrl = TextEditingController(text: _stroke.tipXMm.toString());
    _tipZCtrl = TextEditingController(text: _stroke.tipZMm.toString());
    _tipNoteCtrl = TextEditingController(text: _stroke.tipNote);
    _forceCtrl = TextEditingController(text: _stroke.forceText);
    _styleCtrl = TextEditingController(text: _stroke.strokeStyleText);

    _stepControllers = (existing?.steps ?? const [])
        .map((s) => TextEditingController(text: s))
        .toList();
    _diagramCaptionControllers = _diagrams
        .map((d) => TextEditingController(text: d.caption))
        .toList();

    _initialBaseline = _buildCurrentDraft();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _goalCtrl.dispose();
    _contentCtrl.dispose();
    _mistakesCtrl.dispose();
    _sourceCtrl.dispose();
    _authorCtrl.dispose();
    _sourcePageCtrl.dispose();
    _exactThickCtrl.dispose();
    _tipXCtrl.dispose();
    _tipZCtrl.dispose();
    _tipNoteCtrl.dispose();
    _forceCtrl.dispose();
    _styleCtrl.dispose();
    for (final c in _stepControllers) {
      c.dispose();
    }
    for (final c in _diagramCaptionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _freshUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}'
        '${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }

  double _parseDoubleOr(String raw, double fallback) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite) return fallback;
    return parsed;
  }

  Article _buildCurrentDraft({bool? overrideIsDraft}) {
    final now = widget.existingArticle?.createdAt ?? DateTime.utc(2026);
    final updated = widget.existingArticle?.updatedAt ?? now;
    final parsedExact = double.tryParse(
      _exactThickCtrl.text.trim().replaceAll(',', '.'),
    );

    final stroke = _stroke.copyWith(
      exactThicknessValue:
          (parsedExact != null && parsedExact.isFinite) ? parsedExact : null,
      clearExactThickness:
          parsedExact == null || !parsedExact.isFinite,
      tipXMm: _parseDoubleOr(_tipXCtrl.text, _stroke.tipXMm),
      tipZMm: _parseDoubleOr(_tipZCtrl.text, _stroke.tipZMm),
      tipNote: _tipNoteCtrl.text.trim(),
      forceText: _forceCtrl.text.trim(),
      strokeStyleText: _styleCtrl.text.trim(),
    );

    final steps = _stepControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    final updatedDiagrams = <ArticleDiagram>[];
    for (var i = 0; i < _diagrams.length; i++) {
      updatedDiagrams.add(
        _diagrams[i].copyWith(
          sortOrder: i,
          caption: _diagramCaptionControllers[i].text.trim(),
        ),
      );
    }

    String? optText(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    return Article(
      id: _workingArticleId,
      code: widget.existingArticle?.code ?? '',
      kind: _kind,
      title: _titleCtrl.text,
      summary: _summaryCtrl.text.trim(),
      primaryGroupId: _primaryGroupId,
      tags: widget.existingArticle?.tags ?? const [],
      difficulty: _difficulty,
      goal: _goalCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      steps: steps,
      commonMistakes: _mistakesCtrl.text.trim(),
      source: optText(_sourceCtrl),
      author: optText(_authorCtrl),
      sourcePage: optText(_sourcePageCtrl),
      isDraft: overrideIsDraft ?? _isDraft,
      strokeParameters: stroke,
      diagrams: updatedDiagrams,
      createdAt: now,
      updatedAt: updated,
      isFavorite: widget.existingArticle?.isFavorite ?? false,
      practiceStatus:
          widget.existingArticle?.practiceStatus ?? PracticeStatus.notStarted,
      relatedArticleIds: widget.existingArticle?.relatedArticleIds ?? const [],
    );
  }

  bool get _hasUnsavedChanges {
    if (_savedPopped) return false;
    return _buildCurrentDraft() != _initialBaseline;
  }

  Future<bool> _saveArticle({bool? forceDraft}) async {
    if (widget.controller.isSaving) return false;
    final draft = _buildCurrentDraft(overrideIsDraft: forceDraft);
    final outcome = await widget.controller.saveArticle(draft);
    if (!mounted) return false;

    if (!outcome.isSuccess) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chưa thể lưu bài viết'),
          content: Text(outcome.error ?? 'Lỗi không xác định.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return false;
    }

    _savedPopped = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã lưu bài ${outcome.article!.code}')),
    );
    Navigator.of(context).pop<Article>(outcome.article);
    return true;
  }

  Future<void> _handleExit() async {
    if (widget.controller.isSaving) return;
    if (!_hasUnsavedChanges) {
      Navigator.of(context).pop();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thay đổi chưa được lưu'),
        content: const Text(
          'Bạn có thay đổi chưa lưu trong bài viết này. Bạn muốn xử lý thế nào?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('Ở lại'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Bỏ thay đổi'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (choice == 'discard') {
      _savedPopped = true;
      Navigator.of(context).pop();
    } else if (choice == 'save') {
      await _saveArticle();
    }
  }

  Future<void> _addDiagram() async {
    final newId = _freshUuid();
    final initial = DiagramScene.defaultInitial(id: newId);
    final result = await Navigator.of(context).push<DiagramScene>(
      MaterialPageRoute(
        builder: (_) => TableStageScreen(
          initialScene: initial,
          returnSceneOnSave: true,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _diagrams.add(
        ArticleDiagram(
          id: newId,
          articleId: _workingArticleId,
          sortOrder: _diagrams.length,
          caption: '',
          scene: result.copyWith(id: newId),
        ),
      );
      _diagramCaptionControllers.add(TextEditingController());
    });
  }

  Future<void> _editDiagram(int index) async {
    final existing = _diagrams[index];
    final result = await Navigator.of(context).push<DiagramScene>(
      MaterialPageRoute(
        builder: (_) => TableStageScreen(
          initialScene: existing.scene,
          returnSceneOnSave: true,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _diagrams[index] = existing.copyWith(
        scene: result.copyWith(id: existing.id),
      );
    });
  }

  void _moveDiagram(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _diagrams.length) return;
    setState(() {
      final diag = _diagrams.removeAt(index);
      final cap = _diagramCaptionControllers.removeAt(index);
      _diagrams.insert(next, diag);
      _diagramCaptionControllers.insert(next, cap);
    });
  }

  void _removeDiagram(int index) {
    setState(() {
      _diagrams.removeAt(index);
      final cap = _diagramCaptionControllers.removeAt(index);
      cap.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.controller.groupsForKind(_kind);
    if (!groups.any((g) => g.id == _primaryGroupId) && groups.isNotEmpty) {
      _primaryGroupId = groups.first.id;
    }

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final saving = widget.controller.isSaving;
        return PopScope(
          canPop: _savedPopped || (!saving && !_hasUnsavedChanges),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !saving) {
              _handleExit();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                key: const Key('editor_back_button'),
                icon: const Icon(Icons.arrow_back),
                onPressed: saving ? null : _handleExit,
              ),
              title: Text(
                widget.existingArticle == null
                    ? 'Bài viết mới'
                    : 'Sửa ${widget.existingArticle!.code}',
              ),
              actions: [
                TextButton(
                  key: const Key('save_draft_button'),
                  onPressed: saving ? null : () => _saveArticle(forceDraft: true),
                  child: const Text('Lưu nháp'),
                ),
                FilledButton(
                  key: const Key('save_article_button'),
                  onPressed: saving ? null : () => _saveArticle(forceDraft: false),
                  child: const Text('Lưu bài'),
                ),
                const SizedBox(width: 8.0),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text(
                  'Thông tin chung',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8.0),
                Wrap(
                  spacing: 8.0,
                  children: ArticleKind.values.map((k) {
                    return ChoiceChip(
                      key: Key('kind_chip_${k.storageKey}'),
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: saving
                          ? null
                          : (_) {
                              setState(() {
                                _kind = k;
                                final newGroups =
                                    widget.controller.groupsForKind(k);
                                _primaryGroupId = newGroups.isNotEmpty
                                    ? newGroups.first.id
                                    : 'unclassified';
                              });
                            },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12.0),
                TextField(
                  key: const Key('article_title_input'),
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên bài viết *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10.0),
                TextField(
                  key: const Key('article_summary_input'),
                  controller: _summaryCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả ngắn',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10.0),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('article_group_dropdown'),
                        isExpanded: true,
                        initialValue: groups.any((g) => g.id == _primaryGroupId)
                            ? _primaryGroupId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Nhóm chính',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: groups
                            .map(
                              (g) => DropdownMenuItem(
                                value: g.id,
                                child: Text(
                                  g.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => _primaryGroupId = val);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: DropdownButtonFormField<Difficulty>(
                        key: const Key('article_difficulty_dropdown'),
                        isExpanded: true,
                        initialValue: _difficulty,
                        decoration: const InputDecoration(
                          labelText: 'Độ khó',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: Difficulty.values
                            .map(
                              (d) => DropdownMenuItem(
                                value: d,
                                child: Text(
                                  d.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => _difficulty = val);
                                }
                              },
                      ),
                    ),
                  ],
                ),

                const Divider(height: 32.0),
                Text(
                  'Nội dung bài viết',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8.0),
                TextField(
                  key: const Key('article_goal_input'),
                  controller: _goalCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Mục tiêu & Tình huống áp dụng',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10.0),
                TextField(
                  key: const Key('article_content_input'),
                  controller: _contentCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung giải thích',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Các bước thực hiện',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextButton.icon(
                      key: const Key('add_step_button'),
                      onPressed: saving
                          ? null
                          : () {
                              setState(() {
                                _stepControllers.add(TextEditingController());
                              });
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm bước'),
                    ),
                  ],
                ),
                for (var i = 0; i < _stepControllers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: Key('step_input_$i'),
                            controller: _stepControllers[i],
                            decoration: InputDecoration(
                              labelText: 'Bước ${i + 1}',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Xóa bước',
                          icon: const Icon(Icons.close),
                          onPressed: saving
                              ? null
                              : () {
                                  setState(() {
                                    final c = _stepControllers.removeAt(i);
                                    c.dispose();
                                  });
                                },
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8.0),
                TextField(
                  key: const Key('article_mistakes_input'),
                  controller: _mistakesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Lưu ý / Lỗi thường gặp',
                    border: OutlineInputBorder(),
                  ),
                ),

                const Divider(height: 32.0),
                Text(
                  'Thông số cách đánh (Tĩnh)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  'Chỉ ghi chú thông số kỹ thuật tĩnh; không tự sửa vị trí bi hoặc đường trên sơ đồ.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10.0),
                const Text('Bi chủ', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6.0),
                Wrap(
                  spacing: 6.0,
                  children: const [
                    ('ball_white', 'Bi trắng'),
                    ('ball_yellow', 'Bi vàng'),
                    ('ball_red', 'Bi đỏ'),
                  ].map((e) {
                    return ChoiceChip(
                      key: Key('stroke_cue_${e.$1}'),
                      label: Text(e.$2),
                      selected: _stroke.cueBallId == e.$1,
                      onSelected: saving
                          ? null
                          : (_) => setState(
                                () => _stroke = _stroke.copyWith(cueBallId: e.$1),
                              ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10.0),
                const Text('Độ dày chạm', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6.0),
                Wrap(
                  spacing: 6.0,
                  children: HitThicknessMode.values.map((m) {
                    return ChoiceChip(
                      key: Key('stroke_mode_${m.storageKey}'),
                      label: Text(m.displayName),
                      selected: _stroke.thicknessMode == m,
                      onSelected: saving
                          ? null
                          : (_) => setState(
                                () => _stroke = _stroke.copyWith(thicknessMode: m),
                              ),
                    );
                  }).toList(),
                ),
                if (_stroke.thicknessMode == HitThicknessMode.eighths) ...[
                  const SizedBox(height: 8.0),
                  Wrap(
                    spacing: 6.0,
                    children: List.generate(8, (idx) {
                      final k = idx + 1;
                      return ChoiceChip(
                        key: Key('stroke_eighth_$k'),
                        label: Text('$k/8'),
                        selected: _stroke.eighthCount == k,
                        onSelected: saving
                            ? null
                            : (_) => setState(
                                  () => _stroke = _stroke.copyWith(eighthCount: k),
                                ),
                      );
                    }),
                  ),
                ] else if (_stroke.thicknessMode == HitThicknessMode.exact) ...[
                  const SizedBox(height: 8.0),
                  TextField(
                    key: const Key('stroke_exact_thickness_input'),
                    controller: _exactThickCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Giá trị chạm chính xác (ví dụ 0.45)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 8.0),
                SwitchListTile(
                  key: const Key('stroke_full_face_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tràn mặt'),
                  subtitle: const Text(
                    'Bật/tắt tràn mặt vẫn giữ nguyên tỷ lệ và má chạm đã chọn trước đó.',
                  ),
                  value: _stroke.isFullFace,
                  onChanged: saving
                      ? null
                      : (v) => setState(
                            () => _stroke = _stroke.copyWith(isFullFace: v),
                          ),
                ),
                Wrap(
                  spacing: 6.0,
                  children: HitSide.values.map((side) {
                    return ChoiceChip(
                      key: Key('stroke_side_${side.storageKey}'),
                      label: Text(side.displayName),
                      selected: _stroke.hitSide == side,
                      onSelected: saving
                          ? null
                          : (_) => setState(
                                () => _stroke = _stroke.copyWith(hitSide: side),
                              ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10.0),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('stroke_tip_x_input'),
                        controller: _tipXCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Mũi cơ X (mm, + phải / - trái)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: TextField(
                        key: const Key('stroke_tip_z_input'),
                        controller: _tipZCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Mũi cơ Z (mm, + trên / - dưới)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6.0),
                Text(
                  'Quy ước 4 mức biên tập: Ngang ${CueTipConvention.describeAxisOffset(_parseDoubleOr(_tipXCtrl.text, _stroke.tipXMm), positiveLabel: 'Phải', negativeLabel: 'Trái')} • '
                  'Dọc ${CueTipConvention.describeAxisOffset(_parseDoubleOr(_tipZCtrl.text, _stroke.tipZMm), positiveLabel: 'Trên', negativeLabel: 'Dưới')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8.0),
                Wrap(
                  spacing: 6.0,
                  children: CueTipConvention.standardTipDiametersMm.map((d) {
                    return ChoiceChip(
                      label: Text('Đầu cơ $d mm'),
                      selected: (_stroke.tipDiameterMm - d).abs() < 0.01,
                      onSelected: saving
                          ? null
                          : (_) => setState(
                                () => _stroke = _stroke.copyWith(tipDiameterMm: d),
                              ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8.0),
                TextField(
                  key: const Key('stroke_force_input'),
                  controller: _forceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lực đánh (văn bản, ví dụ: vừa đủ về)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8.0),
                TextField(
                  key: const Key('stroke_style_input'),
                  controller: _styleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kiểu ra cơ (văn bản)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),

                const Divider(height: 32.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sơ đồ gắn với bài (${_diagrams.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    FilledButton.tonalIcon(
                      key: const Key('add_diagram_button'),
                      onPressed: saving ? null : _addDiagram,
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Thêm sơ đồ'),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                for (var i = 0; i < _diagrams.length; i++)
                  Card(
                    key: Key('editor_diagram_card_$i'),
                    margin: const EdgeInsets.only(bottom: 12.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Sơ đồ ${i + 1}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              IconButton(
                                key: Key('diagram_up_$i'),
                                tooltip: 'Đưa lên',
                                icon: const Icon(Icons.arrow_upward),
                                onPressed: (saving || i == 0)
                                    ? null
                                    : () => _moveDiagram(i, -1),
                              ),
                              IconButton(
                                key: Key('diagram_down_$i'),
                                tooltip: 'Đưa xuống',
                                icon: const Icon(Icons.arrow_downward),
                                onPressed:
                                    (saving || i == _diagrams.length - 1)
                                        ? null
                                        : () => _moveDiagram(i, 1),
                              ),
                              IconButton(
                                key: Key('delete_diagram_$i'),
                                tooltip: 'Xóa sơ đồ',
                                icon: const Icon(Icons.delete_outline),
                                onPressed:
                                    saving ? null : () => _removeDiagram(i),
                              ),
                            ],
                          ),
                          Center(
                            child: SizedBox(
                              height: 220.0,
                              child: BilliardTableReadOnlyView(
                                scene: _diagrams[i].scene,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          TextField(
                            key: Key('diagram_caption_input_$i'),
                            controller: _diagramCaptionControllers[i],
                            decoration: const InputDecoration(
                              labelText: 'Chú thích sơ đồ',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          OutlinedButton.icon(
                            key: Key('edit_diagram_$i'),
                            onPressed: saving ? null : () => _editDiagram(i),
                            icon: const Icon(Icons.edit_location_alt_outlined),
                            label: const Text('Mở trình dựng sơ đồ'),
                          ),
                        ],
                      ),
                    ),
                  ),

                const Divider(height: 32.0),
                Text(
                  'Nguồn tài liệu (tùy chọn)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8.0),
                TextField(
                  key: const Key('article_source_input'),
                  controller: _sourceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên nguồn / Sách',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('article_author_input'),
                        controller: _authorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tác giả',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: TextField(
                        key: const Key('article_source_page_input'),
                        controller: _sourcePageCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Số trang',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

