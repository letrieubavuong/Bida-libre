import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../repositories/notebook_repository.dart';
import '../repositories/sqlite_notebook_repository.dart';

class ArticleSaveOutcome {
  final Article? article;
  final String? error;

  const ArticleSaveOutcome({this.article, this.error});

  bool get isSuccess => article != null && error == null;
}

class CollectionActionOutcome {
  final Collection? collection;
  final String? error;

  const CollectionActionOutcome({this.collection, this.error});

  bool get isSuccess => collection != null && error == null;
}

class TabViewState {
  final ArticleFilterCriteria criteria;
  final double scrollOffset;

  const TabViewState({
    this.criteria = const ArticleFilterCriteria(),
    this.scrollOffset = 0.0,
  });

  TabViewState copyWith({
    ArticleFilterCriteria? criteria,
    double? scrollOffset,
  }) {
    return TabViewState(
      criteria: criteria ?? this.criteria,
      scrollOffset: scrollOffset ?? this.scrollOffset,
    );
  }
}

/// Quản lý trạng thái điều hướng, tìm kiếm/lọc, sắp xếp, nhóm, thẻ, bộ sưu tập và CRUD SQLite.
class NotebookController extends ChangeNotifier {
  final NotebookRepository _repository;

  ArticleKind _currentTab = ArticleKind.technique;
  final Map<ArticleKind, TabViewState> _tabStates = {
    ArticleKind.technique: const TabViewState(),
    ArticleKind.system: const TabViewState(),
    ArticleKind.position: const TabViewState(),
  };

  bool _isDisposed = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;

  NotebookController({NotebookRepository? repository})
      : _repository = repository ?? SqliteNotebookRepository();

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  NotebookRepository get repository => _repository;
  ArticleKind get currentTab => _currentTab;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;

  TabViewState get currentTabState => _tabStates[_currentTab]!;
  ArticleFilterCriteria get currentCriteria => currentTabState.criteria;
  String get searchQuery => currentCriteria.searchQuery;
  bool get favoritesOnly => currentCriteria.favoritesOnly;
  Set<String> get selectedGroupIds => currentCriteria.groupIds;
  Set<String> get selectedTagKeys => currentCriteria.tagKeys;
  Set<Difficulty> get selectedDifficulties => currentCriteria.difficulties;
  Set<String> get selectedCollectionIds => currentCriteria.collectionIds;
  ArticleSortOption get sortBy => currentCriteria.sortBy;
  double get currentScrollOffset => currentTabState.scrollOffset;

  String? get selectedGroupId =>
      selectedGroupIds.length == 1 ? selectedGroupIds.first : null;

  bool get hasActiveFilters => currentCriteria.hasActiveFilters;

  List<EditorialGroup> get currentGroups => _repository.getGroups(_currentTab);

  List<EditorialGroup> groupsForKind(ArticleKind kind) =>
      _repository.getGroups(kind);

  String groupNameFor(ArticleKind kind, String groupId) {
    for (final g in _repository.getGroups(kind)) {
      if (g.id == groupId) return g.name;
    }
    return groupId;
  }

  int countArticlesInGroup(String groupId) =>
      _repository.countArticlesInGroup(groupId);

  List<Collection> get collections => _repository.getCollections();

  Collection? getCollectionById(String collectionId) =>
      _repository.getCollectionById(collectionId);

  List<Collection> getCollectionsForArticle(String articleId) =>
      _repository.getCollectionsForArticle(articleId);

  List<Tag> get tags => _repository.getTags();

  List<String> suggestTags(String query) => _repository.suggestTags(query);

  List<Article> get visibleArticles {
    final allInTab = _repository.getArticles(kind: _currentTab);
    return ArticleQueryEngine.filterAndSort(
      articles: allInTab,
      criteria: currentCriteria,
      collections: _repository.getCollections(),
      kindFilter: _currentTab,
    );
  }

  List<Article> articlesForCollection(
    String collectionId, {
    ArticleKind? kindFilter,
  }) {
    final all = _repository.getArticles();
    return ArticleQueryEngine.filterAndSort(
      articles: all,
      criteria: ArticleFilterCriteria(
        collectionIds: {collectionId},
        sortBy: ArticleSortOption.collectionManualOrder,
      ),
      collections: _repository.getCollections(),
      kindFilter: kindFilter,
    );
  }

  Article? getArticleById(String id) => _repository.getArticleById(id);

  Future<void> initialize() async {
    _isLoading = true;
    _loadError = null;
    _safeNotify();
    try {
      await _repository.initialize();
      _isLoading = false;
      _safeNotify();
    } catch (e) {
      _isLoading = false;
      _loadError = 'Không thể mở kho bài viết SQLite: $e';
      _safeNotify();
    }
  }

  void _updateCurrentCriteria(ArticleFilterCriteria next) {
    _tabStates[_currentTab] = currentTabState.copyWith(criteria: next);
    _safeNotify();
  }

