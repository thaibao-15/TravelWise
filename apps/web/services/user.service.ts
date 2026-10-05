import { apiFetch } from "@/services/api";
import { UpdateUserRequest, User, UserConversation } from "@/types/auth";
import { AuthService } from "@/services/auth.service";

export class UserService {
  /**
   * Lấy thông tin mới nhất của người dùng hiện tại
   */
  static async getProfile(): Promise<User> {
    return AuthService.getMe();
  }

  /**
   * Cập nhật thông tin profile (họ tên, ảnh đại diện)
   */
  static async updateProfile(
    userId: number,
    data: UpdateUserRequest
  ): Promise<User> {
    const updatedUser = await apiFetch<User>(`/api/v1/users/${userId}`, {
      method: "PATCH",
      body: JSON.stringify(data),
    });
    AuthService.setCachedUser(updatedUser);
    return updatedUser;
  }

  /**
   * Lấy danh sách các cuộc trò chuyện AI của người dùng
   */
  static async getConversations(): Promise<UserConversation[]> {
    return apiFetch<UserConversation[]>("/api/v1/conversations/", {
      method: "GET",
    });
  }

  /**
   * Xóa một cuộc trò chuyện AI theo ID
   */
  static async deleteConversation(conversationId: number): Promise<void> {
    await apiFetch<void>(`/api/v1/conversations/${conversationId}`, {
      method: "DELETE",
    });
  }
}
