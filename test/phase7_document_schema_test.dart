import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/models/models.dart';

void main() {
  group('ArticleBlock & ArticleDocument Schema Tests', () {
    test('YouTubeBlockData extracts video IDs correctly from various formats', () {
      final validUrls = [
        ('https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'dQw4w9WgXcQ'),
        ('https://youtu.be/dQw4w9WgXcQ', 'dQw4w9WgXcQ'),
        ('https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=42s', 'dQw4w9WgXcQ'),
        ('https://www.youtube.com/embed/dQw4w9WgXcQ', 'dQw4w9WgXcQ'),
        ('https://www.youtube.com/shorts/dQw4w9WgXcQ', 'dQw4w9WgXcQ'),
      ];

      for (final (url, expectedId) in validUrls) {
        final parsed = YouTubeBlockData.fromInputUrl(url, caption: 'Test Video');
        expect(parsed, isNotNull, reason: 'Failed for url: $url');
        expect(parsed!.videoId, expectedId);
        expect(parsed.caption, 'Test Video');
      }

      final invalid = YouTubeBlockData.fromInputUrl('https://example.com/video');
      expect(invalid, isNull);

      final scriptInjection = YouTubeBlockData.fromInputUrl('<script>alert("hack")</script>');
      expect(scriptInjection, isNull);
    });

    test('Heading numbering & TOC calculation works recursively and correctly', () {
      final doc = ArticleDocument(
        blocks: [
          ArticleBlock(
            id: 'h1',
            type: ArticleBlockType.heading,
            data: HeadingBlockData(text: 'Khái niệm cơ bản', level: 1),
          ),
          ArticleBlock(
            id: 'p1',
            type: ArticleBlockType.paragraph,
            data: ParagraphBlockData(text: 'Nội dung khái niệm.'),
          ),
          ArticleBlock(
            id: 'h2',
            type: ArticleBlockType.heading,
            data: HeadingBlockData(text: 'Tư thế đứng', level: 2),
          ),
          ArticleBlock(
            id: 'h3',
            type: ArticleBlockType.heading,
            data: HeadingBlockData(text: 'Chân trước chân sau', level: 3),
          ),
          ArticleBlock(
            id: 'h4',
            type: ArticleBlockType.heading,
            data: HeadingBlockData(text: 'Góc nghiêng', level: 3),
          ),
          ArticleBlock(
            id: 'h5',
            type: ArticleBlockType.heading,
            data: HeadingBlockData(text: 'Cách cầm cơ', level: 2),
          ),
          ArticleBlock(
            id: 'h6',
            type: ArticleBlockType.heading,
            data: HeadingBlockData(text: 'Kỹ thuật nâng cao', level: 1),
          ),
        ],
      );

      final headingNumbers = doc.computeHeadingNumbers();
      expect(headingNumbers['h1'], '1.');
      expect(headingNumbers['h2'], '1.1.');
      expect(headingNumbers['h3'], '1.1.1.');
      expect(headingNumbers['h4'], '1.1.2.');
      expect(headingNumbers['h5'], '1.2.');
      expect(headingNumbers['h6'], '2.');

      final toc = doc.generateTableOfContents();
      expect(toc.length, 6);
      expect(toc[0].title, 'Khái niệm cơ bản');
      expect(toc[0].numbering, '1.');
      expect(toc[2].title, 'Chân trước chân sau');
      expect(toc[2].numbering, '1.1.1.');
      expect(toc[2].level, 3);
    });

    test('Round-trip JSON serialization preserves all 12 block types and data', () {
      final doc = ArticleDocument(
        schemaVersion: 1,
        blocks: [
          ArticleBlock(
            id: 'b-head',
            type: ArticleBlockType.heading,
            data: HeadingBlockData(text: 'Đề mục chính', level: 1),
          ),
          ArticleBlock(
            id: 'b-para',
            type: ArticleBlockType.paragraph,
            data: ParagraphBlockData(
              text: 'Văn bản có định dạng đậm và nghiêng.',
              spans: [
                InlineSpanStyle(
                  start: 11,
                  end: 18,
                  styles: {InlineStyle.bold},
                ),
                InlineSpanStyle(
                  start: 22,
                  end: 30,
                  styles: {InlineStyle.italic},
                ),
              ],
            ),
          ),
          ArticleBlock(
            id: 'b-callout',
            type: ArticleBlockType.callout,
            data: CalloutBlockData(
              preset: CalloutPreset.mistake,
              title: 'Lỗi thường gặp',
              content: 'Không nhấp cơ quá nhanh.',
            ),
          ),
          ArticleBlock(
            id: 'b-bullet',
            type: ArticleBlockType.bulletList,
            data: BulletListBlockData(
              items: [
                ListItemData(text: 'Mục 1', level: 0),
                ListItemData(text: 'Mục 1.a lồng', level: 1),
              ],
            ),
          ),
          ArticleBlock(
            id: 'b-ordered',
            type: ArticleBlockType.orderedList,
            data: OrderedListBlockData(
              numberingStyle: NumberingStyle.number,
              items: [
                ListItemData(text: 'Bước 1', level: 0),
                ListItemData(text: 'Bước 2', level: 0),
              ],
            ),
          ),
          ArticleBlock(
            id: 'b-img',
            type: ArticleBlockType.image,
            data: ImageBlockData(
              assetId: 'asset-123',
              caption: 'Hình minh họa thế bi',
              displaySize: ImageDisplaySize.large,
            ),
          ),
          ArticleBlock(
            id: 'b-yt',
            type: ArticleBlockType.youtubeVideo,
            data: YouTubeBlockData(
              url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
              videoId: 'dQw4w9WgXcQ',
              caption: 'Video hướng dẫn cụ thể',
            ),
          ),
          ArticleBlock(
            id: 'b-diag',
            type: ArticleBlockType.billiardDiagram,
            data: BilliardDiagramBlockData(
              diagramId: 'diag-456',
              caption: 'Sơ đồ đường đi bi chủ',
            ),
          ),
          ArticleBlock(
            id: 'b-stroke',
            type: ArticleBlockType.strokeParameter,
            data: StrokeParameterBlockData(
              strokeParameters: StrokeParameters(
                twelfthCount: 4,
                hitSide: HitSide.left,
                tipXMm: -4.0,
                tipZMm: 2.0,
                forcePercent: 45,
                forceText: 'Lực êm vừa đủ 3 băng',
              ),
              linkedDiagramId: 'diag-456',
            ),
          ),
          ArticleBlock(
            id: 'b-div',
            type: ArticleBlockType.divider,
            data: DividerBlockData(),
          ),
          ArticleBlock(
            id: 'b-code',
            type: ArticleBlockType.codeFormula,
            data: CodeFormulaBlockData(
              text: 'Tia = Điểm ngắm - Điểm chạm',
              language: 'formula',
            ),
          ),
          ArticleBlock(
            id: 'b-unk',
            type: ArticleBlockType.unknown,
            data: UnknownBlockData(
              rawType: 'customFutureType',
              rawData: {'futureKey': 123},
            ),
          ),
        ],
      );

      final serialized = doc.toJsonString();
      final restored = ArticleDocument.fromJsonString(serialized);

      expect(restored.schemaVersion, 1);
      expect(restored.blocks.length, 12);
      expect(restored.blocks[0].type, ArticleBlockType.heading);
      expect((restored.blocks[0].data as HeadingBlockData).text, 'Đề mục chính');
      expect((restored.blocks[1].data as ParagraphBlockData).spans.length, 2);
      expect(
        (restored.blocks[2].data as CalloutBlockData).preset,
        CalloutPreset.mistake,
      );
      expect(
        (restored.blocks[7].data as BilliardDiagramBlockData).diagramId,
        'diag-456',
      );
      final restoredStroke =
          restored.blocks[8].data as StrokeParameterBlockData;
      expect(restoredStroke.strokeParameters.twelfthCount, 4);
      expect(restoredStroke.linkedDiagramId, 'diag-456');
      expect(restored.blocks[11].type, ArticleBlockType.unknown);
      expect(
        (restored.blocks[11].data as UnknownBlockData).rawType,
        'customFutureType',
      );
    });

    test('ArticleDocumentConverter converts legacy article without losing fields', () {
      final legacy = Article(
        id: 'art-legacy-1',
        code: 'KT-001',
        kind: ArticleKind.technique,
        title: 'Kỹ thuật Cule trố',
        summary: 'Tóm tắt kỹ thuật cule.',
        primaryGroupId: 'technique_basic',
        tags: ['cule', 'bida-libre'],
        difficulty: Difficulty.intermediate,
        goal: 'Đưa bi 2 về gần bi 3',
        content: 'Nội dung hướng dẫn chính của bài viết dạng legacy.',
        steps: ['Bước 1: Ngắm tâm bi', 'Bước 2: Ra ngọn thẳng'],
        commonMistakes: 'Thường bị cắm cơ quá sâu.',
        isDraft: false,
        strokeParameters: StrokeParameters(
          twelfthCount: 8,
          hitSide: HitSide.center,
          forcePercent: 60,
        ),
        diagrams: [
          ArticleDiagram(
            id: 'diag-legacy-1',
            articleId: 'art-legacy-1',
            sortOrder: 0,
            caption: 'Sơ đồ cule',
            scene: DiagramScene(id: 'diag-legacy-1', balls: const []),
          ),
        ],
        images: [
          ArticleImageAttachment(
            id: 'img-legacy-1',
            articleId: 'art-legacy-1',
            assetId: 'asset-legacy-1',
            relativePath: 'images/cule.jpg',
            originalName: 'cule.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 1024,
            caption: 'Ảnh tư thế cule',
            sortOrder: 0,
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final doc = ArticleDocumentConverter.fromArticle(legacy);
      expect(doc.blocks.isNotEmpty, isTrue);

      final callouts = doc.blocks
          .where((b) => b.type == ArticleBlockType.callout)
          .map((b) => b.data as CalloutBlockData)
          .toList();
      final diagrams = doc.blocks
          .where((b) => b.type == ArticleBlockType.billiardDiagram)
          .toList();
      final strokes = doc.blocks
          .where((b) => b.type == ArticleBlockType.strokeParameter)
          .toList();
      final images = doc.blocks
          .where((b) => b.type == ArticleBlockType.image)
          .toList();
      final orderedLists = doc.blocks
          .where((b) => b.type == ArticleBlockType.orderedList)
          .toList();

      expect(callouts.any((c) => c.content.contains('Đưa bi 2 về gần bi 3')), isTrue);
      expect(orderedLists.isNotEmpty, isTrue);
      expect(
        (orderedLists.first.data as OrderedListBlockData).items.length,
        2,
      );
      expect(callouts.any((c) => c.content.contains('cắm cơ quá sâu')), isTrue);
      expect(diagrams.length, 1);
      expect(strokes.length, 1);
      expect(images.length, 1);

      // Kiểm tra extract plain text
      final plainText = ArticleDocumentConverter.extractPlainText(doc);
      expect(plainText.contains('Đưa bi 2 về gần bi 3'), isTrue);
      expect(plainText.contains('Nội dung hướng dẫn chính'), isTrue);
      expect(plainText.contains('Bước 1: Ngắm tâm bi'), isTrue);
    });
  });
}
