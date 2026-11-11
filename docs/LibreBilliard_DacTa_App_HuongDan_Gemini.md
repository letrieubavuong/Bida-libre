# LIBREBILLIARD — Đặc tả ứng dụng sổ tay kỹ thuật, bộ số và hình bi
## Hướng dẫn triển khai thống nhất dành cho Gemini

**Phiên bản:** 1.1 — 11/11/2026  
**Sản phẩm:** Flutter Android, tiếng Việt, ưu tiên điện thoại và sử dụng offline.  
**Hình thức triển khai:** tạo ứng dụng mới hoàn toàn từ đặc tả này.  
**Trạng thái tài liệu:** Đặc tả để xây dựng; không phải báo cáo chức năng đã hoàn thành.

> Đọc toàn bộ tài liệu trước khi triển khai. Đây là đặc tả độc lập và đầy đủ để tạo ứng dụng từ đầu. Làm từng phase, bàn giao bản chạy được và dừng tại mốc nghiệm thu. Không tự mở rộng sang phase tiếp theo.

## 1. Mục tiêu và giới hạn

Người dùng cần mang một thư viện billiard libre trong điện thoại: đọc kỹ thuật, tra bộ số, xem hàng trăm hình bi gom và tự soạn thêm bài. Người dùng có thể dựng ba bi, vẽ đường đi theo sách, ghi thông số và mở lại khi tập trên bàn thật.

**Ứng dụng là công cụ biên soạn và tra cứu sơ đồ tĩnh. Mô phỏng vật lý không thuộc phạm vi sản phẩm.**

- Không có engine động lực học, solver va chạm, tính xoáy, tính tốc độ bi, dự đoán ghi điểm hoặc gom bi.
- Không có Play/Pause, timeline, hoạt ảnh bi chạy hoặc hoạt ảnh ra cơ.
- Không có nhãn “đã kiểm chứng vật lý”.
- Đường bi là đường hướng dẫn do người soạn đặt và chỉnh; thay thông số cách đánh không tự sửa đường.
- Từ “đường chạy” trong nội dung có nghĩa là hình minh họa tĩnh về đường đi dự kiến.
- Không xây tài khoản, backend, đồng bộ đám mây, AI nhận dạng ảnh hoặc mạng xã hội trong phiên bản này.
- Mọi dữ liệu cốt lõi đọc và sửa được khi không có mạng.

**Thành công của sản phẩm:** người dùng dựng được một bài trong sách, lưu lại, tìm thấy nhanh trên điện thoại và xem rõ khi tập luyện.

## 2. Khởi tạo ứng dụng mới hoàn toàn

1. Tạo một dự án Flutter trống tên libre_billiard_notebook trong thư mục làm việc mới.
2. Xây dựng model, giao diện, lưu trữ, trình vẽ và kiểm thử từ đầu theo tài liệu này.
3. Tài liệu này và các mẫu thiết kế người dùng cung cấp là đầu vào triển khai; không cần khảo sát hoặc so sánh với bất kỳ ứng dụng hay repository nào khác.
4. Không có nhiệm vụ lưu trữ dự án khác, chuyển đổi dữ liệu, nhập model hoặc tái sử dụng mã từ một phiên bản khác.
5. Dữ liệu ban đầu gồm cấu hình và nhóm mặc định, cùng bài mẫu được tạo mới có nhãn rõ ràng. Khi thiếu nguồn chuyên môn, để bài nháp chờ nội dung.
6. Khởi tạo Git riêng trong dự án mới và commit theo từng phase. Không tự tạo repository từ xa hoặc xuất bản nếu chưa có yêu cầu.
7. Báo đường dẫn dự án, cấu trúc thư mục và phiên bản Flutter đang sử dụng.
8. Viết README và AGENTS.md dành riêng cho ứng dụng này.

Tự quyết định các lựa chọn kỹ thuật thông thường trong phạm vi đặc tả. Không thêm công việc khảo sát, đối chiếu hay chuyển đổi hệ thống khác vào các phase.

## 3. Ba phần chính và điều hướng

Thanh điều hướng dưới cùng có đúng ba mục:

| Mục | Vai trò | Nội dung ví dụ |
| --- | --- | --- |
| Kĩ thuật | Giải thích cách thực hiện một kỹ thuật | Trô, kéo, cu-lê, giò gà, đánh chết bi |
| Bộ số | Tập hợp các phương pháp tính và sơ đồ bộ số | Quy ước số, công thức, điều kiện áp dụng, ví dụ |
| Hình bi | Tra cứu các thế bi và cách xử lý | Gom góc, gom dọc băng, thế giữa bàn, thế khứ hồi |

