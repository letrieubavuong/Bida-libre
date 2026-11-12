import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/notebook_controller.dart';
import '../widgets/article_detail_body.dart';
import 'article_editor_screen.dart';

/// Màn hình xem chi tiết bài viết (chỉ đọc):
/// - Hiển thị đầy đủ nội dung, thông số cách đánh tĩnh và các sơ đồ theo thứ tự.
/// - Các sơ đồ được hiển thị ở chế độ chỉ đọc để tránh vô tình kéo bi hoặc sửa đường khi xem.
class ArticleDetailScreen extends StatefulWidget {
  final NotebookController controller;
  final String articleId;
  final Future<bool> Function(Uri uri)? onLaunchUrl;

  const ArticleDetailScreen({
    super.key,
    required this.controller,
    required this.articleId,
    this.onLaunchUrl,
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
          body: ArticleDetailBody(
            article: article,
            groupName: _groupName(article),
            collections: _controller.getCollectionsForArticle(article.id),
            assetStore: _controller.assetStore,
            onLaunchUrl: widget.onLaunchUrl,
          ),
        );
      },
    );
  }
}

/// Màn hình xem trước bài viết trước khi lưu (Phase 4C).
/// Không ghi SQLite, không cấp mã chính thức và không commit tệp staging.
class ArticlePreviewScreen extends StatelessWidget {
  final Article draftArticle;
  final String groupName;
  final List<Collection> collections;
  final dynamic assetStore;
  final Future<bool> Function(Uri uri)? onLaunchUrl;

  const ArticlePreviewScreen({
    super.key,
    required this.draftArticle,
    required this.groupName,
    this.collections = const [],
    required this.assetStore,
    this.onLaunchUrl,
  });

  @override
  Widget build(BuildContext context) {
    final title = draftArticle.code.trim().isEmpty
        ? 'Xem trước bản nháp'
        : 'Xem trước · ${draftArticle.code}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: ArticleDetailBody(
        article: draftArticle,
        groupName: groupName,
        collections: collections,
        assetStore: assetStore,
        isPreview: true,
        onLaunchUrl: onLaunchUrl,
      ),
    );
  }
}

