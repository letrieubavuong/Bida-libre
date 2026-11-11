# LibreBilliard (`libre_billiard_notebook`)

Ứng dụng Flutter Android tiếng Việt đóng vai trò **sổ tay biên soạn và tra cứu sơ đồ tĩnh** cho bộ môn billiard libre (Kĩ thuật, Bộ số, Hình bi), ưu tiên sử dụng offline trên điện thoại.

## Phạm vi và nguyên tắc cốt lõi

- **Không mô phỏng vật lý:** Không có engine động lực học, solver va chạm, tính xoáy, tính tốc độ bi, dự đoán ghi điểm hay Play/Pause/timeline.
- **Sơ đồ tĩnh do người soạn vẽ:** Bi, đường hướng dẫn (thẳng / Bézier) và thông số đánh chỉ mang tính trình bày/tra cứu tĩnh; thay thông số đánh không tự sửa đường bi.
- **Offline hoàn toàn:** Không tài khoản, backend hay đồng bộ đám mây.

## Cấu trúc thư mục

```text
libre_billiard_notebook/
├── lib/
│   ├── main.dart                     # Điểm khởi chạy ứng dụng Material 3
│   ├── geometry/
│   │   ├── path_geometry.dart        # Hình học đường thẳng/gấp khúc, bắt dính & kiểm tra giới hạn
│   │   ├── table_constants.dart      # Hằng số đơn vị sơ đồ bàn 188x376 (1:2)
│   │   └── table_geometry.dart       # Ánh xạ tọa độ bàn <-> màn hình & kiểm tra/kẹp vị trí bi
│   ├── models/
│   │   ├── enums.dart                # ArticleKind, Difficulty, PracticeStatus, BallColor, ArrowMode...
│   │   ├── article.dart              # Model bài viết (Kĩ thuật, Bộ số, Hình bi)
│   │   ├── diagram_scene.dart        # Model scene vector bất biến, validateScene() & kiểm tra schema
│   │   ├── library_meta.dart         # EditorialGroup, Tag, Collection, PracticeEntry, AssetRef
│   │   └── models.dart               # Barrel exports
│   ├── repositories/
│   │   ├── notebook_repository.dart  # Giao diện kho lưu trữ & InMemoryNotebookRepository
│   │   └── scene_storage.dart        # Lưu/tải nguyên tử một sơ đồ JSON trong thư mục ứng dụng
│   ├── state/
│   │   ├── notebook_controller.dart  # Trạng thái điều hướng 3 tab & bộ lọc dùng chung
│   │   └── table_editor_controller.dart # Trạng thái dựng bi, vẽ/sửa đường gấp khúc, Undo/Redo, lưu/tải
│   └── ui/
│       ├── screens/
│       │   ├── notebook_home_screen.dart # Khung 3 tab, chip nhóm, lọc Yêu thích & nút Dựng thế bi
│       │   └── table_stage_screen.dart   # Màn hình Dựng thế bi dọc/ngang, vẽ đường, lưu/tải
│       └── widgets/
│           └── billiard_table_canvas.dart # CustomPainter bàn TikZ 1:2, kéo bi & vẽ/sửa đường
├── test/
│   ├── widget_test.dart              # Kiểm thử NAV-01 & round-trip model
│   ├── phase1_table_test.dart        # Kiểm thử hình học, kéo thả, bất biến scene & bố cục Phase 1
│   └── phase2_path_storage_test.dart # Kiểm thử vẽ/sửa đường thẳng/gấp khúc, liên kết & lưu/tải Phase 2
├── docs/
│   └── LibreBilliard_DacTa_App_HuongDan_Gemini.md
├── AGENTS.md                         # Quy tắc làm việc cho agent trong dự án này
└── README.md
```

## Kiến trúc & Phương án lưu trữ

- **Quản lý trạng thái:** `ChangeNotifier` gọn nhẹ, tách riêng model thuần Dart, repository, geometry và UI.
- **Lưu trữ dữ liệu (chốt một phương án duy nhất):**
  - *Phase 0–1:* Khung 3 tab và dựng thử bàn + 3 bi trong bộ nhớ.
  - *Phase 2:* Lưu/tải một sơ đồ JSON nguyên tử qua `FileSceneStorage` vào thư mục bền vững của ứng dụng (`getApplicationSupportDirectory()`).
  - *Phase 4+:* Bổ sung **SQLite** cho thư viện bài viết, nhóm chính, thẻ, bộ sưu tập, nhật ký tập luyện và tham chiếu tệp; không duy trì hai kho dữ liệu song song.

## Lệnh phát triển & kiểm tra

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
