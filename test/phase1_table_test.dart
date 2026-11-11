import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/geometry/table_constants.dart';
import 'package:libre_billiard_notebook/geometry/table_geometry.dart';
import 'package:libre_billiard_notebook/main.dart';
import 'package:libre_billiard_notebook/models/models.dart';
import 'package:libre_billiard_notebook/repositories/scene_storage.dart';
import 'package:libre_billiard_notebook/state/table_editor_controller.dart';
import 'package:libre_billiard_notebook/ui/screens/table_stage_screen.dart';

void main() {
  group('A.2 & A.3: Tính bất biến và kiểm tra toàn vẹn DiagramScene', () {
    test('F.8: Danh sách trong DiagramScene bất biến và bản cũ không bị sửa theo thao tác sau',
        () {
      final sourceBalls = [
        const Ball(
          id: 'ball_white',
          color: BallColor.white,
          label: '1',
          center: DiagramPoint(50.0, 100.0),
        ),
        const Ball(
          id: 'ball_yellow',
          color: BallColor.yellow,
          label: '2',
          center: DiagramPoint(100.0, 200.0),
        ),
        const Ball(
          id: 'ball_red',
          color: BallColor.red,
          label: '3',
          center: DiagramPoint(140.0, 260.0),
        ),
      ];
      final scene = DiagramScene(id: 's1', balls: sourceBalls);

      // Sửa danh sách đầu vào bên ngoài không làm đổi scene
      sourceBalls.clear();
      expect(scene.balls.length, 3);

      // Danh sách cung cấp ra ngoài không cho phép sửa trực tiếp
      expect(
        () => scene.balls.add(scene.balls.first),
        throwsUnsupportedError,
      );
      expect(
        () => scene.paths.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => scene.annotations.clear(),
        throwsUnsupportedError,
      );

      // Thao tác qua controller không làm thay đổi bản snapshot trong undoHistory
      final controller = TableEditorController(initialScene: scene);
      controller.setBallPosition('ball_white', const DiagramPoint(60.0, 110.0));
      expect(controller.undoHistory.length, 1);
      expect(
        controller.undoHistory.first.balls.first.center,
        const DiagramPoint(50.0, 100.0),
      );
      expect(
        controller.scene.balls.first.center,
        const DiagramPoint(60.0, 110.0),
      );
    });

    test('Kiểm tra scene từ chối dữ liệu lỗi (NaN, r <= 0, trùng ID, ngoài bàn, chồng bi)',
        () {
      final invalidRadius = DiagramScene(
        id: 'bad_r',
        balls: const [
          Ball(
            id: 'b1',
            color: BallColor.white,
            center: DiagramPoint(94, 94),
            radius: 0,
          ),
        ],
      );
      expect(invalidRadius.validatePhase1(), isNotNull);

      final duplicateIds = DiagramScene(
        id: 'dup_id',
        balls: const [
          Ball(id: 'b1', color: BallColor.white, center: DiagramPoint(40, 40)),
          Ball(id: 'b1', color: BallColor.red, center: DiagramPoint(80, 80)),
        ],
      );
      expect(duplicateIds.validatePhase1(), contains('trùng'));

      final outOfBounds = DiagramScene(
        id: 'oob',
        balls: const [
          Ball(id: 'b1', color: BallColor.white, center: DiagramPoint(2.0, 50)),
        ],
      );
      expect(outOfBounds.validatePhase1(), isNotNull);

      final overlapping = DiagramScene(
        id: 'overlap',
        balls: const [
          Ball(id: 'b1', color: BallColor.white, center: DiagramPoint(50, 50)),
          Ball(id: 'b2', color: BallColor.red, center: DiagramPoint(54, 50)),
        ],
      );
      expect(overlapping.validatePhase1(), contains('chồng'));

      // fromJson không âm thầm sửa dữ liệu lỗi
      expect(
        () => DiagramScene.fromJson(overlapping.toJson()),
        throwsFormatException,
      );
      expect(
        () => DiagramPoint.fromJson({'x': double.nan, 'y': 10}),
        throwsFormatException,
      );
    });
  });

  group('C & D: Hệ tọa độ, giới hạn bàn và va chạm tĩnh', () {
    test('F.1: Round-trip bàn -> màn hình -> bàn tại 4 góc, khung và tâm đạt sai số < 1e-9',
        () {
      for (final canvasSize in const [Size(360, 640), Size(800, 360)]) {
        final mapper = TableCoordinateMapper(canvasSize: canvasSize);
        const testPoints = [
          DiagramPoint(0, 0),
          DiagramPoint(188, 0),
          DiagramPoint(0, 376),
          DiagramPoint(188, 376),
          DiagramPoint(94, 188),
          DiagramPoint(TableConstants.frameMinX, TableConstants.frameMinY),
          DiagramPoint(TableConstants.frameMaxX, TableConstants.frameMaxY),
        ];

        for (final pt in testPoints) {
          final screen = mapper.diagramToScreen(pt);
          final back = mapper.screenToDiagram(screen);
          expect((back.x - pt.x).abs(), lessThan(1e-9));
          expect((back.y - pt.y).abs(), lessThan(1e-9));
        }

        // Kiểm tra trục Y tăng lên trên (điểm y lớn hơn có screenY nhỏ hơn)
        expect(
          mapper.diagramToScreen(const DiagramPoint(94, 300)).dy,
          lessThan(mapper.diagramToScreen(const DiagramPoint(94, 100)).dy),
        );

        // Kiểm tra toàn khung không cắt mép màn hình
        final topLeftFrame = mapper.diagramToScreen(
          const DiagramPoint(TableConstants.frameMinX, TableConstants.frameMaxY),
        );
        final bottomRightFrame = mapper.diagramToScreen(
          const DiagramPoint(TableConstants.frameMaxX, TableConstants.frameMinY),
        );
        expect(topLeftFrame.dx, greaterThanOrEqualTo(0.0));
        expect(topLeftFrame.dy, greaterThanOrEqualTo(0.0));
        expect(bottomRightFrame.dx, lessThanOrEqualTo(canvasSize.width + 1e-9));
        expect(bottomRightFrame.dy, lessThanOrEqualTo(canvasSize.height + 1e-9));
      }
    });

    test('F.2 & F.3: Kéo vào 4 góc, 4 cạnh và vượt ra ngoài khung vẫn nằm hợp lệ trong lòng bàn',
        () {
      final controller = TableEditorController();
      const r = TableConstants.defaultBallRadius;

      const extremeTargets = [
        DiagramPoint(-40, -40), // góc dưới-trái ngoài khung
        DiagramPoint(250, -40), // góc dưới-phải ngoài khung
        DiagramPoint(-40, 420), // góc trên-trái ngoài khung
        DiagramPoint(250, 420), // góc trên-phải ngoài khung
        DiagramPoint(-30, 94),  // băng trái ngoài khung
        DiagramPoint(230, 94),  // băng phải ngoài khung
        DiagramPoint(94, -30),  // băng dưới ngoài khung
        DiagramPoint(94, 415),  // băng trên ngoài khung
      ];

      for (final target in extremeTargets) {
        controller.beginBallDrag('ball_white');
        controller.updateBallDrag(target);
        controller.endBallDrag();

        final white = controller.balls.firstWhere((b) => b.id == 'ball_white');
        expect(white.center.x, inInclusiveRange(r, 188.0 - r));
        expect(white.center.y, inInclusiveRange(r, 376.0 - r));
        expect(controller.scene.validatePhase1(), isNull);
      }
    });

    test('F.4: Kéo bi vào bi khác (kể cả sát góc) không đẩy bi kia, không chồng và không nhảy qua phía đối diện',
        () {
      final cornerScene = DiagramScene(
        id: 'corner_block',
        balls: const [
          Ball(id: 'ball_white', color: BallColor.white, center: DiagramPoint(30, 4)),
          Ball(id: 'ball_yellow', color: BallColor.yellow, center: DiagramPoint(4, 4)),
          Ball(id: 'ball_red', color: BallColor.red, center: DiagramPoint(100, 200)),
        ],
      );
      final controller = TableEditorController(initialScene: cornerScene);

      // Kéo bi trắng đâm thẳng về phía góc (4,4) đang có bi vàng và vượt qua về (-10, 4)
      controller.beginBallDrag('ball_white');
      controller.updateBallDrag(const DiagramPoint(-10, 4));
      controller.endBallDrag();

      final white = controller.balls.firstWhere((b) => b.id == 'ball_white');
      final yellow = controller.balls.firstWhere((b) => b.id == 'ball_yellow');

      // Bi vàng không bị đẩy
      expect(yellow.center, const DiagramPoint(4, 4));
      // Bi trắng không chồng lấp và ở phía bên phải của bi vàng (không nhảy sang phía đối diện)
      expect(white.center.x, greaterThanOrEqualTo(yellow.center.x + 8.0 - 1e-4));
      expect(white.center.distanceTo(yellow.center), greaterThanOrEqualTo(8.0 - 1e-6));
      expect(controller.scene.validatePhase1(), isNull);

      // Thử kéo bi trắng xuyên thẳng qua tâm bi đỏ từ dưới lên trên giữa bàn
      controller.setBallPosition('ball_white', const DiagramPoint(100, 170));
      controller.beginBallDrag('ball_white');
      controller.updateBallDrag(const DiagramPoint(100, 240));
      controller.endBallDrag();

      final whiteAfter = controller.balls.firstWhere((b) => b.id == 'ball_white');
      final redAfter = controller.balls.firstWhere((b) => b.id == 'ball_red');
      expect(redAfter.center, const DiagramPoint(100, 200));
      // Phải dừng ở phía dưới (y < 200), không nhảy sang phía trên (y > 200)
      expect(whiteAfter.center.y, lessThan(redAfter.center.y));
      expect(whiteAfter.center.distanceTo(redAfter.center), greaterThanOrEqualTo(8.0 - 1e-6));
    });

    test('F.5: Chạm lệch tâm rồi kéo không làm bi nhảy tâm về điểm chạm ở bước đầu', () {
      final controller = TableEditorController();
      // Tâm bi trắng mặc định ở (94, 94). Chạm lệch tâm tại (96, 95).
      controller.beginBallDrag(
        'ball_white',
        touchPoint: const DiagramPoint(96.0, 95.0),
      );
      // Kéo ngón tay lên (96, 98) (+0, +3)
      controller.updateBallDragFromTouch(const DiagramPoint(96.0, 98.0));
      final white = controller.balls.firstWhere((b) => b.id == 'ball_white');
      expect(white.center.x, closeTo(94.0, 1e-9));
      expect(white.center.y, closeTo(97.0, 1e-9));
      controller.endBallDrag();
    });

    test('D.9: Vùng bắt chạm giao nhau chọn bi gần nhất ổn định', () {
      final scene = DiagramScene(
        id: 'close_balls',
        balls: const [
          Ball(id: 'ball_white', color: BallColor.white, center: DiagramPoint(90, 100)),
          Ball(id: 'ball_yellow', color: BallColor.yellow, center: DiagramPoint(100, 100)),
          Ball(id: 'ball_red', color: BallColor.red, center: DiagramPoint(150, 300)),
        ],
      );
      final mapper = TableCoordinateMapper(canvasSize: const Size(360, 640));
      // Điểm gần bi vàng hơn bi trắng
      final nearYellow = mapper.diagramToScreen(const DiagramPoint(97, 100));
      final hit1 = BallPlacementValidator.hitTestBall(
        screenPosition: nearYellow,
        balls: scene.balls,
        mapper: mapper,
      );
      expect(hit1?.id, 'ball_yellow');

      // Điểm gần bi trắng hơn bi vàng
      final nearWhite = mapper.diagramToScreen(const DiagramPoint(93, 100));
      final hit2 = BallPlacementValidator.hitTestBall(
        screenPosition: nearWhite,
        balls: scene.balls,
        mapper: mapper,
      );
      expect(hit2?.id, 'ball_white');
    });

    test('F.6 & F.7: Khóa bi, Undo/Redo, Reset và kéo không đổi vị trí không tạo Undo',
        () {
      final controller = TableEditorController();

      // 1. Kéo không đổi vị trí -> không tạo Undo
      controller.beginBallDrag('ball_white');
      controller.endBallDrag();
      expect(controller.canUndo, isFalse);

      // 2. Kéo bi nhiều frame -> chỉ 1 bước Undo
      controller.beginBallDrag('ball_white');
      controller.updateBallDrag(const DiagramPoint(94, 110));
      controller.updateBallDrag(const DiagramPoint(94, 120));
      controller.updateBallDrag(const DiagramPoint(94, 130));
      controller.endBallDrag();
      expect(controller.undoHistory.length, 1);

      // 3. Nhập X/Y hợp lệ -> thêm 1 bước Undo
      expect(
        controller.setBallPosition('ball_white', const DiagramPoint(80, 130)),
        isNull,
      );
      expect(controller.undoHistory.length, 2);

      // 4. Khóa bi -> từ chối kéo và nhập X/Y
      controller.toggleBallLock('ball_white');
      expect(controller.beginBallDrag('ball_white'), isNull);
      expect(
        controller.setBallPosition('ball_white', const DiagramPoint(50, 50)),
        contains('khóa'),
      );
      expect(controller.undoHistory.length, 3);

      // 5. Undo rồi thao tác mới -> xóa nhánh Redo
      controller.undo(); // mở khóa lại
      expect(controller.canRedo, isTrue);
      controller.setBallPosition('ball_yellow', const DiagramPoint(60, 210));
      expect(controller.canRedo, isFalse);

      // 6. Đặt lại là thao tác có thể Undo
      controller.resetBalls();
      expect(
        controller.balls.firstWhere((b) => b.id == 'ball_white').center,
        const DiagramPoint(94.0, 94.0),
      );
      controller.undo();
      expect(
        controller.balls.firstWhere((b) => b.id == 'ball_white').center,
        const DiagramPoint(80.0, 130.0),
      );
      controller.redo();
      expect(
        controller.balls.firstWhere((b) => b.id == 'ball_white').center,
        const DiagramPoint(94.0, 94.0),
      );
    });
  });

  group('B, E & F: Widget tests cho Dựng thế bi, xoay màn hình, bàn phím & Pan Cancel', () {
    testWidgets('Mở Dựng thế bi từ tab Hình bi, không hiển thị thuật ngữ Phase hay Đã lưu',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        LibreBilliardApp(sceneStorage: MemorySceneStorage()),
      );

      // Chuyển sang tab Hình bi
      await tester.tap(find.text('Hình bi'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Phase'), findsNothing);
      expect(find.text('Dựng thế bi'), findsWidgets);

      // Bấm nút mở màn hình Dựng thế bi
      await tester.tap(find.byKey(const Key('empty_open_table_stage')));
      await tester.pumpAndSettle();

      expect(find.byType(TableStageScreen), findsOneWidget);
      expect(find.textContaining('Đã lưu'), findsNothing);
      expect(find.textContaining('Phase'), findsNothing);
    });

    testWidgets('F.5 & F.10: Chạm kéo trên canvas thật & Pan cancel không để kẹt trạng thái',
        (WidgetTester tester) async {
      final controller = TableEditorController();
      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      final canvasFinder = find.byKey(const Key('billiard_table_canvas'));
      final canvasTopLeft = tester.getTopLeft(canvasFinder);
      final canvasSize = tester.getSize(canvasFinder);
      final mapper = TableCoordinateMapper(canvasSize: canvasSize);

      final whiteStart = controller.balls.first.center;
      final whiteScreen = mapper.diagramToScreen(whiteStart);

      // Chạm lệch tâm +4px theo X trên màn hình
      final touchStartGlobal = canvasTopLeft + whiteScreen + const Offset(4.0, 0.0);
      final gesture = await tester.startGesture(touchStartGlobal);
      // Kéo nhẹ sang phải +10px, lên trên -20px
      await gesture.moveBy(const Offset(10.0, -20.0));
      await tester.pump();

      expect(controller.isDraggingBall, isTrue);
      final movedWhite = controller.balls.first.center;
      // Kiểm tra bi không nhảy về tâm ngón tay mà dịch đúng theo delta
      expect(
        movedWhite.x - whiteStart.x,
        closeTo(10.0 / mapper.scale, 0.2),
      );

      // Gửi pan cancel -> hủy kéo, khôi phục vị trí trước kéo, không mắc kẹt
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(controller.isDraggingBall, isFalse);
      expect(controller.balls.first.center, whiteStart);
      expect(controller.canUndo, isFalse);
    });

    testWidgets('Nhập X/Y lỗi (NaN/ngoài bàn/chồng bi) phản hồi rõ & hợp lệ tạo Undo',
        (WidgetTester tester) async {
      final controller = TableEditorController();
      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('coord_x_input')), 'NaN');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('coordinate_error_text')), findsOneWidget);

      // Nhập tọa độ chồng bi vàng (70, 200)
      await tester.enterText(find.byKey(const Key('coord_x_input')), '70');
      await tester.enterText(find.byKey(const Key('coord_y_input')), '200');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('chồng'), findsOneWidget);

      // Nhập tọa độ hợp lệ (tự đóng sheet khi Đặt thành công)
      await tester.enterText(find.byKey(const Key('coord_x_input')), '120');
      await tester.enterText(find.byKey(const Key('coord_y_input')), '120');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('xy_editor_sheet')), findsNothing);
      expect(
        controller.balls.first.center,
        const DiagramPoint(120.0, 120.0),
      );
      expect(controller.canUndo, isTrue);
    });

    testWidgets('F.9: Xoay dọc/ngang và mở bàn phím không tràn bố cục, giữ nguyên tọa độ bi',
        (WidgetTester tester) async {
      final controller = TableEditorController();
      controller.setBallPosition('ball_white', const DiagramPoint(110.0, 140.0));

      // Dọc (400 x 800)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Mở bàn phím ảo (viewInsets bottom = 300)
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.balls.first.center, const DiagramPoint(110.0, 140.0));

      // Xoay ngang (800 x 400) và đóng bàn phím
      tester.view.viewInsets = FakeViewPadding.zero;
      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.balls.first.center, const DiagramPoint(110.0, 140.0));

      // Xoay ngang + mở bàn phím (800 x 400, inset = 180)
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.balls.first.center, const DiagramPoint(110.0, 140.0));
    });

    testWidgets('B: Thoát khi có thay đổi chưa lưu hỏi Bỏ thay đổi hoặc Tiếp tục chỉnh sửa',
        (WidgetTester tester) async {
      final controller = TableEditorController();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TableStageScreen(controller: controller),
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

      controller.setBallPosition('ball_white', const DiagramPoint(110.0, 110.0));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();

      expect(find.text('Bỏ thay đổi'), findsOneWidget);
      expect(find.text('Tiếp tục chỉnh sửa'), findsOneWidget);

      await tester.tap(find.text('Tiếp tục chỉnh sửa'));
      await tester.pumpAndSettle();
      expect(find.byType(TableStageScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bỏ thay đổi'));
      await tester.pumpAndSettle();
      expect(find.byType(TableStageScreen), findsNothing);
    });
  });

  group('Phản biện 1: Bảo vệ giao dịch kéo', () {
    test('Không nhận beginBallDrag mới khi giao dịch trước chưa xử lý & token sai không hủy được kéo',
        () {
      final controller = TableEditorController();
      final token1 = controller.beginBallDrag('ball_white');
      expect(token1, isNotNull);
      expect(controller.isDraggingBall, isTrue);

      // Giao dịch khác chưa đóng -> từ chối beginBallDrag mới
      expect(controller.beginBallDrag('ball_yellow'), isNull);
      expect(controller.selectedBallId, 'ball_white');

      // Token sai không thể kết thúc hoặc hủy giao dịch đang chạy
      controller.updateBallDrag(const DiagramPoint(110, 110), dragToken: token1! + 99);
      expect(controller.balls.first.center, const DiagramPoint(94, 94));
      expect(controller.cancelBallDrag(dragToken: token1 + 99), isFalse);
      expect(controller.endBallDrag(dragToken: token1 + 99), isFalse);
      expect(controller.isDraggingBall, isTrue);

      // Token đúng mới cập nhật và hủy được
      controller.updateBallDrag(const DiagramPoint(110, 110), dragToken: token1);
      expect(controller.balls.first.center, const DiagramPoint(110, 110));
      expect(controller.cancelBallDrag(dragToken: token1), isTrue);
      expect(controller.isDraggingBall, isFalse);
      expect(controller.balls.first.center, const DiagramPoint(94, 94));
    });

    test('Đang kéo -> Undo bị chặn ở controller, thả tay mới tạo đúng 1 bước Undo', () {
      final controller = TableEditorController();
      // Tạo sẵn 1 bước lịch sử
      controller.setBallPosition('ball_white', const DiagramPoint(80, 80));
      expect(controller.undoHistory.length, 1);

      // Bắt đầu kéo
      final token = controller.beginBallDrag('ball_white');
      expect(token, isNotNull);
      controller.updateBallDrag(const DiagramPoint(120, 120), dragToken: token);

      // Đang kéo -> Undo phải bị từ chối và không làm hỏng kéo
      expect(controller.canUndo, isFalse);
      expect(controller.undo(), isFalse);
      expect(controller.isDraggingBall, isTrue);
      expect(controller.balls.first.center, const DiagramPoint(120, 120));
      expect(controller.undoHistory.length, 1);

      // Thả tay kết thúc giao dịch kéo -> tạo 1 bước Undo thứ 2 theo đúng thứ tự
      expect(controller.endBallDrag(dragToken: token), isTrue);
      expect(controller.isDraggingBall, isFalse);
      expect(controller.undoHistory.length, 2);
      expect(controller.undo(), isTrue);
      expect(controller.balls.first.center, const DiagramPoint(80, 80));
    });

    test('Đang kéo -> khóa bi -> cancel khôi phục đúng vị trí trước kéo và không bị khóa', () {
      final controller = TableEditorController();
      final token = controller.beginBallDrag('ball_white');
      controller.updateBallDrag(const DiagramPoint(130, 140), dragToken: token);

      // Đang kéo -> khóa bi bị vô hiệu hóa ở tầng controller
      expect(controller.toggleBallLock('ball_white'), isFalse);
      expect(controller.balls.first.locked, isFalse);

      // Pan cancel -> khôi phục nguyên vẹn về (94, 94)
      expect(controller.cancelBallDrag(dragToken: token), isTrue);
      expect(controller.balls.first.center, const DiagramPoint(94, 94));
      expect(controller.balls.first.locked, isFalse);
      expect(controller.canUndo, isFalse);
    });

    test('Đang kéo -> Reset -> thả tay không ghi đè hoặc tạo lịch sử sai thứ tự', () {
      final controller = TableEditorController();
      controller.setBallPosition('ball_white', const DiagramPoint(60, 60));

      final token = controller.beginBallDrag('ball_white');
      controller.updateBallDrag(const DiagramPoint(125, 125), dragToken: token);

      // Đang kéo -> Reset bị chặn ở tầng controller
      expect(controller.resetBalls(), isFalse);
      expect(controller.balls.first.center, const DiagramPoint(125, 125));

      // Thả tay -> kết thúc giao dịch kéo hợp lệ
      expect(controller.endBallDrag(dragToken: token), isTrue);
      expect(controller.undoHistory.length, 2);

      // Sau khi thả tay mới Reset được và Reset tạo bước Undo hợp lệ
      expect(controller.resetBalls(), isTrue);
      expect(controller.balls.first.center, const DiagramPoint(94, 94));
      expect(controller.undoHistory.length, 3);
    });

    testWidgets('Hai ngón: một ngón giữ bi trên bàn, một ngón bấm toolbar bị vô hiệu hóa an toàn',
        (WidgetTester tester) async {
      final controller = TableEditorController();
      controller.setBallPosition('ball_white', const DiagramPoint(80, 90));

      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      final canvasFinder = find.byKey(const Key('billiard_table_canvas'));
      final canvasTopLeft = tester.getTopLeft(canvasFinder);
      final canvasSize = tester.getSize(canvasFinder);
      final mapper = TableCoordinateMapper(canvasSize: canvasSize);

      final whiteScreen = mapper.diagramToScreen(const DiagramPoint(80, 90));
      final finger1 = await tester.startGesture(canvasTopLeft + whiteScreen);
      await finger1.moveBy(const Offset(24.0, -24.0));
      await tester.pump();

      expect(controller.isDraggingBall, isTrue);
      final draggedPos = controller.balls.first.center;

      // Khi ngón 1 đang giữ bi, các nút toolbar xung đột đều bị vô hiệu hóa
      expect(
        tester.widget<IconButton>(find.byKey(const Key('undo_button'))).onPressed,
        isNull,
      );
      expect(
        tester.widget<PopupMenuButton<String>>(find.byKey(const Key('more_menu_button'))).enabled,
        isFalse,
      );
      expect(
        tester.widget<IconButton>(find.byKey(const Key('lock_ball_button'))).onPressed,
        isNull,
      );

      // Ngón 2 thử chạm trực tiếp vào nút Menu thêm và Khóa bi trên toolbar nổi
      final moreCenter = tester.getCenter(find.byKey(const Key('more_menu_button')));
      final finger2More = await tester.startGesture(moreCenter);
      await finger2More.up();
      await tester.pump();
      expect(find.byKey(const Key('menu_reset_balls')), findsNothing);

      final lockCenter = tester.getCenter(find.byKey(const Key('lock_ball_button')));
      final finger2Lock = await tester.startGesture(lockCenter);
      await finger2Lock.up();
      await tester.pump();

      // Giao dịch kéo của ngón 1 vẫn nguyên vẹn, chưa bị ghi đè
      expect(controller.isDraggingBall, isTrue);
      expect(controller.balls.first.center, draggedPos);
      expect(controller.balls.first.locked, isFalse);

      // Ngón 1 thả tay -> ghi nhận đúng 1 bước Undo cho lần kéo
      await finger1.up();
      await tester.pumpAndSettle();

      expect(controller.isDraggingBall, isFalse);
      expect(controller.balls.first.center, draggedPos);
      expect(controller.undoHistory.length, 2);
    });
  });

  group('Phản biện 2: Bảo toàn độ chính xác tọa độ & xử lý ô nhập dở', () {
    testWidgets('Tọa độ (94.04, 110.04) bấm Đặt không sửa giữ nguyên & không tạo Undo; chỉ sửa X giữ Y thật',
        (WidgetTester tester) async {
      final preciseScene = DiagramScene(
        id: 'precise',
        balls: const [
          Ball(
            id: 'ball_white',
            color: BallColor.white,
            label: '1',
            center: DiagramPoint(94.0416, 110.0416),
          ),
          Ball(
            id: 'ball_yellow',
            color: BallColor.yellow,
            label: '2',
            center: DiagramPoint(70.0, 200.0),
          ),
          Ball(
            id: 'ball_red',
            color: BallColor.red,
            label: '3',
            center: DiagramPoint(118.0, 200.0),
          ),
        ],
      );
      final controller = TableEditorController(initialScene: preciseScene);

      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Bấm Đặt khi không sửa X/Y -> không di chuyển bi, không tạo Undo
      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(
        controller.balls.first.center,
        const DiagramPoint(94.0416, 110.0416),
      );
      expect(controller.canUndo, isFalse);

      // Chỉ sửa X -> Y giữ nguyên đúng giá trị thật 110.0416 (không bị chuỗi làm tròn ghi đè)
      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('coord_x_input')), '120.25');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(
        controller.balls.first.center,
        const DiagramPoint(120.25, 110.0416),
      );
      expect(controller.undoHistory.length, 1);
    });

    testWidgets('Tọa độ (94.04, 110.04) và đặt hai bi vừa tiếp xúc tại tọa độ thập phân',
        (WidgetTester tester) async {
      final scene = DiagramScene(
        id: 'decimal_touch',
        balls: const [
          Ball(
            id: 'ball_white',
            color: BallColor.white,
            label: '1',
            center: DiagramPoint(94.04, 110.04),
          ),
          Ball(
            id: 'ball_yellow',
            color: BallColor.yellow,
            label: '2',
            center: DiagramPoint(70.0, 200.0),
          ),
          Ball(
            id: 'ball_red',
            color: BallColor.red,
            label: '3',
            center: DiagramPoint(118.0, 200.0),
          ),
        ],
      );
      final controller = TableEditorController(initialScene: scene);

      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();
      final xField = tester.widget<TextField>(find.byKey(const Key('coord_x_input')));
      final yField = tester.widget<TextField>(find.byKey(const Key('coord_y_input')));
      expect(xField.controller?.text, '94.04');
      expect(yField.controller?.text, '110.04');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();

      // Chọn bi vàng và đặt vừa tiếp xúc bi trắng tại (94.04, 118.04) (khoảng cách = 8.0 = 2r)
      await tester.tap(find.byKey(const Key('select_ball_yellow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('coord_x_input')), '94.04');
      await tester.enterText(find.byKey(const Key('coord_y_input')), '118.04');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('xy_editor_sheet')), findsNothing);
      final yellow = controller.balls.firstWhere((b) => b.id == 'ball_yellow');
      expect(yellow.center, const DiagramPoint(94.04, 118.04));

      // Thử lấn vào 0.01 -> chồng bi -> phải từ chối
      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('coord_y_input')), '118.03');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('chồng'), findsOneWidget);
      expect(
        controller.balls.firstWhere((b) => b.id == 'ball_yellow').center,
        const DiagramPoint(94.04, 118.04),
      );
    });

    testWidgets('Nhập dở trong lúc ô có focus -> Undo/Redo hủy nháp có chủ đích và không ghi đè vị trí mới',
        (WidgetTester tester) async {
      final controller = TableEditorController();
      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Bước 1: Đặt bi trắng tới (120, 120)
      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('coord_x_input')), '120');
      await tester.enterText(find.byKey(const Key('coord_y_input')), '120');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(controller.balls.first.center, const DiagramPoint(120, 120));

      // Bước 2: Mở lại X/Y, đang có focus ở ô X và nhập dở "175" (chưa bấm Đặt)
      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('coord_x_input')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('coord_x_input')), '175');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const Key('coord_x_input'))).focusNode?.hasFocus,
        isTrue,
      );

      // Bước 3: Hoàn tác (Undo) -> về (94, 94), xả focus và xóa nháp "175"
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.balls.first.center, const DiagramPoint(94, 94));
      expect(
        tester.widget<TextField>(find.byKey(const Key('coord_x_input'))).controller?.text,
        '94',
      );

      // Bấm Đặt ngay sau Undo không làm giá trị cũ "175" âm thầm áp dụng (và đóng sheet)
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(controller.balls.first.center, const DiagramPoint(94, 94));
      expect(controller.canRedo, isTrue);

      // Bước 4: Bấm Làm lại (Redo) -> về (120, 120) rồi mở X/Y nhập tiếp X = 135 (Y giữ 120)
      await tester.tap(find.byKey(const Key('redo_button')));
      await tester.pumpAndSettle();
      expect(controller.balls.first.center, const DiagramPoint(120, 120));

      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('coord_x_input')), '135');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(controller.balls.first.center, const DiagramPoint(135, 120));
    });

    testWidgets('Từ chối Infinity, ngoài bàn và giữ nguyên vị trí hợp lệ',
        (WidgetTester tester) async {
      final controller = TableEditorController();
      await tester.pumpWidget(
        MaterialApp(home: TableStageScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_xy_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('coord_x_input')), 'Infinity');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('coordinate_error_text')), findsOneWidget);
      expect(controller.balls.first.center, const DiagramPoint(94, 94));

      await tester.enterText(find.byKey(const Key('coord_x_input')), '186');
      await tester.tap(find.byKey(const Key('apply_coords_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('coordinate_error_text')), findsOneWidget);
      expect(controller.balls.first.center, const DiagramPoint(94, 94));
    });
  });
}

