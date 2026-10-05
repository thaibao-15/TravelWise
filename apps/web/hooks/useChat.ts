"use client";

import { useState, useCallback } from "react";
import { ChatMessage } from "@/types/chat";
import { chatService } from "@/services/chat.service";

const INITIAL_WELCOME_MESSAGE: ChatMessage = {
  id: "welcome-1",
  role: "assistant",
  content:
    "Xin chào! Tôi là **TravelWise AI**, trợ lý du lịch thông minh của bạn. 🌴✨\n\nHãy đặt câu hỏi về các địa điểm du lịch, khách sạn, ẩm thực hoặc nhờ tôi gợi ý lịch trình du lịch cho chuyến đi sắp tới của bạn nhé!",
  timestamp: new Date(),
  status: "success",
};

export function useChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([INITIAL_WELCOME_MESSAGE]);
  const [conversationId, setConversationId] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const sendMessage = useCallback(
    async (queryText: string, mode: "chat" | "voice" = "chat") => {
      const trimmed = queryText.trim();
      if (!trimmed || isLoading) return;

      setError(null);
      const timestamp = new Date();

      // Tạo tin nhắn người dùng
      const userMessage: ChatMessage = {
        id: `user-${Date.now()}`,
        role: "user",
        content: trimmed,
        timestamp,
        status: "success",
      };

      // Tạo tin nhắn đang xử lý của assistant
      const assistantMsgId = `assistant-${Date.now()}`;
      const loadingAssistantMessage: ChatMessage = {
        id: assistantMsgId,
        role: "assistant",
        content: "",
        timestamp: new Date(),
        status: "sending",
      };

      setMessages((prev) => [...prev, userMessage, loadingAssistantMessage]);
      setIsLoading(true);

      let currentStreamContent = "";

      try {
        // Ưu tiên truyền phát dữ liệu thời gian thực (Streaming)
        const finalAnswer = await chatService.askStream(
          trimmed,
          conversationId,
          mode,
          {
            onInit: (convId) => {
              setConversationId(convId);
            },
            onToken: (token) => {
              currentStreamContent += token;
              setMessages((prev) =>
                prev.map((msg) =>
                  msg.id === assistantMsgId
                    ? { ...msg, content: currentStreamContent }
                    : msg
                )
              );
            },
            onDone: (data) => {
              if (data.conversation_id) {
                setConversationId(data.conversation_id);
              }
              setMessages((prev) =>
                prev.map((msg) =>
                  msg.id === assistantMsgId
                    ? {
                        ...msg,
                        id: `msg-${data.message_id}`,
                        content: data.content,
                        status: "success",
                      }
                    : msg
                )
              );
            },
          }
        );

        return finalAnswer;
      } catch (streamErr) {
        console.warn("Stream API error, falling back to standard askAI:", streamErr);

        try {
          // Fallback sang endpoint đồng bộ nếu streaming bị lỗi mạng
          const response = await chatService.askAI(trimmed, conversationId, mode);

          if (response.conversation_id) {
            setConversationId(response.conversation_id);
          }

          const answerContent =
            response.message?.content || response.answer || "";

          setMessages((prev) =>
            prev.map((msg) =>
              msg.id === assistantMsgId
                ? {
                    ...msg,
                    id: response.message
                      ? `msg-${response.message.id}`
                      : assistantMsgId,
                    content: answerContent,
                    timestamp: response.message
                      ? new Date(response.message.created_at)
                      : new Date(),
                    status: "success",
                  }
                : msg
            )
          );
          return answerContent;
        } catch (err: unknown) {
          const errorMsg =
            err instanceof Error
              ? err.message
              : "Đã xảy ra lỗi không xác định khi kết nối với AI.";

          setError(errorMsg);
          setMessages((prev) =>
            prev.map((msg) =>
              msg.id === assistantMsgId
                ? {
                    ...msg,
                    content:
                      "Rất tiếc, đã có lỗi xảy ra khi xử lý câu hỏi của bạn.",
                    status: "error",
                    errorMessage: errorMsg,
                  }
                : msg
            )
          );
          return null;
        }
      } finally {
        setIsLoading(false);
      }
    },
    [conversationId, isLoading]
  );

  const retryMessage = useCallback(
    async (messageId: string) => {
      const targetIdx = messages.findIndex((m) => m.id === messageId);
      if (targetIdx <= 0) return;

      const precedingUserMsg = messages[targetIdx - 1];
      if (!precedingUserMsg || precedingUserMsg.role !== "user") return;

      setMessages((prev) =>
        prev.map((m) =>
          m.id === messageId
            ? { ...m, status: "sending", errorMessage: undefined }
            : m
        )
      );
      setIsLoading(true);
      setError(null);

      try {
        const response = await chatService.askAI(
          precedingUserMsg.content,
          conversationId
        );

        if (response.conversation_id) {
          setConversationId(response.conversation_id);
        }

        const answerContent =
          response.message?.content || response.answer || "";

        setMessages((prev) =>
          prev.map((m) =>
            m.id === messageId
              ? {
                  ...m,
                  id: response.message
                    ? `msg-${response.message.id}`
                    : messageId,
                  content: answerContent,
                  timestamp: response.message
                    ? new Date(response.message.created_at)
                    : new Date(),
                  status: "success",
                }
              : m
          )
        );
      } catch (err: unknown) {
        const errorMsg =
          err instanceof Error ? err.message : "Thử lại thất bại.";
        setError(errorMsg);
        setMessages((prev) =>
          prev.map((m) =>
            m.id === messageId
              ? {
                  ...m,
                  status: "error",
                  errorMessage: errorMsg,
                }
              : m
          )
        );
      } finally {
        setIsLoading(false);
      }
    },
    [conversationId, messages]
  );

  const clearMessages = useCallback(() => {
    setMessages([
      {
        ...INITIAL_WELCOME_MESSAGE,
        timestamp: new Date(),
      },
    ]);
    setConversationId(null);
    setError(null);
  }, []);

  const loadConversation = useCallback(async (id: number) => {
    try {
      setIsLoading(true);
      setConversationId(id);
      const msgs = await chatService.getConversationMessages(id);
      if (msgs && msgs.length > 0) {
        const formatted: ChatMessage[] = msgs.map((m) => ({
          id: `msg-${m.id}`,
          role: m.sender.toUpperCase() === "USER" ? "user" : "assistant",
          content: m.content,
          timestamp: new Date(m.created_at),
          status: "success",
        }));
        setMessages(formatted);
      }
    } catch (err) {
      console.error("Failed to load conversation messages", err);
    } finally {
      setIsLoading(false);
    }
  }, []);

  return {
    messages,
    conversationId,
    isLoading,
    error,
    sendMessage,
    retryMessage,
    clearMessages,
    loadConversation,
  };
}
