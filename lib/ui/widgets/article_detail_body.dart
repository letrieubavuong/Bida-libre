import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../repositories/article_asset_store.dart';
import 'article_document_renderer.dart';
import 'billiard_table_canvas.dart';

/// Thành phần trình bày nội dung bài viết dùng chung cho cả Màn hình Đọc bài
/// và Màn hình Xem trước trước khi lưu (Phase 4C).
class ArticleDetailBody extends StatelessWidget {
  final Article article;
  final String groupName;
  final List<Collection> collections;
  final ArticleAssetStore assetStore;
  final bool isPreview;
  final Future<bool> Function(Uri uri)? onLaunchUrl;

  const ArticleDetailBody({
    super.key,
    required this.article,
    required this.groupName,
    this.collections = const [],
    required this.assetStore,
    this.isPreview = false,
    this.onLaunchUrl,
  });

  Future<void> _openSourceUrl(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liên kết nguồn không hợp lệ.')),
      );
      return;
    }
    final launcher = onLaunchUrl ??
        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    final launched = await launcher(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể mở trình duyệt cho liên kết này.')),
      );
    }
  }

  void _openDiagramViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiagramViewerScreen(
          diagrams: article.diagrams,
          initialIndex: initialIndex,
          articleCode: article.code,
          articleTitle: article.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stroke = article.strokeParameters;
    final cueLabel = switch (stroke.cueBallId) {
      'ball_yellow' => 'Bi vàng',
      'ball_red' => 'Bi đỏ',
      _ => 'Bi trắng',
    };

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 6.0,
          children: [
            Chip(label: Text(article.kind.label)),
            Chip(label: Text(groupName)),
            Chip(label: Text(article.difficulty.label)),
            if (isPreview)
              Chip(
                avatar: const Icon(Icons.visibility_outlined, size: 16.0),
                label: Text(
                  article.code.isEmpty
                      ? 'Bản nháp (xem trước)'
                      : 'Xem trước ${article.code}',
                ),
              )
            else if (article.isDraft)
              const Chip(
                avatar: Icon(Icons.edit_note, size: 16.0),
                label: Text('Bản nháp'),
              ),
          ],
        ),
        if (article.tags.isNotEmpty) ...[
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 6.0,
            runSpacing: 4.0,
            children: article.tags
                .map(
                  (t) => Chip(
                    label: Text('#$t'),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        if (collections.isNotEmpty) ...[
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 6.0,
            runSpacing: 4.0,
            children: collections
                .map(
                  (c) => Chip(
                    avatar: const Icon(
                      Icons.collections_bookmark_outlined,
                      size: 16.0,
                    ),
                    label: Text(c.name),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 12.0),
        Text(
          article.title.trim().isEmpty ? '(Chưa đặt tên bài)' : article.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (article.summary.isNotEmpty) ...[
          const SizedBox(height: 8.0),
          Text(
            article.summary,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
        const SizedBox(height: 16.0),
        if (article.document != null) ...[
          ArticleDocumentRenderer(
            article: article,
            document: article.document!,
            assetStore: assetStore,
            onLaunchUrl: onLaunchUrl,
            onOpenDiagramViewer: (idx) => _openDiagramViewer(context, idx),
          ),
          if (article.images.isNotEmpty &&
              !article.document!.blocks.any((b) => b.type == ArticleBlockType.image)) ...[
            const SizedBox(height: 16.0),
            Text(
              'Ảnh nguồn đính kèm (${article.images.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8.0),
            for (var i = 0; i < article.images.length; i++)
              _ArticleImageCard(
                key: Key('detail_image_card_$i'),
                attachment: article.images[i],
                index: i,
                assetStore: assetStore,
              ),
          ],
        ] else ...[
          if (article.goal.isNotEmpty)
            _DetailSectionCard(
              title: 'Mục tiêu & Tình huống',
              child: Text(article.goal),
            ),
          if (article.content.isNotEmpty)
            _DetailSectionCard(
              title: 'Nội dung giải thích',
              child: Text(article.content),
            ),
          if (article.steps.isNotEmpty)
            _DetailSectionCard(
              title: 'Các bước thực hiện',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < article.steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Text('${i + 1}. ${article.steps[i]}'),
                    ),
                ],
              ),
            ),
          if (article.commonMistakes.isNotEmpty)
            _DetailSectionCard(
              title: 'Lưu ý & Lỗi thường gặp',
              child: Text(article.commonMistakes),
            ),
          _DetailSectionCard(
            title: 'Thông số cách đánh (Tĩnh)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Bi chủ: $cueLabel'),
                Text('• Độ dày & má bi: ${stroke.thicknessSummary}'),
                Text('• Mũi cơ ngang: ${stroke.horizontalTipLabel}'),
                Text('• Mũi cơ dọc: ${stroke.verticalTipLabel}'),
                Text('• Đầu cơ tham chiếu: ${stroke.tipDiameterMm} mm'),
                if (stroke.tipNote.isNotEmpty)
                  Text('• Ghi chú mũi cơ: ${stroke.tipNote}'),
                if (stroke.forceText.isNotEmpty)
                  Text('• Lực đánh: ${stroke.forceText}'),
                if (stroke.strokeStyleText.isNotEmpty)
                  Text('• Kiểu ra cơ: ${stroke.strokeStyleText}'),
              ],
            ),
          ),
          if (article.diagrams.isNotEmpty) ...[
            Text(
              'Sơ đồ (${article.diagrams.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8.0),
            for (var i = 0; i < article.diagrams.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 12.0),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Sơ đồ ${i + 1}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          TextButton.icon(
                            key: Key('open_diagram_viewer_$i'),
                            icon: const Icon(Icons.fullscreen, size: 18.0),
                            label: const Text('Xem lớn'),
                            onPressed: () => _openDiagramViewer(context, i),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      Center(
                        child: InkWell(
                          onTap: () => _openDiagramViewer(context, i),
                          borderRadius: BorderRadius.circular(8.0),
                          child: SizedBox(
                            height: 280.0,
                            child: BilliardTableReadOnlyView(
                              key: Key('readonly_diagram_$i'),
                              scene: article.diagrams[i].scene,
                            ),
                          ),
                        ),
                      ),
                      if (article.diagrams[i].caption.isNotEmpty) ...[
                        const SizedBox(height: 8.0),
                        Text(article.diagrams[i].caption),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          if (article.images.isNotEmpty) ...[
            const SizedBox(height: 4.0),
            Text(
              'Ảnh nguồn đính kèm (${article.images.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8.0),
            for (var i = 0; i < article.images.length; i++)
              _ArticleImageCard(
                key: Key('detail_image_card_$i'),
                attachment: article.images[i],
                index: i,
                assetStore: assetStore,
              ),
          ],
        ],
        if (article.source != null ||
            article.author != null ||
            article.sourcePage != null ||
            article.sourceUrl != null)
          _DetailSectionCard(
            title: 'Nguồn tài liệu',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (article.source != null) Text('• Nguồn: ${article.source}'),
                if (article.author != null) Text('• Tác giả: ${article.author}'),
                if (article.sourcePage != null)
                  Text('• Trang: ${article.sourcePage}'),
                if (article.sourceUrl != null) ...[
                  const SizedBox(height: 6.0),
                  OutlinedButton.icon(
                    key: const Key('open_source_url_button'),
                    onPressed: () => _openSourceUrl(context, article.sourceUrl!),
                    icon: const Icon(Icons.open_in_new, size: 16.0),
                    label: Text(
                      article.sourceUrl!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ArticleImageCard extends StatefulWidget {
  final ArticleImageAttachment attachment;
  final int index;
  final ArticleAssetStore assetStore;

  const _ArticleImageCard({
    super.key,
    required this.attachment,
    required this.index,
    required this.assetStore,
  });

  @override
  State<_ArticleImageCard> createState() => _ArticleImageCardState();
}

class _ArticleImageCardState extends State<_ArticleImageCard> {
  late Future<File?> _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = widget.assetStore.findExistingFile(
      assetId: widget.attachment.assetId,
      relativePath: widget.attachment.relativePath,
    );
  }

  @override
  void didUpdateWidget(covariant _ArticleImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.assetId != widget.attachment.assetId ||
        oldWidget.attachment.relativePath != widget.attachment.relativePath) {
      _fileFuture = widget.assetStore.findExistingFile(
        assetId: widget.attachment.assetId,
        relativePath: widget.attachment.relativePath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ảnh ${widget.index + 1} • ${att.originalName}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8.0),
            FutureBuilder<File?>(
              future: _fileFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 160.0,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final file = snapshot.data;
                if (file == null) {
                  return Container(
                    key: Key('missing_image_${widget.index}'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.broken_image_outlined),
                        SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            'Không tìm thấy tệp ảnh trên máy. Văn bản và sơ đồ của bài vẫn đọc bình thường.',
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return InkWell(
                  key: Key('open_image_viewer_${widget.index}'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ImageViewerScreen(
                          file: file,
                          title: att.originalName,
                          caption: att.caption,
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280.0),
                      child: Image.file(
                        file,
                        cacheWidth: 1080,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Không thể giải mã tệp ảnh này.'),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (att.caption.isNotEmpty) ...[
              const SizedBox(height: 8.0),
              Text(att.caption),
            ],
          ],
        ),
      ),
    );
  }
}

/// Màn hình xem sơ đồ vector lớn với zoom & pan (Phase 6):
/// - Chế độ chỉ đọc hoàn toàn, không thể kéo bi hoặc sửa đường.
/// - Hỗ trợ pinch zoom / 2-finger pan qua InteractiveViewer.
/// - Nút "Vừa màn hình" (Đặt lại góc nhìn) khôi phục ma trận về gốc.
/// - Cho phép chuyển nhanh giữa các sơ đồ của cùng bài viết (nếu có nhiều sơ đồ).
/// - Phân biệt rõ là Sơ đồ vector với Ảnh chụp sách.
class DiagramViewerScreen extends StatefulWidget {
  final List<ArticleDiagram> diagrams;
  final int initialIndex;
  final String articleCode;
  final String articleTitle;

  const DiagramViewerScreen({
    super.key,
    required this.diagrams,
    this.initialIndex = 0,
    required this.articleCode,
    required this.articleTitle,
  });

  @override
  State<DiagramViewerScreen> createState() => _DiagramViewerScreenState();
}

class _DiagramViewerScreenState extends State<DiagramViewerScreen> {
  late int _currentIndex;
  final TransformationController _transCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.diagrams.length - 1);
  }

  @override
  void dispose() {
    _transCtrl.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transCtrl.value = Matrix4.identity();
  }

  void _prevDiagram() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _resetZoom();
      });
    }
  }

  void _nextDiagram() {
    if (_currentIndex < widget.diagrams.length - 1) {
      setState(() {
        _currentIndex++;
        _resetZoom();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.diagrams.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Xem sơ đồ')),
        body: const Center(child: Text('Bài viết không có sơ đồ nào.')),
      );
    }

    final diag = widget.diagrams[_currentIndex];
    final total = widget.diagrams.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.articleCode.isNotEmpty ? widget.articleCode : 'Sơ đồ vector',
              style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
            ),
            Text(
              total > 1
                  ? 'Sơ đồ ${_currentIndex + 1} / $total'
                  : 'Sơ đồ vector (Chỉ đọc)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('reset_diagram_zoom_button'),
            tooltip: 'Vừa màn hình',
            icon: const Icon(Icons.fit_screen),
            onPressed: _resetZoom,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner định danh rõ ràng sơ đồ vector
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.architecture, size: 18.0),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    'Sơ đồ vector chuẩn 1:2 (Chỉ đọc · Phóng to / di chuyển bằng 2 ngón)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
          // Vùng hiển thị sơ đồ có InteractiveViewer
          Expanded(
            child: InteractiveViewer(
              key: const Key('diagram_interactive_viewer'),
              transformationController: _transCtrl,
              minScale: 0.5,
              maxScale: 5.0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: BilliardTableReadOnlyView(
                    scene: diag.scene,
                  ),
                ),
              ),
            ),
          ),
          // Thanh chuyển sơ đồ & chú thích (nếu có nhiều sơ đồ)
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (diag.caption.isNotEmpty) ...[
                    Text(
                      diag.caption,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8.0),
                  ],
                  if (total > 1)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton.filledTonal(
                          key: const Key('prev_diagram_button'),
                          tooltip: 'Sơ đồ trước',
                          onPressed: _currentIndex > 0 ? _prevDiagram : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          'Sơ đồ ${_currentIndex + 1} / $total',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton.filledTonal(
                          key: const Key('next_diagram_button'),
                          tooltip: 'Sơ đồ kế tiếp',
                          onPressed:
                              _currentIndex < total - 1 ? _nextDiagram : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Màn hình xem ảnh lớn, phóng to và di chuyển để đọc trang sách / thế bi.
class ImageViewerScreen extends StatefulWidget {
  final File file;
  final String title;
  final String caption;

  const ImageViewerScreen({
    super.key,
    required this.file,
    required this.title,
    this.caption = '',
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final TransformationController _transCtrl = TransformationController();

  @override
  void dispose() {
    _transCtrl.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transCtrl.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('reset_image_zoom_button'),
            tooltip: 'Vừa màn hình',
            icon: const Icon(Icons.fit_screen),
            onPressed: _resetZoom,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.image, size: 18.0),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    'Ảnh nguồn đính kèm (Ảnh chụp sách/tài liệu · Phóng to / di chuyển bằng 2 ngón)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              key: const Key('image_interactive_viewer'),
              transformationController: _transCtrl,
              minScale: 0.5,
              maxScale: 5.0,
              child: Center(
                child: Image.file(
                  widget.file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text('Không thể hiển thị ảnh.'),
                ),
              ),
            ),
          ),
          if (widget.caption.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Text(widget.caption),
            ),
        ],
      ),
    );
  }
}

class _DetailSectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6.0),
            child,
          ],
        ),
      ),
    );
  }
}

