import 'article_document.dart';
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

/// Ảnh nguồn đính kèm của bài viết (tách biệt với scene vector, lưu bằng assetId & relativePath).
class ArticleImageAttachment {
  final String id;
  final String articleId;
  final String assetId;
  final String relativePath;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final String caption;
  final int sortOrder;

  const ArticleImageAttachment({
    required this.id,
    this.articleId = '',
    required this.assetId,
    required this.relativePath,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.caption = '',
    this.sortOrder = 0,
  });

  ArticleImageAttachment copyWith({
    String? id,
    String? articleId,
    String? assetId,
    String? relativePath,
    String? originalName,
    String? mimeType,
    int? sizeBytes,
    int? width,
    int? height,
    String? caption,
    int? sortOrder,
  }) {
    return ArticleImageAttachment(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      assetId: assetId ?? this.assetId,
      relativePath: relativePath ?? this.relativePath,
      originalName: originalName ?? this.originalName,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      caption: caption ?? this.caption,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'articleId': articleId,
        'assetId': assetId,
        'relativePath': relativePath,
        'originalName': originalName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        'caption': caption,
        'sortOrder': sortOrder,
      };

  factory ArticleImageAttachment.fromJson(Map<String, dynamic> json) {
    return ArticleImageAttachment(
      id: json['id'] as String,
      articleId: (json['articleId'] as String?) ?? '',
      assetId: json['assetId'] as String,
      relativePath: json['relativePath'] as String,
      originalName: (json['originalName'] as String?) ?? 'image',
      mimeType: (json['mimeType'] as String?) ?? 'image/jpeg',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      caption: (json['caption'] as String?) ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArticleImageAttachment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          articleId == other.articleId &&
          assetId == other.assetId &&
          relativePath == other.relativePath &&
          originalName == other.originalName &&
          mimeType == other.mimeType &&
          sizeBytes == other.sizeBytes &&
          width == other.width &&
          height == other.height &&
          caption == other.caption &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(
        id,
        articleId,
        assetId,
        relativePath,
        originalName,
        mimeType,
        sizeBytes,
        width,
        height,
        caption,
        sortOrder,
      );
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
  final String? sourceUrl;
  final bool isDraft;
  final StrokeParameters strokeParameters;
  final List<ArticleDiagram> diagrams;
  final List<ArticleImageAttachment> images;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final PracticeStatus practiceStatus;
  final List<String> relatedArticleIds;
  final ArticleDocument? document;

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
    this.sourceUrl,
    this.isDraft = false,
    this.strokeParameters = const StrokeParameters.defaults(),
    List<ArticleDiagram> diagrams = const [],
    List<ArticleImageAttachment> images = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.practiceStatus = PracticeStatus.notStarted,
    List<String> relatedArticleIds = const [],
    this.document,
  })  : tags = List<String>.unmodifiable(tags),
        steps = List<String>.unmodifiable(steps),
        diagrams = List<ArticleDiagram>.unmodifiable(diagrams),
        images = List<ArticleImageAttachment>.unmodifiable(images),
        relatedArticleIds = List<String>.unmodifiable(relatedArticleIds);

  static bool isValidOptionalHttpUrl(String? url) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return true;
    final uri = Uri.tryParse(trimmed);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Kiểm tra dữ liệu tối thiểu để lưu bài (nháp thiếu nội dung vẫn hợp lệ nếu có tiêu đề và nhóm).
  String? validateMinimalForSave() {
    if (title.trim().isEmpty) {
      return 'Vui lòng nhập tên bài viết trước khi lưu.';
    }
    if (primaryGroupId.trim().isEmpty) {
      return 'Vui lòng chọn nhóm chính cho bài viết.';
    }
    if (!isValidOptionalHttpUrl(sourceUrl)) {
      return 'URL nguồn phải bắt đầu bằng http:// hoặc https:// hợp lệ.';
    }
    final strokeErr = strokeParameters.validate();
    if (strokeErr != null) {
      return strokeErr;
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
    String? sourceUrl,
    bool clearSourceUrl = false,
    bool? isDraft,
    StrokeParameters? strokeParameters,
    List<ArticleDiagram>? diagrams,
    List<ArticleImageAttachment>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    PracticeStatus? practiceStatus,
    List<String>? relatedArticleIds,
    ArticleDocument? document,
    bool clearDocument = false,
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
      sourceUrl: clearSourceUrl ? null : (sourceUrl ?? this.sourceUrl),
      isDraft: isDraft ?? this.isDraft,
      strokeParameters: strokeParameters ?? this.strokeParameters,
      diagrams: diagrams ?? this.diagrams,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      practiceStatus: practiceStatus ?? this.practiceStatus,
      relatedArticleIds: relatedArticleIds ?? this.relatedArticleIds,
      document: clearDocument ? null : (document ?? this.document),
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
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
      'isDraft': isDraft,
      'strokeParameters': strokeParameters.toJson(),
      'diagrams': diagrams.map((d) => d.toJson()).toList(),
      'images': images.map((img) => img.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isFavorite': isFavorite,
      'practiceStatus': practiceStatus.storageKey,
      'relatedArticleIds': relatedArticleIds,
      if (document != null) 'document': document!.toJson(),
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
      sourceUrl: json['sourceUrl'] as String?,
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
      images: (json['images'] as List<dynamic>?)
              ?.map(
                (e) =>
                    ArticleImageAttachment.fromJson(e as Map<String, dynamic>),
              )
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
      document: json['document'] is Map<String, dynamic>
          ? ArticleDocument.fromJson(json['document'] as Map<String, dynamic>)
          : null,
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
        sourceUrl != other.sourceUrl ||
        isDraft != other.isDraft ||
        strokeParameters != other.strokeParameters ||
        createdAt != other.createdAt ||
        updatedAt != other.updatedAt ||
        isFavorite != other.isFavorite ||
        practiceStatus != other.practiceStatus ||
        tags.length != other.tags.length ||
        steps.length != other.steps.length ||
        diagrams.length != other.diagrams.length ||
        images.length != other.images.length ||
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
    for (var i = 0; i < images.length; i++) {
      if (images[i] != other.images[i]) return false;
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
        sourceUrl,
        isDraft,
        strokeParameters,
        createdAt,
        updatedAt,
        isFavorite,
        practiceStatus,
        Object.hashAll(tags),
        Object.hashAll(steps),
        Object.hashAll(diagrams),
        Object.hashAll(images),
        Object.hashAll(relatedArticleIds),
      ]);
}
