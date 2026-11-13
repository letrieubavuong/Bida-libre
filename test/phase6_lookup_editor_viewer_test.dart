import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:libre_billiard_notebook/geometry/table_geometry.dart';
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

      // Mặc định khi vào màn hình: panel thuộc tính ẩn thành pill nhỏ để giải phóng không gian bàn bi
      expect(find.byKey(const Key('floating_panel_collapsed_pill')), findsOneWidget);
      expect(find.byKey(const Key('floating_ball_panel')), findsNothing);

      // Chạm mở lại thuộc tính từ nút Thuộc tính trên thanh phải hoặc từ pill
      await tester.tap(find.byKey(const Key('open_properties_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_ball_panel')), findsOneWidget);

      // Nhấn nút thu gọn thuộc tính
      final collapseBtn = find.byKey(const Key('floating_panel_collapse_button'));
      expect(collapseBtn, findsOneWidget);
      await tester.tap(collapseBtn);
      await tester.pumpAndSettle();

      // Xác nhận panel đã thu gọn thành pill nhỏ, giải phóng không gian bàn bi
      expect(find.byKey(const Key('floating_panel_collapsed_pill')), findsOneWidget);
      expect(find.byKey(const Key('floating_ball_panel')), findsNothing);

      // Chạm mở lại thuộc tính bằng pill
      await tester.tap(find.byKey(const Key('floating_panel_expand_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_ball_panel')), findsOneWidget);

      // Thu gọn thanh công cụ trái
      final leftToolbarCollapse =
          find.byKey(const Key('left_toolbar_collapse_button'));
      expect(leftToolbarCollapse, findsOneWidget);
      await tester.tap(leftToolbarCollapse);
      await tester.pumpAndSettle();

      // Mở lại thanh công cụ trái
      await tester.tap(leftToolbarCollapse);
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

    testWidgets(
        '6. Điều hướng Editor: Bỏ offset cứng, cuộn chính xác với bài viết dài & text scale lớn (1.5x, 2.0x)',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844); // iPhone 12/13/14 portrait
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dbPath = p.join(tempDir.path, 'editor_long_content.db');
      final repo = SqliteNotebookRepository(dbPath: dbPath);
      await tester.runAsync(() => repo.initialize());
      final controller = NotebookController(repository: repo);
      await tester.runAsync(() => controller.initialize());

      // Tạo bài viết dài có sẵn nhiều bước đánh, thẻ nhãn và sơ đồ
      final longArticle = Article(
        id: 'long_art_1',
        code: 'KT099',
        kind: ArticleKind.technique,
        title: 'Kỹ thuật gom bi dài nhiều bước',
        primaryGroupId: 'grp_tech_retro',
        tags: ['Gom bi', 'Băng dài', 'Retro', 'Masse', 'Bi mục tiêu 1', 'Bi mục tiêu 2'],
        steps: [
          'Bước 1: Quan sát góc tới và góc phản xạ',
          'Bước 2: Chọn điểm ngắm trên bi chạm cách 3mm',
          'Bước 3: Hạ thấp cán cơ 5 độ so với mặt bàn',
          'Bước 4: Ướm cơ đều nhịp 3 lần',
          'Bước 5: Ra ngọn dứt khoát không rụt tay',
          'Bước 6: Dừng mũi cơ sau mặt bi 2cm',
          'Bước 7: Giữ nguyên tư thế quan sát đường chạy',
        ],
        diagrams: [
          ArticleDiagram(
            id: 'diag_long_1',
            articleId: 'long_art_1',
            caption: 'Sơ đồ thế bi gom',
            scene: _buildRichScene('scene_long_1'),
          ),
        ],
        createdAt: DateTime.utc(2026, 11, 12, 10, 0),
        updatedAt: DateTime.utc(2026, 11, 12, 10, 0),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5), // Cỡ chữ lớn 1.5x
            ),
            child: child!,
          ),
          home: ArticleEditorScreen(
            controller: controller,
            existingArticle: longArticle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Xác nhận tiêu đề phần 1 đang ở trong viewport
      expect(find.text('Thông tin chung'), findsOneWidget);

      // Chuyển sang phần 2: Nội dung
      await tester.ensureVisible(find.byKey(const Key('editor_section_tab_content')));
      await tester.tap(find.byKey(const Key('editor_section_tab_content')));
      await tester.pumpAndSettle();
      expect(find.text('Nội dung bài viết'), findsOneWidget);

      // Chuyển sang phần 3: Sơ đồ
      await tester.ensureVisible(find.byKey(const Key('editor_section_tab_diagrams')));
      await tester.tap(find.byKey(const Key('editor_section_tab_diagrams')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add_diagram_button')), findsOneWidget);

      // Chuyển sang phần 4: Ảnh & Nguồn
      await tester.ensureVisible(find.byKey(const Key('editor_section_tab_media')));
      await tester.tap(find.byKey(const Key('editor_section_tab_media')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add_image_button')), findsOneWidget);

      // Cuộn về lại phần 1: Thông tin chung
      await tester.ensureVisible(find.byKey(const Key('editor_section_tab_info')));
      await tester.tap(find.byKey(const Key('editor_section_tab_info')));
      await tester.pumpAndSettle();
      expect(find.text('Thông tin chung'), findsOneWidget);

      // Thao tác chỉnh sửa form ở phần 1 để xác nhận form state và validation hoàn toàn bình thường
      await tester.enterText(
        find.byKey(const Key('article_title_input')),
        'Kỹ thuật gom bi dài nhiều bước đã chỉnh sửa',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Kỹ thuật gom bi dài nhiều bước đã chỉnh sửa'),
        findsOneWidget,
      );

      await tester.runAsync(() => repo.close());
    });

    testWidgets(
        '7. Thumbnail trong Lưới (GridView) so với Danh sách (ListView): Kích thước thực tế & tỷ lệ bàn bi',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dbPath = p.join(tempDir.path, 'thumb_grid_vs_list.db');
      final repo = SqliteNotebookRepository(dbPath: dbPath);
      await tester.runAsync(() async {
        await repo.initialize();
        final db = repo.dbForTesting!;
        final nowIso = DateTime.utc(2026, 11, 12, 10, 0).toIso8601String();
        final s1 = _buildRichScene('scene_grid_1');
        await db.insert('articles', {
          'id': 'art_grid_test',
          'code': 'KT-001',
          'kind': 'technique',
          'title': 'Bài kiểm tra kích thước thumbnail',
          'summary': 'Tóm tắt bài',
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
        await db.insert('article_diagrams', {
          'id': 'diag_grid_1',
          'article_id': 'art_grid_test',
          'sort_order': 0,
          'caption': 'Sơ đồ mẫu',
          'scene_json': jsonEncode(s1.toJson()),
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

      // Mặc định đang ở chế độ Danh sách (ListView)
      final listThumbFinder = find.byKey(const Key('thumb_scene_art_grid_test'));
      expect(listThumbFinder, findsOneWidget);
      final listThumbSize = tester.getSize(listThumbFinder);
      expect(listThumbSize.width, lessThanOrEqualTo(50.0));
      expect(listThumbSize.height, lessThanOrEqualTo(80.0));

      // Chuyển sang chế độ Lưới (GridView)
      await tester.tap(find.byKey(const Key('toggle_view_mode_button')));
      await tester.pump();
      await tester.pumpAndSettle();

      // Thumbnail trong chế độ lưới phải chiếm vùng ảnh thực tế của card và lớn hơn nhiều danh sách
      final gridThumbFinder = find.byKey(const Key('thumb_scene_art_grid_test'));
      expect(gridThumbFinder, findsOneWidget);
      final gridThumbSize = tester.getSize(gridThumbFinder);
      expect(gridThumbSize.width, greaterThan(150.0));
      expect(gridThumbSize.height, greaterThan(100.0));

      await tester.runAsync(() => repo.close());
    });

    testWidgets(
        '8. Thu gọn mọi panel ngữ cảnh trên TableStageScreen: Bảo toàn dữ liệu, không tạo undo & nút mở lại luôn tiếp cận',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final initialScene = _buildRichScene('stage_collapse_test');
      final controller = TableEditorController(initialScene: initialScene);

      await tester.pumpWidget(
        MaterialApp(
          home: TableStageScreen(
            controller: controller,
            returnSceneOnSave: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final collapseBtnFinder = find.byKey(const Key('floating_panel_collapse_button'));
      final expandBtnFinder = find.byKey(const Key('floating_panel_expand_button'));

      // 1. Panel chọn bi (floating_ball_panel) mặc định ẩn, bấm nút Thuộc tính để mở
      expect(find.byKey(const Key('floating_panel_collapsed_pill')), findsOneWidget);
      expect(find.byKey(const Key('floating_ball_panel')), findsNothing);
      await tester.tap(find.byKey(const Key('open_properties_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_ball_panel')), findsOneWidget);
      expect(collapseBtnFinder, findsOneWidget);
      await tester.tap(collapseBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_ball_panel')), findsNothing);
      expect(expandBtnFinder, findsOneWidget);
      await tester.tap(expandBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_ball_panel')), findsOneWidget);

      // 2. Panel vẽ đường (floating_draw_panel)
      await tester.tap(find.byKey(const Key('mode_draw_chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_draw_panel')), findsOneWidget);
      // Giả lập thêm 2 điểm vẽ dở dang
      controller.addDraftPoint(const DiagramPoint(50.0, 50.0));
      controller.addDraftPoint(const DiagramPoint(80.0, 100.0));
      await tester.pumpAndSettle();
      expect(controller.draftPoints.length, 2);
      final initialUndoCount = controller.canUndo;

      // Thu gọn panel vẽ đường
      await tester.tap(collapseBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_draw_panel')), findsNothing);
      expect(expandBtnFinder, findsOneWidget);
      // Dữ liệu điểm vẽ dở không bị xóa, không tạo thêm bước undo
      expect(controller.draftPoints.length, 2);
      expect(controller.canUndo, initialUndoCount);

      // Mở lại panel vẽ đường
      await tester.tap(expandBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_draw_panel')), findsOneWidget);
      expect(find.text('2 điểm'), findsOneWidget);
      expect(find.byKey(const Key('complete_draft_path_button')), findsOneWidget);

      // Hủy đường vẽ để chuyển sang kiểm tra panel khác
      await tester.tap(find.byKey(const Key('cancel_draft_path_button')));
      await tester.pumpAndSettle();

      // 3. Panel chọn đường (floating_path_panel)
      controller.selectPath('stage_collapse_test_path_1');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_path_panel')), findsOneWidget);
      await tester.tap(collapseBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_panel_collapsed_pill')), findsOneWidget);
      expect(controller.selectedPathId, 'stage_collapse_test_path_1');
      await tester.tap(expandBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_path_panel')), findsOneWidget);
      controller.selectPath(null);
      await tester.pumpAndSettle();

      // 4. Panel đặt chú thích (floating_place_annotation_panel)
      await tester.tap(find.byKey(const Key('mode_annotation_chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_place_annotation_panel')), findsOneWidget);
      await tester.ensureVisible(collapseBtnFinder);
      await tester.tap(collapseBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_panel_collapsed_pill')), findsOneWidget);
      expect(controller.toolMode, EditorToolMode.placeAnnotation);
      await tester.tap(expandBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_place_annotation_panel')), findsOneWidget);
      controller.setToolMode(EditorToolMode.select);
      await tester.pumpAndSettle();

      // 5. Panel sửa chú thích (floating_annotation_panel)
      controller.selectAnnotation('stage_collapse_test_ann_1');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_annotation_panel')), findsOneWidget);
      await tester.ensureVisible(collapseBtnFinder);
      await tester.tap(collapseBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_panel_collapsed_pill')), findsOneWidget);
      expect(controller.selectedAnnotationId, 'stage_collapse_test_ann_1');
      await tester.tap(expandBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_annotation_panel')), findsOneWidget);
    });

    testWidgets(
        '9. Thích ứng giao diện màn hình hẹp (320px–390px), màn hình ngang & Text Scale lớn không overflow',
        (tester) async {
      // Thử nghiệm màn hình cực hẹp 320x568 (iPhone SE gen 1) với text scale 1.5x
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final initialScene = _buildRichScene('narrow_screen_test');
      final controller = TableEditorController(initialScene: initialScene);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: TableStageScreen(
            controller: controller,
            returnSceneOnSave: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra các nút cốt lõi đều tiếp cận và nhấn được trên màn hình hẹp
      expect(find.byKey(const Key('mode_select_chip')), findsOneWidget);
      expect(find.byKey(const Key('mode_draw_chip')), findsOneWidget);
      expect(find.byKey(const Key('save_scene_button')), findsOneWidget);

      // Thử nghiệm chuyển sang màn hình ngang (Landscape 800x360)
      tester.view.physicalSize = const Size(800, 360);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mode_select_chip')), findsOneWidget);
      expect(find.byKey(const Key('mode_draw_chip')), findsOneWidget);
      expect(find.byKey(const Key('save_scene_button')), findsOneWidget);
    });

    testWidgets(
        '10. Zoom/Pan hai ngón, Vừa màn hình & Kéo riêng biệt hai capsule trên TableStageScreen',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844); // iPhone 12/13/14
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final initialScene = _buildRichScene('zoom_pan_capsule_test');
      final controller = TableEditorController(initialScene: initialScene);

      await tester.pumpWidget(
        MaterialApp(
          home: TableStageScreen(
            controller: controller,
            returnSceneOnSave: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Kiểm tra vị trí ban đầu của 2 thanh capsule
      final leftHandleFinder = find.byKey(const Key('left_toolbar_drag_handle'));
      final rightHandleFinder = find.byKey(const Key('right_toolbar_drag_handle'));
      expect(leftHandleFinder, findsOneWidget);
      expect(rightHandleFinder, findsOneWidget);

      final initialLeftPos = tester.getCenter(leftHandleFinder);
      final initialRightPos = tester.getCenter(rightHandleFinder);

      // Kéo thanh trái xuống
      await tester.drag(leftHandleFinder, const Offset(0, 60));
      await tester.pumpAndSettle();
      final movedLeftPos = tester.getCenter(leftHandleFinder);
      expect(movedLeftPos.dy, greaterThan(initialLeftPos.dy + 30));
      // Thanh phải không bị ảnh hưởng khi kéo thanh trái
      expect(tester.getCenter(rightHandleFinder).dy, equals(initialRightPos.dy));

      // Kéo thanh phải xuống
      await tester.drag(rightHandleFinder, const Offset(0, 50));
      await tester.pumpAndSettle();
      final movedRightPos = tester.getCenter(rightHandleFinder);
      expect(movedRightPos.dy, greaterThan(initialRightPos.dy + 30));

      // Thu gọn và mở lại không làm mất vị trí kéo
      await tester.tap(find.byKey(const Key('left_toolbar_collapse_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('left_toolbar_collapse_button')));
      await tester.pumpAndSettle();
      expect(tester.getCenter(leftHandleFinder).dy, equals(movedLeftPos.dy));

      // 2. Kiểm tra InteractiveViewer zoom / pan và nút Vừa màn hình
      final interactiveFinder = find.byType(InteractiveViewer);
      expect(interactiveFinder, findsOneWidget);
      final ivWidget = tester.widget<InteractiveViewer>(interactiveFinder);
      final transCtrl = ivWidget.transformationController!;

      // Giả lập biến đổi zoom/pan bằng matrix
      transCtrl.value = Matrix4.identity()
        ..translateByDouble(30.0, 40.0, 0.0, 1.0)
        ..scaleByDouble(1.5, 1.5, 1.0, 1.0);
      await tester.pumpAndSettle();
      expect(transCtrl.value, isNot(equals(Matrix4.identity())));

      // Bấm nút Vừa màn hình (fit_screen_button)
      await tester.tap(find.byKey(const Key('fit_screen_button')));
      await tester.pumpAndSettle();

      // Transform được reset về ma trận đơn vị
      expect(transCtrl.value, equals(Matrix4.identity()));
      // Thao tác khung nhìn không làm thay đổi dữ liệu scene hay tạo bước undo
      expect(controller.canUndo, isFalse);
      expect(controller.hasUnsavedChanges, isFalse);

      // 3. Kéo bi sau zoom: tọa độ bi vẫn tính toán chính xác
      transCtrl.value = Matrix4.identity()
        ..scaleByDouble(1.2, 1.2, 1.0, 1.0);
      await tester.pumpAndSettle();

      final canvasFinder = find.byKey(const Key('billiard_table_canvas'));
      final canvasTopLeft = tester.getTopLeft(canvasFinder);
      final canvasSize = tester.getSize(canvasFinder);
      final mapper = TableCoordinateMapper(canvasSize: canvasSize);

      final whiteBall = controller.balls.firstWhere((b) => b.id == 'ball_white');
      final whiteScreenPos = canvasTopLeft + mapper.diagramToScreen(whiteBall.center);

      // Kéo nhẹ bi trắng
      await tester.dragFrom(whiteScreenPos, const Offset(20, 20));
      await tester.pumpAndSettle();

      // Bi vẫn nằm hoàn toàn trong giới hạn lòng bàn hợp lệ
      final updatedWhiteBall = controller.balls.firstWhere((b) => b.id == 'ball_white');
      expect(updatedWhiteBall.center.x, inInclusiveRange(updatedWhiteBall.radius, 188.0 - updatedWhiteBall.radius));
      expect(updatedWhiteBall.center.y, inInclusiveRange(updatedWhiteBall.radius, 376.0 - updatedWhiteBall.radius));
    });

    testWidgets(
        '7. Đính chính Phase 6A: Thanh thông số cách đánh 3 phần (Chạm trái 12 phần, Ép phê, Lực 0-100%)',
        (tester) async {
      tester.view.physicalSize = const Size(360, 720); // Màn hình hẹp
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final initialStroke = const StrokeParameters(
        thicknessMode: HitThicknessMode.twelfths,
        twelfthCount: 6,
        hitSide: HitSide.center,
        tipXMm: 0.0,
        tipZMm: 0.0,
        forcePercent: 50,
      );
      final initialScene = DiagramScene.defaultInitial(id: 'scene_test_stroke')
          .copyWith(strokeParameters: initialStroke);
      final controller = TableEditorController(initialScene: initialScene);
      addTearDown(() => controller.dispose());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableStageScreen(
              controller: controller,
              returnSceneOnSave: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Kiểm tra sự hiện diện của thanh đáy 3 phần
      expect(find.byKey(const Key('bottom_stroke_bar')), findsOneWidget);
      expect(find.byKey(const Key('bottom_hit_thickness_button')), findsOneWidget);
      expect(find.byKey(const Key('bottom_cue_tip_button')), findsOneWidget);
      expect(find.byKey(const Key('bottom_force_button')), findsOneWidget);

      // 2. PHẦN CHẠM TRÁI: Mở dialog, điều chỉnh slider 12 phần & má chạm, Hủy vs Áp dụng
      await tester.tap(find.byKey(const Key('bottom_hit_thickness_button')));
      await tester.pumpAndSettle();

      // Kiểm tra các thành phần trong dialog Chạm trái
      expect(find.text('Chạm trái / Độ dày tiếp xúc'), findsOneWidget);
      expect(find.byKey(const Key('hit_side_left')), findsOneWidget);
      expect(find.byKey(const Key('hit_side_right')), findsOneWidget);
      expect(find.byKey(const Key('hit_thickness_twelfths_slider')), findsOneWidget);
      expect(find.byKey(const Key('hit_thickness_cancel_button')), findsOneWidget);
      expect(find.byKey(const Key('hit_thickness_apply_button')), findsOneWidget);

      // Chọn má phải và trượt slider sang 9/12
      await tester.tap(find.byKey(const Key('hit_side_right')));
      await tester.pumpAndSettle();
      final sliderFinder = find.byKey(const Key('hit_thickness_twelfths_slider'));
      await tester.ensureVisible(sliderFinder);
      await tester.drag(sliderFinder, const Offset(50, 0));
      await tester.pumpAndSettle();

      // Bấm Hủy -> Không đổi giá trị trong controller
      await tester.ensureVisible(find.byKey(const Key('hit_thickness_cancel_button')));
      await tester.tap(find.byKey(const Key('hit_thickness_cancel_button')));
      await tester.pumpAndSettle();
      expect(controller.scene.strokeParameters.twelfthCount, 6);
      expect(controller.scene.strokeParameters.hitSide, HitSide.center);

      // Mở lại, chỉnh sang 9/12 và Má trái -> Áp dụng
      await tester.tap(find.byKey(const Key('bottom_hit_thickness_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hit_side_left')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('hit_thickness_twelfths_slider')));
      await tester.drag(find.byKey(const Key('hit_thickness_twelfths_slider')), const Offset(50, 0));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('hit_thickness_apply_button')));
      await tester.tap(find.byKey(const Key('hit_thickness_apply_button')));
      await tester.pumpAndSettle();

      expect(controller.scene.strokeParameters.hitSide, HitSide.left);
      expect(controller.hasUnsavedChanges, isTrue);
      expect(controller.canUndo, isTrue);

      // 3. PHẦN ÉP PHÊ: Mở dialog, điều chỉnh mũi cơ, liên kết cập nhật biểu tượng
      await tester.tap(find.byKey(const Key('bottom_cue_tip_button')));
      await tester.pumpAndSettle();
      expect(find.text('Ép phê / Điểm mũi cơ'), findsOneWidget);
      expect(find.byKey(const Key('cue_tip_interactive_ball')), findsOneWidget);

      // Kéo/chạm chấm mũi cơ trên mặt bi
      final ballCenter1 = tester.getCenter(find.byKey(const Key('cue_tip_interactive_ball')));
      await tester.tapAt(ballCenter1 + const Offset(25, -20));
      await tester.pumpAndSettle();

      // Bấm Hủy -> Giữ nguyên tọa độ cũ
      await tester.tap(find.byKey(const Key('cue_tip_cancel_button')));
      await tester.pumpAndSettle();
      expect(controller.scene.strokeParameters.tipXMm, 0.0);
      expect(controller.scene.strokeParameters.tipZMm, 0.0);

      // Mở lại, chọn điểm lệch tâm và bấm Áp dụng
      await tester.tap(find.byKey(const Key('bottom_cue_tip_button')));
      await tester.pumpAndSettle();
      final ballCenter2 = tester.getCenter(find.byKey(const Key('cue_tip_interactive_ball')));
      await tester.tapAt(ballCenter2 + const Offset(30, -25));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cue_tip_apply_button')));
      await tester.pumpAndSettle();

      // Ép phê được cập nhật, tỷ lệ chạm trái và má chạm KHÔNG bị thay đổi
      expect(controller.scene.strokeParameters.tipXMm, isNot(0.0));
      expect(controller.scene.strokeParameters.hitSide, HitSide.left);

      // 4. PHẦN LỰC ĐÁNH: 0..100%, chặn ngoài miền, cập nhật số
      await tester.tap(find.byKey(const Key('bottom_force_button')));
      await tester.pumpAndSettle();
      expect(find.text('Lực đánh'), findsOneWidget);
      expect(find.byKey(const Key('force_slider')), findsOneWidget);
      expect(find.byKey(const Key('force_number_input')), findsOneWidget);

      // Thử nhập số ngoài miền (> 100) -> báo lỗi và vô hiệu hóa nút Áp dụng
      await tester.enterText(find.byKey(const Key('force_number_input')), '150');
      await tester.pumpAndSettle();
      expect(find.text('Lực phải nằm trong khoảng từ 0% đến 100%.'), findsOneWidget);

      // Nhập số hợp lệ 75%
      await tester.enterText(find.byKey(const Key('force_number_input')), '75');
      await tester.pumpAndSettle();
      expect(find.text('Lực phải nằm trong khoảng từ 0% đến 100%.'), findsNothing);

      await tester.tap(find.byKey(const Key('force_apply_button')));
      await tester.pumpAndSettle();

      expect(controller.scene.strokeParameters.forcePercent, 75);
      expect(controller.scene.strokeParameters.forceDisplay, '75%');

      // 5. Kiểm tra tính năng Undo / Redo cho thông số cách đánh
      expect(controller.canUndo, isTrue);
      controller.undo();
      await tester.pumpAndSettle();
      // Quay lại lực trước đó
      expect(controller.scene.strokeParameters.forcePercent, isNot(75));

      controller.redo();
      await tester.pumpAndSettle();
      expect(controller.scene.strokeParameters.forcePercent, 75);

      // 6. Kiểm tra bảo toàn dữ liệu cũ (8 phần) không bị âm thầm làm tròn
      final legacyJson = {
        'cueBallId': 'ball_white',
        'thicknessMode': 'eighths',
        'eighthCount': 3,
        'hitSide': 'left',
        'tipXMm': 5.0,
        'tipZMm': -3.0,
        'forceText': 'vừa đủ về',
      };
      final loadedParams = StrokeParameters.fromJson(legacyJson);
      expect(loadedParams.thicknessMode, HitThicknessMode.eighths);
      expect(loadedParams.eighthCount, 3);
      expect(loadedParams.forceText, 'vừa đủ về');
      expect(loadedParams.effectiveThicknessFraction, closeTo(3.0 / 8.0, 1e-4));
      // Không bị ép sang 12 phần khi serialize lại
      final exportedJson = loadedParams.toJson();
      expect(exportedJson['thicknessMode'], 'eighths');
      expect(exportedJson['eighthCount'], 3);
    });
  });
}
