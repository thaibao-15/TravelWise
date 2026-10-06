# 🌍 TravelWise

**TravelWise** là ứng dụng hỗ trợ du lịch thông minh tích hợp AI (RAG - Retrieval-Augmented Generation), trợ lý ảo tư vấn địa điểm và lập kế hoạch du lịch.

Dự án được cấu trúc dạng monorepo gồm 3 ứng dụng chính trong thư mục `apps`:
- **API (Backend)**: FastAPI + SQLModel + SQL Server + Chroma Vector DB + Google Gemini.
- **Web**: Next.js (TypeScript, Bun / Node.js).
- **Mobile**: Flutter (Android, iOS, Web).

---

## ⚙️ Yêu cầu hệ thống

| Thành phần | Công nghệ / Phiên bản | Ghi chú |
|---|---|---|
| **Python** | ≥ 3.14 | Dùng cho Backend FastAPI |
| **Package Manager (Python)** | [uv](https://docs.astral.sh/uv/) (Mới nhất) | Quản lý virtualenv & dependencies |
| **Database** | Microsoft SQL Server | Local hoặc Remote |
| **DB Driver** | ODBC Driver 17 for SQL Server | [Tải ODBC Driver 17](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server) |
| **Web Runtime** | [Bun](https://bun.sh/) (hoặc Node.js) | Chạy ứng dụng Next.js |
| **Mobile SDK** | Flutter SDK | Xem yêu cầu chi tiết tại `apps/mobile/pubspec.yaml` |

---

## 📂 Cấu trúc dự án (Monorepo)

```text
TravelWise/
├── apps/
│   ├── api/          # Backend REST API (FastAPI, SQLModel, RAG AI, Alembic)
│   ├── web/          # Web Frontend (Next.js)
│   └── mobile/       # Mobile App (Flutter)
└── README.md
```

---

## 🚀 1. Chạy FastAPI Backend (`apps/api`)

Mở terminal và di chuyển vào thư mục API:

```bash
cd apps/api
```

### Bước 1 — Cài đặt dependencies

```bash
uv sync
```
> `uv` sẽ tự động tạo virtual environment (`.venv`) và cài đặt đầy đủ các thư viện từ `pyproject.toml`.

### Bước 2 — Cấu hình biến môi trường

Sao chép file cấu hình mẫu:

```bash
# Trên Windows PowerShell:
copy .env.example .env

# Trên Linux/macOS/Git Bash:
cp .env.example .env
```

Mở file `.env` và cập nhật thông số kết nối Database, Secret Key & AI Provider:

```env
# SQL Server Database Configuration
SQLSERVER_SERVER=localhost
SQLSERVER_PORT=1433
SQLSERVER_USER=sa
SQLSERVER_PASSWORD=YourPassword
SQLSERVER_DB=TravelWiseDB
SQLSERVER_DRIVER=ODBC Driver 17 for SQL Server
SQLSERVER_TRUST_CERT=yes

# JWT Configuration
JWT_SECRET=your-super-secret-key-change-this-in-production
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# LLM Configuration (Google Gemini)
LLM_PROVIDER=gemini
GEMINI_API_KEY=your-gemini-api-key-here
GEMINI_MODEL=gemini-3.5-flash-lite

# RAG Embedding Configuration (local = miễn phí 100%, không tốn quota)
EMBEDDING_PROVIDER=local
```

> ⚠️ **Lưu ý:** 
> - Lấy `GEMINI_API_KEY` miễn phí tại [Google AI Studio](https://aistudio.google.com/apikey).
> - Đổi `JWT_SECRET` thành chuỗi bí mật an toàn khi đưa lên sản phẩm thật.

### Bước 3 — Tạo Database trên SQL Server

Kết nối vào SQL Server (dùng SSMS, Azure Data Studio hoặc sqlcmd) và chạy câu lệnh tạo database & bảng `users`:

```sql
CREATE DATABASE TravelWiseDB;
GO

USE TravelWiseDB;
GO

CREATE TABLE users (
    id          BIGINT IDENTITY PRIMARY KEY,
    email       NVARCHAR(255) UNIQUE NOT NULL,
    password    NVARCHAR(MAX),
    full_name   NVARCHAR(255),
    avatar_url  NVARCHAR(MAX),
    role        NVARCHAR(20)  DEFAULT 'USER',
    is_active   BIT           DEFAULT 1,
    created_at  DATETIME      DEFAULT GETDATE(),
    updated_at  DATETIME      DEFAULT GETDATE()
);
GO
```

### Bước 4 — Chạy migration database (Alembic)

```bash
uv run alembic upgrade head
```

### Bước 5 — Khởi tạo dữ liệu mẫu (Seeding)

```bash
uv run python seed.py
```

### Bước 6 — Nạp dữ liệu vào Chroma Vector Database (RAG Ingestion)

Chuyển đổi bài viết tri thức từ SQL Server sang vector embeddings và lưu vào Chroma DB:

```bash
uv run python scripts/ingest_rag.py
```

### Bước 7 — Khởi chạy server API

```bash
# Development (Auto-reload)
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

#### 📖 API Documentation & Links

| Service / Doc | URL | Mô tả |
|---|---|---|
| **API Base URL** | `http://localhost:8000` | Giao diện gốc API |
| **Swagger UI** | `http://localhost:8000/docs` | Tài liệu API tương tác |
| **ReDoc** | `http://localhost:8000/redoc` | Tài liệu API chuẩn hóa |

#### 🤖 Các tính năng Backend nổi bật

- **Authentication & Authorization**: Đăng ký, đăng nhập JWT (`/api/v1/auth/register`, `/login`, `/me`).
- **RAG & AI Assistant**:
  - `POST /rag/ask`: Trả lời câu hỏi du lịch thông minh bằng Gemini + Chroma DB context.
  - `POST /rag/search`: Tìm kiếm địa điểm/tri thức theo độ tương đồng ngữ nghĩa (Semantic Search).
  - `POST /rag/test-llm`: Kiểm tra kết nối LLM.

*Xem chi tiết tài liệu backend tại [`apps/api/README.md`](apps/api/README.md).*

---

## 🌐 2. Chạy Next.js Web (`apps/web`)

Mở terminal mới:

```bash
cd apps/web

# Cài đặt dependencies
bun install

# Khởi chạy môi trường development
bun run dev
```

Truy cập giao diện Web tại: `http://localhost:3000`

---

## 📱 3. Chạy Flutter Mobile (`apps/mobile`)

Mở terminal mới:

```bash
cd apps/mobile

# Lấy các package Flutter
flutter pub get

# Khởi chạy ứng dụng
flutter run
```

- Để chọn thiết bị cụ thể: `flutter run -d <device_id>`
- Để chạy trên trình duyệt Web: `flutter run -d chrome`

---

## 🐳 4. Chạy bằng Docker Compose (Backend + Web)

Docker Compose cho phép khởi chạy đồng thời **API Backend** và **Web Frontend** chỉ với một lệnh duy nhất, không cần cài đặt Python, uv hay Bun trên máy host.

### Yêu cầu

| Thành phần | Ghi chú |
|---|---|
| **Docker Desktop** | [Tải Docker Desktop](https://www.docker.com/products/docker-desktop/) |
| **SQL Server** | Đang chạy trên máy host (local) hoặc remote server |
| **File `.env`** | Đã cấu hình đầy đủ tại `apps/api/.env` (xem [Bước 2 ở mục 1](#bước-2--cấu-hình-biến-môi-trường)) |

### Kiến trúc Services

```text
┌─────────────────────────────────────────────────┐
│                Docker Compose                   │
│                                                 │
│  ┌──────────────────┐   ┌────────────────────┐  │
│  │  travelwise-api  │   │  travelwise-web    │  │
│  │  (FastAPI)       │   │  (Next.js)         │  │
│  │  Port: 8000      │◄──│  Port: 3000        │  │
│  └────────┬─────────┘   └────────────────────┘  │
│           │                                     │
└───────────┼─────────────────────────────────────┘
            │ host.docker.internal
            ▼
   ┌─────────────────┐
   │  SQL Server     │
   │  (Máy host)     │
   │  Port: 1433     │
   └─────────────────┘
```

> **Lưu ý:** SQL Server chạy trên máy host, API container kết nối tới SQL Server thông qua `host.docker.internal`.

### Bước 1 — Cấu hình file `.env`

Đảm bảo file `apps/api/.env` đã được cấu hình đúng (xem [hướng dẫn ở mục 1](#bước-2--cấu-hình-biến-môi-trường)). Docker Compose sẽ tự động load file này và ghi đè `SQLSERVER_SERVER=host.docker.internal` để container có thể kết nối tới SQL Server trên máy host.

### Bước 2 — Build và khởi chạy

```bash
# Tại thư mục gốc TravelWise/
docker compose up --build
```

Lần đầu build sẽ mất vài phút để tải image và cài dependencies. Các lần sau sẽ nhanh hơn nhờ Docker cache.

### Bước 3 — Truy cập ứng dụng

| Service | URL | Mô tả |
|---|---|---|
| **Web App** | `http://localhost:3000` | Giao diện người dùng |
| **API** | `http://localhost:8000` | REST API endpoint |
| **Swagger UI** | `http://localhost:8000/docs` | Tài liệu API tương tác |
| **ReDoc** | `http://localhost:8000/redoc` | Tài liệu API chuẩn hóa |

### Các lệnh Docker Compose thường dùng

```bash
docker compose up --build         # Build và chạy (foreground, xem log trực tiếp)
docker compose up --build -d      # Build và chạy (background/detached)
docker compose logs -f            # Xem log realtime của tất cả services
docker compose logs -f api        # Xem log riêng API service
docker compose down               # Dừng và xóa containers
docker compose restart api        # Restart riêng API service
docker compose ps                 # Xem trạng thái các containers
```

> [!TIP]
> Nếu chỉ thay đổi code mà không đổi dependencies, bạn có thể chạy `docker compose up --build` — Docker sẽ sử dụng cache cho các layer không thay đổi nên build rất nhanh.

> [!WARNING]
> **SQL Server trên Windows:** Đảm bảo SQL Server cho phép kết nối TCP/IP và firewall không chặn port `1433`. Kiểm tra trong **SQL Server Configuration Manager** → **SQL Server Network Configuration** → **Protocols** → Enable **TCP/IP**.

---

## 🛠️ Tổng hợp lệnh hữu ích

```bash
# --- Backend (apps/api) ---
uv sync                                      # Cài dependencies
uv run alembic upgrade head                  # Áp dụng migration
uv run python seed.py                        # Seed dữ liệu SQL Server
uv run python scripts/ingest_rag.py          # Ingest RAG sang Chroma DB
uv run python scripts/test_llm.py            # Test kết nối LLM
uv run uvicorn app.main:app --reload         # Chạy Dev API Server

# --- Web (apps/web) ---
bun install                                  # Cài dependencies
bun run dev                                  # Chạy Dev Web Server

# --- Mobile (apps/mobile) ---
flutter pub get                              # Tải dependencies Flutter
flutter run                                  # Chạy Mobile App
```
