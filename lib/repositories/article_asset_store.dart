import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Kết quả kiểm tra và lưu tạm (staging) một ảnh nguồn từ thiết bị.
class StagedImageAsset {
  final String assetId;
  final String relativePath;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;

  const StagedImageAsset({
    required this.assetId,
    required this.relativePath,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
  });
}

/// Quản lý kho tệp ảnh nguồn bền vững cho bài viết (Phase 4C):
/// - Ảnh mới chọn được kiểm tra định dạng/kích thước/dung lượng và lưu vào vùng staging.
/// - Chỉ khi lưu bài mới chuyển (promote) sang vùng dữ liệu bền vững `article_assets/`.
/// - Tệp vật lý trong `article_assets/` là bất biến theo `assetId` và chỉ bị xóa khi
///   không còn bài viết nào trong SQLite tham chiếu tới.
class ArticleAssetStore {
  static const String committedFolderName = 'article_assets';
  static const String stagingFolderName = 'article_assets_staging';

  /// Giới hạn hợp lý cho ảnh đính kèm: tối đa 15 MB và tối đa 8192x8192 px.
  static const int maxImageBytes = 15 * 1024 * 1024;
  static const int maxImageDimensionPx = 8192;

  final Future<Directory> Function() _directoryProvider;
  final Future<void> Function(String stage, String assetId)? debugAssetHook;

