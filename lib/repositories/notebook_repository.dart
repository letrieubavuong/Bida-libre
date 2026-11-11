import '../models/models.dart';

/// Giao diện kho lưu trữ cho LibreBilliard.
/// Phiên bản đích sử dụng SQLite cho bài viết/nhóm/thẻ/bộ sưu tập/nhật ký và JSON cho scene vector.
abstract class NotebookRepository {
  List<EditorialGroup> getGroups(ArticleKind kind);
  List<Article> getArticles({
    ArticleKind? kind,
    String? groupId,
    bool favoritesOnly = false,
    String query = '',
  });
  List<Collection> getCollections();
  List<Tag> getTags();
}

/// Kho dữ liệu trong bộ nhớ dành cho Phase 0 (khung ứng dụng và nhóm mặc định).
/// Không thêm seed hàng loạt; bài mẫu thực tế sẽ được tạo ở Phase 4.
class InMemoryNotebookRepository implements NotebookRepository {
  final List<EditorialGroup> _groups;
  final List<Article> _articles;
  final List<Collection> _collections;
  final List<Tag> _tags;

  InMemoryNotebookRepository({
    List<EditorialGroup>? groups,
    List<Article>? articles,
    List<Collection>? collections,
    List<Tag>? tags,
  })  : _groups = groups ??
            [
              ...DefaultEditorialGroups.techniqueGroups,
              ...DefaultEditorialGroups.systemGroups,
              ...DefaultEditorialGroups.positionGroups,
            ],
        _articles = articles ?? const [],
        _collections = collections ?? const [],
        _tags = tags ?? const [];

  @override
  List<EditorialGroup> getGroups(ArticleKind kind) {
    final result = _groups.where((g) => g.kind == kind).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List.unmodifiable(result);
  }

  @override
  List<Article> getArticles({
    ArticleKind? kind,
    String? groupId,
    bool favoritesOnly = false,
    String query = '',
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    return _articles.where((article) {
      if (kind != null && article.kind != kind) return false;
      if (groupId != null && article.primaryGroupId != groupId) return false;
      if (favoritesOnly && !article.isFavorite) return false;
      if (normalizedQuery.isNotEmpty) {
        final inTitle = article.title.toLowerCase().contains(normalizedQuery);
        final inCode = article.code.toLowerCase().contains(normalizedQuery);
        final inSummary = article.summary.toLowerCase().contains(normalizedQuery);
        if (!inTitle && !inCode && !inSummary) return false;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  List<Collection> getCollections() => List.unmodifiable(_collections);

  @override
  List<Tag> getTags() => List.unmodifiable(_tags);
}

