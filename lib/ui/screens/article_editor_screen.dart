import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/models.dart';
import '../../repositories/article_asset_store.dart';
import '../../state/notebook_controller.dart';
import '../widgets/billiard_table_canvas.dart';
import 'article_detail_screen.dart';
import 'table_stage_screen.dart';

/// Màn hình soạn / chỉnh sửa bài viết (Phase 4A–4C):
/// - Form đơn giản cho Kĩ thuật / Bộ số / Hình bi + Thông số cách đánh tĩnh + Sơ đồ + Ảnh đính kèm.
/// - Tích hợp trình dựng sơ đồ trả kết quả về bản nháp (không đụng `primary_scene.json`).
/// - Cảnh báo khi thoát có thay đổi chưa lưu (Lưu / Bỏ thay đổi / Ở lại).
class ArticleEditorScreen extends StatefulWidget {
  final NotebookController controller;
  final Article? existingArticle;
  final ArticleKind initialKind;
  final Future<List<({String name, String? path, Uint8List? bytes})>> Function()?
      imagePickerOverride;
  final Future<bool> Function(Uri uri)? onLaunchUrl;

  const ArticleEditorScreen({
    super.key,
    required this.controller,
    this.existingArticle,
    this.initialKind = ArticleKind.technique,
    this.imagePickerOverride,
    this.onLaunchUrl,
  });

  @override
  State<ArticleEditorScreen> createState() => ArticleEditorScreenState();
}

class ArticleEditorScreenState extends State<ArticleEditorScreen> {
  static final DateTime _draftSentinelTimestamp =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final Random _random = Random.secure();

  late ArticleKind _kind;
  late String _primaryGroupId;
  late Difficulty _difficulty;
  late bool _isDraft;
  late List<String> _tags;
  late StrokeParameters _stroke;
  late List<ArticleDiagram> _diagrams;
  late List<ArticleImageAttachment> _images;
  late List<TextEditingController> _stepControllers;
  late List<TextEditingController> _diagramCaptionControllers;
  late List<TextEditingController> _imageCaptionControllers;
  final List<String> _newlyStagedAssetIds = [];
  bool _isImportingImages = false;
  bool _isDisposed = false;

  /// Cache thumbnail LRU với giới hạn dung lượng/số mục rõ ràng.
  /// Đọc bất đồng bộ và đóng file handle ngay lập tức (không giữ khóa tệp trên Windows).
  /// Giải phóng khi bỏ ảnh hoặc khi đóng editor.
  final EditorThumbnailCache _thumbnailCache = EditorThumbnailCache(maxEntries: 20);

  @visibleForTesting
  EditorThumbnailCache get thumbnailCacheForTesting => _thumbnailCache;

  bool get _isBusy => widget.controller.isSaving || _isImportingImages;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _goalCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _mistakesCtrl;
  late final TextEditingController _sourceCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _sourcePageCtrl;
  late final TextEditingController _sourceUrlCtrl;
  late final TextEditingController _exactThickCtrl;
  late final TextEditingController _tipXCtrl;
  late final TextEditingController _tipZCtrl;
  late final TextEditingController _tipNoteCtrl;
  late final TextEditingController _forceCtrl;
  late final TextEditingController _styleCtrl;
  late final TextEditingController _tagInputCtrl;

  late final String _workingArticleId;
  late final Article _initialBaseline;
  late final String _initialExactRaw;
  late final String _initialTipXRaw;
  late final String _initialTipZRaw;
  bool _savedPopped = false;

  List<TextEditingController> get _fixedTextControllers => [
        _titleCtrl,
        _summaryCtrl,
        _goalCtrl,
        _contentCtrl,
        _mistakesCtrl,
        _sourceCtrl,
        _authorCtrl,
        _sourcePageCtrl,
        _sourceUrlCtrl,
        _exactThickCtrl,
        _tipXCtrl,
        _tipZCtrl,
        _tipNoteCtrl,
        _forceCtrl,
        _styleCtrl,
        _tagInputCtrl,
      ];

