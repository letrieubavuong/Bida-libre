import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/main.dart';
import 'package:libre_billiard_notebook/models/models.dart';
import 'package:libre_billiard_notebook/repositories/sqlite_notebook_repository.dart';
import 'package:libre_billiard_notebook/state/notebook_controller.dart';
import 'package:libre_billiard_notebook/ui/screens/article_detail_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/article_editor_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/collections_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/group_management_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Article _makeArticle({
  String id = '',
  String code = '',
  required ArticleKind kind,
  required String title,
  String summary = '',
  required String primaryGroupId,
  List<String> tags = const [],
  Difficulty difficulty = Difficulty.basic,
  bool isFavorite = false,
  DateTime? createdAt,
  DateTime? updatedAt,
  List<ArticleDiagram> diagrams = const [],
}) {
  final ts = createdAt ?? DateTime.utc(2026, 11, 12, 8, 0);
  return Article(
    id: id,
    code: code,
    kind: kind,
    title: title,
    summary: summary,
    primaryGroupId: primaryGroupId,
    tags: tags,
    difficulty: difficulty,
    goal: 'Mục tiêu $title',
    content: 'Nội dung $title',
    isFavorite: isFavorite,
    diagrams: diagrams,
    createdAt: ts,
    updatedAt: updatedAt ?? ts,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Phase 4B — A. Migration v1 -> v2 & Bảo toàn dữ liệu Phase 4A', () {
    test('Nâng cấp DB schema v1 có sẵn bài và nhiều sơ đồ lên v2 không mất dữ liệu',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('lb_p4b_mig_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });
      final dbPath = p.join(tempDir.path, 'legacy_v1.db');

      // Tạo DB đúng schema v1 của Phase 4A
      final v1Db = await databaseFactoryFfiNoIsolate.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE code_counters (kind TEXT PRIMARY KEY, last_number INTEGER NOT NULL)',
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
              CREATE TABLE article_diagrams (
                id TEXT PRIMARY KEY,
                article_id TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                caption TEXT NOT NULL,
                scene_json TEXT NOT NULL,
                FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
              )
            ''');
          },
        ),
      );

      await v1Db.insert('meta', {'key': 'default_groups_seeded', 'value': '1'});
      await v1Db.insert('code_counters', {'kind': 'technique', 'last_number': 1});
      await v1Db.insert('editorial_groups', {
        'id': 'tech_draw',
        'kind': 'technique',
        'name': 'Trô / kéo (tùy chỉnh)',
        'description': '',
        'sort_order': 1,
      });
      await v1Db.insert('articles', {
        'id': 'legacy-uuid-1',
        'code': 'KT-001',
        'kind': 'technique',
        'title': 'Bài Phase 4A cần bảo toàn',
        'summary': 'Mô tả cũ',
        'primary_group_id': 'tech_draw',
        'tags_json': '["Cu lê", "Trô kéo"]',
        'difficulty': 'intermediate',
        'goal': 'Giữ nguyên mục tiêu',
        'content': 'Giữ nguyên nội dung',
        'steps_json': '["Bước 1"]',
        'common_mistakes': 'Lưu ý cũ',
        'source': 'Sách cũ',
        'author': null,
        'source_page': null,
        'is_draft': 0,
        'stroke_params_json':
            '{"cueBallId":"ball_white","thicknessMode":"eighths","eighthCount":4,"isFullFace":false,"hitSide":"center","tipXMm":0.0,"tipZMm":0.0,"tipDiameterMm":12.0,"tipNote":"","forceText":"","strokeStyleText":""}',
        'created_at': '2026-11-11T09:00:00.000Z',
        'updated_at': '2026-11-11T10:00:00.000Z',
        'is_favorite': 1,
        'practice_status': 'not_started',
        'related_article_ids_json': '[]',
      });
      final sceneJson =
          '{"id":"diag-v1-1","version":1,"width":188.0,"height":376.0,"balls":[{"id":"ball_white","color":"white","label":"1","center":{"x":94.0,"y":94.0},"radius":4.0,"locked":false}]}';
      await v1Db.insert('article_diagrams', {
        'id': 'diag-v1-1',
        'article_id': 'legacy-uuid-1',
        'sort_order': 0,
        'caption': 'Sơ đồ 1 từ v1',
        'scene_json': sceneJson,
      });
      await v1Db.insert('article_diagrams', {
        'id': 'diag-v1-2',
        'article_id': 'legacy-uuid-1',
        'sort_order': 1,
        'caption': 'Sơ đồ 2 từ v1',
        'scene_json': sceneJson.replaceFirst('diag-v1-1', 'diag-v1-2'),
      });
      await v1Db.close();

      // Mở bằng repository v2 (chạy migration)
      final repo = SqliteNotebookRepository(dbPath: dbPath);
      await repo.initialize();

      final migrated = repo.getArticleById('legacy-uuid-1');
      expect(migrated, isNotNull);
      expect(migrated!.code, 'KT-001');
      expect(migrated.title, 'Bài Phase 4A cần bảo toàn');
      expect(migrated.diagrams.length, 2);
      expect(migrated.diagrams[0].caption, 'Sơ đồ 1 từ v1');
      expect(migrated.diagrams[1].caption, 'Sơ đồ 2 từ v1');
      expect(migrated.createdAt, DateTime.utc(2026, 11, 11, 9, 0));
      expect(migrated.isFavorite, isTrue);

      // Tên nhóm tùy chỉnh không bị ghi đè, đồng thời nhóm Chưa phân loại được bổ sung
      expect(
        repo.getGroupById('tech_draw')!.name,
        'Trô / kéo (tùy chỉnh)',
      );
      expect(
        repo.getGroupById(DefaultEditorialGroups.techniqueUnclassifiedId),
        isNotNull,
      );
      // Thẻ cũ đã được đồng bộ sang bảng tags
      expect(repo.getTags().map((t) => t.name), containsAll(['Cu lê', 'Trô kéo']));
      await repo.close();

      // Đóng và mở lại lần nữa vẫn đầy đủ
      final repo2 = SqliteNotebookRepository(dbPath: dbPath);
      await repo2.initialize();
      expect(repo2.getArticleById('legacy-uuid-1')!.diagrams.length, 2);
      expect(repo2.getTags().length, 2);
      await repo2.close();
    });
  });

  group('Phase 4B — B. Quản lý nhóm', () {
    test('Tạo/đổi tên/xóa nhóm chuyển bài đúng đích, chặn sai loại, rollback khi lỗi',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('lb_p4b_grp_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });

      bool failDeleteGroup = false;
      final repo = SqliteNotebookRepository(
        dbPath: p.join(tempDir.path, 'groups.db'),
        debugTransactionHook: (txn, stage) async {
          if (failDeleteGroup && stage == 'before_delete_group') {
            throw const FileSystemException('Simulated group delete failure');
          }
        },
      );
      await repo.initialize();

      // Tạo nhóm mới & đổi tên -> giữ nguyên UUID/mã bài viết
      final customGrp = await repo.saveGroup(
        kind: ArticleKind.technique,
        name: 'Nhóm tạm',
      );
      final renamed = await repo.saveGroup(
        id: customGrp.id,
        kind: ArticleKind.technique,
        name: 'Nhóm tùy biến',
      );
      expect(renamed.id, customGrp.id);
      expect(renamed.name, 'Nhóm tùy biến');

      final art = await repo.saveArticle(
        _makeArticle(
          kind: ArticleKind.technique,
          title: 'Bài trong nhóm tùy biến',
          primaryGroupId: customGrp.id,
        ),
      );
      expect(art.code, 'KT-001');

      // Không cho xóa nhóm Chưa phân loại
      await expectLater(
        () => repo.deleteGroup(
          groupId: DefaultEditorialGroups.techniqueUnclassifiedId,
          targetGroupId: 'tech_draw',
        ),
        throwsA(isA<FormatException>()),
      );

      // Không nhận nhóm đích thuộc sai loại
      await expectLater(
        () => repo.deleteGroup(
          groupId: customGrp.id,
          targetGroupId: DefaultEditorialGroups.systemUnclassifiedId,
        ),
        throwsA(isA<FormatException>()),
      );

      // Giả lập lỗi giữa transaction -> rollback sạch sẽ, bài vẫn ở nhóm cũ
      failDeleteGroup = true;
      await expectLater(
        () => repo.deleteGroup(
          groupId: customGrp.id,
          targetGroupId: 'tech_draw',
        ),
        throwsA(isA<FileSystemException>()),
      );
      failDeleteGroup = false;
      expect(repo.getGroupById(customGrp.id), isNotNull);
      expect(repo.getArticleById(art.id)!.primaryGroupId, customGrp.id);

      // Xóa nhóm thành công -> chuyển bài sang tech_draw, UUID & mã bài giữ nguyên
      await repo.deleteGroup(
        groupId: customGrp.id,
        targetGroupId: 'tech_draw',
      );
      expect(repo.getGroupById(customGrp.id), isNull);
      final moved = repo.getArticleById(art.id)!;
      expect(moved.id, art.id);
      expect(moved.code, 'KT-001');
      expect(moved.primaryGroupId, 'tech_draw');

      // Bài viết không nhận nhóm thuộc sai loại
      await expectLater(
        () => repo.saveArticle(
          moved.copyWith(primaryGroupId: DefaultEditorialGroups.positionUnclassifiedId),
        ),
        throwsA(isA<FormatException>()),
      );

      await repo.close();
    });
  });

  group('Phase 4B — C. Thẻ và Bộ sưu tập', () {
    test('Thẻ chống trùng hoa/thường & khoảng trắng; 1 bài ở 3 bộ sưu tập; giữ thứ tự thủ công',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('lb_p4b_col_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });
      final dbPath = p.join(tempDir.path, 'col.db');
      final repo = SqliteNotebookRepository(dbPath: dbPath);
      await repo.initialize();

      final a1 = await repo.saveArticle(
        _makeArticle(
          kind: ArticleKind.technique,
          title: 'Cu-lê căn bản',
          primaryGroupId: 'tech_follow',
          tags: const ['  Cu lê  ', 'cu lê', 'CU LÊ', 'trô   kéo'],
        ),
      );
      final a2 = await repo.saveArticle(
        _makeArticle(
          kind: ArticleKind.position,
          title: 'Gom góc một chạm',
          primaryGroupId: 'corner',
        ),
      );
      expect(a1.tags, ['Cu lê', 'trô kéo']);
      expect(repo.suggestTags('cu'), ['Cu lê']);

      final col1 = await repo.createCollection('Sách A — Chương 2');
      final col2 = await repo.createCollection('20 thế cơ bản');
      final col3 = await repo.createCollection('Đang tập tuần này');

      // Một bài vào 3 bộ sưu tập; thêm trùng trong cùng bộ sưu tập không tạo dòng thứ 2
      await repo.addArticleToCollection(collectionId: col1.id, articleId: a1.id);
      await repo.addArticleToCollection(collectionId: col1.id, articleId: a1.id);
      await repo.addArticleToCollection(collectionId: col1.id, articleId: a2.id);
      await repo.addArticleToCollection(collectionId: col2.id, articleId: a1.id);
      await repo.addArticleToCollection(collectionId: col3.id, articleId: a1.id);

      expect(repo.getCollectionById(col1.id)!.orderedArticleIds, [a1.id, a2.id]);
      expect(repo.getCollectionsForArticle(a1.id).length, 3);

      // Đổi thứ tự thủ công trong col1: [a2.id, a1.id]
      await repo.reorderCollectionArticles(
        collectionId: col1.id,
        orderedArticleIds: [a2.id, a1.id],
      );

      // Sửa bài a1 một lần -> không bị mất quan hệ bộ sưu tập (không dùng INSERT OR REPLACE!)
      await repo.saveArticle(a1.copyWith(title: 'Cu-lê căn bản (cập nhật)'));
      expect(repo.getCollectionsForArticle(a1.id).length, 3);
      expect(
        repo.getArticleById(a1.id)!.title,
        'Cu-lê căn bản (cập nhật)',
      );

      // Nhân bản a1 -> bản sao KHÔNG tự chui vào col1/col2/col3
      final dup = await repo.duplicateArticle(a1.id);
      expect(repo.getCollectionsForArticle(dup.id), isEmpty);

      // Xóa col2 -> không xóa bài a1
      await repo.deleteCollection(col2.id);
      expect(repo.getCollectionById(col2.id), isNull);
      expect(repo.getArticleById(a1.id), isNotNull);
      expect(repo.getCollectionsForArticle(a1.id).length, 2);

      // Đóng và mở lại SQLite -> thứ tự thủ công col1 vẫn giữ [a2.id, a1.id]
      await repo.close();
      final repo2 = SqliteNotebookRepository(dbPath: dbPath);
      await repo2.initialize();
      expect(
        repo2.getCollectionById(col1.id)!.orderedArticleIds,
        [a2.id, a1.id],
      );
      expect(repo2.getArticleById(a1.id)!.tags, ['Cu lê', 'trô kéo']);
      await repo2.close();
    });
  });

  group('Phase 4B — D & F. Tìm kiếm, Lọc OR/AND, Sắp xếp & 500 bài giả lập', () {
    test('Chuẩn hóa tiếng Việt, alias cu-lê, OR trong lọc, AND giữa lọc, sắp xếp mã số',
        () {
      final t1 = DateTime.utc(2026, 11, 12, 8, 0);
      final articles = [
        _makeArticle(
          id: '1',
          code: 'KT-10',
          kind: ArticleKind.technique,
          title: 'Trô kéo bi đỏ',
          summary: 'Kéo giật qua băng ngắn',
          primaryGroupId: 'tech_draw',
          tags: const ['Trô', 'Bi đỏ'],
          difficulty: Difficulty.basic,
          updatedAt: t1,
        ),
        _makeArticle(
          id: '2',
          code: 'KT-2',
          kind: ArticleKind.technique,
          title: 'Cu-lê hồi băng',
          summary: 'Đẩy tới nhẹ',
          primaryGroupId: 'tech_follow',
          tags: const ['Cu lê'],
          difficulty: Difficulty.intermediate,
          updatedAt: t1.add(const Duration(minutes: 5)),
        ),
        _makeArticle(
          id: '3',
          code: 'KT-100',
          kind: ArticleKind.technique,
          title: 'Đánh chết bi giữa bàn',
          summary: 'Amorti chuẩn',
          primaryGroupId: 'tech_amorti',
          tags: const ['Amorti'],
          difficulty: Difficulty.advanced,
          updatedAt: t1.add(const Duration(minutes: 10)),
        ),
      ];

      // "tro" tìm được "Trô" và "do" tìm được "đỏ" (đ -> d)
      expect(
        ArticleQueryEngine.filterAndSort(
          articles: articles,
          criteria: const ArticleFilterCriteria(searchQuery: 'tro'),
        ).map((a) => a.id),
        ['1'],
      );
      expect(
        ArticleQueryEngine.filterAndSort(
          articles: articles,
          criteria: const ArticleFilterCriteria(searchQuery: 'do'),
        ).map((a) => a.id),
        ['1'],
      );

      // "cule", "cu lê", "cu-lê" đều tìm được nhau
      for (final q in ['cule', 'cu lê', 'cu-lê']) {
        expect(
          ArticleQueryEngine.filterAndSort(
            articles: articles,
            criteria: ArticleFilterCriteria(searchQuery: q),
          ).map((a) => a.id),
          ['2'],
        );
      }

      // Tìm theo mã bài
      expect(
        ArticleQueryEngine.filterAndSort(
          articles: articles,
          criteria: const ArticleFilterCriteria(searchQuery: 'KT-100'),
        ).map((a) => a.id),
        ['3'],
      );

      // OR trong cùng bộ lọc (basic OR intermediate) AND nhóm (tech_follow)
      final combined = ArticleQueryEngine.filterAndSort(
        articles: articles,
        criteria: const ArticleFilterCriteria(
          difficulties: {Difficulty.basic, Difficulty.intermediate},
          groupIds: {'tech_follow'},
        ),
      );
      expect(combined.map((a) => a.id), ['2']);

      // Sắp xếp theo mã bài có phần số khác độ dài: KT-2 < KT-10 < KT-100
      final byCode = ArticleQueryEngine.filterAndSort(
        articles: articles,
        criteria: const ArticleFilterCriteria(sortBy: ArticleSortOption.codeAsc),
      );
      expect(byCode.map((a) => a.code), ['KT-2', 'KT-10', 'KT-100']);
    });

    test('Kiểm tra tìm/lọc trên 500 bài giả lập (chỉ dùng trong test fixture)', () {
      final base = DateTime.utc(2026, 11, 12, 1, 0);
      final fixture = List<Article>.generate(500, (i) {
        final num = i + 1;
        return _makeArticle(
          id: 'fixture-$num',
          code: 'HB-$num',
          kind: ArticleKind.position,
          title: num % 25 == 0 ? 'Thế cu-lê gom góc số $num' : 'Hình bi mẫu $num',
          summary: num % 10 == 0 ? 'Trô về băng ngắn' : 'Tình huống thường',
          primaryGroupId: num.isEven ? 'corner' : 'long_rail',
          tags: [num % 50 == 0 ? 'ưu tiên' : 'cơ bản'],
          difficulty: num % 3 == 0 ? Difficulty.advanced : Difficulty.basic,
          updatedAt: base.add(Duration(minutes: num)),
        );
      });

      final res = ArticleQueryEngine.filterAndSort(
        articles: fixture,
        criteria: const ArticleFilterCriteria(
          searchQuery: 'cule',
          groupIds: {'corner'},
          sortBy: ArticleSortOption.codeAsc,
        ),
      );
      // Các số chia hết cho 25 và là số chẵn -> bội của 50 (50, 100, ..., 500 => 10 bài)
      expect(res.length, 10);
      expect(res.first.code, 'HB-50');
      expect(res.last.code, 'HB-500');
    });
  });

  group('Phase 4B — E. Widget: Điều hướng giữ bộ lọc/cuộn, Nhóm, Thẻ & Bộ sưu tập', () {
    testWidgets(
      'Đổi tab giữ bộ lọc riêng; mở bài quay lại giữ từ khóa, bộ lọc & vị trí cuộn; sửa UI nhóm/thẻ/bộ sưu tập',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('lb_p4b_ui_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            try {
              tempDir.deleteSync(recursive: true);
            } catch (_) {}
          }
        });
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'ui_p4b.db'),
        );
        await tester.runAsync(() => repo.initialize());

        // Tạo 20 bài ở tab Kĩ thuật để có danh sách dài kiểm tra giữ vị trí cuộn,
        // và 1 bài ở tab Bộ số.
        await tester.runAsync(() async {
          for (var i = 1; i <= 20; i++) {
            await repo.saveArticle(
              _makeArticle(
                kind: ArticleKind.technique,
                title: 'Bài kỹ thuật số $i',
                primaryGroupId: 'tech_draw',
                tags: const ['Trô kéo'],
                updatedAt: DateTime.utc(2026, 11, 12, 8, i),
              ),
            );
          }
          await repo.saveArticle(
            _makeArticle(
              kind: ArticleKind.system,
              title: 'Bộ số 50 tham khảo',
              primaryGroupId: 'sys_unclassified',
            ),
          );
        });

        final controller = NotebookController(repository: repo);
        await tester.pumpWidget(LibreBilliardApp(controller: controller));
        await tester.pumpAndSettle();

        // Ở tab Kĩ thuật: cuộn xuống và gõ từ khóa 'Bài kỹ thuật'
        await tester.enterText(
          find.byKey(const Key('home_search_input')),
          'Bài kỹ thuật',
        );
        await tester.pumpAndSettle();

        final listFinder = find.byKey(const Key('articles_list_technique'));
        await tester.drag(listFinder, const Offset(0, -400));
        await tester.pumpAndSettle();
        final savedOffset = controller.scrollOffsetFor(ArticleKind.technique);
        expect(savedOffset, greaterThan(50.0));

        // Chuyển sang tab Bộ số -> từ khóa tab Bộ số vẫn rỗng, không bị ảnh hưởng bởi tab Kĩ thuật
        await tester.tap(find.text('Bộ số'));
        await tester.pumpAndSettle();
        expect(controller.searchQuery, isEmpty);
        expect(find.text('Bộ số 50 tham khảo'), findsOneWidget);

        // Chuyển lại tab Kĩ thuật -> giữ nguyên từ khóa & vị trí cuộn
        await tester.tap(find.text('Kĩ thuật'));
        await tester.pumpAndSettle();
        expect(controller.searchQuery, 'Bài kỹ thuật');
        expect(
          tester.widget<TextField>(find.byKey(const Key('home_search_input'))).controller!.text,
          'Bài kỹ thuật',
        );

        // Mở một bài đang hiện rõ giữa màn hình rồi quay lại -> vẫn giữ từ khóa, bộ lọc & vị trí cuộn
        final visibleCard = find.byType(Card).at(2);
        await tester.tap(visibleCard);
        await tester.pumpAndSettle();
        expect(find.byType(ArticleDetailScreen), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(controller.searchQuery, 'Bài kỹ thuật');
        expect(
          controller.scrollOffsetFor(ArticleKind.technique),
          closeTo(savedOffset, 10.0),
        );

        // Mở Quản lý nhóm -> tạo nhóm mới
        await tester.tap(find.byKey(const Key('manage_groups_button')));
        await tester.pumpAndSettle();
        expect(find.byType(GroupManagementScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('add_group_button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('group_name_input')),
          'Nhóm UI mới',
        );
        await tester.tap(find.byKey(const Key('confirm_save_group_button')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Nhóm UI mới'),
          200.0,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Nhóm UI mới'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Mở Bộ sưu tập -> tạo bộ sưu tập mới
        await tester.tap(find.byKey(const Key('collections_button')));
        await tester.pumpAndSettle();
        expect(find.byType(CollectionsScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('add_collection_button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('collection_name_input')),
          'Tuyển tập kiểm thử',
        );
        await tester.tap(find.byKey(const Key('confirm_collection_name_button')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(find.text('Tuyển tập kiểm thử'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Mở Editor -> thử đổi loại bài từ Kĩ thuật sang Hình bi -> nhóm tự điều chỉnh hợp lệ & thêm thẻ
        await tester.tap(find.byKey(const Key('fab_new_article')));
        await tester.pumpAndSettle();
        expect(find.byType(ArticleEditorScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('kind_chip_position')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('tag_input')), '  Gom góc ');
        await tester.tap(find.byKey(const Key('add_tag_button')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('article_tag_chip_0')),
            matching: find.text('Gom góc'),
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.runAsync(() => repo.close());
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );
  });
}

