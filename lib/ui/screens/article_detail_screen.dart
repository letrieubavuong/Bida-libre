import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/notebook_controller.dart';
import '../widgets/billiard_table_canvas.dart';
import 'article_editor_screen.dart';

/// Màn hình xem chi tiết bài viết (chỉ đọc):
/// - Hiển thị đầy đủ nội dung, thông số cách đánh tĩnh và các sơ đồ theo thứ tự.
/// - Các sơ đồ được hiển thị ở chế độ chỉ đọc để tránh vô tình kéo bi hoặc sửa đường khi xem.
class ArticleDetailScreen extends StatefulWidget {
  final NotebookController controller;
  final String articleId;

  const ArticleDetailScreen({
    super.key,
    required this.controller,
    required this.articleId,
  });

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  NotebookController get _controller => widget.controller;

  String _groupName(Article article) {
    for (final g in _controller.groupsForKind(article.kind)) {
      if (g.id == article.primaryGroupId) return g.name;
    }
    return article.primaryGroupId;
  }

  Future<void> _openEditor(Article article) async {
    await Navigator.of(context).push<Article>(
      MaterialPageRoute(
        builder: (_) => ArticleEditorScreen(
          controller: _controller,
          existingArticle: article,
          initialKind: article.kind,
        ),
      ),
    );
  }

  Future<void> _duplicate(Article article) async {
    final outcome = await _controller.duplicateArticle(article.id);
    if (!mounted) return;
    if (!outcome.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.error ?? 'Không thể nhân bản bài.')),
      );
      return;
    }
    final copy = outcome.article!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã nhân bản thành ${copy.code}')),
    );
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ArticleDetailScreen(
          controller: _controller,
          articleId: copy.id,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Article article) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa bài viết?'),
        content: Text(
          'Bạn có chắc muốn xóa "${article.title}" (${article.code})? '
          'Mã bài sẽ không được dùng lại cho bài khác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa bài'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final err = await _controller.deleteArticle(article.id);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final article = _controller.getArticleById(widget.articleId);
        if (article == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chi tiết bài viết')),
            body: const Center(child: Text('Bài viết không còn tồn tại.')),
          );
        }

        final stroke = article.strokeParameters;
        final cueLabel = switch (stroke.cueBallId) {
          'ball_yellow' => 'Bi vàng',
          'ball_red' => 'Bi đỏ',
          _ => 'Bi trắng',
        };

        return Scaffold(
          appBar: AppBar(
            title: Text(article.code),
            actions: [
              IconButton(
                key: const Key('detail_favorite_button'),
                tooltip: article.isFavorite ? 'Bỏ yêu thích' : 'Yêu thích',
                icon: Icon(
                  article.isFavorite ? Icons.star : Icons.star_border,
                  color: article.isFavorite ? Colors.amber : null,
                ),
                onPressed: _controller.isSaving
                    ? null
                    : () => _controller.toggleFavorite(article.id),
              ),
              IconButton(
                key: const Key('detail_edit_button'),
                tooltip: 'Sửa bài',
                icon: const Icon(Icons.edit_outlined),
                onPressed:
                    _controller.isSaving ? null : () => _openEditor(article),
              ),
              IconButton(
                key: const Key('detail_duplicate_button'),
                tooltip: 'Nhân bản',
                icon: const Icon(Icons.copy_outlined),
                onPressed:
                    _controller.isSaving ? null : () => _duplicate(article),
              ),
              IconButton(
                key: const Key('detail_delete_button'),
                tooltip: 'Xóa bài',
                icon: const Icon(Icons.delete_outline),
                onPressed:
                    _controller.isSaving ? null : () => _confirmDelete(article),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Wrap(
                spacing: 8.0,
                runSpacing: 6.0,
                children: [
                  Chip(label: Text(article.kind.label)),
                  Chip(label: Text(_groupName(article))),
                  Chip(label: Text(article.difficulty.label)),
                  if (article.isDraft)
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
              Builder(
                builder: (context) {
                  final cols = _controller.getCollectionsForArticle(article.id);
                  if (cols.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Wrap(
                      spacing: 6.0,
                      runSpacing: 4.0,
                      children: cols
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
                  );
                },
              ),
              const SizedBox(height: 12.0),
              Text(
                article.title,
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

              if (article.goal.isNotEmpty)
                _SectionCard(
                  title: 'Mục tiêu & Tình huống',
                  child: Text(article.goal),
                ),

              if (article.content.isNotEmpty)
                _SectionCard(
                  title: 'Nội dung giải thích',
                  child: Text(article.content),
                ),

              if (article.steps.isNotEmpty)
                _SectionCard(
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
                _SectionCard(
                  title: 'Lưu ý & Lỗi thường gặp',
                  child: Text(article.commonMistakes),
                ),

              _SectionCard(
                title: 'Thông số cách đánh (Tĩnh)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bi chủ: $cueLabel'),
                    const SizedBox(height: 4.0),
                    Text('Độ dày chạm: ${stroke.thicknessSummary}'),
                    const SizedBox(height: 4.0),
                    Text(
                      'Mũi cơ ngang (X): ${stroke.horizontalTipLabel}',
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'Mũi cơ dọc (Z): ${stroke.verticalTipLabel}',
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'Đầu cơ tham chiếu: ${stroke.tipDiameterMm} mm '
                      '(quy ước 4 mức biên tập: 1 mức = ${CueTipConvention.fourLevelStepMm} mm)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (stroke.tipNote.isNotEmpty) ...[
                      const SizedBox(height: 4.0),
                      Text('Ghi chú mũi cơ: ${stroke.tipNote}'),
                    ],
                    if (stroke.forceText.isNotEmpty) ...[
                      const SizedBox(height: 4.0),
                      Text('Lực đánh: ${stroke.forceText}'),
                    ],
                    if (stroke.strokeStyleText.isNotEmpty) ...[
                      const SizedBox(height: 4.0),
                      Text('Kiểu ra cơ: ${stroke.strokeStyleText}'),
                    ],
                  ],
                ),
              ),

              if ((article.source ?? '').isNotEmpty ||
                  (article.author ?? '').isNotEmpty ||
                  (article.sourcePage ?? '').isNotEmpty)
                _SectionCard(
                  title: 'Nguồn tham khảo',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((article.source ?? '').isNotEmpty)
                        Text('Nguồn: ${article.source}'),
                      if ((article.author ?? '').isNotEmpty)
                        Text('Tác giả: ${article.author}'),
                      if ((article.sourcePage ?? '').isNotEmpty)
                        Text('Trang: ${article.sourcePage}'),
                    ],
                  ),
                ),

              const SizedBox(height: 8.0),
              Text(
                'Sơ đồ minh họa (${article.diagrams.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8.0),
              if (article.diagrams.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Bài viết chưa gắn sơ đồ nào.'),
                  ),
                )
              else
                for (var i = 0; i < article.diagrams.length; i++)
                  Card(
                    key: Key('detail_diagram_card_$i'),
                    margin: const EdgeInsets.only(bottom: 12.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.diagrams[i].caption.isNotEmpty
                                ? 'Sơ đồ ${i + 1}: ${article.diagrams[i].caption}'
                                : 'Sơ đồ ${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8.0),
                          Center(
                            child: SizedBox(
                              height: 320.0,
                              child: BilliardTableReadOnlyView(
                                key: Key('readonly_diagram_$i'),
                                scene: article.diagrams[i].scene,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8.0),
            child,
          ],
        ),
      ),
    );
  }
}

