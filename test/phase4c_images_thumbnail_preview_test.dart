import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/main.dart';
import 'package:libre_billiard_notebook/models/models.dart';
import 'package:libre_billiard_notebook/repositories/article_asset_store.dart';
import 'package:libre_billiard_notebook/repositories/sqlite_notebook_repository.dart';
import 'package:libre_billiard_notebook/state/notebook_controller.dart';
import 'package:libre_billiard_notebook/ui/screens/article_detail_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/article_editor_screen.dart';
import 'package:libre_billiard_notebook/ui/widgets/article_thumbnail.dart';
import 'package:libre_billiard_notebook/ui/widgets/billiard_table_canvas.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Valid 1x1 RGBA PNG bytes.
Uint8List _validPng1x1() => Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, //
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, //
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, //
  0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, //
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, //
  0xAE, 0x42, 0x60, 0x82,
]);

/// Valid JPEG header (3x2) for format & dimension parser tests.
Uint8List _validJpegHeader3x2() => Uint8List.fromList(const [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, //
  0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, //
  0x00, 0x01, 0x00, 0x00, //
  0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x02, 0x00, //
  0x03, 0x01, 0x01, 0x11, 0x00, //
  0xFF, 0xD9,
]);

/// PNG header declaring 9000x1 px (exceeds 8192 px limit).
Uint8List _oversizedDimensionPng() {
  final bytes = Uint8List.fromList(_validPng1x1());
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(16, 9000, Endian.big);
  return bytes;
}

Future<void> _flushRealAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder target, {
  int maxTries = 30,
}) async {
  for (var i = 0; i < maxTries && target.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// Đóng repo khi còn tác vụ ghi được xếp hàng trong FakeAsync zone
/// (ví dụ dọn ảnh nháp sau "Bỏ thay đổi"): xen kẽ thời gian thực và pump
/// để hàng đợi ghi chạy xong, tránh deadlock của runAsync(close).
Future<void> _closeRepo(WidgetTester tester, SqliteNotebookRepository repo) async {
  var done = false;
  Object? error;
  repo.close().then((_) => done = true, onError: (Object e) {
    error = e;
    done = true;
  });
  await _waitUntil(tester, () => done, maxTries: 400);
  if (error != null) throw error!;
  expect(done, isTrue, reason: 'repo.close() không hoàn tất');
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxTries = 40,
}) async {
  for (var i = 0; i < maxTries && !predicate(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target, {
  double delta = 250.0,
}) async {
  final primaryStep = delta > 0 ? -500.0 : 500.0;
  for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).last, Offset(0, primaryStep));
    await tester.pump();
  }
  for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).last, Offset(0, -primaryStep));
    await tester.pump();
  }
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target.last);
    await tester.pump();
  }
}

Future<void> _scrollToAndTap(WidgetTester tester, Finder target) async {
  await _scrollTo(tester, target);
  await tester.tap(target);
  await _flushRealAsync(tester);
}

Future<void> _scrollToAndEnterText(
  WidgetTester tester,
  Finder target,
  String text,
) async {
  await _scrollTo(tester, target);
  await tester.enterText(target, text);
  await tester.pumpAndSettle();
}