- Mỗi mục có tìm kiếm, bộ lọc và nút “+” tạo bài.
- Yêu thích là bộ lọc dùng chung, không cần tab thứ tư.
- Cài đặt, sao lưu/khôi phục nằm trong menu ứng dụng.
- Tìm kiếm tại tab mặc định tìm trong tab đó; có lựa chọn rõ “Tất cả nội dung”.
- Trên màn hình bài có nút Chỉnh sửa, Nhân bản, Yêu thích và menu thao tác.
- Người dùng được chỉnh mọi bài lưu trong máy, bao gồm bài mẫu.
- Liên kết giữa các mục mở bài tương ứng; thao tác Quay lại trở về danh sách và vị trí cuộn trước đó.

## 4. Tổ chức nội dung từng mục

### 4.1. Kĩ thuật

Phân nhóm ban đầu, cho phép đổi tên/thêm nhóm:

1. Nền tảng và kiểm soát cơ.
2. Trô / kéo.
3. Cu-lê / đẩy tới.
4. Đánh chết bi / amorti.
5. Giò gà và kỹ thuật đặc thù.
6. Kiểm soát bi qua băng.

Các tên trên là nhóm biên tập khởi đầu, không phải tuyên bố các kỹ thuật đồng nghĩa hay phân loại chuyên môn bắt buộc. Giữ “trô”, “kéo”, “giò gà” đúng cách tác giả sử dụng; không tự đổi thuật ngữ.

Mỗi bài tập trung vào một kỹ thuật, có thể liên kết nhiều hình bi minh họa. Một hình bi liên quan đến nhiều kỹ thuật vẫn chỉ có một bản ghi chính.

### 4.2. Bộ số

Phân nhóm theo họ phương pháp do người dùng đặt, kèm thẻ số băng và tình huống áp dụng. Không tự chế công thức bộ số.

Mỗi bài cần:
- Tên bộ số, tác giả/nguồn nếu biết.
- Quy ước số trên từng băng, chiều đọc, vị trí gốc.
- Định nghĩa các đại lượng và công thức.
- Điều kiện áp dụng: cách đánh, lực, ép phê theo tài liệu.
- Ít nhất một sơ đồ khi có dữ liệu nguồn.
- Ví dụ thay số và kết quả do người soạn cung cấp.
- Sai lệch thường gặp và lưu ý của tác giả.
- Liên kết hình bi áp dụng nếu có.

Bản đầu trình bày công thức và ví dụ tĩnh. Chưa làm máy tính bộ số tự động, ngôn ngữ công thức hoặc tự suy diễn kết quả.

**Số diamond hình học và số của bộ số là hai lớp khác nhau:** một vị trí trên băng có thể mang nhãn riêng theo từng bài. Không đổi vị trí nút vật lý chỉ vì đổi nhãn số.

### 4.3. Hình bi — tổ chức cho hàng trăm bài

Dùng **một nhóm chính + nhiều thẻ + bộ sưu tập**, không tạo cây thư mục nhiều tầng.

Nhóm chính gợi ý:

| ID nhóm ổn định | Tên hiển thị | Ý nghĩa biên tập |
| --- | --- | --- |
| corner | Gom góc | Thế gom liên quan khu vực góc |
| long_rail | Gom dọc băng dài | Thế gom triển khai gần băng dài |
| short_rail | Gom gần băng ngắn | Thế gom triển khai gần băng ngắn |
| center | Gom giữa bàn | Thế gom triển khai ở vùng giữa bàn |
| return | Khứ hồi / kéo về | Điểm nổi bật là đưa một bi đi rồi trở về |
| series | Seri / dẫn bi | Thế giữ và nối tiếp chuỗi dẫn bi |
| special | Thế đặc biệt | Các bài cần nhóm riêng |
| unclassified | Chưa phân loại | Nơi tiếp nhận bài mới |

Đây là cách sắp xếp tra cứu, có thể có giao nhau về chuyên môn. Mỗi bài chọn một nhóm chính theo ý đồ tác giả; các đặc điểm khác dùng thẻ.

Thẻ độc lập:
- Kỹ thuật: trô, kéo, cu-lê, giò gà, amorti...
- Đường đi: trực tiếp, một băng, hai băng, ba băng...; chỉ nhập theo bài, không tự tính.
- Độ khó: cơ bản, trung cấp, nâng cao, chưa đánh giá.
- Khoảng cách: gần, trung bình, xa, nếu người soạn muốn dùng.
- Nguồn: tên sách/tác giả.
- Từ khóa tùy chọn: giữ bi, tránh đá, sửa thế...
- Trạng thái tập luyện được quản lý riêng, không biến thành thẻ nội dung.