  void selectTab(ArticleKind kind) {
    if (_currentTab == kind) return;
    _currentTab = kind;
    _safeNotify();
  }

  void setScrollOffset(ArticleKind kind, double offset) {
    final prev = _tabStates[kind]!;
    if ((prev.scrollOffset - offset).abs() < 0.5) return;
    _tabStates[kind] = prev.copyWith(scrollOffset: offset < 0 ? 0.0 : offset);
  }

  double scrollOffsetFor(ArticleKind kind) => _tabStates[kind]!.scrollOffset;

  void setSearchQuery(String query) {
    if (currentCriteria.searchQuery == query) return;
    _updateCurrentCriteria(currentCriteria.copyWith(searchQuery: query));
  }

  void toggleFavoritesOnly() {
    _updateCurrentCriteria(
      currentCriteria.copyWith(favoritesOnly: !currentCriteria.favoritesOnly),
    );
  }

  void selectGroup(String? groupId) {
    if (groupId == null) {
      if (currentCriteria.groupIds.isEmpty) return;
      _updateCurrentCriteria(currentCriteria.copyWith(groupIds: const {}));
      return;
    }
    toggleGroupFilter(groupId);
  }

  void toggleGroupFilter(String groupId) {
    final next = Set<String>.from(currentCriteria.groupIds);
    if (!next.add(groupId)) {
      next.remove(groupId);
    }
    _updateCurrentCriteria(currentCriteria.copyWith(groupIds: next));
  }

  void toggleTagFilter(String tagDisplay) {
    final key = VietnameseSearchNormalizer.tagDuplicateKey(tagDisplay);
    if (key.isEmpty) return;
    final next = Set<String>.from(currentCriteria.tagKeys);
    if (!next.add(key)) {
      next.remove(key);
    }
    _updateCurrentCriteria(currentCriteria.copyWith(tagKeys: next));
  }

  void toggleDifficultyFilter(Difficulty diff) {
    final next = Set<Difficulty>.from(currentCriteria.difficulties);
    if (!next.add(diff)) {
      next.remove(diff);
    }
    _updateCurrentCriteria(currentCriteria.copyWith(difficulties: next));
  }

  void toggleCollectionFilter(String collectionId) {
    final next = Set<String>.from(currentCriteria.collectionIds);
    if (!next.add(collectionId)) {
      next.remove(collectionId);
    }
    var nextSort = currentCriteria.sortBy;
    if (nextSort == ArticleSortOption.collectionManualOrder &&
        next.length != 1) {
      nextSort = ArticleSortOption.updatedDesc;
    }
    _updateCurrentCriteria(
      currentCriteria.copyWith(collectionIds: next, sortBy: nextSort),
    );
  }

  void setSortOption(ArticleSortOption sortBy) {
    if (sortBy == ArticleSortOption.collectionManualOrder &&
        currentCriteria.collectionIds.length != 1) {
      return;
    }
    if (currentCriteria.sortBy == sortBy) return;
    _updateCurrentCriteria(currentCriteria.copyWith(sortBy: sortBy));
  }

  void clearFilters() {
    _updateCurrentCriteria(
      ArticleFilterCriteria(sortBy: currentCriteria.sortBy),
    );
  }

  Future<ArticleSaveOutcome> saveArticle(Article draft) async {
    if (_isSaving) {
      return const ArticleSaveOutcome(
        error: 'Đang lưu bài viết, vui lòng chờ.',
      );
    }
    if (_isLoading) {
      return const ArticleSaveOutcome(
        error: 'Kho dữ liệu đang tải, vui lòng thử lại sau giây lát.',
      );
    }
    final minimalErr = draft.validateMinimalForSave();
    if (minimalErr != null) {
      return ArticleSaveOutcome(error: minimalErr);
    }

    _isSaving = true;
    _safeNotify();
    try {
      final saved = await _repository.saveArticle(draft);
      _isSaving = false;
      _safeNotify();
      return ArticleSaveOutcome(article: saved);
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return ArticleSaveOutcome(error: 'Không thể lưu bài viết: $e');
    }
  }

  Future<ArticleSaveOutcome> duplicateArticle(String sourceArticleId) async {
    if (_isSaving || _isLoading) {
      return const ArticleSaveOutcome(
        error: 'Hệ thống đang bận thao tác khác, vui lòng chờ.',
      );
    }
    _isSaving = true;
    _safeNotify();
    try {
      final copy = await _repository.duplicateArticle(sourceArticleId);
      _isSaving = false;
      _safeNotify();
      return ArticleSaveOutcome(article: copy);
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return ArticleSaveOutcome(error: 'Không thể nhân bản bài viết: $e');
    }
  }

