import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/geometry/table_constants.dart';
import 'package:libre_billiard_notebook/geometry/table_geometry.dart';
import 'package:libre_billiard_notebook/models/models.dart';
import 'package:libre_billiard_notebook/state/table_editor_controller.dart';
import 'package:libre_billiard_notebook/ui/screens/table_stage_screen.dart';
import 'package:libre_billiard_notebook/ui/widgets/billiard_table_canvas.dart';
import 'package:libre_billiard_notebook/ui/widgets/table_gesture_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A & B: Unit Test TableCoordinateConverter & TableGestureCoordinator', () {
    test('Coordinate conversions: Diagram <-> Canvas <-> Viewport qua Zoom và Pan', () {
      const canvasSize = Size(400.0, 800.0);
      final mapper = TableCoordinateMapper(canvasSize: canvasSize);

      // Điểm chính giữa lòng bàn: (94, 188)
      const centerDiag = DiagramPoint(94.0, 188.0);
      final canvasCenter = TableCoordinateConverter.diagramToCanvas(centerDiag, mapper);
      expect(canvasCenter.dx, closeTo(200.0, 1e-4));
      expect(canvasCenter.dy, closeTo(400.0, 1e-4));

      final roundTripDiag = TableCoordinateConverter.canvasToDiagram(canvasCenter, mapper);
      expect(roundTripDiag.x, closeTo(centerDiag.x, 1e-4));
      expect(roundTripDiag.y, closeTo(centerDiag.y, 1e-4));

      // Ma trận biến đổi: scale 2.0x, dịch chuyển (50, 100)
      final matrix = Matrix4.identity()
        ..translateByDouble(50.0, 100.0, 0.0, 1.0)
        ..scaleByDouble(2.0, 2.0, 2.0, 1.0);

      final viewportPos = TableCoordinateConverter.canvasToViewport(canvasCenter, matrix);
      // viewport = matrix * canvas = 2.0 * (200, 400) + (50, 100) = (450, 900)
      expect(viewportPos.dx, closeTo(450.0, 1e-4));
      expect(viewportPos.dy, closeTo(900.0, 1e-4));

      final recoveredCanvas = TableCoordinateConverter.viewportToCanvas(viewportPos, matrix);
      expect(recoveredCanvas.dx, closeTo(canvasCenter.dx, 1e-4));
      expect(recoveredCanvas.dy, closeTo(canvasCenter.dy, 1e-4));

      final recoveredDiag = TableCoordinateConverter.viewportToDiagram(
        viewportPos: viewportPos,
        transformMatrix: matrix,
        mapper: mapper,
      );
      expect(recoveredDiag.x, closeTo(centerDiag.x, 1e-4));
      expect(recoveredDiag.y, closeTo(centerDiag.y, 1e-4));
    });

    test('TableGestureCoordinator: Phân quyền gesture và bảo vệ ngón tay sót lại', () {
      final coordinator = TableGestureCoordinator();
      expect(coordinator.state, TableGestureState.idle);
      expect(coordinator.panEnabled, isFalse);
      expect(coordinator.scaleEnabled, isFalse);

      // 1 ngón chạm xuống -> idle, chuẩn bị drag
      coordinator.onPointerDown(const PointerDownEvent(pointer: 1, position: Offset(100, 100)));
      expect(coordinator.activePointerCount, 1);
      expect(coordinator.panEnabled, isFalse); // Một ngón KHÔNG BAO GIỜ pan

      // Bắt đầu kéo đối tượng
      coordinator.notifyDragStarted();
      expect(coordinator.state, TableGestureState.objectDrag);

      // Ngón thứ 2 chạm xuống -> chuyển sang viewportGesture và gọi hủy kéo dở
      bool cancelCallbackCalled = false;
      coordinator.onPointerDown(
        const PointerDownEvent(pointer: 2, position: Offset(200, 200)),
        onCancelActiveDrag: () => cancelCallbackCalled = true,
      );
      expect(cancelCallbackCalled, isTrue);
      expect(coordinator.state, TableGestureState.viewportGesture);
      expect(coordinator.activePointerCount, 2);
      expect(coordinator.panEnabled, isTrue);
      expect(coordinator.scaleEnabled, isTrue);

      // Nhấc ngón 1 -> còn 1 ngón -> VẪN GIỮ viewportGesture, panEnabled về false
      coordinator.onPointerUp(const PointerUpEvent(pointer: 1, position: Offset(100, 100)));
      expect(coordinator.activePointerCount, 1);
      expect(coordinator.state, TableGestureState.viewportGesture);
      expect(coordinator.panEnabled, isFalse); // Ngón còn lại không thể pan

      // Nhấc nốt ngón 2 -> trở về idle hoàn toàn
      coordinator.onPointerUp(const PointerUpEvent(pointer: 2, position: Offset(200, 200)));
      expect(coordinator.activePointerCount, 0);
      expect(coordinator.state, TableGestureState.idle);
    });
  });

  group('Nghiệm thu thực tế trên TableStageScreen (InteractiveViewer + BilliardTableCanvas)', () {
    late TableEditorController controller;

    setUp(() {
      controller = TableEditorController(
        initialScene: DiagramScene(
          id: 'test_stage_scene',
          balls: const [
            Ball(id: 'white', color: BallColor.white, center: DiagramPoint(94.0, 280.0)),
            Ball(id: 'yellow', color: BallColor.yellow, center: DiagramPoint(94.0, 100.0)),
            Ball(id: 'red', color: BallColor.red, center: DiagramPoint(40.0, 50.0)),
          ],
        ),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    Widget buildTestApp() {
      return MaterialApp(
        home: Scaffold(
          body: TableStageScreen(
            controller: controller,
            returnSceneOnSave: true,
          ),
        ),
      );
    }

    testWidgets('1. Kéo từng bi bằng một pointer: Tọa độ bi đổi, 2 bi kia giữ nguyên, ma trận khung nhìn không đổi',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final ivFinder = find.byType(InteractiveViewer);
      expect(ivFinder, findsOneWidget);
      final ivWidget = tester.widget<InteractiveViewer>(ivFinder);
      final initialMatrix = ivWidget.transformationController!.value.clone();

      final canvasFinder = find.byType(BilliardTableCanvas);
      expect(canvasFinder, findsOneWidget);
      final canvasBox = tester.renderObject<RenderBox>(canvasFinder);
      final mapper = TableCoordinateMapper(canvasSize: canvasBox.size);

      // Điểm màn hình của bi trắng
      final whiteCanvasPos = mapper.diagramToScreen(const DiagramPoint(94.0, 280.0));
      final whiteGlobalPos = canvasBox.localToGlobal(whiteCanvasPos);

      // 1 pointer kéo bi trắng đi xuống 40 px trên màn hình
      final gesture = await tester.startGesture(whiteGlobalPos);
      await tester.pump();
      await gesture.moveBy(const Offset(0.0, 40.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Kiểm tra: Bi trắng đã thay đổi tọa độ (kéo xuống trên màn hình làm giảm Y sơ đồ do trục Y hướng lên)
      final updatedWhite = controller.scene.balls.firstWhere((b) => b.id == 'white');
      expect(updatedWhite.center.y, isNot(280.0));
      expect(updatedWhite.center.y, closeTo(262.05, 0.5));

      // Kiểm tra: Hai bi vàng và đỏ giữ nguyên 100%
      final updatedYellow = controller.scene.balls.firstWhere((b) => b.id == 'yellow');
      final updatedRed = controller.scene.balls.firstWhere((b) => b.id == 'red');
      expect(updatedYellow.center.x, 94.0);
      expect(updatedYellow.center.y, 100.0);
      expect(updatedRed.center.x, 40.0);
      expect(updatedRed.center.y, 50.0);

      // Kiểm tra: Ma trận khung nhìn KHÔNG ĐỔI (bàn đứng yên, không pan)
      final afterMatrix = ivWidget.transformationController!.value;
      expect(afterMatrix, equals(initialMatrix));
    });

    testWidgets('2. Pinch/pan bằng hai pointer: Ma trận thay đổi, toàn bộ dữ liệu scene giữ nguyên',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final ivFinder = find.byType(InteractiveViewer);
      final ivWidget = tester.widget<InteractiveViewer>(ivFinder);
      final initialMatrix = ivWidget.transformationController!.value.clone();

      final sceneBefore = controller.scene;

      // Tạo 2 con trỏ zoom/pinch
      final touch1 = await tester.createGesture(pointer: 1);
      final touch2 = await tester.createGesture(pointer: 2);

      await touch1.down(const Offset(200.0, 500.0));
      await touch2.down(const Offset(340.0, 500.0));
      await tester.pump();

      // Kéo dãn hai ngón ra xa nhau (pinch zoom)
      await touch1.moveBy(const Offset(-60.0, 0.0));
      await touch2.moveBy(const Offset(60.0, 0.0));
      await tester.pump();

      await touch1.up();
      await touch2.up();
      await tester.pumpAndSettle();

      // Kiểm tra: Ma trận khung nhìn ĐÃ THAY ĐỔI
      final matrixAfter = ivWidget.transformationController!.value;
      expect(matrixAfter, isNot(equals(initialMatrix)));
      expect(matrixAfter.getMaxScaleOnAxis(), greaterThan(1.0));

      // Kiểm tra: Toàn bộ dữ liệu scene giữ nguyên 100%
      expect(controller.scene.balls.length, sceneBefore.balls.length);
      for (int i = 0; i < sceneBefore.balls.length; i++) {
        expect(controller.scene.balls[i].center.x, sceneBefore.balls[i].center.x);
        expect(controller.scene.balls[i].center.y, sceneBefore.balls[i].center.y);
      }
    });

    testWidgets('3. Sau zoom/pan, chạm đúng tâm bi đang nhìn thấy rồi kéo: Chọn đúng bi, bi bám ngón tay, bàn không trôi',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final ivWidget = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final canvasBox = tester.renderObject<RenderBox>(find.byType(BilliardTableCanvas));
      final mapper = TableCoordinateMapper(canvasSize: canvasBox.size);

      // Zoom khung nhìn lên 1.5x và pan (0, -50) qua transformationController
      ivWidget.transformationController!.value = Matrix4.identity()
        ..translateByDouble(0.0, -50.0, 0.0, 1.0)
        ..scaleByDouble(1.5, 1.5, 1.5, 1.0);
      await tester.pumpAndSettle();

      final matrixCurrent = ivWidget.transformationController!.value.clone();

      // Vị trí bi trắng (94.0, 280.0) trên màn hình sau zoom/pan (ở vùng giữa bàn, thoáng đãng)
      final whiteCanvasPos = mapper.diagramToScreen(const DiagramPoint(94.0, 280.0));
      final whiteGlobalPos = canvasBox.localToGlobal(whiteCanvasPos);

      // Chạm đúng tâm bi trắng đang nhìn thấy rồi kéo
      final drag = await tester.startGesture(whiteGlobalPos);
      await tester.pump();

      // Chọn đúng bi trắng
      expect(controller.selectedBallId, 'white');

      // Kéo thêm 30px ngang, 20px dọc
      await drag.moveBy(const Offset(30.0, 20.0));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      // Bi trắng di chuyển bám ngón tay
      final movedWhite = controller.scene.balls.firstWhere((b) => b.id == 'white');
      expect(movedWhite.center.x, greaterThan(94.0));
      expect(movedWhite.center.y, isNot(280.0));

      // Bàn không bị trôi theo (ma trận giữ nguyên)
      expect(ivWidget.transformationController!.value, equals(matrixCurrent));
    });

    testWidgets('4. Hai ngón -> nhấc một ngón -> di chuyển ngón còn lại: Không kéo bi hoặc tạo điểm ngoài ý muốn',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final canvasBox = tester.renderObject<RenderBox>(find.byType(BilliardTableCanvas));
      final mapper = TableCoordinateMapper(canvasSize: canvasBox.size);
      final whitePos = canvasBox.localToGlobal(mapper.diagramToScreen(const DiagramPoint(94.0, 280.0)));

      final touch1 = await tester.createGesture(pointer: 1);
      final touch2 = await tester.createGesture(pointer: 2);

      await touch1.down(const Offset(200.0, 400.0));
      await touch2.down(const Offset(300.0, 400.0));
      await tester.pump();

      // Di chuyển 2 ngón
      await touch1.moveBy(const Offset(-20.0, 0.0));
      await touch2.moveBy(const Offset(20.0, 0.0));
      await tester.pump();

      // Nhấc 1 ngón
      await touch1.up();
      await tester.pump();

      // Di chuyển ngón còn lại qua vị trí bi trắng
      await touch2.moveTo(whitePos);
      await tester.pump();
      await touch2.moveBy(const Offset(0.0, 50.0));
      await tester.pump();
      await touch2.up();
      await tester.pumpAndSettle();

      // Bi trắng KHÔNG bị kéo di chuyển bởi ngón tay sót lại
      final whiteBall = controller.scene.balls.firstWhere((b) => b.id == 'white');
      expect(whiteBall.center.x, 94.0);
      expect(whiteBall.center.y, 280.0);
    });

    testWidgets('5. Chế độ vẽ đường: 1 ngón vẽ đường; 2 ngón zoom không tạo điểm vẽ',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Bật chế độ vẽ đường thẳng/gấp khúc
      controller.setToolMode(EditorToolMode.drawPolyline);
      await tester.pumpAndSettle();

      final canvasBox = tester.renderObject<RenderBox>(find.byType(BilliardTableCanvas));
      final mapper = TableCoordinateMapper(canvasSize: canvasBox.size);

      final pt1 = canvasBox.localToGlobal(mapper.diagramToScreen(const DiagramPoint(50.0, 100.0)));
      final pt2 = canvasBox.localToGlobal(mapper.diagramToScreen(const DiagramPoint(120.0, 200.0)));

      // 1 ngón chạm đặt 2 điểm
      await tester.tapAt(pt1);
      await tester.pumpAndSettle();
      await tester.tapAt(pt2);
      await tester.pumpAndSettle();

      expect(controller.draftPoints.length, 2);

      // Thao tác 2 ngón zoom
      final t1 = await tester.createGesture(pointer: 10);
      final t2 = await tester.createGesture(pointer: 11);
      await t1.down(const Offset(100, 300));
      await t2.down(const Offset(200, 300));
      await tester.pump();
      await t1.moveBy(const Offset(-30, 0));
      await t2.moveBy(const Offset(30, 0));
      await tester.pump();
      await t1.up();
      await t2.up();
      await tester.pumpAndSettle();

      // Không tự động thêm điểm vẽ trong lúc zoom 2 ngón
      expect(controller.draftPoints.length, 2);
    });

    testWidgets('6. Kéo bi ra băng/chạm bi khác: Tuân thủ giới hạn và tạo đúng 1 bước undo',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final canvasBox = tester.renderObject<RenderBox>(find.byType(BilliardTableCanvas));
      final mapper = TableCoordinateMapper(canvasSize: canvasBox.size);
      final redPos = canvasBox.localToGlobal(mapper.diagramToScreen(const DiagramPoint(40.0, 50.0)));

      // Kéo bi đỏ sang trái vượt mép bàn
      final drag = await tester.startGesture(redPos);
      await tester.pump();
      await drag.moveBy(const Offset(-200.0, 0.0));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      // Bi đỏ bị giữ lại đúng mép băng (r = 6.15)
      final redBall = controller.scene.balls.firstWhere((b) => b.id == 'red');
      expect(redBall.center.x, closeTo(TableConstants.defaultBallRadius, 1e-4));

      // Bấm Undo: Bi đỏ trở về vị trí cũ (40.0, 50.0)
      expect(controller.canUndo, isTrue);
      controller.undo();
      await tester.pumpAndSettle();
      final redUndo = controller.scene.balls.firstWhere((b) => b.id == 'red');
      expect(redUndo.center.x, 40.0);
      expect(redUndo.center.y, 50.0);
    });

    testWidgets('7. Chạm toolbar hoặc nút Vừa màn hình không tác động canvas bên dưới',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Zoom trước đó
      final ivWidget = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      ivWidget.transformationController!.value = Matrix4.identity()
        ..scaleByDouble(2.0, 2.0, 2.0, 1.0);
      await tester.pumpAndSettle();
      expect(ivWidget.transformationController!.value.getMaxScaleOnAxis(), 2.0);

      // Bấm nút Vừa màn hình trên thanh công cụ phải
      final fitBtn = find.byKey(const Key('fit_screen_button'));
      expect(fitBtn, findsOneWidget);
      await tester.tap(fitBtn);
      await tester.pumpAndSettle();

      // Ma trận được đặt lại về identity
      expect(ivWidget.transformationController!.value, equals(Matrix4.identity()));
      // Không làm mất bi hay thay đổi dữ liệu scene
      expect(controller.scene.balls.length, 3);
    });
  });
}
