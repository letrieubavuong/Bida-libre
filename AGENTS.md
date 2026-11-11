# Hướng dẫn dành cho Agent trong `libre_billiard_notebook`

Tài liệu này quy định các nguyên tắc bắt buộc khi làm việc trong dự án này, tuân thủ đúng tài liệu đặc tả `docs/LibreBilliard_DacTa_App_HuongDan_Gemini.md`.

## 1. Giới hạn phạm vi (Tuyệt đối tuân thủ)

- **Không xây dựng mô phỏng vật lý**: Ứng dụng là sổ tay tĩnh. Không thêm engine động lực học, solver va chạm, tính xoáy, tốc độ bi hay tự nắn đường bi theo thông số.
- **Không tự ý chuyển phase**: Làm từng phase một, nghiệm thu xong mới chuyển phase. Không làm gộp.
- **Không tự chế nội dung**: Không tự bịa công thức bộ số hay hàng trăm bài giả vào thư viện chính thức.
- **Không thay đổi cấu trúc tổng thể**: Giữ nguyên hệ tọa độ sơ đồ lòng bàn `188 x 376`, tỉ lệ 1:2, gốc dưới-trái, đơn vị sơ đồ.

## 2. Quy chuẩn code & Kiến trúc

- **Flutter / Dart**: Tách bạch rõ:
  - `models/`: Thuần Dart, có serialize/deserialize JSON đầy đủ và round-trip an toàn.
  - `geometry/`: Tính toán tọa độ tĩnh và giới hạn trên bàn.
  - `repositories/`: Giao diện lưu trữ thống nhất (SQLite cho metadata/quan hệ và JSON vector cho scene).
  - `state/`: Quản lý trạng thái gọn gàng, có thể kiểm thử không phụ thuộc UI.
  - `ui/`: Giao diện tiếng Việt chuẩn, hỗ trợ offline.
- **Testing**: Chạy `flutter analyze` và `flutter test` trước khi commit hoặc bàn giao.