  void _onFormFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existingArticle;
    _workingArticleId = existing?.id ?? '';
    _kind = existing?.kind ?? widget.initialKind;

    final groups = widget.controller.groupsForKind(_kind);
    _primaryGroupId = existing?.primaryGroupId ??
        (groups.isNotEmpty
            ? groups.first.id
            : DefaultEditorialGroups.unclassifiedIdFor(_kind));
    _difficulty = existing?.difficulty ?? Difficulty.unrated;
    _isDraft = existing?.isDraft ?? false;
    _tags = List<String>.from(existing?.tags ?? const []);
    _stroke = existing?.strokeParameters ?? const StrokeParameters.defaults();
    _diagrams = List<ArticleDiagram>.from(existing?.diagrams ?? const []);
    _images = List<ArticleImageAttachment>.from(existing?.images ?? const []);

    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _summaryCtrl = TextEditingController(text: existing?.summary ?? '');
    _goalCtrl = TextEditingController(text: existing?.goal ?? '');
    _contentCtrl = TextEditingController(text: existing?.content ?? '');
    _mistakesCtrl =
        TextEditingController(text: existing?.commonMistakes ?? '');
    _sourceCtrl = TextEditingController(text: existing?.source ?? '');
    _authorCtrl = TextEditingController(text: existing?.author ?? '');
    _sourcePageCtrl = TextEditingController(text: existing?.sourcePage ?? '');
    _sourceUrlCtrl = TextEditingController(text: existing?.sourceUrl ?? '');

    _exactThickCtrl = TextEditingController(
      text: _stroke.exactThicknessValue?.toString() ?? '',
    );
    _tipXCtrl = TextEditingController(text: _stroke.tipXMm.toString());
    _tipZCtrl = TextEditingController(text: _stroke.tipZMm.toString());
    _tipNoteCtrl = TextEditingController(text: _stroke.tipNote);
    _forceCtrl = TextEditingController(text: _stroke.forceText);
    _styleCtrl = TextEditingController(text: _stroke.strokeStyleText);
    _tagInputCtrl = TextEditingController();

    _stepControllers = (existing?.steps ?? const [])
        .map((s) => TextEditingController(text: s))
        .toList();
    _diagramCaptionControllers = _diagrams
        .map((d) => TextEditingController(text: d.caption))
        .toList();
    _imageCaptionControllers = _images
        .map((img) => TextEditingController(text: img.caption))
        .toList();

    for (final c in _fixedTextControllers) {
      c.addListener(_onFormFieldChanged);
    }
    for (final c in _stepControllers) {
      c.addListener(_onFormFieldChanged);
    }
    for (final c in _diagramCaptionControllers) {
      c.addListener(_onFormFieldChanged);
    }
    for (final c in _imageCaptionControllers) {
      c.addListener(_onFormFieldChanged);
    }

