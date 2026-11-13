import 'package:flutter/foundation.dart';

import 'stroke_parameters.dart';

/// Các loại khối nội dung trong tài liệu bài viết (Phase 7).
enum ArticleBlockType {
  heading,
  paragraph,
  callout,
  bulletList,
  orderedList,
  image,
  youtubeVideo,
  billiardDiagram,
  strokeParameter,
  divider,
  codeFormula,
  unknown;

  String get code {
    switch (this) {
      case ArticleBlockType.heading:
        return 'heading';
      case ArticleBlockType.paragraph:
        return 'paragraph';
      case ArticleBlockType.callout:
        return 'callout';
      case ArticleBlockType.bulletList:
        return 'bulletList';
      case ArticleBlockType.orderedList:
        return 'orderedList';
      case ArticleBlockType.image:
        return 'image';
      case ArticleBlockType.youtubeVideo:
        return 'youtubeVideo';
      case ArticleBlockType.billiardDiagram:
        return 'billiardDiagram';
      case ArticleBlockType.strokeParameter:
        return 'strokeParameter';
      case ArticleBlockType.divider:
        return 'divider';
      case ArticleBlockType.codeFormula:
        return 'codeFormula';
      case ArticleBlockType.unknown:
        return 'unknown';
    }
  }

  static ArticleBlockType fromCode(String code) {
    for (final t in ArticleBlockType.values) {
      if (t.code == code) return t;
    }
    return ArticleBlockType.unknown;
  }
}

/// Phong cách định dạng nội tuyến cho đoạn văn bản.
enum InlineStyle {
  bold,
  italic,
  underline,
  link;

  String get code => name;

