/// Kiểu độ dày chạm bi mục tiêu (tĩnh, hoàn toàn không giải cơ học).
enum HitThicknessMode {
  eighths('eighths', 'Phần tám (k/8)'),
  oneThird('one_third', '1/3 bi'),
  twoThirds('two_thirds', '2/3 bi'),
  exact('exact', 'Giá trị chính xác');

  const HitThicknessMode(this.storageKey, this.displayName);

  final String storageKey;
  final String displayName;

  static HitThicknessMode fromKey(String key) {
    return HitThicknessMode.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => HitThicknessMode.eighths,
    );
  }
}

/// Phía chạm má bi (giữ riêng với cờ tràn mặt để bật/tắt tràn mặt không làm mất má trước đó).
enum HitSide {
  center('center', 'Chính tâm'),
  left('left', 'Má trái'),
  right('right', 'Má phải');

  const HitSide(this.storageKey, this.displayName);

  final String storageKey;
  final String displayName;

  static HitSide fromKey(String key) {
    return HitSide.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => HitSide.center,
    );
  }
}

/// Quy ước biên tập bốn mức cho vị trí mũi cơ (mục 5.2 trong đặc tả).
class CueTipConvention {
  const CueTipConvention._();

  static const double referenceBallDiameterMm = 61.5;
  static const double referenceBallRadiusMm = 30.75;
  static const double fourLevelStepMm = 3.84375;
  static const double fourLevelMaxMm = 15.375;
  static const List<double> standardTipDiametersMm = [11.5, 11.75, 12.0];

  /// Chuyển độ lệch X/Z (mm) sang nhãn quy ước bốn mức (1 mức = 3.84375 mm, mức 4 = 15.375 mm).
  static String describeAxisOffset(
    double offsetMm, {
    required String positiveLabel,
    required String negativeLabel,
  }) {
    if (!offsetMm.isFinite || offsetMm.abs() < 0.05) {
      return 'Tâm (0)';
    }
    final dir = offsetMm > 0 ? positiveLabel : negativeLabel;
    final absMm = offsetMm.abs();
    final level = absMm / fourLevelStepMm;
    if (absMm > fourLevelMaxMm + 1e-6) {
      return '$dir mức >4 (${absMm.toStringAsFixed(2)} mm, ngoài 4 mức quy ước)';
    }
    final nearestLevel = level.clamp(0.0, 4.0);
    return '$dir mức ${nearestLevel.toStringAsFixed(1)} (${absMm.toStringAsFixed(2)} mm)';
  }
}

/// Thông số cách đánh hoàn toàn tĩnh gắn với bài viết (không thay đổi bi hoặc đường).
class StrokeParameters {
  final String cueBallId;
  final HitThicknessMode thicknessMode;
  final int eighthCount; // 1..8 khi dùng Phần tám
  final double? exactThicknessValue; // Giá trị chính xác khi chọn exact
  final bool isFullFace; // Tràn mặt: bật/tắt vẫn giữ thicknessMode & hitSide trước đó
  final HitSide hitSide;
  final double tipXMm; // + phải, - trái
  final double tipZMm; // + trên, - dưới
  final double tipDiameterMm; // 11.5, 11.75, 12.0 mm
  final String tipNote;
  final String forceText;
  final String strokeStyleText;

  const StrokeParameters({
    this.cueBallId = 'ball_white',
    this.thicknessMode = HitThicknessMode.eighths,
    this.eighthCount = 4,
    this.exactThicknessValue,
    this.isFullFace = false,
    this.hitSide = HitSide.center,
    this.tipXMm = 0.0,
    this.tipZMm = 0.0,
    this.tipDiameterMm = 12.0,
    this.tipNote = '',
    this.forceText = '',
    this.strokeStyleText = '',
  });

  const StrokeParameters.defaults() : this();

  String get thicknessSummary {
    if (isFullFace) {
      return 'Tràn mặt (trước đó: ${_baseThicknessLabel()}, ${hitSide.displayName})';
    }
    return '${_baseThicknessLabel()} • ${hitSide.displayName}';
  }

  String _baseThicknessLabel() {
    switch (thicknessMode) {
      case HitThicknessMode.eighths:
        return '$eighthCount/8';
      case HitThicknessMode.oneThird:
        return '1/3';
      case HitThicknessMode.twoThirds:
        return '2/3';
      case HitThicknessMode.exact:
        return exactThicknessValue != null
            ? exactThicknessValue!.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')
            : 'Chính xác';
    }
  }

  String get horizontalTipLabel => CueTipConvention.describeAxisOffset(
        tipXMm,
        positiveLabel: 'Phải',
        negativeLabel: 'Trái',
      );

  String get verticalTipLabel => CueTipConvention.describeAxisOffset(
        tipZMm,
        positiveLabel: 'Trên',
        negativeLabel: 'Dưới',
      );

