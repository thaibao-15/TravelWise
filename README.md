# AI Travel

Dự án gồm ba ứng dụng trong thư mục `apps`: API FastAPI, ứng dụng Flutter và web Next.js. Hãy mở **ba terminal riêng** để chạy chúng đồng thời.

## Yêu cầu

- Python 3 và `pip`
- Flutter SDK cùng Dart SDK tương thích với yêu cầu trong `apps/mobile/pubspec.yaml`
- Bun 1.3.13 (phiên bản được khai báo trong `apps/web/package.json`)
- Android Emulator hoặc thiết bị thật nếu muốn chạy ứng dụng Flutter trên Android

## Chạy FastAPI

Từ thư mục gốc của repository:

```powershell
cd apps/api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install fastapi "uvicorn[standard]"
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Trên macOS/Linux, sau khi tạo môi trường ảo, kích hoạt bằng `source .venv/bin/activate` rồi chạy các lệnh cài đặt và khởi động như trên.

- API: <http://localhost:8000>
- Swagger UI: <http://localhost:8000/docs>

## Chạy Next.js

Mở terminal khác tại thư mục gốc:

```powershell
cd apps/web
bun install
bun run dev
```

Mở <http://localhost:3000> để xem ứng dụng web.

## Chạy Flutter

Mở terminal khác tại thư mục gốc:

```powershell
cd apps/mobile
flutter pub get
flutter devices
flutter run
```

Nếu có nhiều thiết bị, chọn một thiết bị cụ thể bằng `flutter run -d <device_id>`. Để chạy trên Chrome (khi Flutter Web được bật), dùng `flutter run -d chrome`.

## Chạy lại sau khi cài đặt

- FastAPI: từ `apps/api`, kích hoạt môi trường `.venv` rồi chạy `python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000`.
- Next.js: từ `apps/web`, chạy `bun run dev`.
- Flutter: từ `apps/mobile`, chạy `flutter run`.

Hiện API trả về thông điệp mẫu. Các lệnh trên khởi chạy từng ứng dụng riêng; kết nối API từ web/mobile cần được cấu hình riêng.
