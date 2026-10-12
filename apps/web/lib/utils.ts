/**
 * Utility function to combine class names
 */
export function cn(...classes: (string | boolean | undefined | null)[]): string {
  return classes.filter(Boolean).join(" ");
}

/**
 * Format timestamp into HH:MM or relative string
 */
export function formatTime(date: Date): string {
  if (!date) return "";
  const d = new Date(date);
  return d.toLocaleTimeString("vi-VN", {
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * Kiểm tra xem một chuỗi / câu lệnh có ý định yêu cầu tạo / lên lịch trình du lịch hay không.
 * Ví dụ: "Hãy tạo lịch trình cho tôi", "Tạo lịch trình", "Lên kế hoạch du lịch", "Thiết kế tour", etc.
 */
export function isCreateItineraryCommand(text: string): boolean {
  if (!text || typeof text !== "string") return false;

  const clean = text
    .toLowerCase()
    .normalize("NFC")
    .replace(/[.,?!:;~^`'"()[\]{}]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (!clean) return false;

  // Chuỗi không dấu để hỗ trợ người dùng gõ tiếng Việt không dấu (VD: "hay tao lich trinh cho toi")
  const noAccent = clean
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "d");

  // 1. Nhóm từ khóa hành động: tạo, lên, lập, thiết kế, xây dựng, gợi ý, chuẩn bị, làm, viết, sắp xếp, cho mình, cho tôi...
  const hasActionVerb =
    /(?:hãy\s+)?(?:tạo|lên|lập|thiết\s*kế|xây\s*dựng|gợi\s*ý|chuẩn\s*bị|làm|viết|sắp\s*xếp|cho\s*(?:mình|tôi|em|anh|chị))/i.test(clean) ||
    /(?:hay\s+)?(?:tao|len|lap|thiet\s*ke|xay\s*dung|goi\s*y|chuan\s*bi|lam|viet|sap\s*xep|cho\s*(?:minh|toi|em|anh|chi))/i.test(noAccent);

  // 2. Nhóm từ khóa mục tiêu: lịch trình, kế hoạch, lộ trình, tour, chuyến đi...
  const hasTargetNoun =
    /(?:lịch\s*trình|kế\s*hoạch|lộ\s*trình|tour|chuyến\s*đi)/i.test(clean) ||
    /(?:lich\s*trinh|ke\s*hoach|lo\s*trinh|tour|chuyen\s*di)/i.test(noAccent);

  // Phối hợp hành động + mục tiêu (VD: "hãy tạo lịch trình cho tôi", "tạo giúp tôi một lịch trình", "lên kế hoạch", "cho mình lịch trình")
  if (hasActionVerb && hasTargetNoun) {
    return true;
  }

  // 3. Các cụm từ trực tiếp thông dụng
  if (/(?:tạo|lên|lập)\s*lịch\b/i.test(clean) || /(?:tao|len|lap)\s*lich\b/i.test(noAccent)) {
    return true;
  }

  // 4. Các câu lệnh tiếng Anh
  if (/(?:create|make|build|generate|plan)\s+(?:an?\s+)?(?:itinerary|trip|travel\s*plan)/i.test(clean)) {
    return true;
  }

  return false;
}
