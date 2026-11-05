import { apiFetch, ApiError } from "@/services/api";
import {
  LiveKitStatusResponse,
  LiveKitTokenRequest,
  LiveKitTokenResponse,
} from "@/types/livekit";

export const livekitService = {
  /**
   * Kiểm tra trạng thái sẵn sàng kết nối LiveKit trên backend FastAPI
   */
  async getStatus(): Promise<LiveKitStatusResponse> {
    return await apiFetch<LiveKitStatusResponse>("/api/v1/livekit/status");
  },

  /**
   * Yêu cầu backend cấp JWT Token để kết nối vào phòng WebRTC LiveKit
   */
  async getRoomToken(
    conversationId?: number | null,
    roomName?: string | null
  ): Promise<LiveKitTokenResponse> {
    const payload: LiveKitTokenRequest = {
      conversation_id: conversationId || undefined,
      room_name: roomName || undefined,
    };

    try {
      return await apiFetch<LiveKitTokenResponse>("/api/v1/livekit/token", {
        method: "POST",
        body: JSON.stringify(payload),
      });
    } catch (err) {
      if (err instanceof ApiError) {
        if (err.status === 401) {
          throw new ApiError(
            "Bạn chưa đăng nhập hoặc phiên đăng nhập đã hết hạn. Vui lòng đăng nhập tài khoản để sử dụng LiveKit Voice.",
            401
          );
        }
        if (err.status === 503) {
          throw new ApiError(
            "Máy chủ chưa cấu hình đầy đủ LiveKit Cloud. Vui lòng kiểm tra lại thiết lập backend.",
            503
          );
        }
        if (err.status === 403) {
          throw new ApiError(
            "Bạn không có quyền truy cập vào phiên hội thoại này.",
            403
          );
        }
      }
      throw err;
    }
  },
};
