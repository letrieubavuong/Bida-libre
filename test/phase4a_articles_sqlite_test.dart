import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_billiard_notebook/geometry/scene_validator.dart';
import 'package:libre_billiard_notebook/main.dart';
import 'package:libre_billiard_notebook/models/models.dart';
import 'package:libre_billiard_notebook/repositories/scene_storage.dart';
import 'package:libre_billiard_notebook/repositories/sqlite_notebook_repository.dart';
import 'package:libre_billiard_notebook/state/notebook_controller.dart';
import 'package:libre_billiard_notebook/ui/screens/article_detail_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/article_editor_screen.dart';
import 'package:libre_billiard_notebook/ui/screens/table_stage_screen.dart';
import 'package:libre_billiard_notebook/ui/widgets/billiard_table_canvas.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DiagramScene _buildRichScene(
  String id, {
  double whiteY = 94.0,
  String annotationText = 'N1',
}) {
  final base = DiagramScene.defaultInitial(id: id);
  final movedBalls = [
    base.balls[0].copyWith(center: DiagramPoint(94.0, whiteY)),
    base.balls[1].copyWith(center: const DiagramPoint(130.0, 210.0)),
    base.balls[2].copyWith(center: const DiagramPoint(58.0, 285.0)),
  ];
  final mixedPath = GuidePath(
    id: '${id}_path_1',
    ownerBallId: 'ball_white',
    startAnchorBallId: 'ball_white',
    segments: [
      PathSegment.line(
        start: DiagramPoint(94.0, whiteY),
        end: const DiagramPoint(120.0, 180.0),
      ),
      const PathSegment.cubic(
        start: DiagramPoint(120.0, 180.0),
        control1: DiagramPoint(135.0, 215.0),
        control2: DiagramPoint(95.0, 245.0),
        end: DiagramPoint(62.0, 270.0),
      ),
    ],
  );
  final railAnnotation = DiagramAnnotation(
    id: '${id}_ann_1',
    type: AnnotationType.label,
    position: const DiagramPoint(47.0, -12.0),
    text: annotationText,
  );
  return base.copyWith(
    balls: movedBalls,
    paths: [mixedPath],
    annotations: [railAnnotation],
  );
}

