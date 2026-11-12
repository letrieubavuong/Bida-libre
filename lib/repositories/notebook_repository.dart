import '../models/models.dart';

/// Giao diện kho lưu trữ thống nhất cho LibreBilliard (Phase 4A).
/// Bản chính sử dụng SQLite qua [SqliteNotebookRepository].
abstract class NotebookRepository {
  Future<void> initialize();

  List<EditorialGroup> getGroups(ArticleKind kind);

  List<Article> getArticles({
    ArticleKind? kind,
    String? groupId,
    bool favoritesOnly = false,
  });

  Article? getArticleById(String id);

  Future<Article> saveArticle(Article draft);

  Future<Article> duplicateArticle(String sourceArticleId);

  Future<void> deleteArticle(String articleId);

  Future<Article?> toggleFavorite(String articleId);

  List<Collection> getCollections();

  List<Tag> getTags();

  Future<void> close();
}