  static InlineStyle? fromCode(String code) {
    for (final s in InlineStyle.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Dải định dạng nội tuyến áp dụng cho một đoạn ký tự [start..end).
@immutable
class InlineSpanStyle {
  final int start;
  final int end;
  final Set<InlineStyle> styles;
  final String? url;

  const InlineSpanStyle({
    required this.start,
    required this.end,
    required this.styles,
    this.url,
  });

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'styles': styles.map((s) => s.code).toList(),
        if (url != null) 'url': url,
      };

  factory InlineSpanStyle.fromJson(Map<String, dynamic> json) {
    final stylesList = (json['styles'] as List<dynamic>?) ?? [];
    final set = <InlineStyle>{};
    for (final item in stylesList) {
      final s = InlineStyle.fromCode(item.toString());
      if (s != null) set.add(s);
    }
    return InlineSpanStyle(
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      styles: set,
      url: json['url'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineSpanStyle &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          setEquals(styles, other.styles) &&
          url == other.url;

  @override
  int get hashCode => Object.hash(start, end, Object.hashAll(styles), url);
}

/// Preset cho khung ghi chú kiểu tcolorbox.
enum CalloutPreset {
  note,     // Ghi chú (xanh dương)
  warning,  // Chú ý / Cảnh báo (cam / đỏ nhẹ)
  example,  // Ví dụ (xanh lá)
  tip,      // Mẹo / Gợi ý (tím / ngọc)
  mistake;  // Lỗi thường gặp (đỏ)

  String get code => name;

  String get defaultLabel {
    switch (this) {
      case CalloutPreset.note:
        return 'Ghi chú';
      case CalloutPreset.warning:
        return 'Chú ý';
      case CalloutPreset.example:
        return 'Ví dụ';
      case CalloutPreset.tip:
        return 'Mẹo thực chiến';
      case CalloutPreset.mistake:
        return 'Lỗi thường gặp';
    }
  }

  static CalloutPreset fromCode(String code) {
    for (final p in CalloutPreset.values) {
      if (p.code == code) return p;
    }
    return CalloutPreset.note;
  }
}

/// Kiểu đánh số danh sách có thứ tự.
enum NumberingStyle {
  number, // 1, 2, 3...
  letter; // a, b, c...

  String get code => name;

  static NumberingStyle fromCode(String code) {
    for (final s in NumberingStyle.values) {
      if (s.code == code) return s;
    }
    return NumberingStyle.number;
  }
}

/// Một mục trong danh sách có cấp độ lồng nhau.
@immutable
class ListItemData {
  final String text;
  final int level; // 0: cấp ngoài cùng, 1: cấp con, 2: cấp cháu...

  const ListItemData({
    required this.text,
    this.level = 0,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'level': level,
      };

  factory ListItemData.fromJson(Map<String, dynamic> json) => ListItemData(
        text: json['text'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListItemData &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          level == other.level;

  @override
  int get hashCode => Object.hash(text, level);
}

/// Kích cỡ hiển thị ảnh trong bài viết.
enum ImageDisplaySize {
  small,    // Nhỏ (khoảng 35% chiều rộng)
  medium,   // Vừa (khoảng 65% chiều rộng)
  large,    // Lớn (100% chiều rộng)
  original; // Tự nhiên theo kích cỡ ảnh

  String get code => name;

  static ImageDisplaySize fromCode(String code) {
    for (final s in ImageDisplaySize.values) {
      if (s.code == code) return s;
    }
    return ImageDisplaySize.large;
  }
}

/// Lớp cơ sở cho dữ liệu của một khối.
abstract class ArticleBlockData {
  const ArticleBlockData();

  Map<String, dynamic> toJson();
}

/// 1. Khối Đề mục (Heading) cấp 1..6.
@immutable
class HeadingBlockData extends ArticleBlockData {
  final int level; // 1: Section, 2: Subsection, 3: Subsubsection, 4..6: tiểu mục nhỏ
  final String text;
  final bool isNumbered;

  const HeadingBlockData({
    this.level = 1,
    required this.text,
    this.isNumbered = true,
  });

  @override
  Map<String, dynamic> toJson() => {
        'level': level.clamp(1, 6),
        'text': text,
        'isNumbered': isNumbered,
      };

  factory HeadingBlockData.fromJson(Map<String, dynamic> json) => HeadingBlockData(
        level: ((json['level'] as num?)?.toInt() ?? 1).clamp(1, 6),
        text: json['text'] as String? ?? '',
        isNumbered: json['isNumbered'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadingBlockData &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          text == other.text &&
          isNumbered == other.isNumbered;

  @override
  int get hashCode => Object.hash(level, text, isNumbered);
}

/// 2. Khối Đoạn văn (Paragraph) hỗ trợ rich text nội tuyến.
@immutable
class ParagraphBlockData extends ArticleBlockData {
  final String text;
  final List<InlineSpanStyle> spans;

  const ParagraphBlockData({
    required this.text,
    this.spans = const [],
  });

  @override
  Map<String, dynamic> toJson() => {
        'text': text,
        'spans': spans.map((s) => s.toJson()).toList(),
      };

  factory ParagraphBlockData.fromJson(Map<String, dynamic> json) {
    final rawSpans = (json['spans'] as List<dynamic>?) ?? [];
    return ParagraphBlockData(
      text: json['text'] as String? ?? '',
      spans: rawSpans
          .whereType<Map<String, dynamic>>()
          .map(InlineSpanStyle.fromJson)
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParagraphBlockData &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          listEquals(spans, other.spans);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(spans));
}

/// 3. Khối Ghi chú kiểu tcolorbox.
@immutable
class CalloutBlockData extends ArticleBlockData {
  final CalloutPreset preset;
  final String? title;
  final String content;
  final List<String> items;

  const CalloutBlockData({
    this.preset = CalloutPreset.note,
    this.title,
    required this.content,
    this.items = const [],
  });

  @override
  Map<String, dynamic> toJson() => {
        'preset': preset.code,
        if (title != null) 'title': title,
        'content': content,
        'items': items,
      };

  factory CalloutBlockData.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>?) ?? [];
    return CalloutBlockData(
      preset: CalloutPreset.fromCode(json['preset'] as String? ?? ''),
      title: json['title'] as String?,
      content: json['content'] as String? ?? '',
      items: rawItems.map((e) => e.toString()).toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalloutBlockData &&
          runtimeType == other.runtimeType &&
          preset == other.preset &&
          title == other.title &&
          content == other.content &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(preset, title, content, Object.hashAll(items));
}

/// 4. Khối Danh sách không thứ tự (itemize).
@immutable
class BulletListBlockData extends ArticleBlockData {
  final List<ListItemData> items;

  const BulletListBlockData({
    required this.items,
  });

  @override
  Map<String, dynamic> toJson() => {
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory BulletListBlockData.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>?) ?? [];
    return BulletListBlockData(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(ListItemData.fromJson)
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BulletListBlockData &&
          runtimeType == other.runtimeType &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hashAll(items);
}

/// 5. Khối Danh sách có thứ tự (enumerate).
@immutable
class OrderedListBlockData extends ArticleBlockData {
  final NumberingStyle numberingStyle;
  final List<ListItemData> items;

  const OrderedListBlockData({
    this.numberingStyle = NumberingStyle.number,
    required this.items,
  });

  @override
  Map<String, dynamic> toJson() => {
        'numberingStyle': numberingStyle.code,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory OrderedListBlockData.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List<dynamic>?) ?? [];
    return OrderedListBlockData(
      numberingStyle:
          NumberingStyle.fromCode(json['numberingStyle'] as String? ?? ''),
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(ListItemData.fromJson)
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderedListBlockData &&
          runtimeType == other.runtimeType &&
          numberingStyle == other.numberingStyle &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(numberingStyle, Object.hashAll(items));
}

/// 6. Khối Ảnh nguồn đính kèm (tham chiếu bằng assetId).
@immutable
class ImageBlockData extends ArticleBlockData {
  final String assetId;
  final String caption;
  final ImageDisplaySize displaySize;

  const ImageBlockData({
    required this.assetId,
    this.caption = '',
    this.displaySize = ImageDisplaySize.large,
  });

  @override
  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'caption': caption,
        'displaySize': displaySize.code,
      };

  factory ImageBlockData.fromJson(Map<String, dynamic> json) => ImageBlockData(
        assetId: json['assetId'] as String? ?? '',
        caption: json['caption'] as String? ?? '',
        displaySize:
            ImageDisplaySize.fromCode(json['displaySize'] as String? ?? ''),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageBlockData &&
          runtimeType == other.runtimeType &&
          assetId == other.assetId &&
          caption == other.caption &&
          displaySize == other.displaySize;

  @override
  int get hashCode => Object.hash(assetId, caption, displaySize);
}

/// 7. Khối Video YouTube.
@immutable
class YouTubeBlockData extends ArticleBlockData {
  final String url;
  final String videoId;
  final String caption;

  const YouTubeBlockData({
    required this.url,
    required this.videoId,
    this.caption = '',
  });

  /// Nhận dạng và trích xuất YouTube Video ID từ nhiều định dạng URL phổ biến:
  /// - https://www.youtube.com/watch?v=VIDEO_ID
  /// - https://youtu.be/VIDEO_ID
  /// - https://www.youtube.com/shorts/VIDEO_ID
  /// - https://www.youtube.com/embed/VIDEO_ID
  /// - https://m.youtube.com/watch?v=VIDEO_ID
  /// Từ chối các chuỗi HTML/iframe hoặc URL độc hại.
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('<iframe') || trimmed.contains('<script')) return null;

    // Regex trích xuất 11 ký tự video ID chuẩn của YouTube
    final regExp = RegExp(
      r'^(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(trimmed);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  /// Tạo khối an toàn từ URL đầu vào của người dùng.
  static YouTubeBlockData? fromInputUrl(String input, {String caption = ''}) {
    final vid = extractVideoId(input);
    if (vid == null) return null;
    return YouTubeBlockData(
      url: 'https://www.youtube.com/watch?v=$vid',
      videoId: vid,
      caption: caption,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'url': url,
        'videoId': videoId,
        'caption': caption,
      };

  factory YouTubeBlockData.fromJson(Map<String, dynamic> json) => YouTubeBlockData(
        url: json['url'] as String? ?? '',
        videoId: json['videoId'] as String? ?? '',
        caption: json['caption'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YouTubeBlockData &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          videoId == other.videoId &&
          caption == other.caption;

  @override
  int get hashCode => Object.hash(url, videoId, caption);
}

/// 8. Khối Sơ đồ hình bi (tham chiếu qua diagramId).
@immutable
class BilliardDiagramBlockData extends ArticleBlockData {
  final String diagramId;
  final String caption;

  const BilliardDiagramBlockData({
    required this.diagramId,
    this.caption = '',
  });

  @override
  Map<String, dynamic> toJson() => {
        'diagramId': diagramId,
        'caption': caption,
      };

  factory BilliardDiagramBlockData.fromJson(Map<String, dynamic> json) =>
      BilliardDiagramBlockData(
        diagramId: json['diagramId'] as String? ?? '',
        caption: json['caption'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BilliardDiagramBlockData &&
          runtimeType == other.runtimeType &&
          diagramId == other.diagramId &&
          caption == other.caption;

  @override
  int get hashCode => Object.hash(diagramId, caption);
}

/// 9. Khối Thẻ thông số cách đánh (Chạm trái 12 phần, Ép phê, Lực 0-100%).
@immutable
class StrokeParameterBlockData extends ArticleBlockData {
  final String? linkedDiagramId; // Gắn với một sơ đồ cụ thể hoặc null nếu độc lập
  final StrokeParameters strokeParameters;

  const StrokeParameterBlockData({
    this.linkedDiagramId,
    required this.strokeParameters,
  });

  @override
  Map<String, dynamic> toJson() => {
        if (linkedDiagramId != null) 'linkedDiagramId': linkedDiagramId,
        'strokeParameters': strokeParameters.toJson(),
      };

  factory StrokeParameterBlockData.fromJson(Map<String, dynamic> json) {
    final rawStroke = json['strokeParameters'];
    final stroke = rawStroke is Map<String, dynamic>
        ? StrokeParameters.fromJson(rawStroke)
        : StrokeParameters.defaults();
    return StrokeParameterBlockData(
      linkedDiagramId: json['linkedDiagramId'] as String?,
      strokeParameters: stroke,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokeParameterBlockData &&
          runtimeType == other.runtimeType &&
          linkedDiagramId == other.linkedDiagramId &&
          strokeParameters == other.strokeParameters;

  @override
  int get hashCode => Object.hash(linkedDiagramId, strokeParameters);
}

/// 10. Khối Đường phân cách.
@immutable
class DividerBlockData extends ArticleBlockData {
  const DividerBlockData();

  @override
  Map<String, dynamic> toJson() => {};

  factory DividerBlockData.fromJson(Map<String, dynamic> json) =>
      const DividerBlockData();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DividerBlockData;

  @override
  int get hashCode => 0;
}

/// 11. Khối Công thức / Ghi chú mã.
@immutable
class CodeFormulaBlockData extends ArticleBlockData {
  final String text;
  final String? language;

  const CodeFormulaBlockData({
    required this.text,
    this.language,
  });

  @override
  Map<String, dynamic> toJson() => {
        'text': text,
        if (language != null) 'language': language,
      };

  factory CodeFormulaBlockData.fromJson(Map<String, dynamic> json) =>
      CodeFormulaBlockData(
        text: json['text'] as String? ?? '',
        language: json['language'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeFormulaBlockData &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          language == other.language;

  @override
  int get hashCode => Object.hash(text, language);
}

/// Khối dữ liệu không nhận diện được (bảo vệ schema mở rộng từ tương lai).
@immutable
class UnknownBlockData extends ArticleBlockData {
  final String rawType;
  final Map<String, dynamic> rawData;

  const UnknownBlockData({
    required this.rawType,
    required this.rawData,
  });

  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(rawData);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownBlockData &&
          runtimeType == other.runtimeType &&
          rawType == other.rawType &&
          mapEquals(rawData, other.rawData);

  @override
  int get hashCode => Object.hash(rawType, Object.hashAll(rawData.entries));
}

/// Một khối nội dung bất biến trong tài liệu bài viết.
@immutable
class ArticleBlock {
  final String id;
  final ArticleBlockType type;
  final ArticleBlockData data;

  const ArticleBlock({
    required this.id,
    required this.type,
    required this.data,
  });

  ArticleBlock copyWith({
    String? id,
    ArticleBlockType? type,
    ArticleBlockData? data,
  }) {
    return ArticleBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type == ArticleBlockType.unknown && data is UnknownBlockData
            ? (data as UnknownBlockData).rawType
            : type.code,
        'data': data.toJson(),
      };

  factory ArticleBlock.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final typeCode = json['type'] as String? ?? '';
    final type = ArticleBlockType.fromCode(typeCode);
    final rawData = (json['data'] as Map<String, dynamic>?) ?? {};

    ArticleBlockData blockData;
    switch (type) {
      case ArticleBlockType.heading:
        blockData = HeadingBlockData.fromJson(rawData);
      case ArticleBlockType.paragraph:
        blockData = ParagraphBlockData.fromJson(rawData);
      case ArticleBlockType.callout:
        blockData = CalloutBlockData.fromJson(rawData);
      case ArticleBlockType.bulletList:
        blockData = BulletListBlockData.fromJson(rawData);
      case ArticleBlockType.orderedList:
        blockData = OrderedListBlockData.fromJson(rawData);
      case ArticleBlockType.image:
        blockData = ImageBlockData.fromJson(rawData);
      case ArticleBlockType.youtubeVideo:
        blockData = YouTubeBlockData.fromJson(rawData);
      case ArticleBlockType.billiardDiagram:
        blockData = BilliardDiagramBlockData.fromJson(rawData);
      case ArticleBlockType.strokeParameter:
        blockData = StrokeParameterBlockData.fromJson(rawData);
      case ArticleBlockType.divider:
        blockData = DividerBlockData.fromJson(rawData);
      case ArticleBlockType.codeFormula:
        blockData = CodeFormulaBlockData.fromJson(rawData);
      case ArticleBlockType.unknown:
        blockData = UnknownBlockData(rawType: typeCode, rawData: rawData);
    }

    return ArticleBlock(
      id: id,
      type: type,
      data: blockData,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArticleBlock &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          data == other.data;

  @override
  int get hashCode => Object.hash(id, type, data);
}
