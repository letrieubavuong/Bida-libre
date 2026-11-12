import 'article.dart';
import 'enums.dart';
import 'library_meta.dart';

/// Tùy chọn sắp xếp danh sách bài viết.
enum ArticleSortOption {
  updatedDesc('updated_desc', 'Mới sửa'),
  codeAsc('code_asc', 'Mã bài'),
  titleAsc('title_asc', 'Tên bài'),
  collectionManualOrder('collection_manual', 'Thứ tự bộ sưu tập');

  const ArticleSortOption(this.storageKey, this.label);

  final String storageKey;
  final String label;
}

/// Bộ chuẩn hóa chuỗi tìm kiếm tiếng Việt & bảng alias biên tập tường minh (Phase 4B).
class VietnameseSearchNormalizer {
  const VietnameseSearchNormalizer._();

  static const Map<String, String> _diacriticMap = {
    'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
    'đ': 'd',
    'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
  };

  /// Bảng alias biên tập tường minh (chỉ mở rộng những cụm đã quy định, không tự suy đoán).
  static const List<List<String>> editorialAliasGroups = [
    ['cu le', 'cule'],
    ['a mot ti', 'amorti'],
    ['ma xe', 'masse'],
  ];

  /// Chuẩn hóa văn bản: thường, bỏ dấu (gồm đ -> d), gạch nối -> khoảng trắng, gộp khoảng trắng.
  static String normalize(String input) {
    final lower = input.toLowerCase();
    final buffer = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      if (ch == '-' || ch == '–' || ch == '—' || ch == '_') {
        buffer.write(' ');
      } else {
        buffer.write(_diacriticMap[ch] ?? ch);
      }
    }
    return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Chuẩn hóa tên thẻ để lưu và chống trùng lặp hoa/thường/khoảng trắng, giữ nguyên dấu tiếng Việt.
  static String cleanTagDisplay(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String tagDuplicateKey(String raw) {
    return cleanTagDisplay(raw).toLowerCase();
  }

  /// Trả về các biến thể tìm kiếm tương đương theo bảng alias biên tập.
  static List<String> expandQueryVariants(String rawQuery) {
    final base = normalize(rawQuery);
    if (base.isEmpty) return const [];
    final variants = <String>{base};
    for (final group in editorialAliasGroups) {
      for (final term in group) {
        if (base.contains(term)) {
          for (final alt in group) {
            variants.add(base.replaceAll(term, alt));
          }
        }
      }
    }
    return variants.toList(growable: false);
  }

  /// Kiểm tra [candidate] có chứa [rawQuery] hay biến thể alias biên tập tương ứng không.
  static bool matches(String candidate, String rawQuery) {
    final qVariants = expandQueryVariants(rawQuery);
    if (qVariants.isEmpty) return true;
    final cNorm = normalize(candidate);
    if (cNorm.isEmpty) return false;
    final cVariants = <String>{cNorm};
    for (final group in editorialAliasGroups) {
      for (final term in group) {
        if (cNorm.contains(term)) {
          for (final alt in group) {
            cVariants.add(cNorm.replaceAll(term, alt));
          }
        }
      }
    }
    for (final qv in qVariants) {
      for (final cv in cVariants) {
        if (cv.contains(qv)) return true;
      }
    }
    return false;
  }
}

/// Tiêu chí tìm kiếm, lọc và sắp xếp bài viết (tách biệt hoàn toàn khỏi UI để kiểm thử độc lập).
class ArticleFilterCriteria {
  final String searchQuery;
  final Set<String> groupIds;
  final Set<String> tagKeys; // Dùng tagDuplicateKey
  final Set<Difficulty> difficulties;
  final Set<String> collectionIds;
  final bool favoritesOnly;
  final ArticleSortOption sortBy;

  const ArticleFilterCriteria({
    this.searchQuery = '',
    this.groupIds = const {},
    this.tagKeys = const {},
    this.difficulties = const {},
    this.collectionIds = const {},
    this.favoritesOnly = false,
    this.sortBy = ArticleSortOption.updatedDesc,
  });

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      groupIds.isNotEmpty ||
      tagKeys.isNotEmpty ||
      difficulties.isNotEmpty ||
      collectionIds.isNotEmpty ||
      favoritesOnly;

