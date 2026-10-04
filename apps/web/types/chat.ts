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

export interface RAGAskRequest {
  query: string;
}

export interface RAGAskResponse {
  query: string;
  answer: string;
}

export interface SuggestedQuestion {
  id: string;
  category: string;
  title: string;
  prompt: string;
  icon: string;
}
