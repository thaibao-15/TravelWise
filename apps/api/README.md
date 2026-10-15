# 🚀 TravelWise API — Backend Service

Backend REST API & AI Engine cho nền tảng du lịch **TravelWise**, được xây dựng với **FastAPI**, **SQLModel**, **Microsoft SQL Server**, **Chroma Vector DB**, **Google Gemini LLM** và **Blaze AI Realtime Voice**.

---

## 🛠️ Công nghệ Sử dụng (Tech Stack)

| Thành phần | Công nghệ | Mô tả |
|---|---|---|
| **Web Framework** | [FastAPI](https://fastapi.tiangolo.com/) (Async) | High-performance, Swagger UI tự động, Non-blocking I/O |
| **ORM & Database** | [SQLModel](https://sqlmodel.tiangolo.com/) + SQLAlchemy | Type-safe ORM kết nối Microsoft SQL Server qua `pyodbc` |
| **Database Migrations** | [Alembic](https://alembic.sqlalchemy.org/) | Quản lý lịch sử và phiên bản cấu trúc database |
| **RAG & Vector DB** | [ChromaDB](https://www.trychroma.com/) + LangChain | Lưu trữ vector embeddings, Semantic Search tri thức du lịch |
| **LLM Engine** | [Google Gemini](https://ai.google.dev/) (`gemini-3.5-flash-lite`) | Hỏi đáp RAG thông minh, lập kế hoạch lịch trình tự động |
| **Realtime TTS** | [Blaze AI](https://blaze.vn/) (WebSocket + Streaming HTTP) | Chuyển văn bản thành giọng nói tiếng Việt với độ trễ < 1s |
| **Authentication** | PyJWT + pwdlib (BCrypt) | Bảo mật JWT token, phân quyền người dùng |
| **Runtime & Package** | Python ≥ 3.14 + [uv](https://docs.astral.sh/uv/) | Quản lý virtual environment và dependencies siêu tốc |

---

## ⚙️ Yêu cầu Hệ thống

- **Python** ≥ 3.14
- **uv** — Trình quản lý gói và môi trường ([Hướng dẫn cài đặt uv](https://docs.astral.sh/uv/getting-started/installation/))
- **Microsoft SQL Server** (Bản Local, Docker hoặc Remote Cloud)
- **ODBC Driver 17 for SQL Server** — [Tải ODBC Driver 17](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server)

---

## 🚀 Hướng dẫn Cài đặt & Khởi chạy

### 1. Di chuyển vào thư mục API

```bash
cd TravelWise/apps/api
```

### 2. Cài đặt Dependencies với `uv`

```bash
uv sync
```
> `uv` sẽ tự động tạo virtual environment (`.venv`) và đồng bộ toàn bộ dependencies từ file `pyproject.toml`.

### 3. Cấu hình Biến môi trường

Sao chép file cấu hình mẫu:

```bash
# Trên Windows PowerShell:
copy .env.example .env

# Trên Linux / macOS:
cp .env.example .env
```

Mở file `.env` và điền các thông số:

```env
# 1. SQL Server Database
SQLSERVER_SERVER=localhost
SQLSERVER_PORT=1433
SQLSERVER_USER=sa
SQLSERVER_PASSWORD=YourPassword123!
SQLSERVER_DB=TravelWiseDB
SQLSERVER_DRIVER=ODBC Driver 17 for SQL Server
SQLSERVER_TRUST_CERT=yes

# 2. JWT Security
JWT_SECRET=your-super-secret-key-change-this-in-production
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# 3. LLM Configuration (Google Gemini)
LLM_PROVIDER=gemini
GEMINI_API_KEY=your-gemini-api-key-here
GEMINI_MODEL=gemini-3.5-flash-lite

# 4. Blaze AI Realtime TTS (Voice Companion)
BLAZE_API_KEY=your-blaze-api-key-here
BLAZE_TTS_WS_URL=wss://api.blaze.vn/v1/tts/realtime
BLAZE_TTS_SPEAKER_ID=DaNang-Nu-1-BL
BLAZE_TTS_MODEL=2.0-realtime
BLAZE_TTS_AUDIO_FORMAT=mp3

# 5. Chroma Vector DB
CHROMA_PERSIST_DIRECTORY=data/chroma
CHROMA_COLLECTION_NAME=travelwise_knowledge
EMBEDDING_PROVIDER=auto
```

> 💡 **Lấy API Key:**
> - `GEMINI_API_KEY`: Miễn phí tại [Google AI Studio](https://aistudio.google.com/apikey).
> - `BLAZE_API_KEY`: Đăng ký tài khoản tại [Blaze AI](https://blaze.vn/).

### 4. Khởi tạo Database & Chạy Migrations

Kết nối vào SQL Server và tạo cơ sở dữ liệu:
```sql
CREATE DATABASE TravelWiseDB;
GO
```

Áp dụng các migration của Alembic:
```bash
uv run alembic upgrade head
```

### 5. Nạp dữ liệu mẫu (Seeding) & Tri thức RAG

Nạp dữ liệu ban đầu về danh mục, địa điểm và bài viết:
```bash
uv run python seed.py
```

Nạp dữ liệu từ SQL Server vào Chroma Vector DB:
```bash
uv run python scripts/ingest_rag.py
```

*(Tùy chọn)* Nạp thêm dữ liệu cào du lịch Đà Nẵng:
```bash
uv run python scripts/ingest_crawled_knowledge.py
```

### 6. Khởi chạy Server Development

```bash
uv run uvicorn app.main:app --reload
```

Server sẽ lắng nghe tại: **`http://localhost:8000`**

---

## 📂 Cấu trúc Thư mục (Directory Structure)

```text
apps/api/
├── alembic/                      # Quản lý migration cơ sở dữ liệu
│   ├── versions/                 # Các file migration tự động
│   └── env.py                    # Cấu hình kết nối Alembic
│
├── app/
│   ├── api/                      # Tầng Presentation / HTTP Routes
│   │   ├── deps.py               # Dependency Injection (Auth, Session, Permissions)
│   │   └── routes/               # API Endpoints
│   │       ├── auth.py           # Đăng ký, Đăng nhập, /me
│   │       ├── users.py          # Quản lý tài khoản người dùng
│   │       ├── places.py         # Tìm kiếm, lọc và xem chi tiết địa điểm
│   │       ├── categories.py     # Danh mục du lịch
│   │       ├── conversations.py  # Quản lý lịch sử phòng chat
│   │       ├── rag.py            # RAG Ask (Chat/Voice), RAG Semantic Search
│   │       ├── trips.py          # Lập lịch trình AI, Day plans, Activities
│   │       ├── tts.py            # Realtime TTS stream, status, websocket probe
│   │       └── stt.py            # Nhận diện giọng nói STT
│   │
│   ├── core/                     # Cấu hình lõi & Bảo mật
│   │   ├── config.py             # Pydantic Settings đọc biến môi trường (.env)
│   │   └── security.py           # Hashing BCrypt, mã hóa & giải mã JWT Token
│   │
│   ├── db/                       # Kết nối cơ sở dữ liệu
│   │   └── session.py            # SQLModel Engine & Session generator
│   │
│   ├── models/                   # SQLModel Database Models (Ánh xạ bảng)
│   │   ├── user.py               # Bảng Users
│   │   ├── place.py              # Bảng Places, Reviews, Knowledge
│   │   ├── category.py           # Bảng Categories
│   │   ├── conversation.py       # Bảng Conversations, Messages
│   │   └── trip.py               # Bảng Trips, TripDays, TripActivities
│   │
│   ├── rag/                      # RAG Core Engine
│   │   ├── chain.py              # LangChain RAG pipeline & LLM chain
│   │   ├── prompt.py             # Prompts chuyên biệt cho Chat vs Voice Guide
│   │   ├── retriever.py          # Bộ truy xuất tài liệu tương đồng ngữ nghĩa
│   │   ├── vectorstore.py        # Quản lý kết nối Chroma Vector DB
│   │   └── embeddings.py         # Module sinh vector embeddings
│   │
│   ├── schemas/                  # Pydantic Request / Response Schemas
│   │   ├── auth.py, user.py, place.py, category.py
│   │   ├── conversation.py, trip.py, rag.py, tts.py, stt.py
│   │
│   ├── services/                 # Tầng Business Logic
│   │   ├── auth_service.py       # Nghiệp vụ xác thực & tài khoản
│   │   ├── conversation_service.py # Quản lý tin nhắn & ngữ cảnh hội thoại
│   │   ├── trip_planning.py      # Sinh lịch trình du lịch thông minh qua LLM
│   │   ├── itinerary_persistence.py # Lưu trữ cấu trúc lịch trình vào SQL Server
│   │   ├── tts_service.py        # Blaze AI Realtime TTS WebSocket & Pipelining
│   │   └── stt_service.py        # Dịch vụ nhận dạng giọng nói
│   │
│   └── main.py                   # FastAPI Application initialization & Middlewares
│
├── data/                         # Lưu trữ Chroma DB & file dữ liệu cào
│   ├── chroma/                   # Chroma Vector DB Storage
│   └── crawled_pages.jsonl       # Dữ liệu cào tri thức du lịch
│
├── scripts/                      # Các tiện ích bổ trợ
│   ├── crawl_danang_tourism.py   # Script cào bài viết du lịch
│   ├── ingest_crawled_knowledge.py # Nạp dữ liệu cào vào Chroma DB
│   └── ingest_rag.py             # Nạp dữ liệu Knowledge từ SQL Server vào Chroma
│
├── tests/                        # 11 Test Suites tự động (100% Pass)
│   ├── test_tts.py, test_ask_api.py, test_chain.py, test_prompt.py
│   ├── test_llm.py, test_stt.py, test_place_search.py, test_itinerary_generation.py
│   ├── test_conversation_memory.py, test_trip_planning_context.py, test_itinerary_persistence.py
│
├── .env.example                  # Mẫu biến môi trường
├── alembic.ini                   # Cấu hình Alembic
└── pyproject.toml                # Dependencies & Metadata dự án
```

---

## 📖 Tài liệu API (Interactive Documentation)

Khi server đang chạy, truy cập tài liệu tương tác:

| Đường dẫn | Công cụ | Chức năng |
|---|---|---|
| **`http://localhost:8000/docs`** | **Swagger UI** | Thử nghiệm trực tiếp các API ngay trên trình duyệt |
| **`http://localhost:8000/redoc`** | **ReDoc** | Đọc tài liệu chi tiết, trực quan hóa Schemas |
| **`http://localhost:8000/openapi.json`** | **OpenAPI Schema** | File cấu hình chuẩn OpenAPI 3.1 |

---

## 🌐 Danh sách Endpoint Chính (Key Endpoints)

### 1. Trợ lý AI Du lịch (RAG Assistant)

#### `POST /api/v1/rag/ask`
Gửi câu hỏi của người dùng để RAG AI truy xuất tài liệu và trả lời.

- **Request Body:**
  ```json
  {
    "query": "Thời tiết Đà Nẵng mùa này thế nào?",
    "conversation_id": 15,
    "mode": "voice"
  }
  ```
  - `mode="voice"`: Phản hồi súc tích 3–4 câu văn xuôi, không markdown, chuẩn bị sẵn cho TTS đọc ngay.
  - `mode="chat"`: Phản hồi chi tiết, hỗ trợ markdown, gạch đầu dòng và đề xuất lịch trình.

- **Response `200 OK`:**
  ```json
  {
    "conversation_id": 15,
    "message": {
      "id": 2055,
      "sender": "AI",
      "content": "Thời tiết Đà Nẵng hiện tại đang rất tuyệt vời với bầu trời quang đãng...",
      "created_at": "2026-10-14T09:24:58.263Z",
      "audio_url": null
    },
    "planning_context": null
  }
  ```

#### `POST /api/v1/rag/search`
Tìm kiếm ngữ nghĩa trực tiếp từ Chroma Vector Database:
```json
{
  "query": "Bà Nà Hills",
  "top_k": 3
}
```

---

### 2. Dịch vụ Giọng nói Realtime (TTS & STT)

#### `GET /api/v1/tts/status`
Kiểm tra cấu hình và tình trạng kết nối Blaze AI Realtime WebSocket:
```json
{
  "is_configured": true,
  "speaker_id": "DaNang-Nu-1-BL",
  "model": "2.0-realtime",
  "audio_format": "mp3",
  "ws_url": "wss://api.blaze.vn/v1/tts/realtime"
}
```

#### `GET /api/v1/tts/stream?text=...`
Tạo và stream trực tiếp dữ liệu âm thanh MP3 với độ trễ tối thiểu (hỗ trợ HEAD request preflight).

#### `POST /api/v1/stt/transcribe`
Tải file audio (`.wav`, `.mp3`, `.m4a`) để chuyển đổi thành văn bản tiếng Việt.

---

### 3. Lập Kế hoạch Chuyến đi AI (Trip Planner)

#### `POST /api/v1/trips/generate`
Tự động lập lịch trình du lịch trọn gói dựa trên điểm đến, số ngày, ngân sách và sở thích:
```json
{
  "destination": "Đà Nẵng - Hội An",
  "duration_days": 3,
  "budget_level": "trung bình",
  "travel_style": "khám phá ẩm thực & biển"
}
```

#### `POST /api/v1/trips/from-proposal`
Chuyển đổi trực tiếp đề xuất lịch trình từ cuộc trò chuyện RAG thành chuyến đi chính thức.

#### `GET /api/v1/trips` & `GET /api/v1/trips/{id}`
Xem danh sách và chi tiết chuyến đi kèm hoạt động từng ngày (`TripDays`, `TripActivities`).

---

### 4. Xác thực Tài khoản (Authentication)

- `POST /api/v1/auth/register`: Đăng ký tài khoản mới.
- `POST /api/v1/auth/login`: Đăng nhập lấy Bearer JWT access token.
- `GET /api/v1/auth/me`: Lấy thông tin tài khoản hiện tại (Cần header `Authorization: Bearer <token>`).

---

## 🧪 Kiểm thử Tự động (Testing)

Hệ thống đi kèm **11 test suites** kiểm thử toàn diện từ Unit test đến Integration test:

```bash
# Chạy toàn bộ 100 test cases tự động:
uv run python -m unittest discover -s tests -p "test_*.py"

# Chạy riêng kiểm thử TTS Realtime:
uv run python -m unittest tests/test_tts.py

# Chạy riêng kiểm thử RAG Chain:
uv run python -m unittest tests/test_chain.py
```

Kết quả kiểm thử tiêu chuẩn:
```text
Ran 100 tests in 38.428s
OK (100% tests passed)
```

---

## 📦 Các Lệnh Thường Dùng (Cheatsheet)

```bash
# Chạy Server dev tự động reload
uv run uvicorn app.main:app --reload

# Nạp dữ liệu ban đầu
uv run python seed.py

# Nạp tiếp dữ liệu mới vào Chroma Vector Store (Mặc định: Bỏ qua bài cũ, chỉ nhúng bài mới)
uv run python scripts/ingest_rag.py

# Xóa sạch và nạp lại toàn bộ từ đầu vào Chroma
uv run python scripts/ingest_rag.py --reset

# Tạo file migration Alembic mới
uv run alembic revision --autogenerate -m "ten_migration"

# Nâng cấp database lên bản migration mới nhất
uv run alembic upgrade head

# Hạ cấp database về bản migration trước
uv run alembic downgrade -1

# Cài đặt thêm thư viện mới
uv add <ten_package>
```
