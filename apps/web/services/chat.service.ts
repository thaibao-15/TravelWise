import { apiFetch } from "@/services/api";
import { RAG_ENDPOINTS } from "@/lib/constants";
import { RAGAskRequest, RAGAskResponse } from "@/types/chat";

export const chatService = {
  /**
   * Send a travel query to TravelWise RAG AI service
   */
  async askRAG(query: string): Promise<RAGAskResponse> {
    const payload: RAGAskRequest = { query };
    try {
      // Primary route: /rag/ask
      return await apiFetch<RAGAskResponse>(RAG_ENDPOINTS.ASK, {
        method: "POST",
        body: JSON.stringify(payload),
      });
    } catch (err: unknown) {
      // Fallback to /api/v1/rag/ask if root route fails with 404
      const status = (err as { status?: number })?.status;
      if (status === 404) {
        return await apiFetch<RAGAskResponse>(RAG_ENDPOINTS.ASK_V1, {
          method: "POST",
          body: JSON.stringify(payload),
        });
      }
      throw err;
    }
  },
};
