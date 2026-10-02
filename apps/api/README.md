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
```

> ⚠️ **Quan trọng:** Đổi `JWT_SECRET` thành một chuỗi ngẫu nhiên mạnh trước khi deploy production.

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

### 6. Khởi chạy server

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

## 🧪 Test nhanh trên Swagger UI

1. Mở `http://127.0.0.1:8000/docs`
2. Gọi `POST /api/v1/auth/register` để tạo tài khoản
3. Gọi `POST /api/v1/auth/login` → copy `access_token`
4. Bấm **Authorize 🔒** → nhập token vào ô **Value**
5. Gọi `GET /api/v1/auth/me` để xem thông tin tài khoản

---

## 📦 Các lệnh hữu ích

```bash
# Cài thêm dependency
uv add <package-name>

# Chạy script Python
uv run python <script.py>

# Tạo migration mới
uv run alembic revision --autogenerate -m "mô tả thay đổi"

# Áp dụng migration
uv run alembic upgrade head

# Rollback migration
uv run alembic downgrade -1

# Xem lịch sử migration
uv run alembic history
```
