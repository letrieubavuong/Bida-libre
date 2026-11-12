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

/// Quản lý trạng thái điều hướng, bộ lọc và CRUD bài viết từ SQLite cho 3 mục (Kĩ thuật, Bộ số, Hình bi).
class NotebookController extends ChangeNotifier {
  final NotebookRepository _repository;

  ArticleKind _currentTab = ArticleKind.technique;
  bool _favoritesOnly = false;
  final Map<ArticleKind, String?> _selectedGroupByTab = {
    ArticleKind.technique: null,
    ArticleKind.system: null,
    ArticleKind.position: null,
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
  bool get favoritesOnly => _favoritesOnly;
  String? get selectedGroupId => _selectedGroupByTab[_currentTab];
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;

  bool get hasActiveFilters => _favoritesOnly || selectedGroupId != null;

  List<EditorialGroup> get currentGroups => _repository.getGroups(_currentTab);

  List<EditorialGroup> groupsForKind(ArticleKind kind) =>
      _repository.getGroups(kind);

  List<Article> get visibleArticles => _repository.getArticles(
        kind: _currentTab,
        groupId: selectedGroupId,
        favoritesOnly: _favoritesOnly,
      );

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

  void selectTab(ArticleKind kind) {
    if (_currentTab == kind) return;
    _currentTab = kind;
    _safeNotify();
  }

  void toggleFavoritesOnly() {
    _favoritesOnly = !_favoritesOnly;
    _safeNotify();
  }

  void selectGroup(String? groupId) {
    final current = _selectedGroupByTab[_currentTab];
    final next = current == groupId ? null : groupId;
    if (current == next) return;
    _selectedGroupByTab[_currentTab] = next;
    _safeNotify();
  }

  void clearFilters() {
    _favoritesOnly = false;
    _selectedGroupByTab[_currentTab] = null;
    _safeNotify();
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
}
