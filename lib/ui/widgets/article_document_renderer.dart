import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../repositories/article_asset_store.dart';
import 'article_detail_body.dart';
import 'billiard_table_canvas.dart';
import 'stroke_parameter_widgets.dart';

/// Trình hiển thị tài liệu bài viết dạng khối linh hoạt (Phase 7).
/// Dùng chung cho cả màn hình Đọc bài viết (ArticleDetailScreen) và Xem trước (ArticlePreviewScreen).
class ArticleDocumentRenderer extends StatelessWidget {
  final Article article;
  final ArticleDocument document;
  final ArticleAssetStore assetStore;
  final Future<bool> Function(Uri uri)? onLaunchUrl;
  final void Function(int diagramIndex)? onOpenDiagramViewer;

  const ArticleDocumentRenderer({
    super.key,
    required this.article,
    required this.document,
    required this.assetStore,
    this.onLaunchUrl,
    this.onOpenDiagramViewer,
  });

  Future<void> _handleLaunchUrl(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liên kết không hợp lệ.')),
      );
      return;
    }
    final launcher = onLaunchUrl ??
        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    final launched = await launcher(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể mở trình duyệt cho liên kết này.'),
        ),
      );
    }
  }

  void _showTableOfContents(BuildContext context) {
    final toc = document.generateTableOfContents();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mục lục bài viết',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (toc.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(
                        child: Text('Bài viết chưa có đề mục nào.'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: toc.length,
                        itemBuilder: (context, index) {
                          final item = toc[index];
                          final indent = (item.level - 1) * 16.0;
                          return InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              // Có thể kích hoạt cuộn tới block
                            },
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: indent,
                                top: 8.0,
                                bottom: 8.0,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.subdirectory_arrow_right,
                                    size: 16.0,
                                    color: item.level == 1
                                        ? Theme.of(ctx).colorScheme.primary
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 8.0),
                                  Expanded(
                                    child: Text(
                                      item.fullTitle,
                                      style: TextStyle(
                                        fontWeight: item.level == 1
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: item.level == 1 ? 15.0 : 14.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final headingNumbers = document.computeHeadingNumbers();
    final blocks = document.blocks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocks.any((b) => b.type == ArticleBlockType.heading)) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('document_toc_button'),
              icon: const Icon(Icons.list_alt, size: 18.0),
              label: const Text('Mục lục'),
              onPressed: () => _showTableOfContents(context),
            ),
          ),
          const SizedBox(height: 8.0),
        ],
        for (final block in blocks) ...[
          _renderBlock(context, block, headingNumbers),
          const SizedBox(height: 12.0),
        ],
      ],
    );
  }

  Widget _renderBlock(
    BuildContext context,
    ArticleBlock block,
    Map<String, String> headingNumbers,
  ) {
    switch (block.type) {
      case ArticleBlockType.heading:
        final data = block.data as HeadingBlockData;
        final numPrefix =
            data.isNumbered ? (headingNumbers[block.id] ?? '') : '';
        final displayTitle = numPrefix.isNotEmpty
            ? '$numPrefix ${data.text}'
            : data.text;

        final textStyle = switch (data.level) {
          1 => Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
          2 => Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          3 => Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          _ => Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        };

        return Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Text(
            displayTitle,
            style: textStyle,
          ),
        );

      case ArticleBlockType.paragraph:
        final data = block.data as ParagraphBlockData;
        return _renderParagraph(context, data);

      case ArticleBlockType.callout:
        final data = block.data as CalloutBlockData;
        return _renderCallout(context, data);

      case ArticleBlockType.bulletList:
        final data = block.data as BulletListBlockData;
        return _renderBulletList(context, data);

      case ArticleBlockType.orderedList:
        final data = block.data as OrderedListBlockData;
        return _renderOrderedList(context, data);

      case ArticleBlockType.image:
        final data = block.data as ImageBlockData;
        return _renderImage(context, data);

      case ArticleBlockType.youtubeVideo:
        final data = block.data as YouTubeBlockData;
        return _renderYouTube(context, data);

      case ArticleBlockType.billiardDiagram:
        final data = block.data as BilliardDiagramBlockData;
        return _renderBilliardDiagram(context, data);

      case ArticleBlockType.strokeParameter:
        final data = block.data as StrokeParameterBlockData;
        return _renderStrokeParameter(context, data);

      case ArticleBlockType.divider:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Divider(thickness: 1.5),
        );

      case ArticleBlockType.codeFormula:
        final data = block.data as CodeFormulaBlockData;
        return _renderCodeFormula(context, data);

      case ArticleBlockType.unknown:
        return Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                const Icon(Icons.extension_outlined, color: Colors.amber),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    'Khối nội dung mở rộng chưa được hỗ trợ trên phiên bản này: ${(block.data as UnknownBlockData).rawType}',
                    style: const TextStyle(fontSize: 13.0),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _renderParagraph(BuildContext context, ParagraphBlockData data) {
    if (data.spans.isEmpty) {
      return Text(
        data.text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
      );
    }

    final spans = <InlineSpan>[];
    int current = 0;
    final text = data.text;

    // Sắp xếp spans theo start
    final sortedSpans = List<InlineSpanStyle>.from(data.spans)
      ..sort((a, b) => a.start.compareTo(b.start));

    for (final s in sortedSpans) {
      final safeStart = s.start.clamp(0, text.length);
      final safeEnd = s.end.clamp(0, text.length);

      if (safeStart > current) {
        spans.add(TextSpan(text: text.substring(current, safeStart)));
      }

      if (safeEnd > safeStart) {
        final sub = text.substring(safeStart, safeEnd);
        final isBold = s.styles.contains(InlineStyle.bold);
        final isItalic = s.styles.contains(InlineStyle.italic);
        final isUnderline = s.styles.contains(InlineStyle.underline);
        final isLink = s.styles.contains(InlineStyle.link) && s.url != null;

        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: isLink
                ? InkWell(
                    onTap: () => _handleLaunchUrl(context, s.url!),
                    child: Text(
                      sub,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  )
                : Text(
                    sub,
                    style: TextStyle(
                      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                      decoration: isUnderline
                          ? TextDecoration.underline
                          : TextDecoration.none,
                    ),
                  ),
          ),
        );
      }
      current = safeEnd;
    }

    if (current < text.length) {
      spans.add(TextSpan(text: text.substring(current)));
    }

    return Text.rich(
      TextSpan(
        children: spans,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
      ),
    );
  }

  Widget _renderCallout(BuildContext context, CalloutBlockData data) {
    final (bgColor, borderColor, icon, defaultTitle) = switch (data.preset) {
      CalloutPreset.note => (
          Colors.blue.shade50,
          Colors.blue.shade400,
          Icons.info_outline,
          'Ghi chú',
        ),
      CalloutPreset.warning => (
          Colors.amber.shade50,
          Colors.amber.shade700,
          Icons.warning_amber_rounded,
          'Chú ý',
        ),
      CalloutPreset.example => (
          Colors.green.shade50,
          Colors.green.shade600,
          Icons.lightbulb_outline,
          'Ví dụ',
        ),
      CalloutPreset.tip => (
          Colors.purple.shade50,
          Colors.purple.shade400,
          Icons.tips_and_updates_outlined,
          'Mẹo hữu ích',
        ),
      CalloutPreset.mistake => (
          Colors.red.shade50,
          Colors.red.shade400,
          Icons.error_outline,
          'Lỗi thường gặp',
        ),
    };

    final title = (data.title != null && data.title!.trim().isNotEmpty)
        ? data.title!.trim()
        : defaultTitle;

    return Container(
      decoration: BoxDecoration(
        color: borderColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Container(
        margin: const EdgeInsets.only(left: 4.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8.0)),
        ),
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: borderColor, size: 20.0),
                const SizedBox(width: 8.0),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: borderColor,
                    fontSize: 15.0,
                  ),
                ),
              ],
            ),
            if (data.content.trim().isNotEmpty) ...[
              const SizedBox(height: 8.0),
              Text(
                data.content.trim(),
                style: const TextStyle(fontSize: 14.5, height: 1.4),
              ),
            ],
            if (data.items.isNotEmpty) ...[
              const SizedBox(height: 6.0),
              for (final item in data.items)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: borderColor, fontWeight: FontWeight.bold)),
                      Expanded(child: Text(item, style: const TextStyle(height: 1.35))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _renderBulletList(BuildContext context, BulletListBlockData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in data.items)
          Padding(
            padding: EdgeInsets.only(
              left: item.level * 18.0,
              top: 3.0,
              bottom: 3.0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.level == 0
                      ? '• '
                      : (item.level == 1 ? '– ' : '▪ '),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0),
                ),
                Expanded(
                  child: Text(
                    item.text,
                    style: const TextStyle(height: 1.4, fontSize: 14.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _renderOrderedList(BuildContext context, OrderedListBlockData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < data.items.length; i++)
          Padding(
            padding: EdgeInsets.only(
              left: data.items[i].level * 18.0,
              top: 3.0,
              bottom: 3.0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.numberingStyle == NumberingStyle.letter
                      ? '${String.fromCharCode(97 + (i % 26))}. '
                      : '${i + 1}. ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
                Expanded(
                  child: Text(
                    data.items[i].text,
                    style: const TextStyle(height: 1.4, fontSize: 14.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _renderImage(BuildContext context, ImageBlockData data) {
    // Tìm attachment trong bài viết để lấy relativePath
    final attachment = article.images.cast<ArticleImageAttachment?>().firstWhere(
          (img) => img?.assetId == data.assetId,
          orElse: () => null,
        );

    final widthFactor = switch (data.displaySize) {
      ImageDisplaySize.small => 0.4,
      ImageDisplaySize.medium => 0.7,
      ImageDisplaySize.large => 1.0,
      ImageDisplaySize.original => 1.0,
    };

    return FutureBuilder<File>(
      future: attachment != null
          ? assetStore.resolveRelativePath(attachment.relativePath)
          : null,
      builder: (context, snapshot) {
        final file = snapshot.data;
        final fileExists = file != null && file.existsSync();

        return FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: Alignment.center,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fileExists)
                  GestureDetector(
                    onTap: () {
                      // Xem toàn màn hình
                      showDialog<void>(
                        context: context,
                        builder: (_) => Dialog.fullscreen(
                          child: Scaffold(
                            appBar: AppBar(
                              title: Text(data.caption.isNotEmpty ? data.caption : 'Ảnh đính kèm'),
                              leading: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                            body: InteractiveViewer(
                              child: Center(
                                child: Image.file(file),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320.0),
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                else
                  Container(
                    height: 180.0,
                    color: Colors.grey.shade200,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_not_supported_outlined, size: 40.0, color: Colors.grey.shade600),
                          const SizedBox(height: 8.0),
                          Text('Ảnh đính kèm: ${data.assetId}', style: TextStyle(color: Colors.grey.shade700)),
                        ],
                      ),
                    ),
                  ),
                if (data.caption.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      data.caption.trim(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _renderYouTube(BuildContext context, YouTubeBlockData data) {
    final thumbUrl = 'https://img.youtube.com/vi/${data.videoId}/hqdefault.jpg';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handleLaunchUrl(context, data.url),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Platform.environment.containsKey('FLUTTER_TEST')
                      ? Container(
                          color: Colors.black87,
                          child: const Center(
                            child: Icon(Icons.video_library, color: Colors.white70, size: 48.0),
                          ),
                        )
                      : Image.network(
                          thumbUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.black87,
                            child: const Center(
                              child: Icon(Icons.video_library, color: Colors.white70, size: 48.0),
                            ),
                          ),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 8.0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36.0,
                  ),
                ),
                Positioned(
                  bottom: 8.0,
                  right: 8.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new, color: Colors.white, size: 14.0),
                        SizedBox(width: 4.0),
                        Text(
                          'Mở YouTube',
                          style: TextStyle(color: Colors.white, fontSize: 12.0),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.caption.isNotEmpty ? data.caption : 'Video minh họa YouTube',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    data.url,
                    style: TextStyle(fontSize: 12.0, color: Theme.of(context).colorScheme.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderBilliardDiagram(
    BuildContext context,
    BilliardDiagramBlockData data,
  ) {
    // Tìm sơ đồ tương ứng trong bài
    final index = article.diagrams.indexWhere((d) => d.id == data.diagramId);
    final diagram = index != -1
        ? article.diagrams[index]
        : (article.diagrams.isNotEmpty ? article.diagrams.first : null);

    if (diagram == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Sơ đồ không tồn tại (ID: ${data.diagramId})'),
        ),
      );
    }

    final diagIndex = index != -1 ? index : 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sơ đồ ${diagIndex + 1}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                TextButton.icon(
                  key: Key('open_diagram_viewer_$diagIndex'),
                  icon: const Icon(Icons.fullscreen, size: 18.0),
                  label: const Text('Xem lớn'),
                  onPressed: () {
                    if (onOpenDiagramViewer != null) {
                      onOpenDiagramViewer!(diagIndex);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DiagramViewerScreen(
                            diagrams: article.diagrams,
                            initialIndex: diagIndex,
                            articleCode: article.code,
                            articleTitle: article.title,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            Center(
              child: SizedBox(
                height: 260.0,
                child: BilliardTableReadOnlyView(
                  key: Key('readonly_diagram_$diagIndex'),
                  scene: diagram.scene,
                ),
              ),
            ),
            if (data.caption.isNotEmpty || diagram.caption.isNotEmpty) ...[
              const SizedBox(height: 8.0),
              Text(
                data.caption.isNotEmpty ? data.caption : diagram.caption,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _renderStrokeParameter(
    BuildContext context,
    StrokeParameterBlockData data,
  ) {
    final stroke = data.strokeParameters;
    final cueLabel = switch (stroke.cueBallId) {
      'ball_yellow' => 'Bi vàng',
      'ball_red' => 'Bi đỏ',
      _ => 'Bi trắng',
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Thông số cách đánh',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (data.linkedDiagramId != null)
                  Chip(
                    label: const Text('Gắn với sơ đồ'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12.0),
            // Hiển thị thanh 3 phần chuẩn Phase 6A:
            // 1. Chạm trái
            // 2. Ép phê
            // 3. Lực
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 500;
                final items = [
                  // 1. Chạm trái
                  Expanded(
                    flex: isWide ? 1 : 0,
                    child: Column(
                      children: [
                        Text('Chạm trái: ${stroke.thicknessSummary}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0)),
                        const SizedBox(height: 6.0),
                        SizedBox(
                          height: 70.0,
                          width: 160.0,
                          child: CustomPaint(
                            painter: HitThicknessPainter(stroke, isLarge: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isWide) const SizedBox(height: 12.0),
                  // 2. Ép phê
                  Expanded(
                    flex: isWide ? 1 : 0,
                    child: Column(
                      children: [
                        Text('Mũi cơ: ${stroke.horizontalTipLabel}, ${stroke.verticalTipLabel}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0)),
                        const SizedBox(height: 6.0),
                        SizedBox(
                          height: 70.0,
                          width: 70.0,
                          child: CustomPaint(
                            painter: CueTipPainter(stroke, isLarge: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isWide) const SizedBox(height: 12.0),
                  // 3. Lực
                  Expanded(
                    flex: isWide ? 1 : 0,
                    child: Column(
                      children: [
                        Text('Lực: ${stroke.forceText.isNotEmpty ? stroke.forceText : "${stroke.forcePercent}%"}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0)),
                        const SizedBox(height: 10.0),
                        LinearProgressIndicator(
                          value: (stroke.forcePercent ?? 50) / 100.0,
                          minHeight: 12.0,
                          borderRadius: BorderRadius.circular(6.0),
                        ),
                        if (stroke.strokeStyleText.isNotEmpty) ...[
                          const SizedBox(height: 4.0),
                          Text('Kiểu: ${stroke.strokeStyleText}', style: const TextStyle(fontSize: 12.0)),
                        ],
                      ],
                    ),
                  ),
                ];

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: items,
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: items,
                  );
                }
              },
            ),
            const SizedBox(height: 8.0),
            Text('• Bi chủ đánh: $cueLabel', style: const TextStyle(fontSize: 13.0)),
          ],
        ),
      ),
    );
  }

  Widget _renderCodeFormula(BuildContext context, CodeFormulaBlockData data) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.functions, size: 20.0, color: Colors.blueGrey),
          const SizedBox(width: 8.0),
          Expanded(
            child: SelectableText(
              data.text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14.0,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