  /// Kiểm tra tính hợp lệ dữ liệu số của thông số cách đánh tĩnh.
  String? validate() {
    if (!tipXMm.isFinite) {
      return 'Tọa độ mũi cơ X (mm) phải là số hữu hạn.';
    }
    if (!tipZMm.isFinite) {
      return 'Tọa độ mũi cơ Z (mm) phải là số hữu hạn.';
    }
    if (!tipDiameterMm.isFinite || tipDiameterMm <= 0) {
      return 'Đường kính đầu cơ phải là số hữu hạn lớn hơn 0.';
    }
    if (eighthCount < 1 || eighthCount > 8) {
      return 'Độ dày phần tám phải nằm trong khoảng 1 đến 8.';
    }
    if (thicknessMode == HitThicknessMode.exact) {
      if (exactThicknessValue == null || !exactThicknessValue!.isFinite) {
        return 'Vui lòng nhập giá trị độ dày chính xác hợp lệ (0 đến 1).';
      }
      if (exactThicknessValue! < 0.0 || exactThicknessValue! > 1.0) {
        return 'Độ dày chính xác phải nằm trong khoảng từ 0 đến 1.';
      }
    } else if (exactThicknessValue != null) {
      if (!exactThicknessValue!.isFinite ||
          exactThicknessValue! < 0.0 ||
          exactThicknessValue! > 1.0) {
        return 'Độ dày chính xác phải nằm trong khoảng từ 0 đến 1.';
      }
    }
    return null;
  }

  StrokeParameters copyWith({
    String? cueBallId,
    HitThicknessMode? thicknessMode,
    int? eighthCount,
    double? exactThicknessValue,
    bool clearExactThickness = false,
    bool? isFullFace,
    HitSide? hitSide,
    double? tipXMm,
    double? tipZMm,
    double? tipDiameterMm,
    String? tipNote,
    String? forceText,
    String? strokeStyleText,
  }) {
    return StrokeParameters(
      cueBallId: cueBallId ?? this.cueBallId,
      thicknessMode: thicknessMode ?? this.thicknessMode,
      eighthCount: eighthCount ?? this.eighthCount,
      exactThicknessValue: clearExactThickness
          ? null
          : (exactThicknessValue ?? this.exactThicknessValue),
      isFullFace: isFullFace ?? this.isFullFace,
      hitSide: hitSide ?? this.hitSide,
      tipXMm: tipXMm ?? this.tipXMm,
      tipZMm: tipZMm ?? this.tipZMm,
      tipDiameterMm: tipDiameterMm ?? this.tipDiameterMm,
      tipNote: tipNote ?? this.tipNote,
      forceText: forceText ?? this.forceText,
      strokeStyleText: strokeStyleText ?? this.strokeStyleText,
    );
  }

  Map<String, dynamic> toJson() => {
        'cueBallId': cueBallId,
        'thicknessMode': thicknessMode.storageKey,
        'eighthCount': eighthCount,
        if (exactThicknessValue != null)
          'exactThicknessValue': exactThicknessValue,
        'isFullFace': isFullFace,
        'hitSide': hitSide.storageKey,
        'tipXMm': tipXMm,
        'tipZMm': tipZMm,
        'tipDiameterMm': tipDiameterMm,
        'tipNote': tipNote,
        'forceText': forceText,
        'strokeStyleText': strokeStyleText,
      };

  factory StrokeParameters.fromJson(Map<String, dynamic> json) {
    final rawEighth = (json['eighthCount'] as num?)?.toInt() ?? 4;
    final eighthCount = rawEighth.clamp(1, 8);
    final rawExact = (json['exactThicknessValue'] as num?)?.toDouble();
    final rawX = (json['tipXMm'] as num?)?.toDouble() ?? 0.0;
    final rawZ = (json['tipZMm'] as num?)?.toDouble() ?? 0.0;
    final rawDia = (json['tipDiameterMm'] as num?)?.toDouble() ?? 12.0;

    return StrokeParameters(
      cueBallId: (json['cueBallId'] as String?) ?? 'ball_white',
      thicknessMode: HitThicknessMode.fromKey(
        (json['thicknessMode'] as String?) ?? 'eighths',
      ),
      eighthCount: eighthCount,
      exactThicknessValue:
          (rawExact != null && rawExact.isFinite) ? rawExact : null,
      isFullFace: (json['isFullFace'] as bool?) ?? false,
      hitSide: HitSide.fromKey((json['hitSide'] as String?) ?? 'center'),
      tipXMm: rawX.isFinite ? rawX : 0.0,
      tipZMm: rawZ.isFinite ? rawZ : 0.0,
      tipDiameterMm: (rawDia.isFinite && rawDia > 0) ? rawDia : 12.0,
      tipNote: (json['tipNote'] as String?) ?? '',
      forceText: (json['forceText'] as String?) ?? '',
      strokeStyleText: (json['strokeStyleText'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokeParameters &&
          runtimeType == other.runtimeType &&
          cueBallId == other.cueBallId &&
          thicknessMode == other.thicknessMode &&
          eighthCount == other.eighthCount &&
          exactThicknessValue == other.exactThicknessValue &&
          isFullFace == other.isFullFace &&
          hitSide == other.hitSide &&
          tipXMm == other.tipXMm &&
          tipZMm == other.tipZMm &&
          tipDiameterMm == other.tipDiameterMm &&
          tipNote == other.tipNote &&
          forceText == other.forceText &&
          strokeStyleText == other.strokeStyleText;

  @override
  int get hashCode => Object.hash(
        cueBallId,
        thicknessMode,
        eighthCount,
        exactThicknessValue,
        isFullFace,
        hitSide,
        tipXMm,
        tipZMm,
        tipDiameterMm,
        tipNote,
        forceText,
        strokeStyleText,
      );
}

