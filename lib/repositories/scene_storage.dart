import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../geometry/scene_validator.dart';
import '../models/models.dart';

/// Giao diện lưu/tải một sơ đồ (Phase 2).
abstract class SceneStorage {
  Future<DiagramScene?> loadScene();
  Future<void> saveScene(DiagramScene scene);
}

typedef FileReplaceHook = Future<void> Function(File tmpFile, File targetFile);

/// Repository lưu một sơ đồ vector dạng JSON an toàn trong thư mục dữ liệu bền vững
/// của ứng dụng (`getApplicationSupportDirectory()`), không dùng thư mục tạm.
///
/// Cơ chế an toàn ghi/phục hồi:
/// - Giữ bản sao tốt gần nhất (`primary_scene.json.bak`) trước khi thay thế.
/// - Ghi dữ liệu mới ra tệp tạm cùng thư mục (`primary_scene.json.tmp`) và flush trước khi thay thế.
/// - Không xóa tệp chính trước khi thay thế thành công.
/// - Nếu tệp chính bị hỏng nhưng `.bak` còn nguyên vẹn, tự phục hồi từ `.bak` và giữ bản sao hỏng (`.corrupt`).
/// - Từ chối ghi đè hoặc tải schema mới hơn phiên bản app hiện tại.
class FileSceneStorage implements SceneStorage {
  static const String defaultFileName = 'primary_scene.json';

  final Future<Directory> Function() _directoryProvider;
  final String fileName;
  final FileReplaceHook _replaceFile;

  FileSceneStorage({
    Future<Directory> Function()? directoryProvider,
    this.fileName = defaultFileName,
    FileReplaceHook? replaceFile,
  })  : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
        _replaceFile = replaceFile ?? _defaultReplaceFile;

  static Future<void> _defaultReplaceFile(File tmpFile, File targetFile) async {
    await tmpFile.rename(targetFile.path);
  }

  Future<File> _resolveFile(String suffix) async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, '$fileName$suffix'));
  }

  DiagramScene _decodeStrict(String raw) {
    if (raw.trim().isEmpty) {
      throw const FormatException('Tệp sơ đồ bị rỗng.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Định dạng dữ liệu sơ đồ không hợp lệ.');
    }
    return DiagramScene.fromJson(decoded);
  }

  Future<void> _preserveCorruptCopy(File source, File corruptFile) async {
    if (await source.exists()) {
      await source.copy(corruptFile.path);
    }
  }

  @override
  Future<DiagramScene?> loadScene() async {
    final target = await _resolveFile('');
    final backup = await _resolveFile('.bak');
    final corrupt = await _resolveFile('.corrupt');

    if (await target.exists()) {
      try {
        final raw = await target.readAsString();
        return _decodeStrict(raw);
      } on SchemaVersionException {
        rethrow;
      } catch (primaryError) {
        // Tệp chính bị hỏng: giữ lại bản sao hỏng và thử phục hồi từ bản sao lưu `.bak`.
        await _preserveCorruptCopy(target, corrupt);
        if (await backup.exists()) {
          try {
            final bakRaw = await backup.readAsString();
            final recovered = _decodeStrict(bakRaw);
            // Phục hồi lại tệp chính qua tệp tạm mà không xóa trực tiếp trước khi ghi xong.
            final recoveryTmp = await _resolveFile('.recover.tmp');
            await recoveryTmp.writeAsString(bakRaw, flush: true);
            await _replaceFile(recoveryTmp, target);
            return recovered;
          } on SchemaVersionException {
            rethrow;
          } catch (_) {
            // Backup cũng hỏng -> báo lỗi gốc.
          }
        }
        throw FormatException(
          'Tệp sơ đồ bị hỏng và không thể phục hồi: $primaryError',
        );
      }
    }

    // Trường hợp tệp chính chưa kịp tạo lại nhưng có `.bak` hợp lệ sau gián đoạn.
    if (await backup.exists()) {
      final bakRaw = await backup.readAsString();
      final recovered = _decodeStrict(bakRaw);
      final recoveryTmp = await _resolveFile('.recover.tmp');
      await recoveryTmp.writeAsString(bakRaw, flush: true);
      await _replaceFile(recoveryTmp, target);
      return recovered;
    }

    return null;
  }

  @override
  Future<void> saveScene(DiagramScene scene) async {
    final validationError = SceneValidator.validateCompleteForSave(scene);
    if (validationError != null) {
      throw FormatException(validationError);
    }

    final target = await _resolveFile('');
    final backup = await _resolveFile('.bak');
    final corrupt = await _resolveFile('.corrupt');
    final tmpFile = await _resolveFile('.tmp');

    if (await target.exists()) {
      final existingRaw = await target.readAsString();
      var existingValid = false;
      try {
        _decodeStrict(existingRaw);
        existingValid = true;
      } on SchemaVersionException {
        rethrow;
      } catch (_) {
        // Tệp cũ đang hỏng -> lưu lại một bản sao `.corrupt` trước khi thay thế có chủ đích.
        await _preserveCorruptCopy(target, corrupt);
      }

      // Sao lưu bản hợp lệ gần nhất sang `.bak` trước khi thay thế tệp chính.
      if (existingValid) {
        final bakTmp = await _resolveFile('.bak.tmp');
        await bakTmp.writeAsString(existingRaw, flush: true);
        await _replaceFile(bakTmp, backup);
      }
    }

    final payload = const JsonEncoder.withIndent('  ').convert(scene.toJson());
    await tmpFile.writeAsString(payload, flush: true);

    try {
      await _replaceFile(tmpFile, target);
    } catch (_) {
      // Giữ nguyên tệp chính / `.bak` hiện có; không xóa bản đã lưu trước đó.
      rethrow;
    }
  }
}

/// Kho lưu trữ sơ đồ trong bộ nhớ (dùng cho kiểm thử widget không phụ thuộc đĩa).
class MemorySceneStorage implements SceneStorage {
  DiagramScene? _stored;

  MemorySceneStorage({DiagramScene? initialScene}) : _stored = initialScene;

  @override
  Future<DiagramScene?> loadScene() async => _stored;

  @override
  Future<void> saveScene(DiagramScene scene) async {
    final err = SceneValidator.validateCompleteForSave(scene);
    if (err != null) throw FormatException(err);
    _stored = scene;
  }
}
