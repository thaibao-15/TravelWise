# TravelWise API

Backend REST API cho ứng dụng du lịch **TravelWise**, xây dựng bằng **FastAPI** + **SQLModel** + **SQL Server**.

---

## 🛠️ Tech Stack

| Thành phần | Công nghệ |
|---|---|
| Web framework | FastAPI |
| ORM | SQLModel + SQLAlchemy |
| Database | Microsoft SQL Server |
| DB Driver | pyodbc (ODBC Driver 17) |
| Migration | Alembic |
| Auth | PyJWT + pwdlib (BCrypt) |
| Config | Pydantic Settings |
| Runtime | Python ≥ 3.14 |
| Package manager | [uv](https://docs.astral.sh/uv/) |

---

## ⚙️ Yêu cầu hệ thống

- **Python** ≥ 3.14
- **uv** — package manager ([cài đặt](https://docs.astral.sh/uv/getting-started/installation/))
- **Microsoft SQL Server** (local hoặc remote)
- **ODBC Driver 17 for SQL Server** — [tải tại đây](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server)

---

## 🚀 Hướng dẫn chạy dự án

### 1. Clone & di chuyển vào thư mục API

```bash
git clone <repo-url>
cd TravelWise/apps/api
```

### 2. Cài đặt dependencies

```bash
uv sync
```

> `uv` sẽ tự tạo virtual environment (`.venv`) và cài đặt toàn bộ dependencies từ `pyproject.toml`.

### 3. Cấu hình biến môi trường

Copy file mẫu và chỉnh sửa thông số kết nối:

```bash
cp .env.example .env
```

Mở file `.env` và cập nhật:

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

# LLM Configuration (Google Gemini miễn phí hoặc OpenAI)
LLM_PROVIDER=gemini
GEMINI_API_KEY=your-gemini-api-key-here
GEMINI_MODEL=gemini-3.5-flash-lite

# RAG Embedding Configuration (local = miễn phí 100%, không tốn quota)
EMBEDDING_PROVIDER=local
```

> ⚠️ **Quan trọng:** 
> - Đổi `JWT_SECRET` thành một chuỗi ngẫu nhiên mạnh trước khi deploy production.
> - Lấy `GEMINI_API_KEY` miễn phí tại [Google AI Studio](https://aistudio.google.com/apikey).

### 4. Tạo database trên SQL Server

Kết nối vào SQL Server và chạy lệnh sau để tạo database và bảng:

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

### 5. Chạy migration với Alembic

```bash
# Tạo migration mới (nếu có thay đổi model)
uv run alembic revision --autogenerate -m "initial"

# Áp dụng migration lên database
uv run alembic upgrade head
```

### 6. Khởi tạo dữ liệu mẫu (Seeding)

Nạp dữ liệu các địa điểm du lịch, danh mục và bài viết tri thức vào SQL Server:

```bash
uv run python seed.py
```

### 7. Nạp dữ liệu từ SQL Server vào Chroma Vector Database (RAG Ingestion)

Để hệ thống RAG có thể tìm kiếm và trả lời thông minh, chạy lệnh sau để chuyển đổi các bài viết tri thức từ SQL Server sang vector embeddings và lưu vào Chroma:

```bash
uv run python scripts/ingest_rag.py
```

> 💡 **Cơ chế hoạt động:**
> 1. Đọc toàn bộ các bài viết từ bảng `Knowledge` trong SQL Server.
> 2. Chia bài viết thành các đoạn nhỏ (`chunk_size=500`, `overlap=100`) bằng `RecursiveCharacterTextSplitter`.
> 3. Tạo vector embeddings (mặc định dùng model local `all-MiniLM-L6-v2` miễn phí, không tốn quota API).
> 4. Lưu và đánh index vào thư mục `data/chroma`.
> 5. Script sử dụng ID cố định (`knowledge_{id}_chunk_{index}`) nên có thể **chạy lại bất kỳ lúc nào** khi có bài viết mới mà không lo trùng lặp dữ liệu.

### 8. Khởi chạy server

**Development (auto-reload):**
```bash
uv run uvicorn app.main:app --reload
```

**Production:**
```bash
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

Server sẽ chạy tại: `http://127.0.0.1:8000`

---

## 📋 Cấu trúc thư mục

```
apps/api/
├── alembic/                  # Alembic migrations
│   ├── versions/             # Các file migration
│   └── env.py                # Cấu hình Alembic
├── app/
│   ├── api/
│   │   ├── deps.py           # FastAPI dependencies (auth)
│   │   └── routes/
│   │       ├── auth.py       # Endpoints: /register, /login, /me
│   │       └── users.py      # Endpoints: /users
│   ├── core/
│   │   ├── config.py         # Pydantic Settings (đọc .env)
│   │   └── security.py       # BCrypt hashing + JWT utilities
│   ├── db/
│   │   └── session.py        # SQLModel engine & session
│   ├── models/
│   │   └── user.py           # SQLModel User model
│   ├── schemas/
│   │   ├── auth.py           # RegisterRequest, LoginRequest, TokenResponse
│   │   └── user.py           # UserResponse
│   ├── services/
│   │   └── auth_service.py   # Business logic tầng Service
│   └── main.py               # FastAPI app entry point
├── .env                      # Biến môi trường (không commit)
├── .env.example              # Mẫu biến môi trường
├── alembic.ini               # Cấu hình Alembic
└── pyproject.toml            # Dependencies & metadata
```

---

## 📖 API Documentation

Sau khi chạy server, truy cập:

| URL | Mô tả |
|---|---|
| `http://127.0.0.1:8000/docs` | **Swagger UI** (interactive docs) |
| `http://127.0.0.1:8000/redoc` | **ReDoc** (readable docs) |
| `http://127.0.0.1:8000/openapi.json` | OpenAPI JSON schema |

---

## 🔐 Authentication

### Đăng ký tài khoản

```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "123456",
  "full_name": "Nguyen Van A"
}
```

**Response `201 Created`:**
```json
{
  "id": 1,
  "email": "user@example.com",
  "full_name": "Nguyen Van A",
  "avatar_url": null,
  "role": "USER",
  "is_active": true,
  "created_at": "2026-10-02T10:00:00Z",
  "updated_at": "2026-10-02T10:00:00Z"
}
```

---

### Đăng nhập

```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "123456"
}
```

**Response `200 OK`:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```

---

### Lấy thông tin người dùng hiện tại

```http
GET /api/v1/auth/me
Authorization: Bearer <access_token>
```

**Response `200 OK`:**
```json
{
  "id": 1,
  "email": "user@example.com",
  "full_name": "Nguyen Van A",
  "avatar_url": null,
  "role": "USER",
  "is_active": true,
  "created_at": "2026-10-02T10:00:00Z",
  "updated_at": "2026-10-02T10:00:00Z"
}
```

---

### HTTP Status Codes

| Code | Ý nghĩa |
|---|---|
| `200` | Thành công |
| `201` | Tạo mới thành công |
| `401` | Sai email/password hoặc token không hợp lệ |
| `403` | Tài khoản bị vô hiệu hóa |
| `409` | Email đã tồn tại |
| `422` | Request body không hợp lệ |

---

---

## 🤖 RAG & AI Assistant APIs

TravelWise tích hợp hệ thống RAG (Retrieval-Augmented Generation) kết hợp Chroma Vector Database và Gemini Chat Model.

### 1. Hỏi đáp du lịch thông minh (RAG Ask)

Gửi câu hỏi của người dùng, hệ thống tự động tìm kiếm tài liệu liên quan nhất và sinh câu trả lời chính xác, thân thiện:

```http
POST /api/v1/rag/ask
Content-Type: application/json

{
  "message": "Chùa Linh Ứng có gì đặc biệt?"
}
```

**Response `200 OK`:**
```json
{
  "conversation_id": 15,
  "message": {
    "id": 42,
    "sender": "AI",
    "content": "Chùa Linh Ứng - Bãi Bụt nổi bật với tượng Phật Quan Thế Âm cao 67m (tương đương tòa nhà 30 tầng), là một trong những tượng Phật cao nhất Việt Nam...",
    "created_at": "2026-10-05T08:00:00Z",
    "audio_url": null
  }
}
```

---

### 2. Tìm kiếm ngữ nghĩa tri thức (Semantic Search)

Tìm kiếm các đoạn tri thức liên quan dựa trên độ tương đồng ngữ nghĩa:

```http
POST /rag/search
Content-Type: application/json

{
  "query": "Bà Nà Hills",
  "top_k": 3
}
```

**Response `200 OK`:**
```json
{
  "query": "Bà Nà Hills",
  "results": [
    {
      "content": "Khu du lịch Bà Nà Hills nằm trên đỉnh núi Chúa...",
      "score": 0.8524,
      "metadata": {
        "place_name": "Bà Nà Hills",
        "knowledge_id": 1,
        "chunk_index": 0
      }
    }
  ]
}
```

---

### 3. Kiểm tra kết nối LLM (Health Check)

```http
POST /rag/test-llm
Content-Type: application/json

{
  "prompt": "Xin chào"
}
```

---

## 🧪 Test nhanh trên Swagger UI

1. Mở `http://127.0.0.1:8000/docs`
2. Đăng ký & Đăng nhập để lấy `access_token` nếu cần gọi các API bảo vệ.
3. Thử nghiệm ngay các endpoint `/rag/search` và `/rag/ask` trực tiếp trên Swagger.

---

## 📦 Các lệnh hữu ích

```bash
# Khởi chạy server development
uv run uvicorn app.main:app --reload

# Seed dữ liệu vào SQL Server
uv run python seed.py

# Nạp dữ liệu từ SQL Server vào Chroma Vector Database
uv run python scripts/ingest_rag.py

# Kiểm tra kết nối LLM
uv run python scripts/test_llm.py

# Chạy toàn bộ test suites tự động
uv run python -m unittest discover tests

# Cài thêm dependency
uv add <package-name>

# Tạo migration mới
uv run alembic revision --autogenerate -m "mô tả thay đổi"

# Áp dụng migration
uv run alembic upgrade head

# Rollback migration
uv run alembic downgrade -1

# Xem lịch sử migration
uv run alembic history
```

