import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../repositories/article_asset_store.dart';
import 'billiard_table_canvas.dart';

/// Thumbnail đại diện cho bài viết trên card danh sách (Phase 4C):
/// 1. Ưu tiên scene đầu tiên (dùng chung logic vẽ tĩnh [BilliardTableReadOnlyView]).
/// 2. Nếu không có scene nhưng có ảnh -> hiển thị ảnh đầu tiên (giải mã ở kích thước nhỏ).
/// 3. Nếu không có cả hai -> hiển thị placeholder theo loại bài.
class ArticleThumbnail extends StatefulWidget {
  final Article article;
  final ArticleAssetStore assetStore;
  final double width;
  final double height;

  const ArticleThumbnail({
    super.key,
    required this.article,
    required this.assetStore,
    this.width = 48.0,
    this.height = 76.0,
  });

  @override
  State<ArticleThumbnail> createState() => _ArticleThumbnailState();
}

class _ArticleThumbnailState extends State<ArticleThumbnail> {
  Future<File?>? _imageFileFuture;

  @override
  void initState() {
    super.initState();
    _syncImageFuture();
  }

  @override
  void didUpdateWidget(covariant ArticleThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.article.diagrams.isNotEmpty || widget.article.images.isEmpty) {
      _imageFileFuture = null;
      return;
    }
    final hadDiagrams = oldWidget.article.diagrams.isNotEmpty;
    final oldFirst =
        oldWidget.article.images.isNotEmpty ? oldWidget.article.images.first : null;
    final newFirst = widget.article.images.first;
    if (hadDiagrams ||
        _imageFileFuture == null ||
        oldFirst?.assetId != newFirst.assetId ||
        oldFirst?.relativePath != newFirst.relativePath) {
      _syncImageFuture();
    }
  }

  void _syncImageFuture() {
    if (widget.article.diagrams.isEmpty && widget.article.images.isNotEmpty) {
      final first = widget.article.images.first;
      _imageFileFuture = widget.assetStore.findExistingFile(
        assetId: first.assetId,
        relativePath: first.relativePath,
      );
    } else {
      _imageFileFuture = null;
    }
  }

  IconData _placeholderIcon(ArticleKind kind) {
    switch (kind) {
      case ArticleKind.technique:
        return Icons.menu_book_outlined;
      case ArticleKind.system:
        return Icons.calculate_outlined;
      case ArticleKind.position:
        return Icons.grid_view_outlined;
    }
  }

  Widget _buildPlaceholder(BuildContext context, {bool brokenImage = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: Key('thumb_placeholder_${widget.article.id}'),
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8.0),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            brokenImage
                ? Icons.broken_image_outlined
                : _placeholderIcon(widget.article.kind),
            size: 22.0,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 2.0),
          Text(
            widget.article.kind.codePrefix,
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.article.diagrams.isNotEmpty) {
      final firstScene = widget.article.diagrams.first.scene;
      return RepaintBoundary(
        child: ClipRRect(
          key: Key('thumb_scene_${widget.article.id}'),
          borderRadius: BorderRadius.circular(6.0),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Center(
              child: BilliardTableReadOnlyView(scene: firstScene),
            ),
          ),
        ),
      );
    }

    if (widget.article.images.isNotEmpty && _imageFileFuture != null) {
      return FutureBuilder<File?>(
        future: _imageFileFuture,
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildPlaceholder(context);
          }
          if (file == null) {
            return _buildPlaceholder(context, brokenImage: true);
          }
          return ClipRRect(
            key: Key('thumb_image_${widget.article.id}'),
            borderRadius: BorderRadius.circular(8.0),
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Image.file(
                file,
                cacheWidth: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _buildPlaceholder(context, brokenImage: true),
              ),
            ),
          );
        },
      );
    }

    return _buildPlaceholder(context);
  }
}

