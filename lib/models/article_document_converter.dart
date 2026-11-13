import '../models/article.dart';
import '../models/article_block.dart';
import '../models/article_document.dart';

/// Bộ chuyển đổi hai chiều giữa mô hình bài viết cũ và tài liệu khối Phase 7.
/// Bảo đảm 100% không mất dữ liệu cũ và không tự ý bịa thông số.
class ArticleDocumentConverter {
  const ArticleDocumentConverter._();

  /// Chuyển đổi một [Article] cũ thành [ArticleDocument].
  /// Tự động ánh xạ:
  /// - goal -> Khối Heading "Mục tiêu" + Khối Paragraph hoặc Callout tip
  /// - content -> Khối Heading "Nội dung" + Khối Paragraph
  /// - steps -> Khối Heading "Các bước thực hiện" + Khối OrderedList
  /// - mistakes -> Khối Callout preset mistake "Lỗi thường gặp"
  /// - diagrams -> Các khối BilliardDiagramBlock
  /// - images -> Các khối ImageBlock
  /// - strokeParameters -> Khối StrokeParameterBlock (liên kết với diagram đầu nếu có)
  static ArticleDocument fromArticle(Article article) {
    if (article.document != null && article.document!.isNotEmpty) {
      return article.document!;
    }

    final blocks = <ArticleBlock>[];
    int blockCounter = 1;
    String nextId(String prefix) => '${prefix}_${article.id}_${blockCounter++}';

    // 1. Mục tiêu bài viết
    final goal = article.goal.trim();
    if (goal.isNotEmpty) {
      blocks.add(
        ArticleBlock(
          id: nextId('block_goal_heading'),
          type: ArticleBlockType.heading,
          data: const HeadingBlockData(
            level: 2,
            text: 'Mục tiêu',
            isNumbered: true,
          ),
        ),
      );
      blocks.add(
        ArticleBlock(
          id: nextId('block_goal_content'),
          type: ArticleBlockType.callout,
          data: CalloutBlockData(
            preset: CalloutPreset.tip,
            title: 'Mục tiêu bài tập',
            content: goal,
          ),
        ),
      );
    }

    // 2. Nội dung chính
    final content = article.content.trim();
    if (content.isNotEmpty) {
      blocks.add(
        ArticleBlock(
          id: nextId('block_content_heading'),
          type: ArticleBlockType.heading,
          data: const HeadingBlockData(
            level: 2,
            text: 'Nội dung kỹ thuật',
            isNumbered: true,
          ),
        ),
      );
      blocks.add(
        ArticleBlock(
          id: nextId('block_content_para'),
          type: ArticleBlockType.paragraph,
          data: ParagraphBlockData(text: content),
        ),
      );
    }

    // 3. Các sơ đồ hình bi (Billiard Diagram)
    if (article.diagrams.isNotEmpty) {
      blocks.add(
        ArticleBlock(
          id: nextId('block_diagrams_heading'),
          type: ArticleBlockType.heading,
          data: const HeadingBlockData(
            level: 2,
            text: 'Sơ đồ hình bi',
            isNumbered: true,
          ),
        ),
      );
      for (final diag in article.diagrams) {
        blocks.add(
          ArticleBlock(
            id: nextId('block_diagram'),
            type: ArticleBlockType.billiardDiagram,
            data: BilliardDiagramBlockData(
              diagramId: diag.id,
              caption: diag.caption,
            ),
          ),
        );
      }
    }

    // 4. Thẻ thông số cách đánh
    final linkedId =
        article.diagrams.isNotEmpty ? article.diagrams.first.id : null;
    blocks.add(
      ArticleBlock(
        id: nextId('block_stroke'),
        type: ArticleBlockType.strokeParameter,
        data: StrokeParameterBlockData(
          linkedDiagramId: linkedId,
          strokeParameters: article.strokeParameters,
        ),
      ),
    );

    // 5. Các bước thực hiện (Steps)
    if (article.steps.isNotEmpty) {
      blocks.add(
        ArticleBlock(
          id: nextId('block_steps_heading'),
          type: ArticleBlockType.heading,
          data: const HeadingBlockData(
            level: 2,
            text: 'Các bước thực hiện',
            isNumbered: true,
          ),
        ),
      );
      blocks.add(
        ArticleBlock(
          id: nextId('block_steps_list'),
          type: ArticleBlockType.orderedList,
          data: OrderedListBlockData(
            numberingStyle: NumberingStyle.number,
            items: article.steps
                .map((s) => ListItemData(text: s, level: 0))
                .toList(growable: false),
          ),
        ),
      );
    }

    // 6. Lỗi thường gặp (Mistakes)
    if (article.commonMistakes.trim().isNotEmpty) {
      blocks.add(
        ArticleBlock(
          id: nextId('block_mistakes'),
          type: ArticleBlockType.callout,
          data: CalloutBlockData(
            preset: CalloutPreset.mistake,
            title: 'Lỗi thường gặp',
            content: article.commonMistakes.trim(),
          ),
        ),
      );
    }

    // 7. Ảnh đính kèm (Images)
    if (article.images.isNotEmpty) {
      blocks.add(
        ArticleBlock(
          id: nextId('block_images_heading'),
          type: ArticleBlockType.heading,
          data: const HeadingBlockData(
            level: 2,
            text: 'Ảnh minh họa & tư liệu',
            isNumbered: true,
          ),
        ),
      );
      for (final img in article.images) {
        blocks.add(
          ArticleBlock(
            id: nextId('block_image'),
            type: ArticleBlockType.image,
            data: ImageBlockData(
              assetId: img.assetId,
              caption: img.caption,
              displaySize: ImageDisplaySize.large,
            ),
          ),
        );
      }
    }

    return ArticleDocument(
      schemaVersion: ArticleDocument.currentSchemaVersion,
      blocks: blocks,
    );
  }