  ArticleFilterCriteria copyWith({
    String? searchQuery,
    Set<String>? groupIds,
    Set<String>? tagKeys,
    Set<Difficulty>? difficulties,
    Set<String>? collectionIds,
    bool? favoritesOnly,
    ArticleSortOption? sortBy,
  }) {
    return ArticleFilterCriteria(
      searchQuery: searchQuery ?? this.searchQuery,
      groupIds: groupIds ?? this.groupIds,
      tagKeys: tagKeys ?? this.tagKeys,
      difficulties: difficulties ?? this.difficulties,
      collectionIds: collectionIds ?? this.collectionIds,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

/// Bộ máy lọc & sắp xếp bài viết thuần Dart.
class ArticleQueryEngine {
  const ArticleQueryEngine._();

  static final RegExp _codeRegex = RegExp(r'^([A-Za-z]+)-(\d+)$');

  /// So sánh mã bài theo phần chữ + phần số nguyên (KT-2 < KT-10).
  static int compareCodes(String a, String b) {
    final ma = _codeRegex.firstMatch(a.trim());
    final mb = _codeRegex.firstMatch(b.trim());
    if (ma != null && mb != null) {
      final prefixCmp = ma.group(1)!.compareTo(mb.group(1)!);
      if (prefixCmp != 0) return prefixCmp;
      final numA = int.tryParse(ma.group(2)!) ?? 0;
      final numB = int.tryParse(mb.group(2)!) ?? 0;
      final numCmp = numA.compareTo(numB);
      if (numCmp != 0) return numCmp;
    }
    return a.compareTo(b);
  }

  static List<Article> filterAndSort({
    required List<Article> articles,
    required ArticleFilterCriteria criteria,
    List<Collection> collections = const [],
    ArticleKind? kindFilter,
  }) {
    final collectionById = {for (final c in collections) c.id: c};
    final allowedByCollection = <String>{};
    if (criteria.collectionIds.isNotEmpty) {
      for (final cid in criteria.collectionIds) {
        final col = collectionById[cid];
        if (col != null) {
          allowedByCollection.addAll(col.orderedArticleIds);
        }
      }
    }

    final query = criteria.searchQuery.trim();
    final filtered = articles.where((article) {
      if (kindFilter != null && article.kind != kindFilter) {
        return false;
      }
      if (criteria.favoritesOnly && !article.isFavorite) {
        return false;
      }
      // OR trong cùng bộ lọc nhóm
      if (criteria.groupIds.isNotEmpty &&
          !criteria.groupIds.contains(article.primaryGroupId)) {
        return false;
      }
      // OR trong cùng bộ lọc độ khó
      if (criteria.difficulties.isNotEmpty &&
          !criteria.difficulties.contains(article.difficulty)) {
        return false;
      }
      // OR trong cùng bộ lọc bộ sưu tập
      if (criteria.collectionIds.isNotEmpty &&
          !allowedByCollection.contains(article.id)) {
        return false;
      }
      // OR trong cùng bộ lọc thẻ
      if (criteria.tagKeys.isNotEmpty) {
        final articleTagKeys = article.tags
            .map(VietnameseSearchNormalizer.tagDuplicateKey)
            .toSet();
        if (!articleTagKeys.any(criteria.tagKeys.contains)) {
          return false;
        }
      }
      // Tìm kiếm kết hợp AND với các bộ lọc: khớp mã, tên, mô tả ngắn hoặc thẻ
      if (query.isNotEmpty) {
        final matchesCode =
            VietnameseSearchNormalizer.matches(article.code, query);
        final matchesTitle =
            VietnameseSearchNormalizer.matches(article.title, query);
        final matchesSummary =
            VietnameseSearchNormalizer.matches(article.summary, query);
        final matchesTag = article.tags.any(
          (t) => VietnameseSearchNormalizer.matches(t, query),
        );
        if (!matchesCode && !matchesTitle && !matchesSummary && !matchesTag) {
          return false;
        }
      }
      return true;
    }).toList();

    Map<String, int>? manualOrderIndex;
    if (criteria.sortBy == ArticleSortOption.collectionManualOrder &&
        criteria.collectionIds.length == 1) {
      final col = collectionById[criteria.collectionIds.first];
      if (col != null) {
        manualOrderIndex = {
          for (var i = 0; i < col.orderedArticleIds.length; i++)
            col.orderedArticleIds[i]: i,
        };
      }
    }

    int compareStableTieBreaker(Article a, Article b) {
      final updCmp = b.updatedAt.compareTo(a.updatedAt);
      if (updCmp != 0) return updCmp;
      final codeCmp = compareCodes(a.code, b.code);
      if (codeCmp != 0) return codeCmp;
      return a.id.compareTo(b.id);
    }

    filtered.sort((a, b) {
      switch (criteria.sortBy) {
        case ArticleSortOption.updatedDesc:
          return compareStableTieBreaker(a, b);
        case ArticleSortOption.codeAsc:
          final cmp = compareCodes(a.code, b.code);
          return cmp != 0 ? cmp : compareStableTieBreaker(a, b);
        case ArticleSortOption.titleAsc:
          final na = VietnameseSearchNormalizer.normalize(a.title);
          final nb = VietnameseSearchNormalizer.normalize(b.title);
          final cmp = na.compareTo(nb);
          if (cmp != 0) return cmp;
          final rawCmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          return rawCmp != 0 ? rawCmp : compareStableTieBreaker(a, b);
        case ArticleSortOption.collectionManualOrder:
          if (manualOrderIndex != null) {
            final ia = manualOrderIndex[a.id] ?? 1 << 30;
            final ib = manualOrderIndex[b.id] ?? 1 << 30;
            final cmp = ia.compareTo(ib);
            if (cmp != 0) return cmp;
          }
          return compareStableTieBreaker(a, b);
      }
    });

    return filtered;
  }
}

