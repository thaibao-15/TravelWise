"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import {
  ChatMessage,
  ItineraryProposalData,
  GeneratedItineraryData,
} from "@/types/chat";
import { chatService } from "@/services/chat.service";
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

/**
 * Nhận diện chính xác câu lệnh chỉnh sửa lịch trình hiện có.
 * Phân lớp lọc chặt chẽ: Loại trừ thắc mắc/FAQ -> Nhận diện các biến thể chỉnh sửa đa dạng.
 */
function isItineraryEditIntent(prompt: string): boolean {
  const lower = cleanPromptText(prompt);
  if (!lower) return false;

  // =========================================================================
  // BƯỚC 1: BỘ LỌC PHỦ ĐỊNH (Tuyệt đối không phải lệnh sửa lịch trình)
  // =========================================================================

  // 1a. Câu hỏi về danh tính, vai trò bot, chào hỏi, cảm ơn đơn thuần
  if (
    /^(xin\s*chào|chào\s*bạn|hi|hello|cảm\s*ơn|thanks|thank\s*you|tạm\s*biệt)\b/i.test(lower) ||
    /hướng\s*dẫn\s*viên|bạn\s*là\s*ai|giới\s*thiệu\s*bản\s*thân|bạn\s*có\s*thể\s*làm\s*gì|bạn\s*tên\s*gì|vai\s*trò\s*của\s*bạn/i.test(lower)
  ) {
    return false;
  }

  // 1b. Yêu cầu tạo mới từ đầu / làm lại hoàn toàn (thuộc luồng isRegenerateIntent)
  if (
    /(?:tạo\s*lại|làm\s*lại|lên\s*lại|thiết\s*kế\s*lại|lập\s*lại|tạo\s*mới|lên\s*mới|xóa\s*hết\s*làm\s*lại|chuyến\s*đi\s*mới|reset)/i.test(lower) &&
    !/(?:thêm|bớt|sửa|chỉnh|ngày\s*\d)/i.test(lower)
  ) {
    return false;
  }

  // 1c. Các câu hỏi tham khảo FAQ du lịch, khoảng cách, review, mẹo, thời tiết
  const isGeneralInquiry =
    /(?:mấy\s*giờ\s*(?:mở|đóng)|(?:mở|đóng)\s*cửa\s*lúc\s*mấy\s*giờ|vé\s*bao\s*nhiêu|giá\s*vé|bao\s*nhiêu\s*tiền|mất\s*bao\s*lâu|cách\s*bao\s*xa|khoảng\s*cách|đi\s*hết\s*mấy\s*tiếng)\b/i.test(lower) ||
    /(?:thời\s*tiết|có\s*mưa\s*không|mùa\s*này|mang\s*theo\s*gì|mặc\s*đồ\s*gì|trang\s*phục|kinh\s*nghiệm\s*đi|lưu\s*ý\s*gì)\b/i.test(lower) ||
    /(?:có\s*ngon\s*không|có\s*đẹp\s*không|review|đánh\s*giá|nên\s*đi\s*không|có\s*gì\s*(?:chơi|ngon|hot|đặc\s*sắc))\b/i.test(lower) ||
    /(?:nên\s*đi\s*[\w\s]+\s*hay\s*[\w\s]+|so\s*sánh|cái\s*nào\s*tốt\s*hơn)\b/i.test(lower);

  // Nếu là câu hỏi FAQ thuần túy và không kèm động từ hành động sửa đổi
  const hasStrongEditVerb = /(?:thay|đổi|thêm|bớt|bỏ|xoá|xóa|dời|chuyển|sửa|chỉnh|cập\s*nhật|giãn|tối\s*ưu)/i.test(lower);
  if (isGeneralInquiry && !hasStrongEditVerb) {
    return false;
  }

  // =========================================================================
  // BƯỚC 2: BỘ LỌC KHẲNG ĐỊNH (Nhận diện các trường hợp chỉnh sửa)
  // =========================================================================

  // 2a. Thay đổi giờ giấc / thời gian
  const hasTimeAdjustment =
    /(?:bắt\s*đầu|khởi\s*hành|xuất\s*phát|dời|lùi|chuyển|đổi|sang|kéo\s*dài|rút\s*ngắn)\s*(?:lúc|sang|vào|từ)?\s*\d{1,2}(?:h|:|\s*giờ)/i.test(lower) ||
    /(?:sớm\s*hơn|muộn\s*hơn|trễ\s*hơn|nhanh\s*hơn|chậm\s*hơn|ngủ\s*nướng)\b/i.test(lower) ||
    /(?:cho|để)\s+(?:lịch|chuyến\s*đi)\s+(?:bắt\s*đầu|khởi\s*hành)\s+lúc/i.test(lower) ||
    /(?:tăng|thêm|bớt|giảm)\s*\d+\s*(?:tiếng|giờ|phút)/i.test(lower);

  // 2b. Thêm / Bớt / Xóa / Bỏ qua hoạt động hoặc địa điểm cụ thể
  const hasActionWithTarget =
    /(?:thêm|bổ\s*sung|bớt|bỏ|xoá|xóa|cắt\s*bớt|ghé\s*thêm|chèn\s*thêm)\s+(?:vào\s+ngày\s*\d|khỏi\s+lịch|ngày\s*\d|hoạt\s*động|địa\s*điểm|quán|biển|cafe|cà\s*phê|khách\s*sạn|resort|chợ|chùa|bảo\s*tàng|điểm)/i.test(lower) ||
    /(?:bỏ|xóa|xoá|bỏ\s*qua|không\s*đi|ngưng\s*đi)\s+[\w\s]+(?:đi|khỏi\s*lịch|ra|nữa)/i.test(lower) ||
    /(?:thêm|ghé\s*thêm|chèn)\s+[\w\s]+(?:vào\s*ngày|vào\s*buổi|vào\s*lịch|cho\s*mình)/i.test(lower);

  // 2c. Thay thế / Hoán đổi (Thay A bằng B, đổi thứ tự, đảo ngày)
  const hasSwapOrReplace =
    /(?:thay|đổi|chuyển)\s+[\w\s]+(?:bằng|thành|sang)\s+[\w\s]+/i.test(lower) ||
    /(?:đảo|hoán\s*đổi|đổi\s*thứ\s*tự)\s+(?:ngày|buổi|hoạt\s*động|địa\s*điểm|\d)/i.test(lower) ||
    /ngày\s*\d\s*(?:đổi|hoán\s*đổi|đảo)\s*(?:với|cho)\s*ngày\s*\d/i.test(lower);

  // 2d. Chỉnh sửa theo ngày hoặc theo buổi cụ thể
  const hasDayOrSessionEdit =
    /(?:ngày\s*\d|hôm\s*\d)\s*(?:thay|đổi|sửa|chỉnh|thêm|bớt|bỏ|xoá|xóa|dời|chuyển|ưu\s*tiên|tối\s*ưu)/i.test(lower) ||
    /(?:sửa|đổi|chỉnh|cập\s*nhật|update)\s+(?:ngày\s*\d|hôm\s*\d)/i.test(lower) ||
    /(?:buổi\s*)?(?:sáng|trưa|chiều|tối|đêm)\s*(?:ngày\s*\d|hôm\s*\d)?\s*(?:đổi|thay|thêm|bớt|bỏ|chuyển|cho\s*đi|ghé)/i.test(lower);

  // 2e. Điều chỉnh nhịp độ, phong cách, đối tượng, phương tiện
  const hasPacingOrStyleEdit =
    /(?:dày\s*đặc|kín\s*quá|gấp\s*quá|nhiều\s*điểm\s*quá|mệt\s*quá)\s*(?:giãn|bớt|chỉnh|sửa|giảm)/i.test(lower) ||
    /(?:giãn\s*(?:lịch|thời\s*gian|ra)|thong\s*thả\s*hơn|nhẹ\s*nhàng\s*hơn|nghỉ\s*ngơi\s*nhiều\s*hơn)/i.test(lower) ||
    /(?:đổi|chuyển|chỉnh|sửa)\s*(?:sang|theo)?\s*(?:phong\s*cách\s*)?(?:nghỉ\s*dưỡng|chill|tiết\s*kiệm|sang\s*chảnh|trải\s*nghiệm)/i.test(lower) ||
    /(?:đi\s*cùng|có)\s*(?:người\s*già|người\s*lớn\s*tuổi|trẻ\s*(?:em|nhỏ|con))\s*(?:nên|sửa|chỉnh|giảm)/i.test(lower) ||
    /(?:đổi\s*phương\s*tiện|thuê\s*xe\s*máy|đi\s*taxi|đi\s*grab)/i.test(lower);

  // 2f. Yêu cầu sửa lịch trình tổng quát
  const hasGeneralEdit =
    /(?:sửa|chỉnh|chỉnh\s*sửa|thay\s*đổi|cập\s*nhật|điều\s*chỉnh|sắp\s*xếp\s*lại|tối\s*ưu\s*lại|update|edit|fix)\s*(?:lại\s*)?(?:lịch|lịch\s*trình|chuyến\s*đi|kế\s*hoạch)/i.test(lower) ||
    /(?:lịch|lịch\s*trình|chuyến\s*đi|kế\s*hoạch)\s*(?:này\s*)?(?:cần\s*)?(?:sửa|chỉnh|thay\s*đổi|cập\s*nhật|điều\s*chỉnh|update|edit)/i.test(lower) ||
    /(?:sửa|chỉnh|thay\s*đổi|cập\s*nhật|điều\s*chỉnh|update|edit|fix)\s*(?:giúp|hộ|cho|giùm)\s*mình/i.test(lower) ||
    /(?:sửa|chỉnh|chỉnh\s*sửa|update|edit)\s+(?:lại|giúp|cho|hộ|giùm|tí|chút|xíu)/i.test(lower);

  return Boolean(
    hasTimeAdjustment ||
    hasActionWithTarget ||
    hasSwapOrReplace ||
    hasDayOrSessionEdit ||
    hasPacingOrStyleEdit ||
    hasGeneralEdit
  );
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
      const isGenericEdit = /^(?:sửa lại|chỉnh sửa|sửa|thay đổi|cập nhật|điều chỉnh)(?:\s+lại)?(?:\s+(?:lịch|lịch trình|chuyến đi))?(?:\s+(?:này|cho mình|giúp mình))?$/i.test(lower.trim());
      if (isGenericEdit) {
        summary = `Dạ bạn muốn chỉnh sửa phần nào trong lịch trình hiện tại? Bạn có thể yêu cầu cụ thể như:\n• "Dời giờ bắt đầu ngày 1 sang 9h sáng"\n• "Thêm quán cafe view đẹp ngắm hoàng hôn vào ngày 2"\n• "Bỏ chợ đêm và thay bằng hoạt động khác"\nHoặc nếu muốn đổi số ngày hay đổi thành phố khác, bạn hãy nhắn "tạo lại lịch trình" nhé! 😊`;
        return {
          itinerary: current,
          summary,
        };
      }
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
          let serverRes: any = null;
          if (activeTripId) {
            serverRes = await chatService.editItinerary(activeTripId, trimmed);
          } else {
            // Nếu chưa có activeTripId thì gọi generateItineraryDirect kèm user_prompt điều chỉnh
            serverRes = await chatService.generateItineraryDirect({
              context: planningContextRef.current,
              conversation_id: conversationId,
              save_to_db: true,
              user_prompt: trimmed,
            });
          }

          if (serverRes && (serverRes.itinerary || serverRes.days || serverRes.status === "EDITED" || serverRes.status === "GENERATED")) {
            const resTripId = serverRes.trip_id || activeTripId;
            const normalized = normalizeItineraryData(
              serverRes.itinerary || serverRes,
              optimisticItinerary.destination || optimisticItinerary.destination_city || "chuyến đi",
              optimisticItinerary.duration_days || 3,
              resTripId
            );
            if (normalized && normalized.days && normalized.days.length > 0) {
              setCurrentItinerary(normalized);
              if (resTripId) setCurrentTripId(resTripId);
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

      // Trường hợp 4: Chưa tạo lịch trình nào nhưng người dùng yêu cầu sửa lịch trình
      if (!activeItin && !activeTripId && !hasPendingProposal && isEditRequest) {
        const noItinMsg = "Hiện tại bạn chưa tạo lịch trình nào để chỉnh sửa. Bạn có muốn mình thiết kế lịch trình mới ngay bây giờ không? Hãy chia sẻ điểm đến và số ngày dự kiến nhé! 🗺️✨";
        setMessages((prev) => [
          ...prev,
          userMessage,
          {
            id: `assistant-${Date.now()}`,
            role: "assistant",
            content: noItinMsg,
            timestamp: new Date(),
            status: "success",
          },
        ]);
        return noItinMsg;
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
