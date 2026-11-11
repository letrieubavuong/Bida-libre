import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/geometry/table_constants.dart';
import 'package:libre_billiard_notebook/main.dart';
import 'package:libre_billiard_notebook/models/models.dart';

void main() {
  group('NAV-01: Khung điều hướng ba mục & không mô phỏng vật lý', () {
    testWidgets('Hiển thị đúng 3 tab Kĩ thuật, Bộ số, Hình bi và không có Play/mô phỏng',
        (WidgetTester tester) async {
      await tester.pumpWidget(const LibreBilliardApp());

      final navBar = find.byType(NavigationBar);
      expect(navBar, findsOneWidget);

      final destinations = find.descendant(
        of: navBar,
        matching: find.byType(NavigationDestination),
      );
      expect(destinations, findsNWidgets(3));

      expect(find.text('Kĩ thuật'), findsOneWidget);
      expect(find.text('Bộ số'), findsOneWidget);
      expect(find.text('Hình bi'), findsOneWidget);

      // Không có nút Play / Pause hay mô phỏng vật lý
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.textContaining('mô phỏng', findRichText: true), findsNothing);

      // Tab mặc định là Kĩ thuật và có các nhóm khởi đầu
      expect(find.text('LibreBilliard — Kĩ thuật'), findsOneWidget);
      expect(find.text('Trô / kéo'), findsOneWidget);

      // Chuyển sang tab Bộ số
      await tester.tap(find.text('Bộ số'));
      await tester.pumpAndSettle();
      expect(find.text('LibreBilliard — Bộ số'), findsOneWidget);
      expect(find.text('Chưa phân nhóm'), findsOneWidget);

      // Chuyển sang tab Hình bi
      await tester.tap(find.text('Hình bi'));
      await tester.pumpAndSettle();
      expect(find.text('LibreBilliard — Hình bi'), findsOneWidget);
      expect(find.text('Gom góc'), findsOneWidget);
      expect(find.text('Gom dọc băng dài'), findsOneWidget);
    });

    testWidgets('Hỗ trợ tìm kiếm, bật bộ lọc Yêu thích và xóa lọc ở trạng thái rỗng',
        (WidgetTester tester) async {
      await tester.pumpWidget(const LibreBilliardApp());

      expect(find.text('Chưa có bài nào trong mục Kĩ thuật'), findsOneWidget);

      await tester.tap(find.byTooltip('Yêu thích'));
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy kết quả phù hợp'), findsOneWidget);
      expect(find.text('Bỏ lọc'), findsOneWidget);

      await tester.tap(find.text('Bỏ lọc'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có bài nào trong mục Kĩ thuật'), findsOneWidget);
    });
  });

  group('Data Models & Serialization Round-Trip', () {
    test('Nhóm biên tập mặc định khớp đặc tả mục 4.1 và 4.3', () {
      expect(DefaultEditorialGroups.techniqueGroups.length, 6);
      expect(DefaultEditorialGroups.positionGroups.length, 8);
      expect(
        DefaultEditorialGroups.positionGroups.map((g) => g.id).toList(),
        [
          'corner',
          'long_rail',
          'short_rail',
          'center',
          'return',
          'series',
          'special',
          'unclassified',
        ],
      );
    });

    test('Article round-trip JSON giữ nguyên ID, mã, loại và trạng thái', () {
      final now = DateTime.utc(2026, 11, 11, 10, 0);
      final article = Article(
        id: 'uuid-article-1',
        code: 'KT-001',
        kind: ArticleKind.technique,
        title: 'Kỹ thuật trô căn bản',
        summary: 'Tóm tắt kỹ thuật',
        primaryGroupId: 'tech_draw',
        tags: const ['tro', 'keo'],
        difficulty: Difficulty.basic,
        content: 'Nội dung hướng dẫn tĩnh',
        source: 'Tài liệu mẫu',
        createdAt: now,
        updatedAt: now,
        isFavorite: true,
        practiceStatus: PracticeStatus.practicing,
        relatedArticleIds: const ['uuid-pos-1'],
      );

      final restored = Article.fromJson(article.toJson());
      expect(restored.id, article.id);
      expect(restored.code, 'KT-001');
      expect(restored.kind, ArticleKind.technique);
      expect(restored.primaryGroupId, 'tech_draw');
      expect(restored.difficulty, Difficulty.basic);
      expect(restored.isFavorite, isTrue);
      expect(restored.practiceStatus, PracticeStatus.practicing);
      expect(restored.relatedArticleIds, ['uuid-pos-1']);
    });

    test('DiagramScene round-trip JSON bảo toàn kích thước 188x376 và tọa độ bi', () {
      final scene = DiagramScene.defaultInitial(id: 'scene-1');
      expect(scene.width, TableConstants.playfieldWidth);
      expect(scene.height, TableConstants.playfieldHeight);
      expect(scene.balls.length, 3);

      final restored = DiagramScene.fromJson(scene.toJson());
      expect(restored.id, 'scene-1');
      expect(restored.version, 1);
      expect(restored.balls.length, 3);
      expect(restored.balls[0].center, const DiagramPoint(94.0, 94.0));
      expect(restored.balls[0].radius, 4.0);
    });

    test('PracticeEntry kiểm tra số lần đạt không âm và không lớn hơn số lần thử', () {
      expect(
        () => PracticeEntry(
          id: 'p1',
          articleId: 'a1',
          date: DateTime.utc(2026, 11, 11),
          attempts: 5,
          successes: 6,
        ),
        throwsArgumentError,
      );
      expect(
        () => PracticeEntry(
          id: 'p2',
          articleId: 'a1',
          date: DateTime.utc(2026, 11, 11),
          attempts: 5,
          successes: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}
