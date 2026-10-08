import { SuggestedQuestion } from "@/types/chat";

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";

export const AI_ENDPOINTS = {
  ASK: "/api/v1/rag/ask",
  ASK_STREAM: "/api/v1/rag/ask-stream",
  SEARCH: "/api/v1/rag/search",
  TEST_LLM: "/api/v1/rag/test-llm",
};

export const RAG_ENDPOINTS = AI_ENDPOINTS;

export const DEFAULT_SUGGESTED_QUESTIONS: SuggestedQuestion[] = [
  {
    id: "1",
    category: "Địa điểm & Di tích",
    title: "Chùa Linh Ứng Đà Nẵng",
    prompt: "Chùa Linh Ứng ở Đà Nẵng có gì đặc biệt và nên đi vào thời điểm nào?",
    icon: "⛩️",
  },
  {
    id: "2",
    category: "Ẩm thực & Đặc sản",
    title: "Đặc sản Hội An",
    prompt: "Gợi ý các món ăn đặc sản không thể bỏ qua khi du lịch Hội An?",
    icon: "🍜",
  },
  {
    id: "3",
    category: "Lịch trình Du lịch",
    title: "Lịch trình Đà Nẵng 3N2Đ",
    prompt: "Lên kế hoạch lịch trình du lịch Đà Nẵng 3 ngày 2 đêm tối ưu nhất?",
    icon: "🗺️",
  },
  {
    id: "4",
    category: "Vé & Trải nghiệm",
    title: "Kinh nghiệm Bà Nà Hills",
    prompt: "Giá vé và kinh nghiệm vui chơi tự túc tại Bà Nà Hills?",
    icon: "🎡",
  },
];