  ArticleAssetStore({
    Future<Directory> Function()? directoryProvider,
    this.debugAssetHook,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  Future<Directory> _baseDir() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _committedDir() async {
    final base = await _baseDir();
    final dir = Directory(p.join(base.path, committedFolderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _stagingDir() async {
    final base = await _baseDir();
    final dir = Directory(p.join(base.path, stagingFolderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Giải quyết đường dẫn tương đối (`article_assets/...` hoặc `article_assets_staging/...`)
  /// sang tệp thực tế trên máy (nằm trong vùng dữ liệu ứng dụng).
  Future<File> resolveRelativePath(String relativePath) async {
    final base = await _baseDir();
    final normalized = relativePath.replaceAll('\\', '/');
    return File(p.joinAll([base.path, ...normalized.split('/')]));
  }

  /// Kiểm tra tồn tại tệp đã commit hoặc đang staging cho một ảnh đính kèm.
  Future<File?> findExistingFile({
    required String assetId,
    required String relativePath,
  }) async {
    final primary = await resolveRelativePath(relativePath);
    if (await primary.exists()) return primary;
    final ext = p.extension(relativePath);
    final committed = File(
      p.join((await _committedDir()).path, '$assetId$ext'),
    );
    if (await committed.exists()) return committed;
    final staged = File(
      p.join((await _stagingDir()).path, '$assetId$ext'),
    );
    if (await staged.exists()) return staged;
    return null;
  }

  /// Kiểm tra ảnh và ghi vào vùng staging (`article_assets_staging/<assetId><ext>`).
  /// Không dùng tên tệp gốc của người dùng làm đường dẫn lưu.
  Future<StagedImageAsset> stageImageBytes({
    required String assetId,
    required Uint8List bytes,
    required String originalName,
  }) async {
    if (bytes.isEmpty) {
      throw const FormatException('Tệp ảnh rỗng hoặc không đọc được.');
    }
    if (bytes.length > maxImageBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw FormatException(
        'Ảnh "$originalName" nặng $mb MB, vượt quá giới hạn 15 MB.',
      );
    }

    final parsed = inspectImageHeader(bytes);
    if (parsed == null) {
      throw FormatException(
        'Ảnh "$originalName" không đúng định dạng hỗ trợ (PNG, JPEG, WebP) hoặc bị hỏng.',
      );
    }
    if (parsed.width <= 0 ||
        parsed.height <= 0 ||
        parsed.width > maxImageDimensionPx ||
        parsed.height > maxImageDimensionPx) {
      throw FormatException(
        'Kích thước ảnh ${parsed.width}x${parsed.height} px vượt giới hạn cho phép '
        '(tối đa ${maxImageDimensionPx}x$maxImageDimensionPx px).',
      );
    }

    await debugAssetHook?.call('before_stage_write', assetId);

    final staging = await _stagingDir();
    final fileName = '$assetId${parsed.extension}';
    final target = File(p.join(staging.path, fileName));
    final tmp = File(p.join(staging.path, '$fileName.tmp'));
    await tmp.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await tmp.rename(target.path);

    return StagedImageAsset(
      assetId: assetId,
      relativePath: '$committedFolderName/$fileName',
      originalName: originalName,
      mimeType: parsed.mimeType,
      sizeBytes: bytes.length,
      width: parsed.width,
      height: parsed.height,
    );
  }

  /// Đọc từ tệp nguồn tạm (từ ImagePicker) và đưa vào vùng staging.
  Future<StagedImageAsset> stageImageFile({
    required String assetId,
    required String sourceFilePath,
    required String originalName,
  }) async {
    final file = File(sourceFilePath);
    if (!await file.exists()) {
      throw FormatException('Không tìm thấy tệp ảnh "$originalName".');
    }
    final length = await file.length();
    if (length > maxImageBytes) {
      final mb = (length / (1024 * 1024)).toStringAsFixed(1);
      throw FormatException(
        'Ảnh "$originalName" nặng $mb MB, vượt quá giới hạn 15 MB.',
      );
    }
    final bytes = await file.readAsBytes();
    return stageImageBytes(
      assetId: assetId,
      bytes: bytes,
      originalName: originalName,
    );
  }

  /// Chuyển ảnh từ staging sang vùng bền vững `article_assets/` trước khi commit SQLite.
  Future<void> promoteStagedAsset({
    required String assetId,
    required String relativePath,
  }) async {
    await debugAssetHook?.call('before_promote_asset', assetId);

    final committedFile = await resolveRelativePath(relativePath);
    if (await committedFile.exists()) {
      // Tài nguyên bất biến đã tồn tại (ví dụ từ lần lưu trước hoặc bài nhân bản).
      return;
    }

    final fileName = p.basename(relativePath);
    final stagedFile = File(p.join((await _stagingDir()).path, fileName));
    if (!await stagedFile.exists()) {
      throw FileSystemException(
        'Không tìm thấy tệp ảnh tạm để lưu bài viết.',
        stagedFile.path,
      );
    }

    final committedDir = await _committedDir();
    if (!await committedDir.exists()) {
      await committedDir.create(recursive: true);
    }
    final tmp = File('${committedFile.path}.tmp');
    await stagedFile.copy(tmp.path);
    await tmp.rename(committedFile.path);
    if (await stagedFile.exists()) {
      try {
        await stagedFile.delete();
      } catch (_) {
        // Trên Windows, bộ giải mã ảnh có thể giữ handle đọc tạm thời;
        // cleanupOrphanedAssets sẽ dọn tệp staging này sau khi quá hạn.
      }
    }
  }

  /// Xóa các tệp tạm đang staging khi người dùng chủ động hủy bản nháp.
  Future<void> discardStagingAssets(Iterable<String> assetIds) async {
    final idSet = assetIds.toSet();
    if (idSet.isEmpty) return;
    final staging = await _stagingDir();
    if (!await staging.exists()) return;
    await for (final entity in staging.list()) {
      if (entity is File) {
        final base = p.basenameWithoutExtension(entity.path);
        if (idSet.contains(base)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
  }

  /// Xóa tệp đã commit theo `relativePath` (chỉ gọi sau khi SQLite xác nhận refCount == 0).
  Future<void> deleteCommittedAsset(String relativePath) async {
    final file = await resolveRelativePath(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Dọn tệp mồ côi:
  /// - Trong `article_assets/`: xóa tệp không nằm trong [referencedAssetIds].
  /// - Trong `article_assets_staging/`: xóa tệp staging không thuộc [activeDraftStagingIds]
  ///   và cũ hơn [stagingMaxAge] (mặc định 24 giờ, hoặc ngay lập tức khi truyền 0 cho test).
  Future<int> cleanupOrphanedAssets({
    required Set<String> referencedAssetIds,
    Set<String> activeDraftStagingIds = const {},
    Duration stagingMaxAge = const Duration(hours: 24),
  }) async {
    var deletedCount = 0;
    final committed = await _committedDir();
    if (await committed.exists()) {
      await for (final entity in committed.list()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.endsWith('.tmp')) {
            try {
              await entity.delete();
              deletedCount++;
            } catch (_) {}
            continue;
          }
          final assetId = p.basenameWithoutExtension(entity.path);
          if (!referencedAssetIds.contains(assetId)) {
            try {
              await entity.delete();
              deletedCount++;
            } catch (_) {}
          }
        }
      }
    }

    final staging = await _stagingDir();
    if (await staging.exists()) {
      final now = DateTime.now();
      await for (final entity in staging.list()) {
        if (entity is File) {
          final assetId = p.basenameWithoutExtension(
            entity.path.endsWith('.tmp')
                ? entity.path.substring(0, entity.path.length - 4)
                : entity.path,
          );
          if (activeDraftStagingIds.contains(assetId)) {
            continue;
          }
          final stat = await entity.stat();
          if (now.difference(stat.modified) >= stagingMaxAge) {
            try {
              await entity.delete();
              deletedCount++;
            } catch (_) {}
          }
        }
      }
    }
    return deletedCount;
  }

  /// Phân tích magic bytes & kích thước ảnh từ header PNG / JPEG / WebP (thuần Dart).
  static ({String mimeType, String extension, int width, int height})?
      inspectImageHeader(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // PNG: 89 50 4E 47 0D 0A 1A 0A, IHDR width@16..19, height@20..23
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      final bd = ByteData.sublistView(bytes);
      final w = bd.getUint32(16, Endian.big);
      final h = bd.getUint32(20, Endian.big);
      return (mimeType: 'image/png', extension: '.png', width: w, height: h);
    }

    // JPEG: FF D8 FF ... SOF0..SOF3/SOF5..SOF15 (C0..CF trừ C4, C8, CC)
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      var offset = 2;
      while (offset + 4 < bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }
        while (offset < bytes.length && bytes[offset] == 0xFF) {
          offset++;
        }
        if (offset >= bytes.length) break;
        final marker = bytes[offset];
        offset++;
        if (marker == 0xD8 || marker == 0xD9 || marker == 0x00) continue;
        if (marker >= 0xD0 && marker <= 0xD7) continue;
        if (offset + 2 > bytes.length) break;
        final segmentLen = (bytes[offset] << 8) | bytes[offset + 1];
        if (segmentLen < 2 || offset + segmentLen > bytes.length) break;
        final isSof = (marker >= 0xC0 && marker <= 0xCF) &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC;
        if (isSof && offset + 7 <= bytes.length) {
          final h = (bytes[offset + 3] << 8) | bytes[offset + 4];
          final w = (bytes[offset + 5] << 8) | bytes[offset + 6];
          return (
            mimeType: 'image/jpeg',
            extension: '.jpg',
            width: w,
            height: h,
          );
        }
        offset += segmentLen;
      }
      return null;
    }

    // WebP: RIFF....WEBP
    if (bytes.length >= 30 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      final chunk = String.fromCharCodes(bytes.sublist(12, 16));
      if (chunk == 'VP8X' && bytes.length >= 30) {
        final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
        final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
        return (mimeType: 'image/webp', extension: '.webp', width: w, height: h);
      }
      if (chunk == 'VP8 ' && bytes.length >= 30) {
        final w = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
        final h = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
        return (mimeType: 'image/webp', extension: '.webp', width: w, height: h);
      }
      if (chunk == 'VP8L' && bytes.length >= 25) {
        final bits = bytes[21] |
            (bytes[22] << 8) |
            (bytes[23] << 16) |
            (bytes[24] << 24);
        final w = (bits & 0x3FFF) + 1;
        final h = ((bits >> 14) & 0x3FFF) + 1;
        return (mimeType: 'image/webp', extension: '.webp', width: w, height: h);
      }
    }

    return null;
  }
}

