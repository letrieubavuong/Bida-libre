# Hướng dẫn dành cho Agent trong `libre_billiard_notebook`

Tài liệu này quy định các nguyên tắc bắt buộc khi làm việc trong dự án này, tuân thủ đúng tài liệu đặc tả `docs/LibreBilliard_DacTa_App_HuongDan_Gemini.md`.

## 1. Giới hạn phạm vi (Tuyệt đối tuân thủ)

- **Không xây dựng mô phỏng vật lý**: Ứng dụng là sổ tay tĩnh. Không thêm engine động lực học, solver va chạm, tính xoáy, tốc độ bi hay tự nắn đường bi theo thông số.
- **Không tự ý chuyển phase**: Làm từng phase một, nghiệm thu xong mới chuyển phase. Không làm gộp.
- **Không tự chế nội dung**: Không tự bịa công thức bộ số hay hàng trăm bài giả vào thư viện chính thức.
- **Không thay đổi cấu trúc tổng thể**: Giữ nguyên hệ tọa độ sơ đồ lòng bàn `188 x 376`, tỉ lệ 1:2, gốc dưới-trái, đơn vị sơ đồ.
- **Điều chỉnh phạm vi Phase 6 (Theo quyết định chấp thuận Phase 4C)**:
  - App là sổ tay hình bi để tra cứu và tập luyện: Kĩ thuật / Bộ số / Hình bi; đọc bài, xem ảnh và sơ đồ; tạo/sửa bài, đặt bi và vẽ đường hướng dẫn tĩnh; nhóm, thẻ, bộ sưu tập, tìm kiếm và yêu thích.
  - Bỏ toàn bộ Phase 5: Không phát triển tiến độ, trạng thái hoặc nhật ký tập; Không phát triển chia sẻ, xuất PNG, sao lưu/khôi phục; Không mô phỏng vật lý hoặc chạy bi.
  - Không tự xóa trường/database cũ chỉ để dọn mã; giữ nguyên nội dung và dữ liệu người dùng.

## 2. Quy chuẩn code & Kiến trúc

- **Flutter / Dart**: Tách bạch rõ:
  - `models/`: Thuần Dart, có serialize/deserialize JSON đầy đủ và round-trip an toàn.
  - `geometry/`: Tính toán tọa độ tĩnh và giới hạn trên bàn.
  - `repositories/`: Giao diện lưu trữ thống nhất (SQLite cho metadata/quan hệ và JSON vector cho scene).
  - `state/`: Quản lý trạng thái gọn gàng, có thể kiểm thử không phụ thuộc UI.
  - `ui/`: Giao diện tiếng Việt chuẩn, hỗ trợ offline.
- **Testing & Bàn giao**: Chạy `flutter analyze`, `flutter test` và build APK kèm SHA-256 trước khi commit hoặc bàn giao. Không yêu cầu chụp ảnh màn hình hay quay video.