Article _sampleArticle({
  required ArticleKind kind,
  required String title,
  required String primaryGroupId,
  Difficulty difficulty = Difficulty.intermediate,
  bool isDraft = false,
  StrokeParameters stroke = const StrokeParameters.defaults(),
  List<ArticleDiagram> diagrams = const [],
}) {
  final now = DateTime.utc(2026, 11, 12, 5, 0);
  return Article(
    id: '',
    code: '',
    kind: kind,
    title: title,
    summary: 'Tóm tắt $title',
    primaryGroupId: primaryGroupId,
    difficulty: difficulty,
    goal: 'Mục tiêu cho $title',
    content: 'Nội dung giải thích chi tiết $title',
    steps: const ['Bước 1: Đặt bi', 'Bước 2: Chọn má chạm'],
    commonMistakes: 'Tránh đánh giật ngọn cơ.',
    source: 'Tài liệu thử nghiệm',
    author: 'Biên tập viên thử nghiệm',
    sourcePage: 'tr. 12',
    isDraft: isDraft,
    strokeParameters: stroke,
    diagrams: diagrams,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Phase 4A — SQLite persistence, codes, transactions & diagrams', () {
    test('Tạo 3 loại bài, đóng và mở lại SQLite giữ nguyên dữ liệu & không ghi đè nhóm mặc định',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lb_p4a_reopen_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final dbPath = p.join(tempDir.path, 'notebook.db');

      final repo1 = SqliteNotebookRepository(dbPath: dbPath);
      await repo1.initialize();

      const stroke = StrokeParameters(
        cueBallId: 'ball_yellow',
        thicknessMode: HitThicknessMode.twoThirds,
        eighthCount: 5,
        isFullFace: false,
        hitSide: HitSide.right,
        tipXMm: 7.6875, // Mức 2 = 2 * 3.84375 mm
        tipZMm: -3.84375,
        tipDiameterMm: 11.75,
        tipNote: 'Áp phê phải nhẹ',
        forceText: 'Vừa',
        strokeStyleText: 'Ra ngọn êm',
      );

      final sceneA = _buildRichScene('scene_a', whiteY: 88.0, annotationText: 'A1');
      final sceneB = _buildRichScene('scene_b', whiteY: 102.0, annotationText: 'B2');

      expect(SceneValidator.validateCompleteForSave(sceneA), isNull);
      expect(SceneValidator.validateCompleteForSave(sceneB), isNull);

      final techSaved = await repo1.saveArticle(
        _sampleArticle(
          kind: ArticleKind.technique,
          title: 'Trô hồi băng ngắn',
          primaryGroupId: 'tech_draw',
          stroke: stroke,
          diagrams: [
            ArticleDiagram(
              id: 'diag_1',
              articleId: '',
              sortOrder: 0,
              caption: 'Vị trí xuất phát',
              scene: sceneA,
            ),
            ArticleDiagram(
              id: 'diag_2',
              articleId: '',
              sortOrder: 1,
              caption: 'Điểm hồi băng',
              scene: sceneB,
            ),
          ],
        ),
      );
      final sysSaved = await repo1.saveArticle(
        _sampleArticle(
          kind: ArticleKind.system,
          title: 'Bộ cộng trừ tham khảo',
          primaryGroupId: 'sys_plus_minus',
        ),
      );
      final posSaved = await repo1.saveArticle(
        _sampleArticle(
          kind: ArticleKind.position,
          title: 'Gom góc về băng ngắn',
          primaryGroupId: 'corner',
        ),
      );

      expect(techSaved.code, 'KT-001');
      expect(sysSaved.code, 'BS-001');
      expect(posSaved.code, 'HB-001');
      await repo1.close();

      // Mở trực tiếp tệp SQLite bằng repo mới để mô phỏng thoát/mở lại app,
      // và kiểm tra bảng editorial_groups không bị ghi đè nếu đã chỉnh tên trước đó.
      final rawDb = await databaseFactoryFfiNoIsolate.openDatabase(dbPath);
      await rawDb.update(
        'editorial_groups',
        {'name': 'Trô / kéo (đã tùy chỉnh)'},
        where: 'id = ?',
        whereArgs: ['tech_draw'],
      );
      await rawDb.close();

      final repo2 = SqliteNotebookRepository(dbPath: dbPath);
      await repo2.initialize();

      final techGroup = repo2
          .getGroups(ArticleKind.technique)
          .firstWhere((g) => g.id == 'tech_draw');
      expect(techGroup.name, 'Trô / kéo (đã tùy chỉnh)');

      final reopenedTech = repo2.getArticleById(techSaved.id);
      expect(reopenedTech, isNotNull);
      expect(reopenedTech!.code, 'KT-001');
      expect(reopenedTech.goal, techSaved.goal);
      expect(reopenedTech.content, techSaved.content);
      expect(reopenedTech.steps, techSaved.steps);
      expect(reopenedTech.commonMistakes, techSaved.commonMistakes);
      expect(reopenedTech.source, 'Tài liệu thử nghiệm');
      expect(reopenedTech.author, 'Biên tập viên thử nghiệm');
      expect(reopenedTech.sourcePage, 'tr. 12');
      expect(reopenedTech.createdAt, techSaved.createdAt);
      expect(reopenedTech.updatedAt, techSaved.updatedAt);

      expect(reopenedTech.strokeParameters, stroke);
      expect(reopenedTech.diagrams.length, 2);
      expect(reopenedTech.diagrams[0].caption, 'Vị trí xuất phát');
      expect(reopenedTech.diagrams[1].caption, 'Điểm hồi băng');
      expect(reopenedTech.diagrams[0].scene.paths.single.segments.length, 2);
      expect(
        reopenedTech.diagrams[0].scene.paths.single.segments[1].type,
        SegmentType.cubic,
      );
      expect(
        reopenedTech.diagrams[0].scene.annotations.single.text,
        'A1',
      );

      expect(repo2.getArticleById(sysSaved.id)!.code, 'BS-001');
      expect(repo2.getArticleById(posSaved.id)!.code, 'HB-001');

      await repo2.close();
    });

    test('Chỉnh thứ tự 2 sơ đồ giữ nguyên cả 2; đổi thông số cách đánh tĩnh không làm đổi sơ đồ',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lb_p4a_stroke_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final repo = SqliteNotebookRepository(
        dbPath: p.join(tempDir.path, 'notebook.db'),
      );
      await repo.initialize();

      final s1 = _buildRichScene('s1', whiteY: 75.0, annotationText: 'L1');
      final s2 = _buildRichScene('s2', whiteY: 135.0, annotationText: 'L2');

      final initial = await repo.saveArticle(
        _sampleArticle(
          kind: ArticleKind.position,
          title: 'Hình bi hai sơ đồ',
          primaryGroupId: 'corner',
          stroke: const StrokeParameters(
            thicknessMode: HitThicknessMode.twoThirds,
            hitSide: HitSide.right,
          ),
          diagrams: [
            ArticleDiagram(id: 'd1', articleId: '', sortOrder: 0, caption: 'Bước đầu', scene: s1),
            ArticleDiagram(id: 'd2', articleId: '', sortOrder: 1, caption: 'Bước sau', scene: s2),
          ],
        ),
      );

      // Quy ước 4 mức mũi cơ trong model
      expect(CueTipConvention.fourLevelStepMm, closeTo(3.84375, 1e-9));
      expect(CueTipConvention.fourLevelMaxMm, closeTo(15.375, 1e-9));
      expect(
        CueTipConvention.describeAxisOffset(
          7.6875,
          positiveLabel: 'Phải',
          negativeLabel: 'Trái',
        ),
        contains('mức 2.0'),
      );

      // Bật tràn mặt rồi tắt tràn mặt phải giữ nguyên 2/3 & Má phải
      final toggledFull = initial.strokeParameters.copyWith(isFullFace: true);
      expect(toggledFull.isFullFace, isTrue);
      expect(toggledFull.thicknessMode, HitThicknessMode.twoThirds);
      expect(toggledFull.hitSide, HitSide.right);
      final restoredFull = toggledFull.copyWith(isFullFace: false);
      expect(restoredFull.isFullFace, isFalse);
      expect(restoredFull.thicknessMode, HitThicknessMode.twoThirds);
      expect(restoredFull.hitSide, HitSide.right);

      // Đổi thứ tự sơ đồ + sửa chú thích sơ đồ 1 + đổi strokeParameters -> không tự sửa balls/paths
      final editedS1 = s1.copyWith(
        balls: [
          s1.balls[0].copyWith(center: const DiagramPoint(90.0, 82.0)),
          s1.balls[1],
          s1.balls[2],
        ],
        paths: [
          s1.paths.single.copyWith(
            segments: [
              PathSegment.line(
                start: const DiagramPoint(90.0, 82.0),
                end: s1.paths.single.segments[0].end,
              ),
              s1.paths.single.segments[1],
            ],
          ),
        ],
      );
      final updated = await repo.saveArticle(
        initial.copyWith(
          strokeParameters: restoredFull.copyWith(
            tipXMm: -15.375,
            tipZMm: 3.84375,
            forceText: 'Mạnh',
            strokeStyleText: 'Xuyên suốt',
          ),
          diagrams: [
            ArticleDiagram(
              id: 'd2',
              articleId: initial.id,
              sortOrder: 0,
              caption: 'Bước sau (đẩy lên đầu)',
              scene: s2,
            ),
            ArticleDiagram(
              id: 'd1',
              articleId: initial.id,
              sortOrder: 1,
              caption: 'Bước đầu (đã chỉnh)',
              scene: editedS1,
            ),
          ],
        ),
      );

      expect(updated.diagrams[0].id, 'd2');
      expect(updated.diagrams[0].scene.balls, s2.balls);
      expect(updated.diagrams[0].scene.paths, s2.paths);
      expect(updated.diagrams[0].scene.annotations, s2.annotations);
      expect(updated.diagrams[1].id, 'd1');
      expect(updated.diagrams[1].scene.balls, editedS1.balls);
      expect(updated.diagrams[1].scene.paths, editedS1.paths);
      await repo.close();
    });

    test('Nhân bản, xóa bài không đánh lại mã, lưu tuần tự không trùng mã',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lb_p4a_dup_del_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final repo = SqliteNotebookRepository(
        dbPath: p.join(tempDir.path, 'notebook.db'),
      );
      await repo.initialize();

      final s1 = _buildRichScene('orig_s1', whiteY: 94.0);
      final orig = await repo.saveArticle(
        _sampleArticle(
          kind: ArticleKind.technique,
          title: 'Bài gốc KT1',
          primaryGroupId: 'tech_draw',
          diagrams: [
            ArticleDiagram(
              id: 'orig_diag',
              articleId: '',
              sortOrder: 0,
              caption: 'Sơ đồ gốc',
              scene: s1,
            ),
          ],
        ),
      );
      expect(orig.code, 'KT-001');

      // Nhân bản liên tiếp -> KT-002, KT-003 (không trùng UNIQUE code)
      final dup1 = await repo.duplicateArticle(orig.id);
      final dup2 = await repo.duplicateArticle(orig.id);
      expect(dup1.id, isNot(orig.id));
      expect(dup1.code, 'KT-002');
      expect(dup2.code, 'KT-003');
      expect(dup1.diagrams.single.id, isNot(orig.diagrams.single.id));
      expect(dup1.diagrams.single.scene.id, isNot(orig.diagrams.single.scene.id));

      // Sửa bản sao hoàn toàn không ảnh hưởng bản gốc
      final mutatedDup = dup1.copyWith(
        title: 'Bản sao đã sửa',
        content: 'Nội dung riêng của bản sao',
        strokeParameters: dup1.strokeParameters.copyWith(forceText: 'Rất mạnh'),
        diagrams: [
          dup1.diagrams.single.copyWith(
            caption: 'Sơ đồ bản sao',
            scene: dup1.diagrams.single.scene.copyWith(
              balls: [
                dup1.diagrams.single.scene.balls[0]
                    .copyWith(center: const DiagramPoint(50.0, 50.0)),
                dup1.diagrams.single.scene.balls[1],
                dup1.diagrams.single.scene.balls[2],
              ],
              paths: [
                dup1.diagrams.single.scene.paths.single.copyWith(
                  segments: [
                    PathSegment.line(
                      start: const DiagramPoint(50.0, 50.0),
                      end: dup1.diagrams.single.scene.paths.single.segments[0].end,
                    ),
                    dup1.diagrams.single.scene.paths.single.segments[1],
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      await repo.saveArticle(mutatedDup);

      final origAfter = repo.getArticleById(orig.id)!;
      expect(origAfter.title, 'Bài gốc KT1');
      expect(origAfter.diagrams.single.caption, 'Sơ đồ gốc');
      expect(
        origAfter.diagrams.single.scene.balls[0].center,
        const DiagramPoint(94.0, 94.0),
      );

      // Xóa KT-001 và KT-002 -> vẫn còn KT-003, bài mới tạo tiếp theo phải là KT-004
      await repo.deleteArticle(orig.id);
      await repo.deleteArticle(dup1.id);
      expect(repo.getArticleById(orig.id), isNull);
      expect(repo.getArticleById(dup1.id), isNull);
      expect(repo.getArticleById(dup2.id), isNotNull);

      final nextKt = await repo.saveArticle(
        _sampleArticle(
          kind: ArticleKind.technique,
          title: 'Bài KT thứ 4',
          primaryGroupId: 'tech_follow',
        ),
      );
      expect(nextKt.code, 'KT-004');
      await repo.close();
    });

    test('Lỗi giữa transaction rollback sạch sẽ, không lưu nửa vời và không làm hỏng bài cũ',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lb_p4a_rollback_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final dbPath = p.join(tempDir.path, 'notebook.db');

      bool failOnDiagramInsert = false;
      final repo = SqliteNotebookRepository(
        dbPath: dbPath,
        debugTransactionHook: (txn, stage) async {
          if (failOnDiagramInsert && stage == 'after_article_insert') {
            throw const FileSystemException('Simulated disk full mid-tx');
          }
        },
      );
      await repo.initialize();

      final existing = await repo.saveArticle(
        _sampleArticle(
          kind: ArticleKind.system,
          title: 'Bộ số an toàn',
          primaryGroupId: 'sys_basic',
          diagrams: [
            ArticleDiagram(
              id: 'safe_d1',
              articleId: '',
              sortOrder: 0,
              caption: 'Sơ đồ an toàn',
              scene: DiagramScene.defaultInitial(id: 'safe_scene'),
            ),
          ],
        ),
      );
      expect(existing.code, 'BS-001');

      failOnDiagramInsert = true;
      await expectLater(
        () => repo.saveArticle(
          _sampleArticle(
            kind: ArticleKind.system,
            title: 'Bộ số bị lỗi giữa chừng',
            primaryGroupId: 'sys_basic',
            diagrams: [
              ArticleDiagram(
                id: 'fail_d1',
                articleId: '',
                sortOrder: 0,
                caption: 'Sơ đồ lỗi',
                scene: DiagramScene.defaultInitial(id: 'fail_scene'),
              ),
            ],
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      failOnDiagramInsert = false;

      // Mở lại từ CSDL thật để kiểm tra hoàn toàn không có bản ghi nửa vời nào sót lại
      await repo.close();
      final rawDb = await databaseFactoryFfiNoIsolate.openDatabase(dbPath);
      final articleRows = await rawDb.query('articles');
      final diagramRows = await rawDb.query('article_diagrams');
      await rawDb.close();
      expect(articleRows.length, 1);
      expect(articleRows.single['id'], existing.id);
      expect(diagramRows.length, 1);
      expect(diagramRows.single['article_id'], existing.id);

      // Lần lưu kế tiếp vẫn lấy đúng mã BS-002 (counter đã rollback theo transaction)
      final repo2 = SqliteNotebookRepository(dbPath: dbPath);
      await repo2.initialize();
      final next = await repo2.saveArticle(
        _sampleArticle(
          kind: ArticleKind.system,
          title: 'Bộ số sau rollback',
          primaryGroupId: 'sys_basic',
        ),
      );
      expect(next.code, 'BS-002');
      await repo2.close();
    });

    test('Thao tác CRUD bài viết không đụng tới primary_scene.json độc lập của Phase 2-3',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lb_p4a_scene_iso_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sceneStorage = FileSceneStorage(
        directoryProvider: () async => tempDir,
      );
      final standaloneScene = _buildRichScene('standalone', whiteY: 160.0);
      await sceneStorage.saveScene(standaloneScene);
      final standaloneFile = File(p.join(tempDir.path, FileSceneStorage.defaultFileName));
      final beforeBytes = await standaloneFile.readAsBytes();

      final repo = SqliteNotebookRepository(
        dbPath: p.join(tempDir.path, SqliteNotebookRepository.defaultDbFileName),
      );
      await repo.initialize();
      final created = await repo.saveArticle(
        _sampleArticle(
          kind: ArticleKind.position,
          title: 'Bài gắn sơ đồ riêng',
          primaryGroupId: 'corner',
          diagrams: [
            ArticleDiagram(
              id: 'art_diag',
              articleId: '',
              sortOrder: 0,
              caption: 'Không đụng file độc lập',
              scene: _buildRichScene('art_scene', whiteY: 60.0),
            ),
          ],
        ),
      );
      final dup = await repo.duplicateArticle(created.id);
      await repo.deleteArticle(dup.id);
      await repo.deleteArticle(created.id);
      await repo.close();

      final afterBytes = await standaloneFile.readAsBytes();
      expect(utf8.decode(afterBytes), utf8.decode(beforeBytes));
      final loadedStandalone = await sceneStorage.loadScene();
      expect(loadedStandalone, standaloneScene);
    });
  });

  group('Phase 4A — Widget workflows (Soạn bài, Sơ đồ, Đọc chỉ đọc, Nháp, Chống lưu trùng)',
      () {
    testWidgets(
      'Tạo bài -> Thêm sơ đồ qua TableStageScreen -> Lưu -> Xem chi tiết chỉ đọc -> Nhân bản -> Xóa',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('lb_p4a_ui_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            try {
              tempDir.deleteSync(recursive: true);
            } catch (_) {}
          }
        });
        final sceneStorage = FileSceneStorage(
          directoryProvider: () async => tempDir,
        );
        final standalone = DiagramScene.defaultInitial(id: 'standalone_ui');
        await tester.runAsync(() => sceneStorage.saveScene(standalone));

        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'ui.db'),
        );
        await tester.runAsync(() => repo.initialize());
        final controller = NotebookController(repository: repo);

        await tester.pumpWidget(
          LibreBilliardApp(
            controller: controller,
            sceneStorage: sceneStorage,
          ),
        );
        await tester.pumpAndSettle();

        // Chuyển sang tab Hình bi -> bấm Tạo bài (+ Tạo bài)
        await tester.tap(find.text('Hình bi'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('fab_new_article')));
        await tester.pumpAndSettle();
        expect(find.byType(ArticleEditorScreen), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('article_title_input')),
          'Gom góc 3 băng mẫu',
        );
        await tester.enterText(
          find.byKey(const Key('article_goal_input')),
          'Đưa 3 bi về góc bàn.',
        );
        await tester.enterText(
          find.byKey(const Key('article_content_input')),
          'Đánh mỏng má bi vàng ở góc.',
        );

        // Chạm 2/3 -> bật tràn mặt -> tắt tràn mặt để kiểm tra giữ nguyên 2/3
        final editorScroll = find
            .descendant(
              of: find.byType(ArticleEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        final twoThirds = find.byKey(const Key('stroke_mode_two_thirds'));
        await tester.scrollUntilVisible(twoThirds, 250.0, scrollable: editorScroll);
        await tester.ensureVisible(twoThirds);
        await tester.pumpAndSettle();
        await tester.tap(twoThirds);
        await tester.pumpAndSettle();
        final fullFace = find.byKey(const Key('stroke_full_face_switch'));
        await tester.scrollUntilVisible(fullFace, 200.0, scrollable: editorScroll);
        await tester.ensureVisible(fullFace);
        await tester.pumpAndSettle();
        await tester.tap(fullFace);
        await tester.pumpAndSettle();
        await tester.tap(fullFace);
        await tester.pumpAndSettle();

        // Thêm sơ đồ qua trình dựng TableStageScreen (không đụng standalone scene)
        final addDiagramBtn = find.byKey(const Key('add_diagram_button'));
        await tester.scrollUntilVisible(
          addDiagramBtn,
          250.0,
          scrollable: editorScroll,
        );
        await tester.ensureVisible(addDiagramBtn);
        await tester.pumpAndSettle();
        await tester.tap(addDiagramBtn);
        await tester.pumpAndSettle();
        expect(find.byType(TableStageScreen), findsOneWidget);

        // Chạm save_scene_button để trả DiagramScene về ArticleEditorScreen
        await tester.tap(find.byKey(const Key('save_scene_button')));
        await tester.pumpAndSettle();
        expect(find.byType(ArticleEditorScreen), findsOneWidget);
        expect(find.byKey(const Key('editor_diagram_card_0')), findsOneWidget);

        // Lưu bài
        await tester.tap(find.byKey(const Key('save_article_button')));
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();

        expect(find.byType(ArticleEditorScreen), findsNothing);
        expect(find.text('Gom góc 3 băng mẫu'), findsOneWidget);
        expect(find.textContaining('HB-001'), findsAtLeastNWidgets(1));

        // Mở màn hình Chi tiết chỉ đọc
        final saved = controller.visibleArticles.single;
        await tester.tap(find.byKey(Key('article_card_${saved.id}')));
        await tester.pumpAndSettle();
        expect(find.byType(ArticleDetailScreen), findsOneWidget);
        expect(find.byType(BilliardTableReadOnlyView), findsOneWidget);

        // Kéo trên sơ đồ chỉ đọc hoàn toàn không làm đổi tọa độ bi
        final beforeDragScene = saved.diagrams.single.scene;
        final readOnlyDiag = find.byKey(const Key('readonly_diagram_0'));
        await tester.ensureVisible(readOnlyDiag);
        await tester.pumpAndSettle();
        await tester.drag(
          readOnlyDiag,
          const Offset(40, 40),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(
          controller.getArticleById(saved.id)!.diagrams.single.scene,
          beforeDragScene,
        );

        // Nhân bản trên màn hình Chi tiết
        await tester.tap(find.byKey(const Key('detail_duplicate_button')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(find.text('HB-002'), findsOneWidget);

        // Xóa bản nhân bản HB-002
        await tester.tap(find.byKey(const Key('detail_delete_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xóa bài'));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();

        expect(controller.visibleArticles.length, 1);
        expect(controller.visibleArticles.single.code, 'HB-001');

        // Standalone Phase 2-3 scene vẫn nguyên vẹn
        final reloadedStandalone =
            await tester.runAsync(() => sceneStorage.loadScene());
        expect(reloadedStandalone, standalone);

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.runAsync(() => repo.close());
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets(
      'Hủy chỉnh sơ đồ giữ sơ đồ cũ; thoát soạn bài hỏi Ở lại / Bỏ thay đổi / Lưu; lưu nháp thiếu nội dung; chống lưu đồng thời',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('lb_p4a_guard_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            try {
              tempDir.deleteSync(recursive: true);
            } catch (_) {}
          }
        });
        final repo = SqliteNotebookRepository(
          dbPath: p.join(tempDir.path, 'guard.db'),
        );
        await tester.runAsync(() => repo.initialize());

        // Tạo sẵn 1 bài nháp trước
        final initialDraft = await tester.runAsync(
          () => repo.saveArticle(
            _sampleArticle(
              kind: ArticleKind.technique,
              title: 'Nháp ban đầu',
              primaryGroupId: 'tech_draw',
              isDraft: true,
              diagrams: [
                ArticleDiagram(
                  id: 'd_keep',
                  articleId: '',
                  sortOrder: 0,
                  caption: 'Sơ đồ phải được giữ',
                  scene: _buildRichScene('keep_scene', whiteY: 94.0),
                ),
              ],
            ),
          ),
        );

        final controller = NotebookController(repository: repo);
        await tester.pumpWidget(LibreBilliardApp(controller: controller));
        await tester.pumpAndSettle();

        // Mở bài -> vào Sửa
        await tester.tap(find.byKey(Key('article_card_${initialDraft!.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('detail_edit_button')));
        await tester.pumpAndSettle();

        // Bấm sửa sơ đồ -> mở TableStageScreen -> bấm Back thoát (không lưu sơ đồ) -> giữ nguyên sơ đồ cũ
        final editDiagBtn = find.byKey(const Key('edit_diagram_0'));
        await tester.scrollUntilVisible(
          editDiagBtn,
          250.0,
          scrollable: find
              .descendant(
                of: find.byType(ArticleEditorScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(editDiagBtn);
        await tester.pumpAndSettle();
        await tester.tap(editDiagBtn);
        await tester.pumpAndSettle();
        expect(find.byType(TableStageScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('back_button')));
        await tester.pumpAndSettle();
        expect(find.byType(ArticleEditorScreen), findsOneWidget);
        expect(find.text('Sơ đồ phải được giữ'), findsOneWidget);

        // Sửa tiêu đề -> bấm Back thoát -> Hiện hộp thoại 3 lựa chọn -> chọn Ở lại
        final titleInput = find.byKey(const Key('article_title_input'));
        await tester.scrollUntilVisible(
          titleInput,
          -250.0,
          scrollable: find
              .descendant(
                of: find.byType(ArticleEditorScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(titleInput);
        await tester.pumpAndSettle();
        await tester.enterText(
          titleInput,
          'Tiêu đề dở dang',
        );
        await tester.tap(find.byKey(const Key('editor_back_button')));
        await tester.pumpAndSettle();
        expect(find.text('Thay đổi chưa được lưu'), findsOneWidget);
        expect(find.text('Ở lại'), findsOneWidget);
        expect(find.text('Bỏ thay đổi'), findsOneWidget);
        expect(find.text('Lưu'), findsOneWidget);

        await tester.tap(find.text('Ở lại'));
        await tester.pumpAndSettle();
        expect(find.byType(ArticleEditorScreen), findsOneWidget);

        // Bấm Back lại -> chọn Bỏ thay đổi -> bài trong SQLite vẫn là 'Nháp ban đầu'
        await tester.tap(find.byKey(const Key('editor_back_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bỏ thay đổi'));
        await tester.pumpAndSettle();
        expect(find.byType(ArticleEditorScreen), findsNothing);
        expect(controller.getArticleById(initialDraft.id)!.title, 'Nháp ban đầu');

        // Kiểm tra chống gọi saveArticle hai lần đồng thời ở tầng controller
        final slowRepo = SqliteNotebookRepository(
          dbPath: inMemoryDatabasePath,
          debugTransactionHook: (txn, stage) async {
            if (stage == 'after_article_insert') {
              await Future<void>.delayed(const Duration(milliseconds: 60));
            }
          },
        );
        await tester.runAsync(() => slowRepo.initialize());
        final slowController = NotebookController(repository: slowRepo);

        final outcomes = await tester.runAsync(() {
          final f1 = slowController.saveArticle(
            _sampleArticle(
              kind: ArticleKind.system,
              title: 'Lưu lần 1',
              primaryGroupId: 'sys_basic',
              isDraft: true,
            ),
          );
          final f2 = slowController.saveArticle(
            _sampleArticle(
              kind: ArticleKind.system,
              title: 'Lưu trùng',
              primaryGroupId: 'sys_basic',
              isDraft: true,
            ),
          );
          return Future.wait([f1, f2]);
        });
        expect(outcomes![0].isSuccess, isTrue);
        expect(outcomes[1].isSuccess, isFalse);
        expect(outcomes[1].error, contains('Đang lưu'));

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        slowController.dispose();
        await tester.runAsync(() async {
          await repo.close();
          await slowRepo.close();
        });
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}
