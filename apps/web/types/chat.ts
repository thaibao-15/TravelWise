export type MessageRole = "user" | "assistant" | "system";

export type MessageStatus = "sending" | "success" | "error";

export interface ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  timestamp: Date;
  status?: MessageStatus;
  errorMessage?: string;
}

export interface ChatAskRequest {
  message?: string;
  query?: string;
  conversation_id?: number | null;
}

export type RAGAskRequest = ChatAskRequest;

export interface AIMessageResponse {
  id: number;
  sender: string;
  content: string;
  created_at: string;
  audio_url?: string | null;
}

export interface ChatAskResponse {
  conversation_id: number;
  message: AIMessageResponse;
  // Giữ fallback dự phòng nếu cần
  answer?: string;
}

export type RAGAskResponse = ChatAskResponse;

export interface SuggestedQuestion {
  id: string;
  category: string;
  title: string;
  prompt: string;
  icon: string;
}
