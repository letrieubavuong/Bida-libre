import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'article_block.dart';

/// Mục trong Mục lục (Table of Contents) tự động sinh từ các khối Heading.
@immutable
class TableOfContentsEntry {
  final String blockId;
  final int level;
  final String title;
  final String? numbering; // e.g. "1.", "1.2."

  const TableOfContentsEntry({
    required this.blockId,
    required this.level,
    required this.title,
    this.numbering,
  });

  String get fullTitle => numbering != null ? '$numbering $title' : title;
}

/// Mô hình tài liệu linh hoạt dạng khối của bài viết (Phase 7).
@immutable
class ArticleDocument {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final List<ArticleBlock> blocks;

  const ArticleDocument({
    this.schemaVersion = currentSchemaVersion,
    this.blocks = const [],
  });

  bool get isEmpty => blocks.isEmpty;
  bool get isNotEmpty => blocks.isNotEmpty;

  ArticleDocument copyWith({
    int? schemaVersion,
    List<ArticleBlock>? blocks,
  }) {
    return ArticleDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      blocks: blocks ?? this.blocks,
    );
  }

  /// Trích xuất danh sách Mục lục (TOC) tự động từ các khối Heading.
  List<TableOfContentsEntry> generateTableOfContents() {
    final numbers = computeHeadingNumbers();
    final result = <TableOfContentsEntry>[];

    for (final block in blocks) {
      if (block.type == ArticleBlockType.heading &&
          block.data is HeadingBlockData) {
        final heading = block.data as HeadingBlockData;
        final numbering = numbers[block.id];
        result.add(
          TableOfContentsEntry(
            blockId: block.id,
            level: heading.level,
            title: heading.text,
            numbering: numbering,
          ),
        );
      }
    }
    return result;
  }

  /// Tính toán số đề mục đa cấp tự động (Section 1, Subsection 1.1, Subsubsection 1.1.1...).
  Map<String, String> computeHeadingNumbers() {
    final result = <String, String>{};
    final counters = <int>[0, 0, 0, 0, 0, 0]; // Cấp 1..6

    for (final block in blocks) {
      if (block.type == ArticleBlockType.heading &&
          block.data is HeadingBlockData) {
        final heading = block.data as HeadingBlockData;
        if (!heading.isNumbered) continue;

        final levelIndex = (heading.level - 1).clamp(0, 5);
        counters[levelIndex]++;
        // Đặt lại các cấp con sâu hơn về 0
        for (int i = levelIndex + 1; i < counters.length; i++) {
          counters[i] = 0;
        }

        // Tạo chuỗi số thứ tự: 1. hoặc 1.2. hoặc 1.2.1.
        final parts = <int>[];
        for (int i = 0; i <= levelIndex; i++) {
          parts.add(counters[i] == 0 ? 1 : counters[i]);
        }
        final numStr = '${parts.join('.')}.';
        result[block.id] = numStr;
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory ArticleDocument.fromJson(Map<String, dynamic> json) {
    final schema = (json['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion;
    final rawBlocks = (json['blocks'] as List<dynamic>?) ?? [];
    return ArticleDocument(
      schemaVersion: schema,
      blocks: rawBlocks
          .whereType<Map<String, dynamic>>()
          .map(ArticleBlock.fromJson)
          .toList(growable: false),
    );
  }

  factory ArticleDocument.fromJsonString(String source) {
    if (source.trim().isEmpty) {
      return const ArticleDocument();
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return ArticleDocument.fromJson(decoded);
      }
    } catch (_) {}
    return const ArticleDocument();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArticleDocument &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          listEquals(blocks, other.blocks);

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(blocks));
}
