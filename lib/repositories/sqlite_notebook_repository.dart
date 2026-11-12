import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../geometry/scene_validator.dart';
import '../models/models.dart';
import 'notebook_repository.dart';

typedef SqliteTransactionHook = Future<void> Function(
  Transaction txn,
  String stage,
);

/// Kho lưu trữ chính bằng SQLite cho bài viết, sơ đồ gắn theo bài, nhóm biên tập và bộ đếm mã bài.
/// - Mọi thao tác lưu/sửa/nhân bản/xóa bài + sơ đồ chạy trong transaction nguyên tử.
/// - Không đụng tới tệp `primary_scene.json` của bàn dựng độc lập từ Phase 2–3.
class SqliteNotebookRepository implements NotebookRepository {
  static const int schemaVersion = 1;
  static const String defaultDbFileName = 'libre_billiard.db';

  final String? dbPath;
  final DatabaseFactory? databaseFactoryOverride;
  final Future<String> Function()? directoryPathProvider;
  final SqliteTransactionHook? debugTransactionHook;

  Database? _db;
  Future<void>? _initFuture;
  Future<void> _writeQueue = Future<void>.value();
  final Random _random = Random.secure();

  final List<EditorialGroup> _groups = [
    ...DefaultEditorialGroups.techniqueGroups,
    ...DefaultEditorialGroups.systemGroups,
    ...DefaultEditorialGroups.positionGroups,
  ];
  final List<Article> _articles = [];
  final List<Collection> _collections = [];
  final List<Tag> _tags = [];

  SqliteNotebookRepository({
    this.dbPath,
    this.databaseFactoryOverride,
    this.directoryPathProvider,
    this.debugTransactionHook,
  });

  bool get isInitialized => _db != null;

  @override
  Future<void> initialize() {
    return _initFuture ??= _openAndLoad();
  }

