import 'enums.dart';

/// Nhóm chính biên tập cho từng mục (Kĩ thuật, Bộ số, Hình bi).
class EditorialGroup {
  final String id;
  final ArticleKind kind;
  final String name;
  final String description;
  final int sortOrder;

  const EditorialGroup({
    required this.id,
    required this.kind,
    required this.name,
    this.description = '',
    this.sortOrder = 0,
  });

  EditorialGroup copyWith({
    String? id,
    ArticleKind? kind,
    String? name,
    String? description,
    int? sortOrder,
  }) {
    return EditorialGroup(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      description: description ?? this.description,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorialGroup &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          name == other.name &&
          description == other.description &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(id, kind, name, description, sortOrder);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.storageKey,
        'name': name,
        'description': description,
        'sortOrder': sortOrder,
      };

  factory EditorialGroup.fromJson(Map<String, dynamic> json) {
    return EditorialGroup(
      id: json['id'] as String,
      kind: ArticleKind.fromKey(json['kind'] as String),
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Thẻ độc lập kèm danh sách alias để hỗ trợ tìm kiếm có/không dấu hoặc đồng nghĩa biên tập.
class Tag {
  final String id;
  final String name;
  final List<String> aliases;

  const Tag({
    required this.id,
    required this.name,
    this.aliases = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aliases': aliases,
      };

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String,
      name: json['name'] as String,
      aliases:
          (json['aliases'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
    );
  }
}

/// Bộ sưu tập: lưu danh sách ID bài có thứ tự thủ công, không nhân bản nội dung bài.
class Collection {
  final String id;
  final String name;
  final List<String> orderedArticleIds;

  const Collection({
    required this.id,
    required this.name,
    this.orderedArticleIds = const [],
  });

  Collection copyWith({
    String? id,
    String? name,
    List<String>? orderedArticleIds,
  }) {
    return Collection(
      id: id ?? this.id,
      name: name ?? this.name,
      orderedArticleIds: orderedArticleIds ?? this.orderedArticleIds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Collection ||
        id != other.id ||
        name != other.name ||
        orderedArticleIds.length != other.orderedArticleIds.length) {
      return false;
    }
    for (var i = 0; i < orderedArticleIds.length; i++) {
      if (orderedArticleIds[i] != other.orderedArticleIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAll(orderedArticleIds));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'orderedArticleIds': orderedArticleIds,
      };

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: json['id'] as String,
      name: json['name'] as String,
      orderedArticleIds: (json['orderedArticleIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }
}

/// Nhật ký một buổi/lần tập luyện cho một bài viết.
class PracticeEntry {
  final String id;
  final String articleId;
  final DateTime date;
  final int? attempts;
  final int? successes;
  final String note;

  PracticeEntry({
    required this.id,
    required this.articleId,
    required this.date,
    this.attempts,
    this.successes,
    this.note = '',
  }) {
    if (attempts != null && attempts! < 0) {
      throw ArgumentError('Số lần thử không được âm.');
    }
    if (successes != null && successes! < 0) {
      throw ArgumentError('Số lần đạt không được âm.');
    }
    if (attempts != null && successes != null && successes! > attempts!) {
      throw ArgumentError('Số lần đạt không được lớn hơn số lần thử.');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'articleId': articleId,
        'date': date.toIso8601String(),
        if (attempts != null) 'attempts': attempts,
        if (successes != null) 'successes': successes,
        'note': note,
      };

  factory PracticeEntry.fromJson(Map<String, dynamic> json) {
    return PracticeEntry(
      id: json['id'] as String,
      articleId: json['articleId'] as String,
      date: DateTime.parse(json['date'] as String),
      attempts: (json['attempts'] as num?)?.toInt(),
      successes: (json['successes'] as num?)?.toInt(),
      note: (json['note'] as String?) ?? '',
    );
  }
}

/// Tệp đính kèm (ảnh nguồn) được sao chép vào vùng dữ liệu ứng dụng.
class AssetRef {
  final String id;
  final String relativePath;
  final String mimeType;
  final List<String> articleIds;

  const AssetRef({
    required this.id,
    required this.relativePath,
    required this.mimeType,
    this.articleIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'relativePath': relativePath,
        'mimeType': mimeType,
        'articleIds': articleIds,
      };

  factory AssetRef.fromJson(Map<String, dynamic> json) {
    return AssetRef(
      id: json['id'] as String,
      relativePath: json['relativePath'] as String,
      mimeType: json['mimeType'] as String,
      articleIds: (json['articleIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }
}

/// Dữ liệu nhóm biên tập khởi đầu theo đặc tả mục 4.1 và 4.3.
class DefaultEditorialGroups {
  const DefaultEditorialGroups._();

  static const List<EditorialGroup> techniqueGroups = [
    EditorialGroup(
      id: 'tech_foundation',
      kind: ArticleKind.technique,
      name: 'Nền tảng và kiểm soát cơ',
      sortOrder: 1,
    ),
    EditorialGroup(
      id: 'tech_draw',
      kind: ArticleKind.technique,
      name: 'Trô / kéo',
      sortOrder: 2,
    ),
    EditorialGroup(
      id: 'tech_follow',
      kind: ArticleKind.technique,
      name: 'Cu-lê / đẩy tới',
      sortOrder: 3,
    ),
    EditorialGroup(
      id: 'tech_amorti',
      kind: ArticleKind.technique,
      name: 'Đánh chết bi / amorti',
      sortOrder: 4,
    ),
    EditorialGroup(
      id: 'tech_masse_special',
      kind: ArticleKind.technique,
      name: 'Giò gà và kỹ thuật đặc thù',
      sortOrder: 5,
    ),
    EditorialGroup(
      id: 'tech_rail_control',
      kind: ArticleKind.technique,
      name: 'Kiểm soát bi qua băng',
      sortOrder: 6,
    ),
  ];

  static const List<EditorialGroup> systemGroups = [
    EditorialGroup(
      id: 'sys_unclassified',
      kind: ArticleKind.system,
      name: 'Chưa phân nhóm',
      description: 'Họ phương pháp bộ số do người dùng đặt',
      sortOrder: 1,
    ),
  ];

  static const List<EditorialGroup> positionGroups = [
    EditorialGroup(
      id: 'corner',
      kind: ArticleKind.position,
      name: 'Gom góc',
      description: 'Thế gom liên quan khu vực góc',
      sortOrder: 1,
    ),
    EditorialGroup(
      id: 'long_rail',
      kind: ArticleKind.position,
      name: 'Gom dọc băng dài',
      description: 'Thế gom triển khai gần băng dài',
      sortOrder: 2,
    ),
    EditorialGroup(
      id: 'short_rail',
      kind: ArticleKind.position,
      name: 'Gom gần băng ngắn',
      description: 'Thế gom triển khai gần băng ngắn',
      sortOrder: 3,
    ),
    EditorialGroup(
      id: 'center',
      kind: ArticleKind.position,
      name: 'Gom giữa bàn',
      description: 'Thế gom triển khai ở vùng giữa bàn',
      sortOrder: 4,
    ),
    EditorialGroup(
      id: 'return',
      kind: ArticleKind.position,
      name: 'Khứ hồi / kéo về',
      description: 'Điểm nổi bật là đưa một bi đi rồi trở về',
      sortOrder: 5,
    ),
    EditorialGroup(
      id: 'series',
      kind: ArticleKind.position,
      name: 'Seri / dẫn bi',
      description: 'Thế giữ và nối tiếp chuỗi dẫn bi',
      sortOrder: 6,
    ),
    EditorialGroup(
      id: 'special',
      kind: ArticleKind.position,
      name: 'Thế đặc biệt',
      description: 'Các bài cần nhóm riêng',
      sortOrder: 7,
    ),
    EditorialGroup(
      id: 'unclassified',
      kind: ArticleKind.position,
      name: 'Chưa phân loại',
      description: 'Nơi tiếp nhận bài mới',
      sortOrder: 8,
    ),
  ];

  static const String techniqueUnclassifiedId = 'tech_unclassified';
  static const String systemUnclassifiedId = 'sys_unclassified';
  static const String positionUnclassifiedId = 'unclassified';

  static String unclassifiedIdFor(ArticleKind kind) {
    switch (kind) {
      case ArticleKind.technique:
        return techniqueUnclassifiedId;
      case ArticleKind.system:
        return systemUnclassifiedId;
      case ArticleKind.position:
        return positionUnclassifiedId;
    }
  }

  static bool isUnclassifiedGroupId(String groupId) {
    return groupId == techniqueUnclassifiedId ||
        groupId == systemUnclassifiedId ||
        groupId == positionUnclassifiedId;
  }

  static EditorialGroup unclassifiedGroupFor(ArticleKind kind) {
    switch (kind) {
      case ArticleKind.technique:
        return const EditorialGroup(
          id: techniqueUnclassifiedId,
          kind: ArticleKind.technique,
          name: 'Chưa phân loại',
          description: 'Nơi tiếp nhận bài kĩ thuật chưa phân loại',
          sortOrder: 99,
        );
      case ArticleKind.system:
        return systemGroups.first;
      case ArticleKind.position:
        return positionGroups.last;
    }
  }

  static List<EditorialGroup> forKind(ArticleKind kind) {
    switch (kind) {
      case ArticleKind.technique:
        return techniqueGroups;
      case ArticleKind.system:
        return systemGroups;
      case ArticleKind.position:
        return positionGroups;
    }
  }
}

