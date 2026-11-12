import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../geometry/scene_validator.dart';
import '../models/models.dart';
import 'article_asset_store.dart';
import 'notebook_repository.dart';

typedef SqliteTransactionHook = Future<void> Function(
  Transaction txn,
  String stage,
);

/// Kho lưu trữ chính bằng SQLite cho bài viết, sơ đồ gắn theo bài, nhóm biên tập và bộ đếm mã bài.
/// - Mọi thao tác lưu/sửa/nhân bản/xóa bài + sơ đồ chạy trong transaction nguyên tử.
/// - Không đụng tới tệp `primary_scene.json` của bàn dựng độc lập từ Phase 2–3.
class SqliteNotebookRepository implements NotebookRepository {
  static const int schemaVersion = 3;
  static const String defaultDbFileName = 'libre_billiard.db';

  final String? dbPath;
  final DatabaseFactory? databaseFactoryOverride;
  final Future<String> Function()? directoryPathProvider;
  final SqliteTransactionHook? debugTransactionHook;
  late final ArticleAssetStore _assetStore;

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
    ArticleAssetStore? assetStore,
  }) {
    if (assetStore != null) {
      _assetStore = assetStore;
    } else if (directoryPathProvider != null) {
      _assetStore = ArticleAssetStore(
        directoryProvider: () async => Directory(await directoryPathProvider!()),
      );
    } else if (dbPath != null && dbPath != inMemoryDatabasePath) {
      _assetStore = ArticleAssetStore(
        directoryProvider: () async => Directory(p.dirname(dbPath!)),
      );
    } else {
      _assetStore = ArticleAssetStore();
    }
  }

  @override
  ArticleAssetStore get assetStore => _assetStore;

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
        onUpgrade: (db, oldVersion, newVersion) async {
          await _migrateSchema(db, oldVersion, newVersion);
        },
      ),
    );
    _db = db;

    await _ensureInitialSeedOnce(db);
    await _reloadCacheFromDb(db);
    if (!isInMemory) {
      final activeAssets = <String>{
        for (final art in _articles)
          for (final img in art.images) img.assetId,
      };
      await _assetStore.cleanupOrphanedAssets(
        referencedAssetIds: activeAssets,
      );
    }
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
        source_url TEXT,
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
    await _createPhase4BTables(db);
    await _createPhase4CTables(db);
  }

  Future<void> _createPhase4CTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS article_images (
        id TEXT PRIMARY KEY,
        article_id TEXT NOT NULL,
        asset_id TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        original_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        width INTEGER,
        height INTEGER,
        caption TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_article_images_order '
      'ON article_images(article_id, sort_order)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_article_images_asset '
      'ON article_images(asset_id)',
    );
  }

  Future<void> _createPhase4BTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY,
        normalized_key TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        aliases_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS collection_items (
        collection_id TEXT NOT NULL,
        article_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        PRIMARY KEY (collection_id, article_id),
        FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE,
        FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_collection_items_order '
      'ON collection_items(collection_id, sort_order)',
    );
  }

  Future<void> _migrateSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createPhase4BTables(db);

      // Bảo đảm nhóm Chưa phân loại tồn tại cho mọi loại bài mà không ghi đè dữ liệu cũ.
      for (final kind in ArticleKind.values) {
        final unc = DefaultEditorialGroups.unclassifiedGroupFor(kind);
        await db.insert(
          'editorial_groups',
          {
            'id': unc.id,
            'kind': unc.kind.storageKey,
            'name': unc.name,
            'description': unc.description,
            'sort_order': unc.sortOrder,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Đồng bộ toàn bộ thẻ đã có trong bài viết Phase 4A vào bảng tags.
      final articleRows = await db.query('articles', columns: ['tags_json']);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      for (final row in articleRows) {
        final decoded = jsonDecode(row['tags_json'] as String) as List<dynamic>;
        for (final raw in decoded) {
          final clean = VietnameseSearchNormalizer.cleanTagDisplay(raw.toString());
          if (clean.isEmpty) continue;
          final key = VietnameseSearchNormalizer.tagDuplicateKey(clean);
          await db.insert(
            'tags',
            {
              'id': generateUuidV4(),
              'normalized_key': key,
              'name': clean,
              'aliases_json': '[]',
              'created_at': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    }
    if (oldVersion < 3) {
      final cols = await db.rawQuery('PRAGMA table_info(articles)');
      final hasSourceUrl = cols.any((c) => c['name'] == 'source_url');
      if (!hasSourceUrl) {
        await db.execute('ALTER TABLE articles ADD COLUMN source_url TEXT');
      }
      await _createPhase4CTables(db);
    }
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
          DefaultEditorialGroups.unclassifiedGroupFor(ArticleKind.technique),
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
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Bảo đảm mỗi loại đều có nhóm Chưa phân loại (chỉ thêm nếu thiếu, không ghi đè).
      for (final kind in ArticleKind.values) {
        final unc = DefaultEditorialGroups.unclassifiedGroupFor(kind);
        await txn.insert(
          'editorial_groups',
          {
            'id': unc.id,
            'kind': unc.kind.storageKey,
            'name': unc.name,
            'description': unc.description,
            'sort_order': unc.sortOrder,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
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

    final imageRows = await db.query(
      'article_images',
      orderBy: 'sort_order ASC',
    );
    final imagesByArticle = <String, List<ArticleImageAttachment>>{};
    for (final row in imageRows) {
      final articleId = row['article_id'] as String;
      final img = ArticleImageAttachment(
        id: row['id'] as String,
        articleId: articleId,
        assetId: row['asset_id'] as String,
        relativePath: row['relative_path'] as String,
        originalName: (row['original_name'] as String?) ?? 'image',
        mimeType: (row['mime_type'] as String?) ?? 'image/jpeg',
        sizeBytes: (row['size_bytes'] as num).toInt(),
        width: (row['width'] as num?)?.toInt(),
        height: (row['height'] as num?)?.toInt(),
        caption: (row['caption'] as String?) ?? '',
        sortOrder: (row['sort_order'] as num).toInt(),
      );
      imagesByArticle.putIfAbsent(articleId, () => []).add(img);
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
        sourceUrl: row['source_url'] as String?,
        isDraft: (row['is_draft'] as num).toInt() != 0,
        strokeParameters: StrokeParameters.fromJson(strokeMap),
        diagrams: diagramsByArticle[id] ?? const [],
        images: imagesByArticle[id] ?? const [],
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

    final tagRows = await db.query(
      'tags',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final loadedTags = tagRows.map((row) {
      final aliasesRaw = (row['aliases_json'] as String?) ?? '[]';
      final aliases = (jsonDecode(aliasesRaw) as List<dynamic>)
          .map((e) => e.toString())
          .toList();
      return Tag(
        id: row['id'] as String,
        name: row['name'] as String,
        aliases: aliases,
      );
    }).toList();

    final collectionRows = await db.query(
      'collections',
      orderBy: 'updated_at DESC, name COLLATE NOCASE ASC',
    );
    final itemRows = await db.query(
      'collection_items',
      orderBy: 'sort_order ASC',
    );
    final articleIdsByCollection = <String, List<String>>{};
    for (final row in itemRows) {
      final cid = row['collection_id'] as String;
      final aid = row['article_id'] as String;
      articleIdsByCollection.putIfAbsent(cid, () => []).add(aid);
    }
    final loadedCollections = collectionRows.map((row) {
      final cid = row['id'] as String;
      return Collection(
        id: cid,
        name: row['name'] as String,
        orderedArticleIds: articleIdsByCollection[cid] ?? const [],
      );
    }).toList();

    _groups
      ..clear()
      ..addAll(loadedGroups);
    _articles
      ..clear()
      ..addAll(loadedArticles);
    _tags
      ..clear()
      ..addAll(loadedTags);
    _collections
      ..clear()
      ..addAll(loadedCollections);
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

  List<String> _dedupeTags(List<String> rawTags) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in rawTags) {
      final clean = VietnameseSearchNormalizer.cleanTagDisplay(raw);
      if (clean.isEmpty) continue;
      final key = VietnameseSearchNormalizer.tagDuplicateKey(clean);
      if (seen.add(key)) {
        result.add(clean);
      }
    }
    return result;
  }

  Future<void> _upsertTagsInTxn(
    Transaction txn,
    List<String> cleanTags,
    DateTime now,
  ) async {
    final nowIso = now.toIso8601String();
    for (final tagName in cleanTags) {
      final key = VietnameseSearchNormalizer.tagDuplicateKey(tagName);
      await txn.insert(
        'tags',
        {
          'id': generateUuidV4(),
          'normalized_key': key,
          'name': tagName,
          'aliases_json': '[]',
          'created_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
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

      final normalizedTags = _dedupeTags(draft.tags);

      // Xác định ảnh mới cần promote từ staging sang vùng bền vững trước transaction SQLite.
      final existingArticleId = draft.id.trim();
      final prevImages = existingArticleId.isEmpty
          ? const <ArticleImageAttachment>[]
          : (getArticleById(existingArticleId)?.images ??
              const <ArticleImageAttachment>[]);
      final prevAssetPaths = <String, String>{
        for (final img in prevImages) img.assetId: img.relativePath,
      };

      for (final img in draft.images) {
        final alreadyPersisted = prevAssetPaths.containsKey(img.assetId);
        if (!alreadyPersisted) {
          await _assetStore.promoteStagedAsset(
            assetId: img.assetId,
            relativePath: img.relativePath,
          );
          final committedFile =
              await _assetStore.resolveRelativePath(img.relativePath);
          if (!await committedFile.exists()) {
            throw FileSystemException(
              'Không thể xác minh tệp ảnh đã lưu.',
              committedFile.path,
            );
          }
        }
      }

      late Article persisted;
      final candidateDeleteAssets = <String, String>{};
      await db.transaction((txn) async {
        // Kiểm tra nhóm chính phải tồn tại và thuộc đúng loại bài viết.
        final groupRows = await txn.query(
          'editorial_groups',
          columns: ['id', 'kind'],
          where: 'id = ?',
          whereArgs: [draft.primaryGroupId],
        );
        if (groupRows.isEmpty) {
          throw const FormatException('Nhóm chính không tồn tại.');
        }
        final groupKind = ArticleKind.fromKey(groupRows.first['kind'] as String);
        if (groupKind != draft.kind) {
          throw const FormatException(
            'Nhóm chính phải thuộc đúng loại bài viết.',
          );
        }

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
          resolvedCreatedAt = now;
        } else {
          final row = existingRows.first;
          final prevKind = ArticleKind.fromKey(row['kind'] as String);
          resolvedCode = prevKind == draft.kind
              ? (row['code'] as String)
              : await _allocateNextCode(txn, draft.kind);
          resolvedCreatedAt = DateTime.parse(row['created_at'] as String).toUtc();
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

        final normalizedImages = <ArticleImageAttachment>[];
        for (var i = 0; i < draft.images.length; i++) {
          final img = draft.images[i];
          final imgId =
              img.id.trim().isEmpty ? generateUuidV4() : img.id.trim();
          normalizedImages.add(
            img.copyWith(
              id: imgId,
              articleId: articleId,
              sortOrder: i,
            ),
          );
        }

        persisted = draft.copyWith(
          id: articleId,
          code: resolvedCode,
          tags: normalizedTags,
          diagrams: normalizedDiagrams,
          images: normalizedImages,
          createdAt: resolvedCreatedAt,
          updatedAt: now,
        );

        final values = <String, Object?>{
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
          'source_url': persisted.sourceUrl,
          'is_draft': persisted.isDraft ? 1 : 0,
          'stroke_params_json': jsonEncode(persisted.strokeParameters.toJson()),
          'created_at': persisted.createdAt.toIso8601String(),
          'updated_at': persisted.updatedAt.toIso8601String(),
          'is_favorite': persisted.isFavorite ? 1 : 0,
          'practice_status': persisted.practiceStatus.storageKey,
          'related_article_ids_json': jsonEncode(persisted.relatedArticleIds),
        };

        // Không dùng INSERT OR REPLACE để tránh kích hoạt ON DELETE CASCADE ngoài ý muốn.
        if (existingRows.isEmpty) {
          await txn.insert('articles', {'id': persisted.id, ...values});
        } else {
          await txn.update(
            'articles',
            values,
            where: 'id = ?',
            whereArgs: [persisted.id],
          );
        }

        await _upsertTagsInTxn(txn, normalizedTags, now);

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

        await txn.delete(
          'article_images',
          where: 'article_id = ?',
          whereArgs: [persisted.id],
        );

        for (final img in normalizedImages) {
          await txn.insert('article_images', {
            'id': img.id,
            'article_id': img.articleId,
            'asset_id': img.assetId,
            'relative_path': img.relativePath,
            'original_name': img.originalName,
            'mime_type': img.mimeType,
            'size_bytes': img.sizeBytes,
            'width': img.width,
            'height': img.height,
            'caption': img.caption,
            'sort_order': img.sortOrder,
          });
        }

        final keptAssetIds = normalizedImages.map((e) => e.assetId).toSet();
        for (final entry in prevAssetPaths.entries) {
          if (!keptAssetIds.contains(entry.key)) {
            candidateDeleteAssets[entry.key] = entry.value;
          }
        }

        await debugTransactionHook?.call(txn, 'before_commit');
      });

      // Chỉ xóa tệp vật lý sau khi SQLite commit và không còn bài nào khác tham chiếu assetId.
      for (final entry in candidateDeleteAssets.entries) {
        await _deleteAssetIfUnreferenced(db, entry.key, entry.value);
      }

      await _reloadCacheFromDb(db);
      return getArticleById(persisted.id) ?? persisted;
    });
  }

  Future<void> _deleteAssetIfUnreferenced(
    Database db,
    String assetId,
    String relativePath,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM article_images WHERE asset_id = ?',
      [assetId],
    );
    final count = (rows.first['cnt'] as num?)?.toInt() ?? 0;
    if (count == 0) {
      try {
        await _assetStore.deleteCommittedAsset(relativePath);
      } catch (_) {}
    }
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

        final clonedImages = <ArticleImageAttachment>[];
        for (var i = 0; i < source.images.length; i++) {
          final srcImg = source.images[i];
          clonedImages.add(
            srcImg.copyWith(
              id: generateUuidV4(),
              articleId: newArticleId,
              sortOrder: i,
            ),
          );
        }

        cloned = source.copyWith(
          id: newArticleId,
          code: newCode,
          title: '${source.title} (Bản sao)',
          diagrams: clonedDiagrams,
          images: clonedImages,
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
          'source_url': cloned.sourceUrl,
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
        for (final img in clonedImages) {
          await txn.insert('article_images', {
            'id': img.id,
            'article_id': img.articleId,
            'asset_id': img.assetId,
            'relative_path': img.relativePath,
            'original_name': img.originalName,
            'mime_type': img.mimeType,
            'size_bytes': img.sizeBytes,
            'width': img.width,
            'height': img.height,
            'caption': img.caption,
            'sort_order': img.sortOrder,
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
      final candidateAssets = <String, String>{};
      await db.transaction((txn) async {
        final imgRows = await txn.query(
          'article_images',
          columns: ['asset_id', 'relative_path'],
          where: 'article_id = ?',
          whereArgs: [articleId],
        );
        for (final row in imgRows) {
          candidateAssets[row['asset_id'] as String] =
              row['relative_path'] as String;
        }
        await txn.delete(
          'collection_items',
          where: 'article_id = ?',
          whereArgs: [articleId],
        );
        await txn.delete(
          'article_images',
          where: 'article_id = ?',
          whereArgs: [articleId],
        );
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
      for (final entry in candidateAssets.entries) {
        await _deleteAssetIfUnreferenced(db, entry.key, entry.value);
      }
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
  EditorialGroup? getGroupById(String groupId) {
    for (final g in _groups) {
      if (g.id == groupId) return g;
    }
    return null;
  }

  @override
  int countArticlesInGroup(String groupId) {
    return _articles.where((a) => a.primaryGroupId == groupId).length;
  }

  @override
  Future<EditorialGroup> saveGroup({
    String? id,
    required ArticleKind kind,
    required String name,
    String description = '',
  }) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      final cleanName = name.trim();
      if (cleanName.isEmpty) {
        throw const FormatException('Tên nhóm không được để trống.');
      }

      late String resolvedId;
      await db.transaction((txn) async {
        final existingId = id?.trim();
        if (existingId != null && existingId.isNotEmpty) {
          final rows = await txn.query(
            'editorial_groups',
            where: 'id = ?',
            whereArgs: [existingId],
          );
          if (rows.isEmpty) {
            throw StateError('Không tìm thấy nhóm để cập nhật.');
          }
          await txn.update(
            'editorial_groups',
            {'name': cleanName, 'description': description.trim()},
            where: 'id = ?',
            whereArgs: [existingId],
          );
          resolvedId = existingId;
        } else {
          final maxOrderRows = await txn.rawQuery(
            'SELECT COALESCE(MAX(sort_order), 0) AS max_order '
            'FROM editorial_groups WHERE kind = ?',
            [kind.storageKey],
          );
          final maxOrder =
              (maxOrderRows.first['max_order'] as num?)?.toInt() ?? 0;
          resolvedId = generateUuidV4();
          await txn.insert('editorial_groups', {
            'id': resolvedId,
            'kind': kind.storageKey,
            'name': cleanName,
            'description': description.trim(),
            'sort_order': maxOrder + 1,
          });
        }
      });

      await _reloadCacheFromDb(db);
      return getGroupById(resolvedId)!;
    });
  }

  @override
  Future<void> reorderGroups(ArticleKind kind, List<String> orderedGroupIds) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      await db.transaction((txn) async {
        for (var i = 0; i < orderedGroupIds.length; i++) {
          await txn.update(
            'editorial_groups',
            {'sort_order': i + 1},
            where: 'id = ? AND kind = ?',
            whereArgs: [orderedGroupIds[i], kind.storageKey],
          );
        }
      });
      await _reloadCacheFromDb(db);
    });
  }

  @override
  Future<void> deleteGroup({
    required String groupId,
    required String targetGroupId,
  }) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      if (DefaultEditorialGroups.isUnclassifiedGroupId(groupId)) {
        throw const FormatException('Không thể xóa nhóm Chưa phân loại.');
      }
      if (groupId == targetGroupId) {
        throw const FormatException('Nhóm nhận bài phải khác nhóm đang xóa.');
      }

      await db.transaction((txn) async {
        final srcRows = await txn.query(
          'editorial_groups',
          where: 'id = ?',
          whereArgs: [groupId],
        );
        if (srcRows.isEmpty) {
          throw StateError('Không tìm thấy nhóm cần xóa.');
        }
        final dstRows = await txn.query(
          'editorial_groups',
          where: 'id = ?',
          whereArgs: [targetGroupId],
        );
        if (dstRows.isEmpty) {
          throw const FormatException('Nhóm đích không tồn tại.');
        }
        final srcKind = srcRows.first['kind'] as String;
        final dstKind = dstRows.first['kind'] as String;
        if (srcKind != dstKind) {
          throw const FormatException(
            'Nhóm nhận bài phải thuộc cùng loại với nhóm bị xóa.',
          );
        }

        await txn.update(
          'articles',
          {'primary_group_id': targetGroupId},
          where: 'primary_group_id = ?',
          whereArgs: [groupId],
        );

        await debugTransactionHook?.call(txn, 'before_delete_group');

        await txn.delete(
          'editorial_groups',
          where: 'id = ?',
          whereArgs: [groupId],
        );
      });

      await _reloadCacheFromDb(db);
    });
  }

  @override
  List<Collection> getCollections() => List.unmodifiable(_collections);

  @override
  Collection? getCollectionById(String collectionId) {
    for (final c in _collections) {
      if (c.id == collectionId) return c;
    }
    return null;
  }

  @override
  List<Collection> getCollectionsForArticle(String articleId) {
    return _collections
        .where((c) => c.orderedArticleIds.contains(articleId))
        .toList(growable: false);
  }

  @override
  Future<Collection> createCollection(String name) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      final cleanName = name.trim();
      if (cleanName.isEmpty) {
        throw const FormatException('Tên bộ sưu tập không được để trống.');
      }
      final id = generateUuidV4();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      await db.transaction((txn) async {
        await txn.insert('collections', {
          'id': id,
          'name': cleanName,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        await debugTransactionHook?.call(txn, 'before_create_collection');
      });
      await _reloadCacheFromDb(db);
      return getCollectionById(id)!;
    });
  }

  @override
  Future<Collection> renameCollection(String collectionId, String newName) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      final cleanName = newName.trim();
      if (cleanName.isEmpty) {
        throw const FormatException('Tên bộ sưu tập không được để trống.');
      }
      final updatedCount = await db.update(
        'collections',
        {
          'name': cleanName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [collectionId],
      );
      if (updatedCount == 0) {
        throw StateError('Không tìm thấy bộ sưu tập.');
      }
      await _reloadCacheFromDb(db);
      return getCollectionById(collectionId)!;
    });
  }

  @override
  Future<void> deleteCollection(String collectionId) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      await db.transaction((txn) async {
        await txn.delete(
          'collection_items',
          where: 'collection_id = ?',
          whereArgs: [collectionId],
        );
        await txn.delete(
          'collections',
          where: 'id = ?',
          whereArgs: [collectionId],
        );
      });
      await _reloadCacheFromDb(db);
    });
  }

  @override
  Future<void> addArticleToCollection({
    required String collectionId,
    required String articleId,
  }) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      await db.transaction((txn) async {
        final colRows = await txn.query(
          'collections',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [collectionId],
        );
        if (colRows.isEmpty) {
          throw StateError('Bộ sưu tập không tồn tại.');
        }
        final artRows = await txn.query(
          'articles',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [articleId],
        );
        if (artRows.isEmpty) {
          throw StateError('Bài viết không tồn tại.');
        }
        final exists = await txn.query(
          'collection_items',
          columns: ['collection_id'],
          where: 'collection_id = ? AND article_id = ?',
          whereArgs: [collectionId, articleId],
        );
        if (exists.isNotEmpty) return;

        final maxRows = await txn.rawQuery(
          'SELECT COALESCE(MAX(sort_order), -1) AS max_order '
          'FROM collection_items WHERE collection_id = ?',
          [collectionId],
        );
        final nextOrder =
            ((maxRows.first['max_order'] as num?)?.toInt() ?? -1) + 1;
        await txn.insert('collection_items', {
          'collection_id': collectionId,
          'article_id': articleId,
          'sort_order': nextOrder,
        });
        await txn.update(
          'collections',
          {'updated_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [collectionId],
        );
        await debugTransactionHook?.call(txn, 'before_add_collection_item');
      });
      await _reloadCacheFromDb(db);
    });
  }

  @override
  Future<void> removeArticleFromCollection({
    required String collectionId,
    required String articleId,
  }) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      await db.transaction((txn) async {
        await txn.delete(
          'collection_items',
          where: 'collection_id = ? AND article_id = ?',
          whereArgs: [collectionId, articleId],
        );
        final remaining = await txn.query(
          'collection_items',
          columns: ['article_id'],
          where: 'collection_id = ?',
          whereArgs: [collectionId],
          orderBy: 'sort_order ASC',
        );
        for (var i = 0; i < remaining.length; i++) {
          await txn.update(
            'collection_items',
            {'sort_order': i},
            where: 'collection_id = ? AND article_id = ?',
            whereArgs: [collectionId, remaining[i]['article_id']],
          );
        }
        await txn.update(
          'collections',
          {'updated_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [collectionId],
        );
        await debugTransactionHook?.call(txn, 'before_remove_collection_item');
      });
      await _reloadCacheFromDb(db);
    });
  }

  @override
  Future<void> reorderCollectionArticles({
    required String collectionId,
    required List<String> orderedArticleIds,
  }) {
    return _serializedWrite(() async {
      await initialize();
      final db = _db!;
      await db.transaction((txn) async {
        for (var i = 0; i < orderedArticleIds.length; i++) {
          await txn.update(
            'collection_items',
            {'sort_order': i},
            where: 'collection_id = ? AND article_id = ?',
            whereArgs: [collectionId, orderedArticleIds[i]],
          );
        }
        await txn.update(
          'collections',
          {'updated_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [collectionId],
        );
        await debugTransactionHook?.call(txn, 'before_reorder_collection');
      });
      await _reloadCacheFromDb(db);
    });
  }

  @override
  List<Tag> getTags() => List.unmodifiable(_tags);

  @override
  List<String> suggestTags(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return _tags.map((t) => t.name).toList(growable: false);
    }
    return _tags
        .where((t) => VietnameseSearchNormalizer.matches(t.name, trimmed))
        .map((t) => t.name)
        .toList(growable: false);
  }

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