Bộ sưu tập:
- “Sách A — Chương 2”, “20 thế cơ bản”, “Đang tập tuần này”...
- Một bài thuộc nhiều bộ sưu tập mà không nhân bản.
- Có thứ tự thủ công trong bộ sưu tập.
- Xóa bộ sưu tập không xóa bài bên trong.
- Đổi nhóm/thẻ không đổi ID bài; xóa nhóm đang có bài phải chọn chuyển bài sang nhóm khác hoặc Chưa phân loại.

Màn hình danh sách:
- Đầu trang có ô tìm kiếm, chip nhóm và nút lọc.
- Card có ảnh thu nhỏ sơ đồ, mã bài, tên, độ khó và trạng thái tập.
- Cho chọn lưới hoặc danh sách; không trình bày hàng trăm bài bằng một cột văn bản dài.
- Sắp xếp theo mới sửa, mã, tên hoặc thứ tự bộ sưu tập.
- Nhiều giá trị trong cùng bộ lọc kết hợp OR; giữa các bộ lọc kết hợp AND.
- Tìm có và không dấu: “tro”, “trô”; “cule”, “cu lê”, “cu-lê” qua alias biên tập.
- Thông báo rõ khi không có kết quả, có nút bỏ lọc.
- Giữ bộ lọc và vị trí cuộn khi quay lại.

**Mã bài:** KT-001, BS-001, HB-001... Mã dùng để đọc/tìm; ID nội bộ là UUID ổn định. Không đánh lại mã khi xóa bài hoặc đổi nhóm. Nhân bản tạo ID và mã mới.

Không phải soạn ngay hàng trăm bài. Dùng dữ liệu giả lập có nhãn để kiểm tra khả năng tìm/lọc 500 bài; không đưa nội dung giả vào thư viện chính thức.

## 5. Cấu trúc một bài viết

Dùng một model bài viết chung, thêm trường riêng cho từng loại.

### 5.1. Trường chung

- ID, mã bài, loại bài, tên, mô tả ngắn.
- Nhóm chính, thẻ, độ khó, thời điểm tạo/sửa.
- Mục tiêu và tình huống áp dụng.
- Nội dung giải thích theo các mục.
- Các bước thực hiện.
- Lưu ý, lỗi thường gặp và cách sửa.
- Một hoặc nhiều sơ đồ, có thứ tự và chú thích.
- Ảnh/video nguồn nếu nhập từ tệp; phiên bản đầu ưu tiên ảnh, liên kết video là tùy chọn.
- Tên nguồn, tác giả, trang, URL tùy chọn; cho để trống khi chưa biết.
- Bài liên quan bằng ID.
- Ghi chú cá nhân, yêu thích và trạng thái tập.

Không bắt người dùng điền tất cả trường để lưu nháp.

### 5.2. Thông số cách đánh, hoàn toàn tĩnh

- Bi chủ được chỉ định bằng ID bi, không bắt buộc luôn là bi trắng.
- Độ dày: k/8, 1/3, 2/3 hoặc giá trị chính xác.
- Má trái/phải hoặc tràn mặt; giữ đúng giá trị khi bật/tắt.
- Điểm mũi cơ: tọa độ X/Z trên sơ đồ mặt bi, nhãn bốn mức và ghi chú.
- Đường kính bi tham chiếu 61.5 mm; đầu cơ 11.5, 11.75, 12 mm.
- Quy ước bốn mức là quy ước biên tập: tâm 0; mỗi mức 3.84375 mm, mức 4 là 15.375 mm. Hiện giải thích quy ước, không gọi là chuẩn duy nhất của môn.
- Khi nhập kết hợp ngang/dọc ngoài miền đã chọn, hiển thị giá trị thực và cho người dùng hiểu việc giới hạn.
- Lực: văn bản như “nhẹ”, “mạnh”, “vừa đủ về”; có preset nhưng luôn sửa được.
- Nhịp cơ, độ xuyên cơ, góc nâng cơ: mô tả tùy chọn từ tài liệu.
- Thay thông số chỉ sửa thẻ thông tin; không tự sửa vị trí bi hoặc đường.

Không dùng vận tốc m/s, độ xoáy rad/s hoặc cờ kiểm chứng engine trong model mới.

### 5.3. Biên tập trên điện thoại

