# 🌴 TravelWise Web — Frontend Application

**TravelWise Web** là giao diện người dùng của nền tảng du lịch thông minh, tích hợp **Trợ lý AI Hướng dẫn viên Giọng nói Bản địa (Voice Companion)**, **Hỏi đáp RAG Du lịch** và **Lập kế hoạch Lịch trình Tự động (Trip Planner)**.

---

## 🛠️ Công nghệ Sử dụng (Tech Stack)

| Thành phần | Công nghệ / Thư viện | Mô tả |
|---|---|---|
| **Framework** | [Next.js 16.3](https://nextjs.org/) (App Router, Turbopack) | Server & Client Components, SSR / SSG tối ưu SEO |
| **UI Library** | [React 19](https://react.dev/) + [TypeScript 5](https://www.typescriptlang.org/) | Type-safe, React 19 Hooks, Quản lý State bất đồng bộ |
| **Styling** | [Tailwind CSS v4](https://tailwindcss.com/) | Giao diện Dark Theme hiện đại, Glassmorphism, Micro-animations |
| **Realtime Audio** | Web Speech API + Web Audio API | Nhận diện giọng nói STT và phát âm thanh Streaming TTS Queue |
| **Package Manager** | [Bun](https://bun.sh/) (Khuyên dùng) hoặc [npm](https://www.npmjs.com/) | Cài đặt và build ứng dụng siêu tốc |

---

## ✨ Tính năng Nổi bật (Key Features)

- 🎙️ **Voice Tour Guide (`/voice-guide`)**:
  - Đàm thoại 2 chiều thời gian thực với trợ lý giọng nói bản địa tiếng Việt.
  - **Streaming TTS Queue**: Cắt nhỏ câu đầu tiên phát ngay trong vòng **< 1s** song song với lúc AI đang tạo văn bản.
  - **Voice Orb phát sáng đa tầng**: Hiệu ứng sóng radar neon khi đang nghe, nhịp đập khi AI suy nghĩ, và cột sóng âm Equalizer khi AI đang nói.
  - Thẻ câu hỏi gợi ý nhanh phân loại theo *Lịch trình, Ẩm thực, Kinh nghiệm, Thời tiết*.
  - Tự động ngắt lời AI tức thì khi người dùng chạm nút micro.

- 💬 **Smart Travel Chat (`/chat`)**:
  - Trò chuyện du lịch thông minh với Gemini RAG Engine.
  - Hỗ trợ streaming token thời gian thực, lưu trữ ngữ cảnh đa lượt (Multi-turn memory).
  - Tự động phát hiện ý định tạo lịch trình và đồng bộ với bảng kế hoạch.

- 🗺️ **Trip Canvas & Planner (`/trips`, `/trips/[id]`)**:
  - Bảng vẽ lịch trình trực quan theo từng ngày (Day-by-day Itinerary).
  - Tự động sinh danh sách hoạt động, địa điểm ăn uống, thời gian và chi phí ước tính.

- 📍 **Khám phá Địa điểm (`/places`, `/places/[id]`)**:
  - Tra cứu danh lam thắng cảnh, di tích lịch sử và đặc sản ẩm thực miền Trung.
  - Tích hợp bộ lọc theo vùng miền, danh mục và từ khóa ngữ nghĩa.

- 🔐 **Xác thực & Cá nhân hóa (`/login`, `/register`, `/profile`)**:
  - Đăng ký, đăng nhập tài khoản với JWT token bảo mật.
  - Lưu trữ và đồng bộ hóa lịch sử hội thoại trên các thiết bị.

---

## 📂 Cấu trúc Thư mục (Directory Structure)

```text
apps/web/
├── app/                        # Next.js App Router (Pages, Layouts & Routes)
│   ├── chat/                   # Trang Chat RAG du lịch truyền thống
│   ├── voice-guide/            # Trang Voice Companion thời gian thực
│   ├── places/                 # Danh bạ địa điểm du lịch & chi tiết
│   ├── trips/                  # Kế hoạch & Quản lý lịch trình chuyến đi
│   ├── login/ & register/      # Đăng nhập & Đăng ký tài khoản
│   ├── profile/                # Thông tin tài khoản người dùng
│   ├── layout.tsx              # Root Layout bọc toàn bộ ứng dụng
│   ├── page.tsx                # Trang chủ Landing Page
│   └── globals.css             # Cấu hình Tailwind CSS v4 & theme
│
├── components/                 # Các UI Components tái sử dụng
│   ├── voice-guide/            # Header, VoiceMicButton, VoiceMessageBubble
│   ├── chat/                   # ChatHeader, ChatInput, ChatMessage, SuggestedQuestions
│   ├── canvas/                 # TripCanvas (Thanh bên kế hoạch lịch trình)
│   ├── places/                 # PlaceCard, FilterBar, PlaceDetail
│   ├── trips/                  # TripCard, DaySchedule, ActivityItem
│   └── ui/                     # Nút bấm, Modal, Badge, Loading indicators
│
├── hooks/                      # Custom React Hooks
│   ├── useVoiceCompanion.ts    # Điều khiển Voice State, Streaming Queue, Mic
│   ├── useChat.ts              # Quản lý SSE Streaming chat, hội thoại, lịch trình
│   ├── useSpeechToText.ts      # Web Speech Recognition API wrapper
│   └── useAuth.ts              # Quản lý phiên đăng nhập và User state
│
├── services/                   # Tầng giao tiếp Backend API
│   ├── chat.service.ts         # Gửi nhận tin nhắn, streaming RAG SSE
│   ├── tts.service.ts          # StreamingTTSQueue, Blaze AI / Web Speech TTS
│   ├── trip.service.ts         # CRUD lịch trình & kế hoạch du lịch
│   └── place.service.ts        # Tìm kiếm và tra cứu địa điểm
│
├── types/                      # Định nghĩa kiểu dữ liệu TypeScript
│   ├── chat.ts                 # Message, Proposal, StreamPayload types
│   ├── trip.ts                 # Itinerary, DayPlan, Activity types
│   └── place.ts                # Place, Location, Category types
│
├── public/                     # Tài nguyên tĩnh (Favicon, Logo, Demo audio)
├── package.json                # Định nghĩa thư viện & scripts
└── tsconfig.json               # Cấu hình TypeScript
```

---

## 🚀 Hướng dẫn Cài đặt & Chạy ứng dụng

### 1. Yêu cầu hệ thống
- **Runtime**: [Bun](https://bun.sh/) (khuyên dùng) hoặc **Node.js** (v18.18 trở lên).
- **Backend API**: FastAPI server đang chạy tại `http://localhost:8000` (xem hướng dẫn tại `apps/api/README.md`).

### 2. Cài đặt Dependencies

Mở terminal tại thư mục `apps/web`:

```bash
cd apps/web
bun install
# hoặc nếu dùng npm:
# npm install
```

### 3. Cấu hình Biến môi trường (Tùy chọn)

Mặc định ứng dụng sẽ trỏ trực tiếp đến `http://localhost:8000`. Nếu Backend của bạn chạy ở cổng hoặc host khác, tạo file `.env.local` trong thư mục `apps/web`:

```env
NEXT_PUBLIC_API_URL=http://localhost:8000
```

### 4. Khởi chạy Development Server

```bash
bun run dev
# hoặc nếu dùng npm:
# npm run dev
```

Mở trình duyệt và truy cập: **[http://localhost:3000](http://localhost:3000)**

- Trang chủ: `http://localhost:3000/`
- Trợ lý Giọng nói Voice Guide: `http://localhost:3000/voice-guide`
- Chat Box AI: `http://localhost:3000/chat`
- Kế hoạch Chuyến đi: `http://localhost:3000/trips`
- Khám phá Địa điểm: `http://localhost:3000/places`

---

## 📜 Các Lệnh Thực Thi (Available Scripts)

| Lệnh | Trình quản lý gói | Mục đích |
|---|---|---|
| `bun run dev` | Bun / npm | Chạy máy chủ phát triển cục bộ (Turbopack) |
| `bun run build` | Bun / npm | Kiểm tra TypeCheck và đóng gói production bundle |
| `bun run start` | Bun / npm | Chạy production server sau khi đã build |
| `bun run lint` | Bun / npm | Kiểm tra lỗi cú pháp và chuẩn code bằng ESLint |

---

## 🔗 Liên kết với Backend

Để các tính năng AI hoạt động đầy đủ:
1. Đảm bảo Backend FastAPI đã được kích hoạt:
   ```bash
   cd apps/api
   uv run uvicorn app.main:app --reload
   ```
2. Kiểm tra trạng thái dịch vụ TTS Realtime tại: [http://localhost:8000/api/v1/tts/status](http://localhost:8000/api/v1/tts/status)
