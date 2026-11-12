import '../models/models.dart';
import 'pure_annotation_geometry.dart';
import 'pure_path_geometry.dart';

/// Báo cáo tách biệt giữa:
/// 1) Lỗi cấu trúc / hỏng dữ liệu (`structuralError`).
/// 2) Lỗi hình học đường hướng dẫn (`pathErrors` — chặn lưu sơ đồ hoàn chỉnh).
/// 3) Cảnh báo quy tắc biên tập mới trên dữ liệu cũ (`annotationRuleWarnings` — vẫn cho mở & chỉnh).
class SceneValidationReport {
  final String? structuralError;
  final Map<String, String> pathErrors;
  final Map<String, String> annotationRuleWarnings;

  const SceneValidationReport({
    required this.structuralError,
    required this.pathErrors,
    required this.annotationRuleWarnings,
  });

  bool get isStructurallyValid => structuralError == null;
  bool get isCompleteValid => structuralError == null && pathErrors.isEmpty;

  String? formatCompleteSaveError() {
    if (isCompleteValid) return null;
    if (structuralError != null) return structuralError;
    final details = pathErrors.entries
        .map((e) => '- ${e.key}: ${e.value}')
        .join('\n');
    return 'Chưa thể lưu sơ đồ hoàn chỉnh vì có ${pathErrors.length} đường không hợp lệ:\n$details';
  }
}

/// Validator thống nhất thuần Dart dùng cho cả editor UI lẫn tầng lưu trữ hoàn chỉnh.
class SceneValidator {
  const SceneValidator._();

  static SceneValidationReport inspect(DiagramScene scene) {
    final structErr = scene.validateStructure();
    final pathErrs = <String, String>{};
    for (final path in scene.paths) {
      final err = PurePathGeometry.validatePath(
        path,
        scene.balls,
        width: scene.width,
        height: scene.height,
      );
      if (err != null) {
        pathErrs[path.id] = err;
      }
    }
    final annWarnings = PureAnnotationGeometry.collectRuleWarnings(scene);

    return SceneValidationReport(
      structuralError: structErr,
      pathErrors: Map<String, String>.unmodifiable(pathErrs),
      annotationRuleWarnings: annWarnings,
    );
  }

  /// Kiểm tra toàn vẹn bắt buộc trước khi lưu sơ đồ hoàn chỉnh.
  static String? validateCompleteForSave(DiagramScene scene) {
    return inspect(scene).formatCompleteSaveError();
  }
}