- Form chia nhóm: Thông tin / Nội dung / Sơ đồ / Nguồn.
- Nội dung gồm tiêu đề mục, đoạn văn, danh sách, ảnh và sơ đồ.
- Bản đầu dùng các ô soạn văn bản rõ ràng và danh sách thêm/xóa/sắp xếp; không xây trình Word đầy đủ.
- Hỗ trợ công thức bộ số dạng văn bản, ví dụ “Điểm ngắm = Điểm đi − Điểm đến”.
- Cho xem trước bài hoàn chỉnh trước khi lưu.
- Có Lưu nháp và Lưu thay đổi; không có quy trình xuất bản nhiều người.
- Thoát khi có thay đổi chưa lưu: Lưu / Bỏ thay đổi / Ở lại.
- Ghi chú lúc tập và sửa nội dung bài là hai thao tác khác nhau.
- Không ghi đè bài mẫu khi chỉ đổi chế độ xem.
- Ảnh lấy từ máy phải được sao chép vào vùng dữ liệu ứng dụng; không phụ thuộc đường dẫn tạm.

## 6. Bàn vẽ và hệ tọa độ

### 6.1. Thiết kế theo TikZ của người dùng

Mẫu tham chiếu:

~~~latex
\filldraw[fill=gray,rounded corners] (-20,-20) rectangle (208,396);
\filldraw[fill=blue] (-5,-5) rectangle (193,381);
\filldraw[fill=blue!80] (0,0) rectangle (188,376);
~~~

- Lòng bàn: x = 0..188, y = 0..376; tỉ lệ 1:2.
- Gốc tọa độ dưới trái, y tăng lên trên; renderer chuyển sang trục màn hình.
- Đây là **đơn vị sơ đồ**, không tự gọi là cm hoặc mm kích thước bàn thật.
- Nút theo băng ngang ở x = 0, 47, 94, 141, 188; theo băng dọc ở y = 0, 47, ..., 376. Đặt trên phần băng, bố cục góc tránh trùng/đè.
- Hoàn thiện hai băng dài theo cùng quy luật; đoạn TikZ gốc chưa đủ thân vòng lặp.
- Kích thước nút diamond được thiết kế cân đối, không sao chép máy móc circle(36pt).
- Khung xám bo góc; băng xanh; lòng bàn xanh như mẫu. Cho đổi giao diện sau, không cần nhiều theme ở bản đầu.
- Một hệ số scale cho hai trục, luôn giữ bi tròn.
- Lưới, nút diamond, số diamond và nhãn bộ số có công tắc riêng.
- Bản đầu ưu tiên bàn đứng; hỗ trợ màn hình ngang bằng bố trí lại, không kéo méo.
- Phóng to/pan là biến đổi khung nhìn, không làm thay đổi dữ liệu tọa độ.

### 6.2. Bi và giới hạn

- Ba bi trắng, vàng, đỏ; số 1/2/3 tùy chọn.
- ID bi ổn định, màu và vai trò được lưu riêng.
- Bán kính bi lưu theo đơn vị sơ đồ; đề xuất mặc định r = 4, điều chỉnh được trong thiết lập sơ đồ.
- r = 4 là kích thước minh họa, không suy ra từ đường kính 61.5 mm nếu chưa có phép đổi kích thước bàn thật.
- Toàn bộ hình bi phải ở trong lòng bàn:
  x thuộc [r, 188-r], y thuộc [r, 376-r].
- Khoảng cách hai tâm >= tổng bán kính, cho phép chạm nhau, không chồng lấp.
- Khi kéo vượt biên, đưa tới vị trí hợp lệ gần yêu cầu nhất, không nhảy sang phía đối diện.
- Khi không thể tới điểm do bi khác chắn, giữ vị trí hợp lệ cuối cùng; không đẩy các bi khác.
- Có chọn bi, nhập X/Y, khóa vị trí, reset và hoàn tác.
- Vùng nhận ngón tay lớn hơn hình bi; không đổi bán kính hình học để làm dễ chạm.
- Một lần kéo là một bước undo, không tạo hàng trăm bước theo từng frame.
- Đổi bán kính phải kiểm tra lại bố trí; nếu không hợp lệ, báo và cho hủy, không tự di chuyển âm thầm.

## 7. Trình vẽ đường hướng dẫn

### 7.1. Công cụ và thao tác cơ bản

Thanh công cụ gọn:
- Chọn / Di chuyển bi.
- Đường thẳng / Gấp khúc.
- Đường cong.
- Chú thích.
- Undo / Redo.
- Hoàn tất.

Chọn một bi sở hữu đường; màu đường phù hợp nhưng đủ tương phản với mặt bàn. Một bi có nhiều đường được, ví dụ phương án A/B.

Vẽ gấp khúc:
1. Chọn bi và công cụ.
2. Chạm điểm đầu, các điểm tiếp theo.
3. Có nét xem trước đoạn đang dựng.
4. Nhấn Hoàn tất; không phụ thuộc double tap khó thao tác.
5. Có Hủy đường đang vẽ, không mất các đối tượng đã lưu.

