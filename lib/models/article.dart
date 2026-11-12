import 'diagram_scene.dart';
import 'enums.dart';
import 'stroke_parameters.dart';

/// Một sơ đồ gắn theo thứ tự trong bài viết.
class ArticleDiagram {
  final String id;
  final String articleId;
  final int sortOrder;
  final String caption;
  final DiagramScene scene;

  const ArticleDiagram({
    required this.id,
    required this.articleId,
    this.sortOrder = 0,
    this.caption = '',
    required this.scene,
  });

  ArticleDiagram copyWith({
    String? id,
    String? articleId,
    int? sortOrder,
    String? caption,
    DiagramScene? scene,
  }) {
    return ArticleDiagram(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      sortOrder: sortOrder ?? this.sortOrder,
      caption: caption ?? this.caption,
      scene: scene ?? this.scene,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'articleId': articleId,
        'sortOrder': sortOrder,
        'caption': caption,
        'scene': scene.toJson(),
      };

  factory ArticleDiagram.fromJson(Map<String, dynamic> json) {
    final sceneJson = json['scene'] as Map<String, dynamic>;
    return ArticleDiagram(
      id: json['id'] as String,
      articleId: json['articleId'] as String,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      caption: (json['caption'] as String?) ?? '',
      scene: DiagramScene.fromJson(sceneJson),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArticleDiagram &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          articleId == other.articleId &&
          sortOrder == other.sortOrder &&
          caption == other.caption &&
          scene == other.scene;

  @override
  int get hashCode => Object.hash(id, articleId, sortOrder, caption, scene);
}

/// Bài viết sổ tay (Kĩ thuật, Bộ số, hoặc Hình bi).
/// Model thuần Dart, hỗ trợ serialization JSON & SQLite, kèm các danh sách bất biến.
class Article {
  final String id;
  final String code; // KT-001, BS-001, HB-001
  final ArticleKind kind;
  final String title;
  final String summary;
  final String primaryGroupId;
  final List<String> tags;
  final Difficulty difficulty;
  final String goal;
  final String content;
  final List<String> steps;
  final String commonMistakes;
  final String? source;
  final String? author;
  final String? sourcePage;
  final bool isDraft;
  final StrokeParameters strokeParameters;
  final List<ArticleDiagram> diagrams;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final PracticeStatus practiceStatus;
  final List<String> relatedArticleIds;

  Article({
    required this.id,
    required this.code,
    required this.kind,
    required this.title,
    this.summary = '',
    required this.primaryGroupId,
    List<String> tags = const [],
    this.difficulty = Difficulty.unrated,
    this.goal = '',
    this.content = '',
    List<String> steps = const [],
    this.commonMistakes = '',
    this.source,
    this.author,
    this.sourcePage,
    this.isDraft = false,
    this.strokeParameters = const StrokeParameters.defaults(),
    List<ArticleDiagram> diagrams = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.practiceStatus = PracticeStatus.notStarted,
    List<String> relatedArticleIds = const [],
  })  : tags = List<String>.unmodifiable(tags),
        steps = List<String>.unmodifiable(steps),
        diagrams = List<ArticleDiagram>.unmodifiable(diagrams),
        relatedArticleIds = List<String>.unmodifiable(relatedArticleIds);

  /// Kiểm tra dữ liệu tối thiểu để lưu bài (nháp thiếu nội dung vẫn hợp lệ nếu có tiêu đề và nhóm).
  String? validateMinimalForSave() {
    if (title.trim().isEmpty) {
      return 'Vui lòng nhập tên bài viết trước khi lưu.';
    }
    if (primaryGroupId.trim().isEmpty) {
      return 'Vui lòng chọn nhóm chính cho bài viết.';
    }
    return null;
  }

  Article copyWith({
    String? id,
    String? code,
    ArticleKind? kind,
    String? title,
    String? summary,
    String? primaryGroupId,
    List<String>? tags,
    Difficulty? difficulty,
    String? goal,
    String? content,
    List<String>? steps,
    String? commonMistakes,
    String? source,
    bool clearSource = false,
    String? author,
    bool clearAuthor = false,
    String? sourcePage,
    bool clearSourcePage = false,
    bool? isDraft,
    StrokeParameters? strokeParameters,
    List<ArticleDiagram>? diagrams,
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
      goal: goal ?? this.goal,
      content: content ?? this.content,
      steps: steps ?? this.steps,
      commonMistakes: commonMistakes ?? this.commonMistakes,
      source: clearSource ? null : (source ?? this.source),
      author: clearAuthor ? null : (author ?? this.author),
      sourcePage: clearSourcePage ? null : (sourcePage ?? this.sourcePage),
      isDraft: isDraft ?? this.isDraft,
      strokeParameters: strokeParameters ?? this.strokeParameters,
      diagrams: diagrams ?? this.diagrams,
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
      'goal': goal,
      'content': content,
      'steps': steps,
      'commonMistakes': commonMistakes,
      if (source != null) 'source': source,
      if (author != null) 'author': author,
      if (sourcePage != null) 'sourcePage': sourcePage,
      'isDraft': isDraft,
      'strokeParameters': strokeParameters.toJson(),
      'diagrams': diagrams.map((d) => d.toJson()).toList(),
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
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      difficulty: Difficulty.fromKey(json['difficulty'] as String? ?? 'unrated'),
      goal: (json['goal'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      steps:
          (json['steps'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      commonMistakes: (json['commonMistakes'] as String?) ?? '',
      source: json['source'] as String?,
      author: json['author'] as String?,
      sourcePage: json['sourcePage'] as String?,
      isDraft: (json['isDraft'] as bool?) ?? false,
      strokeParameters: json['strokeParameters'] is Map<String, dynamic>
          ? StrokeParameters.fromJson(
              json['strokeParameters'] as Map<String, dynamic>,
            )
          : const StrokeParameters.defaults(),
      diagrams: (json['diagrams'] as List<dynamic>?)
              ?.map((e) => ArticleDiagram.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isFavorite: (json['isFavorite'] as bool?) ?? false,
      practiceStatus: PracticeStatus.fromKey(
        json['practiceStatus'] as String? ?? 'not_started',
      ),
      relatedArticleIds: (json['relatedArticleIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Article) return false;
    if (id != other.id ||
        code != other.code ||
        kind != other.kind ||
        title != other.title ||
        summary != other.summary ||
        primaryGroupId != other.primaryGroupId ||
        difficulty != other.difficulty ||
        goal != other.goal ||
        content != other.content ||
        commonMistakes != other.commonMistakes ||
        source != other.source ||
        author != other.author ||
        sourcePage != other.sourcePage ||
        isDraft != other.isDraft ||
        strokeParameters != other.strokeParameters ||
        createdAt != other.createdAt ||
        updatedAt != other.updatedAt ||
        isFavorite != other.isFavorite ||
        practiceStatus != other.practiceStatus ||
        tags.length != other.tags.length ||
        steps.length != other.steps.length ||
        diagrams.length != other.diagrams.length ||
        relatedArticleIds.length != other.relatedArticleIds.length) {
      return false;
    }
    for (var i = 0; i < tags.length; i++) {
      if (tags[i] != other.tags[i]) return false;
    }
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] != other.steps[i]) return false;
    }
    for (var i = 0; i < diagrams.length; i++) {
      if (diagrams[i] != other.diagrams[i]) return false;
    }
    for (var i = 0; i < relatedArticleIds.length; i++) {
      if (relatedArticleIds[i] != other.relatedArticleIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        code,
        kind,
        title,
        summary,
        primaryGroupId,
        difficulty,
        goal,
        content,
        commonMistakes,
        source,
        author,
        sourcePage,
        isDraft,
        strokeParameters,
        createdAt,
        updatedAt,
        isFavorite,
        practiceStatus,
        Object.hashAll(tags),
        Object.hashAll(steps),
        Object.hashAll(diagrams),
        Object.hashAll(relatedArticleIds),
      ]);
}
