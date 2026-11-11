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
│   │   └── table_constants.dart      # Hằng số đơn vị sơ đồ bàn 188x376 (1:2)
│   ├── models/
│   │   ├── enums.dart                # ArticleKind, Difficulty, PracticeStatus, BallColor...
│   │   ├── article.dart              # Model bài viết (Kĩ thuật, Bộ số, Hình bi)
│   │   ├── diagram_scene.dart        # Model scene vector tĩnh (Ball, GuidePath, Annotation)
│   │   ├── library_meta.dart         # EditorialGroup, Tag, Collection, PracticeEntry, AssetRef
│   │   └── models.dart               # Barrel exports
│   ├── repositories/
│   │   └── notebook_repository.dart  # Giao diện kho lưu trữ & InMemoryNotebookRepository (Phase 0)
│   ├── state/
│   │   └── notebook_controller.dart  # Trạng thái điều hướng 3 tab & bộ lọc dùng chung
│   └── ui/
│       └── screens/
│           └── notebook_home_screen.dart # Khung 3 tab, chip nhóm, lọc Yêu thích, menu & trạng thái rỗng
├── test/
│   └── widget_test.dart              # Kiểm thử NAV-01 & round-trip model Phase 0
├── AGENTS.md                         # Quy tắc làm việc cho agent trong dự án này
└── README.md
```

## Kiến trúc & Phương án lưu trữ

- **Quản lý trạng thái:** `ChangeNotifier` gọn nhẹ, tách riêng model thuần Dart, repository, geometry và UI.
- **Lưu trữ dữ liệu (chốt một phương án duy nhất):**
  - *Phase 0:* Dùng `InMemoryNotebookRepository` cho khung dữ liệu và nhóm mặc định.
  - *Phase lưu trữ bền vững (Phase 2–4+):* Sử dụng **SQLite** cho bài viết, nhóm chính, thẻ, bộ sưu tập, nhật ký tập luyện và tham chiếu tệp; **scene vector** được lưu dưới dạng JSON có `version` trong repository; ảnh đính kèm được sao chép vào thư mục dữ liệu bền vững của ứng dụng và lưu đường dẫn tương đối. Không duy trì hai kho dữ liệu song song.

## Lệnh phát triển & kiểm tra

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
