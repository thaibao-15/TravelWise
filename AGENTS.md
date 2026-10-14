# TravelWise — AI Agent Guidelines & Coding Standards

Tài liệu này định hình các quy tắc, tiêu chuẩn kiến trúc và quy trình phát triển cho AI Assistant khi lập trình trong dự án **TravelWise**.

---

## 1. Tổng quan Kiến trúc Dự án (Monorepo)

TravelWise là nền tảng du lịch thông minh tích hợp Trợ lý Hướng dẫn viên AI, Lập kế hoạch lịch trình tự động (RAG Trip Planner) và Đàm thoại giọng nói thời gian thực (Real-time Voice Companion).

```
TravelWise/
├── apps/
│   ├── web/                    # Frontend: Next.js (App Router), React, TypeScript, TailwindCSS
│   │   ├── app/                # Next.js Pages & Layouts (voice-guide, chat, trips, places, ...)
│   │   ├── components/         # Reusable UI & Feature components
│   │   ├── hooks/              # Custom React Hooks (useVoiceCompanion, useChat, useSpeechToText)
│   │   ├── services/           # API client, chatService, ttsService
│   │   └── types/              # TypeScript definitions & interfaces
│   │
│   └── api/                    # Backend: FastAPI, Python, SQLModel, ChromaDB, LangChain
│       ├── app/
│       │   ├── api/routes/     # API Endpoints (rag, tts, stt, trips, places, conversations, auth)
│       │   ├── core/           # Config, Security, Database connection
│       │   ├── models/         # SQLModel database models
│       │   ├── rag/            # RAG Engine: chain, retriever, embeddings, vectorstore, prompt
│       │   ├── schemas/        # Pydantic request/response schemas
│       │   └── services/       # Business logic (trip_planning, tts_service, conversation_service)
│       └── data/               # Vector DB Chroma storage & crawled travel pages
```

---

## 2. Công cụ Quản lý & Lệnh Thực thi (Dev Environment)

### Frontend (`apps/web`):
- **Trình quản lý gói**: Sử dụng `bun` (ưu tiên) hoặc `npm`.
- **Chạy Server phát triển**: `bun run dev` (chạy tại thư mục `apps/web`).
- **Kiểm tra biên dịch & Typecheck**: `bun run build`.
- **Cài đặt thư viện**: `bun add <package-name>` (hoặc `bun add -d <pkg>` cho devDependencies).

### Backend (`apps/api`):
- **Trình quản lý gói & môi trường**: Sử dụng `uv`.
- **Chạy Server phát triển**: `uv run uvicorn app.main:app --reload` (chạy tại `apps/api`).
- **Thực thi script / test**: `uv run python <script.py>` hoặc `uv run python -c "..."`.
- **Cài đặt thư viện**: `uv add <package-name>`.

---

## 3. Quy tắc Lập trình Frontend (Next.js & React)

1. **Next.js App Router**:
   - Tuân thủ cấu trúc App Router hiện đại (`use client` ở đầu các component có tương tác state/hooks/browser APIs).
   - Sử dụng dynamic routing (`[id]/page.tsx`) theo chuẩn Next.js.
2. **Quản lý State & Async Callbacks**:
   - Khi xử lý streaming SSE hoặc audio callbacks, luôn dùng `useRef` kết hợp `useCallback` để tránh lỗi **stale closures**.
   - Cẩn trọng với `useEffect`: Tránh race condition giữa các state cập nhật bất đồng bộ (ví dụ: `isLoadingChat` và `voiceState`).
3. **Giao diện & Thẩm mỹ (UI/UX)**:
   - Sử dụng Tailwind CSS với theme tối (`bg-slate-950`, `text-slate-100`, border `slate-800`).
   - Giữ thiết kế hiện đại, mượt mà, micro-interactions tinh tế, responsive trên mọi kích thước màn hình.
4. **Xử lý Âm thanh & Streaming TTS**:
   - Sử dụng `StreamingTTSQueue` trong `tts.service.ts` để phát âm thanh câu đầu tiên ngay lập tức (< 1s) thay vì chờ tải toàn bộ đoạn văn bản.
   - Luôn ngắt microphone (`stopRecording()`) trước khi phát giọng nói để tránh mic thu lại âm thanh từ loa gây lặp vô hạn.

---

## 4. Quy tắc Lập trình Backend (FastAPI & Python)

1. **Type Annotations & Validation**:
   - Khai báo Type Hints đầy đủ (`Optional[T]`, `list[T]`, `dict[K, V]`).
   - Sử dụng Pydantic models để validate request body / query parameters.
2. **Kiến trúc phân tầng rõ ràng**:
   - `app/api/routes/`: Chỉ tiếp nhận request, gọi dependencies, điều hướng sang services.
   - `app/services/`: Chứa toàn bộ business logic phức tạp.
   - `app/rag/`: Đóng gói logic tìm kiếm ngữ nghĩa, prompt templates và chuỗi LLM chain.
3. **Tối ưu Bất đồng bộ (Async/Await)**:
   - Các thao tác I/O (WebSocket, HTTP calls, DB session query) phải là `async def` và dùng non-blocking client (`httpx.AsyncClient`, `websockets.connect`).
   - Áp dụng kỹ thuật Request Coalescing (`asyncio.Future`) khi có nhiều request đồng thời cùng nội dung để tránh lãng phí tài nguyên và nghẽn API bên ngoài.
4. **Bảo mật & Cấu hình**:
   - Tất cả API keys và URL bên ngoài phải đọc qua `app.core.config.settings` (đọc từ file `.env`).
   - Tuyệt đối không hardcode API keys hoặc secrets trực tiếp vào mã nguồn.

---

## 5. Quy tắc RAG & AI Voice Companion

1. **Giọng điệu Voice Mode**:
   - Prompt dành riêng cho Voice (`RAG_VOICE_SYSTEM_INSTRUCTION`): Trả lời tự nhiên, độ dài 3–4 câu (80–150 từ), đi thẳng vào nội dung.
   - Tuyệt đối KHÔNG lặp lại câu chào "Chào bạn, tôi là TravelWise AI" ở mỗi lượt trả lời.
   - Tuyệt đối KHÔNG xuất định dạng markdown (`**`, `#`, gạch đầu dòng `-`, emoji) trong chế độ voice để TTS đọc mượt mà.
2. **Chất lượng dữ liệu RAG**:
   - Đảm bảo danh tính hệ thống luôn là **TravelWise AI**.
   - Không đưa các tài liệu quảng cáo của công ty lữ hành bên thứ ba (như AZ Tour, Tourism Danang) vào làm nhận diện thương hiệu của bot.

---

## 6. Quy trình Xác thực & Kiểm thử (Verification Checklist)

Mỗi khi chỉnh sửa hoặc thêm tính năng:
1. **Kiểm tra TypeScript / Build**: Chạy `bun run build` tại `apps/web` đảm bảo không có lỗi type hoặc compile.
2. **Kiểm tra Python syntax / imports**: Chạy `uv run python -c "from app.services.<module> import ...; print('OK')"` tại `apps/api`.
3. **Giữ nguyên tính toàn vẹn**: Bảo toàn toàn bộ comments, cấu trúc code hiện có và không làm ảnh hưởng đến các tính năng khác.
