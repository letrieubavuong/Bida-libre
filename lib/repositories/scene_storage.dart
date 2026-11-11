import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Giao diện lưu/tải một sơ đồ (Phase 2).
abstract class SceneStorage {
  Future<DiagramScene?> loadScene();
  Future<void> saveScene(DiagramScene scene);
}

/// Repository lưu một sơ đồ vector dạng JSON nguyên tử trong thư mục dữ liệu bền vững
/// của ứng dụng (`getApplicationSupportDirectory()`), không dùng thư mục tạm.
class FileSceneStorage implements SceneStorage {
  static const String defaultFileName = 'primary_scene.json';

  final Future<Directory> Function() _directoryProvider;
  final String fileName;

  FileSceneStorage({
    Future<Directory> Function()? directoryProvider,
    this.fileName = defaultFileName,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  Future<File> _resolveTargetFile() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, fileName));
  }

  @override
  Future<DiagramScene?> loadScene() async {
    final target = await _resolveTargetFile();
    if (!await target.exists()) {
      return null;
    }
    final raw = await target.readAsString();
    if (raw.trim().isEmpty) {
      throw const FormatException('Tệp sơ đồ bị rỗng.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Định dạng dữ liệu sơ đồ không hợp lệ.');
    }
    return DiagramScene.fromJson(decoded);
  }

  @override
  Future<void> saveScene(DiagramScene scene) async {
    final validationError = scene.validateScene();
    if (validationError != null) {
      throw FormatException(validationError);
    }

    final target = await _resolveTargetFile();

    // Không ghi đè nếu tệp hiện có thuộc schema mới hơn bản app hiện tại.
    if (await target.exists()) {
      try {
        final existingRaw = await target.readAsString();
        if (existingRaw.trim().isNotEmpty) {
          final existingJson = jsonDecode(existingRaw);
          if (existingJson is Map<String, dynamic>) {
            final existingVersion = (existingJson['version'] as num?)?.toInt();
            if (existingVersion != null &&
                existingVersion > DiagramScene.currentSchemaVersion) {
              throw SchemaVersionException(
                foundVersion: existingVersion,
                supportedVersion: DiagramScene.currentSchemaVersion,
              );
            }
          }
        }
      } on SchemaVersionException {
        rethrow;
      } catch (_) {
        // Nếu tệp cũ bị hỏng không đọc được JSON, cho phép ghi đè bằng bản hợp lệ mới.
      }
    }

    final payload = const JsonEncoder.withIndent('  ').convert(scene.toJson());
    final tmpFile = File('${target.path}.tmp');
    await tmpFile.writeAsString(payload, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await tmpFile.rename(target.path);
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
    final err = scene.validateScene();
    if (err != null) throw FormatException(err);
    _stored = scene;
  }
}
