import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../repositories/scene_storage.dart';
import '../../state/notebook_controller.dart';
import '../widgets/article_thumbnail.dart';
import 'article_detail_screen.dart';
import 'article_editor_screen.dart';
import 'collections_screen.dart';
import 'group_management_screen.dart';
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

  late final TextEditingController _searchCtrl;
  late final ScrollController _scrollCtrl;
  ArticleKind? _lastRenderedTab;
  bool _restoringScroll = false;

  @override
  void initState() {
    super.initState();
    _lastRenderedTab = _controller.currentTab;
    _searchCtrl = TextEditingController(text: _controller.searchQuery);
    _scrollCtrl = ScrollController(
      initialScrollOffset: _controller.currentScrollOffset,
    );
    _scrollCtrl.addListener(_onScroll);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_restoringScroll || !_scrollCtrl.hasClients) return;
    _controller.setScrollOffset(_controller.currentTab, _scrollCtrl.offset);
  }

  void _restoreScrollForCurrentTab() {
    final target = _controller.currentScrollOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final maxExtent = _scrollCtrl.position.maxScrollExtent;
      final clamped = target.clamp(0.0, maxExtent);
      if ((_scrollCtrl.offset - clamped).abs() > 0.5) {
        _restoringScroll = true;
        _scrollCtrl.jumpTo(clamped);
        _restoringScroll = false;
      }
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final tabChanged = _lastRenderedTab != _controller.currentTab;
    _lastRenderedTab = _controller.currentTab;

    if (_searchCtrl.text != _controller.searchQuery) {
      _searchCtrl.value = TextEditingValue(
        text: _controller.searchQuery,
        selection: TextSelection.collapsed(
          offset: _controller.searchQuery.length,
        ),
      );
    }

    setState(() {});
    if (tabChanged) {
      _restoreScrollForCurrentTab();
    }
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
    _restoreScrollForCurrentTab();
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
    _restoreScrollForCurrentTab();
  }

  void _openGroupManager() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupManagementScreen(
          controller: _controller,
          kind: _controller.currentTab,
        ),
      ),
    );
  }

  void _openCollections() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionsScreen(controller: _controller),
      ),
    );
  }

  void _openFilterAndSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AnimatedBuilder(
        animation: _controller,
        builder: (ctx, _) {
          final allTags = _controller.tags;
          final allCollections = _controller.collections;
          final canManualSort = _controller.selectedCollectionIds.length == 1;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sắp xếp & Bộ lọc (${_controller.currentTab.label})',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (_controller.hasActiveFilters)
                        TextButton(
                          key: const Key('sheet_clear_filters_button'),
                          onPressed: _controller.clearFilters,
                          child: const Text('Bỏ lọc'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  const Text(
                    'Sắp xếp theo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6.0),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 6.0,
                    children: ArticleSortOption.values.map((opt) {
                      final enabled =
                          opt != ArticleSortOption.collectionManualOrder ||
                              canManualSort;
                      return ChoiceChip(
                        key: Key('sort_option_${opt.storageKey}'),
                        label: Text(opt.label),
                        selected: _controller.sortBy == opt,
                        onSelected: enabled
                            ? (_) => _controller.setSortOption(opt)
                            : null,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12.0),
                  const Text(
                    'Độ khó (chọn nhiều = HOẶC)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6.0),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 6.0,
                    children: Difficulty.values.map((d) {
                      return FilterChip(
                        key: Key('filter_diff_${d.storageKey}'),
                        label: Text(d.label),
                        selected: _controller.selectedDifficulties.contains(d),
                        onSelected: (_) => _controller.toggleDifficultyFilter(d),
                      );
                    }).toList(),
                  ),
                  if (allTags.isNotEmpty) ...[
                    const SizedBox(height: 12.0),
                    const Text(
                      'Thẻ (chọn nhiều = HOẶC)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6.0),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 6.0,
                      children: allTags.map((t) {
                        final key =
                            VietnameseSearchNormalizer.tagDuplicateKey(t.name);
                        return FilterChip(
                          key: Key('filter_tag_$key'),
                          label: Text('#${t.name}'),
                          selected: _controller.selectedTagKeys.contains(key),
                          onSelected: (_) =>
                              _controller.toggleTagFilter(t.name),
                        );
                      }).toList(),
                    ),
                  ],
                  if (allCollections.isNotEmpty) ...[
                    const SizedBox(height: 12.0),
                    const Text(
                      'Bộ sưu tập (chọn nhiều = HOẶC)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6.0),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 6.0,
                      children: allCollections.map((c) {
                        return FilterChip(
                          key: Key('filter_collection_${c.id}'),
                          label: Text(c.name),
                          selected:
                              _controller.selectedCollectionIds.contains(c.id),
                          onSelected: (_) =>
                              _controller.toggleCollectionFilter(c.id),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 12.0),
                  SwitchListTile(
                    key: const Key('filter_favorites_switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chỉ hiển thị bài Yêu thích'),
                    value: _controller.favoritesOnly,
                    onChanged: (_) => _controller.toggleFavoritesOnly(),
                  ),
                ],
              ),
            ),
          );
        },
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
            key: const Key('collections_button'),
            tooltip: 'Bộ sưu tập',
            icon: const Icon(Icons.collections_bookmark_outlined),
            onPressed: _openCollections,
          ),
          IconButton(
            key: const Key('manage_groups_button'),
            tooltip: 'Quản lý nhóm',
            icon: const Icon(Icons.folder_outlined),
            onPressed: _openGroupManager,
          ),
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
          preferredSize: const Size.fromHeight(104.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('home_search_input'),
                        controller: _searchCtrl,
                        onChanged: _controller.setSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'Tìm mã, tên, mô tả hoặc thẻ...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  key: const Key('clear_search_button'),
                                  tooltip: 'Xóa tìm kiếm',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _controller.setSearchQuery('');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8.0,
                            horizontal: 12.0,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    IconButton.filledTonal(
                      key: const Key('filter_button'),
                      tooltip: 'Lọc & Sắp xếp',
                      icon: Icon(
                        _controller.hasActiveFilters
                            ? Icons.filter_alt
                            : Icons.tune,
                      ),
                      onPressed: _openFilterAndSortSheet,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4.0),
              SizedBox(
                height: 44.0,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: groups.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8.0),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = _controller.selectedGroupIds.isEmpty;
                      return ChoiceChip(
                        label: const Text('Tất cả nhóm'),
                        selected: isSelected,
                        onSelected: (_) => _controller.selectGroup(null),
                      );
                    }
                    final group = groups[index - 1];
                    final isSelected =
                        _controller.selectedGroupIds.contains(group.id);
                    return FilterChip(
                      key: Key('home_group_chip_${group.id}'),
                      label: Text(group.name),
                      selected: isSelected,
                      onSelected: (_) =>
                          _controller.toggleGroupFilter(group.id),
                    );
                  },
                ),
              ),
            ],
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
                    key: Key('articles_list_${currentKind.storageKey}'),
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 96.0),
                    itemCount: articles.length,
                    itemBuilder: (context, index) {
                      final article = articles[index];
                      final groupName = _controller.groupNameFor(
                        article.kind,
                        article.primaryGroupId,
                      );
                      final metaParts = <String>[
                        article.code,
                        groupName,
                        article.difficulty.label,
                        '${article.diagrams.length} sơ đồ',
                        if (article.isDraft) 'Nháp',
                      ];
                      return Card(
                        key: Key('article_card_${article.id}'),
                        margin: const EdgeInsets.only(bottom: 12.0),
                        child: ListTile(
                          onTap: () => _openArticleDetail(article),
                          leading: ArticleThumbnail(
                            article: article,
                            assetStore: _controller.assetStore,
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
                              if (article.tags.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    article.tags.map((t) => '#$t').join(' '),
                                    style: Theme.of(context).textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                  ? 'Hãy xóa tìm kiếm hoặc bộ lọc để xem lại danh sách.'
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
