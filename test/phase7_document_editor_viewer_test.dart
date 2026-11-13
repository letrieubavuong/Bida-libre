import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/models/models.dart';
import 'package:libre_billiard_notebook/repositories/article_asset_store.dart';
import 'package:libre_billiard_notebook/repositories/sqlite_notebook_repository.dart';
import 'package:libre_billiard_notebook/state/notebook_controller.dart';
import 'package:libre_billiard_notebook/ui/screens/article_detail_screen.dart';
import 'package:libre_billiard_notebook/ui/widgets/article_detail_body.dart';
import 'package:libre_billiard_notebook/ui/widgets/article_document_editor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _transparentPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _transparentPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_transparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    HttpOverrides.global = _TestHttpOverrides();
  });

  group('Phase 7 Comprehensive Document Editor & Viewer Tests', () {
    late Directory tempDir;
    late SqliteNotebookRepository repository;
    late NotebookController controller;

    Future<void> initRepoAndController() async {
      final dbPath = '${tempDir.path}/test_p7.db';
      repository = SqliteNotebookRepository(
        dbPath: dbPath,
        databaseFactoryOverride: databaseFactoryFfi,
        directoryPathProvider: () async => tempDir.path,
      );
      await repository.initialize();
      controller = NotebookController(repository: repository);
      await controller.initialize();
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bida_libre_phase7_');
    });

    tearDown(() async {
      try {
        controller.dispose();
      } catch (_) {}
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Uint8List valid1x1Png() {
      return Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);
    }

    /// Hàm tạo Fixture bài viết mẫu KT-PHASE7 chứa đầy đủ toàn bộ 10+ loại khối
    Article createPhase7CompleteFixture({String? relativePath}) {
      const diagId = 'diag_fixture_p7';
      const assetId = 'asset_fixture_p7';
      final actualPath = relativePath ?? 'images/fixture_p7.png';

      final doc = ArticleDocument(
        schemaVersion: 1,
        blocks: [
          // 1. Đề mục cấp 1, 2, 3 kèm đánh số
          ArticleBlock(
            id: 'h_1',
            type: ArticleBlockType.heading,
            data: const HeadingBlockData(
              level: 1,
              text: 'Tổng quan Kỹ thuật Bida Libre Nâng cao',
              isNumbered: true,
            ),
          ),
          ArticleBlock(
            id: 'h_1_1',
            type: ArticleBlockType.heading,
            data: const HeadingBlockData(
              level: 2,
              text: 'Cơ sở Lý thuyết và Điểm chạm',
              isNumbered: true,
            ),
          ),
          ArticleBlock(
            id: 'h_1_1_1',
            type: ArticleBlockType.heading,
            data: const HeadingBlockData(
              level: 3,
              text: 'Quy ước phân chia 12 phần bi',
              isNumbered: true,
            ),
          ),

          // 2. Đoạn văn có in đậm, in nghiêng, liên kết
          ArticleBlock(
            id: 'para_1',
            type: ArticleBlockType.paragraph,
            data: const ParagraphBlockData(
              text:
                  'Kỹ thuật đánh đòi hỏi sự chính xác tuyệt đối ở mũi cơ và cảm giác lực êm ái. Tham khảo thêm tài liệu tại trang chủ.',
              spans: [
                InlineSpanStyle(
                  start: 27,
                  end: 45,
                  styles: {InlineStyle.bold},
                ),
                InlineSpanStyle(
                  start: 57,
                  end: 74,
                  styles: {InlineStyle.italic},
                ),
                InlineSpanStyle(
                  start: 104,
                  end: 113,
                  styles: {InlineStyle.link},
                  url: 'https://example.com/bida-libre',
                ),
              ],
            ),
          ),

          // 3. Khung ghi chú (Callout đủ 5 presets)
          ArticleBlock(
            id: 'callout_note',
            type: ArticleBlockType.callout,
            data: const CalloutBlockData(
              preset: CalloutPreset.note,
              title: 'Ghi chú quan trọng',
              content: 'Luôn giữ thẳng ngọn cơ khi ra đòn.',
            ),
          ),
          ArticleBlock(
            id: 'callout_warning',
            type: ArticleBlockType.callout,
            data: const CalloutBlockData(
              preset: CalloutPreset.warning,
              title: 'Cảnh báo kẹt bi',
              content: 'Tránh đánh quá dày khiến bi chủ bị dính cơ.',
            ),
          ),
          ArticleBlock(
            id: 'callout_example',
            type: ArticleBlockType.callout,
            data: const CalloutBlockData(
              preset: CalloutPreset.example,
              title: 'Ví dụ thực tế',
              content: 'Thế bi mắt kính cự ly 15cm dọc băng dài.',
            ),
          ),
          ArticleBlock(
            id: 'callout_tip',
            type: ArticleBlockType.callout,
            data: const CalloutBlockData(
              preset: CalloutPreset.tip,
              title: 'Mẹo ra cơ',
              content: 'Thả lỏng cổ tay và nhấp cơ đều 3 nhịp.',
            ),
          ),
          ArticleBlock(
            id: 'callout_mistake',
            type: ArticleBlockType.callout,
            data: const CalloutBlockData(
              preset: CalloutPreset.mistake,
              title: 'Lỗi thường gặp',
              content: 'Gồng ngón tay cái khiến bi lệch hướng.',
              items: ['Cắm cơ quá sâu gây tẹc cơ', 'Đẩy mũi cơ giật cục'],
            ),
          ),

          // 4. Danh sách không thứ tự lồng nhau
          ArticleBlock(
            id: 'bullet_list',
            type: ArticleBlockType.bulletList,
            data: const BulletListBlockData(
              items: [
                ListItemData(text: 'Trang bị cần chuẩn bị', level: 0),
                ListItemData(text: 'Cơ bida libre đầu 11.5mm', level: 1),
                ListItemData(text: 'Lơ bida mịn có độ bám cao', level: 1),
                ListItemData(text: 'Găng tay vải mỏng', level: 2),
                ListItemData(text: 'Tâm lý thi đấu ổn định', level: 0),
              ],
            ),
          ),

          // 5. Danh sách có thứ tự lồng nhau
          ArticleBlock(
            id: 'ordered_list',
            type: ArticleBlockType.orderedList,
            data: const OrderedListBlockData(
              numberingStyle: NumberingStyle.number,
              items: [
                ListItemData(text: 'Quan sát vị trí 3 bi trên bàn', level: 0),
                ListItemData(text: 'Xác định tia ngắm và độ dày chạm', level: 0),
                ListItemData(text: 'Đặt cầu tay vững chắc', level: 1),
                ListItemData(text: 'Thực hiện cú đánh dứt khoát', level: 0),
              ],
            ),
          ),

          // 6. Đường phân cách
          ArticleBlock(
            id: 'div_1',
            type: ArticleBlockType.divider,
            data: const DividerBlockData(),
          ),

          // 7. Video YouTube
          ArticleBlock(
            id: 'yt_1',
            type: ArticleBlockType.youtubeVideo,
            data: const YouTubeBlockData(
              url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
              videoId: 'dQw4w9WgXcQ',
              caption: 'Video thị phạm chi tiết thế bi',
            ),
          ),

          // 8. Sơ đồ hình bi (Phase 6A)
          ArticleBlock(
            id: 'diag_block_1',
            type: ArticleBlockType.billiardDiagram,
            data: const BilliardDiagramBlockData(
              diagramId: diagId,
              caption: 'Sơ đồ thế bi gom số 1',
            ),
          ),

          // 9. Thẻ thông số cách đánh 3 phần (Chạm trái 12 vạch, Ép phê, Lực)
          ArticleBlock(
            id: 'stroke_block_1',
            type: ArticleBlockType.strokeParameter,
            data: const StrokeParameterBlockData(
              linkedDiagramId: diagId,
              strokeParameters: StrokeParameters(
                cueBallId: 'ball_white',
                twelfthCount: 5,
                hitSide: HitSide.left,
                tipXMm: -3.84,
                tipZMm: 7.68,
                forcePercent: 40,
                forceText: 'Lực êm vừa tới băng',
                strokeStyleText: 'Đẩy dài tay',
              ),
            ),
          ),

          // 10. Ảnh đính kèm
          ArticleBlock(
            id: 'img_block_1',
            type: ArticleBlockType.image,
            data: const ImageBlockData(
              assetId: assetId,
              caption: 'Ảnh minh họa góc nhìn từ trên xuống',
              displaySize: ImageDisplaySize.large,
            ),
          ),

          // 11. Công thức / Mã
          ArticleBlock(
            id: 'code_formula_1',
            type: ArticleBlockType.codeFormula,
            data: const CodeFormulaBlockData(
              text: 'Tia_đích = Điểm_ngắm_băng_3 - (Góc_vào * 0.5)',
              language: 'formula',
            ),
          ),
        ],
      );

      return Article(
        id: 'art_fixture_phase7',
        code: 'KT-PHASE7',
        kind: ArticleKind.technique,
        title: 'Kỹ thuật gom bi Libre đỉnh cao',
        summary: 'Tài liệu hướng dẫn hoàn chỉnh theo chuẩn Phase 7.',
        primaryGroupId: 'tech_foundation',
        tags: ['gom-bi', 'libre-nang-cao', 'phase7'],
        difficulty: Difficulty.advanced,
        goal: 'Gom cả 3 bi vào góc dậu trong 2 lượt cơ.',
        content: 'Nội dung kỹ thuật tổng quan.',
        steps: const ['Bước A', 'Bước B'],
        commonMistakes: 'Lỗi đánh xước bi.',
        isDraft: false,
        strokeParameters: const StrokeParameters(
          twelfthCount: 5,
          hitSide: HitSide.left,
          forcePercent: 40,
        ),
        diagrams: [
          ArticleDiagram(
            id: diagId,
            articleId: 'art_fixture_phase7',
            sortOrder: 0,
            caption: 'Sơ đồ gom bi góc dậu',
            scene: DiagramScene.defaultInitial(
              id: diagId,
            ),
          ),
        ],
        images: [
          ArticleImageAttachment(
            id: 'img_att_p7',
            articleId: 'art_fixture_phase7',
            assetId: assetId,
            relativePath: actualPath,
            originalName: 'fixture_p7.png',
            mimeType: 'image/png',
            sizeBytes: 2048,
            caption: 'Góc chụp thực tế thế bi',
            sortOrder: 0,
          ),
        ],
        document: doc,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
    }

    test('SQLite Round-trip: Save fixture with all block types -> Reload cache -> Verify complete fidelity', () async {
      await initRepoAndController();
      final staged = await repository.assetStore.stageImageBytes(
        assetId: 'asset_fixture_p7',
        bytes: valid1x1Png(),
        originalName: 'fixture_p7.png',
      );
      final fixture = createPhase7CompleteFixture(relativePath: staged.relativePath);
      final savedOutcome = await controller.saveArticle(fixture);
      expect(savedOutcome.isSuccess, isTrue, reason: savedOutcome.error);

      // Xóa bộ nhớ đệm và nạp lại trực tiếp từ CSDL SQLite
      await repository.reloadCacheForTesting();

      final reloaded = controller.getArticleById(fixture.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.code, 'KT-PHASE7');
      expect(reloaded.title, 'Kỹ thuật gom bi Libre đỉnh cao');
      expect(reloaded.document, isNotNull);

      final reloadedDoc = reloaded.document!;
      expect(reloadedDoc.blocks.length, 17);

      // 1. Kiểm tra Heading
      final h1 = reloadedDoc.blocks[0];
      expect(h1.type, ArticleBlockType.heading);
      expect((h1.data as HeadingBlockData).text, 'Tổng quan Kỹ thuật Bida Libre Nâng cao');
      expect((h1.data as HeadingBlockData).level, 1);

      // 2. Kiểm tra Paragraph & Inline spans
      final p1 = reloadedDoc.blocks[3];
      expect(p1.type, ArticleBlockType.paragraph);
      final pData = p1.data as ParagraphBlockData;
      expect(pData.spans.length, 3);
      expect(pData.spans.any((s) => s.styles.contains(InlineStyle.bold)), isTrue);
      expect(pData.spans.any((s) => s.styles.contains(InlineStyle.link) && s.url!.contains('example.com')), isTrue);

      // 3. Kiểm tra Callout presets
      final callouts = reloadedDoc.blocks.where((b) => b.type == ArticleBlockType.callout).toList();
      expect(callouts.length, 5);
      expect((callouts[0].data as CalloutBlockData).preset, CalloutPreset.note);
      expect((callouts[1].data as CalloutBlockData).preset, CalloutPreset.warning);
      expect((callouts[2].data as CalloutBlockData).preset, CalloutPreset.example);
      expect((callouts[3].data as CalloutBlockData).preset, CalloutPreset.tip);
      expect((callouts[4].data as CalloutBlockData).preset, CalloutPreset.mistake);
      expect((callouts[4].data as CalloutBlockData).items.length, 2);

      // 4. Kiểm tra Bullet List lồng nhau
      final bulletBlock = reloadedDoc.blocks.firstWhere((b) => b.type == ArticleBlockType.bulletList);
      final bulletData = bulletBlock.data as BulletListBlockData;
      expect(bulletData.items.length, 5);
      expect(bulletData.items[3].level, 2);

      // 5. Kiểm tra Ordered List
      final orderedBlock = reloadedDoc.blocks.firstWhere((b) => b.type == ArticleBlockType.orderedList);
      final orderedData = orderedBlock.data as OrderedListBlockData;
      expect(orderedData.items.length, 4);

      // 6. Kiểm tra YouTube Block
      final ytBlock = reloadedDoc.blocks.firstWhere((b) => b.type == ArticleBlockType.youtubeVideo);
      final ytData = ytBlock.data as YouTubeBlockData;
      expect(ytData.videoId, 'dQw4w9WgXcQ');

      // 7. Kiểm tra Sơ đồ & Thẻ ép phê 3 phần
      final diagBlock = reloadedDoc.blocks.firstWhere((b) => b.type == ArticleBlockType.billiardDiagram);
      expect((diagBlock.data as BilliardDiagramBlockData).diagramId, 'diag_fixture_p7');

      final strokeBlock = reloadedDoc.blocks.firstWhere((b) => b.type == ArticleBlockType.strokeParameter);
      final strokeData = strokeBlock.data as StrokeParameterBlockData;
      expect(strokeData.strokeParameters.twelfthCount, 5);
      expect(strokeData.strokeParameters.forcePercent, 40);
      expect(strokeData.linkedDiagramId, 'diag_fixture_p7');

      // 8. Kiểm tra Công thức
      final codeBlock = reloadedDoc.blocks.firstWhere((b) => b.type == ArticleBlockType.codeFormula);
      expect((codeBlock.data as CodeFormulaBlockData).text.contains('Tia_đích'), isTrue);
    });

    testWidgets('ArticleDetailScreen renders Phase 7 Document with Table of Contents and interactive blocks', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late Article fixture;
      await tester.runAsync(() async {
        await initRepoAndController();
        final staged = await repository.assetStore.stageImageBytes(
          assetId: 'asset_fixture_p7',
          bytes: valid1x1Png(),
          originalName: 'fixture_p7.png',
        );
        fixture = createPhase7CompleteFixture(relativePath: staged.relativePath);
        final savedOutcome = await controller.saveArticle(fixture);
        expect(savedOutcome.isSuccess, isTrue);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArticleDetailScreen(
              controller: controller,
              articleId: fixture.id,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Kiểm tra sự xuất hiện của tiêu đề bài viết
      expect(find.text('Kỹ thuật gom bi Libre đỉnh cao'), findsOneWidget);

      // Kiểm tra sự xuất hiện của nút Mục lục (TOC)
      final tocBtn = find.byKey(const Key('document_toc_button'));
      expect(tocBtn, findsOneWidget);

      // Bấm vào Mục lục mở danh sách đề mục
      await tester.tap(tocBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Mục lục bài viết'), findsOneWidget);
      expect(find.text('1. Tổng quan Kỹ thuật Bida Libre Nâng cao'), findsAtLeastNWidgets(1));

      // Đóng mục lục
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Kiểm tra sự xuất hiện của các khối Callout
      expect(find.text('Ghi chú quan trọng'), findsOneWidget);
      expect(find.text('Cảnh báo kẹt bi'), findsOneWidget);
      expect(find.text('Ví dụ thực tế'), findsOneWidget);
      expect(find.text('Mẹo ra cơ'), findsOneWidget);
      expect(find.text('Lỗi thường gặp'), findsOneWidget);

      // Kiểm tra khối Video YouTube
      expect(find.text('Mở YouTube'), findsOneWidget);

      // Kiểm tra sơ đồ bi-a thu nhỏ
      expect(find.byKey(const Key('readonly_diagram_0')), findsOneWidget);
    });

    testWidgets('ArticleDocumentEditor supports Block manipulations: Add, Move, Heading Subsection Move, Duplicate, Undo/Redo', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fixture = createPhase7CompleteFixture();

      ArticleDocument? updatedDoc;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArticleDocumentEditor(
                article: fixture,
                initialDocument: fixture.document!,
                assetStore: ArticleAssetStore(directoryProvider: () async => tempDir),
                onDocumentChanged: (doc) => updatedDoc = doc,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra ban đầu có 17 khối
      final editorState = tester.state<ArticleDocumentEditorState>(
        find.byType(ArticleDocumentEditor),
      );
      expect(editorState.currentDocument.blocks.length, 17);

      // 1. Kiểm tra Undo ban đầu là false
      expect(editorState.canUndo, isFalse);

      // 2. Nhân bản khối đầu tiên (Heading 1)
      final moreMenuFirst = find.byIcon(Icons.more_vert).first;
      await tester.tap(moreMenuFirst);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhân bản'));
      await tester.pumpAndSettle();

      expect(editorState.currentDocument.blocks.length, 18);
      expect(updatedDoc, isNotNull);
      expect(editorState.canUndo, isTrue);

      // 3. Hoàn tác (Undo)
      final undoBtn = find.byKey(const Key('document_undo_button'));
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();
      expect(editorState.currentDocument.blocks.length, 17);
      expect(editorState.canRedo, isTrue);

      // 4. Làm lại (Redo)
      final redoBtn = find.byKey(const Key('document_redo_button'));
      await tester.tap(redoBtn);
      await tester.pumpAndSettle();
      expect(editorState.currentDocument.blocks.length, 18);
      expect(updatedDoc, isNotNull);

      // Undo lại để về 17 khối ban đầu
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();
      expect(editorState.currentDocument.blocks.length, 17);

      // 5. Thêm một khối Divider mới
      final addBottomBtn = find.byKey(const Key('document_add_block_bottom_button'));
      await tester.ensureVisible(addBottomBtn);
      await tester.tap(addBottomBtn);
      await tester.pumpAndSettle();

      // Bấm chọn "Đường phân cách (Divider)"
      final dividerOption = find.text('Đường phân cách (Divider)');
      await tester.ensureVisible(dividerOption);
      await tester.tap(dividerOption);
      await tester.pumpAndSettle();

      expect(editorState.currentDocument.blocks.length, 18);
      expect(updatedDoc, isNotNull);
      expect(editorState.currentDocument.blocks.last.type, ArticleBlockType.divider);
    });

    testWidgets('1. Bài cổ điển: sửa nội dung -> lưu -> tải lại -> trang đọc hiển thị đúng bản mới', (tester) async {
      await tester.runAsync(() async {
        await initRepoAndController();
        const artId = 'art_classic_1';
        final classicArt = Article(
          id: artId,
          code: 'KT-CLS',
          kind: ArticleKind.technique,
          title: 'Bài viết cổ điển ban đầu',
          summary: 'Tóm tắt bài cổ điển',
          primaryGroupId: 'tech_foundation',
          goal: 'Mục tiêu ban đầu',
          content: 'Nội dung giải thích ban đầu',
          steps: const ['Bước 1 ban đầu', 'Bước 2 ban đầu'],
          commonMistakes: 'Lỗi ban đầu',
          document: null,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await repository.saveArticle(classicArt);
        final loaded = repository.getArticleById(artId);
        expect(loaded, isNotNull);
        expect(loaded!.document, isNull);
        expect(loaded.content, 'Nội dung giải thích ban đầu');

        // Sửa nội dung ở chế độ cổ điển và lưu lại (không lưu document cũ)
        final editedClassic = loaded.copyWith(
          content: 'Nội dung mới đã được cập nhật chuẩn xác',
          goal: 'Mục tiêu mới đã sửa',
          clearDocument: true,
          updatedAt: DateTime.now().toUtc(),
        );
        await repository.saveArticle(editedClassic);

        final reloaded = repository.getArticleById(artId);
        expect(reloaded, isNotNull);
        expect(reloaded!.document, isNull);
        expect(reloaded.content, 'Nội dung mới đã được cập nhật chuẩn xác');

        // Render ra ArticleDetailBody kiểm tra nội dung mới hiển thị đúng
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ArticleDetailBody(
                article: reloaded,
                groupName: 'Cơ bản',
                assetStore: repository.assetStore,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nội dung mới đã được cập nhật chuẩn xác'), findsOneWidget);
        expect(find.text('Mục tiêu mới đã sửa'), findsOneWidget);
        expect(find.text('Nội dung giải thích ban đầu'), findsNothing);
      });
    });

    testWidgets('2. Document: xóa toàn bộ khối -> lưu -> tải lại, nội dung cũ không hồi sinh', (tester) async {
      await tester.runAsync(() async {
        await initRepoAndController();
        const artId = 'art_empty_doc';
        // Bài viết có document rỗng (người dùng đã chủ động xóa hết khối)
        // và trường cổ điển rác cũ
        final emptyDocArt = Article(
          id: artId,
          code: 'KT-EMP',
          kind: ArticleKind.technique,
          title: 'Bài viết xóa hết khối',
          summary: 'Tóm tắt bài',
          primaryGroupId: 'tech_foundation',
          goal: 'Mục tiêu cũ rác',
          content: 'Nội dung cũ rác không được hồi sinh',
          steps: const ['Bước rác'],
          document: const ArticleDocument(blocks: []),
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await repository.saveArticle(emptyDocArt);
        final reloaded = repository.getArticleById(artId);
        expect(reloaded, isNotNull);
        expect(reloaded!.document, isNotNull);
        expect(reloaded.document!.isEmpty, isTrue);

        // Render ra ArticleDetailBody: không được lôi các trường rác cổ điển ra hiển thị!
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ArticleDetailBody(
                article: reloaded,
                groupName: 'Cơ bản',
                assetStore: repository.assetStore,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nội dung cũ rác không được hồi sinh'), findsNothing);
        expect(find.text('Mục tiêu cũ rác'), findsNothing);
        expect(find.text('Bước rác'), findsNothing);
      });
    });

    testWidgets('3. Nhân bản bài có sơ đồ và thẻ liên kết -> tải lại -> liên kết đúng & độc lập sơ đồ', (tester) async {
      await tester.runAsync(() async {
        await initRepoAndController();
        const origArtId = 'art_orig_with_diag';
        const origDiagId = 'diag_orig_123';

        final origDiagram = ArticleDiagram(
          id: origDiagId,
          articleId: origArtId,
          sortOrder: 0,
          caption: 'Sơ đồ gốc',
          scene: DiagramScene.defaultInitial(id: origDiagId).copyWith(
            strokeParameters: const StrokeParameters(
              thicknessMode: HitThicknessMode.twelfths,
              twelfthCount: 4,
              forcePercent: 45,
            ),
          ),
        );

        final origDoc = ArticleDocument(
          schemaVersion: 1,
          blocks: [
            ArticleBlock(
              id: 'diag_block_orig',
              type: ArticleBlockType.billiardDiagram,
              data: const BilliardDiagramBlockData(
                diagramId: origDiagId,
                caption: 'Sơ đồ hình bi',
              ),
            ),
            ArticleBlock(
              id: 'stroke_block_orig',
              type: ArticleBlockType.strokeParameter,
              data: const StrokeParameterBlockData(
                linkedDiagramId: origDiagId,
                strokeParameters: StrokeParameters(
                  thicknessMode: HitThicknessMode.twelfths,
                  twelfthCount: 4,
                  forcePercent: 45,
                ),
              ),
            ),
          ],
        );

        final origArt = Article(
          id: origArtId,
          code: 'KT-ORIG',
          kind: ArticleKind.technique,
          title: 'Bài viết gốc',
          summary: 'Tóm tắt bài gốc',
          primaryGroupId: 'tech_foundation',
          diagrams: [origDiagram],
          document: origDoc,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await repository.saveArticle(origArt);

        // Nhân bản bài viết
        final cloned = await repository.duplicateArticle(origArtId);
        expect(cloned.id, isNot(origArtId));
        expect(cloned.diagrams.length, 1);
        final newDiagId = cloned.diagrams.first.id;
        expect(newDiagId, isNot(origDiagId));

        // Kiểm tra document bản sao đã được cập nhật mapping id mới
        expect(cloned.document, isNotNull);
        expect(cloned.document!.blocks.length, 2);

        final diagBlock = cloned.document!.blocks[0].data as BilliardDiagramBlockData;
        final strokeBlock = cloned.document!.blocks[1].data as StrokeParameterBlockData;

        expect(diagBlock.diagramId, newDiagId);
        expect(strokeBlock.linkedDiagramId, newDiagId);

        // Sửa sơ đồ trong bản sao (đổi lực thành 90%)
        final updatedClonedDiagram = cloned.diagrams.first.copyWith(
          scene: cloned.diagrams.first.scene.copyWith(
            strokeParameters: const StrokeParameters(
              thicknessMode: HitThicknessMode.twelfths,
              twelfthCount: 4,
              forcePercent: 90,
            ),
          ),
        );
        await repository.saveArticle(cloned.copyWith(diagrams: [updatedClonedDiagram]));

        // Kiểm tra bài gốc vẫn giữ nguyên thông số lực 45%
        final reloadedOrig = repository.getArticleById(origArtId);
        expect(reloadedOrig!.diagrams.first.scene.strokeParameters!.forcePercent, 45);
      });
    });

    testWidgets('4. Sửa khối ảnh và sơ đồ: giữ block ID và vị trí, không tăng số lượng khối; Undo/Redo khôi phục đúng', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const diag1Id = 'diag_1';
      const diag2Id = 'diag_2';
      final diag1 = ArticleDiagram(
        id: diag1Id,
        articleId: 'test_art',
        scene: DiagramScene.defaultInitial(id: diag1Id),
        caption: 'Sơ đồ 1',
      );
      final diag2 = ArticleDiagram(
        id: diag2Id,
        articleId: 'test_art',
        scene: DiagramScene.defaultInitial(id: diag2Id),
        caption: 'Sơ đồ 2',
      );

      final img1 = ArticleImageAttachment(
        id: 'img_att_1',
        articleId: 'test_art',
        assetId: 'asset_1',
        relativePath: 'images/img1.png',
        originalName: 'anh_1.png',
        mimeType: 'image/png',
        sizeBytes: 100,
        caption: 'Ảnh 1',
      );
      final img2 = ArticleImageAttachment(
        id: 'img_att_2',
        articleId: 'test_art',
        assetId: 'asset_2',
        relativePath: 'images/img2.png',
        originalName: 'anh_2.png',
        mimeType: 'image/png',
        sizeBytes: 100,
        caption: 'Ảnh 2',
      );

      final initialDoc = ArticleDocument(
        schemaVersion: 1,
        blocks: [
          ArticleBlock(
            id: 'block_img_fixed',
            type: ArticleBlockType.image,
            data: const ImageBlockData(
              assetId: 'asset_1',
              caption: 'Ảnh 1',
            ),
          ),
          ArticleBlock(
            id: 'block_diag_fixed',
            type: ArticleBlockType.billiardDiagram,
            data: const BilliardDiagramBlockData(
              diagramId: diag1Id,
              caption: 'Sơ đồ 1',
            ),
          ),
        ],
      );

      final testArt = Article(
        id: 'test_art',
        code: 'KT-TEST',
        kind: ArticleKind.technique,
        title: 'Test sửa khối',
        summary: 'Tóm tắt',
        primaryGroupId: 'tech_foundation',
        diagrams: [diag1, diag2],
        images: [img1, img2],
        document: initialDoc,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArticleDocumentEditor(
                article: testArt,
                initialDocument: initialDoc,
                assetStore: ArticleAssetStore(directoryProvider: () async => tempDir),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<ArticleDocumentEditorState>(
        find.byType(ArticleDocumentEditor),
      );
      expect(state.currentDocument.blocks.length, 2);

      // Mở menu chỉnh sửa khối ảnh đầu tiên
      final moreMenu = find.byIcon(Icons.more_vert).first;
      await tester.tap(moreMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      // Đổi sang chọn Ảnh 2
      expect(find.text('Thay đổi ảnh đính kèm'), findsOneWidget);
      await tester.tap(find.text('anh_2.png'));
      await tester.pumpAndSettle();

      // Kiểm tra: số lượng khối KHÔNG ĐỔI (vẫn là 2), block ID KHÔNG ĐỔI ('block_img_fixed')
      expect(state.currentDocument.blocks.length, 2);
      expect(state.currentDocument.blocks[0].id, 'block_img_fixed');
      final newImgData = state.currentDocument.blocks[0].data as ImageBlockData;
      expect(newImgData.assetId, 'asset_2');

      // Undo lại
      final undoBtn = find.byKey(const Key('document_undo_button'));
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();

      expect(state.currentDocument.blocks.length, 2);
      expect(state.currentDocument.blocks[0].id, 'block_img_fixed');
      final undoneImgData = state.currentDocument.blocks[0].data as ImageBlockData;
      expect(undoneImgData.assetId, 'asset_1');

      // Mở menu chỉnh sửa khối sơ đồ (khối thứ 2)
      final moreMenu2 = find.byIcon(Icons.more_vert).at(1);
      await tester.tap(moreMenu2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      // Đổi sang chọn Sơ đồ 2
      expect(find.text('Thay đổi sơ đồ'), findsOneWidget);
      final diagOption = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ListTile, 'Sơ đồ 2'),
      );
      await tester.tap(diagOption);
      await tester.pumpAndSettle();

      // Kiểm tra: số lượng khối KHÔNG ĐỔI (vẫn là 2), block ID KHÔNG ĐỔI ('block_diag_fixed')
      expect(state.currentDocument.blocks.length, 2);
      expect(state.currentDocument.blocks[1].id, 'block_diag_fixed');
      final newDiagData = state.currentDocument.blocks[1].data as BilliardDiagramBlockData;
      expect(newDiagData.diagramId, diag2Id);
    });

    testWidgets('5. Thẻ liên kết đọc thông số từ sơ đồ; Thẻ độc lập giữ thông số riêng', (tester) async {
      const diagId = 'diag_linked_test';
      final diagram = ArticleDiagram(
        id: diagId,
        articleId: 'art_stroke_test',
        scene: DiagramScene.defaultInitial(id: diagId).copyWith(
          strokeParameters: const StrokeParameters(
            thicknessMode: HitThicknessMode.twelfths,
            twelfthCount: 3,
            forcePercent: 30,
          ),
        ),
      );

      final doc = ArticleDocument(
        schemaVersion: 1,
        blocks: [
          // Thẻ liên kết
          ArticleBlock(
            id: 'stroke_linked',
            type: ArticleBlockType.strokeParameter,
            data: const StrokeParameterBlockData(
              linkedDiagramId: diagId,
              strokeParameters: StrokeParameters(
                thicknessMode: HitThicknessMode.twelfths,
                twelfthCount: 1, // ban đầu trong block
                forcePercent: 10,
              ),
            ),
          ),
          // Thẻ độc lập
          ArticleBlock(
            id: 'stroke_independent',
            type: ArticleBlockType.strokeParameter,
            data: const StrokeParameterBlockData(
              linkedDiagramId: null,
              strokeParameters: StrokeParameters(
                thicknessMode: HitThicknessMode.twelfths,
                twelfthCount: 8,
                forcePercent: 80,
              ),
            ),
          ),
        ],
      );

      final article = Article(
        id: 'art_stroke_test',
        code: 'KT-STK',
        kind: ArticleKind.technique,
        title: 'Kiểm tra thẻ thông số',
        summary: 'Tóm tắt',
        primaryGroupId: 'tech_foundation',
        diagrams: [diagram],
        document: doc,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      // Render bằng ArticleDetailBody
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArticleDetailBody(
              article: article,
              groupName: 'Cơ bản',
              assetStore: ArticleAssetStore(directoryProvider: () async => tempDir),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Thẻ liên kết phải đọc thông số từ sơ đồ (3/12 và 30% lực)
      expect(find.textContaining('3/12'), findsOneWidget);
      expect(find.textContaining('30%'), findsOneWidget);

      // Thẻ độc lập giữ thông số riêng (8/12 và 80% lực)
      expect(find.textContaining('8/12'), findsOneWidget);
      expect(find.textContaining('80%'), findsOneWidget);

      // Cập nhật thông số sơ đồ sang 10/12 và 95% lực
      final updatedDiagram = diagram.copyWith(
        scene: diagram.scene.copyWith(
          strokeParameters: const StrokeParameters(
            thicknessMode: HitThicknessMode.twelfths,
            twelfthCount: 10,
            forcePercent: 95,
          ),
        ),
      );
      final updatedArticle = article.copyWith(diagrams: [updatedDiagram]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArticleDetailBody(
              article: updatedArticle,
              groupName: 'Cơ bản',
              assetStore: ArticleAssetStore(directoryProvider: () async => tempDir),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Thẻ liên kết tự động cập nhật theo sơ đồ: 10/12 và 95%
      expect(find.textContaining('10/12'), findsOneWidget);
      expect(find.textContaining('95%'), findsOneWidget);

      // Thẻ độc lập vẫn giữ nguyên 8/12 và 80%
      expect(find.textContaining('8/12'), findsOneWidget);
      expect(find.textContaining('80%'), findsOneWidget);
      expect(find.text('Lực: 80%'), findsOneWidget);
    });

    testWidgets('6. Chỉnh ép phê và chạm trái k/12 -> lưu SQLite -> tải lại đúng dữ liệu', (tester) async {
      await tester.runAsync(() async {
        await initRepoAndController();
        const artId = 'art_cuetip_save';

        const customStroke = StrokeParameters(
          thicknessMode: HitThicknessMode.twelfths,
          twelfthCount: 5,
          tipXMm: 14.5,
          tipZMm: -9.8,
          forcePercent: 65,
        );

        final doc = ArticleDocument(
          schemaVersion: 1,
          blocks: [
            ArticleBlock(
              id: 'stroke_block_test',
              type: ArticleBlockType.strokeParameter,
              data: const StrokeParameterBlockData(
                linkedDiagramId: null,
                strokeParameters: customStroke,
              ),
            ),
          ],
        );

        final article = Article(
          id: artId,
          code: 'KT-CUE',
          kind: ArticleKind.technique,
          title: 'Bài kiểm tra ép phê',
          summary: 'Tóm tắt',
          primaryGroupId: 'tech_foundation',
          document: doc,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await repository.saveArticle(article);

        final reloaded = repository.getArticleById(artId);
        expect(reloaded, isNotNull);
        expect(reloaded!.document, isNotNull);
        expect(reloaded.document!.blocks.length, 1);

        final data = reloaded.document!.blocks.first.data as StrokeParameterBlockData;
        expect(data.strokeParameters.thicknessMode, HitThicknessMode.twelfths);
        expect(data.strokeParameters.twelfthCount, 5);
        expect(data.strokeParameters.tipXMm, 14.5);
        expect(data.strokeParameters.tipZMm, -9.8);
        expect(data.strokeParameters.forcePercent, 65);
      });
    });
  });
}
