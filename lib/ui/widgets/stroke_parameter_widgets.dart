import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/stroke_parameters.dart';

/// Painter vẽ bi vàng chia 12 vạch sọc đứng (cách đều ngang đường kính)
/// và bi trắng chồng lên theo tỷ lệ độ dày chạm, má chạm, kèm chấm mũi cơ đỏ.
class HitThicknessPainter extends CustomPainter {
  final StrokeParameters stroke;
  final bool isLarge;

  const HitThicknessPainter(this.stroke, {this.isLarge = false});

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = isLarge ? 28.0 : 15.0;
    final double yellowCenterX = isLarge ? 42.0 : 20.0;
    final double centerY = size.height / 2;
    final yellowCenter = Offset(yellowCenterX, centerY);

    // 1. VẼ BI VÀNG VỚI 12 PHẦN BẰNG NHAU THEO CHIỀU NGANG ĐƯỜNG KÍNH
    final double xLeft = yellowCenterX - radius;
    final double xRight = yellowCenterX + radius;
    final double stepX = (2 * radius) / 12.0;

    final yellowPath = Path()
      ..addOval(Rect.fromCircle(center: yellowCenter, radius: radius));

    canvas.save();
    canvas.clipPath(yellowPath);

    // Nền bi vàng tươi
    final yellowPaint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(yellowCenter, radius, yellowPaint);

    // 11 vạch thẳng đứng, cách đều nhau theo đường kính
    final linePaint = Paint()
      ..color = const Color(0xFFC49000)
      ..strokeWidth = isLarge ? 1.5 : 0.8
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
    final thickness = stroke.effectiveThicknessFraction;
    final hitWidth = 2 * radius * thickness;