Chọn đường để hiện điểm điều khiển; kéo điểm, thêm/chèn điểm, xóa điểm, đảo chiều hoặc xóa đường. Kéo thân đường để di chuyển toàn đường nếu không có liên kết cố định; báo rõ cách xử lý đường đang liên kết.

### 7.2. Kiểu nét và đường cong

- Độ dày, nét liền/nét đứt, mũi tên cuối hoặc mũi tên dọc đường.
- Đường theo màu bi, cho chọn màu khác.
- Đường cong Bézier có điểm đầu/cuối và tay nắm.
- Một đường có thể ghép nhiều đoạn thẳng/cong.
- Không tự bo góc hoặc làm mượt một đoạn được chọn là thẳng.
- Mũi tên theo tiếp tuyến của đoạn cuối.
- Điểm điều khiển chỉ hiện khi biên tập; không xuất vào hình.
- Cả đường không vượt lòng bàn; kiểm tra thân đường cong, không chỉ hai đầu.
- Cho tay nắm ra ngoài vùng bàn nếu cần chỉnh, nhưng đường kết quả phải hợp lệ; không cắt bằng clip để che dữ liệu sai.
- Hình học chỉ phục vụ dựng/chọn/giới hạn đường, không tính cơ học.

### 7.3. Ý nghĩa đường và bắt dính

Đường biểu diễn quỹ đạo **tâm bi**:
- Với bi có bán kính r, đường chính nằm trong [r, W-r] × [r, H-r].
- Điểm “sát băng” của tâm bi cách mép lòng bàn r.
- Muốn đánh dấu điểm tiếp xúc trên mép băng, dùng ký hiệu/chú thích riêng.
- Một đường nối tới bi đích có thể kết thúc tại vị trí tâm bi ảo do người soạn đặt; không bắt buộc đi vào tâm bi đích.
- Có thể minh họa ý đồ khác bằng đường phụ; đường phụ phải có loại rõ, không bị nhầm là quỹ đạo tâm.

Bắt dính có công tắc:
- Lưới.
- Tâm bi hoặc điểm điều khiển.
- Đường giới hạn tâm sát băng.
- Vị trí theo diamond; không nhầm tâm bi trên mép với điểm tiếp xúc băng.

Không tự phản xạ, tự xác định độ dày hoặc tự tìm đường tới bi đích.

Liên kết điểm:
- Có thể gắn điểm đầu đường vào tâm bi sở hữu.
- Kéo bi chỉ cập nhật điểm đầu đã liên kết; không làm toàn bộ đường đổi hình âm thầm.
- Cho gỡ liên kết.
- Nếu chỉnh bi làm một đường không hợp lệ, đánh dấu và yêu cầu chỉnh; không âm thầm sửa đường.
- Quy tắc liên kết phải nhất quán khi undo/redo và sau lưu/tải.

### 7.4. Chú thích và ảnh nguồn

- Nhãn chữ, số thứ tự, chấm đánh dấu, vùng tròn/chữ nhật.
- Di chuyển, khóa, đổi màu, xóa.
- Có thể xem ảnh sách cạnh bàn hoặc mở sheet tham chiếu trên điện thoại.
- Sau khi core ổn định mới thêm lớp ảnh mờ để đồ lại: di chuyển, scale đồng đều, chỉnh opacity, khóa ảnh. Không cần nhận dạng tự động.
- Ảnh nguồn không được tự xuất cùng sơ đồ nếu người dùng chưa chọn.

## 8. Chế độ xem và luyện tập

- “Xem bài” là chế độ mặc định khi mở bài.
- Bàn và đường hướng dẫn rõ, ẩn tay nắm và toolbar biên tập.
- Có xem toàn màn hình, zoom và bật/tắt đường của từng bi.
- Không cho vô tình kéo bi khi đang xem.
- “Chỉnh sửa sơ đồ” mở bản nháp; Hủy phải trở lại bản đã lưu.
- Trạng thái tập: Chưa tập / Đang tập / Đã tập.
- Ghi chú: ngày tập, số lần thử, số lần đạt (tùy chọn), nhận xét.
- Nếu nhập số lần: số đạt không âm và không lớn hơn số thử.
- Không tự kết luận người dùng đã thành thạo từ một lần tập.
- Bộ sưu tập đang tập và bộ lọc yêu thích giúp truy cập nhanh.

## 9. Dữ liệu, lưu trữ và kiến trúc

### 9.1. Kiến trúc tối giản