  Future<void> _openAndLoad() async {
    final resolvedPath = await _resolveDbPath();
    final isInMemory = resolvedPath == inMemoryDatabasePath;

    final factory = databaseFactoryOverride ?? databaseFactory;
    final db = await factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: !isInMemory,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      ),
    );
    _db = db;

    await _ensureInitialSeedOnce(db);
    await _reloadCacheFromDb(db);
  }

  Future<String> _resolveDbPath() async {
    if (dbPath != null) return dbPath!;
    if (directoryPathProvider != null) {
      final dir = await directoryPathProvider!();
      return p.join(dir, defaultDbFileName);
    }
    final appSupportDir = await getApplicationSupportDirectory();
    if (!await appSupportDir.exists()) {
      await appSupportDir.create(recursive: true);
    }
    return p.join(appSupportDir.path, defaultDbFileName);
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS code_counters (
        kind TEXT PRIMARY KEY,
        last_number INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS editorial_groups (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS articles (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT NOT NULL,
        primary_group_id TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        goal TEXT NOT NULL,
        content TEXT NOT NULL,
        steps_json TEXT NOT NULL,
        common_mistakes TEXT NOT NULL,
        source TEXT,
        author TEXT,
        source_page TEXT,
        is_draft INTEGER NOT NULL,
        stroke_params_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_favorite INTEGER NOT NULL,
        practice_status TEXT NOT NULL,
        related_article_ids_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS article_diagrams (
        id TEXT PRIMARY KEY,
        article_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        caption TEXT NOT NULL,
        scene_json TEXT NOT NULL,
        FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_article_diagrams_order '
      'ON article_diagrams(article_id, sort_order)',
    );
  }

  /// Khởi tạo nhóm mặc định đúng một lần khi CSDL mới tinh; không ghi đè dữ liệu ở các lần mở sau.
  Future<void> _ensureInitialSeedOnce(Database db) async {
    await db.transaction((txn) async {
      final metaRows = await txn.query(
        'meta',
        where: 'key = ?',
        whereArgs: ['default_groups_seeded'],
      );
      if (metaRows.isEmpty) {
        final defaults = [
          ...DefaultEditorialGroups.techniqueGroups,
          ...DefaultEditorialGroups.systemGroups,
          ...DefaultEditorialGroups.positionGroups,
        ];
        for (final g in defaults) {
          await txn.insert(
            'editorial_groups',
            {
              'id': g.id,
              'kind': g.kind.storageKey,
              'name': g.name,
              'description': g.description,
              'sort_order': g.sortOrder,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await txn.insert(
          'meta',
          {'key': 'default_groups_seeded', 'value': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final kind in ArticleKind.values) {
        await txn.insert(
          'code_counters',
          {'kind': kind.storageKey, 'last_number': 0},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> _reloadCacheFromDb(DatabaseExecutor db) async {
    final groupRows = await db.query(
      'editorial_groups',
      orderBy: 'sort_order ASC, name ASC',
    );
    final loadedGroups = groupRows
        .map(
          (r) => EditorialGroup(
            id: r['id'] as String,
            kind: ArticleKind.fromKey(r['kind'] as String),
            name: r['name'] as String,
            description: (r['description'] as String?) ?? '',
            sortOrder: (r['sort_order'] as num).toInt(),
          ),
        )
        .toList();

    final articleRows = await db.query(
      'articles',
      orderBy: 'updated_at DESC, created_at DESC',
    );
    final diagramRows = await db.query(
      'article_diagrams',
      orderBy: 'sort_order ASC',
    );

    final diagramsByArticle = <String, List<ArticleDiagram>>{};
    for (final row in diagramRows) {
      final articleId = row['article_id'] as String;
      final sceneMap =
          jsonDecode(row['scene_json'] as String) as Map<String, dynamic>;
      final diagram = ArticleDiagram(
        id: row['id'] as String,
        articleId: articleId,
        sortOrder: (row['sort_order'] as num).toInt(),
        caption: (row['caption'] as String?) ?? '',
        scene: DiagramScene.fromJson(sceneMap),
      );
      diagramsByArticle.putIfAbsent(articleId, () => []).add(diagram);
    }

    final loadedArticles = articleRows.map((row) {
      final id = row['id'] as String;
      final strokeMap =
          jsonDecode(row['stroke_params_json'] as String) as Map<String, dynamic>;
      return Article(
        id: id,
        code: row['code'] as String,
        kind: ArticleKind.fromKey(row['kind'] as String),
        title: row['title'] as String,
        summary: (row['summary'] as String?) ?? '',
        primaryGroupId: row['primary_group_id'] as String,
        tags: (jsonDecode(row['tags_json'] as String) as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        difficulty: Difficulty.fromKey(row['difficulty'] as String),
        goal: (row['goal'] as String?) ?? '',
        content: (row['content'] as String?) ?? '',
        steps: (jsonDecode(row['steps_json'] as String) as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        commonMistakes: (row['common_mistakes'] as String?) ?? '',
        source: row['source'] as String?,
        author: row['author'] as String?,
        sourcePage: row['source_page'] as String?,
        isDraft: (row['is_draft'] as num).toInt() != 0,
        strokeParameters: StrokeParameters.fromJson(strokeMap),
        diagrams: diagramsByArticle[id] ?? const [],
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isFavorite: (row['is_favorite'] as num).toInt() != 0,
        practiceStatus: PracticeStatus.fromKey(row['practice_status'] as String),
        relatedArticleIds:
            (jsonDecode(row['related_article_ids_json'] as String)
                    as List<dynamic>)
                .map((e) => e as String)
                .toList(),
      );
    }).toList();

    _groups
      ..clear()
      ..addAll(loadedGroups);
    _articles
      ..clear()
      ..addAll(loadedArticles);
  }

  Future<T> _serializedWrite<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  String generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}'
        '${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }

  Future<String> _allocateNextCode(Transaction txn, ArticleKind kind) async {
    final counterRows = await txn.query(
      'code_counters',
      where: 'kind = ?',
      whereArgs: [kind.storageKey],
    );
    var lastNumber = counterRows.isNotEmpty
        ? (counterRows.first['last_number'] as num).toInt()
        : 0;

    final prefix = kind.codePrefix;
    final existingCodes = await txn.query(
      'articles',
      columns: ['code'],
      where: 'kind = ?',
      whereArgs: [kind.storageKey],
    );
    final regex = RegExp('^${RegExp.escape(prefix)}-(\\d+)\$');
    for (final row in existingCodes) {
      final code = row['code'] as String;
      final match = regex.firstMatch(code);
      if (match != null) {
        final numVal = int.tryParse(match.group(1)!);
        if (numVal != null && numVal > lastNumber) {
          lastNumber = numVal;
        }
      }
    }

    final nextNumber = lastNumber + 1;
    await txn.insert(
      'code_counters',
      {'kind': kind.storageKey, 'last_number': nextNumber},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return '$prefix-${nextNumber.toString().padLeft(3, '0')}';
  }

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
  }) {
    return _articles.where((article) {
      if (kind != null && article.kind != kind) return false;
      if (groupId != null && article.primaryGroupId != groupId) return false;
      if (favoritesOnly && !article.isFavorite) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Article? getArticleById(String id) {
    for (final a in _articles) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Future<Article> saveArticle(Article draft) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;

      final minimalErr = draft.validateMinimalForSave();
      if (minimalErr != null) {
        throw FormatException(minimalErr);
      }

      for (var i = 0; i < draft.diagrams.length; i++) {
        final sceneErr =
            SceneValidator.validateCompleteForSave(draft.diagrams[i].scene);
        if (sceneErr != null) {
          throw FormatException('Sơ đồ ${i + 1} chưa hợp lệ:\n$sceneErr');
        }
      }

      late Article persisted;
      await db.transaction((txn) async {
        final now = DateTime.now().toUtc();
        final articleId =
            draft.id.trim().isEmpty ? generateUuidV4() : draft.id.trim();

        final existingRows = await txn.query(
          'articles',
          columns: ['id', 'code', 'kind', 'created_at'],
          where: 'id = ?',
          whereArgs: [articleId],
        );

        late final String resolvedCode;
        late final DateTime resolvedCreatedAt;

        if (existingRows.isEmpty) {
          resolvedCode = draft.code.trim().isEmpty
              ? await _allocateNextCode(txn, draft.kind)
              : draft.code.trim();
          resolvedCreatedAt = draft.createdAt.toUtc();
        } else {
          final row = existingRows.first;
          final prevKind = ArticleKind.fromKey(row['kind'] as String);
          resolvedCode = prevKind == draft.kind
              ? (row['code'] as String)
              : await _allocateNextCode(txn, draft.kind);
          resolvedCreatedAt = DateTime.parse(row['created_at'] as String);
        }

        final normalizedDiagrams = <ArticleDiagram>[];
        for (var i = 0; i < draft.diagrams.length; i++) {
          final d = draft.diagrams[i];
          final diagId = d.id.trim().isEmpty ? generateUuidV4() : d.id.trim();
          final diagScene = d.scene.id == diagId
              ? d.scene
              : d.scene.copyWith(id: diagId);
          normalizedDiagrams.add(
            ArticleDiagram(
              id: diagId,
              articleId: articleId,
              sortOrder: i,
              caption: d.caption,
              scene: diagScene,
            ),
          );
        }

        persisted = draft.copyWith(
          id: articleId,
          code: resolvedCode,
          diagrams: normalizedDiagrams,
          createdAt: resolvedCreatedAt,
          updatedAt: now,
        );

        await txn.insert(
          'articles',
          {
            'id': persisted.id,
            'code': persisted.code,
            'kind': persisted.kind.storageKey,
            'title': persisted.title.trim(),
            'summary': persisted.summary,
            'primary_group_id': persisted.primaryGroupId,
            'tags_json': jsonEncode(persisted.tags),
            'difficulty': persisted.difficulty.storageKey,
            'goal': persisted.goal,
            'content': persisted.content,
            'steps_json': jsonEncode(persisted.steps),
            'common_mistakes': persisted.commonMistakes,
            'source': persisted.source,
            'author': persisted.author,
            'source_page': persisted.sourcePage,
            'is_draft': persisted.isDraft ? 1 : 0,
            'stroke_params_json':
                jsonEncode(persisted.strokeParameters.toJson()),
            'created_at': persisted.createdAt.toIso8601String(),
            'updated_at': persisted.updatedAt.toIso8601String(),
            'is_favorite': persisted.isFavorite ? 1 : 0,
            'practice_status': persisted.practiceStatus.storageKey,
            'related_article_ids_json': jsonEncode(persisted.relatedArticleIds),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await debugTransactionHook?.call(txn, 'after_article_insert');

        await txn.delete(
          'article_diagrams',
          where: 'article_id = ?',
          whereArgs: [persisted.id],
        );

        for (final diag in normalizedDiagrams) {
          await txn.insert('article_diagrams', {
            'id': diag.id,
            'article_id': diag.articleId,
            'sort_order': diag.sortOrder,
            'caption': diag.caption,
            'scene_json': jsonEncode(diag.scene.toJson()),
          });
        }

        await debugTransactionHook?.call(txn, 'before_commit');
      });

      await _reloadCacheFromDb(db);
      return getArticleById(persisted.id) ?? persisted;
    });
  }

  @override
  Future<Article> duplicateArticle(String sourceArticleId) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      await _reloadCacheFromDb(db);
      final source = getArticleById(sourceArticleId);
      if (source == null) {
        throw StateError('Không tìm thấy bài viết để nhân bản.');
      }

      late Article cloned;
      await db.transaction((txn) async {
        final now = DateTime.now().toUtc();
        final newArticleId = generateUuidV4();
        final newCode = await _allocateNextCode(txn, source.kind);

        final clonedDiagrams = <ArticleDiagram>[];
        for (var i = 0; i < source.diagrams.length; i++) {
          final srcDiag = source.diagrams[i];
          final newDiagId = generateUuidV4();
          final clonedScene = srcDiag.scene.copyWith(id: newDiagId);
          clonedDiagrams.add(
            ArticleDiagram(
              id: newDiagId,
              articleId: newArticleId,
              sortOrder: i,
              caption: srcDiag.caption,
              scene: clonedScene,
            ),
          );
        }

        cloned = source.copyWith(
          id: newArticleId,
          code: newCode,
          title: '${source.title} (Bản sao)',
          diagrams: clonedDiagrams,
          createdAt: now,
          updatedAt: now,
        );

        await txn.insert('articles', {
          'id': cloned.id,
          'code': cloned.code,
          'kind': cloned.kind.storageKey,
          'title': cloned.title,
          'summary': cloned.summary,
          'primary_group_id': cloned.primaryGroupId,
          'tags_json': jsonEncode(cloned.tags),
          'difficulty': cloned.difficulty.storageKey,
          'goal': cloned.goal,
          'content': cloned.content,
          'steps_json': jsonEncode(cloned.steps),
          'common_mistakes': cloned.commonMistakes,
          'source': cloned.source,
          'author': cloned.author,
          'source_page': cloned.sourcePage,
          'is_draft': cloned.isDraft ? 1 : 0,
          'stroke_params_json': jsonEncode(cloned.strokeParameters.toJson()),
          'created_at': cloned.createdAt.toIso8601String(),
          'updated_at': cloned.updatedAt.toIso8601String(),
          'is_favorite': cloned.isFavorite ? 1 : 0,
          'practice_status': cloned.practiceStatus.storageKey,
          'related_article_ids_json': jsonEncode(cloned.relatedArticleIds),
        });

        await debugTransactionHook?.call(txn, 'after_duplicate_article_insert');

        for (final diag in clonedDiagrams) {
          await txn.insert('article_diagrams', {
            'id': diag.id,
            'article_id': diag.articleId,
            'sort_order': diag.sortOrder,
            'caption': diag.caption,
            'scene_json': jsonEncode(diag.scene.toJson()),
          });
        }
      });

      await _reloadCacheFromDb(db);
      return getArticleById(cloned.id) ?? cloned;
    });
  }

  @override
  Future<void> deleteArticle(String articleId) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      await db.transaction((txn) async {
        await txn.delete(
          'article_diagrams',
          where: 'article_id = ?',
          whereArgs: [articleId],
        );
        await txn.delete(
          'articles',
          where: 'id = ?',
          whereArgs: [articleId],
        );
      });
      await _reloadCacheFromDb(db);
    });
  }

  @override
  Future<Article?> toggleFavorite(String articleId) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      await _reloadCacheFromDb(db);
      final existing = getArticleById(articleId);
      if (existing == null) return null;
      final nextFav = !existing.isFavorite;
      await db.update(
        'articles',
        {'is_favorite': nextFav ? 1 : 0},
        where: 'id = ?',
        whereArgs: [articleId],
      );
      await _reloadCacheFromDb(db);
      return getArticleById(articleId);
    });
  }

  @override
  List<Collection> getCollections() => List.unmodifiable(_collections);

  @override
  List<Tag> getTags() => List.unmodifiable(_tags);

  @override
  Future<void> close() async {
    await _writeQueue.catchError((_) {});
    final db = _db;
    _db = null;
    _initFuture = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}

