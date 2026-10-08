import { apiFetch } from "@/services/api";
import { AI_ENDPOINTS } from "@/lib/constants";
import { ChatAskRequest, ChatAskResponse } from "@/types/chat";

export const chatService = {
  /**
   * Gửi câu hỏi du lịch đến Trợ lý AI TravelWise (Đồng bộ)
   */
  async askAI(
    query: string,
    conversationId?: number | null,
    mode?: "chat" | "voice"
  ): Promise<ChatAskResponse> {
    const payload: ChatAskRequest = {
      message: query,
      conversation_id: conversationId || undefined,
      mode: mode || "chat",
    };

    return await apiFetch<ChatAskResponse>(AI_ENDPOINTS.ASK, {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  /**
   * Hỏi đáp AI qua Server-Sent Events Streaming để giảm độ trễ phản hồi tức thì
   */
  async askStream(
    query: string,
    conversationId: number | null | undefined,
    mode: "chat" | "voice" = "chat",
    callbacks: {
      onToken: (token: string) => void;
      onInit?: (convId: number) => void;
      onDone?: (data: { conversation_id: number; message_id: number; content: string }) => void;
      onError?: (err: Error) => void;
    }
  ): Promise<string> {
    const apiUrl = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
    const token =
      typeof window !== "undefined"
        ? localStorage.getItem("travelwise_token") || localStorage.getItem("token")
        : null;

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }

    const payload: ChatAskRequest = {
      message: query,
      conversation_id: conversationId || undefined,
      mode,
    };

    const res = await fetch(`${apiUrl}${AI_ENDPOINTS.ASK_STREAM}`, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      const errText = await res.text().catch(() => "Lỗi kết nối");
      const err = new Error(`Lỗi AI Stream (HTTP ${res.status}): ${errText}`);
      callbacks.onError?.(err);
      throw err;
    }

    if (!res.body) {
      throw new Error("Phản hồi không chứa luồng dữ liệu stream.");
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder("utf-8");
    let accumulatedText = "";
    let buffer = "";

    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          const trimmedLine = line.trim();
          if (trimmedLine.startsWith("data: ")) {
            try {
              const data = JSON.parse(trimmedLine.slice(6));
              if (data.type === "init" && data.conversation_id) {
                callbacks.onInit?.(data.conversation_id);
              } else if (data.type === "token" && data.token) {
                accumulatedText += data.token;
                callbacks.onToken(data.token);
              } else if (data.type === "done") {
                callbacks.onDone?.(data);
              } else if (data.type === "error") {
                throw new Error(data.message || "Lỗi tạo câu trả lời");
              }
            } catch (pErr) {
              if (pErr instanceof Error && pErr.message !== "Lỗi tạo câu trả lời") {
                // Ignore parse errors on partial chunks
              } else {
                throw pErr;
              }
            }
          }
        }
      }
    } catch (streamErr: unknown) {
      const err = streamErr instanceof Error ? streamErr : new Error(String(streamErr));
      callbacks.onError?.(err);
      throw err;
    }

    return accumulatedText;
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