    _initialExactRaw = _exactThickCtrl.text.trim();
    _initialTipXRaw = _tipXCtrl.text.trim();
    _initialTipZRaw = _tipZCtrl.text.trim();
    _initialBaseline = _buildCurrentDraft();
  }

  @override
  void dispose() {
    _thumbnailCache.clear();
    for (final c in _fixedTextControllers) {
      c.removeListener(_onFormFieldChanged);
      c.dispose();
    }
    for (final c in _stepControllers) {
      c.removeListener(_onFormFieldChanged);
      c.dispose();
    }
    for (final c in _diagramCaptionControllers) {
      c.removeListener(_onFormFieldChanged);
      c.dispose();
    }
    for (final c in _imageCaptionControllers) {
      c.removeListener(_onFormFieldChanged);
      c.dispose();
    }
    _isDisposed = true;
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

  double? _tryParseFiniteDouble(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final parsed = double.tryParse(normalized);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  String? get _exactThicknessError {
    if (_stroke.thicknessMode != HitThicknessMode.exact) {
      return null;
    }
    final raw = _exactThickCtrl.text.trim();
    if (raw.isEmpty) {
      return 'Nhập giá trị độ dày (0 đến 1).';
    }
    final parsed = _tryParseFiniteDouble(raw);
    if (parsed == null) {
      return 'Giá trị độ dày phải là số hữu hạn (hỗ trợ dấu phẩy).';
    }
    if (parsed < 0.0 || parsed > 1.0) {
      return 'Độ dày chính xác phải nằm trong khoảng 0 đến 1.';
    }
    return null;
  }

  String? get _tipXError {
    final raw = _tipXCtrl.text.trim();
    if (raw.isEmpty) {
      return 'Nhập tọa độ mũi cơ X (mm).';
    }
    if (_tryParseFiniteDouble(raw) == null) {
      return 'Mũi cơ X phải là số hữu hạn (hỗ trợ dấu phẩy).';
    }
    return null;
  }

  String? get _tipZError {
    final raw = _tipZCtrl.text.trim();
    if (raw.isEmpty) {
      return 'Nhập tọa độ mũi cơ Z (mm).';
    }
    if (_tryParseFiniteDouble(raw) == null) {
      return 'Mũi cơ Z phải là số hữu hạn (hỗ trợ dấu phẩy).';
    }
    return null;
  }

  String? _firstNumericValidationError() {
    return _exactThicknessError ?? _tipXError ?? _tipZError;
  }

  String? get _sourceUrlError {
    final raw = _sourceUrlCtrl.text.trim();
    if (raw.isEmpty) return null;
    if (!Article.isValidOptionalHttpUrl(raw)) {
      return 'Liên kết nguồn phải bắt đầu bằng http:// hoặc https:// và hợp lệ.';
    }
    return null;
  }

  String? _firstFormValidationError() {
    return _firstNumericValidationError() ?? _sourceUrlError;
  }

  Article _buildCurrentDraft({bool? overrideIsDraft}) {
    final created = widget.existingArticle?.createdAt ?? _draftSentinelTimestamp;
    final updated = widget.existingArticle?.updatedAt ?? _draftSentinelTimestamp;
    final parsedExact = _tryParseFiniteDouble(_exactThickCtrl.text);
    final parsedTipX = _tryParseFiniteDouble(_tipXCtrl.text);
    final parsedTipZ = _tryParseFiniteDouble(_tipZCtrl.text);

    final bool exactWithinRange =
        parsedExact != null && parsedExact >= 0.0 && parsedExact <= 1.0;
    final double? effectiveExact = _stroke.thicknessMode == HitThicknessMode.exact
        ? parsedExact
        : (exactWithinRange ? parsedExact : null);

    final stroke = _stroke.copyWith(
      exactThicknessValue: effectiveExact,
      clearExactThickness: effectiveExact == null,
      tipXMm: parsedTipX ?? _stroke.tipXMm,
      tipZMm: parsedTipZ ?? _stroke.tipZMm,
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

    final updatedImages = <ArticleImageAttachment>[];
    for (var i = 0; i < _images.length; i++) {
      updatedImages.add(
        _images[i].copyWith(
          sortOrder: i,
          caption: _imageCaptionControllers[i].text.trim(),
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
      tags: _mergedTagsWithPendingInput(),
      difficulty: _difficulty,
      goal: _goalCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      steps: steps,
      commonMistakes: _mistakesCtrl.text.trim(),
      source: optText(_sourceCtrl),
      author: optText(_authorCtrl),
      sourcePage: optText(_sourcePageCtrl),
      sourceUrl: optText(_sourceUrlCtrl),
      isDraft: overrideIsDraft ?? _isDraft,
      strokeParameters: stroke,
      diagrams: updatedDiagrams,
      images: updatedImages,
      createdAt: created,
      updatedAt: updated,
      isFavorite: widget.existingArticle?.isFavorite ?? false,
      practiceStatus:
          widget.existingArticle?.practiceStatus ?? PracticeStatus.notStarted,
      relatedArticleIds: widget.existingArticle?.relatedArticleIds ?? const [],
    );
  }

  bool _numericFieldChanged(String currentRaw, String initialRaw) {
    final curTrim = currentRaw.trim();
    final initTrim = initialRaw.trim();
    if (curTrim == initTrim) return false;
    final curVal = _tryParseFiniteDouble(curTrim);
    final initVal = _tryParseFiniteDouble(initTrim);
    if (curVal != null && initVal != null && curVal == initVal) {
      return false;
    }
    return true;
  }

  bool get _hasUnsavedChanges {
    if (_savedPopped) return false;
    if (_tagInputCtrl.text.trim().isNotEmpty) return true;
    if (_numericFieldChanged(_tipXCtrl.text, _initialTipXRaw)) return true;
    if (_numericFieldChanged(_tipZCtrl.text, _initialTipZRaw)) return true;
    if (_numericFieldChanged(_exactThickCtrl.text, _initialExactRaw)) {
      return true;
    }
    return _buildCurrentDraft() != _initialBaseline;
  }

  List<String> _mergedTagsWithPendingInput() {
    final result = List<String>.from(_tags);
    final pendingClean = VietnameseSearchNormalizer.cleanTagDisplay(
      _tagInputCtrl.text,
    );
    if (pendingClean.isNotEmpty) {
      final pendingKey =
          VietnameseSearchNormalizer.tagDuplicateKey(pendingClean);
      final exists = result.any(
        (t) => VietnameseSearchNormalizer.tagDuplicateKey(t) == pendingKey,
      );
      if (!exists) {
        result.add(pendingClean);
      }
    }
    return List<String>.unmodifiable(result);
  }

  void _addTag(String raw) {
    final clean = VietnameseSearchNormalizer.cleanTagDisplay(raw);
    if (clean.isEmpty) return;
    final key = VietnameseSearchNormalizer.tagDuplicateKey(clean);
    final alreadyExists = _tags.any(
      (t) => VietnameseSearchNormalizer.tagDuplicateKey(t) == key,
    );
    setState(() {
      if (!alreadyExists) {
        _tags.add(clean);
      }
      _tagInputCtrl.clear();
    });
  }

  void _removeTag(int index) {
    setState(() {
      _tags.removeAt(index);
    });
  }

  Future<bool> _saveArticle({bool? forceDraft}) async {
    if (_isBusy) return false;
    FocusManager.instance.primaryFocus?.unfocus();

    final numericError = _firstNumericValidationError();
    final formError = numericError ?? _sourceUrlError;
    if (formError != null) {
      setState(() {});
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            numericError != null
                ? 'Dữ liệu số chưa hợp lệ'
                : 'Liên kết nguồn chưa hợp lệ',
          ),
          content: Text(formError),
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

    _newlyStagedAssetIds.clear();
    _savedPopped = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã lưu bài ${outcome.article!.code}')),
    );
    Navigator.of(context).pop<Article>(outcome.article);
    return true;
  }

  Future<void> _handleExit() async {
    if (_isBusy) return;
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
      final assetsToDiscard = List<String>.from(_newlyStagedAssetIds);
      _newlyStagedAssetIds.clear();
      _savedPopped = true;
      Navigator.of(context).pop();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await widget.controller.discardDraftAssets(assetsToDiscard);
    } else if (choice == 'save') {
      await _saveArticle();
    }
  }

  Future<void> _openPreview() async {
    if (_isBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final numericError = _firstNumericValidationError();
    final formError = _firstFormValidationError();
    if (formError != null) {
      setState(() {});
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            numericError != null
                ? 'Dữ liệu số chưa hợp lệ'
                : 'Liên kết nguồn chưa hợp lệ',
          ),
          content: Text(formError),
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

    final draft = _buildCurrentDraft();
    var groupName = _primaryGroupId;
    for (final g in widget.controller.groupsForKind(_kind)) {
      if (g.id == _primaryGroupId) {
        groupName = g.name;
        break;
      }
    }
    final collections = widget.existingArticle != null
        ? widget.controller.getCollectionsForArticle(widget.existingArticle!.id)
        : const <Collection>[];

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ArticlePreviewScreen(
          draftArticle: draft,
          groupName: groupName,
          collections: collections,
          assetStore: widget.controller.assetStore,
          onLaunchUrl: widget.onLaunchUrl,
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    if (_isBusy) return;
    setState(() => _isImportingImages = true);
    try {
      final List<({String name, String? path, Uint8List? bytes})> picked;
      try {
        if (widget.imagePickerOverride != null) {
          picked = await widget.imagePickerOverride!();
        } else {
          final picker = ImagePicker();
          final files = await picker.pickMultiImage();
          picked = [
            for (final f in files) (name: f.name, path: f.path, bytes: null),
          ];
        }
      } catch (e) {
        if (mounted && !_isDisposed) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Không thể chọn ảnh'),
              content: Text('Lỗi từ trình chọn ảnh: $e'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (picked.isEmpty || !mounted || _isDisposed) return;

      final errors = <String>[];
      for (final item in picked) {
        if (!mounted || _isDisposed) break;
        try {
          final assetId = _freshUuid();
          final StagedImageAsset staged;
          if (item.bytes != null) {
            staged = await widget.controller.assetStore.stageImageBytes(
              assetId: assetId,
              bytes: item.bytes!,
              originalName: item.name,
            );
          } else if (item.path != null && item.path!.isNotEmpty) {
            staged = await widget.controller.assetStore.stageImageFile(
              assetId: assetId,
              sourceFilePath: item.path!,
              originalName: item.name,
            );
          } else {
            errors.add(
              '${item.name}: Không đọc được đường dẫn hoặc dữ liệu ảnh.',
            );
            continue;
          }
          if (!mounted || _isDisposed) {
            await widget.controller.assetStore
                .discardStagingAssets([staged.assetId]);
            return;
          }
          final captionCtrl = TextEditingController()
            ..addListener(_onFormFieldChanged);
          setState(() {
            _newlyStagedAssetIds.add(staged.assetId);
            _images.add(
              ArticleImageAttachment(
                id: _freshUuid(),
                articleId: _workingArticleId,
                assetId: staged.assetId,
                relativePath: staged.relativePath,
                originalName: staged.originalName,
                mimeType: staged.mimeType,
                sizeBytes: staged.sizeBytes,
                width: staged.width,
                height: staged.height,
                caption: '',
                sortOrder: _images.length,
              ),
            );
            _imageCaptionControllers.add(captionCtrl);
          });
        } catch (e) {
          errors.add('${item.name}: $e');
        }
      }

      if (errors.isNotEmpty && mounted && !_isDisposed) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Không thể thêm một số ảnh'),
            content: Text(errors.join('\n')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isImportingImages = false);
      } else {
        _isImportingImages = false;
      }
    }
  }

  void _moveImage(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _images.length) return;
    setState(() {
      final img = _images.removeAt(index);
      _images.insert(target, img);
      final cap = _imageCaptionControllers.removeAt(index);
      _imageCaptionControllers.insert(target, cap);
    });
  }

  Future<void> _removeImage(int index) async {
    late final ArticleImageAttachment removed;
    setState(() {
      removed = _images.removeAt(index);
      final cap = _imageCaptionControllers.removeAt(index);
      cap.removeListener(_onFormFieldChanged);
      cap.dispose();
    });
    _thumbnailCache.evictByAssetId(removed.assetId);
    final stillUsed = _images.any((i) => i.assetId == removed.assetId);
    if (!stillUsed && _newlyStagedAssetIds.contains(removed.assetId)) {
      _newlyStagedAssetIds.remove(removed.assetId);
      await widget.controller.discardDraftAssets([removed.assetId]);
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
      final capCtrl = TextEditingController()..addListener(_onFormFieldChanged);
      _diagramCaptionControllers.add(capCtrl);
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
      cap.removeListener(_onFormFieldChanged);
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
        final busy = saving || _isImportingImages;
        return PopScope(
          canPop: _savedPopped || (!busy && !_hasUnsavedChanges),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !busy) {
              _handleExit();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                key: const Key('editor_back_button'),
                icon: const Icon(Icons.arrow_back),
                onPressed: busy ? null : _handleExit,
              ),
              title: Text(
                widget.existingArticle == null
                    ? 'Bài viết mới'
                    : 'Sửa ${widget.existingArticle!.code}',
              ),
              actions: [
                IconButton(
                  key: const Key('preview_article_button'),
                  tooltip: 'Xem trước',
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: busy ? null : _openPreview,
                ),
                TextButton(
                  key: const Key('save_draft_button'),
                  onPressed: busy ? null : () => _saveArticle(forceDraft: true),
                  child: const Text('Lưu nháp'),
                ),
                FilledButton(
                  key: const Key('save_article_button'),
                  onPressed:
                      busy ? null : () => _saveArticle(forceDraft: false),
                  child: const Text('Lưu bài'),
                ),
                const SizedBox(width: 8.0),
              ],
            ),
            body: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: 7 + _images.length,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildGeneralInfoSection(groups, saving);
                } else if (index == 1) {
                  return _buildContentSection(saving);
                } else if (index == 2) {
                  return _buildCueSection(saving);
                } else if (index == 3) {
                  return _buildDiagramsSection(saving);
                } else if (index == 4) {
                  return _buildImagesHeader(busy);
                } else if (index < 5 + _images.length) {
                  final imgIndex = index - 5;
                  return _buildImageCard(imgIndex, busy, saving);
                } else if (index == 5 + _images.length) {
                  return _buildSourceSection(saving);
                } else {
                  return const SizedBox(height: 24.0);
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildGeneralInfoSection(List<EditorialGroup> groups, bool saving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        final newGroups = widget.controller.groupsForKind(k);
                        _primaryGroupId = newGroups.isNotEmpty
                            ? newGroups.first.id
                            : DefaultEditorialGroups.unclassifiedIdFor(k);
                      });
                    },
            );
          }).toList(),
        ),
        const SizedBox(height: 12.0),
        TextField(
          key: const Key('article_title_input'),
          controller: _titleCtrl,
          enabled: !saving,
          decoration: const InputDecoration(
            labelText: 'Tên bài viết *',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10.0),
        TextField(
          key: const Key('article_summary_input'),
          controller: _summaryCtrl,
          enabled: !saving,
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
        const SizedBox(height: 12.0),
        const Text(
          'Thẻ (tùy chọn)',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6.0),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('tag_input'),
                controller: _tagInputCtrl,
                enabled: !saving,
                decoration: const InputDecoration(
                  labelText: 'Thêm thẻ (vd: cu-lê, trô kéo)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: saving ? null : _addTag,
              ),
            ),
            const SizedBox(width: 8.0),
            FilledButton.tonal(
              key: const Key('add_tag_button'),
              onPressed: saving ? null : () => _addTag(_tagInputCtrl.text),
              child: const Text('Thêm'),
            ),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 6.0,
            runSpacing: 4.0,
            children: [
              for (var i = 0; i < _tags.length; i++)
                InputChip(
                  key: Key('article_tag_chip_$i'),
                  label: Text(_tags[i]),
                  onDeleted: saving ? null : () => _removeTag(i),
                ),
            ],
          ),
        ],
        Builder(
          builder: (context) {
            final activeKeys = _tags
                .map(VietnameseSearchNormalizer.tagDuplicateKey)
                .toSet();
            final suggestions = widget.controller
                .suggestTags(_tagInputCtrl.text)
                .where(
                  (s) => !activeKeys.contains(
                    VietnameseSearchNormalizer.tagDuplicateKey(s),
                  ),
                )
                .take(8)
                .toList(growable: false);
            if (suggestions.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Wrap(
                spacing: 6.0,
                runSpacing: 4.0,
                children: [
                  for (final sug in suggestions)
                    ActionChip(
                      label: Text('+ $sug'),
                      onPressed: saving ? null : () => _addTag(sug),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildContentSection(bool saving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          enabled: !saving,
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
          enabled: !saving,
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
                        _stepControllers.add(
                          TextEditingController()
                            ..addListener(_onFormFieldChanged),
                        );
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
                    enabled: !saving,
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
                            c.removeListener(_onFormFieldChanged);
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
          enabled: !saving,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Lưu ý / Lỗi thường gặp',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildCueSection(bool saving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Giá trị chạm chính xác (0 đến 1, vd: 0.45)',
              errorText: _exactThicknessError,
              isDense: true,
              border: const OutlineInputBorder(),
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
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Mũi cơ X (mm, + phải / - trái)',
                  errorText: _tipXError,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: TextField(
                key: const Key('stroke_tip_z_input'),
                controller: _tipZCtrl,
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Mũi cơ Z (mm, + trên / - dưới)',
                  errorText: _tipZError,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6.0),
        Builder(
          builder: (context) {
            final parsedX = _tryParseFiniteDouble(_tipXCtrl.text);
            final parsedZ = _tryParseFiniteDouble(_tipZCtrl.text);
            final xLabel = parsedX == null
                ? 'Chờ số hợp lệ'
                : CueTipConvention.describeAxisOffset(
                    parsedX,
                    positiveLabel: 'Phải',
                    negativeLabel: 'Trái',
                  );
            final zLabel = parsedZ == null
                ? 'Chờ số hợp lệ'
                : CueTipConvention.describeAxisOffset(
                    parsedZ,
                    positiveLabel: 'Trên',
                    negativeLabel: 'Dưới',
                  );
            return Text(
              'Quy ước 4 mức biên tập: Ngang $xLabel • Dọc $zLabel',
              style: Theme.of(context).textTheme.bodySmall,
            );
          },
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
          enabled: !saving,
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
          enabled: !saving,
          decoration: const InputDecoration(
            labelText: 'Kiểu ra cơ (văn bản)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildDiagramsSection(bool saving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                        onPressed: (saving || i == _diagrams.length - 1)
                            ? null
                            : () => _moveDiagram(i, 1),
                      ),
                      IconButton(
                        key: Key('delete_diagram_$i'),
                        tooltip: 'Xóa sơ đồ',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: saving ? null : () => _removeDiagram(i),
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
                    enabled: !saving,
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
      ],
    );
  }

  Widget _buildImagesHeader(bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Ảnh đính kèm (${_images.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            FilledButton.tonalIcon(
              key: const Key('add_image_button'),
              onPressed: busy ? null : _pickImages,
              icon: _isImportingImages
                  ? const SizedBox(
                      width: 16.0,
                      height: 16.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _isImportingImages ? 'Đang xử lý...' : 'Thêm ảnh',
              ),
            ),
          ],
        ),
        if (_isImportingImages) ...[
          const SizedBox(height: 8.0),
          const LinearProgressIndicator(
            key: Key('importing_images_banner'),
          ),
        ],
        const SizedBox(height: 8.0),
      ],
    );
  }

  Widget _buildImageCard(int i, bool busy, bool saving) {
    return Card(
      key: Key('editor_image_card_$i'),
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Ảnh ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  key: Key('image_up_$i'),
                  tooltip: 'Đưa lên',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: (busy || i == 0) ? null : () => _moveImage(i, -1),
                ),
                IconButton(
                  key: Key('image_down_$i'),
                  tooltip: 'Đưa xuống',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: (busy || i == _images.length - 1)
                      ? null
                      : () => _moveImage(i, 1),
                ),
                IconButton(
                  key: Key('delete_image_$i'),
                  tooltip: 'Xóa ảnh',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy ? null : () => _removeImage(i),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EditorImageThumbnail(
                  key: ValueKey('editor_thumb_${_images[i].assetId}'),
                  image: _images[i],
                  assetStore: widget.controller.assetStore,
                  cache: _thumbnailCache,
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _images[i].originalName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        '${_images[i].width ?? '?'}×${_images[i].height ?? '?'} · '
                        '${(_images[i].sizeBytes / 1024).toStringAsFixed(1)} KB',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            TextField(
              key: Key('image_caption_input_$i'),
              controller: _imageCaptionControllers[i],
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'Chú thích ảnh',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceSection(bool saving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          enabled: !saving,
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
                enabled: !saving,
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
                enabled: !saving,
                decoration: const InputDecoration(
                  labelText: 'Số trang',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        TextField(
          key: const Key('article_source_url_input'),
          controller: _sourceUrlCtrl,
          enabled: !saving,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Liên kết nguồn (http:// hoặc https://)',
            errorText: _sourceUrlError,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// Bộ đệm LRU cho ảnh thumbnail đính kèm trong editor.
/// Giới hạn số lượng mục (mặc định 20), giải phóng khi bỏ ảnh hoặc đóng form.
class EditorThumbnailCache {
  final int maxEntries;
  final Map<String, Uint8List?> _entries = <String, Uint8List?>{};

  EditorThumbnailCache({this.maxEntries = 20});

  int get length => _entries.length;

  bool containsKey(String key) => _entries.containsKey(key);

  Uint8List? get(String key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key);
    _entries[key] = value;
    return value;
  }

  void put(String key, Uint8List? bytes) {
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    } else if (_entries.length >= maxEntries) {
      final oldestKey = _entries.keys.first;
      _entries.remove(oldestKey);
    }
    _entries[key] = bytes;
  }

  void evict(String key) {
    _entries.remove(key);
  }

  void evictByAssetId(String assetId) {
    _entries.removeWhere((k, _) => k.startsWith('$assetId|') || k == assetId);
  }

  void clear() {
    _entries.clear();
  }
}

/// Widget tải thumbnail theo nhu cầu (chỉ tải khi widget được mount/hiển thị).
/// Đọc tệp bất đồng bộ trên I/O worker, tạo thumbnail nhỏ (160px) vào LRU cache
/// và đóng handle ngay lập tức để không giữ file lock trên Windows.
class _EditorImageThumbnail extends StatefulWidget {
  final ArticleImageAttachment image;
  final ArticleAssetStore assetStore;
  final EditorThumbnailCache cache;

  const _EditorImageThumbnail({
    super.key,
    required this.image,
    required this.assetStore,
    required this.cache,
  });

  @override
  State<_EditorImageThumbnail> createState() => _EditorImageThumbnailState();
}

class _EditorImageThumbnailState extends State<_EditorImageThumbnail> {
  Uint8List? _bytes;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    final key = '${widget.image.assetId}|${widget.image.relativePath}';
    final cached = widget.cache.get(key);
    if (cached != null) {
      _bytes = cached;
      _isLoading = false;
    } else {
      _loadThumbnail();
    }
  }

  @override
  void didUpdateWidget(covariant _EditorImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.assetId != widget.image.assetId ||
        oldWidget.image.relativePath != widget.image.relativePath) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final key = '${widget.image.assetId}|${widget.image.relativePath}';
    final cached = widget.cache.get(key);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _bytes = cached;
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    try {
      final file = await widget.assetStore.findExistingFile(
        assetId: widget.image.assetId,
        relativePath: widget.image.relativePath,
      );
      if (file == null || !await file.exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
        return;
      }

      // Đọc bất đồng bộ trên I/O worker (không dùng readAsBytesSync trên UI isolate)
      final rawBytes = await file.readAsBytes();
      final thumbBytes = await _createThumbnailBytes(rawBytes, targetWidth: 160);

      widget.cache.put(key, thumbBytes);

      if (mounted) {
        setState(() {
          _bytes = thumbBytes;
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  static Future<Uint8List> _createThumbnailBytes(
    Uint8List rawBytes, {
    int targetWidth = 160,
  }) async {
    // Nếu ảnh đã nhỏ (<= 100KB hoặc dummy test bytes), không cần downsample
    if (rawBytes.length <= 100 * 1024) {
      return rawBytes;
    }
    try {
      final codec = await ui.instantiateImageCodec(
        rawBytes,
        targetWidth: targetWidth,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (_) {
      // Mock bytes hoặc codec không giải mã được
    }
    return rawBytes;
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(
        width: 88.0,
        height: 88.0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          _hasError
              ? Icons.broken_image_outlined
              : (_isLoading ? Icons.image_outlined : Icons.broken_image_outlined),
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6.0),
      child: Image.memory(
        _bytes!,
        width: 88.0,
        height: 88.0,
        cacheWidth: 160,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 88.0,
          height: 88.0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

