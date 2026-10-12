"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import {
  ChatMessage,
  ItineraryProposalData,
  GeneratedItineraryData,
} from "@/types/chat";
import { chatService } from "@/services/chat.service";

const INITIAL_WELCOME_MESSAGE: ChatMessage = {
  id: "welcome-1",
  role: "assistant",
  content:
    "Xin chào! Tôi là **TravelWise AI**, hướng dẫn viên du lịch đồng hành của bạn. 🌴✨\n\nHãy chia sẻ về điểm đến bạn muốn khám phá, thời gian hoặc sở thích ẩm thực/trải nghiệm, tôi sẽ tư vấn và đồng hành lên lịch trình tối ưu nhất cho bạn nhé!",
  timestamp: new Date(),
  status: "success",
};

// Mẫu câu nhận diện ý định đồng ý tạo lịch trình từ giọng nói hoặc văn bản
const AFFIRMATIVE_INTENT_REGEX =
  /^(có|tạo đi|tạo cho mình|đồng ý|ok|ừ|dạ có|lên lịch trình|yes|chốt|làm đi|lên kế hoạch đi|tạo luôn đi|tạo ngay đi|được đấy|tạo đi bạn|lên lịch đi|ừ tạo đi|nhờ bạn tạo|hãy tạo lịch trình|tạo giùm mình|tạo hộ mình)/i;

/**
 * Nhận diện chính xác câu lệnh chỉnh sửa lịch trình hiện có.
 * Loại trừ triệt để câu hỏi hướng dẫn viên, câu hỏi FAQ du lịch và yêu cầu tạo lại từ đầu.
 */
function isItineraryEditIntent(prompt: string): boolean {
  const lower = prompt.toLowerCase().trim();
  if (!lower) return false;

  // 1. Phủ định: Câu hỏi về danh tính, vai trò của hướng dẫn viên
  if (
    /hướng dẫn viên|bạn là ai|giới thiệu bản thân|bạn có thể làm gì|bạn tên gì|vai trò của bạn/i.test(lower)
  ) {
    return false;
  }

  // 2. Phủ định: Yêu cầu tạo lại từ đầu / làm lại mới toàn bộ
  if (
    /(tạo lại|làm lại|lên lại|thiết kế lại|lập lại|tạo mới|lên mới|xóa hết làm lại|chuyến đi mới|reset)/i.test(lower)
  ) {
    return false;
  }

  // 3. Phủ định: Các câu hỏi tham khảo thông tin địa danh, hỏi giờ mở cửa, giá vé, hỏi quán ăn chung
  const isGeneralQuery =
    /(mấy giờ (mở|đóng)|(mở|đóng) cửa lúc mấy giờ|vé bao nhiêu|giá vé|giá bao nhiêu|bao nhiêu tiền|ở đâu|cách bao xa|đi thế nào|đi bằng gì|có gì (ngon|chơi|đẹp|đặc sắc)|quán nào|chỗ nào|nơi nào|thời tiết|kinh nghiệm)\b/i.test(lower) ||
    (/^(cho mình hỏi|hỏi xíu|hỏi chút|bạn ơi)/i.test(lower) && !/(đổi|thêm|bớt|xóa|dời)/i.test(lower));

  if (isGeneralQuery) {
    return false;
  }

  // 4. Khẳng định: Các mẫu câu lệnh chỉnh sửa lịch trình rõ ràng
  // 4a. Thay đổi giờ giấc: "bắt đầu lúc 9h", "dời sang 10h", "lùi 1 tiếng", "sớm hơn", "muộn hơn"
  const hasTimeAdjustment =
    /(?:bắt đầu|khởi hành|xuất phát|dời|lùi|chuyển|đổi|sang)\s*(?:lúc|sang|vào|từ)?\s*\d{1,2}(?:h|:|\s*giờ)/i.test(lower) ||
    /(?:sớm hơn|muộn hơn|trễ hơn|nhanh hơn|chậm hơn)\s*\d+/i.test(lower) ||
    /(?:cho|để)\s+lịch\s+(?:bắt đầu|khởi hành)\s+lúc/i.test(lower);

  // 4b. Thêm / Bớt / Xóa / Hoán đổi hoạt động hoặc địa điểm cụ thể
  const hasActionWithTarget =
    /(?:thêm|bổ sung|bớt|bỏ|xoá|xóa|thay thế|hoán đổi|đổi|chuyển)\s+(?:vào\s+ngày\s*\d|khỏi\s+lịch|ngày\s*\d|hoạt động|địa điểm|quán|biển|cafe|khách sạn|resort)/i.test(lower) ||
    /(?:bỏ|xóa|xoá)\s+[a-zà-ỹ0-9\s]+(?:đi|khỏi lịch|ra)/i.test(lower) ||
    /(?:thêm|ghé thêm)\s+[a-zà-ỹ0-9\s]+(?:vào ngày|vào buổi|vào lịch)/i.test(lower);

  // 4c. Chỉnh sửa ngày cụ thể: "ngày 1 đổi sang...", "sửa ngày 2..."
  const hasDayEdit =
    /ngày\s*\d\s*(?:thay|đổi|sửa|chỉnh|thêm|bớt|bỏ|xoá|xóa|dời|chuyển)/i.test(lower) ||
    /(?:sửa|đổi|chỉnh|cập nhật)\s+ngày\s*\d/i.test(lower);

  return Boolean(hasTimeAdjustment || hasActionWithTarget || hasDayEdit);
}

