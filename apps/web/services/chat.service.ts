import { apiFetch } from "@/services/api";
import { AI_ENDPOINTS } from "@/lib/constants";
import { ChatAskRequest, ChatAskResponse } from "@/types/chat";

export const chatService = {
  /**
   * Gửi câu hỏi du lịch đến Trợ lý AI TravelWise
   */
  async askAI(
    query: string,
    conversationId?: number | null
  ): Promise<ChatAskResponse> {
    const payload: ChatAskRequest = {
      message: query,
      conversation_id: conversationId || undefined,
    };

    return await apiFetch<ChatAskResponse>(AI_ENDPOINTS.ASK, {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  /**
   * Alias ngắn gọn cho askAI
   */
  async ask(
    query: string,
    conversationId?: number | null
  ): Promise<ChatAskResponse> {
    return this.askAI(query, conversationId);
  },

  /**
   * Alias tương thích ngược
   */
  async askRAG(
    query: string,
    conversationId?: number | null
  ): Promise<ChatAskResponse> {
    return this.askAI(query, conversationId);
  },

  /**
   * Lấy danh sách tin nhắn của một cuộc hội thoại cụ thể
   */
  async getConversationMessages(conversationId: number) {
    return await apiFetch<
      Array<{
        id: number;
        conversation_id: number;
        sender: string;
        content: string;
        created_at: string;
      }>
    >(`/api/v1/conversations/${conversationId}/messages`, {
      method: "GET",
    });
  },
};
