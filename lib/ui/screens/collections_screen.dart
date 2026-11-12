import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/notebook_controller.dart';
import 'article_detail_screen.dart';

/// Màn hình danh sách bộ sưu tập (Phase 4B).
class CollectionsScreen extends StatefulWidget {
  final NotebookController controller;

  const CollectionsScreen({
    super.key,
    required this.controller,
  });

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  Future<void> _showNameDialog({Collection? existing}) async {
    final rawName = await showDialog<String>(
      context: context,
      builder: (_) => _CollectionNameDialog(existing: existing),
    );
    if (rawName == null || !mounted) return;

    final clean = rawName.trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tên bộ sưu tập không được để trống.')),
      );
      return;
    }

    if (existing == null) {
      await widget.controller.createCollection(clean);
    } else {
      final err = await widget.controller.renameCollection(existing.id, clean);
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  Future<void> _confirmDelete(Collection collection) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xóa bộ sưu tập "${collection.name}"?'),
        content: const Text(
          'Thao tác này chỉ xóa bộ sưu tập và danh sách liên kết, '
          'không xóa các bài viết bên trong.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm_delete_collection_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa bộ sưu tập'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await widget.controller.deleteCollection(collection.id);
    if (!mounted || err == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final collections = widget.controller.collections;
        final busy = widget.controller.isSaving;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bộ sưu tập'),
            actions: [
              IconButton(
                key: const Key('add_collection_button'),
                tooltip: 'Tạo bộ sưu tập mới',
                icon: const Icon(Icons.add),
                onPressed: busy ? null : () => _showNameDialog(),
              ),
            ],
          ),
          body: collections.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Chưa có bộ sưu tập nào.'),
                      const SizedBox(height: 12.0),
                      FilledButton.icon(
                        key: const Key('empty_add_collection_button'),
                        onPressed: busy ? null : () => _showNameDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Tạo bộ sưu tập'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12.0),
                  itemCount: collections.length,
                  itemBuilder: (context, index) {
                    final c = collections[index];
                    return Card(
                      key: Key('collection_card_${c.id}'),
                      child: ListTile(
                        title: Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('${c.orderedArticleIds.length} bài viết'),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CollectionDetailScreen(
                                controller: widget.controller,
                                collectionId: c.id,
                              ),
                            ),
                          );
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key('rename_collection_${c.id}'),
                              tooltip: 'Đổi tên',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: busy
                                  ? null
                                  : () => _showNameDialog(existing: c),
                            ),
                            IconButton(
                              key: Key('delete_collection_${c.id}'),
                              tooltip: 'Xóa bộ sưu tập',
                              icon: const Icon(Icons.delete_outline),
                              onPressed:
                                  busy ? null : () => _confirmDelete(c),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Màn hình chi tiết một bộ sưu tập: lọc theo loại bài, thêm/bỏ bài và sắp xếp thứ tự thủ công.
class CollectionDetailScreen extends StatefulWidget {
  final NotebookController controller;
  final String collectionId;

  const CollectionDetailScreen({
    super.key,
    required this.controller,
    required this.collectionId,
  });

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  ArticleKind? _kindFilter;

  Future<void> _showAddArticleDialog(Collection collection) async {
    final allArticles = widget.controller.repository.getArticles();
    final available = allArticles
        .where((a) => !collection.orderedArticleIds.contains(a.id))
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tất cả bài viết hiện có đã nằm trong bộ sưu tập này.'),
        ),
      );
      return;
    }

    final chosen = await showDialog<Article>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm bài vào bộ sưu tập'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320.0,
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (context, idx) {
              final art = available[idx];
              return ListTile(
                key: Key('pick_collection_article_${art.id}'),
                title: Text(art.title),
                subtitle: Text('${art.code} • ${art.kind.label}'),
                onTap: () => Navigator.of(ctx).pop(art),
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
      ),
    );

    if (chosen == null || !mounted) return;
    final err = await widget.controller.addArticleToCollection(
      collectionId: collection.id,
      articleId: chosen.id,
    );
    if (!mounted || err == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Future<void> _moveArticle(
    Collection collection,
    String articleId,
    int delta,
  ) async {
    final ids = List<String>.from(collection.orderedArticleIds);
    final idx = ids.indexOf(articleId);
    final next = idx + delta;
    if (idx < 0 || next < 0 || next >= ids.length) return;
    final item = ids.removeAt(idx);
    ids.insert(next, item);
    await widget.controller.reorderCollectionArticles(
      collectionId: collection.id,
      orderedArticleIds: ids,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final collection =
            widget.controller.getCollectionById(widget.collectionId);
        if (collection == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Bộ sưu tập')),
            body: const Center(child: Text('Bộ sưu tập không còn tồn tại.')),
          );
        }

        final articles = widget.controller.articlesForCollection(
          collection.id,
          kindFilter: _kindFilter,
        );
        final busy = widget.controller.isSaving;
        final canReorder = _kindFilter == null && !busy;

        return Scaffold(
          appBar: AppBar(
            title: Text(collection.name),
            actions: [
              IconButton(
                key: const Key('collection_add_article_button'),
                tooltip: 'Thêm bài vào bộ sưu tập',
                icon: const Icon(Icons.playlist_add),
                onPressed:
                    busy ? null : () => _showAddArticleDialog(collection),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48.0),
              child: SizedBox(
                height: 44.0,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  children: [
                    ChoiceChip(
                      key: const Key('collection_kind_all'),
                      label: const Text('Tất cả loại'),
                      selected: _kindFilter == null,
                      onSelected: (_) => setState(() => _kindFilter = null),
                    ),
                    const SizedBox(width: 8.0),
                    for (final kind in ArticleKind.values) ...[
                      ChoiceChip(
                        key: Key('collection_kind_${kind.storageKey}'),
                        label: Text(kind.label),
                        selected: _kindFilter == kind,
                        onSelected: (_) => setState(() => _kindFilter = kind),
                      ),
                      const SizedBox(width: 8.0),
                    ],
                  ],
                ),
              ),
            ),
          ),
          body: articles.isEmpty
              ? const Center(
                  child: Text('Chưa có bài nào khớp bộ lọc trong bộ sưu tập.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12.0),
                  itemCount: articles.length,
                  itemBuilder: (context, index) {
                    final art = articles[index];
                    final groupName = widget.controller
                        .groupNameFor(art.kind, art.primaryGroupId);
                    return Card(
                      key: Key('collection_article_card_${art.id}'),
                      child: ListTile(
                        title: Text(
                          art.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${art.code} • ${art.kind.label} • $groupName • '
                          '${art.difficulty.label} • ${art.diagrams.length} sơ đồ',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ArticleDetailScreen(
                                controller: widget.controller,
                                articleId: art.id,
                              ),
                            ),
                          );
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canReorder) ...[
                              IconButton(
                                key: Key('collection_item_up_${art.id}'),
                                tooltip: 'Đưa lên',
                                icon: const Icon(Icons.arrow_upward),
                                onPressed: index == 0
                                    ? null
                                    : () => _moveArticle(collection, art.id, -1),
                              ),
                              IconButton(
                                key: Key('collection_item_down_${art.id}'),
                                tooltip: 'Đưa xuống',
                                icon: const Icon(Icons.arrow_downward),
                                onPressed: index == articles.length - 1
                                    ? null
                                    : () => _moveArticle(collection, art.id, 1),
                              ),
                            ],
                            IconButton(
                              key: Key('collection_remove_item_${art.id}'),
                              tooltip: 'Bỏ khỏi bộ sưu tập',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: busy
                                  ? null
                                  : () => widget.controller
                                      .removeArticleFromCollection(
                                        collectionId: collection.id,
                                        articleId: art.id,
                                      ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _CollectionNameDialog extends StatefulWidget {
  final Collection? existing;

  const _CollectionNameDialog({this.existing});

  @override
  State<_CollectionNameDialog> createState() => _CollectionNameDialogState();
}

class _CollectionNameDialogState extends State<_CollectionNameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Tạo bộ sưu tập' : 'Đổi tên bộ sưu tập',
      ),
      content: TextField(
        key: const Key('collection_name_input'),
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Tên bộ sưu tập *',
          hintText: 'Ví dụ: Sách A — Chương 2',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('confirm_collection_name_button'),
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