function applyItineraryEdit(
  current: GeneratedItineraryData,
  prompt: string
): { itinerary: GeneratedItineraryData; summary: string } {
  const updatedDays = current.days ? JSON.parse(JSON.stringify(current.days)) : [];
  const lower = prompt.toLowerCase();

  let targetDayIdx = -1;
  const dayMatch = lower.match(/ngày\s*(\d+)/);
  if (dayMatch && dayMatch[1]) {
    const num = parseInt(dayMatch[1], 10);
    if (num > 0 && num <= updatedDays.length) {
      targetDayIdx = num - 1;
    }
  }

  // 1. Kiểm tra yêu cầu dời giờ / bắt đầu lúc mấy giờ (VD: "cho lịch bắt đầu lúc 10h đi", "bắt đầu 9h")
  const timeMatch = lower.match(/(?:lúc|từ|bắt đầu lúc|sang|vào)?\s*(\d{1,2})(?:h|:(\d{2})|\s*giờ)/);
  if (
    timeMatch &&
    (lower.includes("bắt đầu") ||
      lower.includes("khởi hành") ||
      lower.includes("xuất phát") ||
      lower.includes("lịch") ||
      lower.includes("giờ") ||
      lower.includes("dời") ||
      lower.includes("lùi"))
  ) {
    const startHour = parseInt(timeMatch[1], 10);
    const startMin = timeMatch[2] ? parseInt(timeMatch[2], 10) : 0;
    if (startHour >= 5 && startHour <= 22) {
      const startStr = `${String(startHour).padStart(2, "0")}:${String(startMin).padStart(2, "0")}`;
      const daysToUpdate = targetDayIdx >= 0 ? [updatedDays[targetDayIdx]] : updatedDays;

      daysToUpdate.forEach((d: any) => {
        if (!d) return;
        d.description = `Lịch trình được tối ưu với giờ bắt đầu từ ${startStr} sáng.`;
        if (d.activities && d.activities.length > 0) {
          // Hoạt động 1: startStr -> +2h
          const h1End = Math.min(startHour + 2, 23);
          d.activities[0].start_time = startStr;
          d.activities[0].end_time = `${String(h1End).padStart(2, "0")}:${String(startMin).padStart(2, "0")}`;

          // Hoạt động 2: Ăn trưa / Giữa ngày
          if (d.activities.length > 1) {
            const h2Start = Math.min(Math.max(h1End, 12), 23);
            const h2End = Math.min(h2Start + 1, 23);
            const h2EndMin = (startMin + 30) % 60;
            d.activities[1].start_time = `${String(h2Start).padStart(2, "0")}:${String(startMin).padStart(2, "0")}`;
            d.activities[1].end_time = `${String(h2End).padStart(2, "0")}:${String(h2EndMin).padStart(2, "0")}`;
          }

          // Hoạt động 3: Buổi chiều
          if (d.activities.length > 2) {
            const h3Start = Math.min(startHour + 5, 17);
            const h3End = Math.min(h3Start + 2, 22);
            d.activities[2].start_time = `${String(h3Start).padStart(2, "0")}:${String(startMin).padStart(2, "0")}`;
            d.activities[2].end_time = `${String(h3End).padStart(2, "0")}:${String(startMin).padStart(2, "0")}`;
          }
        }
      });

      const dayNote = targetDayIdx >= 0 ? `cho Ngày ${targetDayIdx + 1}` : "cho toàn bộ chuyến đi";
      const summary = `Mình đã dời giờ bắt đầu lịch trình ${dayNote} sang **${startStr}** sáng cho bạn! Khung giờ của các hoạt động tiếp theo cũng đã được tự động tính toán lại thật hợp lý. Bạn kiểm tra lại ở bảng bên phải nhé! ⏰✨`;
      return {
        itinerary: { ...current, days: updatedDays },
        summary,
      };
    }
  }

  // 2. Chỉnh sửa theo địa điểm / sở thích (Biển, Ẩm thực, Cafe...)
  const activeIdx = targetDayIdx >= 0 ? targetDayIdx : updatedDays.length > 1 && (lower.includes("biển") || lower.includes("tắm")) ? 1 : 0;
  const targetDay = updatedDays[activeIdx];

  let summary = `Đã cập nhật lịch trình theo yêu cầu của bạn! 🗺️✨`;

  if (targetDay) {
    const newActivities = [...(targetDay.activities || [])];

    if (lower.includes("biển") || lower.includes("tắm")) {
      targetDay.title = `Ngày ${targetDay.day_number}: Trải nghiệm tắm biển & ngắm hoàng hôn`;
      targetDay.description = `Lịch trình được cập nhật ưu tiên hoạt động tắm biển và ngắm cảnh hoàng hôn.`;
      if (newActivities.length >= 3) {
        newActivities[2] = {
          ...newActivities[2],
          title: "Tắm biển & Dạo bờ biển ngắm hoàng hôn",
          place: {
            name: "Bãi biển Mỹ Khê / Bãi tắm du lịch",
            address: current.destination_city || current.destination || "Khu vực ven biển",
          },
          description: "Thư giãn, tắm biển và check-in ngắm hoàng hôn rực rỡ bên bờ biển.",
        };
      }
      summary = `Mình đã điều chỉnh lịch trình Ngày ${targetDay.day_number} ưu tiên tắm biển và ngắm hoàng hôn cho bạn rồi nhé! 🌊🏖️`;
    } else if (lower.includes("ẩm thực") || lower.includes("đặc sản") || lower.includes("ăn") || lower.includes("hải sản")) {
      targetDay.title = `Ngày ${targetDay.day_number}: Khám phá ẩm thực & văn hóa bản địa`;
      targetDay.description = `Lịch trình bổ sung trải nghiệm các món ăn đặc sản nổi tiếng địa phương.`;
      if (newActivities.length >= 2) {
        newActivities[1] = {
          ...newActivities[1],
          activity_type: "MEAL",
          title: "Thưởng thức hải sản tươi sống và ẩm thực đặc sản",
          place: {
            name: "Khu ẩm thực & Nhà hàng hải sản địa phương",
            address: current.destination_city || current.destination || "Trung tâm",
          },
          description: "Thưởng thức các món đặc sản trứ danh chế biến tươi ngon trong ngày.",
          estimated_cost: 250000,
        };
      }
      summary = `Mình đã thêm trải nghiệm ẩm thực đặc sản và hải sản tươi sống vào Ngày ${targetDay.day_number} cho bạn rồi nha! 🍜🦀`;
    } else if (lower.includes("cafe") || lower.includes("cà phê") || lower.includes("chill") || lower.includes("hoàng hôn")) {
      if (newActivities.length >= 3) {
        newActivities[2] = {
          ...newActivities[2],
          title: "Ghé quán cafe view đẹp ngắm hoàng hôn / phố đêm",
          place: {
            name: "Quán Cafe Sunset & Phố đêm",
            address: current.destination_city || current.destination || "Khu vực ngắm cảnh",
          },
          description: "Không gian thoáng đãng, thưởng thức đồ uống và tận hưởng không khí thư thái.",
          estimated_cost: 65000,
        };
      }
      summary = `Mình đã bổ sung quán cafe view đẹp ngắm hoàng hôn vào Ngày ${targetDay.day_number} cho bạn nhé! ☕🌇`;
    } else {
      targetDay.description = `Lịch trình đã được AI điều chỉnh theo yêu cầu: "${prompt}".`;
      if (newActivities.length > 0) {
        newActivities[newActivities.length - 1] = {
          ...newActivities[newActivities.length - 1],
          title: `Trải nghiệm theo yêu cầu: ${prompt.slice(0, 45)}`,
          description: `Hoạt động được điều chỉnh phù hợp với mong muốn của bạn.`,
        };
      }
      summary = `Mình đã cập nhật lịch trình Ngày ${targetDay.day_number} theo mong muốn "${prompt}" của bạn rồi nhé! ✨`;
    }

    targetDay.activities = newActivities;
    updatedDays[activeIdx] = targetDay;
  }

  return {
    itinerary: { ...current, days: updatedDays },
    summary,
  };
}

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

      // Chỉ tạo proposal khi người dùng đã cung cấp đủ thông tin cốt lõi (Điểm đến VÀ Thời gian/Số ngày)
      const explicitDays =
        ctx.trip.duration?.days ||
        ctx.trip.dates?.duration_days ||
        ctx.duration_days;

      const isReady =
        ctx.planning_state?.is_ready_to_generate !== undefined
          ? ctx.planning_state.is_ready_to_generate
          : Boolean(explicitDays);

      if (!isReady && !explicitDays) {
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
    async (queryText: string, mode: "chat" | "voice" = "chat"): Promise<string | null | void> => {
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

      const isAffirmative =
        AFFIRMATIVE_INTENT_REGEX.test(trimmed) ||
        (trimmed.length <= 15 && /^(có|tạo|ok|được|làm|yes|đồng ý)/i.test(trimmed));

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

      // CHỈ tự động kích hoạt tạo lịch trình khi:
      // 1. Đã có Proposal Card rõ ràng được hiển thị, HOẶC
      // 2. Ngữ cảnh đã đầy đủ thông tin cốt lõi (Điểm đến VÀ Thời gian/Số ngày)
      // Nếu CHƯA ĐỦ THÔNG TIN, câu hỏi sẽ được gửi bình thường tới AI để AI chủ động hỏi các trường còn thiếu!
      if ((hasExplicitProposalCard || (isReadyToGenerate && hasDestination && hasDuration)) && isAffirmative && !currentItineraryRef.current) {
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
        return await generateFromProposal();
      }

      // Tạo tin nhắn người dùng bình thường
      const userMessage: ChatMessage = {
        id: `user-${Date.now()}`,
        role: "user",
        content: trimmed,
        timestamp,
        status: "success",
      };

      // Kiểm tra ý định chỉnh sửa lịch trình
      const activeItin = currentItineraryRef.current;
      const activeTripId = currentTripIdRef.current || activeItin?.trip_id;
      const isEditRequest = isItineraryEditIntent(trimmed);

      // Trường hợp 1: Đã có lịch trình hiển thị -> Gọi backend AI cập nhật và tối ưu đồng thời hiển thị Optimistic UI
      if (activeItin && isEditRequest) {
        const editResult = applyItineraryEdit(activeItin, trimmed);
        const optimisticItinerary = editResult.itinerary;
        const optimisticSummary = editResult.summary;

        // Cập nhật optimistic ngay lập tức để người dùng thấy phản hồi tức thì
        setCurrentItinerary(optimisticItinerary);

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
            itinerary: optimisticItinerary,
          },
        ]);
        setIsPlanning(true);

        try {
          if (activeTripId) {
            const serverRes = await chatService.editItinerary(activeTripId, trimmed);
            if (serverRes && (serverRes.itinerary || serverRes.status === "EDITED")) {
              const normalized = normalizeItineraryData(
                serverRes.itinerary || serverRes,
                optimisticItinerary.destination || optimisticItinerary.destination_city || "chuyến đi",
                optimisticItinerary.duration_days || 3,
                activeTripId
              );
              if (normalized) {
                setCurrentItinerary(normalized);
                const finalMsg = serverRes.message || optimisticSummary;
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
            }
          }
        } catch (serverErr) {
          console.warn("Backend edit failed, maintaining optimistic UI:", serverErr);
        } finally {
          setIsPlanning(false);
        }

        // Fallback optimistic UI nếu backend trả về lỗi hoặc timeout
        setMessages((prev) =>
          prev.map((m) =>
            m.id === editAssistantMsgId
              ? {
                  ...m,
                  content: optimisticSummary,
                  status: "success",
                  itinerary: optimisticItinerary,
                }
              : m
          )
        );
        return optimisticSummary;
      }

      // Trường hợp 2: Có trip_id trong cơ sở dữ liệu nhưng chưa tải lịch trình lên client
      if (!activeItin && activeTripId && isEditRequest) {
        const editAssistantMsgId = `assistant-${Date.now()}`;
        setMessages((prev) => [
          ...prev,
          userMessage,
          {
            id: editAssistantMsgId,
            role: "assistant",
            content: "✨ Đang cập nhật lịch trình theo yêu cầu của bạn...",
            timestamp: new Date(),
            status: "sending",
          },
        ]);
        setIsPlanning(true);
        try {
          const serverRes = await chatService.editItinerary(activeTripId, trimmed);
          if (serverRes && (serverRes.itinerary || serverRes.status === "EDITED")) {
            const normalized = normalizeItineraryData(
              serverRes.itinerary || serverRes,
              "chuyến đi",
              3,
              activeTripId
            );
            if (normalized) {
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
          }
        } catch (err) {
          console.warn("Edit trip error:", err);
        } finally {
          setIsPlanning(false);
        }
      }

      // Trường hợp 3: Chưa tạo lịch trình nhưng người dùng đã có điểm đến và yêu cầu chỉnh thời gian / bắt đầu
      if (!activeItin && !activeTripId && hasPendingProposal && isEditRequest) {
        setMessages((prev) => [...prev, userMessage]);
        return await generateFromProposal(trimmed);
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
            },
            onDone: (data: any) => {
              if (data.conversation_id) {
                setConversationId(data.conversation_id);
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
