import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/stroke_parameters.dart';

/// Painter vẽ bi vàng chia 12 vạch sọc đứng (cách đều ngang đường kính)
/// và bi trắng chồng lên theo tỷ lệ độ dày chạm, má chạm, kèm chấm mũi cơ đỏ.
/// Đảm bảo tính toán hoàn toàn theo bounds của widget (không dùng tọa độ cố định)
/// và thể hiện nhất quán không làm che mất bi vàng ở mọi tỷ lệ chạm (kể cả 12/12 và chính tâm).
class HitThicknessPainter extends CustomPainter {
  final StrokeParameters stroke;
  final bool isLarge;

  const HitThicknessPainter(this.stroke, {this.isLarge = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. TÍNH TOÁN BÁN KÍNH VÀ TỌA ĐỘ THEO BOUNDS THỰC TẾ
    final thickness = stroke.effectiveThicknessFraction;

    // Khoảng cách giữa tâm 2 bi:
    // Nếu tràn mặt (isFullFace) hoặc chính tâm (HitSide.center): 2 bi đồng tâm (d = 0).
    // Nếu má phải: bi trắng lệch sang phải (d > 0).
    // Nếu má trái: bi trắng lệch sang trái (d < 0).
    final double separationFactor;
    if (stroke.isFullFace || stroke.hitSide == HitSide.center) {
      separationFactor = 0.0;
    } else if (stroke.hitSide == HitSide.right) {
      separationFactor = 2.0 * (1.0 - thickness);
    } else {
      separationFactor = -2.0 * (1.0 - thickness);
    }

    // Khoảng span ngang tối đa xảy ra tại độ dày mỏng nhất (1/12):
    // spanFactor = |separationFactor| + 2.0 <= 2.0 * (11/12) + 2.0 = 23/6 ≈ 3.8333
    const double padding = 3.0;
    final maxSpanFactor = 2.0 * (2.0 - (1.0 / 12.0)); // 23/6 ≈ 3.8333
    final maxRByWidth = (size.width - padding * 2) / maxSpanFactor;
    final maxRByHeight = (size.height - padding * 2) / 2.0;
    final double radius = min(maxRByWidth, maxRByHeight).clamp(4.0, 100.0);

    final double centerY = size.height / 2.0;
    final double dPx = separationFactor * radius;

    // Căn giữa 2 bi cân đối hoàn hảo trong chiều rộng khả dụng:
    final double yellowCenterX = (size.width / 2.0) - (dPx / 2.0);
    final double whiteCenterX = (size.width / 2.0) + (dPx / 2.0);

    final yellowCenter = Offset(yellowCenterX, centerY);
    final whiteCenter = Offset(whiteCenterX, centerY);

    // 2. VẼ BI VÀNG VỚI 11 VẠCH CHIA 12 PHẦN THẲNG ĐỨNG CÁCH ĐỀU THEO ĐƯỜNG KÍNH
    final double xLeft = yellowCenterX - radius;
    final double xRight = yellowCenterX + radius;
    final double stepX = (2 * radius) / 12.0;

    final yellowPath = Path()
      ..addOval(Rect.fromCircle(center: yellowCenter, radius: radius));

    canvas.save();
    canvas.clipPath(yellowPath);

    // Nền bi vàng tươi
    canvas.drawCircle(
      yellowCenter,
      radius,
      Paint()
        ..color = const Color(0xFFFFCA28)
        ..style = PaintingStyle.fill,
    );

    // 11 vạch thẳng đứng, cách đều nhau theo đường kính tạo 12 dải bằng nhau
    final linePaint = Paint()
      ..color = const Color(0xFFC49000)
      ..strokeWidth = isLarge ? 1.5 : 0.9
      ..style = PaintingStyle.stroke;

    for (var i = 1; i <= 11; i++) {
      final vx = xLeft + i * stepX;
      canvas.drawLine(
        Offset(vx, centerY - radius),
        Offset(vx, centerY + radius),
        linePaint,
      );
    }

    // Vùng tô làm nổi bật phần tiếp xúc chạm đang chọn
    final hitWidth = 2 * radius * thickness;
    if (stroke.isFullFace || stroke.hitSide == HitSide.center) {
      canvas.drawCircle(
        yellowCenter,
        radius,
        Paint()
          ..color = const Color(0x44FFA000)
          ..style = PaintingStyle.fill,
      );
    } else if (stroke.hitSide == HitSide.right) {
      final highlightRect = Rect.fromLTRB(
        xRight - hitWidth,
        centerY - radius,
        xRight,
        centerY + radius,
      );
      canvas.clipRect(highlightRect);
      canvas.drawCircle(
        yellowCenter,
        radius,
        Paint()
          ..color = const Color(0x66FF8F00)
          ..style = PaintingStyle.fill,
      );
    } else if (stroke.hitSide == HitSide.left) {
      final highlightRect = Rect.fromLTRB(
        xLeft,
        centerY - radius,
        xLeft + hitWidth,
        centerY + radius,
      );
      canvas.clipRect(highlightRect);
      canvas.drawCircle(
        yellowCenter,
        radius,
        Paint()
          ..color = const Color(0x66FF8F00)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.restore();

    // Viền tròn bi vàng
    final yellowBorderPaint = Paint()
      ..color = const Color(0xFF8D6E63)
      ..strokeWidth = isLarge ? 1.8 : 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(yellowCenter, radius, yellowBorderPaint);

    // 3. VẼ BI TRẮNG CHỒNG TƯƠNG ĐỐI
    // Cách thể hiện nhất quán: dùng lớp trắng bán trong suốt cao cấp (alpha ~ 84% khi lệch, ~ 76% khi đồng tâm),
    // giúp người dùng luôn nhận biết rõ bi trắng chủ VÀ đồng thời nhìn thấy rõ bi vàng và 11 vạch chia bên dưới!
    final double whiteAlpha = (separationFactor.abs() < 1e-4) ? 0.76 : 0.84;
    final whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: whiteAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(whiteCenter, radius, whitePaint);

    // Viền bi trắng sắc nét
    final whiteBorderPaint = Paint()
      ..color = const Color(0xFF37474F)
      ..strokeWidth = isLarge ? 1.8 : 1.1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(whiteCenter, radius, whiteBorderPaint);

    // Khi đồng tâm (chính tâm hoặc tràn mặt 12/12): vẽ thêm viền ngoài màu cam nổi bật để phân biệt rõ cả 2 bi
    if (separationFactor.abs() < 1e-4) {
      final hintBorderPaint = Paint()
        ..color = const Color(0xFFFFA000)
        ..strokeWidth = isLarge ? 1.6 : 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(whiteCenter, radius + (isLarge ? 2.5 : 1.5), hintBorderPaint);
    }

    // 4. CHẤM MŨI CƠ ĐỎ TRÊN BI TRẮNG (DÙNG CHUNG PHÉP ĐỔI HÌNH HỌC VỚI ÉP PHÊ)
    final dotRadius = isLarge ? 4.5 : 2.5;
    final dotCenter = CueTipGeometry.tipDotCenter(
      ballCenter: whiteCenter,
      ballRadiusPx: radius,
      tipXMm: stroke.tipXMm,
      tipZMm: stroke.tipZMm,
      dotRadiusPx: dotRadius,
    );

    canvas.drawCircle(
      dotCenter,
      dotRadius,
      Paint()
        ..color = const Color(0xFFD32F2F)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      dotCenter,
      dotRadius,
      Paint()
        ..color = const Color(0xFF880E4F)
        ..strokeWidth = isLarge ? 1.0 : 0.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant HitThicknessPainter oldDelegate) {
    return oldDelegate.stroke != stroke || oldDelegate.isLarge != isLarge;
  }
}

/// Painter vẽ mặt bi trắng với hai trục chữ thập qua tâm, 4 vòng mức quy ước và chấm đỏ vị trí mũi cơ.
/// Khớp chính xác giá trị milimét quy ước với hình học hiển thị.
class CueTipPainter extends CustomPainter {
  final StrokeParameters stroke;
  final bool isLarge;

  const CueTipPainter(this.stroke, {this.isLarge = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final radius = min(size.width, size.height) / 2.0 - (isLarge ? 6.0 : 2.5);
    if (radius <= 0) return;

    // Nền bi trắng
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, whitePaint);

    // Viền bi
    final borderPaint = Paint()
      ..color = const Color(0xFF546E7A)
      ..strokeWidth = isLarge ? 2.0 : 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, borderPaint);

    // Hai đường chữ thập vuông góc qua tâm
    final axisPaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..strokeWidth = isLarge ? 1.2 : 0.8
      ..style = PaintingStyle.stroke;

    // Trục dọc
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      axisPaint,
    );
    // Trục ngang
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      axisPaint,
    );

    // 4 vòng tròn đồng tâm khớp đúng 4 mức quy ước (1 mức = 3.84375 mm, mức 4 = 15.375 mm)
    if (isLarge) {
      final ringPaint = Paint()
        ..color = const Color(0x3890A4AE)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      for (var lvl = 1; lvl <= 4; lvl++) {
        final rLvl = CueTipGeometry.levelRadiusPx(lvl, radius);
        canvas.drawCircle(center, rLvl, ringPaint);
      }
    }

    // Chấm đỏ vị trí mũi cơ (dùng chung CueTipGeometry.tipDotCenter)
    final dotRadius = isLarge ? 5.5 : 2.8;
    final dotCenter = CueTipGeometry.tipDotCenter(
      ballCenter: center,
      ballRadiusPx: radius,
      tipXMm: stroke.tipXMm,
      tipZMm: stroke.tipZMm,
      dotRadiusPx: dotRadius,
    );

    canvas.drawCircle(
      dotCenter,
      dotRadius,
      Paint()
        ..color = const Color(0xFFD32F2F)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      dotCenter,
      dotRadius,
      Paint()
        ..color = const Color(0xFF880E4F)
        ..strokeWidth = isLarge ? 1.2 : 0.6
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CueTipPainter oldDelegate) {
    return oldDelegate.stroke != stroke || oldDelegate.isLarge != isLarge;
  }
}

/// Widget hiển thị biểu tượng Chạm trái ở thanh dưới
class HitThicknessPreviewWidget extends StatelessWidget {
  final StrokeParameters stroke;
  final VoidCallback? onTap;

  const HitThicknessPreviewWidget({
    super.key,
    required this.stroke,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Chạm trái: ${stroke.thicknessSummary}',
      child: InkWell(
        key: const Key('bottom_hit_thickness_button'),
        borderRadius: BorderRadius.circular(16.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomPaint(
                size: const Size(66.0, 34.0),
                painter: HitThicknessPainter(stroke, isLarge: false),
              ),
              const SizedBox(height: 1.0),
              Text(
                stroke.isFullFace
                    ? 'Tràn mặt'
                    : (stroke.thicknessMode == HitThicknessMode.twelfths
                        ? '${stroke.twelfthCount}/12'
                        : stroke.thicknessSummary),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10.0,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget hiển thị biểu tượng Ép phê ở thanh dưới
class CueTipPreviewWidget extends StatelessWidget {
  final StrokeParameters stroke;
  final VoidCallback? onTap;

  const CueTipPreviewWidget({
    super.key,
    required this.stroke,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ép phê: ${stroke.horizontalTipLabel}, ${stroke.verticalTipLabel}',
      child: InkWell(
        key: const Key('bottom_cue_tip_button'),
        borderRadius: BorderRadius.circular(16.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomPaint(
                size: const Size(34.0, 34.0),
                painter: CueTipPainter(stroke, isLarge: false),
              ),
              const SizedBox(height: 1.0),
              const Text(
                'Ép phê',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget hiển thị biểu tượng Lực đánh ở thanh dưới
class ForcePreviewWidget extends StatelessWidget {
  final StrokeParameters stroke;
  final VoidCallback? onTap;

  const ForcePreviewWidget({
    super.key,
    required this.stroke,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Lực đánh: ${stroke.forceDisplay}',
      child: InkWell(
        key: const Key('bottom_force_button'),
        borderRadius: BorderRadius.circular(16.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bolt,
                    color: Colors.amberAccent,
                    size: 16.0,
                  ),
                  const SizedBox(width: 2.0),
                  Text(
                    stroke.forceDisplay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1.0),
              const Text(
                'Lực',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog chỉnh sửa Chạm trái (Độ dày 12 phần, má chạm, tràn mặt)
/// Bảo toàn tuyệt đối độ dày cũ (eighths / exact), chỉ chuyển sang k/12 khi người dùng chủ động kéo slider.
class HitThicknessDialog extends StatefulWidget {
  final StrokeParameters initialStroke;
  final ValueChanged<StrokeParameters> onApply;

  const HitThicknessDialog({
    super.key,
    required this.initialStroke,
    required this.onApply,
  });

  @override
  State<HitThicknessDialog> createState() => _HitThicknessDialogState();
}

class _HitThicknessDialogState extends State<HitThicknessDialog> {
  late StrokeParameters _current;
  late int _sliderTwelfths;
  bool _userChangedThickness = false;

  @override
  void initState() {
    super.initState();
    // BẢO TOÀN ĐỘ DÀY CŨ: Không đổi thicknessMode hoặc làm tròn trong initState!
    _current = widget.initialStroke;
    final curFrac = _current.effectiveThicknessFraction;
    _sliderTwelfths = (_current.thicknessMode == HitThicknessMode.twelfths)
        ? _current.twelfthCount
        : (curFrac * 12.0).round().clamp(1, 12);
    _userChangedThickness = false;
  }

  @override
  Widget build(BuildContext context) {
    final isLegacyEighths = _current.thicknessMode == HitThicknessMode.eighths && !_userChangedThickness;
    final isExactFraction = _current.thicknessMode == HitThicknessMode.exact && !_userChangedThickness;

    return AlertDialog(
      title: const Text('Chạm trái / Độ dày tiếp xúc'),
      content: SizedBox(
        width: 320.0,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Preview trực quan phóng to
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2124),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(180.0, 72.0),
                    painter: HitThicknessPainter(_current, isLarge: true),
                  ),
                ),
              ),
              const SizedBox(height: 6.0),
              Text(
                _current.thicknessSummary,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                textAlign: TextAlign.center,
              ),

              // Chỉ báo chế độ cũ (nếu có)
              if (isLegacyEighths) ...[
                const SizedBox(height: 4.0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Đang giữ giá trị gốc: ${_current.eighthCount}/8 bi (chưa chuyển sang 12 phần)',
                    style: const TextStyle(fontSize: 11.0, color: Colors.amber),
                    textAlign: TextAlign.center,
                  ),
                ),
              ] else if (isExactFraction) ...[
                const SizedBox(height: 4.0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Đang giữ giá trị chính xác: ${_current.exactThicknessValue ?? _current.effectiveThicknessFraction}',
                    style: const TextStyle(fontSize: 11.0, color: Colors.tealAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const Divider(height: 18.0),

              // Chọn má chạm
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Phía chạm má bi:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0),
                ),
              ),
              const SizedBox(height: 6.0),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8.0,
                runSpacing: 6.0,
                children: [
                  ChoiceChip(
                    key: const Key('hit_side_left'),
                    label: const Text('Má trái'),
                    selected: _current.hitSide == HitSide.left,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _current = _current.copyWith(hitSide: HitSide.left));
                      }
                    },
                  ),
                  ChoiceChip(
                    key: const Key('hit_side_center'),
                    label: const Text('Chính tâm'),
                    selected: _current.hitSide == HitSide.center,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _current = _current.copyWith(hitSide: HitSide.center));
                      }
                    },
                  ),
                  ChoiceChip(
                    key: const Key('hit_side_right'),
                    label: const Text('Má phải'),
                    selected: _current.hitSide == HitSide.right,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _current = _current.copyWith(hitSide: HitSide.right));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8.0),

              // Tràn mặt (toàn phần)
              SwitchListTile(
                key: const Key('hit_thickness_full_face_switch'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Chạm tràn mặt (toàn phần)'),
                subtitle: const Text('Bật/tắt vẫn giữ nguyên tỷ lệ và má đã chọn'),
                value: _current.isFullFace,
                onChanged: (val) {
                  setState(() => _current = _current.copyWith(isFullFace: val));
                },
              ),

              // Slider 12 phần: Chỉ khi người dùng chủ động kéo mới đổi sang twelfths
              if (!_current.isFullFace) ...[
                const SizedBox(height: 6.0),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _userChangedThickness || _current.thicknessMode == HitThicknessMode.twelfths
                        ? 'Độ dày chạm: $_sliderTwelfths/12 bi'
                        : 'Chỉnh sang quy ước 12 phần: $_sliderTwelfths/12 bi',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                  ),
                ),
                Slider(
                  key: const Key('hit_thickness_twelfths_slider'),
                  value: _sliderTwelfths.toDouble(),
                  min: 1.0,
                  max: 12.0,
                  divisions: 11,
                  label: '$_sliderTwelfths/12',
                  onChanged: (val) {
                    setState(() {
                      _userChangedThickness = true;
                      _sliderTwelfths = val.round();
                      _current = _current.copyWith(
                        thicknessMode: HitThicknessMode.twelfths,
                        twelfthCount: _sliderTwelfths,
                      );
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('hit_thickness_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('hit_thickness_apply_button'),
          onPressed: () {
            // Nếu người dùng không chủ động chỉnh độ dày, giữ nguyên mode và giá trị gốc!
            widget.onApply(_current);
            Navigator.of(context).pop();
          },
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }
}

/// Dialog chỉnh sửa Ép phê / Điểm mũi cơ (kéo chạm trực quan, nhập X/Z, chọn 4 mức)
/// Dùng chung CueTipGeometry, khớp đúng các vòng mức quy ước, bổ sung nhập X/Z chính xác.
class CueTipDialog extends StatefulWidget {
  final StrokeParameters initialStroke;
  final ValueChanged<StrokeParameters> onApply;

  const CueTipDialog({
    super.key,
    required this.initialStroke,
    required this.onApply,
  });

  @override
  State<CueTipDialog> createState() => _CueTipDialogState();
}

class _CueTipDialogState extends State<CueTipDialog> {
  static const double maxTipMm = CueTipConvention.referenceBallRadiusMm - 1.0; // 29.75 mm

  late StrokeParameters _current;
  late TextEditingController _xCtrl;
  late TextEditingController _zCtrl;
  final FocusNode _xFocus = FocusNode();
  final FocusNode _zFocus = FocusNode();

  String? _xError;
  String? _zError;
  String? _normalizationNotice;

  @override
  void initState() {
    super.initState();
    _current = widget.initialStroke;
    _xCtrl = TextEditingController(text: _formatMmValue(_current.tipXMm));
    _zCtrl = TextEditingController(text: _formatMmValue(_current.tipZMm));

    _xFocus.addListener(() {
      if (!_xFocus.hasFocus) {
        _normalizeTextField(isX: true);
      }
    });
    _zFocus.addListener(() {
      if (!_zFocus.hasFocus) {
        _normalizeTextField(isX: false);
      }
    });

    _validateFields();
  }

  @override
  void dispose() {
    _xFocus.dispose();
    _zFocus.dispose();
    _xCtrl.dispose();
    _zCtrl.dispose();
    super.dispose();
  }

  static String _formatMmValue(double val) {
    if (val.abs() < 1e-6) return '0';
    var s = val.toString();
    if (s.contains('.')) {
      while (s.endsWith('0')) {
        s = s.substring(0, s.length - 1);
      }
      if (s.endsWith('.')) {
        s = s.substring(0, s.length - 1);
      }
    }
    return s;
  }

  void _normalizeTextField({required bool isX}) {
    if (isX) {
      if (_xCtrl.text.contains(',')) {
        final norm = _xCtrl.text.replaceAll(',', '.');
        _xCtrl.text = norm;
      }
    } else {
      if (_zCtrl.text.contains(',')) {
        final norm = _zCtrl.text.replaceAll(',', '.');
        _zCtrl.text = norm;
      }
    }
    _validateFields();
  }

  void _validateFields() {
    final xRaw = _xCtrl.text.trim();
    final zRaw = _zCtrl.text.trim();

    String? xErr;
    double? xParsed;
    if (xRaw.isEmpty) {
      xErr = 'Không được để trống';
    } else {
      final xNorm = xRaw.replaceAll(',', '.');
      final xLower = xNorm.toLowerCase();
      if (xLower == 'nan') {
        xErr = 'Không chấp nhận giá trị NaN';
      } else if (xLower.contains('inf')) {
        xErr = 'Không chấp nhận giá trị Infinity';
      } else {
        final p = double.tryParse(xNorm);
        if (p == null) {
          xErr = 'Vui lòng nhập số hợp lệ';
        } else if (p.isNaN) {
          xErr = 'Không chấp nhận giá trị NaN';
        } else if (!p.isFinite) {
          xErr = 'Không chấp nhận giá trị Infinity';
        } else if (p.abs() > maxTipMm) {
          xErr = 'Vượt quá mặt bi (tối đa ±${maxTipMm.toStringAsFixed(2)} mm)';
        } else {
          xParsed = p;
        }
      }
    }

    String? zErr;
    double? zParsed;
    if (zRaw.isEmpty) {
      zErr = 'Không được để trống';
    } else {
      final zNorm = zRaw.replaceAll(',', '.');
      final zLower = zNorm.toLowerCase();
      if (zLower == 'nan') {
        zErr = 'Không chấp nhận giá trị NaN';
      } else if (zLower.contains('inf')) {
        zErr = 'Không chấp nhận giá trị Infinity';
      } else {
        final p = double.tryParse(zNorm);
        if (p == null) {
          zErr = 'Vui lòng nhập số hợp lệ';
        } else if (p.isNaN) {
          zErr = 'Không chấp nhận giá trị NaN';
        } else if (!p.isFinite) {
          zErr = 'Không chấp nhận giá trị Infinity';
        } else if (p.abs() > maxTipMm) {
          zErr = 'Vượt quá mặt bi (tối đa ±${maxTipMm.toStringAsFixed(2)} mm)';
        } else {
          zParsed = p;
        }
      }
    }

    // Nếu cả x và z đều hợp lệ độc lập, kiểm tra bán kính khoảng cách tổng thể
    if (xErr == null && zErr == null && xParsed != null && zParsed != null) {
      final dist = sqrt(xParsed * xParsed + zParsed * zParsed);
      if (dist > maxTipMm) {
        zErr = 'Khoảng cách đến tâm (${dist.toStringAsFixed(2)} mm) vượt quá bán kính mặt bi (${maxTipMm.toStringAsFixed(2)} mm)';
      } else {
        _current = _current.copyWith(tipXMm: xParsed, tipZMm: zParsed);
      }
    }

    setState(() {
      _xError = xErr;
      _zError = zErr;
      if (xRaw.contains(',') || zRaw.contains(',')) {
        _normalizationNotice = 'Đã nhận dấu phẩy và chuẩn hóa thành số thập phân hợp lệ.';
      } else if (_normalizationNotice != null && !xRaw.contains(',') && !zRaw.contains(',')) {
        _normalizationNotice = null;
      }
    });
  }

  void _handleTouch(Offset localPos, double ballSize) {
    final center = Offset(ballSize / 2.0, ballSize / 2.0);
    final radius = ballSize / 2.0 - 6.0;
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;

    // Đổi pixel -> mm dùng CueTipGeometry duy nhất
    var xMm = CueTipGeometry.pxToMm(dx, radius);
    var zMm = -CueTipGeometry.pxToMm(dy, radius);

    // Dùng cùng quy tắc giới hạn maxTipMm
    final dist = sqrt(xMm * xMm + zMm * zMm);
    String? notice;
    if (dist > maxTipMm && dist > 1e-6) {
      xMm = xMm * (maxTipMm / dist);
      zMm = zMm * (maxTipMm / dist);
      notice = 'Đã chuẩn hóa vị trí mũi cơ trong phạm vi mặt bi (${maxTipMm.toStringAsFixed(2)} mm)';
    }

    setState(() {
      _current = _current.copyWith(tipXMm: xMm, tipZMm: zMm);
      _xCtrl.text = _formatMmValue(xMm);
      _zCtrl.text = _formatMmValue(zMm);
      _xError = null;
      _zError = null;
      _normalizationNotice = notice;
    });
  }

  void _setLevel({int? xLevel, int? zLevel}) {
    // Giá trị chính xác theo CueTipConvention, không làm tròn
    final newX = xLevel != null
        ? (xLevel * CueTipConvention.fourLevelStepMm)
        : _current.tipXMm;
    final newZ = zLevel != null
        ? (zLevel * CueTipConvention.fourLevelStepMm)
        : _current.tipZMm;

    setState(() {
      _current = _current.copyWith(tipXMm: newX, tipZMm: newZ);
      _xCtrl.text = _formatMmValue(newX);
      _zCtrl.text = _formatMmValue(newZ);
      _xError = null;
      _zError = null;
      _normalizationNotice = null;
    });
  }

  void _apply() {
    _normalizeTextField(isX: true);
    _normalizeTextField(isX: false);
    _validateFields();
    if (_xError != null || _zError != null) return;

    final xNorm = _xCtrl.text.trim().replaceAll(',', '.');
    final zNorm = _zCtrl.text.trim().replaceAll(',', '.');
    final xParsed = double.tryParse(xNorm) ?? _current.tipXMm;
    final zParsed = double.tryParse(zNorm) ?? _current.tipZMm;

    final updated = _current.copyWith(
      tipXMm: xParsed,
      tipZMm: zParsed,
    );
    widget.onApply(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const double ballSize = 130.0;
    final canApply = _xError == null &&
        _zError == null &&
        _xCtrl.text.trim().isNotEmpty &&
        _zCtrl.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('Ép phê / Điểm mũi cơ'),
      content: SizedBox(
        width: 320.0,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mặt bi tương tác kéo thả
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2124),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.white24),
                ),
                child: GestureDetector(
                  key: const Key('cue_tip_interactive_ball'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _handleTouch(d.localPosition, ballSize),
                  onPanDown: (d) => _handleTouch(d.localPosition, ballSize),
                  onPanUpdate: (d) => _handleTouch(d.localPosition, ballSize),
                  child: CustomPaint(
                    size: const Size(ballSize, ballSize),
                    painter: CueTipPainter(_current, isLarge: true),
                  ),
                ),
              ),
              const SizedBox(height: 10.0),

              // Hiển thị quy ước 4 mức
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  children: [
                    Text(
                      'Ngang (X): ${_current.horizontalTipLabel}',
                      key: const Key('cue_tip_x_summary'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'Đứng (Z): ${_current.verticalTipLabel}',
                      key: const Key('cue_tip_z_summary'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                    ),
                  ],
                ),
              ),
              if (_normalizationNotice != null) ...[
                const SizedBox(height: 6.0),
                Text(
                  _normalizationNotice!,
                  key: const Key('cue_tip_normalization_notice'),
                  style: const TextStyle(fontSize: 11.0, color: Colors.amber),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 10.0),

              // Bổ sung ô nhập X và Z chính xác (mm)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('cue_tip_x_input'),
                      controller: _xCtrl,
                      focusNode: _xFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(
                        labelText: 'X (mm)',
                        hintText: '- trái / + phải',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _xError,
                      ),
                      onChanged: (_) => _validateFields(),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: TextField(
                      key: const Key('cue_tip_z_input'),
                      controller: _zCtrl,
                      focusNode: _zFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(
                        labelText: 'Z (mm)',
                        hintText: '- dưới / + trên',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _zError,
                      ),
                      onChanged: (_) => _validateFields(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10.0),

              // Chọn nhanh các mức ngang chuẩn (đủ 4 mức cho trái/phải và tâm)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Chọn nhanh ngang (Trái 1..4, Phải 1..4):', style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4.0),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4.0,
                runSpacing: 4.0,
                children: [
                  ActionChip(
                    key: const Key('cue_tip_chip_left_4'),
                    label: const Text('Trái 4'),
                    onPressed: () => _setLevel(xLevel: -4),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_left_3'),
                    label: const Text('Trái 3'),
                    onPressed: () => _setLevel(xLevel: -3),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_left_2'),
                    label: const Text('Trái 2'),
                    onPressed: () => _setLevel(xLevel: -2),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_left_1'),
                    label: const Text('Trái 1'),
                    onPressed: () => _setLevel(xLevel: -1),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_x_center'),
                    label: const Text('Tâm'),
                    onPressed: () => _setLevel(xLevel: 0),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_right_1'),
                    label: const Text('Phải 1'),
                    onPressed: () => _setLevel(xLevel: 1),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_right_2'),
                    label: const Text('Phải 2'),
                    onPressed: () => _setLevel(xLevel: 2),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_right_3'),
                    label: const Text('Phải 3'),
                    onPressed: () => _setLevel(xLevel: 3),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_right_4'),
                    label: const Text('Phải 4'),
                    onPressed: () => _setLevel(xLevel: 4),
                  ),
                ],
              ),
              const SizedBox(height: 10.0),

              // Chọn nhanh các mức đứng chuẩn (đủ 4 mức cho trên/dưới và tâm)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Chọn nhanh đứng (Dưới 1..4, Trên 1..4):', style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4.0),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4.0,
                runSpacing: 4.0,
                children: [
                  ActionChip(
                    key: const Key('cue_tip_chip_down_4'),
                    label: const Text('Dưới 4'),
                    onPressed: () => _setLevel(zLevel: -4),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_down_3'),
                    label: const Text('Dưới 3'),
                    onPressed: () => _setLevel(zLevel: -3),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_down_2'),
                    label: const Text('Dưới 2'),
                    onPressed: () => _setLevel(zLevel: -2),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_down_1'),
                    label: const Text('Dưới 1'),
                    onPressed: () => _setLevel(zLevel: -1),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_z_center'),
                    label: const Text('Tâm'),
                    onPressed: () => _setLevel(zLevel: 0),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_up_1'),
                    label: const Text('Trên 1'),
                    onPressed: () => _setLevel(zLevel: 1),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_up_2'),
                    label: const Text('Trên 2'),
                    onPressed: () => _setLevel(zLevel: 2),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_up_3'),
                    label: const Text('Trên 3'),
                    onPressed: () => _setLevel(zLevel: 3),
                  ),
                  ActionChip(
                    key: const Key('cue_tip_chip_up_4'),
                    label: const Text('Trên 4'),
                    onPressed: () => _setLevel(zLevel: 4),
                  ),
                ],
              ),
              const SizedBox(height: 10.0),

              // Nút về tâm
              OutlinedButton.icon(
                key: const Key('cue_tip_reset_center_button'),
                icon: const Icon(Icons.filter_center_focus, size: 16.0),
                label: const Text('Về chính tâm bi (0, 0)'),
                onPressed: () => _setLevel(xLevel: 0, zLevel: 0),
              ),

              const SizedBox(height: 10.0),
              // Chọn kích thước đầu cơ
              const Text(
                'Đường kính đầu cơ:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0),
              ),
              const SizedBox(height: 4.0),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6.0,
                runSpacing: 4.0,
                children: CueTipConvention.standardTipDiametersMm.map((d) {
                  final isSel = (_current.tipDiameterMm - d).abs() < 0.01;
                  return ChoiceChip(
                    label: Text('$d mm'),
                    selected: isSel,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _current = _current.copyWith(tipDiameterMm: d));
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cue_tip_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('cue_tip_apply_button'),
          onPressed: canApply ? _apply : null,
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }
}

/// Dialog chỉnh sửa Lực đánh (0..100%, slider + ô nhập số, bảo toàn ghi chú lực văn bản cũ)
class ForceDialog extends StatefulWidget {
  final StrokeParameters initialStroke;
  final ValueChanged<StrokeParameters> onApply;

  const ForceDialog({
    super.key,
    required this.initialStroke,
    required this.onApply,
  });

  @override
  State<ForceDialog> createState() => _ForceDialogState();
}

class _ForceDialogState extends State<ForceDialog> {
  late int _forceVal;
  late TextEditingController _textCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _forceVal = widget.initialStroke.forcePercent ?? 50;
    _textCtrl = TextEditingController(text: _forceVal.toString());
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null || parsed < 0 || parsed > 100) {
      setState(() {
        _error = 'Lực phải nằm trong khoảng từ 0% đến 100%.';
      });
    } else {
      setState(() {
        _error = null;
        _forceVal = parsed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lực đánh'),
      content: SizedBox(
        width: 300.0,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bolt, color: Colors.amber, size: 28.0),
                  const SizedBox(width: 8.0),
                  Text(
                    '$_forceVal%',
                    style: const TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              Slider(
                key: const Key('force_slider'),
                value: _forceVal.toDouble().clamp(0.0, 100.0),
                min: 0.0,
                max: 100.0,
                divisions: 100,
                label: '$_forceVal%',
                onChanged: (val) {
                  final rounded = val.round();
                  setState(() {
                    _forceVal = rounded;
                    _textCtrl.text = rounded.toString();
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 12.0),
              TextField(
                key: const Key('force_input_field'),
                controller: _textCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nhập số phần trăm (0 - 100)',
                  suffixText: '%',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _onTextChanged,
              ),
              if (widget.initialStroke.forceText.trim().isNotEmpty) ...[
                const SizedBox(height: 10.0),
                Text(
                  'Ghi chú lực hiện tại: "${widget.initialStroke.forceText.trim()}" (được bảo toàn)',
                  style: const TextStyle(fontSize: 12.0, color: Colors.white70, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('force_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('force_apply_button'),
          onPressed: _error != null
              ? null
              : () {
                  // BẢO TOÀN GHI CHÚ LỰC BẰNG VĂN BẢN KHI CHỌN LỰC PHẦN TRĂM
                  final updated = widget.initialStroke.copyWith(
                    forcePercent: _forceVal,
                    forceText: widget.initialStroke.forceText,
                  );
                  widget.onApply(updated);
                  Navigator.of(context).pop();
                },
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }
}