  /// Trích xuất văn bản thuần tổng hợp từ các khối để hỗ trợ tìm kiếm toàn văn FTS hoặc tóm tắt.
  static String extractPlainText(ArticleDocument document) {
    final buffer = StringBuffer();
    for (final b in document.blocks) {
      switch (b.type) {
        case ArticleBlockType.heading:
          if (b.data is HeadingBlockData) {
            buffer.writeln((b.data as HeadingBlockData).text);
          }
        case ArticleBlockType.paragraph:
          if (b.data is ParagraphBlockData) {
            buffer.writeln((b.data as ParagraphBlockData).text);
          }
        case ArticleBlockType.callout:
          if (b.data is CalloutBlockData) {
            final c = b.data as CalloutBlockData;
            if (c.title != null) buffer.writeln(c.title!);
            if (c.content.isNotEmpty) buffer.writeln(c.content);
            for (final item in c.items) {
              buffer.writeln(item);
            }
          }
        case ArticleBlockType.bulletList:
          if (b.data is BulletListBlockData) {
            for (final item in (b.data as BulletListBlockData).items) {
              buffer.writeln(item.text);
            }
          }
        case ArticleBlockType.orderedList:
          if (b.data is OrderedListBlockData) {
            for (final item in (b.data as OrderedListBlockData).items) {
              buffer.writeln(item.text);
            }
          }
        case ArticleBlockType.codeFormula:
          if (b.data is CodeFormulaBlockData) {
            buffer.writeln((b.data as CodeFormulaBlockData).text);
          }
        case ArticleBlockType.image:
          if (b.data is ImageBlockData) {
            final cap = (b.data as ImageBlockData).caption;
            if (cap.isNotEmpty) buffer.writeln(cap);
          }
        case ArticleBlockType.youtubeVideo:
          if (b.data is YouTubeBlockData) {
            final cap = (b.data as YouTubeBlockData).caption;
            if (cap.isNotEmpty) buffer.writeln(cap);
          }
        case ArticleBlockType.billiardDiagram:
          if (b.data is BilliardDiagramBlockData) {
            final cap = (b.data as BilliardDiagramBlockData).caption;
            if (cap.isNotEmpty) buffer.writeln(cap);
          }
        case ArticleBlockType.strokeParameter:
          if (b.data is StrokeParameterBlockData) {
            final sp = (b.data as StrokeParameterBlockData).strokeParameters;
            buffer.writeln(sp.thicknessSummary);
            if (sp.forceText.isNotEmpty) {
              buffer.writeln(sp.forceText);
            } else if (sp.forcePercent != null) {
              buffer.writeln('Lực: ${sp.forcePercent}%');
            }
            if (sp.tipNote.isNotEmpty) {
              buffer.writeln(sp.tipNote);
            }
          }
        case ArticleBlockType.divider:
        case ArticleBlockType.unknown:
          break;
      }
    }
    return buffer.toString().trim();
  }
}
