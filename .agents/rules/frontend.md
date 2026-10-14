# Quy tắc Frontend (Next.js & React)

1. **App Router & Client Components**:
   - Khai báo `'use client'` ở các component sử dụng React hooks, browser APIs (Audio, WebSocket, SpeechRecognition, MediaStream).
2. **Tránh Stale Closure trong Callbacks Bất đồng bộ**:
   - Đối với callback từ SSE event stream (`onToken`, `onSentence`, `onDone`) hoặc Web Audio API: Luôn dùng `useRef` hoặc `useCallback` với dependencies đầy đủ.
3. **Real-time TTS Streaming Queue**:
   - Khi có text stream từ LLM, sử dụng `StreamingTTSQueue` (`apps/web/services/tts.service.ts`) để tách câu ngay khi đủ dấu câu (`.`, `!`, `?`, `\n`) và phát âm thanh câu đầu tiên ngay lập tức, không đợi tải toàn bộ văn bản.
   - Luôn ngắt microphone (`stopRecording()`) trước khi audio phát ra ngoài loa để tránh mic thu ngược tiếng bot (echo feedback loop).
4. **Kiểm thử trước khi bàn giao**:
   - Chạy `bun run build` tại `apps/web` để đảm bảo không có lỗi type hoặc compile.
