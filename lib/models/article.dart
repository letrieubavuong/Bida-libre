import 'enums.dart';

/// Bài viết sổ tay (Kĩ thuật, Bộ số, hoặc Hình bi).
/// Model thuần Dart, hỗ trợ serialization JSON để lưu trữ.
class Article {
  final String id;
  final String code; // KT-001, BS-001, HB-001
  final ArticleKind kind;
  final String title;
  final String summary;
  final String primaryGroupId;
  final List<String> tags;
  final Difficulty difficulty;
  final String content;
  final String? source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final PracticeStatus practiceStatus;
  final List<String> relatedArticleIds;

  const Article({
    required this.id,
    required this.code,
    required this.kind,
    required this.title,
    required this.summary,
    required this.primaryGroupId,
    this.tags = const [],
    this.difficulty = Difficulty.unrated,
    this.content = '',
    this.source,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.practiceStatus = PracticeStatus.notStarted,
    this.relatedArticleIds = const [],
  });

  Article copyWith({
    String? id,
    String? code,
    ArticleKind? kind,
    String? title,
    String? summary,
    String? primaryGroupId,
    List<String>? tags,
    Difficulty? difficulty,
    String? content,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    PracticeStatus? practiceStatus,
    List<String>? relatedArticleIds,
  }) {
    return Article(
      id: id ?? this.id,
      code: code ?? this.code,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      primaryGroupId: primaryGroupId ?? this.primaryGroupId,
      tags: tags ?? this.tags,
      difficulty: difficulty ?? this.difficulty,
      content: content ?? this.content,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      practiceStatus: practiceStatus ?? this.practiceStatus,
      relatedArticleIds: relatedArticleIds ?? this.relatedArticleIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'kind': kind.storageKey,
      'title': title,
      'summary': summary,
      'primaryGroupId': primaryGroupId,
      'tags': tags,
      'difficulty': difficulty.storageKey,
      'content': content,
      if (source != null) 'source': source,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isFavorite': isFavorite,
      'practiceStatus': practiceStatus.storageKey,
      'relatedArticleIds': relatedArticleIds,
    };
  }

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      id: json['id'] as String,
      code: json['code'] as String,
      kind: ArticleKind.fromKey(json['kind'] as String),
      title: json['title'] as String,
      summary: (json['summary'] as String?) ?? '',
      primaryGroupId: json['primaryGroupId'] as String,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      difficulty: Difficulty.fromKey(json['difficulty'] as String? ?? 'unrated'),
      content: (json['content'] as String?) ?? '',
      source: json['source'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isFavorite: (json['isFavorite'] as bool?) ?? false,
      practiceStatus: PracticeStatus.fromKey(json['practiceStatus'] as String? ?? 'not_started'),
      relatedArticleIds: (json['relatedArticleIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    );
  }
}