Article _makeArticle({
  String id = '',
  String code = '',
  ArticleKind kind = ArticleKind.technique,
  required String title,
  String summary = '',
  String? primaryGroupId,
  List<String> tags = const [],
  Difficulty difficulty = Difficulty.basic,
  String? sourceUrl,
  List<ArticleDiagram> diagrams = const [],
  List<ArticleImageAttachment> images = const [],
}) {
  final ts = DateTime.utc(2026, 11, 12, 9, 0);
  return Article(
    id: id,
    code: code,
    kind: kind,
    title: title,
    summary: summary,
    primaryGroupId:
        primaryGroupId ?? DefaultEditorialGroups.unclassifiedIdFor(kind),
    tags: tags,
    difficulty: difficulty,
    goal: 'Mục tiêu $title',
    content: 'Nội dung $title',
    sourceUrl: sourceUrl,
    diagrams: diagrams,
    images: images,
    createdAt: ts,
    updatedAt: ts,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Phase 4C — A. SQLite Migration v2 -> v3', () {
    testWidgets(
      'Nâng cấp SQLite v2 lên v3 giữ nguyên bài viết, sơ đồ, nhóm, thẻ, bộ sưu tập & primary_scene.json',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_mig_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final dbPath = p.join(tempDir.path, 'notebook_v2.db');
        final primarySceneFile = File(
          p.join(tempDir.path, 'primary_scene.json'),
        );
        primarySceneFile.writeAsStringSync(
          '{"sentinel":"phase3_primary_intact"}',
        );

        await tester.runAsync(() async {
          final dbV2 = await databaseFactory.openDatabase(
            dbPath,
            options: OpenDatabaseOptions(
              version: 2,
              onCreate: (db, _) async {
                await db.execute('''
                  CREATE TABLE meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                  )
                ''');
                await db.insert('meta', {
                  'key': 'default_groups_seeded',
                  'value': '1',
                });
                await db.execute('''
                  CREATE TABLE editorial_groups (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    sort_order INTEGER NOT NULL
                  )
                ''');
                await db.execute('''
                  CREATE TABLE articles (
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
                    is_draft INTEGER NOT NULL DEFAULT 0,
                    stroke_params_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    is_favorite INTEGER NOT NULL DEFAULT 0,
                    practice_status TEXT NOT NULL,
                    related_article_ids_json TEXT NOT NULL
                  )
                ''');
                await db.execute('''
                  CREATE TABLE article_diagrams (
                    id TEXT PRIMARY KEY,
                    article_id TEXT NOT NULL,
                    sort_order INTEGER NOT NULL,
                    caption TEXT NOT NULL,
                    scene_json TEXT NOT NULL
                  )
                ''');
                await db.execute('''
                  CREATE TABLE code_counters (
                    kind TEXT PRIMARY KEY,
                    last_number INTEGER NOT NULL
                  )
                ''');
                await db.execute('''
                  CREATE TABLE tags (
                    id TEXT PRIMARY KEY,
                    normalized_key TEXT NOT NULL UNIQUE,
                    name TEXT NOT NULL,
                    aliases_json TEXT NOT NULL DEFAULT '[]',
                    created_at TEXT NOT NULL
                  )
                ''');
                await db.execute('''
                  CREATE TABLE collections (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                  )
                ''');
                await db.execute('''
                  CREATE TABLE collection_items (
                    collection_id TEXT NOT NULL,
                    article_id TEXT NOT NULL,
                    sort_order INTEGER NOT NULL,
                    PRIMARY KEY (collection_id, article_id)
                  )
                ''');

                await db.insert('editorial_groups', {
                  'id': 'grp_unclassified_technique',
                  'kind': 'technique',
                  'name': 'Chưa phân loại',
                  'description': '',
                  'sort_order': 0,
                });
                final sceneJson = jsonEncode(
                  DiagramScene.defaultInitial(id: 'diag_v2_1').toJson(),
                );
                final strokeJson = jsonEncode(
                  const StrokeParameters.defaults().toJson(),
                );
                await db.insert('articles', {
                  'id': 'art_v2_1',
                  'code': 'KT-0001',
                  'kind': 'technique',
                  'title': 'Bài v2 đầu tiên',
                  'summary': 'Tóm tắt v2',
                  'primary_group_id': 'grp_unclassified_technique',
                  'tags_json': '["gom bi","cơ bản"]',
                  'difficulty': 'basic',
                  'goal': 'Mục tiêu',
                  'content': 'Nội dung',
                  'steps_json': '["Bước 1"]',
                  'common_mistakes': '',
                  'source': 'Sách A',
                  'author': 'Tác giả B',
                  'source_page': '12',
                  'is_draft': 0,
                  'stroke_params_json': strokeJson,
                  'created_at': '2026-11-10T08:00:00.000Z',
                  'updated_at': '2026-11-10T08:00:00.000Z',
                  'is_favorite': 1,
                  'practice_status': 'not_started',
                  'related_article_ids_json': '[]',
                });
                await db.insert('articles', {
                  'id': 'art_v2_2',
                  'code': 'KT-0002',
                  'kind': 'technique',
                  'title': 'Bài v2 thứ hai',
                  'summary': '',
                  'primary_group_id': 'grp_unclassified_technique',
                  'tags_json': '[]',
                  'difficulty': 'basic',
                  'goal': '',
                  'content': 'Nội dung 2',
                  'steps_json': '[]',
                  'common_mistakes': '',
                  'source': null,
                  'author': null,
                  'source_page': null,
                  'is_draft': 0,
                  'stroke_params_json': strokeJson,
                  'created_at': '2026-11-10T09:00:00.000Z',
                  'updated_at': '2026-11-10T09:00:00.000Z',
                  'is_favorite': 0,
                  'practice_status': 'not_started',
                  'related_article_ids_json': '[]',
                });
                await db.insert('article_diagrams', {
                  'id': 'diag_v2_1',
                  'article_id': 'art_v2_1',
                  'sort_order': 0,
                  'caption': 'Sơ đồ v2',
                  'scene_json': sceneJson,
                });
                await db.insert('code_counters', {
                  'kind': 'technique',
                  'last_number': 2,
                });
                await db.insert('collections', {
                  'id': 'col_v2',
                  'name': 'Bộ sưu tập v2',
                  'created_at': '2026-11-10T10:00:00.000Z',
                  'updated_at': '2026-11-10T10:00:00.000Z',
                });
                await db.insert('collection_items', {
                  'collection_id': 'col_v2',
                  'article_id': 'art_v2_2',
                  'sort_order': 0,
                });
                await db.insert('collection_items', {
                  'collection_id': 'col_v2',
                  'article_id': 'art_v2_1',
                  'sort_order': 1,
                });
              },
            ),
          );
          await dbV2.close();

          final assetStore = ArticleAssetStore(
            directoryProvider: () async => tempDir,
          );
          final repo = SqliteNotebookRepository(
            dbPath: dbPath,
            assetStore: assetStore,
          );
          await repo.initialize();

          final articles = repo.getArticles();
          expect(articles.length, 2);
          final art1 = repo.getArticleById('art_v2_1');
          expect(art1, isNotNull);
          expect(art1!.code, 'KT-0001');
          expect(art1.tags, ['gom bi', 'cơ bản']);
          expect(art1.diagrams.length, 1);
          expect(art1.diagrams.first.caption, 'Sơ đồ v2');
          expect(art1.images, isEmpty);
          expect(art1.sourceUrl, isNull);

          final cols = repo.getCollections();
          expect(cols.length, 1);
          expect(cols.first.orderedArticleIds, ['art_v2_2', 'art_v2_1']);
          await repo.close();

          // Reopen again to verify v3 persistence is idempotent
          final repo2 = SqliteNotebookRepository(
            dbPath: dbPath,
            assetStore: assetStore,
          );
          await repo2.initialize();
          expect(repo2.getArticles().length, 2);
          await repo2.close();
        });

        expect(
          primarySceneFile.readAsStringSync(),
          '{"sentinel":"phase3_primary_intact"}',
        );
      },
    );
  });

  group('Phase 4C — B. Vòng đời ảnh, staging, ref-count & dọn mồ côi', () {
    testWidgets(
      'Thêm nhiều ảnh, sửa chú thích, đổi thứ tự, lưu & mở lại SQLite; hủy sửa giữ nguyên ảnh cũ & xóa staging',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_img_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final dbPath = p.join(tempDir.path, 'notebook.db');
        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
        );
        final repo = SqliteNotebookRepository(
          dbPath: dbPath,
          assetStore: assetStore,
        );
        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        var pickBatch = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ArticleEditorScreen(
              controller: controller,
              imagePickerOverride: () async {
                pickBatch++;
                if (pickBatch == 1) {
                  return [
                    (
                      name: '../evil/first.png',
                      path: null,
                      bytes: _validPng1x1(),
                    ),
                    (
                      name: 'second.jpg',
                      path: null,
                      bytes: _validJpegHeader3x2(),
                    ),
                  ];
                }
                return [
                  (name: 'canceled.png', path: null, bytes: _validPng1x1()),
                ];
              },
            ),
          ),
        );

        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('article_title_input')),
          'Bài có ảnh đính kèm',
        );
        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_0')),
        );
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_1')),
        );

        await _scrollTo(tester, find.byKey(const Key('editor_image_card_0')));
        expect(find.byKey(const Key('editor_image_card_0')), findsOneWidget);
        await _scrollTo(tester, find.byKey(const Key('editor_image_card_1')));
        expect(find.byKey(const Key('editor_image_card_1')), findsOneWidget);

        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('image_caption_input_0')),
          'Ảnh PNG đầu',
        );
        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('image_caption_input_1')),
          'Ảnh JPEG hai',
        );
        // Đưa ảnh 2 lên trước ảnh 1
        await _scrollToAndTap(tester, find.byKey(const Key('image_up_1')));

        await tester.tap(find.byKey(const Key('save_article_button')));
        await _waitUntil(tester, () => repo.getArticles().isNotEmpty);
        await tester.pumpAndSettle();
        if (repo.getArticles().isEmpty) {
          final dialogs = find.byType(AlertDialog).evaluate();
          debugPrint('TEST2 DIALOG COUNT: ${dialogs.length}');
          for (final t in find.byType(Text).evaluate()) {
            final w = t.widget as Text;
            if (w.data != null) debugPrint('TEXT: ${w.data}');
          }
        }

        expect(repo.getArticles().length, 1);
        final saved = repo.getArticles().first;
        expect(saved.images.length, 2);
        expect(saved.images[0].caption, 'Ảnh JPEG hai');
        expect(saved.images[0].mimeType, 'image/jpeg');
        expect(saved.images[0].width, 3);
        expect(saved.images[0].height, 2);
        expect(saved.images[0].relativePath.contains('..'), isFalse);
        expect(
          saved.images[0].relativePath.startsWith('article_assets/'),
          isTrue,
        );
        expect(saved.images[1].caption, 'Ảnh PNG đầu');
        expect(saved.images[1].mimeType, 'image/png');
        expect(saved.images[1].width, 1);
        expect(saved.images[1].height, 1);

        // Committed files exist in article_assets/
        for (final img in saved.images) {
          final committedFile = await tester.runAsync(
            () => assetStore.resolveRelativePath(img.relativePath),
          );
          expect(committedFile!.existsSync(), isTrue);
        }

        // Reopen DB to verify persistence
        await _closeRepo(tester, repo);
        final repo2 = SqliteNotebookRepository(
          dbPath: dbPath,
          assetStore: assetStore,
        );
        final controller2 = NotebookController(repository: repo2);
        await tester.runAsync(() => controller2.initialize());
        final reloaded = repo2.getArticleById(saved.id);
        expect(reloaded!.images.map((e) => e.caption).toList(), [
          'Ảnh JPEG hai',
          'Ảnh PNG đầu',
        ]);

        // Open editor on saved article, add 1 image, remove image 0, then CANCEL (Bỏ thay đổi)
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(ctx).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ArticleEditorScreen(
                            controller: controller2,
                            existingArticle: reloaded,
                            imagePickerOverride: () async => [
                              (
                                name: 'temp_cancel.png',
                                path: null,
                                bytes: _validPng1x1(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: const Text('HOME_SENTINEL'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('HOME_SENTINEL'));
        await tester.pumpAndSettle();
        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_2')),
        );
        await _scrollToAndTap(tester, find.byKey(const Key('delete_image_0')));

        await tester.tap(find.byKey(const Key('editor_back_button')));
        await _waitForFinder(tester, find.text('Bỏ thay đổi'));
        await tester.tap(find.text('Bỏ thay đổi'));
        final stagingDir =
            Directory(p.join(tempDir.path, 'article_assets_staging'));
        await _waitUntil(
          tester,
          () =>
              find.text('HOME_SENTINEL').evaluate().isNotEmpty &&
              (!stagingDir.existsSync() ||
                  stagingDir
                      .listSync()
                      .where((e) => e.path.endsWith('.png'))
                      .isEmpty),
        );

        // Original 2 committed files still exist & canceled staging file is removed
        for (final img in reloaded.images) {
          final f = await tester.runAsync(
            () => assetStore.findExistingFile(
              assetId: img.assetId,
              relativePath: img.relativePath,
            ),
          );
          expect(f, isNotNull);
        }
        if (stagingDir.existsSync()) {
          final remainingNames = stagingDir
              .listSync()
              .map((e) => p.basename(e.path))
              .toList();
          // Canceled batch only had PNG; none of any newly staged PNGs remain
          expect(remainingNames.where((n) => n.endsWith('.png')), isEmpty);
        }
        await _closeRepo(tester, repo2);
      },
    );

    testWidgets(
      'Lỗi promote / lỗi SQLite không mất bản nháp; nhân bản dùng ref-count an toàn; ảnh thiếu file vẫn đọc được bài',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_safe_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        var failPromote = false;
        var failSqlCommit = false;
        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
          debugAssetHook: (stage, _) async {
            if (failPromote && stage == 'before_promote_asset') {
              throw const FileSystemException('Simulated copy error');
            }
          },
        );
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'notebook.db'),
          assetStore: assetStore,
          debugTransactionHook: (_, stage) async {
            if (failSqlCommit && stage == 'before_commit') {
              throw Exception('Simulated SQLite commit failure');
            }
          },
        );
        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        // 1. Test promote failure & SQLite failure preserve draft + staged file to retry
        await tester.pumpWidget(
          MaterialApp(
            home: ArticleEditorScreen(
              controller: controller,
              imagePickerOverride: () async => [
                (name: 'retry.png', path: null, bytes: _validPng1x1()),
              ],
            ),
          ),
        );
        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('article_title_input')),
          'Bài thử lỗi lưu ảnh',
        );
        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_0')),
        );

        failPromote = true;
        await tester.tap(find.byKey(const Key('save_article_button')));
        await _waitForFinder(tester, find.text('Chưa thể lưu bài viết'));
        expect(find.text('Chưa thể lưu bài viết'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        expect(repo.getArticles(), isEmpty);

        failPromote = false;
        failSqlCommit = true;
        await tester.tap(find.byKey(const Key('save_article_button')));
        for (
          var i = 0;
          i < 15 && find.text('Chưa thể lưu bài viết').evaluate().isEmpty;
          i++
        ) {
          await _flushRealAsync(tester);
        }
        expect(find.text('Chưa thể lưu bài viết'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        expect(repo.getArticles(), isEmpty);

        // Clear hook -> retry succeeds cleanly
        failSqlCommit = false;
        await tester.tap(find.byKey(const Key('save_article_button')));
        await _waitUntil(tester, () => repo.getArticles().isNotEmpty);
        await tester.pumpAndSettle();
        expect(repo.getArticles().length, 1);

        final original = repo.getArticles().first;
        final committedPath = original.images.first.relativePath;
        final committedFile = await tester.runAsync(
          () => assetStore.resolveRelativePath(committedPath),
        );
        expect(committedFile!.existsSync(), isTrue);

        // 2. Duplicate -> delete duplicate -> original file MUST still exist
        final dupOutcome = await tester.runAsync(
          () => controller.duplicateArticle(original.id),
        );
        expect(dupOutcome!.isSuccess, isTrue);
        final dup = dupOutcome.article!;
        expect(dup.images.first.assetId, original.images.first.assetId);

        await tester.runAsync(() => controller.deleteArticle(dup.id));
        expect(committedFile.existsSync(), isTrue);

        // 3. Delete original -> refCount reaches 0 -> committed file deleted
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        imageCache.clear();
        imageCache.clearLiveImages();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.runAsync(() => controller.deleteArticle(original.id));
        expect(committedFile.existsSync(), isFalse);

        // 4. Verify missing image file UI gracefully renders error card while article stays readable
        final missingStaged = await tester.runAsync(
          () => assetStore.stageImageBytes(
            assetId: 'missing_asset_999',
            bytes: _validPng1x1(),
            originalName: 'missing.png',
          ),
        );
        final missingArt = _makeArticle(
          title: 'Bài ảnh bị thiếu tệp',
          images: [
            ArticleImageAttachment(
              id: 'missing_img_row',
              assetId: missingStaged!.assetId,
              relativePath: missingStaged.relativePath,
              originalName: 'missing.png',
              mimeType: 'image/png',
              sizeBytes: missingStaged.sizeBytes,
              width: 1,
              height: 1,
              sortOrder: 0,
            ),
          ],
        );
        final missingOutcome = await tester.runAsync(
          () => controller.saveArticle(missingArt),
        );
        expect(missingOutcome!.isSuccess, isTrue);
        final missingCommitted = await tester.runAsync(
          () => assetStore.resolveRelativePath(missingStaged.relativePath),
        );
        missingCommitted!.deleteSync();

        await tester.pumpWidget(
          MaterialApp(
            home: ArticleDetailScreen(
              controller: controller,
              articleId: missingOutcome.article!.id,
            ),
          ),
        );
        await _waitForFinder(tester, find.byKey(const Key('missing_image_0')));
        await tester.pump();
        expect(find.text('Bài ảnh bị thiếu tệp'), findsOneWidget);
        expect(find.byKey(const Key('missing_image_0')), findsOneWidget);

        await _closeRepo(tester, repo);
      },
    );

    testWidgets(
      'Từ chối ảnh quá dung lượng (>15MB), hỏng, quá 8192px & dọn tệp mồ côi an toàn',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_val_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
        );
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'notebook.db'),
          assetStore: assetStore,
        );
        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        // Reject invalid files in editor without harming draft
        await tester.pumpWidget(
          MaterialApp(
            home: ArticleEditorScreen(
              controller: controller,
              imagePickerOverride: () async => [
                (
                  name: 'too_big.png',
                  path: null,
                  bytes: Uint8List(15 * 1024 * 1024 + 1),
                ),
                (
                  name: 'corrupt.jpg',
                  path: null,
                  bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
                ),
                (
                  name: 'too_wide.png',
                  path: null,
                  bytes: _oversizedDimensionPng(),
                ),
              ],
            ),
          ),
        );
        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('article_title_input')),
          'Giữ nháp khi ảnh lỗi',
        );
        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );

        expect(find.text('Không thể thêm một số ảnh'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('editor_image_card_0')), findsNothing);
        await _scrollTo(
          tester,
          find.byKey(const Key('article_title_input')),
          delta: -250.0,
        );
        expect(find.text('Giữ nháp khi ảnh lỗi'), findsOneWidget);

        // Orphan cleanup preserves referenced & activeDraftStagingIds, deletes orphans
        await tester.runAsync(() async {
          final committed = Directory(p.join(tempDir.path, 'article_assets'))
            ..createSync(recursive: true);
          final staging = Directory(
            p.join(tempDir.path, 'article_assets_staging'),
          )..createSync(recursive: true);

          File(p.join(committed.path, 'keep_ref.png'))
              .writeAsBytesSync(_validPng1x1());
          File(p.join(committed.path, 'orphan_ref.png'))
              .writeAsBytesSync(_validPng1x1());
          File(p.join(staging.path, 'active_draft.png'))
              .writeAsBytesSync(_validPng1x1());
          File(p.join(staging.path, 'old_orphan.png'))
              .writeAsBytesSync(_validPng1x1());

          final deleted = await assetStore.cleanupOrphanedAssets(
            referencedAssetIds: {'keep_ref'},
            activeDraftStagingIds: {'active_draft'},
            stagingMaxAge: Duration.zero,
          );
          expect(deleted, 2);
          expect(
            File(p.join(committed.path, 'keep_ref.png')).existsSync(),
            isTrue,
          );
          expect(
            File(p.join(committed.path, 'orphan_ref.png')).existsSync(),
            isFalse,
          );
          expect(
            File(p.join(staging.path, 'active_draft.png')).existsSync(),
            isTrue,
          );
          expect(
            File(p.join(staging.path, 'old_orphan.png')).existsSync(),
            isFalse,
          );
        });

        await _closeRepo(tester, repo);
      },
    );
  });

  group('Phase 4C — C. Thumbnail thẻ bài viết', () {
    testWidgets(
      'Ưu tiên sơ đồ đầu (chỉ đọc) -> fallback ảnh đầu -> fallback placeholder theo loại bài',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_thumb_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
        );
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'notebook.db'),
          assetStore: assetStore,
        );
        await tester.runAsync(() => repo.initialize());

        // Stage and promote an image for the image-fallback article
        final staged = await tester.runAsync(
          () => assetStore.stageImageBytes(
            assetId: 'thumb_asset_1',
            bytes: _validPng1x1(),
            originalName: 'thumb.png',
          ),
        );
        final artWithScene = _makeArticle(
          id: 'art_scene',
          title: 'Bài có sơ đồ',
          diagrams: [
            ArticleDiagram(
              id: 'd1',
              articleId: 'art_scene',
              sortOrder: 0,
              caption: 'Sơ đồ 1',
              scene: DiagramScene.defaultInitial(id: 'd1'),
            ),
          ],
          images: [
            ArticleImageAttachment(
              id: 'img_1',
              articleId: 'art_scene',
              assetId: staged!.assetId,
              relativePath: staged.relativePath,
              originalName: 'thumb.png',
              mimeType: 'image/png',
              sizeBytes: staged.sizeBytes,
              width: 1,
              height: 1,
              sortOrder: 0,
            ),
          ],
        );
        final artWithImageOnly = _makeArticle(
          id: 'art_image',
          title: 'Bài chỉ có ảnh',
          images: [
            ArticleImageAttachment(
              id: 'img_2',
              articleId: 'art_image',
              assetId: staged.assetId,
              relativePath: staged.relativePath,
              originalName: 'thumb.png',
              mimeType: 'image/png',
              sizeBytes: staged.sizeBytes,
              width: 1,
              height: 1,
              sortOrder: 0,
            ),
          ],
        );
        final artEmpty = _makeArticle(
          id: 'art_empty',
          title: 'Bài không sơ đồ không ảnh',
        );

        await tester.runAsync(() async {
          await repo.saveArticle(artWithScene);
          await repo.saveArticle(artWithImageOnly);
          await repo.saveArticle(artEmpty);
        });

        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        await tester.pumpWidget(LibreBilliardApp(controller: controller));
        await _waitForFinder(
          tester,
          find.byKey(const Key('thumb_image_art_image')),
          maxTries: 60,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('thumb_scene_art_scene')), findsOneWidget);
        expect(find.byKey(const Key('thumb_image_art_image')), findsOneWidget);
        expect(
          find.byKey(const Key('thumb_placeholder_art_empty')),
          findsOneWidget,
        );
        // Verify scene thumbnail uses read-only view (no interactive canvas toolbar/handles)
        expect(
          find.descendant(
            of: find.byKey(const Key('thumb_scene_art_scene')),
            matching: find.byType(BilliardTableReadOnlyView),
          ),
          findsOneWidget,
        );

        await _closeRepo(tester, repo);
      },
    );
  });

  group('Phase 4C — D & E. Xem trước, Liên kết nguồn & Danh sách 200 bài', () {
    testWidgets(
      'Xem trước hiển thị bản nháp chưa lưu, chặn dữ liệu lỗi, không ghi SQLite, quay lại giữ nguyên form & mở URL khi bấm',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_prev_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
        );
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'notebook.db'),
          assetStore: assetStore,
        );
        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        final launchedUris = <Uri>[];
        await tester.pumpWidget(
          MaterialApp(
            home: ArticleEditorScreen(
              controller: controller,
              imagePickerOverride: () async => [
                (name: 'preview.png', path: null, bytes: _validPng1x1()),
              ],
              onLaunchUrl: (uri) async {
                launchedUris.add(uri);
                return true;
              },
            ),
          ),
        );

        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('article_title_input')),
          'Tiêu đề xem trước',
        );
        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('tag_input')),
          'thẻ chưa bấm thêm',
        );
        // Nhập URL sai -> Xem trước phải chặn
        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('article_source_url_input')),
          'ftp://invalid-scheme.example',
        );
        await tester.tap(find.byKey(const Key('preview_article_button')));
        await _waitForFinder(tester, find.text('Liên kết nguồn chưa hợp lệ'));
        await tester.pumpAndSettle();
        expect(find.text('Liên kết nguồn chưa hợp lệ'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        // Sửa URL hợp lệ + thêm ảnh có chú thích -> Xem trước thành công
        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('article_source_url_input')),
          'https://bida.example.com/bai-1',
        );
        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_0')),
        );
        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('image_caption_input_0')),
          'Chú thích ảnh xem trước',
        );

        await tester.tap(find.byKey(const Key('preview_article_button')));
        await _waitForFinder(tester, find.text('Bản nháp (xem trước)'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();

        final previewScope = find.byType(ArticlePreviewScreen);
        expect(
          find.descendant(
            of: previewScope,
            matching: find.text('Bản nháp (xem trước)'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: previewScope,
            matching: find.text('Tiêu đề xem trước'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: previewScope,
            matching: find.text('#thẻ chưa bấm thêm'),
          ),
          findsOneWidget,
        );
        final previewCaption = find.descendant(
          of: previewScope,
          matching: find.text('Chú thích ảnh xem trước'),
        );
        await _scrollTo(tester, previewCaption);
        expect(previewCaption, findsOneWidget);
        // URL không tự động mở khi mở Xem trước
        expect(launchedUris, isEmpty);
        // Chỉ mở khi bấm nút
        await tester.ensureVisible(
          find.byKey(const Key('open_source_url_button')),
        );
        await tester.tap(find.byKey(const Key('open_source_url_button')));
        await tester.pump();
        expect(launchedUris, [Uri.parse('https://bida.example.com/bai-1')]);

        // Chưa ghi vào SQLite hay cấp mã
        expect(repo.getArticles(), isEmpty);

        // Quay lại trình soạn thảo: dữ liệu vẫn nguyên vẹn
        await tester.pageBack();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await _scrollTo(
          tester,
          find.byKey(const Key('article_title_input')),
          delta: -250.0,
        );
        expect(find.text('Tiêu đề xem trước'), findsOneWidget);
        await _scrollTo(tester, find.byKey(const Key('image_caption_input_0')));
        expect(find.text('Chú thích ảnh xem trước'), findsOneWidget);

        await _closeRepo(tester, repo);
      },
    );

    testWidgets('Danh sách 200 bài viết render theo nhu cầu mượt mà', (
      tester,
    ) async {
      final tempDir = Directory.systemTemp.createTempSync('bida_4c_200_');
      addTearDown(() {
        try {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final dbPath = p.join(tempDir.path, 'notebook_200.db');
      final assetStore = ArticleAssetStore(
        directoryProvider: () async => tempDir,
      );
      await tester.runAsync(() async {
        final db = await databaseFactoryFfiNoIsolate.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 2,
            singleInstance: false,
            onCreate: (db, _) async {
              await db.execute(
                'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
              );
              await db.execute('''
                  CREATE TABLE editorial_groups (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    sort_order INTEGER NOT NULL
                  )
                ''');
              await db.execute('''
                  CREATE TABLE articles (
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
                    is_draft INTEGER NOT NULL DEFAULT 0,
                    stroke_params_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    is_favorite INTEGER NOT NULL DEFAULT 0,
                    practice_status TEXT NOT NULL,
                    related_article_ids_json TEXT NOT NULL
                  )
                ''');
              await db.execute('''
                  CREATE TABLE article_diagrams (
                    id TEXT PRIMARY KEY,
                    article_id TEXT NOT NULL,
                    sort_order INTEGER NOT NULL,
                    caption TEXT NOT NULL,
                    scene_json TEXT NOT NULL
                  )
                ''');
              await db.execute('''
                  CREATE TABLE code_counters (
                    kind TEXT PRIMARY KEY,
                    last_number INTEGER NOT NULL
                  )
                ''');
              await db.execute('''
                  CREATE TABLE tags (
                    id TEXT PRIMARY KEY,
                    normalized_key TEXT NOT NULL UNIQUE,
                    name TEXT NOT NULL,
                    aliases_json TEXT NOT NULL DEFAULT '[]',
                    created_at TEXT NOT NULL
                  )
                ''');
              await db.execute('''
                  CREATE TABLE collections (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                  )
                ''');
              await db.execute('''
                  CREATE TABLE collection_items (
                    collection_id TEXT NOT NULL,
                    article_id TEXT NOT NULL,
                    sort_order INTEGER NOT NULL,
                    PRIMARY KEY (collection_id, article_id)
                  )
                ''');
              await db.insert('meta', {
                'key': 'default_groups_seeded',
                'value': '1',
              });
              await db.insert('editorial_groups', {
                'id': 'grp_unclassified_technique',
                'kind': 'technique',
                'name': 'Chưa phân loại',
                'description': '',
                'sort_order': 0,
              });
              final strokeJson = jsonEncode(
                const StrokeParameters.defaults().toJson(),
              );
              await db.transaction((txn) async {
                final batch = txn.batch();
                for (var i = 0; i < 200; i++) {
                  batch.insert('articles', {
                    'id': 'art_200_$i',
                    'code': 'KT-${(i + 1).toString().padLeft(3, '0')}',
                    'kind': 'technique',
                    'title': 'Bài kiểm thử $i',
                    'summary': '',
                    'primary_group_id': 'grp_unclassified_technique',
                    'tags_json': '[]',
                    'difficulty': 'basic',
                    'goal': '',
                    'content': 'Nội dung $i',
                    'steps_json': '[]',
                    'common_mistakes': '',
                    'source': null,
                    'author': null,
                    'source_page': null,
                    'is_draft': 0,
                    'stroke_params_json': strokeJson,
                    'created_at': '2026-11-12T08:00:00.000Z',
                    'updated_at': '2026-11-12T08:00:00.000Z',
                    'is_favorite': 0,
                    'practice_status': 'not_started',
                    'related_article_ids_json': '[]',
                  });
                }
                await batch.commit(noResult: true);
              });
            },
          ),
        );
        await db.close();
      });

      final repo = SqliteNotebookRepository(
        dbPath: dbPath,
        assetStore: assetStore,
      );
      final controller = NotebookController(repository: repo);
      await tester.runAsync(() => controller.initialize());

      await tester.pumpWidget(LibreBilliardApp(controller: controller));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await _flushRealAsync(tester);

      expect(repo.getArticles().length, 200);
      // ListView.builder only materializes visible items, not all 200 widgets at once
      expect(find.byType(ListTile).evaluate().length, lessThan(30));

      await _closeRepo(tester, repo);
    });
  });

  group('Phase 4C — Hồi quy: Nhập ảnh async, Thumbnail live & Dọn ảnh sau lỗi SQLite', () {
    testWidgets(
      'Giả lập staging chậm: chặn Lưu, Lưu nháp, Xem trước, thoát editor & nhập chồng',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_slow_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final stageGate = Completer<void>();
        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
          debugAssetHook: (stage, _) async {
            if (stage == 'before_stage_write' && !stageGate.isCompleted) {
              await stageGate.future;
            }
          },
        );
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'notebook.db'),
          assetStore: assetStore,
        );
        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        var pickerCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ArticleEditorScreen(
              controller: controller,
              imagePickerOverride: () async {
                pickerCalls++;
                return [(name: 'slow.png', path: null, bytes: _validPng1x1())];
              },
            ),
          ),
        );

        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('article_title_input')),
          'Bài thử staging chậm',
        );

        // Bắt đầu staging chậm
        await _scrollTo(tester, find.byKey(const Key('add_image_button')));
        await tester.tap(find.byKey(const Key('add_image_button')));
        await tester.pump();

        expect(
          find.byKey(const Key('importing_images_banner')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('save_article_button')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('save_draft_button')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const Key('preview_article_button')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('editor_back_button')))
              .onPressed,
          isNull,
        );

        // Chặn nhập chồng & thoát bằng back hệ thống trong lúc staging
        await tester.tap(find.byKey(const Key('add_image_button')));
        await tester.pump();
        expect(pickerCalls, 1);

        final navState = tester.state<NavigatorState>(find.byType(Navigator));
        await navState.maybePop();
        await tester.pump();
        expect(find.byType(ArticleEditorScreen), findsOneWidget);
        expect(find.text('HOME_SENTINEL'), findsNothing);

        // Hoàn tất staging -> giải phóng trạng thái bận và lưu thành công đủ ảnh
        stageGate.complete();
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_0')),
        );
        await tester.pump();
        expect(find.byKey(const Key('importing_images_banner')), findsNothing);

        await tester.tap(find.byKey(const Key('save_article_button')));
        await _waitUntil(tester, () => repo.getArticles().isNotEmpty);
        expect(repo.getArticles().first.images.length, 1);

        await _closeRepo(tester, repo);
      },
    );

    testWidgets(
      'Giả lập lỗi ImagePicker: hiển thị thông báo và form trở lại dùng được',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_pickerr_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
        );
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'notebook.db'),
          assetStore: assetStore,
        );
        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        var attempt = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ArticleEditorScreen(
              controller: controller,
              imagePickerOverride: () async {
                attempt++;
                if (attempt == 1) {
                  throw PlatformException(
                    code: 'photo_access_denied',
                    message: 'Permission denied',
                  );
                }
                return [
                  (name: 'recovered.png', path: null, bytes: _validPng1x1()),
                ];
              },
            ),
          ),
        );

        await _scrollToAndEnterText(
          tester,
          find.byKey(const Key('article_title_input')),
          'Bài hồi phục sau lỗi picker',
        );

        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );
        await _waitForFinder(tester, find.text('Không thể chọn ảnh'));
        expect(find.text('Không thể chọn ảnh'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        // Trạng thái bận đã được giải phóng, chọn lại thành công
        expect(find.byKey(const Key('importing_images_banner')), findsNothing);
        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_0')),
        );

        await tester.tap(find.byKey(const Key('save_article_button')));
        await _waitUntil(tester, () => repo.getArticles().isNotEmpty);
        expect(repo.getArticles().first.images.length, 1);

        await _closeRepo(tester, repo);
      },
    );

    testWidgets(
      'Bài có scene + ảnh -> xóa scene cuối -> thumbnail chuyển sang ảnh ngay trên cùng widget',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'bida_4c_live_thumb_',
        );
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
        );
        final staged = await tester.runAsync(
          () => assetStore.stageImageBytes(
            assetId: 'live_thumb_asset',
            bytes: _validPng1x1(),
            originalName: 'live.png',
          ),
        );
        await tester.runAsync(
          () => assetStore.promoteStagedAsset(
            assetId: staged!.assetId,
            relativePath: staged.relativePath,
          ),
        );

        var currentArticle = _makeArticle(
          id: 'art_live_thumb',
          title: 'Bài đổi thumbnail trực tiếp',
          diagrams: [
            ArticleDiagram(
              id: 'd_live',
              articleId: 'art_live_thumb',
              sortOrder: 0,
              caption: 'Sơ đồ 1',
              scene: DiagramScene.defaultInitial(id: 'd_live'),
            ),
          ],
          images: [
            ArticleImageAttachment(
              id: 'img_live',
              articleId: 'art_live_thumb',
              assetId: staged!.assetId,
              relativePath: staged.relativePath,
              originalName: 'live.png',
              mimeType: 'image/png',
              sizeBytes: staged.sizeBytes,
              width: 1,
              height: 1,
              sortOrder: 0,
            ),
          ],
        );

        late void Function(VoidCallback) triggerRebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  triggerRebuild = setState;
                  return ArticleThumbnail(
                    key: const ValueKey('persistent_thumb_widget'),
                    article: currentArticle,
                    assetStore: assetStore,
                  );
                },
              ),
            ),
          ),
        );
        await _flushRealAsync(tester);

        expect(
          find.byKey(const Key('thumb_scene_art_live_thumb')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('thumb_image_art_live_thumb')),
          findsNothing,
        );

        // Xóa scene cuối cùng (giữ nguyên assetId & relativePath ảnh) trên CÙNG widget
        triggerRebuild(() {
          currentArticle = currentArticle.copyWith(diagrams: const []);
        });
        await tester.pump();
        await _waitForFinder(
          tester,
          find.byKey(const Key('thumb_image_art_live_thumb')),
        );

        expect(
          find.byKey(const Key('thumb_scene_art_live_thumb')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('thumb_image_art_live_thumb')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Thêm ảnh -> promote thành công -> SQLite lỗi -> Bỏ thay đổi: xóa tệp mới mồ côi, giữ nguyên ảnh bài cũ',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_discard_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        var failSqlCommit = false;
        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
        );
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'notebook.db'),
          assetStore: assetStore,
          debugTransactionHook: (_, stage) async {
            if (failSqlCommit && stage == 'before_commit') {
              throw Exception('Simulated SQLite error after promote');
            }
          },
        );
        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        // Lưu bài gốc với 1 ảnh ban đầu
        final origStaged = await tester.runAsync(
          () => assetStore.stageImageBytes(
            assetId: 'orig_asset_1',
            bytes: _validPng1x1(),
            originalName: 'orig.png',
          ),
        );
        final savedOrig = await tester.runAsync(
          () => controller.saveArticle(
            _makeArticle(
              title: 'Bài gốc có ảnh',
              images: [
                ArticleImageAttachment(
                  id: 'orig_img_row',
                  assetId: origStaged!.assetId,
                  relativePath: origStaged.relativePath,
                  originalName: 'orig.png',
                  mimeType: 'image/png',
                  sizeBytes: origStaged.sizeBytes,
                  width: 1,
                  height: 1,
                  sortOrder: 0,
                ),
              ],
            ),
          ),
        );
        expect(savedOrig!.isSuccess, isTrue);
        final origFile = await tester.runAsync(
          () => assetStore.resolveRelativePath(origStaged!.relativePath),
        );
        expect(origFile!.existsSync(), isTrue);

        // Mở editor sửa bài, thêm ảnh thứ 2, promote thành công nhưng SQLite lỗi
        await tester.pumpWidget(
          MaterialApp(
            home: ArticleEditorScreen(
              controller: controller,
              existingArticle: savedOrig.article,
              imagePickerOverride: () async => [
                (name: 'new_fail.png', path: null, bytes: _validPng1x1()),
              ],
            ),
          ),
        );

        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_1')),
        );

        failSqlCommit = true;
        await tester.tap(find.byKey(const Key('save_article_button')));
        await _waitForFinder(tester, find.text('Chưa thể lưu bài viết'));
        expect(find.text('Chưa thể lưu bài viết'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        // Lúc này ảnh mới đã được promote sang article_assets/ (có 2 tệp trong article_assets/)
        final committedDir = Directory(p.join(tempDir.path, 'article_assets'));
        expect(committedDir.listSync().length, 2);

        // Hủy sửa (Bỏ thay đổi) -> phải dọn tệp mới đã promote, giữ nguyên ảnh bài gốc
        await tester.tap(find.byKey(const Key('editor_back_button')));
        await _waitForFinder(tester, find.text('Bỏ thay đổi'));
        await tester.tap(find.text('Bỏ thay đổi'));
        await _waitUntil(tester, () => committedDir.listSync().length == 1);

        expect(origFile.existsSync(), isTrue);
        expect(committedDir.listSync().length, 1);
        final stagingDir = Directory(
          p.join(tempDir.path, 'article_assets_staging'),
        );
        if (stagingDir.existsSync()) {
          expect(stagingDir.listSync(), isEmpty);
        }
        expect(repo.getArticleById(savedOrig.article!.id)!.images.length, 1);

        await _closeRepo(tester, repo);
      },
    );

    testWidgets(
      'Thêm ảnh -> promote thành công -> SQLite lỗi -> thử lưu lại: ảnh được lưu đầy đủ',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('bida_4c_retry_');
        addTearDown(() {
          try {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });

        var failSqlCommit = false;
        final assetStore = ArticleAssetStore(
          directoryProvider: () async => tempDir,
        );
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'notebook.db'),
          assetStore: assetStore,
          debugTransactionHook: (_, stage) async {
            if (failSqlCommit && stage == 'before_commit') {
              throw Exception('Simulated SQLite error before retry');
            }
          },
        );
        final controller = NotebookController(repository: repo);
        await tester.runAsync(() => controller.initialize());

        final origStaged = await tester.runAsync(
          () => assetStore.stageImageBytes(
            assetId: 'orig_asset_retry',
            bytes: _validPng1x1(),
            originalName: 'orig.png',
          ),
        );
        final savedOrig = await tester.runAsync(
          () => controller.saveArticle(
            _makeArticle(
              title: 'Bài thử lưu lại sau lỗi SQLite',
              images: [
                ArticleImageAttachment(
                  id: 'orig_img_retry',
                  assetId: origStaged!.assetId,
                  relativePath: origStaged.relativePath,
                  originalName: 'orig.png',
                  mimeType: 'image/png',
                  sizeBytes: origStaged.sizeBytes,
                  width: 1,
                  height: 1,
                  sortOrder: 0,
                ),
              ],
            ),
          ),
        );
        expect(savedOrig!.isSuccess, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: ArticleEditorScreen(
              controller: controller,
              existingArticle: savedOrig.article,
              imagePickerOverride: () async => [
                (name: 'retry_ok.png', path: null, bytes: _validPng1x1()),
              ],
            ),
          ),
        );

        await _scrollToAndTap(
          tester,
          find.byKey(const Key('add_image_button')),
        );
        await _waitForFinder(
          tester,
          find.byKey(const Key('editor_image_card_1')),
        );

        failSqlCommit = true;
        await tester.tap(find.byKey(const Key('save_article_button')));
        await _waitForFinder(tester, find.text('Chưa thể lưu bài viết'));
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        // Thử lưu lại khi hết lỗi -> cả 2 ảnh được lưu đầy đủ vào SQLite
        failSqlCommit = false;
        await tester.tap(find.byKey(const Key('save_article_button')));
        await _waitUntil(
          tester,
          () => repo.getArticleById(savedOrig.article!.id)!.images.length == 2,
        );

        final updated = repo.getArticleById(savedOrig.article!.id)!;
        expect(updated.images.length, 2);
        for (final img in updated.images) {
          final f = await tester.runAsync(
            () => assetStore.resolveRelativePath(img.relativePath),
          );
          expect(f!.existsSync(), isTrue);
        }

        await _closeRepo(tester, repo);
      },
    );
  });
}
