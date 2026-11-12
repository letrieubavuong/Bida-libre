import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:libre_billiard_notebook/models/models.dart';
import 'package:libre_billiard_notebook/repositories/sqlite_notebook_repository.dart';
import 'package:libre_billiard_notebook/state/notebook_controller.dart';
import 'package:libre_billiard_notebook/state/table_editor_controller.dart';
import 'package:libre_billiard_notebook/ui/screens/article_detail_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/article_editor_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/notebook_home_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/table_stage_screen.dart';
import 'package:libre_billiard_notebook/ui/widgets/article_detail_body.dart';

DiagramScene _buildRichScene(
  String id, {
  double whiteY = 94.0,
  String annotationText = 'N1',
}) {
  final base = DiagramScene.defaultInitial(id: id);
  final movedBalls = [
    base.balls[0].copyWith(center: DiagramPoint(94.0, whiteY)),
    base.balls[1].copyWith(center: const DiagramPoint(130.0, 210.0)),
    base.balls[2].copyWith(center: const DiagramPoint(58.0, 285.0)),
  ];
  final mixedPath = GuidePath(
    id: '${id}_path_1',
    ownerBallId: 'ball_white',
    startAnchorBallId: 'ball_white',
    segments: [
      PathSegment.line(
        start: DiagramPoint(94.0, whiteY),
        end: const DiagramPoint(120.0, 180.0),
      ),
      const PathSegment.cubic(
        start: DiagramPoint(120.0, 180.0),
        control1: DiagramPoint(135.0, 215.0),
        control2: DiagramPoint(95.0, 245.0),
        end: DiagramPoint(62.0, 270.0),
      ),
    ],
  );
  final railAnnotation = DiagramAnnotation(
    id: '${id}_ann_1',
    type: AnnotationType.label,
    position: const DiagramPoint(47.0, -12.0),
    text: annotationText,
  );
  return base.copyWith(
    balls: movedBalls,
    paths: [mixedPath],
    annotations: [railAnnotation],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Phase 6 — Nghiệm thu Tra cứu thư viện, Xem bài & Bàn vẽ rộng', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bida_phase6_test_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('1. Tra cứu 500 bài giả lập trong fixture riêng: Lọc, Tìm kiếm & Dựng theo nhu cầu',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dbPath = p.join(tempDir.path, 'articles_500.db');
      final repo = SqliteNotebookRepository(dbPath: dbPath);

      await tester.runAsync(() async {
        await repo.initialize();
        final db = repo.dbForTesting!;
        final batch = db.batch();
        final nowIso = DateTime.utc(2026, 11, 12, 5, 0).toIso8601String();
        for (var i = 0; i < 500; i++) {
          final kind = i < 300
              ? 'technique'
              : (i < 400 ? 'system' : 'position');
          final grpId = i % 2 == 0 ? 'tech_draw' : 'tech_follow';
          final code = 'KT-${i.toString().padLeft(3, '0')}';
          batch.insert('articles', {
            'id': 'art_$i',
            'code': code,
            'kind': kind,
            'title': 'Bài tập libre số $i',
            'summary': 'Tóm tắt bài $i',
            'primary_group_id': grpId,
            'tags_json': '[]',
            'difficulty': i % 3 == 0
                ? 'unrated'
                : (i % 3 == 1 ? 'intermediate' : 'advanced'),
            'goal': '',
            'content': '',
            'steps_json': '[]',
            'common_mistakes': '',
            'source': null,
            'author': null,
            'source_page': null,
            'source_url': null,
            'is_draft': 0,
            'stroke_params_json': '{}',
            'created_at': nowIso,
            'updated_at': nowIso,
            'is_favorite': i % 10 == 0 ? 1 : 0,
            'practice_status': 'not_started',
            'related_article_ids_json': '[]',
          });
        }
        await batch.commit(noResult: true);
        await repo.reloadCacheForTesting();
      });

      final controller = NotebookController(repository: repo);
      await tester.runAsync(() => controller.initialize());

      await tester.pumpWidget(
        MaterialApp(
          home: NotebookHomeScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Kiểm tra 500 bài được lưu và tab Kĩ thuật lọc ra 300 bài
      expect(controller.visibleArticles.length, 300);

      // Cơ chế on-demand của ListView: chỉ dựng số lượng card vừa màn hình
      final renderedCards = find.byType(Card);
      expect(renderedCards.evaluate().length, lessThan(30));

      // Thử tìm kiếm bài số "150"
      controller.setSearchQuery('150');
      await tester.pumpAndSettle();
      expect(controller.visibleArticles.length, 1);
      expect(find.text('Bài tập libre số 150'), findsOneWidget);

      // Xóa tìm kiếm và lọc Yêu thích
      controller.setSearchQuery('');
      controller.toggleFavoritesOnly();
      await tester.pumpAndSettle();
      expect(controller.visibleArticles.every((a) => a.isFavorite), isTrue);

      controller.clearFilters();
      await tester.pumpAndSettle();
      expect(controller.visibleArticles.length, 300);

      await tester.runAsync(() => repo.close());
    });

    testWidgets('2. Chuyển đổi Lưới / Danh sách (Grid / List): Nhớ lựa chọn & không mất bộ lọc',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dbPath = p.join(tempDir.path, 'grid_list.db');
      final repo = SqliteNotebookRepository(dbPath: dbPath);

      await tester.runAsync(() async {
        await repo.initialize();
        final db = repo.dbForTesting!;
        final nowIso = DateTime.utc(2026, 11, 12, 5, 0).toIso8601String();
        await db.insert('articles', {
          'id': 'art_test_1',
          'code': 'KT-001',
          'kind': 'technique',
          'title': 'Kỹ thuật Trô kéo 1',
          'summary': 'Tóm tắt bài 1',
          'primary_group_id': 'tech_draw',
          'tags_json': '[]',
          'difficulty': 'intermediate',
          'goal': '',
          'content': '',
          'steps_json': '[]',
          'common_mistakes': '',
          'source': null,
          'author': null,
          'source_page': null,
          'source_url': null,
          'is_draft': 0,
          'stroke_params_json': '{}',
          'created_at': nowIso,
          'updated_at': nowIso,
          'is_favorite': 0,
          'practice_status': 'not_started',
          'related_article_ids_json': '[]',
        });
        await db.insert('articles', {
          'id': 'art_test_2',
          'code': 'KT-002',
          'kind': 'technique',
          'title': 'Kỹ thuật Cule 2',
          'summary': 'Tóm tắt bài 2',
          'primary_group_id': 'tech_follow',
          'tags_json': '[]',
          'difficulty': 'intermediate',
          'goal': '',
          'content': '',
          'steps_json': '[]',
          'common_mistakes': '',
          'source': null,
          'author': null,
          'source_page': null,
          'source_url': null,
          'is_draft': 0,
          'stroke_params_json': '{}',
          'created_at': nowIso,
          'updated_at': nowIso,
          'is_favorite': 1,
          'practice_status': 'not_started',
          'related_article_ids_json': '[]',
        });
        await repo.reloadCacheForTesting();
      });

      final controller = NotebookController(repository: repo);
      await tester.runAsync(() => controller.initialize());

      await tester.pumpWidget(
        MaterialApp(
          home: NotebookHomeScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Mặc định là danh sách
      expect(find.byKey(const Key('articles_list_technique')), findsOneWidget);
      expect(find.byKey(const Key('articles_grid_technique')), findsNothing);

      // Bấm nút chuyển đổi dạng xem
      final toggleBtn = find.byKey(const Key('toggle_view_mode_button'));
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      // Xác nhận chuyển sang GridView
      expect(find.byKey(const Key('articles_grid_technique')), findsOneWidget);
      expect(find.byKey(const Key('articles_list_technique')), findsNothing);

      // Card dạng lưới hiển thị tiêu đề rõ ràng
      expect(find.text('Kỹ thuật Trô kéo 1'), findsOneWidget);
      expect(find.text('Kỹ thuật Cule 2'), findsOneWidget);

      // Chuyển sang tab "Bộ số" rồi quay lại "Kĩ thuật": chế độ Lưới vẫn được nhớ
      controller.selectTab(ArticleKind.system);
      await tester.pump();
      await tester.pumpAndSettle();
      controller.selectTab(ArticleKind.technique);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('articles_grid_technique')), findsOneWidget);

      // Chuyển lại về Danh sách
      await tester.tap(find.byKey(const Key('toggle_view_mode_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('articles_list_technique')), findsOneWidget);

      await tester.runAsync(() => repo.close());
    });

    testWidgets('3. Xem bài và Xem sơ đồ lớn: Zoom/Pan chỉ đọc, chuyển sơ đồ & nút Vừa màn hình',
        (tester) async {
      final dbPath = p.join(tempDir.path, 'viewer.db');
      final repo = SqliteNotebookRepository(dbPath: dbPath);

      late Article saved;
      await tester.runAsync(() async {
        await repo.initialize();
        final db = repo.dbForTesting!;
        final s1 = _buildRichScene('scene_view_1', whiteY: 70.0);
        final s2 = _buildRichScene('scene_view_2', whiteY: 120.0);
        final nowIso = DateTime.utc(2026, 11, 12, 5, 0).toIso8601String();
        await db.insert('articles', {
          'id': 'art_viewer_test',
          'code': 'KT-099',
          'kind': 'technique',
          'title': 'Bài xem sơ đồ lớn',
          'summary': 'Tóm tắt bài xem sơ đồ',
          'primary_group_id': 'tech_draw',
          'tags_json': '[]',
          'difficulty': 'intermediate',
          'goal': '',
          'content': 'Nội dung',
          'steps_json': '[]',
          'common_mistakes': '',
          'source': null,
          'author': null,
          'source_page': null,
          'source_url': null,
          'is_draft': 0,
          'stroke_params_json': '{}',
          'created_at': nowIso,
          'updated_at': nowIso,
          'is_favorite': 0,
          'practice_status': 'not_started',
          'related_article_ids_json': '[]',
        });
        await db.insert('article_diagrams', {
          'id': 'diag_1',
          'article_id': 'art_viewer_test',
          'sort_order': 0,
          'caption': 'Giai đoạn 1: Chuẩn bị ra cơ',
          'scene_json': jsonEncode(s1.toJson()),
        });
        await db.insert('article_diagrams', {
          'id': 'diag_2',
          'article_id': 'art_viewer_test',
          'sort_order': 1,
          'caption': 'Giai đoạn 2: Bi gom về góc',
          'scene_json': jsonEncode(s2.toJson()),
        });
        await repo.reloadCacheForTesting();
        saved = repo.getArticleById('art_viewer_test')!;
      });

      final controller = NotebookController(repository: repo);
      await tester.runAsync(() => controller.initialize());

      await tester.pumpWidget(
        MaterialApp(
          home: ArticleDetailScreen(
            controller: controller,
            articleId: saved.id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra có nút "Xem lớn" ở sơ đồ 1
      final openViewerBtn = find.byKey(const Key('open_diagram_viewer_0'));
      expect(openViewerBtn, findsOneWidget);
      await tester.tap(openViewerBtn);
      await tester.pumpAndSettle();

      // Xác nhận DiagramViewerScreen mở ra
      expect(find.byType(DiagramViewerScreen), findsOneWidget);
      expect(find.byKey(const Key('diagram_interactive_viewer')), findsOneWidget);
      expect(find.text('Giai đoạn 1: Chuẩn bị ra cơ'), findsOneWidget);

      // Chuyển sang sơ đồ 2
      final nextBtn = find.byKey(const Key('next_diagram_button'));
      expect(nextBtn, findsOneWidget);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
      expect(find.text('Giai đoạn 2: Bi gom về góc'), findsOneWidget);

      // Nút "Vừa màn hình" (Đặt lại góc nhìn)
      final resetZoomBtn = find.byKey(const Key('reset_diagram_zoom_button'));
      expect(resetZoomBtn, findsOneWidget);
      await tester.tap(resetZoomBtn);
      await tester.pumpAndSettle();

      // Thoát xem lớn
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Xác nhận quay lại chi tiết bài viết và sơ đồ nguyên vẹn
      expect(find.byType(ArticleDetailScreen), findsOneWidget);
      final checkArticle = controller.getArticleById(saved.id)!;
      expect(checkArticle.diagrams[0].scene.balls[0].center.y, 70.0);

      await tester.runAsync(() => repo.close());
    });

    testWidgets('4. Bàn vẽ rộng và Thu gọn panel thuộc tính (TableStageScreen)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TableEditorController();
      await tester.pumpWidget(
        MaterialApp(
          home: TableStageScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Kiểm tra canvas bàn bi hiển thị
      expect(find.byKey(const Key('billiard_table_canvas')), findsOneWidget);

      // Panel thuộc tính ở đáy màn hình
      expect(find.byKey(const Key('floating_ball_panel')), findsOneWidget);

      // Nhấn nút thu gọn thuộc tính
      final collapseBtn = find.byKey(const Key('floating_panel_collapse_button'));
      expect(collapseBtn, findsOneWidget);
      await tester.tap(collapseBtn);
      await tester.pumpAndSettle();

      // Xác nhận panel đã thu gọn thành pill nhỏ, giải phóng không gian bàn bi
      expect(find.byKey(const Key('floating_panel_collapsed_pill')), findsOneWidget);
      expect(find.byKey(const Key('floating_ball_panel')), findsNothing);

      // Chạm mở lại thuộc tính
      await tester.tap(find.byKey(const Key('floating_panel_expand_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_ball_panel')), findsOneWidget);

      // Thu gọn thanh công cụ chính
      final toolbarCollapse =
          find.byKey(const Key('floating_toolbar_collapse_button'));
      expect(toolbarCollapse, findsOneWidget);
      await tester.tap(toolbarCollapse);
      await tester.pumpAndSettle();

      // Mở lại thanh công cụ
      await tester.tap(toolbarCollapse);
      await tester.pumpAndSettle();
    });

    testWidgets('5. Soạn bài 4 phần: Thông tin / Nội dung / Sơ đồ / Ảnh & Nguồn không mất dữ liệu',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dbPath = p.join(tempDir.path, 'editor_4_sections.db');
      final repo = SqliteNotebookRepository(dbPath: dbPath);
      await tester.runAsync(() => repo.initialize());

      final controller = NotebookController(repository: repo);
      await tester.runAsync(() => controller.initialize());

      await tester.pumpWidget(
        MaterialApp(
          home: ArticleEditorScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra thanh chuyển 4 phần xuất hiện ở đầu trang
      expect(find.byKey(const Key('editor_section_tab_info')), findsOneWidget);
      expect(find.byKey(const Key('editor_section_tab_content')), findsOneWidget);
      expect(find.byKey(const Key('editor_section_tab_diagrams')), findsOneWidget);
      expect(find.byKey(const Key('editor_section_tab_media')), findsOneWidget);

      // Điền tiêu đề ở phần 1
      await tester.enterText(
        find.byKey(const Key('article_title_input')),
        'Bài thử nghiệm Phase 6',
      );
      await tester.pumpAndSettle();

      // Bấm tab "Nội dung" -> chuyển tới phần 2
      await tester.tap(find.byKey(const Key('editor_section_tab_content')));
      await tester.pumpAndSettle();

      // Điền mục tiêu ở phần 2
      await tester.enterText(
        find.byKey(const Key('article_goal_input')),
        'Mục tiêu bi gom sát băng',
      );
      await tester.pumpAndSettle();

      // Bấm tab "Sơ đồ" ở trên: cuộn tới phần 3
      await tester.tap(find.byKey(const Key('editor_section_tab_diagrams')));
      await tester.pumpAndSettle();

      // Bấm tab "Thông tin" ở trên: cuộn về đầu trang
      await tester.tap(find.byKey(const Key('editor_section_tab_info')));
      await tester.pumpAndSettle();

      // Kiểm tra dữ liệu tiêu đề và mục tiêu vẫn được bảo toàn nguyên vẹn
      expect(find.text('Bài thử nghiệm Phase 6'), findsOneWidget);
      expect(find.text('Mục tiêu bi gom sát băng'), findsOneWidget);

      await tester.runAsync(() => repo.close());
    });
  });
}
