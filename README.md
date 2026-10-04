# TravelWise

Dự án gồm ba ứng dụng trong thư mục `apps`: **API FastAPI** (backend chính), ứng dụng **Flutter** (mobile) và web **Next.js**. Mở ba terminal riêng để chạy đồng thời.

---

## ⚙️ Yêu cầu

| Thành phần | Phiên bản |
|---|---|
| Python | ≥ 3.14 |
| [uv](https://docs.astral.sh/uv/) (package manager) | Mới nhất |
| Microsoft SQL Server | Local hoặc remote |
| ODBC Driver 17 for SQL Server | [Tải tại đây](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server) |
| Bun | 1.3.13 |
| Flutter SDK | Xem `apps/mobile/pubspec.yaml` |

---

## 🚀 Chạy FastAPI (Backend)

```powershell
cd apps/api
```

### Bước 1 — Cài đặt dependencies

```powershell
uv sync
```

> `uv` tự tạo môi trường ảo `.venv` và cài toàn bộ thư viện từ `pyproject.toml`.

### Bước 2 — Cấu hình biến môi trường

```powershell
copy .env.example .env
```

Mở `.env` và chỉnh sửa ít nhất các biến sau:

```env
SQLSERVER_SERVER=localhost
SQLSERVER_USER=sa
SQLSERVER_PASSWORD=YourPassword
SQLSERVER_DB=TravelWiseDB

JWT_SECRET=your-super-secret-key

# Nếu dùng tính năng RAG / AI
OPENAI_API_KEY=sk-...
```

### Bước 3 — Chạy migration database

```powershell
uv run alembic upgrade head
```

### Bước 4 — Khởi chạy server

```powershell
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

| URL | Mô tả |
|---|---|
| <http://localhost:8000> | API Server |
| <http://localhost:8000/docs> | Swagger UI |
| <http://localhost:8000/redoc> | ReDoc |

---

### Lần chạy lại (đã cài đặt)

```powershell
cd apps/api
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

---

## 🌐 Chạy Next.js (Web)

```powershell
cd apps/web
bun install
bun run dev
```

Mở <http://localhost:3000>.

---

## 📱 Chạy Flutter (Mobile)

```powershell
cd apps/mobile
flutter pub get
flutter run
```

Nếu có nhiều thiết bị: `flutter run -d <device_id>`. Chạy trên Chrome: `flutter run -d chrome`.