Flutter với một cách quản lý state nhất quán. Tách:
- Model thuần Dart và serialization.
- Repository lưu/đọc.
- Editor state và lệnh undo/redo.
- Geometry và renderer.
- Màn hình danh sách, xem bài, soạn bài, dựng hình.

Đề xuất dùng SQLite cho bài, nhóm, thẻ, bộ sưu tập và nhật ký; scene vector là JSON có phiên bản trong một trường hoặc tệp được repository quản lý. Ảnh nằm trong thư mục dữ liệu ứng dụng, DB lưu đường dẫn tương đối. Chọn một phương án và ghi vào README; không duy trì hai kho dữ liệu song song.

Không tạo kiến trúc plugin tổng quát, microservice hoặc framework canvas khổng lồ.

### 9.2. Các thực thể tối thiểu

| Thực thể | Trường cốt lõi |
| --- | --- |
| Article | id, code, kind, title, summary, primaryGroupId, difficulty, content, source, timestamps |
| Scene | id, version, width, height, balls, paths, annotations, viewSettings |
| Ball | id, color, label, center, radius, locked |
| GuidePath | id, ownerBallId, segments, style, optional startAnchor |
| Segment | type line/cubic, start, end, control points nếu cubic |
| Annotation | id, type, position, text/shape, style, locked |
| Collection | id, name, ordered article references |
| Tag | id, name, aliases |
| PracticeEntry | id, articleId, date, optional attempts/successes, note |
| Asset | id, relativePath, mimeType, attachment references |

- Tọa độ, tay nắm và ID phải round-trip không mất dữ liệu.
- kind thuộc technique / system / position.
- Source và thông số đánh là dữ liệu có cấu trúc, không nhét tất cả vào tiêu đề.
- Yêu thích/trạng thái tập tách khỏi nội dung chuyên môn.
- Không lưu pixel hoặc kết quả render làm nguồn chính của sơ đồ.
- Thumbnail chỉ là cache; mất cache vẫn dựng lại được từ scene.
- Kiểm tra dữ liệu số hữu hạn, ID tham chiếu tồn tại và kiểu segment hợp lệ.

### 9.3. Lưu an toàn

- Dữ liệu chính ở thư mục ứng dụng bền vững, không dùng thư mục tạm.
- Lưu bài và tham chiếu ảnh phải có cơ chế tránh trạng thái dang dở.
- Chỉ báo “Đã lưu” sau khi thao tác thực sự thành công.
- Lỗi lưu phải báo và giữ bản nháp để thử lại.
- Không xóa ảnh còn được bài khác dùng.
- Xóa bài có xác nhận hoặc thùng rác; không xóa dây chuyền bài liên quan.
- Schema mới hơn app hiện tại: từ chối ghi đè, thông báo cần bản app phù hợp.
- Không tải seed lại làm ghi đè bài người dùng đã sửa.
- Có thể khôi phục bài mẫu bằng hành động rõ ràng, không tự động.

## 10. Nhập/xuất và sao lưu của ứng dụng

### 10.1. Sao lưu

Gói ZIP gồm:
- manifest: schema version, app version, thời điểm.
- Dữ liệu bài, nhóm, thẻ, bộ sưu tập, nhật ký.
- Scene vector.
- Ảnh đính kèm.

Khôi phục phải:
- Kiểm tra schema, tệp thiếu, dữ liệu lỗi trước khi thay đổi kho chính.
- Chặn đường dẫn ZIP thoát thư mục và giới hạn kích thước nhập hợp lý.
- Sao lưu kho hiện tại trước khi thay thế.
- Cho chọn “Gộp” hoặc “Thay thế”, hiển thị số bài.
- Gộp không nhân đôi cùng ID âm thầm; xung đột phải có lựa chọn rõ: giữ bản hiện có hoặc nhập thành bản sao.
- Không coi trùng mã bài là trùng ID; cấp mã mới cho bản sao nếu cần.
- Bảo đảm không mất ảnh khi chuyển sang máy khác.

### 10.2. Xuất hình

- Xuất PNG theo scene vector, có chọn độ phân giải.
- Không có toolbar, điểm chọn, tay nắm hoặc thông báo debug.
- Tùy chọn hiện mã/tên bài và chú thích.
- Bản đầu không cần PDF hoặc xuất LaTeX.

## 11. Thiết kế trải nghiệm

