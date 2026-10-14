# Quy tắc Chung & Tối ưu Code Dự án (General Rules)

1. **Hiệu năng & Trải nghiệm Thời gian thực (Real-time First)**:
   - Mọi luồng xử lý tương tác giọng nói, tìm kiếm hay phản hồi chat cần được tối ưu stream/queue theo từng chunk nhỏ để người dùng nhận được phản hồi ngay lập tức (< 1s).
2. **Kiến trúc Monorepo**:
   - `apps/web`: Frontend Next.js (App Router), React, TypeScript, TailwindCSS. Chạy bằng `bun`.
   - `apps/api`: Backend FastAPI, Python, SQLModel, ChromaDB, LangChain. Chạy bằng `uv`.
3. **An toàn kiểu dữ liệu (Strict Typing)**:
   - TypeScript không dùng `any` bừa bãi.
   - Python luôn có Type Hints (`Optional[T]`, `list[T]`, Pydantic models).
4. **Không làm phá vỡ logic cũ**:
   - Luôn giữ lại docstring, comment và kiểm tra độ tương thích ngược trước khi refactor.
