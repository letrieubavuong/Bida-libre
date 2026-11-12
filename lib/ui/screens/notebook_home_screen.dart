import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../repositories/scene_storage.dart';
import '../../state/notebook_controller.dart';
import 'article_detail_screen.dart';
import 'article_editor_screen.dart';
import 'table_stage_screen.dart';

class NotebookHomeScreen extends StatefulWidget {
  final NotebookController controller;
  final SceneStorage? sceneStorage;

  const NotebookHomeScreen({
    super.key,
    required this.controller,
    this.sceneStorage,
  });

  @override
  State<NotebookHomeScreen> createState() => _NotebookHomeScreenState();
}

class _NotebookHomeScreenState extends State<NotebookHomeScreen> {
  NotebookController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  int _tabIndex(ArticleKind kind) {
    switch (kind) {
      case ArticleKind.technique:
        return 0;
      case ArticleKind.system:
        return 1;
      case ArticleKind.position:
        return 2;
    }
  }

  ArticleKind _kindFromIndex(int index) {
    switch (index) {
      case 0:
        return ArticleKind.technique;
      case 1:
        return ArticleKind.system;
      case 2:
      default:
        return ArticleKind.position;
    }
  }

  void _openTableStage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TableStageScreen(storage: widget.sceneStorage),
      ),
    );
  }

  Future<void> _openCreateArticle() async {
    await Navigator.of(context).push<Article>(
      MaterialPageRoute(
        builder: (_) => ArticleEditorScreen(
          controller: _controller,
          initialKind: _controller.currentTab,
        ),
      ),
    );
  }

  Future<void> _openArticleDetail(Article article) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ArticleDetailScreen(
          controller: _controller,
          articleId: article.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentKind = _controller.currentTab;
    final articles = _controller.visibleArticles;
    final groups = _controller.currentGroups;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'LibreBilliard — ${currentKind.label}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Yêu thích',
            icon: Icon(
              _controller.favoritesOnly ? Icons.star : Icons.star_border,
              color: _controller.favoritesOnly ? Colors.amber : null,
            ),
            onPressed: _controller.toggleFavoritesOnly,
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu ứng dụng',
            onSelected: (value) {
              if (value == 'about') {
                _showInfoDialog(
                  context,
                  title: 'Về LibreBilliard',
                  message:
                      'LibreBilliard — Sổ tay kỹ thuật, bộ số và hình bi libre.\n'
                      'Công cụ tra cứu và dựng sơ đồ bàn tĩnh, sử dụng ngoại tuyến.',
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                enabled: false,
                child: Text('Cài đặt (sắp ra mắt)'),
              ),
              PopupMenuItem(
                value: 'backup',
                enabled: false,
                child: Text('Sao lưu / Khôi phục (sắp ra mắt)'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'about',
                child: Text('Thông tin ứng dụng'),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: SizedBox(
            height: 44.0,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              scrollDirection: Axis.horizontal,
              itemCount: groups.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8.0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = _controller.selectedGroupId == null;
                  return ChoiceChip(
                    label: const Text('Tất cả nhóm'),
                    selected: isSelected,
                    onSelected: (_) => _controller.selectGroup(null),
                  );
                }
                final group = groups[index - 1];
                final isSelected = _controller.selectedGroupId == group.id;
                return ChoiceChip(
                  label: Text(group.name),
                  selected: isSelected,
                  onSelected: (_) => _controller.selectGroup(group.id),
                );
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_controller.isLoading)
            const LinearProgressIndicator(minHeight: 2.0),
          if (_controller.loadError != null)
            MaterialBanner(
              content: Text(_controller.loadError!),
              actions: [
                TextButton(
                  onPressed: _controller.initialize,
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          Expanded(
            child: articles.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 96.0),
                    itemCount: articles.length,
                    itemBuilder: (context, index) {
                      final article = articles[index];
                      final metaParts = <String>[
                        article.code,
                        article.difficulty.label,
                        '${article.diagrams.length} sơ đồ',
                        if (article.isDraft) 'Nháp',
                      ];
                      return Card(
                        key: Key('article_card_${article.id}'),
                        margin: const EdgeInsets.only(bottom: 12.0),
                        child: ListTile(
                          onTap: () => _openArticleDetail(article),
                          leading: CircleAvatar(
                            child: Text(article.kind.codePrefix),
                          ),
                          title: Text(
                            article.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(metaParts.join(' • ')),
                              if (article.summary.isNotEmpty)
                                Text(
                                  article.summary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: article.isFavorite
                                ? 'Bỏ yêu thích'
                                : 'Yêu thích',
                            icon: Icon(
                              article.isFavorite
                                  ? Icons.star
                                  : Icons.star_border,
                              color: article.isFavorite ? Colors.amber : null,
                            ),
                            onPressed: () =>
                                _controller.toggleFavorite(article.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (currentKind == ArticleKind.position) ...[
            FloatingActionButton.small(
              heroTag: 'fab_table_stage_hero',
              key: const Key('fab_open_table_stage'),
              tooltip: 'Dựng thế bi',
              onPressed: _openTableStage,
              child: const Icon(Icons.grid_on),
            ),
            const SizedBox(height: 10.0),
          ],
          FloatingActionButton.extended(
            heroTag: 'fab_new_article_hero',
            key: const Key('fab_new_article'),
            onPressed: _openCreateArticle,
            icon: const Icon(Icons.add),
            label: const Text('Tạo bài'),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex(currentKind),
        onDestinationSelected: (index) {
          _controller.selectTab(_kindFromIndex(index));
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Kĩ thuật',
          ),
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Bộ số',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Hình bi',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final hasFilters = _controller.hasActiveFilters;
    final currentKind = _controller.currentTab;
    final isPositionTab = currentKind == ArticleKind.position;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasFilters ? Icons.filter_list_off : Icons.library_books_outlined,
              size: 64.0,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16.0),
            Text(
              hasFilters
                  ? 'Không tìm thấy kết quả phù hợp'
                  : 'Chưa có bài nào trong mục ${currentKind.label}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            Text(
              hasFilters
                  ? 'Hãy xóa bộ lọc để xem lại danh sách.'
                  : isPositionTab
                      ? 'Bạn có thể tạo bài hình bi mới hoặc mở bàn dựng nhanh ba bi.'
                      : 'Nhấn "Tạo bài" để soạn và lưu ngoại tuyến vào sổ tay.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            if (hasFilters)
              FilledButton.tonalIcon(
                onPressed: _controller.clearFilters,
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Bỏ lọc'),
              )
            else ...[
              FilledButton.icon(
                key: const Key('empty_create_article'),
                onPressed: _openCreateArticle,
                icon: const Icon(Icons.add),
                label: Text('Tạo bài ${currentKind.label}'),
              ),
              if (isPositionTab) ...[
                const SizedBox(height: 8.0),
                OutlinedButton.icon(
                  key: const Key('empty_open_table_stage'),
                  onPressed: _openTableStage,
                  icon: const Icon(Icons.grid_on),
                  label: const Text('Dựng thế bi'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
