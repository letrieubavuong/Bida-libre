import '../models/models.dart';

/// Giao diện kho lưu trữ thống nhất cho LibreBilliard (Phase 4A–4B).
/// Bản chính sử dụng SQLite qua [SqliteNotebookRepository].
abstract class NotebookRepository {
  Future<void> initialize();

  List<EditorialGroup> getGroups(ArticleKind kind);

  EditorialGroup? getGroupById(String groupId);

  int countArticlesInGroup(String groupId);

  Future<EditorialGroup> saveGroup({
    String? id,
    required ArticleKind kind,
    required String name,
    String description = '',
  });

  Future<void> reorderGroups(ArticleKind kind, List<String> orderedGroupIds);

  Future<void> deleteGroup({
    required String groupId,
    required String targetGroupId,
  });

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

  Collection? getCollectionById(String collectionId);

  List<Collection> getCollectionsForArticle(String articleId);

  Future<Collection> createCollection(String name);

  Future<Collection> renameCollection(String collectionId, String newName);

  Future<void> deleteCollection(String collectionId);

  Future<void> addArticleToCollection({
    required String collectionId,
    required String articleId,
  });

  Future<void> removeArticleFromCollection({
    required String collectionId,
    required String articleId,
  });

  Future<void> reorderCollectionArticles({
    required String collectionId,
    required List<String> orderedArticleIds,
  });

  List<Tag> getTags();

  List<String> suggestTags(String query);

  Future<void> close();
}