  Future<String?> deleteArticle(String articleId) async {
    if (_isSaving || _isLoading) {
      return 'Hệ thống đang bận thao tác khác, vui lòng chờ.';
    }
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.deleteArticle(articleId);
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể xóa bài viết: $e';
    }
  }

  Future<void> toggleFavorite(String articleId) async {
    if (_isSaving || _isLoading) return;
    await _repository.toggleFavorite(articleId);
    _safeNotify();
  }

  // --- Quản lý nhóm ---

  Future<String?> saveGroup({
    String? id,
    required ArticleKind kind,
    required String name,
    String description = '',
  }) async {
    if (_isSaving || _isLoading) return 'Hệ thống đang bận.';
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.saveGroup(
        id: id,
        kind: kind,
        name: name,
        description: description,
      );
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể lưu nhóm: $e';
    }
  }

  Future<String?> reorderGroups(
    ArticleKind kind,
    List<String> orderedGroupIds,
  ) async {
    if (_isSaving || _isLoading) return 'Hệ thống đang bận.';
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.reorderGroups(kind, orderedGroupIds);
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể sắp xếp nhóm: $e';
    }
  }

  Future<String?> deleteGroup({
    required String groupId,
    required String targetGroupId,
  }) async {
    if (_isSaving || _isLoading) return 'Hệ thống đang bận.';
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.deleteGroup(
        groupId: groupId,
        targetGroupId: targetGroupId,
      );
      for (final kind in ArticleKind.values) {
        final state = _tabStates[kind]!;
        if (state.criteria.groupIds.contains(groupId)) {
          final nextGroups = Set<String>.from(state.criteria.groupIds)
            ..remove(groupId);
          _tabStates[kind] = state.copyWith(
            criteria: state.criteria.copyWith(groupIds: nextGroups),
          );
        }
      }
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể xóa nhóm: $e';
    }
  }

  // --- Quản lý bộ sưu tập ---

  Future<CollectionActionOutcome> createCollection(String name) async {
    if (_isSaving || _isLoading) {
      return const CollectionActionOutcome(
        error: 'Hệ thống đang bận, bộ sưu tập chưa được lưu.',
      );
    }
    _isSaving = true;
    _safeNotify();
    try {
      final created = await _repository.createCollection(name);
      _isSaving = false;
      _safeNotify();
      return CollectionActionOutcome(collection: created);
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return CollectionActionOutcome(
        error: 'Không thể tạo bộ sưu tập (chưa lưu): $e',
      );
    }
  }

  Future<String?> renameCollection(String collectionId, String newName) async {
    if (_isSaving || _isLoading) return 'Hệ thống đang bận.';
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.renameCollection(collectionId, newName);
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể đổi tên bộ sưu tập: $e';
    }
  }

  Future<String?> deleteCollection(String collectionId) async {
    if (_isSaving || _isLoading) return 'Hệ thống đang bận.';
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.deleteCollection(collectionId);
      for (final kind in ArticleKind.values) {
        final state = _tabStates[kind]!;
        if (state.criteria.collectionIds.contains(collectionId)) {
          final nextCols = Set<String>.from(state.criteria.collectionIds)
            ..remove(collectionId);
          final nextSort =
              state.criteria.sortBy == ArticleSortOption.collectionManualOrder &&
                      nextCols.length != 1
                  ? ArticleSortOption.updatedDesc
                  : state.criteria.sortBy;
          _tabStates[kind] = state.copyWith(
            criteria: state.criteria.copyWith(
              collectionIds: nextCols,
              sortBy: nextSort,
            ),
          );
        }
      }
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể xóa bộ sưu tập: $e';
    }
  }

  Future<String?> addArticleToCollection({
    required String collectionId,
    required String articleId,
  }) async {
    if (_isSaving || _isLoading) return 'Hệ thống đang bận.';
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.addArticleToCollection(
        collectionId: collectionId,
        articleId: articleId,
      );
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể thêm bài vào bộ sưu tập: $e';
    }
  }

  Future<String?> removeArticleFromCollection({
    required String collectionId,
    required String articleId,
  }) async {
    if (_isSaving || _isLoading) {
      return 'Hệ thống đang bận, thao tác chưa được lưu.';
    }
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.removeArticleFromCollection(
        collectionId: collectionId,
        articleId: articleId,
      );
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể bỏ bài khỏi bộ sưu tập (chưa lưu): $e';
    }
  }

  Future<String?> reorderCollectionArticles({
    required String collectionId,
    required List<String> orderedArticleIds,
  }) async {
    if (_isSaving || _isLoading) {
      return 'Hệ thống đang bận, thứ tự mới chưa được lưu.';
    }
    _isSaving = true;
    _safeNotify();
    try {
      await _repository.reorderCollectionArticles(
        collectionId: collectionId,
        orderedArticleIds: orderedArticleIds,
      );
      _isSaving = false;
      _safeNotify();
      return null;
    } catch (e) {
      _isSaving = false;
      _safeNotify();
      return 'Không thể lưu thứ tự bài trong bộ sưu tập (chưa lưu): $e';
    }
  }
}
