# 🌍 TravelWise

**TravelWise** là nền tảng hỗ trợ du lịch thông minh toàn trình tích hợp AI (RAG - Retrieval-Augmented Generation), trợ lý đàm thoại giọng nói hai chiều thời gian thực (LiveKit WebRTC Voice Agent) và lập kế hoạch hành trình du lịch tự động.

Dự án được cấu trúc dạng monorepo gồm 4 ứng dụng trong thư mục `apps`:
- **API (Backend)**: FastAPI + SQLModel + SQL Server + Chroma Vector DB + Google Gemini + LiveKit Token Generator.
- **Web (Frontend)**: Next.js 16 (React 19, TypeScript, Tailwind CSS, Living Voice Orb, Trip Canvas).
- **Voice Agent**: LiveKit Voice Agent Worker độc lập (WebRTC song công, Blaze AI STT/TTS tiếng Việt, Gemini RAG, ngắt lời VAD).
- **Mobile**: Flutter (Android, iOS, Web).

---

## ⚙️ Yêu cầu hệ thống

| Thành phần | Công nghệ / Phiên bản | Ghi chú |
|---|---|---|
| **Python** | ≥ 3.11 (Khuyên dùng 3.12 - 3.14) | Dùng cho Backend FastAPI & Voice Agent |
| **Package Manager (Python)** | [uv](https://docs.astral.sh/uv/) (Mới nhất) | Quản lý virtualenv & dependencies siêu tốc |
| **Database** | Microsoft SQL Server | Local hoặc Remote |
| **DB Driver** | ODBC Driver 17 hoặc 18 for SQL Server | [Tải ODBC Driver](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server) |
| **Web Runtime** | [Bun](https://bun.sh/) (hoặc Node.js ≥ 20) | Chạy ứng dụng Next.js |
| **Voice Platform** | [LiveKit Cloud](https://cloud.livekit.io/) | Dự án WebRTC Realtime (gói miễn phí) |
| **Voice AI (STT/TTS)** | [Blaze AI](https://blaze.vn/) (hoặc OpenAI/Deepgram) | Nhận diện & tổng hợp tiếng Việt độ trễ siêu thấp |
| **Mobile SDK** | Flutter SDK | Xem chi tiết tại `apps/mobile/pubspec.yaml` |

---

## 📂 Cấu trúc dự án (Monorepo)

```text
TravelWise/
├── apps/
│   ├── api/          # Backend REST API (FastAPI, SQLModel, RAG AI, LiveKit Token)
│   ├── web/          # Web Frontend (Next.js, LiveKit Voice, Chat Box, Canvas)
│   ├── voice-agent/  # Realtime Voice Agent Worker (LiveKit WebRTC, Blaze AI, RAG)
│   └── mobile/       # Mobile App (Flutter)
├── docker-compose.yml# Cấu hình khởi chạy đồng bộ các service
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

Mở file `.env` và cập nhật thông số kết nối Database, Secret Key, AI Provider & LiveKit:

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

# LiveKit WebRTC Configuration (để cấp Token phòng thoại)
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your-livekit-api-key
LIVEKIT_API_SECRET=your-livekit-api-secret
LIVEKIT_AGENT_NAME=travelwise-voice-assistant
```

> ⚠️ **Lưu ý:** 
> - Lấy `GEMINI_API_KEY` miễn phí tại [Google AI Studio](https://aistudio.google.com/apikey).
> - Lấy `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` miễn phí tại [LiveKit Cloud](https://cloud.livekit.io/).

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

---

## 🎙️ 2. Chạy Realtime Voice Agent (`apps/voice-agent`)

Voice Agent chạy như một Worker độc lập, kết nối tới LiveKit Cloud qua WebRTC để tiếp nhận giọng nói người dùng và đàm thoại hai chiều.

Mở terminal mới:

```bash
cd apps/voice-agent
```

### Bước 1 — Cài đặt dependencies

```bash
uv sync
```

### Bước 2 — Cấu hình biến môi trường

Sao chép file cấu hình mẫu:

```bash
copy .env.example .env
```

Cập nhật thông tin LiveKit Cloud và Blaze AI trong `apps/voice-agent/.env`:

```env
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your-livekit-api-key
LIVEKIT_API_SECRET=your-livekit-api-secret
LIVEKIT_AGENT_NAME=travelwise-voice-assistant

BLAZE_API_KEY=your-blaze-api-key
BACKEND_API_URL=http://127.0.0.1:8000
JWT_SECRET=your-super-secret-key-change-this-in-production
```

### Bước 3 — Khởi chạy Agent Worker

```bash
# Môi trường phát triển (Development / Auto-reload):
uv run python main.py dev

# Môi trường sản xuất (Production Worker Daemon):
uv run python main.py start
```

*Xem chi tiết kiến trúc và benchmark âm thanh tại [`apps/voice-agent/README.md`](apps/voice-agent/README.md).*

---

## 🌐 3. Chạy Next.js Web (`apps/web`)

Mở terminal mới:

```bash
cd apps/web

# Cài đặt dependencies
bun install

# Khởi chạy môi trường development
bun run dev
```

Truy cập giao diện Web tại: `http://localhost:3000`
- **Trò chuyện giọng nói LiveKit**: `http://localhost:3000/voice-guide`
- **Trang kiểm tra WebRTC độc lập**: `http://localhost:3000/livekit-test`
- **Chat văn bản thông minh & Lịch trình**: `http://localhost:3000/chat`

---

## 📱 4. Chạy Flutter Mobile (`apps/mobile`)

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

## 🐳 5. Chạy bằng Docker Compose (API + Web + Voice Agent)

Docker Compose cho phép khởi chạy đồng thời **API Backend**, **Web Frontend** và **LiveKit Voice Agent Worker** chỉ với một lệnh duy nhất.

### Kiến trúc Services

```text
┌──────────────────────────────────────────────────────────────┐
│                       Docker Compose                         │
│                                                              │
│  ┌──────────────────┐   ┌─────────────────────────────────┐  │
│  │  travelwise-api  │   │  travelwise-voice-agent         │  │
│  │  (FastAPI)       │   │  (LiveKit Worker)               │  │
│  │  Port: 8000      │   │  Outbound WebSocket             │  │
│  └────────┬─────────┘   └────────────────┬────────────────┘  │
│           │                              │                   │
│           │        ┌─────────────────────┼────────────────┐  │
│           │        │  travelwise-web     │                │  │
│           │        │  (Next.js)          ▼                │  │
│           │        │  Port: 3000    LiveKit Cloud         │  │
│           │        └──────────────── (wss://...)          │  │
└───────────┼──────────────────────────────────────────────────┘
            │ host.docker.internal
            ▼
   ┌─────────────────┐
   │  SQL Server     │
   │  (Máy host)     │
   │  Port: 1433     │
   └─────────────────┘
```

### Bước 1 — Cấu hình file `.env`

Đảm bảo đã cấu hình file `.env` tại cả 2 thư mục:
- `apps/api/.env`
- `apps/voice-agent/.env`

### Bước 2 — Build và khởi chạy

```bash
# Tại thư mục gốc TravelWise/
docker compose up --build
```

Để chạy ngầm trong nền (detached mode):
```bash
docker compose up --build -d
```

### Bước 3 — Các lệnh Docker Compose thường dùng

```bash
docker compose logs -f voice-agent  # Xem log riêng của LiveKit Voice Agent
docker compose logs -f api          # Xem log riêng API Backend
docker compose logs -f web          # Xem log riêng Web Frontend
docker compose restart voice-agent  # Khởi động lại riêng Voice Agent
docker compose down                 # Dừng và xóa containers
docker compose ps                   # Xem trạng thái các containers
```

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

# --- Voice Agent (apps/voice-agent) ---
uv sync                                      # Cài dependencies
uv run python main.py dev                    # Chạy Dev Voice Agent
uv run python main.py start                  # Chạy Production Voice Agent Worker
uv run python -m unittest discover tests     # Chạy bộ Unit Tests kiểm thử

# --- Web (apps/web) ---
bun install                                  # Cài dependencies
bun run dev                                  # Chạy Dev Web Server
bun run build                                # Kiểm tra typecheck và build production

# --- Mobile (apps/mobile) ---
flutter pub get                              # Tải dependencies Flutter
flutter run                                  # Chạy Mobile App
```
