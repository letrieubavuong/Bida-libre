import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../repositories/article_asset_store.dart';
import 'article_document_renderer.dart';
import 'stroke_parameter_widgets.dart';

/// Trình soạn thảo tài liệu bài viết linh hoạt theo kiến trúc khối (Phase 7).
/// Cho phép thêm, xóa, sắp xếp, di chuyển (kèm di chuyển cả phần con của đề mục),
/// nhân bản, đổi loại khối, và undo/redo cấp tài liệu.
class ArticleDocumentEditor extends StatefulWidget {
  final Article article;
  final ArticleDocument initialDocument;
  final ArticleAssetStore assetStore;
  final void Function(ArticleDocument doc)? onDocumentChanged;
  final VoidCallback? onAddDiagramRequested;
  final void Function(int index)? onEditDiagramRequested;
  final VoidCallback? onAddImageRequested;

  const ArticleDocumentEditor({
    super.key,
    required this.article,
    required this.initialDocument,
    required this.assetStore,
    this.onDocumentChanged,
    this.onAddDiagramRequested,
    this.onEditDiagramRequested,
    this.onAddImageRequested,
  });

  @override
  State<ArticleDocumentEditor> createState() => ArticleDocumentEditorState();
}

class ArticleDocumentEditorState extends State<ArticleDocumentEditor> {
  late List<ArticleBlock> _blocks;
  final List<List<ArticleBlock>> _undoStack = [];
  final List<List<ArticleBlock>> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _blocks = List<ArticleBlock>.from(widget.initialDocument.blocks);
  }

  ArticleDocument get currentDocument => ArticleDocument(
        schemaVersion: ArticleDocument.currentSchemaVersion,
        blocks: List.unmodifiable(_blocks),
      );

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _pushHistory() {
    _undoStack.add(List<ArticleBlock>.from(_blocks));
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    setState(() {
      _redoStack.add(List<ArticleBlock>.from(_blocks));
      _blocks = _undoStack.removeLast();
    });
    _notifyChanged();
  }

  void redo() {
    if (!canRedo) return;
    setState(() {
      _undoStack.add(List<ArticleBlock>.from(_blocks));
      _blocks = _redoStack.removeLast();
    });
    _notifyChanged();
  }

  void _notifyChanged() {
    widget.onDocumentChanged?.call(currentDocument);
  }

  String _generateBlockId(String prefix) {
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_blocks.length}';
  }

  void _insertBlockAt(int index, ArticleBlock block) {
    _pushHistory();
    setState(() {
      _blocks.insert(index.clamp(0, _blocks.length), block);
    });
    _notifyChanged();
  }

  void _updateBlockAt(int index, ArticleBlock newBlock) {
    if (index < 0 || index >= _blocks.length) return;
    _pushHistory();
    setState(() {
      _blocks[index] = newBlock;
    });
    _notifyChanged();
  }

  void _removeBlockAt(int index) {
    if (index < 0 || index >= _blocks.length) return;
    _pushHistory();
    setState(() {
      _blocks.removeAt(index);
    });
    _notifyChanged();
  }

  void _duplicateBlockAt(int index) {
    if (index < 0 || index >= _blocks.length) return;
    _pushHistory();
    final orig = _blocks[index];
    final copy = orig.copyWith(id: _generateBlockId('copy_${orig.type.code}'));
    setState(() {
      _blocks.insert(index + 1, copy);
    });
    _notifyChanged();
  }

  void _moveBlock(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _blocks.length) return;
    _pushHistory();
    setState(() {
      final item = _blocks.removeAt(index);
      _blocks.insert(target, item);
    });
    _notifyChanged();
  }

  /// Di chuyển cả section con của Đề mục (Heading và tất cả khối con tới Heading cùng/cao cấp hơn).
  void _moveHeadingSection(int headingIndex, int delta) {
    if (headingIndex < 0 || headingIndex >= _blocks.length) return;
    final block = _blocks[headingIndex];
    if (block.type != ArticleBlockType.heading) return;
    final headingLevel = (block.data as HeadingBlockData).level;

    // Tìm phạm vi của section con
    int sectionEnd = headingIndex + 1;
    while (sectionEnd < _blocks.length) {
      final b = _blocks[sectionEnd];
      if (b.type == ArticleBlockType.heading) {
        final lvl = (b.data as HeadingBlockData).level;
        if (lvl <= headingLevel) break;
      }
      sectionEnd++;
    }

    final sectionBlocks = _blocks.sublist(headingIndex, sectionEnd);

    if (delta > 0) {
      // Di chuyển xuống qua khối/section tiếp theo
      if (sectionEnd >= _blocks.length) return; // Đã ở cuối
      int nextSectionEnd = sectionEnd + 1;
      if (_blocks[sectionEnd].type == ArticleBlockType.heading) {
        final nextLevel = (_blocks[sectionEnd].data as HeadingBlockData).level;
        while (nextSectionEnd < _blocks.length) {
          final b = _blocks[nextSectionEnd];
          if (b.type == ArticleBlockType.heading &&
              (b.data as HeadingBlockData).level <= nextLevel) {
            break;
          }
          nextSectionEnd++;
        }
      }
      _pushHistory();
      setState(() {
        _blocks.removeRange(headingIndex, sectionEnd);
        final insertPos = headingIndex + (nextSectionEnd - sectionEnd);
        _blocks.insertAll(insertPos.clamp(0, _blocks.length), sectionBlocks);
      });
      _notifyChanged();
    } else if (delta < 0) {
      // Di chuyển lên trước section/khối trước đó
      if (headingIndex == 0) return;
      int prevSectionStart = headingIndex - 1;
      // Nếu khối trước là một phần tử của section trước, tìm đầu section trước đó
      while (prevSectionStart > 0 &&
          _blocks[prevSectionStart].type != ArticleBlockType.heading) {
        prevSectionStart--;
      }
      _pushHistory();
      setState(() {
        _blocks.removeRange(headingIndex, sectionEnd);
        _blocks.insertAll(prevSectionStart, sectionBlocks);
      });
      _notifyChanged();
    }
  }

  void _showAddBlockSheet(BuildContext context, int insertIndex) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    'Thêm khối nội dung',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _buildBlockTypeTile(
                        icon: Icons.title,
                        title: 'Đề mục (Heading)',
                        subtitle: 'Phân cấp nội dung (Cấp 1 đến 6, tự động đánh số)',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showHeadingConfigDialog(context, insertIndex);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.notes,
                        title: 'Đoạn văn (Paragraph)',
                        subtitle: 'Văn bản phong phú, định dạng đậm, nghiêng, liên kết',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showParagraphConfigDialog(context, insertIndex);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.call_to_action_outlined,
                        title: 'Khung ghi chú (Callout)',
                        subtitle: 'Ghi chú, Chú ý, Ví dụ, Mẹo, Lỗi thường gặp',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showCalloutConfigDialog(context, insertIndex);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.format_list_bulleted,
                        title: 'Danh sách không thứ tự (Bullet List)',
                        subtitle: 'Các mục bullet lồng nhau theo cấp',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showListConfigDialog(context, insertIndex, isOrdered: false);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.format_list_numbered,
                        title: 'Danh sách có thứ tự (Ordered List)',
                        subtitle: 'Các bước thực hiện đánh số (1., 2., ... hoặc a., b., ...)',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showListConfigDialog(context, insertIndex, isOrdered: true);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.image_outlined,
                        title: 'Ảnh đính kèm',
                        subtitle: 'Chèn ảnh nguồn từ danh sách ảnh đính kèm',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showImagePickerBlockDialog(context, insertIndex);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.video_collection_outlined,
                        title: 'Video YouTube',
                        subtitle: 'Dán URL YouTube (xem trước thumbnail, phát video)',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showYouTubeConfigDialog(context, insertIndex);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.sports_tennis,
                        title: 'Sơ đồ hình bi',
                        subtitle: 'Chèn sơ đồ đường bi tương tác từ bài viết',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showDiagramPickerBlockDialog(context, insertIndex);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.tune,
                        title: 'Thẻ thông số cách đánh',
                        subtitle: 'Chạm trái 12 vạch, Ép phê, Lực đánh tĩnh',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showStrokeConfigDialog(context, insertIndex);
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.horizontal_rule,
                        title: 'Đường phân cách (Divider)',
                        subtitle: 'Vạch ngăn cách thẩm mỹ giữa các phần',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _insertBlockAt(
                            insertIndex,
                            ArticleBlock(
                              id: _generateBlockId('div'),
                              type: ArticleBlockType.divider,
                              data: const DividerBlockData(),
                            ),
                          );
                        },
                      ),
                      _buildBlockTypeTile(
                        icon: Icons.code,
                        title: 'Công thức / Ghi chú mã',
                        subtitle: 'Hiển thị công thức bộ số hoặc cú pháp',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showCodeFormulaDialog(context, insertIndex);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBlockTypeTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.0)),
      onTap: onTap,
    );
  }

  // --- DIALOGS CẤU HÌNH CÁC KHỐI ---

  void _showHeadingConfigDialog(BuildContext context, int insertIndex, [ArticleBlock? editing]) {
    final prevData = editing?.data as HeadingBlockData?;
    int level = prevData?.level ?? 1;
    bool isNumbered = prevData?.isNumbered ?? true;
    final textCtrl = TextEditingController(text: prevData?.text ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text(editing == null ? 'Thêm Đề mục' : 'Sửa Đề mục'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: textCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tiêu đề đề mục',
                        hintText: 'Nhập tiêu đề...',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16.0),
                    const Text('Cấp độ đề mục:'),
                    Wrap(
                      spacing: 8.0,
                      children: [1, 2, 3, 4].map((l) {
                        return ChoiceChip(
                          label: Text('Cấp $l'),
                          selected: level == l,
                          onSelected: (selected) {
                            if (selected) setDialogState(() => level = l);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8.0),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tự động đánh số'),
                      value: isNumbered,
                      onChanged: (val) => setDialogState(() => isNumbered = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () {
                    final text = textCtrl.text.trim();
                    if (text.isEmpty) return;
                    Navigator.of(ctx).pop();
                    final block = ArticleBlock(
                      id: editing?.id ?? _generateBlockId('h'),
                      type: ArticleBlockType.heading,
                      data: HeadingBlockData(
                        level: level,
                        text: text,
                        isNumbered: isNumbered,
                      ),
                    );
                    if (editing == null) {
                      _insertBlockAt(insertIndex, block);
                    } else {
                      _updateBlockAt(insertIndex, block);
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showParagraphConfigDialog(BuildContext context, int insertIndex, [ArticleBlock? editing]) {
    final prevData = editing?.data as ParagraphBlockData?;
    final textCtrl = TextEditingController(text: prevData?.text ?? '');
    final spans = List<InlineSpanStyle>.from(prevData?.spans ?? []);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text(editing == null ? 'Thêm Đoạn văn' : 'Sửa Đoạn văn'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: textCtrl,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Nội dung văn bản',
                          hintText: 'Nhập nội dung đoạn văn...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12.0),
                      Text(
                        'Định dạng áp dụng cho đoạn chữ (${spans.length} vùng):',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                      ),
                      const SizedBox(height: 6.0),
                      Wrap(
                        spacing: 6.0,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.format_bold, size: 16.0),
                            label: const Text('Thêm Đậm'),
                            onPressed: () {
                              _promptAddInlineStyle(
                                dialogCtx,
                                textCtrl.text,
                                InlineStyle.bold,
                                (s) => setDialogState(() => spans.add(s)),
                              );
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.format_italic, size: 16.0),
                            label: const Text('Thêm Nghiêng'),
                            onPressed: () {
                              _promptAddInlineStyle(
                                dialogCtx,
                                textCtrl.text,
                                InlineStyle.italic,
                                (s) => setDialogState(() => spans.add(s)),
                              );
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.link, size: 16.0),
                            label: const Text('Thêm Link'),
                            onPressed: () {
                              _promptAddLinkStyle(
                                dialogCtx,
                                textCtrl.text,
                                (s) => setDialogState(() => spans.add(s)),
                              );
                            },
                          ),
                        ],
                      ),
                      if (spans.isNotEmpty) ...[
                        const SizedBox(height: 8.0),
                        for (var i = 0; i < spans.length; i++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Vùng [${spans[i].start}..${spans[i].end}]: '
                              '${spans[i].styles.map((e) => e.name).join(", ")}'
                              '${spans[i].url != null ? " (${spans[i].url})" : ""}',
                              style: const TextStyle(fontSize: 12.0),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 16.0),
                              onPressed: () => setDialogState(() => spans.removeAt(i)),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () {
                    final text = textCtrl.text;
                    if (text.trim().isEmpty) return;
                    Navigator.of(ctx).pop();
                    final block = ArticleBlock(
                      id: editing?.id ?? _generateBlockId('p'),
                      type: ArticleBlockType.paragraph,
                      data: ParagraphBlockData(
                        text: text,
                        spans: spans,
                      ),
                    );
                    if (editing == null) {
                      _insertBlockAt(insertIndex, block);
                    } else {
                      _updateBlockAt(insertIndex, block);
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _promptAddInlineStyle(
    BuildContext context,
    String fullText,
    InlineStyle style,
    void Function(InlineSpanStyle span) onAdded,
  ) {
    final startCtrl = TextEditingController(text: '0');
    final endCtrl = TextEditingController(text: fullText.length.toString());

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Áp dụng ${style.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Vị trí bắt đầu (Ký tự thứ)'),
            ),
            TextField(
              controller: endCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Vị trí kết thúc'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final start = int.tryParse(startCtrl.text) ?? 0;
              final end = int.tryParse(endCtrl.text) ?? fullText.length;
              if (end > start) {
                onAdded(InlineSpanStyle(start: start, end: end, styles: {style}));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _promptAddLinkStyle(
    BuildContext context,
    String fullText,
    void Function(InlineSpanStyle span) onAdded,
  ) {
    final startCtrl = TextEditingController(text: '0');
    final endCtrl = TextEditingController(text: fullText.length.toString());
    final urlCtrl = TextEditingController(text: 'https://');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm liên kết (Link)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'Địa chỉ URL'),
            ),
            TextField(
              controller: startCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Vị trí bắt đầu'),
            ),
            TextField(
              controller: endCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Vị trí kết thúc'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final start = int.tryParse(startCtrl.text) ?? 0;
              final end = int.tryParse(endCtrl.text) ?? fullText.length;
              final url = urlCtrl.text.trim();
              if (end > start && url.isNotEmpty) {
                onAdded(
                  InlineSpanStyle(
                    start: start,
                    end: end,
                    styles: {InlineStyle.link},
                    url: url,
                  ),
                );
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showCalloutConfigDialog(BuildContext context, int insertIndex, [ArticleBlock? editing]) {
    final prevData = editing?.data as CalloutBlockData?;
    var preset = prevData?.preset ?? CalloutPreset.note;
    final titleCtrl = TextEditingController(text: prevData?.title ?? '');
    final contentCtrl = TextEditingController(text: prevData?.content ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text(editing == null ? 'Thêm Khung ghi chú' : 'Sửa Khung ghi chú'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Kiểu khung ghi chú (Preset):'),
                    const SizedBox(height: 6.0),
                    DropdownButton<CalloutPreset>(
                      value: preset,
                      isExpanded: true,
                      items: CalloutPreset.values.map((p) {
                        return DropdownMenuItem(
                          value: p,
                          child: Text(p.defaultLabel),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => preset = val);
                      },
                    ),
                    const SizedBox(height: 12.0),
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Tiêu đề khung (để trống sẽ lấy mặc định)',
                        hintText: preset.defaultLabel,
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    TextField(
                      controller: contentCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Nội dung ghi chú',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
                FilledButton(
                  onPressed: () {
                    final content = contentCtrl.text.trim();
                    if (content.isEmpty) return;
                    Navigator.of(ctx).pop();
                    final block = ArticleBlock(
                      id: editing?.id ?? _generateBlockId('callout'),
                      type: ArticleBlockType.callout,
                      data: CalloutBlockData(
                        preset: preset,
                        title: titleCtrl.text.trim().isEmpty ? null : titleCtrl.text.trim(),
                        content: content,
                      ),
                    );
                    if (editing == null) {
                      _insertBlockAt(insertIndex, block);
                    } else {
                      _updateBlockAt(insertIndex, block);
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showListConfigDialog(BuildContext context, int insertIndex, {required bool isOrdered, ArticleBlock? editing}) {
    List<ListItemData> items = [];
    if (editing != null) {
      if (isOrdered) {
        items = List<ListItemData>.from((editing.data as OrderedListBlockData).items);
      } else {
        items = List<ListItemData>.from((editing.data as BulletListBlockData).items);
      }
    }
    if (items.isEmpty) {
      items.add(const ListItemData(text: '', level: 0));
    }

    final controllers = items.map((i) => TextEditingController(text: i.text)).toList();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text(isOrdered ? 'Danh sách có thứ tự' : 'Danh sách không thứ tự'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Text(
                                isOrdered ? '${i + 1}. ' : '• ',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: controllers[i],
                                  decoration: InputDecoration(
                                    hintText: 'Mục ${i + 1}...',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_right),
                                tooltip: 'Tăng thụt lề',
                                onPressed: () {
                                  setDialogState(() {
                                    items[i] = ListItemData(
                                      text: controllers[i].text,
                                      level: (items[i].level + 1).clamp(0, 3),
                                    );
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_left),
                                tooltip: 'Giảm thụt lề',
                                onPressed: () {
                                  setDialogState(() {
                                    items[i] = ListItemData(
                                      text: controllers[i].text,
                                      level: (items[i].level - 1).clamp(0, 3),
                                    );
                                  });
                                },
                              ),
                              if (items.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () {
                                    setDialogState(() {
                                      items.removeAt(i);
                                      controllers.removeAt(i);
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm mục'),
                        onPressed: () {
                          setDialogState(() {
                            items.add(const ListItemData(text: '', level: 0));
                            controllers.add(TextEditingController());
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
                FilledButton(
                  onPressed: () {
                    final finalItems = <ListItemData>[];
                    for (var i = 0; i < items.length; i++) {
                      final t = controllers[i].text.trim();
                      if (t.isNotEmpty) {
                        finalItems.add(ListItemData(text: t, level: items[i].level));
                      }
                    }
                    if (finalItems.isEmpty) return;
                    Navigator.of(ctx).pop();
                    final ArticleBlock block;
                    if (isOrdered) {
                      block = ArticleBlock(
                        id: editing?.id ?? _generateBlockId('ordered'),
                        type: ArticleBlockType.orderedList,
                        data: OrderedListBlockData(items: finalItems),
                      );
                    } else {
                      block = ArticleBlock(
                        id: editing?.id ?? _generateBlockId('bullet'),
                        type: ArticleBlockType.bulletList,
                        data: BulletListBlockData(items: finalItems),
                      );
                    }
                    if (editing == null) {
                      _insertBlockAt(insertIndex, block);
                    } else {
                      _updateBlockAt(insertIndex, block);
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showImagePickerBlockDialog(BuildContext context, int insertIndex, [ArticleBlock? editing]) {
    if (widget.article.images.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chưa có ảnh đính kèm'),
          content: const Text(
            'Bài viết chưa có ảnh đính kèm nào. Vui lòng bấm "Thêm ảnh" ở mục đính kèm trước khi chèn khối ảnh.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onAddImageRequested?.call();
              },
              child: const Text('Thêm ảnh đính kèm'),
            ),
          ],
        ),
      );
      return;
    }

    final prevData = editing?.data as ImageBlockData?;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(editing == null ? 'Chọn ảnh đính kèm' : 'Thay đổi ảnh đính kèm'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.article.images.length,
              itemBuilder: (context, index) {
                final img = widget.article.images[index];
                return ListTile(
                  leading: const Icon(Icons.image),
                  title: Text(img.originalName),
                  subtitle: Text(img.caption.isNotEmpty ? img.caption : 'Chưa có chú thích'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final block = ArticleBlock(
                      id: editing?.id ?? _generateBlockId('img'),
                      type: ArticleBlockType.image,
                      data: ImageBlockData(
                        assetId: img.assetId,
                        caption: img.caption,
                        displaySize: prevData?.displaySize ?? ImageDisplaySize.large,
                      ),
                    );
                    if (editing == null) {
                      _insertBlockAt(insertIndex, block);
                    } else {
                      _updateBlockAt(insertIndex, block);
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  void _showYouTubeConfigDialog(BuildContext context, int insertIndex, [ArticleBlock? editing]) {
    final prevData = editing?.data as YouTubeBlockData?;
    final urlCtrl = TextEditingController(text: prevData?.url ?? '');
    final captionCtrl = TextEditingController(text: prevData?.caption ?? '');
    String? errorText;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text(editing == null ? 'Thêm Video YouTube' : 'Sửa Video YouTube'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlCtrl,
                    decoration: InputDecoration(
                      labelText: 'Đường dẫn YouTube',
                      hintText: 'https://www.youtube.com/watch?v=...',
                      errorText: errorText,
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12.0),
                  TextField(
                    controller: captionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Chú thích video (tùy chọn)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
                FilledButton(
                  onPressed: () {
                    final blockData = YouTubeBlockData.fromInputUrl(
                      urlCtrl.text.trim(),
                      caption: captionCtrl.text.trim(),
                    );
                    if (blockData == null) {
                      setDialogState(() {
                        errorText = 'Đường dẫn YouTube không hợp lệ hoặc chứa mã độc.';
                      });
                      return;
                    }
                    Navigator.of(ctx).pop();
                    final block = ArticleBlock(
                      id: editing?.id ?? _generateBlockId('yt'),
                      type: ArticleBlockType.youtubeVideo,
                      data: blockData,
                    );
                    if (editing == null) {
                      _insertBlockAt(insertIndex, block);
                    } else {
                      _updateBlockAt(insertIndex, block);
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDiagramPickerBlockDialog(BuildContext context, int insertIndex, [ArticleBlock? editing]) {
    if (widget.article.diagrams.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chưa có sơ đồ'),
          content: const Text(
            'Bài viết chưa có sơ đồ nào. Bạn có thể mở bàn vẽ để tạo sơ đồ mới.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onAddDiagramRequested?.call();
              },
              child: const Text('Tạo sơ đồ mới'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(editing == null ? 'Chọn sơ đồ' : 'Thay đổi sơ đồ'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.article.diagrams.length,
              itemBuilder: (context, index) {
                final diag = widget.article.diagrams[index];
                return ListTile(
                  leading: const Icon(Icons.sports_tennis),
                  title: Text('Sơ đồ ${index + 1}'),
                  subtitle: Text(diag.caption.isNotEmpty ? diag.caption : 'Chưa có chú thích'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final block = ArticleBlock(
                      id: editing?.id ?? _generateBlockId('diag'),
                      type: ArticleBlockType.billiardDiagram,
                      data: BilliardDiagramBlockData(
                        diagramId: diag.id,
                        caption: diag.caption,
                      ),
                    );
                    if (editing == null) {
                      _insertBlockAt(insertIndex, block);
                    } else {
                      _updateBlockAt(insertIndex, block);
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  void _showStrokeConfigDialog(BuildContext context, int insertIndex, [ArticleBlock? editing]) {
    final prevData = editing?.data as StrokeParameterBlockData?;
    String? linkedId = prevData?.linkedDiagramId;

    // Lấy thông số ban đầu
    StrokeParameters stroke;
    if (linkedId != null) {
      final diag = widget.article.diagrams.cast<ArticleDiagram?>().firstWhere(
            (d) => d?.id == linkedId,
            orElse: () => null,
          );
      stroke = diag?.scene.effectiveStrokeParameters ??
          prevData?.strokeParameters ??
          widget.article.strokeParameters;
    } else {
      stroke = prevData?.strokeParameters ?? widget.article.strokeParameters;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isLinked = linkedId != null;
            final linkedDiag = isLinked
                ? widget.article.diagrams.cast<ArticleDiagram?>().firstWhere(
                    (d) => d?.id == linkedId,
                    orElse: () => null,
                  )
                : null;
            final currentParams = linkedDiag != null
                ? linkedDiag.scene.effectiveStrokeParameters
                : stroke;

            return AlertDialog(
              title: Text(editing == null ? 'Thêm Thẻ thông số' : 'Sửa Thẻ thông số'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.article.diagrams.isNotEmpty) ...[
                      const Text(
                        'Liên kết với sơ đồ (tùy chọn):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                      ),
                      const SizedBox(height: 4.0),
                      DropdownButton<String?>(
                        value: linkedId,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Không liên kết (Độc lập)')),
                          for (var i = 0; i < widget.article.diagrams.length; i++)
                            DropdownMenuItem(
                              value: widget.article.diagrams[i].id,
                              child: Text('Sơ đồ ${i + 1}${widget.article.diagrams[i].caption.isNotEmpty ? ' - ${widget.article.diagrams[i].caption}' : ''}'),
                            ),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == null && linkedId != null) {
                              // Khi bỏ liên kết, sao chép thông số hiện tại thành bộ độc lập
                              stroke = currentParams;
                            }
                            linkedId = val;
                          });
                        },
                      ),
                      const Divider(height: 20.0),
                    ],

                    if (isLinked) ...[
                      Container(
                        padding: const EdgeInsets.all(10.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withAlpha(80),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.link, size: 18.0, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 6.0),
                                Expanded(
                                  child: Text(
                                    'Đang liên kết: Thông số được đọc trực tiếp từ sơ đồ.',
                                    style: TextStyle(
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6.0),
                            const Text(
                              'Để sửa thông số, vui lòng mở chỉnh sửa sơ đồ tương ứng trên bàn vẽ.',
                              style: TextStyle(fontSize: 12.0),
                            ),
                            if (widget.onEditDiagramRequested != null && linkedDiag != null) ...[
                              const SizedBox(height: 8.0),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.edit, size: 16.0),
                                label: const Text('Mở chỉnh sơ đồ'),
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  final diagIndex = widget.article.diagrams.indexOf(linkedDiag);
                                  if (diagIndex >= 0) {
                                    widget.onEditDiagramRequested!(diagIndex);
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12.0),
                    ],

                    // 1. Chạm trái
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1. Chạm trái: ${currentParams.thicknessSummary}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (!isLinked)
                          TextButton(
                            key: const Key('stroke_config_edit_thickness_button'),
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => HitThicknessDialog(
                                  initialStroke: stroke,
                                  onApply: (res) {
                                    setDialogState(() => stroke = res);
                                  },
                                ),
                              );
                            },
                            child: const Text('Chi tiết'),
                          ),
                      ],
                    ),
                    if (!isLinked) ...[
                      Row(
                        children: [
                          const Text('Độ dày 12 phần: '),
                          DropdownButton<int>(
                            value: (stroke.thicknessMode == HitThicknessMode.twelfths && !stroke.isFullFace)
                                ? stroke.twelfthCount
                                : null,
                            hint: Text(stroke.thicknessSummary),
                            items: List.generate(12, (i) => i + 1).map((k) {
                              return DropdownMenuItem(value: k, child: Text('$k/12'));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  // Khi đổi chạm trái sang k/12 phải đặt đúng thicknessMode!
                                  stroke = stroke.copyWith(
                                    thicknessMode: HitThicknessMode.twelfths,
                                    twelfthCount: val,
                                    isFullFace: false,
                                  );
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10.0),

                    // 2. Ép phê
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '2. Ép phê: ${currentParams.horizontalTipLabel}, ${currentParams.verticalTipLabel}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (!isLinked)
                          TextButton(
                            key: const Key('stroke_config_edit_cue_tip_button'),
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => CueTipDialog(
                                  initialStroke: stroke,
                                  onApply: (res) {
                                    setDialogState(() => stroke = res);
                                  },
                                ),
                              );
                            },
                            child: const Text('Chỉnh ép phê'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10.0),

                    // 3. Lực
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('3. Lực: ${currentParams.forcePercent}%',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (!isLinked)
                          TextButton(
                            key: const Key('stroke_config_edit_force_button'),
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => ForceDialog(
                                  initialStroke: stroke,
                                  onApply: (res) {
                                    setDialogState(() => stroke = res);
                                  },
                                ),
                              );
                            },
                            child: const Text('Chi tiết'),
                          ),
                      ],
                    ),
                    if (!isLinked)
                      Slider(
                        value: (stroke.forcePercent ?? 50).toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        label: '${stroke.forcePercent}%',
                        onChanged: (v) {
                          setDialogState(() {
                            stroke = stroke.copyWith(forcePercent: v.round());
                          });
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    final block = ArticleBlock(
                      id: editing?.id ?? _generateBlockId('stroke'),
                      type: ArticleBlockType.strokeParameter,
                      data: StrokeParameterBlockData(
                        strokeParameters: isLinked ? currentParams : stroke,
                        linkedDiagramId: linkedId,
                      ),
                    );
                    if (editing == null) {
                      _insertBlockAt(insertIndex, block);
                    } else {
                      _updateBlockAt(insertIndex, block);
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCodeFormulaDialog(BuildContext context, int insertIndex, [ArticleBlock? editing]) {
    final prevData = editing?.data as CodeFormulaBlockData?;
    final textCtrl = TextEditingController(text: prevData?.text ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing == null ? 'Thêm Công thức / Mã' : 'Sửa Công thức / Mã'),
        content: TextField(
          controller: textCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Công thức hoặc cú pháp',
            hintText: 'Nhập công thức bộ số, tia ngắm...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final text = textCtrl.text.trim();
              if (text.isEmpty) return;
              Navigator.of(ctx).pop();
              final block = ArticleBlock(
                id: editing?.id ?? _generateBlockId('code'),
                type: ArticleBlockType.codeFormula,
                data: CodeFormulaBlockData(text: text),
              );
              if (editing == null) {
                _insertBlockAt(insertIndex, block);
              } else {
                _updateBlockAt(insertIndex, block);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Thanh công cụ Undo / Redo & Thêm nhanh
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
          child: Row(
            children: [
              IconButton(
                key: const Key('document_undo_button'),
                icon: const Icon(Icons.undo),
                tooltip: 'Hoàn tác (Undo)',
                onPressed: canUndo ? undo : null,
              ),
              IconButton(
                key: const Key('document_redo_button'),
                icon: const Icon(Icons.redo),
                tooltip: 'Làm lại (Redo)',
                onPressed: canRedo ? redo : null,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                key: const Key('document_insert_block_top_button'),
                icon: const Icon(Icons.add, size: 18.0),
                label: const Text('Thêm khối'),
                onPressed: () => _showAddBlockSheet(context, _blocks.length),
              ),
            ],
          ),
        ),

        // Danh sách khối đang soạn
        if (_blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.post_add, size: 48.0, color: Colors.grey.shade400),
                  const SizedBox(height: 12.0),
                  const Text(
                    'Tài liệu chưa có khối nội dung nào.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6.0),
                  const Text('Bấm nút "+ Thêm khối" để bắt đầu soạn bài.'),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _blocks.length,
            itemBuilder: (context, index) {
              final block = _blocks[index];
              return _buildBlockEditorCard(context, index, block);
            },
          ),

        // Nút thêm khối ở cuối tài liệu
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: OutlinedButton.icon(
            key: const Key('document_add_block_bottom_button'),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Chèn nội dung mới vào cuối bài'),
            onPressed: () => _showAddBlockSheet(context, _blocks.length),
          ),
        ),
      ],
    );
  }

  Widget _buildBlockEditorCard(BuildContext context, int index, ArticleBlock block) {
    final isHeading = block.type == ArticleBlockType.heading;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header thanh điều khiển khối
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(50),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12.0)),
            ),
            child: Row(
              children: [
                _buildBlockTypeBadge(block.type),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18.0),
                  tooltip: 'Di chuyển lên',
                  onPressed: index > 0 ? () => _moveBlock(index, -1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18.0),
                  tooltip: 'Di chuyển xuống',
                  onPressed: index < _blocks.length - 1 ? () => _moveBlock(index, 1) : null,
                ),
                if (isHeading)
                  PopupMenuButton<String>(
                    tooltip: 'Di chuyển cả phần con',
                    icon: const Icon(Icons.drive_file_move_outlined, size: 18.0),
                    onSelected: (val) {
                      if (val == 'up') _moveHeadingSection(index, -1);
                      if (val == 'down') _moveHeadingSection(index, 1);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'up', child: Text('Di chuyển cả phần lên')),
                      const PopupMenuItem(value: 'down', child: Text('Di chuyển cả phần xuống')),
                    ],
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18.0),
                  onSelected: (val) {
                    if (val == 'insert_above') _showAddBlockSheet(context, index);
                    if (val == 'insert_below') _showAddBlockSheet(context, index + 1);
                    if (val == 'duplicate') _duplicateBlockAt(index);
                    if (val == 'edit') _editBlock(context, index, block);
                    if (val == 'delete') _removeBlockAt(index);
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
                    const PopupMenuItem(value: 'duplicate', child: Text('Nhân bản')),
                    const PopupMenuItem(value: 'insert_above', child: Text('Chèn lên trên')),
                    const PopupMenuItem(value: 'insert_below', child: Text('Chèn xuống dưới')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Xóa khối', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Nội dung hiển thị xem trước của khối
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: InkWell(
              onTap: () => _editBlock(context, index, block),
              child: _buildBlockPreview(context, block),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockTypeBadge(ArticleBlockType type) {
    final (label, icon) = switch (type) {
      ArticleBlockType.heading => ('Đề mục', Icons.title),
      ArticleBlockType.paragraph => ('Đoạn văn', Icons.notes),
      ArticleBlockType.callout => ('Ghi chú', Icons.call_to_action_outlined),
      ArticleBlockType.bulletList => ('DS chấm tròn', Icons.format_list_bulleted),
      ArticleBlockType.orderedList => ('DS có thứ tự', Icons.format_list_numbered),
      ArticleBlockType.image => ('Ảnh', Icons.image_outlined),
      ArticleBlockType.youtubeVideo => ('YouTube', Icons.video_collection_outlined),
      ArticleBlockType.billiardDiagram => ('Sơ đồ hình bi', Icons.sports_tennis),
      ArticleBlockType.strokeParameter => ('Thông số đánh', Icons.tune),
      ArticleBlockType.divider => ('Đường phân cách', Icons.horizontal_rule),
      ArticleBlockType.codeFormula => ('Công thức / Mã', Icons.code),
      ArticleBlockType.unknown => ('Khác', Icons.extension_outlined),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16.0, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4.0),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildBlockPreview(BuildContext context, ArticleBlock block) {
    // Tận dụng chính ArticleDocumentRenderer để hiển thị nhất quán
    return ArticleDocumentRenderer(
      article: widget.article,
      document: ArticleDocument(blocks: [block]),
      assetStore: widget.assetStore,
    );
  }

  void _editBlock(BuildContext context, int index, ArticleBlock block) {
    switch (block.type) {
      case ArticleBlockType.heading:
        _showHeadingConfigDialog(context, index, block);
      case ArticleBlockType.paragraph:
        _showParagraphConfigDialog(context, index, block);
      case ArticleBlockType.callout:
        _showCalloutConfigDialog(context, index, block);
      case ArticleBlockType.bulletList:
        _showListConfigDialog(context, index, isOrdered: false, editing: block);
      case ArticleBlockType.orderedList:
        _showListConfigDialog(context, index, isOrdered: true, editing: block);
      case ArticleBlockType.image:
        _showImagePickerBlockDialog(context, index, block);
      case ArticleBlockType.youtubeVideo:
        _showYouTubeConfigDialog(context, index, block);
      case ArticleBlockType.billiardDiagram:
        _showDiagramPickerBlockDialog(context, index, block);
      case ArticleBlockType.strokeParameter:
        _showStrokeConfigDialog(context, index, block);
      case ArticleBlockType.codeFormula:
        _showCodeFormulaDialog(context, index, block);
      case ArticleBlockType.divider:
      case ArticleBlockType.unknown:
        break;
    }
  }
}
