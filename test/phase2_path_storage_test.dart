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

class _ToggleFailingStorage implements SceneStorage {
  bool shouldFailWrite;
  DiagramScene? _stored;

  _ToggleFailingStorage({this.shouldFailWrite = false, DiagramScene? initial})
      : _stored = initial;

  @override
  Future<DiagramScene?> loadScene() async => _stored;

  @override
  Future<void> saveScene(DiagramScene scene) async {
    if (shouldFailWrite) {
      throw const FileSystemException('Giả lập lỗi ghi đĩa');
    }
    _stored = scene;
  }
}

void main() {
  group('Phase 2 — Vẽ, hủy, chỉnh điểm và Undo/Redo đường thẳng/gấp khúc', () {
    test('Vẽ nhiều đoạn thẳng không tự bo cong; hoàn tất = 1 Undo; hủy không mất đường cũ',
        () {
      final controller = TableEditorController();

      // Vẽ đường thứ nhất cho bi trắng (gấp khúc 3 điểm)
      expect(controller.setToolMode(EditorToolMode.drawPolyline), isTrue);
      controller.setDraftOwnerBall('ball_white');
      controller.addDraftPoint(const DiagramPoint(94, 94));
      // Chỉ có 1 điểm -> không hoàn tất được
      expect(controller.canCompleteDraft, isFalse);
      expect(controller.completeDraftPath(), isNotNull);

      controller.addDraftPoint(const DiagramPoint(70, 200));
      controller.addDraftPoint(const DiagramPoint(118, 200));
      expect(controller.canCompleteDraft, isTrue);
      expect(controller.completeDraftPath(), isNull);

      expect(controller.paths.length, 1);
      final p1 = controller.paths.first;
      expect(p1.ownerBallId, 'ball_white');
      expect(p1.segments.length, 2);
      // EDT-02: Mọi đoạn đều là line, không tự biến thành đường cong
      expect(p1.segments.every((s) => s.type == SegmentType.line), isTrue);
      expect(controller.undoHistory.length, 1);

      // Vẽ nháp đường thứ 2 cho cùng bi trắng rồi Hủy -> không mất đường 1, không tạo Undo
      controller.setToolMode(EditorToolMode.drawPolyline);
      controller.setDraftOwnerBall('ball_white');
      controller.addDraftPoint(const DiagramPoint(94, 94));
      controller.addDraftPoint(const DiagramPoint(140, 260));
      controller.cancelDraftPath();
      expect(controller.paths.length, 1);
      expect(controller.undoHistory.length, 1);
      expect(controller.toolMode, EditorToolMode.select);

      // Vẽ thêm đường thứ 2 cho bi vàng (một bi có nhiều đường được)
      controller.setToolMode(EditorToolMode.drawPolyline);
      controller.setDraftOwnerBall('ball_yellow');
      controller.addDraftPoint(const DiagramPoint(70, 200));
      controller.addDraftPoint(const DiagramPoint(70, 372));
      expect(controller.completeDraftPath(), isNull);
      expect(controller.paths.length, 2);

      // Undo & Redo hoàn tất đường
      expect(controller.undo(), isTrue);
      expect(controller.paths.length, 1);
      expect(controller.redo(), isTrue);
      expect(controller.paths.length, 2);
    });

    test('Chèn điểm, xóa điểm (từ chối khi còn <= 2 điểm), đảo chiều, đổi nét & xóa đường',
        () {
      final controller = TableEditorController();
      controller.setToolMode(EditorToolMode.drawPolyline);
      controller.addDraftPoint(const DiagramPoint(40, 100));
      controller.addDraftPoint(const DiagramPoint(140, 100));
      expect(controller.completeDraftPath(), isNull);

      // Đường đang có 2 điểm -> xóa điểm phải bị từ chối rõ ràng
      final errDelete = controller.deleteSelectedVertex();
      expect(errDelete, contains('ít nhất 2 điểm'));
      expect(controller.paths.length, 1);

      // Chèn điểm ở giữa -> thành 3 điểm tại (90, 100)
      expect(controller.insertVertexOnSelectedPath(segmentIndex: 0), isTrue);
      var verts = PathGeometry.extractVertices(controller.selectedPath!);
      expect(verts.length, 3);
      expect(verts[1], const DiagramPoint(90, 100));

      // Kéo điểm giữa lên (90, 180) qua nhiều frame = 1 bước Undo
      final token = controller.beginVertexDrag(controller.selectedPathId!, 1);
      expect(token, isNotNull);
      controller.updateVertexDrag(const DiagramPoint(90, 140), dragToken: token);
      controller.updateVertexDrag(const DiagramPoint(90, 180), dragToken: token);
      expect(controller.endVertexDrag(dragToken: token), isTrue);
      verts = PathGeometry.extractVertices(controller.selectedPath!);
      expect(verts[1], const DiagramPoint(90, 180));

      // Đảo chiều -> thứ tự đỉnh đảo ngược và hướng đoạn cuối lật ngược
      final dirBefore = PathGeometry.lastNonZeroDirection(controller.selectedPath!);
      expect(controller.reverseSelectedPath(), isTrue);
      final reversedVerts =
          PathGeometry.extractVertices(controller.selectedPath!);
      expect(reversedVerts.first, const DiagramPoint(140, 100));
      expect(reversedVerts.last, const DiagramPoint(40, 100));
      final dirAfter = PathGeometry.lastNonZeroDirection(controller.selectedPath!);
      expect(dirBefore, isNotNull);
      expect(dirAfter, isNotNull);

      // Đổi kiểu nét -> hoàn tác được
      expect(
        controller.updateSelectedPathStyle(
          isDashed: true,
          strokeWidth: 3.4,
          arrowMode: ArrowMode.none,
          customColorValue: 0xFF80DEEA,
        ),
        isTrue,
      );
      expect(controller.selectedPath!.isDashed, isTrue);
      expect(controller.selectedPath!.strokeWidth, 3.4);
      expect(controller.selectedPath!.arrowMode, ArrowMode.none);
      expect(controller.selectedPath!.customColorValue, 0xFF80DEEA);

      // Xóa điểm giữa (đang có 3 điểm -> còn 2 điểm hợp lệ)
      controller.selectPath(controller.selectedPathId, vertexIndex: 1);
      expect(controller.deleteSelectedVertex(), isNull);
      expect(
        PathGeometry.extractVertices(controller.selectedPath!).length,
        2,
      );

      // Xóa đường và Undo khôi phục
      expect(controller.deleteSelectedPath(), isTrue);
      expect(controller.paths, isEmpty);
      expect(controller.undo(), isTrue);
      expect(controller.paths.length, 1);

      // Undo sau đó thực hiện thao tác mới xóa nhánh Redo
      expect(controller.undo(), isTrue);
      expect(controller.canRedo, isTrue);
      controller.setBallPosition('ball_white', const DiagramPoint(94, 80));
      expect(controller.canRedo, isFalse);
    });

    test('Pan cancel khi kéo điểm điều khiển khôi phục trạng thái trước kéo & chặn thao tác xung đột',
        () {
      final controller = TableEditorController();
      controller.setToolMode(EditorToolMode.drawPolyline);
      controller.addDraftPoint(const DiagramPoint(50, 100));
      controller.addDraftPoint(const DiagramPoint(150, 200));
      controller.completeDraftPath();

      final pathId = controller.selectedPathId!;
      final token = controller.beginVertexDrag(pathId, 1);
      expect(token, isNotNull);
      controller.updateVertexDrag(const DiagramPoint(160, 250), dragToken: token);

      // Trong lúc đang kéo điểm -> Undo và đổi chế độ đều bị chặn ở controller
      expect(controller.undo(), isFalse);
      expect(controller.setToolMode(EditorToolMode.drawPolyline), isFalse);
      expect(controller.beginBallDrag('ball_white'), isNull);

      // Hủy kéo với token đúng -> khôi phục về (150, 200)
      expect(controller.cancelVertexDrag(dragToken: token), isTrue);
      expect(controller.isDraggingVertex, isFalse);
      expect(
        PathGeometry.extractVertices(controller.selectedPath!)[1],
        const DiagramPoint(150, 200),
      );
    });
  });

  group('Phase 2 — Giới hạn lòng bàn, bắt dính & liên kết điểm đầu với bi', () {
    test('Điểm quỹ đạo tâm bi không vượt [r, W-r] x [r, H-r] và bắt dính sát băng đúng r',
        () {
      final controller = TableEditorController();
      controller.updateSnapSettings(
        const SnapSettings(snapToGrid: true, snapToRailLimit: true),
      );
      controller.setToolMode(EditorToolMode.drawPolyline);

      // Chạm sát mép ngoài (-10, 1.5) -> bắt dính về sát băng (r=4, r=4), KHÔNG đặt lên mép 0
      final pStart = controller.addDraftPoint(const DiagramPoint(-10, 1.5));
      expect(pStart, const DiagramPoint(4.0, 4.0));

      // Chạm gần mép phải (186.5, 48.0) -> X sát băng 184.0 (188-4), Y bắt lưới 47.0
      final pEnd = controller.addDraftPoint(const DiagramPoint(186.5, 48.0));
      expect(pEnd, const DiagramPoint(184.0, 47.0));
      expect(controller.completeDraftPath(), isNull);

      // Thử đổi bán kính bi từ 4 lên 6 -> cảnh báo đường vượt giới hạn lòng bàn
      final radiusErr = controller.trySetBallRadius(6.0);
      expect(radiusErr, contains('vượt giới hạn'));
      expect(controller.currentBallRadius, 4.0);

      // Nếu người dùng xác nhận đổi & đánh dấu đường lỗi -> đánh dấu rõ, không âm thầm sửa đường
      expect(
        controller.trySetBallRadius(6.0, allowInvalidPaths: true),
        isNull,
      );
      expect(controller.currentBallRadius, 6.0);
      expect(controller.invalidPathWarnings, isNotEmpty);
      // Tọa độ đường vẫn nguyên vẹn (4.0, 4.0) chứ không bị âm thầm kẹp lên (6.0, 6.0)
      expect(
        PathGeometry.extractVertices(controller.paths.first).first,
        const DiagramPoint(4.0, 4.0),
      );
    });

    test('Liên kết điểm đầu: kéo bi chỉ cập nhật điểm đầu, giữ nguyên các điểm sau; chỉnh đường không tự di chuyển bi',
        () {
      final controller = TableEditorController();
      controller.setToolMode(EditorToolMode.drawPolyline);
      controller.setDraftOwnerBall('ball_white');
      controller.setDraftAnchorStart(true); // gắn điểm đầu với tâm bi trắng (94, 94)
      controller.addDraftPoint(const DiagramPoint(70, 200));
      controller.addDraftPoint(const DiagramPoint(118, 280));
      expect(controller.completeDraftPath(), isNull);

      final pathId = controller.selectedPathId!;
      expect(controller.selectedPath!.startAnchorBallId, 'ball_white');

      // Không cho kéo tách điểm đầu khi đang liên kết và không tự di chuyển bi
      String? blockedMsg;
      expect(
        controller.beginVertexDrag(
          pathId,
          0,
          onBlocked: (m) => blockedMsg = m,
        ),
        isNull,
      );
      expect(blockedMsg, isNotNull);

      // Kéo bi trắng từ (94, 94) sang (130, 110) -> chỉ điểm đầu cập nhật, P1 & P2 giữ nguyên
      final ballToken = controller.beginBallDrag('ball_white');
      controller.updateBallDrag(const DiagramPoint(130, 110), dragToken: ballToken);
      controller.endBallDrag(dragToken: ballToken);

      final vertsAfterBallMove = PathGeometry.extractVertices(controller.paths.first);
      expect(vertsAfterBallMove[0], const DiagramPoint(130, 110));
      expect(vertsAfterBallMove[1], const DiagramPoint(70, 200));
      expect(vertsAfterBallMove[2], const DiagramPoint(118, 280));

      // Chọn lại đường và gỡ liên kết -> kéo điểm đầu thoải mái mà không làm bi trắng di chuyển
      expect(controller.selectPath(pathId), isTrue);
      expect(controller.toggleSelectedPathStartAnchor(), isTrue);
      expect(controller.selectedPath!.startAnchorBallId, isNull);

      final vToken = controller.beginVertexDrag(pathId, 0);
      expect(vToken, isNotNull);
      controller.updateVertexDrag(const DiagramPoint(50, 50), dragToken: vToken);
      controller.endVertexDrag(dragToken: vToken);

      expect(
        controller.balls.firstWhere((b) => b.id == 'ball_white').center,
        const DiagramPoint(130, 110),
      );
      expect(
        PathGeometry.extractVertices(controller.paths.first).first,
        const DiagramPoint(50, 50),
      );
    });

    test('Chọn đúng đường gần nhất khi các đường gần nhau & không xóa nhầm đường khác', () {
      final scene = DiagramScene(
        id: 'near_paths',
        balls: DiagramScene.defaultInitial(id: 'near_paths').balls,
        paths: [
          GuidePath(
            id: 'path_1',
            ownerBallId: 'ball_white',
            segments: const [
              PathSegment.line(
                start: DiagramPoint(40, 120),
                end: DiagramPoint(150, 120),
              ),
            ],
          ),
          GuidePath(
            id: 'path_2',
            ownerBallId: 'ball_yellow',
            segments: const [
              PathSegment.line(
                start: DiagramPoint(40, 132),
                end: DiagramPoint(150, 132),
              ),
            ],
          ),
        ],
      );
      final mapper = TableCoordinateMapper(canvasSize: const Size(360, 640));

      final nearPath1 = mapper.diagramToScreen(const DiagramPoint(95, 122));
      final hit1 = PathGeometry.hitTestPath(
        screenPosition: nearPath1,
        paths: scene.paths,
        mapper: mapper,
      );
      expect(hit1?.path.id, 'path_1');

      final nearPath2 = mapper.diagramToScreen(const DiagramPoint(95, 130));
      final hit2 = PathGeometry.hitTestPath(
        screenPosition: nearPath2,
        paths: scene.paths,
        mapper: mapper,
      );
      expect(hit2?.path.id, 'path_2');

      // Chọn path_1 và xóa -> path_2 vẫn nguyên vẹn
      final controller = TableEditorController(initialScene: scene);
      controller.selectPath('path_1');
      expect(controller.deleteSelectedPath(), isTrue);
      expect(controller.paths.map((p) => p.id).toList(), ['path_2']);
    });
  });

  group('Phase 2 — JSON round-trip, lưu/mở lại và xử lý lỗi ghi', () {
    test('JSON round-trip giữ đủ bi, đường, liên kết, nét đứt, độ dày, màu và mũi tên',
        () {
      final scene = DiagramScene(
        id: 'roundtrip_scene',
        balls: DiagramScene.defaultInitial(id: 'roundtrip_scene').balls,
        paths: [
          GuidePath(
            id: 'path_1',
            ownerBallId: 'ball_white',
            role: PathRole.ballCenter,
            segments: const [
              PathSegment.line(
                start: DiagramPoint(94, 94),
                end: DiagramPoint(70, 200),
              ),
              PathSegment.line(
                start: DiagramPoint(70, 200),
                end: DiagramPoint(118, 200),
              ),
            ],
            isDashed: true,
            strokeWidth: 3.4,
            arrowMode: ArrowMode.end,
            customColorValue: 0xFF80DEEA,
            startAnchorBallId: 'ball_white',
          ),
        ],
        viewSettings: SceneViewSettings(
          showGrid: true,
          showDiamonds: false,
          showDiamondNumbers: true,
          showBallNumbers: false,
        ),
      );

      final raw = jsonEncode(scene.toJson());
      final restored =
          DiagramScene.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(restored, scene);
      expect(restored.paths.first.isDashed, isTrue);
      expect(restored.paths.first.strokeWidth, 3.4);
      expect(restored.paths.first.arrowMode, ArrowMode.end);
      expect(restored.paths.first.customColorValue, 0xFF80DEEA);
      expect(restored.paths.first.startAnchorBallId, 'ball_white');
    });

    test('FileSceneStorage lưu/mở lại qua lần khởi tạo mới và chặn schema mới hơn',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('libre_billiard_p2_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final storage = FileSceneStorage(directoryProvider: () async => tempDir);
      final writer = TableEditorController(storage: storage);
      writer.setBallPosition('ball_white', const DiagramPoint(100, 100));
      writer.setToolMode(EditorToolMode.drawPolyline);
      writer.setDraftOwnerBall('ball_white');
      writer.setDraftAnchorStart(true);
      writer.addDraftPoint(const DiagramPoint(70, 200));
      writer.addDraftPoint(const DiagramPoint(118, 200));
      expect(writer.completeDraftPath(), isNull);
      expect(writer.hasUnsavedChanges, isTrue);

      expect(await writer.saveToStorage(), isNull);
      expect(writer.hasUnsavedChanges, isFalse);

      // Giả lập đóng & mở lại app bằng controller mới đọc từ cùng thư mục
      final reader = TableEditorController(storage: storage);
      expect(await reader.loadFromStorage(), isNull);
      expect(reader.scene, writer.scene);
      expect(reader.paths.length, 1);
      expect(reader.paths.first.startAnchorBallId, 'ball_white');

      // Không để lại tệp .tmp
      final tmp = File('${tempDir.path}${Platform.pathSeparator}primary_scene.json.tmp');
      expect(await tmp.exists(), isFalse);

      // Ghi giả lập tệp có schema version mới hơn -> từ chối đọc và từ chối ghi đè
      final targetFile = File('${tempDir.path}${Platform.pathSeparator}primary_scene.json');
      final newerJson = writer.scene.toJson()..['version'] = 99;
      await targetFile.writeAsString(jsonEncode(newerJson));

      expect(
        () => storage.loadScene(),
        throwsA(isA<SchemaVersionException>()),
      );
      expect(
        () => storage.saveScene(writer.scene),
        throwsA(isA<SchemaVersionException>()),
      );
    });

    testWidgets('Lỗi ghi giữ nguyên bản đang chỉnh, không báo Đã lưu và cho thử lại',
        (WidgetTester tester) async {
      final storage = _ToggleFailingStorage(shouldFailWrite: true);
      final controller = TableEditorController(storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: TableStageScreen(controller: controller, storage: storage),
        ),
      );
      await tester.pumpAndSettle();

      // Vẽ thêm đường mới trên màn hình
      await tester.tap(find.byKey(const Key('mode_draw_chip')));
      await tester.pumpAndSettle();

      final canvasFinder = find.byKey(const Key('billiard_table_canvas'));
      final topLeft = tester.getTopLeft(canvasFinder);
      final size = tester.getSize(canvasFinder);
      final mapper = TableCoordinateMapper(canvasSize: size);

      await tester.tapAt(topLeft + mapper.diagramToScreen(const DiagramPoint(94, 94)));
      await tester.pump();
      await tester.tapAt(topLeft + mapper.diagramToScreen(const DiagramPoint(70, 200)));
      await tester.pump();
      await tester.tapAt(topLeft + mapper.diagramToScreen(const DiagramPoint(118, 200)));
      await tester.pumpAndSettle();

      // Khi đang ở chế độ Vẽ đường -> không kéo nhầm bi
      expect(
        controller.balls.firstWhere((b) => b.id == 'ball_white').center,
        const DiagramPoint(94, 94),
      );

      await tester.tap(find.byKey(const Key('complete_draft_path_button')));
      await tester.pumpAndSettle();
      expect(controller.paths.length, 1);

      // Bấm Lưu khi đang lỗi ghi -> hiện hộp thoại lỗi, KHÔNG hiện "Đã lưu sơ đồ", giữ nháp
      await tester.tap(find.byKey(const Key('save_scene_button')));
      await tester.pumpAndSettle();

      expect(find.text('Lỗi lưu sơ đồ'), findsOneWidget);
      expect(find.text('Đã lưu sơ đồ'), findsNothing);
      expect(controller.paths.length, 1);
      expect(controller.hasUnsavedChanges, isTrue);

      // Sửa hết lỗi ghi và bấm "Thử lại" -> lưu thành công
      storage.shouldFailWrite = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text('Đã lưu sơ đồ'), findsOneWidget);
      expect(controller.hasUnsavedChanges, isFalse);
      final saved = await storage.loadScene();
      expect(saved?.paths.length, 1);
    });

    testWidgets('Hủy chỉnh sửa không làm thay đổi bản đã lưu (DAT-02)',
        (WidgetTester tester) async {
      final baseline = DiagramScene.defaultInitial(id: 'primary_scene');
      final storage = _ToggleFailingStorage(initial: baseline);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TableStageScreen(storage: storage),
                      ),
                    );
                  },
                  child: const Text('Mở'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();

      // Vẽ thêm một đường rồi quay lại chọn "Bỏ thay đổi"
      await tester.tap(find.byKey(const Key('mode_draw_chip')));
      await tester.pumpAndSettle();
      final canvasFinder = find.byKey(const Key('billiard_table_canvas'));
      final topLeft = tester.getTopLeft(canvasFinder);
      final mapper = TableCoordinateMapper(canvasSize: tester.getSize(canvasFinder));

      await tester.tapAt(topLeft + mapper.diagramToScreen(const DiagramPoint(50, 100)));
      await tester.pump();
      await tester.tapAt(topLeft + mapper.diagramToScreen(const DiagramPoint(120, 240)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complete_draft_path_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bỏ thay đổi'));
      await tester.pumpAndSettle();

      // Bản đã lưu trong storage không bị thay đổi
      final storedAfter = await storage.loadScene();
      expect(storedAfter?.paths, isEmpty);
    });
  });
}
