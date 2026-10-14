# Quy tắc Backend (FastAPI & Python)

1. **Async & Non-blocking I/O**:
   - Tất cả endpoint, external API calls (Blaze AI, Gemini, Ollama) và database operations phải là asynchronous (`async def`, `httpx.AsyncClient`).
   - Sử dụng In-flight Request Coalescing (`asyncio.Future`) khi nhận các request đồng thời có cùng tham số để tái sử dụng kết quả, tiết kiệm tài nguyên và băng thông.
2. **Cấu hình & Bảo mật**:
   - Mọi cấu hình (API keys, URLs, model names) phải load qua `app.core.config.settings` và file `.env`.
   - Tuyệt đối không hardcode credentials trong code.
3. **Pydantic Validation**:
   - Validate toàn bộ request body và response schema bằng Pydantic models trong `app/schemas/`.
4. **Kiểm tra cú pháp**:
   - Chạy lệnh `uv run python -c "import app.main; print('OK')"` để đảm bảo không bị lỗi import hoặc syntax error.
