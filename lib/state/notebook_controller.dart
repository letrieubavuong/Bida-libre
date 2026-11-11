import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/notebook_repository.dart';

/// Quản lý trạng thái điều hướng và bộ lọc cho 3 mục chính (Kĩ thuật, Bộ số, Hình bi).
class NotebookController extends ChangeNotifier {
  final NotebookRepository _repository;

  ArticleKind _currentTab = ArticleKind.technique;
  String _searchQuery = '';
  bool _searchAllContent = false;
  bool _favoritesOnly = false;
  final Map<ArticleKind, String?> _selectedGroupByTab = {
    ArticleKind.technique: null,
    ArticleKind.system: null,
    ArticleKind.position: null,
  };

  NotebookController({NotebookRepository? repository})
      : _repository = repository ?? InMemoryNotebookRepository();

  ArticleKind get currentTab => _currentTab;
  String get searchQuery => _searchQuery;
  bool get searchAllContent => _searchAllContent;
  bool get favoritesOnly => _favoritesOnly;
  String? get selectedGroupId => _selectedGroupByTab[_currentTab];

  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _searchAllContent ||
      _favoritesOnly ||
      selectedGroupId != null;

  List<EditorialGroup> get currentGroups => _repository.getGroups(_currentTab);

  List<Article> get visibleArticles => _repository.getArticles(
        kind: _searchAllContent ? null : _currentTab,
        groupId: _searchAllContent ? null : selectedGroupId,
        favoritesOnly: _favoritesOnly,
        query: _searchQuery,
      );

  void selectTab(ArticleKind kind) {
    if (_currentTab == kind) return;
    _currentTab = kind;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void toggleSearchAllContent(bool value) {
    if (_searchAllContent == value) return;
    _searchAllContent = value;
    notifyListeners();
  }

  void toggleFavoritesOnly() {
    _favoritesOnly = !_favoritesOnly;
    notifyListeners();
  }

  void selectGroup(String? groupId) {
    final current = _selectedGroupByTab[_currentTab];
    final next = current == groupId ? null : groupId;
    if (current == next) return;
    _selectedGroupByTab[_currentTab] = next;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _searchAllContent = false;
    _favoritesOnly = false;
    _selectedGroupByTab[_currentTab] = null;
    notifyListeners();
  }
}