- Nội dung và hình bi là trung tâm; không hiển thị thuật ngữ kỹ thuật lập trình.
- Giao diện tiếng Việt thống nhất, chữ dễ đọc khi đứng cạnh bàn.
- Vùng chạm nút khoảng 48 logical pixels; tay nắm đủ dễ kéo.
- Không nhồi form, bảng lực và canvas nhỏ vào cùng một màn hình.
- Danh sách dùng thumbnail; xem bài dùng sơ đồ lớn; biên tập có canvas riêng.
- Thanh công cụ ở vị trí không che phần bi đang sửa; có thể cuộn ngang nếu cần.
- Có “Hoàn tất” và “Hủy” rõ ràng.
- Trong editor, ưu tiên thao tác chọn/kéo một ngón; pan hai ngón khi zoom để tránh xung đột.
- Có trạng thái rỗng hướng dẫn tạo bài đầu tiên.
- Hiển thị tiến trình khi nhập/xuất; không để thao tác nặng khóa màn hình.
- Cuộn danh sách phải dựng item theo nhu cầu; không tải ảnh gốc của 500 bài cùng lúc.

## 12. Các phase triển khai và cổng nghiệm thu

**Mỗi phase:** báo phần đã làm, kiểm tra đã chạy (`flutter analyze`, `flutter test`), giới hạn còn lại, commit, APK tải được và SHA-256. Không yêu cầu chụp ảnh màn hình hay quay video. Dừng chờ nghiệm thu trước phase sau. Không báo hoàn thành chỉ bằng mô tả hoặc mã nguồn chưa chạy.

| Phase | Phạm vi | Điều kiện nghiệm thu |
| --- | --- | --- |
| 0 | Khởi tạo bản mới và phạm vi | App chạy Android, ba tab đúng tên, repo/path rõ, không engine vật lý |
| 1 | Bàn và đặt bi | Bàn đúng tỉ lệ; kéo/nhập vị trí ba bi; không ra băng/chồng lấp; reset/undo |
| 2 | Đường thẳng và gấp khúc | Vẽ, sửa điểm, mũi tên, màu/nét; liên kết điểm đầu; lưu/tải một scene |
| 3 | Đường cong và chú thích | Sửa Bézier, trộn đoạn, giới hạn đường, undo/redo đầy đủ; xem bài sạch |
| 4 | Bài viết và ba thư viện | CRUD bài, nhiều sơ đồ, thông số tĩnh, nguồn/ảnh, nhóm/thẻ/bộ sưu tập, tìm/lọc |
| 5 | Dùng lúc tập và trao đổi dữ liệu | Yêu thích, trạng thái/ghi chú tập, xuất PNG, sao lưu/khôi phục |
| 6 | Hoàn thiện và nghiệm thu | Kiểm tra 500 bài, lỗi lưu, sao lưu/khôi phục, tính toàn vẹn dữ liệu và APK nghiệm thu cuối |

### Phase 0

Chỉ tạo khung và chuẩn hóa tên. Không thêm seed hàng loạt, thuật toán hoặc editor phức tạp.

### Phase 1

Bàn và ba bi là sản phẩm chính. Chưa vẽ đường, chưa form bài dài. Nếu lưu scene chưa triển khai thì nói rõ trạng thái, không tự hứa đã lưu.

### Phase 2–3

Dùng chính hình bài trô người dùng đã cung cấp làm mẫu vẽ tĩnh. Nếu tệp nguồn không có trong phiên làm việc, yêu cầu đính kèm lại; không đoán tọa độ rồi tuyên bố đúng sách.

Phải dựng được: ba bi, đường tới bi mục tiêu, đường kéo về bi thứ ba, đường bi mục tiêu đi lên băng và quay về. Không cần giải thích cơ học để editor chấp nhận sơ đồ.

### Phase 4

Tạo các ví dụ:
- Một bài Kĩ thuật.
- Một bài Bộ số nếu có nguồn công thức; thiếu nguồn thì dùng nháp có nhãn chờ nội dung.
- Một bài Hình bi từ ảnh đã cung cấp.
Không tự chế thêm hàng trăm bài hoặc công thức để lấp danh sách.

### Phase 5–6

Mô tả cách người dùng cài APK, tạo một bài, sao lưu, gỡ/cài lại trên thiết bị thử nghiệm và khôi phục. Không thử gỡ app chứa dữ liệu thật của người dùng.

## 13. Ma trận nghiệm thu bắt buộc

