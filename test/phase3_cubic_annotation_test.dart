import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/geometry/path_geometry.dart';
import 'package:libre_billiard_notebook/geometry/table_geometry.dart';
import 'package:libre_billiard_notebook/models/models.dart';
import 'package:libre_billiard_notebook/repositories/scene_storage.dart';
import 'package:libre_billiard_notebook/state/table_editor_controller.dart';
import 'package:libre_billiard_notebook/ui/screens/table_stage_screen.dart';

void main() {
  group('Phase 3 — Hình học Bézier bậc ba, tách/sửa đoạn, mũi tên & biên', () {
    test('Sửa đoạn thẳng không làm mất cubic bên cạnh; kéo bi liên kết bảo toàn cubic',
        () {
      final mixed = GuidePath(
        id: 'path_mixed',
        ownerBallId: 'ball_white',
        startAnchorBallId: 'ball_white',
        segments: const [
          PathSegment.line(
            start: DiagramPoint(94, 94),
            end: DiagramPoint(60, 180),
          ),
          PathSegment.cubic(
            start: DiagramPoint(60, 180),
            end: DiagramPoint(130, 260),
            control1: DiagramPoint(65, 230),
            control2: DiagramPoint(110, 270),
          ),
          PathSegment.line(
            start: DiagramPoint(130, 260),
            end: DiagramPoint(150, 320),
          ),
        ],
      );

      final scene = DiagramScene.defaultInitial(id: 'mixed_test').withPaths([mixed]);
      final controller = TableEditorController(initialScene: scene);

      // 1. Kéo bi trắng có liên kết -> chỉ đoạn 0 cập nhật đầu, đoạn 1 vẫn là cubic nguyên vẹn
      controller.setBallPosition('ball_white', const DiagramPoint(100, 110));
      var updated = controller.paths.first;
      expect(updated.segments[0].type, SegmentType.line);
      expect(updated.segments[0].start, const DiagramPoint(100, 110));
      expect(updated.segments[1].type, SegmentType.cubic);
      expect(updated.segments[1].control1, const DiagramPoint(65, 230));
      expect(updated.segments[1].control2, const DiagramPoint(110, 270));
      expect(updated.segments[2].type, SegmentType.line);

      // 2. Chèn điểm trên đoạn thẳng 0 -> chia đôi đoạn 0, đoạn cong vẫn giữ nguyên là cubic
      controller.selectPath(updated.id, segmentIndex: 0);
      expect(controller.insertVertexOnSelectedPath(segmentIndex: 0), isTrue);
      updated = controller.paths.first;
      expect(updated.segments.length, 4);
      expect(updated.segments[0].type, SegmentType.line);
      expect(updated.segments[1].type, SegmentType.line);
      expect(updated.segments[2].type, SegmentType.cubic);
      expect(updated.segments[2].control1, const DiagramPoint(65, 230));
      expect(updated.segments[3].type, SegmentType.line);

      // 3. Thử xóa điểm nối ngay sát đoạn cong (vertex 2) -> từ chối rõ ràng, không âm thầm biến dạng
      controller.selectPath(updated.id, vertexIndex: 2);
      final delErr = controller.deleteSelectedVertex();
      expect(delErr, isNotNull);
      expect(delErr, contains('đoạn cong'));
      expect(controller.paths.first.segments.length, 4);

      // 4. Xóa điểm nối giữa 2 đoạn thẳng (vertex 1) -> được phép, cubic kế bên vẫn nguyên vẹn
      controller.selectPath(updated.id, vertexIndex: 1);
      expect(controller.deleteSelectedVertex(), isNull);
      updated = controller.paths.first;
      expect(updated.segments.length, 3);
      expect(updated.segments[1].type, SegmentType.cubic);
      expect(updated.segments[1].control2, const DiagramPoint(110, 270));
    });

    test('Chuyển đổi đoạn thẳng <-> cong giữ nguyên hai đầu mút và không chạm đoạn khác',
        () {
      final path = GuidePath(
        id: 'p1',
        ownerBallId: 'ball_white',
        segments: const [
          PathSegment.line(
            start: DiagramPoint(40, 80),
            end: DiagramPoint(120, 160),
          ),
          PathSegment.line(
            start: DiagramPoint(120, 160),
            end: DiagramPoint(140, 280),
          ),
        ],
      );
      final controller = TableEditorController(
        initialScene: DiagramScene.defaultInitial(id: 'conv').withPaths([path]),
      );

      // Chỉ chuyển đoạn 0 sang cong
      expect(controller.convertSegmentToCubic('p1', 0), isTrue);
      var cur = controller.paths.first;
      expect(cur.segments[0].type, SegmentType.cubic);
      expect(cur.segments[0].start, const DiagramPoint(40, 80));
      expect(cur.segments[0].end, const DiagramPoint(120, 160));
      expect(cur.segments[1].type, SegmentType.line);

      // Chuyển đoạn 0 về thẳng -> giữ nguyên hai đầu mút, hoàn tác được
      expect(controller.convertSegmentToLine('p1', 0), isTrue);
      cur = controller.paths.first;
      expect(cur.segments[0].type, SegmentType.line);
      expect(cur.segments[0].start, const DiagramPoint(40, 80));
      expect(cur.segments[0].end, const DiagramPoint(120, 160));

      expect(controller.undo(), isTrue);
      expect(controller.paths.first.segments[0].type, SegmentType.cubic);
      expect(controller.undo(), isTrue);
      expect(controller.paths.first.segments[0].type, SegmentType.line);
    });

    test('Chia cubic bằng de Casteljau giữ nguyên hình dạng trong dung sai < 1e-9',
        () {
      const seg = PathSegment.cubic(
        start: DiagramPoint(30, 70),
        control1: DiagramPoint(150, 90),
        control2: DiagramPoint(25, 220),
        end: DiagramPoint(145, 290),
      );

      for (final splitT in const [0.25, 0.5, 0.73]) {
        final parts = PathGeometry.splitSegmentAt(seg, splitT);
        expect(parts.length, 2);
        expect(parts[0].type, SegmentType.cubic);
        expect(parts[1].type, SegmentType.cubic);
        expect(parts[0].end, parts[1].start);

        for (var k = 0; k <= 20; k++) {
          final u = k / 20.0;
          final pOrigLeft = PathGeometry.evaluateSegment(seg, splitT * u);
          final pLeft = PathGeometry.evaluateSegment(parts[0], u);
          expect(pLeft.distanceTo(pOrigLeft), lessThan(1e-9));

          final pOrigRight =
              PathGeometry.evaluateSegment(seg, splitT + (1.0 - splitT) * u);
          final pRight = PathGeometry.evaluateSegment(parts[1], u);
          expect(pRight.distanceTo(pOrigRight), lessThan(1e-9));
        }
      }
    });

    test('Đảo chiều đường hỗn hợp hai lần phục hồi đúng đường ban đầu', () {
      final original = GuidePath(
        id: 'p_rev',
        ownerBallId: 'ball_yellow',
        segments: const [
          PathSegment.line(
            start: DiagramPoint(30, 80),
            end: DiagramPoint(70, 150),
          ),
          PathSegment.cubic(
            start: DiagramPoint(70, 150),
            control1: DiagramPoint(130, 140),
            control2: DiagramPoint(140, 250),
            end: DiagramPoint(90, 300),
          ),
        ],
      );

      final revOnce = PathGeometry.reversePath(original);
      expect(revOnce.segments[0].type, SegmentType.cubic);
      expect(revOnce.segments[0].start, const DiagramPoint(90, 300));
      expect(revOnce.segments[0].control1, const DiagramPoint(140, 250));
      expect(revOnce.segments[0].control2, const DiagramPoint(130, 140));
      expect(revOnce.segments[0].end, const DiagramPoint(70, 150));
      expect(revOnce.segments[1].type, SegmentType.line);
      expect(revOnce.segments[1].start, const DiagramPoint(70, 150));
      expect(revOnce.segments[1].end, const DiagramPoint(30, 80));

      final revTwice = PathGeometry.reversePath(revOnce);
      expect(revTwice, original);
    });

    test('Mũi tên theo tiếp tuyến cuối, kể cả các trường hợp suy biến không sinh NaN',
        () {
      // 1. Tiếp tuyến chuẩn end - control2 -> hướng (1, 0)
      final normalCubic = GuidePath(
        id: 'c_norm',
        ownerBallId: 'ball_white',
        segments: const [
          PathSegment.cubic(
            start: DiagramPoint(40, 100),
            control1: DiagramPoint(60, 160),
            control2: DiagramPoint(90, 200),
            end: DiagramPoint(120, 200),
          ),
        ],
      );
      final dirNorm = PathGeometry.lastNonZeroDirection(normalCubic);
      expect(dirNorm, isNotNull);
      expect(dirNorm!.dx, closeTo(1.0, 1e-9));
      expect(dirNorm.dy, closeTo(0.0, 1e-9));

      // 2. Suy biến control2 == end -> lùi về (end - control1) -> hướng (0, 1)
      final degC2 = GuidePath(
        id: 'c_deg2',
        ownerBallId: 'ball_white',
        segments: const [
          PathSegment.cubic(
            start: DiagramPoint(40, 100),
            control1: DiagramPoint(120, 140),
            control2: DiagramPoint(120, 200),
            end: DiagramPoint(120, 200),
          ),
        ],
      );
      final dirDeg2 = PathGeometry.lastNonZeroDirection(degC2);
      expect(dirDeg2, isNotNull);
      expect(dirDeg2!.dx, closeTo(0.0, 1e-9));
      expect(dirDeg2.dy, closeTo(1.0, 1e-9));

      // 3. Suy biến toàn đoạn cuối = 0 -> lùi về đoạn trước, không sinh NaN
      final degAllLast = GuidePath(
        id: 'c_deg_last',
        ownerBallId: 'ball_white',
        segments: const [
          PathSegment.line(
            start: DiagramPoint(40, 100),
            end: DiagramPoint(100, 100),
          ),
          PathSegment.cubic(
            start: DiagramPoint(100, 100),
            control1: DiagramPoint(100, 100),
            control2: DiagramPoint(100, 100),
            end: DiagramPoint(100, 100),
          ),
        ],
      );
      final dirPrev = PathGeometry.lastNonZeroDirection(degAllLast);
      expect(dirPrev, isNotNull);
      expect(dirPrev!.dx, closeTo(1.0, 1e-9));
      expect(dirPrev.dy, closeTo(0.0, 1e-9));

      // 4. Toàn bộ đường suy biến về 1 điểm -> null an toàn, không NaN
      final degZero = GuidePath(
        id: 'c_zero',
        ownerBallId: 'ball_white',
        segments: const [
          PathSegment.cubic(
            start: DiagramPoint(80, 80),
            control1: DiagramPoint(80, 80),
            control2: DiagramPoint(80, 80),
            end: DiagramPoint(80, 80),
          ),
        ],
      );
      expect(PathGeometry.lastNonZeroDirection(degZero), isNull);
    });

    test('Hit-test bắt được phần cong xa dây nối hai đầu và bỏ qua dây nối trống',
        () {
      // Đầu mút ở x = 40, tay nắm kéo cung vồng sang x = 160 (B(0.5) = (130, 180))
      final bowed = GuidePath(
        id: 'p_bowed',
        ownerBallId: 'ball_white',
        segments: const [
          PathSegment.cubic(
            start: DiagramPoint(40, 100),
            control1: DiagramPoint(160, 100),
            control2: DiagramPoint(160, 260),
            end: DiagramPoint(40, 260),
          ),
        ],
      );

      final mapper = TableCoordinateMapper(canvasSize: const Size(400, 800));
      final curveMid = PathGeometry.evaluateSegment(bowed.segments.first, 0.5);
      final hitCurve = PathGeometry.hitTestPath(
        screenPosition: mapper.diagramToScreen(curveMid),
        paths: [bowed],
        mapper: mapper,
      );
      expect(hitCurve, isNotNull);
      expect(hitCurve!.path.id, 'p_bowed');
      expect(hitCurve.distancePx, lessThan(2.0));

      // Chạm vào trung điểm dây nối thẳng (40, 180) ở cách xa đường cong -> không bắt nhầm
      final hitChord = PathGeometry.hitTestPath(
        screenPosition: mapper.diagramToScreen(const DiagramPoint(40, 180)),
        paths: [bowed],
        mapper: mapper,
      );
      expect(hitChord, isNull);
    });

    test('Phát hiện đường cong vượt băng [r, W-r] x [r, H-r] dù hai đầu mút nằm hợp lệ trong bàn',
        () {
      // Hai đầu (16, 100) và (16, 220) hoàn toàn nằm trong [4, 184], nhưng tay nắm x=-16
      // kéo cực trị đường cong phình vượt qua x = 4 ra ngoài vùng tâm bi.
      final bulging = GuidePath(
        id: 'p_bulge',
        ownerBallId: 'ball_white',
        role: PathRole.ballCenter,
        segments: const [
          PathSegment.cubic(
            start: DiagramPoint(16, 100),
            control1: DiagramPoint(-16, 130),
            control2: DiagramPoint(-16, 190),
            end: DiagramPoint(16, 220),
          ),
        ],
      );

      final balls = DiagramScene.defaultInitial(id: 'bounds').balls;
      final err = PathGeometry.validatePath(bulging, balls);
      expect(err, isNotNull);
      expect(err, contains('phình ra ngoài'));

      final controller = TableEditorController(
        initialScene: DiagramScene(
          id: 'bounds',
          balls: balls,
          paths: [bulging],
        ),
      );
      expect(controller.invalidPathWarnings.containsKey('p_bulge'), isTrue);
    });
  });

  group('Phase 3 — Giao dịch tay nắm, chú thích, JSON tương thích & lưu/tải', () {
    test('Undo/Redo và cancel cho tay nắm Bézier & điểm nối', () {
      final path = GuidePath(
        id: 'p_drag',
        ownerBallId: 'ball_white',
        segments: const [
          PathSegment.cubic(
            start: DiagramPoint(40, 90),
            control1: DiagramPoint(70, 120),
            control2: DiagramPoint(110, 180),
            end: DiagramPoint(140, 220),
          ),
        ],
      );
      final controller = TableEditorController(
        initialScene: DiagramScene.defaultInitial(id: 'drag_ctrl').withPaths([path]),
      );

      // Kéo tay nắm c1 qua nhiều bước rồi thả -> 1 Undo
      final t1 = controller.beginControlHandleDrag('p_drag', 0, 1);
      expect(t1, isNotNull);
      controller.updateControlHandleDrag(const DiagramPoint(90, 95), dragToken: t1);
      controller.updateControlHandleDrag(const DiagramPoint(125, 110), dragToken: t1);
      expect(controller.isDraggingControlHandle, isTrue);
      expect(controller.isDraggingAny, isTrue);
      expect(controller.endControlHandleDrag(dragToken: t1), isTrue);

      expect(controller.paths.first.segments.first.control1, const DiagramPoint(125, 110));
      expect(controller.undoHistory.length, 1);

      expect(controller.undo(), isTrue);
      expect(controller.paths.first.segments.first.control1, const DiagramPoint(70, 120));
      expect(controller.redo(), isTrue);
      expect(controller.paths.first.segments.first.control1, const DiagramPoint(125, 110));

      // Cancel tay nắm c2 -> khôi phục vị trí trước kéo, không tạo thêm Undo
      final t2 = controller.beginControlHandleDrag('p_drag', 0, 2);
      controller.updateControlHandleDrag(const DiagramPoint(30, 300), dragToken: t2);
      expect(controller.cancelControlHandleDrag(dragToken: t2), isTrue);
      expect(controller.paths.first.segments.first.control2, const DiagramPoint(110, 180));
      expect(controller.undoHistory.length, 1);
    });

    test('Chú thích: 5 loại, khóa, Undo/Redo/cancel & lưu/tải giữ nguyên kích thước vùng',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('libre_billiard_p3_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final storage = FileSceneStorage(directoryProvider: () async => tempDir);
      final writer = TableEditorController(storage: storage);
      final initialBalls = writer.balls;
      final initialPaths = writer.paths;

      // Thêm đủ 5 loại chú thích (không nhét kích thước vào text)
      final annLabel = writer.addAnnotation(
        type: AnnotationType.label,
        position: const DiagramPoint(50, 60),
        text: 'Điểm đánh',
      )!;
      final annSeq = writer.addAnnotation(
        type: AnnotationType.sequence,
        position: const DiagramPoint(80, 90),
        text: '1',
      )!;
      final annMarker = writer.addAnnotation(
        type: AnnotationType.marker,
        position: const DiagramPoint(110, 120),
        radius: 3.5,
      )!;
      final annCircle = writer.addAnnotation(
        type: AnnotationType.circleZone,
        position: const DiagramPoint(94, 240),
        radius: 19.5,
        isDashed: true,
        colorValue: 0xFFA5D6A7,
        text: 'Vùng gom',
      )!;
      final annRect = writer.addAnnotation(
        type: AnnotationType.rectZone,
        position: const DiagramPoint(120, 300),
        width: 44.0,
        height: 22.5,
        isDashed: false,
        colorValue: 0xFFFFCC80,
      )!;

      // Chú thích không làm thay đổi bi hoặc đường
      expect(writer.balls, initialBalls);
      expect(writer.paths, initialPaths);
      expect(writer.annotations.length, 5);

      // Kéo vùng tròn qua nhiều frame = 1 bước Undo
      final tMove = writer.beginAnnotationDrag(annCircle.id);
      expect(tMove, isNotNull);
      writer.updateAnnotationDrag(const DiagramPoint(100, 245), dragToken: tMove);
      writer.updateAnnotationDrag(const DiagramPoint(105, 250), dragToken: tMove);
      expect(writer.endAnnotationDrag(dragToken: tMove), isTrue);
      expect(
        writer.annotations.firstWhere((a) => a.id == annCircle.id).position,
        const DiagramPoint(105, 250),
      );

      // Undo kéo + làm lại + cancel
      expect(writer.undo(), isTrue);
      expect(
        writer.annotations.firstWhere((a) => a.id == annCircle.id).position,
        const DiagramPoint(94, 240),
      );
      expect(writer.redo(), isTrue);
      expect(
        writer.annotations.firstWhere((a) => a.id == annCircle.id).position,
        const DiagramPoint(105, 250),
      );

      final tCancel = writer.beginAnnotationDrag(annRect.id);
      writer.updateAnnotationDrag(const DiagramPoint(50, 50), dragToken: tCancel);
      expect(writer.cancelAnnotationDrag(dragToken: tCancel), isTrue);
      expect(
        writer.annotations.firstWhere((a) => a.id == annRect.id).position,
        const DiagramPoint(120, 300),
      );

      // Khóa chú thích -> không kéo nhầm được
      expect(writer.toggleAnnotationLock(annSeq.id), isTrue);
      String? lockMsg;
      final lockedToken = writer.beginAnnotationDrag(
        annSeq.id,
        onBlocked: (m) => lockMsg = m,
      );
      expect(lockedToken, isNull);
      expect(lockMsg, isNotNull);

      // Thêm đường hỗn hợp để kiểm tra lưu/tải cùng lúc
      final mixedPath = GuidePath(
        id: 'path_mix_save',
        ownerBallId: 'ball_white',
        isDashed: true,
        strokeWidth: 3.0,
        segments: const [
          PathSegment.line(
            start: DiagramPoint(94, 94),
            end: DiagramPoint(60, 160),
          ),
          PathSegment.cubic(
            start: DiagramPoint(60, 160),
            control1: DiagramPoint(75, 220),
            control2: DiagramPoint(125, 240),
            end: DiagramPoint(130, 300),
          ),
        ],
      );
      final sceneToSave = writer.scene.withPaths([mixedPath]);
      final writer2 = TableEditorController(initialScene: sceneToSave, storage: storage);
      expect((await writer2.saveToStorage()).isSuccess, isTrue);

      final reader = TableEditorController(storage: storage);
      expect((await reader.loadFromStorage()).status, LoadStatus.loaded);
      expect(reader.scene, writer2.scene);

      final restoredCircle =
          reader.annotations.firstWhere((a) => a.id == annCircle.id);
      expect(restoredCircle.radius, 19.5);
      expect(restoredCircle.text, 'Vùng gom');
      expect(restoredCircle.isDashed, isTrue);

      final restoredRect =
          reader.annotations.firstWhere((a) => a.id == annRect.id);
      expect(restoredRect.width, 44.0);
      expect(restoredRect.height, 22.5);
      expect(restoredRect.text, '');

      expect(annLabel.id.isNotEmpty && annMarker.radius == 3.5, isTrue);
    });

    test('Đọc scene Phase 2 thiếu trường mới, bảo toàn thuộc tính mở rộng & chặn schema mới hơn',
        () {
      // JSON kiểu Phase 2 có DiagramAnnotation cũ thiếu width/height/radius/isDashed/strokeWidth
      // kèm thuộc tính mở rộng & đoạn chưa hỗ trợ trong cùng schema v1.
      final phase2CompatJson = <String, dynamic>{
        'id': 'legacy_v1',
        'version': 1,
        'width': 188.0,
        'height': 376.0,
        'customRootTag': 'keep_me',
        'balls': DiagramScene.defaultInitial(id: 'legacy_v1')
            .balls
            .map((b) => b.toJson())
            .toList(),
        'paths': [
          {
            'id': 'p_ext',
            'ownerBallId': 'ball_white',
            'role': 'ball_center',
            'customPathProp': 42,
            'segments': [
              {
                'type': 'catmull_future',
                'start': {'x': 50, 'y': 90},
                'end': {'x': 120, 'y': 200},
                'tension': 0.75,
              },
            ],
          },
        ],
        'annotations': [
          {
            'id': 'ann_old_circle',
            'type': 'circle_zone',
            'position': {'x': 94, 'y': 188},
            'text': 'Vùng cũ',
            'locked': false,
          },
        ],
      };

      final parsed = DiagramScene.fromJson(phase2CompatJson);
      expect(parsed.annotations.first.radius, DiagramAnnotation.defaultRadiusFor(AnnotationType.circleZone));
      expect(parsed.annotations.first.isDashed, isFalse);
      expect(parsed.annotations.first.strokeWidth, 1.8);
      expect(parsed.paths.first.segments.first.type, SegmentType.unknown);

      // Round-trip JSON phải bảo toàn đoạn mở rộng và thuộc tính chưa hỗ trợ
      final reEncoded = jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>;
      expect(reEncoded['customRootTag'], 'keep_me');
      final rePath = (reEncoded['paths'] as List<dynamic>).first as Map<String, dynamic>;
      expect(rePath['customPathProp'], 42);
      final reSeg = (rePath['segments'] as List<dynamic>).first as Map<String, dynamic>;
      expect(reSeg['type'], 'catmull_future');
      expect(reSeg['tension'], 0.75);

      // Schema mới hơn vẫn bị chặn như hiện tại
      final newerSchema = Map<String, dynamic>.from(phase2CompatJson)..['version'] = 2;
      expect(
        () => DiagramScene.fromJson(newerSchema),
        throwsA(isA<SchemaVersionException>()),
      );
    });
  });

  group('Phase 3 — Widget tests thao tác đường cong và chú thích trên TableStageScreen',
      () {
    testWidgets('Chuyển đoạn thành cong, kéo tay nắm trực tiếp, phát hiện phình vượt băng & Undo',
        (WidgetTester tester) async {
      final linear = GuidePath(
        id: 'p_ui_curve',
        ownerBallId: 'ball_white',
        segments: const [
          PathSegment.line(
            start: DiagramPoint(12, 100),
            end: DiagramPoint(12, 240),
          ),
        ],
      );
      final controller = TableEditorController(
        initialScene: DiagramScene.defaultInitial(id: 'ui_curve').withPaths([linear]),
      )..selectPath('p_ui_curve', segmentIndex: 0);

      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Bấm "Thành cong"
      await tester.tap(find.byKey(const Key('convert_segment_button')));
      await tester.pumpAndSettle();
      expect(controller.paths.first.segments.first.type, SegmentType.cubic);

      // Kéo tay nắm c1 vượt sang trái x < 0 để đường phình ra ngoài [4, 184] -> hiện banner cảnh báo
      final canvasFinder = find.byKey(const Key('billiard_table_canvas'));
      final topLeft = tester.getTopLeft(canvasFinder);
      final mapper = TableCoordinateMapper(canvasSize: tester.getSize(canvasFinder));

      final c1Diagram = controller.paths.first.segments.first.control1!;
      final drag = await tester.startGesture(topLeft + mapper.diagramToScreen(c1Diagram));
      final outOfBoundsScreen = mapper.diagramToScreen(const DiagramPoint(-18, 140));
      await drag.moveTo(topLeft + outOfBoundsScreen);
      await drag.up();
      await tester.pumpAndSettle();

      expect(controller.invalidPathWarnings.containsKey('p_ui_curve'), isTrue);
      expect(find.byKey(const Key('invalid_path_warning_banner')), findsOneWidget);

      // Hoàn tác bước kéo tay nắm -> cảnh báo biến mất, quay về tay nắm hợp lệ
      await tester.tap(find.byKey(const Key('undo_button')));
      await tester.pumpAndSettle();
      expect(controller.invalidPathWarnings, isEmpty);
      expect(find.byKey(const Key('invalid_path_warning_banner')), findsNothing);
    });

    testWidgets('Đặt vùng tròn/chữ nhật từ UI, sửa kích thước và xóa trên TableStageScreen',
        (WidgetTester tester) async {
      final controller = TableEditorController();

      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Chuyển sang chế độ Chú thích và chọn Vùng chữ nhật
      await tester.tap(find.byKey(const Key('mode_annotation_chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating_place_annotation_panel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('place_ann_rect_zone')));
      await tester.pumpAndSettle();

      // Chạm lên bàn để đặt vùng chữ nhật tại (94, 220)
      final canvasFinder = find.byKey(const Key('billiard_table_canvas'));
      final topLeft = tester.getTopLeft(canvasFinder);
      final mapper = TableCoordinateMapper(canvasSize: tester.getSize(canvasFinder));
      await tester.tapAt(topLeft + mapper.diagramToScreen(const DiagramPoint(94, 220)));
      await tester.pumpAndSettle();

      expect(controller.annotations.length, 1);
      expect(controller.annotations.first.type, AnnotationType.rectZone);
      expect(find.byKey(const Key('floating_annotation_panel')), findsOneWidget);

      // Mở bảng Sửa & Kích thước
      await tester.tap(find.byKey(const Key('edit_annotation_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('annotation_edit_sheet')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ann_text_input')), 'Khu 1');
      await tester.enterText(find.byKey(const Key('ann_width_input')), '52.5');
      await tester.enterText(find.byKey(const Key('ann_height_input')), '30.0');
      await tester.tap(find.byKey(const Key('apply_annotation_button')));
      await tester.pumpAndSettle();

      final edited = controller.annotations.first;
      expect(edited.text, 'Khu 1');
      expect(edited.width, 52.5);
      expect(edited.height, 30.0);

      // Xóa rồi Hoàn tác
      await tester.tap(find.byKey(const Key('delete_annotation_button')));
      await tester.pumpAndSettle();
      expect(controller.annotations, isEmpty);

      await tester.tap(find.byKey(const Key('undo_button')));
      await tester.pumpAndSettle();
      expect(controller.annotations.length, 1);
      expect(controller.annotations.first.width, 52.5);
    });
  });
}

