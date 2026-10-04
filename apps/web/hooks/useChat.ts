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
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const sendMessage = useCallback(async (queryText: string) => {
    const trimmed = queryText.trim();
    if (!trimmed || isLoading) return;

    setError(null);
    const timestamp = new Date();

    // Create user message
    const userMessage: ChatMessage = {
      id: `user-${Date.now()}`,
      role: "user",
      content: trimmed,
      timestamp,
      status: "success",
    };

    // Create temporary loading assistant message
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

    try {
      const response = await chatService.askRAG(trimmed);

      setMessages((prev) =>
        prev.map((msg) =>
          msg.id === assistantMsgId
            ? {
                ...msg,
                content: response.answer,
                status: "success",
              }
            : msg
        )
      );
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
                content: "Rất tiếc, đã có lỗi xảy ra khi xử lý câu hỏi của bạn.",
                status: "error",
                errorMessage: errorMsg,
              }
            : msg
        )
      );
    } finally {
      setIsLoading(false);
    }
  }, [isLoading]);

  const retryMessage = useCallback(async (messageId: string) => {
    // Find failed assistant message index and preceding user message
    const targetIdx = messages.findIndex((m) => m.id === messageId);
    if (targetIdx <= 0) return;

    const precedingUserMsg = messages[targetIdx - 1];
    if (!precedingUserMsg || precedingUserMsg.role !== "user") return;

    // Reset status to sending
    setMessages((prev) =>
      prev.map((m) =>
        m.id === messageId ? { ...m, status: "sending", errorMessage: undefined } : m
      )
    );
    setIsLoading(true);
    setError(null);

    try {
      const response = await chatService.askRAG(precedingUserMsg.content);
      setMessages((prev) =>
        prev.map((m) =>
          m.id === messageId
            ? { ...m, content: response.answer, status: "success" }
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
  }, [messages]);

  const clearMessages = useCallback(() => {
    setMessages([
      {
        ...INITIAL_WELCOME_MESSAGE,
        timestamp: new Date(),
      },
    ]);
    setError(null);
  }, []);

  return {
    messages,
    isLoading,
    error,
    sendMessage,
    retryMessage,
    clearMessages,
  };
}