| Mã | Phép thử | Kết quả cần đạt |
| --- | --- | --- |
| NAV-01 | Mở ứng dụng | Có ba mục Kĩ thuật, Bộ số, Hình bi; không Play/mô phỏng |
| GEO-01 | Bốn góc và bốn cạnh | Toàn bộ bi trong lòng bàn; không chồng lấp |
| GEO-02 | Kéo qua băng rồi thả | Bi giữ vị trí hợp lệ; không mất bi |
| GEO-03 | Đổi kích thước màn hình/zoom | Không đổi tọa độ dữ liệu; bi luôn tròn |
| EDT-01 | Kéo bi, vẽ, sửa, xóa rồi undo/redo | Phục hồi đúng từng thao tác |
| EDT-02 | Vẽ nhiều đoạn thẳng | Không tự biến thành đường cong |
| EDT-03 | Kéo tay nắm Bézier | Toàn đường tuân thủ giới hạn, không chỉ đầu mút |
| EDT-04 | Đổi thông số đánh | Scene không tự đổi |
| EDT-05 | Chạm 2/3 → tràn mặt → trở lại | Giữ đúng 2/3 và má trước đó |
| DAT-01 | Lưu bài nhiều scene, đóng/mở app | Không mất đường, nhãn, ảnh hoặc thứ tự |
| DAT-02 | Hủy chỉnh sửa | Bản đã lưu không bị sửa |
| DAT-03 | Giả lập lỗi ghi | Không báo lưu thành công; giữ nháp |
| CAT-01 | Một bài trong ba bộ sưu tập | Chỉ một bản nội dung, sửa phản ánh ở mọi nơi |
| CAT-02 | Đổi/xóa nhóm | Bài được giữ và có nhóm hợp lệ |
| SEA-01 | Tìm “tro”, lọc nhóm và độ khó | Đúng alias và quy tắc OR/AND |
| SEA-02 | Quay lại từ bài | Giữ lọc và vị trí cuộn |
| IO-01 | Sao lưu rồi nhập vào kho thử trống | Đủ bài, ảnh và scene |
| IO-02 | Nhập ZIP lỗi hoặc schema mới | Không phá kho hiện tại |
| IO-03 | Xuất PNG | Đúng sơ đồ, không có tay nắm/toolbar |
| PERF-01 | 500 bài giả lập | Cuộn/tìm/lọc dùng được, ảnh tải theo nhu cầu |
| OFF-01 | Bật chế độ máy bay | Đọc, sửa, lưu và tìm bài vẫn hoạt động |

Kiểm tra bằng unit/widget test ở các quy tắc dữ liệu và hình học quan trọng; thao tác canvas và bố cục cần chạy trên thiết bị/emulator thật. Flutter analyze và các test liên quan phải đạt trước bàn giao. Không đặt ngưỡng tốc độ thiếu thiết bị đo; ghi model máy, phiên bản Android và kết quả quan sát.

## 14. Những việc Gemini không được tự làm

- Quay lại xây mô phỏng vì tên sản phẩm có billiard.
- Tự tính hoặc tự sửa đường bi dựa trên độ dày/ép phê.
- Tự chế bài sách, tên tác giả, số trang hoặc công thức.
- Thao tác với các dự án không thuộc ứng dụng đang xây dựng.
- Thay cấu trúc tổng thể giữa chừng mà không ghi lý do và ảnh hưởng.
- Dùng ảnh raster của bàn thay cho scene vector có thể chỉnh.
- Nối dữ liệu bằng index danh sách thay cho ID ổn định.
- Gộp yêu thích với bản sao bài viết.
- Triển khai đồng thời mọi phase rồi chỉ gửi một APK cuối cùng.
- Báo đã nghiệm thu thay người dùng.

## 15. Báo cáo bàn giao mỗi phase

~~~text
Phase:
Branch / commit:
Đường dẫn dự án:
Chức năng đã hoàn thành:
Kiểm tra đã chạy và kết quả:
APK và SHA-256:
Các bước nghiệm thu trên điện thoại:
Lỗi/giới hạn còn lại:
Cấu trúc dữ liệu và lưu ý lưu/khôi phục:
Phase kế tiếp dự kiến (chưa triển khai):
~~~

## 16. Lệnh bắt đầu dành cho Gemini

~~~text
Hãy coi file này là đặc tả thống nhất của ứng dụng mới.

Đọc toàn bộ, tóm tắt ngắn:
1. Mục tiêu sản phẩm.
2. Những gì đã loại khỏi phạm vi.
3. Cấu trúc ba mục và nguyên tắc nhóm/thẻ/bộ sưu tập.
4. Phase sẽ làm trong lượt này.

Sau đó thực hiện PHASE 0:
- Tạo dự án Flutter trống từ đầu.
- Khởi tạo Git và cấu trúc dữ liệu mới.
- Dựng ba tab và cấu trúc tối giản.
- Chạy, kiểm tra và build APK.
- Báo cáo đúng mẫu ở mục 15.

Dừng tại mốc nghiệm thu Phase 0.
Không tự chuyển sang phase khác hoặc triển khai mô phỏng.
~~~

