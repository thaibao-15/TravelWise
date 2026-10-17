"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import {
  ChatMessage,
  ItineraryProposalData,
  GeneratedItineraryData,
} from "@/types/chat";
import { chatService } from "@/services/chat.service";
import { ttsService } from "@/services/tts.service";
import { isCreateItineraryCommand } from "@/lib/utils";

const INITIAL_WELCOME_MESSAGE: ChatMessage = {
  id: "welcome-1",
  role: "assistant",
  content:
    "Xin chào! Tôi là **TravelWise AI**, hướng dẫn viên du lịch đồng hành của bạn. 🌴✨\n\nHãy chia sẻ về điểm đến bạn muốn khám phá, thời gian hoặc sở thích ẩm thực/trải nghiệm, tôi sẽ tư vấn và đồng hành lên lịch trình tối ưu nhất cho bạn nhé!",
  timestamp: new Date(),
  status: "success",
};

// Tiền xử lý chuẩn hóa chuỗi đầu vào (loại bỏ emoji, dấu câu thừa, chuẩn hóa khoảng trắng)
function cleanPromptText(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFC")
    .replace(/[.,?!:;~^`'"()[\]{}]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// Mẫu câu nhận diện ý định đồng ý tạo lịch trình từ giọng nói hoặc văn bản (hỗ trợ kính ngữ, từ lóng, teencode, tiếng Anh)
const AFFIRMATIVE_INTENT_REGEX =
  /(?:^|\b)(?:dạ\s+)?(?:có|tạo\s*đi|tạo\s*cho\s*mình|tạo\s*giúp|tạo\s*hộ|tạo\s*luôn|tạo\s*ngay|tạo\s*lịch(?:\s*trình)?(?:\s*đi|\s*luôn|\s*ngay|\s*nha|\s*nhé|\s*cho\s*mình|\s*giúp)?|đồng\s*ý|nhất\s*trí|chốt(?:\s*đơn|\s*nha|\s*nhé|\s*luôn)?|triển(?:\s*thôi|\s*đi|\s*luôn)?|duyệt(?:\s*luôn|\s*nha)?|lên\s*lịch(?:\s*đi|\s*trình|\s*kế\s*hoạch)?|làm\s*đi|làm\s*luôn|ok|okie|oke|uki|yes|yep|sure|let's\s*go|tiến\s*hành\s*đi|chuẩn\s*rồi|được\s*đấy|được\s*nha|ừ(?:\s*tạo\s*đi)?)\b/i;



function normalizeItineraryData(
  raw: any,
  fallbackDest: string,
  fallbackDays: number,
  fallbackTripId?: number | null
): GeneratedItineraryData {
  if (!raw) {
    return {
      trip_id: fallbackTripId || 1,
      name: `Chuyến đi ${fallbackDest}`,
      destination: fallbackDest,
      destination_city: fallbackDest,
      duration_days: fallbackDays,
      days: [],
    };
  }

  const payload = raw.itinerary || raw;
  const tripId = payload.trip_id || raw.trip_id || fallbackTripId || Date.now() % 10000;
  const dest = payload.destination_city || payload.destination || fallbackDest;
  const duration = payload.duration_days || payload.days?.length || fallbackDays;

  return {
    trip_id: tripId,
    name: payload.title || payload.name || `Khám phá ${dest} ${duration} ngày`,
    destination: dest,
    destination_city: dest,
    duration_days: duration,
    total_activities:
      payload.total_activities ||
      (payload.days?.reduce((acc: number, d: any) => acc + (d.activities?.length || 0), 0)) ||
      duration * 3,
    estimated_total_cost:
      payload.estimated_total_cost || payload.budget?.estimated_total || null,
    currency: payload.currency || "VND",
    days: (payload.days || []).map((d: any, idx: number) => ({
      day_number: d.day_number || idx + 1,
      title: d.title || `Ngày ${d.day_number || idx + 1}: Trải nghiệm khám phá ${dest}`,
      description: d.description || d.theme || null,
      activities: (d.activities || []).map((a: any, actIdx: number) => ({
        id: a.id || actIdx + 1,
        order_index: a.order_index || actIdx + 1,
        activity_type: a.activity_type || "VISIT",
        title: a.title || a.place?.name || `Điểm tham quan ${actIdx + 1}`,
        description: a.description || a.note || null,
        start_time: a.start_time || null,
        end_time: a.end_time || null,
        duration_minutes: a.duration_minutes || null,
        estimated_cost: a.estimated_cost || null,
        place: a.place
          ? {
            name: a.place.name,
            address: a.place.address || null,
            category: a.place.category || null,
          }
          : {
            name: a.title,
            address: dest,
          },
      })),
    })),
  };
}

export function useChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([INITIAL_WELCOME_MESSAGE]);
  const [conversationId, setConversationId] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Ngữ cảnh lập kế hoạch & Lịch trình đã tạo
  const [planningContext, setPlanningContext] = useState<any | null>(null);
  const [currentTripId, setCurrentTripId] = useState<number | null>(null);
  const [currentItinerary, setCurrentItinerary] = useState<GeneratedItineraryData | null>(null);
  const [isPlanning, setIsPlanning] = useState<boolean>(false);

  const planningContextRef = useRef<any | null>(null);
  planningContextRef.current = planningContext;

  const currentTripIdRef = useRef<number | null>(null);
  currentTripIdRef.current = currentTripId;

  const currentItineraryRef = useRef<GeneratedItineraryData | null>(null);
  currentItineraryRef.current = currentItinerary;

  // Tự động đồng bộ conversationId vào URL và localStorage để reload trang giữ nguyên phòng chat
  useEffect(() => {
    if (conversationId && typeof window !== "undefined") {
      try {
        localStorage.setItem("travelwise_conversation_id", String(conversationId));
        const currentUrl = new URL(window.location.href);
        if (currentUrl.searchParams.get("conversation_id") !== String(conversationId)) {
          currentUrl.searchParams.set("conversation_id", String(conversationId));
          window.history.replaceState(null, "", currentUrl.toString());
        }
      } catch (e) {
        console.warn("Could not sync conversation_id to storage/URL:", e);
      }
    }
  }, [conversationId]);

  /**
   * Helper: Trích xuất Proposal Data từ TripPlanningContext
   */
  const extractProposal = useCallback(
    (ctx: any): ItineraryProposalData | undefined => {
      if (!ctx || !ctx.trip) return undefined;
      const dest =
        ctx.trip.destination?.city ||
        ctx.trip.destination?.country ||
        ctx.destination;
      if (!dest) return undefined;

      // Chỉ tạo proposal khi người dùng đã có điểm đến (Số ngày nếu chưa có sẽ mặc định 3 ngày)
      const explicitDays =
        ctx.trip.duration?.days ||
        ctx.trip.dates?.duration_days ||
        ctx.duration_days;

      const isReady =
        ctx.planning_state?.is_ready_to_generate !== undefined
          ? ctx.planning_state.is_ready_to_generate
          : Boolean(explicitDays || dest);

      if (!isReady && !explicitDays && !dest) {
        return undefined;
      }

      const days = explicitDays || 3;

      return {
        destination: dest,
        durationDays: days,
        budget:
          ctx.trip.budget?.level ||
          (ctx.trip.budget?.total_amount ? `${ctx.trip.budget.total_amount} đ` : undefined),
        companions:
          ctx.trip.travelers?.composition ||
          (ctx.trip.travelers?.adults
            ? `${ctx.trip.travelers.adults} người`
            : ctx.trip.travelers?.total
              ? `${ctx.trip.travelers.total} người`
              : undefined),
        interests: ctx.preferences?.interests || ctx.trip.preferences?.interests || [],
        tripId: ctx.trip.trip_id,
      };
    },
    []
  );

  /**
   * Tự động sinh lịch trình từ đề xuất (Gọi FastAPI Itinerary Generation)
   */
  const generateFromProposal = useCallback(
    async (
      proposalOrPrompt?: ItineraryProposalData | string,
      customPrompt?: string
    ): Promise<string | null> => {
      let proposal: ItineraryProposalData | undefined;
      let prompt: string | undefined = customPrompt;
      if (typeof proposalOrPrompt === "string") {
        prompt = proposalOrPrompt;
        proposal = undefined;
      } else if (proposalOrPrompt) {
        proposal = proposalOrPrompt;
      }

      const targetProposal =
        proposal || extractProposal(planningContextRef.current);

      const tripId =
        targetProposal?.tripId ||
        currentTripIdRef.current ||
        planningContextRef.current?.trip?.trip_id;

      const destName = targetProposal?.destination || "chuyến đi";
      const daysCount = targetProposal?.durationDays || 3;

      setIsPlanning(true);
      setError(null);

      const statusMsgId = `planning-status-${Date.now()}`;

      // Thêm tin nhắn thông báo AI đang thiết kế lịch trình
      setMessages((prev) => [
        ...prev,
        {
          id: statusMsgId,
          role: "assistant",
          content: `AI đang thiết kế và tối ưu lịch trình du lịch cho chuyến đi **${destName} ${daysCount} ngày**... 🗺️✨`,
          timestamp: new Date(),
          status: "sending",
        },
      ]);

      try {
        let finalItineraryData: GeneratedItineraryData | null = null;

        const effectiveContext = planningContextRef.current || {
          trip: {
            destination: { city: destName, country: "Việt Nam" },
            dates: { duration_days: daysCount },
            preferences: { interests: targetProposal?.interests || [] },
          },
        };
        if (effectiveContext.trip) {
          if (!effectiveContext.trip.destination) {
            effectiveContext.trip.destination = { city: destName, country: "Việt Nam" };
          } else if (!effectiveContext.trip.destination.city) {
            effectiveContext.trip.destination.city = destName;
          }
          if (!effectiveContext.trip.dates) {
            effectiveContext.trip.dates = { duration_days: daysCount };
          } else if (!effectiveContext.trip.dates.duration_days) {
            effectiveContext.trip.dates.duration_days = daysCount;
          }
        }

        let genErr: Error | null = null;

        if (tripId) {
          try {
            const genRes = await chatService.generateItinerary(tripId, {
              save_to_db: true,
              context: effectiveContext,
              user_prompt: prompt,
            });
            if (genRes) {
              finalItineraryData = normalizeItineraryData(genRes, destName, daysCount, tripId);
            }
          } catch (apiErr: unknown) {
            console.warn("Generate itinerary API error:", apiErr);
            genErr = apiErr instanceof Error ? apiErr : new Error(String(apiErr));
          }
        } else {
          try {
            const genRes = await chatService.generateItineraryDirect({
              context: effectiveContext,
              conversation_id: conversationId,
              save_to_db: true,
              user_prompt: prompt,
            });
            if (genRes) {
              const resTripId = genRes.trip_id || tripId;
              finalItineraryData = normalizeItineraryData(genRes, destName, daysCount, resTripId);
              if (resTripId) {
                setCurrentTripId(resTripId);
              }
            }
          } catch (directErr: unknown) {
            console.warn("Generate itinerary direct API error:", directErr);
            genErr = directErr instanceof Error ? directErr : new Error(String(directErr));
          }
        }

        // Bắt buộc dữ liệu phải được sinh thành công từ Backend AI
        if (!finalItineraryData || !finalItineraryData.days || finalItineraryData.days.length === 0) {
          throw new Error(
            genErr?.message ||
            `Hệ thống chưa thể lấy dữ liệu địa điểm và tạo lịch trình cho ${destName}. Vui lòng thử lại sau giây lát.`
          );
        }

        setCurrentItinerary(finalItineraryData);
        if (tripId) setCurrentTripId(tripId);

        const speechSummary = `Mình đã hoàn thành lịch trình ${destName} ${daysCount} ngày cho bạn rồi nhé! Bạn có thể xem chi tiết từng ngày và các địa điểm ngay trên bảng bên phải.`;

        // Cập nhật tin nhắn thành công kèm thẻ Itinerary Card
        setMessages((prev) =>
          prev.map((msg) =>
            msg.id === statusMsgId
              ? {
                ...msg,
                content: `🎉 ${speechSummary}`,
                status: "success",
                itinerary: finalItineraryData!,
              }
              : msg
          )
        );

        return speechSummary;
      } catch (err: unknown) {
        const errorMsg =
          err instanceof Error
            ? err.message
            : "Chưa thể tạo lịch trình lúc này. Vui lòng thử lại.";
        setError(errorMsg);
        setMessages((prev) =>
          prev.map((msg) =>
            msg.id === statusMsgId
              ? {
                ...msg,
                content: `Lỗi khi tạo lịch trình: ${errorMsg}`,
                status: "error",
                errorMessage: errorMsg,
              }
              : msg
          )
        );
        return null;
      } finally {
        setIsPlanning(false);
      }
    },
    [extractProposal]
  );

  /**
   * Gửi tin nhắn (Văn bản hoặc Giọng nói STT)
   */
  const sendMessage = useCallback(
    async (
      queryText: string,
      mode: "chat" | "voice" = "chat",
      onSentence?: (sentence: string) => void
    ): Promise<string | null | void> => {
      const trimmed = queryText.trim();
      if (!trimmed || isLoading || isPlanning) return;

      setError(null);
      const timestamp = new Date();

      // Kiểm tra ý định tạo lịch trình (VD: "Có", "Tạo đi", "Đồng ý", "Ok", "Tạo lịch trình")
      const ctx = planningContextRef.current;
      const hasDestination = Boolean(
        ctx?.trip?.destination?.city ||
        ctx?.trip?.destination?.country ||
        ctx?.destination
      );
      const hasDuration = Boolean(
        ctx?.trip?.dates?.duration_days ||
        ctx?.trip?.dates?.start_date ||
        ctx?.trip?.duration?.days ||
        ctx?.duration_days
      );
      const isReadyToGenerate = Boolean(
        ctx?.planning_state?.is_ready_to_generate ?? (hasDestination && hasDuration)
      );

      const hasExplicitProposalCard = messages.some((m) => m.proposal && !m.itinerary);
      const hasPendingProposal = hasExplicitProposalCard || hasDestination;

      const isCreateCommand = isCreateItineraryCommand(trimmed);
      const isAffirmative =
        isCreateCommand ||
        AFFIRMATIVE_INTENT_REGEX.test(trimmed) ||
        /(?:tạo|lên|lập)\s*(?:cho\s*[\w\s]+\s+)?(?:lịch\s*trình|kế\s*hoạch|lịch|tour)?\s*(?:đi|luôn|ngay|nha|nhé|giúp|hộ)/i.test(trimmed) ||
        (trimmed.length <= 30 && /^(dạ\s+)?(có|tạo|ok|được|làm|yes|đồng ý|nhất trí|chốt|triển|hãy tạo|cứ tạo)/i.test(trimmed));

      // 1. Kiểm tra ý định XÓA / HỦY LỊCH TRÌNH
      const isClearItineraryIntent =
        /(?:xóa|xoá|hủy|bỏ|reset|clear)\s+(?:lịch\s*trình|kế\s*hoạch)(?:\s+(?:này|hiện\s*tại|đi|giúp\s*mình|hộ\s*mình))?/i.test(trimmed) &&
        !/(?:thêm|sửa|đổi|ngày\s*\d)/i.test(trimmed);

      if (isClearItineraryIntent) {
        const userMsg: ChatMessage = {
          id: `user-${Date.now()}`,
          role: "user",
          content: trimmed,
          timestamp,
          status: "success",
        };
        setMessages((prev) => [...prev, userMsg]);

        const hadItin = Boolean(currentItineraryRef.current);
        setCurrentItinerary(null);
        currentItineraryRef.current = null;

        const replyContent = hadItin
          ? "Mình đã xóa lịch trình hiện tại cho bạn rồi nhé! 🗑️✨ Bây giờ bạn có thể chia sẻ điểm đến, số ngày hoặc yêu cầu mới để mình lên lại lịch trình khác cho bạn nhé!"
          : "Hiện tại chưa có lịch trình nào đang mở để xóa bạn nhé! Bạn có thể chia sẻ điểm đến hoặc yêu cầu để mình tạo lịch trình mới ngay.";

        setMessages((prev) => [
          ...prev,
          {
            id: `assistant-${Date.now()}`,
            role: "assistant",
            content: replyContent,
            timestamp: new Date(),
            status: "success",
          },
        ]);
        return replyContent;
      }

      // 2. Kiểm tra ý định TẠO LẠI LỊCH TRÌNH KHÁC
      const isRegenerateIntent =
        /(?:tạo\s*lại|làm\s*lại|lên\s*lại|thiết\s*kế\s*lại)\s+(?:lịch\s*trình|kế\s*hoạch)(?:\s+(?:khác|mới|đi|cho\s*mình|giúp\s*mình))?/i.test(trimmed) ||
        /(?:tạo|lên|làm)\s+(?:lịch\s*trình|kế\s*hoạch)\s+khác/i.test(trimmed);

      if (isRegenerateIntent) {
        // Xóa lịch trình cũ trước để cho phép tạo mới
        setCurrentItinerary(null);
        currentItineraryRef.current = null;

        const hasSpecificNewInfo = /(?:đi\s+[a-zà-ỹ]+|\d+\s*ngày)/i.test(trimmed);

        if (!hasSpecificNewInfo && hasDestination) {
          // Người dùng yêu cầu tạo lại lịch trình khác với điểm đến hiện tại:
          const userMsg: ChatMessage = {
            id: `user-${Date.now()}`,
            role: "user",
            content: trimmed,
            timestamp,
            status: "success",
          };
          setMessages((prev) => [...prev, userMsg]);
          return await generateFromProposal(undefined, "Tạo lại lịch trình khác với các địa điểm và hoạt động mới mẻ hơn");
        }
      }

      // Tự động kích hoạt tạo lịch trình khi:
      // 1. Đã có Proposal Card rõ ràng được hiển thị, HOẶC
      // 2. Ngữ cảnh đã có điểm đến và người dùng đồng ý / yêu cầu tạo lịch trình (isAffirmative / isCreateCommand)
      if (
        (hasExplicitProposalCard || (hasDestination && (hasDuration || isReadyToGenerate || isCreateCommand))) &&
        isAffirmative
      ) {
        // Nếu đã có lịch trình cũ hiển thị, xóa đi trước để tạo mới
        if (currentItineraryRef.current) {
          setCurrentItinerary(null);
          currentItineraryRef.current = null;
        }

        // 1. Thêm câu người dùng nói vào khung chat
        const userMsg: ChatMessage = {
          id: `user-${Date.now()}`,
          role: "user",
          content: trimmed,
          timestamp,
          status: "success",
        };
        setMessages((prev) => [...prev, userMsg]);

        // 2. Tự động kích hoạt tạo lịch trình ngay lập tức
        return await generateFromProposal(undefined, trimmed);
      }

      // Tạo tin nhắn người dùng bình thường
      const userMessage: ChatMessage = {
        id: `user-${Date.now()}`,
        role: "user",
        content: trimmed,
        timestamp,
        status: "success",
      };

      // 3. Tự động xác định ý định chỉnh sửa lịch trình qua LLM & RAG (thay thế Regex cũ)
      const activeItin = currentItineraryRef.current;
      const activeTripId = currentTripIdRef.current || activeItin?.trip_id;

      if (activeTripId) {
        try {
          const intentRes = await chatService.detectEditIntent(
            activeTripId,
            trimmed,
            conversationId
          );

          if (intentRes && intentRes.is_edit_intent) {
            const editAssistantMsgId = `assistant-${Date.now()}`;
            setMessages((prev) => [
              ...prev,
              userMessage,
              {
                id: editAssistantMsgId,
                role: "assistant",
                content: "✨ Đang yêu cầu AI tối ưu và cập nhật lại lịch trình cho bạn...",
                timestamp: new Date(),
                status: "sending",
                itinerary: activeItin || undefined,
              },
            ]);
            setIsPlanning(true);

            try {
              const changePrompt = intentRes.change_prompt || trimmed;
              const serverRes = await chatService.editItinerary(activeTripId, changePrompt);

              if (serverRes && (serverRes.itinerary || serverRes.status === "EDITED")) {
                const normalized = normalizeItineraryData(
                  serverRes.itinerary || serverRes,
                  activeItin?.destination || "chuyến đi",
                  activeItin?.duration_days || 3,
                  activeTripId
                );
                if (normalized && normalized.days && normalized.days.length > 0) {
                  setCurrentItinerary(normalized);
                  const finalMsg = serverRes.message || "Đã cập nhật lịch trình thành công!";
                  setMessages((prev) =>
                    prev.map((m) =>
                      m.id === editAssistantMsgId
                        ? {
                            ...m,
                            content: finalMsg,
                            status: "success",
                            itinerary: normalized,
                          }
                        : m
                    )
                  );
                  return finalMsg;
                }
              } else if (serverRes && serverRes.status === "ANSWERED") {
                // LLM & RAG nhận định đây là câu hỏi tham khảo và trả lời trực tiếp
                const finalMsg = serverRes.message;
                setMessages((prev) =>
                  prev.map((m) =>
                    m.id === editAssistantMsgId
                      ? {
                          ...m,
                          content: finalMsg,
                          status: "success",
                          itinerary: activeItin || undefined,
                        }
                      : m
                  )
                );
                return finalMsg;
              }
            } catch (editErr) {
              console.warn("Backend edit execution failed:", editErr);
            } finally {
              setIsPlanning(false);
            }
          }
        } catch (detectErr) {
          console.warn("Detect edit intent error, fallback to normal chat:", detectErr);
        }
      }

      // Tạo placeholder đang suy nghĩ của AI
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
        let sentenceBuffer = "";

        // Ưu tiên truyền phát dữ liệu thời gian thực (SSE Streaming)
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

              // Trong chế độ voice: đẩy từng câu vào hàng đợi phát NGAY KHI CÂU ĐÓ KẾT THÚC
              if (mode === "voice" && onSentence) {
                sentenceBuffer += token;
                const match = sentenceBuffer.match(/^(.*?[\.\!\?\n])(\s+|$)/);
                // Ngưỡng 6 ký tự giúp các câu chào ngắn ("Chào bạn!", "Dạ được chứ!") được phát ngay
                if (match && match[1].trim().length >= 6) {
                  onSentence(match[1].trim());
                  sentenceBuffer = sentenceBuffer.slice(match[0].length);
                }
              }
            },
            onDone: (data: any) => {
              if (mode === "voice" && onSentence && sentenceBuffer.trim()) {
                onSentence(sentenceBuffer.trim());
                sentenceBuffer = "";
              }

              if (data.conversation_id) {
                setConversationId(data.conversation_id);
              }

              if (data.itinerary) {
                const normalized = normalizeItineraryData(
                  data.itinerary,
                  data.itinerary.destination_city || data.itinerary.destination || "chuyến đi",
                  data.itinerary.duration_days || 3,
                  data.itinerary.trip_id || currentTripIdRef.current
                );
                if (normalized && normalized.days && normalized.days.length > 0) {
                  setCurrentItinerary(normalized);
                }
              }

              let proposal: ItineraryProposalData | undefined;
              if (data.planning_context) {
                setPlanningContext(data.planning_context);
                if (data.planning_context.trip?.trip_id) {
                  setCurrentTripId(data.planning_context.trip.trip_id);
                }
                if (!currentItineraryRef.current) {
                  proposal = extractProposal(data.planning_context);
                }
              }

              setMessages((prev) =>
                prev.map((msg) =>
                  msg.id === assistantMsgId
                    ? {
                      ...msg,
                      id: `msg-${data.message_id}`,
                      content: data.content,
                      status: "success",
                      proposal,
                    }
                    : msg
                )
              );
            },
          }
        );

        return finalAnswer;
      } catch (streamErr) {
        console.warn("Stream API error, falling back to askAI:", streamErr);

        try {
          const response = await chatService.askAI(trimmed, conversationId, mode);

          if (response.conversation_id) {
            setConversationId(response.conversation_id);
          }

          let proposal: ItineraryProposalData | undefined;
          if (response.planning_context) {
            setPlanningContext(response.planning_context);
            if (response.planning_context.trip?.trip_id) {
              setCurrentTripId(response.planning_context.trip.trip_id);
            }
            if (!currentItineraryRef.current) {
              proposal = extractProposal(response.planning_context);
            }
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
                  proposal,
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
                  content: "Rất tiếc, đã có lỗi xảy ra khi xử lý câu hỏi của bạn.",
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
    [
      conversationId,
      isLoading,
      isPlanning,
      messages,
      generateFromProposal,
      extractProposal,
    ]
  );

  /**
   * Chỉnh sửa lịch trình bằng ngôn ngữ tự nhiên
   */
  const editFromChat = useCallback(
    async (changePrompt: string) => {
      return sendMessage(changePrompt);
    },
    [sendMessage]
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
    setPlanningContext(null);
    setCurrentTripId(null);
    setCurrentItinerary(null);
    setError(null);
    if (typeof window !== "undefined") {
      try {
        localStorage.removeItem("travelwise_conversation_id");
        const currentUrl = new URL(window.location.href);
        currentUrl.searchParams.delete("conversation_id");
        window.history.replaceState(null, "", currentUrl.toString());
      } catch {
        // Fallback
      }
    }
  }, []);

  /**
   * Xóa lịch trình hiện tại (giữ nguyên lịch sử trò chuyện)
   */
  const clearItinerary = useCallback((addChatMessage = true): boolean => {
    const hadItin = Boolean(currentItineraryRef.current);
    setCurrentItinerary(null);
    currentItineraryRef.current = null;

    if (addChatMessage && hadItin) {
      setMessages((prev) => [
        ...prev,
        {
          id: `assistant-${Date.now()}`,
          role: "assistant",
          content: "Mình đã xóa lịch trình hiện tại cho bạn rồi nhé! 🗑️✨ Bây giờ bạn có thể chia sẻ điểm đến, thời gian hoặc yêu cầu mới để mình tạo lại một lịch trình khác cho bạn bất cứ lúc nào.",
          timestamp: new Date(),
          status: "success",
        },
      ]);
    }
    return hadItin;
  }, []);

  /**
   * Tạo lại lịch trình khác (làm mới và sinh lại lịch trình mới)
   */
  const regenerateItinerary = useCallback(
    async (customPrompt?: string): Promise<string | null> => {
      setCurrentItinerary(null);
      currentItineraryRef.current = null;
      const promptText = customPrompt || "Tạo lại lịch trình khác với các gợi ý mới mẻ và tối ưu hơn";
      return await generateFromProposal(undefined, promptText);
    },
    [generateFromProposal]
  );

  const loadConversation = useCallback(async (id: number) => {
    try {
      setIsLoading(true);
      setConversationId(id);
      const [msgs, ctx] = await Promise.allSettled([
        chatService.getConversationMessages(id),
        chatService.getPlanningContext(id),
      ]);

      if (msgs.status === "fulfilled" && msgs.value && msgs.value.length > 0) {
        const formatted: ChatMessage[] = msgs.value.map((m) => ({
          id: `msg-${m.id}`,
          role: m.sender.toUpperCase() === "USER" ? "user" : "assistant",
          content: m.content,
          timestamp: new Date(m.created_at),
          status: "success",
        }));
        setMessages(formatted);
      }

      if (ctx.status === "fulfilled" && ctx.value) {
        setPlanningContext(ctx.value);
        const tId = ctx.value.trip?.trip_id;
        if (tId) {
          setCurrentTripId(tId);
          try {
            const itinRes = await chatService.getTripItinerary(tId);
            if (itinRes) {
              const norm = normalizeItineraryData(itinRes, "chuyến đi", 3, tId);
              if (norm) {
                setCurrentItinerary(norm);
              }
            }
          } catch (itinErr) {
            console.warn("Could not preload itinerary for trip", tId, itinErr);
          }
        }
      }
    } catch (err) {
      console.error("Failed to load conversation", err);
    } finally {
      setIsLoading(false);
    }
  }, []);

  return {
    messages,
    conversationId,
    isLoading,
    isPlanning,
    error,
    planningContext,
    currentTripId,
    currentItinerary,
    sendMessage,
    retryMessage,
    clearMessages,
    clearItinerary,
    regenerateItinerary,
    loadConversation,
    generateFromProposal,
    editFromChat,
  };
}