    if (stroke.isFullFace) {
      final highlightPaint = Paint()
        ..color = const Color(0x55FFA000)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(yellowCenter, radius, highlightPaint);
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
    } else {
      // Chính tâm
      final highlightRect = Rect.fromLTRB(
        yellowCenterX - hitWidth / 2,
        centerY - radius,
        yellowCenterX + hitWidth / 2,
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
      ..strokeWidth = isLarge ? 2.0 : 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(yellowCenter, radius, yellowBorderPaint);

    // 2. VẼ BI TRẮNG CHỒNG TƯƠNG ĐỐI
    double whiteCenterX = yellowCenterX;
    if (stroke.isFullFace) {
      whiteCenterX = yellowCenterX;
    } else if (stroke.hitSide == HitSide.right) {
      // Bi trắng ở phía bên phải, chồng lấn theo độ dày chạm
      final deltaX = 2 * radius * (1.0 - thickness);
      whiteCenterX = yellowCenterX + deltaX;
    } else if (stroke.hitSide == HitSide.left) {
      // Bi trắng ở phía bên trái
      final deltaX = 2 * radius * (1.0 - thickness);
      whiteCenterX = yellowCenterX - deltaX;
    } else {
      whiteCenterX = yellowCenterX;
    }

    final whiteCenter = Offset(whiteCenterX, centerY);

    // Nền bi trắng
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(whiteCenter, radius, whitePaint);

    // Viền bi trắng
    final whiteBorderPaint = Paint()
      ..color = const Color(0xFF37474F)
      ..strokeWidth = isLarge ? 2.0 : 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(whiteCenter, radius, whiteBorderPaint);

    // 3. CHẤM MŨI CƠ ĐỎ TRÊN BI TRẮNG (DÙNG CHUNG NGUỒN VỚI ÉP PHÊ)
    const refRadiusMm = CueTipConvention.referenceBallRadiusMm;
    final maxOffsetPx = radius * 0.82;
    final offX = (stroke.tipXMm / refRadiusMm) * maxOffsetPx;
    final offZ = (stroke.tipZMm / refRadiusMm) * maxOffsetPx;
    var dotCenter = Offset(whiteCenter.dx + offX, whiteCenter.dy - offZ);

    final dist = (dotCenter - whiteCenter).distance;
    final maxDist = radius - (isLarge ? 6.0 : 3.0);
    if (dist > maxDist && dist > 1e-6) {
      dotCenter = whiteCenter + (dotCenter - whiteCenter) * (maxDist / dist);
    }

    final dotRadius = isLarge ? 5.0 : 2.5;
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

/// Painter vẽ mặt bi trắng với hai trục chữ thập qua tâm và chấm đỏ vị trí mũi cơ.
class CueTipPainter extends CustomPainter {
  final StrokeParameters stroke;
  final bool isLarge;

  const CueTipPainter(this.stroke, {this.isLarge = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - (isLarge ? 4.0 : 2.0);

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

    // Khi xem phóng to trong dialog: vẽ 4 vòng tròn đồng tâm mờ biểu thị 4 mức quy ước
    if (isLarge) {
      final ringPaint = Paint()
        ..color = const Color(0x3390A4AE)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      for (var lvl = 1; lvl <= 4; lvl++) {
        final rLvl = radius * 0.85 * (lvl / 4.0);
        canvas.drawCircle(center, rLvl, ringPaint);
      }
    }

    // Chấm đỏ vị trí mũi cơ
    const refRadiusMm = CueTipConvention.referenceBallRadiusMm;
    final maxOffsetPx = radius * 0.85;
    final offX = (stroke.tipXMm / refRadiusMm) * maxOffsetPx;
    final offZ = (stroke.tipZMm / refRadiusMm) * maxOffsetPx;
    var dotCenter = Offset(center.dx + offX, center.dy - offZ);

    final dist = (dotCenter - center).distance;
    final maxDist = radius - (isLarge ? 6.0 : 3.0);
    if (dist > maxDist && dist > 1e-6) {
      dotCenter = center + (dotCenter - center) * (maxDist / dist);
    }

    final dotRadius = isLarge ? 6.0 : 3.0;
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
                size: const Size(60.0, 34.0),
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

  @override
  void initState() {
    super.initState();
    _current = widget.initialStroke;
    // Nếu chưa ở chế độ twelfths, chuyển sang twelfths nhưng giữ nguyên tỷ lệ gần nhất
    if (_current.thicknessMode != HitThicknessMode.twelfths) {
      final curFrac = _current.effectiveThicknessFraction;
      final k = (curFrac * 12.0).round().clamp(1, 12);
      _current = _current.copyWith(
        thicknessMode: HitThicknessMode.twelfths,
        twelfthCount: k,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2124),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.white24),
                ),
                child: CustomPaint(
                  size: const Size(130.0, 68.0),
                  painter: HitThicknessPainter(_current, isLarge: true),
                ),
              ),
              const SizedBox(height: 6.0),
              Text(
                _current.thicknessSummary,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                textAlign: TextAlign.center,
              ),
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

              // Slider 12 phần
              if (!_current.isFullFace) ...[
                const SizedBox(height: 6.0),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Độ dày chạm: ${_current.twelfthCount}/12 bi',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                  ),
                ),
                Slider(
                  key: const Key('hit_thickness_twelfths_slider'),
                  value: _current.twelfthCount.toDouble(),
                  min: 1.0,
                  max: 12.0,
                  divisions: 11,
                  label: '${_current.twelfthCount}/12',
                  onChanged: (val) {
                    setState(() {
                      _current = _current.copyWith(
                        thicknessMode: HitThicknessMode.twelfths,
                        twelfthCount: val.round(),
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
            widget.onApply(_current);
            Navigator.of(context).pop();
          },
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }
}

/// Dialog chỉnh sửa Ép phê / Điểm mũi cơ (kéo chấm trên mặt bi hoặc chọn 4 mức)
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
  late StrokeParameters _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialStroke;
  }

  void _handleTouch(Offset localPos, double ballSize) {
    final center = ballSize / 2;
    final radius = center - 4.0;
    final dx = localPos.dx - center;
    final dy = localPos.dy - center;

    const refRadiusMm = CueTipConvention.referenceBallRadiusMm;
    final maxOffsetPx = radius * 0.85;

    // Đổi pixel -> mm
    var xMm = (dx / maxOffsetPx) * refRadiusMm;
    var zMm = -(dy / maxOffsetPx) * refRadiusMm;

    // Giới hạn trong 4 mức quy ước (-15.375 .. +15.375)
    xMm = xMm.clamp(-CueTipConvention.fourLevelMaxMm, CueTipConvention.fourLevelMaxMm);
    zMm = zMm.clamp(-CueTipConvention.fourLevelMaxMm, CueTipConvention.fourLevelMaxMm);

    setState(() {
      _current = _current.copyWith(tipXMm: xMm, tipZMm: zMm);
    });
  }

  @override
  Widget build(BuildContext context) {
    const double ballSize = 130.0;

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
            const SizedBox(height: 12.0),
            // Hiển thị quy ước 4 mức
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                children: [
                  Text(
                    'Ngang (X): ${_current.horizontalTipLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Đứng (Z): ${_current.verticalTipLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12.0),

            // Nút về tâm
            OutlinedButton.icon(
              key: const Key('cue_tip_reset_center_button'),
              icon: const Icon(Icons.filter_center_focus, size: 16.0),
              label: const Text('Về chính tâm bi (0, 0)'),
              onPressed: () {
                setState(() {
                  _current = _current.copyWith(tipXMm: 0.0, tipZMm: 0.0);
                });
              },
            ),

            const SizedBox(height: 12.0),
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
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Text('$d mm'),
                    selected: isSel,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _current = _current.copyWith(tipDiameterMm: d));
                      }
                    },
                  ),
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
          onPressed: () {
            widget.onApply(_current);
            Navigator.of(context).pop();
          },
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }
}

/// Dialog chỉnh sửa Lực đánh (0..100%, slider + ô nhập số, chặn ngoài miền)
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
                    _error = null;
                    _textCtrl.text = rounded.toString();
                  });
                },
              ),
              const SizedBox(height: 8.0),
              TextField(
                key: const Key('force_number_input'),
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
                  final updated = widget.initialStroke.copyWith(
                    forcePercent: _forceVal,
                    forceText: '$_forceVal%',
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
